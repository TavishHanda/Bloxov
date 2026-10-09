class_name Gun
extends Node3D
## Hitscan gun. LMB to fire, hold RMB to aim down sights, R to reload, 1/2 to switch weapons, V to knife.
## Lives under the player's camera.
## Fires whatever weapon is equipped in the active slot (primary/secondary); its stats come from ItemDB.
## Equipping a weapon overwrites these exports with its ItemDB stats: damage, headshot_multiplier,
## rounds_per_minute, mag_size, reload_time, ammo_id, auto (not exported), base/hip/moving spread,
## bloom_per_shot_deg, max_bloom_deg, ads_time, ads_fov, recoil_pitch_deg, recoil_yaw_deg and noise_radius.
## The defaults below match the AK. Everything else (range, flinch, handling, crouch modifiers...) is shared.

signal hit_confirmed(killed: bool, headshot: bool)

const SHOT_SOUND := preload("res://audio/shot.wav")
const HIT_SOUND := preload("res://audio/hit.wav")
const HEADSHOT_SOUND := preload("res://audio/headshot.wav")
const KILL_SOUND := preload("res://audio/kill.wav")
const EMPTY_SOUND := preload("res://audio/empty.wav")
const MAG_OUT_SOUND := preload("res://audio/mag_out.wav")
const MAG_IN_SOUND := preload("res://audio/mag_in.wav")
## Where each model sits when aimed: centered, with its sight just under the middle of the screen.
const ADS_POSITIONS := {"rifle": Vector3(0, -0.092, -0.36), "pistol": Vector3(0, -0.036, -0.28)}

@export_group("Damage")
@export var damage := 28
## Headshot damage multiplier (per gun: AK 2x, pistol 2.5x).
@export var headshot_multiplier := 2.0
@export var max_range := 150.0

@export_group("Ammo")
@export var rounds_per_minute := 600.0
@export var mag_size := 30
## Item id of the rounds this gun loads (taken from the player's inventory when reloading).
@export var ammo_id := "rifle_ammo"
@export var reload_time := 1.6

@export_group("Accuracy")
## Spread is the radius (degrees) of the circle shots land in, spread evenly over it.
## Design targets (scav chest at 20 m, see GUNS_PLAN.md): hip ~75% hits standing, ~90% crouched, ~20% walking;
## aimed ~100% standing or crouched, ~90% walking.
## Spread when fully aimed down sights.
@export var base_spread_deg := 0.15
## Extra spread when firing from the hip (fades out as you aim in).
@export var hip_spread_deg := 0.68
## Extra spread while moving (reduced while aiming).
@export var moving_spread_deg := 0.75
@export var airborne_spread_deg := 4.0
## Crouching tightens your spread.
@export var crouch_spread_multiplier := 0.9
## Extra spread added per shot while spraying; recovers when you stop. Much smaller while aiming.
@export var bloom_per_shot_deg := 0.12
@export var max_bloom_deg := 1.2
@export var bloom_recovery_deg := 6.0
@export var ads_bloom_multiplier := 0.4
## Getting shot loosens your aim for a moment: extra spread per 25 damage, fading at flinch_recovery_deg/s.
@export var flinch_spread_deg := 1.2
@export var flinch_recovery_deg := 3.0

@export_group("Aiming")
## Seconds to go from hip to fully aimed.
@export var ads_time := 0.28
## Camera field of view when fully aimed (the normal view is the player's base_fov).
@export var ads_fov := 55.0
## Aiming cuts the moving-spread penalty to this fraction.
@export var ads_moving_spread_multiplier := 0.8

@export_group("Handling")
## Time to bring the gun up after sprinting before you can fire.
@export var raise_time := 0.3
## Time to swap between primary and secondary.
@export var switch_time := 0.45

@export_group("Recoil")
## Each shot moves your view up by about this much (degrees); you pull the mouse down against it.
## Full-auto follows a pattern you can learn: the first shots climb hardest, then it drifts side to side.
@export var recoil_pitch_deg := 1.2
## How far the pattern drifts sideways per shot (degrees), plus a little randomness.
@export var recoil_yaw_deg := 0.45
@export var crouch_recoil_multiplier := 0.85
## Part of the recoil that's just a quick visual kick (settles by itself).
@export var recoil_kick_fraction := 0.25

@export_group("Feel")
@export var shake := 0.12
## Gunshots alert enemies within this radius.
@export var noise_radius := 25.0

## The equipped weapon stack firing right now (null = unarmed), and its slot.
var weapon: ItemStack = null
var active_slot := "primary"
## Full-auto (hold) or semi-auto (one shot per click).
var auto := true

## Rounds loaded in the current weapon (stored on its ItemStack, so each gun keeps its own).
var in_mag: int:
	get:
		return weapon.loaded if weapon != null else 0
	set(value):
		if weapon != null:
			weapon.loaded = value
## Matching rounds the player is carrying.
var reserve: int:
	get:
		return player.inventory.count_of(ammo_id) if player != null else 0
var is_reloading := false
## 0 = hip, 1 = fully aimed down sights. Moves smoothly between them.
var aim := 0.0

@onready var player: Player = owner
@onready var camera: Camera3D = get_parent()
@onready var _models := {"rifle": $Model, "pistol": $PistolModel}
var model: Node3D
var muzzle: Node3D
var flash: Node3D
var _model_rests := {}
## Key into _models / ADS_POSITIONS for the equipped weapon ("rifle"/"pistol").
var _model_key := ""

var _cooldown := 0.0
var _bloom := 0.0
var _flinch_spread := 0.0
var _aim_block_left := 0.0
## Shots fired in the current burst (resets shortly after you stop), for the recoil pattern.
var _burst_shots := 0
var _since_shot := 99.0
var _reload_left := 0.0
var _mag_in_played := false
var _flash_left := 0.0
var _kick := 0.0
var _bob_time := 0.0
var _needs_trigger_release := true
## Counts down after sprinting; can't fire until it hits 0.
var _raise_left := 0.0


func _ready() -> void:
	for key in _models:
		var node: Node3D = _models[key]
		_model_rests[key] = node.position
		node.visible = false
		(node.get_node("Muzzle/Flash") as Node3D).visible = false
	# The player's own @onready vars aren't set yet (children are ready first), so look the inventory up directly.
	(player.get_node("Inventory") as Inventory).equipment_changed.connect(_on_equipment_changed)


## Switch to the weapon in a slot ("primary"/"secondary"), if there is one.
func select_slot(slot: String) -> void:
	var stack := player.inventory.equipped(slot)
	if stack == null or (slot == active_slot and stack == weapon):
		return
	active_slot = slot
	_apply_weapon(stack)


func _on_equipment_changed() -> void:
	var current := player.inventory.equipped(active_slot)
	if current == null:
		var other := "secondary" if active_slot == "primary" else "primary"
		if player.inventory.equipped(other) != null:
			active_slot = other
			current = player.inventory.equipped(other)
	if current != weapon:
		_apply_weapon(current)


func _apply_weapon(stack: ItemStack) -> void:
	weapon = stack
	is_reloading = false
	_raise_left = switch_time
	for key in _models:
		(_models[key] as Node3D).visible = false
	if stack == null:
		model = null
		return
	var data := ItemDB.item(stack.id)
	damage = data["damage"]
	rounds_per_minute = data["rpm"]
	mag_size = data["mag"]
	reload_time = data["reload"]
	ammo_id = data["ammo"]
	headshot_multiplier = data["head"]
	auto = data["auto"]
	base_spread_deg = data["spread"]
	hip_spread_deg = data["hip_spread"]
	moving_spread_deg = data["move_spread"]
	ads_time = data["ads_time"]
	ads_fov = data["ads_fov"]
	bloom_per_shot_deg = data["bloom"]
	max_bloom_deg = data["max_bloom"]
	recoil_pitch_deg = data["recoil"]
	recoil_yaw_deg = data["recoil_yaw"]
	noise_radius = data["noise"]
	_model_key = data["model"]
	model = _models[_model_key]
	muzzle = model.get_node("Muzzle")
	flash = muzzle.get_node("Flash")
	flash.visible = false
	model.visible = true
	# Start low so the new gun visibly comes up.
	model.position = (_model_rests[_model_key] as Vector3) + Vector3(0, -0.25, 0.05)


func _process(delta: float) -> void:
	_cooldown -= delta
	_bloom = move_toward(_bloom, 0.0, bloom_recovery_deg * delta)
	_flinch_spread = move_toward(_flinch_spread, 0.0, flinch_recovery_deg * delta)
	_aim_block_left -= delta
	_since_shot += delta
	var aim_target := 1.0 if wants_aim() and not player.is_sprinting() and not is_reloading and not player.knife.is_swinging() else 0.0
	aim = move_toward(aim, aim_target, delta / maxf(ads_time, 0.01))
	_update_reload(delta)
	_update_model(delta)

	if player.is_sprinting():
		_raise_left = maxf(_raise_left, raise_time)
	else:
		_raise_left = maxf(_raise_left - delta, 0.0)

	if player.controls_locked() or player.is_healing():
		_needs_trigger_release = true
		return
	# Quick melee works with or without a gun; it cancels a reload (no rounds lost).
	if Input.is_action_just_pressed("melee") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.knife.swing():
		is_reloading = false
	if weapon == null:
		return
	if player.knife.is_swinging():
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
	var trigger := Input.is_action_pressed("shoot") if auto else Input.is_action_just_pressed("shoot")
	if trigger and _cooldown <= 0.0 and not is_reloading and is_ready_to_fire():
		if in_mag > 0:
			shoot_once()
		elif Input.is_action_just_pressed("shoot"):
			Effects.sound(get_tree().current_scene, EMPTY_SOUND)
			start_reload()


## Spread (degrees) for a situation, not counting bloom or flinch. `aim_amount`: 0 = hip, 1 = aimed.
func spread_for(aim_amount: float, moving: bool, crouching: bool, airborne: bool) -> float:
	var spread := base_spread_deg + hip_spread_deg * (1.0 - aim_amount)
	if moving:
		spread += moving_spread_deg * lerpf(1.0, ads_moving_spread_multiplier, aim_amount)
	if airborne:
		spread += airborne_spread_deg
	elif crouching:
		spread *= crouch_spread_multiplier
	return spread


## Spread right now, including bloom from spraying and flinch from getting shot.
func current_spread() -> float:
	var moving := player.horizontal_speed() > 1.0
	var spread := spread_for(aim, moving, player.is_crouching, not player.is_on_floor())
	return spread + _bloom * lerpf(1.0, ads_bloom_multiplier, aim) + _flinch_spread


## Called when the player gets shot.
func add_flinch(amount: int) -> void:
	_flinch_spread = minf(_flinch_spread + flinch_spread_deg * amount / 25.0, 4.0)


## Recoil for the nth shot of a burst (0-based): x = up, y = sideways (degrees).
func recoil_for_shot(n: int) -> Vector2:
	# Climbs harder over the first shots, then eases off once the burst is long (still climbing).
	var up := minf(0.7 + 0.15 * n, 1.15) if n < 12 else 0.55
	# Slight pull left, then right, then back: a slow side-to-side drift.
	var side := sin(n * 0.45 - 0.8) * 1.4 + randf_range(-0.3, 0.3)
	var stance := crouch_recoil_multiplier if player.is_crouching else 1.0
	return Vector2(recoil_pitch_deg * up, recoil_yaw_deg * side) * stance


## Holding the aim button with a gun out (and able to use it). Aiming stops the player from sprinting.
func wants_aim() -> bool:
	return (weapon != null and Input.is_action_pressed("aim") and not player.controls_locked()
		and not player.is_healing() and _aim_block_left <= 0.0)


## Knocked out of aiming for a moment (e.g. hit by a melee bash).
func block_aim(seconds: float) -> void:
	_aim_block_left = maxf(_aim_block_left, seconds)
	aim = 0.0


func is_aiming() -> bool:
	return aim > 0.5


## False while sprinting and for `raise_time` after.
func is_ready_to_fire() -> bool:
	return _raise_left <= 0.0


func shoot_once() -> void:
	if weapon == null:
		return
	_cooldown = 60.0 / rounds_per_minute
	in_mag -= 1
	var world := get_tree().current_scene

	# Pick a point evenly inside the spread circle.
	var spread := deg_to_rad(current_spread())
	var angle := randf() * TAU
	var radius := spread * sqrt(randf())
	var cam_basis := camera.global_basis
	var dir := -cam_basis.z
	dir = dir.rotated(cam_basis.x, radius * sin(angle)).rotated(cam_basis.y, radius * cos(angle))
	var from := camera.global_position
	var to := from + dir * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [player.get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		_handle_hit(result)

	_warn_near_misses(from, end, result.get("collider"))
	Effects.tracer(world, muzzle.global_position, end)
	Effects.sound(world, SHOT_SOUND, -4.0)
	_flash_left = 0.045
	flash.visible = true
	flash.rotation.z = randf() * TAU
	_kick = 1.0
	_bloom = minf(_bloom + bloom_per_shot_deg, max_bloom_deg)
	if _since_shot > 60.0 / rounds_per_minute + 0.15:
		_burst_shots = 0
	var kick := recoil_for_shot(_burst_shots)
	_burst_shots += 1
	_since_shot = 0.0
	player.add_recoil(kick.x * (1.0 - recoil_kick_fraction), kick.y)
	player.add_kick(kick.x * recoil_kick_fraction, 0.0)
	player.add_shake(shake)
	get_tree().call_group("enemies", "hear_noise", player.global_position, noise_radius)
	get_tree().call_group("enemies", "notice_threat")


## Enemies a bullet passed close to notice it, even if they're too far away to hear the shot.
func _warn_near_misses(from: Vector3, end: Vector3, hit: Variant) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == hit or not (enemy is Scav):
			continue
		var scav := enemy as Scav
		var chest := scav.global_position + Vector3(0, 1.2, 0)
		var closest := Geometry3D.get_closest_point_to_segment(chest, from, end)
		if closest.distance_to(chest) <= scav.near_miss_radius:
			scav.notice_near_miss(player.global_position)


func start_reload() -> void:
	if weapon == null or is_reloading or in_mag >= mag_size or reserve <= 0:
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
		in_mag += player.inventory.take(ammo_id, mag_size - in_mag)
		is_reloading = false


func _handle_hit(result: Dictionary) -> void:
	var world := get_tree().current_scene
	var collider: Object = result.collider
	var hit_pos: Vector3 = result.position
	var normal: Vector3 = result.normal
	var health := Health.of(collider)

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
	var dealt := health.take_damage(amount, player.global_position)
	player.on_hit_landed(health, hit_pos, normal, dealt, headshot)
	if health.is_dead:
		Effects.sound(world, KILL_SOUND, -2.0, 0.0)
	else:
		Effects.sound(world, HEADSHOT_SOUND if headshot else HIT_SOUND, -3.0, 0.03)
	hit_confirmed.emit(health.is_dead, headshot)


func _update_model(delta: float) -> void:
	if model == null:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		flash.visible = false
	_kick = move_toward(_kick, 0.0, delta * 9.0)

	var speed := player.horizontal_speed() if player.is_on_floor() else 0.0
	var sprinting := player.is_sprinting()
	_bob_time += delta * speed * (2.0 if sprinting else 2.6)
	var bob_scale := minf(speed / player.walk_speed, 1.0) * (2.2 if sprinting else 1.0)
	var bob := Vector3(sin(_bob_time) * 0.012, absf(cos(_bob_time)) * 0.014, 0.0) * bob_scale * (1.0 - 0.85 * aim)

	var rest: Vector3 = (_model_rests[_model_key] as Vector3).lerp(ADS_POSITIONS[_model_key], aim)
	var target_pos := rest + bob + Vector3(0, 0, 0.07 * _kick)
	var target_rot := Vector3(0.12 * _kick, 0, 0)
	if sprinting:
		# Gun held low and across the body.
		target_pos += Vector3(-0.08, -0.1, 0.06)
		target_rot += Vector3(-0.35, 0.85, 0.35)
	elif player.knife.is_swinging():
		# Gun drops out of the way while the knife swings.
		target_pos += Vector3(0.05, -0.16, 0.05)
		target_rot += Vector3(-0.4, -0.3, 0.0)
	elif is_reloading:
		target_pos += Vector3(0, -0.08, 0.04)
		target_rot += Vector3(-0.5, 0.3, 0.4)
	# Raising the gun after a sprint is a bit slower than other moves.
	# While aiming the gun follows the aim amount closely (that's already smoothed).
	var weight := minf(delta * (10.0 if _raise_left > 0.0 else 18.0 + 30.0 * aim), 1.0)
	model.position = model.position.lerp(target_pos, weight)
	model.rotation = model.rotation.lerp(target_rot, weight)
