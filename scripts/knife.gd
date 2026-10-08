class_name Knife
extends Node3D
## Quick melee (V). Everyone always has a knife: it isn't an item, so it can't be lost, dropped or sold.
## Works with any gun out; cancels aiming and reloading. Stabbing someone from behind kills them in one hit.
## Lives under the player's camera, next to the Gun.

signal hit_confirmed(killed: bool, headshot: bool)

const SWING_SOUND := preload("res://audio/mag_out.wav")
const HIT_SOUND := preload("res://audio/hit.wav")
const KILL_SOUND := preload("res://audio/kill.wav")

@export var damage := 45
## Damage from behind (one-hit kill on anything with 100 HP or less).
@export var backstab_damage := 100
@export var reach := 2.2
## Seconds from pressing V until the blade connects, and the whole swing (you can't shoot until it ends).
@export var windup := 0.12
@export var swing_time := 0.55
## Enemies within this radius hear the swing.
@export var noise_radius := 4.0

@onready var player: Player = owner
@onready var camera: Camera3D = get_parent()

var _swing_left := 0.0
var _hit_pending := false
var _blade: Node3D


func _ready() -> void:
	_blade = _build_blade()
	add_child(_blade)
	_blade.visible = false


func is_swinging() -> bool:
	return _swing_left > 0.0


## Starts a swing. Returns false if one is already going (or the player can't act).
func swing() -> bool:
	if is_swinging() or player.controls_locked() or player.is_healing():
		return false
	_swing_left = swing_time
	_hit_pending = true
	_blade.visible = true
	Effects.sound(get_tree().current_scene, SWING_SOUND, -6.0, 0.1)
	get_tree().call_group("enemies", "hear_noise", player.global_position, noise_radius)
	return true


func _process(delta: float) -> void:
	if not is_swinging():
		return
	_swing_left -= delta
	if _hit_pending and _swing_left <= swing_time - windup:
		_hit_pending = false
		_strike()
	# Placeholder animation: the blade sweeps from the right across the middle of the screen.
	var t := 1.0 - _swing_left / swing_time
	var sweep := clampf(t / 0.45, 0.0, 1.0)
	_blade.position = Vector3(lerpf(0.25, -0.12, sweep), lerpf(-0.12, -0.2, sweep), -0.35)
	_blade.rotation = Vector3(-0.3, lerpf(0.9, -0.6, sweep), lerpf(-0.5, 0.4, sweep))
	if _swing_left <= 0.0:
		_blade.visible = false


func _strike() -> void:
	var target := _find_target()
	if target.is_empty():
		return
	var health: Health = target.health
	var victim: Node3D = target.node
	var amount := damage
	if _is_behind(victim):
		amount = backstab_damage
	health.take_damage(amount, player.global_position)
	var world := get_tree().current_scene
	Effects.impact(world, target.position, target.normal, Color(0.95, 0.25, 0.2), 12)
	if GameSettings.damage_numbers:
		Effects.damage_number(world, target.position, amount, amount == backstab_damage)
	Effects.sound(world, KILL_SOUND if health.is_dead else HIT_SOUND, -2.0, 0.03)
	if health.is_dead:
		player.gun.kills += 1
	hit_confirmed.emit(health.is_dead, false)


## A few rays in a small fan, so the knife is a bit forgiving. Returns {node, health, position, normal} or {}.
func _find_target() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var forward := -camera.global_basis.z
	for angle in [0.0, 0.25, -0.25]:
		var dir := forward.rotated(camera.global_basis.y, angle)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 4, [player.get_rid()])
		var result := space.intersect_ray(query)
		if result.is_empty() or not result.collider is Node:
			continue
		var health := (result.collider as Node).get_node_or_null("Health") as Health
		if health != null and not health.is_dead:
			return {"node": result.collider, "health": health, "position": result.position, "normal": result.normal}
	return {}


## True if the player is behind the victim (the victim is facing away).
func _is_behind(victim: Node3D) -> bool:
	var to_player := player.global_position - victim.global_position
	to_player.y = 0.0
	var facing := -victim.global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(to_player.normalized()) < -0.3


func _build_blade() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.77, 0.8)
	steel.metallic = 0.6
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.12, 0.12, 0.12)
	for part in [[Vector3(0.012, 0.03, 0.2), Vector3(0, 0, -0.12), steel], [Vector3(0.025, 0.035, 0.1), Vector3(0, 0, 0.03), grip]]:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mesh.material = part[2]
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.position = part[1]
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	return root
