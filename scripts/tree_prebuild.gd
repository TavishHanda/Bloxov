extends Node
## Builds the next raid's trees while you're in the hideout, a few milliseconds each frame (0.29.8, owner: "if we
## can build the trees faster then yeah do that"). The raid used to spend 1-3 s building them while it loaded (more on
## the web); now it finds them built, or finishes whatever's left. Looks only; nothing on servers or headless.
## 0.39.30: it starts on the title screen once PLAY is up, and in a browser START RAID finishes any rest a step at a
## time behind the loading screen (RaidPrep).

const TREES := preload("res://scripts/trees.gd")
## Time spent a frame (microseconds): small enough not to be felt beside the hideout's own frame.
const BUDGET_USEC := 3000


func _process(_delta: float) -> void:
	if TREES.prebuild(RaidPrep.trees_file(RaidMap.scene_path), BUDGET_USEC):
		queue_free()
