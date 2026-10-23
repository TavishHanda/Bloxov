extends SceneTree
# Where the map collides, drawn over the models (0.18.3: for checking hitboxes match what's drawn).
# xvfb-run -a godot --rendering-driver opengl3 -s tools/collision_view.gd -- <out_dir> "mx,mz,yaw,pitch,y[,fov]" ...
# (map metres; yaw 0 looks north (-z), 90 west) -> <out_dir>/shotN.png and shotN_col.png: what collides (world layer
# and barred windows) in see-through red; red that sticks out past a model is an invisible wall.
var out := ""
var shots := []
var frame := 0
var idx := -1
var cam: Camera3D
var overlay: MeshInstance3D
var phase := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	for c in main.get_children():
		if not (String(c.name) in ["WorldEnvironment", "Sun", "Clouds"]):
			main.remove_child(c); c.free()
	var map: Node = (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	for c in map.get_children():
		if String(c.name) in ["Level", "Loot", "Extracts", "KeyDoors", "Doors"]:
			map.remove_child(c); main.add_child(c)
	map.free()
	root.add_child(main)
	for a in args.slice(1):
		shots.append(a.split(","))
	cam = Camera3D.new(); cam.fov = 70; cam.far = 900
	main.add_child(cam); cam.current = true
	root.size = Vector2i(1280, 720)
	overlay = MeshInstance3D.new()
	main.add_child(overlay)

func _build_overlay() -> void:
	var faces := PackedVector3Array()
	for body in _bodies(root):
		for c in body.get_children():
			if c is CollisionShape3D and not c.disabled and (body.collision_layer & (1 | 128)):
				var s: Shape3D = c.shape
				var xf: Transform3D = c.global_transform
				var m: Mesh = s.get_debug_mesh()
				if s is ConcavePolygonShape3D:
					for v in s.get_faces(): faces.append(xf * v)
				elif s is BoxShape3D:
					for v in BoxMesh.new().get_faces(): faces.append(xf * (v * s.size))
	var am := ArrayMesh.new()
	var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = faces
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0, 0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	am.surface_set_material(0, mat)
	overlay.mesh = am
	print("collision tris ", faces.size() / 3)

func _bodies(n: Node) -> Array:
	var r := []
	if n is CollisionObject3D: r.append(n)
	for c in n.get_children(): r.append_array(_bodies(c))
	return r

func _process(_d: float) -> bool:
	frame += 1
	if frame == 6:
		_build_overlay()
		overlay.visible = false
	if frame < 8:
		return false
	if frame % 10 == 0:
		if idx >= 0:
			root.get_texture().get_image().save_png("%s/shot%d%s.png" % [out, idx, "_col" if overlay.visible else ""])
			if not overlay.visible:
				overlay.visible = true
				return false
			overlay.visible = false
		idx += 1
		if idx >= shots.size():
			return true
		var s: Array = shots[idx]
		cam.global_position = Vector3(float(s[0]) - 175.0, float(s[4]), float(s[1]) - 175.0)
		cam.rotation_degrees = Vector3(float(s[3]), float(s[2]), 0)
		if s.size() > 5:
			cam.fov = float(s[5])
	return false
