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
## Where each model sits when aimed: centered, with its sight just under the middle of the screen
## (the new guns' are in GunViewModels.ADS).
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
## Prone (0.13.6), on top of the crouch bonus.
@export var prone_spread_multiplier := 0.75
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
@export var prone_recoil_multiplier := 0.7
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
## Shotguns (0.15.4): this many pellets per shot, each doing `damage`, spread over this many degrees.
var pellets := 1
var pellet_spread_deg := 0.0
## Damage drop with distance: [from m, to m, multiplier at the far end], or empty for none.
var falloff: Array = []
## Reload one round at a time (`reload_time` each); firing stops it.
var load_one := false
var flash_size := 1.0
## "pump" or "bolt": worked by hand between shots (0.15.6), shown on the model with a click; "" for none.
var cycle := ""
var _cycle_clicked := true
var shot_pitch := 1.0
var shot_db := -4.0

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
var _ads_positions := ADS_POSITIONS.duplicate()
## Where each model's muzzle sits with nothing on the barrel, and how far its optic raises the sight line.
var _muzzle_rests := {}
var _optic_raise := 0.0
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
	_models.merge(GunViewModels.build_all(self))
	_ads_positions.merge(GunViewModels.ADS)
	for key in _models:
		var node: Node3D = _models[key]
		_model_rests[key] = node.position
		_muzzle_rests[key] = (node.get_node("Muzzle") as Node3D).position
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
	if weapon != null and weapon == player.inventory.equipped(active_slot):
		_apply_stats(weapon)   # same gun, maybe new attachments
		_dress_model()
		return
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
	var data := _apply_stats(stack)
	_model_key = data["model"]
	model = _models[_model_key]
	muzzle = model.get_node("Muzzle")
	flash = muzzle.get_node("Flash")
	flash.visible = false
	model.visible = true
	_dress_model()
	# Start low so the new gun visibly comes up.
	model.position = (_model_rests[_model_key] as Vector3) + Vector3(0, -0.25, 0.05)


## Shows the weapon's attachments on its model (0.15.6).
func _dress_model() -> void:
	if model != null:
		_optic_raise = GunViewModels.dress(model, _model_key, weapon.attachments, _muzzle_rests[_model_key])


## Takes the weapon's stats, attachments included (0.15.1). Returns them.
func _apply_stats(stack: ItemStack) -> Dictionary:
	var data := ItemDB.weapon_stats(stack)
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
	pellets = int(data.get("pellets", 1))
	pellet_spread_deg = float(data.get("pellet_spread", 0.0))
	falloff = data.get("falloff", [])
	load_one = bool(data.get("load_one", false))
	flash_size = float(data.get("flash", 1.0))
	cycle = str(data.get("cycle", ""))
	shot_pitch = float(data.get("shot_pitch", 1.0))
	shot_db = float(data.get("shot_db", -4.0))
	return data


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

	if player.is_sprinting() or player.is_vaulting():
		_raise_left = maxf(_raise_left, raise_time)
	else:
		_raise_left = maxf(_raise_left - delta, 0.0)

	if not player.hands_free() or player.is_throwing():
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
	# Loading shells one at a time, you can fire whatever's in already (it stops loading).
	var loading_ok := not is_reloading or (load_one and in_mag > 0)
	if trigger and _cooldown <= 0.0 and loading_ok and is_ready_to_fire():
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
	if player.is_prone:
		spread *= prone_spread_multiplier
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
	if player.is_prone:
		stance *= prone_recoil_multiplier
	return Vector2(recoil_pitch_deg * up, recoil_yaw_deg * side) * stance


## Holding the aim button with a gun out (and able to use it). Aiming stops the player from sprinting.
func wants_aim() -> bool:
	# (not with the inventory open, where right-click is the item menu: owner 0.14.14)
	return (weapon != null and Input.is_action_pressed("aim") and player.hands_free()
		and not player.interactor.blocked and not player.is_throwing()
		and _aim_block_left <= 0.0)


## Knocked out of aiming for a moment (e.g. hit by a melee bash).
func block_aim(seconds: float) -> void:
	_aim_block_left = maxf(_aim_block_left, seconds)
	aim = 0.0


## Seconds since the last shot.
func since_shot() -> float:
	return _since_shot


func is_aiming() -> bool:
	return aim > 0.5


## What you see through the optic while fully aimed (0.15.4): "dot", "scope", or "" (iron sights or not aimed).
func reticle() -> String:
	if weapon == null or aim < 0.95:
		return ""
	for slot: String in weapon.attachments:
		var part: Dictionary = ItemDB.item(weapon.attachments[slot])
		if part.has("reticle"):
			return part["reticle"]
	return ""


## False while sprinting and for `raise_time` after.
func is_ready_to_fire() -> bool:
	return _raise_left <= 0.0 and not player.is_throwing()


func shoot_once() -> void:
	if weapon == null:
		return
	_cooldown = 60.0 / rounds_per_minute
	in_mag -= 1
	is_reloading = false
	var world := get_tree().current_scene

	var cam_basis := camera.global_basis
	var aim_dir := _spread_dir(cam_basis, -cam_basis.z, deg_to_rad(current_spread()))
	var from := camera.global_position
	# A shotgun's pellets spread around where the shot went.
	var dirs := PackedVector3Array()
	for i in pellets:
		dirs.append(aim_dir if pellets == 1 else _spread_dir(cam_basis, aim_dir, deg_to_rad(pellet_spread_deg)))

	# Online, other players (layer 2) can be hit too; the server decides whether they were.
	var online := Network.main.in_online_raid()
	var space := get_world_3d().direct_space_state
	var hits: Array[Dictionary] = []
	for dir in dirs:
		var to := from + dir * max_range
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | (2 if online else 0), [player.get_rid()])
		var result := space.intersect_ray(query)
		var end := to
		if not result.is_empty():
			end = result.position
			if result.collider is RemotePlayer or (result.collider is Scav and (result.collider as Scav).puppet):
				# Just the puff here; damage, the hit marker and the sound come when the server confirms.
				Effects.impact(world, result.position, result.normal, Player.HIT_COLOR, 12)
			else:
				hits.append(result)
		_warn_near_misses(from, end, result.get("collider"))
		Effects.tracer(world, muzzle.global_position, end)
	_handle_hits(hits, from)
	if online:
		Network.main.send_shot(from, dirs, weapon.id, weapon.attachments.values().has("suppressor"))

	Effects.sound(world, SHOT_SOUND, shot_db, 0.08, shot_pitch)
	_cycle_clicked = cycle == ""
	_flash_left = 0.045
	flash.visible = true
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * flash_size
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
	RaidScope.call_all(self, &"enemies", &"hear_noise", [player.global_position, noise_radius])
	RaidScope.call_all(self, &"enemies", &"notice_threat")


## `dir` turned a random amount (evenly inside a circle of `radius` radians) around the camera's axes.
func _spread_dir(cam_basis: Basis, dir: Vector3, radius: float) -> Vector3:
	var angle := randf() * TAU
	var r := radius * sqrt(randf())
	return dir.rotated(cam_basis.x, r * sin(angle)).rotated(cam_basis.y, r * cos(angle)).normalized()


## Enemies a bullet passed close to notice it, even if they're too far away to hear the shot.
func _warn_near_misses(from: Vector3, end: Vector3, hit: Variant) -> void:
	for enemy in RaidScope.nodes(self, &"enemies"):
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
	if not load_one:
		Effects.sound(get_tree().current_scene, MAG_OUT_SOUND)


func _update_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_left -= delta
	if not _mag_in_played and _reload_left <= reload_time * 0.4:
		_mag_in_played = true
		Effects.sound(get_tree().current_scene, MAG_IN_SOUND)
	if _reload_left <= 0.0 and load_one:
		# One round in; keep going while there's room and rounds to load.
		in_mag += player.inventory.take(ammo_id, 1)
		is_reloading = in_mag < mag_size and reserve > 0
		_reload_left = reload_time
		_mag_in_played = false
	elif _reload_left <= 0.0:
		in_mag += player.inventory.take(ammo_id, mag_size - in_mag)
		is_reloading = false


## What this shot's bullets (or pellets) hit: puffs on the world, damage on whatever has health. Pellets that hit
## the same target add up into one hit (one sound, one hit marker), a headshot if any of them was.
func _handle_hits(hits: Array[Dictionary], from: Vector3) -> void:
	var world := get_tree().current_scene
	var targets := {}   # Health -> [damage, headshot, position, normal]
	for result in hits:
		var collider: Object = result.collider
		var health := Health.of(collider)
		if health == null or health.is_dead:
			Effects.impact(world, result.position, result.normal, Color(0.85, 0.8, 0.6))
			continue
		var headshot := false
		if collider is CollisionObject3D:
			var body := collider as CollisionObject3D
			var shape_index: int = result.shape
			var shape_node := body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as Node
			headshot = shape_node != null and shape_node.name == &"HeadShape"
		var amount := damage * ItemDB.falloff_mult(falloff, from.distance_to(result.position)) * (headshot_multiplier if headshot else 1.0)
		if not targets.has(health):
			targets[health] = [0.0, false, result.position, result.normal]
		targets[health][0] += amount
		targets[health][1] = targets[health][1] or headshot
	for health: Health in targets:
		var hit: Array = targets[health]
		var headshot: bool = hit[1]
		var dealt := health.take_damage(roundi(hit[0]), player.global_position, false, headshot)
		player.on_hit_landed(health, hit[2], hit[3], dealt, headshot)
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

	var ads: Vector3 = _ads_positions[_model_key] - Vector3(0, _optic_raise, 0)
	var rest: Vector3 = (_model_rests[_model_key] as Vector3).lerp(ads, aim)
	var target_pos := rest + bob + Vector3(0, 0, 0.07 * _kick)
	var target_rot := Vector3(0.12 * _kick, 0, 0)
	if player.hands_busy():
		# Lowered out of the way while the other hand heals, drinks or holds a grenade (0.14.17).
		target_pos += Vector3(0.04, -0.32, 0.1)
		target_rot += Vector3(-0.8, 0.3, 0.2)
	elif sprinting:
		# Gun held low and across the body.
		target_pos += Vector3(-0.08, -0.1, 0.06)
		target_rot += Vector3(-0.35, 0.85, 0.35)
	elif player.knife.is_swinging():
		# Gun drops out of the way while the knife swings.
		target_pos += Vector3(0.05, -0.16, 0.05)
		target_rot += Vector3(-0.4, -0.3, 0.0)
	elif is_reloading and load_one:
		# Shells go in one at a time: the gun rolls over, a little push per shell.
		var push := sin(clampf(1.0 - _reload_left / maxf(reload_time, 0.01), 0.0, 1.0) * PI)
		target_pos += Vector3(-0.03, -0.07, 0.03 + 0.02 * push)
		target_rot += Vector3(-0.3, 0.2, 0.9)
	elif is_reloading:
		target_pos += Vector3(0, -0.08, 0.04)
		target_rot += Vector3(-0.5, 0.3, 0.4)
	elif cycle != "" and _since_shot < 60.0 / rounds_per_minute:
		# Working the pump or bolt between shots (0.15.6), with a click halfway.
		var t := _since_shot / (60.0 / rounds_per_minute)
		var work := sin(clampf((t - 0.15) / 0.7, 0.0, 1.0) * PI)
		if cycle == "pump":
			target_pos += Vector3(0, -0.01, 0.05 * work)
		else:
			target_pos += Vector3(0, -0.03 * work, 0.02 * work)
			target_rot += Vector3(0, 0, 0.45 * work)
		if t > 0.5 and not _cycle_clicked:
			_cycle_clicked = true
			Effects.sound(get_tree().current_scene, MAG_IN_SOUND, -6.0, 0.05, 1.4)
	# Raising the gun after a sprint is a bit slower than other moves.
	# While aiming the gun follows the aim amount closely (that's already smoothed).
	var weight := minf(delta * (10.0 if _raise_left > 0.0 else 18.0 + 30.0 * aim), 1.0)
	model.position = model.position.lerp(target_pos, weight)
	model.rotation = model.rotation.lerp(target_rot, weight)
	# Looking through a scope, the gun is out of the way (the HUD draws the scope's view).
	model.visible = reticle() != "scope"
