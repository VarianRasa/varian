#!/usr/bin/env bash
set -euo pipefail

: "${AI_3D_PUBLIC_BASE_URL:?set AI_3D_PUBLIC_BASE_URL}"
: "${VARIAN_3D_WORKER_TOKEN:?set VARIAN_3D_WORKER_TOKEN}"
: "${AI_3D_REFERENCE_IMAGE:?set AI_3D_REFERENCE_IMAGE}"

quality="${TRELLIS2_SMOKE_QUALITY:-draft}"
triangle_budget="${TRELLIS2_SMOKE_TRIANGLE_BUDGET:-100000}"
poll_seconds="${TRELLIS2_SMOKE_POLL_SECONDS:-5}"
timeout_seconds="${TRELLIS2_SMOKE_TIMEOUT_SECONDS:-1800}"
job_id="${TRELLIS2_SMOKE_JOB_ID:-trellis2-smoke-$(date -u +%Y%m%dT%H%M%SZ)}"
base_url="${AI_3D_PUBLIC_BASE_URL%/}"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf -- "$work_dir"
}

trap cleanup EXIT

curl -fsSL --retry 3 \
  -H "Authorization: Bearer ${VARIAN_3D_WORKER_TOKEN}" \
  "${base_url}/v1/health" >"${work_dir}/health.json"

python3 - "${work_dir}/health.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
if payload.get("status") != "ok":
    raise SystemExit("worker health is not ok")
if "trellis" not in payload.get("providers", []):
    raise SystemExit("worker does not expose the trellis provider")
if not payload.get("blenderAvailable"):
    raise SystemExit("worker does not have Blender available")
PY

python3 - "${AI_3D_REFERENCE_IMAGE}" "${job_id}" "${quality}" "${triangle_budget}" >"${work_dir}/request.json" <<'PY'
import base64
import json
import mimetypes
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if not data or len(data) > 8 * 1024 * 1024:
    raise SystemExit("reference image must be between 1 byte and 8 MiB")
mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
if mime_type not in {"image/png", "image/jpeg", "image/webp"}:
    raise SystemExit("reference image must be PNG, JPEG, or WebP")
payload = {
    "jobId": sys.argv[2],
    "projectId": "trellis2-remote-smoke",
    "capability": "imageTo3D",
    "prompt": "TRELLIS.2 remote smoke fixture",
    "provider": "trellis",
    "meshQuality": sys.argv[3],
    "textureMode": "pbr",
    "triangleBudget": int(sys.argv[4]),
    "seed": 12345,
    "sourceImageBase64": f"data:{mime_type};base64,{base64.b64encode(data).decode('ascii')}",
}
print(json.dumps(payload))
PY

curl -fsSL --retry 3 \
  -H "Authorization: Bearer ${VARIAN_3D_WORKER_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "@${work_dir}/request.json" \
  "${base_url}/v1/3d/jobs" >"${work_dir}/create.json"

created_job_id="$(python3 - "${work_dir}/create.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
print(payload.get("jobId", ""))
PY
)"
if [[ "${created_job_id}" != "${job_id}" ]]; then
  printf 'worker returned an unexpected job ID\n' >&2
  exit 1
fi

deadline=$((SECONDS + timeout_seconds))
status="queued"
while (( SECONDS < deadline )); do
  curl -fsSL --retry 3 \
    -H "Authorization: Bearer ${VARIAN_3D_WORKER_TOKEN}" \
    "${base_url}/v1/3d/jobs/${job_id}" >"${work_dir}/status.json"
  status="$(python3 - "${work_dir}/status.json" <<'PY'
import json
import sys

print(json.loads(open(sys.argv[1], encoding="utf-8").read()).get("status", ""))
PY
)"
  case "${status}" in
    completed)
      break
      ;;
    failed|canceled)
      python3 - "${work_dir}/status.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
raise SystemExit(payload.get("error") or f"worker job ended with {payload.get('status')}")
PY
      ;;
    queued|processing)
      sleep "${poll_seconds}"
      ;;
    *)
      printf 'worker returned an unknown job status: %s\n' "${status}" >&2
      exit 1
      ;;
  esac
done

if [[ "${status}" != "completed" ]]; then
  printf 'TRELLIS.2 smoke test timed out after %s seconds\n' "${timeout_seconds}" >&2
  exit 1
fi

artifact_url="$(python3 - "${work_dir}/status.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
print((payload.get("artifact") or {}).get("url", ""))
PY
)"
preview_url="$(python3 - "${work_dir}/status.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
print((payload.get("artifact") or {}).get("previewUrl", ""))
PY
)"
if [[ -z "${artifact_url}" ]]; then
  printf 'completed job did not return a GLB URL\n' >&2
  exit 1
fi

curl -fsSL --retry 3 "${artifact_url}" >"${work_dir}/model.glb"
python3 - "${work_dir}/model.glb" <<'PY'
import sys

data = open(sys.argv[1], "rb").read(4)
if data != b"glTF":
    raise SystemExit("downloaded artifact is not a GLB")
PY

if [[ -n "${preview_url}" ]]; then
  curl -fsSL --retry 3 "${preview_url}" >"${work_dir}/preview.png"
  python3 - "${work_dir}/preview.png" <<'PY'
import sys

data = open(sys.argv[1], "rb").read(8)
if data != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("downloaded preview is not a PNG")
PY
fi

printf 'TRELLIS.2 remote smoke test passed: job=%s quality=%s\n' "${job_id}" "${quality}"
