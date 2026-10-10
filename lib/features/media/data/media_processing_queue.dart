import 'dart:async';
import 'dart:collection';

import 'package:varian/domain/models/media_timeline.dart';

class MediaProcessingException implements Exception {
  final String message;

  const MediaProcessingException(this.message);

  @override
  String toString() => message;
}

class MediaProcessingCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const MediaProcessingException('Media processing was cancelled.');
    }
  }
}

class MediaProcessingRequest {
  final String id;
  final String sourceKey;
  final String inputChecksum;
  final List<MediaArtifactKind> artifactKinds;
  final MediaStoragePolicy storagePolicy;
  final int maxAttempts;
  final String? expectedOutputChecksum;
  final Map<String, String> metadata;

  const MediaProcessingRequest({
    required this.id,
    required this.sourceKey,
    required this.inputChecksum,
    required this.artifactKinds,
    this.storagePolicy = MediaStoragePolicy.cache,
    this.maxAttempts = 1,
    this.expectedOutputChecksum,
    this.metadata = const {},
  }) : assert(maxAttempts > 0);

  String get dedupeKey => [
    sourceKey,
    inputChecksum,
    storagePolicy.name,
    ...(artifactKinds.map((kind) => kind.name).toList()..sort()),
  ].join('|');

  bool get isCheckpointable {
    final normalizedSource = sourceKey.trim().toLowerCase();
    return normalizedSource.isNotEmpty &&
        !normalizedSource.startsWith('data:') &&
        !normalizedSource.startsWith('blob:') &&
        !normalizedSource.startsWith('memory:');
  }

  Map<String, dynamic> toJson({bool forCheckpoint = false}) {
    final persistedMetadata = Map<String, String>.from(metadata);
    if (forCheckpoint) persistedMetadata.remove('sourceBytesBase64');
    return {
      'id': id,
      'sourceKey': sourceKey,
      'inputChecksum': inputChecksum,
      'artifactKinds': artifactKinds.map((kind) => kind.name).toList(),
      'storagePolicy': storagePolicy.name,
      'maxAttempts': maxAttempts,
      'expectedOutputChecksum': expectedOutputChecksum,
      'metadata': persistedMetadata,
    };
  }

  Map<String, dynamic> toCheckpointJson() => toJson(forCheckpoint: true);

  static MediaProcessingRequest? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final sourceKey = json['sourceKey'] as String?;
    final inputChecksum = json['inputChecksum'] as String?;
    final rawKinds = json['artifactKinds'];
    if (id == null ||
        id.trim().isEmpty ||
        sourceKey == null ||
        sourceKey.trim().isEmpty ||
        inputChecksum == null ||
        inputChecksum.trim().isEmpty ||
        rawKinds is! List) {
      return null;
    }
    final kinds = [
      for (final rawKind in rawKinds)
        for (final kind in MediaArtifactKind.values)
          if (rawKind == kind.name) kind,
    ];
    if (kinds.isEmpty) return null;

    final rawMetadata = json['metadata'];
    final metadata = <String, String>{};
    if (rawMetadata is Map) {
      for (final entry in rawMetadata.entries) {
        if (entry.key is String && entry.value is String) {
          metadata[entry.key as String] = entry.value as String;
        }
      }
    }
    final storageName = json['storagePolicy'] as String?;
    final storagePolicy = MediaStoragePolicy.values.firstWhere(
      (value) => value.name == storageName,
      orElse: () => MediaStoragePolicy.cache,
    );
    final maxAttempts = (json['maxAttempts'] as num?)?.toInt() ?? 1;
    return MediaProcessingRequest(
      id: id,
      sourceKey: sourceKey,
      inputChecksum: inputChecksum,
      artifactKinds: List.unmodifiable(kinds),
      storagePolicy: storagePolicy,
      maxAttempts: maxAttempts < 1 ? 1 : maxAttempts,
      expectedOutputChecksum: json['expectedOutputChecksum'] as String?,
      metadata: Map.unmodifiable(metadata),
    );
  }
}

abstract interface class MediaProcessingCheckpointStore {
  Future<List<MediaProcessingRequest>> load();

  Future<void> upsert(MediaProcessingRequest request);

  Future<void> remove(String requestId);
}

class MediaProcessingOutput {
  final MediaArtifactManifest artifacts;
  final String checksum;
  final MediaTimeline? timeline;

  const MediaProcessingOutput({
    required this.artifacts,
    required this.checksum,
    this.timeline,
  });
}

typedef MediaProcessingHandler =
    Future<MediaProcessingOutput> Function(
      MediaProcessingRequest request,
      MediaProcessingCancellationToken cancellation,
    );

class MediaProcessingJob {
  final MediaProcessingRequest request;
  final MediaProcessingStatus status;
  final int attempt;
  final MediaProcessingOutput? output;
  final String? error;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const MediaProcessingJob({
    required this.request,
    this.status = MediaProcessingStatus.queued,
    this.attempt = 0,
    this.output,
    this.error,
    this.startedAt,
    this.completedAt,
  });

  MediaProcessingJob copyWith({
    MediaProcessingStatus? status,
    int? attempt,
    Object? output = _sentinel,
    Object? error = _sentinel,
    Object? startedAt = _sentinel,
    Object? completedAt = _sentinel,
  }) => MediaProcessingJob(
    request: request,
    status: status ?? this.status,
    attempt: attempt ?? this.attempt,
    output: output == _sentinel
        ? this.output
        : output as MediaProcessingOutput?,
    error: error == _sentinel ? this.error : error as String?,
    startedAt: startedAt == _sentinel ? this.startedAt : startedAt as DateTime?,
    completedAt: completedAt == _sentinel
        ? this.completedAt
        : completedAt as DateTime?,
  );

  static const Object _sentinel = Object();
}

class MediaProcessingQueue {
  final MediaProcessingHandler handler;
  final MediaProcessingCheckpointStore? checkpointStore;
  final Map<String, MediaProcessingJob> _jobs = {};
  final Queue<String> _pending = Queue<String>();
  final Map<String, MediaProcessingCancellationToken> _tokens = {};
  final StreamController<MediaProcessingJob> _updates =
      StreamController<MediaProcessingJob>.broadcast();
  final List<Completer<void>> _idleWaiters = [];
  bool _draining = false;
  bool _disposed = false;
  bool _restored = false;
  late final Future<void> _restoreFuture;

  MediaProcessingQueue({required this.handler, this.checkpointStore}) {
    _restoreFuture = _restore();
  }

  Stream<MediaProcessingJob> get updates => _updates.stream;

  Iterable<MediaProcessingJob> get jobs => _jobs.values;

  MediaProcessingJob? operator [](String id) => _jobs[id];

  MediaProcessingJob enqueue(MediaProcessingRequest request) {
    _ensureOpen();
    final existingById = _jobs[request.id];
    if (existingById != null) return existingById;
    for (final job in _jobs.values) {
      if (job.request.dedupeKey == request.dedupeKey &&
          job.status != MediaProcessingStatus.cancelled) {
        return job;
      }
    }

    final job = MediaProcessingJob(request: request);
    _jobs[request.id] = job;
    _pending.add(request.id);
    _persist(request);
    _emit(job);
    _scheduleDrain();
    return job;
  }

  MediaProcessingJob? retry(String id) {
    _ensureOpen();
    final current = _jobs[id];
    if (current == null ||
        (current.status != MediaProcessingStatus.failed &&
            current.status != MediaProcessingStatus.cancelled)) {
      return current;
    }
    final next = current.copyWith(
      status: MediaProcessingStatus.queued,
      attempt: 0,
      output: null,
      error: null,
      startedAt: null,
      completedAt: null,
    );
    _jobs[id] = next;
    if (!_pending.contains(id)) _pending.add(id);
    _persist(next.request);
    _emit(next);
    _scheduleDrain();
    return next;
  }

  bool cancel(String id) {
    final current = _jobs[id];
    if (current == null ||
        current.status == MediaProcessingStatus.succeeded ||
        current.status == MediaProcessingStatus.failed ||
        current.status == MediaProcessingStatus.cancelled) {
      return false;
    }
    _tokens[id]?.cancel();
    _pending.remove(id);
    final next = current.copyWith(
      status: MediaProcessingStatus.cancelled,
      error: 'Media processing was cancelled.',
      completedAt: DateTime.now(),
    );
    _jobs[id] = next;
    _removeCheckpoint(id);
    _emit(next);
    _completeIdleWaitersIfIdle();
    return true;
  }

  Future<void> waitForIdle() async {
    await _restoreFuture;
    if (!_draining && _pending.isEmpty) return;
    final completer = Completer<void>();
    _idleWaiters.add(completer);
    await completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _pending.clear();
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
    await _updates.close();
  }

  void _scheduleDrain() {
    if (!_restored || _draining || _disposed) return;
    unawaited(_drain());
  }

  Future<void> _restore() async {
    final store = checkpointStore;
    if (store != null) {
      try {
        final requests = await store.load();
        if (!_disposed) {
          for (final request in requests) {
            if (_jobs.containsKey(request.id) ||
                _jobs.values.any(
                  (job) => job.request.dedupeKey == request.dedupeKey,
                )) {
              continue;
            }
            final job = MediaProcessingJob(request: request);
            _jobs[request.id] = job;
            _pending.add(request.id);
            _emit(job);
          }
        }
      } catch (_) {}
    }
    _restored = true;
    _scheduleDrain();
  }

  void _persist(MediaProcessingRequest request) {
    final store = checkpointStore;
    if (store == null || !request.isCheckpointable) return;
    unawaited(store.upsert(request).catchError((_) {}));
  }

  void _removeCheckpoint(String id) {
    final store = checkpointStore;
    if (store == null) return;
    unawaited(store.remove(id).catchError((_) {}));
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final id = _pending.removeFirst();
        final job = _jobs[id];
        if (job == null || job.status != MediaProcessingStatus.queued) {
          continue;
        }
        await _run(job);
      }
    } finally {
      _draining = false;
      _completeIdleWaitersIfIdle();
      if (_pending.isNotEmpty && !_disposed) _scheduleDrain();
    }
  }

  Future<void> _run(MediaProcessingJob initial) async {
    final token = MediaProcessingCancellationToken();
    _tokens[initial.request.id] = token;
    var job = initial;
    try {
      while (job.attempt < job.request.maxAttempts) {
        token.throwIfCancelled();
        job = job.copyWith(
          status: MediaProcessingStatus.running,
          attempt: job.attempt + 1,
          error: null,
          startedAt: DateTime.now(),
          completedAt: null,
        );
        _jobs[job.request.id] = job;
        _emit(job);
        try {
          final output = await handler(job.request, token);
          token.throwIfCancelled();
          _validateOutput(job.request, output);
          job = job.copyWith(
            status: MediaProcessingStatus.succeeded,
            output: output,
            completedAt: DateTime.now(),
          );
          _jobs[job.request.id] = job;
          _removeCheckpoint(job.request.id);
          _emit(job);
          return;
        } catch (error) {
          if (token.isCancelled ||
              _jobs[job.request.id]?.status ==
                  MediaProcessingStatus.cancelled) {
            return;
          }
          final message = error.toString();
          if (job.attempt >= job.request.maxAttempts) {
            job = job.copyWith(
              status: MediaProcessingStatus.failed,
              error: message,
              completedAt: DateTime.now(),
            );
            _jobs[job.request.id] = job;
            _removeCheckpoint(job.request.id);
            _emit(job);
            return;
          }
          job = job.copyWith(
            status: MediaProcessingStatus.retrying,
            error: message,
          );
          _jobs[job.request.id] = job;
          _emit(job);
        }
      }
    } on MediaProcessingException catch (error) {
      if (_jobs[job.request.id]?.status == MediaProcessingStatus.cancelled) {
        return;
      }
      final failed = job.copyWith(
        status: MediaProcessingStatus.failed,
        error: error.message,
        completedAt: DateTime.now(),
      );
      _jobs[job.request.id] = failed;
      _removeCheckpoint(job.request.id);
      _emit(failed);
    } finally {
      _tokens.remove(initial.request.id);
    }
  }

  void _validateOutput(
    MediaProcessingRequest request,
    MediaProcessingOutput output,
  ) {
    if (output.checksum.trim().isEmpty) {
      throw const MediaProcessingException('Media output checksum is missing.');
    }
    if (request.expectedOutputChecksum != null &&
        request.expectedOutputChecksum != output.checksum) {
      throw const MediaProcessingException('Media output checksum mismatch.');
    }
    for (final kind in request.artifactKinds) {
      final artifact = output.artifacts.find(kind);
      if (artifact == null || !artifact.isAvailable) {
        throw MediaProcessingException(
          'Required media artifact is missing: ${kind.name}.',
        );
      }
      if (artifact.checksum?.trim().isEmpty != false) {
        throw MediaProcessingException(
          'Media artifact checksum is missing: ${kind.name}.',
        );
      }
    }
  }

  void _emit(MediaProcessingJob job) {
    if (!_updates.isClosed) _updates.add(job);
  }

  void _completeIdleWaitersIfIdle() {
    if (_draining || _pending.isNotEmpty) return;
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('Media processing queue is disposed.');
    }
  }
}
