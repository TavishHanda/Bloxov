"""Riptide art step 3 (0.36.19): `below_decks`, the Leviathan's two decks under the main deck. Origin (48, 0, 0), the
same as leviathan_hull, so both share coordinates (x across the ship, -18..18; z along it, bow -104 .. stern 110).

The hold deck (y -4): the cargo hold between two long bulkheads, a side passage down each side, the fore peak, the
workshops under the bridge tower and the stern ramp. The engine room deck (y -8): the pump room forward, the tank
deck (ballast tanks round the moon pool's well), the engine room aft. Also the bow stairwell (all its decks) and the
catwalk and rails round the moon pool on these two decks.

Steel inside, grey deck plate in the hold and green engine-room paint below; hazard bands along the foot of the hold's
bulkheads, frames round every door, a sign over each door naming where it goes, caged lamps on the ceilings, pipe runs
along the hull up out of reach, beams under the main deck over the hold. Furniture is gen_riptide.py's BELOW_PROPS
(boxes with a kind, drawn as the real thing inside each box); the engines, the ballast tanks and the sub bay's power
cabinet are the gray box's own boxes, drawn here.

    python3 art_source/scripts/make_riptide.py below_decks
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import make_riptide as R      # noqa: E402
import make_building as mb    # noqa: E402
import bake_light             # noqa: E402
import gen_riptide as G       # noqa: E402  (the outline of the hull: hull_half)
from make_building import Canvas, Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, flat, cyl, t_part, t_item, t_lamp, KIT   # noqa: E402

ROOT = mb.ROOT
OX = 48.0                       # the model's origin in the world (x)
A, B = -4.0, -8.0               # the hold deck, the engine room deck
DECK = 4.0
SLAB = 0.25
LAB2 = -18.25
HOLD_X = 12.0                   # the hold's bulkheads at x +-12 (world 36, 60)
STAIRS = (-4.0, 4.0, -88.0, -74.0)        # the bow stairwell (x0, x1, z0, z1)
T_STAIRS = (6.0, 14.0, 76.0, 90.0)        # the tower's stairwell (in bridge_tower)
MOON = (-10.0, 10.0, -9.0, 7.0)

mb.PALETTE.update({
    "rb_floor": "6c8072", "rb_floor_dark": "607367", "rb_floor_light": "778b7d",
    "rb_mach": "6f8577", "rb_mach_dark": "617568", "rb_mach_light": "7b9183",
    "rb_blue": "2f5f9e", "rb_cable": "2a2b2d",
})


def paint_floor_g(rng):
    """The engine room deck's floor: green deck paint over chequer plate, worn to steel along the walkways."""
    c = Canvas(64, 64, "rb_floor")
    for y in range(0, 64, 4):
        for x in range(0, 64, 4):
            c.put(x + (2 if (y // 4) % 2 else 0), y, "rb_floor_light")
            c.put(x + 1 + (2 if (y // 4) % 2 else 0), y + 1, "rb_floor_dark")
    R._seams(c, "rb_floor_dark", rows=(0, 32), cols=((0, 0, 64), (32, 0, 64)))
    c.blotch(["ri_dark", "rb_floor_dark"], 6, rng, size=(2, 5))
    return c


def paint_machine(rng):
    """Machinery green: smooth paint, a few chips, bolt heads along the edges."""
    c = Canvas(64, 64, "rb_mach")
    c.noise(0, 0, 64, 64, ["rb_mach_light", "rb_mach_dark"], 0.05, rng)
    for k in range(2, 64, 8):
        c.put(k, 1, "rb_mach_dark")
        c.put(k, 62, "rb_mach_dark")
    c.blotch(["rp_rust", "rb_mach_dark"], 4, rng, size=(1, 3))
    return c


KIT.update({"rip_floor_g": paint_floor_g, "rip_machine": paint_machine})


# ------------------------------------------------------------------------------------------------ where things are
def deck_of(y):
    """The deck a height belongs to: "A" (the hold deck), "B" (the engine room deck), "lab" or "main"."""
    if y >= DECK - 0.01:
        return "main"
    if y >= A - 0.01:
        return "A"
    if y >= B - 0.01:
        return "B"
    return "lab"


def in_rect(r, x, z, pad=0.0):
    return r[0] - pad <= x <= r[1] + pad and r[2] - pad <= z <= r[3] + pad


def place(x, y, z):
    """The name of the place a point is in (for the signs over the doors)."""
    d = deck_of(y)
    if in_rect(STAIRS, x, z):
        return "STAIRS"
    if d == "A":
        if z < -92.0:
            return "FORE PEAK"
        if z > 74.0:
            return "MACHINE SHOP" if x < -4.0 else "WORKSHOP"
        if x < -HOLD_X:
            return "PORT PASSAGE"
        if x > HOLD_X:
            return "STBD PASSAGE"
        return "CARGO HOLD"
    if d == "B":
        if z < -56.0:
            return "PUMP ROOM"
        if z < 30.0:
            return "TANK DECK"
        return "ENGINE ROOM"
    return None


PLACES = ["FORE PEAK", "MACHINE SHOP", "WORKSHOP", "PORT PASSAGE", "STBD PASSAGE", "CARGO HOLD", "PUMP ROOM",
          "TANK DECK", "ENGINE ROOM", "STAIRS", "SUB BAY POWER"]
LEVEL_NAMES = {DECK: "MAIN DECK", A: "HOLD DECK", B: "ENGINE DECK", LAB2: "SITE ZERO"}


# ------------------------------------------------------------------------------------------------ decals
def below_decals(rng):
    real = R.Atlas
    R.Atlas = lambda size=256: real(1024)     # (room for the tower's pictures and these)
    try:
        a = R.tower_decals(rng)   # (the furniture's drawers, screens, pegboards: the same pictures as the tower's)
    finally:
        R.Atlas = real
    for kind, line in R.CONTAINER_LINES.items():     # (the hold's containers: as on the deck)
        w, h, p = R._stencil(line, 3, "rw_light", random.Random(line), chip=0.1)
        a.add("line_" + kind, w, h, p)
    for kind, base in (("container_a", "rc_a"), ("container_b", "rc_b"), ("container_c", "rc_c")):
        a.add("doors_" + kind, 77, 83, R._door_decal(base))
    for name in PLACES:
        w, h, p = R._sign(name, "rw_white", "rx_black")
        a.add("place_" + name, w, h, p)
    for y, name in LEVEL_NAMES.items():
        w, h, p = R._stencil(name, 3, "rx_black", random.Random(name), chip=0.04)
        a.add("level_" + name, w, h, p)
    for name in ("HOLD 1", "HOLD 2", "PUMP ROOM", "ENGINE ROOM", "TANK DECK"):
        w, h, p = R._stencil(name, 5, "ry_yel", random.Random(name), chip=0.05)
        a.add("big_" + name, w, h, p)
    for name in ("FO 1", "FO 2", "FW 1", "FW 2", "BW 3", "BW 4", "BW 5", "BW 6"):
        w, h, p = R._stencil(name, 3, "rw_white", random.Random(name), chip=0.04)
        a.add("tank_" + name, w, h, p)
    w, h, p = R._stencil("EXION", 6, "rx_black", random.Random("exion"), chip=0.05)
    a.add("stencil_EXION", w, h, p)
    w, h, p = R._stencil("MUD", 4, "rx_black", random.Random("mud"), chip=0.05)
    a.add("stencil_MUD", w, h, p)
    w, h, p = R._sign("HIGH VOLTAGE", "ry_yel", "rx_black")
    a.add("high_voltage", w, h, p)
    w, h, p = R._sign("WEAR EAR DEFENDERS", "rb_blue", "rw_light")
    a.add("ear", w, h, p)
    w, h, p = R._sign("NO SMOKING", "rw_white", "rh_red")
    a.add("no_smoking_b", w, h, p)
    w, h, p = R._sign("MAX STACK 2 HIGH", "ry_yel", "rx_black")
    a.add("max_stack", w, h, p)

    def switchboard(c):        # 1 m x 2 m of switchboard: breaker doors, meters, a yellow warning triangle
        c.rect(0, 0, c.w, c.h, "tp_bright")
        for x0 in (0, c.w // 2):
            c.frame(x0, 0, x0 + c.w // 2, c.h, "tp_bright_dark")
            c.rect(x0 + 3, 4, x0 + c.w // 2 - 3, 12, "rx_iron")          # meters
            for k in range(2):
                cx = x0 + 6 + k * 9
                c.rect(cx, 6, cx + 5, 10, "tp_paper")
                c.put(cx + 2, 8, "rh_red")
            for row in range(5):                                      # breakers
                y = 18 + row * 8
                for k in range(3):
                    bx = x0 + 4 + k * 8
                    c.rect(bx, y, bx + 5, y + 5, "rx_iron")
                    c.rect(bx + 2, y + 1, bx + 3, y + 3, "rw_light" if (row + k) % 3 else "rh_red")
            c.rect(x0 + c.w // 2 - 6, 30, x0 + c.w // 2 - 4, 40, "rx_iron")   # handle
        for t in range(9):                                           # the warning triangle
            for x in range(c.w // 2 - t, c.w // 2 + t + 1):
                c.put(x, 54 + t, "ry_yel")
        c.rect(c.w // 2, 56, c.w // 2 + 1, 60, "rx_black")
    a.add("switchboard", 32, 64, switchboard)

    def genpanel(c):           # a generator's control panel: a screen, dials, buttons
        c.rect(0, 0, c.w, c.h, "rx_iron")
        c.frame(0, 0, c.w, c.h, "rx_black")
        c.rect(3, 3, 13, 9, "tp_screen")
        c.rect(4, 4, 9, 5, "tp_screen_on")
        for k in range(3):
            c.rect(16 + k * 4, 4, 18 + k * 4, 6, "tp_paper")
        c.rect(3, 12, 6, 14, "rh_red")
        c.rect(8, 12, 11, 14, "tp_screen_on")
    a.add("genpanel", 28, 16, genpanel)

    def cabinet(c):            # the sub bay's power cabinet: two doors, a big switch handle, a warning sign
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.frame(0, 0, c.w, c.h, "tp_bright_dark")
        c.rect(c.w // 2, 0, c.w // 2 + 1, c.h, "rx_iron")
        c.rect(c.w // 2 - 4, 26, c.w // 2 - 2, 38, "rx_iron")
        c.rect(c.w // 2 + 3, 26, c.w // 2 + 5, 38, "rx_iron")
        c.rect(c.w - 22, 10, c.w - 8, 22, "ry_yel")
        c.frame(c.w - 22, 10, c.w - 8, 22, "rx_black")
        c.rect(c.w - 16, 13, c.w - 14, 19, "rx_black")
    a.add("cabinet", 64, 64, cabinet)

    def extinguisher(c):       # a red extinguisher on its bracket, 0.3 x 0.7 m
        c.rect(0, 0, c.w, c.h, "clear")
        c.rect(2, 2, 8, 20, "rh_red")
        c.rect(3, 20, 7, 22, "rx_black")
        c.rect(4, 22, 9, 23, "rx_black")
        c.rect(3, 8, 7, 11, "rw_light")
    a.add("extinguisher", 10, 24, extinguisher)
    return a


# ------------------------------------------------------------------------------------------------ floors and walls
def floor_top(y):
    return "rip_floor_g" if deck_of(y + 0.01) == "B" else "rip_deck"


def slab_style(row):
    top = row["pos"][1] + row["size"][1] / 2

    def style(n, mid, corners):
        if n[1] > 0.7:
            return floor_top(top)
        if n[1] < -0.7:
            return "rip_steel_in"
        return ("rip_iron", uv_world(1.0))
    return style


def deck_curve(m, row):
    """A strip of deck in the shaped bow or stern: drawn out to the hull plate's inside along the line."""
    c, s = row["pos"], row["size"]
    za, zb = c[2] - s[2] / 2, c[2] + s[2] / 2
    top, bot = c[1] + s[1] / 2, c[1] - s[1] / 2
    ha, hb = G.hull_half(za) - 0.25, G.hull_half(zb) - 0.25
    m.b.poly([(-ha, top, za), (-hb, top, zb), (hb, top, zb), (ha, top, za)], (0, 1, 0), floor_top(top), uv_world())
    m.b.poly([(ha, bot, za), (hb, bot, zb), (-hb, bot, zb), (-ha, bot, za)], (0, -1, 0), "rip_steel_in", uv_world())


def wall_faces(row):
    """The four upright faces of a box: (n, at, a0, a1, y0, y1)."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    out = []
    for sg in (-1, 1):
        out.append(((sg, 0, 0), c[0] + sg * s[0] / 2, c[2] - s[2] / 2, c[2] + s[2] / 2, y0, y1))
        out.append(((0, 0, sg), c[2] + sg * s[2] / 2, c[0] - s[0] / 2, c[0] + s[0] / 2, y0, y1))
    return out


def face_pts(n, at, a0, a1, y0, y1):
    if n[0]:
        return [(at, y0, a0), (at, y0, a1), (at, y1, a1), (at, y1, a0)]
    return [(a0, y0, at), (a1, y0, at), (a1, y1, at), (a0, y1, at)]


def bulkhead(m, row, feet):
    """A steel bulkhead (the hold's walls, the engine room deck's): painted steel both sides, its top and ends dark;
    stiffeners every 2 m on the tall hold walls; a hazard band (hold) or dark skirting (below) along the foot."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    thin = 0 if s[0] < s[2] else 2
    m.box(c, s, lambda n, mid, q: None if abs(n[0 if thin == 0 else 2]) > 0.7 else ("rip_iron", uv_world(1.0)))
    for n, at, a0, a1, fy0, fy1 in wall_faces(row):
        if abs(n[thin]) < 0.7:
            continue
        pts = face_pts(n, at, a0, a1, fy0, fy1)
        mid = tuple(sum(p[k] for p in pts) / 4 for k in range(3))
        if m.hidden(n, mid, pts):
            continue
        flat(m.b, n, at, a0, a1, fy0, fy1, "rip_steel_in", uv_world())
        if abs(fy0 - round(fy0)) < 0.01 and deck_of(fy0 + 0.01) in ("A", "B"):
            feet.append((n, at, a0, a1, fy0))
        if s[1] > 5.0:          # the stiffeners: flat bars every 2 m (painted on: 1 cm proud)
            k = math.ceil(a0 / 2.0) * 2.0
            while k < a1 - 0.1:
                if k - 0.06 > a0:
                    t_item(m)
                    flat(m.b, n, at + (n[0] or n[2]) * 0.01, k - 0.06, k + 0.06, fy0 + 0.3, fy1, "rip_iron", uv_world(1.0))
                k += 2.0
            m.b.group = None


def stair_wall(m, row):
    """The bow stairwell's walls: white where they stand on the main deck outside, steel everywhere else."""
    c, s = row["pos"], row["size"]
    for n, at, a0, a1, y0, y1 in wall_faces(row):
        ax = 0 if n[0] else 2
        out_pt = (at + n[0] * 0.3, (a0 + a1) / 2) if n[0] else ((a0 + a1) / 2, at + n[2] * 0.3)
        outside = not in_rect(STAIRS, out_pt[0], out_pt[1])
        cuts = sorted({y0, y1} | {v for v in (DECK - SLAB, DECK) if y0 < v < y1})
        for lo, hi in zip(cuts, cuts[1:]):
            pts = face_pts(n, at, a0, a1, lo, hi)
            mid = tuple(sum(p[k] for p in pts) / 4 for k in range(3))
            if m.hidden(n, mid, pts):
                continue
            mt = "rip_white" if outside and lo >= DECK - 0.01 else "rip_steel_in"
            flat(m.b, n, at, a0, a1, lo, hi, mt, uv_world())
    # the top and the bottom
    m.box(c, s, lambda n, mid, q: ("rip_white" if mid[1] > DECK else "rip_iron", uv_world(1.0)) if abs(n[1]) > 0.7 else None)


def feet_bands(m, feet):
    for n, at, a0, a1, y0 in feet:
        d = deck_of(y0 + 0.01)
        if d == "A":
            flat(m.b, n, at + (n[0] or n[2]) * 0.011, a0, a1, y0, y0 + 0.3, "rip_hazard", uv_world())
        else:
            flat(m.b, n, at + (n[0] or n[2]) * 0.011, a0, a1, y0, y0 + 0.15, "rip_iron", uv_world(1.0))


# ------------------------------------------------------------------------------------------------ machinery
def engine(m, row, k):
    """A main engine (6 x 2.4 x 6, cover): a long block on a skid, a row of cylinder heads with red rocker covers, the
    exhaust manifold along the top, the flywheel housing at one end, the turbo at the other."""
    c, s = row["pos"], row["size"]
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    b = m.b
    t_item(m)
    t_part(m, x0, y0, z0, x1, y0 + 0.3, z1, "rip_iron")                   # the skid
    t_part(m, x0 + 0.6, y0 + 0.3, z0 + 0.9, x1 - 0.6, y0 + 1.7, z1 - 0.9, "rip_machine")   # the crankcase
    t_part(m, x0 + 1.0, y0 + 1.7, z0 + 1.0, x1 - 1.0, y0 + 1.95, z1 - 1.0, "rip_machine")
    n_cyl = 6
    for i in range(n_cyl):
        zc = z0 + 1.2 + (s[2] - 2.4) * (i + 0.5) / n_cyl
        t_part(m, c[0] - 0.75, y0 + 1.95, zc - 0.28, c[0] + 0.75, y0 + 2.12, zc + 0.28, "rip_machine")
        t_part(m, c[0] - 0.6, y0 + 2.12, zc - 0.22, c[0] + 0.6, y0 + 2.24, zc + 0.22, "rip_red")
    cyl(b, (c[0] + 0.95, y0 + 2.1, c[2]), 0.18, s[2] - 2.0, "rip_pipe", "rip_iron", axis="z", sides=8)   # the exhaust
    for i in range(n_cyl):
        zc = z0 + 1.2 + (s[2] - 2.4) * (i + 0.5) / n_cyl
        t_part(m, c[0] + 0.7, y0 + 2.0, zc - 0.07, c[0] + 0.9, y0 + 2.1, zc + 0.07, "rip_pipe")
    end = z0 if k % 2 else z1
    sg = -1 if k % 2 else 1
    cyl(b, (c[0], y0 + 1.1, end - sg * 0.55), 0.8, 0.9, "rip_machine", "rip_iron", axis="z", sides=12)  # flywheel housing
    cyl(b, (c[0] + 0.9, y0 + 1.85, end - sg * (s[2] - 0.6)), 0.4, 0.6, "rip_pipe", "rip_iron", axis="z", sides=10)  # turbo
    for side in (-1, 1):                                                     # the walkway grating along each side
        xa = x0 if side < 0 else x1 - 0.6
        t_part(m, xa, y0 + 0.3, z0, xa + 0.6, y0 + 0.36, z1, "rip_iron")
    flat(b, (0, 0, sg), end + sg * 0.006, c[0] - 0.7, c[0] + 0.7, y0 + 0.35, y0 + 0.85, "decals", m.d("genpanel"))
    b.group = None


def ballast_tank(m, row, k):
    """A tank lying along the ship (3 x 2 x 4): a drum on two saddles, iron bands, a manhole, its stencil."""
    c, s = row["pos"], row["size"]
    y0 = c[1] - s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    r = min(s[0], s[1]) / 2 - 0.05
    b = m.b
    t_item(m)
    for zz in (z0 + 0.6, z1 - 0.8):
        t_part(m, c[0] - r * 0.8, y0, zz, c[0] + r * 0.8, y0 + 0.5, zz + 0.2, "rip_iron")
    body = "rip_machine" if k % 2 else "rip_white"
    cyl(b, (c[0], y0 + r + 0.05, c[2]), r, s[2] - 0.1, body, body, axis="z", sides=12)
    for zz in (z0 + 0.5, z1 - 0.5):
        cyl(b, (c[0], y0 + r + 0.05, zz), r + 0.02, 0.08, "rip_iron", axis="z", sides=12, caps=(False, False))
    names = ["FO 1", "FO 2", "FW 1", "FW 2", "BW 3", "BW 4", "BW 5", "BW 6"]
    nm = "tank_" + names[k % len(names)]
    for sg in (-1, 1):                                                       # the stencil on the end facing the room
        flat(b, (0, 0, sg), c[2] + sg * (s[2] / 2 - 0.04), c[0] - 0.5, c[0] + 0.5, y0 + r - 0.15, y0 + r + 0.2,
             "graffiti", m.d(nm))
    b.group = None


def power_cabinet(m, row):
    c, s = row["pos"], row["size"]
    x0 = c[0] - s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    t_item(m)
    t_part(m, x0, y0, z0, x0 + s[0], y0 + 0.1, z1, "rip_iron")
    t_part(m, x0, y0 + 0.1, z0, x0 + s[0], y1, z1, "rip_bright")
    flat(m.b, (-1, 0, 0), x0 - 0.006, z0 + 0.2, z1 - 0.2, y0 + 0.2, y1 - 0.1, "decals", m.d("cabinet"))
    R.t_sign(m, "z", x0 - 0.006, -1, c[2], y1 + 0.15, "place_SUB BAY POWER", 1.6)
    m.b.group = None


# ------------------------------------------------------------------------------------------------ the hold's cargo
# (0.36.20, owner: containers don't make sense in a drillship's hold) the gray box's container-sized stacks, drawn as
# a drillship's own cargo. Each fills its box (it is solid): 2.6 m a layer.
def cargo(m, row, k):
    c, s = row["pos"], row["size"]
    kind = row["kind"]
    along = 0 if s[0] >= s[2] else 2
    L, W = s[along], s[2 - along]
    y0 = c[1] - s[1] / 2
    layers = max(1, round(s[1] / 2.6))
    lh = s[1] / layers
    b = m.b
    ax = "x" if along == 0 else "z"

    def P(a, y, w):
        """A point a along the stack, w across it, from its middle."""
        return (c[0] + a, y, c[2] + w) if along == 0 else (c[0] + w, y, c[2] + a)

    def part(a0, a1, ya, yb, w0, w1, mt):
        p0, p1 = P(a0, ya, w0), P(a1, yb, w1)
        t_part(m, min(p0[0], p1[0]), ya, min(p0[2], p1[2]), max(p0[0], p1[0]), yb, max(p0[2], p1[2]), mt)
    t_item(m)
    if kind == "risers":                      # riser joints on yellow frames: 2 across, 2 high a layer
        r = min(W / 4, lh / 4) - 0.02
        for layer in range(layers):
            ly = y0 + layer * lh
            for fa in (-L / 2 + 0.3, -0.12, L / 2 - 0.54):            # the frames: posts and cross bars
                for w0 in (-W / 2, W / 2 - 0.12):
                    part(fa, fa + 0.24, ly, ly + lh, w0, w0 + 0.12, "rip_iron")
                for yy in (ly, ly + lh / 2 - 0.05, ly + lh - 0.1):
                    part(fa, fa + 0.24, yy, yy + 0.1, -W / 2, W / 2, "rip_iron")
            for row_ in range(2):
                for col in range(2):
                    w = -W / 2 + W / 4 + col * W / 2
                    cy = ly + lh / 4 + row_ * lh / 2
                    p = P(0.0, cy, w)
                    cyl(b, p, r, L - 0.05, "rip_yellow", "rip_iron", axis=ax, sides=10)
                    for band in (-L / 2 + 0.6, L / 2 - 0.6):            # the joints' collars
                        cyl(b, P(band, cy, w), r + 0.03, 0.2, "rip_iron", axis=ax, sides=10, caps=(False, False))
    elif kind == "mud":                        # pallets of drilling mud: sacks shrink-wrapped, two pallets high a layer
        n = max(1, int(L // 1.45))
        step = L / n
        for layer in range(2 * layers):
            ly = y0 + layer * lh / 2
            for i in range(n):
                a0 = -L / 2 + i * step + 0.03
                a1 = a0 + step - 0.06
                part(a0, a1, ly, ly + 0.14, -W / 2 + 0.03, W / 2 - 0.03, "rip_wood")      # the pallet
                part(a0 + 0.04, a1 - 0.04, ly + 0.14, ly + lh / 2 - 0.02, -W / 2 + 0.06, W / 2 - 0.06, "rip_card")
                # sack seams: dark lines across the wrapped block, both long sides
                for sg in (-1, 1):
                    wf = sg * (W / 2 - 0.06 + 0.006)
                    for hy in (ly + 0.14 + (lh / 2 - 0.16) / 3, ly + 0.14 + 2 * (lh / 2 - 0.16) / 3):
                        p0, p1 = P(a0 + 0.04, hy, wf), P(a1 - 0.04, hy + 0.03, wf)
                        n3 = (0, 0, sg) if along == 0 else (sg, 0, 0)
                        if along == 0:
                            flat(b, n3, p0[2], p0[0], p1[0], hy, hy + 0.03, "rip_iron", uv_world(1.0))
                        else:
                            flat(b, n3, p0[0], p0[2], p1[2], hy, hy + 0.03, "rip_iron", uv_world(1.0))
            # the stencil on one long side of each pallet layer's middle pallet
        for layer in range(2 * layers):
            ly = y0 + layer * lh / 2
            sg = 1 if k % 2 else -1
            wf = sg * (W / 2 - 0.06 + 0.008)
            if along == 0:
                flat(b, (0, 0, sg), c[2] + wf, c[0] - 0.55, c[0] + 0.55, ly + 0.45, ly + 0.8, "graffiti", m.d("stencil_MUD"))
            else:
                flat(b, (sg, 0, 0), c[0] + wf, c[2] - 0.55, c[2] + 0.55, ly + 0.45, ly + 0.8, "graffiti", m.d("stencil_MUD"))
    else:                                      # Exion's equipment crates: one big crate a layer, battens, the stencil
        for layer in range(layers):
            ly = y0 + layer * lh
            part(-L / 2, L / 2, ly + 0.02, ly + lh - 0.02, -W / 2, W / 2, "rip_wood")
            for a in (-L / 2, -L / 6, L / 6, L / 2):                    # battens round it
                aa = min(max(a - 0.06, -L / 2 - 0.02), L / 2 - 0.1)
                part(aa, aa + 0.12, ly + 0.02, ly + lh - 0.02, -W / 2 - 0.02, W / 2 + 0.02, "rip_wood")
            for yy in (ly + 0.08, ly + lh - 0.16):
                part(-L / 2 - 0.01, L / 2 + 0.01, yy, yy + 0.08, -W / 2 - 0.015, W / 2 + 0.015, "rip_iron")
            for sg in (-1, 1):
                wf = sg * (W / 2 + 0.03)
                if along == 0:
                    flat(b, (0, 0, sg), c[2] + wf, c[0] - 1.2, c[0] + 1.2, ly + 0.8, ly + 1.5, "graffiti", m.d("stencil_EXION"))
                else:
                    flat(b, (sg, 0, 0), c[0] + wf, c[2] - 1.2, c[2] + 1.2, ly + 0.8, ly + 1.5, "graffiti", m.d("stencil_EXION"))
    b.group = None


# ------------------------------------------------------------------------------------------------ furniture
BELOW_KINDS = ("reel", "forklift", "lathe", "manifold", "panel", "tank", "generator")


def b_prop(m, row):
    kind = row["kind"]
    c, s = row["pos"], row["size"]
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    b = m.b
    axis, sg = R._against(row)
    t_item(m)
    if kind == "reel":                       # a cable drum on its side: two wooden flanges, black cable wound on
        along = "z" if s[2] >= s[0] else "x"
        L = s[2] if along == "z" else s[0]
        r = min(s[1], s[0] if along == "z" else s[2]) / 2 - 0.02
        for e in (-1, 1):
            p = (c[0], y0 + r + 0.01, c[2] + e * (L / 2 - 0.06)) if along == "z" else (c[0] + e * (L / 2 - 0.06), y0 + r + 0.01, c[2])
            cyl(b, p, r, 0.1, "rip_wood", "rip_wood", axis=along, sides=12)
        cyl(b, (c[0], y0 + r + 0.01, c[2]), r * 0.7, L - 0.2, "rip_iron", axis=along, sides=12, caps=(False, False))
        t_part(m, x0 + 0.1, y0, z0 + 0.1, x1 - 0.1, y0 + 0.08, z1 - 0.1, "rip_wood")     # the pallet under it
    elif kind == "forklift":                 # forks to the north (-z), counterweight aft
        t_part(m, x0 + 0.1, y0 + 0.2, z0 + 0.9, x1 - 0.1, y0 + 1.05, z1 - 0.05, "rip_yellow")   # the body
        t_part(m, x0 + 0.15, y0 + 0.2, z1 - 0.55, x1 - 0.15, y0 + 1.25, z1, "rip_iron")       # the counterweight
        t_part(m, x0 + 0.35, y0 + 1.05, z0 + 1.6, x1 - 0.35, y0 + 1.45, z0 + 2.0, "rip_navy")   # the seat
        for wx in (x0 + 0.12, x1 - 0.12):                                                    # wheels
            for wz in (z0 + 1.15, z1 - 0.45):
                cyl(b, (wx, y0 + 0.28, wz), 0.27, 0.22, "rip_iron", axis="x", sides=10)
        for mx in (x0 + 0.25, x1 - 0.35):                                                    # the mast
            t_part(m, mx, y0 + 0.1, z0 + 0.78, mx + 0.1, y1 - 0.15, z0 + 0.9, "rip_iron")
        t_part(m, x0 + 0.25, y0 + 0.3, z0 + 0.74, x1 - 0.25, y0 + 0.9, z0 + 0.78, "rip_iron")  # the carriage
        for fx in (x0 + 0.3, x1 - 0.42):                                                     # the forks
            t_part(m, fx, y0 + 0.05, z0, fx + 0.12, y0 + 0.1, z0 + 0.78, "rip_iron")
        for px in (x0 + 0.12, x1 - 0.18):                                                    # the overhead guard
            for pz in (z0 + 1.0, z1 - 0.6):
                t_part(m, px, y0 + 1.05, pz, px + 0.06, y1 - 0.06, pz + 0.06, "rip_iron")
        t_part(m, x0 + 0.1, y1 - 0.06, z0 + 0.95, x1 - 0.1, y1, z1 - 0.55, "rip_iron")
    elif kind == "lathe":                    # along z: two pedestals, the bed, the headstock and chuck, the tailstock
        t_part(m, x0 + 0.1, y0, z0 + 0.1, x1 - 0.1, y0 + 0.75, z0 + 0.9, "rip_machine")
        t_part(m, x0 + 0.1, y0, z1 - 0.8, x1 - 0.1, y0 + 0.75, z1 - 0.1, "rip_machine")
        t_part(m, x0 + 0.05, y0 + 0.7, z0 + 0.05, x1 - 0.05, y0 + 0.78, z1 - 0.05, "rip_iron")   # the chip tray
        t_part(m, x0 + 0.3, y0 + 0.78, z0 + 0.1, x1 - 0.3, y0 + 0.95, z1 - 0.1, "rip_iron")    # the bed
        t_part(m, x0 + 0.15, y0 + 0.95, z0 + 0.1, x1 - 0.15, y1, z0 + 0.9, "rip_machine")      # the headstock
        cyl(b, (c[0], y0 + 1.1, z0 + 1.0), 0.16, 0.2, "rip_iron", axis="z", sides=8)          # the chuck
        t_part(m, x0 + 0.35, y0 + 0.95, z1 - 0.7, x1 - 0.35, y0 + 1.2, z1 - 0.2, "rip_machine")  # the tailstock
        t_part(m, x0 + 0.3, y0 + 0.95, z0 + 1.8, x1 - 0.3, y0 + 1.1, z0 + 2.3, "rip_iron")      # the carriage
    elif kind == "manifold":                 # two pipes along a stand, valves on top, a gauge
        along = "x" if s[0] >= s[2] else "z"
        L = s[0] if along == "x" else s[2]
        for k in range(int(L // 2) + 1):                                                     # the stands
            a = -L / 2 + 0.1 + k * (L - 0.2) / max(1, int(L // 2))
            if along == "x":
                t_part(m, c[0] + a - 0.04, y0, z0 + 0.1, c[0] + a + 0.04, y0 + 0.95, z1 - 0.1, "rip_iron")
            else:
                t_part(m, x0 + 0.1, y0, c[2] + a - 0.04, x1 - 0.1, y0 + 0.95, c[2] + a + 0.04, "rip_iron")
        for off, r, mt in ((-0.18, 0.13, "rip_pipe"), (0.18, 0.11, "rip_red")):
            p = (c[0], y0 + 0.75, c[2] + off) if along == "x" else (c[0] + off, y0 + 0.75, c[2])
            cyl(b, p, r, L, mt, "rip_iron", axis=along, sides=8)
        for k in range(max(2, int(L // 1.5))):
            a = -L / 2 + (k + 0.5) * L / max(2, int(L // 1.5))
            p = (c[0] + a, c[2]) if along == "x" else (c[0], c[2] + a)
            cyl(b, (p[0], y0 + 1.0, p[1]), 0.03, 0.25, "rip_iron", sides=6)
            cyl(b, (p[0], y1 - 0.03, p[1]), 0.17, 0.04, "rip_red" if k % 2 else "rip_yellow", sides=10)
    elif kind == "panel":                    # a switchboard against the wall
        t_part(m, x0, y0, z0, x1, y0 + 0.1, z1, "rip_iron")
        t_part(m, x0, y0 + 0.1, z0, x1, y1, z1, "rip_bright")
        L = s[2] if axis == "x" else s[0]
        n = max(1, int(L // 1.0))
        for k in range(n):
            a0 = (z0 if axis == "x" else x0) + k * L / n
            if axis == "x":
                at = x1 + 0.006 if sg > 0 else x0 - 0.006
                flat(b, (sg, 0, 0), at, a0 + 0.04, a0 + L / n - 0.04, y0 + 0.15, y1 - 0.05, "decals", m.d("switchboard"))
            else:
                at = z1 + 0.006 if sg > 0 else z0 - 0.006
                flat(b, (0, 0, sg), at, a0 + 0.04, a0 + L / n - 0.04, y0 + 0.15, y1 - 0.05, "decals", m.d("switchboard"))
    elif kind == "tank":                     # an upright tank on legs, a band, a domed top
        r = min(s[0], s[2]) / 2 - 0.03
        for lx in (-0.5, 0.5):
            for lz in (-0.5, 0.5):
                t_part(m, c[0] + lx * r - 0.04, y0, c[2] + lz * r - 0.04, c[0] + lx * r + 0.04, y0 + 0.4, c[2] + lz * r + 0.04, "rip_iron")
        cyl(b, (c[0], (y0 + 0.4 + y1 - 0.2) / 2, c[2]), r, y1 - 0.2 - y0 - 0.4, "rip_white", "rip_iron", sides=12)
        cyl(b, (c[0], y1 - 0.1, c[2]), r * 0.7, 0.2, "rip_white", "rip_white", sides=12)
        cyl(b, (c[0], y0 + 1.6, c[2]), r + 0.02, 0.08, "rip_iron", sides=12, caps=(False, False))
    elif kind == "generator":                # a skid, the engine, the alternator, the radiator, its panel
        along = "x" if s[0] >= s[2] else "z"
        t_part(m, x0, y0, z0, x1, y0 + 0.2, z1, "rip_iron")
        if along == "x":
            t_part(m, x0 + 0.1, y0 + 0.2, z0 + 0.2, x0 + 0.5, y1 - 0.05, z1 - 0.2, "rip_iron")      # the radiator
            t_part(m, x0 + 0.5, y0 + 0.2, z0 + 0.3, x1 - 0.9, y0 + 1.3, z1 - 0.3, "rip_machine")
            cyl(b, (x1 - 0.5, y0 + 0.75, c[2]), 0.5, 0.75, "rip_machine", "rip_iron", axis="x", sides=12)
            flat(b, (0, 0, 1), z1 - 0.3 + 0.006, c[0] - 0.6, c[0] + 0.2, y0 + 0.6, y0 + 1.1, "decals", m.d("genpanel"))
        else:
            t_part(m, x0 + 0.2, y0 + 0.2, z0 + 0.1, x1 - 0.2, y1 - 0.05, z0 + 0.5, "rip_iron")
            t_part(m, x0 + 0.3, y0 + 0.2, z0 + 0.5, x1 - 0.3, y0 + 1.3, z1 - 0.9, "rip_machine")
            cyl(b, (c[0], y0 + 0.75, z1 - 0.5), 0.5, 0.75, "rip_machine", "rip_iron", axis="z", sides=12)
            flat(b, (1, 0, 0), x1 - 0.3 + 0.006, c[2] - 0.6, c[2] + 0.2, y0 + 0.6, y0 + 1.1, "decals", m.d("genpanel"))
    b.group = None


# ------------------------------------------------------------------------------------------------ details
def door_frame(m, o):
    """Dark steel frames round a door through a bulkhead, both faces."""
    a0, a1, y0, y1, t = o["a0"], o["a1"], o["y0"], o["y1"], o["t"]
    fw, fd = 0.1, 0.04
    t_item(m)
    for sg in (-1, 1):
        face = o["at"] + sg * t / 2
        for pa, pb, ya, yb in ((a0 - fw, a0, y0, y1 + fw), (a1, a1 + fw, y0, y1 + fw), (a0 - fw, a1 + fw, y1, y1 + fw)):
            if o["axis"] == "x":
                m.box(((pa + pb) / 2, (ya + yb) / 2, face + sg * fd / 2), (pb - pa, yb - ya, fd), mat("rip_iron"), cull=False)
            else:
                m.box((face + sg * fd / 2, (ya + yb) / 2, (pa + pb) / 2), (fd, yb - ya, pb - pa), mat("rip_iron"), cull=False)
    m.b.group = None


def is_door(o):
    return o["y1"] - o["y0"] > 1.9 and o["t"] >= 0.25


def door_signs(m, o):
    """Over a door, on each face: the name of the place it leads into (STAIRS / the deck's name on a stairwell)."""
    mid = (o["a0"] + o["a1"]) / 2
    top = o["y1"] + 0.16
    y = o["y0"] + 0.1
    for sg in (-1, 1):
        face = o["at"] + sg * o["t"] / 2
        if o["axis"] == "x":
            here, there = (mid, face + sg * 0.5), (mid, face - sg * (o["t"] + 0.5))
        else:
            here, there = (face + sg * 0.5, mid), (face - sg * (o["t"] + 0.5), mid)
        stair_here = in_rect(STAIRS, here[0], here[1])
        stair_there = in_rect(STAIRS, there[0], there[1])
        if stair_here:
            level = min(LEVEL_NAMES, key=lambda v: abs(v - o["y0"]))
            if abs(level - o["y0"]) > 0.3:
                continue
            name, width = "level_" + LEVEL_NAMES[level], 1.4
        elif stair_there:
            name, width = "place_STAIRS", 0.9
        else:
            p = place(there[0], y, there[1])
            if p is None:
                continue
            name, width = "place_" + p, 1.1 if len(p) < 10 else 1.4
        R.t_sign(m, o["axis"], face, sg, mid, top, name, width)


def ceiling_at(rows, x, z, y_top):
    """Is there a slab whose underside is at y_top - SLAB over (x, z)?"""
    for r in rows:
        if r["pitch"] or r["yaw"] % 180 or r.get("kind") == "hull_curve":
            continue
        c, s = r["pos"], r["size"]
        if abs(c[1] + s[1] / 2 - y_top) > 0.02 or s[1] > 0.6:
            continue
        if abs(x - c[0]) <= s[0] / 2 and abs(z - c[2]) <= s[2] / 2:
            return True
    return False


def lamps(m, hull_rows):
    """Caged bulkhead lamps on the ceilings: down both side passages and the hold (under the main deck), the
    workshops; over the engine room deck under the hold's floor. None over a hole or in a stairwell."""
    rows = m.data["boxes"]
    spots = []
    for z in range(-88, 104, 6):
        for x in (-15.0, -6.0, 6.0, 15.0):
            spots.append((x, DECK, float(z), hull_rows))
        for x in (-12.5, 0.0, 12.5):
            spots.append((x, A, float(z) + 3.0, rows))
    for x, top, z, src in spots:
        if in_rect(STAIRS, x, z, 0.6) or in_rect(T_STAIRS, x, z, 0.6) or in_rect(MOON, x, z, 0.8):
            continue
        if abs(x) > G.hull_half(z) - 1.5:
            continue
        if not ceiling_at(src, x, z, top):
            continue
        if not all(ceiling_at(src, x + dx, z + dz, top) for dx in (-0.8, 0.8) for dz in (-0.3, 0.3)):
            continue
        y = top - SLAB
        if top == DECK:
            if abs(x) < HOLD_X and -92 < z < 74:
                y -= 0.5        # (under the beams over the hold)
        t_lamp(m, x, y, z, 0.8, 0.3)
        # the cage: two dark bars across the lamp
        for dz in (-0.18, 0.18):
            m.box((x, y - 0.04, z + dz), (0.9, 0.05, 0.04), mat("rip_iron"), cull=False)


def hold_beams(m, hull_rows):
    """Deep beams across the hold under the main deck every 6 m (8 m over the floor: out of reach), where the deck
    is over them."""
    for z in range(-90, 74, 6):
        if -9.5 < z < 7.5:
            continue
        xs = [x / 2 for x in range(-24, 25)]
        run = last = None
        for x in xs + [None]:
            ok = x is not None and ceiling_at(hull_rows, x, z, DECK) and ceiling_at(hull_rows, x, z + 0.25, DECK) \
                and ceiling_at(hull_rows, x, z - 0.25, DECK) and not in_rect(STAIRS, x, z, 0.3)
            if ok:
                if run is None:
                    run = x
                last = x
            elif run is not None:
                # (ends at the last spot with deck over it: 0.36.22, a run reaching the hold's east side used to end
                # at the loop's end marker, x 99, and stuck 85 m out of the ship over the sea)
                if last - run > 0.6:
                    t_item(m)
                    m.box(((run + last) / 2, DECK - SLAB - 0.25, z), (last - run, 0.5, 0.3), mat("rip_iron"), cull=False)
                run = None
                m.b.group = None


def hull_pipes(m):
    """Pipe runs along the hull's inside in both side passages and on the engine room deck, up out of reach; broken
    round the companionways, the ladders' holes and the hull doors."""
    b = m.b
    runs = [  # (side, y, (gaps in z))
        (-1, A + 3.0, [(-60.0, -38.0), (2.0, 9.0)]),
        (1, A + 3.0, [(52.0, 74.0), (-86.0, -82.0), (42.0, 46.0)]),
        (-1, B + 3.3, [(-62.0, -58.0), (48.0, 52.0)]),
        (1, B + 3.3, [(-62.0, -58.0), (48.0, 52.0), (94.0, 101.0)]),
    ]
    for side, y, gaps in runs:
        lo, hi = (-91.5, 73.5) if y > A else (-92.0, 104.5)
        cuts = [lo] + [v for g in sorted(gaps) for v in g] + [hi]
        for za, zb in zip(cuts[0::2], cuts[1::2]):
            if zb - za < 1.0:
                continue
            t_item(m)
            for off, r, yy, mt in ((0.22, 0.09, y, "rip_pipe"), (0.48, 0.12, y + 0.05, "rip_red" if y > A else "rip_machine"),
                                   (0.22, 0.07, y + 0.3, "rip_yellow")):
                x = side * (18.0 - 0.25 - off)
                cyl(b, (x, yy, (za + zb) / 2), r, zb - za, mt, "rip_iron", axis="z", sides=6)
            z = za + 0.3
            while z < zb:                                                   # brackets
                m.box((side * (18.0 - 0.25 - 0.35), y + 0.1, z), (0.6, 0.06, 0.06), mat("rip_iron"), cull=False)
                z += 3.0
            b.group = None


def overhead_pipes(m):
    """Pipe runs under the hold's floor down the engine room deck (3.3 m up: out of reach), broken where the ceiling
    has a hole; brackets every 3 m."""
    rows = m.data["boxes"]
    b = m.b
    for x, r, y, mt in ((-6.0, 0.16, B + 3.3, "rip_pipe"), (-6.45, 0.1, B + 3.35, "rip_yellow"), (6.0, 0.14, B + 3.3, "rip_red"),
                        (6.4, 0.1, B + 3.35, "rip_pipe")):
        run = None
        z = -92.0
        while z <= 104.0:
            ok = all(ceiling_at(rows, x + dx, z, A) for dx in (-0.4, 0.4)) and not in_rect(T_STAIRS, x, z, 0.5) \
                and not in_rect(STAIRS, x, z, 0.5) and not in_rect(MOON, x, z, 0.5)
            if ok and run is None:
                run = z
            if (not ok or z + 0.5 > 104.0) and run is not None:
                if z - run > 1.5:
                    t_item(m)
                    cyl(b, (x, y, (run + z) / 2), r, z - run, mt, "rip_iron", axis="z", sides=6)
                    k = run + 1.0
                    while k < z - 0.5:
                        m.box((x, y + (A - SLAB - y) / 2, k), (0.06, A - SLAB - y, 0.06), mat("rip_iron"), cull=False)
                        k += 3.0
                    b.group = None
                run = None
            z += 0.5


def floor_marks(m):
    """Yellow lines painted round the engines and the pumps (keep clear), on the floor."""
    b = m.b
    for row in m.data["boxes"]:
        k = classify(row)
        if not (k == "engine" or row.get("kind") in ("machine", "generator") and deck_of(row["pos"][1]) == "B"):
            continue
        c, s = row["pos"], row["size"]
        y0 = c[1] - s[1] / 2
        if deck_of(y0 + 0.01) != "B":
            continue
        d = 0.5
        x0, x1 = c[0] - s[0] / 2 - d, c[0] + s[0] / 2 + d
        z0, z1 = c[2] - s[2] / 2 - d, c[2] + s[2] / 2 + d
        y = y0 + 0.012
        for xa, xb, za, zb in ((x0, x1, z0, z0 + 0.1), (x0, x1, z1 - 0.1, z1), (x0, x0 + 0.1, z0, z1), (x1 - 0.1, x1, z0, z1)):
            b.poly([(xa, y, za), (xb, y, za), (xb, y, zb), (xa, y, zb)], (0, 1, 0), "rip_yellow", uv_world(1.0))


def wall_signs(m):
    """Big stencils on the walls, safety signs, extinguishers."""
    b = m.b
    hx = HOLD_X - 0.15
    for z, name in ((-46.0, "HOLD 1"), (28.0, "HOLD 2")):
        for x, n in ((-hx, 1), (hx, -1)):
            reg = m.decals.regions["big_" + name]
            aspect = (reg[3] - reg[1]) / (reg[2] - reg[0])
            w = 4.0
            flat(b, (n, 0, 0), x + n * 0.012, z - w / 2, z + w / 2, A + 2.4, A + 2.4 + w * aspect, "graffiti", m.d("big_" + name))
    # on the engine room deck's bulkheads: the room's name over the middle, both sides
    for zf, n, name in ((-56.15, -1, "PUMP ROOM"), (-55.85, 1, "TANK DECK"), (29.85, -1, "TANK DECK"), (30.15, 1, "ENGINE ROOM")):
        reg = m.decals.regions["big_" + name]
        aspect = (reg[3] - reg[1]) / (reg[2] - reg[0])
        w = 3.6
        flat(b, (0, 0, n), zf + n * 0.012, 4.0 - w / 2, 4.0 + w / 2, B + 2.3, B + 2.3 + w * aspect, "graffiti", m.d("big_" + name))
    R.t_sign(m, "x", 30.15, 1, -9.0, B + 1.4, "ear", 1.6)
    R.t_sign(m, "x", 29.85, -1, -9.0, B + 1.4, "ear", 1.6)
    R.t_sign(m, "x", -56.15, -1, 2.0, B + 1.4, "no_smoking_b", 1.0)
    for x, n in ((-hx, 1), (hx, -1)):
        R.t_sign(m, "z", x, n, -27.0, A + 1.6, "max_stack", 1.8)
    # extinguishers by the doors (flat on the wall, 1 cm out)
    for o in m.data["openings"]:
        if not is_door(o) or in_rect(STAIRS, o["at"] if o["axis"] == "z" else (o["a0"] + o["a1"]) / 2,
                                      o["at"] if o["axis"] == "x" else (o["a0"] + o["a1"]) / 2, 0.5):
            continue
        sg = 1
        face = o["at"] + sg * o["t"] / 2
        a = o["a1"] + 0.45
        n = (sg, 0, 0) if o["axis"] == "z" else (0, 0, sg)
        flat(b, n, face + sg * 0.012, a, a + 0.3, o["y0"] + 0.5, o["y0"] + 1.2, "graffiti", m.d("extinguisher"))
    # HIGH VOLTAGE over each switchboard
    for row in m.data["boxes"]:
        if row.get("kind") == "panel":
            c, s = row["pos"], row["size"]
            axis, sg = R._against(row)
            if axis == "x":
                R.t_sign(m, "z", c[0] - sg * s[0] / 2, sg, c[2], c[1] + s[1] / 2 + 0.1, "high_voltage", 1.2)
            else:
                R.t_sign(m, "x", c[2] - sg * s[2] / 2, sg, c[0], c[1] + s[1] / 2 + 0.1, "high_voltage", 1.2)


# ------------------------------------------------------------------------------------------------ the model
def classify(row):
    c, s, col = row["pos"], row["size"], row["colour"]
    if row.get("kind") == "deck_curve":
        return "deck_curve"
    if row.get("kind") in ("risers", "mud", "equip"):
        return "cargo"
    if row.get("kind") in BELOW_KINDS:
        return "below_prop"
    if row.get("kind"):
        return "tower_prop"
    if row["pitch"]:
        return "ramp"
    if col in R.CONT_MAT:
        return "container"
    if col == "rust":
        if abs(s[0] - 6.0) < 0.05 and abs(s[1] - 2.4) < 0.05:
            return "engine"
        if abs(s[0] - 3.0) < 0.05 and abs(s[1] - 2.0) < 0.05:
            return "tank"
        return "rail"
    if col == "metal":
        if abs(s[0] - 3.5) < 0.05 and abs(s[2] - 4.0) < 0.05:
            return "cabinet"
        if s[1] <= 0.3:
            return "slab"
        if min(s[0], s[2]) <= 0.35:
            return "bulkhead"
        return "slab"
    if col == "concrete":
        return "slab"
    if col == "wall":
        return "stair_wall"
    if col == "roof":
        return "roof"
    return "plain"


def build_below(name="below_decks"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    with open(os.path.join(ROOT, "art_source", "buildings", "leviathan_hull.json")) as f:
        hull_rows = json.load(f)["boxes"]
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = below_decals(random.Random(name))
    decal_png = os.path.join(ROOT, "art_source", "textures", name + "_decals.png")
    if os.path.exists(decal_png):
        os.remove(decal_png)                  # (the signs are made here: paint them again every time)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    m.rng = random.Random(name)
    feet = []
    conts = engines = tanks = 0
    for row in data["boxes"]:
        k = classify(row)
        if k == "deck_curve":
            deck_curve(m, row)
        elif k == "below_prop":
            b_prop(m, row)
        elif k == "tower_prop":
            R.t_prop(m, row)
        elif k == "ramp":
            m.box(row["pos"], row["size"], R.ramp_style, yaw=row["yaw"], pitch=row["pitch"])
        elif k == "cargo":
            cargo(m, row, conts)
            conts += 1
        elif k == "container":
            R.container(m, row, conts)
            conts += 1
        elif k == "engine":
            engine(m, row, engines)
            engines += 1
        elif k == "tank":
            ballast_tank(m, row, tanks)
            tanks += 1
        elif k == "rail":
            R.rail(m, row)
        elif k == "cabinet":
            power_cabinet(m, row)
        elif k == "slab":
            m.box(row["pos"], row["size"], slab_style(row))
        elif k == "bulkhead":
            bulkhead(m, row, feet)
        elif k == "stair_wall":
            stair_wall(m, row)
        elif k == "roof":
            m.box(row["pos"], row["size"], lambda n, mid, q: "rip_roof" if n[1] > 0.7 else ("rip_steel_in" if n[1] < -0.7 else "rip_white"))
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"))
    feet_bands(m, feet)
    for o in data["openings"]:
        if is_door(o):
            door_frame(m, o)
            door_signs(m, o)
    lamps(m, hull_rows)
    hold_beams(m, hull_rows)
    hull_pipes(m)
    overhead_pipes(m)
    floor_marks(m)
    wall_signs(m)
    b = m.b
    bake_light.CELL = 2.5                     # (two big decks: bigger cells keep it in budget)
    bake_light.DARK = 0.68                     # (lit by its lamps; the hatches and the moon pool let the day in)
    shade = [r for r in data["boxes"] if not r["pitch"] and r.get("kind") != "deck_curve"]
    shade += [r for r in R.shade_rows(hull_rows) if not r["pitch"] and not r["yaw"] % 180]
    print("faces before the bake", sum(len(f) - 2 for f in b.faces))
    bake_light.bake(b, shade)
    cells = R.riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris


if __name__ == "__main__":
    build_below()
