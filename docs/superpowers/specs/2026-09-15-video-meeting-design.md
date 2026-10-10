# Design Spec: Video Meeting untuk Windows dan Web

**Status:** Disetujui untuk perencanaan pada 15 September 2026  
**Target MVP:** Flutter Web dan Windows  
**Media provider:** LiveKit melalui adapter aplikasi  
**Control plane:** Supabase Auth, PostgreSQL, Edge Function, dan Realtime

## 1. Tujuan

Varian membutuhkan video meeting terintegrasi dengan project canvas agar host dan collaborator dapat berdiskusi tanpa meninggalkan workspace. MVP menyediakan kamera, mikrofon, screen sharing, roster peserta, kontrol lokal, kontrol host, dan pemulihan koneksi untuk Chrome/Web dan Windows.

Fitur ini bukan pengganti sinkronisasi canvas. Meeting hanya menggunakan identitas, membership, dan permission dari collaboration room; CRDT, cursor, comments, follow viewport, dan screen tracking canvas tetap memiliki lifecycle masing-masing.

## 2. Kondisi Awal Repo

- `pubspec.yaml` sudah memiliki `flutter_webrtc`, tetapi belum memiliki adapter meeting multi-peserta.
- `lib/features/collaboration/data/screen_tracking_service.dart:52` mengelola WebRTC langsung untuk screen tracking satu-ke-satu.
- `lib/features/collaboration/state/collaboration_session_provider.dart:249` memiliki lifecycle screen tracking dan control event collaboration.
- `lib/features/collaboration/data/supabase_collaboration_transport.dart` sudah menangani channel Realtime, reconnect, presence, dan broadcast control event.
- `lib/domain/models/collaboration.dart:102` mendefinisikan role `owner`, `editor`, `commenter`, dan `viewer`.
- `lib/main.dart:98` menggunakan `GoRouter`; route meeting baru harus ditambahkan tanpa mengubah route share publik.
- Supabase memakai `project_role(project_id)` sebagai pemeriksaan membership server-side.

## 3. Ruang Lingkup MVP

### Termasuk

- Host membuat satu meeting aktif untuk satu project.
- Anggota collaboration room bergabung melalui pre-join screen.
- Preview kamera dan pemeriksaan mikrofon sebelum bergabung.
- Publish dan subscribe audio/video multi-peserta melalui SFU.
- Toggle mikrofon dan kamera untuk diri sendiri.
- Screen sharing satu sumber aktif per peserta.
- Layout grid peserta dengan tile aktif dan indikator status.
- Roster peserta dan status media.
- Host mengakhiri meeting untuk semua peserta.
- Host mengeluarkan peserta dari meeting.
- Reconnect media, token refresh, leave, dan cleanup saat route ditutup.
- Pesan error user-facing untuk permission, device, token, room, dan network failure.
- Feature flag agar fitur dapat dirilis bertahap.

### Tidak termasuk MVP

- Recording dan playback rekaman.
- Breakout rooms.
- Live captions atau transcription.
- Virtual background.
- Webinar mode.
- Chat meeting terpisah dari comments/canvas.
- System audio sharing lintas platform.
- Moderator force-mute yang menjamin perangkat peserta benar-benar mute.
- Android, iOS, macOS, dan Linux.

## 4. Keputusan Arsitektur

### 4.1 SFU untuk media

Media meeting memakai SFU melalui LiveKit. P2P mesh tidak digunakan untuk meeting grup karena setiap peserta akan mengunggah stream ke banyak peer dan kualitas turun seiring jumlah peserta.

LiveKit dipanggil melalui `MeetingMediaPort`, sehingga controller dan UI tidak bergantung langsung pada object atau event LiveKit. Deployment MVP menggunakan LiveKit Cloud; konfigurasi server tetap memungkinkan perpindahan ke LiveKit self-hosted tanpa mengubah domain model.

### 4.2 Supabase sebagai control plane

Supabase menyimpan session meeting dan memvalidasi membership. Supabase Realtime hanya mengirim event lifecycle aplikasi seperti meeting ended atau participant removed. Audio, video, screen share, dan media reconnect ditangani oleh LiveKit.

### 4.3 Token selalu dibuat server-side

Flutter hanya menerima URL server dan short-lived access token. LiveKit API key, API secret, Supabase service-role key, dan credential TURN tidak pernah dimasukkan ke `pubspec`, `dart-define` publik, asset, atau client bundle.

Edge Function `meeting-token` memeriksa Bearer token Supabase, membership project, status meeting, role, dan kapasitas sebelum menerbitkan token.

### 4.4 State meeting terpisah dari state canvas

Jangan menambah seluruh state media ke `CollaborationSessionState`. `MeetingController` memiliki state sendiri yang di-scope berdasarkan `projectId` dan menyimpan `meetingId` aktif setelah session dibuat. Controller hanya menerima project membership dan event lifecycle yang diperlukan.

### 4.5 Permission meeting

- `owner`: membuat meeting, mengakhiri meeting, dan mengeluarkan peserta.
- `editor` dan `commenter`: bergabung, publish kamera/mikrofon, dan screen share.
- `viewer`: bergabung dan subscribe media; publish media dinonaktifkan pada token.
- Semua peserta hanya dapat mengubah mute/kamera miliknya sendiri.
- Mengeluarkan peserta mencabut akses token baru dan memerintahkan client aktif untuk leave.

## 5. Alur Pengguna

### 5.1 Host memulai meeting

1. Host menekan `Start Video Meeting` pada header collaboration/canvas.
2. Aplikasi memanggil `create_meeting_session(projectId, 8)`.
3. Backend membuat session `active` dengan `provider_room_name` acak yang tidak berasal dari nama project.
4. Aplikasi membuka route `/meeting/:meetingId`.

Jika session aktif sudah ada, host diarahkan ke session tersebut. Session kedua tidak dibuat untuk project yang sama.

### 5.2 Peserta bergabung

1. Anggota membuka meeting dari collaboration panel atau meeting indicator.
2. Pre-join screen meminta permission kamera/mikrofon dan menampilkan preview lokal.
3. Setelah menekan `Join`, aplikasi memanggil `join_meeting_session(meetingId)` lalu Edge Function `meeting-token`.
4. `MeetingMediaPort.connect()` bergabung ke provider room.
5. UI berpindah ke meeting stage setelah state media `connected` atau menampilkan retry jika gagal.

### 5.3 Saat meeting berlangsung

- Tile lokal dan remote menampilkan nama, avatar/fallback initials, mute state, dan video state.
- Layout memilih grid untuk beberapa peserta dan tile aktif/pinned untuk peserta yang dipilih.
- Toolbar menyediakan microphone, camera, screen share, participant list, dan leave.
- Host melihat kontrol `End for everyone` dan `Remove participant`.
- Leave biasa hanya memutus client lokal; end meeting mengubah status durable menjadi `ended`.

### 5.4 Reconnect dan termination

- Gangguan sementara menampilkan `Reconnecting` dan mempertahankan UI canvas.
- Token expired meminta token baru melalui Edge Function, bukan menggunakan secret di client.
- Meeting `ended`, room expired, atau participant removed memicu disconnect, cleanup track, dan route kembali ke canvas.
- Dispose selalu menghentikan local tracks, unsubscribe event, dan menutup provider room.

## 6. Arsitektur Teknis

```text
CanvasEditorSurface
        |
        v
Meeting entry / GoRouter / MeetingScreen
        |
        v
MeetingController  <---->  MeetingRepository
        |                          |
        v                          v
MeetingMediaPort              Supabase Auth/RPC/Edge Function
        |
        v
LiveKitAdapter  ------------>  LiveKit SFU

Existing CollaborationSessionController
        |
        +-- project membership, role, room lifecycle, canvas CRDT
        +-- existing one-to-one ScreenTrackingService
```

### 6.1 Data model durable

Migration baru membuat `public.meeting_sessions` dengan kolom:

| Kolom | Aturan |
| --- | --- |
| `id` | UUID primary key |
| `project_id` | `text`, foreign key ke `projects(id)` |
| `created_by` | UUID auth user pembuat |
| `provider` | `livekit` pada MVP |
| `provider_room_name` | Unique, acak, bukan secret |
| `status` | `active` atau `ended` |
| `max_participants` | Default 8, valid antara 2 dan 8 |
| `created_at` | `timestamptz` |
| `ended_at` | Nullable `timestamptz` |
| `ended_reason` | Nullable reason terkontrol |

Tidak ada tabel participant durable pada MVP. Roster realtime berasal dari provider; tabel terpisah baru dibuat jika audit attendance menjadi kebutuhan produk.

### 6.2 RPC contract

- `create_meeting_session(p_project_id text, p_max_participants integer default 8) returns jsonb`
  - Hanya project owner.
  - Menolak nilai kapasitas di luar 2..8.
  - Menolak session `active` kedua pada project yang sama.
- `join_meeting_session(p_meeting_id uuid) returns jsonb`
  - Membutuhkan `auth.uid()` dan `project_role(project_id)` tidak null.
  - Menolak session yang sudah `ended`.
- `end_meeting_session(p_meeting_id uuid, p_reason text default 'host_ended') returns jsonb`
  - Hanya owner atau creator yang masih authorized.
  - Mengisi `ended_at` dan mempertahankan operasi idempotent.

Direct table insert/update/delete dicabut dari role client; operasi memakai RPC dengan `security definer`, `set search_path = public`, dan pemeriksaan authorization eksplisit.

### 6.3 Edge Function contract

Request:

```json
{
  "meetingId": "uuid"
}
```

Response sukses:

```json
{
  "token": "short-lived-provider-token",
  "serverUrl": "configured-provider-url",
  "expiresAt": "ISO-8601 timestamp",
  "identity": "authenticated-user-id"
}
```

Function `meeting-token` harus:

1. Menerima hanya `POST` dan `OPTIONS`.
2. Memvalidasi origin terhadap `ALLOWED_ORIGINS`.
3. Membaca Bearer token dan memanggil Supabase Auth untuk mendapatkan user.
4. Memastikan meeting aktif dan user adalah project member.
5. Mengambil role project dan menerapkan grant publish/subscribe.
6. Memeriksa kapasitas provider sebelum membuat token.
7. Mengembalikan error JSON terstruktur tanpa membocorkan credential atau provider secret.

Environment secret function:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `ALLOWED_ORIGINS`

### 6.4 Media port

Domain tidak mengonsumsi SDP atau ICE secara langsung. Adapter menyembunyikan object provider dan menerjemahkan event menjadi model aplikasi:

```dart
abstract interface class MeetingMediaPort {
  Stream<MeetingMediaEvent> get events;

  Future<void> connect({
    required String serverUrl,
    required String token,
  });

  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> setScreenShareEnabled(bool enabled);
  Future<void> disconnect();
  Future<void> dispose();
}
```

`MeetingMediaEvent` mencakup perubahan connection state, local media state, remote participant joined/left, remote track subscribed/unsubscribed, active speaker, provider error, dan token refresh request.

## 7. Platform Requirements

### Web

- Permission kamera/mikrofon memakai browser permission prompt.
- UI menampilkan instruksi jika permission diblokir dan menyediakan retry.
- Screen share memakai browser display picker; system audio tidak dijanjikan pada MVP.
- Route dan refresh tidak boleh meninggalkan credential provider di URL.

### Windows

- Kamera/mikrofon menggunakan device default dan dapat di-toggle sebelum publish.
- Screen share memakai desktop capture adapter yang dipisahkan dari canvas screen tracking.
- Close window, route leave, dan app lifecycle harus menghentikan tracks sebelum room disconnect.
- Manual test wajib mencakup Windows host ke Chrome guest dan Chrome host ke Windows guest.

## 8. Error dan Recovery Contract

| Kondisi | State | Pesan user-facing |
| --- | --- | --- |
| Supabase belum dikonfigurasi | `unavailable` | `Video meeting belum tersedia karena backend belum dikonfigurasi.` |
| Kamera ditolak | `permissionDenied` | `Akses kamera ditolak. Izinkan kamera lalu coba lagi.` |
| Mikrofon ditolak | `permissionDenied` | `Akses mikrofon ditolak. Meeting tetap dapat dibuka tanpa mikrofon.` |
| Token gagal dibuat | `authorizationError` | `Tidak dapat mengakses meeting ini.` |
| Meeting sudah berakhir | `ended` | `Meeting sudah diakhiri oleh host.` |
| Dikeluarkan host | `removed` | `Anda dikeluarkan dari meeting.` |
| Network reconnect | `reconnecting` | `Koneksi meeting terputus. Mencoba menghubungkan kembali.` |
| Provider room gagal | `providerError` | `Layanan video sedang tidak tersedia. Coba lagi.` |

Pesan internal provider hanya masuk ke log terstruktur dan tidak ditampilkan mentah kepada pengguna.

## 9. Security dan Privacy

- Semua RPC memerlukan `auth.uid()` dan membership server-side.
- Token provider short-lived dan dibatasi ke satu room serta satu identity.
- Viewer menerima `canSubscribe` tanpa `canPublish`.
- API secret, service-role key, dan TURN credential hanya berada pada Edge Function atau provider configuration.
- Meeting ID bukan bearer credential; route tetap memanggil backend untuk authorization.
- Tidak menyimpan frame, rekaman, atau audio pada storage selama MVP.
- Log tidak boleh menyimpan token, SDP, ICE candidate, atau URL credential.
- Revoke/remove/end harus idempotent dan aman terhadap reconnect race.

## 10. Testing Strategy

### Unit

- Model session, role grant, state transition, error mapping, dan token response parsing.
- Repository request/response dengan fake Supabase client boundary.
- Media port dengan fake provider untuk connect, toggle, participant events, reconnect, dan dispose.

### Widget

- Pre-join permission state.
- Participant tile untuk local, remote, muted, camera-off, screen-share, dan error.
- Meeting toolbar toggle dan leave confirmation.
- Host control hanya muncul untuk owner.

### Integration/manual

- Windows host ↔ Chrome guest.
- Chrome host ↔ Windows guest.
- Dua peserta publish audio/video.
- Tiga sampai delapan peserta pada room yang sama.
- Screen share dari Windows dan Web.
- Camera/microphone permission denied lalu retry.
- Refresh/reconnect saat meeting aktif.
- Host end, participant remove, room revoke, dan session expiry.

### Repository gates

- `dart format` pada file yang diubah.
- `flutter analyze --no-pub`.
- `flutter test --no-pub`.
- `flutter build web --no-pub`.
- `flutter build windows --no-pub`.
- Supabase migration test dan Edge Function contract test.

## 11. Acceptance Criteria

- Host dapat membuat satu meeting aktif dari project.
- Anggota authorized dapat join dari Web atau Windows setelah pre-join.
- Audio, camera video, dan screen share dapat dipublish/subscribe multi-peserta melalui SFU.
- Viewer tidak dapat publish media.
- Mute/unmute dan camera on/off tidak memutus room.
- Host dapat mengakhiri meeting dan mengeluarkan participant.
- Client menangani reconnect, token refresh, room ended, remove, leave, dan dispose.
- Tidak ada provider secret atau service-role key di client bundle.
- Test dan build gates repository lulus.
- Fitur dapat dimatikan melalui feature flag tanpa merusak collaboration/canvas.

## 12. Rollout

1. Rilis adapter dan backend dengan feature flag off.
2. Aktifkan untuk internal project dengan kapasitas maksimal 8 peserta.
3. Jalankan manual matrix Windows/Web dan monitor error rate, join latency, reconnect, serta permission failure.
4. Aktifkan bertahap setelah tidak ada kebocoran credential dan semua lifecycle termination terverifikasi.

## 13. Open Decisions Sebelum Production

- LiveKit Cloud tetap dipakai atau dipindahkan ke self-hosted setelah spike biaya dan data residency.
- Apakah attendance perlu disimpan pada tabel participant pada fase berikutnya.
- Apakah commenter tetap boleh screen share atau dibatasi ke owner/editor.
- Apakah meeting harus tetap aktif ketika collaboration room dicabut, atau langsung diakhiri.
