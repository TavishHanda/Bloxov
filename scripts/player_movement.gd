extends "res://scripts/player_base.gd"
## How the player moves: crouch and prone, ladders, vaulting, lean, stamina, footsteps and noise, camera motion
## and recoil.

## Emitted for every sound the player makes that enemies can hear (footsteps, landing).
signal noise_made(pos: Vector3, radius: float)
## Energy drink (0.14.5): seconds left of its boost (stamina comes back twice as fast, sprinting uses half).
var drink_boost_left := 0.0

var _spawn_position: Vector3
var _trauma := 0.0
## Recoil that went into the view (x = pitch, y = yaw, radians) and hasn't been pulled down against yet.
## It returns after a burst, so if you compensated with the mouse the view doesn't dip below the target.
var _recoil_debt := Vector2.ZERO
var _recoil_return_wait := 0.0
var _sprint_fov := 0.0
var _lean_toggled := 0
var _landing_left := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _bob_time := 0.0
var _landing_dip := 0.0
var _move_input := Vector2.ZERO
var _roll := 0.0

var is_crouching := false
## Lying prone (is_crouching stays true too, so everything quiet/steady about crouching applies).
var is_prone := false
var _vault_t := 0.0
var _vault_duration := 0.0
var _vault_crouch_after := false
## Squeezing through a window: the eyes go down to crouch height so the camera clears the top of it.
var _vault_duck := false
var _vault_exit_speed := 0.0
## Ladders we're in reach of (newest last), the one we're on (null = none), and a moment after letting go
## before one can catch us again.
var _ladders: Array[Ladder] = []
var _ladder_grab_wait := 0.0
## Looking further down than this (radians, about 25°), W climbs down a ladder and S up (0.20.13).
const LADDER_LOOK_DOWN := -0.44
var _climbed := 0.0
var stamina := 100.0
## True after running out of stamina, until it recovers to `exhausted_recover_at`.
var is_exhausted := false
var _stamina_delay_left := 0.0
var _stride_left := 0.0


func set_crouching(crouch: bool) -> void:
	if is_prone:
		# Getting up from prone, to a crouch or all the way (if there's room).
		if _ceiling_blocked(crouch_height if crouch else stand_height):
			return
		is_prone = false
		is_crouching = not crouch
	if crouch == is_crouching:
		_set_capsule()
		return
	if not crouch and _ceiling_blocked():
		return
	is_crouching = crouch
	_set_capsule()


## Z: lie down, or get up (standing if there's room, else crouched).
func set_prone(on: bool) -> void:
	if on == is_prone or downed:
		return
	if not on:
		set_crouching(false)
		if is_prone:
			set_crouching(true)
		return
	is_prone = true
	is_crouching = true
	_sprinting = false
	_set_capsule()
	WorldSounds.own(self, WorldSounds.PRONE, -8.0)


func _set_capsule() -> void:
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = prone_height if is_prone else (crouch_height if is_crouching else stand_height)
	body_shape.position.y = capsule.height * 0.5


func teleport_to(pos: Vector3) -> void:
	_vault_path.clear()
	_climbing = null
	_fall_speed = 0.0
	global_position = pos
	_spawn_position = pos
	velocity = Vector3.ZERO


func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)


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


func ladder_entered(ladder: Ladder) -> void:
	_ladders.append(ladder)


func ladder_exited(ladder: Ladder) -> void:
	_ladders.erase(ladder)
	if ladder == _climbing:
		_climbing = null


## Ladders (0.13.5): gets on one when walking into it facing it, when walking off the top looking down, or when
## dropping past it (stepping off the top). W climbs the way you look (0.20.13: looking down goes down, otherwise
## up; S the other way), so a touch stick works the same as the keys. Space lets go, and climbing past the top
## steps you off onto the floor there. True while on one.
func _update_climb(delta: float) -> bool:
	_ladder_grab_wait -= delta
	var input_dir := Vector2.ZERO
	if not controls_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _climbing == null:
		if _ladders.is_empty() or downed or controls_locked() or _ladder_grab_wait > 0.0:
			return false
		var ladder := _ladders.back() as Ladder
		var facing := -global_basis.z
		facing = Vector3(facing.x, 0.0, facing.z).normalized()
		var forward := input_dir.y < -0.3
		var looking_down := head.rotation.x < LADDER_LOOK_DOWN
		var walking_in := forward and not looking_down and facing.dot(ladder.into()) > 0.5
		var stepping_down := forward and looking_down and is_on_floor() \
			and global_position.y > ladder.top_y() - 0.3 and facing.dot(ladder.into()) < -0.3
		var dropping := not is_on_floor() and velocity.y < -0.5 and global_position.y < ladder.top_y() - 0.2
		if not walking_in and not stepping_down and not dropping:
			return false
		_climbing = ladder
		_sprinting = false
		if is_crouching:
			set_crouching(false)
	var ladder := _climbing
	if Input.is_action_just_pressed("jump") and not controls_locked():
		_climbing = null
		_ladder_grab_wait = 0.6
		velocity = -ladder.into() * 2.5 + Vector3.UP * 1.5
		return false
	var up := -input_dir.y
	if head.rotation.x < LADDER_LOOK_DOWN:
		up = -up
	var feet := global_position.y
	# How far past the ladder's foot, toward what it leans on (climbers hang at about minus their radius).
	var past := (global_position - ladder.global_position).dot(ladder.into())
	velocity = Vector3(0.0, up * climb_speed, 0.0) + ladder.into() * 0.5
	if up < 0.0 and past > 0.05 - (body_shape.shape as CapsuleShape3D).radius:
		velocity -= ladder.into() * 2.0   # going down from the floor at the top: out over the ladder first
	elif feet > ladder.top_y() - 0.4 and up > 0.0:
		velocity += ladder.into() * 2.0   # over the top, onto the floor
		if feet > ladder.top_y():
			velocity.y = -1.0
	move_and_slide()
	_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_climbed += absf(global_position.y - feet)
	if _climbed > 0.6:
		_climbed = 0.0
		_play_step(-2.0)
		WorldSounds.own(self, WorldSounds.RUNG, -8.0)
		_make_noise(walk_noise * 0.5)
	# Off at the bottom (on the ground, not going up) or at the top (standing on the floor up there).
	past = (global_position - ladder.global_position).dot(ladder.into())
	if is_on_floor() and ((up <= 0.0 and feet < ladder.top_y() - 0.5) or (up >= 0.0 and past > 0.5)):
		_climbing = null
		_ladder_grab_wait = 0.3
		velocity = Vector3.ZERO
	return true


## Space while moving into cover: vaults over it (thin cover) or climbs onto it (ledges, wide tops) if there's
## room. False = nothing to vault. Plain movement, so online it shows up for the others like any other move.
func try_vault() -> bool:
	var move := Vault.plan(self, -global_basis.z, (body_shape.shape as CapsuleShape3D).radius, stand_height,
		crouch_height, vault_reach, mantle_max_height)
	if move.is_empty():
		return false
	if move["crouch_after"] and not is_crouching:
		set_crouching(true)
	_vault_crouch_after = move["crouch_after"]
	_vault_duck = move["duck"]
	_vault_path = move["path"]
	_vault_t = 0.0
	_vault_duration = vault_time if move["over"] else mantle_time
	_vault_exit_speed = maxf(horizontal_speed(), walk_speed) if move["over"] else 0.0
	velocity = Vector3.ZERO
	_sprinting = false
	_play_step(2.0)
	WorldSounds.own(self, WorldSounds.VAULT, -6.0)
	_make_noise(vault_noise)
	# 0.18.8: going through a window takes the glass with you.
	var path: PackedVector3Array = move["path"]
	BoxMap.break_window_along(self, path[0] + Vector3.UP * 1.0, path[path.size() - 1] + Vector3.UP * 1.0)
	return true


func _update_vault(delta: float) -> void:
	if out_of_fight():
		_vault_path.clear()
		return
	_vault_t += delta / _vault_duration
	global_position = Vault.position_at(_vault_path, _vault_t)
	if _vault_t < 1.0:
		return
	var dir := Vector3(_vault_path[2].x - _vault_path[0].x, 0.0, _vault_path[2].z - _vault_path[0].z).normalized()
	_vault_path.clear()
	velocity = dir * _vault_exit_speed
	_landing_dip = 0.05
	_play_step(0.0)
	if not _vault_crouch_after:
		set_crouching(false)


func _target_velocity(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var speed := sprint_speed if _sprinting else walk_speed
	if is_crouching:
		speed = prone_speed if is_prone else crouch_speed
	if is_healing():
		speed = walk_speed * 0.5
	if downed:
		speed = walk_speed * crawl_multiplier
	if _landing_left > 0.0:
		speed *= landing_slowdown
	speed *= lerpf(1.0, ads_move_multiplier, gun.aim)
	speed *= lerpf(1.0, lean_move_multiplier, absf(lean))
	if BoxMap.is_wading(self):
		speed *= wade_multiplier
	if BoxMap.in_bush(self):
		speed *= bush_multiplier
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
	if out_of_fight() or _sprinting:
		return 0
	if GameSettings.lean_toggle:
		return _lean_toggled
	return int(Input.is_action_pressed("lean_right")) - int(Input.is_action_pressed("lean_left"))


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
	if drink_boost_left > 0.0:
		return   # energy drink (0.14.14, owner): no stamina drain while it lasts
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
	Surfaces.step(self, volume_db)


func _make_noise(radius: float) -> void:
	if radius <= 0.0:
		return
	noise_made.emit(global_position, radius)
	RaidScope.call_all(self, &"enemies", &"hear_noise", [global_position, radius])
