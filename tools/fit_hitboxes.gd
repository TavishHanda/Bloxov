extends SceneTree
# Prints Hitbox's fitted parts (CROUCH_PARTS, PRONE_PARTS, DOWNED_PARTS and the necks) measured on the PMC model in
# each pose (BodyPose.measure). Paste them into scripts/hitbox.gd after changing the model or BodyPose's poses.
# godot --headless -s tools/fit_hitboxes.gd


func _initialize() -> void:
	var model: Node3D = (load("res://assets/models/characters/pmc.glb") as PackedScene).instantiate()
	root.add_child.call_deferred(model)
	await process_frame
	var pose := BodyPose.new(model)
	for item: Array in [["CROUCH", {"crouch": 1.0}], ["PRONE", {"prone": 1.0}], ["DOWNED", {"downed": 1.0}]]:
		var parts := pose.measure(item[1])
		var text := "const %s_PARTS := [" % item[0]
		for part: Array in parts:
			text += "[%s, %s, %s, %.3f], " % [_v(part[0]), _v(part[1]), "true" if part[2] else "false", part[3]]
		print(text.trim_suffix(", ") + "]")
		pose.crouch = item[1].get("crouch", 0.0)
		pose.prone = item[1].get("prone", 0.0)
		pose.downed = item[1].get("downed", 0.0)
		pose.update(0.0)
		print("const %s_NECK := %s" % [item[0], _v(pose.in_model(pose.joint("Neck")).origin)])
	quit()


func _v(v: Vector3) -> String:
	return "Vector3(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
