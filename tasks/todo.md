# Checklist Implementasi Kolaborasi

## Foundation

- [x] Tambahkan `CollaborationRole` dan `CollaborationPermissions`.
- [x] Perluas model `CanvasMember` dengan profil dan metadata aktivitas.
- [x] Tambahkan model event control-plane dengan validasi payload.
- [x] Tambahkan migration profil anggota, policy, dan RPC management.
- [x] Tambahkan test model dan migration.

## Roster dan Role

- [x] Tambahkan transport event role/remove/profile.
- [x] Buat panel anggota responsive untuk host dan guest.
- [x] Tampilkan role, status online, cursor-active, dan last seen.
- [x] Implementasikan role change dan remove realtime.
- [x] Pisahkan permission session dari `widget.readOnly`.
- [x] Tambahkan guard pada node, komentar, AI, history, dan toolbar.

## Follow Viewport

- [x] Kirim viewport position dan zoom secara ter-debounce.
- [x] Implementasikan request/approve/reject/stop.
- [x] Implementasikan follow viewport tanpa mengambil alih input.
- [x] Bersihkan follow state saat disconnect, revoke, remove, atau dispose.

## Screen Tracking

- [x] Verifikasi capability WebRTC Web dan Windows melalui analyzer/build.
- [x] Tambahkan adapter capture layar per platform.
- [x] Tambahkan signaling offer/answer/ICE melalui Realtime.
- [x] Tambahkan consent dialog dan indikator sharing.
- [x] Tambahkan viewer stream dan tombol stop.
- [x] Tambahkan cleanup untuk leave, revoke, remove, disconnect, dan error.
- [x] Dokumentasikan kebutuhan STUN/TURN.

## Verification

- [x] Jalankan `supabase db push --linked --yes` pada 9 September 2026.
- [x] Jalankan `dart format` pada file yang berubah.
- [x] Jalankan `flutter analyze --no-pub`.
- [x] Jalankan `flutter test --no-pub` tanpa failure lama di luar fitur.
- [x] Jalankan `flutter build web --no-pub`.
- [x] Jalankan `flutter build windows --no-pub`.
- [ ] Uji Windows host ↔ Chrome guest.
- [ ] Uji Chrome host ↔ Windows guest.
- [x] Uji role change, kick, follow, consent, stop, revoke, dan reconnect.
