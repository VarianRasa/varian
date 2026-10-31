import 'package:flutter/foundation.dart';

@immutable
class WorkspaceNoteFolder {
  const WorkspaceNoteFolder({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.parentFolderId,
  });

  final String id;
  final String ownerUserId;
  final String? projectId;
  final String? parentFolderId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorkspaceNoteFolder.fromJson(Map<String, dynamic> json) =>
      WorkspaceNoteFolder(
        id: json['id'] as String,
        ownerUserId: json['owner_user_id'] as String,
        projectId: json['project_id'] as String?,
        parentFolderId: json['parent_folder_id'] as String?,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      );
}
