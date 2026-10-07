extends Node3D
## Attach to an imported pixel-art model (.glb). Forces crisp "nearest" texture filtering and matte
## materials on every mesh inside it, so 16 px/m textures stay sharp instead of blurry.

func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				material.metallic = 0.0
				material.roughness = 1.0
