extends SceneTree
## Economy numbers (0.16.0, Economy update): rolls the real map's containers and the AI's body loot thousands of
## times with the game's own loot code, and prints what things are worth when sold, next to what kits cost.
## Run from the repo root: godot --headless -s tools/economy_sim.gd [-- runs=2000]
## Sell value uses the trader's real prices (Traders.sell_price), so re-run it after any price change, and after
## the map overhaul (owner, 2026-10-12: loot spots will move and their number will change), then re-tune prices.

const MAP := "res://scenes/maps/old_bloxov.tscn"
const BODIES := {"Scav": "res://scenes/scav.tscn", "Sniper": "res://scenes/sniper.tscn",
	"Raider": "res://scenes/raider.tscn", "Bon": "res://scenes/boss.tscn"}
const CONTAINER_SCENES := {"3_crate": "res://scenes/loot_crate.tscn", "4_locker": "res://scenes/loot_locker.tscn",
	"5_safe": "res://scenes/loot_safe.tscn"}
## Kits: [name, [[item id, count], ...]]
const KITS := [
	["Starter (Stinger)", [["pistol", 1], ["pistol_ammo", 50], ["bandage", 2]]],
	["Wasp kit", [["smg", 1], ["smg_ammo", 90], ["bandage", 2], ["backpack_small", 1]]],
	["Hound kit", [["ak", 1], ["rifle_ammo", 120], ["armor_light", 1], ["helmet_basic", 1], ["backpack_medium", 1], ["bandage", 2], ["medkit", 1]]],
	["Lancer kit", [["sniper", 1], ["sniper_ammo", 20], ["scope_8x", 1], ["armor_light", 1], ["helmet_basic", 1], ["backpack_medium", 1], ["medkit", 1], ["bandage", 2]]],
	["Kitted Hound", [["ak", 1], ["rifle_ammo", 120], ["red_dot", 1], ["foregrip", 1], ["suppressor", 1], ["ext_mag", 1], ["armor_light", 1], ["helmet_basic", 1], ["backpack_medium", 1], ["medkit", 2], ["grenade", 2]]],
]

var runs := 2000


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.trim_prefix("runs="))
	var containers := _map_containers()
	print("Economy sim: %d runs per container, %d containers on the map" % [runs, containers.size()])
	print("Sell values at today's trader prices.\n")

	# Average sell value of each container, grouped by place.
	var by_place := {}
	var place_counts := {}
	var open_total := 0.0
	var open_count := 0
	for c: Dictionary in containers:
		var avg := _avg_container(c)
		c["avg"] = avg
		var key: String = c["place"] if c["place"] != "" else "(no place)"
		by_place[key] = by_place.get(key, 0.0) + avg
		place_counts[key] = place_counts.get(key, 0) + 1
		if not c["locked"]:
			open_total += avg
			open_count += 1
	print("== Per container type (unlocked, all places) ==")
	for kind in ["crate", "locker", "safe"]:
		var total := 0.0
		var count := 0
		for c: Dictionary in containers:
			if c["table"] == kind and not c["locked"]:
				total += c["avg"]
				count += 1
		if count > 0:
			print("  %-8s x%-3d avg %s" % [kind, count, ItemDB.money(roundi(total / count))])
	print("\n== By place (sum of its containers per raid) ==")
	var places := by_place.keys()
	places.sort_custom(func(a, b): return by_place[a] > by_place[b])
	for p in places:
		print("  %-16s %2d containers  %s" % [p, place_counts[p], ItemDB.money(roundi(by_place[p]))])
	print("\n== Bodies (avg per kill) ==")
	var body_avg: Dictionary = {}
	for b in BODIES:
		body_avg[b] = _avg_body(BODIES[b])
		print("  %-8s %s" % [b, ItemDB.money(roundi(body_avg[b]))])
	var per_open := open_total / maxi(open_count, 1)
	print("\n== Raids (rough) ==")
	var quick: float = per_open * 8 + body_avg["Scav"] * 2
	var loop: float = per_open * 20 + body_avg["Scav"] * 4 + body_avg["Raider"]
	var everything := open_total
	print("  Quick raid (8 containers, 2 scavs):          %s" % ItemDB.money(roundi(quick)))
	print("  Town loop (20 containers, 4 scavs, 1 Raider): %s" % ItemDB.money(roundi(loop)))
	print("  Vault run (Bank place incl. vault safes):     %s" % ItemDB.money(roundi(by_place.get("Bank", 0.0))))
	print("  Bunker run (Bunker place, + Bon kill):        %s" % ItemDB.money(roundi(by_place.get("Bunker", 0.0) + body_avg["Bon"])))
	print("  Every unlocked container on the map:          %s" % ItemDB.money(roundi(everything)))
	print("  (You carry out what fits: a medium backpack + pockets holds a fraction of a full loop.)")
	print("\n== Kits (buy price today) ==")
	for kit: Array in KITS:
		var cost := 0
		var missing: Array[String] = []
		for entry: Array in kit[1]:
			cost += Traders.buy_price(entry[0], entry[1])
			if Traders.trader_for(entry[0]) == "":
				missing.append(ItemDB.display_name(entry[0]))
		var note := "" if missing.is_empty() else "  (loot-only: %s)" % ", ".join(missing)
		print("  %-18s %8s  = %.1f quick raids, %.1f town loops%s" % [kit[0], ItemDB.money(cost), cost / quick, cost / loop, note])
	print("\n== Ming's boxes (average sell value of what comes out) ==")
	for box: String in Traders.BOXES:
		var total := 0
		var shop := 0
		for i in runs * 5:
			var id := Traders.open_box(box)
			total += Traders.sell_price(ItemStack.new(id))
			shop += Traders.buy_price(id, 1)
		var price: int = Traders.BOXES[box]["price"]
		var avg := float(total) / (runs * 5)
		print("  %-10s %8s  sells for %s (%d%%), costs %s at a trader" % [Traders.BOXES[box]["name"], ItemDB.money(price),
			ItemDB.money(roundi(avg)), roundi(100.0 * avg / price), ItemDB.money(roundi(float(shop) / (runs * 5)))])
	quit()


## [{name, table, place, locked, scene}] for every loot container in the real map (read from the .tscn text,
## so nothing on the map has to run).
func _map_containers() -> Array:
	var out := []
	var text := FileAccess.get_file_as_string(MAP)
	var current := {}
	for line in text.split("\n"):
		if line.begins_with("[node "):
			if not current.is_empty():
				out.append(current)
			current = {}
			for res in CONTAINER_SCENES:
				if line.contains('ExtResource("%s")' % res):
					var name := line.get_slice('name="', 1).get_slice('"', 0)
					current = {"name": name, "scene": CONTAINER_SCENES[res], "place": "", "locked": false,
						"table": res.get_slice("_", 1)}
		elif not current.is_empty():
			if line.begins_with("metadata/place"):
				current["place"] = line.get_slice('"', 1)
			elif line.begins_with("metadata/locked"):
				current["locked"] = line.contains("true")
	if not current.is_empty():
		out.append(current)
	return out


func _avg_container(c: Dictionary) -> float:
	var scene: PackedScene = load(c["scene"])
	var total := 0
	for i in runs:
		var box: LootContainer = scene.instantiate()
		box.name = c["name"]
		if c["place"] != "":
			box.set_meta("place", c["place"])
		box._ready()   # rolls the loot, exactly like a raid (outside the tree, so nothing else runs)
		for stack in box.grid.stacks:
			total += Traders.sell_price(stack)
		box.free()
	return float(total) / runs


## Body loot, the way ScavBase.die() builds it (the gun it carries, its worn gear, its table rolls).
func _avg_body(path: String) -> float:
	var ai: Node = (load(path) as PackedScene).instantiate()
	var total := 0
	for i in runs:
		var gun: String = ai.weapon_drop if ai.weapon_drop != "" else AILoadouts.pick(ai.loadout)
		if gun != "" and randf() < ai.weapon_drop_chance:
			total += Traders.sell_price(AILoadouts.dropped_gun(gun, ai.drop_parts, ai.drop_part_chance))
		for id in ai.extra_drops:
			total += Traders.sell_price(ItemStack.new(id))
		for id in ItemDB.TABLE_CHANCES.get(ai.loot_table, {}):
			if randf() < ItemDB.TABLE_CHANCES[ai.loot_table][id]:
				total += Traders.sell_price(ItemStack.new(id))
		for gear in [ai.armor, ai.helmet]:
			if gear != "":
				total += Traders.sell_price(ItemStack.new(gear))
		for j in randi_range(ai.min_drops, ai.max_drops):
			var id := ItemDB.roll(ai.loot_table)
			var stack := ItemStack.new(id)
			stack.count = ItemDB.roll_count(id)
			total += Traders.sell_price(stack)
	ai.free()
	return float(total) / runs
