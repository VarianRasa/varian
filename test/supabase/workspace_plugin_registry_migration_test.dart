import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration() => File(
  'supabase/migrations/20260914020000_create_workspace_plugin_registry.sql',
).readAsStringSync().toLowerCase();

void main() {
  test('stores plugin manifests behind RLS and revokes direct table access', () {
    final sql = _migration();

    expect(
      sql,
      contains(
        'create table if not exists public.workspace_plugin_registrations',
      ),
    );
    expect(sql, contains('primary key (project_id, plugin_id)'));
    expect(
      sql,
      contains(
        'alter table public.workspace_plugin_registrations enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.workspace_plugin_registrations from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains("state in ('pendingreview', 'enabled', 'disabled', 'blocked')"),
    );
  });

  test(
    'validates manifests and exact permission approval before enablement',
    () {
      final sql = _migration();

      expect(
        sql,
        contains(
          'create or replace function public.validate_workspace_plugin_manifest',
        ),
      );
      expect(sql, contains(r"plugin_id !~ '^[a-z0-9][a-z0-9._-]{2,63}$'"));
      expect(sql, contains(r"api_version !~ '^1\.\d+$'"));
      expect(sql, contains('not (coalesce(p_approved_permissions'));
      expect(
        sql,
        contains('only the project owner can update plugin registrations'),
      );
    },
  );

  test('provides backend command authorization for enabled plugins', () {
    final sql = _migration();

    expect(
      sql,
      contains(
        'create or replace function public.authorize_workspace_plugin_command',
      ),
    );
    expect(sql, contains("when 'createnode' then 'writenodes'"));
    expect(sql, contains("when 'exportdocument' then 'export'"));
    expect(sql, contains('plugin command permission denied'));
    expect(
      sql,
      contains(
        'grant execute on function public.authorize_workspace_plugin_command',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.authorize_workspace_plugin_command',
      ),
    );
  });

  test('provides owner-only remote plugin deletion with an audit event', () {
    final sql = File(
      'supabase/migrations/20260914040000_add_workspace_plugin_registry_delete.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'create or replace function public.delete_workspace_plugin_registration',
      ),
    );
    expect(
      sql,
      contains('only the project owner can delete plugin registrations'),
    );
    expect(sql, contains('workspace.plugin.registration_deleted'));
    expect(
      sql,
      contains(
        'grant execute on function public.delete_workspace_plugin_registration',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.delete_workspace_plugin_registration',
      ),
    );
  });
}
