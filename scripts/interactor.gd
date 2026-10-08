class_name Interactor
extends Node
## Finds the loot container the player is looking at and handles hold-E-to-search.

signal opened(container: LootContainer)

@export var reach := 2.6

@onready var player: Player = owner

var target: LootContainer = null
## The container `progress` belongs to (looking at another one starts over).
var _progress_target: LootContainer = null
## 0..1 while holding E on an unsearched container.
var progress := 0.0
## Set by the HUD while a loot/inventory screen is open.
var blocked := false


func _physics_process(delta: float) -> void:
	target = null
	if blocked or player.controls_locked() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		progress = 0.0
		return
	target = _find_target()
	if target == null or not Input.is_action_pressed("interact"):
		progress = 0.0
		return

	if target != _progress_target:
		_progress_target = target
		progress = 0.0
	var hold_time := target.interact_time()
	if hold_time <= 0.0:
		if Input.is_action_just_pressed("interact"):
			opened.emit(target)
		return
	progress += delta / hold_time
	if progress >= 1.0:
		progress = 0.0
		target.mark_searched()
		opened.emit(target)


func _find_target() -> LootContainer:
	var camera := player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	# Mask: world (1) so walls block it + interactables (8).
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8, [player.get_rid()])
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.collider as LootContainer
