class_name RemotePlayer
extends CharacterBody3D
## Another player in an online raid, as this machine sees them: a body moved by the positions the server
## relays (no camera, no input). 0.7.0: position and facing only, smoothed; crouch, lean and aim come in 0.7.1.

## How fast the body catches up with the latest position (higher = snappier, lower = smoother).
@export var follow_speed := 15.0

var peer_id := 0
var _target_position := Vector3.ZERO
var _target_yaw := 0.0
var _placed := false


func apply_state(pos: Vector3, yaw: float) -> void:
	_target_position = pos
	_target_yaw = yaw
	# The first update puts them straight there instead of sliding in from the origin.
	if not _placed:
		_placed = true
		global_position = pos
		rotation.y = yaw


func _process(delta: float) -> void:
	var t := minf(follow_speed * delta, 1.0)
	global_position = global_position.lerp(_target_position, t)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)
