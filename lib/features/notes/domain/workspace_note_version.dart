import 'package:flutter/foundation.dart';

@immutable
class WorkspaceNoteVersion {
  const WorkspaceNoteVersion({
    required this.id,
    required this.noteId,
    required this.revision,
    required this.title,
    required this.markdownContent,
    required this.actorId,
    required this.createdAt,
  });

  final String id;
  final String noteId;
  final int revision;
  final String title;
  final String markdownContent;
  final String? actorId;
  final DateTime createdAt;

  factory WorkspaceNoteVersion.fromJson(Map<String, dynamic> json) =>
      WorkspaceNoteVersion(
        id: json['id'] as String,
        noteId: json['note_id'] as String,
        revision: json['revision'] as int,
        title: json['title'] as String,
        markdownContent: json['markdown_content'] as String,
        actorId: json['actor_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
