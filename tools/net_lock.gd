extends SceneTree
## Re-records tests/net_lock.txt (0.35.2): godot --headless -s tools/net_lock.gd
## Run it after deciding whether config/net_version must go up (docs/context/ONLINE.md, "The net version").

func _init() -> void:
	var NetLockCore: GDScript = load("res://tools/net_lock_core.gd")
	var path := ProjectSettings.globalize_path(NetLockCore.LOCK_PATH)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("Could not write %s" % path)
		quit(1)
		return
	f.store_string(NetLockCore.lock_text())
	f.close()
	print("Recorded %s (net version %d)" % [path, NetLockCore.project_net_version()])
	quit()
