"""Bloxov characters: builds the Scav, PMC or Raider model, with outfit variants, to match docs/ART_SPEC.md.

How to use (Blender 4.x / 5.x):
  1. Set CHARACTER below ("scav", "pmc" or "raider") and save the .blend as art_source/<character>.blend first.
  2. Scripting tab > Text > Open > art_source/scripts/make_character.py, then Run (Alt+P).
Re-running rebuilds the character (it only touches objects in the "Bloxov" collection).

What you get (front faces +Y, feet on the ground at the origin, same sizes as the old box Scav):
  - "LegL" / "LegR": empties at the hips. The game swings them to walk, so pants and boots are their children.
  - "Gun" with a "Muzzle" empty at the barrel tip (where shots and the muzzle flash come from).
  - Outfit parts named "Slot__option" (or "Slot__option__L/R" for the two legs). Every option of every slot
    is in the file; the game shows ONE option per slot at random when a character spawns
    (scripts/pixel_model.gd). An empty named "Slot__none" means "nothing in this slot" is a choice.
    To add an option, add a builder line in SCAV/PMC below; the slot names are up to you.
  - One material ("<character>_mat") with one 128x128 pixel texture, 16 px/m, Bloxov palette only.
    Every block is box-projected in its own space, so 1 m = 16 texture pixels everywhere.

PREVIEW_SEED picks which random outfit the viewport shows (None shows every option piled on top of each other).
Texture: art_source/textures/<character>.png; if it exists it is loaded instead of repainted (hand-paint it and
re-run). Set REGENERATE_TEXTURE = True to repaint from scratch.
To export: set EXPORT = True and run. It writes assets/models/characters/<character>.glb with every option.
"""
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

CHARACTER = "scav"  # "scav", "pmc" or "raider"
EXPORT = False
REGENERATE_TEXTURE = False
PREVIEW_SEED = 1

PX_PER_M = 16
TILE = 16
ATLAS = 128  # 8 x 8 tiles of 16 px
COLS = ATLAS // TILE

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

# Skins: what a 16x16 tile looks like. base color, noise [(color, chance)], optional pattern:
#   knit (alternate rows), weave (canvas checker), camo (blobs of `blobs`), sole (bottom row in `sole`),
#   stripe (a `stripe` colored stripe on the side faces, like a tracksuit).
SKINS = {
    # people
    "skin_pale": {"base": "wood_pale", "noise": [("wood_light", 0.04)]},
    "skin_tan": {"base": "wood_light", "noise": [("wood", 0.05)]},
    "skin_dark": {"base": "wood_mid", "noise": [("wood_dark", 0.06)]},
    "hair_dark": {"base": "black", "noise": [("iron_dark", 0.3)]},
    "hair_brown": {"base": "wood_dark", "noise": [("wood_mid", 0.25)]},
    "eye": {"base": "black"},
    "black": {"base": "black", "noise": [("iron_dark", 0.2)]},
    # guns
    "gun_black": {"base": "iron_dark", "noise": [("black", 0.25), ("iron", 0.08)]},
    "gun_rail": {"base": "iron_dark", "noise": [("iron", 0.1)], "pattern": "rail"},
    "gun_wood": {"base": "wood", "noise": [("wood_mid", 0.3), ("wood_dark", 0.08)]},
    "mag_rust": {"base": "rust", "noise": [("wood_dark", 0.2)]},
    "mag_tan": {"base": "sand", "noise": [("yellow_dark", 0.1)]},
    "lens": {"base": "sky_blue", "noise": [("steel_light", 0.15)]},
    # scav clothes
    "knit_black": {"base": "black", "noise": [("iron_dark", 0.25)], "pattern": "knit", "knit": "iron_dark"},
    "knit_olive": {"base": "olive_dark", "noise": [("olive", 0.2)], "pattern": "knit", "knit": "olive"},
    "track_blue": {"base": "sky_blue", "noise": [("iron", 0.05)], "pattern": "stripe", "stripe": "bone"},
    "track_black": {"base": "iron_dark", "noise": [("black", 0.2)], "pattern": "stripe", "stripe": "bone"},
    "jacket_olive": {"base": "olive", "noise": [("olive_dark", 0.15), ("olive_light", 0.05)]},
    "woodland": {"base": "olive", "noise": [("olive_dark", 0.08)], "pattern": "camo",
                 "blobs": ["olive_dark", "wood_mid", "black"]},
    "hoodie_grey": {"base": "steel", "noise": [("iron", 0.15), ("steel_light", 0.05)]},
    "leather": {"base": "wood_mid", "noise": [("wood_dark", 0.2), ("wood", 0.08)]},
    "denim": {"base": "sky_blue", "noise": [("iron", 0.12), ("steel", 0.04)]},
    "cargo_olive": {"base": "olive_light", "noise": [("olive", 0.2)]},
    "canvas_sand": {"base": "sand", "noise": [("wood_light", 0.06)], "pattern": "weave", "weave": "yellow_dark"},
    "canvas_olive": {"base": "olive_dark", "noise": [("olive", 0.1)], "pattern": "weave", "weave": "olive"},
    "sneaker_white": {"base": "bone", "noise": [("concrete", 0.2)], "pattern": "sole", "sole": "iron_dark"},
    "sneaker_dark": {"base": "iron_dark", "noise": [("iron", 0.15)], "pattern": "sole", "sole": "bone"},
    "boot_brown": {"base": "wood_dark", "noise": [("wood_mid", 0.2)], "pattern": "sole", "sole": "black"},
    "boot_black": {"base": "black", "noise": [("iron_dark", 0.2)], "pattern": "sole", "sole": "iron_dark"},
    "fur": {"base": "wood_mid", "noise": [("wood_dark", 0.3), ("wood", 0.15)], "pattern": "knit", "knit": "wood_dark"},
    "cap_sand": {"base": "sand", "noise": [("wood_light", 0.1)]},
    "cap_red": {"base": "red", "noise": [("rust", 0.2)]},
    "helmet_old": {"base": "olive", "noise": [("olive_dark", 0.15), ("rust", 0.05)]},
    "glove_brown": {"base": "wood_mid", "noise": [("wood_dark", 0.2)]},
    "glove_olive": {"base": "olive_dark", "noise": [("olive", 0.15)]},
    # pmc clothes and gear
    "shirt_green": {"base": "olive_dark", "noise": [("olive", 0.1)]},
    "shirt_black": {"base": "iron_dark", "noise": [("black", 0.15)]},
    "shirt_tan": {"base": "sand", "noise": [("olive_light", 0.06)]},
    "multicam": {"base": "sand", "noise": [("wood_light", 0.06)], "pattern": "camo",
                 "blobs": ["wood_light", "olive", "wood_mid"]},
    "carrier_tan": {"base": "sand", "noise": [("olive_light", 0.06)], "pattern": "weave", "weave": "olive_light"},
    "carrier_green": {"base": "grass", "noise": [("olive_dark", 0.12)], "pattern": "weave", "weave": "olive_dark"},
    "carrier_black": {"base": "iron_dark", "noise": [("black", 0.15)], "pattern": "weave", "weave": "black"},
    "helmet_tan": {"base": "sand", "noise": [("olive_light", 0.06)]},
    "helmet_green": {"base": "grass", "noise": [("olive_dark", 0.12)]},
    "helmet_black": {"base": "iron_dark", "noise": [("black", 0.15), ("iron", 0.05)]},
    "boot_tan": {"base": "sand", "noise": [("olive_light", 0.1)], "pattern": "sole", "sole": "iron_dark"},
    "boot_coyote": {"base": "wood_light", "noise": [("wood", 0.15)], "pattern": "sole", "sole": "black"},
    "glove_tan": {"base": "sand", "noise": [("olive_light", 0.08)]},
    "gaiter_tan": {"base": "sand", "noise": [("olive_light", 0.1)], "pattern": "knit", "knit": "olive_light"},
    "gaiter_black": {"base": "black", "noise": [("iron_dark", 0.2)], "pattern": "knit", "knit": "iron_dark"},
    "gaiter_green": {"base": "olive_dark", "noise": [("olive", 0.15)], "pattern": "knit", "knit": "olive"},
    # raider clothes and gear (dark, with rust-red faction accents)
    "raider_black": {"base": "iron_dark", "noise": [("black", 0.2), ("iron", 0.04)]},
    "urban": {"base": "iron", "noise": [("iron_dark", 0.08)], "pattern": "camo",
              "blobs": ["black", "steel", "iron_dark"]},
    "rust_jacket": {"base": "rust", "noise": [("wood_dark", 0.15), ("red", 0.04)]},
    "armband": {"base": "red", "noise": [("rust", 0.2)]},
    "knit_rust": {"base": "rust", "noise": [("wood_dark", 0.2)], "pattern": "knit", "knit": "wood_dark"},
    "skull_bone": {"base": "bone", "noise": [("concrete", 0.2)]},
    "rubber": {"base": "black", "noise": [("iron_dark", 0.3)]},
    "visor": {"base": "steel", "noise": [("steel_light", 0.12), ("iron", 0.1)]},
    "helmet_heavy": {"base": "olive_dark", "noise": [("iron_dark", 0.15), ("rust", 0.04)]},
    "helmet_heavy_black": {"base": "iron_dark", "noise": [("black", 0.15), ("rust", 0.04)]},
    "heavy_black": {"base": "iron_dark", "noise": [("black", 0.15)], "pattern": "weave", "weave": "black"},
    "heavy_olive": {"base": "olive_dark", "noise": [("olive", 0.1)], "pattern": "weave", "weave": "black"},
    "canvas_black": {"base": "black", "noise": [("iron_dark", 0.2)], "pattern": "weave", "weave": "iron_dark"},
}

# ---------------------------------------------------------------- body layout (meters, Blender axes)
HIP_Z, LEG_X = 0.6, 0.19
GUN_X = 0.1
GRIP = Vector((GUN_X, 0.43, 1.12))  # right hand / gun origin
SUPPORT = Vector((GUN_X, 0.72, 1.14))  # left hand under the handguard
MUZZLE = Vector((GUN_X, 1.0, 1.26))


def rgba(name):
    h = PALETTE[name]
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


# ---------------------------------------------------------------- texture atlas

class Atlas:
    """Hands out 16x16 tiles for skins as they get used, then paints them."""

    def __init__(self):
        self.tiles = {}  # (skin, variant) -> index

    def uv_origin(self, skin, variant=""):
        if variant and SKINS[skin].get("pattern") != "stripe":
            variant = ""
        key = (skin, variant)
        if key not in self.tiles:
            if len(self.tiles) >= COLS * COLS:
                raise RuntimeError("Texture atlas is full (%d tiles)" % (COLS * COLS))
            self.tiles[key] = len(self.tiles)
        i = self.tiles[key]
        return (i % COLS) * TILE, (i // COLS) * TILE

    def paint(self):
        rng = random.Random(7)
        px = [[rgba("black")] * ATLAS for _ in range(ATLAS)]
        for (skin, variant), i in sorted(self.tiles.items(), key=lambda kv: kv[1]):
            ox, oy = (i % COLS) * TILE, (i // COLS) * TILE
            spec = SKINS[skin]
            pattern = spec.get("pattern")
            for y in range(TILE):
                for x in range(TILE):
                    color = spec["base"]
                    r = rng.random()
                    for noise_color, chance in spec.get("noise", []):
                        if r < chance:
                            color = noise_color
                            break
                        r -= chance
                    if pattern == "knit" and y % 2 and rng.random() < 0.4:
                        color = spec["knit"]
                    elif pattern == "weave" and (x + y) % 2 and rng.random() < 0.25:
                        color = spec["weave"]
                    elif pattern == "rail" and x % 2 == 0:
                        color = "black"
                    elif pattern == "sole" and y == 0:
                        color = spec["sole"]
                    elif pattern == "stripe" and variant == "side" and x in (1, 2):
                        color = spec["stripe"]
                    px[oy + y][ox + x] = rgba(color)
            if pattern == "camo":
                for blob in spec["blobs"]:
                    for _ in range(7):
                        bx, by = rng.randrange(TILE), rng.randrange(TILE)
                        for dy in range(rng.choice((1, 2))):
                            for dx in range(rng.choice((2, 3))):
                                px[oy + (by + dy) % TILE][ox + (bx + dx) % TILE] = rgba(blob)
        return [c for row in px for p in row for c in p]


# ---------------------------------------------------------------- mesh building

class Part:
    """Blocks that become one object. Coordinates are world space; finish() moves the origin."""

    def __init__(self, atlas):
        self.atlas = atlas
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _block(self, size, matrix, skin, sides=True):
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        for v in verts:  # local block: x and z centered, y from 0 to length
            v.co = Vector((v.co.x * size[0], (v.co.y + 0.5) * size[1], v.co.z * size[2]))
        for face in {f for v in verts for f in v.link_faces}:
            face.normal_update()
            axis = max(range(3), key=lambda i: abs(face.normal[i]))
            ox, oy = self.atlas.uv_origin(skin, "side" if axis == 0 and sides else "")
            for loop in face.loops:
                co = loop.vert.co + Vector((size[0] / 2, 0, size[2] / 2))
                a, b = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[axis]
                u = ox + min(max(a * PX_PER_M, 0.0), TILE)
                w = oy + min(max(b * PX_PER_M, 0.0), TILE)
                loop[self.uv].uv = (u / ATLAS, w / ATLAS)
        for v in verts:
            v.co = matrix @ v.co

    def box(self, a, b, skin):
        """Axis-aligned block between corners a and b (any order)."""
        lo = Vector([min(a[i], b[i]) for i in range(3)])
        hi = Vector([max(a[i], b[i]) for i in range(3)])
        size = hi - lo
        self._block(size, Matrix.Translation(Vector((lo.x + size.x / 2, lo.y, lo.z + size.z / 2))), skin)
        return self

    def beam(self, start, end, w, h, skin):
        """Block of width w and height h running from start to end (forearms, curved mags)."""
        start, end = Vector(start), Vector(end)
        d = end - start
        rot = d.normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()
        self._block((w, d.length, h), Matrix.Translation(start) @ rot, skin, sides=False)
        return self


class Builder:
    def __init__(self, coll, material, atlas):
        self.coll, self.material, self.atlas = coll, material, atlas

    def part(self):
        return Part(self.atlas)

    def finish(self, part, name, origin=(0, 0, 0), parent=None):
        origin = Vector(origin)
        for v in part.bm.verts:
            v.co -= origin
        mesh = bpy.data.meshes.new(name)
        part.bm.to_mesh(mesh)
        part.bm.free()
        mesh.materials.append(self.material)
        obj = bpy.data.objects.new(name, mesh)
        self._place(obj, origin, parent)
        return obj

    def empty(self, name, origin=(0, 0, 0), parent=None):
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = 0.08
        self._place(obj, Vector(origin), parent)
        return obj

    def _place(self, obj, origin, parent):
        self.coll.objects.link(obj)
        if parent is not None:
            obj.parent = parent
            obj.location = origin - parent.matrix_world.translation
        else:
            obj.location = origin
        bpy.context.view_layer.update()


# ---------------------------------------------------------------- body parts shared by both characters

def legs(b, pants, boots):
    """pants / boots: {option: (skin, extras)}. extras: 'pads' (knee pads), 'pockets' (cargo)."""
    for side, sx in (("L", -1), ("R", 1)):
        hip = Vector((sx * LEG_X, 0, HIP_Z))
        leg = b.empty("Leg" + side, hip)
        cx = sx * LEG_X
        for option, (skin, extras) in pants.items():
            p = b.part().box((cx - 0.15, -0.17, 0.12), (cx + 0.15, 0.17, 0.62), skin)
            if "pads" in extras:
                p.box((cx - 0.12, 0.17, 0.24), (cx + 0.12, 0.215, 0.37), "black")
            if "pockets" in extras:
                ox = cx + sx * 0.15
                p.box((ox, -0.08, 0.28), (ox + sx * 0.03, 0.08, 0.42), skin)
            b.finish(p, "Pants__%s__%s" % (option, side), hip, leg)
        for option, skin in boots.items():
            p = b.part().box((cx - 0.16, -0.18, 0.0), (cx + 0.16, 0.22, 0.14), skin)
            b.finish(p, "Boots__%s__%s" % (option, side), hip, leg)


def tops(b, options):
    """options: {option: (skin, extras)}. extras: 'hood', 'collar', 'armband' (red band on the left arm)."""
    for option, (skin, extras) in options.items():
        p = b.part()
        p.box((-0.38, -0.22, 0.58), (0.38, 0.22, 1.36), skin)
        p.box((-0.22, -0.2, 1.36), (0.22, 0.16, 1.42), skin)  # neck / collar
        for sx in (-1, 1):
            p.box((sx * 0.38, -0.09, 1.0), (sx * 0.56, 0.09, 1.36), skin)  # upper arms
        p.beam((-0.46, 0.04, 1.06), SUPPORT + Vector((-0.03, -0.04, -0.04)), 0.13, 0.13, skin)  # forearms
        p.beam((0.46, 0.04, 1.04), GRIP + Vector((0.03, -0.04, -0.04)), 0.13, 0.13, skin)
        if "hood" in extras:
            p.box((-0.25, -0.31, 1.3), (0.25, -0.2, 1.52), skin)
        if "collar" in extras:
            p.box((-0.27, -0.22, 1.36), (0.27, 0.12, 1.48), skin)
        if "armband" in extras:
            p.box((-0.575, -0.105, 1.17), (-0.365, 0.105, 1.25), "armband")
        b.finish(p, "Top__" + option)


def gloves(b, options):
    for option, skin in options.items():
        p = b.part()
        for c in (GRIP + Vector((0, 0.01, 0)), SUPPORT):
            p.box(c - Vector((0.07, 0.07, 0.07)), c + Vector((0.07, 0.07, 0.07)), skin)
        b.finish(p, "Gloves__" + option)


def heads(b, options):
    """options: {option: (skin, hair, extras)}. extras: 'beard', 'balaclava' (skin = knit, hair = eye band skin),
    'skull' (painted skull mask, hair = mask skin), 'gasmask' (hair = filter canister skin)."""
    for option, (skin, hair, extras) in options.items():
        p = b.part().box((-0.26, -0.26, 1.40), (0.26, 0.26, 1.92), skin)
        if "skull" in extras:
            p.box((-0.22, 0.26, 1.44), (0.22, 0.28, 1.86), hair)
            for sx in (-1, 1):
                p.box((sx * 0.17, 0.28, 1.65), (sx * 0.05, 0.29, 1.76), "eye")  # eye sockets
            p.box((-0.025, 0.28, 1.58), (0.025, 0.29, 1.63), "eye")  # nose
            p.box((-0.14, 0.28, 1.5), (0.14, 0.29, 1.52), "eye")  # teeth
            for tx in (-0.09, -0.03, 0.03, 0.09):
                p.box((tx - 0.008, 0.28, 1.46), (tx + 0.008, 0.29, 1.56), "eye")
            b.finish(p, "Head__" + option)
            continue
        if "gasmask" in extras:
            p.box((-0.21, 0.26, 1.44), (0.21, 0.3, 1.82), "rubber")
            for sx in (-1, 1):
                p.box((sx * 0.17, 0.3, 1.65), (sx * 0.05, 0.312, 1.77), "lens")
            p.box((-0.07, 0.3, 1.44), (0.07, 0.42, 1.57), hair)  # filter canister
            b.finish(p, "Head__" + option)
            continue
        if "balaclava" in extras:
            p.box((-0.19, 0.26, 1.64), (0.19, 0.272, 1.75), hair)  # eye opening
            front = 0.272
        else:
            p.box((-0.03, 0.26, 1.58), (0.03, 0.29, 1.66), skin)  # nose
            for sx in (-1, 1):
                p.box((sx * 0.16, 0.26, 1.74), (sx * 0.07, 0.272, 1.77), hair)  # brows
            p.box((-0.27, -0.27, 1.86), (0.27, 0.24, 1.95), hair)  # hair
            p.box((-0.27, -0.28, 1.6), (0.27, -0.25, 1.95), hair)
            if "beard" in extras:
                p.box((-0.21, 0.26, 1.42), (0.21, 0.275, 1.56), hair)
            front = 0.26
        for sx in (-1, 1):
            p.box((sx * 0.15, front, 1.66), (sx * 0.08, front + 0.012, 1.72), "eye")
        b.finish(p, "Head__" + option)


def headset(p):
    for sx in (-1, 1):
        p.box((sx * 0.26, -0.08, 1.6), (sx * 0.33, 0.08, 1.78), "black")


def gun(b, kind):
    p = b.part()
    x0, x1 = GUN_X - 0.04, GUN_X + 0.04
    if kind == "ak":
        p.box((x0, 0.28, 1.18), (x1, 0.62, 1.30), "gun_black")  # receiver
        p.box((x0 - 0.01, 0.62, 1.18), (x1 + 0.01, 0.82, 1.29), "gun_wood")  # handguard
        p.box((GUN_X - 0.02, 0.82, 1.24), (GUN_X + 0.02, 1.0, 1.28), "gun_black")  # barrel
        p.box((GUN_X - 0.015, 0.94, 1.28), (GUN_X + 0.015, 0.97, 1.32), "gun_black")  # front sight
        p.box((x0 + 0.005, 0.14, 1.12), (x1 - 0.005, 0.30, 1.26), "gun_wood")  # stock
        p.box((GUN_X - 0.025, 0.40, 1.04), (GUN_X + 0.025, 0.46, 1.18), "gun_wood")  # grip
        p.beam((GUN_X, 0.55, 1.19), (GUN_X, 0.62, 0.99), 0.06, 0.08, "mag_rust")  # curved mag
    elif kind == "rpk":
        p.box((x0, 0.28, 1.18), (x1, 0.62, 1.30), "gun_black")  # receiver
        p.box((x0 - 0.01, 0.62, 1.18), (x1 + 0.01, 0.80, 1.29), "gun_black")  # polymer handguard
        p.box((GUN_X - 0.02, 0.80, 1.24), (GUN_X + 0.02, 1.0, 1.28), "gun_black")  # long barrel
        p.box((GUN_X - 0.015, 0.94, 1.28), (GUN_X + 0.015, 0.97, 1.32), "gun_black")  # front sight
        p.box((GUN_X - 0.03, 0.82, 1.19), (GUN_X + 0.03, 0.98, 1.22), "gun_black")  # folded bipod
        p.box((x0 + 0.005, 0.12, 1.12), (x1 - 0.005, 0.30, 1.26), "gun_black")  # stock
        p.box((GUN_X - 0.025, 0.40, 1.04), (GUN_X + 0.025, 0.46, 1.18), "gun_black")  # grip
        p.box((GUN_X - 0.07, 0.48, 0.96), (GUN_X + 0.07, 0.66, 1.18), "gun_black")  # drum mag
        p.box((GUN_X - 0.075, 0.53, 1.02), (GUN_X + 0.075, 0.61, 1.12), "mag_rust")  # drum face
    else:  # m4
        p.box((x0 + 0.005, 0.30, 1.18), (x1 - 0.005, 0.58, 1.30), "gun_black")  # receiver
        p.box((x0, 0.58, 1.19), (x1, 0.86, 1.29), "gun_rail")  # railed handguard
        p.box((GUN_X - 0.02, 0.86, 1.22), (GUN_X + 0.02, 1.0, 1.26), "gun_black")  # barrel
        p.box((GUN_X - 0.03, 0.12, 1.14), (GUN_X + 0.03, 0.30, 1.26), "gun_black")  # stock
        p.box((GUN_X - 0.025, 0.40, 1.04), (GUN_X + 0.025, 0.46, 1.18), "gun_black")  # grip
        p.box((GUN_X - 0.03, 0.40, 1.30), (GUN_X + 0.03, 0.54, 1.38), "gun_black")  # optic
        p.box((GUN_X - 0.02, 0.54, 1.32), (GUN_X + 0.02, 0.545, 1.36), "lens")
        p.beam((GUN_X, 0.50, 1.19), (GUN_X, 0.53, 1.00), 0.05, 0.08, "mag_tan")  # straight mag
    obj = b.finish(p, "Gun", GRIP)
    b.empty("Muzzle", MUZZLE, obj)


# ---------------------------------------------------------------- the two characters

def build_scav(b):
    legs(b, {
        "track_black": ("track_black", ()),
        "track_blue": ("track_blue", ()),
        "jeans": ("denim", ()),
        "cargo_olive": ("cargo_olive", ("pockets",)),
        "woodland": ("woodland", ("pockets",)),
    }, {
        "sneaker_white": "sneaker_white",
        "sneaker_dark": "sneaker_dark",
        "boot_brown": "boot_brown",
        "boot_black": "boot_black",
    })
    tops(b, {
        "tracksuit_blue": ("track_blue", ()),
        "tracksuit_black": ("track_black", ()),
        "jacket_olive": ("jacket_olive", ("collar",)),
        "woodland": ("woodland", ("collar",)),
        "hoodie_grey": ("hoodie_grey", ("hood",)),
        "leather": ("leather", ("collar",)),
    })
    gloves(b, {"black": "black", "brown": "glove_brown", "olive": "glove_olive"})
    heads(b, {
        "balaclava_black": ("knit_black", "skin_pale", ("balaclava",)),
        "balaclava_olive": ("knit_olive", "skin_tan", ("balaclava",)),
        "pale": ("skin_pale", "hair_dark", ()),
        "tan_beard": ("skin_tan", "hair_brown", ("beard",)),
        "dark": ("skin_dark", "hair_dark", ()),
        "pale_beard": ("skin_pale", "hair_brown", ("beard",)),
    })
    for option, skin in (("beanie_black", "knit_black"), ("beanie_olive", "knit_olive")):
        p = b.part().box((-0.29, -0.29, 1.80), (0.29, 0.29, 2.02), skin)
        p.box((-0.30, -0.30, 1.80), (0.30, 0.30, 1.87), skin)
        b.finish(p, "Hat__" + option)
    for option, skin in (("cap_sand", "cap_sand"), ("cap_red", "cap_red")):
        p = b.part().box((-0.275, -0.28, 1.84), (0.275, 0.25, 1.99), skin)
        p.box((-0.2, 0.25, 1.84), (0.2, 0.4, 1.87), skin)
        b.finish(p, "Hat__" + option)
    p = b.part().box((-0.29, -0.29, 1.85), (0.29, 0.29, 2.04), "fur")
    p.box((-0.3, 0.25, 1.86), (0.3, 0.31, 1.98), "fur")
    for sx in (-1, 1):
        p.box((sx * 0.26, -0.14, 1.62), (sx * 0.32, 0.14, 1.88), "fur")
    b.finish(p, "Hat__ushanka")
    p = b.part().box((-0.3, -0.3, 1.83), (0.3, 0.3, 2.04), "helmet_old")
    p.box((-0.34, -0.34, 1.82), (0.34, 0.34, 1.86), "helmet_old")
    b.finish(p, "Hat__helmet_old")
    b.empty("Hat__none")
    for option, skin in (("rig_sand", "canvas_sand"), ("rig_olive", "canvas_olive")):
        p = b.part().box((-0.32, 0.22, 0.92), (0.32, 0.27, 1.18), skin)
        for cx in (-0.2, 0.0, 0.2):
            p.box((cx - 0.08, 0.27, 0.94), (cx + 0.08, 0.33, 1.14), skin)
        for sx in (-1, 1):
            x0, x1 = sx * 0.135, sx * 0.225
            p.box((x0, 0.22, 1.18), (x1, 0.25, 1.39), skin)
            p.box((x0, -0.23, 1.36), (x1, 0.25, 1.39), skin)
            p.box((x0, -0.25, 0.92), (x1, -0.22, 1.39), skin)
        b.finish(p, "Vest__" + option)
    b.empty("Vest__none")
    gun(b, "ak")


def build_pmc(b):
    pads = ("pads",)
    legs(b, {
        "green": ("shirt_green", pads),
        "black": ("shirt_black", pads),
        "tan": ("shirt_tan", pads),
        "multicam": ("multicam", pads + ("pockets",)),
    }, {"tan": "boot_tan", "coyote": "boot_coyote", "black": "boot_black"})
    tops(b, {
        "green": ("shirt_green", ()),
        "black": ("shirt_black", ()),
        "tan": ("shirt_tan", ()),
        "multicam": ("multicam", ()),
    })
    gloves(b, {"black": "black", "tan": "glove_tan", "green": "glove_olive"})
    heads(b, {
        "pale": ("skin_pale", "hair_dark", ()),
        "tan": ("skin_tan", "hair_brown", ()),
        "dark": ("skin_dark", "hair_dark", ()),
        "pale_beard": ("skin_pale", "hair_brown", ("beard",)),
        "dark_beard": ("skin_dark", "hair_dark", ("beard",)),
    })
    for option, skin in (("gaiter_tan", "gaiter_tan"), ("gaiter_black", "gaiter_black"), ("gaiter_green", "gaiter_green")):
        b.finish(b.part().box((-0.275, -0.275, 1.40), (0.275, 0.30, 1.62), skin), "Mask__" + option)
    b.empty("Mask__none")
    p = b.part().box((-0.2, 0.262, 1.65), (0.2, 0.29, 1.74), "black")
    b.finish(p, "Eyes__glasses")
    b.empty("Eyes__none")
    for option, skin in (("helmet_tan", "helmet_tan"), ("helmet_green", "helmet_green"), ("helmet_black", "helmet_black")):
        p = b.part().box((-0.3, -0.31, 1.82), (0.3, 0.29, 2.03), skin)
        p.box((-0.05, 0.29, 1.9), (0.05, 0.32, 1.98), "black")  # NVG mount
        for sx in (-1, 1):
            p.box((sx * 0.3, -0.12, 1.86), (sx * 0.315, 0.12, 1.92), "black")  # rails
        headset(p)
        b.finish(p, "Hat__" + option)
    p = b.part().box((-0.275, -0.28, 1.84), (0.275, 0.25, 1.99), "black")
    p.box((-0.2, 0.25, 1.84), (0.2, 0.4, 1.87), "black")
    p.box((-0.3, -0.04, 1.78), (0.3, 0.04, 2.0), "black")  # headband over the cap
    headset(p)
    b.finish(p, "Hat__cap_headset")
    for option, skin in (("tan", "carrier_tan"), ("green", "carrier_green"), ("black", "carrier_black")):
        p = b.part().box((-0.35, -0.27, 0.86), (0.35, 0.27, 1.34), skin)
        for sx in (-1, 1):
            p.box((sx * 0.12, -0.27, 1.33), (sx * 0.24, 0.27, 1.39), skin)  # shoulder straps
        for cx in (-0.18, 0.0, 0.18):
            p.box((cx - 0.07, 0.27, 0.88), (cx + 0.07, 0.33, 1.06), skin)  # mag pouches
        p.box((-0.12, 0.27, 1.08), (0.12, 0.31, 1.24), skin)  # admin pouch
        p.box((-0.2, -0.32, 0.9), (0.2, -0.27, 1.26), skin)  # back pouch
        p.box((-0.39, -0.23, 0.58), (0.39, 0.23, 0.68), skin)  # battle belt
        b.finish(p, "Vest__" + option)
    gun(b, "m4")


def build_raider(b):
    """Raiders: the tougher AI faction. Dark gear, heavy armor, rust-red armband, masks; reads as neither scav nor PMC."""
    pads = ("pads",)
    legs(b, {
        "black": ("raider_black", pads),
        "urban": ("urban", pads + ("pockets",)),
        "olive": ("shirt_green", pads),
    }, {"black": "boot_black", "brown": "boot_brown"})
    band = ("armband",)
    tops(b, {
        "black": ("raider_black", band + ("collar",)),
        "urban": ("urban", band),
        "rust": ("rust_jacket", band + ("collar",)),
        "hoodie_black": ("raider_black", band + ("hood",)),
    })
    gloves(b, {"black": "black", "brown": "glove_brown"})
    heads(b, {
        "skull": ("knit_black", "skull_bone", ("skull",)),
        "gasmask": ("knit_black", "helmet_heavy", ("gasmask",)),
        "balaclava_black": ("knit_black", "skin_pale", ("balaclava",)),
        "balaclava_rust": ("knit_rust", "skin_tan", ("balaclava",)),
    })
    for option, skin in (("altyn", "helmet_heavy"), ("altyn_black", "helmet_heavy_black")):
        p = b.part().box((-0.31, -0.31, 1.82), (0.31, 0.31, 2.05), skin)  # heavy dome
        p.box((-0.32, -0.32, 1.6), (0.32, 0.2, 1.84), skin)  # sides and back, down past the ears
        p.box((-0.26, 0.3, 1.6), (0.26, 0.34, 1.84), "visor")  # armored visor
        p.box((-0.2, 0.34, 1.7), (0.2, 0.345, 1.74), "eye")  # vision slit
        b.finish(p, "Hat__" + option)
    b.finish(b.part().box((-0.3, -0.32, 1.5), (0.3, 0.24, 2.0), "raider_black"), "Hat__hood")
    p = b.part().box((-0.275, -0.28, 1.84), (0.275, 0.27, 1.97), "armband")
    p.box((-0.06, -0.32, 1.82), (0.06, -0.28, 1.9), "armband")  # knot
    b.finish(p, "Hat__bandana")
    b.empty("Hat__none")
    for option, skin in (("heavy_black", "heavy_black"), ("heavy_olive", "heavy_olive")):
        p = b.part().box((-0.36, -0.28, 0.84), (0.36, 0.28, 1.36), skin)
        for sx in (-1, 1):
            p.box((sx * 0.355, -0.12, 1.22), (sx * 0.6, 0.12, 1.4), skin)  # shoulder armor
        p.box((-0.3, -0.27, 1.34), (0.3, 0.18, 1.44), skin)  # neck guard
        for cx in (-0.2, 0.0, 0.2):
            p.box((cx - 0.08, 0.28, 0.86), (cx + 0.08, 0.35, 1.06), skin)  # mag pouches
        p.box((-0.16, 0.22, 0.5), (0.16, 0.27, 0.72), skin)  # groin flap
        p.box((-0.39, -0.23, 0.58), (0.39, 0.23, 0.68), skin)  # belt
        b.finish(p, "Vest__" + option)
    p = b.part().box((-0.32, 0.22, 0.92), (0.32, 0.27, 1.18), "canvas_black")
    for cx in (-0.2, 0.0, 0.2):
        p.box((cx - 0.08, 0.27, 0.94), (cx + 0.08, 0.34, 1.14), "canvas_black")
    for sx in (-1, 1):
        x0, x1 = sx * 0.135, sx * 0.225
        p.box((x0, 0.22, 1.18), (x1, 0.25, 1.39), "canvas_black")
        p.box((x0, -0.23, 1.36), (x1, 0.25, 1.39), "canvas_black")
        p.box((x0, -0.25, 0.92), (x1, -0.22, 1.39), "canvas_black")
    b.finish(p, "Vest__rig_black")
    gun(b, "rpk")


# ---------------------------------------------------------------- setup, preview, export

def get_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def clear(coll):
    for obj in list(coll.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def make_material(name, image):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
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


def get_texture(atlas_painter):
    """Loads the saved texture, or paints it (atlas_painter is called after the mesh assigned its tiles)."""
    rel = "//textures/%s.png" % CHARACTER
    path = bpy.path.abspath(rel)
    image = bpy.data.images.get(CHARACTER)
    if image is None:
        image = bpy.data.images.new(CHARACTER, ATLAS, ATLAS, alpha=False)
    if os.path.exists(path) and not REGENERATE_TEXTURE:
        image.filepath = rel
        image.source = "FILE"
        image.reload()
        return image, None
    return image, lambda: _paint_image(image, atlas_painter, rel, path)


def _paint_image(image, atlas_painter, rel, path):
    image.source = "GENERATED"
    image.generated_width = image.generated_height = ATLAS
    image.pixels = atlas_painter()
    if bpy.data.filepath:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        image.filepath = rel  # keep it relative so the .blend works from any clone
    else:
        image.pack()


def outfit_slots(coll):
    """{slot: {option: [objects]}} for every object named Slot__option[__side]."""
    slots = {}
    for obj in coll.objects:
        parts = obj.name.split("__")
        if len(parts) >= 2:
            slots.setdefault(parts[0], {}).setdefault(parts[1], []).append(obj)
    return slots


def show_outfit(coll, seed):
    rng = random.Random(seed)
    for slot, options in sorted(outfit_slots(coll).items()):
        pick = rng.choice(sorted(options)) if seed is not None else None
        for option, objs in options.items():
            for obj in objs:
                hidden = pick is not None and option != pick
                obj.hide_set(hidden)
                obj.hide_render = hidden


def main():
    builders = {"scav": build_scav, "pmc": build_pmc, "raider": build_raider}
    if CHARACTER not in builders:
        raise ValueError("CHARACTER must be one of %s" % ", ".join(builders))
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    coll = get_collection("Bloxov")
    clear(coll)

    atlas = Atlas()
    image, paint = get_texture(atlas.paint)
    b = Builder(coll, make_material(CHARACTER + "_mat", image), atlas)
    builders[CHARACTER](b)
    if paint is not None:
        paint()

    slots = outfit_slots(coll)
    combos = 1
    for options in slots.values():
        combos *= len(options)
    print("Bloxov: built %s, %d outfit slots, %d combinations, %d texture tiles"
          % (CHARACTER, len(slots), combos, len(atlas.tiles)))

    if EXPORT:
        if not bpy.data.filepath:
            raise RuntimeError("Save the .blend into the repo's art_source/ folder first, then run again.")
        show_outfit(coll, None)  # everything visible and selectable
        for obj in bpy.context.view_layer.objects:
            obj.select_set(obj.name in coll.objects)
        path = bpy.path.abspath("//../assets/models/characters/%s.glb" % CHARACTER)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
        )
        print("Bloxov: exported", path)
    show_outfit(coll, PREVIEW_SEED)


main()
