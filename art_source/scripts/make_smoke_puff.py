"""Makes assets/textures/smoke_puff.png (0.32.3): one puff of smoke for the burning wrecks' columns, drawn as pixel art
to match the blocky clouds (owner picked option D: pixel puffs with a lighter top, like the clouds).
16 x 16, two steps of see-through (a fainter rim round a solid middle), white on top and a little greyer below
(the particles tint it). The game draws it pixel-sharp (nearest filter) and never turns it, so the pixels stay square.
Run from the repo root: python3 art_source/scripts/make_smoke_puff.py"""
import math
import random
from PIL import Image

SIZE = 16
STEPS = 2
rng = random.Random(7)
# (centre x, centre y, radius) in 0..1 of the image: one big blob and a few smaller ones round it
blobs = [(0.5, 0.52, 0.34)]
for _ in range(6):
    a = rng.uniform(0, math.tau)
    d = rng.uniform(0.1, 0.2)
    blobs.append((0.5 + math.cos(a) * d, 0.52 + math.sin(a) * d, rng.uniform(0.15, 0.22)))

img = Image.new("RGBA", (SIZE, SIZE))
px = img.load()
for y in range(SIZE):
    for x in range(SIZE):
        u, v = (x + 0.5) / SIZE, (y + 0.5) / SIZE
        a = 0.0
        for bx, by, r in blobs:
            a = max(a, min(1.0, max(0.0, 1.0 - math.hypot(u - bx, v - by) / r) * 2.2))
        q = max(0.0, min(1.0, math.ceil(a * STEPS - 0.35) / STEPS)) if a > 0.08 else 0.0
        shade = 255 if v < 0.45 else 219   # lit top, greyer underside
        px[x, y] = (shade, shade, shade, int(q * 255))
img.save("assets/textures/smoke_puff.png")
print("saved assets/textures/smoke_puff.png")
