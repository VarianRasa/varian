import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/domain/workspace_note_project_scope.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/domain/workspace_note_links.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';
import 'package:varian/features/notes/domain/workspace_note_scope_change_job.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';

final workspaceNoteRepositoryProvider = Provider<WorkspaceNoteRepository>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw StateError('Notes require a configured account.');
  return WorkspaceNoteRepository(client);
});

sealed class WorkspaceNoteSaveOutcome {
  const WorkspaceNoteSaveOutcome();
}

final class WorkspaceNoteSaveSuccess extends WorkspaceNoteSaveOutcome {
  const WorkspaceNoteSaveSuccess(this.note);
  final WorkspaceNote note;
}

final class WorkspaceNoteSaveConflict extends WorkspaceNoteSaveOutcome {
  const WorkspaceNoteSaveConflict(this.remoteNote);
  final WorkspaceNote remoteNote;
}

final class WorkspaceNoteSaveUnavailable extends WorkspaceNoteSaveOutcome {
  const WorkspaceNoteSaveUnavailable();
}

sealed class WorkspaceNoteRenameException implements Exception {
  const WorkspaceNoteRenameException();
}

final class WorkspaceNoteRenameConflictException
    extends WorkspaceNoteRenameException {
  const WorkspaceNoteRenameConflictException();
}

final class WorkspaceNoteRenameUnavailableException
    extends WorkspaceNoteRenameException {
  const WorkspaceNoteRenameUnavailableException();
}

class WorkspaceNoteRepository {
  WorkspaceNoteRepository(this._client);

  static const _columns =
      'id, owner_user_id, title, markdown_content, created_at, updated_at, revision, deleted_at, project_id, folder_id, created_by, daily_note_date';
  static const _folderColumns =
      'id, owner_user_id, project_id, parent_folder_id, name, sort_order, created_at, updated_at';
  static const _templateColumns =
      'id, owner_user_id, created_by, project_id, title, markdown_content, revision, created_at, updated_at';
  final SupabaseClient _client;

  String _requireAccount(String? expectedAccountId) {
    final auth = _client.auth;
    final user = auth.currentSession?.user ?? auth.currentUser;
    final accountId = user?.id;
    if (user == null || user.isAnonymous || accountId == null) {
      throw StateError('Sign in to access private notes.');
    }
    if (expectedAccountId != null && accountId != expectedAccountId) {
      throw StateError('The signed-in account changed during this action.');
    }
    return accountId;
  }

  Future<List<WorkspaceNote>> list({String? expectedAccountId}) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = await _client
        .from('workspace_notes')
        .select(_columns)
        .isFilter('deleted_at', null)
        .order('updated_at', ascending: false);
    _requireAccount(accountId);
    return rows
        .map((row) => WorkspaceNote.fromJson(row))
        .toList(growable: false);
  }

  Future<void> _requireProjectEdit(String? projectId, String accountId) async {
    if (projectId == null) return;
    final allowed = await _client.rpc(
      'can_edit_project',
      params: {'p_project_id': projectId},
    );
    _requireAccount(accountId);
    if (allowed != true) throw StateError('Project edit membership required.');
  }

  Future<List<WorkspaceNote>> listTrash({String? expectedAccountId}) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = await _client
        .from('workspace_notes')
        .select(_columns)
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    _requireAccount(accountId);
    return rows
        .map((row) => WorkspaceNote.fromJson(row))
        .toList(growable: false);
  }

  Future<List<WorkspaceNoteVersion>> listNoteVersions(String noteId) async {
    final accountId = _requireAccount(null);
    final rows = await _client
        .from('workspace_note_versions')
        .select(
          'id, note_id, revision, title, markdown_content, actor_id, created_at',
        )
        .eq('note_id', noteId)
        .order('revision', ascending: false);
    _requireAccount(accountId);
    return rows
        .map((row) => WorkspaceNoteVersion.fromJson(row))
        .toList(growable: false);
  }

  Future<WorkspaceNote> restoreNoteVersion({
    required String noteId,
    required String versionId,
    required int expectedRevision,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final noteRow = await _client
        .from('workspace_notes')
        .select(_columns)
        .eq('id', noteId)
        .maybeSingle();
    _requireAccount(accountId);
    if (noteRow == null) throw StateError('The note is unavailable.');
    final current = WorkspaceNote.fromJson(noteRow);
    if (current.deletedAt != null) throw StateError('The note is in Trash.');
    if (current.projectId == null && current.ownerUserId != accountId) {
      throw StateError('A private note can only be restored by its owner.');
    }
    await _requireProjectEdit(current.projectId, accountId);

    final versionRow = await _client
        .from('workspace_note_versions')
        .select(
          'id, note_id, revision, title, markdown_content, actor_id, created_at',
        )
        .eq('id', versionId)
        .eq('note_id', noteId)
        .maybeSingle();
    _requireAccount(accountId);
    if (versionRow == null) {
      throw StateError('The note version is unavailable.');
    }
    final version = WorkspaceNoteVersion.fromJson(versionRow);
    if (current.title == version.title &&
        current.markdownContent == version.markdownContent) {
      return current;
    }
    final restored = await _client
        .from('workspace_notes')
        .update({
          'title': version.title,
          'markdown_content': version.markdownContent,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'revision': expectedRevision + 1,
        })
        .eq('id', noteId)
        .eq('revision', expectedRevision)
        .isFilter('deleted_at', null)
        .select(_columns)
        .maybeSingle();
    _requireAccount(accountId);
    if (restored == null) {
      throw StateError('The note changed. Reload history before restoring.');
    }
    return WorkspaceNote.fromJson(restored);
  }

  Future<WorkspaceNote> delete(
    WorkspaceNote note, {
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (note.projectId == null && note.ownerUserId != accountId) {
      throw StateError('A private note can only be deleted by its owner.');
    }
    await _requireProjectEdit(note.projectId, accountId);
    final row = await _client
        .from('workspace_notes')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'revision': note.revision + 1,
        })
        .eq('id', note.id)
        .eq('revision', note.revision)
        .isFilter('deleted_at', null)
        .select(_columns)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) throw StateError('The note is unavailable or changed.');
    return WorkspaceNote.fromJson(row);
  }

  Future<WorkspaceNote> restore(
    WorkspaceNote note, {
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (note.projectId == null && note.ownerUserId != accountId) {
      throw StateError('A private note can only be restored by its owner.');
    }
    await _requireProjectEdit(note.projectId, accountId);
    final row = await _client
        .from('workspace_notes')
        .update({
          'deleted_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'revision': note.revision + 1,
        })
        .eq('id', note.id)
        .eq('revision', note.revision)
        .not('deleted_at', 'is', null)
        .select(_columns)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) throw StateError('The note is unavailable or changed.');
    return WorkspaceNote.fromJson(row);
  }

  Future<WorkspaceNote> create({
    required String title,
    String markdownContent = '',
    String? projectId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    await _requireProjectEdit(projectId, accountId);
    final now = DateTime.now().toUtc();
    final normalizedTitle = title.trim();
    final normalizedCreatedTitle =
        normalizedTitle.isEmpty || normalizedTitle == 'Untitled Note'
        ? formatWorkspaceTimestamp(now)
        : normalizedTitle;
    final row = await _client
        .from('workspace_notes')
        .insert({
          'id': const Uuid().v4(),
          'owner_user_id': accountId,
          'created_by': accountId,
          'project_id': projectId,
          'title': normalizedCreatedTitle,
          'markdown_content': markdownContent,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .select(_columns)
        .single();
    _requireAccount(accountId);
    return WorkspaceNote.fromJson(row);
  }

  Future<WorkspaceNote> getOrCreateDailyNote({
    required DateTime localDate,
    String? projectId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final dateKey = formatWorkspaceDateKey(localDate);
    final response = await _client.rpc(
      'get_or_create_workspace_daily_note',
      params: {'p_daily_note_date': dateKey, 'p_project_id': projectId},
    );
    _requireAccount(accountId);
    if (response is! Map) throw StateError('The daily Note is unavailable.');
    final note = WorkspaceNote.fromJson(Map<String, dynamic>.from(response));
    if (note.dailyNoteDate != dateKey ||
        note.projectId != projectId ||
        note.deletedAt != null ||
        (projectId == null && note.ownerUserId != accountId)) {
      throw StateError('The daily Note is unavailable.');
    }
    return note;
  }

  Future<List<WorkspaceNoteTemplate>> listTemplates({
    String? projectId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = projectId == null
        ? await _client
              .from('workspace_note_templates')
              .select(_templateColumns)
              .isFilter('project_id', null)
              .eq('owner_user_id', accountId)
              .order('updated_at', ascending: false)
        : await _client
              .from('workspace_note_templates')
              .select(_templateColumns)
              .eq('project_id', projectId)
              .order('updated_at', ascending: false);
    _requireAccount(accountId);
    final templates = rows
        .map((row) => WorkspaceNoteTemplate.fromJson(row))
        .toList(growable: false);
    if (templates.any(
      (template) =>
          template.projectId != projectId ||
          (projectId == null && template.ownerUserId != accountId),
    )) {
      throw StateError('Template scope changed.');
    }
    return templates;
  }

  Future<WorkspaceNoteTemplate> createTemplate({
    required String title,
    required String markdownContent,
    String? projectId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title');
    }
    await _requireProjectEdit(projectId, accountId);
    final now = DateTime.now().toUtc();
    final row = await _client
        .from('workspace_note_templates')
        .insert({
          'id': const Uuid().v4(),
          'owner_user_id': accountId,
          'created_by': accountId,
          'project_id': projectId,
          'title': normalizedTitle,
          'markdown_content': markdownContent,
          'revision': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .select(_templateColumns)
        .single();
    _requireAccount(accountId);
    final template = WorkspaceNoteTemplate.fromJson(row);
    if (template.projectId != projectId ||
        template.ownerUserId != accountId ||
        template.createdBy != accountId) {
      throw StateError('Template scope changed.');
    }
    return template;
  }

  Future<WorkspaceNoteTemplate> updateTemplate(
    WorkspaceNoteTemplate template, {
    required String title,
    required String markdownContent,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title');
    }
    if (template.projectId == null && template.ownerUserId != accountId) {
      throw const WorkspaceNoteTemplateUnavailableException();
    }
    await _requireProjectEdit(template.projectId, accountId);
    var update = _client
        .from('workspace_note_templates')
        .update({
          'title': normalizedTitle,
          'markdown_content': markdownContent,
          'revision': template.revision + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', template.id)
        .eq('revision', template.revision)
        .eq('owner_user_id', template.ownerUserId)
        .eq('created_by', template.createdBy);
    update = template.projectId == null
        ? update.isFilter('project_id', null)
        : update.eq('project_id', template.projectId!);
    final row = await update.select(_templateColumns).maybeSingle();
    _requireAccount(accountId);
    if (row == null) {
      final current = await _getTemplate(template.id, accountId);
      if (current == null ||
          current.projectId != template.projectId ||
          current.ownerUserId != template.ownerUserId ||
          current.createdBy != template.createdBy) {
        throw const WorkspaceNoteTemplateUnavailableException();
      }
      throw const WorkspaceNoteTemplateConflictException();
    }
    final updated = WorkspaceNoteTemplate.fromJson(row);
    if (updated.projectId != template.projectId ||
        updated.ownerUserId != template.ownerUserId ||
        updated.createdBy != template.createdBy) {
      throw const WorkspaceNoteTemplateUnavailableException();
    }
    return updated;
  }

  Future<void> deleteTemplate({
    required WorkspaceNoteTemplate template,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (template.projectId == null && template.ownerUserId != accountId) {
      throw const WorkspaceNoteTemplateUnavailableException();
    }
    await _requireProjectEdit(template.projectId, accountId);
    var delete = _client
        .from('workspace_note_templates')
        .delete()
        .eq('id', template.id)
        .eq('revision', template.revision)
        .eq('owner_user_id', template.ownerUserId)
        .eq('created_by', template.createdBy);
    delete = template.projectId == null
        ? delete.isFilter('project_id', null)
        : delete.eq('project_id', template.projectId!);
    final row = await delete.select('id').maybeSingle();
    _requireAccount(accountId);
    if (row != null) return;
    final current = await _getTemplate(template.id, accountId);
    if (current == null ||
        current.projectId != template.projectId ||
        current.ownerUserId != template.ownerUserId ||
        current.createdBy != template.createdBy) {
      throw const WorkspaceNoteTemplateUnavailableException();
    }
    throw const WorkspaceNoteTemplateConflictException();
  }

  Future<WorkspaceNoteTemplate?> _getTemplate(
    String templateId,
    String accountId,
  ) async {
    final row = await _client
        .from('workspace_note_templates')
        .select(_templateColumns)
        .eq('id', templateId)
        .maybeSingle();
    _requireAccount(accountId);
    return row == null ? null : WorkspaceNoteTemplate.fromJson(row);
  }

  Future<List<WorkspaceNote>> importNotes({
    required List<PreparedNoteImport> notes,
    required String? projectId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (notes.isEmpty || notes.length > NotesImportService.maxFiles) {
      throw ArgumentError.value(
        notes.length,
        'notes',
        'Must contain 1–100 notes.',
      );
    }
    await _requireProjectEdit(projectId, accountId);
    final noteIds = <String>{};
    final titles = <String>{};
    final folderPaths = <String>{};
    for (final note in notes) {
      if (note.newId.isEmpty ||
          !noteIds.add(note.newId) ||
          note.title.trim().isEmpty ||
          !titles.add(note.title.trim().toLowerCase()) ||
          utf8.encode(note.markdown).length >
              NotesImportService.maxMarkdownBytes) {
        throw ArgumentError.value(
          note,
          'notes',
          'Contains invalid or duplicate notes.',
        );
      }
      final folderPath = note.folderPath;
      if (folderPath != null) {
        final segments = folderPath.split('/');
        if (folderPath.isEmpty ||
            folderPath.startsWith('/') ||
            folderPath.contains('\\') ||
            folderPath.contains(':') ||
            segments.any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
          throw ArgumentError.value(
            folderPath,
            'folderPath',
            'Must be a safe relative path.',
          );
        }
        folderPaths.add(folderPath);
      }
    }

    final response = await _client.rpc(
      'import_workspace_notes_batch',
      params: {
        'p_notes': [
          for (final note in notes)
            {
              'id': note.newId,
              'title': note.title.trim(),
              'markdown_content': note.markdown,
              'folder_path': note.folderPath,
            },
        ],
        'p_folders': folderPaths.toList()..sort(),
        'p_project_id': projectId,
      },
    );
    _requireAccount(accountId);
    if (response is! List || response.length != notes.length) {
      throw StateError('The import response did not match the accepted notes.');
    }
    return response
        .map(
          (row) =>
              WorkspaceNote.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<WorkspaceNote>> renameLegacyUntitledNotes({
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = await _client
        .from('workspace_notes')
        .select(_columns)
        .eq('owner_user_id', accountId)
        .isFilter('deleted_at', null)
        .eq('title', 'Untitled Note');
    _requireAccount(accountId);
    final candidates = rows
        .map((row) => WorkspaceNote.fromJson(row))
        .toList(growable: false);
    final renamed = <WorkspaceNote>[];
    for (final note in candidates) {
      final updatedTitle = formatWorkspaceTimestamp(note.createdAt);
      final row = await _client
          .from('workspace_notes')
          .update({'title': updatedTitle, 'revision': note.revision + 1})
          .eq('id', note.id)
          .eq('owner_user_id', accountId)
          .eq('revision', note.revision)
          .eq('title', 'Untitled Note')
          .select(_columns)
          .maybeSingle();
      _requireAccount(accountId);
      if (row != null) renamed.add(WorkspaceNote.fromJson(row));
    }
    return renamed;
  }

  Future<List<WorkspaceNote>> renameWithLinks({
    required WorkspaceNote target,
    required String title,
    required List<WorkspaceNote> snapshot,
    required Map<String, String> markdownReplacements,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final normalizedTitle = title.trim();
    await _requireProjectEdit(target.projectId, accountId);
    if ((target.projectId == null && target.ownerUserId != accountId) ||
        target.deletedAt != null) {
      throw ArgumentError.value(
        target.id,
        'target',
        'Must be an active owned note.',
      );
    }
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be empty.');
    }

    final snapshotById = <String, WorkspaceNote>{};
    for (final note in snapshot) {
      if ((note.projectId == null && note.ownerUserId != accountId) ||
          !notesShareLinkScope(target, note) ||
          note.deletedAt != null) {
        throw ArgumentError.value(
          snapshot,
          'snapshot',
          'Must contain active owned notes only.',
        );
      }
      if (snapshotById.containsKey(note.id)) {
        throw ArgumentError.value(
          snapshot,
          'snapshot',
          'Note IDs must be unique.',
        );
      }
      snapshotById[note.id] = note;
    }
    final snapshotTarget = snapshotById[target.id];
    if (snapshotTarget == null ||
        snapshotTarget.revision != target.revision ||
        snapshotTarget.title != target.title ||
        snapshotTarget.markdownContent != target.markdownContent) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'Must include the current target note.',
      );
    }
    final plan = planWorkspaceNoteRename(
      activeNotes: snapshot,
      targetId: target.id,
      requestedTitle: normalizedTitle,
    );
    if (plan.ambiguousSourceIds.isNotEmpty ||
        plan.markdownReplacements.length != markdownReplacements.length ||
        plan.markdownReplacements.entries.any(
          (entry) => markdownReplacements[entry.key] != entry.value,
        )) {
      throw ArgumentError.value(
        markdownReplacements,
        'markdownReplacements',
        'Must match the deterministic rename plan for this snapshot.',
      );
    }

    final sourceUpdates = <Map<String, Object>>[];
    for (final replacement in markdownReplacements.entries) {
      final source = snapshotById[replacement.key];
      if (source == null || replacement.value == source.markdownContent) {
        throw ArgumentError.value(
          markdownReplacements,
          'markdownReplacements',
          'Must contain changed Markdown for active snapshot notes only.',
        );
      }
      sourceUpdates.add({
        'id': source.id,
        'revision': source.revision,
        'markdown_content': replacement.value,
      });
    }
    sourceUpdates.sort(
      (a, b) => (a['id']! as String).compareTo(b['id']! as String),
    );
    final snapshotPayload = snapshot
        .map((note) => {'id': note.id, 'revision': note.revision})
        .toList(growable: false);

    try {
      final response = await _client.rpc(
        'rename_workspace_notes_with_links',
        params: {
          'p_target_id': target.id,
          'p_expected_revision': target.revision,
          'p_title': normalizedTitle,
          'p_snapshot': snapshotPayload,
          'p_source_updates': sourceUpdates,
        },
      );
      _requireAccount(accountId);
      if (response is! List) {
        throw const FormatException('Rename RPC returned an invalid response.');
      }
      final updated = response
          .map(
            (row) =>
                WorkspaceNote.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
      final expectedIds = {target.id, ...markdownReplacements.keys};
      final returnedIds = updated.map((note) => note.id).toSet();
      if (updated.length != expectedIds.length ||
          returnedIds.length != expectedIds.length ||
          !returnedIds.containsAll(expectedIds)) {
        throw const FormatException(
          'Rename RPC returned an incomplete result.',
        );
      }
      for (final note in updated) {
        final previous = snapshotById[note.id]!;
        final expectedTitle = note.id == target.id
            ? normalizedTitle
            : previous.title;
        final expectedMarkdown =
            markdownReplacements[note.id] ?? previous.markdownContent;
        if (note.ownerUserId != previous.ownerUserId ||
            note.projectId != previous.projectId ||
            note.folderId != previous.folderId ||
            note.createdBy != previous.createdBy ||
            !notesShareLinkScope(target, note) ||
            note.deletedAt != null ||
            note.revision != previous.revision + 1 ||
            note.title != expectedTitle ||
            note.markdownContent != expectedMarkdown) {
          throw const FormatException(
            'Rename RPC returned an invalid note row.',
          );
        }
      }
      return updated;
    } on PostgrestException catch (error) {
      _requireAccount(accountId);
      if (error.message == 'workspace_notes_conflict') {
        throw const WorkspaceNoteRenameConflictException();
      }
      if (error.message == 'workspace_notes_unavailable') {
        throw const WorkspaceNoteRenameUnavailableException();
      }
      rethrow;
    }
  }

  Future<WorkspaceNoteSaveOutcome> save(
    WorkspaceNote note, {
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (note.projectId == null && note.ownerUserId != accountId) {
      throw StateError('A private note can only be saved by its owner.');
    }
    await _requireProjectEdit(note.projectId, accountId);
    final row = await _client
        .from('workspace_notes')
        .update({
          'title': note.title.trim().isEmpty
              ? 'Untitled Note'
              : note.title.trim(),
          'markdown_content': note.markdownContent,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'revision': note.revision + 1,
        })
        .eq('id', note.id)
        .eq('revision', note.revision)
        .isFilter('deleted_at', null)
        .select(_columns)
        .maybeSingle();
    _requireAccount(accountId);
    if (row != null) {
      return WorkspaceNoteSaveSuccess(WorkspaceNote.fromJson(row));
    }
    final remoteRow = await _client
        .from('workspace_notes')
        .select(_columns)
        .eq('id', note.id)
        .maybeSingle();
    _requireAccount(accountId);
    if (remoteRow == null) {
      return const WorkspaceNoteSaveUnavailable();
    }
    final remote = WorkspaceNote.fromJson(remoteRow);
    if (remote.deletedAt != null) {
      return const WorkspaceNoteSaveUnavailable();
    }
    if (remote.revision != note.revision) {
      return WorkspaceNoteSaveConflict(remote);
    }
    return const WorkspaceNoteSaveUnavailable();
  }

  Future<List<WorkspaceNoteFolder>> listFolders({
    String? projectId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    var query = _client.from('workspace_note_folders').select(_folderColumns);
    query = projectId == null
        ? query.isFilter('project_id', null).eq('owner_user_id', accountId)
        : query.eq('project_id', projectId);
    final rows = await query.order('sort_order').order('name');
    _requireAccount(accountId);
    return rows
        .map((row) => WorkspaceNoteFolder.fromJson(row))
        .toList(growable: false);
  }

  Future<WorkspaceNoteFolder> createFolder({
    required String name,
    String? projectId,
    String? parentFolderId,
    int sortOrder = 0,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    await _requireProjectEdit(projectId, accountId);
    if (parentFolderId != null) {
      final parent = await _client
          .from('workspace_note_folders')
          .select('id, owner_user_id, project_id')
          .eq('id', parentFolderId)
          .maybeSingle();
      _requireAccount(accountId);
      if (parent == null ||
          parent['project_id'] != projectId ||
          (projectId == null && parent['owner_user_id'] != accountId)) {
        throw StateError('Folder scope mismatch.');
      }
    }
    final row = await _client
        .from('workspace_note_folders')
        .insert({
          'owner_user_id': accountId,
          'project_id': projectId,
          'parent_folder_id': parentFolderId,
          'name': name.trim(),
          'sort_order': sortOrder,
        })
        .select(_folderColumns)
        .single();
    _requireAccount(accountId);
    return WorkspaceNoteFolder.fromJson(row);
  }

  Future<void> moveNoteToFolder({
    required String noteId,
    String? folderId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final note = await _client
        .from('workspace_notes')
        .select('id, owner_user_id, project_id')
        .eq('id', noteId)
        .maybeSingle();
    _requireAccount(accountId);
    if (note == null ||
        (note['project_id'] == null && note['owner_user_id'] != accountId)) {
      throw StateError('Note unavailable.');
    }
    await _requireProjectEdit(note['project_id'] as String?, accountId);
    if (folderId != null) {
      final folder = await _client
          .from('workspace_note_folders')
          .select('id, owner_user_id, project_id')
          .eq('id', folderId)
          .maybeSingle();
      _requireAccount(accountId);
      if (folder == null ||
          folder['project_id'] != note['project_id'] ||
          (note['project_id'] == null &&
              folder['owner_user_id'] != accountId)) {
        throw StateError('Folder scope mismatch.');
      }
    }
    final updated = await _client
        .from('workspace_notes')
        .update({'folder_id': folderId})
        .eq('id', noteId)
        .select('id')
        .maybeSingle();
    _requireAccount(accountId);
    if (updated == null) throw StateError('Note unavailable or changed.');
  }

  Future<void> renameFolder({
    required String folderId,
    required String name,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    final folder = await _client
        .from('workspace_note_folders')
        .select('id, owner_user_id, project_id')
        .eq('id', folderId)
        .maybeSingle();
    _requireAccount(accountId);
    if (folder == null ||
        (folder['project_id'] == null &&
            folder['owner_user_id'] != accountId)) {
      throw StateError('Folder unavailable.');
    }
    await _requireProjectEdit(folder['project_id'] as String?, accountId);
    final updated = await _client
        .from('workspace_note_folders')
        .update({'name': normalizedName})
        .eq('id', folderId)
        .select('id')
        .maybeSingle();
    _requireAccount(accountId);
    if (updated == null) throw StateError('Folder unavailable or changed.');
  }

  Future<void> moveFolder({
    required String folderId,
    String? parentFolderId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final row = await _client
        .from('workspace_note_folders')
        .select('id, owner_user_id, project_id')
        .eq('id', folderId)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null ||
        (row['project_id'] == null && row['owner_user_id'] != accountId)) {
      throw StateError('Folder unavailable.');
    }
    await _requireProjectEdit(row['project_id'] as String?, accountId);
    var ancestorId = parentFolderId;
    final visited = <String>{};
    while (ancestorId != null) {
      if (ancestorId == folderId || !visited.add(ancestorId)) {
        throw StateError('Folder hierarchy cannot contain a cycle.');
      }
      final ancestor = await _client
          .from('workspace_note_folders')
          .select('id, owner_user_id, project_id, parent_folder_id')
          .eq('id', ancestorId)
          .maybeSingle();
      _requireAccount(accountId);
      if (ancestor == null ||
          ancestor['project_id'] != row['project_id'] ||
          (row['project_id'] == null &&
              ancestor['owner_user_id'] != accountId)) {
        throw StateError('Folder scope mismatch.');
      }
      ancestorId = ancestor['parent_folder_id'] as String?;
    }
    final updated = await _client
        .from('workspace_note_folders')
        .update({'parent_folder_id': parentFolderId})
        .eq('id', folderId)
        .select('id')
        .maybeSingle();
    _requireAccount(accountId);
    if (updated == null) throw StateError('Folder unavailable or changed.');
  }

  Future<void> deleteFolder({
    required String folderId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final folder = await _client
        .from('workspace_note_folders')
        .select('id, owner_user_id, project_id')
        .eq('id', folderId)
        .maybeSingle();
    _requireAccount(accountId);
    if (folder == null) return;
    if (folder['project_id'] == null && folder['owner_user_id'] != accountId) {
      throw StateError('Folder unavailable.');
    }
    await _requireProjectEdit(folder['project_id'] as String?, accountId);
    final deleted = await _client
        .from('workspace_note_folders')
        .delete()
        .eq('id', folderId)
        .select('id')
        .maybeSingle();
    _requireAccount(accountId);
    if (deleted == null) throw StateError('Folder unavailable or changed.');
  }

  Future<void> setPinned({
    required String noteId,
    required bool pinned,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (pinned) {
      await _client.from('workspace_note_preferences').upsert({
        'user_id': accountId,
        'note_id': noteId,
      }, onConflict: 'user_id,note_id');
    } else {
      await _client
          .from('workspace_note_preferences')
          .delete()
          .eq('user_id', accountId)
          .eq('note_id', noteId);
    }
    _requireAccount(accountId);
  }

  Future<List<WorkspaceNote>> listPinnedNotes({
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = await _client
        .from('workspace_note_preferences')
        .select('note:workspace_notes($_columns)')
        .eq('user_id', accountId);
    _requireAccount(accountId);
    return rows
        .map(
          (row) => WorkspaceNote.fromJson(
            Map<String, dynamic>.from(row['note'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<String?> setNoteProject({
    required String noteId,
    required String? projectId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final note = await _client
        .from('workspace_notes')
        .select('id, owner_user_id, project_id')
        .eq('id', noteId)
        .maybeSingle();
    _requireAccount(accountId);
    if (note == null) throw StateError('Note unavailable.');
    if (note['project_id'] == projectId) return null;
    if (note['project_id'] == null && note['owner_user_id'] != accountId) {
      throw StateError('Only the note owner may link it.');
    }
    if (note['project_id'] != null) {
      final isOwner = await _client.rpc(
        'is_project_owner',
        params: {'p_project_id': note['project_id']},
      );
      _requireAccount(accountId);
      if (isOwner != true) {
        throw StateError(
          'Only the current project owner may relink this note.',
        );
      }
    }
    if (projectId != null) {
      final canEdit = await _client.rpc(
        'can_edit_project',
        params: {'p_project_id': projectId},
      );
      _requireAccount(accountId);
      if (canEdit != true) {
        throw StateError('Project edit membership required.');
      }
    }
    final jobId = await _client.rpc(
      'request_workspace_note_attachment_scope_change',
      params: {'p_note_id': noteId, 'p_target_project_id': projectId},
    );
    _requireAccount(accountId);
    if (jobId == null) return null;
    if (jobId is String && jobId.isNotEmpty) return jobId;
    throw const FormatException('Note scope change response is invalid.');
  }

  Future<bool> canManageNoteScopeChange({
    required String noteId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final existingJob = await getNoteScopeChangeStatus(
      noteId: noteId,
      expectedAccountId: accountId,
    );
    if (existingJob != null &&
        existingJob.status != WorkspaceNoteScopeChangeStatus.complete) {
      return true;
    }

    final note = await _client
        .from('workspace_notes')
        .select('owner_user_id, project_id, deleted_at')
        .eq('id', noteId)
        .maybeSingle();
    _requireAccount(accountId);
    if (note == null || note['deleted_at'] != null) return false;
    final projectId = note['project_id'];
    if (projectId == null) return note['owner_user_id'] == accountId;
    if (projectId is! String || projectId.isEmpty) return false;

    final isOwner = await _client.rpc(
      'is_project_owner',
      params: {'p_project_id': projectId},
    );
    _requireAccount(accountId);
    return isOwner == true;
  }

  Future<List<WorkspaceNoteProjectScope>> listEditableNoteProjectScopes({
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final projectRows = await _client
        .from('projects')
        .select('id, name, owner_id')
        .order('name');
    _requireAccount(accountId);

    final memberships = await _client
        .from('workspace_members')
        .select('project_id, role')
        .eq('user_id', accountId)
        .inFilter('role', ['owner', 'editor']);
    _requireAccount(accountId);
    final editableIds = memberships
        .where((row) => row['role'] == 'owner' || row['role'] == 'editor')
        .where((row) => row['project_id'] is String)
        .map((row) => row['project_id'] as String)
        .toSet();

    return projectRows
        .where((row) {
          final projectId = row['id'];
          return projectId is String &&
              (row['owner_id'] == accountId || editableIds.contains(projectId));
        })
        .map((row) {
          final projectId = row['id'] as String;
          final name = row['name'];
          return WorkspaceNoteProjectScope(
            id: projectId,
            name: name is String && name.trim().isNotEmpty ? name : projectId,
          );
        })
        .toList(growable: false);
  }

  Future<WorkspaceNoteScopeChangeJob?> getNoteScopeChangeStatus({
    required String noteId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final row = await _client
        .from('workspace_note_attachment_rehome_jobs')
        .select('id, requested_by, status, attempt_count, last_error_code')
        .eq('job_kind', 'note_scope_change')
        .eq('note_id', noteId)
        .eq('requested_by', accountId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) return null;
    if (row['requested_by'] != accountId) {
      throw StateError('Note scope change is unavailable.');
    }
    return WorkspaceNoteScopeChangeJob.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> retryNoteScopeChange({
    required String jobId,
    String? expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (jobId.trim().isEmpty) {
      throw ArgumentError.value(jobId, 'jobId');
    }
    await _client.rpc(
      'retry_workspace_note_attachment_rehome',
      params: {'p_job_id': jobId},
    );
    _requireAccount(accountId);
  }

  Future<WorkspaceNote> get(String noteId, {String? expectedAccountId}) async {
    final accountId = _requireAccount(expectedAccountId);
    final row = await _client
        .from('workspace_notes')
        .select(_columns)
        .eq('id', noteId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) throw StateError('The note is unavailable.');
    return WorkspaceNote.fromJson(row);
  }
}
