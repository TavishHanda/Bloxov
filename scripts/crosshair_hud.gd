class_name CrosshairHUD
extends Control
## Screen-center crosshair (0.8.3): four small pixel ticks and a dot, outlined so they show on any background.
## Hit marker: four little pixel stair-steps for 0.12 s (yellow and a bit bigger on a headshot). Subtle on purpose.

var show_crosshair := true
## Aimed through an optic (0.15.4): "dot" (a red dot in the middle) or "scope" (the scope's round view, black
## around it, thin cross lines), "" for none. See Gun.reticle().
var reticle := ""
const RETICLE_RED := Color(1.0, 0.15, 0.1)
var _hit_left := 0.0
var _headshot := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -20
	offset_top = -20
	offset_right = 20
	offset_bottom = 20


func flash_hit(headshot: bool) -> void:
	_hit_left = 0.12
	_headshot = headshot


func _process(delta: float) -> void:
	_hit_left -= delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if reticle == "scope":
		var screen := get_viewport_rect().size
		var radius := screen.y * 0.45
		var ring := screen.length()
		# Black all round the scope's circle: one very thick ring.
		draw_arc(c, radius + ring * 0.5, 0.0, TAU, 96, Color.BLACK, ring)
		var line := Color(0, 0, 0, 0.85)
		draw_rect(Rect2(c.x - radius, c.y - 1, radius * 2, 2), line)
		draw_rect(Rect2(c.x - 1, c.y - radius, 2, radius * 2), line)
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), RETICLE_RED)
	elif reticle == "dot":
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), RETICLE_RED)
	if show_crosshair:
		var color := Color(HudStyle.TEXT, 0.9)
		for rect in [Rect2(c + Vector2(-1, -10), Vector2(2, 6)), Rect2(c + Vector2(-1, 4), Vector2(2, 6)),
				Rect2(c + Vector2(-10, -1), Vector2(6, 2)), Rect2(c + Vector2(4, -1), Vector2(6, 2)), Rect2(c - Vector2(1, 1), Vector2(2, 2))]:
			draw_rect(rect.grow(1), Color(0, 0, 0, 0.7))
			draw_rect(rect, color)
	if _hit_left > 0.0:
		var color := HudStyle.ACTIVE if _headshot else Color.WHITE
		var step := 3.0 if _headshot else 2.0
		for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			for i in 3:
				var p: Vector2 = c + dir * (5.0 + i * step)
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(step, step)).grow(1), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(step, step)), color)
