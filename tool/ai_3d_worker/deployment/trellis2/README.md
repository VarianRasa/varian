# TRELLIS.2 Linux GPU worker

This deployment runs the pinned TRELLIS.2 provider behind the existing Varian
worker API. The Flutter client and Supabase Edge Function remain unchanged.

## Requirements

- Linux host with NVIDIA GPU memory of at least 24 GB.
- NVIDIA Container Toolkit and Docker Compose v2.
- An HTTPS reverse proxy or managed job URL that points to port `20130`.
- A private worker token; do not put it in Flutter or source control.
- A Hugging Face token with access to `facebook/dinov3-vitl16-pretrain-lvd1689m`
  and `briaai/RMBG-2.0`; do not put it in Flutter, Dockerfile, or source control.

## Build and run

From the repository root:

```bash
export VARIAN_3D_WORKER_TOKEN="replace-with-a-random-secret"
export HF_TOKEN="replace-with-a-huggingface-token"
export AI_3D_PUBLIC_BASE_URL="https://worker.example.com"
export AI_3D_CORS_ORIGINS="https://app.example.com"
docker compose -f tool/ai_3d_worker/deployment/trellis2/docker-compose.yml up --build -d
```

The first build compiles CUDA extensions and can take a long time. The image
records the resolved dependency BOM in `/opt/varian/provenance`. The Compose
file persists the Hugging Face cache in `trellis2-model-cache`, so a restart does
not redownload the checkpoint and gated feature models.

Set `TRELLIS2_PIPELINE_TYPE=512` for the lowest-memory profile, or use
`1024`, `1024_cascade`, and `1536_cascade` when the host has enough VRAM. The
worker loads only the model family required by the selected profile and keeps
the checkpoint's original mixed dtypes. The adapter also handles the DINOv3
module layout used by current `transformers` releases.

Verify the worker from the host:

```bash
curl -fsS \
  -H "Authorization: Bearer ${VARIAN_3D_WORKER_TOKEN}" \
  "${AI_3D_PUBLIC_BASE_URL}/v1/health"
```

The response must report `defaultProvider: "trellis"` and
`blenderAvailable: true` before connecting Supabase.

Run the repeatable remote smoke test from the repository root after the worker
is healthy. It performs authenticated health, create, poll, GLB download, and
preview validation without printing the worker token:

```bash
export AI_3D_REFERENCE_IMAGE="/path/to/chair.png"
bash tool/ai_3d_worker/deployment/trellis2/verify_remote.sh
```

Use `TRELLIS2_SMOKE_QUALITY=balanced` only after the host passes the `draft`
profile. The script requires a real generated GLB; the demo provider is not
accepted by this check.

## Connect Supabase

Set the Edge Function secrets to the HTTPS worker URL, not the internal Docker
address:

```bash
supabase secrets set \
  AI_3D_WORKER_BASE_URL="${AI_3D_PUBLIC_BASE_URL}/v1" \
  AI_3D_WORKER_TOKEN="${VARIAN_3D_WORKER_TOKEN}" \
  AI_3D_ALLOWED_PROVIDERS="triposr,trellis,comfyui"
supabase functions deploy ai-3d --use-api
```

Run the authenticated create → poll → GLB download → Storage handoff flow
before using the worker for users. Keep the `AI_3D_DEFAULT_PROVIDER` on the
worker at `trellis` only after the benchmark artifact and provenance review
pass.

## Provenance review

The image contains:

- `pip-freeze.txt` for the resolved Python dependency graph;
- `git-revisions.json` for TRELLIS.2, model, native extensions, and utilities;
- `blender-version.txt` for the separate Blender process.

Compare these files with `tool/ai_3d_worker/provider-lock.json` and
`docs/ai-3d-licensing.md` before release.
