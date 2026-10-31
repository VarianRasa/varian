import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/note_crdt_document.dart';
import '../domain/note_crdt_operation.dart';
import '../../collaboration/domain/crdt_primitives.dart';
import 'notes_sync_repository.dart';

class SupabaseNotesSyncTransport implements NotesSyncTransport {
  const SupabaseNotesSyncTransport(this.client);

  final SupabaseClient client;

  Map<String, dynamic>? _operation(Map<String, dynamic> entry) {
    final raw = entry['operation'] ?? entry;
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  void _assertAccount(String accountId) {
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous || user.id != accountId) {
      throw StateError('Notes account changed during sync.');
    }
  }

  @override
  Future<bool> canReplay(String accountId, Map<String, dynamic> entry) async {
    final user = client.auth.currentUser;
    final operation = _operation(entry);
    final noteId = entry['noteId'];
    if (user == null ||
        user.isAnonymous ||
        user.id != accountId ||
        operation == null ||
        noteId is! String ||
        operation['noteId'] != noteId ||
        operation['opId'] != entry['opId']) {
      return false;
    }
    final projectId = entry['projectId'];
    if (entry['kind'] == 'note_mutation' && operation['action'] == 'create') {
      if (projectId is String) {
        final allowed = await client.rpc(
          'can_edit_project',
          params: {'p_project_id': projectId},
        );
        _assertAccount(accountId);
        return allowed == true;
      }
      return operation['ownerUserId'] == accountId;
    }
    final row = await client
        .from('workspace_notes')
        .select('owner_user_id, project_id')
        .eq('id', noteId)
        .maybeSingle();
    _assertAccount(accountId);
    if (row == null) return false;
    if (projectId is String) {
      if (row['project_id'] != projectId) return false;
      final allowed = await client.rpc(
        'can_edit_project',
        params: {'p_project_id': projectId},
      );
      _assertAccount(accountId);
      return allowed == true;
    }
    return row['project_id'] == null && row['owner_user_id'] == accountId;
  }

  Future<void> _replayNoteMutation(
    String accountId,
    Map<String, dynamic> entry,
  ) async {
    final action = entry['action'];
    final noteId = entry['noteId'] as String;
    if (action == 'create') {
      final ownerUserId = entry['ownerUserId'];
      final title = entry['title'];
      final markdown = entry['markdownContent'];
      if (ownerUserId != accountId || title is! String || markdown is! String) {
        throw const FormatException();
      }
      await client
          .from('workspace_notes')
          .upsert(
            {
              'id': noteId,
              'owner_user_id': accountId,
              'created_by': accountId,
              'project_id': entry['projectId'],
              'folder_id': entry['folderId'],
              'title': title,
              'markdown_content': markdown,
              'revision': 1,
            },
            onConflict: 'id',
            ignoreDuplicates: true,
          );
      _assertAccount(accountId);
      final created = await client
          .from('workspace_notes')
          .select('owner_user_id, project_id, title, markdown_content')
          .eq('id', noteId)
          .maybeSingle();
      _assertAccount(accountId);
      if (created == null ||
          created['owner_user_id'] != accountId ||
          created['project_id'] != entry['projectId'] ||
          created['title'] != title ||
          created['markdown_content'] != markdown) {
        throw StateError('Notes create conflict.');
      }
      return;
    }

    final current = await client
        .from('workspace_notes')
        .select(
          'owner_user_id, project_id, title, markdown_content, revision, deleted_at',
        )
        .eq('id', noteId)
        .maybeSingle();
    _assertAccount(accountId);
    if (current == null ||
        current['project_id'] != entry['projectId'] ||
        (entry['projectId'] == null && current['owner_user_id'] != accountId)) {
      throw StateError('Notes mutation target is missing or changed scope.');
    }
    final revision = (current['revision'] as num).toInt();
    final currentDeleted = current['deleted_at'] != null;
    final desiredTitle = entry['title'];
    final desiredMarkdown = entry['markdownContent'];
    final desiredDeleted = action == 'delete'
        ? true
        : action == 'restore'
        ? false
        : currentDeleted;
    if (action == 'update' &&
        current['title'] == desiredTitle &&
        current['markdown_content'] == desiredMarkdown) {
      return;
    }
    if ((action == 'delete' && currentDeleted) ||
        (action == 'restore' && !currentDeleted)) {
      return;
    }
    if (action != 'update' && action != 'delete' && action != 'restore') {
      throw const FormatException();
    }
    if (revision != entry['expectedRevision']) {
      throw StateError('Notes mutation revision conflict.');
    }
    final patch = <String, Object?>{
      'revision': revision + 1,
      if (action == 'update') ...{
        'title': desiredTitle,
        'markdown_content': desiredMarkdown,
      },
      if (action == 'delete')
        'deleted_at':
            entry['deletedAt'] ?? DateTime.now().toUtc().toIso8601String(),
      if (action == 'restore') 'deleted_at': null,
    };
    await client
        .from('workspace_notes')
        .update(patch)
        .eq('id', noteId)
        .eq('revision', revision);
    _assertAccount(accountId);
    final updated = await client
        .from('workspace_notes')
        .select('title, markdown_content, deleted_at')
        .eq('id', noteId)
        .maybeSingle();
    _assertAccount(accountId);
    if (updated == null ||
        (action == 'update' &&
            (desiredTitle is! String ||
                desiredMarkdown is! String ||
                updated['title'] != desiredTitle ||
                updated['markdown_content'] != desiredMarkdown)) ||
        (updated['deleted_at'] != null) != desiredDeleted) {
      throw StateError('Notes mutation was not applied.');
    }
  }

  @override
  Future<void> replay(String accountId, Map<String, dynamic> entry) async {
    if (!await canReplay(accountId, entry)) {
      throw StateError('Notes access was revoked.');
    }
    _assertAccount(accountId);
    if (entry['kind'] == 'note_mutation') {
      await _replayNoteMutation(accountId, entry);
      return;
    }
    final operationJson = _operation(entry);
    if (operationJson == null) throw const FormatException();
    final operation = NoteCrdtOperation.fromJson(operationJson);
    final noteId = operation.noteId;
    final noteRow = await client
        .from('workspace_notes')
        .select('owner_user_id, project_id, title, markdown_content, revision')
        .eq('id', noteId)
        .single();
    _assertAccount(accountId);
    final snapshot = await client
        .from('workspace_note_crdt_snapshots')
        .select('state_json, version_vector')
        .eq('note_id', noteId)
        .maybeSingle();
    _assertAccount(accountId);
    final document = snapshot?['state_json'] is Map
        ? NoteCrdtDocument.fromSnapshot(
            Map<String, dynamic>.from(snapshot!['state_json'] as Map),
          )
        : NoteCrdtDocument.fromMarkdown(
            noteId,
            noteRow['markdown_content'] as String,
          );
    final delta = await client.rpc(
      'get_workspace_note_crdt_delta',
      params: {
        'p_note_id': noteId,
        'p_since': document.versionVector.toJson(),
        'p_limit': 500,
      },
    );
    _assertAccount(accountId);
    if (delta is! List) throw const FormatException();
    for (final item in delta.whereType<Map>()) {
      document.applyRemoteOperation(
        NoteCrdtOperation.fromJson(Map<String, dynamic>.from(item)),
      );
    }
    final applyStatus = document.applyRemoteOperation(operation);
    if (applyStatus == CrdtApplyStatus.rejected ||
        applyStatus == CrdtApplyStatus.buffered) {
      throw StateError('Notes operation is not causally ready.');
    }
    _assertAccount(accountId);
    await client.rpc(
      'append_workspace_note_crdt_operation',
      params: {'p_note_id': noteId, 'p_operation': operation.toJson()},
    );
    _assertAccount(accountId);
    await client.rpc(
      'materialize_workspace_note_crdt',
      params: {
        'p_note_id': noteId,
        'p_expected_revision': noteRow['revision'],
        'p_markdown_content': document.visibleMarkdown,
        'p_state_json': document.snapshotState(),
        'p_version_vector': document.versionVector.toJson(),
      },
    );
  }
}
