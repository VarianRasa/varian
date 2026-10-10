import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration(String name) =>
    File('supabase/migrations/$name').readAsStringSync();

void main() {
  test(
    'AI policy migration creates strict provider and authorization controls',
    () {
      final sql = _migration('20260913000004_harden_workspace_ai_policy.sql');

      expect(
        sql,
        contains(
          'create table if not exists public.workspace_ai_provider_policies',
        ),
      );
      expect(sql, contains('allowed_models jsonb'));
      expect(
        sql,
        contains('alter table public.workspace_ai_job_authorizations'),
      );
      expect(
        sql,
        contains("create or replace function public.authorize_ai_job_v2"),
      );
      expect(sql, contains('allowUnknownProviders'));
      expect(sql, contains('fallbackProviders'));
      expect(sql, contains('budgetAlertThreshold'));
      expect(sql, contains('rate_limit_window_seconds'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains("raise exception using errcode = '54000'"));
      expect(sql, contains("raise exception using errcode = '50300'"));
      expect(
        sql,
        contains('revoke execute on function public.authorize_ai_job_v2'),
      );
    },
  );

  test(
    'AI governance persistence stores global policy and provider rows together',
    () {
      final sql = _migration(
        '20260913000005_upsert_workspace_ai_governance.sql',
      );

      expect(
        sql,
        contains(
          'create or replace function public.upsert_workspace_ai_governance',
        ),
      );
      expect(sql, contains("'{aiGovernance}'"));
      expect(sql, contains('workspace_ai_provider_policies'));
      expect(
        sql,
        contains('delete from public.workspace_ai_provider_policies'),
      );
      expect(sql, contains('workspace.ai_governance.updated'));
      expect(
        sql,
        contains(
          'grant execute on function public.upsert_workspace_ai_governance',
        ),
      );
    },
  );
}
