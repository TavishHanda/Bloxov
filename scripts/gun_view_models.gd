class_name GunViewModels
extends RefCounted
## The first-person gun models (0.18.1): the same .glb models other players and the AI hold (HeldGun,
## art_source/scripts/make_gun.py), one per view model key. The rifle and pistol go into the Model and PistolModel nodes
## of player.tscn, the others into new nodes built here; each has a "Muzzle" marker with the muzzle flash (copied from
## the rifle's), moved onto the model's own muzzle.

## Turned a little at the hip so its side shows (the shotgun's pump), straight when aimed.
const REST_TURN := {"shotgun": Vector3(0.0, 0.35, 0.12)}
## Where each model sits at rest, and when aimed (centred; the height comes from the model's iron sights, see
## aim_height()). The rifle's and pistol's rest places are their nodes' in player.tscn.
const REST := {"smg": Vector3(0.2, -0.19, -0.38), "shotgun": Vector3(0.22, -0.2, -0.42), "sniper": Vector3(0.22, -0.2, -0.44)}
const ADS := {"smg": Vector3(0, -0.086, -0.32), "shotgun": Vector3(0, -0.072, -0.38), "sniper": Vector3(0, -0.084, -0.4)}
## View model key -> the weapon whose model it shows (HeldGun.MODELS).
const WEAPONS := {"rifle": "ak", "pistol": "pistol", "smg": "smg", "shotgun": "shotgun", "sniper": "sniper"}
## Aimed, the sight line sits this far under the middle of the screen.
const SIGHT_MARGIN := 0.003


## Puts the gun models into `gun` (the Gun node). Returns {key: model} for the models it adds.
static func build_all(gun: Node3D) -> Dictionary:
	var flash := gun.get_node("Model/Muzzle/Flash") as Node3D
	var holders := {"rifle": gun.get_node("Model"), "pistol": gun.get_node("PistolModel")}
	var models := {}
	for key: String in REST:
		var holder := Node3D.new()
		holder.name = key.capitalize() + "Model"
		holder.position = REST[key]
		holder.visible = false
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		holder.add_child(muzzle)
		muzzle.add_child(flash.duplicate())
		gun.add_child(holder)
		holders[key] = holder
		models[key] = holder
	for key: String in holders:
		var holder: Node3D = holders[key]
		var art := HeldGun.instance(WEAPONS[key])
		art.name = "Art"
		holder.add_child(art)
		for mesh: GeometryInstance3D in art.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(holder.get_node("Muzzle") as Node3D).position = (art.get_node("Muzzle") as Node3D).position
	return models


## How high the model's iron sights are (aiming puts them just under the middle of the screen).
static func sight_height(model: Node3D) -> float:
	return (model.get_node("Art/Sight") as Node3D).position.y


## Where model `model` sits when aimed, from `ads` (its centred place) and its sights.
static func aim_place(model: Node3D, ads: Vector3) -> Vector3:
	return Vector3(ads.x, -sight_height(model) - SIGHT_MARGIN, ads.z)


# --- Attachments on the gun (0.15.6; models 0.18.1) ----------------------------------

## Shows `attachments` (slot -> id) on first-person `model`: their models (assets/models/guns/att_<id>.glb) under an
## "Attachments" node, the mag stretched for an extended mag, the muzzle moved out past a barrel part. `muzzle_rest` is
## where the muzzle sits bare. Returns how far the optic raises the sight line (aiming lowers the gun by that much).
static func dress(model: Node3D, _key: String, attachments: Dictionary, muzzle_rest: Vector3) -> float:
	var old := model.get_node_or_null("Attachments")
	if old != null:
		model.remove_child(old)
		old.free()
	var holder := Node3D.new()
	holder.name = "Attachments"
	model.add_child(holder)
	var art := model.get_node("Art") as Node3D
	var muzzle := model.get_node("Muzzle") as Node3D
	muzzle.position = muzzle_rest
	var mag := art.get_node_or_null("Mag") as Node3D
	if mag != null:
		mag.scale = Vector3(1, 1.5 if attachments.values().has("ext_mag") else 1.0, 1)
	var raise := 0.0
	for slot: String in attachments:
		var path := "res://assets/models/guns/att_%s.glb" % attachments[slot]
		var mount := art.get_node_or_null({"scope": "Optic", "sight": "Optic", "grip": "Fore"}.get(slot, "Muzzle")) as Node3D
		if mount == null or not ResourceLoader.exists(path):
			continue
		var part: Node3D = (load(path) as PackedScene).instantiate()
		PixelModel.make_crisp(part)
		for mesh: GeometryInstance3D in part.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(part)
		part.position = mount.position
		match slot:
			"scope", "sight":
				raise = mount.position.y + (part.get_node("Line") as Node3D).position.y - sight_height(model)
			"barrel":
				part.position = muzzle_rest
				var end := part.get_node_or_null("End") as Node3D
				if end != null:
					muzzle.position = muzzle_rest + end.position
	return raise
