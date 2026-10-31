import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace notes are private to authenticated owners', () {
    final migration = File(
      'supabase/migrations/20261010000000_private_workspace_notes.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      migration,
      contains('create table if not exists public.workspace_notes'),
    );
    expect(
      migration,
      contains(
        'owner_user_id uuid not null references auth.users(id) on delete cascade',
      ),
    );
    expect(migration, contains('markdown_content text not null'));
    expect(
      migration,
      contains('alter table public.workspace_notes enable row level security'),
    );
    expect(migration, contains('for select to authenticated'));
    expect(migration, contains('for insert to authenticated'));
    expect(migration, contains('for update to authenticated'));
    expect(migration, contains('for delete to authenticated'));
    expect(migration, contains('owner_user_id = (select auth.uid())'));
    expect(
      migration,
      contains('revoke all on public.workspace_notes from anon'),
    );
    expect(
      migration,
      contains('with check (owner_user_id = (select auth.uid()))'),
    );
  });

  test('workspace notes grants only owner-scoped CRUD to authenticated', () {
    final migration = File(
      'supabase/migrations/20261014000000_harden_private_workspace_notes_privileges.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      migration,
      contains(
        'revoke all privileges on table public.workspace_notes\nfrom public, anon, authenticated',
      ),
    );
    expect(
      migration,
      contains(
        'grant select, insert, update, delete\non table public.workspace_notes\nto authenticated',
      ),
    );
    expect(migration, isNot(contains('truncate')));
    expect(migration, isNot(contains('references')));
    expect(migration, isNot(contains('trigger')));
  });

  test('rename RPC is invoker-scoped and shares a pre-row-lock owner lock', () {
    final migration = File(
      'supabase/migrations/20261016105349_rename_workspace_notes_with_links.sql',
    ).readAsStringSync().toLowerCase();
    final functionStart = migration.indexOf(
      'create or replace function public.rename_workspace_notes_with_links',
    );
    expect(functionStart, greaterThanOrEqualTo(0));
    final signatureEnd = migration.indexOf(
      'returns setof public.workspace_notes',
      functionStart,
    );
    final signature = migration.substring(functionStart, signatureEnd);
    expect(signature, contains('p_target_id uuid'));
    expect(signature, contains('p_expected_revision integer'));
    expect(signature, contains('p_snapshot jsonb'));
    expect(signature, contains('p_source_updates jsonb'));
    expect(signature, isNot(contains('p_owner_user_id')));
    final rpcDefinition = migration.substring(functionStart);
    expect(rpcDefinition, contains('security invoker'));
    expect(rpcDefinition, isNot(contains('security definer')));
    final triggerStart = migration.indexOf(
      'create or replace function public.lock_workspace_notes_owner_writes',
    );
    final triggerEnd = migration.indexOf(
      'create trigger workspace_notes_owner_write_lock',
      triggerStart,
    );
    final triggerDefinition = migration.substring(triggerStart, triggerEnd);
    expect(triggerDefinition, contains('security definer'));
    expect(triggerDefinition, contains('set search_path = pg_catalog'));
    expect(
      triggerDefinition,
      contains(
        'grant execute on function public.lock_workspace_notes_owner_writes()',
      ),
    );
    expect(migration, contains('apply this migration as the table owner'));
    expect(
      migration,
      isNot(contains('grant trigger on public.workspace_notes')),
    );
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('before insert or update or delete'));
    expect(migration, contains('for each statement'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains("hashtextextended('workspace_notes:'"));
    expect(migration, contains('order by n.id'));
    expect(migration, contains('for update'));
    expect(migration, contains('jsonb_to_recordset(p_snapshot)'));
    expect(migration, contains('jsonb_to_recordset(p_source_updates)'));
    expect(migration, contains('deleted_at is null'));
    expect(migration, contains('workspace_notes_conflict'));
    expect(migration, contains('workspace_notes_unavailable'));
    expect(
      migration,
      contains(
        'revoke all on function public.rename_workspace_notes_with_links',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.rename_workspace_notes_with_links',
      ),
    );
  });
}
