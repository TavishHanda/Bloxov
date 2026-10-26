"""Bloxov jointed characters (0.23): the Scav, PMC and Raider on joints, so they can kneel, lie prone and crawl
instead of squashing or tipping over stiff. Same outfit slots and skins as make_character.py, new body (look C,
owner 2026-10-26: "make it the same as before for now": the old models' sizes, ~2.05 m, just with joints).

Run: python3 art_source/scripts/make_body.py [scav|pmc|raider ...]   (all three without arguments)
No Blender needed (the .glb is written directly). Texture: one 128 px atlas per character, 16 px per meter,
art_source/textures/<character>_body.png (painted the first time, loaded after that; delete it to repaint).

Built in Blender axes (front +y, up +z, feet at the origin) and written as glTF (front -z, up +y).
Joints (empty nodes; the game turns them, scripts/body_pose.gd):
  Hips                 the pelvis, at the hip joints' height
    Spine              the chest, bends at the waist
      Neck             the head turns and nods here
      ArmL, ArmR       shoulders; the arm hangs down -y in its own frame
        ElbowL, ElbowR forearm and hand (glove)
    LegL, LegR         hip joints; the leg hangs down
      KneeL, KneeR     shin and boot
Outfit parts are named "Slot__option__Joint" and hang off that joint (scripts/pixel_model.gd shows one option per
slot). An empty "Slot__none" makes "nothing" a choice.
"""
import json
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402

ROOT = mb.ROOT
PX_PER_M = 16
TILE = 16
ATLAS = 128
COLS = ATLAS // TILE

PALETTE = {
    "black": "1b1c1f", "iron_dark": "2f3236", "iron": "4b5057", "steel": "6f767d", "steel_light": "9aa1a6",
    "concrete": "b8b4aa", "bone": "e2dccb", "wood_dark": "4a2f1b", "wood_mid": "6e4628", "wood": "8f5e34",
    "wood_light": "b07a45", "wood_pale": "c99a5e", "rust": "8a3f1f", "red": "b03a2e", "hazard_yellow": "e8b923",
    "yellow_dark": "a8801a", "sand": "a89a6a", "olive_dark": "3d4228", "olive": "5b6236", "olive_light": "7d8450",
    "grass": "556b2f", "green_dark": "2e7d32", "extract_green": "4fd44a", "sky_blue": "3e6d8c",
}

# The skins of make_character.py (what a 16x16 tile looks like), plus a few for the new body.
SKINS = {
    "skin_pale": {"base": "wood_pale", "noise": [("wood_light", 0.04)]},
    "skin_tan": {"base": "wood_light", "noise": [("wood", 0.05)]},
    "skin_dark": {"base": "wood_mid", "noise": [("wood_dark", 0.06)]},
    "hair_dark": {"base": "black", "noise": [("iron_dark", 0.3)]},
    "hair_brown": {"base": "wood_dark", "noise": [("wood_mid", 0.25)]},
    "eye": {"base": "black"},
    "black": {"base": "black", "noise": [("iron_dark", 0.2)]},
    "lens": {"base": "sky_blue", "noise": [("steel_light", 0.15)]},
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
    "raider_black": {"base": "iron_dark", "noise": [("black", 0.2), ("iron", 0.04)]},
    "urban": {"base": "iron", "noise": [("iron_dark", 0.08)], "pattern": "camo", "blobs": ["black", "steel", "iron_dark"]},
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
HIP_Z = 0.60            # hip joints
KNEE_Z = 0.31
LEG_X = 0.19            # hip joints out from the middle
LEG_W = 0.30
WAIST_Z = 0.62          # the chest bends here
SHOULDER_Z = 1.36       # top of the chest
NECK_Z = 1.37           # the head turns here
HEAD = 0.52             # head block, from NECK_Z + 0.03
HEAD_Z = NECK_Z + 0.03
TORSO_W, TORSO_D = 0.76, 0.44
CHEST_Z = 0.80          # vests and rigs are placed from here
ARM_X = TORSO_W / 2 + 0.09   # shoulder joints
ARM_Z = SHOULDER_Z - 0.08
ARM_W = 0.18
UPPER = 0.30            # shoulder to elbow
FORE = 0.27             # elbow to wrist
ELBOW_Z = ARM_Z - UPPER
WRIST_Z = ELBOW_Z - FORE

JOINTS = {   # name: (parent, position)
    "Hips": (None, (0.0, 0.0, HIP_Z)),
    "Spine": ("Hips", (0.0, 0.0, WAIST_Z)),
    "Neck": ("Spine", (0.0, 0.0, NECK_Z)),
    "ArmL": ("Spine", (-ARM_X, 0.0, ARM_Z)),
    "ArmR": ("Spine", (ARM_X, 0.0, ARM_Z)),
    "ElbowL": ("ArmL", (-ARM_X, 0.0, ELBOW_Z)),
    "ElbowR": ("ArmR", (ARM_X, 0.0, ELBOW_Z)),
    "LegL": ("Hips", (-LEG_X, 0.0, HIP_Z)),
    "LegR": ("Hips", (LEG_X, 0.0, HIP_Z)),
    "KneeL": ("LegL", (-LEG_X, 0.0, KNEE_Z)),
    "KneeR": ("LegR", (LEG_X, 0.0, KNEE_Z)),
}


def rgba(name):
    h = PALETTE[name]
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [255]


class Atlas:
    """Hands out 16x16 tiles for skins as they get used, then paints them (as make_character.py)."""

    def __init__(self):
        self.tiles = {}

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
                    elif pattern == "sole" and y == TILE - 1:
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
        return px


class Part:
    """Blocks that become one mesh node, in body space (Blender axes); the writer moves them onto their joint."""

    def __init__(self, atlas):
        self.atlas = atlas
        self.quads = []   # (4 corners, normal, 4 uvs)

    def box(self, a, b, skin):
        lo = [min(a[i], b[i]) for i in range(3)]
        hi = [max(a[i], b[i]) for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        for axis in range(3):
            u_ax, v_ax = [(1, 2), (0, 2), (0, 1)][axis]
            ox, oy = self.atlas.uv_origin(skin, "side" if axis == 0 else "")
            for sign in (-1, 1):
                p = hi[axis] if sign > 0 else lo[axis]
                corners = []
                for (cu, cv) in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    c = [0.0, 0.0, 0.0]
                    c[axis] = p
                    c[u_ax] = hi[u_ax] if cu else lo[u_ax]
                    c[v_ax] = hi[v_ax] if cv else lo[v_ax]
                    corners.append(c)
                n = [0.0, 0.0, 0.0]
                n[axis] = float(sign)
                # winding: counter-clockwise seen from outside
                e1 = [corners[1][k] - corners[0][k] for k in range(3)]
                e2 = [corners[2][k] - corners[0][k] for k in range(3)]
                cr = mb.cross(e1, e2)
                if mb.dot(cr, n) < 0:
                    corners.reverse()
                uvs = []
                for c in corners:
                    u = ox + min(max((c[u_ax] - lo[u_ax]) * PX_PER_M, 0.0), TILE)
                    # v from the top of the block down, so a "sole" row lands at the bottom
                    w = oy + min(max((hi[v_ax] - c[v_ax]) * PX_PER_M, 0.0), TILE) if v_ax == 2 else \
                        oy + min(max((c[v_ax] - lo[v_ax]) * PX_PER_M, 0.0), TILE)
                    uvs.append((u / ATLAS, w / ATLAS))
                self.quads.append((corners, n, uvs))
        return self

    def tris(self):
        return len(self.quads) * 2


class Body:
    def __init__(self, name):
        self.name = name
        self.atlas = Atlas()
        self.parts = []    # (name, joint, Part or None)

    def part(self):
        return Part(self.atlas)

    def finish(self, part, name, joint):
        self.parts.append((name, joint, part))

    def empty(self, name, joint="Hips"):
        self.parts.append((name, joint, None))

    def tris(self, picks=None):
        return sum(p.tris() for _, _, p in self.parts if p is not None)


# ---------------------------------------------------------------- body parts

def legs(b, pants, boots):
    """pants / boots: {option: (skin, extras)}. extras: 'pads' (knee pads), 'pockets' (cargo)."""
    w = LEG_W / 2
    for option, (skin, extras) in pants.items():
        p = b.part().box((-TORSO_W / 2 + 0.03, -TORSO_D / 2 + 0.02, HIP_Z - 0.06), (TORSO_W / 2 - 0.03, TORSO_D / 2 - 0.02,
                         WAIST_Z + 0.02), skin)    # seat of the pants, the pelvis
        b.finish(p, "Pants__%s__Hips" % option, "Hips")
    for side, sx in (("L", -1), ("R", 1)):
        cx = sx * LEG_X
        for option, (skin, extras) in pants.items():
            p = b.part().box((cx - w, -w, KNEE_Z - 0.02), (cx + w, w, HIP_Z + 0.02), skin)
            if "pockets" in extras:
                ox = cx + sx * w
                p.box((ox, -0.07, KNEE_Z + 0.12), (ox + sx * 0.03, 0.07, KNEE_Z + 0.26), skin)
            b.finish(p, "Pants__%s__Leg%s" % (option, side), "Leg" + side)
            p = b.part().box((cx - w + 0.01, -w + 0.01, 0.12), (cx + w - 0.01, w - 0.01, KNEE_Z + 0.02), skin)
            if "pads" in extras:
                p.box((cx - w + 0.03, w - 0.01, KNEE_Z - 0.1), (cx + w - 0.03, w + 0.035, KNEE_Z + 0.04), "black")
            b.finish(p, "Pants__%s__Knee%s" % (option, side), "Knee" + side)
        for option, skin in boots.items():
            p = b.part().box((cx - w - 0.01, -w - 0.01, 0.0), (cx + w + 0.01, w + 0.07, 0.14), skin)
            b.finish(p, "Boots__%s__Knee%s" % (option, side), "Knee" + side)


def tops(b, options):
    """options: {option: (skin, extras)}. extras: 'hood', 'collar', 'armband' (red band on the left arm)."""
    a = ARM_W / 2
    for option, (skin, extras) in options.items():
        p = b.part().box((-TORSO_W / 2, -TORSO_D / 2, WAIST_Z - 0.04), (TORSO_W / 2, TORSO_D / 2, SHOULDER_Z), skin)
        p.box((-0.15, -0.13, SHOULDER_Z), (0.15, 0.11, NECK_Z + 0.04), skin)   # neck / collar
        if "hood" in extras:
            p.box((-0.2, -0.25, SHOULDER_Z - 0.06), (0.2, -TORSO_D / 2, NECK_Z + 0.14), skin)
        if "collar" in extras:
            p.box((-0.2, -0.17, SHOULDER_Z), (0.2, 0.1, NECK_Z + 0.08), skin)
        b.finish(p, "Top__%s__Spine" % option, "Spine")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            p = b.part().box((cx - a - 0.01, -a - 0.01, ELBOW_Z - 0.02), (cx + a + 0.01, a + 0.01, ARM_Z + a), skin)
            if "armband" in extras and side == "L":
                p.box((cx - a - 0.02, -a - 0.02, ELBOW_Z + 0.12), (cx + a + 0.02, a + 0.02, ELBOW_Z + 0.19), "armband")
            b.finish(p, "Top__%s__Arm%s" % (option, side), "Arm" + side)
            p = b.part().box((cx - a, -a, WRIST_Z + 0.02), (cx + a, a, ELBOW_Z + 0.02), skin)
            b.finish(p, "Top__%s__Elbow%s" % (option, side), "Elbow" + side)


def gloves(b, options):
    for option, skin in options.items():
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            h = ARM_W / 2 + 0.005
            p = b.part().box((cx - h, -h, WRIST_Z - 0.11), (cx + h, h, WRIST_Z + 0.04), skin)
            b.finish(p, "Gloves__%s__Elbow%s" % (option, side), "Elbow" + side)


def heads(b, options):
    """options: {option: (skin, hair, extras)}. extras: 'beard', 'balaclava' (skin = knit, hair = eye band skin),
    'skull' (painted skull mask, hair = mask skin), 'gasmask' (hair = filter canister skin)."""
    h = HEAD / 2
    z0, z1 = HEAD_Z, HEAD_Z + HEAD
    f = h          # the face's plane (+y)

    def at(t):     # height t (0 chin .. 1 crown) on the head
        return z0 + t * HEAD

    for option, (skin, hair, extras) in options.items():
        p = b.part().box((-h, -h, z0), (h, h, z1), skin)
        if "skull" in extras:
            p.box((-h + 0.04, f, at(0.08)), (h - 0.04, f + 0.02, at(0.88)), hair)
            for sx in (-1, 1):
                p.box((sx * 0.13, f + 0.02, at(0.48)), (sx * 0.04, f + 0.03, at(0.68)), "eye")
            p.box((-0.02, f + 0.02, at(0.35)), (0.02, f + 0.03, at(0.43)), "eye")
            p.box((-0.11, f + 0.02, at(0.16)), (0.11, f + 0.03, at(0.2)), "eye")
            b.finish(p, "Head__" + option, "Neck")
            continue
        if "gasmask" in extras:
            p.box((-0.16, f, at(0.08)), (0.16, f + 0.035, at(0.78)), "rubber")
            for sx in (-1, 1):
                p.box((sx * 0.13, f + 0.035, at(0.5)), (sx * 0.04, f + 0.045, at(0.7)), "lens")
            p.box((-0.055, f + 0.035, at(0.06)), (0.055, f + 0.13, at(0.3)), hair)
            b.finish(p, "Head__" + option, "Neck")
            continue
        if "balaclava" in extras:
            p.box((-0.15, f, at(0.48)), (0.15, f + 0.012, at(0.66)), hair)
            front = f + 0.012
        else:
            p.box((-0.025, f, at(0.36)), (0.025, f + 0.03, at(0.5)), skin)        # nose
            for sx in (-1, 1):
                p.box((sx * 0.13, f, at(0.66)), (sx * 0.05, f + 0.012, at(0.7)), hair)   # brows
            p.box((-h - 0.01, -h - 0.01, at(0.86)), (h + 0.01, h - 0.03, z1 + 0.04), hair)   # hair
            p.box((-h - 0.01, -h - 0.02, at(0.4)), (h + 0.01, -h + 0.01, z1 + 0.04), hair)
            if "beard" in extras:
                p.box((-0.16, f, z0 + 0.01), (0.16, f + 0.015, at(0.3)), hair)
            front = f
        for sx in (-1, 1):
            p.box((sx * 0.12, front, at(0.53)), (sx * 0.055, front + 0.012, at(0.62)), "eye")
        b.finish(p, "Head__" + option, "Neck")


def headset(p):
    for sx in (-1, 1):
        p.box((sx * (HEAD / 2), -0.06, HEAD_Z + 0.16), (sx * (HEAD / 2 + 0.06), 0.06, HEAD_Z + 0.32), "black")


def hat_box(p, skin, grow=0.03, bottom=0.78, top=0.28):
    """A cap-like block over the head: from `bottom` (fraction of head height) to `top` m above the crown... (y up)"""
    h = HEAD / 2 + grow
    p.box((-h, -h, HEAD_Z + HEAD * bottom), (h, h, HEAD_Z + HEAD + top), skin)
    return p


def chest_rig(p, skin):
    """A scav-style chest rig over the top: front panel, three pouches, straps over the shoulders."""
    d = TORSO_D / 2
    p.box((-0.26, d, CHEST_Z + 0.08), (0.26, d + 0.05, CHEST_Z + 0.32), skin)
    for cx in (-0.17, 0.0, 0.17):
        p.box((cx - 0.07, d + 0.05, CHEST_Z + 0.1), (cx + 0.07, d + 0.1, CHEST_Z + 0.28), skin)
    for sx in (-1, 1):
        x0, x1 = sx * 0.1, sx * 0.18
        p.box((x0, d, CHEST_Z + 0.32), (x1, d + 0.03, SHOULDER_Z + 0.01), skin)
        p.box((x0, -d - 0.02, SHOULDER_Z - 0.02), (x1, d + 0.03, SHOULDER_Z + 0.02), skin)
        p.box((x0, -d - 0.02, CHEST_Z + 0.08), (x1, -d, SHOULDER_Z + 0.01), skin)
    return p


# ---------------------------------------------------------------- the three characters

def build_scav(b):
    legs(b, {
        "track_black": ("track_black", ()), "track_blue": ("track_blue", ()), "jeans": ("denim", ()),
        "cargo_olive": ("cargo_olive", ("pockets",)), "woodland": ("woodland", ("pockets",)),
    }, {"sneaker_white": "sneaker_white", "sneaker_dark": "sneaker_dark", "boot_brown": "boot_brown",
        "boot_black": "boot_black"})
    tops(b, {
        "tracksuit_blue": ("track_blue", ()), "tracksuit_black": ("track_black", ()),
        "jacket_olive": ("jacket_olive", ("collar",)), "woodland": ("woodland", ("collar",)),
        "hoodie_grey": ("hoodie_grey", ("hood",)), "leather": ("leather", ("collar",)),
    })
    gloves(b, {"black": "black", "brown": "glove_brown", "olive": "glove_olive"})
    heads(b, {
        "balaclava_black": ("knit_black", "skin_pale", ("balaclava",)),
        "balaclava_olive": ("knit_olive", "skin_tan", ("balaclava",)),
        "pale": ("skin_pale", "hair_dark", ()), "tan_beard": ("skin_tan", "hair_brown", ("beard",)),
        "dark": ("skin_dark", "hair_dark", ()), "pale_beard": ("skin_pale", "hair_brown", ("beard",)),
    })
    for option, skin in (("beanie_black", "knit_black"), ("beanie_olive", "knit_olive")):
        p = hat_box(b.part(), skin, 0.02, 0.72, 0.07)
        b.finish(p, "Hat__" + option, "Neck")
    for option, skin in (("cap_sand", "cap_sand"), ("cap_red", "cap_red")):
        h = HEAD / 2 + 0.015
        p = b.part().box((-h, -h, HEAD_Z + HEAD * 0.8), (h, h - 0.02, HEAD_Z + HEAD + 0.06), skin)
        p.box((-0.15, h - 0.02, HEAD_Z + HEAD * 0.8), (0.15, h + 0.11, HEAD_Z + HEAD * 0.8 + 0.025), skin)
        b.finish(p, "Hat__" + option, "Neck")
    p = hat_box(b.part(), "fur", 0.03, 0.8, 0.09)
    for sx in (-1, 1):
        p.box((sx * (HEAD / 2), -0.11, HEAD_Z + HEAD * 0.4), (sx * (HEAD / 2 + 0.05), 0.11, HEAD_Z + HEAD * 0.9), "fur")
    b.finish(p, "Hat__ushanka", "Neck")
    p = hat_box(b.part(), "helmet_old", 0.03, 0.74, 0.08)
    p.box((-HEAD / 2 - 0.06, -HEAD / 2 - 0.06, HEAD_Z + HEAD * 0.72), (HEAD / 2 + 0.06, HEAD / 2 + 0.06,
          HEAD_Z + HEAD * 0.8), "helmet_old")
    b.finish(p, "Hat__helmet_old", "Neck")
    b.empty("Hat__none", "Neck")
    for option, skin in (("rig_sand", "canvas_sand"), ("rig_olive", "canvas_olive")):
        b.finish(chest_rig(b.part(), skin), "Vest__" + option, "Spine")
    b.empty("Vest__none", "Spine")


def build_pmc(b):
    pads = ("pads",)
    legs(b, {
        "green": ("shirt_green", pads), "black": ("shirt_black", pads), "tan": ("shirt_tan", pads),
        "multicam": ("multicam", pads + ("pockets",)),
    }, {"tan": "boot_tan", "coyote": "boot_coyote", "black": "boot_black"})
    tops(b, {"green": ("shirt_green", ()), "black": ("shirt_black", ()), "tan": ("shirt_tan", ()),
             "multicam": ("multicam", ())})
    gloves(b, {"black": "black", "tan": "glove_tan", "green": "glove_olive"})
    heads(b, {
        "pale": ("skin_pale", "hair_dark", ()), "tan": ("skin_tan", "hair_brown", ()),
        "dark": ("skin_dark", "hair_dark", ()), "pale_beard": ("skin_pale", "hair_brown", ("beard",)),
        "dark_beard": ("skin_dark", "hair_dark", ("beard",)),
    })
    h = HEAD / 2
    for option, skin in (("gaiter_tan", "gaiter_tan"), ("gaiter_black", "gaiter_black"), ("gaiter_green", "gaiter_green")):
        p = b.part().box((-h - 0.012, -h - 0.012, HEAD_Z - 0.01), (h + 0.012, h + 0.03, HEAD_Z + HEAD * 0.45), skin)
        b.finish(p, "Mask__" + option, "Neck")
    b.empty("Mask__none", "Neck")
    p = b.part().box((-0.16, h + 0.002, HEAD_Z + HEAD * 0.5), (0.16, h + 0.03, HEAD_Z + HEAD * 0.68), "black")
    b.finish(p, "Eyes__glasses", "Neck")
    b.empty("Eyes__none", "Neck")
    for option, skin in (("helmet_tan", "helmet_tan"), ("helmet_green", "helmet_green"), ("helmet_black", "helmet_black")):
        p = hat_box(b.part(), skin, 0.035, 0.74, 0.09)
        p.box((-0.04, h + 0.035, HEAD_Z + HEAD * 0.86), (0.04, h + 0.065, HEAD_Z + HEAD * 1.02), "black")   # NVG mount
        for sx in (-1, 1):
            p.box((sx * (h + 0.035), -0.1, HEAD_Z + HEAD * 0.8), (sx * (h + 0.05), 0.1, HEAD_Z + HEAD * 0.88), "black")
        headset(p)
        b.finish(p, "Hat__" + option, "Neck")
    p = b.part().box((-h - 0.015, -h - 0.015, HEAD_Z + HEAD * 0.8), (h + 0.015, h - 0.02, HEAD_Z + HEAD + 0.06), "black")
    p.box((-0.15, h - 0.02, HEAD_Z + HEAD * 0.8), (0.15, h + 0.11, HEAD_Z + HEAD * 0.8 + 0.025), "black")
    p.box((-h - 0.03, -0.035, HEAD_Z + HEAD * 0.7), (h + 0.03, 0.035, HEAD_Z + HEAD + 0.07), "black")   # headband
    headset(p)
    b.finish(p, "Hat__cap_headset", "Neck")
    d = TORSO_D / 2
    for option, skin in (("tan", "carrier_tan"), ("green", "carrier_green"), ("black", "carrier_black")):
        p = b.part().box((-TORSO_W / 2 + 0.03, -d - 0.04, CHEST_Z + 0.06), (TORSO_W / 2 - 0.03, d + 0.04, SHOULDER_Z - 0.04), skin)
        for sx in (-1, 1):
            p.box((sx * 0.1, -d - 0.04, SHOULDER_Z - 0.05), (sx * 0.2, d + 0.04, SHOULDER_Z + 0.02), skin)   # straps
        for cx in (-0.16, 0.0, 0.16):
            p.box((cx - 0.065, d + 0.04, CHEST_Z + 0.08), (cx + 0.065, d + 0.1, CHEST_Z + 0.25), skin)   # mag pouches
        p.box((-0.1, d + 0.04, CHEST_Z + 0.27), (0.1, d + 0.08, CHEST_Z + 0.41), skin)                 # admin pouch
        p.box((-0.17, -d - 0.09, CHEST_Z + 0.1), (0.17, -d - 0.04, CHEST_Z + 0.42), skin)              # back pouch
        b.finish(p, "Vest__" + option, "Spine")
        p = b.part().box((-TORSO_W / 2 - 0.01, -d - 0.01, HIP_Z + 0.02), (TORSO_W / 2 + 0.01, d + 0.01, WAIST_Z + 0.06), skin)
        b.finish(p, "Vest__%s__Hips" % option, "Hips")                                                 # battle belt


def build_raider(b):
    pads = ("pads",)
    legs(b, {"black": ("raider_black", pads), "urban": ("urban", pads + ("pockets",)), "olive": ("shirt_green", pads)},
         {"black": "boot_black", "brown": "boot_brown"})
    band = ("armband",)
    tops(b, {"black": ("raider_black", band + ("collar",)), "urban": ("urban", band),
             "rust": ("rust_jacket", band + ("collar",)), "hoodie_black": ("raider_black", band + ("hood",))})
    gloves(b, {"black": "black", "brown": "glove_brown"})
    heads(b, {
        "skull": ("knit_black", "skull_bone", ("skull",)), "gasmask": ("knit_black", "helmet_heavy", ("gasmask",)),
        "balaclava_black": ("knit_black", "skin_pale", ("balaclava",)),
        "balaclava_rust": ("knit_rust", "skin_tan", ("balaclava",)),
    })
    h = HEAD / 2
    for option, skin in (("altyn", "helmet_heavy"), ("altyn_black", "helmet_heavy_black")):
        p = hat_box(b.part(), skin, 0.04, 0.74, 0.1)
        p.box((-h - 0.05, -h - 0.05, HEAD_Z + HEAD * 0.35), (h + 0.05, h - 0.06, HEAD_Z + HEAD * 0.78), skin)
        p.box((-h + 0.02, h + 0.02, HEAD_Z + HEAD * 0.35), (h - 0.02, h + 0.06, HEAD_Z + HEAD * 0.78), "visor")
        p.box((-0.15, h + 0.06, HEAD_Z + HEAD * 0.56), (0.15, h + 0.065, HEAD_Z + HEAD * 0.64), "eye")
        b.finish(p, "Hat__" + option, "Neck")
    p = b.part().box((-h - 0.03, -h - 0.05, HEAD_Z + HEAD * 0.15), (h + 0.03, h - 0.03, HEAD_Z + HEAD + 0.07), "raider_black")
    b.finish(p, "Hat__hood", "Neck")
    p = b.part().box((-h - 0.015, -h - 0.02, HEAD_Z + HEAD * 0.82), (h + 0.015, h + 0.015, HEAD_Z + HEAD + 0.05), "armband")
    p.box((-0.05, -h - 0.05, HEAD_Z + HEAD * 0.8), (0.05, -h - 0.02, HEAD_Z + HEAD * 0.95), "armband")
    b.finish(p, "Hat__bandana", "Neck")
    b.empty("Hat__none", "Neck")
    d = TORSO_D / 2
    for option, skin in (("heavy_black", "heavy_black"), ("heavy_olive", "heavy_olive")):
        p = b.part().box((-TORSO_W / 2 + 0.02, -d - 0.05, CHEST_Z + 0.04), (TORSO_W / 2 - 0.02, d + 0.05, SHOULDER_Z - 0.02), skin)
        p.box((-0.24, -d - 0.04, SHOULDER_Z - 0.04), (0.24, d - 0.06, SHOULDER_Z + 0.06), skin)          # neck guard
        for cx in (-0.17, 0.0, 0.17):
            p.box((cx - 0.07, d + 0.05, CHEST_Z + 0.08), (cx + 0.07, d + 0.12, CHEST_Z + 0.26), skin)
        b.finish(p, "Vest__" + option, "Spine")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            a = ARM_W / 2 + 0.04
            p = b.part().box((cx - a, -a, ARM_Z - 0.1), (cx + a, a, ARM_Z + ARM_W / 2 + 0.04), skin)    # shoulder armor
            b.finish(p, "Vest__%s__Arm%s" % (option, side), "Arm" + side)
        p = b.part().box((-0.14, d - 0.02, HIP_Z - 0.16), (0.14, d + 0.04, WAIST_Z), skin)               # groin flap
        p.box((-TORSO_W / 2 - 0.01, -d - 0.01, HIP_Z + 0.02), (TORSO_W / 2 + 0.01, d + 0.01, WAIST_Z + 0.06), skin)
        b.finish(p, "Vest__%s__Hips" % option, "Hips")
    b.finish(chest_rig(b.part(), "canvas_black"), "Vest__rig_black", "Spine")


BUILDERS = {"scav": build_scav, "pmc": build_pmc, "raider": build_raider}


# ---------------------------------------------------------------- writing

def gl(p):
    """Blender axes to glTF axes."""
    return (p[0], p[2], -p[1])


def write_glb(path, body, png):
    blob = bytearray()
    views, accessors = [], []

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), **({"target": target} if target else {})})
        blob.extend(data)
        return len(views) - 1

    def add_accessor(values, ctype, kind, target, minmax=False):
        fmt = {"VEC3": "3f", "VEC2": "2f", "SCALAR": "I"}[kind]
        data = b"".join(struct.pack("<" + fmt, *(v if isinstance(v, tuple) else (v,))) for v in values)
        acc = {"bufferView": add_view(data, target), "componentType": ctype, "count": len(values), "type": kind}
        if minmax:
            acc["min"] = [min(v[k] for v in values) for k in range(3)]
            acc["max"] = [max(v[k] for v in values) for k in range(3)]
        accessors.append(acc)
        return len(accessors) - 1

    nodes, meshes = [], []
    index = {}
    for name, (parent, pos) in JOINTS.items():
        rel = pos if parent is None else mb.v_sub(pos, JOINTS[parent][1])
        index[name] = len(nodes)
        nodes.append({"name": name, "translation": list(gl(rel)), "children": []})
        if parent is not None:
            nodes[index[parent]]["children"].append(index[name])
    for name, joint, part in body.parts:
        origin = JOINTS[joint][1]
        node = {"name": name}
        if part is not None:
            pos, nrm, uv, idx = [], [], [], []
            for corners, n, uvs in part.quads:
                base = len(pos)
                for c, t in zip(corners, uvs):
                    pos.append(gl(mb.v_sub(c, origin)))
                    nrm.append(gl(n))
                    uv.append(t)
                idx += [base, base + 1, base + 2, base, base + 2, base + 3]
            meshes.append({"name": name, "primitives": [{"attributes": {
                "POSITION": add_accessor(pos, 5126, "VEC3", 34962, True),
                "NORMAL": add_accessor(nrm, 5126, "VEC3", 34962),
                "TEXCOORD_0": add_accessor(uv, 5126, "VEC2", 34962)},
                "indices": add_accessor(idx, 5125, "SCALAR", 34963), "material": 0}]})
            node["mesh"] = len(meshes) - 1
        nodes[index[joint]]["children"].append(len(nodes))
        nodes.append(node)
    for n in nodes:
        if "children" in n and not n["children"]:
            del n["children"]
    image = {"bufferView": add_view(png), "mimeType": "image/png", "name": body.name}
    gltf = {"asset": {"version": "2.0", "generator": "Bloxov make_body.py"}, "scene": 0,
            "scenes": [{"nodes": [index["Hips"]]}], "nodes": nodes, "meshes": meshes,
            "materials": [{"name": body.name + "_mat", "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0}}],
            "textures": [{"source": 0, "sampler": 0}], "images": [image],
            "samplers": [{"magFilter": 9728, "minFilter": 9984, "wrapS": 33071, "wrapT": 33071}],
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": 0}]}
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(out)


def shown_tris(body):
    """Triangles of the biggest outfit (the most one character can show)."""
    best = {}
    for name, _, part in body.parts:
        bits = name.split("__")
        slot, option = bits[0], bits[1] if len(bits) > 1 else ""
        n = part.tris() if part else 0
        best.setdefault(slot, {}).setdefault(option, 0)
        best[slot][option] += n
    return sum(max(opts.values()) for opts in best.values())


def main(out_dir=None):
    names = [a for a in sys.argv[1:] if a in BUILDERS] or list(BUILDERS)
    for a in sys.argv[1:]:
        if a.startswith("out="):
            out_dir = a[4:]
    for name in names:
        body = Body(name)
        BUILDERS[name](body)
        tex = os.path.join(ROOT, "art_source", "textures", name + "_body.png")
        px = body.atlas.paint()
        rows = list(reversed(px))   # write_png takes rows bottom-first
        mb.write_png(tex, ATLAS, ATLAS, rows)
        with open(tex, "rb") as f:
            png = f.read()
        path = os.path.join(out_dir or os.path.join(ROOT, "assets", "models", "characters"), name + "_body.glb")
        write_glb(path, body, png)
        print("%s: %d parts, %d triangles at most showing, %d tiles -> %s"
              % (name, len(body.parts), shown_tris(body), len(body.atlas.tiles), path))


if __name__ == "__main__":
    main()
