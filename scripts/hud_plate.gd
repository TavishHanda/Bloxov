class_name HudPlate
extends Control
## A notched HUD plate (HudStyle.draw_plate) drawn behind a label; follows `target`'s rect (grown by `padding`).
## Hidden whenever the target is.

var target: Control
var padding := Vector2(10, 4)
var border := HudStyle.PLATE_EDGE


func _init(label: Control, pad := Vector2(10, 4)) -> void:
	target = label
	padding = pad
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	visible = target.visible and target.modulate.a > 0.01
	if visible:
		var rect := target.get_rect()
		# Hug a label's text, not its whole box (respecting its alignment).
		if target is Label:
			var label := target as Label
			var text_size := label.get_minimum_size()
			var x := rect.position.x
			match label.horizontal_alignment:
				HORIZONTAL_ALIGNMENT_RIGHT:
					x = rect.end.x - text_size.x
				HORIZONTAL_ALIGNMENT_CENTER:
					x = rect.get_center().x - text_size.x * 0.5
			rect = Rect2(Vector2(x, rect.position.y), Vector2(text_size.x, maxf(text_size.y, rect.size.y if label.vertical_alignment != VERTICAL_ALIGNMENT_TOP else text_size.y)))
		position = rect.position - padding
		size = rect.size + padding * 2.0
		queue_redraw()


func _draw() -> void:
	HudStyle.draw_plate(self, Rect2(Vector2.ZERO, size), border)
