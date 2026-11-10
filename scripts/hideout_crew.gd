class_name HideoutCrew
extends Node3D
## The crew (lively hideout, owner 2026-11-09: "YESSSSSS OMG YES"): other PMCs living in the hideout, each at one
## thing: asleep in a bunk, cooking at the stove, two playing cards in the mess, one fixing the generator, one with a
## coffee by the range. The ones awake look round at you when you come close. Looks only: nobody collides, nothing is
## sent online, and a headless run (the server, the tests) shows none of them unless `force_reacts` is set.
## Where they are comes from the hideout level: its seats, its Life node's metadata (make_hideout.py) and the range.

const CHARACTER_MODEL := preload("res://assets/models/characters/trader.glb")   # (its own clean model, 2026-11-09)
const PIXEL_MODEL_SCRIPT := preload("res://scripts/pixel_model.gd")
const SNORE := preload("res://audio/world/snore.wav")
const WRENCH := preload("res://audio/world/wrench.wav")
const LOOK_REACH := 4.5      # metres: the ones awake turn their heads to you nearer than this
const SNORE_EVERY := 4.2     # seconds a breath, asleep
const NEAR_SNORE := 6.0
const NEAR_WRENCH := 11.0
## Two of them walk round (owner, 0.34.1: "everyone seems still", "make sure the dudes can path to the secret room
## and chill there"): from spot to spot over the hideout's walkable area (assets/hideout/nav.res, baked by
## tools/hideout_nav_bake.gd: re-run it after make_hideout.py changes the cave), hanging about at each a while.
const NAV := preload("res://assets/hideout/nav.res")
const WALK_SPEED := 1.25
const HANG_ABOUT := Vector2(20.0, 60.0)    # seconds at a spot before moving on
const ROAMERS := ["roam_a", "roam_b"]

var walker: Node3D
## Each one: {"id", "model", "pose", "phase", "look" (radians the head's turned), "next" (seconds to their next sound)}.
var members: Array[Dictionary] = []
var _time := 0.0
var _dice := RandomNumberGenerator.new()
## Where the walkers go: [where (hideout coordinates), name]; the den (the secret room) is always one of them.
var hangouts: Array = []
var _nav_map := RID()


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
		_add("cook", Vector3(stove.x, 0.0, stove.z) + out * 0.85, out)
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
	# The traders behind their counters (owner's picks, TraderLooks.PICKED), each busy with their own thing.
	var spots := level.get_node_or_null("Traders") as Node3D
	if spots != null:
		for spot_node: Node in spots.get_children():
			var stand := spot_node as Node3D
			_add("trader_" + String(stand.name), stand.position, stand.basis.z, TraderLooks.look(String(stand.name)))
	_roamers(level)
	_props()


## One of them at `at` (on the floor), facing away from `back` (the model faces its -z).
func _add(id: String, at: Vector3, back: Vector3, look := {}) -> void:
	var model := CHARACTER_MODEL.instantiate()
	model.set_script(PIXEL_MODEL_SCRIPT)
	(model as PixelModel).randomize_outfit = false
	model.name = id.capitalize().replace(" ", "")
	add_child(model)
	(model as PixelModel).pick_outfit(look if not look.is_empty() else TraderLooks.CREW[id])
	model.position = at
	model.rotation.y = atan2(back.x, back.z)
	var gun := model.get_node_or_null("Gun") as Node3D
	if gun != null:
		gun.visible = false
	var pose := BodyPose.new(model)
	pose.armed = false
	members.append({"id": id, "model": model, "pose": pose, "phase": _dice.randf() * TAU, "look": 0.0,
		"next": _dice.randf_range(1.0, 6.0), "nod": 0.0, "near": false})


## The two who walk round: they start at the war table and the den, then go from spot to spot.
func _roamers(level: Node3D) -> void:
	var region := NavigationRegion3D.new()
	region.name = "Walkable"
	region.navigation_mesh = NAV
	add_child(region)
	_nav_map = region.get_navigation_map()
	var spots := {"den": level.get_node_or_null("Hangout"), "war_table": level.get_node_or_null("Stations/war_table"),
		"workbench": level.get_node_or_null("Stations/workbench"), "range": level.get_node_or_null("Range/Spot"),
		"mess": level.get_node_or_null("Quarters"), "traders": level.get_node_or_null("Stations/valuables")}
	for id: String in spots:
		var node := spots[id] as Node3D
		if node != null:
			var at := node.position
			at += {"war_table": Vector3(0.0, 0.0, 2.6), "workbench": Vector3(0.0, 0.0, -2.0), "range": Vector3(1.5, 0.0, 1.0),
				"mess": Vector3(1.5, 0.0, -4.5), "traders": Vector3(0.0, 0.0, -2.5)}.get(id, Vector3.ZERO)   # (by it, on the floor)
			hangouts.append([at, id])
	if hangouts.is_empty():
		return
	for k in ROAMERS.size():
		var start: Array = hangouts[0] if k == 1 else hangouts[mini(1, hangouts.size() - 1)]
		_add(ROAMERS[k], start[0] + Vector3(k * 0.8, 0.0, 0.6), Vector3(0, 0, 1))
		var m: Dictionary = members[members.size() - 1]
		m["path"] = PackedVector3Array()
		m["at"] = start[1]
		m["wait"] = _dice.randf_range(4.0, 15.0) + k * 10.0
		m["chill"] = _dice.randi() % 3


## A walker's next spot: somewhere they're not, the den more often than the rest.
func _next_spot(m: Dictionary) -> void:
	if not _nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(_nav_map) == 0:
		m["wait"] = 1.0   # (the map isn't ready for the first frame or two)
		return
	var choices := hangouts.filter(func(h: Array) -> bool: return h[1] != m["at"])
	if choices.is_empty():
		return
	var pick: Array = choices[_dice.randi() % choices.size()]
	for h: Array in choices:   # (the den: a third of the time, it's where they go to chill)
		if h[1] == "den" and _dice.randf() < 0.35:
			pick = h
	var model: Node3D = m["model"]
	var path := route(model.position, (pick[0] as Vector3) + Vector3(_dice.randf_range(-1.0, 1.0), 0.0, _dice.randf_range(-1.0, 1.0)))
	if path.size() < 2:
		m["wait"] = _dice.randf_range(5.0, 10.0)
		return
	m["path"] = path
	m["at"] = pick[1]
	m["chill"] = _dice.randi() % 3


## A walkable route from `a` to `b` (both in the hideout's coordinates, like the path it gives back).
func route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var xf := global_transform
	var from := NavigationServer3D.map_get_closest_point(_nav_map, xf * a)
	var to := NavigationServer3D.map_get_closest_point(_nav_map, xf * b)
	var path := NavigationServer3D.map_get_path(_nav_map, from, to, true)
	var back := xf.affine_inverse()
	for k in path.size():
		path[k] = back * path[k]
	return path


## Walking along their path (the feet on the walkable area: it sits a cell above the floor).
func _walk(m: Dictionary, delta: float) -> float:
	var path: PackedVector3Array = m["path"]
	var model: Node3D = m["model"]
	var step := WALK_SPEED * delta
	while path.size() > 0 and step > 0.0:
		var goal := path[0] - Vector3.UP * 0.12
		var to := goal - model.position
		var flat := Vector2(to.x, to.z).length()
		if flat <= step:
			model.position = goal
			step -= flat
			path.remove_at(0)
			continue
		model.position += to / maxf(to.length(), 0.001) * step
		step = 0.0
		var want := atan2(-to.x, -to.z)   # (the model faces its -z: its back to where it came from)
		model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, delta * 8.0))
	m["path"] = path
	if path.is_empty():
		m["wait"] = _dice.randf_range(HANG_ABOUT.x, HANG_ABOUT.y)
		return 0.0
	return WALK_SPEED


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
			"trader_guns":   # a rifle across the hands, being cleaned
				_box(pose.joint("ElbowR"), Vector3(0.05, 0.08, 0.75), Vector3(0.12, -0.34, -0.1), Color(0.18, 0.18, 0.19), Vector3(0, -70, 0))
				_box(pose.joint("ElbowL"), Vector3(0.07, 0.03, 0.09), Vector3(0, -0.36, -0.02), Color(0.85, 0.82, 0.72))
			"trader_supplies":   # a wad of cash
				_box(pose.joint("ElbowL"), Vector3(0.07, 0.04, 0.14), Vector3(0, -0.35, -0.06), Color(0.42, 0.6, 0.38))
				_box(pose.joint("ElbowR"), Vector3(0.07, 0.006, 0.14), Vector3(0, -0.35, -0.06), Color(0.42, 0.6, 0.38))
			"trader_valuables":   # a gold watch held up to the loupe
				_box(pose.joint("ElbowR"), Vector3(0.05, 0.05, 0.015), Vector3(0, -0.37, -0.05), Color(0.85, 0.68, 0.25))
			"trader_ming":   # a deck in each hand, shuffled together
				for side: String in ["ElbowL", "ElbowR"]:
					_box(pose.joint(side), Vector3(0.07, 0.04, 0.1), Vector3(0, -0.36, -0.05), Color(0.93, 0.91, 0.86))
			"trader_meds":   # a clipboard and a pen
				_box(pose.joint("ElbowL"), Vector3(0.2, 0.015, 0.27), Vector3(0.04, -0.37, -0.08), Color(0.55, 0.42, 0.28))
				_box(pose.joint("ElbowR"), Vector3(0.012, 0.012, 0.11), Vector3(0, -0.36, -0.05), Color(0.15, 0.15, 0.18))
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
	if String(parent.name).begins_with("Elbow"):   # (written for a forearm bent the old way: see _elbows)
		at.z = -at.z
		turn.x = -turn.x
	parent.add_child(box)
	box.position = at
	box.rotation_degrees = turn
	return box


## The poses here were written with elbows bending the wrong way (owner, 0.34.1: "that guy's arm is backwards"): on
## the character models a positive elbow bend brings the forearm forward, so their elbow angles are flipped here.
static func _elbows(p: Dictionary) -> Dictionary:
	for key: String in ["ElbowL", "ElbowR"]:
		if p.has(key):
			var a: Vector3 = p[key]
			p[key] = Vector3(-a.x, a.y, a.z)
	return p


func _process(delta: float) -> void:
	_time += delta
	for m: Dictionary in members:
		if m.has("path"):
			var pose: BodyPose = m["pose"]
			if (m["path"] as PackedVector3Array).is_empty():
				m["wait"] = float(m["wait"]) - delta
				if float(m["wait"]) <= 0.0:
					_next_spot(m)
				pose.speed = 0.0
			else:
				pose.speed = _walk(m, delta)
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
			pose._apply(_elbows(p))
			return
		"cards_a", "cards_b":   # sat at the table, cards held up, now and then one goes down
			var play := maxf(0.0, sin(t * 0.7)) ** 8.0
			p = {"hips_pos": Vector3(0, 0.52, 0.02), "Spine": Vector3(-8, 0, 0), "Neck": Vector3(-18, 0, 0),
				"LegL": Vector3(78, 0, -4), "KneeL": Vector3(-82, 0, 0), "LegR": Vector3(78, 0, 4), "KneeR": Vector3(-82, 0, 0),
				"ArmL": Vector3(28, 0, -8), "ElbowL": Vector3(-70, 0, 0),
				"ArmR": Vector3(28 + 25.0 * play, 0, 8), "ElbowR": Vector3(-70 + 40.0 * play, 0, 0)}
			_look(m, p, delta, 0.6)
			pose._apply(_elbows(p))
			return
	# The rest stand or kneel: BodyPose does the legs, the breathing and the feet, then the arms are theirs.
	pose.crouch = 1.0 if m["id"] == "mechanic" else 0.0
	pose.update(delta)
	var arms := {}
	match m["id"]:
		"cook":   # stirring the pot
			arms = {"ArmR": Vector3(68, 10.0 * sin(t * 3.0), 10.0 + 6.0 * cos(t * 3.0)), "ElbowR": Vector3(-18, 0, 0),
				"ArmL": Vector3(30, 0, -12), "ElbowL": Vector3(-55, 0, 0), "Neck": Vector3(-28, 0, 0)}
		"mechanic":   # working on the generator with a wrench
			var turn := sin(t * 4.0)
			arms = {"ArmR": Vector3(62 + 12.0 * turn, 0, 6), "ElbowR": Vector3(-30 - 10.0 * turn, 0, 0),
				"ArmL": Vector3(70, 0, -10), "ElbowL": Vector3(-25, 0, 0), "Neck": Vector3(-12, 0, 0)}
		"trader_guns":   # wiping down a rifle held across the body
			var wipe := sin(t * 2.2)
			arms = {"ArmR": Vector3(38, 0, 12), "ElbowR": Vector3(-75, 0, 0), "ArmL": Vector3(40 + 12.0 * wipe, 30.0 * wipe, -6),
				"ElbowL": Vector3(-70, 0, 0), "Neck": Vector3(-24, 0, 0)}
		"trader_supplies":   # counting cash, a note at a time
			var flick := maxf(0.0, sin(t * 3.4)) ** 4.0
			arms = {"ArmL": Vector3(30, 0, -6), "ElbowL": Vector3(-80, 0, 0), "ArmR": Vector3(30 + 18.0 * flick, 0, 10),
				"ElbowR": Vector3(-78 - 14.0 * flick, -10.0 * flick, 0), "Neck": Vector3(-20, 0, 0)}
		"trader_valuables":   # turning a watch over under the loupe
			arms = {"ArmR": Vector3(55, 0, 22), "ElbowR": Vector3(-115 + 10.0 * sin(t * 0.6), 45.0 * sin(t * 0.9), 0), "ArmL": Vector3(8, 0, -6),
				"ElbowL": Vector3(-20, 0, 0), "Neck": Vector3(-6, 0, 0)}
		"trader_ming":   # shuffling: the decks riffle together, again and again
			var riffle := sin(t * 5.0)
			arms = {"ArmL": Vector3(35, 0, -8 + 6.0 * riffle), "ElbowL": Vector3(-65, 0, 0), "ArmR": Vector3(35, 0, 8 + 6.0 * riffle),
				"ElbowR": Vector3(-65, 0, 0), "Neck": Vector3(-14, 0, 0)}
		"trader_meds":   # writing notes on a clipboard
			var write := sin(t * 6.0) * 2.5
			arms = {"ArmL": Vector3(35, 0, -4), "ElbowL": Vector3(-80, 0, 0), "ArmR": Vector3(38, 4.0 * write, 6),
				"ElbowR": Vector3(-82 + 3.0 * write, 0, 0), "Neck": Vector3(-26, 0, 0)}
		"roam_a", "roam_b":   # walking: BodyPose swings the arms; stood about: arms crossed, hands on hips or one up
			if (m["path"] as PackedVector3Array).is_empty():
				match int(m["chill"]):
					0:
						arms = {"ArmL": Vector3(38, 0, -16), "ElbowL": Vector3(-100, 0, 0), "ArmR": Vector3(38, 0, 16),
							"ElbowR": Vector3(-100, 0, 0), "Neck": Vector3(0, 30.0 * sin(t * 0.35), 0)}
					1:
						arms = {"ArmL": Vector3(-10, 0, -38), "ElbowL": Vector3(-80, 0, 0), "ArmR": Vector3(-10, 0, 38),
							"ElbowR": Vector3(-80, 0, 0), "Neck": Vector3(-6, 35.0 * sin(t * 0.25), 0)}
					_:
						var talk := sin(t * 1.7)
						arms = {"ArmR": Vector3(40 + 12.0 * talk, 0, 12), "ElbowR": Vector3(-60 + 15.0 * talk, 0, 0),
							"ArmL": Vector3(4, 0, -6), "Neck": Vector3(8.0 * sin(t * 0.9), 20.0 * sin(t * 0.4), 0)}
		"coffee":   # a mug at the chest, a sip now and then
			var sip := maxf(0.0, sin(t * 0.45)) ** 10.0
			arms = {"ArmR": Vector3(22 + 18.0 * sip, 0, 10), "ElbowR": Vector3(-95 - 35.0 * sip, 0, 0),
				"ArmL": Vector3(5, 0, -8), "Neck": Vector3(12.0 * sip, 0, 0)}
	arms = _elbows(arms)
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
	# (nobody near: they glance about now and then, owner 0.34.1: "everyone seems still")
	var want := sin(_time * 0.31 + float(m["phase"]) * 3.0) ** 3 * 0.7 * most
	var close := false
	if walker != null:
		var to := model.to_local(walker.global_position)
		to.y = 0.0
		if to.length() < LOOK_REACH and to.length() > 0.3:
			want = clampf(atan2(-to.x, -to.z), -PI / 2.0 * most, PI / 2.0 * most)
			close = true
	m["look"] = move_toward(float(m["look"]), want, delta * 2.5)
	# The traders nod to you when you come up to the counter.
	var near := close and String(m["id"]).begins_with("trader_")
	if near and not bool(m["near"]):
		m["nod"] = 1.0
	m["near"] = near
	m["nod"] = maxf(0.0, float(m["nod"]) - delta * 1.6)
	if float(m["nod"]) > 0.0:
		var nd: Vector3 = p.get("Neck", Vector3.ZERO)
		p["Neck"] = nd + Vector3(-16.0 * sin(PI * (1.0 - float(m["nod"]))), 0, 0)
	var neck: Vector3 = p.get("Neck", Vector3.ZERO)
	p["Neck"] = Vector3(neck.x * (1.0 - absf(float(m["look"])) / (PI / 2.0)), neck.y + rad_to_deg(float(m["look"])), neck.z)
