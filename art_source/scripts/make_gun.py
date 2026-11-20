"""Bloxov guns (0.18 art pass): the five guns and their attachments as separate models.

The same model is used in first person (scripts/gun_view_models.gd) and in the hands of scavs, Raiders and other players
(scripts/held_gun.gd), so the guns are life size. Every gun has LOOKS ("a", "b", "c": option sheets for the owner); the
game uses the one in PICKED, written to assets/models/guns/<gun>.glb. Other looks go to <gun>_<look>.glb only when
asked for on the command line (they're for the option sheets, not committed).

Run: python3 art_source/scripts/make_gun.py            (the picked looks + attachments)
     python3 art_source/scripts/make_gun.py all        (also every look, as <gun>_<look>.glb)
No Blender needed (the .glb is written directly, like make_loot.py). Textures: art_source/textures/guns/, 64 px per
meter (seen up close), Bloxov palette.

Model frame (Godot axes): barrel along -z, up +y, origin where the old box model's middle was, so first person keeps its
places. Nodes in each gun .glb:
  Body      the gun                          Mag   the magazine, its origin at the top (an extended mag stretches it)
  Bolt      what's racked on a reload: the charging/cocking handle, the pistol's slide, the Lancer's bolt
  Irons     the iron sights (hidden while an optic is on, so the two never show together)
  Muzzle    where shots and the flash leave  Grip  where the right hand holds it (third person)
  Sight     the iron sights' line (aiming puts it through the middle of the screen)
  Optic     where an optic's base sits       Fore  where a foregrip clamps on (guns with a grip slot)
Attachments (att_<id>.glb): Body, origin at the base (optics: underside; barrel parts: back end; foregrip: clamp top),
Line on optics (their sight line, above the base) and End on barrel parts (where the muzzle moves to).
"""
import math
import os
import random
import struct
import json
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
from make_building import Builder, Canvas, Texture, uv_world, uv_fit  # noqa: E402

mb.REGENERATE_TEXTURES = True          # painted from fixed seeds, so they come out the same every run
mb.PALETTE.update({"tan": "9a855c", "tan_dark": "7c6a48", "tan_light": "ad9a70", "brass": "b08a3a",
                   "lens": "2b4a5e", "lens_light": "6f9db5", "lens_dark": "1c3140", "glass": "a9c8d6", "gun_red": "8c2f25"})

PICKED = {"hound": "a", "stinger": "c", "wasp": "a", "mauler": "a", "lancer": "c", "reaper": "k",   # owner, 2026-10-23 (Reaper k: 2026-11-16)
          "viper": "a", "hornet": "a", "brawler": "a", "talon": "a"}   # (0.36.42: one look each)
TILE = 0.5                              # 32 px textures over 0.5 m = 64 px per meter
OUT = os.path.join(mb.ROOT, "assets", "models", "guns")


# ------------------------------------------------------------------------------------------------ textures
def _tex(base, specks=(), scratches=(), size=32):
    def paint(rng):
        c = Canvas(size, size, base)
        for col, chance in specks:
            c.noise(0, 0, size, size, [col], chance, rng)
        for col in scratches:
            c.blotch([col], 3, rng, size=(2, 3))
        return c
    return paint


def _grain(base, dark, light):
    def paint(rng):
        c = Canvas(32, 32, base)
        for y in range(32):                     # grain runs along the gun (u = length on the sides)
            if rng.random() < 0.5:
                x, run = rng.randrange(32), rng.randrange(8, 30)
                for k in range(run):
                    c.put((x + k) % 32, y + (1 if rng.random() < 0.12 else 0), dark)
        c.noise(0, 0, 32, 32, [light], 0.03, rng)
        return c
    return paint


def _rows(base, line, every=4, width=2):
    def paint(rng):
        c = Canvas(32, 32, base)
        for y in range(0, 32, every):
            c.rect(0, y, 32, y + width, line)
        return c
    return paint


def _lens(rng):
    c = Canvas(16, 16, "lens")
    for y in range(16):                     # darker towards the bottom, a soft glint top left
        for x in range(16):
            if (x - 5) ** 2 + (y - 11) ** 2 < 10:
                c.put(x, y, "lens_light")
            elif y < 5:
                c.put(x, y, "lens_dark")
    return c


def _tape(rng):
    c = Canvas(32, 32, "olive")
    for x in range(0, 32, 6):
        c.rect(x, 0, x + 1, 32, "olive_dark")       # wrap edges across the length
    c.noise(0, 0, 32, 32, ["olive_light"], 0.06, rng)
    return c


MATS = {
    "blued": _tex("iron_dark", (("black", 0.05), ("iron", 0.025))),
    "black": _tex("black", (("iron_dark", 0.07),)),
    "park": _tex("iron", (("iron_dark", 0.09), ("steel", 0.02))),
    "worn": _tex("iron", (("iron_dark", 0.08), ("rust", 0.03)), ("rust",)),
    "steel": _tex("steel", (("steel_light", 0.06), ("iron", 0.04))),
    "wood": _grain("wood_mid", "wood_dark", "wood"),
    "wood_red": _grain("rust", "wood_dark", "wood_mid"),
    "wood_light": _grain("wood", "wood_mid", "wood_light"),
    "olive": _tex("olive", (("olive_dark", 0.07), ("olive_light", 0.02))),
    "olive_dark": _tex("olive_dark", (("black", 0.05), ("olive", 0.03))),
    "tan": _tex("tan", (("tan_dark", 0.07), ("tan_light", 0.03))),
    "bakelite": _tex("gun_red", (("rust", 0.08), ("wood_dark", 0.03))),
    "rail": _rows("black", "iron", 4, 2),
    "stipple": _tex("black", (("iron_dark", 0.3),)),
    "shell": _tex("red", (("gun_red", 0.1),)),
    "brass": _tex("brass", (("yellow_dark", 0.12),)),
    "tape": _tape,
    "lens": _lens,
    "glass": _tex("glass"),
    "dot": _tex("bone"),
}
FIT = {"lens", "glass"}                 # these show their whole image on each face
SEE_THROUGH = {"glass": 0.18}           # alpha-blended (a red dot's window: the HUD draws the dot)


# ------------------------------------------------------------------------------------------------ geometry
class Model:
    """A gun or attachment: named mesh parts (each with its own origin) and marker empties, in the gun frame."""

    def __init__(self, name):
        self.name = name
        self.parts = {"Body": [Builder(), (0.0, 0.0, 0.0)], "Irons": [Builder(), (0.0, 0.0, 0.0)]}
        self.marks = {}

    def part(self, name, origin):
        self.parts[name] = [Builder(), tuple(origin)]

    def mark(self, name, pos):
        self.marks[name] = tuple(pos)

    def _b(self, part):
        return self.parts[part][0]

    @staticmethod
    def _uv(mat):
        return uv_fit((0.0, 0.0, 1.0, 1.0)) if mat in FIT else uv_world(TILE)

    def box(self, c, s, mat, yaw=0.0, pitch=0.0, part="Body", ends=None):
        """ends: material for the faces looking along z (a lens on a tube end, a shell's brass)."""
        def style(n, m, q):
            if ends and abs(n[2]) > 0.7:
                return ends, self._uv(ends)
            return mat, self._uv(mat)
        self._b(part).box(c, s, yaw=yaw, pitch=pitch, style=style)

    def prism(self, profile, hw, mat, x=0.0, part="Body"):
        """Side profile [(z, y), ...] (convex, in order) pushed out to +-hw across x."""
        b = self._b(part)
        cz = sum(p[0] for p in profile) / len(profile)
        cy = sum(p[1] for p in profile) / len(profile)
        for i, (z0, y0) in enumerate(profile):
            z1, y1 = profile[(i + 1) % len(profile)]
            n = (0.0, -(z1 - z0), (y1 - y0))
            mz, my = (z0 + z1) / 2 - cz, (y0 + y1) / 2 - cy
            if n[1] * my + n[2] * mz < 0:
                n = (0.0, -n[1], -n[2])
            pts = [(x - hw, y0, z0), (x + hw, y0, z0), (x + hw, y1, z1), (x - hw, y1, z1)]
            b.poly(pts, mb.norm(n), mat, self._uv(mat))
        for sx in (-1, 1):
            b.poly([(x + sx * hw, y, z) for z, y in profile], (sx, 0, 0), mat, self._uv(mat))

    def tube(self, x, y, z0, z1, r, mat, sides=8, part="Body", ends=None):
        """A round-ish tube along z (flat sides, flat on top)."""
        b = self._b(part)
        a0 = 90 + 180 / sides
        ring = [(x + r * math.cos(math.radians(a0 + 360 * k / sides)),
                 y + r * math.sin(math.radians(a0 + 360 * k / sides))) for k in range(sides)]
        for i in range(sides):
            (xa, ya), (xb, yb) = ring[i], ring[(i + 1) % sides]
            n = mb.norm(((xa + xb) / 2 - x, (ya + yb) / 2 - y, 0.0))
            b.poly([(xa, ya, z0), (xb, yb, z0), (xb, yb, z1), (xa, ya, z1)], n, mat, self._uv(mat))
        for z, sz in ((z0, -1), (z1, 1)):
            e = ends or mat
            b.poly([(px, py, z) for px, py in ring], (0, 0, sz if z1 > z0 else -sz), e, self._uv(e))

    def ytube(self, x, z, y0, y1, r, mat, sides=8, part="Body"):
        """A round-ish post standing up (turret caps, knobs)."""
        b = self._b(part)
        ring = [(x + r * math.cos(math.radians(22.5 + 360 * k / sides)),
                 z + r * math.sin(math.radians(22.5 + 360 * k / sides))) for k in range(sides)]
        for i in range(sides):
            (xa, za), (xb, zb) = ring[i], ring[(i + 1) % sides]
            n = mb.norm(((xa + xb) / 2 - x, 0.0, (za + zb) / 2 - z))
            b.poly([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], n, mat, self._uv(mat))
        b.poly([(px, y1, pz) for px, pz in ring], (0, 1, 0), mat, self._uv(mat))
        b.poly([(px, y0, pz) for px, pz in ring], (0, -1, 0), mat, self._uv(mat))

    def ring(self, x, y, z, inner, bar, depth, mat, part="Body"):
        """A square ring round the line (x, y) with chamfered corners: an aperture, a sight hood, a red dot's window."""
        o = inner + bar
        for sx in (-1, 1):
            self.box((x + sx * (inner + bar / 2), y, z), (bar, inner * 1.4, depth), mat, part=part)       # sides
            self.box((x, y + sx * (inner + bar / 2), z), (inner * 1.4, bar, depth), mat, part=part)       # top, bottom
            for sy in (-1, 1):                                                                             # corners
                self.box((x + sx * (o - bar * 1.1), y + sy * (o - bar * 1.1), z), (bar * 1.6, bar * 1.6, depth),
                         mat, part=part)

    def notch(self, z, base_top, sight, mat, width=0.03, gap=0.009, depth=0.01, dots=False, base_w=None, floor_drop=0.007,
              part="Irons"):
        """A rear sight: a block up from base_top, two ears either side of a square notch whose floor is just under
        the sight line (the front post's tip sits level with the ear tops, in the notch)."""
        floor = sight - floor_drop
        if floor > base_top:
            self.box((0, (base_top + floor) / 2, z), (base_w or width, floor - base_top, depth), mat, part=part)
        ear = (width - gap) / 2
        for sx in (-1, 1):
            self.box((sx * (gap + ear) / 2, (floor + sight) / 2, z), (ear, sight - floor, depth), mat, part=part)
            if dots:
                self.box((sx * (gap + ear) / 2, sight - 0.0035, z + depth / 2 + 0.0005), (0.003, 0.003, 0.001), "dot",
                         part=part)

    def post(self, z, base_top, sight, mat, guard="ears", width=0.005, base_w=0.02, dot=True, hood=0.0095, part="Irons"):
        """A front sight: a base block, a thin post to the sight line (a light dot on its back), and ears or a round hood
        round it so it reads in the notch."""
        stem = sight - 0.012
        if stem > base_top:
            self.box((0, (base_top + stem) / 2, z), (base_w, stem - base_top, 0.012), mat, part=part)
        self.box((0, (stem + sight) / 2, z), (width, sight - stem, 0.006), mat, part=part)
        if dot:
            self.box((0, sight - 0.003, z + 0.0035), (0.003, 0.003, 0.001), "dot", part=part)
        if guard == "ears":
            for sx in (-1, 1):
                self.box((sx * 0.012, (stem + sight + 0.003) / 2, z), (0.004, sight + 0.003 - stem, 0.012), mat, part=part)
        elif guard == "hood":
            self.ring(0, sight - 0.004 + (0.0095 - hood), z, hood, 0.0025, 0.014, mat, part=part)

    def curved(self, top, w, d, seg, angles, mat, part="Body"):
        """A curved magazine: boxes hanging from `top`, each tipped forward by its angle (degrees)."""
        p = top
        for a in angles:
            half = mb.rot((0.0, -seg / 2, 0.0), 0.0, a)
            self.box(mb.v_add(p, half), (w, seg * 1.12, d), mat, pitch=a, part=part)
            p = mb.v_add(p, mb.v_scale(half, 2.0))
        return p

    def tris(self):
        return sum(len(f) - 2 for b, _ in self.parts.values() for f in b.faces)


# ------------------------------------------------------------------------------------------------ the guns
def hound(m, look):
    """The Hound (AK): A wood and blued steel, B black polymer with rails, C a worn scav gun with taped furniture."""
    metal = {"a": "blued", "b": "black", "c": "worn"}[look]
    furn = {"a": "wood_red", "b": "black", "c": "wood"}[look]
    grip = {"a": "bakelite", "b": "stipple", "c": "black"}[look]
    mag = {"a": "bakelite", "b": "black", "c": "park"}[look]
    m.box((0, 0, 0), (0.066, 0.09, 0.36), metal)                                  # receiver
    m.box((0, 0.051, 0.0), (0.06, 0.013, 0.33), metal)                            # dust cover
    m.box((0, 0, -0.2), (0.068, 0.082, 0.04), metal)                              # trunnion
    m.box((0, 0.066, -0.205), (0.05, 0.022, 0.07), metal)                         # rear sight block
    m.box((0, 0.079, -0.2), (0.026, 0.004, 0.05), metal, part="Irons")            # tangent leaf
    m.notch(-0.18, 0.077, 0.089, metal, width=0.026)
    m.box((0, 0.05, -0.31), (0.05, 0.032, 0.2), furn)                             # upper handguard (gas tube)
    m.box((0, -0.005, -0.3), (0.07, 0.066, 0.18), furn)                           # lower handguard
    m.box((0, -0.005, -0.395), (0.072, 0.068, 0.012), metal)                      # handguard cap
    m.box((0, 0.042, -0.425), (0.032, 0.036, 0.03), metal)                        # gas block
    m.box((0, 0.01, -0.45), (0.026, 0.026, 0.13), metal)                          # barrel
    m.box((0, 0.03, -0.47), (0.03, 0.04, 0.035), metal)                           # front sight block
    m.post(-0.47, 0.05, 0.089, metal)                                             # front post in its ears
    m.box((0, 0.01, -0.535), (0.034, 0.034, 0.045), metal)                        # muzzle brake
    m.box((0, -0.09, 0.075), (0.034, 0.1, 0.048), grip, pitch=-18)                # pistol grip
    m.box((0, -0.06, 0.02), (0.012, 0.006, 0.09), metal)                          # trigger guard
    m.box((0, -0.053, -0.025), (0.012, 0.016, 0.006), metal)
    m.box((0, -0.052, 0.015), (0.006, 0.016, 0.006), metal)                       # trigger
    m.part("Bolt", (0.044, 0.02, -0.1))                                           # (racked in first person)
    m.box((0.044, 0.02, -0.1), (0.024, 0.012, 0.014), "steel", part="Bolt")       # charging handle
    m.box((0.035, 0.024, 0.04), (0.004, 0.02, 0.14), metal)                       # selector lever
    stock = [(0.175, 0.035), (0.175, -0.045), (0.40, -0.085), (0.40, 0.0)]
    m.prism(stock, 0.026, furn)
    m.box((0, -0.042, 0.405), (0.054, 0.09, 0.012), metal)                        # butt plate
    m.part("Mag", (0, -0.045, -0.07))
    m.curved((0, -0.045, -0.07), 0.03, 0.075, 0.055, (8, 18, 28), mag, part="Mag")
    m.mark("Optic", (0, 0.0575, 0.01))
    if look == "b":
        m.box((0, 0.064, 0.01), (0.03, 0.013, 0.22), "rail")                      # top rail on the cover
        m.mark("Optic", (0, 0.0705, 0.01))
        for x in (-0.037, 0.037):
            m.box((x, -0.005, -0.3), (0.006, 0.02, 0.15), "rail")                 # side rails
        m.box((0, -0.04, -0.3), (0.025, 0.006, 0.15), "rail")                     # bottom rail
        m.box((0, 0.025, 0.29), (0.05, 0.025, 0.1), furn)                         # cheek riser
        for k in range(3):                                                        # mag ribs
            m.box((0, -0.012 - k * 0.012, 0.0), (0.034, 0.004, 0.077), "black", pitch=6 + k * 4, part="Mag")
    if look == "c":
        for z in (-0.25, -0.34):
            m.box((0, -0.005, z), (0.076, 0.072, 0.03), "tape")                   # taped handguard
        m.box((0, 0.05, -0.29), (0.056, 0.038, 0.03), "tape")
        m.box((0, -0.06, -0.081), (0.036, 0.024, 0.08), "tape", pitch=10, part="Mag")
        m.box((0, -0.05, 0.36), (0.054, 0.006, 0.02), "black")                    # sling loop
    m.mark("Muzzle", (0, 0.01, -0.56))
    m.mark("Grip", (0, -0.075, 0.07))
    m.mark("Sight", (0, 0.089, 0))
    m.mark("Fore", (0, -0.038 - (0.006 if look == "b" else 0.0), -0.3))


def stinger(m, look):
    """The Stinger (pistol): A black polymer, B steel slide with wood grips, C tan frame and black slide."""
    slide = {"a": "black", "b": "steel", "c": "black"}[look]
    frame = {"a": "black", "b": "steel", "c": "tan"}[look]
    grip = {"a": "stipple", "b": "wood", "c": "tan"}[look]
    m.part("Bolt", (0, 0.012, 0.0))                                               # the slide (racked in first person)
    m.box((0, 0.012, 0.0), (0.032, 0.035, 0.19), slide, part="Bolt")              # slide
    for k in range(5):                                                            # rear serrations
        m.box((0, 0.012, 0.06 + k * 0.007), (0.0335, 0.03, 0.003), "black" if slide != "black" else "park", part="Bolt")
    m.box((0, 0.02, -0.03), (0.0335, 0.01, 0.028), "black", part="Bolt")          # ejection port
    m.notch(0.085, 0.0295, 0.0355, "black", width=0.028, gap=0.008, dots=True)    # three-dot sights
    m.post(-0.085, 0.0295, 0.0355, "black", guard=None, width=0.006, base_w=0.008)
    m.box((0, 0.012, -0.096), (0.014, 0.014, 0.004), "blued")  # barrel end
    m.box((0, -0.017, -0.01), (0.03, 0.025, 0.17), frame)                         # frame
    m.box((0, -0.075, 0.06), (0.03, 0.105, 0.045), grip, pitch=-16)               # grip
    if grip != frame:                                                             # the grip frame round the panels
        m.box((0, -0.075, 0.06), (0.024, 0.107, 0.047), frame, pitch=-16)
    m.box((0, -0.04, -0.012), (0.01, 0.006, 0.06), frame)                         # trigger guard
    m.box((0, -0.034, -0.04), (0.01, 0.016, 0.006), frame)
    m.box((0, -0.031, -0.004), (0.006, 0.016, 0.006), "blued")                    # trigger
    if look == "b":
        m.box((0, 0.02, 0.1), (0.012, 0.018, 0.01), "steel", pitch=-30)           # hammer
    if look in ("a", "c"):
        m.box((0, -0.034, -0.065), (0.022, 0.006, 0.04), "rail")                  # accessory rail
    m.part("Mag", (0, -0.12, 0.072))
    m.box((0, -0.124, 0.074), (0.032, 0.008, 0.05), "black", pitch=-16, part="Mag")  # base plate
    m.mark("Muzzle", (0, 0.012, -0.1))
    m.mark("Grip", (0, -0.06, 0.055))
    m.mark("Sight", (0, 0.0355, 0))
    m.mark("Optic", (0, 0.0295, 0.03))


def wasp(m, look):
    """The Wasp (SMG): A classic roller-delay SMG with struts, B a boxy one with the mag in the grip, C a modern olive one."""
    if look == "a":
        m.box((0, 0.0, 0.0), (0.054, 0.068, 0.3), "black")                        # receiver tube
        m.box((0, 0.042, 0.0), (0.03, 0.016, 0.26), "black")                      # top ridge
        m.box((0, 0.058, 0.13), (0.03, 0.018, 0.03), "black")                     # rear drum
        m.box((0, 0.069, 0.13), (0.012, 0.006, 0.012), "black", part="Irons")
        m.ring(0, 0.08, 0.13, 0.0075, 0.003, 0.01, "black", part="Irons")         # its aperture
        m.box((0, 0.033, -0.17), (0.016, 0.05, 0.02), "black")                    # front sight tower
        m.post(-0.17, 0.058, 0.08, "black", guard="hood")
        m.box((0, -0.012, -0.18), (0.054, 0.05, 0.12), "stipple")                 # slim handguard
        m.box((0, -0.012, -0.245), (0.044, 0.04, 0.012), "black")                 # its front cap
        m.tube(0, 0.008, -0.25, -0.3, 0.009, "black")                             # barrel
        for z in (-0.27, -0.285):
            m.tube(0, 0.008, z, z - 0.005, 0.012, "black")                        # barrel lugs
        m.part("Bolt", (0.033, 0.03, -0.11))
        m.box((0.033, 0.03, -0.11), (0.012, 0.012, 0.04), "steel", part="Bolt")   # cocking handle
        m.box((0, -0.075, 0.09), (0.034, 0.09, 0.046), "stipple", pitch=-12)      # grip
        m.box((0, -0.04, 0.06), (0.04, 0.03, 0.09), "black")                      # trigger group
        m.box((0, -0.055, 0.04), (0.01, 0.006, 0.05), "black")                    # guard
        for x in (-0.022, 0.022):
            m.box((x, 0.0, 0.235), (0.008, 0.012, 0.17), "steel")                 # stock struts
        m.box((0, -0.01, 0.32), (0.056, 0.07, 0.016), "black")                    # butt pad
        m.part("Mag", (0, -0.034, -0.06))
        m.curved((0, -0.034, -0.06), 0.026, 0.04, 0.055, (4, 9, 14), "black", part="Mag")
        m.mark("Optic", (0, 0.05, 0.02))
        m.mark("Fore", (0, -0.048, -0.17))
        m.mark("Muzzle", (0, 0.008, -0.31))
    elif look == "b":
        m.box((0, 0.0, 0.0), (0.056, 0.07, 0.27), "park")                         # boxy receiver
        m.box((0, 0.04, 0.03), (0.05, 0.01, 0.2), "park")                         # top cover
        for z in (-0.04, 0.0, 0.04):
            m.box((0, 0.046, z), (0.05, 0.004, 0.012), "black")                   # cover ribs
        m.box((0, 0.056, 0.11), (0.03, 0.036, 0.02), "park", part="Irons")        # rear sight ears
        m.box((0, 0.056, -0.12), (0.012, 0.036, 0.016), "park", part="Irons")     # front post
        m.box((0, 0.006, -0.17), (0.024, 0.024, 0.08), "black")                   # barrel
        m.box((0, -0.023, -0.1), (0.06, 0.03, 0.06), "black")                     # front grip plate
        m.box((0, -0.09, -0.005), (0.036, 0.12, 0.048), "stipple", pitch=-8)      # grip (mag inside)
        m.box((0, -0.05, -0.05), (0.01, 0.006, 0.05), "park")                     # guard
        m.part("Bolt", (0.032, 0.03, 0.06))
        m.box((0.032, 0.03, 0.06), (0.008, 0.014, 0.03), "steel", part="Bolt")    # bolt knob
        for x in (-0.026, 0.026):
            m.box((x, -0.005, 0.22), (0.006, 0.016, 0.17), "park")                # folding stock arms
        m.box((0, -0.02, 0.305), (0.058, 0.07, 0.012), "park")
        m.part("Mag", (0, -0.15, 0.005))
        m.box((0, -0.157, 0.007), (0.03, 0.014, 0.04), "park", pitch=-8, part="Mag")  # mag base out of the grip
        m.mark("Optic", (0, 0.045, 0.02))
        m.mark("Fore", (0, -0.038, -0.1))
        m.mark("Muzzle", (0, 0.006, -0.21))
    else:
        m.box((0, 0.0, 0.0), (0.056, 0.074, 0.26), "olive_dark")                  # receiver
        m.box((0, 0.043, 0.0), (0.03, 0.012, 0.3), "rail")                        # full top rail
        m.box((0, 0.06, 0.12), (0.026, 0.024, 0.02), "black", part="Irons")       # flip-up sights
        m.box((0, 0.06, -0.13), (0.01, 0.024, 0.016), "black", part="Irons")
        m.box((0, 0.004, -0.17), (0.06, 0.066, 0.1), "olive")                     # handguard
        for x in (-0.031, 0.031):
            m.box((x, 0.004, -0.17), (0.004, 0.02, 0.08), "black")                # vents
        m.box((0, 0.006, -0.25), (0.022, 0.022, 0.06), "black")                   # barrel
        m.box((0, 0.006, -0.285), (0.03, 0.03, 0.025), "black")                   # flash hider
        m.box((0, -0.078, 0.08), (0.034, 0.09, 0.044), "olive", pitch=-15)        # grip
        m.box((0, -0.05, 0.03), (0.01, 0.006, 0.06), "olive_dark")                # guard
        m.part("Bolt", (0.034, 0.03, 0.09))
        m.box((0.034, 0.03, 0.09), (0.01, 0.012, 0.03), "black", part="Bolt")     # charging handle
        stock = [(0.13, 0.03), (0.13, -0.03), (0.33, -0.05), (0.33, 0.03)]       # skeleton stock
        m.prism(stock, 0.02, "olive_dark")
        m.box((0, -0.01, 0.335), (0.05, 0.085, 0.014), "black")
        m.part("Mag", (0, -0.037, -0.06))
        m.box((0, -0.11, -0.06), (0.028, 0.15, 0.042), "black", pitch=4, part="Mag")
        m.mark("Optic", (0, 0.049, 0.02))
        m.mark("Fore", (0, -0.029, -0.17))
        m.mark("Muzzle", (0, 0.006, -0.3))
    m.mark("Grip", (0, -0.06, 0.08 if look != "b" else 0.0))
    m.mark("Sight", (0, 0.08, 0))


def mauler(m, look):
    """The Mauler (pump shotgun): A wood and blued, B black tactical with a side saddle, C worn with a heat shield."""
    metal = {"a": "blued", "b": "black", "c": "worn"}[look]
    furn = {"a": "wood", "b": "black", "c": "wood_light"}[look]
    m.box((0, 0.0, 0.02), (0.066, 0.096, 0.2), metal)                             # receiver
    m.box((0.034, 0.012, 0.0), (0.004, 0.03, 0.07), "black")                      # ejection port (right)
    m.box((0, 0.028, -0.33), (0.046, 0.046, 0.5), metal)                          # barrel
    m.box((0, 0.053, -0.33), (0.012, 0.006, 0.46), metal)                         # vent rib
    m.ytube(0, -0.565, 0.056, 0.066, 0.004, "brass", part="Irons")                # front bead
    m.ytube(0, -0.3, 0.056, 0.061, 0.0025, "steel", part="Irons")                 # mid bead
    m.box((0, -0.028, -0.29), (0.038, 0.038, 0.42), metal)                        # magazine tube
    m.box((0, -0.028, -0.5), (0.04, 0.04, 0.012), metal)                          # tube cap
    m.box((0, -0.06, 0.045), (0.012, 0.006, 0.08), metal)                         # trigger guard
    m.box((0, -0.052, 0.008), (0.006, 0.016, 0.006), metal)                       # trigger
    if look == "b":
        m.box((0, -0.03, -0.27), (0.07, 0.06, 0.15), "stipple")                   # polymer pump
        for z in (-0.22, -0.25, -0.28, -0.31):
            m.box((0, -0.03, z), (0.072, 0.062, 0.008), "black")
        m.box((0, -0.085, 0.13), (0.036, 0.1, 0.048), "stipple", pitch=-15)       # pistol grip
        stock = [(0.12, 0.04), (0.12, -0.045), (0.39, -0.07), (0.39, 0.03)]
        m.prism(stock, 0.028, "black")
        m.box((0, -0.02, 0.395), (0.06, 0.106, 0.014), "stipple")                 # recoil pad
        m.box((-0.037, 0.005, 0.02), (0.008, 0.05, 0.11), "black")                # side saddle (left)
        for k in range(4):
            m.box((-0.045, 0.005, -0.03 + k * 0.026), (0.012, 0.046, 0.02), "shell", ends="brass")
        m.box((0, 0.058, 0.08), (0.03, 0.008, 0.02), "black", part="Irons")       # ghost ring
        m.ring(0, 0.069, 0.08, 0.005, 0.004, 0.012, "black", part="Irons")
        m.box((0, 0.052, 0.0), (0.03, 0.01, 0.14), "rail")
        m.mark("Optic", (0, 0.057, 0.0))
        m.mark("Grip", (0, -0.07, 0.125))
    else:
        m.box((0, -0.03, -0.27), (0.068, 0.058, 0.17), furn)                      # wood pump
        for z in (-0.21, -0.24, -0.27, -0.30, -0.33):
            m.box((0, -0.03, z), (0.07, 0.06, 0.006), metal)
        # Straight stock with a small wrist, the grip in the wood (classic pump).
        stock = [(0.12, 0.045), (0.12, -0.05), (0.2, -0.085), (0.42, -0.1), (0.42, 0.03)]
        m.prism(stock, 0.028, furn)
        m.box((0, -0.035, 0.425), (0.058, 0.13, 0.012), "black")                  # butt pad
        m.mark("Optic", (0, 0.048, 0.02))
        m.mark("Grip", (0, -0.05, 0.16))
        if look == "c":
            m.box((0, 0.034, -0.17), (0.054, 0.04, 0.16), "rail")                 # perforated heat shield
            for z in (-0.27, -0.04):
                m.box((0, -0.03 if z < -0.1 else 0.0, z), (0.072 if z < -0.1 else 0.07, 0.064 if z < -0.1 else 0.1, 0.02), "tape")
            m.box((-0.035, -0.02, 0.3), (0.006, 0.05, 0.08), "olive_dark")        # stock pouch
    m.mark("Muzzle", (0, 0.028, -0.59))
    m.mark("Sight", (0, 0.066 if look != "b" else 0.069, 0))
    m.mark("Fore", (0, -0.06, -0.27))


def lancer(m, look):
    """The Lancer (bolt rifle): A wood hunting/army rifle, B a black and tan chassis rifle, C olive synthetic."""
    metal = {"a": "blued", "b": "black", "c": "park"}[look]
    m.box((0, 0.012, 0.0), (0.05, 0.05, 0.3), metal)                              # receiver (round-ish action)
    m.box((0, 0.012, 0.0), (0.056, 0.036, 0.3), metal)
    m.part("Bolt", (0, 0.012, 0.09))                                              # turns up and slides back (first person)
    m.box((0, 0.012, 0.12), (0.03, 0.03, 0.06), "steel", part="Bolt")             # bolt shroud
    m.box((0.035, 0.012, 0.09), (0.04, 0.008, 0.008), "steel", part="Bolt")       # bolt handle
    m.box((0.058, 0.004, 0.09), (0.016, 0.016, 0.016), "steel" if look != "b" else "black", part="Bolt")
    m.box((0, 0.012, -0.43), (0.024, 0.024, 0.5), metal)                          # long barrel
    m.box((0, -0.04, 0.03), (0.012, 0.006, 0.07), metal)                          # trigger guard
    m.box((0, -0.034, 0.005), (0.006, 0.016, 0.006), metal)
    m.box((0, 0.028, -0.2), (0.022, 0.01, 0.05), "blued")                         # rear sight ramp on the barrel
    m.notch(-0.19, 0.033, 0.074, "blued", width=0.03, gap=0.011, base_w=0.008, floor_drop=0.01, depth=0.006)  # leaf
    m.box((0, 0.028, -0.645), (0.016, 0.012, 0.04), "blued")                      # front ramp
    m.post(-0.65, 0.034, 0.074, "blued", guard="hood", base_w=0.01, hood=0.0075)
    m.part("Mag", (0, -0.03, -0.03))
    if look == "a":
        # Full wood stock running under the barrel, a sporting wrist and a long fore-end.
        m.prism([(-0.45, 0.012), (-0.45, -0.02), (-0.12, -0.04), (0.05, -0.04), (0.05, 0.02), (-0.12, 0.02)], 0.03, "wood_light")
        m.prism([(0.05, 0.02), (0.05, -0.04), (0.14, -0.08), (0.42, -0.1), (0.42, 0.01), (0.2, 0.0)], 0.028, "wood_light")
        m.box((0, -0.047, 0.425), (0.054, 0.115, 0.012), "black")
        m.box((0, -0.005, -0.38), (0.064, 0.016, 0.012), metal)                    # barrel band
        m.box((0, -0.045, -0.03), (0.04, 0.012, 0.06), metal, part="Mag")        # floor plate
        m.mark("Grip", (0, -0.05, 0.11))
        m.mark("Fore", (0, -0.04, -0.3))
    elif look == "b":
        m.box((0, -0.015, -0.1), (0.06, 0.06, 0.32), "tan")                       # aluminium chassis
        m.box((0, 0.042, -0.08), (0.03, 0.012, 0.42), "rail")                     # long top rail
        m.box((0, -0.015, -0.32), (0.062, 0.06, 0.14), "black")                   # handguard end
        for x in (-0.032, 0.032):
            m.box((x, -0.015, -0.2), (0.004, 0.02, 0.12), "black")                # slots
        m.box((0, -0.085, 0.1), (0.036, 0.1, 0.046), "stipple", pitch=-14)        # pistol grip
        m.box((0, -0.01, 0.2), (0.03, 0.04, 0.14), "black")                       # stock tube
        stock = [(0.27, 0.035), (0.27, -0.09), (0.42, -0.1), (0.42, 0.035)]      # skeleton butt
        m.prism(stock, 0.026, "tan")
        m.box((0, 0.045, 0.32), (0.05, 0.016, 0.1), "black")                      # cheek rest
        for x in (-0.012, 0.012):
            m.box((x, -0.06, -0.33), (0.008, 0.008, 0.16), "black")               # folded bipod legs
        m.box((0, -0.075, -0.03), (0.034, 0.09, 0.056), "black", part="Mag")      # box mag
        m.mark("Grip", (0, -0.07, 0.1))
        m.mark("Fore", (0, -0.065, -0.3))
    else:
        m.prism([(-0.4, 0.012), (-0.4, -0.025), (-0.1, -0.045), (0.05, -0.045), (0.05, 0.02), (-0.1, 0.02)], 0.032, "olive")
        m.prism([(0.05, 0.02), (0.05, -0.045), (0.14, -0.09), (0.42, -0.1), (0.42, 0.012), (0.2, 0.004)], 0.03, "olive")
        m.box((0, 0.025, 0.31), (0.05, 0.02, 0.1), "olive_dark")                  # raised comb
        m.box((0, -0.047, 0.425), (0.058, 0.118, 0.014), "black")
        for z in (-0.3, 0.38):
            m.box((0, -0.05 if z < 0 else -0.09, z), (0.012, 0.012, 0.03), "black")   # sling swivels
        m.box((0, -0.048, -0.03), (0.042, 0.012, 0.06), "black", part="Mag")
        m.mark("Grip", (0, -0.055, 0.11))
        m.mark("Fore", (0, -0.045, -0.28))
    if look == "b":
        m.box((0, 0.012, -0.70), (0.034, 0.034, 0.05), "black")                   # muzzle brake
        m.mark("Muzzle", (0, 0.012, -0.73))
        m.mark("Optic", (0, 0.048, -0.02))
    else:
        m.mark("Muzzle", (0, 0.012, -0.68))
        m.mark("Optic", (0, 0.03, 0.0))
    m.mark("Sight", (0, 0.074, 0))


# Reaper looks (letters a-f; the game uses PICKED): upper receiver, lower receiver, handguard, can, accent, furniture
# (grip, stock), mag, stock shape, can length, band, extras.
REAPER = {
    "a": dict(up="black", low="stipple", hand="park", can="steel", acc="black", furn="stipple", mag="black", stock="wedge"),
    "b": dict(up="black", low="stipple", hand="tan", can="steel", acc="black", furn="tan", mag="black", stock="wedge"),
    "c": dict(up="black", low="black", hand="stipple", can="black", acc="park", furn="black", mag="black", stock="tube",
              long=0.05),
    "d": dict(up="park", low="black", hand="black", can="black", acc="park", furn="black", mag="black", stock="stub",
              band="shell"),
    "e": dict(up="park", low="black", hand="park", can="black", acc="black", furn="black", mag="shell", stock="stub",
              band="shell", pad="shell"),
    "g": dict(up="black", low="stipple", hand="olive", can="steel", acc="black", furn="olive_dark", mag="black", stock="wedge"),
    "h": dict(up="black", low="stipple", hand="tan", can="steel", acc="black", furn="stipple", mag="bakelite", stock="wedge",
              pad="bakelite"),
    "i": dict(up="black", low="black", hand="olive", can="black", acc="olive_dark", furn="tan", mag="black", stock="tube",
              long=0.05),
    "j": dict(up="black", low="black", hand="stipple", can="black", acc="park", furn="black", mag="bakelite", stock="tube",
              long=0.05, pad="bakelite", band="bakelite"),
    "f": dict(up="worn", low="worn", hand="worn", can="worn", acc="black", furn="wood", mag="park", stock="wedge",
              tape=True),
}
REAPER_LOOKS = "abcdefghijk"


def reaper(m, look):
    """The Reaper (Raijin's carbine): a short compact rifle with a short barrel and flash hider (no built-in suppressor), a short rail and a stubby
    stock. Looks a-c: black polymer with a steel can (a), the same with tan furniture (b), all black with a longer can
    and a tube stock (c); d-f: Raijin's gun, dark steel with a red band (d), with a red mag and pad (e), a worn one
    with wood and tape (f)."""
    if look == "k":
        return _reaper_k(m)
    k = REAPER[look]
    up, low, hand, can, acc, furn, mag = k["up"], k["low"], k["hand"], k["can"], k["acc"], k["furn"], k["mag"]
    m.box((0, 0.012, 0.0), (0.058, 0.056, 0.26), up)                              # upper receiver
    m.box((0, 0.03, 0.125), (0.05, 0.02, 0.05), up)                               # raised rear end
    m.box((0, -0.03, 0.02), (0.054, 0.04, 0.21), low)                             # lower receiver
    m.box((0, -0.04, -0.07), (0.05, 0.05, 0.05), low)                             # magwell
    m.box((0.0295, 0.018, -0.03), (0.002, 0.024, 0.07), "black")                  # ejection port
    m.box((0, 0.046, -0.01), (0.026, 0.01, 0.32), "rail")                         # short top rail
    m.mark("Optic", (0, 0.051, 0.0))
    z0 = -0.12
    m.tube(0, 0.002, -0.3, z0, 0.031, hand, sides=8)                              # handguard
    for z in (-0.16, -0.205, -0.25):
        m.box((0.031, 0.002, z), (0.004, 0.024, 0.026), "black")                  # slots, right
        m.box((-0.031, 0.002, z), (0.004, 0.024, 0.026), "black")                 # slots, left
    if k.get("tape"):
        for z in (-0.19, -0.27):
            m.box((0, 0.002, z), (0.07, 0.07, 0.02), "tape")                      # taped handguard
    end = -0.44 - k.get("long", 0.0)
    m.box((0, 0.002, -0.306), (0.07, 0.07, 0.012), acc)                           # cap at the front of the handguard
    if k.get("band"):
        m.box((0, 0.002, -0.285), (0.07, 0.07, 0.016), k["band"])                 # red band
    m.tube(0, 0.002, -0.312, end + 0.05, 0.0135, "park", sides=8)                 # a plain short barrel
    m.box((0, 0.02, -0.33), (0.03, 0.03, 0.03), acc)                              # gas block
    m.tube(0, 0.002, end + 0.05, end, 0.02, acc, sides=8)                         # flash hider
    for z in (end + 0.012, end + 0.03):
        m.box((0, 0.002, z), (0.046, 0.008, 0.007), "black")                      # its slots
        m.box((0, 0.002, z), (0.008, 0.046, 0.007), "black")
    m.box((0, 0.059, -0.17), (0.03, 0.016, 0.026), acc, part="Irons")             # front sight block
    m.post(-0.17, 0.067, 0.083, acc)
    m.notch(0.1, 0.051, 0.083, acc, width=0.026)
    m.box((0, -0.092, 0.085), (0.03, 0.1, 0.044), furn, pitch=-22)                # pistol grip
    m.box((0, -0.06, 0.04), (0.012, 0.006, 0.085), low)                           # trigger guard
    m.box((0, -0.053, 0.0), (0.012, 0.016, 0.006), low)
    m.box((0, -0.052, 0.036), (0.006, 0.016, 0.006), "steel")                     # trigger
    m.part("Bolt", (0.032, 0.018, 0.0))
    m.box((0.032, 0.018, 0.0), (0.022, 0.012, 0.014), "steel", part="Bolt")       # charging handle
    m.box((0.031, -0.005, 0.07), (0.004, 0.018, 0.09), acc)                       # selector lever
    pad = k.get("pad", "black")
    if k["stock"] == "wedge":                                                     # stubby wedge stock
        m.prism([(0.13, 0.036), (0.13, -0.035), (0.268, -0.062), (0.268, 0.018), (0.2, 0.034)], 0.022, furn)
        m.box((0, -0.022, 0.275), (0.054, 0.084, 0.014), pad)
    elif k["stock"] == "tube":                                                    # a short tube stock with a cheek rest
        m.box((0, -0.006, 0.2), (0.04, 0.05, 0.14), acc)
        m.box((0, 0.026, 0.215), (0.036, 0.012, 0.1), furn)
        m.box((0, -0.01, 0.276), (0.054, 0.086, 0.014), pad)
    else:                                                                         # a folded stub: a fat block, a hinge
        m.box((0, 0.0, 0.205), (0.052, 0.07, 0.14), furn)
        m.box((0, 0.0, 0.14), (0.06, 0.05, 0.014), acc)                           # hinge
        m.box((0, 0.0, 0.282), (0.058, 0.074, 0.016), pad)
    m.part("Mag", (0, -0.05, -0.065))
    m.curved((0, -0.05, -0.065), 0.03, 0.055, 0.045, (4, 12, 22), mag, part="Mag")
    m.mark("Muzzle", (0, 0.002, end - 0.01))
    m.mark("Grip", (0, -0.075, 0.07))
    m.mark("Sight", (0, 0.083, 0))
    m.mark("Fore", (0, -0.034, -0.2))


def _strut(m, a, b, t, hw, mat, part="Body"):
    """A thin flat bar in the side view from a = (z, y) to b, t thick, 2*hw wide."""
    (z0, y0), (z1, y1) = a, b
    dz, dy = z1 - z0, y1 - y0
    n = math.hypot(dz, dy)
    oz, oy = -dy / n * t / 2, dz / n * t / 2
    m.prism([(z0 + oz, y0 + oy), (z1 + oz, y1 + oy), (z1 - oz, y1 - oy), (z0 - oz, y0 - oy)], hw, mat, part=part)


def _reaper_k(m):
    """Reaper look k (owner's photo, 2026-11-16): a compact pistol-calibre-style carbine. A flat top rail the whole
    length with flip-up sights, a short squared handguard with long side and bottom slots and a side charging handle,
    a stubby barrel with a small muzzle cap (the suppressor attachment screws on there), a flared magwell, a long
    curved mag, a grooved pistol grip and a skeleton brace: a buffer tube, a thin rod and a triangle pad. All black
    and dark grey. Grip, fore-end, sight line, optic and mag marks match look c, so the hands and aiming still fit."""
    up, low, hand, acc, furn = "black", "black", "blued", "park", "stipple"
    # receivers
    m.box((0, 0.012, 0.0), (0.058, 0.056, 0.26), up)                              # upper receiver
    m.box((0, 0.012, -0.11), (0.064, 0.06, 0.03), up)                             # barrel nut collar
    m.box((0.0295, 0.016, -0.025), (0.002, 0.022, 0.075), "blued")                # ejection port cover
    m.box((0.031, 0.004, 0.09), (0.008, 0.016, 0.026), up)                        # forward assist bump
    m.box((0, -0.03, 0.03), (0.054, 0.04, 0.2), low)                              # lower receiver
    m.prism([(-0.105, -0.012), (-0.035, -0.012), (-0.035, -0.07), (-0.11, -0.078)], 0.029, low)   # magwell, swept
    m.box((0, -0.079, -0.072), (0.066, 0.012, 0.08), low)                         # flared mouth
    m.box((0.0285, -0.02, -0.02), (0.004, 0.014, 0.022), acc)                     # mag release
    m.box((-0.0285, -0.016, -0.015), (0.004, 0.026, 0.012), acc)                  # bolt catch (left)
    m.box((0.031, -0.005, 0.07), (0.004, 0.018, 0.09), acc)                       # selector lever
    for z in (-0.045, 0.06, 0.11):
        m.box((0.0285, -0.035, z), (0.003, 0.008, 0.008), "steel")                # pins
        m.box((-0.0285, -0.035, z), (0.003, 0.008, 0.008), "steel")
    # one flat top rail over the receiver and handguard
    m.box((0, 0.046, -0.085), (0.026, 0.01, 0.43), "rail")
    m.mark("Optic", (0, 0.051, 0.0))
    # squared handguard (an eight-sided tube, flats wide) with long slots on the sides and underneath
    m.box((0, 0.004, -0.215), (0.062, 0.062, 0.19), hand)
    for sx in (-1, 1):
        m.box((sx * 0.03, 0.035, -0.215), (0.012, 0.012, 0.19), hand)             # chamfers top
        m.box((sx * 0.03, -0.027, -0.215), (0.012, 0.012, 0.19), hand)            # chamfers bottom
        for z in (-0.17, -0.25):
            m.box((sx * 0.0315, 0.004, z), (0.002, 0.016, 0.055), "black")        # long side slots
        m.box((sx * 0.0315, 0.026, -0.21), (0.002, 0.006, 0.12), "black")         # upper groove
    for z in (-0.17, -0.25):
        m.box((0, -0.0275, z), (0.018, 0.002, 0.05), "black")                     # bottom slots
    m.box((0, 0.004, -0.309), (0.068, 0.066, 0.008), acc)                         # front lip
    m.box((0.033, 0.006, -0.135), (0.01, 0.024, 0.03), "black")                   # charging slot
    # stubby barrel and muzzle cap (the Muzzle mark is where a suppressor goes on)
    m.tube(0, 0.002, -0.313, -0.345, 0.0135, acc, sides=8)
    m.tube(0, 0.002, -0.345, -0.375, 0.019, "black", sides=8)
    for z in (-0.355, -0.366):
        m.box((0, 0.002, z), (0.042, 0.006, 0.004), "blued")                      # cap grooves
    # flip-up sights on the rail
    m.box((0, 0.058, -0.275), (0.03, 0.014, 0.026), up, part="Irons")             # front sight base
    m.post(-0.275, 0.065, 0.083, up)
    m.box((0, 0.057, 0.105), (0.032, 0.012, 0.03), up, part="Irons")              # rear sight base
    m.notch(0.1, 0.063, 0.083, up, width=0.03)
    # grip and trigger
    m.box((0, -0.094, 0.087), (0.03, 0.104, 0.046), furn, pitch=-22)              # pistol grip
    for k in range(3):
        m.box((0, -0.075 - k * 0.022, 0.058 + k * 0.009), (0.031, 0.01, 0.006), "black", pitch=-22)  # finger grooves
    m.box((0, -0.05, 0.118), (0.034, 0.012, 0.03), low)                           # beavertail
    m.box((0, -0.06, 0.04), (0.012, 0.006, 0.085), low)                           # trigger guard
    m.box((0, -0.053, 0.0), (0.012, 0.016, 0.006), low)
    m.box((0, -0.052, 0.036), (0.006, 0.016, 0.006), "steel")                     # trigger
    m.part("Bolt", (0.034, 0.012, -0.135))
    m.box((0.04, 0.012, -0.135), (0.016, 0.012, 0.014), "steel", part="Bolt")     # side charging handle
    # skeleton brace: tube, top bar to a triangle pad, a thin rod below
    m.box((0, 0.006, 0.137), (0.05, 0.05, 0.014), up)                             # end plate
    m.tube(0, 0.008, 0.144, 0.26, 0.017, up, sides=8)                             # buffer tube
    m.box((0, -0.012, 0.2), (0.03, 0.024, 0.05), up)                              # brace collar
    m.tube(0, -0.03, 0.15, 0.3, 0.005, acc, sides=6)                              # thin rod
    _strut(m, (0.255, 0.012), (0.3, 0.022), 0.014, 0.012, up)                     # top bar
    _strut(m, (0.3, 0.03), (0.3, -0.07), 0.016, 0.026, furn)                      # pad
    _strut(m, (0.3, 0.022), (0.255, -0.06), 0.009, 0.007, up)                     # diagonal
    _strut(m, (0.24, -0.035), (0.3, -0.068), 0.009, 0.007, up)                    # bottom bar
    # long curved mag, ribbed near the top
    m.part("Mag", (0, -0.05, -0.065))
    p = m.curved((0, -0.05, -0.065), 0.03, 0.056, 0.05, (5, 11), "black", part="Mag")
    p = m.curved(p, 0.031, 0.057, 0.05, (17, 23), furn, part="Mag")
    m.box(mb.v_add(p, mb.rot((0, -0.005, 0.0), 0.0, 23)), (0.036, 0.012, 0.064), "black", pitch=23, part="Mag")  # base pad
    m.mark("Muzzle", (0, 0.002, -0.376))
    m.mark("Grip", (0, -0.075, 0.07))
    m.mark("Sight", (0, 0.083, 0))
    m.mark("Fore", (0, -0.034, -0.2))


# ------------------------------------------------------------------------------------------------ second gun of each type
# (0.36.42, owner 2026-11-20: "2 of each weapon type"): one look each, made to read apart from the first gun of its type
# at a glance (colour first, then shape).
def viper(m, look):
    """The Viper (heavy pistol): bigger than the Stinger, a steel slide on a black frame, red-brown grips and a
    compensator out front."""
    m.part("Bolt", (0, 0.014, 0.0))                                               # the slide (racked in first person)
    m.box((0, 0.014, 0.0), (0.036, 0.04, 0.215), "steel", part="Bolt")            # slide
    for k in range(6):                                                            # rear serrations
        m.box((0, 0.014, 0.068 + k * 0.007), (0.0375, 0.034, 0.003), "park", part="Bolt")
    m.box((0, 0.025, -0.035), (0.0375, 0.012, 0.032), "black", part="Bolt")       # ejection port
    m.notch(0.095, 0.034, 0.0415, "black", width=0.03, gap=0.009, dots=True)      # three-dot sights
    m.post(-0.095, 0.034, 0.0415, "black", guard=None, width=0.006, base_w=0.009)
    m.box((0, 0.012, -0.123), (0.04, 0.036, 0.03), "black")                       # compensator
    for z in (-0.116, -0.128):
        m.box((0, 0.031, z), (0.012, 0.003, 0.005), "park")   # its ports on top
    m.box((0, -0.018, -0.01), (0.034, 0.028, 0.19), "black")                      # frame
    m.box((0, -0.034, -0.07), (0.024, 0.006, 0.05), "rail")                       # accessory rail
    m.box((0, -0.082, 0.065), (0.034, 0.115, 0.05), "wood_red", pitch=-14)        # grip panels
    m.box((0, -0.082, 0.065), (0.027, 0.117, 0.052), "black", pitch=-14)          # the grip frame round them
    m.box((0, -0.044, -0.012), (0.011, 0.006, 0.066), "black")                    # trigger guard
    m.box((0, -0.037, -0.044), (0.011, 0.018, 0.006), "black")
    m.box((0, -0.034, -0.004), (0.006, 0.018, 0.006), "steel")                    # trigger
    m.box((0, 0.024, 0.112), (0.012, 0.02, 0.012), "steel", pitch=-30)            # hammer
    m.part("Mag", (0, -0.135, 0.08))
    m.box((0, -0.139, 0.082), (0.036, 0.009, 0.055), "steel", pitch=-14, part="Mag")  # base plate
    m.mark("Muzzle", (0, 0.012, -0.14))
    m.mark("Grip", (0, -0.065, 0.06))
    m.mark("Sight", (0, 0.0415, 0))
    m.mark("Optic", (0, 0.034, 0.035))


def hornet(m, look):
    """The Hornet (heavier SMG): tan, boxy and square where the Wasp is black and slim, a straight mag, a long
    shrouded barrel and a folding wire stock."""
    m.box((0, 0.0, 0.0), (0.058, 0.074, 0.27), "tan")                             # receiver
    m.box((0, 0.044, 0.0), (0.03, 0.012, 0.3), "rail")                            # top rail
    m.box((0, 0.062, 0.125), (0.028, 0.026, 0.02), "black", part="Irons")         # rear aperture block
    m.ring(0, 0.08, 0.125, 0.0065, 0.003, 0.01, "black", part="Irons")
    m.box((0, 0.06, -0.2), (0.014, 0.024, 0.016), "black", part="Irons")          # front post block
    m.post(-0.2, 0.06, 0.08, "black", guard="ears")
    m.box((0, 0.004, -0.2), (0.062, 0.064, 0.14), "black")                        # square barrel shroud
    for z in (-0.16, -0.19, -0.22, -0.25):
        for x in (-0.032, 0.032):
            m.box((x, 0.004, z), (0.004, 0.018, 0.016), "park")                   # its cooling slots
    m.box((0, 0.004, -0.275), (0.026, 0.026, 0.02), "black")                      # barrel nut
    m.box((0, 0.004, -0.3), (0.022, 0.022, 0.03), "black")                        # barrel end
    m.box((0, -0.08, 0.075), (0.036, 0.092, 0.046), "black", pitch=-14)           # grip
    m.box((0, -0.05, 0.03), (0.01, 0.006, 0.06), "tan")                           # guard
    m.box((0, -0.044, 0.0), (0.006, 0.016, 0.006), "black")                       # trigger
    m.part("Bolt", (-0.034, 0.028, -0.09))
    m.box((-0.034, 0.028, -0.09), (0.012, 0.014, 0.03), "black", part="Bolt")     # side cocking handle (left)
    for x in (-0.024, 0.024):
        m.box((x, -0.006, 0.225), (0.006, 0.01, 0.18), "steel")                   # folding wire stock
    m.box((0, -0.018, 0.318), (0.054, 0.07, 0.012), "black")                      # its butt
    m.box((0, -0.016, 0.26), (0.05, 0.006, 0.006), "steel")                       # cross bar
    m.part("Mag", (0, -0.037, -0.07))
    m.box((0, -0.11, -0.07), (0.03, 0.15, 0.038), "black", part="Mag")            # straight stick mag
    m.box((0, -0.187, -0.07), (0.034, 0.008, 0.042), "tan", part="Mag")           # its base plate
    m.mark("Optic", (0, 0.05, 0.02))
    m.mark("Fore", (0, -0.028, -0.2))
    m.mark("Muzzle", (0, 0.004, -0.315))
    m.mark("Grip", (0, -0.062, 0.072))
    m.mark("Sight", (0, 0.08, 0))


def brawler(m, look):
    """The Brawler (semi-auto shotgun): black receiver with olive furniture, a pistol grip and a fixed fore-end (no
    pump), a vented barrel shroud and a charging handle on the right."""
    m.box((0, 0.0, 0.02), (0.064, 0.094, 0.22), "black")                          # receiver
    m.box((0.033, 0.012, -0.005), (0.004, 0.03, 0.075), "steel")                  # ejection port (right)
    m.box((0, 0.052, 0.0), (0.03, 0.01, 0.16), "rail")                            # top rail
    m.box((0, 0.028, -0.33), (0.044, 0.044, 0.5), "blued")                        # barrel
    m.box((0, 0.034, -0.2), (0.052, 0.04, 0.2), "rail")                           # perforated shroud over it
    m.ytube(0, -0.565, 0.05, 0.062, 0.004, "brass", part="Irons")                 # front bead
    m.box((0, 0.058, 0.08), (0.03, 0.008, 0.02), "black", part="Irons")           # ghost ring
    m.ring(0, 0.069, 0.08, 0.005, 0.004, 0.012, "black", part="Irons")
    m.box((0, -0.028, -0.3), (0.038, 0.038, 0.42), "black")                       # magazine tube
    m.box((0, -0.028, -0.515), (0.042, 0.042, 0.02), "steel")                     # tube cap
    m.box((0, -0.03, -0.23), (0.07, 0.062, 0.2), "olive")                         # fixed fore-end
    for x in (-0.036, 0.036):
        m.box((x, -0.03, -0.23), (0.003, 0.02, 0.15), "olive_dark")               # its grooves
    m.part("Bolt", (0.04, 0.012, -0.03))
    m.box((0.04, 0.012, -0.03), (0.02, 0.012, 0.014), "steel", part="Bolt")       # charging handle
    m.box((0, -0.06, 0.045), (0.012, 0.006, 0.08), "black")                       # trigger guard
    m.box((0, -0.052, 0.008), (0.006, 0.016, 0.006), "steel")                     # trigger
    m.box((0, -0.088, 0.11), (0.036, 0.1, 0.048), "olive", pitch=-16)             # pistol grip
    stock = [(0.13, 0.04), (0.13, -0.045), (0.39, -0.075), (0.39, 0.03)]
    m.prism(stock, 0.028, "olive")
    m.box((0, -0.022, 0.395), (0.06, 0.106, 0.014), "black")                      # recoil pad
    m.box((0, 0.048, 0.3), (0.04, 0.014, 0.1), "olive_dark")                      # cheek rest
    for k in range(3):                                                            # side saddle (left), red shells
        m.box((-0.04, 0.004, -0.0 + k * 0.026), (0.012, 0.046, 0.02), "shell", ends="brass")
    m.part("Mag", (0, -0.05, -0.08))
    m.mark("Optic", (0, 0.057, 0.0))
    m.mark("Grip", (0, -0.072, 0.105))
    m.mark("Muzzle", (0, 0.028, -0.585))
    m.mark("Sight", (0, 0.069, 0))
    m.mark("Fore", (0, -0.061, -0.23))


def talon(m, look):
    """The Talon (semi-auto marksman rifle): a black upper on a tan lower and handguard, a box mag, a long rail and a
    muzzle brake. Shorter than the Lancer, with a pistol grip and an adjustable stock."""
    m.box((0, 0.0, 0.0), (0.058, 0.07, 0.3), "black")                             # upper receiver
    m.box((0, -0.035, 0.02), (0.056, 0.04, 0.22), "tan")                          # lower receiver
    m.box((0, 0.042, -0.1), (0.03, 0.012, 0.5), "rail")                           # long top rail
    m.box((0, 0.002, -0.32), (0.062, 0.062, 0.3), "tan")                          # handguard
    for z in (-0.22, -0.27, -0.32, -0.37, -0.42):
        for x in (-0.032, 0.032):
            m.box((x, 0.002, z), (0.004, 0.022, 0.026), "black")                  # its slots
    m.box((0, 0.008, -0.58), (0.022, 0.022, 0.22), "blued")                       # barrel
    m.box((0, 0.008, -0.705), (0.034, 0.034, 0.05), "black")                      # muzzle brake
    for z in (-0.695, -0.715):
        m.box((0, 0.008, z), (0.036, 0.012, 0.006), "park")                       # its ports
    m.box((0, 0.062, 0.12), (0.026, 0.024, 0.02), "black", part="Irons")         # flip-up rear
    m.ring(0, 0.078, 0.12, 0.006, 0.003, 0.01, "black", part="Irons")
    m.box((0, 0.06, -0.44), (0.012, 0.024, 0.016), "black", part="Irons")        # flip-up front
    m.post(-0.44, 0.06, 0.078, "black", guard="ears")
    m.part("Bolt", (0.034, 0.02, 0.05))
    m.box((0.034, 0.02, 0.05), (0.012, 0.014, 0.034), "steel", part="Bolt")       # charging handle (right)
    m.box((0, -0.068, 0.055), (0.012, 0.006, 0.07), "black")                      # trigger guard
    m.box((0, -0.062, 0.025), (0.006, 0.016, 0.006), "steel")                     # trigger
    m.box((0, -0.11, 0.1), (0.036, 0.1, 0.046), "stipple", pitch=-16)             # pistol grip
    m.box((0, -0.008, 0.21), (0.03, 0.036, 0.12), "black")                        # buffer tube
    stock = [(0.24, 0.035), (0.24, -0.075), (0.42, -0.095), (0.42, 0.035)]
    m.prism(stock, 0.026, "tan")
    m.box((0, 0.045, 0.33), (0.046, 0.016, 0.09), "black")                        # cheek riser
    m.box((0, -0.03, 0.425), (0.054, 0.13, 0.012), "black")                       # butt pad
    m.part("Mag", (0, -0.055, -0.06))
    m.box((0, -0.1, -0.065), (0.032, 0.09, 0.06), "black", pitch=6, part="Mag")   # box mag
    m.mark("Optic", (0, 0.048, -0.02))
    m.mark("Grip", (0, -0.095, 0.095))
    m.mark("Fore", (0, -0.029, -0.33))
    m.mark("Muzzle", (0, 0.008, -0.735))
    m.mark("Sight", (0, 0.078, 0))


GUNS = {"hound": hound, "stinger": stinger, "wasp": wasp, "mauler": mauler, "lancer": lancer, "reaper": reaper,
        "viper": viper, "hornet": hornet, "brawler": brawler, "talon": talon}


# ------------------------------------------------------------------------------------------------ attachments
def att_red_dot(m):
    """A small reflex sight: a clamp, a low housing and a square window with rounded corners; the glass is clear (the
    HUD draws the dot when you aim through it)."""
    line = 0.042
    m.box((0, 0.005, 0), (0.034, 0.01, 0.056), "black")                           # rail clamp
    m.box((0.019, 0.005, 0.0), (0.006, 0.012, 0.016), "steel")                    # clamp screw
    m.box((0, 0.018, 0.006), (0.032, 0.016, 0.044), "black")                      # housing
    m.box((0, 0.019, -0.012), (0.012, 0.006, 0.006), "shell")                     # emitter
    m.ring(0, line, -0.006, 0.0125, 0.004, 0.012, "black")                        # window frame
    m.box((0, line, -0.006), (0.026, 0.026, 0.001), "glass")                      # clear glass
    m.ytube(0.022, 0.012, 0.012, 0.022, 0.005, "black")                           # brightness knob (right)
    m.box((0.025, 0.017, 0.012), (0.002, 0.003, 0.008), "steel")                  # its grip lines
    m.mark("Line", (0, line, 0))


def _scope(m, length, r, bell):
    """Main tube, a tapered objective bell in front and an eyepiece behind, two rings on a rail clamp, turret caps."""
    sides = 12
    y = 0.016 + r + 0.014
    half = length / 2
    m.box((0, 0.006, 0), (0.032, 0.012, length * 0.5), "black")                   # clamp base
    for z in (-length * 0.17, length * 0.17):
        m.box((0, 0.018, z), (0.018, 0.016, 0.016), "black")                      # ring posts
        m.tube(0, y, z - 0.008, z + 0.008, r + 0.004, "park", sides=sides)        # rings
    m.tube(0, y, -half * 0.55, half * 0.45, r, "black", sides=sides)              # main tube
    m.tube(0, y, -half * 0.72, -half * 0.55, (r + bell) / 2, "black", sides=sides)  # taper up
    m.tube(0, y, -half, -half * 0.72, bell, "black", sides=sides, ends="lens")    # objective bell, glass in front
    m.tube(0, y, -half - 0.004, -half, bell * 0.92, "park", sides=sides, ends="lens")  # front ring
    m.tube(0, y, half * 0.45, half * 0.62, r * 1.15, "black", sides=sides)        # power ring
    for k in range(3):
        z = half * 0.48 + k * half * 0.05
        m.box((0, y + r * 1.15, z), (0.004, 0.002, 0.003), "steel")               # its grip marks
    m.tube(0, y, half * 0.62, half, r * 1.4, "black", sides=sides, ends="lens")   # eyepiece
    m.tube(0, y, half, half + 0.006, r * 1.3, "stipple", sides=sides, ends="lens")  # rubber eye cup
    m.ytube(0, 0, y + r * 0.6, y + r + 0.012, 0.009, "black")                      # elevation turret
    m.ytube(0, 0, y + r + 0.012, y + r + 0.016, 0.0095, "park")
    m.box((r + 0.006, y, 0), (0.012, 0.016, 0.016), "black")                      # windage turret
    m.box((r + 0.0135, y, 0), (0.003, 0.014, 0.014), "park")
    m.mark("Line", (0, y, 0))


def att_scope_4x(m):
    _scope(m, 0.2, 0.013, 0.019)


def att_scope_8x(m):
    _scope(m, 0.28, 0.015, 0.026)


def att_suppressor(m):
    m.tube(0, 0, 0.0, -0.16, 0.022, "black")
    m.tube(0, 0, -0.158, -0.163, 0.018, "park")                                   # end cap
    m.mark("End", (0, 0, -0.163))


def att_suppressor_reaper(m):
    """The suppressor as it looks on the Reaper (owner's photo, 2026-11-16): a long, fat plain can. Looks only: the same
    item and numbers as the other guns' suppressor."""
    m.tube(0, 0, 0.0, -0.025, 0.02, "blued", sides=8)                              # mount collar
    m.tube(0, 0, -0.025, -0.3, 0.027, "black", sides=8)                            # the can
    m.tube(0, 0, -0.3, -0.306, 0.024, "blued", sides=8)                            # front cap
    m.tube(0, 0, -0.3, -0.307, 0.008, "black", sides=6)                            # bore
    m.mark("End", (0, 0, -0.307))


def att_choke(m):
    m.tube(0, 0, 0.0, -0.05, 0.03, "park")
    for z in (-0.015, -0.03):
        m.box((0, 0.024, z), (0.016, 0.012, 0.006), "black")                      # ports
    m.mark("End", (0, 0, -0.05))


def att_foregrip(m):
    m.box((0, -0.008, 0), (0.03, 0.016, 0.05), "black")                           # clamp
    m.box((0, -0.05, 0.004), (0.03, 0.075, 0.032), "stipple", pitch=-6)
    m.box((0, -0.09, 0.008), (0.034, 0.008, 0.036), "black")                      # end cap


ATTACHMENTS = {"red_dot": att_red_dot, "scope_4x": att_scope_4x, "scope_8x": att_scope_8x,
               "suppressor": att_suppressor, "suppressor_reaper": att_suppressor_reaper, "choke": att_choke, "foregrip": att_foregrip}


# ------------------------------------------------------------------------------------------------ .glb
def write_model(path, model, textures):
    """One mesh node per part (verts relative to its origin) and an empty per mark; flat normals, crisp textures."""
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

    used = []
    for b, _ in model.parts.values():
        for name in b.mat_names:
            if name not in used:
                used.append(name)
    images, materials = [], []
    for name in used:
        images.append({"bufferView": add_view(textures[name].png), "mimeType": "image/png", "name": "gun_" + name})
        materials.append({"name": "gun_" + name, "pbrMetallicRoughness": {
            "baseColorTexture": {"index": len(images) - 1}, "metallicFactor": 0.0, "roughnessFactor": 1.0}})
        if name in SEE_THROUGH:
            materials[-1]["alphaMode"] = "BLEND"
            materials[-1]["pbrMetallicRoughness"]["baseColorFactor"] = [1.0, 1.0, 1.0, SEE_THROUGH[name]]
    meshes, nodes = [], []
    for pname, (b, origin) in model.parts.items():
        if not b.faces:
            continue
        prims = []
        for mname in b.mat_names:
            mi = used.index(mname)
            pos, nrm, uv, idx = [], [], [], []
            for face, uvs, m, n in zip(b.faces, b.uvs, b.mats, b.normals):
                if b.mat_names[m] != mname:
                    continue
                base = len(pos)
                for vi, t in zip(face, uvs):
                    pos.append(mb.v_sub(b.verts[vi], origin))
                    nrm.append(n)
                    uv.append((t[0], 1.0 - t[1]))
                for k in range(1, len(face) - 1):
                    idx += [base, base + k, base + k + 1]
            prims.append({"attributes": {"POSITION": add_accessor(pos, 5126, "VEC3", 34962, True),
                                         "NORMAL": add_accessor(nrm, 5126, "VEC3", 34962),
                                         "TEXCOORD_0": add_accessor(uv, 5126, "VEC2", 34962)},
                          "indices": add_accessor(idx, 5125, "SCALAR", 34963), "material": mi})
        meshes.append({"name": pname, "primitives": prims})
        nodes.append({"name": pname, "mesh": len(meshes) - 1, "translation": list(origin)})
    for mname, pos in model.marks.items():
        nodes.append({"name": mname, "translation": list(pos)})
    gltf = {"asset": {"version": "2.0", "generator": "Bloxov make_gun.py"}, "scene": 0,
            "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes, "materials": materials,
            "textures": [{"source": i, "sampler": 0} for i in range(len(images))], "images": images,
            "samplers": [{"magFilter": 9728, "minFilter": 9984, "wrapS": 10497, "wrapT": 10497}],
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


def main():
    every = "all" in sys.argv[1:]
    textures = {name: Texture("gun_" + name, os.path.join("art_source", "textures", "guns", name + ".png"),
                              painter, random.Random("gun_" + name)) for name, painter in MATS.items()}
    for gun, build in GUNS.items():
        for look in (REAPER_LOOKS if gun == "reaper" else "abc") if every else (PICKED[gun],):
            m = Model(gun)
            build(m, look)
            name = gun if look == PICKED[gun] else f"{gun}_{look}"
            write_model(os.path.join(OUT, name + ".glb"), m, textures)
            if every and look == PICKED[gun]:
                write_model(os.path.join(OUT, f"{gun}_{look}.glb"), m, textures)
            print(f"{name}: look {look}, {m.tris()} triangles")
    for att, build in ATTACHMENTS.items():
        m = Model(att)
        build(m)
        write_model(os.path.join(OUT, f"att_{att}.glb"), m, textures)
        print(f"att_{att}: {m.tris()} triangles")


if __name__ == "__main__":
    main()
