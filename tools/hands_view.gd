extends SceneTree
# Renders the first-person hands on every gun, at the hip and aimed, for checking them and for the owner's option sheets
# (make_hands.py). xvfb-run -a godot --rendering-driver opengl3 -s tools/hands_view.gd -- out=/tmp/hands [hands=<glb>]
# Writes <out>-<key>-hip.png and <out>-<key>-aim.png (640x360, from the window's size) for the rifle, pistol, smg, shotgun and sniper.
const ADS := {"rifle": Vector3(0, -0.092, -0.36), "pistol": Vector3(0, -0.036, -0.28)}   # (Gun.ADS_POSITIONS)


func _initialize() -> void:
	var out := "/tmp/hands"
	var hands := GunViewModels.HANDS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("hands="): hands = a.substr(6)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	for c in main.get_children():
		if not c.name in ["WorldEnvironment", "Sun", "Level"]:
			main.remove_child(c); c.free()
	main.set_script(null)
	root.add_child(main)
	var cam := Camera3D.new(); cam.fov = 80.0; main.add_child(cam); cam.current = true
	cam.look_at_from_position(Vector3(0, 1.6, 6), Vector3(0, 1.4, -10))
	var gun := Node3D.new(); cam.add_child(gun)
	for spec in [["Model", Vector3(0.22, -0.2, -0.42)], ["PistolModel", Vector3(0.17, -0.16, -0.36)]]:
		var holder := Node3D.new(); holder.name = spec[0]; holder.position = spec[1]; gun.add_child(holder)
		var muzzle := Marker3D.new(); muzzle.name = "Muzzle"; holder.add_child(muzzle)
		var flash := Node3D.new(); flash.name = "Flash"; muzzle.add_child(flash)
	var models := GunViewModels.build_all(gun)
	models["rifle"] = gun.get_node("Model"); models["pistol"] = gun.get_node("PistolModel")
	var ads := ADS.merged(GunViewModels.ADS)
	for key: String in ["rifle", "pistol", "smg", "shotgun", "sniper"]:
		var model: Node3D = models[key]
		var old := model.get_node("Hands"); model.remove_child(old); old.free()
		GunViewModels.add_hands(model, HeldGun.MODELS[GunViewModels.WEAPONS[key]], hands)
		for m: Node3D in models.values(): m.visible = m == model
		var rest := model.position
		for pose in ["hip", "aim"]:
			model.position = rest if pose == "hip" else GunViewModels.aim_place(model, ads[key])
			model.rotation = GunViewModels.REST_TURN.get(key, Vector3.ZERO) if pose == "hip" else Vector3.ZERO
			for i in 4: await process_frame
			GunViewModels.pose_arms(model, gun)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(640, 360)
			img.save_png("%s-%s-%s.png" % [out, key, pose])
		model.position = rest
	quit()
