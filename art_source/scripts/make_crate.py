"""Bloxov loot crate: builds a 1.1 x 0.5 x 0.6 m military hard transport case that matches docs/ART_SPEC.md.
The object and files keep the name "crate" because the game's loot crate scene uses them.

How to use (Blender 4.x / 5.x):
  1. Save your .blend file into the repo's art_source/ folder first (so the relative paths work).
  2. Scripting tab > Text > Open > art_source/scripts/make_crate.py  (or paste this into a new text block)
  3. Press Run (the play button, or Alt+P).
Re-running it rebuilds the case (it only touches objects it made, in the "Bloxov" collection).

What you get:
  - "crate": one object, origin at the bottom-center, FRONT facing +Y (latches and label strip mark it).
    Long, low moulded olive shell with bevelled corners and a reinforcing band, a thin lid on a dark gasket
    seam, two stacking ribs with a spray-painted emblem on the lid (EMBLEM), black latches, back hinges,
    fold-down side handles, four skids underneath. One material ("crate_mat") with one 64x64 pixel texture.
  - "REF_Player": a wireframe 0.8 x 1.8 m box showing how big the player is. Not exported.

Texture: 16 px per meter, painted only with the Bloxov palette (PALETTE below, same as art_source/palette.gpl).
The atlas is 32x16 px tiles (front, back, side, top, hardware) and every face is box-projected in world units,
so 1 m on the case = 16 texture pixels and the seam, scuffs and emblem line up with the geometry.
The texture is saved to art_source/textures/crate.png. If that file already exists it is loaded instead of
regenerated, so you can hand-paint it (Aseprite, Krita...) and re-run.
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
WIDTH, DEPTH, HEIGHT = 1.1, 0.6, 0.5
P = 1 / 16  # one texture pixel in meters
CHAMFER = 2 * P  # bevel on the vertical corners of the shell
SKID = 0.045  # skids underneath; the body starts just below their tops
BODY_HX, BODY_HY = WIDTH / 2 - 0.025, DEPTH / 2 - 0.02  # lid overhangs the body by this little
BODY_BOTTOM, BODY_TOP = 0.04, 5 * P  # body is texture rows 0-4
BAND_Z = (2 * P, 3 * P)  # reinforcing band around the body (row 2)
BAND_OUT = 0.015  # how far the band stands proud of the body
LID_BOTTOM, LID_TOP = 0.335, HEIGHT - 0.03  # gasket seam below the lid; ribs reach HEIGHT
RIB_Y = (3 * P, 4 * P)  # stacking ribs on the lid, mirrored front and back
RIB_HX = 0.45

PX_PER_M = 16
TILE_W, TILE_H = 32, 16  # px per atlas tile (the 1.1 m front is 17.6 px wide)
ATLAS_W, ATLAS_H = 64, 64
# Atlas tile (column, row). Row 0 is the bottom of the image.
TILE_FRONT, TILE_BACK, TILE_SIDE, TILE_TOP = (0, 0), (1, 0), (0, 1), (1, 1)
TILE_HARDWARE = (0, 2)
SEAM_ROW = 5  # texture row of the gasket seam on the front, back and sides (z 0.3125 - 0.375)

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

# Spray-painted mark on the lid, between the ribs (7 x 6 px, top row first, read from the front).
EMBLEMS = {
    "star": ["...#...", "..###..", "#######", ".#####.", ".##.##.", ".#...#."],
    "skull": [".#####.", "#######", "#..#..#", "###.###", ".#####.", ".#.#.#."],
}
EMBLEM = "skull"
EMBLEM_COLOR = "concrete"  # faded white
EMBLEM_LEFT, EMBLEM_TOP = 5, 7  # lid-top tile px of the emblem's top-left


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
    """Paints the atlas. Returns a flat RGBA list (bottom row first, like Blender)."""
    rng = random.Random(7)
    px = [[rgba("olive")] * ATLAS_W for _ in range(ATLAS_H)]  # px[y][x]

    def put(tile, x, y, color):
        if 0 <= x < TILE_W and 0 <= y < TILE_H:
            px[tile[1] * TILE_H + y][tile[0] * TILE_W + x] = rgba(color)

    def shell(tile, grime_rows=(0,)):
        """Matte moulded plastic: flat olive, faint mottling, dirt along the bottom."""
        for y in range(TILE_H):
            for x in range(TILE_W):
                color = "olive_dark" if rng.random() < 0.03 else "olive"
                if y in grime_rows and rng.random() < 0.45:
                    color = "olive_dark"
                put(tile, x, y, color)

    def scuffs(tile, cells, chance=0.1):
        """Scuffed edges: lighter worn plastic, now and then a pale scratch."""
        for x, y in sorted(cells):
            r = rng.random()
            if r < chance:
                put(tile, x, y, "olive_light")
            elif r < chance + 0.015:
                put(tile, x, y, "sand")

    def edge_cells(cols, rows, col_span, row_span):
        return {(c, y) for c in cols for y in range(*row_span)} | {(x, r) for r in rows for x in range(*col_span)}

    def seam(tile):
        for x in range(TILE_W):
            put(tile, x, SEAM_ROW, "black" if rng.random() < 0.6 else "iron_dark")

    # Front and back: body rows 0-4 (u 0-17), band row 2, seam row 5, lid rows 6-7.
    for tile in (TILE_FRONT, TILE_BACK):
        shell(tile)
        scuffs(tile, edge_cells((0, 17), (4,), (0, 18), (0, 5)) | edge_cells((0, 17), (6, 7), (0, 18), (6, 8)))
        scuffs(tile, edge_cells((), (2,), (0, 18), (0, 0)), 0.12)  # the band takes the knocks
        seam(tile)
    # Label strip on the front, low and off to one side below the band.
    for x in range(11, 14):
        put(TILE_FRONT, x, 1, "concrete")
    # Sides: body u 0-9 (0.56 m deep), lid u 0-9.
    shell(TILE_SIDE)
    scuffs(TILE_SIDE, edge_cells((0, 9), (4,), (0, 10), (0, 5)) | edge_cells((0, 9), (6, 7), (0, 10), (6, 8)))
    scuffs(TILE_SIDE, edge_cells((), (2,), (0, 10), (0, 0)), 0.12)
    seam(TILE_SIDE)
    # Lid top: u 0-17 by v 0-9, ribs at v 1 and 8, scuffs on the rim and rib tops.
    shell(TILE_TOP, grime_rows=())
    scuffs(TILE_TOP, edge_cells((0, 17), (0, 9), (0, 18), (0, 10)) | edge_cells((), (1, 8), (2, 16), (0, 0)), 0.2)

    # Spray-painted emblem on the lid top, with a few worn gaps.
    emblem = EMBLEMS[EMBLEM]
    for row, line in enumerate(emblem):
        for col, cell in enumerate(line):
            if cell == "#" and rng.random() > 0.06:
                put(TILE_TOP, EMBLEM_LEFT + col, EMBLEM_TOP - row, EMBLEM_COLOR)

    # Hardware (latches, hinges, handles, skids): black plastic and dark metal.
    for y in range(TILE_H):
        for x in range(TILE_W):
            r = rng.random()
            put(TILE_HARDWARE, x, y, "black" if r < 0.25 else "iron" if r < 0.35 else "iron_dark")

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
    image = bpy.data.images.new("crate", ATLAS_W, ATLAS_H, alpha=False)
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
    mat.diffuse_color = (*rgba("olive")[:3], 1.0)
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

def face_uv(co, normal):
    """Box-projects a point to (u, v) in px within a tile, as seen by someone looking at that face
    (so text reads left to right from outside; the lid top reads from the front). Also returns the tile."""
    x, y, z = co.x + WIDTH / 2, co.y + DEPTH / 2, co.z
    axis = max(range(3), key=lambda i: abs(normal[i]))
    positive = normal[axis] > 0
    if axis == 0:
        a, b, tile = (y if positive else DEPTH - y), z, TILE_SIDE
    elif axis == 1:
        a, b, tile = (WIDTH - x if positive else x), z, TILE_FRONT if positive else TILE_BACK
    else:
        a, b = (WIDTH - x, DEPTH - y) if positive else (x, y)
        tile = TILE_TOP
    return a * PX_PER_M, b * PX_PER_M, tile


def set_uvs(faces, uv_layer, tile=None):
    """tile=None picks the painted tile from each face's direction; otherwise every face uses that tile."""
    for face in faces:
        face.normal_update()
        for loop in face.loops:
            a, b, face_tile = face_uv(loop.vert.co, face.normal)
            t = tile or face_tile
            u = (t[0] * TILE_W + min(max(a, 0.0), TILE_W)) / ATLAS_W
            w = (t[1] * TILE_H + min(max(b, 0.0), TILE_H)) / ATLAS_H
            loop[uv_layer].uv = (u, w)


def add_box(bm, uv_layer, lo, hi, tile=None):
    """Adds an axis-aligned box from corner lo to corner hi."""
    verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    for v in verts:
        v.co = Vector(tuple(lo[i] if v.co[i] < 0 else hi[i] for i in range(3)))
    set_uvs({f for v in verts for f in v.link_faces}, uv_layer, tile)


def add_chamfered_box(bm, uv_layer, hx, hy, z0, z1, c, tile=None):
    """Adds a box centered on X/Y with its four vertical edges bevelled by c (an octagonal prism)."""
    ring = [(hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c),
            (-hx + c, -hy), (hx - c, -hy), (hx, -hy + c), (hx, hy - c)]
    bottom = [bm.verts.new((x, y, z0)) for x, y in ring]
    top = [bm.verts.new((x, y, z1)) for x, y in ring]
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bottom)))]
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((bottom[i], bottom[j], top[j], top[i])))  # wound to face outward
    set_uvs(faces, uv_layer, tile)


def build_crate(material):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    hw, hd, h = WIDTH / 2, DEPTH / 2, HEIGHT

    # Shell: body, reinforcing band, dark gasket core in the seam, lid that overhangs to the full bounds.
    add_chamfered_box(bm, uv, BODY_HX, BODY_HY, BODY_BOTTOM, BODY_TOP, CHAMFER)
    add_chamfered_box(bm, uv, BODY_HX + BAND_OUT, BODY_HY + BAND_OUT, BAND_Z[0], BAND_Z[1], CHAMFER + BAND_OUT * 0.4)
    add_box(bm, uv, (-0.47, -0.19, BODY_TOP - 0.01), (0.47, 0.19, LID_BOTTOM + 0.01))
    add_chamfered_box(bm, uv, hw, hd, LID_BOTTOM, LID_TOP, CHAMFER)
    # Stacking ribs on the lid (their bottoms are buried in the lid, so no faces overlap).
    for y0, y1 in (RIB_Y, (-RIB_Y[1], -RIB_Y[0])):
        add_box(bm, uv, (-RIB_HX, y0, LID_TOP - 0.005), (RIB_HX, y1, h))
    # Two front latches and two back hinges under the lid lip, 2 px wide (they stop at the lid, so no overlap).
    for x0 in (-0.375, 0.25):
        add_box(bm, uv, (x0, BODY_HY - 0.005, 0.22), (x0 + 2 * P, hd, LID_BOTTOM), TILE_HARDWARE)
        add_box(bm, uv, (x0, -hd, 0.26), (x0 + 2 * P, -BODY_HY + 0.005, LID_BOTTOM), TILE_HARDWARE)
    # Fold-down side handles above the band: two brackets, then a grip bar that starts where they end.
    for s in (-1, 1):
        face, bar_x = s * (BODY_HX - 0.005), s * (hw - 0.012)
        for y0 in (-2 * P, P):
            add_box(bm, uv, (min(face, bar_x), y0, 0.20), (max(face, bar_x), y0 + P, 0.28), TILE_HARDWARE)
        add_box(bm, uv, (min(bar_x, s * hw), -2 * P, 0.20), (max(bar_x, s * hw), 2 * P, 0.23), TILE_HARDWARE)
    # Skids, tucked under the body corners.
    for x in (-1, 1):
        for y in (-1, 1):
            add_box(bm, uv, (min(x * 0.30, x * 0.44), min(y * 0.10, y * 0.22), 0),
                    (max(x * 0.30, x * 0.44), max(y * 0.10, y * 0.22), SKID), TILE_HARDWARE)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("crate")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return bpy.data.objects.new("crate", mesh)


def build_player_reference():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    add_box(bm, uv, (-0.4, -0.4, 0), (0.4, 0.4, 1.8), TILE_HARDWARE)
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
