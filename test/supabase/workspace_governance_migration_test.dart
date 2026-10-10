import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration(String name) =>
    File('supabase/migrations/$name').readAsStringSync().toLowerCase();

void main() {
  test('protects workspace governance tables and exposes guarded RPCs', () {
    final sql = _migration('20260913000000_create_workspace_governance.sql');

    for (final table in [
      'workspace_policies',
      'workspace_usage_ledger',
      'workspace_audit_events',
      'workspace_data_export_requests',
      'workspace_billing_events',
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
    expect(sql, contains('unique (project_id, category, operation_id)'));
    expect(sql, contains('if existing_row.id is not null then'));
    expect(sql, contains('workspace quota exceeded'));
    expect(sql, contains('workspace data export is disabled'));
    expect(sql, contains('only the project owner can request deletion'));
    expect(sql, contains('only the project owner can purge retention data'));
    expect(sql, contains('only the project owner can enqueue billing events'));
    expect(
      sql,
      contains('grant execute on function public.record_workspace_usage'),
    );
    expect(
      sql,
      contains('revoke execute on function public.record_workspace_usage'),
    );
  });

  test('authorizes AI jobs with provider health, quota, and idempotency guards', () {
    final sql = _migration('20260913000001_create_workspace_ai_governance.sql');

    expect(
      sql,
      contains(
        'create table if not exists public.workspace_ai_provider_health',
      ),
    );
    expect(
      sql,
      contains(
        'create table if not exists public.workspace_ai_job_authorizations',
      ),
    );
    expect(
      sql,
      contains(
        'alter table public.workspace_ai_provider_health enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'alter table public.workspace_ai_job_authorizations enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        "p_status not in ('healthy', 'degraded', 'unavailable', 'experimental')",
      ),
    );
    expect(sql, contains('ai job authorization denied'));
    expect(sql, contains('if job_auth.job_id is not null then'));
    expect(sql, contains("'duplicate', true"));
    expect(sql, contains('workspace ai generation is disabled'));
    expect(sql, contains('ai provider is not healthy'));
    expect(sql, contains('ai provider quota exceeded'));
    expect(sql, contains('grant execute on function public.authorize_ai_job'));
    expect(sql, contains('revoke execute on function public.authorize_ai_job'));
  });

  test('syncs templates through scoped, editor-only RPCs', () {
    final sql = _migration('20260913000002_create_project_template_sync.sql');

    expect(
      sql,
      contains('create table if not exists public.project_templates'),
    );
    expect(
      sql,
      contains("scope text not null check (scope in ('personal', 'team'))"),
    );
    expect(sql, contains('primary key (workspace_id, template_id)'));
    expect(
      sql,
      contains(
        'alter table public.project_templates enable row level security',
      ),
    );
    expect(sql, contains('template access denied'));
    expect(sql, contains('only project editors can sync templates'));
    expect(sql, contains('invalid project template'));
    expect(sql, contains("scope = 'team' or created_by = auth.uid()"));
    expect(sql, contains('on conflict (workspace_id, template_id) do update'));
    expect(sql, contains('template update is not allowed'));
    expect(
      sql,
      contains('grant execute on function public.list_project_templates'),
    );
    expect(
      sql,
      contains('revoke execute on function public.list_project_templates'),
    );
    expect(
      sql,
      contains('grant execute on function public.delete_project_template'),
    );
    expect(
      sql,
      contains('revoke execute on function public.delete_project_template'),
    );
  });

  test('uses a structured, redacted audit event contract', () {
    final sql = _migration(
      '20260913000003_harden_workspace_audit_contract.sql',
    );

    expect(sql, contains('add column if not exists operation text'));
    expect(sql, contains('add column if not exists target_type text'));
    expect(sql, contains('add column if not exists target_id text'));
    expect(sql, contains('add column if not exists result text'));
    expect(sql, contains('add column if not exists correlation_id text'));
    expect(
      sql,
      contains(
        'create or replace function public.normalize_workspace_audit_event',
      ),
    );
    expect(sql, contains("- 'servicerolekey'"));
    expect(sql, contains("- 'turn_secret'"));
    expect(sql, contains('workspace_audit_events_correlation_idx'));
    expect(sql, contains('list_workspace_audit_events'));
  });
}
