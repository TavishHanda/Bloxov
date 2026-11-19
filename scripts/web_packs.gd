extends Node
## The web build's game files come in several packs (0.29.6, faster loading): the big ones (building and outdoor
## models, far views, the rest of the imported art) each have a name made from their content, so the browser keeps
## them across updates (index.html's file cache) and an update only downloads the packs that changed, usually just
## the small main one. tools/cache_bust.py splits the export and lists the extra packs in `window.BLOXOV_PACKS`;
## the page downloads them with the main pack. They're mounted here, when this script loads: the first autoload,
## before anything else loads a resource. Off the web, or a web export that wasn't split, there's nothing to do.
## (0.36.29, faster first load) The packs only raids use (the map models, `window.BLOXOV_LATE_PACKS`) aren't waited
## for: the game starts without them and the page downloads them in the background while you're on the title and in
## the hideout. Each one is mounted here as it arrives; START RAID waits for the rest if they're not in yet
## (`raid_ready`, LoadingScreen.wait_for_map).
## Must stay the first autoload and must not reference other game scripts.

static var mounted: PackedStringArray = []
## The background packs still to mount (web only).
static var _late_left: PackedStringArray = []
## Seconds until the next look at what the page has finished downloading.
var _wait := 0.0


static func _static_init() -> void:
	if not OS.has_feature("web"):
		return
	for pack in _list("BLOXOV_PACKS"):
		if ProjectSettings.load_resource_pack(pack, true):
			mounted.append(pack)
		else:
			push_error("WebPacks: couldn't load %s" % pack)
	_late_left = _list("BLOXOV_LATE_PACKS")


static func _list(js_name: String) -> PackedStringArray:
	var list = JavaScriptBridge.eval("(window.%s || []).join('\\n')" % js_name, true)
	if not (list is String) or (list as String) == "":
		return PackedStringArray()
	return (list as String).split("\n", false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # (the raid opens paused)
	set_process(not _late_left.is_empty())


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.25
	mount_arrived()


## Mounts the background packs the page has finished downloading (the page copies each into the game's files).
static func mount_arrived() -> void:
	if _late_left.is_empty():
		return
	var done := _list("BLOXOV_LATE_DONE")
	for pack in _late_left.duplicate():
		if not done.has(pack):
			continue
		_late_left.remove_at(_late_left.find(pack))
		if ProjectSettings.load_resource_pack(pack, true):
			mounted.append(pack)
		else:
			push_error("WebPacks: couldn't load %s" % pack)


## True once everything a raid needs is in (always true off the web).
static func raid_ready() -> bool:
	mount_arrived()
	return _late_left.is_empty()


## How much of the background download is done, 0 to 1.
static func progress() -> float:
	if _late_left.is_empty():
		return 1.0
	var got = JavaScriptBridge.eval("window.BLOXOV_LATE ? window.BLOXOV_LATE.loaded / Math.max(1, window.BLOXOV_LATE.total) : 0", true)
	return clampf(float(got), 0.0, 1.0) if (got is float or got is int) else 0.0


## True while the page is waiting to try a failed download again (the connection dropped).
static func retrying() -> bool:
	return not _late_left.is_empty() and bool(JavaScriptBridge.eval("!!(window.BLOXOV_LATE && window.BLOXOV_LATE.retrying)", true))
