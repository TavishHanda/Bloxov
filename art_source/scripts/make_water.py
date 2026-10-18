"""Bloxov Battlegrounds water texture (World art 0.17, outdoor step 6; plan /mnt/project-files/notes/outdoor-plan.md).

The creek is drawn by assets/shaders/water.gdshader (material assets/materials/water.tres). It scrolls one small
tiling texture downstream in two layers: R and G are the ripples' slope (the surface normal, 0.5 = flat), B is a
blotchy noise the shader cuts into foam, A a sparse speckle for the flecks drifting on the water. 64 px for 2 m, like
the ground tiles, so the water's pixels match the grass beside it.

    python3 art_source/scripts/make_water.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "textures", "water")
SIZE = 64


def noise(rng, size, low, high):
    """Tiling noise (0..1): white noise kept to the wavelengths between size/high and size/low pixels."""
    f = np.fft.fft2(rng.standard_normal((size, size)))
    k = np.hypot(*np.meshgrid(np.fft.fftfreq(size) * size, np.fft.fftfreq(size) * size))
    f *= (k >= low) & (k <= high)
    n = np.real(np.fft.ifft2(f))
    return (n - n.min()) / (n.max() - n.min())


def main():
    rng = np.random.default_rng(6)
    # ripples: mostly long across the flow (wavelets stretched across the creek), plus a little fine chop
    h = noise(rng, SIZE, 1, 4) * 0.7 + noise(rng, SIZE, 4, 10) * 0.3
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 2.5
    dz = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 2.5
    foam = noise(rng, SIZE, 2, 7)
    fleck = noise(rng, SIZE, 8, 20) ** 3
    rgba = np.stack([np.clip(0.5 + dx, 0, 1), np.clip(0.5 + dz, 0, 1), foam, fleck / fleck.max()], -1)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "ripples.png"))
    print("water texture written")


if __name__ == "__main__":
    main()
