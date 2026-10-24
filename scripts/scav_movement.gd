extends "res://scripts/scav_senses.gd"
## How the AI gets around: navigation paths, patrols and trips, following a leader, hunting, crouching,
## getting unstuck, footsteps, and the level of detail for far, calm AI.

## How far away you can hear an AI's footsteps and its callouts (0.12.32, owner: you could hear every AI on the map
## walking, "like 30 crunching steps"). Gunshots still carry across the map.
const STEP_HEAR_RANGE := 30.0
## Current navigation path (to _path_goal) and the waypoint it's walking to.
var _path := PackedVector3Array()
var _ground_check_left := randf() * 0.5
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
## Where an idle scav is patrolling to (only used while _wander_dir isn't zero), and for how long.
var _wander_point := Vector3.ZERO
var _patrol_time := 0.0
## The loot container this patrol leg heads to (null = just a spot), whether it's jogging, and how long it
## has left searching a container.
var _patrol_container: Node3D = null
var _patrol_jog := false
var _knockback := Vector3.ZERO
var _wander_dir := Vector3.ZERO
var _wander_time := 0.0
var _cover_cooldown_left := 0.0
var home_edge := 0.0
var follow_offset := Vector3(2.0, 0.0, 1.5)
var _side := 1.0
var _stride_left := 0.0
const NET_SNEAK := 8
const NET_CROUCH := 32
## Crouched behind low cover (a tent, a car, a low wall): the model and hitboxes shrink to this fraction of its
## height (0.12.10).
const CROUCH_HEIGHT := 0.6


## Standing on someone's head (another AI or a player): steps off it. Two AI that ended up in one spot used to
## stack, the top one's head stuck in the ceiling for good (0.12.35, owner's screenshot).
## (Checked with a ray down from its feet, not just what it bumped: with its head wedged in a ceiling it may not
## report the body under it.)
func _slide_off_heads() -> void:
	var feet := global_position + Vector3(0, 0.15, 0)
	var query := PhysicsRayQueryParameters3D.create(feet, feet + Vector3(0, -0.45, 0), 2 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var other := hit.get("collider") as Node3D
	for i in get_slide_collision_count():
		var bump := get_slide_collision(i)
		if bump.get_collider() is CharacterBody3D and bump.get_normal().y > 0.5:
			other = bump.get_collider() as Node3D
	if other == null or other == self or not other is PhysicsBody3D:
		return
	# Drops through it to the floor (even wedged under a ceiling) and steps aside; they collide again in a moment.
	var away := _flat(global_position - other.global_position)
	away = away.normalized() if away.length() > 0.05 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	_knockback = away * 4.0
	if get_collision_exceptions().has(other):
		return   # (already passes through it: Bon and his guards)
	add_collision_exception_with(other)
	get_tree().create_timer(1.0, false, true).timeout.connect(func() -> void:
		if is_instance_valid(other) and is_inside_tree():
			remove_collision_exception_with(other))


## Trying to move but not getting anywhere (pressed against a wall, sliding along it) for a while: gives up on
## where it was going (0.12.8, owner: one hugged a building for 20 seconds).
var _unstick_left := 0.0
var _unstick_dir := Vector3.ZERO

func _check_stuck(delta: float, desired: Vector3) -> void:
	var want := _flat(desired)
	if want.length() < 0.5:
		_stuck_time = 0.0
		return
	var progress := _flat(get_real_velocity() / _lod_scale).dot(want.normalized())
	if progress < want.length() * 0.3:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time < 1.5:
		return
	_stuck_time = 0.0
	_path.clear()
	_side = -_side
	# A short step to the side first (0.12.36: Bon's guards got caught for good on a ramp's edge and a corner on
	# the way to the trips' destinations, re-trying the same path forever).
	_unstick_left = 0.7
	_unstick_dir = want.normalized().rotated(Vector3.UP, PI / 2.0 * _side)
	if _cover_phase in [Cover.MOVING, Cover.FLANKING, Cover.PEEKING]:
		_cover_phase = Cover.NONE
		_cover_cooldown_left = cover_cooldown
	elif state == State.IDLE and leader != null:
		_follow_direct_left = 4.0
	elif state == State.IDLE:
		_wander_dir = Vector3.ZERO
		_wander_time = 0.0
	elif state == State.INVESTIGATE:
		_set_state(State.SEARCH)
	elif state == State.ENGAGE and not _can_see:
		# (0.15.28, owner: lost you up close and got stuck on the way: it still hunts for you, not a quick look)
		_set_state(State.SEARCH)
		_start_hunt()


## Scav footsteps, so you can hear them coming.
func _update_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if (not puppet and not is_on_floor()) or speed < 0.5:
		return
	_stride_left -= speed * delta
	if _stride_left <= 0.0:
		_stride_left = 1.4
		if _sneaking() or _net_flags & NET_SNEAK:
			return  # sneaking up: no footstep sounds
		Surfaces.step(self, -6.0, true, 0.9, 2.5, STEP_HEAR_RANGE)


## Lost you mid-fight: start hunting around where it last saw you.
func _start_hunt() -> void:
	_hunting = true
	_hunt_point = Vector3.INF
	_hunt_pause = 0.0
	_hunted.clear()


## Hunting: walk to a spot near where it lost you, look around there a moment, pick the next.
func _hunt(delta: float) -> Vector3:
	if _hunt_point == Vector3.INF or _hunt_pause > 0.0:
		rotation.y += delta * 1.5 * _side
		_hunt_pause -= delta
		if _hunt_pause <= 0.0:
			_hunt_point = _pick_hunt_point()
			if _hunt_point == Vector3.INF:
				_hunt_pause = 1.0
		return Vector3.ZERO
	var move := _path_velocity(_hunt_point, move_speed * investigate_speed * 1.2)
	_face(move, delta, 5.0)
	if _arrived(_hunt_point):
		_hunted.append(_hunt_point)
		_hunt_point = Vector3.INF
		_hunt_pause = randf_range(1.5, 2.5)
	return move


## The next place to check: a walkable spot near where it lost you that it hasn't checked, isn't where another
## searcher is heading, and is preferably indoors (something overhead) where you'd hide.
func _pick_hunt_point() -> Vector3:
	var space := get_world_3d().direct_space_state
	var others: Array[Vector3] = []
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally._hunting and ally._hunt_point != Vector3.INF:
			others.append(ally._hunt_point)
	var best := Vector3.INF
	var best_score := -INF
	for i in 10:
		var offset := Vector3(hunt_radius * sqrt(randf()), 0, 0).rotated(Vector3.UP, randf() * TAU)
		var spot := AINav.closest(self, _last_seen + offset)
		if spot == Vector3.ZERO or _flat(spot - global_position).length() < 3.0:
			continue
		if stays_home and not _near_home(spot):
			continue
		var score := randf() * 2.0
		var up := spot + Vector3(0, 1.0, 0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(up, up + Vector3(0, 8, 0), 1)).is_empty():
			score += 5.0   # indoors
		for p in others + _hunted:
			if _flat(p - spot).length() < 6.0:
				score -= 8.0
		if score > best_score:
			best_score = score
			best = spot
	return best


## Crouching behind low cover: shorter model and hitboxes (puppets follow the server's flag).
func _update_crouch(delta: float) -> void:
	var want := (_net_flags & NET_CROUCH) != 0 if puppet else _crouched
	var amount := move_toward(_crouch_amount, 1.0 if want else 0.0, delta * 5.0)
	if amount == _crouch_amount:
		return
	_crouch_amount = amount
	var height := lerpf(1.0, CROUCH_HEIGHT, amount)
	model.scale.y = height
	var body := $BodyShape as CollisionShape3D
	(body.shape as BoxShape3D).size = Vector3(_body_size.x, _body_size.y * height, _body_size.z)
	body.position = _body_rest * height
	($HeadShape as CollisionShape3D).position = _head_rest * height
var _dodge_dir := 0.0


## In a fight, friends keep a step apart instead of standing inside each other (Bon's guards can walk through him
## on patrol, so they don't box him in): a gentle push away from anyone closer than 1.5 m (0.12.29).
var _apart := Vector3.ZERO
var _apart_check_left := 0.0
func _separation(delta: float) -> Vector3:
	_apart_check_left -= delta
	if _apart_check_left <= 0.0:
		_apart_check_left = 0.2
		_apart = Vector3.ZERO
		for node in RaidScope.nodes(self, &"enemies"):
			var other := node as Scav
			if other == null or other == self or other.state == State.DEAD:
				continue
			var away := _flat(global_position - other.global_position)
			var d := away.length()
			if d < 1.5:
				_apart += (away / d if d > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)) * (1.5 - d) * 2.0
	return _apart


## Raiders closing in on where they think you are (investigating, or chasing without seeing you) move quietly.
func _sneaking() -> bool:
	if sneak_range <= 0.0:
		return false
	var spot := Vector3.INF
	if state == State.INVESTIGATE:
		spot = _goal
	elif state == State.ENGAGE and not _can_see and _cover_phase == Cover.NONE:
		spot = _last_seen
	return spot != Vector3.INF and _flat(spot - global_position).length() < sneak_range


## Velocity toward `goal` along a navigation path (around buildings and crates). Re-paths when the goal moves
## more than a meter or every second. If the goal can't be reached, the path ends at the closest point it can.
## Without a navigation map (e.g. before it's built) it walks straight, sliding off walls.
func _path_velocity(goal: Vector3, speed: float) -> Vector3:
	_repath_left -= _tick_delta
	if _path.is_empty() or _flat(goal - _path_goal).length() > 1.0 or _repath_left <= 0.0:
		_path_goal = goal
		_repath_left = 1.0
		_path = AINav.path(self, global_position, goal)
		_path_index = 1
	if _path.size() < 2:
		var direct := _flat(goal - global_position)
		if direct.length() < 0.1:
			return Vector3.ZERO
		var straight := direct.normalized() * speed
		return straight.rotated(Vector3.UP, PI * 0.4 * _side) if is_on_wall() else straight
	while _path_index < _path.size() - 1 and _flat(_path[_path_index] - global_position).length() < 0.6:
		_path_index += 1
	var to_next := _flat(_path[_path_index] - global_position)
	if to_next.length() < 0.1:
		return Vector3.ZERO
	return to_next.normalized() * speed


## Reached `goal` (or the closest reachable point to it, if the path ended short).
func _arrived(goal: Vector3) -> bool:
	if _flat(goal - global_position).length() < 1.2:
		return true
	return (not _path.is_empty() and _flat(goal - _path_goal).length() <= 1.0
		and _flat(_path[_path.size() - 1] - global_position).length() < 1.2)


## Short fight moves (a dodge, backing off): don't push into a wall; try the other side instead.
func _clear_of_walls(move: Vector3) -> Vector3:
	if move.length() < 0.1 or not _blocked(move):
		return move
	_dodge_dir = -_dodge_dir
	var flipped := Vector3(-move.x, 0.0, -move.z)
	return Vector3.ZERO if _blocked(flipped) else flipped


func _blocked(move: Vector3) -> bool:
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + move.normalized() * 1.0, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Patrolling while unaware: walk to a destination in its area (`home_radius`; the whole map for a roamer), mostly
## loot spots, which are in and around buildings, sometimes anywhere reachable. Pause there, then pick the next one.
## `_wander_dir` is zero while pausing (`_wander_time` counts the pause down).
func _wander(delta: float) -> Vector3:
	# A duo partner sticks with its leader instead of picking its own patrol.
	if leader != null and is_instance_valid(leader) and leader.state != State.DEAD:
		var spot := leader.global_position + leader.global_basis.x * follow_offset.x + leader.global_basis.z * follow_offset.z
		_follow_direct_left -= delta
		if _follow_direct_left > 0.0:
			spot = leader.global_position   # (stuck getting to its own spot: just follow the leader's steps)
		if _flat(spot - global_position).length() < 1.5:
			_wander_dir = Vector3.ZERO
			return Vector3.ZERO
		_wander_dir = _flat(spot - global_position).normalized()
		# (fallen behind: jogs to catch up)
		var catch_up := leader._patrol_jog or _flat(spot - global_position).length() > 8.0
		var follow := _path_velocity(spot, move_speed * (jog_speed if catch_up else patrol_speed) * 1.1)
		_face(follow, delta, 4.0)
		return follow
	if _wander_dir == Vector3.ZERO:
		_wander_time -= delta
		_looting_left -= delta
		if _looting_left > 0.0 and is_instance_valid(_patrol_container):
			_face(_flat(_patrol_container.global_position - global_position), delta, 4.0)
		if _wander_time > 0.0:
			return Vector3.ZERO
		_wander_point = _pick_patrol_point()
		_wander_dir = _flat(_wander_point - global_position).normalized()
		_patrol_time = 0.0
		if _wander_dir == Vector3.ZERO:
			_wander_time = 1.0
		return Vector3.ZERO
	# Leading guards (Bon): waits for one that's fallen far behind, a few seconds at most each time (0.12.36: on
	# trips out of the town hall they trailed 50 m behind).
	if _has_followers:
		if not _follower_behind(14.0):
			_waited = 0.0
		elif _waited < 6.0:
			_waited += delta
			return Vector3.ZERO
	_patrol_time += delta
	if _arrived(_wander_point) or _patrol_time > (90.0 if _trip_point != Vector3.INF else 45.0):
		_wander_dir = Vector3.ZERO
		if is_instance_valid(_patrol_container) and _flat(_patrol_container.global_position - global_position).length() < 3.5:
			# At a container: search it for a while, like a player would.
			_looting_left = randf_range(loot_time_min, loot_time_max)
			_wander_time = _looting_left + 0.5
		else:
			_wander_time = randf_range(patrol_pause_min, patrol_pause_max)
		return Vector3.ZERO
	var move := _path_velocity(_wander_point, move_speed * (jog_speed if _patrol_jog else patrol_speed))
	_face(move, delta, 4.0)
	return move


var _waited := 0.0
var _has_followers := false

## A follower of this one is more than `dist` meters away (not one that's in a fight or dead).
func _follower_behind(dist: float) -> bool:
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if (other != null and other.leader == self and other.state == State.IDLE
				and _flat(other.global_position - global_position).length() > dist):
			return true
	return false


## Starts following `new_leader` (a boss's guard, a Raider's partner). Followers and their leader walk through each
## other (0.12.20: Bon's guards boxed him into a corner of the town hall and none of them could move).
func follow(new_leader: Scav) -> void:
	leader = new_leader
	new_leader._has_followers = true
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other != null and other != self and (other == new_leader or other.leader == new_leader):
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)


var _trips_left := -1
var _alive_time := 0.0
var _next_trip_at := 0.0
## Where its current trip goes (INF: at home). Its guards check it too.
var _trip_point := Vector3.INF

func _pick_patrol_point() -> Vector3:
	# (not the ones behind key doors, 0.14.0: the AI can't get in there)
	var spots := RaidScope.nodes(self, &"loot_containers").filter(func(c: Node) -> bool: return not c.has_meta("locked"))
	if _trip_point != Vector3.INF and _in_home(global_position):
		_trip_point = Vector3.INF   # back from its trip
	if excursions > 0 and home_radius > 0.0:
		if _trips_left < 0:
			_trips_left = excursions
			_next_trip_at = randf_range(60.0, 200.0)
		if _trips_left > 0 and _alive_time >= _next_trip_at and _trip_point == Vector3.INF:
			var trip := _pick_trip(spots)
			if trip != Vector3.ZERO:
				_trips_left -= 1
				if randf() > second_excursion_chance:
					_trips_left = 0
				_next_trip_at = _alive_time + randf_range(150.0, 250.0)
				_trip_point = trip
				_patrol_jog = false
				return trip
	if home_radius > 0.0:
		spots = spots.filter(func(c: Node) -> bool: return _in_home((c as Node3D).global_position))
		# Out of its area (after a fight): head straight back in.
		if not _in_home(global_position):
			_patrol_container = null
			var back := AINav.closest(self, home_center)
			if back != Vector3.ZERO:
				return back
	if not indoor_rooms.is_empty() and _trip_point == Vector3.INF:
		var stop := _pick_room(spots) if randf() < indoor_patrol else _step_out()
		if stop != Vector3.ZERO:
			return stop
	_patrol_jog = randf() < jog_chance
	# Open-ground stops prefer a spot next to a wall or other cover (0.12.7, owner: patrol behind cover, not out
	# in the open where anyone on a hill can pick them off).
	var fallback := Vector3.INF
	for attempt in 8:
		var spot: Vector3
		_patrol_container = null
		# (Loot spots, inside buildings, 45% of the time: 0.12.24, owner: patrol a lot, not go for loot.)
		if not spots.is_empty() and randf() < 0.45:
			_patrol_container = spots.pick_random() as Node3D
			# Walk up next to it (the closest walkable point to the container).
			spot = AINav.closest(self, _patrol_container.global_position)
		elif home_radius > 0.0 and randf() < outside_patrol:
			# Just outside its area (round its building): allowed though it's past the edge.
			var out := Vector3(randf_range(home_radius, home_radius + 12.0), 0, 0).rotated(Vector3.UP, randf() * TAU)
			spot = AINav.closest(self, home_center + out)
			if spot != Vector3.ZERO and _flat(spot - global_position).length() > 6.0:
				return spot
			continue
		elif home_radius > 0.0:
			var offset := Vector3(home_radius * lerpf(home_edge, 1.0, sqrt(randf())), 0, 0).rotated(Vector3.UP, randf() * TAU)
			spot = AINav.closest(self, home_center + offset)
		else:
			spot = AINav.random_point(self)
		if spot != Vector3.ZERO and _flat(spot - global_position).length() > 6.0 and (home_radius <= 0.0 or _in_home(spot)):
			if (_patrol_container != null or _has_cover_at(spot)) and not _patrol_taken(spot):
				return spot
			if fallback == Vector3.INF:
				fallback = spot
	_patrol_container = null
	if fallback != Vector3.INF:
		return fallback
	# No navigation map yet: somewhere a few meters ahead.
	return global_position + _flat(-global_basis.z).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) * 6.0


## An indoor guard's next stop in its building (0.20.14): another room, or now and then a loot spot in the building
## (any floor: up the stairs too). It walks. ZERO if there's nowhere to go.
func _pick_room(spots: Array[Node]) -> Vector3:
	_patrol_jog = false
	_patrol_container = null
	if randf() < 0.35:
		var inside := spots.filter(func(c: Node) -> bool:
			var at := (c as Node3D).global_position
			return indoor_rooms.any(func(r: Vector3) -> bool: return _flat(at - r).length() < 6.0 and absf(at.y - r.y) < 9.0))
		if not inside.is_empty():
			_patrol_container = inside.pick_random() as Node3D
			var at := AINav.closest(self, _patrol_container.global_position)
			if at != Vector3.ZERO:
				return at
			_patrol_container = null
	var rooms := indoor_rooms.duplicate()
	rooms.shuffle()
	for room: Vector3 in rooms:
		if _flat(room - global_position).length() < 3.0 or _room_taken(room):
			continue
		var at := AINav.closest(self, room)
		if at != Vector3.ZERO:
			return at
	# (one room, or the others taken: a few steps round this one)
	var near := AINav.closest(self, rooms[0] + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
	return near if near != Vector3.ZERO and _flat(near - rooms[0]).length() < 3.0 else Vector3.ZERO


## An indoor guard's stop outside: round its building, a few meters out (it comes back in after).
func _step_out() -> Vector3:
	_patrol_container = null
	_patrol_jog = false
	var middle := Vector3.ZERO
	for room in indoor_rooms:
		middle += room
	middle /= indoor_rooms.size()
	var reach := 0.0
	for room in indoor_rooms:
		reach = maxf(reach, _flat(room - middle).length())
	var at := AINav.closest(self, middle + Vector3(reach + randf_range(6.0, 12.0), 0, 0).rotated(Vector3.UP, randf() * TAU))
	return at if at != Vector3.ZERO and (home_radius <= 0.0 or _in_home(at)) else Vector3.ZERO


## Another AI is already standing in or heading for that room spot.
func _room_taken(room: Vector3) -> bool:
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other != null and other != self and other.state == State.IDLE and (_flat(other.global_position - room).length() < 2.0
				or (other._wander_dir != Vector3.ZERO and _flat(other._wander_point - room).length() < 2.0)):
			return true
	return false


## Another patrolling AI (not its own group) is already heading for somewhere near `spot` (owner, 0.15.16: four AI
## walking the same path round the depot). Picking somewhere else keeps them spread out.
func _patrol_taken(spot: Vector3) -> bool:
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if (other != null and other != self and other.leader == null and other != leader and other.state == State.IDLE
				and other._wander_dir != Vector3.ZERO and _flat(other._wander_point - spot).length() < 12.0):
			return true
	return false


## A trip's destination: a loot spot in another building (not in its area) within excursion_range, the bank half
## the time when there is one. ZERO if none.
func _pick_trip(spots: Array[Node]) -> Vector3:
	var away := spots.filter(func(c: Node) -> bool:
		var at := (c as Node3D).global_position
		return not _in_home(at) and _flat(at - home_center).length() <= excursion_range)
	if away.is_empty():
		return Vector3.ZERO
	var bank := away.filter(func(c: Node) -> bool: return c.get_meta("place", "") == "Bank")
	_patrol_container = ((bank if not bank.is_empty() and randf() < 0.5 else away).pick_random()) as Node3D
	return AINav.closest(self, _patrol_container.global_position)


## Something solid (a wall, crate, car) right next to `spot`, about chest high.
func _has_cover_at(spot: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := spot + Vector3(0, 1.0, 0)
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 8.0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 2.5, 1)).is_empty():
			return true
	return false


## A sniper on its perch, unaware: slowly sweeps its view one way, then the other, with the odd pause.
func _scan(delta: float) -> Vector3:
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = randf_range(3.0, 7.0)
		_scan_dir = [-1.0, 0.0, 1.0].pick_random()
	rotation.y += delta * 0.35 * _scan_dir
	return Vector3.ZERO
var _scan_dir := 1.0
var _stuck_time := 0.0
var _follow_direct_left := 0.0
var _hunt_point := Vector3.INF
var _hunt_pause := 0.0
var _hunted: Array[Vector3] = []
var _crouched := false
var _crouch_amount := 0.0
var _body_rest := Vector3.ZERO
var _body_size := Vector3.ONE
var _head_rest := Vector3.ZERO


## Level of detail (0.14.4, health check: 32 AI took ~4 ms of every frame on a fast desktop, too much for phones,
## and the server runs every raid in one process). A calm AI (patrolling, unaware) that's farther from every player
## than it can see thinks and moves every LOD_FRAMES frames instead of every frame, catching up the time it skipped
## in one step. Nothing it does changes: it can't spot anyone from there anyway, and noises, shots and calls for help
## still reach it at once (they change its state, which brings it straight back to every frame). Between its ticks
## the body glides along the step it just took, so it moves as smoothly as before and its hitbox is where it's drawn.
const LOD_FRAMES := 6
## Players this close to it (beyond what it can see) keep it at full rate.
const LOD_MARGIN := 15.0
## (Tests switch it off to compare.)
static var lod_enabled := true
var _lod_far := false
var _lod_check_left := randf() * 0.5
var _lod_wait := randi() % LOD_FRAMES   # (spread over the frames so they don't all tick on the same one)
var _lod_delta := 0.0
## How many frames this tick stands for (1 at full rate).
var _lod_scale := 1.0
## The time this tick covers (more than one frame's on a slow tick).
var _tick_delta := 1.0 / 60.0
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _glide_yaw_from := 0.0
var _glide_yaw_to := 0.0
var _glide_frame := 0


## True to skip this physics frame (its time is saved up for the next slow tick).
func _lod_skip(delta: float) -> bool:
	_lod_check_left -= delta
	if _lod_check_left <= 0.0:
		_lod_check_left = 0.5
		_lod_far = _far_from_players()
	if not lod_enabled or not _lod_far or state != State.IDLE or _cover_phase == Cover.HEALING:
		return false
	_lod_wait -= 1
	if _lod_wait <= 0:
		_lod_wait = LOD_FRAMES
		return false
	_lod_delta += delta
	if _glide_frame > 0 and _glide_frame < LOD_FRAMES:
		_glide_frame += 1
		_glide_at(float(_glide_frame) / LOD_FRAMES)
	return true


func _far_from_players() -> bool:
	var range_sq := (sight_range + LOD_MARGIN) * (sight_range + LOD_MARGIN)
	for node in RaidScope.nodes(self, &"player"):
		if (node as Node3D).global_position.distance_squared_to(global_position) < range_sq:
			return false
	return true


## After a slow tick's move: back to where it started, then a share of the way each frame until the next tick.
func _lod_glide_start(from: Vector3, yaw_from: float) -> void:
	_glide_from = from
	_glide_to = global_position
	_glide_yaw_from = yaw_from
	_glide_yaw_to = rotation.y
	_glide_frame = 1
	_glide_at(1.0 / LOD_FRAMES)


## The rest of the way at once (before it thinks or moves again).
func _lod_glide_finish() -> void:
	if _glide_frame > 0:
		_glide_frame = 0
		_glide_at(1.0)


func _glide_at(t: float) -> void:
	global_position = _glide_from.lerp(_glide_to, t)
	rotation.y = lerp_angle(_glide_yaw_from, _glide_yaw_to, t)
