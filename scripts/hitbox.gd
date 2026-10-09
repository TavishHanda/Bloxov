class_name Hitbox
extends RefCounted
## Where a player's hitboxes are for a given state (RemotePlayer.capture: [position, yaw, pitch, lean, flags]).
## Shared by RemotePlayer (the boxes you see and shoot at) and the server's hit checks (RaidWorld), so both agree.
## No dependencies on purpose: the server's autoload uses it (see the note in net.gd).

const FLAG_CROUCH := 1
const FLAG_AIM := 2
const FLAG_SPRINT := 4
const FLAG_DEAD := 8
const FLAG_EXTRACTED := 16
## Holding a gun (other players only show the gun on their model when they are).
const FLAG_ARMED := 32

const BODY_SIZE := Vector3(0.8, 1.35, 0.6)
const HEAD_SIZE := Vector3(0.62, 0.72, 0.62)
const HEAD_HEIGHT := 1.71
const CROUCH_SCALE := 0.67
## Same as the local player (player.gd: lean_distance 0.35 m at head height): the angle the body tips by.
const LEAN_ANGLE := 0.21


## Body box center (relative to the feet, before turning by yaw) for a crouch amount (0..1).
static func body_center(crouch: float) -> Vector3:
	return Vector3(0, BODY_SIZE.y * height_scale(crouch) * 0.5, 0)


static func body_size(crouch: float) -> Vector3:
	return Vector3(BODY_SIZE.x, BODY_SIZE.y * height_scale(crouch), BODY_SIZE.z)


static func head_center(crouch: float, lean: float) -> Vector3:
	var h := HEAD_HEIGHT * height_scale(crouch)
	return Vector3(sin(lean * LEAN_ANGLE) * h, cos(lean * LEAN_ANGLE) * h, 0)


static func height_scale(crouch: float) -> float:
	return lerpf(1.0, CROUCH_SCALE, crouch)


## Where the segment from..to first enters this player's boxes: {} for a miss, else {distance, headshot}.
static func trace(state: Array, from: Vector3, to: Vector3) -> Dictionary:
	var flags: int = state[4]
	if flags & (FLAG_DEAD | FLAG_EXTRACTED):
		return {}
	var crouch := 1.0 if flags & FLAG_CROUCH else 0.0
	var feet := Transform3D(Basis(Vector3.UP, state[1]), state[0])
	var local_from := feet.affine_inverse() * from
	var local_to := feet.affine_inverse() * to
	var best := {}
	for part in [[head_center(crouch, state[3]), HEAD_SIZE, true], [body_center(crouch), body_size(crouch), false]]:
		var box := AABB(part[0] - part[1] * 0.5, part[1])
		var hit: Variant = box.intersects_segment(local_from, local_to)
		if hit != null:
			var distance := local_from.distance_to(hit)
			if best.is_empty() or distance < best["distance"]:
				best = {"distance": distance, "headshot": part[2]}
	return best
