import json
import re
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = "#101828"
OUTLINE = "#101828"


def to_pixel(origin, unit, value):
    return int(origin + value * unit)


def draw_rotated_tile(image, center, width, height, angle, fill, unit, origin):
    tile_width = int(width * unit) + int(10 * unit)
    tile_height = int(height * unit) + int(10 * unit)
    tile = Image.new("RGBA", (tile_width, tile_height), (0, 0, 0, 0))
    tile_draw = ImageDraw.Draw(tile)
    inset = int(5 * unit)
    tile_draw.rounded_rectangle(
        [inset, inset, tile_width - inset, tile_height - inset],
        radius=max(1, int(6 * unit)),
        fill=fill,
        outline=OUTLINE,
        width=max(1, int(2 * unit)),
    )
    rotated = tile.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    center_x = to_pixel(origin, unit, center[0])
    center_y = to_pixel(origin, unit, center[1])
    image.alpha_composite(
        rotated,
        (center_x - rotated.width // 2, center_y - rotated.height // 2),
    )


def render_icon(size, content_scale=1.0):
    supersample = 4
    high_size = size * supersample
    unit = high_size / 128 * content_scale
    origin = (high_size - 128 * unit) / 2
    image = Image.new("RGBA", (high_size, high_size), BACKGROUND)

    tile_specs = [
        ((35.5, 37.5), 19, 35, -30, "#FF6B6B"),
        ((46.5, 61.5), 19, 35, -30, "#F59E0B"),
        ((58.5, 83.5), 19, 31, -30, "#8B5CF6"),
        ((92.5, 37.5), 19, 35, 30, "#38BDF8"),
        ((81.5, 61.5), 19, 35, 30, "#2563EB"),
        ((69.5, 83.5), 19, 31, 30, "#22C55E"),
    ]
    for center, width, height, angle, fill in tile_specs:
        draw_rotated_tile(image, center, width, height, angle, fill, unit, origin)

    draw_rotated_tile(image, (64, 94), 16, 16, 45, "#F8FAFC", unit, origin)
    draw = ImageDraw.Draw(image)
    line_width = max(1, int(2 * unit))
    cross_points = [
        (
            (to_pixel(origin, unit, 60), to_pixel(origin, unit, 94)),
            (to_pixel(origin, unit, 68), to_pixel(origin, unit, 94)),
        ),
        (
            (to_pixel(origin, unit, 64), to_pixel(origin, unit, 90)),
            (to_pixel(origin, unit, 64), to_pixel(origin, unit, 98)),
        ),
    ]
    for start, end in cross_points:
        draw.line([start, end], fill=BACKGROUND, width=line_width)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_icon(path, size, content_scale=1.0):
    path.parent.mkdir(parents=True, exist_ok=True)
    render_icon(size, content_scale).save(path)


def render_ios_icons():
    icon_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for item in contents["images"]:
        filename = item.get("filename")
        if not filename:
            continue
        if item.get("idiom") == "ios-marketing":
            pixel_size = 1024
        else:
            match = re.search(r"(\d+(?:\.\d+)?)x\1@(\d+)x", filename)
            if not match:
                continue
            pixel_size = round(float(match.group(1)) * int(match.group(2)))
        save_icon(icon_dir / filename, pixel_size)


def render_macos_icons():
    icon_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in icon_dir.glob("app_icon_*.png"):
        match = re.search(r"app_icon_(\d+)\.png", path.name)
        if match:
            save_icon(path, int(match.group(1)))


def render_android_icons():
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for density, size in sizes.items():
        save_icon(ROOT / f"android/app/src/main/res/{density}/ic_launcher.png", size)


def render_web_icons():
    save_icon(ROOT / "web/favicon.png", 64, content_scale=0.9)
    save_icon(ROOT / "web/icons/Icon-192.png", 192, content_scale=0.92)
    save_icon(ROOT / "web/icons/Icon-512.png", 512, content_scale=0.92)
    save_icon(ROOT / "web/icons/Icon-maskable-192.png", 192, content_scale=0.82)
    save_icon(ROOT / "web/icons/Icon-maskable-512.png", 512, content_scale=0.82)


def render_windows_icon():
    icon_path = ROOT / "windows/runner/resources/app_icon.ico"
    icon_path.parent.mkdir(parents=True, exist_ok=True)
    render_icon(256).save(
        icon_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def render_linux_icon():
    save_icon(ROOT / "linux/resources/com.example.varian.png", 512)


save_icon(ROOT / "assets/image/varian_app_icon.png", 1024)
render_android_icons()
render_ios_icons()
render_macos_icons()
render_web_icons()
render_windows_icon()
render_linux_icon()
