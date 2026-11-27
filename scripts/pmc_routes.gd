class_name PmcRoutes
extends RefCounted
## AI PMC routes (0.39.29, owner 2026-11-23: "having a bunch of paths then randomizing between them"): per map, a few
## hand-drawn ways from a spawn area through 2-3 loot places to an extract, kept to the map's edges and cover and
## clear of the scav camps' middles, the snipers' perches and the boss's area. A bot takes one that starts near where
## it spawned, at random (PmcAI). Each point is [x, z] (a turn on the way) or [x, z, "Place"] (loot there: the
## PmcAI place of that name nearest the point). "extract" is the extract's node name. The map's height is looked up.

const ROUTES := {
	"Bloxov Frontlines": [
		{"name": "West edge", "points": [[-161, 15], [-165, 40, "Waterfall"], [-160, 0], [-149, -43, "Shops"], [-150, -80],
			[-155, -112, "School"]], "extract": "TownRoad"},
		{"name": "Big houses", "points": [[-161, -161], [-136, -147, "BigHouse1"], [-118, -150], [-99, -133, "BigHouse2"],
			[-80, -150], [-64, -136, "BigHouse3"]], "extract": "MillLane"},
		{"name": "School run", "points": [[-161, -161], [-160, -130], [-155, -112, "School"], [-149, -43, "Shops"]],
			"extract": "TownRoad"},
		{"name": "Church", "points": [[29, -157], [24, -128, "Crypt"], [5, -155], [-8, -146, "Church"], [-15, -125],
			[-36, -108, "Grocery"], [-45, -140]], "extract": "MillLane"},
		{"name": "Motel", "points": [[29, -157], [41, -147, "Motel"], [41, -131, "Motel"], [76, -108, "Shed"]],
			"extract": "FarmRoad"},
		{"name": "Farm", "points": [[161, -161], [144, -143, "Farmhouse"], [120, -160], [93, -139, "Barn"], [41, -147, "Motel"]],
			"extract": "FarmRoad"},
		{"name": "East edge", "points": [[169, 5], [140, -5, "Cabin3"], [160, 40], [147, 67, "OldHouse3"], [160, 90],
			[153, 104, "Junkyard"], [132, 90, "JunkOffice"]], "extract": "Highway"},
		{"name": "Depot", "points": [[169, 5], [140, -5, "Cabin3"], [120, 40], [103, 66, "Depot"], [87, 111, "Checkpoint"],
			[120, 110]], "extract": "Highway"},
		{"name": "Diner", "points": [[95, 167], [116, 151, "Diner"], [124, 152, "GasStation"], [150, 156, "GasStation"],
			[170, 158, "Garage"]], "extract": "Highway"},
		{"name": "Old houses", "points": [[-7, 93], [27, 94, "OldHouse1"], [10, 110], [-10, 107, "OldHouse6"],
			[-21, 142, "OldHouse7"], [40, 149, "OldHouse8"]], "extract": "SouthRoad"},
		{"name": "Woods", "points": [[-105, 169], [-77, 121, "Cabin1"], [-109, 88, "Campsite"], [-135, 135, "Cabin2"],
			[-133, 149, "Field"]], "extract": "CreekTrail"},
		{"name": "Creek", "points": [[-105, 169], [-135, 135, "Cabin2"], [-150, 100], [-165, 40, "Waterfall"], [-160, 120]],
			"extract": "CreekTrail"},
	],
}


## Tests: routes to use on every map instead (empty = the real ones).
static var test_routes: Array = []


## The routes for the map named `map_name` (its `map_name` meta; none = the bot plans as before).
static func for_map(map_name: String) -> Array:
	return test_routes if not test_routes.is_empty() else ROUTES.get(map_name, [])
