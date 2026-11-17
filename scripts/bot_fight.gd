class_name BotFight
extends RefCounted
## How many scavs, Raiders, snipers or Bon one fight with an AI PMC pulls in from elsewhere (0.36.13, owner: "a bot's
## shots pull 1 scav, not 4"; with 4, as for a real player, bots were swarmed and dead inside two minutes).
## Like FightBudget, with its own ledger per raid: each fight (noises and calls within RADIUS of it) hands out at most
## BUDGET tickets to AI coming over because they heard an AI PMC shoot, were called by an AI fighting one, or saw a
## buddy dropped by one. AI with no ticket carry on as if nothing happened. The fight is forgotten once it has been
## quiet for QUIET_RESET seconds. Real players' fights don't use this: FightBudget, unchanged.

const BUDGET := 1
const QUIET_RESET := 45.0
const RADIUS := 50.0
const _META := &"bot_fight_budget"


## Asks for one AI to come over to the AI PMC's fight at `pos`: true (and counted) if that fight still has room.
static func take(node: Node, pos: Vector3) -> bool:
	var viewport := node.get_viewport()
	var now := float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	var fights: Array = (viewport.get_meta(_META, []) as Array).filter(
		func(f: Dictionary) -> bool: return now - float(f["last"]) < QUIET_RESET)
	var best := {}
	var best_d := RADIUS
	for f: Dictionary in fights:
		var d := (f["pos"] as Vector3).distance_to(pos)
		if d <= best_d:
			best = f
			best_d = d
	if best.is_empty():
		best = {"pos": pos, "used": 0, "last": now}
		fights.append(best)
	best["last"] = now
	viewport.set_meta(_META, fights)
	if int(best["used"]) >= BUDGET:
		return false
	best["used"] = int(best["used"]) + 1
	return true


## Forgets every AI PMC fight in `node`'s raid (tests).
static func reset(node: Node) -> void:
	node.get_viewport().set_meta(_META, [])
