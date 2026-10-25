class_name Operators
## Your character (0.21.6, owner picked "both" for the wardrobe: pick an operator, then change any part). An operator is
## a ready-made look for the PMC model; CUSTOMIZE changes single parts. Looks only: nothing here changes how you play.
## Online, your look goes to the others in your raid (as text, `to_text`), so they see your character.
## The names are placeholders until the owner names them.

## The PMC model's outfit parts and their options (assets/models/characters/pmc.glb, "Slot__option" nodes; the smoke
## test checks this matches the model). In the order the wardrobe lists them.
const SLOTS := {
	"Head": ["pale", "pale_beard", "tan", "dark", "dark_beard"],
	"Hat": ["helmet_green", "helmet_tan", "helmet_black", "cap_headset"],
	"Eyes": ["none", "glasses"],
	"Mask": ["none", "gaiter_green", "gaiter_tan", "gaiter_black"],
	"Top": ["green", "tan", "multicam", "black"],
	"Vest": ["green", "tan", "black"],
	"Pants": ["green", "tan", "multicam", "black"],
	"Gloves": ["green", "tan", "black"],
	"Boots": ["coyote", "tan", "black"],
}
## What the wardrobe calls each part.
const SLOT_NAMES := {"Head": "FACE", "Hat": "HEADGEAR", "Eyes": "EYEWEAR", "Mask": "MASK", "Top": "JACKET", "Vest": "VEST",
	"Pants": "TROUSERS", "Gloves": "GLOVES", "Boots": "BOOTS"}

const LIST := [
	{"id": "rook", "name": "Rook", "look": {"Head": "pale", "Hat": "helmet_green", "Eyes": "none", "Mask": "none", "Top": "green",
		"Vest": "green", "Pants": "green", "Gloves": "black", "Boots": "black"}},
	{"id": "dune", "name": "Dune", "look": {"Head": "tan", "Hat": "helmet_tan", "Eyes": "glasses", "Mask": "gaiter_tan", "Top": "tan",
		"Vest": "tan", "Pants": "tan", "Gloves": "tan", "Boots": "coyote"}},
	{"id": "ghost", "name": "Ghost", "look": {"Head": "pale_beard", "Hat": "helmet_black", "Eyes": "glasses", "Mask": "gaiter_black",
		"Top": "black", "Vest": "black", "Pants": "black", "Gloves": "black", "Boots": "black"}},
	{"id": "viper", "name": "Viper", "look": {"Head": "dark", "Hat": "cap_headset", "Eyes": "none", "Mask": "none", "Top": "multicam",
		"Vest": "green", "Pants": "multicam", "Gloves": "green", "Boots": "coyote"}},
	{"id": "bishop", "name": "Bishop", "look": {"Head": "dark_beard", "Hat": "helmet_green", "Eyes": "none", "Mask": "gaiter_green",
		"Top": "multicam", "Vest": "tan", "Pants": "green", "Gloves": "tan", "Boots": "tan"}},
	{"id": "hawk", "name": "Hawk", "look": {"Head": "tan", "Hat": "cap_headset", "Eyes": "glasses", "Mask": "gaiter_black", "Top": "black",
		"Vest": "tan", "Pants": "multicam", "Gloves": "black", "Boots": "coyote"}},
]


static func by_id(id: String) -> Dictionary:
	for entry: Dictionary in LIST:
		if entry["id"] == id:
			return entry
	return LIST[0]


## A full, valid look from anything (a save, the network): unknown parts or options fall back to the first operator's.
static func clean(look) -> Dictionary:
	var base: Dictionary = LIST[0]["look"]
	var out := {}
	for slot: String in SLOTS:
		var pick = look.get(slot) if look is Dictionary else null
		out[slot] = pick if pick is String and (SLOTS[slot] as Array).has(pick) else base[slot]
	return out


## The operator a look is, or "" if it's been changed from all of them (custom).
static func matching(look: Dictionary) -> String:
	for entry: Dictionary in LIST:
		if entry["look"] == clean(look):
			return entry["id"]
	return ""


## Short text for the network: one option index per slot, e.g. "01203110".
static func to_text(look: Dictionary) -> String:
	var clean_look := clean(look)
	var text := ""
	for slot: String in SLOTS:
		text += str((SLOTS[slot] as Array).find(clean_look[slot]))
	return text


static func from_text(text: String) -> Dictionary:
	var look := {}
	var i := 0
	for slot: String in SLOTS:
		var options: Array = SLOTS[slot]
		if i < text.length() and text[i].is_valid_int() and int(text[i]) < options.size():
			look[slot] = options[int(text[i])]
		i += 1
	return clean(look)
