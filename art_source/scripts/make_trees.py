"""Bloxov Frontlines tree textures (World art 0.17, outdoor step 7; plan /mnt/project-files/notes/outdoor-plan.md).

One 256 x 256 sheet, a 4 x 4 grid of 64 px tiles (2 m a tile on the leaf cards, like the bushes' leaves.png), used by
scripts/trees.gd and assets/shaders/trees.gdshader. Transparent pixels are cut out (alpha scissor).

    row 0: leaf clusters for cards: broadleaf, pine fronds, birch, burnt twigs
    row 1: bark: broadleaf (grey-brown furrows), pine (red-brown plates), birch (white, black marks), burnt
    row 2: dense leaf fill for canopy blocks (tiles edge to edge, a ragged rim): broadleaf, pine, birch; a fern frond
    row 3: crops for the farm's field (outdoor step 8): wheat, young maize, sunflowers

    python3 art_source/scripts/make_trees.py
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "textures", "trees", "trees.png")
T = 64


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


LEAF = {   # shadow, dark, mid, light, tip
    "broad": ("2c4524", "3a5529", "4a6b35", "5e8040", "7a9a52"),
    "pine": ("1c3022", "24402b", "2f5234", "3d6640", "557a4e"),
    "birch": ("4a6230", "5e7a38", "77933f", "93ad4c", "b5c265"),
}


def tile(img, col, row):
    """A painter for one tile: put(x, y, colour) with y up from the tile's bottom."""
    def put(x, y, c):
        if 0 <= x < T and 0 <= y < T:
            img.putpixel((col * T + x, row * T + (T - 1 - y)), hexc(c) if isinstance(c, str) else c)
    return put


def cluster(put, rng, cols, n, radius, leaf_shapes, cx=32, cy=32):
    sh, dk, mid, lt, tip = cols
    for _ in range(n):
        a, r = rng.uniform(0, 6.283), rng.random() ** 0.5 * radius
        x, y = int(cx + r * math.cos(a)), int(cy + r * math.sin(a))
        up = y > cy + 2
        col = rng.choice((mid, lt, lt, tip) if up else (sh, dk, dk, mid))
        for dx, dy in rng.choice(leaf_shapes):
            put(x + dx, y + dy, col)


BROAD = (((0, 0), (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)), ((0, 0), (1, 0), (1, 1), (2, 1), (0, -1)))
SMALL = (((0, 0), (1, 0), (0, 1)), ((0, 0), (1, 1)), ((0, 0), (0, 1), (1, 1)))


def pine_fronds(put, rng, cols, dense=False):
    """Drooping branches of needles: a twig from the middle out to each side, needles hanging off it."""
    sh, dk, mid, lt, tip = cols
    if dense:   # (a dark mass of needles behind the fronds, so a block's faces look solid)
        for y in range(T):
            for x in range(T):
                put(x, y, rng.choice((sh, sh, dk)))
    rows = range(4, 62, 4) if dense else range(14, 54, 5)
    for y0 in rows:
        for side in (-1, 1):
            x, y = (rng.uniform(-30, 98) if dense else 32.0), float(y0)
            for k in range(rng.randint(22, 30)):
                x += side
                y -= 0.18 + k * 0.012
                X, Y = int(x), int(y)
                put(X % T if dense else X, Y, "3a2c20")
                for j in range(1, rng.randint(3, 6)):   # needles, hanging down and out
                    c = rng.choice((dk, mid, mid, lt) if j < 3 else (sh, dk))
                    put((X + side * (j // 2)) % T if dense else X + side * (j // 2), Y - j, c)
                    put((X - side) % T if dense else X - side, Y - j + 1, rng.choice((mid, lt, tip)))


def twigs(put, rng, dark, light, n=6):
    for _ in range(n):
        x, y = 32.0 + rng.uniform(-3, 3), 0.0
        dx = rng.uniform(-0.6, 0.6)
        while y < 62:
            put(int(x), int(y), dark if y < 24 else light)
            if y < 16:
                put(int(x) + 1, int(y), dark)
            y += 1
            x += dx
            if rng.random() < 0.08:
                dx = max(-1.0, min(1.0, dx + rng.uniform(-0.7, 0.7)))
            if x < 3 or x > 61:
                break


def bark(put, rng, base, dark, light, mode):
    for y in range(T):
        for x in range(T):
            put(x, y, rng.choice((base, base, base, light)) if rng.random() < 0.3 else base)
    if mode == "furrows":      # long wavy vertical furrows
        for _ in range(9):
            x = rng.uniform(0, T)
            for y in range(T):
                x += rng.uniform(-0.5, 0.5)
                put(int(x) % T, y, dark)
                if rng.random() < 0.5:
                    put((int(x) + 1) % T, y, dark)
    elif mode == "plates":     # flaky plates: dark cracks round lighter patches
        for _ in range(26):
            x0, y0 = rng.randrange(T), rng.randrange(T)
            w, h = rng.randint(3, 7), rng.randint(5, 10)
            for x in range(w):
                for y in range(h):
                    put((x0 + x) % T, (y0 + y) % T, light if 0 < x < w - 1 and 0 < y < h - 1 else dark)
    elif mode == "birch":      # white with black dashes across, darker at the bottom
        for _ in range(30):
            x0, y0 = rng.randrange(T), rng.randrange(T)
            for x in range(rng.randint(3, 11)):
                put((x0 + x) % T, y0, dark)
                if rng.random() < 0.4:
                    put((x0 + x) % T, (y0 + 1) % T, dark)
    elif mode == "burnt":      # charred: black blocks, grey ash cracks, a few deep ember-dark splits
        for _ in range(60):
            x0, y0 = rng.randrange(T), rng.randrange(T)
            for x in range(rng.randint(2, 6)):
                put((x0 + x) % T, y0, light)
        for _ in range(5):
            x = rng.uniform(0, T)
            for y in range(T):
                x += rng.uniform(-0.4, 0.4)
                put(int(x) % T, y, dark)


def dense(put, rng, cols, shapes):
    """Leaves edge to edge (wraps), so a block's faces look solid, with a few holes and a ragged rim."""
    sh, dk, mid, lt, tip = cols
    for y in range(T):
        for x in range(T):
            put(x, y, rng.choice((sh, dk)))
    for _ in range(900):
        x, y = rng.randrange(T), rng.randrange(T)
        col = rng.choice((dk, mid, mid, lt, lt, tip))
        for dx, dy in rng.choice(shapes):
            put((x + dx) % T, (y + dy) % T, col)
    for _ in range(14):   # holes
        x, y = rng.randrange(4, T - 4), rng.randrange(4, T - 4)
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            put(x + dx, y + dy, (0, 0, 0, 0))
    for x in range(T):    # ragged rim: leaves missing at the edges, so blocks don't read as sharp boxes
        for e in range(3):
            if rng.random() < 0.5 - e * 0.15:
                put(x, e, (0, 0, 0, 0)); put(x, T - 1 - e, (0, 0, 0, 0))
                put(e, x, (0, 0, 0, 0)); put(T - 1 - e, x, (0, 0, 0, 0))


def fern(put, rng):
    """One frond, from the bottom middle up to the top: a stem with leaflets off both sides, shorter toward the tip."""
    cols = ("2f4a26", "3d5e2e", "4f7536", "638a40", "7f9e4f")
    x = 32.0
    for y in range(2, 62):
        x += 0.04 * (y - 30) / 30
        put(int(x), y, "3a4f26")
        if y % 3 == 0:
            ln = int(14 * (1 - y / 70) + rng.randint(-1, 1))
            for side in (-1, 1):
                for k in range(1, ln):
                    yy = y + k // 3
                    put(int(x) + side * k, yy, rng.choice(cols[1:4] if k < ln - 2 else cols[2:]))
                    put(int(x) + side * k, yy + 1, rng.choice(cols[:3]))


def crop(put, rng, kind):
    """(Outdoor step 8) A clump of the farm's crops, seen from the side, ground to top (the card is the crop's height):
    wheat (golden stalks, bearded heads), young maize (broad arching leaves, a tassel) or sunflowers going over
    (big leaves, heavy heads drooping)."""
    if kind == "wheat":
        for _ in range(26):
            x0 = rng.uniform(2, 62)
            top = rng.randint(46, 58)
            lean = rng.uniform(-0.08, 0.08)
            for y in range(0, top):
                put(int(x0 + lean * y), y, rng.choice(("8a6f34", "a3853f", "a3853f")) if y < top * 0.5 else rng.choice(("a3853f", "b8994f")))
            for y in range(top, top + 8):   # the head: two grains wide, whiskers
                x = int(x0 + lean * y)
                put(x, y, rng.choice(("cdb066", "b8994f")))
                put(x + 1, y, rng.choice(("b8994f", "a3853f")))
                if y % 2 == 0:
                    put(x - 1, y + 1, "d9c27c")
                    put(x + 2, y + 1, "d9c27c")
            if rng.random() < 0.5:   # a leaf
                y = rng.randint(8, 30)
                for k in range(6):
                    put(int(x0 + lean * y) + k, y + k // 2, "8a7a3a")
    elif kind == "maize":
        for _ in range(4):
            x0 = rng.uniform(10, 54)
            top = rng.randint(52, 60)
            for y in range(0, top):
                put(int(x0), y, "5f7832")
                put(int(x0) + 1, y, "6f8a3c")
            for k in range(5):   # leaves arching out and down
                y = rng.randint(10, top - 8)
                side = rng.choice((-1, 1))
                ln = rng.randint(12, 20)
                for t in range(ln):
                    yy = y + int(6 * math.sin(math.pi * t / ln * 0.9)) - t // 5
                    c = rng.choice(("6f8a3c", "8aa04c", "5f7832"))
                    put(int(x0) + side * t, yy, c)
                    put(int(x0) + side * t, yy + 1, rng.choice(("8aa04c", "6f8a3c")))
            for k in range(5):   # the tassel
                put(int(x0) + k - 2, top + 1 + abs(k - 2), "c9b46a")
                put(int(x0), top + k, "b5a35a")
    else:
        for _ in range(3):
            x0 = rng.uniform(12, 52)
            top = rng.randint(44, 52)
            for y in range(0, top):
                put(int(x0), y, "4d5a2a")
                put(int(x0) + 1, y, "5d6a32")
            for k in range(4):   # big leaves
                y = rng.randint(8, top - 10)
                side = rng.choice((-1, 1))
                for t in range(1, 9):
                    for h in range(-(4 - abs(t - 4)) // 2, (4 - abs(t - 4)) // 2 + 2):
                        put(int(x0) + side * t, y + h - t // 3, rng.choice(("405a26", "4d6a2e", "5e7a38")))
            cx, cy = int(x0) + rng.choice((-3, 3)), top + 3   # the head, drooping (seen from the side: an oval)
            for dx in range(-7, 8):
                for dy in range(-5, 6):
                    d = (dx / 7.0) ** 2 + (dy / 5.0) ** 2
                    if d <= 1.0:
                        put(cx + dx, cy + dy, "4a3523" if d < 0.45 else rng.choice(("d1a52c", "b0861f", "d1a52c")))


def main():
    img = Image.new("RGBA", (T * 4, T * 4), (0, 0, 0, 0))
    rng = random.Random("trees")
    cluster(tile(img, 0, 0), rng, LEAF["broad"], 470, 29, BROAD)
    pine_fronds(tile(img, 1, 0), rng, LEAF["pine"])
    cluster(tile(img, 2, 0), rng, LEAF["birch"], 330, 28, SMALL)
    twigs(tile(img, 3, 0), rng, "1c1917", "2e2925", n=7)
    bark(tile(img, 0, 1), rng, "5f5547", "3f372e", "73695a", "furrows")
    bark(tile(img, 1, 1), rng, "6a4430", "3a2618", "865a40", "plates")
    bark(tile(img, 2, 1), rng, "d8d4c8", "2a2826", "eeebe2", "birch")
    bark(tile(img, 3, 1), rng, "221e1b", "0f0d0c", "4a4440", "burnt")
    dense(tile(img, 0, 2), rng, LEAF["broad"], BROAD)
    pine_fronds(tile(img, 1, 2), rng, LEAF["pine"], dense=True)
    dense(tile(img, 2, 2), rng, LEAF["birch"], SMALL)
    fern(tile(img, 3, 2), rng)
    crop(tile(img, 0, 3), rng, "wheat")
    crop(tile(img, 1, 3), rng, "maize")
    crop(tile(img, 2, 3), rng, "sunflower")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("tree textures written")


if __name__ == "__main__":
    main()
