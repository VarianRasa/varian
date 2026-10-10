# Checklist Video Meeting

Plan utama: `docs/superpowers/plans/2026-09-15-video-meeting.md`  
Spec: `docs/superpowers/specs/2026-09-15-video-meeting-design.md`

## Foundation

- [x] Provider spike dan `MeetingConfiguration` selesai.
- [x] `livekit_client` terverifikasi pada Web dan Windows.
- [x] Domain model, state, dan error mapping selesai.
- [x] Migration `meeting_sessions` dan RPC selesai.

## Backend

- [x] Edge Function `meeting-token` selesai.
- [x] Membership, role, capacity, dan token TTL teruji.
- [x] Tidak ada secret provider pada client atau log.
- [x] Repository RPC/function/session stream selesai.

## Media

- [x] `MeetingMediaPort` selesai.
- [x] LiveKit adapter connect/disconnect selesai.
- [x] Opaque credentials and adapter-owned token refresh flow selesai.
- [x] Microphone dan camera publish/subscribe selesai.
- [x] Screen share Web dan Windows selesai.
- [x] Reconnect, token refresh, dan cleanup selesai.

## UI

- [x] Route `/meeting/:meetingId` selesai.
- [x] Pre-join screen selesai.
- [x] Participant grid dan tile states selesai.
- [x] Meeting toolbar selesai.
- [x] Roster dan host actions selesai.
- [x] Feature flag default off terpasang.

## Lifecycle dan QA

- [x] End meeting, remove participant, room revoke, dan member removal selesai.
- [x] Widget, controller, repository, migration, dan Edge Function tests selesai.
- [ ] Windows host ↔ Chrome guest teruji.
- [ ] Chrome host ↔ Windows guest teruji.
- [x] Permission denial dan reconnect teruji melalui fake/integration tests.
- [x] `flutter analyze --no-pub` lulus.
- [ ] `flutter test --no-pub` lulus; existing unrelated failures remain.
- [x] `flutter build web --no-pub` lulus melalui release gate.
- [x] `flutter build windows --no-pub` lulus melalui release gate.
- [x] README dan release checklist diperbarui.
