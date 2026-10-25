extends SceneTree
# Renders the main screen's background (0.21.15): the town of Bloxov Battlegrounds at dusk, smoke rising, wider than
# the screen so the title screen can drift slowly across it.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/render_title_bg.gd  (writes assets/textures/title_dusk.jpg)
const OUT := "res://assets/textures/title_dusk.jpg"
const SIZE := Vector2i(2400, 1080)
const FROM := Vector3(-40, 22, -30)
const AT := Vector3(-95, 0, -110)


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var keep := ["WorldEnvironment", "Sun", "Clouds", "Level", "Loot"]
	for c in main.get_children():
		if not c.name in keep:
			main.remove_child(c)
			c.free()
	main.set_script(null)
	root.add_child(main)
	for i in 3:
		await process_frame
	# Dusk: the raid's look, the sun low and red, a warm haze.
	var env: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.16, 0.18, 0.3)
	sky.sky_horizon_color = Color(0.95, 0.5, 0.3)
	sky.ground_horizon_color = Color(0.6, 0.35, 0.25)
	env.ambient_light_color = Color(0.45, 0.42, 0.55)
	env.ambient_light_energy = 0.7
	env.fog_light_color = Color(0.75, 0.42, 0.3)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.4
	var sun: DirectionalLight3D = main.get_node("Sun")
	sun.light_color = Color(1.0, 0.55, 0.32)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-9, 200, 0)
	var cam := Camera3D.new()
	cam.far = 2000
	cam.fov = 55
	main.add_child(cam)
	cam.current = true
	root.size = SIZE
	cam.look_at_from_position(FROM, AT)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(OUT), 0.88)
	quit()
