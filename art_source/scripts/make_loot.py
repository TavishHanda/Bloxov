"""Bloxov loot containers (World art, 0.17): one small model per container look, so a container fits its place
(owner: lockers in the school, safes where they make sense, the rest remodelled to suit the building).

The map generator picks the look for each container (tools/gen_old_bloxov.py, LOOT_LOOKS) and the game swaps the model
in (scripts/loot_container.gd, LOOKS: its name and collision size). What's inside doesn't change: that still comes from
the container's loot table (crate / locker / safe).

Run: python3 art_source/scripts/make_loot.py [look ...]   (all looks if none given)
Writes assets/models/loot/<look>.glb. Every model stands on the floor at the origin with its front facing -z, and is
no bigger than its size in loot_container.gd's LOOKS (that's its collision box). Uses the building kit textures
(art_source/textures/kit) plus art_source/textures/loot/ (flat colours and the decal atlas, 32 px per meter).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
from make_building import Atlas, Builder, Canvas, Texture, side_of, uv_world  # noqa: E402

FLAT = {"olive": "olive", "olive_dark": "olive_dark", "gold": "hazard_yellow", "blue": "sky_blue",
        "steel": "steel", "wood_dark": "wood_dark", "green": "green_dark"}


# ------------------------------------------------------------------------------------------------ decals
def loot_decals(rng):
    a = Atlas(256)

    def safe(c):            # 0.8 x 0.82 m
        c.rect(0, 0, c.w, c.h, "olive_dark")
        c.frame(0, 0, c.w, c.h, "black")
        c.frame(2, 2, c.w - 2, c.h - 11, "yellow_dark")             # gold pinstripe
        c.rect(1, c.h - 10, c.w - 1, c.h - 2, "iron_dark")          # name plate above it
        c.rect(1, 6, 2, 10, "iron"); c.rect(1, c.h - 16, 2, c.h - 12, "iron")   # hinges
        w = Canvas.text_width("BLOXOV")
        c.ctext(0, c.w, c.h - 8, "BLOXOV", "hazard_yellow")
        c.blotch(["olive", "iron_dark"], 4, rng, area=(3, 3, c.w - 3, c.h - 10))

    def locker(c):          # 0.75 x 1.9 m
        c.rect(0, 0, c.w, c.h, "sky_blue")
        c.frame(0, 0, c.w, c.h, "iron_dark")
        c.rect(c.w // 2, 0, c.w // 2 + 1, c.h, "iron_dark")
        for x0 in (3, c.w // 2 + 3):
            for k in range(4):
                c.rect(x0, c.h - 6 - k * 2, x0 + 7, c.h - 5 - k * 2, "iron_dark")     # vents
            c.rect(x0 + 4, c.h - 22, x0 + 7, c.h - 19, "bone")                       # name tag
        c.rect(c.w // 2 - 2, 28, c.w // 2, 34, "steel_light")                        # handles
        c.rect(c.w // 2 + 1, 28, c.w // 2 + 3, 34, "steel_light")
        c.rect(4, 22, 9, 26, "hazard_yellow")                                        # sticker
        c.blotch(["steel", "iron"], 6, rng, size=(2, 4))                             # dents, scratches
        c.rect(0, 0, c.w, 3, "iron_dark")

    def wardrobe(c):        # 1.0 x 2.0 m
        c.rect(0, 0, c.w, c.h, "wood")
        c.frame(0, 0, c.w, c.h, "wood_dark")
        c.rect(c.w // 2, 0, c.w // 2 + 1, c.h, "wood_dark")
        for x0, x1 in ((3, c.w // 2 - 2), (c.w // 2 + 3, c.w - 3)):
            c.frame(x0, 34, x1, c.h - 4, "wood_mid")
            c.frame(x0, 6, x1, 30, "wood_mid")
        c.rect(c.w // 2 - 2, 32, c.w // 2, 34, "bone")
        c.rect(c.w // 2 + 2, 32, c.w // 2 + 4, 34, "bone")
        c.blotch(["wood_light", "wood_mid"], 6, rng)
        c.rect(0, 0, c.w, 3, "wood_dark")

    def gun_cabinet(c):     # 0.9 x 1.9 m
        c.rect(0, 0, c.w, c.h, "wood_mid")
        c.frame(0, 0, c.w, c.h, "wood_dark")
        c.rect(3, 20, c.w - 3, c.h - 3, "black")                                    # glass, dark inside
        for x in (6, 13, 20):                                                       # rifles standing up
            c.rect(x, 22, x + 3, 30, "wood")                                         # stock
            c.rect(x + 1, 30, x + 2, c.h - 8, "iron")                                # barrel
            c.rect(x, 34, x + 3, 38, "iron_dark")                                    # receiver
        c.rect(c.w // 2, 20, c.w // 2 + 1, c.h - 3, "wood_dark")                     # door bars
        c.noise(3, 20, c.w - 3, c.h - 3, ["steel_light"], 0.03, rng)                 # glass glints
        c.frame(3, 4, c.w - 3, 17, "wood_dark")                                      # drawer
        c.rect(c.w // 2 - 1, 10, c.w // 2 + 2, 12, "hazard_yellow")                  # lock

    def filing(c):          # 0.5 x 1.3 m
        c.rect(0, 0, c.w, c.h, "steel")
        for k in range(4):
            y0 = 1 + k * 10
            c.frame(1, y0, c.w - 1, y0 + 9, "iron")
            c.rect(5, y0 + 3, c.w - 5, y0 + 4, "iron_dark")                          # handle
            c.rect(6, y0 + 6, c.w - 6, y0 + 8, "bone")                               # label
        c.blotch(["steel_light", "iron"], 3, rng)

    def toolbox(c):         # 0.8 x 0.8 m (cabinet)
        c.rect(0, 0, c.w, c.h, "red")
        c.frame(0, 0, c.w, c.h, "rust")
        for y0 in (3, 9, 14, 18, 22):
            c.rect(1, y0, c.w - 1, y0 + 1, "black")
            c.rect(c.w // 2 - 4, y0 + 2, c.w // 2 + 4, y0 + 3, "steel_light")
        c.blotch(["rust", "black"], 5, rng, size=(2, 3))

    def toolbox_top(c):     # 0.76 x 0.3 m
        c.rect(0, 0, c.w, c.h, "red")
        c.rect(0, 5, c.w, 6, "black")
        c.rect(c.w // 2 - 2, 3, c.w // 2 + 2, 7, "steel_light")

    def dresser(c):         # 1.0 x 0.9 m
        c.rect(0, 0, c.w, c.h, "wood")
        c.frame(0, 0, c.w, c.h, "wood_dark")
        for k, y0 in enumerate((2, 11, 20)):
            c.frame(2, y0, c.w - 2, y0 + 8, "wood_dark")
            if k == 1:
                c.rect(3, y0 + 6, c.w - 3, y0 + 7, "black")                          # left open a crack
            c.rect(8, y0 + 3, 10, y0 + 5, "bone")
            c.rect(c.w - 10, y0 + 3, c.w - 8, y0 + 5, "bone")
        c.blotch(["wood_light"], 4, rng)

    def kitchen(c):         # 1.0 x 0.9 m
        c.rect(0, 0, c.w, c.h, "steel_light")
        c.rect(0, 0, c.w, 3, "black")                                                # toe kick
        c.frame(1, 3, c.w // 2, c.h - 6, "steel")
        c.frame(c.w // 2, 3, c.w - 1, c.h - 6, "steel")
        c.frame(1, c.h - 6, c.w - 1, c.h - 1, "steel")                               # drawer
        c.rect(c.w // 2 - 3, 14, c.w // 2 - 2, 22, "black")
        c.rect(c.w // 2 + 2, 14, c.w // 2 + 3, 22, "black")
        c.rect(c.w // 2 - 4, c.h - 4, c.w // 2 + 4, c.h - 3, "black")
        c.blotch(["concrete", "sand"], 5, rng, size=(2, 4))                          # grease

    def chest(c):           # 0.9 x 0.5 m
        c.rect(0, 0, c.w, c.h, "wood_mid")
        for y in range(0, c.h, 4):
            c.rect(0, y, c.w, y + 1, "wood_dark")
        for x in (3, c.w - 6):
            c.rect(x, 0, x + 3, c.h, "iron_dark")                                    # iron bands
        c.rect(c.w // 2 - 2, c.h - 7, c.w // 2 + 2, c.h - 2, "hazard_yellow")        # lock
        c.put(c.w // 2, c.h - 5, "black")

    def hard_case(c):       # 1.0 x 0.5 m
        c.rect(0, 0, c.w, c.h, "olive")
        c.frame(0, 0, c.w, c.h, "olive_dark")
        c.rect(0, c.h - 4, c.w, c.h - 3, "olive_dark")                               # lid seam
        for x in (4, c.w - 8):
            c.rect(x, c.h - 6, x + 4, c.h - 1, "iron")                               # latches
        w = Canvas.text_width("SUPPLY")
        c.ctext(0, c.w, 3, "SUPPLY", "black")
        c.blotch(["sand", "olive_light"], 4, rng, size=(2, 3))

    def weapon_case(c):     # 1.15 x 0.36 m
        c.rect(0, 0, c.w, c.h, "iron_dark")
        c.rect(0, c.h - 4, c.w, c.h - 3, "black")
        for x in (4, c.w // 2 - 2, c.w - 8):
            c.rect(x, c.h - 6, x + 4, c.h - 1, "steel")
        w = Canvas.text_width("ARMS")
        c.ctext(0, c.w, 1, "ARMS", "bone")

    def med(c):             # 0.8 x 1.6 m
        c.rect(0, 0, c.w, c.h, "bone")
        c.frame(0, 0, c.w, c.h, "steel")
        c.rect(c.w // 2, 0, c.w // 2 + 1, c.h, "steel")
        cx, cy = c.w // 2, c.h - 12                                                 # green cross (not red: that's the
        c.rect(cx - 6, cy - 2, cx + 7, cy + 3, "green_dark")                          # Red Cross's protected emblem)
        c.rect(cx - 2, cy - 6, cx + 3, cy + 7, "green_dark")
        c.rect(c.w // 2 - 3, 18, c.w // 2 - 1, 24, "steel")
        c.rect(c.w // 2 + 2, 18, c.w // 2 + 4, 24, "steel")
        w = Canvas.text_width("MED")
        c.ctext(0, c.w, 28, "MED", "steel")
        c.blotch(["concrete", "sand"], 5, rng, size=(2, 4))

    def box_label(text, colour, ink):
        def paint(c):       # 0.5 x 0.4 m cardboard box side
            c.rect(0, 0, c.w, c.h, "wood_pale")
            c.noise(0, 0, c.w, c.h, ["wood_light", "sand"], 0.15, rng)
            c.rect(0, c.h - 2, c.w, c.h, "sand")                                     # tape
            c.rect(1, 2, c.w - 1, 9, colour)
            w = Canvas.text_width(text)
            c.ctext(0, c.w, 3, text, ink)
        return paint

    a.add("safe", 27, 26, safe)   # odd width: BLOXOV (23 px) gets a 1 px gap each side
    a.add("locker", 24, 61, locker)
    a.add("wardrobe", 32, 64, wardrobe)
    a.add("gun_cabinet", 29, 61, gun_cabinet)
    a.add("filing", 16, 42, filing)
    a.add("med", 26, 51, med)
    a.add("toolbox", 26, 26, toolbox)
    a.add("toolbox_top", 24, 10, toolbox_top)
    a.add("dresser", 32, 29, dresser)
    a.add("kitchen", 32, 29, kitchen)
    a.add("chest", 29, 16, chest)
    a.add("hard_case", 32, 16, hard_case)
    a.add("weapon_case", 37, 12, weapon_case)
    a.add("box_soda", 16, 13, box_label("SODA", "red", "bone"))
    a.add("box_food", 16, 13, box_label("FOOD", "hazard_yellow", "red"))
    return a


# ------------------------------------------------------------------------------------------------ styles
def solid(mat, tile=1.0):
    """One material all round (no bottom)."""
    return lambda n, m, q: None if side_of(n) == "-y" else (mat, uv_world(tile))


def front(atlas, region, mat, tile=1.0, side="-z"):
    """The front (-z) shows a decal, the rest `mat`."""
    fit = mb.uv_fit(atlas.regions[region])
    return lambda n, m, q: None if side_of(n) == "-y" else (("decals", fit) if side_of(n) == side else (mat, uv_world(tile)))


# ------------------------------------------------------------------------------------------------ models
def look_safe(b, d):
    for x in (-0.33, 0.33):
        for z in (-0.28, 0.28):
            b.box((x, 0.04, z), (0.08, 0.08, 0.08), style=solid("black"))
    b.box((0, 0.49, 0), (0.8, 0.82, 0.7), style=front(d, "safe", "olive_dark"))
    b.box((-0.12, 0.52, -0.37), (0.17, 0.17, 0.04), style=solid("gold"))           # dial
    b.box((-0.12, 0.52, -0.395), (0.03, 0.08, 0.01), style=solid("black"))
    b.box((0.2, 0.46, -0.38), (0.05, 0.24, 0.05), style=solid("gold"))             # handle


def look_locker(b, d):
    b.box((0, 0.95, 0.02), (0.75, 1.9, 0.48), style=front(d, "locker", "blue"))
    b.box((0.08, 1.98, 0.05), (0.42, 0.16, 0.32), yaw=8, style=solid("cardboard"))   # a box left on top


def look_wardrobe(b, d):
    b.box((0, 1.0, 0.0), (1.0, 1.96, 0.55), style=front(d, "wardrobe", "wood"))
    b.box((0, 1.99, 0.0), (1.04, 0.05, 0.57), style=solid("wood_dark"))


def look_gun_cabinet(b, d):
    b.box((0, 0.95, 0.0), (0.9, 1.9, 0.45), style=front(d, "gun_cabinet", "wood"))
    b.box((0, 1.92, 0.0), (0.94, 0.05, 0.47), style=solid("wood_dark"))


def look_filing(b, d):
    b.box((0, 0.65, 0.0), (0.5, 1.3, 0.6), style=front(d, "filing", "steel"))
    b.box((0.03, 1.31, 0.02), (0.3, 0.02, 0.4), yaw=-10, style=solid("bone"))       # papers on top
    b.box((-0.05, 1.33, 0.0), (0.26, 0.02, 0.34), yaw=15, style=solid("bone"))


def look_med(b, d):
    b.box((0, 0.8, 0.0), (0.8, 1.6, 0.4), style=front(d, "med", "bone"))


def look_toolbox(b, d):
    for x in (-0.34, 0.34):
        for z in (-0.18, 0.18):
            b.box((x, 0.05, z), (0.08, 0.1, 0.08), style=solid("black"))             # wheels
    b.box((0, 0.5, 0.0), (0.8, 0.8, 0.5), style=front(d, "toolbox", "red"))
    b.box((0, 1.05, 0.0), (0.76, 0.3, 0.46), style=front(d, "toolbox_top", "red"))
    b.box((0.43, 0.75, 0.0), (0.04, 0.04, 0.4), style=solid("steel"))               # push bar


def look_dresser(b, d):
    b.box((0, 0.45, 0.0), (1.0, 0.9, 0.5), style=front(d, "dresser", "wood"))
    b.box((0, 0.915, 0.0), (1.04, 0.03, 0.52), style=solid("wood_dark"))
    b.box((0.3, 1.02, 0.12), (0.16, 0.2, 0.03), yaw=-12, style=solid("trim_dark"))   # photo frame
    b.box((-0.28, 0.98, 0.05), (0.14, 0.1, 0.14), style=solid("bone"))              # jewellery box


def look_kitchen(b, d):
    b.box((0, 0.45, 0.0), (1.0, 0.9, 0.6), style=front(d, "kitchen", "steel"))
    b.box((0, 0.92, 0.0), (1.02, 0.04, 0.6), style=solid("metal"))
    b.box((0.22, 1.02, 0.05), (0.26, 0.16, 0.26), style=solid("trim_dark"))          # pot


def look_chest(b, d):
    b.box((0, 0.25, 0.0), (0.9, 0.5, 0.55), style=front(d, "chest", "wood"))
    b.box((0, 0.55, 0.0), (0.92, 0.1, 0.55), style=solid("wood_dark"))
    for x in (-0.3, 0.3):
        b.box((x, 0.55, 0.0), (0.06, 0.12, 0.57), style=solid("black"))


def look_hard_case(b, d):
    for x in (-0.4, 0.4):
        b.box((x, 0.025, 0.0), (0.1, 0.05, 0.58), style=solid("black"))
    b.box((0, 0.3, 0.0), (1.0, 0.5, 0.6), style=front(d, "hard_case", "olive"))
    b.box((0, 0.565, 0.0), (0.9, 0.03, 0.5), style=solid("olive_dark"))
    for x in (-0.51, 0.51):
        b.box((x, 0.38, 0.0), (0.03, 0.05, 0.22), style=solid("black"))              # end handles


def look_weapon_case(b, d):
    b.box((0, 0.06, 0.0), (1.2, 0.12, 0.55), style=solid("wood"))                    # pallet
    b.box((0, 0.3, 0.0), (1.15, 0.36, 0.45), style=front(d, "weapon_case", "trim_dark"))
    b.box((0, 0.5, 0.0), (0.3, 0.04, 0.05), style=solid("black"))


def look_duffel(b, d):
    b.box((0, 0.18, 0.0), (0.85, 0.36, 0.42), style=solid("olive"))
    for x in (-0.43, 0.43):
        b.box((x, 0.18, 0.0), (0.02, 0.3, 0.36), style=solid("olive_dark"))
    for x in (-0.2, 0.2):
        b.box((x, 0.18, 0.0), (0.06, 0.38, 0.44), style=solid("black"))              # straps
    b.box((0, 0.38, 0.0), (0.3, 0.04, 0.05), style=solid("black"))
    b.box((0, 0.362, 0.0), (0.7, 0.006, 0.03), style=solid("trim_dark"))             # zip


def look_stock_boxes(b, d):
    fit = {k: mb.uv_fit(d.regions[k]) for k in ("box_soda", "box_food")}

    def box_style(label):
        return lambda n, m, q: None if side_of(n) == "-y" else (
            ("decals", fit[label]) if side_of(n) == "-z" else ("cardboard", uv_world(1.0)))
    b.box((-0.24, 0.2, 0.0), (0.5, 0.4, 0.55), style=box_style("box_soda"))
    b.box((0.26, 0.2, 0.02), (0.46, 0.4, 0.5), yaw=4, style=box_style("box_food"))
    b.box((-0.08, 0.6, 0.0), (0.5, 0.4, 0.5), yaw=-6, style=box_style("box_soda"))


LOOKS = {
    "safe": look_safe, "locker": look_locker, "wardrobe": look_wardrobe, "gun_cabinet": look_gun_cabinet,
    "filing": look_filing, "med_cabinet": look_med, "toolbox": look_toolbox, "dresser": look_dresser,
    "kitchen": look_kitchen, "chest": look_chest, "hard_case": look_hard_case, "weapon_case": look_weapon_case,
    "duffel": look_duffel, "stock_boxes": look_stock_boxes,
}


def main():
    names = sys.argv[1:] or list(LOOKS)
    rng = random.Random("loot")
    textures, mat_info = {}, {}
    for kit in ("metal", "wood", "cardboard", "trim", "trim_dark", "red", "bone", "black"):
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"),
                                         mb.KIT[kit], random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, False)
    for name, colour in FLAT.items():
        textures["loot_" + name] = Texture("loot_" + name, os.path.join("art_source", "textures", "loot", name + ".png"),
                                           mb.paint_flat(colour), rng)
        mat_info[name] = ("loot_" + name, False, False)
    atlas = loot_decals(rng)
    textures["loot_decals"] = Texture("loot_decals", os.path.join("art_source", "textures", "loot", "decals.png"),
                                      lambda r: atlas.c, rng)
    mat_info["decals"] = ("loot_decals", False, False)
    for name in names:
        b = Builder()
        LOOKS[name](b, atlas)
        mb.BUILDING_NAME[0] = name
        out = os.path.join(mb.ROOT, "assets", "models", "loot", name + ".glb")
        mb.write_glb(out, b, textures, mat_info)
        print(f"{name}: {sum(len(f) - 2 for f in b.faces)} triangles, {len(b.mat_names)} materials -> {out}")


if __name__ == "__main__":
    main()
