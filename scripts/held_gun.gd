class_name HeldGun
extends RefCounted
## The gun a character model holds in third person, kept apart from the model (0.15.0): character models come with
## a gun drawn in (a "Gun" node with a "Muzzle" empty, see art_source/scripts/make_character.py), and this swaps it
## for the model of the gun the character actually carries. Until the art pass makes real gun models, the only one
## is the AK drawn into the scav model (the Raider's drawn-in RPK is gone: owner, 0.15.0, "I don't want an rpk").
## The art pass adds entries to MODELS (or separate .glb guns) and nothing else has to change.

## Gun model key -> [scene, path of the gun node inside it].
const MODELS := {
	"ak": ["res://assets/models/characters/scav.glb", "Gun"],
}


## Replaces the "Gun" node of `model` with gun model `key` (same place, same name, so `$Model/Gun/Muzzle` still
## works). Returns the new gun node, or the old one when there's nothing to swap.
static func show(model: Node3D, key: String) -> Node3D:
	var old := model.get_node_or_null("Gun") as Node3D
	if old == null or not MODELS.has(key):
		return old
	var source: Node = (load(MODELS[key][0]) as PackedScene).instantiate()
	var gun := source.get_node(MODELS[key][1] as String) as Node3D
	source.remove_child(gun)
	source.free()
	gun.owner = null
	gun.transform = old.transform
	model.remove_child(old)
	old.free()
	gun.name = "Gun"
	model.add_child(gun)
	PixelModel.make_crisp(gun)
	return gun

