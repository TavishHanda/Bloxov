"""Riptide shore art, pass 3a (owner 2026-11-20: "keep going with the art pass", rooms built up, roofs reachable):
`north_point`. Origin (-110, 0, -145); like make_riptide_plaza.py this works in world metres, and it borrows that
script's wall, band and frame code (its module settings are swapped for this model's while it runs).

The cannery (pale green cladding over a dark plinth; inside, white panels, concrete floor, high-bay lamps, the canning
lines and cookers, the office deck's rooms, the cold store and the locker room under it), the lighthouse (white, a red
band at the top), the fuel depot's round tanks inside the bund wall, the sheds on the north street (grey block), the
rocks along the shore.

    python3 art_source/scripts/make_riptide.py north_point
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_riptide as R          # noqa: E402
import make_riptide_quay as Q     # noqa: E402
import make_riptide_plaza as P    # noqa: E402  (walls, bands, frames, furniture facing; the rs_* kits)
import make_building as mb        # noqa: E402
import bake_light                 # noqa: E402
from make_building import Canvas, Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, flat, cyl, KIT   # noqa: E402

ROOT = mb.ROOT
OX, OZ = -110.0, -145.0
SHORE = 2.5
DECK = SHORE + 4.5

BUILDINGS = {
    "cannery": ([(-142.0, -96.0, -166.0, -130.0)], "rs_clad", "rip_panel", "rq_conc", "rip_steel_in", "rq_conc"),
    "lighthouse": ([(-65.0, -59.0, -161.0, -155.0)], "rip_white", "rip_white", "rq_conc", "rq_conc", "rq_conc"),
    "nshed1": ([(-150.0, -136.0, -128.0, -118.0)], "rs_block_grey", "rip_panel", "rq_conc", "rip_ceiling", "rq_conc"),
    "nshed2": ([(-116.0, -100.0, -122.0, -112.0)], "rs_block_grey", "rip_panel", "rq_conc", "rip_ceiling", "rq_conc"),
    "nshed3": ([(-70.0, -58.0, -126.0, -114.0)], "rs_block_grey", "rip_panel", "rq_conc", "rip_ceiling", "rq_conc"),
}
TOPS = {"cannery": SHORE + 10.0, "lighthouse": SHORE + 14.0, "nshed1": SHORE + 4.0, "nshed2": SHORE + 5.0,
        "nshed3": SHORE + 4.5}
TANKS = [(-86.0, -150.0), (-86.0, -136.0), (-74.0, -143.0)]

mb.PALETTE.update({
    "rs_clad": "7d8a80", "rs_clad_dark": "6f7b72", "rs_clad_light": "89968c",
    "rs_rock": "6d6a63", "rs_rock_dark": "5b5852", "rs_rock_light": "7b7870", "rs_lichen": "77755a",
    "rs_tank": "a3a49e", "rs_tank_dark": "93948e", "rs_tank_light": "afb0aa",
})


def paint_clad(rng):
    """Profiled cladding sheets, a rib every 25 cm, faded paint, rust at the laps."""
    c = Canvas(64, 64, "rs_clad")
    c.noise(0, 0, 64, 64, ["rs_clad_dark", "rs_clad_light"], 0.1, rng)
    for x in range(0, 64, 8):
        for y in range(64):
            c.put(x, y, "rs_clad_dark")
            c.put(x + 1, y, "rs_clad_light")
    for y in (0, 32):
        for x in range(64):
            c.put(x, y, "rs_clad_dark")
    R._streaks(c, ["rp_rust", "rs_clad_dark"], 7, rng, starts=(31, 63), length=(4, 12))
    return c


def paint_rock(rng):
    c = Canvas(64, 64, "rs_rock")
    c.noise(0, 0, 64, 64, ["rs_rock_dark", "rs_rock_light"], 0.3, rng)
    c.blotch(["rs_rock_dark", "rs_rock_light", "rs_lichen"], 14, rng, size=(3, 9))
    for _ in range(6):
        x, y = rng.randrange(64), rng.randrange(64)
        for k in range(rng.randrange(6, 18)):
            c.put(x % 64, y % 64, "rx_black")
            x += rng.choice((-1, 0, 1))
            y += 1
    return c


def paint_tank(rng):
    """A storage tank's welded courses (1 m tall plates), pale paint, rust running from the seams."""
    c = Canvas(64, 64, "rs_tank")
    c.noise(0, 0, 64, 64, ["rs_tank_dark", "rs_tank_light"], 0.1, rng)
    for y in (0, 32):
        for x in range(64):
            c.put(x, y, "rs_tank_dark")
    for x0 in (0, 40):
        for y in range(0, 32):
            c.put(x0, y, "rs_tank_dark")
    for x0 in (20, 52):
        for y in range(32, 64):
            c.put(x0, y, "rs_tank_dark")
    R._streaks(c, ["rp_rust", "rs_tank_dark"], 10, rng, starts=(31, 63), length=(4, 14))
    return c


KIT.update({"rs_clad": paint_clad, "rs_rock": paint_rock, "rs_tank": paint_tank})


def top_of(kind):
    return TOPS.get(kind, 99.0)


def band_list(kind, outside):
    if kind == "lighthouse":
        return [(-99.0, SHORE + 0.5, "rs_plinth"), (SHORE + 0.5, SHORE + 12.6, "rip_white"), (SHORE + 12.6, 99.0, "rip_red")]
    return [(-99.0, SHORE + 0.6, "rs_plinth"), (SHORE + 0.6, 99.0, outside)]


def use_plaza_helpers():
    """Point make_riptide_plaza's wall / band / frame code at this model."""
    P.OX, P.OZ = OX, OZ
    P.BUILDINGS = BUILDINGS
    P.top_of = top_of
    P.band_list = band_list


def north_decals(rng):
    real = R.Atlas
    R.Atlas = lambda size=256: real(1024)
    try:
        a = R.tower_decals(rng)            # (the furniture's drawers, screens and the NO SMOKING sign)
    finally:
        R.Atlas = real
    for name in ("CANNERY", "COLD STORE", "LOCKERS", "OFFICE", "FUEL DEPOT"):
        w, h, p = R._sign(name, "rw_white", "rx_black", 3 if name in ("CANNERY", "FUEL DEPOT") else 2)
        a.add("n_" + name, w, h, p)
    return a


def sign(m, name, n, at, a_mid, y, width):
    u0, v0, u1, v1 = m.decals.regions[name]
    h = width * (v1 - v0) / (u1 - u0)
    if n[2]:
        flat(m.b, n, at - OZ + n[2] * 0.015, a_mid - OX - width / 2, a_mid - OX + width / 2, y, y + h, "decals", m.d(name))
    else:
        flat(m.b, n, at - OX + n[0] * 0.015, a_mid - OZ - width / 2, a_mid - OZ + width / 2, y, y + h, "decals", m.d(name))


# ------------------------------------------------------------------------------------------------ pieces
def rock(m, row):
    m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else ("rs_rock", uv_world(1.0)), yaw=row["yaw"])


def tanks(m):
    """Each tank (an octagon of two 9 m squares for collision) drawn round: 16 sides, r 4.75, a shallow cone of a roof,
    a rail round its top, a ladder cage up the side, a dark band of pipework at its foot."""
    b = m.b
    for x, z in TANKS:
        c = (x - OX, SHORE + 5.0, z - OZ)
        cyl(b, c, 4.75, 10.0, "rs_tank", "rip_roof", sides=16, caps=(False, True))
        cyl(b, (c[0], SHORE + 10.2, c[2]), 2.4, 0.4, "rip_roof", "rip_roof", sides=12, caps=(False, True))   # the crown
        for k in range(16):                      # the rail round the top: posts
            import math
            a = 2 * math.pi * (k + 0.5) / 16
            px, pz = c[0] + math.cos(a) * 4.6, c[2] + math.sin(a) * 4.6
            m.box((px, SHORE + 10.55, pz), (0.06, 1.1, 0.06), mat("rip_yellow"), cull=False)
        cyl(b, (c[0], SHORE + 11.05, c[2]), 4.62, 0.08, "rip_yellow", "rip_yellow", sides=16, caps=(False, False))
        # the ladder cage on the side facing the bund's gate (south-west)
        lx, lz = c[0] - 3.45, c[2] + 3.45
        for dx, dz in ((-0.25, 0.25), (0.25, -0.25)):
            m.box((lx + dx, SHORE + 6.15, lz + dz), (0.08, 7.7, 0.08), mat("rip_yellow"), cull=False)   # (starts over head height)
        for k in range(3, 10):
            m.box((lx, SHORE + 0.3 + k, lz), (0.6, 0.08, 0.6), mat("rip_yellow"), yaw=45, cull=False)
        cyl(b, (c[0], SHORE + 0.3, c[2]), 4.8, 0.6, "rip_iron", None, sides=16, caps=(False, False))


def canline(m, row):
    """A canning line: a steel frame, a dark belt along the top, yellow guards, the cans riding it."""
    c, s = row["pos"], row["size"]
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    m.box((c[0], (y0 + y1 - 0.5) / 2, c[2]), (s[0], s[1] - 0.5, s[2]),
          lambda n, mid, q: None if n[1] < -0.7 else ("rq_rubber" if n[1] > 0.7 else "rip_machine"))
    for zz in (z0 + 0.06, z1 - 0.06):          # guards along both sides, posts every 2 m
        m.box((c[0], y1 - 0.12, zz), (s[0], 0.08, 0.06), mat("rip_yellow"), cull=False)
        for k in range(int(s[0] // 2) + 1):
            xx = min(x1 - 0.04, x0 + 0.04 + 2.0 * k)
            m.box((xx, y1 - 0.31, zz), (0.06, 0.38, 0.06), mat("rip_yellow"), cull=False)
    rng = random.Random(str(c))
    for k in range(18):                         # cans in a few rows on the belt
        xx = x0 + 0.4 + k * (s[0] - 0.8) / 17
        for zz in (c[2] - 0.35, c[2], c[2] + 0.35):
            if rng.random() < 0.6:
                m.box((xx, y1 - 0.5 + 0.07, zz), (0.1, 0.14, 0.1), mat("rip_bright"), cull=False)


def cooker(m, row):
    """A retort: a long steel drum on two saddles, a hatch at one end, a gauge pipe on top."""
    c, s = row["pos"], row["size"]
    r = s[2] / 2 - 0.05                      # (as wide as its box; up on saddles so it fills the box's height too)
    yc = c[1] + s[1] / 2 - r - 0.05
    cyl(m.b, (c[0], yc, c[2]), r, s[0] - 0.2, "rip_pipe", "rip_iron", axis="x", sides=12)
    for dx in (-s[0] / 2 + 1.2, s[0] / 2 - 1.2):
        base = c[1] - s[1] / 2
        m.box((c[0] + dx, (base + yc) / 2, c[2]), (0.4, yc - base, s[2] - 0.2), mat("rip_iron"), cull=False)
    m.box((c[0] + s[0] / 2 - 1.5, yc + r, c[2]), (0.5, 0.1, 0.5), mat("rip_iron"), cull=False)     # (a hatch on top)


def details(m):
    b = m.b
    for name, info in BUILDINGS.items():
        if info[5]:
            for x0, x1, z0, z1 in info[0]:
                p = [P.W((x0, SHORE + 0.005, z0)), P.W((x1, SHORE + 0.005, z0)), P.W((x1, SHORE + 0.005, z1)),
                     P.W((x0, SHORE + 0.005, z1))]
                b.poly([p[0], p[3], p[2], p[1]], (0, 1, 0), info[5], uv_world())
    X = lambda x: x - OX    # noqa: E731
    Z = lambda z: z - OZ    # noqa: E731
    # high-bay lamps over the hall, lamps under the deck, in the deck offices and in the sheds
    for x in range(-126, -97, 8):
        for z in (-160.0, -150.0, -140.0):
            R.t_lamp(m, X(x), SHORE + 10.0, Z(z), 1.6, 0.5)
    for z in (-164.0, -154.0, -138.0):
        R.t_lamp(m, X(-138.0), DECK - 0.25, Z(z))
    for z in (-161.0, -135.0):
        R.t_lamp(m, X(-138.0), DECK + 2.75, Z(z))
    for (x0, x1, z0, z1), key in zip([BUILDINGS[k][0][0] for k in ("nshed1", "nshed2", "nshed3")], ("nshed1", "nshed2", "nshed3")):
        R.t_lamp(m, X((x0 + x1) / 2), TOPS[key], Z((z0 + z1) / 2))
    # signs
    sign(m, "n_CANNERY", (0, 0, 1), -130.0 + 0.15, -121.0, SHORE + 7.6, 7.0)
    sign(m, "n_CANNERY", (1, 0, 0), -96.0 + 0.15, -147.0, SHORE + 7.8, 5.0)
    sign(m, "n_COLD STORE", (1, 0, 0), -134.0 + 0.15, -164.0, SHORE + 2.55, 1.2)
    sign(m, "n_LOCKERS", (1, 0, 0), -134.0 + 0.15, -154.0, SHORE + 2.55, 1.0)
    sign(m, "n_OFFICE", (0, 0, 1), -156.0 + 0.15, -136.0, DECK + 2.5, 0.9)
    sign(m, "n_OFFICE", (0, 0, -1), -140.0 - 0.15, -138.0, DECK + 2.5, 0.9)
    sign(m, "n_FUEL DEPOT", (0, 0, 1), -128.0 + 0.15, -86.0, SHORE + 0.15, 2.2)
    sign(m, "no_smoking", (0, 0, 1), -128.0 + 0.15, -74.0, SHORE + 0.2, 0.9)


def build_north(name="north_point"):
    use_plaza_helpers()
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    assert data.get("map") == "riptide", f"{name}: not a Riptide model"
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = north_decals(random.Random(name))
    decal_png = os.path.join(ROOT, "art_source", "textures", name + "_decals.png")
    if os.path.exists(decal_png):
        os.remove(decal_png)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    m.rng = random.Random(name)
    P._M[0] = m
    R._against = P.against
    outside = []
    for row in data["boxes"]:
        kind = row.get("kind") or ""
        if kind == "pallets":
            R.t_prop(m, dict(row, kind="crates"))
        elif kind in P.PROP_KINDS or kind in ("tool_cab", "drums") or kind.startswith("chair_"):
            R.t_prop(m, row)
        elif kind == "rock":
            rock(m, row)
        elif kind == "tank":
            pass                                   # (drawn round, below)
        elif kind == "bund":
            m.box(row["pos"], row["size"], Q.concrete_style)
        elif kind == "canline":
            canline(m, row)
        elif kind == "cooker":
            cooker(m, row)
        elif kind in ("cannery", "lighthouse", "nshed"):
            P.building_piece(m, row, kind, outside)
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"), yaw=row["yaw"], pitch=row["pitch"])
    P.outside_bands(m, outside)
    for o in data["openings"]:
        P.frame(m, o)
    tanks(m)
    details(m)
    b = m.b
    bake_light.CELL = 3.0
    bake_light.DARK = 0.6
    bake_light.bake(b, [r for r in data["boxes"] if not r["pitch"] and not r["yaw"]])
    cells = R.riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris
