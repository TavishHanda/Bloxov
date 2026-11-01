class_name GunViewModels
extends RefCounted
## The first-person gun models (0.18.1): the same .glb models other players and the AI hold (HeldGun,
## art_source/scripts/make_gun.py), one per view model key. The rifle and pistol go into the Model and PistolModel nodes
## of player.tscn, the others into new nodes built here; each has a "Muzzle" marker with the muzzle flash (copied from
## the rifle's), moved onto the model's own muzzle.

## Turned a little at the hip so its side shows (the shotgun's pump; less since 0.20.15, owner: it faced too far left),
## straight when aimed.
const REST_TURN := {"shotgun": Vector3(0.0, 0.1, 0.1)}
## Where each model sits at rest, and when aimed (centred; the height comes from the model's iron sights, see
## aim_height()). The rifle's and pistol's rest places are their nodes' in player.tscn.
const REST := {"smg": Vector3(0.2, -0.19, -0.38), "shotgun": Vector3(0.22, -0.2, -0.42), "sniper": Vector3(0.22, -0.2, -0.44)}
const ADS := {"smg": Vector3(0, -0.086, -0.32), "shotgun": Vector3(0, -0.072, -0.38), "sniper": Vector3(0, -0.084, -0.4)}
## View model key -> the weapon whose model it shows (HeldGun.MODELS).
const WEAPONS := {"rifle": "ak", "pistol": "pistol", "smg": "smg", "shotgun": "shotgun", "sniper": "sniper"}
## Aimed, the sight line runs through the middle of the screen, where the shots go (0.21.16: it sat 3 mm under it,
## so the sights pointed a little low of the crosshair, owner).


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
		add_hands(holder, HeldGun.MODELS[WEAPONS[key]])
	return models


# --- Hands (0.20.15, owner: "add like a hand model holding the gun") ---------------------------------

## The hands model (art_source/scripts/make_hands.py): each gun's two hands, and the forearms.
const HANDS := "res://assets/models/hands/hands.glb"
## Where the elbows are, in the Gun node's frame (just under and behind the camera): the forearms point at them.
const ELBOW_R := Vector3(0.24, -0.46, 0.02)
const ELBOW_L := Vector3(-0.14, -0.44, -0.12)


## Puts gun `gun`'s hands (and both forearms) on first-person `holder`, as a "Hands" node lined up with its Art.
static func add_hands(holder: Node3D, gun: String, path := HANDS) -> void:
	var hands: Node3D = (load(path) as PackedScene).instantiate()
	hands.name = "Hands"
	PixelModel.make_crisp(hands)
	for child: Node in hands.get_children():
		if not child.name in [gun + "_R", gun + "_L", "ArmR", "ArmL"]:
			hands.remove_child(child)
			child.free()
	for mesh: GeometryInstance3D in hands.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wear(hands, Profile.look)
	holder.add_child(hands)
	hands.set_meta("gun", gun)


## The dressed sleeve and glove materials, shared and kept for good: one freed while its hands were being freed left
## the renderer pointing at it (an engine error on the server when a player left, 0.21.16).
static var _dressed := {}


## Dresses the hands in your character's jacket and gloves (0.21.11, owner: the hands should match the character you
## picked in the wardrobe): the sleeves and gloves get that option's texture (make_hands.py writes them).
static func wear(hands: Node3D, look: Dictionary) -> void:
	var outfit := Operators.clean(look)
	var swap := {"gun_sleeve_black": "sleeve-" + String(outfit["Top"]), "gun_glove_black": "glove-" + String(outfit["Gloves"])}
	for mesh_instance: MeshInstance3D in hands.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material == null or not swap.has(material.resource_name):
				continue
			var path := "res://assets/models/hands/outfit/%s.png" % swap[material.resource_name]
			if not ResourceLoader.exists(path):
				continue
			var key := "%s|%s" % [material.resource_path + material.resource_name, path]
			if not _dressed.has(key):
				var dressed := material.duplicate() as BaseMaterial3D
				dressed.albedo_texture = load(path)
				_dressed[key] = dressed
			mesh_instance.set_surface_override_material(i, _dressed[key])


## Points the forearms of `holder`'s hands from the wrists at the elbows (`frame`: the Gun node). Call after moving it.
static func pose_arms(holder: Node3D, frame: Node3D) -> void:
	var hands := holder.get_node_or_null("Hands") as Node3D
	if hands == null or not hands.is_visible_in_tree():
		return
	var gun: String = hands.get_meta("gun")
	for side: String in ["R", "L"]:
		var arm := hands.get_node("Arm" + side) as Node3D
		var wrist := (hands.get_node(gun + "_" + side) as Node3D).global_position
		var elbow := frame.to_global(ELBOW_R if side == "R" else ELBOW_L)
		arm.global_position = wrist
		if not wrist.is_equal_approx(elbow):
			arm.look_at(elbow, frame.global_basis.x)


## How high the model's iron sights are (aiming puts them level with the middle of the screen).
static func sight_height(model: Node3D) -> float:
	return (model.get_node("Art/Sight") as Node3D).position.y


## Where model `model` sits when aimed, from `ads` (its centred place) and its sights.
static func aim_place(model: Node3D, ads: Vector3) -> Vector3:
	return Vector3(ads.x, -sight_height(model), ads.z)


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
	var irons := art.get_node_or_null("Irons") as Node3D
	if irons != null:   # an optic replaces the iron sights (0.20.20): never both on the gun
		irons.visible = not (attachments.has("scope") or attachments.has("sight"))
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


# --- Animations (0.20.24, owner: reload animations and a visual kick per shot) ------------------------

## How hard each model jolts back and up when it fires. Only the model moves: aim, recoil and spread don't change.
const KICK := {"rifle": 1.0, "pistol": 0.8, "smg": 0.65, "shotgun": 1.7, "sniper": 1.9}

## Each view model's own reload (0.25.29, owner: the Lancer had the same reload as the pistol): "rock" (the Hound: the
## mag rocks out and back in, the handle on its right is racked), "slap" (the Wasp: the cocking handle is locked back,
## the mag swapped, the handle slapped home), "drop" (the Stinger: the mag drops out of the grip, a new one goes in from
## below, the slide is racked), "bolt" (the Lancer: the bolt turns up and back, rounds are pushed in from the top, the
## bolt goes home), "shells" (the Mauler: a shell at a time into the port underneath).
const RELOAD_STYLE := {"rifle": "rock", "smg": "slap", "pistol": "drop", "sniper": "bolt", "shotgun": "shells"}


## The kick's offset to the model's place and turn, for kick amount `kick` (a spring, about 1 at its peak) and
## `side` (-1..1, a little sideways roll, new each shot). Smaller when aimed.
static func kick_offset(kick: float, side: float, aim: float) -> Array[Vector3]:
	var k := kick * lerpf(1.0, 0.45, aim)
	return [Vector3(0.004 * side, 0.006, 0.05) * k, Vector3(0.09, 0.02 * side, 0.05 * side) * k]


## When view model `key`'s reload sounds play, as [t, sound] in order (`t`: how far through, 0-1): "out" the mag
## released (or the Lancer's bolt drawn back), "in" the mag going in (the rounds, a shell), "click" a handle, slide or
## bolt being worked. `empty`: reloading from empty (the gun is racked at the end).
static func reload_sounds(key: String, empty: bool) -> Array:
	match RELOAD_STYLE.get(key, "rock"):
		"shells":
			return [[0.6, "in"]]
		"bolt":
			return [[0.17, "click"], [0.25, "out"], [0.54, "in"], [0.86, "click"]]
		"slap":
			if empty:
				return [[0.0, "out"], [0.16, "click"], [0.66, "in"], [0.82, "click"]]
			return [[0.0, "out"], [0.6, "in"]]
		"drop":
			return [[0.0, "out"], [0.52, "in"]] + ([[0.82, "click"]] if empty else [])
	return [[0.0, "out"], [0.62, "in"]] + ([[0.84, "click"]] if empty else [])


## How much the whole gun bumps `t` through a reload: as the mag (or rounds) go in and the gun is worked.
static func reload_jolt(key: String, t: float, empty: bool) -> float:
	var jolt := 0.0
	for sound: Array in reload_sounds(key, empty):
		if sound[1] != "out":
			jolt += _bump(t, sound[0], 0.05)
	return jolt


## How the whole gun is held `t` through a reload of view model `key`, added to where it sits and how it's turned:
## brought in and rolled so the magazine (the Lancer's bolt, the Mauler's loading port) faces the hand working it.
static func reload_hold(key: String, t: float, empty: bool) -> Array[Vector3]:
	var jolt := reload_jolt(key, t, empty)
	match RELOAD_STYLE.get(key, "rock"):
		"shells":
			var push := sin(clampf(t, 0.0, 1.0) * PI)
			return [Vector3(-0.06, 0.0, 0.04 + 0.02 * push), Vector3(0.1, 0.2, -0.7)]
		"drop":
			return [Vector3(-0.07, 0.07 + 0.01 * jolt, 0.02), Vector3(0.3 + 0.06 * jolt, 0.15, -0.35)]
		"bolt":
			return [Vector3(-0.07, 0.02 + 0.01 * jolt, 0.03), Vector3(0.12 + 0.06 * jolt, 0.12, -0.38)]
		"slap":
			return [Vector3(-0.07, 0.02 + 0.01 * jolt, 0.03), Vector3(0.12 + 0.06 * jolt, 0.12, -0.38)]
	return [Vector3(-0.07, 0.02 + 0.01 * jolt, 0.03), Vector3(0.12 + 0.06 * jolt, 0.12, -0.38)]


## Poses `holder`'s hands, magazine and bolt (handle, slide) `t` through a reload (0-1) of view model `key`; `t` < 0
## puts them all back where they are when holding the gun. `empty`: reloading from empty (the gun is racked).
static func reload_pose(holder: Node3D, key: String, t: float, empty: bool) -> void:
	var hands := holder.get_node_or_null("Hands") as Node3D
	if hands == null:
		return
	var gun := String(hands.get_meta("gun"))
	var left := hands.get_node(gun + "_L") as Node3D
	var right := hands.get_node(gun + "_R") as Node3D
	var mag := holder.get_node_or_null("Art/Mag") as Node3D
	var bolt := holder.get_node_or_null("Art/Bolt") as Node3D
	var irons := holder.get_node_or_null("Art/Irons") as Node3D
	for node: Node3D in [left, right, mag, bolt, irons]:
		if node == null:
			continue
		if not node.has_meta("rest"):
			node.set_meta("rest", node.position)
			node.set_meta("rest_turn", node.rotation)
		node.position = node.get_meta("rest")
		node.rotation = node.get_meta("rest_turn")
	if mag != null:
		mag.visible = true
	for extra: String in ["Shell", "Rounds"]:
		var node := left.get_node_or_null(extra) as Node3D
		if node != null:
			node.visible = false
	if t < 0.0:
		return
	match RELOAD_STYLE.get(key, "rock"):
		"shells":
			_reload_shells(left, t)
		"bolt":
			if bolt != null:
				_reload_bolt(left, right, bolt, t)
		_:
			if mag == null:
				return
			match RELOAD_STYLE.get(key, "rock"):
				"slap":
					_reload_slap(left, mag, bolt, t, empty)
				"drop":
					_reload_drop(left, mag, [bolt, irons], sight_height(holder), t, empty)
				_:
					_reload_rock(left, mag, bolt, t, empty)


## The Hound: the left hand rocks the curved mag forward out of the gun, hooks a new one in and rocks it back; from
## empty it reaches under to the handle on the right and racks it.
static func _reload_rock(left: Node3D, mag: Node3D, bolt: Node3D, t: float, empty: bool) -> void:
	var hand_rest: Vector3 = left.get_meta("rest")
	var mag_rest: Vector3 = mag.get_meta("rest")
	var grab := mag_rest + Vector3(-0.035, -0.05, 0.0)
	var tip := Vector3(0.0, -0.02, -0.035)
	var away := grab + Vector3(-0.06, -0.3, 0.14)
	var keys := [[0.0, hand_rest], [0.12, grab], [0.18, grab], [0.27, grab + tip], [0.4, away], [0.47, away],
		[0.55, grab + tip], [0.62, grab]]
	if empty and bolt != null:
		var rack: Vector3 = (bolt.get_meta("rest") as Vector3) + Vector3(0.025, -0.035, 0.0)
		keys.append_array([[0.68, grab + Vector3(0.02, 0.0, -0.02)], [0.76, rack], [0.82, rack + Vector3(0, 0, 0.1)],
			[0.86, rack + Vector3(0.01, -0.015, 0.11)], [1.0, hand_rest]])
		bolt.position.z += _trackf([[0.76, 0.0], [0.82, 0.1], [0.84, 0.1], [0.86, 0.0]], t)
	else:
		keys.append([0.8, hand_rest])
	left.position = _track(keys, t)
	if t > 0.12 and t < 0.62:
		mag.position = mag_rest + left.position - grab
		mag.rotation.x = _trackf([[0.18, 0.0], [0.27, 0.55], [0.55, 0.55], [0.62, 0.0]], t)


## The Wasp: from empty the cocking handle is pulled back and locked up first; the mag comes straight down and a new one
## goes in; then the handle is slapped down and snaps home.
static func _reload_slap(left: Node3D, mag: Node3D, bolt: Node3D, t: float, empty: bool) -> void:
	var hand_rest: Vector3 = left.get_meta("rest")
	var mag_rest: Vector3 = mag.get_meta("rest")
	var grab := mag_rest + Vector3(-0.035, -0.05, 0.0)
	var away := grab + Vector3(-0.06, -0.3, 0.14)
	var cocked := empty and bolt != null
	var s := 0.18 if cocked else 0.0   # when the mag swap starts
	var keys := [[0.0, hand_rest]]
	var hold := Vector3.ZERO
	if cocked:
		hold = (bolt.get_meta("rest") as Vector3) + Vector3(-0.005, 0.035, 0.0)   # over the top onto the handle
		keys.append_array([[0.1, hold], [0.16, hold + Vector3(0, 0, 0.08)], [0.2, hold + Vector3(0, 0.012, 0.08)]])
	keys.append_array([[s + 0.14, grab], [s + 0.2, grab], [s + 0.36, away], [s + 0.42, away], [s + 0.52, grab],
		[s + 0.56, grab + Vector3(0, 0.014, 0)]])
	if cocked:
		keys.append_array([[0.76, hold + Vector3(0.0, 0.06, 0.07)], [0.81, hold + Vector3(0, 0.0, 0.08)],
			[0.86, hold + Vector3(0.0, -0.01, 0.0)], [1.0, hand_rest]])
		bolt.position += Vector3(0.0, _trackf([[0.16, 0.0], [0.2, 0.01], [0.81, 0.01], [0.83, 0.0]], t),
			_trackf([[0.1, 0.0], [0.16, 0.08], [0.81, 0.08], [0.83, 0.0]], t))
	else:
		keys.append([0.8, hand_rest])
	left.position = _track(keys, t)
	if t > s + 0.14 and t < s + 0.52:
		mag.position = mag_rest + left.position - grab


## The Stinger: the mag drops out of the grip, the left hand brings a new one up into it from below and palms it home;
## from empty it then racks the slide over the top. `slide`: the slide and the sights on it.
static func _reload_drop(left: Node3D, mag: Node3D, slide: Array, sight: float, t: float, empty: bool) -> void:
	var hand_rest: Vector3 = left.get_meta("rest")
	var mag_rest: Vector3 = mag.get_meta("rest")
	var hold := mag_rest + Vector3(-0.01, -0.05, 0.0)    # cupping the mag's base
	var pouch := mag_rest + Vector3(-0.09, -0.3, 0.12)
	var down_grip := Vector3(0.0, -0.96, 0.28)          # the grip leans back 16 degrees
	var keys := [[0.0, hand_rest], [0.14, pouch], [0.26, pouch], [0.42, hold + down_grip * 0.075], [0.5, hold],
		[0.54, hold + Vector3(0, 0.012, 0)], [0.58, hold]]
	if empty:
		var rack := Vector3(-0.025, sight - 0.01, mag_rest.z - 0.01)
		keys.append_array([[0.66, hold + Vector3(-0.02, 0.04, 0.0)], [0.74, rack], [0.8, rack + Vector3(0, 0, 0.045)],
			[0.84, rack + Vector3(0, 0.01, 0.05)], [1.0, hand_rest]])
		var back := _trackf([[0.74, 0.0], [0.8, 0.03], [0.81, 0.03], [0.83, 0.0]], t)
		for node: Node3D in slide:
			if node != null:
				node.position.z += back
	else:
		keys.append([0.78, hand_rest])
	left.position = _track(keys, t)
	if t < 0.26:
		# The old mag falls out of the grip, gone once it's out of sight.
		var fall := clampf((t - 0.03) / 0.17, 0.0, 1.0)
		mag.position = mag_rest + down_grip * 0.4 * fall * fall
		mag.visible = t < 0.2
	elif t < 0.5:
		mag.position = mag_rest + left.position - hold


## The Lancer: the right hand turns the bolt up and draws it back, the left pushes rounds down into the open action, the
## right runs the bolt home and goes back to the grip.
static func _reload_bolt(left: Node3D, right: Node3D, bolt: Node3D, t: float) -> void:
	var lift := _trackf([[0.1, 0.0], [0.17, 1.1], [0.8, 1.1], [0.86, 0.0]], t)
	bolt.rotation.z = lift
	bolt.position.z += _trackf([[0.17, 0.0], [0.25, 0.075], [0.72, 0.075], [0.8, 0.0]], t)
	var knob := bolt.position + Vector3(0.058, -0.008, 0.0).rotated(Vector3.BACK, lift)
	var on_knob := knob + Vector3(0.015, -0.015, 0.035)
	right.position = (right.get_meta("rest") as Vector3).lerp(on_knob,
		_trackf([[0.02, 0.0], [0.1, 1.0], [0.86, 1.0], [0.96, 0.0]], t))
	var hand_rest: Vector3 = left.get_meta("rest")
	var pouch := hand_rest + Vector3(-0.06, -0.25, 0.22)
	var top := Vector3(-0.04, 0.035, 0.09)   # over the open action
	var push := Vector3(0.0, -0.025, 0.0)
	left.position = _track([[0.0, hand_rest], [0.2, hand_rest], [0.3, pouch], [0.36, pouch], [0.44, top],
		[0.48, top + push], [0.51, top], [0.54, top + push], [0.6, top + Vector3(0, 0.02, 0)], [0.72, hand_rest]], t)
	var rounds := left.get_node_or_null("Rounds") as Node3D
	if rounds == null:
		rounds = _rounds()
		left.add_child(rounds)
	rounds.visible = t > 0.33 and t < 0.56


## The Mauler: down to the shell pouch, then the shell goes up into the loading port under the gun.
static func _reload_shells(left: Node3D, t: float) -> void:
	var hand_rest: Vector3 = left.get_meta("rest")
	var port := Vector3(0.0, -0.075, 0.03)
	left.position = _track([[0.0, hand_rest], [0.22, port + Vector3(-0.05, -0.16, 0.08)],
		[0.34, port + Vector3(-0.05, -0.16, 0.08)], [0.52, port + Vector3(-0.012, -0.035, 0.04)],
		[0.62, port + Vector3(0.0, -0.022, -0.015)], [1.0, hand_rest]], t)
	var shell := left.get_node_or_null("Shell") as Node3D
	if shell == null:
		shell = _shell()
		left.add_child(shell)
	shell.visible = t > 0.26 and t < 0.62


## A shotgun shell for the left hand to load.
static func _shell() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.011
	mesh.bottom_radius = 0.011
	mesh.height = 0.06
	mesh.radial_segments = 8
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.12, 0.1)
	mesh.material = mat
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = mesh
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	shell.position = Vector3(0.012, 0.02, -0.01)
	shell.visible = false
	return shell


## Two rifle rounds lying along the barrel, for the left hand to push into the Lancer.
static func _rounds() -> Node3D:
	var rounds := Node3D.new()
	rounds.name = "Rounds"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.69, 0.54, 0.23)
	for k in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.005
		mesh.bottom_radius = 0.0065
		mesh.height = 0.08
		mesh.radial_segments = 6
		mesh.rings = 1
		mesh.material = mat
		var round_mesh := MeshInstance3D.new()
		round_mesh.mesh = mesh
		round_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		round_mesh.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		round_mesh.position = Vector3(0.006 * (k * 2 - 1), -0.01 * k, 0.0)
		rounds.add_child(round_mesh)
	rounds.position = Vector3(0.02, -0.015, 0.0)
	rounds.visible = false
	return rounds


## `keys` ([[t, value], ...], in order) at `t`, easing in and out between them (a number).
static func _trackf(keys: Array, t: float) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			return lerpf(keys[i - 1][1], keys[i][1], smoothstep(keys[i - 1][0], keys[i][0], t))
	return keys[-1][1]


## `keys` ([[t, place], ...], in order) at `t`, easing in and out between them.
static func _track(keys: Array, t: float) -> Vector3:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], smoothstep(keys[i - 1][0], keys[i][0], t))
	return keys[-1][1]


## 1 at `at`, falling to 0 `width` either side.
static func _bump(t: float, at: float, width: float) -> float:
	return maxf(0.0, 1.0 - absf(t - at) / width)
