class_name PixelModel
extends Node3D
## Attach to an imported pixel-art model (.glb). Forces crisp "nearest" texture filtering and matte
## materials on every mesh inside it, so 16 px/m textures stay sharp instead of blurry.
## Outfits: nodes named "Slot__option" (or "Slot__option__L"/"__R", e.g. both pant legs) are alternatives.
## One option per slot is shown at random, the rest are hidden (see art_source/scripts/make_character.py).

@export var randomize_outfit := true
## Recolors this one character. Currently unused (Raiders have had their own model since 0.7.10). Applied as
## per-instance material overrides, so the shared model file and other characters using it are untouched.
@export var tint := Color.WHITE

## slot -> the option that is showing, e.g. {"Hat": "ushanka", "Top": "tracksuit_blue"}.
var outfit := {}


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
	# Purely visual; skipped without a screen (the headless test renderer errors on per-instance material overrides).
	if tint != Color.WHITE and DisplayServer.get_name() != "headless":
		_apply_tint()
	if randomize_outfit:
		pick_outfit()


func _apply_tint() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material != null:
				var tinted := material.duplicate() as BaseMaterial3D
				tinted.albedo_color = material.albedo_color * tint
				mesh_instance.set_surface_override_material(i, tinted)


## Shows one random option per outfit slot (or the given ones) and hides the rest.
func pick_outfit(choices := {}) -> void:
	var slots := outfit_slots()
	outfit.clear()
	for slot: String in slots:
		var options: Dictionary = slots[slot]
		var pick: String = choices.get(slot, options.keys().pick_random())
		outfit[slot] = pick
		for option: String in options:
			for node: Node3D in options[option]:
				node.visible = option == pick


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
