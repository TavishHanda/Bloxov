"""Bloxov jointed characters (0.23): the Scav, PMC and Raider on joints, so they can kneel, lie prone and crawl
instead of squashing or tipping over stiff. Same outfit slots and skins as make_character.py, new body (look C,
owner 2026-10-26: "make it the same as before for now": the old models' sizes, ~2.05 m, just with joints).

Run: python3 art_source/scripts/make_character.py [scav|pmc|raider ...]   (all three without arguments)
No Blender needed (the .glb is written directly; the old Blender script and art_source/<character>.blend are retired).
Texture: one 256 px atlas per character, 32 px per meter (clean flat colours since 2026-11-09), art_source/textures/<character>.png
(repainted every run). The raid characters keep their old part sizes: tools/check_character_bounds.py checks it.
Writes assets/models/characters/<character>.glb.

Built in Blender axes (front +y, up +z, feet at the origin) and written as glTF (front -z, up +y).
Joints (empty nodes; the game turns them, scripts/body_pose.gd):
  Hips                 the pelvis, at the hip joints' height
    Spine              the chest, bends at the waist
      Neck             the head turns and nods here
      ArmL, ArmR       shoulders; the arm hangs down -y in its own frame
        ElbowL, ElbowR forearm and hand (glove)
    LegL, LegR         hip joints; the leg hangs down
      KneeL, KneeR     shin and boot
  Gun                  (beside Hips) where the right hand holds the gun, with a "Muzzle" empty; scripts/held_gun.gd
                       swaps it for the real gun model and body_pose.gd moves it into the hands.
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
    # (traders, lively hideout)
    "white": "e9e6dc", "white_dark": "c9c4b6", "gold": "d4a73a", "gold_dark": "9c7522", "felt": "2f6b3a",
    "maroon": "6b2430", "navy": "26324a", "navy_dark": "1a2335", "grey_hair": "9a9a96", "scrub": "4f8a7a",
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
    # Traders (lively hideout, 2026-11-09)
    "shirt_white": {"base": "white", "noise": [("white_dark", 0.12)]},
    "apron_leather": {"base": "wood_dark", "noise": [("wood_mid", 0.18), ("black", 0.05)]},
    "gold": {"base": "gold", "noise": [("gold_dark", 0.25)]},
    "brass": {"base": "yellow_dark", "noise": [("gold_dark", 0.3)]},
    "felt_green": {"base": "felt", "noise": [("green_dark", 0.15)]},
    "waistcoat_maroon": {"base": "maroon", "noise": [("rust", 0.08)], "pattern": "weave", "weave": "wood_dark"},
    "waistcoat_black": {"base": "black", "noise": [("iron_dark", 0.15)], "pattern": "weave", "weave": "iron_dark"},
    "suit_navy": {"base": "navy", "noise": [("navy_dark", 0.15)]},
    "coat_dark": {"base": "navy_dark", "noise": [("black", 0.2)]},
    "coat_white": {"base": "white", "noise": [("white_dark", 0.15), ("concrete", 0.04)]},
    "loud": {"base": "red", "noise": [("rust", 0.08)], "pattern": "camo", "blobs": ["gold", "black", "gold_dark"]},
    "scrubs": {"base": "scrub", "noise": [("felt", 0.12)]},
    "hair_grey": {"base": "grey_hair", "noise": [("steel", 0.25)]},
    "lens_green": {"base": "felt", "noise": [("extract_green", 0.1)]},
    "beret_maroon": {"base": "maroon", "noise": [("rust", 0.15)], "pattern": "knit", "knit": "wood_dark"},
    "flatcap_grey": {"base": "steel", "noise": [("iron", 0.2)], "pattern": "weave", "weave": "iron"},
    "boonie": {"base": "olive_light", "noise": [("olive", 0.2)], "pattern": "weave", "weave": "olive"},
    "fedora": {"base": "iron_dark", "noise": [("black", 0.15)]},
    "lamp": {"base": "bone", "noise": [("white", 0.3)]},
    "maroon_band": {"base": "maroon", "noise": [("rust", 0.1)]},
    "steel_metal": {"base": "steel_light", "noise": [("steel", 0.3)]},
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
# 0.25.22 (owner: "the heads are kinda too big, maybe reduce size a bit"): everything on the Neck joint (head,
# hats, helmets, gaiters) is written this much smaller, around the neck joint, so it still sits on the shoulders.
# The head hitboxes shrank with it (Hitbox.HEAD_*, the HeadShape of each character scene, BodyPose.HEAD_MID).
HEAD_SCALE = 0.85
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
    """Hands out square tiles (TILE px) for skins as they get used, then paints them (as make_character.py)."""

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
                    elif pattern == "sole" and y >= TILE - max(1, TILE // 16):
                        color = spec["sole"]
                    elif pattern == "stripe" and variant == "side" and TILE // 16 <= x < 3 * TILE // 16:
                        color = spec["stripe"]
                    px[oy + y][ox + x] = rgba(color)
            if pattern == "camo":
                k = TILE // 16                                         # (the trader's tiles are bigger: same-sized blobs)
                for blob in spec["blobs"]:
                    for _ in range(7 * k * k):
                        bx, by = rng.randrange(TILE), rng.randrange(TILE)
                        for dy in range(rng.choice((1, 2)) * k):
                            for dx in range(rng.choice((2, 3)) * k):
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

# Clean skins for the trader model (owner 2026-11-09: "clean up all the models, make them look nice and lively"):
# twice the pixels (32 px/m), flat colours with only a faint mottle, so the shapes and the details read, not noise.
TRADER_SKINS = {
    "t_skin_pale": ("e0b48c", [("d4a57c", 0.03)]), "t_skin_tan": ("c08a5c", [("b37e52", 0.03)]),
    "t_skin_dark": ("7a4f33", [("6e462d", 0.03)]), "t_lip": ("8e4a3c", []), "t_lip_dark": ("4e2a1e", []),
    "t_eye_white": ("efece4", []), "t_pupil": ("23201e", []),
    "t_hair_dark": ("2a2420", [("332c27", 0.08)]), "t_hair_brown": ("5a3a22", [("4a301c", 0.08)]),
    "t_hair_grey": ("a7a49e", [("918e88", 0.1)]), "t_hair_black": ("17161a", [("222125", 0.06)]),
    "t_white": ("ebe8df", [("dcd8cc", 0.04)]), "t_white_dk": ("cfcabe", []),
    "t_olive": ("5d6438", [("555c33", 0.04)]), "t_olive_dk": ("444a28", []), "t_tan": ("b29e72", [("a69369", 0.04)]),
    "t_tan_dk": ("8f7d56", []), "t_black": ("2a2b2e", [("303134", 0.05)]), "t_black_dk": ("1c1d20", []),
    "t_navy": ("2c3a55", [("27344d", 0.05)]), "t_denim": ("4a6886", [("43607d", 0.06)]), "t_denim_dk": ("3a5470", []),
    "t_leather": ("6a4127", [("5e3a22", 0.06)]), "t_leather_dk": ("4a2c19", []), "t_maroon": ("6e2632", [("62212c", 0.05)]),
    "t_red": ("a8322b", [("9a2d27", 0.04)]), "t_gold": ("d9ad40", [("c49a32", 0.12)]), "t_gold_dk": ("9c7522", []),
    "t_brass": ("b08a3a", [("9c7a30", 0.15)]), "t_steel": ("8b9197", [("7c8288", 0.1)]), "t_steel_dk": ("4b5057", []),
    "t_scrubs": ("4f8a7a", [("487f70", 0.04)]), "t_scrubs_dk": ("3d6d60", []), "t_lens": ("2b3a30", [("3d5a46", 0.1)]),
    "t_shades": ("15161a", [("2a3440", 0.06)]), "t_grey": ("777a7c", [("6e7173", 0.06)]), "t_track": ("26282c", [("2d2f33", 0.05)]),
    "t_felt": ("2f6b3a", [("2a6034", 0.05)]), "t_sole": ("1b1a19", []), "t_boot_brown": ("4e3220", [("452c1c", 0.06)]),
    "t_boot_black": ("232326", [("2b2b2e", 0.05)]), "t_sneaker": ("e6e3da", [("d9d5ca", 0.05)]),
    "t_coffee": ("efeee8", []), "t_cream": ("d9cfb4", [("cfc4a8", 0.05)]),
}
for _name, (_base, _noise) in TRADER_SKINS.items():
    PALETTE[_name] = _base
    for _i, (_c, _ch) in enumerate(_noise):
        PALETTE["%s_n%d" % (_name, _i)] = _c
    SKINS[_name] = {"base": _name, "noise": [("%s_n%d" % (_name, _i), _ch) for _i, (_c, _ch) in enumerate(_noise)]}
PALETTE.update({"t_woodland_a": "3f4a2c", "t_woodland_b": "6f7046", "t_woodland_c": "2b2a22",
                "t_loud_a": "d9ad40", "t_loud_b": "7a1f1a", "t_fur_a": "5e3c24", "t_fur_b": "7c5232"})
SKINS["t_woodland"] = {"base": "t_olive", "noise": [], "pattern": "camo", "blobs": ["t_woodland_a", "t_woodland_b", "t_woodland_c"]}
SKINS["t_loud"] = {"base": "t_red", "noise": [], "pattern": "camo", "blobs": ["t_loud_a", "t_loud_b"]}
SKINS["t_fur"] = {"base": "t_fur_a", "noise": [("t_fur_b", 0.25)], "pattern": "knit", "knit": "t_fur_b"}
SKINS["t_knit"] = {"base": "t_black", "noise": [], "pattern": "knit", "knit": "t_black_dk"}
SKINS["t_track_side"] = {"base": "t_track", "noise": [], "pattern": "stripe", "stripe": "t_white"}

T_SKIN = {"pale": "t_skin_pale", "tan": "t_skin_tan", "dark": "t_skin_dark"}


def t_face(b, option, skin, hair, beard=False, bald=False, lip="t_lip"):
    """A clean face: whites to the eyes, brows, a nose, a mouth, ears and a shaped haircut (and a jaw beard)."""
    h = HEAD / 2
    z0 = HEAD_Z
    f = h

    def at(t):
        return z0 + t * HEAD
    p = b.part().box((-h, -h, z0), (h, h, z0 + HEAD), skin)
    for sx in (-1, 1):
        p.box((sx * h, -0.05, at(0.38)), (sx * (h + 0.03), 0.05, at(0.62)), skin)                       # ears
        p.box((sx * 0.055, f, at(0.5)), (sx * 0.15, f + 0.006, at(0.6)), "t_eye_white")                 # eyes
        p.box((sx * 0.065, f + 0.006, at(0.5)), (sx * 0.105, f + 0.012, at(0.59)), "t_pupil")
        p.box((sx * 0.045, f, at(0.65)), (sx * 0.16, f + 0.014, at(0.69)), hair)                      # brows
    p.box((-0.03, f, at(0.36)), (0.03, f + 0.045, at(0.5)), skin)                                      # nose
    if beard:
        p.box((-0.17, f, z0), (0.17, f + 0.02, at(0.3)), hair)                                         # jaw and chin
        for sx in (-1, 1):
            p.box((sx * 0.17, f - 0.02, z0), (sx * h, f + 0.02, at(0.48)), hair)
            p.box((sx * (h - 0.0), -0.05, z0), (sx * (h + 0.01), f + 0.02, at(0.4)), hair)
        p.box((-0.11, f + 0.02, at(0.26)), (0.11, f + 0.035, at(0.32)), hair)                          # moustache
        p.box((-0.065, f + 0.02, at(0.18)), (0.065, f + 0.03, at(0.22)), lip)
    else:
        p.box((-0.07, f, at(0.21)), (0.07, f + 0.008, at(0.245)), lip)                                 # mouth
    if not bald:
        p.box((-h - 0.012, -h - 0.012, at(0.86)), (h + 0.012, h + 0.012, z0 + HEAD + 0.03), hair)        # crown
        p.box((-h - 0.012, -h - 0.02, at(0.42)), (h + 0.012, -h + 0.04, z0 + HEAD + 0.03), hair)         # back
        for sx in (-1, 1):
            p.box((sx * (h - 0.0), -h - 0.012, at(0.62)), (sx * (h + 0.014), 0.04, at(0.9)), hair)      # sides
        p.box((-h - 0.012, f - 0.01, at(0.84)), (0.06, f + 0.015, at(0.95)), hair)                       # fringe
    else:
        p.box((-h - 0.012, -h - 0.02, at(0.42)), (h + 0.012, -h + 0.06, at(0.7)), hair)                  # a ring round
        for sx in (-1, 1):
            p.box((sx * h, -h - 0.012, at(0.55)), (sx * (h + 0.014), -0.06, at(0.72)), hair)
    b.finish(p, "Head__" + option, "Neck")


def t_tops(b, options):
    """options: {option: (skin, dark skin, extras)}. extras: 'buttons', 'zip', 'collar', 'cuffs', 'pockets', 'sleeves_up'
    (rolled sleeves: the forearms bare), 'stripe' (tracksuit stripes down the arms)."""
    a = ARM_W / 2
    d = TORSO_D / 2
    for option, (skin, dark, extras) in options.items():
        p = b.part().box((-TORSO_W / 2, -d, WAIST_Z - 0.04), (TORSO_W / 2, d, SHOULDER_Z), skin)
        p.box((-0.15, -0.13, SHOULDER_Z), (0.15, 0.11, NECK_Z + 0.04), skin)                            # neck
        p.box((-TORSO_W / 2 - 0.006, -d - 0.006, WAIST_Z - 0.04), (TORSO_W / 2 + 0.006, d + 0.006, WAIST_Z), dark)   # hem
        if "collar" in extras:
            p.box((-0.19, -0.16, SHOULDER_Z - 0.01), (0.19, -0.1, NECK_Z + 0.09), dark)
            for sx in (-1, 1):
                p.box((sx * 0.06, 0.02, SHOULDER_Z - 0.09), (sx * 0.19, d + 0.012, SHOULDER_Z + 0.03), dark)
        if "buttons" in extras:
            p.box((-0.025, d, WAIST_Z), (0.025, d + 0.008, SHOULDER_Z - 0.06), dark)
            for k in range(4):
                z = WAIST_Z + 0.1 + k * 0.17
                p.box((-0.015, d + 0.008, z), (0.015, d + 0.016, z + 0.03), "t_white_dk" if dark != "t_white_dk" else "t_steel")
        if "zip" in extras:
            p.box((-0.012, d, WAIST_Z), (0.012, d + 0.01, SHOULDER_Z), "t_steel")
        if "pockets" in extras:
            for sx in (-1, 1):
                p.box((sx * 0.08, d, CHEST_Z + 0.24), (sx * 0.27, d + 0.018, CHEST_Z + 0.44), skin)
                p.box((sx * 0.08, d + 0.018, CHEST_Z + 0.4), (sx * 0.27, d + 0.03, CHEST_Z + 0.46), dark)
        b.finish(p, "Top__%s__Spine" % option, "Spine")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            p = b.part().box((cx - a - 0.01, -a - 0.01, ELBOW_Z - 0.02), (cx + a + 0.01, a + 0.01, ARM_Z + a), skin)
            if "stripe" in extras:
                p.box((cx + sx * (a + 0.01), -0.03, ELBOW_Z), (cx + sx * (a + 0.02), 0.03, ARM_Z + a), "t_white")
            b.finish(p, "Top__%s__Arm%s" % (option, side), "Arm" + side)
            if "sleeves_up" in extras:
                p = b.part().box((cx - a - 0.02, -a - 0.02, ELBOW_Z - 0.03), (cx + a + 0.02, a + 0.02, ELBOW_Z + 0.05), dark)
            else:
                p = b.part().box((cx - a, -a, WRIST_Z + 0.02), (cx + a, a, ELBOW_Z + 0.02), skin)
                if "stripe" in extras:
                    p.box((cx + sx * a, -0.03, WRIST_Z + 0.02), (cx + sx * (a + 0.01), 0.03, ELBOW_Z + 0.02), "t_white")
                if "cuffs" in extras or "stripe" in extras:
                    p.box((cx - a - 0.008, -a - 0.008, WRIST_Z + 0.02), (cx + a + 0.008, a + 0.008, WRIST_Z + 0.07), dark)
            b.finish(p, "Top__%s__Elbow%s" % (option, side), "Elbow" + side)


def t_legs(b, pants, boots):
    """pants: {option: (skin, dark, extras)}: 'belt' (a belt and buckle), 'pockets' (cargo), 'stripe' (down the side)."""
    w = LEG_W / 2
    for option, (skin, dark, extras) in pants.items():
        p = b.part().box((-TORSO_W / 2 + 0.03, -TORSO_D / 2 + 0.02, HIP_Z - 0.06), (TORSO_W / 2 - 0.03, TORSO_D / 2 - 0.02,
                         WAIST_Z + 0.02), skin)
        if "belt" in extras:
            p.box((-TORSO_W / 2 + 0.02, -TORSO_D / 2 + 0.01, WAIST_Z - 0.06), (TORSO_W / 2 - 0.02, TORSO_D / 2 - 0.01, WAIST_Z), "t_leather_dk")
            p.box((-0.05, TORSO_D / 2 - 0.01, WAIST_Z - 0.065), (0.05, TORSO_D / 2 + 0.005, WAIST_Z + 0.005), "t_brass")
        b.finish(p, "Pants__%s__Hips" % option, "Hips")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * LEG_X
            p = b.part().box((cx - w, -w, KNEE_Z - 0.02), (cx + w, w, HIP_Z + 0.02), skin)
            if "pockets" in extras:
                ox = cx + sx * w
                p.box((ox, -0.07, KNEE_Z + 0.08), (ox + sx * 0.03, 0.07, KNEE_Z + 0.24), skin)
                p.box((ox, -0.07, KNEE_Z + 0.21), (ox + sx * 0.035, 0.07, KNEE_Z + 0.25), dark)
            if "stripe" in extras:
                p.box((cx + sx * w, -0.025, KNEE_Z - 0.02), (cx + sx * (w + 0.008), 0.025, HIP_Z + 0.02), "t_white")
            b.finish(p, "Pants__%s__Leg%s" % (option, side), "Leg" + side)
            p = b.part().box((cx - w + 0.01, -w + 0.01, 0.12), (cx + w - 0.01, w - 0.01, KNEE_Z + 0.02), skin)
            if "stripe" in extras:
                p.box((cx + sx * (w - 0.01), -0.025, 0.12), (cx + sx * (w - 0.002), 0.025, KNEE_Z + 0.02), "t_white")
            b.finish(p, "Pants__%s__Knee%s" % (option, side), "Knee" + side)
        pass
    for option, (skin, lace) in boots.items():
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * LEG_X
            p = b.part().box((cx - w - 0.01, -w - 0.01, 0.035), (cx + w + 0.01, w + 0.07, 0.15), skin)
            p.box((cx - w - 0.015, -w - 0.015, 0.0), (cx + w + 0.015, w + 0.075, 0.035), "t_sole")          # sole
            p.box((cx - 0.05, w + 0.07, 0.07), (cx + 0.05, w + 0.078, 0.14), lace)                        # laces
            b.finish(p, "Boots__%s__Knee%s" % (option, side), "Knee" + side)


def t_hands(b, options):
    """Hands: a palm block and a thumb, in a skin or a glove."""
    for option, skin in options.items():
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            h = ARM_W / 2 - 0.005
            p = b.part().box((cx - h, -h, WRIST_Z - 0.12), (cx + h, h, WRIST_Z + 0.02), skin)
            p.box((cx - sx * h - 0.0, h - 0.06, WRIST_Z - 0.08), (cx - sx * (h + 0.025), h, WRIST_Z), skin)   # thumb
            if option.startswith("none_"):                             # bare: the forearm too (a sleeve covers it)
                f = ARM_W / 2 - 0.008
                p.box((cx - f, -f, WRIST_Z), (cx + f, f, ELBOW_Z + 0.02), skin)
            b.finish(p, "Gloves__%s__Elbow%s" % (option, side), "Elbow" + side)


def build_trader(b):
    """The hideout's traders and crew (lively hideout, owner 2026-11-09: proper, unique looks, "clean up all the
    models, make them look nice and lively"). Its own model, so the players' and the AI's bodies (and hitboxes) are
    untouched: the same jointed frame, but clean flat colours at twice the pixels and real faces, hands, belts, soles,
    collars and buttons. Each trader's or crew member's look picks one option per slot (scripts/trader_looks.gd)."""
    h, d = HEAD / 2, TORSO_D / 2
    t_legs(b, {"olive": ("t_olive", "t_olive_dk", ("belt", "pockets")), "black": ("t_black", "t_black_dk", ("belt",)),
               "navy": ("t_navy", "t_black_dk", ("belt",)), "jeans": ("t_denim", "t_denim_dk", ("belt",)),
               "tan": ("t_tan", "t_tan_dk", ("belt", "pockets")), "scrubs": ("t_scrubs", "t_scrubs_dk", ()),
               "track": ("t_track", "t_black_dk", ("stripe",)), "woodland": ("t_woodland", "t_olive_dk", ("belt", "pockets"))},
           {"brown": ("t_boot_brown", "t_leather_dk"), "black": ("t_boot_black", "t_black_dk"),
            "white": ("t_sneaker", "t_white_dk"), "tan": ("t_tan", "t_tan_dk")})
    t_tops(b, {"white": ("t_white", "t_white_dk", ("collar", "buttons", "cuffs")),
               "white_rolled": ("t_white", "t_white_dk", ("collar", "buttons", "sleeves_up")),
               "olive": ("t_olive", "t_olive_dk", ("collar", "buttons", "pockets", "cuffs")),
               "leather": ("t_leather", "t_leather_dk", ("collar", "zip", "cuffs")),
               "fur": ("t_fur", "t_leather_dk", ("collar", "cuffs")),
               "navy": ("t_navy", "t_black_dk", ("collar", "buttons", "cuffs")),
               "loud": ("t_loud", "t_black_dk", ("collar", "buttons", "sleeves_up")),
               "scrubs": ("t_scrubs", "t_scrubs_dk", ("collar",)),
               "coat_white": ("t_white", "t_white_dk", ("collar", "buttons", "pockets", "cuffs")),
               "coat_dark": ("t_black", "t_black_dk", ("collar", "buttons", "cuffs")),
               "track": ("t_track", "t_black_dk", ("collar", "zip", "stripe")),
               "woodland": ("t_woodland", "t_olive_dk", ("collar", "buttons", "pockets", "cuffs")),
               "tee_olive": ("t_olive", "t_olive_dk", ("sleeves_up",)), "tee_grey": ("t_grey", "t_steel_dk", ("sleeves_up",)),
               "tee_tan": ("t_tan", "t_tan_dk", ("sleeves_up",))})
    for option, skin, dark in (("fur", "t_fur", "t_leather_dk"), ("coat_white", "t_white", "t_white_dk"),
                               ("coat_dark", "t_black", "t_black_dk")):   # long coats: open at the front
        p = b.part()
        p.box((-TORSO_W / 2 - 0.02, -d - 0.02, KNEE_Z - 0.02), (TORSO_W / 2 + 0.02, -d + 0.04, WAIST_Z + 0.02), skin)
        for sx in (-1, 1):
            p.box((sx * (TORSO_W / 2 + 0.02), -d - 0.02, KNEE_Z - 0.02), (sx * (TORSO_W / 2 - 0.04), d + 0.04, WAIST_Z + 0.02), skin)
            p.box((sx * (TORSO_W / 2 + 0.02), d - 0.02, KNEE_Z - 0.02), (sx * 0.13, d + 0.04, WAIST_Z + 0.02), skin)
            p.box((sx * 0.13, d + 0.0, KNEE_Z - 0.02), (sx * 0.16, d + 0.045, WAIST_Z + 0.02), dark)       # its edge
        p.box((-TORSO_W / 2 - 0.025, -d - 0.025, KNEE_Z - 0.03), (TORSO_W / 2 + 0.025, -d + 0.045, KNEE_Z + 0.02), dark)
        b.finish(p, "Top__%s__Hips" % option, "Hips")
    t_hands(b, {"brown": "t_leather", "black": "t_black", "white": "t_white", "none_pale": "t_skin_pale",
                "none_tan": "t_skin_tan", "none_dark": "t_skin_dark"})
    for option, (tone, hair, extra) in {
            "pale": ("pale", "t_hair_brown", {}), "pale_beard": ("pale", "t_hair_brown", {"beard": True}),
            "tan": ("tan", "t_hair_dark", {}), "tan_beard": ("tan", "t_hair_dark", {"beard": True}),
            "dark": ("dark", "t_hair_black", {"lip": "t_lip_dark"}),
            "dark_beard": ("dark", "t_hair_black", {"beard": True, "lip": "t_lip_dark"}),
            "old_pale": ("pale", "t_hair_grey", {"beard": True}), "old_tan": ("tan", "t_hair_grey", {"bald": True}),
            "bald_dark": ("dark", "t_hair_black", {"bald": True, "lip": "t_lip_dark"})}.items():
        t_face(b, option, T_SKIN[tone], hair, **extra)
    for option, skin in (("moustache_dark", "t_hair_dark"), ("moustache_grey", "t_hair_grey")):   # a big moustache
        p = b.part().box((-0.13, h + 0.01, HEAD_Z + HEAD * 0.25), (0.13, h + 0.04, HEAD_Z + HEAD * 0.33), skin)
        for sx in (-1, 1):
            p.box((sx * 0.09, h + 0.01, HEAD_Z + HEAD * 0.15), (sx * 0.14, h + 0.04, HEAD_Z + HEAD * 0.26), skin)
        b.finish(p, "Tash__" + option, "Neck")
    b.empty("Tash__none", "Neck")
    # Headgear. Every hat stands a clear 3 cm proud of the hair (0.34.9, owner: "glitching textures going through each
    # other"): the cap, bandana and flatcap used to put their back face on exactly the hair's back plane (-h - 0.02), so
    # the two fought for the same pixels. The hair's outer faces are x +-0.014, y -h-0.02, so hats use h + 0.03.
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.84), (h + 0.05, h + 0.03, HEAD_Z + HEAD + 0.04), "t_maroon")
    p.box((-0.02, -h + 0.0, HEAD_Z + HEAD + 0.02), (h + 0.09, h - 0.02, HEAD_Z + HEAD + 0.08), "t_maroon")
    p.box((-h - 0.035, -h - 0.035, HEAD_Z + HEAD * 0.82), (h + 0.035, h + 0.035, HEAD_Z + HEAD * 0.87), "t_leather_dk")
    p.box((-0.15, h + 0.02, HEAD_Z + HEAD * 0.86), (-0.07, h + 0.04, HEAD_Z + HEAD * 0.98), "t_gold")      # badge
    b.finish(p, "Hat__beret", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.82), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.06), "t_grey")
    p.box((-h - 0.01, h + 0.02, HEAD_Z + HEAD * 0.82), (h + 0.01, h + 0.12, HEAD_Z + HEAD * 0.82 + 0.03), "t_grey")
    b.finish(p, "Hat__flatcap", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.82), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.06), "t_olive")
    p.box((-0.16, h + 0.02, HEAD_Z + HEAD * 0.82), (0.16, h + 0.13, HEAD_Z + HEAD * 0.82 + 0.03), "t_olive_dk")
    b.finish(p, "Hat__cap", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.8), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.1), "t_tan")
    p.box((-h - 0.1, -h - 0.1, HEAD_Z + HEAD * 0.8), (h + 0.1, h + 0.1, HEAD_Z + HEAD * 0.8 + 0.03), "t_tan")
    p.box((-h - 0.04, -h - 0.04, HEAD_Z + HEAD * 0.83), (h + 0.04, h + 0.04, HEAD_Z + HEAD * 0.9), "t_tan_dk")
    b.finish(p, "Hat__boonie", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.84), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.15), "t_black")
    p.box((-h - 0.09, -h - 0.09, HEAD_Z + HEAD * 0.84), (h + 0.09, h + 0.09, HEAD_Z + HEAD * 0.84 + 0.025), "t_black")
    p.box((-h - 0.035, -h - 0.035, HEAD_Z + HEAD * 0.84 + 0.025), (h + 0.035, h + 0.035, HEAD_Z + HEAD * 0.84 + 0.07), "t_maroon")
    b.finish(p, "Hat__fedora", "Neck")
    p = b.part().box((-h - 0.03, -0.04, HEAD_Z + HEAD * 0.7), (h + 0.03, 0.04, HEAD_Z + HEAD + 0.05), "t_black")
    for sx in (-1, 1):
        p.box((sx * h, -0.08, HEAD_Z + HEAD * 0.3), (sx * (h + 0.08), 0.08, HEAD_Z + HEAD * 0.66), "t_olive_dk")
    b.finish(p, "Hat__ear_defenders", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.82), (h + 0.03, h + 0.03, HEAD_Z + HEAD * 0.9), "t_black")
    p.box((-0.16, h + 0.02, HEAD_Z + HEAD * 0.84), (0.16, h + 0.13, HEAD_Z + HEAD * 0.88), "t_felt")
    b.finish(p, "Hat__visor", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.76), (h + 0.03, h + 0.03, HEAD_Z + HEAD * 0.84), "t_black")
    p.box((-0.05, h + 0.02, HEAD_Z + HEAD * 0.74), (0.05, h + 0.06, HEAD_Z + HEAD * 0.86), "t_coffee")
    b.finish(p, "Hat__head_torch", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.72), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.08), "t_knit")
    p.box((-h - 0.04, -h - 0.04, HEAD_Z + HEAD * 0.7), (h + 0.04, h + 0.04, HEAD_Z + HEAD * 0.8), "t_knit")   # turn-up
    b.finish(p, "Hat__beanie", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.82), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.04), "t_felt")
    p.box((-0.04, -h - 0.09, HEAD_Z + HEAD * 0.8), (0.04, -h - 0.02, HEAD_Z + HEAD * 0.95), "t_felt")       # the knot
    b.finish(p, "Hat__bandana", "Neck")
    b.empty("Hat__none", "Neck")
    # Eyes
    p = b.part().box((-h - 0.01, -h - 0.01, HEAD_Z + HEAD * 0.8), (h + 0.01, h + 0.01, HEAD_Z + HEAD * 0.86), "t_black")
    for sx in (-1, 1):
        p.box((sx * 0.15, h + 0.01, HEAD_Z + HEAD * 0.78), (sx * 0.03, h + 0.07, HEAD_Z + HEAD * 0.92), "t_brass")
        p.box((sx * 0.135, h + 0.07, HEAD_Z + HEAD * 0.8), (sx * 0.045, h + 0.075, HEAD_Z + HEAD * 0.9), "t_lens")
    b.finish(p, "Eyes__goggles", "Neck")
    p = b.part()
    for sx in (-1, 1):
        p.box((sx * 0.04, h + 0.012, HEAD_Z + HEAD * 0.5), (sx * 0.165, h + 0.028, HEAD_Z + HEAD * 0.63), "t_shades")
        p.box((sx * h, -0.02, HEAD_Z + HEAD * 0.58), (sx * (h + 0.012), h + 0.02, HEAD_Z + HEAD * 0.62), "t_black")
    p.box((-0.04, h + 0.012, HEAD_Z + HEAD * 0.58), (0.04, h + 0.024, HEAD_Z + HEAD * 0.62), "t_black")
    b.finish(p, "Eyes__shades", "Neck")
    p = b.part()
    for sx in (-1, 1):   # round-ish wire specs: a rim round each eye
        p.box((sx * 0.045, h + 0.014, HEAD_Z + HEAD * 0.48), (sx * 0.16, h + 0.02, HEAD_Z + HEAD * 0.5), "t_brass")
        p.box((sx * 0.045, h + 0.014, HEAD_Z + HEAD * 0.61), (sx * 0.16, h + 0.02, HEAD_Z + HEAD * 0.63), "t_brass")
        p.box((sx * 0.155, h + 0.014, HEAD_Z + HEAD * 0.48), (sx * 0.165, h + 0.02, HEAD_Z + HEAD * 0.63), "t_brass")
        p.box((sx * h, -0.02, HEAD_Z + HEAD * 0.59), (sx * (h + 0.01), h + 0.02, HEAD_Z + HEAD * 0.61), "t_brass")
    p.box((-0.045, h + 0.014, HEAD_Z + HEAD * 0.56), (0.045, h + 0.02, HEAD_Z + HEAD * 0.58), "t_brass")
    b.finish(p, "Eyes__specs", "Neck")
    p = b.part().box((0.045, h + 0.012, HEAD_Z + HEAD * 0.48), (0.16, h + 0.1, HEAD_Z + HEAD * 0.63), "t_black")   # loupe
    p.box((0.06, h + 0.1, HEAD_Z + HEAD * 0.5), (0.145, h + 0.105, HEAD_Z + HEAD * 0.61), "t_lens")
    p.box((0.16, -0.02, HEAD_Z + HEAD * 0.56), (h + 0.01, h + 0.02, HEAD_Z + HEAD * 0.59), "t_black")
    p.box((h, -h - 0.01, HEAD_Z + HEAD * 0.56), (h + 0.01, -0.02, HEAD_Z + HEAD * 0.59), "t_black")
    b.finish(p, "Eyes__loupe", "Neck")
    p = b.part().box((-0.16, h + 0.012, HEAD_Z + HEAD * 0.47), (-0.04, h + 0.03, HEAD_Z + HEAD * 0.64), "t_black")   # patch
    p.box((-h - 0.01, -h - 0.01, HEAD_Z + HEAD * 0.68), (h + 0.01, h + 0.016, HEAD_Z + HEAD * 0.71), "t_black")
    b.finish(p, "Eyes__patch", "Neck")
    b.empty("Eyes__none", "Neck")
    p = b.part().box((-h - 0.012, -h + 0.06, HEAD_Z + HEAD * 0.08), (h + 0.012, h + 0.03, HEAD_Z + HEAD * 0.46), "t_cream")
    p.box((-h - 0.012, -h + 0.06, HEAD_Z + HEAD * 0.44), (h + 0.012, -h + 0.08, HEAD_Z + HEAD * 0.48), "t_white_dk")
    b.finish(p, "Mask__surgical", "Neck")
    b.empty("Mask__none", "Neck")
    # Over the top
    for option, skin, dark in (("apron", "t_leather", "t_leather_dk"), ("apron_white", "t_white", "t_white_dk")):
        p = b.part().box((-0.27, d, CHEST_Z - 0.1), (0.27, d + 0.025, SHOULDER_Z - 0.08), skin)
        for sx in (-1, 1):
            p.box((sx * 0.12, d, SHOULDER_Z - 0.1), (sx * 0.17, d + 0.025, SHOULDER_Z + 0.01), dark)       # neck strap
            p.box((sx * 0.27, -d - 0.005, WAIST_Z + 0.02), (sx * (TORSO_W / 2 + 0.006), d + 0.025, WAIST_Z + 0.06), dark)
        p.box((-0.12, d + 0.025, CHEST_Z + 0.03), (0.12, d + 0.045, CHEST_Z + 0.18), dark)                 # pocket
        b.finish(p, "Vest__" + option, "Spine")
        p = b.part().box((-0.27, d + 0.01, KNEE_Z + 0.04), (0.27, d + 0.035, WAIST_Z + 0.02), skin)
        b.finish(p, "Vest__%s__Hips" % option, "Hips")
    p = b.part()
    for k in range(9):                                                 # a bandolier from the left shoulder to the right hip
        t = k / 8.0
        x = -0.22 + 0.44 * t
        z = SHOULDER_Z - 0.03 - (SHOULDER_Z - WAIST_Z - 0.06) * t
        p.box((x - 0.045, d, z - 0.045), (x + 0.045, d + 0.03, z + 0.045), "t_leather_dk")
        p.box((x - 0.016, d + 0.03, z - 0.02), (x + 0.016, d + 0.05, z + 0.07), "t_brass")
        p.box((-x - 0.045, -d - 0.03, z - 0.045), (-x + 0.045, -d, z + 0.045), "t_leather_dk")
    b.finish(p, "Vest__bandolier", "Spine")
    for option, out in (("chain", 0.0), ("chain_belly", 1.0)):       # a heavy gold chain (laid over a belly, or not)
        p = b.part()
        for k in range(7):
            for sx in (-1, 1):
                x = sx * (0.13 - k * 0.018)
                z = SHOULDER_Z - 0.02 - k * 0.045
                y = d + 0.006 + out * (0.11 if z < CHEST_Z + 0.38 else 0.0) + out * (0.05 if z < CHEST_Z + 0.27 else 0.0)
                p.box((x - 0.022, y, z - 0.022), (x + 0.022, y + 0.026, z + 0.022), "t_gold")
        y = d + 0.006 + out * 0.16
        p.box((-0.045, y, SHOULDER_Z - 0.42), (0.045, y + 0.034, SHOULDER_Z - 0.31), "t_gold")
        p.box((-0.02, y + 0.034, SHOULDER_Z - 0.39), (0.02, y + 0.04, SHOULDER_Z - 0.34), "t_gold_dk")
        b.finish(p, "Vest__" + option, "Spine")
    for option, skin in (("waistcoat_maroon", "t_maroon"), ("waistcoat_black", "t_black")):
        p = b.part()
        p.box((-TORSO_W / 2 + 0.02, -d - 0.015, WAIST_Z - 0.04), (TORSO_W / 2 - 0.02, -d + 0.03, SHOULDER_Z - 0.06), skin)
        for sx in (-1, 1):
            p.box((sx * (TORSO_W / 2 - 0.02), -d - 0.015, WAIST_Z - 0.04), (sx * 0.02, d + 0.015, SHOULDER_Z - 0.12), skin)
            p.box((sx * (TORSO_W / 2 - 0.02), -d - 0.015, SHOULDER_Z - 0.12), (sx * 0.13, d + 0.015, SHOULDER_Z - 0.06), skin)
        for k in range(4):
            p.box((-0.018, d + 0.015, WAIST_Z + 0.04 + k * 0.12), (0.018, d + 0.025, WAIST_Z + 0.07 + k * 0.12), "t_gold")
        p.box((-0.07, d - 0.02, SHOULDER_Z - 0.02), (0.07, d + 0.03, SHOULDER_Z + 0.05), "t_black")      # bow tie
        p.box((-0.02, d + 0.03, SHOULDER_Z - 0.005), (0.02, d + 0.035, SHOULDER_Z + 0.035), "t_black_dk")
        b.finish(p, "Vest__" + option, "Spine")
    p = b.part().box((-TORSO_W / 2 + 0.03, -d - 0.04, CHEST_Z + 0.06), (TORSO_W / 2 - 0.03, d + 0.04, SHOULDER_Z - 0.04), "t_tan")
    for cx in (-0.17, 0.17):
        p.box((cx - 0.08, d + 0.04, CHEST_Z + 0.08), (cx + 0.08, d + 0.1, CHEST_Z + 0.3), "t_tan_dk")
    for sx in (-1, 1):
        p.box((sx * 0.1, -d - 0.04, SHOULDER_Z - 0.05), (sx * 0.2, d + 0.04, SHOULDER_Z + 0.02), "t_tan_dk")
    b.finish(p, "Vest__shooting", "Spine")
    p = b.part()                                                       # a stethoscope round the neck
    for sx in (-1, 1):
        p.box((sx * 0.15, -0.1, SHOULDER_Z - 0.005), (sx * 0.19, d + 0.02, SHOULDER_Z + 0.03), "t_black")
        p.box((sx * 0.15, d + 0.005, CHEST_Z + 0.2), (sx * 0.19, d + 0.025, SHOULDER_Z + 0.03), "t_black")
    p.box((0.13, d + 0.01, CHEST_Z + 0.12), (0.22, d + 0.045, CHEST_Z + 0.21), "t_steel")
    b.finish(p, "Vest__stethoscope", "Spine")
    b.empty("Vest__none", "Spine")
    for option, skin, dark in (("leather", "t_leather", "t_leather_dk"), ("fur", "t_fur", "t_leather_dk"),
                               ("olive", "t_olive", "t_olive_dk"), ("navy", "t_navy", "t_black_dk"),
                               ("loud", "t_loud", "t_black_dk"), ("track", "t_track", "t_black_dk"),
                               ("white", "t_white", "t_white_dk")):
        p = b.part()                                                   # a big belly, rounded off: two layers out front
        p.box((-0.33, d - 0.02, WAIST_Z - 0.03), (0.33, d + 0.11, CHEST_Z + 0.38), skin)
        p.box((-0.25, d + 0.11, WAIST_Z + 0.06), (0.25, d + 0.16, CHEST_Z + 0.27), skin)
        p.box((-0.335, d - 0.02, WAIST_Z - 0.04), (0.335, d + 0.115, WAIST_Z + 0.0), dark)
        b.finish(p, "Belly__" + option, "Spine")
    b.empty("Belly__none", "Spine")


# ---------------------------------------------------------------- the raid characters, clean (owner 2026-11-09)
# Owner 2026-11-09: the scavs, raiders (and Bon) and the players' PMC get the traders' clean look: twice the pixels,
# flat colours with a faint mottle, and small real details (faces with eye whites and mouths, belts and buckles, boot
# soles and laces, zips, buttons, pocket flaps, knee pads, headset cups). The bodies don't change: every part keeps the
# same option name and fits inside the box the old part had (the details sit in shallow insets), so the hitboxes
# measured off the model stay exactly the same (tools/check_character_bounds.py checks it, scripts/hitbox.gd's numbers
# too through the smoke test).
RAID_SKINS = {
    "c_track_blue": ("3d5f86", [("38587c", 0.05)]), "c_track_blue_dk": ("2b4566", []),
    "c_jacket_olive": ("5f6a3a", [("586235", 0.05)]), "c_jacket_olive_dk": ("454d29", []),
    "c_hoodie": ("7b8086", [("73787e", 0.05)]), "c_hoodie_dk": ("5e6368", []),
    "c_cargo": ("7a7f4e", [("727749", 0.05)]), "c_cargo_dk": ("5d6239", []),
    "c_canvas_sand": ("a8976a", [("9f8f63", 0.06)]), "c_canvas_sand_dk": ("7f7150", []),
    "c_canvas_olive": ("4c5331", [("464c2d", 0.06)]), "c_canvas_olive_dk": ("363b22", []),
    "c_canvas_black": ("2b2c2f", [("323336", 0.06)]), "c_canvas_black_dk": ("1d1e20", []),
    "c_sneaker_dark": ("35373b", [("3c3e42", 0.05)]), "c_cap_sand": ("b5a576", [("ab9c6e", 0.05)]),
    "c_cap_sand_dk": ("8f8259", []), "c_cap_red": ("a8322b", [("9c2e28", 0.05)]), "c_cap_red_dk": ("7a231e", []),
    "c_helmet_old": ("5c6339", [("555b34", 0.06), ("6e4a2c", 0.02)]), "c_helmet_old_dk": ("41462a", []),
    "c_shirt_green": ("4b5534", [("464f30", 0.05)]), "c_shirt_green_dk": ("363d25", []),
    "c_shirt_black": ("2e3034", [("34363a", 0.05)]), "c_shirt_black_dk": ("1f2124", []),
    "c_shirt_tan": ("a99a72", [("a0926b", 0.05)]), "c_shirt_tan_dk": ("857858", []),
    "c_carrier_tan": ("ad9d71", [("a4956b", 0.05)]), "c_carrier_tan_dk": ("857857", []),
    "c_carrier_green": ("56603a", [("4f5935", 0.05)]), "c_carrier_green_dk": ("3c4428", []),
    "c_carrier_black": ("2c2e32", [("33353a", 0.05)]), "c_carrier_black_dk": ("1c1d20", []),
    "c_helmet_tan": ("b09f73", [("a6966c", 0.05)]), "c_helmet_green": ("56603a", [("4f5935", 0.05)]),
    "c_helmet_black": ("303236", [("383a3e", 0.05)]), "c_boot_tan": ("b29e72", [("a8956b", 0.05)]),
    "c_boot_coyote": ("8a6a46", [("806240", 0.05)]), "c_glove_tan": ("b09f73", [("a6966c", 0.04)]),
    "c_glove_olive": ("4c5331", [("464c2d", 0.04)]),
    "c_raider": ("2b2c30", [("323338", 0.05)]), "c_raider_dk": ("1c1d20", []),
    "c_rust": ("7d3a22", [("75361f", 0.05)]), "c_rust_dk": ("5a2918", []),
    "c_armband": ("b03a2e", [("a5362b", 0.04)]), "c_bone": ("e3dccb", [("d8d0bd", 0.05)]),
    "c_rubber": ("27282c", [("2e2f33", 0.05)]), "c_visor": ("8b9197", [("82888e", 0.06)]),
    "c_lens_blue": ("4a7090", [("6a90b0", 0.08)]), "c_heavy_olive": ("444a2c", [("3e4428", 0.05)]),
    "c_heavy_olive_dk": ("2f3320", []), "c_heavy_black": ("2f3134", [("36383c", 0.05)]),
    "c_altyn": ("4e5434", [("484e30", 0.05), ("6a4a2e", 0.02)]), "c_altyn_black": ("2f3134", [("36383c", 0.05)]),
}
for _name, (_base, _noise) in RAID_SKINS.items():
    PALETTE[_name] = _base
    for _i, (_c, _ch) in enumerate(_noise):
        PALETTE["%s_n%d" % (_name, _i)] = _c
    SKINS[_name] = {"base": _name, "noise": [("%s_n%d" % (_name, _i), _ch) for _i, (_c, _ch) in enumerate(_noise)]}
PALETTE.update({"c_mc_a": "7f6e4a", "c_mc_b": "5f6a3e", "c_mc_c": "c4b68c", "c_urban_a": "3a3d42", "c_urban_b": "9a9ea2",
                "c_urban_c": "25272b", "c_wl_a": "3f4a2c", "c_wl_b": "6e5a3a", "c_wl_c": "26261f"})
SKINS["c_multicam"] = {"base": "c_shirt_tan", "noise": [], "pattern": "camo", "blobs": ["c_mc_a", "c_mc_b", "c_mc_c"]}
SKINS["c_urban"] = {"base": "c_hoodie_dk", "noise": [], "pattern": "camo", "blobs": ["c_urban_a", "c_urban_b", "c_urban_c"]}
SKINS["c_woodland"] = {"base": "c_jacket_olive", "noise": [], "pattern": "camo", "blobs": ["c_wl_a", "c_wl_b", "c_wl_c"]}
# Knits: a faint row texture only (the old knit pattern is too busy at 32 px).
for _name, _base, _dark in (("c_knit_black", "t_black", "t_black_dk"), ("c_knit_olive", "c_canvas_olive", "c_canvas_olive_dk"),
                            ("c_knit_rust", "c_rust", "c_rust_dk"), ("c_knit_tan", "c_canvas_sand", "c_canvas_sand_dk"),
                            ("c_knit_green", "c_shirt_green", "c_shirt_green_dk")):
    SKINS[_name] = {"base": _base, "noise": [(_dark, 0.07)]}


def c_legs(b, pants, boots):
    """pants: {option: (skin, dark, extras)}: 'belt' (belt and buckle), 'cord' (a drawstring), 'pockets' (cargo),
    'pads' (knee pads), 'stripe' (down the side), 'cuff' (turned-up hems). boots: {option: (upper, sole, lace)}."""
    w = LEG_W / 2
    sx0, sy0, sz0, sz1 = TORSO_W / 2 - 0.03, TORSO_D / 2 - 0.02, HIP_Z - 0.06, WAIST_Z + 0.02
    for option, (skin, dark, extras) in pants.items():
        p = b.part()
        if "belt" in extras:
            p.box((-sx0 + 0.005, -sy0 + 0.005, sz0), (sx0 - 0.005, sy0 - 0.015, sz1 - 0.05), skin)
            p.box((-sx0, -sy0, sz1 - 0.05), (sx0, sy0 - 0.01, sz1), "t_leather_dk")
            p.box((-0.045, sy0 - 0.01, sz1 - 0.045), (0.045, sy0, sz1 - 0.005), "t_brass")
        else:
            p.box((-sx0, -sy0, sz0), (sx0, sy0 - 0.01, sz1), skin)
            if "cord" in extras:
                for x in (-0.04, 0.03):
                    p.box((x, sy0 - 0.01, sz1 - 0.075), (x + 0.012, sy0, sz1 - 0.01), "t_white")
        b.finish(p, "Pants__%s__Hips" % option, "Hips")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * LEG_X
            out = cx + sx * w
            p = b.part()
            if "stripe" in extras:
                p.box((cx - sx * w, -w, KNEE_Z - 0.02), (out - sx * 0.006, w, HIP_Z + 0.02), skin)
                p.box((out - sx * 0.006, -0.025, KNEE_Z - 0.02), (out, 0.025, HIP_Z + 0.02), "t_white")
            else:
                p.box((cx - w, -w, KNEE_Z - 0.02), (cx + w, w, HIP_Z + 0.02), skin)
            if "pockets" in extras:                                    # cargo pocket on the outside, with its flap
                p.box((out, -0.065, KNEE_Z + 0.12), (out + sx * 0.024, 0.065, KNEE_Z + 0.22), skin)
                p.box((out, -0.07, KNEE_Z + 0.22), (out + sx * 0.03, 0.07, KNEE_Z + 0.26), dark)
            b.finish(p, "Pants__%s__Leg%s" % (option, side), "Leg" + side)
            p = b.part()
            lo = 0.12
            if "cuff" in extras:
                p.box((cx - w + 0.01, -w + 0.01, 0.12), (cx + w - 0.01, w - 0.01, 0.17), dark)
                lo = 0.17
            if "stripe" in extras:
                p.box((cx - sx * (w - 0.01), -w + 0.01, lo), (out - sx * 0.016, w - 0.01, KNEE_Z + 0.02), skin)
                p.box((out - sx * 0.016, -0.025, lo), (out - sx * 0.01, 0.025, KNEE_Z + 0.02), "t_white")
            else:
                p.box((cx - w + 0.01, -w + 0.01, lo), (cx + w - 0.01, w - 0.01, KNEE_Z + 0.02), skin)
            if "pads" in extras:                                       # knee pad: a padded shell on a strap
                p.box((cx - w + 0.03, w - 0.01, KNEE_Z - 0.1), (cx + w - 0.03, w + 0.022, KNEE_Z + 0.04), "t_black_dk")
                p.box((cx - w + 0.045, w + 0.022, KNEE_Z - 0.085), (cx + w - 0.045, w + 0.035, KNEE_Z + 0.025), "t_black")
            b.finish(p, "Pants__%s__Knee%s" % (option, side), "Knee" + side)
    for option, (upper, sole, lace) in boots.items():
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * LEG_X
            p = b.part().box((cx - w - 0.01, -w - 0.01, 0.0), (cx + w + 0.01, w + 0.07, 0.03), sole)      # sole
            p.box((cx - w - 0.005, -w - 0.005, 0.03), (cx + w + 0.005, w + 0.06, 0.12), upper)
            p.box((cx - w - 0.01, -w - 0.01, 0.12), (cx + w + 0.01, w + 0.01, 0.14), upper)            # the top
            p.box((cx - w - 0.005, w + 0.06, 0.03), (cx + w + 0.005, w + 0.07, 0.07), upper)           # toe
            p.box((cx - 0.045, w + 0.06, 0.075), (cx + 0.045, w + 0.068, 0.135), lace)                 # laces
            b.finish(p, "Boots__%s__Knee%s" % (option, side), "Knee" + side)


def c_tops(b, options):
    """options: {option: (skin, dark, extras)}: 'hood' (+ drawstrings, a front pocket), 'collar', 'zip', 'buttons',
    'pockets' (chest), 'stripe' (down the arms), 'armband' (the raiders' red band, left arm), 'patch' (a sleeve
    patch), 'cuffs'. The chest sits 1 cm in at the front, so zips, buttons and pockets stay inside the old block."""
    a = ARM_W / 2
    d = TORSO_D / 2
    for option, (skin, dark, extras) in options.items():
        p = b.part().box((-TORSO_W / 2, -d, WAIST_Z), (TORSO_W / 2, d - 0.01, SHOULDER_Z), skin)
        p.box((-TORSO_W / 2, -d, WAIST_Z - 0.04), (TORSO_W / 2, d, WAIST_Z), dark)                     # hem
        p.box((-0.15, -0.13, SHOULDER_Z), (0.15, 0.11, NECK_Z + 0.04), skin)                           # neck
        if "hood" in extras:
            p.box((-0.2, -0.25, SHOULDER_Z - 0.06), (0.2, -d, NECK_Z + 0.14), skin)
            p.box((-0.17, -0.25, NECK_Z + 0.06), (0.17, -0.24, NECK_Z + 0.12), dark)                    # its fold
            for x in (-0.07, 0.055):
                p.box((x, d - 0.01, SHOULDER_Z - 0.22), (x + 0.015, d, SHOULDER_Z), "t_white")         # drawstrings
            p.box((-0.2, d - 0.01, WAIST_Z + 0.02), (0.2, d, WAIST_Z + 0.22), dark)                    # front pocket
        if "collar" in extras:
            p.box((-0.2, -0.17, SHOULDER_Z), (0.2, 0.05, NECK_Z + 0.08), dark)
            for sx in (-1, 1):
                p.box((sx * 0.06, 0.05, SHOULDER_Z), (sx * 0.2, 0.1, NECK_Z + 0.06), dark)
        if "zip" in extras:
            p.box((-0.012, d - 0.01, WAIST_Z), (0.012, d, SHOULDER_Z), "t_steel")
        if "buttons" in extras:
            p.box((-0.025, d - 0.01, WAIST_Z), (0.025, d - 0.003, SHOULDER_Z), dark)
            for k in range(4):
                z = WAIST_Z + 0.1 + k * 0.17
                p.box((-0.014, d - 0.003, z), (0.014, d, z + 0.028), "t_black_dk")
        if "pockets" in extras:
            for sx in (-1, 1):
                p.box((sx * 0.08, d - 0.01, CHEST_Z + 0.24), (sx * 0.27, d - 0.004, CHEST_Z + 0.42), skin)
                p.box((sx * 0.08, d - 0.01, CHEST_Z + 0.42), (sx * 0.27, d, CHEST_Z + 0.47), dark)
        b.finish(p, "Top__%s__Spine" % option, "Spine")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            out = cx + sx * (a + 0.01)
            p = b.part().box((cx - a - 0.01, -a - 0.01, ELBOW_Z - 0.02), (cx + a + 0.01, a + 0.01, ARM_Z + a), skin)
            if "armband" in extras and side == "L":
                p.box((cx - a - 0.02, -a - 0.02, ELBOW_Z + 0.12), (cx + a + 0.02, a + 0.02, ELBOW_Z + 0.19), "c_armband")
            if "stripe" in extras:
                p.box((out, -0.03, ELBOW_Z - 0.02), (out + sx * 0.008, 0.03, ARM_Z + a), "t_white")
            if "patch" in extras:
                p.box((out, -0.06, ELBOW_Z + 0.1), (out + sx * 0.012, 0.06, ELBOW_Z + 0.22), dark)
            b.finish(p, "Top__%s__Arm%s" % (option, side), "Arm" + side)
            p = b.part().box((cx - a, -a, WRIST_Z + 0.02), (cx + a, a, ELBOW_Z + 0.02), skin)
            if "stripe" in extras:
                p.box((cx + sx * a, -0.03, WRIST_Z + 0.02), (cx + sx * (a + 0.008), 0.03, ELBOW_Z + 0.02), "t_white")
            if "cuffs" in extras or "stripe" in extras:
                p.box((cx - a - 0.008, -a - 0.008, WRIST_Z + 0.02), (cx + a + 0.008, a + 0.008, WRIST_Z + 0.07), dark)
            b.finish(p, "Top__%s__Elbow%s" % (option, side), "Elbow" + side)


def c_gloves(b, options):
    """options: {option: (skin, dark)}: a hand with a thumb, a cuff and a knuckle pad on the back."""
    for option, (skin, dark) in options.items():
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            h = ARM_W / 2 + 0.005
            p = b.part().box((cx - h + 0.005, -h + 0.005, WRIST_Z - 0.11), (cx + h - 0.005, h - 0.005, WRIST_Z), skin)
            p.box((cx - h, -h, WRIST_Z), (cx + h, h, WRIST_Z + 0.04), dark)                              # cuff
            p.box((cx + sx * (h - 0.005), -0.06, WRIST_Z - 0.1), (cx + sx * (h + 0.005), 0.06, WRIST_Z - 0.04), dark)
            p.box((cx - 0.04, h - 0.005, WRIST_Z - 0.07), (cx + 0.04, h + 0.02, WRIST_Z - 0.01), skin)  # thumb
            b.finish(p, "Gloves__%s__Elbow%s" % (option, side), "Elbow" + side)


def c_eyes(p, front, lid=None):
    """Eye whites and pupils on a face whose front is at y = `front` (a brow or eye band above in `lid`)."""
    for sx in (-1, 1):
        p.box((sx * 0.05, front, HEAD_Z + HEAD * 0.52), (sx * 0.13, front + 0.005, HEAD_Z + HEAD * 0.62), "t_eye_white")
        p.box((sx * 0.06, front + 0.005, HEAD_Z + HEAD * 0.52), (sx * 0.1, front + 0.01, HEAD_Z + HEAD * 0.61), "t_pupil")
        if lid:
            p.box((sx * 0.045, front, HEAD_Z + HEAD * 0.65), (sx * 0.14, front + 0.012, HEAD_Z + HEAD * 0.69), lid)


def c_heads(b, options):
    """options: {option: (kind, skin, hair)}. kinds: 'face', 'beard', 'balaclava' (skin = knit, hair = the eyes' skin
    tone), 'skull' (hair = mask), 'gasmask' (hair = filter). Each fits inside the old head block."""
    h = HEAD / 2
    z0, z1 = HEAD_Z, HEAD_Z + HEAD
    f = h

    def at(t):
        return z0 + t * HEAD

    for option, (kind, skin, hair) in options.items():
        p = b.part().box((-h, -h, z0), (h, h, z1), skin)
        if kind == "skull":                                            # a painted skull on a black knit hood
            p.box((-h + 0.04, f, at(0.08)), (h - 0.04, f + 0.018, at(0.88)), hair)
            for sx in (-1, 1):
                p.box((sx * 0.13, f + 0.018, at(0.46)), (sx * 0.035, f + 0.028, at(0.68)), "t_black_dk")
                p.box((sx * 0.1, f + 0.028, at(0.54)), (sx * 0.07, f + 0.03, at(0.6)), "c_armband")   # red glints
            p.box((-0.022, f + 0.018, at(0.34)), (0.022, f + 0.028, at(0.43)), "t_black_dk")
            p.box((-0.12, f + 0.018, at(0.17)), (0.12, f + 0.028, at(0.21)), "t_black_dk")
            for k in range(-2, 3):                                     # teeth
                p.box((k * 0.045 - 0.006, f + 0.018, at(0.12)), (k * 0.045 + 0.006, f + 0.028, at(0.26)), "t_black_dk")
        elif kind == "gasmask":
            p.box((-0.16, f, at(0.08)), (0.16, f + 0.03, at(0.78)), "c_rubber")
            p.box((-0.16, f, at(0.08)), (0.16, f + 0.035, at(0.13)), "t_black_dk")
            for sx in (-1, 1):
                p.box((sx * 0.14, f + 0.03, at(0.48)), (sx * 0.035, f + 0.035, at(0.72)), "t_black_dk")   # lens rims
                p.box((sx * 0.125, f + 0.035, at(0.5)), (sx * 0.05, f + 0.045, at(0.7)), "c_lens_blue")
            p.box((-0.055, f + 0.035, at(0.06)), (0.055, f + 0.11, at(0.3)), hair)                    # the filter
            p.box((-0.06, f + 0.11, at(0.055)), (0.06, f + 0.13, at(0.305)), "t_black_dk")
            for sx in (-1, 1):                                         # straps round the head
                p.box((sx * h, -0.04, at(0.55)), (sx * (h + 0.0), 0.04, at(0.62)), "c_rubber")
        elif kind == "balaclava":                                      # knit, with the eyes showing
            p.box((-0.15, f, at(0.48)), (0.15, f + 0.012, at(0.7)), hair)
            c_eyes(p, f + 0.012)
            p.box((-0.15, f + 0.012, at(0.68)), (0.15, f + 0.024, at(0.7)), skin)                      # its edge
        else:
            p.box((-0.025, f, at(0.36)), (0.025, f + 0.03, at(0.5)), skin)                               # nose
            c_eyes(p, f, hair)
            for sx in (-1, 1):
                p.box((sx * h, -0.05, at(0.38)), (sx * (h + 0.01), 0.05, at(0.6)), skin)               # ears
            p.box((-h - 0.01, -h - 0.01, at(0.86)), (h + 0.01, h - 0.03, z1 + 0.04), hair)              # hair
            p.box((-h - 0.01, -h - 0.02, at(0.4)), (h + 0.01, -h + 0.04, z1 + 0.04), hair)
            for sx in (-1, 1):
                p.box((sx * h, -h + 0.04, at(0.62)), (sx * (h + 0.01), 0.04, at(0.86)), hair)          # sides
            p.box((-h - 0.01, h - 0.03, at(0.85)), (0.06, f + 0.015, at(0.95)), hair)                    # fringe
            lip = "t_lip_dark" if skin == "t_skin_dark" else "t_lip"
            if kind == "beard":
                p.box((-0.17, f, z0), (0.17, f + 0.015, at(0.3)), hair)
                for sx in (-1, 1):
                    p.box((sx * 0.17, f - 0.02, z0), (sx * h, f + 0.015, at(0.46)), hair)
                p.box((-0.11, f + 0.015, at(0.26)), (0.11, f + 0.026, at(0.32)), hair)                  # moustache
                p.box((-0.06, f + 0.015, at(0.18)), (0.06, f + 0.024, at(0.22)), lip)
            else:
                p.box((-0.07, f, at(0.21)), (0.07, f + 0.008, at(0.245)), lip)                         # mouth
        b.finish(p, "Head__" + option, "Neck")


def c_headset(p):
    for sx in (-1, 1):
        p.box((sx * (HEAD / 2), -0.06, HEAD_Z + 0.16), (sx * (HEAD / 2 + 0.06), 0.06, HEAD_Z + 0.32), "t_black")
        p.box((sx * (HEAD / 2 + 0.05), -0.035, HEAD_Z + 0.185), (sx * (HEAD / 2 + 0.06), 0.035, HEAD_Z + 0.295), "t_black_dk")


def c_cap(b, name, skin, dark, h, headset=False, peak=0.0):
    """A peaked cap; with a headset under it (the PMC's), a band over the top too. `peak`: the crown's front and the
    peak this much farther out (the scavs' caps always were)."""
    p = b.part().box((-h - 0.015, -h - 0.015, HEAD_Z + HEAD * 0.8), (h + 0.015, h - 0.02 + peak, HEAD_Z + HEAD + 0.045), skin)
    p.box((-0.03, -0.03, HEAD_Z + HEAD + 0.045), (0.03, 0.03, HEAD_Z + HEAD + 0.06), dark)                # button
    p.box((-h - 0.015, -h - 0.015, HEAD_Z + HEAD * 0.8), (h + 0.015, h - 0.02 + peak, HEAD_Z + HEAD * 0.85), dark)  # band
    p.box((-0.15, h - 0.02 + peak, HEAD_Z + HEAD * 0.8), (0.15, h + 0.11 + peak, HEAD_Z + HEAD * 0.8 + 0.025), dark)  # peak
    if headset:
        p.box((-h - 0.03, -0.035, HEAD_Z + HEAD * 0.7), (h + 0.03, 0.035, HEAD_Z + HEAD + 0.07), "t_black")
        c_headset(p)
    b.finish(p, "Hat__" + name, "Neck")


def c_rig(b, name, skin, dark):
    """The scavs' (and raiders') chest rig: a front panel, three pouches with flaps and buckles, straps."""
    d = TORSO_D / 2
    p = b.part().box((-0.26, d, CHEST_Z + 0.08), (0.26, d + 0.045, CHEST_Z + 0.32), skin)
    p.box((-0.26, d + 0.045, CHEST_Z + 0.08), (0.26, d + 0.05, CHEST_Z + 0.1), dark)                       # webbing
    for cx in (-0.17, 0.0, 0.17):
        p.box((cx - 0.065, d + 0.05, CHEST_Z + 0.1), (cx + 0.065, d + 0.095, CHEST_Z + 0.23), skin)
        p.box((cx - 0.07, d + 0.05, CHEST_Z + 0.23), (cx + 0.07, d + 0.1, CHEST_Z + 0.28), dark)            # flap
        p.box((cx - 0.015, d + 0.095, CHEST_Z + 0.2), (cx + 0.015, d + 0.1, CHEST_Z + 0.24), "t_black_dk")  # buckle
    for sx in (-1, 1):
        x0, x1 = sx * 0.1, sx * 0.18
        p.box((x0, d, CHEST_Z + 0.32), (x1, d + 0.03, SHOULDER_Z + 0.01), dark)
        p.box((x0, -d - 0.02, SHOULDER_Z - 0.02), (x1, d + 0.03, SHOULDER_Z + 0.02), dark)
        p.box((x0, -d - 0.02, CHEST_Z + 0.08), (x1, -d, SHOULDER_Z + 0.01), dark)
    b.finish(p, "Vest__" + name, "Spine")


def build_scav(b):
    cargo = ("belt", "pockets")
    c_legs(b, {
        "track_black": ("t_track", "t_black_dk", ("cord", "stripe")),
        "track_blue": ("c_track_blue", "c_track_blue_dk", ("cord", "stripe")),
        "jeans": ("t_denim", "t_denim_dk", ("belt", "cuff")), "cargo_olive": ("c_cargo", "c_cargo_dk", cargo),
        "woodland": ("c_woodland", "c_jacket_olive_dk", cargo),
    }, {"sneaker_white": ("t_sneaker", "c_sneaker_dark", "t_white_dk"),
        "sneaker_dark": ("c_sneaker_dark", "t_sneaker", "t_white"),
        "boot_brown": ("t_boot_brown", "t_sole", "t_leather_dk"), "boot_black": ("t_boot_black", "t_sole", "t_black_dk")})
    c_tops(b, {
        "tracksuit_blue": ("c_track_blue", "c_track_blue_dk", ("zip", "stripe")),
        "tracksuit_black": ("t_track", "t_black_dk", ("zip", "stripe")),
        "jacket_olive": ("c_jacket_olive", "c_jacket_olive_dk", ("collar", "buttons", "pockets", "cuffs")),
        "woodland": ("c_woodland", "c_jacket_olive_dk", ("collar", "buttons", "pockets", "cuffs")),
        "hoodie_grey": ("c_hoodie", "c_hoodie_dk", ("hood", "cuffs")),
        "leather": ("t_leather", "t_leather_dk", ("collar", "zip", "cuffs")),
    })
    c_gloves(b, {"black": ("t_black", "t_black_dk"), "brown": ("t_leather", "t_leather_dk"),
                 "olive": ("c_glove_olive", "c_canvas_olive_dk")})
    c_heads(b, {
        "balaclava_black": ("balaclava", "c_knit_black", "t_skin_pale"),
        "balaclava_olive": ("balaclava", "c_knit_olive", "t_skin_tan"),
        "pale": ("face", "t_skin_pale", "t_hair_dark"), "tan_beard": ("beard", "t_skin_tan", "t_hair_brown"),
        "dark": ("face", "t_skin_dark", "t_hair_black"), "pale_beard": ("beard", "t_skin_pale", "t_hair_brown"),
    })
    h = HEAD / 2
    for option, skin, dark in (("beanie_black", "c_knit_black", "t_black_dk"), ("beanie_olive", "c_knit_olive", "c_canvas_olive_dk")):
        p = b.part().box((-h - 0.015, -h - 0.015, HEAD_Z + HEAD * 0.8), (h + 0.015, h + 0.015, HEAD_Z + HEAD + 0.05), skin)
        p.box((-h - 0.02, -h - 0.02, HEAD_Z + HEAD * 0.72), (h + 0.02, h + 0.02, HEAD_Z + HEAD * 0.82), skin)   # turn-up
        p.box((-0.07, -0.07, HEAD_Z + HEAD + 0.05), (0.07, 0.07, HEAD_Z + HEAD + 0.07), dark)
        b.finish(p, "Hat__" + option, "Neck")
    c_cap(b, "cap_sand", "c_cap_sand", "c_cap_sand_dk", h, peak=0.015)
    c_cap(b, "cap_red", "c_cap_red", "c_cap_red_dk", h, peak=0.015)
    p = b.part().box((-h - 0.025, -h - 0.025, HEAD_Z + HEAD * 0.84), (h + 0.025, h + 0.025, HEAD_Z + HEAD + 0.07), "t_fur")
    p.box((-h + 0.01, -h + 0.01, HEAD_Z + HEAD + 0.07), (h - 0.01, h - 0.01, HEAD_Z + HEAD + 0.09), "t_leather_dk")
    p.box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.8), (h + 0.03, h + 0.025, HEAD_Z + HEAD * 0.94), "t_fur")   # brim
    p.box((-0.025, h + 0.025, HEAD_Z + HEAD * 0.85), (0.025, h + 0.03, HEAD_Z + HEAD * 0.91), "t_brass")      # badge
    for sx in (-1, 1):
        p.box((sx * h, -0.11, HEAD_Z + HEAD * 0.4), (sx * (h + 0.05), 0.11, HEAD_Z + HEAD * 0.9), "t_fur")
        p.box((sx * (h + 0.05), -0.01, HEAD_Z + HEAD * 0.4), (sx * (h + 0.05), 0.01, HEAD_Z + HEAD * 0.48), "t_leather_dk")
    b.finish(p, "Hat__ushanka", "Neck")
    p = b.part().box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.78), (h + 0.03, h + 0.03, HEAD_Z + HEAD + 0.05), "c_helmet_old")
    p.box((-h + 0.0, -h + 0.0, HEAD_Z + HEAD + 0.05), (h, h, HEAD_Z + HEAD + 0.08), "c_helmet_old")         # the dome
    p.box((-h - 0.06, -h - 0.06, HEAD_Z + HEAD * 0.72), (h + 0.06, h + 0.06, HEAD_Z + HEAD * 0.78), "c_helmet_old_dk")
    p.box((-h - 0.03, -h - 0.03, HEAD_Z + HEAD * 0.78), (h + 0.03, h + 0.03, HEAD_Z + HEAD * 0.8), "t_leather_dk")
    b.finish(p, "Hat__helmet_old", "Neck")
    b.empty("Hat__none", "Neck")
    c_rig(b, "rig_sand", "c_canvas_sand", "c_canvas_sand_dk")
    c_rig(b, "rig_olive", "c_canvas_olive", "c_canvas_olive_dk")
    b.empty("Vest__none", "Spine")


def build_pmc(b):
    pads = ("belt", "pads")
    c_legs(b, {
        "green": ("c_shirt_green", "c_shirt_green_dk", pads), "black": ("c_shirt_black", "c_shirt_black_dk", pads),
        "tan": ("c_shirt_tan", "c_shirt_tan_dk", pads), "multicam": ("c_multicam", "c_shirt_tan_dk", pads + ("pockets",)),
    }, {"tan": ("c_boot_tan", "t_sole", "t_tan_dk"), "coyote": ("c_boot_coyote", "t_sole", "t_leather_dk"),
        "black": ("t_boot_black", "t_sole", "t_black_dk")})
    shirt = ("zip", "patch", "cuffs")
    c_tops(b, {"green": ("c_shirt_green", "c_shirt_green_dk", shirt), "black": ("c_shirt_black", "c_shirt_black_dk", shirt),
               "tan": ("c_shirt_tan", "c_shirt_tan_dk", shirt), "multicam": ("c_multicam", "c_shirt_tan_dk", shirt)})
    c_gloves(b, {"black": ("t_black", "t_black_dk"), "tan": ("c_glove_tan", "t_tan_dk"),
                 "green": ("c_glove_olive", "c_canvas_olive_dk")})
    c_heads(b, {
        "pale": ("face", "t_skin_pale", "t_hair_dark"), "tan": ("face", "t_skin_tan", "t_hair_brown"),
        "dark": ("face", "t_skin_dark", "t_hair_black"), "pale_beard": ("beard", "t_skin_pale", "t_hair_brown"),
        "dark_beard": ("beard", "t_skin_dark", "t_hair_black"),
    })
    h = HEAD / 2
    for option, skin, dark in (("gaiter_tan", "c_knit_tan", "c_canvas_sand_dk"), ("gaiter_black", "c_knit_black", "t_black_dk"),
                               ("gaiter_green", "c_knit_green", "c_shirt_green_dk")):
        p = b.part().box((-h - 0.012, -h - 0.012, HEAD_Z - 0.01), (h + 0.012, h + 0.025, HEAD_Z + HEAD * 0.4), skin)
        p.box((-h - 0.012, -h - 0.012, HEAD_Z + HEAD * 0.4), (h + 0.012, h + 0.03, HEAD_Z + HEAD * 0.45), dark)   # fold
        b.finish(p, "Mask__" + option, "Neck")
    b.empty("Mask__none", "Neck")
    p = b.part().box((-0.16, h + 0.002, HEAD_Z + HEAD * 0.64), (0.16, h + 0.03, HEAD_Z + HEAD * 0.68), "t_black")
    for sx in (-1, 1):
        p.box((sx * 0.16, h + 0.002, HEAD_Z + HEAD * 0.5), (sx * 0.145, h + 0.03, HEAD_Z + HEAD * 0.64), "t_black")
        p.box((sx * 0.145, h + 0.012, HEAD_Z + HEAD * 0.5), (sx * 0.02, h + 0.024, HEAD_Z + HEAD * 0.64), "t_shades")
    p.box((-0.02, h + 0.002, HEAD_Z + HEAD * 0.56), (0.02, h + 0.03, HEAD_Z + HEAD * 0.64), "t_black")
    b.finish(p, "Eyes__glasses", "Neck")
    b.empty("Eyes__none", "Neck")
    for option, skin in (("helmet_tan", "c_helmet_tan"), ("helmet_green", "c_helmet_green"), ("helmet_black", "c_helmet_black")):
        p = b.part().box((-h - 0.035, -h - 0.035, HEAD_Z + HEAD * 0.8), (h + 0.035, h + 0.035, HEAD_Z + HEAD + 0.06), skin)
        p.box((-h - 0.005, -h - 0.005, HEAD_Z + HEAD + 0.06), (h + 0.005, h + 0.005, HEAD_Z + HEAD + 0.09), skin)  # dome
        p.box((-h - 0.035, -h - 0.035, HEAD_Z + HEAD * 0.74), (h + 0.035, h + 0.035, HEAD_Z + HEAD * 0.8), "t_black")  # edge
        p.box((-0.04, h + 0.035, HEAD_Z + HEAD * 0.86), (0.04, h + 0.065, HEAD_Z + HEAD * 1.02), "t_black")   # NVG mount
        p.box((-0.025, h + 0.06, HEAD_Z + HEAD * 0.9), (0.025, h + 0.065, HEAD_Z + HEAD * 0.98), "t_steel_dk")
        for sx in (-1, 1):
            p.box((sx * (h + 0.035), -0.1, HEAD_Z + HEAD * 0.8), (sx * (h + 0.05), 0.1, HEAD_Z + HEAD * 0.88), "t_black")
        c_headset(p)
        b.finish(p, "Hat__" + option, "Neck")
    c_cap(b, "cap_headset", "t_black", "t_black_dk", h, headset=True)
    d = TORSO_D / 2
    for option, skin, dark in (("tan", "c_carrier_tan", "c_carrier_tan_dk"), ("green", "c_carrier_green", "c_carrier_green_dk"),
                               ("black", "c_carrier_black", "c_carrier_black_dk")):
        p = b.part().box((-TORSO_W / 2 + 0.03, -d - 0.04, CHEST_Z + 0.06), (TORSO_W / 2 - 0.03, d + 0.035, SHOULDER_Z - 0.04), skin)
        for z in (CHEST_Z + 0.07, CHEST_Z + 0.27):                                                      # webbing rows
            p.box((-TORSO_W / 2 + 0.04, d + 0.035, z), (TORSO_W / 2 - 0.04, d + 0.04, z + 0.015), dark)
        for sx in (-1, 1):
            p.box((sx * 0.1, -d - 0.04, SHOULDER_Z - 0.05), (sx * 0.2, d + 0.04, SHOULDER_Z + 0.02), dark)   # straps
        for cx in (-0.16, 0.0, 0.16):                                                                   # mag pouches
            p.box((cx - 0.06, d + 0.035, CHEST_Z + 0.08), (cx + 0.06, d + 0.095, CHEST_Z + 0.21), skin)
            p.box((cx - 0.065, d + 0.035, CHEST_Z + 0.21), (cx + 0.065, d + 0.1, CHEST_Z + 0.25), dark)
        p.box((-0.1, d + 0.035, CHEST_Z + 0.27), (0.1, d + 0.075, CHEST_Z + 0.41), skin)                 # admin pouch
        p.box((-0.06, d + 0.075, CHEST_Z + 0.31), (0.06, d + 0.08, CHEST_Z + 0.39), dark)                 # its patch
        p.box((-0.17, -d - 0.085, CHEST_Z + 0.1), (0.17, -d - 0.04, CHEST_Z + 0.37), skin)                # back pouch
        p.box((-0.17, -d - 0.09, CHEST_Z + 0.37), (0.17, -d - 0.04, CHEST_Z + 0.42), dark)
        b.finish(p, "Vest__" + option, "Spine")
        p = b.part().box((-TORSO_W / 2 - 0.01, -d - 0.01, HIP_Z + 0.02), (TORSO_W / 2 + 0.01, d + 0.005, WAIST_Z + 0.06), dark)
        p.box((-0.05, d + 0.005, HIP_Z + 0.03), (0.05, d + 0.01, WAIST_Z + 0.05), "t_black_dk")           # buckle
        b.finish(p, "Vest__%s__Hips" % option, "Hips")                                                     # battle belt


def build_raider(b):
    pads = ("belt", "pads")
    c_legs(b, {"black": ("c_raider", "c_raider_dk", pads), "urban": ("c_urban", "c_raider_dk", pads + ("pockets",)),
               "olive": ("c_shirt_green", "c_shirt_green_dk", pads)},
           {"black": ("t_boot_black", "t_sole", "t_black_dk"), "brown": ("t_boot_brown", "t_sole", "t_leather_dk")})
    c_tops(b, {"black": ("c_raider", "c_raider_dk", ("armband", "collar", "zip", "cuffs")),
               "urban": ("c_urban", "c_raider_dk", ("armband", "zip", "cuffs")),
               "rust": ("c_rust", "c_rust_dk", ("armband", "collar", "buttons", "pockets", "cuffs")),
               "hoodie_black": ("c_raider", "c_raider_dk", ("armband", "hood", "cuffs"))})
    c_gloves(b, {"black": ("t_black", "t_black_dk"), "brown": ("t_leather", "t_leather_dk")})
    c_heads(b, {
        "skull": ("skull", "c_knit_black", "c_bone"), "gasmask": ("gasmask", "c_knit_black", "c_heavy_olive"),
        "balaclava_black": ("balaclava", "c_knit_black", "t_skin_pale"),
        "balaclava_rust": ("balaclava", "c_knit_rust", "t_skin_tan"),
    })
    h = HEAD / 2
    for option, skin in (("altyn", "c_altyn"), ("altyn_black", "c_altyn_black")):
        p = b.part().box((-h - 0.04, -h - 0.04, HEAD_Z + HEAD * 0.78), (h + 0.04, h + 0.04, HEAD_Z + HEAD + 0.07), skin)
        p.box((-h - 0.01, -h - 0.01, HEAD_Z + HEAD + 0.07), (h + 0.01, h + 0.01, HEAD_Z + HEAD + 0.1), skin)
        p.box((-h - 0.04, -h - 0.04, HEAD_Z + HEAD * 0.74), (h + 0.04, h + 0.04, HEAD_Z + HEAD * 0.78), "t_black")
        p.box((-h - 0.05, -h - 0.05, HEAD_Z + HEAD * 0.35), (h + 0.05, h - 0.06, HEAD_Z + HEAD * 0.78), skin)
        for sx in (-1, 1):                                             # bolts
            p.box((sx * (h + 0.04), 0.0, HEAD_Z + HEAD * 0.58), (sx * (h + 0.05), h - 0.06, HEAD_Z + HEAD * 0.66), "t_steel_dk")
        p.box((-h + 0.02, h + 0.02, HEAD_Z + HEAD * 0.35), (h - 0.02, h + 0.06, HEAD_Z + HEAD * 0.78), "t_black")  # frame
        p.box((-h + 0.04, h + 0.06, HEAD_Z + HEAD * 0.38), (h - 0.04, h + 0.062, HEAD_Z + HEAD * 0.75), "c_visor")
        p.box((-0.15, h + 0.062, HEAD_Z + HEAD * 0.56), (0.15, h + 0.065, HEAD_Z + HEAD * 0.64), "t_black_dk")    # slit
        b.finish(p, "Hat__" + option, "Neck")
    p = b.part().box((-h - 0.03, -h - 0.05, HEAD_Z + HEAD * 0.15), (h + 0.03, h - 0.03, HEAD_Z + HEAD + 0.07), "c_raider")
    p.box((-h - 0.03, -h - 0.05, HEAD_Z + HEAD + 0.05), (h + 0.03, -h + 0.05, HEAD_Z + HEAD + 0.07), "c_raider_dk")
    b.finish(p, "Hat__hood", "Neck")
    p = b.part().box((-h - 0.015, -h - 0.02, HEAD_Z + HEAD * 0.82), (h + 0.015, h + 0.015, HEAD_Z + HEAD + 0.05), "c_armband")
    p.box((-h - 0.015, -h - 0.02, HEAD_Z + HEAD * 0.82), (h + 0.015, h + 0.015, HEAD_Z + HEAD * 0.86), "t_red")
    p.box((-0.05, -h - 0.05, HEAD_Z + HEAD * 0.8), (0.05, -h - 0.02, HEAD_Z + HEAD * 0.95), "t_red")          # knot
    b.finish(p, "Hat__bandana", "Neck")
    b.empty("Hat__none", "Neck")
    d = TORSO_D / 2
    for option, skin, dark in (("heavy_black", "c_heavy_black", "t_black_dk"), ("heavy_olive", "c_heavy_olive", "c_heavy_olive_dk")):
        p = b.part().box((-TORSO_W / 2 + 0.02, -d - 0.05, CHEST_Z + 0.04), (TORSO_W / 2 - 0.02, d + 0.045, SHOULDER_Z - 0.02), skin)
        p.box((-TORSO_W / 2 + 0.02, -d - 0.05, CHEST_Z + 0.04), (TORSO_W / 2 - 0.02, d + 0.05, CHEST_Z + 0.07), dark)   # trim
        p.box((-0.24, -d - 0.04, SHOULDER_Z - 0.04), (0.24, d - 0.06, SHOULDER_Z + 0.06), dark)          # neck guard
        for cx in (-0.17, 0.0, 0.17):
            p.box((cx - 0.065, d + 0.045, CHEST_Z + 0.08), (cx + 0.065, d + 0.115, CHEST_Z + 0.21), skin)
            p.box((cx - 0.07, d + 0.045, CHEST_Z + 0.21), (cx + 0.07, d + 0.12, CHEST_Z + 0.26), dark)
        p.box((-0.18, d + 0.045, CHEST_Z + 0.3), (0.18, d + 0.05, SHOULDER_Z - 0.08), dark)                # the plate
        b.finish(p, "Vest__" + option, "Spine")
        for side, sx in (("L", -1), ("R", 1)):
            cx = sx * ARM_X
            a = ARM_W / 2 + 0.04
            p = b.part().box((cx - a, -a, ARM_Z - 0.1), (cx + a, a, ARM_Z + ARM_W / 2 + 0.04), skin)    # shoulder armor
            p.box((cx - a - 0.005, -a - 0.005, ARM_Z - 0.1), (cx + a + 0.005, a + 0.005, ARM_Z - 0.07), dark)
            b.finish(p, "Vest__%s__Arm%s" % (option, side), "Arm" + side)
        p = b.part().box((-0.14, d - 0.02, HIP_Z - 0.16), (0.14, d + 0.035, WAIST_Z), skin)               # groin flap
        p.box((-0.14, d + 0.035, HIP_Z - 0.16), (0.14, d + 0.04, HIP_Z - 0.13), dark)
        p.box((-TORSO_W / 2 - 0.01, -d - 0.01, HIP_Z + 0.02), (TORSO_W / 2 + 0.01, d + 0.01, WAIST_Z + 0.06), dark)
        b.finish(p, "Vest__%s__Hips" % option, "Hips")
    c_rig(b, "rig_black", "c_canvas_black", "c_canvas_black_dk")


BUILDERS = {"scav": build_scav, "pmc": build_pmc, "raider": build_raider, "trader": build_trader}


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
        grow = HEAD_SCALE if joint == "Neck" else 1.0
        node = {"name": name}
        if part is not None:
            pos, nrm, uv, idx = [], [], [], []
            for corners, n, uvs in part.quads:
                base = len(pos)
                for c, t in zip(corners, uvs):
                    pos.append(gl(tuple(v * grow for v in mb.v_sub(c, origin))))
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
    # The gun's place (body_pose.gd moves it every frame): the grip at the right shoulder, the barrel along -z.
    nodes.append({"name": "Gun", "translation": [0.17, 1.13, -0.26], "children": [len(nodes) + 1]})
    nodes.append({"name": "Muzzle", "translation": [0.0, 0.085, -0.63]})
    image = {"bufferView": add_view(png), "mimeType": "image/png", "name": body.name}
    gltf = {"asset": {"version": "2.0", "generator": "Bloxov make_character.py"}, "scene": 0,
            "scenes": [{"nodes": [index["Hips"], len(nodes) - 2]}], "nodes": nodes, "meshes": meshes,
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
    global PX_PER_M, TILE, ATLAS, COLS
    for name in names:
        # Every character is drawn at twice the pixels (clean, 2026-11-09: the traders first, then the raid's).
        PX_PER_M, TILE, ATLAS = 32, 32, 256
        COLS = ATLAS // TILE
        body = Body(name)
        BUILDERS[name](body)
        tex = os.path.join(ROOT, "art_source", "textures", name + ".png")
        px = body.atlas.paint()
        rows = list(reversed(px))   # write_png takes rows bottom-first
        mb.write_png(tex, ATLAS, ATLAS, rows)
        with open(tex, "rb") as f:
            png = f.read()
        path = os.path.join(out_dir or os.path.join(ROOT, "assets", "models", "characters"), name + ".glb")
        write_glb(path, body, png)
        print("%s: %d parts, %d triangles at most showing, %d tiles -> %s"
              % (name, len(body.parts), shown_tris(body), len(body.atlas.tiles), path))


if __name__ == "__main__":
    main()
