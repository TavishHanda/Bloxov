class_name PromptHUD
extends Control
## Under the crosshair (0.8.7, "Ammo Can"): what F does on the thing you're looking at ("[F] SEARCH": a cream key cap
## and the action on a gunmetal plate), with a brass progress bar while it takes time. Healing shows a red cross,
## "HEALING" and a green bar.

const PLATE_H := 32.0
const BELOW_CENTER := 48.0

var player: Player


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## What to show: {text, key ("" = the med cross), progress (-1 = no bar), bar color}, or {} for nothing.
func current() -> Dictionary:
	if player.is_healing():
		return {"text": "HEALING", "key": "", "progress": 1.0 - player.heal_time_left / player.heal_duration, "bar": HudStyle.LIFE}
	var interactor := player.interactor
	if interactor.target != null:
		var progress := interactor.progress if interactor.progress > 0.0 else -1.0
		return {"text": interactor.target.prompt().to_upper(), "key": "F", "progress": progress, "bar": HudStyle.BRASS}
	return {}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var info := current()
	if info.is_empty():
		return
	var text: String = info["text"]
	var text_w := HudStyle.text_width(text, 20) - 1.0
	var lead := 22.0
	var width := 6.0 + lead + 9.0 + text_w + 12.0
	var rect := Rect2(Vector2(roundf(size.x * 0.5 - width * 0.5), roundf(size.y * 0.5 + BELOW_CENTER)), Vector2(width, PLATE_H))
	HudStyle.draw_plate(self, rect)
	var lead_box := Rect2(rect.position + Vector2(6, 5), Vector2(lead, lead))
	if info["key"] == "":
		var cross := HudStyle.icon_size(HudStyle.MED, 3)
		HudStyle.draw_icon(self, HudStyle.MED, (lead_box.get_center() - cross * 0.5).round(), 3, HudStyle.BLOOD)
	else:
		HudStyle.draw_keycap(self, lead_box, info["key"])
	HudStyle.draw_text(self, text, Vector2(lead_box.end.x + 9, HudStyle.centered_baseline(rect.get_center().y, 20)), 20, HudStyle.INK)
	var progress: float = info["progress"]
	if progress >= 0.0:
		var bar := Rect2(rect.position + Vector2(0, PLATE_H + 6), Vector2(width, 6))
		draw_rect(bar.grow(2), HudStyle.OUTLINE)
		draw_rect(bar, HudStyle.DEEP)
		var fill := Rect2(bar.position, Vector2(roundf(bar.size.x * clampf(progress, 0.0, 1.0)), bar.size.y))
		var color: Color = info["bar"]
		draw_rect(fill, color)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), color.lightened(0.35))
