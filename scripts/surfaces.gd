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
		var camera := body.get_viewport().get_camera_3d()
		if camera and camera.global_position.distance_to(body.global_position) > range:
			return   # (too far off to hear: no need to look up the floor)
	var surface := under(body)
	var stream: AudioStream = (STEPS[surface] as Array).pick_random()
	var db := volume_db + float(STEP_DB[surface])
	if at_body:
		Effects.sound_at(world, stream, body.global_position, db, 0.1, pitch, unit_size, range)
	else:
		Effects.sound(world, stream, db, 0.1, pitch)
	if BoxMap.in_bush(body):
		if at_body:
			Effects.sound_at(world, RUSTLES.pick_random(), body.global_position, db - 2.0, 0.12, pitch, unit_size, range)
		else:
			Effects.sound(world, RUSTLES.pick_random(), db - 2.0, 0.12, pitch)
