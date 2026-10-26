extends Node3D
## Cans and bottles you can kick about (0.22.0, World reacts): the ones in the litter by the roads. Walk into one
## and it skitters off the way you were going; a shot next to it or a blast sends it flying. Looks only: each client
## kicks its own (they start in the same places and drift apart), nothing collides with them, nothing is sent online
## and the game server never runs this. Drawn as two MultiMeshes (cans, bottles): two draw calls for the whole map.
## The generator (tools/gen_old_bloxov.py, from make_outdoor.py's list) writes `data`.

const STRIDE := 5          # x, ground y, z, yaw (degrees), kind (0 can, 1 bottle)
const RADIUS := [0.035, 0.04]
const LENGTH := [0.12, 0.28]
const CELL := 4.0          # the grid that finds the cans near someone
const KICK_REACH := 0.4    # how close to a can your feet have to come
const GRAVITY := 9.8
const WORLD_MASK := 1

@export var data := PackedFloat32Array()
@export var colors := PackedColorArray()

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var _turn: Array[Basis] = []
var _spin := PackedVector3Array()      # axis * radians a second, while tumbling
var _kind := PackedInt32Array()
var _slot := PackedInt32Array()        # its number in its kind's MultiMesh
var _grid := {}                        # Vector2i -> Array of indices (where they lie now)
var _awake := {}
var _meshes: Array[MultiMesh] = []


func _ready() -> void:
	var counts := [0, 0]
	for i in range(0, data.size(), STRIDE):
		var k := int(data[i + 4])
		_kind.append(k)
		_slot.append(counts[k])
		counts[k] += 1
		pos.append(Vector3(data[i], data[i + 1] + RADIUS[k], data[i + 2]))
		vel.append(Vector3.ZERO)
		_spin.append(Vector3.ZERO)
		_turn.append(Basis(Vector3.UP, deg_to_rad(data[i + 3])) * Basis(Vector3.RIGHT, PI / 2))
		_file(_kind.size() - 1)
	if not Reacts.wanted(self):
		set_physics_process(false)
		return
	add_to_group(Reacts.GROUP)
	for k in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = RADIUS[k] * (0.45 if k == 1 else 1.0)   # (a bottle narrows to its neck)
		mesh.bottom_radius = RADIUS[k]
		mesh.height = LENGTH[k]
		mesh.radial_segments = 6
		mesh.rings = 0
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.6 if k == 0 else 0.2
		mesh.material = material
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = counts[k]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes.append(mm)
	for i in _kind.size():
		_meshes[_kind[i]].set_instance_color(_slot[i], colors[i] if i < colors.size() else Color.GRAY)
		_place(i)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _file(i: int) -> void:
	var c := _cell(pos[i])
	if not _grid.has(c):
		_grid[c] = []
	(_grid[c] as Array).append(i)


func _unfile(i: int) -> void:
	var c := _cell(pos[i])
	if _grid.has(c):
		(_grid[c] as Array).erase(i)


## The cans and bottles within `reach` of `at` (across).
func near(at: Vector3, reach: float) -> Array[int]:
	var out: Array[int] = []
	var c := _cell(at)
	var n := ceili(reach / CELL)
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), []):
				if Vector2(pos[i].x - at.x, pos[i].z - at.z).length() < reach and absf(pos[i].y - at.y) < reach + 1.0:
					out.append(i)
	return out


## Sends can `i` off at `velocity`, tumbling.
func kick(i: int, velocity: Vector3) -> void:
	vel[i] = velocity
	var across := Vector3(velocity.z, 0.0, -velocity.x)
	if across.length() > 0.01:
		_spin[i] = across.normalized() * clampf(velocity.length() * 6.0, 2.0, 25.0)
	if not _awake.has(i):
		_unfile(i)
		_awake[i] = true


func on_shot(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	for i in near(to, 0.5):
		if pos[i].distance_to(to) < 0.5:
			kick(i, Vector3(dir.x, 0.0, dir.z) * 2.5 + Vector3(randf_range(-0.6, 0.6), 2.6, randf_range(-0.6, 0.6)))


func on_blast(at: Vector3, radius: float) -> void:
	for i in near(at, radius * 1.6):
		var d := pos[i] - at
		var f := 1.0 - d.length() / (radius * 1.6)
		if f > 0.0:
			var flat := Vector3(d.x, 0.0, d.z).normalized()
			kick(i, flat * 9.0 * f + Vector3(0.0, 4.0 + 5.0 * f, 0.0))


func _physics_process(delta: float) -> void:
	for m: Dictionary in Reacts.movers(self):
		var v := m.vel as Vector3
		var flat := Vector3(v.x, 0.0, v.z)
		if flat.length() < 1.0:
			continue   # (standing still, or creeping: you step round it)
		var feet := m.pos as Vector3
		for i in near(feet, KICK_REACH):
			if pos[i].y < feet.y + 0.5:
				kick(i, flat * randf_range(0.9, 1.4) + Vector3(randf_range(-0.5, 0.5), randf_range(0.8, 1.8), randf_range(-0.5, 0.5)))
	if _awake.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i: int in _awake.keys():
		_step(i, delta, space)


func _step(i: int, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var r: float = RADIUS[_kind[i]]
	vel[i].y -= GRAVITY * delta
	var from := pos[i]
	var to := from + vel[i] * delta
	# Walls: bounce off what it would fly into.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * r, WORLD_MASK))
	if not hit.is_empty() and (hit.normal as Vector3).y < 0.6:
		var n := hit.normal as Vector3
		vel[i] = vel[i].bounce(n) * 0.45
		to = (hit.position as Vector3) + n * (r + 0.01)
	# The ground: land, bounce a little, roll to a stop.
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(to + Vector3.UP * 0.4, to - Vector3.UP * (r + 0.05), WORLD_MASK))
	var landed := false
	if not down.is_empty() and to.y - r <= (down.position as Vector3).y + 0.01:
		to.y = (down.position as Vector3).y + r
		if vel[i].y < -1.2:
			vel[i].y = -vel[i].y * 0.3
		else:
			vel[i].y = 0.0
			landed = true
		var flat := Vector2(vel[i].x, vel[i].z).move_toward(Vector2.ZERO, 3.0 * delta)   # (rolling to a stop)
		vel[i].x = flat.x
		vel[i].z = flat.y
		_spin[i] *= 0.9
	elif down.is_empty() and to.y < -50.0:
		vel[i] = Vector3.ZERO   # (fell off the world somehow: stop)
		landed = true
	pos[i] = to
	if _spin[i].length() > 0.01:
		_turn[i] = Basis(_spin[i].normalized(), _spin[i].length() * delta) * _turn[i]
	if landed and Vector2(vel[i].x, vel[i].z).length() < 0.05:
		# At rest: lying on its side again, wherever it ended up facing.
		var axis := _turn[i].y
		var yaw := atan2(axis.x, axis.z)
		_turn[i] = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI / 2)
		vel[i] = Vector3.ZERO
		_spin[i] = Vector3.ZERO
		_awake.erase(i)
		_file(i)
	_place(i)


func _place(i: int) -> void:
	if _meshes.is_empty():
		return
	_meshes[_kind[i]].set_instance_transform(_slot[i], Transform3D(_turn[i], pos[i]))
