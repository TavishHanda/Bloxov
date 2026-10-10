"""Bloxov town square props for Old Bloxov: planter, market stall, fountain and statue (docs/MAP_PLAN.md, docs/ART_SPEC.md).
Each one fits its gray box in tools/gen_old_bloxov.py (sizes in PROPS below). Old Bloxov theme (owner): 2000s,
abandoned but intact, summer, nothing that points to a country.

How to use (Blender 4.x / 5.x):
  1. Save your .blend into the repo's art_source/ folder first (art_source/square.blend), so the relative paths work.
  2. Scripting tab > Text > Open > art_source/scripts/make_square.py, then Run (Alt+P).
Re-running rebuilds the props (it only touches objects it made, in the "Bloxov" collection).

What you get: one object per prop, origin at the bottom-center, FRONT facing +Y (the stall's counter, the statue's
plaque). Options use the outfit naming from make_character.py, so scripts/pixel_model.gd shows one at random:
  stall: Canopy__blue / Canopy__red (the planter always has flowers)
Materials are small tiling textures shared by all the props (mat_concrete, mat_wood...), mapped in meters, so
1 m = 16 px everywhere and the same files can dress buildings later. Painted only with the Bloxov palette.
Textures are saved to art_source/textures/<material>.png; existing files are loaded instead of repainted (hand-paint
them and re-run). REGENERATE_TEXTURE = True repaints them.

To export: set EXPORT = True and run again. It writes assets/models/props/<prop>.glb for every prop.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

EXPORT = False
EXPORT_DIR = "//../assets/models/props/"
TEXTURE_DIR = "//textures/"
REGENERATE_TEXTURE = False

PX_PER_M = 16

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


# ---------------------------------------------------------------- textures (16 px = 1 m, they tile)

def tex_concrete(rng, x, y):
    if x == 0 or y == 0:
        return "steel_light"  # 1 m block joints
    r = rng.random()
    return "steel_light" if r < 0.12 else "bone" if r < 0.17 else "sand" if r < 0.2 else "concrete"


def tex_stone(rng, x, y):  # darker plinth stone
    if y % 8 == 0 or (x + (8 if y // 8 % 2 else 0)) % 16 == 0:
        return "iron"
    r = rng.random()
    return "steel_light" if r < 0.15 else "steel"


def tex_soil(rng, x, y):
    r = rng.random()
    return "wood_mid" if r < 0.3 else "olive_dark" if r < 0.4 else "wood_dark"


def tex_leaves(rng, x, y):
    r = rng.random()
    return "olive_light" if r < 0.15 else "olive" if r < 0.35 else "green_dark" if r < 0.45 else "grass"


def tex_flowers(rng, x, y):
    r = rng.random()
    if r < 0.08:
        return "hazard_yellow"
    if r < 0.14:
        return "red"
    if r < 0.18:
        return "bone"
    return tex_leaves(rng, x, y)


def tex_wood(rng, x, y):
    if y % 4 == 0:
        return "wood_dark"  # plank gaps, 25 cm boards
    if (x + 5 * (y // 4)) % 16 == 0:
        return "wood_mid"  # board ends
    r = rng.random()
    return "wood_mid" if r < 0.12 else "wood_light" if r < 0.2 else "wood"


def tex_canopy(colour):
    def f(rng, x, y):
        c = colour if (x // 4) % 2 == 0 else "bone"
        return "sand" if rng.random() < 0.05 else c  # sun-faded, dusty
    return f


def tex_water(rng, x, y):
    r = rng.random()
    if r < 0.06:
        return "steel_light"
    if r < 0.14:
        return "olive"  # a summer of standing water
    return "sky_blue" if (x + y) % 7 else "iron"


def tex_bronze(rng, x, y):
    r = rng.random()
    return "olive_light" if r < 0.4 else "olive" if r < 0.7 else "steel" if r < 0.8 else "yellow_dark" if r < 0.9 else "sand"


def tex_plaque(rng, x, y):
    return "yellow_dark" if x in (0, 15) or y in (0, 15) else "olive_light" if rng.random() < 0.3 else "sand"


MATERIALS = {
    "mat_concrete": tex_concrete,
    "mat_stone": tex_stone,
    "mat_soil": tex_soil,
    "mat_leaves": tex_leaves,
    "mat_flowers": tex_flowers,
    "mat_wood": tex_wood,
    "mat_canopy_blue": tex_canopy("sky_blue"),
    "mat_canopy_red": tex_canopy("red"),
    "mat_water": tex_water,
    "mat_bronze": tex_bronze,
    "mat_plaque": tex_plaque,
}


def get_texture(name):
    path = bpy.path.abspath(TEXTURE_DIR + name + ".png")
    image = bpy.data.images.get(name)
    if image is not None:
        bpy.data.images.remove(image)
    if os.path.exists(path) and not REGENERATE_TEXTURE:
        image = bpy.data.images.load(TEXTURE_DIR + name + ".png")
        image.name = name
        return image
    rng = random.Random(sum(map(ord, name)))
    rows = [[rgba(MATERIALS[name](rng, x, y)) for x in range(16)] for y in range(16)]
    image = bpy.data.images.new(name, 16, 16, alpha=False)
    image.pixels = [c for row in rows for pixel in row for c in pixel]
    if bpy.data.filepath:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        image.filepath = TEXTURE_DIR + name + ".png"
    else:
        image.pack()
    return image


def get_material(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
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
    tex.image = get_texture(name)
    tex.interpolation = "Closest"
    tex.extension = "REPEAT"
    tex.location = (bsdf.location.x - 300, bsdf.location.y)
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.diffuse_color = tuple(tex.image.pixels[0:4])
    return mat


# ---------------------------------------------------------------- mesh building

class Part:
    """Collects boxes for one mesh object; each box gets a material, UVs are world meters (1 m = one tile)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.materials = []

    def mat(self, name):
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def box(self, lo, hi, material):
        index = self.mat(material)
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        for v in verts:
            v.co = Vector(tuple(lo[i] if v.co[i] < 0 else hi[i] for i in range(3)))
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = index
            face.normal_update()
            axis = max(range(3), key=lambda i: abs(face.normal[i]))
            for loop in face.loops:
                co = loop.vert.co
                a, b = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][axis]
                loop[self.uv].uv = (a, b)

    def cbox(self, cx, cy, z0, sx, sy, z1, material):
        """Box centered on (cx, cy) in X/Y, from z0 to z1."""
        self.box((cx - sx / 2, cy - sy / 2, z0), (cx + sx / 2, cy + sy / 2, z1), material)

    def finish(self, parent=None):
        remove_object(self.name)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for name in self.materials:
            mesh.materials.append(get_material(name))
        obj = bpy.data.objects.new(self.name, mesh)
        get_collection("Bloxov").objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


def get_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def remove_object(name):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        for child in list(obj.children):
            remove_object(child.name)
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


# ---------------------------------------------------------------- props

def make_planter():
    """3 x 1.0 x 2 m concrete planter (gray box: planter())."""
    p = Part("planter")
    w, d, h, t = 3.0, 2.0, 1.0, 0.15
    p.box((-w / 2, -d / 2, 0), (w / 2, -d / 2 + t, h), "mat_concrete")
    p.box((-w / 2, d / 2 - t, 0), (w / 2, d / 2, h), "mat_concrete")
    p.box((-w / 2, -d / 2 + t, 0), (-w / 2 + t, d / 2 - t, h), "mat_concrete")
    p.box((w / 2 - t, -d / 2 + t, 0), (w / 2, d / 2 - t, h), "mat_concrete")
    p.box((-w / 2 + t, -d / 2 + t, 0), (w / 2 - t, d / 2 - t, h - 0.12), "mat_soil")
    for cx in (-0.9, 0.0, 0.9):  # summer flowers (owner picked these over a bush)
        p.cbox(cx, 0, h - 0.15, 0.75, 1.5, h + 0.2, "mat_flowers")
    return p.finish()


def make_stall():
    """Market stall (gray box: stall()): 3.0 x 1.1 x 1.6 m counter, posts at the ends, 3.4 x 2.2 m canopy at 2.4 m."""
    p = Part("stall")
    p.cbox(0, 0, 0, 3.0, 1.6, 0.95, "mat_wood")             # counter body
    p.cbox(0, 0.05, 0.95, 3.1, 1.75, 1.1, "mat_wood")       # counter top, overhanging the front
    for x in (-1.5, 1.5):
        p.cbox(x, -0.6, 1.1, 0.12, 0.12, 2.4, "mat_wood")   # posts (gray box: at the ends)
        p.cbox(x, 0.6, 1.1, 0.12, 0.12, 2.4, "mat_wood")
    for cx, cy, s in ((-0.9, 0.1, 0.45), (-0.35, -0.2, 0.4), (0.8, 0.0, 0.5)):  # empty produce crates
        p.cbox(cx, cy, 1.1, s, s * 0.8, 1.1 + s * 0.6, "mat_wood")
    root = p.finish()
    for colour in ("blue", "red"):
        c = Part("Canopy__" + colour)
        c.cbox(0, 0, 2.4, 3.4, 2.2, 2.55, "mat_canopy_" + colour)
        c.cbox(0, 1.1 - 0.05, 2.15, 3.4, 0.1, 2.4, "mat_canopy_" + colour)  # front valance
        c.finish(root)
    return root


def make_fountain():
    """6 x 0.8 x 6 m basin with a 1.2 m column to 2.6 m (gray box: town square)."""
    p = Part("fountain")
    w, h, t = 6.0, 0.8, 0.45
    p.box((-w / 2, -w / 2, 0), (w / 2, -w / 2 + t, h), "mat_concrete")
    p.box((-w / 2, w / 2 - t, 0), (w / 2, w / 2, h), "mat_concrete")
    p.box((-w / 2, -w / 2 + t, 0), (-w / 2 + t, w / 2 - t, h), "mat_concrete")
    p.box((w / 2 - t, -w / 2 + t, 0), (w / 2, w / 2 - t, h), "mat_concrete")
    p.box((-w / 2 + t, -w / 2 + t, 0), (w / 2 - t, w / 2 - t, 0.5), "mat_water")
    p.cbox(0, 0, 0.5, 1.2, 1.2, 1.5, "mat_stone")     # column
    p.cbox(0, 0, 1.5, 1.8, 1.8, 1.75, "mat_concrete")  # upper bowl
    p.cbox(0, 0, 1.75, 1.4, 1.4, 1.8, "mat_water")
    p.cbox(0, 0, 1.75, 0.5, 0.5, 2.35, "mat_stone")
    p.cbox(0, 0, 2.35, 0.7, 0.7, 2.6, "mat_concrete")  # cap
    return p.finish()


def make_statue():
    """3 x 1.2 x 3 m plinth with a 1 x 2.8 x 1 m figure on it, top at 4.0 m (gray box: town square).
    A plain standing figure in a long coat, hands at its sides: nobody in particular (the lore is the owner's)."""
    p = Part("statue")
    p.cbox(0, 0, 0, 3.0, 3.0, 0.4, "mat_stone")
    p.cbox(0, 0, 0.4, 2.2, 2.2, 1.2, "mat_stone")
    p.box((-0.4, 1.1, 0.6), (0.4, 1.13, 1.0), "mat_plaque")   # blank plaque on the front
    z = 1.2
    p.cbox(0, 0, z, 0.9, 0.9, z + 0.12, "mat_bronze")          # base slab under the feet
    z += 0.12
    for x in (-0.17, 0.17):
        p.cbox(x, 0.05, z, 0.26, 0.4, z + 0.12, "mat_bronze")  # shoes
        p.cbox(x, 0, z, 0.24, 0.26, z + 0.95, "mat_bronze")    # legs
    p.cbox(0, 0, z + 0.7, 0.66, 0.4, z + 1.85, "mat_bronze")   # long coat and chest
    for x in (-0.42, 0.42):
        p.cbox(x, 0, z + 1.0, 0.18, 0.24, z + 1.8, "mat_bronze")  # arms at the sides
    p.cbox(0, 0, z + 1.85, 0.2, 0.2, z + 1.95, "mat_bronze")   # neck
    p.cbox(0, 0, z + 1.95, 0.4, 0.42, z + 2.4, "mat_bronze")   # head
    p.cbox(0, -0.02, z + 2.4, 0.44, 0.46, z + 2.48, "mat_bronze")  # hair
    return p.finish()


PROPS = {
    "planter": make_planter,
    "stall": make_stall,
    "fountain": make_fountain,
    "statue": make_statue,
}


def build_player_reference():
    remove_object("REF_Player")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.8, v.co.y * 0.8, (v.co.z + 0.5) * 1.8))
    mesh = bpy.data.meshes.new("REF_Player")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("REF_Player", mesh)
    obj.location = (-3.0, 2.0, 0)
    obj.display_type = "WIRE"
    obj.hide_render = True
    get_collection("Bloxov").objects.link(obj)


def tri_count(obj):
    objs = [obj] + [c for c in obj.children if c.type == "MESH"]
    return sum(len(p.vertices) - 2 for o in objs if o.type == "MESH" for p in o.data.polygons)


def main():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    build_player_reference()
    x = 0.0
    for name, make in PROPS.items():
        root = make()
        bpy.context.view_layer.update()
        print("Bloxov: built %s (%d tris incl. all options), front = +Y" % (name, tri_count(root)))
        if EXPORT:
            if not bpy.data.filepath:
                raise RuntimeError("Save the .blend into the repo's art_source/ folder first, then run again.")
            for obj in bpy.context.view_layer.objects:
                obj.select_set(False)
            for obj in [root] + list(root.children):
                obj.select_set(True)
            bpy.context.view_layer.objects.active = root
            path = bpy.path.abspath(EXPORT_DIR + name + ".glb")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                      export_yup=True, export_apply=True)
            print("Bloxov: exported", path)
        root.location.x = x  # side by side in the .blend (after export, so the .glb stays at the origin)
        x += 8.0


main()
