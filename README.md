# varian

A Flutter canvas application.

## Local development and QA

Read [`AGENTS.md`](AGENTS.md) for the project map, development conventions, safety boundaries, and focused validation commands. From a fresh checkout with Flutter installed, install dependencies and launch the interactive Web app:

```powershell
.\tool\run_flutter_web.ps1
```

The script installs dependencies and launches the Web app in Chrome. This uses the app's existing Supabase Auth flow and checked-in public client configuration. Sign in with a dedicated test account on a disposable Supabase project for authenticated cloud workflows; do not use production accounts or credentials in automated tests. The Flutter widget and service tests use local fakes/mocked HTTP clients and do not require a Supabase login. Run the app boot and interactive auth-screen smoke tests with:

```sh
flutter test --no-pub test/widget_test.dart test/features/auth/auth_screen_test.dart
```

The auth-screen tests use an overridden null Supabase client and exercise a built-in template selection; they do not bypass authentication or make a remote login request.

The AI 3D worker has an isolated end-to-end API smoke test. It exercises the health/job/artifact flow with an in-process ASGI client, temporary files, and the deterministic `demo` provider, without Supabase, external AI services, or credentials:

```sh
python -m pip install -r tool/ai_3d_worker/requirements.txt
python -m unittest tool.ai_3d_worker.test_worker.WorkerTest.test_job_lifecycle_returns_a_bounded_artifact
```

CI runs Dart formatting, `flutter analyze`, the Flutter suite with coverage output, the worker suite, and Gitleaks secret scanning. `flutter test --list-tests` is unsupported by the Flutter CLI used here; use actual test commands instead.

## Interface appearance

Application chrome uses the shared Material 3 tokens and responsive UI primitives. Canvas, chart, media, and 3D authored content keeps its own colors, separate from the surrounding interface.

The shared chrome standard is an ongoing migration, not a claim that every
feature surface has been audited. Feature dialogs and editor panels are being
aligned with `AppTokens`, `AppSpacing`, `AppResponsive`, and `Ui*` primitives;
authored canvas, drawing, media, chart, and model content retains its own visual
language. Validation for the current migration slice is recorded in
`docs/creative-studio-migration-2026-09-14.md`.

## Capture Inbox

Capture Inbox keeps text, links, images, audio, and files in local device storage. **Add to canvas** copies a capture into a selected active local project; collaboration rooms and read-only sessions are rejected. The Inbox item remains independent, so deleting or undoing the canvas node does not remove the capture, and purging a capture removes only its local Inbox record and file—not any copied canvas artifact or cloud data.

## GLB 3D model nodes

The canvas accepts `.glb` files only. Use **Media & Cards → 3D Model (GLB)** to upload a model, or drag one from the operating system file manager onto the canvas. Files are validated before import and limited to 100 MB. Imported bytes are stored locally first, while Supabase storage receives an optional copy when cloud sync is configured. Canvas JSON stores model metadata and durable artifact references, not large runtime byte buffers.

Model nodes show the real GLB preview as soon as they are visible. The selected node enables orbit, zoom, pan, auto-rotate, and animation controls; unselected nodes use a lighter one-shot renderer and remain selectable without moving the canvas node. Drag the selected model header to move the canvas node. Inside a selected viewer, left-drag orbits, middle-drag and wheel zoom, right-drag or `Shift + drag` pans, and the compact control dock provides zoom, pan, four-way orbit, reset, and auto-rotate actions. The selection box follows the full GLB card, including its header and footer. If the renderer cannot initialize, including the current Linux `three_js`/Angle compatibility limitation, the model remains as a usable fallback card with retry and metadata controls.

The model inspector also provides Sketchfab-style wireframe colors, single/double-sided rendering, `3D`, `3D + 2D`, and `2D` UV views, final/no-post-processing render modes, material-channel previews, matcap/wireframe/vertex-normal geometry overlays, and a UV checker. `finalRender` uses an app-owned studio light rig and ACES tone mapping to keep metallic and textured materials readable; it does not promise pixel-identical Sketchfab output because Sketchfab supplies its own HDR environment and post-processing. Render, material, geometry, wireframe, and UV display modes share one global selection, so choosing one automatically clears the others; viewport, background, sidedness, and auto-rotate remain independent. `Transparent background` keeps the viewer RGBA and removes the card fill so the model can sit directly on the canvas; Windows uses the ANGLE D3D surface-producer path to keep the renderer and Flutter on a shared surface without incomplete FBO attachments, and preview/overlay colors follow the active light or dark canvas tokens. These display choices are persisted with the canvas node; texture-backed channels use the GLB's actual maps and scalar channels show an explicit fallback when the asset has no map. ANGLE previews disable texture mipmap generation and transmission passes when necessary to avoid unsupported framebuffer formats.

## AI Creative Engine on Web

The Web build sends AI requests through the browser. Configure an HTTPS OpenAI-compatible endpoint or a same-origin `/v1` proxy. `Image Generation API Mode` controls text-to-image requests; `Image Editing API Route` independently controls image-to-image and sketch/reference edits. Edit `Auto` tries `/images/edits`, `/responses`, then `/chat/completions`, and advances only after an explicit unsupported-route/model response. An HTTP 2xx response without an image ends the attempt to avoid duplicate billable requests. The edit route selector can pin one route. Configure `Image Model` independently from the chat model; the image model ID is passed through as entered, including custom provider model names. Model discovery is only a `/models` name heuristic, not an image-capability check. `Test AI API` checks connectivity, not image generation/edit capability. OpenAI-compatible protocol labels do not guarantee route/model support; confirm the provider's documented request and response contract. The server must support `OPTIONS` and `POST` for:

- `/v1/images/generations`
- `/v1/images/edits` (multipart image edits)
- `/v1/responses` with the `image_generation` tool (image edits and configured generation mode)
- `/v1/chat/completions` (chat-backed image generation/editing and assistant text)

On Web, remote source images and URL-based generation results use the Supabase `link-preview` asset proxy when Supabase is configured. Deploy that function and allow the app origin through `ALLOWED_ORIGINS`; without the proxy, the image host must permit browser CORS. Desktop downloads remote images directly after destination validation.

The AI panel uses one prompt composer. The plus menu selects image creation, image editing, sketch/reference-to-image, image-to-video, 3D, or canvas questions; it also supports image file attachments and the selected canvas image. Uploaded PNG/JPEG/WebP files are signature-checked, limited to 20 MB by default, kept in transient UI memory, and take precedence over a selected canvas image until removed. Choosing **Use selected canvas image** in the plus menu clears the upload; image-edit submissions without either source are blocked locally. Text-to-image and text-to-3D need no image source; video currently requires one.

Completed image, video, and 3D outputs are placed directly on the canvas using the selected `OUTPUT SEMANTICS` mode (`Insert as new node` or `Replace selected source`), with no insertion confirmation in the AI panel. If no compatible source is selected, or it disappears while generation is running, `Replace` falls back to insertion. Read-only collaboration sessions cannot open the AI panel or apply canvas mutations. File attachments are transient and are not linked as canvas variants; canvas image inputs retain their source link and placement behavior.

Image-to-Image, Sketch-to-Image, Reference-to-Image, and composition edits send the selected source image with the prompt through the route chosen by `Image Editing API Route`. `Auto` tries `/v1/images/edits`, `/v1/responses` with an image-generation edit tool, and `/v1/chat/completions`, but only retries after explicit route/model rejection. A successful text-only response or an unrecognized image response shape is reported as a failure and is not retried; choose a documented image-output route/model or check its response contract. Failures include sanitized route, model, HTTP status, content type, and response shape, never the provider's raw body or image bytes. Operation-specific intent and selected material, lighting, style, or entourage settings are included in the prompt. These request shapes do not guarantee that every OpenAI-compatible provider supports the operation or produces the requested result. Video requires a configured compatible image-to-video provider; 3D uses its configured worker/provider. Tests use mock endpoints and validate client behavior only; live provider and platform verification is still required.

Dedicated upscaling, denoising, sharpening, restoration, and detail enhancement are not implemented and are hidden from the panel. Canvas Assistant exposes only text questions about the canvas or selection through `/v1/chat/completions`; it does not propose or apply canvas actions. Autonomous tools, agent generation/edit/layout, and prompt-to-diagram have no provider contract and fail without sending a request. The video provider currently implements `Image → Video` only; other video operations are unsupported.
For the AI endpoint, allow the app origin, `OPTIONS` and `POST`, and the headers `Authorization`, `Content-Type`, and `Accept`. Do not use `Access-Control-Allow-Origin: *` for a production credentialed setup. The `link-preview` asset proxy must also allow the app origin; without it, source and result image hosts must permit browser CORS.

### Link Card preview on Web

The Web build uses the anonymous Supabase Edge Function at `supabase/functions/link-preview` to avoid third-party CORS restrictions. Desktop keeps the direct network path. The function supports HTML pages, redirects, direct images, favicons, and `og:image` assets.

Deploy after linking the Supabase project:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --linked --yes
supabase functions deploy link-preview --use-api
```

Run `dart run tool/media_codec_probe.dart` to check the configured or bundled
native video encoder. Set `VARIAN_VIDEO_ENCODER` to an approved encoder path
when the target does not expose `ffmpeg` on `PATH`.

The database migrations create `projects`, `canvas_snapshots`, `comments`, collaboration state, and immutable `published_snapshots`. Cloud autosave and publishing require an authenticated project owner. Anonymous viewers use only the token-hashed `read_canvas_share` RPC; direct table access remains restricted by RLS.

Publishing a snapshot stores the exact document version instead of exposing the live canvas. Password-protected snapshots receive a challenge in the share route, disabled downloads hide the export surface, and private publishing revokes active viewer links. When `Allow embed` is enabled, the dialog provides an embed URL using `?embed=1`; the route rejects that mode for snapshots that do not allow embedding.

The collaboration assets migration creates the public `assets` Storage bucket and project-scoped policies used by AI Creative Engine image nodes. Ensure the `supabase db push --linked --yes` step above has been run before testing cross-client AI output.

Set the function secret `ALLOWED_ORIGINS` to a comma-separated list of allowed Web origins, for example `https://app.example.com,http://localhost:3000`. Leave it unset only for local development; an unset value allows all origins. The function rejects local/private destinations, limits redirects to 3, limits upstream responses to 2 MB, times out upstream requests after 8 seconds, and rate-limits each client bucket to 30 requests per minute.

`http://localhost:20128` refers to the computer running the browser, not the computer hosting the desktop application. Use localhost only for local development with the AI server running on the same machine and configured for CORS. If the Web app is served over HTTPS, an HTTP remote endpoint can be blocked as mixed content; use HTTPS or a same-origin proxy.

Provider API keys are visible to browser users when entered directly in the Web client. For production, use an authenticated same-origin server proxy that keeps provider keys server-side, restricts upstreams and origins, limits request size/rate, and redacts logs.

### Asset Library Openverse proxy

Asset Library uses the public Openverse API by default. For production Web builds,
its optional `supabase/functions/asset-library` proxy keeps the upstream route
fixed to `api.openverse.org/v1/images` or `/v1/audio`; it validates query bounds,
requires an authenticated-user Supabase JWT (the public anon role is rejected),
rejects unsafe redirects, caps responses at 2 MB, and rate-limits requests. Deploy it with the database migrations and configure the
function secret `ALLOWED_ORIGINS` with exact application origins:

```bash
supabase functions deploy asset-library --use-api
supabase secrets set ALLOWED_ORIGINS=https://app.example.com
```

Enable the proxy at build time only after deployment:

```bash
flutter build web --dart-define=ASSET_LIBRARY_PROVIDER_PROXY=true
```

An explicit HTTPS proxy URL can be supplied with
`ASSET_LIBRARY_PROVIDER_URL`. No Openverse or provider secret belongs in the
Flutter bundle; attribution, creator, license, and source URLs remain part of
the catalog record. The package selection, license allow-list, provenance
requirements, and portable-package loss report are documented in
[`docs/asset-library-export.md`](docs/asset-library-export.md).

## AI text/image-to-3D generation

The canvas now supports `Text → 3D` and `Image → 3D`. Flutter does not load model
checkpoints. It submits an asynchronous job to `tool/ai_3d_worker`, polls the
status, validates the returned GLB, stores a durable artifact reference, and
adds a `Model3D` node to the canvas. Supabase Edge Function deployment is the
recommended production path; direct local-worker mode is useful for development.

### Open-source stack decision

- **TripoSR** is the MVP provider for single-image reconstruction. Its upstream
  implementation is MIT-licensed and targets a roughly 6 GB VRAM class setup.
  `Text → 3D` uses the configured text-to-image endpoint to create a reference
  image before running TripoSR.
- **TRELLIS.2** is the current high-fidelity image-to-3D candidate. Its
  upstream code is MIT-licensed, Linux-tested, and requires at least 24 GB of
  NVIDIA GPU memory, so keep it on a remote Linux GPU worker. The bundled
  `trellis` adapter supports the current `Trellis2ImageTo3DPipeline` and
  `o_voxel.postprocess.to_glb` API when `TRELLIS2_ROOT` is set to a pinned
  checkout. The provider remains image-only and `Text → 3D` uses the
  reference-image stage. Keep this provider on a remote Linux GPU worker.
- **Hosted FAL TRELLIS.2** is an optional `fal-trellis2` fallback when a
  dedicated Linux GPU is unavailable. It keeps `FAL_KEY` server-side, validates
  the returned GLB before Storage handoff, and is disabled by default because
  hosted inference is metered. It supports image-to-3D; text-to-3D still needs
  a reference-image stage.
- **Hunyuan3D-2.1** is an optional image-to-3D provider in this adapter. The
  official Tencent Hunyuan 3D 2.1 Community License is expressly limited to
  the worldwide territory excluding the European Union, United Kingdom, and
  South Korea. It also requires territory-limited use, agreement and notice
  handling for distribution, prominent notices for modified files, and
  compliance with its Acceptable Use Policy. The legal review decision is to
  keep this provider out of production until deployment geography, model
  weights, dependencies, and counsel approval are recorded.
- **Blender** is the headless post-processing tool: normalize scale/origin,
  enforce the triangle budget, and export a self-contained GLB. It is not the
  generator itself.
- **ComfyUI** can be added as an optional orchestration layer for versioned
  workflows. It is not required by the Flutter client or the direct worker API.

Official projects: [TripoSR](https://github.com/VAST-AI-Research/TripoSR),
[TRELLIS.2](https://github.com/microsoft/TRELLIS.2),
[Hunyuan3D-2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1),
[Blender](https://www.blender.org/about/license/), and
[ComfyUI](https://github.com/Comfy-Org/ComfyUI).

### Local worker

Run the smoke-test provider from the repository root:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r tool\ai_3d_worker\requirements.txt
$env:AI_3D_DEFAULT_PROVIDER = "demo"
python -m uvicorn tool.ai_3d_worker.app:app --host 127.0.0.1 --port 20130
```

The `demo` provider only produces a deterministic cube for transport and GLB
tests; it is not exposed as a production provider in the Flutter UI. For a
real local setup, install the optional TripoSR stack separately, then configure
the pinned checkout and checkpoint before selecting `triposr` in Backend
Settings:

```powershell
$env:TRIPOSR_ROOT = "C:\ai-models\TripoSR"
$env:TRIPOSR_MODEL = "C:\ai-models\TripoSR-checkpoint"
$env:TRIPOSR_CONFIG = "config.yaml"
$env:TRIPOSR_WEIGHTS = "model.ckpt"
$env:TRIPOSR_DEVICE = "cuda"
$env:TRIPOSR_CHUNK_SIZE = "4096"
$env:BLENDER_BIN = "C:\Program Files\Blender Foundation\Blender\blender.exe"
.\tool\ai_3d_worker\start_worker.ps1 -Provider triposr
```

The adapter expects TripoSR revision
`107cefdc244c39106fa830359024f6a2f1c78871` and the upstream checkpoint files
`config.yaml` and `model.ckpt`. `TRIPOSR_ROOT` is required when the checkout is
not already on `PYTHONPATH`. The worker pins NumPy below 2 because the selected
TripoSR/trimesh combination uses the removed `ndarray.ptp` API. If the machine
has no CUDA Toolkit, a CPU-only `torchmcubes` build still works; neural
inference remains on the GPU and marching-cubes extraction falls back to CPU.

`imageTo3D` is fully local with this setup. `textTo3D` first asks the configured
OpenAI-compatible image endpoint for a centered reference image, then sends
that image through TripoSR; configure an image-capable AI endpoint for that
mode.

For development, use the launcher below instead of calling `flutter run`
directly. It starts the local worker, waits for `/health`, runs the selected
Flutter target, and stops the worker when Flutter exits:

```powershell
.\tool\run_ai_3d_dev.ps1 -Target windows
.\tool\run_ai_3d_dev.ps1 -Target web -WebDevice chrome
```

Pass `-KeepWorker` to leave the worker running after Flutter exits. The
launcher starts the current TripoSR Python worker, not Docker; the repository's
Docker Compose bundle is for the separate TRELLIS.2 deployment. A hosted Web
site cannot start Docker on a user's computer, so production Web requires a
stable remote worker URL configured in Backend Settings or through the
Supabase Edge Function.

When `output\ai-3d-triposr-runtime` is present, the launcher automatically uses
its `.venv` and pinned `TripoSR` checkout. Otherwise pass `-PythonExecutable`
and `-TripoSRRoot` explicitly.

ComfyUI can be used as an additional direct provider when a pinned ComfyUI
workflow and a 3D custom node are installed. Configure the worker with
`COMFYUI_BASE_URL`, `COMFYUI_WORKFLOW_FILE`, and optionally
`COMFYUI_OUTPUT_NODE_ID`; the workflow must produce a `.glb` artifact.

### Supabase worker proxy

Deploy the migration and authenticated Edge Function after linking Supabase:

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --linked --yes
supabase functions deploy ai-3d --use-api
supabase secrets set `
  AI_3D_WORKER_BASE_URL=https://worker.example.com/v1 `
  AI_3D_WORKER_TOKEN=YOUR_WORKER_TOKEN `
  AI_3D_ALLOWED_PROVIDERS=triposr,trellis,comfyui,fal-trellis2 `
  ALLOWED_ORIGINS=https://app.example.com
```

The Edge Function accepts authenticated `create`, `poll`, `cancel`, and
`health` requests, enforces project edit access and rate limits, validates GLB
magic/header/chunks and size, and saves the final artifact to Supabase Storage.
Configure `AI_3D_ALLOWED_SOURCE_HOSTS` when image-to-3D jobs use remote image
URLs. Keep worker and provider credentials server-side in production.
To enable the hosted TRELLIS.2 fallback explicitly, add `FAL_KEY` and set
`AI_3D_ENABLE_FAL_TRELLIS2=true` plus `FAL_3D_MODEL=fal-ai/trellis-2`. Keep
`AI_3D_DEFAULT_PROVIDER=triposr`; the UI labels hosted generation as metered.
`hunyuan3d` is removed from the default provider allow-list. Enable it only
after legal approval with all four server-side gates:
`AI_3D_ENABLE_HUNYUAN=true`,
`AI_3D_HUNYUAN_LEGAL_APPROVED=true`,
`AI_3D_HUNYUAN_TERRITORY_CONFIRMED=true`, and
`AI_3D_HUNYUAN_AUP_CONFIRMED=true`. The deployment must also carry the
reviewed model/dependency bill of materials and required user-facing notices.

### Implementation status

The transport, typed job/artifact contract, local worker, GLB validation,
storage handoff, canvas insertion, cancellation, retry, preview artifact,
ComfyUI API adapter, provider security tests, and fake-worker integration tests
are implemented. The Supabase migration is applied to project
`jnpxpylzzskaukgwhuzg`, and the authenticated `ai-3d` Edge Function is deployed.
TripoSR image-to-3D was also verified locally through the HTTP worker with
Blender 5.2.1: the draft fixture completed in about 12 seconds, exported a
3.1 MB self-contained GLB with 25,980 triangles, and produced a 512×512 PNG
preview. TripoSR image-to-3D was subsequently verified through the HTTP worker
and imported into the canvas on both Windows and Web as a `Model3D` node. The
worker security suite, Supabase helper suite, all Flutter tests, and static
analysis pass.

The authenticated staging path was verified on 2026-09-11 through a
token-protected HTTPS quick tunnel to the local TripoSR worker. The full
Supabase flow completed: health, create, poll, GLB download, Storage handoff,
and preview validation. The quick tunnel is temporary and has no uptime
guarantee; durable production still requires a dedicated HTTPS Linux GPU
worker and stable `AI_3D_WORKER_BASE_URL`/`AI_3D_WORKER_TOKEN` secrets.

The hosted `fal-trellis2` queue adapter and its security contract tests are now
deployed in Edge Function version 14. One explicitly requested live draft smoke
test reached the hosted provider on 2026-09-11, but FAL returned HTTP 403 before
returning a request ID or artifact. Rotate `FAL_KEY` or verify account/model
access before retrying; the production path remains TripoSR until that check
passes.

TRELLIS.2 inference reached the preview stage on the official remote Linux GPU
Space with the same fixture, but its GLB extraction was rejected by the
anonymous ZeroGPU quota. A Hugging Face token with available quota or a
dedicated Linux GPU worker is required to seal the TRELLIS.2 artifact
benchmark. The reproducible dedicated-worker image and pinned dependency
manifest are available under `tool/ai_3d_worker/deployment/trellis2`; the
remote build and end-to-end artifact check remain pending GPU access.
Hunyuan3D-2.1 shape generation was completed remotely and its GLB
passed the worker validator and Blender post-processing, but the provider
remains disabled by the license gate above.

## Image-to-video provider

Image-to-video uses the user's OpenAI-compatible Videos API for automatic generation. The public Hugging Face Wan2.1 Fast Space remains available only as an explicit manual mode; it is not used as a silent fallback because its GPU queue and quota are shared and can fail without detail.

The primary provider must support:

```text
POST /v1/videos
GET  /v1/videos/{id}
GET  /v1/videos/{id}/content
```

The create request is multipart and sends `model`, `prompt`, `seconds`, `size`, and one `input_reference` image. The client polls every two seconds for up to five minutes, downloads the completed MP4, displays it as a canvas video card, and provides a Download action.

Configure the provider in Backend Settings:

- `Video Provider Mode`: OpenAI-compatible Videos API (automatic) or Wan2.1 Fast (public/manual).
- `Video API Key`: optional override; empty uses the general AI key.
- `Video API Base URL`: optional override; empty uses the general AI base URL.
- `Video Model Identifier`: required for primary video generation.

The `Test Video API` action checks the selected provider's availability without creating a paid video job. For the OpenAI-compatible provider, it first probes `/videos` and then queries `/models` when available. For Wan2.1, it queries the Gradio info endpoint. OpenAI-compatible is a protocol shape, not a guarantee that a provider supports video; an unsupported or incomplete endpoint returns a configuration error instead of silently sending the image to a public Space.

Native video API keys use secure storage. Web keeps the video key only for the current session; browser users can inspect credentials entered directly in the Web app. Use an authenticated same-origin proxy when the key must remain server-side. Provider pricing, credits, and rate limits belong to the configured provider. Wan2.1 manual mode does not require an API key, but it still uses the public shared Space.

Wan2.1 uses a public shared GPU queue. Generation can take 60–90 seconds or fail without a provider detail when the Space is busy, out of quota, or rejects an input. The client allows up to 120 seconds per Gradio request and reports a safe generic message when the Space returns an empty error event. This build does not bundle a local video model or GPU runtime; a 6 GB laptop GPU is not a reliable target for Wan2.1 14B.

Generated MP4 files are cached locally on Windows and Android and can be downloaded to a user-selected location. Web uses an in-memory session artifact. API keys are never stored in canvas data, cloud sync, job history, logs, or video URLs.

A deterministic FFmpeg still-image fallback is not bundled in this build. It does not provide semantic AI animation.

## Import and media portability

The import service keeps a loss report with every non-native format so users can review what became editable canvas content and what remains attached to the original file:

- `PDF`: page frames, literal text operators, basic filled/stroked rectangles, transformed line/cubic paths, common `q/Q` graphics state, `cm`, `ca/CA`, `ExtGState` alpha, fill rules, caps, joins, dashes, embedded JPEG images, supported Flate RGB/Gray images, and simple form widgets become editable nodes. Full vector fidelity, clipping, blend modes, unsupported image filters/colorspaces, annotations other than supported widgets, advanced AcroForm appearance streams, font metrics, and exact layout remain in the loss report.
- `PPTX`: slide frames plus supported shape geometry, rotation, stroke width, text styling, and embedded raster images become editable nodes. Theme/master inheritance, exact font fidelity, tables, charts, animations, and timings remain listed in the loss report.
- Invalid or unsupported documents remain auditable `fileCard` attachments instead of being silently discarded.
- The import preview must be reviewed before applying a lossy result to the canvas. Keep the original source available when exact PDF/PPTX fidelity, forms, annotations, themes, or animation timing must be preserved.

Video proxy encoding is process-backed on native platforms and uses `ffmpeg` when it is available on `PATH`. The adapter supports bounded trim, multi-clip concat, H.264/AAC output for MP4/MOV/MKV, and VP9/Opus output for WebM. If `ffmpeg` is missing, times out, is cancelled, or returns an error, the app exposes an explicit unavailable/failed state and never treats the source bytes as an encoded proxy. Web and unsupported native targets keep the same explicit unavailable state until a target codec boundary is provided.

Run local checks:

```bash
flutter test test/features/ai test/features/backend_sync_test.dart
flutter analyze
flutter build web --release
flutter build windows --release
```

Run the cross-runtime collaboration preflight without creating accounts or
using a personal browser profile:

```powershell
powershell -ExecutionPolicy Bypass -File tool/collaboration_platform_matrix.ps1
```

The command runs the two-client Realtime transport suite on Chrome and Windows
and writes logs plus a Markdown/JSON report under
`output/collaboration-matrix/<run-id>/`. This is target-runtime evidence only;
the report keeps the Windows-host/Chrome-guest and Chrome-host/Windows-guest
production matrix pending until two authorized Supabase sessions complete the
manual room, edit, reconnect, revoke, duplicate-operation, and presence checks.

Run the deterministic empty/loading/error/unavailable/cancel/retry/offline,
health, accessibility, and recovery state gate across VM, Chrome, and Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool/creative_studio_state_matrix.ps1
```

The report is written under `output/state-matrix/<run-id>/` and lists native
platform gates that still require an iOS runtime or a real codec backend.

Workspace operability is available through the authenticated Supabase migration
`20260914000000_create_workspace_operability.sql`. The canvas Governance dialog
uses the workspace health RPC, can submit a SHA-256 checked redacted support
bundle, and can read or update the workspace release channel when the user has
the required role. The public `workspace-health` Edge Function probes Supabase
Auth and the release-policy table for uptime monitoring; configure
`APP_VERSION`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` only in the
Supabase Function environment. Apply the migration and deploy the function
before treating these checks as production evidence.

Run the repeatable health probe from the repository root. It exits non-zero
when the endpoint is unavailable, reports an unhealthy check, or returns an
unexpected application version:

```powershell
powershell -ExecutionPolicy Bypass -File tool/workspace_health_probe.ps1 `
  -Url https://<project-ref>.supabase.co/functions/v1/workspace-health `
  -ExpectedVersion 1.0.0+1 `
  -OutputPath output/workspace-health/latest.json
```

Billing entitlement sync is available through migration
`20260914010000_create_workspace_billing_entitlements.sql` and the signed
`billing-webhook` Edge Function. The function accepts a bounded provider event,
requires an HMAC-SHA256 signature using `x-billing-timestamp` and
`x-billing-signature`, rejects timestamps older than five minutes, strips raw
provider fields before persistence, and applies each provider/event ID once.
Configure `BILLING_WEBHOOK_SECRET` with at least 16 characters and optionally
`BILLING_PROVIDER`; keep both values in the Supabase Function environment.
Deploy the migration and function before enabling a real billing provider:

```bash
supabase db push --workdir .
supabase functions deploy billing-webhook --workdir . --no-verify-jwt
```

The Flutter client reads the authenticated entitlement RPC and displays the
provider, plan, status, revision, and key limits in Workspace Governance. A
provider account, live webhook secret, metering reconciliation, and external
monitor are still required for production billing evidence.

Workspace retention maintenance is available through migrations
`20260914030000_create_workspace_retention_job.sql` and
`20260914030100_harden_workspace_retention_job.sql`, plus the service-role-only
`workspace-retention` Edge Function. The function requires the deployment-owned
`RETENTION_JOB_SECRET`; keep it only in the Supabase Function environment or a
local process environment and never commit it. Run an operator probe from the
repository root after configuring the secret:

```powershell
$env:RETENTION_JOB_SECRET = '<deployment-secret>'
powershell -ExecutionPolicy Bypass -File tool/workspace_retention_probe.ps1 `
  -Url https://<project-ref>.supabase.co/functions/v1/workspace-retention `
  -ProjectId <project-id> `
  -OutputPath output/workspace-retention/latest.json
```

The probe exits non-zero unless the function returns the requested project ID
and bounded audit/export deletion counts. Requests without the operator secret
are rejected with `401 INVALID_SECRET`.

Plugin registry synchronization is available through migration
`20260914020000_create_workspace_plugin_registry.sql`. Owner-only RPCs validate
the manifest/API version, require exact permission approval before enablement,
persist state transitions, and authorize node/export commands for enabled
plugins. Governance keeps a local-first fallback when the registry migration is
not deployed. The app runtime applies command, storage, event, network, and
execution budgets and exposes cooperative cancellation to plugin handlers; a
real production sandbox still requires isolated untrusted-code execution and
deployment policy.

## Collaboration rooms

Collaboration uses a six-digit Room ID instead of a share URL. The host opens
**Collaboration Room**, chooses a lifetime, and shares the ID. Other users open
**Join Room**, enter the six digits, and sign in before joining the workspace.
The host must also be signed in before creating or rotating a room; local-only
documents remain available without an account, but cloud snapshots and room
membership are deliberately protected by the authenticated Supabase session.

Collaborative asset changes are staged through the authenticated `assets`
bucket. Embedded data URLs and external HTTP media are promoted to a durable
project-scoped storage URL before the CRDT asset operation is broadcast when
possible; local-only fallback remains explicit when storage is unavailable.
The host can revoke the room; the cached Room ID is retained until it is
revoked or expires.

Open **Collaboration members** to see the persistent roster, online status,
cursor activity, role, and last-seen information. The host can assign
`editor`, `commenter`, or `viewer`, and remove guests. Role changes are applied
to the active canvas session without restarting the app; the backend RLS/RPC
policies remain the final enforcement layer.

**Follow viewport** shares the target user's canvas position, zoom, selection,
and active node after the target approves the request. **Screen tracking** is a
separate WebRTC feature: the target must approve the in-app request and the
browser or Windows OS consent prompt. Either side can stop it, and leaving,
revoking, removing a member, or disposing the session closes the peer and
media tracks. The client uses a public STUN server by default; production
deployments behind restrictive NATs should provide a TURN service through
backend configuration, never by shipping a service secret in Flutter.

## Video meetings (LiveKit)

Video meetings use LiveKit for the media plane and Supabase Auth, PostgreSQL,
Realtime, and two Supabase Edge Functions: `meeting-token` issues join/refresh
tokens, while `meeting-remove-participant` authorizes host removal and calls the
LiveKit server API. The supported release targets are Flutter Web in Chrome and
Flutter Windows. Meeting routes require an authenticated Supabase session and an
active project membership; the public share routes are unchanged.

### Configure the server

Both meeting functions must have these deployment-owned environment names:

```text
LIVEKIT_URL
LIVEKIT_API_KEY
LIVEKIT_API_SECRET
ALLOWED_ORIGINS
```

Keep the LiveKit API key and secret in the Supabase Edge Function environment
only. Do not put them in Flutter `--dart-define` values, assets, URLs, logs, or
source control. `LIVEKIT_URL` is an endpoint, not a credential. Supabase
provides the function's `SUPABASE_URL` and `SUPABASE_ANON_KEY` runtime values;
they are not client meeting secrets and should not be copied into this config.

`ALLOWED_ORIGINS` is a comma-separated exact-origin allowlist with no paths or
wildcards, for example `https://app.example.com,http://localhost:3000`. Include
the hosted Web origin and every local Chrome origin used for testing. A browser
request with an origin not in this list is rejected. An omitted `Origin` is
accepted for native Windows clients after the remaining authentication and
configuration checks pass. Leaving `ALLOWED_ORIGINS` empty therefore fails
closed for browser clients; it does not enable all origins.

Link the project, apply the meeting migration, deploy both exact function names,
then set their shared values through the Supabase secret store. Supply the values
from a deployment secret manager or already-exported process environment
variables; never replace them with committed literals:

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --linked --yes
supabase functions deploy meeting-token --use-api
supabase functions deploy meeting-remove-participant --use-api
supabase secrets set `
  LIVEKIT_URL=$env:LIVEKIT_URL `
  LIVEKIT_API_KEY=$env:LIVEKIT_API_KEY `
  LIVEKIT_API_SECRET=$env:LIVEKIT_API_SECRET `
  ALLOWED_ORIGINS=$env:ALLOWED_ORIGINS
```

`supabase/config.toml` declares both functions with `verify_jwt = false`; each
function validates the Supabase Bearer token itself. Bearer authentication for
participant removal is manually verified during release testing.

The deployed token endpoint is
`https://YOUR_PROJECT_REF.supabase.co/functions/v1/meeting-token`. It accepts
an authenticated `POST` containing `{ "meetingId": "<uuid>" }`; the function
issues a short-lived LiveKit token only after membership, role, active-session,
and provider-capacity checks. Missing or malformed server configuration returns
an unavailable response and never issues a token.

The deployed removal endpoint is
`https://YOUR_PROJECT_REF.supabase.co/functions/v1/meeting-remove-participant`.
It accepts an authenticated `POST` containing
`{ "meetingId": "<uuid>", "identity": "<uuid>" }` and returns
`{ "removed": true }` or `{ "removed": false }`; false is an idempotent no-op.
It uses the same server-only LiveKit credentials and never exposes provider
errors or credential details.


### Configure the client safely

The implemented client-safe compile-time defines are:

| Define | Default | Purpose |
| --- | --- | --- |
| `VIDEO_MEETING_ENABLED` | `false` | Rollout flag; only `true` enables the feature. |
| `LIVEKIT_URL` | empty | Public provider endpoint used by the availability guard. |
| `VIDEO_MEETING_MAX_PARTICIPANTS` | `8` | Client request limit, normalized to `2..8`. |

The client is unavailable unless both `VIDEO_MEETING_ENABLED=true` and a
non-empty `LIVEKIT_URL` are supplied. This is a fail-closed rollout default;
the server-issued URL and token remain authoritative. The client defines may
contain the public provider URL, but never `LIVEKIT_API_KEY` or
`LIVEKIT_API_SECRET`:

```powershell
flutter run -d chrome `
  --dart-define=VIDEO_MEETING_ENABLED=true `
  --dart-define=LIVEKIT_URL=wss://YOUR_LIVEKIT_HOST

flutter run -d windows `
  --dart-define=VIDEO_MEETING_ENABLED=true `
  --dart-define=LIVEKIT_URL=wss://YOUR_LIVEKIT_HOST
```

Use the same defines for release builds only after the function is deployed
and its exact Web origins are allowlisted. The meeting feature is disabled by
default; keep the flag off (or omit the defines) until the manual matrix below
passes.

### Lifecycle and manual release matrix

Leave, route disposal, provider disconnect, an ended session, participant
removal, and room revocation must stop local media, disconnect the LiveKit
adapter, cancel the meeting session stream, clear participant state, and ignore
late provider events. **End for everyone** additionally records the durable
Supabase session transition; ordinary **Leave** only disconnects the local
participant. No meeting cleanup owns or stops the separate canvas screen-
tracking session.

Run both directions with two signed-in users and record an absolute UTC date,
build revision, target versions, and evidence path. Do not mark the release
gate passed from a unit test alone:
Run the repository release-gate script in safe flag-off mode before enabling
the feature; it checks configuration without printing environment values:

```powershell
powershell -ExecutionPolicy Bypass -File tool/video_meeting_platform_matrix.ps1
```

Use the configured server check only after the deployment environment has been
populated. It validates the same names without printing values:

```powershell
powershell -ExecutionPolicy Bypass -File tool/video_meeting_platform_matrix.ps1 `
  -RequireServerConfiguration
```

Keep `VIDEO_MEETING_ENABLED` off until the two-client checks pass.

| Direction | Required checks |
| --- | --- |
| Windows host ↔ Chrome guest | Start and join the active room; verify roster, two-way camera/microphone, Windows and Chrome screen share, mute/camera-off states, reconnect after a temporary network interruption, guest leave, host remove, host end, and collaboration-room revoke. |
| Chrome host ↔ Windows guest | Repeat the same checks with host and guest reversed, including browser permission denial followed by retry and Windows device permission denial followed by retry. |

Also verify an unauthenticated or non-member user receives no token, a viewer
can subscribe but cannot publish, and an unavailable or misconfigured backend
leaves the feature disabled without exposing credential details.

## Public authentication

Users authenticate from the full-page `/auth` canvas screen with email/password, signup, password reset, or Google OAuth. They never enter a Supabase URL or key. This build includes the connected project's public Supabase URL and publishable key, so local runs work without flags:

```powershell
flutter run -d chrome
flutter run -d windows
```

The project keeps the Web development server on `http://localhost:3000` via
`web_dev_config.yaml`, so `--web-port 3000` is not required. This is only a
local development setting and does not affect hosted Web builds.

Publisher builds can override those defaults for another project or a rotated key:

```powershell
flutter build web --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY

flutter build windows --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=io.canvascreative://auth/callback
```

The publishable key is intended for client applications. Never ship a Supabase service-role key. The app uses PKCE and does not log passwords, OAuth tokens, or connection keys.

In Supabase Auth, enable the Google provider and allow these redirect URLs:

- `http://localhost:3000` for the local `flutter run -d chrome` Web build.
- `http://localhost:8080` only if the development port is overridden.
- `https://YOUR_WEB_ORIGIN` for the hosted Web build.
- `io.canvascreative://auth/callback` for desktop builds.

The Web OAuth redirect and share links use the current browser origin from
`Uri.base.origin`. If the `link-preview` Edge Function has `ALLOWED_ORIGINS`
configured, include `http://localhost:3000` there as well; leave it unset for
local development.

Windows desktop builds use `app_links` to receive the callback and register the
`io.canvascreative` scheme for the current executable at startup. Packaged
installers can register the same scheme before first launch with this elevated-
free, per-user PowerShell command:

```powershell
.\tool\register_windows_auth_protocol.ps1 -ExecutablePath 'C:\Path\To\creative_canvas.exe'
```

For packaged Windows installers, add the same `HKCU\Software\Classes\io.canvascreative\shell\open\command` registration to the installer. macOS and Linux packages must register the same `io.canvascreative` scheme using their native desktop packaging mechanism. Set `SUPABASE_AUTH_REDIRECT_URL` when a platform requires a different callback URI.

`ALLOW_RUNTIME_SUPABASE_CONFIG=true` is reserved for local development. Release builds hide the Supabase fields in Backend Settings and ignore saved developer Supabase values unless this flag is explicitly supplied.

## Getting Started

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
