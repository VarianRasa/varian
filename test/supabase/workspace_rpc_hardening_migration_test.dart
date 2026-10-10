import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualifies ambiguous governance, retention, and plugin references', () {
    final sql = File(
      'supabase/migrations/20260914060000_harden_workspace_rpc_ambiguity.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('provider_policy.rate_limit_count'));
    expect(sql, contains('workspace_audit_events.project_id = v_project_id'));
    expect(sql, contains('v_plugin_id'));
  });

  test('counts AI providers with supported PostgreSQL JSON functions', () {
    final sql = File(
      'supabase/migrations/20260914070000_fix_workspace_ai_provider_count.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('select count(*) from jsonb_object_keys(providers)'));
    expect(sql, isNot(contains('jsonb_object_length')));
  });
}
