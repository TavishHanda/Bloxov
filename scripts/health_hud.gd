class_name HealthHUD
extends Control
## Bottom-left health (0.8.4, "Ammo Can"): a gunmetal plate with 10 voxel cubes of 10 HP each (green / yellow /
## red; a partly lost cube shrinks) and the number stamped on a brass tag. Taking damage knocks
## cubes off (they flash, pop up and tumble away) and jolts the plate; at 30 or less the cubes and the tag
## (turned red) pulse. Stamina is a thin bar under the cubes, only while it isn't full; hazard-striped when
## exhausted.

const PLATE_SIZE := Vector2(250, 44)
const SEGMENTS := 10
const CUBE := 14.0
const CUBE_GAP := 3.0
const CUBES_AT := Vector2(12, 13)
const TAG := Rect2(189, 7, 52, 30)
const STAMINA_AT := Vector2(12, 34)
const CHIP_LIFE := 0.55

var player: Player
var _shown_hp := -1.0
## Cubes that were just knocked off: {index, age, spin} (they flash, then pop up and tumble away).
var _chips: Array = []
var _shake := 0.0
var _stamina_alpha := 0.0
var _stripe := 0.0
var _pulse := 0.0


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 18
	offset_top = -18 - PLATE_SIZE.y
	offset_right = 18 + PLATE_SIZE.x
	offset_bottom = -18


func _process(delta: float) -> void:
	var health := player.health
	var hp := float(health.current)
	var per := float(health.max_health) / SEGMENTS
	if _shown_hp >= 0.0 and hp < _shown_hp:
		# Knock off every cube that emptied (more than half gone).
		for i in SEGMENTS:
			var half := i * per + per * 0.5
			if _shown_hp >= half and hp < half:
				_chips.append({"index": i, "age": 0.0, "spin": randf_range(-1.0, 1.0)})
		_shake = 0.14
	_shown_hp = hp
	for chip in _chips:
		chip["age"] += delta
	_chips = _chips.filter(func(c: Dictionary) -> bool: return c["age"] < CHIP_LIFE)
	_shake = maxf(_shake - delta, 0.0)
	var wants_stamina := player.stamina < player.max_stamina and not player.controls_locked()
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if wants_stamina else 0.0, delta / 0.4 if not wants_stamina else delta * 8.0)
	_stripe += delta * 18.0
	_pulse += delta * TAU * 1.2
	queue_redraw()


func cube_rect(i: int) -> Rect2:
	return Rect2(CUBES_AT + Vector2(i * (CUBE + CUBE_GAP), 0), Vector2(CUBE, CUBE))


func _draw() -> void:
	var health := player.health
	var fraction := float(health.current) / maxf(health.max_health, 1)
	var origin := Vector2(randi_range(-2, 2), randi_range(-1, 1)) if _shake > 0.0 else Vector2.ZERO
	draw_set_transform(origin)
	HudStyle.draw_plate(self, Rect2(Vector2.ZERO, PLATE_SIZE))
	var low := fraction <= 0.3 and not player.controls_locked()
	var glow := 0.5 + 0.5 * cos(_pulse) if low else 0.0
	# Cubes: full ones are beveled voxels, empty ones dark sockets, the partly lost one drained from the top.
	var color := HudStyle.health_color(fraction).lightened(0.18 * glow)
	var per := float(health.max_health) / SEGMENTS
	for i in SEGMENTS:
		var rect := cube_rect(i)
		draw_rect(rect, HudStyle.DEEP)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(0, 0, 0, 0.45))
		var fill := clampf((health.current - i * per) / per, 0.0, 1.0)
		if fill >= 1.0:
			_cube(rect, color)
		elif fill > 0.0:
			# A partly lost cube shrinks (whole pixels, kept centered).
			var side := roundf(lerpf(4.0, CUBE - 2.0, fill) * 0.5) * 2.0
			_cube(Rect2(rect.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), color, 2.0)
	# Brass tag with the number (red and pulsing when low).
	var tag_face := HudStyle.BLOOD.lerp(HudStyle.BLOOD.lightened(0.25), glow) if low else HudStyle.BRASS
	HudStyle.draw_block(self, TAG, tag_face, tag_face.lightened(0.3), tag_face.darkened(0.4), 2.0)
	var digits := HudStyle.INK if low else HudStyle.DEEP
	# (the bevel is 2 px on every side, so the face's center is the tag's center)
	HudStyle.draw_centered(self, str(health.current), TAG, 30, digits, null, false)
	# Stamina.
	if _stamina_alpha > 0.0:
		var bar := Rect2(STAMINA_AT, Vector2(SEGMENTS * (CUBE + CUBE_GAP) - CUBE_GAP, 3))
		draw_rect(bar, Color(HudStyle.DEEP, _stamina_alpha))
		var amount := Rect2(bar.position, Vector2(roundf(bar.size.x * player.stamina / player.max_stamina), bar.size.y))
		if player.is_exhausted:
			HudStyle.draw_hazard(self, amount, _stamina_alpha, 6.0, _stripe, HudStyle.BLOOD)
		else:
			draw_rect(amount, Color(HudStyle.HAZARD, _stamina_alpha))
	# Knocked-off cubes: a white flash, then they pop up, tumble and fade.
	for chip in _chips:
		var age: float = chip["age"]
		var rect := cube_rect(chip["index"])
		if age < 0.06:
			draw_rect(rect.grow(1), Color.WHITE)
			continue
		var t := age - 0.06
		var k := 1.0 - t / (CHIP_LIFE - 0.06)
		var spin: float = chip["spin"]
		var pos := rect.get_center() + Vector2(spin * 40.0 * t, -70.0 * t + 380.0 * t * t)
		draw_set_transform(origin + pos, spin * 7.0 * t)
		_cube(Rect2(-rect.size * 0.5, rect.size), Color(color, k), 3.0, k)
	draw_set_transform(Vector2.ZERO)


## One health cube: a beveled voxel in `color`.
func _cube(rect: Rect2, color: Color, bevel := 3.0, alpha := 1.0) -> void:
	var hi := Color(color.lightened(0.4), alpha)
	var dk := Color(color.darkened(0.45), alpha)
	HudStyle.draw_block(self, rect, Color(color, alpha), hi, dk, minf(bevel, rect.size.y * 0.3), Color(0, 0, 0, 0))
