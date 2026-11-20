"""Riptide shore art, pass 2 (owner 2026-11-19: "yes" to the terminal and the Harbor Tower): `harbor_plaza`. Origin
(-100, 0, -40); this script works in world metres and moves everything by the origin.

The Harbor Tower (six floors of offices in pale grey block, a concrete band at every floor, its two stairwells, a
parapet round the roof, HARBOR TOWER on top), the customs hall (sandstone block, two floors inside), the canteen (buff
block) and the garage (corrugated sheeting), the gatehouse and the gate's truck bay, the road, the lorries, the barriers
and the bus shelter; the container terminal's stacks and its gantry crane (the quay cranes' faded blue).

Inside: painted panel walls, lino floors, tiled ceilings with lamps in the tower; the customs hall's tiles and
counters; the canteen's tiles; the garage's bare concrete. Every opening gets a dark frame, outside windows a concrete
sill. Nothing is drawn that a person can walk into without a gray box behind it.

    python3 art_source/scripts/make_riptide.py harbor_plaza
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_riptide as R      # noqa: E402
import make_riptide_quay as Q  # noqa: E402  (its kits: concrete, corrugated sheeting, crane blue)
import make_building as mb    # noqa: E402
import bake_light             # noqa: E402
from make_building import Atlas, Canvas, Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, flat, cyl, KIT   # noqa: E402

ROOT = mb.ROOT
OX, OZ = -100.0, -40.0          # the model's origin in the world
SHORE = 2.5
SLAB = 0.25
TOWER_FLOORS = [SHORE + 3.5 * f for f in range(6)]
TOWER_TOP = TOWER_FLOORS[-1] + 3.5

# name: (footprints [(x0, x1, z0, z1)], outside, walls inside, floor, ceiling, ground floor overlay)
BUILDINGS = {
    "tower": ([(-124.0, -92.0, -30.0, -10.0)], "rs_block_grey", "rip_panel", "rip_lino", "rip_ceiling", "rip_tile"),
    "stairs": ([(-132.0, -124.0, -30.0, -16.0), (-92.0, -84.0, -24.0, -10.0)], "rs_block_grey", "rq_conc", "rq_conc",
               "rq_conc", None),
    "customs": ([(-76.0, -48.0, -14.0, 16.0)], "rs_sandstone", "rip_panel_g", "rip_lino", "rip_ceiling", "rip_lino"),
    "canteen": ([(-124.0, -102.0, 8.0, 24.0)], "rs_block_buff", "rip_panel", "rip_tile", "rip_ceiling", "rip_tile"),
    "garage": ([(-96.0, -80.0, 12.0, 30.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", "rq_conc"),
    "gatehouse": ([(-172.0, -167.0, -11.0, -6.0)], "rq_corr", "rip_panel", "rip_lino", "rip_ceiling", "rip_lino"),
}

mb.PALETTE.update({
    "rs_grey": "8f8e89", "rs_grey_dark": "7f7e79", "rs_grey_light": "9a9994", "rs_grey_joint": "6b6a66",
    "rs_sand": "9c8f74", "rs_sand_dark": "8b7f66", "rs_sand_light": "a69a80", "rs_sand_joint": "6f6553",
    "rs_buff": "9a8a70", "rs_buff_dark": "8a7b63", "rs_buff_light": "a4957b", "rs_buff_joint": "6c6150",
    "rs_tar": "3e4042", "rs_tar_dark": "343638", "rs_tar_light": "47494b", "rs_line": "b3ad8f",
    "rs_navy": "2c3e57",
})


def _blocks(base):
    def paint(rng):
        """Masonry blocks (50 x 25 cm, staggered), weathered: soot under the joints, a few chipped blocks."""
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [base + "_dark", base + "_light"], 0.12, rng)
        for row in range(16):
            y = row * 4
            for x in range(64):
                c.put(x, y, base + "_joint")
            off = 4 if row % 2 else 0
            for x in range(off, 64, 8):
                for k in range(4):
                    c.put(x, y + k, base + "_joint")
        for _ in range(10):                      # a few blocks a shade off the rest
            bx, by = rng.randrange(8) * 8 + (4 if rng.random() < 0.5 else 0), rng.randrange(16) * 4
            col = rng.choice([base + "_dark", base + "_light"])
            for yy in range(by + 1, by + 4):
                for xx in range(bx + 1, bx + 8):
                    c.put(xx % 64, yy, col)
        R._streaks(c, ["rq_stain", base + "_dark"], 8, rng, starts=(63, 31), length=(4, 12))
        return c
    return paint


def paint_tar(rng):
    """Asphalt: dark, patched, cracked."""
    c = Canvas(64, 64, "rs_tar")
    c.noise(0, 0, 64, 64, ["rs_tar_dark", "rs_tar_light"], 0.2, rng)
    c.blotch(["rs_tar_dark", "rs_tar_light"], 8, rng, size=(3, 8))
    for _ in range(4):
        x, y = rng.randrange(64), rng.randrange(64)
        for k in range(rng.randrange(6, 16)):
            c.put(x % 64, y % 64, "rx_black")
            x += rng.choice((0, 1))
            y += 1
    return c


def paint_plinth(rng):
    """The dark concrete base round a building, splashed with grime."""
    c = Canvas(64, 64, "rq_conc_dark")
    c.noise(0, 0, 64, 64, ["rq_stain", "rq_conc_joint"], 0.15, rng)
    R._seams(c, "rq_conc_joint", rows=(0,), cols=((0, 0, 64), (32, 0, 64)))
    return c


KIT.update({"rs_block_grey": _blocks("rs_grey"), "rs_sandstone": _blocks("rs_sand"), "rs_block_buff": _blocks("rs_buff"),
            "rs_tar": paint_tar, "rs_plinth": paint_plinth})


SIGNS = {"tower": "HARBOR TOWER", "customs": "CUSTOMS", "canteen": "CANTEEN", "garage": "GARAGE", "gate": "GATE 1",
         "authority": "PORT AUTHORITY", "terminal": "TERMINAL 2"}


# (0.36.40) the tower's rooms, floor by floor: (NW, NE, SW, SE); the signs go over each room's corridor door
ROOMS = [("POST ROOM", "GOODS IN", "RECEPTION", "SECURITY"), ("OFFICES", "HARBOR MASTER", "BREAK ROOM", "WASHROOM"),
         ("ARCHIVE", "RECORDS", "PRINT ROOM", "WASHROOM"), ("MEETING ROOM", "OFFICES", "KITCHEN", "RADIO ROOM"),
         ("DIRECTOR", "BOARDROOM", "SECRETARY", "WASHROOM"), ("HARBOR CONTROL", "TRAFFIC CONTROL", "RADIO ROOM", "STORES")]
ROOM_DOORS = [(-120.0, -20.5 + 0.15, 1), (-97.0, -20.5 + 0.15, 1), (-114.0, -15.0 - 0.15, -1), (-100.0, -15.0 - 0.15, -1)]
FLOOR_NAMES = ["GROUND FLOOR"] + ["FLOOR %d" % f for f in range(1, 6)]
PROP_KINDS = {"shelves", "crates", "console", "desk", "files", "counter", "sofa", "mess_table", "fridge", "stove", "tv",
              "bench", "radio", "stalls", "chart_table"}


def plaza_decals(rng):
    real = R.Atlas
    R.Atlas = lambda size=256: real(1024)
    try:
        a = R.tower_decals(rng)            # (the furniture's drawers, screens, monitors: the ship tower's pictures)
    finally:
        R.Atlas = real
    for kind, line in R.CONTAINER_LINES.items():
        w, h, p = R._stencil(line, 3, "rw_light", random.Random(line), chip=0.1)
        a.add("line_" + kind, w, h, p)
    for kind, base in (("container_a", "rc_a"), ("container_b", "rc_b"), ("container_c", "rc_c")):
        a.add("doors_" + kind, 77, 83, R._door_decal(base))
    for name in sorted({n for f in ROOMS for n in f} | {"ROOF", "STAIRS"} | {FLOOR_NAMES[f] for f in range(6)}):
        w, h, p = R._sign(name, "rw_white", "rx_black", 2)
        a.add("room_" + name, w, h, p)
    for k, text in SIGNS.items():
        bg, fg = ("rs_navy", "rw_white") if k in ("tower", "authority", "terminal") else ("rw_white", "rx_black")
        w, h, p = R._sign(text, bg, fg, 3 if k == "tower" else 2)
        a.add("sign_" + k, w, h, p)
    return a


# ------------------------------------------------------------------------------------------------ helpers
def W(p):
    """World metres -> the model's."""
    return (p[0] - OX, p[1], p[2] - OZ)


def world(p):
    return (p[0] + OX, p[1], p[2] + OZ)


def where(p):
    """The building whose footprint holds world point p (x, z), and which piece of it."""
    for name, info in BUILDINGS.items():
        for x0, x1, z0, z1 in info[0]:
            if x0 - 0.01 <= p[0] <= x1 + 0.01 and z0 - 0.01 <= p[2] <= z1 + 0.01:
                return name
    return None


def top_of(kind):
    return {"tower": TOWER_TOP, "stairs": TOWER_TOP + 3.45, "customs": SHORE + 9.0, "canteen": SHORE + 4.0,
            "garage": SHORE + 5.0, "gatehouse": SHORE + 2.8}.get(kind, 99.0)


def band_list(kind, outside):
    """An outside wall's bands: a dark plinth, the building's own face, a concrete band at every floor of the tower."""
    out = [(-99.0, SHORE + 0.5, "rs_plinth" if outside != "rq_corr" else "rq_corr"), (SHORE + 0.5, 99.0, outside)]
    if kind in ("tower", "stairs"):
        bands = [(SHORE + 0.5, TOWER_FLOORS[1] - SLAB, outside)]
        for f, y in enumerate(TOWER_FLOORS[1:]):
            nxt = TOWER_FLOORS[f + 2] - SLAB if f + 2 < len(TOWER_FLOORS) else TOWER_TOP - SLAB
            bands += [(y - SLAB - 0.1, y + 0.1, "rq_conc"), (y + 0.1, nxt, outside)]
        bands += [(TOWER_TOP - SLAB - 0.1, 99.0, "rq_conc")]
        out = [out[0]] + bands
    return out


def building_piece(m, row, kind, outside_faces):
    """A wall or slab of a building: outside faces are collected and drawn in bands, the rest painted here."""
    c, s = row["pos"], row["size"]
    if row["pitch"]:                                 # (a stair flight)
        m.box(c, s, lambda n, mid, q: "rq_conc", yaw=row["yaw"], pitch=row["pitch"])
        return
    if row["colour"] == "wood":                      # a counter
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_wood" if n[1] > 0.7 else "rip_panel"))
        return
    info = BUILDINGS.get(kind)

    def style(n, mid, corners):
        wm = world(mid)
        here = where(wm) or kind
        inf = BUILDINGS.get(here, info)
        if n[1] > 0.7:
            if wm[1] >= top_of(here) - 0.3:
                return "rip_roof" if s[1] < 0.5 else "rq_conc"
            return inf[3] if inf else "rq_conc"
        if n[1] < -0.7:
            if wm[1] < SHORE + 0.1:
                return None
            return inf[4] if inf else "rq_conc"
        out = (wm[0] + n[0] * 0.25, wm[1], wm[2] + n[2] * 0.25)
        if where(out) is None or wm[1] > top_of(here) - 0.05:
            outside_faces.append((n, mid, corners, here))
            return None
        return inf[2] if inf else "rq_conc"
    m.box(c, s, style)


def outside_bands(m, faces):
    for n, mid, corners, kind in faces:
        axis_i = 0 if n[0] else 2
        other = 2 if n[0] else 0
        a0, a1 = min(q[other] for q in corners), max(q[other] for q in corners)
        y0, y1 = min(q[1] for q in corners), max(q[1] for q in corners)
        R.band_face(m, n, mid[axis_i], a0, a1, y0, y1, band_list(kind, (BUILDINGS.get(kind) or next(iter(BUILDINGS.values())))[1]))


def frame(m, o):
    """A dark frame round an opening on both faces; a concrete sill under a window's outside."""
    a0, a1, y0, y1, t = o["a0"], o["a1"], o["y0"], o["y1"], o["t"]
    fw, fd = 0.1, 0.04
    if y1 - y0 < 1.5:
        return                                   # (the gap in the roof's parapet: no frame)
    window = not any(0.0 <= y0 - lv < 0.3 for lv in TOWER_FLOORS + [SHORE + 4.5, TOWER_TOP])
    for sg in (-1, 1):
        face = o["at"] + sg * t / 2
        pieces = [(a0 - fw, a0, y0 - (fw if window else 0), y1 + fw), (a1, a1 + fw, y0 - (fw if window else 0), y1 + fw),
                  (a0 - fw, a1 + fw, y1, y1 + fw)]
        if window:
            pieces.append((a0 - fw, a1 + fw, y0 - fw, y0))
        for pa, pb, ya, yb in pieces:
            if o["axis"] == "x":
                m.box(((pa + pb) / 2, (ya + yb) / 2, face + sg * fd / 2), (pb - pa, yb - ya, fd), mat("rip_iron"))
            else:
                m.box((face + sg * fd / 2, (ya + yb) / 2, (pa + pb) / 2), (fd, yb - ya, pb - pa), mat("rip_iron"))
        if window:
            mid = ((a0 + a1) / 2, y0, face) if o["axis"] == "x" else (face, y0, (a0 + a1) / 2)
            wm = world((mid[0] + (0 if o["axis"] == "x" else sg * 0.3), y0, mid[2] + (sg * 0.3 if o["axis"] == "x" else 0)))
            if where(wm) is None:
                if o["axis"] == "x":
                    m.box(((a0 + a1) / 2, y0 - fw - 0.04, face + sg * 0.06), (a1 - a0 + 0.3, 0.08, 0.12), mat("rq_conc"))
                else:
                    m.box((face + sg * 0.06, y0 - fw - 0.04, (a0 + a1) / 2), (0.12, 0.08, a1 - a0 + 0.3), mat("rq_conc"))


def sign(m, name, n, at, a_mid, y, width):
    rect = m.decals.regions["sign_" + name]
    u0, v0, u1, v1 = rect
    h = width * (v1 - v0) / (u1 - u0)
    flat(m.b, n, at + (n[0] + n[2]) * 0.015, a_mid - width / 2, a_mid + width / 2, y, y + h, "decals", m.d("sign_" + name))


def details(m):
    """Signs, lamps and the floors laid over the ground inside."""
    b = m.b
    for name, info in BUILDINGS.items():
        if info[5]:
            for x0, x1, z0, z1 in info[0]:
                p = [W((x0, SHORE + 0.005, z0)), W((x1, SHORE + 0.005, z0)), W((x1, SHORE + 0.005, z1)), W((x0, SHORE + 0.005, z1))]
                b.poly([p[0], p[3], p[2], p[1]], (0, 1, 0), info[5], uv_world())
    # signs (world: the tower's north face is z -30, its west x -124; the customs hall's east face x -48)
    X = lambda x: x - OX    # noqa: E731
    Z = lambda z: z - OZ    # noqa: E731
    sign(m, "tower", (0, 0, -1), Z(-30.0 - 0.15), X(-108.0), TOWER_TOP - 2.9, 12.0)
    sign(m, "tower", (0, 0, 1), Z(-10.0 + 0.15), X(-108.0), TOWER_TOP - 2.9, 12.0)
    sign(m, "authority", (0, 0, 1), Z(-10.0 + 0.15), X(-119.0), SHORE + 2.9, 3.6)
    sign(m, "customs", (1, 0, 0), X(-48.0 + 0.15), Z(2.6), SHORE + 5.4, 4.0)
    sign(m, "customs", (0, 0, -1), Z(-14.0 - 0.15), X(-62.0), SHORE + 3.0, 3.6)
    sign(m, "canteen", (0, 0, -1), Z(8.0 - 0.15), X(-113.0), SHORE + 2.8, 3.6)
    sign(m, "garage", (0, 0, -1), Z(12.0 - 0.15), X(-88.0), SHORE + 4.15, 3.2)
    sign(m, "gate", (0, 0, 1), Z(-6.0 + 0.15), X(-169.5), SHORE + 2.25, 1.8)
    # ceiling lamps
    for f, y in enumerate(TOWER_FLOORS):
        ceil = y + 3.5 - SLAB
        for z in (-25.25, -17.75, -12.5):
            for x in range(-120, -94, 6):
                R.t_lamp(m, X(x + 0.0), ceil, Z(z))
    for x in (-70.0, -62.0, -54.0):
        for z in (-8.0, 2.0, 12.0):
            R.t_lamp(m, X(x), SHORE + 4.5 - SLAB, Z(z), 1.6, 0.4)
            R.t_lamp(m, X(x), SHORE + 9.0, Z(z), 1.6, 0.4)
    for x in (-118.0, -108.0):
        for z in (12.0, 20.0):
            R.t_lamp(m, X(x), SHORE + 4.0, Z(z))
    for z in (16.0, 24.0):
        R.t_lamp(m, X(-88.0), SHORE + 5.0, Z(z), 1.6, 0.4)


def gantry(m, row):
    c, s = row["pos"], row["size"]
    if s[1] > 20.0:                                # a leg: hazard paint at the foot
        m.box(c, s, lambda n, mid, q: None if abs(n[1]) > 0.7 else
              (("rip_hazard", uv_world(1.0)) if mid[1] < SHORE + 1.2 else "rq_crane"))
    elif s[0] > 6.0 and s[2] > 6.0:                # the trolley
        m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else ("rip_hazard" if abs(n[1]) < 0.7 else "rq_crane"))
    else:
        m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else "rq_crane")


def open_cont(m, row, k):
    """(0.38.2) A container you can walk into (gen_riptide.py open_container): corrugated walls and roof inside and
    out, a plank floor, the corner posts, the doors swung right back against the sides at each open end, the shut
    end's doors drawn on it."""
    c, s, kind = row["pos"], row["size"], row["colour"]
    body = R.CONT_MAT[kind]
    ends = row["kind"][5:]                       # "2", "1p" or "1n"
    ax = 0 if s[0] > s[2] else 2                 # along
    cx = 2 - ax                                  # across
    L, W, H, t = s[ax], s[cx], s[1], 0.1
    y0 = c[1] - H / 2

    def P(a, b, y):                              # a along, b across (from the centre), y up
        q = [0.0, y, 0.0]
        q[ax], q[cx] = c[ax] + a, c[cx] + b
        return tuple(q)

    def S(a, b):
        q = [0.0, 0.0, 0.0]
        q[ax], q[cx] = a, b
        return q

    def bx(a, b, y, sa, sb, sy, style):
        size = S(sa, sb)
        size[1] = sy
        m.box(P(a, b, y), tuple(size), style, cull=False)
    shell = lambda n, mid, q: (body, uv_world())
    for sg in (-1, 1):                           # the long walls, the roof
        bx(0.0, sg * (W / 2 - t / 2), y0 + H / 2, L - 0.04, t, H - 0.04, shell)
    bx(0.0, 0.0, y0 + H - t / 2, L - 0.04, W - 2 * t, t, lambda n, mid, q: (body, uv_world()) if n[1] > 0.7 else "rip_steel_in")
    bx(0.0, 0.0, y0 + 0.03, L - 0.3, W - 2 * t, 0.06, mat("rip_wood"))       # the floor
    open_ends = (-1, 1) if ends == "2" else ((1,) if ends == "1p" else (-1,))
    for e in (-1, 1):
        if e in open_ends:                       # (the door leaves are their own boxes: ocont_door)
            pass
        else:                                    # the shut end: steel inside, its doors outside
            bx(e * (L / 2 - t / 2), 0.0, y0 + (H - t) / 2, t, W - 2 * t, H - t,
               lambda n, mid, q: "rip_iron")
            nrm = [0, 0, 0]
            nrm[ax] = e
            flat(m.b, tuple(nrm), c[ax] + e * (L / 2 + 0.005), c[cx] - W / 2 + 0.16, c[cx] + W / 2 - 0.16, y0 + 0.16,
                 y0 + H - 0.16, "decals", m.d("doors_" + kind))
    for ea in (-1, 1):                           # corner posts, the top and bottom rails
        for eb in (-1, 1):
            bx(ea * (L / 2 - 0.08), eb * (W / 2 - 0.08), y0 + H / 2, 0.16, 0.16, H, mat("rip_iron"))
    for yy in (y0 + 0.08, y0 + H - 0.08):
        for sg in (-1, 1):
            bx(0.0, sg * (W / 2 - 0.06), yy, L - 0.32, 0.12, 0.16, mat("rip_iron"))
    for sg in (-1, 1):                           # the line's name on the long sides
        nrm = [0, 0, 0]
        nrm[cx] = sg
        flat(m.b, tuple(nrm), c[cx] + sg * (W / 2 + 0.005), c[ax] - 1.55, c[ax] + 1.55, y0 + 0.35 + H / 2,
             y0 + 0.85 + H / 2, "graffiti", m.d("line_" + kind))


def truck(m, row, conts):
    c, s, yaw = row["pos"], row["size"], row["yaw"]
    if row["colour"] in R.CONT_MAT:                # the trailer's box
        body = R.CONT_MAT[row["colour"]]
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else body, yaw=yaw)
    else:                                          # the cab: white, a dark glass band round its top
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rip_white"), yaw=yaw)
        top = c[1] + s[1] / 2
        m.box((c[0], top - 0.55, c[2]), (s[0] + 0.02, 0.7, s[2] + 0.02),
              lambda n, mid, q: None if abs(n[1]) > 0.7 else "rq_rubber", yaw=yaw, cull=False)


def kiosk(m, row):
    """The road's checkpoint booth and kiosks (solid): corrugated sides, a dark shuttered window band, a flat roof."""
    c, s = row["pos"], row["size"]
    m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rq_corr"))
    y0, y1 = c[1] - s[1] / 2 + 1.1, c[1] - s[1] / 2 + 1.9
    m.box((c[0], (y0 + y1) / 2, c[2]), (s[0] + 0.04, y1 - y0, s[2] + 0.04),
          lambda n, mid, q: None if abs(n[1]) > 0.7 else "rq_rubber", cull=False)
    m.box((c[0], c[1] + s[1] / 2 + 0.06, c[2]), (s[0] + 0.3, 0.12, s[2] + 0.3), lambda n, mid, q: "rip_iron", cull=False)


_M = [None]


def against(row):
    """Which way a piece of furniture faces (into the room): away from the wall behind it."""
    c, s = row["pos"], row["size"]
    m = _M[0]

    def blocked(p):
        return m.inside(p) or where(world(p)) is None
    if s[0] < s[2]:
        return ("x", 1 if blocked((c[0] - s[0] / 2 - 0.25, c[1], c[2])) else -1)
    return ("z", 1 if blocked((c[0], c[1], c[2] - s[2] / 2 - 0.25)) else -1)


def room_signs(m):
    for f, y in enumerate(TOWER_FLOORS):
        for (x, z, sg), name in zip(ROOM_DOORS, ROOMS[f]):
            u0, v0, u1, v1 = m.decals.regions["room_" + name]
            width = min(1.9, (u1 - u0) * 1024 / 72.0)
            h = width * (v1 - v0) / (u1 - u0)
            lo = y + 2.55
            flat(m.b, (0, 0, sg), z - OZ + sg * 0.01, x - OX - width / 2, x - OX + width / 2, lo, lo + h, "decals",
                 m.d("room_" + name))
    # the corridor: the floor's name by the stairs (west end, north wall), a clock (south wall)
    for f, y in enumerate(TOWER_FLOORS):
        nm = "room_" + FLOOR_NAMES[f]
        u0, v0, u1, v1 = m.decals.regions[nm]
        width = (u1 - u0) * 1024 / 72.0
        flat(m.b, (0, 0, 1), -20.5 + 0.15 + 0.01 - OZ, -121.5 - OX, -121.5 + width - OX, y + 1.5,
             y + 1.5 + width * (v1 - v0) / (u1 - u0), "decals", m.d(nm))
        flat(m.b, (0, 0, -1), -15.0 - 0.15 - 0.01 - OZ, -108.2 - OX, -107.8 - OX, y + 2.2, y + 2.6, "decals", m.d("clock"))
    # the roof door (stairwell A's top landing, facing east onto the roof) and the stair doors' signs
    u0, v0, u1, v1 = m.decals.regions["room_ROOF"]
    width = 0.7
    flat(m.b, (1, 0, 0), -124.0 + 0.15 + 0.01 - OX, -28.5 - width / 2 - OZ, -28.5 + width / 2 - OZ, TOWER_TOP + 2.55,
         TOWER_TOP + 2.55 + width * (v1 - v0) / (u1 - u0), "decals", m.d("room_ROOF"))


def build_plaza(name="harbor_plaza"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    assert data.get("map") == "riptide", f"{name}: not a Riptide model"
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = plaza_decals(random.Random(name))
    decal_png = os.path.join(ROOT, "art_source", "textures", name + "_decals.png")
    if os.path.exists(decal_png):
        os.remove(decal_png)                     # (the signs are made here: paint them again every time)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    m.rng = random.Random(name)
    _M[0] = m
    R._against = against
    outside = []
    conts = 0
    cost = {}
    for row in data["boxes"]:
        kind, col = row.get("kind"), row["colour"]
        f0 = len(m.b.faces)
        if kind == "ocont_part":
            pass                                   # (drawn by its marker, below)
        elif kind == "ocont_door":                 # a door leaf standing open: corrugated outside, its bars inside
            body = R.CONT_MAT[col]
            m.box(row["pos"], row["size"], lambda n, mid, q, body=body: None if n[1] < -0.7 else (body, uv_world()),
                  yaw=row["yaw"], cull=False)
            ya = math.radians(row["yaw"])
            for dz in (-0.3, 0.3):                 # the locking bars, upright
                p = list(row["pos"])
                p[0] += math.sin(ya) * dz
                p[2] += math.cos(ya) * dz
                m.box(tuple(p), (0.14, 2.3, 0.06), mat("rip_iron"), yaw=row["yaw"], cull=False)
        elif (kind or "").startswith("ocont"):
            open_cont(m, row, conts)
            conts += 1
        elif kind in PROP_KINDS or (kind or "").startswith("chair_"):
            R.t_prop(m, row)
        elif kind == "truck":
            truck(m, row, conts)
        elif col in R.CONT_MAT:
            R.container(m, row, conts)
            conts += 1
        elif kind == "gantry":
            gantry(m, row)
        elif kind == "road":
            m.box(row["pos"], row["size"], lambda n, mid, q: "rs_tar" if n[1] > 0.7 else None)
        elif kind in ("barrier", "baywall"):
            m.box(row["pos"], row["size"], Q.concrete_style, yaw=row["yaw"])
        elif kind == "kiosk":
            kiosk(m, row)
        elif kind == "shelter":
            m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else
                  ("rip_roof" if n[1] > 0.7 else ("rq_corr" if abs(n[2]) > 0.7 else "rip_glass")))
        elif kind in BUILDINGS or kind == "tower":
            building_piece(m, row, kind, outside)
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"), yaw=row["yaw"], pitch=row["pitch"])
        key = "container" if col in R.CONT_MAT and kind != "truck" else str(kind)
        cost[key] = cost.get(key, 0) + len(m.b.faces) - f0
    for step, fn in (("bands", lambda: outside_bands(m, outside)), ("frames", lambda: [frame(m, o) for o in data["openings"]]),
                     ("details", lambda: (details(m), room_signs(m)))):
        f0 = len(m.b.faces)
        fn()
        cost[step] = len(m.b.faces) - f0
    b = m.b
    bake_light.CELL = 3.0
    bake_light.DARK = 0.6
    bake_light.bake(b, [r for r in data["boxes"] if not r["pitch"] and not r["yaw"] and r.get("kind") != "road"])
    cells = R.riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris
