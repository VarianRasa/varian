# Spec: Canva-like Asset Library

## Objective

Meningkatkan `AssetLibraryDialog` dari daftar asset yang sudah dipakai di canvas
menjadi library yang dapat dicari dan digunakan ulang: asset bawaan, upload
milik pengguna, hasil pencarian Openverse, favorit, folder/tag, provenance dan
lisensi. Library harus tetap berfungsi lokal ketika Supabase atau provider
eksternal tidak tersedia.

Scope library awal adalah **project aktif** karena backend Varian saat ini
menggunakan `project_id` sebagai scope workspace. Model dapat diperluas ke
workspace lintas project tanpa mengubah kontrak item.

## Current baseline

- `DocumentAssetManifest` sudah menyimpan id, kind, storage, MIME, checksum,
  source, folder, tag, version, thumbnail, license dan metadata.
- Manifest sudah ikut tersimpan di `CanvasDocument` dan CRDT.
- `AssetLibraryDialog` saat ini hanya membaca node asset dan manifest; belum ada
  catalog provider, upload-to-library, favorite, persistence metadata, atau grid.
- Supabase Storage bucket `assets` dan policy project-scoped sudah ada, tetapi
  belum ada tabel metadata katalog library.
- Binary tidak boleh dimasukkan ke Postgres, document JSON, atau CRDT; simpan di
  Storage dan simpan metadata/reference saja.

## User stories / success criteria

- Pengguna dapat membuka library, memilih kategori, mencari, dan melihat kartu
  thumbnail dengan loading, empty, offline dan error state.
- Pengguna dapat upload satu atau banyak file ke library; file disimpan lokal
  dan, bila backend tersedia, metadata disimpan di Postgres serta binary di
  Supabase Storage.
- Pengguna dapat menyimpan hasil provider ke library, melihat creator/license/
  attribution, memfavoritkan, memberi tag/folder, dan memasukkannya ke canvas.
- Asset yang sama dipakai banyak node melalui satu asset ID; insert kedua tidak
  menggandakan binary.
- Asset remote yang dipakai di dokumen memiliki reference durable atau status
  missing yang jelas; provider URL yang kedaluwarsa tidak membuat canvas crash.
- Tidak ada API key provider di Flutter/client dan tidak ada scraping/copy asset
  Canva.

## Catalog policy

Default connector hanya untuk sumber yang provenance dan lisensinya dapat
disimpan per item:

- Openverse untuk image/audio search sebagai provider pertama.
- Wikimedia Commons sebagai connector berikutnya dengan license check per item.
- Curated/bundled icon/illustration packs (misalnya Lucide, Tabler, OpenMoji,
  unDraw) hanya setelah license resmi setiap pack diverifikasi dan attribution
  disertakan.
- Poly Haven untuk 3D hanya setelah adapter 3D dan license metadata tersedia.
- Unsplash/Pexels/Pixabay bukan open-source; boleh menjadi connector opt-in
  terpisah dengan API key server-side dan mengikuti terms/attribution mereka.

Kandidat sumber resmi untuk diverifikasi kembali sebelum connector diaktifkan:

- https://api.openverse.org/v1/
- https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia
- https://lucide.dev/license
- https://tabler.io/license
- https://openmoji.org/license/
- https://undraw.co/license
- https://polyhaven.com/license

## Data and interface contract

`AssetLibraryItem` adalah metadata katalog; `DocumentAsset` tetap menjadi
reference yang tertanam di dokumen. Item library menyimpan provider id, source,
thumbnail/preview, managed storage path bila ada, MIME/dimensi/durasi,
creator, license, attribution, tags/folder, checksum, usage dan metadata.
Favorite bersifat per-user, bukan boolean global pada item.

Repository contract minimum:

- `search(AssetLibraryQuery) -> AssetLibraryPage` dengan cursor/page-size.
- `saveUpload(...) -> AssetLibraryItem`.
- `saveProviderItem(...) -> AssetLibraryItem`.
- `setFavorite(itemId, active)`.
- `updateMetadata(itemId, folderId, tags, name)`.
- `delete(itemId)` dengan authorization.
- `recordUsage(itemId, projectId, nodeId)`.
- `toDocumentAsset(item) -> DocumentAsset`.

Response provider selalu divalidasi dan dinormalisasi sebelum dirender.

## Storage and security boundaries

- Postgres menyimpan metadata; Supabase Storage menyimpan binary. Preview/thumbnail saat ini hanya berupa reference (remote HTTPS atau object original); jika thumbnail turunan ditambahkan, ia harus mengikuti lifecycle Storage yang sama.
- Path upload harus project-scoped, misalnya
  `<projectId>/library/<itemId>/original.ext`; tidak menerima path dari user.
- Validasi size, MIME dan magic bytes; allowlist host provider; HTTPS only;
  jangan fetch URL arbitrer dari server (SSRF).
- RLS hanya mengizinkan member membaca dan editor mengubah asset project;
  favorite hanya dapat diubah user pemiliknya; system catalog read-only.
- API key provider hanya di Edge Function secrets. Provider response dianggap
  untrusted data.
- Untuk kompatibilitas tahap pertama dapat memakai bucket `assets` yang sudah
  ada, tetapi public URL bukan kontrol kerahasiaan. Migrasi ke private bucket +
  signed URL harus menjadi keputusan eksplisit jika upload private diperlukan.

## Commands

- Focused test: `flutter test --no-pub test/features/assets/`
- Analyze: `flutter analyze --no-pub`
- Full test: `flutter test --no-pub`
- Web build: `flutter build web --no-pub`
- Windows build: `flutter build windows --no-pub`

## Boundaries

- Always: pertahankan kontrak `DocumentAssetManifest`, simpan license/provenance,
  gunakan pagination, local fallback, validasi boundary, dan test setiap slice.
- Ask first: deploy migration ke Supabase production, provider berbayar/API key,
  perubahan public/private Storage bucket, dan dependency baru.
- Never: scrape/copy asset Canva, commit secret, menyimpan binary besar di
  Postgres/CRDT, atau melewati RLS dengan service-role key di client.

## Out of scope for first slice

- Editor gambar penuh, background removal, AI generation dan marketplace.
- Workspace global lintas banyak project sebelum model workspace resmi tersedia.
- Menyalin seluruh katalog provider ke database tanpa TTL/retention policy.
- Video/3D provider search sebelum resolver dan preview masing-masing siap.

## Open questions

1. Apakah asset upload boleh terlihat publik melalui URL Supabase, atau wajib
   private/signed URL?
2. Apakah connector berbayar seperti Unsplash/Pexels akan diaktifkan nanti?
3. Setelah slice image selesai, apakah prioritas berikutnya audio/video atau
   icon/illustration pack?

## Approval status

Draft ini dibuat untuk eksekusi bertahap. Implementasi dimulai dari local-first
catalog + Openverse image search + Supabase metadata migration; provider dan
storage yang membutuhkan credential tetap opt-in.
