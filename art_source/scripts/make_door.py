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


LOOKS = {"wood": door_wood, "metal": door_metal}


def main():
    rng = random.Random("doors")
    textures, mat_info = {}, {}
    for kit in ("wood", "trim", "trim_dark", "black"):
        textures["kit_" + kit] = Texture("kit_" + kit, os.path.join("art_source", "textures", "kit", kit + ".png"),
                                         mb.KIT[kit], random.Random(kit))
        mat_info[kit] = ("kit_" + kit, False, False)
    for name, colour in (("wood_dark", "wood_dark"), ("gold", "hazard_yellow"), ("steel", "steel")):
        textures["loot_" + name] = Texture("loot_" + name, os.path.join("art_source", "textures", "loot", name + ".png"),
                                           mb.paint_flat(colour), rng)
        mat_info[name] = ("loot_" + name, False, False)
    for name, make in LOOKS.items():
        b = Builder()
        make(b)
        mb.BUILDING_NAME[0] = "door_" + name
        out = os.path.join(mb.ROOT, "assets", "models", "props", "door_" + name + ".glb")
        mb.write_glb(out, b, textures, mat_info)
        print(f"door_{name}: {sum(len(f) - 2 for f in b.faces)} triangles -> {out}")


if __name__ == "__main__":
    main()
