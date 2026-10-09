extends Control
## Between raids: your stash, your loadout, and the trader. START RAID loads the raid.
## Everything here is saved to the Profile as soon as it changes.

const RAID_SCENE := "res://scenes/main.tscn"
const BUY_MARKUP := 1.2
## Valuables sell for full value; everything else for this fraction.
const GEAR_SELL_RATE := 0.6
## [item id, amount per purchase]
const TRADER_STOCK := [
	["ak", 1], ["pistol", 1], ["rifle_ammo", 60], ["pistol_ammo", 50], ["bandage", 1],
	["medkit", 1], ["armor_light", 1], ["backpack_small", 1], ["backpack_medium", 1],
]
const FREE_KIT_HINT := "Free kit: pistol, 30 rounds and a bandage. Only when you own no weapon and can't afford one."

var inventory: Inventory
var screen: LootUI

var _money_label: Label
var _version_label: Label
var _stats_label: Label
## Messages (bought, sold, no room...) show under the top bar so long ones aren't cut off, then fade.
var _message_label: Label
var _message_tween: Tween
const MESSAGE_MAX_WIDTH := 800.0
var _online_button: Button
var _free_kit_button: Button
var _online_panel: PanelContainer
var _offline_box: VBoxContainer
var _online_box: VBoxContainer
var _name_edit: LineEdit
var _connect_button: Button
var _party_label: Label
var _party_members: Label
var _join_row: HBoxContainer
var _party_code_edit: LineEdit
var _leave_party_button: Button
var _queue_button: Button
var _queue_info: Label
var _start_now_button: Button
var _online_status: Label
var _save_queued := false


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Back from an online raid: still online, in the same party (tell the server we're out of the raid).
	Network.main.leave_raid()
	Profile.load_profile()
	GameSettings.load_settings()

	var background := ColorRect.new()
	background.color = Color(0.1, 0.11, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	inventory = Inventory.new()
	add_child(inventory)
	Profile.apply_inventory(inventory, Profile.loadout)

	screen = LootUI.new(null, inventory)
	screen.sell_handler = sell
	screen.price_handler = sell_price
	add_child(screen)
	screen.set_top_margin(56)
	screen.open_stash(Profile.stash)
	screen.add_column(_build_trader())

	_build_top_bar()
	_build_online_panel()
	var net := Network.main
	net.raid_started.connect(start_raid)
	net.connected.connect(func() -> void:
		_online_status.text = ""
		_refresh_online())
	net.connect_failed.connect(_on_connect_failed)
	net.connection_lost.connect(_on_connection_lost)
	net.party_changed.connect(_refresh_online)
	net.queue_changed.connect(_refresh_online)
	net.notice.connect(func(text: String) -> void: _online_status.text = text)
	# Came back from an online raid: show the party/queue screen again.
	if net.is_client():
		_online_panel.visible = true
	inventory.changed.connect(_queue_save)
	Profile.stash.changed.connect(_queue_save)
	_refresh()


# --- Trading -----------------------------------------------------------------------

func buy_price(id: String, amount: int) -> int:
	return ceili(ItemDB.value(id) * amount * BUY_MARKUP)


func sell_price(stack: ItemStack) -> int:
	var rate := 1.0 if ItemDB.kind(stack.id) == "valuable" else GEAR_SELL_RATE
	return roundi(stack.value() * rate)


## Buys `amount` of an item into the stash. Returns true if it worked.
func buy(id: String, amount: int) -> bool:
	var price := buy_price(id, amount)
	if Profile.money < price:
		_message("Not enough money for %s (%s)" % [ItemDB.display_name(id), ItemDB.money(price)])
		return false
	var stash := Profile.stash
	if ItemDB.max_stack(id) == 1:
		var spot := stash.find_spot(id)
		if spot.is_empty():
			_message("No room in your stash")
			return false
		stash.place(ItemStack.new(id, 1, spot[0], spot[1], spot[2]))
	else:
		var left := stash.add(id, amount)
		if left >= amount:
			_message("No room in your stash")
			return false
		price = buy_price(id, amount - left)
	Profile.money -= price
	_message("Bought %s for %s" % [ItemDB.display_name(id), ItemDB.money(price)])
	_queue_save()
	return true


func sell(grid: GridInventory, stack: ItemStack) -> void:
	var price := sell_price(stack)
	grid.remove(stack)
	Profile.money += price
	Profile.stats["earned"] += price
	_message("Sold %s for %s" % [ItemDB.label(stack.id, stack.count), ItemDB.money(price)])
	_queue_save()


## True if you own any weapon (stash or loadout).
func owns_weapon() -> bool:
	for stack in Profile.stash.stacks + inventory.all_stacks():
		if ItemDB.kind(stack.id) == "weapon":
			return true
	return false


func can_take_free_kit() -> bool:
	return not owns_weapon() and Profile.money < buy_price("pistol", 1)


func take_free_kit() -> bool:
	if not can_take_free_kit():
		return false
	var pistol := ItemStack.new("pistol")
	pistol.loaded = int(ItemDB.item("pistol")["mag"])
	if not inventory.equip("secondary", pistol):
		var spot := Profile.stash.find_spot("pistol")
		if spot.is_empty():
			return false
		pistol.set_spot(Vector2i(spot[0], spot[1]), spot[2])
		Profile.stash.place(pistol)
	for kit_item in [["pistol_ammo", 30], ["bandage", 1]]:
		var left := inventory.add(kit_item[0], kit_item[1])
		if left > 0:
			Profile.stash.add(kit_item[0], left)
	_message("Took the free kit. Good luck out there.")
	_queue_save()
	return true


func start_raid() -> void:
	save_now()
	get_tree().change_scene_to_file(RAID_SCENE)


# --- Saving / UI -------------------------------------------------------------------

func _queue_save() -> void:
	if not _save_queued:
		_save_queued = true
		save_now.call_deferred()


func save_now() -> void:
	_save_queued = false
	Profile.loadout = Profile.capture_inventory(inventory)
	Profile.save_profile()
	_refresh()


func _refresh() -> void:
	if _money_label == null:
		return
	_money_label.text = ItemDB.money(Profile.money)
	_stats_label.text = "Raids %d · Extracts %d · Deaths %d · Stash worth %s" % [
		int(Profile.stats["raids"]), int(Profile.stats["extracts"]), int(Profile.stats["deaths"]),
		ItemDB.money(Profile.stash.total_value())]
	_free_kit_button.visible = can_take_free_kit()


func _message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	# Fit the tape to the text (up to 800 px; longer messages wrap), centered under the bar.
	var width := minf(HudStyle.tape_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 30.0, MESSAGE_MAX_WIDTH)
	_message_label.custom_minimum_size = Vector2(width, 0)
	_message_label.offset_left = -width * 0.5
	_message_label.offset_right = width * 0.5
	_message_label.modulate.a = 1.0
	if _message_tween != null:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(3.5)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.6)


func _build_top_bar() -> void:
	# Look (0.8.11, "Ammo Can"): a gunmetal strip, the pixel font, money on a brass tag, a hazard-yellow START RAID.
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 50
	LootUI.skin_panel(bar, 3.0)
	add_child(bar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var title := Label.new()
	title.text = "BLOXOV"
	HudStyle.style_label(title, 30)
	row.add_child(title)
	var place := Label.new()
	place.text = "HIDEOUT"
	HudStyle.style_label(place, 20, HudStyle.INK_DIM)
	row.add_child(place)
	# Same dim style as the version in the corner during a raid.
	_version_label = Label.new()
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	HudStyle.style_label(_version_label, 20, Color(HudStyle.INK, 0.4))
	row.add_child(_version_label)
	# Money on a brass tag.
	_money_label = Label.new()
	HudStyle.style_label(_money_label, 30, HudStyle.DEEP)
	_money_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var tag := StyleBoxFlat.new()
	tag.bg_color = HudStyle.BRASS
	tag.border_color = HudStyle.BRASS_DK
	tag.set_border_width_all(2)
	tag.border_width_bottom = 4
	tag.content_margin_left = 10
	tag.content_margin_right = 10
	_money_label.add_theme_stylebox_override("normal", tag)
	_money_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_money_label)
	_stats_label = Label.new()
	HudStyle.style_label(_stats_label, 20, HudStyle.INK_DIM)
	_stats_label.add_theme_font_override("font", HudStyle.spaced_font(20))
	row.add_child(_stats_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	# Messages are written on a strip of masking tape stuck under the bar (sized to the text, centered; see _message).
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.offset_top = 46
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # (long ones wrap, never cut off)
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_label.add_theme_font_override("font", HudStyle.tape_font())
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", HudStyle.TAPE_INK)
	var tape := StyleBoxFlat.new()
	tape.bg_color = HudStyle.TAPE
	tape.shadow_color = Color(0, 0, 0, 0.45)
	tape.shadow_offset = Vector2(2, 3)
	tape.shadow_size = 1
	tape.content_margin_left = 14
	tape.content_margin_right = 14
	tape.content_margin_top = 3
	tape.content_margin_bottom = 3
	_message_label.add_theme_stylebox_override("normal", tape)
	_message_label.modulate.a = 0.0  # (no message yet: hide the empty tape)
	add_child(_message_label)
	_free_kit_button = Button.new()
	_free_kit_button.text = "Free kit"
	_free_kit_button.tooltip_text = FREE_KIT_HINT
	_free_kit_button.focus_mode = Control.FOCUS_NONE
	_free_kit_button.pressed.connect(take_free_kit)
	LootUI.style_button(_free_kit_button)
	row.add_child(_free_kit_button)
	var raid_button := Button.new()
	raid_button.text = "START RAID"
	raid_button.custom_minimum_size = Vector2(150, 0)
	raid_button.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(raid_button, 30, HudStyle.HAZARD)
	raid_button.pressed.connect(func() -> void:
		Network.main.go_offline()  # START RAID is always solo (against the AI), so leave online play.
		start_raid())
	row.add_child(raid_button)
	_online_button = Button.new()
	_online_button.text = "ONLINE"
	_online_button.tooltip_text = "Queue into raids with other players, or party up with a friend"
	_online_button.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(_online_button)
	_online_button.pressed.connect(func() -> void: _online_panel.visible = not _online_panel.visible)
	row.add_child(_online_button)


# --- Online --------------------------------------------------------------------------
## The online panel (JOIN ONLINE): go online, party up with a friend's code, queue, or start a raid right away.
## Raids start when the server says so (Network.raid_started).

## Connects to the server with the address and name in the panel.
func go_online(address: String, player_name: String) -> void:
	if address.strip_edges() == "":
		_online_status.text = "Enter the server address."
		return
	GameSettings.set_online(address.strip_edges(), player_name.strip_edges())
	save_now()
	_online_status.text = "Connecting... (a sleeping server can take a few seconds to wake up)"
	_connect_button.disabled = true
	Network.main.go_online(address, player_name)


func _on_connect_failed(reason: String) -> void:
	_online_status.text = reason
	_refresh_online()


func _on_connection_lost() -> void:
	_online_status.text = "Lost the connection to the server."
	_refresh_online()


## The ONLINE button says where you are, so you know even with the panel closed.
func online_status() -> String:
	var net := Network.main
	if not net.is_client():
		return "ONLINE"
	if net.queued and net.queue_countdown >= 0.0:
		return "RAID IN %ds" % ceili(net.queue_countdown)
	if net.queued:
		return "IN QUEUE (%d/%d)" % [net.queue_waiting, Matchmaker.MIN_PLAYERS]
	return "ONLINE ●"


## Redraws the online panel from what the server last told us.
func _refresh_online() -> void:
	if _online_panel == null:
		return
	var net := Network.main
	var online := net.is_client()
	_online_button.text = online_status()
	_offline_box.visible = not online
	_online_box.visible = online
	_connect_button.disabled = net.is_online() and not online
	if not online:
		return
	_party_label.text = "Your party code: %s" % net.party_code
	var who := PackedStringArray()
	for i in net.party_names.size():
		who.append(net.party_names[i] + (" (leader)" if i == 0 and net.party_names.size() > 1 else ""))
	_party_members.text = "In your party: " + ", ".join(who)
	var in_party := net.party_names.size() > 1
	_join_row.visible = not in_party
	_leave_party_button.visible = in_party
	_queue_button.visible = net.is_leader
	_start_now_button.visible = net.is_leader
	_queue_button.text = "CANCEL QUEUE" if net.queued else "QUEUE"
	if not net.is_leader:
		_queue_info.text = "Your party leader starts the queue." + (" Queued..." if net.queued else "")
	elif net.queued and net.queue_countdown >= 0.0:
		_queue_info.text = "Raid starts in %d s · %d players" % [ceili(net.queue_countdown), net.queue_waiting]
	elif net.queued:
		_queue_info.text = "Waiting for more players (%d in the queue, needs %d)" % [net.queue_waiting, Matchmaker.MIN_PLAYERS]
	else:
		_queue_info.text = "%d players in the queue right now" % net.queue_waiting


func _build_online_panel() -> void:
	_online_panel = PanelContainer.new()
	_online_panel.visible = false
	_online_panel.set_anchors_preset(Control.PRESET_CENTER)
	_online_panel.custom_minimum_size = Vector2(460, 0)
	_online_panel.position = Vector2(-230, -170)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.13, 0.98)
	style.border_color = Color(0.45, 0.5, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_online_panel.add_theme_stylebox_override("panel", style)
	add_child(_online_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_online_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ONLINE"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	# Not connected: name + server, Go online.
	_offline_box = VBoxContainer.new()
	_offline_box.add_theme_constant_override("separation", 8)
	column.add_child(_offline_box)
	var hint := Label.new()
	hint.text = "Queue into raids with other players (solos and duos, up to %d per raid). Party up with a friend using your party code." % Matchmaker.MAX_PLAYERS
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.7)
	_offline_box.add_child(hint)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 16
	_name_edit.text = GameSettings.player_name if GameSettings.player_name != "" else "Player %d" % randi_range(100, 999)
	_offline_box.add_child(_name_edit)
	# Always the game's own server (owner: no address box).
	_connect_button = Button.new()
	_connect_button.text = "Go online"
	_connect_button.pressed.connect(func() -> void: go_online(Network.DEFAULT_ADDRESS, _name_edit.text))
	_offline_box.add_child(_connect_button)

	# Connected: party, queue, start now.
	_online_box = VBoxContainer.new()
	_online_box.add_theme_constant_override("separation", 8)
	column.add_child(_online_box)
	_party_label = Label.new()
	_party_label.add_theme_font_size_override("font_size", 18)
	_online_box.add_child(_party_label)
	_party_members = Label.new()
	_party_members.modulate = Color(1, 1, 1, 0.8)
	_online_box.add_child(_party_members)
	_join_row = HBoxContainer.new()
	_online_box.add_child(_join_row)
	_party_code_edit = LineEdit.new()
	_party_code_edit.placeholder_text = "Friend's party code"
	_party_code_edit.max_length = 4
	_party_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_row.add_child(_party_code_edit)
	var join_button := Button.new()
	join_button.text = "Join party"
	join_button.pressed.connect(func() -> void: Network.main.join_party(_party_code_edit.text))
	_join_row.add_child(join_button)
	_leave_party_button = Button.new()
	_leave_party_button.text = "Leave party"
	_leave_party_button.pressed.connect(func() -> void: Network.main.leave_party())
	_online_box.add_child(_leave_party_button)
	_queue_button = Button.new()
	_queue_button.custom_minimum_size = Vector2(0, 40)
	_queue_button.add_theme_font_size_override("font_size", 20)
	_queue_button.pressed.connect(func() -> void: Network.main.set_queued(not Network.main.queued))
	_online_box.add_child(_queue_button)
	_queue_info = Label.new()
	_queue_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_box.add_child(_queue_info)
	_start_now_button = Button.new()
	_start_now_button.text = "Start now: just my party, no queue"
	_start_now_button.tooltip_text = "An online raid with only you (and your party). For testing."
	_start_now_button.pressed.connect(func() -> void: Network.main.start_now())
	_online_box.add_child(_start_now_button)
	var offline_button := Button.new()
	offline_button.text = "Go offline"
	offline_button.pressed.connect(func() -> void:
		Network.main.go_offline()
		_online_status.text = ""
		_refresh_online())
	_online_box.add_child(offline_button)

	_online_status = Label.new()
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_status.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	column.add_child(_online_status)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _online_panel.visible = false)
	column.add_child(close)
	_refresh_online()


func _build_trader() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	LootUI.skin_panel(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := Label.new()
	title.text = "TRADER"
	HudStyle.style_label(title, 30)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Buy: goes to your stash.\nSell: right-click any item.\nValuables sell for full value,\ngear for %d%%." % roundi(GEAR_SELL_RATE * 100)
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	for entry in TRADER_STOCK:
		var id: String = entry[0]
		var amount: int = entry[1]
		var row := HBoxContainer.new()
		box.add_child(row)
		var item_name := Label.new()
		item_name.text = ItemDB.label(id, amount)
		HudStyle.style_label(item_name, 20, ItemDB.color(id))
		item_name.add_theme_font_override("font", HudStyle.spaced_font(20))
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_name)
		var button := Button.new()
		button.text = ItemDB.money(buy_price(id, amount))
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(76, 0)
		LootUI.style_button(button)
		button.pressed.connect(buy.bind(id, amount))
		row.add_child(button)
	return panel
