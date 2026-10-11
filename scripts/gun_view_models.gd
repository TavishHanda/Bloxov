class_name GunViewModels
extends RefCounted
## Placeholder first-person models for the Guns update's new guns (0.15.4), built from boxes in the same style as
## the AK and pistol in player.tscn (dark body, orange accents). Mechanics only for now (owner): the art pass swaps
## real models in. Each model has a "Muzzle" marker with the muzzle flash (copied from the AK's) like the others.

## Where each model sits at rest, and when aimed (its sight just under the middle of the screen).
const REST := {"smg": Vector3(0.2, -0.19, -0.38), "shotgun": Vector3(0.22, -0.2, -0.42), "sniper": Vector3(0.22, -0.2, -0.44)}
const ADS := {"smg": Vector3(0, -0.086, -0.32), "shotgun": Vector3(0, -0.066, -0.38), "sniper": Vector3(0, -0.084, -0.4)}

## Boxes: [size, position, accent?]. Muzzle: where shots and the flash come out.
const PARTS := {
	"smg": {
		"boxes": [
			[Vector3(0.07, 0.09, 0.26), Vector3.ZERO, false],             # body
			[Vector3(0.035, 0.035, 0.12), Vector3(0, 0.01, -0.18), false],  # barrel
			[Vector3(0.04, 0.16, 0.05), Vector3(0, -0.12, -0.04), false],   # long straight mag
			[Vector3(0.04, 0.07, 0.14), Vector3(0, -0.01, 0.19), true],     # stock
			[Vector3(0.025, 0.035, 0.05), Vector3(0, 0.06, 0.02), false],   # rear sight
		],
		"muzzle": Vector3(0, 0.01, -0.25),
	},
	"shotgun": {
		"boxes": [
			[Vector3(0.075, 0.09, 0.3), Vector3.ZERO, false],               # receiver
			[Vector3(0.045, 0.045, 0.42), Vector3(0, 0.015, -0.33), false],  # barrel
			[Vector3(0.06, 0.05, 0.14), Vector3(0, -0.035, -0.28), true],    # pump
			[Vector3(0.06, 0.1, 0.18), Vector3(0, -0.02, 0.23), true],       # stock
			[Vector3(0.015, 0.02, 0.02), Vector3(0, 0.05, -0.52), false],    # bead sight
		],
		"muzzle": Vector3(0, 0.015, -0.55),
	},
	"sniper": {
		"boxes": [
			[Vector3(0.07, 0.09, 0.34), Vector3.ZERO, false],               # receiver
			[Vector3(0.03, 0.03, 0.5), Vector3(0, 0.01, -0.42), false],      # long barrel
			[Vector3(0.065, 0.11, 0.22), Vector3(0, -0.02, 0.27), true],     # stock
			[Vector3(0.045, 0.06, 0.06), Vector3(0, -0.07, -0.03), false],   # small mag
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
			mesh.name = "Part%d" % i
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
