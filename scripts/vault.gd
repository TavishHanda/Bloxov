class_name Vault
extends RefCounted
## Vaulting over low cover and climbing onto ledges (0.13.0), shared by players and the AI (0.13.1).
## `plan()` looks straight ahead of a body for something waist-to-chest high and works out the move;
## `position_at()` walks it. Heights are from the body's feet (its origin).

## Lower than this is a step or a jump, not a vault.
const MIN_HEIGHT := 0.5
## Up to this, thin cover (fences, sandbags, low walls) is vaulted: over and down the other side.
const VAULT_HEIGHT := 1.25
## Up to this (chest high), ledges and wide tops are climbed onto.
const MANTLE_HEIGHT := 1.7
## Cover thinner than this is vaulted over (thicker: climbed onto). The AI's navigation crosses the same pieces.
const MAX_THICKNESS := 0.9
## Of a vault's time, the share spent getting up and over the top (the rest is down the far side).
const SPLIT := 0.6
## How far behind something low (a crate under a window) cover further back still counts.
const BEHIND := 1.2


## The move for `body` heading `forward` (flat), or {} if there's nothing to vault or no room:
## {"path": [start, over the top, end], "over": true = vaulted over (false = climbed onto), "crouch_after": only
## fits crouched at the end, "duck": squeezing through a low gap (a window)}. `reach` = how far past the body cover still counts; `mantle_height` = VAULT_HEIGHT
## means vault-overs only.
static func plan(body: CollisionObject3D, forward: Vector3, radius: float, stand_height: float, crouch_height: float,
		reach: float, mantle_height := MANTLE_HEIGHT) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	# Something in front from knee to chest height (0.14.14: raised cover too, like a ramp's side). Nearest first;
	# what's further back is tried too when the near thing can't be vaulted over (0.14.22, owner: a crate under a
	# window used to block the window: you climbed onto the crate, or nothing).
	var hits := []
	for h: float in [0.3, 0.65, 1.0, 1.35]:
		var from := feet + Vector3(0, h, 0)
		var probe := _ray(body, space, from, from + forward * (radius + reach + BEHIND))
		# (a slope you can walk up, like a ramp ahead, isn't cover: 0.14.19, vaulting "over" a ramp dropped you
		# through it to the floor below)
		if probe.is_empty() or probe["normal"].y >= 0.7:
			continue
		probe["distance"] = Vector2(probe["position"].x - feet.x, probe["position"].z - feet.z).length()
		hits.append(probe)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	if hits.is_empty() or hits[0]["distance"] > radius + reach:
		return {}
	var climb := {}
	var tried := -INF
	for hit: Dictionary in hits:
		if hit["distance"] < tried + 0.05:
			continue   # (the same face, seen from another height)
		tried = hit["distance"]
		var move := _plan_at(body, space, feet, forward, hit, radius, stand_height, crouch_height, mantle_height)
		if not move.is_empty():
			if move["over"]:
				return move
			if climb.is_empty():
				climb = move
	return climb


## plan() for one thing in front (`hit`, a ray hit on its face).
static func _plan_at(body: CollisionObject3D, space: PhysicsDirectSpaceState3D, feet: Vector3, forward: Vector3,
		hit: Dictionary, radius: float, stand_height: float, crouch_height: float, mantle_height: float) -> Dictionary:
	# Faced fairly head-on...
	var into := -Vector3(hit["normal"].x, 0.0, hit["normal"].z).normalized()
	if into.dot(forward) < 0.6:
		return {}
	var wall: Vector3 = hit["position"]
	wall.y = feet.y
	# ...with a top in reach (and not still wall above it). Looked for just past the face and a bit further in, the
	# highest one counting (0.14.14: a 15 cm fence's top was missed by looking 15 cm in).
	var top: Variant = null
	for depth: float in [0.06, 0.15, 0.3]:
		var t: Variant = _top(body, space, wall + into * depth, feet.y + mantle_height + 0.1, feet.y + 0.3)
		if t != null and (top == null or t.y > top.y):
			top = t
	if top == null:
		return {}
	var height: float = top.y - feet.y
	if height < MIN_HEIGHT or height > mantle_height:
		return {}
	var above_top := Vector3(feet.x, top.y + 0.25, feet.z)
	var to_wall := Vector2(wall.x - feet.x, wall.z - feet.z).length()
	if not _ray(body, space, above_top, above_top + forward * (to_wall + 0.3)).is_empty():
		return {}
	# Windows (0.13.10, owner): the gap over a sill is lower than a crouch, so squeeze through ducked; and
	# slide sideways a little to fit the gap if you're not dead centre.
	var along := into.cross(Vector3.UP)
	for shift: float in [0.0, 0.2, -0.2, 0.4, -0.4]:
		var at := wall + along * shift
		var over := Vector3(at.x, top.y + 0.05, at.z) + into * 0.15
		var duck := false
		if not _fits(body, over, radius, crouch_height):
			if not _fits(body, over, radius, radius * 2.0):
				continue
			duck = true
		var move := _finish(body, space, feet, over, at, into, top, height, radius, stand_height, crouch_height, mantle_height)
		if not move.is_empty():
			move["duck"] = duck
			return move
	return {}


## The rest of plan(): where it ends (over and down, or on top) and whether there's room there.
static func _finish(body: CollisionObject3D, space: PhysicsDirectSpaceState3D, feet: Vector3, over: Vector3,
		wall: Vector3, into: Vector3, top: Vector3, height: float, radius: float, stand_height: float,
		crouch_height: float, mantle_height: float) -> Dictionary:
	# Thin enough to go over: find where the top ends, then land on the ground past it.
	var end: Variant = null
	if height <= VAULT_HEIGHT:
		var d := 0.3
		while d <= MAX_THICKNESS + 0.15 and end == null:
			var below: Variant = _top(body, space, wall + into * d, top.y + 0.1, top.y - 3.0)
			if below == null or below.y < top.y - 0.3:
				var far := wall + into * (d + radius + 0.1)
				var ground: Variant = _top(body, space, far, top.y + 0.1, top.y - 3.0)
				end = Vector3(far.x, top.y if ground == null else ground.y + 0.02, far.z)
			d += 0.15
	# No room on the far side (cover against a wall, a ramp's side): climb onto it instead, if that's allowed.
	if end != null and not _fits(body, end, radius, crouch_height):
		end = null
	var vault_over := end != null
	# Otherwise climb onto it.
	if not vault_over:
		if height > mantle_height or mantle_height <= VAULT_HEIGHT:
			return {}
		var on_top := wall + into * (radius + 0.15)
		end = Vector3(on_top.x, top.y + 0.02, on_top.z)
	if BoxMap.inside_solid(body, end + Vector3.UP * 0.3):
		return {}
	var crouch_after := false
	if not _fits(body, end, radius, stand_height):
		if not _fits(body, end, radius, crouch_height):
			return {}
		crouch_after = true
	return {"path": PackedVector3Array([feet, over, end]), "over": vault_over, "crouch_after": crouch_after}


## Where the body is `t` (0-1) of the way through a vault's path.
static func position_at(path: PackedVector3Array, t: float) -> Vector3:
	var from := path[0]
	var to := path[1]
	var k := t / SPLIT
	if t >= SPLIT:
		from = path[1]
		to = path[2]
		k = (t - SPLIT) / (1.0 - SPLIT)
	k = clampf(k, 0.0, 1.0)
	return Vector3(lerpf(from.x, to.x, k), lerpf(from.y, to.y, smoothstep(0.0, 1.0, k)), lerpf(from.z, to.z, k))


static func _ray(body: CollisionObject3D, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [body.get_rid()]))
	# (0.19.4, owner: vaulting into a dirt bank got you stuck in it: from inside, the bank's skin looked like a top
	# to land on. Map collision is solid from both sides, so only its outsides count here.)
	if not hit.is_empty() and BoxMap.hit_from_behind(hit, (to - from).normalized()):
		return {}
	return hit


## The walkable top straight down at `at` between heights `from_y` and `to_y` (null = none).
static func _top(body: CollisionObject3D, space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float, to_y: float) -> Variant:
	var hit := _ray(body, space, Vector3(at.x, from_y, at.z), Vector3(at.x, to_y, at.z))
	if hit.is_empty() or hit["normal"].y < 0.7:
		return null
	return hit["position"]


## Room for the body (`height` tall) standing at `feet`: no world, player or AI in the way.
static func _fits(body: CollisionObject3D, feet: Vector3, radius: float, height: float) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), feet + Vector3(0, height * 0.5 + 0.05, 0))
	query.collision_mask = 1 | 2 | 4 | BoxMap.BARS_LAYER   # (0.18.3: barred windows can't be climbed through)
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
