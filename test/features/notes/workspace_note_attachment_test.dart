import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note_attachments.dart';

void main() {
  const attachmentId = '123e4567-e89b-12d3-a456-426614174000';
  const ownerId = '223e4567-e89b-12d3-a456-426614174001';
  const noteId = '323e4567-e89b-12d3-a456-426614174002';

  test(
    'parses ready attachment metadata only when ID, path, type, and size agree',
    () {
      final attachment = WorkspaceNoteAttachment.fromJson({
        'id': attachmentId,
        'note_id': noteId,
        'owner_user_id': ownerId,
        'project_id': null,
        'storage_path': 'private/$ownerId/$attachmentId',
        'original_name': 'diagram.png',
        'mime_type': 'image/png',
        'size_bytes': 8,
        'sha256': 'a' * 64,
        'status': 'ready',
      });

      expect(attachment.id, attachmentId);
      expect(attachment.scopeId, 'private:$ownerId');
      expect(attachment.type, WorkspaceNoteAttachmentType.png);
    },
  );

  test('rejects metadata outside the selected note scope', () {
    expect(
      () => WorkspaceNoteAttachment.fromJson({
        'id': attachmentId,
        'note_id': noteId,
        'owner_user_id': ownerId,
        'project_id': 'another-project',
        'storage_path': 'private/$ownerId/$attachmentId',
        'original_name': 'diagram.png',
        'mime_type': 'image/png',
        'size_bytes': 8,
        'sha256': 'a' * 64,
        'status': 'ready',
      }),
      throwsFormatException,
    );
  });

  test('rejects pending, unapproved, and malformed metadata', () {
    final metadata = {
      'id': attachmentId,
      'note_id': noteId,
      'owner_user_id': ownerId,
      'project_id': null,
      'storage_path': 'private/$ownerId/$attachmentId',
      'original_name': 'diagram.png',
      'mime_type': 'image/png',
      'size_bytes': 8,
      'sha256': 'a' * 64,
      'status': 'ready',
    };
    expect(
      () => WorkspaceNoteAttachment.fromJson({
        ...metadata,
        'status': 'pending_upload',
      }),
      throwsFormatException,
    );
    expect(
      () => WorkspaceNoteAttachment.fromJson({
        ...metadata,
        'mime_type': 'image/svg+xml',
      }),
      throwsFormatException,
    );
    expect(
      () => WorkspaceNoteAttachment.fromJson({
        ...metadata,
        'original_name': '../diagram.png',
      }),
      throwsFormatException,
    );
  });
}
