class_name HideoutCat
extends Node3D
## The hideout's cat (lively hideout, owner 2026-11-09: a pet, "do cat"). It lives by the stove: it wanders round the
## bunker, sits and washes, loafs, naps by the fire, and now and then comes over to you. Walk up and press USE to pet
## it: it shuts its eyes, lifts its tail and purrs (heard only up close). Looks only: it doesn't collide, nothing is
## sent online, and a headless run (the server, the tests) has no cat unless `force_reacts` is set.
## It finds its way with the hideout's own colliders: a straight line it can walk (rays at its height) and the floor
## under it (a ray down), so it never walks through a wall or off a ledge.

const PURR := preload("res://audio/world/purr.wav")
const MEOW := preload("res://audio/world/meow.wav")
const WALK_SPEED := 0.55        # metres a second, strolling
const TROT_SPEED := 1.1         # coming over to you
const PET_REACH := 1.7          # metres: how close you have to be to pet it
const PET_TIME := 4.5           # seconds it purrs after a pet
const HOME_REACH := 14.0        # it heads back towards the stove when it's further than this
const NEAR_PURR := 5.0
const NEAR_MEOW := 10.0
const STEP_UP := 0.3            # the most the floor may rise or drop in one go
const WALLS := 1 | 512          # what it can't walk through: the world and the props (BoxMap.PROPS_LAYER)
const SIZE := 1.15              # (the characters are big: a cat to match them)

## What it's doing: "walk", "sit", "groom", "loaf", "sleep", "petted".
var state := "sit"
var walker: Node3D
var home := Vector3.ZERO        # where it sleeps: by the stove (in the hideout's coordinates)
var target := Vector3.ZERO      # where it's walking to
var pets := 0                   # times petted (for the tests)
var walked := 0.0               # metres walked (for the tests)
var purr: AudioStreamPlayer3D
var body: Node3D
var head: Node3D
var tail: Array[Node3D] = []
var legs: Array[Node3D] = []    # front left, front right, back left, back right
var eyes_open: Node3D
var eyes_shut: Node3D
var _left := 2.0                # seconds left of what it's doing
var _coming := false            # walking over to you
var _phase := 0.0
var _time := 0.0
var _floor := 0.0
var _dice := RandomNumberGenerator.new()
var _on := false


func setup(level: Node3D, who: Node3D) -> void:
	walker = who
	if not Reacts.wanted(self):
		return
	_on = true
	_dice.randomize()
	var life := level.get_node_or_null("Life") as Node3D
	if life != null and life.has_meta(&"fire"):
		var fire: Vector3 = life.get_meta(&"fire")
		var out: Vector3 = life.get_meta(&"fire_dir", Vector3.LEFT)
		home = Vector3(fire.x, 0.0, fire.z) + out * 1.0 + out.cross(Vector3.UP) * 0.9   # (by the fire, beside the cook)
	else:
		home = (level.get_node("Spawn") as Node3D).position if level.has_node("Spawn") else Vector3.ZERO
	position = home
	rotation.y = _dice.randf() * TAU
	_build()
	purr = AudioStreamPlayer3D.new()
	purr.name = "Purr"
	purr.stream = Ambience.looped(PURR)
	purr.volume_db = -12.0
	purr.unit_size = 1.2
	purr.max_distance = NEAR_PURR
	purr.bus = Hearing.world_bus()
	purr.position = Vector3(0.0, 0.25, -0.2)
	add_child(purr)
	_start("sleep", _dice.randf_range(10.0, 30.0))


func _ready() -> void:
	set_physics_process(Reacts.wanted(self))


## Is the cat close enough, and in front of you, to pet (or nil)?
func in_reach() -> bool:
	if not _on or walker == null or state == "petted":
		return false
	var to := global_position - walker.global_position
	if absf(to.y) > 1.2:
		return false
	to.y = 0.0
	var d := to.length()
	if d > PET_REACH:
		return false
	var ahead: Vector3 = walker.call(&"facing") if walker.has_method(&"facing") else Vector3.FORWARD
	return d < 0.6 or ahead.dot(to / d) > 0.45


## You petting it: it stops, turns to you, shuts its eyes and purrs.
func pet() -> void:
	if not _on:
		return
	pets += 1
	_face(walker.global_position)
	_start("petted", PET_TIME)
	if not purr.playing:
		purr.play()


func _physics_process(delta: float) -> void:
	if not _on:
		return
	_time += delta
	_left -= delta
	if state == "walk":
		_walk(delta)
	elif _left <= 0.0:
		_next()
	if state != "petted" and purr.playing:
		purr.volume_db = move_toward(purr.volume_db, -40.0, delta * 20.0)
		if purr.volume_db <= -39.0:
			purr.stop()
	elif state == "petted":
		purr.volume_db = move_toward(purr.volume_db, -12.0, delta * 30.0)
	_pose(delta)


## What it does next, once it's done with this.
func _next() -> void:
	var near_you := walker != null and walker.global_position.distance_to(global_position) < 7.0 \
		and absf(walker.global_position.y - global_position.y) < 1.0
	if state == "petted" and _dice.randf() < 0.5:
		_start("loaf", _dice.randf_range(6.0, 14.0))   # (happy where it is for a bit)
		return
	var roll := _dice.randf()
	var by_home := position.distance_to(home) < 1.5
	if near_you and roll < 0.22 and _go_to(walker.position, true):
		return
	if by_home and roll < 0.35:
		_start("sleep", _dice.randf_range(25.0, 70.0))
	elif roll < 0.6:
		if not _wander():
			_start("sit", _dice.randf_range(2.0, 4.0))
	elif roll < 0.75:
		_start("groom", _dice.randf_range(4.0, 8.0))
	elif roll < 0.88:
		_start("sit", _dice.randf_range(4.0, 9.0))
	else:
		_start("loaf", _dice.randf_range(8.0, 18.0))


func _start(what: String, seconds: float) -> void:
	state = what
	_left = seconds


## A stroll somewhere it can walk to: a few metres off, back towards the stove when it's wandered far.
func _wander() -> bool:
	var back := position.distance_to(home) > HOME_REACH or _dice.randf() < 0.15
	for attempt in 10:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, _dice.randf() * TAU)
		if back:
			var to_home := home - position
			to_home.y = 0.0
			if to_home.length() > 0.3:
				dir = to_home.normalized().rotated(Vector3.UP, _dice.randf_range(-0.6, 0.6))
		var reach := _dice.randf_range(1.5, 4.5)
		if back and attempt < 5:
			reach = minf(reach * 1.5, position.distance_to(home))
		if _go_to(position + dir * reach, false):
			return true
	return false


## Starts walking to `spot` (hideout coordinates) if it can get there in a straight line; false if it can't.
func _go_to(spot: Vector3, coming: bool) -> bool:
	var flat := spot - position
	flat.y = 0.0
	if coming:   # (stop short of your feet)
		var d := flat.length()
		if d < 1.2:
			return false
		flat = flat * ((d - 0.8) / d)
	if flat.length() < 0.4:
		return false
	var end := position + flat
	var floor_y := _floor_at(end)
	if is_inf(floor_y) or absf(floor_y - position.y) > STEP_UP * 2.0:
		return false
	end.y = floor_y
	if not _clear(position, end):
		return false
	target = end
	_coming = coming
	_start("walk", flat.length() / (TROT_SPEED if coming else WALK_SPEED) + 3.0)
	return true


## Nothing in the way between `a` and `b` (hideout coordinates) at the cat's height and width.
func _clear(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	var origin: Transform3D = (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	var dir := (b - a)
	dir.y = 0.0
	var side := dir.normalized().cross(Vector3.UP) * 0.14
	for h: float in [0.12, 0.32]:
		for s: float in [-1.0, 0.0, 1.0]:
			var from: Vector3 = origin * (a + Vector3.UP * h + side * s)
			var to: Vector3 = origin * (b + Vector3.UP * h + side * s + dir.normalized() * 0.3)
			var query := PhysicsRayQueryParameters3D.create(from, to, WALLS)
			if not space.intersect_ray(query).is_empty():
				return false
	return true


## The floor's height under `spot` (hideout coordinates), or INF if there's none near.
func _floor_at(spot: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return INF
	var origin: Transform3D = (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	var query := PhysicsRayQueryParameters3D.create(origin * (spot + Vector3.UP * 0.8),
		origin * (spot + Vector3.DOWN * 1.0), WALLS)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return INF
	return (origin.affine_inverse() * (hit["position"] as Vector3)).y


func _walk(delta: float) -> void:
	var to := target - position
	to.y = 0.0
	var d := to.length()
	if _coming and walker != null:   # (you moved off: it gives up following once you're well away)
		if walker.position.distance_to(position) < 1.0:
			d = 0.0
	if d < 0.08 or _left <= 0.0:
		if _coming:
			_face(walker.global_position)
			_start("sit", _dice.randf_range(5.0, 10.0))
			WorldSounds.at_soft(self, MEOW, global_position + Vector3.UP * 0.3, -14.0, NEAR_MEOW, _dice.randf_range(0.95, 1.15))
		else:
			_next()
		_coming = false
		return
	var speed := TROT_SPEED if _coming else WALK_SPEED
	var step := minf(d, speed * delta)
	var dir := to / d
	var want := atan2(dir.x, dir.z) + PI   # (the model faces its -z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 6.0))
	var next := position + dir * step
	var floor_y := _floor_at(next)
	if is_inf(floor_y) or absf(floor_y - position.y) > STEP_UP:
		_start("sit", 2.0)   # (a drop or a step too high: it stops and thinks again)
		_coming = false
		return
	next.y = floor_y
	position = next
	walked += step
	_phase += step / 0.16 * SIZE


## It turns to face `at` (global).
func _face(at: Vector3) -> void:
	var to := at - global_position
	to.y = 0.0
	if to.length() > 0.05:
		global_rotation.y = atan2(to.x, to.z) + PI


# --- The model and its poses ---------------------------------------------------------------------------------------

const ORANGE := Color(0.86, 0.47, 0.18)
const STRIPE := Color(0.62, 0.29, 0.1)
const WHITE := Color(0.95, 0.92, 0.86)
const PINK := Color(0.93, 0.56, 0.6)
const EYE := Color(0.55, 0.78, 0.25)
const DARK := Color(0.09, 0.08, 0.07)
const LEG := 0.17               # leg length (before SIZE)
var _materials := {}


func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.95
		_materials[colour] = m
	return _materials[colour]


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, name_ := "") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	if name_ != "":
		box.name = name_
	box.mesh = mesh
	box.material_override = _material(colour)
	box.position = at
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box


func _joint(parent: Node3D, at: Vector3, name_: String) -> Node3D:
	var j := Node3D.new()
	j.name = name_
	j.position = at
	parent.add_child(j)
	return j


## A ginger tabby with a white chest and socks, green eyes and a pink nose, out of boxes like everything else.
func _build() -> void:
	var root := _joint(self, Vector3.ZERO, "Model")
	root.scale = Vector3.ONE * SIZE
	body = _joint(root, Vector3(0.0, LEG + 0.09, 0.0), "Body")
	_box(body, Vector3(0.19, 0.18, 0.46), Vector3.ZERO, ORANGE, "Torso")
	_box(body, Vector3(0.15, 0.1, 0.05), Vector3(0.0, -0.035, -0.215), WHITE)          # (white chest)
	_box(body, Vector3(0.13, 0.03, 0.3), Vector3(0.0, -0.08, -0.03), WHITE)            # (and belly)
	for k in 4:   # (tabby stripes over the back)
		_box(body, Vector3(0.196, 0.05, 0.035), Vector3(0.0, 0.07, -0.12 + k * 0.09), STRIPE)
	_box(body, Vector3(0.05, 0.186, 0.05), Vector3(0.0, 0.0, 0.2), STRIPE)             # (a dark patch at the rump)
	# Legs: pivots at the body, the leg hanging down, a white sock.
	for spot: Vector3 in [Vector3(-0.06, -0.05, -0.17), Vector3(0.06, -0.05, -0.17),
			Vector3(-0.06, -0.05, 0.17), Vector3(0.06, -0.05, 0.17)]:
		var leg := _joint(body, spot, "Leg%d" % legs.size())
		_box(leg, Vector3(0.06, LEG, 0.06), Vector3(0.0, -LEG * 0.5 + 0.02, 0.0), ORANGE)
		_box(leg, Vector3(0.066, 0.04, 0.075), Vector3(0.0, -LEG + 0.035, -0.006), WHITE)
		legs.append(leg)
	# Head: on a neck pivot at the front of the body.
	head = _joint(body, Vector3(0.0, 0.08, -0.23), "Head")
	_box(head, Vector3(0.17, 0.14, 0.14), Vector3(0.0, 0.05, -0.05), ORANGE)
	_box(head, Vector3(0.17, 0.035, 0.141), Vector3(0.0, 0.1, -0.05), STRIPE)          # (a darker brow band)
	_box(head, Vector3(0.09, 0.055, 0.05), Vector3(0.0, 0.0, -0.13), WHITE)            # (muzzle)
	_box(head, Vector3(0.03, 0.022, 0.02), Vector3(0.0, 0.025, -0.155), PINK)          # (nose)
	for s: float in [-1.0, 1.0]:
		var ear := _joint(head, Vector3(s * 0.055, 0.12, -0.04), "Ear")
		ear.rotation.z = s * -0.18
		_box(ear, Vector3(0.06, 0.03, 0.03), Vector3(0.0, 0.015, 0.0), ORANGE)         # (a wide base, stepping in
		_box(ear, Vector3(0.04, 0.022, 0.026), Vector3(s * -0.006, 0.04, 0.0), ORANGE) # to a point: a triangle in boxes)
		_box(ear, Vector3(0.018, 0.016, 0.022), Vector3(s * -0.012, 0.058, 0.0), ORANGE)
		_box(ear, Vector3(0.032, 0.03, 0.01), Vector3(s * -0.004, 0.022, -0.012), PINK)
		for w in 2:   # (whiskers)
			_box(head, Vector3(0.09, 0.004, 0.004), Vector3(s * 0.08, 0.005 - w * 0.018, -0.14), WHITE)
	eyes_open = _joint(head, Vector3.ZERO, "EyesOpen")
	eyes_shut = _joint(head, Vector3.ZERO, "EyesShut")
	for s: float in [-1.0, 1.0]:
		_box(eyes_open, Vector3(0.04, 0.035, 0.01), Vector3(s * 0.042, 0.06, -0.121), EYE)
		_box(eyes_open, Vector3(0.012, 0.03, 0.012), Vector3(s * 0.042, 0.06, -0.122), DARK)
		_box(eyes_shut, Vector3(0.04, 0.008, 0.01), Vector3(s * 0.042, 0.055, -0.121), STRIPE)
	eyes_shut.visible = false
	# Tail: four pieces from the rump, each on its own pivot so it can curl.
	var parent := body
	var at := Vector3(0.0, 0.05, 0.23)
	for k in 4:
		var piece := _joint(parent, at, "Tail%d" % k)
		_box(piece, Vector3(0.045, 0.045, 0.1), Vector3(0.0, 0.0, 0.05), STRIPE if k == 3 else ORANGE)
		tail.append(piece)
		parent = piece
		at = Vector3(0.0, 0.0, 0.095)


## Sets the body, legs, head and tail for what it's doing (and blinks, breathes, flicks its tail).
func _pose(delta: float) -> void:
	var lying := 0.0      # 0 standing, 1 flat on the floor
	var sitting := 0.0    # 0 level, 1 sat up on its haunches
	var tail_up := 0.0
	var tail_curl := 0.0
	var head_pitch := 0.0
	var head_turn := sin(_time * 0.37) * 0.25
	var shut := false
	var swing := 0.0
	match state:
		"walk":
			swing = sin(_phase) * 0.55
			tail_up = 0.75
			head_turn = 0.0
		"sit":
			sitting = 1.0
			tail_curl = 0.6
		"groom":
			sitting = 1.0
			tail_curl = 0.6
			head_pitch = 0.55 + sin(_time * 9.0) * 0.12
			head_turn = -0.5
			shut = true
		"loaf":
			lying = 1.0
			tail_curl = 1.0
			shut = fmod(_time, 7.0) > 4.0   # (dozing off now and then)
		"sleep":
			lying = 1.0
			tail_curl = 1.0
			head_pitch = 0.35
			head_turn = 0.9
			shut = true
		"petted":
			sitting = 0.6
			tail_up = 1.0
			head_pitch = -0.35 + sin(_time * 2.2) * 0.08
			head_turn = sin(_time * 1.3) * 0.2
			shut = true
	var blend := minf(1.0, delta * 5.0)
	var lie := lerpf(body.position.y, lerpf(LEG + 0.09, 0.095, lying), blend)
	var breathe := 1.0 + sin(_time * (1.6 if state == "sleep" else 3.0)) * 0.03
	body.position.y = lie
	body.scale = Vector3(breathe, breathe, 1.0)
	body.rotation.x = lerp_angle(body.rotation.x, sitting * 0.62, blend)
	body.position.z = lerpf(body.position.z, sitting * 0.06, blend)
	# Sat up: the back legs fold under, the front ones stay straight down (against the body's tilt).
	for i in legs.size():
		var front := i < 2
		var x := 0.0
		if state == "walk":
			x = swing * (1.0 if (i == 0 or i == 3) else -1.0)
		elif lying > 0.5:
			x = 1.45   # (tucked under: front paws out in front, back legs folded beneath)
		elif sitting > 0.0:
			x = -body.rotation.x if front else 1.2
		legs[i].rotation.x = lerp_angle(legs[i].rotation.x, x, blend * 2.0)
	head.rotation.x = lerp_angle(head.rotation.x, -body.rotation.x * 0.8 - head_pitch, blend)   # (head_pitch: + looks down)
	head.rotation.y = lerp_angle(head.rotation.y, head_turn, blend)
	var blink := fmod(_time, 4.3) < 0.12
	eyes_open.visible = not (shut or blink)
	eyes_shut.visible = not eyes_open.visible
	# Tail: up and waving gently walking or petted, curled round when sat or lying, a flick at the tip now and then.
	for k in tail.size():
		var up := lerpf(-0.35, -0.75 if k == 0 else 0.25, tail_up)   # (tail_up: the base rises, the rest follows)
		var curl := tail_curl * 0.55 + sin(_time * 1.7 + k * 0.8) * (0.1 + 0.08 * k) * (1.0 - tail_curl * 0.6)
		if k == 0 and tail_up < 0.5:
			up = lerpf(0.6, 0.9, tail_curl)   # (hanging down off the rump)
		tail[k].rotation.x = lerp_angle(tail[k].rotation.x, up if k == 0 else up * 0.4 + (0.25 if tail_up > 0.5 and k == 3 else 0.0), blend)
		tail[k].rotation.y = lerp_angle(tail[k].rotation.y, curl, blend)
