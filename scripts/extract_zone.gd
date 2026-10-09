class_name ExtractZone
extends Area3D
## Stand inside an open extract for `extract_time` seconds to leave the raid with your loot.
## The Raid decides which extracts are open each raid.

signal extracted(zone: ExtractZone)

@export var extract_name := "Extract"
@export var extract_time := 7.0

@onready var pad: MeshInstance3D = $Pad
@onready var beam: Node3D = $Beam

var is_open := true
## Seconds the player has been standing in it.
var progress := 0.0
var player_inside: Player = null

## Shared by every closed pad (built once, on first use).
static var _closed_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("extracts")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_open(open: bool) -> void:
	is_open = open
	beam.visible = open
	pad.material_override = null if open else _closed_pad_material()


static func _closed_pad_material() -> StandardMaterial3D:
	if _closed_material == null:
		_closed_material = StandardMaterial3D.new()
		_closed_material.albedo_color = Color(0.45, 0.12, 0.1)
	return _closed_material


func _physics_process(delta: float) -> void:
	if is_open and player_inside != null and not player_inside.controls_locked():
		progress += delta
		if progress >= extract_time:
			progress = 0.0
			extracted.emit(self)
	else:
		progress = 0.0


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_inside = body


func _on_body_exited(body: Node3D) -> void:
	if body == player_inside:
		player_inside = null
