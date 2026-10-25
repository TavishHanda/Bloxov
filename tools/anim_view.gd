extends SceneTree
# Renders the first-person reload animation and shot kick (0.20.24, GunViewModels.reload_pose / kick_offset) as frames,
# for checking them. xvfb-run -a godot --rendering-driver opengl3 -s tools/anim_view.gd -- out=/tmp/anim [guns=rifle,pistol] [frames=r00,r05,k1.0] [empty]
# Writes <out>-<key>-<frame>.png (480x270) for each gun: reload at t = 0, 0.1 .. 1, then kick frames k0..k3.
const ADS := {"rifle": Vector3(0, -0.092, -0.36), "pistol": Vector3(0, -0.036, -0.28)}   # (Gun.ADS_POSITIONS)
const RESTS := {"rifle": Vector3(0.22, -0.2, -0.42), "pistol": Vector3(0.17, -0.16, -0.36)}


func _initialize() -> void:
	var out := "/tmp/anim"
	var keys := ["rifle", "pistol", "smg", "shotgun", "sniper"]
	var empty := false
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("guns="): keys = Array(a.substr(5).split(","))
		if a == "empty": empty = true
		if a.begins_with("frames="): only = Array(a.substr(7).split(","))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	for c in main.get_children():
		if not c.name in ["WorldEnvironment", "Sun", "Level"]:
			main.remove_child(c); c.free()
	main.set_script(null)
	root.add_child(main)
	var cam := Camera3D.new(); cam.fov = 80.0; main.add_child(cam); cam.current = true
	cam.look_at_from_position(Vector3(0, 1.6, 6), Vector3(0, 1.4, -10))
	var gun := Node3D.new(); cam.add_child(gun)
	for spec in [["Model", RESTS["rifle"]], ["PistolModel", RESTS["pistol"]]]:
		var holder := Node3D.new(); holder.name = spec[0]; holder.position = spec[1]; gun.add_child(holder)
		var muzzle := Marker3D.new(); muzzle.name = "Muzzle"; holder.add_child(muzzle)
		var flash := Node3D.new(); flash.name = "Flash"; muzzle.add_child(flash)
	var models := GunViewModels.build_all(gun)
	models["rifle"] = gun.get_node("Model"); models["pistol"] = gun.get_node("PistolModel")
	for key: String in keys:
		var model: Node3D = models[key]
		for m: Node3D in models.values(): m.visible = m == model
		var rest: Vector3 = GunViewModels.REST.get(key, RESTS.get(key, Vector3.ZERO))
		var one := key == "shotgun"
		var frames := []
		for i in 11:
			frames.append(["r%02d" % i, i / 10.0])
		for k in [0.0, 0.4, 1.0, 1.4]:
			frames.append(["k%.1f" % k, -k])
		for f in frames:
			if not only.is_empty() and not f[0] in only:
				continue
			var t: float = f[1]
			if t >= 0.0:
				# The whole-gun reload pose from Gun._update_model.
				var jolt := GunViewModels.reload_jolt(t, empty)
				var pose: Array = GunViewModels.LOAD_ONE_POSE if one else GunViewModels.RELOAD_POSE
				model.position = rest + pose[0] + Vector3(0, 0.012 * jolt, 0)
				model.rotation = pose[1] + Vector3(0.06 * jolt, 0, 0)
				GunViewModels.reload_pose(model, t, empty, one)
			else:
				var kick := GunViewModels.kick_offset(-t, 0.5, 0.0)
				model.position = rest + kick[0]
				model.rotation = GunViewModels.REST_TURN.get(key, Vector3.ZERO) + kick[1]
				GunViewModels.reload_pose(model, -1.0, false, one)
			for j in 3: await process_frame
			GunViewModels.pose_arms(model, gun)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(480, 270)
			img.save_png("%s-%s-%s.png" % [out, key, f[0]])
	quit()
