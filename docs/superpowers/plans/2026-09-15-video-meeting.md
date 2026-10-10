# Video Meeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menambahkan video meeting multi-peserta untuk Flutter Web dan Windows dengan LiveKit sebagai media SFU dan Supabase sebagai authorization/control plane.

**Architecture:** Meeting memiliki controller, repository, domain model, dan media adapter terpisah dari `CollaborationSessionController`. Supabase membuat session serta short-lived token; LiveKit menangani audio, video, screen share, participant events, dan media reconnect.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase Auth/PostgreSQL/Edge Functions/Realtime, `livekit_client`, LiveKit Cloud untuk MVP, Web dan Windows.

**Spec:** `docs/superpowers/specs/2026-09-15-video-meeting-design.md`

## Global Constraints

- Target platform MVP hanya Flutter Web dan Windows.
- Media meeting memakai SFU melalui LiveKit; jangan membuat P2P mesh untuk group call.
- Supabase menjadi sumber authorization dan lifecycle; LiveKit menjadi media plane.
- `ScreenTrackingService` tetap satu-ke-satu; meeting memakai `MeetingMediaPort` terpisah.
- API secret, service-role key, TURN credential, token provider, SDP, dan ICE candidate tidak boleh masuk client bundle atau log user-facing.
- Kapasitas awal meeting adalah 8 peserta dan validasi server harus menolak nilai di luar 2..8.
- Viewer dapat subscribe tetapi tidak dapat publish media.
- Feature flag video meeting default `false` sampai manual Windows/Web matrix lulus.
- Jangan mengubah CRDT, comments, cursor, atau route share publik untuk kebutuhan meeting.
- Jangan menjalankan `git commit`; commit hanya dilakukan jika diminta pengguna.

---

## File Map

**Domain dan state**

- Create: `lib/features/meeting/domain/meeting_models.dart` — status, session, participant, track, media event, dan state.
- Create: `lib/features/meeting/domain/meeting_errors.dart` — error codes dan user-facing message mapping.
- Create: `lib/features/meeting/state/meeting_controller.dart` — lifecycle dan command meeting per `meetingId`.

**Data dan backend**

- Create: `lib/features/meeting/data/meeting_configuration.dart` — feature flag, provider URL, dan batas client-safe.
- Create: `lib/features/meeting/data/meeting_repository.dart` — RPC, Edge Function token, dan session stream.
- Create: `lib/features/meeting/data/meeting_media_port.dart` — adapter contract.
- Create: `lib/features/meeting/data/livekit_meeting_media.dart` — implementasi LiveKit.
- Create: `supabase/migrations/20260915070000_create_meeting_sessions.sql` — table, index, RLS, dan RPC.
- Create: `supabase/functions/meeting-token/index.ts` — authenticated token gateway.

**Presentation dan routing**

- Create: `lib/features/meeting/presentation/pre_join_screen.dart` — pre-join permission and preview.
- Create: `lib/features/meeting/presentation/meeting_screen.dart` — stage, lifecycle, dan layout responsive.
- Create: `lib/features/meeting/presentation/widgets/participant_tile.dart` — local/remote tile.
- Create: `lib/features/meeting/presentation/widgets/meeting_toolbar.dart` — media and leave controls.
- Create: `lib/features/meeting/presentation/widgets/meeting_participants_panel.dart` — roster and host actions.
- Modify: `lib/main.dart:98-121` — route `/meeting/:meetingId` dan auth redirect.
- Modify: `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart:2989-2999` — entry point meeting.

**Tests dan documentation**

- Create: `test/features/meeting/meeting_configuration_test.dart`.
- Create: `test/features/meeting/meeting_models_test.dart`.
- Create: `test/features/meeting/meeting_repository_test.dart`.
- Create: `test/features/meeting/meeting_media_port_test.dart`.
- Create: `test/features/meeting/meeting_controller_test.dart`.
- Create: `test/features/meeting/meeting_widgets_test.dart`.
- Create: `test/supabase/video_meeting_migration_test.dart`.
- Create: `supabase/functions/meeting-token/index_test.ts`.
- Modify: `README.md` — provider secrets, deploy, feature flag, dan manual test matrix.

## Task 1: Provider Spike dan Client Configuration

**Files:**
- Modify: `pubspec.yaml:28-93`
- Create: `lib/features/meeting/data/meeting_configuration.dart`
- Create: `test/features/meeting/meeting_configuration_test.dart`

**Interfaces:**
- Produces `MeetingConfiguration.fromEnvironment()`.
- Produces `MeetingConfiguration.isEnabled`, `MeetingConfiguration.serverUrl`, dan `MeetingConfiguration.maxParticipants`.
- Tidak menghasilkan token atau menyimpan secret.

- [x] Tambahkan dependency `livekit_client` dengan `flutter pub add livekit_client`; jangan meng-upgrade dependency lain.
- [x] Implementasikan `MeetingConfiguration.fromEnvironment()` dengan nilai default feature flag `false`, URL kosong, dan kapasitas `8`.
- [x] Validasi konfigurasi: URL kosong membuat `isAvailable == false`, kapasitas di luar 2..8 kembali ke `8`, dan string environment di-trim.
- [x] Tulis test `disabledByDefault`, `readsProviderUrl`, `clampsParticipantLimit`, dan `neverExposesSecretFields`.
- [x] Jalankan `flutter pub get` lalu `flutter test --no-pub test/features/meeting/meeting_configuration_test.dart`.
- [x] Jalankan `flutter build web --no-pub` dan `flutter build windows --no-pub` untuk membuktikan dependency tidak merusak target MVP.

**Acceptance criteria:**
- `MeetingConfiguration` aman ketika Supabase atau provider belum dikonfigurasi.
- Build Web dan Windows tetap dapat dibuat.
- Tidak ada API secret atau service-role value pada class config client.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_configuration_test.dart`, `flutter build web --no-pub`, `flutter build windows --no-pub`.

## Task 2: Domain Contract dan Error Mapping

**Files:**
- Create: `lib/features/meeting/domain/meeting_models.dart`
- Create: `lib/features/meeting/domain/meeting_errors.dart`
- Create: `test/features/meeting/meeting_models_test.dart`

**Interfaces:**
- `MeetingStatus { idle, creating, joining, connected, reconnecting, ended, error }`.
- `MeetingParticipantRole { host, publisher, viewer }`.
- `MeetingSession.fromJson(Map<String, dynamic>)` dan `toJson()`.
- `MeetingParticipant.fromJson(Map<String, dynamic>)` dan `toJson()`.
- `MeetingState.initial({required String projectId, String? meetingId})` dan `copyWith(...)`.
- `MeetingErrorCode { authorizationError, capacityFull, permissionDenied, providerUnavailable, ended, removed, unavailable }` dan `MeetingErrorMessage.forCode(...)`.
- `MeetingToken` dengan `token`, `serverUrl`, `expiresAt`, dan `identity`.
- `MeetingTerminationReason { ended, removed, roomRevoked, expired, providerError }`.

- [x] Definisikan `MeetingSession` dengan `id`, `projectId`, `provider`, `providerRoomName`, `status`, `createdBy`, `createdAt`, `endedAt`, `endedReason`, dan `maxParticipants`.
- [x] Definisikan `MeetingParticipant` dengan `identity`, `displayName`, `role`, `isLocal`, `microphoneEnabled`, `cameraEnabled`, `screenShareEnabled`, dan `isSpeaking`.
- [x] Definisikan `MeetingMediaEvent` untuk connection, participant, track, active speaker, token refresh, dan provider error tanpa membawa SDP/ICE ke state UI.
- [x] Definisikan `MeetingState` immutable dengan session nullable, participant map keyed by identity, local media flags, status, error code, error message, dan `isHost`.
- [x] Implementasikan parsing tanggal, enum wire names, dan fallback error secara deterministic.
- [x] Tulis test round-trip JSON, invalid enum fallback, `copyWith`, role-derived flags, dan user-facing message mapping.
- [x] Jalankan `dart format lib/features/meeting test/features/meeting` dan test file domain.

**Acceptance criteria:**
- Domain model tidak mengimpor package LiveKit.
- JSON malformed tidak membuat state crash; parser menghasilkan error terkontrol.
- Status terminal `ended` tidak dapat kembali ke `connected` melalui `copyWith` tanpa command controller.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_models_test.dart`.

## Task 3: Supabase Meeting Session Schema

**Files:**
- Create: `supabase/migrations/20260915070000_create_meeting_sessions.sql`
- Create: `test/supabase/video_meeting_migration_test.dart`

**Interfaces:**
- SQL table `public.meeting_sessions`.
- RPC `public.create_meeting_session(text, integer)`.
- RPC `public.join_meeting_session(uuid)`.
- RPC `public.end_meeting_session(uuid, text)`.

- [x] Buat table dengan `id uuid`, `project_id text references public.projects(id) on delete cascade`, `created_by uuid`, `provider text default 'livekit'`, `provider_room_name text unique`, `status text check (status in ('active','ended'))`, timestamps, reason, dan `max_participants integer check (max_participants between 2 and 8)`.
- [x] Tambahkan partial unique index agar satu project hanya memiliki satu session `active`.
- [x] Aktifkan RLS, revoke direct table writes dari `anon` dan `authenticated`, lalu expose hanya RPC yang diperlukan.
- [x] Implementasikan `create_meeting_session`: auth wajib, `is_project_owner` wajib, capacity 2..8, provider harus `livekit`, room name dibuat acak dari UUID, dan active duplicate mengembalikan row active yang sama tanpa membuat provider room kedua.
- [x] Implementasikan `join_meeting_session`: auth wajib, `project_role(project_id)` tidak null, status harus `active`, dan row yang dikembalikan tidak memuat secret.
- [x] Implementasikan `end_meeting_session`: auth wajib, owner/creator authorized, status update idempotent, reason dibatasi ke `host_ended`, `room_revoked`, `expired`, atau `admin_ended`.
- [x] Tulis migration contract test yang memeriksa table, check constraints, partial index, RLS, revoke, grants, dan authorization function names.
- [x] Jalankan `flutter test --no-pub test/supabase/video_meeting_migration_test.dart`.

**Acceptance criteria:**
- Unauthorized user tidak dapat membuat, join, atau end session melalui RPC.
- Active duplicate per project mengembalikan session active yang sama tanpa membuat second provider room.
- Migration tidak mengubah table collaboration yang sudah ada.

**Verification:** `flutter test --no-pub test/supabase/video_meeting_migration_test.dart`; linked `supabase db push --linked --yes` remains pending and was not run.

## Checkpoint: Backend Foundation

- [x] Task 1–3 selesai tanpa perubahan pada CRDT atau screen tracking.
- [x] Unit test domain/config dan migration contract test lulus.
- [x] Web dan Windows build tetap lulus.
- [x] Review manual schema dan permission sebelum token gateway dibuat.

## Task 4: Authenticated Meeting Token Gateway

**Files:**
- Create: `supabase/functions/meeting-token/index.ts`
- Create: `supabase/functions/meeting-token/index_test.ts`
- Modify: `supabase/config.toml:1-15`

**Interfaces:**
- `POST /functions/v1/meeting-token` dengan `{ "meetingId": "uuid" }`.
- Sukses: `{ token, serverUrl, expiresAt, identity }`.
- Error: `{ error: { code, message } }` dengan status 4xx/5xx.

- [ ] Tambahkan konfigurasi function dengan `verify_jwt = false` karena function memvalidasi Bearer token secara eksplisit seperti function authenticated lain di repo.
- [ ] Implementasikan `OPTIONS` dan `POST`; method lain mengembalikan 405.
- [ ] Implementasikan origin allowlist dari `ALLOWED_ORIGINS`; origin kosong hanya diterima untuk request non-browser yang sesuai pola function repo.
- [ ] Implementasikan Bearer parsing dan Supabase `auth.getUser`/equivalent authenticated helper tanpa menerima user ID dari request body.
- [ ] Validasi `meetingId` sebagai UUID, ambil active session, dan cek `project_role(session.project_id)` memakai user yang authenticated.
- [ ] Hitung participant aktif dari LiveKit RoomService; jika jumlah sudah `max_participants`, kembalikan 409 dan jangan menerbitkan token.
- [ ] Buat token dengan identity auth user, room provider name, TTL pendek, `canSubscribe: true`, `canPublish: role != viewer`, dan `canPublishSources` yang membatasi screen share ke role yang diizinkan.
- [ ] Ambil `LIVEKIT_URL`, `LIVEKIT_API_KEY`, dan `LIVEKIT_API_SECRET` hanya dari `Deno.env`; jika kosong, kembalikan error konfigurasi tanpa detail secret.
- [ ] Tulis test helper untuk malformed body, missing auth, invalid UUID, ended session, unauthorized project, capacity full, missing env, dan successful grant.
- [ ] Jalankan test Deno sesuai script Edge Function repo dan pastikan response tidak mengandung secret.

**Acceptance criteria:**
- Hanya member aktif yang menerima token untuk room aktif.
- Viewer tidak menerima grant publish.
- Secret provider dan service-role tidak pernah dikembalikan atau ditulis ke log.

**Verification:** `supabase functions serve meeting-token` dengan env test, `supabase functions deploy meeting-token`, dan contract test function.

## Task 5: Repository dan Supabase Client Boundary

**Files:**
- Create: `lib/features/meeting/data/meeting_repository.dart`
- Create: `test/features/meeting/meeting_repository_test.dart`
- Modify: `lib/data/remote/supabase_service.dart:39-45`

**Interfaces:**
- `Future<MeetingSession> createMeeting({required String projectId, int maxParticipants = 8})`.
- `Future<MeetingSession> joinMeeting({required String meetingId})`.
- `Future<MeetingToken> requestToken({required String meetingId})`.
- `Future<MeetingSession> endMeeting({required String meetingId, String reason = 'host_ended'})`.
- `Stream<MeetingSession> watchMeeting(String meetingId)`.

- [ ] Buat repository yang menerima `SupabaseClient?` melalui constructor agar test tidak memerlukan global Supabase initialization.
- [ ] Map RPC response ke `MeetingSession` dan function response ke `MeetingToken` dengan validasi field wajib.
- [ ] Gunakan `client.functions.invoke('meeting-token', body: {'meetingId': meetingId})` dan map non-2xx menjadi `MeetingErrorCode.authorizationError`, `capacityFull`, atau `providerUnavailable`.
- [ ] Gunakan Postgres Realtime pada `meeting_sessions` untuk `watchMeeting`; filter hanya `id == meetingId` dan status change yang relevan.
- [ ] Tambahkan helper pada `SupabaseSyncService` hanya jika existing service pattern memerlukannya; jangan menaruh LiveKit token logic di service canvas.
- [ ] Tulis fake-client tests untuk RPC names/params, token body, malformed response, function error, dan stream end.
- [ ] Jalankan `flutter test --no-pub test/features/meeting/meeting_repository_test.dart`.

**Acceptance criteria:**
- Repository tidak mengekspos service-role credential.
- Error mapping stabil dan dapat dipakai controller/UI.
- Session stream berhenti setelah status `ended` atau repository dispose.

**Verification:** focused repository test dan `flutter analyze --no-pub`.

## Task 6: Media Port dan LiveKit Adapter

**Files:**
- Create: `lib/features/meeting/data/meeting_media_port.dart`
- Create: `lib/features/meeting/data/livekit_meeting_media.dart`
- Create: `test/features/meeting/meeting_media_port_test.dart`
- Modify: `pubspec.yaml:28-93` hanya jika Task 1 belum mencatat dependency resolved

**Interfaces:**
- `MeetingMediaPort.connect(serverUrl:, token:)`.
- `setMicrophoneEnabled(bool)`, `setCameraEnabled(bool)`, `setScreenShareEnabled(bool)`.
- `disconnect()` dan `dispose()`.
- `Stream<MeetingMediaEvent> events`.

- [x] Implementasikan adapter dengan satu provider room per `MeetingController`; connect kedua saat room sudah aktif harus menjadi no-op atau error deterministic, bukan membuat duplicate room.
- [x] Map provider connection events ke `MeetingStatus.connected`, `reconnecting`, `ended`, dan `error`.
- [x] Publish local microphone/camera hanya setelah `connect` sukses dan sesuai grant provider.
- [x] Map remote participant join/leave, track subscribed/unsubscribed, mute state, camera state, screen-share state, dan active speaker ke `MeetingMediaEvent`.
- [x] Simpan track handle hanya di adapter/domain opaque wrapper; jangan simpan SDP atau ICE di `MeetingState`.
- [x] Implementasikan screen-share stop dari browser picker, Windows capture stop, route leave, provider room close, dan adapter dispose.
- [x] Buat fake media port pada test untuk memastikan command dan event order tanpa device.
- [x] Tulis test connect idempotency, local toggles, remote event mapping, provider failure, reconnect, dan cleanup idempotency.
- [x] Jalankan focused media tests dan build Web/Windows karena adapter menyentuh platform plugin.

**Acceptance criteria:**
- Adapter tidak mengubah `ScreenTrackingService`.
- Semua local tracks dihentikan pada `disconnect`/`dispose`.
- UI dapat menerima participant/track event tanpa mengimpor raw WebRTC signaling.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_media_port_test.dart`, `flutter build web --no-pub`, `flutter build windows --no-pub`.

**Known SDK limitation:** `livekit_client` 2.13 exposes server token refresh only through an `@internal` signal event. The adapter keeps token-refresh mapping in the provider-neutral seam and tests it without importing internal SDK APIs; the default public-API provider cannot observe that callback.

## Checkpoint: Media Foundation

- [x] Task 4–6 selesai dan provider secret hanya ada pada Edge Function env.
- [x] Fake media port membuktikan state transition tanpa kamera/mikrofon nyata.
- [x] LiveKit adapter tidak tercampur dengan CRDT atau one-to-one canvas screen tracking.
- [ ] Manual smoke test satu client dapat connect dan disconnect dengan cleanup bersih.

## Task 7: Meeting Controller dan Lifecycle

**Files:**
- Create: `lib/features/meeting/state/meeting_controller.dart`
- Create: `test/features/meeting/meeting_controller_test.dart`
- Modify: `lib/features/collaboration/state/collaboration_session_provider.dart:730-912` hanya untuk expose entry command/meeting indicator tanpa memindahkan media state

**Interfaces:**
- `meetingControllerProvider` scoped by `projectId`.
- `Future<MeetingSession> startMeeting({int maxParticipants = 8})`.
- `Future<void> join({required String meetingId})`.
- `Future<void> toggleMicrophone()`.
- `Future<void> toggleCamera()`.
- `Future<void> toggleScreenShare()`.
- `Future<void> leave()`.
- `Future<void> endForEveryone()`.
- `Future<void> removeParticipant(String identity)`.

- [ ] Implementasikan dependency injection untuk `MeetingRepository` dan `MeetingMediaPort` agar test tidak menggunakan LiveKit nyata.
- [ ] Implementasikan start flow: create session, request token, connect media, lalu publish default device state; return `MeetingSession` agar route memperoleh `meetingId`.
- [ ] Implementasikan join flow: join RPC dengan `meetingId`, request token, connect media, dan populate local role/session.
- [ ] Teruskan `MeetingMediaEvent` ke immutable `MeetingState` dan deduplicate participant events berdasarkan identity/track ID.
- [ ] Implementasikan token refresh tanpa mengganti meeting ID atau mengulang create session.
- [ ] Implementasikan `leave` dan `dispose` idempotent; end-for-everyone memanggil end RPC lalu disconnect lokal.
- [ ] Saat `watchMeeting` menerima `ended`, `room_revoked`, atau participant removed untuk identity lokal, controller mengakhiri media dan menetapkan error/status yang sesuai.
- [ ] Tambahkan guard feature flag dan membership failure sebelum membuka media device.
- [ ] Tulis tests untuk start/join success, duplicate join, viewer grant, toggle, reconnect, end, remove, route dispose, dan error mapping.
- [ ] Jalankan focused controller test dan `flutter analyze --no-pub`.

**Acceptance criteria:**
- Controller tetap dapat dites tanpa network/device.
- Lifecycle terminal selalu memanggil disconnect dan membersihkan participant/track state.
- Collaboration session hanya menyediakan entry/indicator; tidak menyimpan raw provider state.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_controller_test.dart` dan analyzer.

## Task 8: Pre-Join, Route, dan Meeting Entry

**Files:**
- Create: `lib/features/meeting/presentation/pre_join_screen.dart`
- Create: `test/features/meeting/pre_join_screen_test.dart`
- Modify: `lib/main.dart:98-121`
- Modify: `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart:2989-2999`

**Interfaces:**
- `PreJoinScreen({required String meetingId, required String projectId})`.
- Route `/meeting/:meetingId` menerima `projectId` melalui query parameter yang bukan credential.
- Entry command hanya tersedia saat `MeetingConfiguration.isEnabled` dan collaboration membership valid.

- [ ] Tambahkan `GoRoute(path: '/meeting/:meetingId', ...)` dengan redirect ke `/auth` jika Supabase session tidak aktif.
- [ ] Validasi `meetingId` sebelum membuat controller; malformed route menampilkan error page aman.
- [ ] Buat pre-join state untuk camera preview, microphone level/status jika tersedia, loading, denied, failed, dan join button.
- [ ] Pastikan pre-join tidak membuat durable participant row dan tidak mem-publish track sebelum user menekan `Join`.
- [ ] Tambahkan tombol `Start Video Meeting`/`Join Video Meeting` di collaboration surface tanpa mengganggu room revoke, follow, atau screen tracking actions.
- [ ] Tulis widget tests untuk disabled flag, auth redirect input, join enabled/disabled, permission denied, dan error retry.
- [ ] Jalankan `flutter test --no-pub test/features/meeting/pre_join_screen_test.dart`.

**Acceptance criteria:**
- User tidak dapat masuk meeting melalui URL tanpa authorization backend.
- Kamera/mikrofon belum dipublish sebelum konfirmasi join.
- Route share publik tetap berperilaku sama.

**Verification:** focused widget test dan `flutter build web --no-pub`.

## Task 9: Meeting Stage, Tiles, Toolbar, dan Host Panel

**Files:**
- Create: `lib/features/meeting/presentation/meeting_screen.dart`
- Create: `lib/features/meeting/presentation/widgets/participant_tile.dart`
- Create: `lib/features/meeting/presentation/widgets/meeting_toolbar.dart`
- Create: `lib/features/meeting/presentation/widgets/meeting_participants_panel.dart`
- Create: `test/features/meeting/meeting_widgets_test.dart`

**Interfaces:**
- `MeetingScreen({required String meetingId, required String projectId})`.
- `ParticipantTile({required MeetingParticipant participant})`.
- `MeetingToolbar({required MeetingState state, required callbacks})`.
- `MeetingParticipantsPanel({required MeetingState state, required callbacks})`.

- [ ] Implementasikan responsive layout: grid untuk beberapa participant, local tile, selected/pinned tile, empty video fallback, initials/avatar, mute icon, camera-off label, screen-share badge, dan speaking outline.
- [ ] Gunakan adapter-owned video surface agar `meeting_screen.dart` tidak membuat `RTCVideoRenderer` atau mengakses SDP/ICE.
- [ ] Implementasikan toolbar microphone, camera, screen share, participants, leave, dan error/reconnect indicator.
- [ ] Implementasikan leave confirmation dan end-for-everyone confirmation terpisah.
- [ ] Panel host menampilkan remove action hanya untuk owner; viewer/editor tidak melihat action terlarang.
- [ ] Pastikan screen share tile dapat dipin dan kembali ke camera tile tanpa mengubah canvas screen tracking state.
- [ ] Tambahkan accessibility label, keyboard focus order, high contrast tokens, dan reduced-motion behavior mengikuti app theme.
- [ ] Tulis widget tests untuk tile variants, local toggle callbacks, role visibility, reconnect banner, ended state, dan responsive participant count.
- [ ] Jalankan focused widget tests dan `dart format` pada feature meeting.

**Acceptance criteria:**
- UI tidak crash ketika participant join/leave bersamaan dengan route dispose.
- Semua action memiliki loading/disabled state saat command sedang berjalan.
- Host controls tidak dapat dipicu melalui widget state saja tanpa guard controller/backend.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_widgets_test.dart`, Web build, Windows build.

## Task 10: Realtime End, Remove, Revoke, and Failure Hardening

**Files:**
- Modify: `lib/features/meeting/data/meeting_repository.dart`
- Modify: `lib/features/meeting/state/meeting_controller.dart`
- Modify: `lib/features/collaboration/state/collaboration_session_provider.dart:765-912`
- Create: `test/features/meeting/meeting_lifecycle_integration_test.dart`

**Interfaces:**
- `MeetingRepository.watchMeeting` emits terminal session transitions.
- `MeetingController.handleExternalTermination(MeetingTerminationReason reason)`.
- Existing `removeMember`, `disableRoom`, and `stopScreenTracking` remain source-compatible.

- [ ] Subscribe controller to durable session updates and map `ended` to local leave exactly once.
- [ ] When collaboration member removal or room revoke occurs, call `handleExternalTermination` before canvas session cleanup completes.
- [ ] Ensure meeting cleanup does not call `stopScreenTracking` on the existing one-to-one screen service unless that service owns the same capture, which it must not in the new architecture.
- [ ] Add retry backoff for token refresh and media reconnect with a finite attempt count; after exhaustion expose `providerUnavailable` and a retry action.
- [ ] Ignore late provider events after controller dispose using generation/session ID checks.
- [ ] Add redacted structured logs for join latency, state transitions, reconnect count, and terminal reason; omit token, SDP, ICE, and raw participant payloads.
- [ ] Write integration-style tests for end race, remove race, revoke while reconnecting, duplicate leave, late event, and provider error.
- [ ] Run collaboration tests that cover role change, kick, follow, screen share, and room revoke to detect regressions.

**Acceptance criteria:**
- End/remove/revoke always disconnect media and return user to canvas.
- Late events cannot resurrect an ended meeting.
- Existing collaboration screen tracking and canvas lifecycle tests remain green.

**Verification:** `flutter test --no-pub test/features/meeting/meeting_lifecycle_integration_test.dart` and the focused collaboration test suite.

## Checkpoint: End-to-End MVP

- [ ] Tasks 7–10 complete.
- [ ] Host can start/end; authorized guest can join/leave; viewer is subscribe-only.
- [ ] Camera, microphone, screen share, roster, responsive stage, and reconnect work in fake tests.
- [ ] No client secret appears in source, compiled asset, URL, or log fixture.
- [ ] Manual Windows ↔ Chrome two-client test passes in both directions.

## Task 11: Deployment Documentation and Release Gates

**Files:**
- Modify: `README.md`
- Modify: `supabase/config.toml`
- Create: `docs/video-meeting-release-checklist.md`
- Create: `tool/video_meeting_platform_matrix.ps1`
- Create: `test/features/meeting/video_meeting_release_contract_test.dart`

**Interfaces:**
- Documented env names: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `ALLOWED_ORIGINS`, and client-safe feature flag/provider URL.
- Script exit code `0` only when required Web/Windows build and configuration checks pass.

- [ ] Dokumentasikan provider setup, Edge Function deployment, secret placement, allowed origins, feature flag rollout, and cleanup behavior.
- [ ] Dokumentasikan manual matrix: Windows host ↔ Chrome guest, Chrome host ↔ Windows guest, permission denial, screen share, reconnect, end, remove, and room revoke.
- [ ] Buat PowerShell release gate yang memeriksa env names tanpa mencetak values, menjalankan targeted test, analyzer, Web build, dan Windows build secara berurutan.
- [ ] Tambahkan contract test yang memastikan README dan config menyebut endpoint/function name yang sama.
- [ ] Jalankan release gate dengan feature flag off untuk memastikan aplikasi existing tetap berjalan.

**Acceptance criteria:**
- Engineer lain dapat deploy token gateway tanpa menebak secret name atau command.
- Release gate gagal jika secret ditaruh di client config atau function belum dikonfigurasi.
- Manual test evidence memiliki tanggal absolut dan arah host/guest yang jelas.

**Verification:** `powershell -ExecutionPolicy Bypass -File tool/video_meeting_platform_matrix.ps1` dan seluruh repository gates.

## Checkpoint: Complete

- [ ] Semua acceptance criteria pada spec terpenuhi.
- [ ] `dart format` dan `flutter analyze --no-pub` lulus.
- [ ] `flutter test --no-pub` lulus tanpa failure baru.
- [ ] `flutter build web --no-pub` lulus.
- [ ] `flutter build windows --no-pub` lulus.
- [ ] Supabase migration dan `meeting-token` terdeploy pada environment target.
- [ ] Manual Windows/Web matrix lulus.
- [ ] Feature flag rollout siap direview.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| LiveKit SDK tidak stabil pada salah satu target | High | Task 1 memaksa Web/Windows build spike sebelum UI dibuat; adapter membatasi blast radius. |
| Token gateway salah mengizinkan project member | Critical | RPC/RLS dan Edge Function melakukan membership check; test unauthorized wajib sebelum UI. |
| Credential provider masuk client bundle | Critical | Secret hanya di Edge Function env; release contract test mencari secret-shaped values dan README policy. |
| Reconnect race menghidupkan meeting yang sudah ended | High | Durable status, generation/session ID checks, idempotent cleanup, lifecycle integration test. |
| Screen share meeting tercampur screen tracking canvas | High | Adapter meeting terpisah; tidak mengubah `ScreenTrackingService` atau `_screenTracking` ownership. |
| Provider cost meningkat karena room terlalu besar | Medium | Server cap 8, feature flag, join metrics, dan review capacity sebelum menaikkan limit. |
| Browser/Windows permission berbeda | High | Pre-join state machine, retry UI, dan manual matrix dua arah. |
| Realtime session event terlambat | Medium | Join/status RPC tetap source of truth; provider disconnect dan periodic session check menangani stale event. |

## Open Questions

- Apakah deployment pertama menggunakan LiveKit Cloud atau self-hosted LiveKit setelah provider spike biaya dan data residency?
- Apakah `commenter` boleh screen share pada deployment pertama, atau hanya `owner` dan `editor`?
- Apakah pencatatan attendance diperlukan sebelum release publik?
- Apakah revoke collaboration room harus selalu mengakhiri meeting aktif secara durable?

## Execution Notes

Implementasi dimulai hanya setelah plan ini ditinjau. Jalankan Task 1–3 secara berurutan, lalu lakukan review backend sebelum Task 4. Task 6 membutuhkan verifikasi platform nyata; jangan mengklaim dukungan Windows/Web hanya dari analyzer. Setelah Task 9, lakukan manual two-client test sebelum menambah hardening dan release documentation.
