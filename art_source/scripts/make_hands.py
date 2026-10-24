"""Bloxov first-person hands (owner, 2026-10-24: "add like a hand model holding the gun"): the player's two hands and
forearms, posed on each of the five guns.

Each look ("a", "b", "c": option sheets for the owner) is one .glb; the game uses the one in PICKED, written to
assets/models/hands/hands.glb (other looks go to hands_<look>.glb only with `all`, for the option sheets).

Run: python3 art_source/scripts/make_hands.py          (the picked look)
     python3 art_source/scripts/make_hands.py all      (every look, as hands_<look>.glb)
No Blender needed (written directly, like make_gun.py, whose model and .glb code this uses). Textures:
art_source/textures/hands/, 64 px per meter like the guns.

Nodes in the .glb, all in the frame of the gun model (make_gun.py: barrel along -z, up +y), so the hands line up when
the .glb sits on the gun model's origin:
  <gun>_R   the right hand on the gun's grip        <gun>_L   the left hand (on the fore-end; on the pistol, round
                                                               the right hand)
  Each hand's origin is its wrist, where the forearm joins.
  ArmR, ArmL  the forearms, origin at the wrist, running along -z (scripts/gun_view_models.gd puts them on the wrists
              and points them at the elbows, below the camera, every frame).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_building as mb  # noqa: E402
import make_gun as mg  # noqa: E402
from make_building import Canvas, Texture  # noqa: E402

mb.PALETTE.update({"skin": "c99a72", "skin_dark": "a87a55", "skin_light": "d9ae88", "watch": "2a2a2a",
                   "coyote": "806a45", "coyote_dark": "66533a", "coyote_light": "937c55", "mc_base": "a3946a"})

PICKED = "a"
OUT = os.path.join(mb.ROOT, "assets", "models", "hands")


def _camo(base, blobs):
    def paint(rng):
        c = Canvas(32, 32, base)
        for col in blobs:
            c.blotch([col], 6, rng, size=(3, 7))
        return c
    return paint


def _cloth(base, dark, light):
    return mg._tex(base, ((dark, 0.08), (light, 0.03)))


MATS = {
    "multicam": _camo("mc_base", ("olive", "wood_mid", "olive_light")),
    "sleeve_black": _cloth("iron_dark", "black", "iron"),
    "sleeve_olive": _cloth("olive_dark", "black", "olive"),
    "glove_tan": _cloth("coyote", "coyote_dark", "coyote_light"),
    "glove_black": _cloth("black", "iron_dark", "iron"),
    "glove_olive": _cloth("olive", "olive_dark", "olive_light"),
    "knuckle": mg._tex("iron_dark", (("black", 0.2),)),
    "skin": mg._tex("skin", (("skin_dark", 0.05), ("skin_light", 0.04))),
    "watch": mg._tex("watch", (("iron", 0.1),)),
}

# Per look: sleeve, glove, finger ends (bare on fingerless gloves), knuckle pads, sleeve rolled up (bare forearm), watch.
LOOKS = {
    "a": {"sleeve": "multicam", "glove": "glove_tan", "tips": "glove_tan", "pads": None, "rolled": False, "watch": False},
    "b": {"sleeve": "sleeve_black", "glove": "glove_black", "tips": "glove_black", "pads": "knuckle", "rolled": False,
          "watch": False},
    "c": {"sleeve": "sleeve_olive", "glove": "glove_olive", "tips": "skin", "pads": None, "rolled": True, "watch": True},
}

# Each gun's handholds (picked looks, make_gun.py): the grip (width, depth, lean in degrees as in make_gun's pitch, and
# how far above the Grip mark its middle is; on the straight stocks the "grip" is the stock's wrist, lying almost flat)
# and the fore-end (width, height above the Fore mark).
GUNS = {
    "hound": {"grip": (0.034, 0.048, -18, 0.0), "fore": (0.07, 0.066)},
    "stinger": {"grip": (0.03, 0.045, -16, 0.0), "fore": None},
    "wasp": {"grip": (0.034, 0.046, -12, 0.0), "fore": (0.054, 0.05)},
    "mauler": {"grip": (0.056, 0.075, -75, 0.038), "fore": (0.068, 0.058)},
    "lancer": {"grip": (0.06, 0.07, -70, 0.022), "fore": (0.064, 0.04)},
}
F = 0.017   # finger thickness


class Hand:
    """Boxes in a handhold's own frame (grip: up along the grip, forward -z; fore-end: the gun's frame), placed on the
    gun by `at` and leaning `pitch` degrees, all into one part of the model."""

    def __init__(self, m, part, at, pitch, look):
        self.m, self.part, self.at, self.pitch, self.look = m, part, at, pitch, look

    def box(self, c, s, mat):
        p = mb.v_add(self.at, mb.rot(c, 0.0, self.pitch))
        self.m.box(p, s, mat, pitch=self.pitch, part=self.part)

    def to_gun(self, c):
        return mb.v_add(self.at, mb.rot(c, 0.0, self.pitch))

    def glove(self):
        return LOOKS[self.look]["glove"]

    def tips(self):
        return LOOKS[self.look]["tips"]


def right_hand(m, gun, look):
    """Wrapped round the grip: back of the hand on the right, three fingers round the front, the trigger finger along
    the frame, the thumb over the left side."""
    w, d, lean, up = GUNS[gun]["grip"]
    grip = mb.v_add(m.marks["Grip"], (0.0, up, 0.0))
    wrist_local = (w / 2 + 0.006, -0.03, d / 2 + 0.014)
    h = Hand(m, f"{gun}_R", grip, lean, look)
    wrist = h.to_gun(wrist_local)
    m.part(f"{gun}_R", wrist)
    g, t = h.glove(), h.tips()
    h.box((w / 2 + 0.011, 0.0, 0.004), (0.022, 0.07, d + 0.02), g)                    # back of the hand
    h.box((0.004, -0.004, d / 2 + 0.009), (w * 0.9, 0.064, 0.018), g)                  # heel of the hand behind
    h.box((w / 2 + 0.008, -0.03, d / 2 + 0.012), (0.03, 0.026, 0.03), g)               # wrist
    for k, y in enumerate((0.019, 0.0, -0.019)):                                       # middle, ring, little finger
        size = F if k < 2 else F * 0.85
        h.box((0.003, y, -(d / 2 + size / 2)), (w + 0.028, size, size), g)
        h.box((-(w / 2 + size / 2), y, -d / 2 + 0.012), (size, size, 0.026), t)
    h.box((w / 2 + 0.006, 0.042, -d / 2 - 0.01), (0.014, 0.015, 0.04), t)              # trigger finger on the frame
    h.box((-(w / 2 + 0.008), 0.034, -0.002), (0.016, 0.016, d * 0.75), t)              # thumb over the left side
    if LOOKS[look]["pads"]:
        h.box((w / 2 + 0.024, 0.0, -d / 2 + 0.004), (0.006, 0.062, 0.016), LOOKS[look]["pads"])


def left_hand(m, gun, look):
    """Under the fore-end: palm under it and up the left side, fingers up the right side, the thumb over the top of the
    left side (so it shows from behind the gun)."""
    fore = GUNS[gun]["fore"]
    if fore is None:
        return support_hand(m, gun, look)
    h = Hand(m, f"{gun}_L", m.marks["Fore"], 0.0, look)
    g, t = h.glove(), h.tips()
    wd, ht = fore
    m.part(f"{gun}_L", h.to_gun((-wd / 2 - 0.006, -0.026, 0.03)))
    h.box((0.0, -0.011, 0.0), (wd * 0.95, 0.022, 0.08), g)                             # palm
    h.box((-(wd / 2 + 0.009), ht * 0.3, 0.004), (0.018, ht * 0.6 + 0.02, 0.072), g)     # up the left side
    h.box((-wd / 2 - 0.004, -0.018, 0.03), (0.03, 0.03, 0.04), g)                      # heel and wrist
    reach = min(ht * 0.75, 0.045)
    for k in range(4):                                                                 # fingers up the right side
        z = -0.028 + k * 0.018
        size = F if k < 3 else F * 0.85
        h.box((wd / 2 + size / 2, reach / 2 - 0.012, z), (size, reach + 0.012, size), t if k == 0 else g)
        h.box((wd / 2 + size / 2, reach - 0.004, z), (size, 0.012, size), t)
    h.box((-(wd / 2 + 0.006), ht * 0.6 + 0.012, -0.008), (0.016, 0.016, 0.03), g)      # thumb base
    h.box((-(wd / 2 - 0.004), ht + 0.004, -0.03), (0.016, 0.014, 0.036), t)            # thumb over the top
    if LOOKS[look]["pads"]:
        h.box((wd / 2 + F + 0.003, reach * 0.4, -0.001), (0.006, 0.02, 0.07), LOOKS[look]["pads"])


def support_hand(m, gun, look):
    """The pistol: the left hand cupped round the right, fingers over the right hand's, thumb forward along the frame."""
    w, d, lean, _up = GUNS[gun]["grip"]
    h = Hand(m, f"{gun}_L", m.marks["Grip"], lean, look)
    m.part(f"{gun}_L", h.to_gun((-(w / 2 + 0.03), -0.03, 0.01)))
    g, t = h.glove(), h.tips()
    h.box((-(w / 2 + 0.028), -0.004, -0.002), (0.02, 0.068, d + 0.01), g)              # palm on the left
    for k, y in enumerate((0.012, -0.006, -0.024)):
        h.box((-0.006, y, -(d / 2 + F + F / 2)), (w + 0.064, F, F), g)                 # fingers over the right hand's
        h.box((w / 2 + 0.03, y, -(d / 2 + 0.006)), (F, F, 0.022), t)
    h.box((-(w / 2 + 0.02), 0.04, -0.02), (0.015, 0.015, 0.05), t)                     # thumb forward
    h.box((-(w / 2 + 0.026), -0.034, 0.008), (0.03, 0.026, 0.03), g)                   # wrist


def arm(m, name, look, left):
    """A forearm along -z from the wrist: the glove's cuff, then the sleeve (or the bare arm and a rolled sleeve)."""
    L = LOOKS[look]
    m.part(name, (0.0, 0.0, 0.0))
    m.box((0, 0, -0.02), (0.05, 0.048, 0.05), L["glove"], part=name)                  # glove cuff
    if L["rolled"]:
        m.box((0, 0, -0.14), (0.054, 0.052, 0.2), "skin", part=name)                  # bare forearm
        m.box((0, 0, -0.27), (0.07, 0.068, 0.07), L["sleeve"], part=name)             # rolled-up sleeve
        m.box((0, 0, -0.42), (0.066, 0.064, 0.24), L["sleeve"], part=name)
        if left and L["watch"]:
            m.box((0, 0, -0.06), (0.058, 0.056, 0.02), "watch", part=name)
    else:
        m.box((0, 0, -0.065), (0.064, 0.062, 0.05), L["sleeve"], part=name)           # sleeve end, a bit wider
        m.box((0, 0, -0.3), (0.06, 0.058, 0.42), L["sleeve"], part=name)


def build(look):
    m = mg.Model("hands")
    del m.parts["Body"]
    for gun, make in mg.GUNS.items():
        g = mg.Model(gun)
        make(g, mg.PICKED[gun])
        m.marks = g.marks             # this gun's Grip and Fore
        right_hand(m, gun, look)
        left_hand(m, gun, look)
    m.marks = {}
    arm(m, "ArmR", look, False)
    arm(m, "ArmL", look, True)
    return m


def main():
    every = "all" in sys.argv[1:]
    mg.MATS.update(MATS)
    textures = {name: Texture("hands_" + name, os.path.join("art_source", "textures", "hands", name + ".png"),
                              painter, random.Random("hands_" + name)) for name, painter in MATS.items()}
    for look in ("a", "b", "c") if every else (PICKED,):
        m = build(look)
        names = [f"hands_{look}"] if every else []
        if look == PICKED:
            names.append("hands")
        for name in names:
            mg.write_model(os.path.join(OUT, name + ".glb"), m, textures)
        print(f"{', '.join(names)}: look {look}, {m.tris()} triangles")


if __name__ == "__main__":
    main()
