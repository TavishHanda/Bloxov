extends SceneTree
# Preview sheet of the jointed characters (make_body.py) standing, kneeling and prone, in their real outfits.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/body_preview.gd -- dir=<folder with *_body.glb> out=<prefix>
var dir := "res://assets/models/characters"
var out := "/tmp/body"

const UPPER := 0.30
const HAND := 0.27 + 0.05


func load_body(name: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(dir.path_join(name + "_body.glb"), state)
	var scene := doc.generate_scene(state) as Node3D
	var holder := Node3D.new()
	holder.add_child(scene)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return holder


func pick_outfit(ch: Node3D, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slots := {}
	for node in ch.find_children("*__*", "Node3D", true, false):
		var parts := String(node.name).split("__")
		slots.get_or_add(parts[0], {}).get_or_add(parts[1], []).append(node)
	var names := slots.keys()
	names.sort()
	for slot in names:
		var options: Array = slots[slot].keys()
		options.sort()
		var pick: String = options[rng.randi_range(0, options.size() - 1)]
		for option in options:
			for node in slots[slot][option]:
				(node as Node3D).visible = option == pick


func j(ch: Node3D, name: String) -> Node3D:
	return ch.find_child(name, true, false) as Node3D


func deg(x: float, y := 0.0, z := 0.0) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))


func limb_basis(along: Vector3, ch: Node3D) -> Basis:
	var y := -along.normalized()
	var ref := -ch.global_basis.z
	if absf(y.dot(ref)) > 0.95:
		ref = ch.global_basis.y
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


func reach(ch: Node3D, side: String, target: Vector3, pole: Vector3) -> void:
	var sh := j(ch, "Arm" + side)
	var el := j(ch, "Elbow" + side)
	var a := UPPER
	var b := HAND
	var S := sh.global_position
	var to := target - S
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var cos_a := (a * a + d * d - b * b) / (2.0 * a * d)
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var E := S + dir * a * cos_a + perp * a * sqrt(maxf(1.0 - cos_a * cos_a, 0.0))
	sh.global_basis = limb_basis(E - S, ch)
	el.global_basis = limb_basis(S + dir * d - E, ch)


func hold_gun(ch: Node3D, gun: Node3D, grip: Vector3) -> void:
	var g := gun.get_node("Grip") as Node3D
	var f := gun.get_node("Fore") as Node3D
	gun.position = grip - g.position
	var right := ch.global_basis.x
	reach(ch, "R", gun.global_transform * (g.position + Vector3(0, 0.03, 0)), right * 0.6 - ch.global_basis.y)
	reach(ch, "L", gun.global_transform * (f.position + Vector3(0, -0.01, 0)), -right * 0.8 - ch.global_basis.y)


func pose(ch: Node3D, gun: Node3D, p: String) -> void:
	var hips := j(ch, "Hips")
	match p:
		"stand":
			j(ch, "LegL").rotation = deg(6)
			j(ch, "LegR").rotation = deg(-5)
		"crouch":
			j(ch, "LegL").rotation = deg(82)
			j(ch, "KneeL").rotation = deg(-84)
			j(ch, "LegR").rotation = deg(-8)
			j(ch, "KneeR").rotation = deg(-82)
			hips.position.y = 0.38 * cos(deg_to_rad(8)) + 0.1
			j(ch, "Spine").rotation = deg(-12)
			j(ch, "Neck").rotation = deg(10)
		"prone":
			hips.position.y = 0.2
			hips.rotation = deg(-90)
			j(ch, "Spine").rotation = deg(10)
			j(ch, "Neck").rotation = deg(62)
			j(ch, "LegL").rotation = deg(0, 0, -14)
			j(ch, "LegR").rotation = deg(0, 0, 16)
			j(ch, "KneeL").rotation = deg(-12)
	var neck := ch.to_local(j(ch, "Neck").global_position)
	if p == "prone":
		hold_gun(ch, gun, Vector3(0.09, 0.16, neck.z - 0.12))
	else:
		hold_gun(ch, gun, neck + Vector3(0.17, -0.26, -0.26))


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("dir="):
			dir = a.substr(4)
	var vp := SubViewport.new()
	vp.size = Vector2i(520, 520)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b2f33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6b6a5c")
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 32
	world.add_child(cam)
	cam.current = true
	await process_frame
	# Lineup: today's models (left) next to the new ones, facing the camera.
	vp.size = Vector2i(1400, 640)
	var line := Node3D.new()
	world.add_child(line)
	var x := -3.9
	for who in ["pmc", "scav", "raider"]:
		var old: Node3D = (load("res://assets/models/characters/%s.glb" % who) as PackedScene).instantiate()
		old.set_script(load("res://scripts/pixel_model.gd"))
		line.add_child(old)
		old.position.x = x
		old.rotation.y = PI
		(old as PixelModel).pick_outfit_seeded(7)
		var nb := load_body(who)
		pick_outfit(nb, {"pmc": 3, "scav": 5, "raider": 2}[who])
		line.add_child(nb)
		nb.position.x = x + 1.05
		nb.rotation.y = PI
		x += 2.8
	line.rotation.y = 0.0
	cam.look_at_from_position(Vector3(-0.2, 1.5, 7.2), Vector3(-0.2, 1.0, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s-lineup.png" % out)
	line.queue_free()
	vp.size = Vector2i(520, 520)
	var guns := {"scav": "hound", "pmc": "wasp", "raider": "hound"}
	for who in ["pmc", "scav", "raider"]:
		for p in ["stand", "crouch", "prone"]:
			var ch := load_body(who)
			pick_outfit(ch, {"pmc": 3, "scav": 5, "raider": 2}[who])
			var gun: Node3D = (load("res://assets/models/guns/%s.glb" % guns[who]) as PackedScene).instantiate()
			ch.add_child(gun)
			ch.rotation.y = deg_to_rad(-35)
			world.add_child(ch)
			pose(ch, gun, p)
			var local := Vector3(0, 0.95, 0) if p != "prone" else Vector3(0, 0.3, -0.35)
			var target := ch.global_transform * local
			var back := 6.0 if p != "prone" else 5.0
			cam.look_at_from_position(target + Vector3(-2.2, 1.3 if p != "prone" else 2.0, -4.2).normalized() * back, target)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s-%s-%s.png" % [out, who, p])
			world.remove_child(ch)
			ch.free()
	quit()
