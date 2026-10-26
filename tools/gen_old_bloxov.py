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
import collections
import contextlib
import json
import math
import os
import random
import re

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
SHOP_WIN_W, SHOP_WIN_LO, SHOP_WIN_HI = 4.0, 0.5, 2.4
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
    ("lot", (0.3, 0.3, 0.32)),        # car parks (World art 0.17: drawn with assets/materials/lot.tres)
    ("bush", (0.3, 0.5, 0.27)),       # bushes (0.18.3: walk-through, slow you down, hide you from the AI: BoxMap)
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


def box(x0, y0, z0, x1, y1, z1, colour, solid=True, kind=None, people=False):
    """Axis-aligned box from map-space corners (x/z in map meters, y = height). `kind` (inside `modeled`) tells the
    building's model what to draw there (a "pump", a "shelf"...)."""
    if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01:
        return
    _add_box(((x0 + x1) / 2 - M / 2, (y0 + y1) / 2, (z0 + z1) / 2 - M / 2,
              x1 - x0, y1 - y0, z1 - z0, 0.0, 0.0, C[colour], 1 if solid else 0), kind, people)


def obox(cx, cy, cz, sx, sy, sz, yaw, colour, solid=True, pitch=0.0, kind=None, people=False):
    """Rotated box: centre in map space, yaw in degrees (Godot convention, around +Y)."""
    _add_box((cx - M / 2, cy, cz - M / 2, sx, sy, sz, yaw, pitch, C[colour], 1 if solid else 0), kind, people)


# Open railings and bars drawn by a building's model (0.19.8, owner: "i cannot shoot through these cracks in the bus
# stop, stuff like this needs to be fixed"): their boxes stop people (and vaulting) but not shots or eyes, like barred
# windows. `people=True` on a box does the same. Marked 4 until the scene is written (still solid for the scatter),
# then they go to BoxMap `bar_boxes`.
PEOPLE_KINDS = {"gallery_rail", "loft_rail", "cell_bars"}


def model_shots(name):
    """{box number: triangles} of a model's see-through props (art_source/scripts/make_building.py SHOT_KINDS, 0.19.9):
    their boxes only stop people; shots hit these triangles (`shot_faces`, by write_model_boxes)."""
    path = os.path.join(MODEL_JSON_DIR, name + "_shots.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return {r["box"]: r["tris"] for r in json.load(f)["shots"]}


def _add_box(b, kind=None, people=False):
    m = _model[-1]
    if m is not None:
        m["boxes"].append((b, kind))
        if m["hide"]:   # drawn by the building's model: keep the collision, don't draw the box (BoxMap: 2 / 3)
            people = people or kind in PEOPLE_KINDS or len(m["boxes"]) - 1 in m["shots"]
            b = b[:9] + ((4 if people else 2) if b[9] else 3,)
    elif _debris[-1] is not None:   # a piece of the outdoor debris kit: tagged with its piece (b[10])
        b = b + (_debris[-1],)
    boxes.append(b)
    anchors.append(_anchor[-1])


# The outdoor debris kit (World art 0.17, outdoor step 1; owner 2026-10-18: "use a mix of all 3 [looks] ... i like the
# variation"): every piece of outside junk made by a function marked `@debris_kind(kind)` is drawn by a model
# (art_source/scripts/make_outdoor.py) in one of three looks, picked from where it stands. Its gray boxes still collide
# as before (cover and AI paths don't change) but aren't drawn once the model exists. The models are one per map chunk
# (OUTDOOR_CHUNK m square), so far-off chunks can be culled; `write_outdoor` writes their .json after the hills.
debris = []        # {"kind", "at": (x, z)}: one per piece; its index is the tag on its boxes
_debris = [None]
OUTDOOR_CHUNK = 87.5
OUTDOOR_JSON_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_source", "outdoor")


def debris_kind(kind, keep=False):
    """`keep`: never dropped by the scatter's overlap check (trees: they stay where they always were)."""
    def wrap(fn):
        def piece(x, z, *args, **kw):
            if _model[-1] is not None or _debris[-1] is not None:   # (part of a building's model, or of a bigger piece)
                return fn(x, z, *args, **kw)
            debris.append({"kind": kind, "at": (x, z)})
            _debris.append(len(debris) - 1)
            start, crater_start = len(boxes), len(craters)
            try:
                result = fn(x, z, *args, **kw)
            finally:
                _debris.pop()
            if _scattering[0] and not keep and _overlaps_earlier(start):   # (scattered junk never lands in something else)
                del boxes[start:]
                del anchors[start:]
                del craters[crater_start:]
                debris[-1]["dropped"] = True
            return result
        piece.__name__ = fn.__name__
        return piece
    return wrap


# Scattered pieces (clutter, cover, ruins: `scatter_piece`) are dropped if they'd overlap something already there
# (owner 2026-10-18: "make sure things arent over lapping"): any earlier debris piece, car, tree trunk, post or wall.
_scattering = [0]
_fp_index = {"upto": 0, "grid": {}}
FP_CELL = 8.0
FP_GAP = 0.3       # the least room between two pieces


def _fp_corners(b, pad=0.0):
    """A box's footprint (Godot x, z), its four corners."""
    c, s = math.cos(math.radians(b[6])), math.sin(math.radians(b[6]))
    hx, hz = b[3] / 2 + pad, b[5] / 2 + pad
    return [(b[0] + u * c + v * s, b[2] - u * s + v * c) for u, v in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]


def _fp_apart(p, q):
    """True if two convex footprints don't overlap (separating axes)."""
    for poly in (p, q):
        for k in range(len(poly)):
            ax, az = poly[k][1] - poly[k - 1][1], poly[k - 1][0] - poly[k][0]
            a = [ax * x + az * z for x, z in p]
            b = [ax * x + az * z for x, z in q]
            if max(a) <= min(b) or max(b) <= min(a):
                return True
    return False


def _fp_counts(b):
    """Earlier boxes a scattered piece must keep clear of: debris, and anything solid that stands on the ground
    (not ground covers, not tree tops)."""
    if len(b) > 10 and debris[b[10]]["kind"] not in POLE_KINDS + RAIL_KINDS + SET_KINDS + ("tree", "deadtree"):
        return True   # (power lines, the railway, trees, the set pieces: as before, only what's solid)
    return bool(b[9]) and b[4] > 0.2 and b[1] + b[4] / 2 > 0.05 and b[1] - b[4] / 2 < 2.0 and max(b[3], b[5]) < 60


def _overlaps_earlier(start):
    grid = _fp_index["grid"]
    for k in range(_fp_index["upto"], start):
        b = boxes[k]
        if not _fp_counts(b):
            continue
        r = math.hypot(b[3], b[5]) / 2
        for i in range(int((b[0] - r) // FP_CELL), int((b[0] + r) // FP_CELL) + 1):
            for j in range(int((b[2] - r) // FP_CELL), int((b[2] + r) // FP_CELL) + 1):
                grid.setdefault((i, j), []).append(k)
    _fp_index["upto"] = start
    for b in boxes[start:]:
        if b[4] <= 0.06:
            continue
        mine = _fp_corners(b, FP_GAP)
        r = math.hypot(b[3], b[5]) / 2 + FP_GAP
        seen = set()
        for i in range(int((b[0] - r) // FP_CELL), int((b[0] + r) // FP_CELL) + 1):
            for j in range(int((b[2] - r) // FP_CELL), int((b[2] + r) // FP_CELL) + 1):
                for k in grid.get((i, j), ()):
                    if k in seen:
                        continue
                    seen.add(k)
                    if not _fp_apart(mine, _fp_corners(boxes[k])):
                        return True
    return False


def outdoor_chunk(x, z):
    n = int(M // OUTDOOR_CHUNK)
    return f"outdoor_{min(n - 1, max(0, int(x // OUTDOOR_CHUNK)))}{min(n - 1, max(0, int(z // OUTDOOR_CHUNK)))}"


def outdoor_path(chunk):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "outdoor", chunk + ".glb")


# Building models (World art, 0.17): boxes made inside `with modeled(name, x, z):` still collide (players, AI paths
# and shots behave exactly as with the gray box) but aren't drawn; assets/models/buildings/<name>.glb draws them.
# Their boxes go to art_source/buildings/<name>.json (relative to the model's origin at map (x, 0, z)), which
# art_source/scripts/make_building.py builds the model around.
models = []
_model = [None]
MODEL_JSON_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_source", "buildings")


@contextlib.contextmanager
def modeled(name, x, z, turned=False):
    # Until the model is exported the gray box stays visible (the .json is still written for the build script).
    # turned: everything made in here is turned round (x, z) afterwards, and the model drawn turned to match (owner,
    # police round 3: "the entrance is facing away from the street"); its .json stays as built, the model's own frame.
    # True = half a turn; or a yaw in degrees (90: the model's south side faces east, the shops).
    turn = 180.0 if turned is True else float(turned or 0.0) % 360.0
    m = {"name": name, "x": x, "z": z, "boxes": [], "hide": os.path.exists(model_path(name)), "turned": turn,
         "shots": model_shots(name)}
    models.append(m)
    _model.append(m)
    counts = (len(boxes), len(markers), len(loot), len(buildings))
    try:
        yield
    finally:
        _model.pop()
        m["range"] = (counts[0], len(boxes))
        if turn % 180.0:
            # A quarter turn changes the building's footprint: it's turned after the random scatter (trees, clutter,
            # cover) is settled, so the scatter doesn't reshuffle map-wide; what then stands in its way is cleared.
            late_turns.append((x, z, turn, counts, (len(boxes), len(markers), len(loot), len(buildings))))
        elif turn:
            _turn(x, z, turn, counts, (len(boxes), len(markers), len(loot), len(buildings)))
        if not turn % 180.0:
            _floor_rect(m)


late_turns = []   # (x, z, deg, box/marker/loot/building counts before and after) of quarter-turned models, see apply_late_turns


# What each building's floors sound like underfoot (Sound update 0.20.0: footsteps by surface, scripts/surfaces.gd:
# 1 wood, 2 metal, 3 concrete/tile). Used where you stand on the ground or on a plain floor slab inside the building;
# boxes with their own colour (wood lofts, metal) sound like that colour. Not listed = outdoors (yards).
FLOOR_SURFACE = {
    "barn": 1, "cabin_east": 1, "cabin_fisher": 1, "cabin_trapper": 1, "farmhouse": 1, "shed": 1, "motel": 1,
    "signal_box": 1, "junk_office": 1, "big_house_1": 1, "big_house_2": 1, "big_house_3": 1,
    "old_house_1": 1, "old_house_6": 1, "old_house_7": 1, "old_house_8": 1,
    "silo": 2,
    "bank": 3, "bell_tower": 3, "church": 3, "depot": 3, "diner": 3, "garage": 3, "gas_station": 3,
    "gas_station_town": 3, "grocery": 3, "gun_store": 3, "offices": 3, "pharmacy": 3, "police": 3, "school": 3,
    "shops": 3, "th_vault": 3, "town_hall": 3, "train_station": 3,
}
floor_rects = []   # (Godot x0, z0, x1, z1, surface) of each modeled building, from its solid boxes


def _floor_rect(m):
    """Notes model m's footprint (its solid boxes, as they now stand) with its floor sound, see FLOOR_SURFACE."""
    surface = FLOOR_SURFACE.get(m["name"])
    if surface is None:
        return
    xs, zs = [], []
    for b in boxes[m["range"][0]:m["range"][1]]:
        if b[9] in (1, 2, 4):
            r = math.hypot(b[3], b[5]) / 2 if b[6] or b[7] else 0.0
            xs += [b[0] - (r or b[3] / 2), b[0] + (r or b[3] / 2)]
            zs += [b[2] - (r or b[5] / 2), b[2] + (r or b[5] / 2)]
    if xs:
        floor_rects.append((min(xs), min(zs), max(xs), max(zs), surface))


def apply_late_turns(margin=3.0):
    """Turns the quarter-turned models (see `modeled`), then drops the scatter pieces that now stand in or round them."""
    late = [m for m in models if m["turned"] % 180.0]
    for (x, z, deg, start, end), m in zip(late_turns, late):
        _turn(x, z, deg, start, end)
        _floor_rect(m)
        for b in buildings[start[3]:end[3]]:
            r = next(f for f in footprints if f[0] == b.name)[1:]
            clear_scatter((r[0] - margin, r[1] - margin, r[2] + margin, r[3] + margin) if b.name not in SCATTER_CLEAR
                          else SCATTER_CLEAR[b.name])


def clear_scatter(rect, hit=None):
    """Drops every scatter piece (clutter, cover, trees) with a box in rect (map x0, z0, x1, z1), whole; or, given
    `hit` (a box -> bool), every piece with a box it hits."""
    x0, z0, x1, z1 = rect or (0, 0, 0, 0)
    for piece in reversed(scatter_pieces):
        (b0, b1), *rest = piece[1]
        if hit is not None:
            if not any(hit(boxes[k]) for k in range(b0, b1)):
                continue
        elif not any(x0 < boxes[k][0] + M / 2 < x1 and z0 < boxes[k][2] + M / 2 < z1 for k in range(b0, b1)):
            continue
        del boxes[b0:b1]
        del anchors[b0:b1]
        for lst, (a0, a1) in zip((trunks, craters, clutter_spots, woods), rest):
            del lst[a0:a1]
        k = scatter_pieces.index(piece)
        scatter_pieces.remove(piece)
        # (the pieces made after it move down the lists: so a later clear finds them where they are now)
        for n, (spot, ranges) in enumerate(scatter_pieces[k:], start=k):
            scatter_pieces[n] = (spot, [(a - (e1 - e0), e - (e1 - e0)) for (a, e), (e0, e1) in zip(ranges, piece[1])])


def turn_point(px, pz, x, z, deg):
    """(px, pz) turned `deg` (Godot yaw: 90 takes +z to +x) round (x, z)."""
    c, s = round(math.cos(math.radians(deg)), 9), round(math.sin(math.radians(deg)), 9)
    dx, dz = px - x, pz - z
    return x + dx * c + dz * s, z - dx * s + dz * c


def _turn(x, z, deg, start, end):
    """Turns the boxes, doors, loot and buildings made between the counts `start` and `end` (each box, marker, loot,
    building) `deg` round map point (x, z)."""
    (nb, nm, nl, nbuild), (eb, em, el, ebuild) = start, end
    quarter = deg % 180.0 != 0.0
    for k in range(nb, eb):
        b = boxes[k]
        bx, bz = turn_point(b[0], b[2], gx(x), gz(z), deg)
        sx, sz = b[3], b[5]
        if b[6] == 0.0 and b[7] == 0.0:
            yaw = 0.0
            if quarter:
                sx, sz = sz, sx   # (an unturned box stays unturned: its sides swap)
        else:
            yaw = (b[6] + deg) % 360.0
        boxes[k] = (bx, b[1], bz, sx, b[4], sz, yaw) + b[7:]
    for k in range(nm, em):
        g, name, mx, my, mz, meta = markers[k]
        mx, mz = turn_point(mx, mz, x, z, deg)
        if quarter and "yaw" in meta:   # (half a turn leaves a doorway's leaf where it was: police kept that)
            meta = dict(meta, yaw=(meta["yaw"] + deg) % 360.0)
        markers[k] = (g, name, mx, my, mz, meta)
    for k in range(nl, el):
        name, kind, lx, ly, lz, yaw, table, place = loot[k]
        lx, lz = turn_point(lx, lz, x, z, deg)
        loot[k] = (name, kind, lx, ly, lz, (yaw + deg) % 360.0, table, place)
    for b in buildings[nbuild:ebuild]:
        b.turned_about = (x, z, deg)   # (its rooms, strips etc. stay as built: indoor spawns turn their points)
        k = next(i for i, f in enumerate(footprints) if f[0] == b.name)
        (ax, az), (bx, bz) = turn_point(b.x0, b.z0, x, z, deg), turn_point(b.x1, b.z1, x, z, deg)
        footprints[k] = (b.name, min(ax, bx), min(az, bz), max(ax, bx), max(az, bz))


@contextlib.contextmanager
def unmodeled():
    """Boxes made in here aren't part of the building model they're inside (drawn as gray box as usual)."""
    _model.append(None)
    try:
        yield
    finally:
        _model.pop()


def note_opening(kind, side, at, mid, w, lo, hi):
    """An outside wall opening of a modeled building (window, door, shop window, blast hole), for its model: windows
    get frames and glass (whole or smashed), doorways a broken door (refine pass, owner)."""
    m = _model[-1] if _model else None
    if m is None:
        return
    m.setdefault("openings", []).append({"kind": kind, "side": side, "at": at, "mid": mid, "w": w, "lo": lo, "hi": hi})


def model_path(name):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "buildings", name + ".glb")


# Solid-looking things that had no box (0.22.0, World reacts; owner: "give solid-looking things real hitboxes",
# found with tools/walkthrough_audit.gd). Two kinds of fix, both made late (after the scatter, like fit_trucks) so
# nothing else on the map moves:
# - MADE_SOLID: gray-box kinds that were picture only but look solid (furniture, racks, open stall doors).
# - <name>_solids.json from art_source/scripts/make_building.py (SOLIDS): boxes for what a model draws without a gray
#   box (fallen roof slabs and beams in the caved rooms, chairs, porch posts).
# Both only stop players (flag 5, BoxMap `prop_boxes`): shots, eyes and the AI pass through them as before, and the
# AI's navigation doesn't see them (AI locked in, owner). Rubble you step over stays picture only (owner, 0.11.6:
# nothing blocks a doorway or loot).
MADE_SOLID = {
    "waiting_seats", "waiting_seats_east", "chair_rows", "briefing_chairs", "sb_chair", "cabin_chairs", "dn_stool",
    "tc_stool", "tc_bench", "fc_rocker", "motel_table", "motel_nightstand", "motel_cot", "cell_bunk", "cell_toilet",
    "th_cot", "globe", "voting_booths", "plant", "coat_rack", "robe_rail", "fc_fish_rack", "tc_pelt_rack",
    "tc_stretchers", "tc_cache", "mugshot_camera", "drill_rig", "cashier_spot", "stall_gate", "wc_stalls", "wc_door",
    "casino_cage", "motel_rail", "st_canopy_wreck",
}


def model_solids(name):
    path = os.path.join(MODEL_JSON_DIR, name + "_solids.json")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return json.load(f)["solids"]


def solid_late():
    """MADE_SOLID kinds stop people now; each model's SOLIDS get their boxes (before terrain() lifts them)."""
    key = lambda x, y, z, sy: (round(x, 2), round(y, 2), round(z, 2), round(sy, 2))   # noqa: E731
    made = set()
    for m in models:
        if m["hide"]:
            for b, kind in m["boxes"]:   # (kept unturned: find them where the turn put them)
                if kind in MADE_SOLID and b[9] in (0, 3):
                    x, z = turn_point(b[0], b[2], gx(m["x"]), gz(m["z"]), m["turned"])
                    made.add(key(x, b[1], z, b[4]))
    for i, b in enumerate(boxes):
        if b[9] in (0, 3) and key(b[0], b[1], b[2], b[4]) in made:
            boxes[i] = b[:9] + (5,) + b[10:]
    for m in models:
        if not m["hide"]:
            continue
        ox, oz = gx(m["x"]), gz(m["z"])
        m["solids"] = model_solids(m["name"])
        for r in m["solids"]:
            (px, py, pz), size = r["pos"], r["size"]
            x, z = turn_point(ox + px, oz + pz, ox, oz, m["turned"])
            boxes.append((x, py, z, size[0], size[1], size[2], (r["yaw"] + m["turned"]) % 360.0, r["pitch"],
                          C["wood" if r["people"] else "concrete"], 5))
            anchors.append(None)


def write_model_boxes(ter):
    """Also checks the whole model stands on one flat pad (the model can't bend over hills like the boxes)."""
    names = {i: n for n, i in C.items()}
    os.makedirs(MODEL_JSON_DIR, exist_ok=True)
    for m in models:
        ox, oz = gx(m["x"]), gz(m["z"])
        rows = [{"pos": [round(b[0] - ox, 3), round(b[1], 3), round(b[2] - oz, 3)],
                 "size": [round(v, 3) for v in b[3:6]], "yaw": b[6], "pitch": b[7], "colour": names[b[8]],
                 "solid": bool(b[9]), "kind": kind} for b, kind in m["boxes"]]
        y = ter.lift(m["x"], m["z"])
        bad = [b for b, _ in m["boxes"]   # (a turned model's boxes are kept unturned, in its own frame)
               if abs(ter.lift(*turn_point(b[0] + M / 2, b[2] + M / 2, m["x"], m["z"], m["turned"])) - y) > 0.01]
        assert not bad, f"{m['name']}: not all on one pad ({len(bad)} boxes off it: {[(round(b[0] + M / 2, 1), round(b[2] + M / 2, 1)) for b in bad]})"
        m["y"] = y
        opens = []
        for o in m.get("openings", []):
            ns = o["side"] in "NS"
            at = gz(o["at"]) - oz if ns else gx(o["at"]) - ox
            mid = gx(o["mid"]) - ox if ns else gz(o["mid"]) - oz
            opens.append({"kind": o["kind"], "side": o["side"], "at": round(at, 3), "mid": round(mid, 3),
                          "w": o["w"], "lo": round(o["lo"], 3), "hi": round(o["hi"], 3)})
        barred(m, opens)
        if m["hide"]:
            for n, tris in m["shots"].items():   # (the see-through props: what shots hit, in the map)
                b = m["boxes"][n][0]
                for p in clipped_to_box(tris, (b[0] - ox, b[1], b[2] - oz), b[3:6], b[6]):
                    x, z = turn_point(ox + p[0], oz + p[2], ox, oz, m["turned"])
                    shot_faces.extend((x, y + p[1], z))
            path = os.path.join(MODEL_JSON_DIR, m["name"] + "_solids.json")
            for kx, ky, kz, yaw, kind, colour in (json.load(open(path)).get("kicks", []) if os.path.exists(path) else []):
                x, z = turn_point(ox + kx, oz + kz, ox, oz, m["turned"])   # (its tins and bottles: kickables.gd)
                KICKS.append([x, y + ky, z, (yaw + m["turned"]) % 360.0, kind, colour])
        prop_loot(m)
        glazed(m)
        with open(os.path.join(MODEL_JSON_DIR, m["name"] + ".json"), "w") as f:
            f.write('{"note": "Generated by tools/gen_old_bloxov.py: the gray-box pieces this building\'s model covers, '
                    'in Godot space (y up, -z north) relative to the model\'s origin.",\n"openings": '
                    + json.dumps(opens) + ',\n"boxes": [\n'
                    + ",\n".join(json.dumps(r) for r in rows) + "\n]}\n")


# Barred and boarded-up windows (0.18.3, owner: "make sure windows that are barred up and stuff arent jumpable"): the
# models draw steel bars (art_source/scripts/make_building.py window_bars) or planks over these; each gets a box that
# stops people (and vaulting) but not bullets or anyone's eyes (BoxMap `bar_boxes`). Model name -> which windows.
BARRED = {"gun_store": lambda o: True, "bank": lambda o: o["lo"] < 1.5, "police": lambda o: o["lo"] < 1.5,
          "farmhouse": lambda o: o["lo"] < 2 and o["side"] in "NW"}
bar_boxes = []   # Godot x, y, z, size x, y, z, yaw
prop_boxes = []  # the same, for what stops players only (0.22.0, solid_late: BoxMap `prop_boxes`)


def barred(m, opens):
    rule = BARRED.get(m["name"])
    if rule is None:
        return
    ox, oz = gx(m["x"]), gz(m["z"])
    for o in opens:
        if o["kind"] != "window" or not rule(o):
            continue
        ns = o["side"] in "NS"
        lx, lz = (o["mid"], o["at"]) if ns else (o["at"], o["mid"])
        sx, sz = (o["w"] + 0.1, 0.5) if ns else (0.5, o["w"] + 0.1)
        x, z = turn_point(ox + lx, oz + lz, ox, oz, m["turned"])
        bar_boxes.append((x, m["y"] + (o["lo"] + o["hi"]) / 2, z, sx, o["hi"] - o["lo"] + 0.1, sz, m["turned"]))


# Props that look like you could search them are containers (0.18.4, owner: "dont make fake loot spots. anything that
# looks lootable should be lootable"): the building model draws them (make_building.py, by box kind); each gets an
# invisible container the size of its box (LootContainer `prop` metadata) with a light roll, in the place of the
# nearest real container. Box kind -> (scene/table, name shown, fewest, most items).
PROP_LOOT = {
    "file_cabinet": ("crate", "Filing Cabinet", 1, 2), "jo_filing": ("crate", "Filing Cabinet", 1, 2),
    "record_cabinet": ("crate", "Record Cabinet", 1, 2), "plan_chest": ("crate", "Plan Chest", 1, 2),
    "rx_drawers": ("crate", "Medicine Drawers", 1, 2), "motel_nightstand": ("crate", "Nightstand", 1, 1),
    "motel_dresser": ("crate", "Dresser", 1, 2), "fc_drawers": ("crate", "Drawers", 1, 2),
    "vanity": ("crate", "Vanity", 1, 2), "toy_chest": ("crate", "Toy Chest", 1, 2),
    "trunk": ("crate", "Trunk", 1, 2), "cabin_trunk": ("crate", "Trunk", 1, 2), "tc_footlocker": ("crate", "Footlocker", 1, 2),
    "tc_cache": ("crate", "Cache", 1, 2), "cabin_loft_crates": ("crate", "Crates", 1, 2),
    "supply_crates": ("crate", "Supply Crates", 1, 2), "dp_crates": ("crate", "Crates", 1, 2),
    "ammo_crates": ("crate", "Ammo Crates", 1, 2), "ammo_cans": ("crate", "Ammo Cans", 1, 2),
    "ice_chest": ("crate", "Cooler", 1, 2), "chest_freezer": ("crate", "Freezer", 1, 2),
    "hall_lockers": ("locker", "Lockers", 1, 3), "fc_wardrobe": ("locker", "Wardrobe", 1, 3),
    "tc_hutch": ("locker", "Hutch", 1, 3), "gr_toolchest": ("locker", "Tool Chest", 1, 3),
    "small_safe": ("safe", "Small Safe", 1, 1),
}
PROP_OF = {}   # container name -> (shown name, box size, fewest, most)


def prop_loot(m):
    """(Its place: the nearest real container in the same building, on the same floor if there's one.)"""
    pts = [turn_point(b[0] + M / 2, b[2] + M / 2, m["x"], m["z"], m["turned"]) for b, _ in m["boxes"]]
    x0, x1 = min(p[0] for p in pts) - 1, max(p[0] for p in pts) + 1
    z0, z1 = min(p[1] for p in pts) - 1, max(p[1] for p in pts) + 1
    inside = [l for l in loot if l[0] not in PROP_OF and x0 < l[2] < x1 and z0 < l[4] < z1]
    for b, kind in m["boxes"]:
        if kind not in PROP_LOOT:
            continue
        table, shown, lo, hi = PROP_LOOT[kind]
        # (Another piece drawn round it, like the motel's aid table over a dresser, is what you see and look at.)
        b = next((o for o, k in m["boxes"] if k and k != kind and o[6] == b[6] and all(
            abs(o[i] - b[i]) + b[i + 3] / 2 <= o[i + 3] / 2 + 0.001 for i in range(3))), b)
        x, z = turn_point(b[0] + M / 2, b[2] + M / 2, m["x"], m["z"], m["turned"])
        y = m["y"] + b[1] - b[4] / 2
        near = min(inside or [l for l in loot if l[0] not in PROP_OF],
                   key=lambda l: math.hypot(l[2] - x, l[4] - z) + 50 * (abs(l[3] - y) > 2))
        place = near[7] if math.hypot(near[2] - x, near[4] - z) < 60 else ""
        n = sum(1 for l in loot if l[0].startswith(place + "_Prop")) + 1
        name = f"{place}_Prop{n}"
        PROP_OF[name] = (shown, b[3:6], lo, hi)
        loot.append((name, table, x, y, z, (m["turned"] + b[6]) % 360.0, table, place))


# The windows still glazed (0.18.8, owner: "make windows breakable"): art_source/scripts/make_building.py leaves these
# panes out of the model and lists them in <name>_panes.json; the map draws and collides them (BoxMap `window_panes`)
# so a shot or a shove breaks one. A model without the file (not rebuilt yet) simply has no breakable windows.
window_panes = []   # Godot x, y, z, width, height, yaw (the pane faces along its yaw)


def glazed(m):
    path = os.path.join(MODEL_JSON_DIR, m["name"] + "_panes.json")
    if not os.path.exists(path):
        return
    ox, oz = gx(m["x"]), gz(m["z"])
    with open(path) as f:
        panes = json.load(f)["panes"]
    for p in panes:
        lx, lz = (p["mid"], p["at"]) if p["ns"] else (p["at"], p["mid"])
        x, z = turn_point(ox + lx, oz + lz, ox, oz, m["turned"])
        window_panes.append((x, m["y"] + p["y"], z, p["w"], p["h"], (m["turned"] + (0.0 if p["ns"] else 90.0)) % 360.0))


# ---------------------------------------------------------------------------------------------- nodes
loot = []        # (name, scene, x, y, z, yaw, table, place)
extracts = []    # (node name, display name, x, z)
player_spawns = []
enemy_spawns = []
NO_INDOOR_SPAWNS = {"Grocery"}   # rooms full of shelves
indoor_spawns = []   # (name, x, z, zone, building): AI spawn spots inside buildings, in the middle of ground-floor rooms
buildings = []
markers = []     # (group node, name, x, y, z, metadata dict)


# What each container looks like (World art 0.17, owner: containers fit their place): (place, loot kind) -> look,
# a model in assets/models/loot (art_source/scripts/make_loot.py; names and sizes in scripts/loot_container.gd).
# Places are matched without their number (BigHouse2 -> BigHouse). Only the model changes, not the loot.
LOOT_LOOKS = {
    "crate": {"GunStore": "weapon_case", "Checkpoint": "hard_case", "Bunker": "hard_case", "Railyard": "hard_case",
              "Depot": "hard_case", "Pharmacy": "med_cabinet", "Grocery": "stock_boxes", "Shops": "stock_boxes",
              "GasStationTown": "stock_boxes", "GasStation": "stock_boxes", "BigHouse": "dresser",
              "OldHouse": "dresser", "RoadHouse": "dresser", "Motel": "dresser", "Farmhouse": "dresser", "Cabin": "duffel",
              "Campsite": "duffel", "BellTower": "duffel", "Offices": "filing", "TownHall": "filing",
              "Police": "filing", "Bank": "filing", "School": "filing", "TrainStation": "filing",
              "JunkOffice": "filing", "Barn": "toolbox", "Shed": "toolbox", "Garage": "toolbox",
              "Junkyard": "toolbox", "Church": "chest", "Crypt": "chest", "Diner": "kitchen"},
    "locker": {"BigHouse": "wardrobe", "OldHouse": "wardrobe", "Farmhouse": "wardrobe", "Church": "wardrobe",
               "GunStore": "gun_cabinet"},
    "safe": {},
}
DEFAULT_LOOK = {"crate": "hard_case", "locker": "locker", "safe": "safe"}


# A container's own look when its room needs one that isn't its place's (round 4, owner: containers that make sense
# for the room: the TV shop's boxes are TVs, the laundromat has a laundry cart). Container name -> look.
LOOK_OF = {}


def settle_fallen_doors():
    """A door that fell off lies flat on the floor on either side of its doorway (scripts/door.gd): where furniture
    stands there, it would lie under or through it (owner, police round 3: the doors under the front desk), so that
    door stays up and works instead."""
    for k, (grp, name, x, y, z, meta) in enumerate(markers):
        if grp != "Doors" or meta.get("broken") != "fallen":
            continue
        along_x = meta.get("yaw", 0.0) == 0.0          # the doorway runs along x (a wall along x)
        for b in boxes:
            if b[7] != 0.0 or not (0.15 < b[4] <= 2.3) or b[3] * b[5] > 8.0:
                continue
            if not (y - 0.05 < b[1] - b[4] / 2 < y + 0.6):
                continue
            bx, bz = b[0] + M / 2, b[2] + M / 2
            ha, hw = (b[3], b[5]) if along_x else (b[5], b[3])
            if b[6] % 180.0 != 0.0:
                ha = hw = max(b[3], b[5])
            da, dw = (bx - x, bz - z) if along_x else (bz - z, bx - x)
            if abs(da) < 1.1 + ha / 2 and 0.1 - hw / 2 < abs(dw) < 2.9 + hw / 2:
                meta["broken"] = ""
                break


def loot_look(place, kind, name=""):
    return LOOK_OF.get(name) or LOOT_LOOKS[kind].get(re.sub(r"\d+$", "", place), DEFAULT_LOOK[kind])


def prop_lines(name, kind, place):
    """The look of a container, or (a searchable prop, PROP_OF) its name, box and roll."""
    if name not in PROP_OF:
        return [f'metadata/look = "{loot_look(place, kind, name)}"']
    shown, size, lo, hi = PROP_OF[name]
    return [f'display_name = "{shown}"', f"min_items = {lo}", f"max_items = {hi}",
            f"metadata/prop = Vector3({fmt(size[0])}, {fmt(size[1])}, {fmt(size[2])})"]


def add_loot(place, kind, x, z, y=0.0, yaw=0.0, look=None):
    """kind: crate / locker / safe (the scene's loot table; ItemDB.PLACE_LOOT adds the place's own loot, 0.14.0)."""
    n = sum(1 for l in loot if l[0].startswith(place + "_")) + 1
    name = f"{place}_{kind.capitalize()}{n}"
    if look:
        LOOK_OF[name] = look
    loot.append((name, kind, x, y, z, yaw, kind, place))


# ---------------------------------------------------------------------------------------------- walls
def wall_x(x0, x1, z, y0, h, colour, openings=(), t=WALL_T, kind=None):
    """A wall along x (from x0 to x1 at depth z). openings: (centre_x, width, bottom, top)."""
    _wall(x0, x1, y0, h, colour, openings, lambda a, b, y_lo, y_hi: box(a, y_lo, z - t / 2, b, y_hi, z + t / 2, colour, kind=kind))


def wall_z(z0, z1, x, y0, h, colour, openings=(), t=WALL_T, kind=None):
    _wall(z0, z1, y0, h, colour, openings, lambda a, b, y_lo, y_hi: box(x - t / 2, y_lo, a, x + t / 2, y_hi, b, colour, kind=kind))


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
# What each building's doors look like (owner: doors fit their building): a model in assets/models/props/door_<look>.glb
# (art_source/scripts/make_door.py). Places match without their number; anything else gets DOOR_DEFAULT.
DOOR_LOOKS = {"GasStationTown": "metal", "GasStation": "metal", "Shops": "metal", "Grocery": "metal",
              "GunStore": "metal", "Diner": "metal", "TrainStation": "metal", "Depot": "metal",
              "Police": "office", "Bank": "office", "TownHall": "office", "Offices": "office", "Pharmacy": "office",
              "School": "school", "Cabin": "plank", "Barn": "plank", "Shed": "plank"}
DOOR_DEFAULT = "wood"
# School doors (owner, 2026-10-13: the navy-and-oak door and a plain oak one, each where it makes sense): navy on the
# pupils' rooms, plain oak on the staff and quiet rooms. Rooms (floor, i, j) are 10 x 8 m from map (8, 50).
SCHOOL_OAK_ROOMS = {(0, 0, 0), (0, 0, 2), (0, 2, 2), (1, 1, 2), (1, 2, 2)}  # library, nurse, staff lounge, principal, store


def school_door_look(x, y, z, yaw):
    """Plain oak when either side of the doorway is a staff/quiet room, else the navy classroom door."""
    f = int(y >= FLOOR_H - 0.5)
    sides = ((x - 1, z), (x + 1, z)) if yaw == 90.0 else ((x, z - 1), (x, z + 1))
    rooms = {(f, max(0, min(2, int((sx - 8) // 10))), max(0, min(2, int((sz - 50) // 8)))) for sx, sz in sides}
    return "school_oak" if rooms & SCHOOL_OAK_ROOMS else "school"
# How inner doorways turn out (cumulative): ~20% no door, ~15% a leaf on the floor, ~12% hanging off, the rest work.
DOOR_FATES = {"gone": 0.20, "fallen": 0.35, "hanging": 0.47}


def inner_door(x, y, z, yaw, place):
    """A door in an inner doorway (World art 0.17, owner: doors to open and shut). Outside doorways stay open
    (smashed in). Doorways that already have a key door get none (see write_scene)."""
    # Round 3 (owner: "not every doorway needs a door"): some doorways have none, some a wrecked one (lying on the
    # floor or hanging off a hinge: scripts/door.gd `broken`), the rest work. Fixed per doorway (seeded by its place).
    fate = random.Random(f"door{x:.1f},{y:.1f},{z:.1f}").random()
    if fate < DOOR_FATES["gone"]:
        return
    broken = "fallen" if fate < DOOR_FATES["fallen"] else "hanging" if fate < DOOR_FATES["hanging"] else ""
    hx0, hz0, hx1, hz1 = BUNKER_HOLE
    if broken and y < 1.0 and hx0 - 1 < x < hx1 + 1 and hz0 - 3 < z < hz1 + 3:
        broken = ""   # (owner: a wrecked leaf would lie on the bunker ramp's ghost runner, floating over the hole)
    if broken == "hanging" and place.startswith("BigHouse"):
        return   # (round 11, owner: a door hanging off its hinge across the hall read as a rail blocking the way in)
    n = sum(1 for m in markers if m[0] == "Doors") + 1
    look = DOOR_LOOKS.get(re.sub(r"\d+$", "", place), DOOR_DEFAULT)
    if place == "School":
        look = school_door_look(x, y, z, yaw)
    markers.append(("Doors", f"Door{n}", x, y, z, {"yaw": yaw, "width": INNER_DOOR_W, "place": place, "look": look,
                                                   "broken": broken}))


class Building:
    """A rectangular building: `floors` storeys, rooms in an nx x nz grid with doorways between all neighbours,
    windows in every outside room wall, ramps (stairs) between storeys, optional flat roof you can walk on."""

    def __init__(self, name, x, y, w, d, floors=1, colour="wall", rooms=(2, 2), doors="S", roof=False,
                 height=FLOOR_H, solid_inner=(), no_windows=(), big_doors=False, blasts=(), caved=(), shopfronts="",
                 open_plan=False, roof_ramp=None, wall_openings=None, stairs=True, spawn_spots=None, walled_stairs=False):
        self.name, self.x0, self.z0, self.x1, self.z1 = name, x, y, x + w, y + d
        self.floors, self.colour, self.nx, self.nz = floors, colour, rooms[0], rooms[1]
        self.doors, self.roof, self.h = doors, roof, height
        self.solid_inner = set(solid_inner)   # interior wall segments with no doorway: ("v"|"h", i, j)
        self.no_windows = set(no_windows)     # rooms (i, j) whose outside walls get no windows
        self.big_doors = big_doors
        # War damage (owner, 0.11.6): blasts = blown-out holes in outside walls, (floor, side, k) with k the room
        # along that wall; caved = rooms (i, j) whose roof fell in. Rubble and scorch marks come with them.
        self.blasts, self.caved = set(blasts), set(caved)
        # Shopfronts (World art 0.17, owner): on these sides every ground-floor room gets its own door and a big shop
        # window instead of the usual window.
        self.shopfronts = shopfronts
        # Grocery (World art 0.17): open_plan = no grid of inner walls (the building draws its own); roof_ramp "NE" =
        # the roof stairs along the north wall, landing at the east end; wall_openings = {side: [(kind, mid, w, lo,
        # hi)]} replaces the ground floor's made-up openings on that side (blasts included, by hand).
        self.open_plan, self.roof_ramp, self.wall_openings = open_plan, roof_ramp, wall_openings or {}
        # Motel (World art 0.17): wall_openings may also give an upper storey's openings, keyed (side, storey);
        # stairs=False = no stairs inside (the building makes its own outside); spawn_spots = the indoor AI spawn
        # spots [(x, z)] instead of the ground-floor rooms' middles.
        self.stairs, self.spawn_spots = stairs, spawn_spots
        # walled_stairs (World art 0.17, owner 2026-10-17: "wrap the wall around the stairs", nothing behind them): the
        # ramp gets a wall up its open side on both storeys and across its low end upstairs instead of rails, so the
        # stairwell is its own space, entered at its foot and left at its landing; the outside wall beside it gets no
        # window downstairs (the space under the landing is shut in).
        self.walled_stairs = walled_stairs
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
        for f in range(storeys - 1 if self.stairs else 0):
            self.ramps.append((f, (self.roof_ramp or "S") if f == self.floors - 1 else "N"))
        self.strips = []
        for f, wall in self.ramps:
            if wall == "N":
                self.strips.append((self.x0, self.x0 + WALL_T / 2 + LANDING + self._ramp_len() + 1.8, self.z0, self.z0 + WALL_T / 2 + RAMP_W))
            elif wall == "NE":
                self.strips.append((self.x1 - WALL_T / 2 - LANDING - self._ramp_len() - 1.8, self.x1, self.z0, self.z0 + WALL_T / 2 + RAMP_W))
            else:
                self.strips.append((self.x1 - WALL_T / 2 - LANDING - self._ramp_len() - 1.8, self.x1, self.z1 - WALL_T / 2 - RAMP_W, self.z1))
        box(self.x0, 0.0, self.z0, self.x1, 0.03, self.z1, "slab", solid=False)   # ground floor (looks only)
        for f in range(self.floors):
            y = f * self.h
            self._outer_walls(f, y)
            if not self.open_plan:
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
            openings, kinds = [], []
            own = self.wall_openings.get(side if f == 0 else (side, f))
            for kind, mid, w, lo, hi in (own or ()):
                openings.append((mid, w, lo, hi))
                kinds.append(kind)
            for k in (range(0) if own is not None else range(n)):
                cell = (k, 0 if side == "N" else self.nz - 1) if horizontal else (0 if side == "W" else self.nx - 1, k)
                a0, a1 = (self.x0 + k * self.cw, self.x0 + (k + 1) * self.cw) if horizontal else \
                         (self.z0 + k * self.cd, self.z0 + (k + 1) * self.cd)
                mid = (a0 + a1) / 2
                if (f, side, k) in self.blasts:
                    assert not (f == 0 and side in self.doors and k == n // 2), f"{self.name}: blast on the door"
                    assert not self._ramp_blocks(f, side, cell), f"{self.name}: blast behind the stairs"
                    w = min(3.4, a1 - a0 - 0.6)
                    openings.append((mid, w, 0.0 if f == 0 else 0.5, self.h if f == self.floors - 1 else self.h - 0.6))
                    kinds.append("blast")
                elif f == 0 and side in self.shopfronts:
                    openings.append((mid - 1.6, SHOP_WIN_W, SHOP_WIN_LO, SHOP_WIN_HI))
                    openings.append((mid + 2.2, DOOR_W, 0.0, DOOR_H))
                    kinds += ["shop_window", "door"]
                elif f == 0 and side in self.doors and k == n // 2:
                    if self.big_doors:
                        openings.append((mid, min(4.0, a1 - a0 - 1.0), 0.0, 4.0))
                        kinds.append("big_door")
                    else:
                        openings.append((mid, DOOR_W, 0.0, DOOR_H))
                        kinds.append("door")
                elif cell not in self.no_windows and a1 - a0 >= 2.6 and not self._ramp_blocks(f, side, cell) and \
                        not (self.walled_stairs and f == 0 and side == "W" and cell[1] == 0):
                    openings.append((mid, WIN_W, WIN_LO, WIN_HI))
                    kinds.append("window")
            for (c, w, lo, hi), kind in zip(openings, kinds):
                at = (self.z0 if side == "N" else self.z1) if horizontal else (self.x0 if side == "W" else self.x1)
                note_opening(kind, side, at, c, w, y + lo, y + hi)
            if horizontal:
                wall_x(self.x0, self.x1, self.z0 if side == "N" else self.z1, y, self.h, self.colour, openings)
            else:
                wall_z(self.z0, self.z1, self.x0 if side == "W" else self.x1, y, self.h, self.colour, openings)

    def _ramp_blocks(self, f, side, cell):
        # No windows behind the ramps.
        x0, _, x1, _ = self.cell(*cell)
        for (rf, wall), (sx0, sx1, _, _) in zip(self.ramps, self.strips):
            if side == wall[0] and rf in (f, f - 1) and x0 < sx1 and x1 > sx0:
                return True
        return False

    def _inner_walls(self, y):
        h = self.h
        for i in range(1, self.nx):          # walls along z at x = x0 + i*cw
            x = self.x0 + i * self.cw
            for j in range(self.nz):
                # Inner walls meet with no gap (refine pass, owner: "gaps between the walls"): walls along z run
                # through the crossings (to the far face of the 0.2 m wall along x), walls along x stop at their faces.
                a0 = self.z0 + j * self.cd + (WALL_T / 2 if j == 0 else -0.1)
                a1 = self.z0 + (j + 1) * self.cd - (WALL_T / 2 if j == self.nz - 1 else -0.1)
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
                if op:
                    inner_door(x, y, (a0 + a1) / 2, 90.0, self.name)
        for j in range(1, self.nz):          # walls along x at z = z0 + j*cd
            z = self.z0 + j * self.cd
            for i in range(self.nx):
                a0, a1 = self.x0 + i * self.cw, self.x0 + (i + 1) * self.cw
                op = [] if ("h", i, j) in self.solid_inner else [((a0 + a1) / 2, INNER_DOOR_W, 0.0, DOOR_H)]
                wall_x(a0 + (WALL_T / 2 if i == 0 else 0.1), a1 - (WALL_T / 2 if i == self.nx - 1 else 0.1), z, y, h,
                       self.colour, op, t=0.2)
                if op:
                    inner_door(((a0 + a1) / 2), y, z, 0.0, self.name)

    def _ramp(self, f, wall):
        """A ramp up from storey f to f+1 in the strip along the `wall` (N: climbs west to a landing in the north-west
        corner; S: climbs east to a landing in the south-east corner)."""
        length = self._ramp_len()
        if wall == "N":
            rz0 = self.z0 + WALL_T / 2
            hi_x = self.x0 + WALL_T / 2 + LANDING
            lo_x = hi_x + length
        elif wall == "NE":
            rz0 = self.z0 + WALL_T / 2
            hi_x = self.x1 - WALL_T / 2 - LANDING
            lo_x = hi_x - length
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
        if self.walled_stairs and wall == "N":
            iw = 0.2
            xs = [self.x0 + i * self.cw for i in range(1, self.nx)]           # (stop at the inner walls along z)

            def run(a0, a1, ya, yb):
                cuts = [a0] + [c for x in xs if a0 < x < a1 for c in (x - 0.1, x + 0.1)] + [a1]
                for c0, c1 in zip(cuts[::2], cuts[1::2]):
                    if c1 - c0 > 0.02:
                        box(c0, ya, rz1, c1, yb, rz1 + iw, "wall")
            run(self.x0 + WALL_T / 2, hx1 + iw, y0, y1 - SLAB_T)                 # downstairs: up its side to the foot
            run(hx0, hx1 + iw, y1, y1 + self.h - SLAB_T)                          # upstairs: round the hole
            box(hx1, y1, rz0, hx1 + iw, y1 + self.h - SLAB_T, rz1, "wall")
            return
        # Rails round the hole upstairs (its open side and its low end), so nobody walks off the edge.
        rail_z = rz1 + 0.05 if wall[0] == "N" else rz0 - 0.05
        box(hx0, y1, rail_z - 0.05, hx1, y1 + 1.0, rail_z + 0.05, "metal", people=True)
        if wall == "N":
            box(hx1, y1, rz0, hx1 + 0.1, y1 + 1.0, rz1, "metal", people=True)
        else:
            box(hx0 - 0.1, y1, rz0, hx0, y1 + 1.0, rz1, "metal", people=True)

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
            # scorch round the hole (not over it), and jagged bits of wall hanging into it. A modeled building draws
            # its own broken edges, scorch and rubble (round 4, owner: "make the broken wall proper"): only the rubble
            # heaps' collision stays, under kind "rubble_heap"/"rubble" so the model draws them where they lie.
            modeled_here = bool(_model) and _model[-1] is not None
            hw = min(3.4, (self.cw if horizontal else self.cd) - 0.6) / 2
            for sgn in (-1, 1):
                jx, jz = at(sgn * (hw - 0.3), 0)
                jh = rng.uniform(0.25, 0.5) * self.h
                if modeled_here:
                    continue
                face(sgn * (hw + 0.6), y + self.h * 0.45, 1.2, self.h * 0.8)
                obox(jx, y + self.h - jh / 2, jz, 0.6 if horizontal else WALL_T, jh, WALL_T if horizontal else 0.6, 0,
                     self.colour)
            if f < self.floors - 1 and not modeled_here:
                face(0, y + self.h - 0.35, 2 * hw, 0.6)
            with (contextlib.nullcontext() if modeled_here else unmodeled()):
                # (gray box: outside, off the building's pad, stays gray box until the ground gets its art)
                for _ in range(rng.randint(5, 8)):   # chunks blown out onto the ground
                    px, pz = at(rng.uniform(-3, 3), rng.uniform(1.0, 4.5))
                    w, h, d = rng.uniform(0.4, 1.3), rng.uniform(0.2, 0.6), rng.uniform(0.4, 1.3)
                    # Big chunks block you, small ones you walk over (owner, world art round 8).
                    big = max(w, d) >= 0.9 and h >= 0.35
                    obox(px, h / 2, pz, w, h, d, rng.uniform(0, 90), rng.choice((self.colour, "concrete", "scorch")),
                         solid=big, kind="rubble" if modeled_here else None)
                for sgn in (-1, 1):                    # a solid heap each side of the hole (cover)
                    px, pz = at(sgn * rng.uniform(2.6, 3.4), rng.uniform(1.4, 2.4))
                    obox(px, 0.45, pz, rng.uniform(1.4, 2.2), 0.9, rng.uniform(1.0, 1.6), rng.uniform(0, 90), self.colour,
                         kind="rubble_heap" if modeled_here else None)
        top = (self.floors - 1) * self.h
        modeled_here = bool(_model) and _model[-1] is not None
        for i, j in sorted(self.caved):
            cx0, cz0, cx1, cz1 = self.cell(i, j)
            cx, cz = (cx0 + cx1) / 2, (cz0 + cz1) / 2
            if modeled_here:
                # A modeled building draws its own wreckage for the room (owner: each caved room its own look);
                # this marks the room (picture only, like the gray-box pieces below).
                box(cx0, top, cz0, cx1, top + 0.05, cz1, "scorch", solid=False, kind="caved_room")
                continue
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
            # (but not out through the end wall: a 5 m room's 2.4 m slide put OldHouse6's dresser half outside)
            wall_len = self.cw if horizontal else self.cd
            offset = min(2.4, wall_len / 2 - 0.7) * (1 if offset >= 0 else -1)
        if side == "E":
            return cx1 - 0.7, y, (cz0 + cz1) / 2 + offset, 90.0
        if side == "W":
            return cx0 + 0.7, y, (cz0 + cz1) / 2 + offset, -90.0
        if side == "S":
            return (cx0 + cx1) / 2 + offset, y, cz1 - 0.6, 0.0
        return (cx0 + cx1) / 2 + offset, y, cz0 + 0.6, 180.0


def classroom(x0, z0, y, lab=False):
    """A 10 x 8 m school room (World art 0.17): board and teacher's desk at the north wall, desks (or lab benches)
    in the four corners so the cross between the doorways and the middle (AI spawn spot) stay clear."""
    x1, z1 = x0 + 10, z0 + 8
    mx = x0 + 5
    box(x0 + 0.6, y + 1.0, z0 + 0.15, x0 + 3.6, y + 2.2, z0 + 0.2, "wood", solid=False, kind="chalkboard")
    box(x0 + 1.0, y, z0 + 1.2, x0 + 2.5, y + 0.78, z0 + 2.0, "wood", kind="teacher_desk")
    if lab:
        for zz in (z0 + 2.0, z0 + 5.5):
            for xa in (x0 + 1.2, mx + 1.2):
                box(xa, y, zz, xa + 2.6, y + 0.95, zz + 0.8, "metal", kind="lab_bench")
        return
    for zz in (z0 + 2.4, z0 + 5.2, z0 + 6.5):
        for xa in (x0 + 1.2, x0 + 2.7, mx + 1.4, mx + 2.9):
            box(xa, y, zz, xa + 0.9, y + 0.75, zz + 0.55, "wood", kind="school_desk")


def school_furniture():
    """The school's rooms (World art 0.17). Rooms are 10 x 8 m: x 8 / 18 / 28 / 38, z 50 / 58 / 66 / 74.
    Furniture keeps to the room corners, so the paths between the doorways and the room middles (AI spawn spots)
    stay clear (refine pass, owner: "some of the rooms are just not furnished properly")."""
    F = FLOOR_H
    # Ground floor: library (under the stairs), two classrooms and a science lab, the cafeteria, the locker hall,
    # the nurse's room, the lobby and the staff lounge.
    box(8.15, 0, 54.8, 8.6, 1.9, 57.7, "wood", kind="wall_books")              # library: bookcases on the walls
    box(8.8, 0, 57.4, 11.6, 1.9, 57.85, "wood", kind="wall_books")
    box(14.4, 0, 57.4, 17.6, 1.9, 57.85, "wood", kind="wall_books")
    box(17.4, 0, 55.3, 17.85, 1.9, 57.2, "wood", kind="wall_books")
    box(14.2, 0, 55.6, 16.6, 1.8, 56.1, "wood", kind="bookshelf")
    box(9.6, 0, 55.3, 11.8, 0.75, 56.1, "wood", kind="reading_table")
    box(8.4, 0, 50.15, 10.2, 0.78, 50.85, "wood", kind="desk")                 # the librarian's desk, under the landing
    classroom(18, 50, 0)
    classroom(28, 50, 0, lab=True)
    classroom(28, 58, 0)
    box(8.3, 0, 59.3, 11.8, 0.9, 60.1, "metal", kind="serving_counter")        # cafeteria (round 5: room to walk behind)
    for xa, zz in ((9.0, 61.6), (14.0, 59.5), (9.0, 63.7), (14.0, 63.7)):
        box(xa, 0, zz, xa + 3.0, 0.75, zz + 0.8, "wood", kind="caf_table")
    for za, zb in ((58.1, 58.6), (65.4, 65.9)):
        for xa, xb in ((18.3, 21.8), (24.2, 27.7)):
            box(xa, 0, za, xb, 2.0, zb, "metal", kind="hall_lockers")
    box(19.0, 0, 66.15, 21.6, 1.9, 66.6, "wood", kind="trophy_case")           # lobby
    box(24.8, 0, 73.2, 27.2, 0.45, 73.7, "wood", kind="hall_bench")
    box(18.8, 0, 73.2, 21.2, 0.45, 73.7, "wood", kind="hall_bench")            # entrance: benches, plants by the doors
    box(21.4, 0, 73.3, 21.8, 1.2, 73.7, "wood", kind="plant")
    box(24.2, 0, 73.3, 24.6, 1.2, 73.7, "wood", kind="plant")
    box(8.4, 0, 71.0, 10.4, 0.6, 73.6, "metal", kind="cot")                    # nurse
    box(8.4, 0, 66.5, 10.4, 0.6, 69.0, "metal", kind="cot")
    box(14.5, 0, 66.2, 17.0, 1.9, 66.6, "metal", kind="med_cabinet")
    box(14.0, 0, 72.8, 15.5, 0.75, 73.6, "wood", kind="desk")
    box(16.6, 0, 73.3, 17.15, 1.3, 73.8, "metal", kind="file_cabinet")
    box(34.3, 0, 66.2, 36.9, 0.9, 66.8, "wood", kind="kitchenette")            # staff lounge
    box(37.0, 0, 66.2, 37.8, 1.8, 66.9, "metal", kind="home_fridge")
    box(28.4, 0, 66.2, 29.4, 1.8, 67.0, "metal", kind="vending")
    box(28.5, 0, 73.0, 31.3, 0.9, 73.85, "wood", kind="sofa")
    box(29.3, 0, 71.9, 30.7, 0.45, 72.5, "wood", kind="coffee_table")
    box(34.8, 0, 71.8, 36.0, 0.75, 73.0, "wood", kind="lounge_table")
    # Upstairs: art room, three classrooms, the computer room, the locker hall, the principal's office, the store room.
    box(10.0, F, 55.0, 12.5, F + 0.8, 56.2, "wood", kind="art_table")
    box(14.0, F, 55.0, 16.5, F + 0.8, 56.2, "wood", kind="art_table")
    box(8.15, F, 54.8, 8.6, F + 1.8, 57.7, "wood", kind="art_shelf")
    box(17.25, F, 50.3, 17.85, F + 0.9, 52.6, "wood", kind="sink_counter")
    box(16.4, F, 56.8, 17.0, F + 1.6, 57.3, "wood", kind="easel")
    box(9.4, F, 56.9, 10.0, F + 1.6, 57.4, "wood", kind="easel")
    classroom(18, 50, F)
    classroom(28, 50, F)
    classroom(28, 58, F)
    classroom(8, 66, F)
    for za, zb in ((58.15, 58.85), (65.15, 65.85)):
        for xa, xb in ((9.0, 12.0), (14.0, 17.0)):
            box(xa, F, za, xb, F + 0.75, zb, "wood", kind="computer_desk")
    for za, zb in ((58.1, 58.6), (65.4, 65.9)):
        for xa, xb in ((18.3, 21.8), (24.2, 27.7)):
            box(xa, F, za, xb, F + 2.0, zb, "metal", kind="hall_lockers")
    box(24.4, F, 71.5, 26.4, F + 0.78, 72.4, "wood", kind="principal_desk")    # the principal's office (owner)
    box(23.9, F, 70.6, 27.4, F + 0.02, 73.2, "wood", solid=False, kind="rug")
    box(24.6, F, 73.4, 27.6, F + 2.0, 73.85, "wood", kind="wall_books")
    box(18.35, F, 66.2, 18.9, F + 1.3, 66.7, "metal", kind="file_cabinet")
    box(19.0, F, 66.2, 19.55, F + 1.3, 66.7, "metal", kind="file_cabinet")
    box(21.2, F, 66.25, 21.6, F + 1.2, 66.65, "wood", kind="plant")
    box(24.6, F, 66.2, 27.4, F + 0.9, 67.0, "wood", kind="sofa")
    box(25.3, F, 67.6, 26.7, F + 0.45, 68.1, "wood", kind="coffee_table")
    box(18.3, F, 71.4, 19.5, F + 0.75, 72.6, "wood", kind="corner_table")      # (round 8: off the filing cabinet)
    box(28.5, F, 66.3, 31.0, F + 2.0, 66.9, "metal", kind="rack")
    box(34.8, F, 66.3, 37.3, F + 2.0, 66.9, "metal", kind="rack")


# The rich houses on the hill (World art 0.17, owner: "similar to each other" with switches so each shows the people
# who lived there). One shared house: living room with a fireplace (chimney up the west wall) SW, entrance hall and
# dining room SE (front door, porch), kitchen NE, a den NW by the stairs; upstairs a landing hall NW, a bedroom SW,
# the main bedroom NE and one more room SE. Who lived there switches the den, the SE room upstairs and the small
# things: "doctor" (old money: library, study, the safe), "family" (young kids and a dog: playroom, nursery),
# "officer" (an Exion officer, his wife and a teenager: trophy den, music room). Furniture keeps to the corners,
# off the windows and doorways, so the room middles (AI spawns) and door paths stay clear.
RICH_HOUSES = [(30, 22, 16, 13, "doctor"), (68, 36, 15, 12, "family"), (100, 32, 15, 12, "officer")]


# The barn (World art 0.17, owner 2026-10-17 "do all the buildings in the farm"): stalls down the west side under a
# hayloft (a ladder up, a hay door high in the west wall; BARN_LOFT, put to the owner), the tractor bay and the
# workbench on the east side, the middle and both big doors clear. The four hay bales stay where they were (cover).
BARN_LOFT = True


def ladder(x, y, z, yaw, height, place):
    """A ladder (scripts/ladder.gd, 0.13.5): foot at (x, y, z), leaning on what's behind it (-Z after `yaw`)."""
    n = sum(1 for m in markers if m[0] == "Ladders") + 1
    markers.append(("Ladders", f"Ladder{n}", x, y, z, {"yaw": yaw, "height": height, "place": place}))


SILO = (296.0, 30.0)          # the silo's middle (map)
SHED_SHIFT = (2.0, 16.0)      # the machine shed, moved south from its old spot by the barn


def farm_barn():
    with modeled("barn", 268.0, 35.0):
        west = [("window", 29.0, 1.0, 1.6, 2.4), ("window", 41.0, 1.0, 1.6, 2.4)]
        if BARN_LOFT:
            west.append(("hay_door", 35.0, 2.2, 3.5, 5.4))
        build(Building("Barn", 256, 26, 24, 18, colour="wall_farm", rooms=(1, 1), doors="SN", height=6.0,
                       big_doors=True, wall_openings={"W": west}), [("crate", 0, 0, 0, "E", 0), ("crate", 0, 0, 0, "W", 2)])
        for hx, hz in ((262, 31), (262, 33.5), (274, 39), (270, 30)):
            box(hx - 1.0, 0, hz - 0.7, hx + 1.0, 1.2, hz + 0.7, "hay", kind="hay_bales")
        for z in (30.6, 35.0, 39.4):                                       # stalls: low board walls, gates
            box(256.15, 0, z - 0.06, 259.7, 1.4, z + 0.06, "wood", kind="stall_wall")
        for za, zb in ((26.15, 30.6), (30.6, 35.0), (35.0, 39.4), (39.4, 43.85)):
            box(259.65, 0, za + 0.1, 259.75, 1.2, zb - 0.1, "wood", kind="stall_gate", solid=False)
        box(275.6, 0, 27.4, 278.9, 2.6, 32.6, "metal", kind="farm_tractor")
        box(279.1, 0, 37.0, 279.85, 0.92, 40.2, "wood", kind="barn_bench")
        box(278.4, 0, 42.2, 279.8, 0.95, 43.8, "metal", kind="fuel_drums")
        if BARN_LOFT:
            box(256.15, 2.8, 26.15, 262.0, 3.0, 43.85, "wood", kind="loft_floor")
            box(261.9, 3.0, 26.15, 262.0, 4.0, 34.4, "wood", kind="loft_rail")
            box(261.9, 3.0, 35.6, 262.0, 4.0, 43.85, "wood", kind="loft_rail")
            for z in (28.3, 41.7):
                box(261.82, 0, z - 0.1, 262.02, 2.8, z + 0.1, "wood", kind="loft_post")
            box(256.4, 3.0, 26.5, 258.4, 4.2, 29.0, "hay", kind="hay_bales")
            box(256.4, 3.0, 41.0, 258.0, 3.6, 43.5, "hay", kind="hay_bales")
            ladder(262.12, 0.0, 35.0, -90.0, 3.0, "Barn")   # (leans west, on the loft)


def rich_house(n, x, y, w, d, who, model=None, place=None, loot=None, colour="wall_rich"):
    """model/place/loot: the farmhouse (World art 0.17, "farmer") is the same house on the farm, its own loot."""
    hw, hd = w / 2, d / 2
    ox, oz = x + hw, y + hd
    F = FLOOR_H
    wx, dz = hw - WALL_T / 2, hd - WALL_T / 2      # inside faces of the outside walls (local)
    q, r = w / 4, d / 4                            # room middles
    strip = -hw + WALL_T / 2 + LANDING + RAMP_L + 1.8   # east end of the stair corridor along the north wall
    sz = -hd + WALL_T / 2 + RAMP_W                 # its south edge

    def put(kind, x0, z0, x1, z1, h, floor=0, solid=True, colour="wood", y=0.0):
        box(ox + x0, floor * F + y, oz + z0, ox + x1, floor * F + y + h, oz + z1, colour, solid=solid, kind=kind)
    with modeled(model or f"big_house_{n}", ox, oz):
        build(Building(place or f"BigHouse{n}", x, y, w, d, floors=2, colour=colour, rooms=(2, 2), doors="S"), loot or [
            ("locker", 1, 1, 0, "E", 1.9), ("crate", 0, 1, 1, "W", -1.9), ("locker", 1, 0, 1, "E", 1.9)])   # (off the windows)
        # The stairs are walled off from the den (round 11, owner: the open side "looks super off").
        box(ox - wx, 0.0, oz + sz, ox - 0.1, F - SLAB_T, oz + sz + 0.15, "wall_rich")
        put("fireplace", -wx, 0.35, -wx + 0.55, 1.95, 1.25, colour="concrete")
        put("chimney", -hw - 0.85, 0.45, -hw - WALL_T / 2, 1.85, 2 * F + 2.4, colour="concrete")
        put("shoe_bench", 0.35, dz - 0.45, 1.9, dz - 0.05, 0.5)
        put("home_fridge", wx - 0.8, -dz, wx - 0.05, -dz + 0.7, 1.8, colour="metal")
        # Each house its own ground floor (round 11, owner: "they all got the exact same setup, mix them up").
        if who == "doctor":
            # Living room (SW): sofa under the south wall, coffee table, TV; dining table by the east wall; kitchen
            # table by the window.
            put("house_sofa", -wx + 0.25, dz - 0.9, -q - 0.85, dz - 0.05, 0.9)
            put("coffee_table", -wx + 0.75, dz - 2.0, -q - 1.35, dz - 1.4, 0.45)
            put("house_rug", -wx + 0.4, dz - 2.7, -q - 0.4, dz - 0.95, 0.02, solid=False)
            put("armchair", -1.05, dz - 1.05, -0.25, dz - 0.25, 0.95)
            put("tv_stand", -0.6, 0.4, -0.15, 1.6, 0.55)
            put("dining_table", wx - 2.6, 0.45, wx - 0.2, 2.35, 0.9)
            put("kitchen_run", strip + 1.2, -dz, wx - 0.85, -dz + 0.6, 0.9)   # (clear of the stairs' foot: AI paths)
            put("kitchen_table", wx - 2.55, -2.15, wx - 0.45, -0.45, 0.85)
        elif who == "family":
            # The sofa faces the fire, its back to the room; a big kitchen table in the middle of the kitchen; the
            # dining table turned long-ways under the south window.
            put("house_sofa", -2.9, 0.7, -2.05, 3.3, 0.9)
            put("coffee_table", -5.2, 1.3, -4.4, 2.7, 0.45)
            put("house_rug", -6.3, 0.6, -3.3, 3.4, 0.02, solid=False)
            put("armchair", -wx + 0.3, dz - 1.1, -wx + 1.1, dz - 0.3, 0.95)
            put("dining_table", q + 0.9, 1.6, wx - 0.3, 3.4, 0.9)
            put("kitchen_run", strip + 1.2, -dz, wx - 0.85, -dz + 0.6, 0.9)
            put("kitchen_table", q - 1.1, -3.5, q + 1.1, -2.1, 0.85)
        elif who == "farmer":
            # The farm kitchen is the big room: a long table by the window, the range; the living room keeps the
            # sofa under the window, the TV by the fire.
            put("house_sofa", -wx + 0.25, dz - 0.9, -q - 0.85, dz - 0.05, 0.9)
            put("coffee_table", -wx + 0.75, dz - 2.0, -q - 1.35, dz - 1.4, 0.45)
            put("house_rug", -wx + 0.4, dz - 2.7, -q - 0.4, dz - 0.95, 0.02, solid=False)
            put("armchair", -1.05, dz - 1.05, -0.25, dz - 0.25, 0.95)
            put("tv_stand", -0.6, 0.4, -0.15, 1.6, 0.55)
            put("dining_table", wx - 2.6, 0.45, wx - 0.2, 2.35, 0.9)
            put("kitchen_run", strip + 1.2, -dz, wx - 0.85, -dz + 0.6, 0.9)
            put("kitchen_table", wx - 1.5, -4.9, wx - 0.3, -3.0, 0.85)
        else:
            # A formal room: the sofa and two armchairs round the fire, no TV; a long dining table by the east wall; the kitchen's cupboards round the corner and its table by the hall door.
            put("house_sofa", -wx + 1.5, dz - 0.9, -1.4, dz - 0.05, 0.9)
            put("house_rug", -wx + 0.9, 0.5, -2.6, dz - 1.1, 0.02, solid=False)
            put("armchair", -wx + 0.9, 2.3, -wx + 1.7, 3.1, 0.95)
            put("armchair", -2.6, 1.2, -1.8, 2.0, 0.95)
            put("coffee_table", -5.3, 2.0, -4.5, 3.0, 0.45)
            put("dining_table", wx - 2.6, 0.6, wx - 0.2, 2.6, 0.9)
            put("kitchen_run", strip + 1.2, -dz, wx - 0.85, -dz + 0.6, 0.9)
            put("kitchen_table", wx - 1.6, -3.4, wx - 0.3, -1.0, 0.85)
        # Upstairs. Landing hall (NW): a bookcase. Bedroom (SW): the bed against the south wall. Main bedroom (NE):
        # the bed against the north wall with its night stands.
        put("wall_books", -wx + 0.2, -0.55, -q - 1.2, -0.1, 1.9, floor=1)
        put("house_bed", -2.3 if who != "doctor" else -2.4, dz - 2.0, -0.8, dz, 0.9, floor=1)
        put("main_bed", wx - 3.1, -dz, wx - 0.5, -dz + 2.1, 1.1, floor=1)
        if who != "doctor":   # (the doctor's safe is on that wall)
            put("vanity", strip + 1.6, -dz, strip + 2.7, -dz + 0.5, 0.8, floor=1)   # (east of the bathroom door)
        # The bathroom (owner, 2026-10-16): the main bedroom's north-west corner, against the stairwell rail (it
        # closes the gap there between the landing and the bedroom). A bath, the toilet, a basin; door on the east.
        bx0 = strip - 1.55
        washroom(ox, oz, bx0, -dz, bx0 + 2.45, sz - WC_T, "WSE", ("E", (sz - WC_T - dz) / 2 - 0.15, 1), y=F, fit=(
            ("wc_bath", "N", bx0 + 0.8, 1.55, 0.7, 0.55), ("wc_sink", "N", bx0 + 2.1, 0.5, 0.45, 0.9),
            ("wc_toilet", "S", bx0 + 0.45, 0.45, 0.72, 0.85)))
        # Front porch: a roof on two posts over the door, a step.
        put("porch_post", q - 1.6, hd + 1.35, q - 1.4, hd + 1.55, 2.75, colour="wood")
        put("porch_post", q + 1.4, hd + 1.35, q + 1.6, hd + 1.55, 2.75, colour="wood")
        if who == "farmer":
            # The farmhouse's own front (owner, 2026-10-17: "give it some pazazz"): a veranda the whole width of
            # the house on more posts, two rocking chairs by the living room window.
            for px in (-hw + 0.15, -4.0, -0.75, hw - 0.15):
                put("porch_post", px - 0.1, hd + 1.35, px + 0.1, hd + 1.55, 2.75, colour="wood")
            put("porch", -hw - 0.1, hd + WALL_T / 2, hw + 0.1, hd + 1.7, 0.1, solid=False, colour="concrete")
            for cx in (-6.3, -5.2):
                put("porch_chair", cx - 0.32, hd + 0.45, cx + 0.32, hd + 1.15, 1.0)
        else:
            put("porch", q - 1.75, hd + WALL_T / 2, q + 1.75, hd + 1.7, 0.1, solid=False, colour="concrete")
        if who == "doctor":
            # Library den, a grandfather clock in the hall, a study upstairs (desk under the window, bookcases).
            put("wall_books", -wx, -dz + 0.3, -wx + 0.45, -r - 0.85, 1.9)
            put("wall_books", -wx + 0.3, -0.55, -q - 1.2, -0.1, 1.9)
            put("reading_chair", -wx + 0.75, -dz + 0.6, -wx + 1.65, -dz + 1.5, 1.0)
            put("globe", -2.0, -0.6, -1.45, -0.15, 1.0)
            put("grandfather_clock", 0.1, 0.4, 0.6, 0.9, 2.1)
            put("study_desk", wx - 1.8, dz - 0.85, wx - 0.2, dz - 0.1, 0.78, floor=1)
            put("wall_books", q + 1.2, 0.1, wx - 0.2, 0.55, 1.9, floor=1)
            put("trunk", -wx + 0.05, -2.3, -wx + 0.6, -1.3, 0.55, floor=1)
        elif who == "farmer":
            # The den is the boot room and pantry: boots and coats by the wall, jars and sacks on the shelves; the
            # kid's room upstairs (SW), the sewing and junk room (SE).
            put("pantry_shelf", -wx + 0.3, -0.55, -q - 1.2, -0.1, 1.9)
            put("boot_rack", -wx + 0.05, sz + 0.35, -wx + 0.5, sz + 1.85, 0.45)   # (south of the stair wall)
            put("coat_rack", -wx + 0.05, sz + 2.05, -wx + 0.35, sz + 2.95, 1.8, solid=False)
            put("feed_sacks", -4.4, sz + 0.2, -3.2, sz + 1.0, 0.7)
            put("toy_chest", -2.0 - 1.0, dz - 0.6, -2.0 - 0.4, dz - 0.05, 0.55, floor=1)
            put("sewing_table", wx - 1.7, dz - 0.75, wx - 0.2, dz - 0.15, 0.8, floor=1)
            put("trunk", q + 1.2, 0.1, q + 2.2, 0.65, 0.55, floor=1)
            put("junk_boxes", wx - 1.0, 0.1, wx - 0.1, 1.4, 1.2, floor=1)
        elif who == "family":
            # Playroom den, nursery upstairs, a little one's bedroom.
            put("toy_chest", -wx + 0.3, -dz + 0.3, -wx + 1.2, -dz + 0.85, 0.6)
            put("kid_table", -wx + 0.6, -1.95, -wx + 2.4, -0.35, 0.6)
            put("rocking_horse", -2.3, -3.45, -1.4, -3.05, 0.8)
            put("crib", wx - 1.45, dz - 0.75, wx - 0.2, dz - 0.1, 1.0, floor=1)
            put("changing_table", wx - 1.1, 0.15, wx - 0.2, 0.75, 0.95, floor=1)
            put("rocking_chair", 0.4, dz - 1.1, 1.15, dz - 0.3, 1.0, floor=1)
            put("toy_chest", -2.0 - 1.0, dz - 0.6, -2.0 - 0.4, dz - 0.05, 0.55, floor=1)
        else:
            # Trophy den (banner, medal case, the map table, his dress uniform), music room, the teenager's room.
            put("medal_case", -wx + 0.3, -0.55, -q - 1.2, -0.1, 1.6)
            put("map_table", -wx + 0.9, -2.2, -wx + 2.5, -1.2, 0.85)
            put("uniform_stand", -wx + 0.45, -dz + 0.4, -wx + 1.0, -dz + 0.95, 1.8)
            put("piano", q + 1.3, 0.1, q + 2.9, 1.1, 1.25, floor=1)
            put("record_cabinet", wx - 1.15, dz - 0.6, wx - 0.1, dz - 0.1, 0.85, floor=1)
            put("guitar_stand", 0.35, dz - 0.6, 0.85, dz - 0.15, 1.1, floor=1)
            put("teen_desk", -wx + 0.4, dz - 0.75, -wx + 1.8, dz - 0.1, 0.78, floor=1)
            put("sewing_table", -1.6, -0.6, -0.4, -0.1, 0.8, floor=1)
            put("flag_pole", q + 3.2, hd + 2.1, q + 3.3, hd + 2.2, 7.0, solid=False, colour="metal")


def offices_furniture(ox, oz):
    """Korven Engineering (World art 0.17), in the model's own coordinates (origin map (ox, oz), rooms 7.33 x 10.5 m,
    storeys 3 m). Desks, cabinets and machines are solid like everywhere else; the desk pods' low partitions are
    picture only (no new cover, owner rule). Room middles, doorways and the stairs' foot stay clear for the AI."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Ground floor. Reception (south-east, the front door): the front desk, waiting seats, a water cooler, plants.
    o(4.4, 0, 7.3, 6.8, 1.05, 8.0, "wood", "front_desk")
    o(10.3, 0, 0.45, 10.7, 1.3, 0.85, "metal", "water_cooler")
    o(10.25, 0, 1.5, 10.8, 0.85, 3.5, "metal", "waiting_seats", solid=False)
    o(4.0, 0, 0.4, 4.4, 1.3, 0.8, "wood", "plant", solid=False)
    o(10.3, 0, 9.7, 10.7, 1.3, 10.1, "wood", "plant", solid=False)
    # Open office (south middle): four desk pods, filing cabinets by the back wall.
    for x0, z0 in ((-3.2, 1.0), (1.5, 1.0), (-3.1, 7.3), (1.4, 7.3)):
        o(x0, 0, z0, x0 + 1.7, 0.75, z0 + 1.5, "wood", "office_pod")
    o(-3.4, 0, 9.7, -2.4, 1.3, 10.3, "metal", "file_cabinet")
    o(2.4, 0, 9.7, 3.4, 1.3, 10.3, "metal", "file_cabinet")
    # Copy and mail room (south-west): the photocopier, pigeonholes, a sorting table, paper stock.
    o(-6.0, 0, 0.4, -4.9, 1.1, 1.1, "metal", "photocopier")
    o(-4.17, 0, 7.2, -3.77, 1.8, 9.6, "wood", "pigeonholes")
    o(-6.2, 0, 9.0, -4.4, 0.9, 9.8, "wood", "mail_table")
    o(-10.7, 0, 1.0, -10.0, 0.9, 2.0, "wood", "paper_boxes")
    o(-10.6, 0, 9.85, -8.4, 1.8, 10.3, "metal", "paper_shelf")
    # Break room (north middle; the stairs' foot is its north-west corner): kitchenette, fridge, vending, a table.
    o(-0.2, 0, -10.35, 2.6, 0.9, -9.75, "wood", "kitchenette")
    o(2.75, 0, -10.35, 3.5, 1.8, -9.65, "metal", "home_fridge")
    o(2.77, 0, -9.3, 3.57, 1.8, -8.4, "metal", "vending")
    o(1.4, 0, -2.3, 2.8, 0.75, -1.3, "wood", "break_table")
    # Accounts (north-east): filing cabinets, two desk pods, a printer.
    o(4.0, 0, -10.35, 5.5, 1.3, -9.75, "metal", "file_cabinet")
    o(4.2, 0, -3.4, 5.9, 0.75, -1.9, "wood", "office_pod")
    o(8.7, 0, -3.4, 10.4, 0.75, -1.9, "wood", "office_pod")
    o(10.25, 0, -8.6, 10.85, 1.0, -7.8, "metal", "printer")
    # The blasted room (north-west): desks thrown over by the blast.
    o(-9.2, 0, -2.4, -7.6, 0.75, -1.6, "wood", "desk_over")
    o(-5.8, 0, -1.3, -4.2, 0.75, -0.5, "wood", "desk_over")
    # Upstairs. The manager's office (south-east): big desk at the window, bookcase, sofa, trophies, a globe.
    o(6.2, 3.0, 7.0, 8.0, 3.78, 7.8, "wood", "manager_desk")
    o(3.77, 3.0, 7.0, 4.17, 5.0, 9.0, "wood", "wall_books")
    o(4.0, 3.0, 0.2, 6.0, 3.85, 1.0, "wood", "sofa")
    o(8.6, 3.0, 0.1, 10.6, 4.8, 0.55, "wood", "trophy_case")
    o(9.9, 3.0, 1.2, 10.5, 4.2, 1.8, "wood", "globe", solid=False)
    # Meeting room (north-east): the long table (a whiteboard and a projector screen at its ends are dressing).
    o(5.4, 3.0, -8.8, 9.4, 3.76, -7.6, "wood", "meeting_table")
    # Archive (north middle): tall shelving with boxes and binders, more on the south wall.
    o(-2.85, 3.0, -9.9, -2.35, 5.2, -6.9, "metal", "archive_shelf")
    o(2.35, 3.0, -9.9, 2.85, 5.2, -6.9, "metal", "archive_shelf")
    o(-3.4, 3.0, -0.55, -1.4, 5.0, -0.1, "metal", "archive_shelf")
    o(1.4, 3.0, -0.55, 3.4, 5.0, -0.1, "metal", "archive_shelf")
    # Records (north-west, at the top of the stairs): cabinets on the west wall (clear of the landing), a desk pod.
    o(-10.85, 3.0, -1.9, -10.25, 4.3, -0.4, "metal", "file_cabinet")
    o(-6.0, 3.0, -2.1, -4.3, 3.75, -0.6, "wood", "office_pod")   # clear of the stairwell
    # Drawing office (south-west): the surveyors' drafting tables, a plan chest, crates of rock core samples.
    o(-10.5, 3.0, 1.0, -9.3, 3.95, 2.0, "wood", "drafting_table")
    o(-10.5, 3.0, 8.0, -9.3, 3.95, 9.0, "wood", "drafting_table")
    o(-6.0, 3.0, 0.3, -4.2, 3.9, 1.0, "wood", "plan_chest")
    o(-5.6, 3.0, 9.45, -4.0, 3.6, 10.25, "wood", "core_boxes")
    # Upstairs, the wall between the records room and the archive carries on past the stairwell (owner: the gap
    # behind the stair rail looked like a missing wall). Downstairs it stays open: that's the way onto the stairs.
    o(-3.767, 3.0, -10.35, -3.567, 6.0, -8.15, "wall", None)


def town_hall_furniture(ox, oz):
    """Bloxov Town Hall (World art 0.17), in the model's own coordinates (origin map (ox, oz), rooms 12.5 x 9 m,
    storeys 3 m). Furniture is solid like everywhere else; flags, chairs, bedrolls and the voting booths' curtains
    are picture only. Room middles (the boss and his guards start in the ground-floor ones), doorways, the stairs'
    feet and the bunker ramp's rail stay clear for the AI."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Ground floor. The foyer (north middle, the front door onto the square): the enquiries desk, a glass case with a
    # model of the town, benches, plants by the door.
    o(8.9, 0, -2.6, 11.7, 1.05, -1.7, "wood", "th_info_desk")
    o(9.3, 0, -8.2, 11.5, 1.0, -6.8, "wood", "town_model")
    o(0.9, 0, -8.75, 3.5, 0.5, -8.25, "wood", "hall_bench")
    o(0.9, 0, -0.75, 3.5, 0.5, -0.25, "wood", "hall_bench")
    o(4.3, 0, -8.6, 4.7, 1.3, -8.2, "wood", "plant", solid=False)
    o(7.8, 0, -8.6, 8.2, 1.3, -8.2, "wood", "plant", solid=False)
    # Records office (north, west of the foyer): cabinets along the north wall, two desk pods.
    for x0 in (-11.8, -10.7, -2.1, -1.0):
        o(x0, 0, -8.85, x0 + 1.0, 1.3, -8.25, "metal", "file_cabinet")
    o(-11.5, 0, -2.7, -9.8, 0.75, -1.2, "wood", "office_pod")
    o(-2.7, 0, -2.7, -1.0, 0.75, -1.2, "wood", "office_pod")
    # The stair hall (north-west): the stairs up, the bunker's ramp down; the crew's supplies in the corner.
    o(-14.6, 0, -8.8, -12.7, 0.9, -7.5, "wood", "supply_crates")
    # Rates office (north-east): the cashier's counter with its glass screen, the cashier's side behind it.
    o(20.0, 0, -6.4, 24.85, 1.05, -5.8, "wood", "cashier_counter")
    o(22.6, 0, -8.85, 23.6, 1.3, -8.25, "metal", "file_cabinet")
    o(20.6, 0, -8.6, 21.9, 0.75, -7.6, "wood", "desk")
    o(13.3, 0, -0.75, 16.2, 0.85, -0.25, "metal", "waiting_seats", solid=False)
    # Registry office (south-west): the registrar's desk, rows of chairs for weddings, a flower arch.
    o(-24.4, 0, 6.2, -23.6, 0.75, 8.2, "wood", "registrar_desk")
    o(-24.7, 0, 5.6, -24.3, 2.4, 8.8, "wood", "flower_arch", solid=False)
    o(-21.5, 0, 5.8, -15.5, 0.9, 8.2, "wood", "chair_rows", solid=False)
    # Town clerk's office (south middle-west): the clerk's desk, cabinets, the ballot boxes from the last election.
    o(-10.2, 0, 6.8, -8.4, 0.78, 7.8, "wood", "clerk_desk")   # (back from the door, owner)
    o(-12.35, 0, 7.0, -11.75, 1.3, 8.6, "metal", "file_cabinet")
    o(-1.6, 0, 7.4, -0.3, 0.8, 8.7, "wood", "ballot_boxes")
    # The back hall (south middle, the back door): Bon's crew's mess, a card table, cots, a camp stove, ammo.
    o(1.0, 0, 6.3, 2.4, 0.75, 7.5, "wood", "card_table")
    o(9.4, 0, 7.6, 11.6, 0.5, 8.5, "wood", "th_cot")
    o(0.3, 0, 0.4, 1.4, 0.8, 1.4, "metal", "camp_stove")
    o(10.6, 0, 0.35, 12.25, 0.9, 1.7, "wood", "ammo_crates")
    # Planning office (south-east): the plan chest, drafting tables, the town plan on the wall.
    o(13.3, 0, 0.3, 15.1, 0.9, 1.0, "wood", "plan_chest")
    o(23.4, 0, 1.0, 24.6, 0.95, 2.0, "wood", "drafting_table")
    o(23.4, 0, 6.9, 24.6, 0.95, 7.9, "wood", "drafting_table")
    # Upstairs. The upper hall (north-west, the top of the stairs): benches under the old mayors' portraits.
    o(-24.2, 3.0, -0.75, -21.2, 3.5, -0.25, "wood", "hall_bench")
    o(-16.3, 3.0, -0.75, -13.3, 3.5, -0.25, "wood", "hall_bench")
    # The crew's barracks (north middle-west): cots and kit.
    o(-4.9, 3.0, -8.75, -2.9, 3.5, -7.85, "wood", "th_cot")
    o(-2.5, 3.0, -8.75, -0.5, 3.5, -7.85, "wood", "th_cot")
    o(-11.9, 3.0, -1.05, -9.9, 3.5, -0.15, "wood", "th_cot")
    o(-3.0, 3.0, -1.05, -1.0, 3.5, -0.15, "wood", "th_cot")
    # The council chamber (north middle-east): the horseshoe council table, the public benches, the flags.
    o(2.6, 3.0, -7.6, 9.9, 3.76, -6.8, "wood", "council_table")
    o(2.6, 3.0, -6.8, 3.4, 3.76, -5.7, "wood", "council_table")
    o(9.1, 3.0, -6.8, 9.9, 3.76, -5.7, "wood", "council_table")
    o(0.8, 3.0, -1.5, 4.2, 3.45, -1.0, "wood", "council_bench")
    o(8.3, 3.0, -1.5, 11.7, 3.45, -1.0, "wood", "council_bench")
    for x in (4.4, 8.1):
        o(x - 0.1, 3.0, -8.6, x + 0.1, 5.4, -8.4, "metal", "th_flag", solid=False)
    # The mayor's office (north-east) is the caved-in room. The deputy's office, Bon's now (south middle-west): the big
    # desk, a bookcase, a sofa, a globe.
    o(-11.0, 3.0, 1.0, -9.2, 3.78, 1.8, "wood", "manager_desk")
    o(-3.4, 3.0, 8.2, -1.4, 5.0, 8.6, "wood", "wall_books")
    o(-11.5, 3.0, 7.95, -9.5, 3.85, 8.75, "wood", "sofa")
    o(-1.3, 3.0, 0.7, -0.7, 4.2, 1.3, "wood", "globe", solid=False)
    # The archive (south-west): tall shelving along the walls, a reading table.
    for x0, z0 in ((-24.4, 0.2), (-17.1, 0.2), (-24.4, 8.3), (-17.1, 8.3)):
        o(x0, 3.0, z0, x0 + 4.0, 5.2, z0 + 0.5, "metal", "archive_shelf")
    # The polling room (south middle-east): voting booths, the counting table, more ballot boxes; the crate (loot).
    o(0.4, 3.0, 0.2, 3.6, 5.0, 1.0, "wood", "voting_booths", solid=False)
    o(1.0, 3.0, 7.7, 4.4, 3.76, 8.5, "wood", "counting_table")
    o(10.9, 3.0, 0.3, 12.2, 3.8, 1.6, "wood", "ballot_boxes")
    # The radio room (south-east, the stairs to the roof): the crew's radio post, crates, a generator.
    o(20.5, 3.0, 0.25, 23.5, 3.78, 1.05, "wood", "radio_table")
    o(23.6, 3.0, 2.0, 24.8, 3.9, 3.2, "wood", "ammo_crates")
    o(13.0, 3.0, 0.4, 14.0, 3.8, 1.2, "metal", "generator")
    # On the roof: the radio's mast by the top of the stairs (picture only).
    o(24.2, 6.0, 5.8, 24.4, 10.0, 6.0, "metal", "radio_mast", solid=False)


def bank_furniture(ox, oz):
    """The Bank of Bloxov (World art 0.17), in the model's own coordinates (origin map (ox, oz), rooms 8 x 10 m,
    storeys 3 m). Furniture is solid like everywhere else; queue posts, chairs, the drill rig and the Raiders' cots
    are picture only. Room middles, doorways, the stairs' foot and the swing of the vault door stay clear."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Ground floor. The banking hall (west middle, the front door): the tellers' counter with its grilles (tellers
    # east of it, the way through to the back office), queue posts, a slip desk, a bench; the Raiders' guard post by
    # the door (their gun cabinet is the loot).
    o(-2.6, 0, -3.0, -1.9, 1.05, 3.0, "wood", "teller_counter")
    o(-3.6, 0, -2.5, -3.4, 1.0, 2.5, "metal", "queue_posts", solid=False)
    o(-7.6, 0, 4.35, -5.4, 1.0, 4.85, "wood", "slip_desk")
    o(-7.6, 0, -4.75, -5.4, 0.5, -4.25, "wood", "hall_bench")
    o(-7.75, 0, -1.9, -7.35, 1.3, -1.5, "wood", "plant", solid=False)
    # The stair hall (north-west): a wall closes the stairs off from the room (owner), all the way along. A
    # waiting area: seats along the west wall and back to back in the middle, a coffee table, a cooler, plants.
    o(-8.0, 0, -12.55, 0.0, 2.75, -12.35, "wall_rich", None)   # (owner: all the way; the stairs' foot is off the counting room)
    o(-7.8, 0, -10.6, -7.25, 0.85, -6.4, "metal", "waiting_seats_east", solid=False)
    o(-6.6, 0, -9.3, -5.8, 0.45, -7.7, "wood", "coffee_table")
    o(-5.2, 0, -10.2, -4.65, 0.85, -6.8, "metal", "waiting_seats", solid=False)
    o(-4.65, 0, -10.2, -4.1, 0.85, -6.8, "metal", "waiting_seats_east", solid=False)
    o(-7.75, 0, -5.75, -7.35, 1.3, -5.35, "wood", "plant", solid=False)
    o(-7.75, 0, -12.2, -7.35, 1.3, -11.8, "wood", "plant", solid=False)
    o(-0.6, 0, -6.2, -0.2, 1.3, -5.8, "metal", "water_cooler")
    # The manager's office (south-west): his desk, a bookcase, a sofa, a globe, his own safe (blown, empty).
    o(-2.6, 0, 10.8, -0.8, 0.78, 11.6, "wood", "manager_desk")
    o(-0.5, 0, 6.0, -0.1, 2.0, 8.0, "wood", "wall_books")
    o(-7.8, 0, 12.0, -7.0, 0.85, 14.0, "wood", "sofa")
    o(-7.6, 0, 6.0, -7.0, 1.2, 6.6, "wood", "globe", solid=False)
    o(-5.5, 0, 8.0, -2.9, 0.02, 12.2, "wood", "rug", solid=False)
    o(-1.0, 0, 14.25, -0.3, 0.8, 14.85, "metal", "small_safe")
    o(-7.75, 0, 7.4, -7.35, 1.3, 7.8, "wood", "plant", solid=False)
    o(-6.4, 0, 14.25, -5.4, 1.3, 14.85, "metal", "file_cabinet")
    # The counting room (north-east): counting tables, a cash trolley, shelves of cash boxes and ledgers, a cabinet.
    o(2.0, 0, -14.75, 5.6, 0.9, -13.95, "wood", "counting_table")
    o(6.0, 0, -14.75, 7.8, 0.9, -13.95, "wood", "counting_table")
    o(6.8, 0, -8.3, 7.6, 1.0, -7.5, "metal", "cash_trolley")
    o(5.3, 0, -5.6, 7.8, 1.8, -5.1, "metal", "archive_shelf")
    o(0.2, 0, -6.8, 0.8, 1.3, -5.6, "metal", "file_cabinet")
    # Behind the counter (east middle): the tellers' desks, a cabinet, the Raiders' cots, ammo and generator; their
    # drill rig still aimed at the vault door (it held).
    o(1.0, 0, -4.4, 2.6, 0.75, -3.6, "wood", "desk")
    o(5.4, 0, -4.4, 7.0, 0.75, -3.6, "wood", "desk")
    o(0.2, 0, -4.8, 0.8, 1.3, -3.6, "metal", "file_cabinet")
    o(6.9, 0, 1.6, 7.8, 0.5, 3.6, "wood", "th_cot", solid=False)
    o(6.9, 0, -3.0, 7.8, 0.5, -1.0, "wood", "th_cot", solid=False)
    o(0.2, 0, 1.0, 1.15, 0.9, 2.2, "wood", "ammo_crates")
    o(6.0, 0, 2.6, 6.8, 1.4, 3.4, "metal", "drill_rig", solid=False)   # (pushed aside, owner)
    o(5.8, 0, 3.8, 6.8, 0.8, 4.6, "metal", "generator")
    # The vault (south-east, behind the key door): safe-deposit boxes round the walls, the table in the middle, a
    # cash trolley.
    o(0.1, 0, 5.6, 0.5, 2.4, 14.4, "metal", "deposit_wall")
    o(7.45, 0, 5.6, 7.85, 2.4, 10.6, "metal", "deposit_wall")
    o(0.6, 0, 14.45, 3.2, 2.4, 14.85, "metal", "deposit_wall")
    o(4.8, 0, 14.45, 6.6, 2.4, 14.85, "metal", "deposit_wall")
    o(3.2, 0, 9.0, 4.8, 0.9, 10.4, "metal", "vault_table")
    o(1.0, 0, 12.6, 1.8, 1.0, 13.4, "metal", "cash_trolley")
    # Upstairs. The top of the stairs (north-west): seats for the loans office, a cabinet, a plant.
    o(-7.8, 3.0, -9.2, -7.25, 3.85, -6.6, "metal", "waiting_seats_east", solid=False)
    o(-0.7, 3.0, -7.2, -0.1, 4.3, -6.2, "metal", "file_cabinet")
    # Upstairs the wall between the stairs and records runs right to the north wall (owner: you saw into records).
    o(-0.1, 3.0, -15.0, 0.1, 6.0, -12.65, "wall_rich", None)
    o(-7.75, 3.0, -5.75, -7.35, 4.3, -5.35, "wood", "plant", solid=False)
    # The loans office (west middle): two desks (off the walls, room for their chairs), a water cooler, a plant.
    o(-2.6, 3.0, 1.8, -0.9, 3.75, 3.3, "wood", "office_pod")   # (clear of the board room's doorway)
    o(-2.6, 3.0, -3.6, -0.9, 3.75, -2.1, "wood", "office_pod")
    o(-7.8, 3.0, 4.3, -7.4, 4.3, 4.7, "metal", "water_cooler")
    o(-0.55, 3.0, 4.35, -0.15, 4.3, 4.75, "wood", "plant", solid=False)
    # The board room (south-west): the long table, a bookcase, a plant.
    o(-6.0, 3.0, 9.4, -2.0, 3.76, 10.6, "wood", "meeting_table")
    o(-0.5, 3.0, 7.0, -0.1, 5.0, 9.0, "wood", "wall_books")
    o(-0.55, 3.0, 14.35, -0.15, 4.3, 14.75, "wood", "plant", solid=False)
    # The accounts office (east middle): desks, a printer, cabinets.
    o(1.0, 3.0, -3.6, 2.7, 3.75, -2.1, "wood", "office_pod")
    o(1.0, 3.0, 2.1, 2.7, 3.75, 3.6, "wood", "office_pod")
    o(7.2, 3.0, -3.6, 7.8, 4.0, -2.8, "metal", "printer")
    o(7.25, 3.0, -2.4, 7.85, 4.3, -1.4, "metal", "file_cabinet")
    o(5.4, 3.0, -4.85, 6.8, 4.3, -4.25, "metal", "file_cabinet")
    # Records (north-east): shelving.
    o(2.0, 3.0, -14.6, 5.0, 5.2, -14.1, "metal", "archive_shelf")
    o(5.2, 3.0, -5.6, 7.6, 5.0, -5.1, "metal", "archive_shelf")
    o(7.35, 3.0, -8.8, 7.85, 5.0, -6.0, "metal", "archive_shelf")
    # The security room over the vault (south-east, caved in): the camera desk, the tape rack, a cabinet.
    o(7.25, 3.0, 7.0, 7.85, 3.8, 10.0, "wood", "cctv_desk")
    o(7.35, 3.0, 11.0, 7.85, 4.8, 12.2, "metal", "tape_rack")
    o(0.3, 3.0, 13.6, 0.9, 4.3, 14.6, "metal", "file_cabinet")

# The grocery store's outside openings (World art 0.17), ground floor, map coords: the glass shop front either side of
# the entrance (south, the street), the loading door (west, Mill Lane) into the stock room, the manager's office window
# (north), the blast hole and a window on the car park side (east).
GROCERY_OPENINGS = {
    "S": [("glass_front", 132.0, 6.0, 0.5, 2.4), ("glass_front", 137.0, 2.8, 0.5, 2.4), ("door", 140.0, DOOR_W, 0.0, DOOR_H),
          ("glass_front", 143.0, 2.8, 0.5, 2.4), ("glass_front", 148.0, 6.0, 0.5, 2.4)],
    "W": [("dock", 62.35, 2.6, 0.0, 2.5)],
    "N": [("window", 140.75, WIN_W, WIN_LO, WIN_HI)],
    "E": [("blast", 65.0, 3.4, 0.0, FLOOR_H), ("window", 75.0, WIN_W, WIN_LO, WIN_HI)],
}


GROCERY_CHECKOUTS = (-7.2, -4.9, -2.6)   # the counters' middles (model x), lane 1 in the west


def grocery_furniture(ox, oz):
    """The grocery store (World art 0.17), in the model's own coordinates (origin map (ox, oz): the building is x -12..12,
    z -10..10, north -z). One sales floor laid out like a real supermarket, back rooms behind a wall along the north:
    the stock room (loading door west), the manager's office, the staff room with the stairs up to the roof (walled the
    whole way, one way up). The three aisles keep their places (their front halves exactly; the back halves end 2 m
    further south (1.3 m long now), leaving a walkway along the back wall). Ransacked."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # ---- Walls of the back rooms: along the back (doorways to the stock room, office and staff room; its east end
    # was blown off by the blast at the corner), between the rooms, and along the roof stairs.
    wall_x(ox - 11.85, ox + 9.7, oz - 5.6, 0.0, 2.75, "wall_food", [(ox - 6.0, INNER_DOOR_W, 0.0, DOOR_H),
           (ox + 0.75, INNER_DOOR_W, 0.0, DOOR_H), (ox + 7.0, INNER_DOOR_W, 0.0, DOOR_H)], t=0.2)
    for x in (-1.5, 3.0):
        wall_z(oz - 9.85, oz - 5.7, ox + x, 0.0, 2.75, "wall_food", t=0.2)
    wall_x(ox + 4.95, ox + 11.85, oz - 7.55, 0.0, 2.75, "wall_food", t=0.2)
    for x in (-6.0, 0.75, 7.0):
        inner_door(ox + x, 0.0, oz - 5.6, 0.0, "Grocery")
    # ---- Sales floor. The aisles: double-sided shelving (solid, as the old gray boxes).
    # (owner, grocery round 2: the aisles' front halves end 2 m sooner to give the checkouts room)
    for x in (-8.0, 0.0, 8.0):
        o(x, 0, 2.0, x + 0.9, 1.7, 5.0, "wood", "groc_gondola")
        o(x, 0, -3.3, x + 0.9, 1.7, -2.0, "wood", "groc_gondola")
    # Fridges along the side walls: dairy (west), drinks (east, between the blast hole and the window).
    o(-11.85, 0, 0.0, -11.1, 2.0, 6.6, "metal", "wall_fridge")
    o(11.1, 0, -2.6, 11.85, 2.0, 3.6, "metal", "wall_fridge")
    # The deli and bakery counter in the north-west corner: a glass case facing the floor, the back counter on the back
    # wall; the staff walk in from the walkway at its east end.
    o(-10.6, 0, -2.9, -8.6, 1.15, -2.1, "metal", "deli_case")
    o(-11.85, 0, -5.5, -10.7, 0.95, -4.9, "metal", "deli_back")
    # Chest freezers in the cross aisle, between the aisles.
    o(-5.0, 0, -0.5, -3.0, 0.9, 0.5, "metal", "chest_freezer")
    o(3.0, 0, -0.5, 5.0, 0.9, 0.5, "metal", "chest_freezer")
    # The checkouts west of the entrance (belt, till, candy rack; solid at counter height), produce stands east of it.
    # Laid out like real lanes (owner, round 2): customers queue in the 1.4 m north of them, walk south down the lane
    # east of each counter, pay at the till and leave along the 1.75 m walkway in front of the glass to the door; the
    # cashier stands west of the counter by the till (a mat and a stool, picture only).
    for x in GROCERY_CHECKOUTS:
        o(x - 0.35, 0, 6.4, x + 0.35, 0.9, 8.1, "metal", "checkout")
        o(x - 1.1, 0, 7.0, x - 0.4, 0.6, 8.0, "metal", "cashier_spot", solid=False)
    o(2.6, 0, 7.7, 4.2, 0.85, 8.9, "wood", "produce_stand")
    o(5.4, 0, 7.7, 7.0, 0.85, 8.9, "wood", "produce_stand")
    # ---- The stock room: pallet racking on the north wall, pallets, the pallet jack (picture only).
    o(-10.0, 0, -9.85, -6.0, 2.6, -8.75, "metal", "pallet_rack")
    o(-5.0, 0, -9.85, -2.0, 2.6, -8.75, "metal", "pallet_rack")
    o(-8.0, 0, -8.0, -6.8, 1.1, -6.8, "wood", "pallet_load")
    o(-5.6, 0, -7.9, -4.4, 0.15, -7.1, "wood", "pallet_jack", solid=False)   # (west of the washroom)
    # ---- The manager's office: the desk against the east wall (the chair in front of it, off the window), the CCTV
    # monitor on it.
    o(1.9, 0, -8.8, 2.7, 0.76, -7.0, "wood", "manager_desk_g")
    o(2.15, 0, -9.85, 2.85, 1.3, -9.3, "metal", "file_cabinet")
    # ---- The staff area beside the stairs (a passage to their foot): lockers along the stair wall at the east end.
    o(8.4, 0, -7.45, 10.4, 1.9, -7.0, "metal", "hall_lockers")
    # ---- Loot: the same three crates (food table), each where it fits: stock boxes on a pallet in the stock room,
    # the manager's cabinet, the deli's cupboard behind the counter.
    add_loot("Grocery", "crate", ox - 10.5, oz - 6.3, yaw=0.0, look="stock_boxes")
    add_loot("Grocery", "crate", ox - 0.8, oz - 8.0, yaw=-90.0, look="filing")
    add_loot("Grocery", "crate", ox - 9.8, oz - 4.9, yaw=180.0, look="kitchen")
    # ---- Outside: the cart corral and carts by the car park, an ice chest and a newspaper box by the door, dumpsters
    # round the back by the loading door.
    o(13.0, 0, 7.0, 14.6, 1.0, 9.5, "metal", "cart_corral")
    o(3.0, 0, 10.35, 4.2, 0.9, 11.1, "metal", "ice_chest")
    o(-3.6, 0, 10.4, -3.1, 1.1, 10.9, "metal", "news_box")
    o(-14.4, 0, -4.0, -12.8, 1.4, -2.0, "metal", "dumpster")
    o(-14.4, 0, -1.2, -12.8, 1.4, 0.8, "metal", "dumpster")


# The church's outside openings (World art 0.17), map coords: the west door (south end, the street side of the
# churchyard) under the gable, four tall lancet windows down each side of the nave, the big window over the altar
# (north), small windows for the washroom (west) and the vestry (east) in the rooms either side of the porch.
CHURCH_LANCETS = (32.0, 37.0, 42.0, 46.6)
CHURCH_OPENINGS = {
    "S": [("church_door", 167.0, 2.4, 0.0, 3.2)],
    "W": [("lancet", z, 1.2, 1.4, 4.6) for z in CHURCH_LANCETS] + [("small_window", 50.3, 0.8, 1.7, 2.4),
          ("side_door", 34.5, 1.6, 0.0, DOOR_H)],          # (the covered passage from the bell tower, owner 2026-10-16)
    "E": [("lancet", z, 1.2, 1.4, 4.6) for z in CHURCH_LANCETS] + [("small_window", 50.3, 0.8, 1.5, 2.4)],
    "N": [("east_window", 167.0, 2.6, 2.4, 5.4)],
}


CH_RISE, CH_OVER = 6.0, 0.35   # the church's roof as make_building.py draws it: rise eaves (6 m) to ridge, overhang


def church_roof_solid(ox, oz):
    """The church's pitched roof gets collision (0.22.9, owner: "You can walk through the church roof"): until now only
    the flat slab at the eaves collided, so from the bell tower you walked about inside the drawn roof. Its two slopes
    (their top on the tiles, over the shell hole too) and the gable ends in steps under them, all hidden."""
    run, top = 7.15 + CH_OVER, 6.0 + CH_RISE
    eave = 6.0 - CH_OVER * CH_RISE / 7.15
    rise = top - eave
    length = math.hypot(run, rise)
    nx, ny = rise / length, run / length          # the east slope's outward normal (x, y)
    for sx in (-1, 1):
        obox(ox + sx * (run / 2 + 0.04 * nx), (eave + top) / 2 + 0.04 * ny, oz, 24.3, 0.2, length + 0.3, 90.0, "roof",
             pitch=sx * math.degrees(math.atan2(rise, run)), kind="church_roof_hidden")
    for sz in (-1, 1):
        for k in range(12):
            y0 = 6.0 + 0.5 * k
            half = 7.15 * (1.0 - (y0 + 0.5 - 6.0) / CH_RISE)
            if half > 0.1:
                box(ox - half, y0, oz + min(sz * 12.0, sz * 12.15), ox + half, y0 + 0.5, oz + max(sz * 12.0, sz * 12.15), "wall",
                    kind="church_roof_hidden")


def church_furniture(ox, oz):
    """The parish church (World art 0.17), in the model's own coordinates (origin map (ox, oz): the church is x -7..7,
    z -12..12, north -z, one tall room 6 m to the eaves). Laid out like a real church: the porch inside the door at the
    south end with the washroom (west) and the vestry (east) either side of it, the nave with its pews (same places as
    the gray boxes, an aisle down the middle), the chancel at the north end with the altar under the big window, the
    pulpit and the lectern, the organ. War: used as a shelter, then shelled (the roof hole is picture only)."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # ---- The porch rooms (3 m tall, a flat ceiling): washroom south-west, vestry south-east, doors off the porch.
    for x0, x1, dx in ((-6.85, -2.1, -2.0), (2.1, 6.85, 2.0)):
        wall_x(ox + x0, ox + x1, oz + 8.6, 0.0, 3.0, "wall", t=0.2)
        wall_z(oz + 8.5, oz + 11.85, ox + dx, 0.0, 3.0, "wall", [(oz + 10.25, INNER_DOOR_W, 0.0, DOOR_H)], t=0.2)
        o(min(x0, dx - 0.1), 3.0, 8.5, max(x1, dx + 0.1), 3.15, 11.85, "slab", None)
    inner_door(ox - 2.0, 0.0, oz + 10.25, 90.0, "Church")
    inner_door(ox + 2.0, 0.0, oz + 10.25, 90.0, "Church")
    # ---- The nave: the pews (solid as the gray boxes, an aisle down the middle), the altar.
    for z in range(-6, 8, 3):
        o(-4.5, 0, z, -1.0, 0.9, z + 0.8, "wood", "pew")
        o(1.0, 0, z, 4.5, 0.9, z + 0.8, "wood", "pew")
    o(-2.0, 0, -10.4, 2.0, 1.0, -9.0, "wood", "altar")
    # ---- The chancel: the pulpit (west), the lectern (east), the organ against the east wall, candle stands.
    o(-6.0, 0, -7.8, -4.8, 1.25, -6.6, "wood", "pulpit")
    o(4.9, 0, -7.6, 5.5, 1.2, -7.0, "wood", "lectern")
    o(5.95, 0, -6.8, 6.85, 2.4, -4.0, "wood", "organ")
    for x in (-2.6, 2.6):
        o(x - 0.15, 0, -9.85, x + 0.15, 1.5, -9.55, "metal", "candle_stand", solid=False)
    # ---- The washroom (two stalls, sinks) and the vestry (robes, the parish desk, the safe-ish cupboard).
    o(-6.85, 0, 8.7, -5.1, 2.0, 11.85, "wood", "wc_stalls", solid=False)
    o(-4.8, 0, 8.7, -3.9, 0.9, 9.3, "metal", "wc_sinks")
    o(5.9, 0, 9.3, 6.85, 0.76, 11.0, "wood", "vestry_desk")
    o(2.1, 0, 11.3, 4.3, 2.0, 11.85, "wood", "robe_rail", solid=False)

def bell_tower_furniture(ox, oz):
    """The bell tower (World art 0.17), model coordinates (origin map (ox, oz): x -5..5, z -5..5, storeys 3 m, the
    belfry on the roof). Stairs walled the whole way (owner rule): the ground-floor flight along the north wall is
    walled off from the ringing room up to its foot (east end), the roof flight along the south wall upstairs is
    walled off from the clock room up to its foot (west end). Ringing room: the bell rope, the ringers' bench; clock
    room: the clock frame in the middle, rods out to the faces on the north and south walls."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    o(-4.85, 0, -2.65, 2.05, 2.75, -2.45, "wall", None)
    o(-2.05, 3.0, 2.45, 4.85, 5.75, 2.65, "wall", None)
    o(-4.85, 0, -1.6, -4.4, 0.45, 1.6, "wood", "ringers_bench")
    o(1.4, 0.0, 0.4, 1.6, 2.75, 0.6, "wood", "bell_rope", solid=False)
    o(-0.7, 3.0, -0.45, 0.7, 4.6, 0.45, "metal", "clock_works")

def graveyard_furniture(ox, oz):
    """The graveyard (World art 0.17), model coordinates (origin map (ox, oz): the yard is x -13..13, z -13..13, the
    crypt x 3..11, z 0..8, door west). A row of fresh war graves along the north wall (thin wooden crosses, solid so
    nobody walks through them), the crypt's coffin shelves along its north and south walls (the middle stays clear)."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    for k in range(10):
        x = -7.6 + k * 1.6
        o(x - 0.05, 0, -11.85, x + 0.05, 0.95, -11.75, "wood", "war_cross")
        o(x - 0.45, 0, -11.7, x + 0.45, 0.18, -10.35, "dirt", "grave_mound", solid=False)
    for z0 in (0.15, 7.15):
        o(3.4, 0, z0, 10.6, 1.9, z0 + 0.7, "stone", "coffin_shelf")

# The Last Stop Motel (World art 0.17, owner 2026-10-17: the two road houses east of the graveyard become one big
# roadside motel; plan worldart/motel-plan.md). A long two-storey block (map x 211.5-220.5, z 24-66) with an outside
# gallery along its east side (walkway upstairs, railing, posts) and walled stairs up at both ends; the rooms open onto
# the gallery and the motel's own car park by the county road. The office (front desk, lobby, the manager's flat behind
# it) at the south end, nearest Main Street; the laundry next to it. 5 m rooms: 101-105 downstairs (102 has a car through
# its front), 206.0-213.0 upstairs, each with its own bathroom at the back.
MOTEL = (211.5, 24.0, 220.5, 66.0)        # the block (map x0, z0, x1, z1)
MOTEL_O = (216.0, 45.0)                   # the model's origin
MOTEL_CELL = 5.25                         # one room along the block
MOTEL_GAL = 223.5                         # the gallery's outer edge (posts and rail)
MOTEL_LOT = (223.5, 18.0, 232.5, 72.0)    # the car park
MOTEL_CLEAR = (208.0, 15.0, 237.0, 74.0)  # the scatter cleared for it
MOTEL_CASINO = (207, 208)                 # knocked through into a back-room card room (owner 2026-10-17)
MOTEL_LOOT_ROOMS = (103, 105, 202, 205)   # a dresser of loot (owner 2026-10-17: a few more spots, not every room)


def motel_rooms():
    """(storey, cell k, room number) of the guest rooms (cell k runs z 24 + 5.25 k ..)."""
    rooms = [(0, k, 101 + n) for n, k in enumerate(range(5))]
    rooms += [(1, k, 201 + k) for k in range(8)]
    return rooms


def motel_openings():
    """Outside openings: per room a window and the door (a real door, `inner_door`) on the gallery side, a window at the
    back (in the dressing nook beside the bathroom); 102's front is a hole where a car went through; the office's
    door and windows, the end windows."""
    x0, z0, x1, z1 = MOTEL
    ops = {"E": [], "W": [], ("E", 1): [], ("W", 1): []}
    for f, k, num in motel_rooms() + [(0, 5, 0)]:
        c = z0 + k * MOTEL_CELL
        E, W = ops["E" if f == 0 else ("E", 1)], ops["W" if f == 0 else ("W", 1)]
        if num == 102:
            E.append(("blast", c + 2.6, 3.4, 0.0, 2.6))
        else:
            E.append(("window", c + 1.3, WIN_W, WIN_LO, WIN_HI))
            E.append(("room_door", c + 3.85, INNER_DOOR_W, 0.0, DOOR_H))
        if num and num not in MOTEL_CASINO:                 # (the card room upstairs is blacked out)
            W.append(("window", c + 3.9, WIN_W, WIN_LO, WIN_HI))
    ops["E"] += [("window", 57.6, WIN_W, WIN_LO, WIN_HI), ("door", 61.5, DOOR_W, 0.0, DOOR_H)]
    ops["W"] += [("window", 58.3, WIN_W, WIN_LO, WIN_HI), ("window", 62.3, WIN_W, WIN_LO, WIN_HI)]
    ops["N"] = [("window", 216.5, WIN_W, WIN_LO, WIN_HI)]
    ops[("N", 1)] = [("window", 216.5, WIN_W, WIN_LO, WIN_HI)]
    ops["S"] = [("door", 218.0, DOOR_W, 0.0, DOOR_H), ("window", 214.45, 0.8, 1.5, 2.1)]
    ops[("S", 1)] = []                                       # (the card room is blacked out)
    return ops


# The church path and the shared car park (World art 0.17, outdoor step 2; /mnt/project-files/worldart/motel-plan.md
# section 2, owner 2026-10-17): the grocery's car park moved from in front of the church door to behind the grocery
# (north, off Mill Lane), shared by both; a stone path runs from the church door down the old car park's lawn to the
# Main Street sidewalk, with a churchyard noticeboard at the street end.
CHURCH_PATH = ((167.0, 52.4), (167.0, 98.6))     # map x, z: the church door to the sidewalk
CAR_PARK = (130.0, 41.0, 148.0, 58.0)
old_car_park = [0, 0]   # its boxes (from, to), see the grocery
lot_ways = []           # the car parks' ways in off the roads (points, width): no road lines across their mouths


@debris_kind("shelter")
def bus_shelter(x, z, yaw):
    """A bus shelter (its open side faces yaw + 180): roof, back and end panels, a bench, the stop's sign."""
    with group():
        c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        obox(x + s_ * 0.8, 1.2, z + c * 0.8, 4.0, 2.4, 0.1, yaw, "metal")          # back panel
        obox(x, 2.45, z, 4.2, 0.1, 1.9, yaw, "metal", solid=False)                   # roof
        obox(x + c * 2.4, 1.3, z - s_ * 2.4, 0.1, 2.6, 0.1, yaw, "metal")           # the stop's sign post


@debris_kind("bench")
def bench(x, z, yaw):
    obox(x, 0.25, z, 1.6, 0.5, 0.5, yaw, "wood")


def station_square():
    """Bloxov Station's square (World art 0.17, owner 2026-10-18: "just a road leading to the train station ... make
    this a hub"; picked B, the station square, with some of C's market stalls; the hill levelled for it, EXTRA_PADS):
    paving in front of the station, a drop-off with taxis where Station Road ends, a clock on a plinth, a bus
    shelter, benches, lamps, planters by the doors, a kiosk and a few market stalls."""
    clear_scatter((193.0, 164.0, 245.0, 190.5))
    plaza(219.0, 183.75, 40.0, 11.5)                       # (199..239 x 178..189.5; the station's north wall at 190)
    box(196.0, 0.0, 170.0, 216.0, 0.06, 178.0, "lot", solid=False)    # the drop-off
    car(200.5, 174.0, 0, "car_b"); car(204.5, 174.2, 2, "car_a")       # (taxis waiting)
    statue(229.0, 182.0)                                   # the clock
    bus_shelter(221.5, 175.5, 0)
    for x in (212.0, 226.0):   # (flanking the doors; the office's blast rubble lies east of them)
        planter(x, 187.0)
    for x, yaw in ((204.0, 0), (231.5, 0), (216.0, 180)):
        bench(x, 180.0 if yaw == 0 else 179.0, yaw)
    for x in (199.5, 212.0, 226.0, 238.5):
        lamp(x, 178.6, 0)
    kiosk(236.5, 182.5, 180)                               # (on the paving, its hatch to the road)
    stall(203.0, 184.5, 0); stall(207.0, 180.5, 0); stall(213.5, 182.5, 90)


# Paths to the buildings' doors (World art 0.17, outdoor round 3; owner 2026-10-18: "a lot just have grass going to
# them"). Every ground-floor outside door gets a path out to the nearest road, pavement or car park (from the door
# straight out, then to it), unless it opens onto paving already or nothing is near. PATH_LOOK: "a" none (grass, as
# before), "b" worn earth everywhere, "c" by place (concrete slabs in town, worn earth out of town), "d" paved
# everywhere (concrete slabs in town, laid flagstones out of town). Looks only: no collision, the AI's paths don't change.
PATH_LOOK = os.environ.get("BLOXOV_PATH_LOOK", "c")
PATH_DOORS = ("door", "church_door", "side_door", "big_door")
PATH_REACH = 40.0      # the furthest a door's path runs
PATH_SKIP = {"church"}  # (has its own path: churchyard)
door_walks = []        # (points, width, kind) of the paths made, for the options sheets


def _door_spots():
    """(building, x, z, outward nx, nz, door width) of every ground-floor outside door, map space, turned like its model."""
    out = []
    for m in models:
        if m["name"] in PATH_SKIP:
            continue
        for o in m.get("openings", []):
            if o["kind"] not in PATH_DOORS or o["lo"] > 0.3:
                continue
            side = o["side"]
            if side in "NS":
                x, z, nx, nz = o["mid"], o["at"], 0.0, (-1.0 if side == "N" else 1.0)
            else:
                x, z, nx, nz = o["at"], o["mid"], (-1.0 if side == "W" else 1.0), 0.0
            if m["turned"]:
                ex, ez = turn_point(x + nx, z + nz, m["x"], m["z"], m["turned"])
                x, z = turn_point(x, z, m["x"], m["z"], m["turned"])
                nx, nz = ex - x, ez - z
            out.append((m["name"], x, z, nx, nz, o["w"]))
    return out


def _paving_rects():
    """Flat paving already on the ground (pavements, car parks, the square, forecourts): map rects."""
    out = []
    for b in boxes:
        if b[4] <= 0.12 and b[8] in (C["pavement"], C["lot"]) and max(b[3], b[5]) > 2.5 and b[6] % 90 == 0 \
                and b[1] - b[4] / 2 < 0.2:
            hx, hz = (b[3], b[5]) if b[6] % 180 == 0 else (b[5], b[3])
            cx, cz = b[0] + M / 2, b[2] + M / 2
            out.append((cx - hx / 2, cz - hz / 2, cx + hx / 2, cz + hz / 2))
    return out


@debris_kind("walk")
def walk_slabs(x, z, points, width):
    _walk_box(points, width, "slabs")


@debris_kind("flags")
def walk_flags(x, z, points, width):
    _walk_box(points, width, "flags")


def walk(points, width, kind):
    """Lays a path: concrete slabs or flagstones (drawn by the outdoor kit, following the ground) on worn earth, or
    worn earth only."""
    paths.append((points, width * (0.85 if kind != "earth" else 1.0)))
    door_walks.append((points, width, kind))
    if kind != "earth":
        (walk_slabs if kind == "slabs" else walk_flags)(points[0][0], points[0][1], points, width)


def _walk_box(points, width, kind):
    for (ax, az), (bx, bz) in zip(points, points[1:]):
        ln = math.hypot(bx - ax, bz - az)
        if ln < 0.3:
            continue
        tx, tz = (bx - ax) / ln, (bz - az) / ln
        yaw = math.degrees(math.atan2(tx, tz))
        t = 0.1
        k = 0
        while t < ln - 0.2:
            if kind == "slabs":   # square concrete slabs, a thin joint between
                step = min(width, ln - t)
                obox(ax + tx * (t + step / 2), 0.035, az + tz * (t + step / 2), width, 0.07, step - 0.06, yaw, "slab",
                     solid=False)
            else:                 # flagstones, a little off line like a laid path
                step = min(0.7 + ((k * 7.3) % 1.0) * 0.35, ln - t)
                wob = (((k * 3.7) % 1.0) - 0.5) * 0.18
                obox(ax + tx * (t + step / 2) - tz * wob, 0.035, az + tz * (t + step / 2) + tx * wob,
                     width * (0.8 + ((k * 5.1) % 1.0) * 0.2), 0.07, step - 0.12, yaw + wob * 20, "slab", solid=False)
            t += step
            k += 1


PATH_NARROW = ("big_house", "old_house", "cabin", "farmhouse", "shed", "motel")   # (house paths: 1.2 m)


def door_paths():
    if PATH_LOOK == "a":
        return
    paving = _paving_rects()
    own = {n: r for n, *r in footprints}
    left = []
    for spot in _door_spots():
        if not _door_path(spot, paving, own, False):
            left.append(spot)
    for spot in left:   # (out of town, a door with nothing near joins another door's path: the farmhouse)
        _door_path(spot, paving, own, True)


def _door_path(spot, paving, own, join):
    """Lays one door's path (see door_paths); join: to another door's path instead of a road. True if laid."""
    name, x, z, nx, nz, w = spot
    x0, z0 = x + nx * 0.3, z + nz * 0.3   # (the doorstep)
    if any(r[0] - 1.2 < x0 < r[2] + 1.2 and r[1] - 1.2 < z0 < r[3] + 1.2 for r in paving):
        return True   # (opens onto paving already)
    town = TOWN[0] < x < TOWN[2] and TOWN[1] < z < TOWN[3]
    if join and town:
        return False
    # the nearest road edge or paving (out of town also a yard), from a point a little out from the door, that
    # the path can reach without going through a building
    x1, z1 = x0 + nx * 2.5, z0 + nz * 2.5
    goals = []
    for pts, rw in ([] if join else roads):
        d, (px, pz) = _nearest_on(pts, x1, z1)
        if d > rw / 2 + 0.2:
            goals.append((d - rw / 2, px + (x1 - px) / d * (rw / 2 - 0.2), pz + (z1 - pz) / d * (rw / 2 - 0.2)))
    for r in ([] if join else paving) + ([] if town else [y for y in yards if (y[2] - y[0]) * (y[3] - y[1]) < 4000]):
        ex, ez = min(max(x1, r[0] + 0.3), r[2] - 0.3), min(max(z1, r[1] + 0.3), r[3] - 0.3)
        goals.append((math.hypot(ex - x1, ez - z1), ex, ez))
    if join:
        for pts, _, _ in door_walks:
            d, (px, pz) = _nearest_on(pts[1:], x1, z1)
            goals.append((d, px, pz))
    reach = PATH_REACH if town else 60.0
    for gap, ex, ez in sorted(goals):
        if gap > reach:
            break
        pts = [(x0, z0), (x1, z1), (ex, ez)]
        if any(_seg_rect_gap(a, b, (r[0] + 0.2, r[1] + 0.2, r[2] - 0.2, r[3] - 0.2)) <= 0.0
               for n, r in own.items() for k, (a, b) in enumerate(zip(pts, pts[1:])) if k or n != name):
            continue   # (through a building)
        kind = "earth" if PATH_LOOK == "b" or (PATH_LOOK == "c" and not town) else "slabs" if town else "flags"
        width = 1.3 if kind == "earth" else 1.2 if name.startswith(PATH_NARROW) else 1.8
        def hits(bx, w=width):
            return bx[1] - bx[4] / 2 < 1.5 and any(_seg_rect_gap(a, b, (
                bx[0] + M / 2 - max(bx[3], bx[5]) / 2, bx[2] + M / 2 - max(bx[3], bx[5]) / 2,
                bx[0] + M / 2 + max(bx[3], bx[5]) / 2, bx[2] + M / 2 + max(bx[3], bx[5]) / 2)) < w / 2 + 0.2
                for a, b in zip(pts, pts[1:]))
        # Cover stays (the sightlines): a paved path that would run into it takes the next way out; a worn trail
        # just goes past it. Only low junk is cleared off a path.
        tall = [p for p in scatter_pieces if any(hits(boxes[k]) for k in range(*p[1][0])) and
                max(boxes[k][4] for k in range(*p[1][0])) >= 0.7]
        if tall and kind != "earth":
            continue
        low = [boxes[p[1][0][0]] for p in scatter_pieces if p not in tall and any(hits(boxes[k]) for k in range(*p[1][0]))]
        for first in low:   # (by its first box: deleting pieces moves the others' indices, not their boxes)
            clear_scatter(None, hit=lambda bx, first=first: bx is first)
        walk(pts, width, kind)
        return True
    return False


def churchyard():
    (px, z0), (_, z1) = CHURCH_PATH
    clear_scatter((px - 2.5, z0, px + 2.5, z1 + 1.0))
    clear_scatter((CAR_PARK[0] - 1.0, CAR_PARK[1] - 1.5, CAR_PARK[2] + 1.0, CAR_PARK[3] + 1.0))
    clear_scatter((118.0, 44.0, CAR_PARK[0] + 1.0, 55.0))   # (and the way in: owner, dirt banks across it)
    paths.append(([(px, z0), (px, z1)], 1.6))
    # Flagstones (each its own slab, so they follow the hills), a little off line like a laid path.
    z = z0 + 0.2
    while z < z1 - 0.3:
        wob = ((z * 7.3) % 1.0 - 0.5) * 0.16
        long = 0.75 + (z * 3.1) % 0.3
        box(px - 0.6 + wob, 0, z, px + 0.6 + wob, 0.07, min(z + long, z1), "slab", solid=False)
        z += long + 0.12
    # The noticeboard, beside the path where it meets the sidewalk.
    with group():
        box(px + 1.4, 0, z1 - 0.9, px + 1.55, 1.7, z1 - 0.75, "wood")
        box(px + 2.6, 0, z1 - 0.9, px + 2.75, 1.7, z1 - 0.75, "wood")
        box(px + 1.3, 1.0, z1 - 0.95, px + 2.85, 1.8, z1 - 0.8, "wood")
    x0, cz0, x1, cz1 = CAR_PARK
    box(x0, 0.0, cz0, x1, 0.06, cz1, "lot", solid=False)
    lot_ways.append(([(121.0, 49.5), (x0 + 1.0, 49.5)], 5.0))     # the way in, off Mill Lane (follows the slope)
    car(132.5, 45.0, 0); car(143.0, 52.5, 0, "car_b")
    # The shops' car park (made with the shops): no dirt banks round it, and a way in off the road (owner, 2026-10-18).
    clear_scatter((12.0, 144.0, 50.0, 168.0))
    clear_scatter((44.0, 152.0, 56.0, 162.0))
    lot_ways.append(([(44.0, 157.0), (53.5, 157.0)], 6.0))
    for points, width in lot_ways:
        strip(points, width, "lot", y=0.1)
    # (last: deleting these moves the later boxes down, which the scatter lists don't follow)
    k0, k1 = old_car_park
    gone = set(anchors[k0:k1])
    del boxes[k0:k1]
    del anchors[k0:k1]
    cars[:] = [c for c in cars if c["anchor"] not in gone]


def motel():
    """Builds the motel (after the scatter, like the shops' turn: see main) and its car park."""
    x0, z0, x1, z1 = MOTEL
    ox, oz = MOTEL_O
    G = MOTEL_GAL

    def o(a0, b0, c0, a1, b1, c1, colour, kind=None, solid=True):
        box(a0, b0, c0, a1, b1, c1, colour, solid=solid, kind=kind)
    spots = []
    with modeled("motel", ox, oz):
        m = build(Building("Motel", x0, z0, x1 - x0, z1 - z0, floors=2, colour="wall", rooms=(1, 8), doors="",
                           open_plan=True, wall_openings=motel_openings(), stairs=False, spawn_spots=spots))
        add_loot("Motel", "crate", 212.35, 56.5, yaw=-90.0, look="filing")             # the manager's cabinet
        # ---- Party walls between the rooms (both storeys; downstairs the office is one, cells 6-7).
        for k in range(1, 8):
            z = z0 + k * MOTEL_CELL
            for f in (0, 1):
                if k == 7:                                        # the office; the card room
                    continue
                wall_x(x0 + 0.15, x1 - 0.15, z, f * FLOOR_H, FLOOR_H, "wall", t=0.2)
        # ---- The rooms: the bathroom at the back (north half), the dressing nook beside it (rail, the back window),
        # the bed against the south wall, the TV dresser opposite, a small table and chair by the front window.
        for f, k, num in motel_rooms():
            c, y = z0 + k * MOTEL_CELL, f * FLOOR_H
            zs = c + (0.15 if k == 0 else 0.1)                    # the room's north and south inside faces
            ze = c + MOTEL_CELL - 0.1
            if num in MOTEL_CASINO:
                inner_door(x1, y, c + 3.85, 90.0, "Motel")
                if num == 208:
                    continue
            washroom(0.0, 0.0, x0 + 0.15, zs, 214.0, c + 2.45, "ES", ("E", c + 1.7, -2), y=y, sign=None, fit=(
                ("wc_bath", "N", 212.5, 1.6, 0.72, 0.55), ("wc_toilet", "W", c + 1.75, 0.45, 0.7, 0.8),
                ("wc_sink", "E", c + 0.75, 0.55, 0.5, 0.85)))
            if num in MOTEL_CASINO:
                continue
            if num == 102:
                # A car through the front (picture: nose down, the bed shoved over); solid, cover in the gallery.
                obox(219.6, 0.6, c + 2.6, 1.9, 1.2, 4.4, 74.0, "car_a", kind="motel_car")
                o(214.6, 0, ze - 2.1, 216.2, 0.6, ze, "wood", "motel_bed", solid=True)
                continue
            special = {204: "nest", 206: "aid"}.get(num, "loot" if num in MOTEL_LOOT_ROOMS else None)
            if special != "aid":
                o(215.6, y, ze - 2.1, 217.2, y + 0.6, ze, "wood", "motel_bed")
                o(214.95, y, ze - 0.45, 215.5, y + 0.55, ze, "wood", "motel_nightstand", solid=False)
                o(217.3, y, ze - 0.45, 217.85, y + 0.55, ze, "wood", "motel_nightstand", solid=False)
            if special == "loot":
                add_loot("Motel", "crate", 216.4, c + 0.7, y=y, yaw=180.0, look="dresser")
            else:
                o(215.5, y, zs, 217.3, y + 0.8, zs + 0.5, "wood", "motel_dresser")
            o(219.15, y, zs + 0.05, 219.85, y + 0.72, zs + 0.75, "wood", "motel_table", solid=False)
            o(212.1, y, c + 2.62, 213.7, y + 1.7, c + 2.92, "metal", "motel_rail", solid=False)
            if special == "nest":   # a sniper's nest on the graveyard: sandbags under the back window, a mattress
                o(211.75, y, c + 3.1, 212.35, y + 0.75, c + 4.7, "sandbag", "motel_sandbags")
            if special == "aid":    # a field dressing station: cots, a supply table
                for zz in (c + 2.9, c + 4.1):
                    o(215.2, y, zz, 217.6, y + 0.45, zz + 0.8, "metal", "motel_cot", solid=False)
                o(215.5, y, zs, 217.3, y + 0.9, zs + 0.6, "metal", "motel_aid_table")
            if f == 0:
                spots.append((218.2, c + 2.4))
            inner_door(x1, y, c + 3.85, 90.0, "Motel")
        # ---- The laundry (downstairs, cell 5): washers along the north wall, dryers, the ice machine, a vending machine.
        c = z0 + 5 * MOTEL_CELL
        o(212.4, 0, c + 0.1, 216.0, 1.0, c + 0.8, "metal", "motel_washers")
        o(x0 + 0.15, 0, c + 1.4, x0 + 0.85, 1.8, c + 3.6, "metal", "dryers")
        o(212.2, 0, c + 4.35, 213.2, 1.8, c + 5.15, "metal", "ice_machine")
        o(213.6, 0, c + 4.3, 214.5, 1.85, c + 5.15, "metal", "vending")
        spots.append((217.0, c + 2.6))
        inner_door(x1, 0.0, c + 3.85, 90.0, "Motel")
        # ---- The office: lobby (front desk, key board behind it, sofa, leaflets, a vending machine) and the manager's
        # flat behind it (back office, bed, kitchenette, staff washroom), through a door at the north end.
        wall_z(55.6, z1 - 0.15, 215.6, 0.0, FLOOR_H, "wall", [(57.2, INNER_DOOR_W, 0.0, DOOR_H)], t=0.2)
        inner_door(215.6, 0.0, 57.2, 90.0, "Motel")
        o(216.7, 0, 59.4, 217.4, 1.05, 63.6, "wood", "motel_desk")
        o(215.72, 1.2, 60.0, 215.76, 2.1, 62.4, "wood", "key_board", solid=False)
        o(217.8, 0, 55.65, 219.8, 0.85, 56.5, "wood", "sofa")
        o(219.6, 0, 58.9, 220.3, 1.6, 60.0, "metal", "leaflet_rack")         # (clear of the vending machine)
        o(219.4, 0, 65.1, 220.3, 1.85, 65.85, "metal", "vending")
        o(211.65, 0, 59.5, 212.45, 0.76, 61.0, "wood", "motel_office_desk")
        o(211.65, 0, 63.7, 212.6, 0.55, 65.85, "wood", "motel_cot_bed")
        o(214.85, 0, 59.3, 215.5, 0.9, 61.3, "wood", "kitchenette")
        washroom(0.0, 0.0, 213.6, 64.0, 215.5, z1 - 0.15, "NW", ("N", 214.1, -2), sign=None, fit=(
            ("wc_toilet", "S", 214.8, 0.45, 0.7, 0.8), ("wc_sink", "E", 64.8, 0.55, 0.5, 0.85)))
        spots += [(218.5, 58.0), (213.6, 61.8)]
        # ---- The card room upstairs (207 + 208 knocked through, blacked-out back windows): slot machines along the
        # back wall, a roulette table, two poker tables, the bar at the south end, the cashier's cage (a safe) in the
        # south-west corner. Set dressing only: none of it plays (store rules: no gambling games).
        y = FLOOR_H
        o(211.65, y, 58.3, 212.35, y + 1.7, 63.6, "metal", "casino_slots")
        o(215.1, y, 56.9, 217.3, y + 0.85, 57.9, "wood", "casino_roulette")
        for px, pz in ((215.4, 61.0), (218.0, 62.3)):
            o(px - 0.6, y, pz - 0.6, px + 0.6, y + 0.78, pz + 0.6, "wood", "casino_table")
        o(214.2, y, 65.2, 218.6, y + 1.1, 65.85, "wood", "casino_bar")
        o(211.65, y, 64.0, 213.6, y + 1.05, 64.3, "wood", "casino_counter")          # the cage: counters, a grille over
        o(213.3, y, 64.3, 213.6, y + 1.05, 64.95, "wood", "casino_counter")          # them, the gate open (south-east)
        o(211.65, y + 1.05, 64.0, 213.6, y + 2.4, z1 - 0.15, "metal", "casino_cage", solid=False)
        add_loot("Motel", "safe", 212.2, 65.3, y=y, yaw=0.0)
        # ---- The gallery: the walkway upstairs (slab, rail), posts, the roof over it all; walled stairs at both ends
        # (one way up each), closed underneath; sandbags on the walkway.
        o(x1 + 0.15, 0.0, z0, G, 0.06, z1, "pavement", "gallery_walk", solid=False)
        o(x1 + 0.15, FLOOR_H - SLAB_T, z0, G, FLOOR_H, z1, "slab")
        o(G - 0.1, FLOOR_H, z0, G, FLOOR_H + 1.0, z1, "metal", "gallery_rail")
        for k in range(9):
            z = min(max(z0 + k * MOTEL_CELL, z0 + 0.1), z1 - 0.1)
            for f in (0, 1):
                o(G - 0.25, f * FLOOR_H, z - 0.1, G - 0.05, f * FLOOR_H + FLOOR_H - (SLAB_T if f == 0 else 0.25), z + 0.1,
                  "wood", "gallery_post")
        o(x1 + 0.15, 2 * FLOOR_H - SLAB_T, z0 - RAMP_L, G + 0.3, 2 * FLOOR_H, z1 + RAMP_L, "roof", "gallery_roof")
        for sz in (-1, 1):
            a = z0 if sz < 0 else z1                                   # where the stairs meet the walkway
            b = a + sz * RAMP_L                                         # their foot
            for wx0, wx1 in ((x1 - 0.15, x1 + 0.15), (G - 0.2, G)):
                o(wx0, 0.0, min(a, b), wx1, 2 * FLOOR_H - SLAB_T, max(a, b), "wall")
            o(x1 + 0.15, 0.0, min(a, a + sz * 0.2), G - 0.2, 2.5, max(a, a + sz * 0.2), "wall")   # closed under the top
            slope = math.hypot(RAMP_L, FLOOR_H)
            # (a plank pitched so its +z end is low, turned so that end points at the foot: see Building._ramp)
            obox((x1 + G) / 2 + 0.03, FLOOR_H / 2 - 0.1, (a + b) / 2, RAMP_W, 0.2, slope, 180.0 if sz < 0 else 0.0,
                 "wood", pitch=math.degrees(math.atan2(FLOOR_H, RAMP_L)))
        for zz in (37.0, 50.5):
            o(G - 0.6, FLOOR_H, zz, G - 0.1, FLOOR_H + 0.9, zz + 2.0, "sandbag", "motel_sandbags")
        # ---- The car park (picture: asphalt, bay lines, kerb stops) and the big sign by the road.
        lx0, lz0, lx1, lz1 = MOTEL_LOT
        o(lx0, 0.0, lz0, lx1, 0.05, lz1, "road", "motel_lot", solid=False)
        o(232.6, 0.0, 66.4, 233.0, 7.6, 66.8, "metal", "motel_sign")
        o(230.5, 7.4, 66.3, 234.9, 10.6, 66.9, "metal", "motel_sign_board", solid=False)
    m.spawn_spots = spots
    # Parked cars (gray box, cover like any car park's), one burnt out.
    for x, z, yaw, col in ((226.5, 27.0, 90, "car_b"), (226.8, 47.5, 95, "car_a"), (226.4, 58.0, 86, "car_b"),
                           (230.0, 36.0, 15, "rust")):
        car(x, z, yaw, col)


def police_furniture(ox, oz):
    """Bloxov police station (World art 0.17), in the model's own coordinates (origin map (ox, oz), rooms 8.67 x
    7.33 m, storeys 3 m). Overrun and ransacked. Furniture is solid like everywhere else; chairs, the mugshot
    camera, bunks and the like are picture only. Room middles, doorways (0.75 m round) and the stairs' feet stay
    clear; nothing stands in front of a window."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Stair walls (owner, bank round: run them the full length so you can't see into rooms, one way up). Ground:
    # the stairs are walled off from the stair hall along their whole side up to the foot, and from the locker room;
    # upstairs the landing is walled off from the chief's office. The roof stairs likewise in the property store.
    o(-13.0, 0, -8.57, -7.4, 2.75, -8.37, "wall_police", None)
    o(-4.43, 0, -10.85, -4.23, 2.75, -8.65, "wall_police", None)
    o(-4.43, 3.0, -10.85, -4.23, 5.75, -8.65, "wall_police", None)
    o(7.4, 3.0, 8.37, 13.0, 5.75, 8.57, "wall_police", None)
    o(4.23, 3.0, 8.65, 4.43, 5.75, 10.85, "wall_police", None)
    # The roof stairs' strip also cut the ground floor's lobby/interview wall (round 2, owner: "the wall here just
    # doesn't go all the way across"): close it.
    o(4.23, 0, 8.65, 4.43, 2.75, 10.85, "wall_police", None)
    # ---- Ground floor.
    # The stair hall (north-west): a bench and the duty board on the south wall, a water cooler, a plant.
    o(-12.6, 0, -4.3, -10.4, 0.5, -3.85, "wood", "hall_bench")
    o(-5.0, 0, -4.4, -4.6, 1.3, -4.0, "metal", "water_cooler")
    o(-12.65, 0, -8.35, -12.25, 1.3, -7.95, "wood", "plant", solid=False)
    # The locker room (north middle): lockers along the south wall either side of the door, benches in front.
    o(-4.0, 0, -4.3, -1.8, 1.9, -3.8, "metal", "hall_lockers")
    o(1.8, 0, -4.3, 4.0, 1.9, -3.8, "metal", "hall_lockers")
    o(-3.0, 0, -5.4, -1.4, 0.45, -5.0, "wood", "hall_bench")
    o(1.4, 0, -5.4, 3.0, 0.45, -5.0, "wood", "hall_bench")
    # The staff washroom in the locker room's north-east corner (owner, 2026-10-16).
    washroom(ox, oz, 1.9, -10.85, 4.23, -8.6, "WS", ("S", 3.3, -1), fit=(
        ("wc_toilet", "N", 3.55, 0.45, 0.72, 0.85), ("wc_sink", "W", -9.9, 0.5, 0.45, 0.9)))
    # The armoury (north-east): rifle racks on the south wall (mostly emptied), ammo crates and cans, the gun
    # cabinets are the loot.
    o(4.9, 0, -4.4, 7.2, 2.2, -3.8, "wood", "armoury_rack")
    o(10.1, 0, -4.4, 12.5, 2.2, -3.8, "wood", "armoury_rack")
    o(4.6, 0, -10.6, 5.6, 0.9, -9.4, "wood", "ammo_crates")
    o(4.6, 0, -5.9, 5.3, 0.6, -4.9, "metal", "ammo_cans")
    # Booking (west middle, the staff door): the booking desk, the height chart and its camera, the fingerprint
    # stand, a bench with a cuff rail.
    o(-12.6, 0, -3.3, -10.5, 1.1, -2.6, "wood", "booking_desk")
    o(-6.6, 0, 1.4, -5.1, 1.6, 1.9, "metal", "mugshot_camera", solid=False)
    o(-12.6, 0, 1.9, -12.0, 1.0, 2.6, "metal", "fingerprint_stand")
    o(-5.0, 0, -3.2, -4.55, 0.5, -1.6, "wood", "cuff_bench")
    # The custody block (owner: lay it out like a real station): prisoners come in by the side door, are booked, then
    # walked straight through to the cells in the middle room (no windows, no way in from the lobby). Five cells off a
    # corridor between the booking door and the squad room: two on the north side (the locker room's door between
    # them), three on the south. Barred fronts are solid, their doors thrown open; bunks and steel toilets.
    for x0, x1 in ((-4.23, -1.3), (1.3, 4.23)):
        o(x0 + 1.0, 0, -1.45, x1, 2.75, -1.3, "metal", "cell_bars")    # (its door, open, in the 1 m west of it)
        o(x0 + 0.1, 0, -3.47, x0 + 1.95, 0.5, -2.75, "metal", "cell_bunk", solid=False)
        o(x1 - 0.55, 0, -3.45, x1 - 0.1, 0.45, -3.0, "metal", "cell_toilet", solid=False)
    for x in (-1.3, 1.2):
        o(x, 0, -3.57, x + 0.1, 2.75, -1.3, "wall_police", None)
    for x0, x1 in ((-4.23, -1.45), (-1.35, 1.35), (1.45, 4.23)):
        o(x0 + 1.0, 0, 1.3, x1, 2.75, 1.45, "metal", "cell_bars")
        o(x0 + 0.1, 0, 2.75, x0 + 1.95, 0.5, 3.47, "metal", "cell_bunk", solid=False)
        o(x1 - 0.55, 0, 3.0, x1 - 0.1, 0.45, 3.45, "metal", "cell_toilet", solid=False)
    for x in (-1.45, 1.35):
        o(x, 0, 1.3, x + 0.1, 2.75, 3.57, "wall_police", None)
    # The squad room (east middle): desks, the loot crate on the east wall.
    o(5.4, 0, -2.6, 7.1, 0.75, -1.1, "wood", "office_pod")
    o(5.4, 0, 1.1, 7.1, 0.75, 2.6, "wood", "office_pod")
    o(10.2, 0, -2.6, 11.9, 0.75, -1.1, "wood", "office_pod")
    # Dispatch (south-west): radio consoles on the north wall, filing cabinets.
    o(-12.6, 0, 4.0, -10.3, 0.8, 4.7, "wood", "dispatch_console")
    o(-6.8, 0, 4.0, -4.7, 0.8, 4.7, "wood", "dispatch_console")
    o(-12.6, 0, 9.9, -12.0, 1.3, 10.6, "metal", "file_cabinet")
    o(-5.2, 0, 10.2, -4.6, 1.3, 10.6, "metal", "file_cabinet")
    # The lobby (south middle, the front door): the front desk behind its screen, waiting seats, a plant.
    o(1.8, 0, 4.6, 3.6, 1.1, 5.3, "wood", "police_desk")
    o(-4.1, 0, 9.0, -3.55, 0.85, 10.6, "metal", "waiting_seats_east", solid=False)
    o(3.75, 0, 10.2, 4.15, 1.3, 10.6, "wood", "plant", solid=False)
    # Interview room (south-east): the table, a filing cabinet.
    o(10.4, 0, 8.9, 12.0, 0.76, 9.8, "metal", "interview_table")
    o(12.2, 0, 4.0, 12.8, 1.3, 4.6, "metal", "file_cabinet")
    # ---- Upstairs.
    # Top of the stairs (north-west): the trophy case, a plant.
    o(-12.6, 3.0, -4.3, -10.3, 5.0, -3.8, "wood", "trophy_case")
    o(-5.0, 3.0, -4.4, -4.6, 4.3, -4.0, "wood", "plant", solid=False)
    # The chief's office (north middle): his desk, bookcase, sofa, cabinet.
    o(-0.9, 3.0, -8.6, 0.9, 3.78, -7.8, "wood", "manager_desk")
    o(3.8, 3.0, -10.5, 4.2, 5.0, -8.9, "wood", "wall_books")
    o(-4.2, 3.0, -10.5, -3.4, 3.85, -8.9, "wood", "sofa")
    o(2.4, 3.0, -4.4, 3.4, 4.3, -3.8, "metal", "file_cabinet")
    # The break room (north-east, caved in): the kitchenette, the vending machine.
    o(4.6, 3.0, -4.4, 6.9, 3.9, -3.8, "wood", "kitchenette")
    o(12.1, 3.0, -5.6, 12.8, 4.9, -4.4, "metal", "vending")
    # Detectives (west middle): two desks, filing cabinets (the case board is on the wall).
    o(-12.3, 3.0, -2.75, -10.6, 3.75, -1.25, "wood", "office_pod")
    o(-12.3, 3.0, 1.25, -10.6, 3.75, 2.75, "wood", "office_pod")
    o(-5.1, 3.0, -3.3, -4.5, 4.3, -2.7, "metal", "file_cabinet")
    # The briefing room (middle): rows of chairs facing the board on the north wall, a lectern.
    o(-3.6, 3.0, 1.4, -1.4, 3.9, 3.2, "metal", "briefing_chairs", solid=False)
    o(1.4, 3.0, 1.4, 3.6, 3.9, 3.2, "metal", "briefing_chairs", solid=False)
    o(2.2, 3.0, -2.6, 2.7, 4.2, -2.2, "wood", "lectern")
    # Evidence (east middle): shelves of evidence boxes.
    o(12.3, 3.0, -3.3, 12.8, 5.0, -1.0, "metal", "archive_shelf")
    o(12.3, 3.0, 1.0, 12.8, 5.0, 3.3, "metal", "archive_shelf")
    o(4.8, 3.0, -3.3, 5.8, 3.8, -2.6, "wood", "paper_boxes")
    # Staff lockers upstairs (south-west): lockers on the north wall, benches.
    o(-12.6, 3.0, 4.0, -10.2, 4.9, 4.45, "metal", "hall_lockers")
    o(-7.2, 3.0, 4.0, -4.7, 4.9, 4.45, "metal", "hall_lockers")
    o(-12.4, 3.0, 5.5, -10.6, 3.45, 5.9, "wood", "hall_bench")
    # Records (south middle): shelves on the south wall either side of the window, a copier, cabinets.
    o(-3.9, 3.0, 10.3, -1.2, 4.8, 10.8, "metal", "archive_shelf")
    o(1.2, 3.0, 10.3, 3.9, 4.8, 10.8, "metal", "archive_shelf")
    o(-3.2, 3.0, 3.9, -2.2, 4.1, 4.6, "metal", "photocopier")
    o(-4.1, 3.0, 3.9, -3.4, 3.45, 4.5, "wood", "paper_boxes", solid=False)
    o(2.0, 3.0, 4.0, 3.0, 4.3, 4.6, "metal", "file_cabinet")
    # The property store (south-east, the roof stairs): shelves of seized goods.
    o(4.8, 3.0, 4.1, 6.0, 3.8, 4.9, "wood", "paper_boxes")


WC_T = 0.15      # a washroom's own walls
WC_DOOR = 0.85   # its doorway (narrower than the AI's 1.5 m: their paths don't go in, so nothing about them changes)


def washroom(ox, oz, x0, z0, x1, z1, walls, door, fit=(), y=0.0, sign="wc_sign", h=None):
    """A washroom in the corner of a room (World art 0.17, owner 2026-10-16: the town had none), in a model's own
    coordinates (origin map (ox, oz)); x0..x1, z0..z1 are its inside faces, y its floor. walls: the sides ("N", "S",
    "E", "W") that need a new thin wall (the others are the room's own walls). door: (side, centre along it, hinge):
    the doorway in one of the new walls and the sign over it outside; the leaf (picture only) hangs on the -1/+1 side
    (along the wall) pushed right open flat against the outside of the wall, or with -2/+2 swung into the washroom. fit: fittings, (kind, side, along, width, depth, height) against an inside wall, or (kind, (xa, za,
    xb, zb), height). The model tiles every wall face looking in (make_building, "washroom" box). h: the walls'
    height (default a 3 m storey's, up to the slab; the station's rooms are taller)."""
    H = h or FLOOR_H - SLAB_T

    def o(a0, b0, c0, a1, b1, c1, kind=None, solid=True, colour="wall"):
        box(ox + a0, y + b0, oz + c0, ox + a1, y + b1, oz + c1, colour, solid=solid, kind=kind)
    dside, dmid, hinge = door
    for side in walls:
        if side in "NS":
            a0, a1 = (x0 - WC_T if "W" in walls else x0), (x1 + WC_T if "E" in walls else x1)
            zz = (z0 - WC_T, z0) if side == "N" else (z1, z1 + WC_T)
            put = lambda a, b, lo, hi: o(a, lo, zz[0], b, hi, zz[1])
        else:
            a0, a1 = z0, z1
            xx = (x0 - WC_T, x0) if side == "W" else (x1, x1 + WC_T)
            put = lambda a, b, lo, hi: o(xx[0], lo, a, xx[1], hi, b)
        if side == dside:
            d0, d1 = dmid - WC_DOOR / 2, dmid + WC_DOOR / 2
            put(a0, d0, 0.0, H)
            put(d0, d1, 2.1, H)
            put(d1, a1, 0.0, H)
        else:
            put(a0, a1, 0.0, H)
    # The open leaf and the sign over the doorway (outside).
    hs = 1 if hinge > 0 else -1
    jamb = dmid + hs * WC_DOOR / 2 - hs * 0.04
    edge = dmid + hs * WC_DOOR / 2
    if dside in "NS":
        face, into = (z0, 1) if dside == "N" else (z1, -1)
        if abs(hinge) == 2:
            o(jamb - 0.02, 0.02, min(face, face + into * 0.8), jamb + 0.02, 2.06, max(face, face + into * 0.8), "wc_door", solid=False)
        else:
            wf = face - into * (WC_T + 0.06)
            o(min(edge, edge + hs * 0.8), 0.02, wf - 0.02, max(edge, edge + hs * 0.8), 2.06, wf + 0.02, "wc_door", solid=False)
        out = face - into * (WC_T + 0.008)
        if sign:
            o(dmid - 0.2, 2.2, out - 0.01, dmid + 0.2, 2.6, out + 0.01, sign, solid=False)
    else:
        face, into = (x0, 1) if dside == "W" else (x1, -1)
        if abs(hinge) == 2:
            o(min(face, face + into * 0.8), 0.02, jamb - 0.02, max(face, face + into * 0.8), 2.06, jamb + 0.02, "wc_door", solid=False)
        else:
            wf = face - into * (WC_T + 0.06)
            o(wf - 0.02, 0.02, min(edge, edge + hs * 0.8), wf + 0.02, 2.06, max(edge, edge + hs * 0.8), "wc_door", solid=False)
        out = face - into * (WC_T + 0.008)
        if sign:
            o(out - 0.01, 2.2, dmid - 0.2, out + 0.01, 2.6, dmid + 0.2, sign, solid=False)
    o(x0, 0.0, z0, x1, H, z1, "washroom", solid=False)
    for f in fit:
        kind = f[0]
        if isinstance(f[1], tuple):
            (xa, za, xb, zb), h = f[1], f[2]
        else:
            side, along, w, d, h = f[1:]
            xa, xb, za, zb = {"N": (along - w / 2, along + w / 2, z0, z0 + d), "S": (along - w / 2, along + w / 2, z1 - d, z1),
                              "W": (x0, x0 + d, along - w / 2, along + w / 2), "E": (x1 - d, x1, along - w / 2, along + w / 2)}[side]
        o(xa, 0.0, za, xb, h, zb, kind)


def cabin_furniture(ox, oz):
    """The hunter's log cabin in the east woods (World art 0.17), in the model's own coordinates (origin map (ox, oz),
    local x -6.5..6.5, z -5..5, front door south in the east room). Main room east: the wood stove on the east wall
    (the fieldstone chimney outside it), the kitchen corner, the table and chairs; bunk room west with the washroom in
    its south-west corner. Room middles, the doorways and the way in stay clear; chairs and the porch roof are picture
    only."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Main room (x 0.15..6.35).
    o(5.55, 0, -3.3, 6.35, 1.0, -1.7, "metal", "cabin_stove")             # stove on its stone hearth, east wall
    o(4.9, 0, 4.25, 6.35, 0.92, 4.85, "wood", "cabin_kitchen")            # counter + sink + hand pump, south wall
    o(5.75, 0, 2.9, 6.35, 1.9, 3.75, "wood", "cabin_shelf")               # shelf of tins in the corner, east wall
    o(0.9, 0, -3.9, 2.4, 0.78, -2.9, "wood", "cabin_table")               # table (tins open, a map), off the middle
    o(0.75, 0, -2.75, 2.55, 1.0, -2.25, "wood", "cabin_chairs", solid=False)  # its chairs (a coat over one)
    o(0.1, 1.15, -4.3, 0.2, 1.85, -2.5, "wood", "cabin_gun_rack", solid=False)   # empty gun rack by the table
    o(4.3, 0, -4.85, 5.5, 1.5, -4.45, "wood", "cabin_radio_shelf")        # radio, maps and lamp on a shelf
    # Bunk room (x -6.35..-0.15): bunks along the north wall, a trunk at their foot, gear by the door.
    o(-6.35, 0, -4.85, -4.35, 1.9, -3.95, "wood", "cabin_bunk")
    o(-4.25, 0, -4.85, -3.7, 0.5, -3.95, "wood", "cabin_trunk")
    o(-6.35, 0, -2.6, -5.85, 1.7, -1.4, "wood", "cabin_gear")             # pegs with jackets, boots, a pack
    o(-2.4, 0, 4.15, -0.5, 0.45, 4.85, "wood", "cabin_cot")              # a spare cot along the south wall
    o(-0.6, 0, -4.0, -0.1, 0.9, -3.0, "wood", "cabin_washstand")         # washstand: basin, jug, shaving mirror
    washroom(ox, oz, -6.35, 3.0, -4.6, 4.85, "NE", ("E", 3.9, -1), sign=None, fit=(
        ("wc_toilet", "W", 4.25, 0.5, 0.65, 0.8), ("wc_sink", "N", -5.75, 0.5, 0.4, 0.85)))
    # The fieldstone chimney on the east gable, outside the stove (solid like the walls; the stack is picture only).
    o(6.65, 0, -3.1, 7.75, 2.6, -1.9, "stone", "cabin_chimney")
    # Porch along the front (picture only, on the building's flat pad, level with the floor inside): deck, posts, bench,
    # chopping block, firewood.
    o(-6.8, 0, 5.15, 6.8, 0.06, 7.2, "wood", "cabin_porch", solid=False)
    o(-5.0, 0.06, 5.2, -3.4, 0.51, 5.6, "wood", "cabin_bench")
    o(5.0, 0.06, 5.2, 6.6, 1.16, 5.75, "wood", "cabin_firewood")
    o(4.9, 0.06, 6.3, 5.5, 0.56, 6.9, "wood", "cabin_block")


CAB_HATCH = (-1.85, -2.0, -0.65, -1.0)   # the loft hatch in the bunk room's ceiling (model-local x0, z0, x1, z1)
CAB_PITCH = 32.0                         # the cabin's roof (make_building draws it: CAB_ROOF_T = tan 32)


def cabin_loft(ox, oz):
    """The east cabin's loft (owner 2026-10-17 picked "loft, no loot"): the flat roof slab is its floor, reached by a
    ladder through a hatch in the bunk room's ceiling. The pitched roof (drawn by the model) gets collision here: its
    two slopes, the gables (a lookout window in the west one, sill 0.6 m over the loft floor), and knee walls where
    the roof comes down to 0.8 m, so nobody crawls into the eaves."""
    def o(x0, y0, z0, x1, y1, z1, kind="cabin_hidden", colour="wood"):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, kind=kind)
    t = math.tan(math.radians(CAB_PITCH))
    for sg in (-1, 1):                    # the roof slopes: 0.2 m thick, their underside on the drawn roof's underside
        zc = sg * 2.6
        yc = 3.0 + (5.15 - 2.6) * t - 0.15 + 0.1 / math.cos(math.radians(CAB_PITCH))
        obox(ox, yc, oz + zc, 14.0, 0.2, 6.4, 0.0, "wood", pitch=sg * CAB_PITCH, kind="cabin_hidden")
    for sx in (-1, 1):                    # gables (stepped to sit inside the roof)
        x0, x1 = (-6.65, -6.35) if sx < 0 else (6.35, 6.65)
        if sx < 0:                        # the west one's window: z -0.5..0.5, y 3.6..4.5
            o(x0, 3.0, -2.6, x1, 4.4, -0.5); o(x0, 3.0, 0.5, x1, 4.4, 2.6); o(x0, 3.0, -0.5, x1, 3.6, 0.5)
            o(x0, 4.4, -1.6, x1, 5.0, -0.5); o(x0, 4.4, 0.5, x1, 5.0, 1.6); o(x0, 4.5, -0.5, x1, 5.0, 0.5)
        else:
            o(x0, 3.0, -2.6, x1, 4.4, 2.6); o(x0, 4.4, -1.6, x1, 5.0, 1.6)
        o(x0, 5.0, -0.7, x1, 5.8, 0.7)
    for sg in (-1, 1):                    # knee walls (planks, drawn)
        z0, z1 = (-3.6, -3.5) if sg < 0 else (3.5, 3.6)
        o(-6.35, 3.0, z0, 6.35, 3.9, z1, kind="cabin_knee")
    ladder(ox - 1.25, 0.0, oz + CAB_HATCH[3] - 0.12, 180.0, 3.0, "Cabin3")   # (leans on the hatch's south edge)
    # The loft's things (picture only but the crates): a straw mattress and bedroll, a stool and binoculars at the
    # window, two crates, a coil of rope.
    o(-5.6, 3.0, -1.6, -3.6, 3.15, -0.6, kind="cabin_loft_bed", colour="wood")
    o(-6.3, 3.0, 0.7, -5.7, 3.5, 1.3, kind="cabin_loft_stool")
    o(2.0, 3.0, -2.2, 2.8, 3.5, -1.5, kind="cabin_loft_crates")
    o(4.2, 3.0, 1.4, 5.0, 3.5, 2.1, kind="cabin_loft_crates")


FC_X = -2.4        # the fisherman's cabin: the log wall between the main block (east) and the lean-to (west)
FC_BED_Z = -1.2    # the bedroom's wall (main block, north)
FC_WC_Z = 1.6      # the washroom's wall (lean-to, south)
FC_RIDGE_X = 2.05  # the main block's ridge (and its front door, porch, fireplace)


def fisher_cabin(x, y):
    """The fisherman's cabin in the bottom-left woods (World art 0.17, owner 2026-10-17: the two cabins there alike,
    but not like the hunter's cabin in the east woods). Cabin1's spot and size (13 x 10 m), the creek just west of it.
    A log main block with its gable to the front (south) and a lean-to down the creek side (west): main room with the
    fireplace (the chimney goes up through the ridge) and kitchen, the bedroom behind it, the gear room (rods, nets,
    waders) and the washroom in the lean-to. Same one duffel."""
    ox, oz = x + 6.5, y + 5.0

    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    ops = {"S": [("window", ox - 4.45, 0.8, 1.5, 2.1), ("window", ox - 0.75, WIN_W, WIN_LO, WIN_HI),
                 ("door", ox + FC_RIDGE_X, DOOR_W, 0.0, DOOR_H), ("window", ox + 5.0, WIN_W, WIN_LO, WIN_HI)],
           "N": [("window", ox - 3.35, WIN_W, WIN_LO, WIN_HI), ("window", ox + 2.05, WIN_W, WIN_LO, WIN_HI)],
           "E": [("window", oz + 0.5, WIN_W, WIN_LO, WIN_HI), ("window", oz - 3.05, WIN_W, WIN_LO, WIN_HI)],
           "W": [("window", oz - 1.6, WIN_W, WIN_LO, WIN_HI), ("window", oz + 3.3, 0.8, 1.5, 2.1)]}
    cab = Building("Cabin1", x, y, 13, 10, colour="wood", rooms=(2, 1), doors="S", open_plan=True, wall_openings=ops,
                   spawn_spots=[(ox - 4.4, oz - 1.6), (ox + 3.6, oz + 2.2)])
    build(cab)
    add_loot("Cabin1", "crate", ox - 5.8, oz + 0.55, yaw=-90.0)            # the duffel, gear room by the west wall
    H = FLOOR_H - SLAB_T
    # Inner walls: the old log wall between the main block and the lean-to (the gear room's doorway), the bedroom's
    # plank wall (its doorway east of the fireplace).
    wall_z(oz - 4.85, oz + 4.85, ox + FC_X, 0.0, H, "wood", [(oz + 0.25, INNER_DOOR_W, 0.0, DOOR_H)], t=0.3)
    inner_door(ox + FC_X, 0.0, oz + 0.25, 90.0, "Cabin1")
    wall_x(ox + FC_X + 0.15, ox + 6.35, oz + FC_BED_Z, 0.0, H, "wood", [(ox + 4.4, INNER_DOOR_W, 0.0, DOOR_H)], t=0.2)
    inner_door(ox + 4.4, 0.0, oz + FC_BED_Z, 0.0, "Cabin1")
    washroom(ox, oz, -6.35, FC_WC_Z + 0.075, FC_X - 0.15, 4.85, "N", ("N", -3.4, 2), sign=None, fit=(
        ("wc_toilet", "W", 2.6, 0.5, 0.65, 0.8), ("wc_sink", "S", -5.6, 0.5, 0.4, 0.85),
        ("wc_bath", "E", 3.75, 0.75, 1.65, 0.6)))
    # Main room (x -2.25..6.35, z -1.1..4.85): the stone fireplace on the bedroom wall under the ridge, the range and
    # kitchen counter along the east wall, the table by the front window, a rocking chair at the fire.
    o(1.15, 0, FC_BED_Z + 0.1, 2.95, 1.6, FC_BED_Z + 0.8, "stone", "fc_fireplace")
    o(5.75, 0, 1.55, 6.35, 0.92, 4.85, "wood", "fc_kitchen")
    o(5.55, 0, -1.1, 6.35, 1.05, -0.45, "metal", "fc_range")
    o(-1.75, 0, 3.2, -0.25, 0.78, 4.15, "wood", "cabin_table")
    o(-1.9, 0, 2.65, -0.1, 1.0, 3.15, "wood", "cabin_chairs", solid=False)
    o(0.2, 0, -0.1, 0.9, 1.1, 0.7, "wood", "fc_rocker", solid=False)
    # Bedroom (x -2.25..6.35, z -4.85..-1.3): the bed against the north wall, a wardrobe, a chest of drawers, a trunk.
    o(-0.7, 0, -4.85, 0.9, 0.6, -2.75, "wood", "fc_bed")
    o(-2.25, 0, -4.85, -1.65, 2.0, -3.65, "wood", "fc_wardrobe")
    o(5.1, 0, -4.85, 6.35, 0.95, -4.35, "wood", "fc_drawers")
    o(-2.25, 0, -2.4, -1.75, 0.55, -1.6, "wood", "cabin_trunk")
    # Gear room (lean-to, x -6.35..-2.55, z -4.85..1.5): rods on the north wall, the tackle bench on the west wall,
    # waders on pegs, a cooler; the duffel against the west wall by the washroom.
    o(-6.35, 0, -4.85, -4.6, 2.1, -4.6, "wood", "fc_rod_rack", solid=False)
    o(-6.35, 0, -4.4, -5.75, 0.9, -3.0, "wood", "fc_tackle_bench")
    o(-2.95, 0, -4.2, -2.55, 1.8, -2.6, "wood", "fc_waders")
    o(-5.0, 0, 0.9, -4.4, 0.5, 1.45, "wood", "fc_cooler")
    # Outside: the porch under the front gable (deck, posts and roof picture only), a bench; the canoe on trestles
    # and the fish drying rack on the creek side; firewood stacked against the lean-to's south wall.
    o(-2.55, 0, 5.15, 6.65, 0.06, 7.4, "wood", "cabin_porch", solid=False)
    o(4.6, 0.06, 5.25, 6.1, 0.5, 5.65, "wood", "cabin_bench")
    o(-8.6, 0, -2.9, -7.4, 0.9, 2.3, "wood", "fc_canoe")
    o(-8.7, 0, 2.9, -7.6, 1.8, 4.9, "wood", "fc_fish_rack", solid=False)
    o(-6.3, 0, 5.15, -3.6, 1.2, 5.75, "wood", "cabin_firewood")


TC_X = 2.4          # the trapper's cabin (mirrors the fisherman's): the log wall between the main block (west) and the lean-to
TC_BED_Z = -1.0     # the bedrooms' wall (main block, north)
TC_BED_X = -2.05    # the wall between the two bedrooms (under the ridge)
TC_STORE_Z = -1.6   # the pantry's and washroom's wall (lean-to, north)
TC_WC_X = 4.375     # the washroom's west inside face (the pantry west of it)


def trapper_cabin(x, y):
    """The trapper's cabin in the bottom-left woods, west of the creek (World art 0.17, owner 2026-10-17: like the
    fisherman's cabin but laid out differently, and not like the hunter's cabin in the east woods). Cabin2's spot and
    size (13 x 10 m). The fisherman's shape mirrored: a log main block with its gable to the front (south) and a
    lean-to on the creek side (east), but no gable porch: the way in is the lean-to's door under a low porch roof.
    Lean-to: the workroom (traps, pelt stretchers, the duffel), the pantry and the washroom. Main block: the main room
    (barrel stove, kitchen, trestle table) and two small bedrooms. Outside (west): a woodshed, a sawhorse, the
    chopping block; a raised cache on stilts behind. Same one duffel."""
    ox, oz = x + 6.5, y + 5.0

    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    ops = {"S": [("window", ox - 3.5, WIN_W, WIN_LO, WIN_HI), ("window", ox - 0.6, WIN_W, WIN_LO, WIN_HI),
                 ("door", ox + 4.45, DOOR_W, 0.0, DOOR_H)],
           "N": [("window", ox - 3.9, WIN_W, WIN_LO, WIN_HI), ("window", ox + 1.2, WIN_W, WIN_LO, WIN_HI),
                 ("window", ox + 5.4, 0.8, 1.5, 2.1)],
           "E": [("window", oz + 3.4, WIN_W, WIN_LO, WIN_HI)],
           "W": [("window", oz + 3.0, WIN_W, WIN_LO, WIN_HI)]}
    cab = Building("Cabin2", x, y, 13, 10, colour="wood", rooms=(2, 1), doors="S", open_plan=True, wall_openings=ops,
                   spawn_spots=[(ox - 0.8, oz + 1.6), (ox + 4.2, oz + 1.8)])
    build(cab)
    add_loot("Cabin2", "crate", ox + 5.8, oz + 2.0, yaw=90.0)             # the duffel, workroom by the east wall
    H = FLOOR_H - SLAB_T
    # Inner walls: the old log wall between the main block and the lean-to (the workroom's doorway), the bedrooms'
    # plank wall (a doorway into each) and the plank wall between them, the pantry's plank wall (a narrow doorway).
    wall_z(oz - 4.85, oz + 4.85, ox + TC_X, 0.0, H, "wood", [(oz + 2.2, INNER_DOOR_W, 0.0, DOOR_H)], t=0.3)
    inner_door(ox + TC_X, 0.0, oz + 2.2, 90.0, "Cabin2")
    wall_x(ox - 6.35, ox + TC_X - 0.15, oz + TC_BED_Z, 0.0, H, "wood",
           [(ox - 4.4, INNER_DOOR_W, 0.0, DOOR_H), (ox + 0.15, INNER_DOOR_W, 0.0, DOOR_H)], t=0.2)
    inner_door(ox - 4.4, 0.0, oz + TC_BED_Z, 0.0, "Cabin2")
    inner_door(ox + 0.15, 0.0, oz + TC_BED_Z, 0.0, "Cabin2")
    wall_z(oz - 4.85, oz + TC_BED_Z - 0.1, ox + TC_BED_X, 0.0, H, "wood", t=0.2)
    washroom(ox, oz, TC_WC_X, -4.85, 6.35, TC_STORE_Z, "WS", ("S", 5.4, 2), sign=None, fit=(
        ("wc_bath", "N", 5.36, 1.65, 0.75, 0.6), ("wc_toilet", "E", -2.9, 0.5, 0.65, 0.8),
        ("wc_sink", "W", -3.3, 0.5, 0.4, 0.85)))
    wall_x(ox + TC_X + 0.15, ox + TC_WC_X - WC_T, oz + TC_STORE_Z + WC_T / 2, 0.0, H, "wood", [(ox + 3.4, 0.9, 0.0, DOOR_H)],
           t=WC_T)
    # Main room (x -6.35..2.25, z -0.9..4.85): the barrel stove on the west wall (its pipe up through the roof), the
    # woodbox, the kitchen counter in the south-west corner, the trestle table and its benches, a hutch on the
    # bedrooms' wall between their doors.
    o(-6.35, 0, 0.0, -5.6, 1.1, 1.0, "metal", "tc_stove")
    o(-6.35, 0, -0.75, -5.8, 0.6, -0.2, "wood", "tc_woodbox")
    o(-6.35, 0, 4.2, -4.45, 0.92, 4.85, "wood", "tc_kitchen")
    o(-4.6, 0, 1.55, -2.6, 0.78, 2.35, "wood", "tc_table")
    o(-4.5, 0, 1.0, -2.7, 0.45, 1.35, "wood", "tc_bench", solid=False)
    o(-4.5, 0, 2.55, -2.7, 0.45, 2.9, "wood", "tc_bench", solid=False)
    o(-3.15, 0, -0.9, -1.1, 1.9, -0.45, "wood", "tc_hutch")
    # West bedroom (the trapper's, x -6.35..-2.15): a log bed with a fur blanket on the west wall, a nightstand, a
    # trunk at the foot, coats and his hat on pegs on the plank wall.
    o(-6.35, 0, -4.85, -4.95, 0.6, -2.85, "wood", "tc_bed")
    o(-4.85, 0, -4.85, -4.35, 0.6, -4.4, "wood", "tc_stand")
    o(-6.35, 0, -2.7, -5.75, 0.55, -1.9, "wood", "cabin_trunk")
    o(-2.7, 0.9, -4.6, -2.15, 1.9, -2.6, "wood", "tc_pegs", solid=False)
    # East bedroom (x -1.95..2.25): the bunk along the north wall, a footlocker, a stool with a lamp.
    o(-1.95, 0, -4.85, 0.05, 1.9, -3.95, "wood", "cabin_bunk")
    o(1.65, 0, -3.3, 2.25, 0.5, -2.2, "wood", "tc_footlocker")
    o(-1.9, 0, -2.4, -1.45, 0.5, -1.95, "wood", "tc_stool", solid=False)
    # Pantry (x 2.55..4.225, z -4.85..-1.6): shelves of jars and tins on the log wall, a barrel and sacks.
    o(2.55, 0, -4.85, 3.0, 2.0, -2.0, "wood", "tc_pantry_shelf")
    o(3.35, 0, -4.85, 4.225, 0.9, -4.15, "wood", "tc_sacks")
    # Workroom (lean-to, x 2.55..6.35, z -1.45..4.85): the workbench on the east wall (traps hung over it), stretcher
    # boards leaning on the log wall; the duffel by the bench.
    o(5.7, 0, -0.6, 6.35, 0.95, 1.3, "wood", "tc_workbench")
    o(2.55, 0, -1.2, 2.85, 1.7, 0.9, "wood", "tc_stretchers", solid=False)
    # Outside: the porch along the lean-to's front (deck picture only, its roof the lean-to's run on), a bench; the
    # woodshed, sawhorse and chopping block on the west side; the raised cache behind (its stilts and box solid, the
    # ladder and roof picture only); a pelt rack on the creek side.
    o(2.4, 0, 5.15, 6.95, 0.06, 7.0, "wood", "cabin_porch", solid=False)
    o(5.75, 0.06, 5.25, 6.85, 0.5, 5.65, "wood", "cabin_bench")
    o(-9.2, 0, -3.8, -7.4, 1.6, -0.2, "wood", "tc_woodshed")
    o(-9.2, 0, 2.5, -7.8, 0.95, 3.3, "wood", "tc_sawhorse")
    o(-8.1, 0, 4.2, -7.5, 0.55, 4.8, "wood", "cabin_block")
    for lx, lz in ((-5.1, -7.8), (-3.7, -7.8), (-5.1, -6.4), (-3.7, -6.4)):
        o(lx - 0.1, 0, lz - 0.1, lx + 0.1, 2.0, lz + 0.1, "wood", "cabin_hidden")
    o(-5.3, 2.0, -8.0, -3.5, 3.2, -6.2, "wood", "cabin_hidden")
    o(-5.4, 0, -8.1, -3.4, 3.7, -6.1, "wood", "tc_cache", solid=False)
    o(6.7, 0, -0.8, 7.3, 1.9, 1.8, "wood", "tc_pelt_rack", solid=False)


def station_furniture(ox, oz):
    """Bloxov Station (World art 0.17) in the model's own coordinates (origin map (ox, oz); local x -19..19, z -7..7,
    walls 3.6 m, north = Station Road, south = the platform). Room middles, doorways and the way through stay clear;
    the waiting room's washrooms are in its north corners, the roof stairs (along the south wall of the east room,
    rising east) are walled off from the room (owner rule), the ticket windows are drawn on the hall's east wall."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    H = 3.355                                                              # the roof slab's underside
    # Waiting room (x -18.85..-6.43): men's and women's washrooms in the north corners, benches along the south wall
    # (off the window), the stove on the east wall, a vending machine, the left luggage (the crate) on the west wall.
    washroom(ox, oz, -18.85, -6.85, -15.55, -3.9, "ES", ("S", -16.4, -1), sign="wc_sign_m", h=H, fit=(
        ("wc_toilet", "W", -6.1, 0.5, 0.65, 0.8), ("wc_urinal", "N", -17.3, 0.4, 0.35, 1.2),
        ("wc_urinal", "N", -16.6, 0.4, 0.35, 1.2), ("wc_sink", "E", -5.0, 0.5, 0.4, 0.85)))
    washroom(ox, oz, -9.75, -6.85, -6.43, -3.9, "WS", ("S", -8.0, 1), sign="wc_sign_f", h=H, fit=(
        ("wc_toilet", "E", -6.1, 0.5, 0.65, 0.8), ("wc_sink", "W", -5.0, 0.5, 0.4, 0.85)))
    o(-18.6, 0, 6.3, -14.1, 0.95, 6.85, "wood", "st_bench")
    o(-11.2, 0, 6.3, -6.9, 0.95, 6.85, "wood", "st_bench")
    o(-7.15, 0, 2.6, -6.43, 1.1, 3.6, "metal", "st_stove")
    o(-15.2, 0, -6.85, -14.3, 1.85, -6.15, "metal", "vending")
    # Booking hall (x -6.23..6.23): the ticket windows on its east wall (picture only), a bench on the west wall, the
    # departures board hanging over the way through, the EXION checkpoint by the platform door (sandbags, a table).
    o(6.08, 0.95, -5.3, 6.23, 2.3, -4.1, "wood", "st_ticket_window", solid=False)
    o(6.08, 0.95, -3.3, 6.23, 2.3, -2.1, "wood", "st_ticket_window", solid=False)
    o(-6.23, 0, 2.2, -5.7, 0.95, 5.2, "wood", "st_bench")
    o(-1.6, 2.55, -2.2, 1.6, 3.2, -2.0, "metal", "st_departures", solid=False)
    o(-3.1, 0, 6.2, -1.45, 0.65, 6.85, "wood", "st_sandbags")
    o(1.45, 0, 6.2, 3.1, 0.65, 6.85, "wood", "st_sandbags")
    o(-5.9, 0, 3.6, -5.0, 0.76, 5.3, "wood", "st_check_table")            # (in front of the bench's south end)
    # East room (x 6.43..18.85): the ticket office behind the windows (desk along the hall wall, ticket rack on the
    # north wall), the station master's desk, safe and key board in the north-east, parcels in the south-east by the
    # walled-in roof stairs. The way from the hall doorway to the stairs' foot (x 9.3..11.1) stays clear.
    o(6.43, 0, -6.0, 7.1, 1.0, -2.0, "wood", "st_ticket_desk")
    o(7.4, 0, -6.85, 9.6, 2.2, -6.45, "wood", "st_ticket_rack")
    o(14.6, 0, -5.4, 16.2, 0.78, -4.6, "wood", "st_master_desk")
    o(18.15, 0, -6.6, 18.85, 0.9, -5.8, "metal", "small_safe")
    o(16.9, 1.0, -6.85, 18.0, 1.9, -6.7, "wood", "st_key_board", solid=False)
    o(11.6, 0, 3.75, 15.6, 2.0, 4.45, "wood", "st_parcel_shelf")
    o(16.0, 0, 3.3, 16.9, 0.9, 4.2, "metal", "st_scale")
    o(10.9, 0, 4.45, 18.85, H, 4.65, "wall", None)                        # the roof stairs' wall (open at the foot)
    # Platform (x -23..27, z 8..10.6, 0.8 m up): filled to the wall along the station, a ramp up from the platform
    # door (drawn as steps), the canopy's columns, benches against the wall, a baggage cart, nameboards at the ends.
    o(-23.0, 0, 8.0, 27.0, 0.8, 10.6, "concrete", "st_platform")
    o(-19.0, 0, 7.15, -1.1, 0.8, 8.0, "concrete", "st_platform")
    o(1.1, 0, 7.15, 19.0, 0.8, 8.0, "concrete", "st_platform")
    t = math.atan2(0.8, 1.25)        # (turned round: its low end at the door, 33 degrees)
    obox(ox, 0.4 - 0.08 * math.cos(t), oz + 7.775 + 0.08 * math.sin(t), 2.2, 0.16, math.hypot(1.25, 0.8), 180.0, "wood",
         pitch=math.degrees(t), kind="st_steps")
    for x in range(-10, 15, 4):
        o(x - 0.08, 0.8, 9.92, x + 0.08, 3.3, 10.08, "metal", "st_column")
    o(-14.1, 0.8, 9.92, -13.9, 1.4, 10.08, "metal", "st_column_stub")   # (snapped: the west end came down)
    # The platform canopy (owner 2026-10-17: solid, you can climb out onto it from the roof over the parapet). Its
    # west end was blown off (owner: more war damage): the wreck lies on the platform, picture only.
    o(-11.6, 3.3, 7.15, 17.5, 3.45, 10.75, "roof", "st_canopy")
    o(-18.0, 0.8, 7.7, -11.8, 1.6, 10.6, "roof", "st_canopy_wreck", solid=False)
    o(-9.2, 0.8, 7.15, -7.0, 1.75, 7.7, "wood", "st_bench")
    o(7.0, 0.8, 7.15, 9.2, 1.75, 7.7, "wood", "st_bench")
    o(11.6, 0.8, 8.9, 13.6, 1.5, 9.9, "wood", "st_cart")
    o(-23.0, 0.8, 9.9, -21.0, 3.3, 10.1, "metal", "st_nameboard", solid=False)
    o(25.0, 0.8, 9.9, 27.0, 3.3, 10.1, "metal", "st_nameboard", solid=False)
    o(-22.0, 0.8, 8.4, -21.8, 4.0, 8.6, "metal", "st_lamp", solid=False)
    o(25.8, 0.8, 8.4, 26.0, 4.0, 8.6, "metal", "st_lamp", solid=False)
    # The street front: a little canopy over the door (solid like the platform's), the clock gable over it stands
    # on the parapet (solid like it).
    o(-1.7, 2.75, -8.45, 1.7, 2.9, -7.15, "roof", "st_porch")
    o(-1.6, 4.6, -7.15, 1.6, 6.2, -6.85, "wall", "st_gable")


def depot_furniture(ox, oz):
    """The goods shed (World art 0.17, owner 2026-10-17: "goods shed with a loading dock and crates", "a lot more war
    ruined"), in the model's own coordinates (origin map (ox, oz); local x -15..15, z -9..9, walls 7 m, big doors west
    and east at z 0, the roof gone). A track comes in through the west door along z 0 (its rails torn up outside) to
    a buffer stop, an open wagon on it; the loading dock (1.1 m, solid) south of the track with steps at the west end
    and a cart ramp at the east end, a hand crane on its edge, crates and sacks; the weigh office (with the staff
    washroom) in the north-east corner, a forklift, the roof's wreckage in a heap. The doorways, the way along the
    track, the north hole's way in and the aisle behind the dock (the south crate) stay clear."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)

    def slope(x_lo, x_hi, z0, z1, rise, kind):
        """A slab from the floor at x_lo up to `rise` at x_hi (its top surface on that line)."""
        run = abs(x_hi - x_lo)
        t = math.atan2(rise, run)
        n = math.copysign(1.0, x_lo - x_hi)          # the surface's normal leans toward the low end
        cx = (x_lo + x_hi) / 2 - 0.08 * n * math.sin(t)
        obox(ox + cx, rise / 2 - 0.08 * math.cos(t), oz + (z0 + z1) / 2, z1 - z0, 0.16, math.hypot(run, rise),
             90.0 if x_lo > x_hi else -90.0, "concrete", pitch=math.degrees(t), kind=kind)
    # The track: an open wagon on it, the buffer stop at its end (the rails themselves are drawn by the model).
    o(-8.5, 0, -1.3, -1.5, 2.3, 1.3, "wood", "dp_wagon")
    o(11.6, 0, -1.0, 12.3, 1.1, 1.0, "metal", "dp_buffer")
    # The loading dock, its steps (west) and cart ramp (east); the crane on its edge over the track.
    o(-12.0, 0, 2.2, 11.0, 1.1, 6.4, "concrete", "dp_dock")
    slope(-14.4, -12.0, 2.6, 4.2, 1.1, "st_steps")
    slope(13.4, 11.0, 3.1, 5.5, 1.1, "dp_ramp")                            # (room at its foot for the AI)
    o(2.3, 1.1, 2.55, 2.75, 4.4, 3.0, "metal", "dp_crane")
    o(-10.8, 1.1, 4.4, -8.6, 2.6, 6.2, "wood", "dp_crates")
    o(-6.8, 1.1, 4.6, -5.0, 1.9, 6.2, "wood", "dp_sacks")
    o(5.0, 1.1, 4.0, 7.4, 2.3, 6.2, "wood", "dp_crates")
    add_loot("Depot", "crate", ox + 9.6, oz + 5.9, y=1.1, yaw=0.0)                  # (owner: more loot spots here)
    # North floor: crates and sacks in the north-west, the roof's wreckage, fuel drums by the west door, the forklift.
    o(-12.6, 0, -8.7, -10.4, 1.6, -6.6, "wood", "dp_crates")
    o(-10.0, 0, -8.7, -8.2, 0.9, -7.3, "wood", "dp_sacks")
    o(-12.2, 0, -5.6, -8.8, 0.7, -3.2, "metal", "dp_wreck")
    o(-14.6, 0, -3.7, -13.4, 1.0, -2.5, "metal", "fuel_drums")
    o(3.6, 0, -7.9, 6.2, 2.2, -6.7, "metal", "dp_forklift")
    # The weigh office (north-east corner): timber walls 3 m, a door and a window in its south wall, the scale outside it; the
    # clerk's desk and the filing cabinet inside (a new loot spot, owner OK), the staff washroom in its corner.
    H = 3.0
    o(9.4, 0, -4.52, 9.55, H, -4.4, "wall", None)
    o(9.55, 2.1, -4.52, 11.55, H, -4.4, "wall", None)                     # (a 2 m door: the AI's paths go in)
    o(11.55, 0, -4.52, 11.95, H, -4.4, "wall", None)
    o(11.95, 0, -4.52, 13.0, 1.0, -4.4, "wall", None)                    # (the office window, x 11.95..13.0)
    o(11.95, 2.1, -4.52, 13.0, H, -4.4, "wall", None)
    o(13.0, 0, -4.52, 14.85, H, -4.4, "wall", None)
    o(9.4, 0, -8.85, 9.52, H, -4.52, "wall", None)
    o(9.3, H, -8.85, 14.85, H + 0.12, -4.3, "wood", "dp_hut_roof")
    o(9.52, 0, -8.85, 11.4, 0.78, -8.15, "wood", "dp_desk")
    add_loot("Depot", "crate", ox + 12.5, oz - 8.45, yaw=180.0, look="filing")
    washroom(ox, oz, 13.25, -8.85, 14.85, -6.95, "WS", ("S", 14.05, -2), h=H, fit=(
        ("wc_toilet", "N", 13.7, 0.5, 0.65, 0.8), ("wc_sink", "E", -7.8, 0.5, 0.4, 0.85)))
    o(7.6, 0, -6.4, 8.5, 0.9, -5.5, "metal", "st_scale")


def signal_box_furniture(ox, oz):
    """Bloxov Junction signal box (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -6..6,
    z -5..5, two 3 m storeys, north = the railway). The outside stair runs up the south wall (rising east) to a landing
    at the lever room's door. Downstairs: the lamp room (west, the street door, the washroom) and the locking room
    (east) behind a partition; upstairs: the lever room, open. Room middles (the AI's spawn spots downstairs), the
    doorways and the stair's landing stay clear."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # The outside stair: a ramp from the ground (x -4.0) up to the landing (x 0.4..2.9) at the lever room's floor,
    # railed on the outside; posts under it.
    t = math.atan2(FLOOR_H, RAMP_L)
    zc = 5.15 + RAMP_W / 2
    obox(ox - 4.0 + RAMP_L / 2 + 0.1 * math.sin(t), FLOOR_H / 2 - 0.1 * math.cos(t), oz + zc, RAMP_W, 0.2,
         math.hypot(RAMP_L, FLOOR_H), -90.0, "wood", pitch=math.degrees(t), kind="sb_stair")
    o(0.4, FLOOR_H - 0.2, 5.15, 2.9 + 0.1, FLOOR_H, 5.15 + RAMP_W, "wood", "sb_landing")
    o(0.4, FLOOR_H, 5.15 + RAMP_W, 2.9 + 0.1, FLOOR_H + 1.0, 5.15 + RAMP_W + 0.08, "metal", "sb_rail")   # (landing only: owner)
    o(2.92, FLOOR_H, 5.15, 3.0, FLOOR_H + 1.0, 5.15 + RAMP_W, "metal", "sb_rail")
    # Lamp room (x -5.85..-1.6): the washroom in the north-west corner, a workbench under the west window, signal
    # lamps on shelves against the partition, oil drums; the crate (a toolbox) against the west wall north of the street door (owner: it stuck out of the south wall).
    o(-1.6, 0, -4.85, -1.4, FLOOR_H - SLAB_T, -1.5, "wall", None)          # the partition, a doorway at z -1.5..0.7
    o(-1.6, 2.4, -1.5, -1.4, FLOOR_H - SLAB_T, 0.7, "wall", None)
    o(-1.6, 0, 0.7, -1.4, FLOOR_H - SLAB_T, 4.85, "wall", None)
    washroom(ox, oz, -5.85, -4.85, -4.2, -3.0, "ES", ("S", -5.0, -2), fit=(
        ("wc_toilet", "N", -5.3, 0.5, 0.65, 0.8), ("wc_sink", "E", -4.4, 0.5, 0.4, 0.85)))
    o(-5.85, 0, -2.4, -5.2, 0.9, -0.9, "wood", "sb_bench")
    o(-2.15, 0, 1.4, -1.6, 1.9, 3.8, "wood", "sb_lamps")
    o(-3.3, 0, -4.85, -2.1, 1.0, -4.25, "metal", "fuel_drums")
    # Locking room (x -1.4..5.85): the interlocking under the lever frame along the north wall (rods up through the
    # ceiling), relay racks along the south wall, the battery shelf.
    o(-0.8, 0, -4.85, 4.6, 1.1, -3.9, "metal", "sb_locking")
    o(0.0, 0, 4.3, 5.0, 2.0, 4.85, "metal", "sb_relays")
    o(5.3, 0, 0.9, 5.85, 1.2, 3.2, "metal", "sb_batteries")
    # Lever room (upstairs): the lever frame along the north wall (its base solid, the levers picture only), the
    # track diagram over it, the train register desk east of the door, the stove on the west wall, a chair.
    F = FLOOR_H
    o(-4.5, F, -3.9, 4.0, F + 0.6, -3.1, "metal", "sb_frame")
    o(-1.5, F + 1.75, -4.85, 1.5, F + 2.55, -4.8, "wood", "sb_diagram", solid=False)
    o(3.2, F, 4.2, 5.2, F + 0.8, 4.85, "wood", "sb_desk")
    o(-5.85, F, -1.6, -5.2, F + 1.1, -0.6, "metal", "st_stove")
    o(0.6, F, -1.0, 1.1, F + 0.9, -0.5, "wood", "sb_chair", solid=False)


def diner_furniture(ox, oz):
    """The diner (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -8..8, z -6..6, one
    3 m storey; north = the highway). Dining room west: the counter and stools along the kitchen wall, booths and
    tables, the jukebox, the washroom in the south-west corner. Kitchen east: the range and grill, the sink, the
    fridge, shelves. The doorways, the room middles (AI spawn spots) and the holes' ways in stay clear."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Dining room (x -7.85..-0.1).
    o(-1.6, 0, 1.5, -0.9, 1.05, 4.7, "wood", "dn_counter")
    o(-1.5, 0, -3.4, -0.6, 1.4, -1.5, "metal", "dn_pie_case")
    for z in (1.9, 2.7, 3.5, 4.3):
        o(-2.25, 0, z - 0.2, -1.85, 0.75, z + 0.2, "metal", "dn_stool", solid=False)
    o(-7.85, 0, -4.6, -6.3, 1.2, -1.5, "wood", "dn_booth")
    o(-7.85, 0, 1.4, -6.3, 1.2, 3.3, "wood", "dn_booth")
    o(-4.3, 0, 2.2, -3.4, 0.76, 3.1, "wood", "dn_table")
    o(-4.6, 0, -4.6, -3.7, 0.76, -3.7, "wood", "dn_table")
    o(-1.65, 0, 5.2, -0.85, 1.6, 5.85, "metal", "dn_jukebox")
    # (owner 2026-10-17: the booth blocked the washroom's door: the door is on its east wall now, onto the open floor)
    washroom(ox, oz, -7.85, 3.6, -6.0, 5.85, "EN", ("E", 4.8, -2), fit=(
        ("wc_toilet", "W", 5.3, 0.5, 0.65, 0.8), ("wc_sink", "N", -7.3, 0.5, 0.4, 0.85)))
    # Kitchen (x 0.1..7.85).
    o(0.5, 0, 5.15, 3.0, 0.95, 5.85, "metal", "dn_range")
    o(3.3, 0, 5.25, 4.7, 0.9, 5.85, "metal", "dn_sink")
    o(5.0, 0, 5.1, 6.1, 1.95, 5.85, "metal", "dn_fridge")
    o(0.1, 0, -5.85, 0.75, 1.8, -2.0, "metal", "dn_shelves")
    o(7.25, 0, 2.6, 7.85, 1.8, 5.0, "metal", "dn_shelves")


def gas_station_furniture(ox, oz):
    """The old gas station (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -14..14,
    z -7..7, one 3 m storey; north = the highway, south = the forecourt). Shop west: the counter and till, two
    shelves, the drinks fridges on the partition, the washroom in the south-west corner. Service bay east: a burnt
    car fallen off the lift, the workbench, tyres, oil drums. Outside: the canopy over the pumps (its east half down
    on the forecourt). The doorways, the room middles and the holes' ways in stay clear."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    # Shop (x -13.85..-0.1).
    o(-11.4, 0, -5.4, -10.7, 1.0, -1.6, "wood", "gs_counter")
    o(-13.85, 1.2, -5.0, -13.6, 2.1, -2.2, "wood", "gs_cig_rack")
    o(-8.4, 0, -1.2, -5.0, 1.4, -0.5, "metal", "gs_shelf")
    o(-8.4, 0, 1.8, -5.0, 1.4, 2.5, "metal", "gs_shelf")
    o(-0.75, 0, -6.85, -0.1, 2.0, -2.6, "metal", "gs_fridges")
    o(-3.4, 0, 6.1, -1.0, 1.2, 6.85, "metal", "gs_oil_rack")
    washroom(ox, oz, -13.85, 4.6, -12.0, 6.85, "EN", ("N", -12.9, 2), fit=(
        ("wc_toilet", "W", 6.2, 0.5, 0.65, 0.8), ("wc_sink", "E", 5.7, 0.5, 0.4, 0.85)))
    # Service bay (x 0.1..13.85).
    o(4.2, 0, -1.5, 9.4, 1.3, 1.5, "rust", "gs_car")   # (the lift's posts stand inside its box)
    o(1.0, 0, -6.85, 4.6, 0.95, -6.1, "wood", "gs_bench")
    o(12.95, 0, -6.6, 13.85, 1.2, -4.6, "metal", "gs_tyres")
    o(0.2, 0, 4.9, 1.4, 1.0, 6.1, "metal", "fuel_drums")
    # Outside: the canopy over the pumps (its east posts blown away, the east half down on the forecourt).
    for x, z in ((-15.5, 9.0), (-15.5, 14.5), (0.5, 14.5)):
        o(x, 0, z, x + 0.5, 4.5, z + 0.5, "metal", "gs_post")
    o(-16.0, 4.5, 8.5, 1.0, 4.9, 15.5, "wall_fuel", "gs_canopy")
    t = math.atan2(4.3, 17.5)
    obox(ox + 9.75, 2.5, oz + 12.0, 7.0, 0.4, math.hypot(17.5, 4.3), 90.0, "wall_fuel", pitch=math.degrees(t),
         kind="gs_canopy_down")
    for x in (-10.0, -2.0, 6.0):
        o(x, 0, 11.2, x + 1.2, 1.6, 12.4, "metal", "gs_pump")


def garage_furniture(ox, oz):
    """The garage (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -7..7, z -7..7, one
    4.5 m storey, no roof left; north = the highway). A burnt pickup east of the middle, nose to the highway, the
    engine hoist by it, an engine block on the floor; the workbench and tool chest on the east wall, tyres and drums
    in the west corners, parts shelving on the south wall, the washroom in the north-east corner."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    o(1.9, 0, -1.0, 4.3, 1.8, 4.6, "metal", "gr_pickup")
    o(1.0, 0, -3.0, 1.8, 2.2, -2.0, "metal", "gr_hoist")
    o(-4.1, 0, -0.9, -3.1, 0.8, 0.1, "metal", "gr_engine")
    o(6.1, 0, -4.1, 6.85, 0.95, -2.0, "wood", "gr_bench")
    o(6.25, 0, 2.2, 6.85, 1.1, 3.2, "metal", "gr_toolchest")
    o(-6.85, 0, -6.6, -6.0, 1.3, -5.0, "metal", "gs_tyres")
    o(-6.6, 0, 5.2, -5.4, 1.0, 6.4, "metal", "fuel_drums")
    o(-5.6, 0, 6.25, -2.0, 2.2, 6.85, "metal", "gr_shelves")
    washroom(ox, oz, 5.0, -6.85, 6.85, -4.6, "WS", ("W", -5.75, 2), fit=(
        ("wc_toilet", "E", -6.1, 0.5, 0.65, 0.8), ("wc_sink", "N", 5.6, 0.5, 0.4, 0.85)))


def junk_office_furniture(ox, oz):
    """The junkyard office (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -5..5,
    z -4..4, one 3 m storey, its roof gone; the door south on the yard). A car's back seat for a sofa and the
    filing cabinets along the north wall (the crate between them), the desk under the west window, a parts shelf
    in the south-east corner, the washroom in the south-west corner."""
    def o(x0, y0, z0, x1, y1, z1, colour, kind, solid=True):
        box(ox + x0, y0, oz + z0, ox + x1, y1, oz + z1, colour, solid=solid, kind=kind)
    o(-4.6, 0, -3.85, -2.6, 0.85, -3.15, "wood", "jo_seat")
    o(2.4, 0, -3.85, 4.2, 1.3, -3.3, "metal", "jo_filing")
    o(-4.85, 0, -1.6, -4.05, 0.76, 0.4, "wood", "jo_desk")
    o(4.25, 0, 1.9, 4.85, 1.8, 3.85, "metal", "gr_shelves")
    washroom(ox, oz, -4.85, 1.7, -3.0, 3.85, "EN", ("N", -3.9, 2), fit=(
        ("wc_toilet", "W", 3.2, 0.5, 0.65, 0.8), ("wc_sink", "S", -4.2, 0.5, 0.4, 0.85)))


def old_house_furniture(n, ox, oz):
    """The old quarter's houses (World art 0.17), in the model's own coordinates (origin map (ox, oz); local x -6..6,
    z -5..5, 3 m storeys; rooms NW, NE, SW, SE split at x 0 and z 0). Bombed and left: a little of each family's
    furniture is still where it stood, clear of the room middles (AI spawns), the doorways and the shell holes.
    The two-storey houses (1, 7) have the stairs along the north wall (foot east, top west) and their south rooms
    upstairs open to the sky; 6 (spawn 5's cover) is whole."""
    def o(x0, y0, z0, x1, y1, z1, kind, colour="wood", solid=True, y=0.0):
        box(ox + x0, y + y0, oz + z0, ox + x1, y + y1, oz + z1, colour, solid=solid, kind=kind)
    up = FLOOR_H
    if n in (1, 7):
        if n == 1:      # (its kitchen's west wall is blown in: the cupboards on the inside wall)
            o(-1.9, 0, -0.7, -0.15, 0.9, -0.1, "kitchen_run")
        else:
            o(-5.85, 0, -2.4, -5.25, 0.9, -0.2, "kitchen_run")
        o(5.4, 0, -4.6, 5.85, 0.5, -3.4, "shoe_bench")
        washroom(ox, oz, 4.15, -1.75, 5.85, -0.1, "WN", ("W", -0.95, 2), fit=(
            ("wc_toilet", "S", 5.3, 0.5, 0.65, 0.8), ("wc_sink", "E", -1.2, 0.5, 0.4, 0.85)))
        o(-5.4, 0, 4.0, -3.4, 0.9, 4.85, "house_sofa")
        o(-4.8, 0, 1.4, -1.4, 0.02, 3.6, "house_rug", solid=False)
        o(-2.9, 0, 4.0, -2.1, 0.95, 4.8, "armchair")
        if n == 1:
            o(4.2, 0, 0.5, 5.7, 0.9, 2.0, "dining_table")
        else:           # (its east wall is blown in)
            o(3.0, 0, 3.7, 4.5, 0.85, 4.85, "kitchen_table")
        o(4.3, 0, -0.95, 5.85, 0.6, -0.1, "house_bed", y=up)      # upstairs, under the roof that's left
    elif n == 6:
        o(-5.85, 0, -4.6, -5.25, 0.9, -0.4, "kitchen_run")
        o(-1.9, 0, -4.6, -0.4, 0.85, -3.5, "kitchen_table")
        o(-5.6, 0, 4.4, -4.4, 0.5, 4.85, "shoe_bench")
        o(-1.9, 0, 0.15, -0.2, 0.9, 1.0, "house_sofa")
        o(-1.2, 0, 3.9, -0.3, 0.95, 4.7, "armchair")
        o(4.0, 0, -4.85, 5.85, 0.6, -3.3, "house_bed")
        o(5.4, 0, 0.6, 5.85, 0.55, 1.8, "tv_stand")
        washroom(ox, oz, 4.2, 3.2, 5.85, 4.85, "WN", ("W", 4.0, 2), fit=(
            ("wc_toilet", "E", 4.2, 0.5, 0.65, 0.8), ("wc_sink", "S", 5.3, 0.5, 0.4, 0.85)))
    elif n == 8:
        o(5.25, 0, -4.6, 5.85, 0.9, -2.0, "kitchen_run")
        washroom(ox, oz, 0.1, -4.85, 1.8, -3.55, "SE", ("E", -4.2, 2), fit=(
            ("wc_toilet", "N", 0.9, 0.5, 0.65, 0.8),))
        o(-5.6, 0, 0.3, -4.8, 0.95, 1.1, "armchair")
        o(-1.9, 0, 0.15, -0.2, 0.6, 1.25, "house_bed")


def build(b, loot_spots=()):
    """loot_spots: (kind, room i, room j, floor, wall side, offset[, look])."""
    footprints.append((b.name, b.x0, b.z0, b.x1, b.z1))
    buildings.append(b)
    b.build()
    b.damage_debris(random.Random(b.name))
    for kind, i, j, floor, side, off, *look in loot_spots:
        x, y, z, yaw = b.against_wall(i, j, floor, side, off)
        add_loot(b.name, kind, x, z, y=y, yaw=yaw, look=look[0] if look else None)
    return b


def shops_frontage():
    """The pavement in front of the shops, out to Old Road (made after the scatter, like the shops' turn)."""
    box(36, 0.0, 112, 44.5, 0.06, 141, "pavement", solid=False)


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
# Buildings moved after the random scatter (trees, poles, clutter) was settled: the scatter keeps clear of where they
# were, so moving one doesn't reshuffle the trees and cover all over the map (z offset back to the old spot).
SCATTER_OLD_Z = {"TownHall": -4.0}
# Ground kept clear round a quarter-turned building (default: its footprint and 3 m round it), map x0, z0, x1, z1.
# The two road houses' old footprints (the motel stands there now): the scatter keeps clear of them as it always has.
MOTEL_GHOSTS = [("RoadHouse1", 214.0, 30.0, 226.0, 40.0), ("RoadHouse2", 218.0, 54.0, 230.0, 64.0)]
SCATTER_CLEAR = {"Shops": (20, 108, 49, 144)}   # (owner, world art: the shops turned to face Old Road, front kept open)   # world art round 5 (owner): the town hall moved 4 m south, away from the square


def scatter_footprints():
    return [(n, x0, z0 + SCATTER_OLD_Z.get(n, 0.0), x1, z1 + SCATTER_OLD_Z.get(n, 0.0)) for n, x0, z0, x1, z1 in footprints]
labels = []       # (text, x, z, big) for the in-raid map (M)
water = []        # (points, width) of water, for the map
woods = []        # (x, z, radius) of tree clusters, for the map
yards = []        # (x0, z0, x1, z1) of yards, fields and paving, for the map
# A dug trench line in the open field south of the town hall (owner, 0.11.8: trench warfare). Axis-aligned
# rectangles (x0, z0, x1, z1) that overlap at the corners; the ground has holes there and the floor is 1.1 m down.
TRENCHES = [(126, 172, 140, 174.4), (137.6, 172, 140, 180), (137.6, 177.6, 158, 180), (155.6, 170, 158, 180),
            (155.6, 170, 176, 172.4)]
TRENCH_DEPTH = 1.1
BUNKER_HOLE = (85.5, 152.0, 94.0, 154.4)   # the ramp down to the bunker, at the town hall's west end
BUNKER = (80.0, 147.0, 132.0, 163.0)       # the bunker under the town hall
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


def strip(points, width, colour, y=0.02, h=0.04, solid=False, people=False):
    """A flat band along a polyline (roads, paths, water). Pieces overlap a little at each bend so there are no
    gaps; every other piece is a millimetre higher so the overlaps don't flicker."""
    for k, ((ax, az), (bx, bz)) in enumerate(zip(points, points[1:])):
        length = math.hypot(bx - ax, bz - az)
        if length < 0.01:
            continue
        yaw = math.degrees(math.atan2(bx - ax, bz - az))
        lift = 0.001 * (k % 2)
        with anchored(("seg", ax, az, bx, bz, width)):
            obox((ax + bx) / 2, y + h / 2 + lift, (az + bz) / 2, width, h, length + width * 0.5, yaw, colour, solid,
                 people=people)


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
# The map's cars (World art 0.17, owner 2026-10-17: "different types throughout the map"): four types, drawn by
# assets/models/props/cars/car_<type>_<paint | burnt>.glb (art_source/scripts/make_building.py cars). Each collides
# as boxes that fit its shape: body (width, height, length) and cabin (width, top, front z, back z; front at -z).
CAR_TYPES = {"a": ((1.7, 0.86, 4.2), (1.6, 1.44, -0.8, 1.0)),       # saloon
             "b": ((1.62, 0.86, 3.7), (1.52, 1.46, -0.5, 1.75)),    # hatchback
             "c": ((1.72, 0.9, 4.5), (1.62, 1.5, -0.9, 2.15)),      # estate
             "d": ((1.9, 2.07, 4.4), None)}                         # minibus
CAR_PAINTS = {"a": ("wine", "sb_cream", "police_navy"), "b": ("teal", "yellow", "wine"),
              "c": ("police_navy", "st_green", "sb_cream"), "d": ("olive", "blue", "teal")}
# Each car's pillars between its windows (z) and its roof (z from, to); the minibus: pillars and the window band's
# height (y from, to). As the models draw them (art_source/scripts/make_building.py car_parts).
CAR_GLASS = {"a": ((-0.75, 0.12, 0.95), (-0.6, 0.85)), "b": ((-0.45, 0.45, 1.68), (-0.35, 1.8)),
             "c": ((-0.85, 0.1, 1.15, 2.1), (-0.7, 2.2)), "d": ((-2.1, -1.2, -0.2, 0.9, 2.0), (1.29, 1.77))}
# The gap under each car (0.20.23, owner: "can you shoot under the car? ... u cant shoot through the parts u can see
# through"): its height, and the wheels (radius, z of the axles) that still stop shots there. As car_parts draws them.
CAR_UNDER = {"a": (0.28, 0.32, (-1.3, 1.3)), "b": (0.28, 0.32, (-1.15, 1.2)), "c": (0.28, 0.32, (-1.4, 1.45)),
             "d": (0.26, 0.34, (-1.25, 1.35))}
cars = []         # {"glb", "anchor", "roll", "under"}: placed by write_scene where its body box ended up


def fit_car_unders():
    """Opens the gap under each drawn car (CAR_UNDER) to shots: its body box (the group's first) splits into the body
    and a people-only box under it, plus its wheels. Done late, like fit_trucks, so the scatter stays as it was."""
    global boxes, anchors
    under = {c["anchor"]: c["under"] for c in cars if c["under"]}
    out_b, out_a = [], []
    for b, a in zip(boxes, anchors):
        if a not in under:
            out_b.append(b)
            out_a.append(a)
            continue
        (kind, sink), w, length = under.pop(a), b[3], b[5]
        yaw = b[6]
        if yaw == 0.0 and w > length:   # (an unturned box turned a quarter: its sides swapped)
            yaw, w, length = 90.0, length, w
        gap, r, axles = CAR_UNDER[kind]
        bottom, top = b[1] - b[4] / 2, b[1] + b[4] / 2
        cut = bottom + sink / 2 + gap - sink   # (the body's bottom is half the sink under the car's ground)
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        parts = [(0.0, 0.0, (cut + top) / 2, w, top - cut, length, b[9]), (0.0, 0.0, (bottom + cut) / 2, w, cut - bottom, length, 4)]
        parts += [(sx * (w / 2 - 0.11), az, bottom + sink / 2 + r - sink / 2, 0.22, 2 * r - sink, 2 * r, b[9])
                  for az in axles for sx in (-1, 1)]
        for px, pz, py, sx_, sy_, sz_, flag in parts:
            out_b.append((b[0] + px * c + pz * s, py, b[2] - px * s + pz * c, sx_, sy_, sz_, yaw) + b[7:9] + (flag,) + b[10:])
            out_a.append(a)
    boxes, anchors = out_b, out_a


def car_glb(name):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "props", "cars", name + ".glb")


def car(x, z, yaw, colour="car_a", roll=0.0):
    """A car (cover). Its type and paint come from where it stands (so the map has a mix); colour "rust" = burnt out.
    roll 90: on its side."""
    pick = random.Random(f"car {x:.1f} {z:.1f}")
    kind = pick.choice("abcd")
    paint = pick.choice(CAR_PAINTS[kind])
    glb = f"car_{kind}_{'burnt' if colour == 'rust' else paint}"
    shown = os.path.exists(car_glb(glb))
    (w, h, length), cab = CAR_TYPES[kind]
    sink = 0.12 if colour == "rust" else 0.0
    # (0.19.9, owner: shots through car windows too) A drawn car's window band only stops people (flag 4: BoxMap
    # `bar_boxes`); shots hit the body, the roof and the pillars between the windows (the model's, CAR_GLASS).
    windows = shown and not roll
    parts = [(0.0, h / 2 - sink, 0.0, w, h - sink, length, 2)]
    if cab:
        cw, top, z0, z1 = cab
        parts.append((0.0, (h + top) / 2 - sink, (z0 + z1) / 2, cw, top - h, z1 - z0, 4 if windows else 2))
        if windows:
            pillars, (r0, r1) = CAR_GLASS[kind]
            parts.append((0.0, top - 0.04 - sink, (r0 + r1) / 2, cw, 0.08, r1 - r0, 2))
            parts += [(0.0, (h + top) / 2 - sink, pz, cw, top - h, 0.09, 2) for pz in pillars]
    elif windows:   # (the minibus: its windows run round the body)
        pillars, (y0, y1) = CAR_GLASS[kind]
        parts = [(0.0, y0 / 2 - sink, 0.0, w, y0 - sink, length, 2), (0.0, (y0 + y1) / 2 - sink, 0.0, w, y1 - y0, length, 4),
                 (0.0, (y1 + h) / 2 - sink, 0.0, w, h - y1, length, 2)]
        parts += [(0.0, (y0 + y1) / 2 - sink, pz, w, y1 - y0, 0.14, 2) for pz in pillars]
    with group():
        cars.append({"glb": glb, "anchor": _anchor[-1], "roll": roll, "at": (x, z), "under": (kind, sink) if windows else None})
        for px, py, pz, sx, sy, sz, flag in parts:
            if roll:     # (on its side, the car's left down: its height runs along -x; the body's middle at x, z)
                px, py, sx, sy = (h - sink) / 2 - py, w / 2 + px, sy, sx
            c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            obox(x + px * c + pz * s, py, z - px * s + pz * c, sx, sy, sz, yaw, colour)
            if shown:    # drawn by the model: collide only (BoxMap: 2; 4 = people only)
                boxes[-1] = boxes[-1][:9] + (flag,)


@debris_kind("dumpster")
def dumpster(x, z, yaw=0.0):
    obox(x, 0.7, z, 2.0, 1.4, 1.2, yaw, "metal")


@debris_kind("barrier")
def barrier(x, z, yaw):
    obox(x, 0.45, z, 0.6, 0.9, 3.0, yaw, "concrete")


@debris_kind("planter")
def planter(x, z):
    box(x - 1.5, 0, z - 1.0, x + 1.5, 1.0, z + 1.0, "concrete")


@debris_kind("plaza")
def plaza(x, z, w, d):
    """The town square's paving (w x d m round x, z)."""
    box(x - w / 2, 0.0, z - d / 2, x + w / 2, 0.06, z + d / 2, "pavement", solid=False)


@debris_kind("fountain")
def fountain(x, z):
    box(x - 3, 0, z - 3, x + 3, 0.8, z + 3, "concrete")                 # basin
    box(x - 0.6, 0.8, z - 0.6, x + 0.6, 2.6, z + 0.6, "concrete")       # column


@debris_kind("statue")
def statue(x, z):
    box(x - 1.5, 0, z - 1.5, x + 1.5, 1.2, z + 1.5, "concrete")         # plinth
    box(x - 0.5, 1.2, z - 0.5, x + 0.5, 4.0, z + 0.5, "metal")          # the statue


@debris_kind("kiosk")
def kiosk(x, z, yaw=0.0):
    """A newsstand kiosk, 2.5 m square (its hatch faces +z at yaw 0)."""
    obox(x, 1.3, z, 2.5, 2.6, 2.5, yaw, "car_b")


@debris_kind("stall")
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


# The cabins' footprints (x0, z0, x1, z1, 1 m of slack): no tree grows in one (0.15.18, owner: a tree inside a cabin).
CABINS = [(90, 288), (36, 304), (306, 166)]
NO_TREES = [(x - 1, z - 1, x + 14, z + 11) for x, z in CABINS]


def in_creek(x, z, margin=0.0):
    """True if (x, z) is in the creek or on its banks (World art 0.17, owner 2026-10-18: no trees in the water)."""
    return any(_nearest_on(pts, x, z)[0] < CREEK_BANK + margin for pts, _ in water)


@debris_kind("tree", keep=True)
def tree(x, z, rng):
    """A tree (drawn by scripts/trees.gd, outdoor step 7: its kind comes from where it grows, `tree_kind`): the trunk
    collides, the leaves box only hides you from the AI."""
    if any(x0 < x < x1 and z0 < z < z1 for x0, z0, x1, z1 in NO_TREES) or in_creek(x, z):
        rng.uniform(5.0, 7.5); rng.uniform(3.0, 4.6)   # (keep the rest of the woods where it was)
        return
    trunks.append((x, z))
    h = rng.uniform(5.0, 7.5)
    with group():
        box(x - 0.35, 0, z - 0.35, x + 0.35, h, z + 0.35, "trunk")
        s = rng.uniform(3.0, 4.6)
        box(x - s / 2, h - 1.0, z - s / 2, x + s / 2, h + s * 0.7, z + s / 2, "leaves", solid=False)


@debris_kind("bush")
def bush(x, z, rng):
    s = rng.uniform(1.4, 2.2)
    box(x - s / 2, 0, z - s / 2, x + s / 2, rng.uniform(1.0, 1.5), z + s / 2, "bush", solid=False)


# Bush sizes for bush_pass (owner 2026-10-18: "some solid some not, like different sizes ... almost like more
# foliage"): (weight, width range, height range, solid until 0.18.3: now every bush is walk-through and hides you
# from the AI, owner "make them all walk throughable").
BUSH_SIZES = [(5, (0.8, 1.5), (0.6, 1.0), False),     # shrubs
              (3, (1.3, 2.1), (1.0, 1.4), False),     # bushes you can push through
              (2, (1.4, 2.2), (1.0, 1.5), True),
              (3, (2.0, 3.2), (1.5, 2.2), True)]      # big ones: cover


@debris_kind("bush")
def big_bush(x, z, rng, size=None):
    _, (w0, w1), (h0, h1), solid = size or BUSH_SIZES[-1]
    sx, sz, h = rng.uniform(w0, w1), rng.uniform(w0, w1), rng.uniform(h0, h1)
    obox(x, h / 2, z, sx, h, sz, rng.uniform(0, 180), "bush", solid=False)   # (0.18.3, owner: all walk-through)


# Street lamps (World art 0.17, outdoor step 3): along the town's roads, both sides in turn, the pole by the kerb and
# the lamp over the road. Some are knocked down (lying in the verge: no collision) or bent. Drawn by the outdoor kit
# (make_outdoor.py draw_lamp); their look is LAMP_LOOK (or a mix).
LAMP_LOOK = os.environ.get("BLOXOV_LAMP_LOOK", "c")   # (owner 2026-10-18 picked C: old iron lanterns)
TOWN = (0.0, 0.0, 205.0, 200.0)     # map x0, z0, x1, z1 the lamps stay in


@debris_kind("lamp")
def lamp(x, z, yaw, down=False):
    """A street lamp at (x, z); yaw turns its arm (local +z) out over the road."""
    if down:   # knocked over, lying away from the road
        c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        obox(x - s_ * 3.0, 0.12, z - c * 3.0, 0.24, 0.24, 6.0, yaw, "metal", solid=False)
    else:
        obox(x, 3.0, z, 0.24, 6.0, 0.24, yaw, "metal")


def lamp_pass(every=24.0):
    if LAMP_LOOK == "none":   # (for the options sheets: the roads as they were)
        return
    _fp_index["upto"], _fp_index["grid"] = 0, {}
    rng = random.Random(7300)
    x0, z0, x1, z1 = TOWN
    for curve, width in roads[:4] + roads[4:6]:
        side, dist, next_at = 1, 0.0, every / 2
        for (ax, az), (bx, bz) in zip(curve, curve[1:]):
            seg = math.hypot(bx - ax, bz - az)
            while seg > 0 and next_at <= dist + seg:
                t = (next_at - dist) / seg
                tx, tz = (bx - ax) / seg, (bz - az) / seg
                px = ax + (bx - ax) * t - tz * side * (width / 2 + 1.0)
                pz = az + (bz - az) * t + tx * side * (width / 2 + 1.0)
                next_at += every
                side = -side
                if not (x0 < px < x1 and z0 < pz < z1):
                    continue
                if any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 0.6 for pts, w in roads for a, b in zip(pts, pts[1:])):
                    continue   # (at a junction)
                if any(b[4] <= 0.06 and max(b[3], b[5]) > 8 and abs(px - (b[0] + M / 2)) < b[3] / 2 + 2.5 and
                       abs(pz - (b[2] + M / 2)) < b[5] / 2 + 2.5 for b in boxes if b[8] == C["lot"]):
                    continue   # (in a car park's way in)
                yaw = math.degrees(math.atan2(ax + (bx - ax) * t - px, az + (bz - az) * t - pz))   # arm toward the middle
                with scatter_piece(px, pz):
                    lamp(px, pz, yaw, down=rng.random() < 0.12)
            dist += seg


# Road signs (World art 0.17, outdoor round 3): the town's name where roads come in (its crossed-out name on the back,
# for leaving), stop signs where side roads meet a bigger one, speed limits, and finger boards at the big junctions.
# Drawn by the outdoor kit (make_outdoor.py draw_sign) in SIGN_LOOK ("none": no signs, for the options sheet).
SIGN_LOOK = os.environ.get("BLOXOV_SIGN_LOOK", "c")   # (owner 2026-10-18 picked C for paths, poles and signs)
SIGN_KINDS = ("sign_town", "sign_stop", "sign_speed", "sign_dir", "sign_bus", "sign_rail")


def _sign(kind, x, z, yaw, extra=0):
    """A sign post at (x, z), the sign facing yaw (local +z points at the traffic it's for). `extra`: the sign's
    variant (speed: 0 = 50 in town, 1 = 80 out of town; finger board: which junction)."""
    @debris_kind(kind)
    def put(x, z):
        if kind == "sign_town":   # (on two posts; the first box is the board's middle, a hidden marker)
            c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            obox(x, 0.005, z, 0.01, 0.01, 0.01, yaw, "metal", solid=False)
            for d in (-0.7, 0.7):
                obox(x + c * d, 1.4, z - s_ * d, 0.1, 2.8, 0.1, yaw, "metal")
            return
        obox(x, 1.3, z, 0.1, 2.6, 0.1, yaw, "metal")
        for k in range(extra):   # (the variant, as tiny hidden markers: the drawing counts them)
            obox(x, 0.005, z, 0.01, 0.01, 0.01, yaw, "metal", solid=False)
    with scatter_piece(x, z):
        put(x, z)


def _road_point(curve, dist):
    """The point `dist` m along a polyline and its direction."""
    for (ax, az), (bx, bz) in zip(curve, curve[1:]):
        ln = math.hypot(bx - ax, bz - az)
        if dist <= ln or (bx, bz) == curve[-1]:
            t = min(dist / ln, 1.0) if ln else 0.0
            return ax + (bx - ax) * t, az + (bz - az) * t, (bx - ax) / ln, (bz - az) / ln
        dist -= ln


def _road_len(curve):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(curve, curve[1:]))


def _sign_at(curve, width, dist, toward, kind, extra=0, off=1.3):
    """A sign beside a road `dist` m along it, on the right of traffic going `toward` (+1 along the curve, -1 back),
    facing that traffic."""
    x, z, tx, tz = _road_point(curve, dist)
    tx, tz = tx * toward, tz * toward
    px, pz = x - tz * (width / 2 + off), z + tx * (width / 2 + off)   # (right of travel: Godot yaw, x east, z south)
    if any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 0.5 for pts, w in roads for a, b in zip(pts, pts[1:])):
        return
    if any(x0 - 1 < px < x1 + 1 and z0 - 1 < pz < z1 + 1 for _, x0, z0, x1, z1 in footprints):
        return
    _sign(kind, px, pz, math.degrees(math.atan2(-tx, -tz)), extra)


DIR_NAMES = {2: "HILLSIDE", 3: "CHURCH", 5: "STATION", 6: "JUNKYARD", 7: "WOODS"}   # (road index: where it goes)
BUS_STOPS = ((95.0, 104.5, 0.0), (47.0, 128.0, -90.0))   # map x, z, yaw (0: open to the north) of the town's stops


def sign_pass():
    if SIGN_LOOK == "none":
        return
    _fp_index["upto"], _fp_index["grid"] = 0, {}
    x0, z0, x1, z1 = TOWN
    for i, (curve, width) in enumerate(roads):
        total = _road_len(curve)
        # where a big road crosses the town's edge (not the map's): the town sign facing in-coming traffic
        prev = None
        d = 0.0
        while d <= total and width >= 8:
            x, z, _, _ = _road_point(curve, d)
            inside = x0 < x < x1 and z0 < z < z1
            if prev is not None and inside != prev and 3 < x < M - 3 and 3 < z < M - 3:
                into = 1 if inside else -1   # (travelling along the curve goes into town)
                _sign_at(curve, width, d - into * 3.0, into, "sign_town")
                _sign_at(curve, width, d + into * 12.0, into, "sign_speed", 0)        # 50 in town
                _sign_at(curve, width, d - into * 12.0, -into, "sign_speed", 1)       # 80 leaving it
            prev = inside
            d += 1.0
        # where it ends on another road (not where one road carries on as the next): a stop sign, and a finger
        # board naming where it goes on the far corner
        for end, toward in ((curve[0], -1), (curve[-1], 1)):
            on = [(k, w) for k, (pts, w) in enumerate(roads) if k != i and _nearest_on(pts, *end)[0] < w / 2 + 1.0]
            if not on or any(math.hypot(end[0] - p[0], end[1] - p[1]) < 1.0 for k, _ in on
                             for p in (roads[k][0][0], roads[k][0][-1])):
                continue
            main = on[0][1]
            dist = (main / 2 + 2.5) if toward == -1 else total - (main / 2 + 2.5)
            _sign_at(curve, width, dist, toward, "sign_stop", off=0.9)
            if i in DIR_NAMES:
                x, z, tx, tz = _road_point(curve, dist)
                tx, tz = tx * toward, tz * toward   # (toward the junction)
                px, pz = x + tz * (width / 2 + 1.2), z - tx * (width / 2 + 1.2)   # (the left of that traffic)
                with scatter_piece(px, pz):
                    _finger(px, pz, math.degrees(math.atan2(-tx, -tz)), sorted(DIR_NAMES).index(i))
    for x, z, yaw in BUS_STOPS:
        with scatter_piece(x, z):
            bus_shelter(x, z, yaw)
    for curve, width in roads:   # level crossings (outdoor step 5): a crossbuck each side of the rails, facing the traffic
        total, d, prev = _road_len(curve), 0.0, None
        while d <= total:
            x, z, _, _ = _road_point(curve, d)
            if prev is not None and (prev < RAIL_Z) != (z < RAIL_Z):
                _sign_at(curve, width, d - 5.5, 1, "sign_rail", off=1.0)
                _sign_at(curve, width, d + 5.5, -1, "sign_rail", off=1.0)
            prev = z
            d += 0.5


@debris_kind("sign_dir")
def _finger(x, z, yaw, which):
    """A finger board on a post: local +z (yaw) points away from the junction, up the road it names."""
    obox(x, 1.3, z, 0.1, 2.6, 0.1, yaw, "metal")
    for k in range(which):
        obox(x, 0.005, z, 0.01, 0.01, 0.01, yaw, "metal", solid=False)


def _bush_spot(x, z):
    """Grass a bush can stand on: off roads, the rail, water, yards, doorsteps, spawns, extracts and loot (closer in
    than `_clear_of_map`: bushes grow along yards and round houses; the scatter's overlap check does the rest)."""
    if not (6 < x < M - 6 and 6 < z < M - 6) or abs(z - RAIL_Z) < 6:
        return False
    if any(t[0] - 4 < x < t[2] + 4 and t[1] - 4 < z < t[3] + 4 for t in TRENCHES):
        return False
    for points, width in roads + water + paths:
        for a, b in zip(points, points[1:]):
            if _seg_rect_gap(a, b, (x - 0.1, z - 0.1, x + 0.1, z + 0.1)) < width / 2 + 3.5:
                return False
    for x0, z0, x1, z1 in yards + camp_rects:
        if x0 - 2 < x < x1 + 2 and z0 - 2 < z < z1 + 2:
            return False
    for name, x0, z0, x1, z1 in scatter_footprints() + areas:
        if x0 - 4 < x < x1 + 4 and z0 - 4 < z < z1 + 4:
            return False
    if any(math.hypot(x - sx, z - sz) < 6 for _, sx, sz in player_spawns + enemy_spawns):
        return False
    for b in boxes:   # flat paving (the town square, car parks, the sports field...)
        if b[4] <= 0.06 and max(b[3], b[5]) > 8 and abs(x - (b[0] + M / 2)) < b[3] / 2 + 1.5 and abs(z - (b[2] + M / 2)) < b[5] / 2 + 1.5:
            return False
    if any(math.hypot(x - ex, z - ez) < 10 for _, _, ex, ez in extracts):
        return False
    if any(x0 - 4 < x < x1 + 4 and z0 - 4 < z < z1 + 4 for x0, z0, x1, z1 in NO_TREES):   # (the cabins)
        return False
    return not any(math.hypot(x - l[2], z - l[4]) < 6 for l in loot)


def bush_pass(spacing=8.0, tries=4000):
    """Bushes and shrubs on open grass (World art 0.17, outdoor step 2, owner 2026-10-18: "add some big bushes", then
    "some solid some not, like different sizes"): clumps of one to four of mixed sizes (BUSH_SIZES)."""
    _fp_index["upto"], _fp_index["grid"] = 0, {}   # (boxes were taken out since the scatter: index them afresh)
    rng = random.Random(5150)
    sizes = [b for b in BUSH_SIZES for _ in range(b[0])]
    placed = []
    for _ in range(tries):
        x, z = rng.uniform(0, M), rng.uniform(0, M)
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in placed) or not _bush_spot(x, z):
            continue
        placed.append((x, z))
    for x, z in placed:
        for k in range(rng.choice((1, 2, 2, 3, 4))):
            a, d = rng.uniform(0, 2 * math.pi), 0.0 if k == 0 else rng.uniform(1.8, 3.4)
            bx, bz, size = x + math.cos(a) * d, z + math.sin(a) * d, rng.choice(sizes)
            if k and not _bush_spot(bx, bz):   # (each bush of a clump keeps off doors and loot too)
                continue
            with scatter_piece(x, z):
                big_bush(bx, bz, rng, size)
    return placed


def car_stack(x, z, yaw, n, rng, kind=None):
    """Wrecked cars stacked n high (junkyard walls)."""
    with group():
        for k in range(n):
            obox(x, 0.55 + k * 1.1, z, 1.9, 1.1, 4.2, yaw + rng.uniform(-6, 6), ("car_a", "car_b", "rust")[rng.randrange(3)],
                 kind=kind)


# An army truck's boxes, as art_source/scripts/make_outdoor.py draw_truck draws it (0.20.20, owner: "you can walk
# inside the hood in the green military trucks ... needs to have a proper hitbox"): (z along the truck from its middle,
# width, height, length). The bed (and the gap behind the cab), the cab, the bonnet. The bed is the longest: the model
# is drawn from it (TRUCK_BED_Z back from the truck's middle). Until fit_trucks the trucks keep their old two boxes,
# so the scatter round them (what's dropped for overlapping) stays as it was.
TRUCK_BED_Z = -0.1
TRUCK_PARTS = ((TRUCK_BED_Z, 2.5, 3.0, 6.6), (4.1, 2.4, 2.3, 1.8), (5.3, 2.2, 1.4, 0.6))


def truck_boxes(x, z, yaw, old, colours):
    """`old`: the old (body height, body length, cab offset, cab height) the scatter still sees."""
    bh, bl, fo, fh = old
    with group():
        obox(x, bh / 2, z, 2.5, bh, bl, yaw, colours[0])
        obox(x + fo * math.sin(math.radians(yaw)), fh / 2, z + fo * math.cos(math.radians(yaw)), 2.4, fh, 1.8, yaw, colours[1])
    if len(boxes[-1]) > 10 and debris[boxes[-1][10]]["kind"] == "truck":
        debris[boxes[-1][10]]["truck"] = colours


def fit_trucks():
    """Swaps the trucks' old boxes (the body, round the truck's middle, and the cab) for ones that fit the model."""
    global boxes, anchors
    out_b, out_a = [], []
    for b, a in zip(boxes, anchors):
        colours = debris[b[10]].get("truck") if len(b) > 10 else None
        if colours is None:
            out_b.append(b)
            out_a.append(a)
        elif b[5] > 2.0:   # (the body; the cab box just goes)
            sy, cy = math.sin(math.radians(b[6])), math.cos(math.radians(b[6]))
            for (pz, w, h, length), colour in zip(TRUCK_PARTS, colours):
                out_b.append((b[0] + pz * sy, h / 2, b[2] + pz * cy, w, h, length, b[6], 0.0, C[colour]) + b[9:])
                out_a.append(a)
    boxes, anchors = out_b, out_a


@debris_kind("truck")
def truck(x, z, yaw):
    """An army truck (checkpoint)."""
    truck_boxes(x, z, yaw, (2.8, 7.0, 4.3, 2.2), ("army", "army", "army"))


@debris_kind("sandbags")
def sandbags(x, z, yaw, length=4.0):
    obox(x, 0.55, z, 0.7, 1.1, length, yaw, "sandbag")


# Extract camps (World art 0.17, owner 2026-10-18: "make the extracts nicer", picked the radio mast plus "little
# areas where the extracts are", a mix of designs): beside each extract's square (which stays clear) a tent camp, a
# checkpoint post or a dug-in outpost under a camo net. The radio mast and the square are scenes/extract_zone.tscn.
@debris_kind("tent")
def tent(x, z, yaw):
    """An army tent (its length along yaw; the open end faces yaw + 180)."""
    obox(x, 0.8, z, 2.6, 1.6, 3.4, yaw, "army")


@debris_kind("hut")
def guard_hut(x, z, yaw):
    """A checkpoint's guard hut (its door faces yaw)."""
    obox(x, 1.25, z, 2.0, 2.5, 2.0, yaw, "army")


@debris_kind("crates")
def ammo_crates(x, z, yaw):
    """A stack of army crates."""
    with group():
        obox(x, 0.35, z, 1.1, 0.7, 0.8, yaw, "army")
        obox(x + 0.1, 0.92, z, 0.8, 0.45, 0.6, yaw + 12, "army")


@debris_kind("net")
def camo_net(x, z, yaw, w=4.4, d=4.0):
    """A camo net on four poles (w across yaw, d along it), 2.2 m up: walk under it."""
    with group():
        c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        for lx, lz in ((-w / 2, -d / 2), (w / 2, -d / 2), (-w / 2, d / 2), (w / 2, d / 2)):
            obox(x + c * lx + s_ * lz, 1.1, z - s_ * lx + c * lz, 0.12, 2.2, 0.12, yaw, "wood")
        obox(x, 2.2, z, w, 0.05, d, yaw, "army", solid=False)


CAMP_KINDS = ("tent", "hut", "net", "crates")
CAMPS = {"TownRoad": "checkpoint", "Highway": "checkpoint", "FarmRoad": "outpost", "MillLane": "tents",
         "CreekTrail": "tents", "SouthRoad": "outpost"}
CAMP_FLIP = {"Highway"}   # (the camps on the side away from the middle: the junkyard's fence is on the other)
camp_rects = []   # (map x0, z0, x1, z1) round each camp: gravel underfoot (write_splat)


def extract_camps():
    for name, _, ex, ez in extracts:
        style = CAMPS.get(name)
        if style is None:
            continue
        near = min(((_nearest_on(pts, ex, ez), pts, w) for pts, w in roads), key=lambda r: r[0][0])
        (dist, (px, pz)), pts, width = near
        if dist < 8.0:   # along the road's last stretch
            k = min(range(len(pts) - 1), key=lambda i: _seg_rect_gap(pts[i], pts[i + 1], (ex, ez, ex, ez)))
            ux, uz = pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]
        else:            # (no road: square to the way in from the map's edge)
            ux, uz = M / 2 - ex, M / 2 - ez
            ux, uz = -uz, ux
            width = 4.0
        ul = math.hypot(ux, uz)
        ux, uz = ux / ul, uz / ul
        vx, vz = -uz, ux
        if (vx * (M / 2 - ex) + vz * (M / 2 - ez) < 0) != (name in CAMP_FLIP):   # (toward the map's middle)
            vx, vz = -vx, -vz
        off = (ex - px) * vx + (ez - pz) * vz if dist < 8.0 else 0.0   # (the extract's own offset off the road)
        v0 = max(3.2, width / 2 + 1.2 - off)

        def at(u, v):
            return ex + ux * u + vx * v, ez + uz * u + vz * v
        yu = math.degrees(math.atan2(ux, uz))   # a box's length along the road
        yv = math.degrees(math.atan2(vx, vz))   # and across it
        pieces = []
        if style == "tents":
            pieces = [(tent, 0.0, v0 + 2.4, yv), (tent, 3.6, v0 + 2.6, yv + 6), (ammo_crates, -3.0, v0 + 2.2, yu),
                      (sandbags, -1.6, v0 + 4.8, yu, 3.0)]
        elif style == "checkpoint":
            pieces = [(guard_hut, -2.4, v0 + 1.4, yv + 180), (sandbags, 2.2, v0 + 0.4, yu, 3.2),
                      (sandbags, 4.0, v0 + 2.0, yv, 2.4), (ammo_crates, -2.4, v0 + 3.6, yu + 20)]
        else:
            pieces = [(camo_net, 0.0, v0 + 2.6, yu), (ammo_crates, -1.0, v0 + 2.3, yu), (ammo_crates, 1.2, v0 + 3.2, yu + 30),
                      (sandbags, 0.0, v0 + 5.4, yu + 90, 5.0), (sandbags, -3.0, v0 + 2.8, yu, 3.0)]
        xs, zs = zip(*[at(p[1], p[2]) for p in pieces])
        rect = (min(xs) - 4, min(zs) - 4, max(xs) + 4, max(zs) + 4)
        clear_scatter(rect)
        camp_rects.append(rect)
        for fn, u, v, yaw, *rest in pieces:
            fn(*at(u, v), yaw, *rest)


# ---------------------------------------------------------------------------------------------- clutter (0.11.4)
# War-torn junk in the empty grass (owner, 0.11.4): rocks, rubble, wrecks, tank traps, craters. Gray boxes for
# now; real models come later. Placed by `clutter()` in the dead areas only, away from buildings, roads and spawns.
@debris_kind("rocks")
def rock(x, z, rng):
    for _ in range(rng.randint(1, 3)):
        w, h, d = rng.uniform(1.4, 3.6), rng.uniform(0.8, 2.4), rng.uniform(1.4, 3.2)
        obox(x + rng.uniform(-1.5, 1.5), h / 2 - 0.1, z + rng.uniform(-1.2, 1.2), w, h, d, rng.uniform(0, 90), "stone")


@debris_kind("rubble")
def rubble(x, z, rng):
    """A pile of broken concrete round a stub of wall."""
    for _ in range(rng.randint(4, 7)):
        w, h, d = rng.uniform(0.6, 1.8), rng.uniform(0.3, 0.9), rng.uniform(0.6, 1.8)
        obox(x + rng.uniform(-2.5, 2.5), h / 2, z + rng.uniform(-2.5, 2.5), w, h, d, rng.uniform(0, 90),
             rng.choice(("concrete", "concrete", "wall", "slab")))
    # (a stub of wall, waist high: owner 2026-10-18, no more lone walls standing up)
    h = 1.0 + (x * 7.3 + z * 3.1) % 0.4
    obox(x + rng.uniform(-1, 1), h / 2, z + rng.uniform(-1, 1), rng.uniform(2.5, 4.0), h, 0.3, rng.uniform(0, 180), "wall")


def wreck(x, z, rng):
    """A burnt-out car, sometimes on its side."""
    yaw = rng.uniform(0, 180)
    if rng.random() < 0.3:
        car(x, z, yaw, "rust", roll=90.0)
    else:
        rng.uniform(-4, 4)   # (keeps the rest of the scatter where it was)
        car(x, z, yaw, "rust")


@debris_kind("truck")
def wrecked_truck(x, z, rng):
    yaw = rng.uniform(0, 180)
    rng.uniform(-10, 10), rng.uniform(-8, 0)   # (the cab's old twist and tilt, which the model never drew: kept so the scatter after it stays put)
    truck_boxes(x, z, yaw, (2.6, 6.5, 4.0, 1.8), ("rust", "army", "army"))


@debris_kind("tanktrap")
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


@debris_kind("crater")
def crater(x, z, rng):
    """A shell crater: a ring of dirt mounds round a hole in the ground (you can crouch in it)."""
    r = rng.uniform(2.5, 3.5)
    craters.append((x, z, r))
    for k in range(8):
        a = k * 45 + rng.uniform(-10, 10)
        obox(x + r * math.sin(math.radians(a)), 0.3, z + r * math.cos(math.radians(a)), 2.4, 0.6, 1.0, a + 90, "dirt")


@debris_kind("drums")
def barrels(x, z, rng):
    for _ in range(rng.randint(2, 4)):
        obox(x + rng.uniform(-1.5, 1.5), 0.5, z + rng.uniform(-1.5, 1.5), 0.6, 1.0, 0.6, rng.uniform(0, 90),
             rng.choice(("rust", "army", "metal")))
    if rng.random() < 0.5:
        obox(x + 2.0, 0.3, z, 0.6, 0.6, 1.0, 90, "rust", pitch=90.0)   # one knocked over


CLUTTER = [(rock, 5), (rubble, 3), (wreck, 3), (wrecked_truck, 1), (tank_traps, 2), (crater, 2), (barrels, 2)]


# Sightline breakers (World art 0.17, owner: "you can spawn, go on a hill and kill a bunch of AI"): taller cover,
# added by `cover_pass()` between the old clutter. Check with tools/sightlines.gd.
def _near_buildings(x, z, reach=45.0):
    return any(x0 - reach < x < x1 + reach and z0 - reach < z < z1 + reach for _, x0, z0, x1, z1 in footprints)


def broken_cover(x, z, rng, yaw=None):
    """Tall cover where a lone ruined wall stood (owner 2026-10-18: too many walls standing up on their own, "it makes
    no sense"): near the town a shelled house's remains, out in the country a rock outcrop."""
    (ruin if _near_buildings(x, z, 22.0) else outcrop)(x, z, rng, yaw)


@debris_kind("ruin")
def ruin(x, z, rng, yaw=None):
    """What's left of a small shelled house: its floor slab, a corner still standing (full cover, the long side along
    yaw), stubs of the other walls with a gap for the door, heaps of fallen wall inside, sometimes the chimney."""
    yaw = rng.uniform(0, 180) if yaw is None else yaw
    L, D = rng.uniform(6.0, 7.5), rng.uniform(4.6, 5.6)
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

    def put(u, v, h, su, sv, colour="wall", solid=True, y0=0.0):
        obox(x + u * c + v * s_, y0 + h / 2, z - u * s_ + v * c, su, h, sv, yaw, colour, solid=solid)
    put(0, 0, 0.2, L, D, "concrete", solid=False)               # the floor slab
    side = rng.choice((-1, 1))                                   # which end the standing corner is at
    back = rng.uniform(0.55, 0.85) * L                           # the back wall, still standing from the corner
    put(side * (L - back) / 2, -D / 2 + 0.2, rng.uniform(2.4, 3.0), back, 0.4)
    ret = rng.uniform(0.4, 0.75) * D                             # its return along the end wall
    put(side * (L / 2 - 0.2), -D / 2 + 0.4 + ret / 2, rng.uniform(2.1, 2.7), 0.4, ret)
    if back < L - 0.6:                                           # the rest of the back wall: a stub
        put(-side * back / 2, -D / 2 + 0.2, rng.uniform(0.4, 0.9), L - back - 0.3, 0.4)
    if ret < D - 1.0:
        put(side * (L / 2 - 0.2), D / 2 - (D - ret - 0.8) / 2 - 0.2, rng.uniform(0.3, 0.8), 0.4, D - ret - 0.8)
    door = rng.uniform(-L / 4, L / 4)                            # the front: stubs either side of the doorway
    for u0, u1 in ((-L / 2, door - 0.6), (door + 0.6, L / 2)):
        if u1 - u0 > 0.5:
            put((u0 + u1) / 2, D / 2 - 0.2, rng.uniform(0.35, 1.0), u1 - u0, 0.4)
    put(-side * (L / 2 - 0.2), 0.2, rng.uniform(0.3, 0.7), 0.4, D - 1.4)   # the far end wall, knocked down
    for _ in range(rng.randint(2, 4)):                           # heaps of fallen wall inside
        w, h = rng.uniform(1.0, 2.0), rng.uniform(0.35, 0.8)
        u, v = rng.uniform(-L / 2 + 1.2, L / 2 - 1.2), rng.uniform(-D / 2 + 1.1, D / 2 - 1.1)
        obox(x + u * c + v * s_, h / 2, z - u * s_ + v * c, w, h, rng.uniform(0.8, 1.6), yaw + rng.uniform(-30, 30), "concrete")
    if rng.random() < 0.35:                                      # the chimney stack, still up
        put(side * (L / 2 - 1.4), -D / 2 + 0.55, rng.uniform(3.4, 4.2), 0.9, 0.7)


@debris_kind("rocks")
def outcrop(x, z, rng, yaw=None):
    """Two or three big boulders in a row along yaw: head-high cover out in the country."""
    yaw = rng.uniform(0, 180) if yaw is None else yaw
    n = rng.randint(2, 3)
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    u = -(n - 1) * 1.1
    for k in range(n):
        w, h, d = rng.uniform(2.2, 3.0), rng.uniform(1.9, 2.6) if k != n // 2 or n == 2 else rng.uniform(2.3, 2.8), rng.uniform(1.8, 2.6)
        v = rng.uniform(-0.4, 0.4)
        obox(x + u * c + v * s_, h / 2 - 0.1, z - u * s_ + v * c, w, h, d, yaw + rng.uniform(-25, 25), "stone")
        u += 2.2


@debris_kind("container")
def container(x, z, rng, yaw=None):
    """A dumped shipping container (now and then two, one on top)."""
    yaw = rng.uniform(0, 180) if yaw is None else yaw
    col = rng.choice(("rust", "army", "car_b", "boxcar"))
    with group():
        obox(x, 1.3, z, 2.4, 2.6, 6.1, yaw, col)
        if rng.random() < 0.25:
            obox(x + rng.uniform(-0.3, 0.3), 3.9, z + rng.uniform(-0.3, 0.3), 2.4, 2.6, 6.1, yaw + rng.uniform(-8, 8),
                 rng.choice(("rust", "army", "car_b")))


@debris_kind("berm")
def berm(x, z, rng, yaw=None):
    """A bulldozed earth bank, head high."""
    yaw = rng.uniform(0, 180) if yaw is None else yaw
    length = rng.uniform(7.0, 11.0)
    for k in (-1, 0, 1):
        off = k * length / 3
        h = rng.uniform(1.7, 2.1) if k == 0 else rng.uniform(1.2, 1.6)
        obox(x + off * math.cos(math.radians(yaw)), h / 2 - 0.1, z - off * math.sin(math.radians(yaw)), length / 2.4,
             h, 2.6, yaw + rng.uniform(-6, 6), "dirt")


COVER = [(broken_cover, 5), (container, 2), (berm, 3), (rock, 3), (wrecked_truck, 2), (rubble, 2), (wreck, 2)]


def _clear_of_map(x, z):
    """True if (x, z) is open grass: off roads, rail, water, yards and away from buildings, props and spawns."""
    if not (8 < x < M - 8 and 8 < z < M - 8) or abs(z - 210.0) < 8:   # the railway
        return False
    if any(t[0] - 6 < x < t[2] + 6 and t[1] - 6 < z < t[3] + 6 for t in TRENCHES):
        return False
    if any(sx - 6 < x < sx + 6 and sz - 6 < z < sz + 13 for sx, sz in stand_spots):   # (the stands' ramps)
        return False
    for points, width in roads + water:
        for a, b in zip(points, points[1:]):
            if _seg_rect_gap(a, b, (x - 0.1, z - 0.1, x + 0.1, z + 0.1)) < width / 2 + 6:
                return False
    for x0, z0, x1, z1 in yards:
        if x0 - 6 < x < x1 + 6 and z0 - 6 < z < z1 + 6:
            return False
    for name, x0, z0, x1, z1 in scatter_footprints() + areas:
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
    moved = [(x0, z0, x1, z1, SCATTER_OLD_Z[n]) for n, x0, z0, x1, z1 in footprints if n in SCATTER_OLD_Z]
    car_groups = {c["anchor"] for c in cars}
    standing = set(anchors)
    # (a car counts as the 4.2 m gray box it was before the car models: so the scatter stays where it was)
    if any(math.hypot(x - c["at"][0], z - c["at"][1]) < 2.1 + 6 for c in cars if c["anchor"] in standing):
        return False
    for b, a in zip(boxes, anchors):   # props already placed (stands, campsite, power poles, fences...)
        if a in car_groups:
            continue
        bz = b[2] + M / 2
        for x0, z0, x1, z1, dz in moved:   # (a moved building's own walls count where they were)
            if x0 - 0.5 < b[0] + M / 2 < x1 + 0.5 and z0 - 0.5 < bz < z1 + 0.5:
                bz += dz
                break
        if b[4] > 0.2 and max(b[3], b[5]) < 30 and math.hypot(x - (b[0] + M / 2), z - bz) < max(b[3], b[5]) / 2 + 6:
            return False
    return True


@debris_kind("junk")
def bits(x, z, rng):
    """Small junk scattered round a clutter spot (planks, scrap, stones)."""
    for _ in range(rng.randint(2, 4)):
        a, r = rng.uniform(0, 360), rng.uniform(3.5, 6.0)
        obox(x + r * math.sin(math.radians(a)), 0.12, z + r * math.cos(math.radians(a)), rng.uniform(0.3, 0.8), 0.25,
             rng.uniform(0.6, 2.2), rng.uniform(0, 180), rng.choice(("wood", "metal", "stone", "rust")), solid=False)


scatter_pieces = []   # (spot, [(start, end) in boxes, trunks, craters, clutter_spots, woods]) of each scatter piece


@contextlib.contextmanager
def scatter_piece(x, z):
    """Notes what the scatter piece made in here added (so `clear_scatter` can take it back out whole)."""
    lists = (boxes, trunks, craters, clutter_spots, woods)
    start = [len(lst) for lst in lists]
    _scattering[0] += 1
    try:
        yield
    finally:
        _scattering[0] -= 1
    scatter_pieces.append(((x, z), [(a, len(lst)) for a, lst in zip(start, lists)]))


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
        with scatter_piece(x, z):
            kind = rng.choice(kinds)
            kind(x, z, rng)
            bits(x, z, rng)
            if kind is not crater:   # (wrecks and rubble get a level spot on the hills; craters are dug into them)
                clutter_spots.append((x, z))
    return placed


def cover_pass(spacing=11.0, tries=6000):
    """More cover between the old clutter (0.17): spots on open grass, `spacing` apart, away from everything."""
    rng = random.Random(1700)
    placed = []
    kinds = [k for k, w in COVER for _ in range(w)]
    for _ in range(tries):
        x, z = rng.uniform(0, M), rng.uniform(0, M)
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in placed) or not _clear_of_map(x, z):
            continue
        placed.append((x, z))
        with scatter_piece(x, z):
            rng.choice(kinds)(x, z, rng)
            clutter_spots.append((x, z))
    return placed


# The bombed old quarter (World art 0.17, owner 2026-10-17: the bottom right "a lot more war ruined ... the old area
# that got bombed"): more shell holes and rubble between the clutter there.
RUIN_AREAS = [(180.0, 225.0, 350.0, 350.0), (138.0, 255.0, 180.0, 340.0)]
RUIN = [(crater, 4), (rubble, 2), (ruin, 2), (wreck, 2), (tank_traps, 1), (barrels, 1)]


def ruin_pass(spacing=9.0, tries=5000):
    rng = random.Random(1017)
    ok = _cover_checker()
    kinds = [k for k, w in RUIN for _ in range(w)]
    taken = list(clutter_spots) + [(x, z) for x, z, _ in craters]
    placed = []
    for _ in range(tries):
        x0, z0, x1, z1 = rng.choice(RUIN_AREAS)
        x, z = rng.uniform(x0, x1), rng.uniform(z0, z1)
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in placed + taken) or not ok(x, z):
            continue
        placed.append((x, z))
        with scatter_piece(x, z):
            kind = rng.choice(kinds)
            kind(x, z, rng)
            if kind is not crater:
                clutter_spots.append((x, z))
    return placed


COVER_SPOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cover_spots.json")
COVER_CANDIDATES = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cover_candidates.json")


def _cover_checker():
    """A looser `_clear_of_map` for sightline breakers (they may stand closer to roads and buildings), made once
    with a grid of the props for speed."""
    cell = 10.0
    grid = {}
    car_groups = {c["anchor"] for c in cars}
    # (a car counts as the 4.2 m gray box it was before the car models: so the scatter stays where it was)
    props = [(b[0] + M / 2, b[2] + M / 2, max(b[3], b[5]) / 2 + 2.5) for b, a in zip(boxes, anchors)
             if b[4] > 0.2 and max(b[3], b[5]) < 30 and a not in car_groups]
    standing = set(anchors)
    props += [(c["at"][0], c["at"][1], 4.6) for c in cars if c["anchor"] in standing]
    for bx, bz, r in props:
        for i in range(int((bx - r) // cell), int((bx + r) // cell) + 1):
            for j in range(int((bz - r) // cell), int((bz + r) // cell) + 1):
                grid.setdefault((i, j), []).append((bx, bz, r))
    flat = [(b[0] + M / 2, b[2] + M / 2, b[3] / 2 + 2, b[5] / 2 + 2) for b in boxes
            if b[4] <= 0.06 and max(b[3], b[5]) > 8]

    def ok(x, z):
        if not (8 < x < M - 8 and 8 < z < M - 8) or abs(z - 210.0) < 6:
            return False
        if any(t[0] - 3 < x < t[2] + 3 and t[1] - 3 < z < t[3] + 3 for t in TRENCHES):
            return False
        if any(sx - 5 < x < sx + 5 and sz - 5 < z < sz + 12 for sx, sz in stand_spots):   # (the stands' ramps)
            return False
        for points, width in roads + water:
            for a, b in zip(points, points[1:]):
                if _seg_rect_gap(a, b, (x - 0.1, z - 0.1, x + 0.1, z + 0.1)) < width / 2 + 2:
                    return False
        if any(x0 - 2 < x < x1 + 2 and z0 - 2 < z < z1 + 2 for x0, z0, x1, z1 in yards):
            return False
        if any(x0 - 8 < x < x1 + 8 and z0 - 8 < z < z1 + 8 for _, x0, z0, x1, z1 in scatter_footprints() + areas):
            return False
        if any(math.hypot(x - tx, z - tz) < 3 for tx, tz in trunks):
            return False
        if any(math.hypot(x - sx, z - sz) < 8 for _, sx, sz in player_spawns + enemy_spawns):
            return False
        if any(math.hypot(x - ex, z - ez) < 12 for _, _, ex, ez in extracts):
            return False
        if any(math.hypot(x - l[2], z - l[4]) < 5 for l in loot):
            return False
        if any(abs(x - fx) < hx and abs(z - fz) < hz for fx, fz, hx, hz in flat):
            return False
        return not any(math.hypot(x - bx, z - bz) < r for bx, bz, r in grid.get((int(x // cell), int(z // cell)), []))
    return ok


def planned_cover():
    """Sightline breakers where `tools/sightlines.gd -- plan=N` found they block the most hill-to-AI views
    (tools/cover_spots.json: [x, z, yaw] in map metres; the wall runs along yaw, across the views it blocks)."""
    ok = _cover_checker()
    if os.path.exists(COVER_SPOTS):
        with open(COVER_SPOTS) as f:
            spots = json.load(f)
        for x, z, yaw in spots:
            if not ok(x, z):
                continue
            rng = random.Random(int(x * 1000 + z))
            kind = rng.choice((broken_cover, broken_cover, broken_cover, container, berm, berm))
            with scatter_piece(x, z):
                kind(x, z, rng, yaw)   # (no level pad: these stand on the hill tops, they sink into the slope instead)
            ok = _cover_checker()   # (so the next one keeps its distance)
    # Where the next round of cover could go (open ground on a 4 m grid), for tools/sightlines.gd.
    free = [[x, z] for x in range(10, int(M) - 9, 4) for z in range(10, int(M) - 9, 4) if ok(x, z)]
    with open(COVER_CANDIDATES, "w") as f:
        json.dump(free, f)


def trench():
    """Floor, earth walls and two ramps for TRENCHES, with sandbags along parts of the north lip."""
    trench_earth((TRENCHES[0][0] + TRENCHES[0][2]) / 2, (TRENCHES[0][1] + TRENCHES[0][3]) / 2)
    for x0, x1, z in ((131, 139, 171.6), (143, 151, 177.2), (160, 168, 169.6)):   # sandbags on the north lip
        sandbags((x0 + x1) / 2, z, 90, length=x1 - x0)


@debris_kind("trench")
def trench_earth(x, z):
    """The trench's earth (drawn by the outdoor kit as rough dug dirt, owner 2026-10-18)."""
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


@debris_kind("deadtree", keep=True)
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
        with scatter_piece(x, z):
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


# Power lines (World art 0.17, outdoor step 4): wooden poles with crossarms and insulators, sagging wires, a
# transformer on some poles; two poles were shelled and snapped, their top half and wires lying across the road (looks
# only: the stump keeps the old pole's collision). Drawn by the outdoor kit (make_outdoor.py draw_pole / draw_wire) in
# the look POLE_LOOK ("none": the old gray boxes, for the options sheet).
POLE_LOOK = os.environ.get("BLOXOV_POLE_LOOK", "c")
POLE_KINDS = ("pole", "pole_snap", "wire", "wire_down")
RAIL_KINDS = ("track", "bridge", "boxcar", "loco", "wagon", "tanker", "signal", "points")
SNAPPED_POLES = ((183.0, 98.0), (236.0, 277.0))   # map x, z near the two shelled poles (Main Street, the old road)


@debris_kind("pole")
def pole(x, z, yaw, transformer=False):
    """A pole at (x, z), its crossarm square to yaw (the line's direction)."""
    obox(x, 4.0, z, 0.3, 8.0, 0.3, yaw, "wood")
    obox(x, 7.475, z, 1.8, 0.15, 0.16, yaw, "wood", solid=False)
    if transformer:
        obox(x, 6.0, z, 0.01, 0.01, 0.01, yaw, "metal", solid=False)   # (a marker: the drawing adds the transformer)


@debris_kind("pole_snap")
def pole_snapped(x, z, yaw, fall):
    """A shelled pole: a 2.6 m stump, the rest lying toward `fall` (degrees)."""
    obox(x, 1.3, z, 0.3, 2.6, 0.3, yaw, "wood")
    c, s_ = math.cos(math.radians(fall)), math.sin(math.radians(fall))
    obox(x + s_ * 5.6, 0.1, z + c * 5.6, 0.3, 0.2, 5.4, fall, "wood", solid=False)   # (0.2 high: no spawn rules change)


def _wire_ends(ax, az, ayaw, bx, bz, byaw):
    """Hidden markers at both poles (their yaw = the pole's), so the wires meet the crossarms."""
    obox(ax, 0.005, az, 0.01, 0.01, 0.01, ayaw, "metal", solid=False)
    obox(bx, 0.005, bz, 0.01, 0.01, 0.01, byaw, "metal", solid=False)


@debris_kind("wire")
def wire_span(x, z, ax, az, ayaw, bx, bz, byaw):
    length = math.hypot(bx - ax, bz - az)
    with anchored(("wire", ax, az, bx, bz)):
        obox(x, 7.3, z, 0.05, 0.05, length, math.degrees(math.atan2(bx - ax, bz - az)), "metal", solid=False)
    _wire_ends(ax, az, ayaw, bx, bz, byaw)


@debris_kind("wire_down")
def wire_down(x, z, ax, az, ayaw, bx, bz, fall):
    """The wires from a standing pole (a) to a snapped one (b): hanging down and lying across the road to its top.
    (The span's box is kept as it was, hidden: the scatter keeps off long flat boxes, so nothing else moves.)"""
    length = math.hypot(bx - ax, bz - az)
    with anchored(("wire", ax, az, bx, bz)):
        obox(x, 7.3, z, 0.05, 0.05, length, math.degrees(math.atan2(bx - ax, bz - az)), "metal", solid=False)
    _wire_ends(ax, az, ayaw, bx, bz, fall)


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
            if any(x0 - 2 < px < x1 + 2 and z0 - 2 < pz < z1 + 2 for _, x0, z0, x1, z1 in scatter_footprints() + areas):
                continue
            if math.hypot(px - 263.0, pz - 285.0) < 20:   # the checkpoint
                continue
            if any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 1.0 for pts, w in roads for a, b in zip(pts, pts[1:])):
                continue
            poles.append((px, pz, math.degrees(math.atan2(tz * side, -tx * side))))   # (fall: toward the road)
        dist += seg
    if POLE_LOOK == "none":   # (the old gray boxes, for the options sheets)
        for px, pz, _ in poles:
            with group():
                box(px - 0.15, 0, pz - 0.15, px + 0.15, 8.0, pz + 0.15, "wood")
                box(px - 0.9, 7.4, pz - 0.08, px + 0.9, 7.55, pz + 0.08, "wood", solid=False)
        for (ax, az, _), (bx, bz, _) in zip(poles, poles[1:]):
            length = math.hypot(bx - ax, bz - az)
            if length < 60:
                with anchored(("wire", ax, az, bx, bz)):
                    obox((ax + bx) / 2, 7.3, (az + bz) / 2, 0.05, 0.05, length, math.degrees(math.atan2(bx - ax, bz - az)),
                         "metal", solid=False)
        return
    spans = [(a, b) for a, b in zip(poles, poles[1:]) if math.hypot(b[0] - a[0], b[1] - a[1]) < 60]
    yaws = []   # each pole's crossarm square to the line through its neighbours (a bend's bisector)
    for k, (px, pz, _) in enumerate(poles):
        prev = poles[k - 1] if k and (poles[k - 1], poles[k]) in spans else poles[k]
        nxt = poles[k + 1] if k + 1 < len(poles) and (poles[k], poles[k + 1]) in spans else poles[k]
        if prev is nxt:
            prev, nxt = poles[max(k - 1, 0)], poles[min(k + 1, len(poles) - 1)]
        yaws.append(math.degrees(math.atan2(nxt[0] - prev[0], nxt[1] - prev[1])))
    snapped = {min(range(len(poles)), key=lambda k: math.hypot(poles[k][0] - sx, poles[k][1] - sz))
               for sx, sz in SNAPPED_POLES if min(math.hypot(p[0] - sx, p[1] - sz) for p in poles) < 3.0}
    for k, (px, pz, fall) in enumerate(poles):
        if k in snapped:
            pole_snapped(px, pz, yaws[k], fall)
        else:
            pole(px, pz, yaws[k], transformer=random.Random(f"transformer {px:.1f} {pz:.1f}").random() < 0.3)
    for (a, b) in spans:
        ka, kb = poles.index(a), poles.index(b)
        if ka in snapped and kb in snapped:
            continue
        if kb in snapped or ka in snapped:
            (s, ks), (o, ko) = ((b, kb), (a, ka)) if kb in snapped else ((a, ka), (b, kb))
            wire_down((o[0] + s[0]) / 2, (o[1] + s[1]) / 2, o[0], o[1], yaws[ko], s[0], s[1], s[2])
        else:
            wire_span((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, a[0], a[1], yaws[ka], b[0], b[1], yaws[kb])


# The railway (World art 0.17, outdoor step 5): same boxes as the gray box (none of them changed: the track is looks
# only, the bridge deck and the boxcars collide as before), drawn by the outdoor kit.
@debris_kind("track")
def track_main(x, z, x0, x1):
    box(x0, 0, z - 1.6, x1, RAIL_TOP, z + 1.6, "rail", solid=False)
    for sx in range(2, int(M), 3):
        if not x0 <= sx < x1:
            continue
        if any(_nearest_on(pts, sx + 0.2, z)[0] < w / 2 + 3.0 for pts, w in roads):
            continue   # (no sleepers poking through a level crossing)
        box(sx, 0.0, z - 1.4, sx + 0.4, RAIL_TOP + 0.05, z + 1.4, "wood", solid=False)   # (5 cm up: no flicker)


_LEAD_END, _LEAD_DIR = (238.0, 214.2), (0.916, 0.401)   # where the depot line splits, and its heading there
DEPOT_SIDINGS = (
    bezier((222.0, 210.0), (230.0, 210.0), (233.4, 212.2), _LEAD_END, n=8)[:-1] +   # (off the main line, RAIL_Z)
    bezier(_LEAD_END, (_LEAD_END[0] + _LEAD_DIR[0] * 4, _LEAD_END[1] + _LEAD_DIR[1] * 4), (246.0, 220.0), (254.0, 220.0), n=8)
    + [(290.0, 220.0)],
    bezier(_LEAD_END, (_LEAD_END[0] + _LEAD_DIR[0] * 6, _LEAD_END[1] + _LEAD_DIR[1] * 6), (252.0, 228.0), (262.0, 228.0), n=10)
    + [(290.0, 228.0)])


@debris_kind("track")
def track_siding(x, z, points):
    strip(points, 3.0, "rail", y=0.0, h=0.12)


@debris_kind("bridge")
def rail_bridge(x, z):
    box(x - 6, 0.0, z - 3, x + 6, 0.25, z + 3, "wood")


@debris_kind("boxcar")
def boxcar(x, z):
    box(x - 5.5, 0, z - 1.5, x + 5.5, 3.6, z + 1.5, "boxcar")


# The waterfall and its secret room (World art 0.17, outdoor step 6; owner 2026-10-12, on the roadmap: "a waterfall by
# the creek; walk through it into a hidden room with a couple of safes"): the creek's source. At the head of the
# creek the map's west edge becomes a rock cliff (owner 2026-10-18: "on the edge of the map ... instead of the wall"),
# rising toward the border; a spring pours off its lip in front of a doorway (the falling water is drawn by
# WaterfallSheet, no collision: you walk through it) off an overhang straight into the creek's head (owner
# 2026-10-18: "the river actually goes into the waterfall"); the door opens onto the pool it falls into. Inside, a rock
# room with two safes. The ground is cut out under the room (CAVE_HOLE); every box here stands on the ground at the
# doorway (anchor "cave": y is from CAVE_OUTSIDE's ground, see terrain()). Map x, z; the cliff faces east.
CAVE_Z = (215.0, 230.0)              # the cliff's north and south ends, along the map edge
CAVE_FACE = 6.5                      # its east face (x), where the water falls
CAVE_DOOR = (221.0, 223.4, 2.3)      # the doorway in the cliff: z from, z to, height (wide enough for the AI)
CAVE_ROOM = (0.9, 219.0, 4.9, 225.5)   # the room inside (x0, z0, x1, z1)
CAVE_HOLE = (CAVE_ROOM[0], CAVE_ROOM[1], CAVE_FACE, CAVE_ROOM[3])   # (the room and the doorway through the face)
CAVE_HEIGHT = 2.6
CAVE_LIP = 6.5                       # the spring's lip, where the water falls from (the cliff rises behind it)
CAVE_OUTSIDE = (CAVE_FACE + 0.4, sum(CAVE_DOOR[:2]) / 2)   # the ground the doorway opens onto (the floor's height)
CAVE_FALL = CAVE_FACE + 1.4          # where the water falls (x): off the overhang, into the creek's head
CAVE_SPLASH = (CAVE_FALL - 0.7, CAVE_FALL + 0.7)   # the splash's x range on the water
CAVE_STREAM = []                     # (a stream from the waterfall to the creek: none now, it falls into it)
# the creek's head: the water starts behind the falling water, the channel deepens from there (Terrain._height)
CREEK_HEAD = [(CAVE_FACE + 0.2, sum(CAVE_DOOR[:2]) / 2), (CAVE_FACE + 4.6, sum(CAVE_DOOR[:2]) / 2), (15.2, 224.1)]
CREEK_HEAD_FADE = 1.2                # (m from the head to the full channel)
NO_TREES.append((0.0, CAVE_Z[0] - 2.0, CAVE_FACE + 3.0, CAVE_Z[1] + 2.0))
cave_floor = [0.0, 0.0]              # (the doorway's ground height and the water's at the fall, set in terrain())


@debris_kind("cave")
def cave_room(x, z):
    (z0, z1), fx, (dz0, dz1, dh) = CAVE_Z, CAVE_FACE, CAVE_DOOR
    rx0, rz0, rx1, rz1 = CAVE_ROOM
    back = 0.0   # (the map edge)
    box(rx0 - 0.2, -0.4, rz0 - 0.2, fx + 0.1, 0.02, rz1 + 0.2, "stone")               # the floor, out through the door
    box(rx1, -0.4, z0, fx, CAVE_LIP - 0.4, dz0, "stone")                                 # the cliff face, door in it
    box(rx1, -0.4, dz1, fx, CAVE_LIP - 0.4, z1, "stone")
    box(rx1, dh, dz0, fx, CAVE_LIP - 0.4, dz1, "stone")
    box(back, -0.4, z0, rx1, CAVE_LIP + 0.6, rz0, "stone")                               # the sides and back, higher
    box(back, -0.4, rz1, rx1, CAVE_LIP + 0.9, z1, "stone")                               # toward the border
    box(back, -0.4, rz0, rx0, CAVE_LIP + 1.6, rz1, "stone")
    box(rx0, CAVE_HEIGHT, rz0, rx1, CAVE_LIP + 0.4, rz1, "stone")                        # the roof
    box(fx - 3.4, CAVE_LIP - 0.4, z0 + 1.0, fx - 0.4, CAVE_LIP, z1 - 1.0, "stone")       # the lip on top
    box(fx - 1.0, CAVE_LIP - 1.2, dz0 - 1.4, CAVE_FALL + 0.8, CAVE_LIP + 0.2, dz1 + 1.4, "stone")   # the overhang
    # boulders tumbled round its foot, so it reads as a rock cliff, not a block
    # (0.18.3, owner: two low ones in front of the face, in the way along its foot to the door, were taken out)
    for bx, bz, w, h, d, yaw in ((fx - 0.6, z0 - 0.7, 2.2, 2.0, 1.8, -10), (fx - 2.5, z1 + 0.7, 2.4, 2.4, 1.8, 5),
                                 (1.4, z0 - 0.9, 2.0, 3.0, 1.6, 15), (1.4, z1 + 0.9, 2.0, 3.2, 1.6, -5)):
        obox(bx, h / 2 - 0.4, bz, w, h, d, yaw, "stone")
    # inside: a bedroll and a lantern (someone hid here), the two safes against the back wall
    box(rx0 + 0.6, 0.05, rz0 + 0.4, rx0 + 2.5, 0.2, rz0 + 1.2, "dirt", solid=False)
    box(rx0 + 2.7, 0.05, rz0 + 0.5, rx0 + 2.95, 0.4, rz0 + 0.75, "metal", solid=False)
    # the threshold: a slab from the floor out to the ground outside, tilted to meet it (terrain(): anchor
    # "cave_ramp"), so the step in is never too high for the AI's paths
    ramp = (fx - 0.6, sum(CAVE_DOOR[:2]) / 2, fx + 1.1, sum(CAVE_DOOR[:2]) / 2)
    with anchored(("cave_ramp",) + ramp):
        obox((ramp[0] + ramp[2]) / 2, -0.13, ramp[1], dz1 - dz0 + 0.4, 0.3, ramp[2] - ramp[0], 90.0, "concrete")
    add_loot("Waterfall", "safe", rx0 + 0.45, rz0 + 1.8, y=0.02, yaw=-90.0)
    add_loot("Waterfall", "safe", rx0 + 0.45, rz1 - 1.8, y=0.02, yaw=-90.0)


def stream_line(ter):
    """The waterfall's stream as BoxMap points (Godot x, y, z), every 0.7 m and just over the highest ground across
    it (so the ground never pokes through), ending where it runs into the creek."""
    out = []
    for (ax, az), (bx, bz) in zip(CAVE_STREAM, CAVE_STREAM[1:]):
        n = max(1, round(math.hypot(bx - ax, bz - az) / 0.7))
        for k in range(n + (1 if (bx, bz) == CAVE_STREAM[-1] else 0)):
            x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
            if in_creek(x, z, -1.4):
                return out
            tx, tz = (bz - az), -(bx - ax)
            ln = math.hypot(tx, tz) or 1.0
            y = max(ter.at(x + tx / ln * d, z + tz / ln * d) for d in (-0.5, 0.0, 0.5)) + 0.04
            out.append((gx(x), y, gz(z)))
    return out


# (0.18.7, owner: "that end of the map needs like some more rocks or smth to make it look more natural"): the knoll
# stood alone on the edge; a broken line of outcrops runs along the map edge north (past the railway) and south of it,
# and a few boulders lie out from its foot. (map x, z, yaw)
EDGE_OUTCROPS = ((2.4, 199.0, 0.0), (2.0, 190.0, 8.0), (3.2, 181.0, -5.0), (2.4, 237.0, 0.0), (2.0, 246.0, -8.0),
                 (2.8, 255.0, 5.0))
EDGE_BOULDERS = ((9.5, 214.5), (10.5, 231.5), (6.5, 241.0))


def waterfall():
    clear_scatter((0.0, CAVE_Z[0] - 3.0, CAVE_FACE + 4.0, CAVE_Z[1] + 3.0))
    with anchored(("cave",)):
        cave_room(CAVE_FACE, sum(CAVE_Z) / 2)
    rng = random.Random("edge rocks")
    for x, z, yaw in EDGE_OUTCROPS:
        clear_scatter((x - 4.0, z - 4.5, x + 4.0, z + 4.5))
        outcrop(x, z, rng, yaw=90.0 + yaw)
    for x, z in EDGE_BOULDERS:
        clear_scatter((x - 3.0, z - 3.0, x + 3.0, z + 3.0))
        rock(x, z, rng)



# Where the creek leaves the map (outdoor step 6, owner 2026-10-18: "where it meets the end of the map isnt nice"): a
# twin box culvert in a concrete headwall against the south edge, grates over both mouths, boulders at its wings. The
# water runs in through the grates; nobody walks out. Map x, z; y from the water's surface there (anchor "water").
CREEK_MOUTH = [(97.32, 340.55), (99.66, 344.16), (101.13, 348.2), (101.38, 350.0)]
CULVERT_AT = (101.3, 348.5)
CULVERT_FRONT = 347.4
NO_TREES.append((88.0, CULVERT_FRONT - 5.0, 115.0, M))


@debris_kind("culvert")
def culvert(x, z):
    f, c = CULVERT_FRONT, CULVERT_AT[0]
    box(c - 8.0, -1.4, f, c - 3.5, 3.0, M, "concrete")          # the headwall: left, the pier, right
    box(c - 0.4, -1.4, f, c + 0.4, 3.0, M, "concrete")
    box(c + 3.5, -1.4, f, c + 8.0, 3.0, M, "concrete")
    box(c - 3.5, 1.9, f, c + 3.5, 3.0, M, "concrete")           # over the two mouths
    box(c - 3.5, -1.4, M - 1.2, c + 3.5, 1.9, M, "concrete")    # the dark back of the tunnels
    box(c - 3.5, -0.6, f + 0.1, c - 0.4, 1.9, f + 0.3, "metal")  # the grates
    box(c + 0.4, -0.6, f + 0.1, c + 3.5, 1.9, f + 0.3, "metal")
    box(c - 8.4, 3.0, f - 0.3, c + 8.4, 3.25, M, "concrete")    # the coping along its top
    # boulders piled at its wings, so it sits in the banks
    for bx, bz, w, h, d, yaw in ((-8.6, f - 0.8, 2.6, 2.8, 2.2, 15), (-10.4, f + 0.8, 2.4, 3.6, 2.4, -20),
                                 (-6.2, f - 1.6, 1.8, 1.5, 1.6, 40), (8.6, f - 0.8, 2.6, 3.0, 2.2, -10),
                                 (10.4, f + 0.8, 2.4, 3.6, 2.4, 25), (6.2, f - 1.7, 1.8, 1.6, 1.5, -35)):
        obox(c + bx, h / 2 - 0.6, bz, w, h, d, yaw, "stone")


def creek_mouth():
    clear_scatter((CULVERT_AT[0] - 14.0, CULVERT_FRONT - 4.0, CULVERT_AT[0] + 14.0, M))
    with anchored(("water",) + CULVERT_AT):
        culvert(*CULVERT_AT)


# The creek's banks (outdoor step 6): pebbles and reed clumps along the waterline (looks only), a few boulders standing
# in the water (low cover, with foam rings: BoxMap water_rocks), fallen logs on the banks and two lines of stepping
# stones (by the campsite, and between the two cabins). Distances are along the water line from where it starts.
CREEK_EDGE = 3.2        # (the waterline: this far from the middle line)
CREEK_ROCKS = ((14, -1.4, 1.2), (31, 1.1, 1.0), (49, -0.6, 1.3), (70, 1.6, 0.9), (91, -1.5, 1.1), (122, 0.9, 1.2),
               (133, -1.2, 0.9), (150, 1.3, 1.1), (158, -0.4, 0.8))   # (distance, offset across (+ = left), size)
CREEK_LOGS = ((40, 5.6, 5.0), (96, -6.0, 4.2), (142, 5.8, 4.6))       # (distance, offset across, length)
CREEK_STONES = (72.5, 101.0)                                           # stepping stones across here
water_rocks = []


def _along(pts, dist):
    """(x, z, direction x, direction z) at this distance along a polyline."""
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        ln = math.hypot(bx - ax, bz - az)
        if dist <= ln or (bx, bz) == pts[-1]:
            t = min(1.0, dist / ln)
            return ax + (bx - ax) * t, az + (bz - az) * t, (bx - ax) / ln, (bz - az) / ln
        dist -= ln


@debris_kind("bank")
def bank_stretch(x, z, pts, d0, d1, rng):
    """Pebbles and reeds along both waterlines from d0 to d1 m along the creek: looks only (no collision)."""
    d = d0
    while d < d1:
        px, pz, dx, dz = _along(pts, d)
        for side in (-1, 1):
            nx, nz = -dz * side, dx * side
            if rng.random() < 0.55:   # a pebble or two, half in the water
                off = CREEK_EDGE + rng.uniform(-0.5, 0.4)
                w = rng.uniform(0.25, 0.6)
                obox(px + nx * off, w * 0.25 - 0.05, pz + nz * off, w, w * 0.6, w * rng.uniform(0.7, 1.0), rng.uniform(0, 180),
                     "stone", solid=False)
            if rng.random() < 0.3:    # a clump of reeds in the shallows
                off = CREEK_EDGE + rng.uniform(-0.3, 0.6)
                h = rng.uniform(0.9, 1.5)
                obox(px + nx * off, h / 2, pz + nz * off, rng.uniform(0.6, 1.1), h, rng.uniform(0.6, 1.0), rng.uniform(0, 180),
                     "grass", solid=False)
        d += rng.uniform(1.6, 2.6)


@debris_kind("rocks")
def creek_rock(x, z, size, yaw):
    obox(x, size * 0.45 - 0.75, z, size, size * 0.9 + 0.6, size * 0.85, yaw, "stone")


@debris_kind("log")
def fallen_log(x, z, length, yaw, rng):
    obox(x, 0.2, z, 0.48, 0.48, length, yaw + rng.uniform(-12, 12), "trunk")


@debris_kind("stones")
def stepping_stones(x, z, dx, dz, rng):
    """Flat-topped stones across the creek, a stride apart, just above the water (y from the water's surface)."""
    nx, nz = -dz, dx
    for k in range(7):
        off = -2.85 + k * 0.95 + rng.uniform(-0.1, 0.1)
        w = rng.uniform(0.6, 0.8)
        obox(x + nx * off + dx * rng.uniform(-0.2, 0.2), 0.12 - 0.6, z + nz * off + dz * rng.uniform(-0.2, 0.2), w, 1.2,
             w * rng.uniform(0.8, 1.0), rng.uniform(0, 90), "stone")


def creek_banks():
    pts = water[0][0][WATER_START:]
    length = sum(math.hypot(bx - ax, bz - az) for (ax, az), (bx, bz) in zip(pts, pts[1:]))
    rng = random.Random("creek banks")
    near_stones = lambda d: any(abs(d - s) < 3.0 for s in CREEK_STONES)
    for k in range(int(length // 12.0)):   # (one piece per 12 m, so each map chunk draws its own)
        d0, d1 = k * 12.0 + 2.0, min(length - 4.0, (k + 1) * 12.0 + 2.0)
        px, pz, _, _ = _along(pts, (d0 + d1) / 2)
        bank_stretch(px, pz, pts, d0, d1, rng)
    for d, off, size in CREEK_ROCKS:
        if near_stones(d):
            continue
        px, pz, dx, dz = _along(pts, d)
        x, z = px - dz * off, pz + dx * off
        with anchored(("water", x, z)):
            creek_rock(x, z, size, rng.uniform(0, 90))
        water_rocks.append((gx(x), gz(z), size * 0.5))
    for d, off, length_ in CREEK_LOGS:
        px, pz, dx, dz = _along(pts, d)
        x, z = px - dz * off, pz + dx * off
        clear_scatter((x - length_ / 2 - 1, z - length_ / 2 - 1, x + length_ / 2 + 1, z + length_ / 2 + 1))
        fallen_log(x, z, length_, math.degrees(math.atan2(dx, dz)), rng)
    for d in CREEK_STONES:
        px, pz, dx, dz = _along(pts, d)
        with anchored(("water", px, pz)):
            stepping_stones(px, pz, dx, dz, rng)


# The derailed freight train by the creek (World art 0.17, outdoor step 5; owner 2026-10-18 picked C): it came off
# the rails just past the bridge, westbound; the locomotive slewed off and leans into the ballast, two boxcars
# jackknifed behind it, the tanker at the back still on the rails. New cover (sightlines checked). Each car is one
# solid box like the old boxcars; a hidden marker's yaw carries the drawing's lean (BoxMap boxes can't roll).
TRAIN = (("loco", 62.0, 214.0, 65.0, 6.0), ("wagon", 76.0, 212.0, 105.0, 0.0), ("wagon", 89.0, 210.0, 82.0, 0.0),
         ("tanker", 101.0, 209.0, 90.0, 0.0))   # (kind, map x, z, yaw (Godot: 90 = along the track), lean)


@debris_kind("loco")
def locomotive(x, z, yaw, lean):
    obox(x, 2.0, z, 3.0, 4.0, 15.0, yaw, "boxcar")
    obox(x, 0.005, z, 0.01, 0.01, 0.01, lean, "metal", solid=False)


@debris_kind("wagon")
def wagon(x, z, yaw, lean):
    obox(x, 1.8, z, 3.0, 3.6, 12.0, yaw, "boxcar")


@debris_kind("tanker")
def tanker(x, z, yaw, lean):
    obox(x, 1.8, z, 3.0, 3.6, 12.0, yaw, "boxcar")


def clear_sidings():
    """Drops the scatter standing on the depot sidings (owner 2026-10-18: the track should look like the rest of the
    railway; the pieces had kept off nothing there, the sidings are flat)."""
    for pts in DEPOT_SIDINGS:
        for a, b in zip(pts, pts[1:]):
            clear_scatter(None, hit=lambda bx, a=a, b=b: bx[4] > 0.06 and 210 < bx[0] + M / 2 < 296 and
                          204 < bx[2] + M / 2 < 234 and _seg_rect_gap(a, b, (bx[0] + M / 2, bx[2] + M / 2, bx[0] + M / 2, bx[2] + M / 2)) <
                          1.7 + math.hypot(bx[3], bx[5]) / 2)


def derailed_train():
    made = len(boxes)
    for kind, x, z, yaw, lean in TRAIN:
        {"loco": locomotive, "wagon": wagon, "tanker": tanker}[kind](x, z, yaw, lean)
    mine = [_fp_corners(b, 0.6) for b in boxes[made:] if b[9]]
    clear_scatter(None, hit=lambda bx: bx[4] > 0.06 and any(not _fp_apart(_fp_corners(bx), m) for m in mine))


# Signals and points (World art 0.17, outdoor step 5): a thin solid mast, the rest looks only; made after the
# scatter (clearing what stood there) so nothing else moves. A signal faces the trains it governs (its yaw: Godot, +z toward them); a points'
# lever stands at the toe of its switch (yaw: the way the siding turns off).
RAIL_SIGNALS = ((190.0, 213.3, -90.0), (296.0, 206.7, 90.0), (54.0, 206.7, 90.0), (116.0, 213.3, -90.0))
RAIL_POINTS = ((222.6, 208.6, 0.0), (237.6, 212.3, 0.0))


@debris_kind("signal")
def rail_signal(x, z, yaw):
    obox(x, 2.6, z, 0.2, 5.2, 0.2, yaw, "metal")   # (solid, like a lamp post: the bushes keep off it)


@debris_kind("points")
def rail_points(x, z, yaw):
    obox(x, 0.3, z, 0.3, 0.6, 0.3, yaw, "metal", solid=False)


def signals_and_points():
    for x, z, yaw in RAIL_SIGNALS:
        clear_scatter((x - 1.5, z - 1.5, x + 1.5, z + 1.5))
        rail_signal(x, z, yaw)
    for x, z, yaw in RAIL_POINTS:
        clear_scatter((x - 1.0, z - 1.0, x + 1.0, z + 1.0))
        rail_points(x, z, yaw)


def fence(points, h=1.1):
    """A low wooden fence along a polyline, with a gap every so often (low cover, jumpable later)."""
    if _model[-1] is not None:   # (the graveyard's railings: drawn by its model)
        strip(points, 0.15, "wood", y=0.0, h=h, solid=True, people=True)
    else:
        farm_fence(points[0][0], points[0][1], points, h)


@debris_kind("fence")
def farm_fence(x, z, points, h):
    """(Outdoor step 8: a farm fence drawn by the outdoor kit: split rails, boards or a woven stake fence.)"""
    strip(points, 0.15, "wood", y=0.0, h=h, solid=True)


# ---------------------------------------------------------------------------------------------- set pieces (step 8)
# (World art 0.17, outdoor step 8) The checkpoint's booth, the campsite, the hunting stands, the farm's field, fences
# and tractor: drawn by the outdoor kit (make_outdoor.py) round the same gray boxes as before (same collision, cover
# and AI paths). They count for the scatter's overlap check like the plain boxes they were (only what's solid).
SET_KINDS = ("booth", "camptent", "firepit", "logseat", "stand", "crops", "fence", "farmland", "tractor", "boom", "hay")


@debris_kind("booth")
def guard_booth(x, z, yaw):
    obox(x, 1.3, z, 2.6, 2.6, 2.6, yaw, "army")


@debris_kind("camptent")
def camp_tent(x, z, yaw):
    obox(x, 0.6, z, 2.4, 1.2, 2.8, yaw, "army")
    obox(x, 1.35, z, 1.2, 0.3, 2.8, yaw, "army")


@debris_kind("firepit")
def fire_pit(x, z):
    """A ring of stones (four solid ones, step-over high) round the ashes."""
    for dx, dz in ((-0.8, 0), (0.8, 0), (0, -0.8), (0, 0.8)):
        box(x + dx - 0.3, 0, z + dz - 0.3, x + dx + 0.3, 0.3, z + dz + 0.3, "stone")


@debris_kind("logseat")
def log_seat(x, z):
    obox(x, 0.2, z, 0.5, 0.4, 2.2, 0, "trunk")


@debris_kind("stand")
def hunting_stand(sx, sz):
    """A platform 3.5 m up on four posts, rails on three sides, a ramp up the open (south) side."""
    h, run = 3.5, 5.2
    box(sx - 1.4, h - 0.2, sz - 1.4, sx + 1.4, h, sz + 1.4, "wood")
    for px, pz in ((sx - 1.3, sz - 1.3), (sx + 1.3, sz - 1.3), (sx - 1.3, sz + 1.3), (sx + 1.3, sz + 1.3)):
        box(px - 0.12, 0, pz - 0.12, px + 0.12, h - 0.2, pz + 0.12, "trunk")
    box(sx - 1.4, h, sz - 1.4, sx + 1.4, h + 1.0, sz - 1.3, "wood")       # rails (open at the ramp)
    box(sx - 1.4, h, sz - 1.4, sx - 1.3, h + 1.0, sz + 1.4, "wood")
    box(sx + 1.3, h, sz - 1.4, sx + 1.4, h + 1.0, sz + 1.4, "wood")
    obox(sx, h / 2 - 0.1, sz + 1.4 + run / 2, 2.2, 0.2, math.hypot(run, h), 0.0, "wood",
         pitch=math.degrees(math.atan2(h, run)))


FARM_FIELD = (282.0, 46.0, 342.0, 96.0)   # map x0, z0, x1, z1 of the ploughed field (make_outdoor draw_farmland)


@debris_kind("farmland")
def farmland(x, z):
    """The farm's flat ground (its gray box is a dirt slab): the field is drawn ploughed, the yard is the ground's own
    grass with dirt tracks (write_splat)."""
    box(245, 0.0, 8, 343, 0.03, 100, "dirt", solid=False)


@debris_kind("crops")
def crops(x, z):
    """A strip of crops in the farm's field, waist high (low cover): wheat, maize or sunflowers by the look."""
    box(x - 26, 0, z - 1.5, x + 26, 1.0, z + 1.5, "crop")


@debris_kind("tractor")
def tractor(x, z):
    obox(x, 1.0, z, 2.2, 2.0, 3.6, 20, "car_a")


# Made after the AI's spawn spots are picked (zone_spawns), so nothing else on the map moves for them.
HAY_BALES = ((275.0, 57.5, 10.0), (277.6, 59.8, 55.0), (273.5, 86.0, -20.0), (339.0, 42.0, 80.0))   # map x, z, yaw
BOOM_AT = (-1.0, -5.2)   # the checkpoint's boom gate: along the highway, out from its middle (see the checkpoint)
checkpoint_frame = []    # (x, z, ux, uz, nx, nz, yaw) of the highway checkpoint, set where it's built


@debris_kind("hay")
def hay_bale(x, z, yaw):
    """A round hay bale lying on its side (chest-high cover, outdoor step 8: the farm's field)."""
    obox(x, 0.7, z, 1.5, 1.4, 1.5, yaw, "hay")


@debris_kind("boom")
def boom_gate(x, z, yaw):
    """The checkpoint's boom gate, its arm up (picture only: a thin marker for the outdoor kit to draw round)."""
    obox(x, 0.55, z, 0.3, 1.1, 0.3, yaw, "army", solid=False)


# Behind the town hall (0.22.9, owner: "behind the town hall is a little open, i keep seeing them roaming around there
# and my friend keeps killing them with snipers"): Bon's crew have barricaded the hall's back lawn with shipping
# containers, an army truck and sandbag posts, ~10 m out from the back wall, gaps left to walk through. Built after
# the scatter (what stood there is cleared, while the scatter's lists still line up, like the motel's), before the
# AI's spawn spots are picked (so none lands in it).
TH_BACK_CLEAR = (78.0, 166.0, 126.0, 186.0)
TH_BACK = (("container", 85.5, 176.5, 62.0), ("sandbags", 91.6, 179.6, 90.0), ("truck", 99.0, 180.5, 92.0),
           ("sandbags", 106.4, 179.6, 90.0), ("container", 111.5, 178.6, 92.0), ("container", 119.6, 177.6, 84.0),
           ("sandbags", 124.0, 173.0, 0.0))


def town_hall_back():
    clear_scatter(TH_BACK_CLEAR)
    for k, (kind, x, z, yaw) in enumerate(TH_BACK):
        if kind == "container":
            container(x, z, random.Random(f"th back {k}"), yaw)
        elif kind == "truck":
            truck(x, z, yaw)
        else:
            sandbags(x, z, yaw)


def set_pieces_late():
    for x, z, yaw in HAY_BALES:
        assert all(math.hypot(x - sx, z - sz) > 6 for _, sx, sz in player_spawns + enemy_spawns), (x, z)
        hay_bale(x, z, yaw)
    cx, cz, ux, uz, nx_, nz_, yaw = checkpoint_frame[0]
    boom_gate(cx + ux * BOOM_AT[0] + nx_ * BOOM_AT[1], cz + uz * BOOM_AT[0] + nz_ * BOOM_AT[1], yaw)


# Small details (outdoor step 9): litter by the roads in town and round the extract camps, tyre marks and scorch marks
# on the roads, smoke rising from a few burnt-out wrecks (scenes/smoke_column.tscn). All looks only (no collision), and
# placed last (after the bushes), so nothing else moves. Posters and NOVA / X1 marks are drawn on the poles, walls and
# containers by art_source/scripts/make_outdoor.py itself.
SMOKE = []        # (map x, map z) of the wrecks that smoke


@debris_kind("litter")
def litter(x, z, yaw):
    obox(x, 0.01, z, 1.8, 0.02, 1.8, yaw, "scorch", solid=False)


@debris_kind("skid")
def skid(x, z, yaw, length):
    obox(x, 0.01, z, 1.8, 0.02, length, yaw, "scorch", solid=False)


@debris_kind("roadburn")
def road_burn(x, z, yaw, size):
    obox(x, 0.01, z, size, 0.02, size, yaw, "scorch", solid=False)


def street_details():
    rng = random.Random("street details")
    camps = [(ex, ez) for _, _, ex, ez in extracts]
    for pts, w in roads:
        dist = 0.0
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            seg = math.hypot(bx - ax, bz - az)
            if seg < 0.01:
                continue
            tx, tz = (bx - ax) / seg, (bz - az) / seg
            yaw = math.degrees(math.atan2(tx, tz))
            t = 0.0
            while t < seg:
                x, z = ax + tx * t, az + tz * t
                in_town = TOWN[0] <= x <= TOWN[2] and TOWN[1] <= z <= TOWN[3]
                by_camp = any(math.hypot(x - cx, z - cz) < 28 for cx, cz in camps)
                if 6 < x < M - 6 and 6 < z < M - 6:
                    if (in_town or by_camp) and rng.random() < 0.55:   # (litter in the gutters)
                        side = rng.choice((-1, 1))
                        off = side * (w / 2 + rng.uniform(-0.9, 1.2))
                        litter(x - tz * off, z + tx * off, rng.uniform(0, 360))
                    if rng.random() < (0.05 if in_town else 0.035):   # tyre marks
                        off = rng.uniform(-w / 4, w / 4)
                        skid(x - tz * off, z + tx * off, yaw + rng.uniform(-8, 8), rng.uniform(6.0, 13.0))
                    elif not in_town and rng.random() < 0.025:   # a shell's scorch on the road
                        road_burn(x + rng.uniform(-1, 1), z + rng.uniform(-1, 1), rng.uniform(0, 360), rng.uniform(2.2, 3.6))
                t += 7.0
            dist += seg
    burnt = [c["at"] for c in cars if c["glb"].endswith("burnt")]
    for x, z in burnt:   # scorched road round the burnt wrecks
        road_burn(x, z, rng.uniform(0, 360), 5.0)
    # (a few of them still smoke: spread over the map, not all in one place)
    for x, z in burnt:
        if all(math.hypot(x - sx, z - sz) > 90 for sx, sz in SMOKE) and len(SMOKE) < 4:
            SMOKE.append((x, z))


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
    (238, 146, 22, 5.0),    # a rise east of Station Road (World art 0.17: eased back off the station square)
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
WATER_START = 0   # the first creek point with water (it starts at the waterfall, CREEK_HEAD)
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
    (154.0, 62.0, 168.0, 80.0),    # the old grocery car park, now the church lawn (the grocery's blast debris is on it)
    (36.0, 112.0, 46.0, 141.0),    # the pavement in front of the shops (shops_frontage)
    (61.5, 98.5, 72.5, 114.5),    # town gas station forecourt
    (295.0, 334.0, 331.0, 343.0),  # old gas station canopy
    (196.0, 204.0, 246.0, 208.0),  # station platform
    (222.0, 184.0, 240.0, 190.0),  # the rubble blown out of the station office's street wall (World art 0.17)
    (232.0, 214.0, 292.0, 231.0),  # depot sidings
    (270.0, 250.0, 285.0, 256.0),  # the rubble blown out of the depot's south wall (World art 0.17)
    (316.0, 248.0, 329.0, 251.5),  # the signal box's outside stair (World art 0.17)
    (321.0, 232.0, 330.0, 238.0),  # the rubble blown out of the signal box's north wall
    (328.0, 237.0, 333.0, 245.0),  # and its east wall
    (284.0, 314.5, 291.5, 320.0),  # the rubble blown out of the diner's front (World art 0.17)
    (279.5, 332.0, 284.0, 337.5),  # and its back
    (201.0, 274.0, 209.5, 279.5),  # the rubble blown out of OldHouse1's south wall (World art 0.17)
    (190.5, 264.0, 196.0, 271.0),  # and its west wall
    (160.0, 316.0, 166.4, 324.0),  # rubble blown out of OldHouse7's east wall (World art 0.17)
    (148.5, 322.0, 156.0, 328.5),  # and its south wall
    (208.0, 266.5, 213.7, 271.0),  # and OldHouse1's east wall (upstairs)
    (124.0, 168.0, 178.0, 182.0),  # the trench
    (249.0, 271.0, 277.0, 299.0),  # the checkpoint
    (58.0, 260.0, 74.0, 274.0),    # campsite
    (89.0, 66.0, 106.0, 72.0),     # the rubble blown out of the pharmacy's north wall (round 4: part of its model)
    (220.5, 18.0, 232.5, 72.0),    # the motel's gallery, stairs and car park
    (195.0, 168.0, 243.0, 190.0),  # the station square (World art 0.17, owner 2026-10-18: level it into the hill)
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
                d, (px, pz) = _nearest_on(points, x, z)
                if d < CREEK_BANK:
                    h -= CREEK_DEPTH * (1.0 - _smoothstep(CREEK_BED, CREEK_BANK, d)) * _smoothstep(0.0, CREEK_HEAD_FADE, math.hypot(px - CREEK_HEAD[0][0], pz - CREEK_HEAD[0][1]))
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
    ter = Terrain([BUNKER_HOLE, CAVE_HOLE] + TRENCHES)
    # (the highest ground at the threshold, so walking in never steps up onto the floor)
    cave_floor[0] = max(ter.at(CAVE_OUTSIDE[0] + dx, CAVE_OUTSIDE[1] + dz) for dx in (-0.3, 0.0, 0.3) for dz in (-1.0, 0.0, 1.0))
    # (the splash lies on the threshold slab: from the floor at the door down to the ground at its end)
    cave_floor[1] = ter.water_level(CAVE_FALL, CAVE_OUTSIDE[1])

    def low(b):   # the lowest ground under a box that isn't on a pad (so it never floats)
        p = ter.pad_at(b[0] + M / 2, b[2] + M / 2)
        if p is not None:
            return p
        return min([ter.at(x, z) for x, z in _footprint(b)] + [ter.at(b[0] + M / 2, b[2] + M / 2)])
    group_lift = {}
    for b, a in zip(boxes, anchors):
        if isinstance(a, tuple) and a[0] == "g":
            group_lift[a] = min(group_lift.get(a, float("inf")), low(b))
    for b, a in zip(boxes, anchors):     # (a car's first box is its body: the model goes where it ended up)
        if isinstance(a, tuple) and a[0] == "g" and a not in car_at:
            car_at[a] = (b, group_lift[a])
    out = []
    covers = []
    car_groups = {c["anchor"]: [] for c in cars}   # (their boxes in `out`, fitted to the ground after the loop)

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
        elif a == ("cave",):
            out.append(_moved(b, cave_floor[0]))
        elif a[0] == "water":   # (y from the water's surface there)
            out.append(_moved(b, ter.water_level(a[1], a[2])))
        elif a[0] == "cave_ramp":
            _, ax, az, bx, bz = a
            out.append(_tilted(b, cave_floor[0], ter.at(bx, bz), math.hypot(bx - ax, bz - az)))
        elif a[0] == "g":
            if a in car_groups:
                car_groups[a].append(len(out))
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
    for a, idx in car_groups.items():
        if a in car_at and idx:
            fit_car(ter, a, idx, out, covers)
    boxes = out
    for x0, z0, x1, z1, top in covers:   # (no ground poking up through a floor or a yard: it flickers)
        poke = max(ter.at(x0 + (x1 - x0) * i / 12, z0 + (z1 - z0) * k / 12) for i in range(13) for k in range(13))
        assert poke < top - 0.03, f"the ground pokes through the cover at {x0:.0f}, {z0:.0f} ({poke:.2f} vs {top:.2f})"
    ter.hide_under(covers)
    # the edge of the map: a wall that follows the ground (only collision once the border's drawn: outdoor step 9)
    edge_from = len(boxes)
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
                # (the waterfall's cliff is the edge there: the wall goes see-through behind it, and taller, so its
                # top is never a way out)
                c0, c1 = max(a0, CAVE_Z[0]), min(a1, CAVE_Z[1])
                if c0 < c1:
                    box(-1, lo, a0, 0.5, hi, c0, "boundary")
                    box(-1, lo, c1, 0.5, hi, a1, "boundary")
                    _add_box((gx(-0.25), (lo + hi + 6.0) / 2, gz((c0 + c1) / 2), 1.5, hi + 6.0 - lo, c1 - c0, 0.0, 0.0,
                              C["boundary"], 2))
                else:
                    box(-1, lo, a0, 0.5, hi, a1, "boundary")
            else:
                box(M - 0.5, lo, a0, M + 1, hi, a1, "boundary")
    if os.path.exists(BORDER_GLB):
        for k in range(edge_from, len(boxes)):
            boxes[k] = boxes[k][:9] + (2,) + boxes[k][10:]
    # the bunker's ceiling (the ground above it is a thin mesh now): under the hall's floor, round the ramp hole
    hall_y = ter.pad_at(BUNKER_HOLE[0], BUNKER_HOLE[1])
    bx0, bz0, bx1, bz1 = BUNKER[0] - 0.3, BUNKER[1] - 0.3, BUNKER[2] + 0.3, BUNKER[3] + 0.3
    hx0, hz0, hx1, hz1 = BUNKER_HOLE
    # (0.18.5, owner: the vault's ceiling glitched: the vault's model draws the ceiling at the same height, so the
    # boxes are solid but not drawn, or the two fight over who's in front: stripes)
    n0 = len(boxes)
    for x0, z0, x1, z1 in ((bx0, bz0, hx0, bz1), (hx1, bz0, bx1, bz1), (hx0, bz0, hx1, hz0), (hx0, hz1, hx1, bz1)):
        box(x0, hall_y - 1.0, z0, x1, hall_y - 0.02, z1, "bunker")
    if os.path.exists(model_path("th_vault")):
        for k in range(n0, len(boxes)):
            boxes[k] = boxes[k][:9] + (2,) + boxes[k][10:]
    # containers, extracts, spawns and markers stand on the ground too
    for k, l in enumerate(loot):
        loot[k] = l[:3] + (l[3] + (cave_floor[0] if l[7] == "Waterfall" else ter.lift(l[2], l[4])),) + l[4:]
    # (the waterfall room's roof must cover the ground cut out over it)
    rx0, rz0, rx1, rz1 = CAVE_ROOM
    over = max(ter.at(rx0 + (rx1 - rx0) * i / 8, rz0 + (rz1 - rz0) * k / 8) for i in range(9) for k in range(9))
    assert over < cave_floor[0] + CAVE_LIP + 0.4 - 0.2, f"the ground pokes out over the waterfall room ({over:.2f})"
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
car_at = {}       # group anchor: (its first box, the group's lift[, its tilt]), see terrain() and fit_car()


def fit_car(ter, a, idx, out, covers):
    """Sits a car on what's under its wheels (owner 2026-10-18: a car was sunk into a hill and the road): the ground,
    a road (its ribbon is level across, at the highest ground under it) or a car park, tilted to match. Its boxes
    pitch along their length (BoxMap boxes can't roll; the model does both)."""
    b, _ = car_at[a]
    if ter.pad_at(b[0] + M / 2, b[2] + M / 2) is not None:
        return   # (on a building's floor: flat already)

    def floor(x, z):
        h = ter.at(x, z)
        r = road_top(ter, x, z)
        if r is not None:
            h = max(h, r)
        for x0, z0, x1, z1, top in covers:
            if x0 <= x <= x1 and z0 <= z <= z1:
                h = max(h, top)
        return h
    cx, cz = b[0] + M / 2, b[2] + M / 2
    c, s = math.cos(math.radians(b[6])), math.sin(math.radians(b[6]))
    hx, hz = b[3] / 2 * 0.85, b[5] / 2 * 0.8      # (the wheels: a little in from the body's corners)
    pts = [(lx, lz, floor(cx + c * lx + s * lz, cz - s * lx + c * lz)) for lx, lz in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]
    gx_ = ((pts[1][2] + pts[2][2]) - (pts[0][2] + pts[3][2])) / (4 * hx)   # rise per metre along local x
    gz_ = ((pts[2][2] + pts[3][2]) - (pts[0][2] + pts[1][2])) / (4 * hz)   # and along local z
    h0 = sum(p[2] for p in pts) / 4
    # (no belly in a bump: the middle never under the ground)
    h0 = max(h0, floor(cx, cz) - 0.15)
    # back to map axes: local x is (c, -s), local z is (s, c)
    ax, az = gx_ * c + gz_ * s, -gx_ * s + gz_ * c
    lift0 = car_at[a][1]
    for k in idx:
        q = out[k]
        qx, qz = q[0] + M / 2 - cx, q[2] + M / 2 - cz
        dy = h0 + ax * qx + az * qz - lift0
        qc, qs = math.cos(math.radians(q[6])), math.sin(math.radians(q[6]))
        pitch = -math.degrees(math.atan(ax * qs + az * qc))   # (BoxMap pitch: + tips the box's +z end down)
        out[k] = (q[0], q[1] + dy) + tuple(q[2:7]) + (q[7] + pitch,) + tuple(q[8:])
    car_at[a] = (b, h0, (ax, az))


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
            if ter.xs[i] < CAVE_FACE and CAVE_Z[0] <= ter.zs[j] < CAVE_Z[1]:
                continue   # (inside the waterfall's rock: the cut round its room)
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
    road([(186, 104), (194, 150), (206.2, 172)], 6)                                                    # Station Road
    # (World art 0.17: it ends at the station square's drop-off now, station_square())
    road([(236, 270), (290, 258), (350, 252)], 6)                                                      # East Lane
    road([(196, 240), (180, 300), (160, 348)], 6)                                                      # South Lane
    # creek (shallow: walkable) and the rail bridge over it
    creek = bezier((0, 212), (60, 250), (40, 300), (110, 350), n=48)
    creek = CREEK_HEAD + creek[6:-4] + CREEK_MOUTH   # (its last stretch turns to run straight into the culvert at the edge)
    water.append((creek, 5.0))   # (the water itself is a surface `BoxMap` makes from `water_points`)

    # --- railway (west to east at y 210) with sidings to the depot
    RY = RAIL_Z
    # (World art 0.17, outdoor step 5: the track drawn by the outdoor kit, make_outdoor.py draw_track: ballast,
    # sleepers, rails; one piece per map chunk so each chunk draws its own stretch)
    for k in range(int(M // OUTDOOR_CHUNK)):
        track_main(k * OUTDOOR_CHUNK + OUTDOOR_CHUNK / 2, RY, k * OUTDOOR_CHUNK, (k + 1) * OUTDOOR_CHUNK)
    # (owner 2026-10-18: one line off the main line, then splitting to the two depot sidings; curved, not kinked)
    for siding in DEPOT_SIDINGS:
        track_siding(siding[-1][0], siding[-1][1], siding)
    rail_bridge(42, RY)   # the rail bridge's deck over the creek

    # ===================================================================== TOWN (top left)
    # town square: paving + lots of cover (owner): fountain, planters, stalls, parked cars, statue, kiosk
    # (World art 0.17: each piece drawn by the outdoor kit, art_source/scripts/make_outdoor.py; same boxes as before)
    plaza(106, 123, 36, 30)
    fountain(106, 123)
    for px, pz in ((93, 112), (119, 112), (93, 134), (119, 134), (98, 123), (114, 123)):
        planter(px, pz)
    stall(99, 115, 0); stall(106, 115, 0); stall(113, 115, 0)
    stall(100, 131, 0); stall(112, 131, 0)
    car(91, 124, 0, "car_b"); car(121, 126, 10, "car_a")
    statue(106, 134.5)
    kiosk(119.25, 119.25)

    # downtown
    bunker_floor = -4.5
    hx0, hz0, hx1, hz1 = bunker_hole
    with modeled("town_hall", 107.0, 155.0):   # World art 0.17: the town hall (ransacked; Bon's crew hold it)
        # Loot spots slid off the windows. The mayor's office (upstairs, north-east) caved in (owner: like the offices;
        # a corner room, so the roof's cut pieces stay small and the AI spawn spots round the hall keep their room).
        hall = build(Building("TownHall", 82, 146, 50, 18, floors=2, colour="wall_hall", rooms=(4, 2), doors="NS",
                              roof=True, caved=[(3, 0)]), [
            ("locker", 1, 0, 1, "N", -2.6), ("crate", 2, 1, 1, "S", 2.6), ("locker", 3, 0, 1, "E", -2.4, "wardrobe"),
            ("crate", 1, 1, 0, "S", 2.6)])
        town_hall_furniture(107.0, 155.0)
        # Washroom (owner, 2026-10-16): the planning office's south-west corner.
        washroom(107.0, 155.0, 12.6, 6.4, 15.0, 8.85, "NE", ("N", 14.0, -1), fit=(
            ("wc_toilet", "S", 14.55, 0.45, 0.72, 0.85), ("wc_sink", "W", 7.6, 0.5, 0.45, 0.9)))
        # (no rail round the bunker's ramp hole now: a "ghost cloth" runner hides it, owner; drawn by the model)
    # World art 0.17: the bunker is the town hall's vault (its own model: shelter, strongroom, records, lab)
    with modeled("th_vault", 107.0, 155.0):
        # the bunker (owner: best loot, behind a key door later): ramp down from the hall's west room
        run = hx1 - hx0
        obox((hx0 + hx1) / 2, bunker_floor / 2 - 0.1, (hz0 + hz1) / 2, hz1 - hz0 - 0.1, 0.2, math.hypot(run, bunker_floor),
             90.0, "concrete", pitch=math.degrees(math.atan2(-bunker_floor, run)))   # top (y 0) west, bottom east
        bx0, bz0, bx1, bz1 = BUNKER
        box(bx0, bunker_floor - 0.3, bz0, bx1, bunker_floor, bz1, "bunker")                 # floor
        box(bx0 - 0.3, bunker_floor, bz0 - 0.3, bx1 + 0.3, -1.0, bz0, "bunker")              # north wall
        box(bx0 - 0.3, bunker_floor, bz1, bx1 + 0.3, -1.0, bz1 + 0.3, "bunker")              # south wall
        box(bx0 - 0.3, bunker_floor, bz0, bx0, -1.0, bz1, "bunker")                          # west wall
        box(bx1, bunker_floor, bz0, bx1 + 0.3, -1.0, bz1, "bunker")                          # east wall
        # shaft wall north of the ramp (its rail upstairs is with the hall's model)
        box(hx0, bunker_floor, hz0 - 0.3, hx1, -1.0, hz0, "bunker")
        # the shaft's sides between the vault's ceiling (-1) and the hall's floor (0), all round the hole: without them
        # you saw out under the whole map from the ramp once the ghost cloth tripped (0.19.4)
        box(hx0 - 0.3, -1.0, hz0 - 0.3, hx1 + 0.3, 0.0, hz0, "bunker")                     # north
        box(hx0 - 0.3, -1.0, hz1, hx1 + 0.3, 0.0, hz1 + 0.3, "bunker")                     # south
        box(hx0 - 0.3, -1.0, hz0, hx0, 0.0, hz1, "bunker")                                 # west (the ramp's top)
        box(hx1, -1.0, hz0, hx1 + 0.3, 0.0, hz1, "bunker")                                 # east (over the ramp's foot)
        # key door: the wall at x 99 between the ramp landing and the bunker rooms (locked: the bunker key, 0.14.0)
        wall_z(bz0, bz1, 99.0, bunker_floor, -1.0 - bunker_floor, "bunker", [(155.0, DOOR_W, 0.0, DOOR_H)])
        # bunker rooms: corridor along the south, three vaults to the north
        for x in (110.0, 121.0):
            wall_z(bz0, bz1 - 5, x, bunker_floor, 3.5, "bunker", [((bz0 + bz1 - 5) / 2, INNER_DOOR_W, 0.0, DOOR_H)])
        wall_x(99.0, bx1, bz1 - 5, bunker_floor, 3.5, "bunker",
               [(104.5, INNER_DOOR_W, 0.0, DOOR_H), (115.5, INNER_DOOR_W, 0.0, DOOR_H), (126.5, INNER_DOOR_W, 0.0, DOOR_H)])
    markers.append(("KeyDoors", "BunkerDoor", 99.0, bunker_floor, 155.0, {"key": "bunker_key", "place": "Bunker", "yaw": 90.0, "width": DOOR_W}))
    for x, z, yaw in ((102.0, 148.0, 180.0), (113.0, 148.0, 180.0), (124.0, 148.0, 180.0), (130.5, 153.0, 90.0)):
        add_loot("Bunker", "safe", x, z, y=bunker_floor, yaw=yaw)
    add_loot("Bunker", "locker", 107.0, 148.0, y=bunker_floor, yaw=180.0)
    add_loot("Bunker", "crate", 101.0, 160.5, y=bunker_floor, yaw=-90.0)   # (faces down the corridor, owner)

    # bank with offices upstairs, one building east of the square (owner). The vault is the south-east room (1, 2),
    # only reachable from room (1, 1) through a key door (the bank vault key; the stairs are along the north wall).
    with modeled("bank", 136.0, 125.0):   # World art 0.17: the Bank of Bloxov (ransacked; Raiders hold it)
        # Loot spots slid off the windows. The security room upstairs (south-east, over the vault) caved in (a corner
        # room; the north-east one is over the stairs' corridor).
        bank = build(Building("Bank", 128, 110, 16, 30, floors=2, colour="wall_rich", rooms=(2, 3), doors="W",
                              solid_inner=[("v", 1, 2)], no_windows=[(1, 2)], caved=[(1, 2)]), [
            ("safe", 1, 2, 0, "E", 1.5), ("safe", 1, 2, 0, "S", 0), ("locker", 1, 1, 0, "S", -3.4, "gun_cabinet"),
            ("crate", 1, 0, 0, "E", -2.6)])
        for kind, i, j, side, off in (("crate", 1, 0, "E", -2.6), ("crate", 0, 2, "W", 2.6), ("locker", 1, 1, "E", 2.6),
                                      ("crate", 0, 1, "W", -2.6)):
            x, y, z, yaw = bank.against_wall(i, j, 1, side, off)
            add_loot("Offices", kind, x, z, y=y, yaw=yaw)
        bank_furniture(136.0, 125.0)
        # Staff washroom (owner, 2026-10-16): the records room's south-west corner, upstairs.
        washroom(136.0, 125.0, 0.1, -7.6, 2.5, -5.1, "NE", ("E", -6.4, -1), y=FLOOR_H, fit=(
            ("wc_toilet", "W", -5.8, 0.45, 0.72, 0.85), ("wc_sink", "N", 0.7, 0.5, 0.45, 0.9)))
    markers.append(("KeyDoors", "BankVaultDoor", 140.0, 0.0, 130.0, {"key": "bank_vault_key", "place": "Bank", "yaw": 0.0, "width": INNER_DOOR_W}))
    with modeled("offices", 75.0, 129.5):   # World art 0.17: Korven Engineering's office (ransacked)
        # Loot spots slid off the windows.
        build(Building("Offices", 64, 119, 22, 21, floors=2, rooms=(3, 2), doors="E",
                       blasts=[(0, "W", 0)], caved=[(1, 1)]), [
            ("crate", 0, 1, 0, "W", 2.5), ("crate", 2, 0, 0, "N", 2.3), ("crate", 1, 0, 1, "N", 0),
            ("locker", 2, 1, 1, "E", 2.6), ("crate", 0, 0, 1, "W", 2.4)])
        offices_furniture(75.0, 129.5)
        # Washroom (owner, 2026-10-16): the meeting room's south-east corner, upstairs (the room south of the
        # archive is the caved-in one, open to the sky).
        washroom(75.0, 129.5, 8.5, -2.45, 10.85, -0.1, "WN", ("N", 9.4, 1), y=FLOOR_H, fit=(
            ("wc_toilet", "E", -0.6, 0.45, 0.72, 0.85), ("wc_sink", "S", 9.0, 0.5, 0.45, 0.9)))
    with modeled("gun_store", 78.0, 76.0):   # World art 0.17
        # Border Arms: the shop east (door south), the gun room west. Loot spots slid off the windows.
        build(Building("GunStore", 70, 70, 16, 12, colour="wall_guns", rooms=(2, 1), doors="S"), [
            ("locker", 0, 0, 0, "W", -1.55), ("locker", 1, 0, 0, "E", 3.0), ("crate", 1, 0, 0, "N", -2.4)])
        for z in (73.0, 77.0):   # glass display counters (same spots as the gray box's counters)
            box(72.0, 0, z, 77.0, 1.0, z + 0.8, "wood", kind="gun_counter")
        box(71.0, 0, 70.15, 72.9, 2.4, 70.55, "wood", kind="rifle_rack")        # behind the north counter
        box(75.0, 0, 70.15, 77.6, 2.4, 70.55, "wood", kind="rifle_rack")
        box(70.3, 0, 81.2, 72.8, 0.9, 81.85, "wood", kind="gunsmith_bench")    # gun room, south wall
        box(75.3, 0, 81.0, 77.1, 0.7, 81.8, "metal", kind="ammo_cans")
        box(82.9, 0, 72.4, 85.6, 1.0, 73.0, "wood", kind="gun_till")           # shop: the till, a parts wall behind
        box(83.2, 0, 70.15, 85.8, 0.9, 70.6, "wood", kind="parts_wall")
        box(78.3, 0, 81.35, 80.6, 1.8, 81.85, "metal", kind="ammo_wall")        # ammo shelves
        box(78.1, 0, 77.6, 78.6, 1.8, 80.9, "metal", kind="ammo_wall")
    with modeled("pharmacy", 97.5, 78.0):   # World art 0.17: shop floor (east), dispensary (west)
        # Staff washroom (owner, 2026-10-16): the dispensary's south-east corner, behind the counter.
        washroom(97.5, 78.0, -2.4, 3.9, -0.1, 5.85, "WN", ("W", 5.0, -1), fit=(
            ("wc_toilet", "S", -0.6, 0.45, 0.72, 0.85), ("wc_sink", "E", 4.4, 0.5, 0.45, 0.9)))
        build(Building("Pharmacy", 90, 72, 15, 12, colour="wall_med", rooms=(2, 1), doors="S", blasts=[(0, "N", 0)]), [
            ("crate", 0, 0, 0, "W", -3.0), ("crate", 1, 0, 0, "E", -2.6, "stock_meds")])   # (off the windows)
        box(92.0, 0, 76.0, 96.5, 1.6, 76.8, "wood", kind="rx_shelf")
        # Shop: two aisles of shelves, a wall of shelves, the till counter, a sunglasses stand by the door.
        box(98.6, 0, 73.8, 99.4, 1.6, 77.2, "metal", kind="pharm_gondola")   # clear of the window
        box(101.0, 0, 73.8, 101.8, 1.6, 77.2, "metal", kind="pharm_gondola")
        box(102.6, 0, 72.15, 104.8, 2.0, 72.6, "metal", kind="pharm_wall")
        # The till (round 4, owner: an area to walk behind): a counter facing the shop, a back bar on the wall.
        box(102.9, 0, 79.4, 103.5, 1.0, 82.6, "wood", kind="pharm_counter")
        box(104.4, 0, 79.8, 104.85, 0.9, 82.2, "wood", kind="pharm_backbar")
        box(98.1, 0, 81.8, 98.7, 1.6, 82.4, "metal", kind="spinner")
        # Dispensary: drug drawers, the prescriptions counter, the pharmacist's desk.
        box(90.4, 0, 83.2, 92.9, 2.0, 83.85, "wood", kind="rx_drawers")
        box(94.5, 0, 79.9, 97.0, 1.0, 80.7, "wood", kind="rx_counter")   # (0.6 m north: room to the washroom door, owner)
        box(90.4, 0, 72.4, 91.9, 0.75, 73.3, "wood", kind="desk")
    with modeled("grocery", 140.0, 70.0):   # World art 0.17: a real supermarket (sales floor + back rooms)
        build(Building("Grocery", 128, 60, 24, 20, colour="wall_food", rooms=(3, 2), doors="S", roof=True,
                       blasts=[(0, "E", 0)], open_plan=True, roof_ramp="NE", wall_openings=GROCERY_OPENINGS))
        grocery_furniture(140.0, 70.0)
        # Staff washroom (owner, 2026-10-16): the stock room's south-east corner (the pallet jack moved for it).
        washroom(140.0, 70.0, -4.0, -8.0, -1.6, -5.7, "WN", ("W", -6.7, -1), fit=(
            ("wc_toilet", "E", -7.4, 0.45, 0.72, 0.85), ("wc_sink", "S", -2.3, 0.5, 0.45, 0.9)))
    # The old car park (taken back out by churchyard(): made here still so the scatter round it doesn't change).
    old_car_park[0] = len(boxes)
    box(154, 0.0, 62, 168, 0.06, 80, "pavement", solid=False)
    car(158, 66, 0); car(164, 74, 0, "car_b")
    old_car_park[1] = len(boxes)
    # (0.17, owner: the school moved up by the hill houses and the shops down to where it was)
    with modeled("shops", 29.5, 126.5, turned=90):   # World art 0.17: laundromat (west), shoe store (middle), burned-out TV shop
        # The flat's bathroom (owner, 2026-10-16), upstairs beside the stairwell: a bath, the toilet, a basin.
        washroom(29.5, 126.5, -7.2, -6.35, -4.93, -4.1, "WS", ("S", -5.6, -1), y=FLOOR_H, fit=(
            ("wc_bath", "N", -6.1, 1.6, 0.7, 0.55), ("wc_toilet", "E", -5.2, 0.45, 0.72, 0.85),
            ("wc_sink", "W", -4.8, 0.5, 0.45, 0.9)))
        # The shoe store's staff toilet, upstairs in its stock room (owner, 2026-10-17: none downstairs in the
        # laundromat, no room; none in the TV shop, its upstairs one was blown up).
        washroom(29.5, 126.5, -4.73, -6.35, -2.53, -4.15, "ES", ("E", -5.25, 1), y=FLOOR_H, fit=(
            ("wc_toilet", "W", -5.6, 0.45, 0.72, 0.85), ("wc_sink", "N", -3.3, 0.5, 0.45, 0.9)))
        build(Building("Shops", 15, 120, 29, 13, floors=2, rooms=(3, 1), doors="E", caved=[(2, 0)], shopfronts="S"), [
            ("crate", 0, 0, 0, "W", -1.5, "laundry_cart"), ("crate", 2, 0, 0, "E", 3.5, "stock_tv"),
            ("crate", 1, 0, 1, "N", 2.2, "stock_shoes"), ("locker", 0, 0, 1, "W", -2.6, "wardrobe"),
            ("crate", 1, 0, 0, "E", -3.5, "stock_shoes")])   # round 4: each room's own loot, off the windows
        # Laundromat: a double row of washers, dryers on the west wall, a folding table.
        box(16.2, 0, 123.0, 20.8, 1.0, 124.4, "metal", kind="washers")
        box(15.15, 0, 128.2, 15.95, 1.9, 131.6, "metal", kind="dryers")
        box(16.6, 0, 128.6, 19.4, 0.9, 129.6, "wood", kind="fold_table")
        # Shoe store: shoe walls, try-on benches, a display table, the till, a pile of shoeboxes, the window display.
        box(25.2, 0, 120.15, 28.6, 2.2, 120.6, "wood", kind="shoe_wall")
        box(30.4, 0, 120.15, 33.8, 2.2, 120.6, "wood", kind="shoe_wall")
        box(26.4, 0, 122.6, 28.6, 0.45, 123.15, "wood", kind="bench")
        box(30.4, 0, 122.6, 32.6, 0.45, 123.15, "wood", kind="bench")
        box(28.2, 0, 128.8, 30.2, 0.8, 130.0, "wood", kind="shoe_table")
        box(32.6, 0, 128.6, 34.1, 1.0, 130.8, "wood", kind="shoe_counter")
        box(25.2, 0, 128.8, 26.0, 1.2, 129.8, "wood", kind="shoebox_stack")
        box(26.0, 0, 131.9, 29.8, 0.4, 132.8, "wood", kind="window_display")
        # TV shop (burned out, its roof fell in): shelves of dead TVs, a display table.
        box(35.0, 0, 120.15, 38.4, 2.0, 120.7, "metal", kind="tv_shelf")
        box(40.0, 0, 120.15, 43.5, 2.0, 120.7, "metal", kind="tv_shelf")
        box(36.4, 0, 129.8, 39.0, 0.9, 131.0, "metal", kind="tv_table")
        box(42.1, 0, 122.9, 43.8, 1.0, 123.7, "metal", kind="tv_counter")
        box(34.8, 0, 131.2, 35.6, 1.1, 132.2, "metal", kind="box_stack")
        # Upstairs: a small flat over the laundromat, the shoe store's stock room.
        box(16.0, 3.0, 129.6, 18.0, 3.5, 132.8, "wood", kind="bed")
        box(20.0, 3.0, 125.0, 21.4, 3.75, 126.0, "wood", kind="table")
        box(21.0, 3.0, 132.3, 24.0, 3.95, 132.85, "wood", kind="kitchenette")
        box(25.2, 3.0, 132.25, 28.4, 5.0, 132.85, "metal", kind="rack")
        box(30.6, 3.0, 132.25, 33.8, 5.0, 132.85, "metal", kind="rack")
        box(32.6, 3.0, 120.3, 34.1, 3.75, 121.1, "wood", kind="desk")   # in the corner (owner)
    # modern gas station on the corner of Main Street and Old Road (owner, 0.10.1; the town house was here)
    with modeled("gas_station_town", 80.5, 111.0):   # World art 0.17: the first modeled building
        build(Building("GasStationTown", 74, 106, 13, 10, colour="wall_modern", rooms=(2, 1), doors="W"), [
            ("crate", 1, 0, 0, "E", -2.6), ("locker", 1, 0, 0, "E", 2.6)])   # stock room: boxes, a staff locker
        for x in (63.0, 70.5):
            for z in (100.0, 112.5):
                box(x, 0, z, x + 0.5, 4.6, z + 0.5, "wall_modern", kind="canopy_post")
        box(62.5, 4.6, 99.5, 71.5, 5.0, 113.5, "brand", kind="canopy")
        box(61.5, 0.0, 98.5, 72.5, 0.05, 114.5, "pavement", solid=False, kind="forecourt")
        box(72.5, 0.0, 104.5, 74.0, 0.05, 117.5, "pavement", solid=False, kind="forecourt")   # apron to the door
        for z in (103.0, 107.0, 111.0):
            box(66.4, 0, z - 0.6, 67.6, 1.6, z + 0.6, "metal", kind="pump")
        # Inside (0.17: furniture, so it collides like it looks). Shop (west room): till, shelf, drinks fridges.
        box(74.9, 0, 113.9, 77.9, 1.0, 114.6, "wood", kind="counter")
        box(78.2, 1.3, 115.6, 80.1, 2.1, 115.85, "wood", kind="cig_rack")   # right of the window (owner)
        box(76.1, 0, 108.5, 78.9, 1.4, 109.3, "metal", kind="shelf")
        box(78.1, 0, 106.15, 79.5, 2.1, 106.85, "metal", kind="fridge")   # (windows stay clear, owner)
        box(79.0, 0, 108.5, 79.6, 1.1, 109.3, "metal", kind="endcap")       # snacks at the end of the shelf
        box(79.6, 0, 106.15, 80.35, 1.7, 106.8, "metal", kind="atm")
        box(74.15, 0, 112.6, 74.75, 0.95, 113.7, "wood", kind="coffee")
        box(79.95, 0, 113.0, 80.35, 1.3, 114.4, "metal", kind="magazines")
        # Back room: storage racks and a desk.
        box(81.0, 0, 106.15, 82.9, 2.0, 106.75, "metal", kind="rack")
        box(81.0, 0, 115.25, 82.9, 2.0, 115.85, "metal", kind="rack")
        box(84.9, 0, 114.6, 86.4, 0.75, 115.5, "wood", kind="desk")
        # Outside: the price sign at the corner, an ice chest by the door.
        box(62.6, 0, 99.1, 62.9, 6.2, 99.4, "metal", kind="sign_pole")
        box(72.6, 0, 112.8, 73.4, 1.0, 114.4, "metal", kind="ice_chest")
        box(83.0, 3.0, 108.0, 84.6, 3.8, 109.2, "metal", kind="roof_ac")   # on the roof
    with modeled("police", 163.0, 123.0, turned=True):   # World art 0.17: Bloxov police station (overrun, ransacked)
        # The caved room is a corner room upstairs (north-east: the other corners hold the stairs' landing and the
        # roof stairs, and the south-west one the staff lockers).
        build(Building("Police", 150, 112, 26, 22, floors=2, colour="wall_police", rooms=(3, 3), doors="WS", roof=True,
                       caved=[(2, 0)], solid_inner=[("h", 1, 2)]), [
            ("locker", 2, 0, 0, "E", -2.3, "gun_cabinet"), ("locker", 2, 0, 0, "N", -1.7, "gun_cabinet"),
            ("locker", 0, 2, 1, "W", 2.3), ("locker", 2, 2, 1, "E", -2.3), ("crate", 2, 1, 0, "E", 2.4)])
        # (loot slid off the windows; the cells, middle, have no door to the lobby)
        police_furniture(163.0, 123.0)
    for x, z, yaw in ((180, 118, 90), (180, 126, 90)):
        car(x, z, yaw, "car_b")
    barrier(178, 108, 90)
    with modeled("school", 23.0, 62.0):   # World art 0.17
        build(Building("School", 8, 50, 30, 24, floors=2, colour="wall_school", rooms=(3, 3), doors="S", roof=True), [
            ("crate", 0, 0, 0, "W", -1.6), ("crate", 2, 2, 0, "E", -1.4, "kitchen"), ("locker", 1, 2, 1, "S", -2.5, "filing"),
            ("crate", 0, 1, 1, "W", -1.8)])   # library, staff lounge, principal's office, computer room (off the windows)
        school_furniture()
        # Washrooms (owner, 2026-10-16): boys' and girls' in the lobby's north-east corner, by the hall door.
        washroom(23.0, 62.0, 1.2, 4.1, 2.975, 6.5, "WES", ("S", 2.1, 2), sign="wc_sign_m", fit=(
            ("wc_toilet", "N", 2.4, 0.45, 0.72, 0.85), ("wc_sink", "W", 5.6, 0.5, 0.45, 0.9)))
        washroom(23.0, 62.0, 3.125, 4.1, 4.9, 6.5, "S", ("S", 4.0, -2), sign="wc_sign_f", fit=(
            ("wc_toilet", "N", 4.3, 0.45, 0.72, 0.85), ("wc_sink", "E", 5.6, 0.5, 0.45, 0.9)))
    box(15, 0.0, 148, 45, 0.06, 166, "lot", solid=False)   # the shops' car park (was the sports field)
    car(22, 154, 90); car(34, 160, 90, "car_b"); car(40, 152, 270)

    # hillside: big houses (owner: expensive loot)
    # (0.10.1: down from 5 to 3, owner: fewer houses so the good loot isn't spread thin, and the hill has sightlines)
    for n, (x, y, w, d, who) in enumerate(RICH_HOUSES, start=1):
        rich_house(n, x, y, w, d, who)
    add_loot("BigHouse1", "safe", 41.0, 22.8, y=FLOOR_H, yaw=180.0)   # in the doctor's bedroom

    # street cover around town
    # (owner 2026-10-18 picked burnt wrecks, look B, for some of the road cars: "rust" = a burnt-out shell)
    for x, z, yaw, col in ((44, 85, 85, "car_a"), (80, 96, 72, "rust"), (125, 101, 92, "car_a"), (150, 104, 97, "rust"),
                           (57, 112, 10, "car_a"), (118, 52, 5, "rust")):
        car(x, z, yaw, col)
    for x, z in ((48, 82), (88, 88), (124, 88), (147, 143), (78, 143), (126, 84)):
        dumpster(x, z)

    # the Last Stop Motel between town and farm (World art 0.17: it replaced the two road houses there). It's built
    # after the scatter (see `motel`); until then the scatter keeps clear of where the road houses stood, so it
    # doesn't reshuffle map-wide.
    footprints.extend(MOTEL_GHOSTS)

    # church and graveyard, top right of town (owner, 0.10.1): a bell tower you can climb (roof lookout), pews
    # inside, headstones (low cover) and a crypt
    with modeled("church", 167.0, 40.0):   # World art 0.17: the parish church (nave, chancel, washroom, vestry)
        build(Building("Church", 160, 28, 14, 24, colour="wall", rooms=(1, 1), doors="S", height=6.0,
                       wall_openings=CHURCH_OPENINGS), [
            ("crate", 0, 0, 0, "N", -4.5, "chest"), ("locker", 0, 0, 0, "N", 4.5, "wardrobe")])
        church_furniture(167.0, 40.0)
        church_roof_solid(167.0, 40.0)
    with modeled("bell_tower", 153.0, 33.0):   # World art 0.17: the church's bell tower (ringing room, clock, belfry)
        tower = build(Building("BellTower", 148, 28, 10, 10, floors=2, colour="wall", rooms=(1, 1), doors="S", roof=True,
                               wall_openings={"E": [("door", 34.5, 1.6, 0.0, DOOR_H)]}),
                      [("crate", 0, 0, 2, "W", 0, "chest")])
        # A covered passage from the ringing room to the church's west door (owner 2026-10-16: "i like it having a
        # passage to the church a lot"), 2 m across, between the two walls' faces.
        for z0 in (33.4, 35.4):
            box(158.15, 0.0, z0, 159.85, 2.8, z0 + 0.2, "wall", kind="passage_wall")
        box(158.15, 2.8, 33.4, 159.85, 3.0, 35.6, "slab", kind="passage_roof")
        for px, pz in ((148.4, 28.4), (157.6, 28.4), (148.4, 37.6), (157.6, 37.6)):  # the bell frame on the roof
            box(px - 0.2, 6.0, pz - 0.2, px + 0.2, 9.0, pz + 0.2, "wood", kind="belfry_pier")
        box(148.2, 9.0, 28.2, 157.8, 9.4, 37.8, "roof", kind="belfry_canopy")
        box(152.4, 7.4, 32.4, 153.6, 8.9, 33.6, "metal", solid=False, kind="bell")   # the bell
        bell_tower_furniture(153.0, 33.0)
    areas.append(("Graveyard", 176, 30, 202, 56))
    with modeled("graveyard", 189.0, 43.0):   # World art 0.17: churchyard wall + railings, real headstones, the crypt
        fence([(181, 56), (176, 56), (176, 45)]); fence([(176, 39), (176, 30), (202, 30), (202, 56), (186, 56)])
        build(Building("Crypt", 192, 43, 8, 8, colour="stone", rooms=(1, 1), doors="W", no_windows={(0, 0)}),
              [("crate", 0, 0, 0, "E", 0, "chest")])   # (a crypt: no windows, coffin shelves on the walls)
        for z in range(33, 54, 3):
            for x in (179.0, 181.6, 184.2, 186.8, 191.0, 193.6, 196.2, 198.8):     # (a path down the middle)
                if 188 < x + 1 and x - 1 < 202 and 41 < z + 0.5 and z - 0.5 < 53.5 and x > 189:
                    continue   # the crypt and the ground round it
                if rng.random() < 0.25:
                    continue
                box(x - 0.45, 0, z - 0.12, x + 0.45, rng.uniform(0.8, 1.1), z + 0.12, "stone", kind="headstone")
        graveyard_furniture(189.0, 43.0)
        with unmodeled():
            for tx, tz in ((178, 54), (200, 32), (178, 32)):
                tree(tx, tz, rng)

    # ===================================================================== FARM (top right)
    farmland(294, 54)
    farm_barn()
    # The silo and the shed stand well off the barn (owner, 2026-10-17: "the farm is huge").
    with modeled("silo", SILO[0], SILO[1]):
        # Round concrete silo (World art 0.17): drawn round by its model; solid as an octagon (two squares) inside it.
        obox(SILO[0], 6.0, SILO[1], 6.4, 12.0, 6.4, 0.0, "concrete", kind="silo")
        obox(SILO[0], 6.0, SILO[1], 6.4, 12.0, 6.4, 45.0, "concrete", kind="silo_part")
    rich_house(0, 310, 26, 16, 12, "farmer", model="farmhouse", place="Farmhouse", colour="wall", loot=[
        ("locker", 1, 0, 0, "E", 1.9), ("crate", 0, 1, 1, "W", -1.9)])   # (the wardrobe off the kitchen table)
    shx, shz = SHED_SHIFT
    with modeled("shed", 255.0 + shx, 51.0 + shz):
        # The machine shed (World art 0.17): workbench and tool wall on the north wall, an engine on a stand, tyres,
        # shelving, fuel drums; the middle and the big door's way in stay clear.
        build(Building("Shed", 248 + shx, 46 + shz, 14, 10, colour="wall_farm", rooms=(1, 1), doors="E", height=4.0,
                       big_doors=True), [("crate", 0, 0, 0, "W", 0)])
        box(249.6 + shx, 0, 46.15 + shz, 253.8 + shx, 0.92, 46.85 + shz, "wood", kind="shed_bench")
        box(250.9 + shx, 0, 48.9 + shz, 252.1 + shx, 1.05, 49.9 + shz, "metal", kind="engine_stand")
        box(248.25 + shx, 0, 54.4 + shz, 249.35 + shx, 1.2, 55.75 + shz, "metal", kind="tyre_stack")
        box(252.0 + shx, 0, 55.3 + shz, 255.0 + shx, 2.0, 55.85 + shz, "metal", kind="shed_shelf")
        box(259.3 + shx, 0, 54.6 + shz, 261.7 + shx, 0.95, 55.75 + shz, "metal", kind="fuel_drums")
    for k in range(5):   # crop rows (low cover)
        crops(312, 50 + k * 9 + 1.5)
    fence([(245, 8), (245, 40)]); fence([(245, 52), (245, 100), (300, 100)]); fence([(312, 100), (343, 100)])
    tractor(250, 90)

    # ===================================================================== MIDDLE: train station + depot
    with modeled("train_station", 219.0, 197.0):
        # Bloxov Station (World art 0.17, plan worldart/station-plan.md): waiting room + washrooms west, booking hall
        # in the middle (street door north, platform door south), ticket office + station master + parcels east.
        # Same loot: the left luggage (west), the parcels (east), the luggage locker in the hall.
        # War (owner 2026-10-17: "a bit more messed up", the bombed old part of the map): the waiting room's roof
        # fell in, a shell blew through the office's street wall.
        build(Building("TrainStation", 200, 190, 38, 14, colour="wall", rooms=(3, 1), doors="SN", roof=True,
                       height=3.6, blasts=[(0, "N", 2)], caved=[(0, 0)]), [("crate", 0, 0, 0, "W", -2.6, "duffel"), ("crate", 2, 0, 0, "E", 2.4, "chest"),
                                     ("locker", 1, 0, 0, "N", 4.6)])
        station_furniture(219.0, 197.0)
    with modeled("depot", 277.0, 241.0):
        # The goods shed (World art 0.17, plan worldart/station-plan.md): bombed (owner 2026-10-17: the old part of
        # the map that got bombed, "depot more messed up"): the roof fell in, shells holed both long walls and
        # knocked chunks out of their tops (those are 4.2 m up and more: no new ways in).
        build(Building("Depot", 262, 232, 30, 18, colour="wall_farm", rooms=(1, 1), doors="WE", height=7.0,
                       big_doors=True, blasts=[(0, "N", 0), (0, "S", 0)], caved=[(0, 0)], wall_openings={
                           "N": [("blast", 268.5, 3.8, 4.6, 7.0), ("blast", 277.0, 4.4, 0.0, 4.6)],
                           "S": [("blast", 277.0, 3.0, 0.0, 3.4), ("blast", 285.5, 4.6, 4.2, 7.0)]}),
              [("crate", 0, 0, 0, "N", -6), ("crate", 0, 0, 0, "S", 6)])
        depot_furniture(277.0, 241.0)
    # (the first one stood half on the old road's level crossing: moved off it, owner 2026-10-18 "more seamless")
    for x0, z0 in ((156, RY), (171, RY), (266, 220), (266, 228), (300, RY)):
        boxcar(x0 + 5.5, z0)
    add_loot("Railyard", "crate", 161.0, RY + 2.3, yaw=180.0)

    # ===================================================================== BOTTOM RIGHT: old houses, gas station
    # war damage (owner, 0.11.6): most houses down here are shot up; OldHouse6 stays whole (spawn 5's cover).
    # (owner 2026-10-17: the bottom right is the old quarter that got bombed, "a lot more war ruined": more holes,
    # more roofs in)
    # (owner 2026-10-17: nothing behind the stairs: 1's west shell hole is off the stairwell now, into the kitchen only)
    damage = {1: dict(blasts=[(0, "S", 1), (1, "E", 1)], caved=[(1, 1), (0, 1)],
                      wall_openings={"W": [("blast", 264 + 3.7, 2.1, 0.0, FLOOR_H), ("window", 264 + 7.5, WIN_W, WIN_LO, WIN_HI)]}),
              3: dict(blasts=[(0, "E", 0)], caved=[(0, 1)]),
              7: dict(blasts=[(1, "S", 0), (0, "E", 1)], caved=[(0, 1), (1, 1)]),
              8: dict(blasts=[(0, "S", 0), (0, "E", 1)], caved=[(1, 1), (0, 0)])}
    for n, (x, y) in [(1, (196, 264)), (6, (164, 276)), (7, (148, 312)), (8, (214, 316))]:
        with modeled(f"old_house_{n}", x + 6.0, y + 5.0):     # (World art 0.17: the old quarter's houses)
            build(Building(f"OldHouse{n}", x, y, 12, 10, floors=1 + (n % 2), rooms=(2, 2), doors="N" if n % 3 else "W",
                           walled_stairs=bool(n % 2), **damage.get(n, {})),
                  [("crate", 0, 1, 0, "W", -1.0 if n == 6 else 0)] + ([("locker", 1, 0, 1, "E", 0)] if n % 2 else []))
            # (6's dresser slides off its west door to the room's north end: the shoe bench is at the south end)
            old_house_furniture(n, x + 6.0, y + 5.0)
    with modeled("signal_box", 322.0, 243.0):
        # The signal box (World art 0.17, owner 2026-10-17: what should the house beside the depot be): OldHouse3
        # becomes Bloxov Junction's signal box, same size, rooms and loot (the place name stays, so the loot does).
        # The lever room upstairs looks north over the line, reached by an outside stair up the south wall; the
        # locking room and the lamp room downstairs. Shot up: the lever room's roof is half gone (south-west), a shell
        # through its north wall, another through the locking room's east wall.
        build(Building("OldHouse3", 316, 238, 12, 10, floors=2, rooms=(2, 2), doors="W", open_plan=True, stairs=False,
                       blasts=[(0, "E", 0), (1, "N", 1)], caved=[(0, 1)], wall_openings={
                           "S": [], ("S", 1): [("door", 323.65, DOOR_W, 0.0, DOOR_H), ("window", 318.5, WIN_W, WIN_LO, WIN_HI)]}),
              [("crate", 0, 1, 0, "W", -2.0, "toolbox"), ("locker", 1, 0, 1, "E", 0, "locker")])
        signal_box_furniture(322.0, 243.0)
    with modeled("gas_station", 312.0, 327.0):
        # The old gas station (World art 0.17): the shop west, the service bay east, the pumps under the canopy on
        # the south forecourt. A shop door and windows on the highway side too (owner rule: entrances face the
        # street). Bombed: the bay's roof gone, shells through the bay's front and east wall and the shop's back,
        # half the canopy down on the pumps.
        build(Building("GasStation", 298, 320, 28, 14, colour="wall_fuel", rooms=(2, 1), doors="S",
                       blasts=[(0, "E", 0)], caved=[(1, 0)], wall_openings={
                           "N": [("window", 300.6, WIN_W, WIN_LO, WIN_HI), ("window", 303.4, WIN_W, WIN_LO, WIN_HI),
                                 ("door", 307.0, DOOR_W, 0.0, DOOR_H), ("window", 310.0, WIN_W, WIN_LO, WIN_HI),
                                 ("blast", 319.5, 3.6, 0.0, FLOOR_H)],
                           "S": [("blast", 301.6, 3.0, 0.0, FLOOR_H), ("door", 306.0, DOOR_W, 0.0, DOOR_H),
                                 ("window", 309.6, WIN_W, WIN_LO, WIN_HI), ("door", 318.5, 4.0, 0.0, 2.8),
                                 ("window", 323.6, WIN_W, WIN_LO, WIN_HI)]}),
              [("crate", 0, 0, 0, "W", 0), ("locker", 1, 0, 0, "E", 4.0)])
        gas_station_furniture(312.0, 327.0)
    with modeled("diner", 284.0, 326.0):
        # The diner (World art 0.17): the dining room west (counter, booths, the washroom), the kitchen east. Its
        # front door faces the highway (owner rule: entrances face the street; the side door stays). Bombed: the
        # dining room's roof fell in, shells through the kitchen's front and the dining room's back.
        build(Building("Diner", 276, 320, 16, 12, colour="wall_food", rooms=(2, 1), doors="W",
                       blasts=[(0, "N", 1), (0, "S", 0)], caved=[(0, 0)], wall_openings={
                           "N": [("window", 277.6, WIN_W, WIN_LO, WIN_HI), ("door", 280.8, DOOR_W, 0.0, DOOR_H),
                                 ("window", 282.9, WIN_W, WIN_LO, WIN_HI), ("blast", 288.0, 3.4, 0.0, FLOOR_H)]}),
              [("crate", 1, 0, 0, "E", 0)])
        diner_furniture(284.0, 326.0)
    with modeled("garage", 339.0, 329.0):
        # The garage (World art 0.17): a repair shop, its big door now on the highway (owner rule: entrances face the
        # street; the old west doorway stays as a side door). Bombed: the whole roof is gone, shells through the
        # east and south walls.
        build(Building("Garage", 332, 322, 14, 14, rooms=(1, 1), doors="N", height=4.5, big_doors=True,
                       blasts=[(0, "E", 0), (0, "S", 0)], caved=[(0, 0)], wall_openings={
                           "W": [("door", 327.0, DOOR_W, 0.0, DOOR_H), ("window", 332.6, WIN_W, WIN_LO, WIN_HI)]}),
              [("crate", 0, 0, 0, "E", 4.6)])
        garage_furniture(339.0, 329.0)
    car(286, 300, 70, "rust"); car(244, 268, 40, "rust")              # (burnt out)

    # junkyard north of the gas station (owner, 0.10.1): a fenced yard of stacked wrecks that makes a maze, a crane,
    # a crusher and the office
    jx0, jz0, jx1, jz1 = 298.0, 262.0, 346.0, 294.0
    areas.append(("Junkyard", jx0, jz0, jx1, jz1))
    with modeled("junk_office", 305.5, 268.5):
        # The junkyard office (World art 0.17): the yard man's hut, its door on the yard. Bombed: the roof's gone,
        # a shell through the east wall.
        build(Building("JunkOffice", 300.5, 264.5, 10, 8, colour="wall", rooms=(1, 1), doors="S", blasts=[(0, "E", 0)],
                       caved=[(0, 0)]), [("crate", 0, 0, 0, "N", 0)])
        junk_office_furniture(305.5, 268.5)
    with modeled("junkyard", 322.0, 278.0):
        # (World art 0.17: the fence, the wrecks, the crane and the crusher are the junkyard's model.)
        wall_x(jx0, jx1, jz0, 0.0, 2.4, "rust", [(320.0, 4.0, 0.0, 2.4)], t=0.2, kind="jy_fence")
        wall_x(jx0, jx1, jz1, 0.0, 2.4, "rust", [(330.5, 5.0, 0.0, 2.4)], t=0.2, kind="jy_fence")
        wall_z(jz0, jz1, jx0, 0.0, 2.4, "rust", [(278.5, 5.0, 0.0, 2.4)], t=0.2, kind="jy_fence")
        wall_z(jz0, jz1, jx1, 0.0, 2.4, "rust", t=0.2, kind="jy_fence")
        for z, xs in ((270, (316, 321, 326, 336, 341)), (278, (310, 315, 330, 335, 340)), (286, (304, 309, 320, 325, 338))):
            for x in xs:
                car_stack(x, z, 90, rng.randint(1, 3), rng, kind="jy_car")
        box(341.2, 0, 265.2, 342.8, 12.0, 266.8, "metal", kind="jy_crane")          # crane tower and its boom
        box(326, 11.4, 265.6, 343, 12.0, 266.4, "metal", solid=False, kind="jy_boom")
        box(304, 0, 290, 312, 3.0, 293.5, "concrete", kind="jy_crusher")             # crusher
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
    checkpoint_frame.append((263.0, 285.0, ux, uz, nx_, nz_, yaw_r))
    for s_, t_ in ((-6, -2.0), (6, 2.0)):
        barrier(*at(s_, t_), yaw_r + 90)
    for t_ in (-7.5, 7.5):
        sandbags(*at(0, t_), yaw_r)
        sandbags(*at(-2.3, t_ * 0.85), yaw_r + 90, 2.4)
        sandbags(*at(2.3, t_ * 0.85), yaw_r + 90, 2.4)
    bx_, bz_ = at(-4, -10.5)
    guard_booth(bx_, bz_, math.degrees(math.atan2(-uz, ux)))   # guard booth (a cube: turned so its door faces the road)
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
        camp_tent(tx, tz, yaw)
    fire_pit(x, z + 2)
    log_seat(x - 2.6, z + 2.0); log_seat(x + 2.6, z + 2.0)
    add_loot("Campsite", "crate", x + 0.5, z - 5.5, yaw=180.0)
    # hunting stands (owner, 0.10.1): a platform 3.5 m up with a ramp, one watching the Creek Trail extract
    for sx, sz in stands:
        stand_spots.append((sx, sz))
        hunting_stand(sx, sz)
    for n, (x, y) in enumerate(CABINS, start=1):
        if n == 3:
            # The hunter's cabin in the east woods (World art 0.17, owner 2026-10-17): a log cabin with a porch,
            # main room (stove, kitchen corner, table) east, bunk room + washroom west. Same spot, size and duffel.
            with modeled("cabin_east", x + 6.5, y + 5.0):
                cab = Building(f"Cabin{n}", x, y, 13, 10, colour="wood", rooms=(2, 1), doors="S")
                cab.holes[1] = (x + 6.5 + CAB_HATCH[0], y + 5.0 + CAB_HATCH[1], x + 6.5 + CAB_HATCH[2], y + 5.0 + CAB_HATCH[3])
                build(cab, [("crate", 1, 0, 0, "E", 1.7)])
                cabin_furniture(x + 6.5, y + 5.0)
                cabin_loft(x + 6.5, y + 5.0)
            continue
        if n == 1:
            # (owner 2026-10-18: "flip the first cabin": its porch faces north, toward the campsite and the map, not
            # into the corner)
            with modeled("cabin_fisher", x + 6.5, y + 5.0, turned=True):
                fisher_cabin(x, y)
            continue
        if n == 2:
            # (owner 2026-10-18: "make the second cabin face the river": turned so its front looks east at the creek)
            with modeled("cabin_trapper", x + 6.5, y + 5.0, turned=90):
                trapper_cabin(x, y)
            continue
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
            (106, 104), (60, 100), (140, 90), (26, 110), (90, 25), (163, 145), (30, 172), (100, 168),
            (220, 42), (270, 50), (320, 45), (300, 110), (220, 196), (190, 225), (282, 236.5), (230, 290),
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
    cover_pass()
    planned_cover()
    ruin_pass()
    apply_late_turns()
    shops_frontage()
    for g in MOTEL_GHOSTS:
        footprints.remove(g)
    clear_scatter(MOTEL_CLEAR)
    town_hall_back()
    motel()
    station_square()
    churchyard()
    door_paths()
    derailed_train()
    signals_and_points()
    waterfall()
    creek_mouth()
    creek_banks()
    extract_camps()
    zone_spawns()
    clear_sidings()   # (after the AI's spawn spots are picked: they stay where they were)
    set_pieces_late()
    lamp_pass()
    sign_pass()
    bush_pass()
    street_details()
    map_labels()
    check_roads()
    settle_fallen_doors()
    fit_trucks()
    fit_car_unders()
    solid_late()
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
    ("RoadHouses", 222, 47, 20, 1, 0, 0.0),   # the motel on the road between the church and the farm (was two houses)
    ("Church", 180, 42, 25, 1, 0, 0.0),
    ("Woods", 75, 290, 40, 3, 0, 0.0),        # cabins, campsite, hunting stand
    ("OldHouses", 200, 300, 30, 2, 0, 1.0),   # old houses south of the railway
    ("TownHall", 107, 155, 20, 0, 0, 0.0),    # the boss's zone: the town hall and its bunker (boss + guards only)
]
# Parts of a zone its AI keep out of (spawns and patrols), and how far out its open-ground patrol stops sit
# (fraction of the radius). Town (0.12.31, owner): Bon's guards hold the town hall and Raiders the bank, so the
# town's scavs spawn and patrol away from both, more round the edges of town.
AI_ZONE_AVOID = {"Town": [(107, 155, 30), (150, 124, 32)]}
AI_ZONE_EDGE = {"Town": 0.45}
# The boss (owner: a Raider commander with guards, at the town hall + bunker, in every raid while testing; a chance
# later): zone, guards, chance per raid.
AI_BOSS = ("TownHall", 3, 1.0)
# Where the boss and guards start (owner, 0.12.18: inside the town hall, then out on patrol): ground-floor room
# centres of the hall (rooms 12.5 x 9 m), one picked per raid.
BOSS_STARTS = [(100.75, 159.5), (113.25, 150.5), (113.25, 159.5), (125.75, 159.5)]
AI_ROAMERS = 3
# Sniper perches (Scavs 2.0, owner): high spots with a view, a sniper stays on one. 2 of them are used each raid
# (preferring ones that don't already see a player). (name, x, z, height above the ground, which way it watches)
SNIPER_PERCHES = [
    ("PerchPolice", 152.5, 123.0, 6.0, "W"),       # police roof, over the town core and square
    ("PerchBellTower", 150.5, 30.5, 6.0, "S"),     # the bell tower, over the north of town
    ("PerchSchool", 35.5, 52.5, 6.0, "E"),        # school roof, over the west of town
    ("PerchStation", 230.0, 196.0, 3.6, "S"),      # train station office roof (the waiting room roof is caved), over the railway and the middle field
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
        if any(math.hypot(x - ax, z - az) <= ar for ax, az, ar in AI_ZONE_AVOID.get(zone[0], [])):
            continue
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
    # building matters). Since 0.20.14 (owner: AI spawn inside buildings and patrol around; picked "indoor guards"):
    # one spot in every roofed ground-floor room of every building, found from the boxes as they now stand
    # (`building_rooms`), so the modelled buildings' own rooms count. The spawner starts about 2 in 3 of a zone's AI at
    # one, and those AI patrol their building's rooms (markers carry `building`). (Only markers: nothing moves.)
    for b in buildings:
        if b.name in NO_INDOOR_SPAWNS:
            continue
        rooms = []
        for cx, cz in building_rooms(b):
            zone = _zone_of(cx, cz)
            if zone is None or zone[0] == AI_BOSS[0] or (zone[4] + zone[5]) == 0 or behind_key_door(b.name, cx, cz):
                continue
            rooms.append((round(cx, 1), round(cz, 1), zone[0]))
        for x, z, zname in rooms:
            indoor_spawns.append((f"Indoor{len(indoor_spawns) + 1}", x, z, zname, b.name))


ROOM_CELL = 0.25      # grid step of the room search (m)
ROOM_CORE = 5         # cells (1.25 m) clear of anything solid at body height: a room's open middle; doorways are narrower
ROOM_MIN_CORE = 8     # open-middle cells a room needs: smaller is a nook or a corridor end
ROOM_SPLIT = 600      # a hall with this many open-middle cells (~37 m2) or more gets another spot, and so on


def building_rooms(b):
    """The ground-floor rooms of building b as they now stand (its own walls or its model's boxes, turned if it was):
    [(x, z)] map points, the most open spot of each (big halls get more, spread out). A room's open middle is the
    floor inside the footprint at least ROOM_CORE from anything solid at body height, so the narrow doorways split
    the rooms apart (wide openings join them)."""
    xs, zs = [b.x0, b.x1], [b.z0, b.z1]
    if getattr(b, "turned_about", None):
        corners = [turn_point(x, z, *b.turned_about) for x in xs for z in zs]
        xs, zs = [c[0] for c in corners], [c[1] for c in corners]
    pad = int(1.5 / ROOM_CELL)   # (cells round the footprint: the way in from outside)
    x0, z0 = min(xs) - pad * ROOM_CELL, min(zs) - pad * ROOM_CELL
    nx, nz = int((max(xs) - min(xs)) / ROOM_CELL) + 2 * pad, int((max(zs) - min(zs)) / ROOM_CELL) + 2 * pad
    solid = [[False] * nx for _ in range(nz)]
    for bx in boxes:
        if bx[9] == 0:
            continue
        cx, cz = bx[0] + M / 2, bx[2] + M / 2
        sx, sy, sz, yaw, pitch = bx[3], bx[4], bx[5], bx[6], bx[7]
        half_y = sy / 2 + abs(math.sin(math.radians(pitch))) * sz / 2
        if bx[1] - half_y > 1.8 or bx[1] + half_y < 0.25:
            continue   # (not at body height: a floor, a roof, a shelf up high)
        r = math.hypot(sx, sz) / 2 + ROOM_CELL
        if cx + r < x0 or cz + r < z0 or cx - r > x0 + nx * ROOM_CELL or cz - r > z0 + nz * ROOM_CELL:
            continue
        c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        # (half a cell bigger, so a thin wall between two cell middles still blocks)
        hx, hz = sx / 2 + ROOM_CELL / 2, sz / 2 + ROOM_CELL / 2
        for j in range(max(0, int((cz - r - z0) / ROOM_CELL)), min(nz, int((cz + r - z0) / ROOM_CELL) + 1)):
            pz = z0 + (j + 0.5) * ROOM_CELL - cz
            for i in range(max(0, int((cx - r - x0) / ROOM_CELL)), min(nx, int((cx + r - x0) / ROOM_CELL) + 1)):
                px = x0 + (i + 0.5) * ROOM_CELL - cx
                if abs(px * c - pz * s_) <= hx and abs(px * s_ + pz * c) <= hz:
                    solid[j][i] = True
    for _, _, lx, ly, lz, _, _, _ in loot:   # (containers and searchable props stand in the way too: not boxes)
        if ly < 1.5:
            for j in range(max(0, int((lz - 0.9 - z0) / ROOM_CELL)), min(nz, int((lz + 0.9 - z0) / ROOM_CELL) + 1)):
                for i in range(max(0, int((lx - 0.9 - x0) / ROOM_CELL)), min(nx, int((lx + 0.9 - x0) / ROOM_CELL) + 1)):
                    solid[j][i] = True

    def distances(blocked):   # how far each open cell is from a blocked one (in cells, 8-way)
        far = [[0 if blocked[j][i] else 10 ** 6 for i in range(nx)] for j in range(nz)]
        queue = collections.deque((i, j) for j in range(nz) for i in range(nx) if blocked[j][i])
        while queue:
            i, j = queue.popleft()
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                a, c2 = i + di, j + dj
                if 0 <= a < nx and 0 <= c2 < nz and far[c2][a] > far[j][i] + 1:
                    far[c2][a] = far[j][i] + 1
                    queue.append((a, c2))
        return far

    def flood(start, ok):   # the cells joined (4-way) to `start` through cells where ok(i, j)
        cells, queue, seen_ = [], collections.deque([start]), {start}
        while queue:
            a, c2 = queue.popleft()
            cells.append((a, c2))
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (a + di, c2 + dj)
                if 0 <= p[0] < nx and 0 <= p[1] < nz and p not in seen_ and ok(*p):
                    seen_.add(p)
                    queue.append(p)
        return cells

    # Where someone can walk in from outside (room for a body through the doorways): a room it doesn't reach is shut.
    walk = distances(solid)
    reach = set()
    for j in range(nz):
        for i in range(nx):
            if (i in (0, nx - 1) or j in (0, nz - 1)) and walk[j][i] >= 4 and (i, j) not in reach:
                reach.update(flood((i, j), lambda a, c2: walk[c2][a] >= 4))
    # The rooms: the footprint's edge counts as solid (holes in the outside walls don't let a room out).
    inside = [[solid[j][i] or not (pad <= i < nx - pad and pad <= j < nz - pad) for i in range(nx)] for j in range(nz)]
    far = distances(inside)
    seen = set()
    rooms = []
    for j in range(nz):
        for i in range(nx):
            if far[j][i] < ROOM_CORE or (i, j) in seen:
                continue
            cells = flood((i, j), lambda a, c2: far[c2][a] >= ROOM_CORE)
            seen.update(cells)
            if len(cells) < ROOM_MIN_CORE:
                continue
            mid_i, mid_j = sum(p[0] for p in cells) / len(cells), sum(p[1] for p in cells) / len(cells)
            picks = [max(cells, key=lambda p: (far[p[1]][p[0]], -abs(p[0] - mid_i) - abs(p[1] - mid_j)))]
            if picks[0] not in reach:
                continue
            while len(picks) < 1 + len(cells) // ROOM_SPLIT:   # (the next one as far as it gets from the others)
                picks.append(max(cells, key=lambda p: min((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 for q in picks)))
            rooms += [(x0 + (a + 0.5) * ROOM_CELL, z0 + (c2 + 0.5) * ROOM_CELL) for a, c2 in picks]
    return rooms


def spawner_meta(ter):
    """The map's AI numbers and zones (EnemySpawner settings)."""
    def extra(n):
        avoid = AI_ZONE_AVOID.get(n)
        out = ""
        if avoid:
            out += ', "avoid": [' + ", ".join(f"Vector3({fmt(gx(ax))}, {fmt(ar)}, {fmt(gz(az))})" for ax, az, ar in avoid) + "]"
        if n in AI_ZONE_EDGE:
            out += f', "edge": {fmt(AI_ZONE_EDGE[n])}'
        return out
    zones = ", ".join(
        f'{{"name": "{n}", "center": Vector3({fmt(gx(x))}, {fmt(ter.lift(x, z))}, {fmt(gz(z))}), "radius": {fmt(r)}, '
        f'"scavs": {s}, "raiders": {rd}, "trickle": {fmt(t)}{extra(n)}}}' for n, x, z, r, s, rd, t in AI_ZONES)
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
MAP_NAME_SIDE = {"GunStore": "above", "Shops": "above", "Pharmacy": "below", "Diner": "above", "GasStation": "below", "Garage": "above"}


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
                  CAR_PARK, (15, 148, 45, 166)])   # (CAR_PARK: the grocery and church car park, churchyard)


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


def car_xform(c, b, lift, tilt=(0.0, 0.0)):
    """Where a car's model goes: under its body box (b, after any turn), on the ground the group was lifted to,
    tilted to the ground's slope (tilt: its rise per metre east and south, see fit_car)."""
    yaw = b[6]
    if yaw == 0.0 and b[3] > b[5] and not c["roll"]:   # (an unturned box turned a quarter: its sides swapped)
        yaw = 90.0
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    x, z = b[0], b[2]
    if c["roll"]:      # Ry(yaw) * Rz(roll): the body box sits off the model's middle by its height / 2 (along -x)
        r = math.radians(c["roll"])
        cr, sr = math.cos(r), math.sin(r)
        off = b[3] / 2             # (the box's x size is the car's height on its side)
        x, z = x + off * cy, z - off * sy
        y = lift + b[4] / 2        # (the car's half width: its side on the ground)
        rows = ((cy * cr, -cy * sr, sy), (sr, cr, 0.0), (-sy * cr, sy * sr, cy))
    else:
        y = lift
        rows = ((cy, 0.0, sy), (0.0, 1.0, 0.0), (-sy, 0.0, cy))
    if tilt != (0.0, 0.0):   # turn the car's up onto the ground's normal (about the axis between them)
        nx, ny, nz = -tilt[0], 1.0, -tilt[1]
        nl = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / nl, ny / nl, nz / nl
        kx, kz = nz, -nx
        kl = math.hypot(kx, kz)
        if kl > 1e-6:
            kx, kz = kx / kl, kz / kl
            ca, sa = ny, kl
            t = 1 - ca
            rt = ((ca + kx * kx * t, -kz * sa, kx * kz * t), (kz * sa, ca, -kx * sa), (kz * kx * t, kx * sa, ca + kz * kz * t))
            rows = tuple(tuple(sum(rt[i][k] * rows[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    return ("Transform3D(" + ", ".join(fmt(v) for row in rows for v in row) + f", {fmt(gx(x + M / 2))}, {fmt(y)}, "
            f"{fmt(gz(z + M / 2))})")


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


def behind_key_door(place, x, z):
    """Loot behind a key door (the bunker, the bank vault: the bank's south-east room): the AI leave it alone."""
    return place == "Bunker" or (place == "Bank" and 136 < x < 144 and 130 < z < 140)


# The ground's splat map (World art 0.17, outdoor step 2): what the ground shader (assets/shaders/ground.gdshader)
# draws where, SPLAT_PX pixels per metre over the map: R worn earth (paths), G mud (the creek's banks), B scorched
# earth (craters, burnt wrecks, the bombed quarter), A gravel (road shoulders, the railway's ballast, round buildings,
# yards and car parks). Soft values: the shader cuts them at 0.5 with a pixel dither.
# The roads' look (outdoor step 3; assets/materials/road_<look>.tres): b worn asphalt, white lines; c dark asphalt,
# yellow middle lines; d concrete slabs.
ROAD_LOOK = os.environ.get("BLOXOV_ROAD_LOOK", "c")   # (owner 2026-10-18 picked C)
SPLAT_PX = 2
SPLAT_PNG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures", "ground", "splat.png")
GRASS_MASK_PNG = os.path.join(os.path.dirname(SPLAT_PNG), "grass_mask.png")
paths = []        # (points, width) of footpaths (worn earth)


def _png(path, w, h, rows):
    import struct
    import zlib

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_splat(ter):
    n = int(M * SPLAT_PX)
    chan = [[[0.0] * n for _ in range(n)] for _ in range(4)]

    def stamp(c, x0, z0, x1, z1, value):
        """value(x, z) -> 0..1 over the map rect (max with what's there)."""
        for j in range(max(0, int(z0 * SPLAT_PX)), min(n, int(z1 * SPLAT_PX) + 1)):
            z = (j + 0.5) / SPLAT_PX
            row = chan[c][j]
            for i in range(max(0, int(x0 * SPLAT_PX)), min(n, int(x1 * SPLAT_PX) + 1)):
                v = value((i + 0.5) / SPLAT_PX, z)
                if v > row[i]:
                    row[i] = v

    def seg_d(x, z, a, b):
        ax, az = a
        dx, dz = b[0] - ax, b[1] - az
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / ((dx * dx + dz * dz) or 1)))
        return math.hypot(x - ax - t * dx, z - az - t * dz)

    def lines(c, polylines, inner, outer):
        for points, width in polylines:
            for a, b in zip(points, points[1:]):
                r = width / 2 + outer
                def v(x, z, a=a, b=b, width=width):
                    d = seg_d(x, z, a, b) - width / 2
                    return max(0.0, min(1.0, (outer - d) / max(outer - inner, 0.01)))
                stamp(c, min(a[0], b[0]) - r, min(a[1], b[1]) - r, max(a[0], b[0]) + r, max(a[1], b[1]) + r, v)
    lines(0, paths, 0.0, 0.5)                                 # footpaths
    lines(1, water, 0.6, 2.2)                                  # mud along the creek
    lines(3, roads, 0.5, 1.3)                                  # road shoulders (under the road too: it hides it)
    stamp(3, 0, RAIL_Z - 3.2, M, RAIL_Z + 3.2, lambda x, z: max(0.0, min(1.0, (3.2 - abs(z - RAIL_Z)) / 0.8)))
    small_yards = [y for y in yards if (y[2] - y[0]) * (y[3] - y[1]) < 1500]   # (not round the farm's fields)
    for x0, z0, x1, z1 in [f[1:] for f in footprints] + small_yards:   # round buildings, yards and car parks
        stamp(3, x0 - 1.5, z0 - 1.5, x1 + 1.5, z1 + 1.5,
              lambda x, z, r=(x0, z0, x1, z1): max(0.0, min(1.0, (1.4 - max(r[0] - x, x - r[2], r[1] - z, z - r[3], 0.0)) / 0.9)))
    def blot(x, z, r, soft, seed):   # a ragged round patch
        ph = random.Random(seed)
        p1, p2 = ph.uniform(0, 6.3), ph.uniform(0, 6.3)

        def v(px, pz):
            a = math.atan2(pz - z, px - x)
            re = r * (1 + 0.22 * math.sin(3 * a + p1) + 0.12 * math.sin(7 * a + p2))
            return max(0.0, min(1.0, 0.5 + (re - math.hypot(px - x, pz - z)) / soft))
        return v
    for x, z, r in craters:                                    # scorched round shell holes
        stamp(2, x - r - 4, z - r - 4, x + r + 4, z + r + 4, blot(x, z, r + 1.4, 2.0, f"crater {x} {z}"))
    for c in cars:                                             # under burnt-out wrecks
        if c["glb"].endswith("burnt") or "rust" in c["glb"]:
            x, z = c["at"]
            stamp(2, x - 6, z - 6, x + 6, z + 6, blot(x, z, 3.2, 1.5, f"wreck {x} {z}"))
    for x0, z0, x1, z1 in camp_rects:                          # trodden gravel round the extract camps
        cx, cz, rx, rz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2 - 1.5, (z1 - z0) / 2 - 1.5
        stamp(3, x0, z0, x1, z1, lambda x, z, cx=cx, cz=cz, rx=rx, rz=rz:
              max(0.0, min(1.0, (1.0 - math.hypot((x - cx) / rx, (z - cz) / rz)) * 3.0 + 0.5)))
    for name, x0, z0, x1, z1 in areas:                         # the junkyard (owner 2026-10-18: junkyard ground)
        if name != "Junkyard":
            continue
        # packed gravel over the whole yard, worn dirt tracks down the lanes between the stacks and through the
        # gates, bare dirt patches, and dark oil stains (the scorch texture) where the wrecks drip
        stamp(3, x0 - 1.5, z0 - 1.5, x1 + 1.5, z1 + 1.5,
              lambda x, z, r=(x0, z0, x1, z1): max(0.0, min(1.0, (1.4 - max(r[0] - x, x - r[2], r[1] - z, z - r[3], 0.0)) / 0.9)))
        ph = random.Random("junkyard ground")
        tracks = [([(x0 + 1, 274.0), ((x0 + x1) / 2, 274.7), (x1 - 1, 274.2)], 2.6),
                  ([(x0 + 1, 282.0), ((x0 + x1) / 2, 281.4), (x1 - 1, 282.3)], 2.6),
                  ([(320.0, z0), (320.5, 274.0)], 2.4), ([(330.5, z1), (330.0, 282.0)], 2.4),
                  ([(x0, 278.5), (x0 + 6, 278.0), (x0 + 6, 282.0)], 2.2)]
        lines(0, tracks, 0.2, 0.9)
        for k in range(24):
            bx_, bz_ = ph.uniform(x0 + 2, x1 - 2), ph.uniform(z0 + 2, z1 - 2)
            br = ph.uniform(0.8, 2.4)
            stamp(0, bx_ - br - 3, bz_ - br - 3, bx_ + br + 3, bz_ + br + 3, blot(bx_, bz_, br, 1.5, f"junk dirt {k}"))
        for k in range(40):
            bx_, bz_ = ph.uniform(x0 + 1.5, x1 - 1.5), ph.uniform(z0 + 1.5, z1 - 1.5)
            br = ph.uniform(0.5, 1.4)
            stamp(2, bx_ - br - 2, bz_ - br - 2, bx_ + br + 2, bz_ + br + 2, blot(bx_, bz_, br, 0.8, f"junk oil {k}"))
    rng = random.Random(2018)                                  # blast patches over the bombed quarter
    blasts = [(rng.uniform(a[0], a[2]), rng.uniform(a[1], a[3]), rng.uniform(3, 6)) for a in RUIN_AREAS for _ in range(8)]
    for x, z, r in blasts:
        stamp(2, x - r * 1.5, z - r * 1.5, x + r * 1.5, z + r * 1.5, blot(x, z, r, 2.5, f"blast {x} {z}"))
    rows = []
    for j in range(n):
        row = bytearray()
        for i in range(n):
            row += bytes(int(round(chan[c][j][i] * 255)) for c in range(4))
        rows.append(row)
    os.makedirs(os.path.dirname(SPLAT_PNG), exist_ok=True)
    _png(SPLAT_PNG, n, n, rows)
    # Where grass tufts may grow (scripts/grass_tufts.gd): not under anything standing on the ground (floors, roads,
    # yards, debris, walls...), so none poke through. (The tufts skip paths, mud, gravel and scorch by the splat map.)
    free = [[255] * n for _ in range(n)]
    for bx in boxes:
        if bx[9] == 0 and bx[4] > 0.5:   # (tree tops, signs: looks-only and off the ground)
            continue
        if len(bx) > 10 and debris[bx[10]]["kind"] == "farmland":   # (the farm's yard is grass: only its field isn't)
            continue
        x, z = bx[0] + M / 2, bx[2] + M / 2
        if bx[1] - bx[4] / 2 > ter.at(x, z) + 0.4:
            continue
        cs = _fp_corners(bx, 0.25)
        x0, x1 = min(p[0] for p in cs) + M / 2, max(p[0] for p in cs) + M / 2
        z0, z1 = min(p[1] for p in cs) + M / 2, max(p[1] for p in cs) + M / 2
        c, s_ = math.cos(math.radians(bx[6])), math.sin(math.radians(bx[6]))
        hx, hz = bx[3] / 2 + 0.25, bx[5] / 2 + 0.25
        for j in range(max(0, int(z0 * SPLAT_PX)), min(n, int(z1 * SPLAT_PX) + 1)):
            pz = (j + 0.5) / SPLAT_PX - z
            for i in range(max(0, int(x0 * SPLAT_PX)), min(n, int(x1 * SPLAT_PX) + 1)):
                px = (i + 0.5) / SPLAT_PX - x
                if abs(px * c - pz * s_) <= hx and abs(px * s_ + pz * c) <= hz:
                    free[j][i] = 0
    x0, z0, x1, z1 = FARM_FIELD
    for j in range(int(z0 * SPLAT_PX), int(z1 * SPLAT_PX) + 1):
        for i in range(int(x0 * SPLAT_PX), int(x1 * SPLAT_PX) + 1):
            free[j][i] = 0
    _png(GRASS_MASK_PNG, n, n, [bytearray(v for g in row for v in (g, g, g, 255)) for row in free])


ARMY_KINDS = ("sandbags", "tanktrap", "barrier")


bush_data = []    # (x, bottom y, z, size x, y, z, yaw, look, airy) in Godot space, for scripts/bushes.gd
tree_data = []    # (x, ground y, z, trunk height, canopy width, kind, yaw) in Godot space, for scripts/trees.gd
TREE_LOOK = 1     # (scripts/trees.gd look: owner 2026-10-18 picked B, leaf clumps)


def tree_kind(x, z):
    """0 broadleaf, 1 pine, 2 birch (outdoor step 7): pines in the woods with a few birches, broadleaf trees in town
    and on the farm with some birch, a mix out in the country."""
    roll = random.Random(f"tree kind {x:.2f} {z:.2f}").random()
    if any(r >= 7 and math.hypot(x - cx, z - cz) < r + 3 for cx, cz, r in woods):
        return 1 if roll < 0.68 else 2 if roll < 0.88 else 0
    if TOWN[0] <= x <= TOWN[2] and TOWN[1] <= z <= TOWN[3]:
        return 0 if roll < 0.78 else 2
    return 0 if roll < 0.55 else 2 if roll < 0.8 else 1


# The map's edge (outdoor step 9, owner 2026-10-18: "change that big grey box around the map into something different"):
# the edge stays a wall nobody gets over, but it's only collision now (hidden), and what you see there is a border:
# the land goes on outside (rolling hills climbing away into forest, so there's no edge to the world), a fence along
# the line, tree lines behind it, and the roads and the railway running out through closed crossings. Drawn by
# art_source/scripts/make_outdoor.py (border()) into assets/models/outdoor/outdoor_border.glb from
# art_source/outdoor/border.json; the trees outside are scripts/trees.gd's (looks only, no boxes: nobody gets there).
BORDER_LOOK = os.environ.get("BLOXOV_BORDER", "b")   # b border fence, c rock bank, d army line (hesco + wire)
BORDER_RINGS = (0.0, 2.5, 6.0, 11.0, 18.0, 28.0, 42.0, 62.0, 90.0, 130.0, 185.0, 260.0, 380.0, 560.0)   # m out
BORDER_GLB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "outdoor",
                          "outdoor_border.glb")


def _vnoise(x, z, size, seed):
    """Smooth value noise in 0..1 (cells `size` m)."""
    u, v = x / size, z / size
    i, j = math.floor(u), math.floor(v)
    fu, fv = u - i, v - j
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)

    def r(a, b):
        return random.Random(f"border {seed} {a} {b}").random()
    return (r(i, j) * (1 - fu) + r(i + 1, j) * fu) * (1 - fv) + (r(i, j + 1) * (1 - fu) + r(i + 1, j + 1) * fu) * fv


def border_ways(ter):
    """Where roads and the railway leave the map: (edge x, edge z, out x, out z, width, height, "road"|"rail")."""
    out = []
    for curve, w in roads:
        for a, b in ((curve[0], curve[1]), (curve[-1], curve[-2])):
            x, z = a
            for ex, ez, nx, nz in ((0.0, None, -1, 0), (M, None, 1, 0), (None, 0.0, 0, -1), (None, M, 0, 1)):
                if (ex is not None and abs(x - ex) < 4) or (ez is not None and abs(z - ez) < 4):
                    px, pz = (ex, z) if ex is not None else (x, ez)
                    out.append((px, pz, nx, nz, w, ter.at(px, pz), "road"))
    for ex, nx in ((0.0, -1), (M, 1)):
        out.append((ex, RAIL_Z, nx, 0, 5.0, ter.at(ex, RAIL_Z), "rail"))
    return out


def outside_h(ter, ways, x, z):
    """The land's height outside the map (the edge's own height at the line, then hills climbing away)."""
    px, pz = min(max(x, 0.0), M), min(max(z, 0.0), M)
    d = math.hypot(x - px, z - pz)
    e = ter.at(px, pz)
    n = _vnoise(x, z, 70.0, 1) * 0.65 + _vnoise(x, z, 26.0, 2) * 0.35
    rise = _smoothstep(6.0, 150.0, d)
    h = e + rise * (8.0 + 26.0 * n) + (_vnoise(x, z, 11.0, 3) - 0.5) * 2.2 * _smoothstep(4.0, 24.0, d)
    if BORDER_LOOK == "c":   # (a rock bank: the land climbs steeply straight from the line)
        h += 5.5 * _smoothstep(0.0, 7.0, d)
    if x < 0 and 211.0 < z < 236.0:   # (behind the waterfall's cliff: the land is up at its top)
        w = min(_smoothstep(211.0, 215.0, z), 1.0 - _smoothstep(232.0, 236.0, z))
        h = max(h, e + w * (CAVE_LIP + 3.0 - e) * _smoothstep(-1.0, 3.0, d) + rise * 6.0)
    if z > M and 84.0 < x < 119.0:    # (over the culvert: an embankment at its coping)
        top = ter.water_level(*CULVERT_AT) + 3.25
        w = min(_smoothstep(84.0, 90.0, x), 1.0 - _smoothstep(113.0, 119.0, x))
        h = max(h, e + w * (top - e) * _smoothstep(-1.0, 2.0, d))
    for ox, oz, nx, nz, w, y0, k in ways:   # (roads and the railway run out level, in a cutting through the hills)
        along = (x - ox) * nx + (z - oz) * nz
        across = abs((x - ox) * nz - (z - oz) * nx)
        if along > 0.0:   # (at the line itself the land is the edge's own height: no seam with the ground)
            m = (1.0 - _smoothstep(w / 2 + 2.0, w / 2 + 14.0 + along * 0.08, across)) * _smoothstep(0.0, 2.5, along)
            h = h * (1 - m) + (y0 + (0.02 if k == "road" else 0.0) * along) * m
    return h


def write_border(ter):
    """art_source/outdoor/border.json (the land outside, the line, the ways out) and the trees outside."""
    ways = border_ways(ter)
    out = [-r for r in reversed(BORDER_RINGS[1:])]
    xs = out + list(ter.xs) + [M + r for r in BORDER_RINGS[1:]]
    zs = out + list(ter.zs) + [M + r for r in BORDER_RINGS[1:]]
    grid = [[round(outside_h(ter, ways, x, z), 3) if not (0 <= x <= M and 0 <= z <= M) or x in (0.0, M) or z in (0.0, M)
             else None for x in xs] for z in zs]
    with open(os.path.join(OUTDOOR_JSON_DIR, "border.json"), "w") as f:
        json.dump({"note": "Generated by tools/gen_old_bloxov.py: the land outside the map (Godot x, z; heights, null "
                   "inside the map), the ways out, for art_source/scripts/make_outdoor.py border().",
                   "look": BORDER_LOOK, "size": M, "xs": [round(gx(v), 3) for v in xs], "zs": [round(gz(v), 3) for v in zs],
                   "h": grid, "ways": [[round(gx(a), 3), round(gz(b), 3), nx, nz, w, round(y, 3), k]
                                       for a, b, nx, nz, w, y, k in ways],
                   "edge": [[round(gz(v) if s else gx(v), 3), round(ter.at(*((0.0, v) if s == 1 else (M, v) if s == 2
                                                                            else (v, 0.0) if s == 0 else (v, M))), 3)]
                            for s in range(4) for v in ter.xs]}, f)
    # the tree lines outside: big trees close to the fence, cheap far ones (scripts/trees.gd kind 8) behind
    rng = random.Random("border trees")

    def clear(x, z):
        return all(abs((x - ox) * nz - (z - oz) * nx) > w / 2 + 5.0 for ox, oz, nx, nz, w, _, _ in ways) and \
            not (x < 0 and 205.0 < z < 240.0 and x > -20.0) and not (z > M and 80.0 < x < 123.0 and z < M + 14.0)
    for _ in range(9000):
        side = rng.randrange(4)
        a = rng.uniform(-60.0, M + 60.0)
        d = 7.0 + rng.random() ** 1.6 * 170.0
        x, z = ((a, -d), (a, M + d), (-d, a), (M + d, a))[side]
        if min(x, z) < -d - 0.1 or max(x, z) > M + d + 0.1 or not clear(x, z):
            continue
        if d > 40.0 and rng.random() < 0.35 + d / 400.0:   # (thinner far out: the far ones are bigger)
            continue
        y = outside_h(ter, ways, x, z) - 0.05
        roll = rng.random()
        if d < 26.0:
            kind = 1 if roll < 0.6 else 0 if roll < 0.82 else 2
            tree_data.append((gx(x), y, gz(z), rng.uniform(5.2, 7.6), rng.uniform(3.2, 4.6), kind, rng.uniform(0, 360)))
        else:
            tree_data.append((gx(x), y, gz(z), rng.uniform(6.0, 9.0) * (1 + d / 260.0), rng.uniform(4.0, 5.5) * (1 + d / 200.0),
                              8 if roll < 0.75 else 9, rng.uniform(0, 360)))


# How thick scripts/trees.gd draws each kind's trunk at chest height (broadleaf, pine, birch): its collision.
TRUNK_WIDTHS = {0: 0.6, 1: 0.46, 2: 0.32}


def write_outdoor(ter):
    """The outdoor debris kit's .json per chunk (see `debris_kind`), and hides the gray boxes of the chunks whose model
    exists. Returns those chunks' names."""
    names = {i: n for n, i in C.items()}
    pieces = {}
    for k, b in enumerate(boxes):
        if len(b) > 10:
            pieces.setdefault(b[10], []).append(k)
    chunks = {}
    for tag, ks in sorted(pieces.items()):
        d = debris[tag]
        x, z = d["at"]
        chunk = outdoor_chunk(x, z)
        look = random.Random(f"debris {d['kind']} {x:.2f} {z:.2f}").choice("bcd")   # (owner: a mix of all three)
        if d["kind"] == "lamp" and LAMP_LOOK:
            look = LAMP_LOOK
        if d["kind"] in SIGN_KINDS:
            look = SIGN_LOOK
        if d["kind"] in POLE_KINDS:   # (one look for every pole and its wires)
            look = POLE_LOOK
        if d["kind"] == "berm":   # (earth banks are shaped from the ground; wire-mesh barriers only at army posts)
            look = "d" if any(e["kind"] in ARMY_KINDS and not e.get("dropped") and
                              math.hypot(e["at"][0] - x, e["at"][1] - z) < 30 for e in debris) else "b"
        chunks.setdefault(chunk, []).append((d["kind"], look, f"{x:.2f} {z:.2f}", ks))
        if d["kind"] in ("tree", "deadtree"):   # (drawn by scripts/trees.gd)
            trunk = boxes[ks[0]]
            s = boxes[ks[1]][3] if d["kind"] == "tree" and len(ks) > 1 else 0.0
            kind = tree_kind(x, z) if d["kind"] == "tree" else 3
            tree_data.append((trunk[0], trunk[1] - trunk[4] / 2, trunk[2], trunk[4], s, kind,
                              random.Random(f"tree yaw {x:.2f} {z:.2f}").uniform(0, 360)))
            if d["kind"] == "tree":   # (0.18.3, owner: shots hit the air between trees: the trunk collides as drawn)
                w = TRUNK_WIDTHS[kind]
                boxes[ks[0]] = trunk[:3] + (w, trunk[4], w, tree_data[-1][6]) + trunk[7:]
        if d["kind"] == "crops":   # (outdoor step 8: clumps of crop cards over the strip, scripts/trees.gd kinds 5-7)
            b = boxes[ks[0]]
            crng = random.Random(f"crops {x:.2f} {z:.2f}")
            kind, tall = {"b": (5, 1.0), "c": (6, 1.06), "d": (7, 1.02)}[look]
            n = int(b[3] / 0.6)
            for row in (-1.0, -0.33, 0.33, 1.0):
                for k in range(n):
                    tree_data.append((b[0] - b[3] / 2 + (k + crng.uniform(0.2, 0.8)) * b[3] / n, b[1] - b[4] / 2 - 0.03,
                                      b[2] + row * 1.1 + crng.uniform(-0.15, 0.15), tall * crng.uniform(0.9, 1.04),
                                      crng.uniform(0.8, 1.05), kind, crng.uniform(0, 360)))
        if d["kind"] == "bush":   # (drawn by scripts/bushes.gd: owner 2026-10-18 picked C, D (airy) for some)
            airy = random.Random(f"bush airy {x:.2f} {z:.2f}").random() < 0.3
            for k in ks:
                b = boxes[k]
                bush_data.append((b[0], b[1] - b[4] / 2, b[2], b[3], b[4], b[5], b[6], "bcd".index(look), 1 if airy else 0))
    # ferns on the woods' floor (outdoor step 7: looks only, no boxes), clear of trunks, paths and the creek
    rng = random.Random("ferns")
    for cx, cz, r in woods:
        if r < 7:
            continue
        for _ in range(int(r * 1.6)):
            a, d = rng.uniform(0, 2 * math.pi), r * rng.random() ** 0.5
            fx, fz = cx + math.cos(a) * d, cz + math.sin(a) * d
            if in_creek(fx, fz) or ter.pad_at(fx, fz) is not None or \
                    any(math.hypot(fx - tx, fz - tz) < 1.2 for tx, tz in trunks) or \
                    any(_seg_rect_gap(p, q, (fx - 0.1, fz - 0.1, fx + 0.1, fz + 0.1)) < w / 2 + 1.5
                        for pts, w in roads + paths for p, q in zip(pts, pts[1:])):
                continue
            tree_data.append((gx(fx), ter.lift(fx, fz) - 0.03, gz(fz), rng.uniform(0.45, 0.8), rng.uniform(1.0, 1.7), 4,
                              rng.uniform(0, 360)))
    os.makedirs(OUTDOOR_JSON_DIR, exist_ok=True)
    with open(os.path.join(OUTDOOR_JSON_DIR, "terrain.json"), "w") as f:   # (the pieces are fitted to the ground)
        json.dump({"note": "Generated by tools/gen_old_bloxov.py: the ground's height grid (Godot x, z; split like BoxMap's "
                   "triangles), for art_source/scripts/make_outdoor.py.", "xs": [round(gx(v), 3) for v in ter.xs],
                   "zs": [round(gz(v), 3) for v in ter.zs], "h": [[round(h, 3) for h in row] for row in ter.h],
                   # (the road ribbons' sections, Godot x, height, z, left then right, per road: so things lying in
                   # the road sit on it, not on the ground under it)
                   "roads": _ribbon_sections(ter)}, f)
    shown = []
    for chunk, ps in sorted(chunks.items()):
        i, j = int(chunk[-2]), int(chunk[-1])
        ox, oz = gx((i + 0.5) * OUTDOOR_CHUNK), gz((j + 0.5) * OUTDOOR_CHUNK)
        rows = []
        for kind, look, seed, ks in ps:
            rows.append(json.dumps({"kind": kind, "look": look, "seed": seed, "boxes": [
                {"pos": [round(boxes[k][0] - ox, 3), round(boxes[k][1], 3), round(boxes[k][2] - oz, 3)],
                 "size": [round(v, 3) for v in boxes[k][3:6]], "yaw": round(boxes[k][6], 2), "pitch": round(boxes[k][7], 2),
                 "colour": names[boxes[k][8]], "solid": bool(boxes[k][9])} for k in ks]}))
        with open(os.path.join(OUTDOOR_JSON_DIR, chunk + ".json"), "w") as f:
            f.write('{"note": "Generated by tools/gen_old_bloxov.py: the outdoor debris pieces in this map chunk (gray boxes '
                    'in Godot space relative to the chunk\'s middle, at height 0). Drawn by art_source/scripts/make_outdoor.py.",\n'
                    f'"origin": [{ox}, {oz}],\n'
                    '"pieces": [\n' + ",\n".join(rows) + "\n]}\n")
        if os.path.exists(outdoor_path(chunk)):
            shown.append((chunk, ox, oz))
            for kind, _, seed, ks in ps:
                shaped = SHAPED.get(f"{kind} {seed}")
                if shaped and shaped.get("people"):   # (what shots hit, inside the boxes that stop people: 0.19.8)
                    for n in shaped["boxes"]:
                        b = boxes[ks[n]]
                        shot_faces.extend(v for p in clipped_to_box(shaped["tris"], b[:3], b[3:6], b[6]) for v in p)
                elif shaped:   # (collides with its drawing instead: `shaped_faces`)
                    shaped_faces.extend(shaped["tris"])
                for n, k in enumerate(ks):
                    b = boxes[k]
                    if shaped and n in shaped["boxes"]:
                        boxes[k] = b[:9] + (3,) + b[10:]
                        if shaped.get("people"):   # (0.19.8: open frames still stop people, just not shots)
                            bar_boxes.append((b[0], b[1], b[2], b[3], b[4], b[5], b[6]))
                    elif b[9] in (0, 1):
                        boxes[k] = b[:9] + (2 if b[9] else 3,) + b[10:]
    return shown


# Collision shaped like the drawing (0.18.3, owner: "a lot of hitboxes are messed up like rocks ... match hitboxes to
# them"): boulders, earth banks, crater rims, rubble lumps and the derailed train's locomotive and tank cars collide
# with triangles made from their models (art_source/scripts/make_outdoor.py writes art_source/outdoor/collision.json)
# instead of their gray boxes, which then neither collide nor show. BoxMap `shaped_faces`. After changing any of these
# pieces: run this, make_outdoor.py, then this again.
SHAPED_JSON = os.path.join(OUTDOOR_JSON_DIR, "collision.json")
SHAPED = json.load(open(SHAPED_JSON))["shapes"] if os.path.exists(SHAPED_JSON) else {}
# (0.22.0, World reacts: the litter's cans and bottles, kicked about by scripts/kickables.gd; looks only)
KICKS = json.load(open(SHAPED_JSON)).get("kicks", []) if os.path.exists(SHAPED_JSON) else []
shaped_faces = []


def shaped_mesh():
    """`shaped_faces` as points and indices (three per triangle; shared corners once: a smaller scene)."""
    if "mesh" not in _shaped_cache:
        points, index, indices = [], {}, []
        for k in range(0, len(shaped_faces), 3):
            p = tuple(fmt(v) for v in shaped_faces[k:k + 3])
            if p not in index:
                index[p] = len(points)
                points.append(shaped_faces[k:k + 3])
            indices.append(index[p])
        _shaped_cache["mesh"] = (points, indices)
    return _shaped_cache["mesh"]


_shaped_cache = {}

# What shots and eyes hit on the see-through pieces (0.19.8/0.19.9: shelters, fences, car windows, tables...): their
# drawings' triangles, cut to the boxes that still stop people (BoxMap `bar_boxes`), so nobody ever bumps into them
# and moving round them is as before. BoxMap `shot_points` / `shot_indices`; the navigation bake leaves them out.
shot_faces = []


def clipped_to_box(tris, c, size, yaw):
    """The triangles (flat x, y, z list) cut to the box (centre, size, yaw in degrees), as a list of points (three a
    triangle)."""
    co, si = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    half = [v / 2 for v in size]
    out = []
    for k in range(0, len(tris), 9):
        poly = []
        for j in range(3):
            dx, dy, dz = tris[k + 3 * j] - c[0], tris[k + 3 * j + 1] - c[1], tris[k + 3 * j + 2] - c[2]
            poly.append((dx * co - dz * si, dy, dx * si + dz * co))   # (into the box's frame)
        for axis in range(3):
            for sign in (1, -1):
                lim = half[axis]
                res = []
                for a, b in zip(poly, poly[1:] + poly[:1]):
                    da, db = lim - sign * a[axis], lim - sign * b[axis]
                    if da >= 0:
                        res.append(a)
                    if (da >= 0) != (db >= 0):
                        t = da / (da - db)
                        res.append(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))
                poly = res
                if len(poly) < 3:
                    break
            if len(poly) < 3:
                break
        if len(poly) < 3:
            continue
        world = [(c[0] + x * co + z * si, c[1] + y, c[2] - x * si + z * co) for x, y, z in poly]
        for j in range(1, len(world) - 1):
            out += [world[0], world[j], world[j + 1]]
    return out


def shot_mesh():
    if "mesh" not in _shot_cache:
        points, index, indices = [], {}, []
        for k in range(0, len(shot_faces), 3):
            p = tuple(fmt(v) for v in shot_faces[k:k + 3])
            if p not in index:
                index[p] = len(points)
                points.append(shot_faces[k:k + 3])
            indices.append(index[p])
        _shot_cache["mesh"] = (points, indices)
    return _shot_cache["mesh"]


_shot_cache = {}


def _ribbon_h(ter, i, x, z, tx, tz, width, miter=1.0, step=2.0):
    """The height of road i's ribbon at the section through (x, z) (direction (tx, tz))."""
    # (level across, at the highest ground under it: the ground's grid cells bend between the samples and
    # poked through the road's edges in steps)
    y = 0.02 + 0.004 * (i + 1) + 0.04 + 0.002
    h = max(ter.at(x + tx * a - tz * b * width / 2 * miter, z + tz * a + tx * b * width / 2 * miter)
            for a in (-step / 2, 0.0, step / 2) for b in (-1.0, -0.5, 0.0, 0.5, 1.0)) + y
    if abs(z - RAIL_Z) < 1.6 + width:   # a level crossing: over the rails, as the strips do
        h = max(h, RAIL_TOP + COVER_STEP + 0.002)
    return h


def road_top(ter, x, z):
    """The top of the road surface at (x, z), or None off the roads (the highest where roads meet)."""
    best = None
    for i, (curve, width) in enumerate(roads):
        for (ax, az), (bx, bz) in zip(curve, curve[1:]):
            ux, uz = bx - ax, bz - az
            ln = math.hypot(ux, uz) or 1.0
            t = max(0.0, min(ln, ((x - ax) * ux + (z - az) * uz) / ln))
            px, pz = ax + ux / ln * t, az + uz / ln * t
            if math.hypot(x - px, z - pz) <= width / 2 + 0.1:
                h = _ribbon_h(ter, i, px, pz, ux / ln, uz / ln, width)
                best = h if best is None else max(best, h)
    return best


KERB_ROADS = (0, 2, 3, 4, 5)   # (road index: Main Street, Hill Road, Mill Lane, the old road, Station Road) in TOWN


def _ribbon_sections(ter):
    """Per road: its width, ribbon points and their flags (see road_ribbons), and whether it gets kerbs (in town:
    the flag is 3 where a door's path or a car park's way in meets it, no kerb there)."""
    pts, _, flags, counts, widths = road_ribbons(ter)
    gaps = [p[-1] for p, _, _ in door_walks] + [p[0] for p, _ in lot_ways] + [p[-1] for p, _ in lot_ways]
    out, k = [], 0
    for r, (n, w) in enumerate(zip(counts, widths)):
        fl = list(flags[k:k + 2 * n])
        for i in range(k, k + 2 * n):
            x, z = pts[i][0] + M / 2, pts[i][2] + M / 2
            if fl[i - k] == 0 and any(math.hypot(x - gx_, z - gz_) < 2.2 for gx_, gz_ in gaps):
                fl[i - k] = 3.0
            if not (TOWN[0] < x < TOWN[2] and TOWN[1] < z < TOWN[3]):
                fl[i - k] = max(fl[i - k], 4.0)   # (out of town: no kerb)
        out.append({"width": w, "kerb": r in KERB_ROADS, "flags": fl,
                    "points": [[round(v, 3) for v in pts[i]] for i in range(k, k + 2 * n)]})
        k += 2 * n
    return out


def road_ribbons(ter, step=2.0):
    """The roads' surface (World art 0.17, outdoor step 3; owner: the lines were jagged and broken at every piece):
    one smooth ribbon per road for BoxMap to draw instead of its strip pieces, sections every `step` m at the strips'
    height (each road a hair above the one before, like the strips), mitred at bends. Per vertex: position, (across,
    along) in metres for the lane lines, and 1 where it's inside another road (no lines through junctions), 2 at a
    car park's way in (no edge line).
    Returns (points, uvs, junction flags, sections per road, widths)."""
    pts, uvs, flags, counts, widths = [], [], [], [], []
    for i, (curve, width) in enumerate(roads):
        others = [(c, w) for k, (c, w) in enumerate(roads) if k != i]
        samples = []
        for (ax, az), (bx, bz) in zip(curve, curve[1:]):
            ln = math.hypot(bx - ax, bz - az)
            n = max(1, int(math.ceil(ln / step)))
            for k in range(n):
                samples.append((ax + (bx - ax) * k / n, az + (bz - az) * k / n))
        samples.append(curve[-1])
        dist = 0.0
        for k, (x, z) in enumerate(samples):
            if k:
                dist += math.hypot(x - samples[k - 1][0], z - samples[k - 1][1])
            p0, p1 = samples[max(0, k - 1)], samples[min(len(samples) - 1, k + 1)]
            tx, tz = p1[0] - p0[0], p1[1] - p0[1]
            tl = math.hypot(tx, tz) or 1.0
            tx, tz = tx / tl, tz / tl
            miter = 1.0
            if 0 < k < len(samples) - 1:   # (keep the width square to each piece at a bend)
                ux, uz = samples[k + 1][0] - x, samples[k + 1][1] - z
                ul = math.hypot(ux, uz) or 1.0
                miter = min(1.4, 1.0 / max(0.7, (ux * tx + uz * tz) / ul))
            h = _ribbon_h(ter, i, x, z, tx, tz, width, miter, step)
            for side in (-1, 1):
                px, pz = x - tz * side * width / 2 * miter, z + tx * side * width / 2 * miter
                pts.append((gx(px), h, gz(pz)))
                uvs.append((side * width / 2, dist))
                inside = any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 0.8 for c, w in others for a, b in zip(c, c[1:]))
                mouth = any(_seg_rect_gap(a, b, (px, pz, px, pz)) < w / 2 + 0.5 for c, w in lot_ways for a, b in zip(c, c[1:]))
                flags.append(1.0 if inside else 2.0 if mouth else 0.0)
        counts.append(len(samples))
        widths.append(width)
    return pts, uvs, flags, counts, widths


def write_scene(ter):
    write_model_boxes(ter)
    outdoor = write_outdoor(ter)
    write_border(ter)
    if os.path.exists(BORDER_GLB):
        outdoor.append(("outdoor_border", 0.0, 0.0))
    write_splat(ter)
    for i, b in enumerate(boxes):   # (railings and bars: people-only, see PEOPLE_KINDS; 5: players only, solid_late)
        if b[9] == 4:
            bar_boxes.append(tuple(b[:7]))
            boxes[i] = b[:9] + (3,) + b[10:]
        elif b[9] == 5:
            prop_boxes.append(tuple(b[:7]))
            boxes[i] = b[:9] + (3,) + b[10:]
    scenes = {"crate": "res://scenes/loot_crate.tscn", "locker": "res://scenes/loot_locker.tscn",
              "safe": "res://scenes/loot_safe.tscn", "door": "res://scenes/key_door.tscn",
              "swing_door": "res://scenes/door.tscn", "ladder": "res://scenes/ladder.tscn"}
    out = ["[gd_scene format=3]", "",
           '[ext_resource type="Script" path="res://scripts/box_map.gd" id="1_boxmap"]',
           '[ext_resource type="PackedScene" path="res://scenes/extract_zone.tscn" id="2_extract"]']
    ids = {}
    for n, (kind, path) in enumerate(scenes.items(), start=3):
        ids[kind] = f"{n}_{kind}"
        out.append(f'[ext_resource type="PackedScene" path="{path}" id="{ids[kind]}"]')
    shown = [m for m in models if m["hide"]]
    if shown:
        out.append('[ext_resource type="Script" path="res://scripts/pixel_model.gd" id="m_pixel"]')
    for m in shown:
        out.append(f'[ext_resource type="PackedScene" path="res://assets/models/buildings/{m["name"]}.glb" id="m_{m["name"]}"]')
    placed = [(c, car_at[c["anchor"]]) for c in cars if c["anchor"] in car_at and os.path.exists(car_glb(c["glb"]))]
    if (placed or outdoor) and not shown:
        out.append('[ext_resource type="Script" path="res://scripts/pixel_model.gd" id="m_pixel"]')
    for chunk, _, _ in outdoor:
        out.append(f'[ext_resource type="PackedScene" path="res://assets/models/outdoor/{chunk}.glb" id="o_{chunk}"]')
    for glb in sorted({c["glb"] for c, _ in placed}):
        out.append(f'[ext_resource type="PackedScene" path="res://assets/models/props/cars/{glb}.glb" id="c_{glb}"]')
    out.append('[ext_resource type="Material" path="res://assets/materials/ground.tres" id="g_ground"]')
    out.append('[ext_resource type="PackedScene" path="res://scenes/smoke_column.tscn" id="s_smoke"]')
    out.append('[ext_resource type="Script" path="res://scripts/ghost_cloth.gd" id="s_ghost"]')
    rib = road_ribbons(ter) if ROAD_LOOK != "a" else ([], [], [], [], [])
    out.append('[ext_resource type="Material" path="res://assets/materials/lot.tres" id="g_lot"]')
    out.append('[ext_resource type="Material" path="res://assets/materials/water.tres" id="g_water"]')
    out.append('[ext_resource type="Mesh" path="res://assets/meshes/waterfall_sheet.tres" id="g_fall"]')
    out.append('[ext_resource type="Mesh" path="res://assets/meshes/waterfall_splash.tres" id="g_splash"]')
    if ROAD_LOOK != "a":   # (a: the old flat colour, for the options sheets)
        out.append(f'[ext_resource type="Material" path="res://assets/materials/road_{ROAD_LOOK}.tres" id="g_road"]')
    out.append('[ext_resource type="Script" path="res://scripts/grass_tufts.gd" id="g_tufts"]')
    out.append('[ext_resource type="Script" path="res://scripts/bushes.gd" id="g_bushes"]')
    out.append('[ext_resource type="Script" path="res://scripts/kickables.gd" id="g_kicks"]')
    out.append('[ext_resource type="Texture2D" path="res://assets/textures/ground/leaves.png" id="g_leaves"]')
    out.append('[ext_resource type="Script" path="res://scripts/trees.gd" id="g_trees"]')
    out.append('[ext_resource type="Texture2D" path="res://assets/textures/trees/trees.png" id="g_tree_sheet"]')
    for rid, png in (("g_tuft_sprites", "tufts"), ("g_splat", "splat"), ("g_mask", "grass_mask")):
        out.append(f'[ext_resource type="Texture2D" path="res://assets/textures/ground/{png}.png" id="{rid}"]')
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
            "boxes = PackedFloat32Array(" + ", ".join(fmt(v) for b in boxes for v in b[:10]) + ")",
            "colour_names = PackedStringArray(" + ", ".join(f'"{name}"' for name, _ in COLOURS) + ")",
            "floor_rects = PackedFloat32Array(" + ", ".join(fmt(v) for r in floor_rects for v in r) + ")",
            f"terrain_colour = {C['grass']}",
            'ground_material = ExtResource("g_ground")',
            'road_material = ExtResource("g_road")' if ROAD_LOOK != "a" else "",
            f"road_colour = {C['road']}",
            'lot_material = ExtResource("g_lot")',
            f"lot_colour = {C['lot']}",
            "road_points = PackedVector3Array(" + ", ".join(f"{fmt(a)}, {fmt(b)}, {fmt(c)}" for a, b, c in rib[0]) + ")",
            "road_uvs = PackedVector2Array(" + ", ".join(f"{fmt(a)}, {fmt(b)}" for a, b in rib[1]) + ")",
            "road_junctions = PackedFloat32Array(" + ", ".join(fmt(v) for v in rib[2]) + ")",
            "road_sections = PackedInt32Array(" + ", ".join(str(v) for v in rib[3]) + ")",
            "road_widths = PackedFloat32Array(" + ", ".join(fmt(v) for v in rib[4]) + ")",
            "terrain_xs = PackedFloat32Array(" + ", ".join(fmt(gx(x)) for x in ter.xs) + ")",
            "terrain_zs = PackedFloat32Array(" + ", ".join(fmt(gz(z)) for z in ter.zs) + ")",
            "terrain_heights = PackedFloat32Array(" + ", ".join(fmt(h) for row in ter.h for h in row) + ")",
            "terrain_holes = PackedInt32Array(" + ", ".join(str(c) for c in ter.hole_cells) + ")",
            "terrain_hidden = PackedInt32Array(" + ", ".join(str(c) for c in ter.hidden_cells) + ")",
            f"water_colour = {C['water']}",
            'water_material = ExtResource("g_water")',
            f"water_width = {fmt(2 * CREEK_BANK)}",
            "water_points = PackedVector3Array(" + ", ".join(
                f"{fmt(gx(x))}, {fmt(ter.water_level(x, z))}, {fmt(gz(z))}" for x, z in water[0][0][WATER_START:]) + ")",
            "stream_points = PackedVector3Array(" + ", ".join(f"{fmt(x)}, {fmt(y)}, {fmt(z)}" for x, y, z in stream_line(ter)) + ")",
            "stream_width = 1.0",
            "water_rocks = PackedVector4Array(" + ", ".join(f"{fmt(x)}, {fmt(z)}, {fmt(r)}, 0" for x, z, r in water_rocks) + ")",
            "window_panes = PackedFloat32Array(" + ", ".join(fmt(v) for p in window_panes for v in p) + ")",
            "bar_boxes = PackedFloat32Array(" + ", ".join(fmt(v) for b in bar_boxes for v in b) + ")",
            "prop_boxes = PackedFloat32Array(" + ", ".join(fmt(v) for b in prop_boxes for v in b) + ")",
            "shaped_points = PackedVector3Array(" + ", ".join(fmt(v) for p in shaped_mesh()[0] for v in p) + ")",
            "shaped_indices = PackedInt32Array(" + ", ".join(str(i) for i in shaped_mesh()[1]) + ")",
            "shot_points = PackedVector3Array(" + ", ".join(fmt(v) for p in shot_mesh()[0] for v in p) + ")",
            "shot_indices = PackedInt32Array(" + ", ".join(str(i) for i in shot_mesh()[1]) + ")",
            "",
            # the waterfall's falling water and its splash (outdoor step 6), in front of the secret room's door
            '[node name="WaterfallSheet" type="MeshInstance3D" parent="Level"]',
            f"transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, {fmt(gx(CAVE_FALL))}, "
            f"{fmt(cave_floor[0] + CAVE_LIP - 1.1 - 2.95)}, {fmt(gz(sum(CAVE_DOOR[:2]) / 2))})",
            'mesh = ExtResource("g_fall")',
            "cast_shadow = 0", "",
            '[node name="WaterfallSplash" type="MeshInstance3D" parent="Level"]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(gx(sum(CAVE_SPLASH) / 2))}, {fmt(cave_floor[1])}, "
            f"{fmt(gz(sum(CAVE_DOOR[:2]) / 2))})",
            'mesh = ExtResource("g_splash")',
            "cast_shadow = 0", "",
            # grass tufts and wildflowers near the camera (outdoor step 2), where write_splat's maps say grass grows
            '[node name="Tufts" type="Node3D" parent="Level/Blocks"]',
            'script = ExtResource("g_tufts")',
            'sprites = ExtResource("g_tuft_sprites")',
            'splat = ExtResource("g_splat")',
            'mask = ExtResource("g_mask")',
            f"map_origin = Vector2({fmt(-M / 2)}, {fmt(-M / 2)})",
            f"map_size = {fmt(M)}", "",
            # the bushes (outdoor; their boxes collide and block the AI's sight, this draws them)
            '[node name="Bushes" type="Node3D" parent="Level/Blocks"]',
            'script = ExtResource("g_bushes")',
            'leaves = ExtResource("g_leaves")',
            "data = PackedFloat32Array(" + ", ".join(fmt(v) for b in bush_data for v in b) + ")", "",
            # the litter's cans and bottles (0.22.0, World reacts: kicked about, looks only; make_outdoor.py lists them)
            '[node name="Kickables" type="Node3D" parent="Level/Blocks"]',
            'script = ExtResource("g_kicks")',
            "data = PackedFloat32Array(" + ", ".join(fmt(v) for k in KICKS for v in k[:5]) + ")",
            "colors = PackedColorArray(" + ", ".join("%s, %s, %s, 1" % tuple(fmt(int(k[5][j:j + 2], 16) / 255) for j in (0, 2, 4))
                                                     for k in KICKS) + ")", "",
            # the trees (outdoor step 7; their trunks collide and their leaves hide you from the AI, this draws them)
            '[node name="Trees" type="Node3D" parent="Level/Blocks"]',
            'script = ExtResource("g_trees")',
            'sheet = ExtResource("g_tree_sheet")',
            f"look = {TREE_LOOK}",
            "data = PackedFloat32Array(" + ", ".join(fmt(v) for t in tree_data for v in t) + ")", "",
            '[node name="Models" type="Node3D" parent="Level"]', ""]
    for m in shown:
        out += [f'[node name="{m["name"]}" parent="Level/Models" instance=ExtResource("m_{m["name"]}")]',
                f"transform = {xform(m['x'], m['y'], m['z'], m['turned'])}", 'script = ExtResource("m_pixel")', ""]
        if m["name"] == "town_hall":   # the ghost cloth over the bunker ramp fades once someone goes through (0.18.6)
            out += ['[node name="GhostCloth" type="Area3D" parent="Level/Models/town_hall"]',
                    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -17.25, 0.5, -1.8)", 'script = ExtResource("s_ghost")', ""]
    if placed:
        out += ['[node name="Cars" type="Node3D" parent="Level/Models"]', ""]
    for n, (c, (b, lift, *tilt)) in enumerate(placed):
        out += [f'[node name="Car{n}" parent="Level/Models/Cars" instance=ExtResource("c_{c["glb"]}")]',
                f"transform = {car_xform(c, b, lift, *tilt)}", 'script = ExtResource("m_pixel")', ""]
    if outdoor:
        out += ['[node name="Outdoor" type="Node3D" parent="Level/Models"]', ""]
    for chunk, ox, oz in outdoor:
        out += [f'[node name="{chunk}" parent="Level/Models/Outdoor" instance=ExtResource("o_{chunk}")]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(ox)}, 0, {fmt(oz)})", 'script = ExtResource("m_pixel")', ""]
    out += ['[node name="Loot" type="Node3D" parent="."]', ""]
    for name, kind, x, y, z, yaw, table, place in loot:
        out += [f'[node name="{name}" parent="Loot" instance=ExtResource("{ids[kind]}")]',
                f"transform = {xform(x, y, z, yaw)}",
                f'metadata/place = "{place}"'] + prop_lines(name, kind, place) + (["metadata/locked = true"] if behind_key_door(place, x, z) else []) + [""]
    for k, (x, z) in enumerate(SMOKE):
        out += [f'[node name="Smoke{k}" parent="Level" instance=ExtResource("s_smoke")]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(gx(x))}, {fmt(ter.lift(x, z) + 0.8)}, {fmt(gz(z))})", ""]
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
    for name, x, z, zone, building in indoor_spawns:   # (on the floor: 0.12.23-0.12.37 put them 1.2 m up, heads in the ceiling)
        out += [f'[node name="{name}" type="Marker3D" parent="EnemySpawns"]',
                f"transform = {xform(x, ter.lift(x, z) + 0.1, z)}", f'metadata/zone = "{zone}"',
                "metadata/indoor = true", f'metadata/building = "{building}"', ""]
    for i, (x, z) in enumerate(BOSS_STARTS):   # (on the hall's floor)
        out += [f'[node name="BossStart{i + 1}" type="Marker3D" parent="EnemySpawns"]',
                f"transform = {xform(x, ter.lift(x, z) + 0.1, z)}", "metadata/boss_start = true", ""]
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
            if grp == "Doors":      # ordinary doors (0.17): F opens and shuts them, the AI open them
                if any(k[0] == "KeyDoors" and abs(k[2] - x) < 1.0 and abs(k[4] - z) < 1.0 for k in markers):
                    continue
                out += [f'[node name="{name}" parent="{g}" instance=ExtResource("{ids["swing_door"]}")]',
                        f"transform = {xform(x, y, z, meta['yaw'])}",
                        f"size = Vector2({fmt(meta['width'])}, {fmt(DOOR_H)})", f'look = "{meta["look"]}"']
                if meta["broken"]:
                    out.append(f'broken = "{meta["broken"]}"')
                out += [f'metadata/place = "{meta["place"]}"', ""]
                continue
            if grp == "Ladders":    # ladders (0.13.5; the barn's loft, World art 0.17)
                out += [f'[node name="{name}" parent="{g}" instance=ExtResource("{ids["ladder"]}")]',
                        f"transform = {xform(x, y, z, meta['yaw'])}", f"height = {fmt(meta['height'])}",
                        f'metadata/place = "{meta["place"]}"', ""]
                continue
            if grp == "KeyDoors":   # locked doors (0.14.0): a door leaf filling the doorway, a bit wider than it
                out += [f'[node name="{name}" parent="{g}" instance=ExtResource("{ids["door"]}")]',
                        f"transform = {xform(x, y, z, meta['yaw'])}", f'key = "{meta["key"]}"',
                        f"size = Vector3({fmt(meta['width'] + 0.2)}, {fmt(DOOR_H + 0.05)}, 0.12)",
                        f'metadata/place = "{meta["place"]}"', ""]
                continue
            out += [f'[node name="{name}" type="Marker3D" parent="{g}"]', f"transform = {xform(x, y, z)}"]
            out += [f'metadata/{k} = "{v}"' for k, v in meta.items()]
            out.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
