"""Makes the web export findable by search engines (0.25.9).

Godot's page is just a canvas, so search engines see almost nothing on it. This script:
  1. sets a descriptive tab title, and keeps it once the game starts (Godot sets the tab title to the
     project name, "Bloxov", on start; the desktop window title stays "Bloxov"),
  2. adds a canonical link (players can land on ?v=<version> after an update, see cache_bust.py),
  3. adds the game's structured data (web/seo/game.json, schema.org VideoGame),
  4. puts a short intro (web/seo/intro.html + intro.css) on the loading screen; it sits inside Godot's
     #status overlay, so it goes away with the loading screen once the game starts,
  5. copies web/robots.txt and writes sitemap.xml (one page, dated today).

Usage: python3 tools/web_seo.py build/web
"""
import datetime
import json
import shutil
import sys
from pathlib import Path

SITE = "https://bloxov.com/"
TITLE = "Bloxov: No Man's Land \u2013 Free Browser Extraction Shooter"
# Ignores Godot's start-up "document.title = 'Bloxov'"; any other title the game sets still goes through.
KEEP_TITLE = """<script>(function(){var d=Object.getOwnPropertyDescriptor(Document.prototype,"title");if(!d||!d.set)return;
Object.defineProperty(document,"title",{configurable:true,get:function(){return d.get.call(document);},
set:function(v){if(v!=="Bloxov")d.set.call(document,v);}});})();</script>
"""
SRC = Path(__file__).resolve().parent.parent / "web"


def replace_once(html: str, old: str, new: str) -> str:
    if html.count(old) != 1:
        sys.exit("web_seo: expected exactly one %r in index.html" % old)
    return html.replace(old, new)


def main(build_dir: str) -> None:
    web = Path(build_dir)
    html_path = web / "index.html"
    html = html_path.read_text(encoding="utf-8")

    start = html.find("<title>")
    end = html.find("</title>", start)
    if start < 0 or end < 0:
        sys.exit("web_seo: <title> not found in index.html")
    data = json.loads((SRC / "seo" / "game.json").read_text(encoding="utf-8"))  # fails the build if malformed
    head = (
        "<title>%s</title>\n" % TITLE
        + KEEP_TITLE
        + '<link rel="canonical" href="%s">\n' % SITE
        + '<script type="application/ld+json">%s</script>\n' % json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
        + "<style>%s</style>\n" % (SRC / "seo" / "intro.css").read_text(encoding="utf-8").strip()
    )
    html = html[:start] + head + html[end + len("</title>"):]
    intro = (SRC / "seo" / "intro.html").read_text(encoding="utf-8").strip()
    html = replace_once(html, '<div id="status">', '<div id="status">\n' + intro)
    html_path.write_text(html, encoding="utf-8")

    shutil.copy(SRC / "robots.txt", web / "robots.txt")
    today = datetime.date.today().isoformat()
    (web / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        "  <url><loc>%s</loc><lastmod>%s</lastmod></url>\n"
        "</urlset>\n" % (SITE, today),
        encoding="utf-8",
    )
    print("web_seo: title, canonical, structured data, intro, robots.txt and sitemap.xml done")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
