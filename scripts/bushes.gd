@tool
extends Node3D
## The map's bushes (World art 0.17, outdoor; owner 2026-10-18: "more see-through, more 3D, sway like the grass").
## Each bush is many small cut-out leaf cards in a rounded clump (look C), some airier with twigs showing (look D);
## the leaf colour is the bush's old look (b green, c evergreen, d in flower). Looks only: the generator
## (tools/gen_old_bloxov.py) keeps each bush's box for collision and the AI's sight (big ones solid, small ones on the
## leaves layer). Built once at load into one mesh per map square, so far squares are culled. Skipped headless.

const CELL := 50.0
const STRIDE := 9          # x, bottom y, z, size x, y, z, yaw (degrees), look (0 b, 1 c, 2 d), airy (0/1)
const SHADER := preload("res://assets/shaders/bushes.gdshader")

@export var leaves: Texture2D
@export var data := PackedFloat32Array()

var _material: ShaderMaterial


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or leaves == null:
		return
	var material := ShaderMaterial.new()
	_material = material
	material.shader = SHADER
	material.set_shader_parameter("leaves", leaves)
	var cells := {}
	for i in range(0, data.size(), STRIDE):
		var key := Vector2i(floori(data[i] / CELL), floori(data[i + 2] / CELL))
		if not cells.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[key] = st
		_bush(cells[key], i)
	for key: Vector2i in cells:
		var mi := MeshInstance3D.new()
		mi.mesh = (cells[key] as SurfaceTool).commit()
		mi.material_override = material
		add_child(mi)


func _bush(st: SurfaceTool, i: int) -> void:
	var at := Vector3(data[i], data[i + 1], data[i + 2])
	var w := Vector3(data[i + 3], data[i + 4], data[i + 5])
	var turn := Basis(Vector3.UP, deg_to_rad(data[i + 6]))
	var look := int(data[i + 7])
	var airy := data[i + 8] > 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(at.x, at.z))
	var h := w.y
	var centre := Vector3(0, h * 0.45, 0)
	var area := w.x * w.z
	var n := int((9.0 if airy else 14.0) * area + 6)
	for _k in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if d.length() > 1.0:
			d = d.normalized() * rng.randf()
		var r: float = pow(d.length(), 0.55 if airy else 0.4)
		d = d.normalized() * r
		# (a point in the bush: an egg, flat underneath, filling its box)
		var p := Vector3(d.x * w.x * 0.48, maxf(0.14, h * 0.45 + d.y * h * 0.5), d.z * w.z * 0.48)
		var size := rng.randf_range(0.45, 0.75) * (0.7 + minf(w.x, w.z) * 0.15)
		var b := Basis.from_euler(Vector3(rng.randf_range(-1.2, 1.2), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
		var shade := (0.62 + 0.38 * clampf(r, 0.0, 1.0)) * (0.85 + 0.15 * clampf(p.y / h, 0.0, 1.0))
		_card(st, at, turn, p, b.x * size * 0.5, b.y * size * 0.5, centre, h, look, shade)
	if airy:   # twigs: crossed cards up the middle
		for k in 2:
			var b := Basis(Vector3.UP, k * PI / 2 + rng.randf() * 0.5)
			var tw := Vector3(0, h * 0.4, 0)
			_card(st, at, turn, tw, b.x * h * 0.45, Vector3(0, h * 0.4, 0), centre, h, 3, 0.9)


func _card(st: SurfaceTool, at: Vector3, turn: Basis, p: Vector3, ax: Vector3, ay: Vector3, centre: Vector3,
		h: float, tile: int, shade: float) -> void:
	var normal := turn * (((p - centre) * Vector3(1, 0.8, 1)) + Vector3(0, 0.35 * h, 0)).normalized()
	var corners := [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
	var u0 := tile * 0.25
	var uvs := [Vector2(u0, 1), Vector2(u0 + 0.25, 1), Vector2(u0 + 0.25, 0), Vector2(u0, 0)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		var c: Vector3 = corners[k]
		st.set_color(Color(shade, shade, shade, clampf(c.y / h, 0.0, 1.0)))
		st.set_normal(normal)
		st.set_uv(uvs[k])
		st.add_vertex(at + turn * c)


func _process(_delta: float) -> void:
	# (0.22.0, World reacts: the bushes part round whoever walks through them; looks only)
	if _material != null and not Engine.is_editor_hint():
		_material.set_shader_parameter(&"pushers", Reacts.pushers(self))
