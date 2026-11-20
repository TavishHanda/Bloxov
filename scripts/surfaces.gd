class_name Surfaces
extends RefCounted
## What people walk on (Sound update 0.20.0, footsteps by surface): the ground (today's steps), wood, metal,
## concrete/tile and water, plus a rustle on top in a bush. Which one: `BoxMap.surface_at`.

const GROUND := BoxMap.SURFACE_GROUND
const WOOD := BoxMap.SURFACE_WOOD
const METAL := BoxMap.SURFACE_METAL
const CONCRETE := BoxMap.SURFACE_CONCRETE
const WATER := BoxMap.SURFACE_WATER

const STEPS := [
	[preload("res://audio/step1.wav"), preload("res://audio/step2.wav"), preload("res://audio/step3.wav")],
	[preload("res://audio/steps/wood1.wav"), preload("res://audio/steps/wood2.wav"), preload("res://audio/steps/wood3.wav")],
	[preload("res://audio/steps/metal1.wav"), preload("res://audio/steps/metal2.wav"), preload("res://audio/steps/metal3.wav")],
	[preload("res://audio/steps/concrete1.wav"), preload("res://audio/steps/concrete2.wav"), preload("res://audio/steps/concrete3.wav")],
	[preload("res://audio/steps/water1.wav"), preload("res://audio/steps/water2.wav"), preload("res://audio/steps/water3.wav")],
]
## Each surface's loudness next to today's step (dB), so a metal stair rings out a little and tile clicks.
const STEP_DB := [0.0, 0.0, 1.0, -1.0, 1.0]
const RUSTLES := [preload("res://audio/steps/rustle1.wav"), preload("res://audio/steps/rustle2.wav")]
## 0.36.24: the same steps heard through a wall, shut door or pane (WALL) or a floor/ceiling (FLOOR), muffled in the
## file by tools/make_step_variants.py (the web build skips the runtime low-pass, so before this a step behind a wall
## there was only 5 dB quieter). Same order as STEPS; Hearing.MUFFLED_DB still goes on top.
const STEPS_WALL := [
	[preload("res://audio/steps/muffled/step1_wall.wav"), preload("res://audio/steps/muffled/step2_wall.wav"), preload("res://audio/steps/muffled/step3_wall.wav")],
	[preload("res://audio/steps/muffled/wood1_wall.wav"), preload("res://audio/steps/muffled/wood2_wall.wav"), preload("res://audio/steps/muffled/wood3_wall.wav")],
	[preload("res://audio/steps/muffled/metal1_wall.wav"), preload("res://audio/steps/muffled/metal2_wall.wav"), preload("res://audio/steps/muffled/metal3_wall.wav")],
	[preload("res://audio/steps/muffled/concrete1_wall.wav"), preload("res://audio/steps/muffled/concrete2_wall.wav"), preload("res://audio/steps/muffled/concrete3_wall.wav")],
	[preload("res://audio/steps/muffled/water1_wall.wav"), preload("res://audio/steps/muffled/water2_wall.wav"), preload("res://audio/steps/muffled/water3_wall.wav")],
]
const STEPS_FLOOR := [
	[preload("res://audio/steps/muffled/step1_floor.wav"), preload("res://audio/steps/muffled/step2_floor.wav"), preload("res://audio/steps/muffled/step3_floor.wav")],
	[preload("res://audio/steps/muffled/wood1_floor.wav"), preload("res://audio/steps/muffled/wood2_floor.wav"), preload("res://audio/steps/muffled/wood3_floor.wav")],
	[preload("res://audio/steps/muffled/metal1_floor.wav"), preload("res://audio/steps/muffled/metal2_floor.wav"), preload("res://audio/steps/muffled/metal3_floor.wav")],
	[preload("res://audio/steps/muffled/concrete1_floor.wav"), preload("res://audio/steps/muffled/concrete2_floor.wav"), preload("res://audio/steps/muffled/concrete3_floor.wav")],
	[preload("res://audio/steps/muffled/water1_floor.wav"), preload("res://audio/steps/muffled/water2_floor.wav"), preload("res://audio/steps/muffled/water3_floor.wav")],
]
const RUSTLES_WALL := [preload("res://audio/steps/muffled/rustle1_wall.wav"), preload("res://audio/steps/muffled/rustle2_wall.wav")]
const RUSTLES_FLOOR := [preload("res://audio/steps/muffled/rustle1_floor.wav"), preload("res://audio/steps/muffled/rustle2_floor.wav")]


## The surface under `body`'s feet (its origin).
static func under(body: Node3D) -> int:
	if BoxMap.is_wading(body):
		return WATER
	for map in RaidScope.nodes(body, &"box_maps"):
		var surface := (map as BoxMap).surface_at(body.global_position)
		if surface != GROUND:
			return surface
	return GROUND


## One footstep of `body`: the sound for what it stands on, with a rustle on top in a bush. Heard by this player
## only (`at_body` false: their own steps) or from the body's spot (others), `range` m at most.
static func step(body: Node3D, volume_db: float, at_body := false, pitch := 1.0, unit_size := 3.0, range := 0.0) -> void:
	var world := body.get_tree().current_scene
	if world == null:
		return   # (the game server: nothing to hear)
	if range > 0.0:
		range *= Characters.hearing   # (SABLE hears footsteps further, 0.37.0)
		var camera := body.get_viewport().get_camera_3d()
		if camera and camera.global_position.distance_to(body.global_position) > range:
			return   # (too far off to hear: no need to look up the floor)
	var surface := under(body)
	var steps: Array = STEPS
	var rustles: Array = RUSTLES
	var db := volume_db + float(STEP_DB[surface])
	if at_body:
		# Someone else's step: through a wall or floor it plays the muffled file (one ray, plus four only when blocked).
		var block := Hearing.block_of(Hearing.listener(world), body.global_position)
		if block == Hearing.Block.FLOOR:
			steps = STEPS_FLOOR
			rustles = RUSTLES_FLOOR
			db += Hearing.MUFFLED_DB
		elif block != Hearing.Block.NONE and block != Hearing.Block.OPENING:
			steps = STEPS_WALL
			rustles = RUSTLES_WALL
			db += Hearing.MUFFLED_DB
	var stream: AudioStream = (steps[surface] as Array).pick_random()
	if at_body:
		Hearing.heard_step(world, body.global_position)   # (0.30.3: someone close dips the ambience)
		Effects.sound_at(world, stream, body.global_position, db, 0.1, pitch, unit_size, range, &"", false)
	else:
		Effects.sound(world, stream, db, 0.1, pitch)
	if BoxMap.in_bush(body):
		if at_body:
			Effects.sound_at(world, rustles.pick_random(), body.global_position, db - 2.0, 0.12, pitch, unit_size, range, &"", false)
		else:
			Effects.sound(world, RUSTLES.pick_random(), db - 2.0, 0.12, pitch)
