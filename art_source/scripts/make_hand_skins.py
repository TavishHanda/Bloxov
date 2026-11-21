"""First-person sleeves and gloves for the six playable characters (0.38.14, owner 2026-11-21: "the hand models on
first person view match the model of the character the person is using").

Each character's builder in make_character.py dresses its forearms (c_tops) and gloves (c_gloves) per skin. This
records those colours and paints a sleeve and a glove texture per character and skin, the way make_hands.py paints
the wardrobe options:
  assets/models/hands/outfit/sleeve-<id>-<skin>.png   glove-<id>-<skin>.png
(hyphens: .gitignore drops *_*.png there). The game swaps them onto hands.glb's sleeves and gloves
(scripts/gun_view_models.gd `wear`, scripts/playable_models.gd `hands_look`).

Run: python3 art_source/scripts/make_hand_skins.py   (re-run after changing a character's tops or gloves)
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
import make_character as mc  # noqa: E402
from make_building import Canvas, Texture  # noqa: E402

PLAYABLE = ["vega", "voss", "sable", "patch", "nine", "korr"]
OUT = os.path.join("assets", "models", "hands", "outfit")


def record(name):
    """{skin: (sleeve skin, sleeve dark, glove skin, glove dark)} from character `name`'s builder."""
    tops, gloves = {}, {}
    real_tops, real_gloves = mc.c_tops, mc.c_gloves

    def c_tops(b, options):
        tops.update({k: (v[0], v[1]) for k, v in options.items()})
        real_tops(b, options)

    def c_gloves(b, options):
        gloves.update(options)
        real_gloves(b, options)

    mc.c_tops, mc.c_gloves = c_tops, c_gloves
    try:
        mc.BUILDERS[name](mc.Body(name))
    finally:
        mc.c_tops, mc.c_gloves = real_tops, real_gloves
    return {k: tops[k] + gloves[k] for k in mc.PLAYABLE_SKINS[name] if k in tops and k in gloves}


def colour(skin):
    """A make_character skin name -> [base hex, [(speck hex, chance)]]."""
    s = mc.SKINS[skin]
    return mc.PALETTE[s["base"]], [(mc.PALETTE[c], ch) for c, ch in s.get("noise", [])]


def painter(skin, dark):
    base, specks = colour(skin)
    dark_hex = mc.PALETTE[mc.SKINS[dark]["base"]] if dark in mc.SKINS else mc.PALETTE.get(dark, base)
    names = {}

    def name_of(hexcol):
        key = "hs_" + hexcol
        mb.PALETTE[key] = hexcol
        names[hexcol] = key
        return key

    def paint(rng):
        c = Canvas(32, 32, name_of(base))
        for col, chance in specks + [(dark_hex, 0.08)]:
            c.noise(0, 0, 32, 32, [name_of(col)], chance, rng)
        return c
    return paint


def main():
    os.makedirs(os.path.join(mb.ROOT, OUT), exist_ok=True)
    mb.REGENERATE_TEXTURES = True
    for name in PLAYABLE:
        mc.PX_PER_M, mc.TILE, mc.ATLAS = 32, 32, 256
        mc.COLS = mc.ATLAS // mc.TILE
        for skin, (top, top_dark, glove, glove_dark) in record(name).items():
            for kind, (s, d) in (("sleeve", (top, top_dark)), ("glove", (glove, glove_dark))):
                tag = "%s-%s-%s" % (kind, name, skin)
                Texture("hands_" + tag, os.path.join(OUT, tag + ".png"), painter(s, d), random.Random("hands_" + tag))
                print(tag, s)


if __name__ == "__main__":
    main()
