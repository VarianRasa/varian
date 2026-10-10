#!/usr/bin/env bash
set -euo pipefail

: "${VARIAN_3D_WORKER_TOKEN:?VARIAN_3D_WORKER_TOKEN must be set}"
: "${AI_3D_PUBLIC_BASE_URL:?AI_3D_PUBLIC_BASE_URL must be set}"
: "${AI_3D_CORS_ORIGINS:?AI_3D_CORS_ORIGINS must be set}"

exec uvicorn tool.ai_3d_worker.app:app \
  --host 0.0.0.0 \
  --port "${AI_3D_WORKER_PORT:-20130}" \
  --workers 1
