import 'package:flutter/foundation.dart';

@immutable
class WorkspaceNote {
  const WorkspaceNote({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.markdownContent,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.deletedAt,
    this.projectId,
    this.folderId,
    this.dailyNoteDate,
    String? createdBy,
  }) : createdBy = createdBy ?? ownerUserId;

  final String id;
  final String ownerUserId;
  final String title;
  final String markdownContent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final DateTime? deletedAt;
  final String? projectId;
  final String? folderId;
  final String? dailyNoteDate;
  final String createdBy;

  WorkspaceNote copyWith({
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? title,
    String? markdownContent,
    DateTime? updatedAt,
    int? revision,
  }) => WorkspaceNote(
    id: id,
    ownerUserId: ownerUserId,
    title: title ?? this.title,
    markdownContent: markdownContent ?? this.markdownContent,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    projectId: projectId,
    folderId: folderId,
    dailyNoteDate: dailyNoteDate,
    createdBy: createdBy,
  );

  factory WorkspaceNote.fromJson(Map<String, dynamic> json) => WorkspaceNote(
    id: json['id'] as String,
    ownerUserId: json['owner_user_id'] as String,
    title: json['title'] as String,
    markdownContent: json['markdown_content'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    revision: json['revision'] as int? ?? 1,
    projectId: json['project_id'] as String?,
    folderId: json['folder_id'] as String?,
    dailyNoteDate: json['daily_note_date'] as String?,
    createdBy: json['created_by'] as String? ?? json['owner_user_id'] as String,
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
  );
}
