@tool
class_name Door
extends StaticBody3D
## An ordinary door in a doorway (World art 0.17, owner: "we need to add doors to the game"). Press F to open or shut
## it; it swings away from whoever opens it. The AI open a shut door when they walk up to it (and leave it open).
## Shut, it stops people and the AI's eyes, but not bullets or grenades (a thin door: shots go through).
## Online the server owns it: a player asks, the server swings its copy and tells everyone in the raid; the AI's
## doors open on the server the same way.
## Doorways stay open in the AI's navigation (the door isn't in the nav bake), so their paths go through it.
## Built from code: `size` is the doorway (width, height); two leaves when it's wide (a double door).

const GROUP := &"doors"
## Collision layer 5 (bit value 16): people and the AI bump into it, the AI can't see through it; bullets ignore it.
const LAYER := 16
const SWING := 95.0
const SWING_TIME := 0.35
const MODEL := "res://assets/models/props/door_%s.glb"
const HIDE_BEYOND := 150.0    # metres: past this a door is a few pixels tall, not worth its draw calls
const HIDE_INDOORS := 40.0    # ... and a door with a roof on both sides (inside a building) past this (0.18.12)
## Where to look for a roof: a metre in front of the doorway and a metre behind it.
const SIDES: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1)]

## Swung open (1 or -1: which way) or shut (0). Changed with set_state (everyone's copy agrees online).
signal changed(state: int)

@export var size := Vector2(2.0, 2.4)
## The leaf's look: "wood" or "metal" (a model in assets/models/props).
@export var look := "wood"
## A wrecked door (World art round 3, owner: "not every doorway needs a door"): "" works; "fallen" = its leaf
## lies on the floor beside the doorway; "hanging" = it hangs open off one hinge. A wrecked door is only a picture:
## no collision, no F, the AI walk straight through (tools/gen_old_bloxov.py picks which doorways get one).
@export var broken := ""

var state := 0
var _hinges: Array[Node3D] = []
## Each leaf's collision box (direct children of the body, as physics needs) and where it sits on its hinge.
var _shapes: Array[CollisionShape3D] = []
var _shape_offsets: Array[Vector3] = []
var _tween: Tween


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_preview()
		return
	if broken != "":
		_build_wreck(DisplayServer.get_name() != "headless")
		_draw_less()
		return
	add_to_group(GROUP)
	collision_layer = LAYER | 8   # 8: interactable (F)
	collision_mask = 0
	var leaves := 2 if size.x > 1.5 else 1
	var leaf_w := size.x / leaves
	for k in leaves:
		var side := -1.0 if k == 0 else 1.0       # hinge on the left edge (and the right one for the second leaf)
		var hinge := Node3D.new()
		hinge.position.x = side * size.x * 0.5
		add_child(hinge)
		_hinges.append(hinge)
		var middle := Vector3(-side * leaf_w * 0.5, size.y * 0.5, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(leaf_w - 0.02, size.y - 0.02, 0.06)
		shape.shape = box
		add_child(shape)
		_shapes.append(shape)
		_shape_offsets.append(middle)
		_add_leaf_model(hinge, middle, leaf_w, side)
	var sensor := Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 4      # the AI
	var zone := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(size.x + 0.4, size.y, 2.4)
	zone.shape = zone_box
	zone.position.y = size.y * 0.5
	sensor.add_child(zone)
	add_child(sensor)
	sensor.body_entered.connect(_on_ai_near)
	_place_shapes()
	set_physics_process(false)
	_draw_less()


## In the Godot editor (the script is @tool for this only): draw the shut leaves, so doors show in the editor too.
## Nothing here is saved into the scene.
func _editor_preview() -> void:
	set_physics_process(false)
	if broken != "":
		_build_wreck(true)
		return
	var path := MODEL % look
	if not ResourceLoader.exists(path):
		return
	var leaves := 2 if size.x > 1.5 else 1
	var leaf_w := size.x / leaves
	for k in leaves:
		var side := -1.0 if k == 0 else 1.0
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.scale = Vector3(leaf_w, size.y / 2.0, 1.0)
		model.position = Vector3(side * size.x * 0.5 - side * leaf_w * 0.5, size.y * 0.5, 0)
		if side > 0:
			model.rotation.y = PI
		add_child(model)


## A wrecked door's leaves: lying on the floor or hanging off a hinge (the same picture on every game: the random
## numbers come from where the door is). Each leaf of a double door may be gone instead, but one always shows.
func _build_wreck(with_model: bool) -> void:
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var path := MODEL % look
	if not with_model or not ResourceLoader.exists(path):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0)))
	var leaves := 2 if size.x > 1.5 else 1
	var leaf_w := size.x / leaves
	var keep := rng.randi_range(0, leaves - 1)
	for k in leaves:
		if k != keep and rng.randf() < 0.5:
			continue                                # torn off and gone
		var side := -1.0 if k == 0 else 1.0
		var model: Node3D = (load(path) as PackedScene).instantiate()
		if not Engine.is_editor_hint():
			PixelModel.make_crisp(model)
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.add_child(model)
		model.scale = Vector3(leaf_w, size.y / 2.0, 1.0)
		if side > 0:
			model.rotation.y = PI
		if broken == "fallen":
			# Flat on the floor on one side of the doorway, its top towards the room.
			var away := 1.0 if rng.randf() < 0.5 else -1.0
			pivot.position = Vector3(side * leaf_w * 0.5 + rng.randf_range(-0.3, 0.3), 0.03,
				away * (size.y * 0.5 + rng.randf_range(0.15, 0.45)))
			pivot.rotation.y = rng.randf_range(-0.35, 0.35) + (0.0 if away < 0.0 else PI)
			model.rotation.x = -PI / 2.0
		else:
			# Swung open against one side, sagging off its broken top hinge.
			pivot.position = Vector3(side * size.x * 0.5, 0.0, 0.0)
			pivot.rotation.y = deg_to_rad(rng.randf_range(65.0, 100.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			model.position = Vector3(-side * leaf_w * 0.5, size.y * 0.5 - 0.06, 0.0)
			model.rotation.z = side * deg_to_rad(rng.randf_range(6.0, 13.0))


func _physics_process(_delta: float) -> void:
	_place_shapes()
	if _tween == null or not _tween.is_running():
		set_physics_process(false)


## The leaves' collision boxes follow their hinges (while a leaf swings).
func _place_shapes() -> void:
	for k in _shapes.size():
		_shapes[k].transform = _hinges[k].transform * Transform3D(Basis.IDENTITY, _shape_offsets[k])


func _add_leaf_model(hinge: Node3D, middle: Vector3, leaf_w: float, side: float) -> void:
	var path := MODEL % look
	var model: Node3D = null
	if DisplayServer.get_name() != "headless" and ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
		PixelModel.make_crisp(model)
		# The model is a 1 m x 2 m leaf, its handle on +x: stretch it to the leaf, handle away from the hinge.
		model.scale = Vector3(leaf_w, size.y / 2.0, 1.0)
		if side > 0:
			model.rotation.y = PI
	else:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(leaf_w - 0.02, size.y - 0.02, 0.05)
		mesh_instance.mesh = mesh
		model = mesh_instance
	model.position = middle
	hinge.add_child(model)


## Fewer draw calls (0.18.12, owner: "the whole game just feels kinda laggy"): doors were the biggest share of a
## frame's. No shadow (a door sits in its wall's shadow anyway, and each shadow is two more draw calls), and it stops
## drawing far out, sooner inside a building.
func _draw_less() -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	PixelModel.hide_beyond_roofed(self, HIDE_BEYOND, HIDE_INDOORS, SIDES)


func is_open() -> bool:
	return state != 0


## What F does here.
func prompt() -> String:
	return "Close door" if is_open() else "Open door"


## A player pressed F on it from `from` (where they stand). Offline it swings now; online the server decides.
func use(from: Vector3) -> void:
	var want := 0 if is_open() else _away_from(from)
	if Network.main.in_online_raid():
		Network.main.use_door(String(name), want)
	set_state(want)


## The AI walked up to it: open it away from them (offline, or on the server; players' copies wait to be told).
func _on_ai_near(body: Node3D) -> void:
	if is_open() or Network.main.in_online_raid():
		return
	set_state(_away_from(body.global_position))


## Opens it the side away from `from` (1 or -1).
func _away_from(from: Vector3) -> int:
	return 1 if to_local(from).z > 0.0 else -1


## Shut (0) or open one way (1, -1).
func set_state(new_state: int) -> void:
	new_state = clampi(new_state, -1, 1)
	if new_state == state:
		return
	state = new_state
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel() if is_inside_tree() else null
	for k in _hinges.size():
		var hinge := _hinges[k]
		# Both leaves of a double door swing to the same side.
		var angle := deg_to_rad(SWING) * float(state) * (1.0 if k == 0 else -1.0)
		if _tween != null:
			_tween.tween_property(hinge, "rotation:y", angle, SWING_TIME).set_trans(Tween.TRANS_SINE)
		else:
			hinge.rotation.y = angle
	if _tween != null:
		set_physics_process(true)
	elif not _shapes.is_empty():
		_place_shapes()
	changed.emit(state)
