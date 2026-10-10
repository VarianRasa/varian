from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

from .glb_utils import GLBInfo, GLBValidationError, validate_glb_file
from .preview import PreviewValidationError, validate_png_file, write_fallback_preview


class PostprocessError(RuntimeError):
    pass


def postprocess_glb(
    source_path: Path,
    output_path: Path,
    *,
    triangle_budget: int,
    texture_mode: str,
    max_bytes: int,
) -> GLBInfo:
    if not source_path.is_file():
        raise PostprocessError("The provider did not create a model file.")
    blender = _blender_binary()
    if blender is None:
        if source_path.resolve() != output_path.resolve():
            output_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_path, output_path)
    else:
        _run_blender(
            blender,
            source_path,
            output_path,
            triangle_budget=triangle_budget,
            texture_mode=texture_mode,
        )

    try:
        info = validate_glb_file(output_path, max_bytes=max_bytes)
    except (OSError, GLBValidationError) as error:
        raise PostprocessError(f"Post-processed GLB failed validation: {error}") from error
    if info.triangle_count > triangle_budget:
        raise PostprocessError(
            f"The generated model has {info.triangle_count} triangles, above the "
            f"configured budget of {triangle_budget}. Configure Blender post-processing "
            "or choose a lower mesh quality."
        )
    return info


def generate_preview(source_path: Path, output_path: Path) -> tuple[int, int]:
    if not source_path.is_file():
        raise PostprocessError("The model for the preview does not exist.")
    blender = _blender_binary()
    if blender is None:
        write_fallback_preview(output_path)
    else:
        try:
            _run_blender_preview(blender, source_path, output_path)
        except PostprocessError:
            write_fallback_preview(output_path)
    try:
        return validate_png_file(output_path)
    except (OSError, PreviewValidationError) as error:
        raise PostprocessError(f"Generated preview failed validation: {error}") from error


def _blender_binary() -> str | None:
    configured = os.getenv("BLENDER_BIN", "").strip()
    if configured and Path(configured).is_file():
        return configured
    discovered = shutil.which("blender")
    return discovered


def _run_blender(
    blender: str,
    source_path: Path,
    output_path: Path,
    *,
    triangle_budget: int,
    texture_mode: str,
) -> None:
    script = Path(__file__).with_name("blender_postprocess.py")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        blender,
        "--background",
        "--python",
        str(script),
        "--",
        "--input",
        str(source_path),
        "--output",
        str(output_path),
        "--triangle-budget",
        str(triangle_budget),
        "--texture-mode",
        texture_mode,
    ]
    timeout = int(os.getenv("BLENDER_TIMEOUT_SECONDS", "180"))
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise PostprocessError("Blender post-processing did not finish.") from error
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise PostprocessError(
            f"Blender post-processing failed: {detail[-1000:] or 'unknown error'}"
        )
    _read_blender_result(completed.stdout)


def _read_blender_result(stdout: str) -> None:
    for line in reversed(stdout.splitlines()):
        text = line.strip()
        if not text.startswith("{"):
            continue
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            continue
        if payload.get("ok") is True:
            return
        if payload.get("error"):
            raise PostprocessError(str(payload["error"]))
    if "Blender post-processing completed" not in stdout:
        raise PostprocessError("Blender did not report a completed export.")


def _run_blender_preview(blender: str, source_path: Path, output_path: Path) -> None:
    script = Path(__file__).with_name("blender_preview.py")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        blender,
        "--background",
        "--python",
        str(script),
        "--",
        "--input",
        str(source_path),
        "--output",
        str(output_path),
    ]
    timeout = int(os.getenv("BLENDER_PREVIEW_TIMEOUT_SECONDS", "120"))
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise PostprocessError("Blender preview rendering did not finish.") from error
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise PostprocessError(
            f"Blender preview rendering failed: {detail[-1000:] or 'unknown error'}"
        )
    for line in reversed(completed.stdout.splitlines()):
        if "Blender preview rendering completed" in line:
            return
    raise PostprocessError("Blender did not report a completed preview render.")
