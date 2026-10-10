# Checklist: Canva-like Asset Library

## Phase 0 — Contract and local foundation

- [x] Tambahkan model `AssetLibraryItem`, query, page, source/license/status.
- [x] Tambahkan repository contract dan mapping ke `DocumentAsset`.
- [x] Tambahkan local-first catalog/cache dengan corrupt-record recovery.
- [x] Normalisasi upload: UUID, checksum, MIME, size, type/size validation.
- [x] Tambahkan unit tests model, query, parser, dedupe dan local persistence.

## Phase 1 — UI and local end-to-end

- [x] Ubah dialog menjadi responsive grid dengan category/sidebar.
- [x] Tambahkan search, sort, folder/tag, favorites, used-in-document.
- [x] Tambahkan thumbnail, loading, empty/offline/error state dan details/license.
- [x] Tambahkan multiple upload dengan progress dan per-file failure.
- [x] Tambahkan save/favorite/tag/folder actions.
- [x] Insert provider/upload item menjadi `DocumentAsset` + node dengan satu ID.
- [x] Pertahankan kompatibilitas node-derived assets dan read-only mode.
- [x] Widget/integration tests: upload → library → insert → reload.

## Checkpoint A

- [x] `flutter test --no-pub test/features/assets/`
- [x] `dart analyze` untuk modul asset library dan editor.
- [ ] Manual responsive check 320/768/1024/1440 px.

## Phase 2 — Supabase

- [x] Buat migration table item/folder/favorite/usage/cache.
- [x] Tambahkan indexes, uniqueness, RLS, grants dan project-scoped Storage policy.
- [x] Hubungkan quota `assetBytes` dan audit/usage idempotency.
- [x] Tambahkan typed remote repository, retry dan offline reconciliation.
- [x] Tambahkan migration/remote/RLS contract tests.
- [x] Review migration sebelum `supabase db push --linked --yes`; linked migrations are current.
- [ ] Rotate/revoke production API, service-role, and CLI database credentials
      exposed in terminal output before release.

## Phase 3 — Open-source providers

- [x] Implementasikan normalized Openverse image/audio provider.
- [x] Tambahkan fixture tests untuk pagination, malformed response dan
      license/attribution.
- [x] Tambahkan Edge Function/proxy allowlist bila provider dipakai production.
- [x] Simpan metadata provider ke library tanpa menyalin binary ke Postgres.
- [x] Tambahkan URL/size/path boundary validation tests.

## Phase 4 — Expansion

- [ ] Curate and verify icon/illustration packs (Lucide/Tabler/OpenMoji/unDraw).
- [ ] Tambahkan Wikimedia connector.
- [ ] Tambahkan video/audio/3D adapters memakai existing pipelines.
- [x] Tambahkan usage count dan relink/replace yang sudah dipakai library.
- [x] Selesaikan orphan cleanup lifecycle (aged UUID upload paths); previews/thumbnails are references only, so no derived thumbnail objects require deletion.
- [x] Update export/license documentation dan loss report.
- [ ] `flutter test --no-pub`
- [x] `flutter build web --no-pub`
- [x] `flutter build windows --no-pub`
