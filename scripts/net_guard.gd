class_name NetGuard
extends RefCounted
## The server's anti-cheat bookkeeping (0.25.0, the security update). Pure logic, no nodes: `Network` asks it
## before acting on anything a player sends. Nothing here changes how the game plays for an honest player:
##   - Rate limits: every kind of request has a refilling allowance (well above what the game sends); requests
##     over it are dropped.
##   - Movement: how far a player may move between updates (a speed allowance that refills, with room for lag
##     spikes, falls, shoves and vaults) and whether they walked through a wall. A move that fails is not
##     taken: the server keeps the player where they were and tells their game to put them back.
##   - Strikes: each thing caught adds points that fade over time; a player who keeps cheating gets kicked
##     (owner's call: undo + log, kick on repeats). There are no bans yet: those need accounts (Stash update).
## Kept free of player/gun scripts (Network is an autoload, see net.gd's top).

## Kind -> [allowance refilled per second, most saved up]. The game sends states 20 times a second, a gun at most
## ~15 shots a second (each shot is checked against its gun's rate too), and the rest only on a key press.
const RATES := {
	"state": [40.0, 60.0],
	"shot": [25.0, 30.0],
	"knife": [6.0, 6.0],
	"loot": [20.0, 40.0],
	"world": [10.0, 20.0],
	"grenade": [2.0, 4.0],
	"drop": [6.0, 12.0],
	"revive": [6.0, 12.0],
	"lobby": [5.0, 15.0],
	"report": [80.0, 100.0],
	"kit": [1.0, 3.0],
	"use": [4.0, 8.0],
}

## Strike points: each fades at STRIKE_FADE a second; KICK_AT kicks.
const KICK_AT := 20.0
const STRIKE_FADE := 0.1
const STRIKES := {
	"flood": 0.25,      # a request over its rate limit
	"bad_data": 1.0,    # a request that couldn't come from the real game (malformed, made-up items)
	"speed": 2.0,       # moved further than they could have
	"teleport": 6.0,    # moved much further than they could have
	"wall": 3.0,        # walked through a wall
	"item": 3.0,        # used, fired or dropped something they don't carry
	"god": 4.0,         # stayed up with no health left
	"extract": 4.0,     # said they extracted away from an open extract
}

## Movement allowance: refills at MOVE_SPEED m/s up to MOVE_SLACK m (sprint is 5.6 m/s; the slack covers a
## lag spike of ~1.5 s, a shove, a vault). Upward the same with CLIMB_* (jumps, ladders, stairs, hills); falling
## is free. A move over TELEPORT m is a bigger strike.
const MOVE_SPEED := 8.0
const MOVE_SLACK := 12.0
const CLIMB_SPEED := 5.0
const CLIMB_SLACK := 6.0
const TELEPORT := 30.0
## After putting a player back, their game's moves sent before it heard are ignored (no strikes) until one
## arrives this close to where they were put.
const FIX_NEAR := 2.5
## A move back to where they spawned (this close to their first position) is always allowed.
const SPAWN_NEAR := 3.0

## Off in tests that move players around freely.
var check_moves := true
## Set by Network: called as log_func.call(text).
var log_func := Callable()

var _buckets := {}   # peer -> {kind: [left, time]}
var _strikes := {}   # peer -> [points, time]
var _moves := {}     # peer -> {pos, time, flat, up, fixing}


## True if `peer` may make one more request of `kind` now (else it's dropped, and counts a little toward a kick).
func allow(peer: int, kind: String, now: float) -> bool:
	var rate: Array = RATES.get(kind, [10.0, 20.0])
	var peer_buckets: Dictionary = _buckets.get_or_add(peer, {})
	var bucket: Array = peer_buckets.get(kind, [rate[1], now])
	var left := minf(float(bucket[0]) + (now - float(bucket[1])) * float(rate[0]), float(rate[1]))
	if left < 1.0:
		peer_buckets[kind] = [left, now]
		return false
	peer_buckets[kind] = [left - 1.0, now]
	return true


## Adds a strike to `peer` (a STRIKES kind) and logs it. True when they've now earned a kick.
func strike(peer: int, kind: String, detail: String, now: float) -> bool:
	var old: Array = _strikes.get(peer, [0.0, now])
	var points := maxf(float(old[0]) - (now - float(old[1])) * STRIKE_FADE, 0.0) + float(STRIKES.get(kind, 1.0))
	_strikes[peer] = [points, now]
	if kind != "flood" and log_func.is_valid():
		log_func.call("peer %d: %s (%s), %.1f strike points" % [peer, kind, detail, points])
	return points >= KICK_AT


## Current strike points (after fading).
func strike_points(peer: int, now: float) -> float:
	var old: Array = _strikes.get(peer, [0.0, now])
	return maxf(float(old[0]) - (now - float(old[1])) * STRIKE_FADE, 0.0)


## Checks a move to `pos`. Returns "" if it's fine (it becomes their position), else what was wrong ("speed",
## "teleport", "wall", or "fixing": still waiting for their game to take the last put-back) and they stay at
## position_of(peer). `blocked`: called as blocked.call(from, to) -> bool, true if a wall is in the way.
func check_move(peer: int, pos: Vector3, now: float, blocked := Callable()) -> String:
	var m: Dictionary = _moves.get(peer, {})
	if m.is_empty() or not check_moves:
		_moves[peer] = {"pos": pos, "time": now, "flat": MOVE_SLACK, "up": CLIMB_SLACK, "fixing": false,
			"spawn": pos if m.is_empty() else m["spawn"]}
		return ""
	# Fell out of the world: the game puts you back where you spawned (Player.kill_height). Always allowed.
	if pos.distance_to(m["spawn"]) < SPAWN_NEAR:
		m["pos"] = pos
		m["time"] = now
		m["fixing"] = false
		return ""
	var dt := clampf(now - float(m["time"]), 0.0, 2.0)
	m["time"] = now
	m["flat"] = minf(float(m["flat"]) + dt * MOVE_SPEED, MOVE_SLACK)
	m["up"] = minf(float(m["up"]) + dt * CLIMB_SPEED, CLIMB_SLACK)
	var from: Vector3 = m["pos"]
	if m["fixing"]:
		if pos.distance_to(from) > FIX_NEAR:
			return "fixing"
		m["fixing"] = false
	var step := pos - from
	var flat := Vector2(step.x, step.z).length()
	var up := maxf(step.y, 0.0)
	var problem := ""
	if flat > TELEPORT or up > TELEPORT:
		problem = "teleport"
	elif flat > float(m["flat"]) or up > float(m["up"]):
		problem = "speed"
	elif flat > 0.3 and blocked.is_valid() and blocked.call(from, pos):
		problem = "wall"
	if problem != "":
		m["fixing"] = true
		return problem
	m["flat"] = float(m["flat"]) - flat
	m["up"] = float(m["up"]) - up
	m["pos"] = pos
	return ""


## Where the server has `peer` (their last move that passed), or null if it hasn't seen one.
func position_of(peer: int) -> Variant:
	return _moves[peer]["pos"] if _moves.has(peer) else null


## Forgets a player's movement (a new raid starts them fresh wherever they spawn).
func reset_moves(peer: int) -> void:
	_moves.erase(peer)


func forget(peer: int) -> void:
	_buckets.erase(peer)
	_strikes.erase(peer)
	_moves.erase(peer)
