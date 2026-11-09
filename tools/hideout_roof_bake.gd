extends SceneTree
## Bakes where the hideout's roofs are (lively hideout): for each 1 m square of the cave, the heights of up to four
## ceilings above it (the vault, the catwalk, a tunnel's roof...), lowest first. HideoutWar drops grit off the roof
## from it when a shell lands up top (the roof has no collision to ray-cast against, and the model is 80k triangles:
## too slow to search while you play). Re-run after rebuilding the hideout model (make_hideout.py):
##   godot --headless -s tools/hideout_roof_bake.gd
const OUT := "res://assets/hideout/roof.res"
const CELL := 1.0
const NONE := 999.0


func _initialize() -> void:
	var model := (load("res://assets/models/buildings/hideout.glb") as PackedScene).instantiate()
	var meshes: Array[TriangleMesh] = []
	var box := AABB()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var faces := mi.mesh.get_faces()
		var xf := mi.transform   # (the glb's meshes sit at the root; children of children would need the full chain)
		for i in faces.size():
			faces[i] = xf * faces[i]
		var tm := TriangleMesh.new()
		tm.create_from_faces(faces)
		meshes.append(tm)
		box = mi.get_aabb() if box.size == Vector3.ZERO else box.merge(xf * mi.get_aabb())
	var x0 := floorf(box.position.x)
	var z0 := floorf(box.position.z)
	var w := int(ceilf(box.end.x - x0) / CELL)
	var h := int(ceilf(box.end.z - z0) / CELL)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBAF)
	var found := 0
	for zi in h:
		for xi in w:
			var p := Vector3(x0 + (xi + 0.5) * CELL, box.position.y - 1.0, z0 + (zi + 0.5) * CELL)
			var roofs: Array[float] = []
			var y := p.y
			while roofs.size() < 4 and y < box.end.y:
				var best := INF
				var best_normal := Vector3.ZERO
				for tm in meshes:
					var hit := tm.intersect_ray(Vector3(p.x, y, p.z), Vector3.UP)
					if not hit.is_empty() and (hit["position"] as Vector3).y < best:
						best = (hit["position"] as Vector3).y
						best_normal = hit["normal"]
				if best == INF:
					break
				# A face looking down (a ceiling) with room under it.
				if best_normal.y < -0.3 and (roofs.is_empty() or best - roofs[-1] > 1.8):
					roofs.append(best)
				y = best + 0.05
			var c := Color(NONE, NONE, NONE, NONE)
			for k in mini(roofs.size(), 4):
				c[k] = roofs[k]
			if not roofs.is_empty():
				found += 1
			image.set_pixel(xi, zi, c)
	image.set_meta(&"origin", Vector2(x0, z0))
	image.set_meta(&"cell", CELL)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := ResourceSaver.save(image, OUT)
	print("hideout_roof_bake: %dx%d cells, %d with roofs -> %s (%s)" % [w, h, found, OUT, error_string(err)])
	model.free()
	quit(0 if err == OK else 1)
