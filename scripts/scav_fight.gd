extends "res://scripts/scav_movement.gd"
## The AI in a fight: the tactics brain, cover and peeking, flanking, suppressing, shooting, melee and healing.

const BASH_SOUND := preload("res://audio/swing.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")
## Of its hits on a player, this share land on the head (0.14.2: the helmet takes those, the armor the rest). The
## damage is the same either way: AI don't get headshot damage.
const HEAD_HIT_CHANCE := 0.15
var _fire_timer := 0.0
var _shots_left := 0
var _flinch_left := 0.0
var _melee_cooldown_left := 0.0
var _cover_point := Vector3.ZERO
var _cover_hold_left := 0.0
## Heals left this life, and time left on the current heal.
var _heals_left := 0
var _heal_left := 0.0
## How long since it last had a line of sight to its target (for patching up once things go quiet).
var _unseen_time := 0.0
## > 0 while winding up a bash.
var _windup_left := 0.0
var _lunge_left := 0.0
var _muzzle_flash_time := 0.0

## Online (0.7.8): the AI runs on the server; each player sees a puppet copy that only shows what the server's
## scav does (moved by net_push, no thinking of its own). The server sends net_capture() and these events.
signal fired(end: Vector3)
signal bash_started


## Rifle-butt bash: wind up (visible), then hit if the target is still in reach.
func _update_melee(delta: float, dist: float) -> void:
	if _windup_left <= 0.0:
		_windup_left = melee_windup
		bash_started.emit()
		_hold_fire()
		net_bash_started()
		return
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_melee_cooldown_left = melee_cooldown
	_lunge_left = 0.15
	if dist <= melee_range + 0.5:
		_target.take_bash(melee_damage, global_position, melee_shove, melee_aim_block)
var _tactic_time := 0.0
## STAND: how long it trades shots in the open before looking for cover (or a flank) again.
var _stand_time := 0.0
## Got shot since it last decided (makes a plan in the open rethink).
var _hit_since_decide := false
## Its last plan in the open was standing and shooting (so next it moves to cover: shoot first, then cover).
var _stood_last := false
## never_cover AI: how long this chase lasts before a break, whether it's on a break, and where it's stepping to.
var _chase_burst := 0.0
var _chase_break := false
var _pausing := false
var _reposition_to := Vector3.INF
var _suppress_at := Vector3.ZERO
## Moving to cover after trading shots in the open: strafes there still shooting (0.12.37).
var _strafe_to_cover := false
## A quick sidestep after getting shot in the open (the only sideways move it makes there).
var _dodge_left := 0.0
## When it set off to cover or round a flank: how far off you were (INF if it couldn't see you) and where you were.
var _move_seen_from := INF
var _move_target_from := Vector3.ZERO


func _fight(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	_tactic_time += delta
	_dodge_left -= delta
	if (not sees and _lost_sight_time < track_time and _target != null and is_instance_valid(_target)
			and dist < track_range):
		_last_seen = _target.global_position   # still knows where you are for a few seconds after losing sight
	# The cover plans (cover + peeking, flanking, falling back to heal) run their own steps until they end.
	if _cover_phase != Cover.NONE:
		var move := _update_cover(delta, sees, to_target, dist)
		if _cover_phase == Cover.NONE:
			tactic = Tactic.NONE   # done: decide again next frame
		return move
	if sees:
		_fled_left = 0.0
		_suppress_left = 0.0
		_may_suppress = true
		_last_seen = _target.global_position
		_suppress_at = _last_seen   # (pinning you down: where it last SAW you, not where it knows you went)
		_lost_sight_time = 0.0
		_spot = 0.0
		# Reflexes.
		if _windup_left > 0.0 or (dist < melee_range and _melee_cooldown_left <= 0.0):
			_face(to_target, delta)
			_update_melee(delta, dist)
			return Vector3.ZERO
		if dist < min_distance:
			_face(to_target, delta)
			_update_shooting(delta, dist)
			return _clear_of_walls(-to_target.normalized() * move_speed * 0.7)
	else:
		_lost_sight_time += delta
	if tactic == Tactic.NONE or _should_rethink(sees, dist):
		_decide(sees, to_target, dist)
		if _cover_phase != Cover.NONE:
			return _update_cover(delta, sees, to_target, dist)
	match tactic:
		Tactic.STAND:
			# Trades shots where it stands; the only sideways move is a quick dodge right after being hit.
			_face(to_target, delta)
			_update_shooting(delta, dist)
			if _reposition_to != Vector3.INF:
				if _arrived(_reposition_to):
					_reposition_to = Vector3.INF
				else:
					return _path_velocity(_reposition_to, move_speed * push_speed)
			if _dodge_left > 0.0 and not holds_position:
				return _clear_of_walls(to_target.normalized().cross(Vector3.UP) * _dodge_dir * move_speed * 0.8)
			return Vector3.ZERO
		Tactic.PUSH:
			_face(to_target, delta)
			_update_shooting(delta, dist)
			return _path_velocity(_target.global_position, move_speed * push_speed)
		Tactic.CHASE:
			# Walks straight at you shooting. Where the path bends round something it faces where it's going and
			# holds fire for those steps, so it never walks sideways across your view.
			var chase_move := _path_velocity(_target.global_position, move_speed * push_speed)
			if chase_move.length() > 0.1 and _flat(chase_move).normalized().dot(_flat(to_target).normalized()) < 0.5:
				_face(chase_move, delta)
				_hold_fire()
			else:
				_face(to_target, delta)
				_update_shooting(delta, dist)
			return chase_move
		Tactic.ADVANCE:
			_hold_fire()
			if holds_position:
				_face(to_target, delta)
				return Vector3.ZERO
			return _close_in(delta, _target.global_position, to_target)
		Tactic.SUPPRESS:
			# Pinning you down: keeps firing at where you ducked out of sight.
			_suppress_left -= delta
			_face(_flat(_suppress_at - global_position), delta)
			_update_shooting(delta, global_position.distance_to(_suppress_at), true)
			return Vector3.ZERO
		Tactic.PURSUE:
			# Ran off from a sniper it can't fight: stays hidden, watching that way, until FLEE_TIME is up.
			if _fled_left > 0.0:
				_fled_left -= delta
				_face(_flat(_last_seen - global_position), delta)
				_lost_sight_time = 0.0
				return Vector3.ZERO
			# Lost sight: go to where it last saw you (it doesn't know where you went), then search.
			if _arrived(_last_seen) or _lost_sight_time > give_up_time:
				_set_state(State.SEARCH)
				_start_hunt()
				_bark("lost", 0.6)
				return Vector3.ZERO
			if holds_position or is_hurt() or _strays_from_guards(_last_seen):   # (badly hurt: it doesn't come after you, it waits for you to show; Bon: not away from his guards)
				_face(_flat(_last_seen - global_position), delta)
				return Vector3.ZERO
			if _flat(_last_seen - global_position).length() > shoot_range:
				return _close_in(delta, _last_seen, _flat(_last_seen - global_position))
			var move := _path_velocity(_last_seen, move_speed)
			_face(move, delta)
			return move
	return Vector3.ZERO


## Whether the current plan no longer fits (something real changed).
func _should_rethink(sees: bool, dist: float) -> bool:
	match tactic:
		Tactic.STAND:
			return (not sees or dist > shoot_range or _can_push(dist) or _tactic_time > _stand_time
				or (_hit_since_decide and _dodge_left <= 0.0 and _tactic_time > 1.0)
				or (not _pausing and _can_chase(dist) and dist > chase_stop + 3.0))
		Tactic.CHASE:
			# (Getting hit doesn't stop it: it keeps coming.)
			if never_cover and _tactic_time > _chase_burst:
				_chase_break = true
				return true
			return not sees or not _can_chase(dist) or dist <= chase_stop or _can_push(dist)
		Tactic.PUSH:
			return not sees or not _can_push(dist)
		Tactic.ADVANCE:
			return not sees or dist <= shoot_range
		Tactic.SUPPRESS:
			return sees or _suppress_left <= 0.0
		Tactic.PURSUE:
			return sees
	return true


## Sniped from out of its range: how long it stays hidden after running off before it goes looking (seconds).
const FLEE_TIME := 20.0
var _fled_left := 0.0

## Picks the plan, in order: lost you: pin you down (if a friend can flank) or go after you; too far: move up;
## you're reloading or healing: push; otherwise get to cover (sometimes flank in a lull), and only with no cover
## anywhere near, trade shots in the open. Badly hurt it never pushes or flanks, and it never runs away: it
## repositions to cover and keeps fighting (0.12.32, owner), patching up once the fight goes quiet.
func _decide(sees: bool, to_target: Vector3, dist: float) -> void:
	_tactic_time = 0.0
	var was_hit := _hit_since_decide
	_hit_since_decide = false
	_pausing = false
	_reposition_to = Vector3.INF
	if not sees:
		_chase_break = false
		# Sniped from beyond its own range, with no way to shoot back (0.15.26, owner): it runs off somewhere farther
		# away that the shooter can't see, then lies low for a while (FLEE_TIME) before it goes looking.
		if was_hit and _target != null and dist > shoot_range and not holds_position and not never_cover:
			var away := _find_cover(cover_search_radius * 2.0, 8.0)
			if away != Vector3.INF:
				_cover_point = away
				_cover_low = _found_low
				_cover_phase = Cover.MOVING
				_peeks_left = 0
				_peek_point = global_position
				_note_move_start()
				_bark("cover", 0.35)
				_fled_left = FLEE_TIME
				tactic = Tactic.COVER
				return
		if _suppress_left > 0.0 or _try_suppress():
			tactic = Tactic.SUPPRESS
		else:
			tactic = Tactic.PURSUE
		return
	if dist > shoot_range:
		tactic = Tactic.ADVANCE
		return
	# Opening volley (0.17.9, owner): the first thing it does in a fight it can see you in is stand and shoot,
	# before any push, flank or cover run. Badly hurt it still goes for cover first.
	if _opening:
		_opening = false
		if not is_hurt():
			_stood_last = true
			_pausing = true   # (holds its ground for the volley even in chase range)
			tactic = Tactic.STAND
			_stand_time = randf_range(2.0, 3.0)
			_fire_timer = minf(_fire_timer, aim_time)
			return
	if _can_push(dist):
		tactic = Tactic.PUSH
		_bark("push")
		return
	# In range to really hurt you: mostly it comes at you (a flank in a lull still counts), sometimes cover first.
	if _chase_break:
		# A break between chases (never_cover AI, owner): stands and fires, or steps aside firing, then comes on.
		_chase_break = false
		_pausing = true
		_stood_last = true
		tactic = Tactic.STAND
		_stand_time = randf_range(chase_pause_min, chase_pause_max)
		_fire_timer = minf(_fire_timer, 0.15)   # (owner: never just standing there: it opens fire right away)
		if randf() < reposition_chance:
			_reposition_to = _side_step(to_target)
		return
	if _can_chase(dist) and dist > chase_stop:
		if _since_threat > lull_time and dist >= close_fight_range and randf() < flank_chance:
			_try_flank(to_target, dist)
			if _cover_phase == Cover.FLANKING:
				tactic = Tactic.FLANK
				return
			_cover_phase = Cover.NONE   # (no hidden flank spot: it took cover instead; chase or cover rolls below)
		if never_cover or randf() >= chase_cover_chance or _cover_cooldown_left > 0.0:
			if tactic != Tactic.CHASE:
				_bark("push", 0.4)
			tactic = Tactic.CHASE
			_chase_burst = randf_range(chase_burst_min, chase_burst_max)
			return
	# Its first instinct is to shoot (0.12.36, owner: in the open they still ran first): a healthy AI that wasn't
	# just trading shots stands and fires for a couple of seconds before it moves to cover. Badly hurt, cover first.
	if not is_hurt() and tactic != Tactic.STAND and not _stood_last:
		_stood_last = true
		tactic = Tactic.STAND
		_stand_time = randf_range(2.0, 3.0)
		return
	var from_the_open := _stood_last and dist > chase_range
	_stood_last = false
	_strafe_to_cover = false
	if not holds_position and _cover_cooldown_left <= 0.0:
		# Up close (inside a building, round a corner) its first instinct is to shoot back: it only ducks into cover
		# that's a step or two away (0.12.30, owner: one ran around looking for cover while he shot it).
		if dist < close_fight_range:
			_try_take_cover(close_cover_radius)
		elif _since_threat > lull_time and randf() < flank_chance and not is_hurt():
			_try_flank(to_target, dist)   # (takes cover instead if there's no hidden spot to flank to)
		else:
			_try_take_cover()
		if _cover_phase != Cover.NONE:
			tactic = Tactic.FLANK if _cover_phase == Cover.FLANKING else Tactic.COVER
			_strafe_to_cover = from_the_open and _cover_phase == Cover.MOVING
			return
	tactic = Tactic.STAND
	_stand_time = randf_range(2.0, 3.0) * (0.5 if is_hurt() else 1.0)   # badly hurt: looks for cover again sooner


## A spot a few meters to one side (and a little closer) it can walk to while firing, or INF if there's none.
func _side_step(to_target: Vector3) -> Vector3:
	var forward := _flat(to_target).normalized()
	var side := forward.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	for s in [side, -side]:
		var spot := AINav.closest(self, global_position + s * 4.0 + forward * 1.0)
		if spot != Vector3.ZERO and _flat(spot - global_position).length() > 2.0:
			return spot
	return Vector3.INF


## You're reloading or healing and it's not hurt: worth rushing you.
func _can_push(dist: float) -> bool:
	return (_target_busy() and not holds_position and not is_hurt() and dist > min_distance + 2.0
		and not _leashed_from_target())


## Close enough to really hurt you, and fit and free to come after you.
func _can_chase(dist: float) -> bool:
	return dist <= chase_range and not holds_position and not is_hurt() and not _leashed_from_target()


## Bon out at the end of his guard leash with you farther on (0.21.18): he holds there instead of coming after you.
func _leashed_from_target() -> bool:
	return _target != null and is_instance_valid(_target) and _strays_from_guards(_target.global_position)


## Too far away to shoot (e.g. you're up on a hill): it moves up cover to cover (0.12.7, owner: they went into
## cover, then just walked at him in the open). With no cover ahead it waits where it is, out of sight if it can.
func _close_in(delta: float, goal: Vector3, to_goal: Vector3) -> Vector3:
	if _strays_from_guards(goal):
		_face(to_goal, delta)
		return Vector3.ZERO   # (Bon: holds at his guard leash, 0.21.18)
	_advance_check_left -= delta
	if _advance_check_left <= 0.0 and not never_cover:
		_advance_check_left = 0.6
		var spot := _find_advance_cover(goal)
		if spot != Vector3.INF:
			_cover_point = spot
			_cover_low = false
			_cover_phase = Cover.MOVING
			_strafe_to_cover = false
			_peek_point = Vector3.INF
			_peeks_left = 0
			_note_move_start()
			return _path_velocity(spot, move_speed)
		if _can_see and _cover_cooldown_left <= 0.0:
			_try_take_cover()   # nothing closer: at least get out of your sight
			if _cover_phase != Cover.NONE:
				return Vector3.ZERO
	_face(to_goal, delta)
	if _can_see and _lost_sight_time <= 0.0 and (never_cover or _no_cover_around()):
		# Out in the open with nowhere to hide: rush straight in.
		return _path_velocity(goal, move_speed)
	return Vector3.ZERO


## True when it already checked and there's no cover near here worth going to.
func _no_cover_around() -> bool:
	return _cover_cooldown_left > 0.0 and _cover_phase == Cover.NONE


## The next spot of cover toward `goal`: a few meters closer to it and out of its view, or INF if there's none.
func _find_advance_cover(goal: Vector3) -> Vector3:
	var eyes := goal + Vector3(0, 1.6, 0)
	if _target != null and _can_see:
		eyes = _target.eye_position()
	var to_goal := _flat(goal - global_position)
	var dist := to_goal.length()
	if dist < 1.0:
		return Vector3.INF
	var forward := to_goal / dist
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_left := dist - 5.0   # must gain at least 5 m
	for radius in [8.0, 13.0, 18.0]:
		for i in 7:
			var dir := forward.rotated(Vector3.UP, deg_to_rad(-60.0 + i * 20.0))
			var spot := AINav.closest(self, global_position + dir * radius)
			if spot == Vector3.ZERO:
				continue
			var left := _flat(goal - spot).length()
			if left >= best_left or left < shoot_range * 0.5:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty():
				continue  # it would be in view there
			if AINav.path_length(AINav.path(self, global_position, spot)) > radius * 1.6:
				continue
			best = spot
			best_left = left
	return best


## Looks for a walkable spot nearby that the target can't see; starts moving there if it finds one.
func _try_take_cover(radius := -1.0) -> void:
	_strafe_to_cover = false
	_cover_cooldown_left = cover_cooldown
	if never_cover:
		return
	var spot := _find_cover(radius)
	if spot != Vector3.INF:
		_cover_point = spot
		_cover_low = _found_low
		_cover_phase = Cover.MOVING
		_note_move_start()
		_bark("cover", 0.35)
		# Where it stands now can see you: that's where it peeks out from.
		_peek_point = global_position
		# (Too far to shoot back from there: no point peeking out, it moves up cover to cover instead.)
		_peeks_left = peeks if _target != null and global_position.distance_to(_target.global_position) <= shoot_range else 0
		if _target != null and _can_chase(global_position.distance_to(_target.global_position)):
			_peeks_left = mini(_peeks_left, 1)   # in chase range: one peek, then it comes after you
	else:
		_cover_cooldown_left = 3.0  # nothing nearby: keep fighting, look again soon


## Circle around the target: a reachable spot off to one side at about the same distance (Raiders, scavs since 0.12.3).
## A flank (0.12.28-0.12.29, owner: no sideways runs across your view, no messy loops): it circles to a spot
## 50-90 degrees round from where it is now, 10-20 m from where it knows you are, that you can't see, along a path
## that's not too long and doesn't pass close to you. With no such spot it takes cover instead.
func _try_flank(to_target: Vector3, dist: float) -> void:
	_cover_cooldown_left = cover_cooldown
	var center := global_position + _flat(to_target)
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var back := -_flat(to_target).normalized()   # from you toward it
	var radius := clampf(dist, 10.0, 20.0)
	var first := 1.0 if randf() < 0.5 else -1.0
	for side_sign: float in [first, -first]:
		for angle: float in [70.0, 50.0, 90.0]:
			var spot := AINav.closest(self, center + back.rotated(Vector3.UP, deg_to_rad(angle) * side_sign) * radius)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() < 4.0:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.5, eyes, 1)).is_empty():
				continue   # you'd see it get there
			var route := AINav.path(self, global_position, spot)
			var length := AINav.path_length(route)
			if length > 30.0 or length > _flat(spot - global_position).length() * 2.0:
				continue   # a long loop round
			var too_close := false
			for point in route:
				if _flat(point - center).length() < 6.0:
					too_close = true
					break
			if too_close:
				continue   # the way there runs right past you
			_cover_point = spot
			_cover_low = false
			_cover_phase = Cover.FLANKING
			_note_move_start()
			_bark("flank")
			return
	_cover_cooldown_left = 0.0
	_try_take_cover()


## Lost sight of everyone a while and nothing's shooting at it: worth patching up (if it's lost a fair bit).
func _quiet_enough_to_heal() -> bool:
	return (_heals_left > 0 and _cover_phase != Cover.HEALING and state in [State.ENGAGE, State.SEARCH, State.IDLE]
		and health.current <= health.max_health - heal_amount / 2 and _since_threat >= quiet_heal_time
		and _unseen_time >= quiet_heal_time and _windup_left <= 0.0)


## Patching up: true when done (healed).
func _tick_heal(delta: float) -> bool:
	_heal_left -= delta
	_hold_fire()
	if _heal_left > 0.0:
		return false
	health.heal(heal_amount)
	_heals_left -= 1
	_was_wounded = is_wounded()
	_cover_phase = Cover.NONE
	_lost_sight_time = 0.0
	return true


func _start_heal() -> void:
	_cover_phase = Cover.HEALING
	_heal_left = heal_time
	_hold_fire()
	_bark("heal")
	Effects.sound_at(get_tree().current_scene, HEAL_SOUND, global_position, -6.0, 0.1, 1.0, 6.0, 20.0)


## The closest walkable spot within `radius` (by walking distance) the target can't see; INF if none. Retreating
## (`farther` > 0), only spots at least that much farther from the target than it is now count.
func _find_cover(radius := -1.0, farther := 0.0) -> Vector3:
	if radius < 0.0:
		radius = cover_search_radius
	var my_dist := _flat(global_position - _target.global_position).length()
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_walk := INF
	_found_low = false
	# First the far side of things right around it (a tree trunk, a tent, a car, a wall corner, a hillside): the
	# circle samples below easily miss something as thin as a trunk (0.12.10, owner: one didn't hide behind the
	# tents or trees at the camp).
	var away := _flat(global_position - _target.global_position).normalized()
	var chest := global_position + Vector3(0, 1.0, 0)
	for i in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 16.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir * radius, 1, [get_rid()]))
		if hit.is_empty():
			continue
		var behind: Vector3 = hit.position + away * 0.9 - dir * 0.3
		var spot := AINav.closest(self, Vector3(behind.x, global_position.y, behind.z))
		if spot == Vector3.ZERO or _flat(spot - behind).length() > 1.5:
			continue
		var hides := _hides_at(space, eyes, spot)
		if hides == 0 or _spot_taken(spot) or _flat(spot - _target.global_position).length() < my_dist + farther:
			continue  # the target could see it there, or a friend is already hiding there
		# (Low cover, where it has to crouch, counts as a few meters farther: it prefers a spot it can stand at.)
		var walk := AINav.path_length(AINav.path(self, global_position, spot))
		if walk <= radius * 1.6 and walk + (3.0 if hides == 1 else 0.0) < best_walk:
			best = spot
			best_walk = walk + (3.0 if hides == 1 else 0.0)
			_found_low = hides == 1
	if best != Vector3.INF:
		return best
	for ring: float in [3.0, 5.0, radius]:
		for i in 12:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 12.0)
			var spot := AINav.closest(self, global_position + dir * ring)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() > ring + 1.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty() or _spot_taken(spot) or _flat(spot - _target.global_position).length() < my_dist + farther:
				continue  # the target could see it there, or a friend is already hiding there
			# Judge by walking distance: a spot inside a building may be close in a straight line but far around.
			var walk := AINav.path_length(AINav.path(self, global_position, spot))
			if walk <= ring * 1.6 and walk < best_walk:
				best = spot
				best_walk = walk
		if best != Vector3.INF:
			break
	return best


## A friend is at (or heading to) cover within 2 m of `spot`: each AI gets its own spot, so they don't bunch up
## behind the same box (0.12.29).
func _spot_taken(spot: Vector3) -> bool:
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self or other.state == State.DEAD:
			continue
		if _flat(other.global_position - spot).length() < 2.0:
			return true
		if other._cover_phase != Cover.NONE and _flat(other._cover_point - spot).length() < 2.0:
			return true
	return false


## Whether `spot` is hidden from `eyes`: 2 standing up, 1 only crouched (low cover), 0 not at all.
func _hides_at(space: PhysicsDirectSpaceState3D, eyes: Vector3, spot: Vector3) -> int:
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)).is_empty():
		return 2
	var head := spot + Vector3(0, 1.71 * CROUCH_HEIGHT + 0.2, 0)
	if (not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, head, 1)).is_empty()
			and not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 0.5, 0), 1)).is_empty()):
		return 1
	return 0


## True if it's not getting anywhere (e.g. the last bit of the path is blocked by another scav).
func _cover_stuck(move: Vector3) -> bool:
	return move.length() < 0.05 or (get_real_velocity().length() < 0.1 and _flat(_cover_point - global_position).length() < 1.2)


## Moving to cover (still shooting if it has a shot), then holding a moment; after that it goes back to the fight
## (if it can't see you from cover, it heads to where it last saw you = peeking out).
func _update_cover(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	if _cover_phase == Cover.FLANKING:
		# Runs there facing where it's going (not sideways while shooting at you); shot on the way: fights back.
		var flank_move := _path_velocity(_cover_point, move_speed)
		_face(flank_move, delta)
		_hold_fire()
		# Done, stuck, shot at, it runs into you up close, or you show up: back to deciding (and fighting).
		var fight := _fight_instead(sees, dist)
		if _arrived(_cover_point) or _cover_stuck(flank_move) or (sees and (_flinch_left > 0.0 or dist < 10.0)) or fight:
			_cover_phase = Cover.NONE
			_lost_sight_time = 0.0
			if fight:
				_cover_cooldown_left = cover_cooldown   # (shoots first, not straight off to cover again)
		return flank_move
	if _cover_phase == Cover.MOVING:
		# Runs to cover with intent: facing where it's going, not shooting (0.12.36, owner; 0.12.28: no sideways
		# walking to cover while shooting at you). The last step in it turns to face you.
		# Except out in the open after trading shots (0.12.37, owner: "they shoot a few times then run to cover,
		# which is unrealistic"): there it strafes over still shooting at you.
		if _strafe_to_cover and sees and dist <= shoot_range:
			var strafe := _path_velocity(_cover_point, move_speed * 0.85)
			_face(to_target, delta)
			_update_shooting(delta, dist)
			if _flat(_cover_point - global_position).length() < 0.4 or _cover_stuck(strafe):
				_cover_phase = Cover.HOLDING
				_cover_hold_left = cover_hold_time
			return strafe
		var move := _path_velocity(_cover_point, move_speed)
		if move.length() < 0.5:
			_face(to_target if sees else _flat(_last_seen - global_position), delta)
		else:
			_face(move, delta)
		_hold_fire()
		# Shot up close on the way, with the cover still a way off: turns and fights instead of running with its
		# back to you (0.12.31).
		# Same when you show up or come at it while it's on its way (0.14.11, owner).
		if (sees and (_hit_since_decide and dist < close_fight_range or _fight_instead(sees, dist))
				and _flat(_cover_point - global_position).length() > 2.0):
			_cover_phase = Cover.NONE
			_cover_cooldown_left = cover_cooldown
			return Vector3.ZERO
		# Get all the way in (normal arriving allows 1.2 m, which can leave it peeking past the corner).
		if _flat(_cover_point - global_position).length() < 0.4 or _cover_stuck(move):
			_cover_phase = Cover.HOLDING
			_cover_hold_left = cover_hold_time * (1.5 if is_hurt() else 1.0)   # badly hurt: stays down a bit longer
		return move
	if _cover_phase == Cover.HEALING:
		_face(_flat(_last_seen - global_position), delta)
		_tick_heal(delta)
		return Vector3.ZERO
	_cover_hold_left -= delta
	if _cover_phase == Cover.PEEKING:
		return _update_peek(delta, sees, to_target, dist)
	if _target_busy():
		_cover_hold_left = 0.0   # you're reloading or healing: come out now
	_face(_flat(_last_seen - global_position), delta)
	_hold_fire()
	if _cover_hold_left <= 0.0:
		_lost_sight_time = 0.0
		if _peeks_left > 0 and _peek_point != Vector3.INF and not _target_busy():
			_peeks_left -= 1
			_cover_phase = Cover.PEEKING
			_peek_left = randf_range(peek_time_min, peek_time_max)
			_peek_blind = 0.0
		else:
			_cover_phase = Cover.NONE   # done peeking (or you're reloading): back to the open fight / chase
	return Vector3.ZERO


## Peeking out of cover: step to where it could see you, shoot while it can, then duck back into cover.
## If it gets there and you're gone, it stops hiding and goes after you.
func _update_peek(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	var move := Vector3.ZERO
	if not sees:
		move = _path_velocity(_peek_point, move_speed * 0.8)
		# The last step or two out it faces you, ready to shoot; farther than that it walks there facing ahead
		# (0.12.30: no long sideways walks out of cover).
		var out_left := _flat(_peek_point - global_position).length()
		_face(_flat(_last_seen - global_position) if out_left < 2.0 else move, delta)
		_hold_fire()
		if _arrived(_peek_point) or _cover_stuck(move):
			_peek_blind += delta
			if _peek_blind > 1.0:
				_cover_phase = Cover.NONE   # you moved: find you
				_lost_sight_time = 0.0
		return move
	_peek_blind = 0.0
	_face(to_target, delta)
	if dist <= shoot_range:
		_update_shooting(delta, dist)
	_peek_left -= delta
	# Done (and between bursts), or getting hit: duck back in.
	if (_peek_left <= 0.0 or _flinch_left > 0.0) and _shots_left <= 0:
		# Last peek with you in chase range: it comes straight out after you instead of ducking back in.
		_cover_phase = Cover.NONE if _peeks_left <= 0 and _can_chase(dist) and _flinch_left <= 0.0 else Cover.MOVING
		if _cover_phase == Cover.MOVING:
			_note_move_start()
	return move


## Setting off to cover or round a flank: remembers where you were (see _fight_instead).
func _note_move_start() -> void:
	_move_seen_from = INF
	if _target != null and is_instance_valid(_target):
		_move_target_from = _target.global_position
		if _can_see:
			_move_seen_from = _flat(_target.global_position - global_position).length()


## On its way to cover or round a flank and you show up (0.14.11, owner: one kept repositioning while he walked
## right up to it): it stops and fights if it set off with you out of sight or out of range and now sees you in
## range, or you've come at it (moved a few meters, now close).
func _fight_instead(sees: bool, dist: float) -> bool:
	if not sees or dist > shoot_range or _target == null:
		return false
	if _move_seen_from > shoot_range:
		return true
	return dist < close_fight_range and _flat(_target.global_position - _move_target_from).length() > 3.0


## No shot right now: drop the burst and re-aim when a shot comes back.
func _hold_fire() -> void:
	_shots_left = 0
	_fire_timer = maxf(_fire_timer, aim_time)


func _update_shooting(delta: float, dist: float, suppressing := false) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if _shots_left <= 0:
		_shots_left = _burst_length(dist)
		_start_burst()
	if suppressing:
		_fire_at_point(_suppress_at + Vector3(0, 1.1, 0))
	else:
		_fire_at_target(dist)
	_shots_left -= 1
	if _shots_left > 0:
		_fire_timer = burst_interval
	else:
		_fire_timer = randf_range(burst_cooldown_min, burst_cooldown_max)


## Its first burst at someone in a fight (0.21.18, owner: "a raider should not be able to kill you instantly without
## being able to react; only Bon and his guards should"): the burst gets a number the player's side uses to keep it
## from killing them, bar a small chance that shrinks with their armor (Player.opening_kill_chance). Later bursts,
## and Bon's and his guards', are 0 (no such limit).
static var _burst_numbers := 0
var _opening_burst := 0


func _start_burst() -> void:
	_opening_burst = 0
	if _opened_on != _target and not opening_can_kill and not (leader != null and is_instance_valid(leader) and leader.opening_can_kill):
		_burst_numbers += 1
		_opening_burst = _burst_numbers
	_opened_on = _target


## A shot that hit its target.
func _hit_target() -> void:
	var head := randf() < HEAD_HIT_CHANCE
	if _target.has_method("take_ai_hit"):
		_target.take_ai_hit(shot_damage, global_position, head, _opening_burst)
	else:
		_target.health.take_damage(shot_damage, global_position, false, head)
	if _target.health.is_dead:
		_chatter("taunt")   # (0.20.4: a smug chuckle)


## A burst's length: random, longer up close (up to burst_size + 2 inside 10 m), short taps far away.
func _burst_length(dist: float) -> int:
	if burst_size <= 1:
		return 1
	if dist < 10.0:
		return randi_range(burst_size, burst_size + 2)
	if dist < 25.0:
		return randi_range(2, burst_size + 1)
	return randi_range(1, maxi(burst_size - 1, 1))


func _fire_at_target(dist: float) -> void:
	# The bullet's path starts inside the scav's own body (excluded), not the gun barrel: with someone right
	# in its face, a ray from the barrel tip would start past them and miss. Chest height normally; from the
	# eyes when the chest's line is blocked (over a hill crest, a windowsill), since the eyes are what saw them.
	var space := get_world_3d().direct_space_state
	var chest_from := global_position + Vector3(0, 1.3, 0)
	var eyes := global_position + Vector3(0, 1.65, 0)
	var chest := _target.global_position + Vector3(0, _target.chest_height(), 0)
	var head := _target.eye_position() - Vector3(0, 0.1, 0)
	# Peeking around cover (leaning) or over a crest: aim at whatever part of them has a clear line.
	var from := chest_from
	var picked := false
	for option in [[chest_from, chest], [eyes, chest], [eyes, head]]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(option[0], option[1], 1 | Door.LAYER | BoxMap.LEAVES_LAYER, [get_rid()])).is_empty():
			from = option[0]
			chest = option[1]
			picked = true
			break
	if not picked:
		return  # no clear shot (seen over the crest, but every line hits the ground): don't shoot the hill

	var chance := hit_chance(dist)
	if dist < point_blank_range:
		chance = maxf(chance, point_blank_accuracy)
	if _target.is_sprinting():
		chance -= moving_target_penalty
	if _flinch_left > 0.0:
		chance -= flinch_accuracy_penalty
	var hit := randf() < chance

	var aim_point := chest
	if not hit:
		# Miss close enough that you see and hear it go by.
		var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.8), randf_range(-1.0, 1.0))
		aim_point = chest + offset.normalized() * randf_range(0.7, 1.5)

	var dir := (aim_point - from).normalized()
	var to := from + dir * (shoot_range + 20.0)
	# Missed shots ignore the player's hitbox so a "miss" can't land by accident.
	# (Tree tops stop the AI's shots too, 0.17.13; and shut doors, 0.21.19.)
	var mask := (1 | 2 | Door.LAYER | BoxMap.LEAVES_LAYER) if hit else (1 | Door.LAYER | BoxMap.LEAVES_LAYER)
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	query.hit_from_inside = true
	var result := space.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		if result.collider == _target:
			_hit_target()
		else:
			Effects.impact(get_tree().current_scene, end, result.normal, Color(0.85, 0.8, 0.6))
			WorldSounds.impact(get_tree().current_scene, end, result.normal)

	BoxMap.break_window_along(self, from, end, false)   # (0.18.8: its shots break glass too, and pass through)
	fired.emit(end)
	net_fired(end)  # the tracer and sound still come from the gun


## Suppressing: a shot at roughly `point` (where you were); it hits you only if you're in the way.
func _fire_at_point(point: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.65, 0)
	var aim := point + Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.6), randf_range(-0.8, 0.8))
	var to := from + (aim - from).normalized() * (shoot_range + 20.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | Door.LAYER | BoxMap.LEAVES_LAYER, [get_rid()])
	query.hit_from_inside = true
	var result := space.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		if result.collider == _target:
			_hit_target()
		else:
			Effects.impact(get_tree().current_scene, end, result.normal, Color(0.85, 0.8, 0.6))
			WorldSounds.impact(get_tree().current_scene, end, result.normal)
	fired.emit(end)
	net_fired(end)


## Just lost you: if another AI is fighting you too and nobody's suppressing yet, it pins you down and sends the
## nearest other one around to flank you. True if it's suppressing now.
func _try_suppress() -> bool:
	if not _may_suppress or _lost_sight_time > 1.0:
		return false
	_may_suppress = false   # (decided once each time it loses you)
	if randf() > suppress_chance or global_position.distance_to(_last_seen) > shoot_range * 0.8:
		return false
	var flanker: Scav = null
	var best := 40.0
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally == null or ally == self or ally.faction != faction or ally.state != State.ENGAGE or ally._target != _target:
			continue
		if ally._opening and ally._can_see:
			continue   # (it's about to open fire on you: it doesn't break off to flank first)
		if ally._suppress_left > 0.0:
			return false   # someone already is
		var d := ally.global_position.distance_to(global_position)
		if d < best and not ally.holds_position and not ally.is_wounded() and ally._cover_phase in [Cover.NONE, Cover.HOLDING]:
			best = d
			flanker = ally
	if flanker == null:
		return false
	_suppress_left = suppress_time
	_bark_left = 0.0
	_bark("push")
	var to_target := _flat(_last_seen - flanker.global_position)
	flanker._try_flank(to_target, to_target.length())
	flanker._bark_left = 0.0
	flanker._bark("flank")
	return true
## Fighting from cover: where it peeks out from, how long this peek has left, how many peeks before it re-thinks,
## and how long it's stood at the peek spot without seeing you.
var _peek_point := Vector3.INF
var _peek_left := 0.0
var _peeks_left := 0
var _advance_check_left := 0.0
var _suppress_left := 0.0
var _may_suppress := true
var _was_wounded := false
## The cover spot it's heading for is low (only hides it crouched); it's crouching there now; how crouched it looks.
var _cover_low := false
var _found_low := false
var _peek_blind := 0.0


## Chance a bullet hits at `dist` meters (before point blank, sprinting and flinch adjustments).
func hit_chance(dist: float) -> float:
	if dist <= accuracy_range:
		return lerpf(accuracy_near, accuracy_far, dist / maxf(accuracy_range, 0.01))
	return lerpf(accuracy_far, accuracy_long, clampf((dist - accuracy_range) / maxf(shoot_range - accuracy_range, 1.0), 0.0, 1.0))


## Tracer, sound and flash from the gun for a shot ending at `end` (puppets: one the server's scav fired).
func net_fired(end: Vector3) -> void:
	var muzzle_pos := muzzle.global_position
	Effects.tracer(get_tree().current_scene, muzzle_pos, end)
	Effects.sound_at(get_tree().current_scene, shot_sound, muzzle_pos, shot_volume_db, 0.06, shot_pitch, shot_unit_size)
	Hearing.gunshot(get_tree().current_scene, muzzle_pos, end, shot_volume_db)
	_muzzle_flash_time = 0.05


## Bash wind-up sound (puppets: the server's scav started one).
func net_bash_started() -> void:
	Effects.sound_at(get_tree().current_scene, BASH_SOUND, global_position, -4.0, 0.1, 0.8, 6.0, 30.0)
