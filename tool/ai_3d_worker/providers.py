from __future__ import annotations

import os
import json
import random
import re
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import quote, urlsplit

import httpx

from .glb_utils import write_demo_glb


ProgressCallback = Callable[[float], None]


class ProviderError(RuntimeError):
    pass


class ProviderUnavailable(ProviderError):
    pass


_TRELLIS2_PIPELINE_MODELS: dict[str, tuple[str, ...]] = {
    "512": (
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_flow_model_512",
        "shape_slat_decoder",
        "tex_slat_flow_model_512",
        "tex_slat_decoder",
    ),
    "1024": (
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_flow_model_1024",
        "shape_slat_decoder",
        "tex_slat_flow_model_1024",
        "tex_slat_decoder",
    ),
    "1024_cascade": (
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_flow_model_512",
        "shape_slat_flow_model_1024",
        "shape_slat_decoder",
        "tex_slat_flow_model_1024",
        "tex_slat_decoder",
    ),
    "1536_cascade": (
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_flow_model_512",
        "shape_slat_flow_model_1024",
        "shape_slat_decoder",
        "tex_slat_flow_model_1024",
        "tex_slat_decoder",
    ),
}


def _trellis2_pipeline_type(mesh_quality: str) -> str:
    configured = os.getenv("TRELLIS2_PIPELINE_TYPE", "").strip().lower()
    pipeline_type = configured or {
        "draft": "512",
        "balanced": "1024_cascade",
        "high": "1536_cascade",
    }.get(mesh_quality, "1024_cascade")
    if pipeline_type not in _TRELLIS2_PIPELINE_MODELS:
        supported = ", ".join(_TRELLIS2_PIPELINE_MODELS)
        raise ProviderUnavailable(
            f"TRELLIS2_PIPELINE_TYPE must be one of: {supported}."
        )
    return pipeline_type


def _install_trellis2_dinov3_compatibility() -> None:
    module_names = (
        "trellis2.modules.image_feature_extractor",
        "trellis2.trainers.flow_matching.mixins.image_conditioned",
    )
    for module_name in module_names:
        try:
            module = __import__(module_name, fromlist=["DinoV3FeatureExtractor"])
        except ImportError:
            continue
        extractor_class = getattr(module, "DinoV3FeatureExtractor", None)
        if extractor_class is None or getattr(
            extractor_class,
            "_varian_dinov3_compatibility",
            False,
        ):
            continue
        original_extract_features = extractor_class.extract_features

        def extract_features(
            extractor: Any,
            image: Any,
            _original: Callable[..., Any] = original_extract_features,
        ) -> Any:
            model = extractor.model
            if getattr(model, "layer", None) is not None:
                return _original(extractor, image)
            backbone = getattr(model, "model", None)
            layers = getattr(backbone, "layer", None)
            if layers is None:
                return _original(extractor, image)
            object.__setattr__(model, "layer", layers)
            try:
                return _original(extractor, image)
            finally:
                object.__delattr__(model, "layer")

        extractor_class.extract_features = extract_features
        extractor_class._varian_dinov3_compatibility = True


@dataclass(frozen=True)
class GenerationRequest:
    capability: str
    prompt: str
    source_path: Path | None
    output_path: Path
    mesh_quality: str
    texture_mode: str
    triangle_budget: int
    seed: int
    negative_prompt: str | None = None


@dataclass(frozen=True)
class ProviderResult:
    provider: str
    output_path: Path
    warning: str | None = None


class ThreeDProvider:
    name = "unknown"

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        raise NotImplementedError


class DemoProvider(ThreeDProvider):
    name = "demo"

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        progress(25)
        info = write_demo_glb(request.output_path)
        progress(100)
        return ProviderResult(
            provider=self.name,
            output_path=request.output_path,
            warning=f"Smoke-test cube generated with {info.triangle_count} triangles.",
        )


class ComfyUIProvider(ThreeDProvider):
    name = "comfyui"

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        base_url = _comfy_base_url()
        workflow = _load_comfy_workflow()
        timeout = httpx.Timeout(30.0, connect=10.0)
        try:
            with httpx.Client(
                follow_redirects=False,
                timeout=timeout,
                trust_env=False,
            ) as client:
                source_image = None
                if request.source_path is not None:
                    source_image = self._upload_image(client, base_url, request.source_path)
                workflow = _replace_workflow_tokens(
                    workflow,
                    {
                        "{{prompt}}": request.prompt,
                        "{{negativePrompt}}": request.negative_prompt or "",
                        "{{sourceImage}}": source_image or "",
                        "{{seed}}": request.seed,
                        "{{triangleBudget}}": request.triangle_budget,
                        "{{capability}}": request.capability,
                        "{{meshQuality}}": request.mesh_quality,
                        "{{textureMode}}": request.texture_mode,
                    },
                )
                if "{{" in json.dumps(workflow, separators=(",", ":")):
                    raise ProviderError(
                        "ComfyUI workflow contains an unresolved template token."
                    )
                progress(15)
                prompt_id = self._queue_workflow(client, base_url, workflow)
                progress(25)
                descriptor = self._wait_for_output(
                    client,
                    base_url,
                    prompt_id,
                    progress,
                    cancel_event,
                )
                self._download_output(client, base_url, descriptor, request.output_path)
                progress(100)
        except ProviderError:
            raise
        except httpx.HTTPError as error:
            raise ProviderUnavailable(f"ComfyUI request failed: {error}") from error
        return ProviderResult(provider=self.name, output_path=request.output_path)

    def _upload_image(self, client: httpx.Client, base_url: str, path: Path) -> str:
        if not path.is_file():
            raise ProviderError("ComfyUI source image does not exist.")
        data = path.read_bytes()
        extension, content_type = _image_format(data)
        response = client.post(
            f"{base_url}/upload/image",
            files={
                "image": (
                    f"varian-source{extension}",
                    data,
                    content_type,
                )
            },
            data={"overwrite": "true"},
        )
        payload = _comfy_json(response, "image upload")
        name = _safe_comfy_component(payload.get("name"), "uploaded image name")
        subfolder = _safe_comfy_subfolder(payload.get("subfolder"))
        return f"{subfolder}/{name}" if subfolder else name

    def _queue_workflow(
        self,
        client: httpx.Client,
        base_url: str,
        workflow: dict[str, Any],
    ) -> str:
        response = client.post(
            f"{base_url}/prompt",
            json={
                "prompt": workflow,
                "client_id": os.getenv("COMFYUI_CLIENT_ID", "").strip() or str(uuid.uuid4()),
            },
        )
        payload = _comfy_json(response, "workflow submission")
        prompt_id = payload.get("prompt_id")
        if not isinstance(prompt_id, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,200}", prompt_id):
            detail = payload.get("error")
            raise ProviderError(
                f"ComfyUI did not return a valid prompt ID{f': {detail}' if detail else '.'}"
            )
        return prompt_id

    def _wait_for_output(
        self,
        client: httpx.Client,
        base_url: str,
        prompt_id: str,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> dict[str, str]:
        timeout_seconds = _comfy_float_env("COMFYUI_TIMEOUT_SECONDS", 1800.0, minimum=60.0)
        poll_seconds = _comfy_float_env("COMFYUI_POLL_SECONDS", 2.0, minimum=0.05)
        deadline = time.monotonic() + timeout_seconds
        output_node_id = os.getenv("COMFYUI_OUTPUT_NODE_ID", "").strip()
        while time.monotonic() < deadline:
            if cancel_event.is_set():
                self._interrupt(client, base_url)
                raise ProviderError("Generation was canceled.")
            response = client.get(f"{base_url}/history/{quote(prompt_id, safe='')}")
            payload = _comfy_json(response, "workflow history")
            entry = payload.get(prompt_id)
            if isinstance(entry, dict):
                descriptor = _find_comfy_output(entry, output_node_id)
                if descriptor is not None:
                    return descriptor
                status = entry.get("status")
                if isinstance(status, dict):
                    status_name = str(status.get("status_str", "")).lower()
                    if status_name in {"error", "failed", "canceled"}:
                        raise ProviderError("ComfyUI workflow failed.")
                    if status.get("completed") is True:
                        raise ProviderError("ComfyUI workflow completed without a GLB output.")
            elapsed = timeout_seconds - max(0.0, deadline - time.monotonic())
            progress(min(82.0, 25.0 + (elapsed / timeout_seconds) * 55.0))
            time.sleep(poll_seconds)
        raise ProviderError("ComfyUI workflow timed out before producing a GLB.")

    def _download_output(
        self,
        client: httpx.Client,
        base_url: str,
        descriptor: dict[str, str],
        output_path: Path,
    ) -> None:
        response = client.get(
            f"{base_url}/view",
            params={
                "filename": descriptor["filename"],
                "subfolder": descriptor["subfolder"],
                "type": descriptor["type"],
            },
        )
        if response.status_code < 200 or response.status_code >= 300:
            raise ProviderError(f"ComfyUI output download failed (HTTP {response.status_code}).")
        maximum = _comfy_int_env("COMFYUI_MAX_ARTIFACT_BYTES", 64 * 1024 * 1024, minimum=1)
        if len(response.content) == 0 or len(response.content) > maximum:
            raise ProviderError("ComfyUI GLB output exceeds the configured size limit.")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(response.content)

    def _interrupt(self, client: httpx.Client, base_url: str) -> None:
        try:
            client.post(f"{base_url}/interrupt")
        except httpx.HTTPError:
            return


class TripoSRProvider(ThreeDProvider):
    name = "triposr"
    _model: Any = None
    _device: str | None = None
    _lock = threading.Lock()

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        if request.source_path is None:
            raise ProviderError(
                "TripoSR requires an image reference. Configure a text-capable provider "
                "or enable the text-to-image reference stage."
            )
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        torch, model = self._load_model()
        try:
            from PIL import Image
        except ImportError as error:
            raise ProviderUnavailable("Install Pillow before using TripoSR.") from error

        progress(10)
        image = Image.open(request.source_path).convert("RGB")
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        resolution = {"draft": 128, "balanced": 192, "high": 256}.get(
            request.mesh_quality,
            192,
        )
        has_vertex_color = request.texture_mode != "none"
        model.renderer.set_chunk_size(int(os.getenv("TRIPOSR_CHUNK_SIZE", "8192")))
        progress(35)
        with torch.inference_mode():
            scene_codes = model(image, device=self._device)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        progress(78)
        mesh = model.extract_mesh(
            scene_codes,
            has_vertex_color=has_vertex_color,
            resolution=resolution,
        )[0]
        request.output_path.parent.mkdir(parents=True, exist_ok=True)
        mesh.export(str(request.output_path))
        progress(100)
        warning = None
        if request.texture_mode == "pbr":
            warning = "TripoSR output uses vertex color unless Blender texture baking is enabled."
        return ProviderResult(
            provider=self.name,
            output_path=request.output_path,
            warning=warning,
        )

    @classmethod
    def _load_model(cls) -> tuple[Any, Any]:
        try:
            import torch
            root = os.getenv("TRIPOSR_ROOT", "").strip()
            if root and root not in sys.path:
                sys.path.insert(0, root)
            from tsr.system import TSR
        except ImportError as error:
            raise ProviderUnavailable(
                "TripoSR is not installed. Set TRIPOSR_ROOT to the pinned checkout "
                "and install its dependencies from the worker README."
            ) from error

        with cls._lock:
            if cls._model is None:
                configured_device = os.getenv("TRIPOSR_DEVICE", "").strip()
                cls._device = configured_device or (
                    "cuda" if torch.cuda.is_available() else "cpu"
                )
                model_path = os.getenv("TRIPOSR_MODEL", "stabilityai/TripoSR")
                cls._model = TSR.from_pretrained(
                    model_path,
                    config_name=os.getenv("TRIPOSR_CONFIG", "config.yaml"),
                    weight_name=os.getenv("TRIPOSR_WEIGHTS", "model.ckpt"),
                )
                cls._model.to(cls._device)
        return torch, cls._model


class TrellisProvider(ThreeDProvider):
    name = "trellis"
    _pipelines: dict[str, Any] = {}
    _lock = threading.Lock()

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        try:
            import torch
            from PIL import Image
        except ImportError as error:
            raise ProviderUnavailable(
                "TRELLIS requires torch and Pillow. Install the optional TRELLIS dependencies."
            ) from error
        if not torch.cuda.is_available():
            raise ProviderUnavailable("TRELLIS requires a CUDA-capable worker.")

        if os.getenv("TRELLIS2_ROOT", "").strip():
            return self._generate_trellis2(request, progress, cancel_event, torch, Image)

        mode = "text" if request.capability == "textTo3D" and request.source_path is None else "image"
        pipeline = self._load_pipeline(mode)
        seed = request.seed if request.seed >= 0 else random.randint(0, 2**31 - 1)
        progress(12)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        if mode == "text":
            outputs = pipeline.run(request.prompt, seed=seed, formats=["gaussian", "mesh"])
        else:
            if request.source_path is None:
                raise ProviderError("TRELLIS image mode requires an image reference.")
            image = Image.open(request.source_path).convert("RGBA")
            outputs = pipeline.run(
                image,
                seed=seed,
                formats=["gaussian", "mesh"],
                preprocess_image=True,
            )
        progress(78)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        try:
            from trellis.utils import postprocessing_utils
        except ImportError as error:
            raise ProviderUnavailable(
                "TRELLIS postprocessing utilities are unavailable."
            ) from error
        texture_size = {"draft": 512, "balanced": 1024, "high": 2048}.get(
            request.mesh_quality,
            1024,
        )
        glb = postprocessing_utils.to_glb(
            outputs["gaussian"][0],
            outputs["mesh"][0],
            simplify=1.0,
            texture_size=texture_size,
        )
        request.output_path.parent.mkdir(parents=True, exist_ok=True)
        glb.export(str(request.output_path))
        progress(100)
        return ProviderResult(provider=self.name, output_path=request.output_path)

    def _generate_trellis2(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
        torch: Any,
        image_module: Any,
    ) -> ProviderResult:
        if request.source_path is None:
            raise ProviderError(
                "TRELLIS.2 is image-only. Provide a reference image for textTo3D "
                "or use the configured text-to-image reference stage."
            )
        pipeline_type = _trellis2_pipeline_type(request.mesh_quality)
        pipeline = self._load_trellis2_pipeline(pipeline_type)
        seed = request.seed if request.seed >= 0 else random.randint(0, 2**31 - 1)
        progress(12)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        image = image_module.open(request.source_path).convert("RGBA")
        try:
            mesh = pipeline.run(
                image,
                seed=seed,
                pipeline_type=pipeline_type,
                max_num_tokens=int(os.getenv("TRELLIS2_MAX_NUM_TOKENS", "49152")),
            )[0]
        except Exception as error:
            raise ProviderError(f"TRELLIS.2 generation failed: {error}") from error
        progress(78)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        try:
            from o_voxel import postprocess
        except ImportError as error:
            raise ProviderUnavailable(
                "TRELLIS.2 post-processing is unavailable. Install the pinned o-voxel package."
            ) from error
        texture_size = {"draft": 512, "balanced": 1024, "high": 2048}.get(
            request.mesh_quality,
            1024,
        )
        try:
            glb = postprocess.to_glb(
                vertices=mesh.vertices,
                faces=mesh.faces,
                attr_volume=mesh.attrs,
                coords=mesh.coords,
                attr_layout=mesh.layout,
                voxel_size=mesh.voxel_size,
                aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]],
                decimation_target=max(1000, request.triangle_budget),
                texture_size=texture_size,
                remesh=_env_bool("TRELLIS2_REMESH", False),
                remesh_band=float(os.getenv("TRELLIS2_REMESH_BAND", "1")),
                remesh_project=float(os.getenv("TRELLIS2_REMESH_PROJECT", "0.9")),
                verbose=False,
                use_tqdm=False,
            )
            request.output_path.parent.mkdir(parents=True, exist_ok=True)
            glb.export(str(request.output_path), extension_webp=True)
        except Exception as error:
            raise ProviderError(f"TRELLIS.2 GLB export failed: {error}") from error
        progress(100)
        return ProviderResult(provider=self.name, output_path=request.output_path)

    @classmethod
    def _load_pipeline(cls, mode: str) -> Any:
        with cls._lock:
            if mode in cls._pipelines:
                return cls._pipelines[mode]
            root = os.getenv("TRELLIS_ROOT", "").strip()
            if root and root not in sys.path:
                sys.path.insert(0, root)
            try:
                from trellis.pipelines import (
                    TrellisImageTo3DPipeline,
                    TrellisTextTo3DPipeline,
                )
            except ImportError as error:
                raise ProviderUnavailable(
                    "TRELLIS is not installed. Install the optional TRELLIS stack on Linux."
                ) from error
            model_name = os.getenv(
                "TRELLIS_TEXT_MODEL" if mode == "text" else "TRELLIS_IMAGE_MODEL",
                "microsoft/TRELLIS-text-base" if mode == "text" else "microsoft/TRELLIS-image-large",
            )
            pipeline_class = TrellisTextTo3DPipeline if mode == "text" else TrellisImageTo3DPipeline
            pipeline = pipeline_class.from_pretrained(model_name)
            pipeline.cuda()
            cls._pipelines[mode] = pipeline
            return pipeline

    @classmethod
    def _load_trellis2_pipeline(cls, pipeline_type: str | None = None) -> Any:
        pipeline_type = pipeline_type or _trellis2_pipeline_type("balanced")
        cache_key = f"trellis2:{pipeline_type}"
        with cls._lock:
            if cache_key in cls._pipelines:
                return cls._pipelines[cache_key]
            root = os.getenv("TRELLIS2_ROOT", "").strip()
            if root:
                for path in (root, os.path.join(root, "o-voxel")):
                    if path not in sys.path:
                        sys.path.insert(0, path)
            os.environ.setdefault("OPENCV_IO_ENABLE_OPENEXR", "1")
            os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
            hf_token = _huggingface_token()
            if _env_bool("TRELLIS2_HF_TOKEN_REQUIRED", False) and not hf_token:
                raise ProviderUnavailable(
                    "TRELLIS.2 requires HF_TOKEN with access to "
                    "facebook/dinov3-vitl16-pretrain-lvd1689m and briaai/RMBG-2.0."
                )
            try:
                from trellis2.pipelines import Trellis2ImageTo3DPipeline
            except ImportError as error:
                raise ProviderUnavailable(
                    "TRELLIS.2 is not installed. Install the pinned TRELLIS.2 stack on Linux."
                ) from error
            _install_trellis2_dinov3_compatibility()
            model_name = os.getenv("TRELLIS2_MODEL", "microsoft/TRELLIS.2-4B")
            model_revision = os.getenv("TRELLIS2_MODEL_REVISION", "").strip()
            model_path = model_name
            if model_revision:
                try:
                    from huggingface_hub import snapshot_download
                except ImportError as error:
                    raise ProviderUnavailable(
                        "TRELLIS.2 model pinning requires huggingface_hub."
                    ) from error
                try:
                    snapshot_args: dict[str, Any] = {
                        "repo_id": model_name,
                        "revision": model_revision,
                    }
                    if hf_token:
                        snapshot_args["token"] = hf_token
                    model_path = snapshot_download(**snapshot_args)
                except Exception as error:
                    raise ProviderUnavailable(
                        f"TRELLIS.2 model revision could not be downloaded: {error}"
                    ) from error
            try:
                original_model_names = getattr(
                    Trellis2ImageTo3DPipeline,
                    "model_names_to_load",
                    None,
                )
                had_model_names = "model_names_to_load" in Trellis2ImageTo3DPipeline.__dict__
                Trellis2ImageTo3DPipeline.model_names_to_load = list(
                    _TRELLIS2_PIPELINE_MODELS[pipeline_type]
                )
                try:
                    pipeline = Trellis2ImageTo3DPipeline.from_pretrained(model_path)
                finally:
                    if had_model_names:
                        Trellis2ImageTo3DPipeline.model_names_to_load = original_model_names
                    else:
                        del Trellis2ImageTo3DPipeline.model_names_to_load
                pipeline.cuda()
            except Exception as error:
                if _is_huggingface_access_error(error):
                    raise ProviderUnavailable(
                        "TRELLIS.2 requires HF_TOKEN with access to "
                        "facebook/dinov3-vitl16-pretrain-lvd1689m and briaai/RMBG-2.0."
                    ) from error
                raise ProviderUnavailable(f"TRELLIS.2 could not load its model: {error}") from error
            cls._pipelines[cache_key] = pipeline
            return pipeline


class Hunyuan3DProvider(ThreeDProvider):
    name = "hunyuan3d"
    _pipeline: Any = None
    _lock = threading.Lock()

    def generate(
        self,
        request: GenerationRequest,
        progress: ProgressCallback,
        cancel_event: threading.Event,
    ) -> ProviderResult:
        if request.source_path is None:
            raise ProviderError(
                "The configured Hunyuan3D pipeline requires an image reference."
            )
        try:
            import torch
        except ImportError as error:
            raise ProviderUnavailable("Hunyuan3D requires torch.") from error
        if not torch.cuda.is_available():
            raise ProviderUnavailable("Hunyuan3D requires a CUDA-capable worker.")
        pipeline = self._load_pipeline()
        progress(15)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        mesh = pipeline(image=str(request.source_path), num_inference_steps=30)[0]
        progress(85)
        if cancel_event.is_set():
            raise ProviderError("Generation was canceled.")
        request.output_path.parent.mkdir(parents=True, exist_ok=True)
        mesh.export(str(request.output_path))
        progress(100)
        return ProviderResult(provider=self.name, output_path=request.output_path)

    @classmethod
    def _load_pipeline(cls) -> Any:
        with cls._lock:
            if cls._pipeline is not None:
                return cls._pipeline
            root = os.getenv("HUNYUAN3D_ROOT", "").strip()
            if root and root not in sys.path:
                sys.path.insert(0, root)
            try:
                from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
            except ImportError as error:
                raise ProviderUnavailable(
                    "Hunyuan3D is not installed. Install the optional Hunyuan3D stack."
                ) from error
            cls._pipeline = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
                os.getenv("HUNYUAN3D_MODEL", "tencent/Hunyuan3D-2.1")
            )
            return cls._pipeline


def create_provider(name: str) -> ThreeDProvider:
    normalized = name.strip().lower()
    providers: dict[str, ThreeDProvider] = {
        "demo": DemoProvider(),
        "comfyui": ComfyUIProvider(),
        "triposr": TripoSRProvider(),
        "trellis": TrellisProvider(),
        "hunyuan3d": Hunyuan3DProvider(),
    }
    provider = providers.get(normalized)
    if provider is None:
        raise ProviderError(
            f"Unknown 3D provider '{name}'. Allowed providers: triposr, trellis, hunyuan3d, comfyui, demo."
        )
    return provider


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}

def _huggingface_token() -> str:
    return (
        os.getenv("HF_TOKEN", "").strip()
        or os.getenv("HUGGINGFACEHUB_API_TOKEN", "").strip()
    )

def _is_huggingface_access_error(error: BaseException) -> bool:
    text = str(error).lower()
    return any(
        marker in text
        for marker in (
            "gatedrepoerror",
            "cannot access gated repo",
            "access to model",
            "401 client error",
            "invalid username or password",
        )
    )


def _comfy_base_url() -> str:
    raw = os.getenv("COMFYUI_BASE_URL", "http://127.0.0.1:8188").strip()
    parsed = urlsplit(raw)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise ProviderUnavailable("COMFYUI_BASE_URL must be an http(s) URL without credentials or query parts.")
    if parsed.scheme == "http" and parsed.hostname.lower() not in {"localhost", "127.0.0.1", "::1"}:
        if not _env_bool("COMFYUI_ALLOW_INSECURE_HTTP", False):
            raise ProviderUnavailable("COMFYUI_BASE_URL must use HTTPS outside loopback development.")
    return raw.rstrip("/")


def _load_comfy_workflow() -> dict[str, Any]:
    configured = os.getenv("COMFYUI_WORKFLOW_FILE", "").strip()
    if not configured:
        raise ProviderUnavailable("Set COMFYUI_WORKFLOW_FILE to a ComfyUI API-format workflow JSON file.")
    path = Path(configured).expanduser().resolve()
    if not path.is_file():
        raise ProviderUnavailable("Configured COMFYUI_WORKFLOW_FILE does not exist.")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ProviderUnavailable("Configured COMFYUI_WORKFLOW_FILE is not valid JSON.") from error
    if not isinstance(value, dict) or not value:
        raise ProviderUnavailable("Configured ComfyUI workflow must be a non-empty JSON object.")
    return value


def _replace_workflow_tokens(value: Any, replacements: dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {key: _replace_workflow_tokens(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [_replace_workflow_tokens(item, replacements) for item in value]
    if not isinstance(value, str):
        return value
    if value in replacements:
        return replacements[value]
    result = value
    for token, replacement in replacements.items():
        result = result.replace(token, str(replacement))
    return result


def _find_comfy_output(entry: dict[str, Any], output_node_id: str) -> dict[str, str] | None:
    outputs = entry.get("outputs")
    if not isinstance(outputs, dict):
        return None
    nodes = outputs.items()
    if output_node_id:
        node = outputs.get(output_node_id)
        nodes = [(output_node_id, node)] if node is not None else []
    for _, node_output in nodes:
        descriptor = _walk_comfy_output(node_output)
        if descriptor is not None:
            return descriptor
    return None


def _walk_comfy_output(value: Any) -> dict[str, str] | None:
    if isinstance(value, dict):
        filename = value.get("filename")
        if isinstance(filename, str) and filename.lower().endswith(".glb"):
            safe_filename = _safe_comfy_component(filename, "output filename")
            subfolder = _safe_comfy_subfolder(value.get("subfolder"))
            output_type = str(value.get("type", "output")).strip().lower()
            if output_type not in {"output", "temp", "input"}:
                raise ProviderError("ComfyUI returned an unsupported output directory.")
            return {"filename": safe_filename, "subfolder": subfolder, "type": output_type}
        for item in value.values():
            descriptor = _walk_comfy_output(item)
            if descriptor is not None:
                return descriptor
    elif isinstance(value, list):
        for item in value:
            descriptor = _walk_comfy_output(item)
            if descriptor is not None:
                return descriptor
    return None


def _safe_comfy_component(value: Any, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,255}", value):
        raise ProviderError(f"ComfyUI returned an unsafe {label}.")
    return value


def _safe_comfy_subfolder(value: Any) -> str:
    if value is None or value == "":
        return ""
    if not isinstance(value, str):
        raise ProviderError("ComfyUI returned an unsafe output subfolder.")
    parts = value.replace("\\", "/").split("/")
    if any(not re.fullmatch(r"[A-Za-z0-9._-]{1,255}", part) for part in parts):
        raise ProviderError("ComfyUI returned an unsafe output subfolder.")
    return "/".join(parts)


def _image_format(data: bytes) -> tuple[str, str]:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png", "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg", "image/jpeg"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp", "image/webp"
    raise ProviderError("ComfyUI source image has an unsupported format.")


def _comfy_json(response: httpx.Response, operation: str) -> dict[str, Any]:
    if response.status_code < 200 or response.status_code >= 300:
        raise ProviderError(f"ComfyUI {operation} failed (HTTP {response.status_code}).")
    if len(response.content) > 2 * 1024 * 1024:
        raise ProviderError(f"ComfyUI {operation} response is too large.")
    try:
        payload = response.json()
    except ValueError as error:
        raise ProviderError(f"ComfyUI {operation} returned invalid JSON.") from error
    if not isinstance(payload, dict):
        raise ProviderError(f"ComfyUI {operation} returned an invalid object.")
    return payload


def _comfy_int_env(name: str, default: int, *, minimum: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as error:
        raise ProviderUnavailable(f"{name} must be an integer.") from error
    if value < minimum:
        raise ProviderUnavailable(f"{name} must be at least {minimum}.")
    return value


def _comfy_float_env(name: str, default: float, *, minimum: float) -> float:
    try:
        value = float(os.getenv(name, str(default)))
    except ValueError as error:
        raise ProviderUnavailable(f"{name} must be a number.") from error
    if value < minimum:
        raise ProviderUnavailable(f"{name} must be at least {minimum}.")
    return value
