# Checklist Roadmap Creative Studio

> `[x]` berarti sudah memiliki implementasi dan bukti test/build pada workspace ini. Item benchmark, golden, dan verifikasi host cross-platform tidak dicentang tanpa evidence khusus.

## Milestone A — Core Contract

- [x] Tetapkan document package v2 dan compatibility policy.
- [x] Buat migration registry dari schema lama ke schema baru.
- [x] Tambahkan asset manifest, checksum, MIME, size, dan durable artifact ID.
- [x] Pisahkan document JSON dari binary/preview/cache artifact.
- [x] Tambahkan package import validator dan missing-asset recovery.
- [x] Ubah mutation path menjadi transactional command bus.
- [x] Tambahkan command coalescing untuk drag, resize, dan text editing.
- [x] Tambahkan replay/debug export untuk command history.
- [x] Tambahkan serialization, migration, dan package round-trip tests.

## Milestone B — Reliable Editing

- [x] Tambahkan local journal, crash recovery, retry queue, dan sync pause/resume.
- [x] Tambahkan conflict state serta keep-local/keep-remote/merge UX.
- [x] Lengkapi transform parity: rotate, aspect lock, center resize, keyboard nudge,
  scale-with-children, dan group/frame coordinate conversion.
- [x] Audit semua mutasi agar role/permission guard berada sebelum command enqueue.
- [x] Buat shortcut map dan input behavior matrix untuk Web, Windows, Android,
  mouse, trackpad, touch, dan stylus.
- [x] Tambahkan golden tests untuk selection, transform, nesting, dan edge repair.

## Milestone C — Scale and Collaboration

- [x] Tambahkan spatial index, visible-node culling, repaint profiling, dan
  progressive media loading.
- [x] Buat benchmark document untuk node, image, raster stroke, video, dan GLB.
- [x] Tetapkan frame-time, memory, startup, dan sync latency budget.
- [x] Selesaikan verification Windows host ↔ Chrome guest dan Chrome host ↔
  Windows guest melalui runtime matrix lokal; production session evidence tetap
  dicatat sebagai external gate.
- [x] Verifikasi role change, kick, revoke, follow consent, screen tracking,
  reconnect, dan duplicate-operation prevention.
- [x] Tambahkan audit log serta session diagnostics yang tidak membocorkan secret.

## Milestone D — Design Workflow

- [x] Tambahkan variables/tokens untuk color, typography, spacing, radius, dan
  shadow.
- [x] Tambahkan publishable component library dengan override/reset semantics.
- [x] Tambahkan team/personal templates dan starter project wizard.
- [x] Upgrade asset library dengan folder, tag, search, version, duplicate
  detection, relink, replace, thumbnail, dan license/provenance.
- [x] Tambahkan asset package include/exclude policy saat export.

## Milestone E — AI Workflow

- [x] Buat capability matrix implemented/configured/experimental/unavailable.
- [x] Persist job history, prompt, model, provider, seed, cost, status, dan
  source/output artifact references.
- [x] Tambahkan mask/brush editor untuk inpaint, outpaint, object, dan background
  operations.
- [x] Tambahkan output variants, compare view, favorite, retry, cancel, dan
  explicit replace/insert semantics.
- [x] Tambahkan provenance, license notice, provider health, quota, dan safe
  secret handling.
- [x] Pisahkan production provider dari experimental provider gate.

## Milestone F — Presentation and Motion

- [x] Tambahkan frame order, hotspot validation, transitions, speaker notes, dan
  presenter view.
- [x] Tambahkan storyboard shot list dan timeline yang terpisah dari static
  canvas semantics.
- [x] Tambahkan seek-safe playback dan deterministic PDF/video export.
- [x] Tambahkan remote presenter control dengan permission dan expiry.

## Milestone G — Distribution and Governance

- [x] Tambahkan published snapshot, read-only share link, expiry/password, embed,
  watermark, dan download policy.
- [x] Tambahkan plugin manifest, permission scopes, local sandbox, dan event API.
- [x] Tambahkan accessibility audit, reduced motion, keyboard-only flow, dan
  remappable shortcuts.
- [x] Tambahkan workspace/team permission, quota, audit, retention, delete/export,
  dan billing integration hooks.
- [x] Jadikan analyze, focused tests, full tests, dan Web/Windows builds sebagai
  verified release gates.
- [x] Tambahkan golden smoke test dan benchmark smoke sebagai release gates.
- [x] Perluas golden coverage untuk selection, transform, nesting, dan edge repair.

## Checkpoint

### Setelah Milestone A–B

- [x] Legacy project terbuka tanpa migration loss.
- [x] Crash/offline/restart tidak kehilangan perubahan terakhir.
- [x] Undo/redo, permission guard, dan transform tests lulus.

### Setelah Milestone C–D

- [x] Benchmark besar tetap interaktif.
- [x] Collaboration cross-platform lokal lulus reconnect dan revoke pada matrix
  Chrome ↔ Windows.
- [ ] Collaboration production lulus dengan dua authorized Supabase sessions,
  backend RLS, dan media-delivery evidence.
- [x] Library, template, dan asset package dapat round-trip.

### Setelah Milestone E–G

- [x] AI job dan artifact dapat dipulihkan serta diaudit.
- [x] Presentation export deterministik.
- [x] Published snapshot tidak berubah sebelum explicit publish.
- [x] Release gates terverifikasi pada Web dan Windows; golden/benchmark smoke lulus.
