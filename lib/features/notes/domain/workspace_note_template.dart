import 'package:flutter/foundation.dart';

@immutable
class WorkspaceNoteTemplate {
  const WorkspaceNoteTemplate({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.markdownContent,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.projectId,
    String? createdBy,
  }) : createdBy = createdBy ?? ownerUserId;

  final String id;
  final String ownerUserId;
  final String? projectId;
  final String title;
  final String markdownContent;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  WorkspaceNoteTemplate copyWith({
    String? title,
    String? markdownContent,
    int? revision,
    DateTime? updatedAt,
  }) => WorkspaceNoteTemplate(
    id: id,
    ownerUserId: ownerUserId,
    projectId: projectId,
    title: title ?? this.title,
    markdownContent: markdownContent ?? this.markdownContent,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdBy: createdBy,
  );

  factory WorkspaceNoteTemplate.fromJson(Map<String, dynamic> json) =>
      WorkspaceNoteTemplate(
        id: json['id'] as String,
        ownerUserId: json['owner_user_id'] as String,
        projectId: json['project_id'] as String?,
        title: json['title'] as String,
        markdownContent: json['markdown_content'] as String,
        revision: json['revision'] as int? ?? 1,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
        createdBy:
            json['created_by'] as String? ?? json['owner_user_id'] as String,
      );
}

class WorkspaceNoteTemplateConflictException implements Exception {
  const WorkspaceNoteTemplateConflictException();
}

class WorkspaceNoteTemplateUnavailableException implements Exception {
  const WorkspaceNoteTemplateUnavailableException();
}
