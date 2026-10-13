"""Bloxov buildings (World art, 0.17): builds a building's model around its gray box.

The map generator (tools/gen_old_bloxov.py) still makes every wall, floor and prop of a building as a box, so players,
shots and AI paths work exactly as before; inside `with modeled("<name>", x, z):` those boxes are not drawn and are
written to art_source/buildings/<name>.json instead. This script reads that file and draws the boxes with the shared
kit textures (walls, floors, ceilings, concrete...) and each prop `kind` (pump, shelf, fridge...) with its own detail,
then adds the building's own decoration (signs, broken glass, litter) from DRESSING below.

How to use:
  - Blender (4.x / 5.x): Scripting tab > Text > Open > art_source/scripts/make_building.py, set BUILDING below, Run.
    The repo is found from the open .blend (save it in art_source/) or from this script's own path.
  - Command line: blender --background --python art_source/scripts/make_building.py -- gas_station_town
  - Without Blender: python3 art_source/scripts/make_building.py gas_station_town writes the same .glb directly.
Re-running rebuilds the model (it only touches objects in the "Bloxov" collection). Set EXPORT = True (the command
line always exports) to write assets/models/buildings/<name>.glb; then re-run tools/gen_old_bloxov.py so the map
hides the gray box and places the model.

Kit textures: 16 px per meter, tiling every 4 m (64 x 64), painted with the Bloxov palette, saved to
art_source/textures/kit/<name>.png. Signs and decals are in one 256 x 256 atlas per building at 32 px per meter
(art_source/textures/<building>_decals.png). Existing files are loaded instead of repainted, so you can paint over
them by hand and re-run; REGENERATE_TEXTURES = True repaints them all.

Coordinates in this file are Godot's (x east, y up, z south, like the .json); they're turned into Blender's
(x, -z, y) when the mesh is made, and the glTF export turns them back.
"""
import math
import os
import random
import sys

import json
import re
import struct
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_light  # noqa: E402

try:
    import bpy
except ImportError:      # plain Python: writes the .glb itself (same model, no Blender needed)
    bpy = None

BUILDING = "gas_station_town"
EXPORT = False
REGENERATE_TEXTURES = False
BAKE_LIGHT = os.environ.get("BLOXOV_BAKE", "1") == "1"   # sky light baked into vertex colours (bake_light.py)

# Art style knobs (0.17 style tests; the chosen look becomes the default). BLOXOV_STYLE=<name> picks one of STYLES.
STYLES = {
    "pixel": {},                                                        # v1: 16 px/m, some dirt
    "flat": {"flat": True},                                             # kit surfaces one colour each (signs stay)
    "gritty": {"dirt": 2.5, "sat": 0.6, "bright": 0.8, "grime": 0.4},   # war-torn: soot, grime, dark and dirty
    "dusty": {"dirt": 1.5, "sat": 0.75, "tint": (1.08, 0.98, 0.82)},   # sun-bleached, dusty, warm
    "fine": {"fine": True},                                             # twice the pixels (32 px/m grain)
    "bold": {"outline": True, "sat": 1.25, "bright": 1.04, "dirt": 0.5},  # dark edges on every shape, punchy colour
}
STYLE = {"dirt": 1.0, "sat": 1.0, "bright": 1.0, "outline": False, "fine": False, "flat": False, "grime": 0.0,
         "tint": (1.0, 1.0, 1.0)}
STYLE.update(STYLES.get(os.environ.get("BLOXOV_STYLE", "pixel"), {}))
TEX_DIR = os.environ.get("BLOXOV_TEX_DIR")   # style tests paint into a scratch folder instead of art_source/textures

PX_PER_M = 16
TILE_M = 4.0           # kit textures repeat every 4 m (64 px)
DECAL_PX_PER_M = 32

PALETTE = {
    "black": "1b1c1f", "iron_dark": "2f3236", "iron": "4b5057", "steel": "6f767d", "steel_light": "9aa1a6",
    "concrete": "b8b4aa", "bone": "e2dccb", "wood_dark": "4a2f1b", "wood_mid": "6e4628", "wood": "8f5e34",
    "wood_light": "b07a45", "wood_pale": "c99a5e", "rust": "8a3f1f", "red": "b03a2e", "hazard_yellow": "e8b923",
    "yellow_dark": "a8801a", "sand": "a89a6a", "olive_dark": "3d4228", "olive": "5b6236", "olive_light": "7d8450",
    "grass": "556b2f", "green_dark": "2e7d32", "extract_green": "4fd44a", "sky_blue": "3e6d8c",
}


def rgba(name):
    if name == "clear":          # see-through (cut-out decals)
        return [0.0, 0.0, 0.0, 0.0]
    h = PALETTE[name]
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


# ------------------------------------------------------------------------------------------------ paths
def repo_root():
    if bpy is not None and bpy.data.filepath:
        return os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), ".."))
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    return os.path.abspath(os.path.join(here, "..", ".."))


ROOT = repo_root()


# ------------------------------------------------------------------------------------------------ pixels
class Canvas:
    """A small image painted pixel by pixel with palette colours. (0, 0) is the bottom-left, like Blender."""

    def __init__(self, w, h, fill="black"):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y % self.h][x % self.w]

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, c)

    def frame(self, x0, y0, x1, y1, c):
        for x in range(x0, x1):
            self.put(x, y0, c)
            self.put(x, y1 - 1, c)
        for y in range(y0, y1):
            self.put(x0, y, c)
            self.put(x1 - 1, y, c)

    def noise(self, x0, y0, x1, y1, colours, chance, rng):
        chance *= STYLE["dirt"]
        for y in range(y0, y1):
            for x in range(x0, x1):
                if rng.random() < chance:
                    self.put(x, y, rng.choice(colours))

    def blotch(self, colours, count, rng, area=None, size=(2, 5)):
        """Irregular patches (dirt, stains, chipped paint): clusters read better than single-pixel noise."""
        x0, y0, x1, y1 = area or (0, 0, self.w, self.h)
        for _ in range(round(count * STYLE["dirt"])):
            x, y, col = rng.randrange(x0, x1), rng.randrange(y0, y1), rng.choice(colours)
            for _ in range(rng.randrange(*size) ** 2 // 2 + 1):
                if x0 <= x < x1 and y0 <= y < y1:
                    self.put(x % self.w, y % self.h, col)
                x += rng.choice((-1, 0, 1))
                y += rng.choice((-1, 0, 1))

    def text(self, x, y, s, c, scale=1, wide_gap=-1):
        """Pixel text (3 x 5 glyphs, 1 px apart) with its bottom-left at (x, y). Returns the width.
        wide_gap: the gap after that letter is 1 px wider (ctext uses it to centre exactly)."""
        cx = x
        for i, ch in enumerate(s.upper()):
            if i == wide_gap + 1:
                cx += 1
            g = FONT.get(ch)
            if g is None:
                cx += 2 * scale
                continue
            for r, row in enumerate(g):
                for k, bit in enumerate(row):
                    if bit == "#":
                        self.rect(cx + k * scale, y + (4 - r) * scale, cx + (k + 1) * scale, y + (5 - r) * scale, c)
            cx += (len(g[0]) + 1) * scale
        return cx - x - scale

    def ctext(self, x0, x1, y, s, c, scale=1):
        """Pixel text centred between columns x0 and x1. The leftover space must split evenly (else one side
        gets a pixel more, which shows at this size), so an odd leftover widens the middle gap by a pixel."""
        w = Canvas.text_width(s, scale)
        gap = -1
        if (x1 - x0 - w) % 2:          # odd leftover: widen the middle gap a pixel so both sides match
            if len(s) < 2:
                raise ValueError("text %r (%d px) can't be centred in %d px" % (s, w, x1 - x0))
            gap, w = (len(s) - 2) // 2, w + 1
        return self.text(x0 + (x1 - x0 - w) // 2, y, s, c, scale, gap)

    @staticmethod
    def text_width(s, scale=1):
        return sum(((len(FONT[ch][0]) if ch in FONT else 1) + 1) * scale for ch in s.upper()) - scale

    def flat(self):
        out = []
        for row in self.px:
            for c in row:
                out += rgba(c)
        return out


FONT = {
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "K": ["#.#", "##.", "#..", "##.", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"], "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"], "O": [".#.", "#.#", "#.#", "#.#", ".#."],
    "P": ["##.", "#.#", "##.", "#..", "#.."], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"], "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "X": ["#.#", "#.#", ".#.", "#.#", "#.#"], "Z": ["###", "..#", ".#.", "#..", "###"],
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#", "##", ".#", ".#", ".#"],
    "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
    ".": [".", ".", ".", ".", "#"], "-": ["..", "..", "##", "..", ".."], "!": ["#", "#", "#", ".", "#"],
    "$": [".##", "##.", ".#.", ".##", "##."], "?": ["##.", "..#", ".#.", "...", ".#."], "/": ["..#", "..#", ".#.", "#..", "#.."],
}


# ------------------------------------------------------------------------------------------------ kit textures
def paint_ext_block(rng):
    """Painted cinder block, a red base band (0-0.56 m), grime, the odd bullet hole."""
    c = Canvas(64, 64, "concrete")
    for y in range(64):
        for x in range(64):
            row = y // 4
            off = 4 if row % 2 else 0
            mortar = y % 4 == 0 or (x + off) % 8 == 0
            c.put(x, y, "concrete" if mortar else "bone")
    c.blotch(["concrete"], 14, rng, size=(2, 6))
    c.rect(0, 0, 64, 9, "red")
    c.rect(0, 9, 64, 10, "rust")
    c.blotch(["rust"], 6, rng, area=(0, 0, 64, 9), size=(2, 4))      # chipped paint
    c.noise(0, 0, 64, 3, ["wood_mid"], 0.25, rng)                    # splash dirt
    for _ in range(9):                                                # rain streaks
        x = rng.randrange(64)
        for y in range(rng.randrange(20, 40), rng.randrange(44, 64)):
            if rng.random() < 0.7:
                c.put(x, y, "concrete" if c.get(x, y) == "bone" else c.get(x, y))
    for _ in range(5):                                                # bullet holes
        x, y = rng.randrange(2, 62), rng.randrange(12, 60)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.put(x + dx, y + dy, "steel")
        c.put(x, y, "black")
    return c


def paint_int_wall(rng):
    c = Canvas(64, 64, "bone")
    c.blotch(["concrete"], 10, rng, size=(2, 6))
    c.rect(0, 0, 64, 2, "wood_dark")
    c.blotch(["concrete"], 8, rng, area=(0, 2, 64, 8), size=(2, 4))  # scuffs
    for _ in range(3):                                                # peeling patches
        x, y = rng.randrange(64), rng.randrange(14, 56)
        c.rect(x, y, x + rng.randrange(2, 5), y + rng.randrange(1, 3), "concrete")
    return c


def paint_floor_tile(rng):
    c = Canvas(64, 64, "bone")
    for y in range(64):
        for x in range(64):
            if x % 8 == 0 or y % 8 == 0:
                c.put(x, y, "steel_light")
            elif (x // 8 + y // 8) % 2:
                c.put(x, y, "concrete")
    c.blotch(["sand"], 8, rng, size=(2, 5))                          # dirt
    for _ in range(4):                                                # cracked tiles
        x, y = rng.randrange(8) * 8, rng.randrange(8) * 8
        for k in range(1, 8):
            c.put(x + k, y + k if k % 3 else y + k - 1, "steel")
    return c


def paint_ceiling(rng):
    c = Canvas(64, 64, "bone")
    for y in range(64):
        for x in range(64):
            if x % 8 == 0 or y % 8 == 0:
                c.put(x, y, "steel_light")
    for x0, y0 in ((9, 25), (41, 57 - 32)):                           # light panels (2 per 4 m)
        c.rect(x0, y0, x0 + 14, y0 + 6, "steel_light")
        c.rect(x0 + 1, y0 + 1, x0 + 13, y0 + 5, "bone")
    c.rect(24, 40, 32, 48, "black")                                   # a missing panel
    c.blotch(["sand"], 4, rng, size=(3, 6))                          # water stains
    return c


def paint_roof(rng):
    c = Canvas(64, 64, "iron")
    c.noise(0, 0, 64, 64, ["iron_dark"], 0.12, rng)
    c.blotch(["steel"], 6, rng, size=(2, 5))
    return c


def paint_concrete(rng):
    c = Canvas(64, 64, "concrete")
    c.blotch(["steel_light", "sand"], 18, rng, size=(2, 6))
    for k in range(64):
        c.put(k, 0, "steel")
        c.put(0, k, "steel")
        c.put(k, 32, "steel")
        c.put(32, k, "steel")
    for _ in range(3):                                                # oil stains
        x, y, r = rng.randrange(64), rng.randrange(64), rng.randrange(3, 6)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r and rng.random() < 0.8:
                    c.put((x + dx) % 64, (y + dy) % 64, "iron" if dx * dx + dy * dy < r * r / 3 else "steel")
    for _ in range(2):                                                # cracks
        x, y = rng.randrange(64), rng.randrange(64)
        for _ in range(18):
            c.put(x % 64, y % 64, "iron")
            x += rng.choice((1, 1, 0))
            y += rng.choice((1, 0, -1))
    return c


def paint_metal(rng):
    c = Canvas(64, 64, "steel")
    c.blotch(["steel_light"], 6, rng, size=(2, 4))
    for x in range(0, 64, 8):
        for y in range(64):
            c.put(x, y, "iron")
    c.noise(0, 0, 64, 64, ["rust"], 0.02, rng)
    return c


def paint_wood(rng):
    c = Canvas(64, 64, "wood")
    for y in range(64):
        for x in range(64):
            if y % 4 == 0:
                c.put(x, y, "wood_mid")
            elif rng.random() < 0.08:
                c.put(x, y, "wood_light")
    return c


def paint_canopy_ceiling(rng):
    c = Canvas(64, 64, "bone")
    for y in range(64):
        for x in range(64):
            if y % 4 == 0:
                c.put(x, y, "steel_light")                             # metal panel seams
    for x0, y0 in ((8, 12), (40, 44)):                                # floodlights
        c.rect(x0, y0, x0 + 16, y0 + 8, "iron_dark")
        c.rect(x0 + 1, y0 + 1, x0 + 15, y0 + 7, "steel_light" if x0 == 8 else "black")  # one is smashed
    c.blotch(["sand"], 5, rng, size=(2, 5))
    return c


def paint_flat(colour):
    def paint(rng):
        c = Canvas(8, 8, colour)
        return c
    return paint


def paint_post(rng):
    """Canopy post, fitted to the whole post (0.5 x 4.6 m): hazard stripes at the bottom, red band at the top."""
    c = Canvas(8, 64, "bone")
    for y in range(12):
        for x in range(8):
            c.put(x, y, "hazard_yellow" if ((x + y) // 3) % 2 else "black")
    c.rect(0, 56, 8, 64, "red")
    c.blotch(["concrete"], 4, rng, area=(0, 12, 8, 56), size=(2, 4))
    return c


def paint_cardboard(rng):
    c = Canvas(16, 16, "wood_pale")
    c.noise(0, 0, 16, 16, ["wood_light", "sand"], 0.15, rng)
    c.rect(7, 0, 9, 16, "sand")                                       # tape
    return c


def paint_glass(rng):
    """Pale glass with a couple of diagonal glints (drawn see-through: the material's alpha)."""
    c = Canvas(16, 16, "steel_light")
    for k in range(16):
        c.put(k, 15 - k, "bone")
        if k < 15:
            c.put(k + 1, 15 - k, "bone")
        if 4 <= k < 10:
            c.put(k, 13 - k, "bone")
    return c


def paint_brick(rng):
    """Red brick (0.5 x 0.25 m bricks), soot and faded patches. (The concrete base is its own strip: see dress_shops.)"""
    c = Canvas(64, 64, "concrete")
    for row in range(16):
        off = 4 if row % 2 else 0
        for k in range(8):
            col = rng.choice(("red", "red", "rust", "red", "wood_mid"))
            c.rect((k * 8 + off + 1) % 64, row * 4 + 1, (k * 8 + off + 1) % 64 + 7, row * 4 + 4, col)
            if (k * 8 + off + 1) % 64 + 7 > 64:
                c.rect(0, row * 4 + 1, (k * 8 + off + 8) % 64, row * 4 + 4, col)
    c.blotch(["iron", "rust"], 6, rng, size=(2, 5))
    return c


def paint_int_tile(rng):
    """Laundromat: white tiles to 1.25 m, a blue band, painted plaster above."""
    c = Canvas(64, 64, "bone")
    for y in range(20):
        for x in range(64):
            if x % 5 == 0 or y % 5 == 0:
                c.put(x, y, "steel_light")
    c.rect(0, 20, 64, 22, "sky_blue")
    c.blotch(["concrete"], 8, rng, area=(0, 22, 64, 64), size=(2, 5))
    c.blotch(["sand"], 4, rng, area=(0, 0, 64, 20), size=(2, 3))
    return c


def paint_int_warm(rng):
    """Shoe store: dark wood panelling to 1 m, warm paint above."""
    c = Canvas(64, 64, "wood_pale")
    c.rect(0, 0, 64, 16, "wood_mid")
    for x in range(0, 64, 8):
        c.rect(x, 0, x + 1, 16, "wood_dark")
    c.rect(0, 16, 64, 17, "wood_dark")
    c.blotch(["wood_light", "sand"], 8, rng, area=(0, 17, 64, 64), size=(2, 5))
    return c


def _soot_edge(rng, n, start, step):
    """A wrapping random walk (one value per column), for soot lines that tile."""
    walk = [0]
    for _ in range(n - 1):
        walk.append(walk[-1] + rng.choice((-step, 0, step)))
    drift = walk[-1] / n
    return [start + round(w - drift * k) for k, w in enumerate(walk)]


def paint_int_soot(rng):
    """Burned out: smoke-blackened from the ceiling down, in big soft bands (4 px columns, no speckle)."""
    c = Canvas(64, 64, "concrete")
    top = _soot_edge(rng, 16, 34, 2)
    for col, h in enumerate(top):
        c.rect(col * 4, h, col * 4 + 4, 64, "iron")
        c.rect(col * 4, h + 8, col * 4 + 4, 64, "iron_dark")
        c.rect(col * 4, h + 18, col * 4 + 4, 64, "black")
    c.rect(0, 0, 64, 2, "iron")                                       # scorched skirting
    return c


def paint_ceiling_soot(rng):
    c = Canvas(64, 64, "iron_dark")
    for y in range(64):
        for x in range(64):
            if x % 8 == 0 or y % 8 == 0:
                c.put(x, y, "iron")
    for x0, y0 in ((16, 24), (40, 48)):                               # panels burned through
        c.rect(x0, y0, x0 + 8, y0 + 8, "black")
    return c


def paint_render(rng):
    """Painted render (stucco) for shop fronts: pale, with a few big weathered patches."""
    c = Canvas(64, 64, "bone")
    for _ in range(5):
        x, y = rng.randrange(0, 64, 4), rng.randrange(0, 64, 4)
        w, h = rng.choice((8, 12, 16)), rng.choice((4, 8))
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                c.put(xx % 64, yy % 64, "concrete" if rng.random() < 0.85 else "bone")
    for _ in range(4):                                                # rain streaks
        x = rng.randrange(64)
        c.rect(x, rng.randrange(20, 50), x + 1, 64, "concrete")
    return c


def paint_floor_wood(rng):
    c = Canvas(64, 64, "wood_light")
    for y in range(64):
        for x in range(64):
            if y % 4 == 0:
                c.put(x, y, "wood_mid")
            elif (x + (y // 4) * 13) % 24 == 0:
                c.put(x, y, "wood_mid")                            # plank ends
            elif rng.random() < 0.06:
                c.put(x, y, "wood_pale")
    c.blotch(["wood"], 6, rng, size=(2, 5))
    return c


def paint_floor_burnt(rng):
    """The shop's floor tiles, scorched: each tile darkens with how close it was to the fire (a smooth burn field
    that wraps), a few tiles cracked or gone to bare concrete."""
    c = Canvas(64, 64, "bone")
    fires = [(rng.randrange(64), rng.randrange(64), rng.uniform(14, 26)) for _ in range(3)]

    def burn(x, y):
        v = 0.0
        for fx, fy, r in fires:
            dx, dy = min(abs(x - fx), 64 - abs(x - fx)), min(abs(y - fy), 64 - abs(y - fy))
            v = max(v, 1.0 - math.hypot(dx, dy) / r)
        return v
    shades = ("bone", "concrete", "steel", "iron", "iron_dark")
    for ty in range(8):
        for tx in range(8):
            b_ = burn(tx * 8 + 4, ty * 8 + 4) + rng.uniform(-0.12, 0.12)
            k = max(0, min(4, int(b_ * 5)))
            if (tx + ty) % 2 and k == 0:
                k = 1                                                  # the checker, like the other shops
            gone = rng.random() < 0.06
            c.rect(tx * 8 + 1, ty * 8 + 1, tx * 8 + 8, ty * 8 + 8, "concrete" if gone else shades[k])
            if not gone and k >= 2 and rng.random() < 0.3:             # soot creeping over the tile edge
                c.rect(tx * 8 + 1, ty * 8 + 1, tx * 8 + 4, ty * 8 + 4, shades[min(4, k + 1)])
            if rng.random() < 0.12:                                    # a crack
                for d in range(1, 7):
                    c.put(tx * 8 + d, ty * 8 + (d if d % 3 else d - 1), "iron_dark")
    for y in range(64):                                                # grout
        for x in range(64):
            if x % 8 == 0 or y % 8 == 0:
                c.put(x, y, "iron" if burn(x, y) > 0.3 else "steel_light")
    return c


KIT = {
    "brick": paint_brick, "render": paint_render, "ceiling_soot": paint_ceiling_soot, "int_tile": paint_int_tile, "int_warm": paint_int_warm, "int_soot": paint_int_soot,
    "floor_wood": paint_floor_wood, "floor_burnt": paint_floor_burnt,
    "yellow": paint_flat("hazard_yellow"), "blue": paint_flat("sky_blue"), "olive": paint_flat("olive"),
    "steel_light": paint_flat("steel_light"),
    "ext_block": paint_ext_block, "int_wall": paint_int_wall, "floor_tile": paint_floor_tile,
    "ceiling": paint_ceiling, "roof": paint_roof, "concrete": paint_concrete, "metal": paint_metal,
    "wood": paint_wood, "canopy_ceiling": paint_canopy_ceiling, "post": paint_post, "cardboard": paint_cardboard,
    "glass": paint_glass, "trim": paint_flat("steel"), "trim_dark": paint_flat("iron_dark"),
    "red": paint_flat("red"), "bone": paint_flat("bone"), "black": paint_flat("black"),
}


# ------------------------------------------------------------------------------------------------ decal atlas
class Atlas:
    """Regions of one square decal image (32 px/m), packed in rows."""

    def __init__(self, size=256):
        self.c = Canvas(size, size, "black")
        self.regions = {}
        self.x = self.y = self.row_h = 0

    def add(self, name, w, h, painter):
        if self.x + w > self.c.w:
            self.x, self.y, self.row_h = 0, self.y + self.row_h + 1, 0
        assert self.y + h <= self.c.h, f"decal atlas full at {name}"
        sub = Canvas(w, h, "black")
        painter(sub)
        for yy in range(h):
            for xx in range(w):
                self.c.put(self.x + xx, self.y + yy, sub.px[yy][xx])
        s = self.c.w
        self.regions[name] = ((self.x + 0.5) / s, (self.y + 0.5) / s, (self.x + w - 0.5) / s, (self.y + h - 0.5) / s)
        self.x += w + 1
        self.row_h = max(self.row_h, h)


def gas_station_decals(rng):
    a = Atlas(512)

    def fascia(c):        # 2 m x 1 m, repeats along the canopy edge
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, 0, c.w, 3, "iron_dark")
        c.rect(0, c.h - 3, c.w, c.h, "iron_dark")
        c.rect(0, 8, c.w, 20, "red")
        c.rect(0, 22, c.w, 25, "red")
        c.blotch(["concrete"], 4, rng, area=(0, 3, c.w, c.h - 3), size=(2, 4))

    def logo(c):          # 2.5 m x 1 m: the station's sign on the canopy
        c.rect(0, 0, c.w, c.h, "red")
        c.frame(0, 0, c.w, c.h, "iron_dark")
        c.frame(2, 2, c.w - 2, c.h - 2, "bone")
        w = Canvas.text_width("GAS", 4)
        c.ctext(0, c.w, 6, "GAS", "bone", 4)
        c.blotch(["rust"], 3, rng, area=(3, 3, c.w - 3, c.h - 3), size=(2, 4))

    def pump_front(c):    # 1 m x 1.5 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, 0, c.w, 6, "red")
        c.rect(0, c.h - 8, c.w, c.h, "red")
        c.rect(4, 26, c.w - 4, 38, "iron_dark")                         # display
        c.rect(6, 33, c.w - 6, 36, "black")
        c.text(7, 28, "0.00", "extract_green")
        c.rect(5, 14, 13, 22, "iron_dark")                              # keypad
        for ky in range(15, 21, 2):
            for kx in range(6, 12, 2):
                c.put(kx, ky, "steel_light")
        c.rect(c.w - 12, 12, c.w - 5, 23, "black")                       # nozzle bay
        c.blotch(["concrete"], 4, rng, size=(2, 4))

    def pump_smashed(c):
        pump_front(c)
        for _ in range(40):                                              # smashed screen
            c.put(rng.randrange(4, c.w - 4), rng.randrange(26, 38), rng.choice(("black", "steel", "steel_light")))
        c.blotch(["iron_dark", "black"], 10, rng, size=(3, 7))         # soot

    def pump_side(c):     # 0.6 m x 1.5 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, 0, c.w, 6, "red")
        c.rect(0, c.h - 8, c.w, c.h, "red")
        c.rect(3, 18, c.w - 3, 30, "red")
        c.text(4, 21, "95", "bone")
        c.blotch(["concrete"], 4, rng, size=(2, 4))

    def price_board(c):   # 1.5 m x 2 m
        c.rect(0, 0, c.w, c.h, "iron_dark")
        c.rect(2, c.h - 22, c.w - 2, c.h - 2, "red")
        w = Canvas.text_width("GAS", 3)
        c.ctext(0, c.w, c.h - 19, "GAS", "bone", 3)
        rows = (("95", "4.1_"), ("98", "_._9"), ("DSL", "3.8_"))
        for k, (fuel, price) in enumerate(rows):
            y = c.h - 34 - k * 12
            c.rect(2, y - 2, c.w - 2, y + 9, "black")
            c.text(4, y, fuel, "hazard_yellow")
            c.text(c.w - 4 - Canvas.text_width(price.replace("_", "8")), y, price.replace("_", " "), "hazard_yellow")
        c.blotch(["rust"], 4, rng, size=(2, 4))

    def market(c):        # 3 m x 0.5 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "red")
        w = Canvas.text_width("MARKET 24H", 2)
        c.ctext(0, c.w, 3, "MARKET 24H", "red", 2)
        c.blotch(["concrete"], 4, rng, area=(1, 1, c.w - 1, c.h - 1), size=(2, 3))

    def fridge(c):        # 3 m x 2 m: three glass doors of drinks, half sold out
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, c.h - 8, c.w, c.h, "red")
        dw = (c.w - 4) // 3
        for d in range(3):
            x0 = 2 + d * dw
            c.rect(x0, 4, x0 + dw - 2, c.h - 10, "steel")
            c.rect(x0 + 1, 5, x0 + dw - 3, c.h - 11, "iron_dark")
            for shelf in range(5):
                y = 7 + shelf * 9
                c.rect(x0 + 1, y - 1, x0 + dw - 3, y, "steel_light")
                for k in range(x0 + 2, x0 + dw - 4, 3):
                    if rng.random() < 0.45:
                        col = rng.choice(("red", "extract_green", "hazard_yellow", "sky_blue", "bone"))
                        c.rect(k, y, k + 2, y + 6, col)
            c.rect(x0 + dw - 5, c.h // 2 - 4, x0 + dw - 4, c.h // 2 + 4, "steel_light")   # handle
        for _ in range(30):                                              # one door smashed
            c.put(rng.randrange(2, 2 + dw), rng.randrange(4, c.h - 10), rng.choice(("steel_light", "black")))

    def products(c):      # 3 m x 1.4 m: the side of a shop shelf
        c.rect(0, 0, c.w, c.h, "steel")
        for shelf in range(4):
            y = 3 + shelf * 11
            c.rect(0, y - 2, c.w, y, "iron_dark")
            x = 1
            while x < c.w - 3:
                w = rng.randrange(2, 5)
                if rng.random() < 0.5:
                    col = rng.choice(("red", "hazard_yellow", "sky_blue", "extract_green", "bone", "wood_light", "olive"))
                    c.rect(x, y, x + w, y + rng.randrange(4, 8), col)
                x += w + 1
        c.rect(0, 0, c.w, 2, "iron_dark")

    def counter(c):       # 3 m x 1 m
        c.rect(0, 0, c.w, c.h, "wood")
        for x in range(0, c.w, 8):
            c.rect(x, 0, x + 1, c.h, "wood_mid")
        c.rect(0, 0, c.w, 3, "wood_dark")
        c.rect(30, 8, 62, 26, "bone")                                    # poster
        c.ctext(30, 62, 18, "LOTTO", "red")
        c.ctext(30, 62, 10, "WIN!", "red")
        c.blotch(["wood_dark"], 4, rng, area=(0, 0, 28, c.h), size=(2, 4))

    def cigs(c):          # 2.7 m x 1 m
        c.rect(0, 0, c.w, c.h, "iron_dark")
        for y in range(2, c.h - 2, 6):
            for x in range(2, c.w - 2, 3):
                if rng.random() < 0.3:
                    c.rect(x, y, x + 2, y + 4, rng.choice(("bone", "red", "sky_blue", "olive_light")))

    def ice(c):           # 1.6 m x 1 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "steel_light")
        c.ctext(0, c.w, 6, "ICE", "sky_blue", 4)
        c.blotch(["rust", "concrete"], 5, rng, size=(2, 4))

    def graffiti(c):      # 3 m x 1 m: stencil spray, black with drips
        c.rect(0, 0, c.w, c.h, "clear")
        w = Canvas.text_width("NO FUEL", 3)
        x0 = (c.w - w) // 2
        c.text(x0, 10, "NO FUEL", "bone", 3)
        for x in range(x0, x0 + w):
            if c.get(x, 10) == "bone" and rng.random() < 0.4:
                for y in range(10 - rng.randrange(2, 8), 10):
                    c.put(x, y, "bone")

    def closed(c):        # 0.6 m x 0.4 m paper notice
        c.rect(0, 0, c.w, c.h, "bone")
        c.ctext(0, c.w, 6, "CLOSED", "black")
        c.rect(2, 3, c.w - 2, 4, "steel")

    def magazines(c):     # 1.4 m x 1.3 m: rack of magazines and papers, a few gone
        c.rect(0, 0, c.w, c.h, "wood_mid")
        for row in range(3):
            y = 3 + row * 13
            c.rect(0, y - 2, c.w, y, "wood_dark")
            for x in range(2, c.w - 6, 7):
                if rng.random() < 0.75:
                    col = rng.choice(("red", "sky_blue", "bone", "hazard_yellow", "olive_light", "extract_green"))
                    c.rect(x, y, x + 6, y + 9, col)
                    c.rect(x + 1, y + 6, x + 5, y + 7, "bone" if col != "bone" else "black")

    def atm(c):           # 0.75 m x 1.7 m
        c.rect(0, 0, c.w, c.h, "steel")
        c.rect(0, c.h - 8, c.w, c.h, "sky_blue")
        c.ctext(0, c.w, c.h - 7, "ATM", "bone")
        c.rect(3, 30, c.w - 3, 42, "black")                                # smashed screen
        for _ in range(12):
            c.put(rng.randrange(3, c.w - 3), rng.randrange(30, 42), rng.choice(("steel_light", "steel")))
        c.rect(4, 18, c.w - 4, 27, "iron")                                  # keypad
        c.rect(5, 12, c.w - 5, 14, "black")                                 # card slot / cash slot

    def clock(c):         # 0.4 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "iron_dark")
        c.rect(c.w // 2, c.h // 2, c.w // 2 + 1, c.h - 3, "black")
        c.rect(c.w // 2, c.h // 2, c.w - 4, c.h // 2 + 1, "black")

    def poster(c):        # 0.6 m x 0.8 m
        c.rect(0, 0, c.w, c.h, "hazard_yellow")
        c.ctext(0, c.w, c.h - 8, "SALE", "red")
        c.rect(2, 4, c.w - 2, 13, "red")
        c.ctext(2, c.w - 2, 6, "50%", "bone")

    def banner(c):        # 2 m x 0.35 m
        c.rect(0, 0, c.w, c.h, "red")
        w = Canvas.text_width("COLD DRINKS", 1)
        c.ctext(0, c.w, 3, "COLD DRINKS", "bone")

    def wet(c):           # 0.3 m x 0.6 m: warning triangle with "!", stripes at the foot
        c.rect(0, 0, c.w, c.h, "hazard_yellow")
        for k in range(8):                                   # triangle, point up, rows y 6..13
            half = (k + 2) // 2
            y = 13 - k
            c.put(c.w // 2 - half, y, "black")
            c.put(c.w // 2 + half - 1, y, "black")
        c.rect(c.w // 2 - 4, 6, c.w // 2 + 4, 7, "black")
        c.rect(c.w // 2 - 1, 9, c.w // 2 + 1, 12, "black")  # "!"
        c.rect(c.w // 2 - 1, 7, c.w // 2 + 1, 8, "black")
        c.rect(1, 2, c.w - 1, 3, "black")
        c.rect(1, 4, c.w - 1, 5, "black")

    a.add("fascia", 64, 32, fascia)
    a.add("magazines", 45, 42, magazines)
    a.add("atm", 24, 54, atm)
    a.add("clock", 13, 13, clock)

    def welcome(c):       # 3.2 x 0.6 m banner inside the entrance
        c.rect(0, 0, c.w, c.h, "sky_blue")
        c.frame(0, 0, c.w, c.h, "bone")
        c.ctext(0, c.w, 6, "WELCOME BACK", "bone", 1)
        c.blotch(["concrete", "black"], 4, rng, size=(2, 4))
    a.add("welcome", 102, 19, welcome)
    a.add("poster", 19, 26, poster)
    a.add("banner", 64, 11, banner)
    a.add("wet", 10, 19, wet)
    a.add("logo", 80, 32, logo)
    a.add("pump_front", 32, 48, pump_front)
    a.add("pump_smashed", 32, 48, pump_smashed)
    a.add("pump_side", 20, 48, pump_side)
    a.add("price_board", 48, 64, price_board)
    a.add("market", 96, 16, market)
    a.add("fridge", 96, 64, fridge)
    a.add("products", 96, 45, products)
    a.add("counter", 96, 32, counter)
    a.add("cigs", 86, 32, cigs)
    a.add("ice", 51, 32, ice)
    a.add("graffiti", 96, 32, graffiti)
    a.add("closed", 26, 13, closed)
    # Graffiti is the only see-through decal (its background is "clear").
    return a


DECALS = {"gas_station_town": gas_station_decals}


# ------------------------------------------------------------------------------------------------ materials
def write_png(path, w, h, rgba_rows):
    """rgba_rows: rows bottom-first of [r, g, b, a] 0-255."""
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in reversed(rgba_rows))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return data


def read_png(path):
    """Minimal reader for 8-bit RGB/RGBA PNGs (what paint programs save). Returns (w, h, rows bottom-first)."""
    with open(path, "rb") as f:
        data = f.read()
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        tag, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (2, 6) and body[12] == 0, f"{path}: save it as 8-bit RGB(A), not interlaced"
            bpp = 4 if ctype == 6 else 3
        elif tag == b"IDAT":
            idat += body
        pos += 12 + n
    raw, stride, rows, prev = zlib.decompress(idat), w * bpp, [], bytearray(w * bpp)
    for y in range(h):
        ft, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([list(line[k:k + bpp]) + ([255] if bpp == 3 else []) for k in range(0, stride, bpp)])
        prev = line
    return w, h, list(reversed(rows))


def styled(canvas, rng):
    """The canvas as RGBA rows (0-255), with the STYLE's colour, outline and fine-grain changes."""
    w, h = canvas.w, canvas.h
    if STYLE["flat"] and canvas.w <= 64 and canvas.h <= 64:      # kit textures (decal atlases are bigger)
        counts = {}
        for row in canvas.px:
            for col in row:
                counts[col] = counts.get(col, 0) + 1
        main = max(counts, key=counts.get)
        canvas = Canvas(w, h, main)
    shade = None
    if STYLE["grime"]:                    # big soft-edged dark patches (8 px cells)
        cells = [[rng.random() for _ in range(w // 8 + 2)] for _ in range(h // 8 + 2)]
        shade = [[1.0 - STYLE["grime"] * max(0.0, cells[y // 8][x // 8] * 1.6 - 0.6) for x in range(w)] for y in range(h)]
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = rgba(canvas.px[y][x])
            if STYLE["outline"]:
                below, left = canvas.px[(y - 1) % h][x], canvas.px[y][(x - 1) % w]
                if (below != canvas.px[y][x] or left != canvas.px[y][x]) and a > 0:
                    r, g, b = r * 0.55, g * 0.55, b * 0.55
            grey = (r + g + b) / 3
            r, g, b = (grey + (c - grey) * STYLE["sat"] for c in (r, g, b))
            k = STYLE["bright"] * (shade[y][x] if shade else 1.0)
            row.append([max(0, min(255, round(c * k * t * 255))) for c, t in zip((r, g, b), STYLE["tint"])]
                       + [round(a * 255)])
        rows.append(row)
    if STYLE["fine"]:                     # every pixel becomes 2 x 2 with a little grain
        fine = []
        for row in rows:
            for _ in range(2):
                line = []
                for px in row:
                    for _ in range(2):
                        k = rng.uniform(0.9, 1.06)
                        line.append([max(0, min(255, round(c * k))) for c in px[:3]] + [px[3]])
                fine.append(line)
        rows = fine
    return rows


class Texture:
    """A kit or decal image: painted (and saved) the first time, loaded from its PNG after that."""

    def __init__(self, name, path, painter, rng):
        self.name, self.path = name, os.path.join(TEX_DIR, os.path.basename(path)) if TEX_DIR else os.path.join(ROOT, path)
        if os.path.exists(self.path) and not REGENERATE_TEXTURES and not TEX_DIR:
            self.w, self.h, rows = read_png(self.path)
        else:
            canvas = painter(rng)
            rows = styled(canvas, random.Random(name))
            self.w, self.h = len(rows[0]), len(rows)
            write_png(self.path, self.w, self.h, rows)
        with open(self.path, "rb") as f:
            self.png = f.read()


def blender_material(name, tex, cutout=False, double_sided=False):
    img = bpy.data.images.get(tex.name)
    if img is None:
        img = bpy.data.images.load(tex.path)
        img.name = tex.name
    mat = bpy.data.materials.get(name)
    if mat is not None:
        bpy.data.materials.remove(mat)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    node = nodes.new("ShaderNodeTexImage")
    node.image = img
    node.interpolation = "Closest"
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    if cutout:   # see-through where the texture's alpha is 0
        mat.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(mat, "blend_method"):
            mat.blend_method = "CLIP"
    mat.use_backface_culling = not double_sided
    return mat


# ------------------------------------------------------------------------------------------------ geometry
def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return v_scale(a, 1.0 / length)


def rot(p, yaw, pitch):
    """Godot basis Ry(yaw) * Rx(pitch) applied to p (degrees)."""
    x, y, z = p
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    y, z = y * cp - z * sp, y * sp + z * cp
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return (x * cy + z * sy, y, -x * sy + z * cy)


def face_frame(n):
    """(right, up) of a face with normal n, as seen from outside."""
    if abs(n[1]) > 0.7:
        return ((1, 0, 0), (0, 0, -1)) if n[1] > 0 else ((1, 0, 0), (0, 0, 1))
    up = (0.0, 1.0, 0.0)
    return norm(cross(v_scale(n, -1.0), up)), up


class Builder:
    def __init__(self):
        self.verts, self.faces, self.uvs, self.mats, self.normals = [], [], [], [], []
        self.mat_names = []
        self.groups, self.group = [], None     # faces of one small item share a group: one baked light for all

    def mat_index(self, name):
        if name not in self.mat_names:
            self.mat_names.append(name)
        return self.mat_names.index(name)

    def poly(self, pts, normal, mat, uv):
        """pts: corners (Godot space); turned to face `normal`. uv: a mapping, see the uv_* functions."""
        e1, e2 = v_sub(pts[1], pts[0]), v_sub(pts[2], pts[0])
        if dot(cross(e1, e2), normal) < 0:
            pts = list(reversed(pts))
        base = len(self.verts)
        self.verts += [tuple(p) for p in pts]
        self.normals.append(norm(tuple(normal)))
        self.faces.append(list(range(base, base + len(pts))))
        self.uvs.append(uv(pts, normal))
        self.mats.append(self.mat_index(mat))
        self.groups.append(self.group)

    def box(self, center, size, yaw=0.0, pitch=0.0, style=None):
        """style(normal, face centre, corners) -> (material, uv) or None to leave the face out."""
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        for axis in range(3):
            for sgn in (-1, 1):
                n_local = [0, 0, 0]
                n_local[axis] = sgn
                a, b = [k for k in range(3) if k != axis]
                corners = []
                for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = sgn * (hx, hy, hz)[axis]
                    p[a] = sa * (hx, hy, hz)[a]
                    p[b] = sb * (hx, hy, hz)[b]
                    corners.append(v_add(rot(tuple(p), yaw, pitch), center))
                n = norm(rot(tuple(n_local), yaw, pitch))
                mid = v_scale(v_add(corners[0], corners[2]), 0.5)
                got = style(n, mid, corners) if style else ("trim", uv_world())
                if got:
                    self.poly(corners, n, got[0], got[1])

    def to_object(self, name, materials, coll):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([(p[0], -p[2], p[1]) for p in self.verts], [], self.faces)
        mesh.update()
        uv_layer = mesh.uv_layers.new(name="UVMap")
        loop = 0
        for poly, uvs in zip(mesh.polygons, self.uvs):
            for k, li in enumerate(poly.loop_indices):
                uv_layer.data[li].uv = uvs[k]
            loop += len(uvs)
        for name_ in self.mat_names:
            mesh.materials.append(materials[name_])
        for poly, m in zip(mesh.polygons, self.mats):
            poly.material_index = m
        obj = bpy.data.objects.new(name, mesh)
        coll.objects.link(obj)
        return obj


def uv_world(tile=TILE_M, offset=(0.0, 0.0)):
    """Tiling texture projected in world meters (kit textures)."""
    def f(pts, n):
        r, u = face_frame(n)
        return [(dot(p, r) / tile + offset[0], dot(p, u) / tile + offset[1]) for p in pts]
    return f


def uv_fit(rect, flip_u=False):
    """The face shows exactly `rect` (u0, v0, u1, v1) of the image."""
    def f(pts, n):
        r, u = face_frame(n)
        us, vs = [dot(p, r) for p in pts], [dot(p, u) for p in pts]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        out = []
        for a, b in zip(us, vs):
            s = (a - u0) / ((u1 - u0) or 1)
            if flip_u:
                s = 1 - s
            t = (b - v0) / ((v1 - v0) or 1)
            out.append((rect[0] + s * (rect[2] - rect[0]), rect[1] + t * (rect[3] - rect[1])))
        return out
    return f


# ------------------------------------------------------------------------------------------------ building pieces
class Ctx:
    def __init__(self, data, decals, footprint):
        self.data, self.decals, self.footprint = data, decals, footprint
        self.b = Builder()
        self.rng = random.Random(BUILDING)

    def d(self, name, flip=False):
        return uv_fit(self.decals.regions[name], flip)


def wall_style(fp, ext="ext_block", inner=None, storey=3.0):
    """Building shell: outside faces `ext`, inside faces `inner(face centre)` (plaster), openings' edges trim."""
    x0, z0, x1, z1 = fp

    def style(n, mid, corners):
        if abs(n[1]) > 0.7:
            if n[1] < 0 and mid[1] < 0.01:
                return None                                   # bottom on the floor
            if n[1] > 0 and mid[1] > storey - 0.01 and abs(mid[1] / storey - round(mid[1] / storey)) < 0.01:
                return None                                   # hidden under a slab
            return ("trim", uv_world(1.0))
        # On the outside plane and facing out (wall ends at the corners too): outside material, so corners join.
        if ((n[0] > 0.7 and abs(mid[0] - x1) < 0.05) or (n[0] < -0.7 and abs(mid[0] - x0) < 0.05)
                or (n[2] > 0.7 and abs(mid[2] - z1) < 0.05) or (n[2] < -0.7 and abs(mid[2] - z0) < 0.05)):
            return (ext, uv_world())
        dist = min(mid[0] - x0, x1 - mid[0], mid[2] - z0, z1 - mid[2])
        if dist < -0.05:
            return (ext, uv_world())
        if dist > 0.05:
            return (inner(mid) if inner else "int_wall", uv_world())
        return ("trim", uv_world(1.0))
    return style


# Plain materials for gray-box colours that aren't walls (ramps, rails, scorch marks).
SHELL_COLOURS = {"wood": "wood", "metal": "metal", "scorch": "black", "concrete": "concrete"}


def shell_box(ctx, row):
    c, s = row["pos"], row["size"]
    colour = row["colour"]
    b = ctx.b
    cfg = SHELLS.get(BUILDING_NAME[0], {})
    if colour == "slab":
        floor = cfg.get("floor", lambda m: "floor_tile")
        ceiling = cfg.get("ceiling", lambda m: "ceiling")
        b.box(c, s, row["yaw"], row["pitch"], style=lambda n, m, k: None if abs(n[1]) > 0.7 else ("trim", uv_world(1.0)))
        # Top and bottom cut where the rooms change (a different floor in each shop).
        x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
        z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
        cuts = [x0] + [x for x in cfg.get("x_splits", ()) if x0 < x < x1] + [x1]
        zcuts = [z0] + [z for z in cfg.get("z_splits", ()) if z0 < z < z1] + [z1]
        yt, yb = c[1] + s[1] / 2, c[1] - s[1] / 2
        for a, e in zip(cuts, cuts[1:]):
            for za, ze in zip(zcuts, zcuts[1:]):
                mid = ((a + e) / 2, c[1], (za + ze) / 2)
                b.poly([(a, yt, za), (e, yt, za), (e, yt, ze), (a, yt, ze)], (0, 1, 0), floor(mid), uv_world())
                if c[1] > 0.5:
                    b.poly([(a, yb, za), (e, yb, za), (e, yb, ze), (a, yb, ze)], (0, -1, 0), ceiling(mid), uv_world())
    elif colour == "roof":
        side = cfg.get("roof_side", "red")
        ceiling = cfg.get("ceiling", lambda m: "ceiling")

        def style(n, m, k):
            if n[1] > 0.7:
                return ("roof", uv_world())
            if n[1] < -0.7:
                return (ceiling(m), uv_world())
            return (side, uv_world())
        b.box(c, s, row["yaw"], row["pitch"], style=style)
    elif colour == "wood" and abs(row["pitch"]) > 10:
        stairs(ctx, c, s, row["yaw"], row["pitch"])
    elif colour in SHELL_COLOURS:
        mat = SHELL_COLOURS[colour]
        b.box(c, s, row["yaw"], row["pitch"], style=lambda n, m, k: (mat, uv_world(2.0)))
    else:
        style = wall_style(ctx.footprint, cfg.get("ext", "ext_block"), cfg.get("inner"))
        if row["yaw"] or row["pitch"]:
            b.box(c, s, row["yaw"], row["pitch"], style=style)
        else:
            split_box(b, c, s, style, cfg.get("x_lines", ()), cfg.get("z_lines", ()), (3.0, 6.0))


def split_box(b, c, s, style, xcuts, zcuts, ycuts):
    """An unturned wall box whose side faces are cut where rooms and storeys change (the building's room lines),
    so each piece takes the paint of the room it faces (a long wall face used to take one room's paint for all)."""
    lo = [c[k] - s[k] / 2 for k in range(3)]
    hi = [c[k] + s[k] / 2 for k in range(3)]
    cuts = (tuple(xcuts), tuple(ycuts), tuple(zcuts))
    for axis in range(3):
        for sgn in (-1, 1):
            n = [0.0, 0.0, 0.0]
            n[axis] = float(sgn)
            a, e = [k for k in range(3) if k != axis]
            plane = hi[axis] if sgn > 0 else lo[axis]
            spans = []
            for k in (a, e):
                edges = [lo[k]] + sorted(v for v in cuts[k] if lo[k] + 0.01 < v < hi[k] - 0.01) + [hi[k]]
                spans.append(list(zip(edges, edges[1:])))
            for p0, p1 in spans[0]:
                for q0, q1 in spans[1]:
                    corners = []
                    for u, v in ((p0, q0), (p1, q0), (p1, q1), (p0, q1)):
                        pt = [0.0, 0.0, 0.0]
                        pt[axis], pt[a], pt[e] = plane, u, v
                        corners.append(tuple(pt))
                    mid = v_scale(v_add(corners[0], corners[2]), 0.5)
                    got = style(tuple(n), mid, corners)
                    if got:
                        b.poly(corners, tuple(n), got[0], got[1])


def stairs(ctx, c, s, yaw, pitch):
    """A gray-box ramp drawn as a flight of stairs (owner, 0.17). Players and AI still walk the smooth ramp: each
    tread sits where the ramp passes through its middle, so feet are never more than half a step off."""
    b = ctx.b
    lo = v_add(c, rot((0, s[1] / 2, s[2] / 2), yaw, pitch))        # the ramp's top surface at its low (+z) end
    hi = v_add(c, rot((0, s[1] / 2, -s[2] / 2), yaw, pitch))
    run = math.hypot(hi[0] - lo[0], hi[2] - lo[2])
    rise = hi[1] - lo[1]
    n = max(2, round(rise / 0.2))
    tread = run / n
    along = rot((0, 0, 1), yaw, 0)                                 # risers face along the flight
    for k in range(n):
        t = (k + 0.5) / n
        top = lo[1] + rise * t
        h = rise / n + 0.12
        p = (lo[0] + (hi[0] - lo[0]) * t, top - h / 2, lo[2] + (hi[2] - lo[2]) * t)
        b.box(p, (s[0], h, tread), yaw=yaw,
              style=lambda nn, m, q: ("wood", uv_world(1.0)) if nn[1] > 0.7 or abs(dot(nn, along)) > 0.7
              else ("trim_dark", uv_world(1.0)))
    for side in (-1, 1):                                           # stringers along both sides
        sc = v_add(c, rot((side * (s[0] / 2 + 0.04), -0.05, 0), yaw, pitch))
        b.box(sc, (0.08, 0.35, s[2]), yaw=yaw, pitch=pitch, style=lambda nn, m, q: ("trim_dark", uv_world(1.0)))


def side_of(n):
    """'+x', '-x', '+z', '-z', '+y', '-y'."""
    k = max(range(3), key=lambda i: abs(n[i]))
    return ("+" if n[k] > 0 else "-") + "xyz"[k]


def prop_pump(ctx, c, s, k):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box((c[0], base_y + 0.075, c[2]), (s[0] + 0.3, 0.15, s[2] + 0.5),
          style=lambda n, m, q: None if n[1] < -0.7 else ("concrete", uv_world(2.0)))     # island
    b.box((c[0], base_y + 0.16, c[2]), (s[0] + 0.32, 0.02, s[2] + 0.52),
          style=lambda n, m, q: ("red", uv_world()) if n[1] < 0.7 else None)               # curb paint
    body = (0.55, 1.42, 0.95)
    by = base_y + 0.15 + body[1] / 2
    front = "pump_smashed" if k == 1 else "pump_front"

    def style(n, m, q):
        side = side_of(n)
        if side in ("+x", "-x"):
            return ("decals", ctx.d(front))
        if side in ("+z", "-z"):
            return ("decals", ctx.d("pump_side"))
        if side == "+y":
            return ("red", uv_world())
        return None
    b.box((c[0], by, c[2]), body, style=style)
    b.box((c[0], base_y + 0.15 + body[1] + 0.04, c[2]), (0.62, 0.08, 1.05),
          style=lambda n, m, q: ("red", uv_world()) if n[1] > -0.7 else None)               # cap
    for sx in (-1, 1):                                                                       # nozzles + hoses
        nx = c[0] + sx * (body[0] / 2 + 0.06)
        b.box((nx, base_y + 0.95, c[2] + 0.25), (0.1, 0.22, 0.1), style=lambda n, m, q: ("trim_dark", uv_world()))
        b.box((nx + sx * 0.03, base_y + 0.62, c[2] + 0.36), (0.05, 0.6, 0.05), style=lambda n, m, q: ("black", uv_world()))
        b.box((nx + sx * 0.03, base_y + 0.33, c[2] + 0.2), (0.05, 0.05, 0.36), style=lambda n, m, q: ("black", uv_world()))


def prop_post(ctx, c, s):
    ctx.b.box(c, s, style=lambda n, m, q: None if abs(n[1]) > 0.7 else ("post", uv_fit((0, 0, 1, 1))))
    base_y = c[1] - s[1] / 2
    ctx.b.box((c[0], base_y + 0.15, c[2]), (s[0] + 0.2, 0.3, s[2] + 0.2),
              style=lambda n, m, q: None if n[1] < -0.7 else ("concrete", uv_world(2.0)))


def strip_quads(ctx, x0, x1, y0, y1, z, normal, region, tile, axis="x"):
    """A band of decal pieces along x (or z) at depth z, each `tile` meters long."""
    a = x0
    while a < x1 - 1e-6:
        b_ = min(a + tile, x1)
        frac = (b_ - a) / tile
        r = ctx.decals.regions[region]
        rect = (r[0], r[1], r[0] + (r[2] - r[0]) * frac, r[3])
        if axis == "x":
            pts = [(a, y0, z), (b_, y0, z), (b_, y1, z), (a, y1, z)]
        else:
            pts = [(z, y0, a), (z, y0, b_), (z, y1, b_), (z, y1, a)]
        ctx.b.poly(pts, normal, "decals", uv_fit(rect))
        a = b_


def prop_canopy(ctx, c, s):
    b = ctx.b
    top = c[1] + s[1] / 2
    y0, y1 = top - 0.55, top + 0.25          # the fascia is taller than the slab (looks only)
    hx, hz = s[0] / 2 + 0.05, s[2] / 2 + 0.05
    x0, x1, z0, z1 = c[0] - hx, c[0] + hx, c[2] - hz, c[2] + hz
    strip_quads(ctx, x0, x1, y0, y1, z0, (0, 0, -1), "fascia", 2.0, "x")
    strip_quads(ctx, x0, x1, y0, y1, z1, (0, 0, 1), "fascia", 2.0, "x")
    strip_quads(ctx, z0, z1, y0, y1, x0, (-1, 0, 0), "fascia", 2.0, "z")
    strip_quads(ctx, z0, z1, y0, y1, x1, (1, 0, 0), "fascia", 2.0, "z")
    b.poly([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0), "canopy_ceiling", uv_world())
    b.poly([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0), "roof", uv_world())
    # The GAS sign on each side, standing a little proud of the fascia.
    lw = 2.5
    for nrm, pts in (((-1, 0, 0), [(x0 - 0.03, y0 + 0.02, c[2] - lw / 2), (x0 - 0.03, y0 + 0.02, c[2] + lw / 2),
                                    (x0 - 0.03, y1 + 0.2, c[2] + lw / 2), (x0 - 0.03, y1 + 0.2, c[2] - lw / 2)]),
                     ((0, 0, -1), [(c[0] - lw / 2, y0 + 0.02, z0 - 0.03), (c[0] + lw / 2, y0 + 0.02, z0 - 0.03),
                                   (c[0] + lw / 2, y1 + 0.2, z0 - 0.03), (c[0] - lw / 2, y1 + 0.2, z0 - 0.03)]),
                     ((0, 0, 1), [(c[0] - lw / 2, y0 + 0.02, z1 + 0.03), (c[0] + lw / 2, y0 + 0.02, z1 + 0.03),
                                  (c[0] + lw / 2, y1 + 0.2, z1 + 0.03), (c[0] - lw / 2, y1 + 0.2, z1 + 0.03)])):
        b.poly(pts, nrm, "decals", ctx.d("logo"))


def prop_forecourt(ctx, c, s):
    ctx.b.box(c, s, style=lambda n, m, q: ("concrete", uv_world()) if n[1] > 0.7 else None)


def face_decal(region, other, front):
    """Style: the `front` side ('+x'...) shows a decal, the rest `other`; bottoms left out."""
    def style(n, m, q):
        side = side_of(n)
        if side == "-y":
            return None
        if side == front:
            return ("decals", region)
        return (other, uv_world(2.0))
    return style


def prop_counter(ctx, c, s):
    b = ctx.b
    body = (s[0], s[1] - 0.05, s[2] - 0.05)
    b.box((c[0], c[1] - 0.025, c[2] + 0.025), body, style=face_decal(ctx.d("counter"), "wood", "-z"))
    b.box((c[0], c[1] + s[1] / 2 - 0.025, c[2]), (s[0] + 0.06, 0.05, s[2] + 0.06),
          style=lambda n, m, q: None if n[1] < -0.7 else ("bone", uv_world()))
    top = c[1] + s[1] / 2
    register(b, c[0] + s[0] / 2 - 0.5, top, c[2] + 0.08, 1)
    card_reader(b, c[0] + s[0] / 2 - 1.05, top, c[2] - 0.2)
    for k in range(3):                                                   # gum and candy boxes on the customer side
        col = ("red", "yellow", "blue")[k]
        x = c[0] - s[0] / 2 + 0.35 + k * 0.2
        b.group = ("item", len(b.faces))
        b.box((x, top + 0.05, c[2] - 0.18), (0.16, 0.1, 0.12), pitch=-15, style=no_bottom(col, 1.0))
        b.group = None


def register(b, x, top, z, face):
    """A cash register on a counter at (x, top, z); the clerk stands on the `face` side (+1: +z). The cash drawer is
    pulled out, empty but for a few notes; a keypad, a screen for the clerk and a small display for the customer."""
    nb = lambda mat: no_bottom(mat, 1.0)
    b.group = ("item", len(b.faces))
    b.box((x, top + 0.05, z), (0.42, 0.1, 0.42), style=nb("trim_dark"))                              # drawer box
    dz = z + face * 0.3
    b.box((x, top + 0.05, dz), (0.38, 0.08, 0.2), style=lambda n, m, q: None if n[1] < -0.7 else
          (("black", uv_world(1.0)) if n[1] > 0.7 else ("trim_dark", uv_world(1.0))))             # pulled out
    for k in range(4):                                                                             # a few notes
        if k % 2 == 0:
            b.box((x - 0.13 + k * 0.085, top + 0.093, dz - face * 0.03), (0.07, 0.006, 0.12), style=nb("mint"))
    b.box((x, top + 0.085, dz + face * 0.1), (0.38, 0.03, 0.02), style=nb("trim"))                   # its front lip
    b.box((x, top + 0.16, z - face * 0.04), (0.38, 0.12, 0.3), pitch=-10 * face, style=nb("black"))  # keypad body
    for i in range(4):                                                                             # keys
        for j in range(3):
            col = "red" if (i, j) == (3, 0) else ("mint" if (i, j) == (3, 2) else "bone")
            b.box((x - 0.12 + i * 0.065, top + 0.235 - j * 0.01 * face * 0, z - face * 0.1 + face * j * 0.06),
                  (0.045, 0.012, 0.045), pitch=-10 * face, style=nb(col))
    b.box((x + 0.12, top + 0.3, z - face * 0.14), (0.03, 0.18, 0.03), style=nb("black"))             # screen post
    b.box((x + 0.12, top + 0.43, z - face * 0.14), (0.26, 0.17, 0.04), pitch=8 * face, style=nb("black"))
    b.poly(_quad_z(x + 0.12, 0.11, top + 0.43, 0.065, z - face * 0.14 + face * 0.021), (0, 0, face), "glass",
           uv_world(1.0))                                                                          # clerk's screen
    b.box((x - 0.14, top + 0.33, z - face * 0.16), (0.12, 0.06, 0.04), style=nb("black"))            # customer display
    b.poly(_quad_z(x - 0.14, 0.05, top + 0.33, 0.022, z - face * 0.16 - face * 0.021), (0, 0, -face), "mint",
           uv_world(1.0))
    b.box((x - 0.14, top + 0.25, z - face * 0.16), (0.02, 0.1, 0.02), style=nb("black"))
    b.box((x + 0.3, top + 0.06, z), (0.14, 0.12, 0.18), style=nb("bone"))                              # receipt printer
    b.box((x + 0.3, top + 0.125, z + face * 0.05), (0.08, 0.004, 0.12), pitch=20, style=nb("bone"))
    b.group = None


def card_reader(b, x, top, z):
    nb = lambda mat: no_bottom(mat, 1.0)
    b.group = ("item", len(b.faces))
    b.box((x, top + 0.04, z), (0.1, 0.08, 0.1), style=nb("trim_dark"))
    b.box((x, top + 0.11, z), (0.09, 0.03, 0.16), pitch=25, style=nb("black"))
    b.group = None


def _quad_z(x, hw, y, hh, z):
    """A rectangle facing along z: centre (x, y), half sizes hw, hh, on the plane z."""
    return [(x - hw, y - hh, z), (x + hw, y - hh, z), (x + hw, y + hh, z), (x - hw, y + hh, z)]


def prop_cigs(ctx, c, s):
    """Cigarette wall behind the till: shallow shelves of packs."""
    shelving(ctx, c, s, "x", (-1,), "cigs", levels=5, frame="trim_dark", lip="black", fill=0.45)


def prop_shelf(ctx, c, s):
    """Aisle gondola: groceries on both sides."""
    shelving(ctx, c, s, "x", (1, -1), "grocery", levels=4, frame="steel_light", lip="red", fill=0.55)


def prop_fridge(ctx, c, s):
    """Drinks cooler: shelves of cans and bottles behind smashed glass doors, a lit header on top."""
    b = ctx.b
    face = 1 if _front_into(c, 2) == "+z" else -1
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    body = (c[0], c[1] - 0.12, c[2])
    shelving(ctx, body, (s[0], s[1] - 0.24, s[2]), "x", (face,), "drinks", levels=5, frame="bone", lip="black", fill=0.5)
    b.box((c[0], y1 - 0.12, c[2]), (s[0], 0.24, s[2]), style=no_bottom("red", 1.0))
    zf = c[2] + face * s[2] / 2
    n = max(2, round(s[0] / 0.8))
    for k in range(n + 1):                                                # door frames
        x = c[0] - s[0] / 2 + k * s[0] / n
        b.box((x, (y0 + y1 - 0.24) / 2, zf), (0.05, s[1] - 0.24, 0.05), style=no_bottom("black", 1.0))
    for k in range(n):                                                    # broken glass left in the frames
        xa = c[0] - s[0] / 2 + k * s[0] / n
        shards(ctx, xa + 0.03, xa + s[0] / n - 0.03, y0 + 0.1, y1 - 0.3, zf, "x", ctx.rng)


def prop_rack(ctx, c, s, rng):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    hx, hz = s[0] / 2 - 0.03, s[2] / 2 - 0.03
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((c[0] + sx * hx, c[1], c[2] + sz * hz), (0.05, s[1], 0.05), style=lambda n, m, q: ("trim", uv_world()))
    for k in range(4):
        y = base_y + 0.15 + k * 0.6
        b.box((c[0], y, c[2]), (s[0], 0.04, s[2]), style=lambda n, m, q: ("metal", uv_world(2.0)))
        x = c[0] - s[0] / 2 + 0.1
        while x < c[0] + s[0] / 2 - 0.4:
            w = rng.uniform(0.3, 0.6)
            if rng.random() < 0.65:
                h = rng.uniform(0.2, 0.42)
                b.box((x + w / 2, y + 0.02 + h / 2, c[2] + rng.uniform(-0.05, 0.05)), (w, h, s[2] * 0.8),
                      yaw=rng.uniform(-6, 6), style=lambda n, m, q: None if n[1] < -0.7 else ("cardboard", uv_world(1.0)))
            x += w + 0.08


def office_desk(ctx, c, s, with_pc=True):
    """Office desk (shared, refine pass): laminate top, steel legs and a modesty panel, a drawer pedestal with
    handles; a PC on it (monitor, tower, keyboard, mouse). The chair side faces into the room."""
    b = ctx.b
    face = 1 if _front_into(c, 2) == "+z" else -1           # the side the person sits on
    y0 = c[1] - s[1] / 2
    top = y0 + s[1]
    b.box((c[0], top - 0.02, c[2]), (s[0], 0.04, s[2]), style=lambda n, m, q: ("bone", uv_world(2.0)) if n[1] > 0.7
          else ("trim_dark", uv_world()))
    for sx in (-1, 1):
        b.box((c[0] + sx * (s[0] / 2 - 0.04), y0 + (s[1] - 0.04) / 2, c[2]), (0.04, s[1] - 0.04, s[2] - 0.08),
              style=no_bottom("steel_light", 1.0))
    b.box((c[0], y0 + s[1] * 0.55, c[2] - face * (s[2] / 2 - 0.06)), (s[0] - 0.1, s[1] * 0.6, 0.02),
          style=no_bottom("steel_light", 1.0))                                                   # modesty panel
    px = c[0] + s[0] / 2 - 0.27
    b.box((px, y0 + (s[1] - 0.06) / 2 + 0.02, c[2]), (0.4, s[1] - 0.08, s[2] - 0.16), style=no_bottom("steel_light", 1.0))
    for k in range(3):                                                                        # drawers
        y = y0 + 0.12 + k * (s[1] - 0.12) / 3
        b.box((px, y + 0.1, c[2] + face * (s[2] / 2 - 0.075)), (0.36, 0.005, 0.01), style=no_bottom("trim_dark", 1.0))
        b.box((px, y + 0.06, c[2] + face * (s[2] / 2 - 0.07)), (0.12, 0.02, 0.02), style=no_bottom("black", 1.0))
    if with_pc:
        pc(ctx, c[0] - s[0] * 0.12, top, c[2], face, tower_x=c[0] - s[0] / 2 + 0.2, floor=y0)


def pc(ctx, x, top, z, face, tower_x=None, floor=None):
    """Monitor on a stand, keyboard and mouse in front of it, tower under the desk (if tower_x)."""
    b = ctx.b
    back = z - face * 0.12
    b.box((x, top + 0.01, back), (0.22, 0.02, 0.16), style=no_bottom("black", 1.0))                 # stand foot
    b.box((x, top + 0.09, back - face * 0.02), (0.04, 0.16, 0.03), style=no_bottom("black", 1.0))   # neck
    b.box((x, top + 0.31, back), (0.52, 0.32, 0.04), style=lambda n, m, q: None if n[1] < -0.7 else ("black", uv_world()))
    zs = back + face * 0.021
    b.poly([(x - 0.24, top + 0.17, zs), (x + 0.24, top + 0.17, zs), (x + 0.24, top + 0.45, zs), (x - 0.24, top + 0.45, zs)],
           (0, 0, face), "glass", uv_world(1.0))                                                   # dead screen
    b.box((x, top + 0.012, z + face * 0.14), (0.44, 0.024, 0.14), style=lambda n, m, q: None if n[1] < -0.7 else
          (("trim", uv_world(1.0)) if n[1] > 0.7 else ("black", uv_world())))                      # keyboard
    b.box((x + 0.34, top + 0.003, z + face * 0.14), (0.2, 0.006, 0.18), style=no_bottom("blue", 1.0))  # mouse mat
    b.box((x + 0.34, top + 0.02, z + face * 0.14), (0.06, 0.03, 0.1), style=no_bottom("black", 1.0))   # mouse
    if tower_x is not None:
        b.box((tower_x, floor + 0.22, z - face * 0.05), (0.2, 0.44, 0.44), style=lambda n, m, q: None if n[1] < -0.7 else
              (("trim", uv_world(1.0)) if n[2] * face > 0.7 else ("black", uv_world())))          # tower
        b.box((tower_x, floor + 0.38, z - face * 0.05 + face * 0.222), (0.06, 0.02, 0.005), style=no_bottom("green", 1.0))


def prop_desk(ctx, c, s):
    office_desk(ctx, c, s)


def prop_teacher_desk(ctx, c, s):
    """Teacher's desk: no PC, a stack of books and some papers."""
    b = ctx.b
    office_desk(ctx, c, s, with_pc=False)
    top = c[1] + s[1] / 2
    for k, col in enumerate(("red", "blue", "green")):
        b.box((c[0] - s[0] * 0.25, top + 0.02 + k * 0.04, c[2]), (0.24, 0.04, 0.18), yaw=k * 9, style=no_bottom(col, 1.0))
    for k in range(3):
        b.box((c[0] + 0.05 + k * 0.12, top + 0.002, c[2] + 0.05 * (k - 1)), (0.21, 0.004, 0.3), yaw=k * 13 - 10,
              style=no_bottom("bone", 1.0))


def prop_sign_pole(ctx, c, s):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box(c, s, style=lambda n, m, q: None if n[1] < -0.7 else ("trim_dark", uv_world()))
    yaw = 45.0                                                   # the board faces both roads (north-west)
    face = rot((0, 0, -1), yaw, 0)

    def style(n, m, q):
        if abs(dot(n, face)) > 0.9:
            return ("decals", ctx.d("price_board"))
        return ("trim_dark", uv_world())
    b.box((c[0], base_y + s[1] - 1.05, c[2]), (1.5, 2.0, 0.2), yaw=yaw, style=style)


def prop_ice(ctx, c, s):
    ctx.b.box(c, s, style=face_decal(ctx.d("ice"), "bone", "-x"))


def prop_roof_ac(ctx, c, s):
    b = ctx.b

    def style(n, m, q):
        if n[1] < -0.7:
            return None
        return ("metal", uv_world(1.0))
    b.box(c, s, style=style)
    b.box((c[0], c[1] + s[1] / 2 + 0.01, c[2]), (0.7, 0.02, 0.7), style=lambda n, m, q: ("black", uv_world()))


def prop_endcap(ctx, c, s):
    """The aisle's end display: snacks facing the door."""
    shelving(ctx, c, s, "z", (1,), "snacks", levels=3, frame="steel_light", lip="yellow", fill=0.6)


def prop_atm(ctx, c, s):
    b = ctx.b
    b.box(c, s, style=face_decal(ctx.d("atm"), "trim", "+z"))
    b.box((c[0], c[1] + 0.05, c[2] + s[2] / 2 + 0.06), (s[0] - 0.1, 0.06, 0.12),
          style=lambda n, m, q: ("trim_dark", uv_world()))                                 # little shelf


def prop_coffee(ctx, c, s):
    """Coffee station (refine pass): a red laminate cabinet with doors, a black worktop, a two-pot brewer against
    the wall, stacks of cups, a lid rack and a sugar box. The front faces into the shop."""
    b = ctx.b
    face = 1 if _front_into(c, 0) == "+x" else -1                      # the cabinet's front, along x
    y0 = c[1] - s[1] / 2
    top = y0 + s[1]
    xf, xb = c[0] + face * s[0] / 2, c[0] - face * s[0] / 2
    b.box((c[0] - face * 0.02, y0 + (s[1] - 0.04) / 2, c[2]), (s[0] - 0.04, s[1] - 0.04, s[2]), style=no_bottom("red", 1.0))
    b.box((c[0], top - 0.02, c[2]), (s[0] + 0.02, 0.04, s[2] + 0.04), style=no_bottom("black", 1.0))     # worktop
    for k in range(2):                                                                               # doors
        zc = c[2] - s[2] / 4 + k * s[2] / 2
        b.box((xf - face * 0.03, y0 + 0.47, zc), (0.012, 0.74, s[2] / 2 - 0.05), style=no_bottom("red", 1.0))
        b.box((xf - face * 0.015, y0 + 0.7, zc + (0.17 if k == 0 else -0.17)), (0.02, 0.12, 0.025),
              style=no_bottom("trim", 1.0))
    b.box((xf - face * 0.03, y0 + 0.05, c[2]), (0.012, 0.1, s[2] - 0.02), style=no_bottom("black", 1.0))   # kick
    b.box((xf - face * 0.02, y0 + 0.47, c[2]), (0.012, 0.74, 0.02), style=no_bottom("black", 1.0))        # door seam
    nb = lambda mat: no_bottom(mat, 1.0)
    # The brewer: a base with two warmer plates, a tower at the back, the hood over the brew basket.
    bz = c[2] - s[2] / 2 + 0.3
    b.group = ("item", len(b.faces))
    b.box((xb + face * 0.2, top + 0.02, bz), (0.34, 0.04, 0.5), style=nb("black"))
    b.box((xb + face * 0.08, top + 0.26, bz), (0.12, 0.48, 0.5), style=nb("steel_light"))
    b.box((xb + face * 0.2, top + 0.46, bz), (0.34, 0.1, 0.5), style=nb("steel_light"))
    b.box((xb + face * 0.22, top + 0.38, bz - 0.11), (0.16, 0.05, 0.16), style=nb("black"))           # brew basket
    b.box((xb + face * 0.33, top + 0.38, bz - 0.11), (0.08, 0.02, 0.03), style=nb("black"))           # its handle
    for k, dz in enumerate((-0.12, 0.12)):
        zz = bz + dz
        b.box((xb + face * 0.22, top + 0.045, zz), (0.15, 0.01, 0.15), style=nb("trim_dark"))          # warmer
        b.box((xb + face * 0.22, top + 0.1, zz), (0.13, 0.1, 0.13), style=nb("black"))                # coffee in the pot
        b.box((xb + face * 0.22, top + 0.19, zz), (0.13, 0.08, 0.13),
              style=lambda n, m, q: ("glass", uv_world(1.0)) if n[1] < 0.7 else None)               # pot glass
        b.box((xb + face * 0.22, top + 0.235, zz), (0.1, 0.02, 0.1), style=nb("black" if k else "mint"))   # lid
        b.box((xb + face * 0.31, top + 0.15, zz), (0.03, 0.12, 0.03), style=nb("black"))             # handle
    b.group = None
    # Cups: three stacks (small, medium, large), red sleeves; a lid rack and a sugar box.
    for k in range(3):
        zz = c[2] + 0.08 + k * 0.13
        h = 0.22 + 0.06 * k
        b.group = ("item", len(b.faces))
        b.box((c[0] - face * 0.08, top + h / 2, zz), (0.08 + 0.01 * k, h, 0.08 + 0.01 * k), style=nb("bone"))
        b.box((c[0] - face * 0.08, top + h * 0.6, zz), (0.09 + 0.01 * k, 0.04, 0.09 + 0.01 * k), style=nb("red"))
        b.group = None
    b.box((c[0] + face * 0.14, top + 0.05, c[2] + 0.38), (0.16, 0.1, 0.12), style=nb("cardboard"))      # sugar packets
    b.box((c[0] + face * 0.14, top + 0.04, c[2] + 0.16), (0.12, 0.08, 0.2), style=nb("trim_dark"))      # lid rack
    for k in range(3):
        b.box((c[0] + face * 0.14, top + 0.09, c[2] + 0.1 + k * 0.06), (0.1, 0.02, 0.05), style=nb("black"))


def prop_magazines(ctx, c, s):
    """Magazine rack: tilted shelves of magazines and papers."""
    shelving(ctx, c, s, "z", (-1,), "magazines", levels=3, frame="wood", lip="wood", fill=0.7)


PROPS = {
    "endcap": lambda ctx, c, s, k: prop_endcap(ctx, c, s),
    "atm": lambda ctx, c, s, k: prop_atm(ctx, c, s),
    "coffee": lambda ctx, c, s, k: prop_coffee(ctx, c, s),
    "magazines": lambda ctx, c, s, k: prop_magazines(ctx, c, s),
    "canopy_post": lambda ctx, c, s, k: prop_post(ctx, c, s),
    "canopy": lambda ctx, c, s, k: prop_canopy(ctx, c, s),
    "forecourt": lambda ctx, c, s, k: prop_forecourt(ctx, c, s),
    "pump": prop_pump,
    "counter": lambda ctx, c, s, k: prop_counter(ctx, c, s),
    "cig_rack": lambda ctx, c, s, k: prop_cigs(ctx, c, s),
    "shelf": lambda ctx, c, s, k: prop_shelf(ctx, c, s),
    "fridge": lambda ctx, c, s, k: prop_fridge(ctx, c, s),
    "rack": lambda ctx, c, s, k: prop_rack(ctx, c, s, ctx.rng),
    "desk": lambda ctx, c, s, k: prop_desk(ctx, c, s),
    "sign_pole": lambda ctx, c, s, k: prop_sign_pole(ctx, c, s),
    "ice_chest": lambda ctx, c, s, k: prop_ice(ctx, c, s),
    "roof_ac": lambda ctx, c, s, k: prop_roof_ac(ctx, c, s),
}


# ------------------------------------------------------------------------------------------------ dressing
def shards(ctx, x0, x1, y0, y1, z, axis, rng):
    """Broken glass left in a window frame (looks only: the window is an open hole for shots)."""
    b = ctx.b
    nrm = (0, 0, 1) if axis == "x" else (1, 0, 0)

    def P(a, y):
        return (a, y, z) if axis == "x" else (z, y, a)
    for corner_a, corner_y, da, dy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        if rng.random() < 0.6:
            la, ly = rng.uniform(0.15, 0.45), rng.uniform(0.15, 0.4)
            b.poly([P(corner_a, corner_y), P(corner_a + da * la, corner_y), P(corner_a, corner_y + dy * ly)], nrm, "glass",
                   uv_world(1.0))


# Openings (refine pass, owner: windows framed, some whole and some smashed; broken doors at the entrances). The
# generator lists every outside opening of the building; every model gets the same treatment.
ENTRANCE_DOOR = {"school": "green"}          # what the front doors are made of (else an aluminium shop door)


def dress_openings(ctx, openings):
    b = ctx.b
    for o in openings:
        kind, side, at, mid, w, lo, hi = o["kind"], o["side"], o["at"], o["mid"], o["w"], o["lo"], o["hi"]
        if kind == "blast":
            continue
        rng = random.Random(f"{BUILDING_NAME[0]}{side}{mid}{lo}")
        ns = side in "NS"
        out = 1 if side in "SE" else -1

        def P(a, y, d):                                 # along the wall, height, depth (+ = outwards)
            return (a, y, at + out * d) if ns else (at + out * d, y, a)

        def bx(a, y, d, la, h, ld, mat):
            b.box(P(a, y, d), (la, h, ld) if ns else (ld, h, la), style=lambda n, m, q: (mat, uv_world(1.0)))
        nrm = (0, 0, out) if ns else (out, 0, 0)
        a0, a1 = mid - w / 2, mid + w / 2
        if kind in ("window", "shop_window"):
            f = 0.06
            for a in (a0 + f / 2, a1 - f / 2):                                     # frame
                bx(a, (lo + hi) / 2, 0.06, f, hi - lo, 0.08, "trim")
            for y in (lo + f / 2, hi - f / 2):
                bx(mid, y, 0.06, w - 2 * f, f, 0.08, "trim")
            bx(mid, lo - 0.04, 0.19, w + 0.1, 0.08, 0.1, "concrete")                # sill outside
            panes = [(a0 + f, a1 - f)]
            if kind == "shop_window" or w > 2.0:
                bx(mid, (lo + hi) / 2, 0.06, 0.05, hi - lo - 2 * f, 0.07, "trim")   # mullion
                panes = [(a0 + f, mid - 0.025), (mid + 0.025, a1 - f)]
            for p0, p1 in panes:
                if rng.random() < 0.5:                                             # still whole
                    b.poly([P(p0, lo + f, 0.06), P(p1, lo + f, 0.06), P(p1, hi - f, 0.06), P(p0, hi - f, 0.06)], nrm,
                           "glass", uv_world(1.0))
                else:
                    shards(ctx, p0, p1, lo + f, hi - f, at + out * 0.06, "x" if ns else "z", rng)
        elif kind in ("door", "big_door"):
            for a in (a0 + 0.04, a1 - 0.04):                                      # door frame
                bx(a, (lo + hi) / 2, 0.0, 0.08, hi - lo, 0.32, "trim_dark")
            bx(mid, hi - 0.04, 0.0, w, 0.08, 0.32, "trim_dark")
            leaves = 2 if w > 1.5 else 1
            lw = w / leaves
            mat = ENTRANCE_DOOR.get(BUILDING_NAME[0], "trim")
            for k in range(leaves):
                fate = rng.random()
                if fate < 0.3:
                    continue                                                        # torn off and gone
                hinge = a0 + 0.08 if k == 0 else a1 - 0.08
                sgn = 1 if k == 0 else -1
                hh = hi - lo - 0.1
                if fate < 0.6:                                                     # lying on the ground outside
                    ang = rng.uniform(-25, 25)
                    c = P(hinge + sgn * lw * 0.5, lo + 0.03, 1.4 + rng.uniform(0, 0.4))
                    yaw = (0 if ns else 90) + ang
                    _door_leaf(b, c, lw - 0.12, hh, yaw, 90, mat, rng)
                else:                                                              # hanging open, off a hinge
                    th = math.radians(rng.uniform(70, 110))
                    u = (1.0, 0.0) if ns else (0.0, 1.0)                           # along the wall (x, z)
                    v = (0.0, float(out)) if ns else (float(out), 0.0)             # outwards
                    dx = sgn * math.cos(th) * u[0] - math.sin(th) * v[0]
                    dz = sgn * math.cos(th) * u[1] - math.sin(th) * v[1]
                    hp = P(hinge, lo + hh / 2 + 0.02, -0.15)
                    c = (hp[0] + dx * lw * 0.5, hp[1], hp[2] + dz * lw * 0.5)
                    _door_leaf(b, c, lw - 0.12, hh, math.degrees(math.atan2(-dz, dx)), 0, mat, rng, upright=True)


def _door_leaf(b, c, w, h, yaw, tilt, mat, rng, upright=False):
    """A broken door leaf centred at c: frame of `mat`, its glass smashed out (a few shards left)."""
    lay = not upright
    parts = [((0, h / 2 - 0.05, 0), (w, 0.1, 0.045)), ((0, -h / 2 + 0.12, 0), (w, 0.24, 0.045)),
             ((-w / 2 + 0.05, 0, 0), (0.1, h, 0.045)), ((w / 2 - 0.05, 0, 0), (0.1, h, 0.045)),
             ((0, -h * 0.05, 0), (w, 0.06, 0.04))]
    for off, size in parts:
        if lay:
            # lying flat: local y goes along the ground (pitch -90 turns the door's up onto -z then yaw)
            o = rot(off, yaw, -90)
            p = (c[0] + o[0], c[1] + 0.025, c[2] + o[2])
            b.box(p, size, yaw=yaw, pitch=-90, style=no_bottom(mat, 1.0))
        else:
            o = rot(off, yaw, 0)
            p = (c[0] + o[0], c[1] + o[1], c[2] + o[2])
            b.box(p, size, yaw=yaw, style=no_bottom(mat, 1.0))


def wet_floor_sign(ctx, x, y, z, yaw):
    """A-frame caution sign: two yellow boards hinged at the top, the warning on both outsides."""
    b = ctx.b
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

    def P(px, py, pz):                     # local (x across, y up, z the way the legs splay) -> model
        return (x + px * cy + pz * sy, y + py, z - px * sy + pz * cy)
    w, h, foot, head = 0.15, 0.62, 0.15, 0.015
    for sz in (-1, 1):
        lo, hi = sz * foot, sz * head
        ln = (0.0, -sz * (hi - lo), sz * h)                       # outward (and a little up), local
        nrm = norm((ln[0] * cy + ln[2] * sy, ln[1], -ln[0] * sy + ln[2] * cy))
        quad = [P(-w, 0.0, lo), P(w, 0.0, lo), P(w, h, hi), P(-w, h, hi)]
        b.poly(quad, nrm, "decals", ctx.d("wet"))
        b.poly(quad, v_scale(nrm, -1.0), "yellow", uv_world(1.0))
    b.box(P(0, h + 0.015, 0), (0.32, 0.03, 0.05), yaw=yaw, style=no_bottom("yellow", 1.0))    # hinge cap


def dress_gas_station(ctx):
    b, rng = ctx.b, ctx.rng
    # Windows: shards of glass in the frames. (Positions from the gray box: 0.17's Building windows.)
    # Store sign over the door (west wall) and the CLOSED notice beside it.
    b.box((-6.72, 2.58, 0.0), (0.08, 0.3, 3.0), style=face_decal(ctx.d("market"), "red", "-x"))
    b.poly([(-6.66, 1.3, -1.3), (-6.66, 1.3, -1.9), (-6.66, 1.7, -1.9), (-6.66, 1.7, -1.3)], (-1, 0, 0), "decals",
           ctx.d("closed"))
    # NO FUEL sprayed on the north wall (faces Main Street).
    b.poly([(-1.5, 1.2, -5.16), (1.5, 1.2, -5.16), (1.5, 2.2, -5.16), (-1.5, 2.2, -5.16)], (0, 0, -1), "graffiti",
           ctx.d("graffiti"))
    # Shop life (0.17, owner: "a bit more lively, not too overly filled").
    b.box((-5.85, 0.012, 0.0), (0.9, 0.02, 2.0), style=lambda n, m, q: ("trim_dark", uv_world()) if n[1] > 0.7 else None)  # door mat
    b.poly([(-6.34, 1.4, -2.2), (-6.34, 1.4, -2.8), (-6.34, 2.2, -2.8), (-6.34, 2.2, -2.2)], (1, 0, 0), "decals", ctx.d("poster"))
    b.poly([(-3.0, 2.3, -4.84), (-2.6, 2.3, -4.84), (-2.6, 2.7, -4.84), (-3.0, 2.7, -4.84)], (0, 0, 1), "decals", ctx.d("clock"))
    for nz in (1, -1):                                                                          # hanging banner
        b.poly([(-4.4, 2.25, 0.5), (-2.4, 2.25, 0.5), (-2.4, 2.6, 0.5), (-4.4, 2.6, 0.5)], (0, 0, nz), "decals", ctx.d("banner"))
    for x in (-4.3, -2.5):
        b.box((x, 2.67, 0.5), (0.02, 0.15, 0.02), style=lambda n, m, q: ("black", uv_world()))
    wet_floor_sign(ctx, -1.9, 0.0, 2.2, 25)
    b.box((-0.9, 0.17, 4.1), (0.4, 0.34, 0.32), style=lambda n, m, q: None if n[1] < -0.7 else ("red", uv_world()))   # mop bucket
    b.box((-0.85, 0.75, 4.1), (0.04, 1.2, 0.04), pitch=-12, style=lambda n, m, q: ("wood", uv_world()))
    b.box((-3.6, 0.1, -1.2), (0.45, 0.2, 0.32), yaw=20, style=lambda n, m, q: None if n[1] < -0.7 else ("red", uv_world()))  # dropped basket
    for _ in range(5):                                                                          # snacks knocked off the shelf
        x, z = rng.uniform(-4.2, -1.8), rng.uniform(-1.5, -1.25)
        col = rng.choice(("red", "bone", "cardboard"))
        b.box((x, 0.06, z), (0.18, 0.12, 0.1), yaw=rng.uniform(0, 90),
              style=lambda n, m, q, col=col: None if n[1] < -0.7 else (col, uv_world(1.0)))
    # Back room: a water heater and a stack of boxes.
    b.box((6.0, 0.8, -4.45), (0.6, 1.6, 0.6), style=lambda n, m, q: None if n[1] < -0.7 else ("bone", uv_world()))
    for k, (dx, dz, h) in enumerate(((0.0, 0.0, 0.0), (0.5, 0.1, 0.0), (0.2, 0.05, 0.45))):
        b.box((1.0 + dx, 0.22 + h, 3.0 + dz), (0.5, 0.44, 0.45), yaw=k * 7,
              style=lambda n, m, q: None if n[1] < -0.7 else ("cardboard", uv_world(1.0)))
    # Litter on the shop floor.
    for _ in range(10):
        x, z = rng.uniform(-6.2, -0.3), rng.uniform(-1.4, 2.6)
        w = rng.uniform(0.1, 0.3)
        col = rng.choice(("bone", "red", "cardboard", "bone"))
        b.box((x, 0.035, z), (w, 0.01, w * rng.uniform(0.6, 1.4)), yaw=rng.uniform(0, 90),
              style=lambda n, m, q, col=col: (col, uv_world(1.0)) if n[1] > 0.7 else None)


DRESSING = {"gas_station_town": dress_gas_station}
FOOTPRINTS = {"gas_station_town": (-6.5, -5.0, 6.5, 5.0)}   # the shop's walls (x0, z0, x1, z1): outside vs inside faces


# ------------------------------------------------------------------------------------------------ shops (0.17)
# The Shops block on the car park (map 15-44 x 120-133, model origin map (29.5, 126.5)): a laundromat (west), a shoe
# store (middle) and a TV shop that burned out (east, its roof fell in); a flat and a stock room upstairs.
SHOP_UNITS = (-4.83, 4.83)          # local x of the walls between the shops


def shop_unit(x):
    return 0 if x < SHOP_UNITS[0] else (1 if x < SHOP_UNITS[1] else 2)


def shops_decals(rng):
    a = Atlas(512)

    def sign(text, board, ink, scale, burnt=False):
        def paint(c):     # 4 m x 0.75 m
            c.rect(0, 0, c.w, c.h, board)
            c.frame(0, 0, c.w, c.h, "iron_dark")
            w = Canvas.text_width(text, scale)
            c.ctext(0, c.w, (c.h - 5 * scale) // 2, text, ink, scale)
            if burnt:
                c.blotch(["black", "iron_dark"], 14, rng, size=(3, 7))
                c.rect(c.w - 22, 0, c.w, 9, "clear")                     # a corner burned away
            else:
                c.blotch(["concrete"], 3, rng, area=(2, 2, c.w - 2, c.h - 2), size=(2, 3))
        return paint

    def washer(c):        # 0.92 x 1.0 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, 0, 1, c.h, "steel_light")
        c.rect(1, c.h - 6, c.w - 1, c.h - 1, "steel_light")              # control panel
        c.rect(4, c.h - 4, 8, c.h - 3, "black")
        c.put(c.w - 6, c.h - 4, "red")
        cx, cy, r = c.w // 2, 12, 8
        for y in range(c.h):
            for x in range(c.w):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if d <= r * r:
                    c.put(x, y, "steel" if d > (r - 2) ** 2 else "sky_blue")
        c.rect(cx - 3, cy + 1, cx + 1, cy + 3, "steel_light")              # glint

    def dryer(c):         # 0.85 x 1.9 m: two stacked
        c.rect(0, 0, c.w, c.h, "steel_light")
        for k, base in enumerate((2, 32)):
            c.frame(0, base - 2, c.w, base + 28, "steel")
            cx, cy, r = c.w // 2, base + 11, 9
            for y in range(base, base + 26):
                for x in range(c.w):
                    d = (x - cx) ** 2 + (y - cy) ** 2
                    if d <= r * r:
                        c.put(x, y, "iron" if d > (r - 2) ** 2 else "black")
            c.rect(3, base + 23, c.w - 3, base + 25, "iron_dark")
            if k == 1:
                c.rect(5, base + 13, 12, base + 16, "bone")                # a sock in the window

    def shoes(c):         # 1.7 x 2.2 m shoe wall
        c.rect(0, 0, c.w, c.h, "wood_dark")
        c.frame(0, 0, c.w, c.h, "wood_mid")
        for row in range(5):
            y = 4 + row * 13
            c.rect(1, y - 1, c.w - 1, y, "wood_pale")                    # shelf edge
            x = 3
            while x < c.w - 8:
                if rng.random() < 0.72:
                    col = rng.choice(("red", "bone", "sky_blue", "black", "hazard_yellow", "olive", "steel_light"))
                    sole = "bone" if col != "bone" else "iron"
                    for dx in (0, 4):
                        c.rect(x + dx, y, x + dx + 3, y + 3, col)
                        c.rect(x + dx, y, x + dx + 3, y + 1, sole)
                        c.put(x + dx + 2, y + 3, col)                     # heel/ankle
                x += 10
        c.blotch(["wood_mid"], 4, rng, size=(2, 3))

    def shoe_counter(c):  # 2.2 x 1.0 m
        c.rect(0, 0, c.w, c.h, "wood_mid")
        c.rect(0, 0, c.w, 3, "wood_dark")
        c.rect(0, c.h - 9, c.w, c.h - 3, "red")
        w = Canvas.text_width("SHOES")
        c.ctext(0, c.w, c.h - 8, "SHOES", "bone")
        for x in range(6, c.w, 12):
            c.rect(x, 3, x + 1, c.h - 9, "wood_dark")

    def tvs(c):           # 1.7 x 2.0 m shelf of dead TVs
        c.rect(0, 0, c.w, c.h, "iron_dark")
        for row in range(3):
            y = 3 + row * 20
            c.rect(0, y - 2, c.w, y, "steel")
            x = 2
            while x < c.w - 12:
                w = rng.choice((12, 14, 16))
                if rng.random() < 0.8:
                    c.rect(x, y, x + w, y + 12, rng.choice(("bone", "iron", "black")))
                    c.rect(x + 1, y + 1, x + w - 3, y + 11, "black")
                    if rng.random() < 0.5:                                # smashed screen
                        for k in range(5):
                            c.put(x + 2 + k * 2 % (w - 4), y + 2 + k, "steel_light")
                x += w + 2
        c.blotch(["black"], 10, rng, size=(3, 6))

    def kitchen(c):       # 3 x 0.95 m
        c.rect(0, 0, c.w, c.h, "wood_pale")
        c.rect(0, 0, c.w, 3, "black")
        for x0 in range(0, c.w, 16):
            c.frame(x0, 3, x0 + 16, c.h - 2, "wood_light")
            c.rect(x0 + 13, c.h - 10, x0 + 14, c.h - 5, "iron")
        c.rect(32, 3, 56, c.h - 2, "steel")                               # oven
        c.rect(35, 7, 53, 19, "black")
        c.rect(34, c.h - 6, 54, c.h - 4, "iron_dark")
        c.rect(0, c.h - 2, c.w, c.h, "steel_light")

    def awning(c):        # 4.6 x 1.2 m
        for x in range(c.w):
            c.rect(x, 0, x + 1, c.h, "red" if (x // 8) % 2 == 0 else "bone")
        for x in range(0, c.w, 8):
            c.rect(x, 0, x + 4, 2, "red" if (x // 8) % 2 == 0 else "bone")
        c.blotch(["sand", "rust"], 5, rng, size=(2, 4))

    def poster(text, colour, ink):
        def paint(c):     # 0.6 x 0.8 m
            c.rect(0, 0, c.w, c.h, colour)
            c.frame(0, 0, c.w, c.h, ink)
            w = Canvas.text_width(text)
            c.ctext(0, c.w, c.h // 2, text, ink)
        return paint

    def soot(c):          # 2 x 1.5 m see-through scorch over a window or door
        cx = c.w // 2
        for y in range(c.h):
            for x in range(c.w):
                spread = 8 + y * 0.45
                if abs(x - cx) < spread * rng.uniform(0.7, 1.0) and rng.random() < 0.92:
                    c.put(x, y, "black" if rng.random() < 0.6 else "iron_dark")
                else:
                    c.put(x, y, "clear")

    def x1(c):            # graffiti: the Brotherhood's mark (lore: docs/LORE.md)
        c.rect(0, 0, c.w, c.h, "clear")
        for k in range(c.h - 4):
            for t in range(4):
                c.put(4 + k * 20 // (c.h - 4) + t, 2 + k, "red")
                c.put(26 - k * 20 // (c.h - 4) + t, 2 + k, "red")
        c.rect(36, 2, 40, c.h - 2, "red")
        c.rect(33, c.h - 6, 37, c.h - 2, "red")
        for _ in range(6):                                                # drips
            x = rng.randrange(4, 40)
            c.rect(x, 0, x + 1, rng.randrange(2, 5), "red")

    def note(c):          # 0.3 x 0.2 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.text(1, 1, "OUT", "red")

    a.add("sign_laundry", 128, 24, sign("LAUNDRY", "sky_blue", "bone", 3))
    a.add("sign_shoes", 128, 24, sign("SHOES", "red", "bone", 3))
    a.add("sign_tv", 128, 24, sign("TV RADIO", "black", "hazard_yellow", 3, burnt=True))
    a.add("washer", 29, 32, washer)
    a.add("dryer", 27, 61, dryer)
    a.add("shoes", 54, 70, shoes)
    a.add("shoe_counter", 70, 32, shoe_counter)
    a.add("tvs", 54, 64, tvs)
    a.add("kitchen", 96, 30, kitchen)
    a.add("awning", 147, 38, awning)
    a.add("poster_sale", 19, 26, poster("SALE", "hazard_yellow", "red"))
    a.add("poster_new", 19, 26, poster("NEW", "red", "bone"))
    a.add("poster_wash", 19, 26, poster("WASH", "sky_blue", "bone"))
    a.add("soot", 64, 48, soot)
    a.add("x1", 44, 32, x1)
    a.add("note", 13, 7, note)
    return a


def _front_into(c, axis):
    """'+z'/'-z' (or x): the side of a box against a wall that faces into the room (away from the nearest wall line
    of the building's SHELLS "x_lines" / "z_lines"; the outside walls if it has none)."""
    cfg = SHELLS.get(BUILDING_NAME[0], {})
    fp = FOOTPRINTS[BUILDING_NAME[0]]
    lines = cfg.get("xz"[axis // 2] + "_lines", (fp[0], fp[2]) if axis == 0 else (fp[1], fp[3]))
    wall = min(lines, key=lambda l: abs(c[axis] - l))
    return ("+" if c[axis] > wall else "-") + "xyz"[axis]


def no_bottom(mat, tile=2.0):
    return lambda n, m, q: None if n[1] < -0.7 else (mat, uv_world(tile))


# ------------------------------------------------------------------------------------------------ shelf kit (0.17)
# Real shelving with small 3D stock on it (owner, refine pass: "realer looking stands with pixel 3D food on them"),
# shared by every shop, office and library. Each item is a few flat-coloured boxes; a shelf is about half looted.

ITEM_COLOURS = ("red", "yellow", "blue", "green", "bone", "olive", "mint", "black")


def _item(b, pts_box, mat_of):
    """One small item: boxes [(centre, size, yaw, pitch)], mat_of(index, normal) -> material. Shares one light."""
    b.group = ("item", len(b.faces))
    for k, (c, sz, yaw, pitch) in enumerate(pts_box):
        b.box(c, sz, yaw, pitch, style=lambda n, m, q, k=k: None if n[1] < -0.7 else (mat_of(k, n), uv_world(1.0)))
    b.group = None


def stock_can(b, at, rng, col):
    """A soda/food can (0.07 wide): body colour, steel top."""
    x, y, z = at
    _item(b, [((x, y + 0.06, z), (0.07, 0.12, 0.07), 0, 0)], lambda k, n: "steel_light" if n[1] > 0.7 else col)
    return 0.075


def stock_bottle(b, at, rng, col):
    x, y, z = at
    _item(b, [((x, y + 0.09, z), (0.07, 0.18, 0.07), 0, 0), ((x, y + 0.21, z), (0.03, 0.06, 0.03), 0, 0)],
          lambda k, n: "black" if k == 1 else col)
    return 0.08


def stock_bag(b, at, rng, col):
    """A bag of chips, leaning back a little."""
    x, y, z = at
    _item(b, [((x, y + 0.12, z), (0.16, 0.24, 0.06), rng.uniform(-8, 8), -8)],
          lambda k, n: "bone" if abs(n[1]) > 0.7 else col)
    return 0.17


def stock_box(b, at, rng, col):
    """A cereal/cracker box, with a white top."""
    x, y, z = at
    h = rng.choice((0.22, 0.26, 0.3))
    _item(b, [((x, y + h / 2, z), (0.18, h, 0.07), rng.uniform(-4, 4), 0)],
          lambda k, n: "bone" if n[1] > 0.7 else col)
    return 0.19


def stock_jar(b, at, rng, col):
    x, y, z = at
    _item(b, [((x, y + 0.06, z), (0.09, 0.12, 0.09), 0, 0), ((x, y + 0.13, z), (0.07, 0.02, 0.07), 0, 0)],
          lambda k, n: col if k == 1 else ("steel_light" if n[1] > 0.7 else "bone"))
    return 0.1


def stock_pills(b, at, rng, col):
    """A small medicine box (white with a coloured band) or a pill bottle."""
    x, y, z = at
    if rng.random() < 0.5:
        _item(b, [((x, y + 0.045, z), (0.08, 0.09, 0.05), rng.uniform(-6, 6), 0)],
              lambda k, n: col if abs(n[1]) < 0.7 and q_band(n) else "bone")
        return 0.09
    _item(b, [((x, y + 0.04, z), (0.05, 0.08, 0.05), 0, 0), ((x, y + 0.09, z), (0.055, 0.02, 0.055), 0, 0)],
          lambda k, n: "bone" if k == 1 else "yellow")
    return 0.06


def stock_book(b, at, rng, col):
    """A book standing on the shelf: coloured cover, pale pages on top."""
    x, y, z = at
    h = rng.uniform(0.18, 0.28)
    _item(b, [((x, y + h / 2, z), (0.04, h, 0.17), 0, 0)], lambda k, n: "bone" if n[1] > 0.7 else col)
    return 0.045


def stock_shoes(b, at, rng, col):
    x, y, z = at
    b.group = ("item", len(b.faces))
    shoe_pair(b, x, y, z, rng.uniform(-10, 10), col)
    b.group = None
    return 0.26


def stock_tv(b, at, rng, col):
    """An old TV (refine pass: properly 3D): a CRT with a bezel, an inset screen (some smashed), a tapered back,
    knobs and little feet; or now and then a flat set on a stand."""
    x, y, z = at
    w = rng.choice((0.42, 0.5, 0.56))
    smashed = rng.random() < 0.3
    b.group = ("item", len(b.faces))
    nb = lambda mat: no_bottom(mat, 1.0)
    if rng.random() < 0.25:                                              # flat screen on a stand
        b.box((x, y + 0.01, z), (0.22, 0.02, 0.14), style=nb("black"))
        b.box((x, y + 0.07, z - 0.02), (0.04, 0.12, 0.03), style=nb("black"))
        b.box((x, y + 0.26, z - 0.02), (w, w * 0.6, 0.04), style=nb("black"))
        b.box((x, y + 0.26, z + 0.001), (w - 0.04, w * 0.6 - 0.04, 0.004), style=nb("black" if smashed else "glass"))
        b.group = None
        return w
    h = w * 0.78
    b.box((x, y + 0.02 + h / 2, z + 0.02), (w, h, 0.2), style=nb(col))                          # front case
    b.box((x, y + 0.02 + h / 2, z - 0.13), (w * 0.7, h * 0.75, 0.14), style=nb(col))            # tube housing
    b.box((x - w * 0.08, y + 0.02 + h * 0.52, z + 0.122), (w * 0.7, h * 0.72, 0.004),
          style=nb("black" if smashed else "trim_dark"))                                       # screen
    b.box((x - w * 0.08, y + 0.02 + h * 0.52, z + 0.121), (w * 0.76, h * 0.8, 0.003), style=nb("trim_dark"))  # bezel
    for k in range(2):                                                                         # knobs
        b.box((x + w * 0.38, y + 0.02 + h * (0.65 - k * 0.25), z + 0.13), (0.04, 0.04, 0.02), style=nb("black"))
    for sx in (-1, 1):                                                                         # feet
        b.box((x + sx * w * 0.38, y + 0.01, z + 0.02), (0.05, 0.02, 0.15), style=nb("black"))
    b.group = None
    return w


def q_band(n):
    return abs(n[0]) > 0.7


def stock_magazine(b, at, rng, col):
    x, y, z = at
    _item(b, [((x, y + 0.14, z), (0.2, 0.28, 0.015), 0, -14)], lambda k, n: col if abs(n[2]) > 0.5 else "bone")
    return 0.22


def stock_cigs(b, at, rng, col):
    x, y, z = at
    _item(b, [((x, y + 0.045, z), (0.06, 0.09, 0.025), 0, 0)], lambda k, n: "bone" if n[1] > 0.7 else col)
    return 0.065


STOCK_W = {"stock_can": 0.075, "stock_bottle": 0.08, "stock_bag": 0.17, "stock_box": 0.19, "stock_jar": 0.1,
           "stock_pills": 0.09, "stock_magazine": 0.22, "stock_cigs": 0.065, "stock_book": 0.045,
           "stock_shoes": 0.26, "stock_tv": 0.6}
STOCK = {          # what each kind of shelf holds: (item, its colours)
    "grocery": [(stock_can, ("red", "blue", "green", "yellow")), (stock_bottle, ("green", "blue", "red", "steel_light")),
                (stock_bag, ("yellow", "red", "blue", "green")), (stock_box, ("red", "yellow", "olive", "blue")),
                (stock_jar, ("red", "green", "yellow"))],
    "drinks": [(stock_can, ("red", "blue", "green", "yellow", "black")),
               (stock_bottle, ("green", "blue", "red", "steel_light", "yellow"))],
    "snacks": [(stock_bag, ("yellow", "red", "blue", "green", "olive")), (stock_box, ("red", "yellow", "blue"))],
    "meds": [(stock_pills, ("red", "blue", "green", "mint")), (stock_jar, ("mint", "blue", "red"))],
    "magazines": [(stock_magazine, ("red", "blue", "yellow", "green", "olive", "bone"))],
    "cigs": [(stock_cigs, ("red", "bone", "blue", "olive", "black"))],
    "books": [(stock_book, ("red", "blue", "green", "yellow", "olive", "black", "bone", "olive_dark"))],
    "shoes": [(stock_shoes, ("red", "bone", "blue", "black", "yellow", "olive"))],
    "tvs": [(stock_tv, ("bone", "steel_light", "trim", "wood"))],
    "art": [(stock_jar, ("red", "yellow", "blue", "green")), (stock_box, ("bone", "cardboard", "yellow")),
            (stock_book, ("bone", "cardboard"))],
}


def stock_run(ctx, a0, a1, y, d, axis, kind, rng, fill=0.6, fallen=None):
    """Stock along one shelf from a0 to a1 (along x if axis is "x", else z) at depth d. Items come in facings
    (a few of the same thing side by side); some facings are gone (looted). Returns nothing."""
    b = ctx.b
    a = a0 + 0.03
    pool = STOCK[kind]
    while a < a1 - 0.08:
        maker, cols = rng.choice(pool)
        col = rng.choice(cols)
        n = rng.randint(2, 4)
        taken = rng.random() > fill
        for _ in range(n):
            w = STOCK_W[maker.__name__]
            if a + w > a1:                                # nothing hangs off the end of the shelf (owner)
                break
            at = (a + w / 2, y, d) if axis == "x" else (d, y, a + w / 2)
            if not taken:
                _place(maker, b, at, axis, rng, col)
            a += w + 0.01
        a += 0.03
    if fallen:
        x0, x1, z0, z1 = fallen
        for _ in range(rng.randint(2, 4)):
            maker, cols = rng.choice(pool)
            at = (rng.uniform(x0, x1), 0.0 + FLOOR_Y[0], rng.uniform(z0, z1))
            _place(maker, b, at, "x", rng, rng.choice(cols), lying=True)


FLOOR_Y = [0.0]


def _place(maker, b, at, axis, rng, col, lying=False):
    """Calls a stock maker, turning its boxes for a shelf along z (and laying it on its side when it fell off)."""
    if axis == "x" and not lying:
        return maker(b, at, rng, col)
    first = len(b.faces)
    w = maker(b, at, rng, col)
    # Turn the new faces round the item's own spot: 90 degrees for a z shelf, onto its side (and spun) on the floor.
    yaw = 90.0 if axis == "z" else 0.0
    if lying:
        yaw = rng.uniform(0, 180)
    _turn_faces(b, first, at, yaw, lying)
    return w


def _turn_faces(b, first, at, yaw, lying):
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    moved = {}
    for f in range(first, len(b.faces)):
        for vi in b.faces[f]:
            if vi in moved:
                continue
            x, y, z = (b.verts[vi][k] - at[k] for k in range(3))
            if lying:                                     # tip over onto its side: y up becomes x
                x, y = y, -x
                y += 0.0
            x, z = x * cy + z * sy, -x * sy + z * cy
            b.verts[vi] = (at[0] + x, at[1] + y, at[2] + z)
            moved[vi] = True
        n = b.normals[f]
        nx, ny, nz = n
        if lying:
            nx, ny = ny, -nx
        b.normals[f] = (nx * cy + nz * sy, ny, -nx * sy + nz * cy)
    if lying:                                             # lift it so it rests on the floor
        low = min(b.verts[vi][1] for f in range(first, len(b.faces)) for vi in b.faces[f])
        for f in range(first, len(b.faces)):
            for vi in b.faces[f]:
                if vi not in moved or moved[vi] == "lifted":
                    continue
                v = b.verts[vi]
                b.verts[vi] = (v[0], v[1] - low + at[1], v[2])
                moved[vi] = "lifted"


def shelving(ctx, c, s, axis, sides, kind, levels=4, frame="metal", lip="red", fill=0.6, seed=0, top_stock=False):
    """A shelving unit (gondola) as the gray box c/s: uprights at the ends, a back panel, `levels` shelves with
    a coloured price strip, stock on every shelf. axis: "x" if it runs along x. sides: +1 and/or -1, the faces
    (along the other axis) that have shelves; both for an aisle gondola, one for a wall unit."""
    b = ctx.b
    rng = random.Random(f"{BUILDING_NAME[0]}{c}{seed}")
    L = s[0] if axis == "x" else s[2]
    D = s[2] if axis == "x" else s[0]
    a0, a1 = (c[0] if axis == "x" else c[2]) - L / 2, (c[0] if axis == "x" else c[2]) + L / 2
    dc = c[2] if axis == "x" else c[0]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2

    def box(a, y, d, la, h, ld, mat, tile=1.0, skip_bottom=True):
        cc = (a, y, d) if axis == "x" else (d, y, a)
        sz = (la, h, ld) if axis == "x" else (ld, h, la)
        b.box(cc, sz, style=lambda n, m, q: None if skip_bottom and n[1] < -0.7 else (mat, uv_world(tile)))
    back_d = dc if len(sides) == 2 else dc - sides[0] * (D / 2 - 0.02)
    # The back panel and top sit between the end uprights (no faces on top of each other: they flickered).
    box((a0 + a1) / 2, (y0 + y1 - 0.03) / 2, back_d, L - 0.08, s[1] - 0.03, 0.03, frame, 2.0)     # back panel
    for e in (a0 + 0.02, a1 - 0.02):                                                           # end uprights
        box(e, (y0 + y1) / 2, dc, 0.04, s[1], D, frame, 2.0)
    box((a0 + a1) / 2, y0 + 0.06, dc, L - 0.08, 0.12, D, "trim_dark")                          # kick plate
    span = (y1 - 0.1) - (y0 + 0.12)
    for side in sides:
        near, far = back_d + side * 0.015, dc + side * D / 2
        depth = abs(far - near)
        mid = (near + far) / 2
        for k in range(levels):
            y = y0 + 0.12 + span * k / levels
            box((a0 + a1) / 2, y + 0.015, mid, L - 0.08, 0.03, depth, frame)                   # shelf
            box((a0 + a1) / 2, y + 0.03, far - side * 0.005, L - 0.08, 0.04, 0.01, lip)         # price strip
            if k < levels:
                stock_run(ctx, a0 + 0.04, a1 - 0.04, y + 0.03, mid, axis, kind, rng, fill)
        if top_stock:
            stock_run(ctx, a0 + 0.04, a1 - 0.04, y1, mid, axis, kind, rng, fill * 0.6)
    box((a0 + a1) / 2, y1 - 0.016, back_d, L - 0.08, 0.03, 0.05 if len(sides) == 1 else D - 0.004, frame)   # top


def prop_washers(ctx, c, s):
    b = ctx.b
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b.box(c, s, style=lambda n, m, q: None if abs(n[2]) > 0.7 or n[1] < -0.7 else ("bone" if n[1] > 0.7 else "trim", uv_world()))
    x0, x1, z0, z1 = c[0] - s[0] / 2, c[0] + s[0] / 2, c[2] - s[2] / 2, c[2] + s[2] / 2
    strip_quads(ctx, x0, x1, y0, y1, z0, (0, 0, -1), "washer", 0.92, "x")
    strip_quads(ctx, x0, x1, y0, y1, z1, (0, 0, 1), "washer", 0.92, "x")
    b.poly([(x0 + 1.2, y1 - 0.5, z0 - 0.005), (x0 + 1.5, y1 - 0.5, z0 - 0.005), (x0 + 1.5, y1 - 0.3, z0 - 0.005),
            (x0 + 1.2, y1 - 0.3, z0 - 0.005)], (0, 0, -1), "decals", ctx.d("note"))         # OUT OF ORDER


def prop_dryers(ctx, c, s):
    b = ctx.b
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b.box(c, s, style=lambda n, m, q: None if n[0] > 0.7 or n[1] < -0.7 else ("steel_light", uv_world()))
    strip_quads(ctx, c[2] - s[2] / 2, c[2] + s[2] / 2, y0, y1, c[0] + s[0] / 2, (1, 0, 0), "dryer", 0.85, "z")


def prop_table(ctx, c, s, top="wood", legs="trim_dark"):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box((c[0], base_y + s[1] - 0.025, c[2]), (s[0], 0.05, s[2]), style=lambda n, m, q: (top, uv_world(2.0)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((c[0] + sx * (s[0] / 2 - 0.06), base_y + (s[1] - 0.05) / 2, c[2] + sz * (s[2] / 2 - 0.06)),
                  (0.05, s[1] - 0.05, 0.05), style=lambda n, m, q: (legs, uv_world()))
    return base_y + s[1]


def prop_fold_table(ctx, c, s):
    top = prop_table(ctx, c, s, "bone")
    for k, (dx, dz, col) in enumerate(((-0.6, 0.1, "blue"), (-0.2, -0.15, "bone"), (0.5, 0.05, "red"), (0.9, 0.1, "olive"))):
        ctx.b.box((c[0] + dx, top + 0.05, c[2] + dz), (0.42, 0.1, 0.32), yaw=k * 17,
                  style=no_bottom(col, 1.0))                                                        # folded clothes
    ctx.b.box((c[0] + 0.1, top + 0.02 + 0.15, c[2] + 0.2), (0.5, 0.3, 0.36), style=no_bottom("bone", 1.0))   # basket


def prop_shoe_wall(ctx, c, s):
    """Wall of shoes: wooden shelves, pairs on each."""
    side = 1 if _front_into(c, 2) == "+z" else -1
    shelving(ctx, c, s, "x", (side,), "shoes", levels=5, frame="wood", lip="wood", fill=0.6)


def shoe_pair(b, x, y, z, yaw, col):
    """A pair of trainers (refine pass, owner: more texture): white soles, a heel tab, a contrasting side stripe,
    pale laces over the top."""
    trim = "bone" if col != "bone" else "red"
    sole = "black" if col == "bone" else "bone"
    for dx in (-0.06, 0.06):
        def put(ox, oy, oz, size, mat):
            p = rot((dx + ox, 0, oz), yaw, 0)
            b.box((x + p[0], y + oy, z + p[2]), size, yaw=yaw, style=no_bottom(mat, 1.0))
        put(0, 0.015, 0, (0.1, 0.03, 0.28), sole)                       # sole
        put(0, 0.06, -0.02, (0.095, 0.06, 0.24), col)                    # upper
        put(0, 0.1, 0.08, (0.09, 0.06, 0.1), col)                      # ankle
        put(0, 0.092, -0.06, (0.05, 0.01, 0.12), trim)                   # laces
        put(0, 0.06, 0.0, (0.1, 0.025, 0.14), trim)                     # side stripe (both sides in one box)


SHOE_COLOURS = ("red", "bone", "blue", "black", "yellow", "olive")


def prop_bench(ctx, c, s):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box((c[0], base_y + s[1] - 0.06, c[2]), (s[0], 0.12, s[2]), style=no_bottom("black", 1.0))   # cushion
    b.box((c[0], base_y + (s[1] - 0.12) / 2, c[2]), (s[0] - 0.1, s[1] - 0.12, s[2] - 0.1), style=no_bottom("wood"))
    shoe_pair(b, c[0] + 0.5, base_y, c[2] + 0.55, 10, ctx.rng.choice(SHOE_COLOURS))                # tried on, left out


def prop_shoe_table(ctx, c, s):
    top = prop_table(ctx, c, s, "wood")
    rng = ctx.rng
    for k in range(5):
        shoe_pair(ctx.b, c[0] - s[0] / 2 + 0.3 + k * 0.36, top, c[2] + rng.uniform(-0.25, 0.25), rng.uniform(-30, 30),
                  rng.choice(SHOE_COLOURS))


def prop_shoe_counter(ctx, c, s):
    b = ctx.b
    b.box(c, s, style=face_decal(ctx.d("shoe_counter"), "wood", "-x"))
    top = c[1] + s[1] / 2
    b.box((c[0], top + 0.02, c[2]), (s[0] + 0.06, 0.04, s[2] + 0.06), style=no_bottom("bone", 1.0))
    b.box((c[0] + 0.1, top + 0.15, c[2] - 0.5), (0.38, 0.22, 0.4), style=no_bottom("trim_dark", 1.0))   # till
    for k in range(3):                                                                               # shoeboxes
        b.box((c[0], top + 0.04 + 0.065 + k * 0.13, c[2] + 0.6), (0.22, 0.13, 0.35), yaw=k * 6,
              style=no_bottom(("red", "blue", "bone")[k], 1.0))


def prop_shoebox_stack(ctx, c, s):
    b, rng = ctx.b, ctx.rng
    base_y = c[1] - s[1] / 2
    for col_x in (-0.18, 0.18):
        for col_z in (-0.25, 0.25):
            h = rng.randrange(6, 10)
            for k in range(h):
                b.box((c[0] + col_x, base_y + 0.065 + k * 0.13, c[2] + col_z), (0.34, 0.13, 0.22), yaw=rng.uniform(-4, 4),
                      style=no_bottom(rng.choice(("red", "blue", "bone", "cardboard", "black")), 1.0))


def prop_window_display(ctx, c, s):
    b, rng = ctx.b, ctx.rng
    b.box(c, s, style=lambda n, m, q: None if n[1] < -0.7 else (("bone", uv_world()) if n[1] > 0.7 else ("wood", uv_world(2.0))))
    top = c[1] + s[1] / 2
    for k in range(4):
        x = c[0] - s[0] / 2 + 0.5 + k * 0.9
        b.box((x, top + 0.15, c[2]), (0.3, 0.3, 0.3), style=no_bottom("trim", 1.0))                     # plinths
        shoe_pair(b, x, top + 0.3, c[2], rng.uniform(-40, 40), rng.choice(SHOE_COLOURS))
    b.poly([(c[0] + 1.3, top, c[2] + 0.3), (c[0] + 1.9, top, c[2] + 0.3), (c[0] + 1.9, top + 0.8, c[2] + 0.3),
            (c[0] + 1.3, top + 0.8, c[2] + 0.3)], (0, 0, 1), "decals", ctx.d("poster_sale"))           # faces the street


def prop_tv_shelf(ctx, c, s):
    """Burned TV shop: steel shelves of old TVs, a few left."""
    side = 1 if _front_into(c, 2) == "+z" else -1
    shelving(ctx, c, s, "x", (side,), "tvs", levels=3, frame="trim_dark", lip="black", fill=0.55)


def prop_tv_table(ctx, c, s):
    """Display plinth: three sets (one big flat screen), a video player, a remote and a price card."""
    b = ctx.b
    rng = random.Random(f"tvtable{c}")
    y0 = c[1] - s[1] / 2
    b.box((c[0], y0 + (s[1] - 0.05) / 2, c[2]), (s[0] - 0.1, s[1] - 0.05, s[2] - 0.1), style=no_bottom("trim_dark", 1.0))
    b.box((c[0], y0 + s[1] - 0.025, c[2]), (s[0], 0.05, s[2]), style=no_bottom("black", 1.0))
    top = y0 + s[1]
    face = 1 if _front_into(c, 2) == "+z" else -1
    for k in range(3):
        x = c[0] - s[0] / 2 + 0.45 + k * (s[0] - 0.9) / 2
        first = len(b.faces)
        stock_tv(b, (x, top, c[2] - 0.05), rng, rng.choice(("bone", "steel_light", "trim")))
        if face < 0:
            _turn_faces(b, first, (x, top, c[2] - 0.05), 180, False)
    b.box((c[0] + 0.3, top + 0.03, c[2] + face * 0.3), (0.36, 0.06, 0.24), style=no_bottom("black", 1.0))   # video
    b.box((c[0] - 0.4, top + 0.01, c[2] + face * 0.38), (0.05, 0.02, 0.16), yaw=30, style=no_bottom("black", 1.0))
    b.box((c[0] - 0.9, top + 0.06, c[2] + face * 0.38), (0.14, 0.1, 0.01), pitch=-20, style=no_bottom("bone", 1.0))


def prop_tv_counter(ctx, c, s):
    """TV shop counter: scorched, the till left on it, a box of cables."""
    b = ctx.b
    b.box((c[0], c[1] - 0.025, c[2]), (s[0], s[1] - 0.05, s[2]), style=no_bottom("trim_dark", 1.0))
    b.box((c[0], c[1] + s[1] / 2 - 0.025, c[2]), (s[0] + 0.06, 0.05, s[2] + 0.06), style=no_bottom("black", 1.0))
    top = c[1] + s[1] / 2
    face = -1 if _front_into(c, 2) == "+z" else 1                        # the clerk's side (against the wall)
    register(b, c[0] - s[0] / 4, top, c[2] + face * 0.05, face)
    b.box((c[0] + s[0] / 4, top + 0.1, c[2]), (0.4, 0.2, 0.3), style=no_bottom("cardboard", 1.0))
    for k in range(3):
        b.box((c[0] + s[0] / 4 - 0.1 + k * 0.1, top + 0.21, c[2]), (0.02, 0.02, 0.28), yaw=k * 20,
              style=no_bottom("black", 1.0))


def prop_box_stack(ctx, c, s):
    """Boxed stock stacked up (TVs, shoes...): cardboard boxes, a few tipped over."""
    b = ctx.b
    rng = random.Random(f"boxes{c}")
    y = c[1] - s[1] / 2
    while y < c[1] + s[1] / 2 - 0.2:
        h = rng.uniform(0.3, 0.45)
        b.box((c[0] + rng.uniform(-0.05, 0.05), y + h / 2, c[2] + rng.uniform(-0.05, 0.05)), (s[0] - 0.1, h, s[2] - 0.1),
              yaw=rng.uniform(-8, 8), style=no_bottom("cardboard", 1.0))
        y += h


def prop_bed(ctx, c, s):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box((c[0], base_y + 0.15, c[2]), (s[0], 0.3, s[2]), style=no_bottom("wood"))
    b.box((c[0], base_y + 0.37, c[2]), (s[0] - 0.1, 0.14, s[2] - 0.1), style=no_bottom("bone", 1.0))
    b.box((c[0], base_y + 0.46, c[2] - 0.35), (s[0] - 0.06, 0.06, s[2] * 0.7), yaw=3, style=no_bottom("blue", 1.0))
    b.box((c[0], base_y + 0.5, c[2] + s[2] / 2 - 0.3), (0.7, 0.12, 0.35), style=no_bottom("bone", 1.0))
    b.box((c[0], base_y + 0.55, c[2] + s[2] / 2 - 0.03), (s[0], 1.1, 0.06), style=no_bottom("wood"))  # headboard


def prop_plain_table(ctx, c, s):
    top = prop_table(ctx, c, s, "wood")
    ctx.b.box((c[0] + 0.2, top + 0.06, c[2]), (0.09, 0.12, 0.09), style=no_bottom("red", 1.0))         # mug
    for dx in (-0.9, 0.9):                                                                           # chairs
        cx = c[0] + dx
        ctx.b.box((cx, c[1] - s[1] / 2 + 0.45, c[2]), (0.42, 0.05, 0.42), style=no_bottom("wood"))
        for sx in (-1, 1):
            for sz in (-1, 1):
                ctx.b.box((cx + sx * 0.18, c[1] - s[1] / 2 + 0.22, c[2] + sz * 0.18), (0.04, 0.44, 0.04),
                          style=no_bottom("trim_dark", 1.0))




SHOPS_PROPS = {
    "washers": prop_washers, "dryers": prop_dryers, "fold_table": prop_fold_table, "shoe_wall": prop_shoe_wall,
    "bench": prop_bench, "shoe_table": prop_shoe_table, "shoe_counter": prop_shoe_counter,
    "shoebox_stack": prop_shoebox_stack, "window_display": prop_window_display, "tv_shelf": prop_tv_shelf,
    "tv_table": prop_tv_table, "bed": prop_bed, "table": prop_plain_table, "tv_counter": prop_tv_counter,
    "box_stack": prop_box_stack,
}
for _kind, _fn in SHOPS_PROPS.items():
    PROPS[_kind] = (lambda fn: lambda ctx, c, s, k: fn(ctx, c, s))(_fn)


def dress_shops(ctx):
    b, rng = ctx.b, ctx.rng
    zf = 6.65                                                       # the front (south) wall's outside face
    units = (-9.67, 0.0, 9.67)
    # Each shop front in its own colour (a band behind the sign), dark pilasters between them, a coping round the top.
    for x, col in zip(units, ("blue", "red", "trim_dark")):
        b.box((x, 2.8, zf + 0.015), (9.4, 0.9, 0.03), style=no_bottom(col, 1.0))
    b.box((14.665, 2.8, 0.0), (0.03, 0.9, 13.3), style=no_bottom("trim_dark", 1.0))
    for x in (-14.5, SHOP_UNITS[0], SHOP_UNITS[1], 14.5):
        b.box((x, 1.625, zf + 0.03), (0.4, 3.25, 0.06), style=no_bottom("trim_dark", 1.0))
    for z in (-zf - 0.03, zf + 0.03):
        b.box((0, 5.9, z), (29.4, 0.2, 0.06), style=no_bottom("trim_dark", 1.0))
    for x in (-14.68, 14.68):
        b.box((x, 5.9, 0), (0.06, 0.2, 13.3), style=no_bottom("trim_dark", 1.0))
    # Shop signs over the fronts, and the TV shop's on the road side too.
    for x, region in zip(units, ("sign_laundry", "sign_shoes", "sign_tv")):
        b.box((x, 2.75, zf + 0.04), (4.0, 0.7, 0.08), style=face_decal(ctx.d(region), "trim_dark", "+z"))
    b.box((14.69, 2.75, 0.0), (0.08, 0.7, 4.0), style=face_decal(ctx.d("sign_tv"), "trim_dark", "+x"))
    # Striped awning over the shoe store window (looks only).
    wx = units[1] - 1.6
    b.box((wx, 2.3, zf + 0.55), (4.6, 0.04, 1.2), pitch=18,
          style=lambda n, m, q: ("decals", ctx.d("awning")) if abs(n[1]) > 0.7 else ("red", uv_world()))
    # A concrete base round the outside (0.45 m), not across the doors.
    gaps = {"S": [(x + 2.2 - 1.1, x + 2.2 + 1.1) for x in units], "E": [(-1.1, 1.1)]}
    for side, (a0, a1, fixed) in {"S": (-14.65, 14.65, zf), "N": (-14.65, 14.65, -zf), "W": (-6.65, 6.65, -14.65),
                                  "E": (-6.65, 6.65, 14.65)}.items():
        cuts = [a0] + [v for g in gaps.get(side, []) for v in g] + [a1]
        for p0, p1 in zip(cuts[::2], cuts[1::2]):
            if side in "NS":
                b.box(((p0 + p1) / 2, 0.225, fixed), (p1 - p0, 0.45, 0.06), style=no_bottom("concrete", 4.0))
            else:
                b.box((fixed, 0.225, (p0 + p1) / 2), (0.06, 0.45, p1 - p0), style=no_bottom("concrete", 4.0))
    # Soot over the TV shop's openings, the Brotherhood's mark on the west end.
    for x in (units[2] - 1.6, units[2] + 2.2):
        b.poly([(x - 1.0, 2.0, zf + 0.01), (x + 1.0, 2.0, zf + 0.01), (x + 1.0, 3.5, zf + 0.01), (x - 1.0, 3.5, zf + 0.01)],
               (0, 0, 1), "graffiti", ctx.d("soot"))
    b.poly([(14.66, 2.0, -1.0), (14.66, 2.0, 1.0), (14.66, 3.5, 1.0), (14.66, 3.5, -1.0)], (1, 0, 0), "graffiti",
           ctx.d("soot"))
    b.poly([(-14.66, 0.8, 2.6), (-14.66, 0.8, 4.0), (-14.66, 1.8, 4.0), (-14.66, 1.8, 2.6)], (-1, 0, 0), "graffiti",
           ctx.d("x1"))
    # Posters inside.
    b.poly([(-4.72, 1.2, -3.2), (-4.72, 1.2, -2.6), (-4.72, 2.0, -2.6), (-4.72, 2.0, -3.2)], (1, 0, 0), "decals",
           ctx.d("poster_new"))
    b.poly([(-4.94, 1.2, 3.0), (-4.94, 1.2, 3.6), (-4.94, 2.0, 3.6), (-4.94, 2.0, 3.0)], (-1, 0, 0), "decals",
           ctx.d("poster_wash"))
    # Shoe store: a mirror by the benches, shoes kicked about, a foot gauge.
    b.box((4.71, 1.1, -3.6), (0.03, 1.7, 0.7), style=no_bottom("trim_dark", 1.0))
    b.poly([(4.69, 0.3, -3.9), (4.69, 0.3, -3.3), (4.69, 1.9, -3.3), (4.69, 1.9, -3.9)], (-1, 0, 0), "steel_light", uv_world())
    for _ in range(5):
        shoe_pair(b, rng.uniform(-3.5, 2.0), 0.0, rng.uniform(-2.5, 1.5), rng.uniform(0, 360), rng.choice(SHOE_COLOURS))
    b.box((-1.0, 0.03, -3.0), (0.25, 0.06, 0.4), style=no_bottom("trim", 1.0))
    # Laundromat: plastic chairs, a dropped basket, a change machine.
    for k in range(3):                                   # waiting chairs along the back wall (not in the doorway)
        chair(b, -7.9 + k * 0.62, 0.0, -5.95, 0.0 + 180.0, "yellow", "trim_dark")
    b.box((-11.5, 0.15, 1.4), (0.55, 0.3, 0.4), yaw=25, style=no_bottom("blue", 1.0))
    for _ in range(4):
        b.box((-11.2 + rng.uniform(-0.6, 0.6), 0.02, 1.9 + rng.uniform(-0.4, 0.4)), (0.4, 0.03, 0.3),
              yaw=rng.uniform(0, 90), style=no_bottom(rng.choice(("bone", "red", "olive")), 1.0))
    b.box((-5.2, 0.7, -2.6), (0.4, 1.4, 0.5), style=no_bottom("steel_light", 1.0))
    # TV shop: a TV face down on the floor, burnt rubbish.
    b.box((7.2, 0.25, 1.5), (0.8, 0.5, 0.5), yaw=30, pitch=80, style=no_bottom("trim_dark", 1.0))
    for _ in range(10):
        w = rng.uniform(0.15, 0.5)
        b.box((rng.uniform(5.5, 13.5), 0.04, rng.uniform(-4.5, 5.0)), (w, 0.05, w * rng.uniform(0.6, 1.5)),
              yaw=rng.uniform(0, 90), style=no_bottom(rng.choice(("black", "trim_dark", "cardboard")), 1.0))
    # Upstairs flat: the laundromat owner's flat, used as somebody's hideout in the war: a sleeping bag on the floor,
    # a radio and a map on the table, ammo tins, empty cans, a chair set back from the window to watch the street.
    b.box((-6.2, 3.03, 3.6), (0.8, 0.06, 1.9), yaw=8, style=no_bottom("olive", 1.0))
    b.box((-6.3, 3.07, 2.85), (0.6, 0.08, 0.3), yaw=8, style=no_bottom("olive_dark", 1.0))
    b.box((-8.5, 3.83, -1.0), (0.3, 0.16, 0.12), style=no_bottom("olive_dark", 1.0))                 # radio
    b.box((-8.38, 4.01, -1.0), (0.01, 0.22, 0.01), pitch=12, style=no_bottom("black", 1.0))
    b.box((-9.0, 3.755, -0.95), (0.5, 0.005, 0.38), yaw=-12, style=no_bottom("bone", 1.0))           # map
    for k in range(3):
        b.box((-5.6, 3.12, 0.8 + k * 0.32), (0.14, 0.24, 0.28), style=no_bottom("olive", 1.0))     # ammo tins
    for _ in range(7):
        b.box((rng.uniform(-13.5, -6.0), 3.04, rng.uniform(-3.0, 4.0)), (0.07, 0.07, 0.12), pitch=90,
              yaw=rng.uniform(0, 180), style=no_bottom(rng.choice(("steel_light", "red", "olive")), 1.0))
    chair(b, -9.6, 3.0, 4.6, 180.0, "wood", "trim_dark")
    # A rug, a lamp; stock room: shoeboxes on the floor.
    b.box((-11.5, 3.01, 1.5), (2.0, 0.01, 1.4), style=lambda n, m, q: ("red", uv_world()) if n[1] > 0.7 else None)
    b.box((-13.9, 3.6, -2.0), (0.06, 1.2, 0.06), style=no_bottom("trim_dark", 1.0))
    b.box((-13.9, 4.25, -2.0), (0.3, 0.25, 0.3), style=no_bottom("bone", 1.0))
    for k in range(6):
        b.box((-2.0 + k * 0.4, 3.065 + (k % 2) * 0.13, 4.8 + rng.uniform(-0.1, 0.1)), (0.34, 0.13, 0.22),
              yaw=rng.uniform(-10, 10), style=no_bottom(rng.choice(("red", "blue", "bone", "cardboard")), 1.0))


DECALS["shops"] = shops_decals
DRESSING["shops"] = dress_shops
FOOTPRINTS["shops"] = (-14.5, -6.5, 14.5, 6.5)
SHELLS = {
    "shops": {
        "ext": "render", "roof_side": "render", "x_splits": SHOP_UNITS,
        "x_lines": (-14.5,) + SHOP_UNITS + (14.5,), "z_lines": (-6.5, 6.5),
        "inner": lambda m: (("int_tile", "int_warm", "int_soot") if m[1] < 3.0 else ("int_wall", "concrete", "int_soot"))[shop_unit(m[0])],
        "floor": lambda m: (("floor_tile", "floor_wood", "floor_burnt") if m[1] < 1.5 else ("floor_wood", "concrete", "floor_burnt"))[shop_unit(m[0])],
        "ceiling": lambda m: "ceiling_soot" if shop_unit(m[0]) == 2 else "ceiling",
    },
}


# ------------------------------------------------------------------------------------------------ school (0.17)
# Bloxov School (map 8-38 x 50-74, model origin map (23, 62)): 3 x 3 rooms of 10 x 8 m on two floors, a flat roof
# with a parapet. Room (i, j): i west to east, j north to south.
def school_room(m):
    return max(0, min(2, int((m[0] + 15) // 10))), max(0, min(2, int((m[2] + 12) // 8)))


SCHOOL_WALLS = {   # (floor, i, j) -> inside walls, floor
    (0, 0, 0): ("int_warm", "carpet"), (0, 0, 1): ("int_tile", "floor_tile"), (0, 0, 2): ("int_tile", "floor_tile"),
    (0, 2, 2): ("int_warm", "carpet"), (1, 1, 2): ("int_warm", "carpet"),
    # Floors (owner, 0.17): terrazzo in the halls and lobby, parquet in the classrooms, rubber in the art room;
    # the lab and computer room keep the speckled lino.
    (0, 1, 1): ("int_school", "terrazzo"), (1, 1, 1): ("int_school", "terrazzo"), (0, 1, 2): ("int_school", "terrazzo"),
    (0, 1, 0): ("int_school", "parquet"), (0, 2, 1): ("int_school", "parquet"), (1, 1, 0): ("int_school", "parquet"),
    (1, 2, 0): ("int_school", "parquet"), (1, 2, 1): ("int_school", "parquet"), (1, 0, 2): ("int_school", "parquet"),
    (1, 0, 0): ("int_school", "rubber"),
}


def school_inner(m):
    if m[1] > 6.0:
        return "brick_tan"                                          # the parapet's inside
    return SCHOOL_WALLS.get((int(m[1] >= 3.0),) + school_room(m), ("int_school", "floor_lino"))[0]


def school_floor(m):
    return SCHOOL_WALLS.get((int(m[1] >= 2.0),) + school_room(m), ("int_school", "floor_lino"))[1]


def paint_int_school(rng):
    """School corridor paint: pale green to 1.2 m with a dark rail, cream above."""
    c = Canvas(64, 64, "bone")
    c.rect(0, 0, 64, 19, "olive_light")
    c.rect(0, 19, 64, 21, "olive_dark")
    c.rect(0, 0, 64, 2, "olive_dark")
    c.blotch(["concrete"], 6, rng, area=(0, 21, 64, 64), size=(2, 5))
    c.blotch(["olive"], 6, rng, area=(0, 2, 64, 19), size=(2, 4))
    return c


def paint_floor_lino(rng):
    """Speckled vinyl tiles (0.5 m), a few scuffs."""
    c = Canvas(64, 64, "concrete")
    for ty in range(8):
        for tx in range(8):
            col = "bone" if (tx + ty) % 2 == 0 else "concrete"
            c.rect(tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8, col)
            for _ in range(3):
                c.put(tx * 8 + rng.randrange(8), ty * 8 + rng.randrange(8), "steel")
    for y in range(64):
        for x in range(0, 64, 8):
            c.put(x, y, "steel_light")
            c.put(y, x, "steel_light")
    c.blotch(["sand"], 4, rng, size=(2, 4))
    return c


def paint_carpet(rng):
    c = Canvas(64, 64, "sky_blue")
    for y in range(64):
        for x in range(64):
            if (x // 2 + y // 2) % 4 == 0:
                c.put(x, y, "iron")
    c.blotch(["iron_dark", "steel"], 5, rng, size=(2, 5))
    return c


def paint_brick_tan(rng):
    """Pale tan school brick (0.5 x 0.25 m bricks)."""
    c = Canvas(64, 64, "concrete")
    for row in range(16):
        off = 4 if row % 2 else 0
        for k in range(8):
            col = rng.choice(("wood_pale", "wood_pale", "sand", "wood_light", "wood_pale"))
            x = k * 8 + off + 1
            for xx in range(x, x + 7):
                c.rect(xx % 64, row * 4 + 1, xx % 64 + 1, row * 4 + 4, col)
    c.blotch(["sand", "wood_light"], 6, rng, size=(2, 4))
    return c


def paint_terrazzo(rng):
    """Speckled stone with brass divider strips every 2 m."""
    c = Canvas(64, 64, "bone")
    for _ in range(260):
        x, y = rng.randrange(64), rng.randrange(64)
        col = rng.choice(("concrete", "steel", "sand", "olive_light", "red", "sky_blue", "wood_light"))
        c.put(x, y, col)
        if rng.random() < 0.3:
            c.put((x + 1) % 64, y, col)
    for k in range(0, 64, 32):
        c.rect(k, 0, k + 1, 64, "yellow_dark")
        c.rect(0, k, 64, k + 1, "yellow_dark")
    c.blotch(["sand"], 3, rng, size=(2, 4))
    return c


def paint_parquet(rng):
    """Wood blocks (1 m squares of four planks), alternating direction."""
    c = Canvas(64, 64, "wood_light")
    for by in range(0, 64, 16):
        for bx in range(0, 64, 16):
            horiz = ((bx + by) // 16) % 2 == 0
            for k in range(4):
                col = rng.choice(("wood_light", "wood", "wood_pale"))
                if horiz:
                    c.rect(bx, by + k * 4, bx + 16, by + k * 4 + 4, col)
                    c.rect(bx, by + k * 4, bx + 16, by + k * 4 + 1, "wood_mid")
                else:
                    c.rect(bx + k * 4, by, bx + k * 4 + 4, by + 16, col)
                    c.rect(bx + k * 4, by, bx + k * 4 + 1, by + 16, "wood_mid")
    c.blotch(["wood_mid"], 3, rng, size=(2, 4))                       # scuffs
    return c


def paint_rubber(rng):
    """Blue speckled rubber flooring with a yellow line."""
    c = Canvas(64, 64, "sky_blue")
    for _ in range(500):
        c.put(rng.randrange(64), rng.randrange(64), rng.choice(("iron", "bone", "steel_light", "iron_dark")))
    c.rect(0, 30, 64, 32, "hazard_yellow")
    return c


KIT.update({"terrazzo": paint_terrazzo, "parquet": paint_parquet, "rubber": paint_rubber,
            "int_school": paint_int_school, "floor_lino": paint_floor_lino, "carpet": paint_carpet,
            "brick_tan": paint_brick_tan, "green": paint_flat("green_dark"), "olive_dark": paint_flat("olive_dark")})


def school_decals(rng):
    a = Atlas(512)

    def board(c):         # 3 x 1.2 m chalkboard
        c.rect(0, 0, c.w, c.h, "wood_mid")
        c.rect(2, 3, c.w - 2, c.h - 2, "green_dark")
        c.rect(2, 2, c.w - 2, 3, "wood_dark")                            # chalk tray
        c.text(5, c.h - 9, "A+B=C", "bone")
        c.text(5, c.h - 17, "2X+3=9", "bone")
        c.text(5, c.h - 25, "X=3", "bone")
        c.text(c.w - 30, c.h - 9, "TEST", "bone")
        c.text(c.w - 30, c.h - 17, "FRI", "bone")
        c.blotch(["olive"], 4, rng, area=(2, 3, c.w - 2, c.h - 2), size=(3, 6))   # half-wiped chalk

    def locker(c):        # one school locker, 0.5 x 2.0 m
        c.rect(0, 0, c.w, c.h, "red")
        c.frame(0, 0, c.w, c.h, "rust")
        for k in range(4):
            c.rect(3, c.h - 6 - k * 2, c.w - 3, c.h - 5 - k * 2, "rust")
        c.rect(c.w - 5, 28, c.w - 3, 34, "steel_light")
        c.rect(3, 50, 9, 52, "bone")
        c.blotch(["rust"], 2, rng, size=(2, 3))

    def books(c):         # 1.2 x 1.8 m of bookshelf
        c.rect(0, 0, c.w, c.h, "wood_dark")
        for row in range(4):
            y = 2 + row * 14
            c.rect(0, y - 2, c.w, y, "wood")
            x = 1
            while x < c.w - 2:
                w = rng.choice((2, 2, 3))
                h = rng.randrange(8, 12)
                if rng.random() < 0.85:
                    c.rect(x, y, x + w, y + h, rng.choice(("red", "sky_blue", "olive", "bone", "wood_pale", "rust", "green_dark")))
                x += w
        c.frame(0, 0, c.w, c.h, "wood")

    def trophy(c):        # 2.6 x 1.9 m trophy case
        c.rect(0, 0, c.w, c.h, "wood_mid")
        c.rect(3, 22, c.w - 3, c.h - 3, "iron_dark")
        for y in (22, 38, 52):
            c.rect(3, y, c.w - 3, y + 1, "steel_light")
            for x in range(8, c.w - 8, 14):
                if rng.random() < 0.75:
                    c.rect(x, y + 1, x + 4, y + 3, "yellow_dark")
                    c.rect(x + 1, y + 3, x + 3, y + 7, "hazard_yellow")
                    c.rect(x - 1, y + 7, x + 5, y + 10, "hazard_yellow")
        c.rect(c.w // 2, 22, c.w // 2 + 1, c.h - 3, "wood_mid")
        c.frame(3, 3, c.w - 3, 19, "wood_dark")

    def sign(c):          # 6 x 0.8 m over the entrance
        c.rect(0, 0, c.w, c.h, "olive_dark")
        c.frame(0, 0, c.w, c.h, "bone")
        w = Canvas.text_width("BLOXOV SCHOOL", 3)
        c.ctext(0, c.w, 5, "BLOXOV SCHOOL", "bone", 3)

    def notice(c):        # 1.6 x 1 m cork board
        c.rect(0, 0, c.w, c.h, "wood_light")
        c.frame(0, 0, c.w, c.h, "wood_dark")
        for _ in range(9):
            x, y = rng.randrange(3, c.w - 10), rng.randrange(3, c.h - 10)
            c.rect(x, y, x + rng.randrange(6, 10), y + rng.randrange(7, 10), rng.choice(("bone", "bone", "hazard_yellow", "sky_blue")))
            c.put(x + 2, y + 6, "red")

    def poster(text, colour, ink):
        def paint(c):     # 0.6 x 0.8 m
            c.rect(0, 0, c.w, c.h, colour)
            c.frame(0, 0, c.w, c.h, ink)
            w = Canvas.text_width(text)
            c.ctext(0, c.w, c.h // 2 - 2, text, ink)
        return paint

    def nurse(c):         # green cross sign (not the protected red cross)
        c.rect(0, 0, c.w, c.h, "bone")
        m = c.w // 2                                              # (odd size: arms the same length, owner)
        c.rect(m - 2, 3, m + 3, c.h - 3, "green_dark")
        c.rect(3, m - 2, c.w - 3, m + 3, "green_dark")

    def menu(c):          # 2 x 0.9 m
        c.rect(0, 0, c.w, c.h, "black")
        c.frame(0, 0, c.w, c.h, "steel")
        c.text(4, c.h - 8, "LUNCH", "hazard_yellow")
        for k, item in enumerate(("SOUP 2", "PIZZA 3", "MILK 1")):
            c.text(4, c.h - 16 - k * 7, item, "bone")

    def graffiti(c):      # NOVA, sprayed (the other army: docs/LORE.md)
        c.rect(0, 0, c.w, c.h, "clear")
        w = Canvas.text_width("NOVA", 4)
        c.ctext(0, c.w, 4, "NOVA", "sky_blue", 4)
        for _ in range(5):
            x = rng.randrange(4, c.w - 4)
            c.rect(x, 0, x + 1, rng.randrange(2, 5), "sky_blue")

    def clock(c):
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "iron_dark")
        c.rect(c.w // 2, c.h // 2, c.w // 2 + 1, c.h - 3, "black")
        c.rect(c.w // 2, c.h // 2, c.w - 4, c.h // 2 + 1, "black")

    a.add("board", 96, 38, board)
    a.add("locker", 16, 64, locker)
    a.add("books", 38, 58, books)
    a.add("trophy", 83, 61, trophy)
    a.add("sign", 192, 26, sign)
    a.add("notice", 51, 32, notice)
    a.add("poster_read", 19, 26, poster("READ", "sky_blue", "bone"))
    a.add("poster_run", 19, 26, poster("WALK", "hazard_yellow", "black"))
    a.add("nurse", 19, 19, nurse)
    a.add("menu", 64, 29, menu)
    a.add("graffiti", 80, 30, graffiti)
    a.add("clock", 13, 13, clock)

    def welcome(c):       # 3.2 x 0.6 m banner inside the entrance
        c.rect(0, 0, c.w, c.h, "sky_blue")
        c.frame(0, 0, c.w, c.h, "bone")
        c.ctext(0, c.w, 6, "WELCOME BACK", "bone", 1)
        c.blotch(["concrete", "black"], 4, rng, size=(2, 4))
    a.add("welcome", 102, 19, welcome)
    return a


def prop_chalkboard(ctx, c, s):
    ctx.b.box(c, s, style=face_decal(ctx.d("board"), "wood", _front_into(c, 2)))


def prop_school_desk(ctx, c, s):
    b = ctx.b
    first = len(b.faces)
    top = prop_table(ctx, c, s, "wood", "trim")
    base = c[1] - s[1] / 2
    _turn_faces(b, first, (c[0], base, c[2]), ctx.rng.uniform(-9, 9), False)   # shoved about (war mess, owner)
    chair(b, c[0], base, c[2] + s[2] / 2 + 0.28, 0.0, "blue", "trim")          # facing the board (north)
    if ctx.rng.random() < 0.4:
        b.box((c[0] + ctx.rng.uniform(-0.2, 0.2), top + 0.01, c[2]), (0.21, 0.01, 0.3), yaw=ctx.rng.uniform(-30, 30),
              style=no_bottom("bone", 1.0))                                  # a worksheet


def prop_lab_bench(ctx, c, s):
    b = ctx.b
    b.box((c[0], c[1] - 0.03, c[2]), (s[0], s[1] - 0.06, s[2]), style=no_bottom("bone", 1.0))
    top = c[1] + s[1] / 2
    b.box((c[0], top - 0.03, c[2]), (s[0] + 0.04, 0.06, s[2] + 0.04), style=no_bottom("black", 1.0))
    b.box((c[0], top + 0.15, c[2]), (0.05, 0.3, 0.05), style=no_bottom("trim", 1.0))           # tap
    for k, col in enumerate(("green", "blue", "bone")):
        b.box((c[0] - 0.8 + k * 0.25, top + 0.08, c[2] + 0.1), (0.08, 0.16, 0.08), style=no_bottom(col, 1.0))


def prop_bookshelf(ctx, c, s):
    """Library shelves, books on both sides."""
    shelving(ctx, c, s, "x", (1, -1), "books", levels=5, frame="wood", lip="wood", fill=0.75)


def prop_caf_table(ctx, c, s):
    b = ctx.b
    top = prop_table(ctx, c, s, "bone", "trim")
    base = c[1] - s[1] / 2
    for side in (-1, 1):
        b.box((c[0], base + 0.45, c[2] + side * (s[2] / 2 + 0.3)), (s[0], 0.05, 0.3), style=no_bottom("red", 1.0))
        for sx in (-1, 1):
            b.box((c[0] + sx * (s[0] / 2 - 0.2), base + 0.22, c[2] + side * (s[2] / 2 + 0.3)), (0.05, 0.44, 0.05),
                  style=no_bottom("trim", 1.0))
    for k in range(3):
        if ctx.rng.random() < 0.7:
            b.box((c[0] - 1.0 + k * 1.0, top + 0.02, c[2] + ctx.rng.uniform(-0.15, 0.15)), (0.4, 0.03, 0.3),
                  yaw=ctx.rng.uniform(-20, 20), style=no_bottom(ctx.rng.choice(("steel_light", "olive", "red")), 1.0))


def prop_hall_lockers(ctx, c, s):
    b = ctx.b
    front = _front_into(c, 2)
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b.box(c, s, style=lambda n, m, q: None if side_of(n) in (front, "-y") else ("red", uv_world()))
    z = c[2] + (s[2] / 2 if front == "+z" else -s[2] / 2)
    strip_quads(ctx, c[0] - s[0] / 2, c[0] + s[0] / 2, y0, y1, z, (0, 0, 1 if front == "+z" else -1), "locker", 0.5, "x")
    if ctx.rng.random() < 0.5:                                           # one hanging open
        x = c[0] + ctx.rng.uniform(-1.2, 1.2)
        dz = 0.25 if front == "+z" else -0.25
        b.box((x, c[1], z + dz), (0.03, s[1] - 0.1, 0.48), yaw=0, style=no_bottom("red", 1.0))


def prop_trophy_case(ctx, c, s):
    """Trophy case (refine pass: 3D): wooden cabinet below, a glass case above with glass shelves, blue felt at the
    back and real little trophies (cups with handles, figure trophies, plaques)."""
    b, rng = ctx.b, random.Random(f"trophy{c}")
    face = 1 if _front_into(c, 2) == "+z" else -1
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    zb, zf = c[2] - face * s[2] / 2, c[2] + face * s[2] / 2           # back and front planes
    mid_z = c[2]
    base_h = 0.62
    b.box((c[0], y0 + base_h / 2, mid_z), (s[0], base_h, s[2]), style=no_bottom("wood", 1.0))        # cabinet
    for k in range(2):                                                                                # its doors
        dx = x0 + s[0] * (k + 0.5) / 2
        b.box((dx, y0 + 0.33, zf + face * 0.006), (s[0] / 2 - 0.12, 0.42, 0.012), style=no_bottom("trim_dark", 1.0))
        b.box((dx + (0.15 if k == 0 else -0.15) * 1, y0 + 0.36, zf + face * 0.018), (0.03, 0.12, 0.02),
              style=no_bottom("yellow", 1.0))
    b.box((c[0], (y0 + base_h + y1) / 2, zb + face * 0.015), (s[0], y1 - y0 - base_h, 0.03), style=no_bottom("blue", 1.0))
    for x in (x0 + 0.03, x1 - 0.03, c[0]):                                                            # frame posts
        b.box((x, (y0 + base_h + y1) / 2, zf - face * 0.025), (0.06 if x != c[0] else 0.04, y1 - y0 - base_h, 0.05),
              style=no_bottom("wood", 1.0))
    b.box((c[0], y1 - 0.04, mid_z), (s[0], 0.08, s[2]), style=lambda n, m, q: ("wood", uv_world(1.0)))  # top
    shelves = (y0 + base_h, y0 + base_h + 0.42, y0 + base_h + 0.82)
    depth = s[2] - 0.1
    for k, y in enumerate(shelves):
        if k:
            b.box((c[0], y - 0.01, mid_z), (s[0] - 0.08, 0.02, depth), style=lambda n, m, q: ("glass", uv_world(1.0)))
        # Trophies along the shelf, some gone (looted), a few knocked over.
        x = x0 + 0.16
        while x < x1 - 0.16:
            if rng.random() < 0.8:
                kind = rng.choice(("cup", "cup", "figure", "plaque"))
                metal = rng.choice(("yellow", "yellow", "steel_light"))
                zz = mid_z + face * rng.uniform(-0.04, 0.04)
                trophy(b, x, y, zz, kind, metal, rng.uniform(0.22, 0.34), face)
            x += rng.uniform(0.24, 0.34)
    for k in range(2):                                                                                # glass doors
        a, e = (x0 + 0.06, c[0] - 0.02) if k == 0 else (c[0] + 0.02, x1 - 0.06)
        shards(ctx, a, e, y0 + base_h, y1 - 0.08, zf, "x", rng)                 # smashed in


def trophy(b, x, y, z, kind, metal, h, face):
    """One small trophy standing at (x, y, z), `h` tall: a dark base, then a cup with handles, a little figure on a
    column, or a plaque (wooden board with a metal plate) facing out."""
    b.group = ("item", len(b.faces))
    nb = lambda mat: no_bottom(mat, 1.0)
    if kind == "plaque":
        b.box((x, y + h * 0.4, z - face * 0.04), (0.16, h * 0.8, 0.03), pitch=-8 * face, style=nb("wood"))
        b.box((x, y + h * 0.42, z - face * 0.022), (0.11, h * 0.4, 0.008), pitch=-8 * face, style=nb(metal))
        b.group = None
        return
    b.box((x, y + 0.03, z), (0.1, 0.06, 0.1), style=nb("black"))                                      # base
    b.box((x, y + 0.075, z), (0.07, 0.03, 0.07), style=nb("black"))
    if kind == "cup":
        b.box((x, y + 0.09 + h * 0.15, z), (0.025, h * 0.3, 0.025), style=nb(metal))                   # stem
        b.box((x, y + 0.09 + h * 0.3 + 0.01, z), (0.06, 0.02, 0.06), style=nb(metal))
        cup_h = h * 0.45
        b.box((x, y + 0.09 + h * 0.3 + 0.02 + cup_h / 2, z), (0.1, cup_h, 0.1), style=nb(metal))       # cup
        for sx in (-1, 1):                                                                             # handles
            b.box((x + sx * 0.065, y + 0.09 + h * 0.3 + 0.02 + cup_h * 0.6, z), (0.03, cup_h * 0.5, 0.015), style=nb(metal))
    else:
        b.box((x, y + 0.09 + h * 0.25, z), (0.045, h * 0.5, 0.045), style=nb("bone"))                 # column
        fy = y + 0.09 + h * 0.5
        b.box((x, fy + h * 0.12, z), (0.04, h * 0.24, 0.03), style=nb(metal))                          # body
        b.box((x, fy + h * 0.27, z), (0.03, 0.03, 0.03), style=nb(metal))                              # head
        b.box((x + 0.03, fy + h * 0.2, z), (0.06, 0.012, 0.012), yaw=0, pitch=0, style=nb(metal))      # arm up
    b.group = None


def prop_hall_bench(ctx, c, s):
    b = ctx.b
    base = c[1] - s[1] / 2
    b.box((c[0], base + s[1] - 0.03, c[2]), (s[0], 0.06, s[2]), style=no_bottom("wood", 1.0))
    for sx in (-1, 1):
        b.box((c[0] + sx * (s[0] / 2 - 0.1), base + (s[1] - 0.06) / 2, c[2]), (0.06, s[1] - 0.06, s[2] - 0.05),
              style=no_bottom("trim", 1.0))


def prop_cot(ctx, c, s):
    b = ctx.b
    base = c[1] - s[1] / 2
    b.box((c[0], base + 0.42, c[2]), (s[0], 0.06, s[2]), style=no_bottom("trim", 1.0))
    b.box((c[0], base + 0.52, c[2]), (s[0] - 0.1, 0.14, s[2] - 0.1), style=no_bottom("bone", 1.0))
    b.box((c[0], base + 0.62, c[2] + s[2] / 2 - 0.3), (0.6, 0.1, 0.3), style=no_bottom("bone", 1.0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((c[0] + sx * (s[0] / 2 - 0.05), base + 0.2, c[2] + sz * (s[2] / 2 - 0.05)), (0.04, 0.4, 0.04),
                  style=no_bottom("trim", 1.0))


def prop_art_table(ctx, c, s):
    top = prop_table(ctx, c, s, "bone", "trim_dark")
    for _ in range(6):
        col = ctx.rng.choice(("red", "blue", "yellow", "green"))
        ctx.b.box((c[0] + ctx.rng.uniform(-1.0, 1.0), top + 0.005, c[2] + ctx.rng.uniform(-0.4, 0.4)),
                  (ctx.rng.uniform(0.1, 0.3), 0.01, ctx.rng.uniform(0.1, 0.3)), style=no_bottom(col, 1.0))   # paint
    ctx.b.box((c[0] + 0.6, top + 0.08, c[2]), (0.3, 0.16, 0.2), style=no_bottom("blue", 1.0))      # paint pots


def prop_computer_desk(ctx, c, s):
    """Computer lab desk: two PCs side by side."""
    b = ctx.b
    top = prop_table(ctx, c, s, "bone", "trim")
    face = 1 if _front_into(c, 2) == "+z" else -1
    for k in range(2):
        x = c[0] - s[0] / 4 + k * s[0] / 2
        pc(ctx, x - 0.1, top, c[2], face)
        chair(b, x + ctx.rng.uniform(-0.1, 0.1), c[1] - s[1] / 2, c[2] + face * (s[2] / 2 + 0.3),
              facing_yaw(0, -face) + ctx.rng.uniform(-25, 25), "black", "trim", office=True)


# ---- furniture kit (refine pass, owner: "some of the rooms are just not furnished properly"): chairs, sofas,
# kitchenettes, vending machines, filing cabinets, plants; shared by every building.
def _at(x, z, yaw, ox, oz):
    p = rot((ox, 0, oz), yaw, 0)
    return x + p[0], z + p[2]


def facing_yaw(dx, dz):
    """The yaw that turns a chair (or sofa) to face along (dx, dz)."""
    return math.degrees(math.atan2(-dx, -dz))


def chair(b, x, y, z, yaw, seat="blue", frame="trim", office=False):
    """A chair standing at (x, y, z) facing local -z turned by yaw. office: a swivel chair on a star base.
    War mess (owner: "everything looks too perfect"): pushed about a little, and now and then knocked over."""
    mess = random.Random(f"chair{x:.2f}{y:.1f}{z:.2f}")
    x, z = x + mess.uniform(-0.1, 0.1), z + mess.uniform(-0.1, 0.1)
    yaw += mess.uniform(-20, 20)
    knocked = mess.random() < 0.14
    first = len(b.faces)
    b.group = ("item", len(b.faces))
    nb = lambda mat: no_bottom(mat, 1.0)
    if office:
        b.box((x, y + 0.03, z), (0.56, 0.04, 0.06), yaw=yaw + 45, style=nb("black"))
        b.box((x, y + 0.03, z), (0.56, 0.04, 0.06), yaw=yaw - 45, style=nb("black"))
        b.box((x, y + 0.24, z), (0.05, 0.4, 0.05), style=nb("trim"))
        b.box((x, y + 0.47, z), (0.48, 0.08, 0.46), yaw=yaw, style=nb(seat))
        bx, bz = _at(x, z, yaw, 0, 0.22)
        b.box((bx, y + 0.8, bz), (0.44, 0.5, 0.06), yaw=yaw, pitch=-6, style=nb(seat))
        for sx in (-1, 1):
            ax, az = _at(x, z, yaw, sx * 0.25, 0.02)
            b.box((ax, y + 0.62, az), (0.04, 0.04, 0.32), yaw=yaw, style=nb("black"))
    else:
        b.box((x, y + 0.45, z), (0.42, 0.05, 0.42), yaw=yaw, style=nb(seat))
        for sx in (-1, 1):
            for sz in (-1, 1):
                lx, lz = _at(x, z, yaw, sx * 0.18, sz * 0.18)
                b.box((lx, y + 0.22, lz), (0.035, 0.44, 0.035), yaw=yaw, style=nb(frame))
        bx, bz = _at(x, z, yaw, 0, 0.19)
        b.box((bx, y + 0.72, bz), (0.42, 0.34, 0.04), yaw=yaw, style=nb(seat))
    if knocked:
        _turn_faces(b, first, (x, y, z), mess.uniform(0, 180), True)
    b.group = None


def _long_axis(s):
    return "x" if s[0] >= s[2] else "z"


def _front(c, s):
    """(axis index, +1/-1): which way a wall unit's front faces (into the room, across its long side)."""
    k = 2 if _long_axis(s) == "x" else 0
    return k, (1 if _front_into(c, k)[0] == "+" else -1)


def _pos(c, k, along, out, y=0.0):
    """A point `along` the unit's length and `out` towards its front (k: the front axis), y up from c."""
    return (c[0] + along, c[1] + y, c[2] + out) if k == 2 else (c[0] + out, c[1] + y, c[2] + along)


def _sz(k, along, h, out):
    return (along, h, out) if k == 2 else (out, h, along)


def prop_sofa(ctx, c, s):
    """A sofa against the wall: base, seat cushions, back and arms (refine pass)."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    y0 = c[1] - s[1] / 2
    col, dark = "olive", "olive_dark"
    b.box(_pos(c, k, 0, 0, -s[1] / 2 + 0.12), _sz(k, L, 0.24, D), style=no_bottom(dark, 1.0))
    n = max(2, round((L - 0.3) / 0.7))
    w = (L - 0.3) / n
    for i in range(n):                                                                  # seat cushions
        a = -L / 2 + 0.15 + w * (i + 0.5)
        b.box(_pos(c, k, a, f * 0.08, -s[1] / 2 + 0.31), _sz(k, w - 0.02, 0.14, D - 0.32), style=no_bottom(col, 1.0))
        b.box(_pos(c, k, a, -f * (D / 2 - 0.16), -s[1] / 2 + 0.6), _sz(k, w - 0.02, 0.44, 0.18), style=no_bottom(col, 1.0))
    b.box(_pos(c, k, 0, -f * (D / 2 - 0.06), -s[1] / 2 + 0.45), _sz(k, L, 0.9, 0.12), style=no_bottom(dark, 1.0))
    for sx in (-1, 1):                                                                  # arms
        b.box(_pos(c, k, sx * (L / 2 - 0.08), 0, -s[1] / 2 + 0.3), _sz(k, 0.16, 0.6, D), style=no_bottom(dark, 1.0))


def kitchenette(ctx, c, s, microwave=True):
    """Kitchen run against a wall (refine pass, was a painted box): cupboards with doors, a worktop with a sink and
    tap, a microwave and kettle, wall cupboards above."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    h = s[1]
    lo = -s[1] / 2
    b.box(_pos(c, k, 0, -0.02 * f, lo + (h - 0.04) / 2), _sz(k, L, h - 0.04, D - 0.04), style=no_bottom("bone", 1.0))
    b.box(_pos(c, k, 0, 0, lo + h - 0.02), _sz(k, L + 0.02, 0.04, D + 0.02), style=no_bottom("black", 1.0))   # worktop
    n = max(1, round(L / 0.6))
    for i in range(n):                                                                    # door gaps and handles
        a = -L / 2 + L * (i + 0.5) / n
        b.box(_pos(c, k, a, f * (D / 2 - 0.035), lo + 0.48), _sz(k, L / n - 0.04, h - 0.22, 0.012), style=no_bottom("steel_light", 1.0))
        b.box(_pos(c, k, a + L / n * 0.3, f * (D / 2 - 0.02), lo + h - 0.2), _sz(k, 0.1, 0.02, 0.02), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, 0, f * (D / 2 - 0.03), lo + 0.05), _sz(k, L - 0.02, 0.1, 0.012), style=no_bottom("black", 1.0))
    sa = -L / 2 + min(0.6, L * 0.3)
    b.box(_pos(c, k, sa, 0, lo + h - 0.07), _sz(k, 0.5, 0.06, D * 0.6), style=lambda n_, m, q: ("trim", uv_world(1.0)) if n_[1] > 0.7 else None)  # sink basin
    b.box(_pos(c, k, sa, -f * (D / 2 - 0.08), lo + h + 0.12), _sz(k, 0.04, 0.24, 0.04), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, sa, -f * (D / 2 - 0.16), lo + h + 0.23), _sz(k, 0.04, 0.03, 0.16), style=no_bottom("trim", 1.0))
    if microwave and L > 1.2:
        ma = L / 2 - 0.35
        b.group = ("item", len(b.faces))
        b.box(_pos(c, k, ma, -f * 0.03, lo + h + 0.15), _sz(k, 0.5, 0.3, 0.36), style=no_bottom("black", 1.0))
        b.box(_pos(c, k, ma - 0.05, f * 0.151, lo + h + 0.15), _sz(k, 0.32, 0.2, 0.004), style=no_bottom("glass", 1.0))
        b.box(_pos(c, k, ma + 0.18, f * 0.151, lo + h + 0.15), _sz(k, 0.08, 0.22, 0.004), style=no_bottom("trim", 1.0))
        b.group = None
        b.box(_pos(c, k, ma - 0.55, 0, lo + h + 0.1), _sz(k, 0.14, 0.2, 0.14), style=no_bottom("red", 1.0))      # kettle
    for i in range(n):                                                                    # wall cupboards
        a = -L / 2 + L * (i + 0.5) / n
        b.box(_pos(c, k, a, -f * (D / 2 - 0.18), lo + 1.85), _sz(k, L / n - 0.02, 0.6, 0.34), style=lambda n_, m, q: ("bone", uv_world(1.0)))
        b.box(_pos(c, k, a + L / n * 0.3, -f * (D / 2 - 0.36), lo + 1.62), _sz(k, 0.1, 0.02, 0.02), style=no_bottom("trim", 1.0))


def prop_kitchenette(ctx, c, s):
    kitchenette(ctx, c, s)


def prop_sink_counter(ctx, c, s):
    """Art room sink: a kitchen run without the microwave, paint pots by the tap."""
    kitchenette(ctx, c, s, microwave=False)
    k, f = _front(c, s)
    L = s[0] if k == 2 else s[2]
    for i, col in enumerate(("red", "yellow", "blue", "green")):
        ctx.b.box(_pos(c, k, L / 2 - 0.2 - i * 0.14, 0, s[1] / 2 + 0.06), _sz(k, 0.1, 0.12, 0.1), style=no_bottom(col, 1.0))


def prop_home_fridge(ctx, c, s):
    """Tall fridge: two doors with handles."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    b.box(c, s, style=no_bottom("bone", 1.0))
    lo = -s[1] / 2
    b.box(_pos(c, k, 0, f * (D / 2 + 0.005), lo + s[1] * 0.68), _sz(k, L - 0.04, 0.012, 0.01), style=no_bottom("trim_dark", 1.0))
    for y in (lo + s[1] * 0.85, lo + s[1] * 0.45):
        b.box(_pos(c, k, L / 2 - 0.08, f * (D / 2 + 0.03), y), _sz(k, 0.03, 0.3, 0.04), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, -L / 4, f * (D / 2 + 0.003), lo + s[1] * 0.8), _sz(k, 0.12, 0.16, 0.004), style=no_bottom("yellow", 1.0))  # a note


def prop_vending(ctx, c, s):
    """Snack vending machine: red cabinet, a glass window onto rows of snacks, a keypad and coin slot panel, the
    pick-up flap at the bottom."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    lo = -s[1] / 2
    b.box(c, s, style=lambda n_, m, q: None if n_[1] < -0.7 else (("black", uv_world(1.0)) if
          (n_[2 - (0 if k == 2 else 2)] * f > 0.7) else ("red", uv_world(1.0))))
    win_w = L * 0.68
    wa = -L / 2 + 0.06 + win_w / 2
    rng = random.Random(f"vend{c}")
    for r in range(5):                                                                      # snack rows
        y = lo + 0.55 + r * 0.26
        b.box(_pos(c, k, wa, f * (D / 2 - 0.22), y), _sz(k, win_w, 0.02, 0.36), style=no_bottom("trim", 1.0))
        a = wa - win_w / 2 + 0.06
        while a < wa + win_w / 2 - 0.1:
            if rng.random() < 0.7:
                maker = rng.choice((stock_bag, stock_box, stock_can, stock_bottle))
                col = rng.choice(("red", "yellow", "blue", "green", "bone", "olive"))
                _place(maker, b, _pos(c, k, a + 0.06, f * (D / 2 - 0.12), y + 0.01), "x" if k == 2 else "z", rng, col)
            a += 0.15
    b.box(_pos(c, k, wa, f * (D / 2 + 0.002), lo + 1.05), _sz(k, win_w, 1.35, 0.004), style=lambda n_, m, q: ("glass", uv_world(1.0)))
    pa = L / 2 - (L - win_w - 0.12) / 2 - 0.04                                               # side panel
    b.box(_pos(c, k, pa, f * (D / 2 + 0.01), lo + 1.3), _sz(k, 0.16, 0.24, 0.02), style=no_bottom("trim_dark", 1.0))
    for i in range(3):
        for j in range(3):
            b.box(_pos(c, k, pa - 0.05 + i * 0.05, f * (D / 2 + 0.022), lo + 1.36 - j * 0.06), _sz(k, 0.035, 0.035, 0.006),
                  style=no_bottom("bone", 1.0))
    b.box(_pos(c, k, pa, f * (D / 2 + 0.01), lo + 1.05), _sz(k, 0.1, 0.12, 0.02), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, wa, f * (D / 2 + 0.01), lo + 0.22), _sz(k, win_w, 0.2, 0.02), style=no_bottom("black", 1.0))


def prop_file_cabinet(ctx, c, s):
    """Steel filing cabinet: four drawers with handles and label slots (one pulled out)."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    lo = -s[1] / 2
    b.box(c, s, style=no_bottom("steel_light", 1.0))
    n = 4
    rng = random.Random(f"file{c}")
    open_one = rng.randrange(n)
    for i in range(n):
        y = lo + s[1] * (i + 0.5) / n
        out = 0.2 if i == open_one else 0.0
        b.box(_pos(c, k, 0, f * (D / 2 + 0.006 + out / 2), y), _sz(k, L - 0.04, s[1] / n - 0.03, 0.012 + out), style=no_bottom("steel_light", 1.0))
        b.box(_pos(c, k, 0, f * (D / 2 + 0.02 + out), y), _sz(k, 0.14, 0.025, 0.02), style=no_bottom("trim_dark", 1.0))
        b.box(_pos(c, k, 0, f * (D / 2 + 0.014 + out), y + 0.07), _sz(k, 0.1, 0.04, 0.004), style=no_bottom("bone", 1.0))
        if out:
            for j in range(4):
                b.box(_pos(c, k, 0, f * (D / 2 + out - 0.04 - j * 0.04), y + 0.05), _sz(k, L - 0.12, 0.2, 0.01),
                      style=no_bottom(("olive", "bone", "yellow", "olive")[j], 1.0))


def prop_wall_books(ctx, c, s):
    """Bookcase against a wall: one-sided shelving full of books."""
    k, f = _front(c, s)
    shelving(ctx, c, s, "x" if k == 2 else "z", (f,), "books", levels=5, frame="wood", lip="wood", fill=0.75)


def prop_med_cabinet(ctx, c, s):
    k, f = _front(c, s)
    shelving(ctx, c, s, "x" if k == 2 else "z", (f,), "meds", levels=5, frame="bone", lip="red", fill=0.5)


def prop_art_shelf(ctx, c, s):
    k, f = _front(c, s)
    shelving(ctx, c, s, "x" if k == 2 else "z", (f,), "art", levels=4, frame="wood", lip="wood", fill=0.7)


def prop_plant(ctx, c, s):
    """A potted plant (dried out: olive and a few green leaves)."""
    b = ctx.b
    lo = c[1] - s[1] / 2
    b.box((c[0], lo + 0.18, c[2]), (0.34, 0.36, 0.34), style=no_bottom("red", 1.0))
    b.box((c[0], lo + 0.34, c[2]), (0.3, 0.02, 0.3), style=no_bottom("trim_dark", 1.0))
    b.box((c[0], lo + 0.7, c[2]), (0.04, 0.7, 0.04), style=no_bottom("olive_dark", 1.0))
    rng = random.Random(f"plant{c}")
    for i in range(7):
        y = lo + 0.6 + i * 0.12
        yaw = rng.uniform(0, 360)
        lx, lz = _at(c[0], c[2], yaw, 0, 0.16)
        b.box((lx, y, lz), (0.12, 0.02, 0.32), yaw=yaw, pitch=rng.uniform(-30, -10),
              style=no_bottom(rng.choice(("green", "olive", "olive")), 1.0))


def prop_rug(ctx, c, s):
    b = ctx.b
    b.box((c[0], c[1] - s[1] / 2 + 0.006, c[2]), (s[0], 0.012, s[2]), style=no_bottom("bone", 1.0))
    b.box((c[0], c[1] - s[1] / 2 + 0.008, c[2]), (s[0] - 0.2, 0.012, s[2] - 0.2), style=no_bottom("red", 1.0))


def prop_coffee_table(ctx, c, s):
    top = prop_table(ctx, c, s, "wood", "trim_dark")
    for i, col in enumerate(("red", "blue")):
        ctx.b.box((c[0] - 0.2 + i * 0.3, top + 0.005 + i * 0.01, c[2]), (0.22, 0.01, 0.3), yaw=i * 20 - 10,
                  style=no_bottom(col, 1.0))
    ctx.b.box((c[0] + 0.3, top + 0.05, c[2] + 0.1), (0.08, 0.1, 0.08), style=no_bottom("bone", 1.0))   # mug


def prop_lounge_table(ctx, c, s):
    """A square table with four chairs round it, mugs and papers."""
    b = ctx.b
    top = prop_table(ctx, c, s, "bone", "trim")
    y0 = c[1] - s[1] / 2
    for dx, dz in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        x, z = c[0] + dx * (s[0] / 2 + 0.25), c[2] + dz * (s[2] / 2 + 0.25)
        chair(b, x, y0, z, facing_yaw(-dx, -dz), "red", "trim")
    for i in range(2):
        b.box((c[0] - 0.2 + i * 0.4, top + 0.05, c[2] + 0.15 - i * 0.3), (0.08, 0.1, 0.08), style=no_bottom(("bone", "red")[i], 1.0))
    b.box((c[0] + 0.05, top + 0.003, c[2]), (0.21, 0.005, 0.3), yaw=17, style=no_bottom("bone", 1.0))


def prop_reading_table(ctx, c, s):
    """Library table: chairs along both long sides, a few open books."""
    b = ctx.b
    top = prop_table(ctx, c, s, "wood", "trim_dark")
    y0 = c[1] - s[1] / 2
    along_x = s[0] >= s[2]
    L = s[0] if along_x else s[2]
    n = max(1, int(L // 0.9))
    for side in (-1, 1):
        for i in range(n):
            a = -L / 2 + L * (i + 0.5) / n
            if along_x:
                chair(b, c[0] + a, y0, c[2] + side * (s[2] / 2 + 0.25), facing_yaw(0, -side), "blue", "trim")
            else:
                chair(b, c[0] + side * (s[0] / 2 + 0.25), y0, c[2] + a, facing_yaw(-side, 0), "blue", "trim")
    for i, col in enumerate(("red", "green")):
        b.box((c[0] + (i - 0.5) * 0.6, top + 0.015, c[2] + (i - 0.5) * 0.1), (0.3, 0.03, 0.22), yaw=i * 25 - 10, style=no_bottom(col, 1.0))
        b.box((c[0] + (i - 0.5) * 0.6, top + 0.032, c[2] + (i - 0.5) * 0.1), (0.28, 0.004, 0.2), yaw=i * 25 - 10, style=no_bottom("bone", 1.0))


def prop_principal_desk(ctx, c, s):
    """The principal's desk: a big wooden desk with drawer pedestals, a PC, a lamp, a nameplate and papers; a leather
    swivel chair behind it (the wall side) and two visitor chairs in front."""
    b = ctx.b
    front = 1 if _front_into(c, 2) == "+z" else -1          # the visitors' side (into the room)
    sit = -front                                              # the principal sits on the wall side
    y0 = c[1] - s[1] / 2
    top = y0 + s[1]
    b.box((c[0], top - 0.025, c[2]), (s[0] + 0.06, 0.05, s[2] + 0.06), style=no_bottom("wood", 1.0))
    for sx in (-1, 1):                                                                       # pedestals
        px = c[0] + sx * (s[0] / 2 - 0.25)
        b.box((px, y0 + (s[1] - 0.05) / 2, c[2]), (0.48, s[1] - 0.05, s[2] - 0.04), style=no_bottom("wood", 1.0))
        for k in range(3):
            y = y0 + 0.14 + k * (s[1] - 0.2) / 3
            b.box((px, y + 0.08, c[2] + sit * (s[2] / 2 - 0.015)), (0.42, (s[1] - 0.2) / 3 - 0.03, 0.012), style=no_bottom("trim_dark", 1.0))
            b.box((px, y + 0.1, c[2] + sit * (s[2] / 2 - 0.005)), (0.12, 0.02, 0.02), style=no_bottom("yellow", 1.0))
    b.box((c[0], y0 + s[1] * 0.55, c[2] + front * (s[2] / 2 - 0.03)), (s[0] - 0.9, s[1] * 0.75, 0.04), style=no_bottom("wood", 1.0))
    pc(ctx, c[0] + s[0] * 0.18, top, c[2], sit)
    b.box((c[0] - s[0] * 0.38, top + 0.01, c[2] - sit * 0.1), (0.14, 0.02, 0.14), style=no_bottom("black", 1.0))   # lamp
    b.box((c[0] - s[0] * 0.38, top + 0.2, c[2] - sit * 0.1), (0.025, 0.36, 0.025), style=no_bottom("yellow", 1.0))
    b.box((c[0] - s[0] * 0.38, top + 0.4, c[2] - sit * 0.03), (0.2, 0.1, 0.2), style=no_bottom("green", 1.0))
    b.box((c[0] - s[0] * 0.12, top + 0.04, c[2] + front * (s[2] / 2 - 0.08)), (0.3, 0.07, 0.04), pitch=front * -20,
          style=no_bottom("yellow", 1.0))                                                    # nameplate
    for k in range(3):
        b.box((c[0] - s[0] * 0.15 + k * 0.06, top + 0.003 + k * 0.002, c[2] + sit * 0.05), (0.21, 0.004, 0.3), yaw=k * 11 - 8,
              style=no_bottom("bone", 1.0))
    chair(b, c[0] + s[0] * 0.05, y0, c[2] + sit * (s[2] / 2 + 0.4), facing_yaw(0, -sit), "black", "trim", office=True)
    for dx in (-0.55, 0.55):
        chair(b, c[0] + dx, y0, c[2] + front * (s[2] / 2 + 0.55), facing_yaw(0, -front), "red", "wood")


def prop_serving_counter(ctx, c, s):
    """Cafeteria serving line: a steel counter with food wells (some still with food), a glass sneeze guard on
    posts, the tray rail in front and a stack of trays at the end."""
    b = ctx.b
    k, f = _front(c, s)
    L, D = (s[0], s[2]) if k == 2 else (s[2], s[0])
    lo = -s[1] / 2
    h = s[1]
    b.box(_pos(c, k, 0, -f * 0.1, lo + (h - 0.04) / 2), _sz(k, L, h - 0.04, D - 0.2), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, 0, -f * 0.1, lo + h - 0.02), _sz(k, L + 0.02, 0.04, D - 0.18), style=lambda n_, m, q: ("steel_light", uv_world(1.0)))
    rng = random.Random(f"serve{c}")
    n = max(2, int((L - 0.6) // 0.5))
    for i in range(n):                                                                       # food wells
        a = -L / 2 + 0.3 + (L - 0.6) * (i + 0.5) / n
        b.box(_pos(c, k, a, -f * 0.1, lo + h - 0.015), _sz(k, 0.4, 0.004, 0.3), style=no_bottom("black", 1.0))
        if rng.random() < 0.5:
            b.box(_pos(c, k, a, -f * 0.1, lo + h - 0.005), _sz(k, 0.34, 0.01, 0.24),
                  style=no_bottom(rng.choice(("yellow", "olive", "bone", "red")), 1.0))
    for a in (-L / 2 + 0.1, L / 2 - 0.1, 0.0):                                               # sneeze guard
        b.box(_pos(c, k, a, f * 0.0, lo + h + 0.22), _sz(k, 0.03, 0.44, 0.03), style=no_bottom("trim", 1.0))
    b.box(_pos(c, k, 0, f * 0.05, lo + h + 0.42), _sz(k, L - 0.1, 0.01, 0.34), style=lambda n_, m, q: ("glass", uv_world(1.0)))
    b.box(_pos(c, k, 0, f * (D / 2 - 0.08), lo + h - 0.1), _sz(k, L, 0.03, 0.18), style=no_bottom("trim", 1.0))        # tray rail
    for j in range(3):
        b.box(_pos(c, k, 0, f * (D / 2 - 0.13), lo + 0.2 + j * 0.25), _sz(k, L - 0.1, 0.02, 0.02), style=no_bottom("trim", 1.0))
    for j in range(8):                                                                       # trays
        b.box(_pos(c, k, -L / 2 + 0.3, -f * 0.1, lo + h + 0.012 + j * 0.018), _sz(k, 0.36, 0.015, 0.28),
              style=no_bottom(("red", "olive")[j % 2], 1.0))


def prop_easel(ctx, c, s):
    """A painting easel: three legs, a ledge and a canvas with a few blobs of paint."""
    b = ctx.b
    lo = c[1] - s[1] / 2
    k, f = _front(c, s)
    yaw = 0 if k == 2 else 90
    for dx in (-0.25, 0.25):
        x, z = _at(c[0], c[2], yaw, dx, -0.05)
        b.box((x, lo + 0.8, z), (0.04, 1.6, 0.04), yaw=yaw, pitch=8, style=no_bottom("wood", 1.0))
    x, z = _at(c[0], c[2], yaw, 0, -0.35 * f)
    b.box((x, lo + 0.7, z), (0.04, 1.45, 0.04), yaw=yaw, pitch=-20 * f, style=no_bottom("wood", 1.0))
    x, z = _at(c[0], c[2], yaw, 0, 0.04)
    b.box((x, lo + 0.7, z), (0.6, 0.04, 0.08), yaw=yaw, style=no_bottom("wood", 1.0))
    b.box((x, lo + 1.05, z), (0.55, 0.65, 0.03), yaw=yaw, pitch=8, style=no_bottom("bone", 1.0))
    rng = random.Random(f"easel{c}")
    for i in range(4):
        dx, dy = rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2)
        px, pz = _at(c[0], c[2], yaw, dx, 0.04 + 0.02)
        b.box((px, lo + 1.05 + dy, pz), (0.1, 0.08, 0.01), yaw=yaw, pitch=8, style=no_bottom(rng.choice(("red", "blue", "yellow", "green")), 1.0))


SCHOOL_PROPS = {
    "chalkboard": prop_chalkboard, "teacher_desk": prop_teacher_desk, "school_desk": prop_school_desk,
    "lab_bench": prop_lab_bench, "bookshelf": prop_bookshelf, "caf_table": prop_caf_table,
    "hall_lockers": prop_hall_lockers, "trophy_case": prop_trophy_case, "hall_bench": prop_hall_bench,
    "cot": prop_cot, "art_table": prop_art_table, "computer_desk": prop_computer_desk, "sofa": prop_sofa,
    "kitchenette": prop_kitchenette, "sink_counter": prop_sink_counter, "home_fridge": prop_home_fridge,
    "vending": prop_vending, "file_cabinet": prop_file_cabinet, "wall_books": prop_wall_books,
    "med_cabinet": prop_med_cabinet, "art_shelf": prop_art_shelf, "plant": prop_plant, "rug": prop_rug,
    "coffee_table": prop_coffee_table, "lounge_table": prop_lounge_table, "reading_table": prop_reading_table,
    "principal_desk": prop_principal_desk, "serving_counter": prop_serving_counter, "easel": prop_easel,
}
for _kind, _fn in SCHOOL_PROPS.items():
    PROPS[_kind] = (lambda fn: lambda ctx, c, s, k: fn(ctx, c, s))(_fn)


def wall_quad(b, axis_n, at, a0, a1, y0, y1, mat, uv):
    """A flat picture on a wall: normal along +-x or +-z (axis_n like (0, 0, 1)), plane at `at`."""
    if axis_n[2]:
        pts = [(a0, y0, at), (a1, y0, at), (a1, y1, at), (a0, y1, at)]
    else:
        pts = [(at, y0, a0), (at, y0, a1), (at, y1, a1), (at, y1, a0)]
    b.poly(pts, axis_n, mat, uv)


def dress_school(ctx):
    b, rng = ctx.b, ctx.rng
    zs = 12.15                                                            # south wall's outside face
    # Entrance: the sign, a canopy on two posts, steps.
    b.box((0, 3.3, zs + 0.05), (6.0, 0.8, 0.1), style=face_decal(ctx.d("sign"), "olive_dark", "+z"))
    b.box((0, 2.7, zs + 1.2), (4.4, 0.15, 2.4), style=lambda n, m, q: ("trim_dark", uv_world()) if n[1] < 0.7 else ("roof", uv_world()))
    for x in (-2.0, 2.0):
        b.box((x, 1.31, zs + 2.2), (0.15, 2.62, 0.15), style=no_bottom("trim_dark", 1.0))
    # Concrete plinth, a band at the upper floor, a coping on the parapet.
    for y0, h, gap in ((0.0, 0.45, True), (2.85, 0.3, False)):
        for z in (-zs - 0.03, zs + 0.03):
            parts = ((-15.2, -1.1), (1.1, 15.2)) if gap and z > 0 else ((-15.2, 15.2),)
            for a0, a1 in parts:
                b.box(((a0 + a1) / 2, y0 + h / 2, z), (a1 - a0, h, 0.06), style=no_bottom("concrete", 4.0))
        for x in (-15.18, 15.18):
            b.box((x, y0 + h / 2, 0), (0.06, h, 24.36), style=no_bottom("concrete", 4.0))
    for z in (-12.0, 12.0):
        b.box((0, 7.04, z), (30.5, 0.08, 0.5), style=no_bottom("concrete", 4.0))
    for x in (-15.0, 15.0):
        b.box((x, 7.04, 0), (0.5, 0.08, 24.5), style=no_bottom("concrete", 4.0))
    # Spray paint on the west end, broken glass in some windows.
    wall_quad(b, (-1, 0, 0), -15.16, -6.0, -1.0, 0.8, 2.6, "graffiti", ctx.d("graffiti"))
    # Hall (room 1,1 both floors): notice boards; lobby: posters; cafeteria menu; nurse's sign; clocks.
    for y in (0.0, 3.0):
        wall_quad(b, (1, 0, 0), -4.89, -3.0, -1.4, y + 1.2, y + 2.2, "decals", ctx.d("notice"))
        wall_quad(b, (-1, 0, 0), 4.89, 1.4, 3.0, y + 1.2, y + 2.2, "decals", ctx.d("notice"))
    wall_quad(b, (0, 0, -1), 11.85, 4.0, 4.6, 1.3, 2.1, "decals", ctx.d("poster_read"))
    wall_quad(b, (0, 0, 1), 4.11, 2.4, 3.0, 1.3, 2.1, "decals", ctx.d("poster_run"))
    wall_quad(b, (0, 0, 1), -3.89, -14.0, -12.0, 1.3, 2.2, "decals", ctx.d("menu"))
    wall_quad(b, (1, 0, 0), -14.84, 5.0, 5.6, 1.4, 2.0, "decals", ctx.d("nurse"))
    for x0 in (-5.0, 5.0):
        for y in (0.0, 3.0):
            wall_quad(b, (0, 0, 1), -11.84, x0 + 6.6, x0 + 7.0, y + 2.3, y + 2.7, "decals", ctx.d("clock"))
    # Entrance (owner: "make a proper entrance"): a welcome banner over the doors, mats, plants either side.
    wall_quad(b, (0, 0, -1), 11.84, -1.6, 1.6, 2.45, 2.95, "decals", ctx.d("welcome"))
    b.box((0, 0.012, 10.9), (2.4, 0.02, 1.4), style=no_bottom("trim_dark", 1.0))
    # War mess (owner: the school looked too neat): fallen ceiling tiles, books knocked off the library shelves,
    # papers everywhere.
    for _ in range(16):
        x, z = rng.uniform(-14.5, 14.5), rng.uniform(-11.5, 11.5)
        y = rng.choice((0.0, 3.0)) + 0.03
        b.box((x, y, z), (0.6, 0.03, 0.6), yaw=rng.uniform(0, 90), pitch=rng.uniform(-12, 12),
              style=no_bottom("ceiling", 1.0))
    for _ in range(12):
        x, z = rng.uniform(-14.0, -6.0), rng.uniform(-6.5, -4.4)
        b.box((x, 0.02, z), (0.17, 0.04, 0.24), yaw=rng.uniform(0, 180),
              style=no_bottom(rng.choice(("red", "blue", "green", "olive", "bone")), 1.0))
    for _ in range(70):
        x, z = rng.uniform(-14.5, 14.5), rng.uniform(-11.5, 11.5)
        y = rng.choice((0.0, 3.0)) + 0.015
        b.box((x, y, z), (0.21, 0.005, 0.3), yaw=rng.uniform(0, 180), style=no_bottom("bone", 1.0))
    for x, z, y in ((-1.5, -4.5, 0.0), (8.0, 1.5, 3.0)):
        b.box((x, y + 0.2, z), (0.4, 0.04, 0.38), pitch=85, yaw=rng.uniform(0, 90), style=no_bottom("blue", 1.0))


DECALS["school"] = school_decals
DRESSING["school"] = dress_school
FOOTPRINTS["school"] = (-15.0, -12.0, 15.0, 12.0)
SHELLS["school"] = {
    "ext": "brick_tan", "roof_side": "brick_tan", "x_splits": (-5.0, 5.0), "z_splits": (-4.0, 4.0),
    "x_lines": (-15.0, -5.0, 5.0, 15.0), "z_lines": (-12.0, -4.0, 4.0, 12.0),
    "inner": school_inner, "floor": school_floor,
}


# ------------------------------------------------------------------------------------------------ pharmacy (0.17)
# The pharmacy (map 90-105 x 72-84, model origin map (97.5, 78)): shop floor east (door south), dispensary west
# (its north wall blown out). Local x < 0 is the dispensary.
def paint_int_clinic(rng):
    """Clean white walls with a mint stripe at 1 m (grubby now)."""
    c = Canvas(64, 64, "bone")
    c.rect(0, 15, 64, 18, "extract_green")
    c.rect(0, 0, 64, 2, "steel")
    c.blotch(["concrete"], 8, rng, area=(0, 18, 64, 64), size=(2, 5))
    return c


def paint_floor_pharm(rng):
    """Big white tiles (1 m), the odd mint one, scuffed."""
    c = Canvas(64, 64, "bone")
    for ty in range(4):
        for tx in range(4):
            if rng.random() < 0.15:
                c.rect(tx * 16 + 1, ty * 16 + 1, tx * 16 + 16, ty * 16 + 16, "olive_light")
    for i in range(0, 64, 16):
        c.rect(i, 0, i + 1, 64, "steel_light")
        c.rect(0, i, 64, i + 1, "steel_light")
    c.blotch(["concrete", "sand"], 6, rng, size=(2, 5))
    return c


KIT.update({"int_clinic": paint_int_clinic, "floor_pharm": paint_floor_pharm, "mint": paint_flat("extract_green")})


def pharmacy_decals(rng):
    a = Atlas(512)

    def sign(c):          # 6 x 0.8 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "green_dark")
        c.rect(4, 4, 22, 22, "green_dark")
        c.rect(11, 6, 15, 20, "bone")
        c.rect(6, 11, 20, 15, "bone")
        w = Canvas.text_width("PHARMACY", 3)
        c.ctext(28, c.w, 5, "PHARMACY", "green_dark", 3)
        c.blotch(["concrete"], 4, rng, area=(2, 2, c.w - 2, c.h - 2), size=(2, 4))

    def cross(c):         # 1 x 1 m lightbox
        c.rect(0, 0, c.w, c.h, "iron_dark")
        c.rect(2, 2, c.w - 2, c.h - 2, "bone")
        c.rect(c.w // 2 - 4, 5, c.w // 2 + 4, c.h - 5, "extract_green")
        c.rect(5, c.h // 2 - 4, c.w - 5, c.h // 2 + 4, "extract_green")
        c.rect(c.w // 2 - 4, 5, c.w // 2 + 4, 8, "green_dark")

    def meds(c):          # 1.2 x 1.6 m of shelf, part looted
        c.rect(0, 0, c.w, c.h, "steel_light")
        for row in range(4):
            y = 2 + row * 12
            c.rect(0, y - 2, c.w, y, "steel")
            x = 1
            while x < c.w - 3:
                w = rng.choice((3, 4, 5))
                if rng.random() < 0.6:
                    col = rng.choice(("bone", "red", "sky_blue", "extract_green", "hazard_yellow", "bone"))
                    h = rng.randrange(4, 9)
                    c.rect(x, y, x + w, y + h, col)
                    if h > 5:
                        c.rect(x, y + h - 2, x + w, y + h - 1, "bone" if col != "bone" else "sky_blue")
                x += w + 1

    def drawers(c):       # 0.775 x 2 m: a column of little labelled drawers
        c.rect(0, 0, c.w, c.h, "wood_light")
        for y in range(2, c.h - 2, 7):
            c.frame(1, y, c.w - 1, y + 6, "wood_mid")
            c.rect(c.w // 2 - 3, y + 3, c.w // 2 + 3, y + 5, "bone")
            if rng.random() < 0.25:                               # pulled out, empty
                c.rect(2, y + 1, c.w - 2, y + 5, "black")

    def counter(c):       # 2.4 x 1 m till counter front
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, 0, c.w, 3, "steel")
        c.rect(0, c.h - 10, c.w, c.h - 4, "extract_green")
        w = Canvas.text_width("PAY HERE")
        c.ctext(0, c.w, c.h - 9, "PAY HERE", "bone")
        c.blotch(["concrete"], 4, rng, size=(2, 4))

    def rx(c):            # 2.5 x 0.4 m hanging sign
        c.rect(0, 0, c.w, c.h, "green_dark")
        w = Canvas.text_width("PRESCRIPTIONS")
        c.ctext(0, c.w, 4, "PRESCRIPTIONS", "bone")

    def glasses(c):       # 0.6 x 1.6 m sunglasses stand side
        c.rect(0, 0, c.w, c.h, "steel_light")
        for y in range(6, c.h - 4, 7):
            for x in (2, 10):
                if rng.random() < 0.6:
                    col = rng.choice(("black", "red", "sky_blue", "iron_dark"))
                    c.rect(x, y, x + 3, y + 2, col)
                    c.rect(x + 4, y, x + 7, y + 2, col)
                    c.put(x + 3, y + 1, col)
        c.rect(0, c.h - 4, c.w, c.h, "extract_green")

    def poster(lines, colour, ink):
        def paint(c):     # 0.6 x 0.8 m
            c.rect(0, 0, c.w, c.h, colour)
            c.frame(0, 0, c.w, c.h, ink)
            for k, t in enumerate(lines):
                w = Canvas.text_width(t)
                c.ctext(0, c.w, c.h - 9 - k * 7, t, ink)
        return paint

    def looted(c):        # graffiti
        c.rect(0, 0, c.w, c.h, "clear")
        w = Canvas.text_width("NO MEDS", 3)
        c.ctext(0, c.w, 3, "NO MEDS", "red", 3)
        for _ in range(5):
            x = rng.randrange(3, c.w - 3)
            c.rect(x, 0, x + 1, rng.randrange(2, 4), "red")

    a.add("sign", 192, 26, sign)
    a.add("cross", 32, 32, cross)
    a.add("meds", 38, 51, meds)
    a.add("drawers", 25, 64, drawers)
    a.add("counter", 77, 32, counter)
    a.add("rx", 80, 13, rx)
    a.add("glasses", 19, 51, glasses)
    a.add("poster_flu", 19, 26, poster(("FLU", "SHOTS"), "sky_blue", "bone"))
    a.add("poster_vit", 19, 26, poster(("VITA", "MINS"), "hazard_yellow", "red"))
    a.add("looted", 96, 22, looted)
    return a


def prop_gondola(ctx, c, s):
    """Pharmacy aisle along z: medicine on both sides."""
    shelving(ctx, c, s, "z", (1, -1), "meds", levels=5, frame="steel_light", lip="mint", fill=0.5)


def prop_rx_shelf(ctx, c, s):
    """Dispensary shelf along x, both sides."""
    shelving(ctx, c, s, "x", (1, -1), "meds", levels=4, frame="wood", lip="wood", fill=0.45)


def prop_pharm_wall(ctx, c, s):
    side = 1 if _front_into(c, 2) == "+z" else -1
    shelving(ctx, c, s, "x", (side,), "meds", levels=5, frame="steel_light", lip="green", fill=0.5)


def prop_pharm_counter(ctx, c, s):
    b = ctx.b
    b.box(c, s, style=face_decal(ctx.d("counter"), "bone", "-x"))
    top = c[1] + s[1] / 2
    b.box((c[0], top + 0.02, c[2]), (s[0] + 0.06, 0.04, s[2] + 0.06), style=no_bottom("steel_light", 1.0))
    b.box((c[0] + 0.1, top + 0.15, c[2] - 0.6), (0.38, 0.22, 0.4), style=no_bottom("trim_dark", 1.0))       # till
    for k in range(4):                                                                                 # bags
        b.box((c[0] + 0.2, top + 0.12, c[2] + 0.3 + k * 0.12), (0.25, 0.2, 0.02), style=no_bottom("bone", 1.0))


def prop_spinner(ctx, c, s):
    b = ctx.b
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2

    def style(n, m, q):
        if n[1] < -0.7:
            return None
        if abs(n[1]) > 0.7:
            return ("mint", uv_world())
        return ("decals", ctx.d("glasses"))
    b.box((c[0], c[1] + 0.05, c[2]), (s[0], s[1] - 0.1, s[2]), yaw=20, style=style)
    b.box((c[0], y0 + 0.05, c[2]), (0.5, 0.1, 0.5), style=no_bottom("trim_dark", 1.0))


def prop_rx_drawers(ctx, c, s):
    b = ctx.b
    front = _front_into(c, 2)
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b.box(c, s, style=lambda n, m, q: None if side_of(n) in (front, "-y") else ("wood", uv_world(2.0)))
    z = c[2] + (s[2] / 2 if front == "+z" else -s[2] / 2)
    strip_quads(ctx, c[0] - s[0] / 2, c[0] + s[0] / 2, y0, y1, z, (0, 0, 1 if front == "+z" else -1), "drawers", 0.775, "x")


def prop_rx_counter(ctx, c, s):
    b = ctx.b
    b.box(c, s, style=lambda n, m, q: None if n[1] < -0.7 else (("bone", uv_world()) if n[1] > 0.7 else ("wood", uv_world(2.0))))
    top = c[1] + s[1] / 2
    b.box((c[0] - 0.6, top + 0.15, c[2]), (0.4, 0.3, 0.35), style=no_bottom("bone", 1.0))              # label printer
    for k in range(5):                                                                                 # pill bottles
        b.box((c[0] + 0.3 + k * 0.12, top + 0.05, c[2] + ctx.rng.uniform(-0.1, 0.1)), (0.06, 0.1, 0.06),
              style=no_bottom(("yellow", "bone")[k % 2], 1.0))
    # The PRESCRIPTIONS sign hangs over it from the ceiling.
    for nz in (-1, 1):
        b.poly([(c[0] - 1.25, 2.3, c[2] + nz * 0.01), (c[0] + 1.25, 2.3, c[2] + nz * 0.01),
                (c[0] + 1.25, 2.7, c[2] + nz * 0.01), (c[0] - 1.25, 2.7, c[2] + nz * 0.01)], (0, 0, nz), "decals", ctx.d("rx"))
    for x in (c[0] - 1.1, c[0] + 1.1):
        b.box((x, 2.85, c[2]), (0.02, 0.3, 0.02), style=lambda n, m, q: ("black", uv_world()))


PHARM_PROPS = {
    "pharm_gondola": prop_gondola, "rx_shelf": prop_rx_shelf, "pharm_wall": prop_pharm_wall,
    "pharm_counter": prop_pharm_counter, "spinner": prop_spinner, "rx_drawers": prop_rx_drawers,
    "rx_counter": prop_rx_counter,
}
for _kind, _fn in PHARM_PROPS.items():
    PROPS[_kind] = (lambda fn: lambda ctx, c, s, k: fn(ctx, c, s))(_fn)


def dress_pharmacy(ctx):
    b, rng = ctx.b, ctx.rng
    zs = 6.15                                                            # south wall's outside face
    # Green band and sign over the front, a cross lightbox sticking out at the corner.
    b.box((0, 2.75, zs + 0.015), (15.3, 0.6, 0.03), style=no_bottom("green", 1.0))
    b.box((1.5, 2.75, zs + 0.06), (6.0, 0.8, 0.08), style=face_decal(ctx.d("sign"), "trim_dark", "+z"))
    b.box((7.9, 2.4, 5.4), (0.8, 0.05, 0.05), style=no_bottom("trim_dark", 1.0))                    # bracket
    b.box((8.2, 2.0, 5.4), (0.12, 0.9, 0.9), style=lambda n, m, q: ("decals", ctx.d("cross")) if abs(n[0]) > 0.7
          else ("trim_dark", uv_world()))
    b.box((0, 0.225, zs + 0.03), (15.3, 0.45, 0.06), style=no_bottom("concrete", 4.0))
    wall_quad(b, (-1, 0, 0), -7.66, -1.5, 1.5, 0.9, 1.6, "graffiti", ctx.d("looted"))
    # Inside: posters, pills and boxes all over the floor (it's been looted), a dropped basket.
    wall_quad(b, (0, 0, -1), 5.89, 1.0, 1.6, 1.2, 2.0, "decals", ctx.d("poster_flu"))
    wall_quad(b, (1, 0, 0), 0.11, -5.0, -4.4, 1.2, 2.0, "decals", ctx.d("poster_vit"))
    for _ in range(26):
        x, z = rng.uniform(-7.0, 7.0), rng.uniform(-5.5, 5.5)
        col = rng.choice(("bone", "red", "blue", "mint", "yellow", "cardboard"))
        b.box((x, 0.04, z), (0.12, 0.08, 0.08), yaw=rng.uniform(0, 90), style=no_bottom(col, 1.0))
    for _ in range(40):                                                  # spilled pills
        b.box((rng.uniform(-5.5, -1.0), 0.006, rng.uniform(-1.0, 0.0)), (0.02, 0.01, 0.02), style=no_bottom("bone", 1.0))
    b.box((2.6, 0.12, 2.0), (0.45, 0.24, 0.32), yaw=35, pitch=70, style=no_bottom("red", 1.0))


DECALS["pharmacy"] = pharmacy_decals
DRESSING["pharmacy"] = dress_pharmacy
FOOTPRINTS["pharmacy"] = (-7.5, -6.0, 7.5, 6.0)
SHELLS["pharmacy"] = {
    "ext": "render", "roof_side": "render", "x_lines": (-7.5, 0.0, 7.5), "z_lines": (-6.0, 6.0),
    "inner": lambda m: "int_clinic", "floor": lambda m: "floor_pharm",
}


# ------------------------------------------------------------------------------------------------ main
def clear_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    for obj in list(coll.objects):
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    return coll


# Kit atlas (performance, owner OK'd 2026-10-13): every tiling kit texture except glass in one 512 px image, an 8 x 8
# grid of 64 px cells, drawn by one shader material (assets/shaders/kit_atlas.gdshader). A cell's place is kept in
# art_source/textures/kit_atlas.json: new kit textures go on the end, so existing models keep their cells.
ATLAS_GRID, ATLAS_CELL = 8, 64
ATLAS_ORDER = os.path.join(ROOT, "art_source", "textures", "kit_atlas.json")
ATLAS_PNG = os.path.join(ROOT, "assets", "textures", "kit_atlas.png")
NOT_IN_ATLAS = ("glass",)        # see-through: its own material


def kit_atlas():
    """Writes the atlas image; returns {kit name: (u, v) of its cell's top-left corner}."""
    order = json.load(open(ATLAS_ORDER)) if os.path.exists(ATLAS_ORDER) else []
    for name in KIT:
        if name not in order and name not in NOT_IN_ATLAS:
            order.append(name)
    assert len(order) <= ATLAS_GRID * ATLAS_GRID, "kit atlas full: make the grid bigger"
    with open(ATLAS_ORDER, "w") as f:
        json.dump(order, f, indent=0)
    size = ATLAS_GRID * ATLAS_CELL
    top = [[[0, 0, 0, 255] for _ in range(size)] for _ in range(size)]          # rows top-first
    cells = {}
    for i, name in enumerate(order):
        path = os.path.join(TEX_DIR or os.path.join(ROOT, "art_source", "textures", "kit"), name + ".png")
        if not os.path.exists(path):
            continue
        w, h, rows = read_png(path)
        src = list(reversed(rows))
        cx, cy = i % ATLAS_GRID, i // ATLAS_GRID
        for y in range(ATLAS_CELL):
            line = src[y * h // ATLAS_CELL]
            out = top[cy * ATLAS_CELL + y]
            for x in range(ATLAS_CELL):
                out[cx * ATLAS_CELL + x] = list(line[x * w // ATLAS_CELL])
        cells[name] = (cx / ATLAS_GRID, cy / ATLAS_GRID)
    write_png(ATLAS_PNG, size, size, list(reversed(top)))
    return cells


def set_import_script(glb):
    """Points the model's .import at tools/building_import.gd (it swaps in the atlas shader material)."""
    path = glb + ".import"
    line = 'import_script/path="res://tools/building_import.gd"'
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write('[remap]\n\nimporter="scene"\n\n[params]\n\n' + line + "\n")
        return
    text = open(path).read()
    if line not in text:
        text = re.sub(r'import_script/path="[^"]*"', line, text)
        with open(path, "w") as f:
            f.write(text)


def write_glb(path, builder, textures, mat_info, atlas=None):
    """The model as a .glb: one mesh, one primitive per material, flat normals, nearest-filtered textures.
    atlas ({kit name: cell corner}): those materials become one "kit_atlas" material, the cell corner in TEXCOORD_1."""
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

    atlas = atlas or {}
    targets = []                                   # the glb's materials (the atlas ones merged into one)
    for mname in builder.mat_names:
        t = "kit_atlas" if mname in atlas else mname
        if t not in targets:
            targets.append(t)
    images, tex_index, materials = [], {}, []
    for mname in targets:
        if mname == "kit_atlas":                   # its texture comes from the shader material (import script)
            materials.append({"name": "kit_atlas", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                              "metallicFactor": 0.0, "roughnessFactor": 1.0}})
            continue
        tex_name, cutout, double = mat_info[mname]
        if tex_name not in tex_index:
            images.append({"bufferView": add_view(textures[tex_name].png), "mimeType": "image/png", "name": tex_name})
            tex_index[tex_name] = len(images) - 1
        m = {"name": mname, "pbrMetallicRoughness": {"baseColorTexture": {"index": tex_index[tex_name]},
                                                     "metallicFactor": 0.0, "roughnessFactor": 1.0}}
        if cutout:
            m["alphaMode"], m["alphaCutoff"] = "MASK", 0.5
        if double:
            m["doubleSided"] = True
        if mname == "glass":                       # see-through (owner: windows you can look through)
            m["alphaMode"] = "BLEND"
            m["pbrMetallicRoughness"]["baseColorFactor"] = [1.0, 1.0, 1.0, 0.28]
        materials.append(m)
    prims = []
    target_of = [targets.index("kit_atlas" if m in atlas else m) for m in builder.mat_names]
    for mi in range(len(targets)):
        pos, nrm, uv, uv2, col, idx = [], [], [], [], [], []
        colors = getattr(builder, "colors", None) or [None] * len(builder.faces)
        for face, uvs, m, n, cs in zip(builder.faces, builder.uvs, builder.mats, builder.normals, colors):
            if target_of[m] != mi:
                continue
            base = len(pos)
            cell = atlas.get(builder.mat_names[m], (0.0, 0.0))
            for k, (vi, t) in enumerate(zip(face, uvs)):
                pos.append(builder.verts[vi])
                nrm.append(n)
                uv.append((t[0], 1.0 - t[1]))          # glTF's v points down the image
                uv2.append(cell)
                col.append(tuple(cs[k]) if cs else (1.0, 1.0, 1.0))
            for k in range(1, len(face) - 1):
                idx += [base, base + k, base + k + 1]
        if not idx:
            continue
        prims.append({"attributes": {"POSITION": add_accessor(pos, 5126, "VEC3", 34962, True),
                                     "NORMAL": add_accessor(nrm, 5126, "VEC3", 34962),
                                     "TEXCOORD_0": add_accessor(uv, 5126, "VEC2", 34962),
                                     **({"TEXCOORD_1": add_accessor(uv2, 5126, "VEC2", 34962)}
                                        if targets[mi] == "kit_atlas" else {}),
                                     **({"COLOR_0": add_accessor(col, 5126, "VEC3", 34962)} if colors[0] else {})},
                      "indices": add_accessor(idx, 5125, "SCALAR", 34963), "material": mi})
    # Images use the alpha channel only where the material says so; gltf's alpha comes from the texture.
    gltf = {"asset": {"version": "2.0", "generator": "Bloxov make_building.py"}, "scene": 0,
            "scenes": [{"nodes": [0]}], "nodes": [{"name": BUILDING_NAME[0], "mesh": 0}],
            "meshes": [{"name": BUILDING_NAME[0], "primitives": prims}], "materials": materials,
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


BUILDING_NAME = [BUILDING]


def build(name, export):
    BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    rng = random.Random(name)
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"),
                                         painter, random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, kit == "glass")
    atlas = DECALS[name](rng)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, rng)
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)

    ctx = Ctx(data, atlas, FOOTPRINTS[name])
    counts = {}
    for row in data["boxes"]:
        kind = row.get("kind")
        if kind:
            k = counts.get(kind, 0)
            counts[kind] = k + 1
            PROPS[kind](ctx, tuple(row["pos"]), tuple(row["size"]), k)
        else:
            shell_box(ctx, row)
    DRESSING[name](ctx)
    dress_openings(ctx, data.get("openings", []))
    if BAKE_LIGHT:
        bake_light.bake(ctx.b, data["boxes"])
    print(f"{name}: {sum(len(f) - 2 for f in ctx.b.faces)} triangles, "
          f"{len({('kit_atlas' if m in KIT and m not in NOT_IN_ATLAS else m) for m in ctx.b.mat_names})} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    if bpy is None:
        if export:
            write_glb(out, ctx.b, textures, mat_info, atlas=kit_atlas())
            set_import_script(out)
            print("exported", out)
        return None
    materials = {m: blender_material(m, textures[t], cut, dbl) for m, (t, cut, dbl) in mat_info.items()}
    coll = clear_collection("Bloxov")
    obj = ctx.b.to_object(name, materials, coll)
    if export:
        for o in bpy.context.scene.objects:
            o.select_set(o == obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_animations=False)
        print("exported", out)
    return obj


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    name = args[0] if args and not args[0].startswith("-") else BUILDING
    if bpy is None:
        build(name, True)
        return
    if bpy.app.background:
        for o in list(bpy.data.objects):            # the default cube, camera and light
            bpy.data.objects.remove(o, do_unlink=True)
    build(name, EXPORT or bpy.app.background)


if __name__ == "__main__":
    main()
