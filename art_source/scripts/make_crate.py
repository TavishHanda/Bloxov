"""Bloxov test crate: builds a 1.0 x 0.75 x 0.7 m textured crate that matches docs/ART_SPEC.md.

How to use (Blender 4.x / 5.x):
  1. Save your .blend file into the repo's art_source/ folder first (so the relative paths work).
  2. Scripting tab > Text > Open > art_source/scripts/make_crate.py  (or paste this into a new text block)
  3. Press Run (the play button, or Alt+P).
Re-running it rebuilds the crate (it only touches objects it made, in the "Bloxov" collection).

What you get:
  - "crate": one object, origin at the bottom-center, FRONT facing +Y (hazard-striped plate marks the front).
    Plank body, wooden frame, metal corner caps. One material ("crate_mat") with one 32x32 pixel texture.
  - "REF_Player": a wireframe 0.8 x 1.8 m box showing how big the player is. Not exported.

Texture: 16 px per meter, painted only with the Bloxov palette (PALETTE below, also art_source/palette.gpl).
The atlas is four 16x16 tiles (planks, frame, metal, marker) and every face is box-projected in world units,
so 1 m on the crate = 16 texture pixels. The texture is saved to art_source/textures/crate.png. If that file
already exists it is loaded instead of regenerated, so you can hand-paint it (Aseprite, Krita...) and re-run.
Set REGENERATE_TEXTURE = True to throw your edits away and paint it from scratch again.

To export: set EXPORT = True below and run again. It writes assets/models/props/crate.glb.
"""
import os
import random

import bmesh
import bpy
from mathutils import Vector

EXPORT = False
EXPORT_PATH = "//../assets/models/props/crate.glb"  # relative to the saved .blend in art_source/
TEXTURE_PATH = "//textures/crate.png"
REGENERATE_TEXTURE = False

# Size in meters. Blender: X = width, Y = depth (front is +Y), Z = height.
WIDTH, DEPTH, HEIGHT = 1.0, 0.7, 0.75
CAP = 0.1875  # metal corner caps (3 px); their outer faces are the crate's bounds
FRAME = 0.125  # wooden posts and rims (2 px)
FRAME_INSET = 0.02  # frame sits this far inside the caps
BODY_INSET = 0.05  # plank panels sit this far inside the bounds

PX_PER_M = 16
TILE = 16  # px per atlas tile
ATLAS = 32  # atlas is 2 x 2 tiles
# Atlas tile (column, row) for each part. Row 0 is the bottom of the image.
TILE_PLANKS, TILE_FRAME, TILE_METAL, TILE_MARKER = (0, 0), (1, 0), (0, 1), (1, 1)

# Bloxov palette (24 colors). Paint only with these.
PALETTE = {
    "black": "1b1c1f",
    "iron_dark": "2f3236",
    "iron": "4b5057",
    "steel": "6f767d",
    "steel_light": "9aa1a6",
    "concrete": "b8b4aa",
    "bone": "e2dccb",
    "wood_dark": "4a2f1b",
    "wood_mid": "6e4628",
    "wood": "8f5e34",
    "wood_light": "b07a45",
    "wood_pale": "c99a5e",
    "rust": "8a3f1f",
    "red": "b03a2e",
    "hazard_yellow": "e8b923",
    "yellow_dark": "a8801a",
    "sand": "a89a6a",
    "olive_dark": "3d4228",
    "olive": "5b6236",
    "olive_light": "7d8450",
    "grass": "556b2f",
    "green_dark": "2e7d32",
    "extract_green": "4fd44a",
    "sky_blue": "3e6d8c",
}


def rgba(name):
    h = PALETTE[name]
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


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


# ---------------------------------------------------------------- texture

def paint_texture():
    """Paints the 32x32 atlas. Returns a flat RGBA list (bottom row first, like Blender)."""
    rng = random.Random(7)
    px = [[None] * ATLAS for _ in range(ATLAS)]  # px[y][x]

    def put(tile, x, y, color):
        px[tile[1] * TILE + y][tile[0] * TILE + x] = rgba(color)

    # Planks: 4 px tall boards (0.25 m), dark seam along the bottom of each, grain flecks, nail heads.
    for board in range(TILE // 4):
        base = rng.choice(["wood", "wood_light", "wood"])
        for y in range(board * 4, board * 4 + 4):
            for x in range(TILE):
                color = base
                if y == board * 4:
                    color = "wood_dark"
                else:
                    r = rng.random()
                    if r < 0.18:
                        color = "wood_mid"
                    elif r < 0.24:
                        color = "wood_pale" if base == "wood_light" else "wood_light"
                put(TILE_PLANKS, x, y, color)
        for x in (3, 12):
            put(TILE_PLANKS, x, board * 4 + 2, "iron_dark")

    # Frame: darker wood, a few flecks.
    for y in range(TILE):
        for x in range(TILE):
            r = rng.random()
            color = "wood_dark" if r < 0.1 else "wood" if r < 0.15 else "wood_mid"
            put(TILE_FRAME, x, y, color)

    # Metal caps: dark iron, speckled, with a light edge pixel now and then.
    for y in range(TILE):
        for x in range(TILE):
            r = rng.random()
            color = "iron_dark" if r < 0.2 else "steel" if r < 0.32 else "rust" if r < 0.35 else "iron"
            put(TILE_METAL, x, y, color)

    # Marker plate: diagonal hazard stripes.
    for y in range(TILE):
        for x in range(TILE):
            put(TILE_MARKER, x, y, "hazard_yellow" if (x + y) % 4 < 2 else "black")

    return [c for row in px for pixel in row for c in pixel]


def get_texture():
    path = bpy.path.abspath(TEXTURE_PATH)
    image = bpy.data.images.get("crate")
    if image is not None:
        bpy.data.images.remove(image)
    if os.path.exists(path) and not REGENERATE_TEXTURE:
        image = bpy.data.images.load(TEXTURE_PATH)
        image.name = "crate"
        return image
    image = bpy.data.images.new("crate", ATLAS, ATLAS, alpha=False)
    image.pixels = paint_texture()
    if bpy.data.filepath:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        image.filepath = TEXTURE_PATH  # keep it relative so the .blend works from any clone
    else:
        image.pack()
    return image


def make_material(image):
    mat = bpy.data.materials.get("crate_mat") or bpy.data.materials.new("crate_mat")
    mat.diffuse_color = (*rgba("wood")[:3], 1.0)
    try:
        mat.use_nodes = True  # always on in newer Blender; harmless there
    except (AttributeError, TypeError):
        pass
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for node in [n for n in nodes if n.type == "TEX_IMAGE"]:
        nodes.remove(node)
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"  # crisp pixels; the glTF exporter writes a nearest sampler
    tex.location = (bsdf.location.x - 300, bsdf.location.y)
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------- mesh

def add_box(bm, uv_layer, lo, hi, tile):
    """Adds an axis-aligned box from corner lo to corner hi, box-projecting UVs into the given atlas tile."""
    result = bmesh.ops.create_cube(bm, size=1.0)
    verts = result["verts"]
    for v in verts:
        v.co = Vector(tuple(lo[i] if v.co[i] < 0 else hi[i] for i in range(3)))
    for face in {f for v in verts for f in v.link_faces}:
        n = face.normal_update() or face.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            x, y, z = loop.vert.co.x + WIDTH / 2, loop.vert.co.y + DEPTH / 2, loop.vert.co.z
            a, b = ((y, z), (x, z), (x, y))[axis]
            u = (tile[0] * TILE + min(max(a * PX_PER_M, 0.0), TILE)) / ATLAS
            w = (tile[1] * TILE + min(max(b * PX_PER_M, 0.0), TILE)) / ATLAS
            loop[uv_layer].uv = (u, w)


def build_crate(material):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    hw, hd, h = WIDTH / 2, DEPTH / 2, HEIGHT
    fi, f, c, bi = FRAME_INSET, FRAME, CAP, BODY_INSET

    # Plank body, inset so the frame stands proud of it.
    add_box(bm, uv, (-hw + bi, -hd + bi, 0.005), (hw - bi, hd - bi, h - bi), TILE_PLANKS)
    # Corner posts and rims.
    for x in (-1, 1):
        for y in (-1, 1):
            add_box(bm, uv, (x * (hw - fi) - (x > 0) * f, y * (hd - fi) - (y > 0) * f, 0),
                    (x * (hw - fi) + (x < 0) * f, y * (hd - fi) + (y < 0) * f, h), TILE_FRAME)
    for z0 in (fi, h - fi - f):
        for y in (-1, 1):
            y0 = y * (hd - fi) - (y > 0) * f
            add_box(bm, uv, (-hw + fi, y0, z0), (hw - fi, y0 + f, z0 + f), TILE_FRAME)
        for x in (-1, 1):
            x0 = x * (hw - fi) - (x > 0) * f
            add_box(bm, uv, (x0, -hd + fi, z0), (x0 + f, hd - fi, z0 + f), TILE_FRAME)
    # Metal corner caps; their outer faces define the crate's bounds.
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (0, 1):
                lo = (hw - c if x > 0 else -hw, hd - c if y > 0 else -hd, h - c if z else 0)
                add_box(bm, uv, lo, (lo[0] + c, lo[1] + c, lo[2] + c), TILE_METAL)
    # Hazard plate on the front (+Y) panel, 8 x 4 px.
    add_box(bm, uv, (-0.25, hd - bi, 0.25), (0.25, hd - bi + 0.02, 0.5), TILE_MARKER)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("crate")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return bpy.data.objects.new("crate", mesh)


def build_player_reference():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    add_box(bm, uv, (-0.4, -0.4, 0), (0.4, 0.4, 1.8), TILE_FRAME)
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
    for name in ("crate_wood", "crate_frame", "crate_marker"):  # materials from the first version of this script
        old = bpy.data.materials.get(name)
        if old is not None and old.users == 0:
            bpy.data.materials.remove(old)

    crate = build_crate(make_material(get_texture()))
    reference = build_player_reference()
    coll.objects.link(crate)
    coll.objects.link(reference)

    bpy.context.view_layer.update()
    for obj in bpy.context.view_layer.objects:
        if obj is not None:
            obj.select_set(False)
    crate.select_set(True)
    bpy.context.view_layer.objects.active = crate
    tris = sum(len(p.vertices) - 2 for p in crate.data.polygons)
    print("Bloxov: built crate (%.2f x %.2f x %.2f m, %d tris), front = +Y" % (WIDTH, HEIGHT, DEPTH, tris))

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
