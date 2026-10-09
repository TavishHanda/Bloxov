"""Builds assets/fonts/BloxovJersey10-Regular.ttf from Jersey 10 (OFL): redraws the capital A with a square top.

Jersey 10's A has a pointed, stepped top while the other capitals are square; the owner found it odd (0.8.12).
The new A sits on the font's own pixel grid (75 units per pixel, 7 px wide, 10 px tall) with 2-px strokes and
crossbar like H and R, and one extra pixel of space on its left (else "RA" looks squished). The font is renamed "Bloxov Jersey 10" since it's a modified version.

Usage: pip install fonttools; python3 tools/make_bloxov_font.py path/to/Jersey10-Regular.ttf
(The original is at https://github.com/google/fonts/tree/main/ofl/jersey10.)
"""
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

OUT = "assets/fonts/BloxovJersey10-Regular.ttf"
## One pixel of the font's grid (units).
LEFT = 75


def main(source: str) -> None:
    font = TTFont(source)
    glyf = font["glyf"]
    pen = TTGlyphPen(font.getGlyphSet())

    def poly(points):
        pen.moveTo(points[0])
        for point in points[1:]:
            pen.lineTo(point)
        pen.closePath()

    # Shifted right by one pixel (LEFT): a full-height square A sat too close to the letter before it ("RA", "TA"
    # looked squished; the old pointed A hid that), so it gets one pixel of space on the left too.
    def shifted(points):
        return [(x + LEFT, y) for x, y in points]

    # Outer shape (clockwise): legs, crossbar, square top with clipped corners.
    poly(shifted([(0, 0), (0, 675), (75, 675), (75, 750), (450, 750), (450, 675), (525, 675), (525, 0),
                  (375, 0), (375, 300), (150, 300), (150, 0)]))
    # The hole above the crossbar (counter-clockwise).
    poly(shifted([(150, 450), (375, 450), (375, 600), (150, 600)]))
    glyph = pen.glyph()
    glyf["A"] = glyph
    glyph.recalcBounds(glyf)
    font["hmtx"]["A"] = (600 + LEFT, LEFT)

    for record in font["name"].names:
        text = record.toUnicode()
        if record.nameID in (1, 4, 16):
            record.string = text.replace("Jersey 10", "Bloxov Jersey 10")
        elif record.nameID == 6:
            record.string = text.replace("Jersey10", "BloxovJersey10")
        elif record.nameID == 3:
            record.string = text + ";Bloxov square A"
    font.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Jersey10-Regular.ttf")
