import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment metadata migration adds review fields and indexes', () {
    final sql = File(
      'supabase/migrations/202609130004_add_comment_review_metadata.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists attachments'));
    expect(sql, contains('add column if not exists labels'));
    expect(sql, contains('add column if not exists assignee_id'));
    expect(sql, contains('add column if not exists due_date'));
    expect(sql, contains('add column if not exists watchers'));
    expect(sql, contains('comments_project_unresolved_idx'));
  });

  test('share function includes comment metadata in legacy fallback', () {
    final sql = File(
      'supabase/migrations/202609130004_add_comment_review_metadata.sql',
    ).readAsStringSync().toLowerCase();
    final shareFunction = sql.substring(
      sql.indexOf('create or replace function public.read_canvas_share'),
    );

    expect(shareFunction, contains("'attachments', comment.attachments"));
    expect(shareFunction, contains("'labels', comment.labels"));
    expect(shareFunction, contains("'duedate', comment.due_date"));
  });
}
