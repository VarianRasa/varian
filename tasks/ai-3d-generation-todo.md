# Checklist Implementasi AI 3D Generation

## Spike

- [x] Pilih target platform dan cek GPU/VRAM untuk local development.
- [x] Benchmark fixture TripoSR image-to-3D pada GPU lokal dan catat output GLB/preview.
- [ ] Benchmark TRELLIS.2 sampai artifact GLB pada prompt/reference yang sama. Preview dan remote inference sudah berhasil; ekstraksi GLB tertahan quota anonymous ZeroGPU.
- [x] Benchmark Hunyuan3D-2.1 shape pada reference `chair.png` melalui official remote GPU Space; output GLB tervalidasi.
- [x] Pin revision TripoSR yang dipakai worker.
- [x] Rekonsiliasi adapter dengan API `Trellis2ImageTo3DPipeline` dan `o_voxel.postprocess.to_glb`.
- [ ] Provision dedicated remote Linux GPU dan pin revision TRELLIS.2 untuk deployment. Official remote GPU Space sudah dipakai untuk smoke benchmark, tetapi bukan endpoint worker dedicated.
- [x] Tambahkan hosted `fal-trellis2` fallback melalui server-side FAL queue adapter; provider tetap opt-in dan TripoSR tetap default.
- [ ] Jalankan live `fal-trellis2` smoke test setelah key/provider access diperbaiki. Percobaan eksplisit 2026-09-11 mencapai FAL tetapi ditolak HTTP 403 sebelum request ID/artifact.
- [x] Build ulang canonical TRELLIS.2 image setelah dependency runtime terakhir dan validasi health/auth/native extensions/Blender.
- [x] Generate license BOM transitive untuk canonical image dan salin lisensi native ke `/opt/varian/provenance/licenses`.
- [x] Uji GLB hasil worker pada validator dan canvas import test.
- [ ] Catat lisensi code, checkpoint, custom node, dan dependency untuk deployment dedicated. Source/model revisions dan keputusan Hunyuan sudah dicatat; BOM transitive remote belum tersedia.

## Contract

- [x] Tambahkan `AICapability.textTo3D` dan `AICapability.imageTo3D`.
- [x] Tambahkan parameter quality, texture mode, triangle budget, provider hint, dan source reference.
- [x] Tambahkan typed AI artifact untuk image/video/model3d.
- [x] Pastikan serialization job lama tetap backward compatible.

## Backend

- [x] Buat API async `create`, `poll`, `cancel`, dan `health` untuk job 3D.
- [x] Tambahkan endpoint `retry` dan UI retry action.
- [x] Tambahkan migration job 3D, RLS, idempotency, quota, dan storage handoff.
- [x] Simpan GLB di storage terkontrol; gunakan signed URL dan durable reference.
- [x] Tambahkan validasi MIME, magic header, size, SSRF, artifact URL, dan path traversal.

## Worker

- [x] Implementasikan `ThreeDGenerationProvider` adapter.
- [x] Tambahkan workflow ComfyUI/direct provider dengan API adapter dan pinned upstream revision; custom-node/workflow hash tetap wajib diisi saat deployment.
- [x] Tambahkan Blender headless post-processing dan GLB export.
- [x] Tambahkan progress, cancellation, timeout, dan cleanup.
- [x] Tambahkan preview image artifact.

## Flutter

- [x] Tambahkan tab/operation `Text -> 3D` dan `Image -> 3D`.
- [x] Hubungkan selected image/file ke controlled storage atau worker input.
- [x] Poll progress dan tampilkan cancel/error/no-GPU state.
- [x] Import hasil memakai `Model3DImportService` dan buat `NodeType.model3d`.
- [x] Pastikan collaborative hydration memakai `artifactReference`.

## Verification

- [x] Unit tests domain/API/artifact.
- [x] Integration test fake worker -> poll -> GLB -> canvas node.
- [x] Security tests auth/RLS/SSRF/size/path/callback.
- [x] `flutter analyze --no-pub`.
- [x] Focused `flutter test --no-pub`.
- [x] `flutter build web --no-pub`.
- [x] `flutter build windows --no-pub`.
- [x] Worker smoke test with deterministic `demo` provider.
- [x] Blender smoke test dengan executable portable 5.2.1.
- [x] Manual Windows and Web canvas test.

## Execution notes

- Supabase project `jnpxpylzzskaukgwhuzg` now has the AI 3D migration applied.
- Edge Function `ai-3d` is deployed and protected by JWT; unauthenticated health requests return HTTP 401.
- Local worker, security tests, ComfyUI adapter tests, Web/Windows build, and startup smoke tests pass.
- Authenticated Supabase Edge Function staging path was verified on 2026-09-11 through a token-protected HTTPS quick tunnel to the local TripoSR worker: create, poll, artifact download, storage handoff, and preview all completed.
- Hunyuan3D-2.1 remote shape benchmark completed on 2026-09-11: 74,264 triangles, 1,338,012-byte source GLB, 9.19 seconds at 20 steps and 128 octree resolution; the shared GLB post-processing path produced a 6,228,288-byte validated GLB and 512×512 preview.
- The deployed Edge Function Hunyuan gate was strengthened and verified: `hunyuan3d` remains unavailable unless the enable, legal-approval, territory-confirmation, and AUP-confirmation flags are all true.
- TRELLIS.2 remote inference reached the preview stage on 2026-09-11 using the same `chair.png` reference. GLB extraction was rejected by the anonymous ZeroGPU quota; a Hugging Face token or dedicated GPU deployment is still required for a complete artifact benchmark.
- The canonical TRELLIS.2 image was rebuilt and validated on 2026-09-11. Its 181-package BOM found NVIDIA non-commercial licenses for `nvdiffrast` and `nvdiffrec`, so commercial/public production activation remains disabled pending legal clearance or replacement dependencies.
- A local canonical-worker inference attempt downloaded the pinned TRELLIS.2 checkpoint but could not load the official gated DINOv3 and RMBG models without an approved Hugging Face token. The worker now fails fast with an actionable credential error instead of downloading the checkpoint and failing later.
- The deployed `ai-3d` Edge Function is version 14. Its provider gate suite and hosted FAL contract suite pass 13/13 tests; `trellis` remains disabled unless legal and dependency-review flags are explicitly enabled, while `fal-trellis2` requires its own explicit enable flag and server-side `FAL_KEY`. A live draft request reached FAL but was rejected with HTTP 403 before an artifact was created.
- The quick tunnel is a staging proof only and has no uptime guarantee. A durable production worker still requires a dedicated HTTPS Linux GPU endpoint and stable `AI_3D_WORKER_BASE_URL`/`AI_3D_WORKER_TOKEN` secrets.
- The complete Flutter suite passed 862 tests after the ComfyUI cancellation-order fix; `flutter analyze --no-pub`, `git diff --check`, and the TRELLIS.2 Compose configuration check also passed.
