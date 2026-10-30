"""Bloxov Frontlines ground textures (World art 0.17, outdoor step 2; plan /mnt/project-files/notes/outdoor-plan.md).

The ground (BoxMap's height grid, and the outdoor kit's earth banks and crater rims) is drawn by one shader,
assets/shaders/ground.gdshader (material assets/materials/ground.tres): grass, with two grass textures mixed in big
patches, bare earth on steep slopes and worn paths, mud by the creek, scorched earth round craters and the bombed
quarter, gravel on road shoulders, the railway and round buildings. Which of those goes where is painted by the
generator (tools/gen_old_bloxov.py writes assets/textures/ground/splat.png). This script paints the tiles (64 px for
2 m, like the building kit) in every grass look; the picked look is copied to grass_a.png / grass_b.png:

    python3 art_source/scripts/make_ground.py [look]     (look: a, b, c, d or mix; default GROUND_LOOK)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
from make_building import Canvas  # noqa: E402

OUT = os.path.join(mb.ROOT, "assets", "textures", "ground")
LOOKS_DIR = os.path.join(mb.ROOT, "art_source", "textures", "ground_looks")   # every look (not shipped)
GROUND_LOOK = "mix"   # the picked grass look (see LOOKS), or "mix": MIX's three tiles in the shader's gradient
# (owner 2026-10-18: "a gradient of the 3 grass textures"): meadow, lush, then late summer, the most of the map
MIX = (("d", "a"), ("b", "a"), ("c", "a"))

mb.PALETTE.update({
    # b: lush green
    "gl_base": "6e994b", "gl_dk": "5b8440", "gl_lt": "84ab5b", "gl_clover": "50783a", "gl2_base": "648f45",
    # c: late summer (green with dry, straw-coloured patches)
    "gs_base": "7a8d4e", "gs_dk": "687b41", "gs_lt": "8e9d5b", "gs_straw": "9c9660",
    "gd_base": "8d8956", "gd_dk": "7b7849", "gd_lt": "a29e69",
    # d: meadow (lush with wildflowers)
    "fl_white": "d6d3c4", "fl_yellow": "d2b548", "fl_violet": "9682b0",
    # the rest
    "ge_base": "7a6650", "ge_dk": "6a5845", "ge_lt": "88735b", "ge_stone": "8f887c",
    "gm_base": "5d4f3d", "gm_dk": "514434", "gm_lt": "685946",
    "gx_base": "4a433b", "gx_dk": "3e3832", "gx_lt": "5a5046", "gx_ash": "6d6660",
    "gg_base": "858073", "gg_dk": "6f6a5f", "gg_lt": "9b968a", "gg_dark": "5d594f",
    # roads (outdoor step 3): b worn grey asphalt, c dark asphalt, d concrete slabs; patches darker and newer
    "ab_base": "5b5b5d", "ab_dk": "4f4f52", "ab_lt": "6a6a6b", "ab_ag": "77767a", "ab_crack": "3c3c3f",
    "ac_base": "45464a", "ac_dk": "3b3c40", "ac_lt": "525357", "ac_ag": "626266", "ac_crack": "2e2f32",
    "ad_base": "8b8780", "ad_dk": "7d7972", "ad_lt": "98948c", "ad_ag": "a29e96", "ad_crack": "5f5c56",
    "ap_base": "3f4043", "ap_dk": "37383b", "ap_lt": "4a4b4e",
})


def grass(base, dk, lt, extra=(), extra_chance=0.0, clumps=None):
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [dk, lt], 0.22, rng)
        c.blotch([dk], 26, rng, size=(2, 4))      # clumps: tufts in shadow
        c.blotch([lt], 14, rng, size=(1, 3))
        for _ in range(60):                       # blade tips catching the light: two pixels on a slant
            x, y = rng.randrange(64), rng.randrange(64)
            c.put(x, y, lt)
            c.put((x + 1) % 64, (y + 1) % 64, lt)
        if clumps:
            c.blotch([clumps], 6, rng, size=(2, 4))
        for _ in range(int(64 * 64 * extra_chance)):
            x, y = rng.randrange(64), rng.randrange(64)
            c.put(x, y, rng.choice(extra))
        return c
    return paint


def patchy(base, dk, lt, specks):
    """The second grass of a look: drier (or darker), with the first one's colour showing through."""
    def paint(rng):
        c = grass(base, dk, lt)(rng)
        c.blotch(specks, 18, rng, size=(1, 3))
        return c
    return paint


def ground_tile(base, dk, lt, stones=(), stone_count=0, blotches=8):
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [dk, lt], 0.14, rng)
        c.blotch([dk], blotches, rng, size=(3, 8))
        c.blotch([lt], blotches // 2, rng, size=(2, 6))
        for _ in range(stone_count):
            x, y = rng.randrange(64), rng.randrange(64)
            col = rng.choice(stones)
            c.rect(x, y, x + rng.choice((1, 2)), y + rng.choice((1, 2)), col)
        return c
    return paint


def gravel(rng):
    c = Canvas(64, 64, "gg_base")
    c.noise(0, 0, 64, 64, ["gg_dk", "gg_lt"], 0.35, rng)
    for _ in range(140):     # stones, each with a darker under side
        x, y = rng.randrange(64), rng.randrange(64)
        c.rect(x, y, x + 2, y + 2, rng.choice(("gg_lt", "gg_base", "gg_dk")))
        c.put(x, (y - 1) % 64, "gg_dark")
        c.put((x + 1) % 64, (y - 1) % 64, "gg_dark")
    return c


# look: (grass_a, grass_b) painters; "a" is today's flat colour
LOOKS = {
    "a": (mb.paint_flat("grass_flat"), mb.paint_flat("grass_flat")),
    "b": (grass("gl_base", "gl_dk", "gl_lt", clumps="gl_clover"), grass("gl2_base", "gl_dk", "gl_lt", clumps="gl_clover")),
    "c": (grass("gs_base", "gs_dk", "gs_lt", extra=("gs_straw",), extra_chance=0.02),
          patchy("gd_base", "gd_dk", "gd_lt", ["gs_base", "gs_dk"])),
    "d": (grass("gl_base", "gl_dk", "gl_lt", extra=("fl_white", "fl_yellow", "fl_violet"), extra_chance=0.008, clumps="gl_clover"),
          grass("gl2_base", "gl_dk", "gl_lt", extra=("fl_white", "fl_yellow"), extra_chance=0.015)),
}
mb.PALETTE.update({"grass_flat": "789e5c"})
TILES = {
    "earth": ground_tile("ge_base", "ge_dk", "ge_lt", ("ge_stone", "ge_dk"), 30),
    "mud": ground_tile("gm_base", "gm_dk", "gm_lt", ("ge_dk",), 10, blotches=12),
    "scorch": ground_tile("gx_base", "gx_dk", "gx_lt", ("gx_ash", "gx_dk"), 25, blotches=10),
    "gravel": gravel,
    "dither": None,
}


# Grass tufts (scripts/grass_tufts.gd): two 16 x 16 sprites side by side (0.5 m, 32 px per metre like the tiles):
# blades, and blades with wildflowers, in the picked look's colours.
TUFT_COLOURS = {"a": ("gl_dk", "grass_flat", "gl_lt", None), "b": ("gl_dk", "gl_base", "gl_lt", None),
                "c": ("gs_dk", "gs_base", "gs_lt", "gs_straw"), "d": ("gl_dk", "gl_base", "gl_lt", None)}


def tufts(path, look):
    dk, mid, lt, dry = TUFT_COLOURS[look]
    rng = random.Random(f"tufts {look}")
    px = [[None] * 32 for _ in range(16)]     # rows bottom-first; None = see-through
    for half in (0, 1):
        for _ in range(9):
            x = rng.randrange(2, 14) + half * 16
            h = rng.randrange(6, 15)
            lean = rng.choice((-1, 0, 0, 1))
            straw = dry and rng.random() < 0.25
            for y in range(h):
                xx = x + (lean * y) // 6
                if half * 16 <= xx < half * 16 + 16:
                    col = (dry if straw else dk) if y < h * 0.35 else (dry if straw else mid) if y < h * 0.8 else lt
                    px[y][xx] = col
        if half:                                   # flowers on some tips
            for _ in range(4):
                x, y = rng.randrange(18, 30), rng.randrange(8, 14)
                col = rng.choice(("fl_white", "fl_yellow", "fl_violet"))
                for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                    px[y + dy if y + dy < 16 else y][x + dx] = col
                for yy in range(y):
                    if px[yy][x] is None:
                        px[yy][x] = dk if yy < 3 else mid
    rows = [[[int(v * 255) for v in mb.rgba(c)[:3]] + [255] if c else [0, 0, 0, 0] for c in row] for row in px]
    mb.write_png(path, 32, 16, rows)


# The bushes' leaves (World art 0.17, owner 2026-10-18: see-through, more 3D bushes that sway; picked C, D for some):
# scripts/bushes.gd builds every bush from many small cut-out cards. One 64 px tile per look, side by side:
# b leafy green, c dark evergreen, d in flower, then twigs (the airy bushes show them).
LEAF_COLOURS = {"b": ("lf1_sh", "lf1_dk", "lf1", "lf1_lt", "lf_tip1"),
                "c": ("lf2_sh", "lf2_dk", "lf2", "lf2_lt", "lf_tip2"),
                "d": ("lf3_dk", "lf1_dk", "lf3", "lf3_lt", "lf_tip3")}
mb.PALETTE.update({"lf1": "4a6b35", "lf1_dk": "3a5529", "lf1_lt": "5e8040", "lf1_sh": "2c4524",
                   "lf2": "3f5a37", "lf2_dk": "2f4529", "lf2_lt": "4f6b42", "lf2_sh": "263a22",
                   "lf3": "4f6e38", "lf3_dk": "3e5a2b", "lf3_lt": "638545",
                   "blossom": "d8d0c2", "blossom2": "c9a4b8", "twig": "5a4532", "twig_dk": "45352a",
                   "lf_tip1": "7a9a52", "lf_tip2": "5f7a4c", "lf_tip3": "8a9e58"})


def leaves(path):
    T = 64
    px = [[None] * (T * 4) for _ in range(T)]       # rows bottom-first; None = see-through
    for t, look in enumerate("bcd"):
        sh, dk, mid, lt, tip = LEAF_COLOURS[look]
        rng = random.Random(f"leaves {look}")
        for _ in range(430):                         # leaves packed in a round cluster, lit from above
            a, r = rng.uniform(0, 6.283), rng.random() ** 0.5 * 29
            x, y = int(32 + r * math.cos(a)), int(32 + r * math.sin(a))
            up = y > 34
            col = rng.choice((mid, lt, lt) if up else (sh, dk, dk, mid))
            shape = ((0, 0), (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)) if rng.random() < 0.5 else \
                ((0, 0), (1, 0), (1, 1), (2, 1), (0, -1))
            for dx, dy in shape:
                X, Y = x + dx, y + dy
                if 0 <= X < T and 0 <= Y < T:
                    px[Y][t * T + X] = col
        for _ in range(28 if look == "d" else 6):   # flowers / pale new tips
            x, y = rng.randrange(6, 58), rng.randrange(10, 58)
            if px[y][t * T + x] is None:
                continue
            col = rng.choice(("blossom", "blossom2")) if look == "d" else tip
            for dx, dy in ((0, 0), (1, 0), (0, 1)):
                if px[y + dy][t * T + x + dx] is not None:
                    px[y + dy][t * T + x + dx] = col
    rng = random.Random("twigs")                     # twigs: a few forking branches up from the bottom middle
    for _ in range(5):
        x, y = 32.0 + rng.uniform(-3, 3), 0.0
        dx = rng.uniform(-0.5, 0.5)
        while y < 60:
            X, Y = int(x), int(y)
            if 0 <= X < T:
                px[Y][3 * T + X] = "twig_dk" if y < 20 else "twig"
                if y < 14 and X + 1 < T:
                    px[Y][3 * T + X + 1] = "twig_dk"
            y += 1
            x += dx
            if rng.random() < 0.06:
                dx = max(-0.9, min(0.9, dx + rng.uniform(-0.6, 0.6)))
            if x < 4 or x > 60:
                break
    rows = [[[int(v * 255) for v in mb.rgba(c)[:3]] + [255] if c else [0, 0, 0, 0] for c in row] for row in px]
    mb.write_png(path, T * 4, T, rows)


def asphalt(base, dk, lt, ag, crack, cracks=5, n=128):
    """A road surface tile (128 px for 4 m): fine noise, aggregate specks, a few branching cracks."""
    def paint(rng):
        c = Canvas(n, n, base)
        c.noise(0, 0, n, n, [dk, lt], 0.3, rng)
        for _ in range(n * n // 40):
            c.put(rng.randrange(n), rng.randrange(n), ag)
        c.blotch([dk], 10, rng, size=(4, 10))
        for _ in range(cracks):   # a crack: a wandering line of dark pixels, sometimes forking
            x, y = rng.randrange(n), rng.randrange(n)
            dx, dy = rng.choice(((1, 0), (0, 1), (1, 1), (1, -1)))
            for _ in range(rng.randrange(20, 50)):
                c.put(x % n, y % n, crack)
                if rng.random() < 0.35:
                    x += rng.choice((-1, 0, 1)) if dx == 0 else 0
                    y += rng.choice((-1, 0, 1)) if dy == 0 else 0
                x, y = x + dx, y + dy
                if rng.random() < 0.05:
                    dx, dy = dy, dx
        return c
    return paint


ROADS = {   # look: (surface, patch)
    "b": asphalt("ab_base", "ab_dk", "ab_lt", "ab_ag", "ab_crack", cracks=7),
    "c": asphalt("ac_base", "ac_dk", "ac_lt", "ac_ag", "ac_crack", cracks=3),
    "d": asphalt("ad_base", "ad_dk", "ad_lt", "ad_ag", "ad_crack", cracks=9),
}
ROAD_PATCH = asphalt("ap_base", "ap_dk", "ap_lt", "ab_ag", "ac_crack", cracks=1)


def save(path, canvas, name):
    rows = mb.styled(canvas, random.Random(name))
    mb.write_png(path, len(rows[0]), len(rows), rows)


def dither(path):
    """64 x 64 noise, for the shader's pixel-sharp edges between ground kinds (mips average it out far off)."""
    rng = random.Random("ground dither")
    rows = [[[v, v, v, 255] for v in (rng.randrange(256) for _ in range(64))] for _ in range(64)]
    mb.write_png(path, 64, 64, rows)


def macro(path, n=128):
    """Smooth tiling value noise for the big grass patches (the shader stretches it over ~90 m)."""
    rng = random.Random("ground macro")
    g = 8
    pts = [[rng.random() for _ in range(g)] for _ in range(g)]

    def at(x, y):
        fx, fy = x / n * g, y / n * g
        i, j = int(fx), int(fy)
        u, v = fx - i, fy - j
        u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
        a, b = pts[j % g][i % g], pts[j % g][(i + 1) % g]
        c, d = pts[(j + 1) % g][i % g], pts[(j + 1) % g][(i + 1) % g]
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    rows = []
    for y in range(n):
        row = []
        for x in range(n):
            v = 0.65 * at(x, y) + 0.35 * at((x * 2) % n, (y * 2) % n)
            k = max(0, min(255, int(v * 255)))
            row.append([k, k, k, 255])
        rows.append(row)
    mb.write_png(path, n, n, rows)


def main():
    pick = sys.argv[1] if len(sys.argv) > 1 else GROUND_LOOK
    os.makedirs(LOOKS_DIR, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for look, (pa, pb) in LOOKS.items():
        for part, painter in (("a", pa), ("b", pb)):
            save(os.path.join(LOOKS_DIR, f"grass_{look}_{part}.png"), painter(random.Random(f"grass {look} {part}")),
                 f"grass {look} {part}")
    for name, painter in TILES.items():
        if painter:
            save(os.path.join(OUT, name + ".png"), painter(random.Random(name)), name)
    dither(os.path.join(OUT, "dither.png"))
    tufts(os.path.join(OUT, "tufts.png"), "c" if pick == "mix" else pick)
    leaves(os.path.join(OUT, "leaves.png"))
    macro(os.path.join(OUT, "macro.png"))
    for look, painter in ROADS.items():
        save(os.path.join(OUT, f"road_{look}.png"), painter(random.Random(f"road {look}")), f"road {look}")
    save(os.path.join(OUT, "road_patch.png"), ROAD_PATCH(random.Random("road patch")), "road patch")
    # (one look: its two tiles, the second also in grass_c's place)
    picked = MIX if pick == "mix" else ((pick, "a"), (pick, "b"), (pick, "b"))
    for slot, (look, part) in zip("abc", picked):
        with open(os.path.join(LOOKS_DIR, f"grass_{look}_{part}.png"), "rb") as f, \
                open(os.path.join(OUT, f"grass_{slot}.png"), "wb") as g:
            g.write(f.read())
    print("ground textures written, grass look", pick)


if __name__ == "__main__":
    main()
