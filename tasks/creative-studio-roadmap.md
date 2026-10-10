# Roadmap Creative Studio Canvas

## Tujuan

Menjadikan Varian sebagai creative studio berbasis infinite canvas yang solid
untuk pekerjaan visual, diagram, dokumen, prototyping, AI-assisted creation,
dan kolaborasi. Fokus roadmap ini bukan menambah node sebanyak mungkin, tetapi
membuat seluruh alur terasa konsisten, aman, cepat, dapat dipulihkan, dan siap
dipakai untuk proyek besar.

## Baseline Saat Ini

Fondasi yang sudah tersedia di repository:

- Infinite canvas dengan node dan edge, selection marquee, snapping, alignment,
  distribution, grouping, frames, auto-layout, z-order, minimap, layers, dan
  inspector.
- Model konten yang luas: rich text/Markdown, sticky note, image, vector path,
  drawing paper/raster, document/PDF, table/formula, todo list, kanban column,
  chart, Mermaid/diagram, link/embed, map, audio/video, GLB 3D, nested board,
  component/variant, sketch card, dan annotation pin.
- Command history, copy/cut/paste, duplication, autosave lokal, cloud sync,
  snapshot recovery, serta CRDT untuk kolaborasi.
- AI contract untuk image, editing, enhancement, video, 3D, diagram, dan
  assistant workflows; image-to-3D TripoSR sudah memiliki jalur worker sampai
  import GLB.
- Collaboration room dengan role, presence, cursor, comments, follow viewport,
  screen tracking, dan Supabase RLS/RPC.
- Export/import untuk JSON, SVG, PNG, PDF, Markdown/plain text, Mermaid, dan
  draw.io, termasuk PSD export untuk drawing paper.
- Presentation mode, templates diagram, asset library dasar, search, serta
  desktop document tabs.

## Diagnosis Produk

Varian sudah lebih dekat ke creative workstation daripada whiteboard biasa.
Risiko terbesar saat ini adalah breadth fitur tumbuh lebih cepat daripada
contract inti dokumen, persistence, performance, dan verification lintas
platform. Karena itu urutan kerja harus:

1. stabilkan core editor dan data;
2. jadikan project besar dan kolaborasi dapat diandalkan;
3. satukan design system, asset, template, dan AI menjadi workflow;
4. baru perluas ecosystem, publishing, dan monetisasi.

## Prioritas Produk

### P0 — Solid Core

Fitur-fitur ini wajib sebelum menambah banyak surface baru.

#### 1. Document package dan migration system

Tambahkan format dokumen resmi yang memiliki `schemaVersion`, manifest asset,
font/resource references, metadata proyek, dan migration registry. Pisahkan
document JSON, binary artifact, thumbnail, dan preview cache. Sediakan import
validator, migration report, rollback, dan export package portable.

Alasan: `CanvasDocument` saat ini sudah memiliki `schemaVersion`, tetapi payload
masih berkembang luas dan local storage memiliki batas ukuran/degraded save.
Creative project besar perlu format yang bisa dipindahkan, diverifikasi, dan
dipulihkan tanpa kehilangan asset.

Acceptance criteria:

- Dokumen lama dapat dibuka melalui migrasi deterministik tanpa mengubah
  semantic node/edge.
- Package berisi manifest dengan checksum, ukuran, MIME, dan status asset.
- Dokumen dengan asset hilang menampilkan placeholder dan recovery action,
  bukan crash atau node kosong.
- Export/import package round-trip lulus pada Web dan Windows.

#### 2. Transactional command bus

Satukan seluruh mutasi canvas ke command bus dengan transaction boundary,
coalescing untuk drag/typing, command label, permission check, dan event audit.
Undo/redo harus mencakup nodes, edges, text, drawing strokes, raster operation,
comments, dan perubahan struktur frame/group.

Acceptance criteria:

- Satu gesture drag/resize/typing menjadi satu history entry.
- Undo/redo tidak meninggalkan edge yatim, parentId salah, atau auto-layout
  state yang tidak sinkron.
- Read-only/commenter tidak dapat memasukkan command mutasi meski shortcut,
  context menu, atau event realtime dipicu langsung.
- Command dapat direplay untuk debugging dan recovery.

#### 3. Crash recovery, offline queue, dan conflict UX

Naikkan autosave menjadi offline-first: journal operasi lokal, retry dengan
backoff, status per project, pause/resume sync, conflict detection, dan layar
recovery. Bedakan `saved locally`, `syncing`, `synced`, `conflicted`, dan
`failed` secara user-facing.

Acceptance criteria:

- Force close saat write/sync tidak merusak dokumen terakhir yang valid.
- Offline edit dapat dilanjutkan dan dikirim ulang tanpa duplicate operation.
- Konflik snapshot/CRDT memiliki pilihan keep local, keep remote, atau merge
  dengan preview per node/field.
- User dapat mengunduh backup lokal sebelum memilih resolusi konflik.

#### 4. Canvas performance foundation

Tambahkan spatial index untuk hit-test/visible nodes, render culling,
progressive media loading, thumbnail cache, repaint boundary strategy, dan
profiling overlay. Tetapkan performance budget untuk jumlah node, zoom, image,
video, raster stroke, dan GLB.

Acceptance criteria:

- Canvas tetap interaktif pada dokumen benchmark besar yang disimpan di
  `tool/benchmarks`.
- Node di luar viewport tidak melakukan full render atau media playback.
- Pan/zoom, selection, dan drag memiliki target frame-time yang terdokumentasi.
- Memory dan texture cleanup diuji setelah membuka/menutup banyak project.

#### 5. Input, selection, dan transform parity

Lengkapi editor dengan transform model yang konsisten: multi-select bounds,
rotate, resize from center, aspect lock, snap-to-keyline, keyboard nudge,
scale-with-children, group/frame coordinate conversion, lock/visibility
semantics, and edge preservation.

Acceptance criteria:

- Transform multi-select menghasilkan posisi, ukuran, rotation, dan edge yang
  konsisten setelah reload.
- Frame/group nesting tidak menggeser child secara tak terduga.
- Mouse, trackpad, stylus, touch, dan keyboard memiliki behavior yang
  terdokumentasi di Web, Windows, dan Android.
- Shortcut map dapat dibuka dari aplikasi dan tidak mengganggu text input.

### P1 — Workflow yang Membuat Produk Berbeda

#### 6. Design system dan reusable library

Jadikan component/variant, color swatch, typography, shadow, dan frame preset
sebagai library yang dapat dipakai lintas project. Tambahkan variables/tokens,
style binding, shared component, override rules, detach/reset instance, dan
asset licensing metadata.

Acceptance criteria:

- User dapat membuat library brand: color, typography, spacing, radius, shadow,
  icon, component, dan template.
- Perubahan master dapat dipreview dan diterapkan ke instance dengan safe
  override handling.
- Library dapat diexport/import dan memiliki version/publish state.
- Inspector menampilkan source library dan alasan ketika override tidak dapat
  diterapkan.

#### 7. Project templates dan starter workflows

Perluas template dari diagram menjadi starter project: moodboard, UI flow,
brand board, social media kit, storyboard, comic/manga page, pitch deck,
research board, lesson plan, product spec, dan 3D presentation board.

Tambahkan template variables, sample assets, guided onboarding, template
preview, duplicate, favorite, dan organization/team template.

Acceptance criteria:

- New project dapat dibuat dari template tanpa ID collision atau asset path
  bocor.
- Template dapat menyatakan required fonts, asset licenses, dan supported
  export targets.
- User dapat menyimpan selection/frame sebagai personal template.

#### 8. Asset library yang benar-benar production-ready

Kembangkan asset library menjadi asset manager: folder/tag/search, duplicate
detector, version, favorite, usage count, remote/local status, thumbnail
generation, drag/drop, replace source, relink missing asset, dan license/
provenance record.

Tambahkan import pipeline untuk SVG, image sequence, PDF pages, audio/video,
GLB textures, serta format yang aman untuk roadmap seperti PSD/AI melalui
converter atau documented limitation.

Acceptance criteria:

- Satu asset yang dipakai banyak node disimpan sekali dan direferensikan lewat
  asset ID.
- Replace/relink mempertahankan transform dan node semantics.
- Asset besar di-stream/thumbnail terlebih dahulu dan tidak membuat document
  JSON melewati limit.
- Export package dapat membawa atau mengecualikan asset dengan laporan jelas.

#### 9. AI Creative Pipeline

Ubah AI dari kumpulan provider menjadi workflow terkontrol:

- capability matrix yang membedakan implemented, configured, unavailable, dan
  experimental;
- prompt history, seed, model/provider, cost estimate, queue, retry, cancel,
  result variants, compare, favorite, dan reuse prompt;
- selection-aware image editing dengan mask/brush, inpaint, outpaint,
  background/object operations;
- AI arrange, summarize, rename, layout, diagram, and document extraction;
- provenance untuk prompt, source node/asset, model, license, timestamp, dan
  output artifact;
- safe provider routing tanpa menyimpan secret di canvas atau log.

Acceptance criteria:

- Setiap job memiliki lifecycle yang dapat dipulihkan setelah restart.
- Output selalu masuk sebagai artifact/node baru atau explicit replacement,
  tidak diam-diam mengubah source.
- User dapat membandingkan minimal dua hasil dan mengembalikan versi sebelumnya.
- UI tidak menampilkan capability sebagai tersedia jika provider/configuration
  belum memenuhi syarat.
- AI action dapat diulang dengan input yang sama dan metadata yang sama ketika
  provider mendukung determinism.

#### 10. Presentation, storyboard, dan motion timeline

Naikkan presentation mode menjadi output workflow: frame order, hotspot/link,
transition, speaker notes, presenter view, remote control, laser/pointer,
storyboard shot list, duration, camera framing, and export to PDF/video.

Untuk motion, gunakan timeline sebagai layer terpisah dari static canvas agar
animasi tidak merusak document semantics.

Acceptance criteria:

- User dapat mengatur urutan frame dan hotspot tanpa mengubah posisi canvas.
- Presenter view memisahkan notes dan control dari audience view.
- Playback dapat di-seek dan hasil export deterministik.
- Frame yang dihapus atau di-rename memperbarui link/hotspot dengan warning.

#### 11. Collaboration yang siap dipakai tim

Tutup verification gap yang sudah tercatat di roadmap kolaborasi saat ini:
Windows ↔ Chrome, role transition, kick/revoke, follow consent, screen
tracking, reconnect, dan failure states. Setelah itu tambahkan:

- share link dengan permission expiry;
- guest invite, workspace/team membership, dan audit log;
- comment filters, mentions, attachments, due date, resolve history;
- follow mode yang tidak mengambil alih input tanpa consent;
- presence privacy dan bandwidth throttling;
- conflict inspector untuk operasi yang bertabrakan.

Acceptance criteria:

- Semua role ditegakkan di UI, controller, transport, RLS, dan storage.
- Reconnect tidak menggandakan node, comments, strokes, atau presence.
- Offline participant mendapat state yang jelas dan dapat resync tanpa reload.
- Owner dapat revoke session dan semua client kehilangan akses secara terukur.

### P2 — Platform dan Ecosystem

#### 12. Publish, share, embed, dan review mode

Tambahkan public read-only link, password/expiry, embed mode, reviewer
annotations, approval state, version compare, watermark, download policy, dan
access analytics. Pisahkan project editor dari published snapshot supaya link
publik tidak berubah tanpa publish action.

#### 13. Plugin/automation SDK

Definisikan API aman untuk membaca selection, membuat node, menambah export
preset, menjalankan command, dan berlangganan event. Mulai dengan local plugin
manifest dan permission scopes sebelum marketplace.

Contoh plugin awal: icon importer, token sync, CSV-to-table, screenshot-to-frame,
accessibility audit, batch rename, and design lint.

#### 14. Accessibility dan input professional

Tambahkan semantic labels, keyboard-only flow, focus order, high contrast,
reduced motion, zoom text, screen reader description, remappable shortcuts,
pen pressure/tilt, palm rejection, ruler/guide, and color-blind-safe palettes.

#### 15. Workspace, governance, dan commercial readiness

Tambahkan workspace/team, project permission inheritance, storage quota, AI
quota/cost visibility, admin audit, retention/deletion/export, billing hooks,
license compliance dashboard, and support diagnostics. Jangan menambah billing
sebelum usage meter dan artifact provenance dapat dipercaya.

## Urutan Implementasi yang Disarankan

1. **Milestone A — Core contract:** package format, migration registry, asset
   manifest, command transaction, serialization fuzz tests.
2. **Milestone B — Reliable editing:** crash recovery, offline queue, conflict
   UX, transform parity, shortcut map, benchmark harness.
3. **Milestone C — Scale and collaboration:** spatial index, culling, media
   cache, cross-client verification, reconnect, permission audit.
4. **Milestone D — Design workflow:** variables/tokens, library, components,
   templates, asset manager.
5. **Milestone E — AI workflow:** capability matrix, job history, mask editor,
   variants/compare, provenance, provider health and cost UX.
6. **Milestone F — Presentation:** storyboard, motion timeline, presenter view,
   deterministic export.
7. **Milestone G — Distribution:** publish/share/embed, plugin SDK, workspace
   governance, accessibility audit, packaging/update channel.

## Definition of Done Produk

- Project dengan ribuan node dan asset besar tetap dapat dibuka, diedit, dan
  diexport tanpa kehilangan data.
- Close/restart/offline/reconnect/conflict memiliki recovery path yang jelas.
- Semua mutasi dapat di-undo/redo dan dapat direplay pada test harness.
- Collaboration lintas Web dan Windows lulus role, reconnect, comment, cursor,
  follow, dan revoke scenarios.
- AI result memiliki provenance, retry/cancel, comparison, dan artifact
  lifecycle yang konsisten.
- Template, library, asset, presentation, dan export memakai document contract
  yang sama.
- Flutter analyze, focused tests, full tests, Web build, Windows build, dan
  benchmark smoke suite menjadi release gates.

## Non-Goals Jangka Pendek

- Jangan menambah puluhan node baru sebelum node lifecycle, asset manifest, dan
  migration stabil.
- Jangan mengaktifkan provider AI eksperimental hanya karena enum capability
  sudah tersedia.
- Jangan membuat marketplace/plugin runtime sebelum permission model dan
  sandbox boundary ada.
- Jangan menjadikan `SharedPreferences` sebagai database utama untuk project
  besar; gunakan storage yang mendukung transactional blob/index bila kebutuhan
  skala meningkat.

