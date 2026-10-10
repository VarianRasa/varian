import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production hardening revokes anonymous access to core project data',
    () {
      final migration = File(
        'supabase/migrations/20261009000000_revoke_public_canvas_access.sql',
      );
      expect(migration.existsSync(), isTrue);
      final sql = migration.readAsStringSync().toLowerCase();

      expect(sql, contains('drop policy if exists projects_public_access'));
      expect(
        sql,
        contains('drop policy if exists canvas_snapshots_public_access'),
      );
      expect(sql, contains('drop policy if exists comments_public_access'));
      expect(sql, contains('revoke all on public.projects from public, anon'));
      expect(sql, contains('grant select, insert, update, delete'));
      expect(sql, contains('to authenticated'));
      expect(sql, contains('anonymous access remains enabled'));
    },
  );

  test(
    'existing collaboration policies enforce authenticated project membership',
    () {
      final migration = File(
        'supabase/migrations/20260907000000_create_collaboration_crdt.sql',
      );
      final sql = migration.readAsStringSync().toLowerCase();

      expect(sql, contains('projects_member_read'));
      expect(sql, contains('using (public.can_read_project(id))'));
      expect(sql, contains('canvas_snapshots_editor_write'));
      expect(sql, contains('public.can_edit_project(project_id)'));
    },
  );

  test('defines authenticated CRDT storage and scoped access policies', () {
    final sql = File(
      'supabase/migrations/20260907000000_create_collaboration_crdt.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create table if not exists public.workspace_members'),
    );
    expect(
      sql,
      contains('create table if not exists public.canvas_crdt_operations'),
    );
    expect(
      sql,
      contains('create table if not exists public.canvas_crdt_snapshots'),
    );
    expect(
      sql,
      contains(
        'create table if not exists public.canvas_collaboration_checkpoints',
      ),
    );
    expect(sql, contains('create table if not exists public.share_links'));
    expect(sql, contains("role text not null check (role in ('owner'"));
    expect(sql, contains('unique (project_id, actor_id, actor_counter)'));

    expect(
      sql,
      contains(
        'create or replace function public.append_canvas_crdt_operation',
      ),
    );
    expect(
      sql,
      contains('create or replace function public.get_canvas_crdt_delta'),
    );
    expect(
      sql,
      contains('create or replace function public.save_canvas_crdt_snapshot'),
    );
    expect(
      sql,
      contains('create or replace function public.read_canvas_share'),
    );
    final shareFunction = sql.substring(
      sql.indexOf('create or replace function public.read_canvas_share'),
    );
    expect(shareFunction, contains('canvas_crdt_snapshots'));
    expect(shareFunction, contains('state_json'));
    expect(shareFunction, contains("-> 'document'"));
    expect(shareFunction, contains("-> 'comments'"));
    expect(shareFunction, contains("link.revoked_at is null"));
    expect(shareFunction, contains('link.expires_at > now()'));
    expect(shareFunction, contains('lower(trim(p_token_hash))'));
    expect(
      sql,
      contains(
        'create or replace function public.claim_canvas_project_ownership',
      ),
    );
    expect(
      sql,
      contains('create or replace function public.set_canvas_member_role'),
    );
    expect(
      sql,
      contains('create or replace function public.remove_canvas_member'),
    );
    expect(sql, contains("'nodeid', comment.node_id"));
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('public.can_edit_project(project_id)'));
    expect(sql, contains('public.can_read_project(project_id)'));
    expect(
      sql,
      contains('revoke all on public.canvas_crdt_operations from anon'),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.read_canvas_share(text, text)',
      ),
    );
    expect(sql, contains('revoke execute on function'));
    expect(sql, contains('from public;'));
    expect(
      sql,
      isNot(contains('create policy canvas_crdt_operation_public_access')),
    );
  });

  test('creates or claims projects atomically for authenticated owners', () {
    final sql = File(
      'supabase/migrations/20260907000001_fix_project_ownership_claim.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('insert into public.projects as project'));
    expect(sql, contains('on conflict (id) do update'));
    expect(sql, contains('where project.owner_id is null'));
    expect(sql, contains('result.owner_id <> auth.uid()'));
    expect(
      sql,
      contains(
        'grant execute on function public.claim_canvas_project_ownership(text)',
      ),
    );
  });

  test('defines collaboration room RPCs', () {
    final sql = File(
      'supabase/migrations/20260908000000_create_collaboration_rooms.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create table if not exists public.collaboration_rooms'),
    );
    expect(sql, contains('room_code_hash text not null unique'));
    expect(sql, contains("extensions.digest(generated_code, 'sha256')"));
    expect(sql, contains("extensions.digest(normalized_code, 'sha256')"));
    expect(
      sql,
      contains('create or replace function public.join_collaboration_room'),
    );
    expect(sql, contains('insert into public.workspace_members'));
    expect(
      sql,
      contains(
        'grant execute on function public.join_collaboration_room(text)',
      ),
    );
  });

  test('runs append and snapshot RPCs outside table RLS policies', () {
    final sql = File(
      'supabase/migrations/20260908000002_harden_collaboration_rpc_security.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'alter function public.append_canvas_crdt_operation(text, jsonb)\n  security definer',
      ),
    );
    expect(
      sql,
      contains(
        'alter function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)\n  security definer',
      ),
    );
    expect(sql, contains('to authenticated;'));
  });

  test('keeps the idempotent append RPC outside table RLS policies', () {
    final sql = File(
      'supabase/migrations/20260909000006_restore_crdt_append_security.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'alter function public.append_canvas_crdt_operation(text, jsonb)\n'
        '  security definer',
      ),
    );
    expect(sql, contains('to authenticated;'));
    expect(sql, contains('from public, anon;'));
  });

  test('hardens member authorization and room-specific removals', () {
    final sql = File(
      'supabase/migrations/20260910000002_harden_collaboration_membership.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create table if not exists public.collaboration_room_blocks'),
    );
    expect(sql, contains('create or replace function public.can_edit_project'));
    expect(sql, contains('wm.role in (\'owner\', \'editor\')'));
    expect(sql, contains('you were removed from this collaboration room'));
    expect(sql, contains('insert into public.collaboration_room_blocks'));
    expect(
      sql,
      contains('create or replace function public.remove_canvas_member('),
    );
  });
}
