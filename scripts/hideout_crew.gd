class_name HideoutCrew
extends Node3D
## The crew (lively hideout, owner 2026-11-09: "YESSSSSS OMG YES"): other PMCs living in the hideout, each at one
## thing: asleep in a bunk, cooking at the stove, two playing cards in the mess, one fixing the generator, one with a
## coffee by the range. The ones awake look round at you when you come close. Looks only: nobody collides, nothing is
## sent online, and a headless run (the server, the tests) shows none of them unless `force_reacts` is set.
## Where they are comes from the hideout level: its seats, its Life node's metadata (make_hideout.py) and the range.

const CHARACTER_MODEL := preload("res://assets/models/characters/pmc.glb")
const PIXEL_MODEL_SCRIPT := preload("res://scripts/pixel_model.gd")
const SNORE := preload("res://audio/world/snore.wav")
const WRENCH := preload("res://audio/world/wrench.wav")
const LOOK_REACH := 4.5      # metres: the ones awake turn their heads to you nearer than this
const SNORE_EVERY := 4.2     # seconds a breath, asleep
const NEAR_SNORE := 6.0
const NEAR_WRENCH := 11.0

## Who's where, and what they wear (the wardrobe's parts; no helmets at home).
const LOOKS := {
	"sleeper": {"Head": "pale_beard", "Hat": "cap_headset", "Eyes": "none", "Mask": "none", "Top": "green", "Vest": "green",
		"Pants": "green", "Gloves": "black", "Boots": "black"},
	"cook": {"Head": "dark_beard", "Hat": "cap_headset", "Eyes": "none", "Mask": "none", "Top": "tan", "Vest": "tan",
		"Pants": "multicam", "Gloves": "tan", "Boots": "coyote"},
	"cards_a": {"Head": "tan", "Hat": "cap_headset", "Eyes": "glasses", "Mask": "none", "Top": "multicam", "Vest": "green",
		"Pants": "green", "Gloves": "green", "Boots": "black"},
	"cards_b": {"Head": "pale", "Hat": "helmet_green", "Eyes": "none", "Mask": "gaiter_green", "Top": "black", "Vest": "black",
		"Pants": "black", "Gloves": "black", "Boots": "black"},
	"mechanic": {"Head": "dark", "Hat": "cap_headset", "Eyes": "glasses", "Mask": "none", "Top": "green", "Vest": "tan",
		"Pants": "tan", "Gloves": "black", "Boots": "coyote"},
	"coffee": {"Head": "pale", "Hat": "helmet_tan", "Eyes": "none", "Mask": "gaiter_tan", "Top": "tan", "Vest": "green",
		"Pants": "multicam", "Gloves": "tan", "Boots": "tan"},
}

var walker: Node3D
## Each one: {"id", "model", "pose", "phase", "look" (radians the head's turned), "next" (seconds to their next sound)}.
var members: Array[Dictionary] = []
var _time := 0.0
var _dice := RandomNumberGenerator.new()


func setup(level: Node3D, who: Node3D) -> void:
	walker = who
	if not Reacts.wanted(self):
		return
	_dice.randomize()
	var life := level.get_node_or_null("Life") as Node3D
	var seats := level.get_node_or_null("Seats") as Node3D
	if life != null and life.has_meta(&"bed"):
		var head: Vector3 = life.get_meta(&"bed_head")
		_add("sleeper", (life.get_meta(&"bed") as Vector3) - head * 0.75, head)   # (lying: the model's +z to the pillow)
	if life != null and life.has_meta(&"steam"):
		var stove: Vector3 = life.get_meta(&"steam")
		var out: Vector3 = life.get_meta(&"fire_dir", Vector3.LEFT)
		_add("cook", Vector3(stove.x, 0.0, stove.z) + out * 0.95, out)
	if seats != null:
		for pair: Array in [["cards_a", "Seat0"], ["cards_b", "Seat2"]]:
			var seat := seats.get_node_or_null(pair[1] as String) as Node3D
			if seat != null:
				seat.set_meta(&"taken", true)   # (HideoutToys won't sit you on someone)
				_add(pair[0], seat.position - Vector3.UP * seat.position.y, seat.basis.z)
	if life != null and life.has_meta(&"generator"):
		var gen: Vector3 = life.get_meta(&"generator")
		_add("mechanic", Vector3(gen.x, 0.0, gen.z + 0.95), Vector3.BACK)
	var spot := level.get_node_or_null("Range/Spot") as Node3D
	if spot != null:
		_add("coffee", spot.position + Vector3(3.1, 0.0, 1.6), Vector3(0.5, 0.0, 0.8).normalized())
	_props()


## One of them at `at` (on the floor), facing away from `back` (the model faces its -z).
func _add(id: String, at: Vector3, back: Vector3) -> void:
	var model := CHARACTER_MODEL.instantiate()
	model.set_script(PIXEL_MODEL_SCRIPT)
	(model as PixelModel).randomize_outfit = false
	model.name = id.capitalize().replace(" ", "")
	add_child(model)
	(model as PixelModel).pick_outfit(LOOKS[id])
	model.position = at
	model.rotation.y = atan2(back.x, back.z)
	var gun := model.get_node_or_null("Gun") as Node3D
	if gun != null:
		gun.visible = false
	var pose := BodyPose.new(model)
	pose.armed = false
	members.append({"id": id, "model": model, "pose": pose, "phase": _dice.randf() * TAU, "look": 0.0,
		"next": _dice.randf_range(1.0, 6.0)})


## What they hold or have in front of them: the cook's spoon, the mechanic's wrench, a mug, cards on the table.
func _props() -> void:
	for m: Dictionary in members:
		var pose: BodyPose = m["pose"]
		match m["id"]:
			"cook":
				_box(pose.joint("ElbowR"), Vector3(0.025, 0.4, 0.025), Vector3(0, -0.36, -0.08), Color(0.5, 0.5, 0.52), Vector3(-50, 0, 0))
			"mechanic":
				_box(pose.joint("ElbowR"), Vector3(0.03, 0.03, 0.26), Vector3(0, -0.34, -0.1), Color(0.55, 0.56, 0.58))
			"coffee":
				_box(pose.joint("ElbowR"), Vector3(0.08, 0.1, 0.08), Vector3(0, -0.36, -0.06), Color(0.85, 0.85, 0.8))
			"cards_a", "cards_b":
				for k in 2:   # (a hand of cards in each)
					var side := "ElbowL" if k == 0 else "ElbowR"
					_box(pose.joint(side), Vector3(0.09, 0.012, 0.12), Vector3(0, -0.35, -0.04), Color(0.92, 0.9, 0.84), Vector3(0, 0, 0))
	var a := members.filter(func(m: Dictionary) -> bool: return m["id"] == "cards_a")
	var b := members.filter(func(m: Dictionary) -> bool: return m["id"] == "cards_b")
	if not a.is_empty() and not b.is_empty():   # (the pile between them, and a few cards played)
		var mid: Vector3 = ((a[0]["model"] as Node3D).position + (b[0]["model"] as Node3D).position) / 2.0
		var table := mid + Vector3.UP * 0.78
		_box(self, Vector3(0.09, 0.04, 0.12), table, Color(0.75, 0.2, 0.18))
		for k in 4:
			_box(self, Vector3(0.09, 0.006, 0.12), table + Vector3(0.18 + k * 0.05, -0.017, 0.02 * (k % 2)), Color(0.93, 0.91, 0.86),
				Vector3(0, 20.0 * k - 30.0, 0))


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, turn := Vector3.ZERO) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	mesh.material = material
	box.mesh = mesh
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	box.position = at
	box.rotation_degrees = turn
	return box


func _process(delta: float) -> void:
	_time += delta
	for m: Dictionary in members:
		_pose(m, delta)
		m["next"] = float(m["next"]) - delta
		if float(m["next"]) <= 0.0:
			_sound(m)


## Their sounds, heard only close by: snoring, the wrench on the generator.
func _sound(m: Dictionary) -> void:
	var model: Node3D = m["model"]
	match m["id"]:
		"sleeper":
			m["next"] = SNORE_EVERY
			WorldSounds.at_soft(self, SNORE, model.global_position + Vector3.UP * 0.3, -14.0, NEAR_SNORE, _dice.randf_range(0.95, 1.05))
		"mechanic":
			m["next"] = _dice.randf_range(3.0, 9.0)
			WorldSounds.at_soft(self, WRENCH, model.global_position + Vector3(0, 0.6, -0.5), -12.0, NEAR_WRENCH, _dice.randf_range(0.9, 1.1))
		_:
			m["next"] = 9999.0


func _pose(m: Dictionary, delta: float) -> void:
	var pose: BodyPose = m["pose"]
	var t := _time + float(m["phase"])
	var p := {}
	match m["id"]:
		"sleeper":   # on their back, one arm across the chest, head to one side, breathing slow
			var breath := sin(t * TAU / SNORE_EVERY)
			p = {"hips_pos": Vector3(0, 0.12, 0.62), "hips_rot": Vector3(90, 0, 0), "Spine": Vector3(2.0 * breath, 0, 0),
				"Neck": Vector3(0, 28, 0), "ArmL": Vector3(35, 0, 30), "ElbowL": Vector3(-95, 0, 0),
				"ArmR": Vector3(0, 0, 10), "ElbowR": Vector3(-10, 0, 0), "LegL": Vector3(0, 0, -6),
				"LegR": Vector3(4, 0, 8), "KneeR": Vector3(-14, 0, 0)}
			pose._apply(p)
			return
		"cards_a", "cards_b":   # sat at the table, cards held up, now and then one goes down
			var play := maxf(0.0, sin(t * 0.7)) ** 8.0
			p = {"hips_pos": Vector3(0, 0.52, 0.02), "Spine": Vector3(-8, 0, 0), "Neck": Vector3(-18, 0, 0),
				"LegL": Vector3(78, 0, -4), "KneeL": Vector3(-82, 0, 0), "LegR": Vector3(78, 0, 4), "KneeR": Vector3(-82, 0, 0),
				"ArmL": Vector3(28, 0, -8), "ElbowL": Vector3(-70, 0, 0),
				"ArmR": Vector3(28 + 25.0 * play, 0, 8), "ElbowR": Vector3(-70 + 40.0 * play, 0, 0)}
			_look(m, p, delta, 0.6)
			pose._apply(p)
			return
	# The rest stand or kneel: BodyPose does the legs, the breathing and the feet, then the arms are theirs.
	pose.crouch = 1.0 if m["id"] == "mechanic" else 0.0
	pose.update(delta)
	var arms := {}
	match m["id"]:
		"cook":   # stirring the pot
			arms = {"ArmR": Vector3(48, 10.0 * sin(t * 3.0), 12.0 + 6.0 * cos(t * 3.0)), "ElbowR": Vector3(-35, 0, 0),
				"ArmL": Vector3(30, 0, -12), "ElbowL": Vector3(-55, 0, 0), "Neck": Vector3(-28, 0, 0)}
		"mechanic":   # working on the generator with a wrench
			var turn := sin(t * 4.0)
			arms = {"ArmR": Vector3(62 + 12.0 * turn, 0, 6), "ElbowR": Vector3(-30 - 10.0 * turn, 0, 0),
				"ArmL": Vector3(70, 0, -10), "ElbowL": Vector3(-25, 0, 0), "Neck": Vector3(-12, 0, 0)}
		"coffee":   # a mug at the chest, a sip now and then
			var sip := maxf(0.0, sin(t * 0.45)) ** 10.0
			arms = {"ArmR": Vector3(22 + 18.0 * sip, 0, 10), "ElbowR": Vector3(-95 - 35.0 * sip, 0, 0),
				"ArmL": Vector3(5, 0, -8), "Neck": Vector3(12.0 * sip, 0, 0)}
	for key: String in arms:
		var joint := pose.joint(key)
		if joint != null:
			var a: Vector3 = arms[key]
			joint.rotation = Vector3(deg_to_rad(a.x), deg_to_rad(a.y), deg_to_rad(a.z))
	if m["id"] != "mechanic":
		var neck := {"Neck": arms.get("Neck", Vector3.ZERO)}
		_look(m, neck, delta, 1.0)
		var n: Vector3 = neck["Neck"]
		pose.joint("Neck").rotation = Vector3(deg_to_rad(n.x), deg_to_rad(n.y), deg_to_rad(n.z))


## Turns `p`'s head toward you when you're near (at most `most` of a right angle), easing there and back.
func _look(m: Dictionary, p: Dictionary, delta: float, most: float) -> void:
	var model: Node3D = m["model"]
	var want := 0.0
	if walker != null:
		var to := model.to_local(walker.global_position)
		to.y = 0.0
		if to.length() < LOOK_REACH and to.length() > 0.3:
			want = clampf(atan2(-to.x, -to.z), -PI / 2.0 * most, PI / 2.0 * most)
	m["look"] = move_toward(float(m["look"]), want, delta * 2.5)
	var neck: Vector3 = p.get("Neck", Vector3.ZERO)
	p["Neck"] = Vector3(neck.x * (1.0 - absf(float(m["look"])) / (PI / 2.0)), neck.y + rad_to_deg(float(m["look"])), neck.z)
