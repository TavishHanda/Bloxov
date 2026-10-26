class_name GhostCloth
extends Area3D
## The "ghost cloth" over the bunker ramp (town hall model, art_source/scripts/make_building.py ghost_runner): a red
## runner you walk straight through. Once someone has gone through it (a player or the AI), it's tripped and fades
## away for the rest of the raid (0.18.6, owner: "if someone goes through the vault carpet, make it disappear like
## its been tripped"). Every game sees who walks in (other players and the AI are bodies in each game too), so
## nothing is sent online. A child of the town hall's model; the runner is the model's "runner" material.

## The hole the runner covers, in the model's space (centre at this node).
@export var size := Vector3(8.5, 2.0, 2.4)
const FADE_TIME := 0.35

var tripped := false
var _faded: BaseMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4   # players, the AI
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	body_entered.connect(func(_body: Node3D) -> void: trip())
	_prepare.call_deferred()


## Puts the see-through copy of the runner on from the start, still fully opaque (0.22.9, owner: "when you reveal the
## red carpet in the town hall vault the game lags for a second"): switching the material to a see-through one when
## it was tripped made the renderer build a new shader right then (and again for the scissor one after the fade).
## Built with the rest of the hall when it first comes into view, tripping it only tweens the alpha.
func _prepare() -> void:
	var runner := _runner()
	if runner.is_empty():
		return
	var mesh_instance: MeshInstance3D = runner[0]
	var surface: int = runner[1]
	_faded = (mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D).duplicate() as BaseMaterial3D
	_faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.set_surface_override_material(surface, _faded)


func trip() -> void:
	if tripped:
		return
	tripped = true
	if _faded == null:
		return
	create_tween().tween_property(_faded, "albedo_color:a", 0.0, FADE_TIME)


## [mesh instance, surface] of the model's runner, or [] (headless or no such material).
func _runner() -> Array:
	for node in get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i)
			if material is BaseMaterial3D and material.resource_name == "runner":
				return [mesh_instance, i]
	return []
