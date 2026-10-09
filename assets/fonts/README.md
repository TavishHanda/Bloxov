# Fonts (all SIL Open Font License 1.1)

| File | Font | License | Used for |
|---|---|---|---|
| `BloxovJersey10/15/20/25-Regular.ttf` | **Bloxov Jersey 10 / 15 / 20 / 25**: the [Jersey](https://github.com/scfried/soft-type-jersey) pixel family (one design per size), rescaled so Godot font sizes 20 / 30 / 40 / 50 draw each one at exactly 1 screen pixel per font pixel, and Jersey 10's capital A redrawn with a square top. Renamed because they're modified | `OFL.txt` | numbers and most HUD/menu text: `HudStyle.font(size)` picks the design for the size |
| `Silkscreen-Bold.ttf` | [Silkscreen](https://github.com/googlefonts/silkscreen) Bold | `OFL-Silkscreen.txt` | tiny stenciled labels (`HudStyle.label_font()`, size 8) |
| `PixelifySans.ttf` | [Pixelify Sans](https://github.com/eifetx/Pixelify-Sans) | `OFL-PixelifySans.txt` | writing on masking tape (`HudStyle.tape_font()`) |

The Bloxov Jersey files are built by `tools/make_bloxov_font.py` from the original Jersey 10/15/20/25 (Google Fonts).
**Only draw them at sizes 20, 30, 40 or 50**: anywhere in between, the font's pixels land between screen pixels and
letters come out uneven.
