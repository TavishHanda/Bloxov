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
import struct
import zlib

try:
    import bpy
except ImportError:      # plain Python: writes the .glb itself (same model, no Blender needed)
    bpy = None

BUILDING = "gas_station_town"
EXPORT = False
REGENERATE_TEXTURES = False

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
        for y in range(y0, y1):
            for x in range(x0, x1):
                if rng.random() < chance:
                    self.put(x, y, rng.choice(colours))

    def blotch(self, colours, count, rng, area=None, size=(2, 5)):
        """Irregular patches (dirt, stains, chipped paint): clusters read better than single-pixel noise."""
        x0, y0, x1, y1 = area or (0, 0, self.w, self.h)
        for _ in range(count):
            x, y, col = rng.randrange(x0, x1), rng.randrange(y0, y1), rng.choice(colours)
            for _ in range(rng.randrange(*size) ** 2 // 2 + 1):
                if x0 <= x < x1 and y0 <= y < y1:
                    self.put(x % self.w, y % self.h, col)
                x += rng.choice((-1, 0, 1))
                y += rng.choice((-1, 0, 1))

    def text(self, x, y, s, c, scale=1):
        """Pixel text (3 x 5 glyphs, 1 px apart) with its bottom-left at (x, y). Returns the width."""
        cx = x
        for ch in s.upper():
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
    c = Canvas(8, 8, "sky_blue")
    c.noise(0, 0, 8, 8, ["steel_light"], 0.2, rng)
    return c


KIT = {
    "ext_block": paint_ext_block, "int_wall": paint_int_wall, "floor_tile": paint_floor_tile,
    "ceiling": paint_ceiling, "roof": paint_roof, "concrete": paint_concrete, "metal": paint_metal,
    "wood": paint_wood, "canopy_ceiling": paint_canopy_ceiling, "post": paint_post, "cardboard": paint_cardboard,
    "glass": paint_glass, "trim": paint_flat("steel"), "trim_dark": paint_flat("iron_dark"),
    "red": paint_flat("red"), "bone": paint_flat("bone"), "black": paint_flat("black"),
}


# ------------------------------------------------------------------------------------------------ decal atlas
class Atlas:
    """Regions of one 256 x 256 decal image (32 px/m), packed in rows."""

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
    a = Atlas()

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
        c.text((c.w - w) // 2, 6, "GAS", "bone", 4)
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
        c.text((c.w - w) // 2, c.h - 19, "GAS", "bone", 3)
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
        c.text((c.w - w) // 2, 3, "MARKET 24H", "red", 2)
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
        c.text(33, 18, "LOTTO", "red")
        c.text(36, 10, "WIN!", "red")
        c.blotch(["wood_dark"], 4, rng, area=(0, 0, 28, c.h), size=(2, 4))

    def cigs(c):          # 2.7 m x 1 m
        c.rect(0, 0, c.w, c.h, "iron_dark")
        for y in range(2, c.h - 2, 6):
            for x in range(2, c.w - 2, 3):
                if rng.random() < 0.3:
                    c.rect(x, y, x + 2, y + 4, rng.choice(("bone", "red", "sky_blue", "olive_light")))

    def ice(c):           # 1.6 m x 1 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, c.h - 6, c.w, c.h, "sky_blue")
        w = Canvas.text_width("ICE", 4)
        c.text((c.w - w) // 2, 6, "ICE", "sky_blue", 4)
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
        c.text(2, 6, "CLOSED", "black")
        c.rect(2, 3, c.w - 2, 4, "steel")

    a.add("fascia", 64, 32, fascia)
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


class Texture:
    """A kit or decal image: painted (and saved) the first time, loaded from its PNG after that."""

    def __init__(self, name, path, painter, rng):
        self.name, self.path = name, os.path.join(ROOT, path)
        if os.path.exists(self.path) and not REGENERATE_TEXTURES:
            self.w, self.h, rows = read_png(self.path)
        else:
            canvas = painter(rng)
            self.w, self.h = canvas.w, canvas.h
            rows = [[[round(v * 255) for v in rgba(col)] for col in row] for row in canvas.px]
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


def wall_style(fp):
    """Building shell: outside faces painted block, inside faces plaster, openings' edges trim."""
    x0, z0, x1, z1 = fp

    def style(n, mid, corners):
        if abs(n[1]) > 0.7:
            if n[1] < 0 and mid[1] < 0.01:
                return None                                   # bottom on the floor
            if n[1] > 0 and mid[1] > 2.99:
                return None                                   # hidden under the roof slab's top
            return ("trim", uv_world(1.0))
        dist = min(mid[0] - x0, x1 - mid[0], mid[2] - z0, z1 - mid[2])
        if dist < -0.05:
            return ("ext_block", uv_world())
        if dist > 0.05:
            return ("int_wall", uv_world())
        return ("trim", uv_world(1.0))
    return style


def shell_box(ctx, row):
    c, s = row["pos"], row["size"]
    colour = row["colour"]
    b = ctx.b
    if colour == "slab":
        b.box(c, s, style=lambda n, m, k: ("floor_tile", uv_world()) if n[1] > 0.7 else None)
    elif colour == "roof":
        def style(n, m, k):
            if n[1] > 0.7:
                return ("roof", uv_world())
            if n[1] < -0.7:
                return ("ceiling", uv_world())
            return ("red", uv_world())
        b.box(c, s, style=style)
    else:
        b.box(c, s, row["yaw"], row["pitch"], style=wall_style(ctx.footprint))


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
    b.box((c[0] + s[0] / 2 - 0.5, top + 0.12, c[2] + 0.05), (0.42, 0.24, 0.36),
          style=lambda n, m, q: None if n[1] < -0.7 else ("trim_dark", uv_world()))         # till, drawer open
    b.box((c[0] + s[0] / 2 - 0.5, top + 0.03, c[2] - 0.28), (0.36, 0.06, 0.25),
          style=lambda n, m, q: ("black", uv_world()))


def prop_cigs(ctx, c, s):
    ctx.b.box(c, s, style=face_decal(ctx.d("cigs"), "trim_dark", "-z"))


def prop_shelf(ctx, c, s):
    b = ctx.b
    base_y = c[1] - s[1] / 2

    def style(n, m, q):
        side = side_of(n)
        if side in ("+z", "-z"):
            return ("decals", ctx.d("products"))
        if side == "-y":
            return None
        return ("metal", uv_world(2.0))
    b.box((c[0], base_y + (s[1] - 0.1) / 2 + 0.1, c[2]), (s[0], s[1] - 0.1, s[2] - 0.1), style=style)
    b.box((c[0], base_y + 0.05, c[2]), (s[0], 0.1, s[2]), style=lambda n, m, q: None if n[1] < -0.7 else ("trim_dark", uv_world()))


def prop_fridge(ctx, c, s):
    ctx.b.box(c, s, style=face_decal(ctx.d("fridge"), "bone", "+z"))


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


def prop_desk(ctx, c, s):
    b = ctx.b
    base_y = c[1] - s[1] / 2
    b.box((c[0], base_y + s[1] - 0.025, c[2]), (s[0], 0.05, s[2]), style=lambda n, m, q: ("wood", uv_world(2.0)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((c[0] + sx * (s[0] / 2 - 0.05), base_y + (s[1] - 0.05) / 2, c[2] + sz * (s[2] / 2 - 0.05)),
                  (0.05, s[1] - 0.05, 0.05), style=lambda n, m, q: ("trim_dark", uv_world()))
    b.box((c[0] + 0.3, base_y + s[1] / 2 - 0.05, c[2]), (0.4, s[1] - 0.2, s[2] - 0.1),
          style=lambda n, m, q: None if n[1] < -0.7 else ("wood", uv_world(1.0)))           # drawers
    b.box((c[0] - 0.2, base_y + s[1] + 0.18, c[2] + 0.1), (0.38, 0.32, 0.34), yaw=-12,
          style=lambda n, m, q: None if n[1] < -0.7 else ("bone", uv_world()))              # old monitor
    b.box((c[0] - 0.2, base_y + s[1] + 0.18, c[2] - 0.075), (0.3, 0.24, 0.02), yaw=-12,
          style=lambda n, m, q: ("black", uv_world()))


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


PROPS = {
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


def dress_gas_station(ctx):
    b, rng = ctx.b, ctx.rng
    # Windows: shards of glass in the frames. (Positions from the gray box: 0.17's Building windows.)
    for x in (-3.25, 3.25):
        for z in (-5.0, 5.0):
            shards(ctx, x - 0.7, x + 0.7, 1.0, 2.2, z, "x", rng)
    shards(ctx, -0.7, 0.7, 1.0, 2.2, 6.5, "z", rng)
    # Store sign over the door (west wall) and the CLOSED notice beside it.
    b.box((-6.72, 2.58, 0.0), (0.08, 0.3, 3.0), style=face_decal(ctx.d("market"), "red", "-x"))
    b.poly([(-6.66, 1.3, -1.3), (-6.66, 1.3, -1.9), (-6.66, 1.7, -1.9), (-6.66, 1.7, -1.3)], (-1, 0, 0), "decals",
           ctx.d("closed"))
    # NO FUEL sprayed on the north wall (faces Main Street).
    b.poly([(-1.5, 1.2, -5.16), (1.5, 1.2, -5.16), (1.5, 2.2, -5.16), (-1.5, 2.2, -5.16)], (0, 0, -1), "graffiti",
           ctx.d("graffiti"))
    # The shop door, kicked off its hinges, lying outside.
    b.box((-8.0, 0.08, 0.6), (1.0, 0.05, 2.1), yaw=14, style=lambda n, m, q: None if n[1] < -0.7 else ("trim", uv_world(1.0)))
    b.box((-8.0, 0.106, 0.6), (0.8, 0.005, 1.8), yaw=14, style=lambda n, m, q: ("glass", uv_world(1.0)) if n[1] > 0.7 else None)
    # Litter on the shop floor.
    for _ in range(14):
        x, z = rng.uniform(-6.2, -0.3), rng.uniform(-1.4, 2.6)
        w = rng.uniform(0.1, 0.3)
        col = rng.choice(("bone", "red", "cardboard", "bone"))
        b.box((x, 0.035, z), (w, 0.01, w * rng.uniform(0.6, 1.4)), yaw=rng.uniform(0, 90),
              style=lambda n, m, q, col=col: (col, uv_world(1.0)) if n[1] > 0.7 else None)


DRESSING = {"gas_station_town": dress_gas_station}
FOOTPRINTS = {"gas_station_town": (-6.5, -5.0, 6.5, 5.0)}   # the shop's walls (x0, z0, x1, z1): outside vs inside faces


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


def write_glb(path, builder, textures, mat_info):
    """The model as a .glb: one mesh, one primitive per material, flat normals, nearest-filtered textures."""
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

    images, tex_index, materials = [], {}, []
    for mname in builder.mat_names:
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
        materials.append(m)
    prims = []
    for mi in range(len(builder.mat_names)):
        pos, nrm, uv, idx = [], [], [], []
        for face, uvs, m, n in zip(builder.faces, builder.uvs, builder.mats, builder.normals):
            if m != mi:
                continue
            base = len(pos)
            for vi, t in zip(face, uvs):
                pos.append(builder.verts[vi])
                nrm.append(n)
                uv.append((t[0], 1.0 - t[1]))          # glTF's v points down the image
            for k in range(1, len(face) - 1):
                idx += [base, base + k, base + k + 1]
        if not idx:
            continue
        prims.append({"attributes": {"POSITION": add_accessor(pos, 5126, "VEC3", 34962, True),
                                     "NORMAL": add_accessor(nrm, 5126, "VEC3", 34962),
                                     "TEXCOORD_0": add_accessor(uv, 5126, "VEC2", 34962)},
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
    print(f"{name}: {sum(len(f) - 2 for f in ctx.b.faces)} triangles, {len(ctx.b.mat_names)} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    if bpy is None:
        if export:
            write_glb(out, ctx.b, textures, mat_info)
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
