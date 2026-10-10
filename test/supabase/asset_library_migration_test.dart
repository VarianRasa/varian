import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration() => File(
  'supabase/migrations/20260915000000_create_asset_library.sql',
).readAsStringSync().toLowerCase();

String _usageHardeningMigration() => File(
  'supabase/migrations/20260915010000_harden_workspace_usage_for_asset_library.sql',
).readAsStringSync().toLowerCase();

String _externalLicenseMigration() => File(
  'supabase/migrations/20260915020000_require_external_asset_license.sql',
).readAsStringSync().toLowerCase();

String _licenseWhitespaceMigration() => File(
  'supabase/migrations/20260915030000_reject_external_license_whitespace.sql',
).readAsStringSync().toLowerCase();

String _rlsPerformanceMigration() => File(
  'supabase/migrations/20260915040000_harden_asset_library_rls_performance.sql',
).readAsStringSync().toLowerCase();

String _triggerGrantMigration() => File(
  'supabase/migrations/20260915050000_revoke_asset_library_trigger_function_grants.sql',
).readAsStringSync().toLowerCase();

String _auditGrantMigration() => File(
  'supabase/migrations/20260915060000_revoke_asset_library_audit_trigger_grant.sql',
).readAsStringSync().toLowerCase();

void main() {
  test('stores catalog metadata separately from binary storage', () {
    final sql = _migration();

    expect(sql, contains('update storage.buckets'));
    expect(sql, contains('file_size_limit = 536870912'));
    expect(
      sql,
      contains('create table if not exists public.asset_library_items'),
    );
    expect(sql, contains('references public.projects(id) on delete cascade'));
    expect(sql, contains('provider_asset_id'));
    expect(sql, contains('primary key (project_id, id)'));
    expect(sql, contains('license_url'));
    expect(sql, contains('metadata jsonb'));
    expect(sql, contains('tags text[]'));
    expect(sql, contains('validate_asset_library_item_boundaries'));
    expect(sql, contains('asset exceeds the 512 mb upload limit'));
    expect(
      sql,
      contains('asset metadata is too large or contains binary data'),
    );
    expect(sql, contains('asset tags are invalid'));
    expect(sql, contains('asset mime type is invalid'));
    expect(sql, contains('asset provider id is invalid'));
    expect(sql, contains('asset library folder is invalid'));
    expect(sql, contains('machine-local paths cannot be stored remotely'));
    expect(sql, contains('asset storage path is invalid'));
    expect(sql, contains("split_part(new.storage_path, '/', 2) not in"));
    expect(sql, contains('asset storage object not found'));
    expect(sql, contains('asset size does not match storage'));
    expect(sql, contains('asset binary fields are immutable'));
    expect(
      sql,
      contains('old.storage_path is null and new.storage_path is not null'),
    );
    expect(sql, contains('asset identity and project are immutable'));
    expect(sql, contains("jsonb_typeof(coalesce(new.metadata, '{}'::jsonb))"));
    expect(sql, contains('tag ~ \'[[:cntrl:]]\''));
    expect(sql, contains('record_workspace_usage'));
    expect(sql, contains('record_asset_library_usage_release'));
    expect(sql, contains('invalid asset usage release'));
    expect(sql, contains('asset-library:add:'));
    expect(sql, contains('backfilled'));
    expect(sql, contains('asset-library:remove:'));
    expect(
      sql,
      contains(
        'before insert or update or delete on public.asset_library_items',
      ),
    );
    expect(sql, contains('foreign key (project_id, folder_id)'));
    expect(sql, contains('on delete set null (folder_id)'));
    expect(sql, contains('asset_library_items_project_checksum_idx'));
    expect(sql, contains('lower(checksum)'));
    expect(sql, contains('new.checksum := lower(btrim(new.checksum))'));
    expect(sql, contains('asset_library.item.created'));
    expect(sql, contains('asset_library.item.deleted'));
  });

  test('requires provenance for external provider catalog rows', () {
    final sql = _externalLicenseMigration();
    final whitespaceSql = _licenseWhitespaceMigration();

    expect(sql, contains('validate_asset_library_external_license'));
    expect(sql, contains("new.source in ('openverse', 'wikimedia', 'remote')"));
    expect(sql, contains('external asset licenses are required'));
    expect(
      whitespaceSql,
      contains('asset license cannot contain surrounding whitespace'),
    );
  });

  test('keeps asset-library RLS policies init-plan friendly', () {
    final sql = _rlsPerformanceMigration();

    expect(sql, contains('user_id = (select auth.uid())'));
    expect(sql, contains('asset_library_folders_insert'));
    expect(sql, contains('asset_library_folders_update'));
    expect(sql, contains('asset_library_folders_delete'));
    expect(sql, isNot(contains('create policy asset_library_folders_write')));
  });

  test('keeps trigger-only asset functions out of public RPCs', () {
    final sql = _triggerGrantMigration();

    expect(sql, contains('validate_asset_library_item_boundaries()'));
    expect(sql, contains('validate_asset_library_folder_boundaries()'));
    expect(sql, contains('validate_asset_library_item_folder()'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('from public, anon, authenticated'));
  });

  test('keeps audit trigger functions out of public RPCs', () {
    final sql = _auditGrantMigration();

    expect(sql, contains('audit_asset_library_item_change()'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('from public, anon, authenticated'));
  });

  test('protects project catalog data and personal favorites with RLS', () {
    final sql = _migration();

    expect(
      sql,
      contains(
        'alter table public.asset_library_items enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.asset_library_items from public, anon, authenticated',
      ),
    );
    expect(sql, contains('public.can_read_project(project_id)'));
    expect(sql, contains('public.can_edit_project(project_id)'));
    expect(sql, contains('user_id = auth.uid()'));
    expect(sql, contains('asset_library_storage_delete'));
    expect(sql, contains('is_asset_library_storage_path'));
    expect(sql, contains('uuid-addressed'));
    expect(sql, contains('not public.is_asset_library_storage_path(name)'));
    expect(sql, contains('split_part(name, \'/\', 1)'));
    expect(sql, contains("source <> 'bundled'"));
  });

  test('hardens shared usage reservations for service-role asset triggers', () {
    final sql = _usageHardeningMigration();

    expect(
      sql,
      contains('create or replace function public.record_workspace_usage'),
    );
    expect(sql, contains("coalesce(auth.role(), '') <> 'service_role'"));
    expect(sql, contains('for update'));
    expect(sql, contains('p_delta <= 0'));
    expect(sql, contains('p_operation_id <> btrim(p_operation_id)'));
    expect(sql, contains('octet_length'));
    expect(
      sql,
      contains(
        'grant execute on function public.record_workspace_usage(text, text, bigint, text, jsonb)',
      ),
    );
  });

  test('records usage through an authorized RPC', () {
    final sql = _migration();

    expect(
      sql,
      contains('create or replace function public.record_asset_library_usage'),
    );
    expect(sql, contains('asset_library_usage'));
    expect(sql, contains('usage_count = usage_count + 1'));
    expect(sql, contains('invalid asset library usage identifiers'));
    expect(sql, contains("nullif(trim(coalesce(p_node_id"));
    expect(
      sql,
      contains('grant execute on function public.record_asset_library_usage'),
    );
    expect(
      sql,
      contains('revoke execute on function public.record_asset_library_usage'),
    );
  });
}
