class_name HealthHUD
extends Control
## Bottom-left health (0.7.15): a plate with a red cross, 10 blocks of 10 HP each (green / yellow / red), and the
## number. Taking damage chips blocks off (they flash, drop and fade) and shakes the plate; at 30 or less the
## cross and number pulse. Stamina is a thin bar under the blocks, only while it isn't full; hazard-striped when
## exhausted.

const PLATE_SIZE := Vector2(236, 48)
const SEGMENTS := 10
const SEG_SIZE := Vector2(16, 20)
const SEG_GAP := 2.0
const SEG_START := Vector2(36, 12)

var player: Player
var _shown_hp := -1.0
## Blocks that just emptied: {index, age} (they flash, then fall and fade).
var _chips: Array = []
var _shake := 0.0
var _stamina_alpha := 0.0
var _stripe := 0.0
var _pulse := 0.0


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(16, -64)
	size = PLATE_SIZE
	custom_minimum_size = PLATE_SIZE
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func _ready() -> void:
	offset_left = 16
	offset_top = -64
	offset_right = 16 + PLATE_SIZE.x
	offset_bottom = -64 + PLATE_SIZE.y


func _process(delta: float) -> void:
	var health := player.health
	var hp := float(health.current)
	var per := float(health.max_health) / SEGMENTS
	if _shown_hp >= 0.0 and hp < _shown_hp:
		# Chip off every block that emptied.
		for i in SEGMENTS:
			var block_top := (i + 1) * per
			if _shown_hp >= block_top - per * 0.5 and hp < block_top - per * 0.5:
				_chips.append({"index": i, "age": 0.0})
		_shake = 0.12
	_shown_hp = hp
	for chip in _chips:
		chip["age"] += delta
	_chips = _chips.filter(func(c: Dictionary) -> bool: return c["age"] < 0.43)
	_shake = maxf(_shake - delta, 0.0)
	var wants_stamina := player.stamina < player.max_stamina and not player.controls_locked()
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if wants_stamina else 0.0, delta / 0.4 if not wants_stamina else delta * 8.0)
	_stripe = fmod(_stripe + delta * 20.0, 12.0)
	_pulse += delta * TAU * 1.2
	queue_redraw()


func _draw() -> void:
	var health := player.health
	var fraction := float(health.current) / maxf(health.max_health, 1)
	var origin := Vector2(randf_range(-2, 2), randf_range(-2, 2)) if _shake > 0.0 else Vector2.ZERO
	HudStyle.draw_plate(self, Rect2(origin, PLATE_SIZE))
	var low := fraction <= 0.3 and not player.controls_locked()
	var pulse_alpha := lerpf(0.55, 1.0, 0.5 + 0.5 * cos(_pulse)) if low else 1.0
	# Red cross with a white inner cross.
	HudStyle.draw_icon(self, HudStyle.MED, origin + Vector2(8, 13), 3, Color(HudStyle.WARN, pulse_alpha))
	draw_rect(Rect2(origin + Vector2(8 + 9 + 1, 13 + 3 + 1), Vector2(1, 19)), Color(1, 1, 1, 0.8 * pulse_alpha))
	draw_rect(Rect2(origin + Vector2(8 + 3 + 1, 13 + 9 + 1), Vector2(19, 1)), Color(1, 1, 1, 0.8 * pulse_alpha))
	# Blocks.
	var color := HudStyle.health_color(fraction)
	var per := float(health.max_health) / SEGMENTS
	for i in SEGMENTS:
		var rect := Rect2(origin + SEG_START + Vector2(i * (SEG_SIZE.x + SEG_GAP), 0), SEG_SIZE)
		draw_rect(rect, HudStyle.WELL)
		var fill := clampf((health.current - i * per) / per, 0.0, 1.0)
		if fill > 0.0:
			var filled := Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y))
			draw_rect(filled, color)
			draw_rect(Rect2(filled.position + Vector2(0, filled.size.y - 3), Vector2(filled.size.x, 3)), color * Color(0.7, 0.7, 0.7))
	# Chipped blocks: a white flash, then the block falls, turns and fades.
	for chip in _chips:
		var age: float = chip["age"]
		var rect := Rect2(origin + SEG_START + Vector2(chip["index"] * (SEG_SIZE.x + SEG_GAP), 0), SEG_SIZE)
		if age < 0.08:
			draw_rect(rect, Color.WHITE)
		else:
			var t := (age - 0.08) / 0.35
			draw_set_transform(rect.get_center() + Vector2(0, 14.0 * t), deg_to_rad(20.0 * t))
			draw_rect(Rect2(-SEG_SIZE * 0.5, SEG_SIZE), Color(color, 1.0 - t))
			draw_set_transform(Vector2.ZERO)
	# Number.
	HudStyle.draw_text(self, str(health.current), origin + Vector2(186, 36), 30, Color(HudStyle.TEXT, pulse_alpha), 44, 2)
	# Stamina.
	if _stamina_alpha > 0.0:
		var bar := Rect2(origin + Vector2(36, 38), Vector2(180, 4))
		draw_rect(bar, Color(HudStyle.WELL, _stamina_alpha))
		var amount := Rect2(bar.position, Vector2(bar.size.x * player.stamina / player.max_stamina, bar.size.y))
		if player.is_exhausted:
			draw_rect(amount, Color(HudStyle.WARN, _stamina_alpha))
			# Hazard stripes scrolling along the bar.
			var x := _stripe - 12.0
			while x < amount.size.x:
				var from := amount.position + Vector2(clampf(x, 0.0, amount.size.x), amount.size.y)
				var to := amount.position + Vector2(clampf(x + 4.0, 0.0, amount.size.x), 0.0)
				draw_line(from, to, Color(HudStyle.PLATE, _stamina_alpha), 2.0)
				x += 6.0
		else:
			draw_rect(amount, Color(HudStyle.STAMINA, _stamina_alpha))
