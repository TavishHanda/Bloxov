extends Node3D
## Blocky clouds high over the map (World art 0.17): flat slabs of big cubes, like the world is built from, drifting
## slowly with the wind. One MultiMesh (one draw call). Lit by the sun, so their undersides are shaded.
## Looks only: the server and headless runs skip it.

## How high the cloud layer sits, how big a cloud cube is, and how far out the clouds go from the map's middle.
@export var height := 120.0
@export var cube := 10.0
@export var reach := 1200.0
@export var count := 70
## Wind (meters a second along x).
@export var drift := 0.6
@export var seed_value := 7
## Set by the raid's look (`Look.cloud_color`).
@export var color := Color(0.97, 0.98, 1.0)

var _mesh_instance: MultiMeshInstance3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cells: Array[Vector3] = []
	for c in count:
		var centre := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		# A blob of cells: a few overlapping ellipses on the cube grid, a second layer over the thick middle.
		var blobs := rng.randi_range(2, 4)
		var taken := {}
		for b in blobs:
			var off := Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2))
			var rx := rng.randf_range(2.0, 5.0)
			var rz := rng.randf_range(1.5, 3.5)
			for i in range(-6, 7):
				for j in range(-5, 6):
					var d := Vector2((i - off.x) / rx, (j - off.y) / rz).length()
					if d < 1.0 and not taken.has(Vector2i(i, j)):
						taken[Vector2i(i, j)] = d
		for key: Vector2i in taken:
			var at := Vector3(centre.x + key.x * cube, height, centre.y + key.y * cube)
			cells.append(at)
			if taken[key] < 0.45:
				cells.append(at + Vector3(0, cube * 0.6, 0))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(cube, cube * 0.6, cube)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.disable_receive_shadows = true
	box.material = material
	multimesh.mesh = box
	multimesh.instance_count = cells.size()
	for k in cells.size():
		multimesh.set_instance_transform(k, Transform3D(Basis.IDENTITY, cells[k]))
	_mesh_instance = MultiMeshInstance3D.new()
	_mesh_instance.multimesh = multimesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	position.x += drift * delta
