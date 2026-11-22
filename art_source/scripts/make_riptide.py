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

        def covered(p):
            q = tuple(p[k] + n[k] * 0.02 for k in range(3))
            return any(b[0] <= q[0] <= b[3] and b[1] <= q[1] <= b[4] and b[2] <= q[2] <= b[5] for b in others)
        if not all(covered(p) for p in pts):
            return False
        # (0.36.29, owner: a see-through door frame by the bow stairs) the five points can all be covered while the
        # face isn't: a tall wall end beside two doors one above the other had its bottom, middle and top inside
        # other boxes and the doorways between them open. Check a grid every 0.4 m across the face too.
        c0, c1, c3 = corners[0], corners[1], corners[3]
        du = math.dist(c0, c1)
        dv = math.dist(c0, c3)
        nu, nv = max(2, min(60, int(du / 0.4) + 1)), max(2, min(60, int(dv / 0.4) + 1))
        for i in range(nu):
            for j in range(nv):
                u, v = 0.05 + 0.9 * i / (nu - 1), 0.05 + 0.9 * j / (nv - 1)
                if not covered(tuple(c0[k] + (c1[k] - c0[k]) * u + (c3[k] - c0[k]) * v for k in range(3))):
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


# (0.36.17, owner: the hull was "too square") the shaped bow and the stern's rounded corners. The gray box has the
# plate as straight yawed pieces (kind "hull_curve") and the decks there as strips (kind "deck_curve"); here the plate
# is drawn as one smooth run along its middle line, and the decks to that line.
def hull_chains(m):
    """{(end, side): [points along the plate's middle line, (x, z), from the straight side to the stem / transom]}."""
    chains = {}
    for row in m.data["boxes"]:
        if row.get("kind") != "hull_curve":
            continue
        c, s, yaw = row["pos"], row["size"], math.radians(row["yaw"])
        d = (math.sin(yaw), math.cos(yaw))
        half = (s[2] - 0.1) / 2
        key = ("bow" if c[2] < 0 else "stern", 1 if c[0] > 0 else -1)
        chains.setdefault(key, []).append(((c[0] - d[0] * half, c[2] - d[1] * half), (c[0] + d[0] * half, c[2] + d[1] * half),
                                           c[1] - s[1] / 2, c[1] + s[1] / 2))
    out = {}
    for key, segs in chains.items():
        pts = [segs[0][0], segs[0][1]] + [sg[1] for sg in segs[1:]]
        out[key] = (pts, segs[0][2], segs[0][3])
    return out


def _seg_normal(a, b, side):
    """The outward normal (x, z) of the plate from a to b on this side of the ship."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dz)
    n = (dz / ln, -dx / ln)
    return n if n[0] * side > 0 or (abs(n[0]) < 1e-6 and n[1] > 0) else (-n[0], -n[1])


def _offset(pts, side, d, stem_z=None):
    """The line `d` out from the plate's middle (inward if negative), mitred at the joints; with stem_z, its last
    point slides along the last piece to that z (where the stem's flat front is)."""
    ns = [_seg_normal(a, b, side) for a, b in zip(pts, pts[1:])]
    out = []
    for i, p in enumerate(pts):
        if i == 0:
            n = ns[0]
        elif i == len(pts) - 1:
            n = ns[-1]
        else:
            a, b = ns[i - 1], ns[i]
            n = (a[0] + b[0], a[1] + b[1])
            ln = math.hypot(*n)
            n = (n[0] / ln, n[1] / ln)
            k = a[0] * n[0] + a[1] * n[1]
            n = (n[0] / k, n[1] / k)
        out.append((p[0] + n[0] * d, p[1] + n[1] * d))
    if stem_z is not None:
        (ax, az), (bx, bz) = out[-2], out[-1]
        t = (stem_z - az) / (bz - az)
        out[-1] = (ax + (bx - ax) * t, stem_z)
    return out, ns


def hull_curves(m):
    """The plate round the shaped bow and the stern's corners: red outside in the same bands as the sides, steel
    inside below the deck and white above, a yellow cap on the rail. Also the decks inside them."""
    b = m.b
    chains = hull_chains(m)
    for (end, side), (pts, lo, hi) in chains.items():
        bow = end == "bow"
        outer, ns = _offset(pts, side, 0.25, -104.25 if bow else None)
        inner, _ = _offset(pts, side, -0.25, -103.75 if bow else None)
        deck_y = FORECASTLE if bow else DECK
        inner_bands = ((-99.0, deck_y, "rip_steel_in"), (deck_y, 99.0, "rip_white"))
        for i, n2 in enumerate(ns):
            n = (n2[0], 0.0, n2[1])
            for line, bands, sg in ((outer, OUTER_BANDS, 1), (inner, inner_bands, -1)):
                (xa, za), (xb, zb) = line[i], line[i + 1]
                for y0, y1, mt in bands:
                    y0, y1 = max(y0, lo), min(y1, hi)
                    if y1 - y0 > 0.01:
                        b.poly([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], tuple(sg * v for v in n), mt,
                               uv_world())
            (oa, ob), (ia, ib) = (outer[i], outer[i + 1]), (inner[i], inner[i + 1])
            b.poly([(ia[0], hi, ia[1]), (oa[0], hi, oa[1]), (ob[0], hi, ob[1]), (ib[0], hi, ib[1])], (0, 1, 0), "rip_yellow",
                   uv_world(1.0))
    # the decks: from one side's middle line to the other's, a piece between each pair of points
    levels = {}
    for row in m.data["boxes"]:
        if row.get("kind") == "deck_curve":
            levels[(round(row["pos"][1] + row["size"][1] / 2, 3), "bow" if row["pos"][2] < 0 else "stern")] = row["size"][1]
    for (top, end), t in levels.items():
        west, east = chains[(end, -1)][0], chains[(end, 1)][0]
        for (wa, wb, ea, eb) in zip(west, west[1:], east, east[1:]):
            q = [(wa[0], wa[1]), (ea[0], ea[1]), (eb[0], eb[1]), (wb[0], wb[1])]
            b.poly([(x, top, z) for x, z in q], (0, 1, 0), "rip_deck", uv_world())
            b.poly([(x, top - t, z) for x, z in q], (0, -1, 0), "rip_steel_in", uv_world())


def on_hull(m, side, z, end="bow"):
    """A spot on the shaped bow's (or stern's) outside face at z: (x, normal (x, z), along (x, z))."""
    pts = hull_chains(m)[(end, side)][0]
    outer, ns = _offset(pts, side, 0.25)
    for i, ((xa, za), (xb, zb)) in enumerate(zip(outer, outer[1:])):
        if min(za, zb) <= z <= max(za, zb):
            t = (z - za) / (zb - za)
            ln = math.hypot(xb - xa, zb - za)
            return xa + (xb - xa) * t, ns[i], ((xb - xa) / ln, (zb - za) / ln)
    raise ValueError(z)


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
    # draft marks: on the shaped bow near the stem (0.36.17), and aft on the straight side before the rounded corner
    for side in (-1, 1):
        x, n, d = on_hull(m, side, -101.6)
        yaw = math.degrees(math.atan2(n[0], n[1]))
        for dm in DRAFTS:
            y = dm - 18.75
            zc = -101.6
            m.box((x + n[0] * 0.02, y + 0.18, zc + n[1] * 0.02), (0.9, 0.36, 0.01),
                  lambda nn, mid, q, dm=dm: ("graffiti", m.d("draft%d" % dm)) if nn[0] * n[0] + nn[2] * n[1] > 0.9 else None,
                  yaw=yaw, cull=False)
        for dm in DRAFTS:
            y = dm - 18.75
            flat(b, (side, 0, 0), side * 18.27, 103.6, 104.5, y, y + 0.36, "graffiti", m.d("draft%d" % dm))
    # anchors: a dark pocket in the bow's flare on each side, the anchor's crown and flukes in it (0.36.17: on the
    # shaped bow, faced with it)
    for side in (-1, 1):
        zc = -97.0
        x, n, d = on_hull(m, side, zc)
        yaw = math.degrees(math.atan2(n[0], n[1]))

        def at(out):
            return (x + n[0] * out, zc + n[1] * out)
        px, pz = at(0.01)
        pocket = [(px - d[0] * 1.6, 1.2, pz - d[1] * 1.6), (px + d[0] * 1.6, 1.2, pz + d[1] * 1.6),
                  (px + d[0] * 1.6, 4.6, pz + d[1] * 1.6), (px - d[0] * 1.6, 4.6, pz - d[1] * 1.6)]
        b.poly(pocket, (n[0], 0, n[1]), "rip_iron", uv_world())
        sx, sz = at(0.12)
        m.box((sx, 3.6, sz), (0.3, 1.6, 0.2), mat("rip_pipe"), yaw=yaw, cull=False)   # the shank
        sx, sz = at(0.15)
        m.box((sx, 2.4, sz), (2.2, 0.5, 0.26), mat("rip_pipe"), yaw=yaw, cull=False)  # the flukes
        for dd in (-0.9, 0.9):
            m.box((sx + d[0] * dd, 2.85, sz + d[1] * dd), (0.4, 0.5, 0.26), mat("rip_pipe"), yaw=yaw, cull=False)
    # a rubbing strake along each side at the deck line: a dark steel band you see the length of the ship
    # (broken round the anchor pockets, the hull doors and the ladders up the side: nothing sticks out across them);
    # round the shaped bow and the stern's corners it follows the plate
    gaps = {-1: [(4.6, 7.0), (37.4, 39.6)], 1: [(-89.1, -82.8), (42.8, 45.2), (48.9, 51.1)]}
    for side in (-1, 1):
        x = side * 18.25
        cuts = [-93.5] + [v for g in gaps[side] for v in g] + [105.0]
        for z0_, z1_ in zip(cuts[0::2], cuts[1::2]):
            m.box((x + side * 0.08, 3.4, (z0_ + z1_) / 2), (0.16, 0.25, z1_ - z0_), mat("rip_iron"), cull=False)
        for end in ("bow", "stern"):
            pts = hull_chains(m)[(end, side)][0]
            outer, ns = _offset(pts, side, 0.33)
            for (xa, za), (xb, zb), n in zip(outer, outer[1:], ns):
                if end == "bow" and min(za, zb) < -95.2 and max(za, zb) > -98.8:      # (the anchor pocket)
                    continue
                ln = math.hypot(xb - xa, zb - za)
                m.box(((xa + xb) / 2, 3.4, (za + zb) / 2), (0.16, 0.25, ln + 0.04), mat("rip_iron"),
                      yaw=math.degrees(math.atan2(xb - xa, zb - za)), cull=False)


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
    if row["pitch"]:     # (0.36.29) a rail down a ramp: the plate and a square handrail along its top, both sloped
        m.box(c, s, rail_style(), yaw=row["yaw"], pitch=row["pitch"])
        p, y = math.radians(row["pitch"]), math.radians(row["yaw"])
        up = (math.sin(y) * math.sin(p), math.cos(p), math.cos(y) * math.sin(p))   # the plate's own up, in the world
        hc = tuple(c[k] + up[k] * (s[1] / 2 + 0.05) for k in range(3))
        m.box(hc, (0.1, 0.1, s[2]), mat("rip_yellow"), yaw=row["yaw"], pitch=row["pitch"], cull=False)
        return
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
    # (0.36.42, model audit: the top layer stopped up to 0.7 m under the rack's solid top) layers spread to fill the
    # height: the bottom one on the lower bar, the top one just under the frames' top bar
    n_up = max(1, round((H - 0.32) / (2 * r + 0.04)))
    lo, hi = y0 + 0.16 + r, y0 + H - 0.16 - r
    for j in range(n_up):
        for i in range(n_across):
            p = list(c)
            p[across] += -W / 2 + 0.15 + (i + 0.5) * (W - 0.3) / n_across + (0.1 if j % 2 else 0.0)
            p[1] = lo + (hi - lo) * (j / (n_up - 1) if n_up > 1 else 0.0)
            cyl(m.b, tuple(p), r, L - 0.1, "rip_pipe", "rip_iron", axis="x" if along == 0 else "z", sides=8)


# ------------------------------------------------------------------------------------------------ cranes
def crane_pedestal(m, row):
    """A deck crane's pedestal: a round yellow column on a foot, the slewing house on top (the cab, glass to the
    boom side), all inside the gray box."""
    c, s = row["pos"], row["size"]
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    b = m.b
    m.box((c[0], y0 + 0.2, c[2]), (2.4, 0.4, 2.4), mat("rip_yellow"))                     # the foot plate
    # (0.36.42, model audit: the round 0.85 m column left the box's corners solid and empty) a chamfered square
    # column filling the gray box, 2.4 m across, its corners cut 0.35 m
    hw, cut = 1.19, 0.35
    ring = [(hw, -hw + cut), (hw, hw - cut), (hw - cut, hw), (-hw + cut, hw), (-hw, hw - cut), (-hw, -hw + cut),
            (-hw + cut, -hw), (hw - cut, -hw)]
    ya, yb = y0 + 0.4, y0 + 6.2
    for k in range(8):
        (u0, v0), (u1, v1) = ring[k], ring[(k + 1) % 8]
        nx, nz = v1 - v0, -(u1 - u0)
        ln = math.hypot(nx, nz)
        b.poly([(c[0] + u0, ya, c[2] + v0), (c[0] + u1, ya, c[2] + v1), (c[0] + u1, yb, c[2] + v1), (c[0] + u0, yb, c[2] + v0)],
               (nx / ln, 0, nz / ln), "rip_yellow", uv_world())
    cyl(b, (c[0], y0 + 6.3, c[2]), 1.25, 0.2, "rip_iron", sides=12)                         # the slewing ring
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
    # (0.36.42, model audit: the box is 4 m wide, the drum 1.6) guard plates down both sides and a mesh cover over
    # the drum, so the whole solid box is drawn
    for sg in (-1, 1):
        m.box((c[0] + sg * (s[0] / 2 - 0.05), y0 + 1.15, c[2]), (0.1, s[1] - 0.3, s[2] - 2.0), mat("rip_yellow"), cull=False)
    m.box((c[0], y0 + s[1] - 0.04, c[2]), (s[0], 0.08, s[2] - 2.0), mat("rip_iron"), cull=False)


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
        if row.get("kind") == "hull_curve":     # (slanted: a box's bounds would shade the deck beside it)
            continue
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
    # (0.36.42, model audit: r 0.62 left its 1.6 m box's sides solid and empty; now the pipe fills the box)
    cyl(m.b, tuple(c), s[0] / 2 - 0.02, s[1], "rip_pipe", "rip_iron", sides=10)
    y = y0 + 4.5
    while y < y1 - 1.0:
        cyl(m.b, (c[0], y, c[2]), s[0] / 2 + 0.15, 0.5, "rip_iron", sides=10)
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
        if row.get("kind") in ("hull_curve", "deck_curve", "sheaves"):     # (drawn by hull_curves, derrick)
            continue
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
    hull_curves(m)
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


# ================================================================================================ the bridge tower
# Art step 2 (0.36.18): `bridge_tower`, origin (48, 0, 90). Outside: white deckhouse plate like the drill shack, a
# white fill at the corners and the floor lines (the gray box leaves notches there), dark steel frames round every
# window and door, signs over the doors, LEVIATHAN on the bridge front, lifebuoys, the helideck's H. Inside, deck by
# deck: steel on the main deck (armory, stores, workshop), panelled walls, lino and tiled ceilings with lamps on the
# decks above (mess and galley, cabins; sick bay, captain, officers; the bridge, chart room, radio room). Furniture
# stands inside its own gray box (gen_riptide.py TOWER_PROPS).
mb.PALETTE.update({
    "tp_panel": "c6bfaa", "tp_panel_dark": "b6af9b", "tp_panel_light": "cec7b3",
    "tp_green": "a3b19f", "tp_green_dark": "95a391", "tp_green_light": "adbba9",
    "tp_lino": "7a868d", "tp_lino_dark": "6f7b82", "tp_lino_light": "838f96",
    "tp_tile": "9c5e49", "tp_tile_dark": "8b5341", "tp_tile_grout": "6f4a3c",
    "tp_ceil": "c9c8c0", "tp_ceil_dark": "b5b4ac",
    "tp_heli": "3f4a40", "tp_heli_dark": "364038", "tp_heli_light": "485449",
    "tp_wood": "8a6440", "tp_wood_dark": "765435", "tp_wood_light": "967049",
    "tp_navy": "34405a", "tp_navy_dark": "2b354b", "tp_navy_light": "3e4b68",
    "tp_sheet": "c6c5bc", "tp_sheet_dark": "b2b1a8",
    "tp_card": "9b7a50", "tp_card_dark": "86683f",
    "tp_red": "8e3326", "tp_red_dark": "772a1f",
    "tp_bright": "a9adad", "tp_bright_dark": "959999", "tp_bright_light": "b9bdbd",
    "tp_orange": "d0622a", "tp_screen": "245446", "tp_screen_on": "7fe39a", "tp_bezel": "1b1f24", "tp_glass": "3d7a8c", "tp_amber": "c99a3a",
    "tp_paper": "d8d2bd", "tp_sea": "6f93a6", "tp_land": "b9ae86",
})


def _plain(base, light, dark, chance=0.1):
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [light, dark], chance, rng)
        return c
    return paint


def paint_panel(base):
    def paint(rng):
        """Ship's interior panels: 1 m sheets with a dark seam, scuffed low down."""
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [base + "_light", base + "_dark"], 0.06, rng)
        for x in (0, 16, 32, 48):
            for y in range(64):
                c.put(x, y, base + "_dark")
        c.blotch([base + "_dark"], 4, rng, size=(2, 4))
        return c
    return paint


def paint_lino(rng):
    """Lino in 50 cm tiles, a lighter fleck, worn paths."""
    c = Canvas(64, 64, "tp_lino")
    c.noise(0, 0, 64, 64, ["tp_lino_light", "tp_lino_dark"], 0.12, rng)
    for k in range(0, 64, 8):
        for t in range(64):
            c.put(k, t, "tp_lino_dark")
            c.put(t, k, "tp_lino_dark")
    c.blotch(["tp_lino_dark"], 5, rng, size=(3, 6))
    return c


def paint_tile(rng):
    """Red quarry tiles (the galley and the mess), 25 cm, dark grout."""
    c = Canvas(64, 64, "tp_tile")
    c.noise(0, 0, 64, 64, ["tp_tile_dark"], 0.1, rng)
    for k in range(0, 64, 4):
        for t in range(64):
            c.put(k, t, "tp_tile_grout")
            c.put(t, k, "tp_tile_grout")
    c.blotch(["tp_tile_dark", "rx_iron"], 4, rng, size=(2, 3))
    return c


def paint_ceiling(rng):
    """Ceiling tiles, 50 cm, a few stained."""
    c = Canvas(64, 64, "tp_ceil")
    for k in range(0, 64, 8):
        for t in range(64):
            c.put(k, t, "tp_ceil_dark")
            c.put(t, k, "tp_ceil_dark")
    c.noise(0, 0, 64, 64, ["tp_ceil_dark"], 0.04, rng)
    c.blotch(["rw_grime"], 3, rng, size=(2, 4))
    return c


def paint_heli(rng):
    """The helideck: dark green non-slip, 2 m plates, tyre marks."""
    c = Canvas(64, 64, "tp_heli")
    c.noise(0, 0, 64, 64, ["tp_heli_light", "tp_heli_dark"], 0.15, rng)
    _seams(c, "tp_heli_dark", rows=(0, 32), cols=((0, 0, 64), (32, 0, 64)))
    c.blotch(["rx_iron", "tp_heli_dark"], 5, rng, size=(2, 5))
    return c


def paint_wood(rng):
    c = Canvas(64, 64, "tp_wood")
    for y in range(64):
        if y % 4 == 0:
            for x in range(64):
                if rng.random() < 0.7:
                    c.put(x, y, "tp_wood_dark")
    c.noise(0, 0, 64, 64, ["tp_wood_light", "tp_wood_dark"], 0.06, rng)
    return c


KIT.update({
    "rip_panel": paint_panel("tp_panel"), "rip_panel_g": paint_panel("tp_green"), "rip_lino": paint_lino,
    "rip_tile": paint_tile, "rip_ceiling": paint_ceiling, "rip_heli": paint_heli, "rip_wood": paint_wood,
    "rip_navy": _plain("tp_navy", "tp_navy_light", "tp_navy_dark"), "rip_sheet": _plain("tp_sheet", "tp_sheet_dark", "tp_sheet_dark", 0.05),
    "rip_card": _plain("tp_card", "tp_card_dark", "tp_card_dark"), "rip_red": _plain("tp_red", "tp_red_dark", "tp_red_dark", 0.08),
    "rip_bright": _plain("tp_bright", "tp_bright_light", "tp_bright_dark", 0.06),
    "rip_orange": _plain("tp_orange", "rw_white", "tp_orange", 0.02),
})

T_FLOORS = (4.0, 7.5, 11.0, 14.5)
T_ROOF = 18.0
TX, TZ = 14.0, 16.0                     # the tower's walls: x -14..14, z -16..16 (their middles)
T_STAIR = (6.0, 14.0, -14.0, 0.0)
# (0.36.19 layout) The rooms of each floor: north-west, north-east, the hall down from the stairs (main deck and
# B deck), and south of the corridor: south-west, the middle, south-east. Signs over the doors read these.
ROOM_NAMES = [
    {"nw": "STORES", "ne": "ARMORY", "hall": "STAIRS", "sw": "WORKSHOP", "sm": "WORKSHOP", "se": "BOSUN"},
    {"nw": "MESS", "ne": "GALLEY", "sw": "BUNK ROOM", "sm": "LOUNGE", "se": "WASHROOM"},
    {"nw": "SICK BAY", "ne": "OFFICE", "hall": "STAIRS", "sw": "CHIEF", "sm": "CAPTAIN", "se": "MEETING ROOM"},
    {"nw": "BRIDGE", "ne": "BRIDGE", "sw": "CHART ROOM", "sm": "RADIO ROOM", "se": "SWITCHBOARD"},
]
T_HALL_FLOORS = (0, 2)                  # (the floors whose stairs land at their north end: a hall x 3..6 down to the corridor)
DECK_NAMES = {4.0: "MAIN DECK", 7.5: "A DECK", 11.0: "B DECK", 14.5: "BRIDGE", 18.0: "HELIDECK"}


def t_floor(y):
    """The floor a height belongs to: 0..3, 4 on the roof, -1 under the main deck (the stairs down)."""
    if y < T_FLOORS[0] - 0.01:
        return -1
    if y >= T_ROOF - 0.01:
        return 4
    return max(i for i, f in enumerate(T_FLOORS) if f <= y + 0.01)


def t_room(x, z, f=None):
    """The room at (x, z) on floor f (0.36.19 layout: the corridor z 0..3 right across, the rooms north and south)."""
    if x < -TX or x > TX or z < -TZ or z > TZ:
        return "out"
    if T_STAIR[0] < x < T_STAIR[1] and T_STAIR[2] < z < T_STAIR[3]:
        return "stair"
    if z < T_STAIR[3]:
        if x > T_STAIR[0]:
            return "stair"                  # (the closed trunk north of the stairs: steel like them)
        if x < -4.0:
            return "nw"
        if x > 3.0 and (f in T_HALL_FLOORS or f is None):
            return "hall"
        return "ne"
    if z < 3.0:
        return "corr"
    return "sw" if x < -5.0 else ("sm" if x < 6.0 else "se")


def t_wall_mat(f, room):
    if room == "out":
        return "rip_white" if f >= 0 else "rip_steel_in"
    if room == "stair" or f <= 0 or f == 4:
        return "rip_steel_in"
    if f == 2 and room == "nw":
        return "rip_panel_g"
    return "rip_panel"


def t_floor_mat(f, room):
    if f == 4:
        return "rip_heli"
    if room == "stair" or f <= 0:
        return "rip_deck"
    if f == 1 and room in ("nw", "ne", "se"):      # (the mess, the galley, the washroom)
        return "rip_tile"
    return "rip_lino"


def _sign_plate(text, scale=2, bg="rw_white", fg="rx_black"):
    return _sign(text, bg, fg, scale)


def tower_decals(rng):
    a = Atlas(512)
    for name in sorted({n for f in ROOM_NAMES for n in f.values()} | {"STAIRS", "MUSTER STATION", "LIFEJACKETS"}):
        w, h, p = _sign_plate(name)
        a.add("sign_" + name, w, h, p)
    for y, name in DECK_NAMES.items():
        w, h, p = _stencil(name, 3, "rx_black", random.Random(name), chip=0.04)
        a.add("deck_" + name, w, h, p)
    w, h, p = _sign_plate(NAME, 4)
    a.add("nameboard", w, h, p)
    w, h, p = _sign("NO SMOKING", "rw_white", "rh_red")
    a.add("no_smoking", w, h, p)

    def helipad(c):            # 128 px over 16 m: the yellow touchdown ring, a white H
        c.rect(0, 0, 128, 128, "clear")
        for y in range(128):
            for x in range(128):
                r = math.hypot(x - 63.5, y - 63.5)
                if 50 <= r <= 56:
                    c.put(x, y, "ry_yel")
        c.rect(46, 40, 54, 88, "rw_light")
        c.rect(74, 40, 82, 88, "rw_light")
        c.rect(54, 60, 74, 68, "rw_light")
        r2 = random.Random("pad")
        for _ in range(300):
            x, y = r2.randrange(128), r2.randrange(128)
            if c.px[y][x] != "clear":
                c.put(x, y, "clear")
    a.add("helipad", 128, 128, helipad)

    def fridge(c):             # 0.8 x 1.9 m
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.rect(0, 40, c.w, 41, "tp_bright_dark")
        c.frame(0, 0, c.w, c.h, "tp_bright_dark")
        c.rect(c.w - 5, 46, c.w - 3, 56, "rx_iron")
        c.rect(c.w - 5, 28, c.w - 3, 36, "rx_iron")
    a.add("fridge", 24, 60, fridge)

    def stove(c):              # 0.9 x 0.9 m, the front
        c.rect(0, 0, c.w, c.h, "tp_bright")
        c.rect(3, 3, c.w - 3, 18, "rx_iron")
        c.rect(5, 5, c.w - 5, 16, "rg_glass")
        c.rect(4, 19, c.w - 4, 20, "rx_iron_light")
        for k in range(4):
            c.rect(5 + k * 6, 23, 8 + k * 6, 26, "rx_black")
    a.add("stove", 30, 28, stove)

    def hob(c):                # the top: four rings
        c.rect(0, 0, c.w, c.h, "rx_iron")
        for cx, cy in ((7, 7), (21, 7), (7, 19), (21, 19)):
            for y in range(c.h):
                for x in range(c.w):
                    if 3.5 <= math.hypot(x - cx, y - cy) <= 5:
                        c.put(x, y, "rx_black")
    a.add("hob", 28, 26, hob)

    def cupboards(c):          # 1 m x 0.9 m of cupboard doors
        c.rect(0, 0, c.w, c.h, "rw_light")
        for x in (0, 15):
            c.frame(x + 1, 1, x + 15, c.h - 3, "rw_white_dark")
            c.rect(x + 12, 16, x + 13, 22, "rx_iron")
        c.rect(0, 0, c.w, 2, "rx_iron")
    a.add("cupboards", 32, 29, cupboards)

    def drawers(c):            # a filing cabinet / tool chest front, 4 drawers
        c.rect(0, 0, c.w, c.h, "clear")
        for k in range(4):
            y = 2 + k * c.h // 4
            c.frame(1, y, c.w - 1, y + c.h // 4 - 2, "rx_iron")
            c.rect(c.w // 2 - 3, y + c.h // 8 - 1, c.w // 2 + 3, y + c.h // 8, "rx_iron_light")
    a.add("drawers", 20, 40, drawers)

    def screens(c):            # a console's sloping top: radar, chart, engine panel, buttons
        c.rect(0, 0, c.w, c.h, "rx_iron_light")
        for k, x in enumerate((4, 36, 68)):
            c.rect(x, 4, x + 26, 20, "tp_screen")
            if k == 0:
                for y in range(4, 20):
                    for xx in range(x, x + 26):
                        r = math.hypot(xx - x - 13, y - 12)
                        if 6.5 <= r <= 7.2 or r < 1:
                            c.put(xx, y, "tp_screen_on")
                c.rect(x + 13, 12, x + 19, 13, "tp_screen_on")
            elif k == 1:
                c.rect(x + 2, 6, x + 14, 18, "tp_sea")
                c.rect(x + 14, 6, x + 24, 18, "tp_land")
                c.rect(x + 10, 10, x + 13, 12, "tp_screen_on")
            else:
                for j in range(5):
                    c.rect(x + 3 + j * 5, 6, x + 6 + j * 5, 8 + j * 2, "tp_amber")
        for x in range(4, c.w - 4, 4):
            c.put(x, 1, "tp_screen_on" if x % 12 else "rh_red")
    a.add("screens", 100, 24, screens)

    def monitor(c):            # (0.36.22) an upright monitor's face: a black bezel, a lit screen with readouts
        c.rect(0, 0, c.w, c.h, "tp_bezel")
        c.rect(2, 2, c.w - 2, c.h - 3, "tp_screen")
        for k, y in enumerate(range(4, c.h - 5, 3)):
            c.rect(4, y, 4 + (7 + 5 * k) % (c.w - 10), y + 1, "tp_screen_on")
        c.rect(c.w - 9, 4, c.w - 4, 9, "tp_amber")
        c.put(c.w // 2, c.h - 2, "tp_screen_on")
    a.add("monitor", 32, 20, monitor)

    def keys(c):               # a keyboard and a row of switches along a console's front lip
        c.rect(0, 0, c.w, c.h, "tp_bezel")
        for x in range(1, c.w - 1, 2):
            c.put(x, 1, "rx_iron_light")
            c.put(x, 3, "rx_iron_light" if x % 6 else "rh_red")
    a.add("keys", 48, 5, keys)

    def chart(c):              # a paper chart: the coast, soundings, a course line
        c.rect(0, 0, c.w, c.h, "tp_paper")
        r2 = random.Random("chart")
        edge = 20
        for y in range(c.h):
            edge = max(8, min(30, edge + r2.choice((-1, 0, 1))))
            c.rect(0, y, edge, y + 1, "tp_land")
        for _ in range(40):
            c.put(r2.randrange(34, c.w - 2), r2.randrange(2, c.h - 2), "rx_iron_light")
        for k in range(30):
            c.put(36 + k, 6 + k // 2, "rh_red")
        c.frame(0, 0, c.w, c.h, "rx_iron_light")
    a.add("chart", 72, 36, chart)

    def pegboard(c):           # tools hung on a board over a bench
        c.rect(0, 0, c.w, c.h, "tp_card")
        for y in range(1, c.h, 3):
            for x in range(1, c.w, 3):
                c.put(x, y, "tp_card_dark")
        for k, x in enumerate(range(4, c.w - 6, 8)):
            if k % 3 == 0:
                c.rect(x, 6, x + 2, 18, "rx_iron")
                c.rect(x - 1, 15, x + 3, 19, "tp_red")
            elif k % 3 == 1:
                c.rect(x, 4, x + 1, 16, "ri_dark")
                c.rect(x - 2, 14, x + 3, 16, "ri_dark")
            else:
                c.rect(x, 8, x + 4, 10, "rx_iron_light")
                c.rect(x + 1, 10, x + 2, 18, "ry_yel")
    a.add("pegboard", 60, 22, pegboard)

    def med(c):                # a glass-fronted cabinet: shelves of boxes and bottles
        c.rect(0, 0, c.w, c.h, "rw_light")
        r2 = random.Random("med")
        for k in range(4):
            y = 4 + k * 14
            c.rect(2, y, c.w - 2, y + 1, "rw_white_dark")
            x = 3
            while x < c.w - 5:
                w = r2.randrange(2, 5)
                c.rect(x, y + 1, x + w, y + 1 + r2.randrange(4, 9), r2.choice(["rw_white", "tp_sea", "tp_amber", "rw_grime"]))
                x += w + 1
        c.frame(0, 0, c.w, c.h, "rw_white_dark")
        c.rect(c.w // 2, 0, c.w // 2 + 1, c.h, "rw_white_dark")
    a.add("med", 40, 60, med)

    def radio(c):              # radio sets on a rack
        c.rect(0, 0, c.w, c.h, "rx_iron")
        for k in range(3):
            y = 2 + k * 9
            c.rect(2, y, c.w - 2, y + 7, "rx_iron_light")
            c.rect(4, y + 2, 16, y + 5, "tp_screen")
            c.rect(5, y + 3, 12, y + 4, "tp_amber")
            for x in range(20, c.w - 4, 5):
                c.rect(x, y + 2, x + 2, y + 4, "rx_black")
    a.add("radio", 60, 29, radio)

    def clock(c):
        c.rect(0, 0, 16, 16, "clear")
        for y in range(16):
            for x in range(16):
                r = math.hypot(x - 7.5, y - 7.5)
                if r <= 7.5:
                    c.put(x, y, "rx_black" if r > 6.4 else "rw_light")
        c.rect(7, 8, 8, 13, "rx_black")
        c.rect(8, 7, 12, 8, "rx_black")
    a.add("clock", 16, 16, clock)
    return a


def t_lamp(m, x, y, z, w=1.2, d=0.3):
    """A ceiling lamp: a flat panel 1 cm under the ceiling at y, lights itself."""
    b = m.b
    b.group = bake_light.GLOW
    b.poly([(x - w / 2, y - 0.01, z - d / 2), (x + w / 2, y - 0.01, z - d / 2), (x + w / 2, y - 0.01, z + d / 2),
            (x - w / 2, y - 0.01, z + d / 2)], (0, -1, 0), "rip_lamp", uv_world(1.0))
    b.group = None


def t_item(m):
    m.b.group = ("item", len(m.b.faces))


def t_part(m, x0, y0, z0, x1, y1, z1, style):
    m.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), style if callable(style) else mat(style))


def _against(row):
    """Which way a prop faces (into the room): the axis and sign of its front, from the nearer wall behind it."""
    c, s = row["pos"], row["size"]
    if s[0] < s[2]:                       # long along z: against a wall at x
        return ("x", -1 if c[0] > 0 else 1)
    return ("z", -1 if c[2] > 0 else 1)


def t_prop(m, row):
    kind = row["kind"]
    c, s = row["pos"], row["size"]
    x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
    y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
    z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
    axis, sg = _against(row)
    if kind == "console":                 # under the front windows: the bridge's consoles face aft
        axis, sg = "z", 1
    b = m.b
    t_item(m)

    def front(name, a0=None, a1=None, lo=None, hi=None, mat_name="decals"):
        """A decal on the prop's front face."""
        if axis == "x":
            at = x1 + 0.006 if sg > 0 else x0 - 0.006
            flat(b, (sg, 0, 0), at, z0 if a0 is None else a0, z1 if a1 is None else a1, y0 if lo is None else lo,
                 y1 if hi is None else hi, mat_name, m.d(name))
        else:
            at = z1 + 0.006 if sg > 0 else z0 - 0.006
            flat(b, (0, 0, sg), at, x0 if a0 is None else a0, x1 if a1 is None else a1, y0 if lo is None else lo,
                 y1 if hi is None else hi, mat_name, m.d(name))

    def legs(top, inset=0.05, w=0.06, mat_name="rip_iron"):
        for lx in (x0 + inset, x1 - inset - w):
            for lz in (z0 + inset, z1 - inset - w):
                t_part(m, lx, y0, lz, lx + w, top, lz + w, mat_name)

    if kind in ("bench", "mess_table", "desk", "chart_table"):
        top_m = "rip_wood" if kind != "bench" else "rip_bright"
        t_part(m, x0, y1 - 0.05, z0, x1, y1, z1, top_m)
        if kind == "bench":
            legs(y1 - 0.05)
            t_part(m, x0 + 0.05, y0 + 0.15, z0 + 0.05, x1 - 0.05, y0 + 0.19, z1 - 0.05, "rip_iron")    # the shelf
            t_part(m, x0 + 0.04, y0 + 0.19, z0 + 0.04, x1 - 0.04, y0 + 0.45, z1 - 0.04, "rip_card")   # boxes on it
            # a vice at one end
            vx, vz = (x0 + 0.25, z0 + 0.5) if axis == "x" else (x0 + 0.5, z0 + 0.25)
            t_part(m, vx - 0.08, y1, vz - 0.12, vx + 0.08, y1 + 0.02, vz + 0.12, "rip_iron")
        elif kind == "desk" or kind == "chart_table":
            legs(y1 - 0.05)
            # a drawer unit at one end
            if s[0] >= s[2]:
                t_part(m, x1 - 0.5, y0, z0 + 0.03, x1 - 0.04, y1 - 0.05, z1 - 0.03, "rip_steel_in")
            else:
                t_part(m, x0 + 0.03, y0, z1 - 0.5, x1 - 0.03, y1 - 0.05, z1 - 0.04, "rip_steel_in")
            if kind == "chart_table":
                b.poly([(x0 + 0.1, y1 + 0.004, z0 + 0.1), (x1 - 0.1, y1 + 0.004, z0 + 0.1), (x1 - 0.1, y1 + 0.004, z1 - 0.1),
                        (x0 + 0.1, y1 + 0.004, z1 - 0.1)], (0, 1, 0), "decals", m.d("chart"))
            else:                            # papers and a closed laptop, flat on the top
                cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
                t_part(m, cx - 0.17, y1, cz - 0.12, cx + 0.17, y1 + 0.025, cz + 0.12, "rip_iron")
                b.poly([(cx + 0.3, y1 + 0.003, cz - 0.15), (cx + 0.52, y1 + 0.003, cz - 0.15), (cx + 0.52, y1 + 0.003, cz + 0.15),
                        (cx + 0.3, y1 + 0.003, cz + 0.15)], (0, 1, 0), "rip_sheet", uv_world(1.0))
        else:                                # the mess tables: bolted down on a post near each end
            L = max(s[0], s[2])
            for k in range(2 if L < 5 else 3):
                a = 0.5 + k * (L - 1.0) / (1 if L < 5 else 2)
                if s[0] >= s[2]:
                    t_part(m, x0 + a - 0.06, y0, (z0 + z1) / 2 - 0.06, x0 + a + 0.06, y1 - 0.05, (z0 + z1) / 2 + 0.06, "rip_iron")
                    t_part(m, x0 + a - 0.25, y0, (z0 + z1) / 2 - 0.25, x0 + a + 0.25, y0 + 0.03, (z0 + z1) / 2 + 0.25, "rip_iron")
                else:
                    t_part(m, (x0 + x1) / 2 - 0.06, y0, z0 + a - 0.06, (x0 + x1) / 2 + 0.06, y1 - 0.05, z0 + a + 0.06, "rip_iron")
                    t_part(m, (x0 + x1) / 2 - 0.25, y0, z0 + a - 0.25, (x0 + x1) / 2 + 0.25, y0 + 0.03, z0 + a + 0.25, "rip_iron")
    elif kind == "shelves" or kind == "gun_rack":
        post = 0.05
        for px in (x0, x1 - post):
            for pz in (z0, z1 - post):
                t_part(m, px, y0, pz, px + post, y1, pz + post, "rip_iron" if kind == "gun_rack" else "rip_yellow")
        if kind == "shelves":
            r2 = random.Random("%.1f%.1f%.1f" % (c[0], c[1], c[2]))
            levels = [y0 + 0.1, y0 + 0.6, y0 + 1.1, y0 + 1.6, y1 - 0.04]
            for ly in levels:
                t_part(m, x0, ly, z0, x1, ly + 0.04, z1, "rip_steel_in")
            L = s[2] if axis == "x" else s[0]
            for ly in levels[:-1]:
                a = 0.08
                while a < L - 0.35:
                    w = r2.uniform(0.25, 0.55)
                    if a + w > L - 0.08:
                        break
                    hgt = r2.uniform(0.2, 0.42)
                    dep = (s[0] if axis == "x" else s[2]) - 0.12
                    if r2.random() < 0.8:
                        if axis == "x":
                            t_part(m, x0 + 0.06, ly + 0.04, z0 + a, x0 + 0.06 + dep, ly + 0.04 + hgt, z0 + a + w,
                                   r2.choice(["rip_card", "rip_card", "rip_cont_b", "rip_iron"]))
                        else:
                            t_part(m, x0 + a, ly + 0.04, z0 + 0.06, x0 + a + w, ly + 0.04 + hgt, z0 + 0.06 + dep,
                                   r2.choice(["rip_card", "rip_card", "rip_cont_b", "rip_iron"]))
                    a += w + r2.uniform(0.04, 0.2)
        else:                                # the gun rack: a back board, a foot rail, rifles standing in a row
            bx = x0 if sg > 0 else x1 - 0.04
            t_part(m, bx, y0 + 0.1, z0 + 0.05, bx + 0.04, y1 - 0.1, z1 - 0.05, "rip_wood")
            t_part(m, x0, y0, z0, x1, y0 + 0.12, z1, "rip_wood")
            t_part(m, x0 + 0.05, y0 + 1.2, z0, x1 - 0.05, y0 + 1.26, z1, "rip_iron")
            z = z0 + 0.3
            while z < z1 - 0.25:
                t_part(m, (x0 + x1) / 2 - 0.03, y0 + 0.12, z - 0.05, (x0 + x1) / 2 + 0.03, y0 + 1.15, z + 0.05, "rip_iron")
                t_part(m, (x0 + x1) / 2 - 0.035, y0 + 0.3, z - 0.07, (x0 + x1) / 2 + 0.035, y0 + 0.55, z + 0.07, "rip_wood")
                z += 0.38
    elif kind == "drums":
        # (0.36.42, model audit: one row of drums left long or square boxes half empty) a grid of drums spread over the
        # whole box, each about 0.6 m across
        nx, nz = max(1, round(s[0] / 0.7)), max(1, round(s[2] / 0.7))
        r = min(0.32, s[0] / nx / 2 - 0.02, s[2] / nz / 2 - 0.02)
        for i in range(nx):
            for j in range(nz):
                cx, cz = x0 + (i + 0.5) * s[0] / nx, z0 + (j + 0.5) * s[2] / nz
                cyl(b, (cx, y0 + 0.45, cz), r, 0.9, "rip_cont_b" if (i + j) % 2 == 0 else "rip_red", "rip_iron", sides=10)
                cyl(b, (cx, y0 + 0.3, cz), r + 0.012, 0.04, "rip_iron", sides=10)
                cyl(b, (cx, y0 + 0.62, cz), r + 0.012, 0.04, "rip_iron", sides=10)
    elif kind == "tool_cab" or kind == "files":
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_red" if kind == "tool_cab" else "rip_steel_in")
        front("drawers", mat_name="graffiti")
    elif kind == "machine":                   # a pump on its bed: base, motor, the pump, a yellow guard
        t_part(m, x0, y0, z0, x1, y0 + 0.25, z1, "rip_iron")
        cyl(b, ((x0 + x1) / 2, y0 + 0.75, z0 + 0.6), 0.42, 1.0, "rip_cont_c", "rip_iron", axis="z", sides=10)
        cyl(b, ((x0 + x1) / 2, y0 + 0.7, z1 - 0.55), 0.38, 0.6, "rip_pipe", "rip_iron", axis="y", sides=10)
        t_part(m, x0 + 0.2, y0 + 0.25, z0 + 1.2, x1 - 0.2, y0 + 0.6, z1 - 0.95, "rip_yellow")
    elif kind == "fridge":
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_bright")
        front("fridge", mat_name="decals")
    elif kind == "counter" or kind == "stove":
        t_part(m, x0, y0 + 0.08, z0, x1, y1 - 0.04, z1, "rip_white")
        t_part(m, x0, y1 - 0.04, z0, x1, y1, z1, "rip_bright")
        t_part(m, x0 + (0.05 if axis == "z" else 0), y0, z0 + (0.05 if axis == "x" else 0),
               x1 - (0.05 if axis == "z" else 0), y0 + 0.08, z1 - (0.05 if axis == "x" else 0), "rip_iron")
        if kind == "stove":
            front("stove")
            b.poly([(x0 + 0.05, y1 + 0.003, z0 + 0.05), (x1 - 0.05, y1 + 0.003, z0 + 0.05), (x1 - 0.05, y1 + 0.003, z1 - 0.05),
                    (x0 + 0.05, y1 + 0.003, z1 - 0.05)], (0, 1, 0), "decals", m.d("hob"))
        else:
            L = s[2] if axis == "x" else s[0]
            a = 0.0
            while a + 1.0 <= L + 0.01:
                lo_a = (z0 if axis == "x" else x0) + a
                front("cupboards", lo_a, lo_a + 1.0, y0 + 0.08, y1 - 0.06)
                a += 1.0
            # a sink in the top: a dark steel basin, flush
            sa = (z0 + z1) / 2 if axis == "x" else (x0 + x1) / 2
            if axis == "x":
                b.poly([(x0 + 0.12, y1 + 0.003, sa - 0.3), (x1 - 0.12, y1 + 0.003, sa - 0.3), (x1 - 0.12, y1 + 0.003, sa + 0.3),
                        (x0 + 0.12, y1 + 0.003, sa + 0.3)], (0, 1, 0), "rip_iron", uv_world(1.0))
            else:
                b.poly([(sa - 0.3, y1 + 0.003, z0 + 0.12), (sa + 0.3, y1 + 0.003, z0 + 0.12), (sa + 0.3, y1 + 0.003, z1 - 0.12),
                        (sa - 0.3, y1 + 0.003, z1 - 0.12)], (0, 1, 0), "rip_iron", uv_world(1.0))
    elif kind in ("bunk", "bed", "sick_bed"):
        post = 0.06
        for px in (x0, x1 - post):
            for pz in (z0, z1 - post):
                t_part(m, px, y0, pz, px + post, y1, pz + post, "rip_white" if kind == "sick_bed" else "rip_iron")
        tiers = [y0 + 0.3] if kind != "bunk" else [y0 + 0.3, y0 + 1.2]
        for ty in tiers:
            t_part(m, x0, ty, z0, x1, ty + 0.06, z1, "rip_iron")
            cover = "rip_sheet" if kind == "sick_bed" else "rip_navy"
            t_part(m, x0 + 0.06, ty + 0.06, z0 + 0.06, x1 - 0.06, ty + 0.22, z1 - 0.06, cover)
            # the pillow at the end away from the door side (the -x or -z end)
            if s[0] >= s[2]:
                t_part(m, x0 + 0.1, ty + 0.22, z0 + 0.15, x0 + 0.5, ty + 0.3, z1 - 0.15, "rip_sheet")
            else:
                t_part(m, x0 + 0.15, ty + 0.22, z0 + 0.1, x1 - 0.15, ty + 0.3, z0 + 0.5, "rip_sheet")
        if kind == "bunk":                    # the top bunk's guard rail
            if axis == "x":
                fx = x1 - 0.04 if sg > 0 else x0
                t_part(m, fx, y0 + 1.5, z0 + 0.06, fx + 0.04, y0 + 1.56, z1 - 0.6, "rip_iron")
            else:
                fz = z1 - 0.04 if sg > 0 else z0
                t_part(m, x0 + 0.06, y0 + 1.5, fz, x1 - 0.6, y0 + 1.56, fz + 0.04, "rip_iron")
    elif kind == "med_cab":
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_white")
        front("med", lo=y0 + 0.1, hi=y1 - 0.05)
    elif kind == "console":                   # (0.36.22, owner: "make them look better") a grey cabinet, a lit
        dz = z1 - z0                          # sloping screen panel, a keyboard lip; out in the room, monitors on top
        t_part(m, x0 + 0.02, y0, z0, x1 - 0.02, y0 + 0.1, z1 - 0.06, "rip_iron")                  # kick plate
        t_part(m, x0, y0 + 0.1, z0, x1, y1 - 0.25, z1, "rip_bright")                             # the cabinet
        t_part(m, x0, y1 - 0.25, z0, x1, y1, z0 + 0.35, "rip_bright")                            # the back hood
        for xa in [x0 + 0.05 + k * 1.1 for k in range(int((x1 - x0 - 0.1) // 1.1) + 1)]:       # door seams
            flat(b, (0, 0, 1), z1 + 0.004, xa, xa + 0.02, y0 + 0.14, y1 - 0.3, "rip_iron", uv_world(1.0))
        flat(b, (0, 0, 1), z1 + 0.004, x0, x1, y1 - 0.29, y1 - 0.25, "rip_iron", uv_world(1.0))   # the lip
        slope = [(x0, y1 - 0.25, z1), (x1, y1 - 0.25, z1), (x1, y1, z0 + 0.35), (x0, y1, z0 + 0.35)]
        ln = math.hypot(0.25, dz - 0.35)
        sn = (0, (dz - 0.35) / ln, 0.25 / ln)
        b.poly(slope, sn, "rip_iron", uv_world(1.0))
        # the panels on the slope, a little proud of it and lit (one per 1.6 m), and the keyboard strip in front
        n_p = max(1, int((x1 - x0) // 1.6))
        w_p = (x1 - x0) / n_p
        lift = (sn[0] * 0.006, sn[1] * 0.006, sn[2] * 0.006)
        b.group = bake_light.GLOW
        for k in range(n_p):
            pa, pb = x0 + k * w_p + 0.08, x0 + (k + 1) * w_p - 0.08
            ya, za = y1 - 0.25 + 0.04 * 0.25 / 0.25, z1 - 0.06
            yb, zb = y1 - 0.02, z0 + 0.35 + 0.02 * (dz - 0.35) / 0.25
            q = [(pa, ya, za), (pb, ya, za), (pb, yb, zb), (pa, yb, zb)]
            b.poly([(p[0] + lift[0], p[1] + lift[1], p[2] + lift[2]) for p in q], sn, "decals", m.d("screens"))
        t_item(m)
        b.poly([(x0 + 0.1, y1 - 0.249, z1 - 0.005), (x1 - 0.1, y1 - 0.249, z1 - 0.005), (x1 - 0.1, y1 - 0.249, z1 - 0.12),
                (x0 + 0.1, y1 - 0.249, z1 - 0.12)], (0, 1, 0), "decals", m.d("keys"))
        for xs in (x0, x1):
            b.poly([(xs, y1 - 0.25, z0 + 0.35), (xs, y1 - 0.25, z1), (xs, y1, z0 + 0.35)], (1 if xs == x1 else -1, 0, 0),
                   "rip_bright", uv_world(1.0))
        if z0 > -TZ + 1.0:                    # out in the room (nothing behind it): monitors on stands along the back
            for k in range(max(1, int((x1 - x0) // 1.3))):
                cx = x0 + (k + 0.5) * (x1 - x0) / max(1, int((x1 - x0) // 1.3))
                t_part(m, cx - 0.04, y1, z0 + 0.12, cx + 0.04, y1 + 0.12, z0 + 0.2, "rip_iron")
                t_part(m, cx - 0.32, y1 + 0.12, z0 + 0.1, cx + 0.32, y1 + 0.52, z0 + 0.16, "rip_iron")
                b.group = bake_light.GLOW
                flat(b, (0, 0, 1), z0 + 0.164, cx - 0.3, cx + 0.3, y1 + 0.14, y1 + 0.5, "decals", m.d("monitor"))
                t_item(m)
    elif kind.startswith("chair_"):           # (0.36.22) a steel-framed chair; the name says which way it faces
        face = {"e": ("x", 1), "w": ("x", -1), "s": ("z", 1), "n": ("z", -1)}[kind[-1]]
        seat = y0 + 0.45
        for px in (x0 + 0.04, x1 - 0.08):
            for pz in (z0 + 0.04, z1 - 0.08):
                t_part(m, px, y0, pz, px + 0.04, seat, pz + 0.04, "rip_iron")
        t_part(m, x0, seat, z0, x1, seat + 0.06, z1, "rip_navy")
        if face[0] == "x":
            bx = x0 if face[1] > 0 else x1 - 0.06
            t_part(m, bx, seat + 0.06, z0 + 0.03, bx + 0.06, y1, z1 - 0.03, "rip_navy")
        else:
            bz = z0 if face[1] > 0 else z1 - 0.06
            t_part(m, x0 + 0.03, seat + 0.06, bz, x1 - 0.03, y1, bz + 0.06, "rip_navy")
    elif kind == "helm":
        t_part(m, x0 + 0.1, y0, z0 + 0.1, x1 - 0.1, y1 - 0.3, z1 - 0.1, "rip_iron")
        t_part(m, x0 + 0.05, y1 - 0.3, z0 + 0.05, x1 - 0.05, y1 - 0.2, z1 - 0.05, "rip_steel_in")
        cyl(b, ((x0 + x1) / 2, y1 - 0.12, (z0 + z1) / 2), 0.04, 0.16, "rip_iron", sides=6)
        cyl(b, ((x0 + x1) / 2, y1 - 0.03, (z0 + z1) / 2), 0.26, 0.04, "rip_wood", "rip_wood", sides=12)
    elif kind == "radio":
        t_part(m, x0, y1 - 0.05, z0, x1, y1, z1, "rip_wood")
        legs(y1 - 0.05)
        front("radio", lo=y0 + 0.2, hi=y1 - 0.08)
    elif kind == "crates":                    # wooden crates stacked two high, the top one smaller
        r2 = random.Random("%.1f%.1f" % (c[0], c[2]))
        h1 = min(0.75, s[1] / 2)
        n = max(1, int(max(s[0], s[2]) // 1.0))
        for k in range(n):
            if s[0] >= s[2]:
                a0, a1, b0, b1 = x0 + k * s[0] / n + 0.03, x0 + (k + 1) * s[0] / n - 0.03, z0 + 0.03, z1 - 0.03
            else:
                a0, a1, b0, b1 = x0 + 0.03, x1 - 0.03, z0 + k * s[2] / n + 0.03, z0 + (k + 1) * s[2] / n - 0.03
            t_part(m, a0, y0, b0, a1, y0 + h1, b1, "rip_wood")
            t_part(m, a0 - 0.01, y0 + h1 / 2 - 0.04, b0 - 0.01, a1 + 0.01, y0 + h1 / 2 + 0.04, b1 + 0.01, "rip_iron")
            # (0.36.42, model audit: a missing top crate left the box's top half solid and empty) every stack is
            # as tall as its box
            if y1 - (y0 + h1) > 0.2:
                t_part(m, a0 + 0.08, y0 + h1, b0 + 0.08, a1 - 0.08, y1, b1 - 0.08, r2.choice(["rip_wood", "rip_cont_c"]))
    elif kind == "sofa":                      # (0.36.19) a seat, a back on the wall side, arms at the ends
        seat = y0 + 0.45
        if axis == "x":
            bx0, bx1 = (x0, x0 + 0.22) if sg > 0 else (x1 - 0.22, x1)
            t_part(m, x0, y0, z0, x1, seat, z1, "rip_red")
            t_part(m, bx0, seat, z0, bx1, y1, z1, "rip_red")
            for az in (z0, z1 - 0.18):
                t_part(m, x0, seat, az, x1, seat + 0.2, az + 0.18, "rip_red")
        else:
            bz0, bz1 = (z0, z0 + 0.22) if sg > 0 else (z1 - 0.22, z1)
            t_part(m, x0, y0, z0, x1, seat, z1, "rip_red")
            t_part(m, x0, seat, bz0, x1, y1, bz1, "rip_red")
            for ax in (x0, x1 - 0.18):
                t_part(m, ax, seat, z0, ax + 0.18, seat + 0.2, z1, "rip_red")
    elif kind == "tv":                        # a low cabinet, the screen standing on it
        t_part(m, x0, y0, z0, x1, y0 + 0.5, z1, "rip_wood")
        if axis == "x":
            sx0 = x0 + 0.15 if sg > 0 else x1 - 0.23
            t_part(m, sx0, y0 + 0.55, z0 + 0.1, sx0 + 0.08, y1, z1 - 0.1, "rip_iron")
            fx = sx0 + 0.08 + 0.004 if sg > 0 else sx0 - 0.004
            flat(b, (sg, 0, 0), fx, z0 + 0.16, z1 - 0.16, y0 + 0.61, y1 - 0.06, "rip_navy", uv_world(1.0))
        else:
            sz0 = z0 + 0.15 if sg > 0 else z1 - 0.23
            t_part(m, x0 + 0.1, y0 + 0.55, sz0, x1 - 0.1, y1, sz0 + 0.08, "rip_iron")
            fz = sz0 + 0.08 + 0.004 if sg > 0 else sz0 - 0.004
            flat(b, (0, 0, sg), fz, x0 + 0.16, x1 - 0.16, y0 + 0.61, y1 - 0.06, "rip_navy", uv_world(1.0))
    elif kind == "stalls":                    # toilet cubicles in a row: white partitions, a door in each front
        L = s[0] if axis == "z" else s[2]
        n = max(1, int(L // 2.0))
        w = L / n
        lo = y0 + 0.15
        for k in range(n + 1):
            a = (x0 if axis == "z" else z0) + k * w
            a0, a1 = (a, a + 0.05) if k < n else (a - 0.05, a)
            if axis == "z":
                t_part(m, a0, lo, z0, a1, y1, z1, "rip_white")
            else:
                t_part(m, x0, lo, a0, x1, y1, a1, "rip_white")
        for k in range(n):
            a = (x0 if axis == "z" else z0) + k * w
            if axis == "z":
                fz = z0 if sg < 0 else z1 - 0.05
                t_part(m, a + 0.05, lo, fz, a + w - 0.05, y1 - 0.1, fz + 0.05, "rip_bright")
                t_part(m, a + w - 0.25, lo + 0.9, fz - 0.03 if sg < 0 else fz + 0.05, a + w - 0.17, lo + 1.0,
                       fz if sg < 0 else fz + 0.08, "rip_iron")
            else:
                fx = x0 if sg < 0 else x1 - 0.05
                t_part(m, fx, lo, a + 0.05, fx + 0.05, y1 - 0.1, a + w - 0.05, "rip_bright")
    else:
        t_part(m, x0, y0, z0, x1, y1, z1, "rip_iron")
    b.group = None


def tower_mast(m):
    """The radar mast on the stairs' head house (out of reach: nothing but the head house's roof under it, 3.4 m over
    the helideck): a yellow lattice post, a yardarm with lamps, the radar scanner, whip aerials."""
    b = m.b
    roof = None
    for row in m.data["boxes"]:
        if row["colour"] == "roof":
            roof = row
    if roof is None:
        return
    c, s = roof["pos"], roof["size"]
    base = c[1] + s[1] / 2
    mx, mz = c[0], c[2] + 2.0
    t_item(m)
    for dx in (-0.3, 0.3):
        for dz in (-0.3, 0.3):
            m.box((mx + dx, base + 3.0, mz + dz), (0.1, 6.0, 0.1), mat("rip_yellow"), cull=False)
    for k in range(6):                        # rungs / bracing
        y = base + 0.5 + k
        for (ax, az, bx, bz) in ((-0.3, -0.3, 0.3, -0.3), (-0.3, 0.3, 0.3, 0.3), (-0.3, -0.3, -0.3, 0.3), (0.3, -0.3, 0.3, 0.3)):
            m.box((mx + (ax + bx) / 2, y, mz + (az + bz) / 2), (abs(bx - ax) + 0.06, 0.05, abs(bz - az) + 0.06), mat("rip_yellow"),
                  cull=False)
    top = base + 6.0
    m.box((mx, top + 0.05, mz), (0.9, 0.1, 0.9), mat("rip_iron"), cull=False)
    m.box((mx, top - 1.4, mz), (0.08, 0.08, 3.2), mat("rip_yellow"), cull=False)     # the yardarm (along z)
    for dz in (-1.5, 1.5):
        cyl(b, (mx, top - 1.5, mz + dz), 0.07, 0.14, "rip_lamp", sides=6)
    # the radar: a pedestal and the long scanner bar
    m.box((mx, top + 0.3, mz), (0.3, 0.4, 0.3), mat("rip_white"), cull=False)
    m.box((mx, top + 0.6, mz), (0.25, 0.2, 3.4), mat("rip_white"), cull=False)
    for dz in (-0.35, 0.35):                  # whip aerials
        cyl(b, (mx + 0.4, top + 1.2, mz + dz), 0.025, 2.4, "rip_iron", sides=4)
    b.group = None


def tower_band(m):
    """A dark band round the bridge's windows (the bridge deck's outside, from the window sills to their heads), so its
    front reads as one strip of glass."""
    f = 3
    lo, hi = T_FLOORS[f] + 0.75, T_FLOORS[f] + 2.55
    ops = [o for o in m.data["openings"] if abs(o["y0"] - (T_FLOORS[f] + 0.9)) < 0.05]
    for axis, at, n, a0, a1 in (("x", -TZ - 0.15, -1, -TX - 0.15, TX + 0.15), ("z", -TX - 0.15, -1, -TZ - 0.15, TZ + 0.15),
                                ("z", TX + 0.15, 1, -TZ - 0.15, TZ + 0.15)):
        holes = sorted((o["a0"] - 0.08, o["a1"] + 0.08) for o in ops if o["axis"] == axis and abs(abs(o["at"]) - abs(at + -n * 0.15)) < 0.01
                       and (o["at"] > 0) == (n > 0))
        edges = [a0]
        for h0, h1 in holes:
            edges += [h0, h1]
        edges.append(a1)
        for pa, pb in zip(edges[::2], edges[1::2]):
            if pb - pa > 0.02:
                if axis == "x":
                    flat(m.b, (0, 0, n), at + n * 0.008, pa, pb, lo, hi, "rip_iron", uv_world(1.0))
                else:
                    flat(m.b, (n, 0, 0), at + n * 0.008, pa, pb, lo, hi, "rip_iron", uv_world(1.0))


def t_frame(m, o):
    """Dark steel frames round an opening, on both faces of its wall; a sill under an outside window."""
    a0, a1, y0, y1, t = o["a0"], o["a1"], o["y0"], o["y1"], o["t"]
    if y0 >= T_ROOF - 0.01 and t < 0.25:
        return                                # (gaps in the helideck's rail: no frame)
    fw, fd = 0.08, 0.04
    window = y0 - t_floor(y0 + 0.01 if y0 >= T_FLOORS[0] else y0) > 0.5 if y0 >= T_FLOORS[0] - 0.01 else False
    outer = (o["axis"] == "x" and abs(abs(o["at"]) - TZ) < 0.01) or (o["axis"] == "z" and abs(abs(o["at"]) - TX) < 0.01)
    for sg in (-1, 1):
        face = o["at"] + sg * t / 2
        pieces = [(a0 - fw, a0, y0 - (fw if window else 0), y1 + fw), (a1, a1 + fw, y0 - (fw if window else 0), y1 + fw),
                  (a0 - fw, a1 + fw, y1, y1 + fw)]
        if window:
            pieces.append((a0 - fw, a1 + fw, y0 - fw, y0))
        for pa, pb, ya, yb in pieces:
            if o["axis"] == "x":
                m.box(((pa + pb) / 2, (ya + yb) / 2, face + sg * fd / 2), (pb - pa, yb - ya, fd), mat("rip_iron"), cull=False)
            else:
                m.box((face + sg * fd / 2, (ya + yb) / 2, (pa + pb) / 2), (fd, yb - ya, pb - pa), mat("rip_iron"), cull=False)
        if not window and outer and sg == 1 and abs(y0 - T_FLOORS[0]) < 0.02:
            # (0.36.22) a steel sill across the outside doorway, the depth of the wall and a little more each side
            if o["axis"] == "x":
                m.box(((a0 + a1) / 2, y0 + 0.01, o["at"]), (a1 - a0, 0.02, t + 0.16), mat("rip_iron"), cull=False)
            else:
                m.box((o["at"], y0 + 0.01, (a0 + a1) / 2), (t + 0.16, 0.02, a1 - a0), mat("rip_iron"), cull=False)
        if window and outer and sg == (1 if o["at"] > 0 else -1):
            # a drip sill under the outside of the window
            if o["axis"] == "x":
                m.box(((a0 + a1) / 2, y0 - fw - 0.03, face + sg * 0.05), (a1 - a0 + 0.3, 0.06, 0.1), mat("rip_white"), cull=False)
            else:
                m.box((face + sg * 0.05, y0 - fw - 0.03, (a0 + a1) / 2), (0.1, 0.06, a1 - a0 + 0.3), mat("rip_white"), cull=False)


def sign_w(m, name, lo=1.2, hi=2.1, tallest=0.5):
    """(0.36.22, owner: "the signs are too small") A room sign's width: about 0.2 m a letter, no taller than `tallest`."""
    u0, v0, u1, v1 = m.decals.regions[name]
    aspect = (v1 - v0) / (u1 - u0)
    w = min(hi, max(lo, 0.2 * len(name.split("_", 1)[1])))
    return min(w, tallest / aspect)


def t_sign(m, axis, at, n_sign, a_mid, y, name, width, height=None):
    """A sign plate flat on a wall (1 cm out), centred at a_mid along it, its bottom at y."""
    rect = m.decals.regions[name]
    if height is None:
        u0, v0, u1, v1 = rect
        aspect = (v1 - v0) / (u1 - u0)
        height = width * aspect
    n = (n_sign, 0, 0) if axis == "z" else (0, 0, n_sign)
    flat(m.b, n, at + n_sign * 0.012, a_mid - width / 2, a_mid + width / 2, y, y + height, "decals", m.d(name))


def tower_details(m):
    b = m.b
    data = m.data
    # the white fill at the corners and the floor lines (the gray box's walls stop at the slabs and at each other)
    for sx in (-1, 1):
        for sz in (-1, 1):
            xa, xb = sorted((sx * TX, sx * (TX + 0.15)))
            za, zb = sorted((sz * TZ, sz * (TZ + 0.15)))
            m.box(((xa + xb) / 2, (T_FLOORS[0] + T_ROOF) / 2, (za + zb) / 2), (xb - xa, T_ROOF - T_FLOORS[0], zb - za),
                  mat("rip_white"), cull=False)
            xa, xb = sorted((sx * TX, sx * (TX + 0.1)))
            za, zb = sorted((sz * TZ, sz * (TZ + 0.1)))
            m.box(((xa + xb) / 2, T_ROOF + 0.5, (za + zb) / 2), (xb - xa, 1.0, zb - za), mat("rip_white"), cull=False)
    for y in list(T_FLOORS[1:]) + [T_ROOF]:
        lo = y - SLAB
        for sz in (-1, 1):
            za, zb = sorted((sz * TZ, sz * (TZ + 0.15)))
            m.box((0.0, lo + SLAB / 2, (za + zb) / 2), (2 * TX, SLAB, zb - za), mat("rip_white"), cull=False)
        for sx in (-1, 1):
            xa, xb = sorted((sx * TX, sx * (TX + 0.15)))
            spans = [(-TZ, TZ)] if sx < 0 else [(-TZ, T_STAIR[2]), (T_STAIR[3], TZ)]   # (the stairs' wall fills it there)
            for za, zb in spans:
                m.box(((xa + xb) / 2, lo + SLAB / 2, (za + zb) / 2), (xb - xa, SLAB, zb - za), mat("rip_white"), cull=False)
    # frames
    for o in data["openings"]:
        t_frame(m, o)
    # signs over the corridor doors (facing the corridor), over the stair doors, outside doors
    for o in data["openings"]:
        f = t_floor(o["y0"] + 0.01)
        if not 0 <= f <= 3 or o["y0"] - T_FLOORS[f] > 0.3:
            continue
        mid = (o["a0"] + o["a1"]) / 2
        top = o["y1"] + 0.14
        if o["axis"] == "x" and abs(o["at"] - T_STAIR[3]) < 0.01 and mid > T_STAIR[0]:   # the stairs' south doors
            t_sign(m, "x", o["at"] + o["t"] / 2, 1, mid, top, "sign_STAIRS", sign_w(m, "sign_STAIRS"))
            t_sign(m, "x", o["at"] - o["t"] / 2, -1, mid, top, "deck_" + DECK_NAMES[T_FLOORS[f]], 1.3)
        elif o["axis"] == "x" and (abs(o["at"]) < 0.01 or abs(o["at"] - 3.0) < 0.01):   # the corridor's doors
            north = abs(o["at"]) < 0.01
            room = t_room(mid, -1.0 if north else 4.0, f)
            n = 1 if north else -1
            nm = "sign_" + ROOM_NAMES[f][room]
            t_sign(m, "x", o["at"] + n * o["t"] / 2, n, mid, top, nm, sign_w(m, nm))
        elif o["axis"] == "z" and abs(o["at"] - T_STAIR[0]) < 0.01:         # the stairs' doors
            t_sign(m, "z", o["at"] - o["t"] / 2, -1, mid, top, "sign_STAIRS", sign_w(m, "sign_STAIRS"))
            t_sign(m, "z", o["at"] + o["t"] / 2, 1, mid, top, "deck_" + DECK_NAMES[T_FLOORS[f]], 1.3)
        elif o["axis"] == "x" and abs(abs(o["at"]) - TZ) < 0.01 and f == 0:  # outside doors on the main deck
            n = 1 if o["at"] > 0 else -1
            room = t_room(mid, o["at"] - n * 1.0, 0)
            nm = "sign_" + ROOM_NAMES[0][room]
            t_sign(m, "x", o["at"] + n * o["t"] / 2, n, mid, top, nm, sign_w(m, nm))
    # the stairs onto the helideck: its door is in the head house's west wall (the top landing)
    for o in data["openings"]:
        if o["axis"] == "z" and abs(o["at"] - T_STAIR[0]) < 0.01 and abs(o["y0"] - T_ROOF) < 0.05:
            mid = (o["a0"] + o["a1"]) / 2
            t_sign(m, "z", o["at"] + o["t"] / 2, 1, mid, o["y1"] + 0.14, "deck_HELIDECK", 1.3)
    # LEVIATHAN across the bridge front (on the helideck's rail), NO SMOKING and a muster sign by the north doors
    t_sign(m, "x", -TZ - 0.1, -1, 0.0, T_ROOF + 0.12, "nameboard", 7.5)
    t_sign(m, "x", -TZ - 0.15, -1, -4.0, T_FLOORS[0] + 1.3, "no_smoking", 0.9)
    t_sign(m, "x", -TZ - 0.15, -1, 8.5, T_FLOORS[0] + 1.3, "sign_MUSTER STATION", 1.4)
    t_sign(m, "x", TZ + 0.15, 1, 7.6, T_FLOORS[0] + 1.3, "sign_LIFEJACKETS", 1.2)
    # the helideck's H, the touchdown ring (16 m across, in the open part west of the stairs' head house)
    b.poly([(-12.0, T_ROOF + 0.006, -8.0), (4.0, T_ROOF + 0.006, -8.0), (4.0, T_ROOF + 0.006, 8.0), (-12.0, T_ROOF + 0.006, 8.0)],
           (0, 1, 0), "graffiti", m.d("helipad"))
    # lifebuoys on the outside walls (a ring of 8 short pieces, 6 cm deep)
    for axis, at, n, a, y in (("x", -TZ - 0.15, -1, -11.0, 5.4), ("x", TZ + 0.15, 1, 6.0, 5.4), ("z", -TX - 0.15, -1, -2.0, 5.4),
                              ("z", TX + 0.15, 1, 4.0, 5.4), ("x", -TZ - 0.15, -1, 11.0, 12.6), ("z", -TX - 0.15, -1, 4.3, 12.6)):
        t_item(m)
        for k in range(8):
            ang = 2 * math.pi * (k + 0.5) / 8
            ca, cy_ = a + 0.3 * math.cos(ang), y + 0.3 * math.sin(ang)
            seg = 2 * 0.3 * math.tan(math.pi / 8) + 0.02
            col = "rip_orange" if k % 2 else "rip_white"
            if axis == "x":
                c3 = (ca, cy_, at + n * 0.03)
                sz = (seg, 0.1, 0.06) if abs(math.sin(ang)) > 0.7 else ((0.1, seg, 0.06) if abs(math.cos(ang)) > 0.7 else (0.12, 0.12, 0.06))
            else:
                c3 = (at + n * 0.03, cy_, ca)
                sz = (0.06, 0.1, seg) if abs(math.sin(ang)) > 0.7 else ((0.06, seg, 0.1) if abs(math.cos(ang)) > 0.7 else (0.06, 0.12, 0.12))
            m.box(c3, sz, mat(col), cull=False)
        b.group = None
    # ceiling lamps, a clock in the mess and on the bridge
    for f, y in enumerate(T_FLOORS):         # (0.36.19: over the middle of each room and along the corridor)
        ceil = (T_FLOORS[f + 1] if f + 1 < len(T_FLOORS) else T_ROOF) - SLAB
        hall = f in T_HALL_FLOORS
        ne = -0.5 if hall else 1.0
        spots = [(-9.0, -12.0), (-9.0, -5.0), (ne, -12.0), (ne, -5.0), (-10.0, 1.5), (-1.0, 1.5), (9.0, 1.5),
                 (-9.5, 7.0), (-9.5, 12.5), (0.5, 7.0), (0.5, 12.5), (10.0, 7.0), (10.0, 12.5)]
        if hall:
            spots += [(4.5, -12.0), (4.5, -5.0)]
        for x, z in spots:
            t_lamp(m, x, ceil, z)
    for row in data["boxes"]:
        if row["colour"] == "concrete" and not row["pitch"]:
            c, s = row["pos"], row["size"]
            if s[2] < 3.5 and s[0] > 7:
                t_lamp(m, c[0], c[1] - s[1] / 2, c[2], 0.8, 0.25)
    for axis, at, n, a, y in (("z", -TX + 0.15, 1, -8.0, T_FLOORS[1] + 2.3), ("z", -TX + 0.15, 1, 4.5, T_FLOORS[3] + 2.6)):
        flat(b, (n, 0, 0), at + 0.012, a - 0.2, a + 0.2, y, y + 0.4, "graffiti", m.d("clock"))
    # pegboards over the benches, the radio rack's wall
    for row in data["boxes"]:
        if row.get("kind") == "bench":
            c, s = row["pos"], row["size"]
            axis, sg = _against(row)
            y = c[1] + s[1] / 2 + 0.25
            back = (c[0] - sg * (s[0] / 2 + 0.05), y + 0.35, c[2]) if axis == "x" else (c[0], y + 0.35, c[2] - sg * (s[2] / 2 + 0.05))
            if not m.inside(back):
                continue                      # (a bench out in the room: no wall to hang the board on)
            if axis == "x":
                at = c[0] - sg * s[0] / 2
                flat(b, (sg, 0, 0), at + sg * 0.012, c[2] - s[2] / 2 + 0.2, c[2] + s[2] / 2 - 0.2, y, y + 0.7, "decals", m.d("pegboard"))
            else:
                at = c[2] - sg * s[2] / 2
                flat(b, (0, 0, sg), at + sg * 0.012, c[0] - s[0] / 2 + 0.2, c[0] + s[0] / 2 - 0.2, y, y + 0.7, "decals", m.d("pegboard"))


SLAB = 0.25


def tower_wall(m, row, skirts):
    """A wall piece: white outside, the room's paint inside (steel on the main deck and in the stairwell)."""
    c, s = row["pos"], row["size"]
    stair_east = abs(c[0] - T_STAIR[1]) < 0.01 and s[1] > 20
    tall = s[1] > 4.0 and not stair_east     # (the stairs' walls run through every deck: painted deck by deck)

    def style(n, mid, corners):
        y = mid[1]
        if abs(n[1]) > 0.7:
            if n[1] < 0 and y < T_FLOORS[0] - 0.05:
                return None
            f = t_floor(y + (0.02 if n[1] > 0 else -0.3))
            if y >= T_ROOF + 0.5 and n[1] > 0:
                return "rip_roof"
            outer = abs(abs(c[0]) - TX) < 0.01 and s[0] < 0.5 or abs(abs(c[2]) - TZ) < 0.01 and s[2] < 0.5
            if outer and f >= 0:
                return "rip_white"
            return t_wall_mat(f, t_room(mid[0], mid[2], f))
        if stair_east and n[0]:
            return None                      # (drawn in bands below: the tower's own east wall covers it)
        if tall:
            tall_faces.append((n, mid, corners))
            return None
        p = (mid[0] + n[0] * 0.3, mid[1], mid[2] + n[2] * 0.3)
        f = t_floor(y)
        room = t_room(p[0], p[2], f)
        if f == 4 or (f >= 0 and room == "out"):
            return "rip_white"
        mt = t_wall_mat(f, room)
        lo = min(q[1] for q in corners)
        if 1 <= f <= 3 and room != "stair" and abs(lo - T_FLOORS[f]) < 0.02:
            skirts.append((n, mid, corners))
        return mt
    tall_faces = []
    m.box(c, s, style)
    for n, mid, corners in tall_faces:
        y0, y1 = min(q[1] for q in corners), max(q[1] for q in corners)
        axis_i = 0 if n[0] else 2
        other = 2 if n[0] else 0
        a0, a1 = min(q[other] for q in corners), max(q[other] for q in corners)
        at = mid[axis_i]
        cuts = sorted({y0, y1} | {v for f in T_FLOORS + (T_ROOF,) for v in (f - SLAB, f) if y0 < v < y1})
        for lo, hi in zip(cuts, cuts[1:]):
            ym = (lo + hi) / 2
            pts = [(at, lo, a0), (at, lo, a1), (at, hi, a1), (at, hi, a0)] if n[0] else \
                  [(a0, lo, at), (a1, lo, at), (a1, hi, at), (a0, hi, at)]
            bm = tuple((lo + hi) / 2 if k == 1 else (mid[k] if k == axis_i else (a0 + a1) / 2) for k in range(3))
            if m.hidden(n, bm, pts):
                continue
            f = t_floor(ym)
            p = (bm[0] + n[0] * 0.3, bm[2] + n[2] * 0.3)
            room = t_room(*p, f)
            mt = "rip_white" if f == 4 or (f >= 0 and room == "out") else t_wall_mat(f, room)
            flat(m.b, n, at, a0, a1, lo, hi, mt, uv_world())
            if 1 <= f <= 3 and room != "stair" and abs(lo - T_FLOORS[f]) < 0.02:
                skirts.append((n, bm, pts))
    if stair_east:
        y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
        bands = [(y0, T_FLOORS[0])] + [(f - SLAB, f) for f in T_FLOORS[1:]] + [(T_ROOF - SLAB, y1)]
        for sg in (-1, 1):
            at = c[0] + sg * s[0] / 2
            for lo, hi in bands:
                if sg > 0 and lo >= T_FLOORS[0] - 0.01 and hi <= T_ROOF:
                    mt = "rip_white"
                elif sg > 0:
                    mt = "rip_white" if lo >= T_ROOF - SLAB - 0.01 else "rip_steel_in"
                else:
                    mt = "rip_steel_in"
                flat(m.b, (sg, 0, 0), at, c[2] - s[2] / 2, c[2] + s[2] / 2, lo, hi, mt, uv_world())


def tower_slab(m, row):
    c, s = row["pos"], row["size"]
    top = c[1] + s[1] / 2
    split = row["colour"] == "metal" and 1 <= t_floor(top + 0.01) <= 3
    if split:                                 # (a slab runs under several rooms: each gets its own floor)
        x0, x1, z0, z1 = c[0] - s[0] / 2, c[0] + s[0] / 2, c[2] - s[2] / 2, c[2] + s[2] / 2
        xs = sorted({x0, x1} | {v for v in (-5.0, -4.0, 3.0, 6.0) if x0 < v < x1})
        zs = sorted({z0, z1} | {v for v in (0.0, 3.0) if z0 < v < z1})
        for xa, xb in zip(xs, xs[1:]):
            for za, zb in zip(zs, zs[1:]):
                ft = t_floor(top + 0.01)
                mt = t_floor_mat(ft, t_room((xa + xb) / 2, (za + zb) / 2, ft))
                m.b.poly([(xa, top, za), (xb, top, za), (xb, top, zb), (xa, top, zb)], (0, 1, 0), mt, uv_world())

    def style(n, mid, corners):
        if n[1] > 0.7:
            if split:
                return None
            f = t_floor(mid[1] + 0.01)
            if row["colour"] == "roof":
                return "rip_roof"
            if row["colour"] == "concrete":
                return "rip_deck"
            return t_floor_mat(f, t_room(mid[0], mid[2], f))
        if n[1] < -0.7:
            f = t_floor(mid[1] - 0.3)
            room = t_room(mid[0], mid[2], f)
            if f <= 0 or room == "stair" or row["colour"] in ("concrete", "roof"):
                return "rip_steel_in"
            return "rip_ceiling"
        if row["colour"] == "concrete":
            return ("rip_yellow", uv_world(1.0))
        return ("rip_iron", uv_world(1.0))
    m.box(c, s, style)


def lifeboat(m, row):
    """(0.38.7) the boat deck's lifeboat, hung in its davits over the side: an orange enclosed boat, a white canopy
    with a band of windows, the davit arms and the falls up to them. Long axis along z, the deck to the west."""
    c, s = row["pos"], row["size"]
    cx, cy, cz = c
    w, h, L = s
    y0 = cy - h / 2
    orange, white, iron = mat("rip_orange"), mat("rip_white"), mat("rip_iron")
    m.box((cx, y0 + 0.25, cz), (w * 0.62, 0.5, L * 0.86), orange)             # the keel, narrower
    m.box((cx, y0 + 0.85, cz), (w, 0.7, L * 0.96), orange)                     # the hull
    m.box((cx, y0 + 1.25, cz), (w + 0.06, 0.1, L * 0.97), white)               # the rubbing strake
    m.box((cx, y0 + 1.7, cz), (w * 0.86, 0.8, L * 0.78), white)                # the canopy
    m.box((cx, y0 + 1.75, cz), (w * 0.88, 0.22, L * 0.7), mat("rip_glass"))    # its windows
    m.box((cx, y0 + 2.2, cz + L * 0.3), (w * 0.5, 0.3, 1.0), orange)           # the helm hatch
    for z in (cz - L * 0.42, cz + L * 0.42):                                    # bow and stern, tapered
        m.box((cx, y0 + 0.75, z), (w * 0.7, 0.6, L * 0.1), orange)
    for z in (cz - L * 0.4, cz + L * 0.4):                                      # the davits and the falls
        m.box((cx - w / 2 + 0.55, y0 + 3.1, z), (1.6, 0.16, 0.16), iron)
        m.box((cx - w / 2 - 0.05, y0 + 1.85, z), (0.14, 2.6, 0.14), iron)
        m.box((cx, y0 + 2.6, z), (0.04, 1.0, 0.04), iron)


def build_tower(name="bridge_tower"):
    mb.BUILDING_NAME[0] = name
    with open(os.path.join(ROOT, "art_source", "buildings", name + ".json")) as f:
        data = json.load(f)
    textures, mat_info = {}, {}
    for kit, painter in KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join(KIT_DIR, kit + ".png"), painter, random.Random(kit))
    atlas = tower_decals(random.Random(name))
    textures[name + "_decals"] = Texture(name + "_decals", os.path.join("art_source", "textures", name + "_decals.png"),
                                         lambda r: atlas.c, random.Random(name))
    mat_info["decals"] = (name + "_decals", False, False)
    mat_info["graffiti"] = (name + "_decals", True, False)
    m = Model(data, atlas)
    m.rng = random.Random(name)
    skirts = []
    for row in data["boxes"]:
        col = row["colour"]
        if row.get("kind") == "lifeboat":
            lifeboat(m, row)
        elif row.get("kind"):
            t_prop(m, row)
        elif row["pitch"]:
            m.box(row["pos"], row["size"], ramp_style, yaw=row["yaw"], pitch=row["pitch"])
        elif col == "wall":
            tower_wall(m, row, skirts)
        elif col in ("metal", "concrete", "roof"):
            tower_slab(m, row)
        elif col == "rust":                       # the helideck's rail: white, a yellow cap
            m.box(row["pos"], row["size"], lambda n, mid, q: ("rip_yellow", uv_world(1.0)) if n[1] > 0.7 else
                  (None if n[1] < -0.7 else "rip_white"))
        else:
            m.box(row["pos"], row["size"], mat("rip_iron"))
    for n, mid, corners in skirts:              # a dark skirting board along the bottom of the panelled walls
        lo = min(q[1] for q in corners)
        if n[0]:
            zs = [q[2] for q in corners]
            flat(m.b, n, mid[0] + n[0] * 0.01, min(zs), max(zs), lo, lo + 0.12, "rip_iron", uv_world(1.0))
        else:
            xs = [q[0] for q in corners]
            flat(m.b, n, mid[2] + n[2] * 0.01, min(xs), max(xs), lo, lo + 0.12, "rip_iron", uv_world(1.0))
    tower_details(m)
    tower_band(m)
    tower_mast(m)
    b = m.b
    bake_light.CELL = 1.5
    bake_light.DARK = 0.62                    # (rooms lit by their lamps: not as dark as the hold)
    bake_light.bake(b, [r for r in data["boxes"] if not r["pitch"]])
    cells = riptide_atlas()
    tris = sum(len(f) - 2 for f in b.faces)
    print(f"{name}: {tris} triangles, {len(set('riptide_atlas' if mn in cells else mn for mn in b.mat_names))} materials")
    out = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    mb.write_glb(out, b, textures, mat_info, atlas=cells, atlas_name="riptide_atlas")
    mb.set_import_script(out)
    print("exported", out)
    return tris


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    name = args[0] if args else "leviathan_hull"
    if name == "below_decks":
        import make_riptide_below
        make_riptide_below.build_below(name)
    elif name == "quay_front":
        import make_riptide_quay
        make_riptide_quay.build_quay(name)
    elif name == "north_point":
        import make_riptide_north
        make_riptide_north.build_north(name)
    elif name == "south_port":
        import make_riptide_south
        make_riptide_south.build_south(name)
    elif name == "harbor_plaza":
        import make_riptide_plaza
        make_riptide_plaza.build_plaza(name)
    elif name == "site_zero":
        import make_riptide_lab
        make_riptide_lab.build_lab(name)
    else:
        build_tower(name) if name == "bridge_tower" else build(name)
