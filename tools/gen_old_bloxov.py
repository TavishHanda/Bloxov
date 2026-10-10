#!/usr/bin/env python3
"""Builds the Bloxov Battlegrounds gray-box map (0.10.0; first called Old Bloxov): writes scenes/maps/old_bloxov.tscn.

The layout follows docs/MAP_PLAN.md and the agreed picture docs/maps/old_bloxov_layout.png (draft 5).
Coordinates below are in "map meters" like the picture: x to the right (east), y down (south), origin at the
top-left corner, map 350 x 350 m. Godot: x = mx - 175, z = my - 175 (north = -Z), y up.

This script is the source of truth for the gray box: edit it and re-run it, don't hand-edit the .tscn.
    python3 tools/gen_old_bloxov.py
Everything solid is a box (see scripts/box_map.gd). Loot containers, extracts and spawn points are real nodes.
Spawn points, extracts and loot spots are placeholders (owner: Scavs 2.0 and the Items update rework them).
"""

import bisect
import contextlib
import math
import os
import random

M = 350.0
OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "old_bloxov.tscn")

FLOOR_H = 3.0      # one storey
WALL_T = 0.3       # wall thickness
SLAB_T = 0.25      # floor slab thickness
RAMP_W = 2.2       # stair ramp width (AI paths need 2 m: they keep 0.75 m from edges)
RAMP_L = 4.4       # ramp length for one storey (34 degrees; AI paths allow 40)
LANDING = 2.5      # flat floor at the top of a ramp (AI paths keep 0.75 m from the wall and the drop)
# Doorways are wide for a gray box so the AI's paths fit through (they keep 0.75 m from walls).
DOOR_W, DOOR_H = 2.2, 2.4
INNER_DOOR_W = 2.0
WIN_W, WIN_LO, WIN_HI = 1.4, 1.0, 2.2

# ---------------------------------------------------------------------------------------------- colours
COLOURS = [
    ("grass", (0.47, 0.62, 0.36)),
    ("road", (0.33, 0.33, 0.35)),
    ("pavement", (0.62, 0.6, 0.56)),
    ("slab", (0.55, 0.53, 0.5)),
    ("roof", (0.42, 0.36, 0.33)),
    ("wall", (0.78, 0.74, 0.66)),
    ("wall_rich", (0.86, 0.78, 0.55)),
    ("wall_police", (0.55, 0.64, 0.78)),
    ("wall_hall", (0.74, 0.5, 0.42)),
    ("wall_guns", (0.5, 0.5, 0.5)),
    ("wall_med", (0.85, 0.62, 0.62)),
    ("wall_food", (0.6, 0.75, 0.52)),
    ("wall_school", (0.7, 0.62, 0.82)),
    ("wall_fuel", (0.88, 0.66, 0.4)),
    ("wall_farm", (0.66, 0.42, 0.32)),
    ("wood", (0.52, 0.38, 0.25)),
    ("trunk", (0.4, 0.3, 0.2)),
    ("leaves", (0.3, 0.5, 0.26)),
    ("water", (0.35, 0.55, 0.75)),
    ("rail", (0.38, 0.3, 0.24)),
    ("metal", (0.45, 0.47, 0.5)),
    ("car_a", (0.55, 0.25, 0.22)),
    ("car_b", (0.3, 0.38, 0.55)),
    ("concrete", (0.66, 0.66, 0.64)),
    ("bunker", (0.45, 0.46, 0.44)),
    ("keydoor", (0.85, 0.2, 0.2)),
    ("crop", (0.72, 0.68, 0.38)),
    ("boundary", (0.5, 0.5, 0.5)),
    ("hay", (0.85, 0.75, 0.4)),
    ("boxcar", (0.55, 0.3, 0.2)),
    ("dirt", (0.55, 0.46, 0.34)),
    ("army", (0.36, 0.42, 0.28)),
    ("sandbag", (0.62, 0.56, 0.4)),
    ("stone", (0.6, 0.6, 0.62)),
    ("rust", (0.5, 0.33, 0.22)),
    ("wall_modern", (0.82, 0.84, 0.86)),
    ("brand", (0.2, 0.55, 0.45)),
    ("scorch", (0.22, 0.2, 0.19)),
    ("deadwood", (0.3, 0.26, 0.22)),
    ("earth", (0.36, 0.28, 0.2)),
]
C = {name: i for i, (name, _) in enumerate(COLOURS)}

boxes = []  # (cx, cy, cz, sx, sy, sz, yaw, pitch, colour, solid) in Godot space
# What each box sits on (0.11.17, hills): None = the ground under it (or the flat pad it stands on), ("g", n) = a
# group that moves as one (a car, a tree), ("seg", ...) = a piece of a strip that tilts with the ground (roads,
# fences), ("wire", ...) = a power line between two poles, "ground" = the old flat ground (only kept for the clutter
# placement, then dropped). Boxes are built flat at height 0 first; `terrain()` lifts them onto the hills.
anchors = []
_anchor = [None]
_groups = [0]


@contextlib.contextmanager
def anchored(a):
    _anchor.append(a)
    try:
        yield
    finally:
        _anchor.pop()


def group():
    """Boxes made inside `with group():` move up or down together (the lowest any of them needs)."""
    _groups[0] += 1
    return anchored(("g", _groups[0]))


def gx(mx):
    return mx - M / 2


def gz(my):
    return my - M / 2


def box(x0, y0, z0, x1, y1, z1, colour, solid=True):
    """Axis-aligned box from map-space corners (x/z in map meters, y = height)."""
    if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01:
        return
    boxes.append(((x0 + x1) / 2 - M / 2, (y0 + y1) / 2, (z0 + z1) / 2 - M / 2,
                  x1 - x0, y1 - y0, z1 - z0, 0.0, 0.0, C[colour], 1 if solid else 0))
    anchors.append(_anchor[-1])


def obox(cx, cy, cz, sx, sy, sz, yaw, colour, solid=True, pitch=0.0):
    """Rotated box: centre in map space, yaw in degrees (Godot convention, around +Y)."""
    boxes.append((cx - M / 2, cy, cz - M / 2, sx, sy, sz, yaw, pitch, C[colour], 1 if solid else 0))
    anchors.append(_anchor[-1])


# ---------------------------------------------------------------------------------------------- nodes
loot = []        # (name, scene, x, y, z, yaw, table, place)
extracts = []    # (node name, display name, x, z)
player_spawns = []
enemy_spawns = []
NO_INDOOR_SPAWNS = {"Grocery"}   # rooms full of shelves
indoor_spawns = []   # (name, x, z, zone): AI spawn spots inside buildings, in the middle of ground-floor rooms
buildings = []
markers = []     # (group node, name, x, y, z, metadata dict)


def add_loot(place, kind, x, z, y=0.0, yaw=0.0):
    """kind: crate / locker / safe (existing loot tables; the Items update gives each place its own)."""
    n = sum(1 for l in loot if l[0].startswith(place + "_")) + 1
    loot.append((f"{place}_{kind.capitalize()}{n}", kind, x, y, z, yaw, kind, place))


# ---------------------------------------------------------------------------------------------- walls
def wall_x(x0, x1, z, y0, h, colour, openings=(), t=WALL_T):
    """A wall along x (from x0 to x1 at depth z). openings: (centre_x, width, bottom, top)."""
    _wall(x0, x1, y0, h, colour, openings, lambda a, b, y_lo, y_hi: box(a, y_lo, z - t / 2, b, y_hi, z + t / 2, colour))


def wall_z(z0, z1, x, y0, h, colour, openings=(), t=WALL_T):
    _wall(z0, z1, y0, h, colour, openings, lambda a, b, y_lo, y_hi: box(x - t / 2, y_lo, a, x + t / 2, y_hi, b, colour))


def _wall(a0, a1, y0, h, colour, openings, put):
    cuts = sorted((c - w / 2, c + w / 2, lo, hi) for c, w, lo, hi in openings)
    pos = a0
    for lo_a, hi_a, lo, hi in cuts:
        lo_a, hi_a = max(lo_a, a0), min(hi_a, a1)
        if hi_a <= lo_a:
            continue
        put(pos, lo_a, y0, y0 + h)
        put(lo_a, hi_a, y0, y0 + lo)          # sill
        put(lo_a, hi_a, y0 + hi, y0 + h)      # lintel
        pos = hi_a
    put(pos, a1, y0, y0 + h)


# ---------------------------------------------------------------------------------------------- buildings
class Building:
    """A rectangular building: `floors` storeys, rooms in an nx x nz grid with doorways between all neighbours,
    windows in every outside room wall, ramps (stairs) between storeys, optional flat roof you can walk on."""

    def __init__(self, name, x, y, w, d, floors=1, colour="wall", rooms=(2, 2), doors="S", roof=False,
                 height=FLOOR_H, solid_inner=(), no_windows=(), big_doors=False, blasts=(), caved=()):
        self.name, self.x0, self.z0, self.x1, self.z1 = name, x, y, x + w, y + d
        self.floors, self.colour, self.nx, self.nz = floors, colour, rooms[0], rooms[1]
        self.doors, self.roof, self.h = doors, roof, height
        self.solid_inner = set(solid_inner)   # interior wall segments with no doorway: ("v"|"h", i, j)
        self.no_windows = set(no_windows)     # rooms (i, j) whose outside walls get no windows
        self.big_doors = big_doors
        # War damage (owner, 0.11.6): blasts = blown-out holes in outside walls, (floor, side, k) with k the room
        # along that wall; caved = rooms (i, j) whose roof fell in. Rubble and scorch marks come with them.
        self.blasts, self.caved = set(blasts), set(caved)
        self.holes = {}   # storey -> (x0, z0, x1, z1) slab hole above a ramp
        self.cw = (self.x1 - self.x0) / self.nx
        self.cd = (self.z1 - self.z0) / self.nz

    def cell(self, i, j):
        return (self.x0 + i * self.cw, self.z0 + j * self.cd, self.x0 + (i + 1) * self.cw, self.z0 + (j + 1) * self.cd)

    def build(self):
        storeys = self.floors + (1 if self.roof else 0)
        # Stairs are ramps in a 2.2 m strip along an outside wall, with a landing at the top (the floor
        # above) and room to walk onto them at the bottom: storey ramps along the north wall (landing at the west
        # end), the roof ramp along the south wall (landing at the east end), so they never stack. Inner walls
        # stop at the strip, so it's a little corridor downstairs.
        self.ramps = []
        for f in range(storeys - 1):
            self.ramps.append((f, "S" if f == self.floors - 1 else "N"))
        self.strips = []
        for f, wall in self.ramps:
            if wall == "N":
                self.strips.append((self.x0, self.x0 + WALL_T / 2 + LANDING + self._ramp_len() + 1.8, self.z0, self.z0 + WALL_T / 2 + RAMP_W))
            else:
                self.strips.append((self.x1 - WALL_T / 2 - LANDING - self._ramp_len() - 1.8, self.x1, self.z1 - WALL_T / 2 - RAMP_W, self.z1))
        box(self.x0, 0.0, self.z0, self.x1, 0.03, self.z1, "slab", solid=False)   # ground floor (looks only)
        for f in range(self.floors):
            y = f * self.h
            self._outer_walls(f, y)
            self._inner_walls(y)
        for f, wall in self.ramps:
            self._ramp(f, wall)
        for f in range(1, self.floors + 1):
            self._slab(f)
        if self.roof:
            ry = self.floors * self.h
            for (a0, a1, z) in ((self.x0, self.x1, self.z0), (self.x0, self.x1, self.z1)):
                box(a0, ry, z - 0.15, a1, ry + 1.0, z + 0.15, self.colour)
            for x in (self.x0, self.x1):
                box(x - 0.15, ry, self.z0, x + 0.15, ry + 1.0, self.z1, self.colour)

    def _ramp_len(self):
        return RAMP_L * self.h / FLOOR_H

    def _outer_walls(self, f, y):
        for side in "NSWE":
            horizontal = side in "NS"
            n = self.nx if horizontal else self.nz
            openings = []
            for k in range(n):
                cell = (k, 0 if side == "N" else self.nz - 1) if horizontal else (0 if side == "W" else self.nx - 1, k)
                a0, a1 = (self.x0 + k * self.cw, self.x0 + (k + 1) * self.cw) if horizontal else \
                         (self.z0 + k * self.cd, self.z0 + (k + 1) * self.cd)
                mid = (a0 + a1) / 2
                if (f, side, k) in self.blasts:
                    assert not (f == 0 and side in self.doors and k == n // 2), f"{self.name}: blast on the door"
                    assert not self._ramp_blocks(f, side, cell), f"{self.name}: blast behind the stairs"
                    w = min(3.4, a1 - a0 - 0.6)
                    openings.append((mid, w, 0.0 if f == 0 else 0.5, self.h if f == self.floors - 1 else self.h - 0.6))
                elif f == 0 and side in self.doors and k == n // 2:
                    if self.big_doors:
                        openings.append((mid, min(4.0, a1 - a0 - 1.0), 0.0, 4.0))
                    else:
                        openings.append((mid, DOOR_W, 0.0, DOOR_H))
                elif cell not in self.no_windows and a1 - a0 >= 2.6 and not self._ramp_blocks(f, side, cell):
                    openings.append((mid, WIN_W, WIN_LO, WIN_HI))
            if horizontal:
                wall_x(self.x0, self.x1, self.z0 if side == "N" else self.z1, y, self.h, self.colour, openings)
            else:
                wall_z(self.z0, self.z1, self.x0 if side == "W" else self.x1, y, self.h, self.colour, openings)

    def _ramp_blocks(self, f, side, cell):
        # No windows behind the ramps.
        x0, _, x1, _ = self.cell(*cell)
        for (rf, wall), (sx0, sx1, _, _) in zip(self.ramps, self.strips):
            if side == wall and rf in (f, f - 1) and x0 < sx1 and x1 > sx0:
                return True
        return False

    def _inner_walls(self, y):
        h = self.h
        for i in range(1, self.nx):          # walls along z at x = x0 + i*cw
            x = self.x0 + i * self.cw
            for j in range(self.nz):
                a0, a1 = self.z0 + j * self.cd + WALL_T / 2, self.z0 + (j + 1) * self.cd - WALL_T / 2
                for sx0, sx1, sz0, sz1 in self.strips:
                    if sx0 < x < sx1:
                        if sz0 <= a0 < sz1:
                            a0 = sz1
                        if sz0 < a1 <= sz1:
                            a1 = sz0
                if a1 - a0 < 0.5:
                    continue
                # (a short piece next to a stair strip has its doorway in the strip itself)
                op = [] if ("v", i, j) in self.solid_inner or a1 - a0 < INNER_DOOR_W + 1.6 else \
                    [((a0 + a1) / 2, INNER_DOOR_W, 0.0, DOOR_H)]
                wall_z(a0, a1, x, y, h, self.colour, op, t=0.2)
        for j in range(1, self.nz):          # walls along x at z = z0 + j*cd
            z = self.z0 + j * self.cd
            for i in range(self.nx):
                a0, a1 = self.x0 + i * self.cw, self.x0 + (i + 1) * self.cw
                op = [] if ("h", i, j) in self.solid_inner else [((a0 + a1) / 2, INNER_DOOR_W, 0.0, DOOR_H)]
                wall_x(a0 + WALL_T / 2, a1 - WALL_T / 2, z, y, h, self.colour, op, t=0.2)

    def _ramp(self, f, wall):
        """A ramp up from storey f to f+1 in the strip along the `wall` (N: climbs west to a landing in the north-west
        corner; S: climbs east to a landing in the south-east corner)."""
        length = self._ramp_len()
        if wall == "N":
            rz0 = self.z0 + WALL_T / 2
            hi_x = self.x0 + WALL_T / 2 + LANDING
            lo_x = hi_x + length
        else:
            rz0 = self.z1 - WALL_T / 2 - RAMP_W
            hi_x = self.x1 - WALL_T / 2 - LANDING
            lo_x = hi_x - length
        rz1 = rz0 + RAMP_W
        y0, y1 = f * self.h, (f + 1) * self.h
        slope = math.hypot(length, y1 - y0)
        angle = math.degrees(math.atan2(y1 - y0, length))
        cx, cy, cz = (lo_x + hi_x) / 2, (y0 + y1) / 2 - 0.1, (rz0 + rz1) / 2
        # A thin plank between the two floors, pitched so its +z end is the low end, then turned so that end
        # points at lo_x (yaw +90: local +z points east; -90: west).
        yaw = 90.0 if lo_x > hi_x else -90.0
        obox(cx, cy, cz, RAMP_W, 0.2, slope, yaw, "wood", pitch=angle)
        # The hole upstairs is over the ramp only; the floor beyond its top end is the landing.
        hx0, hx1 = min(lo_x, hi_x), max(lo_x, hi_x)
        self.holes[f + 1] = (hx0, rz0, hx1, rz1)
        # Rails round the hole upstairs (its open side and its low end), so nobody walks off the edge.
        rail_z = rz1 + 0.05 if wall == "N" else rz0 - 0.05
        box(hx0, y1, rail_z - 0.05, hx1, y1 + 1.0, rail_z + 0.05, "metal")
        if wall == "N":
            box(hx1, y1, rz0, hx1 + 0.1, y1 + 1.0, rz1, "metal")
        else:
            box(hx0 - 0.1, y1, rz0, hx0, y1 + 1.0, rz1, "metal")

    def _slab(self, f):
        y = f * self.h
        x0, z0, x1, z1 = self.x0, self.z0, self.x1, self.z1
        colour = "roof" if f == self.floors else "slab"
        holes = [self.holes[f]] if f in self.holes else []
        if f == self.floors:
            for i, j in self.caved:
                c = self.cell(i, j)
                assert not any(c[0] < sx1 and sx0 < c[2] and c[1] < sz1 and sz0 < c[3] for sx0, sx1, sz0, sz1 in self.strips), \
                    f"{self.name}: caved roof over the stairs"
                holes.append(c)
        # the slab minus its holes, cut into rectangles along the holes' edges
        xs = sorted({x0, x1} | {h[0] for h in holes} | {h[2] for h in holes})
        zs = sorted({z0, z1} | {h[1] for h in holes} | {h[3] for h in holes})
        for a in range(len(xs) - 1):
            for b in range(len(zs) - 1):
                cx, cz = (xs[a] + xs[a + 1]) / 2, (zs[b] + zs[b + 1]) / 2
                if not any(h[0] < cx < h[2] and h[1] < cz < h[3] for h in holes):
                    box(xs[a], y - SLAB_T, zs[b], xs[a + 1], y, zs[b + 1], colour)

    def damage_debris(self, rng):
        """Rubble and scorch marks for the blasts and caved roofs (looks only inside, so nothing blocks a room)."""
        for f, side, k in sorted(self.blasts):
            y = f * self.h
            horizontal = side in "NS"
            if horizontal:
                mid = self.x0 + (k + 0.5) * self.cw
                wz = self.z0 if side == "N" else self.z1
                out = -1 if side == "N" else 1
                at = lambda along, off: (mid + along, wz + out * off)
                face = lambda along, yy, w, hh: obox(mid + along, yy, wz + out * (WALL_T / 2 + 0.03), w, hh, 0.04, 0,
                                                     "scorch", solid=False)
            else:
                mid = self.z0 + (k + 0.5) * self.cd
                wx = self.x0 if side == "W" else self.x1
                out = -1 if side == "W" else 1
                at = lambda along, off: (wx + out * off, mid + along)
                face = lambda along, yy, w, hh: obox(wx + out * (WALL_T / 2 + 0.03), yy, mid + along, 0.04, hh, w, 0,
                                                     "scorch", solid=False)
            # scorch round the hole (not over it), and jagged bits of wall hanging into it
            hw = min(3.4, (self.cw if horizontal else self.cd) - 0.6) / 2
            for sgn in (-1, 1):
                face(sgn * (hw + 0.6), y + self.h * 0.45, 1.2, self.h * 0.8)
                jx, jz = at(sgn * (hw - 0.3), 0)
                jh = rng.uniform(0.25, 0.5) * self.h
                obox(jx, y + self.h - jh / 2, jz, 0.6 if horizontal else WALL_T, jh, WALL_T if horizontal else 0.6, 0,
                     self.colour)
            if f < self.floors - 1:
                face(0, y + self.h - 0.35, 2 * hw, 0.6)
            for _ in range(rng.randint(5, 8)):   # chunks blown out onto the ground
                px, pz = at(rng.uniform(-3, 3), rng.uniform(1.0, 4.5))
                w, h, d = rng.uniform(0.4, 1.3), rng.uniform(0.2, 0.6), rng.uniform(0.4, 1.3)
                obox(px, h / 2, pz, w, h, d, rng.uniform(0, 90), rng.choice((self.colour, "concrete", "scorch")), solid=False)
            for sgn in (-1, 1):                    # a solid heap each side of the hole (cover)
                px, pz = at(sgn * rng.uniform(2.6, 3.4), rng.uniform(1.4, 2.4))
                obox(px, 0.45, pz, rng.uniform(1.4, 2.2), 0.9, rng.uniform(1.0, 1.6), rng.uniform(0, 90), self.colour)
        top = (self.floors - 1) * self.h
        for i, j in sorted(self.caved):
            cx0, cz0, cx1, cz1 = self.cell(i, j)
            cx, cz = (cx0 + cx1) / 2, (cz0 + cz1) / 2
            for _ in range(rng.randint(6, 10)):
                w, h, d = rng.uniform(0.5, 1.6), rng.uniform(0.15, 0.5), rng.uniform(0.5, 1.6)
                obox(cx + rng.uniform(-1.6, 1.6), top + h / 2, cz + rng.uniform(-1.6, 1.6), w, h, d, rng.uniform(0, 90),
                     rng.choice(("roof", "slab", "wood", "scorch")), solid=False)
            obox(cx, top + 0.9, cz, min(cx1 - cx0, cz1 - cz0) * 0.6, 0.15, 2.6, rng.uniform(0, 180), "roof",
                 solid=False, pitch=35.0)   # a piece of the roof hanging down
            box(cx0 + 0.3, top + 0.031, cz0 + 0.3, cx1 - 0.3, top + 0.04, cz1 - 0.3, "scorch", solid=False)

    def room_centre(self, i, j, floor=0):
        cx0, cz0, cx1, cz1 = self.cell(i, j)
        return (cx0 + cx1) / 2, floor * self.h, (cz0 + cz1) / 2

    def against_wall(self, i, j, floor=0, side="E", offset=0.0):
        """A spot for a container inside room (i, j), against its `side` wall."""
        cx0, cz0, cx1, cz1 = self.cell(i, j)
        y = floor * self.h
        # Never in front of the outside door (it would block it): slide along the wall.
        horizontal = side in "NS"
        n = self.nx if horizontal else self.nz
        k = i if horizontal else j
        outer = (side == "N" and j == 0) or (side == "S" and j == self.nz - 1) or \
                (side == "W" and i == 0) or (side == "E" and i == self.nx - 1)
        if floor == 0 and outer and side in self.doors and k == n // 2 and abs(offset) < 2.0:
            offset = 2.4 if offset >= 0 else -2.4
        if side == "E":
            return cx1 - 0.7, y, (cz0 + cz1) / 2 + offset, 90.0
        if side == "W":
            return cx0 + 0.7, y, (cz0 + cz1) / 2 + offset, -90.0
        if side == "S":
            return (cx0 + cx1) / 2 + offset, y, cz1 - 0.6, 0.0
        return (cx0 + cx1) / 2 + offset, y, cz0 + 0.6, 180.0


def build(b, loot_spots=()):
    """loot_spots: (kind, room i, room j, floor, wall side, offset)."""
    footprints.append((b.name, b.x0, b.z0, b.x1, b.z1))
    buildings.append(b)
    b.build()
    b.damage_debris(random.Random(b.name))
    for kind, i, j, floor, side, off in loot_spots:
        x, y, z, yaw = b.against_wall(i, j, floor, side, off)
        add_loot(b.name, kind, x, z, y=y, yaw=yaw)
    return b


# ---------------------------------------------------------------------------------------------- ground
def ground(holes):
    """The old flat grass, cut round `holes` (openings down to the bunker, the trench). Since 0.11.17 the real ground
    is the hill mesh (`terrain()`); these boxes are only made so the clutter lands where it always has, then dropped."""
    xs = sorted({0.0, M} | {h[0] for h in holes} | {h[2] for h in holes})
    zs = sorted({0.0, M} | {h[1] for h in holes} | {h[3] for h in holes})
    for a in range(len(xs) - 1):
        for b in range(len(zs) - 1):
            cx, cz = (xs[a] + xs[a + 1]) / 2, (zs[b] + zs[b + 1]) / 2
            if any(h[0] <= cx <= h[2] and h[1] <= cz <= h[3] for h in holes):
                continue
            with anchored("ground"):
                box(xs[a], -1.0, zs[b], xs[a + 1], 0.0, zs[b + 1], "grass")


roads = []        # (points, width) of every road, for the overlap check
footprints = []   # (name, x0, z0, x1, z1) of every building
labels = []       # (text, x, z, big) for the in-raid map (M)
water = []        # (points, width) of water, for the map
woods = []        # (x, z, radius) of tree clusters, for the map
yards = []        # (x0, z0, x1, z1) of yards, fields and paving, for the map
# A dug trench line in the open field south of the town hall (owner, 0.11.8: trench warfare). Axis-aligned
# rectangles (x0, z0, x1, z1) that overlap at the corners; the ground has holes there and the floor is 1.1 m down.
TRENCHES = [(126, 172, 140, 174.4), (137.6, 172, 140, 180), (137.6, 177.6, 158, 180), (155.6, 170, 158, 180),
            (155.6, 170, 176, 172.4)]
TRENCH_DEPTH = 1.1
BUNKER_HOLE = (85.5, 148.0, 94.0, 150.4)   # the ramp down to the bunker, at the town hall's west end
BUNKER = (80.0, 143.0, 132.0, 159.0)       # the bunker under the town hall
areas = []        # (name, x0, z0, x1, z1) of yards (junkyard, graveyard): kept off roads, buildings may stand inside


def smooth(points, step=5.0):
    """A Catmull-Rom curve through the points (so roads bend instead of kinking), sampled about every `step` m."""
    if len(points) < 3:
        return list(points)
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        n = max(2, int(math.hypot(p2[0] - p1[0], p2[1] - p1[1]) / step))
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
    out.append(points[-1])
    return out


def road(points, width):
    """A road through `points`, smoothed. Each road sits a hair higher than the one before, so where two meet
    neither flickers through the other."""
    curve = smooth(points)
    roads.append((curve, width))
    strip(curve, width, "road", y=0.02 + 0.004 * len(roads))
    return curve


def strip(points, width, colour, y=0.02, h=0.04, solid=False):
    """A flat band along a polyline (roads, paths, water). Pieces overlap a little at each bend so there are no
    gaps; every other piece is a millimetre higher so the overlaps don't flicker."""
    for k, ((ax, az), (bx, bz)) in enumerate(zip(points, points[1:])):
        length = math.hypot(bx - ax, bz - az)
        if length < 0.01:
            continue
        yaw = math.degrees(math.atan2(bx - ax, bz - az))
        lift = 0.001 * (k % 2)
        with anchored(("seg", ax, az, bx, bz, width)):
            obox((ax + bx) / 2, y + h / 2 + lift, (az + bz) / 2, width, h, length + width * 0.5, yaw, colour, solid)


def bezier(p0, p1, p2, p3, n=24):
    out = []
    for k in range(n + 1):
        t = k / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


# ---------------------------------------------------------------------------------------------- props (cover)
def car(x, z, yaw, colour="car_a"):
    with group():
        obox(x, 0.55, z, 1.9, 1.1, 4.2, yaw, colour)
        obox(x, 1.35, z, 1.7, 0.6, 2.2, yaw, colour)


def dumpster(x, z, yaw=0.0):
    obox(x, 0.7, z, 2.0, 1.4, 1.2, yaw, "metal")


def barrier(x, z, yaw):
    obox(x, 0.45, z, 0.6, 0.9, 3.0, yaw, "concrete")


def planter(x, z):
    box(x - 1.5, 0, z - 1.0, x + 1.5, 1.0, z + 1.0, "concrete")


def stall(x, z, yaw=0.0):
    with group():
        obox(x, 0.55, z, 3.0, 1.1, 1.6, yaw, "wood")
        obox(x, 2.4, z, 3.4, 0.15, 2.2, yaw, "car_b", solid=False)
        for dx in (-1.5, 1.5):
            ox = x + dx * math.cos(math.radians(yaw))
            oz = z - dx * math.sin(math.radians(yaw))
            obox(ox, 1.4, oz, 0.12, 2.0, 0.12, yaw, "wood")


def hay(x, z):
    box(x - 1.0, 0, z - 0.7, x + 1.0, 1.2, z + 0.7, "hay")


trunks = []       # (x, z) of every tree, to keep spawns clear of them


def tree(x, z, rng):
    trunks.append((x, z))
    h = rng.uniform(5.0, 7.5)
    with group():
        box(x - 0.35, 0, z - 0.35, x + 0.35, h, z + 0.35, "trunk")
        s = rng.uniform(3.0, 4.6)
        box(x - s / 2, h - 1.0, z - s / 2, x + s / 2, h + s * 0.7, z + s / 2, "leaves", solid=False)


def bush(x, z, rng):
    s = rng.uniform(1.4, 2.2)
    box(x - s / 2, 0, z - s / 2, x + s / 2, rng.uniform(1.0, 1.5), z + s / 2, "leaves")


def car_stack(x, z, yaw, n, rng):
    """Wrecked cars stacked n high (junkyard walls)."""
    with group():
        for k in range(n):
            obox(x, 0.55 + k * 1.1, z, 1.9, 1.1, 4.2, yaw + rng.uniform(-6, 6), ("car_a", "car_b", "rust")[rng.randrange(3)])


def truck(x, z, yaw):
    """An army truck (checkpoint)."""
    with group():
        obox(x, 1.4, z, 2.5, 2.8, 7.0, yaw, "army")
        fx, fz = x + 4.3 * math.sin(math.radians(yaw)), z + 4.3 * math.cos(math.radians(yaw))
        obox(fx, 1.1, fz, 2.4, 2.2, 1.8, yaw, "army")


def sandbags(x, z, yaw, length=4.0):
    obox(x, 0.55, z, 0.7, 1.1, length, yaw, "sandbag")


# ---------------------------------------------------------------------------------------------- clutter (0.11.4)
# War-torn junk in the empty grass (owner, 0.11.4): rocks, rubble, wrecks, tank traps, craters. Gray boxes for
# now; real models come later. Placed by `clutter()` in the dead areas only, away from buildings, roads and spawns.
def rock(x, z, rng):
    for _ in range(rng.randint(1, 3)):
        w, h, d = rng.uniform(1.4, 3.6), rng.uniform(0.8, 2.4), rng.uniform(1.4, 3.2)
        obox(x + rng.uniform(-1.5, 1.5), h / 2 - 0.1, z + rng.uniform(-1.2, 1.2), w, h, d, rng.uniform(0, 90), "stone")


def rubble(x, z, rng):
    """A pile of broken concrete with a chunk of wall still standing."""
    for _ in range(rng.randint(4, 7)):
        w, h, d = rng.uniform(0.6, 1.8), rng.uniform(0.3, 0.9), rng.uniform(0.6, 1.8)
        obox(x + rng.uniform(-2.5, 2.5), h / 2, z + rng.uniform(-2.5, 2.5), w, h, d, rng.uniform(0, 90),
             rng.choice(("concrete", "concrete", "wall", "slab")))
    obox(x + rng.uniform(-1, 1), 1.1, z + rng.uniform(-1, 1), rng.uniform(2.5, 4.0), 2.2, 0.3, rng.uniform(0, 180), "wall")


def wreck(x, z, rng):
    """A burnt-out car, sometimes on its side."""
    yaw = rng.uniform(0, 180)
    with group():
        if rng.random() < 0.3:
            obox(x, 0.95, z, 1.1, 1.9, 4.2, yaw, "rust", pitch=0.0)
        else:
            obox(x, 0.5, z, 1.9, 1.0, 4.2, yaw, "rust")
            obox(x, 1.25, z, 1.7, 0.5, 2.0, yaw + rng.uniform(-4, 4), "metal")


def wrecked_truck(x, z, rng):
    yaw = rng.uniform(0, 180)
    with group():
        obox(x, 1.3, z, 2.5, 2.6, 6.5, yaw, "rust")
        fx, fz = x + 4.0 * math.sin(math.radians(yaw)), z + 4.0 * math.cos(math.radians(yaw))
        obox(fx, 0.9, fz, 2.4, 1.8, 1.8, yaw + rng.uniform(-10, 10), "army", pitch=rng.uniform(-8, 0))


def tank_traps(x, z, rng):
    """A short row of steel hedgehogs."""
    yaw = rng.uniform(0, 180)
    for k in range(rng.randint(2, 4)):
        tx = x + (k - 1.5) * 3.0 * math.cos(math.radians(yaw))
        tz = z - (k - 1.5) * 3.0 * math.sin(math.radians(yaw))
        with group():
            for a in (0, 60, 120):
                obox(tx, 0.7, tz, 0.25, 0.25, 2.0, yaw + a, "metal", pitch=35.0)


craters = []      # (x, z, ring radius): shell holes dug into the ground (0.11.17)


def crater(x, z, rng):
    """A shell crater: a ring of dirt mounds round a hole in the ground (you can crouch in it)."""
    r = rng.uniform(2.5, 3.5)
    craters.append((x, z, r))
    for k in range(8):
        a = k * 45 + rng.uniform(-10, 10)
        obox(x + r * math.sin(math.radians(a)), 0.3, z + r * math.cos(math.radians(a)), 2.4, 0.6, 1.0, a + 90, "dirt")


def barrels(x, z, rng):
    for _ in range(rng.randint(2, 4)):
        obox(x + rng.uniform(-1.5, 1.5), 0.5, z + rng.uniform(-1.5, 1.5), 0.6, 1.0, 0.6, rng.uniform(0, 90),
             rng.choice(("rust", "army", "metal")))
    if rng.random() < 0.5:
        obox(x + 2.0, 0.3, z, 0.6, 0.6, 1.0, 90, "rust", pitch=90.0)   # one knocked over


CLUTTER = [(rock, 5), (rubble, 3), (wreck, 3), (wrecked_truck, 1), (tank_traps, 2), (crater, 2), (barrels, 2)]


def _clear_of_map(x, z):
    """True if (x, z) is open grass: off roads, rail, water, yards and away from buildings, props and spawns."""
    if not (8 < x < M - 8 and 8 < z < M - 8) or abs(z - 210.0) < 8:   # the railway
        return False
    if any(t[0] - 6 < x < t[2] + 6 and t[1] - 6 < z < t[3] + 6 for t in TRENCHES):
        return False
    for points, width in roads + water:
        for a, b in zip(points, points[1:]):
            if _seg_rect_gap(a, b, (x - 0.1, z - 0.1, x + 0.1, z + 0.1)) < width / 2 + 6:
                return False
    for x0, z0, x1, z1 in yards:
        if x0 - 6 < x < x1 + 6 and z0 - 6 < z < z1 + 6:
            return False
    for _, x0, z0, x1, z1 in footprints + areas:
        if x0 - 12 < x < x1 + 12 and z0 - 12 < z < z1 + 12:
            return False
    if any(math.hypot(x - tx, z - tz) < 5 for tx, tz in trunks):
        return False
    for _, sx, sz in player_spawns + enemy_spawns:
        if math.hypot(x - sx, z - sz) < 10:
            return False
    for _, _, ex, ez in extracts:
        if math.hypot(x - ex, z - ez) < 14:
            return False
    for l in loot:
        if math.hypot(x - l[2], z - l[4]) < 8:
            return False
    for b in boxes:   # flat ground patches: the farm field, car parks, sports field...
        if b[4] <= 0.06 and max(b[3], b[5]) > 8 and abs(x - (b[0] + M / 2)) < b[3] / 2 + 4 and abs(z - (b[2] + M / 2)) < b[5] / 2 + 4:
            return False
    for b in boxes:   # props already placed (stands, campsite, power poles, fences...)
        if b[4] > 0.2 and max(b[3], b[5]) < 30 and math.hypot(x - (b[0] + M / 2), z - (b[2] + M / 2)) < max(b[3], b[5]) / 2 + 6:
            return False
    return True


def bits(x, z, rng):
    """Small junk scattered round a clutter spot (planks, scrap, stones)."""
    for _ in range(rng.randint(2, 4)):
        a, r = rng.uniform(0, 360), rng.uniform(3.5, 6.0)
        obox(x + r * math.sin(math.radians(a)), 0.12, z + r * math.cos(math.radians(a)), rng.uniform(0.3, 0.8), 0.25,
             rng.uniform(0.6, 2.2), rng.uniform(0, 180), rng.choice(("wood", "metal", "stone", "rust")), solid=False)


def clutter(spacing=18.0):
    rng = random.Random(4100)
    placed = []
    kinds = [k for k, w in CLUTTER for _ in range(w)]
    for _ in range(4000):
        x, z = rng.uniform(0, M), rng.uniform(0, M)
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in placed) or not _clear_of_map(x, z):
            continue
        placed.append((x, z))
    for x, z in placed:
        kind = rng.choice(kinds)
        kind(x, z, rng)
        bits(x, z, rng)
        if kind is not crater:   # (wrecks and rubble get a level spot on the hills; craters are dug into them)
            clutter_spots.append((x, z))
    return placed


def trench():
    """Floor, earth walls and two ramps for TRENCHES, with sandbags along parts of the north lip."""
    floor = -TRENCH_DEPTH
    for x0, z0, x1, z1 in TRENCHES:
        box(x0, floor - 0.3, z0, x1, floor, z1, "earth")
    inside = lambda x, z: any(t[0] < x < t[2] and t[1] < z < t[3] for t in TRENCHES)
    for x0, z0, x1, z1 in TRENCHES:   # walls round the outline only (not where two pieces meet)
        for horizontal, fixed, a0, a1, out in ((True, z0, x0, x1, -1), (True, z1, x0, x1, 1),
                                                (False, x0, z0, z1, -1), (False, x1, z0, z1, 1)):
            cuts = sorted({a0, a1} | {v for t in TRENCHES for v in ((t[0], t[2]) if horizontal else (t[1], t[3]))
                                     if a0 < v < a1})
            for c0, c1 in zip(cuts, cuts[1:]):
                m = (c0 + c1) / 2
                if inside(*((m, fixed + out * 0.05) if horizontal else (fixed + out * 0.05, m))):
                    continue
                # (a little inside the hole, so the wall hides the ground's cut edge instead of flickering with it)
                w0, w1 = sorted((fixed - out * 0.05, fixed + out * 0.25))
                if horizontal:
                    box(c0, floor - 0.3, w0, c1, 0.0, w1, "earth")
                else:
                    box(w0, floor - 0.3, c0, w1, 0.0, c1, "earth")
    for (x0, z0, x1, z1), (hi_x, lo_x) in ((TRENCHES[0], (126.0, 130.5)), (TRENCHES[-1], (176.0, 171.5))):
        run = abs(lo_x - hi_x)
        obox((hi_x + lo_x) / 2, floor / 2 - 0.1, (z0 + z1) / 2, z1 - z0, 0.2, math.hypot(run, TRENCH_DEPTH),
             90.0 if lo_x > hi_x else -90.0, "earth", pitch=math.degrees(math.atan2(TRENCH_DEPTH, run)))
    for x0, x1, z in ((131, 139, 171.6), (143, 151, 177.2), (160, 168, 169.6)):   # sandbags on the north lip
        sandbags((x0 + x1) / 2, z, 90, length=x1 - x0)


def dead_tree(x, z, rng):
    """A burnt, bare tree: a dark trunk (sometimes snapped off) with a few broken branches, or just a stump."""
    trunks.append((x, z))
    kind = rng.random()
    if kind < 0.25:
        box(x - 0.4, 0, z - 0.4, x + 0.4, rng.uniform(0.6, 1.2), z + 0.4, "deadwood")
        return
    h = rng.uniform(2.5, 4.0) if kind < 0.5 else rng.uniform(4.5, 7.0)
    with group():
        box(x - 0.3, 0, z - 0.3, x + 0.3, h, z + 0.3, "deadwood")
        for _ in range(rng.randint(1, 3) if kind >= 0.5 else 0):
            y = rng.uniform(h * 0.5, h * 0.9)
            a = rng.uniform(0, 360)
            ln = rng.uniform(1.2, 2.4)
            obox(x + math.sin(math.radians(a)) * ln / 2, y + 0.3, z + math.cos(math.radians(a)) * ln / 2, 0.18, 0.18, ln,
                 a, "deadwood", solid=False, pitch=-rng.uniform(15, 40))


def scatter_trees(spots, spacing=34.0):
    """A few lone trees and pairs in the open grass (owner, 0.11.7; fewer and mostly dead in 0.11.8), clear of the
    clutter `spots`."""
    rng = random.Random(4200)
    placed = []
    for _ in range(4000):
        x, z = rng.uniform(0, M), rng.uniform(0, M)
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in placed) or \
                any(math.hypot(x - cx, z - cz) < 10 for cx, cz in spots) or not _clear_of_map(x, z):
            continue
        placed.append((x, z))
    for x, z in placed:
        n = rng.choice((1, 1, 1, 2))
        dead = rng.random() < 0.6   # most trees out here are dead or burnt (owner, 0.11.8)
        for k in range(n):
            a = rng.uniform(0, 360)
            r = 0.0 if k == 0 else rng.uniform(3.5, 5.0)
            (dead_tree if dead else tree)(x + r * math.sin(math.radians(a)), z + r * math.cos(math.radians(a)), rng)
        if not dead:
            if rng.random() < 0.4:
                bush(x + rng.uniform(-4, 4), z + rng.uniform(-4, 4), rng)
            woods.append((x, z, 2.0 + 2.0 * (n > 1)))
    return placed


def power_line(curve, side, width, every=34.0, skip_from=0.0):
    """Wooden poles beside a road (on `side`: +1 right of travel, -1 left) with the wire between them. Poles skip
    spots near buildings and other roads."""
    poles = []
    dist, next_at = 0.0, skip_from + every / 2
    for (ax, az), (bx, bz) in zip(curve, curve[1:]):
        seg = math.hypot(bx - ax, bz - az)
        while seg > 0 and next_at <= dist + seg:
            t = (next_at - dist) / seg
            tx, tz = (bx - ax) / seg, (bz - az) / seg
            px = ax + (bx - ax) * t - tz * side * (width / 2 + 2.0)
            pz = az + (bz - az) * t + tx * side * (width / 2 + 2.0)
            next_at += every
            if not (2 < px < M - 2 and 2 < pz < M - 2):
                continue
            if any(x0 - 2 < px < x1 + 2 and z0 - 2 < pz < z1 + 2 for _, x0, z0, x1, z1 in footprints + areas):
                continue
            if math.hypot(px - 263.0, pz - 285.0) < 20:   # the checkpoint
                continue
            if any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 1.0 for pts, w in roads for a, b in zip(pts, pts[1:])):
                continue
            poles.append((px, pz))
        dist += seg
    for px, pz in poles:
        with group():
            box(px - 0.15, 0, pz - 0.15, px + 0.15, 8.0, pz + 0.15, "wood")
            box(px - 0.9, 7.4, pz - 0.08, px + 0.9, 7.55, pz + 0.08, "wood", solid=False)
    for (ax, az), (bx, bz) in zip(poles, poles[1:]):
        length = math.hypot(bx - ax, bz - az)
        if length < 60:   # (a long gap means poles were skipped round a junction: no wire across it)
            with anchored(("wire", ax, az, bx, bz)):
                obox((ax + bx) / 2, 7.3, (az + bz) / 2, 0.05, 0.05, length, math.degrees(math.atan2(bx - ax, bz - az)),
                     "metal", solid=False)


def fence(points, h=1.1):
    """A low wooden fence along a polyline, with a gap every so often (low cover, jumpable later)."""
    strip(points, 0.15, "wood", y=0.0, h=h, solid=True)


# ---------------------------------------------------------------------------------------------- hills (0.11.17)
# The ground rolls (owner, 0.11.17: "the ground is all flat, there should be hills and valleys"). How it's made:
#  1. `base_height`: a broad rise north of town plus long, gentle waves everywhere (so roads never get steep).
#  2. Roads and the creek flatten the ground across them (the creek sits in a valley it carves).
#  3. HILLS: real hills and hollows away from the roads (they fade out 4-20 m from a road or the creek).
#  4. Flat pads under every building, yard and area, at the average ground round them (pads close together share
#     one height, so neighbours line up; a house on a hillside is dug in on one side); the railway is level at 0 all
#     the way. Roads level out across again where a pad's slope reaches them. Then small level spots for spawns,
#     extracts and outside loot.
#  5. Shell craters dig small holes.
# The ground is a height grid every TERRAIN_STEP m (plus the trench and bunker-hole edges, which are holes in it);
# `BoxMap` turns it into a mesh. Everything built sits on it: boxes are moved up by the ground under them (see
# `anchors`), road and fence pieces tilt with it.
TERRAIN_STEP = 2.5
# (map x, map z, radius, height): broad, gentle rises and dips that roads and buildings follow.
BASE_HILLS = [(62, 22, 75, 6.0), (300, 150, 80, 2.0), (175, 330, 70, 1.5), (40, 300, 70, -1.0)]
# (direction degrees, wavelength m, height m, phase): long rolling waves over everything.
WAVES = [(20, 150, 1.0, 0.3), (110, 120, 0.8, 1.9), (65, 85, 0.45, 4.0), (160, 70, 0.3, 2.2)]
# (map x, map z, radius, height): hills (+) and hollows (-) in the open ground.
HILLS = [
    (305, 150, 40, 9.0),    # the east woods sit on a big hill
    (334, 108, 20, 4.0),
    (235, 150, 22, 6.0),    # a rise east of Station Road
    (252, 186, 18, 4.0),
    (150, 194, 22, 4.5),    # the field between town and the railway
    (106, 180, 16, 3.5),
    (176, 162, 14, -2.5),
    (12, 300, 28, 7.0),     # west of the creek
    (98, 302, 26, 7.0),     # east of the creek (cabin 1, the campsite)
    (75, 232, 18, 4.0),
    (160, 246, 20, 5.0),    # the field south of the railway
    (120, 266, 18, -4.0),   # a hollow by the hunting stand
    (192, 300, 22, 5.0),    # between the old houses
    (132, 326, 20, 5.0),
    (250, 316, 20, 4.0),
    (336, 222, 22, 5.0),    # the east edge behind the depot
    (276, 198, 16, -3.5),   # a dip between the east woods and the depot
    (220, 230, 14, -2.5),
    (20, 192, 16, 3.5),     # west of the school
    (125, 10, 14, 3.0),
    (285, 112, 16, -2.5),
]
CRATER_DEPTH = 0.9
# The creek (0.11.20): a channel this deep in the middle of its valley floor, full depth out to CREEK_BED m from the
# middle line and back up to the floor at CREEK_BANK m; the water sits WATER_DROP m below the floor (so about 0.55 m
# deep in the middle: wading, not swimming). It starts just south of the railway (the rail stays level).
CREEK_DEPTH = 0.9
CREEK_BED = 1.5
CREEK_BANK = 4.5
WATER_DROP = 0.35
WATER_START = 2   # the first creek point with water (the ones before run under the railway at the map edge)
# Ground covers (building ground floors, yards, car parks: flat, looks-only boxes built from height 0) end up this far
# above the ground, so the two never flicker against each other from far away (0.11.21; they were 3 cm up). The
# ground under them isn't drawn where they cover it completely (`terrain_hidden`).
# A cover on top of a bigger one (a house floor on the farmyard) or on a road sits COVER_STEP higher for each, so
# no two are level with each other either (0.12.5).
COVER_TOP = 0.07
COVER_STEP = 0.05
# The railway's top (its sleepers stick up above it); road pieces that cross it are lifted over it.
RAIL_TOP = 0.12
RAIL_Z = 210.0
HILL_CLEAR = 20.0   # hills reach full height this far from a road or the creek (and fade out within 4 m of it)

# Extra flat pads (map x0, z0, x1, z1) for things that stand outside a building's footprint.
EXTRA_PADS = [
    (61.5, 98.5, 72.5, 114.5),    # town gas station forecourt
    (295.0, 334.0, 331.0, 343.0),  # old gas station canopy
    (196.0, 204.0, 246.0, 208.0),  # station platform
    (232.0, 214.0, 292.0, 231.0),  # depot sidings
    (124.0, 168.0, 178.0, 182.0),  # the trench
    (249.0, 271.0, 277.0, 299.0),  # the checkpoint
    (58.0, 260.0, 74.0, 274.0),    # campsite
]


def _bumps(hills, x, z):
    return sum(a * math.exp(-((x - cx) ** 2 + (z - cz) ** 2) / (r * r)) for cx, cz, r, a in hills)


def base_height(x, z):
    h = _bumps(BASE_HILLS, x, z)
    for deg, length, a, phase in WAVES:
        d = x * math.cos(math.radians(deg)) + z * math.sin(math.radians(deg))
        h += a * math.sin(2 * math.pi * d / length + phase)
    return h


def _smoothstep(a, b, v):
    if v <= a:
        return 0.0
    if v >= b:
        return 1.0
    t = (v - a) / (b - a)
    return t * t * (3 - 2 * t)


def _rect_gap(x, z, r):
    dx = max(r[0] - x, 0.0, x - r[2])
    dz = max(r[1] - z, 0.0, z - r[3])
    return math.hypot(dx, dz)


def _nearest_on(points, x, z):
    """(distance, nearest point) from (x, z) to a polyline."""
    best = (float("inf"), points[0])
    for (ax, az), (bx, bz) in zip(points, points[1:]):
        dx, dz = bx - ax, bz - az
        ln2 = dx * dx + dz * dz
        t = 0.0 if ln2 == 0 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / ln2))
        px, pz = ax + dx * t, az + dz * t
        d = math.hypot(x - px, z - pz)
        if d < best[0]:
            best = (d, (px, pz))
    return best


class Terrain:
    def __init__(self, holes):
        xs = {round(k * TERRAIN_STEP, 3) for k in range(int(M / TERRAIN_STEP) + 1)}
        zs = set(xs)
        for x0, z0, x1, z1 in holes:
            xs |= {x0, x1}
            zs |= {z0, z1}
        self.xs, self.zs = sorted(xs), sorted(zs)
        self.lines = []   # (points, width, creek depth, bounding box)
        for points, width, carve in line_features():
            reach = width / 2 + HILL_CLEAR + 1.0   # (far enough to know how close the hills may come)
            self.lines.append((points, width, carve, (min(p[0] for p in points) - reach, min(p[1] for p in points) - reach,
                                                      max(p[0] for p in points) + reach, max(p[1] for p in points) + reach)))
        self._pads()
        self.h = [[self._height(x, z) for x in self.xs] for z in self.zs]
        self._ease()
        self.hole_cells = []
        for j in range(len(self.zs) - 1):
            for i in range(len(self.xs) - 1):
                cx, cz = (self.xs[i] + self.xs[i + 1]) / 2, (self.zs[j] + self.zs[j + 1]) / 2
                if any(h[0] < cx < h[2] and h[1] < cz < h[3] for h in holes):
                    self.hole_cells.append(j * (len(self.xs) - 1) + i)

    # --- pads
    def _pads(self):
        """Flat pads: cores (x0, z0, x1, z1, already grown by their margin) with a falloff round each. Big pads
        close together are joined into clusters that share one height; small pads (spawns, extracts, outside loot)
        then take the height the ground has there."""
        big, small = [], []   # [core rect, falloff, fixed height or None]

        def add(into, r, margin, fall, fixed=None):
            into.append(((r[0] - margin, r[1] - margin, r[2] + margin, r[3] + margin), fall, fixed))
        for _, x0, z0, x1, z1 in footprints:
            add(big, (x0, z0, x1, z1), 3.0, 12.0)
        for r in [a[1:] for a in areas] + yards + EXTRA_PADS:   # (big yards blend out further: the farm is 100 m)
            add(big, r, 2.0, max(12.0, 0.25 * min(r[2] - r[0], r[3] - r[1])))
        for sx, sz in stand_spots:
            add(big, (sx - 1.5, sz - 1.5, sx + 1.5, sz + 7.0), 1.0, 8.0)
        add(big, (-20.0, 207.0, M + 20.0, 213.0), 1.0, 22.0, fixed=0.0)   # the railway: level all the way
        for _, x, z in player_spawns:
            add(small, (x, z, x, z), 3.5, 8.0)
        for _, x, z in enemy_spawns:
            add(small, (x, z, x, z), 3.0, 6.0)
        for _, _, x, z in extracts:
            add(small, (x, z, x, z), 6.0, 8.0)
        for l in loot:
            if not any(x0 <= l[2] <= x1 and z0 <= l[4] <= z1 for _, x0, z0, x1, z1 in footprints):
                add(small, (l[2], l[4], l[2], l[4]), 1.5, 5.0)
        for x, z in clutter_spots:   # (not right next to a building's pad: the two levels would make a bank)
            if all(_rect_gap(x, z, r) > 12.0 for r, _, _ in big):
                add(small, (x, z, x, z), 3.0, 6.0)
        # clusters: big pads whose cores are close share a height (so there's never a cliff between two of them)
        parent = list(range(len(big)))
        gap = 4.0

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a
        for a in range(len(big)):
            ra = big[a][0]
            for b in range(a + 1, len(big)):
                rb = big[b][0]
                if ra[0] <= rb[2] + gap and rb[0] <= ra[2] + gap and ra[1] <= rb[3] + gap and rb[1] <= ra[3] + gap:
                    parent[find(a)] = find(b)
        groups = {}
        for k in range(len(big)):
            groups.setdefault(find(k), []).append(big[k])
        self.clusters = []
        for members in groups.values():
            fixed = [m[2] for m in members if m[2] is not None]
            if fixed:
                target = fixed[0]
            else:   # the average ground (after roads) over the pads and 8 m round them, so neighbours come out alike
                total, n = 0.0, 0
                for (x0, z0, x1, z1), _, _ in members:
                    for xx in _samples(x0 - 8, x1 + 8, 3.0):
                        for zz in _samples(z0 - 8, z1 + 8, 3.0):
                            total += self._hills(xx, zz)[0]
                            n += 1
                target = total / n
            self.clusters.append(self._cluster(members, target))
        self.small = []
        for core, fall, _ in small:
            x, z = (core[0] + core[2]) / 2, (core[1] + core[3]) / 2
            self.small.append(self._cluster([(core, fall, None)], self._big(x, z)[0]))

    @staticmethod
    def _cluster(members, target):
        reach = max(max(m[1] for m in members), HILL_CLEAR + 1.0)
        bound = (min(m[0][0] for m in members) - reach, min(m[0][1] for m in members) - reach,
                 max(m[0][2] for m in members) + reach, max(m[0][3] for m in members) + reach)
        return members, target, bound

    def pad_at(self, x, z):
        """The height of the flat pad (x, z) stands on, or None."""
        for members, target, bound in self.clusters + self.small:
            if bound[0] <= x <= bound[2] and bound[1] <= z <= bound[3]:
                for r, _, _ in members:
                    if r[0] <= x <= r[2] and r[1] <= z <= r[3]:
                        return target
        return None

    # --- the height field
    def _lines(self, x, z):
        """The base ground with roads and the creek flattened across, and the roads near (x, z): (distance, nearest
        point on the road, width)."""
        h = base_height(x, z)
        near = []
        for points, width, carve, bound in self.lines:
            if not (bound[0] <= x <= bound[2] and bound[1] <= z <= bound[3]):
                continue
            d, (px, pz) = _nearest_on(points, x, z)
            near.append((d, px, pz, width, carve))
            core, fall = width / 2 + 1.5, (22.0 if carve else 10.0)
            w = 1.0 - _smoothstep(core, core + fall, d)
            if w <= 0:
                continue
            t = base_height(px, pz)
            if carve:   # the creek's valley deepens away from the railway
                t -= carve * _smoothstep(4.0, 40.0, abs(pz - 210.0))
            h += (t - h) * w
        return h, near

    @staticmethod
    def _blend(clusters, x, z, h, keep):
        """Pulls h toward the pads near (x, z): exactly level on a pad, blending out over its falloff (several
        nearby pads blend by distance). `keep` (0-1) protects roads. Returns (height, distance to the nearest pad)."""
        num = den = most = 0.0
        nearest = float("inf")
        for members, target, bound in clusters:
            if not (bound[0] <= x <= bound[2] and bound[1] <= z <= bound[3]):
                continue
            d = min(_rect_gap(x, z, r) for r, _, _ in members)
            nearest = min(nearest, d)
            if d == 0.0:
                return target + (h - target) * keep, 0.0
            f = max(1.0 - _smoothstep(0.0, fall, _rect_gap(x, z, r)) for r, fall, _ in members)
            if f <= 0:
                continue
            s = f / (d * d)
            num += s * target
            den += s
            most = max(most, f)
        if den > 0:
            h += (num / den - h) * most * (1.0 - keep)
        return h, nearest

    def _hills(self, x, z):
        """The ground before pads: base, roads and creek, and the hills (they fade out 4-20 m from a road or the
        creek, so those stay level across)."""
        h, near = self._lines(x, z)
        clear = min([d - width / 2 for d, _, _, width, _ in near], default=float("inf"))
        return h + _bumps(HILLS, x, z) * _smoothstep(4.0, HILL_CLEAR, clear), near

    def _padded(self, x, z):
        h, near = self._hills(x, z)
        h, pad = self._blend(self.clusters, x, z, h, 0.0)
        return h, near, pad

    def _big(self, x, z):
        """After the big pads, the roads level out across again (at the height the ground has on their middle line),
        so a pad next to a road never leaves it tilted. Returns (height, how much it's on a road)."""
        h, near, _ = self._padded(x, z)
        on_road = 0.0
        for d, px, pz, width, carve in near:
            if carve:
                continue
            w = 1.0 - _smoothstep(width / 2 + 0.5, width / 2 + 3.0, d)
            if w > 0:
                h += (self._padded(px, pz)[0] - h) * w
            on_road = max(on_road, 1.0 - _smoothstep(width / 2 + 0.3, width / 2 + 1.3, d))
        return h, on_road

    def _surface(self, x, z):
        """The ground before the creek's channel is dug."""
        h, on_road = self._big(x, z)
        # (small pads never move a big pad's ground: a spawn by a house would lift the house floor's ground)
        on_big = any(b[0] <= x <= b[2] and b[1] <= z <= b[3] and any(r[0] <= x <= r[2] and r[1] <= z <= r[3]
                                                                    for r, _, _ in m) for m, _, b in self.clusters)
        h = self._blend(self.small, x, z, h, 1.0 if on_big else on_road)[0]
        for cx, cz, r in craters:
            d = math.hypot(x - cx, z - cz)
            if d < r + 1.0:
                h -= CRATER_DEPTH * (1.0 - _smoothstep(0.0, r + 1.0, d))
        return h

    def _height(self, x, z):
        h = self._surface(x, z)
        for points, width, carve, bound in self.lines:
            if carve and bound[0] <= x <= bound[2] and bound[1] <= z <= bound[3]:
                d, (_, pz) = _nearest_on(points, x, z)
                if d < CREEK_BANK:
                    h -= CREEK_DEPTH * (1.0 - _smoothstep(CREEK_BED, CREEK_BANK, d)) * _smoothstep(212.5, 216.0, pz)
        return h

    def water_level(self, x, z):
        """The creek's water surface at a point on its middle line."""
        return self._surface(x, z) - WATER_DROP

    def _ease(self, limit=0.42, rounds=300):
        """Eases the ground wherever it's steeper than `limit` (about 23 degrees) between grid points, leaving pads,
        roads and the map edge alone: walkable everywhere (the AI's paths take 40 degrees), no sudden banks. Works on
        the regular grid; the extra lines (hole edges) then take their height from it, except on pads."""
        on_x = [abs(x / TERRAIN_STEP - round(x / TERRAIN_STEP)) < 1e-6 for x in self.xs]
        on_z = [abs(z / TERRAIN_STEP - round(z / TERRAIN_STEP)) < 1e-6 for z in self.zs]
        ri = [i for i in range(len(self.xs)) if on_x[i]]
        rj = [j for j in range(len(self.zs)) if on_z[j]]
        fixed = {}
        for j, z in enumerate(self.zs):
            for i, x in enumerate(self.xs):
                fixed[j, i] = i in (0, len(self.xs) - 1) or j in (0, len(self.zs) - 1) or \
                    self.pad_at(x, z) is not None or \
                    any(_nearest_on(pts, x, z)[0] < max(w / 2 + 1.5, CREEK_BANK if c else 0.0) for pts, w, c, b in self.lines
                        if b[0] <= x <= b[2] and b[1] <= z <= b[3])
        h = self.h
        step = TERRAIN_STEP
        for _ in range(rounds):
            changed = False
            for jj in range(1, len(rj) - 1):
                j0, j, j1 = rj[jj - 1], rj[jj], rj[jj + 1]
                for ii in range(1, len(ri) - 1):
                    i0, i, i1 = ri[ii - 1], ri[ii], ri[ii + 1]
                    if fixed[j, i]:
                        continue
                    # keep within `limit` of every neighbour (the slope then spreads out from the pads and roads)
                    around = (h[j][i0], h[j][i1], h[j0][i], h[j1][i])
                    lo, hi = max(around) - limit * step, min(around) + limit * step
                    here = h[j][i]
                    want = (lo + hi) / 2 if lo > hi else min(max(here, lo), hi)
                    if abs(want - here) > 0.01:
                        h[j][i] = want
                        changed = True
            if not changed:
                break
        # the extra lines follow the regular grid round them (pads and roads keep their own, exact height)
        for j in range(len(self.zs)):
            for i in range(len(self.xs)):
                if (on_x[i] and on_z[j]) or fixed[j, i]:
                    continue
                i0 = max(k for k in ri if self.xs[k] <= self.xs[i]) if not on_x[i] else i
                i1 = min(k for k in ri if self.xs[k] >= self.xs[i]) if not on_x[i] else i
                j0 = max(k for k in rj if self.zs[k] <= self.zs[j]) if not on_z[j] else j
                j1 = min(k for k in rj if self.zs[k] >= self.zs[j]) if not on_z[j] else j
                u = 0.0 if i1 == i0 else (self.xs[i] - self.xs[i0]) / (self.xs[i1] - self.xs[i0])
                v = 0.0 if j1 == j0 else (self.zs[j] - self.zs[j0]) / (self.zs[j1] - self.zs[j0])
                h[j][i] = (h[j0][i0] * (1 - u) * (1 - v) + h[j0][i1] * u * (1 - v) + h[j1][i0] * (1 - u) * v
                           + h[j1][i1] * u * v)

    def hide_under(self, covers):
        """Grid cells completely under a ground cover (and below it) aren't drawn."""
        self.hidden_cells = []
        for j in range(len(self.zs) - 1):
            for i in range(len(self.xs) - 1):
                x0, x1, z0, z1 = self.xs[i], self.xs[i + 1], self.zs[j], self.zs[j + 1]
                top = max(self.h[j][i], self.h[j][i + 1], self.h[j + 1][i], self.h[j + 1][i + 1])
                if any(c[0] <= x0 and x1 <= c[2] and c[1] <= z0 and z1 <= c[3] and top < c[4] - 0.02 for c in covers):
                    self.hidden_cells.append(j * (len(self.xs) - 1) + i)

    def at(self, x, z):
        """The ground height at (x, z) exactly as the mesh has it (each grid cell is two triangles, split from its
        north-west to its south-east corner)."""
        x = max(0.0, min(M, x))
        z = max(0.0, min(M, z))
        i = max(0, min(len(self.xs) - 2, bisect.bisect_right(self.xs, x) - 1))
        j = max(0, min(len(self.zs) - 2, bisect.bisect_right(self.zs, z) - 1))
        u = (x - self.xs[i]) / (self.xs[i + 1] - self.xs[i])
        v = (z - self.zs[j]) / (self.zs[j + 1] - self.zs[j])
        h00, h10, h01, h11 = self.h[j][i], self.h[j][i + 1], self.h[j + 1][i], self.h[j + 1][i + 1]
        if u >= v:
            return h00 + u * (h10 - h00) + v * (h11 - h10)
        return h00 + v * (h01 - h00) + u * (h11 - h01)

    def lift(self, x, z):
        """How far something standing at (x, z) moves up: its pad, or the ground there."""
        p = self.pad_at(x, z)
        return p if p is not None else self.at(x, z)


def _samples(a, b, step=2.5):
    n = max(1, int((b - a) / step))
    return [a + (b - a) * (k + 0.5) / n for k in range(n)]


stand_spots = []    # hunting stands (flat pads)
clutter_spots = []  # wrecks, rubble, rocks... (small level spots)


def line_features():
    """(points, width, creek valley depth or 0) of the roads and the creek."""
    return [(pts, w, 0.0) for pts, w in roads] + [(pts, w, 2.2) for pts, w in water]


def _footprint(b):
    """Map-space corners of a box seen from above."""
    cx, cz = b[0] + M / 2, b[2] + M / 2
    c, s = math.cos(math.radians(b[6])), math.sin(math.radians(b[6]))
    hx, hz = b[3] / 2, b[5] / 2
    return [(cx + c * lx + s * lz, cz - s * lx + c * lz) for lx, lz in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]


def terrain():
    """Builds the hills, then moves every box, container, spawn and extract onto them."""
    global boxes, anchors
    keep = [k for k, a in enumerate(anchors) if a != "ground"]
    boxes, anchors = [boxes[k] for k in keep], [anchors[k] for k in keep]
    ter = Terrain([BUNKER_HOLE] + TRENCHES)

    def low(b):   # the lowest ground under a box that isn't on a pad (so it never floats)
        p = ter.pad_at(b[0] + M / 2, b[2] + M / 2)
        if p is not None:
            return p
        return min([ter.at(x, z) for x, z in _footprint(b)] + [ter.at(b[0] + M / 2, b[2] + M / 2)])
    group_lift = {}
    for b, a in zip(boxes, anchors):
        if isinstance(a, tuple) and a[0] == "g":
            group_lift[a] = min(group_lift.get(a, float("inf")), low(b))
    out = []
    covers = []

    def is_cover(b, a):
        return a is None and not b[9] and b[7] == 0 and abs(b[1] - b[4] / 2) < 1e-6 and b[4] <= 0.06 + 1e-6

    def bounds(b):
        fp = _footprint(b)
        return min(p[0] for p in fp), min(p[1] for p in fp), max(p[0] for p in fp), max(p[1] for p in fp)

    def overlap(r, q):
        return r[0] < q[2] and q[0] < r[2] and r[1] < q[3] and q[1] < r[3]
    cover_rects = [(bounds(b), b[3] * b[5]) for b, a in zip(boxes, anchors) if is_cover(b, a)]
    road_rects = [bounds(b) for b, a in zip(boxes, anchors) if isinstance(a, tuple) and a[0] == "seg" and b[8] == C["road"]]
    for b, a in zip(boxes, anchors):
        if is_cover(b, a):
            # a ground cover: COVER_TOP above the ground (a step higher for each bigger cover it's on, two on a road),
            # and deep enough underneath to cover a little dip
            r, area = bounds(b), b[3] * b[5]
            steps = sum(1 for q, qa in cover_rects if qa > area and overlap(r, q)) + 2 * any(overlap(r, q) for q in road_rects)
            top = COVER_TOP + COVER_STEP * steps
            b = (b[0], (top - 0.25) / 2, b[2], b[3], top + 0.25) + tuple(b[5:])
            out.append(_moved(b, low(b)))
            if b[6] % 90 == 0:
                hx, hz = (b[3], b[5]) if b[6] % 180 == 0 else (b[5], b[3])
                cx, cz = b[0] + M / 2, b[2] + M / 2
                covers.append((cx - hx / 2, cz - hz / 2, cx + hx / 2, cz + hz / 2, low(b) + top))
        elif a is None:
            out.append(_moved(b, low(b)))
        elif a[0] == "g":
            out.append(_moved(b, group_lift[a]))
        elif a[0] == "wire":
            _, ax, az, bx, bz = a
            ha, hb = ter.lift(ax, az), ter.lift(bx, bz)
            out.append(_tilted(b, ha, hb, math.hypot(bx - ax, bz - az)))
        else:   # a strip piece: split long ones so they bend with the ground; thicker underneath so they never float
            _, ax, az, bx, bz, width = a
            length = math.hypot(bx - ax, bz - az)
            n = max(1, int(math.ceil(length / 4.0))) if length > 6.0 else 1
            for k in range(n):
                t0, t1 = k / n, (k + 1) / n
                px0, pz0 = ax + (bx - ax) * t0, az + (bz - az) * t0
                px1, pz1 = ax + (bx - ax) * t1, az + (bz - az) * t1
                sub = list(b)
                sub[0], sub[2] = (px0 + px1) / 2 - M / 2, (pz0 + pz1) / 2 - M / 2
                sub[5] = length / n + width * 0.5
                sub[1] -= 0.15
                sub[4] += 0.3
                piece = _tilted(tuple(sub), ter.at(px0, pz0), ter.at(px1, pz1), length / n)
                if b[8] == C["road"] and min(pz0, pz1) - width < RAIL_Z + 1.6 and max(pz0, pz1) + width > RAIL_Z - 1.6:
                    # a level crossing: the road goes over the rails (not level with them: it would flicker)
                    piece = _moved(piece, max(0.0, RAIL_TOP + COVER_STEP - (piece[1] + piece[4] / 2)))
                out.append(piece)
    boxes = out
    for x0, z0, x1, z1, top in covers:   # (no ground poking up through a floor or a yard: it flickers)
        poke = max(ter.at(x0 + (x1 - x0) * i / 12, z0 + (z1 - z0) * k / 12) for i in range(13) for k in range(13))
        assert poke < top - 0.03, f"the ground pokes through the cover at {x0:.0f}, {z0:.0f}"
    ter.hide_under(covers)
    # the edge of the map: a wall that follows the ground
    for k in range(35):
        a0, a1 = k * 10.0, k * 10.0 + 10.0
        for side in range(4):
            pts = [(a0 + t * 2.5, 0.0) for t in range(5)] if side == 0 else \
                  [(a0 + t * 2.5, M) for t in range(5)] if side == 1 else \
                  [(0.0, a0 + t * 2.5) for t in range(5)] if side == 2 else [(M, a0 + t * 2.5) for t in range(5)]
            hs = [ter.at(x, z) for x, z in pts]
            lo, hi = min(hs) - 1.0, max(hs) + 6.0
            if side == 0:
                box(a0, lo, -1, a1, hi, 0.5, "boundary")
            elif side == 1:
                box(a0, lo, M - 0.5, a1, hi, M + 1, "boundary")
            elif side == 2:
                box(-1, lo, a0, 0.5, hi, a1, "boundary")
            else:
                box(M - 0.5, lo, a0, M + 1, hi, a1, "boundary")
    # the bunker's ceiling (the ground above it is a thin mesh now): under the hall's floor, round the ramp hole
    hall_y = ter.pad_at(BUNKER_HOLE[0], BUNKER_HOLE[1])
    bx0, bz0, bx1, bz1 = BUNKER[0] - 0.3, BUNKER[1] - 0.3, BUNKER[2] + 0.3, BUNKER[3] + 0.3
    hx0, hz0, hx1, hz1 = BUNKER_HOLE
    for x0, z0, x1, z1 in ((bx0, bz0, hx0, bz1), (hx1, bz0, bx1, bz1), (hx0, bz0, hx1, hz0), (hx0, hz1, hx1, bz1)):
        box(x0, hall_y - 1.0, z0, x1, hall_y - 0.02, z1, "bunker")
    # containers, extracts, spawns and markers stand on the ground too
    for k, l in enumerate(loot):
        loot[k] = l[:3] + (l[3] + ter.lift(l[2], l[4]),) + l[4:]
    for name, _, x, z in extracts:
        ground_y["extract", name] = ter.lift(x, z)
    for name, x, z in player_spawns:
        ground_y["player", name] = ter.lift(x, z)
    for name, x, z in enemy_spawns:
        ground_y["enemy", name] = ter.lift(x, z)
    for k, m in enumerate(markers):
        markers[k] = m[:3] + (m[3] + ter.lift(m[2], m[4]),) + m[4:]
    terrain_report(ter)
    return ter


ground_y = {}


def _moved(b, dy):
    return (b[0], b[1] + dy) + tuple(b[2:])


def _tilted(b, ha, hb, length):
    """A box between two points (its local +z runs from the first to the second) tilted to their heights."""
    pitch = math.degrees(math.atan2(ha - hb, length)) if length > 0 else 0.0
    return (b[0], b[1] + (ha + hb) / 2) + tuple(b[2:7]) + (b[7] + pitch,) + tuple(b[8:])


def terrain_report(ter):
    hs = [h for row in ter.h for h in row]
    steep = 0.0
    for j in range(len(ter.zs) - 1):
        for i in range(len(ter.xs) - 1):
            dx = (ter.h[j][i + 1] - ter.h[j][i]) / (ter.xs[i + 1] - ter.xs[i])
            dz = (ter.h[j + 1][i] - ter.h[j][i]) / (ter.zs[j + 1] - ter.zs[j])
            steep = max(steep, math.degrees(math.atan(math.hypot(dx, dz))))
    grade = 0.0
    for points, _ in roads:
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            ln = math.hypot(bx - ax, bz - az)
            if ln > 0.5:
                grade = max(grade, abs(ter.at(ax, az) - ter.at(bx, bz)) / ln)
    print(f"hills: {min(hs):.1f} to {max(hs):.1f} m, steepest ground {steep:.0f} deg, steepest road {grade * 100:.0f}%, "
          f"{len(ter.xs)} x {len(ter.zs)} grid")
    assert steep < 38, "too steep for the AI's paths (40 degrees)"


# ================================================================================================ the map
def main():
    rng = random.Random(1234)

    # --- the bunker under the town hall: a ramp hole in the ground at the hall's west end
    bunker_hole = BUNKER_HOLE
    ground([bunker_hole] + TRENCHES)
    # (the wall round the map edge follows the hills: made in `terrain()`)

    # --- roads (from the agreed layout picture)
    main_st = road([(0, 82), (30, 80), (62, 86), (100, 98), (135, 96), (168, 104), (200, 104)], 9)              # Main Street
    county = road([(200, 104), (224, 98), (238, 80), (240, 44), (240, 0)], 8)                                   # county road (west of the farm)
    road([(62, 86), (48, 58), (58, 30), (95, 18), (130, 22)], 6)                                       # Hill Road
    road([(112, 100), (118, 70), (122, 40), (138, 8)], 6)                                              # Mill Lane
    old_road = road([(60, 88), (52, 130), (64, 170), (105, 196), (150, 214), (196, 240), (236, 270), (290, 300),
                     (350, 306)], 8)   # Old Road / the highway
    road([(186, 104), (194, 150), (214, 186)], 6)                                                      # Station Road
    road([(236, 270), (290, 258), (350, 252)], 6)                                                      # East Lane
    road([(196, 240), (180, 300), (160, 348)], 6)                                                      # South Lane
    # creek (shallow: walkable) and the rail bridge over it
    creek = bezier((0, 212), (60, 250), (40, 300), (110, 350), n=48)
    water.append((creek, 5.0))   # (the water itself is a surface `BoxMap` makes from `water_points`)

    # --- railway (west to east at y 210) with sidings to the depot
    RY = RAIL_Z
    box(0, 0, RY - 1.6, M, RAIL_TOP, RY + 1.6, "rail", solid=False)
    for x in range(2, int(M), 3):
        if any(_nearest_on(pts, x + 0.2, RY)[0] < w / 2 + 3.0 for pts, w in roads):
            continue   # (no sleepers poking through a level crossing)
        box(x, 0.0, RY - 1.4, x + 0.4, RAIL_TOP + 0.05, RY + 1.4, "wood", solid=False)   # (5 cm up: no flicker)
    for siding in ([(232, RY), (248, 220), (290, 220)], [(238, RY), (254, 228), (290, 228)]):
        strip(siding, 3.0, "rail", y=0.0, h=0.12)
    box(36, 0.0, RY - 3, 48, 0.25, RY + 3, "wood")   # rail bridge deck over the creek

    # ===================================================================== TOWN (top left)
    # town square: paving + lots of cover (owner): fountain, planters, stalls, parked cars, statue, kiosk
    box(88, 0.0, 108, 124, 0.06, 138, "pavement", solid=False)
    box(103, 0, 120, 109, 0.8, 126, "concrete")           # fountain basin
    box(105.4, 0.8, 122.4, 106.6, 2.6, 123.6, "concrete")  # fountain column
    for px, pz in ((93, 112), (119, 112), (93, 134), (119, 134), (98, 123), (114, 123)):
        planter(px, pz)
    stall(99, 115, 0); stall(106, 115, 0); stall(113, 115, 0)
    stall(100, 131, 0); stall(112, 131, 0)
    car(91, 124, 0, "car_b"); car(121, 126, 10, "car_a")
    box(104.5, 0, 133, 107.5, 1.2, 136, "concrete")        # statue plinth
    box(105.5, 1.2, 134, 106.5, 4.0, 135, "metal")         # statue
    box(118, 0, 118, 120.5, 2.6, 120.5, "car_b")           # newsstand kiosk

    # downtown
    hall = build(Building("TownHall", 82, 142, 50, 18, floors=2, colour="wall_hall", rooms=(4, 2), doors="NS",
                          roof=True), [
        ("locker", 1, 0, 1, "N", 0), ("crate", 2, 1, 1, "S", 0), ("locker", 3, 0, 1, "E", 0),
        ("crate", 1, 1, 0, "S", 0)])
    # the bunker (owner: best loot, behind a key door later): ramp down from the hall's west room
    bunker_floor = -4.5
    hx0, hz0, hx1, hz1 = bunker_hole
    run = hx1 - hx0
    obox((hx0 + hx1) / 2, bunker_floor / 2 - 0.1, (hz0 + hz1) / 2, hz1 - hz0 - 0.1, 0.2, math.hypot(run, bunker_floor),
         90.0, "concrete", pitch=math.degrees(math.atan2(-bunker_floor, run)))   # top (y 0) west, bottom east
    bx0, bz0, bx1, bz1 = BUNKER
    box(bx0, bunker_floor - 0.3, bz0, bx1, bunker_floor, bz1, "bunker")                 # floor
    box(bx0 - 0.3, bunker_floor, bz0 - 0.3, bx1 + 0.3, -1.0, bz0, "bunker")              # north wall
    box(bx0 - 0.3, bunker_floor, bz1, bx1 + 0.3, -1.0, bz1 + 0.3, "bunker")              # south wall
    box(bx0 - 0.3, bunker_floor, bz0, bx0, -1.0, bz1, "bunker")                          # west wall
    box(bx1, bunker_floor, bz0, bx1 + 0.3, -1.0, bz1, "bunker")                          # east wall
    # shaft wall north of the ramp; a rail round the hole upstairs (in the hall)
    box(hx0, bunker_floor, hz0 - 0.3, hx1, -1.0, hz0, "bunker")
    box(hx0, 0, hz0 - 0.1, hx1, 1.0, hz0, "metal")
    box(hx1, 0, hz0 - 0.1, hx1 + 0.1, 1.0, hz1 + 0.1, "metal")
    box(hx0, 0, hz1, hx1, 1.0, hz1 + 0.1, "metal")
    # key door: the wall at x 99 between the ramp landing and the bunker rooms (doorway open until keys exist)
    wall_z(bz0, bz1, 99.0, bunker_floor, -1.0 - bunker_floor, "bunker", [(151.0, DOOR_W, 0.0, DOOR_H)])
    box(98.7, bunker_floor + 2.3, 150.0, 99.3, bunker_floor + 2.6, 152.0, "keydoor", solid=False)
    markers.append(("KeyDoors", "BunkerDoor", 99.0, bunker_floor, 151.0, {"key": "bunker_key", "place": "Bunker"}))
    # bunker rooms: corridor along the south, three vaults to the north
    for x in (110.0, 121.0):
        wall_z(bz0, bz1 - 5, x, bunker_floor, 3.5, "bunker", [((bz0 + bz1 - 5) / 2, INNER_DOOR_W, 0.0, DOOR_H)])
    wall_x(99.0, bx1, bz1 - 5, bunker_floor, 3.5, "bunker",
           [(104.5, INNER_DOOR_W, 0.0, DOOR_H), (115.5, INNER_DOOR_W, 0.0, DOOR_H), (126.5, INNER_DOOR_W, 0.0, DOOR_H)])
    for x, z, yaw in ((102.0, 144.0, 180.0), (113.0, 144.0, 180.0), (124.0, 144.0, 180.0), (130.5, 149.0, 90.0)):
        add_loot("Bunker", "safe", x, z, y=bunker_floor, yaw=yaw)
    add_loot("Bunker", "locker", 107.0, 144.0, y=bunker_floor, yaw=180.0)
    add_loot("Bunker", "crate", 101.0, 156.5, y=bunker_floor)

    # bank with offices upstairs, one building east of the square (owner). The vault is the south-east room (1, 2),
    # only reachable from room (1, 1) through a key door placeholder (the stairs are along the north wall).
    bank = build(Building("Bank", 128, 110, 16, 30, floors=2, colour="wall_rich", rooms=(2, 3), doors="W",
                          solid_inner=[("v", 1, 2)], no_windows=[(1, 2)]), [
        ("safe", 1, 2, 0, "E", 1.5), ("safe", 1, 2, 0, "S", 0), ("locker", 0, 1, 0, "W", 0),
        ("crate", 1, 0, 0, "E", 0)])
    for kind, i, j, side in (("crate", 1, 0, "E"), ("crate", 0, 2, "W"), ("locker", 1, 1, "E"), ("crate", 0, 1, "W")):
        x, y, z, yaw = bank.against_wall(i, j, 1, side)
        add_loot("Offices", kind, x, z, y=y, yaw=yaw)
    box(139.0, 2.3, 129.7, 141.0, 2.6, 130.3, "keydoor", solid=False)
    markers.append(("KeyDoors", "BankVaultDoor", 140.0, 0.0, 130.0, {"key": "bank_vault_key", "place": "Bank"}))
    build(Building("Offices", 64, 119, 22, 21, floors=2, rooms=(3, 2), doors="E",
                   blasts=[(0, "W", 0)], caved=[(1, 1)]), [
        ("crate", 0, 1, 0, "W", 0), ("crate", 2, 0, 0, "N", 0), ("crate", 1, 0, 1, "N", 0),
        ("locker", 2, 1, 1, "E", 0), ("crate", 0, 0, 1, "W", 0)])
    gun = build(Building("GunStore", 70, 70, 16, 12, colour="wall_guns", rooms=(2, 1), doors="S"), [
        ("locker", 0, 0, 0, "W", 0), ("locker", 1, 0, 0, "E", 0), ("crate", 1, 0, 0, "N", 0)])
    for z in (73.0, 77.0):   # display counters
        box(72.0, 0, z, 77.0, 1.0, z + 0.8, "wood")
    build(Building("Pharmacy", 90, 72, 15, 12, colour="wall_med", rooms=(2, 1), doors="S", blasts=[(0, "N", 0)]), [
        ("crate", 0, 0, 0, "W", 0), ("crate", 1, 0, 0, "E", 0)])
    box(92.0, 0, 76.0, 96.5, 1.6, 76.8, "wood")
    groc = build(Building("Grocery", 128, 60, 24, 20, colour="wall_food", rooms=(3, 2), doors="S", roof=True,
                          blasts=[(0, "E", 0)]), [
        ("crate", 0, 0, 0, "W", 0), ("crate", 2, 0, 0, "N", 0), ("crate", 1, 1, 0, "S", -2)])
    for x in (132.0, 140.0, 148.0):  # aisles
        box(x, 0, 63.0, x + 0.9, 1.7, 68.0, "wood")
        box(x, 0, 72.0, x + 0.9, 1.7, 77.0, "wood")
    box(154, 0.0, 62, 168, 0.06, 80, "pavement", solid=False)   # car park
    car(158, 66, 0); car(164, 74, 0, "car_b")
    build(Building("Shops", 13, 61, 29, 13, floors=2, rooms=(3, 1), doors="S", caved=[(2, 0)]), [
        ("crate", 0, 0, 0, "W", 0), ("crate", 2, 0, 0, "E", 0), ("crate", 1, 0, 1, "N", 0), ("locker", 0, 0, 1, "W", 0)])
    # modern gas station on the corner of Main Street and Old Road (owner, 0.10.1; the town house was here)
    build(Building("GasStationTown", 74, 106, 13, 10, colour="wall_modern", rooms=(2, 1), doors="W"), [
        ("crate", 1, 0, 0, "E", 0), ("locker", 0, 0, 0, "N", -2.5)])
    for x in (63.0, 70.5):
        for z in (100.0, 112.5):
            box(x, 0, z, x + 0.5, 4.6, z + 0.5, "wall_modern")
    box(62.5, 4.6, 99.5, 71.5, 5.0, 113.5, "brand")                            # canopy
    box(61.5, 0.0, 98.5, 72.5, 0.05, 114.5, "pavement", solid=False)
    for z in (103.0, 107.0, 111.0):
        box(66.4, 0, z - 0.6, 67.6, 1.6, z + 0.6, "metal")                      # pumps
    build(Building("Police", 150, 112, 26, 22, floors=2, colour="wall_police", rooms=(3, 3), doors="WS", roof=True), [
        ("locker", 2, 0, 0, "E", 0), ("locker", 2, 0, 0, "N", 0), ("locker", 0, 2, 1, "W", 0),
        ("locker", 2, 2, 1, "E", 0), ("crate", 1, 1, 0, "S", 0)])
    for x, z, yaw in ((180, 118, 90), (180, 126, 90)):
        car(x, z, yaw, "car_b")
    barrier(178, 108, 90)
    build(Building("School", 15, 120, 30, 24, floors=2, colour="wall_school", rooms=(3, 3), doors="E", roof=True), [
        ("crate", 0, 0, 0, "W", 0), ("crate", 2, 2, 0, "E", 0), ("locker", 1, 2, 1, "S", 0),
        ("crate", 0, 1, 1, "W", 0)])
    box(15, 0.0, 148, 45, 0.04, 166, "crop", solid=False)       # sports field
    for gx_ in (16.0, 43.0):
        box(gx_, 0, 156.0, gx_ + 0.2, 2.4, 156.2, "metal")
        box(gx_, 0, 158.8, gx_ + 0.2, 2.4, 159.0, "metal")

    # hillside: big houses (owner: expensive loot)
    # (0.10.1: down from 5 to 3, owner: fewer houses so the good loot isn't spread thin, and the hill has sightlines)
    for n, (x, y, w, d) in enumerate([(30, 22, 16, 13), (68, 36, 15, 12), (100, 32, 15, 12)], start=1):
        build(Building(f"BigHouse{n}", x, y, w, d, floors=2, colour="wall_rich", rooms=(2, 2), doors="S"), [
            ("locker", 1, 1, 0, "E", 0), ("crate", 0, 1, 1, "W", 0), ("locker", 1, 0, 1, "E", 0)])
    add_loot("BigHouse1", "safe", 41.0, 22.8, y=FLOOR_H, yaw=180.0)

    # street cover around town
    for x, z, yaw, col in ((44, 87, 85, "car_a"), (80, 96, 72, "car_b"), (125, 101, 92, "car_a"), (150, 104, 97, "car_b"),
                           (57, 112, 10, "car_a"), (118, 52, 5, "car_b")):
        car(x, z, yaw, col)
    for x, z in ((48, 82), (88, 88), (124, 88), (147, 143), (78, 143), (126, 84)):
        dumpster(x, z)

    # houses between town and farm
    for n, (x, y) in enumerate([(214, 30), (218, 54)], start=1):
        build(Building(f"RoadHouse{n}", x, y, 12, 10, floors=1 + (n % 2), rooms=(2, 2), doors="S"),
              [("crate", 1, 1, 0, "E", 0)])

    # church and graveyard, top right of town (owner, 0.10.1): a bell tower you can climb (roof lookout), pews
    # inside, headstones (low cover) and a crypt
    build(Building("Church", 160, 28, 14, 24, colour="wall", rooms=(1, 1), doors="S", height=6.0), [
        ("crate", 0, 0, 0, "N", -4.5), ("locker", 0, 0, 0, "N", 4.5)])
    box(165, 0, 29.6, 169, 1.0, 31.0, "wood")                                   # altar
    for z in range(34, 48, 3):                                                  # pews, an aisle down the middle
        box(162.5, 0, z, 166.0, 0.9, z + 0.8, "wood")
        box(168.0, 0, z, 171.5, 0.9, z + 0.8, "wood")
    tower = build(Building("BellTower", 148, 28, 10, 10, floors=2, colour="wall", rooms=(1, 1), doors="S", roof=True),
                  [("crate", 0, 0, 2, "W", 0)])
    for px, pz in ((148.4, 28.4), (157.6, 28.4), (148.4, 37.6), (157.6, 37.6)):  # the bell frame on the roof
        box(px - 0.2, 6.0, pz - 0.2, px + 0.2, 9.0, pz + 0.2, "wood")
    box(148.2, 9.0, 28.2, 157.8, 9.4, 37.8, "roof")
    box(152.4, 7.4, 32.4, 153.6, 8.9, 33.6, "metal", solid=False)              # the bell
    areas.append(("Graveyard", 176, 30, 202, 56))
    fence([(181, 56), (176, 56), (176, 45)]); fence([(176, 39), (176, 30), (202, 30), (202, 56), (186, 56)])
    build(Building("Crypt", 192, 43, 8, 8, colour="stone", rooms=(1, 1), doors="W"), [("crate", 0, 0, 0, "E", 0)])
    for z in range(33, 54, 3):
        for x in (179.0, 181.6, 184.2, 186.8, 191.0, 193.6, 196.2, 198.8):     # (a path down the middle)
            if 188 < x + 1 and x - 1 < 202 and 41 < z + 0.5 and z - 0.5 < 53.5 and x > 189:
                continue   # the crypt and the ground round it
            if rng.random() < 0.25:
                continue
            box(x - 0.45, 0, z - 0.12, x + 0.45, rng.uniform(0.8, 1.1), z + 0.12, "stone")
    for tx, tz in ((178, 54), (200, 32), (178, 32)):
        tree(tx, tz, rng)

    # ===================================================================== FARM (top right)
    box(245, 0.0, 8, 343, 0.03, 100, "dirt", solid=False)
    build(Building("Barn", 256, 26, 24, 18, colour="wall_farm", rooms=(1, 1), doors="SN", height=6.0,
                   big_doors=True), [("crate", 0, 0, 0, "E", 0), ("crate", 0, 0, 0, "W", 2)])
    for hx, hz in ((262, 31), (262, 33.5), (274, 39), (270, 30)):
        hay(hx, hz)
    box(282, 0, 30, 290, 12, 38, "concrete")                          # silo
    build(Building("Farmhouse", 310, 26, 16, 12, floors=2, rooms=(2, 2), doors="S"), [
        ("locker", 1, 0, 0, "E", 0), ("crate", 0, 1, 1, "W", 0)])
    build(Building("Shed", 248, 46, 14, 10, colour="wall_farm", rooms=(1, 1), doors="E", height=4.0,
                   big_doors=True), [("crate", 0, 0, 0, "W", 0)])
    for k in range(5):   # crop rows (low cover)
        z = 50 + k * 9
        box(286, 0, z, 338, 1.0, z + 3, "crop")
    fence([(245, 8), (245, 40)]); fence([(245, 52), (245, 100), (300, 100)]); fence([(312, 100), (343, 100)])
    obox(250, 1.0, 90, 2.2, 2.0, 3.6, 20, "car_a")                     # tractor

    # ===================================================================== MIDDLE: train station + depot
    build(Building("TrainStation", 200, 190, 38, 14, colour="wall", rooms=(3, 1), doors="SN", roof=True,
                   height=3.6), [("crate", 0, 0, 0, "W", 0), ("crate", 2, 0, 0, "E", 0), ("locker", 1, 0, 0, "N", 0)])
    box(196, 0, 205, 246, 0.8, 207.6, "concrete")                       # platform
    build(Building("Depot", 262, 232, 30, 18, colour="wall_farm", rooms=(1, 1), doors="WE", height=7.0,
                   big_doors=True, blasts=[(0, "N", 0)]), [("crate", 0, 0, 0, "N", -6), ("crate", 0, 0, 0, "S", 6)])
    for x0, z0 in ((145, RY), (171, RY), (266, 220), (266, 228), (300, RY)):
        box(x0, 0, z0 - 1.5, x0 + 11, 3.6, z0 + 1.5, "boxcar")
    add_loot("Railyard", "crate", 150.0, RY + 2.3, yaw=180.0)

    # ===================================================================== BOTTOM RIGHT: old houses, gas station
    # war damage (owner, 0.11.6): most houses down here are shot up; OldHouse6 stays whole (spawn 5's cover)
    damage = {1: dict(blasts=[(0, "S", 1), (1, "E", 1)], caved=[(1, 1)]), 3: dict(blasts=[(0, "E", 0)], caved=[(0, 1)]),
              7: dict(blasts=[(1, "S", 0)], caved=[(0, 1)]), 8: dict(blasts=[(0, "S", 0)], caved=[(1, 1)])}
    for n, (x, y) in [(1, (196, 264)), (3, (316, 238)), (6, (164, 276)), (7, (148, 312)), (8, (214, 316))]:
        build(Building(f"OldHouse{n}", x, y, 12, 10, floors=1 + (n % 2), rooms=(2, 2), doors="N" if n % 3 else "W",
                       **damage.get(n, {})),
              [("crate", 0, 1, 0, "W", 0)] + ([("locker", 1, 0, 1, "E", 0)] if n % 2 else []))
    build(Building("GasStation", 298, 320, 28, 14, colour="wall_fuel", rooms=(2, 1), doors="S", blasts=[(0, "N", 0)]), [
        ("crate", 0, 0, 0, "W", 0), ("locker", 1, 0, 0, "E", 0)])
    for x in (296.5, 329.5):  # canopy over the pumps
        for z in (336.0, 341.5):
            box(x, 0, z, x + 0.5, 4.5, z + 0.5, "metal")
    box(296, 4.5, 335.5, 330.5, 4.9, 342.5, "wall_fuel")
    for x in (302, 310, 318):
        box(x, 0, 338.2, x + 1.2, 1.6, 339.4, "metal")
    build(Building("Diner", 276, 320, 16, 12, colour="wall_food", rooms=(2, 1), doors="W",
                   blasts=[(0, "N", 1)], caved=[(0, 0)]), [("crate", 1, 0, 0, "E", 0)])
    build(Building("Garage", 332, 322, 14, 14, rooms=(1, 1), doors="W", height=4.5, big_doors=True),
          [("crate", 0, 0, 0, "E", 0)])
    car(286, 300, 70, "car_b"); car(244, 268, 40, "car_a")

    # junkyard north of the gas station (owner, 0.10.1): a fenced yard of stacked wrecks that makes a maze, a crane,
    # a crusher and the office
    jx0, jz0, jx1, jz1 = 298.0, 262.0, 346.0, 294.0
    areas.append(("Junkyard", jx0, jz0, jx1, jz1))
    wall_x(jx0, jx1, jz0, 0.0, 2.4, "rust", [(320.0, 4.0, 0.0, 2.4)], t=0.2)
    wall_x(jx0, jx1, jz1, 0.0, 2.4, "rust", [(330.5, 5.0, 0.0, 2.4)], t=0.2)
    wall_z(jz0, jz1, jx0, 0.0, 2.4, "rust", [(278.5, 5.0, 0.0, 2.4)], t=0.2)
    wall_z(jz0, jz1, jx1, 0.0, 2.4, "rust", t=0.2)
    build(Building("JunkOffice", 300.5, 264.5, 10, 8, colour="wall", rooms=(1, 1), doors="S"),
          [("crate", 0, 0, 0, "N", 0)])
    for z, xs in ((270, (316, 321, 326, 336, 341)), (278, (310, 315, 330, 335, 340)), (286, (304, 309, 320, 325, 338))):
        for x in xs:
            car_stack(x, z, 90, rng.randint(1, 3), rng)
    box(341.2, 0, 265.2, 342.8, 12.0, 266.8, "metal")                           # crane tower and its boom
    box(326, 11.4, 265.6, 343, 12.0, 266.4, "metal", solid=False)
    box(304, 0, 290, 312, 3.0, 293.5, "concrete")                               # crusher
    add_loot("Junkyard", "crate", 328.0, 274.0, yaw=0.0)
    add_loot("Junkyard", "crate", 312.0, 282.0, yaw=180.0)
    add_loot("Junkyard", "crate", 343.0, 282.0, yaw=90.0)

    # roadblock checkpoint across the highway west of the gas station (owner, 0.10.1): a barrier chicane, sandbag
    # nests both sides, a guard booth and two army trucks
    yaw_r = math.degrees(math.atan2(290 - 236, 300 - 270))
    ux, uz = math.sin(math.radians(yaw_r)), math.cos(math.radians(yaw_r))
    nx_, nz_ = uz, -ux

    def at(s_, t_):
        return 263.0 + ux * s_ + nx_ * t_, 285.0 + uz * s_ + nz_ * t_
    for s_, t_ in ((-6, -2.0), (6, 2.0)):
        barrier(*at(s_, t_), yaw_r + 90)
    for t_ in (-7.5, 7.5):
        sandbags(*at(0, t_), yaw_r)
        sandbags(*at(-2.3, t_ * 0.85), yaw_r + 90, 2.4)
        sandbags(*at(2.3, t_ * 0.85), yaw_r + 90, 2.4)
    bx_, bz_ = at(-4, -10.5)
    obox(bx_, 1.3, bz_, 2.6, 2.6, 2.6, yaw_r, "army")                           # guard booth
    truck(*at(-15, 8.5), yaw_r)
    truck(*at(13, -9.0), yaw_r + 180)
    cx_, cz_ = at(2, 10.0)
    add_loot("Checkpoint", "crate", cx_, cz_, yaw=yaw_r)
    cx_, cz_ = at(-2, -12.5)
    add_loot("Checkpoint", "locker", cx_, cz_, yaw=yaw_r + 180)

    # ===================================================================== WOODS + cabins
    # clearings for the campsite and the hunting stands (0.10.1)
    camp, stands = (66.0, 268.0), [(40.0, 324.0), (116.0, 266.0)]
    clear = [(camp, 8.0)] + [(st, 6.0) for st in stands]
    for (cx, cz, r) in [(20, 240, 9), (42, 258, 11), (24, 288, 10), (58, 300, 12), (30, 322, 9), (85, 270, 10),
                        (72, 332, 9), (102, 312, 8), (110, 250, 7), (124, 332, 8)]:
        woods.append((cx, cz, r))
        for _ in range(int(r * 0.9)):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, r)
            tx, tz = cx + math.cos(a) * d, cz + math.sin(a) * d
            if any(math.hypot(tx - p[0], tz - p[1]) < rad for p, rad in clear):
                rng.uniform(0, 1); rng.uniform(0, 1)   # (keep the rest of the woods where it was)
                continue
            tree(tx, tz, rng)
        for _ in range(2):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, r)
            bush(cx + math.cos(a) * d, cz + math.sin(a) * d, rng)
    for (cx, cz, r) in [(280, 120, 9), (300, 130, 11), (322, 118, 9), (338, 140, 8), (288, 150, 10), (312, 158, 11),
                        (334, 176, 9), (268, 142, 7), (300, 180, 8)]:
        woods.append((cx, cz, r))
        for _ in range(int(r * 0.9)):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, r)
            tree(cx + math.cos(a) * d, cz + math.sin(a) * d, rng)
        bush(cx + rng.uniform(-r, r) / 2, cz + rng.uniform(-r, r) / 2, rng)
    # campsite by the creek (owner, 0.10.1): two tents, a fire pit with log seats, a crate
    x, z = camp
    for tx, tz, yaw in ((x - 4.0, z - 2.0, 20.0), (x + 3.5, z - 3.0, -15.0)):
        obox(tx, 0.6, tz, 2.4, 1.2, 2.8, yaw, "army")
        obox(tx, 1.35, tz, 1.2, 0.3, 2.8, yaw, "army")
    for dx, dz in ((-0.8, 0), (0.8, 0), (0, -0.8), (0, 0.8)):
        box(x + dx - 0.3, 0, z + 2 + dz - 0.3, x + dx + 0.3, 0.3, z + 2 + dz + 0.3, "stone")
    obox(x - 2.6, 0.2, z + 2.0, 0.5, 0.4, 2.2, 0, "trunk"); obox(x + 2.6, 0.2, z + 2.0, 0.5, 0.4, 2.2, 0, "trunk")
    add_loot("Campsite", "crate", x + 0.5, z - 5.5, yaw=180.0)
    # hunting stands (owner, 0.10.1): a platform 3.5 m up with a ramp, one watching the Creek Trail extract
    for sx, sz in stands:
        stand_spots.append((sx, sz))
        h, run = 3.5, 5.2
        box(sx - 1.4, h - 0.2, sz - 1.4, sx + 1.4, h, sz + 1.4, "wood")
        for px, pz in ((sx - 1.3, sz - 1.3), (sx + 1.3, sz - 1.3), (sx - 1.3, sz + 1.3), (sx + 1.3, sz + 1.3)):
            box(px - 0.12, 0, pz - 0.12, px + 0.12, h - 0.2, pz + 0.12, "trunk")
        box(sx - 1.4, h, sz - 1.4, sx + 1.4, h + 1.0, sz - 1.3, "wood")       # rails (open at the ramp)
        box(sx - 1.4, h, sz - 1.4, sx - 1.3, h + 1.0, sz + 1.4, "wood")
        box(sx + 1.3, h, sz - 1.4, sx + 1.4, h + 1.0, sz + 1.4, "wood")
        obox(sx, h / 2 - 0.1, sz + 1.4 + run / 2, 2.2, 0.2, math.hypot(run, h), 0.0, "wood",
             pitch=math.degrees(math.atan2(h, run)))
    for n, (x, y) in enumerate([(90, 288), (36, 304), (306, 166)], start=1):
        build(Building(f"Cabin{n}", x, y, 13, 10, colour="wood", rooms=(2, 1), doors="S"),
              [("crate", 1, 0, 0, "E", 0)])

    # ===================================================================== extracts, spawns
    # Extracts at the road ends and edges (0.10.3: 6, so the ones near your spawn can be closed for you, owner)
    extracts.extend([("FarmRoad", "Farm Road", 240, 6), ("Highway", "Highway", 342, 304),
                     ("CreekTrail", "Creek Trail", 10, 338), ("TownRoad", "Town Road", 6, 82),
                     ("MillLane", "Mill Lane", 138, 6), ("SouthRoad", "South Road", 160, 344)])
    # Player spawns (0.11.3, owner: spread out evenly, one in the top left, no two close enough to see each other):
    # 124+ m apart, each with cover nearby. Top-left corner, north of the church, the farm, west field, behind an
    # old house south of the railway (0.11.3: was out in the open middle field), east woods edge, the creek,
    # bottom right.
    for n, (x, z) in enumerate([(14, 14), (204, 18), (336, 14), (14, 190), (168, 268), (344, 180), (70, 344),
                                (270, 342)]):
        player_spawns.append((f"Spawn{n}", x, z))
        assert all(math.hypot(x - tx, z - tz) > 3.0 for tx, tz in trunks), f"Spawn{n} is in the trees"
        assert not any(x0 - 3 < x < x1 + 3 and z0 - 3 < z < z1 + 3 for _, x0, z0, x1, z1 in footprints), f"Spawn{n}"
    # AI spawn spots: placeholders spread over every area (Scavs 2.0 replaces them with designated spots)
    for n, (x, z) in enumerate([
            (106, 104), (60, 100), (140, 90), (40, 60), (90, 25), (163, 145), (30, 172), (100, 168),
            (220, 42), (270, 50), (320, 45), (300, 110), (220, 196), (190, 225), (280, 245), (230, 290),
            (320, 260), (300, 312), (190, 330), (60, 250), (90, 300), (40, 330), (320, 190), (150, 250),
            # (0.11.10, owner: twice the enemies, so twice the spots: open ground 26+ m from the others, 45+ m from
            # player spawns)
            (214, 252), (317, 223), (189, 199), (19, 84), (16, 294), (329, 294), (62, 36), (21, 267), (132, 200),
            (270, 290), (210, 309), (124, 311), (189, 115), (116, 72), (49, 154), (249, 70), (265, 201), (228, 150),
            (156, 223), (85, 235), (166, 87), (135, 27), (277, 149), (326, 137)]):
        enemy_spawns.append((f"Spawn{n}", x, z))

    # power lines along Main Street, the county road and the highway (owner, 0.10.1)
    power_line(main_st, -1, 9)
    power_line(county, 1, 8)
    power_line(old_road, 1, 8)

    trench()
    scatter_trees(clutter())
    zone_spawns()
    map_labels()
    check_roads()
    write_scene(terrain())
    print(f"{len(boxes)} boxes, {len(loot)} loot containers -> {os.path.normpath(OUT)}")


# AI zones (Scavs 2.0, owner 2026-10-10): each AI patrols only its own zone, so players learn where AI is.
# Hot zones are big areas with more AI and most Raiders: the town core round the town hall (hottest), the rest of
# town and the bottom right (hot-ish). Elsewhere a few small patrols, plus a few roamers that cross the whole map.
# (name, x, z, radius, scavs at the start, Raiders at the start, trickle weight for later arrivals)
AI_ZONES = [
    # Scavs and Raiders are rivals (0.12.17, owner): each side has its own areas.
    ("Town", 85, 95, 65, 6, 0, 2.0),          # scavs: the town, square included
    ("PoliceBank", 150, 124, 30, 0, 2, 2.0),  # Raiders: the police station and the bank (0.12.22, owner: spread out)
    ("GunStore", 80, 74, 20, 0, 2, 2.0),      # Raiders: the gun store and pharmacy, north of town
    ("SouthEast", 305, 300, 45, 0, 2, 2.0),   # Raiders: junkyard, old gas station, diner, garage
    ("Station", 240, 220, 35, 2, 0, 1.0),     # scavs: train station and depot
    ("Farm", 285, 42, 40, 2, 0, 0.0),
    ("RoadHouses", 222, 47, 20, 1, 0, 0.0),   # the two houses on the road between the church and the farm
    ("Church", 180, 42, 25, 1, 0, 0.0),
    ("Woods", 75, 290, 40, 3, 0, 0.0),        # cabins, campsite, hunting stand
    ("OldHouses", 200, 300, 30, 2, 0, 1.0),   # old houses south of the railway
    ("TownHall", 107, 151, 20, 0, 0, 0.0),    # the boss's zone: the town hall and its bunker (boss + guards only)
]
# The boss (owner: a Raider commander with guards, at the town hall + bunker, in every raid while testing; a chance
# later): zone, guards, chance per raid.
AI_BOSS = ("TownHall", 3, 1.0)
# Where the boss and guards start (owner, 0.12.18: inside the town hall, then out on patrol): ground-floor room
# centres of the hall (rooms 12.5 x 9 m), one picked per raid.
BOSS_STARTS = [(100.75, 155.5), (113.25, 146.5), (113.25, 155.5), (125.75, 155.5)]
AI_ROAMERS = 3
# Sniper perches (Scavs 2.0, owner): high spots with a view, a sniper stays on one. 2 of them are used each raid
# (preferring ones that don't already see a player). (name, x, z, height above the ground, which way it watches)
SNIPER_PERCHES = [
    ("PerchPolice", 152.5, 123.0, 6.0, "W"),       # police roof, over the town core and square
    ("PerchBellTower", 150.5, 30.5, 6.0, "S"),     # the bell tower, over the north of town
    ("PerchSchool", 42.5, 122.5, 6.0, "E"),        # school roof, over the west of town
    ("PerchStation", 212.0, 196.0, 3.6, "S"),      # train station roof, over the railway and the middle field
    ("PerchStand", 116.0, 266.0, 3.5, "N"),        # the hunting stand by the creek trail
]
AI_SNIPERS = 2
# AI spawn spots that overlapped something (0.12.20 check): the marker moves to a clear spot nearby. (Only the
# marker: the flat ground and props around the spot are placed for the old spot, so the map doesn't change.)
SPAWN_NUDGE = {(320, 260): (316, 254),   # under the edge of the raised road by the junkyard
               (40, 330): (46, 336)}     # under the hunting stand's ladder
spawn_zone = {}   # enemy spawn name -> its AI zone (no entry = only roamers use it)


def _zone_of(x, z):
    """The smallest AI zone containing (x, z), or None."""
    best = None
    for zone in AI_ZONES:
        if math.hypot(x - zone[1], z - zone[2]) <= zone[3] and (best is None or zone[3] < best[3]):
            best = zone
    return best


def _zone_spot_ok(x, z, taken):
    """Open, walkable ground for an AI spawn: off buildings, water, rail, props and trees, apart from other spots."""
    if not (8 < x < M - 8 and 8 < z < M - 8) or abs(z - 210.0) < 5:
        return False
    for points, width in water:
        for a, b in zip(points, points[1:]):
            if _seg_rect_gap(a, b, (x - 0.1, z - 0.1, x + 0.1, z + 0.1)) < width / 2 + 3:
                return False
    if any(x0 - 4 < x < x1 + 4 and z0 - 4 < z < z1 + 4 for _, x0, z0, x1, z1 in footprints):
        return False
    if any(t[0] - 3 < x < t[2] + 3 and t[1] - 3 < z < t[3] + 3 for t in TRENCHES):
        return False
    if any(math.hypot(x - tx, z - tz) < 3 for tx, tz in trunks):
        return False
    if any(math.hypot(x - sx, z - sz) < 40 for _, sx, sz in player_spawns):
        return False
    if any(math.hypot(x - ex, z - ez) < 14 for _, _, ex, ez in extracts):
        return False
    if any(math.hypot(x - sx, z - sz) < 8 for sx, sz in taken):
        return False
    for b in boxes:   # props (wrecks, rubble, stands, poles, fences...)
        if b[4] > 0.2 and max(b[3], b[5]) < 30 and math.hypot(x - (b[0] + M / 2), z - (b[2] + M / 2)) < max(b[3], b[5]) / 2 + 2:
            return False
    return True


def zone_spawns():
    """Tags the placeholder AI spawn spots with their zone, then adds spots until each zone has one more than it
    starts with (so its AI don't spawn on top of each other)."""
    rng = random.Random(1200)
    for zone in AI_ZONES:   # no zone reaches a player spawn (its AI would be on you the moment the raid starts)
        assert all(math.hypot(zone[1] - x, zone[2] - z) > zone[3] + 8 for _, x, z in player_spawns), zone[0]
    for name, x, z in enemy_spawns:
        zone = _zone_of(x, z)
        if zone:
            spawn_zone[name] = zone[0]
    for zone in AI_ZONES:
        zname, cx, cz, r, scavs, raiders = zone[:6]
        have = sum(1 for n, x, z in enemy_spawns if spawn_zone.get(n) == zname)
        need = max(4 if zname == AI_BOSS[0] else (3 if r >= 30 else 2), scavs + raiders + 1) - have
        for _ in range(3000):
            if need <= 0:
                break
            a, d = rng.uniform(0, math.tau), r * 0.85 * math.sqrt(rng.random())
            x, z = cx + d * math.cos(a), cz + d * math.sin(a)
            if _zone_of(x, z) is not zone or not _zone_spot_ok(x, z, [(sx, sz) for _, sx, sz in enemy_spawns]):
                continue
            name = f"Spawn{len(enemy_spawns)}"
            enemy_spawns.append((name, round(x, 1), round(z, 1)))
            spawn_zone[name] = zname
            need -= 1
        assert need <= 0, f"no room for AI spawn spots in zone {zname}"
    # Inside buildings too (0.12.23, owner: "don't be afraid to spawn the AI in actual buildings", so clearing a
    # building matters): the middle of each ground-floor room of a zone's buildings, away from the stairs. The
    # spawner uses these for about half of a zone's AI. (Only markers: no ground or props move for them.)
    for b in buildings:
        if b.name in NO_INDOOR_SPAWNS:
            continue
        for i in range(b.nx):
            for j in range(b.nz):
                x0, z0, x1, z1 = b.cell(i, j)
                cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
                if min(x1 - x0, z1 - z0) < 3.5:
                    continue   # too small a room
                if any(sx0 - 1.5 < cx < sx1 + 1.5 and sz0 - 1.5 < cz < sz1 + 1.5 for sx0, sx1, sz0, sz1 in b.strips):
                    continue   # the stairs
                zone = _zone_of(cx, cz)
                if zone is None or zone[0] == AI_BOSS[0] or (zone[4] + zone[5]) == 0:
                    continue
                indoor_spawns.append((f"Indoor{len(indoor_spawns) + 1}", round(cx, 1), round(cz, 1), zone[0]))


def spawner_meta(ter):
    """The map's AI numbers and zones (EnemySpawner settings)."""
    zones = ", ".join(
        f'{{"name": "{n}", "center": Vector3({fmt(gx(x))}, {fmt(ter.lift(x, z))}, {fmt(gz(z))}), "radius": {fmt(r)}, '
        f'"scavs": {s}, "raiders": {rd}, "trickle": {fmt(t)}}}' for n, x, z, r, s, rd, t in AI_ZONES)
    scavs = sum(z[4] for z in AI_ZONES) + AI_ROAMERS
    raiders = sum(z[5] for z in AI_ZONES)
    # Scavs 2.0 (owner: about 30 at the start once the boss and snipers are in): the zones' AI and the roamers at
    # the start, then 5 more scavs (one every 50-70 s) and 3 more Raiders trickle into the hot zones.
    return (f'metadata/spawner = {{"zones": [{zones}], "roamers": {AI_ROAMERS}, "snipers": {AI_SNIPERS}, "initial_count": 0, '
            f'"boss": {{"zone": "{AI_BOSS[0]}", "guards": {AI_BOSS[1]}, "chance": {fmt(AI_BOSS[2])}}}, '
            f'"max_alive": 36, "scav_budget": {scavs + 5}, "raider_budget": {raiders + 3}, '
            '"scav_interval_min": 50.0, "scav_interval_max": 70.0, '
            '"raider_times": PackedFloat32Array(150, 300, 420), "min_distance_from_player": 40.0}')


# Names on the in-raid map (M): buildings by their footprint, plus spots and areas.
MAP_NAMES = {"TownHall": "TOWN HALL", "Bank": "BANK", "Offices": "OFFICES", "GunStore": "GUN STORE",
             "Pharmacy": "PHARMACY", "Grocery": "GROCERY", "Shops": "SHOPS", "GasStationTown": "GAS STATION",
             "Police": "POLICE", "School": "SCHOOL", "Church": "CHURCH", "Barn": "BARN", "Farmhouse": "FARMHOUSE",
             "TrainStation": "TRAIN STATION", "Depot": "DEPOT", "GasStation": "OLD GAS STATION", "Diner": "DINER",
             "Garage": "GARAGE", "Cabin1": "CABIN", "Cabin2": "CABIN", "Cabin3": "CABIN"}


# Where a name sits instead of its building's middle (so neighbours' names don't overlap): "above"/"below" it.
MAP_NAME_SIDE = {"GunStore": "above", "Pharmacy": "below", "Diner": "above", "GasStation": "below", "Garage": "above"}


def map_labels():
    for name, x0, z0, x1, z1 in footprints:
        if name in MAP_NAMES:
            side = MAP_NAME_SIDE.get(name)
            z = z0 - 3 if side == "above" else z1 + 3 if side == "below" else (z0 + z1) / 2
            labels.append((MAP_NAMES[name], (x0 + x1) / 2, z, 0))
    labels.extend([("JUNKYARD", 322, 278, 0), ("CHECKPOINT", 263, 276, 0), ("CAMPSITE", 66, 262, 0),
                   ("HILL HOUSES", 66, 12, 0), ("GRAVEYARD", 189, 60, 0),
                   ("TOWN", 30, 104, 1), ("FARM", 312, 72, 1), ("WOODS", 72, 326, 1), ("WOODS", 300, 140, 1), ("RAILWAY", 120, 204, 1),
                   ("OLD HOUSES", 220, 300, 1)])
    yards.extend([(245, 8, 343, 100), (88, 108, 124, 138), (298, 262, 346, 294), (176, 30, 202, 56),
                  (154, 62, 168, 80), (15, 148, 45, 166)])


def _seg_rect_gap(a, b, rect):
    """Shortest distance between segment a-b and a rectangle (0 = they touch)."""
    x0, z0, x1, z1 = rect
    best = float("inf")
    for k in range(41):
        t = k / 40
        px, pz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        dx = max(x0 - px, 0, px - x1)
        dz = max(z0 - pz, 0, pz - z1)
        best = min(best, math.hypot(dx, dz))
    return best


def check_roads():
    """Fails the build if a building stands on a road (owner, 0.10.1): keep 1 m of pavement between them."""
    bad = []
    for name, x0, z0, x1, z1 in footprints:
        for points, width in roads:
            for a, b in zip(points, points[1:]):
                if _seg_rect_gap(a, b, (x0, z0, x1, z1)) < width / 2 + 1.0:
                    bad.append(f"{name} on the road through {a}-{b}")
    for name, x0, z0, x1, z1 in areas:
        for points, width in roads:
            for a, b in zip(points, points[1:]):
                if _seg_rect_gap(a, b, (x0, z0, x1, z1)) < width / 2 + 1.0:
                    bad.append(f"{name} on the road through {a}-{b}")
    for k, (name, x0, z0, x1, z1) in enumerate(footprints):   # and buildings need 1 m between them
        for other, ox0, oz0, ox1, oz1 in footprints[k + 1:]:
            if x0 < ox1 + 1 and ox0 < x1 + 1 and z0 < oz1 + 1 and oz0 < z1 + 1:
                bad.append(f"{name} overlaps {other}")
    if bad:
        raise SystemExit("Buildings on roads or each other:\n  " + "\n  ".join(bad))


# ---------------------------------------------------------------------------------------------- tscn
def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(x, y, z, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return (f"Transform3D({fmt(c)}, 0, {fmt(s)}, 0, 1, 0, {fmt(-s)}, 0, {fmt(c)}, "
            f"{fmt(gx(x))}, {fmt(y)}, {fmt(gz(z))})")


def minimap_meta(ter):
    """What the in-raid map (M) draws, in map metres (x east, z south from the top-left corner)."""
    def floats(values):
        return "PackedFloat32Array(" + ", ".join(fmt(v) for v in values) + ")"

    def lines(items):
        return "[" + ", ".join("PackedVector2Array(" + ", ".join(f"{fmt(x)}, {fmt(z)}" for x, z in pts) + ")"
                               for pts, _ in items) + "]"
    text = ", ".join(f'["{t}", {fmt(x)}, {fmt(z)}, {big}]' for t, x, z, big in labels)
    return ("metadata/minimap = {" + f'"size": {fmt(M)}, "offset": {fmt(-M / 2)}, '
            + f'"buildings": {floats([v for f in footprints for v in f[1:]])}, '
            + f'"yards": {floats([v for y in yards for v in y])}, '
            + f'"woods": {floats([v for w in woods for v in w])}, '
            + f'"roads": {lines(roads)}, "road_widths": {floats([w for _, w in roads])}, '
            + f'"water": {lines(water)}, "water_widths": {floats([w for _, w in water])}, '
            + '"rail": PackedVector2Array(0, 210, 350, 210), '
            + f'"relief_cells": {RELIEF_CELLS}, "relief": {floats(relief(ter))}, '
            + f'"labels": [{text}]' + "}")


RELIEF_CELLS = 140   # the in-raid map's picture of the hills: one height every 2.5 m


def relief(ter):
    step = M / RELIEF_CELLS
    return [ter.at((i + 0.5) * step, (j + 0.5) * step) for j in range(RELIEF_CELLS) for i in range(RELIEF_CELLS)]


def write_scene(ter):
    scenes = {"crate": "res://scenes/loot_crate.tscn", "locker": "res://scenes/loot_locker.tscn",
              "safe": "res://scenes/loot_safe.tscn"}
    out = ["[gd_scene format=3]", "",
           '[ext_resource type="Script" path="res://scripts/box_map.gd" id="1_boxmap"]',
           '[ext_resource type="PackedScene" path="res://scenes/extract_zone.tscn" id="2_extract"]']
    ids = {}
    for n, (kind, path) in enumerate(scenes.items(), start=3):
        ids[kind] = f"{n}_{kind}"
        out.append(f'[ext_resource type="PackedScene" path="{path}" id="{ids[kind]}"]')
    out += ["", "; Generated by tools/gen_old_bloxov.py: edit that script and re-run it, don't edit this file.", "",
            '[node name="OldBloxov" type="Node3D"]',
            'metadata/map_name = "Bloxov Battlegrounds"',
            spawner_meta(ter),
            minimap_meta(ter),
            "",
            '[node name="Level" type="Node3D" parent="."]', "",
            '[node name="Blocks" type="StaticBody3D" parent="Level"]',
            'script = ExtResource("1_boxmap")',
            "colors = PackedColorArray(" + ", ".join(f"{fmt(r)}, {fmt(g)}, {fmt(b)}, 1" for _, (r, g, b) in COLOURS) + ")",
            "boxes = PackedFloat32Array(" + ", ".join(fmt(v) for b in boxes for v in b) + ")",
            f"terrain_colour = {C['grass']}",
            "terrain_xs = PackedFloat32Array(" + ", ".join(fmt(gx(x)) for x in ter.xs) + ")",
            "terrain_zs = PackedFloat32Array(" + ", ".join(fmt(gz(z)) for z in ter.zs) + ")",
            "terrain_heights = PackedFloat32Array(" + ", ".join(fmt(h) for row in ter.h for h in row) + ")",
            "terrain_holes = PackedInt32Array(" + ", ".join(str(c) for c in ter.hole_cells) + ")",
            "terrain_hidden = PackedInt32Array(" + ", ".join(str(c) for c in ter.hidden_cells) + ")",
            f"water_colour = {C['water']}",
            f"water_width = {fmt(2 * CREEK_BANK)}",
            "water_points = PackedVector3Array(" + ", ".join(
                f"{fmt(gx(x))}, {fmt(ter.water_level(x, z))}, {fmt(gz(z))}" for x, z in water[0][0][WATER_START:]) + ")", "",
            '[node name="Loot" type="Node3D" parent="."]', ""]
    for name, kind, x, y, z, yaw, table, place in loot:
        out += [f'[node name="{name}" parent="Loot" instance=ExtResource("{ids[kind]}")]',
                f"transform = {xform(x, y, z, yaw)}",
                f'metadata/place = "{place}"', ""]
    out += ['[node name="Extracts" type="Node3D" parent="."]', ""]
    for name, title, x, z in extracts:
        out += [f'[node name="{name}" parent="Extracts" instance=ExtResource("2_extract")]',
                f"transform = {xform(x, ground_y['extract', name], z)}", f'extract_name = "{title}"', ""]
    out += ['[node name="PlayerSpawns" type="Node3D" parent="."]', ""]
    for name, x, z in player_spawns:
        out += [f'[node name="{name}" type="Marker3D" parent="PlayerSpawns"]',
                f"transform = {xform(x, ground_y['player', name] + 0.1, z)}", ""]
    out += ['[node name="EnemySpawns" type="Node3D" parent="."]', ""]
    for name, x, z in enemy_spawns:
        y = ground_y['enemy', name] + 0.1
        if (x, z) in SPAWN_NUDGE:
            x, z = SPAWN_NUDGE[x, z]
            y = ter.lift(x, z) + 0.3
        out += [f'[node name="{name}" type="Marker3D" parent="EnemySpawns"]', f"transform = {xform(x, y, z)}"]
        out += ([f'metadata/zone = "{spawn_zone[name]}"'] if name in spawn_zone else []) + [""]
    for name, x, z, zone in indoor_spawns:   # (dropped from just above the floor)
        out += [f'[node name="{name}" type="Marker3D" parent="EnemySpawns"]',
                f"transform = {xform(x, ter.lift(x, z) + 1.2, z)}", f'metadata/zone = "{zone}"',
                "metadata/indoor = true", ""]
    for i, (x, z) in enumerate(BOSS_STARTS):   # (dropped from just above the hall's floor)
        out += [f'[node name="BossStart{i + 1}" type="Marker3D" parent="EnemySpawns"]',
                f"transform = {xform(x, ter.lift(x, z) + 1.2, z)}", "metadata/boss_start = true", ""]
    faces = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}
    for name, x, z, h, face in SNIPER_PERCHES:
        out += [f'[node name="{name}" type="Marker3D" parent="EnemySpawns"]',
                f"transform = {xform(x, ter.lift(x, z) + h + 0.3, z)}", "metadata/perch = true",
                f"metadata/face = Vector3({faces[face][0]}, 0, {faces[face][1]})", ""]
    groups = sorted({m[0] for m in markers})
    for g in groups:
        out += [f'[node name="{g}" type="Node3D" parent="."]', ""]
        for grp, name, x, y, z, meta in markers:
            if grp != g:
                continue
            out += [f'[node name="{name}" type="Marker3D" parent="{g}"]', f"transform = {xform(x, y, z)}"]
            out += [f'metadata/{k} = "{v}"' for k, v in meta.items()]
            out.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
