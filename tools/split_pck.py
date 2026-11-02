"""Splits the web export's game data into a small main pack plus content packs named by their content (0.29.6).

GitHub Pages gives every file a new ETag on every deploy, so the browser re-downloaded the whole ~60 MB pack after
each update. The big, rarely changing files (the building and outdoor models, the far views, the other imported art)
now go into packs whose names come from what's in them; index.html keeps those in the browser's Cache Storage (see
cache_bust.py), and scripts/web_packs.gd mounts them before the game loads anything. An update that only touches
scripts or scenes downloads just the main pack.

A content pack's name is a hash of its files' SOURCES (the source file and its .import settings), not of the
imported bytes: Godot's import isn't byte-for-byte repeatable (scene sub-resource ids), so an unchanged model would
otherwise get a new name every build. Same source, same settings = the same model, whichever import it came from.

Reads and writes Godot's PCK format (version 4 in Godot 4.7: header, file data from file_base, directory at the
offset stored at byte 32; offsets relative to file_base; 16-byte alignment).
"""
import hashlib
import struct
import zlib
from pathlib import Path

ALIGN = 16
# (source folder, pack group, number of packs it's split into: one changed model re-downloads only its share)
GROUPS = [
    ("assets/models/buildings/", "buildings", 4),
    ("assets/models/outdoor/", "outdoor", 2),
    ("assets/models/far/", "far", 2),
]
OTHER = ("art", 1)   # every other imported file


def read_pck(path: Path) -> dict:
    data = path.read_bytes()
    magic, version = struct.unpack_from("<4sI", data, 0)
    if magic != b"GDPC" or version != 4:
        raise SystemExit(f"split_pck: {path.name} is not a version 4 pack ({magic!r} v{version})")
    file_base, dir_off = struct.unpack_from("<QQ", data, 24)
    p = dir_off
    (count,) = struct.unpack_from("<I", data, p)
    p += 4
    files = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, p)
        p += 4
        raw_name = data[p:p + length]
        p += length
        offset, size = struct.unpack_from("<QQ", data, p)
        p += 16
        md5 = data[p:p + 16]
        p += 16
        (flags,) = struct.unpack_from("<I", data, p)
        p += 4
        name = raw_name.rstrip(b"\0").decode()
        files.append({"name": name, "raw_name": raw_name, "data": data[file_base + offset:file_base + offset + size],
                      "md5": md5, "flags": flags})
    if p != len(data):
        raise SystemExit(f"split_pck: unexpected bytes after the directory of {path.name}")
    return {"header": data[:file_base], "files": files}


def write_pck(path: Path, header: bytes, files: list) -> None:
    body = bytearray()
    entries = []
    for f in files:
        body += b"\0" * (-len(body) % ALIGN)
        entries.append((f, len(body)))
        body += f["data"]
    body += b"\0" * (-(len(header) + len(body)) % ALIGN)
    directory = bytearray(struct.pack("<I", len(entries)))
    for f, offset in entries:
        directory += struct.pack("<I", len(f["raw_name"])) + f["raw_name"]
        directory += struct.pack("<QQ", offset, len(f["data"])) + f["md5"] + struct.pack("<I", f["flags"])
    out = bytearray(header)
    struct.pack_into("<Q", out, 32, len(header) + len(body))
    path.write_bytes(bytes(out) + bytes(body) + bytes(directory))


def _sources(files: list) -> dict:
    """Imported file -> the source it was imported from (read from the .import remaps in the pack)."""
    out = {}
    for f in files:
        if not f["name"].endswith(".import"):
            continue
        for line in f["data"].decode(errors="ignore").splitlines():
            if line.startswith("path") and "\"res://.godot/imported/" in line:
                out[line.split("\"")[1][len("res://"):]] = f["name"][:-len(".import")]
    return out


def _group(source: str) -> tuple:
    for folder, group, parts in GROUPS:
        if source.startswith(folder):
            return group, zlib.crc32(source.encode()) % parts if parts > 1 else 0
    return OTHER[0], 0


def split(pck: Path, project: Path) -> list:
    """Moves the content files out of `pck` into content packs beside it. Returns [(pack file name, size)]."""
    pack = read_pck(pck)
    sources = _sources(pack["files"])
    main, content = [], {}
    for f in pack["files"]:
        name = f["name"]
        if name.startswith(".godot/imported/") and name in sources and not name.endswith(".fontdata"):
            source = sources[name]
            src_file, settings = project / source, project / (source + ".import")
            if src_file.exists() and settings.exists():
                key = hashlib.sha256(src_file.read_bytes() + b"\0" + settings.read_bytes()).hexdigest()
            else:
                key = hashlib.sha256(f["data"]).hexdigest()
        elif name.startswith("assets/models/far/") and name.endswith(".res"):
            source, key = name, hashlib.sha256(f["data"]).hexdigest()
        else:
            main.append(f)
            continue
        content.setdefault(_group(source), []).append((name, key, f))
    out = []
    for (group, part), entries in sorted(content.items()):
        entries.sort(key=lambda e: e[0])
        digest = hashlib.sha256("\n".join(f"{n} {k}" for n, k, _ in entries).encode()).hexdigest()[:12]
        name = f"pack-{group}{part if part else ''}-{digest}.pck"
        write_pck(pck.parent / name, pack["header"], [f for _, _, f in entries])
        out.append((name, (pck.parent / name).stat().st_size))
    write_pck(pck, pack["header"], main)
    return out
