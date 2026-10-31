"""Makes the web page's Bloxov pictures: the loading-screen splash, the icon (favicon) and the link preview.

Run from the repo root: python3 tools/make_web_branding.py
- assets/textures/boot_splash.png  shown while the game downloads (project setting application/boot_splash/image)
- assets/icons/bloxov_icon.png     game icon, the web export makes the favicon from it (config/icon)
- web/brand/preview.png            1200x630 picture Discord etc. show for a pasted link (og:image, CI copies it)
Pixel fonts are drawn 1:1 then scaled up with nearest-neighbour, like the title screen's logo.
"""
from PIL import Image, ImageDraw, ImageEnhance, ImageFont

INK = (239, 230, 196)
DEEP = (18, 20, 23)
BLOOD = (211, 59, 44)
SHADOW = (0, 0, 0)
LOGO_FONT = "assets/fonts/BloxovJersey25-Regular.ttf"
SUB_FONT = "assets/fonts/BloxovJersey15-Regular.ttf"


def pixel_text(text, font_path, size, scale, colour, spacing=0, shadow=True):
    """Crisp pixel text: drawn at the font's own size without smoothing, then blown up `scale` times."""
    font = ImageFont.truetype(font_path, size)
    widths = [font.getbbox(c)[2] if c != " " else size // 3 for c in text]
    w = sum(widths) + spacing * (len(text) - 1) + 4
    asc, desc = font.getmetrics()
    h = asc + desc + 4
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    passes = [((0, 2), SHADOW + (200,)), ((0, 0), colour + (255,))] if shadow else [((0, 0), colour + (255,))]
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


def main():
    # Splash: the web page shows it centred over the dark background while the game downloads.
    splash = backdrop((1280, 720), 0.45)
    centred(splash, logo_block(3), -30).convert("RGB").save("assets/textures/boot_splash.png")

    # Link preview (1200x630 is what Discord, X and Facebook expect).
    prev = backdrop((1200, 630), 0.5)
    centred(prev, logo_block(3), -40)
    tag = pixel_text("BLOCKY EXTRACTION SHOOTER  -  PLAY FREE IN YOUR BROWSER", SUB_FONT, 30, 1, INK, spacing=2)
    prev.alpha_composite(tag, ((prev.width - tag.width) // 2, 500))
    prev.convert("RGB").save("web/brand/preview.png")

    # Icon: a big "B" on the dark HUD colour with the red bar under it.
    icon = Image.new("RGBA", (256, 256), DEEP + (255,))
    d = ImageDraw.Draw(icon)
    d.rectangle((0, 0, 255, 255), outline=(53, 58, 64), width=8)
    b = pixel_text("B", LOGO_FONT, 50, 5, INK)
    icon.alpha_composite(b, ((256 - b.width) // 2, (232 - b.height) // 2))
    d.rectangle((48, 210, 207, 221), fill=BLOOD)
    icon.save("assets/icons/bloxov_icon.png")


if __name__ == "__main__":
    main()
