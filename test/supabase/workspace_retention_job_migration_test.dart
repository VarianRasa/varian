import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20260914030000_create_workspace_retention_job.sql',
  ).readAsStringSync();
  final hardeningSql = File(
    'supabase/migrations/20260914030100_harden_workspace_retention_job.sql',
  ).readAsStringSync();

  test('retention maintenance is restricted to service role execution', () {
    expect(
      sql,
      contains(
        'create or replace function public.run_workspace_retention_maintenance',
      ),
    );
    expect(sql, contains("auth.role(), '') <> 'service_role'"));
    expect(
      sql,
      contains(
        'revoke all on function public.run_workspace_retention_maintenance(text)',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.run_workspace_retention_maintenance(text) to service_role',
      ),
    );
    expect(
      hardeningSql,
      contains("coalesce(auth.role(), '') <> 'service_role'"),
    );
    expect(hardeningSql, contains("message = 'Project not found'"));
  });

  test(
    'retention maintenance honors policy cutoffs and records an audit event',
    () {
      expect(sql, contains("auditLogRetentionDays"));
      expect(sql, contains("trashRetentionDays"));
      expect(sql, contains("workspace.retention.maintenance_completed"));
      expect(sql, contains("status in ('ready', 'failed', 'expired')"));
      expect(
        hardeningSql,
        contains(
          'coalesce((policy -> \'retention\' ->> \'auditLogRetentionDays\')::integer, 365)',
        ),
      );
    },
  );
}
