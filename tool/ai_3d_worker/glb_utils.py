from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any


GLB_MAGIC = b"glTF"
JSON_CHUNK_TYPE = 0x4E4F534A
BIN_CHUNK_TYPE = 0x004E4942


class GLBValidationError(ValueError):
    pass


@dataclass(frozen=True)
class GLBInfo:
    byte_length: int
    triangle_count: int
    has_binary_chunk: bool
    document: dict[str, Any]


def validate_glb_bytes(
    data: bytes,
    *,
    max_bytes: int = 64 * 1024 * 1024,
) -> GLBInfo:
    if not data:
        raise GLBValidationError("GLB is empty.")
    if len(data) > max_bytes:
        raise GLBValidationError("GLB exceeds the configured size limit.")
    if len(data) < 20 or data[:4] != GLB_MAGIC:
        raise GLBValidationError("GLB magic header is invalid.")

    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2:
        raise GLBValidationError("Only glTF binary version 2 is supported.")
    if declared_length != len(data):
        raise GLBValidationError("GLB length does not match its header.")

    offset = 12
    document: dict[str, Any] | None = None
    has_binary_chunk = False
    while offset < declared_length:
        if offset + 8 > declared_length:
            raise GLBValidationError("GLB chunk header is truncated.")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        end = offset + chunk_length
        if end > declared_length:
            raise GLBValidationError("GLB chunk extends beyond the file.")
        chunk = data[offset:end]
        if chunk_type == JSON_CHUNK_TYPE and document is None:
            try:
                decoded = json.loads(chunk.rstrip(b" \t\r\n\x00").decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise GLBValidationError("GLB JSON chunk is invalid.") from error
            if not isinstance(decoded, dict):
                raise GLBValidationError("GLB JSON document must be an object.")
            document = decoded
        elif chunk_type == BIN_CHUNK_TYPE:
            has_binary_chunk = True
        offset = end

    if document is None:
        raise GLBValidationError("GLB does not contain a JSON chunk.")
    if not has_binary_chunk:
        raise GLBValidationError("GLB does not contain a binary buffer chunk.")
    if not isinstance(document.get("asset"), dict):
        raise GLBValidationError("GLB asset metadata is missing.")
    if document["asset"].get("version") != "2.0":
        raise GLBValidationError("GLB asset version must be 2.0.")

    return GLBInfo(
        byte_length=len(data),
        triangle_count=_triangle_count(document),
        has_binary_chunk=has_binary_chunk,
        document=document,
    )


def validate_glb_file(
    path: Path,
    *,
    max_bytes: int = 64 * 1024 * 1024,
) -> GLBInfo:
    size = path.stat().st_size
    if size > max_bytes:
        raise GLBValidationError("GLB exceeds the configured size limit.")
    return validate_glb_bytes(path.read_bytes(), max_bytes=max_bytes)


def _triangle_count(document: dict[str, Any]) -> int:
    meshes = document.get("meshes")
    accessors = document.get("accessors")
    if not isinstance(meshes, list) or not isinstance(accessors, list):
        return 0

    total = 0
    for mesh in meshes:
        if not isinstance(mesh, dict) or not isinstance(mesh.get("primitives"), list):
            continue
        for primitive in mesh["primitives"]:
            if not isinstance(primitive, dict):
                continue
            mode = int(primitive.get("mode", 4))
            accessor_index = primitive.get("indices")
            count = 0
            if isinstance(accessor_index, int) and 0 <= accessor_index < len(accessors):
                accessor = accessors[accessor_index]
                if isinstance(accessor, dict):
                    count = int(accessor.get("count", 0))
            else:
                attributes = primitive.get("attributes")
                if isinstance(attributes, dict):
                    position_index = attributes.get("POSITION")
                    if isinstance(position_index, int) and 0 <= position_index < len(accessors):
                        accessor = accessors[position_index]
                        if isinstance(accessor, dict):
                            count = int(accessor.get("count", 0))
            if mode == 4:
                total += count // 3
            elif mode in (5, 6):
                total += max(0, count - 2)
    return total


def write_demo_glb(path: Path) -> GLBInfo:
    positions = [
        (-1.0, -1.0, -1.0),
        (1.0, -1.0, -1.0),
        (1.0, 1.0, -1.0),
        (-1.0, 1.0, -1.0),
        (-1.0, -1.0, 1.0),
        (1.0, -1.0, 1.0),
        (1.0, 1.0, 1.0),
        (-1.0, 1.0, 1.0),
    ]
    indices = [
        0,
        1,
        2,
        0,
        2,
        3,
        4,
        6,
        5,
        4,
        7,
        6,
        0,
        4,
        5,
        0,
        5,
        1,
        1,
        5,
        6,
        1,
        6,
        2,
        2,
        6,
        7,
        2,
        7,
        3,
        4,
        0,
        3,
        4,
        3,
        7,
    ]
    position_bytes = struct.pack("<24f", *(value for point in positions for value in point))
    index_offset = _align4(len(position_bytes))
    binary = position_bytes + b"\x00" * (index_offset - len(position_bytes))
    binary += struct.pack("<36H", *indices)
    binary += b"\x00" * (_align4(len(binary)) - len(binary))
    document = {
        "asset": {"version": "2.0", "generator": "Varian AI 3D worker demo"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "GeneratedDemoAsset"}],
        "meshes": [
            {
                "name": "GeneratedDemoMesh",
                "primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}],
            }
        ],
        "materials": [
            {
                "name": "DemoMaterial",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.18, 0.48, 0.82, 1.0],
                    "metallicFactor": 0.05,
                    "roughnessFactor": 0.72,
                },
            }
        ],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(position_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": index_offset, "byteLength": 72, "target": 34963},
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": 8,
                "type": "VEC3",
                "min": [-1.0, -1.0, -1.0],
                "max": [1.0, 1.0, 1.0],
            },
            {"bufferView": 1, "componentType": 5123, "count": 36, "type": "SCALAR"},
        ],
    }
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (_align4(len(json_bytes)) - len(json_bytes))
    glb = struct.pack("<4sII", GLB_MAGIC, 2, 12 + 8 + len(json_bytes) + 8 + len(binary))
    glb += struct.pack("<II", len(json_bytes), JSON_CHUNK_TYPE) + json_bytes
    glb += struct.pack("<II", len(binary), BIN_CHUNK_TYPE) + binary
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(glb)
    return validate_glb_bytes(glb)


def _align4(value: int) -> int:
    return (value + 3) & ~3
