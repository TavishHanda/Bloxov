class_name BodyPose
extends RefCounted
## Poses a jointed character model (0.23, art_source/scripts/make_character.py): scavs, Raiders and other players
## stand, walk, kneel or crouch-walk, lie prone on their elbows and crawl, lie downed and dead, with both hands on the
## gun they hold. Owner (2026-10-26): crouching used to squash the whole model and prone tipped it over stiff, "like
## you're dead". Looks only, but the hitboxes are fitted to these poses (measure(); Hitbox holds the players' boxes).
##
## The owner sets the inputs (crouch, prone, ...) each frame and calls update(delta). Joints are the model's nodes:
## Hips > Spine > Neck / ArmL > ElbowL / ArmR > ElbowR, Hips > LegL > KneeL / LegR > KneeR, and Gun beside Hips.
## Angles below are degrees; a limb hangs down its joint's -Y, so +X swings a leg or arm forward and tips the chest back.

const JOINTS := ["Hips", "Spine", "Neck", "ArmL", "ElbowL", "ArmR", "ElbowR", "LegL", "KneeL", "LegR", "KneeR"]
## Shoulder to elbow, and elbow to the middle of the hand (make_character.py UPPER, FORE + half a glove).
const UPPER := 0.30
const REACH := 0.33

## Crouched (0.23): sitting back on the right heel with the left foot planted ahead, or crouch-walking low; the hips
## are this high, and the chest leans just enough to put the middle of the head box exactly at `crouch_head` (the
## hitbox, owner: "keep the old head height", "the hitboxes need to be precise"), right above the feet. The legs reach
## the ground (_legs).
const KNEEL_HIPS := 0.17
## The middle of the head and headgear, from the neck joint (the head box's middle; make_character.py HEAD_Z, HEAD).
const HEAD_MID := Vector3(0, 0.33, -0.037) * 0.85   # (make_character.py HEAD_SCALE, 0.25.22)
## Tucked (see `tuck`): the grip this far from the neck, close in front of the chest, and the muzzle raised this much
## (radians), so nothing reaches past the front of the body's collision (0.4 m).
const TUCK_GRIP := Vector3(0.15, -0.36, -0.12)
const TUCK_RAISE := 1.2
## Thigh and shin (hip to knee, knee to sole).
const THIGH := 0.29
const SHIN := 0.31
## Lying bodies are centred on the origin (0.25.22, owner: turning round while prone swung the whole body round the
## feet "absolutely crazy"; now it turns about its middle). The hips sit this far behind it, the head as far ahead.
const LIE_HIPS_Z := 0.33
## On the belly, chest up a little, head up looking ahead, legs apart; centred on the origin, where the lying hitboxes
## are (Hitbox.PRONE_*, DOWNED_*).
const PRONE := {"hips_pos": Vector3(0, 0.22, LIE_HIPS_Z), "hips_rot": Vector3(-90, 0, 0),
	"Neck": Vector3(65, 0, 0), "LegL": Vector3(0, 0, -12), "LegR": Vector3(0, 0, 12)}
## Downed: flat on the belly, head turned and down, the right arm reaching ahead to drag them, the left holding the
## wound (not the prone pose: no gun, nothing raised, so a prone player never reads as a downed one).
const DOWNED := {"hips_pos": Vector3(0, 0.22, LIE_HIPS_Z), "hips_rot": Vector3(-90, 0, 0), "Spine": Vector3(0, 0, 4),
	"Neck": Vector3(12, 35, 0), "ArmR": Vector3(165, 0, 18), "ElbowR": Vector3(-25, 0, 0),
	"ArmL": Vector3(60, 0, -10), "ElbowL": Vector3(-100, 0, 0), "LegL": Vector3(0, -50, -18), "KneeL": Vector3(-35, 0, 0),
	"LegR": Vector3(0, 0, 10)}
## Dead, fallen backward: on the back, arms flung out, head to one side (head toward +Z, like before).
const DEAD := {"hips_pos": Vector3(0, 0.22, 0.62), "hips_rot": Vector3(90, 0, 0), "Neck": Vector3(0, 40, 0),
	"ArmL": Vector3(10, 0, -75), "ElbowL": Vector3(-30, 0, 0), "ArmR": Vector3(-20, 0, 80), "ElbowR": Vector3(-15, 0, 0),
	"LegL": Vector3(0, 0, -14), "KneeL": Vector3(-10, 0, 0), "LegR": Vector3(0, 0, 8)}
## Dead after lying down (prone or downed): stays face down, limp (going on its back from there would swing it up
## through standing).
const DEAD_FACE_DOWN := {"hips_pos": Vector3(0, 0.22, LIE_HIPS_Z), "hips_rot": Vector3(-90, 0, 0), "Neck": Vector3(-5, 50, 0),
	"ArmR": Vector3(150, 0, 30), "ElbowR": Vector3(-20, 0, 0), "ArmL": Vector3(20, 0, -40), "LegL": Vector3(0, 0, -10),
	"LegR": Vector3(0, 0, 14), "KneeR": Vector3(-20, 0, 0)}

## Inputs, 0..1 unless said (the owner eases them in).
var crouch := 0.0
var prone := 0.0
var downed := 0.0
var dead := 0.0
## Looking up (+) or down (-), radians: nods the head.
var pitch := 0.0
var aim := 0.0
var sprint := 0.0
## 0..1: a wall right in front, so the gun is pulled in and raised to the chest instead of poking through it (0.25.19,
## owner: other players saw a body's arms and gun stick through a pillar). Looks only: shots come from the eyes.
var tuck := 0.0
## Holding a gun (shown and in both hands); else the arms hang and swing.
var armed := true
## Ground speed, m/s (drives the walk and crawl).
var speed := 0.0
## How fast they're turning, radians/s: turning on the spot shuffles the feet (or the knees, lying down).
var turn := 0.0
## How high the middle of the head is when crouched (players: Hitbox; a kneeling scav keeps its old 1.03 m).
var crouch_head := Hitbox.CROUCH_HEAD

var model: Node3D
var _joints := {}
var _rest := {}
var _walk := 0.0
var _move := 0.0
var _dead_face_down := false
var _was_dead := false
## Smoothed speed and turn (network positions arrive in steps), and a clock for breathing.
var _speed := 0.0
var _turn := 0.0
var _time := 0.0
## The hit flinch (0.25.22): a spring knocked by flinch(), x = pushed back, y = pushed to the right.
var _flinch := Vector2.ZERO
var _flinch_vel := Vector2.ZERO


func _init(model_node: Node3D) -> void:
	model = model_node
	for name: String in JOINTS:
		var joint := model.find_child(name, true, false) as Node3D
		if joint != null:
			_joints[name] = joint
			_rest[name] = joint.position
	# A scav's backpack rides on its back (it was placed on the model when the model didn't bend).
	var pack := model.get_node_or_null("Backpack") as Node3D
	if pack != null and _joints.has("Spine"):
		pack.reparent(_joints["Spine"])


## Whether this model has the joints (older models don't: nothing to pose).
func ok() -> bool:
	return _joints.size() == JOINTS.size()


func joint(name: String) -> Node3D:
	return _joints.get(name)


func update(delta: float) -> void:
	if not ok():
		return
	if dead > 0.0 and not _was_dead:
		_dead_face_down = prone + downed > 0.5
	_was_dead = dead > 0.0
	_time += delta
	_speed = speed if delta <= 0.0 else move_toward(_speed, speed, delta * 14.0)
	_turn = turn if delta <= 0.0 else move_toward(_turn, turn, delta * 12.0)
	_flinch_spring(delta)
	_move = move_toward(_move, clampf(_speed / 1.2, 0.0, 1.0), delta * 4.0)
	var lying := clampf(prone + downed, 0.0, 1.0)
	var alive := 1.0 - dead
	# Turning on the spot steps the feet round too (not while walking: the walk covers it).
	var pace := maxf(_speed, absf(_turn) * 0.45 * (1.0 - downed))
	_walk += delta * pace * lerpf(2.5, 4.0, lying)
	var pose := {}
	var low := crouch * (1.0 - lying)
	pose = _mix(pose, _crouched(), low)
	pose = _mix(pose, PRONE, prone)
	pose = _mix(pose, DOWNED, downed)
	pose = _mix(pose, DEAD_FACE_DOWN if _dead_face_down else DEAD, dead)
	var stride := sin(_walk)
	var push := cos(_walk)
	var up := 1.0 - lying
	# Walking and running (0.25.22, owner: "super static", "stiff"): the legs swing further and the knees lift higher
	# the faster they go, the hips dip as the legs spread (so the feet stay on the ground) and sway over the leg
	# they're on, the hips and shoulders twist against each other, and sprinting leans the body into it.
	var walk := minf(pace / 2.0, 1.0) * up * alive
	var run := sprint * (1.0 - crouch) * (1.0 - tuck) * walk
	var swing := stride * lerpf(34.0, 52.0, run) * walk
	var knee := lerpf(40.0, 85.0, run) * walk
	_add(pose, "LegL", Vector3(swing, 0, 0))
	_add(pose, "LegR", Vector3(-swing, 0, 0))
	_add(pose, "KneeL", Vector3(-maxf(-push, 0.0) * knee, 0, 0))
	_add(pose, "KneeR", Vector3(-maxf(push, 0.0) * knee, 0, 0))
	var standing := walk * (1.0 - crouch)
	var dip := (1.0 - cos(deg_to_rad(swing))) * 0.55 * standing
	_shift(pose, Vector3(stride * 0.03 * standing, -dip + absf(push) * 0.03 * run, 0))
	_add(pose, "hips_rot", Vector3(0, -stride * 7.0 * walk, 0))
	_add(pose, "Spine", Vector3(-14.0 * run - 3.0 * walk * (1.0 - run), stride * 11.0 * walk, 0))
	_add(pose, "Neck", Vector3(14.0 * run, -stride * 4.0 * walk, 0))
	if low > 0.0:
		_shift(pose, Vector3(0, -absf(push) * 0.03 * walk * low, 0))
	# Standing still: breathing, a slow rise and fall of the chest.
	var still := (1.0 - walk) * up * alive
	_add(pose, "Spine", Vector3(sin(_time * 1.8) * 1.5 * still, 0, sin(_time * 0.6) * 1.0 * still))
	# Crawling: each knee in turn draws up along the ground (the leg rolls out so the knee bends sideways, not up),
	# the hips wiggle and the shoulders roll with it; downed, the reaching arm pulls.
	var crawl := minf(pace / 0.6, 1.0) * lying * alive
	var left := maxf(stride, 0.0) * crawl
	var right := maxf(-stride, 0.0) * crawl
	_add(pose, "LegL", Vector3(0, -60.0 * left, -25.0 * left))
	_add(pose, "KneeL", Vector3(-55.0 * left, 0, 0))
	_add(pose, "LegR", Vector3(0, 60.0 * right, 25.0 * right))
	_add(pose, "KneeR", Vector3(-55.0 * right, 0, 0))
	_add(pose, "hips_rot", Vector3(0, stride * 6.0 * crawl, 0))
	_add(pose, "Spine", Vector3(0, -stride * 8.0 * crawl, -stride * 5.0 * crawl))
	_add(pose, "ArmR", Vector3(stride * 15.0 * crawl * downed, 0, 0))
	_add(pose, "ElbowR", Vector3(-maxf(stride, 0.0) * 40.0 * crawl * downed, 0, 0))
	# Looking up and down nods the head (less when lying: the head is already up; not downed). Hitbox.parts nods the
	# head box the same way.
	_add(pose, "Neck", Vector3(rad_to_deg(Hitbox.nod(pitch, prone)) * (1.0 - downed) * alive, 0, 0))
	# Hit: the chest and head snap away from the shot and spring back (less lying down).
	var jolt := _flinch * alive * lerpf(1.0, 0.45, lying)
	_add(pose, "Spine", Vector3(22.0 * jolt.x, 0, -16.0 * jolt.y))
	_add(pose, "Neck", Vector3(12.0 * jolt.x, 0, -8.0 * jolt.y))
	_shift(pose, Vector3(0.04 * jolt.y, 0, 0.05 * jolt.x) * up)
	var with_gun := armed and downed < 0.5 and dead < 0.5
	if not with_gun:
		# Arms hang and swing against the legs (pumping when running).
		var arm := lerpf(0.6, 1.1, run)
		_add(pose, "ArmL", Vector3(-swing * arm, 0, -6.0 * up))
		_add(pose, "ArmR", Vector3(swing * arm, 0, 6.0 * up))
		_add(pose, "ElbowL", Vector3(-25.0 * run, 0, 0))
		_add(pose, "ElbowR", Vector3(-25.0 * run, 0, 0))
	_apply(pose)
	if low > 0.01:
		_legs(low, stride * walk)
	_ground_feet()
	var gun := model.get_node_or_null("Gun") as Node3D
	if gun != null and with_gun:
		_hold(gun, lying, crawl * stride, stride * walk)


## A shot hit them (looks only): `from_dir` is the way the bullet travelled, in the model's frame (the model faces -Z).
func flinch(from_dir: Vector3) -> void:
	var push := Vector2(from_dir.z, from_dir.x)
	if push.length_squared() < 0.01:
		push = Vector2(1.0, randf_range(-0.6, 0.6))
	_flinch_vel += push.normalized() * 18.0


func _flinch_spring(delta: float) -> void:
	if delta <= 0.0 or (_flinch == Vector2.ZERO and _flinch_vel == Vector2.ZERO):
		return
	var step := minf(delta, 1.0 / 30.0)
	_flinch_vel += (-320.0 * _flinch - 24.0 * _flinch_vel) * step
	_flinch += _flinch_vel * step
	if _flinch.length() < 0.002 and _flinch_vel.length() < 0.02:
		_flinch = Vector2.ZERO
		_flinch_vel = Vector2.ZERO


## Feet never go through the ground (0.25.22, owner: going prone the legs vanished, then popped back): a leg whose
## sole would be under the floor bends at the knee to keep it on top, as when someone drops to their knees.
func _ground_feet() -> void:
	if not model.is_inside_tree():   # (the server and tools measure unparented: nothing to stand on there)
		return
	var to_model := model.global_transform.affine_inverse()
	for side: String in ["L", "R"]:
		var leg := _joints["Leg" + side] as Node3D
		var knee := _joints["Knee" + side] as Node3D
		var sole := to_model * (knee.global_transform * Vector3(0, -SHIN, 0))
		if sole.y >= -0.01:
			continue
		sole.y = 0.0
		_two_bone(leg, knee, THIGH, SHIN, model.global_transform * sole, model.global_basis * Vector3(0, -0.3, -1.0),
			leg.global_position)


## The crouched pose's hips and lean (see KNEEL_HIPS): the chest leans by the angle that brings the head down to
## crouch_head, the neck leans back as far so the head stays upright, the hips sit back so the head is over the feet.
func _crouched() -> Dictionary:
	var waist: Vector3 = _rest["Spine"]
	var chest: float = (_rest["Neck"] as Vector3).y
	var lean := acos(clampf((crouch_head - HEAD_MID.y - waist.y - KNEEL_HIPS) / chest, -1.0, 1.0))
	return {"hips_pos": Vector3(0, KNEEL_HIPS, chest * sin(lean)), "Spine": Vector3(-rad_to_deg(lean), 0, 0),
		"Neck": Vector3(rad_to_deg(lean), 0, 0)}


## Crouched legs reach the ground: still, the right knee down with that foot under the seat and the left foot planted
## ahead; moving, both feet step under the hips. Eased from standing feet by `amount`.
func _legs(amount: float, step: float) -> void:
	var hips := _joints["Hips"] as Node3D
	var at := hips.position
	for side: String in ["L", "R"]:
		var leg := _joints["Leg" + side] as Node3D
		var x: float = (_rest["Leg" + side] as Vector3).x
		var stand := Vector3(x, at.y - THIGH - SHIN, at.z)
		var kneel := Vector3(x, 0.0, at.z - 0.38) if side == "L" else Vector3(x, 0.05, at.z + 0.05)
		var s := step if side == "L" else -step
		var walk := Vector3(x, maxf(s, 0.0) * 0.11, at.z - 0.22 + s * 0.21)
		var foot := stand.lerp(kneel.lerp(walk, _move), amount)
		var pole := Vector3(0, 0.6, -1.0)
		_two_bone(leg, _joints["Knee" + side], THIGH, SHIN, model.global_transform * foot,
			model.global_basis * pole, leg.global_position)


## Puts the gun in the hands' place for this pose (level, ahead; lowered while sprinting; on the ground ahead when
## prone) and reaches both arms to it.
func _hold(gun: Node3D, lying: float, crawl: float, step := 0.0) -> void:
	var neck := model.to_local((_joints["Neck"] as Node3D).global_position)
	var up := neck + Vector3(0.17, -0.24, -0.26).lerp(Vector3(0.13, -0.15, -0.2), aim)
	up += Vector3(-0.02, -0.12, 0.08) * sprint * (1.0 - aim)
	# The gun sways a little with each step (less aiming).
	up += Vector3(step * 0.025, absf(step) * 0.015, 0) * (1.0 - aim * 0.7)
	# Prone (0.25.22: it lay hidden under the chin): out ahead by the head, the stock at the shoulder, both elbows down.
	var down := Vector3(0.17, 0.27, neck.z - 0.2 + crawl * 0.08)
	var grip := up.lerp(down, lying)
	var raise := -0.45 * sprint * (1.0 - aim)
	var tucked := tuck * (1.0 - lying)
	if tucked > 0.0:
		grip = grip.lerp(neck + TUCK_GRIP, tucked)
		raise = lerpf(raise, TUCK_RAISE, tucked)
	gun.transform = Transform3D(Basis(Vector3.RIGHT, raise * (1.0 - lying)), grip)
	var side := model.global_basis.x
	var below := -model.global_basis.y
	var hand := gun.global_transform * Vector3(0, 0.03, 0)
	_reach("R", hand, side * 0.7 + below)
	var fore := gun.get_node_or_null("Art/Fore") as Node3D
	var support := fore.global_position if fore != null else gun.global_transform * Vector3(-0.05, -0.01, 0.02)
	_reach("L", support, -side * 0.9 + below)


## The arm of `side` turns at the shoulder and elbow so the hand is at `target` (as near as it gets),
## the elbow toward `pole`.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var shoulder := _joints["Arm" + side] as Node3D
	_two_bone(shoulder, _joints["Elbow" + side], UPPER, REACH, target, pole, shoulder.global_position)


## Turns `upper` (at `from`) and `lower` (lengths a and b) so the end of `lower` is at `target`, as near as it gets,
## the middle joint toward `pole`.
func _two_bone(upper: Node3D, lower: Node3D, a: float, b: float, target: Vector3, pole: Vector3, from: Vector3) -> void:
	var to := target - from
	if to.length_squared() < 0.0001:
		return
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var cos_a := (a * a + d * d - b * b) / (2.0 * a * d)
	var out := pole - dir * pole.dot(dir)
	out = out.normalized() if out.length_squared() > 0.0001 else model.global_basis.y
	var middle := from + dir * a * cos_a + out * a * sqrt(maxf(1.0 - cos_a * cos_a, 0.0))
	upper.global_basis = _limb(middle - from)
	lower.global_basis = _limb(from + dir * d - middle)


## A limb's frame for one pointing along `along` (its -Y), its front kept toward the body's front. (0.25.22: it used to
## come out turned half round about the limb, so a leg that had been bent by _legs, e.g. after crouching, showed
## its boots backward; owner: "my legs turned backwards".)
func _limb(along: Vector3) -> Basis:
	var y := -along.normalized()
	var back := model.global_basis.z
	if absf(y.dot(back.normalized())) > 0.95:
		back = -model.global_basis.y
	var x := y.cross(back).normalized()
	return Basis(x, y, x.cross(y)).scaled(model.global_basis.get_scale())


func _apply(pose: Dictionary) -> void:
	for name: String in JOINTS:
		var node := _joints[name] as Node3D
		var angles: Vector3 = pose.get(name, Vector3.ZERO)
		node.rotation = Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z))
	var hips := _joints["Hips"] as Node3D
	hips.position = pose.get("hips_pos", _rest["Hips"])
	var turn: Vector3 = pose.get("hips_rot", Vector3.ZERO)
	hips.rotation = Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z))


## `a` eased toward `b` by t (keys missing from either are standing: zero angles, the hips at rest).
func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if t <= 0.0:
		return a
	var out := {}
	for key: String in JOINTS + ["hips_pos", "hips_rot"]:
		var zero: Vector3 = _rest["Hips"] if key == "hips_pos" else Vector3.ZERO
		var from: Vector3 = a.get(key, zero)
		var to: Vector3 = b.get(key, zero)
		out[key] = from.lerp(to, t)
	return out


## Moves the hips by `offset` (from where the pose has them).
func _shift(pose: Dictionary, offset: Vector3) -> void:
	pose["hips_pos"] = (pose.get("hips_pos", _rest["Hips"]) as Vector3) + offset


func _add(pose: Dictionary, key: String, angles: Vector3) -> void:
	pose[key] = (pose.get(key, Vector3.ZERO) as Vector3) + angles


## The hit boxes that fit this model in a pose (`settings`: crouch, prone, downed as 0 or 1), standing still and
## looking ahead: [[center, size, headshot, pitch], ...] for the head (and headgear), the chest and the hips and legs,
## relative to the feet, each box turned `pitch` radians about X (the chest's lean). Every outfit option counts, so
## a box fits any outfit. Leaves the model as it was. Hitbox's numbers come from here (the smoke test checks they
## still match); scavs measure themselves.
func measure(settings: Dictionary) -> Array:
	var saved := [crouch, prone, downed, dead, speed, pitch, _move, turn, _time, _flinch, _flinch_vel, tuck]
	turn = 0.0
	_time = 0.0
	_flinch = Vector2.ZERO
	_flinch_vel = Vector2.ZERO
	tuck = 0.0
	crouch = settings.get("crouch", 0.0)
	prone = settings.get("prone", 0.0)
	downed = settings.get("downed", 0.0)
	dead = 0.0
	speed = 0.0
	pitch = 0.0
	_move = 0.0
	update(0.0)
	var parts := []
	for group: Array in [[["Neck"], true], [["Spine"], false], [["Hips", "LegL", "KneeL", "LegR", "KneeR"], false]]:
		var frame := in_model(_joints[group[0][0]])
		# A box turned like the joint when the joint only leans about X; else upright, around everything.
		var leans_only: bool = frame.basis.x.is_equal_approx(Vector3.RIGHT) and group[0][0] != "Hips"
		var into := Transform3D(frame.basis, Vector3.ZERO) if leans_only else Transform3D.IDENTITY
		var box := AABB()
		var first := true
		for name: String in group[0]:
			var joint_frame := into.affine_inverse() * in_model(_joints[name])
			for child in (_joints[name] as Node3D).get_children():
				var part := child as MeshInstance3D
				if part == null or part.mesh == null or not String(part.name).contains("__"):
					continue
				var bounds := (joint_frame * part.transform) * part.mesh.get_aabb()
				box = bounds if first else box.merge(bounds)
				first = false
		var pitch_angle: float = atan2(frame.basis.y.z, frame.basis.y.y) if leans_only else 0.0
		parts.append([into.basis * box.get_center(), box.size, group[1], pitch_angle])
	crouch = saved[0]
	prone = saved[1]
	downed = saved[2]
	dead = saved[3]
	speed = saved[4]
	pitch = saved[5]
	_move = saved[6]
	turn = saved[7]
	_time = saved[8]
	_flinch = saved[9]
	_flinch_vel = saved[10]
	tuck = saved[11]
	update(0.0)
	return parts


## A node's transform in the model's own frame (works off the tree too: the server and tools measure unparented).
func in_model(node: Node3D) -> Transform3D:
	var t := node.transform
	var up := node.get_parent() as Node3D
	while up != null and up != model:
		t = up.transform * t
		up = up.get_parent() as Node3D
	return t
