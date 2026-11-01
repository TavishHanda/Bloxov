class_name FightBudget
extends RefCounted
## How many AI one fight can pull in from elsewhere (0.28.11, owner: a friend fighting in a house by the church had
## scavs and raiders "flooding in all across town"; fights drawing others in is good, but it needs a limit).
## The old cap (Scav.max_responders) only counts AI while they walk over, so once they arrived and started fighting
## the next ones set off, and each arrival called for help again, chaining across town.
## Now each fight (a spot; noises and calls within RADIUS of it count as the same fight) hands out at most BUDGET
## tickets to AI coming over because they heard it, were called, or saw a buddy drop. With none left they go on
## alert where they are instead (Scav._hold_alert). The fight is forgotten, and its budget full again, once nothing
## loud happened near it for QUIET_RESET seconds. AI that see you fight you whatever the budget.
## One ledger per raid (kept on the raid's viewport: the server runs several raids at once).

const BUDGET := 6
const QUIET_RESET := 45.0
const RADIUS := 50.0
const _META := &"fight_budget"


## Asks for one AI to come over to the fight at `pos`: true (and counted) if the fight still has room.
static func take(node: Node, pos: Vector3) -> bool:
	var fight := _fight_at(node, pos, true)
	fight["last"] = _now()
	if int(fight["used"]) >= BUDGET:
		return false
	fight["used"] = int(fight["used"]) + 1
	return true


## Something loud happened at `pos` (a gunshot): a fight there isn't quiet yet.
static func stir(node: Node, pos: Vector3) -> void:
	var fight := _fight_at(node, pos, false)
	if not fight.is_empty():
		fight["last"] = _now()


## Tickets already handed out for the fight at `pos` (0 if there's none).
static func used(node: Node, pos: Vector3) -> int:
	return int(_fight_at(node, pos, false).get("used", 0))


## Forgets every fight in `node`'s raid (tests).
static func reset(node: Node) -> void:
	node.get_viewport().set_meta(_META, [])


static func _fight_at(node: Node, pos: Vector3, create: bool) -> Dictionary:
	var viewport := node.get_viewport()
	var fights: Array = viewport.get_meta(_META, [])
	var now := _now()
	fights = fights.filter(func(f: Dictionary) -> bool: return now - float(f["last"]) < QUIET_RESET)
	var best := {}
	var best_d := RADIUS
	for f: Dictionary in fights:
		var d := (f["pos"] as Vector3).distance_to(pos)
		if d <= best_d:
			best = f
			best_d = d
	if best.is_empty() and create:
		best = {"pos": pos, "used": 0, "last": now}
		fights.append(best)
	viewport.set_meta(_META, fights)
	return best


## Game time (physics frames), so headless tests at --fixed-fps agree with real play.
static func _now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
