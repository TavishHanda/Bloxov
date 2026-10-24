extends SceneTree
# Renders eye-level views of the dirt banks and crater rims (checking how they sit in the ground).
# xvfb-run -a godot --rendering-driver opengl3 -s tools/hump_views.gd -- out=/tmp/h x,z[,dist,yaw] ...  (map metres)
var out := "/tmp/h"
var spots := []
var cam: Camera3D
var frame := 0
var idx := -1

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		else: spots.append(a.split(","))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	for c in main.get_children():
		if not (String(c.name) in ["WorldEnvironment", "Sun", "Clouds"]):
			main.remove_child(c); c.free()
	var map: Node = (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	for c in map.get_children():
		if String(c.name) in ["Level", "Loot", "Extracts"]:
			map.remove_child(c); main.add_child(c)
	map.free()
	root.add_child(main)
	cam = Camera3D.new(); cam.fov = 70; cam.far = 900
	main.add_child(cam); cam.current = true
	root.size = Vector2i(1280, 720)

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -100, z), 1)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0

func _process(_d: float) -> bool:
	frame += 1
	if frame < 10:
		return false
	if frame % 12 == 0:
		if idx >= 0:
			root.get_texture().get_image().save_png("%s-%02d.png" % [out, idx])
		idx += 1
		if idx >= spots.size():
			return true
		var s: Array = spots[idx]
		var t := Vector3(float(s[0]) - 175.0, 0, float(s[1]) - 175.0)
		var dist := float(s[2]) if s.size() > 2 else 11.0
		var yaw := deg_to_rad(float(s[3]) if s.size() > 3 else 35.0)
		var p := t + Vector3(sin(yaw), 0, cos(yaw)) * dist
		t.y = _ground(t.x, t.z) + 0.6
		p.y = max(_ground(p.x, p.z), _ground(p.x, p.z)) + (float(s[4]) if s.size() > 4 else 1.7)
		cam.look_at_from_position(p, t)
	return false
