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
    # the derailed train (step 5): a maroon locomotive with a yellow stripe, tank cars black or grey
    "loco_r": "6a2a24", "loco_r_dk": "57221d", "loco_y": "b8902e", "tank_k": "2e2d2b", "tank_k_dk": "252422",
    "tank_g": "6c6d68", "tank_g_dk": "5a5b57", "placard": "c47a2a", "sig_dead": "2a2f2c",
    "xing": "53524e", "xing_dk": "47463f",
    # bushes (step 2, owner: "add some big bushes"): leafy green, a dark evergreen, and one in flower
    "lf1": "4a6b35", "lf1_dk": "3a5529", "lf1_lt": "5e8040", "lf1_sh": "2c4524",
    "lf2": "3f5a37", "lf2_dk": "2f4529", "lf2_lt": "4f6b42", "lf2_sh": "263a22",
    "lf3": "4f6e38", "lf3_dk": "3e5a2b", "lf3_lt": "638545",
    # the town square (World art 0.17): setts, fountain water, awnings
    "sett1": "7c766c", "sett2": "706a61", "sett3": "857f74", "sett_j": "524d46", "sett_dk": "625c53",
    "wat1": "4c6466", "wat2": "435a5c", "wat_lt": "5d777a", "scum": "56634a",
    # power lines (outdoor step 4): creosoted pole wood, glass and porcelain insulators, transformer grey
    "pole1": "5b4a3a", "pole2": "4d3f32", "pole_lt": "6b5a48", "pole_ck": "3a3027",
    "ins_g": "5f8a7a", "ins_g_lt": "7fa898", "porc": "6e4a34", "porc_lt": "86604a", "xf": "7b8079", "xf_dk": "656a64",
    # the railway (step 5): ballast, steel
    "bal1": "6f6a62", "bal2": "5e5953", "bal3": "7f786d", "bal_dk": "4b4743", "bal_oil": "45403a",
    # road signs (round 3): enamel colours, faded a little in the sun
    "sg_red": "a3342b", "sg_yel": "d9b33a", "sg_grn": "2f6146", "sg_blue": "2f4f7a", "sg_wht": "ddd8cc",
    "sg_blk": "26262a", "sg_wood": "6a4a2e", "sg_wood_dk": "553a23", "sg_cream": "d6c9a4",
    # set pieces (step 8): ploughed soil, wheat, maize, sunflowers, burlap, ashes
    "soil1": "4f3c2b", "soil2": "453425", "soil_lt": "5f4a36", "soil_dk": "3a2b1f",
    "wht1": "b8994f", "wht2": "a3853f", "wht_lt": "cdb066", "wht_dk": "8a6f34",
    "mz1": "6f8a3c", "mz2": "5f7832", "mz_lt": "8aa04c", "mz_dry": "a39a55",
    "sf1": "4d6a2e", "sf2": "405a26", "sf_dry": "7a6a3a", "sf_y": "d1a52c", "sf_y_dk": "b0861f", "sf_seed": "4a3523",
    "brl1": "7d6c4c", "brl2": "6b5b3e", "brl_dk": "564830",
    "ash1": "5d5853", "ash2": "4a4642", "ash_lt": "77716a", "ember": "6b3d24",
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


def k_pole(rng):
    """Weathered creosoted pole wood: vertical grain, cracks (checks), a few grey bleached streaks."""
    c = Canvas(32, 64, "pole1")
    c.noise(0, 0, 32, 64, ["pole2", "pole_lt"], 0.18, rng)
    for _ in range(9):
        x, y = rng.randrange(32), rng.randrange(64)
        c.rect(x, y, x + 1, min(64, y + rng.randint(6, 20)), "pole_ck")
    for _ in range(4):
        x = rng.randrange(32)
        c.rect(x, 0, x + 1, 64, "pole_lt")
    return c


def k_ballast(rng):
    """Railway ballast: crushed grey-brown stone, oily patches."""
    c = Canvas(64, 64, "bal1")
    c.noise(0, 0, 64, 64, ["bal2", "bal3", "bal_dk"], 0.55, rng)
    c.blotch(["bal_oil"], 4, rng, size=(2, 5))
    return c


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


def k_soil(rng):
    """Ploughed field: furrows a ridge every 8 px (0.25 m), clods, a few stones."""
    c = Canvas(64, 64, "soil1")
    for y in range(0, 64, 8):
        c.rect(0, y, 64, y + 2, "soil_dk")
        c.rect(0, y + 4, 64, y + 6, "soil_lt")
    c.noise(0, 0, 64, 64, ["soil2", "soil_dk", "soil_lt"], 0.18, rng)
    for _ in range(10):
        x, y = rng.randrange(64), rng.randrange(64)
        c.rect(x, y, x + 2, y + 1, "pebble")
    return c


def k_stalks(base, dark, light, extra, chance=0.25):
    """A crop's stalks seen from the side: upright streaks, dark gaps between, some lighter leaves."""
    def paint(rng):
        c = Canvas(64, 64, base)
        for x in range(0, 64):
            if rng.random() < 0.28:
                c.rect(x, 0, x + 1, 64, dark)
            elif rng.random() < 0.2:
                c.rect(x, 0, x + 1, 64, light)
        c.noise(0, 0, 64, 64, [dark, light, extra], chance, rng)
        for _ in range(14):   # leaves crossing the stalks
            x, y = rng.randrange(64), rng.randrange(64)
            c.rect(x, y, min(64, x + rng.randint(3, 6)), y + 1, light)
        return c
    return paint


def k_heads(base, dark, light):
    """A crop seen from above: heads and leaf tips, dark gaps."""
    def paint(rng):
        c = Canvas(64, 64, dark)
        c.noise(0, 0, 64, 64, [base, light], 0.75, rng)
        c.blotch([dark], 10, rng, size=(1, 3))
        return c
    return paint


def k_burlap(rng):
    c = Canvas(64, 64, "brl1")
    for y in range(0, 64, 2):
        c.rect(0, y, 64, y + 1, "brl2")
    for x in range(0, 64, 3):
        c.rect(x, 0, x + 1, 64, "brl2")
    c.noise(0, 0, 64, 64, ["brl_dk", "lf2_dk"], 0.12, rng)
    c.blotch(["lf2", "lf2_dk", "dirt2"], 9, rng, size=(3, 8))   # (painted camo patches)
    return c


def k_ash(rng):
    c = Canvas(64, 64, "ash1")
    c.noise(0, 0, 64, 64, ["ash2", "ash_lt", "burnt2"], 0.4, rng)
    c.blotch(["burnt2"], 6, rng, size=(3, 7))
    c.blotch(["ember"], 3, rng, size=(1, 2))
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
    "dbr_ballast": k_ballast, "sg_red_flat": mb.paint_flat("sg_red"),
    "dbr_pole": k_pole, "dbr_ins_g": mb.paint_flat("ins_g"), "dbr_porc": mb.paint_flat("porc"),
    "dbr_xf": k_paint("xf", "xf_dk", 3),
    "dbr_loco_r": k_paint("loco_r", "loco_r_dk", 5), "dbr_tank_k": k_paint("tank_k", "tank_k_dk", 8),
    "dbr_tank_g": k_paint("tank_g", "tank_g_dk", 7), "loco_y_flat": mb.paint_flat("loco_y"),
    "placard_flat": mb.paint_flat("placard"), "sig_dead": mb.paint_flat("sig_dead"),
    "dbr_xing": k_paint("xing", "xing_dk", 2),
    "dbr_awn_r": k_stripes("awn_w", "awn_r"), "dbr_awn_g": k_stripes("awn_w", "awn_g"), "dbr_awn_b": k_stripes("awn_w", "awn_b"),
    "dbr_soil": k_soil, "dbr_wheat": k_stalks("wht1", "wht_dk", "wht_lt", "wht2"), "dbr_wheat_top": k_heads("wht1", "wht_dk", "wht_lt"),
    "dbr_maize": k_stalks("mz1", "mz2", "mz_lt", "mz_dry"), "dbr_maize_top": k_heads("mz1", "mz2", "mz_dry"),
    "dbr_sunfl": k_stalks("sf1", "sf2", "lf1_lt", "sf_dry"), "dbr_sunfl_top": k_heads("sf1", "sf2", "sf_dry"),
    "dbr_burlap": k_burlap, "dbr_ash": k_ash, "sf_y_flat": mb.paint_flat("sf_y"), "sf_seed_flat": mb.paint_flat("sf_seed"),
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


_ROAD_GRID = {}


def surface(x, z):
    """The top of what's under chunk point (x, z): the ground, or a road's ribbon where it's above it."""
    if not _ROAD_GRID:
        for r in TERRAIN.get("roads", []):
            p = r["points"]
            for i in range(0, len(p) - 2, 2):
                quad = (p[i], p[i + 1], p[i + 3], p[i + 2])
                xs, zs = [q[0] for q in quad], [q[2] for q in quad]
                for cx in range(int(min(xs) // 4), int(max(xs) // 4) + 1):
                    for cz in range(int(min(zs) // 4), int(max(zs) // 4) + 1):
                        _ROAD_GRID.setdefault((cx, cz), []).append(quad)
        _ROAD_GRID[None] = True
    h = ground(x, z)
    wx, wz = x + ORIGIN[0], z + ORIGIN[1]
    for quad in _ROAD_GRID.get((int(wx // 4), int(wz // 4)), ()):
        sides = [(c[0] - a[0]) * (wz - a[2]) - (c[2] - a[2]) * (wx - a[0]) for a, c in zip(quad, quad[1:] + quad[:1])]
        if all(v >= 0 for v in sides) or all(v <= 0 for v in sides):
            h = max(h, max(q[1] for q in quad))
    return h


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


# Collision shaped like the drawing (0.18.3, owner: "a lot of hitboxes are messed up like rocks ... make sure we look at
# models and match hitboxes to them"): pieces whose drawing isn't their gray box (boulders, earth banks, crater rims,
# rubble lumps, the leaning locomotive, the tank cars) hand the generator triangles to collide with instead of their
# boxes, in art_source/outdoor/collision.json: {"kind seed": {"boxes": [the box numbers they replace], "tris": [x, y, z,
# ...] (Godot space, the whole map)}}. Re-run the generator after this script so it picks them up.
SHAPES = {}
_SHAPE_KEY = [None]


def shape(b, f0, box, mats=None, upto=None, skip=()):
    """Collides with the faces drawn since face f0 (up to `upto`; only those in `mats`, if given; none in `skip`)
    instead of the current piece's box number `box` (a list: several boxes)."""
    entry = SHAPES.setdefault(_SHAPE_KEY[0], {"boxes": [], "tris": []})
    for k in (box if isinstance(box, (list, tuple)) else [box]):
        if k not in entry["boxes"]:
            entry["boxes"].append(k)
    keep = None if mats is None else {b.mat_index(m) for m in mats}
    drop = {b.mat_names.index(m) for m in skip if m in b.mat_names}
    for face, m in zip(b.faces[f0:upto], b.mats[f0:upto]):
        if (keep is not None and m not in keep) or m in drop:
            continue
        pts = [b.verts[i] for i in face]
        for k in range(1, len(pts) - 1):   # (a fan: the kit's faces are convex)
            for p in (pts[0], pts[k], pts[k + 1]):
                entry["tris"] += [round(p[0] + ORIGIN[0], 3), round(p[1], 3), round(p[2] + ORIGIN[1], 3)]


# Shots through the gaps you can see (0.19.8, owner: "i cannot shoot through these cracks in the bus stop, stuff like
# this needs to be fixed"): pieces that are open frames (shelters, fences, the hunting stands, market stalls, benches,
# signs, the clock, tents) keep their gray boxes for people only (BoxMap `bar_boxes`: you still can't walk through)
# while shots and eyes hit their drawing, glass left out (glass never stops a shot, as with windows).
SEE_THROUGH = {"shelter", "fence", "stand", "stall", "bench", "sign_stop", "sign_town", "sign_rail", "sign_speed",
               "sign_dir", "statue", "tent", "camptent", "truck", "tractor"}   # (trucks, tractor: 0.19.9, their windows)


def see_through(b, f0, piece):
    # (floors and ramps, like a hunting stand's, keep their boxes: you walk and the AI perch on them)
    solid = [k for k, box in enumerate(piece["boxes"]) if box["solid"] and box["size"][1] >= 0.4]
    if not solid:
        return
    shape(b, f0, solid, skip=("glass",))
    SHAPES[_SHAPE_KEY[0]]["people"] = True


def shape_boxes(parts, box, foot=None, yaw=0.0, lean=0.0, pivot_x=0.0):
    """Collides with plain boxes (centre, size: in a frame at the origin) instead of the piece's box(es) `box`; with
    `foot`, they're leaned and placed like `_leaned` does to a drawing."""
    t = Builder()
    for c, size in parts:
        t.box(c, size, style=lambda n, m, q: ("trim", uv_world()))
    if foot is not None:
        _leaned(t, 0, 0, foot, yaw, lean, pivot_x)
    shape(t, 0, box)


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
            spray_tag(b, box, random.Random(f"tag {piece['seed']} {box['pos']}"), 0.3, 0.06 if look == "d" else 0.0)
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


def draw_walk(b, piece, rng):
    """A path's slabs (round 3: paths to the doors): each a thin slab following the ground, its edge dropping into it."""
    mat = "dbr_conc" if piece["kind"] == "walk" else "dbr_slate"
    for box in piece["boxes"]:
        f = frame_of(b, box)
        w, l = box["size"][0], box["size"][2]
        draped(b, f, -w / 2, w / 2, -l / 2, l / 2, 0.045 + rng.uniform(0, 0.012), mat, step=1.2, lip=0.1, tile=1.0)


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
    for k, box in enumerate(piece["boxes"]):
        s = box["size"]
        if is_wall(box, 0.8):
            wall_run(b, box, RUBBLE_WALL[look], rng, top_mat=RUBBLE_WALL[look] if look != "b" else None, rebar=look == "b")
        else:
            f0 = len(b.faces)
            mb.rubble_chunk(b, tuple(box["pos"]), tuple(v * 0.95 for v in s), rng, mats, box["yaw"])
            shape(b, f0, k, upto=f0 + 5)   # (the lump itself is tilted: collide with it, not with the level box)
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
    same = random.Random()
    same.setstate(rng.getstate())
    earth_bank(b, boxes, rng)
    t = Builder()   # (its collision, owner 0.18.3: the bank itself, not a box inside it; the same bank, coarser)
    earth_bank(t, boxes, same, step=1.0, smooth=False)
    shape(t, 0, list(range(len(boxes))), mats=(GROUND,))


GRASS_TINT = (0.47, 0.62, 0.36)   # (the ground's grass colour, BoxMap colors[terrain_colour] = ground.gdshader tint_base)


def ground_tint(y, slope):
    """The colour BoxMap shades its ground with at height y and slope (rise per metre): hilltops a touch lighter,
    hollows and slopes darker. Banks and crater rims carry it as vertex colours, so they shade like the hill they're on."""
    if y > 0.0:
        a = min(max(y * 0.015, 0.0), 0.12)
        c = [v + (1.0 - v) * a for v in GRASS_TINT]
    else:
        a = min(max(-y * 0.04, 0.0), 0.15)
        c = [v * (1.0 - a) for v in GRASS_TINT]
    d = min(max(slope * 0.6, 0.0), 0.25)
    return tuple(v * (1.0 - d) for v in c)


def smooth_sheet(b, xs, zs, H, world, height, skip):
    """A height field drawn smooth: per-corner normals and ground tints from the field's own slopes (so it shades
    like the ground mesh, which is smooth too, and meets it without a seam). H[j][i] = (y, ground y)."""
    e = 0.25

    def corner(x, z):
        dx = (height(x + e, z)[0] - height(x - e, z)[0]) / (2 * e)
        dz = (height(x, z + e)[0] - height(x, z - e)[0]) / (2 * e)
        return dx, dz
    grad = {}
    for j in range(len(zs) - 1):
        for i in range(len(xs) - 1):
            hs = [H[j][i], H[j][i + 1], H[j + 1][i + 1], H[j + 1][i]]
            if skip(hs):
                continue
            ij = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            for k in ij:
                if k not in grad:
                    grad[k] = corner(xs[k[0]], zs[k[1]])
            q = [(world(xs[a], zs[c])[0], H[c][a][0], world(xs[a], zs[c])[1]) for a, c in ij]
            ns, cs = [], []
            for a, c in ij:   # (the slope turned into the world: the field's own frame may be turned by its yaw)
                dx, dz = grad[(a, c)]
                p0, p1, p2 = world(0.0, 0.0), world(1.0, 0.0), world(0.0, 1.0)
                ux, uz = p1[0] - p0[0], p1[1] - p0[1]
                vx, vz = p2[0] - p0[0], p2[1] - p0[1]
                gx, gz = dx * ux + dz * vx, dx * uz + dz * vz
                ns.append(norm((-gx, 1.0, -gz)))
                cs.append(ground_tint(H[c][a][0], math.hypot(gx, gz)))
            for t in ((0, 1, 2), (0, 2, 3)):
                tri = [q[k] for k in t]
                n = norm(cross(v_sub(tri[1], tri[0]), v_sub(tri[2], tri[0])))
                if n[1] < 0:
                    n = v_scale(n, -1)
                b.poly(tri, n, GROUND, uv_world(2.0), vnormals=[ns[k] for k in t], colors=[cs[k] for k in t])


def earth_bank(b, boxes, rng, step=0.5, smooth=True):
    """A bulldozed bank over its gray boxes, shaped from the ground (round 2, owner: the banks didn't sit on the
    hills and looked like loaves). 0.19.12 (owner: "they look super unnatural in some places, make them blend
    better"): a rounded crest instead of a flat top, a steep body (still too steep to walk up, as before) that
    flares into a gentle grassy foot sinking under the ground, a wavering outline, and smooth shading tinted like
    the ground round it, so there's no edge or colour step where it meets the grass. Its crest is as high as its
    boxes (they're its cover height); bare earth shows where it's steep (the ground shader)."""
    mid = boxes[len(boxes) // 2]
    yaw = mid["yaw"]
    ox, oz = mid["pos"][0], mid["pos"][2]
    rects = []
    for box in boxes:   # each box in the middle one's frame: (x0, x1, z0, z1, top)
        l = rot((box["pos"][0] - ox, 0.0, box["pos"][2] - oz), -yaw, 0.0)
        s_ = box["size"]
        rects.append((l[0] - s_[0] / 2, l[0] + s_[0] / 2, l[2] - s_[2] / 2, l[2] + s_[2] / 2, box["pos"][1] + s_[1] / 2))
    crest, sink, reach = 0.7, 0.3, 6.5
    x0, x1 = min(r[0] for r in rects) - reach, max(r[1] for r in rects) + reach
    z0, z1 = min(r[2] for r in rects) - reach, max(r[3] for r in rects) + reach
    ph = [rng.uniform(0, 6) for _ in range(4)]

    def world(x, z):
        p = rot((x, 0.0, z), yaw, 0.0)
        return ox + p[0], oz + p[2]

    def height(x, z):
        wx, wz = world(x, z)
        g = ground(wx, wz)
        # (the outline wavers, so it doesn't read as a stretched box)
        wob = 0.35 * math.sin(x * 0.55 + ph[0]) + 0.2 * math.sin(z * 0.9 + x * 0.3 + ph[1])
        best = None
        for rx0, rx1, rz0, rz1, top in rects:
            dx = max(rx0 - x, 0.0, x - rx1)
            dz = max(rz0 - z, 0.0, z - rz1)
            s = math.hypot(dx, dz) if dx > 0 or dz > 0 else -min(x - rx0, rx1 - x, z - rz0, rz1 - z)
            s += wob
            hh = max(top - g, 0.4) + sink
            body = 1.1 * hh    # (steep: ~48 deg at its middle, too steep to walk up, like the old banks)
            foot = body + 2.6  # (the gentle skirt)
            t1 = (s + crest) / body
            t2 = (s + crest) / foot
            y = g - sink + hh * (0.84 * (1.0 - smooth01(t1)) + 0.16 * (1.0 - smooth01(t2)))
            if best is None:
                best = y
            else:   # (a smooth max: no crease where two boxes' slopes meet)
                k = 0.5
                hk = max(k - abs(best - y), 0.0) / k
                best = max(best, y) + hk * hk * k * 0.25
        best += 0.06 * math.sin(x * 1.3 + ph[2]) * math.sin(z * 1.9 + ph[3])
        return best, g
    nx, nz = max(4, int((x1 - x0) / step)), max(4, int((z1 - z0) / step))
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    zs = [z0 + (z1 - z0) * j / nz for j in range(nz + 1)]
    H = [[height(x, z) for x in xs] for z in zs]
    under = lambda hs: all(h < g - 0.02 for h, g in hs)   # (wholly under the ground: left out)
    if smooth:
        smooth_sheet(b, xs, zs, H, world, height, under)
    else:   # (its collision: plain triangles)
        for j in range(nz):
            for i in range(nx):
                ij = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
                if under([H[c][a] for a, c in ij]):
                    continue
                q = [(world(xs[a], zs[c])[0], H[c][a][0], world(xs[a], zs[c])[1]) for a, c in ij]
                for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                    b.poly(list(tri), (0.0, 1.0, 0.0), GROUND, uv_world(2.0))
    for _ in range(5):   # a few stones round its foot
        sz = rng.uniform(0.2, 0.45)
        r = rng.choice(rects)
        lx = rng.uniform(r[0], r[1])
        lz = rng.choice((r[2] - 2.2, r[3] + 2.2)) + rng.uniform(-0.4, 0.4)
        wx, wz = world(lx, lz)
        y = max(height(lx, lz)[0], ground(wx, wz))
        rock(b, (wx, y + sz * 0.25, wz), (sz * 1.3, sz, sz), rng.uniform(0, 180), rng, "dbr_granite")


# ------------------------------------------------------------------------------------------------ rocks
def draw_rocks(b, piece, rng):
    look = piece["look"]
    for bi, box in enumerate(piece["boxes"]):
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        f0 = len(b.faces)
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
        shape(b, f0, bi)


# ------------------------------------------------------------------------------------------------ bushes
BUSHES_IN_MODEL = False


def draw_bush(b, piece, rng):
    """A bush filling its (solid) box: a big rounded body with smaller clumps bulging out of it, so it reads round
    from every side. Looks: b leafy green, c dark evergreen (taller, pointed), d in flower.
    (Since 2026-10-18 the bushes are drawn by scripts/bushes.gd instead, see-through and swaying: BUSHES_IN_MODEL.)"""
    if not BUSHES_IN_MODEL:
        return
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
    # (owner 2026-10-18: "make it nicer and more 3d, the roof is floating") A newsstand on a low plinth: corner posts,
    # a two-step roof sitting right on the walls with a sign board on top, a framed hatch with the shutter rolled up
    # under a little awning, a counter on brackets, a side door, a paper rack, posters.
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W, H, D = box["size"]
    skin = {"b": "dbr_dmp_g", "c": "dbr_dmp_b", "d": "dbr_dmp_b"}[piece["look"]]
    awn = {"b": "dbr_awn_r", "c": "dbr_awn_g", "d": "dbr_awn_b"}[piece["look"]]
    base, top = 0.15, H - 0.35          # the walls run from the plinth to the roof
    f.box((0, base / 2, 0), (W + 0.2, base, D + 0.2), style=no_bottom("concrete", 1.0))                      # plinth
    f.box((0, (base + top) / 2, 0), (W - 0.1, top - base, D - 0.1), style=no_bottom(skin, 2.0))
    for sx in (-1, 1):   # corner posts
        for sz in (-1, 1):
            f.box((sx * (W / 2 - 0.06), (base + top) / 2, sz * (D / 2 - 0.06)), (0.14, top - base, 0.14),
                  style=no_bottom("trim_dark", 1.0))
    f.box((0, top + 0.1, 0), (W + 0.6, 0.2, D + 0.6), style=flat("trim_dark", 1.0))                          # roof
    f.box((0, top + 0.25, 0), (W - 0.1, 0.1, D - 0.1), style=no_bottom("trim_dark", 1.0))
    f.box((0, top + 0.5, D / 2 - 0.25), (W - 0.3, 0.4, 0.08), style=no_bottom(awn, 1.2))                      # sign
    f.box((0, top + 0.5, D / 2 - 0.2), (W - 0.6, 0.18, 0.02), style=flat("dbr_paper", 1.0))
    for sx in (-1, 1):
        f.box((sx * (W / 2 - 0.5), top + 0.32, D / 2 - 0.3), (0.06, 0.1, 0.06), style=no_bottom("trim_dark", 1.0))
    # The hatch on the square side (south, +z): a frame round a dark inside, the shutter rolled up at the top
    hw, y0, y1, fz = W - 0.7, 1.05, 2.05, D / 2 - 0.05
    f.box((0, (y0 + y1) / 2, fz + 0.005), (hw, y1 - y0, 0.02), style=flat("black", 1.0))
    for sx in (-1, 1):
        f.box((sx * (hw / 2 + 0.05), (y0 + y1) / 2, fz + 0.04), (0.1, y1 - y0 + 0.2, 0.1), style=no_bottom("trim_dark", 1.0))
    f.box((0, y1 + 0.12, fz + 0.08), (hw + 0.2, 0.2, 0.2), style=no_bottom("steel_light", 1.0))           # shutter roll
    f.box((0, y0 - 0.05, fz + 0.25), (hw + 0.3, 0.06, 0.5), style=no_bottom("trim_dark", 1.0))          # counter
    for sx in (-1, 1):
        f.box((sx * (hw / 2 - 0.1), y0 - 0.23, fz + 0.15), (0.05, 0.3, 0.25), style=no_bottom("trim_dark", 1.0))
    f.box((0, y1 + 0.3, fz + 0.35), (hw + 0.3, 0.04, 0.75), pitch=-14, style=lambda n, m, q: (awn, uv_world(1.2)))
    for k in range(6):   # the papers on the counter
        f.box((-hw / 2 + 0.2 + k * (hw - 0.4) / 5, y0 + 0.0, fz + 0.28), (0.24, 0.03, 0.32), yaw=rng.uniform(-10, 10),
              style=no_bottom(rng.choice(("dbr_paper", "awn_r_flat", "paper_green", "dbr_paper")), 1.0))
    for k in range(3):   # magazines pegged up inside the hatch
        f.box((-0.6 + k * 0.6, 1.65, fz + 0.025), (0.4, 0.5, 0.02), style=flat(rng.choice(("dbr_paper", "hz_flat")), 1.0))
    # A side door (east), a paper rack (west), posters
    f.box((W / 2 - 0.03, base + 0.95, -0.3), (0.06, 1.9, 0.8), style=no_bottom("trim_dark", 1.0))
    f.box((W / 2 + 0.01, base + 0.95, -0.3), (0.02, 1.7, 0.65), style=flat(skin, 2.0))
    f.box((W / 2 + 0.04, base + 0.95, -0.02), (0.05, 0.05, 0.14), style=no_bottom("steel_light", 1.0))
    rx = -W / 2 - 0.3
    for zz in (-0.45, 0.45):
        f.box((rx, 0.6, zz), (0.05, 1.2, 0.05), style=no_bottom("trim_dark", 1.0))
    for k in range(3):
        f.box((rx - 0.05 + k * 0.03, 0.4 + k * 0.32, 0), (0.25, 0.04, 0.95), style=no_bottom("trim_dark", 1.0))
        f.box((rx - 0.05 + k * 0.03, 0.47 + k * 0.32, 0), (0.22, 0.1, 0.85), style=no_bottom(rng.choice(("dbr_paper", "hz_flat", "awn_r_flat")), 1.0))
    for k in range(2):
        f.box((-0.5 + k * 0.9, 1.3 + k * 0.05, -D / 2 + 0.04), (0.5, 0.7, 0.02),
              style=flat(rng.choice(("dbr_paper", "awn_r_flat", "hz_flat")), 1.0))
    for _ in range(4):   # newspapers blown about
        b.box(f.p(rng.uniform(-2.5, 2.5), 0.02, rng.uniform(1.5, 3.5)), (0.4, 0.01, 0.3), yaw=rng.uniform(0, 180),
              style=no_bottom("dbr_paper", 1.0))


# ------------------------------------------------------------------------------------------------ the trench
# (owner 2026-10-18: "texture that as dirt and give it like little rough mini bumps") Every face of the trench's earth
# boxes is cut into ~0.3 m cells whose inner corners are pushed in or out a few cm (by world position, so the boxes
# meet without gaps; their edges stay put), plus clods and stones along the floor and a few roots in the walls.
def _bump(p, amount=0.1):
    h = math.sin(p[0] * 12.9898 + p[1] * 78.233 + p[2] * 37.719) * 43758.5453
    return (h - math.floor(h) - 0.5) * 2 * amount


def rough_box(b, box, mat, cell=0.3):
    (cx, cy, cz), (sx, sy, sz) = box["pos"], box["size"]
    yaw, pitch = box["yaw"], box["pitch"]
    P = lambda x, y, z: v_add(rot((x, y, z), yaw, pitch), (cx, cy, cz))
    h = (sx / 2, sy / 2, sz / 2)
    for axis in range(3):
        for sgn in (-1, 1):
            if axis == 1 and sgn < 0:
                continue
            u_ax, v_ax = [a for a in range(3) if a != axis]
            nu, nv = max(1, round(2 * h[u_ax] / cell)), max(1, round(2 * h[v_ax] / cell))
            normal = rot(tuple(float(sgn) if a == axis else 0.0 for a in range(3)), yaw, pitch)
            grid = {}
            for i in range(nu + 1):
                for j in range(nv + 1):
                    q = [0.0, 0.0, 0.0]
                    q[axis] = sgn * h[axis]
                    q[u_ax] = -h[u_ax] + 2 * h[u_ax] * i / nu
                    q[v_ax] = -h[v_ax] + 2 * h[v_ax] * j / nv
                    p = P(*q)
                    if 0 < i < nu and 0 < j < nv:
                        p = v_add(p, v_scale(normal, _bump(p)))
                    grid[(i, j)] = p
            inside = v_sub(P(0, 0, 0), v_scale(normal, 5.0))
            for i in range(nu):
                for j in range(nv):
                    a, c, d, e = grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]
                    tri(b, a, c, d, mat, inside)
                    tri(b, a, d, e, mat, inside)


def draw_trench(b, piece, rng):
    for box in piece["boxes"]:
        (cx, cy, cz), (sx, sy, sz) = box["pos"], box["size"]
        if sy > 0.5 and box["pitch"] == 0:   # a wall: its top 6 cm over the ground (level with it, the grass flickered through)
            box = dict(box, pos=(cx, cy + 0.03, cz), size=(sx, sy + 0.06, sz))
        rough_box(b, box, "dbr_earth")
    floors = [bx for bx in piece["boxes"] if bx["size"][1] < 0.5 and bx["pitch"] == 0]
    for fl in floors:   # clods and stones on the floor, mostly along the walls
        (cx, cy, cz), (sx, sy, sz) = fl["pos"], fl["size"]
        top = cy + sy / 2
        for _ in range(int(sx * sz * 2.5)):
            x = cx + rng.uniform(-sx / 2, sx / 2)
            z = cz + rng.uniform(-sz / 2, sz / 2)
            if sx > sz:
                z = cz + rng.choice((-1, 1)) * rng.uniform(sz / 2 - 0.5, sz / 2 - 0.1)
            else:
                x = cx + rng.choice((-1, 1)) * rng.uniform(sx / 2 - 0.5, sx / 2 - 0.1)
            w = rng.uniform(0.12, 0.3)
            rock(b, (x, top + w * 0.25, z), (w, w * 0.6, w * rng.uniform(0.7, 1.2)), rng.uniform(0, 90), rng,
                 rng.choice(("dbr_earth", "dbr_earth", "dbr_granite")), jitter=0.15, chamfer=0.35, taper=0.8)
    trench_timber(b, piece, floors, rng)


def trench_timber(b, piece, floors, rng):
    """(Outdoor step 8) The trench's walls held up with timber: posts every 1.6 m and planks (b), corrugated sheets (c)
    or a mix of both (d) up to a hand below the lip, so the earth shows at the top; duckboards down the floor."""
    def on_floor(x, z):
        return any(abs(x - f["pos"][0]) < f["size"][0] / 2 and abs(z - f["pos"][2]) < f["size"][2] / 2 for f in floors)
    seen = set()
    look = piece["look"]
    for box in piece["boxes"]:
        (cx, cy, cz), (sx, sy, sz) = box["pos"], box["size"]
        key = (round(cx, 2), round(cz, 2), round(sx, 2), round(sz, 2))
        if sy < 0.5 or box["pitch"] != 0 or key in seen:
            continue
        seen.add(key)
        along_x = sx > sz
        L = sx if along_x else sz
        sgn = 0
        for s_ in (-1, 1):
            px, pz = (cx, cz + s_ * 0.4) if along_x else (cx + s_ * 0.4, cz)
            if on_floor(px, pz):
                sgn = s_
        if not sgn or L < 0.35:
            continue
        y0, y1 = cy - sy / 2 + 0.3, cy + sy / 2 - 0.16      # (the floor's top, a hand under the lip)
        face = (cz if along_x else cx) + sgn * 0.15

        def P(t, off):   # t along the wall, off out from its face into the trench
            return (cx + t, 0.0, face + sgn * off) if along_x else (face + sgn * off, 0.0, cz + t)
        sheets = look == "c" or (look == "d" and rng.random() < 0.5)
        h = y1 - y0
        if sheets:
            n = max(1, round(L / 1.0))
            for k in range(n):
                t = -L / 2 + L * (k + 0.5) / n
                p = P(t, 0.03)
                lean = rng.uniform(-2, 2)
                b.box((p[0], y0 + h / 2, p[2]), (L / n + 0.04 if along_x else 0.03, h, 0.03 if along_x else L / n + 0.04),
                      pitch=lean if not along_x else 0.0, style=flat(rng.choice(("shed_metal", "shed_metal", "dbr_cont_g")), 1.0))
        else:
            rows = max(1, int(h / 0.21))
            for r in range(rows):
                p = P(rng.uniform(-0.05, 0.05), 0.03)
                yy = y0 + (r + 0.5) * h / rows
                b.box((p[0], yy, p[2]), (L if along_x else 0.05, h / rows - 0.025, 0.05 if along_x else L),
                      style=flat(rng.choice(("wood", "wood", "wood_dark", "wood_light")), 1.0))
        n = max(1, int(L / 1.6))
        for k in range(n + 1):
            if L < 1.2 and k > 0:
                break
            t = (-L / 2 + 0.1 + (L - 0.2) * k / n) if L >= 1.2 else 0.0
            p = P(t, 0.1)
            b.box((p[0], y0 + (h + 0.2) / 2, p[2]), (0.11, h + 0.2, 0.11), style=no_bottom("wood_dark", 1.0))
    for fl in floors:   # duckboards: two runners, slats across every 0.3 m
        (cx, cy, cz), (sx, sy, sz) = fl["pos"], fl["size"]
        top = cy + sy / 2
        along_x = sx > sz
        L = (sx if along_x else sz) - 0.6
        for o in (-0.28, 0.28):
            c = (cx, top + 0.03, cz + o) if along_x else (cx + o, top + 0.03, cz)
            b.box(c, (L, 0.06, 0.07) if along_x else (0.07, 0.06, L), style=no_bottom("wood_dark", 1.0))
        n = int(L / 0.3)
        for k in range(n):
            t = -L / 2 + (k + 0.5) * L / n
            if rng.random() < 0.06:   # (a slat gone)
                continue
            c = (cx + t, top + 0.075, cz) if along_x else (cx, top + 0.075, cz + t)
            b.box(c, (0.16, 0.03, 0.75) if along_x else (0.75, 0.03, 0.16), yaw=rng.uniform(-3, 3),
                  style=no_bottom(rng.choice(("wood", "wood_light", "wood")), 1.0))


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


# ------------------------------------------------------------------------------------------------ power lines
# (outdoor step 4) Looks: b a wooden pole with one crossarm and three insulators; c the same with a second, lower arm
# carrying two telephone wires and a step-bolted, more weathered pole; d a tapered concrete pole with a steel arm.
# A transformer hangs on some poles. Wires sag between poles (make_outdoor draws each one from the poles' markers).
WIRES = {"b": ((-0.8, 7.74), (0.8, 7.74), (0.0, 8.2)),
         "c": ((-0.8, 7.74), (0.8, 7.74), (0.0, 8.2), (-0.5, 6.84), (0.5, 6.84)),
         "d": ((-0.85, 7.84), (0.85, 7.84), (0.0, 8.28))}


def insulator(b, f, x, y, look, rng, small=False):
    """A pin insulator standing on an arm (or the pole top) at local (x, y): stacked skirts on a steel pin."""
    mat = "dbr_porc" if small or look == "d" else "dbr_ins_g"
    cyl(b, f.p(x, y + 0.04, 0), 0.015, 0.08, "trim_dark", sides=4, yaw=f.yaw, caps=False)
    for k, r in enumerate((0.07, 0.055) if small else (0.085, 0.07, 0.05)):
        cyl(b, f.p(x, y + 0.08 + k * 0.05, 0), r, 0.045, mat, sides=6, yaw=f.yaw)


def pole_parts(b, f, look, rng, transformer=False, top=8.0, stump=False, shaft_from=0.0):
    """A pole in frame f (foot on the ground, local x along the arms, z along the line). top: where it ends;
    shaft_from: where its shaft starts (a snapped pole's fallen top)."""
    mid, ln = (shaft_from + top) / 2, top - shaft_from
    if look == "d":
        rock(b, f.p(0, mid, 0), (0.3 - 0.1 * shaft_from / 8, ln, 0.3 - 0.1 * shaft_from / 8), f.yaw, rng, "dbr_conc",
             jitter=0.0, chamfer=0.08, taper=0.62 if not stump else 0.95)
    else:
        cyl(b, f.p(0, mid, 0), 0.15 if look == "c" else 0.14, ln, "dbr_pole", sides=8, yaw=f.yaw, tile=1.0)
        if shaft_from == 0.0:
            cyl(b, f.p(0, 0.25, 0), 0.165, 0.5, "dbr_earth", sides=8, yaw=f.yaw, caps=False)   # (wet, dirty foot)
    if stump:   # splintered top
        mat = "dbr_pole" if look != "d" else "dbr_conc"
        for k in range(5):
            a = k * 72 + rng.uniform(-20, 20)
            f.box((0.08 * math.sin(math.radians(a)), top + 0.12 + rng.uniform(0, 0.15), 0.08 * math.cos(math.radians(a))),
                  (0.06, 0.3 + rng.uniform(0, 0.2), 0.05), yaw=a, pitch=rng.uniform(-12, 12), style=flat(mat, 1.0))
        if look == "d":
            for k in range(3):   # (bent rebar out of the broken concrete)
                f.box((rng.uniform(-0.08, 0.08), top + 0.25, rng.uniform(-0.08, 0.08)), (0.025, 0.5, 0.025),
                      pitch=rng.uniform(-30, 30), yaw=rng.uniform(0, 180), style=flat("trim_dark", 1.0))
        return
    if look == "d":
        f.box((0, 7.6, 0), (1.95, 0.1, 0.1), style=flat("trim_dark", 1.0))                      # steel channel arm
        for sx in (-1, 1):
            _rope(b, f.p(sx * 0.55, 7.55, 0.0), f.p(0, 7.1, 0.0))                                # struts
        f.box((0, 8.0, 0), (0.12, 0.08, 0.12), style=flat("trim_dark", 1.0))
        for x, y in ((-0.85, 7.65), (0.85, 7.65), (0.0, 8.04)):
            insulator(b, f, x, y, look, rng)
    else:
        f.box((0, 7.475, 0), (1.8, 0.12, 0.13), style=flat("wood_dark", 1.0))                     # crossarm
        for sx in (-1, 1):   # braces
            _rope(b, f.p(sx * 0.5, 7.41, 0.09), f.p(0, 6.95, 0.09))
        for x, y in ((-0.8, 7.535), (0.8, 7.535), (0.0, top)):
            insulator(b, f, x, y, look, rng)
        if look == "c":
            f.box((0, 6.6, 0), (1.2, 0.1, 0.11), style=flat("wood_dark", 1.0))                    # telephone arm
            for x in (-0.5, 0.5):
                insulator(b, f, x, 6.65, look, rng, small=True)
            if shaft_from < 2.0:
                for k in range(9):   # step bolts
                    f.box(((-1) ** k * 0.17, 2.6 + k * 0.45, 0.0), (0.12, 0.025, 0.025), style=flat("trim_dark", 1.0))
                f.box((0, 1.8, 0.152), (0.14, 0.18, 0.01), style=flat("hz_flat", 1.0))            # number plate
    if transformer:   # a pole-top transformer can on a bracket, leads up to the arm
        z = -0.42
        f.box((0, 6.0, -0.2), (0.12, 0.12, 0.3), style=flat("trim_dark", 1.0))
        cyl(b, f.p(0, 6.0, z), 0.3, 0.85, "dbr_xf", sides=10, yaw=f.yaw)
        cyl(b, f.p(0, 6.46, z), 0.32, 0.06, "dbr_xf", sides=10, yaw=f.yaw)
        for sx in (-1, 1):
            cyl(b, f.p(sx * 0.13, 6.56, z), 0.035, 0.14, "dbr_porc", sides=6, yaw=f.yaw)
            _rope(b, f.p(sx * 0.13, 6.63, z), f.p(sx * 0.8, (7.62 if look != "d" else 7.72), 0.0))
        for sx in (-1, 1):   # cooling fins
            f.box((sx * 0.31, 5.8, z), (0.02, 0.3, 0.2), style=flat("dbr_xf", 1.0))


def draw_pole(b, piece, rng):
    box = piece["boxes"][0]
    f = frame_of(b, box)
    pole_parts(b, f, piece["look"], rng, transformer=len(piece["boxes"]) > 2)
    pole_poster(b, f, piece["look"], random.Random(f"poster {piece['seed']}"))


def draw_pole_snap(b, piece, rng):
    """A shelled pole: the stump, and the top lying toward the road with its crossarm and insulators."""
    stump, fallen = piece["boxes"][0], piece["boxes"][1]
    look = piece["look"]
    f = frame_of(b, stump)
    pole_parts(b, f, look, rng, top=2.6, stump=True)
    (x, y, z) = stump["pos"]
    foot = (x, y - stump["size"][1] / 2, z)
    fall = fallen["yaw"]
    v0, n0 = len(b.verts), len(b.normals)
    pole_parts(b, Frame(b, (0, 0, 0), 0), look, rng, shaft_from=2.75)
    # (lay it down: turned 90 degrees about x, so the pole runs along +z, toward the road; then turned and placed,
    # each point on whatever is under it: ground or road)
    lay = lambda q: (q[0], -q[2], q[1])
    for i in range(v0, len(b.verts)):
        q = lay(b.verts[i])
        p = v_add(rot((q[0], q[1] + 0.15, q[2] + 0.3), fall, 0.0), (foot[0], 0.0, foot[2]))
        b.verts[i] = (p[0], p[1] + _rest(foot, fall, q[2] + 0.3), p[2])
    for i in range(n0, len(b.normals)):
        b.normals[i] = rot(lay(b.normals[i]), fall, 0.0)
    bits(b, foot, 0.5, 4, rng, ("dbr_pole" if look != "d" else "dbr_conc", "rubble_core"))


def _rest(foot, yaw, d):
    """The height a straight fallen pole rests at, d m along it: lying from its foot to where it lands."""
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    far = max(surface(foot[0] + s_ * t, foot[2] + c * t) for t in (6.5, 7.5, 8.3))
    near = surface(foot[0] + s_ * 3.0, foot[2] + c * 3.0)
    t = min(max((d - 3.0) / 5.3, 0.0), 1.0)
    return near + (far - near) * t


def _wire_pt(marker, ox, oy, yaw=None):
    (x, y, z), s = marker["pos"], marker["size"]
    foot = (x, y - s[1] / 2, z)
    return v_add(rot((ox, oy, 0.0), marker["yaw"] if yaw is None else yaw, 0.0), foot)


def _sag_line(b, p0, p1, sag, n=10, ground_at=None, mat="trim_dark"):
    pts = []
    for k in range(n + 1):
        t = k / n
        p = v_add(p0, v_scale(v_sub(p1, p0), t))
        p = (p[0], p[1] - 4 * sag * t * (1 - t), p[2])
        pts.append(p)
    for a, c in zip(pts, pts[1:]):
        _wire_seg(b, a, c, mat)


def _wire_seg(b, a, c, mat="trim_dark"):
    d = v_sub(c, a)
    L = math.sqrt(dot(d, d))
    if L < 1e-4:
        return
    yaw = math.degrees(math.atan2(d[0], d[2]))
    pitch = -math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    u = v_scale(d, 1.0 / L)
    b.box(v_scale(v_add(a, c), 0.5), (0.035, 0.035, L + 0.01), yaw=yaw, pitch=pitch,   # (no end caps: hidden)
          style=lambda n, m, q: None if abs(dot(n, u)) > 0.9 else (mat, uv_world(1.0)))


def draw_wire(b, piece, rng):
    span, ma, mb_ = piece["boxes"][0], piece["boxes"][1], piece["boxes"][2]
    for ox, oy in WIRES[piece["look"]]:
        p0, p1 = _wire_pt(ma, ox, oy), _wire_pt(mb_, ox, oy)
        L = math.hypot(p1[0] - p0[0], p1[2] - p0[2])
        _sag_line(b, p0, p1, 0.022 * L + rng.uniform(-0.05, 0.1), n=12)


def draw_wire_down(b, piece, rng):
    """From the standing pole's arm, the wires hang down steeply, then lie in the road to the fallen top."""
    span, ma, ms = piece["boxes"][0], piece["boxes"][1], piece["boxes"][2]
    fall = ms["yaw"]
    (x, y, z), s = ms["pos"], ms["size"]
    foot = (x, y - s[1] / 2, z)
    for ox, oy in WIRES[piece["look"]]:
        p0 = _wire_pt(ma, ox, oy)
        end = v_add(rot((ox, 0.0, oy + 0.3), fall, 0.0), foot)
        end = (end[0], _rest(foot, fall, oy + 0.3) + 0.16, end[2])
        pts, n = [], 18
        for k in range(n + 1):
            t = k / n
            px, pz = p0[0] + (end[0] - p0[0]) * t, p0[2] + (end[2] - p0[2]) * t
            lie = surface(px, pz) + 0.04 + rng.uniform(0, 0.03)
            hy = p0[1] * (1 - t) ** 3 + end[1] * t ** 3
            pts.append((px + rng.uniform(-0.1, 0.1) * (0 < k < n), max(lie, hy), pz + rng.uniform(-0.1, 0.1) * (0 < k < n)))
        for a, c in zip(pts, pts[1:]):
            _wire_seg(b, a, c)


# ------------------------------------------------------------------------------------------------ road signs
# (outdoor round 3) Looks: b European enamel signs (yellow town board, its name struck through on the back for
# leaving, round speed limits, white finger boards), c North American (green town and guide signs, white speed limit
# boards), d old and rural (painted wooden boards and fingerposts, rusty enamel). Stop signs are octagons in all three.
# The signs' pictures are one decal atlas for every chunk (art_source/textures/outdoor_decals.png, 32 px a metre).
DIR_NAMES = ("HILLSIDE", "CHURCH", "STATION", "JUNKYARD", "WOODS")   # (gen DIR_NAMES, in road order)
DECALS = mb.Atlas(256)


def _say(c, y, s, col, scale=1):
    w = Canvas.text_width(s, scale)
    assert w + 2 <= c.w and y >= 0 and y + 5 * scale <= c.h, f"sign text {s!r} doesn't fit {c.w}x{c.h}"
    assert (c.w - w) % 2 == 0, f"{s!r} can't be centred in {c.w} px: change the width"
    c.ctext(0, c.w, y, s, col, scale)


def _fit_w(s, scale, pad):
    """A width that centres s exactly with at least pad px each side."""
    w = Canvas.text_width(s, scale) + 2 * pad
    return w


def _ring(c, col, ring, width=2):
    r = c.w / 2
    for y in range(c.h):
        for x in range(c.w):
            d = math.hypot(x + 0.5 - r, y + 0.5 - r)
            if d > r - width - 0.3:
                c.put(x, y, ring)


def _rusty(c, rng, n=6):
    c.blotch(["rust", "iron_dark"], n, rng, size=(1, 3))


def sign_decals():
    rng = random.Random("signs")
    a = DECALS

    def town(look, back):
        def paint(c):
            if look == "b":
                c.rect(0, 0, c.w, c.h, "sg_yel")
                c.frame(1, 1, c.w - 1, c.h - 1, "sg_blk")
                _say(c, 6, "BLOXOV", "sg_blk", 2)
                if back:   # (leaving: the name struck through in red)
                    for x in range(4, c.w - 4):
                        y = 3 + (x - 4) * (c.h - 7) // (c.w - 8)
                        c.rect(x, y, x + 1, y + 2, "sg_red")
            elif look == "c":
                c.rect(0, 0, c.w, c.h, "sg_grn")
                c.frame(1, 1, c.w - 1, c.h - 1, "sg_wht")
                _say(c, 13, "BLOXOV", "sg_wht", 2)
                _say(c, 4, "POP 2140", "sg_wht")
            else:
                c.rect(0, 0, c.w, c.h, "sg_wood")
                for y in range(0, c.h, 6):
                    c.rect(0, y, c.w, y + 1, "sg_wood_dk")
                _say(c, 4, "BLOXOV", "sg_cream", 2)
                c.blotch(["sg_wood_dk"], 6, rng, size=(1, 3))
        return paint

    for look, w, h in (("b", 54, 22), ("c", 64, 30), ("d", 54, 18)):
        a.add(f"town_{look}", w, h, town(look, False))
        a.add(f"town_{look}_back", w, h, town(look, True))

    def stop(look):
        def paint(c):
            c.rect(0, 0, c.w, c.h, "sg_red")
            c.frame(0, 0, c.w, c.h, "sg_wht")
            _say(c, 10, "STOP", "sg_wht")
            if look == "d":
                _rusty(c, rng)
        return paint
    for look in "bcd":
        a.add(f"stop_{look}", 25, 25, stop(look))

    def speed(look, v):
        def paint(c):
            if look == "c":
                c.rect(0, 0, c.w, c.h, "sg_wht")
                c.frame(1, 1, c.w - 1, c.h - 1, "sg_blk")
                _say(c, 25, "SPEED", "sg_blk")
                _say(c, 18, "LIMIT", "sg_blk")
                _say(c, 2, v, "sg_blk", 3)
            else:
                c.rect(0, 0, c.w, c.h, "sg_wht")
                _ring(c, "sg_wht", "sg_red", 3)
                _say(c, 5, v, "sg_blk", 2)
                if look == "d":
                    _rusty(c, rng, 8)
        return paint
    for look in "bcd":
        for v in ("50", "80"):
            a.add(f"speed_{look}_{v}", 25 if look == "c" else 22, 32 if look == "c" else 22, speed(look, v))

    def finger(look, name):
        def paint(c):
            bg, ink = {"b": ("sg_wht", "sg_blk"), "c": ("sg_grn", "sg_wht"), "d": ("sg_wood", "sg_cream")}[look]
            c.rect(0, 0, c.w, c.h, bg)
            if look != "d":
                c.frame(0, 0, c.w, c.h, ink)
            else:
                c.blotch(["sg_wood_dk"], 4, rng, size=(1, 2))
            w = Canvas.text_width(name)
            c.text(4, 3, name, ink)
        return paint
    def xbuck(word):
        def paint(c):
            c.rect(0, 0, c.w, c.h, "sg_wht")
            c.frame(0, 0, c.w, c.h, "sg_blk")
            _say(c, 2, word, "sg_blk")
        return paint
    for word in ("RAILROAD", "CROSSING"):
        a.add(f"xbuck_{word}", 41 if word == "RAILROAD" else 42, 9, xbuck(word))

    def manhole(c):
        c.rect(0, 0, c.w, c.h, "iron_dark")
        r = c.w / 2
        for y in range(c.h):
            for x in range(c.w):
                d = math.hypot(x + 0.5 - r, y + 0.5 - r)
                if d > r - 1.5 or (abs(d - r * 0.55) < 0.6):
                    c.put(x, y, "iron")
                elif (x + y) % 4 == 0 and d < r * 0.5:
                    c.put(x, y, "black")
        c.blotch(["rust"], 3, rng, size=(1, 2))
    a.add("manhole", 22, 22, manhole)

    def drain(c):
        c.rect(0, 0, c.w, c.h, "iron")
        for y in range(2, c.h - 2, 3):
            c.rect(2, y, c.w - 2, y + 2, "black")
        c.blotch(["rust"], 2, rng, size=(1, 2))
    a.add("drain", 14, 22, drain)

    for look in "bcd":
        for name in DIR_NAMES:
            a.add(f"dir_{look}_{name}", Canvas.text_width(name) + 12, 11, finger(look, name))


def _plate(b, f, c, w, h, front, back=None, back_mat="metal", t=0.03, shape=None):
    """A sign plate in frame f at local c (w x h m, facing local +z): front/back decal regions. shape: corner points
    (local x, y round c) of an octagon or circle instead of a rectangle."""
    if shape is None:
        shape = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    nf = rot((0, 0, 1), f.yaw, 0.0)
    for side, region in ((1, front), (-1, back)):
        pts = [f.p(c[0] + x * side, c[1] + y, c[2] + side * t / 2) for x, y in shape]
        if region:
            b.poly(pts, v_scale(nf, side), "decals", mb.uv_fit(DECALS.regions[region]))
        else:
            b.poly(pts, v_scale(nf, side), back_mat, uv_world(1.0))
    for (x0, y0), (x1, y1) in zip(shape, shape[1:] + shape[:1]):   # the edge
        q = [f.p(c[0] + x0, c[1] + y0, c[2] - t / 2), f.p(c[0] + x1, c[1] + y1, c[2] - t / 2),
             f.p(c[0] + x1, c[1] + y1, c[2] + t / 2), f.p(c[0] + x0, c[1] + y0, c[2] + t / 2)]
        n = rot(norm(((x0 + x1) / 2, (y0 + y1) / 2, 0.0)), f.yaw, 0.0)
        b.poly(q, n, back_mat, uv_world(1.0))


def _post(b, f, look, x=0.0, h=2.6):
    if look == "d":
        f.box((x, h / 2, 0), (0.1, h, 0.1), style=flat("dbr_pole", 1.0))
    elif look == "c":
        f.box((x, h / 2, 0), (0.07, h, 0.05), style=flat("metal", 1.0))
    else:
        cyl(b, f.p(x, h / 2, 0), 0.04, h, "steel_light", sides=6, yaw=f.yaw)


def _poly_shape(n, r, turn=0.0):
    return [(r * math.cos(math.radians(turn + 360 * k / n)), r * math.sin(math.radians(turn + 360 * k / n))) for k in range(n)]


def draw_sign(b, piece, rng):
    kind, look = piece["kind"], piece["look"]
    post = piece["boxes"][0]
    f = frame_of(b, post)
    extra = len(piece["boxes"]) - 1
    if kind == "sign_town":
        w, h = {"b": (1.69, 0.69), "c": (2.0, 0.94), "d": (1.69, 0.56)}[look]
        for x in (-0.7, 0.7):   # (gen: the two posts' collision)
            _post(b, f, look, x, 2.3 + h / 2)
        f2 = Frame(b, f.p(0, 0, 0.06), f.yaw)
        _plate(b, f2, (0, 2.0 + h / 2, 0), w, h, f"town_{look}", f"town_{look}_back" if look == "b" else None,
               back_mat="metal" if look != "d" else "dbr_pole")
    elif kind == "sign_stop":
        _post(b, f, look)
        f2 = Frame(b, f.p(0, 0, 0.05), f.yaw)
        _plate(b, f2, (0, 2.2, 0), 0.78, 0.78, f"stop_{look}", shape=_poly_shape(8, 0.4, 22.5))
    elif kind == "sign_speed":
        v = "80" if extra else "50"
        _post(b, f, look)
        f2 = Frame(b, f.p(0, 0, 0.05), f.yaw)
        if look == "c":
            _plate(b, f2, (0, 2.1, 0), 0.78, 1.0, f"speed_c_{v}")
        else:
            _plate(b, f2, (0, 2.2, 0), 0.69, 0.69, f"speed_{look}_{v}", shape=_poly_shape(16, 0.345))
    elif kind == "sign_rail":   # a crossbuck over a pair of warning lights (look-independent: the owner's C)
        _post(b, f, "c", h=3.4)
        for word, roll in (("RAILROAD", 40.0), ("CROSSING", -40.0)):
            g = Frame(b, f.p(0, 0, 0.05), f.yaw)
            shape = [(-0.64, -0.14), (0.64, -0.14), (0.64, 0.14), (-0.64, 0.14)]
            c_, s_ = math.cos(math.radians(roll)), math.sin(math.radians(roll))
            shape = [(x * c_ - y * s_, x * s_ + y * c_) for x, y in shape]
            _plate(b, Frame(b, g.p(0, 0, 0.02 if roll > 0 else 0.0), f.yaw), (0, 2.95, 0), 1.28, 0.28,
                   f"xbuck_{word}", shape=shape)
        f.box((0, 2.2, 0.06), (1.1, 0.08, 0.06), style=flat("trim_dark", 1.0))
        for x in (-0.45, 0.45):
            cyl(b, f.p(x, 2.2, 0.14), 0.15, 0.06, "black", sides=10, axis="z", yaw=f.yaw)
            cyl(b, f.p(x, 2.2, 0.18), 0.11, 0.03, "sg_red_flat", sides=10, axis="z", yaw=f.yaw)
            f.box((x, 2.37, 0.2), (0.32, 0.04, 0.16), style=flat("black", 1.0))   # hoods
        f.box((0, 1.3, 0.06), (0.3, 0.4, 0.2), style=flat("trim_dark", 1.0))      # the bell box
    elif kind == "sign_dir":
        name = DIR_NAMES[extra]
        _post(b, f, look, h=2.6)
        reg = DECALS.regions[f"dir_{look}_{name}"]
        L = (Canvas.text_width(name) + 12) / 32.0
        h = 11 / 32.0
        # (local +z points up the road it names: the board runs along it from the post, its point at the far end)
        g = Frame(b, f.at, f.yaw - 90)   # (g's +x = up the road)
        shape = [(-0.08, -h / 2), (L - 0.16, -h / 2), (L - 0.08 + 0.0, 0.0), (L - 0.16, h / 2), (-0.08, h / 2)]
        g.box((0, 2.75, 0), (0.12, 0.08, 0.12), style=flat("trim_dark", 1.0))
        _plate(b, g, (0.0, 2.35, 0.0), L, h, f"dir_{look}_{name}", f"dir_{look}_{name}",
               back_mat="metal" if look != "d" else "wood_dark", shape=shape)


# ------------------------------------------------------------------------------------------------ kerbs, manholes, drains
# (outdoor round 3) Along the town's roads: a concrete kerb on both edges (none at junctions, car park ways in and
# where a door's path meets the road), iron manhole covers in the lanes and drain grates in the gutters. Drawn from
# the road ribbons in terrain.json, each in the chunk its middle is in. Looks only (no collision).
KERB_W, KERB_H = 0.25, 0.12


def _chunk_has(x, z):
    return abs(x - ORIGIN[0]) <= 43.75 and abs(z - ORIGIN[1]) <= 43.75 and \
        (x - ORIGIN[0] < 43.75 or ORIGIN[0] + 43.75 >= 175.0) and (z - ORIGIN[1] < 43.75 or ORIGIN[1] + 43.75 >= 175.0)


def _local(p):
    return (p[0] - ORIGIN[0], p[1], p[2] - ORIGIN[1])


def draw_road_edges(b, rng):
    for road in TERRAIN.get("roads", []):
        if not road.get("kerb"):
            continue
        P, F = road["points"], road["flags"]
        n = len(P) // 2
        for side in (0, 1):   # (left, right edge)
            for i in range(n - 1):
                a, c = P[2 * i + side], P[2 * i + 2 + side]
                if F[2 * i + side] or F[2 * i + 2 + side]:
                    continue
                mx, mz = (a[0] + c[0]) / 2, (a[2] + c[2]) / 2
                if not _chunk_has(mx, mz):
                    continue
                oa, oc = P[2 * i + 1 - side], P[2 * i + 3 - side]   # (the other edge: outward is away from it)
                def out(p, o):
                    dx, dz = p[0] - o[0], p[2] - o[2]
                    ln = math.hypot(dx, dz) or 1.0
                    return dx / ln, dz / ln
                ua, uc = out(a, oa), out(c, oc)
                A, C = _local(a), _local(c)
                ia, ic = (A[0], A[1] + KERB_H, A[2]), (C[0], C[1] + KERB_H, C[2])
                xa = (A[0] + ua[0] * KERB_W, 0.0, A[2] + ua[1] * KERB_W)
                xc = (C[0] + uc[0] * KERB_W, 0.0, C[2] + uc[1] * KERB_W)
                xa = (xa[0], max(A[1], ground(xa[0], xa[2])) + KERB_H, xa[2])
                xc = (xc[0], max(C[1], ground(xc[0], xc[2])) + KERB_H, xc[2])
                ctr = ((A[0] + C[0]) / 2, (A[1] + C[1]) / 2, (A[2] + C[2]) / 2)
                tri(b, ia, ic, xc, "dbr_conc", (ctr[0], ctr[1] - 5, ctr[2]), tile=1.0)          # top
                tri(b, ia, xc, xa, "dbr_conc", (ctr[0], ctr[1] - 5, ctr[2]), tile=1.0)
                lo_a, lo_c = (A[0], A[1] - 0.06, A[2]), (C[0], C[1] - 0.06, C[2])                  # the face to the road
                n_in = norm((-ua[0], 0.0, -ua[1]))
                b.poly([lo_a, lo_c, ic, ia], n_in, "dbr_conc", uv_world(1.0))
                ga, gc = (xa[0], ground(xa[0], xa[2]) - 0.15, xa[2]), (xc[0], ground(xc[0], xc[2]) - 0.15, xc[2])
                b.poly([ga, gc, xc, xa], norm((ua[0], 0.0, ua[1])), "dbr_conc", uv_world(1.0))   # the back
        # manholes in the lanes, drains in the gutters
        dist, next_mh, next_dr = 0.0, 18.0, 9.0
        for i in range(n - 1):
            l0, r0, l1, r1 = P[2 * i], P[2 * i + 1], P[2 * i + 2], P[2 * i + 3]
            m0 = ((l0[0] + r0[0]) / 2, (l0[2] + r0[2]) / 2)
            m1 = ((l1[0] + r1[0]) / 2, (l1[2] + r1[2]) / 2)
            dist += math.hypot(m1[0] - m0[0], m1[1] - m0[1])
            if any(F[2 * i: 2 * i + 4]):
                continue
            if dist >= next_mh:
                next_mh = dist + 38.0 + rng.uniform(-6, 6)
                t = 0.5 + (1.4 / road["width"]) * (1 if (i // 7) % 2 else -1)   # (in one lane or the other)
                p = (l0[0] + (r0[0] - l0[0]) * t, l0[1], l0[2] + (r0[2] - l0[2]) * t)
                if _chunk_has(p[0], p[2]):
                    q = _local(p)
                    cyl(b, (q[0], q[1] + 0.012, q[2]), 0.36, 0.026, "trim_dark", sides=12, caps=False)
                    b.poly([(q[0] + 0.34 * math.cos(math.radians(k * 30)), q[1] + 0.025, q[2] + 0.34 * math.sin(math.radians(k * 30)))
                            for k in range(12)], (0, 1, 0), "decals", mb.uv_fit(DECALS.regions["manhole"]))
            if dist >= next_dr:
                next_dr = dist + 24.0
                side = (i // 5) % 2
                e, o = (l0, r0) if side == 0 else (r0, l0)
                t = 0.32 / road["width"]
                p = (e[0] + (o[0] - e[0]) * t, e[1], e[2] + (o[2] - e[2]) * t)
                if _chunk_has(p[0], p[2]):
                    q = _local(p)
                    yaw = math.degrees(math.atan2(l1[0] - l0[0], l1[2] - l0[2]))
                    g = Frame(b, (q[0], q[1], q[2]), yaw)
                    g.box((0, 0.012, 0), (0.42, 0.024, 0.7), style=lambda n_, m_, q_: None if n_[1] < -0.7 else
                          (("decals", mb.uv_fit(DECALS.regions["drain"])) if n_[1] > 0.7 else ("trim_dark", uv_world(1.0))))


# ------------------------------------------------------------------------------------------------ the railway
# (outdoor step 5) The track: a ballast bed, creosoted sleepers every 0.65 m, two steel rails (standard gauge) with
# rusty sides and a bright running top. Over the creek the sleepers lie on the bridge; at the level crossing the road
# covers it. The bridge: timber deck on two steel plate girders and concrete abutments. Boxcars: ribbed steel bodies
# on two bogies, sliding doors, a roof walk, end ladders; looks b brown-red / blue, c army olive, d burnt out.
GAUGE = 1.435


def _rails(f, z0, z1, flush=None):
    """The two rails from local z0 to z1; `flush` (height over the frame): only their heads, level with a road."""
    L, zc = z1 - z0, (z0 + z1) / 2
    for side in (-1, 1):
        x = side * GAUGE / 2
        head = lambda n_, m_, q_: None if n_[1] < -0.7 else \
            (("steel_light", uv_world(1.0)) if n_[1] > 0.7 else ("dbr_rail", uv_world(1.0)))
        if flush is None:
            f.box((x, 0.135, zc), (0.13, 0.03, L), style=no_bottom("dbr_rail", 1.0))          # foot
            f.box((x, 0.19, zc), (0.025, 0.08, L), style=no_bottom("dbr_rail", 1.0))          # web
            f.box((x, 0.245, zc), (0.07, 0.04, L), style=head)                                # head
        else:
            f.box((x, flush - 0.006, zc), (0.07, 0.04, L), style=head)


def _crossing(f, z0, z1, flush):
    """A level crossing's deck between and beside the rails: dark rubber panels level with the road, flangeways."""
    L, zc = z1 - z0, (z0 + z1) / 2
    y = flush + 0.012
    inner = GAUGE / 2 - 0.12
    f.box((0, y - 0.03, zc), (2 * inner, 0.06, L), style=no_bottom("dbr_xing", 1.0))
    for side in (-1, 1):
        f.box((side * (GAUGE / 2 + 0.06 + 0.3), y - 0.03, zc), (0.6, 0.06, L), style=no_bottom("dbr_xing", 1.0))
        f.box((side * (GAUGE / 2 - 0.08), flush - 0.01, zc), (0.09, 0.02, L), style=no_bottom("black", 1.0))   # flangeway


def _track_line(b, a, c, top, rng, ballast=True):
    """Track from a to c (chunk points, on the bed's top `top`). Where a road crosses it (the road is above the bed)
    the rails sink to the road's top and concrete crossing panels fill between them (owner 2026-10-18: seamless)."""
    d = v_sub(c, a)
    L = math.hypot(d[0], d[2])
    if L < 0.05:
        return
    yaw = math.degrees(math.atan2(d[0], d[2]))
    f = Frame(b, (a[0], top, a[2]), yaw)
    road = lambda z: max(surface(*[f.p(xx, 0, z)[i] for i in (0, 2)]) for xx in (-1.2, 0.0, 1.2)) - top
    n = max(1, int(L / 0.65))
    for k in range(n):
        z = (k + 0.5) * L / n
        if road(z) > 0.03:   # (under the road at the level crossing)
            continue
        f.box((rng.uniform(-0.04, 0.04), 0.06, z), (2.5, 0.12, 0.24), yaw=rng.uniform(-2, 2), style=no_bottom("dbr_pole", 1.0))
    if ballast:
        for side in (-1, 1):   # the bed's sloped shoulders (its top is the gray box, drawn as stone)
            q = [f.p(side * 1.3, 0.0, 0), f.p(side * 1.3, 0.0, L), f.p(side * 1.75, -0.2, L), f.p(side * 1.75, -0.2, 0)]
            b.poly(q, norm(rot((side * 0.4, 1.0, 0), yaw, 0.0)), "dbr_ballast", uv_world(1.0))
        b.poly([f.p(-1.3, 0.0, 0), f.p(1.3, 0.0, 0), f.p(1.3, 0.0, L), f.p(-1.3, 0.0, L)], (0, 1, 0), "dbr_ballast", uv_world(1.0))
    # rails, in runs: plain, or flush with a road where one crosses
    step = 0.25
    m = max(1, int(L / step))
    flags = [road((k + 0.5) * L / m) for k in range(m)]
    k = 0
    while k < m:
        over = flags[k] > 0.03
        j = k
        while j + 1 < m and (flags[j + 1] > 0.03) == over:
            j += 1
        z0, z1 = k * L / m, (j + 1) * L / m
        if over:
            flush = sum(flags[k:j + 1]) / (j + 1 - k)
            _rails(f, z0, z1, flush)
            _crossing(f, z0, z1, flush)
        else:
            _rails(f, z0, z1)
        k = j + 1


def _track_path(b, pts, rng, main_z):
    """A curved siding along chunk points (x, top, z): one continuous ballast bed, sleepers square to the curve every
    0.65 m (none on the main line's bed, `main_z` Godot z: its own sleepers carry both), rails in short runs."""
    tang = []
    for i in range(len(pts)):
        p, q = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        dx, dz = q[0] - p[0], q[2] - p[2]
        ln = math.hypot(dx, dz) or 1.0
        tang.append((dx / ln, dz / ln))
    side_pt = lambda i, off, dy: (pts[i][0] + tang[i][1] * off, pts[i][1] + dy, pts[i][2] - tang[i][0] * off)
    for i in range(len(pts) - 1):   # the bed (1 cm under the main line's, so where they meet the main's shows)
        for o0, o1, d0, d1 in ((-1.3, 1.3, -0.01, -0.01), (1.3, 1.75, -0.01, -0.21), (-1.75, -1.3, -0.21, -0.01)):
            q = [side_pt(i, o0, d0), side_pt(i, o1, d1), side_pt(i + 1, o1, d1), side_pt(i + 1, o0, d0)]
            nrm = norm(cross(v_sub(q[1], q[0]), v_sub(q[3], q[0])))
            if nrm[1] < 0:
                nrm = v_scale(nrm, -1.0)
            b.poly(q, nrm, "dbr_ballast", uv_world(1.0))
    seg = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][2] - pts[i][2]) for i in range(len(pts) - 1)]
    total, at, i, run = sum(seg), 0.325, 0, 0.0
    while at < total:
        while i < len(seg) - 1 and run + seg[i] < at:
            run += seg[i]
            i += 1
        t = (at - run) / (seg[i] or 1.0)
        p = v_add(pts[i], v_scale(v_sub(pts[i + 1], pts[i]), t))
        at += 0.65
        if abs(p[2] + ORIGIN[1] - main_z) < 1.5:
            continue
        dx, dz = pts[i + 1][0] - pts[i][0], pts[i + 1][2] - pts[i][2]
        b.box((p[0], p[1] + 0.06, p[2]), (2.5, 0.12, 0.24), yaw=math.degrees(math.atan2(dx, dz)) + rng.uniform(-2, 2),
              style=no_bottom("dbr_pole", 1.0))
    for i in range(len(pts) - 1):
        a, c = pts[i], pts[i + 1]
        yaw = math.degrees(math.atan2(c[0] - a[0], c[2] - a[2]))
        _rails(Frame(b, a, yaw), -0.02, seg[i] + 0.02)


RAIL_GZ = 210.0 - 175.0   # (the main line, Godot z)


def draw_track(b, piece, rng):
    rails = [bx for bx in piece["boxes"] if bx["colour"] == "rail"]   # (the gray sleepers: drawn by _track_line)
    if rails and not rails[0]["size"][0] > rails[0]["size"][2]:
        # a siding: its strip pieces (each overlaps the next by half the width, see gen strip()) joined into one path
        pts = []
        for box in rails:
            (x, y, z), s = box["pos"], box["size"]
            L = s[2] - s[0] * 0.5
            for end in (-1, 1):
                p = v_add((x, y, z), rot((0, s[1] / 2, end * L / 2), box["yaw"], box["pitch"]))
                if not pts or math.hypot(p[0] - pts[-1][0], p[2] - pts[-1][2]) > 0.05:
                    pts.append(p)
        _track_path(b, pts, rng, RAIL_GZ)
        return
    for box in rails:
        (x, y, z), s = box["pos"], box["size"]
        top = y + s[1] / 2
        L = s[0]
        a, c = (x - L / 2, 0.0, z), (x + L / 2, 0.0, z)
        long_x = True
        # (over the creek: no ballast, the sleepers lie on the bridge deck)
        cuts = [0.0, 1.0]
        wa, wc = a[0] + ORIGIN[0], c[0] + ORIGIN[0]
        if long_x and wa < -133.0 < wc:   # (the bridge spans map x 36..48 = Godot -139..-127)
            cuts = [0.0, (-139.0 - wa) / (wc - wa), (-127.0 - wa) / (wc - wa), 1.0]
        for k in range(len(cuts) - 1):
            p0 = v_add(a, v_scale(v_sub(c, a), cuts[k]))
            p1 = v_add(a, v_scale(v_sub(c, a), cuts[k + 1]))
            on_bridge = len(cuts) == 4 and k == 1
            _track_line(b, p0, p1, 0.25 if on_bridge else top, rng, ballast=not on_bridge)


def draw_bridge(b, piece, rng):
    box = piece["boxes"][0]
    (x, y, z), s = box["pos"], box["size"]
    f = frame_of(b, box)   # (local x along the track: the deck is 12 m along x, 6 m across)
    W, D = s[0], s[2]
    top = s[1]
    for k in range(int(D / 0.25)):   # deck planks across the girders
        zz = -D / 2 + 0.125 + k * 0.25
        f.box((0, top - 0.04, zz), (W, 0.08, 0.23), style=no_bottom("wood_dark" if k % 3 else "dbr_pole", 1.0))
    for side in (-1, 1):   # plate girders under the rails
        f.box((0, top - 0.6, side * 0.9), (W + 0.4, 1.04, 0.04), style=flat("dbr_rail", 1.0))
        for yy in (top - 0.1, top - 1.1):
            f.box((0, yy, side * 0.9), (W + 0.4, 0.04, 0.4), style=flat("dbr_rail", 1.0))
        for k in range(7):   # stiffeners
            f.box((-W / 2 + k * W / 6, top - 0.6, side * 0.9), (0.05, 1.0, 0.25), style=flat("dbr_rail", 1.0))
        f.box((0, top + 0.5, side * (D / 2 - 0.1)), (W, 0.06, 0.06), style=flat("trim_dark", 1.0))   # hand rail
        for k in range(7):
            f.box((-W / 2 + 0.05 + k * (W - 0.1) / 6, top + 0.25, side * (D / 2 - 0.1)), (0.05, 0.5, 0.05),
                  style=flat("trim_dark", 1.0))
    for end in (-1, 1):   # concrete abutments down into the banks
        p = f.p(end * (W / 2 + 0.4), 0, 0)
        g = ground(p[0], p[2])
        h = top - 0.1 - g + 1.0
        f.box((end * (W / 2 + 0.4), top - 0.1 - h / 2, 0), (1.0, h, D + 0.6), style=no_bottom("dbr_conc", 2.0))


BOXCAR_SKINS = {"b": ("dbr_cont_r", "dbr_rail", "dbr_cont_b"), "c": ("dbr_cont_g",), "d": ("dbr_burnt",)}


def draw_boxcar(b, piece, rng):
    box = piece["boxes"][0]
    s = box["size"]
    look = piece["look"]
    skin = rng.choice(BOXCAR_SKINS[look])
    base = frame_of(b, box)
    yaw = base.yaw + (90.0 if s[0] > s[2] else 0.0)   # (local z along the car)
    L, W = max(s[0], s[2]), min(s[0], s[2])
    f = Frame(b, base.at, yaw)
    H0 = 1.1
    body = Frame(b, f.p(0, H0, 0), yaw)
    container(body, rng, skin, ribs=True, holes=look == "d", L=L - 0.3, W=W - 0.1, H=s[1] - H0 - 0.08)
    f.box((0, s[1] - 0.03, 0), (W - 0.02, 0.06, L - 0.25), style=flat(skin, 2.4))               # roof
    f.box((0, s[1] + 0.03, 0), (0.5, 0.05, L - 0.6), style=flat("wood_dark", 1.0))              # roof walk
    for side in (-1, 1):   # sliding doors, half open on some
        dz = rng.choice((0.0, 0.0, 0.9))
        f.box((side * (W / 2 + 0.01), H0 + 1.15, dz), (0.06, 2.2, 1.9), style=flat(skin, 2.4))
        f.box((side * (W / 2 + 0.05), H0 + 2.32, 0.0), (0.05, 0.08, 4.2), style=flat("trim_dark", 1.0))   # door track
        if dz and look != "c":
            f.box((side * (W / 2 - 0.02), H0 + 1.15, -0.95), (0.02, 2.1, 0.02), style=flat("black", 1.0))
    # underframe: the collision box goes to the ground, so it's filled: centre sill, equipment, shadowed fill
    f.box((0, H0 - 0.15, 0), (W - 0.2, 0.3, L - 0.2), style=flat("trim_dark", 1.0))
    f.box((0, 0.6, 0), (W - 0.9, 0.7, L - 4.6), style=flat("black", 1.0))
    for zz in (-1.2, 0.6):
        cyl(b, f.p(0.5, 0.75, zz), 0.25, 1.1, "trim_dark", sides=8, axis="z", yaw=yaw)       # air tanks
    for end in (-1, 1):   # bogies, couplers, ladders
        zc = end * (L / 2 - 1.9)
        f.box((0, 0.75, zc), (W - 0.6, 0.35, 2.4), style=flat("trim_dark", 1.0))
        for side in (-1, 1):
            f.box((side * (GAUGE / 2 + 0.12), 0.55, zc), (0.12, 0.45, 2.6), style=flat("trim_dark", 1.0))
            for az in (-0.9, 0.9):
                cyl(b, f.p(side * GAUGE / 2, 0.42, zc + az), 0.42, 0.12, "dbr_rail", sides=10, axis="x", yaw=yaw)
        f.box((0, 0.95, end * (L / 2 + 0.2)), (0.3, 0.25, 0.5), style=flat("trim_dark", 1.0))
        for k in range(6):
            f.box((W / 2 - 0.3, H0 + 0.3 + k * 0.38, end * (L / 2 - 0.12)), (0.4, 0.03, 0.03), style=flat("trim_dark", 1.0))


def _bogie(f, rng, zc, axles=2, rail_mat="dbr_rail"):
    """A truck under a car or the locomotive: frame, side frames, wheels on the rails' gauge."""
    span = 1.8 if axles == 2 else 2.8
    f.box((0, 0.75, zc), (2.0, 0.35, span + 0.6), style=flat("trim_dark", 1.0))
    for side in (-1, 1):
        f.box((side * (GAUGE / 2 + 0.12), 0.55, zc), (0.12, 0.45, span + 0.8), style=flat("trim_dark", 1.0))
        for k in range(axles):
            az = -span / 2 + k * span / (axles - 1)
            cyl(f.b, f.p(side * GAUGE / 2, 0.42, zc + az), 0.42, 0.12, rail_mat, sides=10, axis="x", yaw=f.yaw)


def _leaned(b, v0, n0, foot, yaw, lean, pivot_x):
    """Leans what was drawn since (v0, n0) (in a frame at the origin) `lean` degrees about its length, round the
    bottom of local x = pivot_x (that side stays on the ground, the other digs in), then turns and places it."""
    c, s_ = math.cos(math.radians(lean)), math.sin(math.radians(lean))
    roll = lambda q, px: (px + (q[0] - px) * c - q[1] * s_, (q[0] - px) * s_ + q[1] * c, q[2])
    for i in range(v0, len(b.verts)):
        b.verts[i] = v_add(rot(roll(b.verts[i], pivot_x), yaw, 0.0), foot)
    for i in range(n0, len(b.normals)):
        b.normals[i] = rot(roll(b.normals[i], 0.0), yaw, 0.0)


LOCO_SKINS = {"b": "dbr_loco_r", "c": "dbr_trk_o", "d": "dbr_loco_r"}   # (d: maroon too, shot up, no stripes)


def draw_loco(b, piece, rng):
    """The derailed diesel: a road switcher (cab, short nose, long hood) off the rails and leaning into the ballast."""
    box, marker = piece["boxes"][0], piece["boxes"][1]
    look = piece["look"]
    skin = LOCO_SKINS[look]
    glass = "black" if look == "d" else "glass"
    s = box["size"]
    W, L = s[0], s[2]
    (x, y, z) = box["pos"]
    foot = (x, y - s[1] / 2, z)
    v0, n0 = len(b.verts), len(b.normals)
    f = Frame(b, (0, 0, 0), 0.0)   # (local -z: the front, toward the bridge)
    f.box((0, 1.375, 0), (W, 0.25, L), style=flat(skin, 2.4))                                    # deck
    if look != "d":
        for side in (-1, 1):
            f.box((side * (W / 2 + 0.005), 1.375, 0), (0.01, 0.12, L), style=flat("loco_y_flat", 1.0))   # sill stripe
    for end in (-1, 1):   # pilots with hazard stripes, couplers, steps
        f.box((0, 0.95, end * (L / 2 - 0.08)), (W - 0.1, 0.6, 0.16), style=flat("dbr_hazard", 0.6))
        f.box((0, 0.95, end * (L / 2 + 0.25)), (0.3, 0.25, 0.5), style=flat("trim_dark", 1.0))
        for side in (-1, 1):
            for k in range(3):
                f.box((side * (W / 2 - 0.3), 0.35 + k * 0.35, end * (L / 2 - 0.4)), (0.5, 0.04, 0.3), style=flat("trim_dark", 1.0))
    for zc in (-L / 2 + 2.6, L / 2 - 2.6):
        _bogie(f, rng, zc, axles=3)
    f.box((0, 0.9, 0), (2.4, 0.8, 4.6), style=flat("trim_dark", 1.0))                          # fuel tank
    f.box((0, 0.55, 0), (W - 0.9, 0.9, L - 2.4), style=flat("black", 1.0))                      # (shadowed fill)
    for side in (-1, 1):
        cyl(b, f.p(side * 0.9, 1.05, 0.0), 0.2, 3.0, "trim_dark", sides=8, axis="z")            # air reservoirs
    # long hood (behind the cab), cab, short nose
    hz0, hz1 = -3.0, L / 2 - 0.4
    hood_c, hood_l = (hz0 + hz1) / 2, hz1 - hz0
    f.box((0, 2.7, hood_c), (2.3, 2.4, hood_l), style=no_bottom(skin, 2.4))
    f.box((0, 3.93, hood_c), (2.1, 0.06, hood_l - 0.2), style=flat("trim_dark", 1.0))
    for side in (-1, 1):
        for k in range(6):   # access doors and louvres
            zz = hz0 + 0.9 + k * (hood_l - 1.8) / 5
            f.box((side * 1.155, 2.6, zz), (0.01, 1.7, 0.03), style=flat("trim_dark", 1.0))
            if k % 2:
                for j in range(4):
                    f.box((side * 1.157, 3.2 + j * 0.12, zz + 0.6), (0.01, 0.05, 0.8), style=flat("black", 1.0))
        if look != "d":
            f.box((side * 1.157, 1.75, hood_c), (0.01, 0.16, hood_l), style=flat("loco_y_flat", 1.0))
        for k in range(8):   # walkway handrail
            f.box((side * (W / 2 - 0.08), 2.0, -L / 2 + 0.4 + k * (L - 0.8) / 7), (0.05, 1.0, 0.05), style=flat("hz_flat", 1.0))
        f.box((side * (W / 2 - 0.08), 2.5, 0), (0.05, 0.05, L - 0.8), style=flat("hz_flat", 1.0))
    for zz in (hz1 - 1.3, hz1 - 3.0):   # radiator fans, exhaust stack
        cyl(b, f.p(0, 3.98, zz), 0.55, 0.06, "black", sides=12)
    cyl(b, f.p(0, 4.05, hz0 + 1.6), 0.18, 0.3, "trim_dark", sides=8)
    cz0, cz1 = -5.7, hz0
    f.box((0, 2.8, (cz0 + cz1) / 2), (W - 0.1, 2.6, cz1 - cz0), style=no_bottom(skin, 2.4))     # cab
    f.box((0, 4.14, (cz0 + cz1) / 2), (W, 0.08, cz1 - cz0 + 0.1), style=flat("trim_dark", 1.0))
    for xx in (-0.6, 0.6):
        f.box((xx, 3.45, cz0 - 0.01), (0.9, 0.7, 0.02), style=flat(glass, 1.0))                   # front windows
    for side in (-1, 1):
        for zz in (cz0 + 0.7, cz1 - 0.7):
            f.box((side * (W / 2 - 0.04), 3.45, zz), (0.02, 0.7, 0.9), style=flat(glass, 1.0))
        f.box((side * (W / 2 - 0.04), 2.5, (cz0 + cz1) / 2), (0.02, 1.9, 0.6), style=flat("trim_dark", 1.0))   # door
    nz0 = -L / 2 + 0.3
    f.box((0, 2.25, (nz0 + cz0) / 2), (2.0, 1.5, cz0 - nz0), style=no_bottom(skin, 2.4))         # nose
    f.box((0, 3.0, (nz0 + cz0) / 2), (1.9, 0.04, cz0 - nz0 - 0.1), style=flat("trim_dark", 1.0))
    for xx in (-0.35, 0.35):
        f.box((xx, 2.6, nz0 - 0.01), (0.22, 0.22, 0.03), style=flat("black" if look == "d" else "dbr_porc", 1.0))   # lights
    f.box((0, 4.3, cz1 - 0.5), (0.5, 0.12, 0.12), style=flat("trim_dark", 1.0))                 # horn
    if look == "d":   # burnt and shot up
        for _ in range(16):
            side = rng.choice((-1, 1))
            f.box((side * 1.16, rng.uniform(1.8, 3.7), rng.uniform(hz0 + 0.5, hz1 - 0.5)),
                  (0.01, rng.uniform(0.08, 0.22), rng.uniform(0.08, 0.22)), style=flat("black", 1.0))
    _leaned(b, v0, n0, foot, box["yaw"], marker["yaw"], W / 2 - 0.7)
    # (its collision leans with it: the frame and bogies, the long hood, the cab and the nose; owner 0.18.3, shots hit
    # an invisible wall over the low side)
    shape_boxes([((0, 0.75, 0), (W - 0.4, 1.5, L - 0.2)), ((0, 2.7, hood_c), (2.3, 2.4, hood_l)),
                 ((0, 2.8, (cz0 + cz1) / 2), (W - 0.1, 2.6, cz1 - cz0)), ((0, 2.25, (nz0 + cz0) / 2), (2.0, 1.5, cz0 - nz0))],
                0, foot=foot, yaw=box["yaw"], lean=marker["yaw"], pivot_x=W / 2 - 0.7)
    # where it came off: ballast thrown up on the low side, broken sleepers by the rails
    lf = Frame(b, foot, box["yaw"])
    for k in range(30):   # (a ridge of ballast and earth pushed up along the low side: lumps piled on each other)
        out = rng.uniform(0, 1.0)
        p = lf.p(-W / 2 - 0.1 - out, 0.0, -L / 2 + 0.6 + rng.uniform(0, L - 1.2))
        h = (0.35 - 0.25 * out) * rng.uniform(0.6, 1.0)
        b.box(on_ground(p, h / 2 - 0.08), (rng.uniform(0.35, 0.7), h + 0.16, rng.uniform(0.4, 0.8)),
              yaw=lf.yaw + rng.uniform(0, 90), pitch=rng.uniform(-15, 15),
              style=no_bottom(rng.choice(("dbr_ballast", "dbr_ballast", "dbr_earth")), 1.0))
    for k in range(4):
        p = lf.p(rng.uniform(-1.0, 1.0), 0.0, -L / 2 - 1.0 - k * 1.1)
        b.box(on_ground(p, 0.08), (0.24, 0.12, 2.4), yaw=lf.yaw + rng.uniform(-50, 50) + 90.0,
              pitch=rng.uniform(-8, 8), style=flat("dbr_pole", 1.0))
    bits(b, lf.p(0, 0, -L / 2 - 2.0), 1.5, 8, rng, ("dbr_ballast", "rubble_core"))


def draw_signal(b, piece, rng):
    """A colour-light signal: a lattice-free steel mast on a concrete foot, a black target with three lamps under
    hoods facing the trains, a ladder up to it, a relay box at its foot. War: most lamps are dead, glass smashed."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    H = box["size"][1]
    f.box((0, 0.15, 0), (0.7, 0.4, 0.7), style=no_bottom("dbr_conc", 1.0))
    f.box((0, 0.0, 0), (0.75, 0.3, 0.75), style=no_bottom("dbr_conc", 1.0))
    cyl(b, f.p(0, 0.35 + (H - 1.2) / 2, 0), 0.08, H - 1.2, "trim_dark", sides=8)
    hy = H - 0.75
    f.box((0, hy, 0.12), (0.55, 1.25, 0.1), style=flat("black", 1.0))                       # target
    f.box((0, hy, 0.06), (0.28, 1.0, 0.22), style=flat("trim_dark", 1.0))                    # lamp case
    lit = rng.random() < 0.5
    for k, col in enumerate(("sg_red_flat", "sig_dead", "sig_dead")):
        y = hy + 0.35 - k * 0.35
        lens = col if (k == 0 and lit) else "sig_dead"
        cyl(b, f.p(0, y, 0.18), 0.1, 0.02, lens, sides=10, axis="z", yaw=f.yaw)
        f.box((0, y + 0.13, 0.27), (0.26, 0.03, 0.2), style=flat("trim_dark", 1.0))          # hood
    for k in range(int((hy - 1.2) / 0.3)):   # ladder (behind the mast)
        f.box((0, 0.8 + k * 0.3, -0.2), (0.35, 0.03, 0.03), style=flat("trim_dark", 1.0))
    for xx in (-0.17, 0.17):
        f.box((xx, (hy + 0.5) / 2 + 0.3, -0.2), (0.03, hy - 0.2, 0.03), style=flat("trim_dark", 1.0))
    f.box((0, hy - 0.72, -0.05), (0.8, 0.04, 0.45), style=flat("trim_dark", 1.0))                # platform
    rel = f.p(0.65, 0, -0.1)
    b.box(on_ground(rel, 0.4), (0.45, 0.8, 0.35), yaw=f.yaw, style=no_bottom("dbr_xf", 1.0))       # relay box


def draw_points(b, piece, rng):
    """A switch at the toe of a turnout: a ground lever with its target, the throw rod to the blades, long sleepers."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    look = piece["look"]
    f.box((0, 0.12, 0), (0.5, 0.18, 0.35), style=no_bottom("trim_dark", 1.0))                  # base
    lever = rng.uniform(-35, 35)
    b.box(f.p(0.0, 0.42, 0.0), (0.05, 0.6, 0.05), yaw=f.yaw, pitch=lever, style=flat("trim_dark", 1.0))
    b.box(f.p(0.0, 0.62, 0.0), (0.06, 0.08, 0.2), yaw=f.yaw, style=flat("hz_flat" if look != "d" else "trim_dark", 1.0))
    cyl(b, f.p(0, 0.55, 0.0), 0.16, 0.02, "sg_red_flat" if look != "d" else "trim_dark", sides=10, axis="x", yaw=f.yaw)
    # throw rod: from the lever across to the far rail, square to the main line (map z)
    lf = Frame(b, f.at, 0.0)
    lf.box((0, 0.17, 1.0), (0.06, 0.05, 2.1), style=flat("trim_dark", 1.0))
    for k in (0.0, 0.7):   # tie plates at the switch toe
        lf.box((k, 0.17, 1.0), (0.18, 0.02, 1.8), style=flat("dbr_rail", 1.0))


TANK_SKINS = {"b": "dbr_tank_k", "c": "dbr_tank_g", "d": "dbr_burnt"}


def draw_tanker(b, piece, rng):
    """A tank car: a long steel tank on saddles, a dome and its walkway, bogies; a hazard placard (no text)."""
    box = piece["boxes"][0]
    s = box["size"]
    look = piece["look"]
    skin = TANK_SKINS[look]
    base = frame_of(b, box)
    yaw = base.yaw + (90.0 if s[0] > s[2] else 0.0)   # (local z along the car)
    L, W = max(s[0], s[2]), min(s[0], s[2])
    f = Frame(b, base.at, yaw)
    R, yc = 1.15, 2.35
    f.box((0, 1.05, 0), (0.6, 0.4, L - 0.3), style=flat("trim_dark", 1.0))                    # centre sill
    for end in (-1, 1):
        f.box((0, 1.2, end * (L / 2 - 0.6)), (W - 0.1, 0.1, 1.2), style=flat("trim_dark", 1.0))   # end platforms
        f.box((0, 0.95, end * (L / 2 + 0.2)), (0.3, 0.25, 0.5), style=flat("trim_dark", 1.0))      # couplers
        f.box((0, 1.4, end * (L / 2 - 2.2)), (2.0, 0.3, 0.4), style=flat("trim_dark", 1.0))        # saddles
        _bogie(f, rng, end * (L / 2 - 1.9))
        for k in range(5):
            f.box((W / 2 - 0.3, 1.4 + k * 0.4, end * (L / 2 - 0.15)), (0.4, 0.03, 0.03), style=flat("trim_dark", 1.0))
    f.box((0, 0.6, 0), (W - 1.2, 0.7, L - 5.2), style=flat("black", 1.0))                         # (shadowed fill)
    tl = L - 1.4
    cyl(b, f.p(0, yc, 0), R, tl, skin, sides=16, axis="z", yaw=yaw, tile=2.4)
    t = Builder()   # (its collision: the frame and bogies, the round tank; owner 0.18.3: not one big block)
    Frame(t, base.at, yaw).box((0, 0.85, 0), (W - 0.4, 1.7, L - 0.2), style=flat("trim"))
    cyl(t, f.p(0, yc, 0), R, tl, "trim", sides=12, axis="z", yaw=yaw)
    shape(t, 0, 0)
    for end in (-1, 1):   # dished heads
        cyl(b, f.p(0, yc, end * (tl / 2 + 0.1)), R * 0.85, 0.2, skin, sides=16, axis="z", yaw=yaw, tile=2.4)
    for zz in (-tl / 2 + 0.6, -tl / 4, tl / 4, tl / 2 - 0.6):
        cyl(b, f.p(0, yc, zz), R + 0.02, 0.07, "trim_dark", sides=16, axis="z", yaw=yaw)       # bands
    cyl(b, f.p(0, yc + R + 0.08, 0), 0.42, 0.3, skin, sides=12, cap_mat="trim_dark")              # dome
    f.box((0, yc + R - 0.02, 0), (1.4, 0.04, 2.2), style=flat("wood_dark", 1.0))                 # walkway
    for side in (-1, 1):
        f.box((side * 0.68, yc + R + 0.4, 0), (0.04, 0.04, 2.2), style=flat("trim_dark", 1.0))
        for zz in (-1.05, 0.0, 1.05):
            f.box((side * 0.68, yc + R + 0.2, zz), (0.04, 0.4, 0.04), style=flat("trim_dark", 1.0))
        if look != "d":   # hazard placard (a plain diamond, no words)
            p = f.p(side * (R + 0.01), yc, tl / 2 - 1.4)
            b.box(p, (0.02, 0.5, 0.5), yaw=yaw, pitch=0.0, style=flat("placard_flat", 1.0))
    for k in range(6):   # side ladder to the walkway
        f.box((R - 0.1, 1.5 + k * 0.38, 0.0), (0.03, 0.03, 0.5), style=flat("trim_dark", 1.0))
    if look == "d":
        for _ in range(12):
            a = rng.uniform(-1.2, 1.2)
            f.box((math.sin(a) * (R + 0.005), yc + math.cos(a) * R * 0.9, rng.uniform(-tl / 2 + 0.5, tl / 2 - 0.5)),
                  (0.02, rng.uniform(0.08, 0.2), rng.uniform(0.08, 0.2)), style=flat("black", 1.0))


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
        spray_tag(b, box, random.Random(f"tag {piece['seed']}"), 0.45, 0.04)


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

    def P(i, j, na=NA, rs=None):
        a = 2 * math.pi * i / na
        r = r0 + (r1 - r0) * j / NR if rs is None else rs[j]
        w = 1.0 + 0.25 * math.sin(3 * a + ph[0]) + 0.15 * math.sin(5 * a + ph[1])
        t = (r - R) / (1.2 if r < R else 1.4)
        h = 0.58 * w * max(0.0, 1 - t * t) ** 1.5
        sink = 0.45 if j == 0 else 0.15 if j == (NR if rs is None else len(rs) - 1) else 0.0
        x, z = cx + r * math.cos(a), cz + r * math.sin(a)
        return (x, ground(x, z) + h - sink, z)   # (round 2: the rim follows the ground and dips under it at its edges)
    # its collision (owner 0.18.3: players got stuck on the 8 mound boxes): the same rim, coarser, to walk over
    t, rs = Builder(), (r0, R - 0.6, R, R + 0.7, r1)
    for i in range(16):
        for j in range(len(rs) - 1):
            t.poly([P(i, j, 16, rs), P(i + 1, j, 16, rs), P(i + 1, j + 1, 16, rs), P(i, j + 1, 16, rs)], (0, 1, 0), "trim", uv_world())
    shape(t, 0, list(range(len(mounds))))
    def shade(i, j):   # (0.19.12: smooth, tinted like the ground, so the rim melts into it; see smooth_sheet)
        du = v_sub(P(i + 0.5, j), P(i - 0.5, j))
        dv = v_sub(P(i, j + 0.5), P(i, j - 0.5))
        n = norm(cross(du, dv))
        if n[1] < 0:
            n = v_scale(n, -1)
        return n, ground_tint(P(i, j)[1], math.sqrt(max(1.0 - n[1] * n[1], 0.0)) / max(n[1], 0.1))
    for i in range(NA):
        for j in range(NR):
            ij = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            q = [P(*k) for k in ij]
            sh = [shade(*k) for k in ij]
            for t in ((0, 1, 2), (0, 2, 3)):
                a, c, d = (q[k] for k in t)
                n = norm(cross(v_sub(c, a), v_sub(d, a)))
                if n[1] < 0:
                    n = v_scale(n, -1)
                b.poly([a, c, d], n, GROUND, uv_world(2.0), vnormals=[sh[k][0] for k in t],
                       colors=[sh[k][1] for k in t])   # (scorched or not: the splat map says)
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


# ------------------------------------------------------------------------------------------------ extract camps
# (World art 0.17, owner 2026-10-18: little camps by the extracts round the radio mast: tents, a checkpoint hut,
# a camo net over crates; their sandbags are the kit's.) Drawn round their gray boxes, same collision.
def draw_tent(b, piece, rng):
    """An army ridge tent over its box: canvas down to the ground both sides, a closed back, the front open (dark
    inside), its ridge pole and guy ropes, a bedroll inside."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W, H, L = box["size"]
    canvas = "dbr_canvas"
    ridge = H + 0.25
    for sx in (-1, 1):   # the two roof sides
        a0, a1 = f.p(sx * (W / 2 + 0.15), -0.05, -L / 2), f.p(sx * (W / 2 + 0.15), -0.05, L / 2)
        r0, r1 = f.p(0, ridge, -L / 2), f.p(0, ridge, L / 2)
        tri(b, a0, a1, r1, canvas, f.p(0, H / 3, 0))
        tri(b, a0, r1, r0, canvas, f.p(0, H / 3, 0))
        # (the inside of the roof: dark, seen through the open front)
        ia0, ia1 = f.p(sx * (W / 2 + 0.1), -0.05, -L / 2 + 0.05), f.p(sx * (W / 2 + 0.1), -0.05, L / 2)
        ir0, ir1 = f.p(0, ridge - 0.06, -L / 2 + 0.05), f.p(0, ridge - 0.06, L / 2)
        tri(b, ia0, ia1, ir1, "trim_dark", f.p(sx * 4, ridge + 3, 0))
        tri(b, ia0, ir1, ir0, "trim_dark", f.p(sx * 4, ridge + 3, 0))
    tri(b, f.p(-W / 2 - 0.15, -0.05, L / 2), f.p(W / 2 + 0.15, -0.05, L / 2), f.p(0, ridge, L / 2), canvas, f.p(0, H / 3, 0))   # back
    for sx in (-1, 1):   # the front flaps, tied back
        tri(b, f.p(sx * (W / 2 + 0.15), -0.05, -L / 2), f.p(sx * 0.45, ridge * 0.72, -L / 2 - 0.02),
            f.p(sx * (W / 2 - 0.2), -0.05, -L / 2 - 0.25), canvas, f.p(0, H / 3, 0))
    f.box((0, ridge + 0.03, 0), (0.07, 0.07, L + 0.5), style=flat("wood_dark", 1.0))       # ridge pole and uprights
    for z in (-L / 2 - 0.2, L / 2 + 0.2):
        f.box((0, ridge / 2, z), (0.07, ridge, 0.07), style=flat("wood_dark", 1.0))
        for sx in (-1, 1):   # guy ropes to pegs
            _rope(b, f.p(0, ridge, z), f.p(sx * 0.7, 0.02, z + (1.3 if z > 0 else -1.3)))
    f.box((-0.5, 0.06, 0.2), (0.6, 0.12, 1.8), style=no_bottom("dbr_bag_grn", 1.0))            # a bedroll
    f.box((0.55, 0.15, 0.9), (0.5, 0.3, 0.35), style=no_bottom("dbr_trk_o", 1.0))              # a kit box


def _rope(b, p0, p1):
    d = v_sub(p1, p0)
    L = math.sqrt(dot(d, d))
    yaw = math.degrees(math.atan2(d[0], d[2]))
    pitch = -math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    b.box(v_scale(v_add(p0, p1), 0.5), (0.03, 0.03, L), yaw=yaw, pitch=pitch, style=flat("trim_dark", 1.0))


def draw_hut(b, piece, rng):
    """A checkpoint guard hut: olive steel box on a step, a roof overhanging all round, a door and a window toward
    the road (local -z), side windows, a lamp over the door, a phone box, sandbag skirt."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W, H, D = box["size"]
    skin = "dbr_trk_o"
    f.box((0, 0.08, 0), (W + 0.2, 0.16, D + 0.2), style=no_bottom("dbr_conc", 2.0))             # its slab
    f.box((0, H / 2 + 0.08, 0), (W, H - 0.25, D), style=no_bottom(skin, 2.0))
    f.box((0, H - 0.05, 0), (W + 0.5, 0.14, D + 0.5), style=lambda n, m, q: ("trim_dark", uv_world(1.0)))   # roof
    f.box((0, H + 0.04, 0), (W + 0.3, 0.06, D + 0.3), style=no_bottom("dbr_cont_g", 2.0))
    f.box((-0.45, 1.05, -D / 2 - 0.01), (0.8, 1.9, 0.03), style=flat("trim_dark", 1.0))          # door
    f.box((-0.2, 1.05, -D / 2 - 0.03), (0.06, 0.06, 0.03), style=flat("steel_light", 1.0))
    f.box((0.5, 1.5, -D / 2 - 0.01), (0.7, 0.6, 0.03), style=flat("black", 1.0))                 # window toward the road
    f.box((0.5, 1.18, -D / 2 - 0.1), (0.85, 0.05, 0.2), style=flat("trim_dark", 1.0))            # its sill
    for sx in (-1, 1):
        f.box((sx * (W / 2 + 0.01), 1.5, 0.1), (0.03, 0.55, 0.9), style=flat("black", 1.0))
    f.box((-0.45, 2.15, -D / 2 - 0.15), (0.25, 0.12, 0.25), style=flat("steel_light", 1.0))      # lamp
    f.box((W / 2 + 0.12, 1.2, 0.6), (0.2, 0.35, 0.25), style=no_bottom("dbr_cont_g", 1.0))       # field phone box
    for sx in (-1, 1):   # sandbags banked against both sides, waist high
        for k in range(3):
            f.box((sx * (W / 2 + 0.3), 0.18 + k * 0.22, -0.55 + (k % 2) * 0.2), (0.4, 0.22, 0.62), yaw=rng.uniform(-6, 6),
                  style=no_bottom("dbr_bag_tan", 1.0))
            f.box((sx * (W / 2 + 0.3), 0.18 + k * 0.22, 0.25 + (k % 2) * 0.2), (0.4, 0.22, 0.62), yaw=rng.uniform(-6, 6),
                  style=no_bottom("dbr_bag_tan", 1.0))


def draw_crates(b, piece, rng):
    """Army crates: olive boards, dark metal corners, rope handles, stencilled lids."""
    for box in piece["boxes"]:
        f = frame_of(b, box)
        W, H, D = box["size"]
        f.box((0, H / 2, 0), (W, H, D), style=no_bottom("dbr_trk_o", 1.0))
        f.box((0, H + 0.01, 0), (W * 0.5, 0.01, D * 0.25), style=flat("sandstone", 1.0))   # (a stencil patch)
        for sx in (-1, 1):
            for sz in (-1, 1):
                f.box((sx * (W / 2 - 0.03), H / 2, sz * (D / 2 - 0.03)), (0.07, H + 0.01, 0.07), style=no_bottom("trim_dark", 1.0))
            f.box((sx * (W / 2 + 0.02), H * 0.62, 0), (0.04, 0.05, D * 0.35), style=flat("dbr_canvas", 1.0))


def draw_net(b, piece, rng):
    """A camo net on four poles: a sagging sheet of net with leafy scraps tied in, hanging down at the edges."""
    posts = [bx for bx in piece["boxes"] if bx["solid"]]
    net = next(bx for bx in piece["boxes"] if not bx["solid"])
    for p in posts:
        f = frame_of(b, p)
        f.box((0, p["size"][1] / 2 + 0.05, 0), (0.12, p["size"][1] + 0.1, 0.12), style=no_bottom("wood_dark", 1.0))
    f = frame_of(b, net)
    W, _, D = net["size"]
    top = net["pos"][1] - frame_of(b, net).at[1] + 0.15
    N = 6
    def P(i, j):   # the net's points: sagging between the poles
        u, v = -W / 2 - 0.3 + (W + 0.6) * i / N, -D / 2 - 0.3 + (D + 0.6) * j / N
        sag = 0.35 * math.sin(math.pi * i / N) * math.sin(math.pi * j / N)
        edge = 0.45 if i in (0, N) or j in (0, N) else 0.0
        return f.p(u, top - sag - edge + rng.uniform(-0.03, 0.03), v)
    pts = [[P(i, j) for j in range(N + 1)] for i in range(N + 1)]
    for i in range(N):
        for j in range(N):
            a, c, d, e = pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1]
            tri(b, a, c, d, "dbr_leaf_c", v_add(a, (0, -5, 0)))
            tri(b, a, d, e, "dbr_leaf_c", v_add(a, (0, -5, 0)))
            tri(b, a, d, c, "dbr_canvas", v_add(a, (0, 5, 0)))   # (its underside)
            tri(b, a, e, d, "dbr_canvas", v_add(a, (0, 5, 0)))
    for _ in range(14):   # leafy scraps tied in
        u, v = rng.uniform(-W / 2, W / 2), rng.uniform(-D / 2, D / 2)
        rock(b, f.p(u, top - 0.05, v), (0.5, 0.18, 0.5), rng.uniform(0, 90), rng, "dbr_leaf_c", jitter=0.2, chamfer=0.4)


# ------------------------------------------------------------------------------------------------ the station square
def draw_shelter(b, piece, rng):
    """A bus shelter: steel frame, glass back and ends (cracked, one pane out), a slatted roof, a bench, the stop's
    blue sign on its post."""
    back = max(piece["boxes"], key=lambda bx: bx["size"][0] if bx["solid"] else 0)
    post = min(piece["boxes"], key=lambda bx: bx["size"][0])
    f = frame_of(b, back)
    W = back["size"][0]
    # (the frame's origin is the back panel's foot; the shelter's front is toward local -z)
    for x in (-W / 2, W / 2):
        for z in (0.0, -1.7):
            f.box((x, 1.25, z), (0.08, 2.5, 0.08), style=flat("trim_dark", 1.0))
    f.box((0, 2.52, -0.85), (W + 0.3, 0.08, 1.95), style=lambda n, m, q: ("trim_dark", uv_world(1.0)))
    f.box((0, 2.45, -0.85), (W + 0.1, 0.06, 1.85), style=flat("steel_light", 1.0))
    f.box((-W / 4, 1.25, 0.0), (W / 2 - 0.1, 2.2, 0.03), style=flat("glass", 1.0))   # glass (the right pane's out)
    f.box((W / 4, 0.25, 0.0), (W / 2 - 0.1, 0.4, 0.03), style=flat("trim_dark", 1.0))
    for x in (-W / 2, W / 2):
        f.box((x, 1.25, -0.6), (0.03, 2.2, 1.0), style=flat("glass", 1.0))
    f.box((0, 0.48, -0.35), (W - 0.6, 0.06, 0.4), style=flat("wood", 1.0))          # bench
    for x in (-W / 2 + 0.6, W / 2 - 0.6):
        f.box((x, 0.24, -0.35), (0.06, 0.48, 0.35), style=flat("trim_dark", 1.0))
    for _ in range(8):   # broken glass
        f.box((rng.uniform(0, W / 2), 0.01, rng.uniform(-1.2, 0.4)), (0.12, 0.02, 0.08), yaw=rng.uniform(0, 180), style=flat("glass", 1.0))
    g = frame_of(b, post)
    g.box((0, 1.3, 0), (0.08, 2.6, 0.08), style=flat("steel_light", 1.0))
    g.box((0, 2.45, 0), (0.7, 0.7, 0.05), style=flat("dbr_cont_b", 1.0))                   # the stop's sign
    g.box((0, 2.45, 0.03), (0.3, 0.3, 0.02), style=flat("sb_cream", 1.0))


def draw_bench(b, piece, rng):
    """A park bench: slatted seat and back on cast iron ends."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    W = box["size"][0]
    for k in range(3):
        f.box((0, 0.44, -0.12 + k * 0.12), (W, 0.04, 0.09), style=flat("wood", 1.0))
    for k in range(2):
        f.box((0, 0.62 + k * 0.14, 0.24), (W, 0.09, 0.03), style=flat("wood", 1.0))
    for x in (-W / 2 + 0.12, W / 2 - 0.12):
        f.box((x, 0.22, 0.0), (0.06, 0.44, 0.45), style=flat("trim_dark", 1.0))
        f.box((x, 0.6, 0.25), (0.06, 0.4, 0.05), style=flat("trim_dark", 1.0))


# ------------------------------------------------------------------------------------------------ the waterfall room
def draw_cave(b, piece, rng):
    """The rock knoll with the secret room behind the waterfall (gen cave_room; outdoor step 6). Its boxes come in
    cave_room's order: floor, the cliff face (two sides and the lintel over the door), the sides and back, the roof,
    the lip on top, the boulders round its foot, then a bedroll and a lantern. Inside, the walls are granite flush
    with their collision (little jitter, no taper) and the floor and roof flat slabs (the roof needs its underside).
    Outside, a skin of big overlapping boulders a little proud of the collision gives it a broken, rocky outline
    instead of a block's; the doorway stays open behind the falling water."""
    bx = piece["boxes"]
    slab = lambda n, m, q: ("dbr_granite", uv_world(2.0))
    for k, box in enumerate(bx):
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        if k == 0:
            b.box(c, s, style=lambda n, m, q: slab(n, m, q) if n[1] > 0.7 else None)
        elif k == 7:
            b.box(c, s, style=lambda n, m, q: slab(n, m, q) if n[1] < -0.7 else None)
        elif k <= 6:
            # the room's walls: plain boxes, flush with their collision (0.18.7: even a little jitter left the drawn
            # wall inside the collision in places, so you stopped short of it)
            b.box(c, s, style=slab)
        elif k == 8:
            rock(b, c, s, yaw, rng, "dbr_granite", jitter=0.02, chamfer=0.06, taper=1.0)
        elif box["colour"] == "stone":
            rock(b, c, (s[0] * 1.05, s[1], s[2] * 1.05), yaw, rng, "dbr_mossrock", jitter=0.12, chamfer=0.4)
        elif box["colour"] == "concrete":   # the threshold slab out of the door (only its top shows)
            b.box(c, s, pitch=box["pitch"], style=lambda n, m, q: slab(n, m, q) if n[1] > 0.7 else None)
        elif box["colour"] == "dirt":   # the bedroll: a rolled-out blanket with the roll at its head
            b.box((c[0] + 0.15, c[1] - s[1] / 2 + 0.03, c[2]), (s[0] - 0.3, 0.06, s[2]), style=flat("dbr_canvas", 1.0))
            cyl(b, (c[0] - s[0] / 2 + 0.17, c[1] - s[1] / 2 + 0.15, c[2]), 0.15, s[2], "dbr_canvas", sides=8, axis="z")
        else:   # the lantern: base, glass, cap and handle
            y0 = c[1] - s[1] / 2
            b.box((c[0], y0 + 0.03, c[2]), (0.2, 0.06, 0.2), style=flat("trim_dark", 1.0))
            b.box((c[0], y0 + 0.17, c[2]), (0.15, 0.22, 0.15), style=flat("glass", 1.0))
            b.box((c[0], y0 + 0.31, c[2]), (0.2, 0.05, 0.2), style=flat("trim_dark", 1.0))
            b.box((c[0], y0 + 0.37, c[2]), (0.02, 0.08, 0.14), style=flat("trim_dark", 1.0))
    # the skin: boulders along each outside face, in tiers up to that face's height (the face side lowest first)
    walls = bx[1:9]
    x0 = min(w["pos"][0] - w["size"][0] / 2 for w in walls)
    x1 = max(w["pos"][0] + w["size"][0] / 2 for w in walls)
    z0 = min(w["pos"][2] - w["size"][2] / 2 for w in walls)
    z1 = max(w["pos"][2] + w["size"][2] / 2 for w in walls)
    floor = bx[0]["pos"][1] + bx[0]["size"][1] / 2
    lintel = bx[3]   # (the doorway: under it, through the face)
    door = [lintel["pos"][k] - lintel["size"][k] / 2 - 0.9 for k in (0, 2)] + \
        [lintel["pos"][k] + lintel["size"][k] / 2 + 0.9 for k in (0, 2)] + [lintel["pos"][1] - lintel["size"][1] / 2]

    # the room inside (0.18.7, owner: the waterfall room's roof was messed up: skin boulders poked in through its
    # walls and roof): no boulder of the skin or the top may reach into it
    room = (bx[6]["pos"][0] + bx[6]["size"][0] / 2, bx[4]["pos"][2] + bx[4]["size"][2] / 2,
            bx[1]["pos"][0] - bx[1]["size"][0] / 2, bx[5]["pos"][2] - bx[5]["size"][2] / 2,
            bx[7]["pos"][1] - bx[7]["size"][1] / 2)

    def pokes_in(c, size, yaw, jitter):
        if c[1] - size[1] / 2 > room[4] + 0.15:
            return False
        grow = 1.0 + 2.0 * jitter
        for sx in (-1, 1):
            for sz in (-1, 1):
                q = v_add(rot((sx * size[0] / 2 * grow, 0.0, sz * size[2] / 2 * grow), yaw, 0.0), c)
                if room[0] - 0.1 < q[0] < room[2] + 0.1 and room[1] - 0.1 < q[2] < room[3] + 0.1:
                    return True
        return False

    def top_at(x, z):   # the collision's height there
        return max([w["pos"][1] + w["size"][1] / 2 for w in walls
                    if abs(x - w["pos"][0]) <= w["size"][0] / 2 + 0.01 and abs(z - w["pos"][2]) <= w["size"][2] / 2 + 0.01]
                   or [floor])
    mats = ("dbr_granite", "dbr_mossrock", "dbr_granite")
    sides = (((x0, z0), (x0, z1), (-1, 0)), ((x0, z1), (x1, z1), (0, 1)), ((x1, z1), (x1, z0), (1, 0)),
             ((x1, z0), (x0, z0), (0, -1)))
    for (ax, az), (cx, cz), (nx, nz) in sides:
        length = math.hypot(cx - ax, cz - az)
        n = max(2, round(length / 1.7))
        for i in range(n):
            t = (i + 0.5) / n + rng.uniform(-0.15, 0.15) / n
            px, pz = ax + (cx - ax) * t, az + (cz - az) * t
            h = top_at(px - nx * 0.5, pz - nz * 0.5) - floor
            y = floor - 0.3
            while y < floor + h - 0.4:
                th = min(rng.uniform(1.6, 2.6), floor + h + 0.35 - y)
                if door[0] < px < door[2] and door[1] < pz < door[3] and y < door[4] + 0.2:
                    y += th   # (keep the doorway open)
                    continue
                w = rng.uniform(1.6, 3.0)
                d = rng.uniform(1.0, 1.8)
                # (in reach, proud of the collision by only 0.1-0.3 m so you never sink into it; above head height
                # up to 0.9 m, which breaks up the cliff's outline into ledges and overhangs)
                out = rng.uniform(-0.2, 0.0) if y < floor + 2.0 else rng.uniform(0.0, 0.6)
                yaw = math.degrees(math.atan2(nx, nz)) + rng.uniform(-28, 28)
                mat = rng.choice(mats)
                for _ in range(5):   # (thinner, and if that's not enough, smaller, till it's clear of the room)
                    at = (px + nx * (out - d / 2 + 0.3), y + th / 2, pz + nz * (out - d / 2 + 0.3))
                    if not pokes_in(at, (w, th + 0.25, d), yaw, 0.16):
                        rock(b, at, (w, th + 0.25, d), yaw, rng, mat, jitter=0.16, chamfer=0.34, taper=0.8)
                        break
                    d, w = d * 0.7, w * 0.85
                y += th * rng.uniform(0.75, 0.9)
    # a broken top: a few slabs and boulders over the roof, higher at the cliff, stepping down to the hill
    for i in range(7):
        tx = x0 + 0.8 + (x1 - x0 - 1.6) * rng.random()
        tz = z0 + 0.8 + (z1 - z0 - 1.6) * rng.random()
        top = top_at(tx, tz)
        w = rng.uniform(1.8, 3.0)
        size, yaw, mat = (w, rng.uniform(0.5, 0.9), w * rng.uniform(0.7, 1.1)), rng.uniform(0, 180), rng.choice(mats)
        if not pokes_in((tx, top + 0.1, tz), size, yaw, 0.12):
            rock(b, (tx, top + 0.1, tz), size, yaw, rng, mat, jitter=0.12, chamfer=0.35, taper=0.8)



def draw_culvert(b, piece, rng):
    """Where the creek leaves the map (gen culvert): a weathered concrete headwall with two box tunnels, black inside,
    rusty grates over their mouths, boulders at its wings. Boxes in culvert()'s order: the headwall's three pieces,
    the beam over the mouths, the tunnels' back, the two grates, the coping, then the boulders."""
    for k, box in enumerate(piece["boxes"]):
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        if k == 4:
            b.box(c, s, style=flat("black", 1.0))
        elif k in (5, 6):   # bars every 0.25 m, two rails across them
            x0, y0, z = c[0] - s[0] / 2, c[1] - s[1] / 2, c[2]
            n = int(s[0] / 0.25)
            for i in range(n + 1):
                b.box((x0 + s[0] * i / n, c[1], z), (0.05, s[1], 0.05), style=flat("dbr_rail", 1.0))
            for yy in (y0 + 0.5, y0 + s[1] - 0.15):
                b.box((c[0], yy, z), (s[0], 0.08, 0.1), style=flat("dbr_rail", 1.0))
        elif k <= 7:
            b.box(c, s, style=flat("dbr_conc", 2.0))
        else:
            rock(b, c, (s[0] * 1.05, s[1], s[2] * 1.05), yaw, rng, rng.choice(("dbr_mossrock", "dbr_granite")),
                 jitter=0.12, chamfer=0.4)


def draw_bank(b, piece, rng):
    """The creek's banks (gen bank_stretch): pebbles (small boulders, mostly sunk) and reed clumps: thin blades leaning
    out from the clump's middle, a few with a brown seed head."""
    for box in piece["boxes"]:
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        if box["colour"] == "stone":
            rock(b, c, s, yaw, rng, rng.choice(("dbr_granite", "dbr_mossrock")), jitter=0.12, chamfer=0.4)
            continue
        y0 = c[1] - s[1] / 2 - 0.15
        for _ in range(rng.randint(9, 15)):
            a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0, 0.5) * min(s[0], s[2])
            h = s[1] * rng.uniform(0.6, 1.1)
            lean = r / max(min(s[0], s[2]) * 0.5, 0.01) * rng.uniform(6, 16)
            bx, bz = c[0] + math.cos(a) * r, c[2] + math.sin(a) * r
            b.box((bx, y0 + h / 2, bz), (0.035, h, 0.06), yaw=math.degrees(a) + 90, pitch=lean,
                  style=flat(rng.choice(("dbr_grass", "dbr_grass", "dbr_leaf_b")), 1.0))
            if rng.random() < 0.18:
                b.box((bx, y0 + h + 0.08, bz), (0.07, 0.2, 0.07), yaw=math.degrees(a), pitch=lean, style=flat("dbr_pole", 1.0))


def draw_log(b, piece, rng):
    """A fallen tree on the bank: a bark-grey trunk, sawn-pale ends, a broken branch stub or two."""
    box = piece["boxes"][0]
    s, (x, y, z), yaw = box["size"], box["pos"], box["yaw"]
    r = s[0] / 2
    cyl(b, (x, y - 0.02, z), r, s[2], "dbr_pole", sides=10, axis="z", yaw=yaw, cap_mat="wood_dark")
    for _ in range(rng.randint(1, 2)):
        t = rng.uniform(-0.35, 0.35) * s[2]
        side = rng.choice((-1, 1))
        ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        px, pz = x + sa * t + ca * side * r * 0.8, z + ca * t - sa * side * r * 0.8
        b.box((px, y + 0.12, pz), (0.5, 0.1, 0.1), yaw=yaw + rng.uniform(-30, 30), pitch=rng.uniform(-20, 20),
              style=flat("dbr_pole", 1.0))


def draw_stones(b, piece, rng):
    """Stepping stones across the creek: flat-topped boulders, their tops worn smooth."""
    for box in piece["boxes"]:
        s, c, yaw = box["size"], tuple(box["pos"]), box["yaw"]
        rock(b, c, s, yaw, rng, "dbr_granite", top="dbr_slate", jitter=0.05, chamfer=0.25, taper=0.85)


# ------------------------------------------------------------------------------------------------ set pieces (step 8)
# (World art 0.17, outdoor step 8) The campsite, the hunting stands, the farm's field, fences and tractor, drawn round
# the same gray boxes as before (gen SET_KINDS). The checkpoint's booth is the extract camps' guard hut.
def _ends(box):
    """A pitched box's two end points along its length (local z) and its length."""
    (x, y, z), s = box["pos"], box["size"]
    d = rot((0.0, 0.0, 1.0), box["yaw"], box["pitch"])
    h = s[2] / 2
    return (x - d[0] * h, y - d[1] * h, z - d[2] * h), (x + d[0] * h, y + d[1] * h, z + d[2] * h), s[2]


def _beam(b, p0, p1, w, h, mat, tile=1.0, roll=0.0):
    """A beam (w wide, h high) from p0 to p1."""
    d = v_sub(p1, p0)
    L = math.sqrt(dot(d, d))
    yaw = math.degrees(math.atan2(d[0], d[2]))
    pitch = -math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    b.box(v_scale(v_add(p0, p1), 0.5), (w, h, L), yaw=yaw + roll, pitch=pitch, style=flat(mat, tile))


def draw_firepit(b, piece, rng):
    """A ring of fieldstones round grey ashes and charred logs, a cooking tripod with a pot over it, a few cans."""
    xs = [bx["pos"][0] for bx in piece["boxes"]]
    zs = [bx["pos"][2] for bx in piece["boxes"]]
    c = (sum(xs) / 4, 0.0, sum(zs) / 4)
    y0 = ground(c[0], c[2])
    for k in range(11):   # the ring (bigger stones where the four solid ones are)
        a = 2 * math.pi * k / 11 + rng.uniform(-0.1, 0.1)
        r = 0.8 + rng.uniform(-0.06, 0.06)
        s = rng.uniform(0.32, 0.46)
        p = (c[0] + math.cos(a) * r, 0, c[2] + math.sin(a) * r)
        rock(b, (p[0], ground(p[0], p[2]) + s * 0.3, p[2]), (s, s * 0.62, s * rng.uniform(0.8, 1.1)), math.degrees(a), rng,
             rng.choice(("dbr_granite", "dbr_mossrock", "dbr_slate")), jitter=0.12, chamfer=0.3)
    cyl(b, (c[0], y0 + 0.02, c[2]), 0.62, 0.05, "dbr_ash", sides=12, cap_mat="dbr_ash")
    for k in range(4):   # charred logs in a little star
        a = math.pi / 2 * k + rng.uniform(-0.3, 0.3)
        p0 = (c[0] + math.cos(a) * 0.08, y0 + 0.16, c[2] + math.sin(a) * 0.08)
        p1 = (c[0] + math.cos(a) * 0.55, y0 + 0.08, c[2] + math.sin(a) * 0.55)
        _beam(b, p0, p1, 0.11, 0.11, "dbr_burnt")
    top = (c[0], y0 + 1.25, c[2])
    for k in range(3):   # the tripod and the pot on its chain
        a = 2 * math.pi * k / 3 + 0.4
        _beam(b, (c[0] + math.cos(a) * 0.75, y0, c[2] + math.sin(a) * 0.75), top, 0.05, 0.05, "wood_dark")
    _beam(b, top, (c[0], y0 + 0.62, c[2]), 0.015, 0.015, "trim_dark")
    cyl(b, (c[0], y0 + 0.47, c[2]), 0.17, 0.28, "trim_dark", sides=10, cap_mat="black")
    for _ in range(3):   # cans by the ring
        a = rng.uniform(0, 2 * math.pi)
        p = (c[0] + math.cos(a) * 1.25, 0, c[2] + math.sin(a) * 1.25)
        cyl(b, (p[0], ground(p[0], p[2]) + 0.04, p[2]), 0.04, 0.11, rng.choice(("steel_light", "dbr_cont_r", "olive")),
            sides=6, axis=rng.choice(("y", "z")), yaw=rng.uniform(0, 180))


def draw_logseat(b, piece, rng):
    """A log to sit on by the fire: bark, sawn ends, a wedge under it so it doesn't roll."""
    box = piece["boxes"][0]
    s, (x, y, z), yaw = box["size"], box["pos"], box["yaw"]
    y0 = y - s[1] / 2
    cyl(b, (x, y0 + 0.21, z), 0.21, s[2], "cabin_bark_d", sides=10, axis="z", yaw=yaw, cap_mat="wood_light")
    f = frame_of(b, box)
    for sz in (-0.7, 0.7):
        f.box((0.24, 0.04, sz), (0.12, 0.08, 0.2), style=no_bottom("wood", 1.0))


def draw_stand(b, piece, rng):
    """A hunting stand: four log legs braced crosswise, a plank deck on joists, plank rails on three sides, a cleated
    plank ramp up the open side. Looks: b open rails; c a burlap blind round the rails and a tin roof on corner poles;
    d cut branches tied round the rails and a camo net over it (the roof and net are picture only, over head height)."""
    bx = piece["boxes"]
    deck, legs, rails, ramp = bx[0], bx[1:5], bx[5:8], bx[8]
    look = piece["look"]
    (dx, dy, dz), ds = deck["pos"], deck["size"]
    top = dy + ds[1] / 2
    hw = ds[0] / 2
    for leg in legs:   # log legs to the ground
        (x, y, z), s = leg["pos"], leg["size"]
        g = ground(x, z) - 0.15
        cyl(b, (x, (g + top - 0.2) / 2, z), 0.13, top - 0.2 - g, "cabin_bark_b", sides=8, cap_mat="wood_light")
    pts = {(round(l["pos"][0] - dx), round(l["pos"][2] - dz)): l["pos"] for l in legs}
    corners = sorted(pts.items())
    by = {k: v for k, v in corners}
    sides = [((-1, -1), (1, -1)), ((-1, -1), (-1, 1)), ((1, -1), (1, 1)), ((-1, 1), (1, 1))]
    for a, c in sides:   # X braces between the legs (the ramp side gets one rail-high brace only)
        pa, pc = by.get(a), by.get(c)
        if pa is None or pc is None:
            continue
        lo_a, lo_c = ground(pa[0], pa[2]) + 0.4, ground(pc[0], pc[2]) + 0.4
        hi = top - 0.45
        if a[1] == 1 and c[1] == 1:
            _beam(b, (pa[0], hi, pa[2]), (pc[0], hi, pc[2]), 0.08, 0.14, "wood")
            continue
        _beam(b, (pa[0], lo_a, pa[2]), (pc[0], hi, pc[2]), 0.07, 0.07, "cabin_bark_b")
        _beam(b, (pc[0], lo_c, pc[2]), (pa[0], hi, pa[2]), 0.07, 0.07, "cabin_bark_b")
    f = Frame(b, (dx, top - ds[1], dz), 0.0)
    for sx in (-1, 1):   # joists, then deck planks across them
        f.box((sx * (hw - 0.15), 0.06, 0), (0.12, 0.12, ds[2]), style=flat("wood_dark", 1.0))
    n = 12
    for k in range(n):
        z = -ds[2] / 2 + ds[2] * (k + 0.5) / n
        f.box((rng.uniform(-0.02, 0.02), 0.15, z), (ds[0] + rng.uniform(-0.05, 0.05), 0.07, ds[2] / n - 0.02),
              yaw=rng.uniform(-1.2, 1.2), style=flat(rng.choice(("wood", "wood", "wood_light")), 1.0))
    # rails: uprights at the corners and middles, a top rail and a mid board
    up = [(-hw + 0.05, -hw + 0.05), (hw - 0.05, -hw + 0.05), (-hw + 0.05, hw - 0.05), (hw - 0.05, hw - 0.05),
          (0, -hw + 0.05), (-hw + 0.05, 0), (hw - 0.05, 0)]
    for x, z in up:
        f.box((x, ds[1] + 0.52, z), (0.09, 1.04, 0.09), style=flat("wood_dark", 1.0))
    for x0, z0, x1, z1 in ((-hw, -hw + 0.05, hw, -hw + 0.05), (-hw + 0.05, -hw, -hw + 0.05, hw), (hw - 0.05, -hw, hw - 0.05, hw)):
        for yh, hh in ((1.0, 0.1), (0.55, 0.18)):
            if x0 == x1:
                f.box((x0, ds[1] + yh, (z0 + z1) / 2), (0.05, hh, z1 - z0), style=flat("wood", 1.0))
            else:
                f.box(((x0 + x1) / 2, ds[1] + yh, z0), (x1 - x0, hh, 0.05), style=flat("wood", 1.0))
    fl = ds[1]
    if look == "c":   # burlap blind on the rails (outside them), tin roof on poles at the corners
        for x0, z0, x1, z1 in ((-hw, -hw - 0.03, hw, -hw - 0.03), (-hw - 0.03, -hw, -hw - 0.03, hw), (hw + 0.03, -hw, hw + 0.03, hw)):
            if x0 == x1:
                f.box((x0, fl + 0.55, (z0 + z1) / 2), (0.02, 0.95, z1 - z0), style=flat("dbr_burlap", 2.0))
            else:
                f.box(((x0 + x1) / 2, fl + 0.55, z0), (x1 - x0, 0.95, 0.02), style=flat("dbr_burlap", 2.0))
        for x, z in ((-hw + 0.05, -hw + 0.05), (hw - 0.05, -hw + 0.05), (-hw + 0.05, hw - 0.05), (hw - 0.05, hw - 0.05)):
            f.box((x, fl + 1.1 + 0.5, z), (0.08, 1.05 if z < 0 else 0.85, 0.08), style=flat("wood_dark", 1.0))
        f.box((0, fl + 2.08, 0), (ds[0] + 0.5, 0.05, ds[2] + 0.6), pitch=-7, style=_solid_tile("shed_metal"))
    elif look == "d":   # cut branches tied round the rails, a camo net over the top
        for _ in range(16):
            side = rng.randrange(3)
            t = rng.uniform(-hw, hw)
            x, z = ((t, -hw - 0.1), (-hw - 0.1, t), (hw + 0.1, t))[side]
            rock(b, f.p(x, fl + rng.uniform(0.45, 0.95), z), (0.55, 0.45, 0.55), rng.uniform(0, 90), rng,
                 rng.choice(("dbr_leaf_c", "dbr_leaf_b")), jitter=0.22, chamfer=0.4)
        N = 4
        for i in range(N):
            for j in range(N):
                def P(u, v):
                    sag = 0.12 * math.sin(math.pi * u / N) * math.sin(math.pi * v / N)
                    return f.p(-hw - 0.2 + (ds[0] + 0.4) * u / N, fl + 2.15 - sag, -hw - 0.2 + (ds[2] + 0.4) * v / N)
                a, c2, d2, e = P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)
                for m, off in (("dbr_leaf_c", 5), ("dbr_canvas", -5)):
                    tri(b, a, c2, d2, m, v_add(a, (0, -off, 0)))
                    tri(b, a, d2, e, m, v_add(a, (0, -off, 0)))
        for x, z in ((-hw + 0.05, -hw + 0.05), (hw - 0.05, -hw + 0.05), (-hw + 0.05, hw - 0.05), (hw - 0.05, hw - 0.05)):
            f.box((x, fl + 1.1 + 0.5, z), (0.06, 1.1, 0.06), style=flat("cabin_bark_b", 1.0))
    # the ramp: two stringers, cleated planks, a hand rope
    p0, p1, L = _ends(ramp)
    lo, hi = (p0, p1) if p0[1] < p1[1] else (p1, p0)
    w = ramp["size"][0]
    yaw = ramp["yaw"]
    ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    side = lambda p, o, dy=0.0: (p[0] + ca * o, p[1] + dy, p[2] - sa * o)
    for o in (-w / 2 + 0.08, w / 2 - 0.08):
        _beam(b, side(lo, o, -0.05), side(hi, o, -0.05), 0.1, 0.22, "wood_dark")
    steps = int(L / 0.32)
    for k in range(steps):
        t = (k + 0.5) / steps
        p = tuple(lo[i] + (hi[i] - lo[i]) * t for i in range(3))
        b.box((p[0], p[1] + 0.08, p[2]), (w, 0.05, 0.22), yaw=yaw, pitch=ramp["pitch"],
              style=flat(rng.choice(("wood", "wood_light")), 1.0))
        if k % 2 == 0:
            b.box((p[0], p[1] + 0.13, p[2]), (w - 0.3, 0.04, 0.05), yaw=yaw, pitch=ramp["pitch"], style=flat("wood_dark", 1.0))


def _solid_tile(mat, tile=1.0):
    return lambda n, m, q: (mat, uv_world(tile))


def draw_fence(b, piece, rng):
    """A farm fence along its strip pieces: b split rails (three, on log posts), c a board fence (four boards with
    gaps), d a woven stake fence. Posts every 2 m, on the ground; the rails follow it."""
    look = piece["look"]
    for box in piece["boxes"]:
        p0, p1, L = _ends(box)
        n = max(1, round(L / 2.0))
        d = v_sub(p1, p0)
        pts = []
        for k in range(n + 1):
            t = k / n
            x, z = p0[0] + d[0] * t, p0[2] + d[2] * t
            pts.append((x, ground(x, z), z))
        for k, p in enumerate(pts[:-1] if box is not piece["boxes"][-1] else pts):
            if look == "b":
                cyl(b, (p[0], p[1] + 0.55, p[2]), 0.08, 1.25, "cabin_bark_b", sides=6, cap_mat="wood_light")
            else:
                b.box((p[0], p[1] + 0.6, p[2]), (0.13, 1.3, 0.13), yaw=box["yaw"], style=no_bottom("wood_dark", 1.0))
        for a, c in zip(pts, pts[1:]):
            if look == "b":
                for yh in (0.32, 0.68, 1.02):
                    _beam(b, (a[0], a[1] + yh + rng.uniform(-0.03, 0.03), a[2]), (c[0], c[1] + yh + rng.uniform(-0.03, 0.03), c[2]),
                          0.09, 0.11, "cabin_bark_b", roll=rng.uniform(-4, 4))
            elif look == "c":
                for yh in (0.2, 0.47, 0.74, 1.01):
                    _beam(b, (a[0], a[1] + yh, a[2]), (c[0], c[1] + yh, c[2]), 0.04, 0.17, "barn_boards" if rng.random() < 0.85 else "wood_light")
            else:
                seg = v_sub(c, a)
                m = max(2, int(math.hypot(seg[0], seg[2]) / 0.22))
                for i in range(1, m):
                    t = i / m
                    q = (a[0] + seg[0] * t, a[1] + seg[1] * t, a[2] + seg[2] * t)
                    hh = 1.0 + rng.uniform(-0.06, 0.08)
                    b.box((q[0], q[1] + hh / 2 - 0.05, q[2]), (0.05, hh, 0.05), yaw=box["yaw"] + rng.uniform(0, 40),
                          style=no_bottom("cabin_bark_d", 1.0))
                for yh in (0.3, 0.62, 0.92):
                    _beam(b, (a[0], a[1] + yh, a[2]), (c[0], c[1] + yh, c[2]), 0.08, 0.13, "dbr_pole")


def draw_farmland(b, piece, rng):
    """The farm's ground: the yard in the ground's own look (grass, the dirt tracks painted by the generator's splat
    map), the field ploughed soil under the crop strips."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    f.at = (f.at[0], 0.0, f.at[2])
    W, D = box["size"][0], box["size"][2]
    # (the yard: the ground's own look, its shader; under it there's no ground, the farm stands on a flat pad)
    draped(b, f, -W / 2, W / 2, -D / 2, D / 2, 0.0, GROUND, step=4.0, lip=0.3, tile=2.0)
    # (the field: map x 282-342, z 46-96; the box's middle is map (294, 54))
    draped(b, f, -12.0, 48.0, -8.0, 42.0, 0.035, "dbr_soil", step=2.0, lip=0.12, tile=2.0)


CROP_LOOK = {"b": ("dbr_wheat", "dbr_wheat_top"), "c": ("dbr_maize", "dbr_maize_top"), "d": ("dbr_sunfl", "dbr_sunfl_top")}


def draw_crops(b, piece, rng):
    """A strip of crops: wheat (b), young maize (c) or sunflowers going over (d). The crops themselves are swaying cards
    (scripts/trees.gd kinds 5-7, from the generator); this is the dense stand in the middle under them, about half their
    height, so the strip reads as the solid waist-high cover its box is (the cards hide its edges)."""
    box = piece["boxes"][0]
    side, top = CROP_LOOK[piece["look"]]
    (x, y, z), s = box["pos"], box["size"]
    y0 = y - s[1] / 2
    seg = 0.8
    n = int(s[0] / seg)
    style = lambda n_, m, q: None if n_[1] < -0.7 else ((top, uv_world(1.0)) if n_[1] > 0.7 else (side, uv_world(1.0)))
    for k in range(n):
        xc = x - s[0] / 2 + seg * (k + 0.5)
        h = rng.uniform(0.45, 0.6)
        b.box((xc, y0 + h / 2 - 0.05, z + rng.uniform(-0.08, 0.08)), (seg + 0.05, h + 0.1, s[2] - 1.3 + rng.uniform(-0.1, 0.1)),
              yaw=rng.uniform(-2, 2), style=style)


def draw_hay(b, piece, rng):
    """A round hay bale on its side: rolled hay, a wrap of twine, loose hay round its foot."""
    box = piece["boxes"][0]
    (x, y, z), s_ = box["pos"], box["size"]
    y0 = y - s_[1] / 2
    r = s_[1] / 2
    cyl(b, (x, y0 + r - 0.03, z), r, s_[0] - 0.05, "hay_kit", sides=12, axis="x", yaw=box["yaw"], cap_mat="hay_kit", tile=1.0)
    for t in (-0.35, 0.0, 0.35):   # the twine
        ca, sa = math.cos(math.radians(box["yaw"])), math.sin(math.radians(box["yaw"]))
        cyl(b, (x + ca * t, y0 + r - 0.03, z - sa * t), r + 0.012, 0.03, "wood_light", sides=12, axis="x", yaw=box["yaw"], caps=False)
    f = frame_of(b, box)
    for _ in range(6):
        f.box((rng.uniform(-1.0, 1.0), 0.02, rng.uniform(-1.0, 1.0)), (rng.uniform(0.3, 0.6), 0.04, rng.uniform(0.15, 0.3)),
              yaw=rng.uniform(0, 180), style=no_bottom("hay_kit", 1.0))


def draw_boom(b, piece, rng):
    """The checkpoint's boom gate: a striped arm raised on its post (a concrete foot, a counterweight, a sign)."""
    box = piece["boxes"][0]
    f = frame_of(b, box)
    f.box((0, 0.12, 0), (0.6, 0.24, 0.6), style=no_bottom("dbr_conc", 1.0))
    f.box((0, 0.65, 0), (0.22, 0.85, 0.22), style=no_bottom("dbr_trk_o", 1.0))
    f.box((0, 1.1, 0), (0.32, 0.18, 0.32), style=flat("trim_dark", 1.0))
    up = 72.0
    L = 6.0
    a, c = math.cos(math.radians(up)), math.sin(math.radians(up))
    p0, p1 = f.p(0, 1.1, 0.0), f.p(a * L, 1.1 + c * L, 0.0)
    _beam(b, p0, p1, 0.12, 0.12, "dbr_redwhite", tile=1.0)
    _beam(b, f.p(0, 1.1, 0.0), f.p(-a * 0.9, 1.1 - c * 0.9, 0.0), 0.2, 0.26, "trim_dark")   # counterweight
    f.box((0.0, 0.7, -0.13), (0.5, 0.35, 0.03), style=flat("sg_red_flat", 1.0))        # a red "stop" board on the post


class _Turned:
    """A Builder seen through a turn round `pivot` (for make_building props drawn facing north)."""

    def __init__(self, b, pivot, yaw):
        self.b, self.pivot, self.yaw = b, pivot, yaw

    def box(self, c, size, yaw=0.0, pitch=0.0, style=None):
        p = v_add(rot(v_sub(c, self.pivot), self.yaw, 0.0), self.pivot)
        self.b.box(p, size, yaw=yaw + self.yaw, pitch=pitch, style=style)


def draw_tractor(b, piece, rng):
    """The farm's old tractor by the field (the barn's one, make_building prop_farm_tractor), parked at an angle."""
    box = piece["boxes"][0]
    c, s = tuple(box["pos"]), box["size"]

    class Ctx:
        pass
    ctx = Ctx()
    ctx.b = _Turned(b, c, box["yaw"])
    mb.prop_farm_tractor(ctx, c, s)


def draw_none(b, piece, rng):
    """Trees are drawn by scripts/trees.gd (outdoor step 7), not in the chunk models: only their boxes are kept."""


DRAW = {"ruin": draw_ruin, "wall": draw_wall, "berm": draw_berm, "rocks": draw_rocks, "rubble": draw_rubble, "container": draw_container,
        "truck": draw_truck, "sandbags": draw_sandbags, "barrier": draw_barrier, "tanktrap": draw_tanktrap,
        "drums": draw_drums, "dumpster": draw_dumpster, "crater": draw_crater, "junk": draw_junk, "bush": draw_bush,
        "plaza": draw_plaza, "fountain": draw_fountain, "statue": draw_statue, "planter": draw_planter, "stall": draw_stall,
        "kiosk": draw_kiosk, "lamp": draw_lamp,
        "trench": draw_trench, "tent": draw_tent, "hut": draw_hut, "crates": draw_crates, "net": draw_net,
        "shelter": draw_shelter, "bench": draw_bench, "pole": draw_pole, "pole_snap": draw_pole_snap,
        "wire": draw_wire, "wire_down": draw_wire_down, "walk": draw_walk, "flags": draw_walk,
        "sign_rail": draw_sign, "track": draw_track, "bridge": draw_bridge, "boxcar": draw_boxcar,
        "loco": draw_loco, "wagon": draw_boxcar, "tanker": draw_tanker, "signal": draw_signal, "points": draw_points,
        "cave": draw_cave, "tree": draw_none, "deadtree": draw_none, "culvert": draw_culvert, "bank": draw_bank, "log": draw_log, "stones": draw_stones, "sign_town": draw_sign, "sign_stop": draw_sign, "sign_speed": draw_sign, "sign_dir": draw_sign,
        "booth": draw_hut, "camptent": draw_tent, "firepit": draw_firepit, "logseat": draw_logseat, "stand": draw_stand,
        "fence": draw_fence, "farmland": draw_farmland, "crops": draw_crops, "tractor": draw_tractor,
        "hay": draw_hay, "boom": draw_boom}


# ------------------------------------------------------------------------------------------------ small details (step 9)
# Litter in the gutters, tyre marks and scorch marks on the roads (pieces from the generator's street_details), posters
# on the poles, NOVA and X1 marks sprayed on walls and containers (Bloxov Battlegrounds is Exion's side: mostly X1).
def detail_decals():
    a = DECALS
    rng = random.Random("detail decals")

    def x1_tag(c):
        c.rect(0, 0, c.w, c.h, "clear")
        mb.paint_x1(c, 5, 4, c.h - 7, "black", 3)
        for x in (6, 20, 27):
            c.rect(x, rng.randrange(0, 3), x + 1, 5, "black")

    def nova_tag(c):
        c.rect(0, 0, c.w, c.h, "clear")
        _say(c, 5, "NOVA", "sg_blue", 2)
        for _ in range(int(c.w * c.h * 0.08)):
            c.put(rng.randrange(c.w), rng.randrange(c.h), "clear")

    def poster_x1(c):     # Exion's: a black X1 on red, a black band at the foot
        c.rect(0, 0, c.w, c.h, "sg_red")
        c.rect(0, 0, c.w, 4, "black")
        mb.paint_x1(c, 2, 7, 11, "black", 2)
        c.blotch(["paper"], 3, rng, size=(1, 2))

    def poster_missing(c):   # a missing person sheet: a grey photo, lines of writing
        c.rect(0, 0, c.w, c.h, "paper")
        c.rect(3, 9, c.w - 3, c.h - 3, "steel")
        c.rect(5, 11, c.w - 5, c.h - 5, "iron")
        for y in (2, 5):
            c.rect(2, y, c.w - 2 - rng.randrange(0, 4), y + 1, "iron")

    def poster_notice(c):    # an army notice: a header bar and lines
        c.rect(0, 0, c.w, c.h, "sg_cream")
        c.rect(0, c.h - 5, c.w, c.h, "sg_grn")
        for y in range(3, c.h - 7, 3):
            c.rect(2, y, c.w - 2 - rng.randrange(0, 5), y + 1, "iron")
    a.add("tag_x1", 40, 26, x1_tag)
    a.add("tag_nova", 40, 19, nova_tag)
    for name, painter in (("poster_x1", poster_x1), ("poster_missing", poster_missing), ("poster_notice", poster_notice)):
        a.add(name, 16, 22, painter)


def _decal(b, f, c, w, h, region):
    """A flat decal (w x h m) in frame f at local c, facing local +z."""
    pts = [f.p(c[0] - w / 2, c[1] - h / 2, c[2]), f.p(c[0] + w / 2, c[1] - h / 2, c[2]),
           f.p(c[0] + w / 2, c[1] + h / 2, c[2]), f.p(c[0] - w / 2, c[1] + h / 2, c[2])]
    b.poly(pts, rot((0, 0, 1), f.yaw, 0.0), "decals_cut", mb.uv_fit(DECALS.regions[region]))


def spray_tag(b, box, rng, chance, lift=0.0):
    """Maybe a sprayed mark on one long side of a wall-like box (mostly X1, now and then NOVA)."""
    if rng.random() > chance:
        return
    (x, y, z), s = box["pos"], box["size"]
    if max(s[0], s[2]) < 1.8 or s[1] < 1.3:
        return
    along_z = s[2] >= s[0]
    side = rng.choice((-1, 1))
    yaw = box["yaw"] + (90 if along_z else 0) + (0 if side > 0 else 180)
    half = (s[0] if along_z else s[2]) / 2 + lift + 0.015
    f = Frame(b, (x, y - s[1] / 2, z), yaw)
    nova = rng.random() < 0.25
    w, h = (1.25, 0.6) if nova else (1.25, 0.8)
    if h + 0.5 > s[1]:
        return
    f.at = f.p(0, 0, half)
    _decal(b, f, (rng.uniform(-0.2, 0.2) * (max(s[0], s[2]) - w), 0.45 + h / 2 + rng.uniform(0, 0.3), 0.0), w, h,
           "tag_nova" if nova else "tag_x1")


def draw_litter(b, piece, rng):
    """Rubbish in a gutter: papers, cans, a bottle, a crushed box."""
    box = piece["boxes"][0]
    x, z = box["pos"][0], box["pos"][2]
    for _ in range(rng.randint(5, 9)):
        px, pz = x + rng.uniform(-0.9, 0.9), z + rng.uniform(-0.9, 0.9)
        y = surface(px, pz)
        kind = rng.random()
        if kind < 0.5:   # a sheet of paper, a little crumpled
            b.box((px, y + 0.012, pz), (rng.uniform(0.2, 0.3), 0.012, rng.uniform(0.26, 0.34)), yaw=rng.uniform(0, 180),
                  pitch=rng.uniform(-4, 4), style=no_bottom("dbr_paper", 1.0))
        elif kind < 0.8:
            cyl(b, (px, y + 0.035, pz), 0.035, 0.12, rng.choice(("steel_light", "dbr_cont_r", "olive")), sides=6,
                axis="z", yaw=rng.uniform(0, 180))
        elif kind < 0.9:
            cyl(b, (px, y + 0.04, pz), 0.04, 0.28, "dbr_cont_g", sides=6, axis="z", yaw=rng.uniform(0, 180))
        else:
            b.box((px, y + 0.05, pz), (0.35, 0.1, 0.28), yaw=rng.uniform(0, 180), pitch=rng.uniform(-8, 8),
                  style=no_bottom("carton", 1.0))


def draw_skid(b, piece, rng):
    """Tyre marks: two dark streaks bending a little, laid on the road."""
    box = piece["boxes"][0]
    (x, _, z), L, yaw = box["pos"], box["size"][2], box["yaw"]
    f = Frame(b, (x, 0.0, z), yaw)
    bend = rng.uniform(-0.6, 0.6)
    n = max(2, int(L / 1.2))
    for side in (-0.75, 0.75):
        prev = None
        for k in range(n + 1):
            t = k / n
            lx, lz = side + bend * (t - 0.5) ** 2 * 4 - bend, (t - 0.5) * L
            p = f.p(lx, 0, lz)
            p = (p[0], surface(p[0], p[2]) + 0.012, p[2])
            if prev is not None:
                d = v_sub(p, prev)
                ax = norm((d[2], 0.0, -d[0]))
                w = 0.11 * (1.0 - abs(t - 0.5))
                b.poly([v_add(prev, v_scale(ax, -w)), v_add(prev, v_scale(ax, w)), v_add(p, v_scale(ax, w)), v_add(p, v_scale(ax, -w))],
                       (0, 1, 0), "dbr_tyre", uv_world(1.0))
            prev = p


def draw_roadburn(b, piece, rng):
    """A scorch mark on the road: an uneven dark blot, ash in the middle."""
    box = piece["boxes"][0]
    (x, _, z), r = box["pos"], box["size"][0] / 2
    for mat, k, lift in (("dbr_scorch", 1.0, 0.008), ("dbr_burnt", 0.55, 0.011)):
        n = 11
        ring = []
        for i in range(n):
            a = 2 * math.pi * i / n
            rr = r * k * rng.uniform(0.7, 1.0)
            px, pz = x + math.cos(a) * rr, z + math.sin(a) * rr
            ring.append((px, surface(px, pz) + lift, pz))
        c = (x, surface(x, z) + lift, z)
        for i in range(n):
            b.poly([c, ring[i], ring[(i + 1) % n]], (0, 1, 0), mat, uv_world(2.0))


def pole_poster(b, f, look, rng):
    """Sometimes a poster or two pasted on a pole, at eye height."""
    if rng.random() > 0.35:
        return
    r = 0.16 if look != "d" else 0.13
    for k in range(rng.randint(1, 2)):
        a = rng.uniform(0, 360)
        g = Frame(b, f.at, f.yaw + a)
        _decal(b, g, (0, 1.6 + k * 0.55 + rng.uniform(-0.1, 0.1), r), 0.48, 0.66,
               rng.choice(("poster_x1", "poster_x1", "poster_missing", "poster_notice")))


DRAW.update({"litter": draw_litter, "skid": draw_skid, "roadburn": draw_roadburn})

# ------------------------------------------------------------------------------------------------ the border (step 9)
# (owner 2026-10-18: "change that big grey box around the map into something different") The edge's wall is only
# collision now; this draws what's there instead, from art_source/outdoor/border.json (tools/gen_old_bloxov.py
# write_border): the land going on outside (hills climbing away, its forest is scripts/trees.gd's), the line itself
# (look b a border fence: concrete posts, chain-link, barbed wire on outriggers; c a rock bank; d an army line of hesco
# and coiled wire), signs on it, and the roads and the railway running out through closed crossings.
BORDER = {}


def _border_sign(c, big, small):
    c.rect(0, 0, c.w, c.h, "sg_wht")
    c.rect(0, c.h - 16, c.w, c.h, "sg_red")
    c.frame(0, 0, c.w, c.h, "sg_red")
    _say(c, c.h - 13, big, "sg_wht", 2)
    _say(c, 4, small, "sg_blk", 2)


def border_decals():
    a = DECALS
    for name, big, small in (("border_closed", "BORDER", "CLOSED"), ("border_mines", "DANGER", "MINES"),
                             ("border_stop", "STOP", "KEEP OUT")):
        w = max(Canvas.text_width(big, 2), Canvas.text_width(small, 2)) + 8
        a.add(name, w, 34, lambda c, big=big, small=small: _border_sign(c, big, small))


def k_chainlink(rng):
    """Chain-link: galvanised wire in diamonds, see-through between (a cut-out material, not in the atlas)."""
    c = Canvas(32, 32, "clear")
    for y in range(32):
        for x in range(32):
            u, v = (x + y) % 8, (x - y) % 8
            if u == 0 or v == 0:
                c.put(x, y, "steel" if (x * 7 + y * 3) % 11 else "rust")
    return c


def _bh(x, z):
    """The border land's height at Godot (x, z) (inside the map: the ground's)."""
    import bisect
    xs, zs, H = BORDER["xs"], BORDER["zs"], BORDER["h"]
    half = BORDER["size"] / 2
    if -half < x < half and -half < z < half:
        return ground(x, z)
    i = min(max(bisect.bisect_right(xs, x) - 1, 0), len(xs) - 2)
    j = min(max(bisect.bisect_right(zs, z) - 1, 0), len(zs) - 2)
    u = min(max((x - xs[i]) / (xs[i + 1] - xs[i]), 0.0), 1.0)
    v = min(max((z - zs[j]) / (zs[j + 1] - zs[j]), 0.0), 1.0)
    q = [H[j][i], H[j][i + 1], H[j + 1][i], H[j + 1][i + 1]]
    if None in q:
        return ground(x, z)
    ha, hb, hc, hd = q
    return ha + u * (hb - ha) + v * (hd - hb) if u >= v else ha + v * (hc - ha) + u * (hd - hc)


def _border_land(b):
    xs, zs, H = BORDER["xs"], BORDER["zs"], BORDER["h"]
    for j in range(len(zs) - 1):
        for i in range(len(xs) - 1):
            q = (H[j][i], H[j][i + 1], H[j + 1][i + 1], H[j + 1][i])
            if None in q:
                continue
            p = [(xs[i], q[0], zs[j]), (xs[i + 1], q[1], zs[j]), (xs[i + 1], q[2], zs[j + 1]), (xs[i], q[3], zs[j + 1])]
            for t in ((p[0], p[1], p[2]), (p[0], p[2], p[3])):   # (split like the ground: north-west to south-east)
                n = norm(cross(v_sub(t[2], t[0]), v_sub(t[1], t[0])))
                b.poly(list(t), n if n[1] > 0 else v_scale(n, -1), GROUND, uv_world(2.0))


def _ways_near(x, z, pad):
    for ox, oz, nx, nz, w, y0, kind in BORDER["ways"]:
        if abs((x - ox) * nz - (z - oz) * nx) < w / 2 + pad and abs((x - ox) * nx + (z - oz) * nz) < 3.0:
            return (ox, oz, nx, nz, w, y0, kind)
    return None


def _skip_line(x, z):
    """Stretches of the line with something else there: the waterfall's cliff (west) and the culvert (south)."""
    half = BORDER["size"] / 2
    mx, mz = x + half, z + half
    return (mx < 1.0 and 211.0 < mz < 234.0) or (mz > BORDER["size"] - 1.0 and 91.0 < mx < 112.0)


def _line_points(step):
    """Points along the line just inside the edge, each with its outward normal, in runs broken by the ways out."""
    half = BORDER["size"] / 2
    inset = 0.3
    runs = []
    for ox, oz, nx, nz in ((None, -half + inset, 0, -1), (None, half - inset, 0, 1), (-half + inset, None, -1, 0),
                           (half - inset, None, 1, 0)):
        run = []
        n = int((2 * half - 2 * inset) / step)
        for k in range(n + 1):
            t = -half + inset + k * (2 * half - 2 * inset) / n
            x, z = (t, oz) if ox is None else (ox, t)
            if _ways_near(x, z, 1.3) or _skip_line(x, z):
                if len(run) > 1:
                    runs.append(run)
                run = []
                continue
            run.append(((x, ground(x, z), z), (nx, 0.0, nz)))
        if len(run) > 1:
            runs.append(run)
    return runs


def _fence_b(b, rng):
    """A border fence: concrete posts every 3 m, chain-link 2.6 m high, an outrigger leaning out with three strands of
    barbed wire, red and white signs on it every so often."""
    signs = 0
    for run in _line_points(3.0):
        for k, (p, n) in enumerate(run):
            yaw = math.degrees(math.atan2(n[0], n[2]))
            f = Frame(b, (p[0], p[1] - 0.3, p[2]), yaw)
            f.box((0, 1.55, 0), (0.16, 3.1, 0.16), style=no_bottom("dbr_conc", 1.0))
            arm0, arm1 = f.p(0, 2.85, 0.05), f.p(0, 3.45, 0.62)
            _beam(b, arm0, arm1, 0.05, 0.05, "steel_light")
            if k + 1 < len(run):
                q, _ = run[k + 1]
                lo = 0.04
                pts = [(p[0], p[1] + lo, p[2]), (q[0], q[1] + lo, q[2]), (q[0], q[1] + 2.6, q[2]), (p[0], p[1] + 2.6, p[2])]
                b.poly(pts, (n[0], 0.0, n[2]), "chainlink", uv_world(0.5))
                _beam(b, (p[0], p[1] + 2.62, p[2]), (q[0], q[1] + 2.62, q[2]), 0.05, 0.05, "steel_light")
                g = Frame(b, (q[0], q[1] - 0.3, q[2]), yaw)
                for t in (0.35, 0.65, 0.95):   # barbed strands along the outriggers
                    a1 = v_add(arm0, v_scale(v_sub(arm1, arm0), t))
                    a2 = v_add(g.p(0, 2.85, 0.05), v_scale(v_sub(g.p(0, 3.45, 0.62), g.p(0, 2.85, 0.05)), t))
                    _beam(b, a1, a2, 0.018, 0.018, "trim_dark")
                if k % 15 == 7:   # a sign on the mesh, facing in
                    signs += 1
                    mid = v_scale(v_add(p, q), 0.5)
                    s = Frame(b, (mid[0] - n[0] * 0.04, (p[1] + q[1]) / 2, mid[2] - n[2] * 0.04), yaw + 180)
                    name = ("border_closed", "border_stop", "border_mines")[signs % 3]
                    rw, rh = DECALS.regions[name][2] - DECALS.regions[name][0], DECALS.regions[name][3] - DECALS.regions[name][1]
                    _plate(b, s, (0, 1.55, 0), 0.9, 0.9 * rh / rw, name, back_mat="metal", t=0.02)


def _fence_c(b, rng):
    """A rock bank: the land outside rises in a rocky slope straight from the line, boulders along its foot."""
    for run in _line_points(2.6):
        for k, (p, n) in enumerate(run):
            if rng.random() < 0.15:
                continue
            s = rng.uniform(1.4, 2.6)
            out = rng.uniform(-0.2, 1.4)
            c = (p[0] + n[0] * out, 0.0, p[2] + n[2] * out)
            rock(b, (c[0], _bh(c[0], c[2]) + s * 0.25, c[2]), (s * rng.uniform(1.0, 1.5), s * rng.uniform(0.6, 1.0), s),
                 rng.uniform(0, 90), rng, rng.choice(("dbr_granite", "dbr_mossrock", "dbr_granite", "dbr_slate")))
            if rng.random() < 0.5:   # and higher up the slope
                d = rng.uniform(2.5, 6.0)
                c = (p[0] + n[0] * d, 0.0, p[2] + n[2] * d)
                s = rng.uniform(1.2, 3.0)
                rock(b, (c[0], _bh(c[0], c[2]) + s * 0.2, c[2]), (s * 1.3, s * 0.7, s), rng.uniform(0, 90), rng,
                     rng.choice(("dbr_granite", "dbr_mossrock")))


def _fence_d(b, rng):
    """An army line: hesco bastions in a row along the line, coiled wire on stakes in front of them (outside)."""
    for run in _line_points(1.1):
        for k, (p, n) in enumerate(run):
            yaw = math.degrees(math.atan2(n[0], n[2]))
            f = Frame(b, (p[0], p[1] - 0.15, p[2]), yaw)
            f.box((0, 0.75, 0.2), (1.05, 1.5, 1.05), yaw=rng.uniform(-1.5, 1.5), style=no_bottom("dbr_hesco", 1.0))
            if k % 3 == 0 and k + 3 < len(run):   # a coil of wire as loops between stakes
                q, _ = run[k + 3]
                g = Frame(b, (q[0], q[1] - 0.15, q[2]), yaw)
                a, c = f.p(0, 0, 1.6), g.p(0, 0, 1.6)
                for i in range(10):
                    t0, t1 = i / 10, (i + 1) / 10
                    for ph in (0.0, math.pi):
                        p0 = v_add(v_add(a, v_scale(v_sub(c, a), t0)), (0, 0.55 + 0.45 * math.sin(t0 * 6 * math.pi + ph), 0))
                        p1 = v_add(v_add(a, v_scale(v_sub(c, a), t1)), (0, 0.55 + 0.45 * math.sin(t1 * 6 * math.pi + ph), 0))
                        _beam(b, p0, p1, 0.02, 0.02, "trim_dark")
                for st in (a, c):
                    _beam(b, st, v_add(st, (0, 1.1, 0)), 0.05, 0.05, "dbr_rail")


def _crossings(b, rng):
    """Where a road or the railway runs out: it goes on outside, closed at the line (concrete blocks across it, a
    boom down, a sign facing in)."""
    for ox, oz, nx, nz, w, y0, kind in BORDER["ways"]:
        yaw = math.degrees(math.atan2(nx, nz))
        f = Frame(b, (ox, 0.0, oz), yaw)
        rings = [0.0, 2.5, 6.0, 11.0, 18.0, 28.0, 42.0, 62.0, 90.0, 130.0, 185.0, 255.0]
        if kind == "road":
            for d0, d1 in zip(rings, rings[1:]):
                y_0, y_1 = y0 + 0.02 * d0 + 0.05, y0 + 0.02 * d1 + 0.05
                q = [f.p(-w / 2, 0, d0), f.p(w / 2, 0, d0), f.p(w / 2, 0, d1), f.p(-w / 2, 0, d1)]
                q = [(q[0][0], y_0, q[0][2]), (q[1][0], y_0, q[1][2]), (q[2][0], y_1, q[2][2]), (q[3][0], y_1, q[3][2])]
                b.poly(q, (0, 1, 0), "mo_asphalt", uv_world(4.0))
                z = d0 + 1.0
                while z + 3.0 < d1:   # the faded centre line, dashed
                    a, c = f.p(-0.06, 0, z), f.p(0.06, 0, z + 3.0)
                    ya, yc = y0 + 0.02 * z + 0.06, y0 + 0.02 * (z + 3.0) + 0.06
                    b.poly([(a[0], ya, a[2]), (f.p(0.06, 0, z)[0], ya, f.p(0.06, 0, z)[2]), (c[0], yc, c[2]),
                            (f.p(-0.06, 0, z + 3.0)[0], yc, f.p(-0.06, 0, z + 3.0)[2])], (0, 1, 0), "hz_flat", uv_world(1.0))
                    z += 6.0
            top = y0 + 0.05
        else:
            g = Frame(b, (ox, y0 + 0.12, oz), yaw)
            _track_line(b, g.p(0, 0, -0.5), g.p(0, 0, 255.0), y0 + 0.12, rng)
            top = y0 + 0.12
        # the closure at the line: jersey blocks across, and the sign
        n = int((w + 3.0) / 1.9)
        for k in range(n):   # (across the whole gap in the line: it stops 1.3 m past the road's edges)
            x = -w / 2 - 1.5 + (k + 0.5) * (w + 3.0) / n
            g = Frame(b, (f.p(x, 0, 1.2)[0], top, f.p(x, 0, 1.2)[2]), yaw + rng.uniform(-6, 6))
            g.box((0, 0.2, 0), (1.8, 0.4, 0.6), style=no_bottom("dbr_conc", 1.0))
            g.box((0, 0.6, 0), (1.8, 0.4, 0.34), style=no_bottom("dbr_conc", 1.0))
            g.box((0, 0.88, 0), (1.8, 0.16, 0.2), style=no_bottom("dbr_redwhite", 1.0))
        s = Frame(b, (f.p(0, 0, 0.4)[0], top, f.p(0, 0, 0.4)[2]), yaw + 180)
        for x in (-0.55, 0.55):
            s.box((x, 1.1, 0), (0.08, 2.2, 0.08), style=no_bottom("metal", 1.0))
        rw = DECALS.regions["border_closed"][2] - DECALS.regions["border_closed"][0]
        rh = DECALS.regions["border_closed"][3] - DECALS.regions["border_closed"][1]
        _plate(b, Frame(b, s.p(0, 0, 0.06), s.yaw), (0, 1.75, 0), 1.4, 1.4 * rh / rw, "border_closed", back_mat="metal")


def border():
    path = os.path.join(JSON_DIR, "border.json")
    if not os.path.exists(path):
        return None
    BORDER.update(json.load(open(path)))
    ORIGIN[:] = [0.0, 0.0]
    b = Builder()
    rng = random.Random("border")
    _border_land(b)
    {"b": _fence_b, "c": _fence_c, "d": _fence_d}[BORDER["look"]](b, rng)
    _crossings(b, rng)
    return b


def main():
    names = sys.argv[1:]
    os.makedirs(OUT_DIR, exist_ok=True)
    textures, mat_info = {}, {}
    for kit, painter in mb.KIT.items():
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"), painter,
                                         random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, kit == "glass")
    mat_info["ground"] = ("kit_dbr_ground", False, False)
    sign_decals()
    border_decals()
    detail_decals()
    mat_info["decals_cut"] = ("outdoor_decals", True, False)
    textures["kit_chainlink"] = Texture("kit_chainlink", os.path.join("art_source", "textures", "kit", "chainlink.png"),
                                        k_chainlink, random.Random("chainlink"))
    mat_info["chainlink"] = ("kit_chainlink", True, True)
    decal_png = os.path.join("art_source", "textures", "outdoor_decals.png")
    if os.path.exists(os.path.join(mb.ROOT, decal_png)):
        os.remove(os.path.join(mb.ROOT, decal_png))   # (painted fresh every run)
    textures["outdoor_decals"] = Texture("outdoor_decals", decal_png, lambda r: DECALS.c, random.Random("decals"))
    mat_info["decals"] = ("outdoor_decals", False, False)
    cells = mb.kit_atlas()
    TERRAIN.update(json.load(open(os.path.join(JSON_DIR, "terrain.json"))))
    total = 0
    for fn in sorted(os.listdir(JSON_DIR)):
        name = fn[:-5]
        if not fn.endswith(".json") or fn in ("terrain.json", "border.json", "collision.json") or (names and name not in names):
            continue
        data = json.load(open(os.path.join(JSON_DIR, fn)))
        ORIGIN[:] = data["origin"]
        b = Builder()
        for piece in data["pieces"]:
            _SHAPE_KEY[0] = f"{piece['kind']} {piece['seed']}"
            f0 = len(b.faces)
            DRAW[piece["kind"]](b, piece, random.Random(f"{piece['kind']} {piece['seed']}"))
            if piece["kind"] in SEE_THROUGH:
                see_through(b, f0, piece)
        if os.environ.get("BLOXOV_KERBS") != "0":   # (off for the options sheets' "today" pictures)
            draw_road_edges(b, random.Random("road edges " + name))
        out = os.path.join(OUT_DIR, name + ".glb")
        mb.write_glb(out, b, textures, mat_info, atlas=cells)
        mb.set_import_script(out)
        tris = sum(len(f) - 2 for f in b.faces)
        total += tris
        print(f"{name}: {len(data['pieces'])} pieces, {tris} triangles")
    if not names or "outdoor_border" in names:
        b = border()
        if b is not None:
            out = os.path.join(OUT_DIR, "outdoor_border.glb")
            mb.write_glb(out, b, textures, mat_info, atlas=cells)
            mb.set_import_script(out)
            tris = sum(len(f) - 2 for f in b.faces)
            total += tris
            print(f"outdoor_border: {tris} triangles")
    print(f"outdoor total: {total} triangles")
    if not names:   # (only on a full run: every chunk's shapes)
        with open(os.path.join(JSON_DIR, "collision.json"), "w") as f:
            json.dump({"note": "Written by art_source/scripts/make_outdoor.py: collision shaped like the drawing for the "
                       "pieces whose drawing isn't their box (read by tools/gen_old_bloxov.py).", "shapes": SHAPES}, f,
                      separators=(",", ":"))
        print(f"shaped collision: {len(SHAPES)} pieces, {sum(len(v['tris']) for v in SHAPES.values()) // 9} triangles")


if __name__ == "__main__":
    main()
