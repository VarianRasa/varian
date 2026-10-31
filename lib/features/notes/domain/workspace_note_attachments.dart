import 'dart:convert';

import '../../../domain/utils/mime_signature.dart';
import 'note_markdown_metadata.dart';
import 'workspace_note_links.dart';

const workspaceNoteAttachmentMaxBytes = 25 * 1024 * 1024;

enum WorkspaceNoteAttachmentType {
  png('image/png'),
  jpeg('image/jpeg'),
  gif('image/gif'),
  webp('image/webp'),
  pdf('application/pdf');

  const WorkspaceNoteAttachmentType(this.mimeType);

  final String mimeType;

  static WorkspaceNoteAttachmentType? fromMimeType(String mimeType) =>
      switch (mimeType.trim().toLowerCase()) {
        'image/png' => png,
        'image/jpeg' => jpeg,
        'image/gif' => gif,
        'image/webp' => webp,
        'application/pdf' => pdf,
        _ => null,
      };
}

String workspaceNoteAttachmentStoragePath({
  required String ownerUserId,
  required String? projectId,
  required String attachmentId,
}) {
  final normalizedOwner = ownerUserId.toLowerCase();
  final normalizedAttachment = attachmentId.toLowerCase();
  if (!_uuidPattern.hasMatch(normalizedOwner) ||
      !_uuidPattern.hasMatch(normalizedAttachment) ||
      (projectId != null &&
          (projectId.isEmpty ||
              projectId.length > 128 ||
              projectId.contains('\u0000')))) {
    throw ArgumentError('Attachment path scope is invalid.');
  }
  if (projectId == null) {
    return 'private/$normalizedOwner/$normalizedAttachment';
  }
  return 'project/${_hexEncode(utf8.encode(projectId))}/$normalizedAttachment';
}

class WorkspaceNoteAttachment {
  const WorkspaceNoteAttachment({
    required this.id,
    required this.noteId,
    required this.ownerUserId,
    required this.projectId,
    required this.storagePath,
    required this.originalName,
    required this.type,
    required this.sizeBytes,
    required this.sha256,
  });

  final String id;
  final String noteId;
  final String ownerUserId;
  final String? projectId;
  final String storagePath;
  final String originalName;
  final WorkspaceNoteAttachmentType type;
  final int sizeBytes;
  final String sha256;

  String get scopeId =>
      projectId == null ? 'private:$ownerUserId' : 'project:$projectId';

  factory WorkspaceNoteAttachment.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Attachment $key is invalid.');
      }
      return value;
    }

    final id = requiredString('id').toLowerCase();
    final noteId = requiredString('note_id').toLowerCase();
    final ownerUserId = requiredString('owner_user_id').toLowerCase();
    final projectValue = json['project_id'];
    if (projectValue != null && projectValue is! String) {
      throw const FormatException('Attachment project scope is invalid.');
    }
    final projectId = (projectValue as String?)?.trim();
    final path = requiredString('storage_path');
    final originalName = requiredString('original_name');
    final mimeType = requiredString('mime_type');
    final type = WorkspaceNoteAttachmentType.fromMimeType(mimeType);
    final size = json['size_bytes'];
    final digest = requiredString('sha256');
    final status = json['status'];
    if (!_uuidPattern.hasMatch(id) ||
        !_uuidPattern.hasMatch(noteId) ||
        !_uuidPattern.hasMatch(ownerUserId) ||
        (projectId != null &&
            (projectId.isEmpty ||
                projectId.length > 128 ||
                projectId.contains('\u0000'))) ||
        originalName.trim().isEmpty ||
        originalName.length > 255 ||
        originalName.contains('/') ||
        originalName.codeUnits.contains(92) ||
        originalName.contains('\u0000') ||
        type == null ||
        size is! int ||
        size < 1 ||
        size > workspaceNoteAttachmentMaxBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        status != 'ready') {
      throw const FormatException('Attachment metadata is invalid.');
    }

    final expectedPath = workspaceNoteAttachmentStoragePath(
      ownerUserId: ownerUserId,
      projectId: projectId,
      attachmentId: id,
    );
    if (path != expectedPath) {
      throw const FormatException('Attachment storage scope is invalid.');
    }
    return WorkspaceNoteAttachment(
      id: id,
      noteId: noteId,
      ownerUserId: ownerUserId,
      projectId: projectId,
      storagePath: path,
      originalName: originalName,
      type: type,
      sizeBytes: size,
      sha256: digest,
    );
  }
}

String _hexEncode(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

WorkspaceNoteAttachmentType? detectWorkspaceNoteAttachmentType(
  List<int> bytes,
) {
  if (bytes.isEmpty || bytes.length > workspaceNoteAttachmentMaxBytes) {
    return null;
  }
  for (final type in WorkspaceNoteAttachmentType.values) {
    if (assetBytesMatchMimeSignature(bytes, type.mimeType)) return type;
  }
  return null;
}

class WorkspaceNoteAttachmentEmbed {
  const WorkspaceNoteAttachmentEmbed({
    required this.attachmentId,
    required this.start,
    required this.end,
  });

  final String attachmentId;
  final int start;
  final int end;
}

final RegExp _attachmentEmbedPattern = RegExp(
  r'!\[\[attachment:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\]\]',
);

List<WorkspaceNoteAttachmentEmbed> parseWorkspaceNoteAttachmentEmbeds(
  String markdown,
) {
  final metadata = parseNoteMarkdownMetadata(markdown);
  if (metadata.frontmatterRaw != null && metadata.body == markdown) {
    return const [];
  }

  final bodyStart = markdown.length - metadata.body.length;
  final codeContext = workspaceMarkdownCodeContextMask(markdown);
  final embeds = <WorkspaceNoteAttachmentEmbed>[];
  for (final match in _attachmentEmbedPattern.allMatches(markdown)) {
    if (match.start < bodyStart ||
        codeContext
            .skip(match.start)
            .take(match.end - match.start)
            .any((v) => v) ||
        _isEscaped(markdown, match.start)) {
      continue;
    }
    embeds.add(
      WorkspaceNoteAttachmentEmbed(
        attachmentId: match.group(1)!.toLowerCase(),
        start: match.start,
        end: match.end,
      ),
    );
  }
  return List.unmodifiable(embeds);
}

bool _isEscaped(String source, int offset) {
  var slashCount = 0;
  for (var index = offset - 1; index >= 0 && source[index] == r'\'; index--) {
    slashCount++;
  }
  return slashCount.isOdd;
}
