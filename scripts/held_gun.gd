class_name HeldGun
extends RefCounted
## The gun a character model holds in third person, kept apart from the model (0.15.0): character models come with
## a gun drawn in (a "Gun" node with a "Muzzle" empty, see art_source/scripts/make_character.py), and this swaps it
## for the model of the gun the character actually carries. The gun models (0.18.1) are separate .glb files made by
## art_source/scripts/make_gun.py; first person uses the same ones (GunViewModels).

## Weapon item id -> its model, assets/models/guns/<name>.glb.
const MODELS := {"ak": "hound", "pistol": "stinger", "smg": "wasp", "shotgun": "mauler", "sniper": "lancer"}


## A new instance of weapon `id`'s model (nodes Body, Mag, Muzzle, Grip, Sight, Optic, Fore: see make_gun.py).
static func instance(id: String) -> Node3D:
	var art: Node3D = (load("res://assets/models/guns/%s.glb" % MODELS[id]) as PackedScene).instantiate()
	PixelModel.make_crisp(art)
	return art


## Replaces the "Gun" node of `model` with weapon `key`'s model (same place, same name, held by its grip, with a
## "Muzzle" node at its muzzle, so `$Model/Gun/Muzzle` still works). Returns the new gun node, or the old one when
## there's nothing to swap.
static func show(model: Node3D, key: String) -> Node3D:
	var old := model.get_node_or_null("Gun") as Node3D
	if old == null or not MODELS.has(key) or old.get_meta("gun", "") == key:
		return old
	var gun := Node3D.new()
	gun.transform = old.transform
	gun.visible = old.visible
	gun.set_meta("gun", key)
	model.remove_child(old)
	old.free()
	gun.name = "Gun"
	model.add_child(gun)
	var art := instance(key)
	art.name = "Art"
	art.position = -(art.get_node("Grip") as Node3D).position
	gun.add_child(art)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = art.position + (art.get_node("Muzzle") as Node3D).position
	gun.add_child(muzzle)
	return gun
