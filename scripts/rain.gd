class_name Rain
extends Node3D
## Rain for a stormy map (0.33.5, Riptide; a map asks for it with `rain` metadata, RaidMap). Looks and sound only,
## for the local player: never synced, never on the server, and nothing the AI or anyone's sight depends on.
## A box of falling streaks follows the camera and stops under a roof; the rain sound drops low indoors.

const SOUND := preload("res://audio/ambience/rain.wav")
## Streaks at once, and the box they fall through round the camera (metres).
const COUNT := 700
const AREA := Vector3(16.0, 7.0, 16.0)
const FALL := Vector3(-3.0, -24.0, -1.5)   # slanted by the wind
const OUTSIDE_DB := -14.0
const INSIDE_DB := -27.0
## A roof within this far above the camera = under cover.
const ROOF := 40.0

var _drops: CPUParticles3D
var _sound: AudioStreamPlayer
## 0 under a roof .. 1 in the open, eased.
var _open := 1.0


func _ready() -> void:
	_drops = CPUParticles3D.new()
	_drops.amount = COUNT
	_drops.lifetime = 0.55
	_drops.preprocess = 0.6
	_drops.local_coords = false
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(AREA.x, 0.5, AREA.z)
	_drops.direction = FALL.normalized()
	_drops.spread = 2.0
	_drops.gravity = Vector3.ZERO
	_drops.initial_velocity_min = FALL.length() * 0.9
	_drops.initial_velocity_max = FALL.length() * 1.1
	_drops.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.018, 0.8, 0.018)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.86, 0.93, 0.45)
	streak.material = mat
	_drops.mesh = streak
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drops)
	_sound = AudioStreamPlayer.new()
	_sound.stream = Ambience.looped(SOUND)
	_sound.bus = Hearing.bus(Ambience.BUS)
	_sound.volume_db = OUTSIDE_DB
	add_child(_sound)
	_sound.play()


func _physics_process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * ROOF, 1)
	var covered := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_open = move_toward(_open, 0.0 if covered else 1.0, delta * 3.0)
	# The streaks start above the camera and a little upwind, so they cross the view.
	_drops.global_position = from + Vector3(0, AREA.y, 0) - Vector3(FALL.x, 0, FALL.z) * 0.15
	_drops.emitting = not covered
	_sound.volume_db = lerpf(INSIDE_DB, OUTSIDE_DB, _open)
