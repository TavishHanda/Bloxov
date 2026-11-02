@tool
extends Node3D
## The map's trees (World art 0.17, outdoor step 7): broadleaf (town, farm), pine (the woods), birch, and burnt dead
## trees for the war zones, with blocky bark trunks and canopies that sway a little in the wind. Looks only: the
## generator (tools/gen_old_bloxov.py) keeps each tree's boxes for collision (the trunk) and the AI's sight (the leaves
## box, on the leaves layer), so drawing them changes nothing in a fight. Built once at load into one mesh per map
## square, so far squares are culled. Skipped headless.
## Far view (outdoor step 10): each square also gets a cheap far version (plain crowns of a few cards and one leaf block,
## no ferns), shown instead of the full trees once the square's middle is FAR_FROM away, so every tree within about
## 75 m is always the full one. The forest outside the map (FAR_PINE, FAR_BROAD) is always drawn the cheap way.
##
## `look`: 0 A blocks (layered leafy blocks), 1 B leaf cards (clumps like the bushes), 2 C blocks with leaf cards
## sticking out of them.

const CELL := 50.0
const FAR_FROM := 110.0    # (metres from a square's middle to its far version; FAR_MARGIN keeps it from flickering)
const FAR_MARGIN := 6.0
const STRIDE := 7          # x, ground y, z, trunk height, canopy width, kind (0 broadleaf, 1 pine, 2 birch, 3 dead,
                           # 4 fern, 5-7 crops: height, width), yaw
const SHADER := preload("res://assets/shaders/trees.gdshader")
const BROAD := 0
const PINE := 1
const BIRCH := 2
const DEAD := 3
const FERN := 4
const WHEAT := 5           # (outdoor step 8: the farm's crops, 5 wheat 6 maize 7 sunflowers: height, width)
const FAR_PINE := 8        # (outdoor step 9: the forest outside the map, nobody gets close: a few cards each)
const FAR_BROAD := 9
# the texture sheet's tiles (art_source/scripts/make_trees.py): 4 x 4, (column, row)
const CARD := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const BARK := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
# a card's whole tile, as _quad clamps it (uv (0, 1), (1, 1), (1, 0), (0, 0))
const CARD_UV0 := Vector2(0.004, 0.996)
const CARD_UV1 := Vector2(0.996, 0.996)
const CARD_UV2 := Vector2(0.996, 0.004)
const CARD_UV3 := Vector2(0.004, 0.004)
const FILL := [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 2)]

@export var sheet: Texture2D
@export var look := 0
@export var data := PackedFloat32Array()
## The map's tree list as its own file (0.29.8: written by the generator beside the map, `<map>_trees.tres`, with
## `data` and `look` as metadata), so the hideout can build the trees before the raid without loading the map.
@export var source: Resource

## Trees already built this session, ready to show (0.29.8): key_of(data, look) -> [[mesh, square middle, far], ...].
## Built in the hideout (`prebuild`, a bit each frame) or by the first raid; later raids reuse them.
static var _built_sets := {}
static var _builders := {}   # key -> a detached builder (this script) part-way through, from `prebuild`

# The mesh being built (0.29.3, faster loading: plain arrays with an index, four corners a quad, instead of a
# SurfaceTool's six vertices a quad; the same triangles, built about twice as fast)
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _col := PackedColorArray()
var _idx := PackedInt32Array()
var _material: ShaderMaterial
var _origin := Vector3.ZERO   # (the square being built: trees are drawn relative to its middle)
var _coarse := false          # (far version: leaf blocks and trunks in one piece a face)
var _rng := RandomNumberGenerator.new()
# Where a build is (it can stop after any tree and carry on later, 0.29.8)
var _cells := {}              # square -> its trees (data indices, in order)
var _squares: Array = []
var _square := 0
var _far_pass := 0
var _next := 0
var _made: Array = []          # [[mesh, square middle, far], ...]


func _ready() -> void:
	if source != null and data.is_empty():
		data = source.get_meta(&"data", PackedFloat32Array())
	if DisplayServer.get_name() == "headless" or sheet == null:
		return
	var material := ShaderMaterial.new()
	_material = material
	material.shader = SHADER
	material.set_shader_parameter("sheet", sheet)
	var key := key_of(data, look)
	if not _built_sets.has(key):
		var builder: Node = _builders.get(key)
		if builder == null:
			builder = self
			_start()
		builder.call(&"_build_until", 0)   # (finishes what the hideout didn't get to)
		_built_sets[key] = builder.get(&"_made")
		_builders.erase(key)
		if builder != self:
			builder.free()
	for part: Array in _built_sets[key]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = material
		mi.position = part[1]
		if part[2]:
			mi.visibility_range_begin = FAR_FROM
			mi.visibility_range_begin_margin = FAR_MARGIN
		else:
			mi.visibility_range_end = FAR_FROM
			mi.visibility_range_end_margin = FAR_MARGIN
		add_child(mi)


static func key_of(trees: PackedFloat32Array, tree_look: int) -> String:
	return "%d:%d:%d" % [hash(trees), trees.size(), tree_look]


## Builds the trees listed in `file` (a map's `_trees.tres`) for a coming raid, for about `budget_usec` per call
## (0.29.8, owner: build the trees while you're in the hideout). Returns true once there's nothing left to do.
static func prebuild(file: String, budget_usec: int) -> bool:
	if DisplayServer.get_name() == "headless" or file == "" or not ResourceLoader.exists(file):
		return true
	var list := load(file)
	var trees: PackedFloat32Array = list.get_meta(&"data", PackedFloat32Array())
	var tree_look: int = list.get_meta(&"look", 0)
	var key := key_of(trees, tree_look)
	if _built_sets.has(key) or trees.is_empty():
		return true
	var builder: Node = _builders.get(key)
	if builder == null:
		builder = (load("res://scripts/trees.gd") as GDScript).new()
		builder.set(&"data", trees)
		builder.set(&"look", tree_look)
		builder.call(&"_start")
		_builders[key] = builder
	if not builder.call(&"_build_until", Time.get_ticks_usec() + budget_usec):
		return false
	_built_sets[key] = builder.get(&"_made")
	_builders.erase(key)
	builder.free()
	return true


func _start() -> void:
	_cells = {}
	for i in range(0, data.size(), STRIDE):
		var key := Vector2i(floori(data[i] / CELL), floori(data[i + 2] / CELL))
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(i)
	_squares = _cells.keys()
	_square = 0
	_far_pass = 0
	_next = 0
	_made = []
	_begin()


## Builds trees until the clock passes `deadline` (Time.get_ticks_usec(); 0 = all of them), square by square, each
## square's full trees then its far version. True once every square is built.
func _build_until(deadline: int) -> bool:
	while _square < _squares.size():
		var key: Vector2i = _squares[_square]
		# (each square's mesh sits at its middle, so the far switch measures from there)
		_origin = Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var list: Array = _cells[key]
		while _next < list.size():
			var i: int = list[_next]
			if _far_pass:
				_coarse = true
				_tree_far(i)
			else:
				_coarse = int(data[i + 5]) >= FAR_PINE
				_tree(i)
			_next += 1
			if deadline > 0 and Time.get_ticks_usec() > deadline:
				return false
		var mesh := _commit()
		if mesh != null:
			_made.append([mesh, _origin, _far_pass == 1])
		_next = 0
		_far_pass += 1
		if _far_pass == 2:
			_far_pass = 0
			_square += 1
	return true


func _begin() -> void:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_uv = PackedVector2Array()
	_col = PackedColorArray()
	_idx = PackedInt32Array()


func _commit() -> ArrayMesh:
	if _v.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_begin()
	return mesh


## A vertex (`at + turn * c`, already worked out), and after every fourth, the quad's two triangles (0 1 2, 0 2 3).
func _corner(p: Vector3, normal: Vector3, uv: Vector2, color: Color) -> void:
	_v.append(p)
	_n.append(normal)
	_uv.append(uv)
	_col.append(color)


func _quad_done() -> void:
	var b := _v.size() - 4
	_idx.append(b)
	_idx.append(b + 1)
	_idx.append(b + 2)
	_idx.append(b)
	_idx.append(b + 2)
	_idx.append(b + 3)


func _tree(i: int) -> void:
	var world := Vector3(data[i], data[i + 1], data[i + 2])
	var at := world - _origin
	var h := data[i + 3]
	var s := data[i + 4]
	var kind := int(data[i + 5])
	var turn := Basis(Vector3.UP, deg_to_rad(data[i + 6]))
	_rng.seed = hash(Vector2(world.x, world.z))
	if kind == DEAD:
		_dead(at, turn, h)
		return
	if kind == FERN:
		_fern(at, turn, h, s)
		return
	if kind == FAR_PINE or kind == FAR_BROAD:
		_far(at, turn, h, s, kind)
		return
	if kind >= WHEAT:
		_crop(at, turn, h, s, Vector2i(kind - WHEAT, 3))
		return
	# the leaves box the generator keeps for the AI's sight: s wide, from h - 1 to h + 0.7 s
	var tall := s * 0.7 + 1.0
	var mid := Vector3(0, h - 1.0 + tall * 0.5, 0)
	match kind:
		PINE:
			_trunk(at, turn, Vector3.ZERO, h + tall * 0.75, 0.5, 0.12, BARK[PINE])
			_pine(at, turn, h, s, tall)
		BIRCH:
			var lean := Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
			_trunk(at, turn, lean, h + tall * 0.6, 0.34, 0.2, BARK[BIRCH])
			_canopy(at, turn, mid + lean, Vector3(s * 0.38, tall * 0.55, s * 0.38), BIRCH, 3)
		_:
			_trunk(at, turn, Vector3.ZERO, h + tall * 0.3, 0.62, 0.38, BARK[BROAD])
			_branches(at, turn, h - 0.6, 0.25, 2, BARK[BROAD], s * 0.3)
			_canopy(at, turn, mid, Vector3(s * 0.5, tall * 0.5, s * 0.5), BROAD, 5)


func _tree_far(i: int) -> void:
	# The same tree seen from far off (the square's far version): the same outline, a fraction of the triangles.
	var world := Vector3(data[i], data[i + 1], data[i + 2])
	var at := world - _origin
	var h := data[i + 3]
	var s := data[i + 4]
	var kind := int(data[i + 5])
	var turn := Basis(Vector3.UP, deg_to_rad(data[i + 6]))
	_rng.seed = hash(Vector2(world.x, world.z))
	match kind:
		FERN:
			return
		DEAD:
			_dead(at, turn, h)
		PINE, FAR_PINE:
			_far(at, turn, h, s, FAR_PINE)
		BROAD, FAR_BROAD:
			_far(at, turn, h, s, FAR_BROAD)
		BIRCH:
			var tall := s * 0.7 + 1.0
			var lean := Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
			_trunk(at, turn, lean, h + tall * 0.6, 0.34, 0.2, BARK[BIRCH])
			var mid := Vector3(0, h - 1.0 + tall * 0.5, 0) + lean
			_far_crown(at, turn, mid, Vector3(s * 0.38, tall * 0.55, s * 0.38), BIRCH, s * 0.27)
		_:
			_crop(at, turn, h, s, Vector2i(kind - WHEAT, 3))


# ---------------------------------------------------------------------------------------------- canopies
func _far(at: Vector3, turn: Basis, h: float, s: float, kind: int) -> void:
	# A tree out past the border, seen from afar: a plain trunk, then crossed cards (three pine tiers, or one crown of
	# leaf cards and a block of leaves inside it so it doesn't read as see-through).
	if kind == FAR_PINE:
		_trunk(at, turn, Vector3.ZERO, h * 0.6, 0.5, 0.2, BARK[PINE])
		var tall := s * 0.7 + 1.0
		var base := h - 2.6
		var top := h + tall + 0.8
		var mid := Vector3(0, (base + top) / 2, 0)
		var half := Vector3(s * 0.55, (top - base) / 2, s * 0.55)
		var step := (top - base) / 3.4
		for k in 3:
			var r := s * 0.6 * (1.0 - k / 3.4 * 0.8)
			_fronds(at, turn, base + k * step, r * 1.25, step * 1.6, mid, half, 2)
		_leaf_block(at, turn, Vector3(0, base + step * 1.4, 0), Vector3(s * 0.22, step * 1.2, s * 0.22), PINE, mid, half, 0.0)
	else:
		_trunk(at, turn, Vector3.ZERO, h * 0.75, 0.6, 0.35, BARK[BROAD])
		var tall := s * 0.7 + 1.0
		var mid := Vector3(0, h - 1.0 + tall * 0.5, 0)
		_far_crown(at, turn, mid, Vector3(s * 0.5, tall * 0.5, s * 0.5), BROAD, s * 0.35)


func _far_crown(at: Vector3, turn: Basis, mid: Vector3, half: Vector3, kind: int, card: float) -> void:
	# A block of leaves with a ring of leaf cards round it.
	_leaf_block(at, turn, mid, half * 0.7, kind, mid, half, _rng.randf_range(-20, 20))
	for k in 6:
		var a := TAU * k / 6.0
		var p := mid + Vector3(cos(a) * half.x * 0.6, _rng.randf_range(-0.2, 0.4) * half.y, sin(a) * half.z * 0.6)
		var b := Basis(Vector3.UP, a + PI / 2)
		_card(at, turn, p, b.x * card, Vector3(0, card, 0), CARD[kind], mid, half, 0.0)


func _canopy(at: Vector3, turn: Basis, mid: Vector3, half: Vector3, kind: int, parts: int) -> void:
	# A rounded crown filling `half` round `mid`: one big mass and smaller ones round and on top of it.
	var masses: Array = [[mid + Vector3(0, -half.y * 0.1, 0), half * Vector3(0.85, 0.7, 0.85)]]
	for k in parts:
		var a := TAU * k / parts + _rng.randf_range(-0.4, 0.4)
		var r := _rng.randf_range(0.35, 0.55)
		var c := mid + Vector3(cos(a) * half.x * r, _rng.randf_range(-0.25, 0.35) * half.y, sin(a) * half.z * r)
		masses.append([c, half * _rng.randf_range(0.45, 0.6)])
	masses.append([mid + Vector3(0, half.y * 0.55, 0), half * Vector3(0.5, 0.42, 0.5)])
	for m: Array in masses:
		var c: Vector3 = m[0]
		var e: Vector3 = m[1]
		match look:
			0:
				_leaf_block(at, turn, c, e, kind, mid, half, _rng.randf_range(-12, 12))
			1:
				_clump(at, turn, c, e * 1.15, kind, mid, half)
			_:
				_leaf_block(at, turn, c, e * 0.85, kind, mid, half, _rng.randf_range(-12, 12))
				_fringe(at, turn, c, e * 0.85, kind, mid, half)


func _pine(at: Vector3, turn: Basis, h: float, s: float, tall: float) -> void:
	# Tiers of branches, widest at the bottom, narrowing to a point.
	var base := h - 2.6
	var top := h + tall + 0.8
	var n := 5
	var step := (top - base) / (n + 0.6)
	var mid := Vector3(0, (base + top) / 2, 0)
	var half := Vector3(s * 0.55, (top - base) / 2, s * 0.55)
	for k in n:
		var y := base + k * step
		var r := s * 0.55 * (1.0 - float(k) / (n + 0.4) * 0.85)
		var c := Vector3(0, y + step * 0.55, 0)
		match look:
			0:
				_leaf_block(at, turn, c, Vector3(r, step * 0.62, r), PINE, mid, half, 45.0 * (k % 2))
			1:
				_fronds(at, turn, y, r * 1.25, step * 1.5, mid, half)
			_:
				_leaf_block(at, turn, c, Vector3(r * 0.8, step * 0.55, r * 0.8), PINE, mid, half, 45.0 * (k % 2))
				_fronds(at, turn, y + step * 0.1, r * 1.2, step * 1.2, mid, half, 3)
	var tip := Vector3(0, top - step * 0.3, 0)
	if look == 1:
		_fronds(at, turn, top - step * 0.9, s * 0.12, step * 1.1, mid, half, 3)
	else:
		_leaf_block(at, turn, tip, Vector3(s * 0.09, step * 0.45, s * 0.09), PINE, mid, half, 0.0)


func _fronds(at: Vector3, turn: Basis, y: float, r: float, high: float, mid: Vector3, half: Vector3, n := 4) -> void:
	# A tier as crossed upright cards through the trunk (the frond tile: drooping branches out to both sides).
	var a0 := _rng.randf() * PI
	for k in n:
		var b := Basis(Vector3.UP, a0 + PI * k / n)
		var c := Vector3(0, y + high * 0.5, 0)
		_card(at, turn, c, b.x * r, Vector3(0, high * 0.5, 0), CARD[PINE], mid, half, 1.0)
	# (and one lying flat, so it isn't see-through from above)
	var flat := Basis(Vector3.UP, a0).rotated(Vector3.UP, 0.4)
	_card(at, turn, Vector3(0, y + high * 0.55, 0), flat.x * r * 0.8, flat.z * r * 0.8, CARD[PINE], mid, half, 0.8)


func _clump(at: Vector3, turn: Basis, c: Vector3, e: Vector3, kind: int, mid: Vector3, half: Vector3) -> void:
	# Leaf cards packed in an egg, like the bushes.
	var n := int(clampf(e.x * e.z * 7.0 + 6.0, 6.0, 46.0) * (1.3 if kind == BIRCH else 1.0))
	for _k in n:
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		if d.length() > 1.0:
			d = d.normalized() * _rng.randf()
		d = d.normalized() * pow(d.length(), 0.45)
		var p := c + d * e
		var size := _rng.randf_range(0.55, 0.85) * (0.8 if kind == BIRCH else 1.0) * clampf(e.x * 0.6, 0.8, 1.4)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf() * TAU, _rng.randf_range(-0.5, 0.5)))
		_card(at, turn, p, b.x * size, b.y * size * (1.3 if kind == BIRCH else 1.0), CARD[kind], mid, half, 0.0)


func _fringe(at: Vector3, turn: Basis, c: Vector3, e: Vector3, kind: int, mid: Vector3, half: Vector3) -> void:
	# Leaf cards on a block's sides and top, half sticking out, so its outline is leafy, not straight.
	var n := int(clampf(e.x * e.z * 3.0 + 4.0, 4.0, 24.0))
	for _k in n:
		var side := _rng.randi_range(0, 4)
		var u := _rng.randf_range(-1, 1)
		var v := _rng.randf_range(-0.8, 1)
		var p: Vector3
		match side:
			0: p = c + Vector3(e.x, v * e.y, u * e.z)
			1: p = c + Vector3(-e.x, v * e.y, u * e.z)
			2: p = c + Vector3(u * e.x, v * e.y, e.z)
			3: p = c + Vector3(u * e.x, v * e.y, -e.z)
			_: p = c + Vector3(u * e.x, e.y, v * e.z)
		var size := _rng.randf_range(0.5, 0.75)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4)))
		_card(at, turn, p, b.x * size, b.y * size, CARD[kind], mid, half, 0.0)


func _leaf_block(at: Vector3, turn: Basis, c: Vector3, e: Vector3, kind: int, mid: Vector3, half: Vector3,
		yaw: float) -> void:
	# A block of dense leaves (its faces cut out at the rim), lit as part of the round crown.
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var axes := [b.x * e.x, Vector3(0, e.y, 0), b.z * e.z]
	for ax in 3:
		for sgn: float in [-1.0, 1.0]:
			var n: Vector3 = axes[ax].normalized() * sgn
			var u: Vector3 = axes[(ax + 1) % 3]
			var v: Vector3 = axes[(ax + 2) % 3]
			if ax == 0 or ax == 2:   # (side faces: u across, v up)
				u = axes[2 if ax == 0 else 0]
				v = axes[1]
			var shade := 0.62 if n.y < -0.5 else (1.0 if n.y > 0.5 else 0.88)
			_face(at, turn, c + axes[ax] * sgn, u, v, FILL[kind], mid, half, n, shade)


func _face(at: Vector3, turn: Basis, c: Vector3, u: Vector3, v: Vector3, tile: Vector2i, mid: Vector3,
		half: Vector3, n: Vector3, shade: float) -> void:
	# A face (centre, half axes), cut into pieces of at most 2 m so the 2 m tile isn't stretched.
	var nu := 1 if _coarse else maxi(1, ceili(u.length() / 1.0))
	var nv := 1 if _coarse else maxi(1, ceili(v.length() / 1.0))
	for i in nu:
		for j in nv:
			var a := -1.0 + 2.0 * i / nu
			var b := -1.0 + 2.0 * j / nv
			var p0 := c + u * a + v * b
			var du := u * (2.0 / nu)
			var dv := v * (2.0 / nv)
			var corners := [p0, p0 + du, p0 + du + dv, p0 + dv]
			var lu := minf(du.length() / 2.0, 1.0)   # (a far face stretches its tile)
			var lv := minf(dv.length() / 2.0, 1.0)
			var o := Vector2(_rng.randf_range(0, 1.0 - minf(lu, 1.0)), _rng.randf_range(0, 1.0 - minf(lv, 1.0)))
			var uvs := [o + Vector2(0, lv), o + Vector2(lu, lv), o + Vector2(lu, 0), o]
			var normal := (n * 0.55 + _out(corners[0] + du * 0.5 + dv * 0.5, mid, half) * 0.45).normalized()
			_quad(at, turn, corners, uvs, tile, normal, shade, mid, half)


func _card(at: Vector3, turn: Basis, p: Vector3, ax: Vector3, ay: Vector3, tile: Vector2i, mid: Vector3,
		half: Vector3, flat: float) -> void:
	# (written out corner by corner, the hottest part of the build: the same numbers as one _quad call with the card's
	# corners p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay and its whole tile)
	var out := _out(p, mid, half)
	var r := clampf(((p - mid) / half).length(), 0.0, 1.0)
	var shade := (0.6 + 0.4 * r) * (0.85 + 0.15 * clampf((p.y - mid.y) / half.y * 0.5 + 0.5, 0.0, 1.0))
	if flat > 0.0:
		shade = maxf(shade, 0.85)
	var nrm := turn * out
	var t := Vector2(tile)
	var bottom := mid.y - half.y
	var height := 2.0 * half.y
	var c := p - ax - ay
	var move := clampf((c.y - bottom) / height, 0.0, 1.0)
	_v.append(at + turn * c)
	_uv.append((t + CARD_UV0) / 4.0)
	_col.append(Color(shade, shade, shade, move * move))
	c = p + ax - ay
	move = clampf((c.y - bottom) / height, 0.0, 1.0)
	_v.append(at + turn * c)
	_uv.append((t + CARD_UV1) / 4.0)
	_col.append(Color(shade, shade, shade, move * move))
	c = p + ax + ay
	move = clampf((c.y - bottom) / height, 0.0, 1.0)
	_v.append(at + turn * c)
	_uv.append((t + CARD_UV2) / 4.0)
	_col.append(Color(shade, shade, shade, move * move))
	c = p - ax + ay
	move = clampf((c.y - bottom) / height, 0.0, 1.0)
	_v.append(at + turn * c)
	_uv.append((t + CARD_UV3) / 4.0)
	_col.append(Color(shade, shade, shade, move * move))
	_n.append(nrm)
	_n.append(nrm)
	_n.append(nrm)
	_n.append(nrm)
	_quad_done()


func _out(p: Vector3, mid: Vector3, half: Vector3) -> Vector3:
	# The crown's outward normal at p (it's lit like one round mass).
	return (((p - mid) / half) + Vector3(0, 0.45, 0)).normalized()


func _quad(at: Vector3, turn: Basis, corners: Array, uvs: Array, tile: Vector2i, normal: Vector3, shade: float,
		mid: Vector3, half: Vector3) -> void:
	var nrm := turn * normal
	var t := Vector2(tile)
	var bottom := mid.y - half.y
	var height := 2.0 * half.y
	for k in 4:
		var c: Vector3 = corners[k]
		var uv: Vector2 = uvs[k]
		# (sways more toward the crown's top and edges; nothing below its bottom moves)
		var move := clampf((c.y - bottom) / height, 0.0, 1.0)
		_v.append(at + turn * c)
		_n.append(nrm)
		_uv.append((t + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0)
		_col.append(Color(shade, shade, shade, move * move))
	_quad_done()


# ---------------------------------------------------------------------------------------------- trunks
func _trunk(at: Vector3, turn: Basis, lean: Vector3, top: float, w0: float, w1: float, tile: Vector2i,
		from := 0.0, ragged := false) -> void:
	# A square, tapering trunk in 1.2 m pieces (the bark tile 2 m a tile), leaning by `lean` at the top.
	var n := 1 if _coarse else maxi(1, ceili((top - from) / 1.2))
	var twist := _rng.randf() * 90.0
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var y0 := lerpf(from, top, t0)
		var y1 := lerpf(from, top, t1)
		var c0 := lean * t0 * t0 + Vector3(0, y0, 0)
		var c1 := lean * t1 * t1 + Vector3(0, y1, 0)
		var r0 := lerpf(w0, w1, t0) / 2.0
		var r1 := lerpf(w0, w1, t1) / 2.0
		var b := Basis(Vector3.UP, deg_to_rad(twist))
		for side in 4:
			var a := b * Basis(Vector3.UP, side * PI / 2)
			var e0 := a.x * r0
			var e1 := a.x * r1
			var o0 := a.z * r0
			var o1 := a.z * r1
			var corners := [c0 + o0 - e0, c0 + o0 + e0, c1 + o1 + e1, c1 + o1 - e1]
			if ragged and k == n - 1 and side % 2 == 0:   # (a snapped top: one side broken off lower)
				corners[2] -= Vector3(0, (y1 - y0) * 0.6, 0)
			var lv := minf((y1 - y0) / 2.0, 0.95)
			var lu := r0
			var v0 := fmod(y0 / 2.0, 1.0 - lv)
			var u0 := side * 0.22
			var uvs := [Vector2(u0, v0 + lv), Vector2(u0 + lu, v0 + lv), Vector2(u0 + lu, v0), Vector2(u0, v0)]
			var shade := 0.72 + 0.28 * clampf(y0 / 2.5, 0.0, 1.0)
			var nrm := turn * a.z
			for q in 4:
				var uv: Vector2 = uvs[q]
				_corner(at + turn * (corners[q] as Vector3), nrm,
					(Vector2(tile) + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0,
					Color(shade, shade, shade, 0.0))
			_quad_done()
	if ragged:
		return
	var top_c := lean + Vector3(0, top, 0)   # (a cap, in case the top is seen)
	var r := w1 / 2.0
	var b := Basis(Vector3.UP, deg_to_rad(twist))
	var cap := [top_c + (-b.x - b.z) * r, top_c + (b.x - b.z) * r, top_c + (b.x + b.z) * r, top_c + (-b.x + b.z) * r]
	for q in 4:
		_corner(at + turn * (cap[q] as Vector3), turn * Vector3.UP, (Vector2(tile) + Vector2(0.1, 0.1)) / 4.0,
			Color(0.8, 0.8, 0.8, 0.0))
	_quad_done()


func _branches(at: Vector3, turn: Basis, y: float, w: float, n: int, tile: Vector2i, reach: float) -> void:
	# Thick branches angling up and out of the trunk into the crown.
	for k in n:
		var a := TAU * k / n + _rng.randf_range(-0.6, 0.6)
		var out := Vector3(cos(a), 0, sin(a)) * reach
		var lift := _rng.randf_range(0.9, 1.4)
		var end := out + Vector3(0, lift, 0)
		_limb(at, turn, Vector3(0, y, 0), Vector3(0, y, 0) + end, w, tile, 0.0)


func _limb(at: Vector3, turn: Basis, p0: Vector3, p1: Vector3, w: float, tile: Vector2i, sway: float) -> void:
	# A square branch from p0 to p1.
	var d := (p1 - p0)
	var f := d.normalized()
	var side := f.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized() * w * 0.5
	var up := side.cross(f).normalized() * w * 0.5
	for k in 4:
		var e: Vector3 = [side, up, -side, -up][k]
		var e2: Vector3 = [up, -side, -up, side][k]
		var corners := [p0 + e - e2, p0 + e + e2, p1 + (e + e2) * 0.6, p1 + (e - e2) * 0.6]
		var lv := minf(d.length() / 2.0, 0.95)
		var uvs := [Vector2(0.3, lv), Vector2(0.3 + w / 2.0, lv), Vector2(0.3 + w / 2.0, 0), Vector2(0.3, 0)]
		var nrm := turn * e.normalized()
		for q in 4:
			var c: Vector3 = corners[q]
			var uv: Vector2 = uvs[q]
			_corner(at + turn * c, nrm, (Vector2(tile) + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0,
				Color(0.85, 0.85, 0.85, sway * float(q != 0 and q != 1)))
		_quad_done()


func _dead(at: Vector3, turn: Basis, h: float) -> void:
	# A burnt tree: a charred trunk with broken branches, snapped off short, or just a stump.
	if h < 1.5:
		_trunk(at, turn, Vector3.ZERO, h, 0.8, 0.7, BARK[DEAD], 0.0, true)
		return
	var lean := Vector3(_rng.randf_range(-0.25, 0.25), 0, _rng.randf_range(-0.25, 0.25))
	var snapped := h < 4.2
	_trunk(at, turn, lean, h, 0.6, 0.3 if not snapped else 0.45, BARK[DEAD], 0.0, snapped)
	if snapped:
		return
	for k in _rng.randi_range(2, 4):
		var y := _rng.randf_range(h * 0.45, h * 0.9)
		var a := _rng.randf() * TAU
		var ln := _rng.randf_range(1.0, 2.2)
		var p0 := lean * (y / h) * (y / h) + Vector3(0, y, 0)
		var p1 := p0 + Vector3(cos(a) * ln, _rng.randf_range(0.3, 1.1), sin(a) * ln)
		_limb(at, turn, p0, p1, 0.16, BARK[DEAD], 0.0)
		if look != 0:   # bare twigs off the branch's end
			var b := Basis(Vector3.UP, a + PI / 2)
			_card(at, turn, p1 + Vector3(0, 0.45, 0), b.x * 0.55, Vector3(0, 0.6, 0), CARD[DEAD],
				Vector3(0, h * 0.8, 0), Vector3(2, h * 0.3, 2), 0.0)


func _crop(at: Vector3, turn: Basis, h: float, w: float, tile: Vector2i) -> void:
	# A clump of crops (looks only: the field's strips keep their waist-high boxes): three crossed cards, ground to top,
	# their tops swaying.
	var mid := Vector3(0, h * 0.5, 0)
	var half := Vector3(w * 0.5, h * 0.5, w * 0.5)
	for k in 3:
		var a := PI / 3.0 * k + _rng.randf_range(-0.2, 0.2)
		var across := Vector3(cos(a), 0, sin(a)) * w * 0.5
		_card(at, turn, mid + Vector3(0, -0.02, 0), across, Vector3(0, h * 0.5, 0), tile, mid, half, 1.0)


func _fern(at: Vector3, turn: Basis, h: float, w: float) -> void:
	# A fern on the woods' floor: fronds arching out of the middle all round (looks only, no box).
	var n := _rng.randi_range(6, 9)
	var mid := Vector3(0, h * 0.4, 0)
	var half := Vector3(w * 0.5, h * 0.5, w * 0.5)
	for k in n:
		var a := TAU * k / n + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var ln := w * 0.5 * _rng.randf_range(0.8, 1.1)
		var rise := h * _rng.randf_range(0.6, 1.0)
		var tip := out * ln + Vector3(0, rise, 0)
		var across := out.cross(Vector3.UP).normalized() * w * 0.16
		var ay := tip * 0.5
		_card(at, turn, ay + Vector3(0, 0.02, 0), across, ay, Vector2i(3, 2), mid, half, 0.0)


func _process(_delta: float) -> void:
	# (0.28.7, owner: the crops move out of the way like the bushes; looks only)
	if _material != null and not Engine.is_editor_hint():
		_material.set_shader_parameter(&"pushers", Reacts.pushers(self))
