# Creative Studio Release Evidence — 2026-09-14

## Scope completed in this slice

- PDF editable import now covers page frames, literal text, basic rectangles, line/cubic paths, embedded JPEG/Flate RGB/Gray XObjects, text widgets, checkbox/radio widgets, and choice widgets with durable asset references; unsupported annotations are classified accurately in the loss report.
- PDF push-button widgets now become labeled editable rectangle nodes instead of being dropped into the loss report.
- PPTX editable import now covers slide frames, supported shapes/text, rotation/stroke/text styling, and safe embedded raster image relationships from `ppt/slides/_rels` to `ppt/media`.
- Local plugin registry state persists through `LocalStorageService` and is controllable from Workspace Governance with explicit enable/disable state.
- Remote plugin registry source paths now include owner-only manifest validation, exact permission approval, state-transition RPCs, command authorization, and local-first Governance synchronization.
- Plugin permission parsing and runtime admission now fail closed for unknown or unapproved permissions; remote uninstall synchronization uses the owner-only `delete_workspace_plugin_registration` RPC.
- Collaboration presence now emits lifecycle heartbeats, expires stale remote presence, and marks remote members offline when a room disconnects or is revoked.
- Workspace Governance now reads backend health, submits a size-bounded redacted support bundle, and exposes typed release-policy and observability RPC clients; Supabase adds guarded operability tables/RPCs plus a public `workspace-health` probe.
- Billing entitlement sync now has an HMAC-signed/replay-bounded `billing-webhook` Edge Function, idempotent webhook receipts, stale-revision protection, redacted provider payloads, an entitlement RPC, and Flutter Governance visibility.
- Large text file previews now render loaded content in lazy 4 KB chunks, preserving the 1 MB preview contract without blocking the Flutter test/runtime frame loop.
- README and migration guidance document lossy import boundaries, codec availability, and production blockers.

## Automated evidence

- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub test/features/import test/features/governance test/features/media test/features/export`: passed, 109 tests.
- `flutter test --no-pub`: passed, 1,237 tests; 4 tests were skipped by their platform/runtime guards.
- `flutter test --no-pub test/features/collaboration`: passed, 77 tests, including duplicate-operation and stale-presence coverage after revoke.
- `flutter build web --no-pub --release`: passed; output is `build/web`.
- `flutter build windows --no-pub --release`: passed; output is `build/windows/x64/runner/Release/varian.exe`.
- `powershell -ExecutionPolicy Bypass -File tool/creative_studio_release_gates.ps1`: passed; analyzer, full suite, focused migration/function contracts, Deno checks, golden/benchmark tests, benchmark smoke, Web build, and Windows build are covered by the runner.
- `git diff --check`: passed; only existing Git line-ending normalization warnings remain.
- `test/features/file_card/file_preview_screen_test.dart`: passed, including the >1 MB text preview case without timeout.
- Latest deterministic state/recovery matrix: `output/state-matrix/20260914T081132Z/`; VM, Chrome, and Windows suites passed.
- Latest Chrome/Windows collaboration runtime matrix: `output/collaboration-matrix/20260914T081156Z/`; both target suites passed 12/12.

## Focused coverage

- `test/features/import/pdf_import_test.dart`: 10 tests passed, including compressed streams, UTF-16 text, vector paths, embedded JPEG/Flate assets, CTM transforms, editable text/checkbox/radio/choice widgets, and labeled push-button conversion.
- `test/features/import/pptx_import_test.dart`: 4 tests passed, including embedded raster image relationships and shape text styling.
- `test/data/local_storage_service_test.dart`: plugin registry persistence/clear round-trip passed.
- `test/features/governance/workspace_governance_dialog_test.dart`: plugin enable/disable UI persistence callback passed.
- `test/features/governance/remote_operability_test.dart`: redaction, UTF-8 byte limits, receipt parsing, release policy, and health snapshot coverage passed.
- `test/supabase/workspace_operability_migration_test.dart`: RLS, RPC grants, payload bounds, server-side redaction, and idempotency contract coverage passed.
- `test/supabase/workspace_billing_entitlements_migration_test.dart`: entitlement RLS, service-role webhook grants, payload bounds, limit validation, idempotency, and stale-revision contract coverage passed.
- `test/supabase/billing_webhook_function_contract_test.dart`: Edge Function signature, replay, payload-size, redaction, and deployment-config contract coverage passed.
- `test/supabase/workspace_plugin_registry_migration_test.dart`: plugin registry RLS, manifest/API validation, exact permission approval, owner-only transitions, and command authorization contract coverage passed.
- Supabase migration `20260914040000_add_workspace_plugin_registry_delete.sql` was pushed successfully; remote plugin deletion is owner-only and audited.
- `test/supabase/workspace_retention_job_migration_test.dart`: service-role-only retention execution, policy cutoffs, and audit-event contract coverage passed.
- `npx --yes deno-bin test --allow-env supabase/functions/billing-webhook/index_test.ts supabase/functions/workspace-health/index_test.ts supabase/functions/workspace-retention/index_test.ts`: 9 Deno tests passed.
- `npx --yes deno-bin check supabase/functions/billing-webhook/index.ts supabase/functions/workspace-health/index.ts`: passed.
- Supabase production migration push: migrations `20260914000000`, `20260914010000`, `20260914020000`, `20260914030000`, `20260914030100`, and `20260914040000` applied successfully to project `jnpxpylzzskaukgwhuzg`.
- Supabase `workspace-health` deployment and public smoke probe: HTTP 200, `healthy`, version `1.0.0+1`, Auth and database checks healthy.
- `tool/workspace_health_probe.ps1` passed against the production endpoint and wrote `output/workspace-health/latest.json`; the probe also verifies expected version and unhealthy check states through its exit code.
- Accessibility runtime binding now applies reduced motion, high contrast, keyboard-only navigation, focus highlighting, and larger text at the app root; `test/features/governance/accessibility_contract_test.dart` covers the mapping.
- Shared Forui primitives preserve the inherited accessibility profile while providing a platform fallback when rendered outside the app shell; `test/forui_theme_test.dart`, `test/features/file_card/pdf_viewer_screen_test.dart`, and `test/features/link_card/link_card_widget_test.dart` pass.
- Native codec discovery now checks configured, bundled, and `PATH` candidates before video processing; `test/features/media/media_codec_runtime_test.dart` and `test/features/media/media_video_proxy_transcoder_test.dart` pass, while the host remains explicitly unavailable until an approved encoder binary is installed.
- Retention maintenance now has a service-role-only migration/function path; migrations `20260914030000` and `20260914030100` are applied, `workspace-retention` is deployed, and an unauthenticated production probe returns `401 INVALID_SECRET` as expected. The successful operator run remains gated on the deployment-owned `RETENTION_JOB_SECRET`.

## Remaining external gates

- Production collaboration still needs two authorized Supabase sessions for both host/guest directions plus real backend auth/RLS and media-delivery evidence; the local Chrome ↔ Windows matrix, duplicate-operation, reconnect, revoke, and stale-presence coverage passes.
- iOS decoder validation needs an iOS simulator or device.
- Native codec bundling and runtime validation need a supported encoder binary on each target.
- Production plugin sandbox, organization identity/SSO/SCIM, and external support/release operations still require deployment-specific infrastructure; the observability/support/health migration and `workspace-health` function are deployed, while an external monitor and secret-backed retention schedule remain open.
- Billing source integration is implemented, but `billing-webhook` still needs a provider-owned `BILLING_WEBHOOK_SECRET`; provider account, metering reconciliation, entitlement enforcement against live usage, and external billing monitor remain open.
