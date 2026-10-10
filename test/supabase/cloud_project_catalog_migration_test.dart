import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cloud project catalog adds owner-scoped metadata and pin preferences',
    () {
      final migration = File(
        'supabase/migrations/20261008000000_cloud_project_catalog.sql',
      );
      expect(migration.existsSync(), isTrue);
      final sql = migration.readAsStringSync().toLowerCase();

      expect(sql, contains('add column if not exists name text'));
      expect(sql, contains('add column if not exists created_at'));
      expect(sql, contains('add column if not exists trashed_at'));
      expect(
        sql,
        contains('create table if not exists public.user_project_preferences'),
      );
      expect(sql, contains('enable row level security'));
      expect(sql, contains('user_id = auth.uid()'));
      expect(sql, contains('public.can_read_project(project_id)'));
      expect(
        sql,
        contains('revoke all on public.user_project_preferences from anon'),
      );
      expect(
        sql,
        contains('revoke all on public.user_project_preferences from public'),
      );
    },
  );
}
