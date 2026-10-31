# Varian AI 3D Worker

Worker HTTP lokal untuk alur `text/image -> 3D -> GLB -> canvas`. Flutter hanya
mengirim job dan mengimpor artifact GLB; checkpoint AI tidak masuk ke binary
Flutter.

## Mode provider

- `triposr`: provider MVP image-to-3D. Cocok untuk `imageTo3D` dan untuk
  `textTo3D` setelah Varian membuat reference image melalui text-to-image yang
  sudah dikonfigurasi.
- `trellis`: compatibility adapter untuk stack TRELLIS; gunakan revision
  upstream yang dipin pada worker CUDA Linux.
- `hunyuan3d`: provider image-to-3D opsional dengan environment resmi Hunyuan3D.
- `demo`: hanya smoke test. Provider ini sengaja tidak ditampilkan sebagai pilihan
  produksi di Flutter dan menghasilkan cube prosedural.

Semua provider wajib berakhir pada satu file `.glb` self-contained. Jika Blender
tersedia di `PATH` atau `BLENDER_BIN`, worker menormalkan skala/origin, mengurangi
triangle sesuai budget, dan mengekspor ulang GLB.

## Menjalankan smoke test

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r tool\ai_3d_worker\requirements.lock
$env:AI_3D_DEFAULT_PROVIDER = "demo"
python -m uvicorn tool.ai_3d_worker.app:app --host 127.0.0.1 --port 20130 --no-access-log
```

Jalankan dari root repository dan biarkan proses server tetap berjalan. Pada terminal PowerShell kedua, dari root repository, jalankan smoke test di bawah. Mode demo tidak memerlukan kredensial: `VARIAN_3D_WORKER_TOKEN` tidak disetel secara default.

Untuk menjalankan suite unit dan coverage lokal dari root repository:

```powershell
python -m coverage run --source=tool.ai_3d_worker -m unittest tool.ai_3d_worker.test_worker
python -m coverage report --fail-under=60
```

Dependensi runtime dan test dikunci pada `requirements.lock`. Setelah mengubah dependensi, perbarui lock secara sengaja dengan `uv pip compile tool/ai_3d_worker/requirements-test.in --python-version 3.12 --output-file tool/ai_3d_worker/requirements.lock`.

Dokumen mesin [OpenAPI](openapi.json) dihasilkan dari route FastAPI. Perbarui dari root repository dengan `python -m tool.ai_3d_worker.export_openapi`; CI memverifikasinya melalui `python -m tool.ai_3d_worker.export_openapi --check`.

Endpoint worker:

- `GET /v1/health`
- `POST /v1/3d/jobs`
- `GET /v1/3d/jobs/{jobId}`
- `POST /v1/3d/jobs/{jobId}/cancel`
- artifact internal: `GET /v1/3d/artifacts/{jobId}.glb?token=...`

Worker menambahkan `X-Request-ID` pada response dan meneruskan ID tersebut ke log
siklus job. Event log JSON mencatat nama event, timestamp UTC, request ID, method,
route template, status, durasi, provider, dan kode error. Prompt, job ID, bearer
token, URL artifact, serta token artifact tidak dicatat. Launcher yang disertakan
menonaktifkan access log Uvicorn agar query token artifact tidak dicatat. Header
`X-Request-ID` diekspos melalui CORS.

Contoh job smoke test:

```powershell
$body = @{ jobId = "smoke-1"; projectId = "local"; capability = "textTo3D"; prompt = "a blue chair"; provider = "demo"; triangleBudget = 100000; meshQuality = "draft"; textureMode = "pbr"; targetFormat = "glb" } | ConvertTo-Json
$job = Invoke-RestMethod -Uri http://127.0.0.1:20130/v1/3d/jobs -Method Post -ContentType application/json -Body $body
$jobId = $job.jobId
do {
    Start-Sleep -Seconds 1
    $job = Invoke-RestMethod -Uri "http://127.0.0.1:20130/v1/3d/jobs/$jobId"
} while ($job.status -in @("queued", "processing"))
if ($job.status -ne "completed") { throw "Worker job ended with status $($job.status): $($job.message)" }
Invoke-WebRequest -Uri $job.artifact.url -OutFile "$env:TEMP\smoke-1.glb"
Get-Item "$env:TEMP\smoke-1.glb"
Invoke-RestMethod -Uri http://127.0.0.1:20130/v1/health
```

## Provider AI

Install provider dependencies in environment terpisah sesuai dokumentasi resmi
masing-masing project. Worker melakukan lazy import sehingga smoke test tidak
memerlukan torch atau checkpoint besar.

Untuk TripoSR, set `TRIPOSR_MODEL`, `TRIPOSR_DEVICE`, dan opsional
`TRIPOSR_CHUNK_SIZE`. Untuk TRELLIS/TRELLIS.2, set root, model, dan
`TRELLIS2_MODEL_REVISION` sesuai pin pada `provider-lock.json`; upstream
TRELLIS.2 memerlukan Linux dan GPU NVIDIA dengan memori besar. Deployment
reproducible tersedia di `tool/ai_3d_worker/deployment/trellis2`.

`TRELLIS2_PIPELINE_TYPE` menerima `512`, `1024`, `1024_cascade`, atau
`1536_cascade`. Adapter hanya memuat keluarga model yang dibutuhkan oleh mode
tersebut; default quality `draft` memakai `512`, `balanced` memakai
`1024_cascade`, dan `high` memakai `1536_cascade`. Dtype checkpoint bawaan
dipertahankan, termasuk checkpoint mixed-precision. Untuk Hunyuan3D, set
`HUNYUAN3D_ROOT` dan `HUNYUAN3D_MODEL` setelah review license dan dependency.

Untuk ComfyUI, jalankan ComfyUI dengan custom node 3D yang menghasilkan GLB,
export workflow dalam format API, lalu set:

```powershell
$env:COMFYUI_BASE_URL = "http://127.0.0.1:8188"
$env:COMFYUI_WORKFLOW_FILE = "C:\ai-models\comfyui\varian-3d-api.json"
$env:COMFYUI_OUTPUT_NODE_ID = "42"
$env:COMFYUI_POLL_SECONDS = "2"
```

Workflow dapat memakai token `{{prompt}}`, `{{negativePrompt}}`, `{{sourceImage}}`, `{{seed}}`,
`{{triangleBudget}}`, `{{capability}}`, `{{meshQuality}}`, dan `{{textureMode}}`.
`{{sourceImage}}` diisi setelah worker mengunggah gambar ke `/upload/image`.
Workflow harus mengembalikan file `.glb` pada output node yang dipilih; worker
menolak output lain sebelum pipeline Blender.

## Konfigurasi keamanan

- `VARIAN_3D_WORKER_TOKEN`: bearer token opsional; Flutter mengirimnya sebagai
  `Authorization: Bearer ...`.
- `AI_3D_PUBLIC_BASE_URL`: URL publik worker jika berada di reverse proxy.
- `AI_3D_CORS_ORIGINS`: daftar origin dipisah koma; default `*` cocok untuk local
  smoke test, bukan deployment publik.
- `AI_3D_ALLOW_SOURCE_URLS`: aktif secara default agar Supabase image URL dapat
  dipakai; validasi DNS menolak alamat private/reserved.
- `AI_3D_ALLOW_LOOPBACK_SOURCE_URLS`: nonaktif secara default untuk mencegah akses ke
  layanan loopback. Aktifkan dengan nilai `true` hanya untuk local development yang
  memang perlu mengambil gambar dari layanan di `localhost` atau `127.0.0.1`.
- `AI_3D_WORK_DIR`: direktori artifact job.
- `BLENDER_BIN`: path Blender headless. Tanpa Blender, worker menolak output yang
  melewati triangle budget daripada mengabaikan batas tersebut.

Untuk deployment publik, gunakan Edge Function sebagai proxy terautentikasi,
storage private, HTTPS, origin allow-list, rate limit, dan worker token.
