@tool
extends Node3D
## The map's trees (World art 0.17, outdoor step 7): broadleaf (town, farm), pine (the woods), birch, and burnt dead
## trees for the war zones, with blocky bark trunks and canopies that sway a little in the wind. Looks only: the
## generator (tools/gen_old_bloxov.py) keeps each tree's boxes for collision (the trunk) and the AI's sight (the leaves
## box, on the leaves layer), so drawing them changes nothing in a fight. Built once at load into one mesh per map
## square, so far squares are culled. Skipped headless.
##
## `look`: 0 A blocks (layered leafy blocks), 1 B leaf cards (clumps like the bushes), 2 C blocks with leaf cards
## sticking out of them.

const CELL := 50.0
const STRIDE := 7          # x, ground y, z, trunk height, canopy width, kind (0 broadleaf, 1 pine, 2 birch, 3 dead,
                           # 4 fern, 5-7 crops: height, width), yaw
const SHADER := preload("res://assets/shaders/trees.gdshader")
const BROAD := 0
const PINE := 1
const BIRCH := 2
const DEAD := 3
const FERN := 4
const WHEAT := 5           # (outdoor step 8: the farm's crops, 5 wheat 6 maize 7 sunflowers: height, width)
# the texture sheet's tiles (art_source/scripts/make_trees.py): 4 x 4, (column, row)
const CARD := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const BARK := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
const FILL := [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 2)]

@export var sheet: Texture2D
@export var look := 0
@export var data := PackedFloat32Array()

var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or sheet == null:
		return
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("sheet", sheet)
	var cells := {}
	for i in range(0, data.size(), STRIDE):
		var key := Vector2i(floori(data[i] / CELL), floori(data[i + 2] / CELL))
		if not cells.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[key] = st
		_st = cells[key]
		_tree(i)
	for key: Vector2i in cells:
		var mi := MeshInstance3D.new()
		mi.mesh = (cells[key] as SurfaceTool).commit()
		mi.material_override = material
		add_child(mi)


func _tree(i: int) -> void:
	var at := Vector3(data[i], data[i + 1], data[i + 2])
	var h := data[i + 3]
	var s := data[i + 4]
	var kind := int(data[i + 5])
	var turn := Basis(Vector3.UP, deg_to_rad(data[i + 6]))
	_rng.seed = hash(Vector2(at.x, at.z))
	if kind == DEAD:
		_dead(at, turn, h)
		return
	if kind == FERN:
		_fern(at, turn, h, s)
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


# ---------------------------------------------------------------------------------------------- canopies
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
	var nu := maxi(1, ceili(u.length() / 1.0))
	var nv := maxi(1, ceili(v.length() / 1.0))
	for i in nu:
		for j in nv:
			var a := -1.0 + 2.0 * i / nu
			var b := -1.0 + 2.0 * j / nv
			var p0 := c + u * a + v * b
			var du := u * (2.0 / nu)
			var dv := v * (2.0 / nv)
			var corners := [p0, p0 + du, p0 + du + dv, p0 + dv]
			var lu := du.length() / 2.0
			var lv := dv.length() / 2.0
			var o := Vector2(_rng.randf_range(0, 1.0 - minf(lu, 1.0)), _rng.randf_range(0, 1.0 - minf(lv, 1.0)))
			var uvs := [o + Vector2(0, lv), o + Vector2(lu, lv), o + Vector2(lu, 0), o]
			var normal := (n * 0.55 + _out(corners[0] + du * 0.5 + dv * 0.5, mid, half) * 0.45).normalized()
			_quad(at, turn, corners, uvs, tile, normal, shade, mid, half)


func _card(at: Vector3, turn: Basis, p: Vector3, ax: Vector3, ay: Vector3, tile: Vector2i, mid: Vector3,
		half: Vector3, flat: float) -> void:
	var corners := [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var out := _out(p, mid, half)
	var r := clampf(((p - mid) / half).length(), 0.0, 1.0)
	var shade := (0.6 + 0.4 * r) * (0.85 + 0.15 * clampf((p.y - mid.y) / half.y * 0.5 + 0.5, 0.0, 1.0))
	if flat > 0.0:
		shade = maxf(shade, 0.85)
	_quad(at, turn, corners, uvs, tile, out, shade, mid, half)


func _out(p: Vector3, mid: Vector3, half: Vector3) -> Vector3:
	# The crown's outward normal at p (it's lit like one round mass).
	return (((p - mid) / half) + Vector3(0, 0.45, 0)).normalized()


func _quad(at: Vector3, turn: Basis, corners: Array, uvs: Array, tile: Vector2i, normal: Vector3, shade: float,
		mid: Vector3, half: Vector3) -> void:
	for k: int in [0, 1, 2, 0, 2, 3]:
		var c: Vector3 = corners[k]
		var uv: Vector2 = uvs[k]
		# (sways more toward the crown's top and edges; nothing below its bottom moves)
		var move := clampf((c.y - (mid.y - half.y)) / (2.0 * half.y), 0.0, 1.0)
		_st.set_color(Color(shade, shade, shade, move * move))
		_st.set_normal(turn * normal)
		_st.set_uv((Vector2(tile) + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0)
		_st.add_vertex(at + turn * c)


# ---------------------------------------------------------------------------------------------- trunks
func _trunk(at: Vector3, turn: Basis, lean: Vector3, top: float, w0: float, w1: float, tile: Vector2i,
		from := 0.0, ragged := false) -> void:
	# A square, tapering trunk in 1.2 m pieces (the bark tile 2 m a tile), leaning by `lean` at the top.
	var n := maxi(1, ceili((top - from) / 1.2))
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
			var lv := (y1 - y0) / 2.0
			var lu := r0
			var v0 := fmod(y0 / 2.0, 1.0 - lv)
			var u0 := side * 0.22
			var uvs := [Vector2(u0, v0 + lv), Vector2(u0 + lu, v0 + lv), Vector2(u0 + lu, v0), Vector2(u0, v0)]
			var shade := 0.72 + 0.28 * clampf(y0 / 2.5, 0.0, 1.0)
			for q: int in [0, 1, 2, 0, 2, 3]:
				_st.set_color(Color(shade, shade, shade, 0.0))
				_st.set_normal(turn * a.z)
				var uv: Vector2 = uvs[q]
				_st.set_uv((Vector2(tile) + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0)
				_st.add_vertex(at + turn * corners[q])
	if ragged:
		return
	var top_c := lean + Vector3(0, top, 0)   # (a cap, in case the top is seen)
	var r := w1 / 2.0
	var b := Basis(Vector3.UP, deg_to_rad(twist))
	var cap := [top_c + (-b.x - b.z) * r, top_c + (b.x - b.z) * r, top_c + (b.x + b.z) * r, top_c + (-b.x + b.z) * r]
	for q: int in [0, 1, 2, 0, 2, 3]:
		_st.set_color(Color(0.8, 0.8, 0.8, 0.0))
		_st.set_normal(turn * Vector3.UP)
		_st.set_uv((Vector2(tile) + Vector2(0.1, 0.1)) / 4.0)
		_st.add_vertex(at + turn * (cap[q] as Vector3))


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
		for q: int in [0, 1, 2, 0, 2, 3]:
			var c: Vector3 = corners[q]
			_st.set_color(Color(0.85, 0.85, 0.85, sway * float(q != 0 and q != 1)))
			_st.set_normal(turn * e.normalized())
			var uv: Vector2 = uvs[q]
			_st.set_uv((Vector2(tile) + uv.clamp(Vector2(0.004, 0.004), Vector2(0.996, 0.996))) / 4.0)
			_st.add_vertex(at + turn * c)


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
