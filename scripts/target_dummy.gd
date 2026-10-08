extends StaticBody3D
## Practice target. Can't die; heals back to full after a short break from being shot.

const FLASH_MATERIAL := preload("res://materials/flash_white.tres")

@export var regen_delay := 1.5

@onready var health: Health = $Health
@onready var model: Node3D = $Model

var _since_hit := 0.0
var _flash_time := 0.0
## Whether the hit-flash overlay is on right now (so the meshes are only touched when it changes).
var _flashing := false
var _wobble := 0.0


func _ready() -> void:
	health.damaged.connect(_on_damaged)


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > regen_delay:
		health.heal(health.max_health)
	_flash_time -= delta
	var flashing := _flash_time > 0.0
	if flashing != _flashing:
		_flashing = flashing
		var overlay: Material = FLASH_MATERIAL if flashing else null
		for child in model.get_children():
			if child is GeometryInstance3D:
				(child as GeometryInstance3D).material_overlay = overlay
	_wobble = lerpf(_wobble, 0.0, minf(delta * 6.0, 1.0))
	model.rotation.x = sin(_since_hit * 30.0) * _wobble


func _on_damaged(_amount: int, _source_position: Vector3) -> void:
	_since_hit = 0.0
	_flash_time = 0.06
	_wobble = 0.12
