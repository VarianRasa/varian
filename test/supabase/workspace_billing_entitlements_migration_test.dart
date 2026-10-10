import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration() => File(
  'supabase/migrations/20260914010000_create_workspace_billing_entitlements.sql',
).readAsStringSync().toLowerCase();

void main() {
  test('stores guarded entitlements and idempotent webhook receipts', () {
    final sql = _migration();

    expect(
      sql,
      contains('create table if not exists public.workspace_entitlements'),
    );
    expect(
      sql,
      contains(
        'create table if not exists public.workspace_billing_webhook_events',
      ),
    );
    expect(sql, contains("unique (provider, event_id)"));
    expect(
      sql,
      contains(
        "status in ('active', 'trialing', 'past_due', 'canceled', 'paused')",
      ),
    );
    expect(sql, contains("overage_policy in ('block', 'grace', 'allow')"));
    expect(
      sql,
      contains(
        'alter table public.workspace_entitlements enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'alter table public.workspace_billing_webhook_events enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.workspace_entitlements from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.workspace_billing_webhook_events from public, anon, authenticated',
      ),
    );
  });

  test(
    'exposes authenticated reads and service-role-only webhook application',
    () {
      final sql = _migration();

      expect(
        sql,
        contains('create or replace function public.get_workspace_entitlement'),
      );
      expect(
        sql,
        contains(
          'create or replace function public.apply_workspace_billing_webhook',
        ),
      );
      expect(sql, contains("coalesce(auth.role(), '') <> 'service_role'"));
      expect(sql, contains('on conflict (provider, event_id) do nothing'));
      expect(sql, contains("status = 'processed', processed_at = now()"));
      expect(
        sql,
        contains('excluded.revision >= public.workspace_entitlements.revision'),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.get_workspace_entitlement(text) to authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.apply_workspace_billing_webhook',
        ),
      );
      expect(
        sql,
        contains(
          'revoke execute on function public.apply_workspace_billing_webhook',
        ),
      );
    },
  );

  test('validates bounded payloads and known entitlement dimensions', () {
    final sql = _migration();

    expect(
      sql,
      contains(
        "octet_length((coalesce(p_payload, '{}'::jsonb))::text) > 262144",
      ),
    );
    expect(
      sql,
      contains(
        "'storagebytes', 'assetbytes', 'transferbytes', 'aicredits', 'renderseconds', 'projectcount', 'seats'",
      ),
    );
    expect(sql, contains("jsonb_typeof(limit_value) <> 'number'"));
    expect(sql, contains("(limit_value::text)::numeric < 0"));
    expect(
      sql,
      contains('create or replace function public.record_workspace_usage'),
    );
    expect(sql, contains('effective_overage_policy'));
    expect(sql, contains("'overage', overage"));
    expect(sql, contains('for update'));
    expect(sql, contains('limit_value := coalesce(case p_category'));
    expect(sql, contains("coalesce(auth.role(), '') <> 'service_role'"));
    expect(sql, contains('created_by'));
  });
}
