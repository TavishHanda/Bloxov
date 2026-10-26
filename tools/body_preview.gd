extends SceneTree
# Pictures of the jointed characters (make_character.py) in every BodyPose pose, optionally with the player hitboxes
# as red wireframes.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/body_preview.gd -- out=/tmp/pose [boxes] [side] [poses=kneel,prone]
# Writes <out>-<character>-<pose>.png (520 px squares).

const POSES := {
	"stand": {}, "walk": {"speed": 3.0, "time": 0.35}, "kneel": {"crouch": 1.0},
	"crouch_walk": {"crouch": 1.0, "speed": 2.0, "time": 0.35}, "prone": {"prone": 1.0},
	"crawl": {"prone": 1.0, "speed": 1.0, "time": 0.4}, "downed": {"downed": 1.0},
	"dead": {"dead": 1.0},
}
const GUNS := {"pmc": "smg", "scav": "ak", "raider": "ak"}


func _initialize() -> void:
	var out := "/tmp/pose"
	var boxes := false
	var only: Array = []
	var side := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a == "boxes":
			boxes = true
		elif a == "side":
			side = true
		elif a.begins_with("poses="):
			only = Array(a.substr(6).split(","))
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
	for who: String in ["pmc", "scav", "raider"]:
		for p: String in POSES:
			if not only.is_empty() and not p in only:
				continue
			var settings: Dictionary = POSES[p]
			var holder := Node3D.new()
			world.add_child(holder)
			holder.rotation.y = deg_to_rad(-35)
			var model: Node3D = (load("res://assets/models/characters/%s.glb" % who) as PackedScene).instantiate()
			model.set_script(load("res://scripts/pixel_model.gd"))
			model.set("randomize_outfit", false)
			holder.add_child(model)
			(model as PixelModel).pick_outfit_seeded({"pmc": 3, "scav": 5, "raider": 2}[who])
			HeldGun.show(model, GUNS[who])
			(model as PixelModel).merge_parts()   # one skinned mesh, as in a raid
			var pose := BodyPose.new(model)
			pose.crouch = settings.get("crouch", 0.0)
			pose.prone = settings.get("prone", 0.0)
			pose.downed = settings.get("downed", 0.0)
			pose.dead = settings.get("dead", 0.0)
			pose.speed = settings.get("speed", 0.0)
			model.get_node("Gun").visible = pose.downed < 0.5 and pose.dead < 0.5
			# Run the walk cycle up to the moment wanted (a stride in mid swing).
			var t := 0.0
			while t < settings.get("time", 0.0) + 0.6:
				pose.update(1.0 / 60.0)
				t += 1.0 / 60.0
			if boxes:
				_boxes(holder, settings)
			var lying: bool = pose.prone + pose.downed + pose.dead > 0.5
			var local := Vector3(0, 0.95, 0)
			if lying:
				local = Vector3(0, 0.3, 0.6 if pose.dead > 0.5 else -0.8)
			var target := holder.global_transform * local
			var from := Vector3(-2.2, 1.3 if not lying else 2.2, -4.2).normalized() * (6.0 if not lying else 5.5)
			if side:   # from their left, level
				from = holder.global_basis * Vector3(-5.5, 0.8, 0.0)
			cam.look_at_from_position(target + from, target)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s-%s-%s.png" % [out, who, p])
			holder.queue_free()
			await process_frame
	quit()


## The player hitboxes (Hitbox) for this pose, as red wireframes (scavs use the same sizes standing).
func _boxes(holder: Node3D, settings: Dictionary) -> void:
	if settings.get("dead", 0.0) > 0.5:
		return
	var parts := []
	if settings.get("prone", 0.0) + settings.get("downed", 0.0) > 0.5:
		parts = [[Hitbox.prone_head_center(0.0), Hitbox.HEAD_SIZE], [Hitbox.DOWNED_BODY_CENTER, Hitbox.DOWNED_BODY_SIZE]]
	else:
		var c: float = settings.get("crouch", 0.0)
		parts = [[Hitbox.head_center(c, 0.0), Hitbox.HEAD_SIZE], [Hitbox.body_center(c), Hitbox.body_size(c)]]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.2, 0.2)
	for part: Array in parts:
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		var h: Vector3 = part[1] * 0.5
		var c: Vector3 = part[0]
		for a in 3:
			for s1: float in [-1.0, 1.0]:
				for s2: float in [-1.0, 1.0]:
					var p0 := Vector3.ZERO
					var p1 := Vector3.ZERO
					var b := (a + 1) % 3
					var d := (a + 2) % 3
					p0[a] = -h[a]
					p1[a] = h[a]
					p0[b] = s1 * h[b]
					p1[b] = s1 * h[b]
					p0[d] = s2 * h[d]
					p1[d] = s2 * h[d]
					im.surface_add_vertex(c + p0)
					im.surface_add_vertex(c + p1)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		holder.add_child(mi)
