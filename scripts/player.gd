class_name Player
extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump, C to crouch, Q/E to lean.
## Aiming down sights (RMB, handled by the Gun) slows you down, zooms the camera and stops sprinting.

## Emitted for every sound the player makes that enemies can hear (footsteps, landing).
signal noise_made(pos: Vector3, radius: float)

const HURT_SOUND := preload("res://audio/hurt.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")
## Blood-red sparks where the player's gun or knife hits someone.
const HIT_COLOR := Color(0.95, 0.25, 0.2)
const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/step1.wav"), preload("res://audio/step2.wav"), preload("res://audio/step3.wav")]

@export_group("Movement")
## Meters per second. For reference, a real jog is ~3, a run ~5.
@export var walk_speed := 3.4
## Sprint only works moving forward, and lowers your gun.
@export var sprint_speed := 5.6
## Speed multipliers when walking backwards / sideways.
@export var backward_multiplier := 0.7
@export var strafe_multiplier := 0.85
## How fast you speed up and slow down on the ground (m/s per second). Lower = heavier.
@export var ground_acceleration := 16.0
@export var ground_deceleration := 20.0
## How much you can steer in the air (m/s per second). Low = jumps commit you.
@export var air_control := 2.5
## About 0.6 m high.
@export var jump_velocity := 3.6
@export var jump_cooldown := 0.45
## Landing from a jump or fall slows you briefly.
@export var landing_slowdown_time := 0.3
@export var landing_slowdown := 0.5
## Speed multiplier while fully aimed down sights.
@export var ads_move_multiplier := 0.7

@export_group("Crouch")
## C toggles crouch. Slower, quieter, smaller, steadier aim.
@export var crouch_speed := 1.8
@export var stand_height := 1.8
@export var crouch_height := 1.2
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 1.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Per second while sprinting. 100 / 12 = about 8 seconds of sprint.
@export var sprint_drain := 12.0
@export var jump_cost := 12.0
@export var stamina_regen := 16.0
## Seconds after sprinting/jumping before stamina starts coming back.
@export var stamina_regen_delay := 1.0
## Run out completely and you can't sprint again until stamina is back to this.
@export var exhausted_recover_at := 25.0

@export_group("Footsteps")
## Meters between footsteps.
@export var walk_stride := 1.5
@export var sprint_stride := 1.9
@export var crouch_stride := 1.1
## How far away enemies hear each step (meters). 0 = silent.
@export var walk_noise := 7.0
@export var sprint_noise := 15.0
@export var crouch_noise := 0.0
@export var landing_noise := 10.0

@export_group("Lean")
## Q/E: the head shifts sideways and tilts to peek around corners. Can't sprint while leaning; walk slower.
## The body (hitbox) stays put, so peeking only exposes what the camera can see past.
@export var lean_distance := 0.35
@export var lean_angle_deg := 12.0
@export var lean_speed := 8.0
@export var lean_move_multiplier := 0.6

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var base_fov := 80.0
## Extra field of view while sprinting, for a sense of speed.
@export var sprint_fov_boost := 6.0
## Head bob strength (meters) when walking / sprinting.
@export var walk_bob := 0.03
@export var sprint_bob := 0.055
## Camera lean when strafing (degrees).
@export var strafe_tilt := 1.5

@export_group("Recoil")
## How quickly the quick visual kick (and flinch from getting shot) settles.
@export var recoil_recovery := 9.0
## After you stop firing, the recoil you didn't pull down against returns at this rate (per second, smoothed).
@export var recoil_return_speed := 7.0
## Seconds after the last shot before recoil starts returning.
@export var recoil_return_delay := 0.12
## Getting shot kicks your aim this far (degrees, at 25 damage; scales with damage).
@export var flinch_deg := 2.2

@export_group("Other")
## Mouse movements bigger than this (in pixels, in one event) are treated as glitches and ignored.
## Works around a Chrome bug where captured-mouse input sometimes reports a huge bogus jump.
@export var max_mouse_delta := 200.0
## Falling below this height respawns the player.
@export var kill_height := -20.0

@onready var head: Node3D = $Head
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var recoil: Node3D = $Head/Recoil
@onready var camera: Camera3D = $Head/Recoil/Camera3D
@onready var gun: Gun = $Head/Recoil/Camera3D/Gun
@onready var knife: Knife = $Head/Recoil/Camera3D/Knife
@onready var health: Health = $Health
@onready var inventory: Inventory = $Inventory
@onready var interactor: Interactor = $Interactor

var is_dead := false
## Enemies killed this raid (gun or knife).
var kills := 0
## True once the player has extracted (raid over, controls off).
var extracted := false

## Seconds left on the current heal, and the item being used.
var heal_time_left := 0.0
var heal_duration := 0.0
var _heal_item := ""

var _spawn_position: Vector3
var _trauma := 0.0
var _sprinting := false
## Recoil that went into the view (x = pitch, y = yaw, radians) and hasn't been pulled down against yet.
## It returns after a burst, so if you compensated with the mouse the view doesn't dip below the target.
var _recoil_debt := Vector2.ZERO
var _recoil_return_wait := 0.0
var _sprint_fov := 0.0
## -1 = fully leaning left, 1 = right (smoothed). _lean_toggled is the held direction in tap-to-toggle mode.
var lean := 0.0
var _lean_toggled := 0
var _jump_cooldown_left := 0.0
var _landing_left := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _bob_time := 0.0
var _landing_dip := 0.0
var _move_input := Vector2.ZERO
var _roll := 0.0

var is_crouching := false
var stamina := 100.0
## True after running out of stamina, until it recovers to `exhausted_recover_at`.
var is_exhausted := false
var _stamina_delay_left := 0.0
var _stride_left := 0.0

# Mouse debug stats, shown by the HUD's F3 overlay.
var debug_recent_dx: Array[int] = []
var debug_max_delta := 0.0
var debug_spikes_dropped := 0


func _ready() -> void:
	add_to_group("player")
	# The capsule comes from player.tscn and is shared by every instance; give each player its own,
	# so one player crouching doesn't shrink the others.
	body_shape.shape = body_shape.shape.duplicate()
	_spawn_position = global_position
	inventory.equipment_changed.connect(_on_equipment_changed)
	# Bring in the loadout from the hideout (or the starter kit on a new profile).
	Profile.load_profile()
	Profile.apply_inventory(inventory, Profile.loadout)
	# Until you extract, the saved profile counts you as dead (so closing the tab mid-raid loses your gear).
	Profile.loadout = Profile.death_loadout(Profile.loadout)
	Profile.save_profile()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func controls_locked() -> bool:
	return is_dead or extracted


func is_healing() -> bool:
	return heal_time_left > 0.0


## True while actually sprinting (holding Shift, moving forward, on the ground).
func is_sprinting() -> bool:
	return _sprinting


## Height of the player's eyes / chest above their feet (lower when crouched). Used by enemies to aim.
func eye_height() -> float:
	return head.position.y


## Where the player's eyes actually are (includes leaning). Enemies check line of sight to this.
func eye_position() -> Vector3:
	return head.global_position


func chest_height() -> float:
	return (body_shape.shape as CapsuleShape3D).height * 0.65


func set_crouching(crouch: bool) -> void:
	if crouch == is_crouching:
		return
	if not crouch and _ceiling_blocked():
		return
	is_crouching = crouch
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = crouch_height if crouch else stand_height
	body_shape.position.y = capsule.height * 0.5


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	_spawn_position = pos
	velocity = Vector3.ZERO


func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)


## Called by the Raid when you make it out.
func extract() -> void:
	extracted = true
	heal_time_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## H key: use the heal item that best fits how hurt you are.
func try_heal() -> void:
	var found := inventory.find_heal(health.max_health - health.current)
	if not found.is_empty():
		use_item(found[0], found[1])


## Uses the item bound to a hotbar key (0 = key 3).
func use_hotbar(index: int) -> void:
	var id := inventory.hotbar[index]
	if id == "":
		return
	var found := inventory.find(id)
	if not found.is_empty():
		use_item(found[0], found[1])


## Feedback for a hit the player's gun or knife landed (after the damage): damage number, sparks, kill count.
## `critical` = headshot or backstab (bigger damage number). The caller plays its own sound.
func on_hit_landed(target_health: Health, pos: Vector3, normal: Vector3, amount: int, critical: bool) -> void:
	var world := get_tree().current_scene
	if GameSettings.damage_numbers:
		Effects.damage_number(world, pos, amount, critical)
	Effects.impact(world, pos, normal, HIT_COLOR, 12)
	if target_health.is_dead:
		kills += 1


func _hotbar_key(event: InputEvent) -> int:
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 3)):
			return i
	return -1


func _on_equipment_changed() -> void:
	health.damage_multiplier = 1.0 - inventory.armor_reduction()


## Use one heal item from a stack. Takes a few seconds; you can't shoot meanwhile.
func use_item(grid: GridInventory, stack: ItemStack) -> void:
	if controls_locked() or is_healing() or health.current >= health.max_health:
		return
	if ItemDB.kind(stack.id) != "heal":
		return
	# Nothing taken = the stack is already gone (e.g. used mid-drag); don't heal for free.
	if grid.take(stack.id, 1) == 0:
		return
	_heal_item = stack.id
	heal_duration = ItemDB.item(stack.id)["use_time"]
	heal_time_left = heal_duration
	Effects.sound(get_tree().current_scene, HEAL_SOUND, -4.0)


## Gun recoil: moves where you're looking (you pull the mouse down against it). Returns after the burst.
func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	_look(pitch, yaw)
	_recoil_debt += Vector2(pitch, yaw)
	_recoil_return_wait = recoil_return_delay


## A quick visual kick of the camera that settles by itself (doesn't move where you're looking for long).
## Shots go where the camera points, so this throws off shots while it lasts.
func add_kick(pitch_deg: float, yaw_deg: float) -> void:
	recoil.rotation.x += deg_to_rad(pitch_deg)
	recoil.rotation.y += deg_to_rad(yaw_deg)


func _look(pitch: float, yaw: float) -> void:
	rotate_y(yaw)
	head.rotation.x = clampf(head.rotation.x + pitch, deg_to_rad(-89.0), deg_to_rad(89.0))


## Screen shake. Amounts stack up to 1.0 and fade out.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked():
		return
	# Capturing the mouse (click to play) is handled by the HUD's pause menu.
	var hotbar_index := _hotbar_key(event)
	if event.is_action_pressed("heal"):
		try_heal()
	elif event.is_action_pressed("weapon_1"):
		gun.select_slot("primary")
	elif event.is_action_pressed("weapon_2"):
		gun.select_slot("secondary")
	elif hotbar_index >= 0:
		use_hotbar(hotbar_index)
	elif event.is_action_pressed("crouch"):
		set_crouching(not is_crouching)
	elif GameSettings.lean_toggle and (event.is_action_pressed("lean_left") or event.is_action_pressed("lean_right")):
		var dir := -1 if event.is_action_pressed("lean_left") else 1
		_lean_toggled = 0 if _lean_toggled == dir else dir
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var delta_len: float = event.screen_relative.length()
		debug_max_delta = maxf(debug_max_delta, delta_len)
		debug_recent_dx.append(roundi(event.screen_relative.x))
		if debug_recent_dx.size() > 12:
			debug_recent_dx.pop_front()
		if delta_len > max_mouse_delta:
			debug_spikes_dropped += 1
			return
		# Zoomed in = slower look, so aiming feels the same at any zoom.
		var sens := mouse_sensitivity * GameSettings.sensitivity * camera.fov / base_fov
		var yaw: float = -event.screen_relative.x * sens
		var pitch: float = -event.screen_relative.y * sens
		_look(pitch, yaw)
		# Pulling against recoil pays it off, so it won't also return on its own.
		if pitch * _recoil_debt.x < 0.0:
			_recoil_debt.x = 0.0 if absf(pitch) >= absf(_recoil_debt.x) else _recoil_debt.x + pitch
		if yaw * _recoil_debt.y < 0.0:
			_recoil_debt.y = 0.0 if absf(yaw) >= absf(_recoil_debt.y) else _recoil_debt.y + yaw


func _process(delta: float) -> void:
	recoil.rotation = recoil.rotation.lerp(Vector3.ZERO, minf(recoil_recovery * delta, 1.0))
	_recoil_return_wait -= delta
	if _recoil_return_wait <= 0.0 and _recoil_debt != Vector2.ZERO:
		var step := _recoil_debt * minf(recoil_return_speed * delta, 1.0)
		if _recoil_debt.length() < 0.0005:
			step = _recoil_debt
		_look(-step.x, -step.y)
		_recoil_debt -= step
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var shake := _trauma * _trauma
	camera.h_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	_update_camera_motion(delta, shake)
	# Eyes move smoothly between standing and crouched height.
	if not controls_locked():
		var eye := crouch_eye_height if is_crouching else stand_eye_height
		head.position.y = lerpf(head.position.y, eye, minf(delta * 10.0, 1.0))
	_update_lean(delta)
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0:
			heal_time_left = 0.0
			health.heal(ItemDB.item(_heal_item)["heal"])


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity += get_gravity() * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_jump_cooldown_left -= delta
	_landing_left -= delta

	var input_dir := Vector2.ZERO
	if not controls_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and on_floor:
			if is_crouching:
				set_crouching(false)
			elif _jump_cooldown_left <= 0.0 and stamina >= jump_cost:
				velocity.y = jump_velocity
				_jump_cooldown_left = jump_cooldown
				_use_stamina(jump_cost)
	_move_input = input_dir

	# Sprint: only forward-ish, on the ground, not while healing, needs stamina. Sprinting stands you up.
	var wants_sprint := (not controls_locked() and on_floor and not is_healing() and not is_exhausted
		and Input.is_action_pressed("sprint") and input_dir.y < -0.5 and not gun.wants_aim() and not is_leaning())
	if wants_sprint and is_crouching:
		set_crouching(false)
	_sprinting = wants_sprint and not is_crouching
	_update_stamina(delta)

	var target := _target_velocity(input_dir)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		var rate := ground_acceleration if target.length() > horizontal.length() else ground_deceleration
		horizontal = horizontal.move_toward(target, rate * delta)
	else:
		# In the air you keep your momentum and can only nudge it.
		horizontal = horizontal.move_toward(target, air_control * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	# Landing.
	if is_on_floor() and not _was_on_floor and _fall_speed > 2.0:
		_landing_left = landing_slowdown_time
		_landing_dip = clampf(_fall_speed * 0.02, 0.03, 0.15)
		_play_step(4.0)
		_make_noise(landing_noise)
	if is_on_floor():
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_update_footsteps(delta)

	if global_position.y < kill_height:
		global_position = _spawn_position
		velocity = Vector3.ZERO


func _target_velocity(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var speed := sprint_speed if _sprinting else walk_speed
	if is_crouching:
		speed = crouch_speed
	if is_healing():
		speed = walk_speed * 0.5
	if _landing_left > 0.0:
		speed *= landing_slowdown
	speed *= lerpf(1.0, ads_move_multiplier, gun.aim)
	speed *= lerpf(1.0, lean_move_multiplier, absf(lean))
	# Slower backwards and sideways.
	var scaled := Vector2(input_dir.x * strafe_multiplier, input_dir.y * (backward_multiplier if input_dir.y > 0.0 else 1.0))
	var local := Vector3(scaled.x, 0.0, scaled.y) * speed
	if local.length() > speed:
		local = local.normalized() * speed
	return transform.basis * local


## Head bob, strafe lean, landing dip and sprint FOV.
func _update_camera_motion(delta: float, shake: float) -> void:
	var speed := horizontal_speed() if is_on_floor() else 0.0
	_bob_time += delta * speed * (1.9 if _sprinting else 2.2)
	var bob_amount := (sprint_bob if _sprinting else walk_bob) * minf(speed / walk_speed, 1.0) * (1.0 - 0.7 * gun.aim)
	_landing_dip = lerpf(_landing_dip, 0.0, minf(delta * 8.0, 1.0))
	var bob := Vector3(cos(_bob_time * 0.5) * bob_amount * 0.6, -absf(sin(_bob_time * 0.5)) * bob_amount - _landing_dip, 0.0)
	camera.position = camera.position.lerp(bob, minf(delta * 12.0, 1.0))

	var tilt := deg_to_rad(-_move_input.x * strafe_tilt)
	_roll = lerpf(_roll, tilt, minf(delta * 8.0, 1.0))
	camera.rotation.z = _roll - deg_to_rad(lean_angle_deg) * lean + randf_range(-1.0, 1.0) * 0.05 * shake

	# Sprint FOV eases in and out; aim zoom follows the gun's aim amount (already smoothed).
	var sprint_target := sprint_fov_boost if _sprinting and speed > walk_speed else 0.0
	_sprint_fov = lerpf(_sprint_fov, sprint_target, minf(delta * 6.0, 1.0))
	camera.fov = lerpf(base_fov + _sprint_fov, gun.ads_fov, gun.aim)


## Which way the player wants to lean right now (-1, 0, 1).
func lean_input() -> int:
	if controls_locked() or _sprinting:
		return 0
	if GameSettings.lean_toggle:
		return _lean_toggled
	return int(Input.is_action_pressed("lean_right")) - int(Input.is_action_pressed("lean_left"))


func is_leaning() -> bool:
	return absf(lean) > 0.1


func _update_lean(delta: float) -> void:
	lean = move_toward(lean, float(lean_input()), delta * lean_speed * 0.5)
	# Don't push the camera into a wall: lean only as far as there's room.
	var reach := lean_distance
	if absf(lean) > 0.01:
		var from := global_transform * Vector3(0, head.position.y, 0)
		var side := global_basis.x * signf(lean)
		var query := PhysicsRayQueryParameters3D.create(from, from + side * (lean_distance + 0.2), 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			reach = maxf(from.distance_to(hit.position) - 0.2, 0.0)
	head.position.x = lerpf(head.position.x, lean * reach, minf(delta * 20.0, 1.0))


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_delay_left = stamina_regen_delay
	if stamina <= 0.0:
		is_exhausted = true


func _update_stamina(delta: float) -> void:
	if _sprinting and horizontal_speed() > walk_speed:
		_use_stamina(sprint_drain * delta)
		return
	_stamina_delay_left -= delta
	if _stamina_delay_left <= 0.0:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
	if is_exhausted and stamina >= exhausted_recover_at:
		is_exhausted = false


func _update_footsteps(delta: float) -> void:
	var speed := horizontal_speed()
	if not is_on_floor() or speed < 0.5:
		_stride_left = minf(_stride_left, 0.3)
		return
	_stride_left -= speed * delta
	if _stride_left > 0.0:
		return
	if is_crouching:
		_stride_left = crouch_stride
		_play_step(-16.0)
		_make_noise(crouch_noise)
	elif _sprinting:
		_stride_left = sprint_stride
		_play_step(-4.0)
		_make_noise(sprint_noise)
	else:
		_stride_left = walk_stride
		_play_step(-9.0)
		_make_noise(walk_noise)


func _play_step(volume_db: float) -> void:
	Effects.sound(get_tree().current_scene, STEP_SOUNDS.pick_random(), volume_db, 0.1)


func _make_noise(radius: float) -> void:
	if radius <= 0.0:
		return
	noise_made.emit(global_position, radius)
	get_tree().call_group("enemies", "hear_noise", global_position, radius)


func _ceiling_blocked() -> bool:
	var from := global_position + Vector3(0, 0.2, 0)
	var to := global_position + Vector3(0, stand_height + 0.05, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_damaged(amount: int, source_position: Vector3) -> void:
	add_shake(0.55)
	# Flinch: getting shot throws your aim off and loosens your next shots.
	var flinch := flinch_deg * clampf(amount / 25.0, 0.4, 2.0)
	add_kick(flinch * randf_range(0.6, 1.0), flinch * randf_range(-0.7, 0.7))
	gun.add_flinch(amount)
	Effects.sound(get_tree().current_scene, HURT_SOUND, 0.0, 0.1)
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		velocity += push.normalized() * 2.5


## Hit by an enemy's melee bash: normal damage and flinch, plus a hard shove and a moment you can't aim.
func take_bash(amount: int, from: Vector3, shove: float, aim_block: float) -> void:
	health.take_damage(amount, from)
	var push := global_position - from
	push.y = 0.0
	if push.length() > 0.01:
		velocity += push.normalized() * shove
	add_kick(3.0, randf_range(-2.0, 2.0))
	gun.block_aim(aim_block)


func _on_died() -> void:
	is_dead = true
	heal_time_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "rotation:z", 1.2, 0.6)
