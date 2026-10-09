"""Bloxov parked car: builds the blocky sedan used as cover on Old Bloxov (docs/MAP_PLAN.md, docs/ART_SPEC.md).
It fits the gray-box car in tools/gen_old_bloxov.py: 1.9 m wide, 4.2 m long, 1.65 m tall (body 1.1 m, cabin 1.7 x 2.2 m).

How to use (Blender 4.x / 5.x):
  1. Save your .blend into the repo's art_source/ folder first (art_source/car.blend), so the relative paths work.
  2. Scripting tab > Text > Open > art_source/scripts/make_car.py, then Run (Alt+P).
Re-running rebuilds the cars (it only touches objects it made, in the "Bloxov" collection).

What you get: one object per paint job in VARIANTS (car_red, car_blue, car_rust), each with its own 128x128 texture
and material. Origin at the bottom-center, FRONT facing +Y (headlights and grille), so Godot's forward (-Z) is the
front. Blocky on purpose: boxes for the body, cabin, bumpers and wheels; doors, windows, lights and wear are painted.
  - "REF_Player": a wireframe 0.8 x 1.8 m box showing how big the player is. Not exported.

Texture: 16 px per meter, painted only with the Bloxov palette (PALETTE below, same as art_source/palette.gpl).
Every face is box-projected in meters onto one of a few atlas tiles (side, top, front, back, tire, bumper), so the side
tile is literally the car's side profile. Textures are saved to art_source/textures/<variant>.png. If a file exists
it's loaded instead of regenerated, so you can hand-paint it and re-run. REGENERATE_TEXTURE = True repaints them.

To export: set EXPORT = True and run again. It writes assets/models/props/<variant>.glb for every variant.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

EXPORT = False
EXPORT_DIR = "//../assets/models/props/"  # relative to the saved .blend in art_source/
TEXTURE_DIR = "//textures/"
REGENERATE_TEXTURE = False

# name: (paint, paint shade, rust spots chance, broken glass)
VARIANTS = {
    "car_red": ("red", "rust", 0.02, False),
    "car_blue": ("sky_blue", "iron", 0.02, False),
    "car_rust": ("rust", "wood_dark", 0.35, True),  # junkyard wreck
}

# Size in meters. Blender: X = width, Y = length (front is +Y), Z = height.
HW, HL = 0.95, 2.1          # half width, half length (with bumpers)
BODY_HL = 2.0               # body ends here, bumpers stick out to HL
BODY_Z = (0.42, 0.95)       # hood/trunk deck
SKIRT_Z = (0.28, BODY_Z[0])  # sill between the wheels
CAB_HW = 0.85
CAB_Y = (-1.25, 0.95)       # cabin, 2.2 m long, set back a little like a sedan
CAB_TOP = 1.65
BUMPER_Z = (0.30, 0.52)
WHEEL_Y = 1.32              # wheel centers at +-WHEEL_Y
WHEEL_R = 0.31
WHEEL_X = (0.68, 0.93)
ARCH_R = 0.40

PX_PER_M = 16
ATLAS = 128
# Atlas tiles (px origin x, y; y counts up from the bottom of the image, like Blender).
T_SIDE = (0, 0)       # 68 x 27: u = meters from the back, v = height
T_TOP = (70, 0)       # 31 x 68: u = meters from the left, v = meters from the back
T_FRONT = (0, 30)     # 31 x 27
T_BACK = (33, 30)     # 31 x 27
T_TIRE = (0, 60)      # 16 x 16, wheel centered at (8, 8)
T_BUMPER = (20, 60)   # 16 x 8 steel
T_UNDER = (40, 60)    # 8 x 8 black

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


def px(m):
    return int(math.floor(m * PX_PER_M + 1e-6))


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

def paint_texture(variant):
    paint, shade, rust_chance, broken = VARIANTS[variant]
    rng = random.Random(sum(map(ord, variant)))
    img = [[rgba("black")] * ATLAS for _ in range(ATLAS)]  # img[y][x]

    def put(tile, x, y, color):
        X, Y = tile[0] + x, tile[1] + y
        if 0 <= X < ATLAS and 0 <= Y < ATLAS:
            img[Y][X] = rgba(color)

    def rect(tile, x0, y0, x1, y1, color):
        for y in range(y0, y1):
            for x in range(x0, x1):
                put(tile, x, y, color)

    def paint_px():
        r = rng.random()
        if r < rust_chance:
            return "rust" if paint != "rust" else "wood_mid"
        if r < rust_chance + 0.03:
            return shade
        return paint

    def body(tile, w, h, dirt_rows=2):
        for y in range(h):
            for x in range(w):
                c = paint_px()
                if y < dirt_rows and rng.random() < 0.5:
                    c = "wood_mid" if rng.random() < 0.6 else "sand"
                put(tile, x, y, c)

    def glass(tile, x0, y0, x1, y1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                c = "iron_dark"
                if (x - x0) - (y - y0) in (2, 3):  # one glint stripe
                    c = "steel"
                if broken and rng.random() < 0.25:
                    c = "black"
                put(tile, x, y, c)

    side_w, side_h = px(2 * HL) + 1, px(CAB_TOP) + 1
    front_w = px(2 * HW) + 1

    # --- side (u = meters from the back bumper, v = height); the right side is mirrored by the UVs
    body(T_SIDE, side_w, side_h, dirt_rows=px(BODY_Z[0]) + 2)
    rect(T_SIDE, 0, px(BODY_Z[1]), px(HL + CAB_Y[0]), side_h, "black")  # nothing above the deck: never seen
    rect(T_SIDE, px(HL + CAB_Y[1]) + 1, px(BODY_Z[1]), side_w, side_h, "black")
    # wheel arches: dark half-circles around the wheels
    for wy in (-WHEEL_Y, WHEEL_Y):
        cu, cv = (HL + wy) * PX_PER_M, WHEEL_R * PX_PER_M
        for y in range(side_h):
            for x in range(side_w):
                if math.hypot(x + 0.5 - cu, y + 0.5 - cv) < ARCH_R * PX_PER_M and y + 0.5 > cv - 2:
                    put(T_SIDE, x, y, "black")
    # chrome trim along the body, door seams and handles
    trim = px(0.78)
    for x in range(px(HL - BODY_HL) + 1, px(HL + BODY_HL) - 1):
        if rng.random() > 0.08:
            put(T_SIDE, x, trim, "steel_light" if paint != "rust" else "steel")
    for seam_y in (CAB_Y[0] + 0.15, -0.15, CAB_Y[1] - 0.05):
        x = px(HL + seam_y)
        for y in range(px(BODY_Z[0]) + 1, px(CAB_TOP) - 1):
            put(T_SIDE, x, y, "black")
    for handle_y in (-0.35, CAB_Y[1] - 0.25):
        put(T_SIDE, px(HL + handle_y), px(0.86), "steel_light")
        put(T_SIDE, px(HL + handle_y) - 1, px(0.86), "steel_light")
    # windows, split by the middle pillar
    wz0, wz1 = px(BODY_Z[1]) + 2, px(CAB_TOP) - 1
    glass(T_SIDE, px(HL + CAB_Y[0]) + 2, wz0, px(HL - 0.15), wz1)
    glass(T_SIDE, px(HL - 0.15) + 1, wz0, px(HL + CAB_Y[1]) - 1, wz1)
    # marker lights at the corners: amber front, red back
    put(T_SIDE, side_w - 3, px(0.68), "hazard_yellow")
    put(T_SIDE, 2, px(0.68), "red" if paint != "red" else "rust")

    # --- top (u = meters from the left side, v = meters from the back)
    top_w, top_h = front_w, side_w
    body(T_TOP, top_w, top_h, dirt_rows=0)
    for x in range(top_w):  # seams: trunk lid, hood
        put(T_TOP, x, px(HL + CAB_Y[0]) - 3, "black")
        put(T_TOP, x, px(HL + CAB_Y[1]) + 3, "black")
    # dust and leaves on the roof and hood
    for _ in range(28):
        put(T_TOP, rng.randrange(top_w), rng.randrange(top_h), "sand" if rng.random() < 0.6 else "olive")

    # --- front and back (u = meters from the left as seen from that end, v = height)
    for tile, front in ((T_FRONT, True), (T_BACK, False)):
        body(tile, front_w, side_h, dirt_rows=px(BODY_Z[0]) + 2)
        cx0, cx1 = px(HW - CAB_HW), px(HW + CAB_HW)
        rect(tile, 0, px(BODY_Z[1]), cx0, side_h, "black")
        rect(tile, cx1 + 1, px(BODY_Z[1]), front_w, side_h, "black")
        glass(tile, cx0 + 2, wz0, cx1 - 1, wz1)
        lz0, lz1 = px(0.62), px(0.82)
        if front:
            rect(tile, px(HW - 0.5), px(0.56), px(HW + 0.5), px(0.84), "iron_dark")  # grille
            for x in range(px(HW - 0.5), px(HW + 0.5), 2):
                rect(tile, x, px(0.56), x + 1, px(0.84), "black")
            for x0 in (2, front_w - 5):
                rect(tile, x0, lz0, x0 + 3, lz1, "bone" if not broken else "concrete")
                put(tile, x0 + (2 if x0 == 2 else 0), lz0 - 1, "hazard_yellow")
        else:
            for x0 in (2, front_w - 5):
                rect(tile, x0, lz0, x0 + 3, lz1, "red" if paint != "red" else "rust")
            rect(tile, px(HW) - 3, px(0.56), px(HW) + 3, px(0.68), "bone")  # plate
            put(tile, px(HW) - 1, px(0.6), "black")
            put(tile, px(HW) + 1, px(0.6), "black")

    # --- tire (wheel face centered at 8, 8), bumper steel, underside black
    for y in range(16):
        for x in range(16):
            d = math.hypot(x + 0.5 - 8, y + 0.5 - 8)
            c = "black"
            if d < WHEEL_R * PX_PER_M * 0.45:
                c = "steel" if not broken else "rust"
            elif d < WHEEL_R * PX_PER_M * 0.6:
                c = "iron"
            elif rng.random() < 0.1:
                c = "iron_dark"
            put(T_TIRE, x, y, c)
    for y in range(8):
        for x in range(16):
            c = "steel_light" if y >= 5 else "steel"
            if rng.random() < (0.3 if broken else 0.06):
                c = "rust"
            put(T_BUMPER, x, y, c)

    return [c for row in img for pixel in row for c in pixel]


def get_texture(variant):
    path = bpy.path.abspath(TEXTURE_DIR + variant + ".png")
    image = bpy.data.images.get(variant)
    if image is not None:
        bpy.data.images.remove(image)
    if os.path.exists(path) and not REGENERATE_TEXTURE:
        image = bpy.data.images.load(TEXTURE_DIR + variant + ".png")
        image.name = variant
        return image
    image = bpy.data.images.new(variant, ATLAS, ATLAS, alpha=False)
    image.pixels = paint_texture(variant)
    if bpy.data.filepath:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        image.filepath = TEXTURE_DIR + variant + ".png"
    else:
        image.pack()
    return image


def make_material(variant, image):
    name = variant + "_mat"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*rgba(VARIANTS[variant][0])[:3], 1.0)
    try:
        mat.use_nodes = True
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
    tex.interpolation = "Closest"
    tex.location = (bsdf.location.x - 300, bsdf.location.y)
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------- mesh

def body_uv(co, normal):
    """Box-projects a body point onto the side, top, front or back tile, as seen from outside."""
    x, y, z = co.x, co.y, co.z
    axis = max(range(3), key=lambda i: abs(normal[i]))
    pos = normal[axis] > 0
    if axis == 0:
        return T_SIDE, ((HL + y) if pos else (HL - y)), z
    if axis == 1:
        return (T_FRONT, HW - x, z) if pos else (T_BACK, HW + x, z)
    if pos:
        return T_TOP, HW + x, HL + y
    return T_UNDER, 0.1, 0.1


def wheel_uv(co, normal, wy):
    axis = max(range(3), key=lambda i: abs(normal[i]))
    if axis == 0:
        return T_TIRE, (co.y - wy) + 8 / PX_PER_M, co.z - WHEEL_R + 8 / PX_PER_M
    return T_TIRE, 0.05, 0.05  # tread: a black corner


def bumper_uv(co, normal):
    """Steel bumpers: the darker lower rows on the sides, the bright top row on top."""
    axis = max(range(3), key=lambda i: abs(normal[i]))
    a = min(max((co.x + HW) / (2 * HW), 0.0), 1.0) * 15 / PX_PER_M
    if axis == 2:
        return T_BUMPER, a, 7.5 / PX_PER_M
    return T_BUMPER, a, min(max(co.z - BUMPER_Z[0], 0.0), 7.5 / PX_PER_M)


def add_box(bm, uv_layer, lo, hi, uv_fn):
    verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    for v in verts:
        v.co = Vector(tuple(lo[i] if v.co[i] < 0 else hi[i] for i in range(3)))
    for face in {f for v in verts for f in v.link_faces}:
        face.normal_update()
        center = face.calc_center_median()
        for loop in face.loops:
            # nudge toward the face center so edge texels never bleed in from the next tile
            co = loop.vert.co + (center - loop.vert.co) * 0.002
            tile, a, b = uv_fn(co, face.normal)
            loop[uv_layer].uv = ((tile[0] + a * PX_PER_M) / ATLAS, (tile[1] + b * PX_PER_M) / ATLAS)


def build_car(variant, material):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    # body deck, sills between the wheels, cabin
    add_box(bm, uv, (-HW, -BODY_HL, BODY_Z[0]), (HW, BODY_HL, BODY_Z[1]), body_uv)
    sill = WHEEL_Y - ARCH_R
    add_box(bm, uv, (-HW, -sill, SKIRT_Z[0]), (HW, sill, SKIRT_Z[1]), body_uv)
    add_box(bm, uv, (-CAB_HW, CAB_Y[0], BODY_Z[1]), (CAB_HW, CAB_Y[1], CAB_TOP), body_uv)
    # bumpers
    for s in (-1, 1):
        add_box(bm, uv, (-HW + 0.05, min(s * BODY_HL, s * HL), BUMPER_Z[0]),
                (HW - 0.05, max(s * BODY_HL, s * HL), BUMPER_Z[1]), bumper_uv)
    # wheels (tucked under the body; only the part below the deck shows)
    for wy in (-WHEEL_Y, WHEEL_Y):
        for s in (-1, 1):
            add_box(bm, uv, (min(s * WHEEL_X[0], s * WHEEL_X[1]), wy - WHEEL_R, 0.0),
                    (max(s * WHEEL_X[0], s * WHEEL_X[1]), wy + WHEEL_R, 2 * WHEEL_R),
                    lambda co, n, wy=wy: wheel_uv(co, n, wy))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(variant)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    return bpy.data.objects.new(variant, mesh)


def build_player_reference():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.8, v.co.y * 0.8, (v.co.z + 0.5) * 1.8))
    mesh = bpy.data.meshes.new("REF_Player")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("REF_Player", mesh)
    obj.location = (-1.6, 0, 0)
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def main():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    coll = get_collection("Bloxov")
    remove_object("REF_Player")
    coll.objects.link(build_player_reference())

    for i, variant in enumerate(VARIANTS):
        remove_object(variant)
        car = build_car(variant, make_material(variant, get_texture(variant)))
        coll.objects.link(car)
        bpy.context.view_layer.update()
        tris = sum(len(p.vertices) - 2 for p in car.data.polygons)
        print("Bloxov: built %s (%.2f x %.2f x %.2f m, %d tris), front = +Y" % (variant, 2 * HW, CAB_TOP, 2 * HL, tris))
        if EXPORT:
            if not bpy.data.filepath:
                raise RuntimeError("Save the .blend into the repo's art_source/ folder first, then run again.")
            for obj in bpy.context.view_layer.objects:
                obj.select_set(False)
            car.select_set(True)
            bpy.context.view_layer.objects.active = car
            path = bpy.path.abspath(EXPORT_DIR + variant + ".glb")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                      export_yup=True, export_apply=True)
            print("Bloxov: exported", path)
        car.location.x = i * 2.6  # side by side in the .blend (after export, so the .glb stays at the origin)


main()
