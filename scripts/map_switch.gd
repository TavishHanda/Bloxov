class_name MapSwitch
extends StaticBody3D
## A switch on a map (Riptide's sub bay power, 0.33.3, owner): USE throws it, once a raid. It opens the extracts
## that wait on it (ExtractZone.needs_power == switch_id) and sounds an alarm: a klaxon over the switch and the
## extract, and every AI in earshot comes to look (owner: "sub bay + alarm yes").
## Solo for now (Riptide isn't online yet): online it will need the server to throw it for everyone.

## Which extracts it powers.
@export var switch_id := "power"
@export var prompt_text := "Turn on the power"
## How far (m) the alarm's noise carries for the AI.
@export var alarm_radius := 70.0
## Klaxon blasts, ALARM_GAP s apart.
@export var alarm_blasts := 6
## (0.38.7, owner: "maybe takes some time to open") seconds from throwing it until its extracts open: the lifeboat
## lowering (30 s), the pilot boat's engine warming up (20 s). 0 opens them at once. The alarm sounds the whole time.
@export var open_delay := 0.0

const ALARM_GAP := 2.4

var used := false
## Seconds left until its extracts open (while open_delay runs).
var _wait_left := 0.0


func _ready() -> void:
	collision_layer = 8          # interactables
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.9, 0.7)
	shape.shape = box
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.6, 0.15)
	mesh.material_override = mat
	add_child(mesh)


func prompt() -> String:
	if _wait_left > 0.0:
		return "Wait... %d s" % ceili(_wait_left)
	if used and open_delay > 0.0:
		return "Ready"
	return "Power on" if used else prompt_text


func use(_from: Vector3) -> void:
	if used:
		return
	# Online (0.33.8): the server throws it, for everyone in the raid (and its scavs hear the alarm); it comes
	# back to us as power_on().
	if Network.main.in_online_raid():
		Network.main.use_switch(switch_id)
		return
	power_on()


## The switch goes over: the power comes on, what waited for it opens, the alarm sounds.
func power_on() -> void:
	if used:
		return
	used = true
	WorldSounds.at(self, WorldSounds.POWER_ON, global_position, 0.0, 40.0)
	var zones: Array[ExtractZone] = []
	var powered: Array[Vector3] = [global_position]
	for node in RaidScope.nodes(self, &"extracts"):
		var zone := node as ExtractZone
		if zone != null and zone.needs_power == switch_id:
			zones.append(zone)
			powered.append(zone.global_position)
	var blasts := alarm_blasts
	if open_delay > 0.0:
		blasts = maxi(blasts, ceili(open_delay / ALARM_GAP) + 1)   # it keeps blaring until the boat's ready
	_alarm(powered, blasts)
	if open_delay > 0.0:
		_wait_left = open_delay
		while _wait_left > 0.0:
			if not is_inside_tree():
				return
			await get_tree().process_frame
			_wait_left -= get_process_delta_time()
		_wait_left = 0.0
	for zone in zones:
		if is_instance_valid(zone):
			zone.set_open(true)


func _alarm(at: Array[Vector3], blasts: int) -> void:
	for blast in blasts:
		if not is_inside_tree():
			return
		for pos in at:
			WorldSounds.at(self, WorldSounds.ALARM, pos, 4.0, 120.0)
			RaidScope.call_all(self, &"enemies", &"hear_noise", [pos, alarm_radius])
		await get_tree().create_timer(ALARM_GAP).timeout
