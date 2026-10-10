import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/collaboration/domain/crdt_engine.dart';
import 'local_storage_service.dart';

const _accountScopedRejoinProjectsKey = 'ccs_account_scoped_rejoin_projects';
const _accountScopedGenerationKey = 'ccs_account_scoped_generation';
const _accountScopedOwnerKey = 'ccs_account_scoped_owner';
const _collaborationQueuePrefix = 'ccs_collab_queue_';
const _collaborationQueueGenerationSuffix = '_generation';

Future<void>? _accountQueueWrite;

Future<T> _enqueueAccountQueue<T>(Future<T> Function() operation) async {
  final previous = _accountQueueWrite ?? Future<void>.value();
  final next = previous.then((_) => operation());
  final queued = next.then<void>((_) {}).catchError((_) {});
  _accountQueueWrite = queued;
  try {
    return await next;
  } finally {
    if (identical(_accountQueueWrite, queued)) _accountQueueWrite = null;
  }
}

Future<void> _waitForAccountQueue() async {
  final pending = _accountQueueWrite;
  if (pending != null) await pending;
}

String _accountQueueKey(String projectId) =>
    '$_collaborationQueuePrefix$projectId';

String _accountQueueGenerationKey(String projectId) =>
    '${_accountQueueKey(projectId)}$_collaborationQueueGenerationSuffix';

/// Device-local cleanup for account-owned collaboration metadata.
///
/// Project documents remain available offline. Only the room markers that
/// would cause a later session to resume cloud collaboration are removed.
extension AccountScopedLocalStorage on LocalStorageService {
  Future<int> accountScopedCollaborationGeneration({String? accountId}) async {
    await _waitForAccountQueue();
    final prefs = await SharedPreferences.getInstance();
    var generation = prefs.getInt(_accountScopedGenerationKey) ?? 0;
    if (accountId == null || accountId.isEmpty) return generation;

    final owner = prefs.getString(_accountScopedOwnerKey);
    if (owner != accountId) {
      generation++;
      await prefs.setInt(_accountScopedGenerationKey, generation);
      final keys = prefs
          .getKeys()
          .where(
            (key) =>
                key.startsWith(_collaborationQueuePrefix) ||
                key.startsWith('ccs_account_collab_queue_'),
          )
          .toList(growable: false);
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.setString(_accountScopedOwnerKey, accountId);
    }
    return generation;
  }

  Future<List<CrdtOperation>> loadAccountScopedCollaborationQueue(
    String projectId, {
    required int generation,
    String? accountId,
  }) async {
    await _waitForAccountQueue();
    if (accountId == null || accountId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_accountScopedOwnerKey) != accountId) {
      return const [];
    }
    final currentGeneration = prefs.getInt(_accountScopedGenerationKey) ?? 0;
    if (currentGeneration != generation) return const [];
    final storedGeneration = prefs.getInt(
      _accountQueueGenerationKey(projectId),
    );
    if (storedGeneration != null && storedGeneration != generation) {
      return const [];
    }
    final raw = prefs.getString(_accountQueueKey(projectId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (value) => CrdtOperation.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((operation) => operation.projectId == projectId)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAccountScopedCollaborationQueue(
    String projectId,
    Iterable<CrdtOperation> operations, {
    required int generation,
    String? accountId,
  }) {
    return _enqueueAccountQueue(() async {
      if (accountId == null || accountId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_accountScopedOwnerKey) != accountId) return;
      final currentGeneration = prefs.getInt(_accountScopedGenerationKey) ?? 0;
      if (currentGeneration != generation) return;
      await prefs.setString(
        _accountQueueKey(projectId),
        jsonEncode(
          operations.map((operation) => operation.toPersistenceJson()).toList(),
        ),
      );
      await prefs.setInt(_accountQueueGenerationKey(projectId), generation);
    });
  }

  Future<void> clearAccountScopedCollaborationQueue(
    String projectId, {
    String? expectedAccountId,
  }) {
    return _enqueueAccountQueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(_accountScopedOwnerKey);
      if (expectedAccountId != null && owner != expectedAccountId) return;
      // An unauthenticated local session must not delete a signed-in
      // account's pending cloud queue for the same project ID.
      if (expectedAccountId == null && owner != null) return;
      await prefs.remove(_accountQueueKey(projectId));
      await prefs.remove(_accountQueueGenerationKey(projectId));
    });
  }

  Future<void> clearAllAccountScopedCollaborationQueues({
    String? expectedAccountId,
    bool Function()? shouldClear,
  }) {
    return _enqueueAccountQueue(() async {
      if (shouldClear != null && !shouldClear()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldClear != null && !shouldClear()) return;
      final expectedOwner = expectedAccountId?.trim();
      final owner = prefs.getString(_accountScopedOwnerKey);
      if (expectedOwner != null && expectedOwner.isNotEmpty) {
        // A late cleanup may run after another account owns the queue. It can
        // remove the outgoing account's queue only while the ownership marker
        // still names that account; otherwise the new account's queue stays
        // untouched and will be reclaimed by its own generation.
        if (owner != expectedOwner) return;
      }
      final generation = (prefs.getInt(_accountScopedGenerationKey) ?? 0) + 1;
      await prefs.setInt(_accountScopedGenerationKey, generation);
      final keys = prefs
          .getKeys()
          .where(
            (key) =>
                key.startsWith(_collaborationQueuePrefix) ||
                key.startsWith('ccs_account_collab_queue_'),
          )
          .toList(growable: false);
      for (final key in keys) {
        if (shouldClear != null && !shouldClear()) return;
        await prefs.remove(key);
      }
      await prefs.remove(_accountScopedOwnerKey);
    });
  }

  Future<void> clearAccountScopedCollaborationMetadata({
    String? expectedAccountId,
    bool Function()? shouldClear,
  }) => clearAccountScopedCollaborationMetadataAtomically(
    expectedAccountId: expectedAccountId,
    shouldClear: shouldClear,
  );

  Future<bool> requiresAccountScopedCollaborationRejoin(
    String projectId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_accountScopedRejoinProjectsKey) ?? const [])
        .contains(projectId);
  }

  Future<void> clearAccountScopedCollaborationRejoin(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final remaining =
        (prefs.getStringList(_accountScopedRejoinProjectsKey) ??
                const <String>[])
            .where((id) => id != projectId)
            .toList(growable: false);
    if (remaining.isEmpty) {
      await prefs.remove(_accountScopedRejoinProjectsKey);
    } else {
      await prefs.setStringList(_accountScopedRejoinProjectsKey, remaining);
    }
  }
}
