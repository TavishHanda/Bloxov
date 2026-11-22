"""Riptide shore art, pass 3b (owner 2026-11-20: "keep going with the art pass"; the tester's "badly placed windows"):
`south_port`. Origin (-90, 0, 110); like make_riptide_north.py this works in world metres and borrows
make_riptide_plaza.py's wall, band and frame code (its module settings are swapped for this model's while it runs).

The grain terminal (the slip-formed silo bank and its conveyor, the headhouse, the grain store in buff block with its
heaps of grain, the hopper wagons on the siding), the shipyard (the unfinished hull on the slipway with its frames,
half deck and scaffold, the fab shed in corrugated sheet, the block workshop, the plank boathouse, timber stacks) and
the three transit sheds on the quay (corrugated sheet, pallets inside). Uses only the textures already on Riptide's
sheet.

    python3 art_source/scripts/make_riptide.py south_port
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_riptide as R          # noqa: E402
import make_riptide_quay as Q     # noqa: E402
import make_riptide_plaza as P    # noqa: E402  (walls, bands, frames; the rs_* kits)
import make_riptide_north as N    # noqa: E402  (rs_clad and the sign helper)
import make_building as mb        # noqa: E402
import bake_light                 # noqa: E402
from make_building import Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, KIT   # noqa: E402

ROOT = mb.ROOT
OX, OZ = -90.0, 110.0
SHORE = 2.5

# name: (footprints [(x0, x1, z0, z1)], outside, walls inside, floor, ceiling, ground floor overlay)
BUILDINGS = {
    "grainstore": ([(-112.0, -72.0, 64.0, 92.0)], "rs_block_buff", "rq_conc", "rq_conc", "rip_steel_in", "rq_conc"),
    "headhouse": ([(-46.0, -38.0, 42.0, 56.0)], "rq_conc", "rq_conc", "rq_conc", "rq_conc", None),
    "fabshed": ([(-152.0, -120.0, 104.0, 128.0)], "rs_clad", "rq_corr", "rq_conc", "rip_steel_in", "rq_conc"),
    "workshop": ([(-104.0, -84.0, 106.0, 124.0)], "rs_block_grey", "rip_panel", "rq_conc", "rip_ceiling", "rq_conc"),
    "tshed1": ([(-60.0, -42.0, -112.0, -72.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", None),
    "tshed2": ([(-60.0, -42.0, -64.0, -24.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", None),
    "tshed3": ([(-62.0, -44.0, 64.0, 104.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", None),
    # (art pass 4) the small buildings along the rail corridor and the south streets, the breakwater's huts
    "weighbridge": ([(-152.0, -138.0, -44.0, -34.0)], "rs_block_buff", "rip_panel", "rip_lino", "rip_ceiling", "rip_lino"),
    "railshed": ([(-152.0, -136.0, 36.0, 56.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", "rq_conc"),
    "signalbox": ([(-150.0, -138.0, 72.0, 84.0)], "rs_block_buff", "rip_panel_g", "rip_lino", "rip_ceiling", "rip_lino"),
    "laneshed": ([(-128.0, -114.0, 94.0, 102.0)], "rs_block_grey", "rq_conc", "rq_conc", "rip_ceiling", "rq_conc"),
    "sgarage": ([(-80.0, -66.0, 126.0, 136.0)], "rq_corr", "rq_corr", "rq_conc", "rip_steel_in", "rq_conc"),
    "sshed": ([(-100.0, -86.0, 164.0, 176.0)], "rs_block_grey", "rq_conc", "rq_conc", "rip_ceiling", "rq_conc"),
    "bargeoffice": ([(-58.0, -44.0, 110.0, 122.0)], "rs_sandstone", "rip_panel", "rip_lino", "rip_ceiling", "rip_lino"),
    "signalhut": ([(-2.0, 8.0, -129.2, -124.0)], "rs_block_grey", "rip_panel", "rq_conc", "rip_ceiling", None),
    "wheelhouse": ([(61.5, 67.5, -123.0, -117.0)], "rip_white", "rip_panel", "rip_wood", "rip_ceiling", None),
    # (art pass 5) the bosun's hut on the forecastle, the ship loader's tower against the ship's side
    "bosun": ([(44.0, 52.0, -102.0, -95.0)], "rip_white", "rip_steel_in", "rip_deck", "rip_steel_in", None),
    "loader": ([(21.5, 29.5, 42.0, 56.0)], "rq_corr", "rq_conc", "rq_conc", "rip_steel_in", None),
}
TOPS = {"grainstore": SHORE + 8.0, "headhouse": 34.0, "fabshed": SHORE + 12.0, "workshop": SHORE + 5.0,
        "tshed1": SHORE + 7.0, "tshed2": SHORE + 7.0, "tshed3": SHORE + 7.0, "weighbridge": SHORE + 4.0,
        "railshed": SHORE + 6.0, "signalbox": SHORE + 7.0, "laneshed": SHORE + 4.0, "sgarage": SHORE + 5.0,
        "sshed": SHORE + 4.0, "bargeoffice": SHORE + 5.0, "signalhut": SHORE + 3.0, "wheelhouse": SHORE + 2.3,
        "bosun": 7.0 + 2.6, "loader": 14.0 + 3.2}
LEVELS = [SHORE, 5.0, 8.0, 11.0, 14.0]        # (floors a doorway can stand on: their openings get no sill)


def top_of(kind):
    return TOPS.get(kind, 99.0)


def band_list(kind, outside):
    if kind == "headhouse":
        return [(-99.0, SHORE + 0.5, "rs_plinth"), (SHORE + 0.5, 99.0, "rq_conc")]
    if outside == "rq_corr" or outside == "rs_clad":
        return [(-99.0, SHORE + 0.9, "rs_plinth"), (SHORE + 0.9, 99.0, outside)]   # (sheet on a block plinth)
    return [(-99.0, SHORE + 0.5, "rs_plinth"), (SHORE + 0.5, 99.0, outside)]


def use_plaza_helpers():
    P.OX, P.OZ = OX, OZ
    P.BUILDINGS = BUILDINGS
    P.top_of = top_of
    P.band_list = band_list
    P.TOWER_FLOORS = LEVELS
    P.TOWER_TOP = 34.0
    N.OX, N.OZ = OX, OZ


SIGN_NAMES = ("GRAIN STORE", "FAB SHED", "WORKSHOP", "BOATHOUSE", "SHED 1", "SHED 2", "SHED 3", "GRAIN TERMINAL",
              "WEIGHBRIDGE", "RAIL SHED", "SIGNAL BOX", "GARAGE", "BARGE OFFICE")


def south_decals(rng):
    real = R.Atlas
    R.Atlas = lambda size=256: real(1024)
    try:
        a = R.tower_decals(rng)
    finally:
        R.Atlas = real
    for name in SIGN_NAMES:
        w, h, p = R._sign(name, "rw_white", "rx_black", 3)
        a.add("n_" + name, w, h, p)
    for kind, line in R.CONTAINER_LINES.items():          # (art pass 4: the loose containers, as on the terminal)
        w, h, p = R._stencil(line, 3, "rw_light", random.Random(line), chip=0.1)
        a.add("line_" + kind, w, h, p)
    for kind, base in (("container_a", "rc_a"), ("container_b", "rc_b"), ("container_c", "rc_c")):
        a.add("doors_" + kind, 77, 83, R._door_decal(base))
    return a


# ------------------------------------------------------------------------------------------------ pieces
def silo(m, row):
    """A slip-formed concrete bin: bare concrete, a dark band of a walkway round its top, the roof felted."""
    c, s = row["pos"], row["size"]
    top = c[1] + s[1] / 2

    def style(n, mid, q):
        if n[1] < -0.7:
            return None
        if n[1] > 0.7:
            return "rip_roof"
        return "rq_conc"
    m.box(c, s, style)
    m.box((c[0], top - 0.6, c[2]), (s[0] + 0.12, 0.5, s[2] + 0.12),
          lambda n, mid, q: None if abs(n[1]) > 0.7 else "rip_iron")     # (the band round the top)
    for k in range(1, 6):                                                  # (pour lines every 5 m)
        y = SHORE + 5.0 * k
        m.box((c[0], y, c[2]), (s[0] + 0.04, 0.06, s[2] + 0.04), lambda n, mid, q: None if abs(n[1]) > 0.7 else "rs_plinth")
    # the joint between this bin and the next (west), a dark recess down the long faces
    m.box((c[0] - s[0] / 2, c[1] - 0.6, c[2]), (0.3, s[1] - 1.2, s[2] + 0.06),
          lambda n, mid, q: "rs_plinth" if abs(n[2]) > 0.7 else None)


def conveyor(m, row):
    """The covered conveyor over the silos to the headhouse: corrugated sides, a roof, iron underneath."""
    m.box(row["pos"], row["size"], lambda n, mid, q: "rip_iron" if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rq_corr"))


def wagon(m, row):
    """A hopper wagon: the body in the container colour, iron frame and bogies under it, hoppers below the body."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    m.box((c[0], (y0 + 1.2 + y1) / 2, c[2]), (s[0], y1 - y0 - 1.2, s[2]),
          lambda n, mid, q: "rip_iron" if n[1] > 0.7 else ("rip_cont_c" if n[1] > -0.7 else None))
    m.box((c[0], y0 + 0.6, c[2]), (s[0] - 0.4, 1.2, s[2] - 0.3), lambda n, mid, q: None if n[1] < -0.7 else "rip_iron")


def heap(m, row):
    m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else "rip_card", yaw=row["yaw"])


def slip_hull(m, row):
    """The unfinished hull's plating: painted hull outside, bare steel inside, the boot topping low down."""
    c, s = row["pos"], row["size"]
    hx, hz = -85.0 - OX, 149.0 - OZ          # (the hull's middle, in the model's space)

    def style(n, mid, q):
        if n[1] < -0.7:
            return None
        if n[1] > 0.7:
            return "rip_iron"
        out = n[0] * (mid[0] - hx) + n[2] * (mid[2] - hz) > 0
        if not out:
            return "rip_steel_in"
        return "rip_boot" if mid[1] < SHORE + 1.2 else "rip_hull"
    m.box(c, s, style)


def boathouse(m, row):
    c, s = row["pos"], row["size"]
    if s[1] < 0.5:                       # (the floor and the roof)
        m.box(c, s, lambda n, mid, q: ("rip_roof" if c[1] > SHORE + 2.0 else "rq_plank") if n[1] > 0.7 else
              ("rq_plank" if n[1] < -0.7 and c[1] > SHORE + 2.0 else (None if n[1] < -0.7 else "rq_plank")))
        return
    m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else "rq_plank")


def machine(m, row):
    c, s = row["pos"], row["size"]
    m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_iron" if n[1] > 0.7 else "rip_machine"))
    m.box((c[0], c[1] + s[1] / 2 - 0.1, c[2] + s[2] / 2 - 0.05), (s[0], 0.08, 0.06), mat("rip_yellow"), cull=False)


BOXCAR = {"rust": "rip_cont_a", "container_c": "rip_cont_c", "container_b": "rip_cont_b"}


def boxcar(m, row):
    """(art pass 4) A freight wagon on the rail line: a ribbed box body, a dark roof, the iron underframe and bogies
    under it, a door half way along each side."""
    c, s = row["pos"], row["size"]
    body = BOXCAR.get(row["colour"], "rip_cont_a")
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    m.box((c[0], (y0 + 1.1 + y1) / 2, c[2]), (s[0], y1 - y0 - 1.1, s[2]),
          lambda n, mid, q: "rip_roof" if n[1] > 0.7 else (None if n[1] < -0.7 else (body if abs(n[0]) > 0.7 else "rip_iron")))
    m.box((c[0], y0 + 0.55, c[2]), (s[0] - 0.3, 1.1, s[2] - 0.2), lambda n, mid, q: None if n[1] < -0.7 else "rip_iron")
    for sg in (-1, 1):                                 # the doors
        m.box((c[0] + sg * (s[0] / 2 + 0.02), (y0 + 1.2 + y1 - 0.2) / 2, c[2]), (0.04, y1 - y0 - 1.4, 2.4), mat("rip_iron"), cull=False)


def roof_bit(m, row):
    kind = row["kind"]
    c, s = row["pos"], row["size"]
    if kind == "ac_unit":
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_iron" if n[1] > 0.7 else "rip_machine"))
    elif kind == "vent":
        R.cyl(m.b, c, min(s[0], s[2]) / 2, s[1], "rip_pipe", "rip_iron", sides=8)
    else:
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rs_tank"))


def boat_piece(m, row):
    """(art pass 5) The boats moored round the ship: a painted hull with a dark boot topping at the water, a planked
    or steel deck; the tug red with a white wheelhouse."""
    kind = row["kind"]
    c, s = row["pos"], row["size"]
    y0 = c[1] - s[1] / 2
    if kind == "tug_house":
        m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_roof" if n[1] > 0.7 else "rip_white"))
        return
    if kind == "canopy":
        m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else "rip_iron")
        return
    side = "rip_hull" if kind == "tug_hull" else ("rip_orange" if c[2] + OZ < -110.0 else "rip_white")   # (the pilot cutter orange)
    deck = "rip_deck" if kind == "tug_hull" else "rq_plank"
    boot = y0 + min(0.8, s[1] * 0.4)

    def style(n, mid, q):
        if n[1] > 0.7:
            return deck
        if n[1] < -0.7:
            return None
        return "rip_boot" if mid[1] < boot else side
    cuts = sorted({y0, boot, y0 + s[1]})
    for ya, yb in zip(cuts, cuts[1:]):
        m.box((c[0], (ya + yb) / 2, c[2]), (s[0], yb - ya, s[2]), style)
    # a rubbing strake round the top edge
    m.box((c[0], y0 + s[1] - 0.1, c[2]), (s[0] + 0.1, 0.12, s[2] + 0.1), lambda n, mid, q: None if abs(n[1]) > 0.7 else "rip_iron")


def ramp_rail(m, row):
    """(ship detail pass) A rail down a ramp's open side: its box is a 1 m slab along the slope; drawn as a yellow top
    rail, a mid rail and a kick plate along the slope, with posts every 1.5 m."""
    c, s, yaw, pitch = row["pos"], row["size"], row["yaw"], row["pitch"]
    up = mb.rot((0.0, 1.0, 0.0), yaw, pitch)
    al = mb.rot((0.0, 0.0, 1.0), yaw, pitch)
    h = s[1]
    for off, th, mt in ((h / 2 - 0.04, 0.07, "rip_yellow"), (0.0, 0.05, "rip_yellow"), (-h / 2 + 0.08, 0.16, "rip_iron")):
        m.box((c[0] + up[0] * off, c[1] + up[1] * off, c[2] + up[2] * off), (0.06, th, s[2]), mat(mt), yaw=yaw, pitch=pitch,
              cull=False)
    n = max(2, int(s[2] // 1.5) + 1)
    for k in range(n):
        t = -s[2] / 2 + 0.05 + (s[2] - 0.1) * k / (n - 1)
        p = (c[0] + al[0] * t, c[1] + al[1] * t, c[2] + al[2] * t)
        lo = p[1] - up[1] * h / 2
        hi = p[1] + up[1] * h / 2
        m.box((p[0], (lo + hi) / 2, p[2]), (0.07, hi - lo, 0.07), mat("rip_yellow"), cull=False)


def details(m):
    for name, info in BUILDINGS.items():          # (detail pass) the floors laid over the ground inside
        if info[5]:
            for x0, x1, z0, z1 in info[0]:
                p = [P.W((x0, SHORE + 0.005, z0)), P.W((x1, SHORE + 0.005, z0)), P.W((x1, SHORE + 0.005, z1)),
                     P.W((x0, SHORE + 0.005, z1))]
                m.b.poly([p[0], p[3], p[2], p[1]], (0, 1, 0), info[5], uv_world())
    X = lambda x: x - OX    # noqa: E731
    Z = lambda z: z - OZ    # noqa: E731
    for x in (-104.0, -92.0, -80.0):          # the grain store's high-bay lamps
        for z in (70.0, 86.0):
            R.t_lamp(m, X(x), SHORE + 8.0, Z(z), 1.6, 0.5)
    for x in (-144.0, -128.0):                # the fab shed's
        for z in (110.0, 122.0):
            R.t_lamp(m, X(x), SHORE + 12.0, Z(z), 1.6, 0.5)
    R.t_lamp(m, X(-94.0), SHORE + 5.0, Z(115.0))
    for x0, x1, z0, z1 in [BUILDINGS[k][0][0] for k in ("tshed1", "tshed2", "tshed3")]:
        for z in (z0 + 10.0, z1 - 10.0):
            R.t_lamp(m, X((x0 + x1) / 2), SHORE + 7.0, Z(z), 1.6, 0.5)
    sign = N.sign
    sign(m, "n_GRAIN STORE", (0, 0, 1), 92.0 + 0.15, -100.0, SHORE + 6.4, 5.0)
    sign(m, "n_GRAIN STORE", (0, 0, -1), 64.0 - 0.15, -92.0, SHORE + 6.4, 5.0)
    sign(m, "n_GRAIN TERMINAL", (1, 0, 0), -38.0 + 0.15, 49.0, SHORE + 20.0, 6.0)
    sign(m, "n_FAB SHED", (0, 0, -1), 104.0 - 0.15, -136.0, SHORE + 9.6, 5.0)
    sign(m, "n_FAB SHED", (0, 0, 1), 128.0 + 0.15, -136.0, SHORE + 9.6, 5.0)
    sign(m, "n_WORKSHOP", (0, 0, -1), 106.0 - 0.15, -98.0, SHORE + 3.0, 2.6)
    sign(m, "n_BOATHOUSE", (0, 0, -1), 156.0 - 0.15, -39.0, SHORE + 3.4, 3.2)
    for name, key, side in (("n_WEIGHBRIDGE", "weighbridge", "n"), ("n_RAIL SHED", "railshed", "s"),
                            ("n_SIGNAL BOX", "signalbox", "n"), ("n_GARAGE", "sgarage", "n"),
                            ("n_BARGE OFFICE", "bargeoffice", "n")):
        x0, x1, z0, z1 = BUILDINGS[key][0][0]
        if side == "n":
            sign(m, name, (0, 0, -1), z0 - 0.15, (x0 + x1) / 2 + 3.0, TOPS[key] - 1.2, 2.4)
        else:
            sign(m, name, (0, 0, 1), z1 + 0.15, (x0 + x1) / 2 + 4.0, TOPS[key] - 1.4, 2.8)
    for key in ("weighbridge", "railshed", "signalbox", "laneshed", "sgarage", "sshed", "bargeoffice", "signalhut"):
        x0, x1, z0, z1 = BUILDINGS[key][0][0]
        R.t_lamp(m, X((x0 + x1) / 2), TOPS[key], Z((z0 + z1) / 2))
    for k, (x0, x1, z0, z1) in enumerate([BUILDINGS[k][0][0] for k in ("tshed1", "tshed2", "tshed3")]):
        name = "n_SHED %d" % (k + 1)
        sign(m, name, (0, 0, -1), z0 - 0.15, (x0 + x1) / 2, SHORE + 4.6, 3.6)
        sign(m, name, (0, 0, 1), z1 + 0.15, (x0 + x1) / 2, SHORE + 4.6, 3.6)
        sign(m, name, (1, 0, 0), x1 + 0.15, (z0 + z1) / 2 - 6.0, SHORE + 5.9, 3.0)


def build_south(name="south_port"):
    use_plaza_helpers()
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    assert data.get("map") == "riptide", f"{name}: not a Riptide model"
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = south_decals(random.Random(name))
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
    conts = 0
    for row in data["boxes"]:
        kind = row.get("kind") or ""
        if kind == "pallets":
            R.t_prop(m, dict(row, kind="crates"))
        elif kind == "silo":
            silo(m, row)
        elif kind == "conveyor":
            conveyor(m, row)
        elif kind == "wagon":
            wagon(m, row)
        elif kind == "heap":
            heap(m, row)
        elif kind == "slip_hull":
            slip_hull(m, row)
        elif kind == "slip_frame":
            m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else "rip_steel_in")
        elif kind == "slip_deck":
            m.box(row["pos"], row["size"], lambda n, mid, q: "rip_deck" if n[1] > 0.7 else "rip_steel_in")
        elif kind == "scaffold":
            m.box(row["pos"], row["size"], Q.plank_style, yaw=row["yaw"], pitch=row["pitch"])
        elif kind == "post":
            m.box(row["pos"], row["size"], mat("rip_yellow"))
        elif kind in ("timber",):
            m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else "rq_plank", yaw=row["yaw"])
        elif kind == "machine":
            machine(m, row)
        elif kind == "boathouse":
            boathouse(m, row)
        elif kind in P.PROP_KINDS or kind == "tool_cab" or kind.startswith("chair_"):
            R.t_prop(m, row)
        elif kind == "ramp_rail":
            ramp_rail(m, row)
        elif kind == "boxcar":
            boxcar(m, row)
        elif kind in ("ac_unit", "vent", "roof_tank"):
            roof_bit(m, row)
        elif kind in ("boat_hull", "tug_hull", "tug_house", "canopy"):
            boat_piece(m, row)
        elif kind == "windlass":
            machine(m, row)
        elif kind == "mast":
            m.box(row["pos"], row["size"], mat("rip_white" if row["pos"][0] + OX > 40.0 else "rip_yellow"))
        elif kind == "plate":
            m.box(row["pos"], row["size"], lambda n, mid, q: "rip_deck" if n[1] > 0.7 else "rip_iron")
        elif kind == "seawall":
            m.box(row["pos"], row["size"], lambda n, mid, q: None if n[1] < -0.7 else "rs_rock")
        elif kind == "mole":       # the breakwater: concrete on top, rock below the quay's edge
            m.box(row["pos"], row["size"], lambda n, mid, q: "rq_quay" if n[1] > 0.7 else (None if n[1] < -0.7 else
                  ("rq_conc" if mid[1] > SHORE - 1.0 else "rs_rock")))
        elif kind == "block":
            m.box(row["pos"], row["size"], Q.concrete_style, yaw=row["yaw"])
        elif kind == "fence":
            m.box(row["pos"], row["size"], Q.concrete_style)
        elif kind == "woodpile":
            R.t_prop(m, dict(row, kind="crates"))
        elif row["colour"] in R.CONT_MAT:
            R.container(m, row, conts)
            conts += 1
        elif kind == "tshed":
            x = row["pos"][0] + OX
            z = row["pos"][2] + OZ
            P.building_piece(m, row, "tshed1" if z < -68.0 else ("tshed2" if z < 0 else "tshed3"), outside)
        elif kind in BUILDINGS:
            P.building_piece(m, row, kind, outside)
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"), yaw=row["yaw"], pitch=row["pitch"])
    P.outside_bands(m, outside)
    for o in data["openings"]:
        if o["t"] >= 0.35:                    # (the hull's plating and its frames: cut edges, no frames)
            continue
        P.frame(m, o)
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
