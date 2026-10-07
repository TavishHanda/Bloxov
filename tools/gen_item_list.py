"""Writes docs/ITEMS.md from the item database in scripts/item_db.gd.

Run from the repo root after changing items or loot tables:  python3 tools/gen_item_list.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "item_db.gd"
OUT = ROOT / "docs" / "ITEMS.md"
RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]
KIND_LABEL = {"weapon": "Weapon", "armor": "Armor", "backpack": "Backpack", "ammo": "Ammo", "heal": "Healing", "valuable": "Valuable"}


def read_dict(text, name):
    """Parses a `const NAME := { ... }` block (GDScript dict literals are JSON-like here)."""
    block = re.search(r"const %s := (\{.*?\n\})" % name, text, re.S).group(1)
    block = re.sub(r",(\s*[}\]])", r"\1", block)  # trailing commas
    return json.loads(block)


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

    lines += ["", "## Where items come from", "",
              "Each container rolls a number of times; each roll picks from its table by weight.",
              "A rarity entry (e.g. *rare*) means a random **valuable** of that rarity.",
              "Ammo rolls come as a stack of 20–60 rifle rounds (15–40 pistol), bandages as 1–2.", ""]
    rolls = {"crate": "1–3 rolls", "locker": "2–4 rolls", "safe": "1–2 rolls, loud to open",
             "scav": "body bag, 1–3 rolls", "pmc": "body bag, 1–3 rolls"}
    titles = {"pmc": "PMC"}
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
