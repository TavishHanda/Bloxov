"""Checks that the raid characters' models (scav, PMC, raider) didn't grow: every part that the hitboxes are measured
from (on the Neck, Spine, Hips, Leg and Knee joints, scripts/body_pose.gd measure()) fits inside the same part of an
older version, and each joint's parts cover the same box as before. Run after changing make_character.py:
  python3 tools/check_character_bounds.py [rev=HEAD] [scav pmc raider]
compares assets/models/characters/<name>.glb with the one in git `rev`. Owner 2026-11-09: looks may change, body
sizes and hitboxes never (unless the owner asks)."""
import json, os, struct, subprocess, sys, tempfile
def load(path):
    """Each mesh part's box: {node name: (joint, min, max)}."""
    data = open(path, "rb").read()
    jl = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jl])
    parent = {}
    for i, n in enumerate(g["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    out = {}
    for i, n in enumerate(g["nodes"]):
        if "mesh" in n:
            acc = g["accessors"][g["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
            out[n["name"]] = (g["nodes"][parent[i]]["name"], acc["min"], acc["max"])
    return out
MEASURED = ("Neck", "Spine", "Hips", "LegL", "LegR", "KneeL", "KneeR")
def check(old, new):
    a, b = load(old), load(new)
    bad = []
    for name, (joint, lo, hi) in b.items():
        if joint not in MEASURED:
            continue
        if name not in a:
            bad.append("new measured part " + name); continue
        _, olo, ohi = a[name]
        if any(lo[k] < olo[k] - 1e-4 or hi[k] > ohi[k] + 1e-4 for k in range(3)):
            bad.append("%s grew: %s..%s vs %s..%s" % (name, [round(x,3) for x in lo], [round(x,3) for x in hi], [round(x,3) for x in olo], [round(x,3) for x in ohi]))
    for name in a:
        if name not in b:
            bad.append("missing " + name)
    # joint unions equal
    for j in MEASURED:
        def u(d):
            ps = [(lo, hi) for jj, lo, hi in d.values() if jj == j]
            if not ps: return None
            return [round(min(p[0][k] for p in ps), 4) for k in range(3)] + [round(max(p[1][k] for p in ps), 4) for k in range(3)]
        if u(a) != u(b):
            bad.append("joint %s union changed %s -> %s" % (j, u(a), u(b)))
    return bad
if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rev = next((a[4:] for a in sys.argv[1:] if a.startswith("rev=")), "HEAD")
    names = [a for a in sys.argv[1:] if not a.startswith("rev=")] or ["scav", "pmc", "raider"]
    ok = True
    tmp = tempfile.mkdtemp()
    for c in names:
        rel = "assets/models/characters/%s.glb" % c
        with open(os.path.join(tmp, c + ".glb"), "wb") as f:
            f.write(subprocess.run(["git", "show", "%s:%s" % (rev, rel)], cwd=root, check=True, capture_output=True).stdout)
        bad = check(os.path.join(tmp, c + ".glb"), os.path.join(root, rel))
        print(c, "OK" if not bad else "")
        for x in bad: print("  ", x)
        ok = ok and not bad
    sys.exit(0 if ok else 1)
