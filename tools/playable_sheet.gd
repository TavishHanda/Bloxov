extends SceneTree
## Pictures of the six playable characters (0.39): one PNG per character, each skin from the front plus the first
## skin from the back, and one PNG of all six side by side in their first skin.
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/playable_sheet.gd -- [out=/some/dir]
var out := "/tmp/playable_sheet/"
const CHARACTERS := {"vega": ["nova", "dusk", "night"], "voss": ["officer", "parade", "field"],
	"sable": ["woodland", "desert", "snow"], "patch": ["field", "city", "winter"], "nine": ["subject", "escaped", "lab"],
	"korr": ["quartermaster", "scrounger", "frost"]}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _model(id: String, skin: String) -> Node3D:
	var model := (load("res://assets/models/characters/%s.glb" % id) as PackedScene).instantiate() as Node3D
	model.set_script(load("res://scripts/pixel_model.gd"))
	(model as PixelModel).randomize_outfit = false
	return model


func _dress(model: Node3D, skin: String) -> void:
	var choices := {}
	for slot: String in (model as PixelModel).outfit_slots():
		choices[slot] = skin
	(model as PixelModel).pick_outfit(choices)
	var gun := model.get_node_or_null("Gun") as Node3D
	if gun != null:
		gun.visible = false
	var pose := BodyPose.new(model)
	pose.armed = false
	pose.update(0.0)


func _run() -> void:
	root.size = Vector2i(1400, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.15, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.83, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 6)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.28, 0.25)
	plane.material = floor_mat
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 30.0
	stage.add_child(camera)
	camera.current = true
	camera.position = Vector3(0.5, 1.6, -7.0)
	camera.look_at(Vector3(0, 1.1, 0))
	# Each character: its skins from the front, then the first skin from the back.
	for id: String in CHARACTERS:
		var skins: Array = CHARACTERS[id]
		var models := []
		for k in skins.size() + 1:
			var model := _model(id, "")
			stage.add_child(model)
			_dress(model, skins[mini(k, skins.size() - 1)] if k < skins.size() else skins[0])
			model.position = Vector3((skins.size() / 2.0 - k) * 1.5, 0, 0)
			model.rotation.y = deg_to_rad(-12.0 + 8.0 * k) if k < skins.size() else PI + deg_to_rad(-20.0)
			models.append(model)
		for i in 6:
			await process_frame
		var path := "%s%s.png" % [out, id]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		for m: Node in models:
			m.free()
	# All six together.
	camera.position = Vector3(0.5, 1.7, -9.0)
	camera.look_at(Vector3(0, 1.15, 0))
	var all := []
	var i := 0
	for id: String in CHARACTERS:
		var model := _model(id, "")
		stage.add_child(model)
		_dress(model, CHARACTERS[id][0])
		model.position = Vector3((2.5 - i) * 1.35, 0, 0)
		model.rotation.y = deg_to_rad(-10.0 + 4.0 * i)
		all.append(model)
		i += 1
	for f in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "all.png")
	print("saved ", out + "all.png")
	quit()
