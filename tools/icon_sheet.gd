extends SceneTree
## A sheet of inventory tiles with pictures, for showing icon looks to the owner (made by tools/render_icons.gd).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/icon_sheet.gd -- dirs=/tmp/a,/tmp/b names=A,B out=/tmp/sheet.png
## Without dirs it shows the game's own icons (assets/icons/items).
const LAYOUT := [
	["ak", 0, 0], ["backpack_medium", 4, 0], ["armor_heavy", 7, 0],
	["bandage", 0, 2, 3], ["rifle_ammo", 1, 2, 60], ["shells", 2, 2, 12], ["grenade", 3, 2, 2],
	["sniper", 0, 3], ["energy_drink", 5, 3], ["gold_watch", 6, 3], ["bon_tag", 7, 3], ["cash", 8, 3], ["crystal", 9, 3],
	["helmet_good", 0, 4], ["holy_grail", 2, 4], ["medkit", 4, 4], ["gpu", 4, 5], ["fuel_can", 6, 4], ["scope_4x", 8, 4],
	["phone", 8, 5], ["beans", 9, 5], ["water", 0, 6], ["duct_tape", 1, 6], ["gold_bar", 2, 6], ["red_dot", 3, 6],
	["cpu", 4, 6], ["diamond_ring", 5, 6], ["intel_exion", 6, 6], ["mil_chip", 7, 6], ["dog_tag", 8, 6], ["gunpowder", 9, 6],
]
const W := 10
const H := 7


func _initialize() -> void:
	var dirs := [""]
	var names := ["Current icons"]
	var out := "/tmp/icon_sheet.png"
	var zoom := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("dirs="): dirs = Array(a.substr(5).split(","))
		if a.begins_with("names="): names = Array(a.substr(6).split(","))
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("zoom="): zoom = float(a.substr(5))
	var cell := GridView.CELL
	var panel := Vector2(W * cell, H * cell + 30)
	var vp := SubViewport.new()
	vp.size = Vector2i(Vector2((panel.x + 20) * dirs.size() + 20, panel.y + 40) * zoom)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var canvas := Control.new()
	canvas.scale = Vector2(zoom, zoom)
	vp.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("23272b")
	bg.size = Vector2(vp.size) / zoom
	canvas.add_child(bg)
	for i in dirs.size():
		ItemIcons._cache.clear()
		if dirs[i] != "":
			for entry in LAYOUT:
				var img := Image.load_from_file(String(dirs[i]).path_join(entry[0] + ".png"))
				ItemIcons._cache[entry[0]] = ImageTexture.create_from_image(img)
		var origin := Vector2(20 + i * (panel.x + 20), 20)
		var title := Label.new()
		HudStyle.style_label(title, 20)
		title.text = names[i]
		title.position = origin
		canvas.add_child(title)
		var cells := ColorRect.new()
		cells.color = GridView.BG_COLOR
		cells.position = origin + Vector2(0, 30)
		cells.size = Vector2(W, H) * cell
		canvas.add_child(cells)
		for x in W + 1:
			var line := ColorRect.new()
			line.color = Color(1, 1, 1, 0.06)
			line.position = cells.position + Vector2(x * cell, 0)
			line.size = Vector2(1, H * cell)
			canvas.add_child(line)
		for y in H + 1:
			var line := ColorRect.new()
			line.color = Color(1, 1, 1, 0.06)
			line.position = cells.position + Vector2(0, y * cell)
			line.size = Vector2(W * cell, 1)
			canvas.add_child(line)
		for entry in LAYOUT:
			var stack := ItemStack.new(entry[0], entry[3] if entry.size() > 3 else 1, entry[1], entry[2])
			var tile := ItemTile.new(stack, null, null, true)
			tile.position = cells.position + Vector2(entry[1], entry[2]) * cell
			canvas.add_child(tile)
	for k in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	quit()
