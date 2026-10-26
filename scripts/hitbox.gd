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
## Knocked down (0.9.2): lying face down, crawling. Still hittable (hits drain the downed bar).
const FLAG_DOWNED := 64
## Lying prone (0.13.6): the same lying-down boxes as downed (the crouch flag is set too).
const FLAG_PRONE := 128
## Under 40% health (0.15.18): the server's AI push a hurt player (Scav.LOW_HEALTH).
const FLAG_LOW := 256
## Which gun they hold (0.18.1, AILoadouts.NET_GUNS index), in the bits from here up, so their model shows it.
const GUN_SHIFT := 10

const BODY_SIZE := Vector3(0.8, 1.35, 0.6)
const HEAD_SIZE := Vector3(0.62, 0.72, 0.62)
const HEAD_HEIGHT := 1.71
## Crouched, the middle of the head box is this much lower (owner: keep the old head height).
const CROUCH_SCALE := 0.67
## Same as the local player (player.gd: lean_distance 0.35 m at head height): the angle the body tips by.
const LEAN_ANGLE := 0.21
## Where a teammate reaches to revive a downed player (their middle).
const DOWNED_BODY_CENTER := Vector3(0, 0.22, -0.68)

## Crouched, prone and downed (0.23, owner: "the hitboxes need to be precise"): boxes fitted to the jointed model in
## that pose (BodyPose.measure on the PMC model, every outfit; the smoke test checks they still fit). Each part is
## [center, size, headshot, pitch]: relative to the feet before turning by yaw, the box turned `pitch` radians about X
## (a leaning chest). Head, chest, then hips and legs. The neck is where the head nods from (nod()).
const CROUCH_PARTS := [
	[Vector3(0.000, 1.146, -0.037), Vector3(0.640, 0.620, 0.665), true, 0.000],
	[Vector3(0.000, 0.500, 0.203), Vector3(0.760, 0.830, 0.630), false, -0.584],
	[Vector3(0.000, 0.130, 0.264), Vector3(0.780, 0.607, 0.759), false, 0.000]
]
const CROUCH_NECK := Vector3(0.000, 0.816, 0.000)
const PRONE_PARTS := [
	[Vector3(0.000, 0.503, -1.563), Vector3(0.640, 0.620, 0.665), true, -0.436],
	[Vector3(0.000, 0.215, -1.015), Vector3(0.760, 0.830, 0.630), false, -1.571],
	[Vector3(0.000, 0.220, -0.350), Vector3(0.943, 0.460, 0.700), false, 0.000]
]
const PRONE_NECK := Vector3(0.000, 0.220, -1.390)
const DOWNED_PARTS := [
	[Vector3(-0.053, 0.261, -1.719), Vector3(0.928, 0.977, 0.744), true, 0.000],
	[Vector3(-0.026, 0.215, -1.014), Vector3(0.816, 0.630, 0.881), false, 0.000],
	[Vector3(-0.081, 0.184, -0.317), Vector3(1.066, 0.531, 0.767), false, 0.000]
]


## How far the head nods for a look `pitch` (BodyPose turns the model's neck by the same): half as far lying prone.
static func nod(pitch: float, prone: float) -> float:
	return clampf(pitch, -0.7, 0.7) * lerpf(1.0, 0.5, prone)


## The boxes for a state's flags, lean and look pitch: [[center, size, headshot, basis], ...], relative to the feet
## before turning by yaw. Standing is the two boxes of old (head, body); crouched, prone and downed the fitted parts.
static func parts(flags: int, lean: float, pitch: float) -> Array:
	var out := []
	if flags & FLAG_DOWNED:
		for part: Array in DOWNED_PARTS:
			out.append([part[0], part[1], part[2], Basis(Vector3.RIGHT, part[3])])
		return out
	if flags & FLAG_PRONE:
		# Leaning (prone, 0.13.7) shifts the head sideways, like the local player's head (lean_distance 0.35 m).
		var turn := Basis(Vector3.RIGHT, nod(pitch, 1.0))
		for part: Array in PRONE_PARTS:
			var center: Vector3 = part[0]
			var basis := Basis(Vector3.RIGHT, part[3])
			if part[2]:
				center = PRONE_NECK + turn * (center - PRONE_NECK) + Vector3(lean * 0.35, 0, 0)
				basis = turn * basis
			out.append([center, part[1], part[2], basis])
		return out
	# Leaning tips the whole body around the feet (0.13.8: the body box too, so a shoulder that shows round a corner
	# can be hit).
	var tilt := lean_basis(lean)
	if flags & FLAG_CROUCH:
		var turn := Basis(Vector3.RIGHT, nod(pitch, 0.0))
		for part: Array in CROUCH_PARTS:
			var center: Vector3 = part[0]
			var basis := Basis(Vector3.RIGHT, part[3])
			if part[2]:
				center = CROUCH_NECK + turn * (center - CROUCH_NECK)
				basis = turn * basis
			out.append([tilt * center, part[1], part[2], tilt * basis])
		return out
	out.append([tilt * Vector3(0, HEAD_HEIGHT, 0), HEAD_SIZE, true, tilt])
	out.append([tilt * Vector3(0, BODY_SIZE.y * 0.5, 0), BODY_SIZE, false, tilt])
	return out


## The tilt of a leaning body (around the feet, sideways), same as the model's.
static func lean_basis(lean: float) -> Basis:
	return Basis(Vector3.BACK, -lean * LEAN_ANGLE)


## Where the segment from..to first enters this player's boxes: {} for a miss, else {distance, headshot}.
static func trace(state: Array, from: Vector3, to: Vector3) -> Dictionary:
	var flags: int = state[4]
	if flags & (FLAG_DEAD | FLAG_EXTRACTED):
		return {}
	var feet := Transform3D(Basis(Vector3.UP, state[1]), state[0])
	var local_from := feet.affine_inverse() * from
	var local_to := feet.affine_inverse() * to
	var best := {}
	for part: Array in parts(flags, state[3], state[2]):
		var into := Transform3D(part[3], part[0]).affine_inverse()
		var size: Vector3 = part[1]
		var box := AABB(-size * 0.5, size)
		var hit: Variant = box.intersects_segment(into * local_from, into * local_to)
		if hit != null:
			var distance := local_from.distance_to(Transform3D(part[3], part[0]) * (hit as Vector3))
			if best.is_empty() or distance < best["distance"]:
				best = {"distance": distance, "headshot": part[2]}
	return best
