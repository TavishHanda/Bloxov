extends SceneTree
## Can players snag or get stuck on the furniture hitboxes (0.22.0 `prop_boxes`, owner 2026-10-26: "i dont want players
## to just keep getting randomly stuck everywhere when they walk")? For every prop box on Bloxov Battlegrounds:
##  - how high it sits off the floor under it and how tall it stands (a low lip trips you, a box hanging off the floor
##    catches your head or feet),
##  - a player-sized capsule (the player's mask) is walked into it from 8 sides, then has to be able to walk away again;
##    "STUCK" if it can't move in any direction afterwards.
##   godot --headless -s tools/prop_snag_check.gd
const RADIUS := 0.4
const HEIGHT := 1.8
var MASK := int(OS.get_environment("SNAG_MASK")) if OS.has_environment("SNAG_MASK") else 917
const SPEED := 5.6

var _frame := 0


func _init() -> void:
	var map: Node = (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	root.add_child(map)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		_check()
		return true
	return false


func _check() -> void:
	var maps := root.find_children("*", "BoxMap", true, false)
	var props := PackedFloat32Array()
	for m: BoxMap in maps:
		props.append_array(m.prop_boxes)
	var space := root.get_world_3d().direct_space_state
	var body := CharacterBody3D.new()
	body.collision_mask = MASK
	body.collision_layer = 2
	body.floor_max_angle = deg_to_rad(46)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape.shape = cap
	shape.position.y = HEIGHT / 2
	body.add_child(shape)
	root.add_child(body)
	var low := 0
	var hanging := 0
	var stuck := 0
	var perched := 0
	var tried := 0
	for i in range(0, props.size(), 7):
		var c := Vector3(props[i], props[i + 1], props[i + 2])
		var size := Vector3(props[i + 3], props[i + 4], props[i + 5])
		var yaw := deg_to_rad(props[i + 6])
		var bottom := c.y - size.y / 2
		var top := c.y + size.y / 2
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c, c - Vector3.UP * 30.0, 1))
		var fy: float = (floor_hit.position as Vector3).y if not floor_hit.is_empty() else bottom
		if top - fy < 0.5:
			low += 1
			print("LOW     %s top %.2f above floor, %s" % [c, top - fy, size])
		if bottom - fy > 0.3 and bottom - fy < 1.8:
			hanging += 1
			print("HANGING %s bottom %.2f above floor, %s" % [c, bottom - fy, size])
		# Walk into it from 8 sides.
		var reach := maxf(size.x, size.z) / 2 + RADIUS + 0.6
		for k in 8:
			var a := TAU * k / 8.0 + yaw
			var start := Vector3(c.x + cos(a) * reach, fy + 0.05, c.z + sin(a) * reach)
			var at := space.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3.UP * 1.0, start - Vector3.UP * 1.5, 1))
			if at.is_empty():
				continue
			start.y = (at.position as Vector3).y + 0.02
			body.global_position = start
			if body.test_move(body.global_transform, Vector3.ZERO):
				continue   # (no room to stand there to begin with)
			tried += 1
			var dir := Vector3(c.x - start.x, 0, c.z - start.z).normalized()
			for f in 30:
				body.velocity = dir * SPEED + Vector3.DOWN * 2.0
				body.move_and_slide()
			# Free if it can walk away at least 10 cm some way, or jump out (perched on two boxes' edges).
			var free := false
			var moves: Array[Vector3] = [Vector3.UP * 0.5]
			for d in 8:
				moves.append(Vector3(cos(TAU * d / 8.0), 0, sin(TAU * d / 8.0)) * 0.3)
			var walks := false
			for mv in moves:
				var hit := KinematicCollision3D.new()
				if not body.test_move(body.global_transform, mv, hit) or hit.get_travel().length() > 0.1:
					free = true
					walks = walks or mv.y == 0.0
			if free and not walks:
				perched += 1
				print("PERCHED walking into %s from %s, ended at %s (can only jump out)" % [c, start, body.global_position])
			if not free:
				stuck += 1
				var why := []
				for d in 4:
					var hit := KinematicCollision3D.new()
					var b := TAU * d / 4.0
					if body.test_move(body.global_transform, Vector3(cos(b), 0, sin(b)) * 0.3, hit):
						var o := hit.get_collider() as CollisionObject3D
						why.append("%s(%d) n%s d%.2f" % [o.name if o else "?", o.collision_layer if o else 0, hit.get_normal().snapped(Vector3.ONE * 0.1), hit.get_travel().length()])
				print("STUCK   walking into %s from %s, ended at %s: %s" % [c, start, body.global_position, why])
	print("PROP SNAG CHECK: %d prop boxes, %d walk-ins, %d low (under 0.5 m), %d hanging, %d stuck, %d only by jumping" % [props.size() / 7, tried, low, hanging, stuck, perched])
