@tool
extends EditorScenePostImport
## Import script for the building models (assets/models/buildings/*.glb, set in their .import files by
## art_source/scripts/make_building.py): their "kit_atlas" material becomes the shared atlas shader material
## (assets/materials/kit_atlas.tres), so every building draws all its kit textures with one material.

const ATLAS_MATERIAL := "res://assets/materials/kit_atlas.tres"


func _post_import(scene: Node) -> Object:
	var material: Material = load(ATLAS_MATERIAL)
	for node in [scene] + scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var surface := mesh_instance.mesh.surface_get_material(i)
			if surface != null and surface.resource_name == "kit_atlas":
				mesh_instance.mesh.surface_set_material(i, material)
	return scene
