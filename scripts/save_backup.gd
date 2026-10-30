class_name SaveBackup
extends RefCounted
## Save backups (0.25.5, owner: nobody loses progress when the game moves to bloxov.com): the whole save (profile and
## settings) as one file to keep, and loading one back, from OPTIONS. The move page (web/move/index.html) builds the
## same package from the old site's save, so a file it hands out loads here too.
## A package: {"format": FORMAT, "profile": Profile.save_text(), "settings": GameSettings.save_text()}.

const FORMAT := "bloxov-save"
## Bigger than any real save by far; stops a wrong file (a video, say) being read into memory.
const MAX_BYTES := 4_000_000

## Keeps the browser's file-picked callback alive until it fires (JavaScriptBridge drops unreferenced ones).
static var _web_callback: JavaScriptObject


## The current save as a package (JSON text).
static func pack() -> String:
	Profile.load_profile()
	GameSettings.load_settings()
	return JSON.stringify({"format": FORMAT, "profile": Profile.save_text(), "settings": GameSettings.save_text()})


## A backup file's name, with today's date.
static func file_name() -> String:
	return "bloxov-save-%s.json" % Time.get_date_string_from_system()


## Checks a package: {"profile", "settings", "summary"} (summary: what's in it, to show before loading it), or
## {"error": why it can't be loaded}.
static func read(text: String) -> Dictionary:
	var data = _parse(text) if text.length() <= MAX_BYTES else null
	if not data is Dictionary or data.get("format") != FORMAT or not data.get("profile") is String:
		return {"error": "That isn't a Bloxov save file."}
	var profile = _parse(data["profile"])
	if not profile is Dictionary or not Profile._is_number(profile.get("version")):
		return {"error": "That save file is damaged."}
	if int(profile["version"]) != Profile.VERSION:
		return {"error": "That save is from a different version of the game."}
	var stats = profile.get("stats")
	var raids := int(stats.get("raids", 0)) if stats is Dictionary and Profile._is_number(stats.get("raids", 0)) else 0
	var money := int(profile["money"]) if Profile._is_number(profile.get("money")) else 0
	var summary := "%s, %d raid%s" % [ItemDB.money(money), raids, "" if raids == 1 else "s"]
	if Profile._is_number(profile.get("saved_at")):
		summary += ", saved " + Time.get_date_string_from_unix_time(int(profile["saved_at"]))
	var settings = data.get("settings")
	return {"profile": data["profile"], "settings": settings if settings is String else "", "summary": summary}


## JSON without the engine's error message for text that isn't (a wrong file is expected here). null if not JSON.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## Replaces the current save with a package checked by read.
static func apply(package: Dictionary) -> void:
	Profile.replace_with(package["profile"])
	if package["settings"] != "":
		GameSettings.replace_with(package["settings"])


## Hands the player the current save as a file: a download in the browser, a save dialog elsewhere.
## `on_done` gets a line to show (empty when there's nothing to say).
static func export_file(owner: Node, on_done: Callable) -> void:
	var text := pack()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name(), "application/json")
		on_done.call("Saved %s to your downloads." % file_name())
		return
	var dialog := _dialog(owner, FileDialog.FILE_MODE_SAVE_FILE)
	dialog.current_file = file_name()
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			on_done.call("Couldn't write that file.")
			return
		file.store_string(text)
		file.close()
		on_done.call("Saved to " + path))


## Lets the player pick a backup file; `on_text` gets its contents (not called if they cancel).
static func pick_file(owner: Node, on_text: Callable) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""window.bloxovPickSave = window.bloxovPickSave || function (done) {
	var input = document.createElement('input');
	input.type = 'file';
	input.accept = '.json,application/json';
	input.onchange = function () {
		var file = input.files && input.files[0];
		if (!file) return;
		if (file.size > %d) { done(''); return; }
		file.text().then(function (text) { done(text); }, function () { done(''); });
	};
	input.click();
};""" % MAX_BYTES, true)
		_web_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
			on_text.call(String(args[0]) if args.size() > 0 and args[0] is String else ""))
		JavaScriptBridge.get_interface("window").bloxovPickSave(_web_callback)
		return
	var dialog := _dialog(owner, FileDialog.FILE_MODE_OPEN_FILE)
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		on_text.call(file.get_as_text() if file != null and file.get_length() <= MAX_BYTES else ""))


static func _dialog(owner: Node, mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Bloxov save"])
	dialog.use_native_dialog = true
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	owner.add_child(dialog)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	dialog.popup_centered_ratio(0.6)
	return dialog
