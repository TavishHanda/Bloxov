@tool
class_name Ladder
extends Area3D
## A ladder (0.13.5): walk into it facing it to climb on (or off the top looking down), W climbs the way
## you look (down when looking down, else up; S the other way), Space to let go. It also catches you
## stepping off the top or dropping past it. Players only for now (the AI don't use ladders).
## The origin is the foot of the ladder; it leans on whatever is behind it (-Z), climbers are on its +Z side.

## How high it goes (to the floor it leads up to).
@export var height := 4.0:
	set(value):
		height = value
		if is_inside_tree():
			_build()
@export var width := 0.6

const GROUP := &"ladders"


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
	if DisplayServer.get_name() == "headless" and not Engine.is_editor_hint():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.3, 0.2)
	material.roughness = 1.0
	for side in [-1.0, 1.0]:
		_bar(Vector3(side * width * 0.5, (height + 0.6) * 0.5, 0.06), Vector3(0.07, height + 0.6, 0.07), material)
	var rung := 0.3
	while rung < height + 0.2:
		_bar(Vector3(0, rung, 0.06), Vector3(width, 0.05, 0.05), material)
		rung += 0.35


func _bar(pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	add_child(part)
