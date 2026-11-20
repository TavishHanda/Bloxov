"""The expedition truck (0.38.3, Expeditions; owner 2026-11-20: "make the vehicle look nicer with proper model"): the
amphibious armoured truck you build to leave the war, as five models, one per part, so the garage can show it growing
(scripts/hideout_garage.gd) and the leaving cutscene shows it whole (scripts/expedition_cutscene.gd build_truck).

    python3 art_source/scripts/make_truck.py          (~2 s)

Writes assets/models/props/truck/truck_<part>.glb for frame, engine, armor, radio and supplies, drawn with the kit
atlas like the map's cars and army trucks (make_building.py kit plus make_outdoor.py's painted steel, tyres, canvas).
All five share one frame: origin on the ground under the middle, front (the bow) at -z, so stacking them gives the
whole truck. Original design: a six-wheeled boat-hulled truck (no real vehicle copied), olive drab, no markings.
  frame    the boat hull (raked bow, chines), six wheels on axles, running boards, the open cargo bed, tow eyes
  engine   the armoured cab (sloped screen, side windows, doors, roof hatch, lights, mirrors), the engine deck (louvres,
           exhaust stack) and the two propeller tunnels at the stern
  armor    bolted steel: side skirts over the wheels, the bow's trim vane, bars over the windows, the cab's roof edge
  radio    two whip aerials, the radio set and a searchlight on the roof
  supplies jerry cans, crates, ration cartons, water, a med case (no red cross: STORE_RULES / owner), a tarp bundle,
           a spare wheel and the roof rack load
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb                                   # noqa: E402
import make_outdoor as mo                                    # noqa: E402  (its KIT entries: dbr_trk_o, dbr_tyre, ...)
from make_building import Builder, Texture, uv_world, v_add, v_sub, cross, norm, rot   # noqa: E402

OUT_DIR = os.path.join(mb.ROOT, "assets", "models", "props", "truck")
PARTS = ("frame", "engine", "armor", "radio", "supplies")

PAINT = "dbr_trk_o"          # olive drab, chipped
STEEL = "olive_dark"         # the bolted-on armour (darker plates over the olive)
DARK = "trim_dark"
TYRE = "dbr_tyre"

# The hull, front at -z: sections (z, bottom y, top y, bottom half width, top half width), bow to stern.
HULL = [(-3.6, 1.05, 1.42, 0.82, 1.08), (-3.0, 0.62, 1.45, 1.0, 1.22), (2.75, 0.62, 1.45, 1.0, 1.22),
        (3.2, 0.9, 1.45, 0.95, 1.2)]
DECK = 1.45
WHEEL_R, WHEEL_W, WHEEL_X, WHEEL_Y = 0.55, 0.42, 1.36, 0.55
WHEEL_Z = (-2.05, -0.35, 1.95)
CAB_Z = (-2.95, -0.55)       # the cab, bow end to its back wall
CAB_TOP = 2.7
CAB_HW = 1.12
BED_Z = (-0.55, 1.85)        # the cargo bed
ENGINE_Z = (1.85, 3.1)       # the engine deck at the stern


def quad(b, pts, mat, tile=1.0, out=None):
    """A flat face; `out` = a point inside the solid it bounds (the face is turned away from it)."""
    n = norm(cross(v_sub(pts[1], pts[0]), v_sub(pts[2], pts[0])))
    if out is not None:
        mid = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
        if sum(n[k] * (mid[k] - out[k]) for k in range(3)) < 0:
            n = tuple(-k for k in n)
    b.poly(pts, n, mat, uv_world(tile))


def box(b, c, s, mat, yaw=0.0, pitch=0.0, bottom=True, tile=1.0):
    b.box(c, s, yaw=yaw, pitch=pitch, style=lambda n, m, q: None if (not bottom and n[1] < -0.7) else (mat, uv_world(tile)))


def loft(b, sections, mat, inside, caps=True, tile=2.0, top=True, bottom=True):
    """Joins hull-like sections (z, y0, y1, hw0, hw1) into a closed solid."""
    def ring(s):
        z, y0, y1, w0, w1 = s
        return [(-w0, y0, z), (w0, y0, z), (w1, y1, z), (-w1, y1, z)]   # bottom left, bottom right, top right, top left
    for a, c in zip(sections, sections[1:]):
        ra, rc = ring(a), ring(c)
        for k in range(4):
            if (k == 2 and not top) or (k == 0 and not bottom):
                continue
            quad(b, [ra[k], ra[(k + 1) % 4], rc[(k + 1) % 4], rc[k]], mat, tile, out=inside)
    if caps:
        for s in (sections[0], sections[-1]):
            quad(b, ring(s), mat, tile, out=inside)


def prism(b, profile, hw, mat, x0=0.0, tile=1.0, sides=True):
    """A side profile [(z, y)] (convex) pushed out across x from x0-hw to x0+hw."""
    cz = sum(p[0] for p in profile) / len(profile)
    cy = sum(p[1] for p in profile) / len(profile)
    inside = (x0, cy, cz)
    if sides:
        for sx in (-1, 1):
            quad(b, [(x0 + sx * hw, y, z) for z, y in profile], mat, tile, out=inside)
    for (z0, y0), (z1, y1) in zip(profile, profile[1:] + profile[:1]):
        quad(b, [(x0 - hw, y0, z0), (x0 + hw, y0, z0), (x0 + hw, y1, z1), (x0 - hw, y1, z1)], mat, tile, out=inside)


def bolts(b, a, c, n, normal_axis, sgn, size=0.05):
    """A row of n bolt heads from a to c on a face looking along +-normal_axis."""
    for i in range(n):
        t = (i + 0.5) / n
        p = [a[k] + (c[k] - a[k]) * t for k in range(3)]
        p[normal_axis] += sgn * size / 2
        s = [size, size, size]
        s[normal_axis] = size * 0.6
        box(b, tuple(p), tuple(s), DARK)


# ------------------------------------------------------------------------------------------------ the parts
def frame(b, rng):
    loft(b, HULL, PAINT, (0, 1.0, 0))
    # the chine (a rubbing strake round the hull at the deck edge) and the bow's rubber fender
    for sx in (-1, 1):
        box(b, (sx * 1.24, 1.38, -0.1), (0.06, 0.1, 6.0), DARK)
    box(b, (0, 1.36, -3.62), (1.9, 0.14, 0.12), "black")
    # the running boards over the wheels (a mudguard each wheel)
    for sx in (-1, 1):
        box(b, (sx * 1.38, 1.24, -0.05), (0.42, 0.06, 5.3), PAINT)
        for z in WHEEL_Z:
            box(b, (sx * 1.57, 1.1, z), (0.04, 0.28, 1.25), PAINT)
    # six wheels on their axles: big off-road tyres, a hub and its nuts
    for z in WHEEL_Z:
        box(b, (0, WHEEL_Y, z), (2.4, 0.14, 0.14), DARK)                              # axle
        for sx in (-1, 1):
            x = sx * WHEEL_X
            mo.cyl(b, (x, WHEEL_Y, z), WHEEL_R, WHEEL_W, TYRE, sides=14, axis="x", cap_mat="black")
            mo.cyl(b, (x + sx * 0.215, WHEEL_Y, z), 0.27, 0.04, PAINT, sides=10, axis="x")   # rim
            mo.cyl(b, (x + sx * 0.25, WHEEL_Y, z), 0.11, 0.06, DARK, sides=8, axis="x")      # hub
            for k in range(6):
                a = math.tau * k / 6
                box(b, (x + sx * 0.24, WHEEL_Y + math.sin(a) * 0.18, z + math.cos(a) * 0.18), (0.04, 0.05, 0.05), DARK)
            # tread blocks round the tyre (so it reads as an off-road tyre from the side)
            for k in range(14):
                a = math.tau * (k + 0.5) / 14
                box(b, (x, WHEEL_Y + math.sin(a) * WHEEL_R, z + math.cos(a) * WHEEL_R),
                    (WHEEL_W - 0.04, 0.04, 0.1), "black", pitch=-math.degrees(a))
    # the cargo bed's low walls (the cab closes its front; the frame alone has a front board)
    z0, z1 = BED_Z
    for sx in (-1, 1):
        box(b, (sx * 1.17, DECK + 0.25, (z0 + z1) / 2), (0.06, 0.5, z1 - z0), PAINT)
        box(b, (sx * 1.17, DECK + 0.52, (z0 + z1) / 2), (0.1, 0.05, z1 - z0), DARK)
        for z in (z0 + 0.6, (z0 + z1) / 2, z1 - 0.6):                                  # stakes
            box(b, (sx * 1.21, DECK + 0.25, z), (0.04, 0.5, 0.08), DARK)
    box(b, (0, DECK + 0.25, z0 + 0.03), (2.3, 0.5, 0.06), PAINT)
    box(b, (0, DECK + 0.01, (z0 + z1) / 2), (2.26, 0.02, z1 - z0 - 0.1), DARK, tile=1.0)
    # tow eyes, bow and stern; the bilge outlets
    for z, sg in ((-3.55, -1), (3.2, 1)):
        for sx in (-1, 1):
            box(b, (sx * 0.6, 1.0, z + sg * 0.06), (0.1, 0.22, 0.14), DARK)
    for sx in (-1, 1):
        mo.cyl(b, (sx * 1.115, 1.2, 2.2), 0.06, 0.04, "black", sides=8, axis="x")


def engine(b, rng):
    z0, z1 = CAB_Z
    # the cab: a sloped armoured screen at the front, flat sides
    prof = [(z1, DECK), (z1, CAB_TOP), (z0 + 0.75, CAB_TOP), (z0, DECK + 0.62), (z0, DECK)]
    prism(b, prof, CAB_HW, PAINT, tile=2.0)
    # windscreen: two panes on the slope, split by a post
    slope = math.degrees(math.atan2(CAB_TOP - (DECK + 0.62), 0.75))
    n_y, n_z = 0.75 / math.hypot(0.75, CAB_TOP - DECK - 0.62), -(CAB_TOP - DECK - 0.62) / math.hypot(0.75, CAB_TOP - DECK - 0.62)
    mid_z, mid_y = z0 + 0.375 + n_z * 0.015, (CAB_TOP + DECK + 0.62) / 2 + n_y * 0.015   # (just out from the slope)
    for sx in (-1, 1):
        box(b, (sx * 0.5, mid_y, mid_z), (0.8, 0.6, 0.03), "glass", pitch=90 - slope)
    box(b, (0, mid_y + n_y * 0.01, mid_z + n_z * 0.01), (0.14, 0.75, 0.04), PAINT, pitch=90 - slope)
    # side windows and the doors (an outline, a handle, hinges)
    for sx in (-1, 1):
        x = sx * (CAB_HW + 0.012)
        box(b, (x, 2.28, -1.55), (0.025, 0.42, 0.7), "glass")
        box(b, (sx * (CAB_HW + 0.008), 1.95, -1.5), (0.02, 1.0, 0.04), DARK)          # door seams
        box(b, (sx * (CAB_HW + 0.008), 1.95, -0.85), (0.02, 1.0, 0.04), DARK)
        box(b, (sx * (CAB_HW + 0.008), 2.46, -1.175), (0.02, 0.04, 0.69), DARK)
        box(b, (sx * (CAB_HW + 0.03), 1.98, -1.4), (0.05, 0.05, 0.16), DARK)          # handle
        box(b, (sx * (CAB_HW + 0.02), 1.65, -0.48), (0.04, 0.14, 0.08), DARK)         # hinges
        box(b, (sx * (CAB_HW + 0.02), 2.3, -0.48), (0.04, 0.14, 0.08), DARK)
        # mirror on an arm
        box(b, (sx * (CAB_HW + 0.2), 2.3, z0 + 0.95), (0.4, 0.04, 0.04), DARK)
        box(b, (sx * (CAB_HW + 0.38), 2.3, z0 + 0.95), (0.06, 0.32, 0.2), "black")
        # step under the door
        box(b, (sx * (CAB_HW + 0.15), 1.3, -1.2), (0.3, 0.05, 0.6), DARK)
    # the back wall's little window, the roof hatch
    box(b, (0, 2.3, z1 + 0.012), (0.9, 0.3, 0.025), "glass")
    mo.cyl(b, (-0.45, CAB_TOP + 0.05, -1.3), 0.36, 0.1, PAINT, sides=12)
    mo.cyl(b, (-0.45, CAB_TOP + 0.11, -1.3), 0.3, 0.04, DARK, sides=12)
    box(b, (-0.12, CAB_TOP + 0.13, -1.3), (0.12, 0.06, 0.06), DARK)                     # its hinge
    # headlights in the bow (round lamps, a bone lens), indicator, the horn
    for sx in (-1, 1):
        mo.cyl(b, (sx * 0.75, 1.58, z0 - 0.05), 0.13, 0.12, DARK, sides=10, axis="z")
        mo.cyl(b, (sx * 0.75, 1.58, z0 - 0.115), 0.1, 0.02, "bone", sides=10, axis="z")
        box(b, (sx * 1.0, 1.6, z0 - 0.04), (0.1, 0.07, 0.04), "yellow")
        box(b, (sx * 1.05, 1.6, ENGINE_Z[1] + 0.04), (0.14, 0.09, 0.04), "red")        # tail lights
    # the engine deck at the stern: a raised box, louvres on top, the exhaust stack
    e0, e1 = ENGINE_Z
    box(b, (0, DECK + 0.22, (e0 + e1) / 2), (2.3, 0.44, e1 - e0), PAINT, bottom=False, tile=2.0)
    for k in range(6):
        z = e0 + 0.2 + k * (e1 - e0 - 0.4) / 5
        box(b, (0, DECK + 0.45, z), (1.4, 0.03, 0.1), DARK)
    for sx in (-1, 1):
        box(b, (sx * 0.85, DECK + 0.46, (e0 + e1) / 2), (0.08, 0.04, e1 - e0 - 0.2), DARK)   # lifting rails
    mo.cyl(b, (1.0, DECK + 0.95, e0 + 0.2), 0.08, 1.1, DARK, sides=8)
    mo.cyl(b, (1.0, DECK + 1.52, e0 + 0.2), 0.09, 0.06, "black", sides=8)
    # the propeller tunnels at the stern (waterjets): a duct, the prop's blades, a rudder each
    for sx in (-1, 1):
        x = sx * 0.55
        mo.cyl(b, (x, 0.85, 3.05), 0.27, 0.35, DARK, sides=12, axis="z", caps=False)
        mo.cyl(b, (x, 0.85, 3.0), 0.21, 0.02, "black", sides=12, axis="z")
        box(b, (x, 0.85, 3.08), (0.4, 0.06, 0.02), "steel_light")                     # the prop's blades
        box(b, (x, 0.85, 3.08), (0.06, 0.4, 0.02), "steel_light")
        box(b, (x, 0.75, 3.32), (0.04, 0.4, 0.22), DARK)


def armor(b, rng):
    # side skirts over the wheels: three plates a side, bolted along the top and bottom
    for sx in (-1, 1):
        x = sx * 1.61
        for z in WHEEL_Z:
            box(b, (x, 1.02, z), (0.05, 0.42, 1.45), STEEL)
            bolts(b, (x, 1.18, z - 0.62), (x, 1.18, z + 0.62), 5, 0, sx)
            bolts(b, (x, 0.88, z - 0.62), (x, 0.88, z + 0.62), 5, 0, sx)
        # plates along the hull's upper sides by the cab and the bed
        box(b, (sx * 1.255, 1.33, -0.1), (0.04, 0.2, 5.2), STEEL)
    # the bow's trim vane: a ribbed plate folded back over the raked bow
    vane = math.degrees(math.atan2(0.43, 0.6))
    box(b, (0, 1.32, -3.42), (2.0, 0.05, 0.62), STEEL, pitch=-vane + 0.0)
    for x in (-0.7, 0.0, 0.7):
        box(b, (x, 1.36, -3.42), (0.05, 0.07, 0.6), DARK, pitch=-vane)
    for sx in (-1, 1):
        box(b, (sx * 1.0, 1.42, -3.08), (0.08, 0.14, 0.14), DARK)                     # its hinges
    # the cab: extra plates on the front slope's sides, bars over the windscreen and side windows, a roof lip
    z0, z1 = CAB_Z
    slope = math.degrees(math.atan2(CAB_TOP - (DECK + 0.62), 0.75))
    mid_z, mid_y = z0 + 0.375 - 0.06, (CAB_TOP + DECK + 0.62) / 2 + 0.06
    for k in range(-4, 5):
        box(b, (k * 0.24, mid_y, mid_z), (0.03, 0.66, 0.03), DARK, pitch=90 - slope)
    box(b, (0, mid_y + 0.3, mid_z - 0.06), (2.1, 0.04, 0.04), DARK)
    for sx in (-1, 1):
        x = sx * (CAB_HW + 0.045)
        for z in (-1.8, -1.65, -1.5, -1.35):
            box(b, (x, 2.28, z), (0.03, 0.5, 0.03), DARK)
        box(b, (sx * (CAB_HW + 0.02), 1.75, (z0 + z1) / 2 + 0.25), (0.04, 0.45, 1.9), STEEL)   # lower door plates
        bolts(b, (sx * (CAB_HW + 0.04), 1.92, z0 + 0.5), (sx * (CAB_HW + 0.04), 1.92, z1 - 0.1), 6, 0, sx)
        box(b, (sx * (CAB_HW - 0.02), CAB_TOP + 0.09, (z1 + z0 + 0.75) / 2), (0.06, 0.18, z1 - z0 - 0.75), STEEL)
    box(b, (0, CAB_TOP + 0.09, z1 - 0.03), (2.2, 0.18, 0.06), STEEL)
    box(b, (0, CAB_TOP + 0.09, z0 + 0.78), (2.2, 0.18, 0.06), STEEL)
    # stern: a plate over the propeller tunnels
    box(b, (0, 1.25, 3.24), (2.1, 0.3, 0.05), STEEL)
    bolts(b, (-0.95, 1.25, 3.27), (0.95, 1.25, 3.27), 7, 2, 1)


def radio(b, rng):
    z1 = CAB_Z[1]
    # the radio set on the cab roof: a case with dials, a handset on a cord
    box(b, (0.45, CAB_TOP + 0.17, -0.95), (0.55, 0.34, 0.4), "olive_dark")
    box(b, (0.45, CAB_TOP + 0.2, -0.744), (0.45, 0.2, 0.012), "black")
    for x in (0.3, 0.42, 0.54):
        mo.cyl(b, (x, CAB_TOP + 0.2, -0.735), 0.03, 0.02, "bone", sides=6, axis="z")
    box(b, (0.6, CAB_TOP + 0.36, -0.95), (0.06, 0.04, 0.3), DARK)
    # two whip aerials on sprung bases at the cab's back corners, raked back
    for sx, h in ((-1, 1.9), (1, 1.6)):
        x = sx * 0.95
        mo.cyl(b, (x, CAB_TOP + 0.08, z1 - 0.15), 0.07, 0.16, DARK, sides=8)
        mo.cyl(b, (x, CAB_TOP + 0.22, z1 - 0.15), 0.035, 0.14, "black", sides=6)
        top = (x, CAB_TOP + 0.29 + h, z1 - 0.15 + h * 0.2)
        mid = (x, CAB_TOP + 0.29 + h / 2, z1 - 0.15 + h * 0.1)
        b.box(mid, (0.025, h, 0.025), pitch=math.degrees(math.atan2(0.2, 1.0)), style=lambda n, m, q: ("black", uv_world(1.0)))
        box(b, top, (0.05, 0.05, 0.05), "black")
    # the searchlight on a post, the cable along the roof
    mo.cyl(b, (-0.8, CAB_TOP + 0.15, -2.05), 0.04, 0.3, DARK, sides=6)
    mo.cyl(b, (-0.8, CAB_TOP + 0.38, -2.1), 0.16, 0.26, DARK, sides=10, axis="z")
    mo.cyl(b, (-0.8, CAB_TOP + 0.38, -2.24), 0.13, 0.02, "bone", sides=10, axis="z")
    box(b, (0.45, CAB_TOP + 0.015, -0.66), (0.04, 0.03, 0.2), "black")
    box(b, (0.7, CAB_TOP + 0.015, -0.57), (0.5, 0.03, 0.04), "black")


def supplies(b, rng):
    z0, z1 = BED_Z
    y = DECK + 0.02
    # jerry cans in a row against the cab, strapped
    for k in range(6):
        x = -0.95 + k * 0.33
        box(b, (x, y + 0.3, z0 + 0.25), (0.17, 0.6, 0.4), "red" if k % 3 else "olive")
        box(b, (x, y + 0.63, z0 + 0.15), (0.06, 0.06, 0.1), DARK)                      # caps
    box(b, (0, y + 0.42, z0 + 0.46), (2.1, 0.05, 0.02), "black")                       # strap
    # crates, stacked, and ration cartons
    box(b, (-0.62, y + 0.25, 0.55), (0.9, 0.5, 0.7), "wood", tile=1.0)
    box(b, (-0.62, y + 0.62, 0.5), (0.7, 0.24, 0.55), "wood_dark", tile=1.0)
    for i, (x, z) in enumerate(((0.35, 0.25), (0.8, 0.25), (0.35, 0.7))):
        box(b, (x, y + 0.18, z), (0.42, 0.36, 0.4), "cardboard", tile=1.0)
    box(b, (0.58, y + 0.47, 0.42), (0.42, 0.22, 0.4), "cardboard", tile=1.0)
    # water: blue jugs in a crate
    box(b, (0.6, y + 0.12, 1.4), (0.8, 0.24, 0.6), "wood_light", tile=1.0)
    for x in (0.38, 0.6, 0.82):
        for z in (1.25, 1.55):
            mo.cyl(b, (x, y + 0.36, z), 0.09, 0.28, "blue", sides=8)
    # the med case: olive with a bone band (no cross)
    box(b, (-0.6, y + 0.15, 1.45), (0.6, 0.3, 0.42), "olive_dark")
    box(b, (-0.6, y + 0.15, 1.45), (0.61, 0.08, 0.43), "bone")
    # a tarp bundle on top of the crates and a coil of rope
    box(b, (-0.55, y + 0.86, 0.75), (1.0, 0.26, 0.9), "dbr_canvas", yaw=4.0, tile=1.0)
    mo.cyl(b, (0.0, y + 0.05, 1.55), 0.18, 0.1, "wood_light", sides=10)
    # the spare wheel on the engine deck, a shovel, more cans on the stern
    mo.cyl(b, (-0.45, DECK + 0.55, 2.5), WHEEL_R * 0.92, 0.3, TYRE, sides=14, cap_mat="black")
    mo.cyl(b, (-0.45, DECK + 0.71, 2.5), 0.26, 0.03, PAINT, sides=10)
    box(b, (0.55, DECK + 0.48, 2.7), (0.12, 0.04, 0.9), "wood")
    box(b, (0.55, DECK + 0.48, 3.2), (0.22, 0.03, 0.22), DARK)
    for x in (0.4, 0.75):
        box(b, (x, 1.1, 3.3), (0.3, 0.42, 0.14), "red")
    # the roof rack on the cab, a bundle and two boxes on it
    for x in (-0.95, 0.95):
        box(b, (x, CAB_TOP + 0.1, -1.95), (0.05, 0.05, 1.0), DARK)
    for z in (-2.4, -1.5):
        box(b, (0, CAB_TOP + 0.1, z), (1.95, 0.05, 0.05), DARK)
    box(b, (0.25, CAB_TOP + 0.25, -1.95), (1.1, 0.26, 0.8), "dbr_canvas", yaw=-3.0, tile=1.0)


DRAW = {"frame": frame, "engine": engine, "armor": armor, "radio": radio, "supplies": supplies}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    textures, mat_info = {}, {}
    for kit, painter in mb.KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"), painter,
                                         random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, kit == "glass")
    cells = mb.kit_atlas()
    total = 0
    for part in PARTS:
        b = Builder()
        DRAW[part](b, random.Random("truck " + part))
        out = os.path.join(OUT_DIR, f"truck_{part}.glb")
        mb.write_glb(out, b, textures, mat_info, atlas=cells)
        mb.set_import_script(out)
        tris = sum(len(f) - 2 for f in b.faces)
        total += tris
        print(f"truck_{part}: {tris} triangles")
    print(f"truck total: {total} triangles")


if __name__ == "__main__":
    main()
