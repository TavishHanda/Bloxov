"""Bloxov door leaves (World art, 0.17): the model scripts/door.gd hangs in every inner doorway.

Run: python3 art_source/scripts/make_door.py
Writes assets/models/props/door_<look>.glb: a 1 m x 2 m leaf centred on the origin, 5 cm thick, its handle on +x
(door.gd stretches it to the doorway and turns it round for the second leaf of a double door).
Uses the building kit textures (art_source/textures/kit) and the loot flat colours (art_source/textures/loot).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
from make_building import Builder, Texture, uv_world  # noqa: E402

T = 0.05   # leaf thickness


def solid(mat, tile=1.0):
    return lambda n, m, q: (mat, uv_world(tile))


def handle(b, x, y, metal):
    for sz in (-1, 1):
        b.box((x, y, sz * (T / 2 + 0.02)), (0.04, 0.04, 0.04), style=solid(metal))
        b.box((x - 0.05, y, sz * (T / 2 + 0.045)), (0.12, 0.025, 0.025), style=solid(metal))


def door_wood(b):
    """Panelled wooden door: a frame of stiles and rails round four raised panels, brass handle."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("wood"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.006)
        for x0, x1, y0, y1 in ((-0.36, -0.04, 0.12, 0.85), (0.04, 0.36, 0.12, 0.85),
                               (-0.36, -0.04, -0.85, -0.12), (0.04, 0.36, -0.85, -0.12)):
            b.box(((x0 + x1) / 2, (y0 + y1) / 2, z), (x1 - x0, y1 - y0, 0.012), style=solid("wood_dark"))
    handle(b, 0.38, -0.02, "gold")


def door_metal(b):
    """Steel service door: kick plate, a small wired window, steel handle."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("steel"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        b.box((0, -0.86, z), (0.9, 0.22, 0.008), style=solid("trim_dark"))
        b.box((0, 0.55, z), (0.34, 0.42, 0.008), style=solid("black"))
    handle(b, 0.38, -0.02, "trim")


def door_office(b):
    """Painted office door (police, bank, town hall, offices, pharmacy): pale grey, a small window, lever handle."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("steel_light"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        for x0, x1, y0, y1 in ((-0.22, 0.22, 0.28, 0.32), (-0.22, 0.22, 0.78, 0.82), (-0.24, -0.2, 0.28, 0.82),
                               (0.2, 0.24, 0.28, 0.82)):
            b.box(((x0 + x1) / 2, (y0 + y1) / 2, z), (x1 - x0, y1 - y0, 0.008), style=solid("trim_dark"))
        b.box((0, 0.55, z * 0.9), (0.4, 0.5, 0.004), style=solid("glass"))
        b.box((0, -0.9, z), (0.9, 0.12, 0.008), style=solid("trim"))
    handle(b, 0.38, -0.02, "trim")


def door_school(b):
    """School classroom door (round 6, owner's pick: a mix of the navy option and the oak, the oak a bit darker):
    dark-stained oak with navy paint round a square wired window, a navy kick plate and push plate."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("oak_dark"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        b.box((0, 0.45, z), (0.52, 0.52, 0.008), style=solid("blue"))
        b.box((0, 0.45, z * 1.1), (0.42, 0.42, 0.004), style=solid("glass"))
        b.box((0, -0.86, z), (0.9, 0.22, 0.008), style=solid("blue"))
        b.box((0.3, 0.02, z), (0.1, 0.3, 0.008), style=solid("trim"))
    handle(b, 0.38, -0.02, "trim")


def door_school_oak(b):
    """Plain school door (owner, 2026-10-13: the school door without its navy parts): dark-stained oak, a square
    wired window in a raised oak bead, a steel push plate. Hangs on the staff rooms (school_door_look in the gen)."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("oak_dark"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.006)
        for x0, x1, y0, y1 in ((-0.25, 0.25, 0.17, 0.21), (-0.25, 0.25, 0.69, 0.73), (-0.25, -0.21, 0.17, 0.73),
                               (0.21, 0.25, 0.17, 0.73)):
            b.box(((x0 + x1) / 2, (y0 + y1) / 2, z), (x1 - x0, y1 - y0, 0.012), style=solid("wood_dark"))
        b.box((0, 0.45, z * 0.9), (0.42, 0.52, 0.004), style=solid("glass"))
        b.box((0.3, 0.02, z), (0.1, 0.3, 0.008), style=solid("trim"))
    handle(b, 0.38, -0.02, "trim")


def door_school_mix2(b):
    """Option (round 6): navy painted with a dark oak panel below the window and oak edges."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("blue"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.006)
        b.box((0, 0.45, z), (0.5, 0.5, 0.012), style=solid("oak_dark"))
        b.box((0, 0.45, z * 1.15), (0.4, 0.4, 0.004), style=solid("glass"))
        b.box((0, -0.45, z), (0.7, 0.9, 0.012), style=solid("oak_dark"))
        for x in (-0.47, 0.47):
            b.box((x, 0, z), (0.04, 1.98, 0.012), style=solid("oak_dark"))
    handle(b, 0.38, -0.02, "trim")


def paint_oak_dark(rng):
    """Dark-stained oak (school doors): vertical grain."""
    c = mb.Canvas(64, 64, "wood_mid")
    for y in range(64):
        for x in range(64):
            if x % 4 == 0:
                c.put(x, y, "wood_dark")
            elif rng.random() < 0.06:
                c.put(x, y, "wood")
    return c


def door_plank(b):
    """Cabin door: vertical planks with a Z brace."""
    for k in range(6):
        x = -0.41 + k * 0.164
        b.box((x, 0, 0), (0.158, 1.98, T), style=solid("wood"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.012)
        for y in (-0.7, 0.7):
            b.box((0, y, z), (0.9, 0.14, 0.024), style=solid("wood_dark"))
        b.box((0, 0, z), (0.14, 1.5, 0.024), style=solid("wood_dark"))
    handle(b, 0.38, -0.02, "black")


def door_school_navy(b):
    """Option (round 5): navy painted, a square wired window, steel kick plate and push plate."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("blue"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        b.box((0, 0.45, z), (0.5, 0.5, 0.008), style=solid("trim"))
        b.box((0, 0.45, z * 1.1), (0.42, 0.42, 0.004), style=solid("glass"))
        b.box((0, -0.86, z), (0.9, 0.22, 0.008), style=solid("trim"))
        b.box((0.3, 0.02, z), (0.1, 0.3, 0.008), style=solid("trim"))
    handle(b, 0.38, -0.02, "trim")


def door_school_red(b):
    """Option (round 5): the classic red school door, a tall window with a white frame, a number plate."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("red"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        b.box((0, 0.4, z), (0.34, 0.86, 0.008), style=solid("bone"))
        b.box((0, 0.4, z * 1.1), (0.26, 0.78, 0.004), style=solid("glass"))
        b.box((0, 0.92, z), (0.16, 0.08, 0.008), style=solid("bone"))
        b.box((0, -0.86, z), (0.9, 0.22, 0.008), style=solid("trim"))
    handle(b, 0.38, -0.02, "trim")


def door_school_twotone(b):
    """Option (round 5): wood below (two panels), cream painted above round a big window, brass handle."""
    b.box((0, -0.45, 0), (0.98, 1.08, T), style=solid("wood"))
    b.box((0, 0.545, 0), (0.98, 0.89, T), style=solid("bone"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.006)
        for x0, x1 in ((-0.38, -0.04), (0.04, 0.38)):
            b.box(((x0 + x1) / 2, -0.47, z), (x1 - x0, 0.8, 0.012), style=solid("wood_dark"))
        b.box((0, 0.5, z * 1.05), (0.62, 0.62, 0.004), style=solid("glass"))
        b.box((0, 0.09, z), (0.98, 0.04, 0.012), style=solid("wood_dark"))
    handle(b, 0.38, -0.02, "gold")


def door_school_grey(b):
    """Option (round 5): light grey steel with a wide window across the top and a dark kick plate."""
    b.box((0, 0, 0), (0.98, 1.98, T), style=solid("steel_light"))
    for sz in (-1, 1):
        z = sz * (T / 2 + 0.004)
        b.box((0, 0.5, z), (0.7, 0.56, 0.008), style=solid("trim_dark"))
        b.box((0, 0.5, z * 1.1), (0.62, 0.48, 0.004), style=solid("glass"))
        b.box((0, -0.84, z), (0.9, 0.26, 0.008), style=solid("trim_dark"))
    handle(b, 0.38, -0.02, "trim")


# The school door options (round 5) are drawn for the owner to pick from, not built: make one the "school" look.
OPTIONS = {"school_mix2": door_school_mix2, "school_navy": door_school_navy, "school_red": door_school_red, "school_twotone": door_school_twotone,
           "school_grey": door_school_grey}
LOOKS = {"wood": door_wood, "metal": door_metal, "office": door_office, "school": door_school, "school_oak": door_school_oak,
         "plank": door_plank}


def main():
    rng = random.Random("doors")
    textures, mat_info = {}, {}
    for kit in ("wood", "trim", "trim_dark", "black", "steel_light", "green", "glass", "blue", "red", "bone"):
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"),
                                         mb.KIT[kit], random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, kit == "glass")
    textures["kit_oak_dark"] = Texture("kit_oak_dark", os.path.join("art_source", "textures", "kit", "oak_dark.png"),
                                       paint_oak_dark, random.Random("oak_dark"))
    mat_info["oak_dark"] = ("kit_oak_dark", False, False)
    for name, colour in (("wood_dark", "wood_dark"), ("gold", "hazard_yellow"), ("steel", "steel")):
        textures["loot_" + name] = Texture("loot_" + name, os.path.join("art_source", "textures", "loot", name + ".png"),
                                           mb.paint_flat(colour), rng)
        mat_info[name] = ("loot_" + name, False, False)
    looks = dict(LOOKS, **(OPTIONS if "--options" in sys.argv else {}))
    for name, make in looks.items():
        b = Builder()
        make(b)
        mb.BUILDING_NAME[0] = "door_" + name
        out = os.path.join(mb.ROOT, "assets", "models", "props", "door_" + name + ".glb")
        mb.write_glb(out, b, textures, mat_info)
        print(f"door_{name}: {sum(len(f) - 2 for f in b.faces)} triangles -> {out}")


if __name__ == "__main__":
    main()
