extends Node3D
## A dropped backpack's lid (0.17.11, owner: "use the textures already on the backpack"): its box wears the pack's
## own camo, and the pack's top pieces (the handle) move from the model onto the lid so they open with it.

## Model surfaces that ride on the lid (scav_backpack.glb: 1 = the grab handle on top).
@export var lid_surfaces: Array[int] = [1]
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
	var lid_box := get_node_or_null("LidMesh") as MeshInstance3D
	if lid_box != null:
		lid_box.material_override = body.mesh.surface_get_material(0)   # (the camo the pack's body wears)
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
