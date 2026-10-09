class_name AmmoHUD
extends Control
## Bottom-right ammo (0.7.15): a plate with the magazine as a row of bullets (spent ones hollow), the loaded count
## big and the reserve small. Low on rounds = yellow, empty = red. Reloading refills the bullets across the reload.
## Unarmed: a small plate with the knife and "UNARMED".

const PLATE_SIZE := Vector2(200, 64)
const UNARMED_SIZE := Vector2(140, 40)

var player: Player


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -16 - PLATE_SIZE.x
	offset_top = -14 - PLATE_SIZE.y
	offset_right = -16
	offset_bottom = -14


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var gun := player.gun
	if gun.weapon == null:
		var rect := Rect2(PLATE_SIZE - UNARMED_SIZE, UNARMED_SIZE)
		HudStyle.draw_plate(self, rect)
		HudStyle.draw_icon(self, HudStyle.KNIFE, rect.position + Vector2(12, 14), 2, HudStyle.TEXT_DIM)
		HudStyle.draw_text(self, "UNARMED", rect.position + Vector2(44, 28), 20, HudStyle.TEXT_DIM)
		return
	HudStyle.draw_plate(self, Rect2(Vector2.ZERO, PLATE_SIZE))
	var mag := maxi(gun.mag_size, 1)
	var loaded := gun.in_mag
	if gun.is_reloading:
		# The bullets fill back up over the reload.
		loaded = roundi(lerpf(float(gun.in_mag), float(mag), clampf(1.0 - gun._reload_left / maxf(gun.reload_time, 0.01), 0.0, 1.0)))
	# One pip per round (per 2 rounds above 40), right-aligned.
	var per_pip := 2 if mag > 40 else 1
	var pips := ceili(float(mag) / per_pip)
	var right := PLATE_SIZE.x - 12.0
	for i in pips:
		var x := right - (pips - i) * 4.0
		var rect := Rect2(Vector2(x, 9), Vector2(3, 8))
		if i * per_pip < loaded:
			draw_rect(rect, HudStyle.TEXT)
			draw_rect(Rect2(rect.position, Vector2(3, 2)), HudStyle.BRASS)
		else:
			draw_rect(rect, HudStyle.WELL, false, 1.0)
	var color := HudStyle.TEXT
	if gun.in_mag == 0:
		color = HudStyle.WARN
	elif gun.in_mag <= mag * 0.25:
		color = HudStyle.HP_MID
	var reserve := "/ %d" % gun.reserve
	var reserve_width := HudStyle.font().get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	HudStyle.draw_text(self, reserve, Vector2(right - reserve_width, 56), 30, HudStyle.TEXT_DIM)
	HudStyle.draw_text(self, str(gun.in_mag), Vector2(12, 58), 60, color, right - reserve_width - 18, 2)
	if gun.is_reloading:
		HudStyle.draw_text(self, "RELOADING", Vector2(12, 24), 20, HudStyle.TEXT_DIM)
