"""Builds the HUD fonts in assets/fonts/ ("Bloxov Jersey 10/15/20/25") from the Jersey family (OFL).

Two changes from the originals:
1. Each font's units-per-em is rescaled so Godot font sizes 20 / 30 / 40 / 50 draw Jersey 10 / 15 / 20 / 25 at exactly
   one screen pixel per font pixel (0.8.13). At other sizes a pixel font's pixels land between screen pixels, so
   strokes and gaps come out uneven (the owner kept seeing odd-looking letter pairs).
2. Jersey 10's capital A is redrawn with a square top (0.8.12): its pointed, stepped top looked odd next to the
   other blocky capitals. It sits on the font's own pixel grid (75 units per pixel, 7 px wide, 10 px tall) with
   2-px strokes and crossbar like H and R, spaced like every other letter.
The fonts are renamed ("Bloxov Jersey N") since they're modified versions.

Usage: pip install fonttools; python3 tools/make_bloxov_font.py DIR
DIR holds the originals Jersey10-Regular.ttf, Jersey15-Regular.ttf, Jersey20-Regular.ttf, Jersey25-Regular.ttf
(https://github.com/google/fonts/tree/main/ofl/jersey10 and jersey15/20/25).
"""
import os
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

OUT_DIR = "assets/fonts"
## Design -> (pixel grid in font units, the Godot font size that should be 1x).
FONTS = {10: (75, 20), 15: (50, 30), 20: (38, 40), 25: (30, 50)}


def square_a(font: TTFont) -> None:
    glyf = font["glyf"]
    pen = TTGlyphPen(font.getGlyphSet())

    def poly(points):
        pen.moveTo(points[0])
        for point in points[1:]:
            pen.lineTo(point)
        pen.closePath()

    # Outer shape (clockwise): legs, crossbar, square top with clipped corners.
    poly([(0, 0), (0, 675), (75, 675), (75, 750), (450, 750), (450, 675), (525, 675), (525, 0),
          (375, 0), (375, 300), (150, 300), (150, 0)])
    # The hole above the crossbar (counter-clockwise).
    poly([(150, 450), (375, 450), (375, 600), (150, 600)])
    glyph = pen.glyph()
    glyf["A"] = glyph
    glyph.recalcBounds(glyf)
    font["hmtx"]["A"] = (600, 0)


def build(source_dir: str, design: int) -> None:
    grid, size = FONTS[design]
    font = TTFont(os.path.join(source_dir, "Jersey%d-Regular.ttf" % design))
    if design == 10:
        square_a(font)
    font["head"].unitsPerEm = grid * size
    for record in font["name"].names:
        text = record.toUnicode()
        if record.nameID in (1, 4, 16):
            record.string = text.replace("Jersey %d" % design, "Bloxov Jersey %d" % design)
        elif record.nameID == 6:
            record.string = text.replace("Jersey%d" % design, "BloxovJersey%d" % design)
        elif record.nameID == 3:
            record.string = text + ";Bloxov pixel grid"
    out = os.path.join(OUT_DIR, "BloxovJersey%d-Regular.ttf" % design)
    font.save(out)
    print("wrote", out, "(1x at size %d)" % size)


if __name__ == "__main__":
    for d in FONTS:
        build(sys.argv[1] if len(sys.argv) > 1 else ".", d)
