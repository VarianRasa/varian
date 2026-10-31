from __future__ import annotations

import struct
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_PREVIEW_BYTES = 4 * 1024 * 1024
MAX_PREVIEW_DIMENSION = 4096


class PreviewValidationError(ValueError):
    pass


def validate_png_file(
    path: Path,
    *,
    max_bytes: int = MAX_PREVIEW_BYTES,
) -> tuple[int, int]:
    if not path.is_file():
        raise PreviewValidationError("Preview image does not exist.")
    with path.open("rb") as stream:
        data = stream.read(max_bytes + 1)
    return validate_png_bytes(data, max_bytes=max_bytes)


def validate_png_bytes(
    data: bytes,
    *,
    max_bytes: int = MAX_PREVIEW_BYTES,
) -> tuple[int, int]:
    if len(data) < 33 or len(data) > max_bytes:
        raise PreviewValidationError("Preview image size is invalid.")
    if data[:8] != PNG_SIGNATURE:
        raise PreviewValidationError("Preview image header is invalid.")

    offset = 8
    dimensions: tuple[int, int] | None = None
    found_iend = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise PreviewValidationError("Preview image chunk is truncated.")
        length = struct.unpack_from(">I", data, offset)[0]
        chunk_type_start = offset + 4
        chunk_data_start = offset + 8
        chunk_data_end = chunk_data_start + length
        crc_end = chunk_data_end + 4
        if crc_end > len(data):
            raise PreviewValidationError("Preview image chunk exceeds the file.")
        chunk_type = data[chunk_type_start:chunk_data_start]
        chunk_data = data[chunk_data_start:chunk_data_end]
        expected_crc = struct.unpack_from(">I", data, chunk_data_end)[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise PreviewValidationError("Preview image chunk checksum is invalid.")

        if chunk_type == b"IHDR":
            if dimensions is not None or length != 13:
                raise PreviewValidationError("Preview image header is invalid.")
            width, height, bit_depth, color_type, compression, filter_method, interlace = (
                struct.unpack(">IIBBBBB", chunk_data)
            )
            if (
                width == 0
                or height == 0
                or width > MAX_PREVIEW_DIMENSION
                or height > MAX_PREVIEW_DIMENSION
                or bit_depth != 8
                or color_type not in {2, 6}
                or compression != 0
                or filter_method != 0
                or interlace != 0
            ):
                raise PreviewValidationError("Preview image format is unsupported.")
            dimensions = (width, height)
        elif chunk_type == b"IEND":
            if length != 0:
                raise PreviewValidationError("Preview image end chunk is invalid.")
            found_iend = True
            offset = crc_end
            break

        offset = crc_end

    if dimensions is None or not found_iend or offset != len(data):
        raise PreviewValidationError("Preview image is incomplete.")
    return dimensions


def write_fallback_preview(path: Path, *, width: int = 512, height: int = 512) -> tuple[int, int]:
    if width <= 0 or height <= 0 or width > MAX_PREVIEW_DIMENSION or height > MAX_PREVIEW_DIMENSION:
        raise PreviewValidationError("Fallback preview dimensions are invalid.")

    pixels = bytearray(width * height * 3)
    for y in range(height):
        vertical = y / max(1, height - 1)
        for x in range(width):
            horizontal = x / max(1, width - 1)
            index = (y * width + x) * 3
            pixels[index] = int(13 + 21 * (1 - vertical) + 8 * horizontal)
            pixels[index + 1] = int(21 + 25 * (1 - vertical) + 10 * horizontal)
            pixels[index + 2] = int(39 + 36 * (1 - vertical) + 14 * horizontal)

    floor_y = int(height * 0.76)
    for y in range(floor_y, height):
        shade = max(18, 45 - int((y - floor_y) * 0.12))
        for x in range(width):
            index = (y * width + x) * 3
            pixels[index : index + 3] = bytes((shade, shade + 5, shade + 14))

    shadow_center = (width // 2, int(height * 0.76))
    shadow_radius_x = int(width * 0.24)
    shadow_radius_y = int(height * 0.035)
    for y in range(
        max(0, shadow_center[1] - shadow_radius_y),
        min(height, shadow_center[1] + shadow_radius_y + 1),
    ):
        for x in range(
            max(0, shadow_center[0] - shadow_radius_x),
            min(width, shadow_center[0] + shadow_radius_x + 1),
        ):
            normalized_x = (x - shadow_center[0]) / max(1, shadow_radius_x)
            normalized_y = (y - shadow_center[1]) / max(1, shadow_radius_y)
            if normalized_x * normalized_x + normalized_y * normalized_y <= 1:
                index = (y * width + x) * 3
                pixels[index : index + 3] = bytes((8, 11, 19))

    center_x = width // 2
    top_y = int(height * 0.25)
    bottom_y = int(height * 0.72)
    half_width = int(width * 0.21)
    depth = int(width * 0.14)
    top = [
        (center_x, top_y),
        (center_x + half_width, top_y + depth),
        (center_x, top_y + depth * 2),
        (center_x - half_width, top_y + depth),
    ]
    left = [
        (center_x - half_width, top_y + depth),
        (center_x, top_y + depth * 2),
        (center_x, bottom_y),
        (center_x - half_width, bottom_y - depth),
    ]
    right = [
        (center_x, top_y + depth * 2),
        (center_x + half_width, top_y + depth),
        (center_x + half_width, bottom_y - depth),
        (center_x, bottom_y),
    ]
    _fill_polygon(pixels, width, height, top, (109, 199, 255))
    _fill_polygon(pixels, width, height, left, (49, 116, 183))
    _fill_polygon(pixels, width, height, right, (72, 151, 216))
    _draw_polygon(pixels, width, height, top, (185, 233, 255))
    _draw_polygon(pixels, width, height, left, (113, 186, 239))
    _draw_polygon(pixels, width, height, right, (145, 211, 255))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_encode_png(width, height, pixels))
    return validate_png_file(path)


def _encode_png(width: int, height: int, pixels: bytearray) -> bytes:
    scanlines = bytearray()
    row_size = width * 3
    for row in range(height):
        scanlines.append(0)
        start = row * row_size
        scanlines.extend(pixels[start : start + row_size])
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
        + _png_chunk(b"IEND", b"")
    )


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def _fill_polygon(
    pixels: bytearray,
    width: int,
    height: int,
    points: list[tuple[int, int]],
    color: tuple[int, int, int],
) -> None:
    minimum_y = max(0, min(point[1] for point in points))
    maximum_y = min(height - 1, max(point[1] for point in points))
    for y in range(minimum_y, maximum_y + 1):
        intersections: list[float] = []
        for index, first in enumerate(points):
            second = points[(index + 1) % len(points)]
            if first[1] == second[1]:
                continue
            if min(first[1], second[1]) <= y < max(first[1], second[1]):
                ratio = (y - first[1]) / (second[1] - first[1])
                intersections.append(first[0] + ratio * (second[0] - first[0]))
        intersections.sort()
        for index in range(0, len(intersections) - 1, 2):
            start = max(0, int(intersections[index]))
            end = min(width - 1, int(intersections[index + 1]))
            for x in range(start, end + 1):
                pixel_index = (y * width + x) * 3
                pixels[pixel_index : pixel_index + 3] = bytes(color)


def _draw_polygon(
    pixels: bytearray,
    width: int,
    height: int,
    points: list[tuple[int, int]],
    color: tuple[int, int, int],
) -> None:
    for index, first in enumerate(points):
        second = points[(index + 1) % len(points)]
        _draw_line(pixels, width, height, first, second, color)


def _draw_line(
    pixels: bytearray,
    width: int,
    height: int,
    first: tuple[int, int],
    second: tuple[int, int],
    color: tuple[int, int, int],
) -> None:
    x0, y0 = first
    x1, y1 = second
    distance_x = abs(x1 - x0)
    step_x = 1 if x0 < x1 else -1
    distance_y = -abs(y1 - y0)
    step_y = 1 if y0 < y1 else -1
    error = distance_x + distance_y
    while True:
        if 0 <= x0 < width and 0 <= y0 < height:
            pixel_index = (y0 * width + x0) * 3
            pixels[pixel_index : pixel_index + 3] = bytes(color)
        if x0 == x1 and y0 == y1:
            return
        double_error = 2 * error
        if double_error >= distance_y:
            error += distance_y
            x0 += step_x
        if double_error <= distance_x:
            error += distance_x
            y0 += step_y
