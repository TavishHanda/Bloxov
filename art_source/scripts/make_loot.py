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

    def locker_door(c):     # 0.33 x 1.74 m: one staff-locker door (the vents and handle are 3D)
        c.rect(0, 0, c.w, c.h, "sky_blue")
        c.rect(3, c.h - 24, c.w - 3, c.h - 21, "bone")                                # name tag
        c.blotch(["steel", "iron"], 3, rng, size=(1, 3))
    a.add("locker_door", 11, 56, locker_door)
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
    a.add("box_meds", 16, 13, box_label("MEDS", "bone", "green_dark"))

    def box_tv(c):          # 0.9 x 0.6 m: a flat-screen box, the set drawn on it
        c.rect(0, 0, c.w, c.h, "wood_pale")
        c.noise(0, 0, c.w, c.h, ["wood_light", "sand"], 0.15, rng)
        c.rect(5, 5, c.w - 5, c.h - 3, "iron_dark")
        c.rect(7, 7, c.w - 7, c.h - 5, "sky_blue")
        c.rect(c.w // 2 - 2, 2, c.w // 2 + 2, 5, "iron_dark")
        c.rect(0, 0, c.w, 2, "red")

    def box_shoes(c):       # 0.35 x 0.13 m shoebox end
        c.rect(0, 0, c.w, c.h, "bone")
        c.rect(0, c.h - 1, c.w, c.h, "iron_dark")                                   # the lid's edge
        c.rect(2, 1, 5, 3, "red")

    a.add("box_tv", 29, 19, box_tv)
    a.add("box_shoes", 11, 4, box_shoes)
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
    """Staff locker (round 4, owner: more 3D): two doors set in a frame on a plinth, raised vent slats, handles and
    hinges that stick out, one door dented, a box and a hard hat left on top."""
    b.box((0, 0.05, 0.02), (0.72, 0.1, 0.44), style=solid("trim_dark"))                # plinth
    b.box((0, 1.0, 0.04), (0.75, 1.8, 0.44), style=lambda n, m, q: None if side_of(n) in ("-y", "-z") else ("blue", uv_world(1.0)))
    for x in (-0.36, 0.36):                                                           # frame round the doors
        b.box((x, 1.0, -0.19), (0.03, 1.8, 0.04), style=solid("trim_dark"))
    for y in (0.115, 1.885):
        b.box((0, y, -0.19), (0.75, 0.03, 0.04), style=solid("trim_dark"))
    b.box((0, 1.0, -0.19), (0.02, 1.76, 0.04), style=solid("trim_dark"))
    for k, x in enumerate((-0.18, 0.18)):
        b.box((x, 1.0, -0.17), (0.33, 1.74, 0.02), yaw=(3 if k else 0), style=front(d, "locker_door", "blue"))
        for j in range(5):                                                            # vent slats
            b.box((x, 1.72 - j * 0.045, -0.185), (0.2, 0.018, 0.012), style=solid("trim_dark"))
        hx = x + (0.12 if k == 0 else -0.12)
        b.box((hx, 1.05, -0.2), (0.03, 0.14, 0.03), style=solid("steel"))           # handle
        b.box((hx, 1.05, -0.215), (0.05, 0.05, 0.01), style=solid("trim_dark"))     # lock
        for y in (0.4, 1.6):                                                          # hinges
            b.box((x - (0.16 if k == 0 else -0.16), y, -0.19), (0.02, 0.08, 0.03), style=solid("steel"))
    b.box((0.1, 1.98, 0.05), (0.42, 0.16, 0.32), yaw=8, style=solid("cardboard"))   # a box left on top
    b.box((-0.2, 1.955, 0.0), (0.24, 0.11, 0.26), style=solid("gold"))               # a hard hat
    b.box((-0.2, 1.905, -0.06), (0.26, 0.01, 0.3), style=solid("gold"))


def look_wardrobe(b, d):
    b.box((0, 1.0, 0.0), (1.0, 1.96, 0.55), style=front(d, "wardrobe", "wood"))
    b.box((0, 1.99, 0.0), (1.04, 0.05, 0.57), style=solid("wood_dark"))


def look_gun_cabinet(b, d):
    b.box((0, 0.95, 0.0), (0.9, 1.9, 0.45), style=front(d, "gun_cabinet", "wood"))
    b.box((0, 1.92, 0.0), (0.94, 0.05, 0.47), style=solid("wood_dark"))


def look_filing(b, d):
    """Four-drawer filing cabinet (round 6, owner: the pulled-out drawer read as a grey block): a steel carcass, drawer
    fronts standing proud with label holders and pulls, one drawer pulled out as an open tray of hanging folders."""
    b.box((0, 0.66, 0.03), (0.5, 1.32, 0.54), style=solid("steel"))                   # carcass
    b.box((0, 0.025, -0.24), (0.46, 0.05, 0.02), style=solid("trim_dark"))           # kick
    rng = random.Random("filing")
    open_k = 1
    for k in range(4):
        y = 0.2 + k * 0.31
        if k == open_k:
            b.box((0, y, -0.235), (0.42, 0.27, 0.01), style=solid("black"))          # the dark slot it came out of
            z = -0.5                                                                  # the tray, 0.27 m out
            b.box((0, y - 0.11, z + 0.13), (0.4, 0.02, 0.27), style=solid("steel"))   # bottom
            for x in (-0.2, 0.2):
                b.box((x, y - 0.03, z + 0.13), (0.015, 0.18, 0.27), style=solid("steel"))   # sides
            for t in range(6):                                                        # hanging folders
                b.box((rng.uniform(-0.03, 0.03), y - 0.02, z + 0.04 + t * 0.04), (0.36, 0.17 + rng.uniform(0, 0.04), 0.012),
                      pitch=rng.uniform(-8, 8), style=solid(rng.choice(("olive", "bone", "gold", "bone"))))
            fz = z - 0.01
        else:
            fz = -0.255
        b.box((0, y, fz), (0.46, 0.28, 0.03), style=solid("steel"))                   # drawer front
        b.box((0, y + 0.07, fz - 0.02), (0.12, 0.05, 0.01), style=solid("bone"))      # label
        b.box((0, y - 0.03, fz - 0.03), (0.16, 0.03, 0.03), style=solid("trim_dark"))  # pull
    b.box((0.03, 1.33, 0.02), (0.3, 0.02, 0.4), yaw=-10, style=solid("bone"))       # papers on top
    b.box((-0.05, 1.35, 0.0), (0.26, 0.02, 0.34), yaw=15, style=solid("bone"))


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


def _box(b, d, c, size, yaw, label, side_mat="cardboard"):
    fit = mb.uv_fit(d.regions[label])
    b.box(c, size, yaw=yaw, style=lambda n, m, q: None if n[1] < -0.7 else (
        ("decals", fit) if abs(n[2]) > 0.7 else (side_mat, uv_world(1.0))))


def look_stock_meds(b, d):
    """Pharmacy stock: cartons with a MEDS label, one opened with pill boxes spilling."""
    _box(b, d, (-0.24, 0.2, 0.0), (0.5, 0.4, 0.55), 0, "box_meds")
    _box(b, d, (0.27, 0.15, 0.02), (0.44, 0.3, 0.5), 5, "box_meds")
    _box(b, d, (-0.1, 0.58, 0.02), (0.46, 0.36, 0.48), -7, "box_meds")
    for k in range(4):
        b.box((0.15 + k * 0.08, 0.34, -0.05 + (k % 2) * 0.1), (0.07, 0.08, 0.05), yaw=k * 20, style=solid("bone"))


def look_stock_tv(b, d):
    """TV shop stock: big flat TV boxes standing and leaning, a small one in front (round 4: not soda and food)."""
    _box(b, d, (-0.05, 0.31, 0.2), (0.92, 0.6, 0.16), 0, "box_tv")
    _box(b, d, (0.05, 0.3, 0.0), (0.9, 0.58, 0.15), -4, "box_tv")
    b.box((0.0, 0.25, -0.2), (0.85, 0.52, 0.14), yaw=3, pitch=-12, style=lambda n, m, q: None if n[1] < -0.7 else (
        ("decals", mb.uv_fit(d.regions["box_tv"])) if n[2] < -0.5 else ("cardboard", uv_world(1.0))))


def look_stock_shoes(b, d):
    """Shoe store stock: stacks of shoeboxes (white, a few coloured), some knocked off."""
    rng = random.Random("shoes")
    cols = ("cardboard", "cardboard", "red", "blue", "trim_dark")
    for sx, rows in ((-0.3, 5), (0.1, 4), (0.42, 2)):
        for k in range(rows):
            c = rng.choice(cols)
            b.box((sx + rng.uniform(-0.02, 0.02), 0.065 + k * 0.13, rng.uniform(-0.05, 0.05)), (0.35, 0.13, 0.22),
                  yaw=rng.uniform(-6, 6) + 90 * 0, style=lambda n, m, q, c=c: None if n[1] < -0.7 else (
                      ("decals", mb.uv_fit(d.regions["box_shoes"])) if n[2] < -0.7 else (c, uv_world(1.0))))
    b.box((0.2, 0.065, -0.3), (0.35, 0.13, 0.22), yaw=35, style=solid("red"))      # one on the floor, lid off
    b.box((0.2, 0.16, -0.28), (0.28, 0.08, 0.1), yaw=35, style=solid("trim_dark"))  # the shoe in it


def look_laundry_cart(b, d):
    """Laundromat: a canvas laundry cart on castors, heaped with clothes (round 4, owner: loot in the laundromat)."""
    for x in (-0.4, 0.4):
        for z in (-0.22, 0.22):
            b.box((x, 0.05, z), (0.06, 0.1, 0.06), style=solid("black"))              # castors
            b.box((x, 0.5, z), (0.03, 0.8, 0.03), style=solid("steel"))               # frame posts
    b.box((0, 0.13, 0), (0.86, 0.03, 0.5), style=solid("steel"))
    for y in (0.88,):
        for z in (-0.23, 0.23):
            b.box((0, y, z), (0.86, 0.03, 0.03), style=solid("steel"))
        for x in (-0.42, 0.42):
            b.box((x, y, 0), (0.03, 0.03, 0.5), style=solid("steel"))
    b.box((0, 0.55, 0), (0.8, 0.62, 0.44), style=lambda n, m, q: ("bone", uv_world(1.0)) if n[1] > 0.7 else ("blue", uv_world(1.0)))  # canvas
    for x in (-0.41, 0.41):                                                           # the bag's rolled rim
        b.box((x, 0.86, 0), (0.04, 0.04, 0.46), style=solid("blue"))
    for z in (-0.23, 0.23):
        b.box((0, 0.86, z), (0.86, 0.04, 0.04), style=solid("blue"))
    rng = random.Random("laundry")
    for k in range(11):                                                               # the clothes heap
        b.box((rng.uniform(-0.28, 0.28), 0.87 + rng.uniform(0, 0.1), rng.uniform(-0.14, 0.14)),
              (rng.uniform(0.2, 0.34), 0.08, rng.uniform(0.14, 0.26)), yaw=rng.uniform(0, 180), pitch=rng.uniform(-15, 15),
              style=solid(rng.choice(("red", "bone", "green", "olive", "gold", "steel"))))
    b.box((-0.47, 0.75, 0), (0.04, 0.35, 0.2), pitch=10, style=solid("bone"))        # a towel over the side


LOOKS = {
    "safe": look_safe, "locker": look_locker, "wardrobe": look_wardrobe, "gun_cabinet": look_gun_cabinet,
    "filing": look_filing, "med_cabinet": look_med, "toolbox": look_toolbox, "dresser": look_dresser,
    "kitchen": look_kitchen, "chest": look_chest, "hard_case": look_hard_case, "weapon_case": look_weapon_case,
    "duffel": look_duffel, "stock_boxes": look_stock_boxes, "stock_meds": look_stock_meds, "stock_tv": look_stock_tv,
    "stock_shoes": look_stock_shoes, "laundry_cart": look_laundry_cart,
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
