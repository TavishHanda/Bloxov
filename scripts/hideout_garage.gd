class_name HideoutGarage
extends Node3D
## The truck in the hideout's garage (0.38.1, Expeditions; owner 2026-11-20 picked a garage tunnel off the hall).
## Parked on the level's Truck marker (art_source/scripts/make_hideout.py garage()), nose to the shutter, showing only
## the parts you've built (ExpeditionCutscene.build_truck): the bare frame to start, the whole truck when it's ready.
## USE beside it (the "garage" station) opens THE TRUCK. Looks only: never synced, never on the server.

var _truck: Node3D
var _shown: Array = []


func setup(level: Node) -> void:
	var spot := level.get_node_or_null("Truck") as Marker3D
	if spot == null:
		return
	# (build_truck's front is +z; the marker looks down -z, at the shutter)
	transform = spot.transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	refresh()


## Shows the parts built now (after building one in the menu).
func refresh() -> void:
	var parts: Array = ["frame"]
	for id: String in Profile.truck:
		if not parts.has(id):
			parts.append(id)
	if parts == _shown and _truck != null:
		return
	_shown = parts
	if _truck != null:
		_truck.queue_free()
	_truck = ExpeditionCutscene.build_truck(parts)
	add_child(_truck)
