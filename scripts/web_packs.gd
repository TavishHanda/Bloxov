extends Node
## The web build's game files come in several packs (0.29.6, faster loading): the big ones (building and outdoor
## models, far views, the rest of the imported art) each have a name made from their content, so the browser keeps
## them across updates (index.html's file cache) and an update only downloads the packs that changed, usually just
## the small main one. tools/cache_bust.py splits the export and lists the extra packs in `window.BLOXOV_PACKS`;
## the page downloads them with the main pack. They're mounted here, when this script loads: the first autoload,
## before anything else loads a resource. Off the web, or a web export that wasn't split, there's nothing to do.
## Must stay the first autoload and must not reference other game scripts.

static var mounted: PackedStringArray = []


static func _static_init() -> void:
	if not OS.has_feature("web"):
		return
	var list = JavaScriptBridge.eval("(window.BLOXOV_PACKS || []).join('\\n')", true)
	if not (list is String) or (list as String) == "":
		return
	for pack in (list as String).split("\n", false):
		if ProjectSettings.load_resource_pack(pack, true):
			mounted.append(pack)
		else:
			push_error("WebPacks: couldn't load %s" % pack)
