# Creative Studio Release Evidence — 2026-09-12

- Canvas navigation now persists pages/sections, viewport bookmarks, active page, and focus mode locally; the editor exposes breadcrumbs, zoom-to-content, bookmark management, and a focus-mode exit control.
- Canvas interaction evidence now includes locked/hidden hit-test exclusion and shape-label text editing; the focused preview, golden, navigation, and hit-test suites pass.
- On September 13, 2026, non-destructive image editing was release-checked: normalized crop metadata, focal point, adjustment stack, background mask, replace semantics, and deterministic batch relink are covered by model, painter, asset-service, and inspector tests.
- On September 13, 2026, AI mask and variant persistence was release-checked: structured mask strokes render to PNG for image edits, runtime image bytes remain redacted from local history, replace and insert workflows retain source-node/output semantics, and variant favorite/compare state survives reload.
- On September 13, 2026, global AI governance persistence was completed: the owner-guarded `upsert_workspace_ai_governance` RPC stores the global policy, synchronizes provider rows, removes deleted provider policies, and records a redacted audit event. Migration `20260913000005` is applied to the linked Supabase project.

## Fresh automated evidence

- Full `flutter test --no-pub` passed with 1,079 tests after the Copilot context, vector appearance, and AI governance persistence slice.
- `flutter analyze --no-pub` passed with no issues.
- `flutter build web --release --no-pub` completed successfully and produced `build/web`.
- `flutter build windows --release --no-pub` completed successfully and produced `build/windows/x64/runner/Release/varian.exe`.
- `powershell -ExecutionPolicy Bypass -File tool/creative_studio_release_gates.ps1` passed analyzer, golden/interactive benchmark tests, and both benchmark scenarios.
- `test/features/ai/ai_copilot_context_test.dart`, vector appearance regressions, and the AI governance migration contract test passed.
- `flutter test --no-pub test/features/canvas/inspector_panel_test.dart test/features/assets/image_relink_service_test.dart test/features/image_asset/image_asset_test.dart` passed with image editing inspector, relink matching, serialization, and loaded-mask painter coverage.
- `flutter run -d windows --no-pub` started the debug runtime successfully, initialized Supabase and media_kit, and exited cleanly after the smoke check.
- `git diff --check` completed successfully; only Git line-ending normalization warnings were emitted.
- `dart run tool/benchmarks/creative_studio_benchmark.dart` passed both `smoke` and `large-canvas` scenarios.
- `test/features/collaboration/collaboration_two_client_test.dart` passed 10 control-plane tests covering editor/viewer delivery, role transition guard, follow consent/stop, screen-share rejection/cleanup, member removal, room revoke, reconnect behavior, and duplicate CRDT delivery.
- `test/features/collaboration/screen_tracking_service_test.dart` verifies that OS/browser capture denial becomes a user-facing error and cleans up peer/renderer state; it passes on Chrome and Windows targets.
- Duplicate CRDT delivery is now verified across both Realtime broadcast and durable operation storage; repeated delivery converges to one materialized state and one stored operation.
- `flutter test --no-pub -d chrome test/features/performance/interactive_canvas_benchmark_test.dart` and the equivalent Windows target both passed the large-canvas paint/gesture benchmark.
- `test/features/performance/interactive_canvas_benchmark_test.dart` now asserts unique node IDs in the large-canvas fixture so benchmark results cannot be masked by duplicate identity.
- Web runtime smoke confirmed that unauthenticated room creation is blocked before cloud mutation and presents `Sign in before creating a collaboration room.`; artifact: `output/playwright/runtime-host-auth-preflight.png`.
- Cloud snapshot error handling now preserves actionable `SyncException` messages instead of replacing auth failures with a generic sync error.
- `flutter test --no-pub test/features/collaboration/collaboration_session_provider_test.dart test/features/collaboration/collaboration_two_client_test.dart test/features/collaboration/collaboration_test.dart test/features/presentation/remote_presenter_control_test.dart test/supabase/presenter_remote_control_migration_test.dart test/features/governance/workspace_governance_dialog_test.dart test/supabase/workspace_governance_migration_test.dart test/features/canvas/canvas_golden_test.dart` passed with 38 tests.
- On September 14, 2026, `powershell -ExecutionPolicy Bypass -File tool/collaboration_platform_matrix.ps1` passed the two-client Realtime transport suite on Chrome and Windows. The generated logs and report are under `output/collaboration-matrix/20260914T030557Z/`.
- On September 14, 2026, `powershell -ExecutionPolicy Bypass -File tool/creative_studio_state_matrix.ps1` passed 57 deterministic state/recovery tests on VM, Chrome, and Windows. The generated logs and report are under `output/state-matrix/20260914T031144Z/`.
- On September 14, 2026, `flutter test --no-pub test/features/import/pptx_import_test.dart test/features/import/import_package_preview_test.dart test/features/import/import_service_archive_test.dart test/features/import/import_dialog_test.dart` passed 12 import tests. PPTX slide geometry/text now imports as editable frame/shape nodes through `lib/features/import/pptx_editable_importer.dart`; invalid archives fall back to an auditable file card.
- On September 14, 2026, `dart analyze lib/features/import/pptx_editable_importer.dart lib/features/import/import_service.dart lib/features/import/import_loss_report.dart` passed with no issues.
- On September 14, 2026, `flutter test --no-pub test/features/import/pdf_import_test.dart test/features/import/pptx_import_test.dart test/features/import/import_package_preview_test.dart test/features/import/import_service_archive_test.dart test/features/import/import_dialog_test.dart` passed 14 import tests. PDF pages, literal text operators, and basic rectangle paths now import as editable frame/text/shape nodes through `lib/features/import/pdf_editable_importer.dart`; invalid PDFs still fall back to an auditable file card.
- On September 14, 2026, `dart analyze lib/features/import/pdf_editable_importer.dart lib/features/import/pptx_editable_importer.dart lib/features/import/import_service.dart lib/features/import/import_loss_report.dart` passed with no issues.
- On September 14, 2026, `flutter test --no-pub test/features/governance/plugin_registry_test.dart test/features/governance/plugin_compatibility_test.dart` passed 7 governance tests. `lib/features/governance/domain/plugin_registry.dart` now enforces compatibility, explicit permission review, enable/disable state, command rate limits, and JSON persistence locally; production registry/runtime integration remains pending.
- On September 14, 2026, `dart analyze lib/features/governance/domain/plugin_registry.dart` passed with no issues.
- On September 14, 2026, `flutter test --no-pub test/features/governance/plugin_registry_test.dart test/features/governance/plugin_compatibility_test.dart` passed 8 governance tests. The local plugin runtime now enforces event-subscription, storage-byte, and network-request sandbox limits in addition to permission review and command rate limits.
- On September 14, 2026, `flutter test --no-pub test/features/media/media_processing_worker_test.dart test/features/media/media_processing_isolate_runner_test.dart test/features/media/media_processing_queue_test.dart test/features/media/media_artifact_store_test.dart test/features/export/export_capabilities_test.dart` passed 34 media/export tests. Video proxy remains explicitly unavailable without a real platform encoder; audio/raster processing, cancellation, retries, checksums, checkpoint resume, and artifact policy remain covered.
- On September 14, 2026, `flutter analyze --no-pub` passed with no issues after the import and plugin-runtime slices.
- On September 14, 2026, `powershell -ExecutionPolicy Bypass -File tool/creative_studio_release_gates.ps1` passed: analyzer clean, 10 golden/benchmark tests green, and smoke/large-canvas benchmark scenarios passed.
- On September 14, 2026, `flutter build web --no-pub` passed and produced `build/web` after the Wasm dry run completed successfully.
- On September 14, 2026, `flutter build windows --no-pub` passed and produced `build/windows/x64/runner/Release/varian.exe`.
- On September 14, 2026, `flutter test --no-pub test/features/media/media_video_proxy_transcoder_test.dart` passed 5 tests. The process-backed video adapter now builds deterministic trim/concat commands, rejects unsupported formats before process launch, cleans temporary files, propagates cooperative cancellation, and reports `unsupported` without copying source bytes when the encoder executable is absent.
- On September 14, 2026, the host encoder probe found no `ffmpeg`/`ffprobe` executable, so target runtime codec validation remains pending rather than being marked production-ready.
- `test/features/collaboration/collaboration_two_client_test.dart` now covers a real Realtime `member_removed` delivery and verifies that a removed guest does not persist a CRDT snapshot during leave.
- `test/features/canvas/canvas_golden_test.dart` covers selection/transform, nested frame clipping, and selected orthogonal edge repair. Baselines are stored in `test/features/canvas/goldens/`.
- `test/supabase/presenter_remote_control_migration_test.dart` verifies consent, role, expiry, revoke, command idempotency, grants, and public/anonymous denial in the presenter RPC migrations.
- `flutter test --no-pub -d chrome test/features/collaboration/collaboration_two_client_test.dart` passed all 10 transport/control-plane tests on the Chrome target.
- `flutter test --no-pub -d windows test/features/collaboration/collaboration_two_client_test.dart` passed all 10 transport/control-plane tests on the Windows target.
- `flutter test --no-pub -d chrome test/features/collaboration/screen_tracking_service_test.dart` passed the capture-denial cleanup test on the Chrome target.
- `flutter test --no-pub -d windows test/features/collaboration/screen_tracking_service_test.dart` passed the capture-denial cleanup test on the Windows target.
- Screen-tracking lifecycle hardening now reports viewer peer-connection, signal, and remote-video failures as recoverable user-facing errors, disposes renderers during cleanup, and accepts numeric or string ICE line indexes.
- Native screen capture now enumerates desktop screen sources before calling `getDisplayMedia`, which is required by the Windows WebRTC adapter; Web keeps the browser-native capture path.
- The focused collaboration suite passed 69 tests after the lifecycle hardening; `flutter analyze --no-pub`, `flutter build web --no-pub`, and `flutter build windows --no-pub` also passed.
- After the collaborator-panel fallback copy was repaired, `dart format --output=none --set-exit-if-changed lib/features/collaboration/presentation/widgets/collaborators_panel.dart`, `flutter analyze --no-pub`, `flutter test --no-pub test/features/collaboration` (62 tests), `flutter test --no-pub` (946 tests), `flutter build web --no-pub`, and `flutter build windows --no-pub` all passed again.
- The collaboration transport and screen-tracking focused tests also passed on Chrome and Windows targets (12 tests per target); the benchmark smoke and large-canvas scenarios passed, and `git diff --check` reported only existing line-ending normalization warnings.
- The repository release-gate script `powershell -ExecutionPolicy Bypass -File tool/creative_studio_release_gates.ps1` passed `flutter analyze`, the creative-studio golden smoke suite (9 tests), the interactive large-canvas benchmark test, and both benchmark scenarios.
- On September 13, 2026, `supabase migration list --linked` confirmed that every local migration through `20260913000005` is applied to the linked remote project. Docker is still not running locally, so this verifies the authoritative remote state rather than a local Postgres execution.

## Manual collaboration evidence

The repeatable Web smoke artifacts are in `output/playwright/`, including roster/role, follow consent, screen-tracking request/stop state, guest rejoin/reconnect, member removal, and room revoke screenshots.

The target-specific preflight is repeatable with `tool/collaboration_platform_matrix.ps1`:

| Runtime | Local Realtime transport suite | Production two-client proof |
| --- | --- | --- |
| Chrome | Passed on September 14, 2026 | Pending |
| Windows | Passed on September 14, 2026 | Pending |

The generated report explicitly keeps the Windows/Chrome production pair pending because the local suite does not exercise Supabase auth, RLS, or two independent app processes.

The state-gate report explicitly keeps iOS decoder runtime, native video codec
processing, and production collaboration evidence pending when their required
runtime/backend is not available.

## Manual cross-platform verification runbook

Run this matrix only with two already-authorized user sessions; do not create a
test account and do not reuse room ID `731904`. Use an isolated browser profile,
not a personal Chrome profile.

1. Start the Web client with `flutter run -d chrome` and the Windows client with
   `flutter run -d windows` using the same configured Supabase project.
2. On the host client, sign in, open the same project, create a collaboration room,
   and record the newly generated six-digit room ID.
3. On the guest client, sign in with the second authorized session and join that
   room ID. Confirm roster, role, and initial document state before editing.
4. Execute the following checks in both directions: node create/move/text edit,
   role transition, follow request/approval/stop, reconnect, member removal,
   room revoke, duplicate-operation check, and screen tracking request/stop.
5. For screen tracking, accept the real browser/OS capture prompt, confirm remote
   video frames arrive, stop from the sharer, and confirm peer/renderer cleanup.
6. Save one screenshot per direction and record client platform, build revision,
   room expiry, and the result in the matrix below.

| Host | Guest | Result | Evidence |
| --- | --- | --- | --- |
| Windows | Chrome | Pending | Capture after a real two-client run |
| Chrome | Windows | Pending | Capture after a real two-client run |

## Known verification gaps

- Windows host ↔ Chrome guest and Chrome host ↔ Windows guest have not been checked in this environment. Native computer-use currently reports that its Codex auth token and app inventory are unavailable.
- Actual OS/browser screen-capture consent and media delivery remain unproven; only request, in-app consent, signaling state, and stop cleanup are covered.
- Local Supabase SQL execution is unavailable while Docker Desktop is stopped; the linked remote project is synchronized through `20260913000005`, and migration contract tests remain the local offline safety net.

The roadmap keeps these gaps unchecked rather than treating Web-only evidence as cross-platform proof.
