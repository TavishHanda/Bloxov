#!/usr/bin/env python3
"""Riptide (map 2) gray box: writes scenes/maps/riptide.tscn. Edit this script and re-run it, never the scene.

The plan (Tavish, 2026-11-09): the Leviathan, a drillship moored off a port, with Site Zero (the lab) on the
sea floor under it and the boss Raijin (Zero until 0.35.6) in its core. The port (The Landing) on the west: v3 (Tavish: "too open, too
small") made it a dense, tall harbor district with transit sheds along the quay. Five ways across (pier with a
covered pipe gallery and a shed, the high grain gallery to the ship loader, the pontoon under it, the breakwater to
the bow, the barge line to the stern) plus sea-side ladders from the boats; the drill floor splits the deck; several
ways between floors (bow stairs, moon pool lift + stairs, tower stairs, outside ladder, hold hatches, side-passage
ladders, the service tube), three ways into the lab and three into the core. tools/riptide_sight.gd measures the
long sightlines.

Coordinates are Godot metres with the origin in the middle of the map: x east (out to sea), z south, y up.
The sea's surface is y = 0. Everything is plain boxes (BoxMap); the art comes later, piece by piece.
"""
import contextlib
import json
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "riptide.tscn")
M = 360.0            # the map is 360 x 360 m
HALF = M / 2

WALL_T = 0.3
SLAB_T = 0.25
DOOR_W = 2.2       # (the AI need 2 m: they keep 0.75 m from edges)
DOOR_H = 2.4
BULWARK = 1.2        # the ship's rail wall above each open deck

# Heights (y, top of each floor)
SHORE = 2.5
PIER = 1.5
BARGE = 1.2
BOAT = 1.0
DECK = 4.0           # the main deck
FORECASTLE = 7.0
DECK2, DECK3, DECK4, ROOF = 7.5, 11.0, 14.5, 18.0
DRILL = 12.0         # the drill floor over the middle of the ship
HULL_A = -4.0        # the cargo hold
HULL_B = -8.0        # the engine room and pump room (the hull's bottom)
# (0.35.2, owner: "the lab is supposed to be a part of the cargo ship") Site Zero is the ship's two lowest decks,
# straight under the engine room deck, inside the hull. Before, it sat on the sea bed 14 m under the hull.
LAB1 = -12.25        # the dock (its ceiling is the hull B deck)
LAB2 = -18.25        # the ring, the wings and the core
SEABED = -29.0

# The ship: x 30..66 (36 m wide), z -104 (bow, north) .. 110 (stern, south)
SX0, SX1, SZ0, SZ1 = 30.0, 66.0, -104.0, 110.0
# The bridge tower (superstructure) on the stern end
TX0, TX1, TZ0, TZ1 = 34.0, 62.0, 74.0, 106.0
# (0.36.17, owner: "the boat shape is like too square") The hull's outline: the bow narrows over its last 10.5 m to a
# 2.8 m stem (the bow ladder climbs it) and the stern's corners are rounded (5 m). Each line is (half the hull's width,
# to the middle of its plate, z), the same on both sides; between them the sides are straight. The hull plate follows
# these points in straight pieces, and the floors inside are cut to them in strips (hull_slab).
BOW_Z, STEM = -93.5, 1.4
STERN_Z, STERN_R = 105.0, 5.0
BOW_LINE = [(STEM + (18.0 - STEM) * math.cos(math.pi / 2 * k / 12), BOW_Z - (BOW_Z - SZ0) * k / 12) for k in range(13)]
STERN_LINE = [(18.0 - STERN_R + STERN_R * math.cos(math.radians(15 * k)), STERN_Z + STERN_R * math.sin(math.radians(15 * k)))
              for k in range(7)]


def hull_half(z):
    """Half the hull's width (to the middle of its plate) at z."""
    for line in (BOW_LINE, STERN_LINE):
        for (ha, za), (hb, zb) in zip(line, line[1:]):
            if min(za, zb) <= z <= max(za, zb) and za != zb:
                return ha + (hb - ha) * (z - za) / (zb - za)
    return 18.0


def hull_strips(z0, z1, step=0.45):
    """The bow's and stern's shaped part between z0 and z1 cut into strips across the ship, each no more than `step`
    narrower at one end than the other: (za, zb, half the width at its narrow end)."""
    cuts = set()
    for line in (BOW_LINE, STERN_LINE):
        for (ha, za), (hb, zb) in zip(line, line[1:]):
            n = max(1, math.ceil(abs(hb - ha) / step))
            cuts |= {za + (zb - za) * k / n for k in range(n + 1)}
    cuts = sorted({z0, z1} | {c for c in cuts if z0 < c < z1})
    return [(za, zb, min(hull_half(za), hull_half(zb))) for za, zb in zip(cuts, cuts[1:])
            if zb - za > 0.005 and (zb <= BOW_Z or za >= STERN_Z)]

COLOURS = [
    ("sand", (0.74, 0.68, 0.52)),
    ("rock", (0.46, 0.45, 0.43)),
    ("concrete", (0.6, 0.59, 0.56)),
    ("metal", (0.47, 0.5, 0.52)),       # decks (metal footsteps)
    ("hull", (0.32, 0.36, 0.4)),
    ("rust", (0.5, 0.33, 0.24)),
    ("wall", (0.72, 0.72, 0.68)),
    ("lab", (0.82, 0.84, 0.86)),
    ("labfloor", (0.55, 0.58, 0.6)),
    ("container_a", (0.55, 0.27, 0.2)),
    ("container_b", (0.24, 0.38, 0.52)),
    ("container_c", (0.36, 0.45, 0.3)),
    ("wood", (0.5, 0.38, 0.26)),
    ("road", (0.33, 0.33, 0.35)),
    ("roof", (0.4, 0.4, 0.42)),
    ("core", (0.3, 0.32, 0.4)),
    ("water", (0.16, 0.3, 0.38)),
]
C = {name: i for i, (name, _) in enumerate(COLOURS)}

boxes = []           # (cx, cy, cz, sx, sy, sz, yaw, pitch, colour, solid)
loot = []            # (name, kind, x, y, z, yaw, table, place)
ladders = []         # (x, y, z, yaw, height, place)
extracts = []        # (node, title, x, y, z)
player_spawns = []   # (x, y, z)
enemy_spawns = []    # (x, y, z, zone or "")
boss_starts = []
perches = []         # (x, y, z, face x, face z)
switches = []        # (node, switch_id, prompt, x, y, z): MapSwitch
labels = []          # (text, x, z, big)
footprints = []      # (x0, z0, x1, z1)


# Models (the art pass, 0.35.29; plan: the "Riptide art plan" doc). As on Frontlines (gen_old_bloxov.py `modeled`):
# boxes made inside `with modeled(name, x, z):` still collide exactly as before (players, AI paths, shots), but once
# assets/models/buildings/<name>.glb exists they aren't drawn (BoxMap flag 2, or 3 if not solid): the model draws
# them. Their boxes go to art_source/buildings/<name>.json, relative to the model's origin at (x, 0, z), for
# art_source/scripts/make_building.py. Riptide's ground doesn't move things up or down, so the origin's y is 0.
models = []
_model = [None]
MODEL_JSON_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_source", "buildings")


def model_path(name):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "buildings", name + ".glb")


@contextlib.contextmanager
def modeled(name, x, z):
    assert _model[-1] is None, f"{name}: models don't nest (inside {_model[-1]['name']})"
    m = next((m for m in models if m["name"] == name), None)   # (a model can be added to again later)
    if m is None:
        m = {"name": name, "x": x, "z": z, "boxes": [], "hide": os.path.exists(model_path(name))}
        models.append(m)
    assert (m["x"], m["z"]) == (x, z), f"{name}: one origin per model"
    _model.append(m)
    try:
        yield
    finally:
        _model.pop()


def _add_box(b, kind=None):
    m = _model[-1]
    if m is not None:
        m["boxes"].append((b, kind))
        if m["hide"]:
            b = b[:9] + (2 if b[9] else 3,)
    boxes.append(b)


def write_model_boxes():
    names = {i: n for n, i in C.items()}
    os.makedirs(MODEL_JSON_DIR, exist_ok=True)
    for m in models:
        rows = [{"pos": [round(b[0] - m["x"], 3), round(b[1], 3), round(b[2] - m["z"], 3)],
                 "size": [round(v, 3) for v in b[3:6]], "yaw": b[6], "pitch": b[7], "colour": names[b[8]],
                 "solid": bool(b[9]), "kind": kind} for b, kind in m["boxes"]]
        with open(os.path.join(MODEL_JSON_DIR, m["name"] + ".json"), "w") as f:
            f.write('{"note": "Generated by tools/gen_riptide.py: the gray-box pieces this model covers, in Godot '
                    'space (y up, -z north) relative to the model\'s origin.",\n"map": "riptide",\n"openings": [],\n'
                    '"boxes": [\n' + ",\n".join(json.dumps(r) for r in rows) + "\n]}\n")


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------------------------------------------------------------------------------------------- pieces
def box(x0, y0, z0, x1, y1, z1, colour, solid=True, kind=None):
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    z0, z1 = min(z0, z1), max(z0, z1)
    if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01:
        return
    _add_box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, 0.0, 0.0, C[colour], 1 if solid else 0),
             kind)


def obox(cx, cy, cz, sx, sy, sz, yaw, colour, pitch=0.0, solid=True, kind=None):
    _add_box((cx, cy, cz, sx, sy, sz, yaw, pitch, C[colour], 1 if solid else 0), kind)


def ramp(a, b, width, colour="metal", t=SLAB_T):
    """A walkable slope from point a to point b (x, y, z), the top surface on the line between them. Straight along x
    or z only."""
    (ax, ay, az), (bx, by, bz) = a, b
    dx, dz = bx - ax, bz - az
    horiz = math.hypot(dx, dz)
    length = math.hypot(horiz, by - ay)
    yaw = math.degrees(math.atan2(dx, dz))           # local +z points from a to b (flat)
    pitch = -math.degrees(math.asin((by - ay) / length))
    p = math.radians(pitch)
    ny, nh = math.cos(p), math.sin(p)                # the slab's up (local y) in (up, along) terms
    cy = (ay + by) / 2 - ny * t / 2
    along = -nh * t / 2                              # (moves the middle back along the slope by half the thickness)
    ux, uz = dx / horiz, dz / horiz
    cx = (ax + bx) / 2 + ux * along
    cz = (az + bz) / 2 + uz * along
    _add_box((cx, cy, cz, width, t, length, yaw, pitch, C[colour], 1))


def wall(axis, at, a0, a1, y0, h, colour="wall", openings=(), t=WALL_T, solid=True):
    """A wall along x (axis "x": from x a0 to a1 at z = at) or along z (axis "z": z a0..a1 at x = at).
    openings: (centre, width, bottom above y0, top above y0)."""
    a0, a1 = min(a0, a1), max(a0, a1)
    cuts = [(max(c - w / 2, a0), min(c + w / 2, a1), lo, min(hi, h)) for c, w, lo, hi in openings]
    def piece(p0, p1, b, top):
        if p1 - p0 < 0.01 or top - b < 0.01:
            return
        if axis == "x":
            box(p0, y0 + b, at - t / 2, p1, y0 + top, at + t / 2, colour, solid)
        else:
            box(at - t / 2, y0 + b, p0, at + t / 2, y0 + top, p1, colour, solid)
    # Split the wall where any opening starts or ends; in each strip, fill round the openings that cover it (two
    # doors one above the other, on a stairwell, share a strip).
    edges = sorted({a0, a1} | {v for o in cuts for v in o[:2] if a0 < v < a1})
    for p0, p1 in zip(edges, edges[1:]):
        mid = (p0 + p1) / 2
        gaps = sorted((lo, hi) for o0, o1, lo, hi in cuts if o0 <= mid <= o1)
        y = 0.0
        for lo, hi in gaps:
            piece(p0, p1, y, lo)
            y = max(y, hi)
        piece(p0, p1, y, h)


def door(c, w=DOOR_W):
    return (c, max(w, DOOR_W), 0.0, DOOR_H)


def window(c, w=1.6, lo=1.0, hi=2.2):
    return (c, w, lo, hi)


def slab(x0, x1, z0, z1, top, colour="metal", holes=(), t=SLAB_T):
    """A floor (top surface at `top`) with rectangular holes (x0, x1, z0, z1)."""
    xs = sorted({x0, x1} | {v for h in holes for v in (h[0], h[1]) if x0 < v < x1})
    zs = sorted({z0, z1} | {v for h in holes for v in (h[2], h[3]) if z0 < v < z1})
    for j in range(len(zs) - 1):
        run = None
        for i in range(len(xs) - 1):
            cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
            hole = any(h[0] <= cx <= h[1] and h[2] <= cz <= h[3] for h in holes)
            if not hole:
                run = (run[0] if run else xs[i], xs[i + 1])
            elif run:
                box(run[0], top - t, zs[j], run[1], top, zs[j + 1], colour)
                run = None
        if run:
            box(run[0], top - t, zs[j], run[1], top, zs[j + 1], colour)


def hull_slab(top, colour="metal", holes=(), z0=SZ0, z1=SZ1, t=SLAB_T):
    """A deck right across the ship (from z0 to z1), cut to the hull's outline: straight where the sides are, strips
    (kind "deck_curve": the model draws the deck's real outline over them) at the bow and the stern."""
    slab(SX0, SX1, max(z0, BOW_Z), min(z1, STERN_Z), top, colour, holes, t)
    for za, zb, half in hull_strips(z0, z1):
        box(48.0 - half, top - t, za, 48.0 + half, top, zb, colour, kind="deck_curve")


def room(x0, x1, z0, z1, y, h, colour="wall", n=(), s=(), w=(), e=(), floor=None, roof=None, t=WALL_T):
    """Four walls (openings per side, positions in world x for n/s and world z for w/e), optional floor and roof."""
    wall("x", z0, x0, x1, y, h, colour, n, t)
    wall("x", z1, x0, x1, y, h, colour, s, t)
    wall("z", x0, z0, z1, y, h, colour, w, t)
    wall("z", x1, z0, z1, y, h, colour, e, t)
    if floor:
        slab(x0, x1, z0, z1, y, floor)
    if roof:
        slab(x0, x1, z0, z1, y + h, roof)


def container(x, y, z, along="x", colour="container_a", high=1):
    """A 6 x 2.4 shipping container (2.6 high), `high` stacked."""
    lx, lz = (6.0, 2.4) if along == "x" else (2.4, 6.0)
    box(x - lx / 2, y, z - lz / 2, x + lx / 2, y + 2.6 * high, z + lz / 2, colour)


def ladder(x, y, z, yaw, height, place):
    """A ladder's foot at (x, y, z); it leans toward -Z of its yaw (yaw 0 leans north, 90 west, -90 east, 180 south)."""
    ladders.append((x, y, z, yaw, height, place))


def add_loot(place, kind, x, y, z, yaw=0.0, table=None):
    n = sum(1 for l in loot if l[0].startswith(place + "_")) + 1
    loot.append((f"{place}_{kind.capitalize()}{n}", kind, x, y, z, yaw, table or kind, place))


def stairwell(x0, z0, levels, doors, colour="wall", roof=True):
    """A walled switchback stairwell 8 x 14 m (x0..x0+8, z0..z0+14) joining `levels` (top first). Landings
    alternate: level k is on the north end (z0..z0+3) when k is even, on the south end otherwise. Lane A
    (x0..x0+3.8) runs north -> south, lane B (x0+4.2..x0+8) south -> north.
    doors: {k: side} with side "N", "S", "W" or "E": a doorway at that level's landing."""
    x1, z1 = x0 + 8.0, z0 + 14.0
    for k, y in enumerate(levels):
        north = k % 2 == 0
        slab(x0, x1, z0 if north else z1 - 3.0, z0 + 3.0 if north else z1, y, "concrete")
        if k + 1 < len(levels):
            y2 = levels[k + 1]
            if north:   # lane A: from the north landing down to the south one
                ramp(((x0 + 1.9), y, z0 + 3.0), ((x0 + 1.9), y2, z1 - 3.0), 3.6, "concrete")
            else:       # lane B: from the south landing down to the north one
                ramp(((x0 + 6.1), y, z1 - 3.0), ((x0 + 6.1), y2, z0 + 3.0), 3.6, "concrete")
    bottom, top = levels[-1] - SLAB_T, levels[0] + 3.2
    box(x0 + 3.8, bottom, z0 + 3.0, x0 + 4.2, top, z1 - 3.0, colour)   # the divider between the lanes
    sides = {"N": [], "S": [], "W": [], "E": []}
    for k, side in doors.items():
        y = levels[k]
        lo, hi = y - bottom, y - bottom + DOOR_H
        north = k % 2 == 0
        if side in "NS":
            sides[side].append((x0 + 2.0 if north else x0 + 6.0, DOOR_W, lo, hi))
        else:
            sides[side].append((z0 + 1.5 if north else z1 - 1.5, DOOR_W, lo, hi))
    h = top - bottom
    wall("x", z0, x0, x1, bottom, h, colour, sides["N"])
    wall("x", z1, x0, x1, bottom, h, colour, sides["S"])
    wall("z", x0, z0, z1, bottom, h, colour, sides["W"])
    wall("z", x1, z0, z1, bottom, h, colour, sides["E"])
    if roof:
        slab(x0, x1, z0, z1, top + SLAB_T, "roof")


# ---------------------------------------------------------------------------------------------- the shore
# The Landing (v3, Tavish 2026-11-09: "too open, too small, more cover, tall buildings"): a working port, the quay at
# x -30 (60 m of water to the ship). From north to south: the north point (cannery, fuel tanks, lighthouse, the
# cove), the container terminal, the harbor plaza (Harbor Tower, the customs hall), the grain terminal (silos, the
# headhouse and its gallery out to the ship), the shipyard (an unfinished hull on the slipway, the fab shed). Transit
# sheds line the quay so the ship can't see into the port; nothing outdoors runs long and straight.
QUAY = -29.4


def gate(c, w=4.0, h=3.6):
    return (c, w, 0.0, h)


def hall(x0, x1, z0, z1, h, colour="wall", n=(), s=(), w=(), e=(), y=SHORE, roof="roof", floor=None):
    room(x0, x1, z0, z1, y, h, colour, n, s, w, e, floor=floor)
    slab(x0, x1, z0, z1, y + h + SLAB_T, roof)
    footprints.append((x0, z0, x1, z1))


def truck(x, z, yaw, colour="container_b"):
    """A lorry (cab and trailer, 2.5 wide, 13 long) heading along yaw."""
    s, c = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    obox(x, SHORE + 1.8, z, 2.5, 3.6, 10.0, yaw, colour)
    obox(x + s * 6.4, SHORE + 1.4, z + c * 6.4, 2.5, 2.8, 2.6, yaw, "rust")


def barrier(x, z, yaw, length=4.0, y=SHORE):
    obox(x, y + 0.45, z, 0.7, 0.9, length, yaw, "concrete")


def wagon(x, z, colour="rust"):
    """A freight wagon on the rail line (along z, 14 long)."""
    box(x - 1.5, SHORE, z - 7.0, x + 1.5, SHORE + 3.8, z + 7.0, colour)


def block(x0, z0, cols, rows, heights, k=0):
    """Containers end to end along x (cols x 6 m) and side by side along z (rows x 2.4 m), stacked 1-3 high."""
    cols_c = ("container_a", "container_b", "container_c")
    for i in range(cols):
        for j in range(rows):
            n = k + i * rows + j
            container(x0 + 3.0 + 6.0 * i, SHORE, z0 + 1.2 + 2.4 * j, "x", cols_c[n % 3], heights[n % len(heights)])


WATER_LADDERS_QUAY = (-86.0, -40.0, 22.0, 70.0, 150.0)


def quay():
    # the quay wall, its low parapet (gaps where the ways across start), the map's edges
    box(-30.0, -10.0, -HALF, QUAY, SHORE, HALF, "concrete")
    gaps = [(-124.0, 12.0), (2.6, 10.0), (39.0, 3.0), (121.0, 6.0), (163.0, 14.0)]
    gaps += [(z, 2.0) for z in WATER_LADDERS_QUAY]      # (0.33.6) the ladders up out of the sea
    # the sea's edge (0.33.6, swimming): a low sea wall round the far water, so nobody swims off the map
    box(HALF - 0.6, -4.0, -HALF, HALF, 3.0, HALF, "rock")
    for z0, z1 in ((-HALF, -HALF + 0.6), (HALF - 0.6, HALF)):
        box(QUAY, -4.0, z0, HALF, 3.0, z1, "rock")
    wall("z", -29.7, -HALF, HALF, SHORE, 0.9, "concrete", [(c, w, 0.0, 0.9) for c, w in gaps], t=0.6)
    wall("z", -HALF + 0.5, -HALF, HALF, SHORE, 3.0, "concrete", t=0.6)
    for z in (-HALF + 0.5, HALF - 0.5):
        wall("x", z, -HALF, QUAY, SHORE, 3.0, "concrete", t=0.6)
    labels.append(("THE LANDING", -110, -2, 1))
    # the rail line inland: stopped freight trains (cover along the spawn side), a level crossing at the road
    for z0, n in [(-176.0, 4), (-104.0, 3), (-46.0, 2), (14.0, 3), (70.0, 4), (142.0, 2)]:
        for i in range(n):
            wagon(-156.0, z0 + 7.0 + 17.0 * i, ("rust", "container_c", "container_b")[i % 3])
    # the spawn strip (between the fence and the rail): fences across it, gates on alternate sides
    for i, z in enumerate((-112.0, -40.0, 48.0, 128.0)):
        gx = -175.0 if i % 2 else -165.0
        wall("x", z, -HALF, -158.0, SHORE, 2.6, "concrete", [(gx, 3.0, 0.0, 2.6)], t=0.4)
        box(gx + (3.5 if i % 2 else -6.5), SHORE, z + 0.3, gx + (6.5 if i % 2 else -3.5), SHORE + 2.4, z + 3.3, "wood")
    # quay cranes straddling the apron (legs every 40 m) and things parked across it, so the apron along the quay
    # never gives a clear line
    for z in (-96.0, -56.0, -16.0, 84.0, 140.0):
        for x in (-38.5, -31.5):
            for dz in (-5.0, 5.0):
                box(x - 0.8, SHORE, z + dz - 0.8, x + 0.8, SHORE + 22.0, z + dz + 0.8, "rust")
        box(-40.0, SHORE + 22.0, z - 6.0, -30.0, SHORE + 24.0, z + 6.0, "rust")
        obox(-14.0, SHORE + 23.0, z, 34.0, 1.2, 1.6, 0, "rust")
    for i, z in enumerate((-138.0, -86.0, -66.0, -40.0, 22.0, 70.0, 96.0, 108.0, 134.0, 150.0)):
        x = -37.0 if i % 2 else -33.6
        container(x, SHORE, z, "x", ("container_a", "container_b", "container_c")[i % 3], 1 + i % 2)


def north_point():
    # rocks along the north shore, the lighthouse (a perch) by the cove
    for x, z, sx, sz, h, yaw in [(-52, -150, 8, 6, 3.0, 20), (-70, -172, 10, 7, 2.2, -15), (-45, -136, 6, 5, 2.0, 40),
                                 (-84, -168, 7, 9, 3.5, 10), (-36, -158, 5, 4, 1.6, 0), (-120, -174, 9, 5, 2.8, 30),
                                 (-150, -170, 6, 5, 2.4, 15)]:
        obox(x, SHORE + h / 2 - 0.3, z, sx, h + 0.6, sz, yaw, "rock")
    lx, lz = -62.0, -158.0
    room(lx - 3, lx + 3, lz - 3, lz + 3, SHORE, 14.0, "wall", s=[door(lx)])
    slab(lx - 3, lx + 3, lz - 3, lz + 3, SHORE + 14.0, "concrete", holes=[(lx - 2.7, lx - 1.5, lz + 1.2, lz + 2.85)])
    wall("x", lz - 3, lx - 3, lx + 3, SHORE + 14.0, 1.1, "wall")
    wall("x", lz + 3, lx - 3, lx + 3, SHORE + 14.0, 1.1, "wall")
    wall("z", lx - 3, lz - 3, lz + 3, SHORE + 14.0, 1.1, "wall")
    wall("z", lx + 3, lz - 3, lz + 3, SHORE + 14.0, 1.1, "wall")
    # (0.35.16: at the hatch's north edge facing north, so its top steps off onto the gallery, not into the wall)
    ladder(lx - 2.1, SHORE, lz + 1.2, 0, 14.0, "Lighthouse")
    perches.append((lx, SHORE + 14.0, lz, 1, 0))
    labels.append(("LIGHTHOUSE", lx, lz - 8, 0))
    extracts.append(("Cove", "COVE", -40.0, SHORE, -170.0))
    # (0.33.2, owner: extracts too easy to camp) the cove is a nook in the rocks: tall outcrops round it, the ways in
    # bent so nobody sees the zone from far off
    for x, z, sx, sz, h, yaw in [(-47.0, -170.0, 3.0, 9.0, 3.6, 5), (-41.0, -163.0, 8.0, 3.0, 3.4, -8),
                                 (-33.5, -166.0, 3.0, 5.0, 3.2, 20), (-52.0, -160.0, 5.0, 4.0, 3.0, 30),
                                 (-36.0, -152.0, 4.0, 3.0, 2.6, -15)]:
        obox(x, SHORE + h / 2 - 0.3, z, sx, h + 0.6, sz, yaw, "rock")
    # the cannery: a tall hall, machine rows, an office deck along the west end (a ramp up)
    cx0, cx1, cz0, cz1 = -142.0, -96.0, -166.0, -130.0
    hall(cx0, cx1, cz0, cz1, 10.0, "wall", n=[gate(-120.0)], s=[gate(-134.0), gate(-108.0)],
         w=[door(-150.0), window(-140.0, 3.0, 5.6, 7.0)], e=[gate(-140.0), door(-156.0), window(-148.0, 3.0, 5.6, 7.0)])
    slab(cx0, cx0 + 12.0, cz0, cz1, SHORE + 4.5, "concrete", holes=[(cx0 + 12.0 - 3.0, cx0 + 12.0, cz0 + 10.0, cz0 + 26.0)])
    ramp((cx0 + 10.5, SHORE, cz0 + 28.0), (cx0 + 10.5, SHORE + 4.5, cz0 + 12.0), 2.6, "concrete")
    wall("z", cx0 + 12.0, cz0, cz0 + 10.0, SHORE + 4.5, 1.1, "wall")
    wall("z", cx0 + 12.0, cz0 + 26.0, cz1, SHORE + 4.5, 1.1, "wall")
    for z in (-160.0, -150.0, -140.0):       # the machine rows (cover)
        box(-124.0, SHORE, z - 1.0, -112.0, SHORE + 1.8, z + 1.0, "metal")
        box(-108.0, SHORE, z + 2.0, -100.0, SHORE + 2.4, z + 4.0, "metal")
    for z in (-162.0, -146.0):               # rooms under the office deck
        wall("x", z, cx0, cx0 + 8.0, SHORE, 4.25, "wall", [door(cx0 + 4.0)])
    labels.append(("CANNERY", -119, -170, 0))
    add_loot("Depot", "crate", -140.8, SHORE, -164.9)   # (0.35.16: out of the doorway, the AI couldn't get in)
    add_loot("Offices", "locker", -140.5, SHORE + 4.5, -152.0, 90)
    add_loot("Offices", "crate", -133.0, SHORE + 4.5, -133.0)
    add_loot("Workshop", "crate", -104.0, SHORE, -133.0, table="crate")
    # the fuel depot: three big tanks behind a low bund wall
    for x, z in [(-86.0, -150.0), (-86.0, -136.0), (-74.0, -143.0)]:
        obox(x, SHORE + 5.0, z, 9.0, 10.0, 9.0, 45, "rust")
    room(-94.0, -66.0, -158.0, -128.0, SHORE, 1.0, "concrete", s=[(-80.0, 4.0, 0.0, 1.0)], w=[(-143.0, 4.0, 0.0, 1.0)])
    labels.append(("FUEL DEPOT", -80, -124, 0))
    player_spawns.append((-172.0, SHORE, -150.0))


def terminal():
    """The container terminal: staggered rows of stacks (1-3 high) and single boxes across the aisles, so every
    line through it bends. A gantry crane over it."""
    hs = [2, 3, 2, 1, 3, 2, 2, 3, 1, 2, 3, 2]
    rows = [-110.0, -96.0, -82.0, -68.0, -54.0]
    for r, z0 in enumerate(rows):
        runs = [(-142.0, 4), (-112.0, 4), (-82.0, 2)] if r % 2 == 0 else [(-128.0, 4), (-98.0, 4), (-146.0, 1)]
        for k, (x0, cols) in enumerate(runs):
            block(x0, z0, cols, 3, hs, k=r * 7 + k * 3)
    for i, (x, z) in enumerate([(-122.0, -99.3), (-88.0, -99.3), (-108.0, -85.3), (-138.0, -71.3), (-76.0, -71.3),
                                (-118.0, -57.3), (-92.0, -57.3)]):
        container(x, SHORE, z, "z", ("container_b", "container_c", "container_a")[i % 3], 1 + (i + 1) % 2)
    for x in (-148.0, -64.0):                      # the gantry crane
        for z in (-99.0, -75.0):
            box(x - 0.8, SHORE, z - 0.8, x + 0.8, SHORE + 24.0, z + 0.8, "rust")
        box(x - 1.0, SHORE + 24.0, -100.0, x + 1.0, SHORE + 26.0, -74.0, "rust")
    box(-148.8, SHORE + 26.0, -100.0, -63.2, SHORE + 28.0, -97.0, "rust")
    box(-148.8, SHORE + 26.0, -77.0, -63.2, SHORE + 28.0, -74.0, "rust")
    # the trolley rides between the girders (0.35.32: it was a container-blue box hanging in the air under them)
    box(-112.0, SHORE + 25.0, -97.0, -104.0, SHORE + 28.0, -77.0, "rust")
    labels.append(("CONTAINER TERMINAL", -105, -116, 0))
    for x, z in [(-130.0, -99.0), (-104.0, -71.0), (-80.0, -85.0), (-140.0, -57.0)]:
        add_loot("Depot", "crate", x, SHORE, z, table="field" if x < -120 else "crate")
    player_spawns.append((-172.0, SHORE, -70.0))


def plaza():
    """Harbor Tower (six floors, two stairwells, a closed roof), the customs hall the pier starts from, the canteen
    and the garage; the road in from the gate, broken up by parked lorries and barriers."""
    tx0, tx1, tz0, tz1 = -124.0, -92.0, -30.0, -10.0
    fl = [SHORE + 3.5 * f for f in range(6)]          # 2.5 .. 20
    top = fl[-1] + 3.5
    for f, y in enumerate(fl):
        k = 5 - f                                      # the stairwells count from the top
        a_door = -28.5 if k % 2 == 0 else -17.5
        b_door = -22.5 if k % 2 == 0 else -11.5
        h = 3.5 - SLAB_T
        n = [window(x, 2.4) for x in (-118.0, -110.0, -102.0)] + ([gate(-98.0, 3.0, 2.6)] if f == 0 else [window(-96.0)])
        s = [window(x, 2.4) for x in (-114.0, -106.0, -98.0)] + ([gate(-119.0, 3.0, 2.6)] if f == 0 else [window(-119.0)])
        room(tx0, tx1, tz0, tz1, y, h, "wall", n=n, s=s, w=[door(a_door), window(-24.0)],
             e=[door(b_door), window(-17.0)])
        if f > 0:
            slab(tx0, tx1, tz0, tz1, y, "concrete")
        wall("x", -20.5, tx0, tx1, y, h, "wall", [door(-120.0), door(-112.0), door(-97.0)])
        wall("x", -15.0, tx0, tx1, y, h, "wall", [door(-114.0), door(-100.0)])
        wall("z", -108.0, tz0, -20.5, y, h, "wall", [door(-26.0)])
        wall("z", -104.0, -15.0, tz1, y, h, "wall", [door(-12.5)])
    slab(tx0, tx1, tz0, tz1, top, "roof")
    wall("x", tz0, tx0, tx1, top, 1.0, "wall")
    wall("x", tz1, tx0, tx1, top, 1.0, "wall")
    wall("z", tx0, tz0, tz1, top, 1.0, "wall")
    wall("z", tx1, tz0, tz1, top, 1.0, "wall")
    stairwell(-132.0, -30.0, fl[::-1], {k: "E" for k in range(6)}, colour="wall")
    stairwell(-92.0, -24.0, fl[::-1], {k: "W" for k in range(6)}, colour="wall")
    footprints.append((-132.0, -30.0, -84.0, -10.0))
    labels.append(("HARBOR TOWER", -108, -36, 0))
    for f, (x, z, kind) in enumerate([(-122.0, -28.0, "crate"), (-94.0, -12.0, "locker"), (-122.0, -12.0, "crate"),
                                      (-94.0, -28.0, "locker"), (-112.0, -28.5, "safe"), (-100.0, -11.5, "safe")]):
        add_loot("Offices", kind, x, fl[f], z, 180 if z > -20 else 0)
    # the customs hall: two floors, the pier's way in on the east side
    hx0, hx1, hz0, hz1 = -76.0, -48.0, -14.0, 16.0
    hall(hx0, hx1, hz0, hz1, 9.0, "wall", n=[door(-70.0), door(-54.0), window(-62.0, 2.0, 5.4, 6.8)],
         s=[door(-66.0), window(-56.0, 2.0, 5.4, 6.8)], w=[gate(10.0), window(-6.0, 2.0, 5.4, 6.8)],
         e=[gate(2.6, 5.0), window(-8.0, 2.0, 5.4, 6.8), window(12.0, 2.0, 5.4, 6.8)], floor="concrete")
    slab(hx0, hx1, hz0, hz1, SHORE + 4.5, "concrete", holes=[(-67.5, -58.0, -13.6, -10.5)])
    ramp((-74.0, SHORE, -12.0), (-58.0, SHORE + 4.5, -12.0), 2.6, "concrete")
    for x0, x1, z in [(-70.0, -58.0, -4.0), (-66.0, -54.0, 8.0)]:   # the counters
        box(x0, SHORE, z - 0.5, x1, SHORE + 1.1, z + 0.5, "wood")
    wall("x", 4.0, hx0, -62.0, SHORE + 4.5, 4.25, "wall", [door(-70.0)])
    labels.append(("CUSTOMS", -62, -18, 0))
    add_loot("Offices", "locker", -75.5, SHORE + 4.5, 12.0, 90)
    add_loot("Offices", "crate", -50.0, SHORE + 4.5, 14.0)
    add_loot("Offices", "crate", -74.0, SHORE, 14.0)
    # the canteen and the garage south of the road
    hall(-124.0, -102.0, 8.0, 24.0, 4.0, "wall", n=[door(-118.0), window(-108.0, 3.0)], s=[door(-106.0)],
         e=[door(16.0), window(20.0)], w=[window(14.0, 3.0)])
    box(-120.0, SHORE, 14.0, -108.0, SHORE + 1.0, 15.0, "wood")
    add_loot("Diner", "crate", -122.0, SHORE, 22.0)
    hall(-96.0, -80.0, 12.0, 30.0, 5.0, "wall", n=[gate(-88.0, 5.0, 4.0)], e=[door(26.0)], w=[window(20.0)])
    add_loot("Garage", "crate", -94.0, SHORE, 28.0)
    labels.append(("CANTEEN", -113, 28, 0))
    # the road in from the gate (the extract): a gatehouse, lorries parked across it, barriers round the plaza
    box(-HALF, SHORE - 0.2, -4.0, -76.0, SHORE + 0.06, 4.0, "road", solid=False)
    room(-172.0, -167.0, -11.0, -6.0, SHORE, 2.8, "wood", s=[door(-169.5)], roof="roof")
    extracts.append(("RoadOut", "ROAD OUT", -174.0, SHORE, 0.0))
    # (0.33.2) the gate's truck bay: walls either side, a container across the road in front of it, ways in at the
    # corners
    wall("x", -5.0, -HALF, -169.0, SHORE, 3.0, "concrete", t=0.5)
    wall("x", 5.0, -HALF, -169.0, SHORE, 3.0, "concrete", t=0.5)
    box(-168.2, SHORE, -2.4, -165.8, SHORE + 5.2, 2.4, "container_a")
    box(-163.0, SHORE, 4.0, -160.6, SHORE + 2.6, 10.0, "container_c")
    box(-163.0, SHORE, -10.0, -160.6, SHORE + 2.6, -4.0, "container_b")
    truck(-140.0, 1.0, 55.0)
    truck(-90.0, -1.0, -50.0, "container_a")
    truck(-140.0, 64.0, 10.0, "container_c")
    for x, z, yaw in [(-82.0, -6.0, 90.0), (-78.0, 8.0, 90.0), (-84.0, -26.0, 90.0), (-132.0, 6.0, 90.0), (-112.0, 4.5, 90.0),
                      (-100.0, -5.0, 90.0), (-66.0, 22.0, 90.0), (-56.0, -20.0, 90.0)]:
        barrier(x, z, yaw)
    box(-110.0, SHORE, -4.0, -106.0, SHORE + 2.6, -2.0, "wall")        # the bus shelter
    labels.append(("HARBOR PLAZA", -100, 4, 0))
    player_spawns.append((-172.0, SHORE, 22.0))


def grain():
    """The grain terminal: the silo bank (30 m tall), the headhouse by the quay with the covered gallery out to the
    ship at y 14, the grain store, hopper wagons on the siding."""
    for i in range(5):
        box(-112.0 + 8.0 * i, SHORE, 38.0, -104.0 + 8.0 * i, SHORE + 30.0, 54.0, "concrete")
    box(-112.0, SHORE + 30.0, 44.0, -46.0, SHORE + 32.0, 47.0, "rust")    # the conveyor over to the headhouse
    footprints.append((-112.0, 38.0, -72.0, 54.0))
    labels.append(("SILOS", -92, 34, 0))
    # the headhouse: a stairwell tower by the quay, the gallery leaves from its top landing
    stairwell(-46.0, 42.0, [GALLERY, 11.0, 8.0, 5.0, SHORE], {0: "E", 4: "W"})
    box(-46.0, GALLERY + 3.45, 42.0, -38.0, 34.0, 56.0, "concrete")
    footprints.append((-46.0, 42.0, -38.0, 56.0))
    labels.append(("HEADHOUSE", -42, 60, 0))
    # the grain store, grain heaps inside (cover)
    hall(-112.0, -72.0, 64.0, 92.0, 8.0, "wall", n=[gate(-104.0), gate(-80.0)], s=[gate(-92.0)], w=[door(78.0)],
         e=[gate(70.0), door(86.0)])
    for x, z, yaw in [(-102.0, 72.0, 0), (-84.0, 82.0, 30), (-96.0, 86.0, 80)]:
        obox(x, SHORE + 1.0, z, 7.0, 2.0, 6.0, yaw, "sand")
    add_loot("Depot", "crate", -110.0, SHORE, 90.0)
    add_loot("Depot", "crate", -74.0, SHORE, 66.0, table="field")
    for x in (-108.0, -84.0):                       # hopper wagons between the silos and the store
        box(x - 7.0, SHORE, 57.5, x + 7.0, SHORE + 3.8, 60.5, "container_c")
    add_loot("Railyard", "crate", -96.0, SHORE, 59.0, table="field")
    labels.append(("GRAIN STORE", -92, 96, 0))
    player_spawns.append((-172.0, SHORE, 90.0))


def shipyard():
    """The unfinished hull on the slipway (open frames, a half deck up a scaffold ramp), the fab shed, the workshop,
    the boathouse on the south quay."""
    hx0, hx1, hz0, hz1 = -112.0, -58.0, 140.0, 158.0
    deck = SHORE + 5.5
    plating = [gate(x, 3.2, 3.0) for x in (-106.0, -94.0, -82.0, -70.0)]
    wall("x", hz0, hx0, hx1, SHORE, 9.0, "hull", plating, t=0.5)
    wall("x", hz1, hx0, hx1, SHORE, 9.0, "hull", plating[1:] + [(-86.0, 2.6, deck - SHORE, deck - SHORE + DOOR_H)], t=0.5)
    wall("z", hx0, hz0, hz1, SHORE, 9.0, "hull", [gate(149.0, 4.0, 3.0)], t=0.5)
    for x in (-100.0, -88.0, -76.0, -66.0):       # the frames inside (under the half deck, up to it)
        wall("z", x, hz0, hz1, SHORE, 9.0 if x > -80 else deck - SLAB_T - SHORE, "rust", [gate(149.0, 5.0, 3.4)], t=0.4)
    slab(hx0, -80.0, hz0, hz1, deck, "metal", holes=[(-108.0, -104.0, 144.0, 150.0)])
    ramp((-58.0, SHORE, 161.0), (-84.0, deck, 161.0), 2.6, "wood")
    box(-90.0, deck - SLAB_T, 158.0, -84.0, deck, 162.3, "wood")
    for x in range(-110, -56, 8):                   # the scaffold posts
        box(x, SHORE, 162.4, x + 0.3, SHORE + 9.0, 162.7, "rust")
    footprints.append((hx0, hz0, hx1, hz1))
    labels.append(("SLIPWAY", -85, 136, 0))
    add_loot("Workshop", "crate", -110.0, SHORE, 156.0)
    add_loot("Workshop", "crate", -96.0, deck, 142.0, table="crate")
    # the fab shed (tall, big doors both ends), the workshop
    hall(-152.0, -120.0, 104.0, 128.0, 12.0, "wall", n=[gate(-136.0, 6.0, 6.0)], s=[gate(-136.0, 6.0, 6.0)],
         w=[door(116.0)], e=[gate(112.0), door(124.0)])
    for x, z in [(-146.0, 110.0), (-128.0, 122.0), (-140.0, 120.0)]:
        box(x - 2.5, SHORE, z - 1.5, x + 2.5, SHORE + 1.6, z + 1.5, "metal")
    add_loot("Workshop", "crate", -150.0, SHORE, 126.0, table="crate")
    labels.append(("FAB SHED", -136, 100, 0))
    hall(-104.0, -84.0, 106.0, 124.0, 5.0, "wall", n=[door(-94.0)], s=[door(-98.0)], e=[gate(115.0)], w=[window(115.0)])
    add_loot("Shed", "crate", -102.0, SHORE, 108.0)
    # the boathouse on the south quay (the extract): open on the water side
    bx0, bx1, bz0, bz1 = -46.0, -32.0, 156.0, 170.0
    hall(bx0, bx1, bz0, bz1, 4.5, "wood", w=[door(167.5, 2.4)], n=[door(-34.0)], e=[(159.5, 5.0, 0.0, 3.6)], floor="wood")
    # (0.33.2) screens inside, so neither the doors nor the water side look straight onto the zone
    wall("z", -36.0, bz0, 162.5, SHORE, 3.0, "wood")
    wall("z", -43.0, 164.0, bz1, SHORE, 3.0, "wood")
    extracts.append(("Boathouse", "BOATHOUSE", -38.0, SHORE, 163.0))
    labels.append(("BOATHOUSE", -39, 174, 0))
    for x, z, yaw in [(-140.0, 150.0, 70), (-150.0, 164.0, 120), (-120.0, 172.0, 95)]:
        obox(x, SHORE + 0.7, z, 2.6, 1.4, 7.0, yaw, "wood")
    player_spawns.append((-150.0, SHORE, 172.0))


def transit_sheds():
    """Long sheds along the quay (7 m tall): the ship sees their walls, not the port behind them."""
    for x0, x1, z0, z1, lbl in [(-60.0, -42.0, -112.0, -72.0, "SHED 1"), (-60.0, -42.0, -64.0, -24.0, "SHED 2"),
                                (-62.0, -44.0, 64.0, 104.0, "SHED 3")]:
        zm = (z0 + z1) / 2
        hall(x0, x1, z0, z1, 7.0, "wall", n=[gate((x0 + x1) / 2)], s=[gate((x0 + x1) / 2)],
             w=[gate(zm - 10.0), door(zm + 12.0)], e=[gate(zm + 8.0), door(zm - 14.0), window(zm, 3.0, 4.0, 5.6)])
        for i, z in enumerate((zm - 12.0, zm + 2.0, zm + 14.0)):   # pallets and crates inside
            box(x0 + 4.0 + 6.0 * (i % 2), SHORE, z - 1.5, x0 + 8.0 + 6.0 * (i % 2), SHORE + 1.6, z + 1.5, "wood")
        labels.append((lbl, (x0 + x1) / 2, zm, 0))
        add_loot("Depot", "crate", x0 + 1.5, SHORE, z0 + 1.5)
        add_loot("Depot", "crate", x1 - 1.5, SHORE, z1 - 1.5, table="field")


def quay_cover(n, z):
    """One 6 m piece of cover on the quay edge (x -33..-30), a different kind each time (0.33.7, owner: it was one
    line of the same container). All of it hides you from the ship; some you can get inside or peek over."""
    x0, x1 = -32.6, -30.2
    kind = (0, 3, 1, 5, 2, 6, 4, 7, 0, 2, 5, 1, 7, 3, 6, 4)[n % 16]
    if kind == 0:      # a container (as before), every other one stood on end or doubled
        box(x0, SHORE, z - 3.0, x1, SHORE + (5.2 if n % 3 == 0 else 2.6), z + 3.0, ("container_a", "container_b", "container_c")[n % 3])
    elif kind == 1:    # a blast wall: tall, with a blown-out notch you can shoot through, rubble at its foot
        box(-32.0, SHORE, z - 3.0, -31.3, SHORE + 2.8, z - 0.4, "concrete")
        box(-32.0, SHORE, z - 0.4, -31.3, SHORE + 1.2, z + 0.8, "concrete")
        box(-32.0, SHORE, z + 0.8, -31.3, SHORE + 2.8, z + 3.0, "concrete")
        obox(-33.2, SHORE + 0.35, z + 0.4, 1.6, 0.7, 1.2, 25, "concrete")
        obox(-30.7, SHORE + 0.25, z - 0.2, 1.0, 0.5, 0.9, -40, "concrete")
    elif kind == 2:    # crates stacked in steps (climb up and over, or sit behind)
        box(x0, SHORE, z - 3.0, x1, SHORE + 1.3, z + 3.0, "wood")
        box(x0, SHORE + 1.3, z - 3.0, x1, SHORE + 2.6, z + 0.6, "wood")
        box(x0 + 0.4, SHORE + 2.6, z - 2.6, x1 - 0.4, SHORE + 3.6, z - 1.0, "wood")
    elif kind == 3:    # a watchman's hut: door on the port side, a slit window at the ship
        room(-33.6, -30.2, z - 2.4, z + 2.4, SHORE, 2.6, "wood", w=[door(z, 1.4)], e=[window(z, 1.6, 1.2, 1.7)], roof="roof")
    elif kind == 4:    # a pile of pipes between two posts
        for i, (dx, y) in enumerate([(-0.8, 0.0), (0.0, 0.0), (0.8, 0.0), (-0.4, 0.7), (0.4, 0.7), (0.0, 1.4)]):
            box(-31.4 + dx - 0.35, SHORE + y, z - 3.0, -31.4 + dx + 0.35, SHORE + y + 0.7, z + 3.0, "rust")
        for dz in (-2.2, 2.2):
            box(-32.7, SHORE, z + dz - 0.15, -32.4, SHORE + 2.6, z + dz + 0.15, "rust")
            box(-30.4, SHORE, z + dz - 0.15, -30.1, SHORE + 2.6, z + dz + 0.15, "rust")
    elif kind == 5:    # a wrecked lorry cab and its spilled load
        obox(-31.5, SHORE + 1.4, z - 1.4, 2.5, 2.8, 2.8, 12, "rust")
        obox(-31.3, SHORE + 0.9, z + 1.6, 2.4, 1.8, 3.0, -8, "container_b")
        obox(-33.4, SHORE + 0.4, z + 2.2, 1.2, 0.8, 1.2, 35, "wood")
    elif kind == 6:    # broken concrete: a slab on its side, blocks thrown round it
        obox(-31.5, SHORE + 1.2, z, 0.7, 2.4, 5.0, 8, "concrete")
        obox(-32.8, SHORE + 0.5, z - 1.6, 1.4, 1.0, 1.6, 30, "concrete")
        obox(-30.8, SHORE + 0.4, z + 1.8, 1.2, 0.8, 1.0, -20, "concrete")
        obox(-33.0, SHORE + 0.3, z + 2.0, 0.9, 0.6, 0.9, 55, "rock")
    else:              # cable drums and a barrier: one drum on its side, one standing
        box(x0, SHORE, z - 3.0, x1, SHORE + 2.4, z - 0.8, "wood")
        box(-32.2, SHORE, z + 0.4, -30.6, SHORE + 1.6, z + 2.0, "wood")
        barrier(-33.2, z + 1.2, 15, 3.4)


def breakers():
    """Sightline breakers (v3), placed where tools/riptide_sight.gd found long open lines: the streets along the
    north and south edges of the terminal and the shipyard, the corridor beside the rail line, the road, the quay
    apron (a row of containers along the quay edge: cover from the ship), the barge line's way into the port."""
    # small buildings across the north street (between the cannery and the terminal) and the mole's root
    for x0, x1, z0, z1, h in [(-150.0, -136.0, -128.0, -118.0, 4.0), (-116.0, -100.0, -122.0, -112.0, 5.0),
                              (-70.0, -58.0, -126.0, -114.0, 4.5)]:
        hall(x0, x1, z0, z1, h, "wall", n=[door((x0 + x1) / 2)], s=[door(x0 + 3.0)], w=[window((z0 + z1) / 2)],
             e=[window((z0 + z1) / 2)])
    add_loot("Shed", "crate", -148.0, SHORE, -120.0)
    add_loot("Shed", "crate", -60.0, SHORE, -124.0, table="field")
    container(-84.0, SHORE, -127.0, "z", "container_b", 2)
    # the corridor beside the rail: the weighbridge office, the rail shed, the signal box, a container across
    hall(-152.0, -138.0, -44.0, -34.0, 4.0, "wall", n=[door(-145.0)], s=[door(-141.0)], e=[window(-39.0)])
    hall(-152.0, -136.0, 36.0, 56.0, 6.0, "wall", n=[gate(-144.0)], s=[gate(-144.0)], e=[door(46.0)])
    hall(-150.0, -138.0, 72.0, 84.0, 7.0, "wall", n=[door(-144.0)], e=[window(78.0)], w=[window(78.0)])
    add_loot("Railyard", "crate", -150.0, SHORE, 54.0)
    add_loot("Railyard", "locker", -149.5, SHORE, 82.0, 90)
    box(-153.0, SHORE, -89.2, -147.0, SHORE + 5.2, -86.8, "container_a")
    # the lane between the rail shed / canteen and the silos / grain store (x -136..-112): broken at three places
    box(-136.0, SHORE, 58.5, -122.0, SHORE + 3.8, 61.5, "container_c")
    box(-132.0, SHORE, 29.8, -126.0, SHORE + 5.2, 32.2, "container_b")
    box(-122.0, SHORE, 32.6, -116.0, SHORE + 2.6, 35.0, "container_a")
    hall(-128.0, -114.0, 94.0, 102.0, 4.0, "wall", n=[door(-121.0)], s=[door(-118.0)], w=[window(98.0)])
    add_loot("Shed", "crate", -126.0, SHORE, 100.0, table="field")
    container(-126.0, SHORE, 136.0, "z", "container_b", 2)
    box(-170.0, SHORE, -22.0, -164.0, SHORE + 2.6, -19.6, "container_c")   # (the spawn strip by the road)
    # the road: a checkpoint booth, kiosks and stacks staggered across it
    for x0, z0, x1, z1, h in [(-151.0, -10.0, -147.0, -2.0, 2.6), (-137.0, 1.0, -133.0, 8.0, 2.6),
                              (-119.0, -9.0, -115.0, -3.0, 2.4), (-101.0, 2.0, -97.0, 8.0, 2.4)]:
        box(x0, SHORE, z0, x1, SHORE + h, z1, "wall")
    # the south street (between the fab shed / workshop and the hull) and the south edge
    container(-118.0, SHORE, 133.0, "x", "container_c", 2)
    hall(-80.0, -66.0, 126.0, 136.0, 5.0, "wall", n=[door(-73.0)], s=[door(-70.0)], w=[window(131.0)])
    add_loot("Garage", "crate", -78.0, SHORE, 128.0)
    hall(-100.0, -86.0, 164.0, 176.0, 4.0, "wall", n=[door(-93.0)], e=[window(170.0)], w=[door(170.0)])
    add_loot("Shed", "crate", -98.0, SHORE, 174.0, table="field")
    container(-70.0, SHORE, 170.0, "z", "container_a", 2)
    container(-128.0, SHORE, 160.0, "x", "container_b", 1)
    # the barge line's way into the port: the barge office and a stack, offset
    hall(-58.0, -44.0, 110.0, 122.0, 5.0, "wall", n=[door(-51.0)], s=[door(-48.0)], e=[window(116.0)])
    add_loot("Offices", "crate", -56.0, SHORE, 112.0)
    box(-40.0, SHORE, 124.0, -37.6, SHORE + 5.2, 130.0, "container_c")
    # the quay edge: a row of containers (cover from the ship), gaps where the ways across, the ladders and the
    # cranes' legs are
    keep_clear = [(-131.0, -116.0), (-4.0, 9.0), (36.0, 42.0), (117.0, 125.0), (154.0, 172.0)]
    legs = [z + dz for z in (-96.0, -56.0, -16.0, 84.0, 140.0) for dz in (-5.0, 5.0)]
    apron = [-138.0, -86.0, -66.0, -40.0, 22.0, 70.0, 96.0, 108.0, 134.0, 150.0]
    z = -172.0
    n = 0
    while z < 176.0:
        if (not any(a - 3.5 < z < b + 3.5 for a, b in keep_clear) and not any(abs(z - l) < 4.5 for l in legs)
                and not any(abs(z - a) < 5.0 for a in apron)):
            quay_cover(n, z)
            n += 1
            z += 11.0
        else:
            z += 1.0
    # the forecastle: the windlasses, the bosun's store, a mast (cover up on the bow)
    for x in (40.0, 56.0):      # (0.36.17: 2 m in from the shaped bow's sides; were x 38 / 58)
        box(x - 1.5, FORECASTLE, -100.0, x + 1.5, FORECASTLE + 1.6, -96.0, "rust")
    room(44.0, 52.0, -102.0, -95.0, FORECASTLE, 2.6, "wall", s=[door(48.0)], e=[window(-98.5)], w=[window(-98.5)],
         roof="roof")
    box(47.5, FORECASTLE + 2.85, -99.0, 48.5, FORECASTLE + 12.0, -98.0, "rust")


# ---------------------------------------------------------------------------------------------- the ways across
GALLERY = 14.0      # the grain gallery's floor
LOADER = (21.5, 42.0)   # the ship loader's stairwell (x0, z0), against the ship's west side


WL = -1.6           # the foot of a ladder that reaches down into the sea (a swimmer's feet float at -1.3)


def water_ladders():
    """The ways out of the sea (0.33.6, swimming): ladders down into the water on the quay, the pier, the pontoon,
    the mole, the barges and every boat. A swimmer can only get out at one of these."""
    for z in WATER_LADDERS_QUAY:                                     # the quay face, at the gaps in its container row
        ladder(QUAY + 0.2, WL, z, 90, SHORE - WL, "Water")
    ladder(9.0, WL, -2.2, 180, PIER - WL, "Water")                   # the pier's north edge
    ladder(-12.0, WL, 37.3, 180, 0.8 - WL, "Water")                  # the pontoon
    ladder(2.0, WL, -117.8, 0, SHORE - WL, "Water")                  # the mole's south face
    for x in (-17.0, 0.0, 46.0):                                     # the barges' south sides
        ladder(x, WL, 126.2, 0, BARGE - WL, "Water")
    ladder(SX1 + 9.2, WL, -88.0, 90, BOAT - WL, "Water")             # the launch and the tug (sea side)
    ladder(SX1 + 11.2, WL, 45.0, 90, BOAT - WL, "Water")
    ladder(60.0, WL, SZ1 + 6.2, 0, 0.8 - WL, "Water")                # the stern dinghy
    ladder(68.2, WL, -125.0, 90, SHORE - WL, "Water")                # the pilot cutter


def crossings():
    # The pier (middle): a shed over the first stretch, then staggered containers; the roofed pipe gallery beside
    px0, px1 = QUAY + 6.0, SX0
    box(px0, PIER - 0.4, -2.0, px1, PIER, 7.2, "wood")
    ramp((QUAY, SHORE, 1.0), (px0, PIER, 1.0), 6.0, "wood")
    box(QUAY, PIER - 0.4, 4.4, px0, PIER, 7.2, "wood")
    ramp((QUAY, SHORE, 5.8), (px0, PIER, 5.8), 2.6, "wood")
    for x in range(-20, 30, 12):     # legs down to the sea bed
        box(x - 0.4, SEABED + 2, -2.0, x + 0.4, PIER - 0.4, -1.2, "rust")
        box(x - 0.4, SEABED + 2, 6.4, x + 0.4, PIER - 0.4, 7.2, "rust")
    wall("x", 4.4, QUAY, px1, PIER, 2.6, "rust", [(c, 1.6, 0.0, 2.2) for c in (-20.0, -4.0, 10.0, 22.0)], t=0.2)
    wall("x", 7.2, QUAY, px1, PIER, 2.6, "rust", t=0.2)
    box(QUAY, PIER + 2.6, 4.3, px1, PIER + 2.8, 7.3, "roof")
    # the pier shed
    wall("x", -2.0, -22.0, -4.0, PIER, 3.0, "wall", [window(-17.0), door(-13.0), window(-8.0)])
    box(-22.0, PIER + 3.0, -2.2, -4.0, PIER + 3.25, 4.4, "roof")
    for x in (-22.0, -4.0):
        box(x - 0.2, PIER, -2.0, x + 0.2, PIER + 3.0, -0.6, "wall")
    container(2.0, PIER, -0.8, "x", "container_b")
    container(12.0, PIER, 3.2, "x", "container_a", 2)
    box(17.0, PIER, -1.6, 19.0, PIER + 1.2, -0.4, "wood")
    labels.append(("PIER", -10, -6, 0))
    ramp((20.0, PIER, 0.0), (SX0, DECK, 0.0), 3.5, "metal")
    box(14.0, PIER - 0.4, -2.0, 20.0, PIER, 2.0, "wood")

    # The grain gallery (high, covered): from the headhouse at the quay to the ship loader beside the ship, small
    # windows, a door halfway out onto a balcony with a long ladder down to the pontoon
    gz0, gz1 = 42.0, 45.0
    gx0, gx1 = -38.0, LOADER[0]
    box(gx0, GALLERY - SLAB_T, gz0, gx1, GALLERY, gz1, "metal")
    wall("x", gz0, gx0, gx1, GALLERY, 2.6, "rust", [window(x, 1.2, 1.2, 2.0) for x in (-30.0, -18.0, 6.0, 16.0)]
         + [door(-4.0)], t=0.2)
    wall("x", gz1, gx0, gx1, GALLERY, 2.6, "rust", [window(x, 1.2, 1.2, 2.0) for x in (-24.0, -12.0, 0.0, 12.0)], t=0.2)
    box(gx0, GALLERY + 2.6, gz0 - 0.1, gx1, GALLERY + 2.85, gz1 + 0.1, "roof")
    for x in (-24.0, -8.0, 8.0):
        box(x - 0.5, SEABED, gz0 + 0.5, x + 0.5, GALLERY - SLAB_T, gz1 - 0.5, "rust")
    box(-6.0, GALLERY - SLAB_T, 40.4, -2.0, GALLERY, gz0, "metal")     # the balcony
    wall("z", -6.0, 40.4, gz0, GALLERY, 1.0, "rust", t=0.15)
    wall("z", -2.0, 40.4, gz0, GALLERY, 1.0, "rust", t=0.15)
    ladder(-4.0, 0.8, 40.3, 180, GALLERY - 0.8, "Gallery")
    labels.append(("GRAIN GALLERY", -8, 49, 0))
    # the ship loader: a stairwell tower against the ship's side, down to the main deck (a gap in the rail)
    stairwell(LOADER[0], LOADER[1], [GALLERY, 11.0, 7.5, DECK], {0: "W", 3: "E"})
    box(LOADER[0] + 8.0 - 0.1, DECK - SLAB_T, 53.2, SX0 + 0.6, DECK, 55.8, "metal")
    box(LOADER[0] + 3.0, GALLERY + 3.45, 44.0, LOADER[0] + 5.0, GALLERY + 12.0, 46.0, "rust")   # the loader's boom post
    footprints.append((LOADER[0], LOADER[1], LOADER[0] + 8.0, LOADER[1] + 14.0))
    labels.append(("LOADER", 18, 58, 0))
    # the pontoon under it, at the water: a ladder up the quay, a ladder up the ship's side
    box(QUAY, 0.4, 37.5, SX0 - 0.3, 0.8, 40.4, "wood")
    ladder(QUAY + 0.2, 0.8, 39.0, 90, SHORE - 0.8, "Pontoon")
    ladder(SX0 - 0.4, 0.8, 38.5, -90, DECK - 0.8, "Pontoon")

    # The breakwater (north): a wide mole (level with the quay) from the north quay to a pad under the bow; a wave wall on the sea side,
    # the signal hut on its north half, broken concrete blocks across the south half
    mz0, mz1 = -130.0, -118.0
    box(QUAY, SEABED, mz0, 36.0, SHORE, mz1, "rock")
    wall("x", mz0 + 0.4, QUAY, 60.0, SHORE, 2.6, "concrete", t=0.8)
    room(-2.0, 8.0, mz0 + 0.8, -124.0, SHORE, 3.0, "wall", w=[door(-126.5)], e=[door(-126.5)], s=[window(3.0, 3.0)],
         roof="roof")
    container(20.0, SHORE, -127.6, "x", "container_a", 2)
    for x, z, yaw, h in [(-18.0, -120.5, 30, 2.4), (-8.0, -122.0, -20, 2.0), (12.0, -120.0, 15, 2.6),
                         (22.0, -122.5, -35, 2.2), (30.0, -119.5, 40, 2.4), (-24.0, -126.0, 10, 2.2)]:
        obox(x, SHORE + h / 2, z, 3.4, h, 3.0, yaw, "concrete")
    box(36.0, SEABED, mz0, 60.0, SHORE, SZ0 - 0.3, "rock")        # the pad under the bow
    labels.append(("BREAKWATER", 0, -134, 0))
    ladder(48.0, SHORE, SZ0 - 0.4, 180, FORECASTLE - SHORE, "Bow")
    box(60.0, BOAT - 0.8, -128.0, 68.0, SHORE, -116.0, "wood")      # the pilot cutter moored at the pad (deck level with it)
    extracts.append(("BowBoat", "BOW PILOT BOAT", 64.0, SHORE, -120.0))
    room(61.5, 67.5, -123.0, -117.0, SHORE, 2.3, "wall", w=[door(-121.5)], s=[window(64.5, 2.0, 0.9, 1.9)], roof="roof")

    # The barge line (south): barges tied end to end from the quay to the stern ramp; containers and cabins across
    # each one, alternating sides, so the way across zigzags and nothing sees down its length
    barges = [(-26.0, -8.0), (-4.0, 14.0), (18.0, 30.0), (34.0, 54.0)]
    ramp((QUAY, SHORE, 121.0), (barges[0][0], BARGE, 121.0), 3.4, "wood")
    for i, (x0, x1) in enumerate(barges):
        z0, z1 = (112.0, 126.0) if i == len(barges) - 1 else (116.0, 126.0)
        box(x0, BARGE - 2.0, z0, x1, BARGE, z1, "rust")
        north = i % 2 == 0           # this barge's wall of cargo is on its north half
        ox = (x0 + x1) / 2 + (2.0 if i == len(barges) - 1 else 0.0)
        if i == len(barges) - 1:
            box(38.8, BARGE, 118.0, 41.2, BARGE + 5.2, z1, "container_a")
        elif north:
            box(ox - 1.2, BARGE, z0, ox + 1.2, BARGE + 5.2, 122.5, ("container_a", "container_b", "container_c")[i % 3])
        else:
            box(ox - 1.2, BARGE, 119.5, ox + 1.2, BARGE + 5.2, z1, ("container_a", "container_b", "container_c")[i % 3])
        box(x1 - 4.0, BARGE, (z0 + 0.5) if north else z1 - 3.5, x1 - 1.0, BARGE + 2.4, (z0 + 3.5) if north else z1 - 0.5, "wall")
        if i < len(barges) - 1:
            pz = (122.0, 125.0) if north else (116.5, 119.5)
            box(x1, BARGE - 0.3, pz[0], barges[i + 1][0], BARGE, pz[1], "wood")
    labels.append(("BARGE LINE", 10, 132, 0))
    player_spawns.append((-20.0, BARGE, 124.5))
    add_loot("Barges", "crate", 10.0, BARGE, 117.0, table="field")

    # The sea side (east): two boats moored against the hull, ladders up to the deck
    box(SX1 + 0.4, BOAT - 1.5, -96.0, SX1 + 9.0, BOAT, -80.0, "wood")
    box(SX1 + 0.4, BOAT - 1.5, 40.0, SX1 + 11.0, BOAT, 60.0, "rust")
    box(SX1 + 5.0, BOAT, 52.0, SX1 + 9.5, BOAT + 2.6, 58.0, "wall")    # the tug's wheelhouse
    ladder(SX1 + 0.4, BOAT, -88.0, 90, DECK - BOAT, "SeaSide")
    ladder(SX1 + 0.4, BOAT, 50.0, 90, DECK - BOAT, "SeaSide")
    player_spawns.append((SX1 + 5.0, BOAT, -92.0))
    player_spawns.append((SX1 + 7.0, BOAT, 44.0))
    labels.append(("TUG", SX1 + 10, 50, 0))

    water_ladders()

    # The stern ladder down to a dinghy (an extract)
    box(57.0, 0.2, SZ1 + 0.4, 63.0, 0.8, SZ1 + 6.0, "wood")
    ladder(60.0, 0.8, SZ1 + 0.4, 0, DECK - 0.8, "Stern")
    extracts.append(("SternLadder", "STERN LADDER", 60.0, 0.8, SZ1 + 3.5))
    box(56.8, 0.8, SZ1 + 0.6, 57.2, 2.8, SZ1 + 6.0, "wood")              # the screen on the barge side
    box(56.8, 2.8, SZ1 + 1.8, 63.2, 3.0, SZ1 + 6.0, "roof")              # the canopy (0.35.16: clear of a climber's head)


# ---------------------------------------------------------------------------------------------- the ship
# Openings in the decks
MOON = (38.0, 58.0, -9.0, 7.0)        # the moon pool: an open well from the drill floor down to the lab (0.33.2)
BOW_STAIRS = (44.0, 52.0, -88.0, -74.0)
TOWER_STAIRS = (54.0, 62.0, 76.0, 90.0)
HATCHES = [(42.0, 54.0, -50.0, -44.0), (42.0, 54.0, 24.0, 30.0)]
# (0.35.16: each stands at the inboard edge of its hatch and faces inboard, so you step off its top onto the hold's
# floor. Before, they were on the hull wall facing it, and at the top there was only the wall ahead.)
SIDE_LADDERS = [(SX0 + 1.9, -60.0, -90), (SX0 + 1.9, 50.0, -90), (SX1 - 1.9, -60.0, 90), (SX1 - 1.9, 50.0, 90)]
SERVICE_TUBE = (46.0, 48.4, -65.4, -63.0)
# (0.35.3, owner: "stair cases going up and down near the front/backs of the ship") both stairwells carry on down from
# the engine room deck to the lab's lower deck: four short flights, so the bottom landing is on the south end
def lab_flights():
    step = (HULL_B - LAB2) / 4
    return [HULL_B - step, HULL_B - 2 * step, HULL_B - 3 * step, LAB2]
# (0.33.7) ramps down through the main deck into the hold's side passages (x0, x1, z at the deck, z at the hold floor):
# aft on the sea side, forward on the port side
COMPANIONS = [(62.8, 65.4, 54.0, 72.0), (30.6, 33.2, -58.0, -40.0)]
BOAT_DOORS = (-84.0, 44.0)     # hull doors at the launch and the tug (the sea side), z


def hole(r, pad=0.0):
    return (r[0] - pad, r[1] + pad, r[2] - pad, r[3] + pad)


def ship():
    footprints.append((SX0, BOW_Z, SX1, STERN_Z))      # (0.36.17: the map screen shows the shaped bow and stern too)
    footprints.extend((48.0 - half, za, 48.0 + half, zb) for za, zb, half in hull_strips(SZ0, SZ1, 1.5))
    labels.append(("LEVIATHAN", 48, 30, 1))
    # (art step 1, model leviathan_hull: the hull's outside, the main deck, the drill floor)
    with modeled("leviathan_hull", 48.0, 0.0):
        hull_sides()
    hull_inside()
    with modeled("leviathan_hull", 48.0, 0.0):
        main_deck()


def hull_sides():
    # The hull's sides and ends, from the bottom to the rail above the main deck
    bottom = LAB2 - 2 * SLAB_T      # (0.35.2) the hull goes down round the lab decks
    top = DECK + BULWARK
    h = top - bottom
    gang = (0.0, 4.0, DECK - bottom, top - bottom)              # the gangway's gap in the rail
    hull_door = (5.8, 2.0, PIER - bottom, PIER - bottom + DOOR_H)  # from the pipe gallery into the hold's west passage
    west_gaps = [(38.5, 1.4, DECK - bottom, top - bottom), (54.5, 2.4, DECK - bottom, top - bottom)]   # pontoon, loader
    wall("z", SX0, BOW_Z, STERN_Z, bottom, h, "hull", [gang, hull_door] + west_gaps, t=0.5)
    sea_gaps = [(z, 1.4, DECK - bottom, top - bottom) for z in (-88.0, 50.0)]
    sea_gaps += [(z, 2.0, BOAT - bottom, BOAT - bottom + DOOR_H) for z in BOAT_DOORS]   # (0.33.7) hull doors off the boats
    wall("z", SX1, BOW_Z, STERN_Z, bottom, h, "hull", sea_gaps, t=0.5)
    stern_ramp = (48.0, 8.0, BARGE - SLAB_T - bottom, DECK - 0.5 - bottom)   # (0.33.7: from the barge deck up, shut below the waterline)
    stern_gap = (60.0, 1.4, DECK - bottom, top - bottom)
    wall("x", SZ1, SX0 + STERN_R, SX1 - STERN_R, bottom, h, "hull", [stern_ramp, stern_gap], t=0.5)   # the transom
    # the bow: higher, round the forecastle; the stem's flat front, the bow ladder's gap in its rail
    wall("x", SZ0, 48.0 - STEM, 48.0 + STEM, bottom, FORECASTLE + BULWARK - bottom, "hull",
         [(48.0, 1.4, FORECASTLE - bottom, FORECASTLE + BULWARK - bottom)], t=0.5)
    for x in (SX0, SX1):
        wall("z", x, BOW_Z, -90.0, DECK + BULWARK, FORECASTLE - DECK, "hull", t=0.5)
    # (0.36.17) the shaped bow and the stern's rounded corners: the plate in straight pieces along the outline
    for line, high in ((BOW_LINE, FORECASTLE + BULWARK), (STERN_LINE, top)):
        for side in (-1, 1):
            for (ha, za), (hb, zb) in zip(line, line[1:]):
                xa, xb = 48.0 + side * ha, 48.0 + side * hb
                length = math.hypot(xb - xa, zb - za)
                obox((xa + xb) / 2, (bottom + high) / 2, (za + zb) / 2, 0.5, high - bottom, length + 0.1,
                     math.degrees(math.atan2(xb - xa, zb - za)), "hull", kind="hull_curve")


def hull_inside():
    hull_slab(LAB2 - SLAB_T, "hull")   # the keel plate, under the lab's floors
    # Hull B: pump room forward, the bilge, the engine room aft
    hull_slab(HULL_B, "metal", holes=[hole(MOON), hole(BOW_STAIRS), hole(TOWER_STAIRS), hole(SERVICE_TUBE)])
    for z in (-56.0, 30.0):
        wall("x", z, SX0, SX1, HULL_B, HULL_A - SLAB_T - HULL_B, "metal", [door(36.0, 2.0), door(58.0, 2.0)])
    labels.append(("PUMP ROOM", 48, -80, 0))
    labels.append(("ENGINE ROOM", 48, 70, 0))
    for z in (44.0, 62.0, 80.0):        # the engines (cover; the aft one stands clear of the tower stairs)
        box(38.0, HULL_B, z - 3, 44.0, HULL_B + 2.4, z + 3, "rust")
        ex = 46.0 if z > 70 else 52.0
        box(ex, HULL_B, z - 3, ex + 6.0, HULL_B + 2.4, z + 3, "rust")
    box(62.0, HULL_B, 96.0, 65.5, HULL_B + 2.0, 100.0, "metal")   # the sub bay's power switch cabinet
    switches.append(("SubBayPower", "sub_bay", "Turn on the sub bay power", 61.7, HULL_B + 1.1, 98.0))
    labels.append(("SUB BAY POWER", 60, 98, 0))
    add_loot("EngineRoom", "crate", 47.0, HULL_B, 95.0, table="crate")
    add_loot("EngineRoom", "locker", 65.2, HULL_B, 90.0, -90)
    add_loot("PumpRoom", "crate", 36.0, HULL_B, -96.0)
    for z in (-40.0, -20.0, 8.0, 18.0):   # the bilge's tanks
        box(33.0, HULL_B, z - 2, 36.0, HULL_B + 2.0, z + 2, "rust")
        box(60.0, HULL_B, z - 2, 63.0, HULL_B + 2.0, z + 2, "rust")

    # Hull A (the cargo hold): side passages down both sides, the hold in the middle, workshops aft
    hull_slab(HULL_A, "metal", holes=[hole(MOON), hole(BOW_STAIRS), hole(TOWER_STAIRS)]
         + [(SX0 + 0.25 if x < 48 else x, x if x < 48 else SX1 - 0.25, z - 0.8, z + 0.8) for x, z, yaw in SIDE_LADDERS])
    for x, z, yaw in SIDE_LADDERS:
        ladder(x, HULL_B, z, yaw, HULL_A - HULL_B, "SideLadder")
    hold_h = DECK - SLAB_T - HULL_A
    doors_w = [door(z, 2.0) for z in (-80.0, -60.0 + 3, -36.0, -18.0, 16.0, 40.0, 60.0)]
    wall("z", 36.0, -92.0, 74.0, HULL_A, hold_h, "metal", doors_w)
    wall("z", 60.0, -92.0, 74.0, HULL_A, hold_h, "metal", doors_w)
    wall("x", -92.0, SX0, SX1, HULL_A, hold_h, "metal", [door(33.0, 2.0), door(40.0, 2.0), door(63.0, 2.0)])
    wall("x", 74.0, SX0, SX1, HULL_A, hold_h, "metal", [door(33.0, 2.0), door(48.0, 4.0), door(63.0, 2.0)])
    labels.append(("CARGO HOLD", 48, -30, 0))
    # the pipe gallery's hull door lands on a platform in the west passage, a ramp takes you down
    box(SX0 + 0.25, PIER - SLAB_T, 3.0, 35.75, PIER, 8.0, "metal")
    ramp((34.4, PIER, 8.0), (34.4, HULL_A, 23.0), 2.7, "metal")
    # the hold's containers: a maze of stacks, two stacks under each hatch to land on
    stacks = [(41, -82, 1), (56, -78, 2), (45, -66, 1), (55, -62, 2), (40, -56, 2), (45, -47, 2), (51, -40, 1),
              (39, -32, 1), (55, -28, 2), (44, -20, 2), (52, -14, 1), (40, 14, 1), (52, 16, 2), (45, 27, 2), (51, 36, 1),
              (40, 44, 2), (56, 50, 1), (46, 58, 2), (53, 66, 1)]
    for i, (x, z, high) in enumerate(stacks):
        container(x, HULL_A, z, "z" if i % 2 else "x", ("container_a", "container_b", "container_c")[i % 3], high)
    for i, (x, z) in enumerate([(48, -72), (37.5, -24), (57.5, 10), (49, 46), (38, 64), (56, -50)]):
        add_loot("Hold", "crate", x, HULL_A, z, 90 * (i % 2))
    # workshops aft, under the tower; the stern ramp up to the last barge
    wall("z", 44.0, 74.0, 96.0, HULL_A, hold_h, "metal", [door(80.0), door(92.0)])
    add_loot("Workshop", "crate", 40.0, HULL_A, 80.0, table="crate")
    add_loot("Workshop", "locker", 64.6, HULL_A, 100.0, -90)
    # (0.33.7) the ramp stays inside the hull and meets the stern door at barge height; a bridge plate crosses to
    # the barge. Before, the door was cut down to the hold floor, under the water.
    ramp((48.0, HULL_A, 96.0), (48.0, BARGE, SZ1 - 0.6), 7.6, "metal")
    box(44.2, BARGE - SLAB_T, SZ1 - 0.6, 51.8, BARGE, SZ1 + 2.6, "metal")
    for x in (44.2, 51.8):
        box(x - 0.1, BARGE, SZ1 + 0.3, x + 0.1, BARGE + 1.0, SZ1 + 2.6, "rust")
    labels.append(("WORKSHOPS", 52, 90, 0))


def main_deck():
    # The main deck: the moon pool deckhouse, the derrick, cranes and containers, the forecastle
    hull_slab(DECK, "metal", z0=-90.0,
         holes=[hole(MOON), hole(BOW_STAIRS), hole(TOWER_STAIRS)] + HATCHES + [(x0, x1, min(za, zb), max(za, zb)) for x0, x1, za, zb in COMPANIONS])
    # (0.33.7, owner: more ways down a floor) companionways: a ramp down through the deck into each side passage of
    # the hold, railed on the open sides; and a hull door off each moored boat onto a landing with a ramp down
    for x0, x1, za, zb in COMPANIONS:
        ramp(((x0 + x1) / 2, DECK, za), ((x0 + x1) / 2, HULL_A, zb), x1 - x0, "metal")
        inboard = x1 if x0 < 48 else x0
        wall("z", inboard, min(za, zb), max(za, zb), DECK, 1.0, "rust", t=0.15)
        wall("x", zb, x0, x1, DECK, 1.0, "rust", t=0.15)
    for z in BOAT_DOORS:
        dz = 1 if z < 0 else -1          # the ramp runs away from the nearest end of the hold
        box(60.25, BOAT - SLAB_T, z - 2.5, SX1 - 0.25, BOAT, z + 2.5, "metal")
        ramp((61.7, BOAT, z + 2.5 * dz), (61.7, HULL_A, z + 17.5 * dz), 2.7, "metal")
        wall("z", 63.1, min(z + 2.5 * dz, z + 8.0 * dz), max(z + 2.5 * dz, z + 8.0 * dz), BOAT, 1.0, "rust", t=0.15)
        wall("x", z + 2.5 * dz, 63.1, SX1 - 0.25, BOAT, 1.0, "rust", t=0.15)
        wall("x", z - 2.5 * dz, 60.25, SX1 - 0.25, BOAT, 1.0, "rust", t=0.15)
    hull_slab(DECK, "metal", z1=-90.0)
    for x0, x1, z0, z1 in HATCHES:   # a low coaming round each open hatch
        room(x0 - 0.3, x1 + 0.3, z0 - 0.3, z1 + 0.3, DECK, 0.5, "rust", t=0.3)
    labels.append(("HATCHES", 48, -54, 0))
    # the forecastle: a raised deck over the bow store, a ramp up
    hull_slab(FORECASTLE, "metal", holes=[(SX0, 34.5, -93.5, -90.0)], z1=-90.0)
    wall("x", -90.0, 34.5, SX1, DECK, FORECASTLE - DECK - SLAB_T, "hull", [door(40.0, 2.0), door(58.0, 2.0)])
    wall("x", -90.0, SX0, 34.5, FORECASTLE, BULWARK, "hull", [(32.2, 4.0, 0.0, BULWARK)])
    ramp((32.2, DECK, -80.0), (32.2, FORECASTLE, -93.5), 4.0, "metal")
    add_loot("BowStore", "crate", 39.0, DECK, -99.0)    # (0.36.17: in from the shaped bow's sides; were x 36 / 60, z -100)
    add_loot("BowStore", "crate", 57.0, DECK, -99.0)
    labels.append(("FORECASTLE", 48, -98, 0))
    # cranes and deck cargo (v3): pipe racks and containers placed so no lane runs the length of the deck; the
    # drill floor (drill_floor) roofs the middle and splits the deck in two
    for x, z in [(34.0, -62.0), (34.0, 30.0), (34.0, 52.0)]:
        box(x - 1.2, DECK, z - 1.2, x + 1.2, DECK + 9.0, z + 1.2, "rust")
        obox(x + 6, DECK + 9.4, z, 13.0, 0.8, 1.0, 0, "rust")
    for x0, z0, x1, z1 in [(38.0, -66.0, 52.0, -63.0), (44.0, -38.0, 47.0, -26.0)]:   # pipe racks
        box(x0, DECK, z0, x1, DECK + 2.0, z1, "rust")
    for i, (x, z, along, high) in enumerate([(36, -80, "z", 2), (59, -82, "x", 1), (60, -62, "z", 2), (64, -56, "z", 1),
                                             (36, -46, "z", 1), (60, -48, "z", 2), (54, -32, "x", 2), (40, -22, "x", 1),
                                             (63, -24, "x", 1), (40, 40, "z", 2), (56, 46, "x", 1), (44, 62, "x", 1),
                                             (58, 66, "z", 2), (37, 60, "z", 2), (50, 36, "x", 2), (59, 54, "x", 1),
                                             (32.5, 46, "z", 1)]):
        container(x, DECK, z, along, ("container_b", "container_a", "container_c")[i % 3], high)
    for i, (x, z) in enumerate([(51, -70), (37, 36), (52, 58)]):
        add_loot("Deck", "crate", x, DECK, z, 90 * (i % 2))
    labels.append(("MAIN DECK", 48, 46, 0))


def moon_pool():
    """The moon pool (0.33.2, owner: "not a huge staircase, endlessly turning corners"): an open well through the
    whole ship, from the drill floor down past the main deck, the hold and the engine room deck to the lab's dock
    (0.35.2: the dock is the next deck down, inside the hull). Railings round it on every deck. From the engine room
    deck two ramps go down round the trunk's walls, open to the middle, so you see who's above and below you. The
    riser (the drill pipe) hangs down the middle, with a catwalk out to it and a ladder down it: the fast, exposed
    way. The trunk opens wide onto the dock."""
    x0, x1, z0, z1 = MOON
    W = 2.6
    bottom = LAB1 - SLAB_T
    # the trunk's walls, from the engine room deck down to the dock (0.35.2: one deck, the lab is inside the hull)
    h = HULL_B - SLAB_T - bottom
    wall("x", z0, x0, x1, bottom, h, "hull", t=0.4)
    wall("x", z1, x0, x1, bottom, h, "hull", [(48.0, 12.0, 0.0, 3.8)], t=0.4)       # wide open onto the dock
    wall("z", x0, z0, z1, bottom, h, "hull", t=0.4)
    wall("z", x1, z0, z1, bottom, h, "hull", t=0.4)
    # two ramps round the trunk's walls: along the north wall east, a landing, the east wall south to the dock's deck
    mid = (HULL_B + LAB1) / 2
    runs = [((x0, HULL_B, z0 + W / 2), (x1 - W, mid, z0 + W / 2)),
            ((x1 - W / 2, mid, z0 + W), (x1 - W / 2, LAB1, z1 - W))]
    for a, b in runs:
        ramp(a, b, W)
    box(x1 - W, mid - SLAB_T, z0, x1, mid, z0 + W, "metal")
    # posts along the open side of the runs (railings, gray box)
    for (ax, ay, az), (bx, by, bz) in runs:
        for i in range(5):
            f = (i + 0.5) / 5
            px, py, pz = ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f
            ox = 0.0 if ax != bx else (-W / 2 if ax > 48 else W / 2)
            oz = 0.0 if az != bz else (W / 2 if az < 0 else -W / 2)
            box(px + ox - 0.08, py, pz + oz - 0.08, px + ox + 0.08, py + 1.0, pz + oz + 0.08, "rust")
    add_loot("LabWing", "crate", x0 + 1.5, LAB1, z1 - 1.5, 90)
    # the riser: the drill pipe down the middle, a catwalk out to it from the hull's bottom deck, a ladder down it
    with modeled("leviathan_hull", 48.0, 0.0):
        box(47.2, LAB1, -1.8, 48.8, 41.0, -0.2, "rust")
    slab(44.0, 52.0, -5.0, 3.0, HULL_B, "metal", holes=[(47.2, 48.8, -1.8, 1.2)])
    box(x0, HULL_B - SLAB_T, -2.2, 44.0, HULL_B, 0.2, "metal")
    wall("x", -5.0, 44.0, 52.0, HULL_B, 1.0, "rust", t=0.12)
    wall("x", 3.0, 44.0, 52.0, HULL_B, 1.0, "rust", t=0.12)
    wall("z", 52.0, -5.0, 3.0, HULL_B, 1.0, "rust", t=0.12)
    # (0.35.16: the ladder faces away from the pipe, at the hatch's south edge, so its top steps off onto the catwalk)
    ladder(48.0, LAB1, 1.2, 180, HULL_B - LAB1, "Riser")
    labels.append(("MOON POOL", 48, -12, 0))
    # railings round the well: on the hull's bottom deck (gaps for the first ramp and the catwalk), and above
    wall("x", z1, x0, x1, HULL_B, 1.0, "rust", t=0.15)
    wall("z", x0, z0, z1, HULL_B, 1.0, "rust", [(z0 + W / 2, W + 0.2, 0.0, 1.0), (-1.0, 2.6, 0.0, 1.0)], t=0.15)
    wall("z", x1, z0, z1, HULL_B, 1.0, "rust", t=0.15)
    room(x0, x1, z0, z1, HULL_A, 1.1, "rust", t=0.15)
    with modeled("leviathan_hull", 48.0, 0.0):    # (art step 1: the rails on the open decks and the riser)
        for y in (DECK, DRILL):
            room(x0, x1, z0, z1, y, 1.1, "rust", t=0.15)


def drill_floor():
    """The drill floor (v3): a deck at y 12 over the middle of the ship (x 30..66, z -14..14), the derrick on it, the
    driller's shack, pipe racks. It roofs the midship and splits the deck in two. Two ramps up (west side from the
    fore deck, east side from the aft deck); the moon pool's well goes down through the middle of it (0.33.2)."""
    x0, x1, z0, z1 = SX0 + 0.25, SX1 - 0.25, -14.0, 14.0
    slab(x0, x1, z0, z1, DRILL, "metal", holes=[hole(MOON)])
    for x, z in [(31.0, -13.0), (63.0, -13.0), (31.0, 11.0), (63.0, 11.0)]:
        box(x, DECK, z, x + 2.0, DRILL - SLAB_T, z + 2.0, "rust")
    wall("x", z0, x0, x1, DRILL, 1.1, "rust", [(33.0, 3.4, 0.0, 1.1)], t=0.2)
    wall("x", z1, x0, x1, DRILL, 1.1, "rust", [(63.0, 3.4, 0.0, 1.1)], t=0.2)
    wall("z", x0, z0, z1, DRILL, 1.1, "rust", t=0.2)
    wall("z", x1, z0, z1, DRILL, 1.1, "rust", t=0.2)
    ramp((33.0, DECK, -36.0), (33.0, DRILL, z0), 3.2, "metal")
    ramp((63.0, DECK, 36.0), (63.0, DRILL, z1), 3.2, "metal")
    for x, z in [(37.0, -10.0), (59.0, -10.0), (37.0, 8.0), (59.0, 8.0)]:   # the derrick, legs either side of the well
        box(x - 0.4, DRILL, z - 0.4, x + 0.4, 40.0, z + 0.4, "rust")
    box(36.6, 40.0, -10.4, 59.4, 41.0, 8.4, "rust")
    room(44.0, 52.0, 8.5, 13.5, DRILL, 3.0, "wall", w=[door(11.0)], e=[door(11.0)], n=[window(48.0)], s=[window(48.0)],
         roof="roof")
    box(31.0, DRILL, 8.0, 41.0, DRILL + 1.4, 11.0, "rust")      # pipe rack
    box(31.0, DRILL, -6.0, 35.0, DRILL + 2.0, -1.0, "metal")    # the drawworks
    add_loot("Workshop", "crate", 50.5, DRILL, 12.5, table="crate")
    add_loot("Deck", "crate", 36.0, DRILL, 1.0)
    labels.append(("DRILL FLOOR", 48, -18, 0))


def bow_stairs():
    stairwell(BOW_STAIRS[0], BOW_STAIRS[2], [DECK, 0.0, HULL_A, HULL_B] + lab_flights(), {0: "W", 2: "W", 3: "W", 7: "S"})
    # (0.35.33) at the bottom, the stairs open into Site Zero's intake hall (lab())


def tower():
    """The bridge tower: armory on the main deck, crew deck, officers' deck, the bridge, the helideck roof."""
    footprints.append((TX0, TZ0, TX1, TZ1))
    labels.append(("BRIDGE TOWER", 48, 70, 0))
    floors = [(DECK, "ARMORY"), (DECK2, "CREW"), (DECK3, "OFFICERS"), (DECK4, "BRIDGE")]
    for i, (y, _) in enumerate(floors):
        h = (floors[i + 1][0] if i + 1 < len(floors) else ROOF) - y - SLAB_T
        if i == 0:
            n, s = [door(40.0, 2.0), door(50.0, 2.0)], [door(44.0, 2.0)]
            w, e = [window(84.0), window(98.0)], [window(98.0)]
        elif i == 3:   # the bridge: windows all round
            n = [window(x, 3.0, 0.9, 2.4) for x in (38.0, 44.0, 50.0)]
            s, w, e = [window(44.0)], [window(z, 3.0, 0.9, 2.4) for z in (80.0, 92.0, 100.0)], [window(98.0)]
        else:
            n = [window(x) for x in (38.0, 44.0, 50.0)]
            s, w, e = [window(40.0), window(50.0)], [window(z) for z in (80.0, 92.0, 100.0)], [window(98.0)]
        room(TX0, TX1, TZ0, TZ1, y, h, "wall", n, s, w, e)
        if i > 0:
            slab(TX0, TX1, TZ0, TZ1, y, "metal", holes=[hole(TOWER_STAIRS)])
        # a corridor across the middle, rooms either side
        wall("x", 87.0, TX0, 54.0, y, h, "wall", [door(38.0), door(48.0)])
        wall("x", 93.0, TX0, 54.0, y, h, "wall", [door(38.0), door(48.0)])
        wall("z", 44.0, TZ0, 87.0, y, h, "wall", [door(81.0)])
        wall("z", 44.0, 93.0, TZ1, y, h, "wall", [door(99.0)])
    slab(TX0, TX1, TZ0, TZ1, ROOF, "metal", holes=[hole(TOWER_STAIRS)])
    wall("x", TZ0, TX0, TX1, ROOF, 1.0, "rust", t=0.2)
    wall("x", TZ1, TX0, TX1, ROOF, 1.0, "rust", [(58.0, 1.6, 0.0, 1.0)], t=0.2)
    wall("z", TX0, TZ0, TZ1, ROOF, 1.0, "rust", t=0.2)
    wall("z", TX1, TZ0, TZ1, ROOF, 1.0, "rust", [(77.5, 2.0, 0.0, 1.0)], t=0.2)
    labels.append(("HELIDECK", 44, 100, 0))
    perches.append((40.0, ROOF, 77.0, -1, 0))
    stairwell(TOWER_STAIRS[0], TOWER_STAIRS[2], [ROOF, DECK4, DECK3, DECK2, DECK, 0.0, HULL_A, HULL_B] + lab_flights(),
              {0: "W", 1: "W", 2: "W", 3: "W", 4: "W", 6: "W", 7: "W", 11: "W"}, roof=True)
    # the outside ladder up the back, from the aft deck to the helideck
    ladder(58.0, DECK, TZ1 + 0.4, 0, ROOF - DECK, "Tower")
    # loot by room
    add_loot("ShipArmory", "locker", 36.0, DECK, 76.0, 0)
    add_loot("ShipArmory", "locker", 41.0, DECK, 76.0, 0)
    add_loot("ShipArmory", "crate", 38.0, DECK, 85.0)
    add_loot("Crew", "locker", 36.0, DECK2, 100.0, 180)
    add_loot("Crew", "locker", 50.0, DECK2, 104.0, 180)
    add_loot("Galley", "crate", 50.0, DECK2, 78.0, table="crate")
    add_loot("Galley", "crate", 36.0, DECK2, 84.0, table="crate")
    add_loot("SickBay", "crate", 36.0, DECK3, 78.0)
    add_loot("SickBay", "locker", 42.5, DECK3, 85.0, 90)
    add_loot("Officers", "locker", 36.0, DECK3, 104.0, 180)
    add_loot("Officers", "crate", 52.0, DECK3, 100.0)
    add_loot("ShipBridge", "safe", 36.0, DECK4, 104.0, 180)
    add_loot("ShipBridge", "safe", 52.0, DECK4, 78.0)


# ---------------------------------------------------------------------------------------------- Site Zero
def lab():
    """Site Zero (0.35.33 layout, owner: "if you were an architect who was an expert at designing labs and also an expert
    game designer"): the ship's two lowest decks, laid out like a real containment lab. Clean to dirty from the bow:
    INTAKE (the bow stairs and the service tube land at the security checkpoint; lockers west, security east), two
    DECON airlocks (each with a side room round it), the MAIN LAB (one open two-storey floor: the cleanroom pod, the
    cold store racks, an office mezzanine with the director's office), the HUB under the moon pool, HOLDING (the cells,
    a third lane down the middle), then the RING round the INCUBATION HALL (Raijin's room: the growth tanks), and
    OPERATIONS aft (control room, the tower stairs' lobby, the server room, quarters). Upstairs (LAB1) the dock with the
    sub bay and the OBSERVATION room that looks down into the hall, with a balcony and a ladder down.
    Three ways in stay where they were (bow stairs + service tube, moon pool to the dock, tower stairs); the corridors
    jog round the hall, so no lane runs the length of the lab."""
    labels.append(("SITE ZERO (BELOW)", 48, 20, 0))
    H = LAB1 - SLAB_T - LAB2            # the lower deck's rooms go up to the dock deck's floor
    l0, l1 = 30.0, 66.0                 # (the hull's sides are the outer walls)
    WR, WC, EC, ER = 37.0, 40.5, 55.5, 59.0   # columns: rooms by the west hull | corridor | middle | corridor | rooms
    wcx, ecx = (WR + WC) / 2, (EC + ER) / 2   # the corridors' middles
    cw = WC - WR                        # corridor width (3.5)
    hx0, hx1, hz0, hz1 = 36.0, 60.0, 38.0, 62.0   # the incubation hall (as before: the owner likes this room)
    tx0, tx1, tz0, tz1 = SERVICE_TUBE

    def low(x0, z0, x1, z1, h=1.1, colour="lab"):     # a bench, counter or console: cover to crouch behind
        box(x0, LAB2, z0, x1, LAB2 + h, z1, colour)

    # ---- the floors: the lower deck's floor, its ceiling (the dock deck), the dock
    slab(l0, l1, -74.0, 100.0, LAB2, "labfloor")
    slab(l0, l1, -74.0, -46.0, LAB1, "lab", holes=[(tx0 - 0.3, tx1 + 0.3, tz0 - 0.3, tz1 + 0.3)])
    slab(l0, l1, -10.0, 7.0, LAB1, "lab")
    slab(l0, l1, 7.0, 27.0, LAB1, "labfloor", holes=[(l0, 34.6, 10.0, 25.0)])
    slab(l0, l1, 27.0, 100.0, LAB1, "lab", holes=[(hx0, hx1, hz0, hz1), hole(TOWER_STAIRS)])
    # the ends
    wall("x", -74.0, l0, BOW_STAIRS[0], LAB2, H, "lab")
    wall("x", -74.0, BOW_STAIRS[1], l1, LAB2, H, "lab")
    wall("x", 100.0, l0, l1, LAB2, H, "lab")

    # ---- INTAKE (z -74..-46): the bow stairs' door (x 50) and the service tube come into the checkpoint hall
    labels.append(("INTAKE", 41, -67, 0))
    wall("z", WR, -74.0, -46.0, LAB2, H, "lab", [door(-62.0), door(-51.0)])   # the locker room (decon showers at its south end)
    wall("z", ER, -74.0, -46.0, LAB2, H, "lab", [door(-62.0), window(-68.0, 2.4), door(-51.0)])   # the security office
    room(tx0 - 0.3, tx1 + 0.3, tz0 - 0.3, tz1 + 0.3, LAB2, HULL_B - SLAB_T - LAB2, "lab", s=[(47.2, DOOR_W, 0.0, DOOR_H)])
    ladder(47.2, LAB2, tz0 + 0.1, 0, HULL_B - LAB2, "ServiceTube")
    labels.append(("SERVICE TUBE", 47, -66, 0))
    low(51.5, -66.0, 56.0, -65.0)            # the security desk, an L facing the stairs
    low(55.0, -65.0, 56.0, -61.0)
    low(41.0, -60.0, 45.0, -59.4, 1.0)       # the queue rails before the airlocks
    low(51.0, -60.0, 55.0, -59.4, 1.0)
    for z in (-72.5, -68.0, -64.0):          # lockers along the hull, benches down the middle
        box(30.3, LAB2, z - 1.2, 31.0, LAB2 + 2.0, z + 1.2, "rust")
    low(32.8, -70.0, 33.6, -60.0, 0.5, "wood")
    for z in (-54.0, -48.5):                 # the showers
        box(30.3, LAB2, z - 0.1, 33.5, LAB2 + 2.2, z + 0.1, "lab")
    low(60.5, -73.5, 65.5, -72.5, 1.0, "core")   # the security office's monitor desk, a weapons cage
    box(63.0, LAB2, -58.0, 65.7, LAB2 + 2.4, -54.0, "rust")
    # the decon airlocks (z -56..-46) with a shower nib each side; the air plant between them
    wall("x", -56.0, WR, WC, LAB2, H, "lab", [door(wcx, cw - 0.6)])
    wall("x", -56.0, EC, ER, LAB2, H, "lab", [door(ecx, cw - 0.6)])
    wall("x", -56.0, WC, EC, LAB2, H, "lab")
    wall("z", WC, -56.0, -46.0, LAB2, H, "lab")
    wall("z", EC, -56.0, -46.0, LAB2, H, "lab")
    labels.append(("DECON", 38, -51, 0))
    labels.append(("DECON", 57, -51, 0))
    labels.append(("AIR PLANT", 48, -51, 0))
    for x in (43.5, 52.5):                   # the air handlers
        box(x - 1.5, LAB2, -54.5, x + 1.5, LAB2 + 3.0, -51.0, "metal")
    add_loot("LabWing", "crate", 48.0, LAB2, -54.5)

    # ---- the MAIN LAB (z -46..-10; owner: not "just a bunch of rooms together"): one open, two-storey lab floor up to
    # the engine room deck. The cleanroom (a glass pod) in the middle, freezer racks and specimen benches along the west
    # hull, an instrument bay; the office mezzanine along the east hull (a ramp up, a ladder at its north end), the
    # director's office at its south end overlooking the floor
    HH = HULL_B - SLAB_T - LAB2
    wall("x", -46.0, l0, l1, LAB2, HH, "lab", [door(wcx, cw - 0.6), door(48.0), door(ecx, cw - 0.6)])
    wall("x", -10.0, l0, WR, LAB2, H, "lab")
    wall("x", -10.0, WR, ER, LAB2, H, "lab", [(40.0, 5.0, 0.0, 3.6), (48.0, 4.0, 0.0, 3.6), (56.0, 5.0, 0.0, 3.6)])
    wall("x", -10.0, ER, l1, LAB2, H, "lab")
    wall("x", -10.0, l0, l1, LAB1 - SLAB_T, HULL_B - LAB1, "lab")    # (closes the space over the hub)
    labels.append(("MAIN LAB", 44, -20, 1))
    # the cleanroom: waist-high walls, glass above (gray box: open), a roof; doors north and south
    px0, px1, pz0, pz1 = 39.0, 47.0, -39.0, -29.0
    for z in (pz0, pz1):
        wall("x", z, px0, px1, LAB2, 1.1, "lab", [door(43.0)], t=0.2)
        box(px0, LAB2 + 2.6, z - 0.1, px1, LAB2 + 3.2, z + 0.1, "lab")
    for x in (px0, px1):
        wall("z", x, pz0, pz1, LAB2, 1.1, "lab", t=0.2)
        box(x - 0.1, LAB2 + 2.6, pz0, x + 0.1, LAB2 + 3.2, pz1, "lab")
    for x, z in ((px0, pz0), (px1, pz0), (px0, pz1), (px1, pz1)):
        box(x - 0.2, LAB2, z - 0.2, x + 0.2, LAB2 + 3.2, z + 0.2, "lab")
    slab(px0, px1, pz0, pz1, LAB2 + 3.45, "lab")
    labels.append(("CLEANROOM", 43, -34, 0))
    low(40.5, -35.0, 45.5, -33.8)
    # bench islands round it, an instrument bay (the sequencers: tall) south of it
    for x0, z0, x1, z1 in ((49.5, -43.5, 50.7, -36.0), (49.5, -32.0, 50.7, -25.0), (39.0, -24.5, 45.0, -23.3),
                           (34.5, -44.0, 36.0, -38.0)):
        low(x0, z0, x1, z1)
    for x0, z0, x1, z1 in ((44.0, -19.0, 47.0, -16.5), (49.5, -19.0, 51.5, -14.0)):
        box(x0, LAB2, z0, x1, LAB2 + 2.4, z1, "metal")
    # the west hull: freezer racks (cold store), the specimen benches
    labels.append(("COLD STORE", 32, -40, 0))
    for z in (-44.5, -41.0, -37.5, -34.0):
        box(30.3, LAB2, z - 0.6, 32.6, LAB2 + 2.4, z + 0.6, "metal")
    add_loot("LabWing", "crate", 31.5, LAB2, -31.0, 90)
    labels.append(("SPECIMEN PREP", 33, -19, 0))
    low(30.3, -26.0, 31.5, -13.0, 1.0)
    low(34.0, -21.0, 35.6, -16.0)
    add_loot("LabWing", "crate", 31.5, LAB2, -11.8, 90)
    # under the mezzanine: the wet benches and shelving along the east hull
    low(64.0, -40.0, 65.7, -31.0)
    box(64.9, LAB2, -27.0, 65.7, LAB2 + 2.2, -14.0, "metal")
    low(60.0, -22.0, 61.6, -17.0)
    # the east mezzanine (at the dock deck's height): a ramp up from the floor, a ladder at its north end
    mx = 58.0
    slab(mx, l1, -42.0, -10.0, LAB1, "metal")
    ramp((53.5, LAB2, -42.0), (53.5, LAB1, -27.0), 3.0, "metal")
    slab(52.0, mx, -27.0, -24.0, LAB1, "metal")                      # the ramp's top landing
    wall("x", -24.0, 52.0, mx, LAB1, 1.0, "rust", t=0.15)
    wall("z", 52.0, -27.0, -24.0, LAB1, 1.0, "rust", t=0.15)
    wall("z", mx, -42.0, -10.0, LAB1, 1.0, "rust", [(-25.5, 3.0, 0.0, 1.0)], t=0.15)
    wall("x", -42.0, mx, 61.0, LAB1, 1.0, "rust", t=0.15)
    wall("x", -42.0, 63.0, l1, LAB1, 1.0, "rust", t=0.15)
    ladder(62.0, LAB2, -42.1, 180, LAB1 - LAB2, "Mezzanine")
    labels.append(("OFFICES (UPPER)", 62, -32, 0))
    for z in (-38.0, -31.0):                 # open-plan desks
        box(61.0, LAB1, z - 0.6, 64.5, LAB1 + 0.8, z + 0.6, "wood")
    add_loot("LabWing", "crate", 64.6, LAB1, -35.0, -90)
    # the director's office: glass onto the lab floor, the safe
    h1m = HULL_B - SLAB_T - LAB1
    wall("x", -22.0, mx, l1, LAB1, h1m, "lab", [door(61.0)])
    wall("z", mx, -22.0, -10.0, LAB1, h1m, "lab", [window(-19.0, 2.4, 1.0, 2.4), window(-14.0, 2.4, 1.0, 2.4)])
    labels.append(("DIRECTOR", 62, -16, 0))
    box(60.5, LAB1, -17.5, 63.0, LAB1 + 0.8, -15.5, "wood")
    add_loot("LabWing", "safe", 64.6, LAB1, -12.0, -90)
    wall("x", 10.0, l0, WR, LAB2, H, "lab")     # (the hub's side rooms' south walls)
    wall("x", 10.0, ER, l1, LAB2, H, "lab")

    # ---- the HUB (z -10..10), under the moon pool: washrooms west, the break room east, the sample lift in the middle
    labels.append(("HUB", 48, -6, 0))
    wall("z", WR, -10.0, 10.0, LAB2, H, "lab", [door(0.0)])
    wall("z", ER, -10.0, 10.0, LAB2, H, "lab", [door(-5.0), door(5.0)])
    box(45.5, LAB2, -2.5, 50.5, LAB2 + H, 2.5, "core")               # the sample lift's shaft (cover)
    box(WR + 0.4, LAB2, -4.2, WC - 0.4, LAB2 + 2.4, -2.6, "metal")    # notice boards where the corridors cross the
    box(EC + 0.4, LAB2, -0.8, ER - 0.4, LAB2 + 2.4, 0.8, "metal")     # hub: the corridors' lines stop here
    low(41.5, 4.0, 43.5, 7.0, 1.0)                                   # benches
    low(52.5, -7.0, 54.5, -4.0, 1.0)
    labels.append(("WASHROOMS", 33, 0, 0))
    for z in (-8.0, -5.0, -2.0):             # stalls
        box(30.3, LAB2, z - 0.05, 32.5, LAB2 + 2.0, z + 0.05, "lab")
    wall("x", 1.5, l0, WR, LAB2, H, "lab", [door(34.0, 2.2)])     # (the men's and women's sides)
    labels.append(("BREAK ROOM", 62, 0, 0))
    low(61.0, -3.0, 64.0, 3.0, 0.8, "wood")
    box(65.0, LAB2, -8.5, 65.7, LAB2 + 2.0, -6.0, "metal")           # the vending machine

    # ---- HOLDING (z 10..32): cells either side of a middle aisle; receiving (the dock's freight ramp) west, the
    # med bay east
    wall("x", 10.0, WC, EC, LAB2, H, "lab", [door(48.0)])
    wall("x", 32.0, WC, EC, LAB2, H, "lab", [door(48.0)])
    wall("z", WC, 10.0, 32.0, LAB2, H, "lab")
    wall("z", EC, 10.0, 32.0, LAB2, H, "lab")
    labels.append(("HOLDING", 48, 21, 0))
    for side, (cx0, cx1) in (("w", (WC, 46.0)), ("e", (50.0, EC))):
        front = cx1 if side == "w" else cx0
        for z0, z1 in ((10.0, 17.3), (17.3, 24.6), (24.6, 32.0)):
            # a cell: glass front (a waist-high wall, open above: shoot over it), a door in it
            wall("z", front, z0, z1, LAB2, 1.0, "lab", [door((z0 + z1) / 2, 2.2)], t=0.2)
            box(front - 0.1, LAB2 + 2.6, z0, front + 0.1, LAB2 + H, z1, "lab")
            if z1 < 32.0:
                wall("x", z1, cx0, cx1, LAB2, H, "lab")
            low(cx0 + 0.3 if side == "w" else cx1 - 1.2, z0 + 1.5, cx0 + 1.2 if side == "w" else cx1 - 0.3, z0 + 3.5, 0.6)
    wall("z", WR, 10.0, 32.0, LAB2, H, "lab", [door(29.0)])
    labels.append(("RECEIVING", 33, 30, 0))
    ramp((32.3, LAB1, 10.0), (32.3, LAB2, 25.0), 4.0, "labfloor")   # the dock's freight ramp (as before)
    wall("z", 34.6, 10.0, 25.0, LAB1, 1.0, "lab")
    box(34.8, LAB2, 13.0, 36.7, LAB2 + 1.6, 17.0, "wood")            # pallets
    add_loot("LabWing", "crate", 35.5, LAB2, 30.5, 180)
    wall("z", ER, 10.0, 32.0, LAB2, H, "lab", [door(14.0), door(28.0)])
    labels.append(("MED BAY", 62, 21, 0))
    for z in (13.0, 18.0, 23.0):             # beds
        low(63.5, z - 1.0, 65.7, z + 1.0, 0.7)
    add_loot("LabWing", "crate", 64.5, LAB2, 29.5, -90)

    # ---- the RING (z 32..68) round the INCUBATION HALL; it joins the corridors north and south
    wall("x", 32.0, l0, WR, LAB2, H, "lab")
    wall("x", 32.0, ER, l1, LAB2, H, "lab")
    wall("x", 68.0, l0, WR, LAB2, H, "lab")
    wall("x", 68.0, WC, 54.0, LAB2, H, "lab", [door(47.0)])
    wall("x", 68.0, ER, l1, LAB2, H, "lab")
    labels.append(("RING", 33, 50, 0))
    hh = HULL_B - SLAB_T - LAB2
    room(hx0, hx1, hz0, hz1, LAB2, hh, "core",
         n=[door(48.0, 4.0), (48.0, 3.0, 6.0, 9.0)] + [window(x, 2.0, 7.0, 8.4) for x in (40.0, 44.0, 52.0, 56.0)],
         s=[door(48.0, 2.4)], w=[door(50.0), window(43.0), window(57.0)], e=[door(50.0), window(43.0), window(57.0)])
    labels.append(("INCUBATION HALL", 48, 50, 1))
    # the growth tanks (owner: "those things where they keep living science experiments"): four in the corners on
    # plinths, a console in front of each; Raijin's own tank in the middle, broken open (a ring of low shards)
    for x, z in [(40.0, 44.0), (56.0, 44.0), (40.0, 56.0), (56.0, 56.0)]:
        box(x - 1.6, LAB2, z - 1.6, x + 1.6, LAB2 + 0.5, z + 1.6, "core")
        box(x - 1.3, LAB2 + 0.5, z - 1.3, x + 1.3, LAB2 + 4.5, z + 1.3, "lab")
        box(x - 1.5, LAB2 + 4.5, z - 1.5, x + 1.5, LAB2 + 5.0, z + 1.5, "core")
        cx, cz = x + (2.6 if x < 48 else -2.6), z + (2.6 if z < 50 else -2.6)
        low(cx - 0.6, cz - 0.6, cx + 0.6, cz + 0.6, 1.1, "core")
    box(46.2, LAB2, 50.2, 49.8, LAB2 + 0.5, 53.8, "core")
    for x0, z0, x1, z1, h in ((46.2, 50.2, 49.8, 50.6, 1.3), (46.2, 53.4, 47.6, 53.8, 0.9), (48.6, 53.4, 49.8, 53.8, 1.6),
                              (46.2, 50.6, 46.6, 52.0, 1.0), (49.4, 51.6, 49.8, 53.4, 1.2)):
        box(x0, LAB2 + 0.5, z0, x1, LAB2 + 0.5 + h, z1, "lab")
    add_loot("LabCore", "safe", 37.0, LAB2, 60.5, 180)
    add_loot("LabCore", "safe", 59.0, LAB2, 60.5, 180)
    add_loot("LabCore", "crate", 48.0, LAB2, 60.0)
    add_loot("LabCore", "crate", 48.0, LAB2, 40.5)
    boss_starts.extend([(48.0, LAB2, 47.5), (44.0, LAB2, 54.0)])

    # ---- OPERATIONS (z 68..100): the control room, the tower stairs' lobby, the server room, quarters, the power room
    wall("z", WC, 68.0, 100.0, LAB2, H, "lab", [door(72.0), door(88.0), door(96.0)])
    wall("z", WR, 68.0, 100.0, LAB2, H, "lab", [door(76.0), door(92.0)])
    wall("x", 84.0, l0, WR, LAB2, H, "lab")
    labels.append(("QUARTERS", 33, 76, 0))
    labels.append(("QUARTERS", 33, 92, 0))
    for z in (70.5, 80.5, 86.5, 97.5):       # bunks
        box(30.3, LAB2, z - 1.0, 32.6, LAB2 + 1.8, z + 1.0, "wood")
    labels.append(("CONTROL ROOM", 47, 76, 0))
    wall("z", 54.0, 68.0, 76.0, LAB2, H, "lab", [door(72.0)])
    wall("x", 84.0, WC, 54.0, LAB2, H, "lab", [door(47.0)])
    for z in (73.0, 78.5):                   # desk rows facing the wall screens
        low(42.5, z - 0.5, 46.0, z + 0.5, 1.0, "core")
        low(48.5, z - 0.5, 52.0, z + 0.5, 1.0, "core")
    for x0, x1 in ((41.0, 45.5), (48.5, 53.5)):   # the wall of screens either side of the door
        box(x0, LAB2 + 1.5, 83.6, x1, LAB2 + 3.5, 83.8, "core", solid=False)
    # the short east corridor from the ring past the power room; the stairs stand where it would carry on
    wall("z", ER, 68.0, 76.0, LAB2, H, "lab", [door(72.0)])
    wall("x", 76.0, TOWER_STAIRS[1], l1, LAB2, H, "lab")
    labels.append(("POWER", 62, 72, 0))
    box(63.0, LAB2, 69.0, 65.7, LAB2 + 2.4, 75.0, "metal")
    labels.append(("LOBBY", 47, 88, 0))
    wall("x", 92.0, WC, l1, LAB2, H, "lab", [door(47.0)])
    wall("x", 90.0, TOWER_STAIRS[1], l1, LAB2, H, "lab")
    wall("z", TOWER_STAIRS[1], 76.0, 90.0, LAB2, H, "lab")
    labels.append(("SERVER ROOM", 53, 96, 0))
    for z in (94.5, 97.5):                   # the server racks, a gap in each row
        box(43.0, LAB2, z - 0.4, 50.0, LAB2 + 2.2, z + 0.4, "core")
        box(52.5, LAB2, z - 0.4, 63.0, LAB2 + 2.2, z + 0.4, "core")
    add_loot("LabWing", "crate", 64.5, LAB2, 98.8, 180)

    # ---- upstairs (LAB1): the dock (the moon pool comes in from the north, the sub bay east, the freight ramp
    # west), and the observation room over the hall's north end
    h1 = HULL_B - SLAB_T - LAB1
    wall("x", 7.0, l0, MOON[0], LAB1, h1, "lab")      # (the moon pool trunk's own wall opens onto the dock)
    wall("x", 7.0, MOON[1], l1, LAB1, h1, "lab")
    wall("x", 27.0, l0, hx0, LAB1, h1, "lab")
    wall("x", 27.0, hx1, l1, LAB1, h1, "lab")
    wall("z", 56.0, 7.0, 27.0, LAB1, h1, "lab", [door(17.0, 2.0)])
    wall("z", 34.6, 10.0, 25.0, LAB1, 1.0, "lab")   # (a rail along the ramp's opening)
    extracts.append(("SubBay", "SUB BAY", 61.0, LAB1, 17.0, "sub_bay"))   # shut until the power's on (MapSwitch)
    box(58.0, LAB1, 22.0, 65.0, LAB1 + 2.2, 26.0, "core")      # the sub
    add_loot("LabDock", "locker", 54.0, LAB1, 26.0, 180)
    add_loot("LabDock", "locker", 38.0, LAB1, 26.0, 180)
    labels.append(("OBSERVATION", 48, 31, 0))
    wall("x", 27.0, hx0, hx1, LAB1, h1, "lab", [door(48.0, 2.4)])
    wall("z", hx0, 27.0, hz0, LAB1, h1, "lab")
    wall("z", hx1, 27.0, hz0, LAB1, h1, "lab")
    for x in (40.0, 44.0, 52.0, 56.0):       # consoles at the hall's windows
        box(x - 1.2, LAB1, hz0 - 1.3, x + 1.2, LAB1 + 1.0, hz0 - 0.5, "core")
    slab(46.0, 50.0, hz0, hz0 + 2.5, LAB1, "labfloor")           # the balcony, a ladder down into the hall
    wall("x", hz0 + 2.5, 46.0, 50.0, LAB1, 1.0, "lab", [(48.8, 1.2, 0.0, 1.0)], t=0.15)
    wall("z", 46.0, hz0, hz0 + 2.5, LAB1, 1.0, "lab", t=0.15)
    wall("z", 50.0, hz0, hz0 + 2.5, LAB1, 1.0, "lab", t=0.15)
    ladder(48.8, LAB2, hz0 + 2.6, 0, LAB1 - LAB2, "Catwalk")


# ---------------------------------------------------------------------------------------------- AI
# Zones (name, x, y, z, radius, scavs, raiders, trickle): few on the shore, more on the ship, the bosses below.
# (0.35.34, owner: three bosses. Fore and Aft are Ace's and Orbit's patrols in the lower hull, the pump room end and the
# engine room end; nothing else starts there. The hold keeps 2 scavs, was 4, as the bosses' crews moved in.)
AI_ZONES = [("Landing", -105.0, SHORE, 0.0, 100.0, 5, 0, 0.8), ("Deck", 48.0, DECK, -30.0, 70.0, 4, 0, 1.0),
            ("Tower", 48.0, DECK2, 90.0, 26.0, 0, 2, 1.0), ("Hold", 48.0, HULL_A, 0.0, 80.0, 2, 0, 1.0),
            ("Lab", 48.0, LAB2, 30.0, 70.0, 0, 2, 1.5),
            ("Fore", 48.0, (HULL_A + HULL_B) / 2, -60.0, 40.0, 0, 0, 0.0),
            ("Aft", 48.0, (HULL_A + HULL_B) / 2, 62.0, 40.0, 0, 0, 0.0)]
# How far up and down a zone's area reaches (the ship's decks are stacked): the lab's two decks; the hold and the
# engine/pump deck. Zones not listed reach any height.
ZONE_HEIGHT = {"Lab": 7.0, "Fore": 4.0, "Aft": 4.0}
AI_ROAMERS = 2
AI_SNIPERS = 1
# (0.35.34, owner: "3 bosses ... each have 2 kinda somewhat non threatening guards"; all tougher than Bon, Raijin the
# toughest): (zone, boss scene). Every raid. Their guards: scenes/guard_riptide.tscn.
AI_BOSSES = [("Lab", "res://scenes/boss_raijin.tscn"), ("Fore", "res://scenes/boss_ace.tscn"),
             ("Aft", "res://scenes/boss_orbit.tscn")]
AI_GUARDS = 2
# (0.35.34, owner: Riptide's own scavs and Raiders, "different skins/names") Deckhands and Exion Troopers.
AI_LOOKS = {"scav": "res://scenes/deckhand.tscn", "raider": "res://scenes/trooper.tscn"}
ZONE_SPOTS = {
    "Landing": [(-115.0, SHORE, -127.0), (-100.0, SHORE, -99.0), (-134.0, SHORE, -85.0), (-70.0, SHORE, -40.0),
                (-110.0, SHORE, 0.0), (-62.0, SHORE, 0.0), (-80.0, SHORE, 104.0), (-112.0, SHORE, 104.0),
                (-74.0, SHORE, 130.0), (-51.0, SHORE, 84.0)],
    "Deck": [(40.0, DECK, -58.0), (56.0, DECK, -40.0), (36.0, DECK, -6.0), (60.0, DECK, 6.0), (44.0, DECK, 52.0),
             (54.0, DECK, 71.0), (48.0, FORECASTLE, -98.0), (48.0, DRILL, -10.0)],
    "Tower": [(38.0, DECK2, 80.0), (50.0, DECK2, 100.0), (38.0, DECK3, 98.0), (48.0, DECK4, 84.0), (40.0, DECK, 100.0)],
    "Hold": [(48.0, HULL_A, -60.0), (33.0, HULL_A, -30.0), (63.0, HULL_A, 10.0), (48.0, HULL_A, 40.0),
             (40.0, HULL_B, 50.0), (56.0, HULL_B, -80.0), (48.0, HULL_B, -20.0), (40.0, HULL_A, 86.0)],
    "Fore": [(44.0, HULL_B, -70.0), (40.0, HULL_A, -72.0), (56.0, HULL_B, -64.0)],
    "Aft": [(48.0, HULL_B, 70.0), (40.0, HULL_A, 90.0), (60.0, HULL_B, 72.0)],
    "Lab": [(48.0, LAB1, 15.0), (47.0, LAB2, -26.5), (54.0, LAB2, 5.0), (33.0, LAB2, 50.0), (63.0, LAB2, 50.0),
            (47.0, LAB2, 81.0), (48.0, LAB2, 65.0)],
}
ROAMER_SPOTS = [(-12.0, PIER, 1.0), (-14.0, SHORE, -121.0), (5.0, BARGE, 117.5)]


def ai():
    for name, *_ in AI_ZONES:
        for x, y, z in ZONE_SPOTS[name]:
            enemy_spawns.append((x, y, z, name))
    for x, y, z in ROAMER_SPOTS:
        enemy_spawns.append((x, y, z, ""))


def spawner_meta():
    zones = ", ".join(f'{{"name": "{n}", "center": Vector3({fmt(x)}, {fmt(y)}, {fmt(z)}), "radius": {fmt(r)}, '
                      + (f'"height": {fmt(ZONE_HEIGHT[n])}, ' if n in ZONE_HEIGHT else "")
                      + f'"scavs": {s}, "raiders": {rd}, "trickle": {fmt(t)}}}' for n, x, y, z, r, s, rd, t in AI_ZONES)
    scavs = sum(z[5] for z in AI_ZONES) + AI_ROAMERS
    raiders = sum(z[6] for z in AI_ZONES)
    bosses = ", ".join(f'{{"zone": "{zone}", "guards": {AI_GUARDS}, "chance": 1.0, "scene": "{scene}", '
                       f'"guard_scene": "res://scenes/guard_riptide.tscn"}}' for zone, scene in AI_BOSSES)
    looks = ", ".join(f'"{k}": "{v}"' for k, v in AI_LOOKS.items())
    crews = len(AI_BOSSES) * (1 + AI_GUARDS)
    return (f'metadata/spawner = {{"zones": [{zones}], "roamers": {AI_ROAMERS}, "snipers": {AI_SNIPERS}, "initial_count": 0, '
            f'"bosses": [{bosses}], "looks": {{{looks}}}, '
            f'"max_alive": {25 + crews}, "scav_budget": {scavs + 4}, "raider_budget": {raiders + 3}, '
            '"scav_interval_min": 60.0, "scav_interval_max": 80.0, '
            '"raider_times": PackedFloat32Array(240, 480, 660), "min_distance_from_player": 40.0}')


# (0.35.17, owner: "when you open the map and look at all the names on the map its super cluttered") The map screen
# shows only these, the places you'd call out; the other 30-odd names (rooms, decks stacked on top of each other on
# the ship) stay in the generator as notes. name -> None (where the generator put it) or (text, x, z) to move or rename.
MAP_LABELS = {
    "THE LANDING": None, "LEVIATHAN": ("LEVIATHAN", 48, 34), "LIGHTHOUSE": None, "CANNERY": None,
    "CONTAINER TERMINAL": None, "HARBOR TOWER": None, "CUSTOMS": None, "SILOS": None,
    "SLIPWAY": ("SHIPYARD", -108, 124), "PIER": None, "BREAKWATER": None, "BARGE LINE": None,
    "FORECASTLE": ("BOW", 48, -96), "DRILL FLOOR": ("DRILL FLOOR", 48, -2), "BRIDGE TOWER": ("BRIDGE TOWER", 48, 78),
    "SITE ZERO (BELOW)": ("SITE ZERO", 48, -50),
}


def map_labels():
    out = []
    for text, x, z, big in labels:
        if text in MAP_LABELS:
            out.append((text, x, z, big) if MAP_LABELS[text] is None else (*MAP_LABELS[text], big))
    assert len(out) == len(MAP_LABELS), "a name in MAP_LABELS isn't in the map any more"
    return out


def minimap_meta():
    """The in-raid map (M): map metres from the top-left corner (x + 180, z + 180)."""
    def floats(values):
        return "PackedFloat32Array(" + ", ".join(fmt(v) for v in values) + ")"
    bld = [v for x0, z0, x1, z1 in footprints for v in (x0 + HALF, z0 + HALF, x1 + HALF, z1 + HALF)]
    text = ", ".join(f'["{t}", {fmt(x + HALF)}, {fmt(z + HALF)}, {big}]' for t, x, z, big in map_labels())
    sea_w = HALF - QUAY
    yards = [QUAY + HALF, -2 + HALF, SX0 + HALF, 7.2 + HALF]   # the pier
    return ("metadata/minimap = {" + f'"size": {fmt(M)}, "offset": {fmt(-HALF)}, '
            + f'"buildings": {floats(bld)}, "yards": {floats(yards)}, "woods": PackedFloat32Array(), '
            + f'"roads": [PackedVector2Array(0, 180, 104, 180)], "road_widths": PackedFloat32Array(8), '
            + f'"seas": PackedFloat32Array({fmt(QUAY + HALF)}, 0, {fmt(M)}, {fmt(M)}), '
            + f'"labels": [{text}]' + "}")


# ---------------------------------------------------------------------------------------------- the scene
def terrain():
    """The ground: the flat port to the quay, then down to the sea bed. One row of heights across x, the same all along z."""
    # (0.33.7: one row of cells across z, with no seam down the middle of the port: the seam at z 0 drew as a
    # flickering saw-toothed stripe from the gate to the pier)
    xs = [-HALF, -30.0, -29.0, 0.0, HALF]
    hs = [SHORE, SHORE, -8.0, SEABED, SEABED]
    zs = [-HALF, HALF]
    return xs, zs, [h for _ in zs for h in hs]


def xform(x, y, z, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return f"Transform3D({fmt(c)}, 0, {fmt(s)}, 0, 1, 0, {fmt(-s)}, 0, {fmt(c)}, {fmt(x)}, {fmt(y)}, {fmt(z)})"


def sea_planes():
    """The sea's surface (y 0) round the ship, so it isn't drawn inside the hull: four flat pieces."""
    pieces = [(QUAY, -HALF, HALF, SZ0 - 0.3), (QUAY, SZ1 + 0.3, HALF, HALF),
              (QUAY, SZ0 - 0.3, SX0 - 0.3, SZ1 + 0.3), (SX1 + 0.3, SZ0 - 0.3, HALF, SZ1 + 0.3)]
    out = []
    for i, (x0, z0, x1, z1) in enumerate(pieces):
        # the water you swim in under this piece (0.33.6): down to the sea bed
        out += [f'[node name="Swim{i}" type="Area3D" parent="Level"]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt((x0 + x1) / 2)}, 0, {fmt((z0 + z1) / 2)})",
                'script = ExtResource("10_swim")', f"size = Vector3({fmt(x1 - x0)}, {fmt(-SEABED + 1.0)}, {fmt(z1 - z0)})", ""]
        out += [f'[node name="Sea{i}" type="MeshInstance3D" parent="Level"]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt((x0 + x1) / 2)}, 0, {fmt((z0 + z1) / 2)})",
                f'mesh = SubResource("sea_{i}")', 'material_override = SubResource("sea_mat")', "cast_shadow = 0", ""]
    # (0.36.17) the corners round the shaped bow and stern: water you swim in (strips, the sides of a swim box can't
    # slant) and the sea's surface (SeaFill: flat polygons up to the hull's plate)
    polys = []
    for line, zend in ((BOW_LINE, SZ0 - 0.3), (STERN_LINE, SZ1 + 0.3)):
        for side in (-1, 1):
            edge = 48.0 + side * 18.3          # (the side pieces' inner edge)
            pts = [(edge, line[0][1])] + [(48.0 + side * (h + 0.15), z) for h, z in line]
            pts += [(48.0 + side * (line[-1][0] + 0.15), zend), (edge, zend)]
            polys.append(pts)
            strips = [(za, zb, max(hull_half(za), hull_half(zb)))
                      for za, zb, _ in hull_strips(min(line[0][1], line[-1][1]), max(line[0][1], line[-1][1]), 0.6)]
            strips.append((min(zend, line[-1][1]), max(zend, line[-1][1]), line[-1][0]))   # (out to the end pieces)
            for za, zb, wide in strips:
                wide += 0.3
                x0, x1 = sorted((edge, 48.0 + side * wide))
                if x1 - x0 > 0.05:
                    i = len(out)
                    out += [f'[node name="SwimC{i}" type="Area3D" parent="Level"]',
                            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt((x0 + x1) / 2)}, 0, {fmt((za + zb) / 2)})",
                            'script = ExtResource("10_swim")',
                            f"size = Vector3({fmt(x1 - x0)}, {fmt(-SEABED + 1.0)}, {fmt(zb - za)})", ""]
    out += ['[node name="SeaFill" type="MeshInstance3D" parent="Level"]', 'script = ExtResource("11_seafill")',
            "polygons = Array[PackedVector2Array]([" + ", ".join(
                "PackedVector2Array(" + ", ".join(f"{fmt(x)}, {fmt(z)}" for x, z in pts) + ")" for pts in polys) + "])",
            'material_override = SubResource("sea_mat")', "cast_shadow = 0", ""]
    subs = ['[sub_resource type="StandardMaterial3D" id="sea_mat"]', "transparency = 1",
            "albedo_color = Color(0.13, 0.27, 0.35, 0.86)", "roughness = 0.15", "metallic_specular = 0.6", ""]
    for i, (x0, z0, x1, z1) in enumerate(pieces):
        subs += [f'[sub_resource type="PlaneMesh" id="sea_{i}"]', f"size = Vector2({fmt(x1 - x0)}, {fmt(z1 - z0)})", ""]
    return subs, out


def write_scene():
    xs, zs, hs = terrain()
    subs, sea = sea_planes()
    scenes = {"crate": "res://scenes/loot_crate.tscn", "locker": "res://scenes/loot_locker.tscn",
              "safe": "res://scenes/loot_safe.tscn", "ladder": "res://scenes/ladder.tscn"}
    out = ["[gd_scene format=3]", "",
           '[ext_resource type="Script" path="res://scripts/box_map.gd" id="1_boxmap"]',
           '[ext_resource type="PackedScene" path="res://scenes/extract_zone.tscn" id="2_extract"]',
           '[ext_resource type="Script" path="res://scripts/map_switch.gd" id="9_switch"]',
           '[ext_resource type="Script" path="res://scripts/swim_zone.gd" id="10_swim"]',
           '[ext_resource type="Script" path="res://scripts/sea_fill.gd" id="11_seafill"]']
    ids = {}
    for n, (kind, path) in enumerate(scenes.items(), start=3):
        ids[kind] = f"{n}_{kind}"
        out.append(f'[ext_resource type="PackedScene" path="{path}" id="{ids[kind]}"]')
    shown = [m for m in models if m["hide"]]
    if shown:
        out.append('[ext_resource type="Script" path="res://scripts/pixel_model.gd" id="m_pixel"]')
    for m in shown:
        out.append(f'[ext_resource type="PackedScene" path="res://assets/models/buildings/{m["name"]}.glb" id="m_{m["name"]}"]')
    out += [""] + subs
    out += ["; Generated by tools/gen_riptide.py: edit that script and re-run it, don't edit this file.", "",
            '[node name="Riptide" type="Node3D"]',
            'metadata/map_name = "Riptide"',
            spawner_meta(),
            'metadata/raid = {"raid_time": 900.0}',
            f"metadata/kill_height = {fmt(SEABED - 16.0)}",   # (0.35.16: well under the lab and the sea bed)
            'metadata/look = "res://assets/looks/storm.tres"',
            'metadata/rain = true',
            'metadata/no_breath = true',   # (0.35.26, owner: no out-of-breath "woosh" on Riptide)
            minimap_meta(),
            "",
            '[node name="Level" type="Node3D" parent="."]', "",
            '[node name="Blocks" type="StaticBody3D" parent="Level"]',
            'script = ExtResource("1_boxmap")',
            "colors = PackedColorArray(" + ", ".join(f"{fmt(r)}, {fmt(g)}, {fmt(b)}, 1" for _, (r, g, b) in COLOURS) + ")",
            "boxes = PackedFloat32Array(" + ", ".join(fmt(v) for b in boxes for v in b) + ")",
            "colour_names = PackedStringArray(" + ", ".join(f'"{name}"' for name, _ in COLOURS) + ")",
            f"terrain_colour = {C['sand']}",
            "terrain_xs = PackedFloat32Array(" + ", ".join(fmt(x) for x in xs) + ")",
            "terrain_zs = PackedFloat32Array(" + ", ".join(fmt(z) for z in zs) + ")",
            "terrain_heights = PackedFloat32Array(" + ", ".join(fmt(h) for h in hs) + ")",
            f"water_colour = {C['water']}",
            ""] + sea
    for name, sid, text, x, y, z in switches:
        out += [f'[node name="{name}" type="StaticBody3D" parent="Level"]', f"transform = {xform(x, y, z)}",
                'script = ExtResource("9_switch")', f'switch_id = "{sid}"', f'prompt_text = "{text}"', ""]
    if shown:
        out += ['[node name="Models" type="Node3D" parent="Level"]', ""]
    for m in shown:
        out += [f'[node name="{m["name"]}" parent="Level/Models" instance=ExtResource("m_{m["name"]}")]',
                f"transform = {xform(m['x'], 0.0, m['z'])}", 'script = ExtResource("m_pixel")', ""]
    out += ['[node name="Ladders" type="Node3D" parent="Level"]', ""]
    for i, (x, y, z, yaw, height, place) in enumerate(ladders):
        out += [f'[node name="Ladder{i + 1}" parent="Level/Ladders" instance=ExtResource("{ids["ladder"]}")]',
                f"transform = {xform(x, y, z, yaw)}", f"height = {fmt(height)}", f'metadata/place = "{place}"', ""]
    out += ['[node name="Loot" type="Node3D" parent="."]', ""]
    for name, kind, x, y, z, yaw, table, place in loot:
        out += [f'[node name="{name}" parent="Loot" instance=ExtResource("{ids[kind]}")]',
                f"transform = {xform(x, y, z, yaw)}", f'metadata/place = "{place}"']
        out += ([f'loot_table = "{table}"'] if table != kind else []) + [""]
    out += ['[node name="Extracts" type="Node3D" parent="."]', ""]
    for name, title, x, y, z, *power in extracts:
        out += [f'[node name="{name}" parent="Extracts" instance=ExtResource("2_extract")]',
                f"transform = {xform(x, y, z)}", f'extract_name = "{title}"']
        out += ([f'needs_power = "{power[0]}"'] if power else []) + [""]
    out += ['[node name="PlayerSpawns" type="Node3D" parent="."]', ""]
    for i, (x, y, z) in enumerate(player_spawns):
        out += [f'[node name="Spawn{i + 1}" type="Marker3D" parent="PlayerSpawns"]', f"transform = {xform(x, y + 0.1, z)}", ""]
    out += ['[node name="EnemySpawns" type="Node3D" parent="."]', ""]
    for i, (x, y, z, zone) in enumerate(enemy_spawns):
        out += [f'[node name="EnemySpawn{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.1, z)}"]
        out += ([f'metadata/zone = "{zone}"'] if zone else []) + [""]
    for i, (x, y, z) in enumerate(boss_starts):
        out += [f'[node name="BossStart{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.1, z)}",
                "metadata/boss_start = true", 'metadata/boss_zone = "Lab"', ""]
    for i, (x, y, z, fx, fz) in enumerate(perches):
        out += [f'[node name="Perch{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.3, z)}",
                "metadata/perch = true", f"metadata/face = Vector3({fx}, 0, {fz})", ""]
    with open(OUT, "w") as f:
        f.write("\n".join(out))


def main():
    quay()
    north_point()
    terminal()
    plaza()
    grain()
    shipyard()
    transit_sheds()
    breakers()
    crossings()
    ship()
    moon_pool()
    with modeled("leviathan_hull", 48.0, 0.0):
        drill_floor()
    bow_stairs()
    tower()
    lab()
    ai()
    write_model_boxes()
    write_scene()
    print(f"riptide: {len(boxes)} boxes, {len(loot)} loot, {len(ladders)} ladders, {len(extracts)} extracts, "
          f"{len(player_spawns)} player spawns, {len(enemy_spawns)} enemy spawns -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
