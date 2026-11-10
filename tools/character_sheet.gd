extends SceneTree
## Renders the raid characters (scav, PMC, raider) in a row of outfits each, one PNG per character, to compare looks
## (clean raid models, 2026-11-09):
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/character_sheet.gd -- [out=/some/dir] [tag=before] [close]
## The outfits come from a fixed seed, so two runs (before and after a model change) show the same looks.
var out := "/tmp/character_sheet/"
var tag := "sheet"
var close := false
const COUNT := 5


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
		elif a.begins_with("tag="):
			tag = a.substr(4)
		elif a == "close":
			close = true
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1400, 620) if not close else Vector2i(1400, 520)
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
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 6)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.28, 0.25)
	plane.material = floor_mat
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 30.0
	stage.add_child(camera)
	camera.current = true
	if close:
		camera.position = Vector3(0.6, 1.75, -6.2)
		camera.look_at(Vector3(0, 1.45, 0))
		camera.fov = 22.0
	else:
		camera.position = Vector3(0.8, 1.5, -8.6)
		camera.look_at(Vector3(0, 1.0, 0))
	for character: String in ["scav", "pmc", "raider"]:
		seed(1234)
		var models := []
		for k in COUNT:
			var model := (load("res://assets/models/characters/%s.glb" % character) as PackedScene).instantiate()
			model.set_script(load("res://scripts/pixel_model.gd"))
			(model as PixelModel).randomize_outfit = false
			stage.add_child(model)
			(model as PixelModel).pick_outfit()
			model.position = Vector3((k - (COUNT - 1) / 2.0) * 1.25, 0, 0)
			model.rotation.y = deg_to_rad(-15.0 + 8.0 * k)   # (the model faces -z: the camera)
			var gun := model.get_node_or_null("Gun") as Node3D
			if gun != null:
				gun.visible = false
			var pose := BodyPose.new(model)
			pose.armed = false
			pose.update(0.0)
			models.append(model)
		for i in 6:
			await process_frame
		var path := "%s%s_%s.png" % [out, character, tag]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		for m: Node in models:
			m.free()
	quit()
