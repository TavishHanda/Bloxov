class_name FarView
## Far versions of the building models (World art 0.17, outdoor step 10: far view and speed pass). Once a building's
## middle is FROM metres away it's drawn from its far mesh instead (assets/models/far/<model>.res, made by
## tools/far_bake.gd): the same outside and what shows through its windows and doors, without the rooms nobody can see
## from there. Up close (and from inside) it's the full model. Looks only: collision is the map's boxes.

const FROM := 70.0
const MARGIN := 5.0     # (so standing right at the switch doesn't flicker between the two)
const MODELS := "res://assets/models/buildings/"
const FAR := "res://assets/models/far/"


## Gives a building model (an instanced .glb) its far version, if one was baked. Skipped headless (servers, tests).
static func attach(model: Node3D) -> void:
	if DisplayServer.get_name() == "headless" or not model.scene_file_path.begins_with(MODELS):
		return
	var path := FAR + model.scene_file_path.get_file().get_basename() + ".res"
	if not ResourceLoader.exists(path):
		return
	var full := model if model is MeshInstance3D else model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	if full == null:
		return
	full.visibility_range_end = FROM
	full.visibility_range_end_margin = MARGIN
	var far := MeshInstance3D.new()
	far.name = "Far"
	far.mesh = load(path)
	far.visibility_range_begin = FROM
	far.visibility_range_begin_margin = MARGIN
	if full == model:
		model.add_child(far)
	else:
		full.get_parent().add_child(far)
		far.transform = full.transform
