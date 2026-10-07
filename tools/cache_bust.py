"""Post-processes the web export so browsers never run a stale build.

GitHub Pages tells browsers to cache files for ~10 minutes, and the export always uses the same
file names, so players could keep getting an old game after an update. This script:
  1. renames index.pck (the game data) to index-<version>.pck and points the loader at it,
  2. adds ?v=<version> to the engine script URL,
  3. writes version.txt and injects a tiny check into index.html that reloads the page
     (with ?v=<version>, which bypasses the cached HTML) when a newer build is deployed.

Usage: python3 tools/cache_bust.py build/web <version>
"""
import json
import re
import sys
from pathlib import Path

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
    new_pck_name = f"{executable}-{version}.pck"
    old_pck.rename(web / new_pck_name)
    config["mainPack"] = new_pck_name
    sizes = config.get("fileSizes", {})
    if f"{executable}.pck" in sizes:
        sizes[new_pck_name] = sizes.pop(f"{executable}.pck")

    html = html.replace(match.group(1), json.dumps(config))
    html = html.replace(f'src="{executable}.js"', f'src="{executable}.js?v={version}"')
    html = html.replace("</head>", CHECK % version + "</head>", 1)
    html_path.write_text(html)
    (web / "version.txt").write_text(version + "\n")
    print(f"cache-busted build {version}: {new_pck_name}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
