from __future__ import annotations

import asyncio
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import httpx


_work_dir = tempfile.TemporaryDirectory()
os.environ.setdefault("PYTHONPATH", str(Path(__file__).resolve().parents[2]))
os.environ["AI_3D_DEFAULT_PROVIDER"] = "demo"
os.environ["AI_3D_WORK_DIR"] = _work_dir.name

from . import app as worker_module
from .app import CreateJobRequest, JobRecord, app
from .glb_utils import validate_glb_bytes, write_demo_glb
from .preview import validate_png_bytes
from .providers import (
    ComfyUIProvider,
    DemoProvider,
    GenerationRequest,
    ProviderError,
    TrellisProvider,
    _comfy_base_url,
    _find_comfy_output,
    _install_trellis2_dinov3_compatibility,
    _replace_workflow_tokens,
    _trellis2_pipeline_type,
)


class WorkerTest(unittest.TestCase):
    def test_demo_glb_is_valid_and_bounded(self) -> None:
        path = Path(_work_dir.name) / "demo.glb"
        info = write_demo_glb(path)
        self.assertEqual(info.triangle_count, 12)
        self.assertEqual(validate_glb_bytes(path.read_bytes()).triangle_count, 12)

    def test_trellis2_model_revision_is_used_for_pipeline_load(self) -> None:
        loaded_paths: list[str] = []

        class FakePipeline:
            @classmethod
            def from_pretrained(cls, path: str) -> "FakePipeline":
                loaded_paths.append(path)
                return cls()

            def cuda(self) -> "FakePipeline":
                return self

        trellis_module = type(sys)("trellis2")
        pipelines_module = type(sys)("trellis2.pipelines")
        pipelines_module.Trellis2ImageTo3DPipeline = FakePipeline
        trellis_module.pipelines = pipelines_module
        huggingface_module = type(sys)("huggingface_hub")

        def snapshot_download(*, repo_id: str, revision: str, **kwargs: object) -> str:
            self.assertEqual(repo_id, "microsoft/TRELLIS.2-4B")
            self.assertEqual(revision, "model-pin")
            return "C:/models/trellis2-model-pin"

        huggingface_module.snapshot_download = snapshot_download
        previous_pipelines = TrellisProvider._pipelines
        TrellisProvider._pipelines = {}
        try:
            with patch.dict(
                sys.modules,
                {
                    "trellis2": trellis_module,
                    "trellis2.pipelines": pipelines_module,
                    "huggingface_hub": huggingface_module,
                },
            ), patch.dict(
                os.environ,
                {
                    "TRELLIS2_MODEL": "microsoft/TRELLIS.2-4B",
                    "TRELLIS2_MODEL_REVISION": "model-pin",
                    "TRELLIS2_HF_TOKEN_REQUIRED": "false",
                },
                clear=False,
            ):
                TrellisProvider._load_trellis2_pipeline()
        finally:
            TrellisProvider._pipelines = previous_pipelines
        self.assertEqual(loaded_paths, ["C:/models/trellis2-model-pin"])

    def test_trellis2_512_pipeline_loads_only_512_model_family(self) -> None:
        loaded_model_names: list[tuple[str, ...]] = []

        class FakePipeline:
            @classmethod
            def from_pretrained(cls, path: str) -> "FakePipeline":
                loaded_model_names.append(tuple(cls.model_names_to_load))
                return cls()

            def cuda(self) -> "FakePipeline":
                return self

        trellis_module = type(sys)("trellis2")
        pipelines_module = type(sys)("trellis2.pipelines")
        pipelines_module.Trellis2ImageTo3DPipeline = FakePipeline
        trellis_module.pipelines = pipelines_module
        previous_pipelines = TrellisProvider._pipelines
        TrellisProvider._pipelines = {}
        try:
            with patch.dict(
                sys.modules,
                {
                    "trellis2": trellis_module,
                    "trellis2.pipelines": pipelines_module,
                },
            ), patch.dict(
                os.environ,
                {
                    "TRELLIS2_MODEL_REVISION": "",
                    "TRELLIS2_HF_TOKEN_REQUIRED": "false",
                },
                clear=False,
            ):
                TrellisProvider._load_trellis2_pipeline("512")
        finally:
            TrellisProvider._pipelines = previous_pipelines

        self.assertEqual(
            loaded_model_names,
            [
                (
                    "sparse_structure_flow_model",
                    "sparse_structure_decoder",
                    "shape_slat_flow_model_512",
                    "shape_slat_decoder",
                    "tex_slat_flow_model_512",
                    "tex_slat_decoder",
                )
            ],
        )

    def test_trellis2_dinov3_compatibility_supports_nested_encoder_layers(self) -> None:
        class FakeBackbone:
            layer = ("nested-layer",)

        class FakeModel:
            def __init__(self) -> None:
                self.model = FakeBackbone()

        class FakeExtractor:
            def __init__(self) -> None:
                self.model = FakeModel()

            def extract_features(self, image: object) -> tuple[str, ...]:
                return self.model.layer

        image_feature_module = type(sys)("trellis2.modules.image_feature_extractor")
        image_feature_module.DinoV3FeatureExtractor = FakeExtractor
        image_conditioned_module = type(sys)(
            "trellis2.trainers.flow_matching.mixins.image_conditioned"
        )
        image_conditioned_module.DinoV3FeatureExtractor = FakeExtractor
        with patch.dict(
            sys.modules,
            {
                "trellis2.modules.image_feature_extractor": image_feature_module,
                "trellis2.trainers.flow_matching.mixins.image_conditioned": image_conditioned_module,
            },
            clear=False,
        ):
            _install_trellis2_dinov3_compatibility()
            extractor = FakeExtractor()
            self.assertEqual(extractor.extract_features(None), ("nested-layer",))
            self.assertFalse(hasattr(extractor.model, "layer"))

    def test_trellis2_rejects_unknown_pipeline_type(self) -> None:
        with patch.dict(
            os.environ,
            {"TRELLIS2_PIPELINE_TYPE": "unsupported"},
            clear=False,
        ):
            with self.assertRaisesRegex(ProviderError, "TRELLIS2_PIPELINE_TYPE"):
                _trellis2_pipeline_type("draft")

    def test_trellis2_requires_huggingface_token_when_configured(self) -> None:
        previous_pipelines = TrellisProvider._pipelines
        TrellisProvider._pipelines = {}
        try:
            with patch.dict(
                os.environ,
                {
                    "TRELLIS2_HF_TOKEN_REQUIRED": "true",
                    "HF_TOKEN": "",
                    "HUGGINGFACEHUB_API_TOKEN": "",
                },
                clear=False,
            ):
                with self.assertRaisesRegex(ProviderError, "HF_TOKEN"):
                    TrellisProvider._load_trellis2_pipeline()
        finally:
            TrellisProvider._pipelines = previous_pipelines

    def test_job_lifecycle_returns_a_bounded_artifact(self) -> None:
        asyncio.run(self._job_lifecycle())

    async def _job_lifecycle(self) -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
            response = await client.post(
                "/v1/3d/jobs",
                json={
                    "jobId": "test-worker-job",
                    "projectId": "local",
                    "capability": "textTo3D",
                    "prompt": "a blue chair",
                    "provider": "demo",
                    "meshQuality": "draft",
                    "textureMode": "pbr",
                    "triangleBudget": 100000,
                },
            )
            self.assertEqual(response.status_code, 202)
            job = await _wait_for_terminal(client, "test-worker-job")
            self.assertEqual(job["status"], "completed")
            artifact = job["artifact"]
            downloaded = await client.get(artifact["url"])
            self.assertEqual(downloaded.status_code, 200)
            self.assertEqual(validate_glb_bytes(downloaded.content).triangle_count, 12)
            preview = await client.get(artifact["previewUrl"])
            self.assertEqual(preview.status_code, 200)
            self.assertEqual(validate_png_bytes(preview.content), (512, 512))
            denied = await client.get(artifact["url"].replace("token=", "token=invalid"))
            self.assertEqual(denied.status_code, 404)
            denied_preview = await client.get(artifact["previewUrl"].replace("token=", "token=invalid"))
            self.assertEqual(denied_preview.status_code, 404)
            repeated = await client.post("/v1/3d/jobs/test-worker-job/retry")
            self.assertEqual(repeated.status_code, 200)
            self.assertEqual(repeated.json()["artifact"]["url"], artifact["url"])

    def test_failed_job_can_be_retried_after_the_previous_task_finishes(self) -> None:
        asyncio.run(self._retry_failed_job())

    async def _retry_failed_job(self) -> None:
        provider = _FailOnceProvider()
        transport = httpx.ASGITransport(app=app)
        with patch.object(worker_module, "create_provider", return_value=provider):
            async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
                response = await client.post(
                    "/v1/3d/jobs",
                    json={
                        "jobId": "retry-worker-job",
                        "projectId": "local",
                        "capability": "textTo3D",
                        "prompt": "a blue chair",
                        "provider": "demo",
                    },
                )
                self.assertEqual(response.status_code, 202)
                failed = await _wait_for_terminal(client, "retry-worker-job")
                self.assertEqual(failed["status"], "failed")

                retry = await client.post("/v1/3d/jobs/retry-worker-job/retry")
                self.assertEqual(retry.status_code, 202)
                self.assertIn(retry.json()["status"], {"queued", "processing"})
                completed = await _wait_for_terminal(client, "retry-worker-job")
                self.assertEqual(completed["status"], "completed")
                self.assertEqual(provider.calls, 2)


    def test_image_job_requires_an_image_source(self) -> None:
        asyncio.run(self._invalid_image_job())

    async def _invalid_image_job(self) -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
            response = await client.post(
                "/v1/3d/jobs",
                json={"projectId": "local", "capability": "imageTo3D", "prompt": "chair", "provider": "demo"},
            )
            self.assertEqual(response.status_code, 400)

    def test_worker_authentication_is_required_when_configured(self) -> None:
        asyncio.run(self._authentication_checks())

    async def _authentication_checks(self) -> None:
        transport = httpx.ASGITransport(app=app)
        with patch.object(worker_module, "WORKER_TOKEN", "worker-secret"):
            async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
                missing = await client.get("/v1/health")
                self.assertEqual(missing.status_code, 401)
                invalid = await client.get("/v1/health", headers={"Authorization": "Bearer wrong"})
                self.assertEqual(invalid.status_code, 401)
                valid = await client.get("/v1/health", headers={"Authorization": "Bearer worker-secret"})
                self.assertEqual(valid.status_code, 200)

    def test_request_size_and_job_id_path_traversal_are_rejected(self) -> None:
        asyncio.run(self._request_validation_checks())

    async def _request_validation_checks(self) -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
            traversal = await client.post(
                "/v1/3d/jobs",
                json={
                    "jobId": "../escape",
                    "projectId": "local",
                    "capability": "textTo3D",
                    "prompt": "chair",
                    "provider": "demo",
                },
            )
            self.assertEqual(traversal.status_code, 400)
            oversized = await client.post(
                "/v1/3d/jobs",
                content=b"x" * (worker_module.MAX_REQUEST_BYTES + 1),
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(oversized.status_code, 413)

    def test_source_url_and_image_size_validation_block_ssrf_inputs(self) -> None:
        with self.assertRaises(ValueError):
            worker_module._validate_source_url("https://user:password@example.com/image.png")
        with self.assertRaises(ValueError):
            worker_module._validate_source_url("https://example.com/image.png#fragment")
        private_address = [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("10.0.0.8", 443))]
        with patch.object(worker_module.socket, "getaddrinfo", return_value=private_address):
            with self.assertRaises(ValueError):
                worker_module._validate_source_url("https://images.example.com/image.png")

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source-image"
            written = worker_module._write_source_image(b"\x89PNG\r\n\x1a\n", path)
            self.assertEqual(written, path)
            with self.assertRaises(ValueError):
                worker_module._write_source_image(b"not-an-image", path)
            with self.assertRaises(ValueError):
                worker_module._write_source_image(
                    b"\x89PNG\r\n\x1a\n" + b"x" * worker_module.MAX_SOURCE_BYTES,
                    path,
                )

    def test_artifact_path_and_expiry_are_enforced(self) -> None:
        asyncio.run(self._artifact_security_checks())

    async def _artifact_security_checks(self) -> None:
        request = CreateJobRequest(
            projectId="local",
            capability="textTo3D",
            prompt="chair",
            provider="demo",
        )
        job_id = "artifact-security-job"
        record = JobRecord(
            job_id=job_id,
            request=request,
            public_base_url="http://worker",
            artifact_token="artifact-secret",
            status="completed",
        )
        with tempfile.TemporaryDirectory() as directory:
            outside = Path(directory) / "outside.glb"
            outside.write_bytes(b"outside")
            record.output_path = outside
            worker_module._jobs[job_id] = record
            try:
                transport = httpx.ASGITransport(app=app)
                async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
                    outside_response = await client.get(
                        f"/v1/3d/artifacts/{job_id}.glb?token=artifact-secret"
                    )
                    self.assertEqual(outside_response.status_code, 404)

                    inside = worker_module.WORK_DIR / f"{job_id}.glb"
                    inside.write_bytes(b"inside")
                    record.output_path = inside
                    record.updated_at = datetime.now(timezone.utc) - timedelta(
                        seconds=worker_module.ARTIFACT_TTL_SECONDS + 1,
                    )
                    expired_response = await client.get(
                        f"/v1/3d/artifacts/{job_id}.glb?token=artifact-secret"
                    )
                    self.assertEqual(expired_response.status_code, 410)
                    inside.unlink(missing_ok=True)
            finally:
                worker_module._jobs.pop(job_id, None)

    def test_comfyui_workflow_tokens_and_output_paths_are_bounded(self) -> None:
        workflow = _replace_workflow_tokens(
            {"prompt": "{{prompt}}", "seed": "{{seed}}", "nested": ["{{sourceImage}}"]},
            {"{{prompt}}": "chair", "{{seed}}": 7, "{{sourceImage}}": "source.png"},
        )
        self.assertEqual(workflow, {"prompt": "chair", "seed": 7, "nested": ["source.png"]})
        self.assertEqual(
            _find_comfy_output(
                {
                    "outputs": {
                        "42": {
                            "files": [
                                {"filename": "model.glb", "subfolder": "draft", "type": "output"}
                            ]
                        }
                    }
                },
                "42",
            ),
            {"filename": "model.glb", "subfolder": "draft", "type": "output"},
        )
        with self.assertRaises(ProviderError):
            _find_comfy_output(
                {"outputs": {"42": {"files": [{"filename": "../escape.glb"}]}}},
                "42",
            )
        with patch.dict(os.environ, {"COMFYUI_BASE_URL": "https://comfy.example.com/v1"}):
            self.assertEqual(_comfy_base_url(), "https://comfy.example.com/v1")
        with patch.dict(os.environ, {"COMFYUI_BASE_URL": "http://comfy.example.com"}):
            with self.assertRaises(ProviderError):
                _comfy_base_url()

    def test_comfyui_provider_runs_upload_prompt_history_and_glb_download(self) -> None:
        asyncio.run(self._comfyui_provider_lifecycle())

    async def _comfyui_provider_lifecycle(self) -> None:
        class FakeResponse:
            def __init__(self, payload=None, content=b"", status_code=200):
                self._payload = payload
                self.content = content
                self.status_code = status_code

            def json(self):
                return self._payload

        class FakeClient:
            def __init__(self, output_bytes):
                self.output_bytes = output_bytes
                self.workflow = None
                self.uploaded = False

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc_value, traceback):
                return False

            def post(self, url, **kwargs):
                if url.endswith("/upload/image"):
                    self.uploaded = True
                    return FakeResponse({"name": "source.png", "subfolder": ""})
                if url.endswith("/prompt"):
                    self.workflow = kwargs["json"]["prompt"]
                    return FakeResponse({"prompt_id": "queue-1"})
                return FakeResponse({})

            def get(self, url, **kwargs):
                if "/history/queue-1" in url:
                    return FakeResponse(
                        {
                            "queue-1": {
                                "status": {"completed": True, "status_str": "success"},
                                "outputs": {
                                    "42": {
                                        "files": [
                                            {"filename": "model.glb", "subfolder": "", "type": "output"}
                                        ]
                                    }
                                },
                            }
                        }
                    )
                if url.endswith("/view"):
                    return FakeResponse(content=self.output_bytes)
                raise AssertionError(f"unexpected ComfyUI GET: {url}")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow_path = root / "workflow.json"
            workflow_path.write_text(
                json.dumps(
                    {
                        "1": {"class_type": "Text3D", "inputs": {"prompt": "{{prompt}}"}},
                        "42": {"class_type": "SaveGLB", "inputs": {"filename": "model.glb"}},
                    }
                ),
                encoding="utf-8",
            )
            source_path = root / "source-image"
            source_path.write_bytes(b"\x89PNG\r\n\x1a\n")
            expected_path = root / "expected.glb"
            write_demo_glb(expected_path)
            output_path = root / "provider-output.glb"
            fake_client = FakeClient(expected_path.read_bytes())
            request = GenerationRequest(
                capability="imageTo3D",
                prompt="a blue chair",
                source_path=source_path,
                output_path=output_path,
                mesh_quality="draft",
                texture_mode="pbr",
                triangle_budget=100000,
                seed=7,
            )
            progress_values = []
            with patch.dict(
                os.environ,
                {
                    "COMFYUI_BASE_URL": "http://127.0.0.1:8188",
                    "COMFYUI_WORKFLOW_FILE": str(workflow_path),
                    "COMFYUI_OUTPUT_NODE_ID": "42",
                    "COMFYUI_POLL_SECONDS": "0.05",
                    "COMFYUI_TIMEOUT_SECONDS": "60",
                },
                clear=False,
            ), patch("tool.ai_3d_worker.providers.httpx.Client", return_value=fake_client):
                result = ComfyUIProvider().generate(
                    request,
                    progress_values.append,
                    threading.Event(),
                )
            self.assertEqual(result.provider, "comfyui")
            self.assertEqual(output_path.read_bytes(), expected_path.read_bytes())
            self.assertTrue(fake_client.uploaded)
            self.assertEqual(fake_client.workflow["1"]["inputs"]["prompt"], "a blue chair")
            self.assertTrue(progress_values[-1] == 100)


async def _wait_for_terminal(client: httpx.AsyncClient, job_id: str) -> dict:
    for _ in range(200):
        await asyncio.sleep(0.05)
        response = await client.get(f"/v1/3d/jobs/{job_id}")
        payload = response.json()
        if payload["status"] in {"completed", "failed", "canceled"}:
            return payload
    raise AssertionError(f"Job {job_id} did not reach a terminal state.")


class _FailOnceProvider:
    name = "demo"

    def __init__(self) -> None:
        self.calls = 0
        self._demo = DemoProvider()

    def generate(self, request, progress, cancel_event):
        self.calls += 1
        if self.calls == 1:
            raise ProviderError("intentional first-attempt failure")
        return self._demo.generate(request, progress, cancel_event)


if __name__ == "__main__":
    unittest.main()
