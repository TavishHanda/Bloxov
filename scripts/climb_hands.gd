class_name ClimbHands
extends Node3D
## First-person hands on a ladder (0.32.1, owner: ladders felt dead, "like floating up an elevator"): both gloved
## hands grip rungs in the world, and as you climb the lower hand lets go and reaches for the next rung up (going
## down, the upper hand reaches down), hand over hand. Lives under the player's camera; the gun is lowered out of
## view meanwhile (gun.gd). Looks only. Hands from assets/models/hands/hands.glb (climb_R, climb_L, ArmR, ArmL).

## The rung runs along x through this point, from the wrist (make_hands.py climb_hand).
const GRIP := Vector3(0, 0.06, -0.05)
## Hands this far either side of the ladder's middle.
const SPREAD := 0.17
## Where the elbows are, in the camera's frame: the forearms point at them.
const ELBOW_R := Vector3(0.26, -0.5, 0.12)
const ELBOW_L := Vector3(-0.26, -0.5, 0.12)
## Seconds for a hand to move to its next rung (quicker when climbing fast, so the hands keep up).
const REACH_TIME := 0.17
## A hand holds a rung this far (m) from the eyes, at most: lower going up (or higher going down) and it reaches.
const LOW := 0.3
const HIGH := 0.3

var player: Node3D
var _hands: Node3D
## Per hand ("R", "L"): the rung held, the rung it came from, and how far into the reach (1 = holding).
var _rung := {"R": 0, "L": 0}
var _from := {"R": 0, "L": 0}
var _t := {"R": 1.0, "L": 1.0}
var _ladder: Ladder
## How fast the eyes are going up or down (m/s, smoothed), and where they were.
var _speed := 0.0
var _last_eye := 0.0
## How far up (0) and out of view (1) the hands are: they come up as you grab on and drop away when you let go.
var _away := 1.0


func _ready() -> void:
	visible = false
	var scene := load(GunViewModels.HANDS) as PackedScene
	if scene == null:
		return
	_hands = scene.instantiate()
	for child: Node in _hands.get_children():
		if not child.name in ["climb_R", "climb_L", "ArmR", "ArmL"]:
			_hands.remove_child(child)
			child.free()
	if _hands.get_node_or_null("climb_R") == null:
		_hands.free()
		_hands = null
		return
	PixelModel.make_crisp(_hands)
	for mesh: GeometryInstance3D in _hands.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GunViewModels.wear(_hands, Profile.look)
	_hands.top_level = true
	add_child(_hands)


func _process(delta: float) -> void:
	if _hands == null or player == null:
		return
	var ladder: Ladder = player.call(&"climbing_ladder")
	_away = move_toward(_away, 0.0 if ladder != null else 1.0, delta * 6.0)
	if ladder != null and ladder != _ladder:
		_ladder = ladder
		_grab_at(get_parent() as Node3D)
	visible = _away < 1.0 and _ladder != null and is_instance_valid(_ladder)
	if not visible:
		if _away >= 1.0:
			_ladder = null
		return
	var eye := (get_parent() as Node3D).global_position.y
	if delta > 0.0:
		_speed = lerpf(_speed, absf(eye - _last_eye) / delta, minf(delta * 10.0, 1.0))
	_last_eye = eye
	if ladder != null:
		_step(eye, delta)
	for side: String in ["R", "L"]:
		_place(side, eye)


## First grab: the hands take the rungs nearest the chest and the head.
func _grab_at(camera: Node3D) -> void:
	var eye := camera.global_position.y
	_rung["R"] = _nearest(eye - 0.15)
	_rung["L"] = _nearest(eye + 0.2)
	if _rung["L"] == _rung["R"]:
		_rung["R"] = maxi(int(_rung["L"]) - 1, 0)
	for side: String in ["R", "L"]:
		_from[side] = _rung[side] - 2
		_t[side] = 0.0


## Hand over hand: the hand that's furthest behind reaches past the other one, one at a time.
func _step(eye: float, delta: float) -> void:
	# One hand moves two rungs for each rung climbed: it has to get there in the time that takes.
	var reach_time := minf(REACH_TIME, Ladder.RUNG_GAP / maxf(_speed, 0.01) * 0.8)
	for side: String in ["R", "L"]:
		_t[side] = minf(float(_t[side]) + delta / reach_time, 1.0)
	if _t["R"] < 1.0 or _t["L"] < 1.0:
		return
	var low := "R" if int(_rung["R"]) <= int(_rung["L"]) else "L"
	var high := "L" if low == "R" else "R"
	var top := _ladder.rung_count() - 1
	if _ladder.rung_y(_rung[low]) < eye - LOW and int(_rung[high]) < top:
		_reach(low, mini(int(_rung[high]) + 2, top))
	elif _ladder.rung_y(_rung[high]) > eye + HIGH and int(_rung[low]) > 0:
		_reach(high, maxi(int(_rung[low]) - 2, 0))
	# Far off (a teleport, a fall): grab again round the eyes.
	if absf(_ladder.rung_y(_rung["R"]) - eye) > 1.5:
		_grab_at(get_parent() as Node3D)


func _reach(side: String, rung: int) -> void:
	_from[side] = _rung[side]
	_rung[side] = rung
	_t[side] = 0.0


func _nearest(y: float) -> int:
	return clampi(roundi((y - _ladder.global_position.y - Ladder.FIRST_RUNG) / Ladder.RUNG_GAP), 0, _ladder.rung_count() - 1)


## Puts a hand on its rung (part way along its reach, lifted off the ladder toward you as it goes), the forearm to
## the elbow; dropped below the view while `_away`.
func _place(side: String, _eye: float) -> void:
	var hand := _hands.get_node("climb_" + side) as Node3D
	var arm := _hands.get_node("Arm" + side) as Node3D
	var sign := 1.0 if side == "R" else -1.0
	var into := _ladder.into()
	var t := smoothstep(0.0, 1.0, float(_t[side]))
	var from := _ladder.rung_point(_from[side], sign * SPREAD)
	var to := _ladder.rung_point(_rung[side], sign * SPREAD)
	var grip := from.lerp(to, t) - into * sin(t * PI) * 0.08
	var camera := get_parent() as Node3D
	grip -= camera.global_basis.y * _away * 0.6
	var basis := Basis(Vector3.UP.cross(-into), Vector3.UP, -into)
	hand.global_transform = Transform3D(basis, grip - basis * GRIP)
	var elbow := camera.to_global(ELBOW_R if side == "R" else ELBOW_L)
	arm.global_position = hand.global_position
	if not hand.global_position.is_equal_approx(elbow):
		arm.look_at(elbow, camera.global_basis.x)
