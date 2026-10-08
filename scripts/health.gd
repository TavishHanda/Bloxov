class_name Health
extends Node
## Health component. Add as a child named "Health" to anything that can be damaged
## (the gun and knife look for a child with that name via Health.of, like GetComponent in Unity).

signal damaged(amount: int, source_position: Vector3)
signal died

@export var max_health := 100
## Incoming damage is multiplied by this (armor lowers it). Always deals at least 1.
@export var damage_multiplier := 1.0

var current: int
var is_dead := false


func _ready() -> void:
	current = max_health


## The "Health" child of a node (null if it has none, or isn't a node).
static func of(target: Object) -> Health:
	if target is Node:
		return (target as Node).get_node_or_null("Health") as Health
	return null


## Returns the damage actually dealt (after armor), 0 if none.
func take_damage(amount: int, source_position := Vector3.ZERO) -> int:
	if is_dead or amount <= 0:
		return 0
	amount = maxi(roundi(amount * damage_multiplier), 1)
	current = maxi(current - amount, 0)
	damaged.emit(amount, source_position)
	if current == 0:
		is_dead = true
		died.emit()
	return amount


func heal(amount: int) -> void:
	if is_dead:
		return
	current = mini(current + amount, max_health)
