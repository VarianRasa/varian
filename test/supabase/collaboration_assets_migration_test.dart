import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines the shared assets bucket and project-scoped policies', () {
    final sql = File(
      'supabase/migrations/20260908000003_create_collaboration_assets.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains("values ('assets', 'assets', true)"));
    expect(sql, contains('grant select, insert, update on storage.objects'));
    expect(sql, contains('collaboration_assets_read'));
    expect(sql, contains('collaboration_assets_insert'));
    expect(sql, contains('collaboration_assets_update'));
    expect(sql, contains('public.can_read_project'));
    expect(sql, contains('public.can_edit_project'));
  });
}
