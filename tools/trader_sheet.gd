extends SceneTree
## Renders every trader design in TraderLooks.OPTIONS (lively hideout), one PNG each, for the owner to pick from:
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/trader_sheet.gd -- [out=/some/dir]
var out := "/tmp/trader_sheet/"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(520, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.15, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.83, 0.8)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.28, 0.25)
	plane.material = floor_mat
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 32.0
	stage.add_child(camera)
	camera.position = Vector3(1.5, 1.45, -4.6)
	camera.look_at(Vector3(0, 1.05, 0))
	camera.current = true
	for trader: String in TraderLooks.OPTIONS:
		var designs: Array = TraderLooks.OPTIONS[trader]
		for k in designs.size():
			var model := (load("res://assets/models/characters/trader.glb") as PackedScene).instantiate()
			model.set_script(load("res://scripts/pixel_model.gd"))
			(model as PixelModel).randomize_outfit = false
			stage.add_child(model)
			(model as PixelModel).pick_outfit(designs[k]["look"])
			model.rotation.y = 0.0   # (the model faces -z: the camera)
			var gun := model.get_node_or_null("Gun") as Node3D
			if gun != null:
				gun.visible = false
			var pose := BodyPose.new(model)
			pose.armed = false
			pose.update(0.0)
			for i in 6:
				await process_frame
			var path := "%s%s_%d.png" % [out, trader, k]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
			model.free()
	quit()
