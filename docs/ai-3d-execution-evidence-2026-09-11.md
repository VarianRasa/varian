# AI 3D Execution Evidence — 2026-09-11

This record captures the runtime checks performed for the remaining AI 3D
stages. It contains no provider keys or worker tokens.

## Supabase staging path

- Local worker: authenticated `GET /v1/health` returned HTTP 200.
- HTTPS tunnel: unauthenticated worker health returned HTTP 401; the same
  request with the worker bearer token returned HTTP 200.
- Supabase project: `jnpxpylzzskaukgwhuzg`.
- Edge Function: authenticated `GET /functions/v1/ai-3d/health` returned HTTP
  200 and reported the TripoSR worker.
- End-to-end job: authenticated `POST /3d/jobs` → repeated `GET /3d/jobs/{id}`
  → artifact download completed with `status=completed` and `progress=100`.
- Artifact handoff: Supabase Storage returned a validated GLB and a validated
  512×512 PNG preview.

The tunnel was an account-less quick tunnel and is staging evidence only. It
does not provide a durable production hostname or uptime guarantee.

## Remote provider benchmarks

The same `chair.png` fixture was used for the remote provider checks.

### Hunyuan3D-2.1

- Runtime: official Tencent Hugging Face Space on remote Linux GPU.
- Settings: 20 steps, guidance 5.0, seed 12345, octree resolution 128,
  background removal enabled, 50,000 chunks.
- Remote shape result: 74,264 triangles, 37,132 vertices, 9.19 seconds.
- Source GLB: 1,338,012 bytes; GLB validator passed.
- Worker post-processing result: 6,228,288-byte GLB with 74,264 triangles and
  a 512×512 PNG preview; validator and Blender post-processing passed.
- Production status: disabled by the license gate; this benchmark does not
  constitute legal approval for commercial or worldwide deployment.
- Deployed gate check: a Hunyuan request returned HTTP 400 while the four
  approval flags were unset.

### TRELLIS.2

- Runtime: official Microsoft Hugging Face Space on remote Linux GPU.
- The image-to-3D inference stage completed with the same fixture and returned
  the rendered preview payload.
- The GLB extraction request was rejected by the anonymous ZeroGPU quota before
  an artifact was returned.
- A reproducible Linux GPU deployment bundle was added under
  `tool/ai_3d_worker/deployment/trellis2`; TRELLIS.2, model, native extension,
  and utility revisions are pinned in `tool/ai_3d_worker/provider-lock.json`.
- The canonical Docker image was rebuilt successfully with the final
  `python3-numpy` and `plyfile` fixes. Authenticated health returned
  `defaultProvider: "trellis"`, unauthenticated health returned HTTP 401, all
  native extensions imported, and Blender was available. The image records the
  pinned revisions and a 181-package license BOM. Final image digest:
  `sha256:a6026dfcb0acf2fb4233cb7d91a68935e077c69757341b0fcd22ddde660bfa8f`.
- Complete TRELLIS.2 artifact benchmarking still requires a Hugging Face token
  with available quota or a dedicated Linux GPU worker. The local RTX 4050 has
  approximately 6 GB VRAM, below the upstream 24 GB requirement.
- The native dependency review also found NVIDIA non-commercial terms for
  `nvdiffrast` and `nvdiffrec`; production/commercial activation remains blocked
  pending legal clearance or replacement dependencies.
- A canonical-worker inference attempt downloaded the pinned TRELLIS.2-4B
  snapshot successfully. The official pipeline then required gated access to
  facebook/dinov3-vitl16-pretrain-lvd1689m and briaai/RMBG-2.0; no Hugging Face
  token with those approvals is available in this environment, so no official
  TRELLIS.2 GLB artifact was produced.
- The worker now fails fast with an actionable HF_TOKEN message when
  TRELLIS2_HF_TOKEN_REQUIRED=true, and the deployment compose file passes the
  token only as a runtime environment secret. The token is never baked into the
  image or Flutter client.
- The Edge Function provider gate and hosted fallback are deployed as version
  14. The Deno provider/security suites passed 13/13 tests. With the TRELLIS.2
  approval flags unset, direct `trellis` remains removed from the production
  allow-list; `fal-trellis2` is separately enabled only when its opt-in flag and
  server-side `FAL_KEY` are present.

### Hosted FAL TRELLIS.2

- The Edge Function now submits `fal-ai/trellis-2` through the FAL queue, polls
  the request status, supports cancellation, validates the returned HTTPS GLB,
  enforces the stored triangle budget, and persists the artifact through the
  existing Supabase Storage handoff.
- The provider key is read only from the Edge Function environment. The Flutter
  client receives no provider credential; the UI labels this provider as
  metered and TripoSR remains the default.
- Contract tests use a mocked FAL queue and passed without network inference or
  provider credit usage. The explicitly approved live generation attempt is
  recorded below.
- An explicitly requested live draft smoke test was attempted with an
  authenticated temporary Supabase project. The Edge Function gate accepted
  `fal-trellis2`, but the hosted queue returned HTTP 403 during job creation;
  no provider request ID or GLB artifact was returned. The next retry requires
  a rotated `FAL_KEY` or confirmation that the configured FAL account can use
  `fal-ai/trellis-2`.

### Current local verification

- `varian-trellis2-worker:canonical` passed authenticated health validation:
  unauthorized requests returned HTTP 401, authenticated health returned
  `status=ok`, `defaultProvider=trellis`, and Blender was available.
- The same image passed the demo-provider end-to-end path: create, poll,
  artifact download, GLB magic validation, and preview availability.
- The worker security suite passed 12/12 tests in the canonical dependency
  image. Flutter analyzer, Web build, Windows build, and the focused 3D tests
  also passed after adding hosted FAL provider selection and text-reference
  handling.
- After the ComfyUI installer cancellation-order fix, the complete Flutter
  suite passed 862 tests with no failures, and `flutter analyze --no-pub`
  reported no issues. `docker compose config --quiet` also passed with
  deployment values supplied through environment variables; no credentials
  were written to the repository.
- Docker Desktop GPU passthrough is available for the canonical image and
  reports an NVIDIA GeForce RTX 4050 Laptop GPU with 6141 MiB. This is enough
  to validate container startup and health, but remains below the upstream
  TRELLIS.2 deployment target of approximately 24 GB VRAM. The Compose bundle
  now persists `/root/.cache/huggingface` and reserves 16 GB shared memory for
  the eventual Linux GPU host.

### Follow-up compatibility hardening

- The worker adapter now resolves `TRELLIS2_PIPELINE_TYPE` before loading the
  pipeline and loads only the model family required by `512`, `1024`,
  `1024_cascade`, or `1536_cascade`.
- The adapter installs a runtime compatibility shim for the DINOv3 layout in
  current `transformers` releases, where encoder layers may be exposed as
  `model.model.layer`; it does not coerce checkpoint parameters to a single
  dtype.
- Worker regression tests passed `15/15`, and `python -m compileall -q
  tool/ai_3d_worker` passed.
- A repeatable remote validation script was added at
  `tool/ai_3d_worker/deployment/trellis2/verify_remote.sh`; `bash -n` passed and
  the script validates authenticated health, create, poll, GLB magic, and PNG
  preview without logging the worker token.
- A compatibility-image rebuild reached layer export but Docker Desktop stopped
  responding during final image unpacking. No new image digest is claimed; the
  previously validated canonical image remains the production reference.

## Reproducibility references

- Provider revisions: `tool/ai_3d_worker/provider-lock.json`.
- License review: `docs/ai-3d-licensing.md`.
- Checklist: `tasks/ai-3d-generation-todo.md`.
- Generated local artifacts are under
  `output/ai-3d-triposr-runtime/benchmark-output/` and are intentionally not
  part of the Flutter bundle.
