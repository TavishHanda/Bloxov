"""Riptide art step 4 (0.36.24): `site_zero`, the lab in the Leviathan's two lowest decks. Origin (48, 0, 0), the same
as leviathan_hull and below_decks (x across the ship, -18..18; z along it). This script works in world x (OX + x).

A clean corporate containment lab built into a ship: white wall panels with a teal stripe and a dark skirting, pale
vinyl floors, tiled ceilings with lamp panels, teal signs over the doors naming where each goes. Washrooms and the
locker room are tiled; the air plant, the dock, the sub bay and the moon pool's trunk are the ship's own steel; the
incubation hall is dark slate round its four glowing growth tanks (green fluid, nothing inside: store rules) and the
smashed one in the middle. The lining hides the hull's plate inside the lab. Glass (the cleanroom, the cells, the
director's office, the security window, the hall's windows) is the map's breakable panes (gen_riptide.py glaze()):
this model only frames the openings. Furniture is the gray box's boxes with a kind (gen_riptide.py lab(), LAB_PROPS),
each drawn inside its box.

    python3 art_source/scripts/make_riptide.py site_zero
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
from make_building import Canvas, Texture, uv_world   # noqa: E402
from make_riptide import Model, mat, flat, cyl, t_part, t_item, t_lamp, KIT   # noqa: E402

ROOT = mb.ROOT
OX = 48.0
LAB1, LAB2 = -12.25, -18.25
HULL_B = -8.0
SLAB = 0.25
CEIL1 = LAB1 - SLAB              # the lower deck's ceiling
CEIL0 = HULL_B - SLAB            # the dock deck's ceiling (the engine room deck's underside)
HULL_IN = (30.25, 65.75)         # the hull plate's inside faces (world x)
HALL = (36.0, 60.0, 38.0, 62.0)

mb.PALETTE.update({
    "rl_panel": "dfe2df", "rl_panel_dark": "cfd3d0", "rl_panel_light": "e8eae7",
    "rl_tile": "e4e6e3", "rl_tile_grout": "b9bebd",
    "rl_floor": "b7bfc0", "rl_floor_dark": "a8b0b1", "rl_floor_light": "c3cacb",
    "rl_teal": "1f8a85", "rl_teal_dark": "17706c", "rl_teal_light": "3fa8a2",
    "rl_core": "37424b", "rl_core_dark": "2d373f", "rl_core_light": "434f59",
    "rl_epoxy": "26292c", "rl_epoxy_light": "33373b",
    "rl_fluid": "5fc77a", "rl_fluid_dark": "3f9f5c", "rl_fluid_light": "9be8a8",
    "rl_leaf": "4f7d3a", "rl_leaf_dark": "3e6630", "rl_leaf_light": "679a4a",
    "rl_sub": "d8a02a", "rl_locker": "6d8796", "rl_locker_dark": "5d7685",
    "rl_raised": "9aa3a6", "rl_raised_dark": "8a9396",
})


def _plain(base, light, dark, chance=0.08):
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [light, dark], chance, rng)
        return c
    return paint


def paint_lab_panel(rng):
    """Lab wall panels: 1.2 m x 2 m white laminate sheets, a fine seam, very little grime."""
    c = Canvas(64, 64, "rl_panel")
    c.noise(0, 0, 64, 64, ["rl_panel_light", "rl_panel_dark"], 0.04, rng)
    for x in (0, 19, 38, 57):
        for y in range(64):
            c.put(x, y, "rl_panel_dark")
    for x in range(64):
        c.put(x, 0, "rl_panel_dark")
        c.put(x, 32, "rl_panel_dark")
    c.blotch(["rl_panel_dark"], 2, rng, size=(2, 3))
    return c


def paint_lab_tile(rng):
    """White wall and floor tiles (washrooms, the locker room), 25 cm."""
    c = Canvas(64, 64, "rl_tile")
    c.noise(0, 0, 64, 64, ["rl_panel_dark"], 0.03, rng)
    for k in range(0, 64, 4):
        for t in range(64):
            c.put(k, t, "rl_tile_grout")
            c.put(t, k, "rl_tile_grout")
    return c


def paint_lab_floor(rng):
    """Pale grey sheet vinyl, flecked, welded seams every 2 m."""
    c = Canvas(64, 64, "rl_floor")
    c.noise(0, 0, 64, 64, ["rl_floor_light", "rl_floor_dark"], 0.18, rng)
    for t in range(64):
        c.put(0, t, "rl_floor_dark")
        c.put(32, t, "rl_floor_dark")
    c.blotch(["rl_floor_dark"], 3, rng, size=(3, 5))
    return c


def paint_core(rng):
    """The incubation hall: dark slate panels, 1 m, lighter seams."""
    c = Canvas(64, 64, "rl_core")
    c.noise(0, 0, 64, 64, ["rl_core_light", "rl_core_dark"], 0.06, rng)
    for x in (0, 16, 32, 48):
        for y in range(64):
            c.put(x, y, "rl_core_light")
    for x in range(64):
        c.put(x, 0, "rl_core_dark")
        c.put(x, 32, "rl_core_dark")
    return c


def paint_core_floor(rng):
    """The hall's floor: dark epoxy, 1 m grating squares, drains."""
    c = Canvas(64, 64, "rl_core_dark")
    c.noise(0, 0, 64, 64, ["rl_core", "rl_epoxy"], 0.12, rng)
    for k in range(0, 64, 16):
        for t in range(64):
            c.put(k, t, "rl_epoxy")
            c.put(t, k, "rl_epoxy")
    return c


def paint_fluid(rng):
    """A growth tank's green fluid seen through the glass: bubbles rising, darker towards the edges."""
    c = Canvas(64, 64, "rl_fluid")
    c.noise(0, 0, 64, 64, ["rl_fluid_dark", "rl_fluid_light"], 0.08, rng)
    for x in (0, 1, 30, 31, 32, 33, 62, 63):       # (the glass's vertical edges, every 2 m round)
        for y in range(64):
            c.put(x, y, "rl_fluid_dark")
    for _ in range(40):                            # bubbles
        x, y = rng.randrange(2, 62), rng.randrange(0, 63)
        c.put(x, y, "rl_fluid_light")
        c.put(x, y + 1, "rw_light")
    return c


def paint_raised(rng):
    """The server room's raised floor: 60 cm tiles, a few perforated."""
    c = Canvas(64, 64, "rl_raised")
    for k in range(0, 64, 10):
        for t in range(64):
            c.put(k, t, "rl_raised_dark")
            c.put(t, k, "rl_raised_dark")
    for bx, by in ((10, 20), (40, 0), (20, 50)):
        for y in range(by + 2, by + 9, 2):
            for x in range(bx + 2, bx + 9, 2):
                c.put(x, y, "rx_iron")
    return c


KIT.update({
    "rip_labpanel": paint_lab_panel, "rip_labtile": paint_lab_tile, "rip_labfloor": paint_lab_floor,
    "rip_core": paint_core, "rip_corefloor": paint_core_floor, "rip_fluid": paint_fluid, "rip_raised": paint_raised,
    "rip_labwhite": _plain("rl_panel_light", "rl_panel", "rl_panel", 0.05),
    "rip_teal": _plain("rl_teal", "rl_teal_light", "rl_teal_dark", 0.04),
    "rip_epoxy": _plain("rl_epoxy", "rl_epoxy_light", "rl_epoxy", 0.05),
    "rip_leaf": _plain("rl_leaf", "rl_leaf_light", "rl_leaf_dark", 0.3),
    "rip_sub": _plain("rl_sub", "ry_light", "ry_dark", 0.05),
    "rip_locker": _plain("rl_locker", "rl_locker_dark", "rl_locker_dark", 0.05),
})


# ------------------------------------------------------------------------------------------------ where things are
def in_r(x, z, x0, x1, z0, z1):
    return x0 < x < x1 and z0 < z < z1


def place(x, y, z):
    """The room a point (world) is in, or None where nobody can be (the closed spaces between the rooms' ceilings and
    the deck above) or outside the lab."""
    if x < 30.2 or x > 65.8:
        return None
    if in_r(x, z, 44.0, 52.0, -88.0, -74.0) or in_r(x, z, 54.0, 62.0, 76.0, 90.0):
        return "STAIRS"
    if in_r(x, z, 45.7, 48.7, -65.7, -62.7):
        return "SERVICE TUBE"
    if z < -74.0 or z > 100.0:
        return None
    if y < CEIL1 - 0.01:                          # the lower deck
        if z < -46.0:
            if x < 37.0:
                return "LOCKER ROOM"
            if x > 59.0:
                return "SECURITY"
            if z < -56.0:
                return "INTAKE"
            return "DECON" if x < 40.5 or x > 55.5 else "AIR PLANT"
        if z < -10.0:
            return "CLEANROOM" if in_r(x, z, 39.0, 47.0, -39.0, -29.0) else "MAIN LAB"
        if z < 10.0:
            return "WASHROOMS" if x < 37.0 else ("BREAK ROOM" if x > 59.0 else "HUB")
        if z < 32.0:
            if x < 37.0:
                return "RECEIVING"
            if x > 59.0:
                return "MED BAY"
            return "HOLDING" if 40.5 < x < 55.5 else "CORRIDOR"
        if z < 68.0:
            return "INCUBATION HALL" if in_r(x, z, *HALL) else "RING"
        if x < 37.0:
            return "QUARTERS"
        if x < 40.5:
            return "CORRIDOR"
        if z > 92.0:
            return "SERVER ROOM"
        if x < 54.0:
            return "CONTROL ROOM" if z < 84.0 else "LOBBY"
        if z < 76.0:
            return "CORRIDOR" if x < 59.0 else "POWER"
        if z > 90.0 and x < 62.0:
            return "LOBBY"
        return None
    # the upper deck (the dock's)
    if -46.0 < z < -10.0:
        if x > 58.0:
            return "OFFICES" if z < -22.0 else "DIRECTOR"
        return "MAIN LAB"
    if -10.0 < z < 7.0:
        return "MOON POOL" if 38.0 < x < 58.0 else None
    if 7.0 < z < 27.0:
        return "SUB BAY" if x > 56.0 else "DOCK"
    if 27.0 < z < 38.0:
        return "OBSERVATION" if 36.0 < x < 60.0 else None
    if 38.0 < z < 62.0 and 36.0 < x < 60.0:
        return "INCUBATION HALL"
    return None


STEEL = ("DOCK", "SUB BAY", "MOON POOL", "STAIRS", "SERVICE TUBE", "AIR PLANT", "POWER")
TILED = ("WASHROOMS", "LOCKER ROOM")
SIGNED = ["LOCKER ROOM", "SECURITY", "INTAKE", "DECON", "AIR PLANT", "MAIN LAB", "CLEANROOM", "WASHROOMS", "BREAK ROOM",
          "HUB", "RECEIVING", "MED BAY", "HOLDING", "RING", "INCUBATION HALL", "QUARTERS", "SERVER ROOM",
          "CONTROL ROOM", "LOBBY", "POWER", "STAIRS", "OFFICES", "DIRECTOR", "DOCK", "SUB BAY", "OBSERVATION",
          "SERVICE TUBE", "MOON POOL"]


def wall_mat(p):
    if p is None:
        return None
    if p == "INCUBATION HALL":
        return "rip_core"
    if p in STEEL:
        return "rip_steel_in"
    if p in TILED:
        return "rip_labtile"
    return "rip_labpanel"


def floor_mat(p):
    if p == "INCUBATION HALL":
        return "rip_corefloor"
    if p in STEEL:
        return "rip_deck"
    if p in TILED:
        return "rip_labtile"
    if p == "SERVER ROOM":
        return "rip_raised"
    if p in ("OFFICES", "DIRECTOR"):
        return "rip_lino"
    return "rip_labfloor"


def ceil_mat(p):
    if p is None or p in STEEL or p == "INCUBATION HALL":
        return "rip_steel_in"
    return "rip_ceiling"


# ------------------------------------------------------------------------------------------------ decals
def lab_decals(rng):
    real = R.Atlas
    R.Atlas = lambda size=256: real(1024)
    try:
        a = R.tower_decals(rng)            # (the furniture's drawers, screens, monitors: the tower's pictures)
    finally:
        R.Atlas = real
    for name in SIGNED:
        w, h, p = R._sign(name, "rl_teal", "rw_light")
        a.add("sign_" + name, w, h, p)
    for name, scale, col in (("SITE ZERO", 6, "rl_teal"), ("MAIN LAB", 5, "rl_teal"), ("HOLDING", 5, "rl_teal"),
                             ("INCUBATION", 5, "rl_teal_light"), ("CONTROL", 5, "rl_teal"), ("DOCK", 5, "rx_black"),
                             ("SUB BAY", 5, "rx_black"), ("EXION", 4, "rx_iron"), ("OBSERVATION", 4, "rl_teal_light")):
        w, h, p = R._stencil(name, scale, col, random.Random(name), chip=0.0 if col.startswith("rl") else 0.05)
        a.add("big_" + name, w, h, p)
    for key, text, bg, fg in (("authorised", "AUTHORISED PERSONNEL ONLY", "rw_light", "rh_red"),
                              ("biohazard", "BIOHAZARD", "ry_yel", "rx_black"),
                              ("decon", "DECONTAMINATION", "ry_yel", "rx_black"),
                              ("wash", "WASH YOUR HANDS", "rw_light", "rl_teal"),
                              ("lift", "SAMPLE LIFT", "rl_teal", "rw_light"),
                              ("no_entry", "NO ENTRY", "rh_red", "rw_light"),
                              ("keep_clear", "KEEP CLEAR", "ry_yel", "rx_black"),
                              ("hv", "HIGH VOLTAGE", "ry_yel", "rx_black"),
                              ("cold", "-80 C", "rw_light", "tp_navy"),
                              ("level", "SITE ZERO", "rl_teal", "rw_light")):
        w, h, p = R._sign(text, bg, fg)
        a.add(key, w, h, p)

    def lockers(c):            # one locker door 0.6 x 2 m: vents, a handle, a number plate
        c.rect(0, 0, c.w, c.h, "rl_locker")
        c.frame(0, 0, c.w, c.h, "rl_locker_dark")
        for y in (5, 7, 9, 52, 54, 56):
            c.rect(4, y, c.w - 4, y + 1, "rl_locker_dark")
        c.rect(c.w - 5, 28, c.w - 3, 36, "rx_iron")
        c.rect(5, 14, 11, 17, "rw_light")
    a.add("locker", 18, 62, lockers)

    def mesh(c):               # chain-link: see-through
        c.rect(0, 0, c.w, c.h, "clear")
        for y in range(c.h):
            for x in range(c.w):
                if (x + y) % 6 == 0 or (x - y) % 6 == 0:
                    c.put(x, y, "rx_iron_light")
    a.add("mesh", 36, 36, mesh)

    def louvres(c):            # an air handler's side: louvres, a rating plate
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.frame(0, 0, c.w, c.h, "tp_bright_dark")
        for y in range(6, c.h - 6, 3):
            c.rect(4, y, c.w // 2 - 2, y + 1, "rx_iron")
        c.rect(c.w // 2 + 6, 8, c.w - 6, 16, "rw_light")
        c.rect(c.w // 2 + 6, c.h - 14, c.w - 6, c.h - 10, "rh_red")
    a.add("louvres", 64, 48, louvres)

    def sequencer(c):          # a tall instrument's front: a screen, a glass sample door, status lights
        c.rect(0, 0, c.w, c.h, "rw_light")
        c.frame(0, 0, c.w, c.h, "rw_white_dark")
        c.rect(3, 4, c.w - 3, 16, "tp_bezel")
        c.rect(4, 5, c.w - 4, 15, "tp_screen")
        for k in range(4):
            c.rect(6, 7 + k * 2, 6 + 4 + (k * 7) % 14, 8 + k * 2, "tp_screen_on")
        c.rect(3, 22, c.w - 3, 48, "rg_glass")
        for y in (28, 34, 40):
            c.rect(5, y, c.w - 5, y + 1, "rx_iron_light")
        c.rect(0, 52, c.w, 54, "rl_teal")
        for k in range(3):
            c.put(5 + k * 4, 58, "tp_screen_on" if k else "rh_red")
    a.add("sequencer", 28, 64, sequencer)

    def freezer(c):            # an upright freezer's door
        c.rect(0, 0, c.w, c.h, "rw_light")
        c.frame(0, 0, c.w, c.h, "rw_white_dark")
        c.rect(4, 6, 16, 11, "tp_bezel")
        c.rect(5, 7, 13, 10, "tp_screen_on")
        c.rect(c.w - 6, 20, c.w - 4, 40, "rx_iron")
        c.rect(0, c.h - 6, c.w, c.h, "rx_iron")
    a.add("freezer", 32, 64, freezer)

    def servers(c):            # a server rack's front: a dark mesh door, rows of lights
        c.rect(0, 0, c.w, c.h, "rx_black")
        c.frame(0, 0, c.w, c.h, "rx_iron")
        r2 = random.Random("servers")
        for y in range(4, c.h - 4, 4):
            c.rect(2, y, c.w - 2, y + 3, "rx_iron")
            for x in range(3, c.w - 3, 3):
                if r2.random() < 0.35:
                    c.put(x, y + 1, r2.choice(["tp_screen_on", "tp_screen_on", "tp_amber", "rl_teal_light"]))
    a.add("servers", 20, 70, servers)

    def vending(c):            # a drinks machine's front
        c.rect(0, 0, c.w, c.h, "rh_red")
        c.rect(3, 4, c.w - 10, c.h - 16, "rg_glass")
        r2 = random.Random("vend")
        for y in range(6, c.h - 18, 6):
            for x in range(5, c.w - 12, 4):
                c.rect(x, y, x + 2, y + 4, r2.choice(["rl_teal", "ry_yel", "rw_light", "tp_sea", "rh_red_light"]))
        c.rect(c.w - 8, 10, c.w - 3, 24, "rx_iron")
        c.rect(5, c.h - 12, c.w - 12, c.h - 6, "rx_black")
        c.text(c.w - 8, 4, "", "rw_light")
    a.add("vending", 36, 64, vending)

    def notice(c):             # a notice board: papers pinned on cork, a site plan
        c.rect(0, 0, c.w, c.h, "tp_card")
        c.frame(0, 0, c.w, c.h, "rx_iron")
        r2 = random.Random("notice")
        for _ in range(9):
            x, y = r2.randrange(2, c.w - 12), r2.randrange(2, c.h - 14)
            c.rect(x, y, x + 9, y + 12, r2.choice(["tp_paper", "rw_light", "ry_light"]))
            for k in range(3):
                c.rect(x + 1, y + 3 + k * 3, x + 8, y + 4 + k * 3, "rx_iron_light")
            c.put(x + 4, y + 1, "rh_red")
    a.add("notice", 64, 40, notice)

    def plan(c):               # a "you are here" plan of the lab
        c.rect(0, 0, c.w, c.h, "rw_light")
        c.frame(0, 0, c.w, c.h, "rl_teal")
        c.rect(3, 3, c.w - 3, 6, "rl_teal")
        for x0, y0, x1, y1 in ((4, 9, 14, 20), (16, 9, 34, 20), (36, 9, 44, 20), (4, 22, 14, 33), (16, 22, 34, 33),
                               (36, 22, 44, 33)):
            c.frame(x0, y0, x1, y1, "rx_iron_light")
        c.rect(23, 25, 27, 29, "tp_screen")
        c.rect(24, 14, 26, 16, "rh_red")
    a.add("plan", 48, 36, plan)

    def mirror(c):
        c.rect(0, 0, c.w, c.h, "tp_sea")
        c.frame(0, 0, c.w, c.h, "tp_bright")
        for k in range(8):
            c.put(4 + k, 3 + k, "rw_light")
    a.add("mirror", 32, 24, mirror)

    def spill(c):              # the broken tank's fluid on the floor: see-through edges
        c.rect(0, 0, c.w, c.h, "clear")
        r2 = random.Random("spill")
        for _ in range(26):
            cx, cy, rr = r2.randrange(10, c.w - 10), r2.randrange(10, c.h - 10), r2.randrange(4, 11)
            for y in range(c.h):
                for x in range(c.w):
                    if math.hypot(x - cx, y - cy) < rr:
                        c.put(x, y, "rl_fluid_dark" if (x * 7 + y * 3) % 11 else "rl_fluid")
    a.add("spill", 96, 96, spill)

    def ups(c):                # battery cabinets: a door with a panel of LEDs
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.frame(0, 0, c.w, c.h, "tp_bright_dark")
        c.rect(4, 6, c.w - 4, 14, "tp_bezel")
        for k in range(5):
            c.put(6 + k * 3, 10, "tp_screen_on" if k < 4 else "tp_amber")
        for y in range(20, c.h - 6, 3):
            c.rect(4, y, c.w - 4, y + 1, "tp_bright_dark")
    a.add("ups", 24, 64, ups)

    def lift_doors(c):         # the sample lift's doors: two steel leaves, a call button
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.frame(0, 0, c.w, c.h, "rx_iron")
        c.rect(c.w // 2, 2, c.w // 2 + 1, c.h - 2, "rx_iron")
        c.rect(c.w - 6, c.h // 2, c.w - 3, c.h // 2 + 3, "rl_teal_light")
    a.add("lift_doors", 40, 64, lift_doors)
    return a


# ------------------------------------------------------------------------------------------------ walls and floors
def segs(lo, hi, cuts):
    vals = sorted({lo, hi} | {v for v in cuts if lo + 0.05 < v < hi - 0.05})
    return list(zip(vals, vals[1:]))


X_CUTS = (30.25, 36.0, 37.0, 38.0, 40.5, 46.0, 47.0, 50.0, 54.0, 55.5, 56.0, 58.0, 59.0, 60.0, 62.0, 65.75)
Z_CUTS = (-74.0, -56.0, -46.0, -42.0, -39.0, -29.0, -22.0, -10.0, -9.0, 1.5, 7.0, 10.0, 17.3, 24.6, 27.0, 32.0, 38.0,
          62.0, 68.0, 76.0, 84.0, 90.0, 92.0, 100.0)
Y_CUTS = (CEIL1, LAB1)


class Paint:
    """Collects the bands that go along the bottom of the walls (skirting) and the teal stripe."""
    def __init__(self):
        self.feet = []


def lab_wall(m, row, paint):
    """A wall piece: each face cut where the rooms change (at every wall line and at the dock deck's floor), each
    stretch painted for the room it faces; nothing drawn into the closed spaces."""
    c, s = row["pos"], row["size"]
    wx = c[0] + OX
    x0, x1 = wx - s[0] / 2, wx + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    thin_x = s[0] <= s[2]                 # the wall runs along z (its big faces face +-x)
    for sg in (-1, 1):
        for big in (True, False):
            if big:
                n = (sg, 0, 0) if thin_x else (0, 0, sg)
                at = (x1 if sg > 0 else x0) if thin_x else (z1 if sg > 0 else z0)
                a_lo, a_hi = (z0, z1) if thin_x else (x0, x1)
                cuts = Z_CUTS if thin_x else X_CUTS
            else:                          # the ends
                n = (0, 0, sg) if thin_x else (sg, 0, 0)
                at = (z1 if sg > 0 else z0) if thin_x else (x1 if sg > 0 else x0)
                a_lo, a_hi = (x0, x1) if thin_x else (z0, z1)
                cuts = ()
            for a0, a1 in segs(a_lo, a_hi, cuts):
                for ya, yb in segs(y0, y1, Y_CUTS):
                    am, ym = (a0 + a1) / 2, (ya + yb) / 2
                    if n[0]:
                        px, pz = at + n[0] * 0.3, am
                        pts = [(at - OX, ya, a0), (at - OX, ya, a1), (at - OX, yb, a1), (at - OX, yb, a0)]
                        mid = (at - OX, ym, am)
                    else:
                        px, pz = am, at + n[2] * 0.3
                        pts = [(a0 - OX, ya, at), (a1 - OX, ya, at), (a1 - OX, yb, at), (a0 - OX, yb, at)]
                        mid = (am - OX, ym, at)
                    p = place(px, ym, pz)
                    mt = wall_mat(p) or "rip_steel_in"   # (the closed spaces too: no light gets through)
                    if m.hidden(n, mid, pts):
                        continue
                    lo_a, hi_a = (a0 - OX, a1 - OX) if not n[0] else (a0, a1)
                    flat(m.b, n, (at - OX) if n[0] else at, lo_a, hi_a, ya, yb, mt, uv_world())
                    if big and abs(ya - LAB2) < 0.02 or big and abs(ya - LAB1) < 0.02 and p in ("OFFICES", "DIRECTOR",
                                                                                                   "OBSERVATION"):
                        paint.feet.append((n, (at - OX) if n[0] else at, lo_a, hi_a, ya, yb, p))
    # the top: only if someone can see it (low walls: the mezzanine's sides, the cleanroom's and cells' waist walls)
    top_p = place(wx, y1 + 0.3, c[2])
    tpts = [(x0 - OX, y1, z0), (x1 - OX, y1, z0), (x1 - OX, y1, z1), (x0 - OX, y1, z1)]
    if top_p is not None and not m.hidden((0, 1, 0), (wx - OX, y1, c[2]), tpts):
        m.b.poly([(x0 - OX, y1, z0), (x1 - OX, y1, z0), (x1 - OX, y1, z1), (x0 - OX, y1, z1)], (0, 1, 0),
                 "rip_iron" if s[1] < 1.3 else "rip_labpanel", uv_world(1.0))


def feet_bands(m, paint):
    """A dark skirting along the foot of the walls and a teal stripe at hand height (white rooms); a black tile band
    in the tiled rooms; a hazard band in the steel rooms."""
    for n, at, a0, a1, ya, yb, p in paint.feet:
        off = (n[0] or n[2]) * 0.011
        if p in STEEL:
            flat(m.b, n, at + off, a0, a1, ya, ya + 0.3, "rip_hazard", uv_world())
            continue
        if p == "INCUBATION HALL":
            flat(m.b, n, at + off, a0, a1, ya, ya + 0.15, "rip_epoxy", uv_world(1.0))
            if yb - ya > 1.45:
                m.b.group = bake_light.GLOW
                flat(m.b, n, at + off, a0, a1, ya + 1.3, ya + 1.36, "rip_teal", uv_world(1.0))
                m.b.group = None
            continue
        flat(m.b, n, at + off, a0, a1, ya, ya + 0.12, "rip_epoxy", uv_world(1.0))
        if p not in TILED and yb - ya > 1.45:
            flat(m.b, n, at + off, a0, a1, ya + 1.2, ya + 1.35, "rip_teal", uv_world(1.0))


def lab_slab(m, row):
    """A floor slab: its top painted room by room, its underside the ceiling of the room below (tiles in the lab,
    steel in the hall and the dock), its edges dark."""
    c, s = row["pos"], row["size"]
    wx = c[0] + OX
    x0, x1 = wx - s[0] / 2, wx + s[0] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    top, bot = c[1] + s[1] / 2, c[1] - s[1] / 2
    for xa, xb in segs(x0, x1, X_CUTS):
        for za, zb in segs(z0, z1, Z_CUTS):
            xm, zm = (xa + xb) / 2, (za + zb) / 2
            pt = place(xm, top + 0.3, zm)
            if True:     # (always: a floor left out under a prop showed the seabed through it)
                mt = floor_mat(pt) if pt is not None else "rip_steel_in"
                if row["colour"] == "metal" and pt not in ("OFFICES", "DIRECTOR"):
                    mt = "rip_deck"
                m.b.poly([(xa - OX, top, za), (xb - OX, top, za), (xb - OX, top, zb), (xa - OX, top, zb)], (0, 1, 0),
                         mt, uv_world())
            pb = place(xm, bot - 0.3, zm)
            if True:
                mt = ceil_mat(pb) if row["colour"] != "metal" else "rip_iron"
                m.b.poly([(xa - OX, bot, za), (xb - OX, bot, za), (xb - OX, bot, zb), (xa - OX, bot, zb)], (0, -1, 0),
                         mt, uv_world())
    # the edges (round holes: the ramp's, the hall's, the trunk's)
    m.box(c, s, lambda n, mid, q: None if abs(n[1]) > 0.7 else ("rip_iron", uv_world(1.0)))


def keel(m, row):
    """The keel plate under the lab: only its bottom and ends are ever seen (from the sea)."""
    c, s = row["pos"], row["size"]
    if row.get("kind") == "deck_curve":
        import gen_riptide as G
        za, zb = c[2] - s[2] / 2, c[2] + s[2] / 2
        bot = c[1] - s[1] / 2
        ha, hb = G.hull_half(za) - 0.25, G.hull_half(zb) - 0.25
        m.b.poly([(ha, bot, za), (hb, bot, zb), (-hb, bot, zb), (-ha, bot, za)], (0, -1, 0), "rip_hull_low", uv_world())
        return
    m.box(c, s, lambda n, mid, q: "rip_hull_low" if n[1] < -0.7 else None)


def lining(m):
    """Lab panels over the hull plate's inside, wherever a lab room is against it, with the skirting and stripe."""
    feet = []
    for side, xw in ((-1, HULL_IN[0]), (1, HULL_IN[1])):
        n = (-side, 0, 0)
        at = xw - OX - side * 0.012
        probe = xw - side * 0.4
        for y0, y1 in ((LAB2, CEIL1), (LAB1, CEIL0)):
            for za, zb in segs(-74.0, 100.0, Z_CUTS):
                p = place(probe, (y0 + y1) / 2, (za + zb) / 2)
                if p is None or p in STEEL:
                    continue
                # (the main lab is two storeys: one sheet from the floor to the ceiling)
                if y0 == LAB1 and p == "MAIN LAB" and place(probe, LAB2 + 1, (za + zb) / 2) == "MAIN LAB":
                    continue
                top = y1
                if y0 == LAB2 and p == "MAIN LAB" and place(probe, LAB1 + 1, (za + zb) / 2) == "MAIN LAB":
                    top = CEIL0
                flat(m.b, n, at, za, zb, y0, top, wall_mat(p), uv_world())
                feet.append((n, at, za, zb, y0, top, p))
    return feet


# ------------------------------------------------------------------------------------------------ furniture
LAB_KINDS = ("reception", "rail_low", "lockers", "bench_seat", "shower_wall", "cage", "air_handler", "lab_bench",
             "sequencer", "freezer", "lab_shelves", "lift", "notice", "planter", "stall_wall", "vending", "cell_bed",
             "tank_plinth", "growth_tank", "tank_cap", "tank_console", "shard", "wall_screens", "ups", "server_rack",
             "sub", "sinks", "cylinders")


_M = [None]


def against(row):
    """Which way a piece faces (into the room): away from the wall behind it (the side whose next 25 cm is a wall,
    the hull or nowhere); a long piece faces across its length."""
    c, s = row["pos"], row["size"]
    m = _M[0]

    def blocked(p):
        return m.inside(p) or place(p[0] + OX, p[1], p[2]) is None
    if s[0] < s[2]:
        return ("x", 1 if blocked((c[0] - s[0] / 2 - 0.25, c[1], c[2])) else -1)
    return ("z", 1 if blocked((c[0], c[1], c[2] - s[2] / 2 - 0.25)) else -1)


def l_prop(m, row):
    kind = row["kind"]
    c, s = row["pos"], row["size"]
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    cx, cz = c[0], c[2]
    b = m.b
    axis, sg = against(row)
    t_item(m)

    def face(name, mt="decals", lo=None, hi=None, inset=0.0, both=False, glow=False):
        """A decal on the front face (and the back too)."""
        for k in ((sg, -sg) if both else (sg,)):
            if glow:
                b.group = bake_light.GLOW
            if axis == "x":
                at = x1 + 0.006 if k > 0 else x0 - 0.006
                flat(b, (k, 0, 0), at, z0 + inset, z1 - inset, lo if lo is not None else y0, hi if hi is not None else y1,
                     mt, m.d(name))
            else:
                at = z1 + 0.006 if k > 0 else z0 - 0.006
                flat(b, (0, 0, k), at, x0 + inset, x1 - inset, lo if lo is not None else y0, hi if hi is not None else y1,
                     mt, m.d(name))
            if glow:
                t_item(m)

    def along_units(w):
        L = s[2] if axis == "x" else s[0]
        n = max(1, int(round(L / w)))
        a0 = z0 if axis == "x" else x0
        return [(a0 + k * L / n, a0 + (k + 1) * L / n) for k in range(n)]

    def front_flat(a0, a1, lo, hi, mt, uv):
        if axis == "x":
            at = x1 + 0.006 if sg > 0 else x0 - 0.006
            flat(b, (sg, 0, 0), at, a0, a1, lo, hi, mt, uv)
        else:
            at = z1 + 0.006 if sg > 0 else z0 - 0.006
            flat(b, (0, 0, sg), at, a0, a1, lo, hi, mt, uv)

    if kind == "reception":                  # a security counter: white front, teal band, dark top, monitors
        t_part(m, x0, y0, z0, x1, y1 - 0.05, z1, "rip_labpanel")
        t_part(m, x0 - 0.03, y1 - 0.05, z0 - 0.03, x1 + 0.03, y1, z1 + 0.03, "rip_epoxy")
        t_part(m, x0 - 0.005, y0 + 0.75, z0 - 0.005, x1 + 0.005, y0 + 0.85, z1 + 0.005, "rip_teal")
        if s[0] > s[2]:
            for k in range(2):
                mx = x0 + (k + 1) * s[0] / 3
                t_part(m, mx - 0.3, y1, cz - 0.05, mx + 0.3, y1 + 0.4, cz + 0.02, "rip_iron")
                b.group = bake_light.GLOW
                flat(b, (0, 0, -1), cz - 0.056, mx - 0.28, mx + 0.28, y1 + 0.02, y1 + 0.38, "decals", m.d("monitor"))
                t_item(m)
    elif kind == "rail_low":                 # a queue barrier: a white half wall, a steel top rail
        t_part(m, x0 + 0.1, y0, z0 + 0.15, x1 - 0.1, y1 - 0.12, z1 - 0.15, "rip_labpanel")
        t_part(m, x0, y1 - 0.12, z0 + 0.1, x1, y1, z1 - 0.1, "rip_bright")
        for px in (x0, x1 - 0.1):
            t_part(m, px, y0, z0 + 0.1, px + 0.1, y1, z1 - 0.1, "rip_bright")
    elif kind == "lockers":                  # a row of steel lockers
        t_part(m, x0, y0, z0, x1, y0 + 0.1, z1, "rip_iron")
        t_part(m, x0, y0 + 0.1, z0, x1, y1, z1, "rip_locker")
        for a0, a1 in along_units(0.6):
            front_flat(a0 + 0.02, a1 - 0.02, y0 + 0.12, y1 - 0.04, "decals", m.d("locker"))
    elif kind == "bench_seat":               # a changing room bench: slats on steel legs
        for k in range(3):
            xa = x0 + 0.04 + k * (s[0] - 0.08) / 3
            t_part(m, xa, y1 - 0.05, z0, xa + (s[0] - 0.08) / 3 - 0.03, y1, z1, "rip_wood")
        for zz in (z0 + 0.3, z1 - 0.36):
            t_part(m, x0 + 0.1, y0, zz, x1 - 0.1, y1 - 0.05, zz + 0.06, "rip_iron")
    elif kind == "shower_wall":              # a tiled partition, a shower head on each side
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_labtile")
        for k in (-1, 1):
            zz = cz + k * 0.15
            cyl(b, (x0 + 0.5, y1 - 0.25, zz + k * 0.06), 0.02, 0.15, "rip_bright", axis="z", sides=6)
            cyl(b, (x0 + 0.5, y1 - 0.32, zz + k * 0.13), 0.07, 0.04, "rip_bright", sides=8)
    elif kind == "cage":                     # a weapons cage: a steel frame, chain-link sides, crates inside
        for px in (x0, x1 - 0.06):
            for pz in (z0, z1 - 0.06):
                t_part(m, px, y0, pz, px + 0.06, y1, pz + 0.06, "rip_iron")
        t_part(m, x0, y1 - 0.06, z0, x1, y1, z1, "rip_iron")
        t_part(m, x0 + 0.3, y0, z0 + 0.4, x1 - 0.2, y0 + 0.8, z0 + 1.6, "rip_cont_c")
        t_part(m, x0 + 0.3, y0, z1 - 1.5, x1 - 0.2, y0 + 1.1, z1 - 0.3, "rip_wood")
        for n, at, a0, a1 in (((-1, 0, 0), x0 + 0.03, z0, z1), ((1, 0, 0), x1 - 0.03, z0, z1), ((0, 0, -1), z0 + 0.03, x0, x1),
                              ((0, 0, 1), z1 - 0.03, x0, x1)):
            for k in (1, -1):              # (both faces: see-through)
                flat(b, tuple(v * k for v in n), at, a0 + 0.06, a1 - 0.06, y0 + 0.05, y1 - 0.06, "graffiti", m.d("mesh"))
    elif kind == "air_handler":              # a big air handling unit, its duct up into the ceiling
        t_part(m, x0, y0, z0, x1, y0 + 0.15, z1, "rip_iron")
        t_part(m, x0 + 0.05, y0 + 0.15, z0 + 0.05, x1 - 0.05, y1, z1 - 0.05, "rip_bright")
        for nz, at in ((-1, z0 + 0.044), (1, z1 - 0.044)):
            flat(b, (0, 0, nz), at, x0 + 0.1, x1 - 0.1, y0 + 0.3, y1 - 0.2, "decals", m.d("louvres"))
        t_part(m, cx - 0.6, y1, cz - 0.5, cx + 0.6, CEIL1, cz + 0.5, "rip_steel_in")
        cyl(b, (x1 - 0.3, y1 + 0.4, cz), 0.12, 0.8, "rip_pipe", sides=8)
    elif kind == "lab_bench":                # white cabinets, a black resin top; kit on the top
        t_part(m, x0 + 0.04, y0, z0 + 0.04, x1 - 0.04, y0 + 0.1, z1 - 0.04, "rip_epoxy")
        t_part(m, x0, y0 + 0.1, z0, x1, y1 - 0.04, z1, "rip_labpanel")
        t_part(m, x0 - 0.02, y1 - 0.04, z0 - 0.02, x1 + 0.02, y1, z1 + 0.02, "rip_epoxy")
        r2 = random.Random("%.1f%.1f" % (cx, cz))
        long_x = s[0] >= s[2]
        L = s[0] if long_x else s[2]
        a = 0.3
        while a < L - 0.5:
            pick = r2.random()
            if long_x:
                px, pz = x0 + a, cz
            else:
                px, pz = cx, z0 + a
            if pick < 0.3:                   # a microscope
                t_part(m, px - 0.12, y1, pz - 0.15, px + 0.12, y1 + 0.04, pz + 0.15, "rip_white")
                t_part(m, px - 0.04, y1 + 0.04, pz - 0.12, px + 0.04, y1 + 0.35, pz - 0.04, "rip_white")
                cyl(b, (px, y1 + 0.32, pz - 0.02), 0.035, 0.22, "rip_iron", axis="z", sides=6)
            elif pick < 0.55:                # an instrument: a box with a little screen
                t_part(m, px - 0.2, y1, pz - 0.18, px + 0.2, y1 + 0.28, pz + 0.18, "rip_bright")
                b.group = bake_light.GLOW
                if long_x:
                    flat(b, (0, 0, 1), pz + 0.186, px - 0.12, px + 0.05, y1 + 0.12, y1 + 0.24, "decals", m.d("monitor"))
                    flat(b, (0, 0, -1), pz - 0.186, px - 0.05, px + 0.12, y1 + 0.12, y1 + 0.24, "decals", m.d("monitor"))
                else:
                    flat(b, (1, 0, 0), px + 0.206, pz - 0.12, pz + 0.05, y1 + 0.12, y1 + 0.24, "decals", m.d("monitor"))
                    flat(b, (-1, 0, 0), px - 0.206, pz - 0.05, pz + 0.12, y1 + 0.12, y1 + 0.24, "decals", m.d("monitor"))
                t_item(m)
            elif pick < 0.8:                 # glassware: bottles
                for k in range(3):
                    dx = (k - 1) * 0.1
                    cyl(b, (px + (dx if long_x else 0), y1 + 0.1, pz + (0 if long_x else dx)), 0.035, 0.2,
                        "rip_glass" if k != 1 else "rip_teal", sides=6)
            else:                            # a rack of sample tubes
                t_part(m, px - 0.15, y1, pz - 0.08, px + 0.15, y1 + 0.08, pz + 0.08, "rip_teal")
            a += r2.uniform(0.7, 1.3)
    elif kind == "sequencer":                # a tall white instrument cabinet
        t_part(m, x0, y0, z0, x1, y0 + 0.1, z1, "rip_epoxy")
        t_part(m, x0, y0 + 0.1, z0, x1, y1, z1, "rip_white")
        for nz, at in ((-1, z0 - 0.006), (1, z1 + 0.006)):
            n_u = max(1, int((x1 - x0) // 0.9))
            for k in range(n_u):
                a0 = x0 + k * (x1 - x0) / n_u
                b.group = bake_light.GLOW
                flat(b, (0, 0, nz), at, a0 + 0.04, a0 + (x1 - x0) / n_u - 0.04, y0 + 0.2, y1 - 0.1, "decals", m.d("sequencer"))
                t_item(m)
    elif kind == "freezer":                  # an upright -80 freezer, door facing into the room
        t_part(m, x0, y0, z0, x1 - 0.1, y1, z1, "rip_white")
        t_part(m, x1 - 0.1, y0 + 0.05, z0 + 0.02, x1, y1 - 0.05, z1 - 0.02, "rip_white")
        flat(b, (1, 0, 0), x1 + 0.006, z0 + 0.05, z1 - 0.05, y0 + 0.1, y1 - 0.1, "decals", m.d("freezer"))
        flat(b, (1, 0, 0), x1 + 0.008, cz - 0.25, cz + 0.25, y1 - 0.45, y1 - 0.3, "decals", m.d("cold"))
    elif kind in ("lab_shelves",):           # white steel shelving: boxes, bottles, files
        post = 0.04
        for px in (x0, x1 - post):
            for pz in (z0, z1 - post):
                t_part(m, px, y0, pz, px + post, y1, pz + post, "rip_white")
        r2 = random.Random("%.1f%.1f" % (cx, cz))
        levels = [y0 + 0.1 + k * (y1 - y0 - 0.15) / 4 for k in range(5)]
        for ly in levels:
            t_part(m, x0, ly, z0, x1, ly + 0.03, z1, "rip_white")
        long_z = s[2] >= s[0]
        L = s[2] if long_z else s[0]
        D = (s[0] if long_z else s[2]) - 0.1
        for ly in levels[:-1]:
            a = 0.06
            while a < L - 0.3:
                w = r2.uniform(0.15, 0.45)
                if a + w > L - 0.06:
                    break
                h = r2.uniform(0.12, (y1 - y0) / 4 - 0.08)
                mt = r2.choice(["rip_card", "rip_white", "rip_teal", "rip_glass", "rip_navy"])
                if long_z:
                    t_part(m, x0 + 0.05, ly + 0.03, z0 + a, x0 + 0.05 + D, ly + 0.03 + h, z0 + a + w, mt)
                else:
                    t_part(m, x0 + a, ly + 0.03, z0 + 0.05, x0 + a + w, ly + 0.03 + h, z0 + 0.05 + D, mt)
                a += w + r2.uniform(0.03, 0.15)
    elif kind == "lift":                     # the sample lift's shaft: steel cladding, doors north and south
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_bright")
        for nz, at in ((-1, z0 - 0.006), (1, z1 + 0.006)):
            flat(b, (0, 0, nz), at, cx - 1.1, cx + 1.1, y0, y0 + 2.4, "decals", m.d("lift_doors"))
            reg = m.decals.regions["lift"]
            w = 1.6
            hh = w * (reg[3] - reg[1]) / (reg[2] - reg[0])
            flat(b, (0, 0, nz), at + nz * 0.002, cx - w / 2, cx + w / 2, y0 + 2.6, y0 + 2.6 + hh, "decals", m.d("lift"))
        for nx, at in ((-1, x0 - 0.006), (1, x1 + 0.006)):
            flat(b, (nx, 0, 0), at, z0 + 0.2, z1 - 0.2, y0, y0 + 0.12, "rip_epoxy", uv_world(1.0))
            flat(b, (nx, 0, 0), at, cz - 0.8, cz + 0.8, y0 + 1.4, y0 + 1.4 + 1.6 * 36 / 48, "decals", m.d("plan"))
    elif kind == "notice":                   # a freestanding board: notices both sides, a plan of the lab on the ends
        t_part(m, x0 + 0.05, y0, z0 + 0.6, x1 - 0.05, y1, z1 - 0.6, "rip_labpanel")
        t_part(m, x0, y0, z0, x1, y0 + 0.15, z1, "rip_epoxy")
        t_part(m, x0 + 0.1, y0 + 0.15, z0 + 0.2, x1 - 0.1, y1 - 0.2, z1 - 0.2, "rip_labpanel")
        for nz, at in ((-1, z0 + 0.194), (1, z1 - 0.194)):
            flat(b, (0, 0, nz), at, x0 + 0.2, x1 - 0.2, y0 + 1.0, y0 + 2.0, "decals", m.d("notice"))
        for nx, at in ((-1, x0 + 0.094), (1, x1 - 0.094)):
            flat(b, (nx, 0, 0), at, z0 + 0.3, z1 - 0.3, y0 + 1.1, y0 + 1.1 + (s[2] - 0.6) * 36 / 48, "decals", m.d("plan"))
    elif kind == "planter":                  # a white planter box, shrubs
        t_part(m, x0, y0, z0, x1, y1 - 0.3, z1, "rip_labpanel")
        t_part(m, x0 - 0.02, y1 - 0.34, z0 - 0.02, x1 + 0.02, y1 - 0.3, z1 + 0.02, "rip_epoxy")
        r2 = random.Random("%.1f%.1f" % (cx, cz))
        for _ in range(4):
            px, pz = r2.uniform(x0 + 0.35, x1 - 0.35), r2.uniform(z0 + 0.35, z1 - 0.35)
            hs = r2.uniform(0.3, 0.55)
            t_part(m, px - hs, y1 - 0.3, pz - hs, px + hs, y1 + r2.uniform(0.2, 0.6), pz + hs, "rip_leaf")
    elif kind == "stall_wall":               # a washroom partition, off the floor on two feet
        t_part(m, x0, y0 + 0.15, z0, x1, y1, z1, "rip_white")
        for px in (x0 + 0.2, x1 - 0.25):
            t_part(m, px, y0, z0 - 0.01, px + 0.05, y0 + 0.15, z1 + 0.01, "rip_bright")
    elif kind == "vending":
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_red")
        b.group = bake_light.GLOW
        flat(b, (-1, 0, 0), x0 - 0.006, z0 + 0.05, z1 - 0.05, y0 + 0.05, y1 - 0.05, "decals", m.d("vending"))
    elif kind == "cell_bed":                 # a steel bunk bolted to the wall, a thin mattress
        t_part(m, x0, y0 + 0.4, z0, x1, y0 + 0.45, z1, "rip_bright")
        t_part(m, x0 + 0.05, y0 + 0.45, z0 + 0.05, x1 - 0.05, y1, z1 - 0.05, "rip_sheet")
        for pz in (z0 + 0.1, z1 - 0.15):
            px = x0 + 0.1 if cx + OX < 48 else x1 - 0.15
            t_part(m, px, y0, pz, px + 0.05, y0 + 0.4, pz + 0.05, "rip_bright")
    elif kind == "tank_plinth":              # a tank's dark steel plinth, bolts, a teal glow strip round it
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_iron")
        t_part(m, x0 - 0.01, y1 - 0.12, z0 - 0.01, x1 + 0.01, y1 - 0.08, z1 + 0.01, "rip_teal")
        b.group = bake_light.GLOW
        t_part(m, x0 - 0.012, y1 - 0.12, z0 - 0.012, x1 + 0.012, y1 - 0.08, z1 + 0.012, "rip_teal")
        if abs(s[0] - 3.6) < 0.05:           # Raijin's tank, broken: the fluid spilt round it
            b.group = None
            sp = 3.4
            b.poly([(cx - sp, y0 + 0.008, cz - sp), (cx + sp, y0 + 0.008, cz - sp), (cx + sp, y0 + 0.008, cz + sp),
                    (cx - sp, y0 + 0.008, cz + sp)], (0, 1, 0), "graffiti", m.d("spill"))
            b.poly([(x0 + 0.1, y1 + 0.006, z0 + 0.1), (x1 - 0.1, y1 + 0.006, z0 + 0.1), (x1 - 0.1, y1 + 0.006, z1 - 0.1),
                    (x0 + 0.1, y1 + 0.006, z1 - 0.1)], (0, 1, 0), "graffiti", m.d("spill"))
            # its cap still hangs from the ceiling on its pipes, the cables torn
            t_item(m)
            ct = y0 + 4.5
            cyl(b, (cx, ct + 0.25, cz), 1.5, 0.5, "rip_iron", "rip_iron", sides=16)
            for dx, dz in ((-0.6, 0.0), (0.6, 0.0)):
                cyl(b, (cx + dx, (ct + 0.5 + CEIL0) / 2, cz + dz), 0.12, CEIL0 - ct - 0.5, "rip_pipe", sides=8)
            for k in range(5):
                ang = k * 1.3
                cyl(b, (cx + 1.0 * math.cos(ang), ct - 0.4 - 0.1 * k, cz + 1.0 * math.sin(ang)), 0.025, 0.8 + 0.15 * k,
                    "rip_iron", sides=4)
    elif kind == "growth_tank":              # a glass cylinder of glowing green fluid, steel bands, a ladder rung row
        r = min(s[0], s[2]) / 2 - 0.02
        b.group = bake_light.GLOW
        cyl(b, (cx, (y0 + y1) / 2, cz), r, s[1], "rip_fluid", "rip_fluid", sides=20, caps=(False, False))
        t_item(m)
        for yy in (y0 + 0.08, y1 - 0.08, (y0 + y1) / 2):
            cyl(b, (cx, yy, cz), r + 0.03, 0.12, "rip_iron", sides=20, caps=(False, False))
        for k in range(4):                   # four steel posts round the glass
            ang = math.pi / 4 + k * math.pi / 2
            px, pz = cx + (r + 0.04) * math.cos(ang), cz + (r + 0.04) * math.sin(ang)
            t_part(m, px - 0.05, y0, pz - 0.05, px + 0.05, y1, pz + 0.05, "rip_iron")
    elif kind == "tank_cap":                 # the tank's lid, pipes up to the ceiling
        cyl(b, (cx, (y0 + y1) / 2, cz), min(s[0], s[2]) / 2, s[1], "rip_iron", "rip_iron", sides=20)
        cyl(b, (cx, y1 + 0.15, cz), 0.6, 0.3, "rip_bright", "rip_bright", sides=12)
        for dx in (-0.45, 0.45):
            cyl(b, (cx + dx, (y1 + 0.3 + CEIL0) / 2, cz), 0.12, CEIL0 - y1 - 0.3, "rip_pipe", sides=8)
    elif kind == "tank_console":             # a pedestal console by each tank, its screen facing the tank
        t_part(m, x0 + 0.15, y0, z0 + 0.15, x1 - 0.15, y1 - 0.25, z1 - 0.15, "rip_iron")
        t_part(m, x0, y1 - 0.25, z0, x1, y1, z1, "rip_bright")
        b.group = bake_light.GLOW
        b.poly([(x0 + 0.08, y1 + 0.005, z0 + 0.08), (x1 - 0.08, y1 + 0.005, z0 + 0.08), (x1 - 0.08, y1 + 0.005, z1 - 0.08),
                (x0 + 0.08, y1 + 0.005, z1 - 0.08)], (0, 1, 0), "decals", m.d("monitor"))
    elif kind == "shard":                    # jagged glass shards standing in the broken tank's base ring
        L = max(s[0], s[2])
        n = max(2, int(L / 0.35))
        r2 = random.Random("%.2f%.2f" % (cx, cz))
        for k in range(n):
            a0 = -L / 2 + k * L / n
            a1 = a0 + L / n
            h = r2.uniform(0.35, 1.0) * s[1]
            peak = r2.uniform(a0, a1)
            if s[0] >= s[2]:
                pts = [(cx + a0, y0, cz), (cx + a1, y0, cz), (cx + peak, y0 + h, cz)]
                nn = (0, 0, 1)
            else:
                pts = [(cx, y0, cz + a0), (cx, y0, cz + a1), (cx, y0 + h, cz + peak)]
                nn = (1, 0, 0)
            b.group = bake_light.GLOW
            b.poly(pts, nn, "rip_fluid", uv_world(1.0))
            b.poly(pts, tuple(-v for v in nn), "rip_fluid", uv_world(1.0))
        t_item(m)
        t_part(m, x0, y0, z0, x1, y0 + 0.06, z1, "rip_iron")
    elif kind == "wall_screens":             # a wall of screens over the control room's south wall
        b.group = bake_light.GLOW
        cols = max(1, int(s[0] // 1.1))
        for i in range(cols):
            for j in range(2):
                a0 = x0 + i * s[0] / cols + 0.04
                a1 = x0 + (i + 1) * s[0] / cols - 0.04
                ya = y0 + j * s[1] / 2 + 0.04
                flat(b, (0, 0, -1), z0 - 0.004, a0, a1, ya, ya + s[1] / 2 - 0.08, "decals", m.d("monitor" if (i + j) % 3 else "screens"))
        t_item(m)
        flat(b, (0, 0, -1), z0 - 0.002, x0 - 0.05, x1 + 0.05, y0 - 0.05, y1 + 0.05, "rip_iron", uv_world(1.0))
    elif kind == "ups":                      # battery cabinets
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_bright")
        for a0, a1 in along_units(0.6):
            front_flat(a0 + 0.02, a1 - 0.02, y0 + 0.05, y1 - 0.05, "decals", m.d("ups"))
    elif kind == "server_rack":              # a row of server racks, the lights on both fronts
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_iron")
        n_r = max(1, int(round(s[0] / 0.6)))
        b.group = bake_light.GLOW
        for k in range(n_r):
            a0 = x0 + k * s[0] / n_r
            for nz, at in ((-1, z0 - 0.006), (1, z1 + 0.006)):
                flat(b, (0, 0, nz), at, a0 + 0.02, a0 + s[0] / n_r - 0.02, y0 + 0.05, y1 - 0.05, "decals", m.d("servers"))
        t_item(m)
    elif kind == "sub":                      # the mini sub on its cradle: a yellow hull, a dome, a fin, the screw
        r = min(s[1], s[2]) / 2 - 0.15
        y = y0 + 0.5 + r - 0.25
        L = s[0] - 1.0
        cyl(b, (cx, y, cz), r, L, "rip_sub", "rip_sub", axis="x", sides=14)
        cyl(b, (x0 + 0.3, y, cz), r * 0.75, 0.5, "rip_glass", "rip_glass", axis="x", sides=14)    # the dome (bow west)
        cyl(b, (x1 - 0.35, y, cz), r * 0.5, 0.4, "rip_iron", "rip_iron", axis="x", sides=10)
        t_part(m, x1 - 0.2, y - 0.05, cz - 0.7, x1 - 0.1, y + 0.05, cz + 0.7, "rip_iron")           # the screw guard
        t_part(m, cx - 0.8, y + r - 0.05, cz - 0.25, cx + 0.6, y1, cz + 0.25, "rip_sub")              # the fin
        t_part(m, cx - 0.3, y + 0.1, cz - r - 0.02, cx + 0.3, y + 0.5, cz - r + 0.02, "rip_glass")   # a porthole
        t_part(m, cx - 0.3, y + 0.1, cz + r - 0.02, cx + 0.3, y + 0.5, cz + r + 0.02, "rip_glass")
        for px in (x0 + 1.0, x1 - 1.4):                                                           # the cradle
            t_part(m, px, y0, z0 + 0.3, px + 0.3, y - r + 0.2, z1 - 0.3, "rip_yellow")
        t_part(m, x0 + 1.0, y0, z0 + 0.3, x1 - 1.1, y0 + 0.12, z0 + 0.45, "rip_yellow")
        t_part(m, x0 + 1.0, y0, z1 - 0.45, x1 - 1.1, y0 + 0.12, z1 - 0.3, "rip_yellow")
    elif kind == "sinks":                    # wash basins on a counter, mirrors over them
        t_part(m, x0, y0 + 0.6, z0, x1, y1, z1, "rip_white")
        t_part(m, x0 + 0.05, y0, z0 + 0.3, x1 - 0.05, y0 + 0.6, z0 + 0.4, "rip_bright")
        t_part(m, x0 + 0.05, y0, z1 - 0.4, x1 - 0.05, y0 + 0.6, z1 - 0.3, "rip_bright")
        n_s = max(1, int(s[2] // 1.0))
        for k in range(n_s):
            sz = z0 + (k + 0.5) * s[2] / n_s
            b.poly([(x0 + 0.1, y1 + 0.003, sz - 0.25), (x1 - 0.1, y1 + 0.003, sz - 0.25), (x1 - 0.1, y1 + 0.003, sz + 0.25),
                    (x0 + 0.1, y1 + 0.003, sz + 0.25)], (0, 1, 0), "rip_bright", uv_world(1.0))
            cyl(b, (x1 - 0.08, y1 + 0.15, sz), 0.02, 0.3, "rip_bright", sides=6)
            flat(b, (-1, 0, 0), x1 + 0.01, sz - 0.4, sz + 0.4, y1 + 0.4, y1 + 1.0, "decals", m.d("mirror"))
        flat(b, (-1, 0, 0), x1 + 0.012, z0, z0 + 1.6, y1 + 1.15, y1 + 1.45, "decals", m.d("wash"))
    elif kind == "cylinders":                # gas bottles chained in a rack against the wall
        t_part(m, x0, y0, z0, x1, y0 + 0.05, z1, "rip_iron")
        n_c = max(1, int(s[2] // 0.32))
        r2 = random.Random("%.1f" % cz)
        for k in range(n_c):
            pz = z0 + (k + 0.5) * s[2] / n_c
            col = r2.choice(["rip_teal", "rip_white", "rip_navy", "rip_white"])
            cyl(b, (cx, y0 + 0.05 + 0.7, pz), 0.13, 1.4, col, col, sides=8)
            cyl(b, (cx, y0 + 1.5, pz), 0.06, 0.1, "rip_bright", sides=6)
        t_part(m, x0, y0 + 1.0, z0, x1, y0 + 1.05, z1, "rip_iron")
    else:
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_iron")
    b.group = None


# ------------------------------------------------------------------------------------------------ details
def is_door(o):
    return o["y1"] - o["y0"] > 1.9


def door_frame(m, o):
    """A frame round a doorway, both faces: grey steel in the lab, hazard stripes at the airlocks and into the hall;
    a sill across the floor. A frame piece that would stand inside another wall is left out."""
    a0, a1, y0, y1, t = o["a0"], o["a1"], o["y0"], o["y1"], o["t"]
    fw, fd = 0.1, 0.04
    mid = (a0 + a1) / 2
    if o["axis"] == "x":
        sides = [place(mid + OX, y0 + 1.0, o["at"] + sg * (t / 2 + 0.3)) for sg in (-1, 1)]
    else:
        sides = [place(o["at"] + OX + sg * (t / 2 + 0.3), y0 + 1.0, mid) for sg in (-1, 1)]
    hazard = "DECON" in sides or "INCUBATION HALL" in sides or "AIR PLANT" in sides
    t_item(m)
    for k, sg in enumerate((-1, 1)):
        if sides[k] is None:
            continue
        face = o["at"] + sg * t / 2
        mt = "rip_hazard" if hazard else ("rip_iron" if sides[k] in STEEL else "rip_bright")
        for pa, pb, ya, yb in ((a0 - fw, a0, y0, y1 + fw), (a1, a1 + fw, y0, y1 + fw), (a0 - fw, a1 + fw, y1, y1 + fw)):
            if o["axis"] == "x":
                cc, sz = ((pa + pb) / 2, (ya + yb) / 2, face + sg * fd / 2), (pb - pa, yb - ya, fd)
            else:
                cc, sz = (face + sg * fd / 2, (ya + yb) / 2, (pa + pb) / 2), (fd, yb - ya, pb - pa)
            probe = (cc[0], cc[1], cc[2])
            # (into another wall: leave it out; the gray box's own wall is the one with the hole)
            if any(bx[0] + 0.02 < probe[0] < bx[3] - 0.02 and bx[1] + 0.02 < probe[1] < bx[4] - 0.02 and bx[2] + 0.02 < probe[2] < bx[5] - 0.02
                   for bx in m.solid):
                continue
            m.box(cc, sz, mat(mt) if mt != "rip_hazard" else (lambda n, md, q: ("rip_hazard", uv_world(1.0))), cull=False)
    # the sill: the wall's depth and a little more
    if o["axis"] == "x":
        m.box(((a0 + a1) / 2, y0 + 0.01, o["at"]), (a1 - a0, 0.02, t + 0.12), mat("rip_iron"), cull=False)
    else:
        m.box((o["at"], y0 + 0.01, (a0 + a1) / 2), (t + 0.12, 0.02, a1 - a0), mat("rip_iron"), cull=False)
    m.b.group = None


def sign_w(m, name):
    return R.sign_w(m, name, lo=1.1, hi=2.4, tallest=0.5)


def door_signs(m, o):
    """Over a doorway, on each face: the name of the room it leads into (not into a corridor or the same room)."""
    mid = (o["a0"] + o["a1"]) / 2
    top = o["y1"] + 0.16
    for sg in (-1, 1):
        face = o["at"] + sg * o["t"] / 2
        if o["axis"] == "x":
            here = place(mid + OX, o["y0"] + 1.0, face + sg * 0.4)
            there = place(mid + OX, o["y0"] + 1.0, face - sg * (o["t"] + 0.4))
        else:
            here = place(face + OX + sg * 0.4, o["y0"] + 1.0, mid)
            there = place(face + OX - sg * (o["t"] + 0.4), o["y0"] + 1.0, mid)
        if here is None or there is None or there == here or there in ("CORRIDOR", "RING", "HUB", "STAIRS"):
            continue
        name = "sign_" + there
        R.t_sign(m, o["axis"], face, sg, mid, top, name, sign_w(m, name))


def ceiling_at(rows, x, z, y_top):
    for r in rows:
        if r["pitch"] or r["yaw"] % 180 or r.get("kind"):
            continue
        c, s = r["pos"], r["size"]
        if abs(c[1] + s[1] / 2 - y_top) > 0.02 or s[1] > 0.6:
            continue
        if abs(x - c[0]) <= s[0] / 2 and abs(z - c[2]) <= s[2] / 2:
            return True
    return False


def lamps(m, below_rows):
    """Lamp panels in the ceilings, a 4 m grid: under the dock deck (the lower rooms), under the engine room deck (the
    main lab, the offices, the dock, observation). The hall gets lamps round its walls, high up, not over the tanks."""
    rows = m.data["boxes"]
    for x in range(32, 66, 4):
        for z in range(-72, 100, 4):
            xl = x - OX
            for top, src in ((LAB1, rows), (HULL_B, below_rows)):
                y = top - SLAB
                p = place(x, y - 0.5, z)
                if p is None or p in ("INCUBATION HALL", "STAIRS"):
                    continue
                if top == HULL_B and place(x, LAB1 + 0.5, z) is None:
                    continue
                if not all(ceiling_at(src, xl + dx, z + dz, top) for dx in (-0.7, 0.7) for dz in (-0.4, 0.4)):
                    continue
                if any(m.inside((xl + dx, y - 0.1, z + dz)) for dx in (-0.7, 0.7) for dz in (-0.3, 0.3)):
                    continue
                if p in STEEL:
                    t_lamp(m, xl, y, z, 0.8, 0.3)
                    for dz in (-0.18, 0.18):
                        m.box((xl, y - 0.04, z + dz), (0.9, 0.05, 0.04), mat("rip_iron"), cull=False)
                else:
                    t_lamp(m, xl, y, z, 1.2, 0.6)
    # the hall: strip lamps along the walls, 1 m under the ceiling
    for z in (40.0, 46.0, 54.0, 60.0):
        for x, n in ((HALL[0] + 0.15, 1), (HALL[1] - 0.15, -1)):
            m.b.group = bake_light.GLOW
            flat(m.b, (n, 0, 0), x - OX + n * 0.02, z - 1.0, z + 1.0, CEIL0 - 1.3, CEIL0 - 1.15, "rip_lamp", uv_world(1.0))
            m.b.group = None


def wall_art(m):
    """Big names on the walls, safety signs, the corridor lines on the floor."""
    b = m.b

    def big(name, axis, at, n, a_mid, y, w):
        reg = m.decals.regions[name]
        h = w * (reg[3] - reg[1]) / (reg[2] - reg[0])
        nn = (n, 0, 0) if axis == "z" else (0, 0, n)
        flat(b, nn, at + n * 0.014, a_mid - w / 2 - (OX if axis == "x" else 0), a_mid + w / 2 - (OX if axis == "x" else 0),
             y, y + h, "graffiti", m.d(name))
    # intake: SITE ZERO over the airlocks, facing the stairs
    big("big_SITE ZERO", "x", -56.15, -1, 48.0, LAB2 + 3.3, 7.0)
    big("big_EXION", "x", -56.15, -1, 48.0, LAB2 + 2.5, 2.6)
    R.t_sign(m, "x", -56.15, -1, 48.0 - OX, LAB2 + 1.3, "authorised", 2.6)
    for x in (38.75, 57.25):
        R.t_sign(m, "x", -56.15, -1, x - OX, LAB2 + 3.2, "decon", 1.8)
    # the main lab: its name on the hub wall, over the openings
    big("big_MAIN LAB", "x", -10.15, -1, 48.0, LAB2 + 4.0, 5.0)
    # holding: on its north wall either side of the door, facing the hub
    big("big_HOLDING", "x", 9.85, -1, 42.5, LAB2 + 2.6, 3.0)
    # the incubation hall: on its north wall outside (the ring), over the big door; inside, under the windows
    big("big_INCUBATION", "x", 37.85, -1, 48.0, LAB2 + 3.2, 6.0)
    big("big_INCUBATION", "x", 38.15, 1, 48.0, LAB2 + 4.4, 5.0)
    for x in (44.5, 51.5):
        R.t_sign(m, "x", 37.85, -1, x - OX, LAB2 + 0.9, "biohazard", 1.4)
    R.t_sign(m, "x", 62.15, 1, 48.0 - OX, LAB2 + 2.7, "biohazard", 1.4)
    for x, n in ((HALL[0] - 0.15, -1), (HALL[1] + 0.15, 1)):
        R.t_sign(m, "z", x - OX, n, 50.0, LAB2 + 2.7, "biohazard", 1.4)
    # the control room's name on its west wall, the dock's and the sub bay's in black
    big("big_CONTROL", "z", WC_IN, 1, 76.0, LAB2 + 2.8, 3.6)
    big("big_DOCK", "x", 26.85, -1, 42.0, LAB1 + 2.4, 2.4)
    big("big_SUB BAY", "z", 56.15 - OX, 1, 12.0, LAB1 + 2.6, 3.0)
    big("big_OBSERVATION", "x", 27.15, 1, 42.0, LAB1 + 2.6, 3.2)
    R.t_sign(m, "z", 56.15 - OX, 1, 21.0, LAB1 + 1.2, "keep_clear", 1.4)
    R.t_sign(m, "x", 75.85, -1, 63.0 - OX, LAB2 + 2.6, "hv", 1.2)
    # the corridors' guide lines (teal, down the middle)
    for x, z0, z1 in ((38.75, 10.0, 32.0), (57.25, 10.0, 32.0), (38.75, 68.0, 100.0), (56.5, 68.0, 76.0)):
        b.poly([(x - OX - 0.08, LAB2 + 0.006, z0), (x - OX + 0.08, LAB2 + 0.006, z0), (x - OX + 0.08, LAB2 + 0.006, z1),
                (x - OX - 0.08, LAB2 + 0.006, z1)], (0, 1, 0), "rip_teal", uv_world(1.0))
    # hazard stripes on the floor through each airlock, round the moon pool's ramp foot and the sub's cradle
    for x0, x1, z0, z1 in ((37.0, 40.5, -56.0, -55.6), (37.0, 40.5, -46.4, -46.0), (55.5, 59.0, -56.0, -55.6),
                           (55.5, 59.0, -46.4, -46.0), (56.0, 66.0, 15.0, 15.3)):
        y = (LAB2 if z1 < 0 else LAB1) + 0.006
        b.poly([(x0 - OX, y, z0), (x1 - OX, y, z0), (x1 - OX, y, z1), (x0 - OX, y, z1)], (0, 1, 0), "rip_hazard", uv_world(1.0))
    # the bow stairs' and tower stairs' doors: a STAIRS sign over each, lab side
    R.t_sign(m, "x", -73.85, 1, 50.0 - OX, LAB2 + 2.56, "sign_STAIRS", sign_w(m, "sign_STAIRS"))
    R.t_sign(m, "z", 54.0 - 0.15 - OX, -1, 88.5, LAB2 + 2.56, "sign_STAIRS", sign_w(m, "sign_STAIRS"))
    R.t_sign(m, "x", -73.85, 1, 44.0 - OX, LAB2 + 2.6, "level", 1.6)
    # clocks in the control room and the break room
    for axis, at, n, a, y in (("z", 40.5 + 0.15 - OX, 1, 80.0, LAB2 + 2.8), ("z", 65.75 - 0.012 - OX, -1, 0.0, LAB2 + 2.3)):
        flat(b, (n, 0, 0), at + n * 0.012, a - 0.2, a + 0.2, y, y + 0.4, "graffiti", m.d("clock"))


WC_IN = 40.5 + 0.15 - OX


# ------------------------------------------------------------------------------------------------ the model
def lab_rail(m, row):
    """A rail (solid in the gray box, so drawn as plate): brushed steel, a dark handrail along the top."""
    c, s = row["pos"], row["size"]
    m.box(c, s, R.rail_style("rip_iron", "rip_bright"))
    if s[1] > 0.6 and max(s[0], s[2]) > 0.5:
        along = "x" if s[0] >= s[2] else "z"
        cyl(m.b, (c[0], c[1] + s[1] / 2 + 0.03, c[2]), 0.05, max(s[0], s[2]), "rip_iron", axis=along, sides=6)


def classify(row):
    col = row["colour"]
    if row.get("kind") == "deck_curve" or col == "hull" and row["size"][1] <= 0.3:
        return "keel"
    if row.get("kind") in LAB_KINDS:
        return "lab_prop"
    if row.get("kind"):
        return "tower_prop"
    if row["pitch"]:
        return "ramp"
    if col == "hull":
        return "trunk"
    if col == "rust":
        return "rail"
    s = row["size"]
    if s[1] <= 0.3 or (s[0] > 2.5 and s[2] > 2.5 and s[1] < 0.7):
        return "slab"
    return "wall"


def build_lab(name="site_zero"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    with open(os.path.join(ROOT, "art_source", "buildings", "below_decks.json")) as f:
        below_rows = json.load(f)["boxes"]
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(R.KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = lab_decals(random.Random(name))
    decal_png = os.path.join(ROOT, "art_source", "textures", name + "_decals.png")
    if os.path.exists(decal_png):
        os.remove(decal_png)                  # (the signs are made here: paint them again every time)
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    _M[0] = m
    R._against = against
    m.rng = random.Random(name)
    paint = Paint()
    for row in data["boxes"]:
        k = classify(row)
        if k == "keel":
            keel(m, row)
        elif k == "lab_prop":
            l_prop(m, row)
        elif k == "tower_prop":
            R.t_prop(m, row)          # (R._against is this script's against() while this runs)
        elif k == "ramp":
            m.box(row["pos"], row["size"], R.ramp_style, yaw=row["yaw"], pitch=row["pitch"])
        elif k == "trunk":
            m.box(row["pos"], row["size"], lambda n, mid, q: ("rip_iron", uv_world(1.0)) if abs(n[1]) > 0.7 else "rip_steel_in")
        elif k == "rail":
            lab_rail(m, row)
        elif k == "slab":
            lab_slab(m, row)
        else:
            lab_wall(m, row, paint)
    paint.feet += lining(m)
    feet_bands(m, paint)
    for o in data["openings"]:
        if is_door(o):
            door_frame(m, o)
            door_signs(m, o)
    lamps(m, below_rows)
    wall_art(m)
    b = m.b
    # (the ship's white is its deckhouse plate, weathered: everything white down here is clean lab white)
    b.mat_names = ["rip_labwhite" if n == "rip_white" else n for n in b.mat_names]
    bake_light.CELL = 2.0
    bake_light.DARK = 0.66
    shade = [r for r in data["boxes"] if not r["pitch"] and r.get("kind") != "deck_curve"]
    shade += [r for r in below_rows if not r["pitch"] and not r["yaw"] % 180 and r.get("kind") != "deck_curve"]
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
