class_name KeyDoor
extends StaticBody3D
## A locked door (0.14.0: the bunker and the bank vault). Hold F with its key somewhere on you (pockets, backpack or
## secure pocket) to unlock it: the key loses a use and the door swings open, for everyone in the raid and for the
## rest of the raid (online, the server opens it in its copy of the map and tells the others).
## Shut, the AI's paths go round it like a wall (it's in the nav bake), so scavs never wander into a locked room.
## Built from code: `size` is the door leaf (width, height, thickness), its origin the middle of its bottom edge.

const GROUP := &"key_doors"
const COLOR := Color(0.32, 0.34, 0.36)

## The key that opens it (an ItemDB id of kind "key" whose "door" is this node's name).
@export var key := "bunker_key"
@export var size := Vector3(2.2, 2.4, 0.12)
## Seconds of holding F to unlock it.
@export var unlock_time := 1.5

var is_open := false
var _hinge: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"nav_source")
	collision_layer = 1 | 8   # world (blocks people, bullets and the AI's paths) + interactable (F)
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position.y = size.y * 0.5
	add_child(_shape)
	# The leaf hangs off a hinge on its left edge, so it can swing open.
	_hinge = Node3D.new()
	_hinge.position.x = -size.x * 0.5
	add_child(_hinge)
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.metallic = 0.6
	material.roughness = 0.5
	mesh.material = material
	leaf.mesh = mesh
	leaf.position = Vector3(size.x * 0.5, size.y * 0.5, 0)
	_hinge.add_child(leaf)
	# A brass handle on both sides, so it reads as a door.
	for side in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		var knob := BoxMesh.new()
		knob.size = Vector3(0.12, 0.12, 0.08)
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.8, 0.62, 0.25)
		knob.material = brass
		handle.mesh = knob
		handle.position = Vector3(size.x - 0.3, 1.05, side * (size.z * 0.5 + 0.04))
		_hinge.add_child(handle)


func key_name() -> String:
	return ItemDB.display_name(key) if ItemDB.ITEMS.has(key) else "a key"


## What F does here for someone carrying `inventory`.
func prompt(inventory: Inventory) -> String:
	if inventory != null and inventory.key_for(String(name)) != null:
		return "Unlock with " + key_name()
	return "Locked: needs " + key_name()


## Unlocks it with a key from `inventory` (one use off it). False if there's no key for it on them.
func unlock(inventory: Inventory) -> bool:
	if is_open:
		return false
	var stack := inventory.key_for(String(name))
	if stack == null:
		return false
	inventory.use_key(stack)
	open()
	Network.main.open_door(String(name))
	return true


## Swings it open (no key needed: the server, or another player's game telling us they opened it).
func open() -> void:
	if is_open:
		return
	is_open = true
	_shape.set_deferred("disabled", true)
	collision_layer = 0
	if is_inside_tree() and _hinge != null:
		create_tween().tween_property(_hinge, "rotation:y", deg_to_rad(-100.0), 0.6).set_trans(Tween.TRANS_SINE)
