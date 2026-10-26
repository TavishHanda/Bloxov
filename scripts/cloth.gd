extends Node3D
## Curtains and washing that sway (0.22.0, World reacts): sheets hung by their top edge, drifting a little and pushed
## aside by whoever walks through them (assets/shaders/cloth.gdshader). Looks only: they never collided and still
## don't, and nothing is sent online. One mesh, one draw call. The generator (make_hideout.py) leaves them out of the
## model and lists them here.

const STRIDE := 7          # centre x, y, z, width, height, yaw (degrees), baked light
const SHADER := preload("res://assets/shaders/cloth.gdshader")
const ACROSS := 4          # quads across a sheet
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
				st.set_normal(normal)
				st.add_vertex(centre + turn * Vector3((g.x / ACROSS - 0.5) * w, h / 2.0 - down * h, 0.0))


func _process(_delta: float) -> void:
	_material.set_shader_parameter(&"pushers", Reacts.pushers(self))
