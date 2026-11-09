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
## Where we last stood on the floor (0.30.4): fall damage is measured from here, not from `_fall_speed`. Jolt
## sometimes flings a body that's wedged between two solids at a huge speed for a frame; that isn't a fall.
var _last_floor_y := 0.0
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
const HANG_OUT := 0.16
var _climbed := 0.0
## Climbing speed now (eased toward the keys, m/s up) and how far we've climbed on this ladder (the bob's rhythm).
var _climb_vel := 0.0
var _climb_phase := 0.0
## A move onto or off a ladder (0.32.1): the path (start, corner, end), time into it (0..1), seconds, whether it
## ends on the ladder (getting on at the top), and the yaw we started at. Empty = none.
var _ladder_path := PackedVector3Array()
var _ladder_path_t := 0.0
var _ladder_path_time := 0.5
var _ladder_path_onto := false
var _ladder_yaw_from := 0.0
var stamina := 100.0
## True after running out of stamina, until it recovers to `exhausted_recover_at`.
var is_exhausted := false
var _stamina_delay_left := 0.0
var _stride_left := 0.0
## The lying body's collision (set_lying), made the first time it's needed.
var _lying_shape: CollisionShape3D
## Front of the head to the boots, lying prone (Hitbox.PRONE_PARTS, BodyPose.LIE_HIPS_Z), meters along -Z.
const LYING_FRONT := -0.87
const LYING_BACK := 0.95
const LYING_RADIUS := 0.18
## The middle of the lying capsule: its underside 0.36 m off the ground, so hills don't catch it (on the real map that
## made 4% of open spots no-lie facing uphill; at this height almost none), its top at the head's.
const LYING_HEIGHT := 0.54
## Leaning stops this far short of a wall at the side (the middle of the head to the wall: half the head hitbox).
const LEAN_HEAD_ROOM := 0.32


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
	if not lying_room():
		return   # (0.25.26: no room ahead and behind for the lying body; stays as it was)
	is_prone = true
	is_crouching = true
	_sprinting = false
	_set_capsule()
	WorldSounds.own(self, WorldSounds.PRONE, -8.0)


func _set_capsule() -> void:
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = prone_height if is_prone else (crouch_height if is_crouching else stand_height)
	body_shape.position.y = capsule.height * 0.5
	set_lying(is_prone)


## Prone (0.25.26, owner picked it): the lying body collides too, a capsule from the head to the boots
## (LYING_FRONT..LYING_BACK, where Hitbox.PRONE_PARTS are), held off the ground so crawling over bumps and
## up gentle slopes isn't caught on them. Before, only the upright capsule at the player's middle collided, and the
## head and legs others see lay inside or through walls.
func set_lying(on: bool) -> void:
	if _lying_shape == null:
		var capsule := CapsuleShape3D.new()
		capsule.radius = LYING_RADIUS
		capsule.height = LYING_BACK - LYING_FRONT
		_lying_shape = CollisionShape3D.new()
		_lying_shape.name = "LyingShape"
		_lying_shape.shape = capsule
		# The capsule's length (its Y) along the body (Z).
		_lying_shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(0, LYING_HEIGHT, (LYING_FRONT + LYING_BACK) * 0.5))
		add_child(_lying_shape)
	_lying_shape.disabled = not on


## Whether the lying body fits here, facing this way.
func lying_room() -> bool:
	set_lying(false)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _lying_shape.shape
	query.transform = global_transform * _lying_shape.transform
	query.collision_mask = collision_mask & ~4   # (other bodies don't count: they get out of the way)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func teleport_to(pos: Vector3) -> void:
	_vault_path.clear()
	_ladder_path.clear()
	_climbing = null
	_fall_speed = 0.0
	_last_floor_y = pos.y
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


## Next to a ladder you could climb (for the new-player tips).
func near_ladder() -> bool:
	return not _ladders.is_empty()


func ladder_exited(ladder: Ladder) -> void:
	_ladders.erase(ladder)
	if ladder == _climbing and _ladder_path.is_empty():
		_climbing = null


## The ladder we're on (or stepping on or off), else null (for the climbing hands).
func climbing_ladder() -> Ladder:
	return _climbing


## A ladder interact would grab now (null = none): for the USE button and the CLIMB prompt.
func ladder_to_grab() -> Ladder:
	if _climbing != null or _ladders.is_empty() or downed or controls_locked() or _ladder_grab_wait > 0.0 \
		or is_vaulting() or is_prone:
		return null
	var it := interactor
	if it != null and (it.target != null or it.door != null or it.swing_door != null or it.map_switch != null
			or it.revive_target != null):
		return null
	return _ladders.back() as Ladder


## Where a climber hangs on `ladder` at height `y`: in the middle, an arm's length off the rungs (HANG_OUT past
## touching them, so both hands show while climbing).
func _hang_at(ladder: Ladder, y: float) -> Vector3:
	var radius := (body_shape.shape as CapsuleShape3D).radius
	var foot := ladder.global_position
	var at := foot - ladder.into() * (radius + HANG_OUT)
	return Vector3(at.x, y, at.z)


## Facing straight at `ladder` (our yaw).
func _ladder_yaw(ladder: Ladder) -> float:
	var into := ladder.into()
	return atan2(-into.x, -into.z)


## Ladders (0.13.5; reworked 0.32.1, owner: "ladder mechanics are ass", the top was weird, it grabbed you when you
## didn't want it, a bit slow, felt dead). Getting on: walk straight into it, or press interact near it; at the top,
## interact or walk off the edge over it, and you're swung round onto it in one smooth move. W climbs the way you look
## (0.20.13: looking down goes down, otherwise up; S the other way), so a touch stick works the same as the keys;
## sprint slides down. At the top you climb up and over onto the floor in one move (like a vault); at the bottom you
## step off. Space lets go (pushed back off it, or sideways with A/D). True while on one.
func _update_climb(delta: float) -> bool:
	_ladder_grab_wait -= delta
	if not _ladder_path.is_empty():
		return _update_ladder_path(delta)
	var input_dir := Vector2.ZERO
	if takes_input():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _climbing == null:
		if not _try_grab(input_dir):
			return false
		if not _ladder_path.is_empty():
			return true
	var ladder := _climbing
	if downed or controls_locked():
		_let_go(ladder, false)
		return false
	if Input.is_action_just_pressed("jump") and takes_input():
		_let_go(ladder, true, input_dir.x)
		return false
	var up := -input_dir.y
	if head.rotation.x < LADDER_LOOK_DOWN:
		up = -up
	var feet := global_position.y
	var target := up * climb_speed
	var sliding := up < 0.0 and takes_input() and Input.is_action_pressed("sprint")
	if sliding:
		target = -slide_speed
	# Eased in and out (it used to start and stop dead), quicker to stop than to get going.
	var rate := 14.0 if absf(target) > absf(_climb_vel) else 20.0
	_climb_vel = move_toward(_climb_vel, target, delta * climb_speed * rate)
	# Held on the ladder's line (in the middle, just off the rungs), so it never drifts or shoves.
	var hang := _hang_at(ladder, feet)
	var pull := Vector3(hang.x - global_position.x, 0.0, hang.z - global_position.z) * 10.0
	velocity = Vector3(pull.x, _climb_vel, pull.z)
	# Up near the top: climb up and over onto the floor in one move.
	if _climb_vel > 0.0 and up > 0.0 and feet > ladder.top_y() - 1.05 and _step_off_top(ladder):
		return true
	if feet > ladder.top_y() + 0.1 and velocity.y > 0.0:
		velocity.y = 0.0   # (no floor to step onto up there: stay at the top)
	move_and_slide()
	_fall_speed = 0.0
	_last_floor_y = global_position.y
	_was_on_floor = is_on_floor()
	var moved := absf(global_position.y - feet)
	_climbed += moved
	_climb_phase += moved
	if _climbed > Ladder.RUNG_GAP * 2.0:
		_climbed = 0.0
		_play_step(-4.0 if sliding else -2.0)
		WorldSounds.own(self, WorldSounds.RUNG, -11.0 if sliding else -8.0)
		_make_noise(walk_noise * (0.8 if sliding else 0.5))
	# Off at the bottom: feet on the ground while going down (or not climbing).
	if is_on_floor() and _climb_vel <= 0.05 and up < 0.0 and global_position.y < ladder.top_y() - 0.5:
		_climbing = null
		_ladder_grab_wait = 0.3
		_climb_vel = 0.0
		velocity = Vector3.ZERO
		_landing_dip = 0.03 if not sliding else 0.08
	return true


## Gets on a ladder in reach if we mean to: walking straight into it, pressing interact, or at the top, walking off the
## edge over it. Not just for passing by or falling past one (owner: it grabbed you when you didn't want it).
func _try_grab(input_dir: Vector2) -> bool:
	var ladder := ladder_to_grab()
	if ladder == null:
		return false
	var into := ladder.into()
	var facing := -global_basis.z
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	var pressed := Input.is_action_just_pressed("interact") and takes_input()
	var feet := global_position.y
	var past := (global_position - ladder.global_position).dot(into)
	if is_on_floor() and feet > ladder.top_y() - 0.3:
		# At the top. Walking off the edge over the ladder (any way you face) catches you too, so you never fall.
		var wish := global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		var off_edge := Vector3(wish.x, 0.0, wish.z).dot(-into) > 0.5 and past < 0.25
		if not pressed and not off_edge:
			return false
		_climbing = ladder
		_start_ladder_path(ladder, PackedVector3Array([global_position,
			_hang_at(ladder, ladder.top_y() + 0.02), _hang_at(ladder, ladder.top_y() - 1.2)]), 0.5, true)
		return true
	var walking_in := input_dir.y < -0.3 and facing.dot(into) > 0.75 and past > -0.8 \
		and head.rotation.x > LADDER_LOOK_DOWN
	if not pressed and not walking_in:
		return false
	if feet > ladder.top_y() - 0.3:
		return false
	_climbing = ladder
	_climb_vel = 0.0
	_climb_phase = 0.0
	_sprinting = false
	if is_crouching:
		set_crouching(false)
	if not is_on_floor():
		velocity = Vector3.ZERO
	return true


## Climbing past the top: up and over onto the floor there, if there's room for us (else false: keep climbing).
func _step_off_top(ladder: Ladder) -> bool:
	var top := ladder.top_y()
	for forward: float in [0.5, 0.15]:
		var end := _hang_at(ladder, top + 0.05) + ladder.into() * ((body_shape.shape as CapsuleShape3D).radius + HANG_OUT + forward)
		if _room_at(end):
			_start_ladder_path(ladder, PackedVector3Array([global_position, _hang_at(ladder, top + 0.15), end]),
				clampf((top + 0.15 - global_position.y) * 0.35, 0.25, 0.45), false)
			return true
	return false


func _room_at(feet: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape.shape
	query.transform = Transform3D(Basis.IDENTITY, feet + body_shape.position)
	query.collision_mask = collision_mask & ~4
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## A smooth move onto or off a ladder (0.32.1): along `path` (start, corner, end, like a vault) in `time` seconds,
## turning to face the ladder if we're getting on (`onto`).
func _start_ladder_path(ladder: Ladder, path: PackedVector3Array, time: float, onto: bool) -> void:
	_ladder_path = path
	_ladder_path_t = 0.0
	_ladder_path_time = time
	_ladder_path_onto = onto
	_ladder_yaw_from = rotation.y
	_climb_vel = 0.0
	_climb_phase = 0.0
	_sprinting = false
	if is_crouching:
		set_crouching(false)
	velocity = Vector3.ZERO
	_play_step(-2.0)
	WorldSounds.own(self, WorldSounds.RUNG, -8.0)


func _update_ladder_path(delta: float) -> bool:
	var ladder := _climbing
	if ladder == null or not is_instance_valid(ladder) or out_of_fight():
		_ladder_path.clear()
		_climbing = null
		return false
	_ladder_path_t = minf(_ladder_path_t + delta / _ladder_path_time, 1.0)
	var before := global_position
	global_position = Vault.position_at(_ladder_path, _ladder_path_t)
	_climb_phase += absf(global_position.y - before.y)
	if _ladder_path_onto:
		rotation.y = lerp_angle(_ladder_yaw_from, _ladder_yaw(ladder), smoothstep(0.0, 1.0, minf(_ladder_path_t * 1.6, 1.0)))
	_fall_speed = 0.0
	_last_floor_y = global_position.y
	velocity = Vector3.ZERO
	if _ladder_path_t < 1.0:
		return true
	_ladder_path.clear()
	if not _ladder_path_onto:
		_climbing = null
		_ladder_grab_wait = 0.4
		_landing_dip = 0.04
		_play_step(0.0)
		return false
	return true


## Lets go of `ladder`: with Space (`jumped`), pushed back off it, or off to the side with A/D (`side`).
func _let_go(ladder: Ladder, jumped: bool, side := 0.0) -> void:
	_climbing = null
	_climb_vel = 0.0
	_ladder_grab_wait = 0.6
	if not jumped:
		velocity = Vector3.ZERO
		return
	var right := ladder.into().cross(Vector3.UP).normalized()
	velocity = -ladder.into() * (1.2 if absf(side) > 0.3 else 2.5) + right * signf(side) * (2.5 if absf(side) > 0.3 else 0.0) \
		+ Vector3.UP * 1.5


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
	if _climbing != null:
		# On a ladder (0.32.1): the body rocks side to side and dips with each pull, two rungs a pull.
		var pull := _climb_phase / (Ladder.RUNG_GAP * 2.0) * PI
		bob = Vector3(sin(pull) * 0.018, -absf(sin(pull)) * 0.03 - _landing_dip, 0.0)
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
	if GameSettings.lean_toggle or TouchInput.active:   # (touch lean buttons tap on / off, 0.29.9)
		return _lean_toggled
	if camera_away:
		return 0
	return int(Input.is_action_pressed("lean_right")) - int(Input.is_action_pressed("lean_left"))


func _update_lean(delta: float) -> void:
	lean = move_toward(lean, float(lean_input()), delta * lean_speed * 0.5)
	# Don't push the camera into a wall: lean only as far as there's room. 0.25.19: room for the whole head (half the
	# head hitbox, 0.31 m, was 0.2), since other players see the head where the camera is and the lean goes online as
	# far as it really went (RemotePlayer.capture): a head poking out the far side of a wall gave you away.
	var reach := lean_distance
	if absf(lean) > 0.01:
		var from := global_transform * Vector3(0, head.position.y, head.position.z)
		var side := global_basis.x * signf(lean)
		var query := PhysicsRayQueryParameters3D.create(from, from + side * (lean_distance + LEAN_HEAD_ROOM), 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			reach = maxf(from.distance_to(hit.position) - LEAN_HEAD_ROOM, 0.0)
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
	if is_prone:   # (prone sets is_crouching too: check it first)
		_stride_left = prone_stride
		_play_step(-18.0)
		_make_noise(prone_noise)
	elif is_crouching:
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
