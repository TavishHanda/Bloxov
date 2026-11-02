extends Node
## Builds the next raid's trees while you're in the hideout, a few milliseconds each frame (0.29.8, owner: "if we
## can build the trees faster then yeah do that"). The raid used to spend 1-3 s building them while it loaded (more on
## the web); now it finds them built, or finishes whatever's left. Looks only; nothing on servers or headless.

const TREES := preload("res://scripts/trees.gd")
## Time spent a frame (microseconds): small enough not to be felt beside the hideout's own frame.
const BUDGET_USEC := 3000


func _process(_delta: float) -> void:
	if TREES.prebuild(RaidMap.scene_path.get_basename() + "_trees.tres" if RaidMap.scene_path != "" else "",
			BUDGET_USEC):
		queue_free()
