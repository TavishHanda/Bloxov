"""Baked sky light for building models (World art 0.17, lighting pass).

The web build has no global illumination, so a room lit only by the flat ambient light looks as bright in its middle
as by the window. This bakes how much open sky each vertex can see (rays against the building's own gray boxes) into
vertex colours: rooms get darker away from windows, doors and holes, corners and under counters get a little
occlusion, and outside walls stay as they are. Godot multiplies the texture by the vertex colour.

Big faces are cut into cells (at most CELL m) first so the light can change across a floor or wall.
"""
import math

import numpy as np

CELL = 1.0          # metres: the size of the cells big faces are cut into
RAYS = 64           # rays per vertex (cosine-weighted over the face's hemisphere)
REACH = 40.0        # metres: a ray that gets this far without hitting anything sees the sky
GROUND = 0.7        # a ray that escapes downwards sees lit ground, not sky
SHADE_KINDS = ("canopy",)   # props big enough to cast shade (the rest of the furniture is left out)
GLOW = "glow"       # group of faces that light themselves (neon signs): always full light
DARK = 0.45         # vertex colour of a spot that sees no sky at all
GAIN = 4.0          # how fast the colour rises to 1 with the share of sky seen


def _directions():
    """Fixed cosine-weighted directions round +Y (Fibonacci spiral), so every bake gives the same result."""
    out = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(RAYS):
        r = math.sqrt((i + 0.5) / RAYS)
        a = i * golden
        out.append((r * math.cos(a), math.sqrt(max(0.0, 1.0 - r * r)), r * math.sin(a)))
    return np.array(out)


DIRS = _directions()


def _frame(n):
    """Rotation taking +Y to n."""
    n = np.array(n, dtype=float)
    t = np.array((1.0, 0.0, 0.0)) if abs(n[0]) < 0.9 else np.array((0.0, 0.0, 1.0))
    u = np.cross(n, t)
    u /= np.linalg.norm(u)
    w = np.cross(u, n)
    return np.stack([u, n, w])          # rows: x, y, z axes of the local frame


def occluders(rows):
    """Axis-aligned boxes from the gray-box rows (yawed boxes as their bounds; ramps left out)."""
    lo, hi = [], []
    for row in rows:
        if row.get("kind") and row["kind"] not in SHADE_KINDS:
            continue                    # furniture: its own boxes are drawn in detail, don't shade them from inside
        if abs(row.get("pitch", 0.0)) > 5:
            continue
        c, s = row["pos"], row["size"]
        if min(s) < 0.02:
            continue                    # floor decals and markings
        yaw = math.radians(row.get("yaw", 0.0))
        ex = abs(math.cos(yaw)) * s[0] / 2 + abs(math.sin(yaw)) * s[2] / 2
        ez = abs(math.sin(yaw)) * s[0] / 2 + abs(math.cos(yaw)) * s[2] / 2
        lo.append((c[0] - ex, c[1] - s[1] / 2, c[2] - ez))
        hi.append((c[0] + ex, c[1] + s[1] / 2, c[2] + ez))
    return np.array(lo), np.array(hi)


def sky(points, normals, lo, hi):
    """Share of sky (0..1) each point sees over its normal's hemisphere."""
    out = np.empty(len(points))
    for k, (p, n) in enumerate(zip(points, normals)):
        d = DIRS @ _frame(n)                                         # (R, 3) world directions
        o = np.array(p) + np.array(n) * 0.03
        inv = 1.0 / np.where(np.abs(d) < 1e-9, 1e-9, d)              # (R, 3)
        t0 = (lo[None, :, :] - o[None, None, :]) * inv[:, None, :]   # (R, B, 3)
        t1 = (hi[None, :, :] - o[None, None, :]) * inv[:, None, :]
        tmin = np.minimum(t0, t1).max(axis=2)
        tmax = np.maximum(t0, t1).min(axis=2)
        hit = ((tmax >= tmin) & (tmax > 0.0) & (tmin < REACH)).any(axis=1)
        weight = np.where(d[:, 1] < 0.0, GROUND, 1.0)
        out[k] = float((weight * ~hit).sum() / RAYS)
    return out


def shade(v):
    return DARK + (1.0 - DARK) * min(1.0, v * GAIN)


def _split(pts, uvs):
    """A quad cut into a grid of cells no bigger than CELL; uvs are interpolated (exact for the affine mappings)."""
    if len(pts) != 4:
        return [(pts, uvs)]
    p = [np.array(q, dtype=float) for q in pts]
    nu = max(1, math.ceil(np.linalg.norm(p[1] - p[0]) / CELL - 1e-6))
    nv = max(1, math.ceil(np.linalg.norm(p[3] - p[0]) / CELL - 1e-6))
    if nu == 1 and nv == 1:
        return [(pts, uvs)]
    t = [np.array(q, dtype=float) for q in uvs]

    def at(arr, s, r):
        return tuple((arr[0] * (1 - s) * (1 - r) + arr[1] * s * (1 - r) + arr[2] * s * r + arr[3] * (1 - s) * r).tolist())
    out = []
    for i in range(nu):
        for j in range(nv):
            cs = ((i / nu, j / nv), ((i + 1) / nu, j / nv), ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv))
            out.append(([at(p, s, r) for s, r in cs], [at(t, s, r) for s, r in cs]))
    return out


def bake(builder, rows):
    """Cuts the builder's big faces into cells and gives every vertex a colour (builder.colors, per face).
    Faces in a group (one small item) all get the light at the item's middle."""
    lo, hi = occluders(rows)
    groups = getattr(builder, "groups", None) or [None] * len(builder.faces)
    if not len(lo):
        builder.colors = [[(1.0, 1.0, 1.0)] * len(f) for f in builder.faces]
        return
    cache = {}

    def key(p, n):
        k = (round(p[0], 3), round(p[1], 3), round(p[2], 3), round(n[0], 2), round(n[1], 2), round(n[2], 2))
        cache.setdefault(k, None)
        return k
    # The middle of each item.
    centres = {}
    for face, g in zip(builder.faces, groups):
        if g is not None and g != GLOW:
            acc = centres.setdefault(g, [0.0, 0.0, 0.0, 0])
            for i in face:
                for a in range(3):
                    acc[a] += builder.verts[i][a]
                acc[3] += 1
    group_key = {g: key((a[0] / a[3], a[1] / a[3], a[2] / a[3]), (0.0, 1.0, 0.0)) for g, a in centres.items()}
    group_key[GLOW] = GLOW
    cache[GLOW] = 1.0
    # Which faces need cutting (any corner short of full light).
    corner_keys = [None if g is not None else [key(builder.verts[i], n) for i in face]
                   for face, n, g in zip(builder.faces, builder.normals, groups)]
    _resolve(cache, lo, hi)
    faces, uvs, mats, normals, verts, gs = [], [], [], [], [], []
    for face, uv, m, n, g, keys in zip(builder.faces, builder.uvs, builder.mats, builder.normals, groups, corner_keys):
        pts = [builder.verts[i] for i in face]
        pieces = [(pts, uv)] if g is not None or min(cache[k] for k in keys) > 0.995 else _split(pts, uv)
        for q, t in pieces:
            base = len(verts)
            verts += q
            faces.append(list(range(base, base + len(q))))
            uvs.append(t)
            mats.append(m)
            normals.append(n)
            gs.append(g)
    keys = [[group_key[g]] * len(f) if g is not None else [key(verts[i], n) for i in f]
            for f, n, g in zip(faces, normals, gs)]
    _resolve(cache, lo, hi)
    builder.verts, builder.faces, builder.uvs, builder.mats, builder.normals = verts, faces, uvs, mats, normals
    builder.groups = gs
    builder.colors = [[(cache[k],) * 3 for k in ks] for ks in keys]


def _resolve(cache, lo, hi):
    todo = [k for k, v in cache.items() if v is None]
    if not todo:
        return
    pts = [k[:3] for k in todo]
    nrm = [k[3:] for k in todo]
    nrm = [tuple(np.array(n) / (np.linalg.norm(n) or 1.0)) for n in nrm]
    for k, v in zip(todo, sky(pts, nrm, lo, hi)):
        cache[k] = shade(v)
