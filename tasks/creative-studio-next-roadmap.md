# Roadmap Lanjutan: Creative Canvas Studio Matang dan Solid

**Tanggal:** 12 September 2026  
**Status:** Proposed  
**Scope:** Setelah Milestone A–G pada `tasks/creative-studio-roadmap-todo.md`

## Tujuan

Mengubah aplikasi yang sudah kaya fitur menjadi produk yang terasa dapat dipercaya
untuk pekerjaan kreatif nyata. Prioritas bukan menambah node sebanyak mungkin,
melainkan membuat siklus berikut konsisten:

```text
Discover → Create → Iterate → Review → Publish → Reuse
```

Setiap capability baru harus hidup di atas document model, command history, asset
system, permission, persistence, dan export yang sama.

## Diagnosis Saat Ini

Fondasi sudah mencakup infinite canvas, command bus, local recovery, asset library,
diagram, Mermaid, drawing, AI workflow, 3D, video, presentation, collaboration,
templates, publishing, plugin sandbox, accessibility, dan governance contract.

Produk belum layak disebut production-solid sebelum gap berikut ditutup:

1. Golden coverage untuk selection, transform, nesting, dan edge repair.
2. Benchmark besar dengan bukti interaktif nyata, bukan hanya specification/harness.
3. Verifikasi dua arah Windows host ↔ Chrome guest dan Chrome host ↔ Windows guest.
4. Reconnect, role transition, revoke/kick, follow consent, screen tracking, dan
   duplicate-operation prevention pada dua client nyata.
5. Transport backend untuk remote presenter, governance/team policy, AI quota/health,
   template sync, serta retention/delete/export.
6. AI mask benar-benar masuk ke payload provider dan output variants dapat diterapkan
   sebagai replace/insert yang tersimpan di document history.

Fase pertama harus menutup gap tersebut. Fitur baru yang tidak meningkatkan
reliability, canvas precision, review, atau reuse ditunda.

## Prinsip Prioritas

- **Reliability before breadth:** satu alur yang dapat dipulihkan lebih bernilai
  daripada beberapa tool baru yang rapuh.
- **Vertical slice:** domain, storage, command, UI, permission, sync, dan test
  selesai dalam satu feature slice.
- **Non-destructive by default:** preview, replace, apply, dan delete selalu dapat
  di-undo atau dipulihkan melalui version history.
- **Cross-platform contract:** setiap fitur interaksi diuji minimal pada Web dan
  Windows; mobile memakai capability fallback yang eksplisit.
- **Evidence-driven performance:** klaim interaktif harus didukung benchmark,
  profiling, dan soak test pada data realistis.
- **One context graph:** asset, node, comment, AI job, version, dan provenance
  harus dapat ditelusuri ke project dan workspace.

## Milestone H — Production Confidence

### H1. Visual regression dan interaction golden

Lengkapi golden untuk selection box, rotated resize, group/frame nesting, clipping,
edge repair, locked/hidden node, text editing, dan high-DPI scale.

**Acceptance criteria**

- Golden berjalan pada theme light/dark dan minimal dua device-pixel-ratio.
- Golden failure menghasilkan diff image yang mudah dibaca.
- Selection, transform, nesting, dan edge repair memiliki test perilaku selain
  screenshot.

### H2. Interactive scale benchmark

Bangun fixture realistis dengan kombinasi vector, text, image, raster stroke, video,
dan GLB; ukur startup, pan/zoom, selection, edit, save, memory, dan recovery.

**Acceptance criteria**

- Benchmark menjalankan aksi interaktif deterministik, bukan hanya membuat object.
- Budget frame-time, memory, startup, export, dan sync memiliki pass/fail gate.
- Profiling dapat membedakan render, hit-test, asset decode, dan persistence.

### H3. Collaboration verification matrix

Uji dua client nyata untuk role change, kick, revoke, reconnect, follow viewport,
screen consent, stop share, duplicate operation, offline queue, dan permission
transition.

**Acceptance criteria**

- Windows host ↔ Chrome guest dan Chrome host ↔ Windows guest lulus.
- Operasi tertunda yang kehilangan permission tidak dikirim ulang.
- Reconnect tidak membuat duplicate node, duplicate comment, atau stale presence.

### H4. Backend control plane

Pindahkan remote presenter, governance, AI health/quota, template sync, dan
retention/delete/export dari local contract ke migration, RPC/Edge Function, RLS,
dan integration test.

**Acceptance criteria**

- Backend menjadi enforcement utama; UI hanya feedback.
- Audit log menyimpan actor, operation, target, result, dan correlation ID tanpa
  secret.
- Quota, expiry, revoke, dan retention tetap berlaku setelah client restart.

### Checkpoint H

- `flutter analyze --no-pub` lulus.
- Full test, golden suite, benchmark smoke, Web build, dan Windows build lulus.
- Manual matrix dua client dicatat dengan evidence dan known limitations.

## Milestone I — Canvas Navigation dan Precision

### I1. Workspace navigation

Tambahkan pages/sections, breadcrumbs, minimap, zoom-to-content, viewport bookmark,
focus mode, dan navigator untuk project besar.

### I2. Command palette dan interaction consistency

Sediakan command palette yang searchable, shortcut discoverability, context menu
yang konsisten, tool history, quick actions, dan input parity mouse/trackpad/touch/
stylus/keyboard.

### I3. Precision layout

Lengkapi rulers, guides, grid presets, smart guides, snap modes, constraints,
spacing measurement, align/distribute, nested auto-layout, dan layout presets.

### I4. Selection dan layer ergonomics

Tambahkan deep-select, select-through, isolate, layer color, multi-edit, lock/hidden
filter, ancestor breadcrumbs, batch rename, dan safe delete/relink.

**Acceptance criteria Milestone I**

- Pengguna dapat menemukan node pada project besar tanpa pan manual berulang.
- Semua alignment/layout action menjadi command yang dapat di-undo dan direplay.
- Keyboard, touch, dan stylus memiliki perilaku yang terdokumentasi.
- Tidak ada regressi pada coordinate conversion atau frame nesting.

## Milestone J — Pro Design Engine

### J1. Vector editing production-grade

Lengkapi pen tool, node/handle editing, path split/join, boolean operation, stroke
cap/join/dash, gradient, pattern, clipping mask, opacity mask, blend mode, dan
non-destructive effects.

### J2. Typography

Tambahkan rich text spans, paragraph/list, text styles, variable font axes, text
wrap yang dapat diprediksi, link, spellcheck/IME, text-on-path, dan locale fallback.

### J3. Image editing non-destructive

Tambahkan crop/fit/fill, focal point, adjustment stack, background removal mask,
image replacement tanpa kehilangan transform, dan asset relink batch.

### J4. Components dan design-system workflow

Perkuat component/instance, variants, slot/override/reset, token binding, detach
warning, library version pinning, dan usage/reference search.

### J5. Inspect dan handoff

Sediakan inspect mode untuk ukuran, spacing, tokens, typography, color, asset
provenance, serta export CSS/Flutter/SVG/JSON yang konsisten dengan document version.

**Acceptance criteria Milestone J**

- Path, text, image, component, dan style mutations punya serialization round-trip.
- Apply/revert style tidak merusak override atau instance relationship.
- Export inspect menghasilkan output yang sama pada Web dan Windows.

## Milestone K — Review, Versioning, dan Collaboration UX

### K1. Review comments

Tambahkan mention, attachment, pin-to-node, resolve/reopen, labels, assignee,
due date, notification preference, dan filter unresolved.

### K2. Version history

Tambahkan named checkpoint, auto checkpoint, visual diff, restore as copy, restore
in place, branch/duplicate, dan audit trail yang menghubungkan command dengan version.

### K3. Review/presentation mode

Tambahkan approval state, reviewer-only access, spotlight, guided walkthrough,
speaker notes sync, handoff checklist, dan publish preview yang tidak mengubah draft.

### K4. Sync resilience UX

Tampilkan sync health, pending operations, conflict explanation, retry per operation,
merge preview, and recovery export tanpa mengekspos internal implementation detail.

**Acceptance criteria Milestone K**

- Reviewer dapat memberi feedback tanpa edit permission.
- User dapat membandingkan dan memulihkan version tanpa kehilangan current draft.
- Offline edits, conflict, reconnect, dan revoke mempunyai state yang dapat dipahami.

## Milestone L — AI Creative OS

### L1. Semantic canvas index

Index node text, tags, asset metadata, comments, versions, dan AI provenance secara
lokal-first; cloud embedding bersifat opt-in. Sediakan search berdasarkan isi,
visual reference, dan relationship.

### L2. Context-aware copilot

AI memahami selection, frame, page, project, asset collection, dan conversation
history dengan context budget yang terlihat user. Aksi awal: summarize, organize,
rename, clean diagram, generate copy, translate, alt text, extract tokens, dan
suggest layout.

### L3. Preview/apply workflow

Setiap AI action menghasilkan patch/variant preview dengan explicit apply, replace,
insert, duplicate, reject, retry, cancel, dan undo sebagai satu command transaction.

### L4. Provider governance

Tambahkan model allowlist, per-workspace quota, budget alert, rate limit, provider
fallback policy, data retention choice, prompt/artifact redaction, and provenance
export.

### L5. Evaluation harness

Simpan deterministic fixtures untuk prompt, mask, seed, output schema, latency,
cost, safety result, dan human acceptance; jalankan regression sebelum provider
atau prompt policy berubah.

**Acceptance criteria Milestone L**

- Mask editor menghasilkan payload provider yang benar.
- Variants replace/insert bertahan setelah restart, sync, export, dan undo/redo.
- User dapat melihat model, provider, cost, data policy, dan sumber artifact.
- AI unavailable tidak merusak workflow manual.

## Milestone M — Media, Motion, dan Prototype

### M1. Timeline media

Tambahkan waveform, clip trim/split, markers, poster frame, playback speed, captions,
subtitle track, proxy media, audio mute/volume, dan deterministic export.

### M2. Interactive prototype

Tambahkan node links, states/variants, hover/press/drag interactions, overlays,
transition presets, prototype preview, deep links, dan device viewport presets.

### M3. 3D scene maturity

Tambahkan camera bookmark, scene annotation, material/light preset, snapshot render,
GLB validation diagnostics, dan graceful fallback untuk target tanpa renderer.

### M4. Media processing pipeline

Pisahkan original, proxy, thumbnail, waveform, preview, dan export artifact; proses
secara background dengan cancellation, retry, checksum, dan storage policy.

## Milestone N — Import/Export dan Portability

### N1. Import matrix

Prioritaskan SVG, PDF, PPTX, draw.io, Markdown, CSV, dan image bundle dengan pilihan
editable, flattened, atau reference-only. Tampilkan loss report sebelum commit.

### N2. Export presets

Sediakan PNG/JPEG/WebP, SVG, PDF, video, presentation, native package, transparent
background, selected region, page/frame batch, font policy, dan export queue.

### N3. Package diagnostics

Tambahkan package health check, missing-artifact repair, partial import, merge/duplicate
project, encrypted package option, checksum verification, dan migration preview.

**Acceptance criteria Milestone N**

- Import tidak mengubah document sebelum user menyetujui preview.
- Export menyertakan provenance, version, asset policy, dan error report.
- Project dapat dipindahkan tanpa ketergantungan pada cache lokal.

## Milestone O — Platform, Governance, dan Ecosystem

### O1. Plugin platform

Lengkapi SDK, API versioning, capability declaration, permission review, sandbox
limits, event/command extension, UI extension points, manifest validation, examples,
and compatibility test kit.

### O2. Team administration

Tambahkan organization/workspace hierarchy, SSO/SCIM readiness, role policy, project
transfer, guest policy, audit export, retention/legal hold, delete/export request,
and admin activity dashboard.

### O3. Usage dan billing hooks

Sediakan storage, transfer, AI, render, dan seat usage ledger; plan limits, grace
period, overage policy, webhook idempotency, invoice metadata, dan offline-safe
entitlement cache.

### O4. Accessibility dan localization maturity

Tambahkan localization framework, RTL, IME, screen reader semantics, high contrast,
color-blind-safe tokens, reduced motion, keyboard-only end-to-end tests, dan touch
target audit.

### O5. Operability

Tambahkan opt-in crash/session diagnostics, feature flags, health endpoint, support
bundle, migration telemetry, release channel, rollback procedure, and backup/restore
drill.

## Urutan Eksekusi yang Direkomendasikan

### 0–4 minggu: Confidence release

Milestone H penuh, terutama H1–H3. Jangan menambah node baru selama two-client
verification dan benchmark belum memiliki evidence yang dapat diulang.

### 5–8 minggu: Canvas mastery

Milestone I: navigator, command palette, guides/snapping, precision layout, dan
selection ergonomics.

### 9–12 minggu: Review dan design handoff

Milestone K paralel dengan J1/J2 kecil: comments, version history, visual diff,
inspect mode, dan approval flow.

### 13–16 minggu: AI yang benar-benar berguna

Milestone L: semantic index, context-aware actions, explicit patch apply, quota,
provenance, dan evaluation fixtures.

### Setelah core stabil: Media, portability, ecosystem

Milestone M, N, dan O dijalankan berdasarkan target pasar. Jangan membangun full
PSD editor, full video editor, atau marketplace sebelum usage evidence mendukungnya.

## Definition of Done untuk Setiap Feature Slice

- Domain contract dan schema version ditetapkan.
- Local persistence, crash recovery, sync, dan migration ditentukan.
- Semua mutation melalui command bus dan memiliki undo/redo semantics.
- Permission guard berada sebelum enqueue dan backend tetap melakukan enforcement.
- Empty, loading, error, unavailable, cancel, retry, dan offline state tersedia.
- Focused unit/widget/integration test tersedia; fitur visual memiliki golden.
- Web dan Windows build lulus; input parity direview untuk mobile bila relevan.
- Performance budget dan telemetry/diagnostics ditentukan.
- Export/import/provenance impact dicatat.
- Dokumentasi user-facing dan migration note diperbarui.

## Risiko Utama

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| Terlalu banyak capability sebelum reliability | Tinggi | Bekukan fitur baru sampai Checkpoint H lulus. |
| Document model membesar tanpa ownership jelas | Tinggi | Tetapkan node contract, schema version, dan capability registry. |
| Realtime terlihat bekerja tetapi gagal pada reconnect | Tinggi | Dua-client test, idempotency key, replay log, dan RLS integration test. |
| AI menjadi fitur demo mahal | Tinggi | Quota, cost ledger, provider gate, explicit apply, dan eval fixture. |
| Import/export menjanjikan fidelity palsu | Sedang | Loss report, mode flattened/reference-only, dan round-trip fixture. |
| Plugin memperluas attack surface | Tinggi | Sandbox, permission scopes, signed manifest, API version, dan limits. |

## Keputusan Produk yang Perlu Dikunci

1. ICP utama berikutnya: creative generalist, UI/UX designer, atau team/agency.
2. Platform prioritas setelah Web/Windows: Android tablet atau iPadOS.
3. Apakah AI cloud wajib opt-in dan apakah local model menjadi target resmi.
4. Batas fidelity import SVG/PDF/PPTX/PSD yang akan dijanjikan.
5. Model bisnis: seat, storage, AI credit, render quota, atau kombinasi.

## North Star Release

Creative Studio matang ketika pengguna dapat membuat ide, mengubahnya menjadi
struktur visual, meminta bantuan AI dengan konteks yang aman, menerima review,
memulihkan versi lama, mempublikasikan hasil, dan membuka project yang sama di
client lain tanpa kehilangan fidelity atau kepercayaan.
