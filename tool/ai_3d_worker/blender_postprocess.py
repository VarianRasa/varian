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
    if input_path.suffix.lower() == ".glb":
        bpy.ops.import_scene.gltf(filepath=str(input_path))
    elif input_path.suffix.lower() in (".gltf",):
        bpy.ops.import_scene.gltf(filepath=str(input_path))
    elif input_path.suffix.lower() == ".obj":
        bpy.ops.wm.obj_import(filepath=str(input_path))
    elif input_path.suffix.lower() == ".ply":
        bpy.ops.wm.ply_import(filepath=str(input_path))
    else:
        print(json.dumps({"ok": False, "error": "Unsupported input model format."}))
        return 2

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        print(json.dumps({"ok": False, "error": "The imported model has no mesh objects."}))
        return 2
    _normalize_geometry(mesh_objects)
    if arguments.texture_mode == "none":
        _remove_image_textures(mesh_objects)
    _reduce_triangles(mesh_objects, max(1, arguments.triangle_budget))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        export_apply=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        use_selection=False,
    )
    print(json.dumps({"ok": True, "message": "Blender post-processing completed"}))
    return 0


def _clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--triangle-budget", type=int, required=True)
    parser.add_argument("--texture-mode", choices=("none", "vertex_color", "pbr"), default="pbr")
    return parser.parse_args(argv)


def _normalize_geometry(objects: list[bpy.types.Object]) -> None:
    corners: list[Vector] = []
    for obj in objects:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    minimum = [min(corner[index] for corner in corners) for index in range(3)]
    maximum = [max(corner[index] for corner in corners) for index in range(3)]
    center = Vector(((minimum[index] + maximum[index]) / 2 for index in range(3)))
    largest = max(maximum[index] - minimum[index] for index in range(3))
    scale = 2.0 / largest if largest > 0 else 1.0
    for obj in objects:
        obj.location -= center
        obj.scale *= scale
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.select_set(False)


def _remove_image_textures(objects: list[bpy.types.Object]) -> None:
    materials = {
        material
        for obj in objects
        for material_slot in obj.material_slots
        if (material := material_slot.material) is not None
    }
    for material in materials:
        if not material.use_nodes:
            continue
        for node in list(material.node_tree.nodes):
            if node.type == "TEX_IMAGE":
                material.node_tree.nodes.remove(node)


def _reduce_triangles(objects: list[bpy.types.Object], budget: int) -> None:
    current = sum(_object_triangles(obj) for obj in objects)
    if current <= budget:
        return
    ratio = max(0.01, min(1.0, budget / current))
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="VarianTriangleBudget", type="DECIMATE")
        modifier.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)


def _object_triangles(obj: bpy.types.Object) -> int:
    return sum(max(0, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


if __name__ == "__main__":
    raise SystemExit(main())
