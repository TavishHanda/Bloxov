class_name Scav
extends "res://scripts/scav_fight.gd"
## Scav: armed scavenger. Patrols until it spots a player, then shoots in short bursts.
## Senses: seeing you = knows where you are. Hearing you = walks over to investigate roughly where the sound was.
## Losing sight of you = goes to where it last saw you, searches for a bit, then goes back to wandering.
## Moves along navigation paths (scripts/nav_baker.gd builds the map's walkable area at raid start), so it walks
## around buildings and crates.
## Raiders (the tougher AI faction, scenes/raider.tscn) use this script too, with tougher numbers and the
## "Raider behavior" settings on. (Real PMCs will be players, with multiplayer.)
## The AI is split into parts (0.14.6): see scav_base.gd. This last part is the per-frame brain, damage and
## death, and the online side.

const POP_SOUND := preload("res://audio/pop.wav")
const FLASH_MATERIAL := preload("res://materials/flash_white.tres")
var _sight_check_time := 0.0
var _hit_flash_time := 0.0
## Whether the hit-flash overlay is on right now (so the meshes are only touched when it changes).
var _flashing := false
var _walk_time := 0.0
## Tests: merge the model's parts headless too (they're only merged where something is drawn).
static var merge_headless := false
const NET_LEAN_IN := 1
const NET_WINDUP := 2
const NET_LUNGE := 4
## Times it has been hit (sent to puppets so they flash when it goes up).
var hits_taken := 0
## Puppet only: [arrival seconds, state] buffer, drawn RemotePlayer.INTERP_DELAY in the past like other players.
var _net_buffer: Array = []
var _net_hits := 0


func _ready() -> void:
	add_to_group("enemies")
	_side = 1.0 if randf() < 0.5 else -1.0
	if loadout != "":
		var gun := AILoadouts.pick(loadout)
		AILoadouts.apply_style(self, gun)
		weapon_drop = gun
		shot_sound = GunSounds.shot(gun)
		carried_gun = gun
		if HeldGun.MODELS.has(gun):
			held_model = gun
	body_pose = BodyPose.new(model)
	if held_model != "":
		muzzle = HeldGun.show(model, held_model).get_node("Muzzle")
	# The model is an imported .glb, so the flash lives in this scene and moves onto its muzzle here.
	muzzle_flash.reparent(muzzle, false)
	muzzle_flash.visible = false
	_merge_model.call_deferred()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_wear_gear()
	_heals_left = heals
	_voice = voice_pitch * randf_range(0.92, 1.08)
	# Its own copies of the hit shapes, so crouching this one doesn't shrink every scav.
	for shape_node: CollisionShape3D in [$BodyShape, $HeadShape]:
		shape_node.shape = shape_node.shape.duplicate()
	_body_rest = ($BodyShape as CollisionShape3D).position
	_body_size = (($BodyShape as CollisionShape3D).shape as BoxShape3D).size
	_head_rest = ($HeadShape as CollisionShape3D).position
	if glint:
		_make_glint()


func _physics_process(delta: float) -> void:
	if state == State.DEAD or puppet:
		return
	if _lod_skip(delta):
		return
	delta += _lod_delta
	_lod_delta = 0.0
	_lod_glide_finish()
	_tick_delta = delta
	_lod_scale = delta / get_physics_process_delta_time()
	var moved_from := global_position
	var turned_from := rotation.y
	# Somehow under the hills (0.13.9, owner: a friend saw one in the floor; the ground is solid from below, so it
	# would be stuck there): back on top, like players.
	_ground_check_left -= delta
	if _ground_check_left <= 0.0:
		_ground_check_left = 0.5
		global_position = BoxMap.above_ground(self, global_position)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_state_time += delta
	_alive_time += delta
	_melee_cooldown_left -= delta
	_since_threat += delta
	_cover_cooldown_left -= delta
	_bark_left -= delta
	if state == State.IDLE and not holds_position and not puppet:
		_mutter_left -= delta
		if _mutter_left <= 0.0:
			if _mutter_left > -1.0:   # (-1: just started, roll the first wait)
				_chatter("idle")
			_mutter_left = _mutter_dice.randf_range(20.0, 50.0)
	# Crouched only while hiding at low cover (holding, or patching up there); up again to peek or move.
	_crouched = _cover_low and state == State.ENGAGE and _cover_phase in [Cover.HOLDING, Cover.HEALING]

	if _target == null or not is_instance_valid(_target) or _target.out_of_fight():
		_target = _pick_target()

	var to_target := Vector3.ZERO
	var dist := INF
	if _target != null and not _target.out_of_fight():
		to_target = _target.global_position - global_position
		to_target.y = 0.0
		dist = to_target.length()

	_sight_check_time -= delta
	if _sight_check_time <= 0.0:
		_sight_check_time = 0.1
		_can_see = dist < sight_range and _has_line_of_sight() and not _leaves_in_way()
	_unseen_time = 0.0 if _can_see else _unseen_time + delta

	# Chased you too far from its area: give up and head back (it won't re-spot you for a few seconds unless shot).
	_home_return_left -= delta
	_wary_left -= delta
	if stays_home and state in [State.ALERT, State.ENGAGE, State.INVESTIGATE] and not _near_home(global_position):
		_cover_phase = Cover.NONE
		_hold_fire()
		_set_state(State.IDLE)
		_wander_dir = Vector3.ZERO
		_wander_time = 0.0
		_home_return_left = 6.0

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			desired = _scan(delta) if holds_position else _wander(delta)
			if _home_return_left <= 0.0 and _spotting(delta, to_target, dist, spot_suspicious_mult if _wary_left > 0.0 else 1.0):
				_alert(_target.global_position)
		State.INVESTIGATE:
			# Walk over to where the sound was, looking that way.
			if holds_position:   # look toward the noise from the perch
				_face(_flat(_goal - global_position), delta, 3.0)
				if _state_time > 3.0:
					_set_state(State.SEARCH)
			else:
				_look_at_sound_left -= delta
				if _look_at_sound_left > 0.6:
					pass   # a moment to register it ("huh?")
				elif _look_at_sound_left > 0.0:
					_face(_flat(_heard_at - global_position), delta, 14.0)
				else:
					desired = _path_velocity(_goal, move_speed * (jog_speed if _answering_call or _alarmed else investigate_speed))
					_face(desired, delta)
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _arrived(_goal) or _state_time > 15.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			if _hunting and not holds_position:
				desired = _hunt(delta)
			else:
				# Look around the spot, then go back to wandering.
				rotation.y += delta * 1.2 * _side
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _state_time > (hunt_time if _hunting else search_time):
				if _hunting:
					_wary_left = wary_time
				_set_state(State.IDLE)
		State.ALERT:
			# Turn toward you if it can see you, else toward where it knows you were.
			_face(to_target if _can_see else _flat(_last_seen - global_position), delta)
			if _state_time >= _reaction:
				_set_state(State.ENGAGE)
				_fire_timer = aim_time
				# No running for cover on first sight, even far off (0.17.9, owner: it read as running away): in
				# range it opens fire, out of range it moves up until it can (see _decide's opening volley).
		State.ENGAGE:
			# Keeps tracking you while it can see you; once it has lost you for a moment it has to re-spot you.
			var sees := _can_see and (_lost_sight_time < maxf(reacquire_grace, track_time)
				or _spotting(delta, to_target, dist, spot_reacquire_mult))
			if dist == INF:
				_set_state(State.IDLE)
			else:
				desired = _fight(delta, sees, to_target, dist) + _separation(delta)

	# The fight's gone quiet (out of sight a while, nothing shooting at it): patch up where it is.
	if _cover_phase == Cover.HEALING and state != State.ENGAGE:
		desired = Vector3.ZERO
		_tick_heal(delta)
	elif _quiet_enough_to_heal():
		_start_heal()
	if holds_position and home_radius > 0.0 and not _in_home(global_position + desired * delta * 4.0):
		desired = Vector3.ZERO   # the edge of its perch
	if _sneaking():
		desired *= 0.55
	if is_wounded():
		desired *= wounded_speed
	if BoxMap.is_wading(self):   # slower through water, like players (0.11.20)
		desired *= 0.6
	if BoxMap.in_bush(self):     # and through bushes (0.18.3)
		desired *= 0.7
	_unstick_left -= delta
	if _unstick_left > 0.0 and desired.length() > 0.5:
		desired = _unstick_dir * desired.length()
	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	if _lod_scale > 1.01:
		# (A slow tick: moves as far as all the frames it skipped would have.)
		velocity *= _lod_scale
		move_and_slide()
		velocity /= _lod_scale
		_lod_glide_start(moved_from, turned_from)
	else:
		move_and_slide()
	_slide_off_heads()
	_check_stuck(delta, desired)
	_update_footsteps(delta)


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if puppet:
		_puppet_update(delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.5

	_muzzle_flash_time -= delta
	muzzle_flash.visible = _muzzle_flash_time > 0.0
	_update_glint()

	_hit_flash_time -= delta
	_flinch_left -= delta
	_lunge_left -= delta
	# Visible jolt when hit: the body snaps back and settles. Bash: leans back to wind up, then lunges.
	# (The model faces -Z, so a positive X rotation tips it backward and a negative one forward.)
	var tilt := 0.3 * maxf(_flinch_left - (flinch_time - 0.25), 0.0) / 0.25
	if (_looting_left > 0.0 and state == State.IDLE) or _cover_phase == Cover.HEALING:
		tilt -= 0.35  # leaning in: searching a container, or patching itself up
	if _windup_left > 0.0:
		tilt += 0.35 * (1.0 - _windup_left / melee_windup)
		if puppet:
			_windup_left -= delta
	elif _lunge_left > 0.0:
		tilt -= 0.4
	model.rotation.x = tilt
	# Limping: the body dips to one side with every other step.
	_limp = move_toward(_limp, 1.0 if is_wounded() else 0.0, delta * 3.0)
	model.rotation.z = _limp * maxf(sin(_walk_time), 0.0) * 0.18 * minf(speed / 1.5, 1.0)
	_update_crouch(delta)
	body_pose.speed = speed
	body_pose.crouch = _crouch_amount
	body_pose.update(delta)
	var flashing := _hit_flash_time > 0.0
	if flashing != _flashing:
		_flashing = flashing
		var overlay: Material = FLASH_MATERIAL if flashing else null
		for mesh in model.find_children("*", "GeometryInstance3D", true, false):
			(mesh as GeometryInstance3D).material_overlay = overlay
var _home_return_left := 0.0
var _wary_left := 0.0
var _limp := 0.0


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	hits_taken += 1
	_target_shooter(source_position)
	_since_threat = 0.0
	_last_hit_from = source_position
	if _cover_phase == Cover.HEALING:
		_cover_phase = Cover.NONE   # interrupted: back to fighting (it patches up again once it's quiet)
	_hit_flash_time = 0.08
	if _flinch_left <= 0.0:
		_fire_timer = maxf(_fire_timer, flinch_fire_delay)
	_flinch_left = flinch_time
	_hit_since_decide = true
	if tactic == Tactic.STAND and _cover_phase == Cover.NONE and _dodge_left <= 0.0:
		_dodge_left = 0.35
		_dodge_dir = -1.0 if randf() < 0.5 else 1.0
	if not health.is_dead and is_wounded() and not _was_wounded:
		# Just got badly hurt: shout for help and get into cover (close by if you're close).
		_was_wounded = true
		_bark_left = 0.0
		_bark("help")
		if _target != null:
			_call_for_help(_target.global_position)
		if not holds_position and _cover_phase == Cover.NONE and state == State.ENGAGE:
			_try_take_cover(close_cover_radius if _can_see and _target != null and global_position.distance_to(_target.global_position) < close_fight_range else -1.0)
			_hit_since_decide = false   # (this hit is why it's going: don't count it as being shot on the way)
	elif not health.is_dead:
		_bark("hurt", 0.5)
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		_knockback = push.normalized() * 3.0
	# Getting shot while unaware: it knows roughly where that came from.
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		_alert(source_position, startle_reaction_time)


## Its armor and helmet, worn (see `armor`).
var _gear: Array[ItemStack] = []


## One mesh per moving part instead of one per piece of clothing (0.18.12, fewer draw calls). Deferred: online, a
## puppet's outfit is picked just after it joins the tree (and picking again re-merges anyway).
func _merge_model() -> void:
	if DisplayServer.get_name() != "headless" or merge_headless:
		(model as PixelModel).merge_parts()


func _wear_gear() -> void:
	for id in [armor, helmet]:
		if ItemDB.ITEMS.has(id):
			_gear.append(ItemStack.new(id))
	_update_gear()
	health.armor_hit.connect(func(amount: int, head: bool) -> void:
		var hit_gear := _gear_for(head)
		if hit_gear != null and hit_gear.durability > 0:
			ItemDB.wear(hit_gear, amount)
			_update_gear())


func _gear_for(head: bool) -> ItemStack:
	for stack in _gear:
		if (ItemDB.kind(stack.id) == "helmet") == head:
			return stack
	return null


func _update_gear() -> void:
	health.damage_multiplier = 1.0 - ItemDB.reduction(_gear_for(false))
	health.head_multiplier = 1.0 - ItemDB.reduction(_gear_for(true))


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	var world := get_tree().current_scene
	Effects.burst(world, global_position + Vector3(0, 0.9, 0), burst_color)
	Effects.sound_at(world, POP_SOUND, global_position)
	if not puppet and _last_hit_from != Vector3.INF:
		_warn_friends()
	if puppet:
		queue_free()  # its body (and loot) is the server's
		return
	var drops: Array = []
	if weapon_drop != "" and randf() < weapon_drop_chance:
		drops.append(AILoadouts.dropped_gun(weapon_drop, drop_parts, drop_part_chance))
	for id in extra_drops:
		drops.append([id, 1])
	for id in ItemDB.TABLE_CHANCES.get(loot_table, {}):
		if randf() < ItemDB.TABLE_CHANCES[loot_table][id]:
			drops.append([id, 1])
	for stack in _gear:
		drops.append(stack)
	for i in randi_range(min_drops, max_drops):
		var id := ItemDB.roll(loot_table)
		drops.append([id, ItemDB.roll_count(id)])
	for drop: Variant in drops:
		if drop is ItemStack:
			(drop as ItemStack).mark_found()   # (its gun, the gun's attachments and worn gear are found in raid, 0.16.13)
	# Into the raid it died in (on the server, that's one of several raids, and there's no current scene).
	# (Scavs and snipers: their body shows as the backpack they wore, LootContainer.BACKPACK_BODIES, 0.17.12.)
	LootContainer.spawn_bag(get_parent(), global_position, body_name, drops, 1.0, true)
	queue_free()


# --- Online ------------------------------------------------------------------------

## What puppets need to show this scav: [position, yaw, flags, hits_taken].
func net_capture() -> Array:
	var flags := 0
	if (_looting_left > 0.0 and state == State.IDLE) or _cover_phase == Cover.HEALING:
		flags |= NET_LEAN_IN
	if _windup_left > 0.0:
		flags |= NET_WINDUP
	if _lunge_left > 0.0:
		flags |= NET_LUNGE
	if _sneaking():
		flags |= NET_SNEAK
	if state in [State.ALERT, State.ENGAGE]:
		flags |= NET_AIM
	if _crouched:
		flags |= NET_CROUCH
	if is_wounded():
		flags |= NET_WOUNDED
	return [global_position, rotation.y, flags, hits_taken]


## Puppet: a new state from the server (`at` = arrival time in seconds).
func net_push(net_state: Array, at := -1.0) -> void:
	if at < 0.0:
		at = Time.get_ticks_msec() / 1000.0
	if _net_buffer.is_empty():
		global_position = net_state[0]
		rotation.y = net_state[1]
		_net_hits = net_state[3]
	_net_buffer.append([at, net_state])
	if _net_buffer.size() > 20:
		_net_buffer.pop_front()


## Puppet: the server's scav died (pop into voxels, like offline; its body bag comes from the server).
func net_died() -> void:
	if state != State.DEAD:
		_on_died()


func _puppet_update(delta: float) -> void:
	if _net_buffer.is_empty():
		return
	var time := Time.get_ticks_msec() / 1000.0 - RemotePlayer.INTERP_DELAY
	while _net_buffer.size() > 2 and _net_buffer[1][0] <= time:
		_net_buffer.pop_front()
	var a: Array = _net_buffer[0]
	var b: Array = _net_buffer[1] if _net_buffer.size() > 1 else a
	var t := 1.0 if b[0] <= a[0] else clampf((time - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var old := global_position
	global_position = (a[1][0] as Vector3).lerp(b[1][0], t)
	rotation.y = lerp_angle(a[1][1], b[1][1], t)
	velocity = (global_position - old) / maxf(delta, 0.001)
	var flags: int = b[1][2]
	# Rising edges start the same animations the server's scav is playing.
	if flags & NET_WINDUP and not _net_flags & NET_WINDUP:
		_windup_left = melee_windup
	if flags & NET_LUNGE and not _net_flags & NET_LUNGE:
		_lunge_left = 0.15
	if not flags & NET_WINDUP:
		_windup_left = 0.0
	_net_flags = flags
	_looting_left = 1.0 if flags & NET_LEAN_IN else 0.0
	if b[1][3] > _net_hits:
		_net_hits = b[1][3]
		_hit_flash_time = 0.08
		_flinch_left = flinch_time
	_update_footsteps(delta)


## Tree tops or a bush between its eyes and yours (0.17.13, owner: the AI saw and shot through the leaves; bushes
## 0.18.3): it can't see you.
func _leaves_in_way() -> bool:
	var eyes := global_position + Vector3(0, 1.65, 0)
	var query := PhysicsRayQueryParameters3D.create(eyes, _target.eye_position(), BoxMap.LEAVES_LAYER | BoxMap.BUSH_LAYER,
		[get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
