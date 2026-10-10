import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds persistent collaboration member metadata and safe RPCs', () {
    final sql = File(
      'supabase/migrations/20260910000001_collaboration_members_presence.sql',
    ).readAsStringSync();

    expect(sql, contains('add column if not exists display_name'));
    expect(sql, contains('add column if not exists avatar_url'));
    expect(sql, contains('add column if not exists last_seen_at'));
    expect(
      sql,
      contains(
        'create or replace function public.upsert_workspace_member_profile',
      ),
    );
    expect(
      sql,
      contains('create or replace function public.touch_workspace_member'),
    );
    expect(
      sql,
      contains('create or replace function public.join_collaboration_room('),
    );
    expect(sql, contains('p_display_name text default'));
    expect(
      sql,
      contains(
        'revoke execute on function public.join_collaboration_room(text, text)',
      ),
    );
    expect(sql, contains("role = 'owner'"));
  });

  test('preserves custom display names when joining an existing room', () {
    final sql = File(
      'supabase/migrations/20260909000002_preserve_collaboration_display_names.sql',
    ).readAsStringSync();

    expect(sql, contains('workspace_members.display_name'));
    expect(sql, contains('then excluded.display_name'));
    expect(sql, contains("'collaborator'"));
    expect(
      sql,
      contains('create or replace function public.join_collaboration_room('),
    );
  });

  test('validates display names on the server', () {
    final sql = File(
      'supabase/migrations/20260909000004_validate_collaboration_display_names.sql',
    ).readAsStringSync();

    expect(sql, contains("raw_name ~ '[[:cntrl:]]'"));
    expect(sql, contains('char_length(normalized_name) < 2'));
    expect(sql, contains('char_length(normalized_name) > 32'));
    expect(
      sql,
      contains("regexp_replace(trim(raw_name), '[[:space:]]+', ' ', 'g')"),
    );
    expect(
      sql,
      contains('create or replace function public.join_collaboration_room('),
    );
  });

  test('keeps CRDT retries idempotent without requiring an update policy', () {
    final sql = File(
      'supabase/migrations/20260909000005_fix_crdt_append_idempotency.sql',
    ).readAsStringSync();

    expect(sql, contains('on conflict (project_id, op_id) do nothing'));
    expect(sql, contains('if result.op_id is null then'));
    expect(sql, isNot(contains('do update')));
  });
}
