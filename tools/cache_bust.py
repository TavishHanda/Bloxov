"""Post-processes the web export so browsers never run a stale build.

GitHub Pages tells browsers to cache files for ~10 minutes, and the export always uses the same
file names, so players could keep getting an old game after an update. This script:
  1. renames index.pck (the game data) to index-<version>.pck and points the loader at it,
  2. adds ?v=<version> to the engine script URL,
  3. writes version.txt and injects a tiny check into index.html that reloads the page
     (with ?v=<version>, which bypasses the cached HTML) when a newer build is deployed,
  4. adds ?v=<version> to the tab icon links and writes favicon.ico, so browsers drop an old cached
     icon (browsers keep tab icons far longer than other files: players kept seeing Godot's icon).
  5. (0.29.6) splits the pack (tools/split_pck.py): the big art goes into content-named packs that the page
     downloads with the main pack and scripts/web_packs.gd mounts, and keeps every big file (engine, packs) in the
     browser's Cache Storage under its content hash, so an update only downloads what changed. GitHub Pages can't do
     that by itself: every deploy gives every file a new ETag, so the browser's own cache always downloads again.
  6. (0.36.30) the packs only raids need (the map models, split_pck.LATE) aren't waited for: the game starts
     without them and the page downloads them in the background, one at a time, copying each into the game's files
     as it arrives (window.BLOXOV_LATE_DONE); scripts/web_packs.gd mounts them and START RAID waits for any left.

Usage: python3 tools/cache_bust.py build/web <version>
"""
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import split_pck  # noqa: E402

# Keeps the files in BLOXOV_FILES (name -> content hash) in Cache Storage, fetched as name?h=<hash> (the query
# skips the browser's HTTP cache, which could still hold the previous build's file under the same name). A file is
# downloaded once per content: later visits and updates that didn't change it read it from the cache. Old builds'
# entries are dropped. Anything going wrong (no Cache Storage, private window, quota) falls back to a plain fetch.
FILE_CACHE = """<script>
window.BLOXOV_PACKS = %s;
window.BLOXOV_LATE_PACKS = %s;
window.BLOXOV_FILES = %s;
(function () {
  var files = window.BLOXOV_FILES, NAME = "bloxov-files";
  if (!window.caches || !window.fetch || !window.URL) return;
  var plain = window.fetch.bind(window);
  function keyOf(name) { return new URL(name + "?h=" + files[name], location.href).toString(); }
  window.fetch = function (input, init) {
    var name;
    try {
      name = new URL(typeof input === "string" ? input : input.url, location.href).pathname.split("/").pop();
    } catch (e) { return plain(input, init); }
    if (!Object.prototype.hasOwnProperty.call(files, name) || (init && init.bloxovOwnCache)) return plain(input, init);
    var key = keyOf(name);
    return caches.open(NAME).then(function (cache) {
      return cache.match(key).then(function (hit) {
        if (hit) return hit;
        return plain(key, init).then(function (response) {
          if (response.ok) cache.put(key, response.clone()).catch(function () {});
          return response;
        });
      });
    }).catch(function () { return plain(input, init); });
  };
  caches.open(NAME).then(function (cache) {
    var want = {};
    for (var n in files) want[keyOf(n)] = true;
    return cache.keys().then(function (keys) {
      keys.forEach(function (k) { if (!want[k.url]) cache.delete(k); });
    });
  }).catch(function () {});
})();
</script>
"""

# Downloads the extra packs alongside the engine and the main pack, and starts the game once all are in. Then
# downloads the late packs (raids only; ones already in the file cache load with the others) in the background, one at a time, trying again whenever the connection drops,
# and copies each into the game's files: window.BLOXOV_LATE has the progress (bytes), BLOXOV_LATE_DONE the packs in.
START_HOOK = """
(function () {
  var packs = window.BLOXOV_PACKS || [], late = window.BLOXOV_LATE_PACKS || [];
  var st = window.BLOXOV_LATE = {loaded: 0, total: 0, retrying: false};
  var done = window.BLOXOV_LATE_DONE = [];
  var got = {};
  // Late packs already in the file cache (an earlier visit) cost no download: they load with the others, as before.
  function cachedLate() {
    if (!late.length || !window.caches) return Promise.resolve([]);
    return caches.open("bloxov-files").then(function (cache) {
      return Promise.all(late.map(function (p) {
        return cache.match(keyOf(p)).then(function (hit) { return hit ? p : null; });
      }));
    }).then(function (list) { return list.filter(function (p) { return p; }); }).catch(function () { return []; });
  }
  function count() { var n = 0; for (var k in got) n += got[k]; st.loaded = n; }
  // Kept in the file cache by hand, as a Blob once it's all in: the usual way (a copy of the download streamed into
  // the cache) is pumped by the page itself and starves while the game is busy loading, so it often never finished.
  function keyOf(p) { return new URL(p + "?h=" + window.BLOXOV_FILES[p], location.href).toString(); }
  function keep(p, buffer) {
    if (!window.caches || !window.BLOXOV_FILES[p]) return;
    caches.open("bloxov-files").then(function (cache) {
      return cache.put(keyOf(p), new Response(new Blob([buffer]), {headers: {"Content-Type": "application/octet-stream"}}));
    }).catch(function () {});
  }
  function download(p) {
    got[p] = 0;
    var url = window.BLOXOV_FILES[p] ? keyOf(p) : p;
    return fetch(url, {bloxovOwnCache: true}).then(function (r) {
      if (!r.ok) throw new Error(p + ": " + r.status);
      if (!r.body || !r.body.getReader) {
        return r.arrayBuffer().then(function (b) { got[p] = b.byteLength; count(); return b; });
      }
      var reader = r.body.getReader(), parts = [], size = 0;
      function pump() {
        return reader.read().then(function (x) {
          if (x.done) {
            var out = new Uint8Array(size), at = 0;
            parts.forEach(function (c) { out.set(c, at); at += c.length; });
            return out.buffer;
          }
          parts.push(x.value);
          size += x.value.length;
          got[p] = size;
          count();
          return pump();
        });
      }
      return pump();
    });
  }
  function fetchLate(i, tries) {
    if (i >= late.length) return;
    var p = late[i];
    download(p).then(function (buffer) {
      st.retrying = false;
      keep(p, buffer);
      engine.copyToFS(p, buffer);
      done.push(p);
      fetchLate(i + 1, 0);
    }).catch(function (e) {
      console.warn("Bloxov: couldn't download " + p + ", trying again", e);
      got[p] = 0;
      count();
      st.retrying = true;
      setTimeout(function () { fetchLate(i, tries + 1); }, Math.min(10000, 1000 * (tries + 1)));
    });
  }
  var ready = cachedLate().then(function (have) {
    packs = window.BLOXOV_PACKS = packs.concat(have);
    late = window.BLOXOV_LATE_PACKS = late.filter(function (p) { return have.indexOf(p) < 0; });
    late.forEach(function (p) { st.total += GODOT_CONFIG.fileSizes[p] || 0; });
    return Promise.all(packs.map(function (p) { return engine.preloadFile(p, p); }));
  });
  var start = engine.start;
  engine.start = function (override) {
    var me = this;
    return ready.then(function () { return start.call(me, override); }).then(function (value) {
      fetchLate(0, 0);
      return value;
    });
  };
})();
"""

CHECK = """<script>
window.BLOXOV_VERSION = "%s";
fetch("version.txt", {cache: "no-store"}).then(function (r) { return r.ok ? r.text() : ""; }).then(function (v) {
  v = v.trim();
  if (!v || v === window.BLOXOV_VERSION) return;
  var url = new URL(location.href);
  if (url.searchParams.get("v") === v) return;  // already tried; avoid a reload loop
  url.searchParams.set("v", v);
  location.replace(url.toString());
}).catch(function () {});
</script>
"""


def png_to_ico(png: bytes) -> bytes:
    """An .ico holding one PNG (allowed since Windows Vista; every browser reads it)."""
    width, height = struct.unpack(">II", png[16:24])
    entry = struct.pack("<BBBBHHII", width % 256, height % 256, 0, 0, 1, 32, len(png), 6 + 16)
    return struct.pack("<HHH", 0, 1, 1) + entry + png


def main(build_dir: str, version: str) -> None:
    web = Path(build_dir)
    html_path = web / "index.html"
    html = html_path.read_text()

    match = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
    if not match:
        sys.exit("GODOT_CONFIG not found in index.html")
    config = json.loads(match.group(1))
    executable = config.get("executable", "index")

    old_pck = web / f"{executable}.pck"
    packs = split_pck.split(old_pck, Path.cwd())
    new_pck_name = f"{executable}-{version}.pck"
    old_pck.rename(web / new_pck_name)
    config["mainPack"] = new_pck_name
    sizes = config.get("fileSizes", {})
    sizes.pop(f"{executable}.pck", None)
    sizes[new_pck_name] = (web / new_pck_name).stat().st_size
    for name, size, _late in packs:
        sizes[name] = size
    config["fileSizes"] = sizes
    cached = {name: name.rsplit("-", 1)[1].split(".")[0] for name, _, _late in packs}
    for name in (new_pck_name, f"{executable}.wasm"):
        if (web / name).exists():
            cached[name] = hashlib.sha256((web / name).read_bytes()).hexdigest()[:16]

    html = html.replace(match.group(1), json.dumps(config))
    html = html.replace(f'src="{executable}.js"', f'src="{executable}.js?v={version}"')
    for icon in (f"{executable}.icon.png", f"{executable}.apple-touch-icon.png"):
        html = html.replace(f'href="{icon}"', f'href="{icon}?v={version}"')
    png = web / f"{executable}.icon.png"
    if png.exists() and not (web / "favicon.ico").exists():  # web_seo.py writes a proper multi-size one
        (web / "favicon.ico").write_bytes(png_to_ico(png.read_bytes()))
    html = html.replace("</head>", CHECK % version + FILE_CACHE % (json.dumps([n for n, _, late in packs if not late]),
                        json.dumps([n for n, _, late in packs if late]), json.dumps(cached)) + "</head>", 1)
    engine_line = "const engine = new Engine(GODOT_CONFIG);"
    if engine_line not in html:
        sys.exit("cache_bust: the engine line wasn't found in index.html")
    html = html.replace(engine_line, engine_line + START_HOOK, 1)
    html_path.write_text(html)
    (web / "version.txt").write_text(version + "\n")
    print(f"cache-busted build {version}: {new_pck_name} ({sizes[new_pck_name] / 1e6:.1f} MB) + "
          + ", ".join(f"{n} ({sz / 1e6:.1f} MB{', late' if late else ''})" for n, sz, late in packs))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
