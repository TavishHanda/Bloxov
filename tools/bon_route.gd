extends SceneTree
## Bon sniping check for Bloxov Frontlines (owner 2026-11-10: "when bon roams, hes still very easy to snipe and camp
## and kill without him noticing"). Bon patrols the town hall's area and a ring just outside it, and takes trips to
## the bank. This samples the outdoor ground of that route and finds, through the real collision, the spots FAR off
## (past Bon's sight, out to RANGE) that can see someone standing on it.
##   godot --headless -s tools/bon_route.gd                                   (report)
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/bon_route.gd -- out=/tmp/bon   (+ top-down pictures)
## Score = sum over route points of the ground (m²) that sees them from MIN..RANGE out; lower = better.

const HALL := Vector2(107, 155)    # map coords (the scene is centred: minus 175)
const BANK := Vector2(150, 124)
const AREA := 32.0                 # home radius 20 + the 12 m ring outside it
const ROUTE_STEP := 4.0
const STEP := 4.0                  # metres between checked sniper spots
const MIN := 60.0                  # Bon's sight range: closer than this he can see you back
const RANGE := 160.0
const EYE := 1.6
const AIM := 1.2
var VIEW := 200.0


func _initialize() -> void:
	var out := ""
	var probe := Vector2.INF   # at=x,z (map): also lists where that route point is seen from
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("at="):
			var xz := a.substr(3).split(",")
			probe = Vector2(float(xz[0]), float(xz[1])) - Vector2(175, 175)
	var draw := DisplayServer.get_name() != "headless" and out != ""
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var keep := ["WorldEnvironment", "Sun", "Level", "Loot"] if draw else ["Level"]
	for c in main.get_children():
		if not c.name in keep:
			main.remove_child(c)
			c.free()
	main.set_script(null)
	root.add_child(main)
	for i in 4:
		await physics_frame
	var space := (main as Node3D).get_world_3d().direct_space_state
	# The route: outdoor ground near the hall, and a band along the walk to the bank.
	var route: Array[Vector3] = []
	var h := HALL - Vector2(175, 175)
	var b := BANK - Vector2(175, 175)
	var n := int(AREA / ROUTE_STEP)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := h + Vector2(i, j) * ROUTE_STEP
			if p.distance_to(h) <= AREA:
				_add_route(space, route, p)
	var seg := b - h
	for k in range(int(seg.length() / ROUTE_STEP) + 1):
		var c := h + seg.normalized() * k * ROUTE_STEP
		for w in [-6.0, -2.0, 2.0, 6.0]:
			var p: Vector2 = c + seg.normalized().orthogonal() * float(w)
			if p.distance_to(h) > AREA and p.distance_to(b) > 12.0:
				_add_route(space, route, p)
	print("route points (outdoor): ", route.size())
	# Sniper spots round it.
	var mid := (h + b) / 2.0
	var spots := {}   # Vector2i -> [eye, count]
	var exposed := PackedInt32Array()
	exposed.resize(route.size())
	var m := int((RANGE + 40.0) / STEP)
	var total := 0
	for j in range(-m, m + 1):
		for i in range(-m, m + 1):
			var p := mid + Vector2(i, j) * STEP
			var near := INF
			for r in route:
				near = minf(near, p.distance_to(Vector2(r.x, r.z)))
			if near < MIN or near > RANGE + 30:
				continue
			var g = _ground(space, p.x, p.y)
			if g == null:
				continue
			var eye := Vector3(p.x, g + EYE, p.y)
			var cnt := 0
			for ri in route.size():
				var r := route[ri]
				var d := Vector2(r.x - p.x, r.z - p.y).length()
				if d < MIN or d > RANGE:
					continue
				var q := PhysicsRayQueryParameters3D.create(eye, r + Vector3(0, AIM, 0))
				q.collision_mask = 1 | 32 | 64
				if space.intersect_ray(q).is_empty():
					cnt += 1
					exposed[ri] += 1
					if probe != Vector2.INF and Vector2(r.x, r.z).distance_to(probe) < 2.5:
						print("    (%.0f, %.0f) seen from map (%.0f, %.0f), eye %.1f m higher" % [r.x + 175, r.z + 175,
								p.x + 175, p.y + 175, eye.y - r.y - AIM])
			if cnt > 0:
				spots[Vector2i(i, j)] = [eye, cnt]
				total += cnt
	print("BON ROUTE SCORE (route point x m² of far ground that sees it): ", total * int(STEP * STEP))
	var seen := 0
	for e in exposed:
		if e > 0:
			seen += 1
	print("route points seen from 60 m+: %d / %d" % [seen, route.size()])
	# Worst sniper spots (a few, spread out), and the worst route points.
	var list := spots.values()
	list.sort_custom(func(a, c): return a[1] > c[1])
	var shown := []
	for s in list:
		if shown.size() >= 12:
			break
		if shown.any(func(l): return l.distance_to(s[0]) < 20.0):
			continue
		shown.append(s[0])
		var d: float = Vector2(s[0].x, s[0].z).distance_to(h)
		print("  sniper spot map (%.0f, %.0f) sees %d route points, %.0f m from the hall" % [s[0].x + 175, s[0].z + 175, s[1], d])
	var idx := range(route.size())
	idx.sort_custom(func(a, c): return exposed[a] > exposed[c])
	var shown2 := []
	for ri in idx:
		if shown2.size() >= 12:
			break
		var r := route[ri]
		if shown2.any(func(l): return l.distance_to(r) < 10.0):
			continue
		shown2.append(r)
		print("  route point map (%.0f, %.0f) seen from %d m²" % [r.x + 175, r.z + 175, exposed[ri] * int(STEP * STEP)])
	if draw:
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = VIEW * 2.0
		cam.far = 400
		main.add_child(cam)
		cam.current = true
		root.size = Vector2i(1000, 1000)
		cam.look_at_from_position(Vector3(mid.x, 150, mid.y), Vector3(mid.x, 0, mid.y), Vector3(0, 0, -1))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var px := float(img.get_width()) / (VIEW * 2.0)
		var best := 1
		for s in list:
			best = maxi(best, s[1])
		for s in list:
			var t: float = clampf(float(s[1]) / best, 0.15, 1.0)
			_dot(img, mid, px, Vector2(s[0].x, s[0].z), STEP, Color(1, 0.6 - 0.5 * t, 0.05, 0.25 + 0.5 * t))
		var worst := 1
		for e in exposed:
			worst = maxi(worst, e)
		for ri in route.size():
			var t := float(exposed[ri]) / worst
			var col := Color(0.2, 1, 0.3, 0.8) if exposed[ri] == 0 else Color(1, 1 - t, 1 - t, 0.9)
			_dot(img, mid, px, Vector2(route[ri].x, route[ri].z), 2.0, col)
		img.save_png(out + "-map.png")
		# A close-up of the route itself.
		cam.size = 90.0
		var hc := (h + b) / 2.0 + Vector2(-8, 6)
		cam.look_at_from_position(Vector3(hc.x, 150, hc.y), Vector3(hc.x, 0, hc.y), Vector3(0, 0, -1))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		img = root.get_texture().get_image()
		px = float(img.get_width()) / 90.0
		for ri in route.size():
			var t := float(exposed[ri]) / worst
			var col := Color(0.2, 1, 0.3, 0.7) if exposed[ri] == 0 else Color(1, 1 - t, 1 - t, 0.75)
			_dot(img, hc, px, Vector2(route[ri].x, route[ri].z), 2.4, col)
		img.save_png(out + "-route.png")
	quit()


func _add_route(space: PhysicsDirectSpaceState3D, route: Array[Vector3], p: Vector2) -> void:
	var g = _ground(space, p.x, p.y)
	if g == null:
		return
	var at := Vector3(p.x, g, p.y)
	# Not on top of something (a fountain, a car): the ground round it is about as high.
	for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		var n = _ground(space, p.x + o.x, p.y + o.y)
		if n != null and g - n > 0.4:
			return
	# Outdoors only (nothing over it), and not inside something solid.
	var up := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, 40, 0))
	up.collision_mask = 1
	if not space.intersect_ray(up).is_empty():
		return
	route.append(at)


func _dot(img: Image, centre: Vector2, px: float, at: Vector2, size: float, col: Color) -> void:
	var u := int((at.x - centre.x) * px + img.get_width() / 2.0)
	var v := int((at.y - centre.y) * px + img.get_height() / 2.0)
	var half := maxi(1, int(size * px / 2.0))
	for yy in range(v - half, v + half):
		for xx in range(u - half, u + half):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, img.get_pixel(xx, yy).blend(col))


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float):
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.7:
		return null
	var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position - Vector3(0, 0.3, 0),
			hit.position - Vector3(0, 30, 0)))
	if not below.is_empty() and hit.position.y - below.position.y > 1.5:
		return null
	return hit.position.y
