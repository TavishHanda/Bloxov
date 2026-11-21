class_name CharacterScreen
extends Control
## The characters (0.37.0, see Characters): pick who you play, unlock more (in-game money and a trader level), and
## spend upgrade points. Left: the six, middle: the picked one's level, traits and passive, right: their points and
## the button to the skill tree (SkillTree, 0.39.1: the points get their own menu).
## Online the server checks every change (OnlineProfile.audit); this screen only offers what it would allow.

const SIDE_WIDTH := 300.0

var hideout: Node
## The character being looked at (not always the one picked).
var showing := "vega"
var _list := {}
var _name: Label
var _role: Label
var _level: Label
var _bio: Label
var _traits: VBoxContainer
var _passive: Label
var _action: Button
var _status: Label
var _points: Label
var _spend: VBoxContainer
var _reset: Button
var _banner: Label
var _view: SubViewport
var _skins: HBoxContainer
var _needs: VBoxContainer
## The upgrade points' own menu (SkillTree), over this screen.
var tree: SkillTree


func _init(menu: Node) -> void:
	hideout = menu
	name = "CharacterScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_top = 56
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.1, 0.11, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	margin.add_child(columns)

	var left := _panel(columns, SIDE_WIDTH)
	left.add_child(_heading("CHARACTERS"))
	for id: String in Characters.ORDER:
		var button := Button.new()
		button.name = id
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 48)
		LootUI.style_button(button, 22)
		button.pressed.connect(func() -> void: look_at_character(id))
		left.add_child(button)
		_list[id] = button

	var middle := _panel(columns, 0.0)
	middle.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The first pick (0.38.3, 0.39: make it obvious): a banner over everything until VEGA or VOSS is chosen.
	_banner = _heading("CHOOSE YOUR FIRST CHARACTER: VEGA (Nova) or VOSS (Exion)")
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", HudStyle.BRASS)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_banner)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	middle.add_child(top)
	top.add_child(_build_preview())
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	_name = _heading("")
	_name.add_theme_font_size_override("font_size", 44)
	titles.add_child(_name)
	_role = _text(20, HudStyle.BRASS)
	titles.add_child(_role)
	_level = _text(20)
	titles.add_child(_level)
	_skins = HBoxContainer.new()
	_skins.add_theme_constant_override("separation", 6)
	titles.add_child(_skins)
	_needs = VBoxContainer.new()
	titles.add_child(_needs)
	_bio = _text(16, HudStyle.INK_DIM)
	middle.add_child(_bio)
	_traits = VBoxContainer.new()
	_traits.add_theme_constant_override("separation", 2)
	middle.add_child(_traits)
	_passive = _text(18)
	middle.add_child(_passive)
	_action = Button.new()
	_action.name = "Action"
	_action.focus_mode = Control.FOCUS_NONE
	_action.custom_minimum_size = Vector2(0, 52)
	LootUI.style_button(_action, 26)
	_action.pressed.connect(_on_action)
	middle.add_child(_action)
	_status = _text(16, HudStyle.INK_DIM)
	middle.add_child(_status)
	var note := _text(13, Color(1, 1, 1, 0.5))
	note.text = "Traits grow from level 1 to 20, the good and the bad. Level by playing raids as them. Upgrade points are shared: any character earns them (2 at level 10, 3 at level 20, 2 for each expedition escape, up to 10 per character) and you spend them on whoever you like."
	middle.add_child(note)

	var right := _panel(columns, SIDE_WIDTH)
	right.add_child(_heading("UPGRADES"))
	_points = _text(20, HudStyle.BRASS)
	right.add_child(_points)
	_reset = Button.new()
	_reset.name = "SkillTreeButton"
	_reset.text = "OPEN SKILL TREE"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.custom_minimum_size = Vector2(0, 64)
	LootUI.style_button(_reset, 24)
	_reset.pressed.connect(open_tree)
	right.add_child(_reset)
	_spend = VBoxContainer.new()
	_spend.add_theme_constant_override("separation", 4)
	right.add_child(_spend)
	tree = SkillTree.new(self)
	add_child(tree)


## The character, drawn by its own little camera in its own world (like the stash screen's).
func _build_preview() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(190, 250)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.size = Vector2i(190, 250)
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(_view)
	var camera := Camera3D.new()
	camera.fov = 30.0
	var eye := Vector3(0, 1.25, 5.6)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0, 1.1, 0) - eye), eye)
	_view.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.5, 0)
	_view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	_view.add_child(environment)
	return holder


func _show_model(id: String, skin: String) -> void:
	var old := _view.get_node_or_null("Character")
	if old != null and old.get_meta("who", "") == id + "/" + skin:
		return
	if old != null:
		_view.remove_child(old)
		old.queue_free()
	var model := PlayableModels.make(id, skin)
	model.name = "Character"
	model.set_meta("who", id + "/" + skin)
	model.rotation.y = PI + 0.35
	_view.add_child(model)
	var stance := BodyPose.new(model)
	stance.armed = false
	stance.update(0.0)


func _panel(parent: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	LootUI.skin_panel(panel)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	HudStyle.style_label(label, 30)
	return label


func _text(size: int, color := HudStyle.INK) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func open() -> void:
	showing = str(Profile.characters.get("selected", "vega"))
	visible = true
	tree.visible = false
	refresh()


func look_at_character(id: String) -> void:
	showing = id
	refresh()


func _unlocked(id: String) -> bool:
	return Profile.characters.get("picked", true) and (Profile.characters["unlocked"] as Array).has(id)


func refresh() -> void:
	var state := Profile.characters
	for id: String in _list:
		var button: Button = _list[id]
		var tag := " (PLAYING)" if state["selected"] == id and state.get("picked", true) else ("" if _unlocked(id) and state.get("picked", true) else " (LOCKED)")
		if not state.get("picked", true) and Characters.STARTERS.has(id):
			tag = " (CHOOSE)"
		button.text = str(Characters.LIST[id]["name"]) + tag
		button.button_pressed = id == showing
	var info: Dictionary = Characters.LIST[showing]
	var c := Characters.char_of(state, showing)
	_name.text = str(info["name"])
	var side := str(info.get("side", ""))
	_role.text = str(info["role"]) + (" · %s" % side.to_upper() if side != "" else "")
	var lv := Characters.level(state, showing)
	var bar := Characters.level_progress(int(c["xp"]))
	_level.text = "Level %d / %d" % [lv, Characters.MAX_LEVEL] + ("  ·  %d / %d XP" % [bar[0], bar[1]] if int(bar[1]) > 0 else "  ·  top level")
	_bio.text = str(info["bio"])
	var picked: bool = state.get("picked", true)
	_banner.visible = not picked
	var skin := Characters.skin_of(state, showing)
	_show_model(showing, skin)
	for child in _skins.get_children():
		child.queue_free()
	for option: String in Characters.SKINS[showing]:
		var b := Button.new()
		b.name = "Skin_" + option
		b.text = option.to_upper()
		b.toggle_mode = true
		b.button_pressed = option == skin
		b.focus_mode = Control.FOCUS_NONE
		LootUI.style_button(b, 14)
		b.disabled = not _unlocked(showing)
		b.pressed.connect(func() -> void: pick_skin(option))
		_skins.add_child(b)
	_skins.visible = _unlocked(showing)
	for child in _needs.get_children():
		child.queue_free()
	if not _unlocked(showing) and not (not picked and Characters.STARTERS.has(showing)):
		var head := _text(16, HudStyle.BRASS)
		head.text = "TO UNLOCK:"
		_needs.add_child(head)
		for need: Array in Characters.requirements(state, showing, Profile.money, Profile.trader_levels):
			var row := _text(16, HudStyle.LIFE if need[1] else HudStyle.BLOOD)
			row.text = ("DONE  " if need[1] else "NEEDED  ") + str(need[0])
			_needs.add_child(row)
	for child in _traits.get_children():
		child.queue_free()
	for i in 4:
		var stat := str(info["traits"][i][0])
		var value := Characters.trait_value(showing, c, i)
		var row := _text(18, HudStyle.LIFE if i < 2 else HudStyle.BLOOD)
		row.text = "%s%.1f%%  %s" % ["+" if value >= 0.0 else "", value * 100.0, Characters.STAT_NAMES[stat]]
		_traits.add_child(row)
	var passive: Dictionary = Characters.PASSIVES[info["passive"]]
	var rank := Characters.passive_rank(c)
	_passive.text = "%s (rank %d): %s %s" % [passive["name"], rank, passive["about"], passive["rank_text"][rank - 1]]
	if state["selected"] == showing and state.get("picked", true):
		_action.text = "PLAYING"
		_action.disabled = true
		_status.text = ""
	elif _unlocked(showing):
		_action.text = "PLAY AS %s" % info["name"]
		_action.disabled = false
		_status.text = ""
	elif not state.get("picked", true) and Characters.STARTERS.has(showing):
		_action.text = "CHOOSE %s (FREE)" % info["name"]
		_action.disabled = false
		_status.text = "VEGA or VOSS. The one you don't choose costs %s to unlock later." % ItemDB.money(Characters.STARTER_PRICE)
	else:
		var problem := Characters.unlock_problem(state, showing, Profile.money, Profile.trader_levels)
		_action.text = "UNLOCK  %s" % ItemDB.money(int(info["price"])) if int(info["price"]) > 0 else "LOCKED"
		_action.disabled = problem != ""
		_status.text = problem
	_fill_points(c, _unlocked(showing))


## The right panel: points left, the button to the skill tree, and what this character has bought.
func _fill_points(c: Dictionary, unlocked: bool) -> void:
	for child in _spend.get_children():
		child.queue_free()
	var state := Profile.characters
	_points.text = "%d points to spend (shared by all characters, %d earned)" % [Characters.points_left(state), Characters.points_earned(state)]
	var info: Dictionary = Characters.LIST[showing]
	for key: String in ["u0", "u1", "d0", "d1", "p"]:
		var spent := int(c["spent"].get(key, 0))
		var row := _text(15, HudStyle.INK if spent > 0 else HudStyle.INK_DIM)
		if key == "p":
			row.text = "%s: rank %d / 3" % [Characters.PASSIVES[info["passive"]]["name"], Characters.passive_rank(c)]
		else:
			var index := 0 if key == "u0" else 1 if key == "u1" else 2 if key == "d0" else 3
			var cap := Characters.UPSIDE_MAX if key.begins_with("u") else Characters.DOWNSIDE_MAX
			row.text = "%s %s: %d / %d" % ["Boost" if key.begins_with("u") else "Shrink",
				Characters.STAT_NAMES[str(info["traits"][index][0])], spent, cap]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_spend.add_child(row)
	_reset.disabled = false
	_reset.tooltip_text = "" if unlocked else "Look around the tree; unlock %s to spend points." % info["name"]


## The skill tree for the character being looked at (owner 2026-11-20: its own menu).
func open_tree() -> void:
	tree.open()


func _on_action() -> void:
	var state := Profile.characters
	if not state.get("picked", true):
		var keep: Dictionary = state.duplicate(true)
		if not Characters.pick_starter(state, showing):
			return
		if not _fit_pockets():
			Profile.characters = keep
			hideout.show_message("Make room in your stash first: your pockets get smaller.")
			refresh()
			return
		hideout.show_message("You play as %s. The other starter unlocks for %s." % [Characters.LIST[showing]["name"], ItemDB.money(Characters.STARTER_PRICE)])
	elif _unlocked(showing):
		var before := str(state["selected"])
		state["selected"] = showing
		if not _fit_pockets():
			state["selected"] = before
			hideout.show_message("Make room in your stash first: your pockets get smaller.")
			refresh()
			return
	elif Characters.unlock_problem(state, showing, Profile.money, Profile.trader_levels) == "":
		Profile.money -= int(Characters.LIST[showing]["price"])
		(state["unlocked"] as Array).append(showing)
		hideout.show_message("%s unlocked." % Characters.LIST[showing]["name"])
	_changed()


## Looks only (0.39): the skin `showing` wears.
func pick_skin(skin: String) -> void:
	if not _unlocked(showing):
		return
	Profile.characters.get_or_add("skins", {})[showing] = skin
	_changed()


func spend(key: String) -> void:
	if not Characters.spend(Profile.characters, showing, key):
		return
	_fit_pockets()   # (Pack Rat only grows the pockets)
	_changed()


## Every point on this character back to the pool, for RESET_COST (from the skill tree).
func reset_points() -> void:
	if Profile.money < Characters.RESET_COST:
		return
	var state := Profile.characters
	var keep: Dictionary = Characters.char_of(state, showing)["spent"].duplicate()
	Characters.reset_points(state, showing)
	if not _fit_pockets():
		Characters.char_of(state, showing)["spent"] = keep
		hideout.show_message("Make room in your stash first: your pockets get smaller.")
		refresh()
		return
	Profile.money -= Characters.RESET_COST
	_changed()


## The pockets take the picked character's width (KORR's Pack Rat); what no longer fits goes to the stash. False
## (and nothing moved) when the stash has no room for it.
func _fit_pockets() -> bool:
	var inventory: Inventory = hideout.inventory
	var width := Characters.pocket_width(Profile.characters)
	if inventory.pockets.width == width:
		return true
	var spots := []
	var trial := GridInventory.new("Stash", Profile.stash.width, Profile.stash.height)
	for stack: ItemStack in Profile.stash.stacks:
		trial.stacks.append(stack)
	for stack: ItemStack in inventory.pockets.stacks:
		if stack.x + ItemDB.rotated_size(stack.id, stack.rotated).x > width:
			var spot := trial.find_spot(stack.id)
			if spot.is_empty():
				return false
			var ghost := ItemStack.new(stack.id, stack.count, spot[0], spot[1], spot[2])
			trial.stacks.append(ghost)
			spots.append([stack, spot])
	for entry: Array in spots:
		var stack: ItemStack = entry[0]
		inventory.pockets.stacks.erase(stack)
		stack.x = entry[1][0]
		stack.y = entry[1][1]
		stack.rotated = entry[1][2]
		Profile.stash.place(stack)
	inventory.set_pocket_width(width)
	inventory.equipment_changed.emit()
	return true


func _changed() -> void:
	Network.main.set_look(Operators.to_text(Profile.look) + Characters.net_tag(Profile.characters))
	hideout.save_now()
	if hideout.get("screen") != null:
		hideout.screen.show_look()   # (the stash screen's character, 0.39)
	if hideout.has_method("update_character_button"):
		hideout.update_character_button()
	refresh()
