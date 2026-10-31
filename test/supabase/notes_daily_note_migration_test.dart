import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily note keys are unique per active private and project scope', () {
    final migration = File(
      'supabase/migrations/20261021120000_workspace_notes_daily_date.sql',
    ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      migration,
      contains('add column if not exists daily_note_date date'),
    );
    expect(
      migration,
      contains(
        'on public.workspace_notes (owner_user_id, daily_note_date) where project_id is null and daily_note_date is not null and deleted_at is null',
      ),
    );
    expect(
      migration,
      contains(
        'on public.workspace_notes (project_id, daily_note_date) where project_id is not null and daily_note_date is not null and deleted_at is null',
      ),
    );
  });

  test('daily get-or-create RPC checks scope and uses conflict-safe inserts', () {
    final migration = File(
      'supabase/migrations/20261021120000_workspace_notes_daily_date.sql',
    ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      migration,
      contains('function public.get_or_create_workspace_daily_note'),
    );
    expect(migration, contains('returns public.workspace_notes'));
    expect(migration, contains('security invoker'));
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('public.can_read_project(p_project_id)'));
    expect(migration, contains('public.can_edit_project(p_project_id)'));
    expect(migration, contains('on conflict (owner_user_id, daily_note_date)'));
    expect(migration, contains('on conflict (project_id, daily_note_date)'));
    expect(migration, contains('do nothing returning * into v_note'));
    expect(
      migration,
      contains(
        'revoke all on function public.get_or_create_workspace_daily_note(date, text) from public, anon, authenticated',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.get_or_create_workspace_daily_note(date, text) to authenticated',
      ),
    );
  });
}
