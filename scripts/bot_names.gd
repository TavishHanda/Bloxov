class_name BotNames
extends RefCounted
## AI PMC names (0.36.2, piece 3 of the owner's AI PMC plan): made-up player-style names, written for the game (no
## real person, streamer or brand). The server gives each bot in a raid one of these, never one a real player in that
## raid is using, and sign-up refuses them as usernames so no account ever shares one. Every name passes NameFilter
## (the smoke test checks the whole list). Only add to or take from the list with the owner's OK.

const LIST: PackedStringArray = [
	"Koda_77", "mud wizard", "Brisket", "SoggyToast", "tinman_42", "Gravelpit", "pickle.jar", "NoScopeNana",
	"Lumberjack88", "frostbyte_9", "BigMoose", "owl at night", "Tater_Tot", "RustyNail", "quietfox", "BeanCounter",
	"HexaGone", "Wobbles", "sir_crumbs", "Muddy_Boots", "PotatoAim", "lowbattery", "Captain_Socks", "Driftwood",
	"jellyroll", "Ironpants", "Moss_Bandit", "cold_coffee", "PineconeKing", "Grumbo", "TurboSnail", "Barnaby_B",
	"slowpoke_99", "CrateDigger", "nightowl_7", "Waffles", "Gunk", "RedKettle", "the_janitor", "Mapleleaf_22",
	"Sprocket", "doorknob", "Hamhock", "Velvet_Moth", "SnackPack", "BlueBucket", "GoblinMode", "spudnik",
	"Rookie_Rick", "ThunderMitt", "Lefty_Loosey", "Paperclip", "quokka_qt", "ChunkyBear", "Tumbleweed", "Sideburns",
	"fern_and_moss", "Scrapper", "MossyRock", "BorealBoy", "coyote_sly", "Nugget", "Shovelhead", "LooseGoose",
	"PebbleDash", "grizzly_gus", "Kettlecorn", "BackpackBob", "Hushbird", "Mr Mittens", "Static_Fizz", "OatmealOps",
	"Nebula_Ned", "wet_socks", "Brickhouse", "Lantern_Jaw", "tin_can_tom", "Crowbar_Carl", "SaltyPretzel", "Hobble",
	"SnowPlow", "Dingus", "TrailMix", "Meatball_Mo", "SocketWrench", "Gopher_Gary", "Ditchdigger", "pond_scum",
	"BoomBucket", "Clover_44", "Sleepy_Sam", "Caribou", "WolfPup", "Buckshot_Bev", "Haystack", "Fuzzy_Dice",
	"marmot_man", "Toolbox", "OldSalt", "PuddleJumper", "Snorkel", "Badger_Bri", "Cinderblock", "Tripod_Dog",
	"Yeti_Spaghetti", "cornbread", "Gearhead_G", "Hollow_Point", "FlannelDan", "sneaky_lou", "Mothball", "Tundra_Tim",
	"Muskrat_77", "RubberDuck", "GhostPepper", "Sawdust", "Roadie_Ray", "Biscuit", "Hedgehog_H", "IcePick",
	"drum_roll", "Swampy", "FoxtrotFive", "Bravo_Two", "Kilo_Nine", "Zulu_Pan", "TangoMango", "Sierra_Dusk",
	"Echo_Lima", "NovemberFog", "BaconBits", "gravy_train", "Lumpy", "Skillet", "Pinwheel", "Whiskers",
	"Crumpet", "TinFoilHat", "Bricklayer", "Banjo_Bill", "MoonBeam_M", "TrashPanda", "Crabcake", "Noodle_Arms",
	"Sunburn", "FlatTire", "Rumble_Ron", "Puddles", "shy_turtle", "Last_One_Out", "Pocketlint", "SgtSprinkles",
]


## True if `text` is one of the bot names (any case): sign-up refuses these as usernames.
static func is_bot_name(text: String) -> bool:
	var lower := text.strip_edges().to_lower()
	for bot_name in LIST:
		if bot_name.to_lower() == lower:
			return true
	return false


## `count` different names for one raid's bots, picked by the raid's seed, skipping any in `taken` (the real players'
## names in that raid, any case). Every name goes through NameFilter.clean.
static func pick(count: int, seed_value: int, taken: Array = []) -> PackedStringArray:
	var used := {}
	for name_taken: Variant in taken:
		used[String(name_taken).to_lower()] = true
	var order := range(LIST.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	var out: PackedStringArray = []
	for index: int in order:
		if out.size() >= count:
			break
		var bot_name := NameFilter.clean(LIST[index], "")
		if bot_name == "" or used.has(bot_name.to_lower()):
			continue
		used[bot_name.to_lower()] = true
		out.append(bot_name)
	return out
