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
var _stats_label: Label
var _message_label: Label
var _free_kit_button: Button
var _save_queued := false


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	if _message_label != null:
		_message_label.text = text


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 50
	add_child(bar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var title := Label.new()
	title.text = "BLOXOV  ·  HIDEOUT"
	title.add_theme_font_size_override("font_size", 22)
	row.add_child(title)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 22)
	_money_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.5))
	row.add_child(_money_label)
	_stats_label = Label.new()
	_stats_label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(_stats_label)
	_message_label = Label.new()
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.clip_text = true
	_message_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	row.add_child(_message_label)
	_free_kit_button = Button.new()
	_free_kit_button.text = "Free kit"
	_free_kit_button.tooltip_text = FREE_KIT_HINT
	_free_kit_button.focus_mode = Control.FOCUS_NONE
	_free_kit_button.pressed.connect(take_free_kit)
	row.add_child(_free_kit_button)
	var raid_button := Button.new()
	raid_button.text = "START RAID"
	raid_button.custom_minimum_size = Vector2(150, 0)
	raid_button.add_theme_font_size_override("font_size", 20)
	raid_button.focus_mode = Control.FOCUS_NONE
	raid_button.pressed.connect(start_raid)
	row.add_child(raid_button)


func _build_trader() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := Label.new()
	title.text = "TRADER"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Buy: goes to your stash.\nSell: right-click any item.\nValuables sell for full value,\ngear for %d%%." % roundi(GEAR_SELL_RATE * 100)
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	for entry in TRADER_STOCK:
		var id: String = entry[0]
		var amount: int = entry[1]
		var row := HBoxContainer.new()
		box.add_child(row)
		var item_name := Label.new()
		item_name.text = ItemDB.label(id, amount)
		item_name.add_theme_color_override("font_color", ItemDB.color(id))
		item_name.add_theme_font_size_override("font_size", 13)
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_name)
		var button := Button.new()
		button.text = ItemDB.money(buy_price(id, amount))
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(76, 0)
		button.pressed.connect(buy.bind(id, amount))
		row.add_child(button)
	return panel
