class_name ExtractHUD
extends Control
## Extract status (0.8.7, "Ammo Can"): above the crosshair while you stand in an extract, "EXTRACTING 3.2" on a
## green-rimmed plate that fills up, or "EXTRACT CLOSED" on a red one with red caution stripes.
## (0.10.2, owner: the open-extract list (O) and the name tags over extracts are gone: the map (M, MapHUD) is
## where you find extracts now.)

const STATUS_SIZE := Vector2(264, 44)

var player: Player
var raid: Raid


func _init(owner_player: Player, owner_raid: Raid) -> void:
	player = owner_player
	raid = owner_raid
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


## The extract you're standing in: {name, open, left (seconds), fraction}, or {}.
func status() -> Dictionary:
	if raid.result != "":
		return {}
	for zone in raid.get_extracts():
		if zone.player_inside == player:
			return {"name": zone.extract_name, "open": zone.is_open, "left": maxf(zone.extract_time - zone.progress, 0.0),
				"fraction": clampf(zone.progress / maxf(zone.extract_time, 0.01), 0.0, 1.0)}
	return {}


func _draw() -> void:
	_draw_status()


func _draw_status() -> void:
	var info := status()
	if info.is_empty():
		return
	var rect := Rect2((Vector2(size.x * 0.5, size.y * 0.5 - 150.0) - STATUS_SIZE * 0.5).round(), STATUS_SIZE)
	var open: bool = info["open"]
	var accent := HudStyle.EXTRACT if open else HudStyle.BLOOD
	HudStyle.draw_plate(self, rect, accent)
	var band := Rect2(rect.position + Vector2(4, STATUS_SIZE.y - 9), Vector2(STATUS_SIZE.x - 8, 4))
	var text_box := Rect2(rect.position, Vector2(STATUS_SIZE.x, STATUS_SIZE.y - 7))
	if open:
		draw_rect(band, HudStyle.DEEP)
		draw_rect(Rect2(band.position, Vector2(roundf(band.size.x * info["fraction"]), band.size.y)), HudStyle.EXTRACT)
		HudStyle.draw_centered(self, "EXTRACTING  %.1f" % info["left"], text_box, 30, HudStyle.EXTRACT)
	else:
		HudStyle.draw_hazard(self, band, 1.0, 8.0, 0.0, HudStyle.BLOOD)
		HudStyle.draw_centered(self, "EXTRACT CLOSED", text_box, 30, HudStyle.BLOOD)
