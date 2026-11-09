"""Makes assets/textures/smoke_puff.png (0.32.3): one soft, lumpy puff of smoke, white (the particles tint it).
A few round blobs on top of each other, soft at every edge, so a column of them reads as smoke, not boxes.
Run from the repo root: python3 art_source/scripts/make_smoke_puff.py"""
import math
import random
from PIL import Image

SIZE = 64
rng = random.Random(7)
# (centre x, centre y, radius, strength) in 0..1 of the image
blobs = [(0.5, 0.52, 0.36, 1.0)]
for _ in range(7):
    a = rng.uniform(0, math.tau)
    d = rng.uniform(0.08, 0.2)
    blobs.append((0.5 + math.cos(a) * d, 0.52 + math.sin(a) * d, rng.uniform(0.14, 0.22), rng.uniform(0.6, 0.9)))

img = Image.new("RGBA", (SIZE, SIZE))
px = img.load()
for y in range(SIZE):
    for x in range(SIZE):
        u, v = (x + 0.5) / SIZE, (y + 0.5) / SIZE
        a = 0.0
        for bx, by, r, s in blobs:
            t = max(0.0, 1.0 - math.hypot(u - bx, v - by) / r)
            a = max(a, s * t * t * (3 - 2 * t))
        # fade the whole thing out before the edge of the square, whatever the blobs did
        edge = max(0.0, 1.0 - math.hypot(u - 0.5, v - 0.5) / 0.5)
        a = min(1.0, a * min(1.0, edge * 2.5))
        shade = int(255 * (0.86 + 0.14 * (1.0 - v)))   # a little lighter on top, like light from above
        px[x, y] = (shade, shade, shade, int(round(a * 255)))
img.save("assets/textures/smoke_puff.png")
print("saved assets/textures/smoke_puff.png")
