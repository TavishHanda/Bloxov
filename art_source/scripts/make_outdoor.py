"""Bloxov Battlegrounds outdoor debris kit (World art 0.17, outdoor step 1; plan /mnt/project-files/notes/outdoor-plan.md).

The map's outside junk was 20 kinds of gray box. Each kind is now drawn as a real piece in three looks (b, c, d), mixed
over the map (owner 2026-10-18: "use a mix of all 3 ... i like the variation"). The generator (tools/gen_old_bloxov.py,
`debris_kind`) tags the gray boxes of every piece and picks its look; they still collide exactly as before, so cover and
AI paths don't change, but aren't drawn. It writes the pieces, grouped by map chunk, to art_source/outdoor/<chunk>.json
(Godot space, relative to the chunk's origin), and this script draws each chunk's pieces round their boxes into one model:

    python3 art_source/scripts/make_outdoor.py        -> assets/models/outdoor/<chunk>.glb, then re-run the generator

Kinds: ruin, wall, berm, rocks, rubble, container, truck, sandbags, barrier, tanktrap, drums, dumpster, crater, junk.
Textures: the building kit atlas (new kits dbr_*, appended to it).
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
from make_building import Builder, Canvas, Texture, cross, dot, no_bottom, norm, rot, uv_world, v_add, v_scale, v_sub  # noqa: E402

JSON_DIR = os.path.join(mb.ROOT, "art_source", "outdoor")
OUT_DIR = os.path.join(mb.ROOT, "assets", "models", "outdoor")

# ------------------------------------------------------------------------------------------------ colours + kits
mb.PALETTE.update({
    "grs": "6f8f4f", "grs_dk": "5e7c42", "grs_lt": "84a35d", "grs_dry": "9a9a5c",
    "dirt1": "6c5640", "dirt2": "5c4834", "dirt3": "7c654e", "dirt_dk": "54412e", "pebble": "857c6e",
    "ground": "789e5c", "earth1": "6e5b45", "earth2": "66543f", "earth3": "75614a",
    "scorch1": "4a433b", "scorch2": "413b34", "scorch3": "524a40",
    "gran": "5f5c57", "gran_dk": "4c4a46", "gran_lt": "726f69", "lichen": "7f8455", "moss": "5f7440",
    "slate1": "625d56", "slate2": "4f4b46", "slate_lt": "77716a",
    "cont_r": "7e3b2a", "cont_r_dk": "662f22", "cont_g": "4f5a3a", "cont_g_dk": "3f4a2e", "cont_b": "3f566b", "cont_b_dk": "324657",
    "burnt1": "3a3430", "burnt2": "2b2623", "ash": "6d6660",
    "hes_fab": "8f8268", "hes_fab_dk": "7b6f58", "hes_wire": "5a5a52",
    "cind": "77756f", "cind_dk": "62615c", "cind_j": "4f4e4a",
    "sb_tan": "a08c62", "sb_tan_dk": "8a7752", "sb_grn": "5f6440", "sb_grn_dk": "4d5234", "sb_gry": "8a877c", "sb_gry_dk": "6f6c63",
    "jb": "9c9a93", "jb_dk": "85837d", "jb_red": "8e3a2c", "jb_wht": "c2bdb0", "hz_y": "c49a2a",
    "drum_b": "3d5470", "drum_b_dk": "2f4259", "drum_o": "56603a", "drum_o_dk": "454e2d",
    "dmp_g": "3f5a43", "dmp_g_dk": "324835", "dmp_b": "3d4f66", "dmp_b_dk": "2f3e52",
    "trk_o": "4f5838", "trk_o_dk": "3f472c", "trk_c": "7a7556", "trk_c_dk": "666246",
    "rail_r": "5a3b2b", "rail_r_dk": "483023", "paper": "b9b2a0",
    # bushes (step 2, owner: "add some big bushes"): leafy green, a dark evergreen, and one in flower
    "lf1": "4a6b35", "lf1_dk": "3a5529", "lf1_lt": "5e8040", "lf1_sh": "2c4524",
    "lf2": "3f5a37", "lf2_dk": "2f4529", "lf2_lt": "4f6b42", "lf2_sh": "263a22",
    "lf3": "4f6e38", "lf3_dk": "3e5a2b", "lf3_lt": "638545",
    # the town square (World art 0.17): setts, fountain water, awnings
    "sett1": "7c766c", "sett2": "706a61", "sett3": "857f74", "sett_j": "524d46", "sett_dk": "625c53",
    "wat1": "4c6466", "wat2": "435a5c", "wat_lt": "5d777a", "scum": "56634a",
    "awn_r": "8f3b32", "awn_g": "476247", "awn_b": "3e5571", "awn_w": "c9c0ab", "blossom": "d8d0c2", "blossom2": "c9a4b8",
})


def k_grass(rng):
    c = Canvas(64, 64, "grs")
    c.noise(0, 0, 64, 64, ["grs_dk", "grs_lt"], 0.35, rng)
    c.blotch(["grs_dry"], 4, rng, size=(2, 4))
    c.blotch(["grs_dk"], 8, rng, size=(2, 5))
    return c


def k_dirt(rng):
    """(round 2, owner: noisy: no bright specks, softer grain)"""
    c = Canvas(64, 64, "dirt1")
    c.noise(0, 0, 64, 64, ["dirt2", "dirt3"], 0.14, rng)
    c.blotch(["dirt2"], 8, rng, size=(4, 9))
    c.blotch(["dirt3"], 5, rng, size=(3, 7))
    for _ in range(10):
        x, y = rng.randrange(64), rng.randrange(64)
        c.rect(x, y, x + 2, y + 1, "pebble")
    return c


def k_scorch(rng):
    """Scorched earth inside a fresh shell hole."""
    c = Canvas(64, 64, "scorch1")
    c.noise(0, 0, 64, 64, ["scorch2", "scorch3"], 0.1, rng)
    c.blotch(["scorch2"], 6, rng, size=(5, 11))
    c.blotch(["earth2"], 3, rng, size=(4, 8))
    return c


def k_earth(rng):
    """Bare earth on the steep sides of banks and crater rims: calm, so it sits next to the plain ground."""
    c = Canvas(64, 64, "earth1")
    c.noise(0, 0, 64, 64, ["earth2", "earth3"], 0.1, rng)
    c.blotch(["earth2"], 6, rng, size=(5, 11))
    c.blotch(["earth3"], 4, rng, size=(4, 9))
    return c


def k_ruts(rng):
    """Bulldozed dirt: tyre-tread ridges across it."""
    c = k_dirt(rng)
    for y in range(0, 64, 4):
        c.rect(0, y, 64, y + 1, "dirt_dk")
        c.rect(0, y + 2, 64, y + 3, "dirt3")
    c.blotch(["dirt2"], 10, rng, size=(2, 6))
    return c


def k_granite(rng):
    c = Canvas(64, 64, "gran")
    c.noise(0, 0, 64, 64, ["gran_dk", "gran_lt"], 0.12, rng)
    c.blotch(["gran_lt"], 6, rng, size=(5, 10))
    c.blotch(["gran_dk"], 6, rng, size=(4, 9))
    c.blotch(["lichen"], 3, rng, size=(4, 7))
    return c


def k_slate(rng):
    """Layered rock: horizontal strata."""
    c = Canvas(64, 64, "slate1")
    y = 0
    while y < 64:
        h = rng.choice((3, 4, 5, 6))
        c.rect(0, y, 64, min(64, y + h), rng.choice(("slate1", "slate2", "slate_lt")))
        c.rect(0, y, 64, y + 1, "slate2")
        y += h
    c.noise(0, 0, 64, 64, ["slate2", "slate_lt"], 0.06, rng)
    return c


def k_leaf(base, dk, lt, sh, flowers=()):
    """Leaves: clumps of light-catching leaves over dark gaps, pixel-crisp (64 px for 2 m like the rest of the kit)."""
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [dk, lt], 0.3, rng)
        c.blotch([sh], 22, rng, size=(1, 3))       # gaps into the bush
        for _ in range(90):                          # single leaves: a lit pixel over a dark one
            x, y = rng.randrange(64), rng.randrange(64)
            c.put(x, y, lt)
            c.put(x, (y - 1) % 64, dk)
        for _ in range(40 if flowers else 0):
            x, y = rng.randrange(63), rng.randrange(63)
            col = rng.choice(flowers)
            c.rect(x, y, x + 2, y + 1, col)
        return c
    return paint


def k_setts(rng):
    """Granite setts in rows (8 x 6 px stones, staggered), some darker, a few cracked or missing."""
    c = Canvas(64, 64, "sett_j")
    for row in range(0, 64, 6):
        off = 4 if (row // 6) % 2 else 0
        for col in range(-8, 64, 8):
            x0 = col + off
            stone = rng.choice(("sett1", "sett2", "sett3", "sett1", "sett_dk"))
            c.rect(max(0, x0), row, min(64, x0 + 7), min(64, row + 5), stone)
    c.noise(0, 0, 64, 64, ["sett_dk", "sett3"], 0.12, rng)
    c.blotch(["sett_j"], 5, rng, size=(1, 3))
    return c


def k_water(rng):
    c = Canvas(64, 64, "wat1")
    c.noise(0, 0, 64, 64, ["wat2", "wat_lt"], 0.15, rng)
    c.blotch(["scum"], 6, rng, size=(3, 7))
    for _ in range(30):
        x, y = rng.randrange(62), rng.randrange(64)
        c.rect(x, y, x + 3, y + 1, "wat_lt")
    return c


def k_mossrock(rng):
    c = k_granite(rng)
    c.blotch(["moss", "grs_dk"], 10, rng, area=(0, 40, 64, 64), size=(3, 7))
    return c


def k_corr(base, dk):
    """Corrugated container steel: a rib every 4 px, rust along the bottom."""
    def paint(rng):
        c = Canvas(64, 64, base)
        for x in range(0, 64, 4):
            c.rect(x, 0, x + 1, 64, dk)
        c.blotch(["rust"], 8, rng, area=(0, 0, 64, 20), size=(2, 5))
        c.blotch(["rust", dk], 6, rng, size=(1, 3))
        c.noise(0, 0, 64, 64, [dk], 0.05, rng)
        return c
    return paint


def k_paint(base, dk, rust=6):
    """Painted steel, chipped and rusty."""
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [dk], 0.1, rng)
        c.blotch(["rust"], rust, rng, size=(1, 4))
        c.blotch([dk], 6, rng, size=(2, 5))
        return c
    return paint


def k_drum(base, dk):
    def paint(rng):
        c = k_paint(base, dk)(rng)
        for y in (20, 42):
            c.rect(0, y, 64, y + 2, dk)
        return c
    return paint


def k_burnt(rng):
    c = Canvas(64, 64, "burnt1")
    for x in range(0, 64, 4):
        c.rect(x, 0, x + 1, 64, "burnt2")
    c.blotch(["rust"], 14, rng, size=(2, 6))
    c.blotch(["ash"], 8, rng, size=(2, 5))
    return c


def k_hesco(rng):
    """Earth-filled wire-mesh barrier: fabric liner behind a steel mesh."""
    c = Canvas(64, 64, "hes_fab")
    c.noise(0, 0, 64, 64, ["hes_fab_dk"], 0.25, rng)
    for k in range(0, 64, 8):
        c.rect(k, 0, k + 1, 64, "hes_wire")
        c.rect(0, k, 64, k + 1, "hes_wire")
    c.blotch(["dirt2"], 5, rng, area=(0, 0, 64, 14), size=(2, 5))
    return c


def k_cinder(rng):
    c = Canvas(64, 64, "cind_j")
    for row in range(8):
        off = 8 if row % 2 else 0
        for x in range(-16 + off, 64, 16):
            c.rect(max(0, x + 1), row * 8 + 1, min(64, x + 16), row * 8 + 8, rng.choice(("cind", "cind", "cind_dk")))
    c.noise(0, 0, 64, 64, ["cind_dk", "cind_j"], 0.1, rng)
    c.blotch(["burnt1"], 5, rng, size=(2, 6))
    return c


def k_bags(base, dk):
    def paint(rng):
        c = Canvas(64, 64, base)
        c.noise(0, 0, 64, 64, [dk], 0.25, rng)
        for y in range(0, 64, 8):
            c.rect(0, y, 64, y + 1, dk)
        c.blotch(["dirt2"], 6, rng, size=(2, 5))
        return c
    return paint


def k_conc(rng):
    c = Canvas(64, 64, "jb")
    c.noise(0, 0, 64, 64, ["jb_dk"], 0.08, rng)
    c.blotch(["jb_dk"], 8, rng, size=(2, 5))
    c.blotch(["dirt2"], 4, rng, area=(0, 0, 64, 10), size=(2, 4))
    return c


def k_stripes(a, b_):
    def paint(rng):
        c = Canvas(64, 64, a)
        for y in range(64):
            for x in range(64):
                if ((x + y) // 8) % 2:
                    c.put(x, y, b_)
        c.noise(0, 0, 64, 64, ["jb_dk"], 0.06, rng)
        c.blotch(["jb", "jb_dk"], 10, rng, size=(2, 5))   # chipped paint
        return c
    return paint


def k_canvas(rng):
    c = Canvas(64, 64, "trk_c")
    c.noise(0, 0, 64, 64, ["trk_c_dk"], 0.2, rng)
    c.blotch(["trk_c_dk", "dirt2"], 8, rng, size=(2, 6))
    return c


def k_tyre(rng):
    c = Canvas(16, 16, "black")
    for x in range(0, 16, 3):
        c.rect(x, 0, x + 1, 16, "iron_dark")
    return c


mb.KIT.update({
    "dbr_grass": k_grass, "dbr_dirt": k_dirt, "dbr_ruts": k_ruts, "dbr_granite": k_granite, "dbr_slate": k_slate,
    "dbr_mossrock": k_mossrock, "dbr_cont_r": k_corr("cont_r", "cont_r_dk"), "dbr_cont_g": k_paint("cont_g", "cont_g_dk", 5),
    "dbr_cont_b": k_corr("cont_b", "cont_b_dk"), "dbr_burnt": k_burnt, "dbr_hesco": k_hesco, "dbr_cinder": k_cinder,
    "dbr_bag_tan": k_bags("sb_tan", "sb_tan_dk"), "dbr_bag_grn": k_bags("sb_grn", "sb_grn_dk"),
    "dbr_bag_gry": k_bags("sb_gry", "sb_gry_dk"), "dbr_conc": k_conc, "dbr_redwhite": k_stripes("jb_wht", "jb_red"),
    "dbr_hazard": k_stripes("hz_y", "black"), "dbr_drum_b": k_drum("drum_b", "drum_b_dk"),
    "dbr_drum_o": k_drum("drum_o", "drum_o_dk"), "dbr_dmp_g": k_paint("dmp_g", "dmp_g_dk"),
    "dbr_dmp_b": k_paint("dmp_b", "dmp_b_dk"), "dbr_trk_o": k_paint("trk_o", "trk_o_dk", 4), "dbr_canvas": k_canvas,
    "dbr_tyre": k_tyre, "dbr_rail": k_paint("rail_r", "rail_r_dk", 10), "dbr_paper": mb.paint_flat("paper"),
    # (round 2: banks and crater rims are shaped from the ground and coloured like it, so they blend in; the ground's
    # own look comes in outdoor step 2 and these follow it)
    "dbr_ground": mb.paint_flat("ground"), "dbr_earth": k_earth, "dbr_scorch": k_scorch,
    "dbr_leaf_b": k_leaf("lf1", "lf1_dk", "lf1_lt", "lf1_sh"), "dbr_leaf_c": k_leaf("lf2", "lf2_dk", "lf2_lt", "lf2_sh"),
    "dbr_leaf_d": k_leaf("lf3", "lf3_dk", "lf3_lt", "lf1_sh", flowers=("blossom", "blossom2")),
    "dbr_setts": k_setts, "dbr_water": k_water, "awn_r_flat": mb.paint_flat("awn_r"), "hz_flat": mb.paint_flat("hz_y"),
    "dbr_awn_r": k_stripes("awn_w", "awn_r"), "dbr_awn_g": k_stripes("awn_w", "awn_g"), "dbr_awn_b": k_stripes("awn_w", "awn_b"),
})


# ------------------------------------------------------------------------------------------------ the ground
# The ground's height grid (tools/gen_old_bloxov.py writes art_source/outdoor/terrain.json) and the chunk's origin, so
# pieces fit the hills: banks and crater rims follow it, loose bits lie on it.
TERRAIN = {}
ORIGIN = [0.0, 0.0]


def ground(x, z):
    """The ground's height under chunk point (x, z) (BoxMap's triangle split: north-west to south-east)."""
    import bisect
    xs, zs, H = TERRAIN["xs"], TERRAIN["zs"], TERRAIN["h"]
    wx, wz = x + ORIGIN[0], z + ORIGIN[1]
    i = min(max(bisect.bisect_right(xs, wx) - 1, 0), len(xs) - 2)
    j = min(max(bisect.bisect_right(zs, wz) - 1, 0), len(zs) - 2)
    u = min(max((wx - xs[i]) / (xs[i + 1] - xs[i]), 0.0), 1.0)
    v = min(max((wz - zs[j]) / (zs[j + 1] - zs[j]), 0.0), 1.0)
    ha, hb, hc, hd = H[j][i], H[j][i + 1], H[j + 1][i], H[j + 1][i + 1]
    return ha + u * (hb - ha) + v * (hd - hb) if u >= v else ha + v * (hc - ha) + u * (hd - hc)


def on_ground(p, lift=0.0):
    return (p[0], ground(p[0], p[2]) + lift, p[2])


def bits(b, centre, spread, n, rng, mats, size=(0.22, 0.07, 0.11)):
    """Broken bits lying on the ground round a point."""
    for _ in range(n):
        p = (centre[0] + rng.uniform(-spread, spread), 0.0, centre[2] + rng.uniform(-spread, spread))
        mb.rubble_chunk(b, on_ground(p, size[1] / 2 - 0.01), size, rng, mats)


# Banks and crater rims are part of the ground: their "ground" material becomes the ground's shader material
# (assets/materials/ground.tres, outdoor step 2) on import (tools/building_import.gd), so they match it exactly.
GROUND = "ground"


# ------------------------------------------------------------------------------------------------ helpers
def flat(mat, tile=2.0):
    return lambda n, m, q: (mat, uv_world(tile))


class Frame:
    """A piece's own frame: origin on the ground under it (world point), turned by yaw. Points and boxes are given in it."""

    def __init__(self, b, at, yaw):
        self.b, self.at, self.yaw = b, at, yaw

    def p(self, x, y, z):
        return v_add(rot((x, y, z), self.yaw, 0.0), self.at)

    def box(self, c, size, yaw=0.0, pitch=0.0, style=None):
        self.b.box(self.p(*c), size, yaw=self.yaw + yaw, pitch=pitch, style=style)


def frame_of(b, box):
    """The frame of a gray box: on its bottom face's middle, turned like it."""
    (x, y, z), s = box["pos"], box["size"]
    return Frame(b, (x, y - s[1] / 2, z), box["yaw"])


def tri(b, a, c, d, mat, centre, tile=2.0):
    n = norm(cross(v_sub(c, a), v_sub(d, a)))
    if dot(n, v_sub(a, centre)) < 0:
        n = v_scale(n, -1)
    b.poly([a, c, d], n, mat, uv_world(tile))


def rock(b, c, size, yaw, rng, mat, top=None, jitter=0.18, chamfer=0.32, taper=0.78):
    """A faceted boulder filling a box (centre c, size, yaw): a chamfered box with every corner nudged, the top a bit
    narrower, the bottom flat."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    ch = chamfer * min(size)
    pts = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                t = taper if sy > 0 else 1.0
                base = {"x": (sx * hx, sy * (hy - ch), sz * (hz - ch)),
                        "y": (sx * (hx - ch), sy * hy, sz * (hz - ch)),
                        "z": (sx * (hx - ch), sy * (hy - ch), sz * hz)}
                for k, p in base.items():
                    j = (rng.uniform(-jitter, jitter) * size[0], rng.uniform(-jitter, jitter) * size[1] * (0.4 if sy < 0 else 1),
                         rng.uniform(-jitter, jitter) * size[2])
                    q = (p[0] * t + j[0], -hy if sy < 0 else p[1] + j[1], p[2] * t + j[2])
                    pts[(sx, sy, sz, k)] = v_add(rot(q, yaw, 0.0), c)

    def face(q, m):
        tri(b, q[0], q[1], q[2], m, c)
        tri(b, q[0], q[2], q[3], m, c)
    for axis in "xyz":
        for s in (-1, 1):
            if axis == "y" and s < 0:
                continue
            cs = []
            for sa in (-1, 1):
                for sb in (-1, 1):
                    cs.append((s, sa, sb) if axis == "x" else (sa, s, sb) if axis == "y" else (sa, sb, s))
            face([pts[cs[0] + (axis,)], pts[cs[1] + (axis,)], pts[cs[3] + (axis,)], pts[cs[2] + (axis,)]],
                 top if (top and axis == "y") else mat)
    for a1, a2 in (("x", "y"), ("y", "z"), ("x", "z")):
        free = ({"x", "y", "z"} - {a1, a2}).pop()
        for s1 in (-1, 1):
            for s2 in (-1, 1):
                if (a1 == "y" and s1 < 0) or (a2 == "y" and s2 < 0):
                    continue
                ks = []
                for sf in (-1, 1):
                    dd = {a1: s1, a2: s2, free: sf}
                    ks.append((dd["x"], dd["y"], dd["z"]))
                face([pts[ks[0] + (a1,)], pts[ks[1] + (a1,)], pts[ks[1] + (a2,)], pts[ks[0] + (a2,)]], mat)
    for sx in (-1, 1):
        for sz in (-1, 1):
            tri(b, pts[(sx, 1, sz, "x")], pts[(sx, 1, sz, "y")], pts[(sx, 1, sz, "z")], mat, c)


def cyl(b, c, r, h, mat, sides=12, axis="y", yaw=0.0, pitch=0.0, caps=True, cap_mat=None, tile=1.0):
    """A cylinder centred at c along its own `axis`, then turned by yaw / pitch."""
    def P(u, v, w):
        p = (u, w, v) if axis == "y" else (w, u, v) if axis == "x" else (u, v, w)
        return v_add(rot(p, yaw, pitch), c)
    ring = [(r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        a, e = ring[k], ring[(k + 1) % sides]
        q = [P(a[0], a[1], -h / 2), P(e[0], e[1], -h / 2), P(e[0], e[1], h / 2), P(a[0], a[1], h / 2)]
        n = v_sub(P((a[0] + e[0]) / 2, (a[1] + e[1]) / 2, 0), c)
        b.poly(q, norm(n), mat, uv_world(tile))
    if caps:
        for s in (-1, 1):
            b.poly([P(x, y, s * h / 2) for x, y in ring], norm(v_sub(P(0, 0, s), c)), cap_mat or mat, uv_world(tile))


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def local_normal(n, yaw):
    return rot(n, -yaw, 0.0)


# ------------------------------------------------------------------------------------------------ walls
WALL_SKIN = {"b": "house_brick", "c": "dbr_cinder", "d": "ch_fieldstone"}


def wall_run(b, box, skin, rng, top_mat=None, rebar=False, posts=False, extra_t=0.0, col_w=0.25):
    """A broken wall over one gray wall box: columns `col_w` wide whose tops step up and down (broken courses), sunk a
    little into the ground (hills), never lower than the box (it collides to its top)."""
    s = box["size"]
    along_x = s[0] >= s[2]
    length, t = (s[0], s[2]) if along_x else (s[2], s[0])
    f = frame_of(b, box)
    n = max(1, round(length / col_w))
    w = length / n
    h = s[1] + rng.uniform(0.0, 0.25)
    tm = top_mat or "rubble_core"
    yaw = f.yaw

    def style(nn, m, q):
        if nn[1] < -0.7:
            return None
        if nn[1] > 0.7:
            return tm, uv_world(1.0)
        ln = local_normal(nn, yaw)
        side = abs(ln[2]) > 0.7 if along_x else abs(ln[0]) > 0.7
        return (skin, uv_world(2.0)) if side else ("rubble_core", uv_world(1.0))
    for i in range(n):
        h = max(s[1], min(s[1] + 0.45, h + rng.choice((-1, 0, 0, 1)) * rng.uniform(0.08, 0.3)))
        a = -length / 2 + (i + 0.5) * w
        size = (w, h + 0.3, t + extra_t) if along_x else (t + extra_t, h + 0.3, w)
        c = (a, (h - 0.3) / 2, 0.0) if along_x else (0.0, (h - 0.3) / 2, a)
        f.box(c, size, style=style)
        if rebar and rng.random() < 0.3:
            for dz in (-0.1, 0.1):
                ln = rng.uniform(0.3, 0.7)
                c2 = (a, h + ln / 2 - 0.05, dz) if along_x else (dz, h + ln / 2 - 0.05, a)
                f.box(c2, (0.03, ln, 0.03), pitch=rng.uniform(-25, 25), style=no_bottom("trim_dark", 1.0))
    if posts:
        for k in range(int(length // 2.6) + 1):
            a = -length / 2 + 0.2 + k * 2.6
            if a > length / 2 - 0.1:
                break
            c = (a, (s[1] - 0.3) / 2, 0.0) if along_x else (0.0, (s[1] - 0.3) / 2, a)
            f.box(c, (0.32, s[1] + 0.3, t + 0.06) if along_x else (t + 0.06, s[1] + 0.3, 0.32), style=no_bottom("concrete", 2.0))
    for _ in range(max(2, int(length))):     # broken bits at its foot (picture only: you walk over them)
        a, side = rng.uniform(-length / 2, length / 2), rng.choice((-1, 1)) * rng.uniform(t / 2 + 0.2, t / 2 + 1.2)
        c = (a, 0.0, side) if along_x else (side, 0.0, a)
        mb.rubble_chunk(b, on_ground(f.p(*c), 0.03), (0.22, 0.07, 0.11), rng, (skin, "rubble_core"))


def is_wall(box, low=1.4):
    s = box["size"]
    return s[1] >= low and min(s[0], s[2]) <= 0.5 and abs(box["pitch"]) < 1


def draw_wall(b, piece, rng):
    skin = WALL_SKIN[piece["look"]]
    look = piece["look"]
    for box in piece["boxes"]:
        if is_wall(box):
            wall_run(b, box, skin, rng, top_mat=skin if look != "c" else None, rebar=look == "c", posts=look == "c",
                     extra_t=0.12 if look == "d" else 0.0, col_w=0.33 if look == "d" else 0.25)
        else:   # a fallen lump of it
            s = box["size"]
            mb.rubble_chunk(b, tuple(box["pos"]), (s[0] * 0.95, s[1] * 0.95, s[2] * 0.95), rng, (skin, skin, "rubble_core"), box["yaw"])


# ------------------------------------------------------------------------------------------------ ruined houses
def draped(b, f, x0, x1, z0, z1, lift, mat, step=1.0, lip=0.15, tile=2.0):
    """A thin slab over the frame's rectangle that follows the ground `lift` above it, its edge dropping under it."""
    nx, nz = max(1, round((x1 - x0) / step)), max(1, round((z1 - z0) / step))
    P = [[None] * (nx + 1) for _ in range(nz + 1)]
    for j in range(nz + 1):
        for i in range(nx + 1):
            p = f.p(x0 + (x1 - x0) * i / nx, 0.0, z0 + (z1 - z0) * j / nz)
            P[j][i] = on_ground(p, lift)
    for j in range(nz):
        for i in range(nx):
            q = [P[j][i], P[j][i + 1], P[j + 1][i + 1], P[j + 1][i]]
            for a, c, d in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                n = norm(cross(v_sub(c, a), v_sub(d, a)))
                if n[1] < 0:
                    n = v_scale(n, -1)
                b.poly([a, c, d], n, mat, uv_world(tile))
    edge = [P[0][i] for i in range(nx + 1)] + [P[j][nx] for j in range(1, nz + 1)] + \
           [P[nz][i] for i in range(nx - 1, -1, -1)] + [P[j][0] for j in range(nz - 1, 0, -1)]
    mid = f.p((x0 + x1) / 2, 0.0, (z0 + z1) / 2)
    for a, c in zip(edge, edge[1:] + edge[:1]):
        q = [a, c, (c[0], c[1] - lift - lip, c[2]), (a[0], a[1] - lift - lip, a[2])]
        n = norm((((a[0] + c[0]) / 2) - mid[0], 0.0, ((a[2] + c[2]) / 2) - mid[2]))
        b.poly(q, n, mat, uv_world(tile))


def draw_ruin(b, piece, rng):
    """A shelled house (round 2, owner: "walls just standing straight up, it makes no sense"): its floor slab on the
    ground, a corner still standing, stubs of the rest, heaps of its own fallen wall inside, charred roof timbers."""
    look = piece["look"]
    skin = WALL_SKIN[look]
    for box in piece["boxes"]:
        s = box["size"]
        if not box["solid"] and s[1] <= 0.3:            # the floor slab
            f = frame_of(b, box)
            draped(b, f, -s[0] / 2, s[0] / 2, -s[2] / 2, s[2] / 2, 0.08, "concrete", tile=2.0)
            cx, cz = box["pos"][0], box["pos"][2]
            bits(b, (cx, 0, cz), min(s[0], s[2]) / 2 - 0.4, 14, rng, (skin, "rubble_core"))
            for _ in range(rng.randint(2, 3)):         # roof timbers, burnt
                b.box(on_ground((cx + rng.uniform(-1.5, 1.5), 0, cz + rng.uniform(-1.2, 1.2)), rng.uniform(0.25, 0.6)),
                      (0.16, 0.18, rng.uniform(2.4, 3.6)), yaw=rng.uniform(0, 180), pitch=rng.uniform(-18, 18),
                      style=flat(rng.choice(("wood_dark", "dbr_burnt")), 1.0))
            for _ in range(4):
                b.box(on_ground((cx + rng.uniform(-2, 2), 0, cz + rng.uniform(-1.6, 1.6)), rng.uniform(0.15, 0.4)), (0.9, 0.05, 0.6),
                      yaw=rng.uniform(0, 180), pitch=rng.uniform(-20, 20), style=flat("roof_clay", 1.0))
        elif min(s[0], s[2]) <= 0.45:                   # a wall, standing or knocked down to a stub
            wall_run(b, box, skin, rng, top_mat=skin if look != "c" else None, rebar=look == "c",
                     extra_t=0.12 if look == "d" else 0.0, col_w=0.33 if look == "d" else 0.25)
        elif s[1] > 2.5:                                 # the chimney stack
            f = frame_of(b, box)
            f.box((0, (s[1] - 0.3) / 2, 0), (s[0], s[1] + 0.3, s[2]), style=no_bottom("house_brick", 2.0))
            for k in range(3):
                f.box((rng.uniform(-0.25, 0.25), s[1] + 0.08, rng.uniform(-0.2, 0.2)), (0.3, 0.16, 0.25), yaw=rng.uniform(0, 30),
                      style=no_bottom("house_brick", 1.0))
        else:                                            # a heap of fallen wall
            mb.rubble_chunk(b, tuple(box["pos"]), tuple(v * 0.95 for v in s), rng, (skin, skin, "rubble_core"), box["yaw"])


# ------------------------------------------------------------------------------------------------ rubble piles
RUBBLE_MATS = {"b": ("dbr_conc", "dbr_conc", "rubble_core"), "c": ("house_brick", "house_brick", "rubble_core"),
               "d": ("house_stone", "dbr_conc", "rubble_core")}
RUBBLE_WALL = {"b": "dbr_cinder", "c": "house_brick", "d": "house_stone"}


def draw_rubble(b, piece, rng):
    look = piece["look"]
    mats = RUBBLE_MATS[look]
    for box in piece["boxes"]:
        s = box["size"]
        if is_wall(box, 0.8):
            wall_run(b, box, RUBBLE_WALL[look], rng, top_mat=RUBBLE_WALL[look] if look != "b" else None, rebar=look == "b")
        else:
            mb.rubble_chunk(b, tuple(box["pos"]), tuple(v * 0.95 for v in s), rng, mats, box["yaw"])
    cx = sum(bx["pos"][0] for bx in piece["boxes"]) / len(piece["boxes"])
    cz = sum(bx["pos"][2] for bx in piece["boxes"]) / len(piece["boxes"])
    bits(b, (cx, 0.0, cz), 3.0, 10, rng, (mats[0], "rubble_core"))
    if look == "d":   # a house came down: roof timbers and tiles in it
        for _ in range(3):
            b.box(on_ground((cx + rng.uniform(-1.5, 1.5), 0, cz + rng.uniform(-1.5, 1.5)), rng.uniform(0.3, 0.7)),
                  (0.16, 0.16, rng.uniform(2.0, 3.2)), yaw=rng.uniform(0, 180), pitch=rng.uniform(-20, 20), style=flat("wood_dark", 1.0))
        for _ in range(4):
            b.box(on_ground((cx + rng.uniform(-2, 2), 0, cz + rng.uniform(-2, 2)), rng.uniform(0.15, 0.5)), (0.9, 0.05, 0.6),
                  yaw=rng.uniform(0, 180), pitch=rng.uniform(-20, 20), style=flat("roof_clay", 1.0))


# ------------------------------------------------------------------------------------------------ berms
def draw_berm(b, piece, rng):
    boxes = piece["boxes"]
    look = piece["look"]
    if look == "d":   # earth-filled wire-mesh barriers filling each box
        for box in boxes:
            s, f = box["size"], frame_of(b, box)
            nx, nz = max(1, round(s[0] / 1.1)), 2
            for i in range(nx):
                for k in range(nz):
                    hh = s[1] - rng.uniform(0.0, 0.08)
                    c = (-s[0] / 2 + (i + 0.5) * s[0] / nx, (hh - 0.3) / 2, -s[2] / 2 + (k + 0.5) * s[2] / nz)
                    f.box(c, (s[0] / nx - 0.02, hh + 0.3, s[2] / nz - 0.02), style=lambda nn, m, q: None if nn[1] < -0.7 else
                          (("dbr_dirt", uv_world(2.0)) if nn[1] > 0.7 else ("dbr_hesco", uv_world(1.1))))
        return
    earth_bank(b, boxes, rng)


def earth_bank(b, boxes, rng, fall=2.2):
    """A bulldozed bank over its gray boxes, shaped from the ground (round 2, owner: the banks didn't sit on the
    hills and looked like loaves): it rises out of the ground round its boxes, its top just over theirs (they collide),
    and its edges dip under the ground, so there's no seam. Plain ground colour where it's gentle, bare earth on the
    steep sides."""
    mid = boxes[len(boxes) // 2]
    yaw = mid["yaw"]
    ox, oz = mid["pos"][0], mid["pos"][2]
    rects = []
    for box in boxes:   # each box in the middle one's frame: (x0, x1, z0, z1, top)
        l = rot((box["pos"][0] - ox, 0.0, box["pos"][2] - oz), -yaw, 0.0)
        s_ = box["size"]
        rects.append((l[0] - s_[0] / 2, l[0] + s_[0] / 2, l[2] - s_[2] / 2, l[2] + s_[2] / 2, box["pos"][1] + s_[1] / 2))
    x0, x1 = min(r[0] for r in rects) - fall - 0.5, max(r[1] for r in rects) + fall + 0.5
    z0, z1 = min(r[2] for r in rects) - fall - 0.5, max(r[3] for r in rects) + fall + 0.5
    ph = (rng.uniform(0, 6), rng.uniform(0, 6))

    def world(x, z):
        p = rot((x, 0.0, z), yaw, 0.0)
        return ox + p[0], oz + p[2]

    def height(x, z):
        wx, wz = world(x, z)
        g = ground(wx, wz)
        best = g - 0.3
        for rx0, rx1, rz0, rz1, top in rects:
            dx = max(rx0 - x, 0.0, x - rx1)
            dz = max(rz0 - z, 0.0, z - rz1)
            d = math.hypot(dx, dz)
            edge = min(x - rx0, rx1 - x, z - rz0, rz1 - z)
            y = top + 0.1 * smooth01(edge / 0.8) if d == 0 else top - (top - g + 0.25) * smooth01(d / fall)
            best = max(best, y)
        best += 0.05 * math.sin(x * 1.3 + ph[0]) * math.sin(z * 1.9 + ph[1])
        return (best if best > g + 0.03 else g - 0.2), g
    nx, nz = max(4, int((x1 - x0) / 0.5)), max(4, int((z1 - z0) / 0.5))
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    zs = [z0 + (z1 - z0) * j / nz for j in range(nz + 1)]
    H = [[height(x, z) for x in xs] for z in zs]
    for j in range(nz):
        for i in range(nx):
            hs = [H[j][i], H[j][i + 1], H[j + 1][i + 1], H[j + 1][i]]
            if all(h <= g + 0.0 for h, g in hs):
                continue
            q = [(xs[i], hs[0][0], zs[j]), (xs[i + 1], hs[1][0], zs[j]), (xs[i + 1], hs[2][0], zs[j + 1]), (xs[i], hs[3][0], zs[j + 1])]
            q = [(world(p[0], p[2])[0], p[1], world(p[0], p[2])[1]) for p in q]
            qn = norm(cross(v_sub(q[2], q[0]), v_sub(q[3], q[1])))   # (one colour per cell: no zigzag edges)
            mat = GROUND   # (step 2: drawn by the ground's own shader, slopes and all; see GROUND)
            for a, c, d in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                n = norm(cross(v_sub(c, a), v_sub(d, a)))
                if n[1] < 0:
                    n = v_scale(n, -1)
                b.poly([a, c, d], n, mat, uv_world(2.0))
    for _ in range(5):   # a few stones at its foot
        sz = rng.uniform(0.2, 0.45)
        lx, lz = rng.uniform(x0 + 1.0, x1 - 1.0), rng.choice((z0 + 0.5, z1 - 0.5)) + rng.uniform(-0.3, 0.3)
        wx, wz = world(lx, lz)
        rock(b, (wx, ground(wx, wz) + sz * 0.3, wz), (sz * 1.3, sz, sz), rng.uniform(0, 180), rng, "dbr_granite")


# ------------------------------------------------------------------------------------------------ rocks
def draw_rocks(b, piece, rng):
    look = piece["look"]
    for box in piece["boxes"]:
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        if look == "b":
            rock(b, c, s, yaw, rng, "dbr_granite")
        elif look == "c":   # layered slate: stacked slabs, each a bit smaller
            n = max(2, min(4, round(s[1] / 0.55)))
            y0 = c[1] - s[1] / 2
            for k in range(n):
                h = s[1] / n
                k_ = 1.0 - 0.12 * k
                rock(b, (c[0], y0 + (k + 0.5) * h, c[2]), (s[0] * k_ * 1.04, h + 0.06, s[2] * k_ * 1.04), yaw + rng.uniform(-8, 8),
                     rng, "dbr_slate", jitter=0.05, chamfer=0.12, taper=0.95)
        else:
            rock(b, c, (s[0] * 1.05, s[1], s[2] * 1.05), yaw, rng, "dbr_mossrock", jitter=0.12, chamfer=0.42)


# ------------------------------------------------------------------------------------------------ bushes
def draw_bush(b, piece, rng):
    """A bush filling its (solid) box: a big rounded body with smaller clumps bulging out of it, so it reads round
    from every side. Looks: b leafy green, c dark evergreen (taller, pointed), d in flower."""
    look = piece["look"]
    mat = "dbr_leaf_" + look
    for box in piece["boxes"]:
        s, c, yaw = box["size"], box["pos"], box["yaw"]
        y0 = c[1] - s[1] / 2 - 0.08
        taper = 0.55 if look == "c" else 0.8
        rock(b, (c[0], y0 + s[1] * 0.42, c[2]), (s[0] * 0.92, s[1] * 0.84, s[2] * 0.92), yaw, rng, mat,
             jitter=0.12, chamfer=0.38, taper=taper)
        n = 2 if s[1] < 1.05 else rng.randint(3, 4) if s[1] < 1.5 else rng.randint(4, 6)   # (small ones cheaper)
        for k in range(n):
            a = math.radians(yaw + k * 360 / n + rng.uniform(-25, 25))
            r = rng.uniform(0.28, 0.4)
            px, pz = math.cos(a) * s[0] * r, math.sin(a) * s[2] * r
            hh = s[1] * rng.uniform(0.45, 0.65) * (0.8 if look == "c" else 1.0)
            w = min(s[0], s[2]) * rng.uniform(0.45, 0.6)
            rock(b, (c[0] + px, y0 + hh / 2 + rng.uniform(0.0, 0.25), c[2] + pz), (w, hh, w * rng.uniform(0.8, 1.1)),
                 rng.uniform(0, 90), rng, mat, jitter=0.15, chamfer=0.4, taper=0.8)
        if n == 2:
            continue
        top = s[1] * (0.4 if look == "c" else 0.32)       # a crown on top
        w = min(s[0], s[2]) * (0.4 if look == "c" else 0.55)
        rock(b, (c[0] + rng.uniform(-0.15, 0.15), y0 + s[1] + 0.08 - top / 2, c[2] + rng.uniform(-0.15, 0.15)),
             (w, top, w), rng.uniform(0, 90), rng, mat, jitter=0.12, chamfer=0.42, taper=0.6 if look == "c" else 0.8)


# ------------------------------------------------------------------------------------------------ the town square
# (World art 0.17, owner 2026-10-18: "we gotta do the town hall, like the middle"): paving, fountain, statue, market
# stalls, planters and a newsstand kiosk, each drawn round its old gray boxes (collision unchanged).
def draw_plaza(b, piece, rng):
    box = piece["boxes"][0]
    (x, y, z), s = box["pos"], box["size"]
    top = y + s[1] / 2
    f = Frame(b, (x, top, z), box["yaw"])
    W, D = s[0], s[2]
    f.box((0, -0.15, 0), (W - 0.5, 0.3, D - 0.5), style=lambda n, m, q: ("dbr_setts", uv_world(2.0)) if n[1] > 0.7 else None)
    kerb = lambda n, m, q: None if n[1] < -0.7 else ("stone_rough", uv_world(1.0))
    for sx in (-1, 1):   # a kerb round the edge (down into the ground)
        f.box((sx * (W / 2 - 0.13), -0.2, 0), (0.26, 0.44, D), style=kerb)
        f.box((0, -0.2, sx * (D / 2 - 0.13)), (W - 0.52, 0.44, 0.26), style=kerb)
    for _ in range(14):   # loose and broken setts, a few weeds in the joints
        p = f.p(rng.uniform(-W / 2 + 1, W / 2 - 1), 0.03, rng.uniform(-D / 2 + 1, D / 2 - 1))
        b.box(p, (0.25, 0.06, 0.18), yaw=rng.uniform(0, 90), style=no_bottom("dbr_setts", 1.0))
    for _ in range(10):
        p = f.p(rng.uniform(-W / 2 + 1, W / 2 - 1), 0.08, rng.uniform(-D / 2 + 1, D / 2 - 1))
        b.box(p, (0.18, 0.16, 0.18), yaw=rng.uniform(0, 90), style=no_bottom("dbr_leaf_b", 1.0))


def draw_fountain(b, piece, rng):
    basin, column = piece["boxes"][:2]
    f = frame_of(b, basin)
    r, H, t = basin["size"][0] / 2, basin["size"][1], 0.42
    side = 2 * r * math.tan(math.pi / 8)
    for k in range(8):   # the octagonal rim, a coping on top
        a = k * 45.0
        c, s_ = math.cos(math.radians(a)), math.sin(math.radians(a))
        f.box(((r - t / 2) * s_, H / 2 - 0.05, (r - t / 2) * c), (side + 0.02, H + 0.1, t), yaw=a, style=no_bottom("stone_rough", 1.0))
        f.box(((r - t / 2) * s_, H + 0.08, (r - t / 2) * c), (side + 0.1, 0.12, t + 0.12), yaw=a, style=no_bottom("sandstone", 1.0))
    cyl(b, f.p(0, 0.25, 0), r - t + 0.05, 0.3, "stone_rough", sides=8, cap_mat="dbr_water", yaw=f.yaw + 22.5)   # water
    H0 = column["pos"][1] - column["size"][1] / 2 - (basin["pos"][1] - H / 2)
    cyl(b, f.p(0, H0 * 0.5, 0), 0.62, H0 - 0.3, "sandstone", sides=8)                       # the pedestal
    cyl(b, f.p(0, H0 + 0.35, 0), 0.42, 0.7, "sandstone", sides=8)
    cyl(b, f.p(0, H0 + 0.8, 0), 1.2, 0.2, "sandstone", sides=10, cap_mat="dbr_water")     # the bowl
    cyl(b, f.p(0, H0 + 0.62, 0), 0.8, 0.18, "stone_rough", sides=10)
    cyl(b, f.p(0, H0 + 1.2, 0), 0.22, 0.6, "sandstone", sides=8)
    cyl(b, f.p(0, H0 + 1.6, 0), 0.4, 0.12, "sandstone", sides=8)
    cyl(b, f.p(0, H0 + 1.75, 0), 0.12, 0.25, "sandstone", sides=6)
    if piece["look"] == "d":   # shelled: a chunk out of the rim, rubble in the water
        bits(b, f.p(r - 0.4, 0, 0.5), 0.5, 5, rng, ("stone_rough", "rubble_core"))
    for _ in range(4):        # litter floating in it
        b.box(f.p(rng.uniform(-1.8, 1.8), 0.42, rng.uniform(-1.8, 1.8)), (0.25, 0.03, 0.18), yaw=rng.uniform(0, 90),
              style=no_bottom(rng.choice(("dbr_paper", "trim_dark")), 1.0))


def draw_statue(b, piece, rng):
    plinth, fig = piece["boxes"][:2]
    f = frame_of(b, plinth)
    W, H = plinth["size"][0], plinth["size"][1]
    f.box((0, 0.12, 0), (W, 0.24, W), style=no_bottom("stone_rough", 1.0))               # step
    f.box((0, H / 2 + 0.05, 0), (W - 0.5, H - 0.25, W - 0.5), style=no_bottom("sandstone", 1.0))
    f.box((0, H - 0.08, 0), (W - 0.25, 0.16, W - 0.25), style=no_bottom("sandstone", 1.0))  # cornice
    f.box((0, H * 0.55, (W - 0.5) / 2 + 0.02), (1.0, 0.45, 0.04), style=flat("bronze", 1.0))   # plaque
    for sx in (-1, 1):
        for sz in (-1, 1):   # wreaths of dead flowers at the foot
            if rng.random() < 0.5:
                cyl(b, f.p(sx * (W / 2 + 0.3), 0.08, sz * rng.uniform(0, W / 2)), 0.3, 0.12, "wood_dark", sides=8, axis="z")
    # The figure: a soldier in bronze (look c raises a flag; d lost its head to a shell, lying on the step)
    g = Frame(b, f.p(0, H, 0), f.yaw)
    br = no_bottom("bronze", 1.0)
    g.box((0, 0.08, 0), (0.9, 0.16, 0.8), style=br)                       # base
    for sx in (-1, 1):
        g.box((sx * 0.16, 0.6, 0), (0.24, 0.9, 0.28), style=br)            # legs
        g.box((sx * 0.16, 0.2, 0.06), (0.26, 0.2, 0.4), style=br)          # boots
    g.box((0, 1.35, 0), (0.62, 0.7, 0.36), style=br)                       # torso
    g.box((0, 1.05, 0), (0.66, 0.12, 0.4), style=br)                       # belt
    g.box((0, 1.78, 0), (0.18, 0.12, 0.18), style=br)                      # neck
    look = piece["look"]
    if look != "d":
        g.box((0, 1.97, 0), (0.3, 0.3, 0.32), style=br)                    # head
        g.box((0, 2.14, 0), (0.42, 0.14, 0.44), style=br)                  # helmet
    else:
        b.box(f.p(W / 2 + 0.4, 0.15, 0.6), (0.36, 0.3, 0.4), yaw=f.yaw + 30, pitch=70, style=flat("bronze", 1.0))
    g.box((-0.42, 1.3, 0.05), (0.18, 0.7, 0.2), style=br)                  # left arm down
    if look == "c":
        g.box((0.42, 1.85, 0), (0.18, 0.7, 0.2), style=br)                 # right arm up with a flag
        cyl(b, g.p(0.42, 2.3, 0), 0.04, 1.6, "bronze", sides=6)
        g.box((0.42, 2.85, 0.45), (0.04, 0.5, 0.85), style=flat("bronze", 1.0))
    else:
        g.box((0.42, 1.4, 0.15), (0.18, 0.55, 0.2), pitch=-30, style=br)   # right arm, holding the rifle across
        g.box((0.0, 1.45, 0.3), (0.9, 0.08, 0.1), yaw=-30, style=br)


def draw_planter(b, piece, rng):
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W, H, D = box["size"]
    f.box((0, H / 2, 0), (W, H, D), style=lambda n, m, q: None if n[1] < -0.7 else ("stone_rough", uv_world(1.5)) if n[1] < 0.7 else None)
    for sx in (-1, 1):   # the lip, its top open over the soil
        f.box((sx * (W / 2 - 0.07), H + 0.04, 0), (0.18, 0.08, D + 0.04), style=no_bottom("stone_rough", 1.0))
        f.box((0, H + 0.04, sx * (D / 2 - 0.07)), (W - 0.32, 0.08, 0.18), style=no_bottom("stone_rough", 1.0))
    f.box((0, H - 0.06, 0), (W - 0.2, 0.1, D - 0.2), style=no_bottom("dbr_dirt", 1.0))
    mat = "dbr_leaf_" + piece["look"]
    for k in range(3):   # shrubs grown wild
        x = (k - 1) * W * 0.3 + rng.uniform(-0.15, 0.15)
        w = rng.uniform(0.7, 0.95)
        rock(b, f.p(x, H + 0.3, rng.uniform(-0.15, 0.15)), (w, rng.uniform(0.6, 0.9), w * 0.9), rng.uniform(0, 90), rng, mat,
             jitter=0.12, chamfer=0.4, taper=0.75)


def draw_stall(b, piece, rng):
    counter, awning = piece["boxes"][0], piece["boxes"][1]
    f = frame_of(b, counter)
    W, H, D = counter["size"]
    look = piece["look"]
    f.box((0, H / 2, 0), (W, H, D), style=lambda n, m, q: None if n[1] < -0.7 else
          (("wood_light" if n[1] > 0.7 else "wood"), uv_world(1.0)))
    f.box((0, H + 0.03, 0.05), (W + 0.1, 0.06, D + 0.2), style=no_bottom("wood_dark", 1.0))      # the counter top
    top = awning["pos"][1] - (counter["pos"][1] - H / 2)
    aw = awning["size"]
    skin = {"b": "dbr_awn_r", "c": "dbr_awn_g", "d": "dbr_awn_b"}[look]
    torn = rng.random() < 0.4
    f.box((0, top, 0), (aw[0], 0.05, aw[2]), pitch=-8, style=lambda n, m, q: (skin, uv_world(1.2)))
    for k in range(9):   # the valance: a scalloped hem along the front
        if torn and k > 5:
            continue
        x = -aw[0] / 2 + (k + 0.5) * aw[0] / 9
        f.box((x, top - 0.22, aw[2] / 2 - 0.12), (aw[0] / 9 - 0.03, 0.3, 0.03), style=lambda n, m, q: (skin, uv_world(1.2)))
    for p in piece["boxes"][2:]:   # the posts
        lp = rot(v_sub(tuple(p["pos"]), f.at), -f.yaw, 0.0)
        for zz in (-aw[2] / 2 + 0.15, aw[2] / 2 - 0.15):
            f.box((lp[0], top / 2, zz), (0.1, top, 0.1), style=no_bottom("wood_dark", 1.0))
    goods = [("crate", 0.5, 0.3, 0.4)] * 2 + [("veg", 0.35, 0.15, 0.3)] * 3
    for _ in range(rng.randint(3, 5)):   # what's left on it: crates, spilled produce
        kind, gx, gy, gz = rng.choice(goods)
        x, z = rng.uniform(-W / 2 + 0.4, W / 2 - 0.4), rng.uniform(-D / 2 + 0.3, D / 2 - 0.3)
        mat = "wood_light" if kind == "crate" else rng.choice(("dbr_leaf_b", "awn_r_flat", "hz_flat"))
        f.box((x, H + 0.06 + gy / 2, z), (gx, gy, gz), yaw=rng.uniform(-20, 20), style=no_bottom(mat, 1.0))
    for _ in range(2):   # and on the ground
        f.box((rng.uniform(-W / 2, W / 2), 0.15, D / 2 + rng.uniform(0.3, 1.0)), (0.5, 0.3, 0.4), yaw=rng.uniform(0, 90),
              pitch=rng.choice((0, 0, 90)), style=no_bottom("wood_light", 1.0))


def draw_kiosk(b, piece, rng):
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W, H, D = box["size"]
    skin = {"b": "dbr_dmp_g", "c": "dbr_dmp_b", "d": "dbr_burnt"}[piece["look"]]
    f.box((0, H / 2 - 0.15, 0), (W, H - 0.3, D), style=no_bottom(skin, 2.0))
    f.box((0, H - 0.1, 0), (W + 0.6, 0.2, D + 0.6), style=flat("trim_dark", 1.0))                  # roof
    f.box((0, H + 0.1, 0), (W - 0.2, 0.2, D - 0.2), style=no_bottom("trim_dark", 1.0))
    # The hatch on the square side (south, +z): shutter rolled half up, a dark inside, a shelf of papers
    f.box((0, 1.55, D / 2 + 0.01), (W - 0.5, 1.0, 0.02), style=flat("black", 1.0))
    f.box((0, 2.05, D / 2 + 0.03), (W - 0.45, 0.3, 0.04), style=flat("steel_light", 1.0))
    f.box((0, 1.05, D / 2 + 0.2), (W - 0.3, 0.06, 0.4), style=no_bottom("trim_dark", 1.0))
    for k in range(6):
        f.box((-W / 2 + 0.45 + k * 0.32, 1.1, D / 2 + 0.2), (0.24, 0.03, 0.32), yaw=rng.uniform(-10, 10),
              style=no_bottom(rng.choice(("dbr_paper", "awn_r_flat", "paper_green", "dbr_paper")), 1.0))
    for sx in (-1, 1):   # posters on the sides
        for k in range(2):
            f.box((sx * (W / 2 + 0.01), 1.3 + k * 0.05, -0.5 + k * 0.9), (0.02, 0.7, 0.5),
                  style=flat(rng.choice(("dbr_paper", "awn_r_flat", "hz_flat")), 1.0))
    for _ in range(4):   # newspapers blown about
        b.box(f.p(rng.uniform(-2.5, 2.5), 0.02, rng.uniform(1.5, 3.5)), (0.4, 0.01, 0.3), yaw=rng.uniform(0, 180),
              style=no_bottom("dbr_paper", 1.0))


# ------------------------------------------------------------------------------------------------ street lamps
# (outdoor step 3) Looks: b a modern steel pole with a cobra-head lamp, c an old cast-iron lantern post, d a concrete
# pole with a curved arm and a sodium lamp. Some are bent; knocked-down ones lie in the verge.
def lamp_parts(b, f, look, rng, bent=0.0):
    """One lamp in frame f (origin at the pole's foot, +y up the pole, +z toward the road)."""
    if look == "b":
        cyl(b, f.p(0, 0.15, 0), 0.2, 0.3, "trim_dark", sides=8, yaw=f.yaw)                     # base
        cyl(b, f.p(0, 3.2, 0), 0.08, 6.1, "metal", sides=8, yaw=f.yaw)
        f.box((0, 6.2, 0.9), (0.08, 0.08, 1.9), pitch=-6 + bent, style=flat("metal", 1.0))    # the arm
        f.box((0, 6.28 - bent * 0.03, 1.9), (0.32, 0.14, 0.62), pitch=bent, style=flat("trim_dark", 1.0))   # the head
        f.box((0, 6.2 - bent * 0.03, 1.92), (0.24, 0.02, 0.46), pitch=bent, style=flat("steel_light", 1.0))  # its lens
    elif look == "c":
        cyl(b, f.p(0, 0.35, 0), 0.2, 0.7, "trim_dark", sides=8, yaw=f.yaw)                     # fluted foot
        cyl(b, f.p(0, 0.75, 0), 0.14, 0.1, "trim_dark", sides=8, yaw=f.yaw)
        cyl(b, f.p(0, 2.2, 0), 0.07, 2.9, "trim_dark", sides=8, yaw=f.yaw)
        cyl(b, f.p(0, 3.68, 0), 0.12, 0.08, "trim_dark", sides=8, yaw=f.yaw)
        f.box((0, 3.75, 0), (0.06, 0.12, 0.7), style=flat("trim_dark", 1.0))                  # cross bar
        f.box((0, 4.02, 0), (0.42, 0.5, 0.42), yaw=bent, style=flat("steel_light", 1.0))      # the lantern's glass
        for sx in (-1, 1):
            for sz in (-1, 1):
                f.box((sx * 0.21, 4.02, sz * 0.21), (0.05, 0.54, 0.05), style=flat("trim_dark", 1.0))
        f.box((0, 4.3, 0), (0.52, 0.08, 0.52), style=flat("trim_dark", 1.0))
        rock(b, f.p(0, 4.45, 0), (0.42, 0.22, 0.42), f.yaw + 45, rng, "trim_dark", jitter=0.0, chamfer=0.1, taper=0.3)
        cyl(b, f.p(0, 4.62, 0), 0.03, 0.14, "trim_dark", sides=6)
    else:
        rock(b, f.p(0, 3.5, 0), (0.24, 7.0, 0.24), f.yaw, rng, "dbr_conc", jitter=0.0, chamfer=0.05, taper=0.6)
        f.box((0, 6.7, 0.5), (0.1, 0.1, 1.1), pitch=-30, style=flat("trim_dark", 1.0))        # the curved arm
        f.box((0, 6.95, 1.35), (0.1, 0.1, 0.9), pitch=-5 + bent, style=flat("trim_dark", 1.0))
        f.box((0, 6.86 - bent * 0.03, 1.85), (0.3, 0.18, 0.5), pitch=bent, style=flat("trim_dark", 1.0))
        f.box((0, 6.76 - bent * 0.03, 1.87), (0.22, 0.04, 0.36), pitch=bent, style=flat("hz_flat", 1.0))   # sodium glass


def draw_lamp(b, piece, rng):
    box = piece["boxes"][0]
    look = piece["look"]
    (x, y, z), s = box["pos"], box["size"]
    if s[1] < 1.0:   # knocked down: the pole lying along the box, its foot at the road end, a crack in the kerb
        yaw = box["yaw"]
        foot = v_add((x, y - s[1] / 2, z), rot((0, 0, s[2] / 2), yaw, 0.0))
        v0, n0 = len(b.verts), len(b.normals)
        lamp_parts(b, Frame(b, (0, 0, 0), 0), look, rng)
        # (lay it down: turned -90 degrees about x, so the pole runs along -z, away from the road, arm up; then placed)
        lay = lambda p: (p[0], p[2], -p[1])
        for i in range(v0, len(b.verts)):
            q = lay(b.verts[i])
            b.verts[i] = v_add(rot((q[0], q[1] + 0.15, q[2]), yaw, 0.0), foot)
        for i in range(n0, len(b.normals)):
            b.normals[i] = rot(lay(b.normals[i]), yaw, 0.0)
        bits(b, foot, 0.4, 3, rng, ("dbr_conc", "rubble_core"))
        return
    f = frame_of(b, box)
    lamp_parts(b, f, look, rng, bent=rng.choice((0, 0, 0, 0, 25, -20)))


# ------------------------------------------------------------------------------------------------ containers
def container(f, rng, skin, ribs=True, holes=False, L=6.1, W=2.4, H=2.6):
    side = lambda nn, m, q: None if nn[1] < -0.7 else (skin, uv_world(2.4))
    f.box((0, H / 2, 0), (W - 0.08, H - 0.12, L - 0.1), style=side)
    if ribs:
        for s in (-1, 1):
            for i in range(14):
                f.box((s * (W / 2 - 0.02), H / 2, -L / 2 + 0.4 + i * (L - 0.8) / 13), (0.05, H - 0.2, 0.14), style=no_bottom(skin, 2.4))
    for s in (-1, 1):
        for y in (0.06, H - 0.06):
            f.box((s * (W / 2 - 0.03), y, 0), (0.1, 0.14, L), style=no_bottom("trim_dark", 2.0))
        for zz in (-1, 1):
            f.box((s * (W / 2 - 0.06), H / 2, zz * (L / 2 - 0.06)), (0.14, H, 0.14), style=no_bottom("trim_dark", 2.0))
    for zz in (-1, 1):
        for y in (0.06, H - 0.06):
            f.box((0, y, zz * (L / 2 - 0.03)), (W, 0.14, 0.1), style=no_bottom("trim_dark", 2.0))
    for s in (-1, 1):   # the doors (+z): two leaves, locking bars
        f.box((s * W / 4, H / 2, L / 2 + 0.02), (W / 2 - 0.1, H - 0.16, 0.05), style=flat(skin, 2.4))
        for k in (0.3, 0.7):
            f.box((s * (W / 2 - 0.06) - s * (W / 2 - 0.06) * k, H / 2, L / 2 + 0.06), (0.04, H - 0.3, 0.04), style=flat("trim_dark", 1.0))
    if holes:   # shot up
        for _ in range(10):
            s = rng.choice((-1, 1))
            f.box((s * (W / 2 + 0.005), rng.uniform(0.6, 2.2), rng.uniform(-2.6, 2.6)), (0.01, rng.uniform(0.08, 0.2), rng.uniform(0.08, 0.2)),
                  style=flat("black", 1.0))


def draw_container(b, piece, rng):
    look = piece["look"]
    for box in piece["boxes"]:
        s = box["size"]
        f = frame_of(b, box)
        if look == "b":
            container(f, rng, rng.choice(("dbr_cont_r", "dbr_cont_b")), L=s[2], W=s[0], H=s[1])
        elif look == "c":
            container(f, rng, "dbr_cont_g", ribs=False, L=s[2], W=s[0], H=s[1])
        else:
            container(f, rng, "dbr_burnt", holes=True, L=s[2], W=s[0], H=s[1])


# ------------------------------------------------------------------------------------------------ army trucks
def draw_truck(b, piece, rng):
    body = max(piece["boxes"], key=lambda bx: bx["size"][2])
    look = piece["look"]
    f = frame_of(b, body)
    skin = "dbr_trk_o"
    burnt = look == "d"
    cover = {"b": "canvas", "c": "torn", "d": "none"}[look]
    f.box((0, 0.7, 0.6), (1.6, 0.25, 8.0), style=flat("trim_dark", 1.0))                    # chassis
    for z in (-2.6, -1.4, 3.8):
        for s in (-1, 1):
            if burnt and rng.random() < 0.3:
                cyl(b, f.p(s * 1.05, 0.3, z), 0.3, 0.3, "trim_dark", sides=10, axis="x", yaw=f.yaw)   # bare hub
            else:
                cyl(b, f.p(s * 1.05, 0.5, z), 0.5, 0.4, "dbr_tyre", sides=12, axis="x", yaw=f.yaw, cap_mat="trim_dark")
    cab = "dbr_burnt" if burnt else skin
    f.box((0, 1.55, 4.1), (2.3, 1.5, 1.8), style=no_bottom(cab, 2.0))
    f.box((0, 1.0, 5.25), (2.2, 0.8, 0.6), style=no_bottom(cab, 2.0))                           # bonnet
    f.box((0, 1.9, 5.01), (2.0, 0.6, 0.04), style=flat("black" if burnt else "trim_dark", 1.0))  # windscreen
    f.box((0, 1.0, 5.56), (2.0, 0.5, 0.04), style=flat("trim_dark", 1.0))                      # grille
    for s in (-1, 1):
        f.box((s * 1.16, 1.95, 4.2), (0.04, 0.5, 0.9), style=flat("black" if burnt else "trim_dark", 1.0))
    bed = "dbr_burnt" if burnt else skin
    f.box((0, 1.0, -0.6), (2.4, 0.15, 5.6), style=no_bottom(bed, 2.0))
    for s in (-1, 1):
        f.box((s * 1.18, 1.45, -0.6), (0.06, 0.8, 5.6), style=flat(bed, 2.0))
    f.box((0, 1.45, -3.38), (2.4, 0.8, 0.06), style=flat(bed, 2.0))
    for z in (-3.2, -1.8, -0.4, 1.0, 2.2):   # canvas hoops
        f.box((0, 2.95, z), (2.4, 0.06, 0.06), style=flat("trim_dark", 1.0))
        for s in (-1, 1):
            f.box((s * 1.2, 2.35, z), (0.06, 1.2, 0.06), style=flat("trim_dark", 1.0))
    if cover == "canvas":
        f.box((0, 2.98, -0.5), (2.5, 0.04, 5.9), style=flat("dbr_canvas", 2.0))
        for s in (-1, 1):
            f.box((s * 1.24, 2.35, -0.5), (0.04, 1.25, 5.9), style=flat("dbr_canvas", 2.0))
    elif cover == "torn":
        f.box((0, 2.98, 0.6), (2.5, 0.04, 2.4), style=flat("dbr_canvas", 2.0))
        f.box((1.24, 2.35, 0.6), (0.04, 1.25, 2.4), style=flat("dbr_canvas", 2.0))
        f.box((-1.3, 1.9, -1.2), (0.04, 1.4, 1.6), style=flat("dbr_canvas", 2.0))   # a flap hanging off
    for _ in range(3 if burnt else 1):
        mb.rubble_chunk(b, f.p(rng.uniform(-2, 2), 0.05, rng.uniform(-3, 4)), (0.3, 0.06, 0.2), rng, ("dbr_burnt", "trim_dark"))


# ------------------------------------------------------------------------------------------------ sandbags
SAND_MATS = {"b": ("dbr_bag_tan",), "c": ("dbr_bag_grn", "dbr_bag_grn", "dbr_bag_tan"), "d": ("dbr_bag_gry", "dbr_bag_gry", "dbr_bag_tan")}


def draw_sandbags(b, piece, rng):
    look = piece["look"]
    for box in piece["boxes"]:
        s = box["size"]
        f = frame_of(b, box)
        along_x = s[0] > s[2]
        L, depth = (s[0], s[2]) if along_x else (s[2], s[0])
        rows = max(1, round((s[1] + 0.2) / 0.21))   # (from 0.2 m under the ground: no gaps where it slopes)
        rh = (s[1] + 0.2) / rows
        n = max(1, round(L / 0.62))
        bl = L / n

        def at(a, d, y):
            return (a, y, d) if along_x else (d, y, a)
        for r in range(rows):
            off = bl / 2 if r % 2 else 0.0
            for i in range(n + (1 if r % 2 else 0)):
                a = -L / 2 + bl / 2 + i * bl - off
                w = bl if abs(a) <= L / 2 - bl / 2 + 1e-6 else bl / 2
                a = max(-L / 2 + w / 2, min(L / 2 - w / 2, a))
                for dd in (-depth / 4, depth / 4):
                    size = (w - 0.03, rh + 0.02, depth / 2 - 0.02)
                    f.box(at(a, dd + rng.uniform(-0.02, 0.02), (r + 0.5) * rh - 0.2),
                          size if along_x else (size[2], size[1], size[0]), yaw=rng.uniform(-3, 3), style=no_bottom(rng.choice(SAND_MATS[look]), 1.0))
        if look == "c":   # timber posts at the ends and a board across the top
            for a in (-L / 2 + 0.1, L / 2 - 0.1):
                f.box(at(a, depth / 2 + 0.08, (s[1] + 0.2) / 2), (0.15, s[1] + 0.2, 0.15), style=no_bottom("wood_dark", 1.0))
        if look == "d":   # burst bags and spilled sand
            for _ in range(max(1, int(L / 1.5))):
                d0 = rng.choice((-1, 1)) * (depth / 2 + rng.uniform(0.2, 0.5))
                f.box(at(rng.uniform(-L / 2, L / 2), d0, 0.05), (0.55, 0.12, 0.35) if along_x else (0.35, 0.12, 0.55),
                      yaw=rng.uniform(-30, 30), style=no_bottom("dbr_bag_gry", 1.0))
                f.box(at(rng.uniform(-L / 2, L / 2), d0, 0.01), (0.6, 0.04, 0.5), yaw=rng.uniform(0, 90), style=no_bottom("dbr_dirt", 1.0))


# ------------------------------------------------------------------------------------------------ concrete barriers
def draw_barrier(b, piece, rng):
    skin = {"b": "dbr_conc", "c": "dbr_redwhite", "d": "dbr_hazard"}[piece["look"]]
    for box in piece["boxes"]:
        s = box["size"]
        f = frame_of(b, box)
        L, W, H = s[2], s[0], s[1]
        k = H / 0.9
        f.box((0, 0.04 * k, 0), (W, 0.08 * k, L), style=no_bottom("dbr_conc", 1.0))
        f.box((0, 0.2 * k, 0), (W * 0.93, 0.24 * k, L), style=no_bottom("dbr_conc", 1.0))
        f.box((0, 0.55 * k, 0), (W * 0.57, 0.46 * k, L),
              style=lambda nn, m, q: None if nn[1] < -0.7 else ((skin if abs(local_normal(nn, f.yaw)[0]) > 0.5 else "dbr_conc"), uv_world(1.5)))
        f.box((0, 0.85 * k, 0), (W * 0.37, 0.14 * k, L - 0.02), style=no_bottom("dbr_conc", 1.0))
        for z in (-L * 0.3, L * 0.3):   # lifting loops
            f.box((0, 0.94 * k, z), (0.05, 0.06, 0.2), style=no_bottom("trim_dark", 1.0))
        f.box((0.1, 0.85 * k, L / 2 - 0.15), (0.25, 0.16, 0.3), style=no_bottom("rubble_core", 1.0))   # a chipped end
        for _ in range(2):
            mb.rubble_chunk(b, f.p(rng.uniform(-0.7, 0.7), 0.05, rng.uniform(-L / 2, L / 2)), (0.15, 0.08, 0.12), rng, ("dbr_conc", "rubble_core"))


# ------------------------------------------------------------------------------------------------ tank traps
def ibeam(b, c, yaw, pitch, mat, L=2.0, fl=0.2, web=0.2):
    for s in (-1, 1):
        b.box(v_add(c, rot((s * web / 2, 0, 0), yaw, pitch)), (0.025, fl, L), yaw=yaw, pitch=pitch, style=flat(mat, 1.0))
    b.box(c, (web, 0.025, L), yaw=yaw, pitch=pitch, style=flat(mat, 1.0))


def draw_tanktrap(b, piece, rng):
    look = piece["look"]
    hogs = []    # boxes sharing a middle make one hedgehog
    for box in piece["boxes"]:
        for h in hogs:
            if math.hypot(h[0]["pos"][0] - box["pos"][0], h[0]["pos"][2] - box["pos"][2]) < 0.3:
                h.append(box)
                break
        else:
            hogs.append([box])
    for h in hogs:
        c = tuple(h[0]["pos"])
        c = (c[0], c[1] + 0.02, c[2])
        for box in h:
            yaw, pitch, L = box["yaw"], box["pitch"], box["size"][2]
            if look == "b":     # rusty riveted I-beams
                ibeam(b, c, yaw, pitch, "gs_burnt", L=L)
            elif look == "c":   # painted angle iron
                b.box(c, (0.16, 0.025, L), yaw=yaw, pitch=pitch, style=flat("dbr_trk_o", 1.0))
                b.box(v_add(c, rot((0.08, 0.07, 0), yaw, pitch)), (0.025, 0.16, L), yaw=yaw, pitch=pitch, style=flat("dbr_trk_o", 1.0))
            else:               # cut railway rails
                b.box(c, (0.14, 0.03, L), yaw=yaw, pitch=pitch, style=flat("dbr_rail", 1.0))
                b.box(v_add(c, rot((0, 0.07, 0), yaw, pitch)), (0.025, 0.12, L), yaw=yaw, pitch=pitch, style=flat("dbr_rail", 1.0))
                b.box(v_add(c, rot((0, 0.14, 0), yaw, pitch)), (0.07, 0.04, L), yaw=yaw, pitch=pitch, style=flat("dbr_rail", 1.0))
        for k in range(3):   # plates at the crossing
            b.box(c, (0.32, 0.32, 0.02), yaw=h[0]["yaw"] + k * 60, style=flat("trim_dark", 1.0))
        if look == "d":      # barbed wire round it
            for i in range(12):
                a = i * 52
                r = 0.55 + 0.15 * math.sin(i)
                b.box((c[0] + r * math.sin(math.radians(a)), c[1] - 0.2 + 0.03 * i, c[2] + r * math.cos(math.radians(a))), (0.02, 0.02, 0.5),
                      yaw=a + 90, pitch=rng.uniform(-20, 20), style=flat("trim_dark", 1.0))


# ------------------------------------------------------------------------------------------------ oil drums
DRUM_MATS = {"b": ("dbr_drum_b", "dbr_drum_b", "dbr_cont_r"), "c": ("dbr_drum_o",), "d": ("dbr_burnt",)}


def drum(b, base, mat, yaw, tipped=False, holes=False, rng=None):
    pitch = 90.0 if tipped else 0.0
    c = (base[0], base[1] + (0.29 if tipped else 0.45), base[2])
    cyl(b, c, 0.29, 0.88, mat, sides=12, yaw=yaw, pitch=pitch)
    for w in (-0.29, 0.0, 0.29):   # rolling hoops
        cyl(b, v_add(c, rot((0, w, 0), yaw, pitch)), 0.305, 0.03, mat, sides=12, yaw=yaw, pitch=pitch, caps=False)
    if not tipped:
        cyl(b, (c[0] + 0.15, base[1] + 0.9, c[2]), 0.04, 0.03, "trim_dark", sides=6)
    if holes:
        for _ in range(3):
            b.box(v_add(c, rot((0.3, rng.uniform(-0.3, 0.3), 0), yaw, 0)), (0.02, 0.06, 0.06), yaw=yaw, style=flat("black", 1.0))


def draw_drums(b, piece, rng):
    look = piece["look"]
    for box in piece["boxes"]:
        s, p = box["size"], box["pos"]
        tipped = abs(box["pitch"]) > 45
        base = (p[0], p[1] - (0.3 if tipped else s[1] / 2), p[2])
        drum(b, base, rng.choice(DRUM_MATS[look]), box["yaw"], tipped=tipped, holes=look == "d", rng=rng)


# ------------------------------------------------------------------------------------------------ dumpsters
def draw_dumpster(b, piece, rng):
    look = piece["look"]
    skin = {"b": "dbr_dmp_g", "c": "dbr_dmp_b", "d": "dbr_burnt"}[look]
    for box in piece["boxes"]:
        f = frame_of(b, box)
        f.box((0, 0.72, 0), (1.9, 1.1, 1.1), style=no_bottom(skin, 2.0))
        f.box((0, 0.72, 0.56), (1.94, 0.12, 0.04), style=no_bottom(skin, 2.0))
        f.box((0, 1.24, 0.58), (1.96, 0.08, 0.08), style=no_bottom("trim_dark", 1.0))
        for s in (-1, 1):
            f.box((s * 0.99, 0.95, 0), (0.06, 0.12, 0.5), style=flat("trim_dark", 1.0))   # lifting pockets
            for zz in (-0.4, 0.4):
                cyl(b, f.p(s * 0.8, 0.09, zz), 0.08, 0.06, "black", sides=8, axis="x", yaw=f.yaw)
        if look == "b":
            f.box((0, 1.3, -0.02), (1.92, 0.05, 1.14), pitch=-4, style=no_bottom("trim_dark", 1.0))
        elif look == "c":   # lid thrown open, bin bags
            f.box((0, 1.75, -0.6), (1.92, 1.0, 0.05), pitch=-8, style=flat("trim_dark", 1.0))
            for _ in range(2):
                cyl(b, f.p(rng.uniform(-0.7, 0.7), 1.3, rng.uniform(-0.3, 0.3)), 0.22, 0.4, "black", sides=7)
            cyl(b, f.p(rng.uniform(-1.4, 1.4), 0.2, 0.9), 0.2, 0.4, "black", sides=7)


# ------------------------------------------------------------------------------------------------ craters
def draw_crater(b, piece, rng):
    look = piece["look"]
    mounds = piece["boxes"]
    cx = sum(m["pos"][0] for m in mounds) / len(mounds)
    cz = sum(m["pos"][2] for m in mounds) / len(mounds)
    R = sum(math.hypot(m["pos"][0] - cx, m["pos"][2] - cz) for m in mounds) / len(mounds)
    ph = (rng.uniform(0, 6), rng.uniform(0, 6))
    NA, NR = 32, 7
    r0, r1 = R - 1.2, R + 1.4

    def P(i, j):
        a = 2 * math.pi * i / NA
        r = r0 + (r1 - r0) * j / NR
        w = 1.0 + 0.25 * math.sin(3 * a + ph[0]) + 0.15 * math.sin(5 * a + ph[1])
        t = (r - R) / (1.2 if r < R else 1.4)
        h = 0.58 * w * max(0.0, 1 - t * t) ** 1.5
        sink = 0.45 if j == 0 else 0.15 if j == NR else 0.0
        x, z = cx + r * math.cos(a), cz + r * math.sin(a)
        return (x, ground(x, z) + h - sink, z)   # (round 2: the rim follows the ground and dips under it at its edges)
    for i in range(NA):
        for j in range(NR):
            q = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
            for a, c, d in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                n = norm(cross(v_sub(c, a), v_sub(d, a)))
                if n[1] < 0:
                    n = v_scale(n, -1)
                b.poly([a, c, d], n, GROUND, uv_world(2.0))   # (scorched or not: the splat map says)
    for _ in range(7):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(R - 0.6, R + 2.2)
        p = on_ground((cx + r * math.cos(a), 0.0, cz + r * math.sin(a)), 0.05)
        if look == "b":     # clods thrown out
            b.box(p, (0.4, 0.14, 0.3), yaw=rng.uniform(0, 90), pitch=rng.uniform(-20, 20),
                  style=lambda nn, m, q: (GROUND, uv_world(1.0)))
        elif look == "c":   # shrapnel
            b.box(p, (0.3, 0.04, 0.12), yaw=rng.uniform(0, 180), pitch=rng.uniform(-30, 30), style=flat("trim_dark", 1.0))
        else:               # stones in the grass
            s = rng.uniform(0.2, 0.4)
            rock(b, (p[0], p[1] + s * 0.3, p[2]), (s * 1.3, s, s), rng.uniform(0, 180), rng, "dbr_granite")


# ------------------------------------------------------------------------------------------------ small junk
def draw_junk(b, piece, rng):
    look = piece["look"]
    for box in piece["boxes"]:
        s = box["size"]
        f = frame_of(b, box)
        if look == "b":     # a plank and some bricks
            f.box((0, 0.03, 0), (0.2, 0.04, s[2]), pitch=rng.uniform(-4, 4), style=flat(rng.choice(("wood", "wood_dark", "wood_light")), 1.0))
            for _ in range(3):
                mb.rubble_chunk(b, f.p(rng.uniform(-0.5, 0.5), 0.04, rng.uniform(-0.6, 0.6)), (0.22, 0.07, 0.11), rng, ("house_brick", "rubble_core"))
        elif look == "c":   # scrap: a bent sheet, a tyre, a pipe
            if s[2] > 1.4:
                f.box((0, 0.06, 0), (0.12, 0.12, s[2]), style=flat("trim_dark", 1.0))
            else:
                f.box((0, 0.08, 0), (1.1, 0.03, 0.8), pitch=rng.uniform(-12, 12), style=flat(rng.choice(("dbr_cont_r", "shed_metal", "dbr_burnt")), 1.0))
            if rng.random() < 0.5:
                cyl(b, f.p(rng.uniform(-0.6, 0.6), 0.11, rng.uniform(-0.6, 0.6)), 0.33, 0.22, "dbr_tyre", sides=10, cap_mat="black")
        else:               # the town's litter: a box, papers, a bottle
            f.box((0, 0.12, 0), (0.5, 0.25, 0.4), yaw=rng.uniform(0, 90), pitch=rng.uniform(-10, 10), style=flat("cardboard", 1.0))
            for _ in range(3):
                f.box((rng.uniform(-0.8, 0.8), 0.01, rng.uniform(-0.8, 0.8)), (0.25, 0.01, 0.32), yaw=rng.uniform(0, 180), style=flat("dbr_paper", 1.0))
            cyl(b, f.p(rng.uniform(-0.6, 0.6), 0.04, rng.uniform(-0.6, 0.6)), 0.04, 0.25, "green", sides=6, axis="z", yaw=rng.uniform(0, 180))


DRAW = {"ruin": draw_ruin, "wall": draw_wall, "berm": draw_berm, "rocks": draw_rocks, "rubble": draw_rubble, "container": draw_container,
        "truck": draw_truck, "sandbags": draw_sandbags, "barrier": draw_barrier, "tanktrap": draw_tanktrap,
        "drums": draw_drums, "dumpster": draw_dumpster, "crater": draw_crater, "junk": draw_junk, "bush": draw_bush,
        "plaza": draw_plaza, "fountain": draw_fountain, "statue": draw_statue, "planter": draw_planter, "stall": draw_stall,
        "kiosk": draw_kiosk, "lamp": draw_lamp}


def main():
    names = sys.argv[1:]
    os.makedirs(OUT_DIR, exist_ok=True)
    textures, mat_info = {}, {}
    for kit, painter in mb.KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"), painter,
                                         random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, kit == "glass")
    mat_info["ground"] = ("kit_dbr_ground", False, False)
    cells = mb.kit_atlas()
    TERRAIN.update(json.load(open(os.path.join(JSON_DIR, "terrain.json"))))
    total = 0
    for fn in sorted(os.listdir(JSON_DIR)):
        name = fn[:-5]
        if not fn.endswith(".json") or fn == "terrain.json" or (names and name not in names):
            continue
        data = json.load(open(os.path.join(JSON_DIR, fn)))
        ORIGIN[:] = data["origin"]
        b = Builder()
        for piece in data["pieces"]:
            DRAW[piece["kind"]](b, piece, random.Random(f"{piece['kind']} {piece['seed']}"))
        out = os.path.join(OUT_DIR, name + ".glb")
        mb.write_glb(out, b, textures, mat_info, atlas=cells)
        mb.set_import_script(out)
        tris = sum(len(f) - 2 for f in b.faces)
        total += tris
        print(f"{name}: {len(data['pieces'])} pieces, {tris} triangles")
    print(f"outdoor total: {total} triangles")


if __name__ == "__main__":
    main()
