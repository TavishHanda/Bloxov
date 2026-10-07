"""Bloxov test crate: builds a 1.0 x 0.75 x 0.7 m crate that matches docs/ART_SPEC.md.

How to use (Blender 4.x / 5.x):
  1. Save your .blend file into the repo's art_source/ folder first (so the export path works).
  2. Scripting tab > Text > Open > art_source/scripts/make_crate.py  (or paste this into a new text block)
  3. Press Run (the play button, or Alt+P).
Re-running it rebuilds the crate (it only touches objects it made, in the "Bloxov" collection).

What you get:
  - "crate": one object, origin at the bottom-center, FRONT facing +Y (yellow plate marks the front).
    Three materials (wood, frame, marker) with basic UVs, ready for you to texture.
  - "REF_Player": a wireframe 0.8 x 1.8 m box showing how big the player is. Not exported.

To export: set EXPORT = True below and run again. It writes assets/models/props/crate.glb.
"""
import os

import bmesh
import bpy
from mathutils import Vector

EXPORT = False
EXPORT_PATH = "//../assets/models/props/crate.glb"  # relative to the saved .blend in art_source/

# Size in meters. Blender: X = width, Y = depth (front is +Y), Z = height.
WIDTH, DEPTH, HEIGHT = 1.0, 0.7, 0.75
FRAME = 0.08  # thickness of the corner posts and rims

COLORS = {
    "crate_wood": (0.62, 0.43, 0.22),
    "crate_frame": (0.38, 0.25, 0.12),
    "crate_marker": (1.0, 0.8, 0.1),
}


def get_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def remove_object(name):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def make_material(name, rgb):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)  # viewport color
    try:
        mat.use_nodes = True  # always on in newer Blender; harmless there
    except (AttributeError, TypeError):
        pass
    if mat.node_tree is not None:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def add_box(bm, uv_layer, center, size, material_index):
    """Adds an axis-aligned box to the bmesh. center/size are (x, y, z) in meters."""
    result = bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    verts = result["verts"]
    for v in verts:
        v.co = Vector((center[0] + v.co.x * size[0], center[1] + v.co.y * size[1], center[2] + v.co.z * size[2]))
    for face in {f for v in verts for f in v.link_faces}:
        face.material_index = material_index


def build_crate():
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    hw, hd, f = WIDTH / 2, DEPTH / 2, FRAME

    # Body, slightly inset so the frame sticks out.
    add_box(bm, uv_layer, (0, 0, HEIGHT / 2), (WIDTH - f * 0.75, DEPTH - f * 0.75, HEIGHT - f * 0.75), 0)
    # Corner posts.
    for x in (-hw + f / 2, hw - f / 2):
        for y in (-hd + f / 2, hd - f / 2):
            add_box(bm, uv_layer, (x, y, HEIGHT / 2), (f, f, HEIGHT), 1)
    # Top and bottom rims.
    for z in (f / 2, HEIGHT - f / 2):
        for y in (-hd + f / 2, hd - f / 2):
            add_box(bm, uv_layer, (0, y, z), (WIDTH, f, f), 1)
        for x in (-hw + f / 2, hw - f / 2):
            add_box(bm, uv_layer, (x, 0, z), (f, DEPTH, f), 1)
    # Front marker plate on the +Y face.
    add_box(bm, uv_layer, (0, hd + 0.005, HEIGHT * 0.55), (0.3, 0.02, 0.15), 2)

    mesh = bpy.data.meshes.new("crate")
    bm.to_mesh(mesh)
    bm.free()
    for name in ("crate_wood", "crate_frame", "crate_marker"):
        mesh.materials.append(make_material(name, COLORS[name]))
    return bpy.data.objects.new("crate", mesh)


def build_player_reference():
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    add_box(bm, uv_layer, (0, 0, 0.9), (0.8, 0.8, 1.8), 0)
    mesh = bpy.data.meshes.new("REF_Player")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("REF_Player", mesh)
    obj.location = (1.5, 0, 0)
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def main():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    coll = get_collection("Bloxov")
    remove_object("crate")
    remove_object("REF_Player")

    crate = build_crate()
    reference = build_player_reference()
    coll.objects.link(crate)
    coll.objects.link(reference)

    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    crate.select_set(True)
    bpy.context.view_layer.objects.active = crate
    print("Bloxov: built crate (%.2f x %.2f x %.2f m), front = +Y" % (WIDTH, HEIGHT, DEPTH))

    if EXPORT:
        if not bpy.data.filepath:
            raise RuntimeError("Save the .blend into the repo's art_source/ folder first, then run again.")
        path = bpy.path.abspath(EXPORT_PATH)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
        )
        print("Bloxov: exported", path)


main()
