from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main() -> int:
    arguments = _parse_args()
    input_path = Path(arguments.input).resolve()
    output_path = Path(arguments.output).resolve()
    if not input_path.is_file():
        print(json.dumps({"ok": False, "error": "Input model does not exist."}))
        return 2

    _clear_scene()
    try:
        bpy.ops.import_scene.gltf(filepath=str(input_path))
    except Exception as error:
        print(json.dumps({"ok": False, "error": f"Model import failed: {error}"}))
        return 2

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        print(json.dumps({"ok": False, "error": "The imported model has no mesh objects."}))
        return 2

    _configure_render(output_path)
    target, minimum, maximum = _bounds(mesh_objects)
    largest = max(maximum[index] - minimum[index] for index in range(3))
    largest = max(largest, 1.0)
    _create_camera(target, largest)
    _create_floor(target, minimum.z, largest)
    _create_lights(target, largest)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(output_path)
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as error:
        print(json.dumps({"ok": False, "error": f"Preview render failed: {error}"}))
        return 2
    print(json.dumps({"ok": True, "message": "Blender preview rendering completed"}))
    return 0


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(argv)


def _clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def _configure_render(output_path: Path) -> None:
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except (TypeError, ValueError):
            continue
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.filepath = str(output_path)
    world = scene.world or bpy.data.worlds.new("VarianPreviewWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.012, 0.019, 0.04, 1.0)
        background.inputs["Strength"].default_value = 0.28


def _bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector((
        min(corner.x for corner in corners),
        min(corner.y for corner in corners),
        min(corner.z for corner in corners),
    ))
    maximum = Vector((
        max(corner.x for corner in corners),
        max(corner.y for corner in corners),
        max(corner.z for corner in corners),
    ))
    return (minimum + maximum) * 0.5, minimum, maximum


def _create_camera(target: Vector, largest: float) -> None:
    distance = largest * 3.25
    location = target + Vector((distance, -distance, distance * 0.7))
    camera_data = bpy.data.cameras.new("VarianPreviewCamera")
    camera = bpy.data.objects.new("VarianPreviewCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    camera.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 52
    camera_data.sensor_width = 36
    camera_data.clip_start = max(0.001, largest * 0.001)
    camera_data.clip_end = largest * 20
    bpy.context.scene.camera = camera


def _create_floor(target: Vector, minimum_z: float, largest: float) -> None:
    bpy.ops.mesh.primitive_plane_add(size=largest * 8, location=(target.x, target.y, minimum_z - largest * 0.015))
    floor = bpy.context.object
    floor.name = "VarianPreviewFloor"
    material = bpy.data.materials.new("VarianPreviewFloorMaterial")
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = (0.025, 0.035, 0.065, 1.0)
        principled.inputs["Roughness"].default_value = 0.68
    floor.data.materials.append(material)


def _create_lights(target: Vector, largest: float) -> None:
    lights = (
        ("VarianPreviewKey", target + Vector((largest * 2.0, -largest * 2.0, largest * 2.8)), 950, 1.8, (0.72, 0.86, 1.0)),
        ("VarianPreviewFill", target + Vector((-largest * 2.0, -largest * 0.8, largest * 1.4)), 600, 2.2, (0.38, 0.58, 1.0)),
        ("VarianPreviewRim", target + Vector((largest * 0.6, largest * 2.0, largest * 2.2)), 850, 1.5, (1.0, 0.52, 0.3)),
    )
    for name, location, energy, size, color in lights:
        light_data = bpy.data.lights.new(name, type="AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = largest * size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.scene.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()


if __name__ == "__main__":
    raise SystemExit(main())
