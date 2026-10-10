# Checklist Roadmap Lanjutan Creative Studio

Dokumen ini melengkapi `tasks/creative-studio-roadmap-todo.md` tanpa mengubah
checklist Milestone A–G yang sudah ada.

## Milestone H — Production Confidence

- [x] H1: Golden selection, transform, nesting, clipping, locked/hidden node, text editing, dan high-DPI.
- [x] H2: Interactive large-canvas benchmark dengan vector, image, raster, video, dan GLB.
- [ ] H3: Windows host ↔ Chrome guest collaboration verification.
  - [x] Chrome and Windows target-specific Realtime transport preflight passes via `tool/collaboration_platform_matrix.ps1`; latest evidence is `output/collaboration-matrix/20260914T081156Z/`.
- [ ] H4: Chrome host ↔ Windows guest collaboration verification.
  - [x] Chrome and Windows target-specific Realtime transport preflight passes via `tool/collaboration_platform_matrix.ps1`; latest evidence is `output/collaboration-matrix/20260914T081156Z/`.
- [x] H5: Role transition, kick, revoke, follow consent, screen tracking, reconnect, dan duplicate-operation test.
- [x] H6: Remote presenter transport + expiry/revoke backend enforcement.
- [x] H7: Governance backend: workspace policy, quota, retention, delete/export, audit, dan billing hooks.
- [x] H8: AI provider health/quota backend enforcement.
- [x] H9: AI mask payload dan variants replace/insert persistence end-to-end.
- [x] H10: Personal/team template sync dan save-selection-as-template workflow.

### Checkpoint H

- [x] Golden, focused tests, full tests, benchmark smoke, Web build, dan Windows build lulus.
- [ ] Evidence dua arah collaboration matrix tersimpan.
  - [x] Matrix target runtime, logs, dan status blocker produksi tersimpan di `output/collaboration-matrix/20260914T081156Z/`.
- [x] Reconnect/revoke tidak menghasilkan duplicate operation atau stale presence.

## Milestone I — Canvas Navigation dan Precision

- [x] I1: Pages/sections, breadcrumbs, minimap, zoom-to-content, viewport bookmarks, focus mode.
- [x] I2: Searchable command palette, shortcut discoverability, tool history, dan context action consistency.
- [x] I3: Rulers, guides, grid presets, smart guides, snap modes, constraints, dan measurement.
- [x] I4: Nested auto-layout, spacing presets, align/distribute, dan layout presets.
- [x] I5: Deep-select, select-through, isolate, layer colors, multi-edit, batch rename, safe delete.

## Milestone J — Pro Design Engine

- [x] J1: Pen tool, node/handle editing, path split/join, boolean, stroke, gradient, mask, effect.
- [x] J2: Rich text spans, paragraph/list, text styles, variable font, link, spellcheck/IME, text-on-path.
- [x] J3: Non-destructive image crop, adjustment stack, background mask, replace, dan batch relink.
- [x] J4: Component variants, slot/override/reset, token binding, library pinning, usage search.
- [x] J5: Inspect mode dan CSS/Flutter/SVG/JSON handoff export.

## Milestone K — Review dan Versioning

- [x] K1: Mentions, attachment, pin-to-node, resolve/reopen, label, assignee, due date, notifications.
- [x] K2: Named checkpoint, auto checkpoint, visual diff, restore copy/in-place, branch/duplicate.
- [x] K3: Approval state, reviewer access, spotlight, walkthrough, handoff checklist, publish preview.
- [x] K4: Sync health, pending operation list, conflict explanation, per-operation retry, recovery export.

## Milestone L — AI Creative OS

- [x] L1: Local-first semantic index untuk node, asset, comment, version, dan provenance.
- [x] L2: Context-aware copilot untuk selection, frame, page, project, dan asset collection.
- [x] L3: Preview/apply/reject/replace/insert/retry/cancel sebagai transaction command.
- [x] L4: Model allowlist, quota, budget alert, fallback policy, retention, redaction, provenance export.
- [x] L5: Deterministic AI evaluation fixtures untuk prompt, mask, seed, cost, latency, dan safety.

## Milestone M — Media dan Motion

- [ ] M1: Waveform, clip trim/split, markers, poster, speed, captions, subtitle track, proxy media.
  - [x] Timeline model/editor untuk trim, split, markers, poster, speed, caption, dan subtitle cue.
  - [x] Waveform aktual untuk PCM WAV dan backend native bytes untuk format terkompresi.
  - [x] Waveform decoder MP3/AAC/OGG dan audio track container melalui `audio_decoder`; fallback tetap aman jika backend platform tidak tersedia.
  - [ ] Verifikasi runtime decoder pada Windows/Web/Android/iOS dan fixture media lintas platform.
    - [x] Windows: MP3, M4A, dan WAV lulus; OGG ditandai `unsupported` karena batas Windows Media Foundation.
    - [x] Web: MP3, OGG, dan M4A lulus melalui probe Chrome nyata; headless `flutter test` tidak dijadikan bukti runtime.
    - [x] Android API 34: MP3, OGG, M4A, dan WAV lulus melalui emulator.
    - [ ] iOS: menunggu simulator atau device iOS.
  - [x] Codec-aware audio trim untuk satu clip aktif dan proxy transcode WAV/M4A.
  - [ ] Multi-clip concat/split dan video proxy transcode berbasis codec.
  - [x] Multi-clip audio trim, filter disabled clip, validasi format PCM, concat WAV, dan output M4A sudah diuji.
    - [x] Process-backed video proxy adapter dengan command planner, trim, multi-clip concat, timeout, temporary-file cleanup, dan explicit unavailable state tersedia untuk runtime yang menyediakan encoder.
    - [ ] Encoder binary/codec runtime belum tersedia pada host ini; fallback copy sengaja ditolak. Runtime resolver and release probe are implemented in `lib/features/media/data/media_codec_runtime.dart` and `tool/media_codec_probe.dart`.
- [x] M2: Prototype links, states, hover/press/drag, overlays, transitions, preview, deep links.
- [x] M3: 3D camera bookmarks, annotations, material/light presets, snapshot render, diagnostics.
- [ ] M4: Background media processing dengan cancellation, retry, checksum, dan storage policy.
  - [x] Serial queue, cooperative cancellation, retry, checksum validation, dan storage policy.
  - [x] Windows video-frame thumbnail dengan fallback lintas platform.
  - [x] Durable resume setelah app/process restart melalui checkpoint store.
  - [x] Sumber `data:`, `blob:`, dan `memory:` dikecualikan dari durable checkpoint.
  - [x] SharedPreferences checkpoint diuji untuk persist, concurrent write, remove, dan ephemeral source.
  - [x] Checkpoint memiliki batas count/byte, transactional eviction, dan observer event untuk skip/eviction/error.
  - [x] Isolate runner untuk decode WAV dan raster image; video decoder tetap platform-bound.
  - [ ] Native worker isolation untuk pekerjaan CPU/media berat.
    - [x] Pure PCM concat dan raster/WAV processing berjalan lewat Dart isolate.
    - [x] Process-backed video adapter meneruskan cooperative cancellation sampai proses codec dan membersihkan temporary output.
    - [ ] Native codec worker cancellable belum tersedia di dependency platform saat ini.

## Milestone N — Portability

- [ ] N1: SVG/PDF/PPTX/draw.io/Markdown/CSV/image bundle import matrix + loss report.
  - [x] Import contract, loss-report, Draw.io/Markdown/CSV/image-bundle, dan embedded-asset paths memiliki coverage lokal.
  - [x] PPTX slide geometry/text diimpor sebagai frame dan shape editable melalui parser ZIP/XML dengan loss report dan fallback attachment auditable.
  - [x] PPTX embedded raster images direlasikan dari `ppt/slides/_rels` ke `ppt/media` sebagai asset durable dan node image editable.
  - [x] PDF page, literal text operator, basic rectangle/path (`re/f/S/B`, `m/l/c/v/y/h`), dan embedded JPEG XObject diimpor sebagai frame/text/shape/vector/image editable melalui parser byte-level lintas platform, dengan loss report dan fallback attachment auditable.
  - [x] PDF text, checkbox, radio, choice, dan push-button widgets diimpor sebagai node editable; annotation kompleks tetap masuk loss report.
  - [ ] PDF vector/image/form fidelity penuh lintas platform belum tersedia.
- [ ] N2: PNG/JPEG/WebP/SVG/PDF/video/presentation/native export presets dan export queue.
  - [x] PNG/JPEG/WebP/SVG/PDF, presentation contract, native presets, dan export queue memiliki coverage lokal.
  - [x] Video codec export memiliki process-backed adapter dan command contract; aplikasi mengembalikan explicit unavailable/failure state bila encoder tidak tersedia.
  - [ ] Native encoder binary/codec bundling dan target-platform validation belum tersedia. Runtime discovery now reports configured, bundled, and `PATH` candidates without silently copying source bytes.
- [x] N3: Package health check, repair, partial import, merge/duplicate, encryption, checksum, migration preview.

## Milestone O — Platform dan Ecosystem

- [ ] O1: Plugin SDK, API versioning, capability declaration, permission review, sandbox limit, compatibility kit.
  - [x] Manifest API version, capability declaration, extension points, sandbox limits, compatibility kit, command gate, local plugin registry, permission review/persistence/UI, dan runtime quota guard tersedia secara lokal.
  - [x] Remote plugin registry migration/RPC, owner-only approval, exact permission matching, state transitions, backend command authorization, dan local-first Governance sync tersedia di source.
  - [x] Unknown permission parsing, exact persisted approval enforcement, dan remote uninstall deletion/audit path tersedia di source; migration `20260914040000` sudah dipush.
  - [ ] Permission enforcement, sandbox runtime, dan plugin registry production belum terhubung.
- [ ] O2: Organization/workspace hierarchy, SSO/SCIM readiness, project transfer, retention/legal hold, admin dashboard.
  - [x] Kontrak hierarchy, roles, guest policy, SSO/SCIM readiness, transfer, legal hold, data request, audit, dan dashboard tersedia secara lokal.
  - [ ] Organization identity, SSO/SCIM, legal hold, dan admin enforcement production belum tersedia.
- [ ] O3: Storage/transfer/AI/render/seat usage ledger, plan limit, grace period, overage, webhook idempotency.
  - [x] Usage ledger idempotent, limit/grace/overage policy, entitlement cache, webhook dedupe, dan invoice metadata tersedia secara lokal.
  - [x] Signed billing webhook HMAC/replay protection, entitlement table/RPC, provider-field redaction, stale-revision guard, Flutter RPC client, dan Governance visibility tersedia di source.
  - [ ] Billing provider, metering backend, dan entitlement enforcement production belum terhubung.
- [ ] O4: Localization, RTL, IME, screen reader, high contrast, color-blind-safe tokens, reduced motion.
  - [x] Locale English/Indonesian, text scale, RTL, color-safe mode, persisted accessibility profile, dan touch-target audit tersedia secara lokal.
  - [x] Runtime binding untuk reduced motion, high contrast, keyboard-only navigation, focus highlight, dan larger text diterapkan di app root dengan test contract.
  - [ ] Validasi runtime penuh untuk IME, screen reader, high contrast, dan device matrix belum selesai.
- [ ] O5: Opt-in diagnostics, feature flags, health endpoint, support bundle, release channel, backup/restore drill.
  - [x] Opt-in diagnostics, deterministic flags, health response, redaction, migration telemetry, release/rollback policy, dan restore drill tersedia secara lokal.
  - [x] Observability event RPC, redacted support bundle delivery, release policy RPC, authenticated workspace health RPC, dan public `workspace-health` probe tersedia di source.
  - [x] Workspace operability migration, `workspace-health` Edge Function, `APP_VERSION` secret, dan HTTP 200 smoke probe sudah dijalankan pada project production.
  - [x] Service-role-only retention maintenance migrations `20260914030000` and `20260914030100`, fail-closed `workspace-retention` Edge Function, and unauthenticated production probe sudah diverifikasi.
  - [ ] Billing webhook secret/provider, external monitor, dan retention operation masih belum dikonfigurasi pada project production.

## Release Gates

- [ ] Setiap feature slice memiliki schema/migration, command history, permission, persistence, dan export decision.
- [ ] Empty/loading/error/unavailable/cancel/retry/offline state tersedia.
  - [x] Deterministic state/recovery matrix lulus VM, Chrome, dan Windows pada `output/state-matrix/20260914T081132Z/`.
- [ ] Visual feature memiliki golden; interaction feature memiliki deterministic test.
- [x] Web dan Windows build lulus; performance smoke/large-canvas budget tidak regress.
- [x] User documentation dan migration note diperbarui; blocker produksi tetap dicatat eksplisit.
