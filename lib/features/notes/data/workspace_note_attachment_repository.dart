import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/utils/mime_signature.dart';

import '../domain/workspace_note_attachments.dart';
import 'notes_local_store.dart';

class WorkspaceNoteAttachmentRepository {
  WorkspaceNoteAttachmentRepository({
    required this._client,
    required this._localStore,
    required this._keyForAccount,
  });

  static const bucket = 'workspace-note-assets';

  final SupabaseClient _client;
  final NotesLocalStore _localStore;
  final Future<Uint8List?> Function(String accountId) _keyForAccount;

  Future<WorkspaceNoteAttachment> upload({
    required String accountId,
    required String noteId,
    required String? expectedProjectId,
    required String originalName,
    required Uint8List bytes,
  }) async {
    _requireCurrentAccount(accountId);
    final type = detectWorkspaceNoteAttachmentType(bytes);
    if (type == null) {
      throw const FormatException('Unsupported Notes attachment.');
    }
    final fileName = _validatedFileName(originalName);

    final note = await _client
        .from('workspace_notes')
        .select('id, owner_user_id, project_id, deleted_at')
        .eq('id', noteId)
        .maybeSingle();
    _requireCurrentAccount(accountId);
    if (note == null ||
        note['deleted_at'] != null ||
        note['project_id'] != expectedProjectId ||
        (expectedProjectId == null && note['owner_user_id'] != accountId)) {
      throw const FormatException('Note is unavailable in the selected scope.');
    }

    final ownerUserId = note['owner_user_id'];
    if (ownerUserId is! String) {
      throw const FormatException('Note owner metadata is invalid.');
    }
    final result = await _client.rpc(
      'create_workspace_note_attachment',
      params: {'p_note_id': noteId, 'p_original_name': fileName},
    );
    _requireCurrentAccount(accountId);
    final created = _singleRow(result);
    final attachmentId = created['attachment_id'];
    final storagePath = created['storage_path'];
    if (attachmentId is! String || storagePath is! String) {
      throw const FormatException('Attachment upload initialization failed.');
    }
    final expectedPath = workspaceNoteAttachmentStoragePath(
      ownerUserId: ownerUserId,
      projectId: expectedProjectId,
      attachmentId: attachmentId,
    );
    if (storagePath != expectedPath) {
      throw const FormatException('Attachment upload path is invalid.');
    }

    await _client.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: type.mimeType, upsert: false),
        );
    _requireCurrentAccount(accountId);

    final response = await _client.functions.invoke(
      'notes-attachment-rehome',
      body: {'action': 'finalize_upload', 'attachmentId': attachmentId},
    );
    _requireCurrentAccount(accountId);
    if (response.status < 200 ||
        response.status >= 300 ||
        response.data is! Map ||
        response.data['attachmentId'] != attachmentId ||
        response.data['mimeType'] != type.mimeType ||
        response.data['sizeBytes'] != bytes.length) {
      throw const FormatException('Notes attachment verification failed.');
    }

    final metadata = await _readMetadata(
      accountId: accountId,
      noteId: noteId,
      attachmentId: attachmentId,
      expectedProjectId: expectedProjectId,
    );
    final key = await _keyForAccount(accountId);
    _requireCurrentAccount(accountId);
    if (key != null) {
      await _localStore.saveAttachmentBytes(
        accountId: accountId,
        attachmentId: attachmentId,
        noteId: metadata.noteId,
        scopeId: metadata.scopeId,
        bytes: bytes,
        key: key,
      );
    }
    return metadata;
  }

  Future<List<WorkspaceNoteAttachment>> listForNote({
    required String accountId,
    required String noteId,
    required String? expectedProjectId,
  }) async {
    _requireCurrentAccount(accountId);
    final rows = await _client
        .from('workspace_note_attachments')
        .select()
        .eq('note_id', noteId)
        .eq('status', 'ready')
        .order('created_at');
    _requireCurrentAccount(accountId);
    final attachments = rows
        .map(
          (row) =>
              WorkspaceNoteAttachment.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
    for (final attachment in attachments) {
      if (attachment.projectId != expectedProjectId ||
          (expectedProjectId == null && attachment.ownerUserId != accountId) ||
          attachment.noteId != noteId.toLowerCase()) {
        throw const FormatException(
          'Attachment is outside the selected note scope.',
        );
      }
    }
    return attachments;
  }

  Future<Uint8List> readBytes({
    required String accountId,
    required String noteId,
    required String attachmentId,
    required String? expectedProjectId,
  }) async {
    final metadata = await _readMetadata(
      accountId: accountId,
      noteId: noteId,
      attachmentId: attachmentId,
      expectedProjectId: expectedProjectId,
    );
    final bytes = await _client.storage
        .from(bucket)
        .download(metadata.storagePath);
    _requireCurrentAccount(accountId);
    if (bytes.length != metadata.sizeBytes ||
        !assetBytesMatchMimeSignature(bytes, metadata.type.mimeType) ||
        sha256.convert(bytes).toString() != metadata.sha256) {
      throw const FormatException(
        'Notes attachment bytes failed verification.',
      );
    }
    final key = await _keyForAccount(accountId);
    _requireCurrentAccount(accountId);
    if (key != null) {
      await _localStore.saveAttachmentBytes(
        accountId: accountId,
        attachmentId: attachmentId,
        noteId: metadata.noteId,
        scopeId: metadata.scopeId,
        bytes: bytes,
        key: key,
      );
    }
    return bytes;
  }

  Future<void> delete({
    required String accountId,
    required String noteId,
    required String attachmentId,
    required String? expectedProjectId,
  }) async {
    _requireCurrentAccount(accountId);
    final result = await _client.rpc(
      'begin_workspace_note_attachment_delete',
      params: {'p_note_id': noteId, 'p_attachment_id': attachmentId},
    );
    _requireCurrentAccount(accountId);
    final storagePath = _singleString(result);
    final expectedPath = workspaceNoteAttachmentStoragePath(
      ownerUserId: accountId,
      projectId: expectedProjectId,
      attachmentId: attachmentId,
    );
    if (storagePath != expectedPath) {
      throw const FormatException('Attachment delete path is invalid.');
    }
    await _client.storage.from(bucket).remove([storagePath]);
    _requireCurrentAccount(accountId);
    await _client.rpc(
      'finish_workspace_note_attachment_delete',
      params: {'p_note_id': noteId, 'p_attachment_id': attachmentId},
    );
    _requireCurrentAccount(accountId);
    await _localStore.removeAttachmentBytes(
      accountId: accountId,
      attachmentId: attachmentId,
    );
  }

  Future<Uint8List?> readCachedBytes({
    required String accountId,
    required String noteId,
    required String noteMarkdown,
    required String attachmentId,
    required String? projectId,
  }) async {
    _requireCurrentAccount(accountId);
    if (!parseWorkspaceNoteAttachmentEmbeds(
      noteMarkdown,
    ).any((embed) => embed.attachmentId == attachmentId.toLowerCase())) {
      return null;
    }
    final key = await _keyForAccount(accountId);
    _requireCurrentAccount(accountId);
    if (key == null) return null;
    final scopeId = projectId == null
        ? 'private:$accountId'
        : 'project:$projectId';
    return _localStore.readAttachmentBytes(
      accountId: accountId,
      attachmentId: attachmentId,
      noteId: noteId,
      scopeId: scopeId,
      key: key,
    );
  }

  Future<WorkspaceNoteAttachment> _readMetadata({
    required String accountId,
    required String noteId,
    required String attachmentId,
    required String? expectedProjectId,
  }) async {
    _requireCurrentAccount(accountId);
    final row = await _client
        .from('workspace_note_attachments')
        .select()
        .eq('id', attachmentId)
        .eq('note_id', noteId)
        .eq('status', 'ready')
        .maybeSingle();
    _requireCurrentAccount(accountId);
    if (row == null) throw const FormatException('Attachment is unavailable.');
    final attachment = WorkspaceNoteAttachment.fromJson(row);
    if (attachment.projectId != expectedProjectId ||
        (expectedProjectId == null && attachment.ownerUserId != accountId) ||
        attachment.noteId != noteId.toLowerCase()) {
      throw const FormatException(
        'Attachment is outside the selected note scope.',
      );
    }
    return attachment;
  }

  void _requireCurrentAccount(String accountId) {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous || user.id != accountId) {
      throw const FormatException(
        'Notes account changed during attachment operation.',
      );
    }
  }

  String _singleString(dynamic result) {
    if (result is String && result.isNotEmpty) return result;
    if (result is List && result.length == 1 && result.single is String) {
      return result.single as String;
    }
    throw const FormatException('Attachment delete initialization failed.');
  }

  Map<String, dynamic> _singleRow(dynamic result) {
    if (result is Map<String, dynamic>) return result;
    if (result is List && result.length == 1 && result.single is Map) {
      return Map<String, dynamic>.from(result.single as Map);
    }
    throw const FormatException('Attachment upload initialization failed.');
  }

  String _validatedFileName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.length > 255 ||
        name.contains('/') ||
        name.codeUnits.contains(92) ||
        name.contains('\u0000')) {
      throw const FormatException('Attachment file name is invalid.');
    }
    return name;
  }
}
