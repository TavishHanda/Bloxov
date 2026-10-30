class_name RaidTips
extends Control
## Tips for new players in a raid (0.24.0, the new-player tutorial): each one comes up once, the first time its
## moment comes (the raid starts, a container to search, you get hit, a ladder, an extract), for a few seconds on a
## card under the raid timer. Seen tips are saved with the profile at the end of the raid; "Raid tips" in the pause
## menu and in OPTIONS turns them off. Looks only: nothing here is sent online or changes how the raid plays.

## Tip id -> text ({keys} filled in by Tutorial.keys).
const TIPS := {
	"start": "Find loot, then get out at an open extract (green beam). {extracts} lists them, {map} opens the map. Still here when time runs out? You lose what you brought.",
	"search": "Hold {use} to search. {tab} opens your bag to move loot round.",
	"hurt": "You're hit. Press {heal} to heal with a bandage or medkit (it takes a few seconds).",
	"ladder": "Walk into a ladder to climb it.",
	"moves": "{jump} vaults low walls and climbs ledges. {crouch} crouches, {prone} goes prone: harder to see and hit.",
	"extract": "Stay in the extract until its timer runs out to get out with everything you carry.",
}
const SHOW_TIME := 9.0
## When the movement tip comes up (seconds into the raid), if nothing else is showing.
const MOVES_AT := 60.0

var player: Player
var hud_extracts: ExtractHUD
var _queue: Array[String] = []
var _showing := ""
var _left := 0.0
var _raid_time := 0.0
var _card: PanelContainer
var _text: Label


func _init(owner_player: Player, extracts: ExtractHUD) -> void:
	player = owner_player
	hud_extracts = extracts
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE   # (the HUD runs while paused; tips wait with the game)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.position = Vector2(-280, 70)
	_card.custom_minimum_size = Vector2(560, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(HudStyle.FACE, 0.9)
	style.border_color = HudStyle.BRASS
	style.set_border_width_all(3)
	style.set_content_margin_all(10)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(540, 0)
	HudStyle.style_label(_text, 20)
	_card.add_child(_text)
	_card.visible = false
	player.health.damaged.connect(func(_amount: int, _from: Vector3) -> void: want("hurt"))


static func on() -> bool:
	return Profile.tutorial.get("tips", false) == true


static func seen(id: String) -> bool:
	return (Profile.tutorial.get("seen", []) as Array).has(id)


## Shows tip `id` (after any already queued) unless it was seen before or tips are off.
func want(id: String) -> void:
	if not on() or seen(id) or _queue.has(id) or _showing == id:
		return
	_queue.append(id)


func showing() -> String:
	return _showing


func _process(delta: float) -> void:
	if not on():
		_queue.clear()
		_showing = ""
		_card.visible = false
		return
	_raid_time += delta
	if _raid_time > 2.0:
		want("start")
	if player.interactor.target != null:
		want("search")
	if player.near_ladder():
		want("ladder")
	if not hud_extracts.status().is_empty():
		want("extract")
	if _raid_time > MOVES_AT:
		want("moves")
	_left -= delta
	if _showing != "" and _left <= 0.0:
		_showing = ""
	if _showing == "" and not _queue.is_empty():
		_showing = _queue.pop_front()
		_left = SHOW_TIME
		(Profile.tutorial["seen"] as Array).append(_showing)   # (saved with the raid's result)
		_text.text = Tutorial.keys(String(TIPS[_showing]))
	_card.visible = _showing != ""
