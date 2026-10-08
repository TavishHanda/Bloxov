class_name Health
extends Node
## Health component. Add as a child named "Health" to anything that can be damaged
## (the gun looks for a child with that name, like GetComponent in Unity).

signal damaged(amount: int, source_position: Vector3)
signal died

@export var max_health := 100
## Incoming damage is multiplied by this (armor lowers it). Always deals at least 1.
@export var damage_multiplier := 1.0

var current: int
var is_dead := false


func _ready() -> void:
	current = max_health


func take_damage(amount: int, source_position := Vector3.ZERO) -> void:
	if is_dead or amount <= 0:
		return
	amount = maxi(roundi(amount * damage_multiplier), 1)
	current = maxi(current - amount, 0)
	damaged.emit(amount, source_position)
	if current == 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead:
		return
	current = mini(current + amount, max_health)
