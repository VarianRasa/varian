import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261021130000_workspace_note_templates.sql',
  ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test('Notes templates have an explicit immutable scoped record shape', () {
    expect(migration, contains('create table public.workspace_note_templates'));
    expect(migration, contains('id uuid primary key'));
    expect(migration, contains('owner_user_id uuid not null'));
    expect(migration, contains('created_by uuid not null'));
    expect(
      migration,
      contains('project_id text references public.projects(id)'),
    );
    expect(migration, contains('title text not null'));
    expect(migration, contains('markdown_content text not null'));
    expect(migration, contains('revision integer not null default 1'));
    expect(migration, contains('check (revision >= 1)'));
    expect(migration, contains('enable row level security'));
  });

  test('template RLS preserves private and project permissions', () {
    expect(
      migration,
      contains(
        'using (public.workspace_note_can_read(owner_user_id, project_id))',
      ),
    );
    expect(migration, contains('created_by = auth.uid()'));
    expect(
      migration,
      contains('project_id is null and owner_user_id = auth.uid()'),
    );
    expect(migration, contains('public.can_edit_project(project_id)'));
    expect(
      migration,
      contains(
        'using (public.workspace_note_can_edit(owner_user_id, project_id)) with check (public.workspace_note_can_edit(owner_user_id, project_id))',
      ),
    );
    expect(
      migration,
      contains(
        'grant update (title, markdown_content, revision, updated_at) on public.workspace_note_templates to authenticated',
      ),
    );
  });

  test('template CAS and project deletion rehome are enforced locally', () {
    expect(
      migration,
      contains('new.revision is distinct from old.revision + 1'),
    );
    expect(migration, contains('where project_id = old.id'));
    expect(migration, contains('update public.workspace_note_templates'));
    expect(migration, contains('owner_user_id = old.owner_id'));
    expect(
      migration,
      contains(
        'create or replace function public.rehome_workspace_notes_before_project_delete()',
      ),
    );
  });
}
