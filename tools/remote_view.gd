extends SceneTree
# Frames of another player (a real RemotePlayer fed network states) in motion: walking, sprinting, crouch-walking,
# going prone, crawling, turning while prone, getting hit. For checking the third-person animation (0.25.22).
# xvfb-run -a godot --rendering-driver opengl3 -s tools/remote_view.gd -- out=/tmp/rv [only=walk,spin] [boxes]
# Writes <out>-<scenario>.png: a strip of frames (320 px each), the camera fixed so movement shows.

const W := 320
## name: [camera offset from the start spot, frames, seconds between frames, gun]
const SCENES := {
	"stand": [Vector3(-2.6, 1.6, -3.4), 4, 0.6, "ak"],
	"walk": [Vector3(-4.2, 1.4, -2.0), 6, 0.1, "ak"],
	"sprint": [Vector3(-4.2, 1.4, -2.0), 6, 0.08, "ak"],
	"crouch_walk": [Vector3(-4.2, 1.2, -2.0), 6, 0.12, "smg"],
	"go_prone": [Vector3(-5.5, 1.6, -0.5), 6, 0.06, "ak"],
	"crawl": [Vector3(-3.5, 2.2, -3.5), 6, 0.15, "ak"],
	"spin": [Vector3(0.01, 7.0, 0.0), 6, 0.15, "ak"],
	"hit": [Vector3(-4.0, 1.4, 0.0), 6, 0.04, "ak"],
	"stand_up": [Vector3(-3.0, 1.2, -3.0), 6, 0.12, "ak"],
	"turn": [Vector3(-2.6, 1.6, -3.4), 6, 0.1, "ak"],
	"climb": [Vector3(-2.6, 0.4, 1.6), 4, 0.15, "ak"],
}


func _initialize() -> void:
	var out := "/tmp/rv"
	var only: Array = []
	var boxes := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("only="):
			only = Array(a.substr(5).split(","))
		elif a == "boxes":
			boxes = true
	var vp := SubViewport.new()
	vp.size = Vector2i(W, 400)
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
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6b6a5c")
	ground.material_override = gm
	world.add_child(ground)
	# A grid of dots on the ground, so you can see where the body is.
	for x in range(-6, 7):
		for z in range(-6, 7):
			var dot := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.06, 0.01, 0.06)
			dot.mesh = bm
			dot.position = Vector3(x * 0.5, 0.005, z * 0.5)
			world.add_child(dot)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.current = true
	await process_frame
	for scene_name: String in SCENES:
		if not only.is_empty() and not scene_name in only:
			continue
		var spec: Array = SCENES[scene_name]
		var ladder: Ladder = null
		if scene_name == "climb":   # (0.32.1: a ladder to climb, its climbing side toward +Z)
			ladder = (load("res://scenes/ladder.tscn") as PackedScene).instantiate()
			ladder.height = 6.0
			world.add_child(ladder)
			ladder.position = Vector3(0, 0, -0.44)
		var body: RemotePlayer = (load("res://scenes/remote_player.tscn") as PackedScene).instantiate()
		body.set_process(false)
		world.add_child(body)
		(body.model as PixelModel).pick_outfit_seeded(3)
		(body.model as PixelModel).merge_parts()
		var gun_flags := Hitbox.FLAG_ARMED | AILoadouts.NET_GUNS.find(spec[3]) << Hitbox.GUN_SHIFT
		var frames: Array[Image] = []
		var clock := 10.0
		var step := 1.0 / 60.0
		var shot_at := -1
		var total := int(spec[1])
		var every := float(spec[2])
		# Warm-up second, then frames.
		var t := 0.0
		var frame := 0
		var next_shot := 1.0
		var warm := 1.0
		var target := Vector3(0, 0.9, 0)
		if scene_name in ["go_prone", "crawl", "spin"]:
			target = Vector3(0, 0.3, 0)
		while frame < total:
			var state := _state(scene_name, t, warm, gun_flags)
			body.push_state(state, clock)
			body.update_view(clock - 0.0001, step)
			if scene_name == "hit" and t >= warm and shot_at < 0:
				if body.has_method("flinch"):
					body.call("flinch", Vector3(0, 0, 1))
				shot_at = 1
			clock += step
			t += step
			if t >= next_shot - 0.0001:
				next_shot += every
				var at: Vector3 = (body.global_position if scene_name in ["walk", "sprint", "crouch_walk", "crawl"] else Vector3.ZERO)
				var look := Vector3(at.x, 0, at.z) + target
				if scene_name == "climb":
					look = body.global_position + target
				cam.look_at_from_position(look + spec[0], look)
				if boxes:
					_boxes(body)
				for i in 2:
					await process_frame
				await RenderingServer.frame_post_draw
				frames.append(vp.get_texture().get_image())
				frame += 1
				for c in body.get_children():
					if c.name == "BoxView":
						c.free()
		var sheet := Image.create(W * frames.size(), 400, false, frames[0].get_format())
		for i in frames.size():
			sheet.blit_rect(frames[i], Rect2i(0, 0, W, 400), Vector2i(i * W, 0))
		sheet.save_png("%s-%s.png" % [out, scene_name])
		body.queue_free()
		if ladder != null:
			ladder.queue_free()
		await process_frame
	quit()


## The state a scenario sends at `t` seconds (`warm` = when the frames start).
func _state(scene_name: String, t: float, warm: float, gun: int) -> Array:
	var f := gun
	var pos := Vector3.ZERO
	var yaw := 0.0
	match scene_name:
		"walk":
			pos = Vector3(0, 0, -3.6 * t)
		"sprint":
			pos = Vector3(0, 0, -5.6 * t)
			f |= Hitbox.FLAG_SPRINT
		"crouch_walk":
			pos = Vector3(0, 0, -2.0 * t)
			f |= Hitbox.FLAG_CROUCH
		"go_prone":
			if t > warm:
				f |= Hitbox.FLAG_CROUCH | Hitbox.FLAG_PRONE
		"crawl":
			pos = Vector3(0, 0, -0.9 * t)
			f |= Hitbox.FLAG_CROUCH | Hitbox.FLAG_PRONE
		"spin":
			yaw = maxf(t - warm, 0.0) * 2.4
			f |= Hitbox.FLAG_CROUCH | Hitbox.FLAG_PRONE
		"stand_up":
			if t < warm:
				f |= Hitbox.FLAG_CROUCH
		"turn":
			yaw = maxf(t - warm, 0.0) * 3.0
		"climb":
			pos = Vector3(0, 0.3 + 2.4 * t, 0)
			yaw = 0.9   # (looking off to the side: the body still faces the ladder)
	return [pos, yaw, 0.0, 0.0, f]


func _boxes(body: RemotePlayer) -> void:
	var holder := Node3D.new()
	holder.name = "BoxView"
	body.add_child(holder)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.2, 0.2)
	for shape: CollisionShape3D in [body.head_shape, body.body_shape, body.legs_shape]:
		if shape.disabled:
			continue
		var h: Vector3 = (shape.shape as BoxShape3D).size * 0.5
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
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
					im.surface_add_vertex(shape.transform * p0)
					im.surface_add_vertex(shape.transform * p1)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		holder.add_child(mi)
