class_name Player
extends "res://scripts/player_movement.gd"
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump, C to crouch, Q/E to lean.
## Aiming down sights (RMB, handled by the Gun) slows you down, zooms the camera and stops sprinting.
## Split into parts (0.14.6): see player_base.gd. This part is input, the per-frame update, items and the hotbar,
## damage and the online side.

## Proxy only: a scav rifle-butted this player (the server passes it on to their game).
signal bashed(amount: int, from: Vector3, shove: float, aim_block: float)
## We killed something (0.18.9, the kill feed): what it was, by its scene's name ("scav", "raider", "boss"...).
signal killed(what: String)

const HURT_SOUND := preload("res://audio/hurt.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")
const THROW_SOUND := preload("res://audio/throw.wav")
## Grenades (0.14.5): how hard you throw (m/s along your view, plus a little up), and the wait between throws.
const THROW_SPEED := 15.0
const THROW_LIFT := 3.0
const THROW_COOLDOWN := 1.0
## The gun can't fire for this long after a throw, and you can't throw this soon after a shot (owner 0.14.14).
const THROW_BUSY := 0.6
const THROW_AFTER_SHOT := 0.3
## Grenade in hand (0.14.17, owner): key 4 pulls it out (this long), click throws it (after a short wind-up),
## key 4 again puts it away.
const NADE_PULL_TIME := 0.45
const NADE_WINDUP_TIME := 0.18
## A heal or drink can be cancelled (right-click, item back) once it's this far in: no heal-cancel spam (owner).
const HEAL_CANCEL_AFTER := 1.0
## Blood-red sparks where the player's gun or knife hits someone.
const HIT_COLOR := Color(0.95, 0.25, 0.2)
## Key 3 / the meds slot (owner, 0.9.3): a tap uses the med, holding this long switches to the next one,
## and keeping it held switches again every MEDS_REPEAT_TIME.
const MEDS_HOLD_TIME := 0.35
const MEDS_REPEAT_TIME := 0.5
## Jumping (0.18.3, owner: "fix jumping, it just feels bad"): a press this long before landing still jumps, and you
## can still jump this long after walking off an edge; ledges up to STEP_HEIGHT are stepped onto; only a landing faster
## than SLOW_LANDING_SPEED (a drop of about 1.3 m) slows you down after.
const JUMP_BUFFER := 0.15
const COYOTE_TIME := 0.12
const STEP_HEIGHT := 0.35
const STEP_HOLD := 0.15
const SLOW_LANDING_SPEED := 5.0
## On the game server, each player in a raid is a proxy: a body the AI can see, hear, shoot and bash, moved by the
## states their game sends (apply_net_state). No input, camera, profile or physics of its own. Set before adding.
var proxy := false
## Enemies killed this raid (gun or knife).
var kills := 0
## Downed: a teammate is holding F on us (shown as a bar; the server tells us when it starts and stops).
var being_revived := false
var revive_time_left := 0.0
## Asked when health reaches 0: can a teammate still come and revive us? Online, a teammate who is up and in the
## raid; offline, never (solo dies). Replaceable (the test stands in for a teammate).
var squad_check := Callable()
var heal_duration := 0.0
var _throw_cooldown_left := 0.0
## The hand that holds grenades, meds and drinks (placeholder animations, 0.14.17).
var hand: HandItem
## 0 = no grenade out, 1 = pulling it out, 2 = holding it, 3 = winding up to throw.
var _nade_phase := 0
var _nade_time := 0.0
var _nade_id := ""
var _heal_grid: GridInventory
## The item being used was free kit (0.16.6) or found in raid (0.16.13): a cancelled use gives back the same kind.
var _heal_marks := 0
## How long key 3 (or the meds slot) has been held, -1 = not held; when it switches next; whether it switched.
var _meds_held := -1.0
var _meds_next_switch := 0.0
var _meds_switched := false
var _ground_check_left := 0.0
## How many ground checks in a row found the player inside something solid (0.19.4).
var _stuck_checks := 0
var _jump_cooldown_left := 0.0
## Jump pressed a moment before landing still jumps; walking off an edge you can still jump a moment after (0.18.3).
var _jump_buffer_left := 0.0
var _coyote_left := 0.0
## Just stepped up onto a ledge: carried on level for a moment, onto it.
var _step_hold_left := 0.0

# Mouse debug stats, shown by the HUD's F3 overlay.
var debug_recent_dx: Array[int] = []
var debug_max_delta := 0.0
var debug_spikes_dropped := 0
# Spike filter state: size and time of the last mouse move that was used, and whether the one before was dropped.
var _last_mouse_delta := 0.0
var _last_mouse_msec := 0
var _dropped_last_mouse := false


func _ready() -> void:
	add_to_group("player")
	# The capsule comes from player.tscn and is shared by every instance; give each player its own,
	# so one player crouching doesn't shrink the others.
	body_shape.shape = body_shape.shape.duplicate()
	if not proxy:
		Ambience.start(self)   # (0.20.5: wind, woods, water, the far-off war)
	if proxy:
		camera.current = false
		# Keep the body in the physics world with its processing off (0.16.9): by default a disabled body is taken out
		# of physics, so the server's scav shots went straight through every player online.
		disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		for node: Node in [self, gun, knife, interactor]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		return
	_spawn_position = global_position
	Effects.warm_up(camera)
	hand = HandItem.new()
	camera.add_child(hand)
	inventory.equipment_changed.connect(_on_equipment_changed)
	# Bring in the loadout from the hideout (or the starter kit on a new profile).
	Profile.load_profile()
	Profile.apply_inventory(inventory, Profile.loadout)
	Profile.raid_begun()
	health.damaged.connect(_on_damaged)
	health.armor_hit.connect(_on_armor_hit)
	health.died.connect(_on_died)
	health.downed.connect(_on_downed)
	health.revived.connect(_on_revived)
	squad_check = teammate_can_revive
	health.can_go_down = func() -> bool: return squad_check.call()


## A teammate started (or stopped) reviving us.
func set_being_revived(on: bool) -> void:
	being_revived = on and downed
	revive_time_left = Network.REVIVE_TIME if being_revived else 0.0


## Our teammate finished reviving us: back up with a little health.
func revive() -> void:
	health.revive(revive_health)


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


## Key 3: use the med it shows (the one picked by holding 3, or the best fit on Auto).
func use_meds() -> void:
	var found := inventory.find_meds(health.max_health - health.current)
	if not found.is_empty():
		use_item(found[0], found[1])


## Key 3 (or a touch on the meds slot) went down: a quick release uses the med, holding switches it.
func meds_press() -> void:
	if out_of_fight():
		return
	_meds_held = 0.0
	_meds_next_switch = MEDS_HOLD_TIME
	_meds_switched = false


func meds_release() -> void:
	if _meds_held < 0.0:
		return
	_meds_held = -1.0
	if not _meds_switched:
		use_meds()


## A hotbar slot (0 = key 3): 3 uses the picked med (Auto = best fit, like H), 4 uses what's bound there, the knife slot swings it.
func use_hotbar(index: int) -> void:
	if downed:
		return
	if index == Inventory.MEDS_KEY:
		use_meds()
		return
	if index == Inventory.KNIFE_KEY:
		knife.swing()
		return
	var id := inventory.hotbar[index]
	if id == "":
		return
	var found := inventory.find(id)
	if not found.is_empty():
		use_item(found[0], found[1])


## Feedback for a hit the player's gun or knife landed (after the damage): damage number, sparks, kill count.
## `critical` = headshot or backstab (bigger damage number). The caller plays its own sound.
## `weapon`: the item id it was done with ("knife" for the knife), for quests.
func on_hit_landed(target_health: Health, pos: Vector3, normal: Vector3, amount: int, critical: bool, weapon := "") -> void:
	var world := get_tree().current_scene
	if GameSettings.damage_numbers:
		Effects.damage_number(world, pos, amount, critical)
	Effects.impact(world, pos, normal, HIT_COLOR, 12)
	if target_health.is_dead:
		kills += 1
		var victim := target_health.get_parent()
		if victim != null and victim.scene_file_path != "":
			var what := victim.scene_file_path.get_file().get_basename()
			Quests.record_kill(what, weapon)
			killed.emit(what)


func _hotbar_key(event: InputEvent) -> int:
	# Keys 3 and 4 (the knife is on V, not a number key).
	for i in Inventory.HOTBAR_SIZE:
		if i != Inventory.KNIFE_KEY and event.is_action_pressed("hotbar_%d" % (i + 3)):
			return i
	return -1


func _on_equipment_changed() -> void:
	health.damage_multiplier = 1.0 - inventory.armor_reduction()
	health.head_multiplier = 1.0 - inventory.helmet_reduction()


## Hits wear the armor (or on the head, the helmet) down (0.14.0), and worn gear stops less from the next one.
func _on_armor_hit(amount: int, head: bool) -> void:
	if inventory.wear_armor(amount, head):
		_on_equipment_changed()


## Use one item from a stack: a heal or a drink takes a few seconds (you can't shoot meanwhile); a grenade is thrown.
func use_item(grid: GridInventory, stack: ItemStack) -> void:
	if ItemDB.kind(stack.id) == "throwable":
		toggle_grenade(stack.id)
		return
	# (right-click cancels a heal or drink: _unhandled_input, owner 0.14.18)
	if is_healing():
		return
	if _nade_phase != 0:
		return
	match ItemDB.kind(stack.id):
		"drink":
			if not hands_free():
				return
		"heal":
			if not hands_free() or health.current >= health.max_health:
				return
		_:
			return
	# Nothing taken = the stack is already gone (e.g. used mid-drag); don't heal for free.
	# (The stack you used, so a cancelled use gives back the same kind: free kit or not.)
	if stack in grid.stacks and stack.count > 0:
		stack.count -= 1
		if stack.count <= 0:
			grid.stacks.erase(stack)
		grid.changed.emit()
	elif grid.take(stack.id, 1) == 0:
		return
	_heal_marks = stack.marks()
	_heal_item = stack.id
	_heal_grid = grid
	if hand != null:
		hand.show_item(stack.id)
	heal_duration = ItemDB.item(stack.id)["use_time"]
	heal_time_left = heal_duration
	Effects.sound(get_tree().current_scene, HEAL_SOUND, -4.0)
	if WorldSounds.ITEMS.has(stack.id):
		WorldSounds.own(self, WorldSounds.ITEMS[stack.id], -8.0)


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked():
		return
	# Capturing the mouse (click to play) is handled by the HUD's pause menu.
	var hotbar_index := -1 if downed else _hotbar_key(event)
	if downed and not (event is InputEventMouseMotion or event.is_action_pressed("ui_cancel")):
		return  # Downed: you can only look around (and crawl).
	if event.is_action_pressed("aim") and is_healing():
		cancel_heal()   # right-click (owner, 0.14.18; a touch button for phones comes with the touch controls)
	elif event.is_action_pressed("heal"):
		try_heal()
	elif event.is_action_pressed("weapon_1"):
		put_away_grenade()
		gun.select_slot("primary")
	elif event.is_action_pressed("weapon_2"):
		put_away_grenade()
		gun.select_slot("secondary")
	elif hotbar_index == Inventory.MEDS_KEY:
		meds_press()
	elif event.is_action_released("hotbar_3"):
		meds_release()
	elif hotbar_index >= 0:
		use_hotbar(hotbar_index)
	elif event.is_action_pressed("crouch"):
		set_crouching(is_prone or not is_crouching)
	elif event.is_action_pressed("prone"):
		set_prone(not is_prone)
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
		if is_mouse_spike(delta_len, Time.get_ticks_msec()):
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


## Chrome sometimes reports one huge bogus jump out of nowhere. A real fast turn builds up over a few moves
## and keeps going, so only a lone jump far bigger than the move before it is dropped, never two in a row.
## (Before 0.17.7 every move over max_mouse_delta was dropped, which ate fast turns on high-DPI mice.)
func is_mouse_spike(delta_len: float, now_msec: int) -> bool:
	var before := _last_mouse_delta if now_msec - _last_mouse_msec < 100 else 0.0
	if delta_len > maxf(max_mouse_delta, before * 4.0) and not _dropped_last_mouse:
		_dropped_last_mouse = true
		return true
	_dropped_last_mouse = false
	_last_mouse_delta = delta_len
	_last_mouse_msec = now_msec
	return false


func _exit_tree() -> void:
	Hearing.set_indoors(false)   # (the indoor echo is off outside a raid)


func _process(delta: float) -> void:
	Hearing.listen(self, delta)
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
		if is_prone or (is_vaulting() and _vault_duck):
			eye = prone_eye_height if is_prone else crouch_eye_height
		if downed:
			eye = downed_eye_height
		head.position.y = lerpf(head.position.y, eye, minf(delta * 10.0, 1.0))
	_update_lean(delta)
	if _meds_held >= 0.0:
		if out_of_fight():
			_meds_held = -1.0
		else:
			_meds_held += delta
			if _meds_held >= _meds_next_switch:
				inventory.cycle_meds()
				_meds_switched = true
				_meds_next_switch += MEDS_REPEAT_TIME
	if downed:
		health.bleed(delta)
		revive_time_left -= delta
		# (never told it stopped, e.g. they lost connection: give up on it a moment after it should have finished)
		if being_revived and revive_time_left < -1.0:
			set_being_revived(false)
		# Nobody left who could revive us (both down, they died, extracted or left): that's it.
		if downed and not squad_check.call():
			health.kill()
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0:
			heal_time_left = 0.0
			if ItemDB.kind(_heal_item) == "drink":
				stamina = max_stamina
				is_exhausted = false
				drink_boost_left = float(ItemDB.item(_heal_item)["boost_time"])
			else:
				health.heal(ItemDB.item(_heal_item)["heal"])
	_update_grenade(delta)
	# Heal done or stopped (finished, cancelled, downed...): the hand goes back down.
	if hand != null and hand.pose == HandItem.Pose.HELD and _nade_phase == 0 and not is_healing():
		hand.put_away()
	drink_boost_left = maxf(drink_boost_left - delta, 0.0)
	_throw_cooldown_left -= delta


func _physics_process(delta: float) -> void:
	if is_vaulting():
		_update_vault(delta)
		return
	if _update_climb(delta):
		return
	_step_hold_left -= delta
	var on_floor := is_on_floor() or _step_hold_left > 0.0
	if not on_floor:
		velocity += get_gravity() * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_jump_cooldown_left -= delta
	_landing_left -= delta
	_jump_buffer_left -= delta
	_coyote_left = COYOTE_TIME if on_floor else _coyote_left - delta

	var input_dir := Vector2.ZERO
	if not controls_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			_jump_buffer_left = JUMP_BUFFER
		var can_jump := on_floor or (_coyote_left > 0.0 and velocity.y <= 0.0)
		if _jump_buffer_left > 0.0 and can_jump and not downed and not is_vaulting():
			_jump_buffer_left = 0.0
			if on_floor and input_dir.y < -0.3 and not is_prone and not is_healing() and stamina >= jump_cost and try_vault():
				_use_stamina(jump_cost)
			elif is_crouching:
				set_crouching(false)
			elif _jump_cooldown_left <= 0.0 and stamina >= jump_cost:
				velocity.y = jump_velocity
				_jump_cooldown_left = jump_cooldown
				WorldSounds.own(self, WorldSounds.JUMP, -10.0)
				_coyote_left = 0.0
				_use_stamina(jump_cost)
	_move_input = input_dir

	# Sprint: only forward-ish, on the ground, not while healing, needs stamina. Sprinting stands you up.
	var wants_sprint := (not out_of_fight() and on_floor and not is_healing() and not is_exhausted
		and Input.is_action_pressed("sprint") and input_dir.y < -0.5 and not gun.wants_aim() and not is_leaning()
		and not BoxMap.is_wading(self))
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
	_break_glass()
	_step_up(horizontal, delta)

	# Landing (0.18.3: an ordinary jump doesn't slow you down after; a drop from higher still does).
	if is_on_floor() and not _was_on_floor and _fall_speed > 2.0:
		if _fall_speed > SLOW_LANDING_SPEED:
			_landing_left = landing_slowdown_time
		_landing_dip = clampf(_fall_speed * 0.02, 0.03, 0.15)
		_play_step(4.0)
		WorldSounds.own(self, WorldSounds.LAND, clampf(-16.0 + _fall_speed * 1.2, -14.0, 0.0))
		_make_noise(landing_noise)
		var dropped := _fall_speed * _fall_speed / (2.0 * get_gravity().length())
		if dropped > safe_fall_height and not out_of_fight():
			_landing_dip = 0.2
			health.take_damage(ceili((dropped - safe_fall_height) * fall_damage_per_meter), global_position, true)
	if is_on_floor():
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_update_footsteps(delta)

	if global_position.y < kill_height:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		_fall_speed = 0.0
	# Somehow under the hills (the ground is solid from below too, so you'd be stuck there): back on top.
	_ground_check_left -= delta
	if _ground_check_left <= 0.0:
		_ground_check_left = 0.5
		var lifted := BoxMap.above_ground(self, global_position)
		if lifted != global_position:
			global_position = lifted
			velocity = Vector3.ZERO
			_fall_speed = 0.0
		_free_if_stuck()


## Walking into a low ledge (a kerb, a lump of rubble, a step up onto a slab: up to STEP_HEIGHT) steps up onto it
## instead of stopping you dead (0.18.3, owner: "fix jumping, it just feels bad"). On the ground, walking into something:
## if there's floor just past it no higher than a step, and room above, you're lifted onto its height and walk on.

## Pushing into a whole window pane breaks it (0.18.8, owner: "make windows breakable"), so you can go through it.
func _break_glass() -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as CollisionObject3D
		if body != null and body.collision_layer == BoxMap.WINDOW_LAYER:
			BoxMap.break_window_at(body, hit.get_collider_shape_index(), true)


## Inside a rock, a bank or a wall for two checks running (0.19.4): put back out on the nearest free spot.
func _free_if_stuck() -> void:
	var capsule := body_shape.shape as CapsuleShape3D
	if is_vaulting() or _climbing != null or not BoxMap.stuck_inside(self, global_position, capsule.radius, capsule.height):
		_stuck_checks = 0
		return
	_stuck_checks += 1
	if _stuck_checks < 2:
		return
	_stuck_checks = 0
	var spot := BoxMap.free_spot(self, global_position, capsule.radius, capsule.height)
	if spot != global_position:
		global_position = spot
		velocity = Vector3.ZERO
		_fall_speed = 0.0


func _step_up(horizontal: Vector3, delta: float) -> void:
	if not _was_on_floor or not is_on_wall() or horizontal.length() < 0.5 or is_prone:
		return
	var radius := (body_shape.shape as CapsuleShape3D).radius
	var feet := global_position
	var probe := feet + horizontal.normalized() * (radius + 0.12)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		probe + Vector3.UP * (STEP_HEIGHT + 0.05), probe + Vector3.UP * 0.02, 1, [get_rid()]))
	# (0.19.4: from inside a bank, its skin looked like a step to stand on)
	if hit.is_empty() or hit["normal"].y < 0.7 or BoxMap.hit_from_behind(hit, Vector3.DOWN):
		return
	var rise: float = hit["position"].y - feet.y + 0.02
	if rise > STEP_HEIGHT + 0.02 or test_move(global_transform, Vector3.UP * rise):
		return
	global_position.y += rise
	velocity = Vector3(horizontal.x, 0.0, horizontal.z)
	_step_hold_left = STEP_HOLD   # (walk on over the edge at that height, as if on the floor)


## A grenade out, or just thrown: the gun can't fire until the arm is back (0.14.14, owner: no shooting while throwing).
func is_throwing() -> bool:
	return _nade_phase != 0 or _throw_cooldown_left > THROW_COOLDOWN - THROW_BUSY


## Healing, drinking or a grenade out: the gun is lowered out of the way.
func hands_busy() -> bool:
	return is_healing() or is_throwing()


## A heal or drink far enough in to cancel (HEAL_CANCEL_AFTER s: no heal-cancel spam).
func can_cancel_heal() -> bool:
	return is_healing() and heal_duration - heal_time_left >= HEAL_CANCEL_AFTER


## Right-click while healing or drinking: stops it, no effect, and the item goes back where it came from.
func cancel_heal() -> bool:
	if not can_cancel_heal():
		return false
	heal_time_left = 0.0
	var left := 1
	if _heal_grid != null:
		left = _heal_grid.add(_heal_item, 1, _heal_marks)
	for grid in inventory.grids():
		if left > 0:
			left = grid.add(_heal_item, left, _heal_marks)
	return true


## Key 4 with a grenade bound: pull one out (then click to throw), or put it away if it's already out.
func toggle_grenade(id: String) -> void:
	if _nade_phase == 1 or _nade_phase == 2:
		put_away_grenade()
		return
	if (_nade_phase != 0 or not hands_free() or _throw_cooldown_left > 0.0 or gun.since_shot() < THROW_AFTER_SHOT
			or inventory.count_of(id) == 0):
		return
	_nade_id = id
	_nade_phase = 1
	_nade_time = NADE_PULL_TIME
	WorldSounds.own(self, WorldSounds.PIN, -10.0)
	if hand != null:
		hand.show_item(id)


func put_away_grenade() -> void:
	if _nade_phase == 0:
		return
	_nade_phase = 0
	if hand != null:
		hand.put_away()


## Click with a grenade out: wind up and throw it.
func throw_held_grenade() -> void:
	if _nade_phase != 2:
		return
	_nade_phase = 3
	_nade_time = NADE_WINDUP_TIME
	if hand != null:
		hand.wind_up()


func _update_grenade(delta: float) -> void:
	if _nade_phase == 0:
		return
	if not hands_free():
		put_away_grenade()
		return
	_nade_time -= delta
	match _nade_phase:
		1:
			if _nade_time <= 0.0:
				_nade_phase = 2
		2:
			if Input.is_action_just_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not interactor.blocked:
				throw_held_grenade()
		3:
			if _nade_time <= 0.0:
				_nade_phase = 0
				var found := inventory.find(_nade_id)
				if found.is_empty():
					hand.put_away()
					return
				throw_grenade(found[0], found[1])
				hand.throw()


## Throws one grenade from `stack` where you're looking (offline it does the damage; online the server's copy does).
func throw_grenade(grid: GridInventory, stack: ItemStack) -> void:
	# (not mid-burst either: shooting and throwing at once, owner 0.14.14)
	if not hands_free() or _throw_cooldown_left > 0.0 or gun.since_shot() < THROW_AFTER_SHOT or grid.take(stack.id, 1) == 0:
		return
	_throw_cooldown_left = THROW_COOLDOWN
	var forward := -camera.global_basis.z
	var from := camera.global_position + forward * 0.5
	var vel := forward * THROW_SPEED + Vector3.UP * THROW_LIFT + Vector3(velocity.x, 0, velocity.z) * 0.5
	var online := Network.main.in_online_raid()
	Grenade.spawn(get_tree().current_scene, from, vel, not online)
	if online:
		Network.main.send_grenade(from, vel)
	Effects.sound(get_tree().current_scene, THROW_SOUND, -4.0)


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
	if proxy:
		bashed.emit(amount, from, shove, aim_block)
		return
	health.take_damage(amount, from)
	var push := global_position - from
	push.y = 0.0
	if push.length() > 0.01:
		velocity += push.normalized() * shove
	add_kick(3.0, randf_range(-2.0, 2.0))
	gun.block_aim(aim_block)


## Under 40% health (0.15.18, owner): the AI get aggressive and push you. A proxy goes by its player's game.
const LOW_HEALTH := 0.4
var _net_low := false

func is_low() -> bool:
	if proxy:
		return _net_low
	return health.current < health.max_health * LOW_HEALTH


## Proxy: moves this body to match a state from the player's game (RemotePlayer.capture), and makes the footstep
## noise their movement would (scavs on the server hear it).
func apply_net_state(state: Array) -> void:
	var flags: int = state[4]
	var moved := Vector2(state[0].x - global_position.x, state[0].z - global_position.z).length()
	global_position = state[0]
	rotation.y = state[1]
	head.rotation.x = state[2]
	lean = state[3]
	is_crouching = flags & Hitbox.FLAG_CROUCH != 0
	is_prone = flags & Hitbox.FLAG_PRONE != 0
	_sprinting = flags & Hitbox.FLAG_SPRINT != 0
	is_dead = flags & Hitbox.FLAG_DEAD != 0
	extracted = flags & Hitbox.FLAG_EXTRACTED != 0
	downed = flags & Hitbox.FLAG_DOWNED != 0
	_net_low = flags & Hitbox.FLAG_LOW != 0
	var low := is_crouching or downed
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = prone_height if is_prone else (crouch_height if low else stand_height)
	body_shape.position.y = capsule.height * 0.5
	var eye := downed_eye_height if downed else (crouch_eye_height if is_crouching else stand_eye_height)
	if is_prone:
		eye = prone_eye_height
	head.position = Vector3(lean * lean_distance, eye, 0)
	velocity = Vector3(moved * Network.SEND_RATE, 0, 0)
	if is_crouching or out_of_fight():
		return
	_stride_left -= moved
	if _stride_left <= 0.0 and moved > 0.01:
		_stride_left = sprint_stride if _sprinting else walk_stride
		_make_noise(sprint_noise if _sprinting else walk_noise)


## 0 HP with a teammate up: down on the ground (crawl only), the gun put away, the downed bar draining.
func _on_downed() -> void:
	downed = true
	heal_time_left = 0.0
	being_revived = false
	_sprinting = false
	_lean_toggled = 0
	# Low like crouching (the capsule), even under a low ceiling; standing back up waits for room (set_crouching).
	is_prone = false
	is_crouching = true
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = crouch_height
	body_shape.position.y = capsule.height * 0.5
	gun.visible = false


func _on_revived() -> void:
	downed = false
	being_revived = false
	revive_time_left = 0.0
	gun.visible = true


func _on_died() -> void:
	is_dead = true
	downed = false
	being_revived = false
	heal_time_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "rotation:z", 1.2, 0.6)
