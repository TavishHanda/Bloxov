"""Riptide shore art, pass 1 (owner 2026-11-19: "U can keep going with riptide art"): `quay_front`, what the ship looks
at across the water. Origin (-30, 0, 0): local x 0 is the back of the quay wall, 0.6 its face over the water.

The quay wall (cast concrete blocks over a wet, weed-dark band at the waterline, black rubber fender pads), its low
parapet (concrete, hazard paint at every gap), the cover along the quay edge (gen_riptide.py quay_cover: containers,
blast walls, crates, watchmen's huts, pipes, a wrecked lorry, broken slabs, cable drums), the five quay cranes (legs,
portal braces, machinery house, a lattice boom over the water with its trolley; the braces and the boom are out of
reach), the containers parked on the apron, the pier (plank deck on steel piles, the covered pipe gallery, the pier
shed), the grain gallery over the water, the pontoon under it and the barge line.

Nothing is drawn that a person can walk into without a gray box behind it (make_riptide.py's rule): the crane's
braces and boom hang out of reach, the fender pads stand 4 cm proud of the wall, everything else is inside its box.

    python3 art_source/scripts/make_riptide.py quay_front
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_riptide as R      # noqa: E402
import make_building as mb    # noqa: E402
import bake_light             # noqa: E402
from make_building import Canvas, Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, flat, cyl, KIT   # noqa: E402

ROOT = mb.ROOT
OX = -30.0                      # the model's origin in the world (x)
SHORE = 2.5
FACE = 0.6                      # the quay wall's face (local x)
LADDERS_Z = (-86.0, -40.0, 22.0, 70.0, 150.0, 39.0)   # (gen_riptide.py WATER_LADDERS_QUAY and the pontoon's ladder)

mb.PALETTE.update({
    # cast concrete (quay wall, parapet, blast walls): mid grey, weathered (owner: muted, mid-tone, nothing blinding)
    "rq_conc": "8d8b85", "rq_conc_dark": "7c7a74", "rq_conc_light": "99978f", "rq_conc_joint": "66645f",
    "rq_stain": "5d5a52",
    # the waterline: wet concrete, weed
    "rq_wet": "4c5048", "rq_wet_dark": "3b4039", "rq_weed": "3f4f37", "rq_weed_light": "4d5f42",
    # rubber, planks, crates
    "rq_rubber": "202122", "rq_rubber_light": "2c2d2f",
    "rq_plank": "6e604f", "rq_plank_dark": "5a4e41", "rq_plank_light": "7a6b59", "rq_plank_gap": "3a332c",
    "rq_crate": "8a6a45", "rq_crate_dark": "73583a", "rq_crate_light": "977651",
    # the quay cranes: a faded port blue (the ship's own cranes are yellow; containers red, blue and green)
    "rq_crane": "4f6a80", "rq_crane_dark": "445d70", "rq_crane_light": "5a768c",
    # corrugated sheeting (the pipe gallery, the huts), the barges' hulls
    "rq_corr": "868a8b", "rq_corr_dark": "7a7e7f", "rq_corr_light": "909495",
    "rq_barge": "3f4245", "rq_barge_light": "4a4d50",
})


def paint_conc(rng):
    """Cast concrete: 2 m pour lines, pitting, dark run-off stains."""
    c = Canvas(64, 64, "rq_conc")
    c.noise(0, 0, 64, 64, ["rq_conc_dark", "rq_conc_light"], 0.12, rng)
    R._seams(c, "rq_conc_joint", rows=(0, 32), cols=((0, 0, 64), (32, 0, 64)))
    c.blotch(["rq_conc_dark", "rq_stain"], 7, rng, size=(2, 5))
    R._streaks(c, ["rq_stain", "rq_conc_dark"], 8, rng, starts=(63, 31), length=(4, 12))
    return c


def paint_quay(rng):
    """The quay's face: big cast blocks (2 x 1 m, staggered), weathered, run-off streaks."""
    c = Canvas(64, 64, "rq_conc")
    c.noise(0, 0, 64, 64, ["rq_conc_dark", "rq_conc_light"], 0.12, rng)
    for row in range(4):
        y = row * 16
        for x in range(64):
            c.put(x, y, "rq_conc_joint")
        off = 16 if row % 2 else 0
        for x in (off, off + 32):
            for k in range(16):
                c.put(x % 64, y + k, "rq_conc_joint")
    c.blotch(["rq_conc_dark", "rq_stain"], 8, rng, size=(2, 5))
    R._streaks(c, ["rq_stain", "rq_conc_dark", "rp_rust"], 12, rng, starts=(63, 47, 31, 15), length=(4, 14))
    return c


def paint_wet(rng):
    """The tide band: wet, dark concrete with weed hanging from it."""
    c = Canvas(64, 64, "rq_wet")
    c.noise(0, 0, 64, 64, ["rq_wet_dark", "rq_weed"], 0.2, rng)
    for x in range(64):
        n = rng.randrange(6, 30)
        for k in range(n):
            if rng.random() < 0.8:
                c.put(x, k, rng.choice(["rq_weed", "rq_weed_light", "rq_wet_dark"]))
    R._seams(c, "rq_wet_dark", rows=(0, 32), cols=())
    return c


def paint_rubber(rng):
    c = Canvas(64, 64, "rq_rubber")
    c.noise(0, 0, 64, 64, ["rq_rubber_light", "rx_black"], 0.12, rng)
    return c


def paint_plank(rng):
    """Weathered deck planks (25 cm), gaps between them, nail lines, worn grey."""
    c = Canvas(64, 64, "rq_plank")
    for x in range(64):
        for y in range(64):
            if y % 4 == 0:
                c.put(x, y, "rq_plank_gap")
    c.noise(0, 0, 64, 64, ["rq_plank_dark", "rq_plank_light"], 0.18, rng)
    for y in range(64):
        if y % 4 == 0:
            for x in range(64):
                c.put(x, y, "rq_plank_gap")
    for x in (10, 42):
        for y in range(1, 64, 4):
            c.put(x, y, "rip_iron")
    c.blotch(["rq_plank_dark"], 6, rng, size=(2, 4))
    return c


def paint_crate(rng):
    """A crate's side: boards, a frame round it, a cross brace."""
    c = Canvas(64, 64, "rq_crate")
    c.noise(0, 0, 64, 64, ["rq_crate_dark", "rq_crate_light"], 0.15, rng)
    for y in range(0, 64, 8):
        for x in range(64):
            c.put(x, y, "rq_crate_dark")
    c.frame(0, 0, 63, 63, "rq_plank_gap")
    c.frame(1, 1, 62, 62, "rq_crate_dark")
    for k in range(4, 60):
        c.put(k, k, "rq_crate_dark")
        c.put(k + 1, k, "rq_crate_dark")
    c.blotch(["rq_plank_dark"], 4, rng, size=(2, 3))
    return c


def paint_crane(rng):
    """Crane paint: faded blue, chipped to primer, rust running from the bolted joints."""
    c = Canvas(64, 64, "rq_crane")
    c.noise(0, 0, 64, 64, ["rq_crane_dark", "rq_crane_light"], 0.1, rng)
    R._seams(c, "rq_crane_dark", rows=(0, 32), cols=())
    c.blotch(["rx_iron_light", "rq_crane_dark"], 6, rng, size=(2, 3))
    R._streaks(c, ["rp_rust", "rq_crane_dark"], 7, rng, starts=(63, 31), length=(3, 10))
    return c


def paint_corr(rng):
    """Corrugated sheeting (galvanised, gone dull): ribs every 25 cm, sheet joins, rust at the bottom."""
    c = Canvas(64, 64, "rq_corr")
    for x in range(64):
        col = ("rq_corr_dark", "rq_corr", "rq_corr_light", "rq_corr")[x % 4]
        for y in range(64):
            c.put(x, y, col)
    c.noise(0, 0, 64, 64, ["rq_corr"], 0.06, rng)
    R._seams(c, "rx_iron_light", rows=(0,), cols=((0, 0, 64), (32, 0, 64)))
    R._streaks(c, ["rp_rust", "rq_stain"], 10, rng, starts=(63,), length=(3, 12))
    return c


def paint_barge(rng):
    """A barge's side: dark grey plate, welded seams, rust everywhere it touches anything."""
    c = Canvas(64, 64, "rq_barge")
    c.noise(0, 0, 64, 64, ["rq_barge_light", "rx_black"], 0.1, rng)
    R._seams(c, "rx_black", rows=(0, 32), cols=((0, 0, 32), (32, 32, 64)))
    c.blotch(["rp_rust", "rh_rust"], 12, rng, size=(2, 5))
    R._streaks(c, ["rp_rust", "rh_rust"], 14, rng, starts=(63, 31), length=(4, 14))
    return c


KIT.update({"rq_conc": paint_conc, "rq_quay": paint_quay, "rq_wet": paint_wet, "rq_rubber": paint_rubber,
            "rq_plank": paint_plank, "rq_crate": paint_crate, "rq_crane": paint_crane, "rq_corr": paint_corr,
            "rq_barge": paint_barge})


# ------------------------------------------------------------------------------------------------ pieces
def member(m, p0, p1, w, mt):
    """A straight steel member from p0 to p1 (w square), out of reach: no collision, drawn whole."""
    d = [p1[k] - p0[k] for k in range(3)]
    L = math.sqrt(sum(v * v for v in d))
    mid = tuple((p0[k] + p1[k]) / 2 for k in range(3))
    yaw = math.degrees(math.atan2(d[0], d[2]))
    pitch = -math.degrees(math.atan2(d[1], math.sqrt(d[0] ** 2 + d[2] ** 2)))
    m.box(mid, (w, w, L), mat(mt), yaw=yaw, pitch=pitch, cull=False)


def bounds(row):
    c, s = row["pos"], row["size"]
    return [c[k] - s[k] / 2 for k in range(3)], [c[k] + s[k] / 2 for k in range(3)]


def quay_wall(m, row):
    """The face over the water: blocks above the tide band, the wet band, a concrete cap; fender pads every 8 m."""
    lo, hi = bounds(row)
    bands = ((-99.0, -1.2, "rq_wet"), (-1.2, 0.5, "rq_wet"), (0.5, SHORE - 0.25, "rq_quay"), (SHORE - 0.25, 99.0, "rq_conc"))
    R.band_face(m, (1, 0, 0), hi[0], lo[2], hi[2], lo[1], hi[1], bands)
    m.b.poly([(lo[0], hi[1], lo[2]), (lo[0], hi[1], hi[2]), (hi[0], hi[1], hi[2]), (hi[0], hi[1], lo[2])],
             (0, 1, 0), "rq_conc", uv_world())
    z = lo[2] + 6.0
    while z < hi[2] - 6.0:
        if not any(abs(z - lz) < 2.5 for lz in LADDERS_Z):
            m.box((hi[0] + 0.02, 0.9, z), (0.04, 1.8, 1.0), lambda n, mid, q: "rq_rubber", cull=False)
            m.box((hi[0] + 0.02, -0.5, z), (0.04, 0.6, 1.0), lambda n, mid, q: "rq_rubber", cull=False)
        z += 8.0


def parapet(m, row):
    """Concrete, its ends (at the gaps where the ways across and the ladders start) painted in hazard stripes."""
    def style(n, mid, q):
        if n[1] < -0.7:
            return None
        if abs(n[2]) > 0.7:
            return ("rip_hazard", uv_world(1.0))
        return "rq_conc"
    m.box(row["pos"], row["size"], style)


def crane(m, legs, head, boom):
    """A quay crane: four legs on the apron (hazard paint at the foot), portal beams and X braces from 6 m up, the
    machinery house on top, the operator's cab under its sea end, the lattice boom over the water, its trolley and
    the spreader hanging from it (all out of reach)."""
    for r in legs:
        lo, hi = bounds(r)
        m.box(r["pos"], r["size"], lambda n, mid, q: None if abs(n[1]) > 0.7 else
              (("rip_hazard", uv_world(1.0)) if mid[1] < SHORE + 1.2 else "rq_crane"))
    xs = sorted({round(r["pos"][0], 2) for r in legs})
    zs = sorted({round(r["pos"][2], 2) for r in legs})
    top = head["pos"][1] - head["size"][1] / 2
    for x in xs:            # the two side frames (along z, between each pair of legs)
        for y in (8.0, 15.0, top - 0.5):
            member(m, (x, y, zs[0] + 0.8), (x, y, zs[1] - 0.8), 0.5, "rq_crane")
        member(m, (x, 8.0, zs[0] + 0.8), (x, 15.0, zs[1] - 0.8), 0.3, "rq_crane")
        member(m, (x, 8.0, zs[1] - 0.8), (x, 15.0, zs[0] + 0.8), 0.3, "rq_crane")
    for z in zs:            # across the apron: only up high (lorries drive under)
        member(m, (xs[0] + 0.8, top - 0.5, z), (xs[1] - 0.8, top - 0.5, z), 0.6, "rq_crane")
        member(m, (xs[0] + 0.8, top - 4.0, z), (xs[1] - 0.8, top - 0.8, z), 0.3, "rq_crane")
        member(m, (xs[1] - 0.8, top - 4.0, z), (xs[0] + 0.8, top - 0.8, z), 0.3, "rq_crane")
    # the machinery house: blue below, a white house with a grey roof on top
    c, s = head["pos"], head["size"]
    m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else "rq_crane", cull=False)
    m.box((c[0] - 1.0, c[1] + s[1] / 2 + 1.3, c[2]), (s[0] - 3.0, 2.6, s[2] - 3.0),
          lambda n, mid, q: "rip_roof" if n[1] > 0.7 else (None if n[1] < -0.7 else "rip_white"), cull=False)
    # the operator's cab, under the sea end of the house
    cab = c[0] + s[0] / 2 - 1.4
    m.box((cab, top - 1.3, c[2] + 2.5), (2.2, 2.4, 2.4),
          lambda n, mid, q: "rip_roof" if n[1] > 0.7 else ("rip_glass" if n[0] > 0.7 or abs(n[2]) > 0.7 else "rq_crane"),
          cull=False)
    # the boom: a lattice of two side trusses over the water
    bc, bs = boom["pos"], boom["size"]
    x0, x1 = bc[0] - bs[0] / 2, bc[0] + bs[0] / 2
    y0, y1 = bc[1] - bs[1] / 2, bc[1] + bs[1] / 2
    for sz in (-1, 1):
        z = bc[2] + sz * (bs[2] / 2 - 0.1)
        member(m, (x0, y0, z), (x1, y0, z), 0.22, "rq_crane")
        member(m, (x0, y1, z), (x1, y1, z), 0.22, "rq_crane")
        k = 0
        x = x0
        while x < x1 - 0.5:
            xn = min(x1, x + 2.0)
            member(m, (x, y0, z), (x, y1, z), 0.14, "rq_crane")
            member(m, (x, y0 if k % 2 else y1, z), (xn, y1 if k % 2 else y0, z), 0.12, "rq_crane")
            x = xn
            k += 1
    x = x0
    while x < x1:
        member(m, (x, y0, bc[2] - bs[2] / 2 + 0.2), (x, y0, bc[2] + bs[2] / 2 - 0.2), 0.12, "rq_crane")
        x += 4.0
    # the boom's tip stays (from the house's top down to the tip: out of reach)
    for sz in (-1, 1):
        member(m, (c[0] + s[0] / 2 - 1.0, c[1] + s[1] / 2 + 2.4, c[2] + sz * 0.6), (x1 - 1.0, y1, bc[2] + sz * 0.6), 0.12,
               "rip_iron")
    # the trolley, its ropes and a spreader hanging over the water, well out of reach
    tx = x1 - 12.0
    m.box((tx, y0 - 0.4, bc[2]), (2.4, 0.8, 2.0), lambda n, mid, q: "rip_hazard" if abs(n[1]) < 0.7 else "rq_crane",
          cull=False)
    spread_y = y0 - 9.0
    for dz in (-0.6, 0.6):
        cyl(m.b, (tx, (y0 - 0.8 + spread_y + 0.3) / 2, bc[2] + dz), 0.03, (y0 - 0.8) - (spread_y + 0.3), "rip_iron", sides=4,
            caps=(False, False))
    m.box((tx, spread_y, bc[2]), (2.2, 0.5, 6.0), lambda n, mid, q: "rip_yellow" if abs(n[1]) < 0.7 else "rip_iron",
          cull=False)


def crate_style(n, mid, q):
    if n[1] < -0.7:
        return None
    return "rq_crate"


def concrete_style(n, mid, q):
    return None if n[1] < -0.7 else "rq_conc"


def plank_style(n, mid, q):
    if n[1] > 0.7:
        return "rq_plank"
    return "rip_iron"


def cover(m, row, kind, conts):
    """One piece of cover on the quay edge (gen_riptide.py quay_cover, by its kind)."""
    col, c, s = row["colour"], row["pos"], row["size"]
    yaw, pitch = row["yaw"], row["pitch"]
    if col in R.CONT_MAT:
        if yaw:
            m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else R.CONT_MAT[col], yaw=yaw)
        else:
            R.container(m, row, conts)
        return
    if kind == "cover3":                    # the watchman's hut: corrugated walls, a grey roof
        if col == "roof":
            m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else "rip_iron")
        else:
            m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_iron" if n[1] > 0.7 else "rq_corr"))
        return
    if kind == "cover4":                    # pipes between posts
        if s[1] > 2.0:
            m.box(c, s, mat("rip_iron"))
        else:
            cyl(m.b, tuple(c), min(s[0], s[1]) / 2 - 0.01, s[2], "rip_pipe", "rip_iron", axis="z", sides=10)
        return
    if kind == "cover5" and col == "rust":  # the wrecked lorry's cab
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rip_cont_a"), yaw=yaw)
        return
    if kind == "cover7" and col == "wood":  # cable drums: one on its side, one standing
        if s[1] > 2.0:
            r = min(s[1], s[2]) / 2 - 0.02
            cyl(m.b, (c[0], c[1] - s[1] / 2 + r, c[2]), r, s[0] - 0.05, "rq_plank", "rq_crate", axis="x", sides=14)
            cyl(m.b, (c[0], c[1] - s[1] / 2 + r, c[2]), r * 0.55, s[0] + 0.02, "rip_pipe", "rip_iron", axis="x", sides=10)
        else:
            r = min(s[0], s[2]) / 2 - 0.02
            cyl(m.b, tuple(c), r, s[1], "rq_plank", "rq_crate", axis="y", sides=14)
        return
    if col == "wood":
        m.box(c, s, crate_style, yaw=yaw, pitch=pitch)
        return
    if col in ("concrete", "rock"):
        m.box(c, s, concrete_style, yaw=yaw, pitch=pitch)
        return
    m.box(c, s, mat("rip_iron"), yaw=yaw, pitch=pitch)


def pier(m, row, conts):
    col, c, s = row["colour"], row["pos"], row["size"]
    lo, hi = bounds(row)
    if col in R.CONT_MAT:
        R.container(m, row, conts)
    elif col == "rust" and lo[1] < -10.0 and s[0] > 0.9 and s[2] > 0.9:   # the grain gallery's trestles
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else "rq_crane")
    elif col == "rust" and lo[1] < -10.0:        # a pile down to the sea bed
        cyl(m.b, tuple(c), min(s[0], s[2]) / 2, s[1], "rip_pipe", "rip_iron", axis="y", sides=8)
    elif col == "rust":                           # the pipe gallery's walls: corrugated sheeting
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_iron" if n[1] > 0.7 else "rq_corr"))
    elif col == "wall":                           # the pier shed: white painted plate
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_iron" if n[1] > 0.7 else "rip_white"))
    elif col == "roof":
        m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else "rq_corr")
    elif col == "metal" and not row["pitch"]:    # the grain gallery's steel floor and balcony
        m.box(c, s, lambda n, mid, q: "rip_deck" if n[1] > 0.7 else "rip_steel_in")
    elif col == "metal":
        m.box(c, s, R.ramp_style, yaw=row["yaw"], pitch=row["pitch"])
    elif col == "wood" and s[1] > 1.0 and not row["pitch"]:
        m.box(c, s, crate_style)
    else:
        m.box(c, s, plank_style, yaw=row["yaw"], pitch=row["pitch"])


def barge(m, row, conts):
    col, c, s = row["colour"], row["pos"], row["size"]
    lo, hi = bounds(row)
    if col in R.CONT_MAT:
        R.container(m, row, conts)
    elif col == "rust":                           # a barge's hull: dark plate, red below the waterline, a grey deck
        def style(n, mid, q):
            if n[1] > 0.7:
                return "rip_deck"
            if n[1] < -0.7:
                return None
            return "rip_hull_low" if mid[1] < 0.0 else "rq_barge"
        for y0, y1 in ((lo[1], 0.2), (0.2, hi[1])):
            m.box((c[0], (y0 + y1) / 2, c[2]), (s[0], y1 - y0, s[2]), style)
        # a fender of old tyres along each long side, flush with the plate
        for sz in (-1, 1):
            z = c[2] + sz * (s[2] / 2 + 0.02)
            x = lo[0] + 1.5
            while x < hi[0] - 1.0:
                flat(m.b, (0, 0, sz), z, x - 0.4, x + 0.4, 0.3, 1.0, "rq_rubber", uv_world())
                x += 3.0
    elif col == "wall":                           # a deck cabin
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rip_white"))
    else:
        m.box(c, s, plank_style, yaw=row["yaw"], pitch=row["pitch"])


def pontoon(m, row):
    c, s = row["pos"], row["size"]
    m.box(c, s, lambda n, mid, q: "rq_plank" if n[1] > 0.7 else (None if n[1] < -0.7 else "rq_rubber"))


def shade_rows(rows):
    """The boxes the light bake shades with: the crane's legs and boom are thin (no shade), the house shades."""
    out = []
    for row in rows:
        if row.get("kind") in ("crane_leg", "crane_boom", "crane_frame"):
            continue
        if row["pitch"] or row["yaw"]:
            continue
        if row["colour"] in R.CONT_MAT:
            row = dict(row, size=[max(0.05, v - 0.3) for v in row["size"]])
        out.append(row)
    return out


def build_quay(name="quay_front"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    assert data.get("map") == "riptide", f"{name}: not a Riptide model"
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = R.leviathan_decals(random.Random(name))       # (container doors and names)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    m.rng = random.Random(name)
    cranes = {}
    conts = 0
    for row in data["boxes"]:
        kind = row.get("kind")
        if kind in ("crane_leg", "crane_head", "crane_boom"):
            z = min((-96.0, -56.0, -16.0, 84.0, 140.0), key=lambda cz: abs(cz - row["pos"][2]))   # (its crane)
            cranes.setdefault(z, {"legs": []})
            if kind == "crane_leg":
                cranes[z]["legs"].append(row)
            else:
                cranes[z][kind] = row
        elif kind == "crane_frame":
            pass                                  # (0.36.42: collision for steelwork crane() draws)
        elif kind == "quay_wall":
            quay_wall(m, row)
        elif kind == "parapet":
            parapet(m, row)
        elif kind and kind.startswith("cover"):
            cover(m, row, kind, conts)
            conts += row["colour"] in R.CONT_MAT
        elif kind in ("pier", "gallery"):
            pier(m, row, conts)
            conts += row["colour"] in R.CONT_MAT
        elif kind == "barge":
            barge(m, row, conts)
            conts += row["colour"] in R.CONT_MAT
        elif kind == "pontoon":
            pontoon(m, row)
        elif row["colour"] in R.CONT_MAT:
            R.container(m, row, conts)
            conts += 1
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"), yaw=row["yaw"], pitch=row["pitch"])
    for cr in cranes.values():
        crane(m, cr["legs"], cr["crane_head"], cr["crane_boom"])
    b = m.b
    bake_light.CELL = 2.0
    bake_light.bake(b, shade_rows(data["boxes"]))
    cells = R.riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris
