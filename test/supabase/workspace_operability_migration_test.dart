import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration() => File(
  'supabase/migrations/20260914000000_create_workspace_operability.sql',
).readAsStringSync().toLowerCase();

void main() {
  test('protects operability tables behind authenticated RPCs', () {
    final sql = _migration();
    for (final table in [
      'workspace_observability_events',
      'workspace_support_bundles',
      'workspace_release_policies',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(
        sql,
        contains(
          'revoke all on public.$table from public, anon, authenticated',
        ),
      );
    }
    expect(sql, contains('unique (project_id, event_type, correlation_id)'));
    expect(sql, contains('workspace observability access denied'));
    expect(sql, contains('invalid workspace support bundle identity'));
    expect(sql, contains('only the project owner can read support bundles'));
    expect(sql, contains('only the project owner can update release policy'));
    expect(sql, contains('get_workspace_health'));
  });

  test('bounds payloads and strips credential fields server-side', () {
    final sql = _migration();
    expect(sql, contains('octet_length((coalesce(p_payload'));
    expect(sql, contains('octet_length((coalesce(p_bundle'));
    expect(sql, contains("'accesstoken'"));
    expect(sql, contains("'servicerolekey'"));
    expect(sql, contains("'private_key'"));
    expect(sql, contains('on conflict (project_id, operation_id) do update'));
  });

  test(
    'exposes release policy and support delivery grants with anon revoked',
    () {
      final sql = _migration();
      for (final functionName in [
        'record_workspace_observability_event',
        'submit_workspace_support_bundle',
        'get_workspace_support_bundle',
        'get_workspace_release_policy',
        'upsert_workspace_release_policy',
        'get_workspace_health',
      ]) {
        expect(sql, contains('grant execute on function public.$functionName'));
        expect(
          sql,
          contains('revoke execute on function public.$functionName'),
        );
      }
    },
  );
}
