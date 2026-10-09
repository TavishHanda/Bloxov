class_name AmmoHUD
extends Control
## Bottom-right ammo (0.8.4, "Ammo Can"): a gunmetal plate with the loaded count big on the left and, on the right,
## the magazine as a row of brass cartridges (spent ones are empty sockets) over the reserve. Low on rounds =
## yellow, empty = red. Reloading: the cartridges fill back up and a strip of tape says so.
## Unarmed: a smaller plate with the knife and "UNARMED".

const PLATE_SIZE := Vector2(206, 50)
const UNARMED_SIZE := Vector2(160, 40)
## Where the big count ends (right-aligned) and the cartridges/reserve start.
const COUNT_RIGHT := 74.0
const RIGHT_COLUMN := 86.0
const PAD := 12.0

var player: Player
var _reload_tape := 0.0


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -18 - PLATE_SIZE.x
	offset_top = -18 - PLATE_SIZE.y
	offset_right = -18
	offset_bottom = -18


func _process(delta: float) -> void:
	var reloading := player.gun.weapon != null and player.gun.is_reloading
	_reload_tape = move_toward(_reload_tape, 1.0 if reloading else 0.0, delta / 0.12)
	queue_redraw()


func _draw() -> void:
	var gun := player.gun
	if gun.weapon == null:
		var rect := Rect2(PLATE_SIZE - UNARMED_SIZE, UNARMED_SIZE)
		HudStyle.draw_plate(self, rect)
		var knife := HudStyle.icon_size(HudStyle.KNIFE, 2)
		HudStyle.draw_icon(self, HudStyle.KNIFE, rect.position + Vector2(PAD, (rect.size.y - knife.y) * 0.5), 2, HudStyle.INK)
		# (stencil caps: the number font's "A" looks odd at this size)
		var label_box := Rect2(Vector2(rect.position.x + PAD + knife.x + 10, rect.position.y), Vector2(rect.end.x - PAD - (rect.position.x + PAD + knife.x + 10), rect.size.y))
		HudStyle.draw_centered(self, "UNARMED", label_box, 16, HudStyle.INK_DIM, HudStyle.label_font())
		return
	HudStyle.draw_plate(self, Rect2(Vector2.ZERO, PLATE_SIZE))
	var mag := maxi(gun.mag_size, 1)
	var loaded := gun.in_mag
	if gun.is_reloading:
		# The cartridges fill back up over the reload.
		loaded = roundi(lerpf(float(gun.in_mag), float(mag), clampf(1.0 - gun._reload_left / maxf(gun.reload_time, 0.01), 0.0, 1.0)))
	# Big count.
	var color := HudStyle.INK
	if gun.in_mag == 0:
		color = HudStyle.BLOOD
	elif gun.in_mag <= mag * 0.25:
		color = HudStyle.HAZARD
	HudStyle.draw_text(self, str(gun.in_mag), Vector2(PAD - 4, 40), 40, color, COUNT_RIGHT - PAD + 4, 2)
	# Divider: a groove between the count and the magazine.
	draw_rect(Rect2(COUNT_RIGHT + 5, 9, 2, PLATE_SIZE.y - 18), HudStyle.FACE_DK)
	draw_rect(Rect2(COUNT_RIGHT + 7, 9, 1, PLATE_SIZE.y - 18), HudStyle.FACE_HI)
	# Cartridges: one per round (per 2 rounds when they wouldn't fit), filling the column left to right.
	var width := PLATE_SIZE.x - PAD - RIGHT_COLUMN
	var per_pip := 1
	while ceili(float(mag) / per_pip) * 3.0 > width:
		per_pip += 1
	var pips := ceili(float(mag) / per_pip)
	var pitch := minf(5.0, floorf(width / pips * 2.0) / 2.0)
	var pip_w := 2.0 if pitch < 4.0 else 3.0
	for i in pips:
		var rect := Rect2(Vector2(RIGHT_COLUMN + i * pitch, 10), Vector2(pip_w, 13))
		if i * per_pip < loaded:
			draw_rect(rect, HudStyle.BRASS)
			draw_rect(Rect2(rect.position, Vector2(pip_w, 4)), HudStyle.COPPER)
			draw_rect(Rect2(rect.position + Vector2(0, 5), Vector2(1, 7)), HudStyle.BRASS_HI)
		else:
			draw_rect(rect, HudStyle.DEEP)
	# Reserve under the cartridges.
	HudStyle.draw_text(self, "/ %d" % gun.reserve, Vector2(RIGHT_COLUMN, 41), 20, HudStyle.INK_DIM)
	if _reload_tape > 0.0:
		var tape_w := HudStyle.tape_width("RELOADING", 14)
		var rect := Rect2(Vector2(PLATE_SIZE.x - tape_w - 6, -24 + 6.0 * (1.0 - _reload_tape)), Vector2(tape_w, 20))
		HudStyle.draw_tape(self, rect, "RELOADING", -2.5, _reload_tape, 14)
