class_name ItemIcons
extends RefCounted
## The inventory pictures of items (assets/icons/items/<id>.png, made by tools/render_icons.gd): PX pixels per grid
## cell, drawn at the cell size (GridView.CELL) so they stay sharp on high-density screens.

const PX := 88
const DIR := "res://assets/icons/items/"

static var _cache := {}


## The picture for item `id`, or null if it has none (the tile then shows the name only).
static func get_icon(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := DIR + id + ".png"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


## Where to draw `texture` inside `room` so it's as big as fits without stretching, centred.
static func fit(texture: Texture2D, room: Rect2) -> Rect2:
	var tex_size := texture.get_size()
	var scale := minf(room.size.x / tex_size.x, room.size.y / tex_size.y)
	var drawn := tex_size * scale
	return Rect2(room.position + (room.size - drawn) * 0.5, drawn)
