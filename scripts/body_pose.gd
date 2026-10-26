class_name BodyPose
extends RefCounted
## Poses a jointed character model (0.23, art_source/scripts/make_character.py): scavs, Raiders and other players
## stand, walk, kneel or crouch-walk, lie prone on their elbows and crawl, lie downed and dead, with both hands on the
## gun they hold. Owner (2026-10-26): crouching used to squash the whole model and prone tipped it over stiff, "like
## you're dead". Looks only: hitboxes come from Hitbox (players) and the scav's own shapes, placed to match these poses.
##
## The owner sets the inputs (crouch, prone, ...) each frame and calls update(delta). Joints are the model's nodes:
## Hips > Spine > Neck / ArmL > ElbowL / ArmR > ElbowR, Hips > LegL > KneeL / LegR > KneeR, and Gun beside Hips.
## Angles below are degrees; a limb hangs down its joint's -Y, so +X swings a leg or arm forward and tips the chest back.

const JOINTS := ["Hips", "Spine", "Neck", "ArmL", "ElbowL", "ArmR", "ElbowR", "LegL", "KneeL", "LegR", "KneeR"]
## Shoulder to elbow, and elbow to the middle of the hand (make_character.py UPPER, FORE + half a glove).
const UPPER := 0.30
const REACH := 0.33

## Kneeling on the right knee, sitting back, chest forward: the head ends up near the crouched head hitbox
## (Hitbox: 1.15 m up, a bit forward).
const KNEEL := {"hips_pos": Vector3(0, 0.24, 0.28), "Spine": Vector3(-28, 0, 0), "Neck": Vector3(22, 0, 0),
	"LegL": Vector3(95, 0, -4), "KneeL": Vector3(-95, 0, 0), "LegR": Vector3(-49, 0, 4), "KneeR": Vector3(-41, 0, 0)}
## Crouched and moving: both knees deep, chest forward (the walk cycle swings the legs about this).
const CROUCH_WALK := {"hips_pos": Vector3(0, 0.30, 0.15), "Spine": Vector3(-32, 0, 0), "Neck": Vector3(24, 0, 0),
	"LegL": Vector3(70, 0, -6), "KneeL": Vector3(-120, 0, 0), "LegR": Vector3(70, 0, 6), "KneeR": Vector3(-120, 0, 0)}
## On the belly, chest up a little, head up looking ahead, legs apart; feet at the origin and the head in front, where
## the lying hitboxes are (Hitbox.DOWNED_*).
const PRONE := {"hips_pos": Vector3(0, 0.22, -0.62), "hips_rot": Vector3(-90, 0, 0),
	"Neck": Vector3(65, 0, 0), "LegL": Vector3(0, 0, -12), "LegR": Vector3(0, 0, 12)}
## Downed: flat on the belly, head turned and down, the right arm reaching ahead to drag them, the left holding the
## wound (not the prone pose: no gun, nothing raised, so a prone player never reads as a downed one).
const DOWNED := {"hips_pos": Vector3(0, 0.22, -0.62), "hips_rot": Vector3(-90, 0, 0), "Spine": Vector3(0, 0, 4),
	"Neck": Vector3(12, 35, 0), "ArmR": Vector3(165, 0, 18), "ElbowR": Vector3(-25, 0, 0),
	"ArmL": Vector3(60, 0, -10), "ElbowL": Vector3(-100, 0, 0), "LegL": Vector3(0, -50, -18), "KneeL": Vector3(-35, 0, 0),
	"LegR": Vector3(0, 0, 10)}
## Dead, fallen backward: on the back, arms flung out, head to one side (head toward +Z, like before).
const DEAD := {"hips_pos": Vector3(0, 0.22, 0.62), "hips_rot": Vector3(90, 0, 0), "Neck": Vector3(0, 40, 0),
	"ArmL": Vector3(10, 0, -75), "ElbowL": Vector3(-30, 0, 0), "ArmR": Vector3(-20, 0, 80), "ElbowR": Vector3(-15, 0, 0),
	"LegL": Vector3(0, 0, -14), "KneeL": Vector3(-10, 0, 0), "LegR": Vector3(0, 0, 8)}
## Dead after lying down (prone or downed): stays face down, limp (going on its back from there would swing it up
## through standing).
const DEAD_FACE_DOWN := {"hips_pos": Vector3(0, 0.22, -0.62), "hips_rot": Vector3(-90, 0, 0), "Neck": Vector3(-5, 50, 0),
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
## Holding a gun (shown and in both hands); else the arms hang and swing.
var armed := true
## Ground speed, m/s (drives the walk and crawl).
var speed := 0.0

var model: Node3D
var _joints := {}
var _rest := {}
var _walk := 0.0
var _move := 0.0
var _dead_face_down := false
var _was_dead := false


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
	_move = move_toward(_move, clampf(speed / 1.2, 0.0, 1.0), delta * 4.0)
	var lying := clampf(prone + downed, 0.0, 1.0)
	_walk += delta * speed * lerpf(2.5, 4.0, lying)
	var pose := {}
	var crouched := _mix(KNEEL, CROUCH_WALK, _move)
	pose = _mix(pose, crouched, crouch * (1.0 - lying))
	pose = _mix(pose, PRONE, prone)
	pose = _mix(pose, DOWNED, downed)
	pose = _mix(pose, DEAD_FACE_DOWN if _dead_face_down else DEAD, dead)
	var alive := 1.0 - dead
	var stride := sin(_walk)
	# Walking (and crouch-walking): legs swing, the knee bends as the leg comes through.
	var walk := minf(speed / 2.0, 1.0) * (1.0 - lying) * alive
	var swing := stride * lerpf(34.0, 22.0, crouch) * walk
	_add(pose, "LegL", Vector3(swing, 0, 0))
	_add(pose, "LegR", Vector3(-swing, 0, 0))
	_add(pose, "KneeL", Vector3(-maxf(-cos(_walk), 0.0) * 40.0 * walk, 0, 0))
	_add(pose, "KneeR", Vector3(-maxf(cos(_walk), 0.0) * 40.0 * walk, 0, 0))
	_add(pose, "Spine", Vector3(-10.0 * sprint * (1.0 - crouch), 0, 0))
	# Crawling: each knee in turn draws up along the ground (the leg rolls out so the knee bends sideways, not up);
	# downed, the reaching arm pulls.
	var crawl := minf(speed / 0.6, 1.0) * lying * alive
	var left := maxf(stride, 0.0) * crawl
	var right := maxf(-stride, 0.0) * crawl
	_add(pose, "LegL", Vector3(0, -60.0 * left, -25.0 * left))
	_add(pose, "KneeL", Vector3(-55.0 * left, 0, 0))
	_add(pose, "LegR", Vector3(0, 60.0 * right, 25.0 * right))
	_add(pose, "KneeR", Vector3(-55.0 * right, 0, 0))
	_add(pose, "ArmR", Vector3(stride * 15.0 * crawl * downed, 0, 0))
	_add(pose, "ElbowR", Vector3(-maxf(stride, 0.0) * 40.0 * crawl * downed, 0, 0))
	# Looking up and down nods the head (less when lying: the head is already up).
	_add(pose, "Neck", Vector3(rad_to_deg(clampf(pitch, -0.7, 0.7)) * lerpf(1.0, 0.5, lying) * alive, 0, 0))
	var with_gun := armed and downed < 0.5 and dead < 0.5
	if not with_gun:
		# Arms hang and swing against the legs.
		_add(pose, "ArmL", Vector3(-swing * 0.6, 0, -6.0 * (1.0 - lying)))
		_add(pose, "ArmR", Vector3(swing * 0.6, 0, 6.0 * (1.0 - lying)))
	_apply(pose)
	var gun := model.get_node_or_null("Gun") as Node3D
	if gun != null and with_gun:
		_hold(gun, lying, crawl * stride)


## Puts the gun in the hands' place for this pose (level, ahead; lowered while sprinting; on the ground ahead when
## prone) and reaches both arms to it.
func _hold(gun: Node3D, lying: float, crawl: float) -> void:
	var neck := model.to_local((_joints["Neck"] as Node3D).global_position)
	var up := neck + Vector3(0.17, -0.24, -0.26).lerp(Vector3(0.13, -0.15, -0.2), aim)
	up += Vector3(-0.02, -0.12, 0.08) * sprint * (1.0 - aim)
	var down := Vector3(0.24, 0.2, neck.z + 0.02 + crawl * 0.08)
	var grip := up.lerp(down, lying)
	gun.transform = Transform3D(Basis(Vector3.RIGHT, -0.45 * sprint * (1.0 - aim) * (1.0 - lying)), grip)
	var side := model.global_basis.x
	var below := -model.global_basis.y
	var hand := gun.global_transform * Vector3(0, 0.03, 0)
	_reach("R", hand, side * 0.7 + below)
	var fore := gun.get_node_or_null("Art/Fore") as Node3D
	var support := fore.global_position if fore != null else gun.global_transform * Vector3(-0.05, -0.01, 0.02)
	_reach("L", support, -side * 0.9 + below)


## Two-bone reach: the arm of `side` turns at the shoulder and elbow so the hand is at `target` (as near as it gets),
## the elbow toward `pole`.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var shoulder := _joints["Arm" + side] as Node3D
	var elbow := _joints["Elbow" + side] as Node3D
	var from := shoulder.global_position
	var to := target - from
	if to.length_squared() < 0.0001:
		return
	var d := clampf(to.length(), absf(UPPER - REACH) + 0.01, UPPER + REACH - 0.001)
	var dir := to.normalized()
	var cos_a := (UPPER * UPPER + d * d - REACH * REACH) / (2.0 * UPPER * d)
	var out := pole - dir * pole.dot(dir)
	out = out.normalized() if out.length_squared() > 0.0001 else model.global_basis.y
	var at_elbow := from + dir * UPPER * cos_a + out * UPPER * sqrt(maxf(1.0 - cos_a * cos_a, 0.0))
	shoulder.global_basis = _limb(at_elbow - from)
	elbow.global_basis = _limb(from + dir * d - at_elbow)


## A limb's frame for one pointing along `along` (its -Y), its front kept toward the body's front.
func _limb(along: Vector3) -> Basis:
	var y := -along.normalized()
	var front := -model.global_basis.z
	if absf(y.dot(front)) > 0.95:
		front = model.global_basis.y
	var x := y.cross(front).normalized()
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


func _add(pose: Dictionary, key: String, angles: Vector3) -> void:
	pose[key] = (pose.get(key, Vector3.ZERO) as Vector3) + angles
