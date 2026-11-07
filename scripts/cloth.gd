extends Node3D
## Curtains and washing that sway (0.22.0, World reacts): sheets hung by their top edge, drifting a little and pushed
## aside by whoever walks through them (assets/shaders/cloth.gdshader). Looks only: they never collided and still
## don't, and nothing is sent online. One mesh, one draw call. The generator (make_hideout.py) leaves them out of the
## model and lists them here.

const STRIDE := 7          # centre x, y, z, width, height, yaw (degrees), baked light
const SHADER := preload("res://assets/shaders/cloth.gdshader")
const ACROSS := 8          # quads across a sheet (0.28.8: 4 -> 8, so it can part round you)
const DOWN := 5            # quads down it

@export var data := PackedFloat32Array()
@export var colors := PackedColorArray()

var _material: ShaderMaterial


func _ready() -> void:
	if not Reacts.wanted(self) or data.is_empty():
		set_process(false)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, data.size(), STRIDE):
		_sheet(st, i)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	mi.material_override = _material
	add_child(mi)


func _sheet(st: SurfaceTool, i: int) -> void:
	var centre := Vector3(data[i], data[i + 1], data[i + 2])
	var w := data[i + 3]
	var h := data[i + 4]
	var turn := Basis(Vector3.UP, deg_to_rad(data[i + 5]))
	var light := data[i + 6]
	var c: Color = colors[i / STRIDE] if i / STRIDE < colors.size() else Color.WHITE
	var normal := turn.z
	for u in ACROSS:
		for v in DOWN:
			var corners: Array[Vector2] = [Vector2(u, v), Vector2(u + 1, v), Vector2(u + 1, v + 1), Vector2(u, v + 1)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var g: Vector2 = corners[k]
				var down := g.y / DOWN
				st.set_color(Color(c.r * light, c.g * light, c.b * light, down))
				st.set_uv(Vector2(g.x / ACROSS * w, down * h))   # (metres: the fabric's weave, 0.28.8)
				st.set_normal(normal)
				st.add_vertex(centre + turn * Vector3((g.x / ACROSS - 0.5) * w, h / 2.0 - down * h, 0.0))


func _process(_delta: float) -> void:
	_material.set_shader_parameter(&"pushers", Reacts.pushers(self))
	_swishes()


## A soft swish when someone pushes past a sheet (0.31.14, owner): moving, and within its width and reach of it.
const SWISH_REACH := 0.45
const SWISH_GAP := 1200     # msec, per sheet
var _swished := {}

func _swishes() -> void:
	var now := Time.get_ticks_msec()
	for m: Dictionary in Reacts.movers(self):
		var v := m.vel as Vector3
		if Vector2(v.x, v.z).length() < 0.8:
			continue
		var p := m.pos as Vector3
		for i in range(0, data.size(), STRIDE):
			var centre := Vector3(data[i], data[i + 1], data[i + 2])
			var h := data[i + 4]
			if p.y > centre.y + h / 2.0 or p.y + float(m.height) < centre.y - h / 2.0:
				continue
			var local := Basis(Vector3.UP, deg_to_rad(data[i + 5])).inverse() * (p - centre)
			if absf(local.z) > SWISH_REACH or absf(local.x) > data[i + 3] / 2.0 + 0.1:
				continue
			if now - int(_swished.get(i, -100000)) < SWISH_GAP:
				continue
			_swished[i] = now
			WorldSounds.at_soft(self, WorldSounds.CURTAIN, Vector3(p.x, centre.y, p.z), WorldSounds.CURTAIN_DB,
				WorldSounds.CURTAIN_RANGE)
