# Varian Publish Readiness Checklist

## Phase 0 — Verification environment
- [ ] Identify and safely release sqlite3.dll file lock without killing unknown processes. Safe rename/restore worked for all 32 repo copies, but runner still fails its cleanup; leave files intact pending process handle diagnostics.
- [x] Run standalone source-contract smoke check for project migration/RLS SQL (`dart run tool/test_no_native_assets.dart`).
- [ ] Run Flutter focused migration tests and full `flutter test --no-pub` after repairing the SDK/runner problem. Focused auth contract test aborts before execution because Flutter cannot delete `varian-capture-build-diag/native_assets/windows/sqlite3.dll`; do not remove DLL or kill unidentified processes.
- [x] Re-run `flutter analyze --no-pub` on current working tree: passed, no issues found.
- [x] Re-run `flutter build web --no-pub` on current working tree: passed; output `varian-capture-build-diag/web` (Wasm dry-run also succeeded).
- [x] Compared live `index.html` and `main.dart.js` to current web build: byte-for-byte matches. `flutter_bootstrap.js` differs only in generated service-worker version. This does not verify the complete deployment or runtime feature flows.
- [ ] Reconcile every production asset and runtime flow against source/config before any deployment.

## Phase 1 — Release architecture
- [ ] Inventory auth, data, storage, RPC, functions, redirects and public config.
- [ ] Separate staging and production deployment configuration; document rollback.
- [ ] Verify browser/mobile presentation, branding, metadata, loading and error states.

## Phase 2 — Backend security
- [ ] Build role/resource access matrix for DB tables, views, RPCs and storage.
- [ ] Add/run cross-account integration tests for denied reads and writes.
- [ ] Review all Edge Functions with `verify_jwt=false` for explicit authentication and abuse controls.
- [x] Run Deno Edge Function suites: all function tests (64 passed, 0 failed) and `deno check supabase/functions/*/index.ts` (9 functions passed). Coverage includes asset-library auth, link-preview SSRF/CORS, AI video/3D, meetings, health, retention and billing.
- [ ] Inspect AI job authorization function exposure and fix verified SQL lint warning before declaring security gate complete.
- [x] Fixed production `workspace-health` response information disclosure: deployed redacted handler, verified live JSON exposes only `status` and `version`, and updated probe to enforce the public payload contract (probe passed).
- [ ] Audit other public monitoring/service endpoints for unintended diagnostic fields.
- [ ] Repair database test runner: `supabase test db --linked` cannot resolve pgTAP `plan(integer)`; read-only production catalog query returned no installed `pgtap` extension. Existing DB tests remain unexecuted; do not install extensions on production solely to unblock tests.
- [x] Read-only production catalog query verified `anon` cannot execute `get_workspace_ai_provider_health`, `authorize_ai_job`, or `upsert_workspace_ai_provider_health`.
- [x] Anonymous REST read of `projects` returned HTTP 401.
- [ ] Add/run privilege regression tests after pgTAP is available in a safe test environment.
- [x] Unauthenticated probes: `workspace-retention` rejects missing secret (401); meeting/link-preview reject the tested web origin (403). `billing-webhook` is absent from the production function inventory (404); reconcile deployments before enabling billing.
- [x] Checked both Firebase domains and local build: they serve matching HTML with CSP Report-Only (local `firebase.json` agrees). The live root’s effective response is Report-Only, not enforcement; verify all paths/headers before marking this security gate complete.
- [x] Compared local and production Edge Function inventories: local has nine function directories; production has eight of those active and lacks `billing-webhook` (production `ai-video` is active although its local directory was not included in the initial inventory scan). Reconcile the complete local inventory before deployment.
- [ ] Correct and verify `ALLOWED_ORIGINS` for `https://varian.web.app`; secret values are intentionally not retrievable, so the project owner must confirm/update via secret management. Do not deploy altered functions until the extensive local uncommitted changes are reviewed.
- [ ] Verify local vs production checksums/config and authenticate intended billing behavior before deciding whether `billing-webhook` should be deployed.
- [ ] Verify authenticated production flows for meeting and link-preview after origin configuration is fixed.
- [ ] Reconcile production frontend artifact with source/config before making further deploy changes.
- [ ] Demonstrate non-production backup and restore.
- [ ] Resolve SQL lint warnings in a safe test environment.
- [ ] Verify privacy/terms routes and account deletion/retention UX.

## Phase 3 — Web security and privacy
- [x] Confirm deployed CSP header is Report-Only on both Firebase domains.
- [ ] Capture real browser network origins; replace broad `https:`/`wss:` in `connect-src` with a tested allowlist.
- [ ] Enforce CSP after origin inventory, then verify primary feature flows.
- [x] Isolated production browser smoke test: page fully rendered as `Untitled Project`; canvas toolbar/minimap visible; `LOCAL ONLY` state shown. No console errors, failed requests, or CSP violations reported; no external origins contacted.
- [x] Traced `LOCAL ONLY`: `syncStatusProvider` initializes to `SyncStatus.localOnly` before any sync/save operation. The unauthenticated smoke test opened an empty local canvas and cannot establish a cloud failure.
- [ ] Confirm public first-run flow is intentional: unauthenticated visitors currently enter the local-only canvas directly; sign-in/sync flow still needs verification with an approved test account.
- [ ] Add and verify privacy/terms/support pages: route table has no legal/support routes; `/privacy`, `/terms`, and `/support` currently return the generic SPA shell (HTTP 200), not policy content.
- [ ] Confirm product owner details needed for truthful disclosures: legal entity/contact, support email, data categories/processors, retention/deletion policy, and account deletion procedure. Do not publish invented policy text.
- [ ] Audit secrets and rotate any client-exposed privileged credentials.
- [ ] Verify auth lifecycle, uploads, URL fetches/SSRF, errors and rate/size bounds.
- [ ] Publish privacy, terms, support, retention/export/deletion disclosures.

## Phase 4 — Product and operations
- [ ] Add desktop/mobile browser E2E smoke coverage for key user journeys.
- [ ] Configure monitoring, uptime, quota/cost alerts and incident/rollback runbook.
- [ ] Review Dart/Flutter dependency advisories and shipped licenses/assets.

## Release gate
- [ ] Blocking tests pass; accepted exceptions documented.
- [ ] Staging security and functional verification passes.
- [ ] Backup/restore and rollback demonstrated.
- [ ] Explicit approval received for production promotion or production auth/policy changes.
