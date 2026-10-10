# Implementation Plan: Canva-like Asset Library

## Overview

Bangun asset library bertahap di atas manifest/CRDT yang sudah ada. Slice
pertama harus usable tanpa backend: grid, kategori, search, upload, favorite,
folder/tag, dan insert image. Supabase kemudian menjadi persistence metadata +
Storage binary, sedangkan Openverse menjadi provider image search dengan
normalisasi dan attribution. Semua hasil provider yang dipakai dokumen harus
memiliki `DocumentAsset` reference yang durable atau status error yang terlihat.

## Dependency graph

```text
AssetLibraryItem + query contract
        |
        +--> local-first repository/cache + provider parser
        |             |
        |             +--> dialog grid/search/filter/favorite/upload
        |                                   |
        |                                   +--> insert -> DocumentAsset + node
        |
        +--> Supabase migration/RLS/RPC + Storage path policy
                      |
                      +--> remote repository sync + offline fallback

Openverse Edge Function/provider connector --> normalized search page
```

## Architecture decisions

1. **Project scope sekarang, workspace scope nanti.** Backend belum memiliki
   workspace id terpisah; `project_id` dipakai sebagai scope aman dan kontrak
   item tidak mengunci implementasi ke sana.
2. **Metadata dan binary dipisah.** Postgres menyimpan katalog/provenance;
   Storage menyimpan original/thumbnail; document/CRDT hanya menyimpan id dan
   reference, bukan bytes.
3. **Local-first.** Local catalog ditampilkan segera; remote result di-cache
   dengan TTL dan kegagalan provider tidak menghilangkan upload lokal.
4. **Provider adapter terpisah.** UI tidak mengetahui format Openverse; semua
   response external divalidasi di adapter. Provider key, bila dibutuhkan,
   hanya berada di Edge Function secrets.
5. **Dedupe berdasarkan provider+providerAssetId atau checksum.** Insert ulang
   memakai item yang sama dan tidak upload binary kedua kali.
6. **Pertahankan API lama.** `AssetLibraryDialog(nodes, manifest, readOnly,
   onInsert)` tetap kompatibel; repository/callback baru bersifat optional saat
   transisi.

## Task List

### Phase 0: Contract and baseline

#### Task 1: Domain model, query, and repository seam

**Acceptance criteria:**
- [ ] `AssetLibraryItem`, kind/source/license/status, query, page dan typed
      repository contract dapat serialize/deserialize dengan input invalid yang
      ditolak secara aman.
- [ ] Mapping item ke `DocumentAsset` menghasilkan id, MIME, source,
      provenance/license, folder/tag dan durable reference.
- [ ] Search local dapat filter kategori, query, tag, folder, favorite dan
      sort tanpa network.

**Verification:** focused unit tests untuk model, parser, dedupe, query dan
mapping.

**Dependencies:** None

**Files likely touched:**
- `lib/features/assets/domain/asset_library.dart`
- `lib/features/assets/data/asset_library_repository.dart`
- `test/features/assets/asset_library_domain_test.dart`

**Estimated scope:** Medium

#### Task 2: Local persistence and upload normalization

**Acceptance criteria:**
- [ ] Upload result diberi UUID, checksum SHA-256, MIME/size, created/updated,
      default folder/tag dan status local.
- [ ] Catalog local survives restart dan corrupt record tidak merusak semua
      project.
- [ ] File size/type/path divalidasi; binary tidak dimasukkan ke catalog JSON
      selain fallback yang sudah ada.

**Verification:** local storage test, checksum/invalid input tests, focused
asset tests.

**Dependencies:** Task 1

**Files likely touched:**
- `lib/data/local/local_storage_service.dart`
- `lib/features/assets/data/asset_library_service.dart`
- `lib/features/assets/data/asset_service.dart`
- `test/data/local_storage_service_test.dart`
- `test/features/assets/asset_library_service_test.dart`

**Estimated scope:** Medium

### Checkpoint: Local catalog

- [ ] Existing asset dialog tests tetap lulus.
- [ ] Catalog lokal dapat diisi dari upload dan dicari tanpa Supabase.
- [ ] `flutter analyze --no-pub` lulus untuk slice ini.

### Phase 1: Usable Canva-like UI

#### Task 3: Responsive library grid and states

**Acceptance criteria:**
- [ ] Dialog menampilkan sidebar/category: All, Photos, Graphics/Icons,
      Illustrations, Video, Audio, 3D, Files, Uploads, Favorites dan Used in
      this document.
- [ ] Kartu memiliki thumbnail/skeleton, title, type, favorite, source/license
      indicator, Insert, dan details/attribution action.
- [ ] Search, category, folder/tag, sort, loading, empty, offline dan error
      state berfungsi di layar 320/768/1024/1440 px.
- [ ] Keyboard focus, semantic label dan read-only behavior tetap benar.

**Verification:** widget tests untuk filter/grid/states/keyboard semantics;
manual screenshot check pada Web/Windows.

**Dependencies:** Tasks 1-2

**Files likely touched:**
- `lib/features/assets/presentation/asset_library_dialog.dart`
- `lib/features/assets/presentation/widgets/asset_library_card.dart`
- `lib/features/assets/presentation/widgets/asset_library_filters.dart`
- `test/features/assets/asset_library_dialog_test.dart`

**Estimated scope:** Large; bila >200 LOC pecah card/filter menjadi task terpisah.

#### Task 4: Upload, favorite, folder/tag and insert flow

**Acceptance criteria:**
- [ ] User dapat upload multiple files, menyimpan ke local catalog dan melihat
      progress/failure per file.
- [ ] Favorite/folder/tag tersimpan per scope; item provider dapat di-save
      tanpa kehilangan license/attribution.
- [ ] Insert image membuat satu `DocumentAsset` manifest record dan image node
      yang memakai asset ID yang sama; duplicate insert tidak menggandakan
      binary/manifest.
- [ ] Existing node-derived assets tetap tampil selama masa transisi.

**Verification:** widget/service tests; integration test upload -> library ->
insert -> reload.

**Dependencies:** Task 3

**Files likely touched:**
- `lib/features/assets/data/asset_library_service.dart`
- `lib/features/assets/presentation/asset_library_dialog.dart`
- `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart`
- `lib/domain/models/document_asset.dart`
- `test/features/assets/asset_library_insert_test.dart`

**Estimated scope:** Large

### Checkpoint: Local end-to-end

- [ ] Upload -> search -> favorite -> folder/tag -> insert -> reload berhasil.
- [ ] Dokumen lama tanpa manifest tidak rusak.
- [ ] Tidak ada binary besar di CRDT operation atau document metadata.

### Phase 2: Supabase persistence

#### Task 5: Metadata schema, RLS and Storage policy

**Acceptance criteria:**
- [ ] Migration membuat table item, folder, favorite dan usage/cache yang
      diperlukan; uniqueness mencegah provider/checksum duplicate.
- [ ] Member dapat membaca item project; hanya editor dapat write/delete;
      favorite hanya user sendiri; system catalog read-only; anon/service key
      access tidak terbuka.
- [ ] Storage path selalu project-scoped dan policy tidak mengubah akses asset
      legacy. Quota `assetBytes` memakai usage ledger existing.

**Verification:** SQL migration tests untuk table/index/constraint/policy/grant;
Supabase local verification. Jangan push linked production tanpa approval.

**Dependencies:** Tasks 1-2

**Files likely touched:**
- `supabase/migrations/<timestamp>_create_asset_library.sql`
- `test/supabase/asset_library_migration_test.dart`
- `README.md` (deployment note)

**Estimated scope:** Large

#### Task 6: Remote repository and sync fallback

**Acceptance criteria:**
- [ ] Repository list/search/save/favorite/tag/folder/usage memakai typed
      response dan structured errors.
- [ ] Supabase unavailable/time-out otomatis memakai local cache dan status
      `offline/pending`; retry tidak menggandakan row atau upload.
- [ ] Upload metadata dan Storage binary konsisten; kegagalan salah satu tahap
      dapat dilanjutkan/reconcile.

**Verification:** fake Supabase/http tests, RLS contract tests, retry/idempotency
checks, Web/Windows build.

**Dependencies:** Tasks 4-5

**Files likely touched:**
- `lib/data/remote/supabase_service.dart` atau adapter baru di
  `lib/features/assets/data/`
- `lib/features/assets/data/asset_library_service.dart`
- `lib/features/assets/state/asset_library_provider.dart`
- `test/features/assets/asset_library_remote_test.dart`

**Estimated scope:** Large

### Phase 3: Open-source provider search

#### Task 7: Normalized Openverse connector

**Acceptance criteria:**
- [ ] Search image (dan audio bila adapter sudah siap) mendukung page/cursor,
      query dan license filter.
- [ ] Response field, URL, MIME, dimensions, creator, license dan attribution
      divalidasi; malformed item di-skip tanpa crash.
- [ ] Provider outage/rate limit menampilkan error yang bisa diretry dan
      catalog lokal tetap tersedia.

**Verification:** fixture tests tanpa network, HTTP status/timeout/invalid JSON
cases, provider attribution tests.

**Dependencies:** Task 1

**Files likely touched:**
- `lib/features/assets/data/providers/openverse_asset_provider.dart`
- `lib/features/assets/data/providers/asset_provider_contract.dart`
- `test/features/assets/openverse_provider_test.dart`

**Estimated scope:** Medium

#### Task 8: Provider proxy/import and provenance

**Acceptance criteria:**
- [ ] Provider API call melalui Edge Function atau allowlisted client path;
      tidak ada secret di Flutter.
- [ ] `Save to library` menyimpan provider id/source/license/creator/attribution
      dan hanya membuat managed copy jika terms mengizinkan.
- [ ] Arbitrary URL, private host, unsupported MIME, oversized response dan
      redirect berbahaya ditolak.

**Verification:** Edge Function tests, URL allowlist/size/magic-byte tests,
manual attribution review.

**Dependencies:** Tasks 5-7

**Files likely touched:**
- `supabase/functions/asset-library/index.ts`
- `supabase/functions/asset-library/helpers.ts`
- `supabase/functions/asset-library/index_test.ts`
- `lib/features/assets/data/asset_library_service.dart`

**Estimated scope:** Large

### Checkpoint: Remote catalog

- [ ] Openverse search -> preview -> save -> insert -> reload berhasil.
- [ ] License/creator attribution selalu terlihat di detail dan export.
- [ ] Provider failure tidak memblokir upload/local assets.

### Phase 4: Coverage and polish

#### Task 9: Additional packs and media types

**Acceptance criteria:**
- [ ] Curated icon/illustration packs diaktifkan hanya dengan license record
      yang diverifikasi; no-license asset tidak masuk catalog.
- [ ] Video/audio/3D adapter memakai existing node/player/GLB pipeline dan
      thumbnail/preview policy masing-masing.
- [ ] Add-to-canvas mempertahankan transform, asset ID dan provenance.

**Verification:** fixture/round-trip tests per type, manual cross-platform
preview, package export tests.

**Dependencies:** Tasks 4, 6, 8

**Files likely touched:**
- `lib/features/assets/`
- `lib/domain/models/document_asset.dart`
- `test/features/assets/`
- `docs/asset-library-sources.md`

**Estimated scope:** Large; split by media type before implementation.

#### Task 10: Usage analytics, cleanup and release gates

**Acceptance criteria:**
- [ ] usage count, last used, orphan detection, delete/relink and thumbnail
      cleanup tidak menghapus asset yang masih direferensikan.
- [ ] Export package menyertakan/exclude asset sesuai license/policy dengan
      loss report.
- [ ] Performance: paginated query, thumbnail-first, no document JSON growth
      proportional to repeated insert.

**Verification:** full tests, migration checks, `flutter analyze --no-pub`,
`flutter build web --no-pub`, `flutter build windows --no-pub`, manual full flow.

**Dependencies:** Task 9

**Files likely touched:**
- `lib/features/assets/`
- `lib/features/export/`
- `test/features/assets/`
- `test/features/export/`
- `docs/asset-library-sources.md`

**Estimated scope:** Medium

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Hak cipta/terms provider berbeda per asset | High | simpan license + URL + creator + attribution; filter default ke verified/free; review resmi sebelum seed. |
| External URL mati/hotlink/CORS | High | thumbnail cache, managed copy jika diizinkan, durable reference dan fallback status. |
| SSRF atau file berbahaya dari URL/upload | High | host allowlist, HTTPS, size/MIME/magic-byte validation, no arbitrary fetch. |
| Bucket existing public | High | jangan menganggap public URL private; pertahankan backward compatibility dan siapkan private/signed URL decision. |
| CRDT/document membesar | High | hanya asset id/reference, dedupe checksum, thumbnail separate, size cap. |
| Provider rate limit/outage | Medium | local-first, TTL cache, retry/backoff, built-in packs. |
| Scope lintas project belum punya workspace id | Medium | gunakan project scope sekarang, simpan migration path ke workspace scope. |

## Definition of Done

Pengguna dapat membuka library yang tidak lagi kosong, mencari/filter, upload,
menyimpan favorit/folder/tag, melihat provenance, dan insert asset ke canvas.
Local-first tetap usable; Supabase migration dan Storage menyimpan metadata/binary
secara aman; Openverse connector bekerja dengan pagination dan attribution;
asset lama tetap kompatibel; focused/full tests serta Web/Windows builds lulus.
