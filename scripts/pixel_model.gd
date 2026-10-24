class_name PixelModel
extends Node3D
## Attach to an imported pixel-art model (.glb). Forces crisp "nearest" texture filtering and matte
## materials on every mesh inside it, so 16 px/m textures stay sharp instead of blurry.
## Outfits: nodes named "Slot__option" (or "Slot__option__L"/"__R", e.g. both pant legs) are alternatives.
## One option per slot is shown at random, the rest are hidden (see art_source/scripts/make_character.py).

@export var randomize_outfit := true

## slot -> the option that is showing, e.g. {"Hat": "ushanka", "Top": "tracksuit_blue"}.
var outfit := {}
## merge_parts: the meshes made, and the parts they stand in for (hidden while merged).
var _merged: Array[MeshInstance3D] = []
var _merged_from: Array[MeshInstance3D] = []


func _ready() -> void:
	FarView.attach(self)
	make_crisp(self)
	if randomize_outfit:
		pick_outfit()


## Crisp texture filtering and matte materials on every mesh under `root`.
static func make_crisp(root: Node) -> void:
	for node in [root] + root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				material.metallic = 0.0
				material.roughness = 1.0


## Stops drawing every mesh under `root` (and its shadow) past `metres`: small props a few pixels tall out there
## each cost a draw call or more (doors and loot were a quarter of the far view's draw calls, 0.18.11).
static func hide_beyond(root: Node, metres: float) -> void:
	for node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if node is GeometryInstance3D:
			node.visibility_range_end = metres


## Like hide_beyond (`outside` metres), but once the map's collision is up, something with a roof over it at every one
## of `spots` (offsets from it, in its own space) stops drawing at `inside` metres instead (0.18.12): from farther,
## you'd only see it through a doorway or window, and you see the building's far model then anyway.
static func hide_beyond_roofed(root: Node3D, outside: float, inside: float, spots: Array[Vector3] = [Vector3.ZERO]) -> void:
	hide_beyond(root, outside)
	if DisplayServer.get_name() == "headless":
		return
	await root.get_tree().physics_frame
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	if spots.all(func(spot: Vector3) -> bool: return roofed(root, root.global_transform * spot)):
		hide_beyond(root, inside)


## Whether there's world (layer 1) overhead, within 15 m above `at`.
static func roofed(node: Node3D, at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.UP * 15.0, 1)
	return not node.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Shows one random option per outfit slot (or the given ones) and hides the rest.
func pick_outfit(choices := {}) -> void:
	var was_merged := not _merged.is_empty()
	unmerge_parts()
	var slots := outfit_slots()
	outfit.clear()
	for slot: String in slots:
		var options: Dictionary = slots[slot]
		var pick: String = choices.get(slot, options.keys().pick_random())
		outfit[slot] = pick
		for option: String in options:
			for node: Node3D in options[option]:
				node.visible = option == pick
	if was_merged:
		merge_parts()


## Fewer draw calls (0.18.12): the parts showing that move together (the same parent: the body, a leg) and share a
## material become one mesh, e.g. a scav's head, hat, top, vest and gloves. Each part was a draw call of its own (and
## two more for its shadow). Leaves out "Gun" (swapped for the gun it holds) and anything with children.
## Picking another outfit undoes it and merges again.
func merge_parts() -> void:
	unmerge_parts()
	var groups := {}    # [parent, material] -> parts
	for node in find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.name == &"Gun" or part.get_child_count() > 0 or not part.is_visible_in_tree() or part.mesh == null \
				or part.mesh.get_surface_count() != 1 or part.material_override != null:
			continue
		var key := [part.get_parent(), part.mesh.surface_get_material(0)]
		groups.get_or_add(key, []).append(part)
	for key: Array in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var parent := key[0] as Node3D
		var tool := SurfaceTool.new()
		for part: MeshInstance3D in parts:
			tool.append_from(part.mesh, 0, part.transform)
		tool.set_material(key[1])
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = tool.commit()
		var first := parts[0] as MeshInstance3D
		merged.cast_shadow = first.cast_shadow
		merged.visibility_range_end = first.visibility_range_end
		parent.add_child(merged)
		_merged.append(merged)
		for part: MeshInstance3D in parts:
			part.visible = false
			_merged_from.append(part)


func unmerge_parts() -> void:
	for merged in _merged:
		if is_instance_valid(merged):
			merged.queue_free()
			merged.get_parent().remove_child(merged)
	for part in _merged_from:
		if is_instance_valid(part):
			part.visible = true
	_merged.clear()
	_merged_from.clear()


## Picks the outfit from a seed, so every machine that uses the same seed shows the same outfit (online enemies).
func pick_outfit_seeded(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var choices := {}
	var slots := outfit_slots()
	var names := slots.keys()
	names.sort()
	for slot: String in names:
		var options: Array = slots[slot].keys()
		options.sort()
		choices[slot] = options[rng.randi_range(0, options.size() - 1)]
	pick_outfit(choices)


## {slot: {option: [nodes]}} for every node named "Slot__option" or "Slot__option__side".
func outfit_slots() -> Dictionary:
	var slots := {}
	for node in find_children("*__*", "Node3D", true, false):
		var parts := String(node.name).split("__")
		var options: Dictionary = slots.get_or_add(parts[0], {})
		var nodes: Array = options.get_or_add(parts[1], [])
		nodes.append(node)
	return slots
