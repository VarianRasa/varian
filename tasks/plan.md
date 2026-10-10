# Rencana Implementasi: Member Management, Role, dan User Tracking

## Overview

Menambahkan lapisan manajemen anggota di atas kolaborasi CRDT yang sudah berjalan:
roster anggota persisten dan online, role serta permission dinamis, kontrol host
terhadap guest, fitur follow viewport, dan screen tracking berbasis WebRTC dengan
persetujuan eksplisit dari pengguna yang membagikan layar.

Implementasi mempertahankan transport CRDT yang sudah ada. Event control-plane
(role, remove, follow, dan signaling) dipisahkan dari operasi canvas agar perubahan
permission tidak bercampur dengan data dokumen.

## Kondisi Saat Ini

- `workspace_members` sudah memiliki role `owner`, `editor`, `commenter`, dan
  `viewer`.
- RPC list/set/remove member sudah tersedia di
  `lib/data/remote/supabase_service.dart`.
- Presence saat ini mengirim cursor, selection, active node, dan status editing.
- Channel Realtime memakai `canvas_room:<projectId>`.
- UI canvas masih banyak mengandalkan `widget.readOnly`, sehingga role guest belum
  dapat berubah tanpa restart atau membuka ulang dokumen.
- Belum ada profil anggota, event management, follow viewport, atau screen-sharing
  transport.

## Architecture Decisions

1. **Role terpusat di backend**
   - `owner`: host penuh; mengatur role, mengeluarkan anggota, mengatur room, dan
     menyetujui atau menghentikan tracking.
   - `editor`: mengubah node, posisi, konektor, dan aset canvas.
   - `commenter`: membaca canvas dan membuat atau mengubah komentar sesuai policy.
   - `viewer`: hanya membaca canvas dan presence.
   - UI permission hanya menjadi feedback; RLS/RPC tetap menjadi enforcement utama.

2. **Roster persisten dan presence realtime dipisahkan**
   - Roster berasal dari `workspace_members` dan profil publik terbatas.
   - Status online, cursor, selection, viewport, dan aktivitas berasal dari Presence.
   - Anggota tetap terlihat di roster walaupun sedang offline.

3. **Control-plane memakai event Realtime khusus**
   - `member_role_changed`
   - `member_removed`
   - `member_profile_updated`
   - `follow_request`, `follow_response`, `follow_state`
   - `screen_share_request`, `screen_share_response`, `screen_share_state`
   - Payload divalidasi, memiliki `projectId`, `actorId`, dan `eventId`, serta tidak
     dipercaya sebagai pengganti pemeriksaan backend.

4. **Follow viewport dan screen tracking adalah dua fitur berbeda**
   - **Follow viewport** hanya menampilkan viewport, zoom, cursor, selection, dan
     active node pengguna lain. Ini ringan dan dapat bekerja melalui Supabase Realtime.
   - **Screen tracking** menampilkan stream layar aktual. Ini memakai WebRTC; frame
     layar tidak dikirim melalui CRDT atau Supabase broadcast.

5. **Screen tracking wajib consent**
   - User yang layarnya dibagikan harus menekan `Allow` melalui dialog sistem/browser.
   - Indikator sharing selalu tampil di sisi sharer dan viewer.
   - Sharer dapat menghentikan stream kapan saja; host juga dapat menghentikannya.
   - Tidak ada silent capture, background capture, atau akses layar tanpa persetujuan.

## Task List

### Phase 1: Contract dan Backend Foundation

#### Task 1: Model role dan permission

**Description:** Tambahkan enum role, permission matrix, model profil/member, dan
model event control-plane tanpa mengubah perilaku canvas lama.

**Acceptance criteria:**
- [ ] Role invalid ditolak sebelum dikirim ke backend.
- [ ] Permission dapat diuji tanpa Flutter binding.
- [ ] `CanvasMember` memuat display name, avatar opsional, role, dan metadata online
      yang dapat diperbarui dari presence.

**Verification:**
- [ ] Unit test untuk seluruh kombinasi role dan permission.
- [ ] Test serialization/deserialization member dan event.

**Dependencies:** None

**Files likely touched:**
- `lib/domain/models/collaboration.dart`
- `lib/data/remote/supabase_service.dart`
- `test/features/collaboration/collaboration_test.dart`

**Estimated scope:** Medium

#### Task 2: Roster profile dan policy backend

**Description:** Tambahkan migration untuk profil publik terbatas, last-seen,
validasi role, RPC management, dan policy yang memastikan hanya owner dapat
mengelola anggota.

**Acceptance criteria:**
- [ ] Host dapat membaca roster lengkap project.
- [ ] Anggota hanya dapat memperbarui profil publik miliknya sendiri.
- [ ] Owner dapat set role atau remove non-owner; owner tidak dapat dihapus atau
      diturunkan melalui client.
- [ ] User yang di-remove tidak dapat membaca atau menulis canvas lagi.
- [ ] Semua RPC baru memiliki `security definer`, `search_path` aman, grant
      `authenticated`, dan tidak dapat dipanggil anon.

**Verification:**
- [ ] Migration tests memeriksa tabel, RPC, grants, dan policy.
- [ ] Uji manual dengan owner, editor, commenter, dan viewer.

**Dependencies:** Task 1

**Files likely touched:**
- `supabase/migrations/<timestamp>_collaboration_members.sql`
- `lib/data/remote/supabase_service.dart`
- `test/supabase/collaboration_members_migration_test.dart`

**Estimated scope:** Large

### Checkpoint: Foundation

- [ ] Model dan migration lulus test.
- [ ] `supabase db push --linked --yes` berhasil pada project Supabase aktif.
- [ ] Roster dapat dibaca lintas Web dan Windows.

### Phase 2: Roster UI dan Dynamic Permissions

#### Task 3: Panel anggota dan kontrol host

**Description:** Tambahkan panel responsive dari header/room dialog yang dapat
dibuka host maupun guest.

**Acceptance criteria:**
- [ ] Host melihat semua anggota, role, status online, cursor-active, dan waktu
      aktivitas terakhir.
- [ ] Guest melihat roster dan role tetapi tidak melihat kontrol host.
- [ ] Host dapat mengubah role, remove guest, menyalin Room ID, rotate/revoke room,
      dan menghentikan tracking.
- [ ] Guest dapat leave room dan mengirim request follow atau screen tracking.
- [ ] Perubahan role/remove muncul realtime di semua client tanpa restart.

**Verification:**
- [ ] Widget test untuk host/guest visibility.
- [ ] Two-client manual test untuk role change dan kick.

**Dependencies:** Tasks 1-2

**Files likely touched:**
- `lib/features/collaboration/presentation/widgets/collaborators_panel.dart`
- `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart`
- `lib/features/collaboration/state/collaboration_session_provider.dart`
- `lib/features/collaboration/data/supabase_collaboration_transport.dart`
- `test/features/collaboration/collaborators_panel_test.dart`

**Estimated scope:** Large

#### Task 4: Enforce permission dinamis di canvas

**Description:** Ganti pemeriksaan `widget.readOnly` yang terkait kolaborasi dengan
permission dari session. `widget.readOnly` tetap dipakai untuk mode dokumen yang
memang read-only di luar room.

**Acceptance criteria:**
- [ ] Editor dapat mengedit canvas dan komentar.
- [ ] Commenter tidak dapat mengubah node tetapi dapat memakai komentar.
- [ ] Viewer tidak dapat mengubah node atau komentar.
- [ ] Perubahan role berlaku saat session aktif dan memblokir aksi berikutnya.
- [ ] Pending operation yang tidak lagi diizinkan tidak dikirim ke backend.

**Verification:**
- [ ] Unit test permission guard pada controller.
- [ ] Widget test tombol toolbar, inspector, AI panel, komentar, dan context menu.
- [ ] Two-client test role transition editor → viewer.

**Dependencies:** Tasks 1-3

**Files likely touched:**
- `lib/features/collaboration/state/collaboration_session_provider.dart`
- `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart`
- `lib/features/collaboration/data/supabase_collaboration_transport.dart`
- `test/features/collaboration/collaboration_permissions_test.dart`

**Estimated scope:** Large

### Phase 3: Follow Viewport dan Screen Tracking

#### Task 5: Follow viewport

**Description:** Perluas payload presence dengan viewport position, zoom, dan
timestamp. Sediakan request/approve/stop sehingga pengguna dapat mengikuti layar
kerja anggota lain tanpa mengambil alih input lokal.

**Acceptance criteria:**
- [ ] Roster menampilkan aksi `Follow` untuk anggota online.
- [ ] Target menerima request dan dapat approve atau reject.
- [ ] Viewer mengikuti viewport, zoom, selection, dan active node secara halus.
- [ ] Viewer dapat berhenti mengikuti kapan saja; target/host dapat menghentikan
      follow.
- [ ] Cursor dan viewport dibatasi rate-limit/debounce agar tidak memicu presence
      flood.

**Verification:**
- [ ] Unit test payload viewport dan state machine request/approve/stop.
- [ ] Two-client test untuk pan, zoom, selection, reconnect, reject, dan stop.

**Dependencies:** Tasks 1-4

**Files likely touched:**
- `lib/domain/models/collaboration.dart`
- `lib/features/collaboration/state/collaboration_session_provider.dart`
- `lib/features/collaboration/data/supabase_collaboration_transport.dart`
- `lib/features/canvas/state/viewport_provider.dart`
- `test/features/collaboration/follow_viewport_test.dart`

**Estimated scope:** Large

#### Task 6: Screen tracking via WebRTC

**Description:** Tambahkan adapter screen capture dan WebRTC signaling untuk Web
dan Windows. Supabase Realtime hanya dipakai sebagai signaling/control channel;
media stream berjalan peer-to-peer melalui ICE server.

**Acceptance criteria:**
- [ ] Sharer dapat meminta/menyetujui screen sharing dan browser/OS menampilkan
      consent prompt.
- [ ] Viewer menerima stream layar aktual dengan indikator nama sharer.
- [ ] Host dapat approve/reject request dan stop share.
- [ ] Sharer dapat stop share; semua peer dibersihkan dan kembali ke status idle.
- [ ] Reconnect, room revoke, member removal, dan dispose menutup peer connection,
      track, timer, dan signaling listener.
- [ ] Jika WebRTC atau TURN belum tersedia, UI menampilkan error yang jelas dan
      follow viewport tetap dapat dipakai.

**Verification:**
- [ ] Unit test signaling state machine dan consent state.
- [ ] Web build dan Windows build lulus.
- [ ] Manual test Windows host ↔ Chrome guest dan Chrome host ↔ Windows guest.
- [ ] Test jaringan berbeda; dokumentasikan kebutuhan STUN/TURN untuk produksi.

**Dependencies:** Tasks 1-5 dan keputusan ICE/TURN.

**Files likely touched:**
- `pubspec.yaml`
- `lib/features/collaboration/screen_tracking/`
- `lib/features/collaboration/data/supabase_collaboration_transport.dart`
- `lib/features/collaboration/presentation/widgets/collaborators_panel.dart`
- `test/features/collaboration/screen_tracking_test.dart`

**Estimated scope:** Extra large; wajib dipecah menjadi adapter, signaling, dan UI
sebelum implementasi.

### Phase 4: Verification dan Hardening

#### Task 7: Cross-platform validation dan observability

**Description:** Tambahkan logging terstruktur untuk event membership/tracking,
perbaiki error state, dan verifikasi build serta alur dua client.

**Acceptance criteria:**
- [ ] Tidak ada status online palsu setelah channel closed atau member removed.
- [ ] Error Realtime, RLS, permission, dan WebRTC memiliki pesan user-facing.
- [ ] Roster, role, follow, screen tracking, room revoke, dan reconnect memiliki
      test coverage yang relevan.
- [ ] Tidak ada service-role key atau secret TURN di client.

**Verification:**
- [ ] `dart format` pada file yang diubah.
- [ ] `flutter analyze --no-pub` lulus.
- [ ] `flutter test --no-pub` lulus.
- [ ] `flutter build web --no-pub` lulus.
- [ ] `flutter build windows --no-pub` lulus.

**Dependencies:** Tasks 1-6

**Files likely touched:**
- `test/features/collaboration/`
- `test/supabase/`
- `README.md`
- `lib/features/collaboration/`

**Estimated scope:** Medium

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| UI masih memakai `widget.readOnly` di banyak jalur | High | Buat satu permission guard di session, lalu migrasikan call site bertahap dan uji setiap role. |
| Presence flood menyebabkan `Client presence rate limit exceeded` | High | Bedakan `track` roster dari broadcast cursor, debounce viewport/cursor, dan jangan kirim payload identik. |
| RLS menolak operasi setelah role berubah | High | Validasi role sebelum enqueue, flush hanya saat permission masih valid, dan tampilkan error khusus permission. |
| Screen capture tidak seragam di Web dan Windows | High | Adapter platform-specific, capability check, fallback ke follow viewport, dan manual matrix dua arah. |
| WebRTC gagal di jaringan NAT/restrictive | High | Konfigurasi STUN/TURN melalui backend config tanpa secret service-role; tampilkan status ICE dan fallback. |
| User di-remove masih punya channel terbuka | Medium | Broadcast `member_removed`, stop session lokal, unsubscribe channel, dan backend tetap memblokir akses baru. |
| Profil auth tidak boleh dibaca langsung dari `auth.users` | Medium | Simpan display name/avatar terbatas di tabel profil publik dengan RLS self-write/member-read. |

## Open Questions

- Apakah host boleh mengubah role menjadi `commenter`/`viewer` saja, atau perlu
  role tambahan seperti `co-host`?
- Apakah screen tracking hanya boleh dimulai host, atau guest boleh meminta host
  dan guest lain untuk share dengan approval target?
- Apakah perlu menyimpan histori siapa yang pernah online, atau cukup `last_seen`
  untuk roster saat ini?
- Apakah environment Supabase sudah memiliki STUN/TURN endpoint yang dapat dipakai
  client Web dan Windows?

## Definition of Done

Fitur dianggap selesai setelah owner dan guest dapat membuka panel anggota,
melihat roster online/offline, menjalankan role management sesuai permission,
melakukan follow viewport dengan consent, dan menggunakan screen tracking dengan
consent di Windows ↔ Web tanpa kehilangan sinkronisasi canvas. Migration sudah
terdeploy ke Supabase, seluruh test/build gate lulus, dan fallback error sudah
jelas ketika WebRTC tidak tersedia.
