#!/usr/bin/env python3
"""Local OpenAI-compatible bridge for a ComfyUI LTX image-to-video workflow."""

from __future__ import annotations

import argparse
import copy
import ctypes
from ctypes import wintypes
import hashlib
import hmac
import http.server
import json
import mimetypes
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from email.parser import BytesParser
from email.policy import default as email_default
from pathlib import Path
from typing import Any, Callable, Mapping

PROFILE_ID = "ltx-video-0.9.5-2b-low-vram"
EXPECTED_CHECKPOINT = "ltx-video-2b-v0.9.5.safetensors"
DEFAULT_BRIDGE_HOST = "127.0.0.1"
DEFAULT_BRIDGE_PORT = 20129
DEFAULT_COMFY_HOST = "127.0.0.1"
DEFAULT_COMFY_PORT = 8188
DEFAULT_POLL_SECONDS = 1.0
DEFAULT_JOB_TIMEOUT_SECONDS = 300.0
DEFAULT_BRIDGE_LEASE_SECONDS = 0
JOB_RETENTION_SECONDS = 15 * 60
MAX_TRACKED_JOBS = 64
MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_REQUEST_BYTES = 10 * 1024 * 1024
MAX_JSON_BYTES = 256 * 1024
MAX_VIDEO_BYTES = 100 * 1024 * 1024
MAX_PROMPT_CHARS = 4000
LOW_VRAM_FPS = 8
LOW_VRAM_DURATIONS = {"4": 33}
DEFAULT_NEGATIVE_PROMPT = "static, blurry, distorted, low quality, watermark, text"
ALLOWED_IMAGE_TYPES = {
    "image/png": b"\x89PNG\r\n\x1a\n",
    "image/jpeg": b"\xff\xd8\xff",
    "image/webp": b"RIFF",
}
REQUEST_ID_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
)


class BridgeError(Exception):
    def __init__(self, code: str, message: str, status: int = 500):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


class ComfyError(BridgeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        raise urllib.error.HTTPError(req.full_url, code, "Redirects are disabled", headers, fp)


_NO_REDIRECT_OPENER = urllib.request.build_opener(NoRedirect)


def _bounded_read(stream: Any, limit: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = stream.read(min(64 * 1024, limit - total + 1))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise BridgeError(
                "VIDEO_PROVIDER_RESPONSE_TOO_LARGE",
                "Provider response exceeded the configured size limit.",
                502,
            )
        chunks.append(chunk)
    return b"".join(chunks)


def _json_bytes(value: Any, limit: int = MAX_JSON_BYTES) -> bytes:
    try:
        data = json.dumps(value, separators=(",", ":")).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise BridgeError("VIDEO_PROVIDER_ERROR", "Provider returned invalid JSON.", 502) from exc
    if len(data) > limit:
        raise BridgeError("VIDEO_PROVIDER_RESPONSE_TOO_LARGE", "Provider JSON response is too large.", 502)
    return data


def _decode_json(data: bytes) -> Mapping[str, Any]:
    if len(data) > MAX_JSON_BYTES:
        raise BridgeError("VIDEO_PROVIDER_RESPONSE_TOO_LARGE", "Provider JSON response is too large.", 502)
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BridgeError("VIDEO_UNSUPPORTED_PROVIDER", "ComfyUI returned malformed JSON.", 502) from exc
    if not isinstance(value, dict):
        raise BridgeError("VIDEO_UNSUPPORTED_PROVIDER", "ComfyUI returned an invalid JSON object.", 502)
    return value


def _safe_text(data: bytes) -> str | None:
    text = data.decode("utf-8", errors="replace").strip()
    if not text:
        return None
    return text[:240]


def _valid_request_id(value: str) -> str:
    if not value or len(value) > 256 or any(char not in REQUEST_ID_CHARS for char in value):
        raise BridgeError("VIDEO_UNSUPPORTED_PROVIDER", "Provider returned an invalid request ID.", 502)
    return value


def _valid_relative_component(value: str, label: str) -> str:
    if not value or len(value) > 512 or ":" in value or any(ord(char) < 32 for char in value):
        raise BridgeError("VIDEO_DOWNLOAD_ERROR", f"Provider returned an invalid {label}.", 502)
    normalized = value.replace("\\", "/")
    parts = normalized.split("/")
    if normalized.startswith("/") or any(part in ("", ".", "..") for part in parts):
        raise BridgeError("VIDEO_DOWNLOAD_ERROR", f"Provider returned an unsafe {label}.", 502)
    return normalized


def _valid_loopback_url(raw: str, default_port: int) -> str:
    try:
        parsed = urllib.parse.urlparse(raw.strip())
        port = parsed.port if parsed.port is not None else default_port
    except ValueError as exc:
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "ComfyUI URL is invalid.", 400) from exc
    if parsed.scheme not in ("http", "https") or parsed.username or parsed.password:
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "ComfyUI URL must be a loopback HTTP(S) URL.", 400)
    if parsed.query or parsed.fragment or not parsed.hostname:
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "ComfyUI URL cannot contain query parameters.", 400)
    host = parsed.hostname.lower()
    if host not in {"localhost", "127.0.0.1", "::1"}:
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "ComfyUI URL must target localhost.", 400)
    if port < 1 or port > 65535:
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "ComfyUI port is invalid.", 400)
    canonical_host = "::1" if host == "::1" else "127.0.0.1"
    formatted_host = f"[{canonical_host}]" if ":" in canonical_host else canonical_host
    return f"{parsed.scheme}://{formatted_host}:{port}"


def _comfy_command(python: Path, main: Path, port: int) -> list[str]:
    command = [
        str(python),
        str(main),
        "--listen",
        DEFAULT_COMFY_HOST,
        "--port",
        str(port),
    ]
    if python.parent.name.lower() == "python_embeded":
        command.append("--windows-standalone-build")
    return command


def _comfy_environment(token_env: str = "VARIAN_COMFYUI_BRIDGE_TOKEN") -> dict[str, str]:
    environment = os.environ.copy()
    environment.pop(token_env, None)
    return environment


_MP4_CONTAINER_TYPES = {
    b"edts",
    b"mdia",
    b"meta",
    b"minf",
    b"moof",
    b"moov",
    b"mvex",
    b"stbl",
    b"trak",
    b"traf",
}


def _mp4_boxes(
    data: bytes,
    start: int,
    end: int,
) -> list[tuple[bytes, int, int]] | None:
    boxes: list[tuple[bytes, int, int]] = []
    offset = start
    while offset < end:
        if end - offset < 8:
            return None
        size = int.from_bytes(data[offset : offset + 4], "big")
        box_type = data[offset + 4 : offset + 8]
        header_size = 8
        if size == 1:
            if end - offset < 16:
                return None
            size = int.from_bytes(data[offset + 8 : offset + 16], "big")
            header_size = 16
        elif size == 0:
            size = end - offset
        if size < header_size or offset + size > end:
            return None
        boxes.append((box_type, offset + header_size, offset + size))
        offset += size
    return boxes


def _nested_mp4_boxes(
    data: bytes,
    start: int,
    end: int,
    wanted: bytes,
) -> list[tuple[bytes, int, int]]:
    found: list[tuple[bytes, int, int]] = []
    boxes = _mp4_boxes(data, start, end) or []
    for box_type, payload_start, payload_end in boxes:
        box = (box_type, payload_start, payload_end)
        if box_type == wanted:
            found.append(box)
        if box_type in _MP4_CONTAINER_TYPES:
            found.extend(_nested_mp4_boxes(data, payload_start, payload_end, wanted))
    return found


def _has_h264_sample_entry(data: bytes, start: int, end: int) -> bool:
    if end - start < 8:
        return False
    entry_count = int.from_bytes(data[start + 4 : start + 8], "big")
    offset = start + 8
    for _ in range(entry_count):
        entries = _mp4_boxes(data, offset, end)
        if not entries:
            return False
        box_type, _, entry_end = entries[0]
        if box_type in {b"avc1", b"avc3"}:
            return True
        offset = entry_end
    return False


def _is_mp4(data: bytes) -> bool:
    if len(data) < 12:
        return False
    boxes = _mp4_boxes(data, 0, len(data))
    if not boxes or boxes[0][0] != b"ftyp":
        return False
    moov = next((box for box in boxes if box[0] == b"moov"), None)
    if moov is None or not any(
        box_type == b"mdat" and payload_end > payload_start
        for box_type, payload_start, payload_end in boxes
    ):
        return False
    for _, trak_start, trak_end in _nested_mp4_boxes(data, moov[1], moov[2], b"trak"):
        handlers = _nested_mp4_boxes(data, trak_start, trak_end, b"hdlr")
        is_video = any(
            handler_end - handler_start >= 12
            and data[handler_start + 8 : handler_start + 12] == b"vide"
            for _, handler_start, handler_end in handlers
        )
        if not is_video:
            continue
        for _, stsd_start, stsd_end in _nested_mp4_boxes(data, trak_start, trak_end, b"stsd"):
            if _has_h264_sample_entry(data, stsd_start, stsd_end):
                return True
    return False


class _JobObjectBasicLimitInformation(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_longlong),
        ("PerJobUserTimeLimit", ctypes.c_longlong),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class _IoCounters(ctypes.Structure):
    _fields_ = [
        ("ReadOperationCount", ctypes.c_ulonglong),
        ("WriteOperationCount", ctypes.c_ulonglong),
        ("OtherOperationCount", ctypes.c_ulonglong),
        ("ReadTransferCount", ctypes.c_ulonglong),
        ("WriteTransferCount", ctypes.c_ulonglong),
        ("OtherTransferCount", ctypes.c_ulonglong),
    ]


class _JobObjectExtendedLimitInformation(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", _JobObjectBasicLimitInformation),
        ("IoInfo", _IoCounters),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


class _WindowsJobObject:
    _KILL_ON_CLOSE = 0x2000
    _EXTENDED_LIMIT_INFORMATION = 9
    _PROCESS_SET_QUOTA = 0x0100
    _PROCESS_TERMINATE = 0x0001
    _PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

    def __init__(self) -> None:
        self._handle: Any | None = None
        if os.name != "nt":
            return
        kernel = ctypes.windll.kernel32
        kernel.CreateJobObjectW.restype = wintypes.HANDLE
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.SetInformationJobObject.restype = wintypes.BOOL
        kernel.AssignProcessToJobObject.restype = wintypes.BOOL
        handle = kernel.CreateJobObjectW(None, None)
        if not handle:
            return
        info = _JobObjectExtendedLimitInformation()
        info.BasicLimitInformation.LimitFlags = self._KILL_ON_CLOSE
        if not kernel.SetInformationJobObject(
            handle,
            self._EXTENDED_LIMIT_INFORMATION,
            ctypes.byref(info),
            ctypes.sizeof(info),
        ):
            kernel.CloseHandle(handle)
            return
        self._handle = handle

    def assign(self, pid: int) -> bool:
        if self._handle is None or os.name != "nt":
            return False
        kernel = ctypes.windll.kernel32
        process = kernel.OpenProcess(
            self._PROCESS_SET_QUOTA
            | self._PROCESS_TERMINATE
            | self._PROCESS_QUERY_LIMITED_INFORMATION,
            False,
            pid,
        )
        if not process:
            return False
        try:
            return bool(kernel.AssignProcessToJobObject(self._handle, process))
        finally:
            kernel.CloseHandle(process)

    def close(self) -> None:
        handle = self._handle
        self._handle = None
        if handle is not None and os.name == "nt":
            ctypes.windll.kernel32.CloseHandle(handle)


def _validate_image(data: bytes, content_type: str) -> str:
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise BridgeError("VIDEO_SOURCE_ERROR", "The selected image is empty or too large.", 422)
    normalized = content_type.split(";", 1)[0].strip().lower()
    signature = ALLOWED_IMAGE_TYPES.get(normalized)
    valid = signature is not None and data.startswith(signature)
    if normalized == "image/webp":
        valid = data.startswith(b"RIFF") and data[8:12] == b"WEBP"
    if not valid:
        raise BridgeError(
            "VIDEO_SOURCE_ERROR",
            "Use a valid PNG, JPEG, or WebP image.",
            422,
        )
    return normalized


def _multipart_body(fields: Mapping[str, str], files: Mapping[str, tuple[str, str, bytes]]) -> tuple[str, bytes]:
    boundary = "----VarianBridge" + secrets.token_hex(16)
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode("utf-8"),
                b"\r\n",
            ]
        )
    for name, (filename, content_type, data) in files.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode(),
                f"Content-Type: {content_type}\r\n\r\n".encode(),
                data,
                b"\r\n",
            ]
        )
    chunks.append(f"--{boundary}--\r\n".encode())
    return f"multipart/form-data; boundary={boundary}", b"".join(chunks)


class ComfyClient:
    def __init__(self, base_url: str, timeout: float = 20.0):
        self.base_url = _valid_loopback_url(base_url, DEFAULT_COMFY_PORT)
        self.timeout = timeout

    def request(self, method: str, path: str, body: bytes | None = None, headers: Mapping[str, str] | None = None, limit: int = MAX_JSON_BYTES) -> tuple[int, Mapping[str, str], bytes]:
        if not path.startswith("/") or "?" in path and any(value in path for value in ("..", "\\")):
            raise ComfyError("VIDEO_CONFIGURATION_ERROR", "Invalid ComfyUI request path.", 500)
        request = urllib.request.Request(
            self.base_url + path,
            data=body,
            method=method,
            headers={"Accept": "application/json", **(headers or {})},
        )
        try:
            with _NO_REDIRECT_OPENER.open(request, timeout=self.timeout) as response:
                return response.status, dict(response.headers.items()), _bounded_read(response, limit)
        except urllib.error.HTTPError as exc:
            detail = _safe_text(_bounded_read(exc, MAX_JSON_BYTES))
            raise ComfyError(
                "VIDEO_CONFIGURATION_ERROR" if exc.code in (400, 404, 422) else "VIDEO_GENERATION_FAILED",
                detail or f"ComfyUI returned HTTP {exc.code}.",
                502,
            ) from exc
        except (urllib.error.URLError, TimeoutError, socket.timeout, OSError) as exc:
            raise ComfyError("VIDEO_PROVIDER_UNAVAILABLE", "ComfyUI could not be reached.", 503) from exc

    def json_request(self, method: str, path: str, value: Any | None = None, limit: int = MAX_JSON_BYTES) -> Mapping[str, Any]:
        body = None if value is None else _json_bytes(value)
        _, _, data = self.request(
            method,
            path,
            body,
            {"Content-Type": "application/json"} if body is not None else None,
            limit,
        )
        return _decode_json(data)

    def upload_image(self, filename: str, content_type: str, data: bytes) -> str:
        content_header, body = _multipart_body(
            {"overwrite": "true", "subfolder": "varian_bridge"},
            {"image": (filename, content_type, data)},
        )
        _, _, response = self.request(
            "POST",
            "/upload/image",
            body,
            {"Content-Type": content_header},
        )
        decoded = _decode_json(response)
        name = decoded.get("name")
        subfolder = decoded.get("subfolder")
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or ".." in name:
            raise ComfyError("VIDEO_UNSUPPORTED_PROVIDER", "ComfyUI returned an unsafe uploaded image name.", 502)
        if subfolder is not None:
            if not isinstance(subfolder, str):
                raise ComfyError("VIDEO_UNSUPPORTED_PROVIDER", "ComfyUI returned an invalid image subfolder.", 502)
            if subfolder:
                _valid_relative_component(subfolder, "image subfolder")
        return f"{subfolder}/{name}" if isinstance(subfolder, str) and subfolder else name

    def queue(self, workflow: Mapping[str, Any], client_id: str) -> str:
        response = self.json_request("POST", "/prompt", {"prompt": workflow, "client_id": client_id})
        prompt_id = response.get("prompt_id")
        if not isinstance(prompt_id, str):
            error = response.get("error") or response.get("node_errors")
            detail = str(error)[:240] if error else "ComfyUI rejected the workflow."
            raise ComfyError("VIDEO_WORKFLOW_ERROR", detail, 422)
        return _valid_request_id(prompt_id)

    def history(self, prompt_id: str) -> Mapping[str, Any]:
        return self.json_request("GET", "/history/" + urllib.parse.quote(_valid_request_id(prompt_id), safe=""))

    def system_stats(self) -> Mapping[str, Any]:
        return self.json_request("GET", "/system_stats")

    def view(self, filename: str, subfolder: str, output_type: str) -> tuple[Mapping[str, str], bytes]:
        filename = _valid_relative_component(filename, "output filename")
        subfolder = "" if not subfolder else _valid_relative_component(subfolder, "output subfolder")
        output_type = output_type.strip().lower()
        if output_type != "output":
            raise ComfyError("VIDEO_DOWNLOAD_ERROR", "ComfyUI returned a non-output file.", 502)
        query = urllib.parse.urlencode({"filename": filename, "subfolder": subfolder, "type": output_type})
        _, headers, data = self.request("GET", "/view?" + query, limit=MAX_VIDEO_BYTES)
        return headers, data


@dataclass
class WorkflowProfile:
    path: Path
    graph: dict[str, Any] = field(default_factory=dict)
    patch: dict[str, Any] = field(default_factory=dict)

    def load(self) -> None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise BridgeError(
                "VIDEO_SETUP_REQUIRED",
                "LTX workflow is not installed. Use the ComfyUI setup action first.",
                503,
            ) from exc
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The installed LTX workflow is unreadable.", 503) from exc
        if not isinstance(data, dict) or not data:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The installed LTX workflow is invalid.", 503)
        graph = (
            data.get("prompt")
            if isinstance(data.get("prompt"), dict)
            else data.get("graph")
            if isinstance(data.get("graph"), dict)
            else data
        )
        patch = data.get("patch")
        if not isinstance(graph, dict):
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The installed LTX workflow has no API graph.", 503)
        self._validate_graph(graph)
        if not isinstance(patch, dict):
            patch = self._derive_patch(graph)
        self._validate_patch(graph, patch)
        self.graph = graph
        self.patch = patch

    @staticmethod
    def _validate_graph(graph: Mapping[str, Any]) -> None:
        classes: list[str] = []
        for node_id, node in graph.items():
            if not isinstance(node_id, str) or not node or not isinstance(node, dict):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow contains an invalid node.", 503)
            class_type = node.get("class_type")
            inputs = node.get("inputs")
            if not isinstance(class_type, str) or not isinstance(inputs, dict):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow is not in API format.", 503)
            classes.append(class_type)
            for key, value in inputs.items():
                if not isinstance(key, str) or len(key) > 100:
                    raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow contains an invalid input.", 503)
                if isinstance(value, str) and any(token in value.lower() for token in ("..\\", "../", "\\\\")):
                    raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow contains an unsafe path.", 503)
        checkpoint_names = {
            str(value).replace("\\", "/").rsplit("/", 1)[-1]
            for node in graph.values()
            if isinstance(node, dict)
            for key, value in node.get("inputs", {}).items()
            if key in {"ckpt_name", "checkpoint_name", "model_name", "unet_name"}
            and isinstance(value, str)
            and value.lower().endswith(".safetensors")
        }
        if EXPECTED_CHECKPOINT not in checkpoint_names:
            raise BridgeError(
                "VIDEO_WORKFLOW_ERROR",
                f"LTX workflow must reference {EXPECTED_CHECKPOINT}.",
                503,
            )
        if "LoadImage" not in classes:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow has no LoadImage node.", 503)
        if sum(1 for value in classes if value == "CLIPTextEncode") < 2:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow needs positive and negative text nodes.", 503)
        if not any(value.startswith("LTXV") for value in classes):
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow has no LTX video conditioning node.", 503)
        if "CreateVideo" not in classes:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow has no video assembly node.", 503)
        if not any(value in {"SaveVideo", "VHS_VideoCombine"} for value in classes):
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow has no MP4 output node.", 503)

    @staticmethod
    def _derive_patch(graph: Mapping[str, Any]) -> dict[str, Any]:
        load_nodes = _nodes(graph, "LoadImage")
        text_nodes = _nodes(graph, "CLIPTextEncode")
        if len(load_nodes) != 1 or len(text_nodes) < 2:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow does not have one image and two text nodes.", 503)
        video_nodes: list[dict[str, Any]] = []
        for node_id, node in graph.items():
            if not isinstance(node, dict) or not str(node.get("class_type", "")).startswith("LTXV"):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            patchable = next(
                (name for name in ("width", "height", "length", "num_frames", "batch_size", "strength") if name in inputs and not isinstance(inputs[name], list)),
                None,
            )
            if patchable is not None:
                video_nodes.append({"node": node_id, "input": patchable})
        output_nodes: list[dict[str, Any]] = []
        for node_id, node in graph.items():
            if not isinstance(node, dict) or node.get("class_type") not in {"SaveVideo", "VHS_VideoCombine"}:
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            patchable = next(
                (name for name in ("filename_prefix", "format", "video_format", "codec", "fps", "frame_rate") if name in inputs and not isinstance(inputs[name], list)),
                None,
            )
            if patchable is not None:
                output_nodes.append({"node": node_id, "input": patchable})
        fps_nodes = [
            {"node": node_id, "input": "fps"}
            for node_id, node in graph.items()
            if isinstance(node, dict)
            and node.get("class_type") == "CreateVideo"
            and isinstance(node.get("inputs"), dict)
            and "fps" in node["inputs"]
            and not isinstance(node["inputs"]["fps"], list)
        ]
        conditioning_fps_nodes = [
            {"node": node_id, "input": "frame_rate"}
            for node_id, node in graph.items()
            if isinstance(node, dict)
            and node.get("class_type") == "LTXVConditioning"
            and isinstance(node.get("inputs"), dict)
            and "frame_rate" in node["inputs"]
            and not isinstance(node["inputs"]["frame_rate"], list)
        ]
        if not video_nodes or not output_nodes or not fps_nodes or not conditioning_fps_nodes:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "LTX workflow has no patchable video, frame-rate, or output node.", 503)
        return {
            "image": {"node": next(node_id for node_id, node in graph.items() if node is load_nodes[0]), "input": "image"},
            "positive_prompt": {"node": next(node_id for node_id, node in graph.items() if node is text_nodes[0]), "input": "text"},
            "negative_prompt": {"node": next(node_id for node_id, node in graph.items() if node is text_nodes[1]), "input": "text"},
            "video_nodes": video_nodes,
            "fps_nodes": fps_nodes,
            "conditioning_fps_nodes": conditioning_fps_nodes,
            "output_nodes": output_nodes,
        }

    @staticmethod
    def _validate_patch(graph: Mapping[str, Any], patch: Mapping[str, Any]) -> None:
        required = {
            "image",
            "positive_prompt",
            "negative_prompt",
            "video_nodes",
            "fps_nodes",
            "conditioning_fps_nodes",
            "output_nodes",
        }
        if not required.issubset(patch):
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow patch map is incomplete.", 503)

        def validate_target(
            target: Any,
            label: str,
            allowed_classes: set[str] | None = None,
            mapped_fields: set[str] | None = None,
        ) -> None:
            if not isinstance(target, dict):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} target is invalid.", 503)
            node_id = target.get("node")
            input_name = target.get("input")
            node = graph.get(str(node_id)) if node_id is not None else None
            if not isinstance(node, dict) or not isinstance(input_name, str):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} target is invalid.", 503)
            if allowed_classes and node.get("class_type") not in allowed_classes:
                raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} node type is unsupported.", 503)
            inputs = node.get("inputs")
            if not isinstance(inputs, dict) or input_name not in inputs or isinstance(inputs[input_name], list):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} input is not patchable.", 503)
            allowed_keys = {"node", "input", *(mapped_fields or set())}
            if any(key not in allowed_keys for key in target):
                raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} target contains an unsupported mapping.", 503)
            for field_name in mapped_fields or set():
                mapped_input = target.get(field_name)
                if mapped_input is not None and (
                    not isinstance(mapped_input, str)
                    or mapped_input not in inputs
                    or isinstance(inputs[mapped_input], list)
                ):
                    raise BridgeError("VIDEO_WORKFLOW_ERROR", f"The LTX workflow {label} mapping is not patchable.", 503)

        validate_target(patch["image"], "image", {"LoadImage"})
        validate_target(patch["positive_prompt"], "positive prompt", {"CLIPTextEncode"})
        validate_target(patch["negative_prompt"], "negative prompt", {"CLIPTextEncode"})
        video_fields = {"width", "height", "length", "num_frames", "batch_size", "strength"}
        for target in patch["video_nodes"] if isinstance(patch["video_nodes"], list) else []:
            validate_target(
                target,
                "video",
                {"LTXVImgToVideo", "LTXVImgToVideoInplace", "LTXVAddGuide", "EmptyLTXVLatentVideo"},
                video_fields,
            )
        if not isinstance(patch["video_nodes"], list) or not patch["video_nodes"]:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow has no patchable video node.", 503)
        if not isinstance(patch["fps_nodes"], list) or not patch["fps_nodes"]:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow has no patchable FPS input.", 503)
        for target in patch["fps_nodes"]:
            validate_target(target, "FPS", {"CreateVideo"}, {"fps"})
        if not isinstance(patch["conditioning_fps_nodes"], list) or not patch["conditioning_fps_nodes"]:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow has no patchable conditioning frame-rate input.", 503)
        for target in patch["conditioning_fps_nodes"]:
            validate_target(target, "conditioning FPS", {"LTXVConditioning"}, {"frame_rate"})
        output_fields = {"filename_prefix", "format", "video_format", "codec", "fps", "frame_rate"}
        for target in patch["output_nodes"] if isinstance(patch["output_nodes"], list) else []:
            validate_target(target, "output", {"SaveVideo", "VHS_VideoCombine"}, output_fields)
        if not isinstance(patch["output_nodes"], list) or not patch["output_nodes"]:
            raise BridgeError("VIDEO_WORKFLOW_ERROR", "The LTX workflow has no patchable output node.", 503)

    def patched(self, image_name: str, prompt: str, duration: str, size: str, output_prefix: str) -> dict[str, Any]:
        if not self.graph:
            self.load()
        if duration not in LOW_VRAM_DURATIONS:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "The low-VRAM LTX profile supports only 4 seconds.", 422)
        try:
            width, height = (int(value) for value in size.lower().split("x", 1))
        except (TypeError, ValueError) as exc:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "Video size must be WIDTHxHEIGHT.", 422) from exc
        if width < 1 or height < 1 or width > 4096 or height > 4096:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "Video size is invalid.", 422)
        internal_width, internal_height = _low_vram_dimensions(width, height)
        graph = copy.deepcopy(self.graph)
        frame_count = LOW_VRAM_DURATIONS[duration]
        _set_target(graph, self.patch["image"], image_name)
        _set_target(graph, self.patch["positive_prompt"], prompt)
        _set_target(graph, self.patch["negative_prompt"], DEFAULT_NEGATIVE_PROMPT)
        for target in self.patch["video_nodes"]:
            if not isinstance(target, dict):
                continue
            node = graph[str(target["node"])]
            inputs = node["inputs"]
            for field_name, value in {
                "width": internal_width,
                "height": internal_height,
                "length": frame_count,
                "num_frames": frame_count,
                "batch_size": 1,
                "strength": 0.8,
            }.items():
                mapped_input = target.get(field_name)
                if isinstance(mapped_input, str):
                    _set_target_value(graph, target, mapped_input, value)
                else:
                    _set_if_present(inputs, field_name, value)
        for target in self.patch["fps_nodes"]:
            if not isinstance(target, dict):
                continue
            inputs = graph.get(str(target["node"]), {}).get("inputs", {})
            mapped_input = target.get("fps")
            if isinstance(mapped_input, str):
                _set_target_value(graph, target, mapped_input, LOW_VRAM_FPS)
            else:
                _set_if_present(inputs, "fps", LOW_VRAM_FPS)
        for target in self.patch["conditioning_fps_nodes"]:
            if not isinstance(target, dict):
                continue
            inputs = graph.get(str(target["node"]), {}).get("inputs", {})
            mapped_input = target.get("frame_rate")
            if isinstance(mapped_input, str):
                _set_target_value(graph, target, mapped_input, LOW_VRAM_FPS)
            else:
                _set_if_present(inputs, "frame_rate", LOW_VRAM_FPS)
        for target in self.patch["output_nodes"]:
            if not isinstance(target, dict):
                continue
            inputs = graph[str(target["node"])]["inputs"]
            for field_name, value in {
                "filename_prefix": output_prefix,
                "format": "mp4",
                "video_format": "mp4",
                "codec": "h264",
                "fps": LOW_VRAM_FPS,
                "frame_rate": LOW_VRAM_FPS,
            }.items():
                mapped_input = target.get(field_name)
                if isinstance(mapped_input, str):
                    _set_target_value(graph, target, mapped_input, value)
                else:
                    _set_if_present(inputs, field_name, value)
        for node in graph.values():
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            for seed_name in ("seed", "noise_seed"):
                if seed_name in inputs and isinstance(inputs[seed_name], (int, float)):
                    inputs[seed_name] = secrets.randbelow(2**63)
        self._validate_graph(graph)
        return graph


def _nodes(graph: Mapping[str, Any], class_type: str) -> list[dict[str, Any]]:
    return [
        node
        for node in graph.values()
        if isinstance(node, dict)
        and node.get("class_type") == class_type
        and isinstance(node.get("inputs"), dict)
    ]


def _set_target(graph: dict[str, Any], target: Mapping[str, Any], value: Any) -> None:
    node_id = str(target["node"])
    input_name = str(target["input"])
    graph[node_id]["inputs"][input_name] = value


def _set_target_value(
    graph: dict[str, Any],
    target: Mapping[str, Any],
    input_name: str,
    value: Any,
) -> None:
    node_id = str(target["node"])
    graph[node_id]["inputs"][input_name] = value


def _set_if_present(inputs: dict[str, Any], key: str, value: Any) -> None:
    if key in inputs and not isinstance(inputs[key], list):
        inputs[key] = value


def _low_vram_dimensions(width: int, height: int) -> tuple[int, int]:
    if width >= height:
        return 512, 288
    return 288, 512


@dataclass
class Job:
    id: str
    prompt_id: str | None = None
    status: str = "queued"
    error: str | None = None
    output: dict[str, str] | None = None
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)


class ComfyProcess:
    def __init__(
        self,
        root: str,
        port: int,
        runtime_dir: Path,
        no_start: bool,
        token_env: str = "VARIAN_COMFYUI_BRIDGE_TOKEN",
    ):
        self.root = Path(root).expanduser() if root else None
        self.port = port
        self.runtime_dir = runtime_dir
        self.no_start = no_start
        self.token_env = token_env
        self.process: subprocess.Popen[bytes] | None = None
        self.log_file: Any | None = None
        self._owned_job: _WindowsJobObject | None = None
        self._owns_process = False
        self.client = ComfyClient(f"http://{DEFAULT_COMFY_HOST}:{port}")

    def ensure_ready(self, timeout: float = 180.0) -> None:
        if not self._probe_ready():
            if self.no_start:
                raise BridgeError("VIDEO_PROVIDER_UNAVAILABLE", "ComfyUI is not reachable on the configured port.", 503)
            self._start()
        deadline = time.monotonic() + timeout
        last_error: Exception | None = None
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                raise BridgeError("VIDEO_SETUP_ERROR", self._log_message() or "ComfyUI stopped during startup.", 503)
            try:
                self.client.system_stats()
                return
            except Exception as exc:  # noqa: BLE001 - converted to a safe setup error below
                last_error = exc
                time.sleep(1)
        detail = "ComfyUI did not become ready before the startup timeout."
        if last_error and isinstance(last_error, BridgeError) and last_error.message:
            detail += " " + last_error.message
        raise BridgeError("VIDEO_SETUP_ERROR", detail, 503)

    def _probe_ready(self) -> bool:
        try:
            self.client.system_stats()
            return True
        except Exception:
            return False

    def _start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        if self.process is not None:
            self.process = None
            if self._owned_job is not None:
                self._owned_job.close()
                self._owned_job = None
        if self.root is None:
            raise BridgeError("VIDEO_SETUP_REQUIRED", "Configure the ComfyUI installation path first.", 503)
        install_root = self.root.resolve()
        root = install_root
        main = root / "main.py"
        if not main.exists():
            candidate = install_root / "ComfyUI" / "main.py"
            if candidate.exists():
                main = candidate
                root = candidate.parent
        if not main.exists():
            raise BridgeError("VIDEO_SETUP_REQUIRED", "ComfyUI main.py was not found in the configured path.", 503)
        python_candidates = [
            install_root / "python_embeded" / "python.exe",
            install_root / "venv" / "Scripts" / "python.exe",
            install_root / ".venv" / "Scripts" / "python.exe",
            root / "python_embeded" / "python.exe",
            root / "venv" / "Scripts" / "python.exe",
            root / ".venv" / "Scripts" / "python.exe",
            install_root.parent / "python_embeded" / "python.exe",
            install_root.parent / "venv" / "Scripts" / "python.exe",
            install_root.parent / ".venv" / "Scripts" / "python.exe",
        ]
        python = next((candidate for candidate in python_candidates if candidate.exists()), None)
        if python is None:
            discovered = shutil.which("python")
            if discovered:
                python = Path(discovered)
        if python is None:
            raise BridgeError("VIDEO_SETUP_REQUIRED", "A Python runtime for ComfyUI was not found.", 503)
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        if self.log_file is not None:
            self.log_file.close()
        self.log_file = (self.runtime_dir / "comfyui.log").open("ab")
        creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        try:
            process = subprocess.Popen(
                _comfy_command(python, main, self.port),
                cwd=str(root),
                env=_comfy_environment(self.token_env),
                stdout=self.log_file,
                stderr=subprocess.STDOUT,
                creationflags=creationflags,
            )
        except OSError as exc:
            self.log_file.close()
            self.log_file = None
            raise BridgeError("VIDEO_SETUP_ERROR", "ComfyUI could not be started.", 503) from exc
        self.process = process
        self._owns_process = True
        self._owned_job = _WindowsJobObject()
        if self._owned_job is not None and not self._owned_job.assign(process.pid):
            self._owned_job.close()
            self._owned_job = None
        threading.Thread(target=self._trim_log, args=(process,), daemon=True).start()

    def _trim_log(self, process: subprocess.Popen[bytes]) -> None:
        log_path = self.runtime_dir / "comfyui.log"
        while self.process is process and process.poll() is None:
            try:
                if log_path.stat().st_size > 4 * 1024 * 1024:
                    data = log_path.read_bytes()[-2 * 1024 * 1024 :]
                    log_path.write_bytes(data)
            except OSError:
                pass
            time.sleep(5)

    def _log_message(self) -> str | None:
        if self.log_file is None:
            return None
        try:
            self.log_file.flush()
            data = (self.runtime_dir / "comfyui.log").read_bytes()[-4096:]
            return _safe_text(data)
        except OSError:
            return None

    def close(self) -> None:
        process = self.process
        self.process = None
        owned = self._owns_process
        self._owns_process = False
        owned_job = self._owned_job
        self._owned_job = None
        if process is not None and owned:
            try:
                if owned_job is not None:
                    owned_job.close()
                elif os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                        check=False,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=5,
                    )
                elif process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            except (OSError, subprocess.SubprocessError):
                try:
                    process.kill()
                except OSError:
                    pass
        elif owned_job is not None:
            owned_job.close()
        if self.log_file is not None:
            self.log_file.close()
            self.log_file = None


class BridgeState:
    def __init__(
        self,
        comfy: ComfyProcess,
        workflow: WorkflowProfile,
        token: str,
        allowed_origins: set[str],
        lease_seconds: int = DEFAULT_BRIDGE_LEASE_SECONDS,
    ):
        if not token:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "A local bridge token is required.", 500)
        if lease_seconds < 0 or lease_seconds > 24 * 60 * 60:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "Bridge lease timeout is invalid.", 500)
        self.comfy = comfy
        self.workflow = workflow
        self.token = token
        self.allowed_origins = allowed_origins
        self.lease_seconds = lease_seconds
        self.jobs: dict[str, Job] = {}
        self.lock = threading.RLock()
        self.active_job: str | None = None
        self.ready = False
        self.ready_error: BridgeError | None = None
        self.last_heartbeat = time.monotonic()
        self._stop = threading.Event()

    def bootstrap(self) -> None:
        try:
            self.workflow.load()
            self.comfy.ensure_ready()
            with self.lock:
                self.ready = True
                self.last_heartbeat = time.monotonic()
        except BridgeError as exc:
            self.comfy.close()
            self.ready_error = exc
        except Exception as exc:  # noqa: BLE001 - startup errors are exposed as safe setup errors
            self.comfy.close()
            self.ready_error = BridgeError("VIDEO_SETUP_ERROR", "ComfyUI bridge setup failed.", 503)
            _ = exc

    def close(self) -> None:
        self._stop.set()
        self.comfy.close()

    def require_ready(self) -> None:
        if self.ready:
            return
        error = self.ready_error
        if error:
            raise error
        raise BridgeError("VIDEO_SETUP_ERROR", "ComfyUI is still starting. Try again shortly.", 503)

    def heartbeat(self) -> None:
        with self.lock:
            self.last_heartbeat = time.monotonic()

    def lease_expired(self) -> bool:
        with self.lock:
            return (
                self.ready
                and self.lease_seconds > 0
                and time.monotonic() - self.last_heartbeat > self.lease_seconds
            )

    def create_job(self, fields: Mapping[str, str], image: bytes, image_type: str) -> Job:
        self.require_ready()
        model = fields.get("model", "").strip()
        if model != PROFILE_ID:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", f"Use the local profile {PROFILE_ID}.", 422)
        prompt = fields.get("prompt", "").strip()
        if not prompt or len(prompt) > MAX_PROMPT_CHARS:
            raise BridgeError("VIDEO_CONFIGURATION_ERROR", "Video prompt must contain 1 to 4000 characters.", 422)
        duration = fields.get("seconds", "").strip()
        size = fields.get("size", "").strip()
        _validate_image(image, image_type)
        self._prune_jobs()
        with self.lock:
            if self.active_job is not None:
                raise BridgeError("VIDEO_RATE_LIMITED", "ComfyUI is processing another video. Try again later.", 429)
            job_id = uuid.uuid4().hex
            job = Job(job_id)
            self.jobs[job_id] = job
            self.active_job = job_id
        job_dir = self.comfy.runtime_dir / "bridge_jobs" / job_id
        try:
            job_dir.mkdir(parents=True, exist_ok=False)
            (job_dir / "input.png").write_bytes(image)
            uploaded = self.comfy.client.upload_image("input.png", image_type, image)
            graph = self.workflow.patched(uploaded, prompt, duration, size, f"varian_bridge_{job_id}")
            prompt_id = self.comfy.client.queue(graph, "varian-bridge")
            with self.lock:
                job.prompt_id = prompt_id
                job.status = "in_progress"
                job.updated_at = time.time()
            threading.Thread(target=self._run_job, args=(job_id,), daemon=True).start()
            return job
        except Exception as exc:  # noqa: BLE001 - normalize all provider failures
            self._remove_job_dir(job_id)
            self._fail(job_id, _as_bridge_error(exc, "ComfyUI rejected the video job."))
            raise _as_bridge_error(exc, "ComfyUI rejected the video job.")

    def _run_job(self, job_id: str) -> None:
        deadline = time.monotonic() + DEFAULT_JOB_TIMEOUT_SECONDS
        try:
            while time.monotonic() < deadline and not self._stop.is_set():
                with self.lock:
                    job = self.jobs.get(job_id)
                    prompt_id = job.prompt_id if job else None
                if job is None or prompt_id is None:
                    return
                history = self.comfy.client.history(prompt_id)
                result = history.get(prompt_id)
                if isinstance(result, dict):
                    status = result.get("status")
                    if isinstance(status, dict) and status.get("status_str") in {"error", "failed"}:
                        detail = _safe_detail(status.get("messages") or result.get("node_errors"))
                        raise _as_bridge_error(
                            RuntimeError(detail or "ComfyUI failed the workflow."),
                            "ComfyUI failed the workflow.",
                        )
                    if result.get("node_errors"):
                        detail = _safe_detail(result["node_errors"])
                        if detail and "out of memory" in detail.lower():
                            raise _as_bridge_error(RuntimeError(detail), "ComfyUI failed the workflow.")
                        raise BridgeError(
                            "VIDEO_WORKFLOW_ERROR",
                            detail or "ComfyUI reported a workflow error.",
                            422,
                        )
                    status_str = status.get("status_str") if isinstance(status, dict) else None
                    output = _find_output(
                        result.get("outputs"),
                        f"varian_bridge_{job_id}",
                    )
                    if status_str in {"success", "completed"}:
                        if output is None:
                            raise BridgeError(
                                "VIDEO_OUTPUT_MISSING",
                                "ComfyUI completed the workflow without an MP4 output.",
                                502,
                            )
                        with self.lock:
                            job.output = output
                            job.status = "completed"
                            job.updated_at = time.time()
                        return
                    if output is not None:
                        with self.lock:
                            job.output = output
                            job.status = "completed"
                            job.updated_at = time.time()
                        return
                time.sleep(DEFAULT_POLL_SECONDS)
            raise BridgeError("VIDEO_GENERATION_TIMEOUT", "ComfyUI video generation timed out after 5 minutes.", 504)
        except Exception as exc:  # noqa: BLE001 - convert provider errors and release the slot
            self._fail(job_id, _as_bridge_error(exc, "ComfyUI video generation failed."))
        finally:
            with self.lock:
                if self.active_job == job_id:
                    self.active_job = None
            self._remove_job_dir(job_id)

    def _remove_job_dir(self, job_id: str) -> None:
        job_dir = self.comfy.runtime_dir / "bridge_jobs" / job_id
        try:
            if job_dir.is_symlink():
                job_dir.unlink()
            elif job_dir.exists():
                shutil.rmtree(job_dir)
        except OSError:
            return

    def _prune_jobs(self) -> None:
        now = time.time()
        removable: list[str] = []
        with self.lock:
            terminal = [
                job
                for job in self.jobs.values()
                if job.status in {"completed", "failed"}
                and job.id != self.active_job
            ]
            removable.extend(
                job.id
                for job in terminal
                if now - job.updated_at > JOB_RETENTION_SECONDS
            )
            if len(self.jobs) - len(removable) > MAX_TRACKED_JOBS:
                remaining = sorted(
                    (job for job in terminal if job.id not in removable),
                    key=lambda job: job.updated_at,
                )
                removable.extend(
                    job.id
                    for job in remaining[: len(self.jobs) - len(removable) - MAX_TRACKED_JOBS]
                )
            for job_id in removable:
                self.jobs.pop(job_id, None)
        for job_id in removable:
            self._remove_job_dir(job_id)

    def _fail(self, job_id: str, error: BridgeError) -> None:
        with self.lock:
            job = self.jobs.get(job_id)
            if job is not None:
                job.status = "failed"
                job.error = error.message
                job.updated_at = time.time()
            if self.active_job == job_id:
                self.active_job = None

    def get_job(self, job_id: str) -> Job:
        job_id = _valid_request_id(job_id)
        self._prune_jobs()
        with self.lock:
            job = self.jobs.get(job_id)
            if job is None:
                raise BridgeError("VIDEO_NOT_FOUND", "Video job was not found.", 404)
            return copy.copy(job)

    def get_content(self, job_id: str) -> tuple[Mapping[str, str], bytes]:
        job = self.get_job(job_id)
        if job.status != "completed" or job.output is None:
            raise BridgeError("VIDEO_NOT_READY", "Video content is not ready.", 409)
        headers, data = self.comfy.client.view(
            job.output["filename"],
            job.output.get("subfolder", ""),
            job.output.get("type", "output"),
        )
        content_type = headers.get("Content-Type", headers.get("content-type", "")).lower()
        if len(data) > MAX_VIDEO_BYTES or not _is_mp4(data) or (content_type and "video/mp4" not in content_type and "application/octet-stream" not in content_type):
            raise BridgeError("VIDEO_DOWNLOAD_ERROR", "ComfyUI returned invalid MP4 content.", 502)
        return {"Content-Type": "video/mp4"}, data


def _find_output(outputs: Any, expected_prefix: str) -> dict[str, str] | None:
    if not isinstance(outputs, dict):
        return None
    for node_output in outputs.values():
        if not isinstance(node_output, dict):
            continue
        for key in ("videos", "gifs", "animated"):
            values = node_output.get(key)
            if not isinstance(values, list):
                continue
            for value in values:
                if not isinstance(value, dict):
                    continue
                filename = value.get("filename")
                subfolder = value.get("subfolder", "")
                output_type = value.get("type", "output")
                if not isinstance(filename, str) or not filename.lower().endswith(".mp4"):
                    continue
                safe_filename = _valid_relative_component(filename, "output filename")
                if not Path(safe_filename).name.startswith(expected_prefix):
                    continue
                if not isinstance(subfolder, str):
                    raise BridgeError("VIDEO_DOWNLOAD_ERROR", "Provider returned an invalid output subfolder.", 502)
                return {
                    "filename": safe_filename,
                    "subfolder": "" if not subfolder else _valid_relative_component(subfolder, "output subfolder"),
                    "type": str(output_type),
                }
    return None


def _safe_detail(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, (dict, list)):
        try:
            text = json.dumps(value, separators=(",", ":"))
        except (TypeError, ValueError):
            text = str(value)
    else:
        text = str(value)
    text = text.replace("Bearer ", "Bearer [redacted]")
    return text.strip()[:240] or None


def _as_bridge_error(error: Exception, fallback: str) -> BridgeError:
    if isinstance(error, BridgeError):
        return error
    detail = str(error).lower()
    if "out of memory" in detail or "cuda out of memory" in detail:
        return BridgeError(
            "VIDEO_OUT_OF_MEMORY",
            "ComfyUI ran out of GPU memory. Lower the profile resolution or close other GPU workloads.",
            507,
        )
    if isinstance(error, (OSError, urllib.error.URLError, TimeoutError, socket.timeout)):
        return BridgeError("VIDEO_PROVIDER_UNAVAILABLE", "ComfyUI could not be reached.", 503)
    return BridgeError("VIDEO_GENERATION_FAILED", fallback, 502)


def _origin_allowed(origin: str | None, allowed_origins: set[str]) -> bool:
    if not origin:
        return True
    if origin in allowed_origins:
        return True
    try:
        parsed = urllib.parse.urlparse(origin)
        port = parsed.port
    except ValueError:
        return False
    return (
        parsed.scheme == "http"
        and not parsed.username
        and not parsed.password
        and (port is None or 1 <= port <= 65535)
        and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    )


def _read_multipart(handler: http.server.BaseHTTPRequestHandler) -> tuple[dict[str, str], bytes, str]:
    content_length = handler.headers.get("Content-Length")
    try:
        length = int(content_length or "-1")
    except ValueError as exc:
        raise BridgeError("VIDEO_SOURCE_ERROR", "Multipart request length is invalid.", 400) from exc
    if length < 0 or length > MAX_REQUEST_BYTES:
        raise BridgeError("VIDEO_SOURCE_ERROR", "Multipart request is too large.", 413)
    body = handler.rfile.read(length)
    if len(body) != length:
        raise BridgeError("VIDEO_SOURCE_ERROR", "Multipart request was truncated.", 400)
    content_type = handler.headers.get("Content-Type", "")
    if not content_type.lower().startswith("multipart/form-data"):
        raise BridgeError("VIDEO_CONFIGURATION_ERROR", "Video create request must be multipart/form-data.", 415)
    envelope = b"Content-Type: " + content_type.encode("latin1", "replace") + b"\r\nMIME-Version: 1.0\r\n\r\n" + body
    message = BytesParser(policy=email_default).parsebytes(envelope)
    if not message.is_multipart():
        raise BridgeError("VIDEO_SOURCE_ERROR", "Multipart request is malformed.", 400)
    fields: dict[str, str] = {}
    image: bytes | None = None
    image_type = ""
    for part in message.iter_parts():
        disposition = part.get("Content-Disposition", "")
        name = part.get_param("name", header="content-disposition")
        if not isinstance(name, str):
            continue
        payload = part.get_payload(decode=True) or b""
        if name == "input_reference":
            image = payload
            image_type = part.get_content_type()
        elif not part.get_filename():
            fields[name] = payload.decode("utf-8", "replace")
    if image is None:
        raise BridgeError("VIDEO_SOURCE_ERROR", "The input_reference image is required.", 422)
    return fields, image, image_type


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    server: "BridgeHttpServer"

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _authenticate(self) -> None:
        host = self.headers.get("Host", "").split(":", 1)[0].lower()
        if host not in {"localhost", "127.0.0.1", "::1"}:
            raise BridgeError("VIDEO_AUTH_ERROR", "Local bridge accepts loopback requests only.", 403)
        authorization = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.state.token
        if not hmac.compare_digest(authorization, expected):
            raise BridgeError("VIDEO_AUTH_ERROR", "Local bridge token was rejected.", 401)

    def _send(self, status: int, body: bytes = b"", headers: Mapping[str, str] | None = None) -> None:
        self.send_response(status)
        origin = self.headers.get("Origin")
        if origin and _origin_allowed(origin, self.server.state.allowed_origins):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, status: int, value: Any) -> None:
        self._send(status, _json_bytes(value), {"Content-Type": "application/json", "X-Content-Type-Options": "nosniff"})

    def _error(self, error: BridgeError) -> None:
        self._json(error.status, {"error": {"code": error.code, "message": error.message}})

    def do_OPTIONS(self) -> None:  # noqa: N802
        origin = self.headers.get("Origin")
        if origin and not _origin_allowed(origin, self.server.state.allowed_origins):
            self._send(403)
            return
        self._send(
            204,
            headers={
                "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
                "Access-Control-Allow-Headers": "Authorization,Content-Type,Accept",
                "Access-Control-Max-Age": "600",
            },
        )

    def do_GET(self) -> None:  # noqa: N802
        try:
            self._authenticate()
            path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
            if path == "/health":
                self.server.state.require_ready()
                self._json(200, {"status": "ready", "profile": PROFILE_ID})
                return
            if path == "/v1/videos":
                self.server.state.require_ready()
                self._json(200, {"object": "list", "data": []})
                return
            if path == "/v1/models":
                self.server.state.require_ready()
                self._json(200, {"object": "list", "data": [{"id": PROFILE_ID, "object": "model"}]})
                return
            parts = path.split("/")
            if len(parts) == 4 and parts[:3] == ["", "v1", "videos"]:
                job = self.server.state.get_job(parts[3])
                value: dict[str, Any] = {"id": job.id, "status": job.status}
                if job.error:
                    value["error"] = {"message": job.error}
                if job.output:
                    value["video_url"] = f"/v1/videos/{job.id}/content"
                self._json(200, value)
                return
            if len(parts) == 5 and parts[:3] == ["", "v1", "videos"] and parts[4] == "content":
                headers, content = self.server.state.get_content(parts[3])
                self._send(200, content, headers)
                return
            raise BridgeError("VIDEO_NOT_FOUND", "Bridge endpoint was not found.", 404)
        except BridgeError as error:
            self._error(error)
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception:  # noqa: BLE001 - do not expose stack traces
            self._error(BridgeError("VIDEO_PROVIDER_ERROR", "Local bridge request failed.", 500))

    def do_POST(self) -> None:  # noqa: N802
        try:
            self._authenticate()
            path = urllib.parse.urlparse(self.path).path.rstrip("/")
            if path == "/health/heartbeat":
                self.server.state.heartbeat()
                self._send(204)
                return
            if path != "/v1/videos":
                raise BridgeError("VIDEO_NOT_FOUND", "Bridge endpoint was not found.", 404)
            fields, image, image_type = _read_multipart(self)
            job = self.server.state.create_job(fields, image, image_type)
            self._json(200, {"id": job.id, "status": job.status})
        except BridgeError as error:
            self._error(error)
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception:  # noqa: BLE001 - do not expose stack traces
            self._error(BridgeError("VIDEO_PROVIDER_ERROR", "Local bridge request failed.", 500))


class BridgeHttpServer(http.server.ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], state: BridgeState):
        super().__init__(address, BridgeHandler)
        self.state = state


def _lease_watch(state: BridgeState, server: BridgeHttpServer) -> None:
    if state.lease_seconds <= 0:
        return
    while not state._stop.wait(1):
        if state.lease_expired():
            state.close()
            server.shutdown()
            return


def _parent_watch(parent_pid: int, server: BridgeHttpServer) -> None:
    if parent_pid <= 0:
        return
    if os.name == "nt":
        try:
            kernel = ctypes.windll.kernel32
            handle = kernel.OpenProcess(0x00100000, False, parent_pid)
            if handle:
                kernel.WaitForSingleObject(handle, 0xFFFFFFFF)
                kernel.CloseHandle(handle)
                server.shutdown()
                return
        except (AttributeError, OSError):
            pass
    while True:
        try:
            os.kill(parent_pid, 0)
        except OSError:
            server.shutdown()
            return
        time.sleep(2)


def _parse_origins(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge-host", default=DEFAULT_BRIDGE_HOST)
    parser.add_argument("--bridge-port", type=int, default=DEFAULT_BRIDGE_PORT)
    parser.add_argument("--comfyui-path", default=os.environ.get("VARIAN_COMFYUI_PATH", ""))
    parser.add_argument("--comfyui-port", type=int, default=int(os.environ.get("VARIAN_COMFYUI_PORT", DEFAULT_COMFY_PORT)))
    parser.add_argument("--runtime-dir", default=os.environ.get("VARIAN_COMFYUI_RUNTIME", ""))
    parser.add_argument("--workflow", default=os.environ.get("VARIAN_COMFYUI_WORKFLOW", ""))
    parser.add_argument("--no-comfy-start", action="store_true")
    parser.add_argument("--parent-pid", type=int, default=int(os.environ.get("VARIAN_BRIDGE_PARENT_PID", "0")))
    parser.add_argument("--lease-seconds", type=int, default=int(os.environ.get("VARIAN_BRIDGE_LEASE_SECONDS", str(DEFAULT_BRIDGE_LEASE_SECONDS))))
    parser.add_argument("--allowed-origins", default=os.environ.get("VARIAN_BRIDGE_ALLOWED_ORIGINS", ""))
    parser.add_argument("--token-env", default="VARIAN_COMFYUI_BRIDGE_TOKEN")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if args.bridge_host not in {"127.0.0.1", "localhost", "::1"}:
        print("bridge host must be loopback", file=sys.stderr)
        return 2
    if not 1 <= args.bridge_port <= 65535 or not 1 <= args.comfyui_port <= 65535:
        print("port is invalid", file=sys.stderr)
        return 2
    token = os.environ.get(args.token_env, "")
    runtime_dir = Path(args.runtime_dir).expanduser() if args.runtime_dir else Path(__file__).resolve().parent / "runtime"
    workflow_path = Path(args.workflow).expanduser() if args.workflow else runtime_dir / "workflow_api.json"
    try:
        comfy = ComfyProcess(
            args.comfyui_path,
            args.comfyui_port,
            runtime_dir,
            args.no_comfy_start,
            args.token_env,
        )
        state = BridgeState(
            comfy,
            WorkflowProfile(workflow_path),
            token,
            _parse_origins(args.allowed_origins),
            args.lease_seconds,
        )
    except BridgeError as error:
        print(error.message, file=sys.stderr)
        return 2
    server = BridgeHttpServer((args.bridge_host, args.bridge_port), state)
    threading.Thread(target=state.bootstrap, daemon=True).start()
    if args.parent_pid:
        threading.Thread(target=_parent_watch, args=(args.parent_pid, server), daemon=True).start()
    if state.lease_seconds > 0:
        threading.Thread(target=_lease_watch, args=(state, server), daemon=True).start()
    def shutdown(signum: int | None = None, frame: Any | None = None) -> None:
        _ = signum, frame
        state.close()
        if threading.current_thread() is not threading.main_thread():
            return
        server.shutdown()
    try:
        signal.signal(signal.SIGTERM, shutdown)
        if hasattr(signal, "SIGINT"):
            signal.signal(signal.SIGINT, shutdown)
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        state.close()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
