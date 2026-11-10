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
## They don't stay put (owner, 0.34.2: "they should move too", "everyone can sleep but not at the same time", "they
## walk too slow"): the hideout has things to do (the bunk, the stove, cards, a meal, the TV, the den's booth and bar, the war
## table, the generator, a coffee by the range), one person each. Everyone has a favourite they go back
## to most and stay longest at; when they're done they pick something free and walk there over the walkable area
## (assets/hideout/nav.res, baked by tools/hideout_nav_bake.gd: re-run it after make_hideout.py changes the cave).
const NAV := preload("res://assets/hideout/nav.res")
const WALK_SPEED := 2.4
const LIKES := 4.0           # how much more often they pick their favourite
const STUCK_AFTER := 3.0     # seconds walking without getting closer: give up and pick something else
const SETTLE := 0.6          # seconds to step into place once there
## Who lives here: their look (TraderLooks.CREW) and their favourite thing to do.
const CREW := [["sleeper", "sleep"], ["cook", "cook"], ["cards_a", "cards_a"], ["cards_b", "cards_b"],
	["mechanic", "fix"], ["coffee", "coffee"], ["roam_a", "war"], ["roam_b", "den"]]

var walker: Node3D
## Each one: {"id", "model", "pose", "phase", "look" (radians the head's turned), "next" (seconds to their next sound)};
## the crew also have "act" (what they're doing or walking to), "path", "wait" (seconds left at it), "props".
var members: Array[Dictionary] = []
var _time := 0.0
var _dice := RandomNumberGenerator.new()
## The things to do: {"name", "kind" (the pose), "at" (where they stand, hideout coordinates), "turn" (their yaw there),
## "time" (seconds, from-to), "seat" (a Seats marker or null), "by" (who's on it, or {})}.
var acts: Array[Dictionary] = []
var _nav_map := RID()


func setup(level: Node3D, who: Node3D) -> void:
	walker = who
	if not Reacts.wanted(self):
		return
	_dice.randomize()
	# The traders behind their counters (owner's picks, TraderLooks.PICKED), each busy with their own thing.
	var spots := level.get_node_or_null("Traders") as Node3D
	if spots != null:
		for spot_node: Node in spots.get_children():
			var stand := spot_node as Node3D
			_add("trader_" + String(stand.name), stand.position, stand.basis.z, TraderLooks.look(String(stand.name)))
	_crew(level)
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


## The things to do (from the hideout level: its Life metadata, its seats, the stations, the range and the den), then
## the crew, each starting at their favourite.
func _crew(level: Node3D) -> void:
	var life := level.get_node_or_null("Life") as Node3D
	var seats := level.get_node_or_null("Seats") as Node3D
	if life != null and life.has_meta(&"bed"):
		var head: Vector3 = life.get_meta(&"bed_head")
		_act("sleep", "sleep", (life.get_meta(&"bed") as Vector3) - head * 0.75, head, Vector2(50, 120))   # (lying: +z to the pillow)
	if life != null and life.has_meta(&"steam"):
		var stove: Vector3 = life.get_meta(&"steam")
		var out: Vector3 = life.get_meta(&"fire_dir", Vector3.LEFT)
		_act("cook", "cook", Vector3(stove.x, 0.0, stove.z) + out * 0.85, out, Vector2(30, 70))
	if seats != null:   # (a seat's marker looks the way you face; they sit 0.46 m under it)
		for row: Array in [["cards_a", "cards", "Seat0"], ["cards_b", "cards", "Seat2"], ["eat_a", "eat", "Seat5"],
				["eat_b", "eat", "Seat11"], ["tv_a", "tv", "Seat12"], ["tv_b", "tv", "Seat13"], ["booth", "lounge", "Seat19"],
				["bar_a", "bar", "Seat15"], ["bar_b", "bar", "Seat17"]]:
			var seat := seats.get_node_or_null(row[2] as String) as Node3D
			if seat != null:
				_act(row[0], row[1], seat.position - Vector3.UP * 0.46, seat.basis.z, Vector2(35, 90))
				acts[acts.size() - 1]["seat"] = seat
	if life != null and life.has_meta(&"generator"):
		var gen: Vector3 = life.get_meta(&"generator")
		_act("fix", "fix", Vector3(gen.x, 0.0, gen.z + 0.95), Vector3.BACK, Vector2(30, 70))
	var spot := level.get_node_or_null("Range/Spot") as Node3D
	if spot != null:
		_act("coffee", "coffee", spot.position + Vector3(3.1, 0.0, 1.6), Vector3(0.5, 0.0, 0.8).normalized(), Vector2(25, 60))
	var table := level.get_node_or_null("Stations/war_table") as Node3D
	if table != null:
		_act("war", "war", table.position + Vector3(0.0, 0.0, 2.6), Vector3.BACK, Vector2(25, 60))
	var den := level.get_node_or_null("Hangout") as Node3D
	if den != null:
		_act("den", "stand", den.position, Vector3.BACK, Vector2(30, 70))
	if acts.is_empty():
		return
	var region := NavigationRegion3D.new()
	region.name = "Walkable"
	region.navigation_mesh = NAV
	add_child(region)
	_nav_map = region.get_navigation_map()
	for row: Array in CREW:
		var home := act_named(row[1])
		if home.is_empty() or not home["by"].is_empty():
			continue
		_add(row[0], home["at"], Vector3.BACK)
		var m: Dictionary = members[members.size() - 1]
		m["likes"] = row[1]
		m["path"] = PackedVector3Array()
		m["props"] = {}
		m["chill"] = _dice.randi() % 2
		_arrive(m, home)
		m["settle"] = 1.0
		(m["model"] as Node3D).rotation.y = home["turn"]
		m["wait"] = _dice.randf_range(8.0, (home["time"] as Vector2).y)   # (so they don't all get up at once)


func _act(id: String, kind: String, at: Vector3, back: Vector3, time: Vector2) -> void:
	acts.append({"name": id, "kind": kind, "at": at, "turn": atan2(back.x, back.z), "time": time, "seat": null, "by": {}})


## The thing to do called `id`, or {}.
func act_named(id: String) -> Dictionary:
	for a: Dictionary in acts:
		if a["name"] == id:
			return a
	return {}


## What `m` is doing now ({} on the way somewhere).
func doing(m: Dictionary) -> Dictionary:
	if not m.has("act") or not (m["path"] as PackedVector3Array).is_empty() or float(m.get("settle", 1.0)) < 1.0:
		return {}
	return m["act"]


## Done here: somewhere free to go next (their favourite more often), and the walk there.
func _next(m: Dictionary) -> void:
	if not _nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(_nav_map) == 0:
		m["wait"] = 1.0   # (the map isn't ready for the first frame or two)
		return
	var model: Node3D = m["model"]
	var here: Dictionary = m["act"]
	var total := 0.0
	var free: Array[Dictionary] = []
	for a: Dictionary in acts:
		if a != here and a["by"].is_empty() and not _seat_in_use(a):
			free.append(a)
			total += LIKES if a["name"] == m["likes"] else 1.0
	var roll := _dice.randf() * total
	for a: Dictionary in free:
		roll -= LIKES if a["name"] == m["likes"] else 1.0
		if roll > 0.0:
			continue
		var path := route(model.position, a["at"])
		if path.size() < 2 or path[path.size() - 1].distance_to(a["at"]) > 1.6:
			break   # (can't get there from here: try again in a bit)
		_leave(m)
		a["by"] = m
		m["act"] = a
		m["path"] = path
		m["stuck"] = 0.0
		m["tries"] = 0
		m["best"] = INF
		if a["seat"] != null:
			(a["seat"] as Node3D).set_meta(&"taken", true)   # (HideoutToys won't sit you on someone)
		_show_props(m, "")
		return
	m["wait"] = _dice.randf_range(3.0, 8.0)


## True if you're sat on this one's seat.
func _seat_in_use(a: Dictionary) -> bool:
	var toys := get_parent().get_node_or_null("Toys") as HideoutToys
	return a["seat"] != null and toys != null and toys.seat == a["seat"]


func _leave(m: Dictionary) -> void:
	var a: Dictionary = m.get("act", {})
	if a.is_empty():
		return
	a["by"] = {}
	if a["seat"] != null:
		(a["seat"] as Node3D).remove_meta(&"taken")


## There: steps into place, holds what goes with it, and stays a while (longer at their favourite).
func _arrive(m: Dictionary, a: Dictionary) -> void:
	a["by"] = m
	m["act"] = a
	if a["seat"] != null:
		(a["seat"] as Node3D).set_meta(&"taken", true)
	var model: Node3D = m["model"]
	m["from"] = model.position
	m["from_turn"] = model.rotation.y
	m["settle"] = 0.0
	var time: Vector2 = a["time"]
	m["wait"] = _dice.randf_range(time.x, time.y) * (1.5 if a["name"] == m["likes"] else 1.0)
	m["chill"] = _dice.randi() % 2
	_show_props(m, a["kind"])


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


## One of the crew this frame: walking, stepping into place, or at it until it's time to move on.
func _live(m: Dictionary, delta: float) -> void:
	var pose: BodyPose = m["pose"]
	var model: Node3D = m["model"]
	var a: Dictionary = m["act"]
	pose.speed = 0.0
	if not (m["path"] as PackedVector3Array).is_empty():
		pose.speed = _walk(m, delta)
		var left := model.position.distance_to(a["at"])   # (stuck somewhere: give up and pick something else)
		if left < float(m["best"]) - 0.2:
			m["best"] = left
			m["stuck"] = 0.0
		else:
			m["stuck"] = float(m["stuck"]) + delta
		if float(m["stuck"]) > STUCK_AFTER:   # (held up somewhere: find the way again, then just step on over)
			m["stuck"] = 0.0
			m["tries"] = int(m.get("tries", 0)) + 1
			var again := route(model.position, a["at"]) if int(m["tries"]) < 2 else PackedVector3Array()
			m["path"] = again
			if again.is_empty():
				_arrive(m, a)
		return
	if float(m["settle"]) < 1.0:
		m["settle"] = minf(1.0, float(m["settle"]) + delta / SETTLE)
		var t := smoothstep(0.0, 1.0, float(m["settle"]))
		model.position = (m["from"] as Vector3).lerp(a["at"], t)
		model.rotation.y = lerp_angle(float(m["from_turn"]), float(a["turn"]), t)
		return
	m["wait"] = float(m["wait"]) - delta
	if float(m["wait"]) <= 0.0:
		_next(m)


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
		model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, delta * 10.0))
	m["path"] = path
	if path.is_empty():
		_arrive(m, m["act"])
		return 0.0
	return WALK_SPEED


## Only what goes with `kind` shows in their hands (a spoon cooking or eating, the wrench, a mug, their cards).
func _show_props(m: Dictionary, kind: String) -> void:
	var want: String = {"cook": "spoon", "eat": "spoon", "fix": "wrench", "coffee": "mug", "tv": "mug", "bar": "mug",
		"cards": "cards"}.get(kind, "")
	var props: Dictionary = m["props"]
	for key: String in props:
		for box: Node3D in props[key]:
			box.visible = key == want


## What they hold or have in front of them: the cook's spoon, the mechanic's wrench, a mug, cards on the table.
func _props() -> void:
	for m: Dictionary in members:
		var pose: BodyPose = m["pose"]
		match m["id"]:
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
		if m.has("props"):   # (the crew: everything they might hold, shown by what they're doing)
			var props: Dictionary = m["props"]
			props["spoon"] = [_box(pose.joint("ElbowR"), Vector3(0.025, 0.4, 0.025), Vector3(0, -0.36, -0.08), Color(0.5, 0.5, 0.52), Vector3(-50, 0, 0))]
			props["wrench"] = [_box(pose.joint("ElbowR"), Vector3(0.03, 0.03, 0.26), Vector3(0, -0.34, -0.1), Color(0.55, 0.56, 0.58))]
			props["mug"] = [_box(pose.joint("ElbowR"), Vector3(0.08, 0.1, 0.08), Vector3(0, -0.36, -0.06), Color(0.85, 0.85, 0.8))]
			props["cards"] = []
			for side: String in ["ElbowL", "ElbowR"]:   # (a hand of cards in each)
				props["cards"].append(_box(pose.joint(side), Vector3(0.09, 0.012, 0.12), Vector3(0, -0.35, -0.04), Color(0.92, 0.9, 0.84)))
			_show_props(m, (m["act"] as Dictionary)["kind"])
	var a := act_named("cards_a")
	var b := act_named("cards_b")
	if not a.is_empty() and not b.is_empty():   # (the pile between them, and a few cards played)
		var mid: Vector3 = ((a["at"] as Vector3) + (b["at"] as Vector3)) / 2.0
		var table := Vector3(mid.x, 0.78, mid.z)
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
		if m.has("act"):
			_live(m, delta)
		_pose(m, delta)
		m["next"] = float(m["next"]) - delta
		if float(m["next"]) <= 0.0:
			_sound(m)


## Their sounds, heard only close by: snoring, the wrench on the generator.
func _sound(m: Dictionary) -> void:
	var model: Node3D = m["model"]
	match doing(m).get("kind", ""):
		"sleep":
			m["next"] = SNORE_EVERY
			WorldSounds.at_soft(self, SNORE, model.global_position + Vector3.UP * 0.3, -14.0, NEAR_SNORE, _dice.randf_range(0.95, 1.05))
		"fix":
			m["next"] = _dice.randf_range(3.0, 9.0)
			WorldSounds.at_soft(self, WRENCH, model.global_position + Vector3(0, 0.6, -0.5), -12.0, NEAR_WRENCH, _dice.randf_range(0.9, 1.1))
		_:
			m["next"] = 2.0


func _pose(m: Dictionary, delta: float) -> void:
	var pose: BodyPose = m["pose"]
	var t := _time + float(m["phase"])
	var p := {}
	var kind := String(m["id"])   # (the traders: their own thing; the crew: what they're doing, or walking)
	if m.has("act"):
		kind = doing(m).get("kind", "walk")
	match kind:
		"sleep":   # on their back, one arm across the chest, head to one side, breathing slow
			var breath := sin(t * TAU / SNORE_EVERY)
			p = {"hips_pos": Vector3(0, 0.12, 0.62), "hips_rot": Vector3(90, 0, 0), "Spine": Vector3(2.0 * breath, 0, 0),
				"Neck": Vector3(0, 28, 0), "ArmL": Vector3(35, 0, 30), "ElbowL": Vector3(-95, 0, 0),
				"ArmR": Vector3(0, 0, 10), "ElbowR": Vector3(-10, 0, 0), "LegL": Vector3(0, 0, -6),
				"LegR": Vector3(4, 0, 8), "KneeR": Vector3(-14, 0, 0)}
			pose._apply(_elbows(p))
			return
		"cards", "eat", "tv", "bar", "lounge":   # sat down
			p = {"hips_pos": Vector3(0, 0.52, 0.02), "Spine": Vector3(-8, 0, 0), "Neck": Vector3(-18, 0, 0),
				"LegL": Vector3(78, 0, -4), "KneeL": Vector3(-82, 0, 0), "LegR": Vector3(78, 0, 4), "KneeR": Vector3(-82, 0, 0)}
			match kind:
				"cards":   # cards held up, now and then one goes down
					var play := maxf(0.0, sin(t * 0.7)) ** 8.0
					p.merge({"ArmL": Vector3(28, 0, -8), "ElbowL": Vector3(-70, 0, 0),
						"ArmR": Vector3(28 + 25.0 * play, 0, 8), "ElbowR": Vector3(-70 + 40.0 * play, 0, 0)}, true)
				"eat":   # a spoonful now and then, the other arm on the table
					var bite := maxf(0.0, sin(t * 1.1)) ** 3.0
					p.merge({"ArmL": Vector3(30, 0, -10), "ElbowL": Vector3(-60, 0, 0), "ArmR": Vector3(30 + 22.0 * bite, 0, 10),
						"ElbowR": Vector3(-60 - 55.0 * bite, 0, 0), "Neck": Vector3(-22 + 14.0 * bite, 0, 0)}, true)
				"tv", "bar":   # leant back watching the TV (or at the den's bar), a mug, a sip now and then
					var sip := maxf(0.0, sin(t * 0.4)) ** 10.0
					p.merge({"Spine": Vector3(12 if kind == "tv" else -4, 0, 0), "Neck": Vector3(-6 + 10.0 * sip, 0, 0), "ArmL": Vector3(12, 0, -10),
						"ElbowL": Vector3(-45, 0, 0), "ArmR": Vector3(20 + 18.0 * sip, 0, 10), "ElbowR": Vector3(-90 - 35.0 * sip, 0, 0)}, true)
				_:   # the den's booth: leant back, one arm along the seat back
					p.merge({"Spine": Vector3(14, 0, 0), "Neck": Vector3(-4, 0, 0), "ArmL": Vector3(-10, 0, -70),
						"ElbowL": Vector3(-20, 0, 0), "ArmR": Vector3(14, 0, 8), "ElbowR": Vector3(-50, 0, 0)}, true)
			_look(m, p, delta, 0.6)
			pose._apply(_elbows(p))
			return
	# The rest stand or kneel: BodyPose does the legs, the breathing and the feet, then the arms are theirs.
	pose.crouch = 1.0 if kind == "fix" else 0.0
	pose.update(delta)
	var arms := {}
	match kind:
		"cook":   # stirring the pot
			arms = {"ArmR": Vector3(68, 10.0 * sin(t * 3.0), 10.0 + 6.0 * cos(t * 3.0)), "ElbowR": Vector3(-18, 0, 0),
				"ArmL": Vector3(30, 0, -12), "ElbowL": Vector3(-55, 0, 0), "Neck": Vector3(-28, 0, 0)}
		"fix":   # working on the generator with a wrench
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
		"war":   # leant on the war table over the map, now and then pointing at something
			var point := maxf(0.0, sin(t * 0.3)) ** 6.0
			arms = {"ArmL": Vector3(58, 0, -14), "ElbowL": Vector3(-25, 0, 0), "ArmR": Vector3(58 + 25.0 * point, 0, 14 - 6.0 * point),
				"ElbowR": Vector3(-25 + 20.0 * point, 0, 0), "Neck": Vector3(-35, 25.0 * sin(t * 0.2), 0)}
		"stand":   # stood about: arms crossed or hands on hips, talking with hands if someone's there to talk to
			if _company(m):
				var talk := sin(t * 1.7)
				arms = {"ArmR": Vector3(40 + 12.0 * talk, 0, 12), "ElbowR": Vector3(-60 + 15.0 * talk, 0, 0),
					"ArmL": Vector3(4, 0, -6), "Neck": Vector3(8.0 * sin(t * 0.9), 0, 0)}
			elif int(m["chill"]) == 0:
				arms = {"ArmL": Vector3(38, 0, -16), "ElbowL": Vector3(-100, 0, 0), "ArmR": Vector3(38, 0, 16),
					"ElbowR": Vector3(-100, 0, 0), "Neck": Vector3(0, 30.0 * sin(t * 0.35), 0)}
			else:
				arms = {"ArmL": Vector3(-10, 0, -38), "ElbowL": Vector3(-80, 0, 0), "ArmR": Vector3(-10, 0, 38),
					"ElbowR": Vector3(-80, 0, 0), "Neck": Vector3(-6, 35.0 * sin(t * 0.25), 0)}
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
	if kind != "fix":
		var neck := {"Neck": arms.get("Neck", Vector3.ZERO)}
		_look(m, neck, delta, 1.0)
		var n: Vector3 = neck["Neck"]
		pose.joint("Neck").rotation = Vector3(deg_to_rad(n.x), deg_to_rad(n.y), deg_to_rad(n.z))


## True if one of the others is doing something close by (someone to talk to).
func _company(m: Dictionary) -> bool:
	var at := (m["model"] as Node3D).position
	for other: Dictionary in members:
		if other != m and other.has("act") and not doing(other).is_empty() and (other["model"] as Node3D).position.distance_to(at) < 3.0:
			return true
	return false


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
