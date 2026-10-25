class_name DartsGame
extends Node3D
## Darts in the mess (0.21.7; a real mini-game in 0.21.12, owner: "just click to throw, too easy... add a power bar...
## maybe play against the traders"). At the line, pick PRACTICE or a trader to play. Your aim drifts a little (like
## breathing); hold the mouse (or your finger) to wind up, and let go with the power bar in the green: too soft and the
## dart drops low, too hard and it flies high. Against a trader: three rounds of three darts each, the highest total
## wins. Each trader throws as well as they do. Just for fun: nothing is bet, nothing is saved.

const DART_HIT := preload("res://audio/world/dart.wav")
## The board's numbers, clockwise from the top.
const DART_NUMBERS := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const DARTS_PER_TURN := 3
const ROUNDS := 3
const DART_FLIGHT := 0.18      # seconds from the hand to the board
## Your aim drifts in a slow loop this far across the board (m) and this fast.
const SWAY := 0.03
const SWAY_SPEED := 1.3
## The power bar: up and back down in POWER_CYCLE seconds; let go at SWEET (±SWEET_BAND is the green). Every bit off
## puts the dart POWER_DROP m per unit lower (too soft) or higher (too hard).
const POWER_CYCLE := 1.3
const SWEET := 0.72
const SWEET_BAND := 0.06
const POWER_DROP := 0.5
const HAND_SPREAD := 0.01      # a throw's little wobble even when it's perfect
## How well each trader throws: the spread of their darts round what they aim at (m), and what they say.
const TRADERS := {
	"guns": {"spread": 0.045, "aim": "T20", "win": "Steady hands. Comes with the job.", "lose": "Lucky. Again?"},
	"meds": {"spread": 0.07, "aim": "BULL", "win": "Don't tell anyone I won that.", "lose": "Hands of a surgeon, aim of a scav."},
	"supplies": {"spread": 0.055, "aim": "T20", "win": "Supplied: one beating.", "lose": "Fine. Next round's on me."},
	"valuables": {"spread": 0.035, "aim": "T20", "win": "Precision is worth paying for.", "lose": "Hm. Not bad."},
	"ming": {"spread": 0.05, "aim": "BULL", "win": "Uncle Ming always wins in the end!", "lose": "Luck runs out, luck comes back."},
}
const TRADER_GAP := 0.7        # seconds between a trader's darts

## Your best three darts in practice, while the game's open.
static var best_round := 0

var board: Node3D
var rings := PackedFloat32Array()
var walker: HideoutWalker
var active := false
## "" (picking), "practice", or the trader you're playing.
var mode := ""
## "you", "them" (the trader's throwing), "over" (the game's done: click to play again).
var turn := "you"
var round_no := 1
## This turn's darts (each [score, label]), and the game's totals.
var turn_darts: Array = []
var your_total := 0
var their_total := 0
var charging := false
var power := 0.0
var _charge_time := 0.0
var _sway_time := 0.0
var _their_wait := 0.0
var _thrown: Array[Node3D] = []
var _dice := RandomNumberGenerator.new()
var _hud: CanvasLayer
var _score: Label
var _say: Label
var _picker: PanelContainer
var _bar: Control
var _bar_fill: ColorRect


func setup(on_board: Node3D, who: HideoutWalker) -> void:
	board = on_board
	walker = who
	rings = board.get_meta("rings")
	_dice.randomize()
	_paint_numbers()
	_build_hud()


# --- Starting and stopping --------------------------------------------------------------------

## At the line: pick who to play.
func begin() -> void:
	active = true
	_hud.visible = true
	_show_picker()


func end() -> void:
	active = false
	charging = false
	_hud.visible = false
	_clear_board()
	walker.locked = false
	walker.camera.rotation.y = 0.0
	walker.look(0.0, 0.0)


func _show_picker() -> void:
	mode = ""
	charging = false
	_picker.visible = true
	_bar.visible = false
	_say.text = ""
	_score.text = "DARTS"
	walker.locked = true   # (the mouse is for the buttons)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Practice (`who` = "practice") or a game against trader `who`.
func play(who: String) -> void:
	mode = who
	walker.locked = false
	_picker.visible = false
	_bar.visible = true
	round_no = 1
	your_total = 0
	their_total = 0
	turn = "you"
	turn_darts.clear()
	_clear_board()
	_say.text = "" if who == "practice" else "%s: \"%s\"" % [trader_name(who), "Three rounds. Highest total wins."]
	if not GameSettings.is_phone():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_show_score()


static func trader_name(who: String) -> String:
	return String(Traders.LIST[who]["name"]) if Traders.LIST.has(who) else who.capitalize()


# --- Input ------------------------------------------------------------------------------------

## A click (or a tap) while playing: press to wind up, let go to throw. True if used.
func handle_input(event: InputEvent) -> bool:
	if not active or mode == "":
		return false
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameSettings.is_phone():
		return false   # (that click grabs the mouse first)
	if button.pressed:
		if turn == "over":
			play(mode)
		elif turn == "you" and turn_darts.size() >= DARTS_PER_TURN:
			_next_turn()
		elif turn == "you":
			charging = true
			_charge_time = 0.0
	elif charging:
		charging = false
		throw_dart(power)
	return true


func _process(delta: float) -> void:
	if not active or mode == "":
		return
	# Your aim drifts in a slow loop (the camera, so you see it and can lead it).
	_sway_time += delta
	var reach := SWAY / board.global_position.distance_to(walker.camera.global_position)
	walker.camera.rotation.y = reach * sin(_sway_time * SWAY_SPEED)
	walker.camera.rotation.x = walker._pitch + reach * 0.6 * sin(_sway_time * SWAY_SPEED * 2.0 + 0.7)
	if charging:
		_charge_time += delta
		power = 0.5 - 0.5 * cos(_charge_time * TAU / POWER_CYCLE)
	_draw_bar()
	if turn == "them":
		_their_wait -= delta
		if _their_wait <= 0.0:
			if turn_darts.size() < DARTS_PER_TURN:
				trader_throw()
				_their_wait = TRADER_GAP
			else:
				_next_turn()


# --- Throwing ---------------------------------------------------------------------------------

## Throws where you're aiming, with `power` from the bar (SWEET is spot on).
func throw_dart(with_power := SWEET) -> void:
	var camera := walker.camera
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var normal := board.global_basis.z
	var hit: Vector3
	var landed := false
	if dir.dot(-normal) > 0.05:
		hit = from + dir * ((board.global_position - from).dot(normal) / dir.dot(normal))
		var off := with_power - SWEET
		if absf(off) < SWEET_BAND:
			off *= 0.25                           # (in the green: near enough spot on)
		hit += Vector3.UP * off * POWER_DROP
		hit += board.global_basis.x * _dice.randfn(0.0, HAND_SPREAD) + board.global_basis.y * _dice.randfn(0.0, HAND_SPREAD)
		landed = hit.distance_to(board.global_position) < 1.2
	_land(from + dir * 0.3, hit, landed)


## The trader's dart: aimed at their favourite spot, off by their spread.
func trader_throw() -> void:
	var info: Dictionary = TRADERS.get(mode, TRADERS["guns"])
	var target := Vector2.ZERO if info["aim"] == "BULL" else Vector2(0, (rings[2] + rings[3]) / 2.0)
	var at := target + Vector2(_dice.randfn(0.0, info["spread"]), _dice.randfn(0.0, info["spread"]))
	var hit := board.to_global(Vector3(at.x, at.y, 0.0))
	var from := board.to_global(Vector3(0.6, -0.1, 2.3))   # (from the line, just beside you)
	_land(from, hit, true)


func _land(from: Vector3, hit: Vector3, landed: bool) -> void:
	var normal := board.global_basis.z
	if not landed:   # (nowhere near: it drops under the board)
		hit = board.global_position + normal * 0.25 + Vector3.DOWN * (board.global_position.y - 0.02)
	var local := board.to_local(hit)
	var result := score_at(Vector2(local.x, local.y), rings) if landed else [0, "MISS"]
	turn_darts.append(result)
	if turn == "you":
		your_total += int(result[0])
	else:
		their_total += int(result[0])
	_fly_dart(from, hit, landed)
	if mode == "practice" and turn_darts.size() == DARTS_PER_TURN:
		best_round = maxi(best_round, turn_total())
	_show_score()


## Score and label (e.g. [60, "T20"]) for a dart at `at` (m on the board's face from its middle, y up).
static func score_at(at: Vector2, board_rings: PackedFloat32Array) -> Array:
	var r := at.length()
	if r <= board_rings[0]:
		return [50, "BULL"]
	if r <= board_rings[1]:
		return [25, "25"]
	if r > board_rings[5]:
		return [0, "MISS"]
	var wedge := int(fposmod(rad_to_deg(atan2(at.x, at.y)) + 9.0, 360.0) / 18.0) % 20
	var number: int = DART_NUMBERS[wedge]
	if r > board_rings[2] and r <= board_rings[3]:
		return [number * 3, "T%d" % number]
	if r > board_rings[4]:
		return [number * 2, "D%d" % number]
	return [number, str(number)]


func turn_total() -> int:
	var total := 0
	for result: Array in turn_darts:
		total += int(result[0])
	return total


## Pulls the darts out; the next turn (yours or the trader's), the next round, or the end of the game.
func _next_turn() -> void:
	_clear_board()
	turn_darts.clear()
	if mode == "practice":
		turn = "you"
	elif turn == "you":
		turn = "them"
		_their_wait = TRADER_GAP
	elif round_no < ROUNDS:
		round_no += 1
		turn = "you"
	else:
		turn = "over"
		var info: Dictionary = TRADERS.get(mode, TRADERS["guns"])
		var line: String = info["lose"] if your_total > their_total else info["win"] if their_total > your_total else "A draw. Again?"
		_say.text = "%s: \"%s\"" % [trader_name(mode), line]
	_show_score()


func _clear_board() -> void:
	for dart in _thrown:
		dart.queue_free()
	_thrown.clear()


# --- What you see -----------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 3
	_hud.visible = false
	add_child(_hud)
	_score = Label.new()
	_score.name = "Score"
	_score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.position = Vector2(-350, 12)
	_score.size = Vector2(700, 110)
	HudStyle.style_label(_score, 22)
	_hud.add_child(_score)
	_say = Label.new()
	_say.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say.position = Vector2(-400, -140)
	_say.size = Vector2(800, 30)
	HudStyle.style_label(_say, 22, HudStyle.BRASS)
	_hud.add_child(_say)
	# The power bar, right of the middle: fills as you wind up, the green band is the sweet spot.
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER)
	_bar.position = Vector2(150, -110)
	_bar.size = Vector2(26, 220)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.size = _bar.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(1.0, 0.85, 0.3, 0.9)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_fill)
	var sweet := ColorRect.new()
	sweet.color = Color(0.3, 0.85, 0.3, 0.65)
	sweet.position = Vector2(0, _bar.size.y * (1.0 - SWEET - SWEET_BAND))
	sweet.size = Vector2(_bar.size.x, _bar.size.y * SWEET_BAND * 2.0)
	sweet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(sweet)   # (over the fill, so you see it as you wind up)
	# Who to play: practice, or one of the traders.
	_picker = PanelContainer.new()
	_picker.name = "Picker"
	LootUI.skin_panel(_picker)
	_picker.set_anchors_preset(Control.PRESET_CENTER)
	_picker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_picker.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hud.add_child(_picker)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_picker.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "DARTS"
	HudStyle.style_label(title, 30)
	box.add_child(title)
	var how := Label.new()
	how.text = "Hold to wind up, let go in the green.\nToo soft drops low, too hard flies high."
	HudStyle.style_label(how, 18, HudStyle.INK_DIM)
	box.add_child(how)
	_pick_button(box, "practice", "PRACTICE")
	for who: String in TRADERS:
		_pick_button(box, who, "PLAY %s" % trader_name(who).to_upper())
	_pick_button(box, "", "WALK AWAY  (%s)" % HideoutWorld.use_key())


func _pick_button(box: Container, who: String, text: String) -> void:
	var button := Button.new()
	button.name = who if who != "" else "Leave"
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(320, 46)
	LootUI.style_button(button, 20)
	if who == "":
		button.pressed.connect(func() -> void: (get_parent() as HideoutToys).stand_up())
	else:
		button.pressed.connect(play.bind(who))
	box.add_child(button)


func _draw_bar() -> void:
	var shown := power if charging else 0.0
	_bar_fill.position = Vector2(4, _bar.size.y * (1.0 - shown))
	_bar_fill.size = Vector2(_bar.size.x - 8, _bar.size.y * shown)


func _show_score() -> void:
	var line := ""
	for k in DARTS_PER_TURN:
		line += ("   " if k > 0 else "") + (String(turn_darts[k][1]) if k < turn_darts.size() else "-")
	var click := "Click" if not GameSettings.is_phone() else "Tap"
	var key := HideoutWorld.use_key()
	if mode == "practice":
		var next := "%s: pull the darts out" % click if turn_darts.size() >= DARTS_PER_TURN else "Hold, let go in the green"
		_score.text = "PRACTICE    %s    %s: stop\n%s    =  %d\nBEST  %d" % [next, key, line, turn_total(), best_round]
		return
	var them := trader_name(mode).to_upper()
	var head := "ROUND %d/%d    YOU %d  :  %d %s" % [round_no, ROUNDS, your_total, their_total, them]
	var doing := ""
	match turn:
		"you":
			doing = "%s: pull the darts out" % click if turn_darts.size() >= DARTS_PER_TURN else "YOUR THROW"
		"them":
			doing = "%s THROWS" % them
		"over":
			doing = ("YOU WIN!" if your_total > their_total else "%s WINS" % them if their_total > your_total else "DRAW") \
				+ "    %s: play again    %s: stop" % [click, key]
	_score.text = "%s\n%s\n%s" % [head, line, doing]


func _fly_dart(from: Vector3, to: Vector3, landed: bool) -> void:
	var dart := _dart_mesh()
	add_child(dart)
	_thrown.append(dart)
	var point := (board.global_basis.z * -1.0).rotated(Vector3.UP, _dice.randf_range(-0.12, 0.12))
	dart.global_position = from
	dart.look_at(from + point, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(dart, "global_position", to + point * 0.02, DART_FLIGHT)
	if landed:
		tween.tween_callback(func() -> void: Effects.sound_at(self, DART_HIT, to, -4.0, 0.1, 1.0, 3.0, 25.0))
	else:
		tween.tween_callback(func() -> void: dart.rotation.x = -PI / 2.2)


static func _dart_mesh() -> Node3D:
	var dart := Node3D.new()
	dart.name = "Dart"
	for part: Array in [[Vector3(0.008, 0.008, 0.11), Vector3(0, 0, 0.05), Color(0.2, 0.2, 0.22)],
			[Vector3(0.002, 0.03, 0.035), Vector3(0, 0, 0.11), Color(0.75, 0.15, 0.12)],
			[Vector3(0.03, 0.002, 0.035), Vector3(0, 0, 0.11), Color(0.75, 0.15, 0.12)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = part[1]
		mesh.material_override = Effects.unshaded(part[2])
		dart.add_child(mesh)
	return dart


## The numbers round the board (white, like the wire ring on a real one).
func _paint_numbers() -> void:
	for k in DART_NUMBERS.size():
		var label := Label3D.new()
		label.text = str(DART_NUMBERS[k])
		label.font = HudStyle.font(24)
		label.font_size = 24
		label.pixel_size = 0.0018
		label.modulate = Color(0.95, 0.93, 0.85)
		label.shaded = false
		label.double_sided = false
		var angle := deg_to_rad(k * 18.0)
		var radius := (rings[5] + rings[6]) / 2.0
		label.position = Vector3(sin(angle) * radius, cos(angle) * radius, 0.004)
		board.add_child(label)
