extends RefCounted
## Small 3D models of every item, for the inventory icons (tools/render_icons.gd). Guns and attachments use their real
## models (assets/models/guns); everything else is built here out of boxes, cylinders and spheres, blocky like the rest
## of Bloxov. Units are metres, roughly life size; the renderer fits each model to the item's grid size, so only the
## proportions matter. Long side along x, up is y, the camera looks from +z.
## No real brands or logos on anything (docs/STORE_RULES.md).

const GUNS := {"ak": "hound", "pistol": "stinger", "smg": "wasp", "shotgun": "mauler", "sniper": "lancer",
	"red_dot": "att_red_dot", "scope_4x": "att_scope_4x", "scope_8x": "att_scope_8x", "suppressor": "att_suppressor",
	"choke": "att_choke", "foregrip": "att_foregrip"}
## Items shown with a model from the game itself (0.19.8, owner: the medium backpack is the green one scavs wear),
## and how it's turned (degrees) to face the camera.
const MODELS := {"backpack_medium": ["res://assets/models/characters/scav_backpack.glb", Vector3(0, 180, 0)]}

const C := {
	"olive": Color("5b6236"), "olive_dk": Color("3e4426"), "olive_lt": Color("78804a"), "tan": Color("9a855c"),
	"tan_dk": Color("7c6a48"), "brass": Color("c09a45"), "copper": Color("b8693a"), "steel": Color("8a9096"),
	"steel_dk": Color("4d5257"), "steel_lt": Color("b9bec2"), "iron": Color("34383c"), "black": Color("1d1f22"),
	"white": Color("e4e1d6"), "bone": Color("cfc6a8"), "red": Color("a8332a"), "red_dk": Color("6e2019"),
	"green": Color("2f6b3a"), "green_lt": Color("55b04a"), "blue": Color("2f5d8c"), "blue_lt": Color("6aa0d0"),
	"navy": Color("23324d"), "gold": Color("e0b335"), "gold_dk": Color("a77d1e"), "orange": Color("d07a2a"),
	"brown": Color("6b4a2e"), "brown_dk": Color("4a321f"), "paper": Color("ddd5bb"), "rust": Color("8a4a2a"),
	"purple": Color("9b5fd6"), "cyan": Color("8fe3ef"), "grey": Color("6e7175"), "yellow": Color("d9c23a"),
	"pcb": Color("2e6a3c"), "glass": Color("9fd0e6"),
}


## The model for item `id`, or null if it has none.
static func build(id: String) -> Node3D:
	if GUNS.has(id):
		var scene := load("res://assets/models/guns/%s.glb" % GUNS[id]) as PackedScene
		var gun := scene.instantiate() as Node3D
		var holder := Node3D.new()
		gun.rotation_degrees.y = -90.0          # muzzle to the right
		holder.add_child(gun)
		return holder
	if MODELS.has(id):
		var model := (load(MODELS[id][0]) as PackedScene).instantiate() as Node3D
		model.rotation_degrees = MODELS[id][1]
		var base := Node3D.new()
		base.add_child(model)
		return base
	var m := Node3D.new()
	match id:
		"rifle_ammo": _ammo(m, "olive", "brass", 0.039, 0.0040, 5, "copper")
		"pistol_ammo": _ammo(m, "tan", "brass", 0.019, 0.0045, 6, "copper")
		"smg_ammo": _ammo(m, "steel_dk", "brass", 0.022, 0.0042, 6, "steel_lt")
		"shells": _shells(m)
		"sniper_ammo": _ammo(m, "navy", "brass", 0.07, 0.0055, 4, "copper")
		"ext_mag":
			box(m, Vector3(0.045, 0.24, 0.024), Vector3(0, 0, 0), "black", Vector3(0, 0, 12))
			box(m, Vector3(0.05, 0.03, 0.028), Vector3(0.025, -0.12, 0), "steel_dk", Vector3(0, 0, 12))
			box(m, Vector3(0.03, 0.012, 0.012), Vector3(-0.022, 0.123, 0), "brass", Vector3(0, 0, 12))
		"armor_light": _vest(m, "olive", "olive_dk", false)
		"armor_heavy": _vest(m, "steel_dk", "black", true)
		"helmet_basic": _helmet(m, "olive", "olive_dk", false)
		"helmet_good": _helmet(m, "olive_dk", "black", true)
		"backpack_small": _pack(m, Vector3(0.3, 0.36, 0.14), "blue", "navy", false)
		"backpack_large": _pack(m, Vector3(0.44, 0.5, 0.22), "olive", "olive_dk", true)
		"grenade":
			sphere(m, 0.032, Vector3(0, -0.01, 0), "olive", Vector3(1, 1.15, 1))
			cyl(m, 0.014, 0.025, Vector3(0, 0.035, 0), "steel_dk")
			box(m, Vector3(0.01, 0.06, 0.012), Vector3(0.022, 0.01, 0.0), "steel", Vector3(0, 0, -12))
			torus(m, 0.008, 0.013, Vector3(-0.02, 0.05, 0.0), "steel_lt", Vector3(90, 0, 0))
		"energy_drink":
			cyl(m, 0.033, 0.155, Vector3.ZERO, "green_lt")
			cyl(m, 0.0335, 0.05, Vector3(0, 0.0, 0), "black")
			cyl(m, 0.029, 0.008, Vector3(0, 0.081, 0), "steel_lt")
			box(m, Vector3(0.03, 0.03, 0.01), Vector3(0, 0.0, 0.033), "yellow", Vector3(0, 0, 45))
		"bandage":
			cyl(m, 0.04, 0.07, Vector3(-0.02, 0, 0), "white", Vector3(0, 0, 90))
			cyl(m, 0.012, 0.072, Vector3(-0.02, 0, 0), "bone", Vector3(0, 0, 90))
			box(m, Vector3(0.07, 0.003, 0.06), Vector3(0.045, -0.038, 0.0), "white")
		"medkit":
			box(m, Vector3(0.3, 0.16, 0.09), Vector3.ZERO, "red")
			box(m, Vector3(0.3, 0.02, 0.092), Vector3(0, 0.04, 0), "red_dk")
			box(m, Vector3(0.09, 0.025, 0.01), Vector3(0, -0.01, 0.046), "white")
			box(m, Vector3(0.025, 0.09, 0.01), Vector3(0, -0.01, 0.046), "white")
			box(m, Vector3(0.08, 0.02, 0.02), Vector3(0, 0.09, 0), "black")
		"bunker_key": _key(m, "iron", 1.0)
		"bank_vault_key": _key(m, "brass", 1.25)
		"beans": _can(m, 0.04, 0.11, "orange", "steel_lt")
		"water":
			cyl(m, 0.035, 0.2, Vector3.ZERO, "glass", Vector3.ZERO, 0.0, 0.55)
			cyl(m, 0.0355, 0.06, Vector3(0, -0.01, 0), "blue")
			cyl(m, 0.016, 0.03, Vector3(0, 0.11, 0), "glass", Vector3.ZERO, 0.0, 0.55)
			cyl(m, 0.017, 0.016, Vector3(0, 0.13, 0), "blue_lt")
		"ration":
			box(m, Vector3(0.14, 0.2, 0.035), Vector3.ZERO, "tan_dk")
			box(m, Vector3(0.14, 0.03, 0.03), Vector3(0, 0.105, 0), "tan")
			box(m, Vector3(0.1, 0.05, 0.01), Vector3(0, 0.0, 0.018), "bone")
			box(m, Vector3(0.06, 0.008, 0.012), Vector3(0, 0.0, 0.019), "black")
		"duct_tape":
			cyl(m, 0.055, 0.048, Vector3.ZERO, "steel", Vector3(90, 0, 0), 0.0, 1.0, 20)
			cyl(m, 0.032, 0.05, Vector3.ZERO, "tan", Vector3(90, 0, 0), 0.0, 1.0, 20)
			cyl(m, 0.027, 0.052, Vector3.ZERO, "black", Vector3(90, 0, 0), 0.0, 1.0, 20)
			box(m, Vector3(0.05, 0.002, 0.048), Vector3(0.045, -0.05, 0), "steel", Vector3(0, 0, -10))
		"scrap":
			box(m, Vector3(0.3, 0.012, 0.12), Vector3(-0.05, 0.0, 0), "rust", Vector3(10, 0, 15))
			box(m, Vector3(0.22, 0.012, 0.1), Vector3(0.08, -0.02, 0.02), "steel_dk", Vector3(-15, 0, -20))
			box(m, Vector3(0.025, 0.2, 0.025), Vector3(0.02, 0.0, 0.04), "rust", Vector3(0, 0, 60))
		"phone":
			box(m, Vector3(0.075, 0.15, 0.01), Vector3.ZERO, "black")
			box(m, Vector3(0.064, 0.125, 0.002), Vector3(0, 0.002, 0.005), "navy")
			box(m, Vector3(0.05, 0.003, 0.003), Vector3(0.0, 0.03, 0.007), "steel_lt", Vector3(0, 0, 35))
			box(m, Vector3(0.035, 0.003, 0.003), Vector3(0.01, 0.015, 0.007), "steel_lt", Vector3(0, 0, -50))
		"battery":
			box(m, Vector3(0.26, 0.17, 0.17), Vector3.ZERO, "black")
			box(m, Vector3(0.26, 0.02, 0.17), Vector3(0, 0.095, 0), "steel_dk")
			cyl(m, 0.013, 0.025, Vector3(-0.08, 0.115, 0), "red")
			cyl(m, 0.013, 0.025, Vector3(0.08, 0.115, 0), "steel_lt")
			box(m, Vector3(0.14, 0.06, 0.004), Vector3(0, 0.0, 0.086), "yellow")
		"gold_watch":
			box(m, Vector3(0.02, 0.17, 0.006), Vector3.ZERO, "gold_dk")
			cyl(m, 0.022, 0.01, Vector3(0, 0, 0.005), "gold", Vector3(90, 0, 0))
			cyl(m, 0.018, 0.01, Vector3(0, 0, 0.007), "white", Vector3(90, 0, 0))
			box(m, Vector3(0.002, 0.014, 0.002), Vector3(0, 0.005, 0.013), "black")
			box(m, Vector3(0.01, 0.002, 0.002), Vector3(0.004, 0, 0.013), "black")
		"laptop":
			box(m, Vector3(0.34, 0.02, 0.24), Vector3(0, -0.06, 0), "steel_dk")
			box(m, Vector3(0.3, 0.004, 0.14), Vector3(0, -0.048, 0.03), "black")
			box(m, Vector3(0.34, 0.22, 0.012), Vector3(0, 0.045, -0.12), "steel_dk", Vector3(-12, 0, 0))
			box(m, Vector3(0.3, 0.18, 0.004), Vector3(0, 0.045, -0.112), "blue", Vector3(-12, 0, 0))
		"cash":
			for i in 4:
				box(m, Vector3(0.16, 0.008, 0.07), Vector3(i * 0.004, i * 0.009 - 0.014, 0), "green" if i % 2 == 0 else "green_lt", Vector3(0, i * 4.0, 0))
			box(m, Vector3(0.03, 0.04, 0.074), Vector3(0, 0, 0), "paper")
		"gold_bar":
			box(m, Vector3(0.2, 0.05, 0.08), Vector3(0, -0.01, 0), "gold")
			box(m, Vector3(0.17, 0.02, 0.06), Vector3(0, 0.025, 0), "gold_dk")
		"dog_tag": _tag(m, "steel", "steel_dk")
		"player_tag": _tag(m, "steel_lt", "blue")
		"bon_tag": _tag(m, "gold", "red")
		"intel_novarra":
			box(m, Vector3(0.22, 0.29, 0.01), Vector3.ZERO, "tan")
			box(m, Vector3(0.2, 0.27, 0.004), Vector3(0.02, 0.012, 0.007), "paper", Vector3(0, 0, -5))
			for i in 4:
				box(m, Vector3(0.12, 0.008, 0.002), Vector3(0.01, 0.07 - i * 0.03, 0.01), "grey", Vector3(0, 0, -5))
			box(m, Vector3(0.06, 0.04, 0.002), Vector3(0.06, -0.08, 0.011), "red", Vector3(0, 0, 10))
		"intel_exion":
			box(m, Vector3(0.24, 0.16, 0.01), Vector3.ZERO, "black")
			cyl(m, 0.032, 0.008, Vector3(0, 0, 0.008), "red", Vector3(90, 0, 0))
			box(m, Vector3(0.04, 0.008, 0.003), Vector3(-0.004, 0, 0.013), "black", Vector3(0, 0, 45))
			box(m, Vector3(0.04, 0.008, 0.003), Vector3(-0.004, 0, 0.013), "black", Vector3(0, 0, -45))
			box(m, Vector3(0.006, 0.03, 0.003), Vector3(0.018, 0, 0.013), "black")
		"mil_chip":
			box(m, Vector3(0.12, 0.08, 0.006), Vector3.ZERO, "pcb")
			box(m, Vector3(0.05, 0.05, 0.008), Vector3(-0.01, 0, 0.006), "black")
			box(m, Vector3(0.03, 0.03, 0.002), Vector3(-0.01, 0, 0.011), "red_dk")
			for i in 8:
				box(m, Vector3(0.006, 0.012, 0.003), Vector3(-0.05 + i * 0.012, -0.036, 0.004), "gold")
		"bolts":
			cyl(m, 0.008, 0.1, Vector3(0, 0, 0), "steel", Vector3(0, 0, 70))
			cyl(m, 0.017, 0.012, Vector3(-0.048, -0.017, 0), "steel_dk", Vector3(0, 0, 70), 0.0, 1.0, 6)
			for p in [Vector3(0.02, -0.04, 0.02), Vector3(0.05, -0.035, -0.01), Vector3(-0.02, -0.045, 0.03)]:
				cyl(m, 0.016, 0.01, p, "steel_lt", Vector3(80, 0, 10), 0.0, 1.0, 6)
		"wires":
			torus(m, 0.008, 0.05, Vector3.ZERO, "copper", Vector3(80, 0, 0))
			torus(m, 0.008, 0.048, Vector3(0.0, 0.0, 0.012), "copper", Vector3(80, 0, 8))
			cyl(m, 0.004, 0.08, Vector3(0.07, 0.03, 0), "red", Vector3(0, 0, -60))
		"gunpowder": _can(m, 0.05, 0.09, "black", "steel_dk")
		"cpu":
			box(m, Vector3(0.05, 0.05, 0.004), Vector3.ZERO, "pcb")
			box(m, Vector3(0.036, 0.036, 0.005), Vector3(0, 0, 0.004), "steel_lt")
			box(m, Vector3(0.01, 0.01, 0.002), Vector3(-0.022, -0.022, 0.003), "gold")
		"fuel_can":
			box(m, Vector3(0.34, 0.3, 0.16), Vector3.ZERO, "red")
			box(m, Vector3(0.12, 0.05, 0.03), Vector3(-0.06, 0.17, 0), "red_dk")
			cyl(m, 0.016, 0.06, Vector3(0.13, 0.17, 0), "black", Vector3(0, 0, -35))
			box(m, Vector3(0.28, 0.24, 0.004), Vector3(0, -0.01, 0.081), "red_dk")
			box(m, Vector3(0.25, 0.012, 0.006), Vector3(0, -0.01, 0.083), "red", Vector3(0, 0, 40))
			box(m, Vector3(0.25, 0.012, 0.006), Vector3(0, -0.01, 0.083), "red", Vector3(0, 0, -40))
		"med_supplies":
			box(m, Vector3(0.13, 0.09, 0.08), Vector3.ZERO, "white")
			box(m, Vector3(0.045, 0.012, 0.004), Vector3(0, 0, 0.041), "blue")
			box(m, Vector3(0.012, 0.045, 0.004), Vector3(0, 0, 0.041), "blue")
			cyl(m, 0.007, 0.08, Vector3(0.0, 0.054, 0.02), "glass", Vector3(0, 0, 80), 0.0, 0.7)
			cyl(m, 0.002, 0.03, Vector3(0.05, 0.06, 0.02), "steel_lt", Vector3(0, 0, 80))
		"novarra_badge":
			box(m, Vector3(0.07, 0.07, 0.006), Vector3(0, 0.01, 0), "gold_dk")
			box(m, Vector3(0.05, 0.05, 0.006), Vector3(0, -0.02, 0), "gold_dk", Vector3(0, 0, 45))
			box(m, Vector3(0.056, 0.056, 0.004), Vector3(0, 0.01, 0.004), "blue")
			box(m, Vector3(0.038, 0.038, 0.004), Vector3(0, -0.018, 0.004), "blue", Vector3(0, 0, 45))
			box(m, Vector3(0.018, 0.018, 0.003), Vector3(0, 0.0, 0.007), "white", Vector3(0, 0, 45))
		"hard_drive":
			box(m, Vector3(0.1, 0.145, 0.026), Vector3.ZERO, "steel_lt")
			box(m, Vector3(0.07, 0.08, 0.002), Vector3(0, 0.02, 0.014), "black")
			box(m, Vector3(0.05, 0.006, 0.002), Vector3(0, 0.03, 0.016), "white")
			box(m, Vector3(0.06, 0.01, 0.02), Vector3(0, -0.075, 0), "black")
		"exion_medal":
			box(m, Vector3(0.036, 0.05, 0.004), Vector3(0, 0.04, 0), "black")
			box(m, Vector3(0.01, 0.05, 0.005), Vector3(0, 0.04, 0), "red")
			cyl(m, 0.03, 0.006, Vector3(0, -0.02, 0), "iron", Vector3(90, 0, 0), 0.0, 1.0, 8)
			box(m, Vector3(0.04, 0.007, 0.003), Vector3(-0.005, -0.02, 0.004), "red", Vector3(0, 0, 45))
			box(m, Vector3(0.04, 0.007, 0.003), Vector3(-0.005, -0.02, 0.004), "red", Vector3(0, 0, -45))
			box(m, Vector3(0.006, 0.028, 0.003), Vector3(0.017, -0.02, 0.004), "red")
		"gpu":
			box(m, Vector3(0.27, 0.11, 0.035), Vector3.ZERO, "black")
			box(m, Vector3(0.27, 0.11, 0.004), Vector3(0, 0, -0.019), "pcb")
			for x in [-0.065, 0.065]:
				cyl(m, 0.045, 0.006, Vector3(x, 0, 0.019), "iron", Vector3(90, 0, 0))
				cyl(m, 0.012, 0.007, Vector3(x, 0, 0.021), "steel_dk", Vector3(90, 0, 0))
			box(m, Vector3(0.012, 0.12, 0.04), Vector3(-0.14, 0, 0), "steel")
			box(m, Vector3(0.12, 0.012, 0.004), Vector3(0.02, -0.06, -0.019), "gold")
		"diamond_ring":
			torus(m, 0.004, 0.012, Vector3(0, -0.006, 0), "gold", Vector3(0, 0, 0), 0.0)
			box(m, Vector3(0.012, 0.012, 0.012), Vector3(0, 0.012, 0), "cyan", Vector3(0, 45, 45), 0.4)
		"vase":
			cyl(m, 0.05, 0.03, Vector3(0, -0.13, 0), "blue")
			cyl(m, 0.09, 0.14, Vector3(0, -0.05, 0), "white", Vector3.ZERO, 0.0, 1.0, 16, 0.06)
			cyl(m, 0.05, 0.1, Vector3(0, 0.07, 0), "white", Vector3.ZERO, 0.0, 1.0, 16, 0.09)
			cyl(m, 0.092, 0.03, Vector3(0, -0.05, 0), "blue")
			cyl(m, 0.06, 0.02, Vector3(0, 0.13, 0), "blue")
		"crystal":
			box(m, Vector3(0.05, 0.16, 0.05), Vector3(0, 0, 0), "purple", Vector3(0, 45, 8), 0.5)
			box(m, Vector3(0.035, 0.1, 0.035), Vector3(-0.04, -0.03, 0.01), "purple", Vector3(0, 30, 30), 0.5)
			box(m, Vector3(0.03, 0.09, 0.03), Vector3(0.04, -0.035, 0.0), "purple", Vector3(0, 20, -28), 0.5)
			box(m, Vector3(0.14, 0.03, 0.06), Vector3(0, -0.08, 0), "grey")
		"golden_toilet":
			box(m, Vector3(0.2, 0.2, 0.2), Vector3(0, -0.25, 0.04), "gold_dk")
			cyl(m, 0.12, 0.12, Vector3(0, -0.1, 0.06), "gold", Vector3.ZERO, 0.0, 1.0, 16, 0.17)
			box(m, Vector3(0.36, 0.03, 0.03), Vector3(0, -0.035, 0.06), "gold_dk")
			box(m, Vector3(0.4, 0.32, 0.16), Vector3(0, 0.12, -0.12), "gold")
			box(m, Vector3(0.42, 0.03, 0.18), Vector3(0, 0.29, -0.12), "gold_dk")
			box(m, Vector3(0.05, 0.015, 0.02), Vector3(-0.13, 0.24, -0.03), "gold_dk")
		"holy_grail":
			cyl(m, 0.08, 0.02, Vector3(0, -0.14, 0), "gold_dk")
			cyl(m, 0.02, 0.12, Vector3(0, -0.07, 0), "gold")
			cyl(m, 0.035, 0.03, Vector3(0, -0.07, 0), "gold_dk")
			cyl(m, 0.05, 0.12, Vector3(0, 0.05, 0), "gold", Vector3.ZERO, 0.0, 1.0, 16, 0.1)
			cyl(m, 0.102, 0.02, Vector3(0, 0.1, 0), "gold_dk")
			for a in [-40.0, 0.0, 40.0]:
				var p := Vector3(sin(deg_to_rad(a)) * 0.08, 0.06, cos(deg_to_rad(a)) * 0.08)
				box(m, Vector3(0.022, 0.022, 0.01), p, "red" if a == 0.0 else "blue_lt", Vector3(0, a, 45), 0.3)
		_:
			return null
	return m


# ------------------------------------------------------------------------------------------------ item kinds
## An ammo box with a few rounds standing in front: the box colour and the round size tell them apart.
static func _ammo(m: Node3D, box_colour: String, case_colour: String, length: float, radius: float, count: int, tip: String) -> void:
	var w := radius * 2.4 * count + radius * 1.5
	var h := length * 1.5
	box(m, Vector3(w, h, 0.06), Vector3(0, h * 0.5, -0.04), box_colour)
	box(m, Vector3(w * 0.6, h * 0.22, 0.002), Vector3(0, h * 0.62, -0.009), "bone")
	for i in count:
		var x := (i - (count - 1) * 0.5) * radius * 2.4
		var case_h := length * 0.68
		cyl(m, radius, case_h, Vector3(x, case_h * 0.5, 0.01), case_colour)
		cyl(m, radius * 0.92, length - case_h, Vector3(x, case_h + (length - case_h) * 0.5, 0.01), tip, Vector3.ZERO, 0.0, 1.0, 12, radius * 0.35)


static func _shells(m: Node3D) -> void:
	box(m, Vector3(0.12, 0.075, 0.06), Vector3(0, 0.0375, -0.04), "red_dk")
	box(m, Vector3(0.08, 0.02, 0.002), Vector3(0, 0.045, -0.009), "bone")
	for i in 4:
		var x := (i - 1.5) * 0.026
		cyl(m, 0.0115, 0.055, Vector3(x, 0.0275 + 0.012, 0.012), "red")
		cyl(m, 0.012, 0.014, Vector3(x, 0.007, 0.012), "brass")


static func _vest(m: Node3D, main: String, dark: String, plated: bool) -> void:
	box(m, Vector3(0.42, 0.5, 0.12), Vector3.ZERO, main)
	box(m, Vector3(0.14, 0.12, 0.122), Vector3(0, 0.22, 0), "black")          # neck hole (dark)
	box(m, Vector3(0.08, 0.08, 0.12), Vector3(-0.17, 0.27, 0), main)            # shoulders
	box(m, Vector3(0.08, 0.08, 0.12), Vector3(0.17, 0.27, 0), main)
	if plated:
		box(m, Vector3(0.28, 0.3, 0.03), Vector3(0, 0.0, 0.07), dark)
		box(m, Vector3(0.26, 0.02, 0.032), Vector3(0, 0.1, 0.072), "steel_dk")
	for i in 3:
		box(m, Vector3(0.1, 0.11, 0.04), Vector3(-0.13 + i * 0.13, -0.17, 0.075), dark)
		box(m, Vector3(0.1, 0.02, 0.045), Vector3(-0.13 + i * 0.13, -0.12, 0.078), main)


static func _helmet(m: Node3D, main: String, dark: String, good: bool) -> void:
	var dome := sphere(m, 0.13, Vector3.ZERO, main, Vector3(1.15, 0.95, 1.0), true)
	dome.position.y = -0.04
	cyl(m, 0.152 if not good else 0.135, 0.015, Vector3(0, -0.04, 0), dark, Vector3.ZERO, 0.0, 1.0, 20)
	if good:
		box(m, Vector3(0.2, 0.025, 0.02), Vector3(0, 0.03, 0.12), "black")       # goggles strap
		for x in [-0.045, 0.045]:
			cyl(m, 0.024, 0.02, Vector3(x, 0.03, 0.13), "glass", Vector3(90, 0, 0), 0.0, 0.8)
			cyl(m, 0.027, 0.016, Vector3(x, 0.03, 0.127), "black", Vector3(90, 0, 0))
		box(m, Vector3(0.04, 0.03, 0.02), Vector3(0, 0.11, 0.06), "iron", Vector3(-30, 0, 0))   # mount
	else:
		box(m, Vector3(0.008, 0.08, 0.01), Vector3(-0.1, -0.08, 0.06), "brown_dk", Vector3(0, 0, 10))   # chin strap


static func _pack(m: Node3D, size: Vector3, main: String, accent: String, big: bool) -> void:
	box(m, size, Vector3.ZERO, main)
	box(m, Vector3(size.x * 1.02, size.y * 0.32, size.z * 1.05), Vector3(0, size.y * 0.36, 0.0), accent if not big else main)
	box(m, Vector3(size.x * 0.7, size.y * 0.32, size.z * 0.4), Vector3(0, -size.y * 0.18, size.z * 0.6), accent)  # front pocket
	box(m, Vector3(size.x * 0.12, size.y * 0.08, 0.01), Vector3(0, -size.y * 0.06, size.z * 0.81), "black")   # pocket tab
	box(m, Vector3(size.x * 0.25, size.y * 0.04, size.z * 0.3), Vector3(0, size.y * 0.53, -size.z * 0.1), "black")  # handle
	if big:
		for x in [-0.5, 0.5]:
			box(m, Vector3(size.x * 0.14, size.y * 0.5, size.z * 0.6), Vector3(x * size.x * 1.07, -size.y * 0.1, 0), accent)
		cyl(m, size.z * 0.35, size.x * 0.9, Vector3(0, -size.y * 0.58, 0), "olive_lt" if main == "olive" else "brown", Vector3(0, 0, 90))  # bedroll


static func _key(m: Node3D, colour: String, big: float) -> void:
	var s := big
	torus(m, 0.008 * s, 0.022 * s, Vector3(-0.05 * s, 0, 0), colour, Vector3(90, 0, 0), 0.0)
	cyl(m, 0.006 * s, 0.09 * s, Vector3(0.01 * s, 0, 0), colour, Vector3(0, 0, 90))
	box(m, Vector3(0.012 * s, 0.025 * s, 0.006 * s), Vector3(0.042 * s, -0.014 * s, 0), colour)
	box(m, Vector3(0.008 * s, 0.018 * s, 0.006 * s), Vector3(0.025 * s, -0.012 * s, 0), colour)
	if big > 1.0:
		cyl(m, 0.012 * s, 0.01 * s, Vector3(-0.026 * s, 0, 0), colour, Vector3(0, 0, 90))


static func _can(m: Node3D, radius: float, height: float, label: String, metal: String) -> void:
	cyl(m, radius, height, Vector3.ZERO, metal)
	cyl(m, radius * 1.01, height * 0.7, Vector3.ZERO, label)
	cyl(m, radius * 1.03, height * 0.06, Vector3(0, height * 0.47, 0), metal)
	cyl(m, radius * 1.03, height * 0.06, Vector3(0, -height * 0.47, 0), metal)
	box(m, Vector3(radius * 0.9, height * 0.25, 0.003), Vector3(0, 0, radius), "bone")


static func _tag(m: Node3D, metal: String, mark: String) -> void:
	for i in 2:
		var p := Vector3(-0.008 + i * 0.018, -0.006 * i, -0.004 * i)
		box(m, Vector3(0.03, 0.05, 0.003), p, metal, Vector3(0, 0, -8 + i * 18))
		box(m, Vector3(0.02, 0.004, 0.001), p + Vector3(0, 0.008, 0.002), mark, Vector3(0, 0, -8 + i * 18))
		box(m, Vector3(0.016, 0.004, 0.001), p + Vector3(0, -0.002, 0.002), mark, Vector3(0, 0, -8 + i * 18))
	for i in 9:   # the chain
		var t := float(i) / 8.0
		sphere(m, 0.0025, Vector3(-0.03 + t * 0.06, 0.03 + sin(t * PI) * 0.02, 0), "steel_dk")


# ------------------------------------------------------------------------------------------------ parts
static func _material(colour: String, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var c: Color = C[colour]
	mat.albedo_color = Color(c, alpha)
	mat.albedo_texture = _speckle()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(6, 6, 6)
	mat.roughness = 0.85
	if colour in ["gold", "gold_dk", "brass", "steel_lt", "copper"]:
		mat.metallic = 0.35
		mat.roughness = 0.45
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = emission
	return mat


static var _speckle_tex: ImageTexture

## A small pixel noise texture, so surfaces read as Bloxov's pixel art rather than flat plastic.
static func _speckle() -> ImageTexture:
	if _speckle_tex == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in 16:
			for x in 16:
				var v := 1.0 - rng.randf() * 0.14
				img.set_pixel(x, y, Color(v, v, v))
		_speckle_tex = ImageTexture.create_from_image(img)
	return _speckle_tex


static func _add(m: Node3D, mesh: Mesh, pos: Vector3, colour: String, rot: Vector3, emission: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = _material(colour, emission, alpha)
	m.add_child(mi)
	return mi


static func box(m: Node3D, size: Vector3, pos: Vector3, colour: String, rot := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(m, mesh, pos, colour, rot, emission, 1.0)


## A cylinder `height` tall along y (rotate it to lay it down). `top` != 0 gives a cone-ish top radius.
static func cyl(m: Node3D, radius: float, height: float, pos: Vector3, colour: String, rot := Vector3.ZERO,
		emission := 0.0, alpha := 1.0, sides := 16, top := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = top if top > 0.0 else radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return _add(m, mesh, pos, colour, rot, emission, alpha)


static func sphere(m: Node3D, radius: float, pos: Vector3, colour: String, scale := Vector3.ONE, half := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if half else 2.0)
	mesh.is_hemisphere = half
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := _add(m, mesh, pos, colour, Vector3.ZERO, 0.0, 1.0)
	mi.scale = scale
	return mi


static func torus(m: Node3D, thickness: float, radius: float, pos: Vector3, colour: String, rot := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 8
	return _add(m, mesh, pos, colour, rot, emission, 1.0)
