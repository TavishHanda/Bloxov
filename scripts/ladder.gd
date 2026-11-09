@tool
class_name Ladder
extends Area3D
## A ladder (0.13.5, reworked 0.32.1): walk straight into it or press interact to climb on (at the top: interact, or
## walk off the edge over it), W climbs the way you look (down when looking down, else up; S the other way), sprint
## slides down, Space lets go. Players only for now (the AI don't use ladders); the climbing itself is in
## player_movement.gd, the hands in climb_hands.gd.
## The origin is the foot of the ladder; it leans on whatever is behind it (-Z), climbers are on its +Z side.

## How high it goes (to the floor it leads up to).
@export var height := 4.0:
	set(value):
		height = value
		if is_inside_tree():
			_build()
@export var width := 0.6

const GROUP := &"ladders"
## The rungs: the first this high off the foot, then one every RUNG_GAP m.
const FIRST_RUNG := 0.3
const RUNG_GAP := 0.35
## How far out from the ladder's foot line the rungs are (toward the climber).
const RUNG_OUT := 0.06


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 2   # players
	monitorable = false
	_build()
	if Engine.is_editor_hint():
		return
	body_entered.connect(func(body: Node) -> void:
		if body.has_method(&"ladder_entered"):
			body.ladder_entered(self))
	body_exited.connect(func(body: Node) -> void:
		if body.has_method(&"ladder_exited"):
			body.ladder_exited(self))


## Into the ladder (toward what it leans on), flat.
func into() -> Vector3:
	var dir := -global_basis.z
	dir.y = 0.0
	return dir.normalized()


func top_y() -> float:
	return global_position.y + height


func rung_count() -> int:
	return int(floor((height + 0.2 - FIRST_RUNG) / RUNG_GAP)) + 1


## How high rung `i` is (world).
func rung_y(i: int) -> float:
	return global_position.y + FIRST_RUNG + i * RUNG_GAP


## A point on rung `i`, `x` m to the side of the middle (world).
func rung_point(i: int, x: float) -> Vector3:
	return global_transform * Vector3(x, FIRST_RUNG + i * RUNG_GAP, RUNG_OUT)


func _build() -> void:
	for child in get_children():
		child.free()
	# Where you can grab it: the ladder's front, up to a meter past the top (to climb off onto the floor above).
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + 0.3, height + 1.0, 0.8)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, (height + 1.0) * 0.5, 0.3)
	add_child(collider)
	# At the top (0.32.1): a meter in over the floor up there, so you needn't stand right on the edge to get on.
	var top := BoxShape3D.new()
	top.size = Vector3(width + 0.6, 1.4, 1.0)
	var top_collider := CollisionShape3D.new()
	top_collider.shape = top
	top_collider.position = Vector3(0, height + 0.5, -0.5)
	add_child(top_collider)
	if DisplayServer.get_name() == "headless" and not Engine.is_editor_hint():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.3, 0.2)
	material.roughness = 1.0
	for side in [-1.0, 1.0]:
		_bar(Vector3(side * width * 0.5, (height + 0.6) * 0.5, RUNG_OUT), Vector3(0.07, height + 0.6, 0.07), material)
	for i in rung_count():
		_bar(Vector3(0, FIRST_RUNG + i * RUNG_GAP, RUNG_OUT), Vector3(width, 0.05, 0.05), material)


func _bar(pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	add_child(part)
