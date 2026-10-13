extends Node3D
## A dropped backpack's flap (0.17.12, owner: "make that solid green part with the grey button open up"): the
## model's own flap pieces move onto this hinge so they swing open with it.

## Model surfaces that make the flap (scav_backpack.glb: 8 = the dark green flap, 9 = its grey button).
@export var lid_surfaces: Array[int] = [8, 9]
## How far it swings open (degrees round its hinge).
@export var open_deg := 100.0


func _ready() -> void:
	var model := get_parent().get_node_or_null("Model")
	if model == null:
		return
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var body := meshes[0] as MeshInstance3D
	var hidden := StandardMaterial3D.new()
	hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden.albedo_color = Color(0, 0, 0, 0)
	for surface in lid_surfaces:
		if surface >= body.mesh.get_surface_count():
			continue
		var piece := ArrayMesh.new()
		piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body.mesh.surface_get_arrays(surface))
		piece.surface_set_material(0, body.mesh.surface_get_material(surface))
		var part := MeshInstance3D.new()
		part.mesh = piece
		add_child(part)
		part.global_transform = body.global_transform
		body.set_surface_override_material(surface, hidden)
