class_name WorldLabelsHUD
extends Control
## Labels over things in the world, drawn crisp in the HUD's pixel font (0.8.16, "Ammo Can"; they used to be
## Label3Ds, which blurred the pixel font). Finds them by group (Effects.WORLD_LABELS, this raid only):
## - damage numbers (owner toggle, off by default; meta label_kind "damage"): cream, popping up and floating away;
##   headshots/backstabs bigger, yellow, with "!".
## - teammate name tags ("name"): small, green, on a mini gunmetal plate, visible through walls like before.

const RISE := 42.0
const FADE_AFTER := 0.3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


## What to draw this frame: [{kind, text, critical, age, at (screen position)}], skipping ones behind the camera.
func entries() -> Array:
	var camera := get_viewport().get_camera_3d()
	var result := []
	if camera == null:
		return result
	var now := Time.get_ticks_msec() / 1000.0
	for node in RaidScope.nodes(self, Effects.WORLD_LABELS):
		var spot := node as Node3D
		if spot == null or not spot.is_inside_tree() or camera.is_position_behind(spot.global_position):
			continue
		result.append({"kind": spot.get_meta("label_kind", "name"), "text": String(spot.get_meta("label_text", "")),
			"critical": spot.get_meta("label_critical", false), "age": now - float(spot.get_meta("label_born", now)),
			"at": camera.unproject_position(spot.global_position).round()})
	return result


func _draw() -> void:
	for entry in entries():
		if entry["kind"] == "damage":
			_draw_damage(entry)
		elif entry["text"] != "":
			_draw_name(entry)


func _draw_damage(entry: Dictionary) -> void:
	var t := clampf(entry["age"] / Effects.DAMAGE_NUMBER_LIFE, 0.0, 1.0)
	var critical: bool = entry["critical"]
	var size := 40 if critical else 30
	var color := HudStyle.HAZARD if critical else HudStyle.INK
	# Pops up fast, then drifts; fades out over the second half.
	var rise := RISE * (1.0 - pow(1.0 - t, 3.0))
	var alpha := 1.0 - clampf((entry["age"] - FADE_AFTER) / (Effects.DAMAGE_NUMBER_LIFE - FADE_AFTER), 0.0, 1.0)
	var at: Vector2 = entry["at"]
	var box := Rect2(Vector2(at.x - 60, at.y - rise - 20), Vector2(120, 40))
	_outlined(entry["text"], box, size, Color(color, alpha))


func _draw_name(entry: Dictionary) -> void:
	var text: String = entry["text"]
	var at: Vector2 = entry["at"]
	var width := HudStyle.text_width(text, 20, HudStyle.spaced_font(20)) - 1.0 + 16.0
	var rect := Rect2(Vector2(roundf(at.x - width * 0.5), at.y - 22.0), Vector2(width, 20))
	HudStyle.draw_plate(self, rect, HudStyle.OUTLINE, HudStyle.FACE, 2.0)
	HudStyle.draw_centered(self, text, rect, 20, HudStyle.EXTRACT, HudStyle.spaced_font(20))


## Text with a hard 2-px dark edge on every side (pixel-crisp, no blur), so a number reads over sky and walls.
func _outlined(text: String, box: Rect2, size: int, color: Color) -> void:
	var dark := Color(0, 0, 0, color.a * 0.85)
	for offset in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(0, 4)]:
		HudStyle.draw_centered(self, text, Rect2(box.position + offset, box.size), size, dark, null, false)
	HudStyle.draw_centered(self, text, box, size, color, null, false)
