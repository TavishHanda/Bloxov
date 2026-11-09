#!/usr/bin/env python3
"""Riptide (map 2) gray box: writes scenes/maps/riptide.tscn. Edit this script and re-run it, never the scene.

The plan (Tavish, 2026-11-09): the Leviathan, a research ship anchored in a bay, with Site Zero (the lab) on the
sea floor under it and the boss Zero in its core. Shore (The Landing) on the west, four ways across (pier with a
covered pipe gallery, the breakwater to the bow, the barge line to the stern, sea-side ladders from the boats),
several ways between floors (bow stairs, moon pool lift + stairs, tower stairs, outside ladder, hold hatches,
side-passage ladders, the service tube), three ways into the lab and three into the core.

Coordinates are Godot metres with the origin in the middle of the map: x east (out to sea), z south, y up.
The sea's surface is y = 0. Everything is plain boxes (BoxMap); the art comes later, piece by piece.
"""
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
HULL_A = -4.0        # the cargo hold
HULL_B = -8.0        # the engine room and pump room (the hull's bottom)
LAB1 = -22.0         # the dock
LAB2 = -28.0         # the ring, the wings and the core
SEABED = -29.0

# The ship: x 30..66 (36 m wide), z -104 (bow, north) .. 110 (stern, south)
SX0, SX1, SZ0, SZ1 = 30.0, 66.0, -104.0, 110.0
# The bridge tower (superstructure) on the stern end
TX0, TX1, TZ0, TZ1 = 34.0, 62.0, 74.0, 106.0

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
labels = []          # (text, x, z, big)
footprints = []      # (x0, z0, x1, z1)


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------------------------------------------------------------------------------------------- pieces
def box(x0, y0, z0, x1, y1, z1, colour, solid=True):
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    z0, z1 = min(z0, z1), max(z0, z1)
    if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01:
        return
    boxes.append(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, 0.0, 0.0, C[colour], 1 if solid else 0))


def obox(cx, cy, cz, sx, sy, sz, yaw, colour, pitch=0.0, solid=True):
    boxes.append((cx, cy, cz, sx, sy, sz, yaw, pitch, C[colour], 1 if solid else 0))


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
    boxes.append((cx, cy, cz, width, t, length, yaw, pitch, C[colour], 1))


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
def shore():
    # The sea wall along the whole shore (cover from the ship), with gaps where the ways across start.
    gaps = [(-128, 6.5), (2.6, 10.0), (63, 6.0), (121, 7.0), (-60, 4.0)]
    wall("z", -95.0, -HALF, HALF, SHORE, 1.0, "concrete", [(c, w, 0.0, 1.0) for c, w in gaps], t=0.6)
    labels.append(("THE LANDING", -140, 0, 1))
    wall("z", -HALF + 0.5, -HALF, HALF, SHORE, 3.0, "concrete", t=0.6)   # the map's inland edge
    for z in (-HALF + 0.5, HALF - 0.5):
        wall("x", z, -HALF, -92.0, SHORE, 3.0, "concrete", t=0.6)

    # North point: rocks, the lighthouse (one way up: a perch), the cove extract
    for x, z, sx, sz, h, yaw in [(-112, -150, 8, 6, 3.0, 20), (-104, -170, 10, 7, 2.2, -15), (-125, -120, 6, 5, 2.0, 40),
                                 (-140, -165, 7, 9, 3.5, 10), (-118, -138, 5, 4, 1.6, 0), (-165, -120, 9, 6, 2.8, 30),
                                 (-100, -142, 4, 6, 1.5, 15)]:
        obox(x, SHORE + h / 2 - 0.3, z, sx, h + 0.6, sz, yaw, "rock")
    lx, lz = -150.0, -148.0
    room(lx - 3, lx + 3, lz - 3, lz + 3, SHORE, 14.0, "wall", s=[door(lx)])
    slab(lx - 3, lx + 3, lz - 3, lz + 3, SHORE + 14.0, "concrete", holes=[(lx - 2.7, lx - 1.5, lz + 1.4, lz + 2.85)])
    for side in ("N", "S", "W", "E"):   # parapet on the top
        if side in "NS":
            wall("x", lz - 3 if side == "N" else lz + 3, lx - 3, lx + 3, SHORE + 14.0, 1.1, "wall")
        else:
            wall("z", lx - 3 if side == "W" else lx + 3, lz - 3, lz + 3, SHORE + 14.0, 1.1, "wall")
    ladder(lx - 2.1, SHORE, lz + 2.65, 180, 14.0, "Lighthouse")
    perches.append((lx, SHORE + 14.0, lz, 1, 0))
    labels.append(("LIGHTHOUSE", lx, lz - 8, 0))
    extracts.append(("Cove", "COVE", -108.0, SHORE, -166.0))
    player_spawns.append((-158.0, SHORE, -128.0))

    # The harbor: the old supply office (two floors), the container yard, fuel tanks, a shore crane, the road out
    ox0, ox1, oz0, oz1 = -142.0, -122.0, -32.0, -14.0
    room(ox0, ox1, oz0, oz1, SHORE, 3.5, "wall", e=[door(-27), window(-19)], w=[door(-23)], n=[window(-136), window(-128)],
         s=[window(-136), window(-128)], floor="concrete")
    slab(ox0, ox1, oz0, oz1, SHORE + 3.5, "concrete", holes=[(ox0 + 0.3, ox0 + 2.6, oz0 + 0.3, oz0 + 9.0)])
    ramp((ox0 + 1.45, SHORE, oz0 + 13.0), (ox0 + 1.45, SHORE + 3.5, oz0 + 2.5), 2.2, "concrete")
    room(ox0, ox1, oz0, oz1, SHORE + 3.5, 3.2, "wall", e=[window(-27), window(-19)], n=[window(-130)], s=[window(-130)],
         roof="roof")
    wall("x", -24.0, ox0 + 3.0, ox1, SHORE, 3.5, "wall", [door(-130)])
    footprints.append((ox0, oz0, ox1, oz1))
    labels.append(("SUPPLY OFFICE", (ox0 + ox1) / 2, oz0 - 4, 0))
    add_loot("Offices", "crate", -128, SHORE, -29)
    add_loot("Offices", "locker", -138, SHORE + 3.5, -17, 180)
    add_loot("Offices", "crate", -125, SHORE + 3.5, -29)
    yard = [(-132, 14, "x", "container_a", 2), (-124, 14, "x", "container_b", 1), (-110, 18, "z", "container_c", 2),
            (-132, 26, "x", "container_b", 1), (-118, 30, "z", "container_a", 1), (-106, 34, "x", "container_c", 2),
            (-128, 40, "x", "container_a", 1), (-114, 44, "z", "container_b", 2)]
    for x, z, along, col, high in yard:
        container(x, SHORE, z, along, col, high)
    add_loot("Shore", "crate", -121, SHORE, 21, table="field")
    add_loot("Shore", "crate", -112, SHORE, 39, table="field")
    for z in (30.0, 42.0):
        obox(-165, SHORE + 3.0, z, 7.0, 6.0, 7.0, 45, "rust")
    box(-101, SHORE, -21, -99, SHORE + 14, -19, "rust")          # the shore crane
    obox(-96, SHORE + 13.5, -20, 2, 1.2, 14, 90, "rust")
    box(-HALF, SHORE - 0.2, -4.0, -118, SHORE + 0.02, 2.0, "road", solid=False)
    extracts.append(("RoadOut", "ROAD OUT", -172.0, SHORE, -1.0))
    labels.append(("HARBOR", -150, 6, 0))
    player_spawns.append((-168.0, SHORE, -36.0))
    player_spawns.append((-150.0, SHORE, 58.0))

    # The south beach: dunes, beached boats, fishing shacks, the boathouse
    for x, z, sx, sz, h, yaw in [(-150, 80, 14, 5, 1.2, 10), (-130, 95, 12, 4, 1.0, -20), (-160, 130, 16, 5, 1.3, 5),
                                 (-125, 150, 10, 4, 1.1, 30), (-145, 170, 12, 5, 1.0, -10)]:
        obox(x, SHORE + h / 2 - 0.2, z, sx, h + 0.4, sz, yaw, "sand")
    for x, z, yaw in [(-108, 90, 70), (-116, 104, 120), (-102, 160, 95)]:
        obox(x, SHORE + 0.6, z, 2.4, 1.4, 6.0, yaw, "wood")
    for i, (x, z) in enumerate([(-140, 112), (-165, 150)]):
        room(x - 2.5, x + 2.5, z - 2.5, z + 2.5, SHORE, 2.6, "wood", e=[door(z)], n=[window(x)], roof="roof")
        add_loot("Shore", "crate", x - 1.2, SHORE, z - 1.2, table="field")
        footprints.append((x - 2.5, z - 2.5, x + 2.5, z + 2.5))
    bx0, bx1, bz0, bz1 = -112.0, -98.0, 134.0, 146.0
    room(bx0, bx1, bz0, bz1, SHORE, 4.0, "wood", w=[door(140, 2.4)], e=[(140, 5.0, 0.0, 3.4)], n=[window(-105)],
         roof="roof", floor="wood")
    add_loot("Boathouse", "crate", bx0 + 1.5, SHORE, bz0 + 1.5)
    footprints.append((bx0, bz0, bx1, bz1))
    labels.append(("BOATHOUSE", -105, 152, 0))
    extracts.append(("Boathouse", "BOATHOUSE", -103.0, SHORE, 140.0))
    labels.append(("SOUTH BEACH", -140, 125, 0))
    player_spawns.append((-162.0, SHORE, 104.0))
    player_spawns.append((-128.0, SHORE, 168.0))


# ---------------------------------------------------------------------------------------------- the ways across
def crossings():
    # The pier (middle): open deck z -2..4, the roofed pipe gallery z 4.4..7.2 beside it
    px0, px1 = -86.0, SX0
    box(px0, PIER - 0.4, -2.0, px1, PIER, 7.2, "wood")
    ramp((-92.0, SHORE, 1.0), (px0, PIER, 1.0), 6.0, "wood")
    for x in range(-84, 30, 12):     # legs down to the sea bed
        box(x - 0.4, SEABED + 2, -2.0, x + 0.4, PIER - 0.4, -1.2, "rust")
        box(x - 0.4, SEABED + 2, 6.4, x + 0.4, PIER - 0.4, 7.2, "rust")
    wall("x", 4.4, -84.0, px1, PIER, 2.6, "rust", [(c, 1.6, 0.0, 2.2) for c in (-80, -55, -30, -5, 18)], t=0.2)
    wall("x", 7.2, -84.0, px1, PIER, 2.6, "rust", t=0.2)
    wall("z", -84.0, 4.4, 7.2, PIER, 2.6, "rust", [(5.8, 1.6, 0.0, 2.2)], t=0.2)
    box(-84.0, PIER + 2.6, 4.3, px1, PIER + 2.8, 7.3, "roof")
    for x, z in [(-62, 0.5), (-34, -0.5), (-8, 1.0), (14, 0.0)]:
        container(x, PIER, z, "x", "container_b" if x % 3 else "container_a")
    labels.append(("PIER", -40, -6, 0))
    # the gangway from the pier up to the main deck, through a gap in the rail
    ramp((20.0, PIER, 0.0), (SX0, DECK, 0.0), 3.5, "metal")
    box(14.0, PIER - 0.4, -2.0, 20.0, PIER, 2.0, "wood")

    # The breakwater (north): a rock jetty from the north point to the bow, rocks along it for cover
    a, b = (-86.0, -128.0), (40.0, -112.0)
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    yaw = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))
    obox((a[0] + b[0]) / 2, (PIER + SEABED) / 2, (a[1] + b[1]) / 2, 7.0, PIER - SEABED, length, yaw, "rock")
    ramp((-92.0, SHORE, -128.0), (-86.0, PIER, -128.0), 6.0, "rock")
    for f, side, s in [(0.15, 1, 2.0), (0.3, -1, 1.6), (0.45, 1, 1.8), (0.6, -1, 2.2), (0.75, 1, 1.5), (0.88, -1, 1.9)]:
        x, z = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
        nx, nz = math.cos(math.radians(yaw)), -math.sin(math.radians(yaw))
        obox(x + nx * side * 2.0, PIER + s / 2 - 0.2, z + nz * side * 2.0, 2.6, s + 0.4, 3.2, yaw + 25 * side, "rock")
    box(36.0, SEABED, -120.0, 60.0, PIER, SZ0 - 0.3, "rock")        # the pad under the bow
    labels.append(("BREAKWATER", -30, -126, 0))
    ladder(48.0, PIER, SZ0 - 0.4, 180, FORECASTLE - PIER, "Bow")
    extracts.append(("BowBoat", "BOW PILOT BOAT", 41.0, PIER, -116.0))
    box(36.0, BOAT - 0.8, -126.0, 44.0, BOAT, -121.0, "wood")      # the pilot boat moored at the pad

    # The barge line (south): barges tied end to end from the beach to the stern ramp
    barges = [(-86, -68), (-62, -44), (-38, -20), (-14, 4), (10, 28), (34, 54)]
    for i, (x0, x1) in enumerate(barges):
        z0, z1 = (112.0, 126.0) if i == len(barges) - 1 else (116.0, 126.0)
        box(x0, BARGE - 2.0, z0, x1, BARGE, z1, "rust")
        box(x0 + 2, BARGE, z1 - 4.5, x0 + 6.5, BARGE + 2.4, z1 - 0.8, "wall")   # a deck cabin (cover)
        if i < len(barges) - 1:
            box(x1, BARGE - 0.3, 119.5, barges[i + 1][0], BARGE, 122.5, "wood")   # the plank to the next one
        if i in (1, 3):
            container((x0 + x1) / 2 + 2, BARGE, 119.0, "x", "container_c")
    ramp((-92.0, SHORE, 121.0), (-86.0, BARGE, 121.0), 3.0, "wood")
    labels.append(("BARGE LINE", -30, 133, 0))
    player_spawns.append((-28.0, BARGE, 122.0))
    add_loot("Barges", "crate", -9.0, BARGE, 124.5, table="field")

    # The sea side (east): two boats moored against the hull, ladders up to the deck
    box(SX1 + 0.4, BOAT - 1.5, -96.0, SX1 + 9.0, BOAT, -80.0, "wood")
    box(SX1 + 0.4, BOAT - 1.5, 40.0, SX1 + 11.0, BOAT, 60.0, "rust")
    box(SX1 + 5.0, BOAT, 52.0, SX1 + 9.5, BOAT + 2.6, 58.0, "wall")    # the tug's wheelhouse
    ladder(SX1 + 0.4, BOAT, -88.0, 90, DECK - BOAT, "SeaSide")
    ladder(SX1 + 0.4, BOAT, 50.0, 90, DECK - BOAT, "SeaSide")
    player_spawns.append((SX1 + 5.0, BOAT, -92.0))
    player_spawns.append((SX1 + 7.0, BOAT, 44.0))
    labels.append(("TUG", SX1 + 10, 50, 0))

    # The stern ladder down to a dinghy (an extract)
    box(57.0, 0.2, SZ1 + 0.4, 63.0, 0.8, SZ1 + 6.0, "wood")
    ladder(60.0, 0.8, SZ1 + 0.4, 0, DECK - 0.8, "Stern")
    extracts.append(("SternLadder", "STERN LADDER", 60.0, 0.8, SZ1 + 3.5))


# ---------------------------------------------------------------------------------------------- the ship
# Openings in the decks
LIFT = (38.0, 46.0, -7.0, 7.0)        # the moon pool lift shaft (placeholder ladder until the lift is built)
MOON_STAIRS = (46.0, 54.0, -7.0, 7.0)
BOW_STAIRS = (44.0, 52.0, -88.0, -74.0)
TOWER_STAIRS = (54.0, 62.0, 76.0, 90.0)
HATCHES = [(42.0, 54.0, -50.0, -44.0), (42.0, 54.0, 24.0, 30.0)]
SIDE_LADDERS = [(SX0 + 0.35, -60.0, 90), (SX0 + 0.35, 50.0, 90), (SX1 - 0.35, -60.0, -90), (SX1 - 0.35, 50.0, -90)]
SERVICE_TUBE = (46.0, 48.4, -65.4, -63.0)


def hole(r, pad=0.0):
    return (r[0] - pad, r[1] + pad, r[2] - pad, r[3] + pad)


def ship():
    footprints.append((SX0, SZ0, SX1, SZ1))
    labels.append(("LEVIATHAN", 48, 30, 1))
    # The hull's sides and ends, from the bottom to the rail above the main deck
    bottom = HULL_B - SLAB_T
    top = DECK + BULWARK
    h = top - bottom
    gang = (0.0, 4.0, DECK - bottom, top - bottom)              # the gangway's gap in the rail
    hull_door = (5.8, 2.0, PIER - bottom, PIER - bottom + DOOR_H)  # from the pipe gallery into the hold's west passage
    wall("z", SX0, SZ0, SZ1, bottom, h, "hull", [gang, hull_door], t=0.5)
    sea_gaps = [(z, 1.4, DECK - bottom, top - bottom) for z in (-88.0, 50.0)]
    wall("z", SX1, SZ0, SZ1, bottom, h, "hull", sea_gaps, t=0.5)
    stern_ramp = (48.0, 8.0, HULL_A - bottom, DECK - 0.5 - bottom)
    stern_gap = (60.0, 1.4, DECK - bottom, top - bottom)
    wall("x", SZ1, SX0, SX1, bottom, h, "hull", [stern_ramp, stern_gap], t=0.5)
    # the bow: higher, round the forecastle
    wall("x", SZ0, SX0, SX1, bottom, FORECASTLE + BULWARK - bottom, "hull",
         [(48.0, 1.4, FORECASTLE - bottom, FORECASTLE + BULWARK - bottom)], t=0.5)
    for x in (SX0, SX1):
        wall("z", x, SZ0, -90.0, DECK + BULWARK, FORECASTLE - DECK, "hull", t=0.5)

    # Hull B (the bottom): pump room forward, the bilge, the engine room aft
    slab(SX0, SX1, SZ0, SZ1, HULL_B, "metal", holes=[hole(LIFT), hole(MOON_STAIRS), hole(BOW_STAIRS), hole(TOWER_STAIRS),
                                                      hole(SERVICE_TUBE)])
    for z in (-56.0, 30.0):
        wall("x", z, SX0, SX1, HULL_B, HULL_A - SLAB_T - HULL_B, "metal", [door(36.0, 2.0), door(58.0, 2.0)])
    labels.append(("PUMP ROOM", 48, -80, 0))
    labels.append(("ENGINE ROOM", 48, 70, 0))
    for z in (44.0, 62.0, 80.0):        # the engines (cover)
        box(38.0, HULL_B, z - 3, 44.0, HULL_B + 2.4, z + 3, "rust")
        box(52.0, HULL_B, z - 3, 58.0, HULL_B + 2.4, z + 3, "rust")
    box(62.0, HULL_B, 96.0, 65.5, HULL_B + 2.0, 100.0, "metal")   # the sub bay's power switch cabinet
    add_loot("EngineRoom", "crate", 47.0, HULL_B, 95.0, table="crate")
    add_loot("EngineRoom", "locker", 65.2, HULL_B, 90.0, -90)
    add_loot("PumpRoom", "crate", 36.0, HULL_B, -96.0)
    for z in (-40.0, -20.0, 0.0, 16.0):   # the bilge's tanks
        box(33.0, HULL_B, z - 2, 36.0, HULL_B + 2.0, z + 2, "rust")
        box(60.0, HULL_B, z - 2, 63.0, HULL_B + 2.0, z + 2, "rust")

    # Hull A (the cargo hold): side passages down both sides, the hold in the middle, workshops aft
    slab(SX0, SX1, SZ0, SZ1, HULL_A, "metal", holes=[hole(LIFT), hole(MOON_STAIRS), hole(BOW_STAIRS), hole(TOWER_STAIRS)]
         + [(x - 0.7 if yaw == 90 else x - 0.95, x + 0.95 if yaw == 90 else x + 0.7, z - 0.6, z + 0.6) for x, z, yaw in SIDE_LADDERS])
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
    stacks = [(41, -82, 1), (51, -78, 2), (45, -66, 1), (55, -62, 2), (40, -56, 2), (45, -47, 2), (51, -40, 1),
              (39, -32, 1), (55, -28, 2), (44, -20, 2), (52, -14, 1), (40, 14, 1), (52, 16, 2), (45, 27, 2), (51, 36, 1),
              (40, 44, 2), (56, 50, 1), (46, 58, 2), (53, 66, 1)]
    for i, (x, z, high) in enumerate(stacks):
        container(x, HULL_A, z, "z" if i % 2 else "x", ("container_a", "container_b", "container_c")[i % 3], high)
    for i, (x, z) in enumerate([(48, -72), (37.5, -24), (57.5, 4), (49, 46), (38, 64), (56, -50)]):
        add_loot("Hold", "crate", x, HULL_A, z, 90 * (i % 2))
    # workshops aft, under the tower; the stern ramp up to the last barge
    wall("z", 44.0, 74.0, 96.0, HULL_A, hold_h, "metal", [door(80.0), door(92.0)])
    add_loot("Workshop", "crate", 40.0, HULL_A, 80.0, table="crate")
    add_loot("Workshop", "locker", 64.6, HULL_A, 100.0, -90)
    ramp((48.0, HULL_A, 96.0), (48.0, BARGE, SZ1 + 2.5), 7.6, "metal")
    labels.append(("WORKSHOPS", 52, 90, 0))

    # The main deck: the moon pool deckhouse, the derrick, cranes and containers, the forecastle
    slab(SX0, SX1, -90.0, SZ1, DECK, "metal",
         holes=[hole(LIFT), hole(MOON_STAIRS), hole(BOW_STAIRS), hole(TOWER_STAIRS)] + HATCHES)
    slab(SX0, SX1, SZ0, -90.0, DECK, "metal")
    for x0, x1, z0, z1 in HATCHES:   # a low coaming round each open hatch
        room(x0 - 0.3, x1 + 0.3, z0 - 0.3, z1 + 0.3, DECK, 0.5, "rust", t=0.3)
    labels.append(("HATCHES", 48, -54, 0))
    # the forecastle: a raised deck over the bow store, a ramp up
    slab(SX0, SX1, SZ0, -90.0, FORECASTLE, "metal", holes=[(SX0, 34.5, -93.5, -90.0)])
    wall("x", -90.0, 34.5, SX1, DECK, FORECASTLE - DECK - SLAB_T, "hull", [door(40.0, 2.0), door(58.0, 2.0)])
    wall("x", -90.0, SX0, 34.5, FORECASTLE, BULWARK, "hull", [(32.2, 4.0, 0.0, BULWARK)])
    ramp((32.2, DECK, -80.0), (32.2, FORECASTLE, -93.5), 4.0, "metal")
    add_loot("BowStore", "crate", 36.0, DECK, -100.0)
    add_loot("BowStore", "crate", 60.0, DECK, -100.0)
    labels.append(("FORECASTLE", 48, -98, 0))
    # cranes and deck cargo
    for x, z in [(34.0, -62.0), (62.0, 20.0), (34.0, 52.0)]:
        box(x - 1.2, DECK, z - 1.2, x + 1.2, DECK + 9.0, z + 1.2, "rust")
        obox(x + (6 if x < 48 else -6), DECK + 9.4, z, 13.0, 0.8, 1.0, 0, "rust")
    for i, (x, z, along, high) in enumerate([(40, -70, "z", 1), (56, -66, "x", 2), (38, -30, "x", 1), (58, -36, "z", 1),
                                             (40, 40, "z", 2), (56, 46, "x", 1), (44, 62, "x", 1), (58, 66, "z", 2),
                                             (36, -20, "z", 1), (60, 34, "z", 1)]):
        container(x, DECK, z, along, ("container_b", "container_a", "container_c")[i % 3], high)
    for i, (x, z) in enumerate([(51, -70), (35, 36), (52, 58)]):
        add_loot("Deck", "crate", x, DECK, z, 90 * (i % 2))
    labels.append(("MAIN DECK", 48, 46, 0))


def moon_pool():
    """The deckhouse over the moon pool: the lift shaft (a placeholder ladder until the lift is built) and the
    stairs beside it, from the main deck down to the dock in the lab. The derrick stands over it (a perch)."""
    x0, x1, z0, z1 = LIFT
    top = DECK + 3.2
    bottom = LAB1 - SLAB_T
    h = top - bottom
    lo = lambda y: y - bottom
    wall("x", z0, x0, x1, bottom, h, "wall", [(42.0, 2.0, lo(DECK), lo(DECK) + DOOR_H)])
    wall("x", z1, x0, x1, bottom, h, "wall", [(42.0, 2.0, lo(HULL_B), lo(HULL_B) + DOOR_H),
                                                (42.0, 2.0, lo(LAB1), lo(LAB1) + DOOR_H)])
    wall("z", x0, z0, z1, bottom, h, "wall")
    slab(x0, x1, z0, z1, LAB1, "concrete")
    slab(x0, x1, z0, z1, top + SLAB_T, "roof")
    ladder(x0 + 0.5, LAB1, 0.0, 90, DECK - LAB1, "Lift")
    labels.append(("MOON POOL", 46, -12, 0))
    stairwell(46.0, -7.0, [DECK, 0.0, HULL_A, HULL_B, -11.5, -15.0, -18.5, LAB1], {0: "N", 2: "N", 3: "S", 7: "S"})
    # up onto the deckhouse roof, then the derrick's platform
    ladder(x0 - 0.4, DECK, 3.0, -90, top + SLAB_T - DECK, "Derrick")
    roof_y = top + SLAB_T
    box(39.0, roof_y, -1.0, 40.0, 14.0, 1.0, "rust")
    ladder(40.4, roof_y, 0.0, 90, 14.0 - roof_y, "Derrick")
    slab(41.0, 53.0, -5.0, 5.0, 14.0, "metal")
    for x, z in [(41.0, -5.0), (53.0, -5.0), (41.0, 5.0), (53.0, 5.0)]:
        box(x - 0.4, roof_y, z - 0.4, x + 0.4, 24.0, z + 0.4, "rust")
    wall("x", -5.0, 41.0, 53.0, 14.0, 1.0, "rust", t=0.2)
    wall("x", 5.0, 41.0, 53.0, 14.0, 1.0, "rust", t=0.2)
    wall("z", 53.0, -5.0, 5.0, 14.0, 1.0, "rust", t=0.2)
    wall("z", 41.0, -5.0, 5.0, 14.0, 1.0, "rust", [(0.0, 2.0, 0.0, 1.0)], t=0.2)
    labels.append(("DERRICK", 47, 8, 0))


def bow_stairs():
    stairwell(BOW_STAIRS[0], BOW_STAIRS[2], [DECK, 0.0, HULL_A, HULL_B], {0: "W", 2: "W", 3: "W"})


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
    stairwell(TOWER_STAIRS[0], TOWER_STAIRS[2], [ROOF, DECK4, DECK3, DECK2, DECK, 0.0, HULL_A, HULL_B],
              {0: "W", 1: "W", 2: "W", 3: "W", 4: "W", 6: "W", 7: "W"}, roof=True)
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
    """Under the ship on the sea floor: Lab 1 (the dock, the sub bay) under the moon pool; Lab 2's north wing, the
    ring round the core, the south wing; the core (Zero's room, a tall chamber); the service tube from the pump room."""
    labels.append(("SITE ZERO (BELOW)", 48, 20, 0))
    # Lab 1: the dock (y -22): the lift and stairs come in from the north, the sub bay on the east side
    l0, l1, lz0, lz1 = 30.0, 66.0, 7.0, 27.0
    h1 = 3.8
    room(l0, l1, lz0, lz1, LAB1, h1, "lab", n=[door(42.0, 2.0), door(52.0)], s=[door(48.0, 2.0)], roof="lab")
    slab(l0, l1, lz0, lz1, LAB1, "labfloor", holes=[(l0, 34.6, 10.0, 25.0)])
    wall("z", 56.0, lz0, lz1, LAB1, h1, "lab", [door(17.0, 2.0)])
    wall("z", 34.6, 10.0, 25.0, LAB1, 1.0, "lab")   # (a rail along the ramp's opening)
    ramp((32.3, LAB1, 10.0), (32.3, LAB2, 25.0), 4.0, "labfloor")
    extracts.append(("SubBay", "SUB BAY", 61.0, LAB1, 17.0))
    box(58.0, LAB1, 22.0, 65.0, LAB1 + 2.2, 26.0, "core")      # the sub
    add_loot("LabDock", "locker", 54.0, LAB1, 26.0, 180)
    add_loot("LabDock", "locker", 38.0, LAB1, 26.0, 180)
    # Lab 2 north wing (cells, test rooms): y -28, roof at the dock's floor
    nz0, nz1 = -40.0, 32.0
    hn = LAB1 - SLAB_T - LAB2
    room(l0, l1, nz0, nz1, LAB2, hn, "lab", n=[door(47.2)], s=[door(40.0, 2.0), door(56.0, 2.0)], floor="labfloor")
    slab(l0, l1, nz0, lz0, LAB1, "lab")
    slab(l0, l1, lz1, nz1, LAB1, "lab")
    for x in (44.0, 52.0):
        wall("z", x, nz0, nz1, LAB2, hn, "lab", [door(z) for z in (-34.0, -22.0, -10.0, 2.0, 14.0, 26.0)])
    for z in (-28.0, -16.0, -4.0, 8.0, 20.0):
        if z < 9.0:   # (the ramp down from the dock comes in along the west side past z 10)
            wall("x", z, l0, 44.0, LAB2, hn, "lab")
        wall("x", z, 52.0, l1, LAB2, hn, "lab")
    for i, (x, z) in enumerate([(31.5, -36.0), (64.5, -24.0), (31.5, -0.0), (64.5, 12.0)]):
        add_loot("LabWing", "crate", x, LAB2, z, 90 if x < 48 else -90)
    labels.append(("NORTH WING", 48, -36, 0))
    # the ring (6 m wide corridor) round the core, and the core itself (tall: up to y -16)
    rz0, rz1 = 32.0, 68.0
    cx0, cx1, cz0, cz1 = 36.0, 60.0, 38.0, 62.0
    room(l0, l1, rz0, rz1, LAB2, 4.0, "lab", n=[door(40.0, 2.0), door(56.0, 2.0)], s=[door(40.0, 2.0), door(56.0, 2.0)],
         floor="labfloor")
    slab(l0, l1, rz0, rz1, LAB2 + 4.0, "lab", holes=[(cx0, cx1, cz0, cz1)])
    room(cx0, cx1, cz0, cz1, LAB2, 12.0, "core", n=[door(40.0, 2.0), (48.0, 3.0, 6.0, 9.0)], s=[door(48.0, 2.4)],
         roof="core")
    labels.append(("ZERO'S CORE", 48, 50, 1))
    for x, z in [(40.0, 44.0), (56.0, 44.0), (40.0, 56.0), (56.0, 56.0)]:   # the program's tanks (cover)
        box(x - 1.3, LAB2, z - 1.3, x + 1.3, LAB2 + 4.5, z + 1.3, "lab")
    add_loot("LabCore", "safe", 37.0, LAB2, 60.5, 180)
    add_loot("LabCore", "safe", 59.0, LAB2, 60.5, 180)
    add_loot("LabCore", "crate", 48.0, LAB2, 60.0)
    add_loot("LabCore", "crate", 48.0, LAB2, 40.5)
    boss_starts.extend([(48.0, LAB2, 50.0), (44.0, LAB2, 54.0)])
    # the catwalk: from the dock's south door over the ring into the core, a balcony and a ladder down
    room(46.0, 50.0, lz1, cz0, LAB1, 3.0, "lab", n=[door(48.0, 2.0)], s=[door(48.0, 2.0)], floor="labfloor", roof="lab")
    slab(46.0, 50.0, cz0, cz0 + 2.5, LAB1, "labfloor")
    wall("x", cz0 + 2.5, 46.0, 50.0, LAB1, 1.0, "lab", [(48.8, 1.2, 0.0, 1.0)], t=0.15)
    ladder(48.8, LAB2, cz0 + 2.6, 0, LAB1 - LAB2, "Catwalk")
    # Lab 2 south wing (labs, the server room)
    sz0, sz1 = 68.0, 100.0
    room(l0, l1, sz0, sz1, LAB2, 4.0, "lab", n=[door(40.0, 2.0), door(56.0, 2.0)], floor="labfloor", roof="lab")
    for x in (44.0, 52.0):
        wall("z", x, sz0, sz1, LAB2, 4.0, "lab", [door(z) for z in (74.0, 86.0, 96.0)])
    wall("x", 80.0, l0, 44.0, LAB2, 4.0, "lab")
    wall("x", 80.0, 52.0, l1, LAB2, 4.0, "lab")
    wall("x", 90.0, 52.0, l1, LAB2, 4.0, "lab")
    for z in (92.0, 96.0):   # the server racks
        box(55.0, LAB2, z - 0.4, 64.0, LAB2 + 2.2, z + 0.4, "core")
    add_loot("LabWing", "crate", 31.5, LAB2, 72.0, 90)
    add_loot("LabWing", "safe", 64.5, LAB2, 98.5, 180)
    add_loot("LabWing", "crate", 31.5, LAB2, 96.0, 90)
    add_loot("LabWing", "crate", 64.5, LAB2, 84.0, -90)
    labels.append(("SOUTH WING", 48, 92, 0))
    # the service tube: a ladder from the pump room down to a tunnel into the north wing
    tx0, tx1, tz0, tz1 = SERVICE_TUBE
    room(tx0 - 0.3, tx1 + 0.3, tz0 - 0.3, tz1 + 0.3, LAB2, HULL_B - SLAB_T - LAB2, "lab", s=[(47.2, DOOR_W, 0.0, DOOR_H)])
    ladder(47.2, LAB2, tz0 + 0.1, 0, HULL_B - LAB2, "ServiceTube")
    room(45.4, 49.0, tz1 + 0.3, nz0, LAB2, 3.2, "lab", n=[(47.2, DOOR_W, 0.0, DOOR_H)], s=[(47.2, DOOR_W, 0.0, DOOR_H)],
         floor="labfloor", roof="lab")
    slab(tx0 - 0.3, tx1 + 0.3, tz0 - 0.3, tz1 + 0.3, LAB2, "labfloor")
    labels.append(("SERVICE TUBE", 47, -66, 0))
    # under it all, a few columns to the sea bed
    for x, z in [(31.0, -39.0), (65.0, -39.0), (31.0, 99.0), (65.0, 99.0), (31.0, 31.0), (65.0, 31.0)]:
        box(x - 0.6, SEABED, z - 0.6, x + 0.6, LAB2 - SLAB_T, z + 0.6, "lab")


# ---------------------------------------------------------------------------------------------- AI
# Zones (name, x, y, z, radius, scavs, raiders, trickle): few on the shore, more on the ship, Zero below.
AI_ZONES = [("Landing", -135.0, SHORE, 0.0, 70.0, 3, 0, 0.6), ("Deck", 48.0, DECK, -30.0, 70.0, 4, 0, 1.0),
            ("Tower", 48.0, DECK2, 90.0, 26.0, 0, 2, 1.0), ("Hold", 48.0, HULL_A, 0.0, 80.0, 4, 0, 1.0),
            ("Lab", 48.0, LAB2, 30.0, 70.0, 0, 2, 1.5)]
AI_ROAMERS = 2
AI_SNIPERS = 1
AI_BOSS = ("Lab", 3, 1.0)   # Zero always spawns (gray box: Bon's setup until Zero's own loadout is in)
ZONE_SPOTS = {
    "Landing": [(-130.0, SHORE, -40.0), (-112.0, SHORE, 28.0), (-150.0, SHORE, 20.0), (-118.0, SHORE, -100.0),
                (-135.0, SHORE, 90.0), (-110.0, SHORE, 150.0)],
    "Deck": [(40.0, DECK, -60.0), (56.0, DECK, -40.0), (36.0, DECK, -10.0), (60.0, DECK, 12.0), (44.0, DECK, 52.0),
             (56.0, DECK, 70.0), (48.0, FORECASTLE, -98.0)],
    "Tower": [(38.0, DECK2, 80.0), (50.0, DECK2, 100.0), (38.0, DECK3, 98.0), (48.0, DECK4, 84.0), (40.0, DECK, 100.0)],
    "Hold": [(48.0, HULL_A, -60.0), (33.0, HULL_A, -30.0), (63.0, HULL_A, 10.0), (48.0, HULL_A, 40.0),
             (40.0, HULL_B, 50.0), (56.0, HULL_B, -80.0), (48.0, HULL_B, -20.0), (40.0, HULL_A, 86.0)],
    "Lab": [(48.0, LAB1, 15.0), (48.0, LAB2, -30.0), (48.0, LAB2, 10.0), (33.0, LAB2, 50.0), (63.0, LAB2, 50.0),
            (48.0, LAB2, 86.0), (48.0, LAB2, 65.0)],
}
ROAMER_SPOTS = [(-48.0, PIER, 2.0), (0.0, PIER, -117.0), (-50.0, BARGE, 121.0)]


def ai():
    for name, *_ in AI_ZONES:
        for x, y, z in ZONE_SPOTS[name]:
            enemy_spawns.append((x, y, z, name))
    for x, y, z in ROAMER_SPOTS:
        enemy_spawns.append((x, y, z, ""))


def spawner_meta():
    zones = ", ".join(f'{{"name": "{n}", "center": Vector3({fmt(x)}, {fmt(y)}, {fmt(z)}), "radius": {fmt(r)}, '
                      f'"scavs": {s}, "raiders": {rd}, "trickle": {fmt(t)}}}' for n, x, y, z, r, s, rd, t in AI_ZONES)
    scavs = sum(z[5] for z in AI_ZONES) + AI_ROAMERS
    raiders = sum(z[6] for z in AI_ZONES)
    return (f'metadata/spawner = {{"zones": [{zones}], "roamers": {AI_ROAMERS}, "snipers": {AI_SNIPERS}, "initial_count": 0, '
            f'"boss": {{"zone": "{AI_BOSS[0]}", "guards": {AI_BOSS[1]}, "chance": {fmt(AI_BOSS[2])}}}, '
            f'"max_alive": 28, "scav_budget": {scavs + 4}, "raider_budget": {raiders + 3}, '
            '"scav_interval_min": 60.0, "scav_interval_max": 80.0, '
            '"raider_times": PackedFloat32Array(240, 480, 660), "min_distance_from_player": 40.0}')


def minimap_meta():
    """The in-raid map (M): map metres from the top-left corner (x + 180, z + 180)."""
    def floats(values):
        return "PackedFloat32Array(" + ", ".join(fmt(v) for v in values) + ")"
    bld = [v for x0, z0, x1, z1 in footprints for v in (x0 + HALF, z0 + HALF, x1 + HALF, z1 + HALF)]
    text = ", ".join(f'["{t}", {fmt(x + HALF)}, {fmt(z + HALF)}, {big}]' for t, x, z, big in labels)
    sea = "[PackedVector2Array(225, 0, 225, 360)]"
    yards = [-94 + HALF, -2 + HALF, SX0 + HALF, 7.2 + HALF]   # the pier
    return ("metadata/minimap = {" + f'"size": {fmt(M)}, "offset": {fmt(-HALF)}, '
            + f'"buildings": {floats(bld)}, "yards": {floats(yards)}, "woods": PackedFloat32Array(), '
            + f'"roads": [PackedVector2Array(0, 179, 62, 179)], "road_widths": PackedFloat32Array(6), '
            + f'"water": {sea}, "water_widths": PackedFloat32Array(266), '
            + f'"labels": [{text}]' + "}")


# ---------------------------------------------------------------------------------------------- the scene
def terrain():
    """The ground: flat shore, a beach, then down to the sea bed. One row of heights across x, the same all along z."""
    xs = [-HALF, -92.0, -86.0, -70.0, -40.0, -15.0, HALF]
    hs = [SHORE, SHORE, 0.0, -6.0, -22.0, SEABED, SEABED]
    zs = [-HALF, 0.0, HALF]
    return xs, zs, [h for _ in zs for h in hs]


def xform(x, y, z, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return f"Transform3D({fmt(c)}, 0, {fmt(s)}, 0, 1, 0, {fmt(-s)}, 0, {fmt(c)}, {fmt(x)}, {fmt(y)}, {fmt(z)})"


def sea_planes():
    """The sea's surface (y 0) round the ship, so it isn't drawn inside the hull: four flat pieces."""
    pieces = [(-88.0, -HALF, HALF, SZ0 - 0.3), (-88.0, SZ1 + 0.3, HALF, HALF),
              (-88.0, SZ0 - 0.3, SX0 - 0.3, SZ1 + 0.3), (SX1 + 0.3, SZ0 - 0.3, HALF, SZ1 + 0.3)]
    out = []
    for i, (x0, z0, x1, z1) in enumerate(pieces):
        out += [f'[node name="Sea{i}" type="MeshInstance3D" parent="Level"]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt((x0 + x1) / 2)}, 0, {fmt((z0 + z1) / 2)})",
                f'mesh = SubResource("sea_{i}")', 'material_override = SubResource("sea_mat")', "cast_shadow = 0", ""]
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
           '[ext_resource type="PackedScene" path="res://scenes/extract_zone.tscn" id="2_extract"]']
    ids = {}
    for n, (kind, path) in enumerate(scenes.items(), start=3):
        ids[kind] = f"{n}_{kind}"
        out.append(f'[ext_resource type="PackedScene" path="{path}" id="{ids[kind]}"]')
    out += [""] + subs
    out += ["; Generated by tools/gen_riptide.py: edit that script and re-run it, don't edit this file.", "",
            '[node name="Riptide" type="Node3D"]',
            'metadata/map_name = "Riptide"',
            spawner_meta(),
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
    for name, title, x, y, z in extracts:
        out += [f'[node name="{name}" parent="Extracts" instance=ExtResource("2_extract")]',
                f"transform = {xform(x, y, z)}", f'extract_name = "{title}"', ""]
    out += ['[node name="PlayerSpawns" type="Node3D" parent="."]', ""]
    for i, (x, y, z) in enumerate(player_spawns):
        out += [f'[node name="Spawn{i + 1}" type="Marker3D" parent="PlayerSpawns"]', f"transform = {xform(x, y + 0.1, z)}", ""]
    out += ['[node name="EnemySpawns" type="Node3D" parent="."]', ""]
    for i, (x, y, z, zone) in enumerate(enemy_spawns):
        out += [f'[node name="EnemySpawn{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.1, z)}"]
        out += ([f'metadata/zone = "{zone}"'] if zone else []) + [""]
    for i, (x, y, z) in enumerate(boss_starts):
        out += [f'[node name="BossStart{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.1, z)}",
                "metadata/boss_start = true", ""]
    for i, (x, y, z, fx, fz) in enumerate(perches):
        out += [f'[node name="Perch{i + 1}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y + 0.3, z)}",
                "metadata/perch = true", f"metadata/face = Vector3({fx}, 0, {fz})", ""]
    with open(OUT, "w") as f:
        f.write("\n".join(out))


def main():
    shore()
    crossings()
    ship()
    moon_pool()
    bow_stairs()
    tower()
    lab()
    ai()
    write_scene()
    print(f"riptide: {len(boxes)} boxes, {len(loot)} loot, {len(ladders)} ladders, {len(extracts)} extracts, "
          f"{len(player_spawns)} player spawns, {len(enemy_spawns)} enemy spawns -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
