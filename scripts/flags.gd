extends Node3D
## Flags waving in the wind (0.26.1, owner: "that flag should have like kinda a waving animation instead of being
## stiff"): the officer's Exion flag on Bloxov Frontlines. The building model draws the pole; make_building.py lists
## the cloth (its hoist corner, size and picture) and the generator places it here. The wave is all in the shader
## (assets/shaders/flag.gdshader). Looks only: nothing collides with them, nothing is sent online and the game server
## never draws them.

const STRIDE := 6          # the hoist's top corner x, y, z, yaw (degrees: its +x flies out from the pole), width, height
const ACROSS := 18         # sheet divisions along the flag (the waves need them), and down it
const DOWN := 4
const SHADER := preload("res://assets/shaders/flag.gdshader")

@export var data := PackedFloat32Array()
@export var pictures := PackedStringArray()   # per flag: its picture (res:// path)


func _ready() -> void:
	if not Reacts.wanted(self):
		return
	var n := data.size() / STRIDE
	for i in n:
		var d := data.slice(i * STRIDE, i * STRIDE + STRIDE)
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"picture", load(pictures[i]) if i < pictures.size() else null)
		material.set_shader_parameter(&"width", d[4])
		var mi := MeshInstance3D.new()
		mi.name = "Flag%d" % i
		mi.mesh = sheet(d[4], d[5])
		mi.material_override = material
		mi.extra_cull_margin = 0.3   # (the waves reach outside the flat sheet's box)
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(d[3])), Vector3(d[0], d[1], d[2]))
		add_child(mi)
	if n > 0:
		_warm_up()


## One flag's flat sheet: from the pole (x 0) out along +x, from its top edge (y 0) down. Its picture reads the right
## way round from -z, the pole on your right (u runs from the fly end at 0 to the pole at 1), backwards from +z.
static func sheet(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for j in DOWN + 1:
		for i in ACROSS + 1:
			var s := float(i) / ACROSS
			var t := float(j) / DOWN
			st.set_uv(Vector2(1.0 - s, t))
			st.add_vertex(Vector3(s * w, -t * h, 0.0))
	for j in DOWN:
		for i in ACROSS:
			var a := j * (ACROSS + 1) + i
			var b := a + ACROSS + 1
			for k in [a, b, a + 1, a + 1, b, b + 1]:
				st.add_index(k)
	return st.commit()


## The flag's shader is built the first time it's drawn (on the web that's a little freeze, 0.17.8): draw a speck of
## it in front of the camera once, at raid start, instead of when you first walk into sight of a flag.
func _warm_up() -> void:
	for _k in 3:   # (the raid's camera comes in after the map)
		await get_tree().process_frame
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var first := get_child(0) as MeshInstance3D if get_child_count() > 0 else null
	if camera == null or first == null:
		return
	var speck := MeshInstance3D.new()
	speck.mesh = first.mesh
	speck.material_override = first.material_override
	speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	speck.scale = Vector3.ONE * 0.001
	camera.add_child(speck)
	speck.position = Vector3(0.0, 0.0, -0.5)
	get_tree().create_timer(0.5, true, false, true).timeout.connect(speck.queue_free)
