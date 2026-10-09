"""Writes docs/ITEMS.md from the item database in scripts/item_db.gd.

Run from the repo root after changing items or loot tables:  python3 tools/gen_item_list.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "item_db.gd"
SCENES = ROOT / "scenes"
OUT = ROOT / "docs" / "ITEMS.md"
RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]
KIND_LABEL = {"weapon": "Weapon", "armor": "Armor", "backpack": "Backpack", "ammo": "Ammo", "heal": "Healing", "valuable": "Valuable"}


def read_dict(text, name):
    """Parses a `const NAME := { ... }` block (GDScript dict literals are JSON-like here)."""
    block = re.search(r"const %s := (\{.*?\n\})" % name, text, re.S).group(1)
    block = re.sub(r",(\s*[}\]])", r"\1", block)  # trailing commas
    return json.loads(block)


def read_exports(script_text):
    """Default values of `@export var name := value` lines (ints and strings only)."""
    exports = {}
    for name, value in re.findall(r"^@export var (\w+) := (\S+)", script_text, re.M):
        exports[name] = value.strip('"') if value.startswith('"') else (int(value) if value.isdigit() else value)
    return exports


def scene_props(scene_text, script_name):
    """Properties set on the root node of a scene whose root uses `scripts/<script_name>`."""
    ext = re.search(r'\[ext_resource type="Script" path="res://scripts/%s" id="([^"]+)"\]' % re.escape(script_name), scene_text)
    if ext is None:
        return None
    root = re.search(r'\[node name="[^"]+" type="[^"]+"\]\n(.*?)(?:\n\n|\n\[|\Z)', scene_text, re.S)
    if root is None or ('script = ExtResource("%s")' % ext.group(1)) not in root.group(1):
        return None
    props = {}
    for name, value in re.findall(r"^(\w+) = (.+)$", root.group(1), re.M):
        props[name] = value.strip('"') if value.startswith('"') else (int(value) if value.isdigit() else value)
    return props


def roll_counts():
    """{loot table: (min rolls, max rolls, is a body bag, makes noise)} read from the scenes and their scripts."""
    container_defaults = read_exports((ROOT / "scripts" / "loot_container.gd").read_text())
    body_defaults = read_exports((ROOT / "scripts" / "scav.gd").read_text())
    result = {}
    for scene in sorted(SCENES.glob("*.tscn")):
        text = scene.read_text()
        props = scene_props(text, "loot_container.gd")
        if props is not None:
            merged = {**container_defaults, **props}
            if merged.get("loot_table"):
                noise = float(merged.get("noise_radius", 0) or 0)
                result[merged["loot_table"]] = (merged["min_items"], merged["max_items"], False, noise > 0)
            continue
        props = scene_props(text, "scav.gd")
        if props is not None:
            merged = {**body_defaults, **props}
            result[merged["loot_table"]] = (merged["min_drops"], merged["max_drops"], True, False)
    return result


def stack_rolls(text):
    """{item id: (min, max)} from ItemDB.roll_count's match block."""
    block = re.search(r"static func roll_count\(.*?\n\n\n", text, re.S).group(0)
    return {item: (int(lo), int(hi)) for item, lo, hi in re.findall(r'"(\w+)":\s*\n\s*return randi_range\((\d+), (\d+)\)', block)}


def span(lo, hi):
    return "%d" % lo if lo == hi else "%d–%d" % (lo, hi)


def money(value):
    return "${:,}".format(value)


def main():
    text = SOURCE.read_text()
    items = read_dict(text, "ITEMS")
    tables = read_dict(text, "LOOT_TABLES")

    lines = [
        "# Item List",
        "",
        "Every item in Bloxov. **Generated** from `scripts/item_db.gd` by `tools/gen_item_list.py`;",
        "edit the item database, then re-run the script (don't edit this file by hand).",
        "",
        "## Items",
        "",
        "| Item | Type | Rarity | Size | Stack | Value (each) | Notes |",
        "|---|---|---|---|---|---|---|",
    ]
    order = sorted(items, key=lambda i: (list(KIND_LABEL).index(items[i]["kind"]), RARITIES.index(items[i]["rarity"]), items[i]["value"]))
    for item_id in order:
        it = items[item_id]
        notes = []
        if it["kind"] == "heal":
            notes.append("heals %d over %.0f s" % (it["heal"], it["use_time"]))
        if it["kind"] == "ammo":
            notes.append("full stack %s" % money(it["value"] * it["stack"]))
        if it["kind"] == "weapon":
            notes.append("%s slot; %s; %d dmg, %d rpm, %d-round mag, %s" % (
                it["slot"], "full-auto" if it["auto"] else "semi-auto", it["damage"], it["rpm"], it["mag"], it["ammo"].replace("_", " ")))
        if it["kind"] == "armor":
            notes.append("-%d%% damage taken" % round(it["reduction"] * 100))
        if it["kind"] == "backpack":
            notes.append("%d×%d storage" % tuple(it["grid"]))
        lines.append("| %s (`%s`) | %s | %s | %d×%d | %d | %s | %s |" % (
            it["name"], item_id, KIND_LABEL[it["kind"]], it["rarity"].capitalize(), it["w"], it["h"],
            it["stack"], money(it["value"]), "; ".join(notes)))

    counts = stack_rolls(text)
    stack_note = "A roll gives one item, except these come as a stack: %s." % ", ".join(
        "%s %s" % (items[i]["name"], span(*counts[i])) for i in counts)
    lines += ["", "## Where items come from", "",
              "Each container rolls a number of times; each roll picks from its table by weight.",
              "A rarity entry (e.g. *rare*) means a random **valuable** of that rarity.",
              stack_note, ""]
    rolls = {}
    for table, (lo, hi, body, loud) in roll_counts().items():
        rolls[table] = ("body bag, " if body else "") + "%s rolls" % span(lo, hi) + (", loud to open" if loud else "")
    titles = {"raider": "Raider"}
    for table, weights in tables.items():
        total = sum(weights.values())
        lines.append("### %s (%s)" % (titles.get(table, table.capitalize()), rolls.get(table, "")))
        lines.append("")
        lines.append("| Entry | Chance per roll |")
        lines.append("|---|---|")
        for key, weight in sorted(weights.items(), key=lambda kv: -kv[1]):
            if key in items:
                label = items[key]["name"]
            else:
                names = [items[i]["name"] for i in items if items[i]["kind"] == "valuable" and items[i]["rarity"] == key]
                label = "%s valuable (%s)" % (key.capitalize(), ", ".join(names))
            lines.append("| %s | %.0f%% |" % (label, 100.0 * weight / total))
        lines.append("")

    OUT.write_text("\n".join(lines).rstrip() + "\n")
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
