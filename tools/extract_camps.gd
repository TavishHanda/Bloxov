extends SceneTree
## Extract camping check for Bloxov Frontlines (owner 2026-11-09: "they are WAY too easy to extract camp"). For each
## extract, finds the spots round it (on the ground, within RANGE) that can see someone standing or crouching in its
## square, through the real collision. Prints a score per extract and draws a top-down picture of each with the
## camping spots on it (red = sees a crouched player in the square, orange = sees a standing one only).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/extract_camps.gd -- out=/tmp/camps   (pictures + report)
##   godot --headless -s tools/extract_camps.gd -- out=/tmp/camps                                  (report only)
##   ... corners=1 also prints, per crouched point of the square (3 x 3), how much ground sees it: the safe corners.
## Score = the ground (m²) a camper could watch the square from, 20 m to RANGE out; lower = better.

const STEP := 3.0          # metres between checked spots
const RANGE := 130.0       # longest camping shot that counts
const NEAR := 20.0         # closer than this is a fight, not a camp
const EYE := 1.6
const STAND := 1.1         # aim height on someone standing
const CROUCH := 0.6        # and crouched
var VIEW := 180.0          # picture width in metres (view=N)


func _initialize() -> void:
	var out := "/tmp/camps"
	var only := ""
	var corners := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("view="):
			VIEW = float(a.substr(5))
		if a == "corners=1":
			corners = true
		if a.begins_with("only="):
			only = a.substr(5)
	var draw := DisplayServer.get_name() != "headless"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var extracts := []
	for e in main.get_node("Extracts").get_children():
		extracts.append([String(e.get("extract_name")), (e as Node3D).position])
	var keep := ["WorldEnvironment", "Sun", "Level", "Loot", "Extracts"] if draw else ["Level"]
	for c in main.get_children():
		if not c.name in keep:
			main.remove_child(c)
			c.free()
	main.set_script(null)
	root.add_child(main)
	for i in 4:
		await physics_frame
	var space := (main as Node3D).get_world_3d().direct_space_state
	var cam: Camera3D
	if draw:
		cam = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = VIEW
		cam.far = 400
		main.add_child(cam)
		cam.current = true
		root.size = Vector2i(900, 900)
	var total := 0
	for ex in extracts:
		if only != "" and not ex[0].to_lower().replace(" ", "").contains(only):
			continue
		var c: Vector3 = ex[1]
		var stand: Array[Vector3] = []
		var crouch: Array[Vector3] = []
		for dx in [-1.5, 0.0, 1.5]:
			for dz in [-1.5, 0.0, 1.5]:
				var g = _ground(space, c.x + dx, c.z + dz)
				if g == null:
					g = c.y
				stand.append(Vector3(c.x + dx, g + STAND, c.z + dz))
				crouch.append(Vector3(c.x + dx, g + CROUCH, c.z + dz))
		var spots := []   # [pos, standing points seen, crouched points seen]
		var per := PackedFloat32Array()   # m² watching each crouched point (corners=1)
		per.resize(9)
		var n := int(RANGE / STEP)
		for j in range(-n, n + 1):
			for i in range(-n, n + 1):
				var x := c.x + i * STEP
				var z := c.z + j * STEP
				var d := Vector2(x - c.x, z - c.z).length()
				if d > RANGE or d < NEAR:
					continue
				var g = _ground(space, x, z)
				if g == null:
					continue
				var eye := Vector3(x, g + EYE, z)
				var s := _seen(space, eye, stand)
				var k := _seen(space, eye, crouch) if s > 0 else 0
				if s > 0:
					spots.append([eye, s, k])
				if corners:
					for p in 9:
						var q := PhysicsRayQueryParameters3D.create(eye, crouch[p])
						q.collision_mask = 1 | 32 | 64
						if space.intersect_ray(q).is_empty():
							per[p] += STEP * STEP
		var area_s := 0.0
		var area_k := 0.0
		var close_k := 0.0
		for s in spots:
			area_s += STEP * STEP
			if s[2] > 0:
				area_k += STEP * STEP
				if Vector2(s[0].x - c.x, s[0].z - c.z).length() < 70.0:
					close_k += STEP * STEP
		total += int(area_s)
		if corners:   # (rows north to south, west to east: the corners nobody far off sees are the safe ones)
			for r in 3:
				print("    crouched, m² watching: %6d %6d %6d" % [per[r], per[3 + r], per[6 + r]])
		print("%-12s map (%.0f, %.0f): watched from %d m² standing, %d m² crouched (%d m² of it within 70 m)" % [
			ex[0], c.x + 175, c.z + 175, area_s, area_k, close_k])
		# the camp spots that see the most, a few metres apart
		spots.sort_custom(func(a, b): return a[1] * 10 + a[2] > b[1] * 10 + b[2])
		var listed := []
		for s in spots:
			if listed.size() >= 6:
				break
			if listed.any(func(l): return l.distance_to(s[0]) < 15.0):
				continue
			listed.append(s[0])
			print("    sees %d/9 standing, %d/9 crouched from map (%.0f, %.0f), %.0f m out, eye %.1f m over the square" % [s[1], s[2],
					s[0].x + 175, s[0].z + 175, Vector2(s[0].x - c.x, s[0].z - c.z).length(), s[0].y - c.y])
		if draw:
			cam.look_at_from_position(Vector3(c.x, 150, c.z), Vector3(c.x, 0, c.z), Vector3(0, 0, -1))
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var px := float(img.get_width()) / VIEW
			var half := int(STEP * px / 2.0)
			for s in spots:
				var u := int((s[0].x - c.x) * px + img.get_width() / 2.0)
				var v := int((s[0].z - c.z) * px + img.get_height() / 2.0)
				var col := Color(1, 0.1, 0.05, 0.55) if s[2] > 0 else Color(1, 0.6, 0.1, 0.4)
				for yy in range(v - half, v + half):
					for xx in range(u - half, u + half):
						if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
							img.set_pixel(xx, yy, img.get_pixel(xx, yy).blend(col))
			var r := int(2.0 * px)
			var mid := img.get_width() / 2
			for t in range(-r, r + 1):
				for w in 2:
					for p in [Vector2i(mid + t, mid - r - w), Vector2i(mid + t, mid + r + w), Vector2i(mid - r - w, mid + t), Vector2i(mid + r + w, mid + t)]:
						img.set_pixelv(p, Color(0.2, 1, 0.3))
			img.save_png("%s-%s.png" % [out, ex[0].to_lower().replace(" ", "_")])
	print("CAMP TOTAL (m² watched, all extracts): ", total)
	quit()


func _seen(space: PhysicsDirectSpaceState3D, eye: Vector3, pts: Array[Vector3]) -> int:
	var n := 0
	for p in pts:
		var q := PhysicsRayQueryParameters3D.create(eye, p)
		q.collision_mask = 1 | 32 | 64   # world, tree tops, bushes: what blocks eyes
		if space.intersect_ray(q).is_empty():
			n += 1
	return n


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float):
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.7:
		return null
	# Roofs and upper floors don't count (most can't be reached): only spots with nothing walkable right under them.
	var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position - Vector3(0, 0.3, 0),
			hit.position - Vector3(0, 30, 0)))
	if not below.is_empty() and hit.position.y - below.position.y > 1.5:
		return null
	return hit.position.y
