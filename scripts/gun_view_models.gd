class_name GunViewModels
extends RefCounted
## Placeholder first-person models for the Guns update's new guns (0.15.4), built from boxes in the same style as
## the AK and pistol in player.tscn (dark body, orange accents). Mechanics only for now (owner): the art pass swaps
## real models in. Each model has a "Muzzle" marker with the muzzle flash (copied from the AK's) like the others.

## Turned a little at the hip so its side shows (the shotgun's pump), straight when aimed.
const REST_TURN := {"shotgun": Vector3(0.0, 0.35, 0.12)}
## Where each model sits at rest, and when aimed (its sight just under the middle of the screen).
const REST := {"smg": Vector3(0.2, -0.19, -0.38), "shotgun": Vector3(0.22, -0.2, -0.42), "sniper": Vector3(0.22, -0.2, -0.44)}
const ADS := {"smg": Vector3(0, -0.086, -0.32), "shotgun": Vector3(0, -0.072, -0.38), "sniper": Vector3(0, -0.084, -0.4)}

## Boxes: [size, position, accent?, optional name ("Mag": an extended mag stretches it)]. Muzzle: where shots
## and the flash come out.
const PARTS := {
	"smg": {
		"boxes": [
			[Vector3(0.07, 0.09, 0.26), Vector3.ZERO, false],             # body
			[Vector3(0.035, 0.035, 0.12), Vector3(0, 0.01, -0.18), false],  # barrel
			[Vector3(0.04, 0.16, 0.05), Vector3(0, -0.12, -0.04), false, "Mag"],   # long straight mag
			[Vector3(0.04, 0.07, 0.14), Vector3(0, -0.01, 0.19), true],     # stock
			[Vector3(0.025, 0.035, 0.05), Vector3(0, 0.06, 0.02), false],   # rear sight
		],
		"muzzle": Vector3(0, 0.01, -0.25),
	},
	"shotgun": {
		# Pump shotgun: a fat barrel with the shell tube under it, a chunky pump around the tube, a stubby
		# receiver with no box mag, a pistol grip and a wide stock (owner: the first one didn't read as a shotgun).
		"boxes": [
			[Vector3(0.07, 0.1, 0.2), Vector3(0, 0, 0.02), false],             # receiver
			[Vector3(0.05, 0.05, 0.5), Vector3(0, 0.025, -0.33), false],      # barrel
			[Vector3(0.042, 0.042, 0.42), Vector3(0, -0.028, -0.29), false],  # shell tube under the barrel
			[Vector3(0.085, 0.072, 0.16), Vector3(0, -0.03, -0.27), true],    # pump
			[Vector3(0.088, 0.075, 0.012), Vector3(0, -0.03, -0.23), false],  # pump grooves
			[Vector3(0.088, 0.075, 0.012), Vector3(0, -0.03, -0.27), false],
			[Vector3(0.088, 0.075, 0.012), Vector3(0, -0.03, -0.31), false],
			[Vector3(0.045, 0.1, 0.05), Vector3(0, -0.08, 0.09), false],      # pistol grip
			[Vector3(0.065, 0.11, 0.2), Vector3(0, -0.03, 0.22), true],       # stock
			[Vector3(0.018, 0.02, 0.02), Vector3(0, 0.06, -0.56), true],      # bead sight
		],
		"muzzle": Vector3(0, 0.025, -0.59),
	},
	"sniper": {
		"boxes": [
			[Vector3(0.07, 0.09, 0.34), Vector3.ZERO, false],               # receiver
			[Vector3(0.03, 0.03, 0.5), Vector3(0, 0.01, -0.42), false],      # long barrel
			[Vector3(0.065, 0.11, 0.22), Vector3(0, -0.02, 0.27), true],     # stock
			[Vector3(0.045, 0.06, 0.06), Vector3(0, -0.07, -0.03), false, "Mag"],   # small mag
			[Vector3(0.06, 0.02, 0.02), Vector3(0.05, 0.02, 0.08), true],    # bolt handle
			[Vector3(0.02, 0.03, 0.03), Vector3(0, 0.06, 0.02), false],      # rear sight
		],
		"muzzle": Vector3(0, 0.01, -0.68),
	},
}


## Builds the models into `gun` (the Gun node) next to the AK's `Model`, whose materials and flash it copies.
## Returns {key: model}.
static func build_all(gun: Node3D) -> Dictionary:
	var rifle := gun.get_node("Model") as Node3D
	var dark := (rifle.get_node("Receiver") as MeshInstance3D).mesh.surface_get_material(0)
	var accent := (rifle.get_node("Stock") as MeshInstance3D).mesh.surface_get_material(0)
	var flash := rifle.get_node("Muzzle/Flash") as Node3D
	var models := {}
	for key: String in PARTS:
		var model := Node3D.new()
		model.name = key.capitalize() + "Model"
		model.position = REST[key]
		model.visible = false
		var i := 0
		for part: Array in PARTS[key]["boxes"]:
			var box := BoxMesh.new()
			box.size = part[0]
			box.material = accent if part[2] else dark
			var mesh := MeshInstance3D.new()
			mesh.name = part[3] if part.size() > 3 else "Part%d" % i
			mesh.mesh = box
			mesh.position = part[1]
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			model.add_child(mesh)
			i += 1
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = PARTS[key]["muzzle"]
		model.add_child(muzzle)
		muzzle.add_child(flash.duplicate())
		gun.add_child(model)
		models[key] = model
	return models


# --- Attachments on the gun (0.15.6) -------------------------------------------------

## Per model (the AK's and pistol's from player.tscn too): where an optic sits ([top of the gun, z]), and where a
## grip goes under the barrel.
const MOUNTS := {
	"rifle": {"top": Vector2(0.09, -0.02), "grip": Vector3(0, -0.075, -0.22)},
	"pistol": {"top": Vector2(0.03, -0.01), "grip": Vector3.ZERO},
	"smg": {"top": Vector2(0.0775, 0.0), "grip": Vector3(0, -0.06, -0.16)},
	"shotgun": {"top": Vector2(0.05, 0.02), "grip": Vector3(0, -0.085, -0.2)},
	"sniper": {"top": Vector2(0.075, -0.02), "grip": Vector3(0, -0.055, -0.3)},
}
## Placeholder looks: [size, accent?]. Optics sit on top, barrel parts on the muzzle (moving it forward by their
## length), the grip under the barrel.
const LOOKS := {
	"red_dot": [Vector3(0.03, 0.035, 0.05), false],
	"scope_4x": [Vector3(0.045, 0.05, 0.2), false],
	"scope_8x": [Vector3(0.05, 0.055, 0.28), false],
	"suppressor": [Vector3(0.045, 0.045, 0.16), false],
	"choke": [Vector3(0.06, 0.06, 0.05), true],
	"foregrip": [Vector3(0.035, 0.08, 0.04), true],
}


## Shows `attachments` (slot -> id) on first-person `model` (key `key`): boxes under an "Attachments" node, the
## mag stretched for an extended mag, the muzzle moved out past a barrel part. `muzzle_rest` is where the muzzle
## sits bare. Returns how far the optic raises the sight line (aiming lowers the gun by that much).
static func dress(model: Node3D, key: String, attachments: Dictionary, muzzle_rest: Vector3) -> float:
	var old := model.get_node_or_null("Attachments")
	if old != null:
		model.remove_child(old)
		old.free()
	var holder := Node3D.new()
	holder.name = "Attachments"
	model.add_child(holder)
	var muzzle := model.get_node("Muzzle") as Node3D
	muzzle.position = muzzle_rest
	var mag := model.get_node_or_null("Mag") as Node3D
	if mag != null:
		mag.scale = Vector3(1, 1.5 if attachments.values().has("ext_mag") else 1.0, 1)
	var raise := 0.0
	var mount: Dictionary = MOUNTS.get(key, MOUNTS["rifle"])
	var dark := (model.get_child(0) as MeshInstance3D).mesh.surface_get_material(0)
	for slot: String in attachments:
		var id: String = attachments[slot]
		if not LOOKS.has(id):
			continue
		var size: Vector3 = LOOKS[id][0]
		var box := BoxMesh.new()
		box.size = size
		box.material = dark
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match slot:
			"scope", "sight":
				var top: Vector2 = mount["top"]
				mesh.position = Vector3(0, top.x + size.y * 0.5, top.y)
				raise = size.y
			"barrel":
				mesh.position = muzzle_rest + Vector3(0, 0, -size.z * 0.5)
				muzzle.position = muzzle_rest + Vector3(0, 0, -size.z)
			"grip":
				mesh.position = mount["grip"]
		if LOOKS[id][1]:
			var accent := StandardMaterial3D.new()
			accent.albedo_color = Color(0.95, 0.55, 0.15)
			box.material = accent
		holder.add_child(mesh)
	return raise
