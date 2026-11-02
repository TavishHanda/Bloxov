"""Makes the web page's Bloxov pictures: the loading-screen splash, the icon (favicon) and the link preview.

Run from the repo root: python3 tools/make_web_branding.py  (add --icons for only the web/brand icon sizes, --splash
for only the web loading screen)
- assets/textures/boot_splash.png  shown while the game downloads (the poster, art_source/brag.jpg) (project setting application/boot_splash/image)
- assets/icons/bloxov_icon.png     game icon, the web export makes the favicon from it (config/icon)
- assets/textures/title_text.png   the main screen's name block (BLOXOV, bar, NO MAN'S LAND, gold line), 1080p size
- web/brand/splash.jpg + splash_text.svg   the web page's loading screen (0.29.12): the poster with its lettering
                                   painted out, full size, and the lettering as a vector picture laid over it, so the
                                   text stays sharp at any size (tools/web_seo.py swaps them in for Godot's splash)
- web/brand/preview.png            1200x630 crop of the poster, Discord etc. show for a pasted link (og:image, CI copies it)
- web/brand/icon-48/96/192.png + favicon.ico   the icon at sizes Google search accepts (square, a multiple of
                                   48 px; the 256 px game icon isn't), linked from the page by tools/web_seo.py
Pixel fonts are drawn 1:1 then scaled up with nearest-neighbour, like the title screen's logo.
"""
from PIL import Image, ImageDraw, ImageEnhance, ImageFont

INK = (239, 230, 196)
DEEP = (18, 20, 23)
BLOOD = (211, 59, 44)
SHADOW = (0, 0, 0)
LOGO_FONT = "assets/fonts/BloxovJersey25-Regular.ttf"
SUB_FONT = "assets/fonts/BloxovJersey15-Regular.ttf"
POSTER_FONT = "assets/fonts/Silkscreen-Bold.ttf"   # (the poster's wide lettering, drawn at 8 px = its pixel grid)
GOLD = (226, 168, 62)


def pixel_text(text, font_path, size, scale, colour, spacing=0, shadow=True, shadow_dy=2):
    """Crisp pixel text: drawn at the font's own size without smoothing, then blown up `scale` times."""
    font = ImageFont.truetype(font_path, size)
    widths = [font.getbbox(c)[2] if c != " " else size // 3 for c in text]
    w = sum(widths) + spacing * (len(text) - 1) + 4
    asc, desc = font.getmetrics()
    h = asc + desc + 4
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    passes = [((0, shadow_dy), SHADOW + (200,)), ((0, 0), colour + (255,))] if shadow else [((0, 0), colour + (255,))]
    for (ox, oy), col in passes:
        x = 1
        for c, cw in zip(text, widths):
            d.text((x + ox, 1 + oy), c, font=font, fill=col)
            x += cw + spacing
    img = img.crop(img.getbbox())
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def backdrop(size, darken):
    """The title screen's dusk view, cropped to fill `size` and darkened so the logo reads."""
    src = Image.open("assets/textures/title_dusk.jpg").convert("RGB")
    tw, th = size
    k = max(tw / src.width, th / src.height)
    src = src.resize((round(src.width * k), round(src.height * k)), Image.LANCZOS)
    left = (src.width - tw) // 2
    top = (src.height - th) // 2
    src = src.crop((left, top, left + tw, top + th))
    return ImageEnhance.Brightness(src).enhance(darken).convert("RGBA")


def logo_block(scale):
    logo = pixel_text("BLOXOV", LOGO_FONT, 50, scale, INK)
    sub = pixel_text("NO MAN'S LAND", SUB_FONT, 30, max(1, scale // 2), INK, spacing=3)
    gap = 10 * scale
    bar_h = 2 * scale
    w = max(logo.width, sub.width)
    block = Image.new("RGBA", (w, logo.height + gap + bar_h + gap + sub.height), (0, 0, 0, 0))
    block.alpha_composite(logo, ((w - logo.width) // 2, 0))
    ImageDraw.Draw(block).rectangle(
        ((w - logo.width) // 2, logo.height + gap, (w + logo.width) // 2, logo.height + gap + bar_h - 1), fill=BLOOD)
    block.alpha_composite(sub, ((w - sub.width) // 2, logo.height + gap + bar_h + gap))
    return block


def centred(bg, block, y_shift=0):
    bg.alpha_composite(block, ((bg.width - block.width) // 2, (bg.height - block.height) // 2 + y_shift))
    return bg


POSTER = "art_source/brag.jpg"   # (0.27.2, owner's favourite picture: "use the brag.jpg for... posters title screen etc")


def poster(size):
    """The poster (art_source/brag.jpg, 1920x1080), scaled to cover `size` and cropped from the middle."""
    src = Image.open(POSTER).convert("RGB")
    tw, th = size
    k = max(tw / src.width, th / src.height)
    src = src.resize((round(src.width * k), round(src.height * k)), Image.LANCZOS)
    left = (src.width - tw) // 2
    top = (src.height - th) // 2
    return src.crop((left, top, left + tw, top + th))


# The poster's lettering (0.29.12), measured off brag.jpg: text, font, font size, pixel size, top-left of the letters
# in the 1920x1080 poster, colour, shadow offset (in the letters' pixels). Drawn with the fonts' own spacing.
POSTER_TEXT = [
    ("BLOXOV", LOGO_FONT, 50, 6, (615, 355), INK, 2),
    ("NO MAN'S LAND", POSTER_FONT, 8, 6, (711, 634), INK, 1),
    ("A BLOCKY FIRST-PERSON EXTRACTION SHOOTER", POSTER_FONT, 8, 5, (325, 841), GOLD, 1),
]
POSTER_BAR = (460, 555, 1000, 17)   # (x, y, width, height of the red bar)
SHADOW_ALPHA = 0.78


def glyph_grid(text, font_path, size):
    """The text's pixels at the font's own size (no smoothing), cropped to the letters: rows of True/False."""
    font = ImageFont.truetype(font_path, size)
    img = Image.new("L", (round(font.getlength(text)) + size * 2, size * 3), 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    d.text((size, size), text, font=font, fill=255)
    img = img.crop(img.getbbox())
    return [[img.getpixel((x, y)) > 0 for x in range(img.width)] for y in range(img.height)]


def runs_path(grid, unit, ox, oy, dx=0, dy=0):
    """An SVG path of the grid's set pixels, one rectangle per run along a row, in poster pixels."""
    out = []
    for y, row in enumerate(grid):
        x = 0
        while x < len(row):
            if row[x]:
                start = x
                while x < len(row) and row[x]:
                    x += 1
                out.append("M%d %dh%dv%dh-%dz" % (ox + (start + dx) * unit, oy + (y + dy) * unit,
                                                  (x - start) * unit, unit, (x - start) * unit))
            else:
                x += 1
    return "".join(out)


def splash_text_svg():
    """The loading screen's lettering as a 1920x1080 vector picture (0.29.12, owner: the loading screen text looked low
    quality: it was baked into the poster, shrunk to 1280 px for the boot splash, then stretched back up by the browser).
    The web page lays it over the poster with the same fit, so it lines up and stays sharp at any screen size."""
    shadows, inks = [], []
    for text, font, size, unit, (x, y), colour, off in POSTER_TEXT:
        grid = glyph_grid(text, font, size)
        shadows.append(runs_path(grid, unit, x, y, off, off))
        inks.append('<path fill="#%02x%02x%02x" d="%s"/>' % (colour + (runs_path(grid, unit, x, y),)))
    bx, by, bw, bh = POSTER_BAR
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080" '
            'shape-rendering="crispEdges">\n<path fill="#000" fill-opacity="%s" d="%s"/>\n%s\n'
            '<rect x="%d" y="%d" width="%d" height="%d" fill="#%02x%02x%02x"/>\n</svg>\n'
            % (SHADOW_ALPHA, "".join(shadows), "\n".join(inks), bx, by, bw, bh, *BLOOD))


def splash_background():
    """The poster with its baked-in lettering painted out (needs OpenCV: pip install opencv-python-headless), full
    size, for the web page's loading screen under splash_text_svg()."""
    import cv2
    import numpy as np
    mask = Image.new("L", (1920, 1080), 0)
    d = ImageDraw.Draw(mask)
    for text, font, size, unit, (x, y), _colour, off in POSTER_TEXT:
        for gy, row in enumerate(glyph_grid(text, font, size)):
            for gx, on in enumerate(row):
                if on:
                    d.rectangle((x + gx * unit, y + gy * unit, x + (gx + off + 1) * unit - 1,
                                 y + (gy + off + 1) * unit - 1), fill=255)
    bx, by, bw, bh = POSTER_BAR
    d.rectangle((bx, by, bx + bw - 1, by + bh - 1), fill=255)
    mask = np.asarray(mask)
    mask = cv2.dilate(mask, np.ones((7, 7), np.uint8))   # (the JPEG's smudge round each letter)
    src = cv2.imread(POSTER)
    clean = cv2.inpaint(src, mask, 6, cv2.INPAINT_TELEA)
    return Image.fromarray(cv2.cvtColor(clean, cv2.COLOR_BGR2RGB))


def make_splash():
    with open("web/brand/splash_text.svg", "w", encoding="utf-8") as f:
        f.write(splash_text_svg())
    splash_background().save("web/brand/splash.jpg", quality=92, optimize=True, progressive=True)


def title_text():
    """The main screen's name block, lettered like the poster (0.28.2): BLOXOV, the red bar, NO MAN'S LAND and the gold
    line, crisp pixels at the poster's 1080p size on a clear background. The title screen shows it as one picture scaled
    to the screen, so the letters keep even pixels on every screen (Labels drawn at an odd scale went uneven on the web)."""
    logo = pixel_text("BLOXOV", LOGO_FONT, 50, 6, INK)
    sub = pixel_text("NO MAN'S LAND", POSTER_FONT, 8, 6, INK, spacing=1, shadow_dy=1)
    tag = pixel_text("A BLOCKY FIRST-PERSON EXTRACTION SHOOTER", POSTER_FONT, 8, 4, GOLD, spacing=1, shadow_dy=1)
    bar_w, bar_h = logo.width + 300, 14
    rows = [(logo, 44), (None, 62), (sub, 46), (tag, 0)]
    w = max(bar_w, tag.width)
    h = sum((r.height if r else bar_h) + gap for r, gap in rows)
    block = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for r, gap in rows:
        if r is None:
            ImageDraw.Draw(block).rectangle(((w - bar_w) // 2, y, (w + bar_w) // 2 - 1, y + bar_h - 1), fill=BLOOD)
            y += bar_h + gap
        else:
            block.alpha_composite(r, ((w - r.width) // 2, y))
            y += r.height + gap
    return block


def main():
    # Splash: the web page shows it while the game downloads. Link preview: 1200x630 is what Discord, X and Facebook
    # expect. Both are the poster since 0.27.2 (before: the dusk view with the logo drawn here, backdrop()/logo_block()).
    poster((1280, 720)).save("assets/textures/boot_splash.png", optimize=True)
    poster((1200, 630)).save("web/brand/preview.png", optimize=True)
    title_text().save("assets/textures/title_text.png", optimize=True)
    make_splash()

    # Icon: a big "B" on the dark HUD colour with the red bar under it.
    icon = Image.new("RGBA", (256, 256), DEEP + (255,))
    d = ImageDraw.Draw(icon)
    d.rectangle((0, 0, 255, 255), outline=(53, 58, 64), width=8)
    b = pixel_text("B", LOGO_FONT, 50, 5, INK)
    icon.alpha_composite(b, ((256 - b.width) // 2, (232 - b.height) // 2))
    d.rectangle((48, 210, 207, 221), fill=BLOOD)
    icon.save("assets/icons/bloxov_icon.png")
    search_icons(icon)


def search_icons(icon):
    """Google only shows a site icon that is square and a multiple of 48 px (0.25.22)."""
    for size in (48, 96, 192):
        icon.resize((size, size), Image.LANCZOS).save("web/brand/icon-%d.png" % size)
    icon.save("web/brand/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--icons"]:  # just the icon sizes, from the saved game icon
        search_icons(Image.open("assets/icons/bloxov_icon.png").convert("RGBA"))
    elif sys.argv[1:] == ["--splash"]:  # just the web loading screen (web/brand/splash.jpg + splash_text.svg)
        make_splash()
    else:
        main()
