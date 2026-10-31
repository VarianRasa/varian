import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const harnessPath = 'tool/notes_local_integration.ps1';

  test('migration contract remains source-text-only', () {
    final migration = File(
      'supabase/migrations/20261016105349_rename_workspace_notes_with_links.sql',
    ).readAsStringSync().toLowerCase();

    expect(migration, contains('security invoker'));
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('workspace_notes_conflict'));
    expect(migration, contains('workspace_notes_unavailable'));
  });

  test(
    'project notes migration declares membership-based access and scope constraints',
    () {
      final migration = File(
        'supabase/migrations/20261016120000_notes_project_folders_favorites.sql',
      ).readAsStringSync().toLowerCase();

      expect(migration, contains('public.can_read_project(p_project)'));
      expect(migration, contains('public.can_edit_project(p_project)'));
      expect(migration, contains('created_by'));
      expect(migration, contains('created_by = auth.uid()'));
      expect(migration, contains('workspace_notes_folder_scope_fk'));
      expect(migration, contains('workspace_note_preferences'));
      expect(migration, contains('old.owner_id is null'));
      expect(
        migration,
        contains('rehome_workspace_notes_before_project_delete'),
      );
      expect(
        migration,
        isNot(contains('workspace_notes_project_owner_relink')),
      );
      expect(migration, contains('workspace_notes_scope_guard'));
      expect(migration, contains('workspace_note_folders_scope_guard'));
      expect(migration, contains('workspace_notes_rename_scope'));
      expect(migration, contains('returns setof public.workspace_notes'));
      expect(migration, contains('security invoker'));
      expect(migration, contains('n.project_id = v_project'));
      expect(
        migration,
        contains('public.workspace_notes_rename_scope(v_owner, v_project)'),
      );
      expect(migration, contains("'workspace_notes:project:' || v_project"));
      expect(migration, contains('workspace_notes_project_write_lock'));
      expect(migration, contains('for update'));
      expect(migration, contains('workspace_note_preferences_read'));
      expect(
        migration,
        contains('workspace_note_can_read(n.owner_user_id, n.project_id)'),
      );
      expect(migration, contains('on delete restrict'));
      expect(
        migration,
        contains(
          'update public.workspace_notes set folder_id = old.parent_folder_id',
        ),
      );
      expect(
        migration,
        isNot(
          contains(
            'update public.workspace_notes set folder_id = null where folder_id = old.id',
          ),
        ),
      );
      expect(migration, contains('workspace_notes_rename_scope'));
    },
  );

  test('history migration captures and protects immutable versions', () {
    final migration = File(
      'supabase/migrations/20261016120100_workspace_note_history.sql',
    ).readAsStringSync().toLowerCase();

    expect(migration, contains('create table public.workspace_note_versions'));
    expect(migration, contains('unique (note_id, revision)'));
    expect(migration, contains('actor_id'));
    expect(migration, contains('workspace_note_versions_read'));
    expect(migration, contains('workspace_note_can_read'));
    expect(migration, contains('security definer'));
    expect(migration, contains('set search_path = pg_catalog, public, auth'));
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('new.revision <> old.revision + 1'));
    expect(migration, contains('new.revision is distinct from old.revision'));
    expect(
      migration,
      contains('new.deleted_at is not distinct from old.deleted_at'),
    );
    expect(migration, contains('new.title is distinct from old.title'));
    expect(
      migration,
      contains('new.markdown_content is distinct from old.markdown_content'),
    );
    expect(
      migration,
      contains('after insert or update on public.workspace_notes'),
    );
    expect(
      migration,
      contains(
        'grant select on table public.workspace_note_versions to authenticated',
      ),
    );
    expect(
      migration,
      contains(
        'revoke all on table public.workspace_note_versions from public, anon, authenticated',
      ),
    );
    expect(
      migration,
      isNot(contains('delete from public.workspace_note_versions')),
    );
    expect(
      migration,
      isNot(contains('truncate public.workspace_note_versions')),
    );
  });

  test('local harness covers atomic history and role access outcomes', () {
    final harness = File(harnessPath).readAsStringSync().toLowerCase();
    expect(harness, contains('legacy note initial version backfill'));
    expect(harness, contains('new note initial version capture'));
    expect(harness, contains('changed content creates one version'));
    expect(harness, contains('no-op content update creates no version'));
    expect(
      harness,
      contains('soft delete and restore do not create content versions'),
    );
    expect(
      harness,
      contains('content change without one revision increment rejected'),
    );
    expect(harness, contains('rolled back note update leaves no version'));
    expect(harness, contains('project member can read note versions'));
    expect(harness, contains('unauthorized note versions remain hidden'));
    expect(harness, contains('history insert privilege was granted'));
    expect(harness, contains('history update privilege was granted'));
    expect(harness, contains('history delete privilege was granted'));
    expect(harness, contains('history truncate privilege was granted'));
    expect(harness, contains('history pruning routine detected'));
  });

  test('local harness expresses four-role and lifecycle outcomes', () {
    final harness = File(harnessPath).readAsStringSync().toLowerCase();
    expect(
      harness,
      contains("role in ('owner','editor','commenter','viewer')"),
    );
    expect(
      harness,
      contains('references public.projects(id) on delete cascade'),
    );
    expect(harness, contains('removed member cannot read linked note'));
    expect(harness, contains('folder project scope mismatch rejected'));
    expect(harness, contains('project delete rehomes notes'));
    expect(harness, contains('created_by preserved'));
    expect(harness, contains('forged created_by insert rejected'));
    expect(harness, contains('child folder deletion did not reparent child'));
    expect(harness, contains('project delete rehomes nested folders'));
    expect(harness, contains('project delete preserves favorite'));
    expect(harness, contains('removed member cannot read folders'));
    expect(harness, contains('private note remains invisible'));
    expect(harness, contains('folder child deletion did not reparent note'));
    expect(harness, contains('null-owner project delete rejection failed'));
    expect(harness, contains('favorite write isolation failed'));
    expect(
      harness,
      contains(
        'mixed private/project rename was not rejected as scope conflict',
      ),
    );
    expect(harness, contains('same-scope project rename failed'));
    expect(harness, contains('stale rename snapshot conflict missing'));
    expect(harness, isNot(contains('set local role authenticated')));
  });

  test(
    'local harness rejects unsafe host and database name before connecting',
    () async {
      final unsafeHost = await Process.run('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        harnessPath,
        '-HostName',
        'db.example.com',
        '-DatabaseName',
        'notes_test_guard',
      ], workingDirectory: Directory.current.path);
      expect(unsafeHost.exitCode, isNot(0));
      expect(
        '${unsafeHost.stdout}${unsafeHost.stderr}',
        contains("Refusing non-loopback host 'db.example.com'"),
      );

      final unsafeDatabase = await Process.run('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        harnessPath,
        '-HostName',
        '127.0.0.1',
        '-DatabaseName',
        'unsafe_database',
      ], workingDirectory: Directory.current.path);
      expect(unsafeDatabase.exitCode, isNot(0));
      expect(
        '${unsafeDatabase.stdout}${unsafeDatabase.stderr}',
        contains("Refusing database name 'unsafe_database'"),
      );
    },
  );

  test('import RPC is atomic, scope-checked, and server-attributes notes', () {
    final migration = File(
      'supabase/migrations/20261016120150_notes_import_rpc.sql',
    ).readAsStringSync().toLowerCase();

    expect(migration, contains('import_workspace_notes_batch'));
    expect(migration, contains('security invoker'));
    expect(migration, contains('auth.uid()'));
    expect(
      migration,
      contains('public.workspace_note_can_edit(v_actor, p_project_id)'),
    );
    expect(migration, contains('jsonb_array_elements'));
    expect(migration, contains('created_by'));
    expect(migration, contains('workspace_notes'));
    expect(migration, contains('workspace_note_folders'));
    expect(migration, contains('p_notes jsonb'));
    expect(migration, contains('p_folders jsonb'));
    expect(migration, contains('p_project_id text'));
    expect(migration, contains('revoke all on function'));
    expect(migration, contains('grant execute'));
  });

  test('local harness exercises atomic import and folder hierarchy', () {
    final harness = File(harnessPath).readAsStringSync().toLowerCase();
    expect(harness, contains('import_workspace_notes_batch'));
    expect(harness, contains('import did not return its inserted note'));
    expect(harness, contains('import did not preserve content, hierarchy'));
    expect(
      harness,
      contains('import did not create attributed initial history'),
    );
    expect(harness, contains('failed import left partial notes behind'));
    expect(harness, contains('atomic collision'));
  });

  test('Notes CRDT migration scopes data and serializes materialization', () {
    final migration = File(
      'supabase/migrations/20261016120200_notes_crdt_collaboration.sql',
    ).readAsStringSync().toLowerCase();
    for (final rpc in [
      'create_workspace_note_from_sync',
      'append_workspace_note_crdt_operation',
      'get_workspace_note_crdt_delta',
      'materialize_workspace_note_crdt',
    ]) {
      expect(migration, contains(rpc));
    }
    expect(migration, contains('auth.uid()'));
    expect(migration, contains('workspace_note_can_edit'));
    expect(migration, contains('for update'));
    expect(migration, contains('expected_revision'));
    expect(migration, contains('on conflict'));
    expect(migration, contains('update public.workspace_notes'));
    expect(migration, contains('revision = revision + 1'));
    expect(migration, contains('auth_user_id'));
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('grant execute'));
    expect(migration, contains('workspace_note_realtime_topic_can_read'));
    expect(migration, contains('on realtime.messages'));
    expect(migration, contains("extension = ''broadcast''"));
    expect(
      File(harnessPath).readAsStringSync(),
      contains('20261016120200_notes_crdt_collaboration.sql'),
    );
    for (final rpc in [
      'create_workspace_note_from_sync',
      'append_workspace_note_crdt_operation',
      'get_workspace_note_crdt_delta',
      'materialize_workspace_note_crdt',
    ]) {
      final start = migration.indexOf('function public.$rpc(');
      final end = migration.indexOf('\$function\$;', start);
      expect(start, greaterThanOrEqualTo(0), reason: rpc);
      expect(end, greaterThan(start), reason: rpc);
      final body = migration.substring(start, end);
      expect(body, contains('auth.uid()'), reason: rpc);
      expect(
        body,
        contains(
          rpc == 'get_workspace_note_crdt_delta'
              ? 'workspace_note_can_read'
              : 'workspace_note_can_edit',
        ),
        reason: rpc,
      );
    }
    expect(migration, contains('revoke all'));
    final harness = File(harnessPath).readAsStringSync().toLowerCase();
    expect(harness, contains('duplicate crdt operation was inserted twice'));
    final delayedOperation = harness.indexOf(
      '"opid":"30000000-0000-4000-8000-000000000004:device-harness:2"',
    );
    final prerequisiteOperation = harness.indexOf(
      '"opid":"30000000-0000-4000-8000-000000000004:device-harness:1"',
    );
    expect(delayedOperation, greaterThanOrEqualTo(0));
    expect(prerequisiteOperation, greaterThan(delayedOperation));
    expect(harness, contains('"dependencies":{"device-harness":1}'));
    expect(
      harness,
      contains('out-of-order crdt delta did not return both operations'),
    );
    expect(harness, contains('crdt materialization/history was not atomic'));
    expect(harness, contains('commenter wrote notes crdt operation'));
    expect(harness, contains('stale crdt materialization changed the note'));
  });

  test('offline key envelope stores only wrapped keys with owner RLS', () {
    final migration = File(
      'supabase/migrations/20261016120300_notes_offline_key_envelopes.sql',
    ).readAsStringSync().toLowerCase();
    expect(migration, contains('workspace_note_key_envelopes'));
    expect(migration, contains('wrapped_key bytea'));
    expect(migration, contains('owner_user_id = auth.uid()'));
    expect(migration, contains('enable row level security'));
    expect(migration, isNot(contains('passphrase')));
    expect(migration, isNot(contains('plaintext_key')));
    expect(migration, isNot(contains('dek bytea')));
  });

  test('local harness keeps its safety boundaries explicit', () {
    final harness = File(harnessPath).readAsStringSync();
    final hostGuard = harness.indexOf("if (\$HostName -cne '127.0.0.1')");
    final databaseGuard = harness.indexOf(
      "if (\$DatabaseName -notmatch '^notes_test_",
    );
    final psqlLookup = harness.indexOf('Get-Command psql');

    expect(hostGuard, greaterThanOrEqualTo(0));
    expect(databaseGuard, greaterThan(hostGuard));
    expect(psqlLookup, greaterThan(databaseGuard));
    expect(harness, contains("\$env:PGPASSFILE = \$PgPassFile"));
    expect(harness, contains('No connection opened; no database created.'));
    expect(harness, contains('DROP DATABASE IF EXISTS'));
    expect(harness, contains('DROP ROLE IF EXISTS \$role'));
    expect(harness, contains("\$createdRoles.Add(\$role)"));
    expect(harness, isNot(contains('Write-Output \$PgPassFile')));
  });
}
