"""Do Riptide's models match their collision? (0.36.42, owner: "make sure all the models match hitboxes")

For every Riptide model (art_source/buildings/<name>.json with "map": "riptide" and its .glb) this checks both ways:
  DRAWN, NOT SOLID   parts of the model further than 0.35 m outside every box (people and bullets go through
                     something that looks solid);
  SOLID, NOT DRAWN   faces of solid boxes, not pressed against another box, with no part of the model within 0.3 m
                     (an invisible wall).
Small things are left out on purpose (frames, sills, signs, lamps, rails stand off a wall by less than 0.35 m).
Reports clusters (2 m cells) with world positions, biggest first.
    python3 tools/riptide_model_audit.py [name ...]
"""
import glob
import json
import math
import os
import struct
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGINS = {}     # filled from tools/gen_riptide.py's modeled() calls


def origins():
    import re
    src = open(os.path.join(ROOT, "tools", "gen_riptide.py")).read()
    for m in re.finditer(r'modeled\("(\w+)",\s*(-?[\d.]+),\s*(-?[\d.]+)\)', src):
        ORIGINS[m.group(1)] = (float(m.group(2)), float(m.group(3)))


def read_glb(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    bin_len = struct.unpack("<I", b[off:off + 4])[0]
    data = b[off + 8:off + 8 + bin_len]

    def acc(i):
        a = j["accessors"][i]
        v = j["bufferViews"][a["bufferView"]]
        start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        k = {"VEC3": 3, "VEC2": 2, "SCALAR": 1, "VEC4": 4}[a["type"]]
        return np.frombuffer(data, comp, a["count"] * k, start).reshape(-1, k) if k > 1 else \
            np.frombuffer(data, comp, a["count"], start)
    tris = []
    for mesh in j["meshes"]:
        for p in mesh["primitives"]:
            pos = acc(p["attributes"]["POSITION"]).astype(np.float64)
            idx = acc(p["indices"]).astype(np.int64)
            tris.append(pos[idx.reshape(-1, 3)])
    return np.concatenate(tris)


def box_arrays(rows):
    c = np.array([r["pos"] for r in rows], float)
    h = np.array([r["size"] for r in rows], float) / 2
    yaw = np.radians([r["yaw"] for r in rows])
    pitch = np.array([r["pitch"] for r in rows], float)
    # (pitched boxes, the ramps: their whole tilted extent, so a ramp's drawn flight is never flagged)
    for i in np.nonzero(pitch)[0]:
        p = math.radians(abs(pitch[i]))
        hy = h[i][1] * math.cos(p) + h[i][2] * math.sin(p)
        hz = h[i][2] * math.cos(p) + h[i][1] * math.sin(p)
        h[i] = (h[i][0], hy, hz)
    return c, h, yaw


def dist_to_boxes(pts, c, h, yaw, chunk=4000):
    """Distance from each point to the nearest box (0 inside)."""
    out = np.full(len(pts), np.inf)
    cs, sn = np.cos(yaw), np.sin(yaw)
    for s in range(0, len(pts), chunk):
        p = pts[s:s + chunk][:, None, :] - c[None, :, :]
        # into each box's frame (Godot: yaw about +Y)
        lx = p[..., 0] * cs[None] - p[..., 2] * sn[None]
        lz = p[..., 0] * sn[None] + p[..., 2] * cs[None]
        d = np.stack([np.abs(lx) - h[None, :, 0], np.abs(p[..., 1]) - h[None, :, 1], np.abs(lz) - h[None, :, 2]], -1)
        out[s:s + chunk] = np.sqrt((np.maximum(d, 0) ** 2).sum(-1)).min(1)
    return out


def tri_samples(tris, step=0.3):
    """Points spread over every triangle (about one per step x step)."""
    pts = [tris.mean(1)]
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    big = area > step * step
    if big.any():
        a, b, c, ar = a[big], b[big], c[big], area[big]
        n = np.minimum((ar / (step * step)).astype(int) + 1, 4000)
        rep = np.repeat(np.arange(len(a)), n)
        u, v = np.random.default_rng(1).random((2, len(rep)))
        flip = u + v > 1
        u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
        pts.append(a[rep] + (b[rep] - a[rep]) * u[:, None] + (c[rep] - a[rep]) * v[:, None])
    return np.concatenate(pts)


def audit(name):
    data = json.load(open(os.path.join(ROOT, "art_source", "buildings", name + ".json")))
    glb = os.path.join(ROOT, "assets", "models", "buildings", name + ".glb")
    if not os.path.exists(glb):
        return []
    ox, oz = ORIGINS.get(name, (0.0, 0.0))
    tris = read_glb(glb)
    rows = data["boxes"]
    # (every Riptide model's boxes count: the hold's ceiling is drawn by below_decks over leviathan_hull's deck)
    others = []
    own = np.array([r["pos"] for r in rows])
    lo, hi = own.min(0), own.max(0)
    for other, (oox, ooz) in ORIGINS.items():
        if other == name:
            continue
        path = os.path.join(ROOT, "art_source", "buildings", other + ".json")
        if os.path.exists(path):
            for r in json.load(open(path))["boxes"]:
                p = r["pos"]
                q = [p[0] + oox - ox, p[1], p[2] + ooz - oz]
                if lo[0] - 5 < q[0] < hi[0] + 5 and lo[2] - 5 < q[2] < hi[2] + 5:     # (only the ones near this model)
                    others.append(dict(r, pos=q))
    c, h, yaw = box_arrays(rows + others)
    n_own = len(rows)
    rows = rows + others
    solid = np.array([r.get("solid", True) for r in rows])
    found = []
    # DRAWN, NOT SOLID: triangle samples far from every box (solid or not: a drawn walk-through piece has its box)
    pts = tri_samples(tris, 0.5)
    d = dist_to_boxes(pts, c, h, yaw)
    far = pts[(d > 0.35) & (pts[:, 1] > 2.6)]      # (floors laid on the ground: the ground is the map's own)
    found += clusters(far, "drawn, not solid", ox, oz, 0.25)
    # SOLID, NOT DRAWN: points on solid, unrotated boxes' faces (not pressed on another box) with nothing drawn near
    grid = {}
    for p in np.round(tri_samples(tris, 0.25) / 0.3).astype(int):
        grid[tuple(p)] = True
    sc, sh, syaw = c[solid], h[solid], yaw[solid]
    own = np.arange(len(rows)) < n_own
    straight = ((np.array([r["yaw"] for r in rows]) % 180 == 0) & (np.array([r["pitch"] for r in rows]) == 0) & own)[solid]
    samples = []
    for bc, bh in zip(sc[straight], sh[straight]):
        for ax in range(3):
            for sg in (-1, 1):
                o = [k for k in range(3) if k != ax]
                n0 = max(2, int(2 * bh[o[0]] / 0.5) + 1)
                n1 = max(2, int(2 * bh[o[1]] / 0.5) + 1)
                if n0 * n1 > 4000:
                    n0, n1 = min(n0, 63), min(n1, 63)
                g0 = np.linspace(-bh[o[0]] * 0.95, bh[o[0]] * 0.95, n0)
                g1 = np.linspace(-bh[o[1]] * 0.95, bh[o[1]] * 0.95, n1)
                A, B = np.meshgrid(g0, g1)
                P = np.zeros((A.size, 3))
                P[:, ax] = bc[ax] + sg * (bh[ax] + 0.03)
                P[:, o[0]] = bc[o[0]] + A.ravel()
                P[:, o[1]] = bc[o[1]] + B.ravel()
                samples.append(P)
    if samples:
        S = np.concatenate(samples)
        covered = dist_to_boxes(S, sc, sh, syaw) <= 0.0
        S = S[~covered]
        S = S[S[:, 1] > 2.6]                                   # (on or under the ground: nobody sees it)
        keys = np.round(S / 0.3).astype(int)
        seen = np.zeros(len(S), dtype=bool)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    seen |= np.array([(k[0] + dx, k[1] + dy, k[2] + dz) in grid for k in keys], dtype=bool)
        found += clusters(S[~seen], "solid, not drawn", ox, oz, 0.25)
    return found


def panel(q):
    """Do these points (one 2 m cell) fill a patch of surface, rather than lie along thin members?"""
    w, v = np.linalg.eigh(np.cov(q.T) + np.eye(3) * 1e-9)
    if math.sqrt(max(w[1], 0)) < 0.15:
        return False                       # (along a line)
    a, b = q @ v[:, 2], q @ v[:, 1]
    na = max(1, int((a.max() - a.min()) / 0.25) + 1)
    nb = max(1, int((b.max() - b.min()) / 0.25) + 1)
    occ = len({(int((x - a.min()) / 0.25), int((y - b.min()) / 0.25)) for x, y in zip(a, b)})
    return occ / (na * nb) > 0.45 and (a.max() - a.min()) * (b.max() - b.min()) > 0.3


def clusters(pts, what, ox, oz, cell_area):
    if len(pts) == 0:
        return []
    cells = {}
    for p in pts:
        k = (int(math.floor(p[0] / 2)), int(math.floor(p[1] / 2)), int(math.floor(p[2] / 2)))
        cells.setdefault(k, []).append(p)
    out = []
    for k, ps in cells.items():
        if len(ps) < 3:
            continue
        ps = np.array(ps)
        m = np.mean(ps, 0)
        if what.startswith("drawn") and not panel(ps - m):
            continue                       # (a thin member: a truss, a rail, a pipe; shots and eyes pass it anyway)
        out.append((len(ps), what, (round(float(m[0]) + ox, 1), round(float(m[1]), 1), round(float(m[2]) + oz, 1))))
    return out


def main():
    origins()
    names = sys.argv[1:] or sorted(os.path.basename(f)[:-5] for f in glob.glob(os.path.join(ROOT, "art_source", "buildings", "*.json"))
                                   if json.load(open(f)).get("map") == "riptide")
    total = 0
    for name in names:
        found = sorted(audit(name), reverse=True)
        total += len(found)
        print(f"{name}: {len(found)} spots")
        for n, what, p in found[:400]:
            print(f"  {what:17s} {n:5d} samples near {p}")
    print("MODEL AUDIT:", "OK" if total == 0 else f"{total} spots to look at")


if __name__ == "__main__":
    main()
