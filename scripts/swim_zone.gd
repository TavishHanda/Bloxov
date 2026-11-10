class_name SwimZone
extends Area3D
## Deep water you swim in (0.33.6, Riptide's sea; owner: "swim slowly to a ladder"). A box of water whose top is the
## surface: a player in it floats with their head out and paddles slowly (player_movement.gd `_update_swim`), with
## no hands for a gun, meds or loot, and the only way out is a ladder. Players only: the AI never goes in the water.

## The box of water (metres); the node sits at the middle of its surface.
@export var size := Vector3(10, 10, 10)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # players
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = -size.y * 0.5
	add_child(shape)
	body_entered.connect(func(body: Node) -> void:
		if body.has_method(&"swim_entered"):
			body.swim_entered(self))
	body_exited.connect(func(body: Node) -> void:
		if body.has_method(&"swim_exited"):
			body.swim_exited(self))


## The height of the water's surface (world).
func surface_y() -> float:
	return global_position.y
