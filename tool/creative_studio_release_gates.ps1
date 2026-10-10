$ErrorActionPreference = 'Stop'

flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/features/quality/creative_studio_golden_test.dart test/features/performance/creative_studio_benchmark_test.dart test/features/performance/interactive_canvas_benchmark_test.dart
flutter test --no-pub test/supabase/workspace_operability_migration_test.dart test/supabase/workspace_billing_entitlements_migration_test.dart test/supabase/workspace_plugin_registry_migration_test.dart test/supabase/workspace_retention_job_migration_test.dart test/supabase/billing_webhook_function_contract_test.dart
npx --yes deno-bin test --allow-env supabase/functions/billing-webhook/index_test.ts supabase/functions/workspace-health/index_test.ts supabase/functions/workspace-retention/index_test.ts
npx --yes deno-bin check supabase/functions/billing-webhook/index.ts supabase/functions/workspace-health/index.ts supabase/functions/workspace-retention/index.ts
dart run tool/benchmarks/creative_studio_benchmark.dart
flutter build web --release
flutter build windows --release
