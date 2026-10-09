class_name ExtractHUD
extends Control
## Extract info (0.8.7, "Ammo Can").
## - Top-right list of open extracts (a green flag, the name, the distance), sliding in for a few seconds at the
##   start of the raid and when you press O (owner rule: not on screen all the time).
## - Above the crosshair while you stand in an extract: "EXTRACTING 3.2" on a green-rimmed plate that fills up,
##   or "EXTRACT CLOSED" on a red one with red caution stripes.

const LIST_WIDTH := 228.0
const LIST_TOP := 36.0
const ROW_H := 24.0
const LIST_TIME := 6.0
const STATUS_SIZE := Vector2(264, 44)

var player: Player
var raid: Raid
## Seconds the list stays up (a few at the start of the raid, and after pressing O).
var list_time := LIST_TIME
var _slide := 0.0


func _init(owner_player: Player, owner_raid: Raid) -> void:
	player = owner_player
	raid = owner_raid
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## O: show the list (or hide it if it's up).
func toggle_list() -> void:
	list_time = 0.0 if list_time > 0.0 else LIST_TIME


func is_list_showing() -> bool:
	return list_time > 0.0


func _process(delta: float) -> void:
	list_time -= delta
	_slide = move_toward(_slide, 1.0 if list_time > 0.0 else 0.0, delta / 0.18)
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


## Open extracts: [{name, distance (m)}].
func open_extracts() -> Array:
	var result := []
	for zone in raid.get_extracts():
		if zone.is_open:
			result.append({"name": zone.extract_name, "distance": roundi(zone.global_position.distance_to(player.global_position))})
	return result


func _draw() -> void:
	if _slide > 0.0:
		_draw_list()
	_draw_status()


func _draw_list() -> void:
	var rows := open_extracts()
	var height := 30.0 + rows.size() * ROW_H + (10.0 if rows.size() > 0 else 0.0)
	var ease_in := 1.0 - pow(1.0 - _slide, 3.0)
	var x := roundf(size.x - 18.0 - LIST_WIDTH + (1.0 - ease_in) * (LIST_WIDTH + 30.0))
	var rect := Rect2(Vector2(x, LIST_TOP), Vector2(LIST_WIDTH, height))
	HudStyle.draw_plate(self, rect)
	# Header: EXTRACTS and the O key cap, over a groove.
	HudStyle.draw_label(self, "EXTRACTS", rect.position + Vector2(12, HudStyle.centered_baseline(15, 8, HudStyle.label_font())), HudStyle.INK_DIM)
	HudStyle.draw_keycap(self, Rect2(rect.position + Vector2(LIST_WIDTH - 12 - 18, 6), Vector2(18, 18)), "O")
	draw_rect(Rect2(rect.position + Vector2(8, 29), Vector2(LIST_WIDTH - 16, 1)), HudStyle.FACE_DK)
	draw_rect(Rect2(rect.position + Vector2(8, 30), Vector2(LIST_WIDTH - 16, 1)), HudStyle.FACE_HI)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var center_y := rect.position.y + 33.0 + i * ROW_H + ROW_H * 0.5
		var flag := HudStyle.icon_size(HudStyle.FLAG, 2)
		HudStyle.draw_icon(self, HudStyle.FLAG, Vector2(rect.position.x + 12, roundf(center_y - flag.y * 0.5)), 2, HudStyle.EXTRACT)
		var baseline := HudStyle.centered_baseline(center_y, 20)
		HudStyle.draw_text(self, row["name"], Vector2(rect.position.x + 30, baseline), 20, HudStyle.INK)
		HudStyle.draw_text(self, "%dm" % row["distance"], Vector2(rect.position.x, baseline), 20, HudStyle.INK_DIM, LIST_WIDTH - 12, 2)


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
