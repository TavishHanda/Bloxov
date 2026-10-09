class_name Health
extends Node
## Health component. Add as a child named "Health" to anything that can be damaged
## (the gun and knife look for a child with that name via Health.of, like GetComponent in Unity).
##
## Downed (0.9.2): when `can_go_down` says so (a player with a teammate who can revive them), reaching 0 HP knocks
## you down instead of killing you. Down, a second bar (`down_hp`, 100) drains to 0 over `bleed_out_time`, hits
## take from it too, and at 0 you die (owner, 0.9.2). `revive()` stands you back up.

signal damaged(amount: int, source_position: Vector3)
signal died
signal downed
signal revived

## The downed bar starts here (owner: a bar from 100 to 0).
const DOWN_HP := 100.0

@export var max_health := 100
## Incoming damage is multiplied by this (armor lowers it). Always deals at least 1.
@export var damage_multiplier := 1.0
## Seconds the downed bar takes to drain on its own (owner: 30 s).
@export var bleed_out_time := 30.0

var current: int
var is_dead := false
var is_downed := false
## The downed bar (DOWN_HP to 0) while downed.
var down_hp := 0.0
## Asked when health reaches 0: true = go down instead of dying. Unset = always die (solo, scavs).
var can_go_down := Callable()


func _ready() -> void:
	current = max_health


## The "Health" child of a node (null if it has none, or isn't a node).
static func of(target: Object) -> Health:
	if target is Node:
		return (target as Node).get_node_or_null("Health") as Health
	return null


## Returns the damage actually dealt (after armor), 0 if none. While downed it comes off the downed bar.
func take_damage(amount: int, source_position := Vector3.ZERO) -> int:
	if is_dead or amount <= 0:
		return 0
	amount = maxi(roundi(amount * damage_multiplier), 1)
	if is_downed:
		down_hp = maxf(down_hp - amount, 0.0)
		damaged.emit(amount, source_position)
		if down_hp <= 0.0:
			kill()
		return amount
	current = maxi(current - amount, 0)
	damaged.emit(amount, source_position)
	if current == 0:
		if can_go_down.is_valid() and can_go_down.call():
			is_downed = true
			down_hp = DOWN_HP
			downed.emit()
		else:
			kill()
	return amount


## Downed: the bar drains on its own (call every frame).
func bleed(delta: float) -> void:
	if not is_downed or is_dead:
		return
	down_hp = maxf(down_hp - DOWN_HP / maxf(bleed_out_time, 0.01) * delta, 0.0)
	if down_hp <= 0.0:
		kill()


## Back up from downed with `hp` health.
func revive(hp: int) -> void:
	if not is_downed or is_dead:
		return
	is_downed = false
	down_hp = 0.0
	current = clampi(hp, 1, max_health)
	revived.emit()


## Dead now, whatever's left (out of time, bled out, no one left to revive you).
func kill() -> void:
	if is_dead:
		return
	current = 0
	is_downed = false
	down_hp = 0.0
	is_dead = true
	died.emit()


func heal(amount: int) -> void:
	if is_dead or is_downed:
		return
	current = mini(current + amount, max_health)
