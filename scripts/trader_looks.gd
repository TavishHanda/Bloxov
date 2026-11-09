class_name TraderLooks
## How each trader looks (lively hideout, owner 2026-11-09: proper, unique traders, several designs to pick from).
## Every look picks one option per slot of assets/models/characters/trader.glb (art_source/scripts/make_character.py
## build_trader). OPTIONS holds the designs on offer; PICKED is the one each trader wears in the hideout.

const SLOTS := ["Head", "Tash", "Hat", "Eyes", "Mask", "Top", "Vest", "Belly", "Pants", "Gloves", "Boots"]

const OPTIONS := {
	"guns": [
		{"name": "Workshop", "look": {"Head": "tan_beard", "Tash": "none", "Hat": "bandana", "Eyes": "goggles", "Mask": "none",
			"Top": "olive", "Vest": "apron", "Belly": "none", "Pants": "olive", "Gloves": "brown", "Boots": "brown"}},
		{"name": "Old soldier", "look": {"Head": "old_pale", "Tash": "none", "Hat": "beret", "Eyes": "patch", "Mask": "none",
			"Top": "woodland", "Vest": "bandolier", "Belly": "none", "Pants": "woodland", "Gloves": "none_pale", "Boots": "black"}},
		{"name": "Range master", "look": {"Head": "dark", "Tash": "none", "Hat": "ear_defenders", "Eyes": "shades", "Mask": "none",
			"Top": "olive", "Vest": "shooting", "Belly": "none", "Pants": "tan", "Gloves": "black", "Boots": "coyote"}},
	],
	"supplies": [
		{"name": "The boss", "look": {"Head": "pale_beard", "Tash": "none", "Hat": "flatcap", "Eyes": "none", "Mask": "none",
			"Top": "fur", "Vest": "chain", "Belly": "fur", "Pants": "black", "Gloves": "none_pale", "Boots": "black"}},
		{"name": "Quartermaster", "look": {"Head": "tan", "Tash": "moustache_dark", "Hat": "beanie", "Eyes": "none", "Mask": "none",
			"Top": "olive", "Vest": "none", "Belly": "olive", "Pants": "olive", "Gloves": "brown", "Boots": "brown"}},
		{"name": "Fixer", "look": {"Head": "dark_beard", "Tash": "none", "Hat": "none", "Eyes": "shades", "Mask": "none",
			"Top": "leather", "Vest": "chain_belly", "Belly": "leather", "Pants": "jeans", "Gloves": "none_dark", "Boots": "white"}},
	],
	"valuables": [
		{"name": "Jeweller", "look": {"Head": "old_tan", "Tash": "moustache_grey", "Hat": "none", "Eyes": "loupe", "Mask": "none",
			"Top": "white", "Vest": "waistcoat_black", "Belly": "none", "Pants": "black", "Gloves": "white", "Boots": "black"}},
		{"name": "Collector", "look": {"Head": "pale", "Tash": "none", "Hat": "fedora", "Eyes": "specs", "Mask": "none",
			"Top": "coat_dark", "Vest": "none", "Belly": "none", "Pants": "navy", "Gloves": "black", "Boots": "black"}},
		{"name": "Smuggler", "look": {"Head": "tan_beard", "Tash": "none", "Hat": "beanie", "Eyes": "none", "Mask": "none",
			"Top": "coat_dark", "Vest": "chain", "Belly": "none", "Pants": "black", "Gloves": "black", "Boots": "brown"}},
	],
	"ming": [
		{"name": "Dealer", "look": {"Head": "old_tan", "Tash": "none", "Hat": "visor", "Eyes": "none", "Mask": "none",
			"Top": "white_rolled", "Vest": "waistcoat_maroon", "Belly": "none", "Pants": "black", "Gloves": "none_tan", "Boots": "black"}},
		{"name": "Showman", "look": {"Head": "tan", "Tash": "moustache_dark", "Hat": "fedora", "Eyes": "none", "Mask": "none",
			"Top": "loud", "Vest": "none", "Belly": "none", "Pants": "black", "Gloves": "none_tan", "Boots": "white"}},
		{"name": "Bookie", "look": {"Head": "tan", "Tash": "none", "Hat": "flatcap", "Eyes": "shades", "Mask": "none",
			"Top": "track", "Vest": "chain", "Belly": "none", "Pants": "track", "Gloves": "none_tan", "Boots": "white"}},
	],
	"meds": [
		{"name": "Field doctor", "look": {"Head": "pale", "Tash": "none", "Hat": "head_torch", "Eyes": "specs", "Mask": "surgical",
			"Top": "coat_white", "Vest": "stethoscope", "Belly": "none", "Pants": "scrubs", "Gloves": "white", "Boots": "black"}},
		{"name": "Combat medic", "look": {"Head": "dark_beard", "Tash": "none", "Hat": "boonie", "Eyes": "none", "Mask": "none",
			"Top": "woodland", "Vest": "shooting", "Belly": "none", "Pants": "olive", "Gloves": "black", "Boots": "coyote"}},
		{"name": "Old doc", "look": {"Head": "old_pale", "Tash": "moustache_grey", "Hat": "none", "Eyes": "specs", "Mask": "none",
			"Top": "scrubs", "Vest": "stethoscope", "Belly": "none", "Pants": "scrubs", "Gloves": "none_pale", "Boots": "white"}},
	],
}

## Which design each trader wears (an index into OPTIONS). Owner, 2026-11-09: Ponta 2 (Old soldier), The Big Don 3
## (Fixer), Supreme 1 (Jeweller), Ming 2 (Showman), the Medic 3 (Old doc).
const PICKED := {"guns": 1, "supplies": 2, "valuables": 0, "ming": 1, "meds": 2}

## The crew living in the hideout (HideoutCrew): off duty, no helmets.
const CREW := {
	"sleeper": {"Head": "pale_beard", "Tash": "none", "Hat": "beanie", "Eyes": "none", "Mask": "none", "Top": "tee_grey",
		"Vest": "none", "Belly": "none", "Pants": "olive", "Gloves": "none_pale", "Boots": "black"},
	"cook": {"Head": "bald_dark", "Tash": "moustache_dark", "Hat": "none", "Eyes": "none", "Mask": "none", "Top": "tee_tan",
		"Vest": "apron_white", "Belly": "none", "Pants": "olive", "Gloves": "none_dark", "Boots": "brown"},
	"cards_a": {"Head": "tan", "Hat": "cap", "Tash": "none", "Eyes": "none", "Mask": "none", "Top": "woodland",
		"Vest": "none", "Belly": "none", "Pants": "tan", "Gloves": "none_tan", "Boots": "tan"},
	"cards_b": {"Head": "pale", "Hat": "bandana", "Tash": "none", "Eyes": "none", "Mask": "none", "Top": "tee_olive",
		"Vest": "none", "Belly": "none", "Pants": "woodland", "Gloves": "none_pale", "Boots": "black"},
	"mechanic": {"Head": "tan_beard", "Hat": "beanie", "Tash": "none", "Eyes": "goggles", "Mask": "none", "Top": "olive",
		"Vest": "none", "Belly": "none", "Pants": "olive", "Gloves": "black", "Boots": "brown"},
	"coffee": {"Head": "dark", "Hat": "cap", "Tash": "none", "Eyes": "none", "Mask": "none", "Top": "tee_olive",
		"Vest": "shooting", "Belly": "none", "Pants": "tan", "Gloves": "none_dark", "Boots": "tan"},
}


static func look(trader: String, design := -1) -> Dictionary:
	var options: Array = OPTIONS.get(trader, [])
	if options.is_empty():
		return {}
	var k: int = PICKED.get(trader, 0) if design < 0 else design
	return options[clampi(k, 0, options.size() - 1)]["look"]
