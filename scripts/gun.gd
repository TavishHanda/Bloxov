class_name Gun
extends Node3D
## Hitscan gun. Hold LMB to fire, R to reload. Lives under the player's camera.

signal hit_confirmed(killed: bool, headshot: bool)
signal fired

const SHOT_SOUND := preload("res://audio/shot.wav")
const HIT_SOUND := preload("res://audio/hit.wav")
const HEADSHOT_SOUND := preload("res://audio/headshot.wav")
const KILL_SOUND := preload("res://audio/kill.wav")
const EMPTY_SOUND := preload("res://audio/empty.wav")
const MAG_OUT_SOUND := preload("res://audio/mag_out.wav")
const MAG_IN_SOUND := preload("res://audio/mag_in.wav")

@export_group("Damage")
@export var damage := 22
@export var headshot_multiplier := 2.0
@export var max_range := 150.0

@export_group("Ammo")
@export var rounds_per_minute := 600.0
@export var mag_size := 30
@export var reserve_ammo := 90
@export var reload_time := 1.6

@export_group("Accuracy")
@export var base_spread_deg := 0.4
## Extra spread added per shot while spraying; recovers when you stop.
@export var bloom_per_shot_deg := 0.35
@export var max_bloom_deg := 3.0
@export var bloom_recovery_deg := 8.0
@export var moving_spread_deg := 1.5
@export var airborne_spread_deg := 4.0

@export_group("Handling")
## Time to bring the gun up after sprinting before you can fire.
@export var raise_time := 0.3

@export_group("Feel")
@export var recoil_pitch_deg := 1.1
@export var recoil_yaw_deg := 0.45
@export var shake := 0.12
## Gunshots alert enemies within this radius.
@export var noise_radius := 35.0

var in_mag: int
var reserve: int
var kills := 0
var is_reloading := false

@onready var player: Player = owner
@onready var camera: Camera3D = get_parent()
@onready var model: Node3D = $Model
@onready var muzzle: Marker3D = $Model/Muzzle
@onready var flash: Node3D = $Model/Muzzle/Flash

var _cooldown := 0.0
var _bloom := 0.0
var _reload_left := 0.0
var _mag_in_played := false
var _flash_left := 0.0
var _model_rest: Vector3
var _kick := 0.0
var _bob_time := 0.0
var _needs_trigger_release := true
## Counts down after sprinting; can't fire until it hits 0.
var _raise_left := 0.0


func _ready() -> void:
	in_mag = mag_size
	reserve = reserve_ammo
	_model_rest = model.position
	flash.visible = false


func _process(delta: float) -> void:
	_cooldown -= delta
	_bloom = move_toward(_bloom, 0.0, bloom_recovery_deg * delta)
	_update_reload(delta)
	_update_model(delta)

	if player.is_sprinting():
		_raise_left = raise_time
	else:
		_raise_left = maxf(_raise_left - delta, 0.0)

	if player.controls_locked() or player.is_healing():
		_needs_trigger_release = true
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Don't fire on the click that captures the mouse.
		_needs_trigger_release = true
		return
	if _needs_trigger_release:
		if not Input.is_action_pressed("shoot"):
			_needs_trigger_release = false
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_pressed("shoot") and _cooldown <= 0.0 and not is_reloading and is_ready_to_fire():
		if in_mag > 0:
			shoot_once()
		elif Input.is_action_just_pressed("shoot"):
			Effects.sound(get_tree().current_scene, EMPTY_SOUND)
			start_reload()


## False while sprinting and for `raise_time` after.
func is_ready_to_fire() -> bool:
	return _raise_left <= 0.0


func shoot_once() -> void:
	_cooldown = 60.0 / rounds_per_minute
	in_mag -= 1
	var world := get_tree().current_scene

	var moving := player.horizontal_speed() > 1.0
	var spread_deg := base_spread_deg + _bloom + (moving_spread_deg if moving else 0.0)
	if not player.is_on_floor():
		spread_deg += airborne_spread_deg
	var spread := deg_to_rad(spread_deg)
	var cam_basis := camera.global_basis
	var dir := -cam_basis.z
	dir = dir.rotated(cam_basis.x, randf_range(-spread, spread)).rotated(cam_basis.y, randf_range(-spread, spread))
	var from := camera.global_position
	var to := from + dir * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [player.get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		_handle_hit(result)

	Effects.tracer(world, muzzle.global_position, end)
	Effects.sound(world, SHOT_SOUND, -4.0)
	_flash_left = 0.045
	flash.visible = true
	flash.rotation.z = randf() * TAU
	_kick = 1.0
	_bloom = minf(_bloom + bloom_per_shot_deg, max_bloom_deg)
	player.add_recoil(recoil_pitch_deg, randf_range(-recoil_yaw_deg, recoil_yaw_deg))
	player.add_shake(shake)
	get_tree().call_group("enemies", "hear_noise", player.global_position, noise_radius)
	fired.emit()


func start_reload() -> void:
	if is_reloading or in_mag >= mag_size or reserve <= 0:
		return
	is_reloading = true
	_reload_left = reload_time
	_mag_in_played = false
	Effects.sound(get_tree().current_scene, MAG_OUT_SOUND)


func _update_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_left -= delta
	if not _mag_in_played and _reload_left <= reload_time * 0.4:
		_mag_in_played = true
		Effects.sound(get_tree().current_scene, MAG_IN_SOUND)
	if _reload_left <= 0.0:
		var needed := mag_size - in_mag
		var taken := mini(needed, reserve)
		in_mag += taken
		reserve -= taken
		is_reloading = false


func _handle_hit(result: Dictionary) -> void:
	var world := get_tree().current_scene
	var collider: Object = result.collider
	var hit_pos: Vector3 = result.position
	var normal: Vector3 = result.normal
	var health: Health = null
	if collider is Node:
		health = (collider as Node).get_node_or_null("Health") as Health

	if health == null or health.is_dead:
		Effects.impact(world, hit_pos, normal, Color(0.85, 0.8, 0.6))
		return

	var headshot := false
	if collider is CollisionObject3D:
		var body := collider as CollisionObject3D
		var shape_index: int = result.shape
		var shape_node := body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as Node
		headshot = shape_node != null and shape_node.name == &"HeadShape"

	var amount := roundi(damage * (headshot_multiplier if headshot else 1.0))
	health.take_damage(amount, player.global_position)
	Effects.damage_number(world, hit_pos, amount, headshot)
	Effects.impact(world, hit_pos, normal, Color(0.95, 0.25, 0.2), 12)
	if health.is_dead:
		kills += 1
		Effects.sound(world, KILL_SOUND, -2.0, 0.0)
	else:
		Effects.sound(world, HEADSHOT_SOUND if headshot else HIT_SOUND, -3.0, 0.03)
	hit_confirmed.emit(health.is_dead, headshot)


func _update_model(delta: float) -> void:
	_flash_left -= delta
	if _flash_left <= 0.0:
		flash.visible = false
	_kick = move_toward(_kick, 0.0, delta * 9.0)

	var speed := player.horizontal_speed() if player.is_on_floor() else 0.0
	var sprinting := player.is_sprinting()
	_bob_time += delta * speed * (2.0 if sprinting else 2.6)
	var bob_scale := minf(speed / player.walk_speed, 1.0) * (2.2 if sprinting else 1.0)
	var bob := Vector3(sin(_bob_time) * 0.012, absf(cos(_bob_time)) * 0.014, 0.0) * bob_scale

	var target_pos := _model_rest + bob + Vector3(0, 0, 0.07 * _kick)
	var target_rot := Vector3(0.12 * _kick, 0, 0)
	if sprinting:
		# Gun held low and across the body.
		target_pos += Vector3(-0.08, -0.1, 0.06)
		target_rot += Vector3(-0.35, 0.85, 0.35)
	elif is_reloading:
		target_pos += Vector3(0, -0.08, 0.04)
		target_rot += Vector3(-0.5, 0.3, 0.4)
	# Raising the gun after a sprint is a bit slower than other moves.
	var weight := minf(delta * (10.0 if _raise_left > 0.0 else 18.0), 1.0)
	model.position = model.position.lerp(target_pos, weight)
	model.rotation = model.rotation.lerp(target_rot, weight)
