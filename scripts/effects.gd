class_name Effects
extends RefCounted
## One-shot visual and sound effects: tracers, impact sparks, voxel bursts, damage numbers, sounds.

## Nodes the HUD draws a label for (damage numbers, teammate name tags): see WorldLabelsHUD.
const WORLD_LABELS := &"hud_world_labels"
const DAMAGE_NUMBER_LIFE := 0.75

static var _materials: Dictionary = {}


static func unshaded(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[color] = mat
	return mat


static func tracer(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var dist := from.distance_to(to)
	if dist < 0.2:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, dist)
	mesh.material = unshaded(Color(1.0, 0.92, 0.55))
	var tracer_mesh := MeshInstance3D.new()
	tracer_mesh.mesh = mesh
	tracer_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(tracer_mesh)
	tracer_mesh.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	tracer_mesh.look_at(to, up)
	_free_after(tracer_mesh, 0.04)


static func impact(world: Node, pos: Vector3, normal: Vector3, color: Color, amount := 8) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var particles := _cube_particles(color, 0.06, amount)
	particles.lifetime = 0.45
	particles.direction = normal
	particles.spread = 50.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.0
	_emit(world, particles, pos, 1.0)


## Explodes something into voxel chunks (enemy deaths).
static func burst(world: Node, pos: Vector3, color: Color) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var particles := _cube_particles(color, 0.16, 30)
	particles.lifetime = 1.2
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 7.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.3, 0.7, 0.3)
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	_emit(world, particles, pos, 1.5)


## A floating damage number (owner toggle). Just a marker in the world: the HUD draws it, crisp in the pixel font
## (WorldLabelsHUD, 0.8.16; it used to be a Label3D, which blurred). It lives for WORLD_LABEL_LIFE seconds.
static func damage_number(world: Node, pos: Vector3, amount: int, critical: bool) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var marker := Node3D.new()
	marker.name = "DamageNumber"
	marker.set_meta("label_kind", "damage")
	marker.set_meta("label_text", str(amount) + ("!" if critical else ""))
	marker.set_meta("label_critical", critical)
	marker.set_meta("label_born", Time.get_ticks_msec() / 1000.0)
	marker.add_to_group(WORLD_LABELS)
	world.add_child(marker)
	marker.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.2, randf_range(-0.25, 0.25))
	marker.get_tree().create_timer(DAMAGE_NUMBER_LIFE).timeout.connect(marker.queue_free)


static func sound(world: Node, stream: AudioStream, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	world.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()


static func sound_at(world: Node, stream: AudioStream, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0, unit_size := 6.0, max_distance := 0.0) -> void:
	if world == null:
		return  # the game server has no scene to show it in
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.unit_size = unit_size
	audio.max_distance = max_distance   # (0 = heard from anywhere, fading with distance: gunshots)
	audio.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	world.add_child(audio)
	audio.global_position = pos
	audio.finished.connect(audio.queue_free)
	audio.play()


static func _cube_particles(color: Color, size: float, amount: int) -> CPUParticles3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = unshaded(color)
	var particles := CPUParticles3D.new()
	particles.mesh = mesh
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	# Not emitting until it's been moved into place (see _emit).
	particles.emitting = false
	return particles


## World-space particles spawn wherever the node is when emission starts, so place it first, then start it.
## (Starting before the move made every impact appear at the middle of the map.)
static func _emit(world: Node, particles: CPUParticles3D, pos: Vector3, free_after: float) -> void:
	world.add_child(particles)
	particles.global_position = pos
	particles.restart()
	_free_after(particles, free_after)


static func _free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds).timeout.connect(node.queue_free)
