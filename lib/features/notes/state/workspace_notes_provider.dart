import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/data/workspace_note_attachment_repository.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/features/notes/domain/note_crdt_document.dart';
import 'package:varian/features/notes/domain/note_crdt_operation.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';

final workspaceNoteAttachmentRepositoryProvider =
    Provider<WorkspaceNoteAttachmentRepository>((ref) {
      final client = ref.watch(supabaseClientProvider);
      final offline = ref.watch(notesOfflineServiceProvider);
      if (client == null || offline == null) {
        throw StateError('Notes require a configured account.');
      }
      return WorkspaceNoteAttachmentRepository(
        client: client,
        localStore: offline.store,
        keyForAccount: offline.keyForAccount,
      );
    });

final workspaceNoteFoldersProvider =
    FutureProvider.family<List<WorkspaceNoteFolder>, String>((ref, accountId) {
      final auth = ref.watch(authUserProvider);
      final user = auth.valueOrNull;
      if (user?.id != accountId || user?.isAnonymous != false) {
        return Future.error(
          StateError('The signed-in account changed during this action.'),
        );
      }
      final repository = ref.watch(workspaceNoteRepositoryProvider);
      return repository.listFolders(expectedAccountId: accountId);
    });

final workspaceScopedNoteFoldersProvider =
    FutureProvider.family<List<WorkspaceNoteFolder>, (String, String?)>((
      ref,
      scope,
    ) {
      final accountId = scope.$1;
      final projectId = scope.$2;
      final auth = ref.watch(authUserProvider);
      final user = auth.valueOrNull;
      if (user?.id != accountId || user?.isAnonymous != false) {
        return Future.error(
          StateError('The signed-in account changed during this action.'),
        );
      }
      final repository = ref.watch(workspaceNoteRepositoryProvider);
      return repository.listFolders(
        projectId: projectId,
        expectedAccountId: accountId,
      );
    });

final workspacePinnedNotesProvider =
    FutureProvider.family<List<WorkspaceNote>, String>((ref, accountId) {
      final auth = ref.watch(authUserProvider);
      final user = auth.valueOrNull;
      if (user?.id != accountId || user?.isAnonymous != false) {
        return Future.error(
          StateError('The signed-in account changed during this action.'),
        );
      }
      final repository = ref.watch(workspaceNoteRepositoryProvider);
      return repository.listPinnedNotes(expectedAccountId: accountId);
    });

final workspaceNotesProvider =
    StateNotifierProvider<WorkspaceNotesNotifier, WorkspaceNotesState>((ref) {
      final client = ref.read(supabaseClientProvider);
      final notifier = WorkspaceNotesNotifier(
        client,
        client == null ? null : WorkspaceNoteRepository(client),
        offlineService: ref.watch(notesOfflineServiceProvider),
      );
      ref.listen(supabaseClientProvider, (_, nextClient) {
        notifier.updateClient(nextClient);
      });
      ref.listen(authUserProvider, (_, next) {
        if (next.hasValue) notifier.refreshAccount();
      });
      return notifier;
    });

final workspaceNoteScopeChangeEligibilityProvider =
    FutureProvider.family<bool, (String, String)>((ref, request) async {
      final (accountId, noteId) = request;
      if (ref.watch(workspaceNotesProvider).accountId != accountId) {
        return false;
      }
      return ref
          .watch(workspaceNoteRepositoryProvider)
          .canManageNoteScopeChange(
            noteId: noteId,
            expectedAccountId: accountId,
          );
    });

String workspaceNotesFailureMessage(
  Object? error, {
  String? accountId,
  bool cloudReady = true,
}) {
  if (!cloudReady) {
    return 'Notes cloud is not ready yet. Retry after cloud services connect.';
  }
  if (accountId == null) return 'Sign in to access your private Notes.';
  if (error is PostgrestException) {
    return switch (error.code) {
      '42P01' || '42703' || 'PGRST204' || 'PGRST205' =>
        'Notes cloud storage is not ready. Apply the private Notes migration, then retry.',
      '42501' || '401' || '403' =>
        'Notes cloud access was denied. Check your sign-in and Notes permissions.',
      _ =>
        'Notes cloud request failed. Retry; if it continues, check the Notes setup.',
    };
  }
  if (error is AuthRetryableFetchException) {
    return 'Your sign-in could not be verified. Check your connection, then retry or sign in again.';
  }
  if (error is AuthException) {
    return 'Your sign-in expired. Sign in again to access private Notes.';
  }
  if (error is TimeoutException || error is ClientException) {
    return 'Notes cloud is unavailable. Check your connection and retry.';
  }
  if (error is StateError) {
    return switch (error.message) {
      'Encrypted Notes storage is unavailable.' =>
        'Encrypted Notes device storage is unavailable. Enable secure storage or unlock Notes recovery before retrying.',
      'The signed-in account changed during this action.' ||
      'The note owner changed.' =>
        'Your signed-in account changed. Sign in again and retry.',
      'Notes cloud is not ready.' || 'Notes require a configured account.' =>
        'Notes cloud is not ready yet. Retry after cloud services connect.',
      'Sign in to access private notes.' ||
      'Sign in to create private notes.' =>
        'Sign in to access your private Notes.',
      _ =>
        'Notes cloud request failed. Retry; if it continues, check the Notes setup.',
    };
  }
  return 'Notes cloud is unavailable. Check your connection and retry.';
}

class WorkspaceNoteConflictError implements Exception {
  const WorkspaceNoteConflictError();
}

class WorkspaceNoteUnavailableError implements Exception {
  const WorkspaceNoteUnavailableError();
}

sealed class WorkspaceNoteRenameOutcome {
  const WorkspaceNoteRenameOutcome();
}

final class WorkspaceNoteRenameSuccess extends WorkspaceNoteRenameOutcome {
  WorkspaceNoteRenameSuccess(List<WorkspaceNote> notes)
    : notes = List.unmodifiable(notes);

  final List<WorkspaceNote> notes;
}

final class WorkspaceNoteRenameBlocked extends WorkspaceNoteRenameOutcome {
  WorkspaceNoteRenameBlocked(Set<String> sourceIds)
    : ambiguousSourceIds = Set.unmodifiable(sourceIds);

  final Set<String> ambiguousSourceIds;
}

final class WorkspaceNoteRenameConflict extends WorkspaceNoteRenameOutcome {
  const WorkspaceNoteRenameConflict();
}

final class WorkspaceNoteRenameUnavailable extends WorkspaceNoteRenameOutcome {
  const WorkspaceNoteRenameUnavailable();
}

final class WorkspaceNoteRenameFailure extends WorkspaceNoteRenameOutcome {
  const WorkspaceNoteRenameFailure(this.error);

  final Object error;
}

@immutable
class WorkspaceNotesState {
  const WorkspaceNotesState({
    this.accountId,
    this.notes = const [],
    this.loading = false,
    this.savingNoteIds = const {},
    this.renamingNoteIds = const {},
    this.conflicts = const {},
    this.queuedNoteIds = const {},
    this.accessPausedNoteIds = const {},
    this.error,
    this.trashNotes = const [],
    this.trashLoading = false,
    this.trashError,
  });

  final String? accountId;
  final List<WorkspaceNote> notes;
  final bool loading;
  final Set<String> savingNoteIds;
  final Set<String> renamingNoteIds;
  final Map<String, WorkspaceNoteSaveConflict> conflicts;
  final Set<String> queuedNoteIds;
  final Set<String> accessPausedNoteIds;
  final Object? error;
  final List<WorkspaceNote> trashNotes;
  final bool trashLoading;
  final Object? trashError;

  WorkspaceNotesState copyWith({
    List<WorkspaceNote>? trashNotes,
    bool? trashLoading,
    Object? trashError,
    bool clearTrashError = false,
    String? accountId,
    List<WorkspaceNote>? notes,
    bool? loading,
    Set<String>? savingNoteIds,
    Set<String>? renamingNoteIds,
    Map<String, WorkspaceNoteSaveConflict>? conflicts,
    Set<String>? queuedNoteIds,
    Set<String>? accessPausedNoteIds,
    Object? error,
    bool clearError = false,
  }) => WorkspaceNotesState(
    accountId: accountId ?? this.accountId,
    notes: notes ?? this.notes,
    loading: loading ?? this.loading,
    savingNoteIds: savingNoteIds ?? this.savingNoteIds,
    renamingNoteIds: renamingNoteIds ?? this.renamingNoteIds,
    conflicts: conflicts ?? this.conflicts,
    queuedNoteIds: queuedNoteIds ?? this.queuedNoteIds,
    accessPausedNoteIds: accessPausedNoteIds ?? this.accessPausedNoteIds,
    error: clearError ? null : error ?? this.error,
    trashNotes: trashNotes ?? this.trashNotes,
    trashLoading: trashLoading ?? this.trashLoading,
    trashError: clearTrashError ? null : trashError ?? this.trashError,
  );
}

class WorkspaceNotesNotifier extends StateNotifier<WorkspaceNotesState> {
  WorkspaceNotesNotifier(this._client, this._repository, {this._offlineService})
    : super(WorkspaceNotesState(accountId: _accountFor(_client))) {
    final accountId = state.accountId;
    if (accountId != null) {
      unawaited(load());
      unawaited(_resumeOfflineState(accountId, _generation));
    }
  }

  SupabaseClient? _client;
  WorkspaceNoteRepository? _repository;
  final NotesOfflineService? _offlineService;
  int _generation = 0;
  int _accountGeneration = 0;
  int _loadGeneration = 0;
  final Map<String, int> _saveGenerations = {};

  Future<WorkspaceNote?> syncCrdtEdit({
    required WorkspaceNote note,
    required NoteCrdtDocument document,
    required List<NoteCrdtOperation> operations,
  }) async {
    final client = _client;
    final repository = _repository;
    final accountId = state.accountId;
    if (client == null ||
        repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId) ||
        (note.projectId == null && note.ownerUserId != accountId)) {
      throw StateError('Notes CRDT access denied.');
    }
    final generation = _generation;
    try {
      for (final operation in operations) {
        if (operation.noteId != note.id) {
          throw ArgumentError.value(operation.noteId, 'operation.noteId');
        }
        await client.rpc(
          'append_workspace_note_crdt_operation',
          params: {'p_note_id': note.id, 'p_operation': operation.toJson()},
        );
        if (!_isCurrent(accountId, generation)) return null;
      }
      final response = await client.rpc(
        'materialize_workspace_note_crdt',
        params: {
          'p_note_id': note.id,
          'p_expected_revision': note.revision,
          'p_markdown_content': document.visibleMarkdown,
          'p_state_json': document.snapshotState(),
          'p_version_vector': document.versionVector.toJson(),
        },
      );
      if (!_isCurrent(accountId, generation)) return null;
      final updated = response is Map
          ? WorkspaceNote.fromJson(Map<String, dynamic>.from(response))
          : await repository.get(note.id, expectedAccountId: accountId);
      if (!_isCurrent(accountId, generation)) return null;
      state = state.copyWith(
        notes: [updated, ...state.notes.where((item) => item.id != updated.id)],
        queuedNoteIds: {...state.queuedNoteIds}..remove(note.id),
        clearError: true,
      );
      return updated;
    } catch (_) {
      if (!_isCurrent(accountId, generation) || operations.isEmpty) rethrow;
      final offline = _offlineService;
      final key = await offline?.keyForAccount(accountId);
      if (offline == null ||
          key == null ||
          !_isCurrent(accountId, generation)) {
        rethrow;
      }
      for (final operation in operations) {
        await offline.sync.enqueue(
          accountId: accountId,
          key: key,
          operation: {
            'noteId': note.id,
            'opId': operation.opId,
            'projectId': note.projectId,
            'operation': operation.toJson(),
          },
        );
      }
      await offline.store.saveNote(
        accountId: accountId,
        noteId: note.id,
        plaintext: document.visibleMarkdown,
        key: key,
      );
      if (!offline.store.isEnabled || !_isCurrent(accountId, generation)) {
        rethrow;
      }
      state = state.copyWith(queuedNoteIds: {...state.queuedNoteIds, note.id});
      return note.copyWith(markdownContent: document.visibleMarkdown);
    }
  }

  Future<void> retryOfflineSync() async {
    final accountId = state.accountId;
    final offline = _offlineService;
    if (accountId == null || offline == null || !_isAuthenticated(accountId)) {
      return;
    }
    final generation = _generation;
    try {
      await offline.sync.resumeAfterAuthentication(accountId);
      if (!_isCurrent(accountId, generation)) return;
      await load();
      if (state.accountId != accountId) return;
      final pending = await offline.sync.pendingNoteIds(accountId);
      final accessPaused = await offline.sync.pausedNoteIds(accountId);
      if (state.accountId != accountId) return;
      state = state.copyWith(
        queuedNoteIds: pending,
        accessPausedNoteIds: accessPaused,
      );
    } catch (_) {
      // Keep queued IDs visible so the user can retry later.
    }
  }

  Future<Map<String, dynamic>?> loadCrdtSnapshot(String noteId) async {
    final client = _client;
    final accountId = state.accountId;
    if (client == null || accountId == null || !_isAuthenticated(accountId)) {
      return null;
    }
    final generation = _generation;
    final row = await client
        .from('workspace_note_crdt_snapshots')
        .select('state_json, version_vector, materialized_revision')
        .eq('note_id', noteId)
        .maybeSingle();
    if (!_isCurrent(accountId, generation) || row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> loadCrdtDelta({
    required String noteId,
    required Map<String, dynamic> versionVector,
  }) async {
    final client = _client;
    final accountId = state.accountId;
    if (client == null || accountId == null || !_isAuthenticated(accountId)) {
      return const [];
    }
    final generation = _generation;
    final response = await client.rpc(
      'get_workspace_note_crdt_delta',
      params: {'p_note_id': noteId, 'p_since': versionVector, 'p_limit': 1000},
    );
    if (!_isCurrent(accountId, generation) || response is! List) {
      return const [];
    }
    return response
        .whereType<Map>()
        .map((operation) => Map<String, dynamic>.from(operation))
        .toList(growable: false);
  }

  static String? _accountFor(SupabaseClient? client) {
    final auth = client?.auth;
    final user = auth?.currentSession?.user ?? auth?.currentUser;
    return user != null && !user.isAnonymous ? user.id : null;
  }

  void updateClient(SupabaseClient? client) {
    if (identical(client, _client)) return;
    _client = client;
    _repository = client == null ? null : WorkspaceNoteRepository(client);
    _resetAccount();
  }

  void refreshAccount() {
    final accountId = _accountFor(_client);
    if (accountId == state.accountId) return;
    _resetAccount();
  }

  void _resetAccount() {
    final accountId = _accountFor(_client);
    _generation++;
    _accountGeneration++;
    _saveGenerations.clear();
    state = WorkspaceNotesState(accountId: accountId);
    _offlineService?.sync.accountChanged();
    if (accountId != null) {
      unawaited(load());
      unawaited(_resumeOfflineState(accountId, _generation));
    }
  }

  Future<void> _resumeOfflineState(String accountId, int generation) async {
    final offline = _offlineService;
    if (offline == null) return;
    try {
      await offline.sync.resumeAfterAuthentication(accountId);
      if (!_isCurrent(accountId, generation)) return;
      final pending = await offline.sync.pendingNoteIds(accountId);
      final accessPaused = await offline.sync.pausedNoteIds(accountId);
      if (!_isCurrent(accountId, generation)) return;
      state = state.copyWith(
        queuedNoteIds: pending,
        accessPausedNoteIds: accessPaused,
      );
    } catch (_) {
      // Retain encrypted queued work for another retry.
    }
  }

  Future<void> load() async {
    final repository = _repository;
    final accountId = state.accountId;
    if (accountId == null) {
      state = const WorkspaceNotesState();
      return;
    }
    if (repository == null) {
      state = state.copyWith(
        loading: false,
        error: StateError('Notes cloud is not ready.'),
      );
      return;
    }
    final loadGeneration = ++_loadGeneration;
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      var notes = await repository.list(expectedAccountId: accountId);
      if (loadGeneration != _loadGeneration) return;
      if (!_isCurrent(accountId, generation)) {
        _clearCurrentLoad(accountId, loadGeneration);
        return;
      }
      final renamed = await repository.renameLegacyUntitledNotes(
        expectedAccountId: accountId,
      );
      if (loadGeneration != _loadGeneration) return;
      if (!_isCurrent(accountId, generation)) {
        _clearCurrentLoad(accountId, loadGeneration);
        return;
      }
      if (renamed.isNotEmpty) {
        final renamedById = {for (final note in renamed) note.id: note};
        notes = [for (final note in notes) renamedById[note.id] ?? note];
      }
      state = state.copyWith(notes: notes, loading: false, clearError: true);
    } catch (error) {
      if (loadGeneration != _loadGeneration) return;
      if (!_isCurrent(accountId, generation)) {
        _clearCurrentLoad(accountId, loadGeneration);
        return;
      }
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> loadTrash() async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(trashLoading: true, clearTrashError: true);
    try {
      final notes = await repository.listTrash(expectedAccountId: accountId);
      if (!_isCurrent(accountId, generation)) return;
      state = state.copyWith(
        trashNotes: notes,
        trashLoading: false,
        clearTrashError: true,
      );
    } catch (error) {
      if (!_isCurrent(accountId, generation)) return;
      state = state.copyWith(trashLoading: false, trashError: error);
    }
  }

  Future<WorkspaceNote?> _queueOfflineTrashMutation({
    required String action,
    required WorkspaceNote note,
    required String accountId,
    required int generation,
  }) async {
    final offline = _offlineService;
    final key = await offline?.keyForAccount(accountId);
    if (offline == null || key == null || !_isCurrent(accountId, generation)) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final updated = action == 'delete'
        ? note.copyWith(
            deletedAt: now,
            updatedAt: now,
            revision: note.revision + 1,
          )
        : note.copyWith(
            clearDeletedAt: true,
            updatedAt: now,
            revision: note.revision + 1,
          );
    await offline.sync.enqueue(
      accountId: accountId,
      key: key,
      operation: {
        'kind': 'note_mutation',
        'action': action,
        'noteId': note.id,
        'opId': '${note.id}:mutation:${note.revision}:$action',
        'projectId': note.projectId,
        'expectedRevision': note.revision,
        if (action == 'delete') 'deletedAt': now.toIso8601String(),
      },
    );
    await offline.store.saveNote(
      accountId: accountId,
      noteId: note.id,
      plaintext: note.markdownContent,
      key: key,
    );
    if (!offline.store.isEnabled || !_isCurrent(accountId, generation)) {
      return null;
    }
    return updated;
  }

  Future<bool> deleteNote(WorkspaceNote note) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        note.ownerUserId != accountId ||
        !_isAuthenticated(accountId)) {
      return false;
    }
    final generation = _generation;
    try {
      final deleted = await repository.delete(
        note,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return false;
      state = state.copyWith(
        notes: state.notes.where((item) => item.id != note.id).toList(),
        trashNotes: [deleted, ...state.trashNotes],
      );
      return true;
    } catch (error) {
      if (!_isCurrent(accountId, generation)) return false;
      try {
        final queued = await _queueOfflineTrashMutation(
          action: 'delete',
          note: note,
          accountId: accountId,
          generation: generation,
        );
        if (queued == null) rethrow;
        state = state.copyWith(
          notes: state.notes.where((item) => item.id != note.id).toList(),
          trashNotes: [queued, ...state.trashNotes],
          queuedNoteIds: {...state.queuedNoteIds, note.id},
          clearError: true,
        );
        return true;
      } catch (_) {
        final failure = _offlineService?.store.isEnabled == false
            ? StateError('Encrypted Notes storage is unavailable.')
            : error;
        state = state.copyWith(error: failure);
        return false;
      }
    }
  }

  Future<bool> restoreNote(WorkspaceNote note) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        note.ownerUserId != accountId ||
        !_isAuthenticated(accountId)) {
      return false;
    }
    final generation = _generation;
    try {
      final restored = await repository.restore(
        note,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return false;
      state = state.copyWith(
        trashNotes: state.trashNotes
            .where((item) => item.id != note.id)
            .toList(),
        notes: [restored, ...state.notes],
      );
      return true;
    } catch (error) {
      if (!_isCurrent(accountId, generation)) return false;
      try {
        final queued = await _queueOfflineTrashMutation(
          action: 'restore',
          note: note,
          accountId: accountId,
          generation: generation,
        );
        if (queued == null) rethrow;
        state = state.copyWith(
          trashNotes: state.trashNotes
              .where((item) => item.id != note.id)
              .toList(),
          notes: [queued, ...state.notes],
          queuedNoteIds: {...state.queuedNoteIds, note.id},
          clearTrashError: true,
        );
        return true;
      } catch (_) {
        final failure = _offlineService?.store.isEnabled == false
            ? StateError('Encrypted Notes storage is unavailable.')
            : error;
        state = state.copyWith(trashError: failure);
        return false;
      }
    }
  }

  Future<List<WorkspaceNoteVersion>> listNoteVersions(String noteId) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      return const [];
    }
    final generation = _generation;
    try {
      final versions = await repository.listNoteVersions(noteId);
      if (!_isCurrent(accountId, generation)) return const [];
      return versions;
    } catch (error) {
      if (_isCurrent(accountId, generation)) {
        state = state.copyWith(error: error);
      }
      return const [];
    }
  }

  Future<bool> restoreNoteVersion({
    required String noteId,
    required String versionId,
    required int expectedRevision,
  }) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      return false;
    }
    final generation = _generation;
    try {
      final restored = await repository.restoreNoteVersion(
        noteId: noteId,
        versionId: versionId,
        expectedRevision: expectedRevision,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return false;
      state = state.copyWith(
        notes: [
          restored,
          ...state.notes.where((item) => item.id != restored.id),
        ],
        clearError: true,
      );
      return true;
    } catch (error) {
      if (_isCurrent(accountId, generation)) {
        state = state.copyWith(error: error);
      }
      return false;
    }
  }

  Future<List<WorkspaceNote>?> importNotes({
    required List<PreparedNoteImport> notes,
    required String? projectId,
  }) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      state = state.copyWith(error: StateError('Sign in to import notes.'));
      return null;
    }
    final generation = _generation;
    try {
      final imported = await repository.importNotes(
        notes: notes,
        projectId: projectId,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return null;
      state = state.copyWith(
        notes: [...imported, ...state.notes],
        clearError: true,
      );
      return imported;
    } catch (error) {
      if (_isCurrent(accountId, generation)) {
        state = state.copyWith(error: error);
      }
      return null;
    }
  }

  Future<WorkspaceNote?> _queueOfflinePrivateCreate(
    String accountId,
    int generation, {
    String title = 'Untitled Note',
  }) async {
    final offline = _offlineService;
    final key = await offline?.keyForAccount(accountId);
    if (offline == null || key == null || !_isCurrent(accountId, generation)) {
      return null;
    }
    final noteId = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final note = WorkspaceNote(
      id: noteId,
      ownerUserId: accountId,
      createdBy: accountId,
      title: title.trim().isEmpty ? 'Untitled Note' : title.trim(),
      markdownContent: '',
      createdAt: now,
      updatedAt: now,
    );
    await offline.sync.enqueue(
      accountId: accountId,
      key: key,
      operation: {
        'kind': 'note_mutation',
        'action': 'create',
        'noteId': noteId,
        'opId': '$noteId:mutation:1',
        'ownerUserId': accountId,
        'projectId': null,
        'folderId': null,
        'title': note.title,
        'markdownContent': note.markdownContent,
      },
    );
    await offline.store.saveNote(
      accountId: accountId,
      noteId: noteId,
      plaintext: '',
      key: key,
    );
    if (!offline.store.isEnabled || !_isCurrent(accountId, generation)) {
      return null;
    }
    state = state.copyWith(
      notes: [note, ...state.notes],
      queuedNoteIds: {...state.queuedNoteIds, noteId},
      clearError: true,
    );
    return note;
  }

  Future<WorkspaceNote?> createNote({
    String title = 'Untitled Note',
    String? projectId,
  }) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      state = state.copyWith(error: StateError('Sign in to create Notes.'));
      return null;
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      state = state.copyWith(error: ArgumentError.value(title, 'title'));
      return null;
    }
    final generation = _generation;
    try {
      final note = await repository.create(
        title: normalizedTitle,
        projectId: projectId,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return null;
      state = state.copyWith(notes: [note, ...state.notes], clearError: true);
      return note;
    } catch (error) {
      if (!_isCurrent(accountId, generation)) return null;
      if (projectId == null) {
        try {
          final queued = await _queueOfflinePrivateCreate(
            accountId,
            generation,
            title: normalizedTitle,
          );
          if (queued != null) return queued;
        } catch (_) {
          // Preserve the normal error state if local persistence is unavailable.
        }
      }
      if (_isCurrent(accountId, generation)) {
        state = state.copyWith(error: error);
      }
      return null;
    }
  }

  Future<WorkspaceNote?> getOrCreateDailyNote({
    required DateTime localDate,
    String? projectId,
  }) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      state = state.copyWith(error: StateError('Sign in to create Notes.'));
      return null;
    }
    final generation = _generation;
    try {
      final note = await repository.getOrCreateDailyNote(
        localDate: localDate,
        projectId: projectId,
        expectedAccountId: accountId,
      );
      if (!_isCurrent(accountId, generation)) return null;
      state = state.copyWith(
        notes: [note, ...state.notes.where((item) => item.id != note.id)],
        clearError: true,
      );
      return note;
    } catch (error) {
      if (!_isCurrent(accountId, generation)) return null;
      state = state.copyWith(error: error);
      return null;
    }
  }

  Future<WorkspaceNoteSaveOutcome?> saveNote(WorkspaceNote note) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        (note.projectId == null && note.ownerUserId != accountId) ||
        !_isAuthenticated(accountId)) {
      state = state.copyWith(error: StateError('The note owner changed.'));
      return null;
    }
    final saveGeneration = (_saveGenerations[note.id] ?? 0) + 1;
    _saveGenerations[note.id] = saveGeneration;
    final generation = _generation;
    state = state.copyWith(
      savingNoteIds: {...state.savingNoteIds, note.id},
      clearError: true,
    );
    try {
      final outcome = await repository.save(note, expectedAccountId: accountId);
      if (!_isCurrent(accountId, generation) ||
          _saveGenerations[note.id] != saveGeneration) {
        return null;
      }
      final saving = {...state.savingNoteIds}..remove(note.id);
      switch (outcome) {
        case WorkspaceNoteSaveSuccess(:final note):
          final conflicts = {...state.conflicts}..remove(note.id);
          state = state.copyWith(
            conflicts: conflicts,
            notes: [note, ...state.notes.where((item) => item.id != note.id)],
            savingNoteIds: saving,
            clearError: true,
          );
        case WorkspaceNoteSaveConflict():
          state = state.copyWith(
            conflicts: {...state.conflicts, note.id: outcome},
            savingNoteIds: saving,
            error: const WorkspaceNoteConflictError(),
          );
        case WorkspaceNoteSaveUnavailable():
          state = state.copyWith(
            savingNoteIds: saving,
            error: const WorkspaceNoteUnavailableError(),
          );
      }
      return outcome;
    } catch (error) {
      if (!_isCurrent(accountId, generation) ||
          _saveGenerations[note.id] != saveGeneration) {
        return null;
      }
      state = state.copyWith(
        savingNoteIds: {...state.savingNoteIds}..remove(note.id),
        error: error,
      );
      return null;
    }
  }

  Future<WorkspaceNoteRenameOutcome?> renameNoteWithLinks({
    required String noteId,
    required String title,
  }) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (accountId == null || !_isAuthenticated(accountId)) {
      final error = StateError('Sign in to access private notes.');
      if (mounted) state = state.copyWith(error: error);
      return WorkspaceNoteRenameFailure(error);
    }
    if (repository == null) {
      final error = StateError('Notes cloud is not ready.');
      state = state.copyWith(error: error);
      return WorkspaceNoteRenameFailure(error);
    }
    if (state.loading) {
      final error = StateError('Notes are still loading.');
      state = state.copyWith(error: error);
      return WorkspaceNoteRenameFailure(error);
    }
    if (state.renamingNoteIds.contains(noteId)) return null;

    final targets = state.notes.where((note) => note.id == noteId).toList();
    if (targets.length != 1 ||
        (targets.single.projectId == null &&
            targets.single.ownerUserId != accountId)) {
      state = state.copyWith(error: const WorkspaceNoteUnavailableError());
      return const WorkspaceNoteRenameUnavailable();
    }
    final target = targets.single;
    final snapshot = state.notes
        .where((note) => note.deletedAt == null)
        .toList(growable: false);
    final WorkspaceNoteRenamePlan plan;
    try {
      plan = planWorkspaceNoteRename(
        activeNotes: snapshot,
        targetId: target.id,
        requestedTitle: title,
      );
    } catch (error) {
      state = state.copyWith(error: error);
      return WorkspaceNoteRenameFailure(error);
    }
    if (plan.ambiguousSourceIds.isNotEmpty) {
      return WorkspaceNoteRenameBlocked(plan.ambiguousSourceIds);
    }

    final accountGeneration = _accountGeneration;
    state = state.copyWith(
      renamingNoteIds: {...state.renamingNoteIds, noteId},
      clearError: true,
    );
    try {
      final updated = await repository.renameWithLinks(
        target: target,
        title: title,
        snapshot: snapshot,
        markdownReplacements: plan.markdownReplacements,
        expectedAccountId: accountId,
      );
      if (!_isAccountCurrent(accountId, accountGeneration)) return null;
      _loadGeneration++;
      final updatedById = {for (final note in updated) note.id: note};
      state = state.copyWith(
        notes: [for (final note in state.notes) updatedById[note.id] ?? note],
        loading: false,
        clearError: true,
      );
      try {
        final refreshed = await repository.list(expectedAccountId: accountId);
        if (!_isAccountCurrent(accountId, accountGeneration)) return null;
        state = state.copyWith(
          notes: refreshed,
          renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
          clearError: true,
        );
      } catch (refreshError) {
        if (!_isAccountCurrent(accountId, accountGeneration)) return null;
        state = state.copyWith(
          renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
          error: refreshError,
        );
      }
      return WorkspaceNoteRenameSuccess(updated);
    } on WorkspaceNoteRenameConflictException {
      if (!_isAccountCurrent(accountId, accountGeneration)) return null;
      state = state.copyWith(
        renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
        error: const WorkspaceNoteConflictError(),
      );
      return const WorkspaceNoteRenameConflict();
    } on WorkspaceNoteRenameUnavailableException {
      if (!_isAccountCurrent(accountId, accountGeneration)) return null;
      state = state.copyWith(
        renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
        error: const WorkspaceNoteUnavailableError(),
      );
      return const WorkspaceNoteRenameUnavailable();
    } catch (error) {
      if (!_isAccountCurrent(accountId, accountGeneration)) return null;
      state = state.copyWith(
        renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
        error: error,
      );
      return WorkspaceNoteRenameFailure(error);
    } finally {
      if (mounted &&
          state.accountId == accountId &&
          state.renamingNoteIds.contains(noteId)) {
        state = state.copyWith(
          renamingNoteIds: {...state.renamingNoteIds}..remove(noteId),
        );
      }
    }
  }

  Future<WorkspaceNote?> openNote(String noteId) async {
    final repository = _repository;
    final accountId = state.accountId;
    if (repository == null ||
        accountId == null ||
        !_isAuthenticated(accountId)) {
      return null;
    }
    final generation = _generation;
    try {
      final note = await repository.get(noteId, expectedAccountId: accountId);
      if (!_isCurrent(accountId, generation)) return null;
      final notes = [note, ...state.notes.where((item) => item.id != note.id)];
      state = state.copyWith(notes: notes, clearError: true);
      return note;
    } catch (error) {
      if (_isCurrent(accountId, generation)) {
        state = state.copyWith(error: error);
      }
      return null;
    }
  }

  void _clearCurrentLoad(String accountId, int loadGeneration) {
    if (!mounted ||
        loadGeneration != _loadGeneration ||
        state.accountId != accountId ||
        !state.loading) {
      return;
    }
    state = state.copyWith(loading: false);
  }

  bool _isAuthenticated(String accountId) {
    final auth = _client?.auth;
    final user = auth?.currentSession?.user ?? auth?.currentUser;
    return user?.id == accountId && user?.isAnonymous == false;
  }

  bool _isCurrent(String accountId, int generation) =>
      mounted &&
      generation == _generation &&
      state.accountId == accountId &&
      _isAuthenticated(accountId);

  bool _isAccountCurrent(String accountId, int generation) =>
      mounted &&
      generation == _accountGeneration &&
      state.accountId == accountId &&
      _isAuthenticated(accountId);
}
