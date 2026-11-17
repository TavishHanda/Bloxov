"""Riptide's models (map 2, the art pass; plan: the "Riptide art plan" doc). Step 1: leviathan_hull, the ship's outside.

Works like make_building.py (it borrows its mesh builder, pixel painting, light bake and .glb writer) but Riptide has
its own texture sheet, so nothing on Frontlines changes: the tiling textures here are packed into
assets/textures/riptide_atlas.png (the same shader as Frontlines' kit atlas, assets/materials/riptide_atlas.tres), and
each model gets its own decal image for names, numbers and signs.

The gray box is still the truth (tools/gen_riptide.py): every box inside `with modeled(...)` still collides as before and
is written to art_source/buildings/<name>.json; this script only draws them. Nothing is drawn that a person could walk
into without a box behind it (the Frontlines lesson): details either sit inside a box, lie flat on it, or hang out of
reach (the derrick's bracing, the crane hooks).

    python3 art_source/scripts/make_riptide.py leviathan_hull
then re-run tools/gen_riptide.py (it hides the gray boxes once the .glb exists) and import.

Colours (Tavish, 2026-11-17, scheme C): red drillship hull, white deckhouses, yellow cranes / derrick / rails, grey deck.
"""
import math
import os
import random
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb   # noqa: E402
import bake_light            # noqa: E402
from make_building import Canvas, Builder, Atlas, Texture, uv_world, uv_fit   # noqa: E402

ROOT = mb.ROOT
mb.PALETTE.update({
    # the hull (scheme C, 0.6 0.24 0.16)
    "rh_red": "993d29", "rh_red_light": "a5452f", "rh_red_dark": "873424", "rh_seam": "70291c", "rh_rust": "6b3a1e",
    "rh_streak": "7d3b22", "rh_low": "5c2420", "rh_low_dark": "4c1e1b", "rh_low_light": "66302a", "rh_boot": "262729",
    "rh_boot_light": "323436",
    # white deckhouses (0.8 0.8 0.76), yellow (0.82 0.62 0.14), grey deck (0.45 0.46 0.46)
    "rw_white": "cccbc2", "rw_white_dark": "b9b8ae", "rw_grime": "9f9d93", "rw_light": "d6d5cc",
    "ry_yel": "d19e24", "ry_dark": "a97f1b", "ry_light": "dcae3b", "ry_chip": "5a5246",
    "rd_deck": "737575", "rd_light": "808282", "rd_dark": "626464", "rd_seam": "555757", "rd_rust": "6e4a33",
    "ri_steel": "8f928f", "ri_dark": "7c7f7c", "ri_light": "9a9d9a",
    "rx_iron": "3b3e42", "rx_iron_light": "4a4e53", "rx_black": "1e1f21",
    "rp_pipe": "5f5b55", "rp_light": "6f6a62", "rp_rust": "7a4a2b",
    "rg_glass": "2b3a44", "rg_shine": "4f6573",
    # deck containers: the gray box's container_a / b / c
    "rc_a": "8c4533", "rc_a_dark": "773a2b", "rc_a_light": "9a4f3c",
    "rc_b": "3d6185", "rc_b_dark": "335272", "rc_b_light": "476d93",
    "rc_c": "5c734d", "rc_c_dark": "4e6241", "rc_c_light": "678057",
})


# ------------------------------------------------------------------------------------------------ the texture sheet
def _seams(c, colour, rows=(0, 32), cols=((0, 0, 32), (32, 32, 64))):
    for y in rows:
        for x in range(c.w):
            c.put(x, y, colour)
    for x, y0, y1 in cols:
        for y in range(y0, y1):
            c.put(x, y, colour)


def _streaks(c, colours, n, rng, starts=(31, 63), length=(5, 16)):
    """Rust run down from the plate seams (and a few from nowhere)."""
    for _ in range(n):
        x = rng.randrange(c.w)
        y = rng.choice(starts) if rng.random() < 0.7 else rng.randrange(c.h)
        col = rng.choice(colours)
        for k in range(rng.randrange(*length)):
            if rng.random() < 0.85:
                c.put(x, y - k, col)
            if rng.random() < 0.08:
                x += rng.choice((-1, 1))


def paint_hull(rng):
    """The red hull: 4 x 2 m plates, staggered, weld seams, rust running from them, chipped paint."""
    c = Canvas(64, 64, "rh_red")
    c.noise(0, 0, 64, 64, ["rh_red_light", "rh_red_dark"], 0.1, rng)
    # (faint, 4 m plates: 2 m staggered seams read as brick from across the water)
    _seams(c, "rh_red_dark", rows=(0,), cols=((0, 0, 64),))
    _streaks(c, ["rh_rust", "rh_streak", "rh_seam"], 10, rng, starts=(63, 40, 20))
    c.blotch(["rh_rust", "rh_red_dark"], 5, rng, size=(2, 3))
    return c


def paint_hull_low(rng):
    """Under the waterline: dark anti-fouling paint, the seams fainter."""
    c = Canvas(64, 64, "rh_low")
    c.noise(0, 0, 64, 64, ["rh_low_light", "rh_low_dark"], 0.12, rng)
    _seams(c, "rh_low_dark", rows=(0,), cols=((0, 0, 64),))
    c.blotch(["rh_low_dark", "rh_low_light"], 6, rng, size=(2, 4))
    return c


def paint_boot(rng):
    """The black boot-top band at the waterline: scuffed by the fenders and the sea."""
    c = Canvas(64, 64, "rh_boot")
    c.noise(0, 0, 64, 64, ["rh_boot_light", "rx_black"], 0.12, rng)
    _seams(c, "rx_black", rows=(32,), cols=((0, 0, 64),))
    c.blotch(["rh_rust", "rh_boot_light"], 4, rng, size=(2, 3))
    return c


def paint_deck(rng):
    """Grey non-slip deck plate: a raised diamond tread, 2 m plates, scuffs and the odd rust spot."""
    c = Canvas(64, 64, "rd_deck")
    for y in range(64):
        for x in range(64):
            if (x % 4 == 0 and y % 4 == 0) or (x % 4 == 2 and y % 4 == 2):
                c.put(x, y, "rd_light")
    c.noise(0, 0, 64, 64, ["rd_dark", "rd_light"], 0.05, rng)
    _seams(c, "rd_seam", rows=(0, 32), cols=((0, 0, 64), (32, 0, 64)))
    c.blotch(["rd_dark", "rd_seam"], 6, rng, size=(2, 5))
    c.blotch(["rd_rust"], 3, rng, size=(2, 3))
    return c


def paint_steel_in(rng):
    """Painted steel inside the hull: light grey, frames every metre, seams."""
    c = Canvas(64, 64, "ri_steel")
    c.noise(0, 0, 64, 64, ["ri_dark", "ri_light"], 0.07, rng)
    for x in (0, 16, 32, 48):
        for y in range(64):
            c.put(x, y, "ri_dark")
            c.put(x + 1, y, "ri_light")
    _seams(c, "ri_dark", rows=(0, 32), cols=())
    _streaks(c, ["rp_rust", "ri_dark"], 4, rng)
    return c


def paint_white(rng):
    """Deckhouse white: 1 m panels, grime under the seams, a little rust."""
    c = Canvas(64, 64, "rw_white")
    c.noise(0, 0, 64, 64, ["rw_white_dark", "rw_light"], 0.08, rng)
    for x in (0, 16, 32, 48):
        for y in range(64):
            c.put(x, y, "rw_white_dark")
    _seams(c, "rw_white_dark", rows=(0,), cols=())
    _streaks(c, ["rw_grime", "rw_white_dark"], 8, rng, starts=(63,), length=(4, 14))
    _streaks(c, ["rh_rust"], 2, rng, starts=(63,), length=(3, 8))
    return c


def paint_yellow(rng):
    """Safety yellow: cranes, the derrick, rails. Chipped to dark primer at the edges."""
    c = Canvas(64, 64, "ry_yel")
    c.noise(0, 0, 64, 64, ["ry_dark", "ry_light"], 0.1, rng)
    c.blotch(["ry_chip", "ry_dark"], 6, rng, size=(2, 3))
    _streaks(c, ["ry_dark"], 5, rng, starts=(63,), length=(3, 10))
    return c


def paint_hazard(rng):
    """Yellow and black stripes (25 cm), worn."""
    c = Canvas(64, 64, "ry_yel")
    for y in range(64):
        for x in range(64):
            if ((x + y) // 8) % 2:
                c.put(x, y, "rx_black")
    c.noise(0, 0, 64, 64, ["ry_dark", "rx_iron"], 0.07, rng)
    c.blotch(["ry_chip"], 4, rng, size=(2, 3))
    return c


def paint_container(base):
    def paint(rng):
        """A container's corrugated side: ribs every 25 cm, rust at the bottom edge, faded paint."""
        c = Canvas(64, 64, base)
        for y in range(64):
            for x in range(64):
                if x % 4 == 0:
                    c.put(x, y, base + "_dark")
                elif x % 4 == 2:
                    c.put(x, y, base + "_light")
        c.noise(0, 0, 64, 64, [base + "_dark", base + "_light"], 0.05, rng)
        c.blotch(["rp_rust", base + "_dark"], 8, rng, size=(2, 4))
        _streaks(c, ["rp_rust"], 6, rng, starts=(63, 22, 43), length=(3, 9))
        return c
    return paint


def paint_pipe(rng):
    c = Canvas(64, 64, "rp_pipe")
    c.noise(0, 0, 64, 64, ["rp_light", "rx_iron_light"], 0.12, rng)
    c.blotch(["rp_rust", "rh_rust"], 12, rng, size=(2, 4))
    return c


def paint_iron(rng):
    """Dark steel: frames, edges, undersides."""
    c = Canvas(64, 64, "rx_iron")
    c.noise(0, 0, 64, 64, ["rx_iron_light", "rx_black"], 0.1, rng)
    c.blotch(["rp_rust"], 4, rng, size=(2, 3))
    return c


def paint_ramp(rng):
    """A steel ramp: grey plate with an anti-slip bar every half metre, its front edge yellow."""
    c = paint_deck(rng)
    for y in range(64):
        if y % 8 == 0:
            for x in range(64):
                c.put(x, y, "rx_iron_light")
        elif y % 8 == 1:
            for x in range(64):
                c.put(x, y, "ry_yel" if rng.random() < 0.9 else "ry_chip")
    return c


def paint_glass(rng):
    """Dark tinted glass on the crane cabs (out of reach, so painted on: nothing to break)."""
    c = Canvas(64, 64, "rg_glass")
    for k in range(64):
        for t in range(3):
            c.put((k + t + 10) % 64, k, "rg_shine")
            c.put((k + t + 40) % 64, k, "rg_shine")
    c.noise(0, 0, 64, 64, ["rx_iron"], 0.04, rng)
    return c


def paint_roof(rng):
    """A deckhouse roof: grey plate, darker, puddle stains."""
    c = Canvas(64, 64, "rd_dark")
    c.noise(0, 0, 64, 64, ["rd_deck", "rd_seam"], 0.1, rng)
    _seams(c, "rd_seam", rows=(0, 32), cols=((0, 0, 64),))
    c.blotch(["rd_seam", "rx_iron_light"], 8, rng, size=(3, 6))
    return c


KIT = {
    "rip_hull": paint_hull, "rip_hull_low": paint_hull_low, "rip_boot": paint_boot, "rip_deck": paint_deck,
    "rip_steel_in": paint_steel_in, "rip_white": paint_white, "rip_yellow": paint_yellow, "rip_hazard": paint_hazard,
    "rip_cont_a": paint_container("rc_a"), "rip_cont_b": paint_container("rc_b"), "rip_cont_c": paint_container("rc_c"),
    "rip_pipe": paint_pipe, "rip_iron": paint_iron, "rip_ramp": paint_ramp, "rip_glass": paint_glass,
    "rip_roof": paint_roof,
}
ATLAS_ORDER = os.path.join(ROOT, "art_source", "textures", "riptide_atlas.json")
ATLAS_PNG = os.path.join(ROOT, "assets", "textures", "riptide_atlas.png")
KIT_DIR = os.path.join("art_source", "textures", "riptide")


def riptide_atlas():
    """Riptide's sheet: the same 16 x 16 cell layout as Frontlines' kit atlas (so the same shader draws it), its own
    order file and image. Returns {kit name: cell corner}."""
    order = json.load(open(ATLAS_ORDER)) if os.path.exists(ATLAS_ORDER) else []
    for name in KIT:
        if name not in order:
            order.append(name)
    assert len(order) <= mb.ATLAS_COLS * mb.ATLAS_ROWS, "riptide atlas full"
    with open(ATLAS_ORDER, "w") as f:
        json.dump(order, f, indent=0)
    cell_px = mb.ATLAS_CELL
    wide, high = mb.ATLAS_COLS * cell_px, mb.ATLAS_ROWS * cell_px
    top = [[[0, 0, 0, 255] for _ in range(wide)] for _ in range(high)]
    cells = {}
    for i, name in enumerate(order):
        path = os.path.join(ROOT, KIT_DIR, name + ".png")
        if not os.path.exists(path):
            continue
        w, h, rows = mb.read_png(path)
        src = list(reversed(rows))
        cx, cy = mb.atlas_cell(i)
        for y in range(cell_px):
            line = src[y * h // cell_px]
            out = top[cy * cell_px + y]
            for x in range(cell_px):
                out[cx * cell_px + x] = list(line[x * w // cell_px])
        cells[name] = (cx / 8, cy / 8)
    mb.write_png(ATLAS_PNG, wide, high, list(reversed(top)))
    return cells


# ------------------------------------------------------------------------------------------------ decals
NAME = "LEVIATHAN"
DRAFTS = (18, 19, 20, 21)      # metres of draft: the keel is at y -18.75, so 19 M sits just over the waterline


def _stencil(text, scale, colour, rng, pad=1, chip=0.06):
    w, h = Canvas.text_width(text, scale) + 2 * pad, 5 * scale + 2 * pad

    def paint(c):
        c.rect(0, 0, w, h, "clear")
        c.text(pad, pad, text, colour, scale)
        for y in range(h):              # worn paint: a few pixels gone
            for x in range(w):
                if c.px[y][x] != "clear" and rng.random() < chip:
                    c.put(x, y, "clear")
    return w, h, paint


def _door_decal(base):
    """A container's door end, 2.4 x 2.6 m: two doors, four locking bars with handles, the seals."""
    def paint(c):
        w, h = c.w, c.h
        c.rect(0, 0, w, h, base)
        for x in range(w):
            if x % 5 == 0:
                for y in range(h):
                    c.put(x, y, base + "_dark")
        mid = w // 2
        c.rect(mid - 1, 0, mid + 1, h, "rx_black")         # where the doors meet
        c.frame(0, 0, w, h, base + "_dark")
        for bx in (w // 8, w * 3 // 8, w * 5 // 8, w * 7 // 8):
            c.rect(bx - 1, 2, bx + 1, h - 2, "ri_light")   # the locking bars
            c.rect(bx - 1, h // 3, bx + 4, h // 3 + 2, "ri_dark")   # their handles
            for y in (4, h - 6):
                c.rect(bx - 2, y, bx + 2, y + 3, "rx_iron")
        r = random.Random(base)
        c.blotch(["rp_rust", base + "_dark"], 10, r, size=(2, 4))
    return paint


def _sign(text, bg, fg, scale=2):
    w = Canvas.text_width(text, scale) + 8
    h = 5 * scale + 8

    def paint(c):
        c.rect(0, 0, w, h, bg)
        c.frame(0, 0, w, h, fg)
        c.text(4, 4, text, fg, scale)
    return w, h, paint


CONTAINER_LINES = {"container_a": "ORMA LINE", "container_b": "KESTREL", "container_c": "TIDELINE"}


def leviathan_decals(rng):
    a = Atlas(512)
    w, h, p = _stencil(NAME, 12, "rw_white", random.Random("name"), chip=0.015)
    a.add("name", w, h, p)
    for d in DRAFTS:
        w, h, p = _stencil("%dM" % d, 2, "rw_white", random.Random("draft%d" % d), chip=0.03)
        a.add("draft%d" % d, w, h, p)
    for kind, line in CONTAINER_LINES.items():
        w, h, p = _stencil(line, 3, "rw_light", random.Random(line), chip=0.1)
        a.add("line_" + kind, w, h, p)
    for kind, base in (("container_a", "rc_a"), ("container_b", "rc_b"), ("container_c", "rc_c")):
        a.add("doors_" + kind, 77, 83, _door_decal(base))
    w, h, p = _stencil("SWL 25T", 2, "rx_black", random.Random("swl"), chip=0.02)
    a.add("swl", w, h, p)
    w, h, p = _sign("DRILLER", "rw_white", "rx_black")
    a.add("driller", w, h, p)
    w, h, p = _sign("DRILL FLOOR", "ry_yel", "rx_black")
    a.add("drill_floor", w, h, p)
    w, h, p = _sign("NO SMOKING", "rw_white", "rh_red")
    a.add("no_smoking", w, h, p)
    return a


# ------------------------------------------------------------------------------------------------ helpers
WATER = 0.0
BOOT = (-0.8, 0.6)           # the black band round the waterline
DECK, FORECASTLE, DRILL = 4.0, 7.0, 12.0


class Model:
    def __init__(self, data, decals):
        self.data, self.decals = data, decals
        self.b = Builder()
        self.rng = random.Random("leviathan")
        # Axis-aligned boxes, to leave out the faces nobody can see (pressed against another box).
        self.solid = []
        for r in data["boxes"]:
            if r["pitch"] or r["yaw"] % 180:
                continue
            c, s = r["pos"], r["size"]
            self.solid.append(tuple(c[k] - s[k] / 2 for k in range(3)) + tuple(c[k] + s[k] / 2 for k in range(3)))

    def d(self, name):
        return uv_fit(self.decals.regions[name])

    def inside(self, p, pad=0.0):
        return any(b[0] - pad <= p[0] <= b[3] + pad and b[1] - pad <= p[1] <= b[4] + pad and b[2] - pad <= p[2] <= b[5] + pad
                   for b in self.solid)

    def hidden(self, n, mid, corners):
        """A face whose middle and corners (pulled a little in, pushed 2 cm out) are all inside other boxes. The box
        the face belongs to (or is drawn inside: a container's body inside its gray box) doesn't count."""
        back = tuple(mid[k] - n[k] * 0.02 for k in range(3))
        others = [b for b in self.solid if not (b[0] <= back[0] <= b[3] and b[1] <= back[1] <= b[4] and b[2] <= back[2] <= b[5])]
        pts = [mid] + [tuple(m + (c - m) * 0.9 for m, c in zip(mid, q)) for q in corners]
        for p in pts:
            q = tuple(p[k] + n[k] * 0.02 for k in range(3))
            if not any(b[0] <= q[0] <= b[3] and b[1] <= q[1] <= b[4] and b[2] <= q[2] <= b[5] for b in others):
                return False
        return True

    def box(self, c, s, style, yaw=0.0, pitch=0.0, cull=True):
        def st(n, mid, corners):
            if cull and not yaw % 180 and not pitch and self.hidden(n, mid, corners):
                return None
            got = style(n, mid, corners)
            if isinstance(got, str):
                return (got, uv_world())
            return got
        self.b.box(tuple(c), tuple(s), yaw, pitch, style=st)


def mat(name):
    return lambda n, m, q: name


def cyl(b, c, r, h, mat_side, mat_cap=None, axis="y", sides=10, caps=(True, True)):
    """A cylinder round c (its middle) along axis, radius r, length h."""
    ring = [(math.cos(2 * math.pi * (k + 0.5) / sides), math.sin(2 * math.pi * (k + 0.5) / sides)) for k in range(sides)]

    def pt(e, u, v):
        if axis == "y":
            return (c[0] + u * r, c[1] + e * h / 2, c[2] + v * r)
        if axis == "x":
            return (c[0] + e * h / 2, c[1] + v * r, c[2] + u * r)
        return (c[0] + u * r, c[1] + v * r, c[2] + e * h / 2)

    def nrm(u, v):
        return {"y": (u, 0, v), "x": (0, v, u), "z": (u, v, 0)}[axis]
    cap = {"y": (0, 1, 0), "x": (1, 0, 0), "z": (0, 0, 1)}[axis]
    for e, on in zip((-1, 1), caps):
        if on:
            b.poly([pt(e, u, v) for u, v in ring], tuple(e * k for k in cap), mat_cap or mat_side, uv_world(1.0))
    for k in range(sides):
        (u0, v0), (u1, v1) = ring[k], ring[(k + 1) % sides]
        b.poly([pt(-1, u0, v0), pt(-1, u1, v1), pt(1, u1, v1), pt(1, u0, v0)], nrm((u0 + u1) / 2, (v0 + v1) / 2),
               mat_side, uv_world(2.0))


def flat(b, n, at, a0, a1, y0, y1, mat_name, uv):
    """A flat picture on a face: normal n along +-x or +-z, plane at `at`, from a0 to a1 along it, y0 to y1."""
    mb.wall_quad(b, n, at, a0, a1, y0, y1, mat_name, uv)


# ------------------------------------------------------------------------------------------------ the hull
OUTER_BANDS = ((-99.0, BOOT[0], "rip_hull_low"), (BOOT[0], BOOT[1], "rip_boot"), (BOOT[1], 99.0, "rip_hull"))


def band_face(m, n, at, a0, a1, y0, y1, bands, z_splits=()):
    """A vertical face (normal n along x or z, plane at `at`, a0..a1 along it, y0..y1) drawn in horizontal bands
    [(from, to, material)], cut at z_splits too; pieces pressed against another box are left out."""
    cuts = [a0] + [v for v in z_splits if a0 < v < a1] + [a1]
    for ca, cb in zip(cuts, cuts[1:]):
        for lo, hi, mt in (bands(ca, cb) if callable(bands) else bands):
            lo, hi = max(lo, y0), min(hi, y1)
            if hi - lo < 0.01:
                continue
            if n[2]:
                corners = [(ca, lo, at), (cb, lo, at), (cb, hi, at), (ca, hi, at)]
            else:
                corners = [(at, lo, ca), (at, lo, cb), (at, hi, cb), (at, hi, ca)]
            mid = tuple(sum(q[k] for q in corners) / 4 for k in range(3))
            if m.hidden(n, mid, corners):
                continue
            flat(m.b, n, at, ca, cb, lo, hi, mt, uv_world())


def hull_box(m, row):
    """A plate of the hull: red outside (dark anti-fouling under the water, a black band at the waterline), white
    inside the rail round an open deck, painted steel inside the hull, a yellow cap on the rail; the edges of every
    gap are dark steel, yellow above the deck (the rail's ends). The ship's corners are red like the sides."""
    c, s = row["pos"], row["size"]
    lo = [c[k] - s[k] / 2 for k in range(3)]
    hi = [c[k] + s[k] / 2 for k in range(3)]
    thin = 0 if s[0] < s[2] else 2
    if thin == 0 and abs(c[0]) < 17.9 or thin == 2 and abs(c[2]) < 103.9:
        return False
    b = m.b
    top = hi[1]
    if not (abs(top - DECK) < 0.02 or abs(top - FORECASTLE) < 0.02):
        corners = [(lo[0], top, lo[2]), (hi[0], top, lo[2]), (hi[0], top, hi[2]), (lo[0], top, hi[2])]
        mid = (c[0], top, c[2])
        if not m.hidden((0, 1, 0), mid, corners):
            b.poly(corners, (0, 1, 0), "rip_yellow", uv_world(1.0))

    def inner_bands(ca, cb):
        deck_y = FORECASTLE if (cb <= -89.99 and thin == 0) or (thin == 2 and c[2] < 0) else DECK
        return ((-99.0, deck_y, "rip_steel_in"), (deck_y, 99.0, "rip_white"))
    end_bands = ((-99.0, DECK, "rip_iron"), (DECK, 99.0, "rip_yellow"))
    for axis in (0, 2):
        other = 2 if axis == 0 else 0
        for sg in (-1, 1):
            n = [0, 0, 0]
            n[axis] = sg
            n = tuple(n)
            at = hi[axis] if sg > 0 else lo[axis]
            a0, a1 = lo[other], hi[other]
            if axis == thin:
                out = (c[axis] > 0) == (sg > 0)
                band_face(m, n, at, a0, a1, lo[1], hi[1], OUTER_BANDS if out else inner_bands,
                          z_splits=(-90.0,) if axis == 0 else ())
            else:
                corner = abs(abs(at) - 18.0) < 0.05 or abs(at + 104.0) < 0.05 or abs(at - 110.0) < 0.05
                band_face(m, n, at, a0, a1, lo[1], hi[1], OUTER_BANDS if corner else end_bands)
    return True


def deck_strips(m):
    """Where a gap in the rail comes down to the deck, the hull's top under it is deck plate (the slab stops at the
    hull's middle): a strip from there to the outside."""
    for row in m.data["boxes"]:
        if row["colour"] != "hull":
            continue
        c, s = row["pos"], row["size"]
        top = c[1] + s[1] / 2
        if not (abs(top - DECK) < 0.02 or abs(top - FORECASTLE) < 0.02):
            continue
        if s[0] < s[2] and abs(c[0]) > 17.9:
            x0, x1 = (18.0, 18.25) if c[0] > 0 else (-18.25, -18.0)
            z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
        elif abs(c[2]) > 103.9:
            z0, z1 = (110.0, 110.25) if c[2] > 0 else (-104.25, -104.0)
            x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
        else:
            continue
        m.b.poly([(x0, top, z0), (x1, top, z0), (x1, top, z1), (x0, top, z1)], (0, 1, 0), "rip_deck", uv_world())


def hull_details(m):
    """The name on both bows and the stern, draft marks fore and aft, anchors in their pockets."""
    b = m.b
    reg = m.decals.regions["name"]
    # bows: the name reads bow to stern on both sides, as painted on a real ship (from outside, left to right)
    L, H = 13.5, 1.9
    y0 = 1.25     # (under the rubbing strake, 3.28 up: it stands out in front and hid the letters' tops)
    z0 = -80.0      # (aft of the anchors, the launch's hull door and its ladder)
    flat(b, (-1, 0, 0), -18.27, z0, z0 + L, y0, y0 + H, "graffiti", uv_fit(reg))
    flat(b, (1, 0, 0), 18.27, z0, z0 + L, y0, y0 + H, "graffiti", uv_fit(reg))
    # the stern: across the transom, under the rail
    flat(b, (0, 0, 1), 110.27, -4.9, 4.9, 3.76, 3.76 + 1.39, "graffiti", uv_fit(reg))   # (over the stern door)
    # draft marks: fore and aft, both sides
    for z in (-102.6, 107.0):
        for side in (-1, 1):
            for dm in DRAFTS:
                y = dm - 18.75
                flat(b, (side, 0, 0), side * 18.27, z - 0.45, z + 0.45, y, y + 0.36, "graffiti", m.d("draft%d" % dm))
    # anchors: a dark pocket in the hull at each bow, the anchor's crown and flukes in it, a hawse pipe above
    for side in (-1, 1):
        x = side * 18.25
        zc = -97.5
        pocket = [(x + side * 0.01, 1.2, zc - 1.6), (x + side * 0.01, 1.2, zc + 1.6), (x + side * 0.01, 4.6, zc + 1.6),
                  (x + side * 0.01, 4.6, zc - 1.6)]
        b.poly(pocket, (side, 0, 0), "rip_iron", uv_world())
        m.box((x + side * 0.12, 3.6, zc), (0.2, 1.6, 0.3), mat("rip_pipe"), cull=False)   # the shank
        m.box((x + side * 0.15, 2.4, zc), (0.26, 0.5, 2.2), mat("rip_pipe"), cull=False)                  # the flukes
        for dz in (-0.9, 0.9):
            m.box((x + side * 0.15, 2.85, zc + dz), (0.26, 0.5, 0.4), mat("rip_pipe"), cull=False)
    # a rubbing strake along each side at the deck line: a dark steel band you see the length of the ship
    # (broken round the anchor pockets, the hull doors and the ladders up the side: nothing sticks out across them)
    gaps = {-1: [(-99.4, -95.6), (4.6, 7.0), (37.4, 39.6)], 1: [(-99.4, -95.6), (-89.1, -82.8), (42.8, 45.2), (48.9, 51.1)]}
    for side in (-1, 1):
        x = side * 18.25
        cuts = [-104.0] + [v for g in gaps[side] for v in g] + [110.0]
        for z0_, z1_ in zip(cuts[0::2], cuts[1::2]):
            m.box((x + side * 0.08, 3.4, (z0_ + z1_) / 2), (0.16, 0.25, z1_ - z0_), mat("rip_iron"), cull=False)


# ------------------------------------------------------------------------------------------------ decks
def deck_style(m, row, top="rip_deck", under="rip_steel_in"):
    def style(n, mid, corners):
        if n[1] > 0.7:
            return (top, uv_world())
        if n[1] < -0.7:
            return (under, uv_world())
        return ("rip_iron", uv_world(1.0))
    return style


def ramp_style(n, mid, corners):
    if n[1] > 0.5:
        return ("rip_ramp", uv_world(4.0))
    if n[1] < -0.5:
        return ("rip_iron", uv_world())
    return ("rip_yellow", uv_world(1.0))


def rail_style(top="rip_yellow", side="rip_yellow"):
    def style(n, mid, corners):
        if n[1] > 0.7:
            return (top, uv_world(1.0))
        if n[1] < -0.7:
            return None
        return (side, uv_world(1.0))
    return style


def rail(m, row):
    """A solid rail (the gray box is solid, so it's drawn as plate, not as see-through bars): yellow plate with a
    round handrail along the top and posts every 1.5 m."""
    c, s = row["pos"], row["size"]
    m.box(c, s, rail_style())
    along = 0 if s[0] >= s[2] else 2
    L = s[along]
    top = c[1] + s[1] / 2
    hc = (c[0], top + 0.03, c[2])
    cyl(m.b, hc, 0.06, L, "rip_yellow", axis="x" if along == 0 else "z", sides=6, caps=(True, True))


def coaming(m, row):
    """A hatch's coaming: hazard stripes on the top you'd trip over, yellow sides."""
    m.box(row["pos"], row["size"], lambda n, mid, q: ("rip_hazard", uv_world()) if n[1] > 0.7 else
          (None if n[1] < -0.7 else ("rip_yellow", uv_world(1.0))))


def deck_lines(m):
    """Painted walkways: a yellow line about a metre in from each rail, along the open deck, broken wherever something
    stands on the deck or the deck has a hole (the companionways); hazard bands on the deck round the hatches."""
    b = m.b
    y = DECK + 0.012
    rows = m.data["boxes"]
    slabs = [r for r in rows if r["colour"] == "metal" and not r["pitch"] and abs(r["pos"][1] + r["size"][1] / 2 - DECK) < 0.02]
    stand = [r for r in rows if not r["pitch"] and abs(r["pos"][1] - r["size"][1] / 2 - DECK) < 0.15 and r["colour"] != "hull"]

    def covers(r, x, z, pad=0.0):
        return (abs(x - r["pos"][0]) <= r["size"][0] / 2 + pad and abs(z - r["pos"][2]) <= r["size"][2] / 2 + pad)

    for x in (-16.6, 16.6):
        run = None
        z = -89.0
        while z <= 73.0:
            ok = any(covers(r, x, z) for r in slabs) and not any(covers(r, x, z, 0.25) for r in stand)
            ok = ok and not (-36.5 < z < -14.0 and x < 0) and not (14.0 < z < 36.5 and x > 0)   # (under the ramps up)
            if ok and run is None:
                run = z
            if (not ok or z + 0.1 > 73.0) and run is not None:
                if z - run > 1.0:
                    b.poly([(x - 0.06, y, run), (x + 0.06, y, run), (x + 0.06, y, z), (x - 0.06, y, z)], (0, 1, 0),
                           "rip_yellow", uv_world(1.0))
                run = None
            z = round(z + 0.1, 2)
    # hazard bands round the hatches: on the deck, against the coamings' outsides
    for z0, z1 in ((-50.45, -43.55), (23.55, 30.45)):
        for (xa, xb, za, zb) in ((-6.95, 6.95, z0 - 0.5, z0), (-6.95, 6.95, z1, z1 + 0.5), (-6.95, -6.45, z0, z1),
                                 (6.45, 6.95, z0, z1)):
            b.poly([(xa, y, za), (xb, y, za), (xb, y, zb), (xa, y, zb)], (0, 1, 0), "rip_hazard", uv_world())


# ------------------------------------------------------------------------------------------------ deck cargo
CONT_MAT = {"container_a": "rip_cont_a", "container_b": "rip_cont_b", "container_c": "rip_cont_c"}


def container(m, row, k):
    """A stack of 20-foot containers: corrugated sides and roof, doors on one end, corner posts and rails in dark
    steel, the line's name on the long sides."""
    c, s = row["pos"], row["size"]
    kind = row["colour"]
    body = CONT_MAT[kind]
    along = 0 if s[0] > s[2] else 2
    units = max(1, round(s[1] / 2.6))
    uh = s[1] / units
    y_base = c[1] - s[1] / 2
    door_end = 1 if k % 2 else -1
    for u in range(units):
        yc = y_base + uh * (u + 0.5)
        size = list(s)
        size[1] = uh
        inner = [size[0] - (0.08 if along == 2 else 0.04), uh - 0.12, size[2] - (0.08 if along == 0 else 0.04)]

        def style(n, mid, corners, along=along):
            if n[1] > 0.7:
                return (body, uv_world())
            if n[1] < -0.7:
                return None
            if abs(n[along]) > 0.7:
                return ("rip_iron", uv_world(1.0))
            return (body, uv_world())
        m.box((c[0], yc, c[2]), inner, style, cull=u == 0)
        # corner posts and the top and bottom rails
        hx, hz = size[0] / 2, size[2] / 2
        for sx in (-1, 1):
            for sz in (-1, 1):
                m.box((c[0] + sx * (hx - 0.08), yc, c[2] + sz * (hz - 0.08)), (0.16, uh, 0.16), mat("rip_iron"), cull=False)
        for yy in (yc - uh / 2 + 0.08, yc + uh / 2 - 0.08):
            for sg in (-1, 1):
                if along == 0:
                    m.box((c[0], yy, c[2] + sg * (hz - 0.06)), (size[0] - 0.32, 0.16, 0.12), mat("rip_iron"), cull=False)
                else:
                    m.box((c[0] + sg * (hx - 0.06), yy, c[2]), (0.12, 0.16, size[2] - 0.32), mat("rip_iron"), cull=False)
        # the doors (one end) and the name (both long sides)
        if along == 0:
            x_end = c[0] + door_end * (hx + 0.005 - 0.02)
            flat(m.b, (door_end, 0, 0), x_end, c[2] - hz + 0.16, c[2] + hz - 0.16, yc - uh / 2 + 0.16, yc + uh / 2 - 0.16,
                 "decals", m.d("doors_" + kind))
            for sg in (-1, 1):
                z = c[2] + sg * (hz - 0.035)
                flat(m.b, (0, 0, sg), z, c[0] - 1.55, c[0] + 1.55, yc + 0.35, yc + 0.85, "graffiti", m.d("line_" + kind))
        else:
            z_end = c[2] + door_end * (hz + 0.005 - 0.02)
            flat(m.b, (0, 0, door_end), z_end, c[0] - hx + 0.16, c[0] + hx - 0.16, yc - uh / 2 + 0.16, yc + uh / 2 - 0.16,
                 "decals", m.d("doors_" + kind))
            for sg in (-1, 1):
                x = c[0] + sg * (hx - 0.035)
                flat(m.b, (sg, 0, 0), x, c[2] - 1.55, c[2] + 1.55, yc + 0.35, yc + 0.85, "graffiti", m.d("line_" + kind))


def pipe_rack(m, row, r=0.28, rows=None):
    """Pipes stacked in a rack: frames at the ends and every 4 m, pipes along the long side filling the box."""
    c, s = row["pos"], row["size"]
    along = 0 if s[0] >= s[2] else 2
    across = 2 if along == 0 else 0
    L, W, H = s[along], s[across], s[1]
    y0 = c[1] - H / 2
    nf = max(2, int(L / 4) + 1)
    for i in range(nf):
        a = -L / 2 + 0.1 + i * (L - 0.2) / (nf - 1)
        for sg in (-1, 1):   # posts
            p = list(c)
            p[along] += a
            p[across] += sg * (W / 2 - 0.08)
            p[1] = y0 + H / 2
            size = [0.16, H, 0.16]
            m.box(p, size, mat("rip_yellow"), cull=False)
        p = list(c)
        p[along] += a
        p[1] = y0 + H - 0.08
        size = [0.16, 0.16, 0.16]
        size[across] = W
        m.box(p, size, mat("rip_yellow"), cull=False)
        p[1] = y0 + 0.08
        m.box(p, size, mat("rip_yellow"), cull=False)
    n_across = max(1, int((W - 0.3) / (2 * r + 0.06)))
    n_up = max(1, int((H - 0.2) / (2 * r + 0.04)))
    for j in range(n_up):
        for i in range(n_across):
            p = list(c)
            p[across] += -W / 2 + 0.15 + (i + 0.5) * (W - 0.3) / n_across + (0.1 if j % 2 else 0.0)
            p[1] = y0 + 0.16 + r + j * (2 * r + 0.04)
            if p[1] + r > y0 + H - 0.16:
                continue
            cyl(m.b, tuple(p), r, L - 0.1, "rip_pipe", "rip_iron", axis="x" if along == 0 else "z", sides=8)


# ------------------------------------------------------------------------------------------------ cranes
def crane_pedestal(m, row):
    """A deck crane's pedestal: a round yellow column on a foot, the slewing house on top (the cab, glass to the
    boom side), all inside the gray box."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b = m.b
    m.box((c[0], y0 + 0.2, c[2]), (2.4, 0.4, 2.4), mat("rip_yellow"))                     # the foot plate
    cyl(b, (c[0], y0 + 0.4 + 2.9, c[2]), 0.85, 5.8, "rip_yellow", sides=12, caps=(False, False))
    cyl(b, (c[0], y0 + 6.3, c[2]), 1.15, 0.2, "rip_iron", sides=12)                         # the slewing ring
    house_y0 = y0 + 6.4
    m.box((c[0], (house_y0 + y1) / 2, c[2]), (2.4, y1 - house_y0, 2.4),
          lambda n, mid, q: "rip_roof" if n[1] > 0.7 else (None if n[1] < -0.7 else "rip_yellow"))
    # the cab's windows: on the boom's side (east) and the front (north / south)
    for nz in (-1, 1):
        flat(b, (0, 0, nz), c[2] + nz * 1.205, c[0] - 0.2, c[0] + 1.0, house_y0 + 1.0, house_y0 + 2.2, "rip_glass", uv_world())
    flat(b, (1, 0, 0), c[0] + 1.205, c[2] - 0.9, c[2] + 0.9, house_y0 + 1.0, house_y0 + 2.2, "rip_glass", uv_world())


def crane_jib(m, row):
    """The jib: a box girder (solid like its gray box), the safe working load painted on, a sheave at the tip and
    the hook hanging from it out of reach."""
    c, s = row["pos"], row["size"]
    b = m.b
    m.box(c, s, lambda n, mid, q: "rip_yellow")
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    for nz in (-1, 1):
        flat(b, (0, 0, nz), c[2] + nz * (s[2] / 2 + 0.005), c[0] - 0.6, c[0] + 0.6, c[1] - 0.2, c[1] + 0.2, "graffiti",
             m.d("swl"))
        # a dark band near the root and the tip
        for xa in (x0 + 0.8, x1 - 1.2):
            flat(b, (0, 0, nz), c[2] + nz * (s[2] / 2 + 0.004), xa, xa + 0.4, c[1] - s[1] / 2, c[1] + s[1] / 2, "rip_hazard",
                 uv_world())
    tip = (x1 - 0.3, c[1] - s[1] / 2, c[2])
    cyl(b, (tip[0], tip[1] - 0.25, tip[2]), 0.3, 0.3, "rip_iron", axis="z", sides=8)
    hook_y = DECK + 6.8          # (the hook block at 10.8 m: over a stacked container's top at 9.2, out of reach)
    cyl(b, (tip[0], (tip[1] - 0.5 + hook_y + 0.45) / 2, tip[2]), 0.03, tip[1] - 0.5 - hook_y - 0.45, "rip_iron", sides=4,
        caps=(False, False))
    m.box((tip[0], hook_y + 0.2, tip[2]), (0.45, 0.5, 0.3), lambda n, mid, q: "rip_hazard" if abs(n[1]) < 0.7 else "rip_iron",
          cull=False)
    m.box((tip[0], hook_y - 0.15, tip[2]), (0.1, 0.25, 0.1), mat("rip_iron"), cull=False)
    m.box((tip[0] + 0.1, hook_y - 0.3, tip[2]), (0.3, 0.08, 0.1), mat("rip_iron"), cull=False)


# ------------------------------------------------------------------------------------------------ the drill floor
def drill_column(m, row):
    """The drill floor's legs: white box columns, hazard stripes round the bottom metre, gussets at the top."""
    c, s = row["pos"], row["size"]
    y0 = c[1] - s[1] / 2
    y1 = c[1] + s[1] / 2

    def style(n, mid, corners):
        if abs(n[1]) > 0.7:
            return None
        return "rip_white"
    m.box((c[0], (y0 + 1.0 + y1) / 2, c[2]), (s[0], y1 - y0 - 1.0, s[2]), style, cull=False)
    m.box((c[0], y0 + 0.5, c[2]), (s[0], 1.0, s[2]), lambda n, mid, q: None if abs(n[1]) > 0.7 else "rip_hazard", cull=False)


def derrick(m, legs, crown):
    """The derrick: four yellow legs, girts and diagonals between them from 4 m over the drill floor (out of reach,
    no collision: they're mostly air, shots go through as they look), the crown on top with its sheaves, a
    travelling block over the well, flood lights (baked glow: no real lights)."""
    b = m.b
    xs = sorted({r["pos"][0] for r in legs})
    zs = sorted({r["pos"][2] for r in legs})
    ytop = crown["pos"][1] - crown["size"][1] / 2
    for r in legs:
        m.box(r["pos"], r["size"], lambda n, mid, q: None if abs(n[1]) > 0.7 else "rip_yellow", cull=False)
    levels = [16.0 + i * 4.0 for i in range(7)]          # girts every 4 m from 16 to 40
    levels = [y for y in levels if y < ytop - 0.5] + [ytop - 0.3]

    def member(p0, p1, w=0.22):
        d = [p1[k] - p0[k] for k in range(3)]
        L = math.sqrt(sum(v * v for v in d))
        mid = tuple((p0[k] + p1[k]) / 2 for k in range(3))
        yaw = math.degrees(math.atan2(d[0], d[2]))
        horiz = math.sqrt(d[0] ** 2 + d[2] ** 2)
        pitch = -math.degrees(math.atan2(d[1], horiz))
        m.box(mid, (w, w, L), mat("rip_yellow"), yaw=yaw, pitch=pitch, cull=False)
    # the four faces: x faces (z fixed) and z faces (x fixed)
    for zf in zs:
        for i, y in enumerate(levels):
            member((xs[0] + 0.4, y, zf), (xs[1] - 0.4, y, zf))
            if i + 1 < len(levels):
                y2 = levels[i + 1]
                a, e = ((xs[0], y), (xs[1], y2)) if i % 2 == 0 else ((xs[1], y), (xs[0], y2))
                member((a[0], a[1], zf), (e[0], e[1], zf), 0.16)
    for xf in xs:
        for i, y in enumerate(levels):
            member((xf, y, zs[0] + 0.4), (xf, y, zs[1] - 0.4))
            if i + 1 < len(levels):
                y2 = levels[i + 1]
                a, e = ((zs[0], y), (zs[1], y2)) if i % 2 == 0 else ((zs[1], y), (zs[0], y2))
                member((xf, a[1], a[0]), (xf, e[1], e[0]), 0.16)
    # the crown: a box frame round a plated top, sheaves in the middle
    c, s = crown["pos"], crown["size"]
    m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else ("rip_iron" if n[1] < -0.7 else "rip_yellow"), cull=False)
    for dz in (-1.2, 0.0, 1.2):
        cyl(b, (0.0, c[1] + s[1] / 2 + 0.5, -1.0 + dz), 0.9, 0.3, "rip_iron", axis="z", sides=10)
    m.box((0.0, c[1] + s[1] / 2 + 0.25, -1.0), (2.4, 0.5, 3.6), mat("rip_yellow"), cull=False)
    # the travelling block and the hook over the well, hanging on its lines from the crown (out of reach: 26 m up)
    blk_y = 27.0
    for dx in (-0.25, 0.25):
        cyl(b, (dx, (blk_y + 1.0 + c[1] - s[1] / 2) / 2, -1.0), 0.03, (c[1] - s[1] / 2) - (blk_y + 1.0), "rip_iron", sides=4,
            caps=(False, False))
    m.box((0.0, blk_y + 0.5, -1.0), (1.2, 1.6, 0.9), lambda n, mid, q: "rip_hazard" if abs(n[1]) < 0.7 else "rip_iron",
          cull=False)
    m.box((0.0, blk_y - 0.7, -1.0), (0.9, 0.8, 0.9), mat("rip_yellow"), cull=False)    # the top drive
    # flood lights on the derrick's legs, facing in and down at the drill floor (baked glow)
    for r in legs:
        x, z = r["pos"][0], r["pos"][2]
        for y in (20.0, 32.0):
            g = b.group
            b.group = bake_light.GLOW
            ix, iz = (-1 if x > 0 else 1), (-1 if z > -1 else 1)
            m.box((x + ix * 0.55, y, z + iz * 0.55), (0.5, 0.35, 0.5),
                  lambda n, mid, q: "rip_lamp" if n[1] < -0.7 else "rip_iron", cull=False)
            b.group = g


def drill_beams(m):
    """Girders under the drill floor (8 m over the deck: out of reach), so its underside isn't a flat lid."""
    y = DRILL - 0.25 - 0.22
    for x in (-16.0, -12.0, 12.0, 16.0):
        m.box((x, y, 0.0), (0.3, 0.44, 27.6), mat("rip_white"), cull=False)
    for x in (-6.0, -2.0, 2.0, 6.0):
        for z0, z1 in ((-13.8, -9.0), (7.0, 13.8)):
            m.box((x, y, (z0 + z1) / 2), (0.3, 0.44, z1 - z0), mat("rip_white"), cull=False)
    for z in (-13.6, -9.15, 7.15, 13.6):
        m.box((0.0, y - 0.01, z), (35.4, 0.42, 0.3), mat("rip_white"), cull=False)


def drawworks(m, row):
    """The drawworks: a skid, the big cable drum, a motor housing either side."""
    c, s = row["pos"], row["size"]
    y0 = c[1] - s[1] / 2
    m.box((c[0], y0 + 0.15, c[2]), (s[0], 0.3, s[2]), mat("rip_iron"))
    cyl(m.b, (c[0], y0 + 1.1, c[2]), 0.8, s[2] - 2.0, "rip_iron", "rip_yellow", axis="z", sides=12)
    for sg in (-1, 1):
        m.box((c[0], y0 + 1.15, c[2] + sg * (s[2] / 2 - 0.5)), (s[0], s[1] - 0.3, 1.0), mat("rip_yellow"), cull=False)


def shack_wall(m, row):
    c, s = row["pos"], row["size"]
    m.box(c, s, lambda n, mid, q: None if n[1] < -0.7 else ("rip_white" if abs(n[1]) < 0.7 else "rip_white"))


def shack_roof(m, row):
    c, s = row["pos"], row["size"]
    m.box(c, s, lambda n, mid, q: "rip_roof" if n[1] > 0.7 else ("rip_steel_in" if n[1] < -0.7 else "rip_white"))


def shack_details(m):
    """The driller's shack: frames round its windows and doors, its sign over both doors."""
    b = m.b
    for z in (8.5, 13.5):                    # windows, centred at x 0, 1.6 wide, 13.0 to 14.2
        for sg in (-1, 1):
            zf = z + sg * 0.15
            for (xa, xb, ya, yb) in ((-0.9, 0.9, 12.92, 13.0), (-0.9, 0.9, 14.2, 14.28), (-0.88, -0.8, 13.0, 14.2),
                                     (0.8, 0.88, 13.0, 14.2)):
                m.box(((xa + xb) / 2, (ya + yb) / 2, zf + sg * 0.03), (xb - xa, yb - ya, 0.06), mat("rip_iron"), cull=False)
    for x in (-4.0, 4.0):                    # doors at z 11, 2.2 wide, to 14.4
        sg = 1 if x > 0 else -1
        xf = x + sg * 0.18
        for (za, zb, ya, yb) in ((9.84, 9.9, 12.0, 14.46), (12.1, 12.16, 12.0, 14.46), (9.84, 12.16, 14.4, 14.46)):
            m.box((xf, (ya + yb) / 2, (za + zb) / 2), (0.06, yb - ya, zb - za), mat("rip_iron"), cull=False)
        flat(b, (sg, 0, 0), x + sg * 0.155, 10.3, 11.7, 14.5, 14.82, "decals", m.d("driller"))


def drill_signs(m):
    """DRILL FLOOR at the top of both ramps (on the wind wall beside the gap), NO SMOKING on the shack."""
    b = m.b
    # the west ramp comes up at x -15 through the north wall's gap (x -16.7..-13.3): a sign on the wall east of it
    flat(b, (0, 0, -1), -14.11, -12.8, -10.0, DRILL + 0.35, DRILL + 1.0, "decals", m.d("drill_floor"))
    flat(b, (0, 0, 1), 14.11, 10.0, 12.8, DRILL + 0.35, DRILL + 1.0, "decals", m.d("drill_floor"))
    flat(b, (0, 0, -1), 8.33, 1.2, 2.6, 13.0, 13.45, "decals", m.d("no_smoking"))


# ------------------------------------------------------------------------------------------------ the forecastle
def forecastle_wall(m, row):
    """The forecastle's front (the bow store's wall, facing aft): white outside, steel inside."""
    c, s = row["pos"], row["size"]

    def style(n, mid, corners):
        if n[1] > 0.7:
            return ("rip_yellow", uv_world(1.0)) if mid[1] > FORECASTLE + 0.1 else None
        if n[1] < -0.7:
            return None
        if n[2] > 0.7:
            return "rip_white"
        if n[2] < -0.7:
            return "rip_steel_in" if mid[1] < FORECASTLE else "rip_white"
        return ("rip_iron", uv_world(1.0)) if mid[1] < FORECASTLE else ("rip_yellow", uv_world(1.0))
    m.box(c, s, style)


def forecastle_details(m):
    b = m.b
    # door frames on the bow store's doors (x -8 and 10, 2 m wide, to 6.4)
    for x in (-8.0, 10.0):
        for (xa, xb, ya, yb) in ((x - 1.08, x - 1.0, 4.0, 6.48), (x + 1.0, x + 1.08, 4.0, 6.48), (x - 1.08, x + 1.08, 6.4, 6.48)):
            m.box(((xa + xb) / 2, (ya + yb) / 2, -89.82), (xb - xa, yb - ya, 0.06), mat("rip_iron"), cull=False)
    flat(b, (0, 0, 1), -89.84, -12.6, -10.2, 5.2, 5.66, "decals", m.d("no_smoking"))   # (beside the west door: the
    # bow stairs' head house stands 2 m in front of the wall's middle)


# ------------------------------------------------------------------------------------------------ hull openings
def hull_openings(m):
    """Frames round the doors cut through the hull (the pier door, the boats' doors, the stern ramp's door), both
    faces, dark steel."""
    def frame_x(x, z, y0, y1, w, sides):
        for sg in sides:
            xf = x + sg * 0.28
            for (za, zb, ya, yb) in ((z - w / 2 - 0.12, z - w / 2, y0, y1 + 0.12), (z + w / 2, z + w / 2 + 0.12, y0, y1 + 0.12),
                                     (z - w / 2 - 0.12, z + w / 2 + 0.12, y1, y1 + 0.12)):
                m.box((xf, (ya + yb) / 2, (za + zb) / 2), (0.06, yb - ya, zb - za), mat("rip_iron"), cull=False)

    frame_x(-18.0, 5.8, 1.5, 3.7, 2.0, (-1, 1))
    frame_x(18.0, -84.0, 1.0, 3.2, 2.0, (-1, 1))
    frame_x(18.0, 44.0, 1.0, 3.2, 2.0, (-1, 1))
    # the stern door: 8 m wide, from 0.95 to 3.5; heavy dark frame and hinge blocks along its bottom
    for sg in (-1, 1):
        zf = 110.0 + sg * 0.28
        for (xa, xb, ya, yb) in ((-4.2, -4.0, 0.95, 3.7), (4.0, 4.2, 0.95, 3.7), (-4.2, 4.2, 3.5, 3.7)):
            m.box(((xa + xb) / 2, (ya + yb) / 2, zf), (xb - xa, yb - ya, 0.06), mat("rip_iron"), cull=False)
    for x in (-3.0, 0.0, 3.0):
        m.box((x, 0.85, 110.3), (0.6, 0.25, 0.12), mat("rip_hazard"), cull=False)


# ------------------------------------------------------------------------------------------------ the model
def classify(row):
    c, s, col = row["pos"], row["size"], row["colour"]
    if col == "hull":
        if abs(c[2] + 90.0) < 0.2 and s[2] < 0.5:
            return "forecastle_wall"
        return "hull"
    if col in CONT_MAT:
        return "container"
    if col == "metal":
        if row["pitch"]:
            return "ramp"
        if abs(c[1] - DRILL - 1.0) < 0.05 and s[1] > 1.5:
            return "drawworks"
        return "slab"
    if col == "wall":
        return "shack_wall"
    if col == "roof":
        return "shack_roof"
    if col == "rust":
        if s[1] > 20:
            return "riser" if s[0] > 1.0 else "derrick_leg"
        if abs(c[1] - 40.5) < 0.05:
            return "crown"
        if abs(s[0] - 2.4) < 0.05 and abs(s[1] - 9.0) < 0.05:
            return "pedestal"
        if abs(s[1] - 0.8) < 0.05 and s[0] > 10:
            return "jib"
        if abs(s[1] - 7.75) < 0.05:
            return "drill_column"
        if abs(s[1] - 0.5) < 0.05:
            return "coaming"
        if min(s[0], s[2]) <= 0.25 and s[1] <= 1.15:
            return "rail"
        if s[1] >= 1.3:
            return "pipe_rack"
    return "plain"


def shade_rows(rows):
    """The boxes the light bake shades with. Things drawn inside their own box (a container's body, a crane's
    column) would sit in its shadow: their boxes shrink 15 cm a side; thin and open things (rails, pipe racks, the
    derrick) cast no shade."""
    out = []
    for row in rows:
        k = classify(row)
        if k in ("rail", "coaming", "pipe_rack", "drawworks", "derrick_leg", "crown", "jib", "riser", "ramp"):
            continue
        if k in ("container", "pedestal", "drill_column"):
            row = dict(row, size=[max(0.05, v - 0.3) for v in row["size"]])
        out.append(row)
    return out


def riser(m, row):
    """The riser (the drill pipe) down the middle of the derrick and the moon pool: dark steel, a collar at every
    joint (every 9 m)."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    cyl(m.b, tuple(c), 0.62, s[1], "rip_pipe", "rip_iron", sides=10)
    y = y0 + 4.5
    while y < y1 - 1.0:
        cyl(m.b, (c[0], y, c[2]), 0.8, 0.5, "rip_iron", sides=10)
        y += 9.0


def build(name="leviathan_hull"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    assert data.get("map") == "riptide", f"{name}: not a Riptide model"
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = leviathan_decals(random.Random(name))
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    legs = []
    crown = None
    conts = 0
    for row in data["boxes"]:
        k = classify(row)
        if k == "hull":
            if not hull_box(m, row):
                m.box(row["pos"], row["size"], mat("rip_white"))
        elif k == "forecastle_wall":
            forecastle_wall(m, row)
        elif k == "container":
            container(m, row, conts)
            conts += 1
        elif k == "ramp":
            m.box(row["pos"], row["size"], ramp_style, yaw=row["yaw"], pitch=row["pitch"])
        elif k == "drawworks":
            drawworks(m, row)
        elif k == "slab":
            top = "rip_deck"
            under = "rip_steel_in"
            m.box(row["pos"], row["size"], deck_style(m, row, top, under))
        elif k == "shack_wall":
            shack_wall(m, row)
        elif k == "shack_roof":
            shack_roof(m, row)
        elif k == "riser":
            riser(m, row)
        elif k == "derrick_leg":
            legs.append(row)
        elif k == "crown":
            crown = row
        elif k == "pedestal":
            crane_pedestal(m, row)
        elif k == "jib":
            crane_jib(m, row)
        elif k == "drill_column":
            drill_column(m, row)
        elif k == "coaming":
            coaming(m, row)
        elif k == "rail":
            rail(m, row)
        elif k == "pipe_rack":
            pipe_rack(m, row, r=0.2 if row["pos"][1] > DRILL else 0.28)
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"))
    if legs and crown:
        derrick(m, legs, crown)
    deck_strips(m)
    drill_beams(m)
    hull_details(m)
    hull_openings(m)
    deck_lines(m)
    forecastle_details(m)
    shack_details(m)
    drill_signs(m)
    b = m.b
    bake_light.CELL = 2.0           # (a ship is big: 2 m cells keep the bake's triangles in budget)
    bake_light.bake(b, shade_rows(data["boxes"]))
    cells = riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris


def paint_lamp(rng):
    c = Canvas(64, 64, "rw_glow")
    c.noise(0, 0, 64, 64, ["rw_light"], 0.1, rng)
    return c


KIT["rip_lamp"] = paint_lamp
mb.PALETTE["rw_glow"] = "f2edd0"


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    build(args[0] if args else "leviathan_hull")
