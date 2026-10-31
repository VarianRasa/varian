import 'dart:convert';
import 'dart:typed_data';

import 'notes_local_store.dart';

abstract interface class NotesSyncTransport {
  Future<bool> canReplay(String accountId, Map<String, dynamic> operation);
  Future<void> replay(String accountId, Map<String, dynamic> operation);
}

class NotesSyncRepository {
  NotesSyncRepository({
    required this._store,
    required this._transport,
    required this._keyForAccount,
    required this._currentAccountId,
    this.maxOperationsPerRun = 100,
  });

  final NotesLocalStore _store;
  final NotesSyncTransport _transport;
  final Future<Uint8List?> Function(String accountId) _keyForAccount;
  final Future<String?> Function() _currentAccountId;
  final int maxOperationsPerRun;
  final Map<String, Future<int>> _running = {};
  final Set<(String, String)> _pausedProjects = {};
  int _generation = 0;

  Future<void> enqueue({
    required String accountId,
    required Map<String, dynamic> operation,
    required Uint8List key,
  }) async {
    final noteId = operation['noteId'];
    final operationId = operation['opId'];
    if (accountId.isEmpty ||
        accountId.length > 256 ||
        noteId is! String ||
        noteId.isEmpty ||
        noteId.length > 256 ||
        operationId is! String ||
        operationId.isEmpty ||
        operationId.length > 256 ||
        key.length != 32) {
      throw ArgumentError('Invalid Notes outbox entry.');
    }
    final payload = jsonEncode(operation);
    if (utf8.encode(payload).length > 256 * 1024) {
      throw ArgumentError('Notes outbox entry exceeds the size limit.');
    }
    await _store.enqueue(
      accountId: accountId,
      operationId: operationId,
      payload: payload,
      key: key,
    );
    if (!_store.isEnabled) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
  }

  Future<void> saveVectorCheckpoint({
    required String accountId,
    required String noteId,
    required Map<String, dynamic> versionVector,
    required Uint8List key,
  }) async {
    await _store.saveCheckpoint(
      accountId: accountId,
      noteId: noteId,
      versionVectorJson: jsonEncode(versionVector),
      key: key,
    );
    if (!_store.isEnabled) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
  }

  Future<Map<String, dynamic>?> loadVectorCheckpoint({
    required String accountId,
    required String noteId,
    required Uint8List key,
  }) async {
    final encoded = await _store.readCheckpoint(
      accountId: accountId,
      noteId: noteId,
      key: key,
    );
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> pendingNoteIds(String accountId) async {
    final ids = await _store.pendingOutboxOperationIds(
      accountId: accountId,
      limit: 10000,
    );
    return ids
        .map((id) => id.split(':').first)
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> pausedNoteIds(String accountId) async {
    final key = await _keyForAccount(accountId);
    if (key == null || key.length != 32) return const {};
    final entries = await _store.readOutbox(
      accountId: accountId,
      key: key,
      limit: 10000,
    );
    final noteIds = <String>{};
    for (final payload in entries) {
      try {
        final value = jsonDecode(payload);
        if (value is! Map) continue;
        final entry = Map<String, dynamic>.from(value);
        final projectId = entry['projectId'];
        final noteId = entry['noteId'];
        if (projectId is String &&
            noteId is String &&
            _pausedProjects.contains((accountId, projectId))) {
          noteIds.add(noteId);
        }
      } catch (_) {
        // Keep malformed ciphertext-derived entries queued but do not label them.
      }
    }
    return noteIds;
  }

  void pauseForRevokedMembership(String accountId, String projectId) {
    _pausedProjects.add((accountId, projectId));
  }

  void accountChanged() {
    _generation++;
  }

  Future<int> resumeAfterAuthentication(String accountId) {
    _generation++;
    _pausedProjects.removeWhere((entry) => entry.$1 == accountId);
    return syncAccount(accountId);
  }

  Future<int> syncAccount(String accountId) {
    final existing = _running[accountId];
    if (existing != null) return existing;
    final generation = _generation;
    final run = _sync(accountId, generation);
    _running[accountId] = run;
    return run.whenComplete(() {
      if (identical(_running[accountId], run)) _running.remove(accountId);
    });
  }

  Future<int> _sync(String accountId, int generation) async {
    if (accountId.isEmpty || accountId.length > 256) return 0;
    final key = await _keyForAccount(accountId);
    if (key == null ||
        key.length != 32 ||
        !(await _isCurrent(accountId, generation))) {
      return 0;
    }
    final entries = await _store.readOutbox(
      accountId: accountId,
      key: key,
      limit: maxOperationsPerRun,
    );
    var replayed = 0;
    for (final payload in entries) {
      if (!(await _isCurrent(accountId, generation))) break;
      String? projectId;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final operation = Map<String, dynamic>.from(decoded);
        final operationId = operation['opId'];
        projectId = operation['projectId'] is String
            ? operation['projectId'] as String
            : null;
        if (operationId is! String || operationId.isEmpty) continue;
        if (projectId is String &&
            _pausedProjects.contains((accountId, projectId))) {
          continue;
        }
        if (!await _transport.canReplay(accountId, operation) ||
            !(await _isCurrent(accountId, generation))) {
          if (projectId is String) {
            _pausedProjects.add((accountId, projectId));
          }
          continue;
        }
        await _transport.replay(accountId, operation);
        if (!(await _isCurrent(accountId, generation))) break;
        await _store.removeOutbox(
          accountId: accountId,
          operationId: operationId,
        );
        replayed++;
      } catch (_) {
        if (projectId != null) _pausedProjects.add((accountId, projectId));
        // Keep failed or malformed encrypted entries for explicit recovery.
      }
    }
    return replayed;
  }

  Future<bool> _isCurrent(String accountId, int generation) async =>
      generation == _generation && await _currentAccountId() == accountId;
}
