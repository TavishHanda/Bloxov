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


## Dresses the hands in your character's jacket and gloves (0.21.11, owner: the hands should match the character you
## picked in the wardrobe): the sleeves and gloves get that option's texture (make_hands.py writes them).
static func wear(hands: Node3D, look: Dictionary) -> void:
	var outfit := Operators.clean(look)
	var swap := {"gun_sleeve_black": "sleeve_" + String(outfit["Top"]), "gun_glove_black": "glove_" + String(outfit["Gloves"])}
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
			var dressed := material.duplicate() as BaseMaterial3D
			dressed.albedo_texture = load(path)
			mesh_instance.set_surface_override_material(i, dressed)


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
## Reloads from empty end with the gun being racked (handle, slide or bolt), pulled back this far through the reload.
const RACK_PULL := 0.82
## How the whole gun is held while reloading, added to its rest place and turn: brought in and rolled so the magazine
## (or the shotgun's loading port) faces the left hand.
const RELOAD_POSE := [Vector3(-0.07, 0.02, 0.03), Vector3(0.12, 0.12, -0.38)]
const LOAD_ONE_POSE := [Vector3(-0.06, 0.0, 0.04), Vector3(0.1, 0.2, -0.7)]


## The kick's offset to the model's place and turn, for kick amount `kick` (a spring, about 1 at its peak) and
## `side` (-1..1, a little sideways roll, new each shot). Smaller when aimed.
static func kick_offset(kick: float, side: float, aim: float) -> Array[Vector3]:
	var k := kick * lerpf(1.0, 0.45, aim)
	return [Vector3(0.004 * side, 0.006, 0.05) * k, Vector3(0.09, 0.02 * side, 0.05 * side) * k]


## Poses `holder`'s left hand (and magazine, or a shell for guns loaded one round at a time) for a reload `t` of the
## way through (0-1); `t` < 0 puts them back where they hold the gun. `empty`: the reload ends with a rack.
static func reload_pose(holder: Node3D, t: float, empty: bool, one_at_a_time: bool) -> void:
	var hands := holder.get_node_or_null("Hands") as Node3D
	if hands == null:
		return
	var hand := hands.get_node(String(hands.get_meta("gun")) + "_L") as Node3D
	if not hand.has_meta("rest"):
		hand.set_meta("rest", hand.position)
	var hand_rest: Vector3 = hand.get_meta("rest")
	var mag := holder.get_node_or_null("Art/Mag") as Node3D
	if mag != null and not mag.has_meta("rest"):
		mag.set_meta("rest", mag.position)
	var shell := hand.get_node_or_null("Shell") as Node3D
	if t < 0.0:
		hand.position = hand_rest
		if mag != null:
			mag.position = mag.get_meta("rest")
		if shell != null:
			shell.visible = false
		return
	var sight := sight_height(holder)
	if one_at_a_time:
		# Down to the shell pouch, then the shell goes up into the loading port under the gun.
		var port := Vector3(0.0, -0.075, 0.03)
		hand.position = _track([[0.0, hand_rest], [0.22, port + Vector3(-0.05, -0.16, 0.08)],
			[0.34, port + Vector3(-0.05, -0.16, 0.08)], [0.52, port + Vector3(-0.012, -0.035, 0.04)],
			[0.62, port + Vector3(0.0, -0.022, -0.015)], [1.0, hand_rest]], t)
		if shell == null:
			shell = _shell()
			hand.add_child(shell)
		shell.visible = t > 0.26 and t < 0.62
		return
	if mag == null:
		return
	var mag_rest: Vector3 = mag.get_meta("rest")
	var pistol := mag_rest.z > 0.0   # the pistol's mag is in its grip, behind the trigger
	var grab := mag_rest + (Vector3(-0.03, -0.03, 0.0) if pistol else Vector3(-0.035, -0.05, 0.0))
	var away := grab + Vector3(-0.06, -0.3, 0.14)
	var keys := [[0.0, hand_rest], [0.14, grab], [0.22, grab], [0.4, away], [0.47, away], [0.58, grab],
		[0.62, grab + Vector3(0, 0.014, 0)]]
	if empty:
		# The rack: the hand goes over the gun, pulls back and lets go.
		var rack := Vector3(-0.025, sight - 0.01, mag_rest.z - 0.01) if pistol else Vector3(-0.045, sight * 0.35, mag_rest.z + 0.07)
		keys.append_array([[0.66, grab], [0.76, rack], [RACK_PULL, rack + Vector3(0, 0, 0.06)], [0.86, rack + Vector3(0, 0, 0.05)], [1.0, hand_rest]])
	else:
		keys.append([0.8, hand_rest])
	hand.position = _track(keys, t)
	mag.position = mag_rest + (hand.position - grab if t > 0.14 and t < 0.58 else Vector3.ZERO)


## How much the whole gun bumps during a reload `t` through: the mag seating (0.6) and the rack letting go.
static func reload_jolt(t: float, empty: bool) -> float:
	var jolt := _bump(t, 0.6, 0.05)
	if empty:
		jolt += _bump(t, 0.85, 0.05)
	return jolt


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
