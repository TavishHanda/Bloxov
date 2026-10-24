@tool
class_name KeyDoor
extends StaticBody3D
## A locked door (0.14.0: the bunker and the bank vault). Hold F with its key somewhere on you (pockets, backpack or
## secure pocket) to unlock it: the key loses a use and the door swings open, for everyone in the raid and for the
## rest of the raid (online, the server opens it in its copy of the map and tells the others).
## Shut, the AI's paths go round it like a wall (it's in the nav bake), so scavs never wander into a locked room.
## Built from code: `size` is the door leaf (width, height, thickness), its origin the middle of its bottom edge.

const GROUP := &"key_doors"
const COLOR := Color(0.32, 0.34, 0.36)
## The vault door's models (art_source/scripts/make_door.py) and its hinge pin (x, z) in them.
const FRAME_MODEL := "res://assets/models/props/vault_frame.glb"
const DOOR_MODEL := "res://assets/models/props/vault_door.glb"
const PIN := Vector2(-1.35, -0.385)
## How far the vault door swings open (towards the side you walk up from).
const SWING := 100.0

## The key that opens it (an ItemDB id of kind "key" whose "door" is this node's name).
@export var key := "bunker_key"
@export var size := Vector3(2.2, 2.4, 0.12)
## Seconds of holding F to unlock it.
@export var unlock_time := 1.5

var is_open := false
var _hinge: Node3D
var _shape: CollisionShape3D
var _face: CollisionShape3D
var _swing := -100.0


func _ready() -> void:
	if Engine.is_editor_hint():   # (owner: show the vault doors in the editor) the models only, shut
		_add_models()
		return
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
	# World art 0.17 (bank thread, owner OK'd): a round vault door. A steel collar on the wall round the doorway
	# (an oval opening in it) and the round door on a hinge arm, both on the side you walk up from (-z), drawn for a
	# 2.4 m doorway and stretched to this one. It swings out towards you. The collision box above is unchanged; a
	# second one keeps people out of the door's thickness while it's shut.
	if DisplayServer.get_name() != "headless" and _add_models():
		_swing = SWING
	else:
		_build_slab()
	_face = CollisionShape3D.new()
	var face_box := BoxShape3D.new()
	face_box.size = Vector3(size.x, size.y, 0.4)
	_face.shape = face_box
	_face.position = Vector3(0, size.y * 0.5, -0.26)
	add_child(_face)


## The vault door's frame and round door (on `_hinge`), drawn for a 2.4 m doorway and stretched to this one. False
## when the models aren't there.
func _add_models() -> bool:
	if not (ResourceLoader.exists(FRAME_MODEL) and ResourceLoader.exists(DOOR_MODEL)):
		return false
	var sx := size.x / 2.4
	var sy := size.y / 2.45
	var frame: Node3D = (load(FRAME_MODEL) as PackedScene).instantiate()
	PixelModel.make_crisp(frame)
	frame.scale = Vector3(sx, sy, 1.0)
	add_child(frame)
	_hinge = Node3D.new()
	_hinge.position = Vector3(PIN.x * sx, 0, PIN.y)
	add_child(_hinge)
	var door: Node3D = (load(DOOR_MODEL) as PackedScene).instantiate()
	PixelModel.make_crisp(door)
	door.scale = Vector3(sx, sy, 1.0)
	_hinge.add_child(door)
	return true


## The plain grey slab (no models: headless, where nothing is drawn anyway).
func _build_slab() -> void:
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
	WorldSounds.own(self, WorldSounds.UNLOCK, -6.0)
	open()
	Network.main.open_door(String(name))
	return true


## Swings it open (no key needed: the server, or another player's game telling us they opened it).
func open() -> void:
	if is_open:
		return
	is_open = true
	if is_inside_tree() and not Engine.is_editor_hint():
		WorldSounds.at(self, WorldSounds.HEAVY_DOOR, global_position + Vector3.UP, -2.0, 45.0)
	_shape.set_deferred("disabled", true)
	_face.set_deferred("disabled", true)
	collision_layer = 0
	if is_inside_tree() and _hinge != null:
		create_tween().tween_property(_hinge, "rotation:y", deg_to_rad(_swing), 1.4).set_trans(Tween.TRANS_SINE)
