extends SceneTree
## Checks every ladder on the maps faces the right way (0.35.27): the floor it leads up to must be on its
## into() side (the side it leans on), not behind the climber. Run: godot --headless -s tools/ladder_audit.gd

const MAPS := ["res://scenes/maps/old_bloxov.tscn", "res://scenes/maps/riptide.tscn"]

var _bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in MAPS:
		var map: Node = (load(path) as PackedScene).instantiate()
		root.add_child(map)
		for i in 4:
			await physics_frame
		var space := root.get_world_3d().direct_space_state
		for ladder in map.find_children("*", "Ladder", true, false):
			var hits := []
			for side in [1.0, -1.0]:
				var p: Vector3 = ladder.global_position + ladder.into() * side * 0.9
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * (ladder.height + 0.6), p + Vector3.UP * (ladder.height - 0.4))
				q.collision_mask = 1
				hits.append(not space.intersect_ray(q).is_empty())
			# (Floor both sides is a hatch in a ceiling; floor only behind the climber is a ladder put on backwards.)
			var ok: bool = hits[0]
			if not ok:
				_bad += 1
			print("%s %s/%s (%s): floor on the lean side %s, behind the climber %s" % ["OK " if ok else "BAD", path.get_file(), ladder.name, ladder.get_meta(&"place", ""), hits[0], hits[1]])
		map.free()
	print("LADDER AUDIT: %s" % ("PASSED" if _bad == 0 else "%d BAD" % _bad))
	quit(1 if _bad else 0)
