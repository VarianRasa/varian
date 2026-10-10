import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260914050000_create_published_snapshots.sql',
  ).readAsStringSync().toLowerCase();

  test('creates immutable published snapshot storage and link binding', () {
    expect(
      migration,
      contains('create table if not exists public.published_snapshots'),
    );
    expect(migration, contains('unique (project_id, version)'));
    expect(migration, contains('published_snapshot_id text'));
    expect(migration, contains('share_links_published_snapshot_id_fkey'));
    expect(
      migration,
      contains(
        'alter table public.published_snapshots enable row level security',
      ),
    );
  });

  test('publishing RPC enforces owner, access, and password policies', () {
    expect(
      migration,
      contains('create or replace function public.publish_canvas_snapshot'),
    );
    expect(migration, contains('public.is_project_owner(p_project_id)'));
    expect(migration, contains('p_access = \'password\''));
    expect(migration, contains('p_access = \'private\''));
    expect(migration, contains('published_snapshots'));
    expect(migration, contains('revoked_at = now()'));
  });

  test('share reader supports password challenges and snapshot metadata', () {
    expect(
      migration,
      contains(
        'create or replace function public.read_canvas_share(\n  p_project_id text,\n  p_token_hash text,\n  p_password_digest text',
      ),
    );
    expect(migration, contains('requirespassword'));
    expect(migration, contains('v_snapshot.document_data'));
    expect(migration, contains('downloadpolicy'));
    expect(migration, contains('watermarkenabled'));
    expect(
      migration,
      contains(
        'select public.read_canvas_share(p_project_id, p_token_hash, null)',
      ),
    );
  });
}
