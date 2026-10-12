extends SceneTree
## Sightline check for Bloxov Battlegrounds (World art 0.17, owner: "you can spawn, go on a hill and kill a bunch of
## AI"). For spots on a grid over the map, counts how many points of the AI zones a standing player can see from
## there (within RANGE, through the real collision: ground, walls, cover). Writes a heat map (red = sees a lot) and
## lists the worst spots within reach of each player spawn.
##   godot --headless -s tools/sightlines.gd -- out=/tmp/sight          writes <out>.png and prints the report
##   godot --headless -s tools/sightlines.gd -- plan=40                 also picks 40 more spots for sightline
##       breakers (from tools/.cover_candidates.json, which tools/gen_old_bloxov.py writes) and adds them to
##       tools/cover_spots.json; re-run the generator to place them, then this again to check.

const STEP := 8.0          # metres between checked spots
const TARGET_STEP := 10.0  # metres between AI zone points
const RANGE := 220.0       # longest shot that counts
const EYE := 1.6
const BODY := 1.1          # aim height on an AI
const SPAWN_REACH := 70.0  # how far from a spawn counts as "right at the start"


func _initialize() -> void:
	var out := "/tmp/sight"
	var plan := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("plan="):
			plan = int(a.substr(5))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var spawns: Array[Vector3] = []
	for s in main.get_node("PlayerSpawns").get_children():
		spawns.append((s as Node3D).position)
	var map_scene: Node = (load(RaidMap.scene_path) as PackedScene).instantiate()
	var zones: Array = map_scene.get_meta("spawner")["zones"]
	map_scene.free()
	for c in main.get_children():
		if not c.name in ["WorldEnvironment", "Sun", "Level"]:
			main.remove_child(c)
			c.free()
	main.set_script(null)
	root.add_child(main)
	for i in 4:
		await physics_frame
	var space := (main as Node3D).get_world_3d().direct_space_state

	# AI zone points on the ground (open ground only: points inside buildings are hidden by walls anyway).
	var targets: Array[Vector3] = []
	for z: Dictionary in zones:
		var c: Vector3 = z["center"]
		var r: float = z["radius"]
		var x := c.x - r
		while x <= c.x + r:
			var zz := c.z - r
			while zz <= c.z + r:
				if Vector2(x - c.x, zz - c.z).length() <= r:
					var g = _ground(space, x, zz)
					if g != null:
						targets.append(Vector3(x, g + BODY, zz))
				zz += TARGET_STEP
			x += TARGET_STEP
	print("AI zone points: ", targets.size())

	var n := int(350.0 / STEP)
	var score := PackedInt32Array()
	score.resize(n * n)
	var spots := []
	for j in n:
		for i in n:
			var x := -175.0 + (i + 0.5) * STEP
			var zz := -175.0 + (j + 0.5) * STEP
			var g = _ground(space, x, zz)
			if g == null:
				continue
			var eye := Vector3(x, g + EYE, zz)
			var seen := 0
			for t in targets:
				if eye.distance_to(t) > RANGE or eye.distance_to(t) < 15.0:
					continue
				var q := PhysicsRayQueryParameters3D.create(eye, t)
				if space.intersect_ray(q).is_empty():
					seen += 1
			score[j * n + i] = seen
			spots.append([seen, eye])
	# Report: per spawn, the worst spot in reach.
	var total := 0
	for k in spawns.size():
		var best := [0, Vector3.ZERO]
		for s in spots:
			if Vector2(s[1].x - spawns[k].x, s[1].z - spawns[k].z).length() <= SPAWN_REACH and s[0] > best[0]:
				best = s
		total += best[0]
		print("Spawn%d (%.0f, %.0f): worst spot in reach sees %d AI zone points, at map (%.0f, %.0f), height %.1f" % [
			k + 1, spawns[k].x + 175, spawns[k].z + 175, best[0], best[1].x + 175, best[1].z + 175, best[1].y])
	spots.sort_custom(func(a, b): return a[0] > b[0])
	print("Worst spots on the map:")
	for s in spots.slice(0, 12):
		print("  sees %d at map (%.0f, %.0f) height %.1f" % [s[0], s[1].x + 175, s[1].z + 175, s[1].y])
	print("SIGHT TOTAL (sum of each spawn's worst): ", total)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var top := 1
	for v in score:
		top = maxi(top, v)
	for j in n:
		for i in n:
			var v := float(score[j * n + i]) / top
			img.set_pixel(i, j, Color(1, 1 - v, 1 - v, 0.15 + 0.7 * v) if v > 0 else Color(0, 0, 0, 0))
	img.resize(700, 700, Image.INTERPOLATE_NEAREST)
	img.save_png(out + ".png")
	if plan > 0:
		_plan(space, spots, spawns, targets, plan)
	quit()


## Greedy: the candidate spot whose 2.5 m high, 5 m wide breaker would cut the most views from the spots near the
## player spawns, then the next best of the views left over, and so on.
func _plan(space: PhysicsDirectSpaceState3D, spots: Array, spawns: Array[Vector3], targets: Array[Vector3], count: int) -> void:
	var cands: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/.cover_candidates.json"))
	var cpos: Array[Vector3] = []
	var cell := {}
	for c in cands:
		var g = _ground(space, c[0] - 175.0, c[1] - 175.0)
		if g == null:
			continue
		var k := cpos.size()
		cpos.append(Vector3(c[0] - 175.0, g, c[1] - 175.0))
		var key := Vector2i(floori(cpos[k].x / 4.0), floori(cpos[k].z / 4.0))
		if not cell.has(key):
			cell[key] = []
		cell[key].append(k)
	# The views that matter: from spots a fresh spawn can reach that see a lot.
	var rays := []
	for s in spots:
		if s[0] < 20:
			continue
		var near := false
		for sp in spawns:
			if Vector2(s[1].x - sp.x, s[1].z - sp.z).length() <= SPAWN_REACH:
				near = true
		if not near:
			continue
		for t in targets:
			var d: float = s[1].distance_to(t)
			if d > RANGE or d < 15.0:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(s[1], t)).is_empty():
				rays.append([s[1], t])
	print("plan: %d views to cut, %d candidate spots" % [rays.size(), cpos.size()])
	var hits := []          # per ray: candidates on it
	var by_cand := {}       # candidate -> rays
	for r in rays.size():
		var a: Vector3 = rays[r][0]
		var b: Vector3 = rays[r][1]
		var on := {}
		var steps := int(Vector2(b.x - a.x, b.z - a.z).length() / 2.0)
		for k in range(1, steps):
			var p := a.lerp(b, float(k) / steps)
			var key := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for ci in cell.get(key + Vector2i(dx, dz), []):
						var c: Vector3 = cpos[ci]
						if Vector2(p.x - c.x, p.z - c.z).length() < 2.5 and p.y - c.y < 2.4 and p.y - c.y > -0.5:
							on[ci] = true
		hits.append(on.keys())
		for ci in on:
			if not by_cand.has(ci):
				by_cand[ci] = []
			by_cand[ci].append(r)
	var alive := PackedByteArray()
	alive.resize(rays.size())
	alive.fill(1)
	var banned := {}
	var chosen := []
	for n in count:
		var best := -1
		var best_n := 0
		for ci in by_cand:
			if banned.has(ci):
				continue
			var m := 0
			for r in by_cand[ci]:
				m += alive[r]
			if m > best_n:
				best_n = m
				best = ci
		if best < 0 or best_n < 5:
			break
		var dir := Vector2.ZERO
		for r in by_cand[best]:
			if alive[r]:
				var a: Vector3 = rays[r][0]
				var b: Vector3 = rays[r][1]
				var v := Vector2(b.x - a.x, b.z - a.z).normalized()
				dir += v if v.dot(dir) >= 0 else -v
				alive[r] = 0
		dir = dir.normalized()
		var yaw := rad_to_deg(atan2(-dir.x, -dir.y))
		var c: Vector3 = cpos[best]
		chosen.append([snappedf(c.x + 175.0, 0.1), snappedf(c.z + 175.0, 0.1), snappedf(yaw, 1.0)])
		for ci in cpos.size():
			if cpos[ci].distance_to(c) < 10.0:
				banned[ci] = true
		print("  cover at map (%.0f, %.0f) cuts %d views" % [c.x + 175, c.z + 175, best_n])
	var path := "res://tools/cover_spots.json"
	var all: Array = []
	if FileAccess.file_exists(path):
		all = JSON.parse_string(FileAccess.get_file_as_string(path))
	all.append_array(chosen)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[\n" + ",\n".join(all.map(func(e): return JSON.stringify(e))) + "\n]\n")
	print("plan: %d new spots, %d in tools/cover_spots.json" % [chosen.size(), all.size()])


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float):
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	if hit.normal.y < 0.7:
		return null
	# Roofs and upper floors don't count (most can't be reached): only spots with nothing walkable right under them.
	var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position - Vector3(0, 0.3, 0),
			hit.position - Vector3(0, 30, 0)))
	if not below.is_empty() and hit.position.y - below.position.y > 1.5:
		return null
	return hit.position.y
