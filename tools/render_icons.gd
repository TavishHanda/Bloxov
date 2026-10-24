extends SceneTree
## Renders the inventory icons: one PNG per item, its grid size x ItemIcons.PX pixels, transparent background
## (tools/item_models.gd has the models). Re-run after adding an item or changing a model:
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/render_icons.gd
## Options: ids=ak,bandage (only those)  look=a|b|c (the option looks, for sheets)  out=<dir> (default assets/icons/items)
const Models := preload("res://tools/item_models.gd")

## The looks shown to the owner. view: camera yaw/pitch in degrees. outline: px of dark edge. key/fill: light energies.
const LOOKS := {
	"a": {"yaw": 0.0, "pitch": 0.0, "outline": 0, "key": 1.1, "fill": 0.55, "ambient": 0.55},
	"b": {"yaw": -28.0, "pitch": -22.0, "outline": 0, "key": 1.5, "fill": 0.3, "ambient": 0.4},
	"c": {"yaw": -14.0, "pitch": -10.0, "outline": 2, "key": 1.2, "fill": 0.5, "ambient": 0.65},
}
const PICKED := "c"
const SUPERSAMPLE := 3
const MARGIN := 0.12   # of the tile, on each side


func _initialize() -> void:
	var look: String = PICKED
	var out := "res://assets/icons/items"
	var ids: Array = ItemDB.ITEMS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("look="): look = a.substr(5)
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("ids="): ids = Array(a.substr(4).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var cfg: Dictionary = LOOKS[look]

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = cfg["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_energy = cfg["key"]
	key.light_color = Color(1.0, 0.97, 0.9)
	key.rotation_degrees = Vector3(-50, -40, 0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = cfg["fill"]
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.rotation_degrees = Vector3(-10, 140, 0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.01
	cam.far = 20.0
	vp.add_child(cam)
	cam.current = true

	await process_frame   # (the tree isn't running yet in _initialize)
	for id in ids:
		var model: Node3D = Models.build(id)
		if model == null:
			push_warning("no model for " + id)
			continue
		var holder := Node3D.new()
		holder.rotation_degrees = Vector3(-cfg["pitch"], cfg["yaw"], 0)
		holder.add_child(model)
		vp.add_child(holder)
		var cells := Vector2(ItemDB.item(id)["w"], ItemDB.item(id)["h"])
		var px := cells * ItemIcons.PX
		vp.size = Vector2i(px * SUPERSAMPLE)
		# Fit the model to the tile (minus the margin), looking from +z.
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mi as MeshInstance3D
			var box := mesh_instance.get_aabb()
			var xf := mesh_instance.global_transform
			for i in 8:
				var p := xf * box.get_endpoint(i)
				lo = lo.min(p)
				hi = hi.max(p)
		var centre := (lo + hi) * 0.5
		var extent := hi - lo
		var room := px - Vector2.ONE * ItemIcons.PX * MARGIN * 2.0   # the same margin all round, whatever the size
		var scale := minf(room.x / extent.x, room.y / extent.y)   # px per metre
		cam.size = px.y / scale
		cam.position = Vector3(centre.x, centre.y, hi.z + 2.0)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(int(px.x), int(px.y), Image.INTERPOLATE_LANCZOS)
		if cfg["outline"] > 0:
			img = _outline(img, cfg["outline"])
		img.save_png(ProjectSettings.globalize_path(out.path_join(id + ".png")))
		holder.queue_free()
	quit()


## A dark edge `width` px wide round everything drawn, so icons stand out on any tile colour.
static func _outline(img: Image, width: int) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var edge := Color(0.05, 0.05, 0.06, 0.9)
	for y in img.get_height():
		for x in img.get_width():
			var a := 0.0
			for dy in range(-width, width + 1):
				for dx in range(-width, width + 1):
					if dx * dx + dy * dy > width * width + 1:
						continue
					var sx := x + dx
					var sy := y + dy
					if sx >= 0 and sy >= 0 and sx < img.get_width() and sy < img.get_height():
						a = maxf(a, img.get_pixel(sx, sy).a)
			out.set_pixel(x, y, Color(edge, edge.a * a))
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	return out
