import 'dart:async';

import 'package:flutter/foundation.dart';

import 'export_presets.dart';

enum ExportQueueJobStatus { queued, running, completed, failed, canceled }

typedef ExportQueueTask = Future<ExportPresetResult?> Function();

class ExportQueueJob {
  final String id;
  final ExportPreset preset;
  final ExportQueueJobStatus status;
  final ExportPresetResult? result;
  final Object? error;

  const ExportQueueJob({
    required this.id,
    required this.preset,
    required this.status,
    this.result,
    this.error,
  });

  bool get isTerminal => switch (status) {
    ExportQueueJobStatus.completed ||
    ExportQueueJobStatus.failed ||
    ExportQueueJobStatus.canceled => true,
    ExportQueueJobStatus.queued || ExportQueueJobStatus.running => false,
  };
}

class ExportQueue extends ChangeNotifier {
  final Map<String, ExportQueueJob> _jobs = {};
  final Map<String, ExportQueueTask> _tasks = {};
  final List<String> _pendingIds = [];
  final Set<String> _cancelRequested = {};
  final List<Completer<void>> _idleWaiters = [];
  final Map<String, List<Completer<ExportQueueJob>>> _jobWaiters = {};
  int _sequence = 0;
  bool _draining = false;
  bool _disposed = false;

  List<ExportQueueJob> get jobs => List.unmodifiable(_jobs.values);

  List<ExportQueueJob> get pendingJobs => _pendingIds
      .map((id) => _jobs[id])
      .whereType<ExportQueueJob>()
      .toList(growable: false);

  ExportQueueJob? operator [](String id) => _jobs[id];

  String enqueue({
    required ExportPreset preset,
    required ExportQueueTask task,
    String? id,
  }) {
    _ensureActive();
    final jobId = _uniqueId(id ?? 'export-${++_sequence}');
    _tasks[jobId] = task;
    _jobs[jobId] = ExportQueueJob(
      id: jobId,
      preset: preset,
      status: ExportQueueJobStatus.queued,
    );
    _pendingIds.add(jobId);
    _notify();
    unawaited(_drain());
    return jobId;
  }

  bool cancel(String id) {
    _ensureActive();
    final job = _jobs[id];
    if (job == null || job.isTerminal) return false;
    _cancelRequested.add(id);
    if (job.status == ExportQueueJobStatus.queued) {
      _pendingIds.remove(id);
      _jobs[id] = ExportQueueJob(
        id: job.id,
        preset: job.preset,
        status: ExportQueueJobStatus.canceled,
      );
      _tasks.remove(id);
      _notify();
      _completeIdleWaitersIfNeeded();
    }
    return true;
  }

  bool retry(String id) {
    _ensureActive();
    final job = _jobs[id];
    final task = _tasks[id];
    if (job == null ||
        task == null ||
        (job.status != ExportQueueJobStatus.failed &&
            job.status != ExportQueueJobStatus.canceled)) {
      return false;
    }
    _cancelRequested.remove(id);
    _jobs[id] = ExportQueueJob(
      id: job.id,
      preset: job.preset,
      status: ExportQueueJobStatus.queued,
    );
    _pendingIds.add(id);
    _notify();
    unawaited(_drain());
    return true;
  }

  void clearTerminal() {
    _ensureActive();
    final ids = _jobs.values
        .where((job) => job.isTerminal)
        .map((job) => job.id)
        .toList(growable: false);
    for (final id in ids) {
      _jobs.remove(id);
      _tasks.remove(id);
      _cancelRequested.remove(id);
    }
    if (ids.isNotEmpty) _notify();
  }

  Future<void> waitForIdle() {
    if (_isIdle) return Future<void>.value();
    final completer = Completer<void>();
    _idleWaiters.add(completer);
    return completer.future;
  }

  Future<ExportQueueJob> waitForJob(String id) {
    _ensureActive();
    final job = _jobs[id];
    if (job == null) {
      return Future<ExportQueueJob>.error(
        StateError('Unknown export queue job: $id'),
      );
    }
    if (job.isTerminal) return Future<ExportQueueJob>.value(job);

    final completer = Completer<ExportQueueJob>();
    (_jobWaiters[id] ??= <Completer<ExportQueueJob>>[]).add(completer);
    final latest = _jobs[id];
    if (latest == null || latest.isTerminal) _completeJobWaiters();
    return completer.future;
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_pendingIds.isNotEmpty && !_disposed) {
        final id = _pendingIds.removeAt(0);
        final job = _jobs[id];
        final task = _tasks[id];
        if (job == null ||
            task == null ||
            job.status != ExportQueueJobStatus.queued ||
            _cancelRequested.contains(id)) {
          continue;
        }
        _jobs[id] = ExportQueueJob(
          id: job.id,
          preset: job.preset,
          status: ExportQueueJobStatus.running,
        );
        _notify();
        try {
          final result = await task();
          final canceled = _cancelRequested.contains(id);
          _jobs[id] = ExportQueueJob(
            id: job.id,
            preset: job.preset,
            status: canceled
                ? ExportQueueJobStatus.canceled
                : result == null
                ? ExportQueueJobStatus.failed
                : ExportQueueJobStatus.completed,
            result: canceled ? null : result,
            error: canceled || result != null
                ? null
                : StateError('Export task returned no result.'),
          );
        } catch (error) {
          _jobs[id] = ExportQueueJob(
            id: job.id,
            preset: job.preset,
            status: _cancelRequested.contains(id)
                ? ExportQueueJobStatus.canceled
                : ExportQueueJobStatus.failed,
            error: _cancelRequested.contains(id) ? null : error,
          );
        } finally {
          _cancelRequested.remove(id);
          _notify();
        }
      }
    } finally {
      _draining = false;
      _completeIdleWaitersIfNeeded();
      if (_pendingIds.isNotEmpty && !_disposed) unawaited(_drain());
    }
  }

  bool get _isIdle => !_draining && _pendingIds.isEmpty;

  void _completeIdleWaitersIfNeeded() {
    if (!_isIdle) return;
    final waiters = List<Completer<void>>.from(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  String _uniqueId(String requested) {
    var candidate = requested.trim().isEmpty
        ? 'export-${++_sequence}'
        : requested.trim();
    var suffix = 2;
    while (_jobs.containsKey(candidate)) {
      candidate = '$requested-$suffix';
      suffix++;
    }
    return candidate;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ExportQueue has been disposed.');
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    _completeJobWaiters();
  }

  void _completeJobWaiters() {
    final completedIds = <String>[];
    for (final entry in _jobWaiters.entries) {
      final job = _jobs[entry.key];
      if (job != null && !job.isTerminal) continue;
      completedIds.add(entry.key);
      for (final waiter in entry.value) {
        if (waiter.isCompleted) continue;
        if (job == null) {
          waiter.completeError(
            StateError('Export queue job was removed: ${entry.key}'),
          );
        } else {
          waiter.complete(job);
        }
      }
    }
    for (final id in completedIds) {
      _jobWaiters.remove(id);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingIds.clear();
    _cancelRequested.addAll(_jobs.keys);
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
    for (final entry in _jobWaiters.entries) {
      for (final waiter in entry.value) {
        if (!waiter.isCompleted) {
          waiter.completeError(StateError('ExportQueue has been disposed.'));
        }
      }
    }
    _jobWaiters.clear();
    super.dispose();
  }
}
