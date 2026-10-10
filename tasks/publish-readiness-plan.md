# Varian Full-Stack Publish Readiness Plan

## Goal
Prepare the existing Flutter Web + Supabase application for a controlled public release. The Firebase Hosting site `https://varian.web.app` is already live; this plan does not treat deployment as proof of product or security readiness.

## Constraints
- Preserve the existing large set of modified and untracked files; do not revert, clean, commit, or push unrelated work.
- Do not make destructive production DB changes, change auth/CORS behavior, introduce a paid service, or alter external integrations without explicit approval.
- User data handling, account isolation, and backups must be verified before claiming production readiness.
- Fix and record tests; never report a blocked command as passing.

## Phases and acceptance criteria

### 0. Establish clean verification environment
- [ ] Identify and safely release the process/file handle locking `varian-capture-build-diag/native_assets/windows/sqlite3.dll`; do not terminate unknown processes blindly.
- [ ] Run the focused migration test, full Flutter suite, analyzer, and Web build from a consistent SDK/dependency state.
- [ ] Record every failing, skipped, or environment-blocked check.

### 1. Release architecture and configuration
- [ ] Inventory application/backend routes, auth providers, redirects, function endpoints, storage buckets, and public vs privileged configuration.
- [ ] Establish staging separate from production and document deploy targets/rollback method.
- [ ] Confirm publishing metadata, app title/assets, error/loading states, responsive Web behavior, and supported-browser matrix.

### 2. Database and authorization assurance
- [ ] Audit every exposed table, view, RPC, storage bucket/policy, and Edge Function against an access matrix (anonymous, owner, member roles, unrelated account).
- [ ] Add regression checks and run two-account integration tests proving unauthorized cross-project reads/writes fail.
- [ ] Inspect every `verify_jwt=false` function for its own auth/signature validation, origin policy, rate/size limits, and abuse/cost bounds.
- [ ] Resolve SQL lint warnings based on function definitions and tests; avoid changing production semantics without verified migration.
- [ ] Verify database and asset backup/restore procedure in non-production.

### 3. Web security and privacy
- [ ] Observe CSP reports on the deployed app; enumerate legitimate script/connect/image/font/media origins, then enforce a least-privilege CSP and retest all primary flows.
- [ ] Audit public client keys vs secrets and remove privileged credentials from client bundles/history if any are found; rotate exposed secrets.
- [ ] Verify auth redirects, password reset, session expiry/logout, account deletion, file size/type limits, URL-fetch SSRF controls, and errors that might leak internals.
- [ ] Publish privacy policy, terms, support/contact details, and data retention/export/deletion disclosures.

### 4. Product verification and operations
- [ ] Browser E2E smoke tests on desktop/mobile viewport for signup/login/recovery, create/edit/save/reload, import/export, upload/download, collaboration, and logout.
- [ ] Add production error/performance monitoring, uptime checks, quota/cost alerts, and an incident/rollback runbook.
- [ ] Review dependency advisories using Flutter/Dart tooling and verify licenses for shipped dependencies/assets.

### 5. Release gate
- [ ] All blocking tests pass; all exceptions are documented and accepted.
- [ ] Staging verification and security headers/CSP checks pass.
- [ ] Backup/restore and rollback are demonstrated.
- [ ] Obtain explicit approval before promoting to production or changing production auth/backend policy.

## Current known state
- Firebase Hosting site `varian` in project `varian-web-prod` is deployed at `https://varian.web.app`.
- Web build and `flutter analyze` passed in the prior session.
- Core anonymous access revoke migration `20261009000000_revoke_public_canvas_access.sql` was applied to the linked Supabase project.
- Live headers verified; CSP is Report-Only pending origin inventory.
- Full Flutter tests remain blocked by an undeletable/locked `sqlite3.dll` under `varian-capture-build-diag`.
- Supabase db lint previously reported warnings in `authorize_ai_job_v2` and `validate_workspace_plugin_manifest`.
- Current repo has extensive pre-existing modifications/untracked files; work must remain narrowly scoped.
