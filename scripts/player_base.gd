extends CharacterBody3D
## The player's settings and shared state, plus questions other scripts ask about it (healing? sprinting? where are
## its eyes?). The player is one object built from a chain of scripts (split up in 0.14.6, no behaviour change):
## player_base.gd -> player_movement.gd (stance, ladders, vaulting, lean, stamina, footsteps, camera motion) ->
## player.gd (class Player: input, the per-frame update, items and the hotbar, damage, online).

@export_group("Movement")
## Meters per second. For reference, a real jog is ~3, a run ~5.
@export var walk_speed := 3.4
## Sprint only works moving forward, and lowers your gun.
@export var sprint_speed := 5.6
## Speed multipliers when walking backwards / sideways.
@export var backward_multiplier := 0.7
@export var strafe_multiplier := 0.85
## How fast you speed up and slow down on the ground (m/s per second). Lower = heavier.
@export var ground_acceleration := 16.0
@export var ground_deceleration := 20.0
## How much you can steer in the air (m/s per second). Low = jumps commit you.
@export var air_control := 2.5
## About 0.6 m high.
@export var jump_velocity := 3.6
@export var jump_cooldown := 0.45
## Landing from a jump or fall slows you briefly.
@export var landing_slowdown_time := 0.3
## Fall damage (0.13.3): drops up to this high (meters) are free; past it, `fall_damage_per_meter` each extra meter.
## About: a one-storey roof (2.75 m) is free, a two-storey roof (5.5 m) costs ~24, 12 m kills. Armor doesn't help.
@export var safe_fall_height := 3.5
@export var fall_damage_per_meter := 12.0
@export var landing_slowdown := 0.5
## Speed multiplier while fully aimed down sights.
@export var ads_move_multiplier := 0.7

@export_group("Vault")
## Space while moving into low cover vaults over it or climbs onto it (0.13.0; heights etc. in `Vault`).
## Up to this (chest high), you climb onto ledges and wide tops.
@export var mantle_max_height := Vault.MANTLE_HEIGHT
## How far in front of you (past your body) cover counts.
@export var vault_reach := 0.7
## Seconds to vault over / climb onto something.
@export var vault_time := 0.45
@export var mantle_time := 0.7
@export var vault_noise := 12.0

@export_group("Ladders")
## Meters per second up or down a ladder (0.13.5).
@export var climb_speed := 2.2

@export_group("Prone")
## Z (0.13.6): lie down. Slow crawl, very quiet, hard to hit, steadiest aim. Z or Space gets you up, C to a crouch.
@export var prone_speed := 1.0
@export var prone_height := 0.8
@export var prone_eye_height := 0.4

@export_group("Crouch")
## C toggles crouch. Slower, quieter, smaller, steadier aim.
@export var crouch_speed := 2.2
## Wading through water (the creek, 0.11.20; owner): this fraction of the speed, and no sprinting.
@export var wade_multiplier := 0.6
@export var stand_height := 1.8
@export var crouch_height := 1.2
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 1.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Per second while sprinting. 100 / 12 = about 8 seconds of sprint.
@export var sprint_drain := 12.0
@export var jump_cost := 12.0
@export var stamina_regen := 16.0
## Seconds after sprinting/jumping before stamina starts coming back.
@export var stamina_regen_delay := 1.0
## Run out completely and you can't sprint again until stamina is back to this.
@export var exhausted_recover_at := 25.0

@export_group("Footsteps")
## Meters between footsteps.
@export var walk_stride := 1.5
@export var sprint_stride := 1.9
@export var crouch_stride := 1.1
## How far away enemies hear each step (meters). 0 = silent. (0.12.30, owner: AI didn't hear him walking right past
## them: walk 7, sprint 15, crouch silent before. Crouching is still nearly silent: only right next to them.)
@export var walk_noise := 12.0
@export var sprint_noise := 25.0
@export var crouch_noise := 2.0
@export var landing_noise := 10.0

@export_group("Lean")
## Q/E: the head shifts sideways and tilts to peek around corners. Can't sprint while leaning; walk slower.
## The body (hitbox) stays put, so peeking only exposes what the camera can see past.
@export var lean_distance := 0.35
@export var lean_angle_deg := 12.0
@export var lean_speed := 8.0
@export var lean_move_multiplier := 0.6

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var base_fov := 80.0
## Extra field of view while sprinting, for a sense of speed.
@export var sprint_fov_boost := 6.0
## Head bob strength (meters) when walking / sprinting.
@export var walk_bob := 0.03
@export var sprint_bob := 0.055
## Camera lean when strafing (degrees).
@export var strafe_tilt := 1.5

@export_group("Recoil")
## How quickly the quick visual kick (and flinch from getting shot) settles.
@export var recoil_recovery := 9.0
## After you stop firing, the recoil you didn't pull down against returns at this rate (per second, smoothed).
@export var recoil_return_speed := 7.0
## Seconds after the last shot before recoil starts returning.
@export var recoil_return_delay := 0.12
## Getting shot kicks your aim this far (degrees, at 25 damage; scales with damage).
@export var flinch_deg := 2.2

@export_group("Downed")
## In a squad, 0 HP knocks you down instead of killing you (owner, 0.9.2): you crawl at this fraction of walk speed
## and can't shoot, heal, loot or extract until a teammate revives you (back up at `revive_health`).
@export var crawl_multiplier := 0.25
@export var downed_eye_height := 0.45
@export var revive_health := 30

@export_group("Other")
## Mouse movements bigger than this (in pixels, in one event) are treated as glitches and ignored.
## Works around a Chrome bug where captured-mouse input sometimes reports a huge bogus jump.
@export var max_mouse_delta := 200.0
## Falling below this height respawns the player.
@export var kill_height := -20.0

@onready var head: Node3D = $Head
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var recoil: Node3D = $Head/Recoil
@onready var camera: Camera3D = $Head/Recoil/Camera3D
@onready var gun: Gun = $Head/Recoil/Camera3D/Gun
@onready var knife: Knife = $Head/Recoil/Camera3D/Knife
@onready var health: Health = $Health
@onready var inventory: Inventory = $Inventory
@onready var interactor: Interactor = $Interactor

var is_dead := false
## True once the player has extracted (raid over, controls off).
var extracted := false
## Knocked down at 0 HP with a teammate around (see Health). On a proxy, from the player's state flags.
var downed := false

## Seconds left on the current heal, and the item being used.
var heal_time_left := 0.0
var _heal_item := ""
var _sprinting := false
## -1 = fully leaning left, 1 = right (smoothed). _lean_toggled is the held direction in tap-to-toggle mode.
var lean := 0.0
## While vaulting: the path (start, over the top, end), time into it and how long it takes; empty = not vaulting.
var _vault_path := PackedVector3Array()
var _climbing: Ladder = null


func controls_locked() -> bool:
	return is_dead or extracted


## Dead, out, or downed: scavs leave you alone (owner, 0.9.2) and you can't extract.
func out_of_fight() -> bool:
	return controls_locked() or downed


## Free to shoot, swing, heal or loot: not dead/out, downed, healing or reviving someone.
func hands_free() -> bool:
	return (not out_of_fight() and not is_healing() and not interactor.is_reviving() and not is_vaulting()
		and not is_climbing())


## Online: is a teammate up (alive, not downed, still in the raid) who could revive us?
func teammate_can_revive() -> bool:
	if not Network.main.in_online_raid():
		return false
	for peer in Network.main.teammates:
		var state: Array = Network.main.states.get(peer, [])
		if not state.is_empty() and int(state[4]) & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED | Hitbox.FLAG_DOWNED) == 0:
			return true
	return false


func is_healing() -> bool:
	return heal_time_left > 0.0


## Healing, but with an energy drink.
func is_drinking() -> bool:
	return is_healing() and ItemDB.kind(_heal_item) == "drink"


## True while actually sprinting (holding Shift, moving forward, on the ground).
func is_sprinting() -> bool:
	return _sprinting


## Height of the player's eyes / chest above their feet (lower when crouched). Used by enemies to aim.
func eye_height() -> float:
	return head.position.y


## Where the player's eyes actually are (includes leaning). Enemies check line of sight to this.
func eye_position() -> Vector3:
	return head.global_position


func chest_height() -> float:
	return (body_shape.shape as CapsuleShape3D).height * 0.65


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_climbing() -> bool:
	return _climbing != null


func is_vaulting() -> bool:
	return not _vault_path.is_empty()


func is_leaning() -> bool:
	return absf(lean) > 0.1


func _ceiling_blocked(height := stand_height) -> bool:
	var from := global_position + Vector3(0, 0.2, 0)
	var to := global_position + Vector3(0, height + 0.05, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
