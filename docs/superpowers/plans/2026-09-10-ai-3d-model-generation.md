# Rencana Implementasi: AI 3D Model Generation untuk Varian

## Tujuan

Menambahkan alur `text/image -> 3D model -> GLB -> canvas` ke AI Creative Engine
tanpa menanam model AI berat ke dalam binary Flutter. Viewer, node model 3D,
artifact store, Supabase Storage, dan persistence yang sudah ada tetap dipakai.

## Kondisi Awal

- `AICapability` belum memiliki capability `textTo3D` atau `imageTo3D`.
- `AIService` hanya merutekan image, chat, dan video; capability non-video tanpa
  API key masuk ke simulated job.
- `AICreativeEngineNotifier` hanya membuat image node atau video node setelah job
  selesai.
- `Model3DImportService` menerima `.glb`, memvalidasi header GLB, menyimpan artifact
  lokal/Web, dan dapat mengunggah bytes ke Supabase Storage.
- `Model3DPayload` sudah mendukung `modelPath`, `modelUrl`, dan
  `artifactReference`, sehingga hasil generasi dapat dipersistenkan sebagai node
  yang sama dengan model impor manual.
- ComfyUI bridge yang ada berfokus pada video dan auto-start lokal Windows; bridge
  dapat menjadi fondasi transport, tetapi kontrak 3D harus dipisahkan dari kontrak
  video.
- Supabase saat ini memiliki Edge Function `ai-video`, tetapi belum ada worker atau
  job endpoint khusus 3D.

## Status Eksekusi — 2026-09-11

- Kontrak domain, worker HTTP, Edge Function `ai-3d`, storage handoff, artifact
  import, AI panel, dan canvas `NodeType.model3d` sudah diimplementasikan.
- Jalur default TripoSR sudah dibuktikan dari job terautentikasi sampai GLB,
  preview, Supabase Storage, dan canvas Windows/Web.
- TRELLIS.2 image canonical, provider lock, provenance, dan Compose bundle sudah
  dibangun serta diuji health/auth/demo. Artifact inferensi resmi masih menunggu
  host Linux GPU dedicated dan akses gated model.
- Adapter hosted `fal-trellis2` dan gate server-side sudah dideploy; smoke test
  live ditolak provider dengan HTTP 403 sebelum request ID/artifact.
- Review teknis Hunyuan3D selesai dengan keputusan no-go production sampai
  territory, AUP, notices, dan persetujuan komersial diverifikasi.
- Security suite Deno lulus 13/13, full Flutter suite lulus 862 test, analyzer,
  Compose validation, Web build, dan Windows build lulus.

## Keputusan Arsitektur

1. **GPU berjalan di worker terpisah**
   - Flutter tidak memuat checkpoint 3D.
   - Worker dapat berjalan di GPU server, Docker/NVIDIA, atau proses lokal Windows.
   - Web client hanya memakai endpoint HTTPS; desktop lokal dapat memakai loopback
     bridge dengan token.

2. **Semua provider menghasilkan kontrak artifact yang sama**
   - Provider boleh mengeluarkan OBJ, PLY, GLB, atau folder tekstur secara internal.
   - Post-processing wajib menghasilkan satu self-contained `.glb` yang tervalidasi.
   - UI dan canvas tidak mengetahui detail provider.

3. **Provider adapter, bukan provider hard-coded**
   - `ThreeDGenerationProvider` mendefinisikan `create`, `poll`, `cancel`, dan
     `health`.
   - Implementasi pertama dapat memakai TripoSR, TRELLIS, atau Hunyuan3D.
   - Provider dipilih melalui backend config/job metadata, bukan dari prompt UI.

4. **Blender dipakai sebagai post-processor eksternal**
   - Blender menjalankan script headless untuk normalisasi skala/origin, perbaikan
     mesh dasar, optimasi ukuran, validasi material, dan ekspor GLB.
   - Jangan meng-embed Blender ke Flutter. Jalankan sebagai proses worker terpisah
     agar ukuran aplikasi, crash boundary, dan deployment tetap terkendali.

5. **Artifact 3D tidak dikirim sebagai base64 di metadata canvas**
   - Job menyimpan status dan reference.
   - GLB disimpan di bucket private atau path asset terkontrol.
   - Canvas menyimpan hanya metadata durable; URL/path runtime dihidrasi ulang,
     mengikuti pola `Model3DPayload` dan artifact store saat ini.

## Kandidat Open Source / Source-Available

| Komponen | Peran | Kesesuaian | Catatan |
| --- | --- | --- | --- |
| TripoSR | Image-to-3D generator | Pilihan MVP paling ringan | Cocok untuk alur existing `text-to-image -> image-to-3D`; repository menyatakan MIT. |
| Microsoft TRELLIS | Text/image-to-3D generator | Pilihan utama untuk server GPU | Mendukung text/image-to-3D; repository menyatakan kode utama MIT, membutuhkan GPU besar, dan deployment resmi terutama diuji di Linux. |
| Hunyuan3D-2/2.1 | Text/image-to-3D generator | Kandidat kualitas tinggi dan local Windows | Mendukung API server serta mode shape/texture; lisensinya adalah community license dengan batasan, jadi bukan default untuk produk komersial sebelum review legal. |
| Stable Fast 3D | Image-to-3D generator | Alternatif cepat dengan output GLB | Memiliki integrasi ComfyUI dan kebutuhan VRAM relatif rendah, tetapi lisensi modelnya perlu review komersial. |
| ComfyUI | Workflow/inference orchestrator | Fondasi integrasi paling dekat dengan proyek | Proyek sudah memiliki bridge ComfyUI untuk video; gunakan API/workflow yang dipin versinya, bukan menjadikan UI ComfyUI sebagai dependency Flutter. |
| Blender | 3D modeler, cleanup, conversion, export | Wajib sebagai tahap post-processing | Open source GPL; gunakan proses headless terpisah dan dokumentasikan kewajiban lisensi/redistribusi. |

### Rekomendasi

- **MVP permissive:** existing text-to-image menghasilkan reference image, lalu
  TripoSR mengubahnya menjadi mesh dan Blender mengekspor GLB.
- **Target kualitas text-to-3D:** tambahkan provider TRELLIS pada worker GPU Linux.
- **Target local Windows/high quality:** evaluasi Hunyuan3D setelah validasi GPU,
  waktu inferensi, dan persyaratan lisensinya.
- **Orkestrasi:** gunakan adapter HTTP sendiri atau ComfyUI API; jangan membuat
  Flutter bergantung langsung pada node custom pihak ketiga.

## Kontrak Data yang Diusulkan

### Capability

Tambahkan capability terpisah:

- `textTo3D`: prompt menghasilkan model 3D.
- `imageTo3D`: gambar/reference node menghasilkan model 3D.
- `model3DRemesh` atau `model3DOptimize`: tahap lanjutan setelah MVP, bukan bagian
  release pertama.

### Parameter

Pertahankan `AICreativeParams` yang ada, lalu tambahkan field 3D:

- `threeDProvider` atau provider hint yang sudah divalidasi allow-list.
- `meshQuality`: `draft`, `balanced`, `high`.
- `textureMode`: `none`, `vertexColor`, `pbr`.
- `targetFormat`: release pertama selalu `glb`.
- `sourceModelReference` untuk image/model input yang sudah berada di storage.
- `triangleBudget`, `seed`, dan `generatePreview` dengan batas server.

Jangan menerima URL provider mentah dari client. Backend memetakan provider hint ke
konfigurasi server.

### Artifact

Lebih baik menambah model hasil generasi typed daripada terus menambah field video:

- `kind`: `image`, `video`, `model3d`.
- `url` atau signed URL sementara.
- `reference` durable.
- `localPath` runtime-only.
- `fileName`, `mimeType`, `byteLength`.
- `previewUrl` opsional.

Tambahkan kompatibilitas `fromJson` untuk job lama agar perubahan tidak merusak
history atau state tersimpan.

## Tahap Implementasi

### Phase 0: Spike dan keputusan provider

**Description:** Validasi satu prompt dan satu reference image pada mesin target,
ukur waktu/VRAM, cek output, serta pastikan lisensi cocok dengan distribusi Varian.

**Acceptance criteria:**

- [ ] Satu provider menghasilkan asset 3D yang dapat dibuka Blender.
- [ ] Worker dapat mengeluarkan `.glb` self-contained maksimal ukuran yang disepakati.
- [ ] Hasil dapat dibuka oleh `three_js` yang sudah dipakai aplikasi.
- [ ] Lisensi code, checkpoint, custom node, dan dependency dicatat.

**Verification:**

- [ ] Uji prompt-only dan image-guided.
- [ ] Catat VRAM puncak, waktu queue/inference/post-process, ukuran GLB, dan jumlah triangle.
- [ ] Buka hasil di Blender dan canvas desktop.

**Dependencies:** None

**Files likely touched:**

- `docs/superpowers/plans/2026-09-10-ai-3d-model-generation.md`
- `tool/ai_3d_worker/README.md`

**Estimated scope:** Medium

### Phase 1: Domain contract dan provider abstraction

**Description:** Tambahkan capability, parameter, artifact typed, dan interface
provider tanpa mengubah UI generation lama.

**Acceptance criteria:**

- [ ] Job image/video lama tetap dapat deserialize.
- [ ] `textTo3D` dan `imageTo3D` masuk kategori generation 3D yang konsisten.
- [ ] Payload menolak provider, quality, format, dan budget di luar allow-list.
- [ ] Tidak ada secret atau local path yang masuk JSON durable.

**Verification:**

- [ ] Unit test enum/category/serialization.
- [ ] Test validation parameter, negative prompt, seed, source reference, dan size budget.

**Dependencies:** Phase 0

**Files likely touched:**

- `lib/domain/models/ai_job.dart`
- `lib/domain/models/model3d_payload.dart`
- `lib/features/model3d/data/model3d_import_service.dart`
- `lib/features/ai/data/three_d_generation_provider.dart`
- `test/features/ai/ai_job_test.dart`
- `test/features/model3d/model3d_import_service_test.dart`

**Estimated scope:** Medium

### Phase 2: Backend job gateway dan storage

**Description:** Buat endpoint async yang mengautentikasi user/project, membuat job,
memanggil worker, memvalidasi callback/poll result, dan menyimpan artifact secara aman.

**Acceptance criteria:**

- [ ] Client tidak memegang provider secret atau service-role key.
- [ ] `create`, `poll`, `cancel`, `retry`, dan `health` memiliki kontrak jelas.
- [ ] Job idempotent; retry tidak menggandakan artifact atau biaya tanpa sengaja.
- [ ] Hanya anggota project yang berhak dapat membaca hasil.
- [ ] GLB hanya diterima jika MIME, size, header, dan hasil normalisasi valid.

**Verification:**

- [ ] Edge Function/integration test untuk auth, RLS, malformed response, timeout, dan retry.
- [ ] Test signed URL expiry, path traversal, SSRF source image, oversized output, dan callback forgery.

**Dependencies:** Phase 1

**Files likely touched:**

- `supabase/functions/ai-3d/index.ts`
- `supabase/functions/ai-3d/helpers.ts`
- `supabase/migrations/<timestamp>_create_ai_3d_jobs.sql`
- `supabase/migrations/<timestamp>_create_ai_3d_storage_policies.sql`
- `test/supabase/ai_3d_jobs_test.dart`

**Estimated scope:** Large; split into job contract and storage/RLS if needed.

### Phase 3: GPU worker, ComfyUI adapter, dan Blender post-processing

**Description:** Implementasikan worker provider-neutral yang menjalankan generator
3D, melakukan cleanup, dan mengeluarkan GLB tunggal yang dapat dipakai canvas.

**Acceptance criteria:**

- [ ] Worker menyediakan status `queued`, `processing`, `completed`, `failed`, `canceled`.
- [ ] Provider adapter tidak mengekspos custom node internals ke client.
- [ ] Blender script menerapkan scale/origin, basic mesh validation, triangle budget,
      material/texture embedding, dan GLB export.
- [ ] Output invalid gagal sebelum upload.
- [ ] Local bridge hanya listen di loopback dan memakai token.

**Verification:**

- [ ] Golden test dari fixture output provider ke GLB final.
- [ ] Test Blender headless dengan fixture kecil.
- [ ] Health check, worker restart, cancellation, timeout, dan cleanup temporary files.

**Dependencies:** Phase 0 and Phase 2

**Files likely touched:**

- `tool/ai_3d_worker/`
- `tool/comfyui_3d_bridge/`
- `tool/blender/glb_postprocess.py`
- `lib/features/ai/data/comfy_ui_bridge_manager.dart`
- `lib/features/ai/data/comfy_ui_bridge_manager_io.dart`
- `lib/data/remote/backend_config.dart`

**Estimated scope:** Large; keep provider-specific adapters in separate files.

### Phase 4: AI panel dan canvas insertion

**Description:** Tambahkan operasi 3D ke AI Creative Engine dan masukkan hasilnya
sebagai `NodeType.model3d` memakai import/artifact flow yang sudah ada.

**Acceptance criteria:**

- [ ] User dapat memilih `Text -> 3D` atau `Image -> 3D`.
- [ ] Image source berasal dari selected image node atau file picker, tidak dari local
      path yang tidak dapat diakses worker.
- [ ] Progress, retry, cancel, error, dan no-GPU state tampil jelas.
- [ ] Job selesai membuat `Model3DPayload` dengan `artifactReference` durable.
- [ ] Node hasil dapat dipreview, disimpan, dibuka ulang, di-share, dan di-export.
- [ ] Job 3D tidak pernah membuat image node fallback secara diam-diam.

**Verification:**

- [ ] Widget tests untuk capability list, parameter validation, progress, retry, dan error.
- [ ] Integration test fake worker -> poll -> import -> add model3D node.
- [ ] Manual test Windows native dan Web Chrome.

**Dependencies:** Phase 1, Phase 2, and Phase 3

**Files likely touched:**

- `lib/features/ai/presentation/ai_panel.dart`
- `lib/features/ai/state/ai_provider.dart`
- `lib/features/ai/data/ai_service.dart`
- `lib/features/model3d/data/model3d_import_service.dart`
- `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart`
- `test/features/ai/ai_3d_generation_test.dart`
- `test/features/model3d/model3d_node_widget_test.dart`

**Estimated scope:** Large

### Phase 5: Collaboration, quotas, and production hardening

**Description:** Pastikan artifact 3D aman untuk project bersama, biaya terkontrol,
dan provider dapat diganti tanpa perubahan dokumen canvas.

**Acceptance criteria:**

- [ ] Semua collaborator yang berhak dapat menghidrasi GLB dengan reference yang sama.
- [ ] Artifact orphan dapat dideteksi dan dibersihkan.
- [ ] Rate limit, max concurrency, max prompt/source/output, dan per-project quota aktif.
- [ ] Provider/model/checkpoint version tersimpan sebagai provenance.
- [ ] Attribution dan license notices ikut dalam build/deployment yang relevan.

**Verification:**

- [ ] Test dua client membaca node 3D yang sama.
- [ ] Test offline/reconnect, expired signed URL, worker failure, dan artifact retry.
- [ ] `flutter analyze --no-pub`, focused tests, Web build, Windows build, dan worker smoke test.

**Dependencies:** Phase 4

**Files likely touched:**

- `lib/data/remote/supabase_service.dart`
- `lib/data/local/local_storage_service.dart`
- `supabase/migrations/`
- `README.md`
- `docs/ai-3d-generation.md`
- `test/features/model3d/`
- `test/supabase/`

**Estimated scope:** Medium/Large

## Definition of Done

- User memasukkan prompt, memilih `Text -> 3D`, dan menerima model pada canvas.
- User memilih image/reference, menjalankan `Image -> 3D`, dan menerima model pada canvas.
- Model tersimpan sebagai GLB self-contained, dapat dipreview oleh viewer yang ada,
  dapat dibuka ulang dari project, dan dapat dipakai collaborator.
- UI membedakan `queued`, `processing`, `completed`, `failed`, `canceled`, dan
  `simulated`; hasil 3D tidak boleh berstatus simulated.
- Provider dapat diganti di worker tanpa migrasi format canvas.
- Tidak ada credential provider di Flutter client atau metadata canvas.
- Focused tests, analyzer, Web build, Windows build, dan worker smoke test lulus.

## Risiko dan Mitigasi

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| VRAM/latency generator terlalu tinggi | High | Mulai dari image-to-3D draft, batasi concurrency, gunakan queue, dan sediakan preview/progress. |
| Output mesh rusak atau terlalu besar | High | Blender post-process, triangle budget, GLB validation, dan reject-before-upload. |
| Model hanya bagus untuk reference image tertentu | Medium | Simpan alur `text-to-image -> image-to-3D`, tambahkan prompt guidance dan reference controls. |
| Lisensi checkpoint/custom node tidak cocok | High | Simpan provenance, audit setiap dependency, dan jadikan provider Hunyuan/Stable Fast 3D opt-in setelah legal review. |
| Web tidak dapat mengakses GPU lokal | High | Web memakai remote worker HTTPS; local loopback hanya untuk desktop dengan capability check. |
| URL/image source menjadi SSRF atau data exfiltration | High | Upload source ke controlled storage, allow-list scheme/host, bounded download, dan jangan fetch arbitrary worker URLs. |
| Worker gagal setelah job dibuat | Medium | Idempotency key, retry state, cleanup, dan pesan error yang dapat ditindaklanjuti. |

## Open Questions

- Target pertama hanya Windows desktop, atau Windows + Web harus dirilis bersamaan?
- Apakah produk akan didistribusikan komersial? Jawaban ini menentukan apakah
  Hunyuan3D/Stable Fast 3D boleh menjadi provider default.
- Apakah server GPU akan dikelola sendiri, atau memakai provider inference eksternal?
- Berapa batas output yang diterima viewer: ukuran file, triangle count, material,
  dan texture resolution?
- Apakah MVP cukup `text-to-image -> image-to-3D`, atau `text-to-3D` langsung wajib?
