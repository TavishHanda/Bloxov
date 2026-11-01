"""The walkable hideout (0.21): the PMCs' base between raids, a place they dug out and patched up with whatever they
scavenged (owner 2026-10-25: an open hub "like Deadlock", not a hallway with rooms; "a group of PMCs going to
scavenge for stuff during war", not a futuristic bunker; no wood; not a box: "more military", arched roofs).
Shapes in project files hideout/shapes.png; two are built to compare (--shape=cave or --shape=post):
  cave: a natural cave with bunker pieces built in. The traders' stalls in a row on a raised rock ledge down the west
        side, the stash, wardrobe and workbench in concrete bunkers dug into the east side, the mess and the bunks in
        the southern pockets, the range down an old mine shaft to the north.
  post: a Cold War command post. A round domed hall (the war table in the middle) with a tunnel off each side: the
        trader market west, the armory east, the mess and bunks south, the range north.

Builds everything the hideout scene needs from one layout, with make_building.py's kit (same textures, same atlas):
  - art_source/buildings/hideout.json: the gray boxes (collision, and the light bake's occluders)
  - assets/models/buildings/hideout.glb: the model (no sky down here: the lamps are baked into the vertex colours)
  - scenes/hideout/hideout_level.tscn: the BoxMap that collides (its boxes aren't drawn, the model is)

    python3 art_source/scripts/make_hideout.py [--shape=cave|post]      (~20 s)

Space: metres, y up, -z north, the floor at y 0. You spawn by the war table in the middle, looking north.
"""
import json
import math
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_light                                  # noqa: E402
import make_building as mb                         # noqa: E402

NAME = "hideout"
SHAPE = "mix"
for _a in sys.argv[1:]:
    if _a.startswith("--shape="):
        SHAPE = _a.split("=", 1)[1]
FIRING_BACK = 1.5                                  # the firing line stands this far in front of the range's mouth
TARGETS = (10, 25, 50, 100)                        # metres from the firing line
TARGET_U = (-2.1, -0.7, 0.7, 2.1)                  # each one in its own lane, so none hides another
BOARD_W, BOARD_H, BOARD_Y = 3.0, 1.8, 1.65             # the quests and stats boards: width, height, middle
# The toys in the mess and bunks (0.21.7, owner asked for all four: radio, seats, darts, a lights-off switch).
DARTBOARD = (-4.44, 1.73, 19.1)                    # the board's face on the mess's left wall (faces +x)
DART_RINGS = (0.012, 0.028, 0.090, 0.106, 0.152, 0.170, 0.225)   # bull, outer bull, treble in/out, double in/out, edge
DART_LINE = -2.07                                  # the throw line (x): 2.37 m from the board, like a real oche
RADIO = (-2.6, 24.4)
SWITCH = (4.46, 1.3, 25.85)                        # the bunks' light switch, on the right wall
BUNK_TOP = 1.71                                    # the top bunk's mattress: what you stand on up there
CLIMB_BUNK = (3.4, 29.6)                           # the bunk with steps up to it (0.25.15)
DARK_GLOWS = []                                    # bulbs that stay lit with the lights off (the fairy lights)
BAND = 1.2                                         # the painted band along the bottom of the concrete walls


# ------------------------------------------------------------------------------------------------ textures
# 16 px per metre, 64 px = 4 m, like the map's kit.
mb.PALETTE.update({"bk_old": "807c72", "bk_old_dark": "6d6a61", "bk_old_light": "8c887d", "bk_old_stain": "5f5b52",
                   "bk_floor": "77756f", "bk_floor_dark": "5c5b58", "bk_floor_light": "84827b",
                   "bk_bag": "958763", "bk_bag_dark": "7c7052", "bk_bag_light": "a39572",
                   "bk_tarp": "566040", "bk_tarp_dark": "4a5337", "bk_paint_white": "d8d2c0",
                   "bk_rock": "6b665c", "bk_rock_dark": "57534b", "bk_rock_light": "7d776b"})


def paint_bk_old(rng):
    """Old cast concrete nobody has looked after: board marks, damp streaks down from above, stains."""
    c = mb.Canvas(64, 64, "bk_old")
    for row in range(16):
        c.rect(0, row * 4, 64, row * 4 + 4, rng.choice(["bk_old", "bk_old", "bk_old_dark", "bk_old_light"]))
        c.rect(0, row * 4, 64, row * 4 + 1, "bk_old_dark")
    for k in range(64):
        c.put(31, k, "bk_old_stain")
    for _ in range(12):                                                # damp running down
        x = rng.randrange(64)
        for y in range(rng.randrange(0, 40), rng.randrange(44, 64)):
            if rng.random() < 0.6:
                c.put(x, y, "bk_old_stain")
    c.blotch(["bk_old_stain", "bk_old_dark"], 12, rng, size=(2, 7))
    return c


def paint_bk_old_ceiling(rng):
    c = mb.Canvas(64, 64, "bk_old_dark")
    for y in range(64):
        for x in range(64):
            if x % 16 == 0 or y % 32 == 0:
                c.put(x, y, "bk_old_stain")
    c.blotch(["bk_old_stain", "charcoal"], 8, rng, size=(2, 6))       # soot from fires and lamps
    return c


def paint_bk_dirt(rng):
    """The floor: worn concrete, trodden dirt, oil."""
    c = mb.Canvas(64, 64, "bk_floor")
    c.blotch(["bk_floor_light", "bk_floor_dark"], 10, rng, size=(3, 7))
    for k in range(64):                                                # saw cuts every 2 m
        for p in (0, 32):
            c.put(k, p, "bk_floor_dark")
            c.put(p, k, "bk_floor_dark")
    c.blotch(["mound", "bk_floor_dark"], 8, rng, size=(3, 7))
    c.blotch(["charcoal"], 2, rng, size=(3, 6))
    return c


def paint_bk_grate(rng):
    """Steel floor grating (the catwalk and its stairs)."""
    c = mb.Canvas(64, 64, "iron_dark")
    for y in range(64):
        for x in range(64):
            if x % 2 == 0 or y % 4 == 0:
                c.put(x, y, "iron")
    c.blotch(["rust"], 4, rng, size=(1, 3))
    return c


def paint_bk_sandbag(rng):
    """Sandbags 0.5 x 0.15 m, laid in staggered courses."""
    c = mb.Canvas(64, 64, "bk_bag")
    for row in range(26):
        y0, y1 = row * 64 // 26, (row + 1) * 64 // 26
        off = 4 if row % 2 else 0
        for col in range(9):
            x0 = col * 8 - off
            c.rect(max(0, x0), y0, min(64, x0 + 8), y1, rng.choice(["bk_bag", "bk_bag", "bk_bag_light"]))
            c.rect(max(0, x0), y1 - 1, min(64, x0 + 8), y1, "bk_bag_dark")
            if 0 <= x0 < 64:
                c.rect(x0, y0, x0 + 1, y1, "bk_bag_dark")
    return c


def paint_bk_tarp(rng):
    c = mb.Canvas(64, 64, "bk_tarp")
    for x in range(0, 64, 6):
        for y in range(64):
            c.put(x, y, "bk_tarp_dark")
    c.blotch(["bk_tarp_dark", "olive"], 8, rng, size=(2, 6))
    return c


def paint_bk_rock(rng):
    """Rock: big fractured faces (each 1-1.5 m) parted by dark cracks, lit a little lighter along their top edges."""
    c = mb.Canvas(64, 64, "bk_rock")
    y = 0
    while y < 64:
        h = rng.randrange(10, 20)
        x = -rng.randrange(0, 12)
        while x < 64:
            w = rng.randrange(14, 26)
            tone = rng.choice(["bk_rock", "bk_rock", "bk_rock_mid", "bk_rock_light"])
            c.rect(max(0, x), y, min(64, x + w), min(64, y + h), tone)
            c.rect(max(0, x), y + 1, min(64, x + w), min(64, y + 2), "bk_rock_light")
            c.rect(max(0, x), y, min(64, x + w), min(64, y + 1), "bk_rock_crack")
            if 0 <= x < 64:
                for yy in range(y, min(64, y + h)):
                    c.put(min(63, max(0, x + (yy - y) // 6)), yy, "bk_rock_crack")
            x += w
        y += h
    c.noise(0, 0, 64, 64, ["bk_rock_dark", "bk_rock_mid"], 0.05, rng)
    return c


mb.PALETTE.update({"bk_rock": "6e685d", "bk_rock_mid": "67625a", "bk_rock_light": "777163", "bk_rock_dark": "5e5950",
                   "bk_rock_crack": "4a463f", "bk_band": "5a6447", "bk_band_dark": "4b5439", "bk_band_chip": "807c72"})


def paint_bk_band(rng):
    """Olive paint along the bottom of the concrete walls, chipped and scuffed, a dark line along its top."""
    c = mb.Canvas(64, 64, "bk_band")
    c.noise(0, 0, 64, 64, ["bk_band_dark"], 0.12, rng)
    c.blotch(["bk_band_chip", "bk_band_dark"], 10, rng, size=(1, 4))
    for x in range(64):
        for y in range(4):
            c.put(x, y, "charcoal_dark" if y < 2 else "bk_band_dark")
    return c


def paint_bk_hazard(rng):
    c = mb.Canvas(64, 64, "hazard_yellow")
    for y in range(64):
        for x in range(64):
            if ((x + y) // 8) % 2:
                c.put(x, y, "charcoal_dark")
    c.blotch(["bk_old"], 8, rng, size=(1, 4))                         # chipped
    return c


mb.KIT.update({"bk_old": paint_bk_old, "bk_old_ceiling": paint_bk_old_ceiling, "bk_dirt": paint_bk_dirt,
               "bk_grate": paint_bk_grate, "bk_sandbag": paint_bk_sandbag, "bk_tarp": paint_bk_tarp,
               "bk_rock": paint_bk_rock, "bk_hazard": paint_bk_hazard, "bk_band": paint_bk_band,
               "bk_iron": mb.paint_flat("iron"), "bk_tube": mb.paint_flat("steel"), "bk_cable": mb.paint_flat("charcoal_dark")})


mb.PALETTE.update({"bk_ground": "6f675a", "bk_ground_dark": "5b5449", "bk_ground_light": "7e7666"})


def paint_bk_ground(rng):
    """The cave floor: trodden earth and grit, flat stones, oil and boot-worn patches."""
    c = mb.Canvas(64, 64, "bk_ground")
    c.noise(0, 0, 64, 64, ["bk_ground_dark", "bk_ground_light"], 0.25, rng)
    for _ in range(14):
        x, y = rng.randrange(64), rng.randrange(64)
        w, h = rng.randrange(3, 8), rng.randrange(2, 6)
        c.rect(x, y, min(64, x + w), min(64, y + h), rng.choice(["bk_rock", "bk_rock_light", "bk_ground_light"]))
        c.rect(x, min(63, y + h - 1), min(64, x + w), min(64, y + h), "bk_rock_dark")
    c.blotch(["bk_ground_dark", "mound"], 10, rng, size=(3, 8))
    c.blotch(["charcoal"], 2, rng, size=(2, 5))
    return c


mb.KIT["bk_ground"] = paint_bk_ground


# The hangout's lounge (0.25.23, owner: "I like the colour but it looks so flat"): painted corrugated tin, worn
# chequered tiles, felt and vinyl, in place of flat colours.
mb.PALETTE.update({"hd_red": "b03a2e", "hd_red_hi": "c24a3c", "hd_red_lo": "8e2d24",
                   "hd_teal": "2f6a69", "hd_teal_hi": "3b7c7a", "hd_teal_lo": "245453",
                   "hd_yel": "d9a823", "hd_yel_hi": "e8b923", "hd_yel_lo": "b38a1c",
                   "hd_tile_w": "e2dccb", "hd_tile_w2": "d6cfbc", "hd_tile_k": "1f2023", "hd_tile_k2": "2a2b2f",
                   "hd_grout": "8d877a", "hd_grime": "6f6a5f", "hd_felt": "2f6b3a", "hd_felt_lo": "285c32",
                   "hd_felt_hi": "377a43", "hd_vinyl": "2f6a69", "hd_vinyl_lo": "245453", "hd_vinyl_hi": "3f807e"})


def paint_hd_tin(paint):
    """Corrugated tin painted one colour: ribs every 25 cm, a seam and rivets every metre, the paint chipped to bare
    steel, rust running down from the rivets, scuffs."""
    def f(rng):
        c = mb.Canvas(64, 64, paint)
        for x in range(64):
            tone = {0: paint + "_hi", 2: paint + "_lo"}.get(x % 4)
            if tone:
                for y in range(64):
                    c.put(x, y, tone)
        c.noise(0, 0, 64, 64, [paint + "_lo", paint + "_hi"], 0.06, rng)
        for x0 in range(0, 64, 16):                                    # the sheets' overlaps, with rivets
            for y in range(64):
                c.put(x0, y, "iron_dark")
            for y in range(3, 64, 10):
                c.put(x0 + 1, y, "steel_light")
                for k in range(rng.randrange(0, 7)):                   # rust running down
                    if y + 1 + k < 64 and rng.random() < 0.8:
                        c.put(x0 + 1, y + 1 + k, "rust")
        c.blotch(["steel", "iron"], 9, rng, size=(1, 3))               # chipped to bare metal
        c.blotch(["rust"], 3, rng, size=(1, 2))
        c.blotch([paint + "_lo"], 6, rng, size=(2, 5))                 # scuffs
        return c
    return f


def paint_hd_tiles(rng):
    """Black and white tiles, 50 cm, grouted; each a shade off, a few cracked or chipped, trodden grime."""
    c = mb.Canvas(64, 64, "hd_grout")
    for i in range(8):
        for j in range(8):
            white = (i + j) % 2 == 0
            col = rng.choice(["hd_tile_w", "hd_tile_w", "hd_tile_w2"] if white else ["hd_tile_k", "hd_tile_k", "hd_tile_k2"])
            c.rect(i * 8 + 1, j * 8 + 1, i * 8 + 8, j * 8 + 8, col)
            if rng.random() < 0.12:                                    # a crack across it
                y = j * 8 + rng.randrange(2, 7)
                for x in range(i * 8 + 1, i * 8 + 8):
                    c.put(x, min(j * 8 + 7, max(j * 8 + 1, y)), "hd_grout")
                    y += rng.choice((-1, 0, 0, 1))
            if rng.random() < 0.15:                                    # a chipped corner
                c.put(i * 8 + 1 + rng.choice((0, 6)), j * 8 + 1 + rng.choice((0, 6)), "hd_grime")
    c.noise(0, 0, 64, 64, ["hd_grime"], 0.03, rng)
    c.blotch(["hd_grime", "hd_grout"], 5, rng, size=(2, 6))
    return c


def paint_hd_felt(rng):
    c = mb.Canvas(64, 64, "hd_felt")
    c.noise(0, 0, 64, 64, ["hd_felt_lo", "hd_felt_hi"], 0.25, rng)
    c.blotch(["hd_felt_lo"], 3, rng, size=(3, 6))                      # worn patches
    return c


def paint_hd_vinyl(rng):
    """Tufted vinyl: a button every 25 cm, creases out from them, cracked here and there."""
    c = mb.Canvas(64, 64, "hd_vinyl")
    c.noise(0, 0, 64, 64, ["hd_vinyl_hi", "hd_vinyl_lo"], 0.12, rng)
    for y in range(2, 64, 16):
        for x in range(2 + (8 if (y // 16) % 2 else 0), 64, 16):
            c.put(x, y, "hd_vinyl_lo")
            for d in (1, 2):
                for dx, dy in ((d, d), (-d, d), (d, -d), (-d, -d)):
                    c.put((x + dx) % 64, (y + dy) % 64, "hd_vinyl_lo" if d == 1 else "hd_vinyl_hi")
    c.blotch(["bone"], 2, rng, size=(1, 2))
    return c


mb.PALETTE.update({"hd_ceil": "cfc6ad", "hd_ceil_hi": "e2dccb", "hd_ceil_lo": "a89f88", "hd_ceil_dk": "857d69"})


def paint_hd_ceiling(rng):
    """Pressed tin ceiling tiles, 50 cm, painted cream: a raised rim lit on one side, a boss in the middle, the paint
    yellowed and flaking here and there."""
    c = mb.Canvas(64, 64, "hd_ceil")
    for i in range(8):
        for j in range(8):
            x0, y0 = i * 8, j * 8
            c.rect(x0, y0, x0 + 8, y0 + 1, "hd_ceil_hi")
            c.rect(x0, y0, x0 + 1, y0 + 8, "hd_ceil_hi")
            c.rect(x0, y0 + 7, x0 + 8, y0 + 8, "hd_ceil_dk")
            c.rect(x0 + 7, y0, x0 + 8, y0 + 8, "hd_ceil_dk")
            c.rect(x0 + 3, y0 + 3, x0 + 5, y0 + 5, "hd_ceil_lo")
            c.put(x0 + 3, y0 + 3, "hd_ceil_hi")
    c.noise(0, 0, 64, 64, ["hd_ceil_lo"], 0.04, rng)
    c.blotch(["hd_ceil_lo", "steel"], 4, rng, size=(1, 3))
    return c


mb.KIT.update({"hd_tin_red": paint_hd_tin("hd_red"), "hd_tin_teal": paint_hd_tin("hd_teal"),
               "hd_tin_yellow": paint_hd_tin("hd_yel"), "hd_tiles": paint_hd_tiles, "hd_felt": paint_hd_felt,
               "hd_vinyl": paint_hd_vinyl, "hd_ceiling": paint_hd_ceiling})


def paint_hd_door(rng):
    """A leaf of the hangout's sliding doors (scripts/hideout_doors.gd stretches it over a 1.2 x 2.08 m leaf): a steel
    frame, teal tin, a round porthole lit from the room behind, a red stripe, a steel pull and a kick plate."""
    c = mb.Canvas(24, 34, "hd_teal")
    for x in range(24):
        tone = {0: "hd_teal_hi", 2: "hd_teal_lo"}.get(x % 4)
        if tone:
            for y in range(34):
                c.put(x, y, tone)
    c.rect(0, 22, 24, 24, "hd_red")
    c.rect(0, 0, 24, 2, "iron_dark")
    c.rect(0, 32, 24, 34, "iron_dark")
    c.rect(0, 0, 2, 34, "iron_dark")
    c.rect(22, 0, 24, 34, "iron_dark")
    c.rect(2, 28, 22, 32, "steel")                                     # the kick plate
    for x in range(3, 22, 3):
        c.put(x, 30, "steel_light")
    for y in range(3, 16):                                             # the porthole: a steel ring round lit glass
        for x in range(4, 20):
            d = math.hypot(x + 0.5 - 12, y + 0.5 - 9)
            if d < 3.6:
                c.put(x, y, "bone" if (x - y) % 5 == 0 else "hazard_yellow")
            elif d < 5.0:
                c.put(x, y, "steel_light" if y < 9 else "steel")
    c.rect(19, 14, 21, 21, "steel_light")                              # the pull, by the meeting edge
    c.blotch(["steel", "rust"], 3, rng, area=(2, 2, 22, 28), size=(1, 2))
    return c


def paint_hd_secret(rng):
    """The hidden door into the passage (0.25.35): the armory's own concrete, 2.5 x 2.9 m at the kit's 16 px a metre."""
    big = paint_bk_old(rng)
    c = mb.Canvas(40, 46, "bk_old")
    for y in range(46):
        for x in range(40):
            c.put(x, y, big.px[y + 9][x + 12])
    return c


def write_door_texture():
    for name, painter in (("hangout_door", paint_hd_door), ("hangout_secret", paint_hd_secret)):
        rows = mb.styled(painter(random.Random(name)), random.Random(name))
        mb.write_png(os.path.join(mb.ROOT, "assets", "textures", name + ".png"), len(rows[0]), len(rows), rows)


DOORS = []          # the hangout's sliding doors: (middle x, floor y, z, width, height, yaw, side) for hideout_doors.gd


def _kit(mat, tile=mb.TILE_M):
    """A box style: every face but the bottom in a kit texture at `tile` metres."""
    return lambda n, m, q: None if n[1] < -0.7 else (mat, mb.uv_world(tile))


# ------------------------------------------------------------------------------------------------ shapes
def vault_y(x, half, spring, crown):
    t = max(0.0, 1.0 - (x / half) ** 2)
    return spring + (crown - spring) * math.sqrt(t)


def vault_xs(half, n):
    """x positions across an arch: closer together near the walls, where it curves most."""
    return sorted({round(-half * math.cos(math.pi * k / n), 4) for k in range(n + 1)})


def quad(b, pts, inside, mat, uv=None, away=False):
    """A face (maybe not flat: rock) turned to face the point `inside` (away from it if `away`)."""
    d1 = mb.v_sub(pts[2], pts[0])
    d2 = mb.v_sub(pts[3], pts[1]) if len(pts) == 4 else mb.v_sub(pts[2], pts[1])
    n = mb.cross(d1, d2)
    ln = math.sqrt(mb.dot(n, n))
    if ln < 1e-9:
        return
    n = mb.v_scale(n, 1.0 / ln)
    mid = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
    if (mb.dot(n, mb.v_sub(inside, mid)) < 0) != away:
        n = mb.v_scale(n, -1.0)
    b.poly(pts, n, mat, uv or mb.uv_world())


def value_noise(seed, nu, nv):
    """Smooth noise 0..1 over (u, v), u wrapping round at nu."""
    r = random.Random(seed)
    g = [[r.random() for _ in range(nv + 2)] for _ in range(nu)]

    def f(u, v):
        i, j = int(math.floor(u)), int(math.floor(v))
        s, t = u - i, v - j
        s, t = s * s * (3 - 2 * s), t * t * (3 - 2 * t)
        a, c = g[i % nu], g[(i + 1) % nu]
        j = max(0, min(nv, j))
        return (a[j] * (1 - s) + c[j] * s) * (1 - t) + (a[j + 1] * (1 - s) + c[j + 1] * s) * t
    return f


def catmull(points, step):
    """A smooth closed curve through `points`, about `step` apart."""
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        seg = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        k = max(1, round(seg / step))
        for s in range(k):
            t = s / k
            out.append(tuple(0.5 * ((2 * p1[c]) + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t * t
                                    + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t * t * t) for c in range(2)))
    return out


class Tunnel:
    """A straight arched tunnel off the hall: axis D (unit x, z) from O, a0..a1 along it, hw half its width."""

    def __init__(self, name, O, D, a0, a1, hw, spring, crown, lip, mats, ribs=None):
        self.name, self.O, self.D, self.a0, self.a1 = name, O, D, a0, a1
        self.U = (-D[1], D[0])
        self.hw, self.spring, self.crown, self.lip = hw, spring, crown, lip
        self.wall, self.ceil, self.floor, self.frame = mats
        self.ribs = ribs
        self.open_end = False      # no wall at a1 (0.25.17: the range's end opens into the crack to the hangout)
        self.into = None           # a narrower tunnel carrying on from a1: the end wall is a ring round it
        self.drop = 0.0            # how far below the hall its a0 end is (0.25.23: the way down to the hangout)

    def off(self, a):
        """How far the floor sits below the hall's at a: the floor slopes evenly from -drop at a0 up to 0 at a1."""
        return -self.drop * (self.a1 - a) / (self.a1 - self.a0) if self.drop else 0.0

    def P(self, u, y, a):
        return (self.O[0] + self.D[0] * a + self.U[0] * u, y + self.off(a), self.O[1] + self.D[1] * a + self.U[1] * u)

    def local(self, p):
        dx, dz = p[0] - self.O[0], p[2] - self.O[1]
        return dx * self.U[0] + dz * self.U[1], dx * self.D[0] + dz * self.D[1]

    def arch(self, u):
        return vault_y(u, self.hw, self.spring, self.crown)

    def yaw(self):
        """A box's yaw that turns its x across the tunnel."""
        return math.degrees(math.atan2(-self.U[1], self.U[0]))

    def hole(self, p):
        """Is p inside the tunnel's mouth (where the hall's wall is left out)?"""
        u, a = self.local(p)
        return abs(u) < self.hw - 0.01 and p[1] - self.off(a) < self.arch(u) - 0.01 and self.a0 - 6.0 < a < self.a0 + 2.0

    def profile(self, out=0.0):
        """The tunnel's outline across (u, y), pushed `out` outwards."""
        us = vault_xs(self.hw, 12)
        pts = [(-self.hw - out, 0.0), (-self.hw - out, BAND)]
        for u in us:
            y = self.arch(u)
            nu, ny = (-1.0, 0.0) if u <= -self.hw else ((1.0, 0.0) if u >= self.hw else (u / self.hw * 0.6, 1.0))
            ln = math.hypot(nu, ny)
            pts.append((u + nu / ln * out, y + ny / ln * out))
        pts += [(self.hw + out, BAND), (self.hw + out, 0.0)]
        return pts

    def draw(self, ctx):
        b = ctx.b
        a_s, a1, hw = self.a0 - self.lip, self.a1, self.hw
        ax = lambda a, y=1.5: self.P(0.0, y, a)                         # noqa: E731 (a point on the axis)
        quad(b, [self.P(-hw, 0, self.a0), self.P(hw, 0, self.a0), self.P(hw, 0, a1), self.P(-hw, 0, a1)],
             ax(self.a0, 5.0), self.floor)
        prof = self.profile()
        for (ua, ya), (ub, yb) in zip(prof, prof[1:]):
            mat = self.wall if max(ya, yb) <= self.spring + 0.01 else self.ceil
            if max(ya, yb) <= BAND + 0.01 and self.wall == "bk_old":
                mat = "bk_band"
            quad(b, [self.P(ua, ya, a_s), self.P(ub, yb, a_s), self.P(ub, yb, a1), self.P(ua, ya, a1)],
                 ax((a_s + a1) / 2, min(ya, yb) * 0.5), mat)
            if not self.open_end:
                quad(b, [self.P(ua, 0, a1), self.P(ub, 0, a1), self.P(ub, yb, a1), self.P(ua, ya, a1)], ax(a1 - 2), self.wall)
        if self.into is not None:                                      # the end wall: a ring round the narrower tunnel
            o = self.into
            inner = [o.P(u, y, o.a1) for u, y in o.profile()]
            if self.U[0] * o.U[0] + self.U[1] * o.U[1] < 0:            # (facing each other: its u runs the other way)
                inner.reverse()
            outer = [self.P(u, y, a1) for u, y in prof]
            for k in range(len(prof) - 1):
                quad(b, [outer[k], outer[k + 1], inner[k + 1], inner[k]], ax(a1 - 2), self.wall)
        # The frame round the mouth: its face towards the hall, and its outer edge.
        # (2.4 m wide and running 2 m back into the rock: the hall's faces round the mouth are left out a whole face at
        # a time, and the bumpy rock can sit back from the frame; narrower left gaps you could see the void through,
        # owner 2026-10-25 "SC1")
        outer = self.profile(2.4)
        for (p, q), (r, s) in zip(zip(prof, prof[1:]), zip(outer, outer[1:])):
            quad(b, [self.P(p[0], p[1], a_s), self.P(q[0], q[1], a_s), self.P(s[0], s[1], a_s), self.P(r[0], r[1], a_s)],
                 ax(a_s - 3), self.frame)
            quad(b, [self.P(r[0], r[1], a_s), self.P(s[0], s[1], a_s), self.P(s[0], s[1], a_s + self.lip + 2.0),
                     self.P(r[0], r[1], a_s + self.lip + 2.0)], ax(a_s + 0.3, 1.2), self.frame, away=True)
        if self.ribs:
            mat, every, t = self.ribs
            a = self.a0 + every
            while a < a1 - 1.0:
                inner = self.profile(-t)
                for (p, q), (r, s) in zip(zip(inner, inner[1:]), zip(prof, prof[1:])):
                    for aa in (a - 0.12, a + 0.12):
                        quad(b, [self.P(p[0], p[1], aa), self.P(q[0], q[1], aa), self.P(s[0], s[1], aa),
                                 self.P(r[0], r[1], aa)], self.P(0, 1.5, a + (aa - a) * 20), mat)
                    quad(b, [self.P(p[0], p[1], a - 0.12), self.P(q[0], q[1], a - 0.12), self.P(q[0], q[1], a + 0.12),
                             self.P(p[0], p[1], a + 0.12)], ax(a, 1.5), mat)
                a += every

    def slope_rows(self):
        """Collision for a sloping tunnel (drop): its floor (a ramp), walls and roof as boxes tilted along it."""
        hw, a_s, a1 = self.hw, self.a0 - self.lip, self.a1
        run = a1 - a_s
        yaw = math.degrees(math.atan2(-self.D[0], -self.D[1]))
        pitch = math.degrees(math.atan2(self.drop, a1 - self.a0))
        length = run / math.cos(math.radians(pitch)) + 0.6
        out = []
        for u0, y0, u1, y1 in ((-hw - 0.3, -0.3, hw + 0.3, 0.0), (-hw - 1.3, -0.3, -hw, self.crown + 0.6),
                               (hw, -0.3, hw + 1.3, self.crown + 0.6), (-hw - 0.3, self.crown, hw + 0.3, self.crown + 0.4)):
            c = self.P((u0 + u1) / 2, (y0 + y1) / 2, (a_s + a1) / 2)
            out.append({"pos": list(c), "size": [u1 - u0, (y1 - y0) / math.cos(math.radians(pitch)), length], "yaw": yaw,
                        "pitch": pitch, "colour": "stairs", "solid": True, "kind": "hd_solid"})
        return out

    def rows(self, put):
        hw, a_s, a1 = self.hw, self.a0 - self.lip, self.a1
        top = self.crown + 0.3

        def box(u0, y0, a0, u1, y1, a1_, kind=None):
            p, q = self.P(u0, y0, a0), self.P(u1, y1, a1_)
            put(min(p[0], q[0]), y0, min(p[2], q[2]), max(p[0], q[0]), y1, max(p[2], q[2]), kind=kind)
        box(-hw - 0.3, -0.3, self.a0, hw + 0.3, 0.0, a1 + (0.0 if self.into is not None and self.into.drop else 0.3))
        # (0.25.35: not on into a sloping passage: its 0.1 m lip over the slope stopped you walking back up)
        box(-hw - 1.3, 0.0, a_s, -hw, top, a1)
        box(hw, 0.0, a_s, hw + 1.3, top, a1)
        # (0.22.0, World reacts: the mouth's frame stands 2.4 m out from the walls; this was walk-through past 1.3 m)
        box(-hw - 2.4, 0.0, a_s, -hw - 1.3, top, a_s + self.lip + 2.0)
        box(hw + 1.3, 0.0, a_s, hw + 2.4, top, a_s + self.lip + 2.0)
        if not self.open_end:
            box(-hw - 0.3, 0.0, a1, hw + 0.3, top, a1 + 0.3)
        box(-hw - 0.3, self.crown, a_s, hw + 0.3, top, a1)
        if self.into is not None:                                      # the ring round the narrower tunnel
            o = self.into
            us = sorted(self.local(o.P(s * o.hw, 0.0, o.a1))[0] for s in (-1, 1))
            box(-hw - 0.3, 0.0, a1, us[0], top, a1 + 0.3)
            box(us[1], 0.0, a1, hw + 0.3, top, a1 + 0.3)
            box(us[0], o.crown, a1, us[1], top, a1 + 0.3)


def place_row(r):
    """Move a box row drawn in the hangout's plan frame to where the hangout is."""
    H = LAY.hang
    r["pos"] = list(H.w(r["pos"]))
    r["yaw"] = r["yaw"] + H.turn


def dome(ctx, outline, C, profile, mats, amp=0.0, holes=(), seed="dome", tunnels=(), floor_rings=(1.0, 0.85, 0.7, 0.55, 0.4, 0.26, 0.13)):
    """The hall: walls rising from `outline` (x, z, closed) and closing over as `profile` (scale toward C, y) goes up,
    bumped out (rock) by up to `amp`. Wall faces with a corner inside a tunnel's mouth are left out."""
    b = ctx.b
    M = len(outline)
    noise = value_noise(seed, max(4, M // 3), len(profile) + 2)
    grid = []
    for k, (f, y) in enumerate(profile):
        ring = []
        for i, (x, z) in enumerate(outline):
            dx, dz = x - C[0], z - C[1]
            ln = math.hypot(dx, dz) or 1.0
            n = noise(i / 3.0, k * 0.7)
            inward = min(1.0, max(0.0, (y - 2.8) / 1.5)) * 0.35
            push = amp * min(1.0, y / 1.2) * (n - inward) * max(f, 0.3)
            for t in tunnels:                                          # the rock sits flush round a tunnel's frame
                u, a = t.local((x, 0.0, z))
                if a > 0 and abs(u) < t.hw + 5.0:
                    push *= min(1.0, max(0.0, (abs(u) - t.hw - 2.0) / 3.0))
            ring.append((C[0] + dx * f + dx / ln * push, y, C[1] + dz * f + dz / ln * push))
        grid.append(ring)
    for k in range(len(profile) - 1):
        for i in range(M):
            j = (i + 1) % M
            q = [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
            if any(h(p) for p in q for h in holes):
                continue
            my = sum(p[1] for p in q) / 4
            mat = mats[0] if my < mats[2] else mats[1]
            if mat == "bk_old" and my < BAND:
                mat = "bk_band"
            quad(ctx.b, q, (C[0], my * 0.5, C[1]), mat)
    top = (C[0], profile[-1][1] + 0.4, C[1])
    for i in range(M):                                                 # the top: a fan (an n-gon this shape folds)
        quad(b, [grid[-1][i], grid[-1][(i + 1) % M], top], (C[0], 0.0, C[1]), mats[1])
    # The floor: rings in to the middle (cut into cells by the light bake).
    rings = [[(C[0] + (x - C[0]) * f, 0.0, C[1] + (z - C[1]) * f) for x, z in outline] for f in floor_rings]
    for ra, rb in zip(rings, rings[1:]):
        for i in range(M):
            j = (i + 1) % M
            b.poly([ra[i], ra[j], rb[j], rb[i]], (0, 1, 0), mats[3], mb.uv_world())
    c = (C[0], 0.0, C[1])
    for i in range(M):
        b.poly([rings[-1][i], rings[-1][(i + 1) % M], c], (0, 1, 0), mats[3], mb.uv_world())
    return grid


def wall_rows(put, outline, C, f_at, base_at, tunnels, top):
    """Collision round the hall: a box behind each stretch of wall, its face where the wall is at head height."""
    M = len(outline)
    for i in range(M):
        p, q = outline[i], outline[(i + 1) % M]
        mx, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        if any(t.hole((mx, 0.5, mz)) for t in tunnels):
            continue
        f = f_at(base_at(mx, mz) + 2.2)
        pa = (C[0] + (p[0] - C[0]) * f, C[1] + (p[1] - C[1]) * f)
        pb = (C[0] + (q[0] - C[0]) * f, C[1] + (q[1] - C[1]) * f)
        dx, dz = pb[0] - pa[0], pb[1] - pa[1]
        ln = math.hypot(dx, dz)
        if ln < 1e-6:
            continue
        nx, nz = dz / ln, -dx / ln                                     # one of the two sideways: make it point out
        if nx * (pa[0] - C[0]) + nz * (pa[1] - C[1]) < 0:
            nx, nz = -nx, -nz
        cx, cz = (pa[0] + pb[0]) / 2 + nx * 0.5, (pa[1] + pb[1]) / 2 + nz * 0.5
        yaw = math.degrees(math.atan2(dx, dz))
        put(cx, 0.0, cz, cx, top, cz, kind="hd_solid", size_xz=(1.0, ln + 0.3), yaw=yaw)


# ------------------------------------------------------------------------------------------------ layouts
SIGNS = {"guns": "GUNSMITH", "meds": "MEDIC", "supplies": "SUPPLIER", "valuables": "SUPREME", "ming": "MING",
         "stash": "STASH", "wardrobe": "WARDROBE", "workbench": "WORKBENCH", "quests": "QUESTS", "stats": "STATS",
         "mess": "MESS", "range": "RANGE", "lights": "QUIET 0200", "wc": "WASHROOM", "chow": "CHOW 1900", "clean": "KEEP CLEAN", "d10": "10 M", "d25": "25 M", "d50": "50 M", "d100": "100 M"}
TRADERS = ("guns", "meds", "supplies", "valuables", "ming")
TINS = ("cabin_tin_b", "shed_metal", "cabin_tin_d", "shed_metal")


class Layout:
    hang = None


def cave_layout():
    L = Layout()
    L.C = (0.0, -2.0)
    L.crown = 11.0
    phis = (0, 0.09, 0.19, 0.3, 0.42, 0.55, 0.68, 0.82, 0.96, 1.1, 1.24, 1.36, 1.47)
    L.profile = [(math.cos(p) ** 0.6, L.crown * math.sin(p)) for p in phis]
    L.f_at = lambda y: math.cos(math.asin(min(0.999, y / L.crown))) ** 0.6
    L.mats = ("bk_rock", "bk_rock", 99.0, "bk_ground")
    L.amp = 1.8
    L.pillars = [(9.0, -9.0, 1.3), (-5.5, 7.0, 1.1)]
    mouth_z = -19.2
    ring = [(3.0, mouth_z), (6.5, -19.4), (11.0, -18.4), (16.0, -15.8), (20.0, -12.0), (22.5, -7.0), (23.5, -1.5),
            (22.5, 4.0), (20.5, 8.5), (18.0, 12.5), (13.0, 14.5), (8.0, 13.6), (4.0, 12.8), (0.0, 13.4), (-4.0, 14.5),
            (-9.0, 15.5), (-14.0, 14.0), (-19.0, 10.5), (-22.5, 6.0), (-24.0, 1.5), (-24.5, -4.0), (-24.0, -10.0),
            (-22.5, -15.0), (-17.0, -18.6), (-9.0, -19.5), (-3.0, mouth_z)]
    curve = catmull(ring, 1.25)
    # across the mine's mouth: straight, a corner every half metre (the mouth's edges land on corners)
    curve = [p for p in curve if not (abs(p[0]) < 6.2 and p[1] < -18.0)]
    curve += [(-6.0 + 0.5 * k, mouth_z) for k in range(25)]
    curve.sort(key=lambda p: math.atan2(p[1] - L.C[1], p[0] - L.C[0]))
    L.outline = curve
    L.tunnels = [Tunnel("range", L.C, (0.0, -1.0), L.C[1] - mouth_z, L.C[1] - mouth_z + 104.0, 3.0, 2.4, 3.6, 1.0,
                        ("bk_rock", "bk_rock", "bk_ground", "bk_old"), ribs=("bk_iron", 4.0, 0.25))]
    L.ledge_y = 2.0
    zs = [-23.0 + k * 1.5 for k in range(20)] + [5.5]
    wr = random.Random("ledge")
    L.ledge = [(-14.8 + wr.uniform(-0.25, 0.25), z) for z in zs]       # its front edge, north to south
    L.stair = ((-9.6, -5.0), (-14.8, -5.0), 2.6)                       # foot, top (x, z), width
    # bays: (id, back middle (x, z), along, facing, width, depth, floor y, kind)
    L.bays = []
    for k, bid in enumerate(TRADERS):                                  # five in a row along the ledge, facing east
        L.bays.append((bid, (-21.6, -13.8 + k * 3.6 + 1.8), (0.0, 1.0), (1.0, 0.0), 3.6, 3.8, L.ledge_y, "tin"))
    for bid, z, w, x in (("stash", -9.0, 5.6, 22.2), ("wardrobe", -2.4, 4.4, 22.8), ("workbench", 4.0, 4.6, 21.8)):
        L.bays.append((bid, (x, z), (0.0, 1.0), (-1.0, 0.0), w, 4.4, 0.0, "bunker"))
    L.war_table = (0.0, -5.0)
    L.spawn = (0.0, -1.0)
    L.mess = (-12.0, 9.8)
    L.bunks = (12.0, 10.0)
    L.wc = (1.2, 9.0, 5.0, 12.4)
    L.kitchen = (-16.0, 11.2, 55.0)
    L.mess = (-11.5, 8.0)
    L.bunk_list = [(9.0, 11.2, 0.0), (11.6, 11.5, 0.0), (14.2, 11.4, 0.0), (16.6, 9.6, -30.0)]
    L.sandbags = [((-6.5, -17.8), (-4.2, -17.8)), ((4.2, -17.8), (6.5, -17.8)), ((15.2, -13.6), (17.4, -12.4)),
                  ((-8.4, -7.4), (-8.4, -9.8)), ((6.8, 7.6), (9.4, 7.6)), ((-2.6, 4.4), (-0.4, 5.6))]
    L.duffels = [(-17.5, -16.0, 5), (9.0, -16.8, 4), (16.4, -14.4, 5), (18.6, 9.0, 4), (-8.0, 13.4, 3), (6.6, 11.6, 3),
                 (-19.8, 8.0, 4), (-2.0, 11.6, 3)]
    L.crates = [(-7.5, -16.3), (12.0, -15.6), (-5.0, 11.8)]
    L.generator = (-8.0, -12.5)
    L.keep_clear = [(0.0, -19.0, 7.5, 3.0), (-21.0, -5.0, 4.0, 10.5), (21.0, -1.0, 4.0, 12.0), (3.0, 11.0, 3.0, 3.0),
                    (-16.0, 11.0, 3.0, 2.5), (12.5, 11.0, 5.0, 2.5)]
    L.boards = [("quests", (-9.5, -18.6), (0.0, 1.0)), ("stats", (9.5, -18.3), (0.0, 1.0))]
    L.strings = [(200, 20, 5.5), (160, -20, 5.8), (250, 70, 6.2), (110, 290, 6.0), (135, 315, 5.6), (45, 225, 5.9)]
    L.work_lamps = [(2.8, -7.0, 1.1, 3.2), (-9.0, 10.4, 1.0, 3.0), (12.0, 8.2, 0.9, 2.8), (-11.0, -6.5, 0.9, 3.0),
                    (-18.0, -15.5, 0.9, 2.6), (3.5, -16.0, 1.0, 3.0)]
    return L


# The hangout (0.25.17, owner picked it from four secret rooms: "a crack at the 100 m end opens onto a flooded mine
# hangout: pool table, jukebox"). 0.25.23 (owner: "the hideout can be a bit closer, so it's easier to find, then make
# a tunnel to it that goes deeper underground"): the armory's end wall has split open instead, and a narrow passage
# with steel stairs runs down into the rock to the den, HANG_DEPTH below the hall.
# The den is drawn as it was built, round its own middle with the passage coming in from +z (H's "plan" frame), then
# turned and lowered into place (H.w): its passage runs on from the armory's end.
HANG_R = 8.0                                       # the den's radius, on average (0.25.26: was 6.6, and squarish)
HANG_CROWN = 8.5                                   # (the rock over it all; 0.25.35: room for the loft)
CEIL = 3.4                                         # the ground floor's ceiling (0.25.35, owner: "make the roof match
UP = 3.6                                           # the room, I hate how it's cavey"), the loft's floor, its ceiling
UP_TOP = 6.2
HOLE = (-4.8, -2.8, -3.6, 3.6)                     # the stairwell up to the loft (x0, z0, x1, z1, plan frame)
HANG_DEPTH = 4.5                                   # how far below the hall the den's floor is
CRACK_LEN = 13.0                                   # from the armory's end wall to where the den's wall would be


def hangout_layout(rt):
    """The passage (a narrow rock tunnel, sloping down) and the den (a small cave like the hall), past rt's end."""
    H = Layout()
    H.C = (0.0, 0.0)                               # (plan frame)
    phis = (0, 0.09, 0.19, 0.3, 0.42, 0.55, 0.68, 0.82, 0.96, 1.1, 1.24, 1.36, 1.47)
    H.crown = HANG_CROWN
    H.profile = [(math.cos(p) ** 0.6, HANG_CROWN * math.sin(p)) for p in phis]
    H.f_at = lambda y: math.cos(math.asin(min(0.999, y / HANG_CROWN))) ** 0.6
    H.mats = ("bk_rock", "bk_rock", 99.0, "bk_ground")
    H.amp = 1.0
    rock = ("bk_rock", "bk_rock", "bk_ground", "bk_rock")
    jit = random.Random("hangout")
    bumps = [jit.uniform(-0.35, 0.35) for _ in range(20)]

    def radius(a):
        """0.25.26 (owner: "less of a square... I hate when things are fully cubes", "a bit bigger"): an uneven round
        room, lobed, with a nook bulging out to the east for the couch."""
        k = (a / (2 * math.pi) * 20) % 20
        i = int(k)
        j = bumps[i] * (1 - (k - i)) + bumps[(i + 1) % 20] * (k - i)
        return (HANG_R + 1.8 * max(0.0, math.cos(a)) ** 4 + 0.7 * math.sin(3 * a + 0.9) + 0.35 * math.sin(5 * a + 2.1)
                + j)
    H.radius = radius
    r_in = radius(math.pi / 2)                     # where the passage comes in
    a0, a1 = math.sqrt(r_in * r_in - 1.0), CRACK_LEN + r_in

    def passage(O, D):
        t = Tunnel("crack", O, D, a0, a1, 1.0, 2.0, 2.6, 0.4, rock)
        t.lip = t.a0 * (1.0 - H.f_at(t.crown + 1.3)) + 0.6
        t.open_end = True
        return t
    crack = passage(H.C, (0.0, 1.0))               # (plan frame, flat: what the den is cut round)
    H.crack = crack
    # Where it goes: the den's middle a1 on past rt's end, the plan frame turned so its -z runs along rt.
    end = rt.P(0.0, 0.0, rt.a1)
    H.Cw = (end[0] + rt.D[0] * a1, end[2] + rt.D[1] * a1)
    H.turn = math.degrees(math.atan2(-rt.D[0], -rt.D[1]))
    H.down = passage(H.Cw, (-rt.D[0], -rt.D[1]))   # the real one, sloping up from the den to rt's end
    H.down.drop = HANG_DEPTH
    rt.open_end, rt.into = True, H.down
    cy, sy = math.cos(math.radians(H.turn)), math.sin(math.radians(H.turn))

    def w(p):                                      # a plan-frame point (x, y, z) where it ends up
        x, y, z = p[0] - H.C[0], p[1], p[2] - H.C[1]
        return (H.Cw[0] + x * cy + z * sy, y - HANG_DEPTH, H.Cw[1] - x * sy + z * cy)

    def wn(n):                                     # a direction, turned the same way
        return (n[0] * cy + n[2] * sy, n[1], -n[0] * sy + n[2] * cy)
    H.w, H.wn = w, wn
    pts = []
    for k in range(96):
        a = 2 * math.pi * k / 96
        p = (H.C[0] + radius(a) * math.cos(a), H.C[1] + radius(a) * math.sin(a))
        u, al = crack.local((p[0], 0, p[1]))
        if not (abs(u) < crack.hw + 0.3 and al > 0):
            pts.append(p)
    for k in range(int(round(crack.hw * 2 / 0.4)) + 1):
        p = crack.P(-crack.hw + k * 0.4, 0, crack.a0)
        pts.append((p[0], p[2]))
    pts.sort(key=lambda p: math.atan2(p[1] - H.C[1], p[0] - H.C[0]))
    H.outline = [p for k, p in enumerate(pts) if math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) > 0.05]
    H.outline_w = [(w((x, 0, z))[0], w((x, 0, z))[2]) for x, z in H.outline]
    cx, cz = H.C
    H.wall_r = lambda a: radius(a) * H.f_at(2.6) - 0.4                # the tin walls' inside, at angle a
    H.up_r = lambda a: radius(a) * H.f_at(UP_TOP + 0.2) - 0.4          # ... and the loft's
    H.table = (cx - 1.2, cz + 0.8)                 # the pool table, long side across the den
    H.jukebox = (cx - H.wall_r(math.pi) + 0.45, cz)    # against the west wall, facing east
    H.booth = (cx + H.wall_r(0.0) - 2.4, cz)       # the round booth's middle, in the east nook
    H.seat_list = []                               # (x, y, z, yaw) in the plan frame: den() fills it
    return H


def post_layout(rock=False):
    """The command post; rock=True: its hall is a cave the tunnels were dug off (owner liked both, 2026-10-25)."""
    L = Layout()
    L.C = (0.0, 0.0)
    R, spring, crown = 13.0, 4.8, 12.0
    L.crown = crown
    if rock:
        L.crown = crown = 11.5
        phis = (0, 0.09, 0.19, 0.3, 0.42, 0.55, 0.68, 0.82, 0.96, 1.1, 1.24, 1.36, 1.47)
        L.profile = [(math.cos(p) ** 0.6, crown * math.sin(p)) for p in phis]
        L.f_at = lambda y: math.cos(math.asin(min(0.999, y / crown))) ** 0.6
        L.mats = ("bk_rock", "bk_rock", 99.0, "bk_ground")
        L.amp = 1.6
        L.pillars = [(8.6, 8.6, 1.2), (-8.8, -8.4, 1.1)]
    else:
        walls = [(1.0, y) for y in (0.0, 0.6, 1.2, 1.8, 2.4, 3.2, 4.0, spring)]
        phis = (0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0, 1.15, 1.3, 1.45)
        L.profile = walls + [(math.cos(p), spring + (crown - spring) * math.sin(p)) for p in phis]
        L.f_at = lambda y: 1.0 if y <= spring else math.cos(math.asin(min(0.999, (y - spring) / (crown - spring))))
        L.mats = ("bk_old", "bk_old_ceiling", spring + 0.01, "bk_dirt")
        L.amp = 0.0
        L.pillars = []
    jit = random.Random("hub")
    bumps = [jit.uniform(-0.6, 0.6) for _ in range(24)]

    def radius(a):                     # the cave bulges out between the tunnels (round for the concrete one)
        if not rock:
            return R
        k = (a / (2 * math.pi) * 24) % 24
        i = int(k)
        j = bumps[i] * (1 - (k - i)) + bumps[(i + 1) % 24] * (k - i)
        return R + 4.0 * abs(math.sin(2 * a)) ** 1.3 + j * abs(math.sin(2 * a))
    concrete = ("bk_old", "bk_old_ceiling", "bk_dirt", "bk_old")
    L.tunnels = [Tunnel("range", L.C, (0.0, -1.0), math.sqrt(R * R - 9.0), 118.0, 3.0, 2.6, 4.0, 0.4, concrete,
                        ribs=("bk_old", 4.8, 0.3)),
                 Tunnel("market", L.C, (-1.0, 0.0), math.sqrt(R * R - 25.0), 40.0, 5.0, 3.4, 6.2, 0.4, concrete,
                        ribs=("bk_old", 4.6, 0.3)),
                 Tunnel("armory", L.C, (1.0, 0.0), math.sqrt(R * R - 20.25), 31.0, 4.5, 3.2, 5.8, 0.4, concrete,
                        ribs=("bk_old", 4.6, 0.3)),
                 Tunnel("mess", L.C, (0.0, 1.0), math.sqrt(R * R - 20.25), 36.0, 4.5, 3.2, 5.8, 0.4, concrete,
                        ribs=("bk_old", 4.6, 0.3))]
    if rock:                           # the concrete mouths stand out of the rock as far as the cave curves in over them
        for t in L.tunnels:
            t.lip = t.a0 * (1.0 - L.f_at(t.crown + 1.3)) + 0.6
    L.hang = hangout_layout(L.tunnels[2]) if rock else None
    # the circle, with a straight chord across each tunnel's mouth (corners every half metre)
    pts = []
    for k in range(96 if not rock else 120):
        a = 2 * math.pi * k / (96 if not rock else 120)
        p = (radius(a) * math.cos(a), radius(a) * math.sin(a))
        if not any(abs(t.local((p[0], 0, p[1]))[0]) < t.hw + 0.3 and t.local((p[0], 0, p[1]))[1] > 0 for t in L.tunnels):
            pts.append(p)
    for t in L.tunnels:
        n = int(round(t.hw * 2 / 0.5))
        for k in range(n + 1):
            u = -t.hw + k * 0.5
            p = t.P(u, 0, t.a0)
            pts.append((p[0], p[2]))
    pts.sort(key=lambda p: math.atan2(p[1], p[0]))
    L.outline = [p for k, p in enumerate(pts) if math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) > 0.05]
    L.ledge_y = 0.0
    L.ledge = None
    L.stair = None
    L.bays = []

    def side(t, bid, a, u_sign, w, depth, kind):
        p = t.P(u_sign * t.hw, 0, a)
        L.bays.append((bid, (p[0], p[2]), t.D, (-t.U[0] * u_sign, -t.U[1] * u_sign), w, depth, 0.0, kind))
    m, arm = L.tunnels[1], L.tunnels[2]
    for k, bid in enumerate(("guns", "meds", "supplies")):             # the market: three stalls one side, two the other
        side(m, bid, 17.3 + k * 4.8, 1, 4.6, 3.0, "tin")
    for k, bid in enumerate(("valuables", "ming")):
        side(m, bid, 19.7 + k * 4.8, -1, 4.6, 3.0, "tin")
    side(arm, "stash", 19.0, -1, 7.0, 2.6, "cage")                    # the armory
    side(arm, "wardrobe", 16.8, 1, 4.4, 2.4, "cage")
    side(arm, "workbench", 22.0, 1, 4.4, 2.4, "cage")
    L.war_table = (0.0, -1.5)
    L.spawn = (0.0, 3.0)
    L.mess = (0.0, 19.0)
    L.bunks = (0.0, 30.0)
    L.wc = (-4.45, 32.4, 4.45, 35.95)                                  # the washroom: the end of the tunnel
    L.kitchen = (3.9, 22.5, 0.0)
    L.bunk_list = [(-3.4, 27.0, 90.0), (-3.4, 29.6, 90.0), (3.4, 27.0, 90.0), (3.4, 29.6, 90.0)]

    def at(r, deg):                    # r: metres in from the wall
        a = math.radians(deg)
        rr = radius(a) * (L.f_at(1.5) if rock else 1.0) - r
        return (rr * math.cos(a), rr * math.sin(a))
    L.sandbags = [(at(2.0, a - 8), at(2.0, a + 8)) for a in ((135, 225) if rock else (45, 135, 225))]
    L.duffels = [at(1.4, a) + (n,) for a, n in ((30, 4), (62, 5), (150, 3), (205, 5), (240, 4), (330, 3))]
    L.duffels += [(-38.6, -3.4, 5), (29.6, 3.0, 4)]
    L.crates = [at(2.6, 115), at(2.6, 290), (-38.0, 2.6), (29.4, -2.4)]
    L.generator = at(2.4, 315)
    L.keep_clear = []
    # The quests and stats boards stand out in the hall on their own, lit, both facing where you spawn (owner
    # 2026-10-25: the quests board was "shoved in the corner", the stats board hard to see).
    L.boards = []
    for bid, (x, z) in (("quests", (7.4, -6.4)), ("stats", (-7.5, -7.0))):
        dx, dz = L.spawn[0] - x, L.spawn[1] + 1.0 - z
        ln = math.hypot(dx, dz)
        L.boards.append((bid, (x, z), (dx / ln, dz / ln)))
    L.strings = [(20, 200, 7.0), (70, 250, 7.6), (110, 290, 7.2), (160, 340, 7.4)]
    L.work_lamps = [(2.8, -4.6, 1.1, 3.2), (-38.5, 3.2, 1.0, 3.0), (29.0, 3.0, 1.0, 3.0), (5.0, 8.5, 0.9, 3.0)]
    if rock:
        L.work_lamps += [at(2.0, 70) + (1.0, 3.2), at(2.0, 150) + (1.0, 3.2), at(2.5, 250) + (1.0, 3.2),
                         at(2.0, 330) + (1.0, 3.2), (3.0, 15.5, 0.9, 3.2)]
    return L


LAY = cave_layout() if SHAPE == "cave" else post_layout(rock=SHAPE == "mix")


def in_ledge(x, z):
    if not LAY.ledge:
        return False
    if z > LAY.ledge[-1][1] or z < LAY.ledge[0][1]:
        return False
    for (xa, za), (xb, zb) in zip(LAY.ledge, LAY.ledge[1:]):
        if za <= z <= zb:
            t = (z - za) / ((zb - za) or 1)
            return x < xa + (xb - xa) * t
    return False


def frame_box(o, t, n, out0, out1, al0, al1):
    """The x/z bounds of a box given in a bay's frame (out from its back, along it)."""
    pts = [(o[0] + n[0] * a + t[0] * b, o[1] + n[1] * a + t[1] * b) for a in (out0, out1) for b in (al0, al1)]
    return min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts)


def base_y(x, z):
    return LAY.ledge_y if in_ledge(x, z) else 0.0


def ramp(foot, top, rise, width):
    """A ramp (drawn as stairs) from foot up to top: (centre, size, yaw, pitch)."""
    dx, dz = top[0] - foot[0], top[1] - foot[1]
    run = math.hypot(dx, dz)
    length = math.hypot(run, rise)
    yaw = math.degrees(math.atan2(-dx / run, -dz / run))
    pitch = math.degrees(math.atan2(rise, run))
    n = mb.rot((0, 1, 0), yaw, pitch)
    mid = ((foot[0] + top[0]) / 2, rise / 2, (foot[1] + top[1]) / 2)
    return mb.v_sub(mid, mb.v_scale(n, 0.15)), (width, 0.3, length), yaw, pitch


# ------------------------------------------------------------------------------------------------ gray boxes
def boxes():
    rows = []

    def put(x0, y0, z0, x1, y1, z1, colour="bunker", kind=None, solid=True, size_xz=None, yaw=0.0):
        if size_xz:
            size = [size_xz[0], y1 - y0, size_xz[1]]
        else:
            size = [x1 - x0, y1 - y0, z1 - z0]
        rows.append({"pos": [(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2], "size": size,
                     "yaw": yaw, "pitch": 0.0, "colour": colour, "solid": solid, "kind": kind or "hd_solid"})

    def solid(x0, y0, z0, x1, y1, z1):           # shades the light bake too
        rows.append({"pos": [(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2], "size": [x1 - x0, y1 - y0, z1 - z0],
                     "yaw": 0.0, "pitch": 0.0, "colour": "bunker", "solid": True, "kind": None})
    xs = [p[0] for p in LAY.outline]
    zs = [p[1] for p in LAY.outline]
    solid(min(xs) - 2, -0.3, min(zs) - 2, max(xs) + 2, 0.0, max(zs) + 2)               # the floor
    wall_rows(put, LAY.outline, LAY.C, LAY.f_at, base_y, LAY.tunnels, LAY.crown)
    for t in LAY.tunnels:
        t.rows(put)
    H = getattr(LAY, "hang", None)
    if H:                                                              # the hangout: its floor, walls and the passage
        hx = [p[0] for p in H.outline_w]
        hz = [p[1] for p in H.outline_w]
        solid(min(hx) - 2, -HANG_DEPTH - 0.3, min(hz) - 2, max(hx) + 2, -HANG_DEPTH, max(hz) + 2)

        class Mouth:                                                   # (the passage's mouth, a little wider: the wall
            @staticmethod                                              # either side of it slants and blocked the way)
            def hole(p):
                u, a = H.crack.local(p)
                return abs(u) < H.crack.hw + 1.0 and H.crack.a0 - 6.0 < a < H.crack.a0 + 2.0

        def put_den(*args, **kw):                                      # (drawn in the plan frame, moved into place)
            put(*args, **kw)
            place_row(rows[-1])
        wall_rows(put_den, H.outline, H.C, H.f_at, lambda x, z: 0.0, [Mouth], H.crown)
        # The loft's floor (0.25.35): four slabs round the stairwell (they shade the light bake), and the stairs.
        x0h, z0h, x1h, z1h = HOLE
        E = 12.0
        S = H.crack.a0 - 0.2                                           # (not out over the passage: you'd hit your head)
        for a, b_ in (((-E, -E), (E, z0h)), ((-E, z1h), (E, S)), ((-E, z0h), (x0h, z1h)), ((x1h, z0h), (E, z1h))):
            solid(H.C[0] + a[0], UP - 0.2, H.C[1] + a[1], H.C[0] + b_[0], UP, H.C[1] + b_[1])
            place_row(rows[-1])
        sx = (x0h + x1h) / 2
        c, sz, yaw, pitch = ramp((sx, z1h), (sx, z0h), UP, x1h - x0h - 0.1)
        rows.append({"pos": list(c), "size": list(sz), "yaw": yaw, "pitch": pitch, "colour": "stairs", "solid": True,
                     "kind": "hd_solid"})
        place_row(rows[-1])
        rows.extend(H.down.slope_rows())
    if LAY.ledge:
        for (xa, za), (xb, zb) in zip(LAY.ledge, LAY.ledge[1:]):
            solid(min(xs) - 2, 0.0, za, (xa + xb) / 2, LAY.ledge_y, zb)
        (fx, fz), (tx, tz), w = LAY.stair
        c, s, yaw, pitch = ramp((fx, fz), (tx, tz), LAY.ledge_y, w)
        rows.append({"pos": list(c), "size": list(s), "yaw": yaw, "pitch": pitch, "colour": "stairs", "solid": True,
                     "kind": "hd_solid"})
        for (xa, za), (xb, zb) in zip(LAY.ledge, LAY.ledge[1:]):     # the rail along the edge (gap at the stairs)
            if zb < fz - w / 2 - 0.1 or za > fz + w / 2 + 0.1:
                put(min(xa, xb) - 0.05, LAY.ledge_y, za, max(xa, xb) + 0.05, LAY.ledge_y + 1.0, zb, "rail")
    for bid, o, t, n, w, depth, y0, kind in LAY.bays:
        for sd in (-1, 1):                                             # side walls
            back = -3.0 if kind == "bunker" else 0.0
            x0, z0, x1, z1 = frame_box(o, t, n, back, depth, sd * w / 2 - 0.1, sd * w / 2 + 0.1)
            if kind == "bunker":
                x0, z0, x1, z1 = frame_box(o, t, n, back, depth, sd * (w / 2 + 0.2) - 0.2, sd * (w / 2 + 0.2) + 0.2)
                solid(x0, y0, z0, x1, y0 + 3.2, z1)
            else:
                put(x0, y0, z0, x1, y0 + 2.4, z1, "tin")
        if kind == "bunker":
            x0, z0, x1, z1 = frame_box(o, t, n, -3.0, depth, -w / 2 - 0.4, w / 2 + 0.4)
            solid(x0, y0 + 3.2, z0, x1, y0 + 3.6, z1)
        if bid in TRADERS:
            x0, z0, x1, z1 = frame_box(o, t, n, depth - 0.8, depth - 0.2, -w / 2 + 0.5, w / 2 - 0.5)
            put(x0, y0, z0, x1, y0 + 1.0, z1, "counter")
    tx, tz = LAY.war_table
    put(tx - 2.7, 0.0, tz - 1.8, tx + 2.7, 1.0, tz + 1.8, "table")
    if LAY.wc and SHAPE == "cave":                                     # (the command post's is drawn by shower_block)
        x0, z0, x1, z1 = LAY.wc
        door = (x0 + x1) / 2
        put(x0 - 0.2, 0.0, z0, x0, 2.6, z1, "wc")
        put(x1, 0.0, z0, x1 + 0.2, 2.6, z1, "wc")
        put(x0 - 0.2, 0.0, z0 - 0.2, door - 0.45, 2.6, z0, "wc")
        put(door + 0.45, 0.0, z0 - 0.2, x1 + 0.2, 2.6, z0, "wc")
        rows.append({"pos": [(x0 + x1) / 2, 1.3, (z0 + z1) / 2], "size": [x1 - x0, 2.6, z1 - z0],
                     "yaw": 0.0, "pitch": 0.0, "colour": "wall", "solid": False, "kind": "washroom"})
        for kind, (xa, za, xb, zb), hgt in (("wc_toilet", (x0 + 0.4, z1 - 0.72, x0 + 0.85, z1), 0.85),
                                            ("wc_toilet", (x0 + 1.6, z1 - 0.72, x0 + 2.05, z1), 0.85),
                                            ("wc_sink", (x1 - 0.45, z0 + 1.0, x1, z0 + 1.5), 0.9)):
            rows.append({"pos": [(xa + xb) / 2, hgt / 2, (za + zb) / 2], "size": [xb - xa, hgt, zb - za],
                         "yaw": 0.0, "pitch": 0.0, "colour": "wood", "solid": True, "kind": kind})
    return rows


# ------------------------------------------------------------------------------------------------ helpers
EXTRA = []          # collision for the props the dressing places (added to the level after the build)


def block(x, y, z, sx, sy, sz, yaw=0.0):
    EXTRA.append({"pos": [x, y + sy / 2, z], "size": [sx, sy, sz], "yaw": yaw, "pitch": 0.0, "colour": "prop",
                  "solid": True, "kind": "hd_solid"})


def pipe(b, a, c, mat="bk_tube", t=0.05):
    """A tube (scaffold, pipe, cable) from point a to point c."""
    d = mb.v_sub(c, a)
    ln = math.sqrt(mb.dot(d, d))
    if ln < 1e-6:
        return
    yaw = math.degrees(math.atan2(d[0], d[2]))
    pitch = -math.degrees(math.asin(max(-1.0, min(1.0, d[1] / ln))))
    b.box(mb.v_scale(mb.v_add(a, c), 0.5), (t, t, ln), yaw=yaw, pitch=pitch, style=mb._solid(mat))


def crate(b, x, y, z, sx, sy, sz, yaw=0.0, mat="olive"):
    """A military crate: the body and a darker lid band (standing 2 cm proud of the body's top, so the two never
    flicker through each other: owner 2026-10-25, the seats round the war table and the footlockers)."""
    b.box((x, y + sy / 2, z), (sx, sy, sz), yaw=yaw, style=mb._nb(mat))
    b.box((x, y + sy - 0.02, z), (sx + 0.04, 0.08, sz + 0.04), yaw=yaw, style=mb._solid("olive_dark"))


def drum(b, x, z, y=0.0, mat="cabin_tin_b"):
    # (the second box a little shorter at both ends: same-height tops flickered)
    b.box((x, y + 0.45, z), (0.5, 0.9, 0.5), style=mb._nb(mat))
    b.box((x, y + 0.45, z), (0.5, 0.86, 0.5), yaw=45, style=mb._nb(mat))
    b.box((x, y + 0.915, z), (0.46, 0.03, 0.46), yaw=22.5, style=mb._solid("bk_iron"))


def duffel(b, x, y, z, yaw, rng):
    """A green army duffel bag lying on its side: an octagonal roll, a strap, darker ends."""
    mat = rng.choice(("olive", "olive_dark", "bk_tarp"))
    ln, r = rng.uniform(0.8, 1.0), rng.uniform(0.17, 0.22)
    b.box((x, y + r * 0.7, z), (r * 2.0, r * 1.4, ln), yaw=yaw, style=mb._nb(mat))
    b.box((x, y + r, z), (r * 1.4, r * 2.0, ln - 0.08), yaw=yaw, style=mb._nb(mat))
    b.box((x, y + r, z), (r * 1.45, r * 2.04, 0.06), yaw=yaw, style=mb._solid("bk_cable"))      # the strap


def duffels(b, x, z, n, rng, y=0.0):
    """A heap of duffel bags in a corner, some on top of the others."""
    for k in range(n):
        yy = y if k < max(2, n * 2 // 3) else y + 0.36
        duffel(b, x + rng.uniform(-0.7, 0.7), yy, z + rng.uniform(-0.7, 0.7), rng.uniform(0, 180), rng)
    block(x, y, z, 1.6, 0.4, 1.6)


def sandbag_wall(b, a, c, h=1.0, t=0.7):
    """A wall of sandbags from (x, z) a to c."""
    dx, dz = c[0] - a[0], c[1] - a[1]
    ln = math.hypot(dx, dz)
    yaw = math.degrees(math.atan2(dx, dz))
    y0 = base_y((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
    b.box(((a[0] + c[0]) / 2, y0 + h / 2, (a[1] + c[1]) / 2), (t, h, ln), yaw=yaw, style=mb._nb("bk_sandbag"))
    b.box(((a[0] + c[0]) / 2, y0 + h + 0.07, (a[1] + c[1]) / 2), (t - 0.15, 0.14, ln - 0.2), yaw=yaw,
          style=mb._nb("bk_sandbag"))
    block((a[0] + c[0]) / 2, y0, (a[1] + c[1]) / 2, t, h, ln, yaw)


def wall_at(y, ang):
    """A point on the hall's wall at height y, in the direction `ang` (radians) from the middle."""
    C = LAY.C
    best = min(LAY.outline, key=lambda p: abs(math.remainder(math.atan2(p[1] - C[1], p[0] - C[0]) - ang, 2 * math.pi)))
    f = LAY.f_at(y) - 0.04
    return (C[0] + (best[0] - C[0]) * f, y, C[1] + (best[1] - C[1]) * f)


class Frame:
    """A bay's own axes: `out` from its back wall, `al` along it, y up."""

    def __init__(self, o, t, n, y0):
        self.o, self.t, self.n, self.y0 = o, t, n, y0
        self.yaw = math.degrees(math.atan2(-n[1], n[0]))              # a box's x runs out, its z along

    def P(self, out, y, al):
        return (self.o[0] + self.n[0] * out + self.t[0] * al, self.y0 + y, self.o[1] + self.n[1] * out + self.t[1] * al)

    def box(self, b, out, y, al, s_out, s_y, s_al, style, yaw=0.0):
        b.box(self.P(out, y, al), (s_out, s_y, s_al), yaw=self.yaw + yaw, style=style)


def sign_board(ctx, F, out, y, region, w=3.0, h=0.55, wires=True):
    """A sheet of tin with the bay's name painted on, facing out of the bay."""
    b = ctx.b
    F.box(b, out - 0.035, y, 0.0, 0.03, h, w, mb._solid("shed_metal"))      # (2 cm behind the paint)
    n = (F.n[0], 0.0, F.n[1])
    pts = [F.P(out, y - h / 2 + 0.03, -w / 2 + 0.04), F.P(out, y - h / 2 + 0.03, w / 2 - 0.04),
           F.P(out, y + h / 2 - 0.03, w / 2 - 0.04), F.P(out, y + h / 2 - 0.03, -w / 2 + 0.04)]
    b.poly(pts, n, "decals", ctx.d(region))
    if wires:
        for s in (-1, 1):
            pipe(b, F.P(out, y + h / 2, s * w * 0.4), F.P(out, y + 1.2, s * w * 0.3), "bk_cable", 0.015)


# ------------------------------------------------------------------------------------------------ the bays
def tin_side(b, F, rng, al, depth, mat, back=0.0):
    """A partition of corrugated sheets ~1 m wide on a tube frame, ragged along the top."""
    n = max(1, round((depth - back) / 1.0))
    w = (depth - back) / n
    for k in range(n):
        top = rng.uniform(2.2, 2.6)
        m = mat if rng.random() < 0.8 else rng.choice(TINS)
        F.box(b, back + w * (k + 0.5), top / 2, al + (0.03 if k % 2 else -0.03), w + 0.08, top, 0.03, mb._solid(m))
    for y in (0.3, 2.0):
        for s in (-1, 1):
            pipe(b, F.P(back, y, al + s * 0.07), F.P(depth, y, al + s * 0.07))


def bay(ctx, rng, i, entry):
    b = ctx.b
    bid, o, t, n, w, depth, y0, kind = entry
    F = Frame(o, t, n, y0)
    mat = TINS[i % len(TINS)]
    if kind == "tin":
        for s in (-1, 1):
            tin_side(b, F, rng, s * w / 2, depth, mat)
        sign_board(ctx, F, depth + 0.3, 3.1, "sign_" + bid, w=min(3.4, w - 0.6))
    elif kind == "cage":
        for s in (-1, 1):                                             # mesh panels on tubes
            for out in (0.1, depth):
                pipe(b, F.P(out, 0, s * w / 2), F.P(out, 2.4, s * w / 2))
            pipe(b, F.P(0.1, 2.4, s * w / 2), F.P(depth, 2.4, s * w / 2))
            F.box(b, depth / 2, 1.2, s * w / 2, depth - 0.1, 2.3, 0.02, mb._solid("bk_grate"))
        pipe(b, F.P(depth, 2.4, -w / 2), F.P(depth, 2.4, w / 2))
        sign_board(ctx, F, depth + 0.05, 2.75, "sign_" + bid, w=min(3.2, w - 0.6), wires=False)
    else:                                                             # a concrete bunker dug into the rock
        for s in (-1, 1):
            F.box(b, (depth - 3.0) / 2, 1.6, s * (w / 2 + 0.2), depth + 3.0, 3.2, 0.4, mb._nb("bk_old"))
            F.box(b, depth - 0.15, 0.5, s * (w / 2 + 0.2), 0.32, 1.0, 0.42, mb._solid("bk_hazard"))
        F.box(b, (depth - 3.0) / 2, 3.4, 0.0, depth + 3.0, 0.4, w + 0.8, mb._nb("bk_old"))
        F.box(b, depth + 0.02, 2.95, 0.0, 0.06, 0.5, w + 0.8, mb._nb("bk_old"))                     # lintel
        sign_board(ctx, F, depth + 0.08, 3.4, "sign_" + bid, w=min(3.4, w - 0.4), h=0.5, wires=False)
        for s in (-1, 1):                                             # steel door frame
            F.box(b, depth - 0.05, 1.5, s * (w / 2 - 0.05), 0.12, 3.0, 0.12, mb._solid("bk_iron"))
    mid = 0.0
    if bid in TRADERS:
        fx = depth - 0.5                                              # the counter: drums at the ends, crates between
        drum(b, *F.P(fx, 0, -w / 2 + 0.6)[0::2], y0, rng.choice(TINS))
        drum(b, *F.P(fx, 0, w / 2 - 0.6)[0::2], y0, rng.choice(TINS))
        k = -w / 2 + 0.9
        while k < w / 2 - 0.95:
            ww = min(rng.uniform(0.55, 0.8), w / 2 - 0.9 - k)
            p = F.P(fx, 0, k + ww / 2)
            crate(b, p[0], y0, p[2], 0.6, 0.85, ww - 0.04, yaw=F.yaw + rng.uniform(-3, 3),
                  mat=rng.choice(("olive", "olive_dark")))
            k += ww
        F.box(b, fx, 0.94, 0.0, 0.8, 0.04, w - 0.8, mb._solid("metal"))
        for y in (0.0, 0.9, 1.8):                                     # steel racking at the back, stocked
            F.box(b, 0.4, y + 0.86, mid, 0.7, 0.04, w - 1.0, mb._solid("metal"))
            for k in range(3):
                if rng.random() < 0.85:
                    p = F.P(0.4, y + 0.88, (k - 1) * (w - 1.4) / 3 + rng.uniform(-0.15, 0.15))
                    crate(b, p[0], p[1], p[2], 0.5, rng.uniform(0.25, 0.5), rng.uniform(0.4, 0.75),
                          yaw=F.yaw + rng.uniform(-6, 6), mat=rng.choice(("olive", "cardboard", "carton", "olive_dark")))
        for al in (-w / 2 + 0.6, w / 2 - 0.6):
            for out in (0.05, 0.75):
                pipe(b, F.P(out, 0, al), F.P(out, 2.75, al), "bk_iron", 0.06)
    elif bid == "stash":
        k = -w / 2 + 0.7
        while k < w / 2 - 0.6:                                        # lockers along the back
            p = F.P(0.5, 0, k)
            crate(b, p[0], y0, p[2], 0.8, rng.uniform(1.5, 1.9), 0.95, yaw=F.yaw,
                  mat=rng.choice(("olive", "olive_dark", "shed_metal")))
            k += 1.05
        block(*F.P(0.5, 0, 0.0), 1.0, 1.9, w - 0.6, F.yaw)
        for s in (-1, 1):
            p = F.P(depth - 0.8, 0, s * (w / 2 - 0.8))
            crate(b, p[0], y0, p[2], 0.9, 0.6, 0.7, yaw=F.yaw + rng.uniform(-10, 10), mat="olive")
    elif bid == "wardrobe":
        for al in (-w / 2 + 0.7, w / 2 - 0.7):
            pipe(b, F.P(0.6, 0, al), F.P(0.6, 1.9, al))
        pipe(b, F.P(0.6, 1.9, -w / 2 + 0.7), F.P(0.6, 1.9, w / 2 - 0.7))
        k = -w / 2 + 1.0
        while k < w / 2 - 0.9:                                        # jackets, smocks and rigs on hangers
            F.box(b, 0.6, 1.4, k, 0.5, 0.9, 0.12, mb._nb(rng.choice(("olive", "olive_dark", "bk_tarp", "bk_cable"))),
                  yaw=rng.uniform(-8, 8))
            k += rng.uniform(0.25, 0.4)
        F.box(b, depth - 1.2, 1.2, w / 2 - 0.6, 0.04, 1.0, 0.45, mb._solid("blue"))            # a mirror on a stand
        pipe(b, F.P(depth - 1.2, 0, w / 2 - 0.6), F.P(depth - 1.2, 0.7, w / 2 - 0.6))
        block(*F.P(0.6, 0, 0.0), 0.7, 1.9, w - 1.2, F.yaw)
    elif bid == "workbench":
        F.box(b, 0.5, 0.9, 0.0, 0.9, 0.06, min(3.2, w - 0.8), mb._solid("metal"))
        for al in (-1.4, 1.4):
            for out in (0.1, 0.9):
                pipe(b, F.P(out, 0, al), F.P(out, 0.88, al), "bk_iron", 0.06)
        F.box(b, 0.03, 1.8, 0.0, 0.04, 1.2, min(3.2, w - 0.8), mb._solid("shed_metal"))      # a sheet for tools
        for k in range(8):
            F.box(b, 0.07, rng.uniform(0.9, 1.6) + 0.5, -1.4 + k * 0.4, 0.03, rng.uniform(0.2, 0.45), 0.06,
                  mb._solid(rng.choice(("bk_iron", "trim_dark", "red"))))
        F.box(b, 0.5, 1.02, -1.0, 0.25, 0.16, 0.18, mb._nb("bk_iron"))                         # vice
        block(*F.P(0.5, 0, 0.0), 1.0, 1.0, 3.2, F.yaw)


# ------------------------------------------------------------------------------------------------ the model
def ledge(ctx):
    """The traders' rock ledge down the west side, steel stairs up from the floor, a tube rail along its edge."""
    b = ctx.b
    y = LAY.ledge_y
    back = min(p[0] for p in LAY.outline) - 2.0
    for (xa, za), (xb, zb) in zip(LAY.ledge, LAY.ledge[1:]):
        b.poly([(back, y, za), (xa, y, za), (xb, y, zb), (back, y, zb)], (0, 1, 0), "bk_ground", mb.uv_world())
        quad(b, [(xa, 0, za), (xb, 0, zb), (xb, y, zb), (xa, y, za)], (0.0, 1.0, (za + zb) / 2), "bk_rock")
    xe, ze = LAY.ledge[-1]
    b.poly([(back, 0, ze), (xe, 0, ze), (xe, y, ze), (back, y, ze)], (0, 0, 1), "bk_rock", mb.uv_world())
    (fx, fz), (tx, tz), w = LAY.stair
    c, s, yaw, pitch = ramp((fx, fz), (tx, tz), y, w)
    mb.stairs(ctx, c, s, yaw, pitch, mats=("bk_grate", "bk_iron"))
    for sd in (-1, 1):
        z = fz + sd * (w / 2 - 0.02)
        pipe(b, (fx, 1.0, z), (tx, y + 1.0, z))
        for k in (0.0, 0.5, 1.0):
            pipe(b, (fx + (tx - fx) * k, y * k, z), (fx + (tx - fx) * k, y * k + 1.0, z))
    for (xa, za), (xb, zb) in zip(LAY.ledge, LAY.ledge[1:]):
        if not (zb < fz - w / 2 - 0.1 or za > fz + w / 2 + 0.1):
            continue
        for yy in (0.55, 1.0):
            pipe(b, (xa - 0.1, y + yy, za), (xb - 0.1, y + yy, zb))
        pipe(b, (xa - 0.1, y, za), (xa - 0.1, y + 1.0, za))


def war_table(ctx):
    """An old steel door laid over drums, the map of Bloxov on it."""
    b, rng = ctx.b, random.Random("table")
    tx, tz = LAY.war_table
    for dx in (-2.0, 2.0):
        for dz in (-1.1, 1.1):
            drum(b, tx + dx, tz + dz, mat=rng.choice(("shed_metal", "bk_iron")))
    b.box((tx, 0.94, tz), (5.2, 0.05, 3.3), style=mb._solid("metal"))
    b.poly([(tx - 2.3, 0.985, tz - 1.4), (tx + 2.3, 0.985, tz - 1.4), (tx + 2.3, 0.985, tz + 1.4), (tx - 2.3, 0.985, tz + 1.4)],
           (0, 1, 0), "decals", ctx.d("map"))
    for _ in range(5):                                                 # ammo tins and a radio holding the map down
        b.box((tx + rng.uniform(-2.3, 2.3), 1.05, tz + rng.choice((-1.45, 1.45))), (0.3, 0.16, 0.15),
              yaw=rng.uniform(0, 90), style=mb._nb(rng.choice(("olive", "olive_dark", "bk_iron"))))
    for k in range(4):                                                 # crates to sit on
        a = math.radians(30 + k * 90)
        crate(b, tx + math.cos(a) * 3.4, 0.0, tz + math.sin(a) * 2.6, 0.5, 0.45, 0.5, yaw=k * 20.0)
        block(tx + math.cos(a) * 3.4, 0.0, tz + math.sin(a) * 2.6, 0.5, 0.5, 0.5, k * 20.0)   # (you walked through them)


def shooting_range(ctx):
    b = ctx.b
    t = LAY.tunnels[0]
    fl = t.a0 - FIRING_BACK
    # The firing line: sandbag rests, a steel top.
    for u, w in ((-2.0, 1.6), (0.0, 1.6), (2.0, 1.6)):
        p = t.P(u, 0, fl)
        b.box((p[0], 0.45, p[2]), (w, 0.9, 0.6), yaw=t.yaw(), style=mb._nb("bk_sandbag"))
        b.box((p[0], 0.93, p[2]), (w + 0.1, 0.05, 0.7), yaw=t.yaw(), style=mb._solid("metal"))
        block(p[0], 0.0, p[2], w, 0.95, 0.6, t.yaw())
    p = t.P(0, 0, t.a1 - 1.3)
    b.box((p[0], 1.2, p[2]), (2 * t.hw, 2.4, 2.4), style=mb._nb("bk_sandbag"))                # the backstop
    for d, u in zip(TARGETS, TARGET_U):                                # a stand and a distance sign for each target
        p = t.P(u, 0, fl + d)
        pipe(b, (p[0], 0.0, p[2]), (p[0], 1.1, p[2]), "bk_iron", 0.08)
        F = Frame((p[0], p[2]), t.U, (-t.D[0], -t.D[1]), 0.0)
        sign_board(ctx, F, 0.0, 2.25, "sign_d%d" % d, w=1.0, h=0.4, wires=False)
        pipe(b, F.P(-0.02, 0.0, 0.6), F.P(-0.02, 2.45, 0.6), "bk_iron", 0.05)
    if SHAPE == "cave":                                                # the old mine's rails, on steel sleepers
        a = t.a0 + 0.5
        while a < t.a1 - 3.0:
            p, q = t.P(-0.9, 0.04, a), t.P(0.9, 0.04, a)
            pipe(b, p, q, "bk_iron", 0.08)
            a += 1.2
        for u in (-0.55, 0.55):
            pipe(b, t.P(u, 0.1, t.a0 + 0.3), t.P(u, 0.1, t.a1 - 3.0), "metal", 0.07)
        p = t.P(1.8, 0, t.a0 + 6.0)                                    # an old mine cart, pushed to the side
        b.box((p[0], 0.6, p[2]), (1.0, 0.7, 1.4), style=mb._nb("cabin_tin_d"))
        block(p[0], 0.0, p[2], 1.0, 1.0, 1.4)


def mess(ctx):
    """Canteen tables (steel, benches both sides), a drum stove, water."""
    b, rng = ctx.b, random.Random("mess")
    mx, mz = LAY.mess
    along_z = SHAPE == "post"
    for k in (-1, 0, 1):
        if along_z:
            x, z, yaw = mx + k * 2.6, mz, 0.0
        else:
            x, z, yaw = mx + k * 0.3, mz + k * 2.2, 90.0
        b.box((x, 0.76, z), (0.8, 0.04, 2.6), yaw=yaw, style=mb._solid("metal"))
        for s in (-0.95, 0.95):
            off = mb.rot((s, 0, 0), yaw, 0)
            b.box((x + off[0], 0.44, z + off[2]), (0.3, 0.04, 2.6), yaw=yaw, style=mb._solid("metal"))
            for e in (-1.1, 1.1):
                o2 = mb.rot((s, 0, e), yaw, 0)
                pipe(b, (x + o2[0], 0, z + o2[2]), (x + o2[0], 0.42, z + o2[2]), "bk_iron", 0.05)
        for e in (-1.1, 1.1):
            o2 = mb.rot((0, 0, e), yaw, 0)
            pipe(b, (x + o2[0] - 0.3, 0, z + o2[2]), (x + o2[0] - 0.3, 0.74, z + o2[2]), "bk_iron", 0.06)
            pipe(b, (x + o2[0] + 0.3, 0, z + o2[2]), (x + o2[0] + 0.3, 0.74, z + o2[2]), "bk_iron", 0.06)
        block(x, 0.0, z, 2.6 if yaw else 0.8, 0.78, 0.8 if yaw else 2.6)
        for side in (-0.95, 0.95):                                     # the benches stop you too
            off = mb.rot((side, 0, 0), yaw, 0)
            block(x + off[0], 0.0, z + off[2], 0.3, 0.46, 2.6, yaw)
        for _ in range(3):                                             # mess tins and mugs
            o2 = mb.rot((rng.uniform(-0.25, 0.25), 0, rng.uniform(-1.1, 1.1)), yaw, 0)
            b.box((x + o2[0], 0.81, z + o2[2]), (0.14, 0.06, 0.2), yaw=rng.uniform(0, 90), style=mb._nb("metal"))
    kx, kz, kyaw = LAY.kitchen
    k = mb.rot((0, 0, 1.0), kyaw, 0)
    b.box((kx, 0.85, kz), (0.8, 0.04, 2.6), yaw=kyaw, style=mb._solid("metal"))
    for e in (-1.0, 1.0):
        crate(b, kx + k[0] * e, 0.0, kz + k[2] * e, 0.7, 0.83, 0.6, yaw=kyaw, mat="olive_dark")
    block(kx, 0.0, kz, 0.8, 0.9, 2.6, kyaw)
    sx, sz = kx + k[0] * 2.3, kz + k[2] * 2.3
    drum(b, sx, sz, mat="bk_iron")                                     # the stove, its pipe up into the rock
    pipe(b, (sx, 0.9, sz), (sx, 4.5, sz), "bk_iron", 0.1)
    b.box((sx, 0.98, sz), (0.3, 0.16, 0.3), style=mb._nb("metal"))    # a pot
    drum(b, kx - k[0] * 2.3, kz - k[2] * 2.3, mat="shed_metal")       # water
    block(kx - k[0] * 2.3, 0.0, kz - k[2] * 2.3, 0.6, 0.95, 0.6)
    block(sx, 0.0, sz, 0.6, 1.0, 0.6)


def bunks(ctx):
    """Tube-frame bunk beds with olive mattresses."""
    b, rng = ctx.b, random.Random("bunks")
    for bx, bz, yaw in LAY.bunk_list:
        r = lambda x, z: mb.rot((x, 0, z), yaw, 0)                    # noqa: E731
        for y in (0.45, 1.65):
            b.box((bx, y, bz), (0.9, 0.12, 2.0), yaw=yaw, style=mb._nb("olive_dark"))
            p = r(0, 0.6)
            b.box((bx + p[0], y + 0.13, bz + p[2]), (0.5, 0.12, 0.35), yaw=yaw + rng.uniform(-8, 8), style=mb._nb("bone"))
        for dx in (-0.45, 0.45):
            for dz in (-1.0, 1.0):
                p = r(dx, dz)
                pipe(b, (bx + p[0], 0, bz + p[2]), (bx + p[0], 2.2, bz + p[2]))
        # (0.25.15, owner: "make sure we can jump on the top bunk"): the bunk collides up to its top mattress, so you
        # can stand up there; the posts above it don't (5 cm tubes)
        block(bx, 0.0, bz, 0.9, BUNK_TOP, 2.0, yaw)
        if (bx, bz) == CLIMB_BUNK:
            # Two jumps' worth of steps at its foot (the hideout's walker jumps ~1 m, no climbing): a footlocker, then
            # two ammo crates stacked, then the top bunk.
            p = r(0.0, -1.3)
            for k, (sx, sy) in enumerate(((0.6, 0.55), (0.56, 0.55))):
                crate(b, bx + p[0], k * 0.55, bz + p[2], sx, sy, 0.56, yaw=yaw + (0.0, 4.0)[k], mat="olive")
            block(bx + p[0], 0.0, bz + p[2], 0.6, 1.12, 0.6, yaw)
            p = r(0.0, -1.95)
            crate(b, bx + p[0], 0.0, bz + p[2], 0.6, 0.44, 0.56, yaw=yaw, mat="olive")   # the footlocker
            block(bx + p[0], 0.0, bz + p[2], 0.6, 0.46, 0.6, yaw)
            continue
        p = r(0.0, -1.35)
        crate(b, bx + p[0], 0.0, bz + p[2], 0.5, 0.4, 0.4, yaw=yaw, mat="olive")   # a footlocker


def washroom(ctx):
    """Its walls: corrugated tin on tubes, a gap for the door; the fittings come from the gray boxes."""
    b, rng = ctx.b, random.Random("wc")
    x0, z0, x1, z1 = LAY.wc
    door = (x0 + x1) / 2
    for a, c in (((x0, z0), (x0, z1)), ((x1, z0), (x1, z1)), ((x0, z0), (door - 0.45, z0)), ((door + 0.45, z0), (x1, z0))):
        ln = math.hypot(c[0] - a[0], c[1] - a[1])
        yaw = math.degrees(math.atan2(c[0] - a[0], c[1] - a[1]))
        b.box(((a[0] + c[0]) / 2, 1.3, (a[1] + c[1]) / 2), (0.04, 2.6, ln), yaw=yaw, style=mb._solid("shed_metal"))
        pipe(b, (a[0], 2.6, a[1]), (c[0], 2.6, c[1]))
    b.box(((x0 + x1) / 2, 2.62, (z0 + z1) / 2), (x1 - x0, 0.04, z1 - z0), style=mb._solid("cabin_tin_d"))
    b.box((door, 2.3, z0 - 0.03), (0.9, 0.6, 0.02), style=mb._solid("shed_metal"))


def shower_block(ctx):
    """The washroom (owner 2026-10-25: not "just some metal box"): the end of the tunnel tiled to head height, open to
    the bunks. Two toilet cubicles in block walls with tarp curtains on the left, a long steel trough with taps and
    shaving mirrors along the back, two showers behind a curtain on the right, towels, a drain, its own lamps."""
    b, rng = ctx.b, random.Random("showers")
    x0, z0, x1, z1 = LAY.wc
    tiles = mb.uv_world(mb.TILE_M, (0.0, 0.0))
    b.poly([(x0, 0.012, z0), (x1, 0.012, z0), (x1, 0.012, z1), (x0, 0.012, z1)], (0, 1, 0), "wc_floor", mb.uv_world(1.0))
    b.poly([(x1, 0.0, z1), (x0, 0.0, z1), (x0, 2.1, z1), (x1, 2.1, z1)], (0, 0, -1), "wc_tile", tiles)
    for x, n in ((x0, 1), (x1, -1)):
        b.poly([(x, 0.0, z0), (x, 0.0, z1), (x, 2.1, z1), (x, 2.1, z0)][::n], (n, 0, 0), "wc_tile", tiles)
    # The cubicles: block walls 2 m tall, a tarp hung across each doorway on a pipe.
    cub_w = 1.6
    for k in range(2):
        za, zb = z1 - k * cub_w - cub_w, z1 - k * cub_w
        b.box((x0 + 0.85, 1.0, za - 0.06), (1.7, 2.0, 0.12), style=mb._nb("bk_old"))   # the wall in front of each
        block(x0 + 0.85, 0.0, za - 0.06, 1.7, 2.0, 0.12)
        toilet(b, x0 + 0.05, (za + zb) / 2, 90.0)
        pipe(b, (x0 + 1.7, 2.0, za), (x0 + 1.7, 2.0, zb), "bk_iron", 0.03)
        open_part = rng.uniform(0.3, 0.6)
        sheet((x0 + 1.72, 1.15, za + (zb - za) * open_part / 2 + 0.02), (zb - za) * open_part, 1.7, 90.0,
              "bk_tarp" if k == 0 else "olive")
    b.box((x0 + 1.77, 1.0, z1 - 2 * cub_w - 0.06), (0.12, 2.0, 0.12), style=mb._nb("bk_old"))
    # The trough: a steel trough on brackets along the back, three taps, three steel mirrors, soap, a razor.
    tx0, tx1 = x0 + 2.1, x1 - 2.3
    tz = z1 - 0.3
    b.box(((tx0 + tx1) / 2, 0.8, tz), (tx1 - tx0, 0.22, 0.5), style=mb._nb("metal"))
    b.box(((tx0 + tx1) / 2, 0.915, tz + 0.02), (tx1 - tx0 - 0.1, 0.012, 0.36), style=mb._solid("trim_dark"))
    pipe(b, (tx0, 1.3, z1 - 0.06), (tx1, 1.3, z1 - 0.06), "bk_iron", 0.04)            # the water pipe
    for k in range(3):
        x = tx0 + (k + 0.5) * (tx1 - tx0) / 3
        pipe(b, (x, 1.3, z1 - 0.06), (x, 1.05, z1 - 0.2), "bk_iron", 0.025)           # a tap
        b.box((x, 1.6, z1 - 0.02), (0.36, 0.44, 0.02), style=mb._solid("steel_light"))  # a mirror
        b.box((x + 0.25, 0.94, tz - 0.12), (0.08, 0.04, 0.06), style=mb._nb(rng.choice(("bone", "green", "red"))))
    for x in (tx0 + 0.1, tx1 - 0.1):
        pipe(b, (x, 0.0, tz), (x, 0.7, tz), "bk_iron", 0.05)
    block((tx0 + tx1) / 2, 0.0, tz, tx1 - tx0, 0.95, 0.5)
    # The showers: two heads off a pipe, a rail and a curtain partly drawn, a drain, a mat, towels on hooks.
    sx = x1 - 1.0
    for k, sz in enumerate((z1 - 0.8, z1 - 2.3)):
        pipe(b, (x1 - 0.05, 2.25, sz), (sx + 0.2, 2.25, sz), "steel_light", 0.03)
        b.box((sx + 0.2, 2.18, sz), (0.16, 0.06, 0.16), style=mb._nb("steel_light"))
        pipe(b, (x1 - 0.05, 1.2, sz - 0.25), (x1 - 0.05, 1.35, sz - 0.25), "steel_light", 0.04)   # the valve
        b.box((sx + 0.2, 0.016, sz), (0.2, 0.01, 0.2), style=mb._solid("trim_dark"))  # the drain
    pipe(b, (x1 - 2.0, 2.3, z1 - 3.1), (x1 - 2.0, 2.3, z1), "bk_iron", 0.03)          # curtain rail
    sheet((x1 - 2.0, 1.25, z1 - 2.6), 1.0, 1.9, 90.0, "blue")
    sheet((x1 - 2.0, 1.25, z1 - 0.5), 0.9, 1.9, 90.0, "blue")
    b.box((x1 - 2.4, 0.016, z1 - 1.6), (0.6, 0.008, 1.0), style=mb._solid("rubber"))  # a mat
    # A short block wall closing the showers off from the bunks, towels hung on its inside.
    b.box((x1 - 1.4, 1.0, z0 + 0.06), (2.0, 2.0, 0.12), style=mb._nb("bk_old"))
    block(x1 - 1.4, 0.0, z0 + 0.06, 2.0, 2.0, 0.12)
    for k in range(3):
        x = x1 - 0.7 - k * 0.6
        b.box((x, 1.45, z0 + 0.15), (0.4, 0.6, 0.04), yaw=rng.uniform(-4, 4),
              style=mb._solid(rng.choice(("bone", "olive", "blue", "red"))))
        pipe(b, (x, 1.78, z0 + 0.12), (x, 1.78, z0 + 0.2), "bk_iron", 0.02)
    for x in (-2.2, 2.2):                                             # its own lamps
        hang((x, 2.6, (z0 + z1) / 2), 2.0, 0.9, 3.4, shaded=True)
    # A sign over it all.
    F = Frame((0.0, z1), (1.0, 0.0), (0.0, -1.0), 0.0)
    sign_board(ctx, F, 0.05, 2.55, "sign_wc", w=2.2, h=0.4, wires=False)


def toilet(b, x, z, yaw):
    """A white toilet with its back at (x, z), facing yaw (degrees, 0 = +z)."""
    r = lambda o, s: mb.rot((s, 0, o), yaw, 0)                         # noqa: E731 (o out from the wall, s sideways)
    for (o, s), y, size, mat in (((0.1, 0), 0.6, (0.44, 0.4, 0.2), "bone"), ((0.1, 0), 0.82, (0.47, 0.04, 0.23), "bone"),
                                 ((0.36, 0), 0.17, (0.26, 0.34, 0.34), "bone"), ((0.44, 0), 0.37, (0.38, 0.08, 0.5), "bone"),
                                 ((0.46, 0), 0.415, (0.26, 0.012, 0.32), "trim_dark"), ((0.45, 0), 0.43, (0.4, 0.03, 0.46), "trim_dark")):
        p = r(o, s)
        b.box((x + p[0], y, z + p[2]), size, yaw=yaw, style=mb._nb(mat))
    p = r(0.4, 0)
    block(x + p[0], 0.0, z + p[2], 0.5, 0.85, 0.8, yaw)


def dress_props(ctx):
    """Sandbags, duffel bags, crates, drums, rocks, the generator: the stuff of a camp."""
    b, rng = ctx.b, random.Random("props")
    for a, c in LAY.sandbags:
        sandbag_wall(b, a, c)
    for x, z, n in LAY.duffels:
        duffels(b, x, z, n, rng, base_y(x, z))
    for cx, cz in LAY.crates:                                          # stacks of crates
        y = base_y(cx, cz)
        for k in range(rng.randrange(3, 6)):
            crate(b, cx + rng.uniform(-0.8, 0.8), y, cz + rng.uniform(-0.5, 0.5), rng.uniform(0.6, 1.0),
                  rng.uniform(0.4, 0.8), rng.uniform(0.6, 1.0), yaw=rng.uniform(-20, 20),
                  mat=rng.choice(("olive", "olive_dark", "cardboard")))
        block(cx, y, cz, 2.2, 0.8, 1.6)
        drum(b, cx + 1.5, cz + 0.3, y, mat=rng.choice(TINS))
        block(cx + 1.5, y, cz + 0.3, 0.6, 0.95, 0.6)
    gx, gz = LAY.generator                                             # the generator, its cable off along the floor
    b.box((gx, 0.5, gz), (1.8, 1.0, 0.9), style=mb._nb("cabin_tin_d"))
    b.box((gx, 1.05, gz), (1.9, 0.1, 1.0), style=mb._solid("bk_iron"))
    pipe(b, (gx + 0.8, 1.1, gz), (gx + 0.8, 2.6, gz), "bk_iron", 0.12)
    pipe(b, (gx - 0.9, 0.03, gz), (LAY.war_table[0] - 2.5, 0.03, LAY.war_table[1] + 1.0), "bk_cable", 0.04)
    block(gx, 0.0, gz, 1.9, 1.1, 1.0)
    if SHAPE == "cave":                                                # rocks fallen along the walls
        C = LAY.C
        for k, (x, z) in enumerate(LAY.outline[::5]):
            if any(abs(x - ex) < ew and abs(z - ez) < ed for ex, ez, ew, ed in LAY.keep_clear):
                continue
            f = rng.uniform(0.88, 0.94)
            px, pz = C[0] + (x - C[0]) * f, C[1] + (z - C[1]) * f
            s = (rng.uniform(0.7, 1.6), rng.uniform(0.5, 1.2), rng.uniform(0.7, 1.6))
            mb.rubble_chunk(b, (px, base_y(px, pz) + s[1] * 0.35, pz), s, rng, ["bk_rock"])
            block(px, base_y(px, pz), pz, s[0] * 0.8, s[1] * 0.8, s[2] * 0.8)


def pillars(ctx):
    """Rock columns the diggers left standing, flared where they meet floor and roof, steel bands round them."""
    b = ctx.b
    for k, (x, z, r) in enumerate(LAY.pillars):
        rng = random.Random("pillar%d" % k)
        ys = [0.0, 0.6, 1.5, 2.6, 3.8, 5.0, 6.3, 7.6, 9.0, 10.5, 12.0]
        rings = []
        for y in ys:
            flare = 1.0 + 0.6 * max(0.0, 1.0 - y / 1.5) ** 2 + 0.9 * max(0.0, (y - 6.0) / 6.0) ** 2
            rings.append([(x + math.cos(a) * r * flare * rng.uniform(0.85, 1.15), y,
                           z + math.sin(a) * r * flare * rng.uniform(0.85, 1.15))
                          for a in (2 * math.pi * i / 9 for i in range(9))])
        for ra, rb in zip(rings, rings[1:]):
            for i in range(9):
                j = (i + 1) % 9
                quad(b, [ra[i], ra[j], rb[j], rb[i]], (x, (ra[i][1] + rb[i][1]) / 2, z), "bk_rock", away=True)
        for y in (1.9, 2.15):                                          # steel bands, a lamp hook
            b.box((x, y, z), (r * 2.05, 0.08, r * 2.05), yaw=k * 17.0, style=mb._solid("bk_iron"))
        block(x, 0.0, z, r * 2.0, 3.0, r * 2.0)


def boards(ctx):
    """The jobs board and the record board: freestanding steel sheets on posts, a tin awning with a bulb under it,
    the sign on top, a couple of crates in front. The hideout writes what's on them (current quests, your record)."""
    b, rng = ctx.b, random.Random("boards")
    for bid, (x, z), (nx, nz) in LAY.boards:
        F = Frame((x, z), (-nz, nx), (nx, nz), base_y(x, z))
        w = BOARD_W
        F.box(b, 0.0, BOARD_Y, 0.0, 0.08, BOARD_H, w, mb._solid("shed_metal"))
        F.box(b, -0.02, BOARD_Y, 0.0, 0.06, BOARD_H + 0.12, w + 0.12, mb._solid("bk_iron"))       # a steel rim
        for s in (-1, 1):
            pipe(b, F.P(0.0, 0, s * (w / 2 + 0.1)), F.P(0.0, 2.95, s * (w / 2 + 0.1)), "bk_iron", 0.08)
            pipe(b, F.P(-0.6, 0, s * (w / 2 + 0.1)), F.P(0.0, 1.4, s * (w / 2 + 0.1)), "bk_iron", 0.06)  # a brace
        F.box(b, 0.35, 2.85, 0.0, 0.9, 0.04, w + 0.6, mb._solid("cabin_tin_d"))                     # the awning
        sign_board(ctx, F, 0.08, 3.1, "sign_" + bid, w=2.2, h=0.45, wires=False)
        for k in range(4):                                             # a few notes pinned round the edge
            F.box(b, 0.06, BOARD_Y + BOARD_H / 2 - 0.25 - k * 0.12 * (k % 2), (w / 2 - 0.25) * (1 if k < 2 else -1),
                  0.01, 0.3, 0.24, mb._solid("bone"), yaw=rng.uniform(-6, 6))
        p = F.P(0.55, 2.75, 0.0)
        bulb(b, p[0], p[1], p[2], strength=1.0, reach=3.6)
        for s in (-1, 1):                                              # crates to sit on, a drum with a radio
            p = F.P(2.0, 0, s * 1.2)
            crate(b, p[0], F.y0, p[2], 0.5, 0.45, 0.5, yaw=F.yaw + rng.uniform(-15, 15),
                  mat=rng.choice(("olive", "olive_dark")))
            block(p[0], F.y0, p[2], 0.5, 0.5, 0.5, F.yaw)
        p = F.P(0.6, 0, w / 2 + 0.8)
        drum(b, p[0], p[2], F.y0, mat="shed_metal")
        b.box((p[0], F.y0 + 1.02, p[2]), (0.32, 0.18, 0.16), yaw=F.yaw + 20, style=mb._nb("bk_iron"))
        block(p[0], F.y0, p[2], 0.6, 0.95, 0.6)
        q = F.P(-0.1, 0, 0.0)
        block(q[0], F.y0, q[2], 0.8, 3.0, w + 0.4, F.yaw)


def quarters(ctx):
    """The mess and bunk tunnel lived in (owner 2026-10-25: it looked "so dead and awkward"; the hideout should be fun
    to hang round in late at night): lamps over the tables and dinner left on them, a corner with a couch and an old
    TV, reading lamps and kit on the bunks, washing hung up, a sink by the washroom, notices on the walls."""
    b, rng = ctx.b, random.Random("quarters")
    mx, mz = LAY.mess
    for k in (-1, 0, 1):                                               # a lamp over each table, the dinner left out
        x, z = mx + k * 0.3, mz + k * 2.2
        hang((x, 2.42, z), 5.6 - 2.42, 0.9, 3.4, shaded=True)          # (0.22.0: it swings, a tin shade over it)
        for _ in range(4):
            px, pz = x + rng.uniform(-1.1, 1.1), z + rng.choice((-0.22, 0.22))
            b.box((px, 0.785, pz), (0.22, 0.012, 0.22), yaw=rng.uniform(0, 90), style=mb._solid("bone"))   # a plate
            KICKS.append((px + 0.18, 0.78, pz, 0.0, 2, KICK_COLOURS[rng.choice(("red", "blue", "metal"))]))   # a can
        if k == 0:                                                     # a card game, and a bottle
            for c in range(6):
                b.box((x + rng.uniform(-0.4, 0.4), 0.784 + c * 0.001, z + rng.uniform(-0.1, 0.1)), (0.06, 0.004, 0.09),
                      yaw=rng.uniform(0, 180), style=mb._solid("bone"))
            KICKS.append((x - 0.6, 0.78, z, 0.0, 3, KICK_COLOURS["green"]))
    # The corner: a couch facing an old TV on crates against the wall, a rug, a crate for a table.
    zc = mz + 5.2
    b.poly([(-4.1, 0.012, zc - 1.4), (-1.0, 0.012, zc - 1.4), (-1.0, 0.012, zc + 1.4), (-4.1, 0.012, zc + 1.4)], (0, 1, 0),
           "carpet", mb.uv_world())
    cx = -1.5
    b.box((cx, 0.22, zc), (0.85, 0.44, 2.1), style=mb._nb("bk_tarp"))                  # seat
    b.box((cx + 0.33, 0.7, zc), (0.22, 0.6, 2.1), style=mb._nb("bk_tarp"))             # back
    for s in (-1, 1):
        b.box((cx, 0.55, zc + s * 1.0), (0.85, 0.3, 0.18), style=mb._nb("olive_dark"))  # arms
    for s in (-0.5, 0.5):
        b.box((cx - 0.05, 0.5, zc + s), (0.6, 0.12, 0.9), yaw=rng.uniform(-4, 4), style=mb._nb("olive"))   # cushions
    block(cx, 0.0, zc, 0.9, 0.9, 2.1)
    crate(b, -2.6, 0.0, zc, 0.6, 0.38, 0.8, mat="olive_dark")                       # the table, a radio and mugs
    b.box((RADIO[0], 0.5, RADIO[1]), (0.3, 0.16, 0.14), style=mb._nb("bk_iron"))     # the radio: dial, knob, aerial
    b.box((RADIO[0] + 0.06, 0.52, RADIO[1] - 0.075), (0.12, 0.06, 0.01), style=mb._solid("bone"))
    b.box((RADIO[0] - 0.08, 0.5, RADIO[1] - 0.08), (0.04, 0.04, 0.03), style=mb._nb("red"))
    pipe(b, (RADIO[0] - 0.1, 0.58, RADIO[1] + 0.03), (RADIO[0] - 0.22, 0.95, RADIO[1] + 0.05), "steel_light", 0.006)
    b.box((-2.5, 0.46, zc - 0.25), (0.08, 0.1, 0.08), style=mb._nb("red"))
    block(-2.6, 0.0, zc, 0.6, 0.45, 0.8)
    crate(b, -4.0, 0.0, zc - 0.4, 0.6, 0.7, 0.6, mat="olive")                       # the TV on crates
    crate(b, -4.0, 0.0, zc + 0.4, 0.6, 0.7, 0.6, mat="olive_dark")
    b.box((-3.95, 1.05, zc), (0.5, 0.6, 0.7), style=mb._nb("trim_dark"))
    b.group = bake_light.GLOW
    mb._bx(b, -3.69, 1.05, zc, 0.01, 0.42, 0.56, "blue", bottom=True)
    b.group = None
    LAMPS.append((-3.4, 1.05, zc, 0.5, 2.4))
    pipe(b, (-3.9, 1.35, zc), (-3.8, 1.75, zc - 0.25), "bk_iron", 0.01)                # rabbit ears
    pipe(b, (-3.9, 1.35, zc), (-3.8, 1.75, zc + 0.25), "bk_iron", 0.01)
    block(-4.0, 0.0, zc, 0.7, 1.4, 1.3)
    # The bunks: a reading lamp clipped to each, a blanket roll and kit on the top ones.
    for bx, bz, yaw in LAY.bunk_list:
        r = lambda x, z: mb.rot((x, 0, z), yaw, 0)                    # noqa: E731
        p = r(0.45, 0.95)
        bulb(b, bx + p[0], 1.3, bz + p[2], 0.45, 1.8)
        p = r(0.0, -0.6)
        b.box((bx + p[0], 1.82, bz + p[2]), (0.7, 0.2, 0.25), yaw=yaw, style=mb._nb(rng.choice(("bk_tarp", "olive", "red"))))
        if rng.random() < 0.6:
            duffel(b, bx, 1.71, bz + rng.uniform(-0.3, 0.3), yaw + rng.uniform(-10, 10), rng)
        p = r(0.0, -0.4)
        b.box((bx + p[0], 0.58, bz + p[2]), (0.75, 0.1, 0.6), yaw=yaw, style=mb._nb(rng.choice(("bk_tarp", "olive", "blue"))))
    # Fairy lights zigzagging over the bunks (they stay on when the bunks' lights go off).
    n0 = len(LAMPS)
    for a, c in (((-4.2, 2.9, 25.6), (4.2, 2.9, 28.4)), ((4.2, 2.9, 28.4), (-4.2, 2.9, 31.6))):
        string_lights(b, a, c, sag=0.35, every=0.9, strength=0.25, reach=2.2)
    DARK_GLOWS[:] = [lamp[:3] for lamp in LAMPS[n0:]]
    # The dartboard on a plywood backboard, a tape line on the floor to throw from.
    x, y, z = DARTBOARD
    b.box((x - 0.035, y, z), (0.03, 0.62, 0.62), style=mb._nb("wood"))
    b.box((x - 0.005, y, z), (0.03, 0.46, 0.46), style=mb._nb("black"))
    b.poly([(x + 0.012, y - 0.225, z + 0.225), (x + 0.012, y - 0.225, z - 0.225), (x + 0.012, y + 0.225, z - 0.225),
            (x + 0.012, y + 0.225, z + 0.225)], (1, 0, 0), "decals", ctx.d("dartboard"))
    b.box((DART_LINE, 0.006, z), (0.05, 0.012, 0.8), style=mb._solid("yellow"))
    # The bunks' light switch: a box on the wall, its cable up to the lamps.
    x, y, z = SWITCH
    b.box((x - 0.03, y, z), (0.06, 0.2, 0.12), style=mb._nb("bk_iron"))
    b.box((x - 0.07, y + 0.03, z), (0.04, 0.03, 0.03), style=mb._nb("red"))
    pipe(b, (x - 0.02, y + 0.1, z), (x - 0.02, 2.9, z), "bk_cable", 0.012)
    # Washing hung up across the tunnel.
    zl = 30.9
    pipe(b, (-4.3, 2.35, zl), (4.3, 2.35, zl), "bk_cable", 0.012)
    for k in range(7):
        x = -3.4 + k * 1.1 + rng.uniform(-0.2, 0.2)
        sheet((x, 2.0, zl), 0.5, 0.65, rng.uniform(-6, 6), rng.choice(("olive", "olive_dark", "bone", "bk_tarp", "blue")))
    # Notices on the walls.
    for bid, z, side in (("lights", 23.0, -1), ("chow", 23.6, 1), ("clean", 31.7, 1)):
        t = LAY.tunnels[3]
        x = side * (t.hw - 0.02)
        F = Frame((x, z), (0.0, 1.0), (-side, 0.0), 0.0)
        b.poly([F.P(0.0, 1.55, -0.6), F.P(0.0, 1.55, 0.6), F.P(0.0, 1.8, 0.6), F.P(0.0, 1.8, -0.6)],
               (-side, 0.0, 0.0), "decals", ctx.d("sign_" + bid))


LAMPS = []          # (x, y, z, strength, reach) for the light bake
SWINGS = []         # (top x, y, z, cable length, shaded) of the lamps that swing (scripts/swing_lamps.gd draws them)
CLOTH = []          # (centre, width, height, yaw, colour) of the curtains and washing that sway (scripts/cloth.gd)
KICKS = []          # (x, y, z, yaw, kind, colour) of the cans and bottles you can knock about (scripts/kickables.gd)
KICK_COLOURS = {"red": "b03a2e", "blue": "3e6d8c", "metal": "9aa1a6", "green": "3f6b3a"}
CLOTH_COLOURS = {"bk_tarp": "6b6a4c", "olive": "5b6236", "olive_dark": "3d4228", "bone": "e2dccb", "blue": "3e6d8c"}


def hangout(ctx):
    """The den past the range (0.25.17; owner on the first look: "make this area more fun, doesn't need to be cave
    like... blend in to the cave but get creative"): the PMCs fitted the old mine chamber out as a lounge. Rock above,
    but walled in to head height with painted tin, a black and white tiled floor, a snack bar with stools, a
    glowing SNACKS sign, two arcade cabinets, the pool table under its lamp, the jukebox, a couch on a rug, string lights.
    No wood (owner): steel, tin and tarp. Glowing bits are baked bright (bake_light.GLOW)."""
    b = ctx.b
    H = LAY.hang
    t = H.down
    t.draw(ctx)
    # Steel stairs down the passage (you walk the smooth ramp under them), bulbs along its roof.
    hi, lo = t.P(0, 0, t.a1 - 0.3), t.P(0, 0, t.a0 + 0.4)
    c, sz, yaw, pitch = ramp((lo[0], lo[2]), (hi[0], hi[2]), hi[1] - lo[1], 2 * t.hw - 0.1)
    step = (hi[1] - lo[1]) / max(2, round((hi[1] - lo[1]) / 0.2))      # (half a step up: each tread's back edge
    n_solid = len(mb.SOLIDS)
    mb.stairs(ctx, (c[0], c[1] + lo[1] + step / 2, c[2]), sz, yaw, pitch, mats=("bk_grate", "bk_iron"))  # meets the floor)
    del mb.SOLIDS[n_solid:]        # (0.25.35: the bottom treads got boxes of their own, and you stuck on them)
    for f in (0.2, 0.55, 0.88):
        a = t.a0 + (t.a1 - t.a0) * f
        p = t.P(0, t.crown - 0.35, a)
        pipe(b, p, t.P(0, t.crown, a), "bk_cable", 0.015)
        bulb(b, p[0], p[1], p[2], 0.6, 2.6)
    pipe(b, t.P(0, t.crown - 0.06, t.a0), t.P(0, t.crown - 0.06, t.a1), "bk_cable", 0.03)
    # The den: drawn in its plan frame, then moved (turned and lowered) into place with all it adds to the lists.
    marks = (len(b.verts), len(b.faces), len(LAMPS), len(SWINGS), len(KICKS), len(EXTRA), len(mb.SOLIDS), len(CLOTH))
    DOORS.clear()
    den(ctx)
    DOORS[:] = [H.w((x, 0.0, z))[::2] + (ln, yaw + H.turn) for x, z, ln, yaw in DOORS]
    b.verts[marks[0]:] = [H.w(v) for v in b.verts[marks[0]:]]
    b.normals[marks[1]:] = [H.wn(n) for n in b.normals[marks[1]:]]
    vn = getattr(b, "vnormals", None)
    if vn:
        vn[marks[1]:] = [[H.wn(n) for n in row] if row else row for row in vn[marks[1]:]]
    LAMPS[marks[2]:] = [H.w(l[:3]) + tuple(l[3:]) for l in LAMPS[marks[2]:]]
    SWINGS[marks[3]:] = [H.w(l[:3]) + tuple(l[3:]) for l in SWINGS[marks[3]:]]
    KICKS[marks[4]:] = [H.w(k[:3]) + (k[3] + H.turn,) + tuple(k[4:]) for k in KICKS[marks[4]:]]
    for r in EXTRA[marks[5]:] + mb.SOLIDS[marks[6]:]:
        place_row(r)
    CLOTH[marks[7]:] = [(H.w(c),) + tuple(c_[1:3]) + (c_[3] + H.turn,) + tuple(c_[4:]) for c_ in CLOTH[marks[7]:] for c in [c_[0]]]


def den(ctx):
    b, rng = ctx.b, random.Random("den")
    H = LAY.hang
    dome(ctx, H.outline, H.C, H.profile, H.mats, H.amp, [H.crack.hole], seed="hangout", tunnels=[H.crack])
    cx, cz = H.C

    def glow(x, y, z, sx, sy, sz, mat, yaw=0.0):
        b.group = bake_light.GLOW
        mb._bx(b, x, y, z, sx, sy, sz, mat, yaw=yaw, bottom=True)
        b.group = None

    # The walls: tin sheets painted red, teal and yellow round the room up to the ceiling, a strip of light along
    # them at head height, a kick plate. (Left open at the crack.)
    M = len(H.outline)
    cols = ("hd_tin_red", "hd_tin_teal", "hd_tin_yellow", "hd_tin_teal")
    for k in range(M):
        pa, pb = H.outline[k], H.outline[(k + 1) % M]
        mx, mz = (pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2
        u, a = H.crack.local((mx, 0, mz))
        if abs(u) < H.crack.hw + 1.1 and a > 0:
            continue
        f = H.f_at(2.6) - 0.35 / HANG_R
        qa = (cx + (pa[0] - cx) * f, cz + (pa[1] - cz) * f)
        qb = (cx + (pb[0] - cx) * f, cz + (pb[1] - cz) * f)
        ln = math.hypot(qb[0] - qa[0], qb[1] - qa[1]) + 0.04
        yaw = math.degrees(math.atan2(qb[0] - qa[0], qb[1] - qa[1]))
        c = ((qa[0] + qb[0]) / 2, (qa[1] + qb[1]) / 2)
        b.box((c[0], CEIL / 2, c[1]), (0.04, CEIL + 0.02, ln), yaw=yaw, style=_kit(cols[k // 6 % 4]))
        b.box((c[0], 2.53, c[1]), (0.1, 0.06, ln), yaw=yaw, style=mb._solid("bk_iron"))
        b.box((c[0], 0.08, c[1]), (0.08, 0.16, ln), yaw=yaw, style=mb._solid("bk_iron"))       # a kick plate
        if k % 2 == 0:
            ix, iz = cx + (c[0] - cx) * 0.985, cz + (c[1] - cz) * 0.985
            glow(ix, 2.46, iz, 0.03, 0.03, ln, ("teal", "red")[k // 2 % 2], yaw)
        block(c[0], 0.0, c[1], 0.2, CEIL, ln, yaw)

    def at(ang, r, y=0.0):                                             # a point r out from the middle at angle ang
        return (cx + math.cos(ang) * r, y, cz + math.sin(ang) * r)

    def yaw_at(ang):                                                   # a box's yaw: its x out from the middle, z round
        return -math.degrees(ang)

    # The floor: black and white tiles, out to the walls whatever their shape.
    for k in range(M):
        pa, pb = H.outline[k], H.outline[(k + 1) % M]
        f = H.f_at(0.1) - 0.1
        b.poly([(cx, 0.004, cz), (cx + (pa[0] - cx) * f, 0.004, cz + (pa[1] - cz) * f),
                (cx + (pb[0] - cx) * f, 0.004, cz + (pb[1] - cz) * f)], (0, 1, 0), "hd_tiles", mb.uv_world())
    # The pool table: a steel frame with felt, red rails, pockets, the balls left out.
    tx, tz = H.table
    L, W = 2.4, 1.3
    b.box((tx, 0.62, tz), (L, 0.16, W), style=mb._nb("bk_iron"))
    b.box((tx, 0.705, tz), (L - 0.2, 0.012, W - 0.2), style=_kit("hd_felt", 2.0))
    for s_ in (-1, 1):
        b.box((tx, 0.74, tz + s_ * (W / 2 - 0.05)), (L, 0.07, 0.1), style=mb._nb("red"))
        b.box((tx + s_ * (L / 2 - 0.05), 0.74, tz), (0.1, 0.07, W), style=mb._nb("red"))
        for e in (-1, 1):
            pipe(b, (tx + s_ * (L / 2 - 0.15), 0, tz + e * (W / 2 - 0.15)), (tx + s_ * (L / 2 - 0.15), 0.56, tz + e * (W / 2 - 0.15)),
                 "bk_iron", 0.08)
            mb._bx(b, tx + s_ * (L / 2 - 0.1), 0.712, tz + e * (W / 2 - 0.1), 0.09, 0.01, 0.09, "black", bottom=True)
        mb._bx(b, tx, 0.712, tz + s_ * (W / 2 - 0.1), 0.09, 0.01, 0.09, "black", bottom=True)
    for k, col in enumerate(("bone", "red", "yellow", "blue", "black", "red", "yellow", "green", "blue")):
        bx = tx + (0.6 if k == 0 else -0.35 - (k % 3) * 0.09 + rng.uniform(-0.25, 0.1))
        bz = tz + (0.0 if k == 0 else rng.uniform(-0.45, 0.45))
        b.box((bx, 0.74, bz), (0.06, 0.06, 0.06), yaw=rng.uniform(0, 90), style=mb._nb(col))
    pipe(b, (tx + 0.2, 0.75, tz + 0.3), (tx + 1.5, 0.78, tz + 0.75), "steel_light", 0.012)     # a cue left on the table
    block(tx, 0.0, tz, L, 0.8, W)
    hang((tx, 2.3, tz), CEIL - 2.3, 1.2, 3.2, shaded=True)
    # The bar: a curve round the north wall, tin front with a light strip under the steel top, stools along it,
    # curved shelves of snacks behind, the glowing SNACKS sign over them.
    north = -math.pi / 2
    rb = H.wall_r(north) - 1.9                                         # (the bar's front; behind it is outwards)
    n = 9
    span = 0.34
    for k in range(n):
        ang = north - span + 2 * span * (k + 0.5) / n
        seg = 2 * rb * math.sin(span / n) + 0.03
        p = at(ang, rb)
        b.box((p[0], 0.5, p[2]), (0.12, 1.0, seg), yaw=yaw_at(ang), style=_kit("hd_tin_red"))
        q = at(ang, rb + 0.35)
        b.box((q[0], 0.55, q[2]), (0.6, 1.1, seg + 0.04), yaw=yaw_at(ang), style=mb._nb("bk_iron"))
        q = at(ang, rb + 0.25)
        b.box((q[0], 1.12, q[2]), (0.8, 0.05, seg + 0.08), yaw=yaw_at(ang), style=mb._solid("steel_light"))
        q = at(ang, rb - 0.1)
        glow(q[0], 1.05, q[2], 0.03, 0.03, seg, "yellow", yaw_at(ang))
        q = at(ang, rb + 0.25)
        block(q[0], 0.0, q[2], 0.8, 1.15, seg + 0.05, yaw_at(ang))
    for k in range(5):                                                 # stools
        ang = north - span * 0.8 + 2 * span * 0.8 * k / 4
        p = at(ang, rb - 0.65)
        pipe(b, (p[0], 0.0, p[2]), (p[0], 0.7, p[2]), "steel_light", 0.05)
        b.box((p[0], 0.72, p[2]), (0.36, 0.06, 0.36), yaw=45, style=mb._nb("red"))
        b.box((p[0], 0.04, p[2]), (0.34, 0.02, 0.34), yaw=45, style=mb._solid("bk_iron"))
        H.seat_list.append((p[0], 0.76, p[2], math.degrees(math.atan2(-math.cos(ang), -math.sin(ang)))))   # (facing the bar)
    rs = H.wall_r(north) - 0.3                                         # the shelves behind it
    for k in range(7):
        ang = north - 0.26 + 0.52 * (k + 0.5) / 7
        seg = 2 * rs * math.sin(0.26 / 7)
        for y in (1.2, 1.7):
            p = at(ang, rs, y)
            b.box(p, (0.3, 0.04, seg + 0.02), yaw=yaw_at(ang), style=mb._solid("bk_iron"))
            x = -seg / 2 + 0.03                                        # (snacks, not drinks: owner 2026-11-01, store rules)
            while x < seg / 2 - 0.1:
                kind = rng.choice(("can", "can", "bag", "box"))
                col = rng.choice(("red", "blue", "yellow", "teal", "bone"))
                tan = (-math.sin(ang), math.cos(ang))
                q = (p[0] + tan[0] * x, p[2] + tan[1] * x)
                if kind == "can":
                    b.box((q[0], y + 0.08, q[1]), (0.065, 0.12, 0.065), style=mb._nb(col))
                    x += 0.1
                elif kind == "bag":
                    b.box((q[0], y + 0.13, q[1]), (0.05, 0.22, 0.16), yaw=yaw_at(ang) + rng.uniform(-10, 10), style=mb._nb(col))
                    x += 0.22
                else:
                    b.box((q[0], y + 0.07, q[1]), (0.14, 0.1, 0.2), yaw=yaw_at(ang), style=mb._nb(col))
                    x += 0.24
        p = at(ang, rs)
        block(p[0], 0.0, p[2], 0.4, 2.0, seg + 0.02, yaw_at(ang))
    for ang in (north - 0.26, north + 0.26):
        p = at(ang, rs)
        pipe(b, (p[0], 0.0, p[2]), (p[0], 2.0, p[2]), "bk_iron", 0.05)
    sp = at(north, rs - 0.05)                                          # the sign, over the shelves
    b.box((sp[0], 2.25, sp[2] - 0.05), (1.9, 0.62, 0.06), style=mb._solid("black"))
    F = Frame((sp[0], sp[2]), (1.0, 0.0), (0.0, 1.0), 0.0)
    b.group = bake_light.GLOW
    b.poly([F.P(0.0, 2.0, -0.85), F.P(0.0, 2.0, 0.85), F.P(0.0, 2.5, 0.85), F.P(0.0, 2.5, -0.85)], (0, 0, 1), "decals",
           ctx.d("neon_bar"))
    b.group = None
    LAMPS.append((sp[0], 2.2, sp[2] + 0.4, 0.5, 2.6))
    LAMPS.append(at(north, rb - 0.8, 2.2) + (0.5, 3.0))
    # Rooms (0.25.33, owner: "having rooms as well? making it sectioned makes it feel cozy"): tin partitions with
    # doorways split the den into the snack bar (north), the booth room (east nook) and the games room between.
    def edge(x, z, dx, dz):                                            # from (x, z) along (dx, dz) to the tin wall
        t = 0.0
        while t < 20.0:
            px, pz = x + dx * t, z + dz * t
            if math.hypot(px - cx, pz - cz) > H.wall_r(math.atan2(pz - cz, px - cx)) + 0.05:
                return t
            t += 0.05
        return t

    def partition(x, z, dx, dz, t0, t1, doors, mat):
        """A tin wall from t0 to t1 along (dx, dz) from (x, z), open at each door (centre t, width), a header over it."""
        yaw = math.degrees(math.atan2(dx, dz))
        cuts = sorted((d - w / 2, d + w / 2) for d, w in doors)
        spans, a = [], t0
        for d0, d1 in cuts:
            spans.append((a, d0, False))
            spans.append((d0, d1, True))
            a = d1
        spans.append((a, t1, False))
        for a0_, a1_, door in spans:
            ln = a1_ - a0_
            m = (x + dx * (a0_ + a1_) / 2, z + dz * (a0_ + a1_) / 2)
            if door:                                                   # the header over the doorway
                nx, nz = -dz, dx                                       # (the games room's side: the doors hang there)
                DOORS.append((m[0], m[1], ln, math.degrees(math.atan2(-dz, dx))))
                rail = (m[0] + nx * 0.15, m[1] + nz * 0.15)
                b.box((rail[0], 2.17, rail[1]), (0.05, 0.06, 2 * ln + 0.3), yaw=yaw, style=mb._solid("bk_iron"))
                for e in (-ln - 0.12, ln + 0.12):                       # its brackets on the wall
                    q = (rail[0] + dx * e, rail[1] + dz * e)
                    b.box((q[0] - nx * 0.05, 2.17, q[1] - nz * 0.05), (0.1, 0.1, 0.05), yaw=yaw, style=mb._solid("bk_iron"))
                b.box((m[0], (2.1 + CEIL) / 2, m[1]), (0.14, CEIL - 2.1, ln + 0.02), yaw=yaw, style=_kit(mat))
                block(m[0], 2.1, m[1], 0.2, CEIL - 2.1, ln, yaw)
                for e in (a0_, a1_):                                   # steel posts either side
                    q = (x + dx * e, z + dz * e)
                    b.box((q[0], 1.25, q[1]), (0.16, 2.5, 0.08), yaw=yaw, style=mb._solid("bk_iron"))
                continue
            b.box((m[0], CEIL / 2, m[1]), (0.12, CEIL, ln), yaw=yaw, style=_kit(mat))
            b.box((m[0], 2.53, m[1]), (0.16, 0.06, ln + 0.02), yaw=yaw, style=mb._solid("bk_iron"))
            b.box((m[0], 0.08, m[1]), (0.16, 0.16, ln), yaw=yaw, style=mb._solid("bk_iron"))
            block(m[0], 0.0, m[1], 0.2, CEIL, ln, yaw)
    ZB, XB = cz - 3.2, cx + 4.6                                        # the bar room's wall (z), the booth room's (x)
    west, east = edge(cx, ZB, -1.0, 0.0), edge(cx, ZB, 1.0, 0.0)
    partition(cx, ZB, 1.0, 0.0, -west, east, [(0.0, 2.4)], "hd_tin_yellow")
    south = edge(XB, ZB, 0.0, 1.0)
    partition(XB, ZB, 0.0, 1.0, 0.1, south, [(cz - ZB, 1.8)], "hd_tin_red")
    hang((cx - 2.6, 2.3, cz - 1.4), CEIL - 2.3, 0.8, 3.0)               # (the games room gets a second lamp)
    # Arcade cabinets along the booth room's wall, facing into the games room, screens lit.
    for k, z_ in enumerate((ZB + 1.0, cz + 1.7, cz + 2.6, cz + 3.5)):
        ax_, az_ = XB - 0.65, z_
        face = -math.pi / 2                                            # facing west
        yaw = math.degrees(face)
        f = (math.sin(face), math.cos(face))
        b.box((ax_, 0.9, az_), (0.7, 1.8, 0.7), yaw=yaw, style=mb._nb(("blue", "black", "red", "teal")[k]))
        glow(ax_ + f[0] * 0.365, 1.3, az_ + f[1] * 0.365, 0.5, 0.4, 0.02, ("teal", "green", "yellow", "red")[k], yaw)
        glow(ax_ + f[0] * 0.365, 1.68, az_ + f[1] * 0.365, 0.6, 0.14, 0.02, ("yellow", "yellow", "teal", "bone")[k], yaw)
        b.box((ax_ + f[0] * 0.42, 0.95, az_ + f[1] * 0.42), (0.6, 0.06, 0.3), yaw=yaw, style=mb._nb("black"))
        for s_ in (-0.15, 0.12):                                       # stick and buttons
            pipe(b, (ax_ + f[0] * 0.48 + f[1] * s_, 0.98, az_ + f[1] * 0.48 - f[0] * s_),
                 (ax_ + f[0] * 0.48 + f[1] * s_, 1.05, az_ + f[1] * 0.48 - f[0] * s_), ("red", "yellow")[s_ > 0], 0.03)
        block(ax_, 0.0, az_, 0.75, 1.8, 0.75, yaw)
        LAMPS.append((ax_ + f[0] * 0.6, 1.3, az_ + f[1] * 0.6, 0.35, 1.8))
    # The jukebox: red tin and chrome, its front lit, on the west wall.
    jx, jz = H.jukebox
    b.box((jx, 0.7, jz), (0.55, 1.4, 0.9), style=_kit("hd_tin_red", 2.0))
    b.box((jx + 0.02, 1.42, jz), (0.5, 0.12, 0.84), style=mb._nb("steel_light"))
    glow(jx + 0.28, 0.95, jz, 0.01, 0.5, 0.6, "yellow")
    b.box((jx + 0.285, 0.45, jz), (0.01, 0.3, 0.6), style=mb._solid("bk_grate"))
    block(jx, 0.0, jz, 0.55, 1.45, 0.9)
    LAMPS.append((jx + 0.5, 0.95, jz, 0.6, 2.4))
    # The booth: a round couch in the east nook, open towards the table, round a drum for a table on a round rug.
    ux, uz = H.booth
    rug = [(ux + math.cos(2 * math.pi * k / 24) * 2.1, 0.012, uz + math.sin(2 * math.pi * k / 24) * 2.1) for k in range(24)]
    for k in range(24):
        b.poly([(ux, 0.012, uz), rug[k], rug[(k + 1) % 24]], (0, 1, 0), "carpet", mb.uv_world())
    rc = 1.55
    nseg = 9
    for k in range(nseg):                                              # from north-west round the east to south-west
        ang = -1.95 + 3.9 * (k + 0.5) / nseg
        seg = 2 * rc * math.sin(3.9 / nseg / 2) + 0.06
        p = (ux + math.cos(ang) * rc, uz + math.sin(ang) * rc)
        y_ = -math.degrees(ang)
        b.box((p[0], 0.22, p[1]), (0.7, 0.44, seg), yaw=y_, style=_kit("hd_vinyl"))
        q = (ux + math.cos(ang) * (rc + 0.3), uz + math.sin(ang) * (rc + 0.3))
        b.box((q[0], 0.72, q[1]), (0.18, 0.6, seg + 0.05), yaw=y_, style=_kit("hd_vinyl"))
        b.box((p[0], 0.5, p[1]), (0.6, 0.12, seg - 0.04), yaw=y_ + rng.uniform(-3, 3), style=mb._nb("yellow"))
        block(p[0], 0.0, p[1], 0.85, 1.0, seg, y_)
        if k % 2 == 1:
            H.seat_list.append((p[0] - math.cos(ang) * 0.05, 0.56, p[1] - math.sin(ang) * 0.05,
                                math.degrees(math.atan2(math.cos(ang), math.sin(ang)))))
    drum(b, ux, uz, mat="cabin_tin_d")
    block(ux, 0.0, uz, 0.6, 0.9, 0.6)
    for k in range(2):
        KICKS.append((ux - 0.1 + k * 0.2, 0.9, uz - 0.1, 0.0, 2, KICK_COLOURS[("red", "metal")[k]]))
    hang((ux, 2.2, uz), CEIL - 2.2, 0.9, 3.0, shaded=True)
    # Cues in a rack on the west wall, by the jukebox.
    for k in range(3):
        p = at(math.pi - 0.35, H.wall_r(math.pi - 0.35) - 0.08)
        z = p[2] + k * 0.25
        pipe(b, (p[0] + 0.15, 0.05, z), (p[0], 1.45, z), "steel_light", 0.012)
    # String lights zigzagging over it all, and a mirror ball over the middle.
    # (under the ceiling now, in the games room only)
    string_lights(b, (cx - 3.4, 3.3, cz + 4.4), (cx + 4.4, 3.3, cz - 2.9), sag=0.4, every=1.2, strength=0.25, reach=2.4)
    string_lights(b, (cx - 3.2, 3.3, cz - 2.9), (cx + 4.4, 3.3, cz + 4.0), sag=0.4, every=1.2, strength=0.25, reach=2.4)
    mx_, mz_ = cx + 1.6, cz + 2.6
    pipe(b, (mx_, 3.0, mz_), (mx_, CEIL, mz_), "bk_cable", 0.015)
    for k in range(3):
        b.box((mx_, 2.88, mz_), (0.2, 0.2, 0.2), yaw=k * 30, pitch=0, style=mb._solid("steel_light"))
    loft(ctx, glow)


def loft(ctx, glow):
    """The ceiling over the den's rooms, and the loft over them (0.25.35, owner: "make the roof match the room...
    maybe even a second floor??"): a movie room up steel stairs from the games room, a screen, couches, beanbags and
    a table football game. The rock dome is still there above it all, but you no longer see it."""
    b, rng = ctx.b, random.Random("loft")
    H = LAY.hang
    cx, cz = H.C
    x0h, z0h, x1h, z1h = HOLE
    T = 0.4
    R = max(H.wall_r(2 * math.pi * k / 48) for k in range(48)) + 0.8
    n = int(R / T) + 1

    def inside(x, z, r_at, pad):
        return math.hypot(x - cx, z - cz) < r_at(math.atan2(z - cz, x - cx)) + pad

    def strips(y, normal, mat, r_at, pad, uv):
        """Flat cells over the room (out under its walls), cut round the stairwell, merged into strips."""
        for j in range(-n, n):
            za = cz + j * T
            run = None
            for i in range(-n, n + 1):
                xa = cx + i * T
                ok = i < n and not (x0h - 1e-6 <= xa + T / 2 <= x1h + 1e-6 and z0h - 1e-6 <= za + T / 2 <= z1h + 1e-6) \
                    and any(inside(xa + dx, za + dz, r_at, pad) for dx in (0, T) for dz in (0, T))
                if ok and run is None:
                    run = xa
                elif not ok and run is not None:
                    b.poly([(run, y, za), (xa, y, za), (xa, y, za + T), (run, y, za + T)], normal, mat, uv)
                    run = None
    strips(CEIL, (0, -1, 0), "hd_ceiling", H.wall_r, 0.3, mb.uv_world())
    strips(UP, (0, 1, 0), "carpet", H.up_r, 0.3, mb.uv_world())
    strips(UP_TOP, (0, -1, 0), "hd_ceiling", H.up_r, 0.3, mb.uv_world())
    # The stairwell's sides (the floor's edge, steel) and a rail round it upstairs, open where the stairs come up.
    for (xa, za), (xb, zb), nn in ((((x0h, z0h), (x1h, z0h), (0, 0, 1))), (((x1h, z0h), (x1h, z1h), (-1, 0, 0))),
                                   (((x1h, z1h), (x0h, z1h), (0, 0, -1))), (((x0h, z1h), (x0h, z0h), (1, 0, 0)))):
        b.poly([(xa, CEIL, za), (xb, CEIL, zb), (xb, UP, zb), (xa, UP, za)], nn, "bk_iron", mb.uv_world(1.0))
    for (xa, za), (xb, zb) in (((x0h, z0h), (x0h, z1h)), ((x1h, z0h), (x1h, z1h)), ((x0h, z1h), (x1h, z1h))):
        pipe(b, (xa, UP + 1.0, za), (xb, UP + 1.0, zb), "steel_light", 0.05)
        pipe(b, (xa, UP + 0.5, za), (xb, UP + 0.5, zb), "steel_light", 0.03)
        ln = math.hypot(xb - xa, zb - za)
        for k in range(int(ln / 1.2) + 2):
            t = min(1.0, k * 1.2 / ln)
            pipe(b, (xa + (xb - xa) * t, UP, za + (zb - za) * t), (xa + (xb - xa) * t, UP + 1.0, za + (zb - za) * t),
                 "steel_light", 0.04)
        block((xa + xb) / 2, UP, (za + zb) / 2, max(0.1, abs(xb - xa)), 1.05, max(0.1, abs(zb - za)))
    # The stairs up, steel, from the games room's south end to the loft (you walk the smooth ramp under them;
    # their treads have no boxes of their own, or you'd catch on them).
    sx = (x0h + x1h) / 2
    c, sz, yaw, pitch = ramp((sx, z1h), (sx, z0h), UP, x1h - x0h - 0.1)
    step = UP / max(2, round(UP / 0.2))
    n_solid = len(mb.SOLIDS)
    mb.stairs(ctx, (c[0], c[1] + step / 2, c[2]), sz, yaw, pitch, mats=("bk_grate", "bk_iron"))
    del mb.SOLIDS[n_solid:]
    for x in (x0h + 0.05, x1h - 0.05):
        pipe(b, (x, 0.95, z1h), (x, UP + 0.95, z0h), "steel_light", 0.04)
        pipe(b, (x, 0.0, z1h), (x, 0.95, z1h), "steel_light", 0.04)
    # The loft's walls: tin again, ceiling to floor, a light strip along them.
    cols = ("hd_tin_teal", "hd_tin_red", "hd_tin_yellow", "hd_tin_red")
    M = 72
    for k in range(M):
        a0, a1 = 2 * math.pi * k / M, 2 * math.pi * (k + 1) / M
        qa = (cx + math.cos(a0) * (H.up_r(a0) + 0.05), cz + math.sin(a0) * (H.up_r(a0) + 0.05))
        qb = (cx + math.cos(a1) * (H.up_r(a1) + 0.05), cz + math.sin(a1) * (H.up_r(a1) + 0.05))
        ln = math.hypot(qb[0] - qa[0], qb[1] - qa[1]) + 0.04
        yaw = math.degrees(math.atan2(qb[0] - qa[0], qb[1] - qa[1]))
        m = ((qa[0] + qb[0]) / 2, (qa[1] + qb[1]) / 2)
        b.box((m[0], (UP + UP_TOP) / 2, m[1]), (0.04, UP_TOP - UP + 0.02, ln), yaw=yaw, style=_kit(cols[k // 6 % 4]))
        b.box((m[0], UP + 0.08, m[1]), (0.08, 0.16, ln), yaw=yaw, style=mb._solid("bk_iron"))
        if k % 2 == 0:
            ix, iz = cx + (m[0] - cx) * 0.985, cz + (m[1] - cz) * 0.985
            glow(ix, UP + 2.2, iz, 0.03, 0.03, ln, ("red", "teal")[k // 2 % 2], yaw)
        block(m[0], UP, m[1], 0.2, UP_TOP - UP, ln, yaw)
    # The movie room: a big screen on the north wall (lit, the film's on), a projector on the ceiling, two couches
    # facing it on a rug, beanbags in front, a table football game at the back.
    north = -math.pi / 2
    # (flat against the curved wall: as far back as its ends let it go)
    rr = min(H.up_r(a) * -math.sin(a) for a in (north + 0.01 * k for k in range(-60, 61))
             if abs(H.up_r(a) * math.cos(a)) <= 2.4) - 0.12
    sxz = (cx, cz - rr)
    b.box((sxz[0], UP + 1.55, sxz[1] + 0.05), (4.6, 2.5, 0.08), style=mb._solid("black"))
    glow(sxz[0], UP + 1.55, sxz[1] + 0.1, 4.3, 2.25, 0.02, "bone")
    for x, y, col, w, h in ((-1.2, 1.0, "blue", 1.9, 0.9), (0.9, 0.9, "olive", 2.2, 0.7), (0.0, 1.8, "yellow", 0.6, 0.6),
                            (-1.4, 2.25, "teal", 1.2, 0.4)):          # (a picture on it: the film's on)
        glow(sxz[0] + x, UP + y, sxz[1] + 0.12, w, h, 0.01, col)
    LAMPS.append((sxz[0], UP + 1.6, sxz[1] + 1.2, 0.8, 3.6))
    px, pz = cx + 0.4, cz + 0.4
    b.box((px, UP_TOP - 0.25, pz), (0.4, 0.18, 0.45), style=mb._nb("black"))
    pipe(b, (px, UP_TOP - 0.16, pz), (px, UP_TOP, pz), "bk_iron", 0.04)
    glow(px, UP_TOP - 0.25, pz - 0.23, 0.12, 0.12, 0.02, "bone")
    rug = [(cx - 1.6, UP + 0.012, cz - 2.6), (cx + 2.6, UP + 0.012, cz - 2.6), (cx + 2.6, UP + 0.012, cz + 1.6),
           (cx - 1.6, UP + 0.012, cz + 1.6)]
    b.poly(rug, (0, 1, 0), "olive_dark", mb.uv_world())
    for row_z, col in ((cz - 1.3, "hd_vinyl"), (cz + 0.7, "hd_vinyl")):
        ux = cx + 0.5
        b.box((ux, UP + 0.22, row_z), (2.4, 0.44, 0.85), style=_kit(col))
        b.box((ux, UP + 0.7, row_z + 0.33), (2.4, 0.6, 0.22), style=_kit(col))
        for e in (-1, 1):
            b.box((ux + e * 1.15, UP + 0.55, row_z), (0.18, 0.3, 0.85), style=mb._nb("bk_iron"))
        for e in (-0.55, 0.55):
            b.box((ux + e, UP + 0.5, row_z - 0.05), (0.9, 0.12, 0.6), yaw=rng.uniform(-3, 3), style=mb._nb("red"))
            H.seat_list.append((ux + e, UP + 0.56, row_z + 0.05, 0.0))
        block(ux, UP, row_z, 2.45, 1.0, 0.9)
    for k, (bx, bz, col) in enumerate(((cx - 1.0, cz - 3.4, "red"), (cx + 0.6, cz - 3.6, "yellow"),
                                       (cx + 2.0, cz - 3.3, "teal"))):
        b.box((bx, UP + 0.2, bz), (0.75, 0.4, 0.75), yaw=rng.uniform(0, 90), style=mb._nb(col))
        b.box((bx, UP + 0.45, bz + 0.15), (0.55, 0.3, 0.3), yaw=rng.uniform(-15, 15), style=mb._nb(col))
        block(bx, UP, bz, 0.7, 0.5, 0.7)
    fx, fz = cx + 2.6, cz + 3.0                                        # the table football game
    b.box((fx, UP + 0.55, fz), (1.2, 0.3, 0.75), style=mb._nb("blue"))
    b.box((fx, UP + 0.705, fz), (1.1, 0.012, 0.65), style=_kit("hd_felt", 2.0))
    for e in (-1, 1):
        for f in (-1, 1):
            pipe(b, (fx + e * 0.5, UP, fz + f * 0.3), (fx + e * 0.5, UP + 0.4, fz + f * 0.3), "bk_iron", 0.07)
    for k in range(6):
        x = fx - 0.45 + k * 0.18
        pipe(b, (x, UP + 0.78, fz - 0.55), (x, UP + 0.78, fz + 0.55), "steel_light", 0.02)
        for m_ in range(2 + k % 2):
            b.box((x, UP + 0.74, fz - 0.2 + m_ * 0.2), (0.04, 0.1, 0.04), style=mb._nb(("red", "blue")[k % 2]))
        b.box((x, UP + 0.78, fz + 0.6 * (1 if k % 2 else -1)), (0.05, 0.05, 0.1), style=mb._nb("black"))
    block(fx, UP, fz, 1.2, 0.85, 0.8)
    hang((cx + 0.5, UP + 2.2, cz - 0.3), UP_TOP - UP - 2.2, 0.7, 3.0, shaded=True)
    hang((fx, UP + 2.2, fz), UP_TOP - UP - 2.2, 0.7, 2.6, shaded=True)
    string_lights(b, (cx - 3.0, UP_TOP - 0.25, cz - 4.0), (cx + 4.0, UP_TOP - 0.25, cz + 3.6), sag=0.3, every=1.2,
                  strength=0.2, reach=2.2)


def hang(at, length, strength, reach, shaded=False):
    """A lamp hanging on a cable from `length` above `at` (the bulb), that swings when knocked (0.22.0, World reacts):
    left out of the model, drawn by scripts/swing_lamps.gd; its light is baked where it hangs still."""
    SWINGS.append((at[0], at[1] + length, at[2], length, 1 if shaded else 0))
    LAMPS.append((at[0], at[1] - 0.15, at[2], strength, reach))


def sheet(c, width, height, yaw, colour):
    """A curtain or a piece of washing hung by its top edge (0.22.0, World reacts): left out of the model, drawn by
    scripts/cloth.gd, which sways it when someone pushes through. Never collides (it never did)."""
    CLOTH.append((c, width, height, yaw, colour))


def bulb(b, x, y, z, strength=0.4, reach=2.6):
    b.group = bake_light.GLOW
    mb._bx(b, x, y - 0.06, z, 0.08, 0.1, 0.08, "bone", bottom=True)
    b.group = None
    LAMPS.append((x, y - 0.15, z, strength, reach))


def string_lights(b, a, c, sag=0.6, every=1.4, strength=0.4, reach=2.6):
    """Bulbs on a cable strung from a to c, sagging in the middle."""
    d = mb.v_sub(c, a)
    ln = math.sqrt(mb.dot(d, d))
    n = max(2, int(ln / every))
    prev = a
    for k in range(1, n + 1):
        t = k / n
        p = (a[0] + d[0] * t, a[1] + d[1] * t - sag * 4 * t * (1 - t), a[2] + d[2] * t)
        pipe(b, prev, p, "bk_cable", 0.015)
        if k < n:
            bulb(b, p[0], p[1], p[2], strength, reach)
        prev = p


def work_lamp(b, x, z, strength=1.1, reach=3.0, y0=0.0):
    """A work lamp on a tripod."""
    for a in (0, 120, 240):
        r = math.radians(a)
        pipe(b, (x + math.sin(r) * 0.4, y0, z + math.cos(r) * 0.4), (x, y0 + 1.7, z), "yellow", 0.03)
    b.box((x, y0 + 1.8, z), (0.35, 0.3, 0.2), style=mb._nb("yellow"))
    b.group = bake_light.GLOW
    mb._bx(b, x, y0 + 1.8, z + 0.11, 0.28, 0.22, 0.01, "bone", bottom=True)
    b.group = None
    LAMPS.append((x, y0 + 1.8, z, strength, reach))


def lamps(ctx):
    b = ctx.b
    for a0, a1, y in LAY.strings:                                      # strings of bulbs across the hall
        string_lights(b, wall_at(y, math.radians(a0)), wall_at(y, math.radians(a1)), sag=1.0, every=1.8, strength=0.3)
    for bid, o, t, n, w, depth, y0, kind in LAY.bays:                  # a bare bulb over every bay
        F = Frame(o, t, n, y0)
        p = F.P(depth * 0.55, 2.45, 0.0)                               # (0.22.0: low enough to head when you jump)
        hang(p, 0.45 + (0.5 if kind == "bunker" else 1.6), 1.3, 2.6)
    if SHAPE != "cave":                                                # a cluster of lamps hung over the war table
        tx, tz = LAY.war_table
        for k in range(5):
            a = 2 * math.pi * k / 5
            p = (tx + math.cos(a) * 1.6, 4.2, tz + math.sin(a) * 1.2)
            pipe(b, p, (tx, 7.5, tz), "bk_cable", 0.015)
            bulb(b, p[0], p[1], p[2], 0.9, 3.6)
    for x, z, s, r in LAY.work_lamps:
        work_lamp(b, x, z, s, r, base_y(x, z))
    for t in LAY.tunnels:                                              # bulbs down each tunnel's crown
        every = 7.0 if t.name == "range" else 4.6
        a = t.a0 + 2.0
        while a < t.a1 - 1.0:
            p = t.P(0, t.crown - 0.35, a)
            pipe(b, p, t.P(0, t.crown, a), "bk_cable", 0.015)
            bulb(b, p[0], p[1], p[2], 1.1 if t.name == "range" else 0.9, 2.8)
            a += every
        pipe(b, t.P(0, t.crown - 0.06, t.a0), t.P(0, t.crown - 0.06, t.a1 - 1.0), "bk_cable", 0.03)


def dress(ctx):
    L = LAY
    LAMPS.clear()
    dome(ctx, L.outline, L.C, L.profile, L.mats, L.amp, [t.hole for t in L.tunnels], seed="hall", tunnels=L.tunnels)
    for t in L.tunnels:
        t.draw(ctx)
    if L.ledge:
        ledge(ctx)
    rng = random.Random("bays")
    for i, entry in enumerate(L.bays):
        bay(ctx, rng, i, entry)
    war_table(ctx)
    shooting_range(ctx)
    mess(ctx)
    bunks(ctx)
    if SHAPE == "cave":
        washroom(ctx)
    else:
        shower_block(ctx)
    dress_props(ctx)
    boards(ctx)
    pillars(ctx)
    if SHAPE != "cave":
        quarters(ctx)
    if L.hang:
        hangout(ctx)
    lamps(ctx)


def decals(rng):
    a = mb.Atlas(256)

    def painted(text):
        def p(c):         # white paint on old tin, a bit patchy
            c.rect(0, 0, c.w, c.h, "fmet")
            c.noise(0, 0, c.w, c.h, ["fmet_dark", "frust"], 0.15, random.Random(text))
            c.ctext(0, c.w, 3, text, "bk_paint_white")
        return p

    def bloxov_map(c):    # the war table's map: fields, woods, the creek, roads, pins
        r = random.Random("map")
        c.rect(0, 0, c.w, c.h, "sage")
        c.blotch(["gsage", "olive_light"], 30, r, size=(3, 8))
        for _ in range(40):
            x, y = r.randrange(c.w), r.randrange(c.h)
            c.rect(x, y, x + 2, y + 2, "olive")
        y = c.h // 2
        for x in range(c.w):
            y = max(2, min(c.h - 3, y + r.choice((-1, 0, 0, 1))))
            c.put(x, y, "sky_blue")
        for x in range(c.w):
            c.put(x, c.h // 3, "bone")
        for y in range(c.h):
            c.put(c.w * 2 // 3, y, "bone")
        for _ in range(8):
            c.put(r.randrange(c.w), r.randrange(c.h), "red")
        c.frame(0, 0, c.w, c.h, "bone")
    def dartboard(c):     # black and cream wedges, red and green rings, 20 at the top (the game paints the numbers)
        bull, obull, t0, t1, d0, d1, edge = DART_RINGS
        for py in range(c.h):
            for px in range(c.w):
                dx, dy = (px + 0.5) / c.w * 2 - 1, (py + 0.5) / c.h * 2 - 1
                r = math.hypot(dx, dy) * edge
                wedge = int(((math.degrees(math.atan2(dx, dy)) + 9) % 360) // 18)
                even = wedge % 2 == 0
                if r > edge:
                    col = "wood"
                elif r <= bull:
                    col = "red"
                elif r <= obull:
                    col = "green_dark"
                elif r > d1:
                    col = "black"
                elif t0 < r <= t1 or d0 < r <= d1:
                    col = "red" if even else "green_dark"
                else:
                    col = "black" if even else "cream"
                c.put(px, py, col)
        for k in range(20):                                            # the wire between the wedges
            ang = math.radians(k * 18 + 9)
            for i in range(int(c.w * 0.04), int(c.w * 0.38)):
                c.put(int(c.w / 2 + math.sin(ang) * i), int(c.h / 2 + math.cos(ang) * i), "steel")
    for bid, text in SIGNS.items():
        a.add("sign_" + bid, 48, 10, painted(text))
    def neon_bar(c):      # the hangout's sign (0.25.17): red neon on black, a teal frame. A snack bar, not a bar
        c.rect(0, 0, c.w, c.h, "black")       # (owner 2026-11-01: alcohol would change the store age-rating forms)
        c.frame(1, 1, c.w - 1, c.h - 1, "teal")
        c.ctext(0, c.w, 3, "SNACKS", "neon_red")
    a.add("neon_bar", 36, 10, neon_bar)
    a.add("dartboard", 96, 96, dartboard)
    a.add("map", 92, 56, bloxov_map)
    return a


# ------------------------------------------------------------------------------------------------ light bake
def lamp_light(points, normals, lo, hi):
    """Light from the lamps at each point: falloff with distance, facing, and blocked by walls."""
    L = np.array([l[:3] for l in LAMPS])
    S = np.array([l[3] for l in LAMPS])
    R = np.array([l[4] for l in LAMPS])
    out = np.empty(len(points))
    for k, (p, n) in enumerate(zip(points, normals)):
        o = np.array(p) + np.array(n) * 0.03
        d = L - o
        dist = np.linalg.norm(d, axis=1)
        near = dist < R * 5.0
        if not near.any():
            out[k] = 0.0
            continue
        dn = d[near] / dist[near, None]
        facing = np.clip(dn @ np.array(n), 0.0, 1.0)
        inv = 1.0 / np.where(np.abs(dn) < 1e-9, 1e-9, dn)
        t0 = (lo[None, :, :] - o[None, None, :]) * inv[:, None, :]
        t1 = (hi[None, :, :] - o[None, None, :]) * inv[:, None, :]
        tmin = np.minimum(t0, t1).max(axis=2)
        tmax = np.maximum(t0, t1).min(axis=2)
        blocked = ((tmax >= tmin) & (tmax > 0.0) & (tmin < dist[near, None] - 0.05)).any(axis=1)
        fall = S[near] / (1.0 + (dist[near] / R[near]) ** 2) ** 1.5
        out[k] = float((fall * (0.35 + 0.65 * facing) * ~blocked).sum())
    return out


def lamp_shade(v):
    return min(1.0, 0.11 + 0.89 * min(1.0, v))


# ------------------------------------------------------------------------------------------------ output
def stations():
    """Where you can press E (USE): (id, x, z, reach). The hideout opens the menu on that station."""
    out = []
    for bid, o, t, n, w, depth, y0, kind in LAY.bays:
        F = Frame(o, t, n, y0)
        p = F.P(depth + 0.7, 0, 0.0)
        out.append((bid, p[0], p[2], max(2.4, w / 2 + 0.4)))
    out.append(("war_table", LAY.war_table[0], LAY.war_table[1], 3.8))
    for bid, (x, z), (nx, nz) in LAY.boards:
        out.append((bid, x + nx * 1.3, z + nz * 1.3, 2.4))
    t = LAY.tunnels[0]
    p = t.P(0, 0, t.a0 - FIRING_BACK - 1.0)
    out.append(("range", p[0], p[2], 3.0))
    if SHAPE != "cave":
        out.append(("darts", DART_LINE + 0.3, DARTBOARD[2], 1.4))
        out.append(("radio", RADIO[0], RADIO[1] + 0.95, 1.4))
        out.append(("lights", SWITCH[0] - 0.75, SWITCH[2], 1.4))
    if LAY.hang:
        jx, jz = LAY.hang.jukebox
        p = LAY.hang.w((jx + 1.0, 0.0, jz))
        out.append(("jukebox", p[0], p[2], 1.4))
    return out


def aimed_stations():
    """The small things you use by looking at them (0.21.16, owner: their reach felt off): id -> (the thing's middle,
    how far round it you can look, how far from your eyes you can use it). The marker is still where darts puts you."""
    if SHAPE == "cave":
        return {}
    return {"darts": ((DARTBOARD[0] + 0.01, DARTBOARD[1], DARTBOARD[2]), 0.36, 3.6),
            "radio": ((RADIO[0] - 0.05, 0.6, RADIO[1]), 0.28, 2.4),
            "lights": ((SWITCH[0] - 0.04, SWITCH[1] + 0.02, SWITCH[2]), 0.2, 2.2),
            **({"jukebox": (LAY.hang.w((LAY.hang.jukebox[0] + 0.28, 0.95, LAY.hang.jukebox[1])), 0.45, 2.6)}
               if LAY.hang else {})}


def seats():
    """Where you can sit (0.21.7): (x, y of the seat, z, the way you face as a yaw in degrees, Godot's)."""
    if SHAPE == "cave":
        return []
    out = []
    mx, mz = LAY.mess
    for k in (-1, 0, 1):                                               # the mess benches, two places each, facing the table
        x, z = mx + k * 0.3, mz + k * 2.2
        for s in (-0.95, 0.95):
            for e in (-0.6, 0.6):
                out.append((x + e, 0.46, z - s, 180.0 if s > 0 else 0.0))
    for e in (-0.5, 0.5):                                              # the couch, facing the TV
        out.append((-1.55, 0.56, LAY.mess[1] + 5.2 + e, 90.0))
    H = LAY.hang
    if H:                                                              # the hangout's booth and bar stools
        for x, y, z, yaw in H.seat_list:
            p = H.w((x, y, z))
            out.append((p[0], round(p[1], 3), p[2], yaw + H.turn))
    return out


def cloth_rows():
    """CLOTH for scripts/cloth.gd: centre x, y, z, width, height, yaw, light (the baked lamp light where it hangs,
    so it matches the model round it), then its colour (r, g, b)."""
    none = np.zeros((0, 3))
    out = []
    for c, w, h, yaw, colour in CLOTH:
        a = math.radians(yaw)
        n = (math.sin(a), 0.0, math.cos(a))
        light = sum(lamp_shade(lamp_light([c], [d], none, none)[0]) for d in (n, tuple(-v for v in n))) / 2
        rgb = tuple(int(CLOTH_COLOURS[colour][k:k + 2], 16) / 255.0 for k in (0, 2, 4))
        out.append((c[0], c[1], c[2], w, h, yaw, round(light, 3), tuple(round(v, 3) for v in rgb)))
    return out


def door_rows():
    """For scripts/hideout_doors.gd: the rooms' tin doors, and the hidden one at the armory's end (0.25.35)."""
    out = [(x, -HANG_DEPTH, z, ln, 2.08, yaw, 1.0, 2.0, 0.0) for x, z, ln, yaw in DOORS]
    if LAY.hang:
        rt = LAY.tunnels[2]
        p = rt.P(0.0, 0.0, rt.a1)
        out.append((p[0], 0.0, p[2], 2.5, 2.9, rt.yaw(), 1.0, 1.0, 1.0))      # (slides towards the duffels: clear)
    return out


def write_level(rows):
    """The scene the hideout loads: a BoxMap of the boxes (collision only, the model draws them)."""
    flat = []
    for r in rows:
        if r["solid"]:
            flat += r["pos"] + r["size"] + [r["yaw"], r["pitch"], 0.0, 2.0]
    path = os.path.join(mb.ROOT, "scenes", "hideout", "hideout_level.tscn")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    nums = ", ".join(("%g" % round(v, 4)) for v in flat)
    sx, sz = LAY.spawn
    with open(path, "w") as f:
        f.write('[gd_scene load_steps=7 format=3]\n\n'
                '[ext_resource type="Script" path="res://scripts/box_map.gd" id="1_box"]\n'
                '[ext_resource type="PackedScene" path="res://assets/models/buildings/hideout.glb" id="2_model"]\n'
                '[ext_resource type="Script" path="res://scripts/swing_lamps.gd" id="3_swing"]\n'
                '[ext_resource type="Script" path="res://scripts/cloth.gd" id="4_cloth"]\n'
                '[ext_resource type="Script" path="res://scripts/kickables.gd" id="5_kicks"]\n'
                '[ext_resource type="Script" path="res://scripts/hideout_doors.gd" id="6_doors"]\n\n'
                '[node name="HideoutLevel" type="Node3D"]\n'
                '; Generated by art_source/scripts/make_hideout.py: edit that and re-run it, never this file.\n\n'
                '[node name="Blocks" type="StaticBody3D" parent="."]\n'
                'script = ExtResource("1_box")\n'
                'boxes = PackedFloat32Array(%s)\n'
                'colors = PackedColorArray(0.5, 0.5, 0.5, 1)\n'
                'colour_names = PackedStringArray("bunker")\n\n'
                '[node name="Model" parent="." instance=ExtResource("2_model")]\n\n'
                '[node name="Spawn" type="Marker3D" parent="."]\n'
                'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)\n\n'
                '[node name="Stations" type="Node3D" parent="."]\n' % (nums, sx, sz))
        t = LAY.tunnels[0]
        fl = t.a0 - FIRING_BACK
        spot = t.P(0.0, 0.0, fl - 0.8)
        yaw = math.atan2(-t.D[0], -t.D[1])                             # (a Marker3D looks down its -z: up the range)
        f.write('\n[node name="Range" type="Node3D" parent="."]\n\n'
                '[node name="Spot" type="Marker3D" parent="Range"]\n'
                'transform = Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %g, 0, %g)\n'
                % (math.cos(yaw), math.sin(yaw), -math.sin(yaw), math.cos(yaw), round(spot[0], 3), round(spot[2], 3)))
        for d, u in zip(TARGETS, TARGET_U):
            p = t.P(u, 0.0, fl + d + 0.3)
            f.write('\n[node name="Target%d" type="Marker3D" parent="Range"]\n'
                    'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)\n' % (d, round(p[0], 3), round(p[2], 3)))
        f.write('\n[node name="Swings" type="Node3D" parent="."]\nscript = ExtResource("3_swing")\n'
                'data = PackedFloat32Array(%s)\n' % ", ".join("%g" % round(v, 3) for row in SWINGS for v in row))
        f.write('\n[node name="Kickables" type="Node3D" parent="."]\nscript = ExtResource("5_kicks")\n'
                'data = PackedFloat32Array(%s)\ncolors = PackedColorArray(%s)\n'
                % (", ".join("%g" % round(v, 3) for k in KICKS for v in k[:5]),
                   ", ".join("%g, %g, %g, 1" % tuple(round(int(k[5][j:j + 2], 16) / 255, 3) for j in (0, 2, 4)) for k in KICKS)))
        f.write('\n[node name="Cloth" type="Node3D" parent="."]\nscript = ExtResource("4_cloth")\n'
                'data = PackedFloat32Array(%s)\ncolors = PackedColorArray(%s)\n'
                % (", ".join("%g" % round(v, 3) for row in cloth_rows() for v in row[:-1]),
                   ", ".join("%g, %g, %g, 1" % row[-1] for row in cloth_rows())))
        f.write('\n[node name="Doors" type="Node3D" parent="."]\nscript = ExtResource("6_doors")\n'
                'data = PackedFloat32Array(%s)\n' % ", ".join("%g" % round(v, 3) for row in door_rows() for v in row))
        f.write('\n[node name="Boards" type="Node3D" parent="."]\n')
        for bid, (x, z), (nx, nz) in LAY.boards:                       # (a Marker3D's +z out of the board's face)
            yaw = math.atan2(nx, nz)
            f.write('\n[node name="%s" type="Marker3D" parent="Boards"]\n'
                    'transform = Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %g, %g, %g)\n'
                    'metadata/size = Vector2(%g, %g)\n'
                    % (bid, math.cos(yaw), math.sin(yaw), -math.sin(yaw), math.cos(yaw), round(x + nx * 0.05, 3),
                       round(base_y(x, z) + BOARD_Y, 3), round(z + nz * 0.05, 3), BOARD_W - 0.95, BOARD_H - 0.2))
        f.write('\n[node name="Seats" type="Node3D" parent="."]\n')
        for k, (x, y, z, yaw) in enumerate(seats()):                    # (a Marker3D looks down its -z: the way you face)
            a = math.radians(yaw)
            f.write('\n[node name="Seat%d" type="Marker3D" parent="Seats"]\n'
                    'transform = Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %g, %g, %g)\n'
                    % (k, math.cos(a), math.sin(a), -math.sin(a), math.cos(a), round(x, 3), y, round(z, 3)))
        if SHAPE != "cave":
            x, y, z = DARTBOARD
            f.write('\n[node name="Dartboard" type="Marker3D" parent="."]\n'
                    'transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, %g, %g, %g)\n'
                    'metadata/rings = PackedFloat32Array(%s)\n'
                    % (x + 0.013, y, z, ", ".join("%g" % r for r in DART_RINGS)))
            x, y, z = SWITCH
            glows = ", ".join("%g, %g, %g" % tuple(round(v, 3) for v in g) for g in DARK_GLOWS)
            f.write('\n[node name="Quarters" type="Marker3D" parent="."]\n'
                    'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, %g)\n'
                    'metadata/area = Rect2(%g, %g, %g, %g)\n'
                    'metadata/glows = PackedVector3Array(%s)\n'
                    'metadata/radio = Vector3(%g, 0.55, %g)\n'
                    'metadata/tv = Vector3(-3.684, 1.05, %g)\n'
                    % (z, -4.5, LAY.mess[1] + 3.5, 9.0, 36.0 - LAY.mess[1] - 3.5, glows, RADIO[0], RADIO[1],
                       LAY.mess[1] + 5.2))
        if LAY.hang:
            jx, jz = LAY.hang.jukebox
            f.write('\n[node name="Hangout" type="Marker3D" parent="."]\n'
                    'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)\n'
                    'metadata/jukebox = Vector3(%g, %g, %g)\n'
                    % ((round(LAY.hang.Cw[0], 3), -HANG_DEPTH, round(LAY.hang.Cw[1], 3))
                       + tuple(round(v, 3) for v in LAY.hang.w((jx + 0.3, 0.95, jz)))))
        aimed = aimed_stations()
        for sid, x, z, reach in stations():
            f.write('\n[node name="%s" type="Marker3D" parent="Stations"]\n'
                    'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)\n'
                    'metadata/reach = %g\n' % (sid, round(x, 3), round(z, 3), round(reach, 2)))
            if sid in aimed:
                (ax, ay, az), radius, eye_reach = aimed[sid]
                f.write('metadata/aim = Vector3(%g, %g, %g)\nmetadata/aim_radius = %g\nmetadata/aim_reach = %g\n'
                        % (round(ax, 3), round(ay, 3), round(az, 3), radius, eye_reach))


def main():
    rows = boxes()
    data = {"note": "Generated by art_source/scripts/make_hideout.py.", "openings": [], "boxes": rows}
    xs = [p[0] for p in LAY.outline]
    zs = [p[1] for p in LAY.outline]
    for t in LAY.tunnels:
        for u in (-t.hw, t.hw):
            p = t.P(u, 0, t.a1)
            xs.append(p[0])
            zs.append(p[2])
    if LAY.hang:
        xs += [p[0] - 2.0 for p in LAY.hang.outline_w] + [p[0] + 2.0 for p in LAY.hang.outline_w]
        zs += [p[1] - 2.0 for p in LAY.hang.outline_w] + [p[1] + 2.0 for p in LAY.hang.outline_w]
    mb.FOOTPRINTS[NAME] = (min(xs) - 1, min(zs) - 1, max(xs) + 1, max(zs) + 1)
    mb.SHELLS[NAME] = {"row_hook": lambda ctx, row: True}       # the dressing draws the shell, not the boxes
    mb.DECALS[NAME] = decals
    mb.DRESSING[NAME] = dress
    mb.PROPS["hd_solid"] = lambda ctx, c, s, k: None
    decal_png = os.path.join(mb.ROOT, "art_source", "textures", NAME + "_decals.png")
    if os.path.exists(decal_png):
        os.remove(decal_png)                                        # (painted fresh: its regions move as signs change)
    with open(os.path.join(mb.ROOT, "art_source", "buildings", NAME + ".json"), "w") as f:
        json.dump(data, f, indent=0)
    write_door_texture()
    bake_light.sky = lamp_light
    bake_light.shade = lamp_shade
    mb.build(NAME, True)
    rows += EXTRA
    # (0.22.0, World reacts: what the dressing draws that looks solid, make_building's SOLIDS, collides too)
    rows += [{"pos": r["pos"], "size": r["size"], "yaw": r["yaw"], "pitch": r["pitch"], "colour": "prop", "solid": True,
              "kind": "hd_solid"} for r in mb.SOLIDS]
    with open(os.path.join(mb.ROOT, "art_source", "buildings", NAME + ".json"), "w") as f:
        json.dump(data, f, indent=0)
    write_level(rows)


if __name__ == "__main__":
    main()
