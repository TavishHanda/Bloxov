extends SceneTree
# Props you can walk through that look solid (World reacts 0.22.0): samples every model triangle at body height and
# lists the drawn bits with no collision near them, grouped into clumps, biggest first.
# godot --headless -s tools/walkthrough_audit.gd -- [map|hideout] [min_size]
# Pictures: xvfb-run -a godot --rendering-driver opengl3 -s tools/walkthrough_audit.gd -- map 0.35 <out_dir> [first] [count]
# -> <out_dir>/clumpN.png, the uncovered points drawn as red dots.
# Each line: clump size (m), centre (map metres), points, the model and its materials. Bushes, tree tops and
# windows count as covered (they're walk-through on purpose or the map draws them).
const MASK := 1 | 8 | 16 | 32 | 64 | 128 | 256 | 512
const LOW := 0.3        # body band above the floor: lower is floor clutter you step over
const HIGH := 1.75      # higher is over your head
const NEAR := 0.18      # collision closer than this counts as covering the point
const CELL := 0.35      # clump grid
var which := "map"
var min_size := 0.35
var frame := 0
var world: Node3D
var out := ""
var first := 0
var count := 40
var shots := []
var dots := PackedVector3Array()
var cam: Camera3D
var shot := -1

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: which = args[0]
	if args.size() > 1: min_size = float(args[1])
	if args.size() > 2: out = args[2]
	if args.size() > 3: first = int(args[3])
	if args.size() > 4: count = int(args[4])
	root.size = Vector2i(960, 600)
	if which == "hideout":
		world = (load("res://scenes/hideout/hideout_level.tscn") as PackedScene).instantiate()
		root.add_child(world)
		return
	world = Node3D.new()
	var map: Node = (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	for c in map.get_children():
		if String(c.name) in ["Level", "Loot", "KeyDoors", "Doors", "PlayerSpawns", "EnemySpawns"]:
			map.remove_child(c); world.add_child(c)
	map.free()
	root.add_child(world)

func _physics_process(_d: float) -> bool:
	frame += 1
	if frame < 4:
		return false
	if frame == 4:
		_audit()
		if out == "":
			return true
		_dress()
		ready_to_shoot = true
	return false

var ready_to_shoot := false
var drawn := 0

func _process(_d: float) -> bool:
	if not ready_to_shoot:
		return false
	drawn += 1
	if drawn % 4 != 0:
		return false
	if shot >= 0:
		root.get_texture().get_image().save_png("%s/clump%d.png" % [out, first + shot])
	shot += 1
	if shot >= shots.size():
		return true
	var c: Array = shots[shot]
	var sz: Vector3 = c[1]; var at: Vector3 = c[2]
	var from: Vector3 = c[6]
	var space := world.get_world_3d().direct_space_state
	var found: bool = c[3] is bool and c[3]
	for r: float in ([] if found else [2.5, 2.0, 3.2, 1.5, 4.0]):
		for j in 16:
			var o := at + Vector3(cos(TAU * j / 16.0), 0, sin(TAU * j / 16.0)) * r
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 1.0, o + Vector3.DOWN * 3.0, 1 | 128))
			if hit.is_empty() or not _walkable(hit.position):
				continue
			var eye: Vector3 = (hit.position as Vector3) + Vector3.UP * 1.6
			var los := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, at, 1 | 128 | 256))
			if los.is_empty() or (los.position as Vector3).distance_to(at) < 0.4:
				from = eye; found = true; break
		if found: break
	cam.global_transform = Transform3D(Basis.looking_at(at - from), from)
	return false

func _dress() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	world.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	cam = Camera3D.new(); cam.fov = 70; cam.far = 400; cam.near = 0.05
	world.add_child(cam); cam.current = true
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new(); box.size = Vector3.ONE * 0.05
	var red := StandardMaterial3D.new(); red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1, 0, 0); red.no_depth_test = true
	box.material = red
	mm.mesh = box; mm.instance_count = dots.size()
	for i in dots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), dots[i]))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	world.add_child(mmi)
	# what collides, see-through blue
	var faces := PackedVector3Array()
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CollisionShape3D and n.shape is ConcavePolygonShape3D and (n.get_parent() as CollisionObject3D).collision_layer & (1 | 128):
			for v in (n.shape as ConcavePolygonShape3D).get_faces(): faces.append((n as Node3D).global_transform * v)
		elif n is CollisionShape3D and n.shape is BoxShape3D:
			for v in BoxMesh.new().get_faces(): faces.append((n as Node3D).global_transform * (v * (n.shape as BoxShape3D).size))
	var am := ArrayMesh.new(); var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = faces
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var blue := StandardMaterial3D.new(); blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blue.albedo_color = Color(0.1, 0.4, 1, 0.12); blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blue.cull_mode = BaseMaterial3D.CULL_DISABLED; blue.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	am.surface_set_material(0, blue)
	var ov := MeshInstance3D.new(); ov.mesh = am; world.add_child(ov)

func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.visible and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)

func _owner_name(m: Node) -> String:
	var n := m
	while n != null and n.get_parent() != world and n.get_parent() != null:
		var p := n.get_parent()
		if String(p.name) in ["Models", "Cars", "Outdoor", "Loot", "Doors"]:
			owner_xf[String(n.name)] = (n as Node3D).global_transform
			return String(n.name)
		n = p
	return String(m.name)

const GRID := 0.6       # walk flood grid
const RISE := 0.6       # steps and stair treads you walk up (vaults and ladders aren't followed)
var walk := {}
var owner_xf := {}      # model name -> its transform (to print where a clump is in the model's own space)          # Vector3i(x, floor y / 0.5, z) -> true: floor a player can walk to from a spawn

func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x / GRID), roundi(p.y / 0.5), roundi(p.z / GRID))

## Every floor spot a body walks to from the spawns (a flood over a GRID grid), so closed-off or roof-top drawing
## isn't listed.
func _flood(space: PhysicsDirectSpaceState3D) -> void:
	var body := CapsuleShape3D.new(); body.radius = 0.3; body.height = 1.5
	var stand := PhysicsShapeQueryParameters3D.new(); stand.shape = body; stand.collision_mask = 1 | 128 | 256 | 512
	var todo: Array[Vector3] = []
	var seeds := []
	for n in world.find_children("*", "Marker3D", true, false):
		if String(n.get_parent().name) in ["PlayerSpawns", "EnemySpawns"] or String(n.name) == "Spawn":
			seeds.append((n as Node3D).global_position)
	var keys := world.get_node_or_null("KeyDoors")         # (behind a locked door: you get there with the key)
	if keys != null:
		for n: Node3D in keys.get_children():
			for side in [-1.5, 1.5]:
				seeds.append(n.global_position + n.global_basis.z * side)
				seeds.append(n.global_position + n.global_basis.x * side)
	for sp: Vector3 in seeds:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 1.0, sp + Vector3.DOWN * 5.0, 1 | 128))
		if not hit.is_empty():
			var f: Vector3 = hit.position
			f = Vector3(roundi(f.x / GRID) * GRID, f.y, roundi(f.z / GRID) * GRID)
			if not walk.has(_key(f)): walk[_key(f)] = true; todo.append(f)
	var steps := [Vector3(GRID, 0, 0), Vector3(-GRID, 0, 0), Vector3(0, 0, GRID), Vector3(0, 0, -GRID)]
	while not todo.is_empty():
		var f: Vector3 = todo.pop_back()
		for d: Vector3 in steps:
			var n := f + d
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(n + Vector3.UP * (RISE + 0.05), n + Vector3.DOWN * 1.5, 1 | 128))
			if hit.is_empty() or (hit.normal as Vector3).y < 0.6 or BoxMap.hit_from_behind(hit, Vector3.DOWN):
				continue
			var g := Vector3(n.x, (hit.position as Vector3).y, n.z)
			var k := _key(g)
			if walk.has(k):
				continue
			stand.transform = Transform3D(Basis(), (f + g) / 2.0 + Vector3.UP * (0.85 + absf(g.y - f.y) / 2.0))
			if not space.intersect_shape(stand, 1).is_empty():
				continue
			stand.transform = Transform3D(Basis(), g + Vector3.UP * 0.85)
			if not space.intersect_shape(stand, 1).is_empty():
				continue
			walk[k] = true
			todo.append(g)
	print("walkable cells: ", walk.size())
	var dump := OS.get_environment("WALK_DUMP")      # (for comparing two versions of the map: what got cut off)
	if dump != "":
		var f := FileAccess.open(dump, FileAccess.WRITE)
		for k: Vector3i in walk:
			f.store_line("%d %d %d" % [k.x, k.y, k.z])
	var before := OS.get_environment("WALK_BEFORE")   # floor that was walkable and is still clear, but cut off now
	if before != "":
		var cut := {}
		for line in FileAccess.get_file_as_string(before).split("\n", false):
			var v := line.split(" ")
			var k := Vector3i(int(v[0]), int(v[1]), int(v[2]))
			if walk.has(k):
				continue
			var at := Vector3(k.x * GRID, k.y * 0.5, k.z * GRID)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6, 1 | 128))
			if hit.is_empty():
				continue
			stand.transform = Transform3D(Basis(), (hit.position as Vector3) + Vector3.UP * 0.85)
			if space.intersect_shape(stand, 1).is_empty():
				var g := Vector3i(floori(at.x / 4.0), roundi(at.y / 2.0), floori(at.z / 4.0))
				cut[g] = cut.get(g, 0) + 1
		print("CUT OFF: %d spots" % cut.size())
		# every container and door still in reach (2.6 m from the eyes) of floor you can walk to
		var lost := 0
		for parent in ["Loot", "Doors", "KeyDoors"]:
			var holder := world.get_node_or_null(parent)
			if holder == null:
				continue
			for n: Node3D in holder.get_children():
				var p := n.global_position
				var ok := false
				for dx in range(-4, 5):
					for dz in range(-4, 5):
						for dy in range(-6, 3):
							var k := Vector3i(roundi(p.x / GRID) + dx, roundi(p.y / 0.5) + dy, roundi(p.z / GRID) + dz)
							if walk.has(k) and Vector3(k.x * GRID, k.y * 0.5 + 1.6, k.z * GRID).distance_to(p + Vector3.UP * 0.5) < 2.4:
								ok = true; break
						if ok: break
					if ok: break
				if not ok:
					lost += 1
					print("  OUT OF REACH: %s/%s at %s" % [parent, n.name, p])
		print("OUT OF REACH: %d" % lost)
		for g: Vector3i in cut:
			print("  cut off near (%d, %d, %d): %d cells" % [g.x * 4 + 2, g.y * 2, g.z * 4 + 2, cut[g]])

func _walkable(floor_at: Vector3) -> bool:
	var k := _key(floor_at)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if walk.has(k + Vector3i(dx, dy, dz)): return true
	return false

var leaves: Array[Transform3D] = []     # bush and tree-top boxes (inverse transforms to a unit cube)
var leaf_grid := {}

func _find_leaves(n: Node) -> void:
	if n is BoxMap:
		var m := n as BoxMap
		for i in range(0, m.boxes.size(), BoxMap.STRIDE):
			var ci := int(m.boxes[i + 8])
			if ci >= m.colors.size() or not (m.colors[ci].is_equal_approx(BoxMap.BUSH_COLOUR) or m.colors[ci].is_equal_approx(BoxMap.LEAVES_COLOUR)):
				continue
			var turn := Basis(Vector3.UP, deg_to_rad(m.boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(m.boxes[i + 7]))
			var size := Vector3(m.boxes[i + 3], m.boxes[i + 4], m.boxes[i + 5]) + Vector3.ONE * 0.4
			var at := m.global_transform * Vector3(m.boxes[i], m.boxes[i + 1], m.boxes[i + 2])
			var inv := Transform3D(turn * Basis.from_scale(size), at).affine_inverse()
			var gk := Vector2i(floori(at.x / 8.0), floori(at.z / 8.0))
			if not leaf_grid.has(gk): leaf_grid[gk] = []
			leaf_grid[gk].append(inv)
	for c in n.get_children():
		_find_leaves(c)

func _in_leaves(p: Vector3) -> bool:
	var gk := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for inv: Transform3D in leaf_grid.get(gk + Vector2i(dx, dz), []):
				var l := inv * p
				if absf(l.x) <= 0.5 and absf(l.y) <= 0.5 and absf(l.z) <= 0.5:
					return true
	return false

func _audit() -> void:
	var space := world.get_world_3d().direct_space_state
	_flood(space)
	var ball := SphereShape3D.new(); ball.radius = NEAR
	var q := PhysicsShapeQueryParameters3D.new(); q.shape = ball; q.collision_mask = MASK
	var body := CapsuleShape3D.new(); body.radius = 0.3; body.height = 1.5
	var stand := PhysicsShapeQueryParameters3D.new(); stand.shape = body; stand.collision_mask = 1 | 128 | 256 | 512
	_find_leaves(world)
	var meshes := []
	_meshes(world, meshes)
	var cells := {}       # Vector3i -> [count, min, max, owner, mats]
	var checked := 0
	for mi: MeshInstance3D in meshes:
		if mi.get_parent() is BoxMap or mi.name == "Ground":
			continue
		var xf := mi.global_transform
		var who := _owner_name(mi)
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var mname := mat.resource_name if mat != null else "?"
			var faces: PackedVector3Array
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n := (idx as PackedInt32Array).size() if idx != null else v.size()
			for t in range(0, n, 3):
				var a: Vector3; var b: Vector3; var c: Vector3
				if idx != null:
					a = v[idx[t]]; b = v[idx[t + 1]]; c = v[idx[t + 2]]
				else:
					a = v[t]; b = v[t + 1]; c = v[t + 2]
				a = xf * a; b = xf * b; c = xf * c
				var area := (b - a).cross(c - a).length() * 0.5
				if area < 0.002:
					continue
				var pts := [(a + b + c) / 3.0]
				if area > 0.08:
					pts.append_array([(a * 4 + b + c) / 6.0, (a + b * 4 + c) / 6.0, (a + b + c * 4) / 6.0])
				for p: Vector3 in pts:
					checked += 1
					var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.02, p + Vector3.DOWN * 4.0, 1 | 128))
					if down.is_empty():
						continue
					var h: float = p.y - (down.position as Vector3).y
					if h < LOW or h > HIGH or (down.normal as Vector3).y < 0.7 or BoxMap.hit_from_behind(down, Vector3.DOWN):
						continue
					q.transform = Transform3D(Basis(), p)
					if not space.intersect_shape(q, 1).is_empty():
						continue
					if _in_leaves(p):
						continue
					var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 30.0, 1))
					if not up.is_empty() and BoxMap.hit_from_behind(up, Vector3.UP):
						continue
					if not _walkable(down.position):
						continue
					var spot: Vector3 = (down.position as Vector3) + Vector3.UP * 1.6
					var k := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
					if not cells.has(k):
						cells[k] = [0, p, p, who, {}, spot]
					var e: Array = cells[k]
					e[0] += 1; e[1] = (e[1] as Vector3).min(p); e[2] = (e[2] as Vector3).max(p)
					(e[4] as Dictionary)[mname] = true
					dots.append(p)
	# clumps: flood-fill neighbouring cells
	var seen := {}
	var clumps := []
	for k: Vector3i in cells:
		if seen.has(k): continue
		var stack := [k]; seen[k] = true
		var cnt := 0; var lo: Vector3 = cells[k][1]; var hi: Vector3 = cells[k][2]
		var owners := {}; var mats := {}; var eye: Vector3 = cells[k][5]
		while not stack.is_empty():
			var c: Vector3i = stack.pop_back()
			var e: Array = cells[c]
			cnt += e[0]; lo = lo.min(e[1]); hi = hi.max(e[2]); owners[e[3]] = true
			for m in e[4]: mats[m] = true
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var nk := c + Vector3i(dx, dy, dz)
						if cells.has(nk) and not seen.has(nk):
							seen[nk] = true; stack.append(nk)
		var size := hi - lo
		if maxf(size.x, size.z) >= min_size and size.y >= 0.2:
			clumps.append([maxf(size.x, size.z) * size.y, size, (lo + hi) / 2.0, cnt, owners.keys(), mats.keys(), eye])
	clumps.sort_custom(func(x, y): return x[0] > y[0])
	var at_env := OS.get_environment("SHOTS_AT")      # "x,y,z;x,y,z": pictures of these spots instead of the clumps
	if at_env != "":
		count = 0
		for t in at_env.split(";", false):
			var v := t.split(",")
			var eye := Vector3(float(v[0]) + 2, float(v[1]) + 1.6, float(v[2]) + 2)
			if v.size() >= 6: eye = Vector3(float(v[3]), float(v[4]), float(v[5]))
			shots.append([0.0, Vector3(3, 1.5, 3), Vector3(float(v[0]), float(v[1]) + 0.5, float(v[2])), v.size() >= 6, [], [], eye])
	print("AUDIT %s: %d points checked, %d clumps" % [which, checked, clumps.size()])
	for c in clumps:
		var sz: Vector3 = c[1]; var at: Vector3 = c[2]
		if clumps.find(c) >= first and shots.size() < count: shots.append(c)
		var local := at
		if owner_xf.has(c[4][0]): local = (owner_xf[c[4][0]] as Transform3D).affine_inverse() * at
		print("%d: %5.2fx%4.2fx%5.2f at (%7.1f,%5.1f,%7.1f) n=%d %s %s local (%.2f,%.2f,%.2f)" % [clumps.find(c), sz.x, sz.y, sz.z, at.x, at.y, at.z, c[3], c[4], c[5], local.x, local.y, local.z])
