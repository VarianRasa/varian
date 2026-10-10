from __future__ import annotations

import asyncio
import base64
import ipaddress
import json
import os
import re
import secrets
import shutil
import socket
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from .glb_utils import GLBValidationError, validate_glb_file
from .postprocess import PostprocessError, generate_preview, postprocess_glb
from .providers import (
    GenerationRequest,
    ProviderError,
    ProviderUnavailable,
    create_provider,
)


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


MAX_SOURCE_BYTES = 8 * 1024 * 1024
MAX_OUTPUT_BYTES = 64 * 1024 * 1024
MAX_REQUEST_BYTES = 12 * 1024 * 1024
MAX_PROMPT_CHARS = 2000
MAX_URL_CHARS = 2048
JOB_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
SUPPORTED_CAPABILITIES = {"textTo3D", "imageTo3D"}
SUPPORTED_PROVIDERS = {"triposr", "trellis", "hunyuan3d", "comfyui", "demo"}

WORK_DIR = Path(os.getenv("AI_3D_WORK_DIR", str(Path.cwd() / "ai_3d_jobs"))).resolve()
WORKER_TOKEN = os.getenv("VARIAN_3D_WORKER_TOKEN", "").strip()
DEFAULT_PROVIDER = os.getenv("AI_3D_DEFAULT_PROVIDER", "triposr").strip().lower()
PUBLIC_BASE_URL = os.getenv("AI_3D_PUBLIC_BASE_URL", "").strip().rstrip("/")
ALLOW_SOURCE_URLS = _env_bool("AI_3D_ALLOW_SOURCE_URLS", True)
ALLOW_LOOPBACK_SOURCE_URLS = _env_bool("AI_3D_ALLOW_LOOPBACK_SOURCE_URLS", True)
ARTIFACT_TTL_SECONDS = max(300, int(os.getenv("AI_3D_ARTIFACT_TTL_SECONDS", "86400")))
MAX_CONCURRENT_JOBS = max(1, int(os.getenv("AI_3D_MAX_CONCURRENT_JOBS", "1")))
JOB_TIMEOUT_SECONDS = max(60, int(os.getenv("AI_3D_JOB_TIMEOUT_SECONDS", "1800")))
RETRY_STOP_TIMEOUT_SECONDS = max(5, int(os.getenv("AI_3D_RETRY_STOP_TIMEOUT_SECONDS", "30")))

if DEFAULT_PROVIDER not in SUPPORTED_PROVIDERS:
    DEFAULT_PROVIDER = "triposr"


class CreateJobRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    job_id: str | None = Field(default=None, alias="jobId")
    project_id: str | None = Field(default=None, alias="projectId")
    capability: str = Field(default="imageTo3D", max_length=40)
    prompt: str = Field(min_length=1, max_length=MAX_PROMPT_CHARS)
    negative_prompt: str | None = Field(default=None, alias="negativePrompt", max_length=1000)
    source_image_base64: str | None = Field(default=None, alias="sourceImageBase64")
    source_image_url: str | None = Field(default=None, alias="sourceImageUrl", max_length=MAX_URL_CHARS)
    source_model_reference: str | None = Field(default=None, alias="sourceModelReference", max_length=1000)
    provider: str | None = Field(default=None, max_length=40)
    mesh_quality: str = Field(default="balanced", alias="meshQuality", max_length=20)
    texture_mode: str = Field(default="pbr", alias="textureMode", max_length=20)
    target_format: str = Field(default="glb", alias="targetFormat", max_length=10)
    triangle_budget: int = Field(default=100000, alias="triangleBudget", ge=1000, le=500000)
    seed: int = Field(default=-1, ge=-1, le=2**31 - 1)
    generate_preview: bool = Field(default=True, alias="generatePreview")


@dataclass
class JobRecord:
    job_id: str
    request: CreateJobRequest
    public_base_url: str
    artifact_token: str
    status: str = "queued"
    progress: float = 0.0
    error: str | None = None
    error_code: str | None = None
    artifact: dict[str, Any] | None = None
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    cancel_event: threading.Event = field(default_factory=threading.Event)
    task: asyncio.Task[None] | None = None
    output_path: Path | None = None
    preview_path: Path | None = None


app = FastAPI(title="Varian AI 3D Worker", version="1.0.0")
_jobs: dict[str, JobRecord] = {}
_jobs_lock = asyncio.Lock()
_job_slots = asyncio.Semaphore(MAX_CONCURRENT_JOBS)

cors_origins = [
    value.strip()
    for value in os.getenv("AI_3D_CORS_ORIGINS", "*").split(",")
    if value.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


@app.get("/v1/health")
async def health(request: Request) -> dict[str, Any]:
    _require_auth(request)
    return {
        "status": "ok",
        "service": "varian-ai-3d-worker",
        "providers": sorted(SUPPORTED_PROVIDERS),
        "defaultProvider": DEFAULT_PROVIDER,
        "blenderAvailable": shutil.which("blender") is not None
        or bool(os.getenv("BLENDER_BIN", "").strip()),
        "sourceUrlInputEnabled": ALLOW_SOURCE_URLS,
    }


@app.post("/v1/3d/jobs", status_code=202)
async def create_job(request: Request) -> JSONResponse:
    _require_auth(request)
    payload = await _read_json(request)
    try:
        job_request = CreateJobRequest.model_validate(payload)
        _validate_job_request(job_request)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    requested_id = (job_request.job_id or "").strip()
    job_id = requested_id or str(uuid.uuid4())
    async with _jobs_lock:
        existing = _jobs.get(job_id)
        if existing is not None:
            return JSONResponse(status_code=200, content=_serialize_job(existing))
        record = JobRecord(
            job_id=job_id,
            request=job_request,
            public_base_url=_resolve_public_base_url(request),
            artifact_token=secrets.token_urlsafe(24),
        )
        _jobs[job_id] = record
        _trim_jobs_locked()
        record.task = asyncio.create_task(_run_job(record))
    return JSONResponse(status_code=202, content=_serialize_job(record))


@app.get("/v1/3d/jobs/{job_id}")
async def get_job(job_id: str, request: Request) -> dict[str, Any]:
    _require_auth(request)
    record = await _get_job(job_id)
    return _serialize_job(record)


@app.post("/v1/3d/jobs/{job_id}/cancel")
async def cancel_job(job_id: str, request: Request) -> dict[str, Any]:
    _require_auth(request)
    record = await _get_job(job_id)
    if record.status in {"completed", "failed", "canceled"}:
        return _serialize_job(record)
    record.cancel_event.set()
    _set_status(record, "canceled", progress=record.progress)
    return _serialize_job(record)


@app.post("/v1/3d/jobs/{job_id}/retry", status_code=202)
async def retry_job(job_id: str, request: Request) -> JSONResponse:
    _require_auth(request)
    record = await _get_job(job_id)

    if record.status == "completed":
        return JSONResponse(status_code=200, content=_serialize_job(record))
    if record.status in {"queued", "processing"}:
        return JSONResponse(status_code=200, content=_serialize_job(record))

    previous_task = record.task
    if previous_task is not None and not previous_task.done():
        record.cancel_event.set()
        try:
            await asyncio.wait_for(
                asyncio.shield(previous_task),
                timeout=RETRY_STOP_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError as error:
            raise HTTPException(
                status_code=409,
                detail="The previous 3D job is still stopping; retry later.",
            ) from error

    async with _jobs_lock:
        current = _jobs.get(job_id)
        if current is None:
            raise HTTPException(status_code=404, detail="Job not found.")
        if current.status == "completed":
            return JSONResponse(status_code=200, content=_serialize_job(current))
        if current.status in {"queued", "processing"}:
            return JSONResponse(status_code=200, content=_serialize_job(current))
        if current.task is not None and not current.task.done():
            raise HTTPException(
                status_code=409,
                detail="The previous 3D job is still stopping; retry later.",
            )

        current.cancel_event = threading.Event()
        current.artifact_token = secrets.token_urlsafe(24)
        current.status = "queued"
        current.progress = 0.0
        current.error = None
        current.error_code = None
        current.artifact = None
        current.output_path = None
        current.preview_path = None
        current.updated_at = datetime.now(timezone.utc)
        current.task = asyncio.create_task(_run_job(current))
        return JSONResponse(status_code=202, content=_serialize_job(current))


@app.get("/v1/3d/artifacts/{job_id}.glb", name="download_artifact")
async def download_artifact(job_id: str, token: str) -> FileResponse:
    record = _jobs.get(job_id)
    if record is None or record.status != "completed" or record.output_path is None:
        raise HTTPException(status_code=404, detail="Artifact not found.")
    if not secrets.compare_digest(token, record.artifact_token):
        raise HTTPException(status_code=404, detail="Artifact not found.")
    age = (datetime.now(timezone.utc) - record.updated_at).total_seconds()
    if age > ARTIFACT_TTL_SECONDS:
        raise HTTPException(status_code=410, detail="Artifact URL expired.")
    path = record.output_path.resolve()
    if not _is_within(path, WORK_DIR) or not path.is_file():
        raise HTTPException(status_code=404, detail="Artifact not found.")
    return FileResponse(
        path,
        media_type="model/gltf-binary",
        filename=f"varian-{job_id}.glb",
    )


@app.get("/v1/3d/artifacts/{job_id}.png", name="download_preview")
async def download_preview(job_id: str, token: str) -> FileResponse:
    record = _jobs.get(job_id)
    if record is None or record.status != "completed" or record.preview_path is None:
        raise HTTPException(status_code=404, detail="Preview not found.")
    if not secrets.compare_digest(token, record.artifact_token):
        raise HTTPException(status_code=404, detail="Preview not found.")
    age = (datetime.now(timezone.utc) - record.updated_at).total_seconds()
    if age > ARTIFACT_TTL_SECONDS:
        raise HTTPException(status_code=410, detail="Preview URL expired.")
    path = record.preview_path.resolve()
    if not _is_within(path, WORK_DIR) or not path.is_file():
        raise HTTPException(status_code=404, detail="Preview not found.")
    return FileResponse(
        path,
        media_type="image/png",
        filename=f"varian-{job_id}.png",
    )


async def _run_job(record: JobRecord) -> None:
    source_path: Path | None = None
    raw_path: Path | None = None
    job_dir = (WORK_DIR / record.job_id).resolve()
    slot_acquired = False
    try:
        await _job_slots.acquire()
        slot_acquired = True
        if record.cancel_event.is_set():
            return
        _set_status(record, "processing", progress=2)
        job_dir.mkdir(parents=True, exist_ok=True)
        source_path = await asyncio.to_thread(_prepare_source_image, record.request, job_dir)
        if record.cancel_event.is_set():
            return
        raw_path = job_dir / "provider-output.glb"
        provider_name = (record.request.provider or DEFAULT_PROVIDER).strip().lower()
        provider = create_provider(provider_name)
        loop = asyncio.get_running_loop()

        def update_progress(value: float) -> None:
            loop.call_soon_threadsafe(_set_progress, record, value)

        generation_request = GenerationRequest(
            capability=record.request.capability,
            prompt=record.request.prompt.strip(),
            negative_prompt=record.request.negative_prompt,
            source_path=source_path,
            output_path=raw_path,
            mesh_quality=record.request.mesh_quality.strip().lower(),
            texture_mode=record.request.texture_mode.strip().lower(),
            triangle_budget=record.request.triangle_budget,
            seed=record.request.seed,
        )
        result = await asyncio.wait_for(
            asyncio.to_thread(
                provider.generate,
                generation_request,
                update_progress,
                record.cancel_event,
            ),
            timeout=JOB_TIMEOUT_SECONDS,
        )
        if record.cancel_event.is_set():
            return
        _set_progress(record, 88)
        final_path = job_dir / "model.glb"
        info = await asyncio.to_thread(
            postprocess_glb,
            result.output_path,
            final_path,
            triangle_budget=record.request.triangle_budget,
            texture_mode=record.request.texture_mode.strip().lower(),
            max_bytes=MAX_OUTPUT_BYTES,
        )
        if record.cancel_event.is_set():
            return
        preview_warning: str | None = None
        if record.request.generate_preview:
            candidate_preview_path = job_dir / "preview.png"
            try:
                await asyncio.to_thread(generate_preview, final_path, candidate_preview_path)
                record.preview_path = candidate_preview_path
            except PostprocessError as error:
                preview_warning = str(error)
        record.output_path = final_path
        record.artifact = _build_artifact(record, result.provider, info.byte_length)
        _set_status(record, "completed", progress=100)
        warnings = [warning for warning in (result.warning, preview_warning) if warning]
        if warnings:
            record.artifact["warning"] = " ".join(warnings)
    except asyncio.TimeoutError:
        _fail_record(record, "3D generation timed out.", "PROVIDER_TIMEOUT")
    except ProviderUnavailable as error:
        _fail_record(record, str(error), "PROVIDER_UNAVAILABLE")
    except (ProviderError, PostprocessError, GLBValidationError, ValueError) as error:
        _fail_record(record, str(error), "GENERATION_FAILED")
    except Exception:
        _fail_record(record, "3D worker failed unexpectedly.", "WORKER_ERROR")
    finally:
        if record.status == "canceled":
            _remove_tree(job_dir)
        elif record.status == "failed":
            _remove_tree(job_dir)
        elif record.output_path is not None:
            for path in (source_path, raw_path):
                if path is not None and path != record.output_path:
                    _safe_unlink(path)
        if slot_acquired:
            _job_slots.release()


async def _get_job(job_id: str) -> JobRecord:
    if not JOB_ID_PATTERN.fullmatch(job_id):
        raise HTTPException(status_code=404, detail="Job not found.")
    record = _jobs.get(job_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Job not found.")
    return record


async def _read_json(request: Request) -> dict[str, Any]:
    content_length = request.headers.get("content-length")
    if content_length is not None and int(content_length) > MAX_REQUEST_BYTES:
        raise HTTPException(status_code=413, detail="Request is too large.")
    body = await request.body()
    if len(body) > MAX_REQUEST_BYTES:
        raise HTTPException(status_code=413, detail="Request is too large.")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as error:
        raise HTTPException(status_code=400, detail="Request body must be valid JSON.") from error
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Request body must be a JSON object.")
    return payload


def _validate_job_request(job_request: CreateJobRequest) -> None:
    capability = job_request.capability.strip()
    if capability not in SUPPORTED_CAPABILITIES:
        raise ValueError("capability must be textTo3D or imageTo3D.")
    if job_request.job_id is not None and not JOB_ID_PATTERN.fullmatch(job_request.job_id.strip()):
        raise ValueError("jobId contains invalid characters.")
    provider = (job_request.provider or DEFAULT_PROVIDER).strip().lower()
    if provider not in SUPPORTED_PROVIDERS:
        raise ValueError("provider is not supported by this worker.")
    if job_request.target_format.strip().lower() != "glb":
        raise ValueError("Only GLB output is supported.")
    mesh_quality = job_request.mesh_quality.strip().lower()
    if mesh_quality not in {"draft", "balanced", "high"}:
        raise ValueError("meshQuality must be draft, balanced, or high.")
    texture_mode = job_request.texture_mode.strip().lower()
    if texture_mode not in {"none", "vertex_color", "pbr"}:
        raise ValueError("textureMode must be none, vertex_color, or pbr.")
    if job_request.source_image_base64 and job_request.source_image_url:
        raise ValueError("Provide sourceImageBase64 or sourceImageUrl, not both.")
    if job_request.source_image_base64 and len(job_request.source_image_base64) > MAX_REQUEST_BYTES:
        raise ValueError("sourceImageBase64 is too large.")
    if job_request.source_image_url:
        _validate_source_url(job_request.source_image_url)
    if capability == "imageTo3D" and not job_request.source_image_base64 and not job_request.source_image_url:
        raise ValueError("imageTo3D requires sourceImageBase64 or sourceImageUrl.")


def _prepare_source_image(job_request: CreateJobRequest, job_dir: Path) -> Path | None:
    value = job_request.source_image_base64
    if value:
        encoded = value.split(",", 1)[1] if value.lstrip().lower().startswith("data:image/") and "," in value else value
        try:
            data = base64.b64decode(encoded, validate=True)
        except (ValueError, base64.binascii.Error) as error:
            raise ValueError("sourceImageBase64 is invalid.") from error
        return _write_source_image(data, job_dir / "source-image")
    if job_request.source_image_url:
        if not ALLOW_SOURCE_URLS:
            raise ValueError("sourceImageUrl input is disabled on this worker.")
        data = _download_source_image(job_request.source_image_url)
        return _write_source_image(data, job_dir / "source-image")
    return None


def _write_source_image(data: bytes, path: Path) -> Path:
    if len(data) == 0 or len(data) > MAX_SOURCE_BYTES:
        raise ValueError("Source image exceeds the 8 MB limit.")
    if not _looks_like_image(data):
        raise ValueError("Source image must be PNG, JPEG, or WebP.")
    path.write_bytes(data)
    return path


def _download_source_image(url: str) -> bytes:
    _validate_source_url(url)
    try:
        with httpx.Client(
            follow_redirects=False,
            timeout=httpx.Timeout(30.0, connect=10.0),
            trust_env=False,
        ) as client:
            response = client.get(url, headers={"Accept": "image/*"})
            if response.status_code < 200 or response.status_code >= 300:
                raise ValueError(f"Source image download failed (HTTP {response.status_code}).")
            if len(response.content) > MAX_SOURCE_BYTES:
                raise ValueError("Source image exceeds the 8 MB limit.")
            return response.content
    except httpx.HTTPError as error:
        raise ValueError("Source image worker download failed.") from error


def _validate_source_url(value: str) -> None:
    parsed = urlparse(value.strip())
    if parsed.scheme not in {"https", "http"} or not parsed.hostname:
        raise ValueError("sourceImageUrl must be an HTTP(S) URL.")
    if parsed.username or parsed.password or parsed.fragment:
        raise ValueError("sourceImageUrl must not contain credentials or fragments.")
    host = parsed.hostname.lower()
    is_loopback_host = host in {"localhost", "127.0.0.1", "::1"}
    if parsed.scheme != "https" and not (is_loopback_host and ALLOW_LOOPBACK_SOURCE_URLS):
        raise ValueError("sourceImageUrl must use HTTPS unless it targets allowed loopback development services.")
    try:
        addresses = socket.getaddrinfo(host, parsed.port or (443 if parsed.scheme == "https" else 80), type=socket.SOCK_STREAM)
    except OSError as error:
        raise ValueError("sourceImageUrl host could not be resolved.") from error
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if ip.is_loopback and ALLOW_LOOPBACK_SOURCE_URLS:
            continue
        if ip.is_private or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
            raise ValueError("sourceImageUrl resolves to a private or reserved address.")


def _looks_like_image(data: bytes) -> bool:
    return (
        data.startswith(b"\x89PNG\r\n\x1a\n")
        or data.startswith(b"\xff\xd8\xff")
        or len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    )


def _build_artifact(record: JobRecord, provider: str, byte_length: int) -> dict[str, Any]:
    base = record.public_base_url.rstrip("/")
    url = f"{base}/v1/3d/artifacts/{record.job_id}.glb?token={record.artifact_token}"
    artifact: dict[str, Any] = {
        "kind": "model3d",
        "url": url,
        "reference": f"ai-3d-jobs/{record.job_id}/model.glb",
        "fileName": f"varian-{record.job_id}.glb",
        "mimeType": "model/gltf-binary",
        "byteLength": byte_length,
        "provider": provider,
    }
    preview_path = record.preview_path
    if preview_path is not None:
        try:
            resolved_preview = preview_path.resolve()
            if _is_within(resolved_preview, WORK_DIR) and resolved_preview.is_file():
                artifact["previewUrl"] = (
                    f"{base}/v1/3d/artifacts/{record.job_id}.png?token={record.artifact_token}"
                )
                artifact["previewReference"] = f"ai-3d-jobs/{record.job_id}/preview.png"
                artifact["previewFileName"] = f"varian-{record.job_id}.png"
                artifact["previewMimeType"] = "image/png"
                artifact["previewByteLength"] = resolved_preview.stat().st_size
        except OSError:
            pass
    return artifact


def _serialize_job(record: JobRecord) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "jobId": record.job_id,
        "status": record.status,
        "progress": round(record.progress, 2),
        "provider": (record.request.provider or DEFAULT_PROVIDER).strip().lower(),
    }
    if record.error:
        payload["error"] = {"code": record.error_code or "GENERATION_FAILED", "message": record.error}
        payload["message"] = record.error
    if record.artifact is not None:
        payload["artifact"] = record.artifact
    return payload


def _set_status(record: JobRecord, status: str, *, progress: float | None = None) -> None:
    if record.status == "completed" and status != "completed":
        return
    record.status = status
    if progress is not None:
        record.progress = max(0.0, min(100.0, float(progress)))
    record.updated_at = datetime.now(timezone.utc)


def _set_progress(record: JobRecord, value: float) -> None:
    if record.status in {"completed", "failed", "canceled"}:
        return
    record.progress = max(record.progress, min(99.0, float(value)))
    record.updated_at = datetime.now(timezone.utc)


def _fail_record(record: JobRecord, message: str, code: str) -> None:
    if record.status == "canceled":
        return
    record.error = message
    record.error_code = code
    _set_status(record, "failed", progress=record.progress)


def _require_auth(request: Request) -> None:
    if not WORKER_TOKEN:
        return
    header = request.headers.get("authorization", "").strip()
    if not header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Authentication is required.")
    token = header[7:].strip()
    if not secrets.compare_digest(token, WORKER_TOKEN):
        raise HTTPException(status_code=401, detail="Authentication is required.")


def _resolve_public_base_url(request: Request) -> str:
    if PUBLIC_BASE_URL:
        return PUBLIC_BASE_URL
    return str(request.base_url).rstrip("/")


def _trim_jobs_locked() -> None:
    if len(_jobs) <= 100:
        return
    completed = sorted(
        (record for record in _jobs.values() if record.status in {"completed", "failed", "canceled"}),
        key=lambda record: record.updated_at,
    )
    for record in completed[: max(0, len(_jobs) - 100)]:
        _jobs.pop(record.job_id, None)
        if record.output_path is not None:
            _remove_tree(record.output_path.parent)


def _remove_tree(path: Path) -> None:
    try:
        resolved = path.resolve()
        if _is_within(resolved, WORK_DIR) and resolved != WORK_DIR:
            shutil.rmtree(resolved, ignore_errors=True)
    except OSError:
        return


def _safe_unlink(path: Path) -> None:
    try:
        resolved = path.resolve()
        if _is_within(resolved, WORK_DIR):
            resolved.unlink(missing_ok=True)
    except OSError:
        return


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent.resolve())
        return True
    except ValueError:
        return False
