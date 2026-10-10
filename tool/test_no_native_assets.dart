import 'dart:io';

void main() {
  final hardening = File(
    'supabase/migrations/20261009000000_revoke_public_canvas_access.sql',
  ).readAsStringSync().toLowerCase();
  _check(hardening, 'drop policy if exists projects_public_access');
  _check(hardening, 'drop policy if exists canvas_snapshots_public_access');
  _check(hardening, 'drop policy if exists comments_public_access');
  _check(hardening, 'revoke all on public.projects from public, anon');
  _check(hardening, 'to authenticated');
  _check(hardening, 'anonymous access remains enabled');

  final policies = File(
    'supabase/migrations/20260907000000_create_collaboration_crdt.sql',
  ).readAsStringSync().toLowerCase();
  _check(policies, 'projects_member_read');
  _check(policies, 'using (public.can_read_project(id))');
  _check(policies, 'canvas_snapshots_editor_write');
  _check(policies, 'public.can_edit_project(project_id)');

  stdout.writeln(
    'PASS: migration revokes public access and scopes project policies',
  );
}

void _check(String value, String expected) {
  if (!value.contains(expected)) {
    stderr.writeln('FAIL: expected SQL to contain: $expected');
    exitCode = 1;
  }
}
