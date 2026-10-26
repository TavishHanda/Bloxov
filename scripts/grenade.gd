class_name Grenade
extends Node3D
## A thrown frag grenade (0.14.5): flies, bounces off the world, and goes off when its fuse runs out.
## The blast hurts everyone in `radius` it has a clear line to (players, you included, and AI), through their armor,
## most in the middle; AI hear it from far away.
## Online the server's copy does the damage (in its RaidWorld, hits on players go to their games like any other);
## the copies on players' screens only show it (`deals_damage` false). Plain motion with rays, not a physics body,
## so every copy flies the same way.

const EXPLOSION_SOUND := preload("res://audio/explosion.wav")
const GRAVITY := 18.0
const BOUNCE := 0.35

## Seconds from the throw to the blast.
@export var fuse := 3.0
## Full damage within `core` meters, falling evenly to 0 at `radius` (0.14.18, owner: 80 on a direct hit).
@export var damage := 80
@export var core := 0.0
@export var radius := 7.0
## AI within this many meters hear the blast.
@export var noise_radius := 60.0

## The nearest AI within radius x WARN_REACH shouts a warning this long before the blast (Sound update 0.20.4: a
## sound only, they don't do anything different).
const WARN_AT := 1.6
const WARN_REACH := 1.6

var velocity := Vector3.ZERO
var deals_damage := true
var exploded := false
var _resting := false


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.16, 0.12)
	box.material = Effects.unshaded(Color(0.25, 0.32, 0.18))
	mesh.mesh = box
	add_child(mesh)


## Throws a grenade into `world` from `from` at `vel`.
static func spawn(world: Node, from: Vector3, vel: Vector3, real := true) -> Grenade:
	var grenade := Grenade.new()
	grenade.velocity = vel
	grenade.deals_damage = real
	world.add_child(grenade)
	grenade.global_position = from
	return grenade


func _physics_process(delta: float) -> void:
	if exploded:
		return
	fuse -= delta
	if fuse <= 0.0:
		explode()
		return
	if deals_damage and fuse <= WARN_AT and fuse + delta > WARN_AT:
		_warn()
	if _resting:
		return
	velocity.y -= GRAVITY * delta
	var step := velocity * delta
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1))
	if hit.is_empty():
		global_position += step
		rotate_x(delta * 9.0)
		return
	var normal: Vector3 = hit.normal
	global_position = (hit.position as Vector3) + normal * 0.08
	velocity = velocity.bounce(normal) * BOUNCE
	if normal.y > 0.7 and velocity.length() < 1.2:
		velocity = Vector3.ZERO
		_resting = true


func explode() -> void:
	if exploded:
		return
	exploded = true
	var world := get_parent()
	var at := global_position
	Effects.burst(world, at + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.2))
	Effects.burst(world, at + Vector3(0, 0.5, 0), Color(0.35, 0.33, 0.3))
	Effects.sound_at(world, EXPLOSION_SOUND, at, 6.0, 0.05, 1.0, 14.0, 150.0)
	Reacts.blast(world, at, radius)   # (0.22.0: lamps swing, cans fly; looks only)
	for node in RaidScope.nodes(self, &"player"):
		# A shake for anyone close (only the local player's camera has one that shows).
		if node.has_method("add_shake") and (node as Node3D).global_position.distance_to(at) < radius * 2.0:
			node.add_shake(clampf(1.0 - (node as Node3D).global_position.distance_to(at) / (radius * 2.0), 0.0, 1.0) * 0.8)
	if deals_damage:
		_hurt_around(at)
		RaidScope.call_all(self, &"enemies", &"hear_noise", [at, noise_radius])
	queue_free()


func _warn() -> void:
	var nearest: Node3D = null
	var best := radius * WARN_REACH
	for node in RaidScope.nodes(self, &"enemies"):
		var d := (node as Node3D).global_position.distance_to(global_position)
		if d < best and node.has_method(&"_chatter") and not (node.get(&"health") as Health).is_dead:
			best = d
			nearest = node
	if nearest != null:
		nearest.call(&"_chatter", "grenade")


## Damage for something `distance` meters from the blast.
func damage_at(distance: float) -> int:
	if distance >= radius:
		return 0
	return roundi(damage * clampf((radius - distance) / (radius - core), 0.0, 1.0))


func _hurt_around(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var targets: Array[Node] = RaidScope.nodes(self, &"player") + RaidScope.nodes(self, &"enemies")
	for node in targets:
		var target := node as Node3D
		var health := Health.of(target)
		if target == null or health == null or health.is_dead:
			continue
		var middle := target.global_position + Vector3(0, 0.9, 0)
		var amount := damage_at(middle.distance_to(at))
		if amount <= 0:
			continue
		# Walls (and floors) between it and the blast stop it.
		var from := at + Vector3(0, 0.3, 0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, middle, 1)).is_empty():
			continue
		health.take_damage(amount, at)
