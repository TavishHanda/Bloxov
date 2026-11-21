class_name PlayableModels
## The six characters' own models (0.39, owner 2026-11-20: every PMC is one of the six). Each model
## (assets/models/characters/<id>.glb, art_source/scripts/make_character.py) has the PMC's body and joints, and every
## outfit slot's options are the character's skins: a skin is the whole outfit. Looks only: never on the server's
## gameplay, never synced beyond the look tag (Characters.net_tag).

const PIXEL_MODEL_SCRIPT := preload("res://scripts/pixel_model.gd")

static var _scenes := {}


static func scene(id: String) -> PackedScene:
	if not Characters.LIST.has(id):
		id = "vega"
	if not _scenes.has(id):
		_scenes[id] = load("res://assets/models/characters/%s.glb" % id)
	return _scenes[id]


## A character's model in `skin`, not yet in the tree.
static func make(id: String, skin: String) -> PixelModel:
	var model := scene(id).instantiate()
	model.set_script(PIXEL_MODEL_SCRIPT)
	(model as PixelModel).randomize_outfit = false
	dress(model as PixelModel, Characters.skin_or_default(id, skin))
	return model as PixelModel


## Shows `skin` in every slot.
static func dress(model: PixelModel, skin: String) -> void:
	var choices := {}
	for slot: String in model.outfit_slots():
		choices[slot] = skin
	model.pick_outfit(choices)


## Swaps `owner`'s "Model" child (a PMC model) for character `id` in `skin`, in the same place. Call before `owner`
## is ready, so its @onready model points at the new one.
static func replace(owner: Node, id: String, skin: String) -> PixelModel:
	var old := owner.get_node_or_null("Model") as Node3D
	var model := make(id, skin)
	if old != null:
		model.transform = old.transform
		var at := old.get_index()
		owner.remove_child(old)
		old.free()
		model.name = "Model"
		owner.add_child(model)
		owner.move_child(model, at)
	else:
		model.name = "Model"
		owner.add_child(model)
	return model


## The sleeves and gloves for this device's first-person hands (GunViewModels.wear): the character's own, per skin
## (0.38.14, owner: the hands match your character; assets/models/hands/outfit/<sleeve|glove>-<id>-<skin>.png,
## art_source/scripts/make_hand_skins.py).
static func hands_look(state: Dictionary) -> Dictionary:
	var id := str(state.get("selected", "vega"))
	if not Characters.LIST.has(id):
		id = "vega"
	var tag := "%s-%s" % [id, Characters.skin_of(state, id)]
	return {"Top": tag, "Gloves": tag, "character": true}
