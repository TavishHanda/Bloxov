extends "res://scripts/scav_base.gd"
## The AI's senses: seeing and spotting players, hearing noises, alerting and calling others, its voice.

const ALERT_SOUND := preload("res://audio/alert.wav")
const BARK_HEAR_RANGE := 50.0
## Callouts (0.12.12; 0.12.27, owner: cartoony gibberish, no real voice lines): barks from tools/gen_voice_placeholders.py,
## 3 takes per kind (audio/voice/<kind>.wav, <kind>_2.wav, <kind>_3.wav).
const VOICE := {
	"spotted": preload("res://audio/voice/spotted.wav"), "lost": preload("res://audio/voice/lost.wav"),
	"cover": preload("res://audio/voice/cover.wav"), "flank": preload("res://audio/voice/flank.wav"),
	"hurt": preload("res://audio/voice/hurt.wav"), "man_down": preload("res://audio/voice/man_down.wav"),
	"help": preload("res://audio/voice/help.wav"), "push": preload("res://audio/voice/push.wav"),
	"heal": preload("res://audio/voice/heal.wav"),
}

var _target: Player
## Where the target was last seen (or where a hit came from), and where a heard sound came from.
var _last_seen := Vector3.ZERO
var _goal := Vector3.ZERO
var _looting_left := 0.0
## 0..1: how close it is to noticing you (fills while you're in view, drains when you're not).
var _spot := 0.0
## How long it takes in ALERT before it starts aiming (reaction_time, or startle_reaction_time when shot at).
var _reaction := 0.0
var _can_see := false
## Cover: seconds since the last threat, where it's heading/holding, and the cooldown.
enum Cover { NONE, MOVING, HOLDING, HEALING, FLANKING, PEEKING }
var _since_threat := 0.0
var _cover_phase := Cover.NONE
## Where it last heard something, and how long it still stands looking that way first.
var _heard_at := Vector3.ZERO
var _look_at_sound_left := 0.0
signal alerted
## Said a callout (VOICE key); online the server sends it on so players hear it.
signal barked(kind: String)
const NET_AIM := 16


## Called via the "enemies" group by anything that makes noise (shots, footsteps, knife, searching).
## Unaware scavs walk over to investigate; scavs already fighting ignore it.
func hear_noise(pos: Vector3, radius: float) -> void:
	if puppet:
		return
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH] or global_position.distance_to(pos) > radius * hearing_mult:
		return
	if stays_home and not _near_home(pos):
		return
	if radius >= alarm_noise and not _is_responding() and _responders() >= max_responders:
		_hold_alert(pos)
		return
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_goal = pos + offset
	# First it snaps round to look where the sound came from (0.12.30, owner: walking right past them, they never
	# looked); then it walks over. (Not again for every footstep it's already looking toward.)
	var to_sound := _flat(pos - global_position)
	if state != State.INVESTIGATE or (to_sound.length() > 0.1 and _flat(-global_basis.z).normalized().dot(to_sound.normalized()) < 0.5):
		_heard_at = pos
		_look_at_sound_left = 0.85
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)
	if radius >= alarm_noise:
		_alarmed = true


## Fills the spot meter while the target is in view (by distance, stance, movement); true once it's noticed.
func _spotting(delta: float, to_target: Vector3, dist: float, mult: float) -> bool:
	# (No target: everyone left, died or extracted since the last sight check.)
	if _target == null or not (_can_see and _in_view(to_target)):
		_spot = maxf(_spot - delta * 0.5, 0.0)
		return false
	var t := lerpf(spot_time_near, spot_time_far, clampf((dist - 5.0) / maxf(sight_range - 5.0, 1.0), 0.0, 1.0))
	if _target.is_crouching:
		t *= spot_crouch_mult
	if _looting_left > 0.0:
		t *= spot_looting_mult
	if _target.is_sprinting():
		t *= spot_sprint_mult
	elif _target.horizontal_speed() < 0.5:
		t *= spot_still_mult
	_spot += delta / maxf(t * mult, 0.01)
	return _spot >= 1.0


## A bullet from `shooter_pos` passed close by: unaware scavs turn toward roughly where it came from.
func notice_near_miss(shooter_pos: Vector3) -> void:
	if puppet:
		return
	_since_threat = 0.0
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	# The farther the shooter, the rougher its guess.
	var spread := global_position.distance_to(shooter_pos) * 0.15
	var guess := shooter_pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * spread
	_alert(guess, startle_reaction_time)


## Spotted (or got shot by) someone at `known_pos`: get ready to fight, starting to aim after `reaction` seconds
## (-1 = reaction_time).
func _alert(known_pos: Vector3, reaction := -1.0) -> void:
	# (Ones that came because of a call don't call again, so one fight doesn't pull in the whole map.)
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		if not _answering_call and _call_for_help(known_pos):
			_bark("help")
		else:
			_bark("spotted", 0.7)
	_reaction = reaction_time if reaction < 0.0 else reaction
	_cover_phase = Cover.NONE
	_spot = 0.0
	_looting_left = 0.0
	_last_seen = known_pos
	_set_state(State.ALERT)
	alerted.emit()
	net_alerted()


## A fight starts: unaware AI nearby (its zone-mates, mostly) come over to help.
## True if anyone was in earshot.
func _call_for_help(known_pos: Vector3) -> bool:
	if help_radius <= 0.0 or puppet:
		return false
	var called := false
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally.faction == faction and global_position.distance_to(ally.global_position) <= help_radius:
			ally.answer_call(known_pos)
			called = true
	return called


## Another AI called for help: if unaware, jog over toward where the fight is (not exactly where you are).
func answer_call(pos: Vector3) -> void:
	if puppet or holds_position or state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	if stays_home and not _near_home(pos):
		return
	if not _is_responding() and _responders() >= max_responders:
		_hold_alert(pos)
		return
	_goal = pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_looting_left = 0.0
	_answering_call = true
	_set_state(State.INVESTIGATE)


## Heading over to a fight it heard or was called to.
func _is_responding() -> bool:
	return state == State.INVESTIGATE and (_answering_call or _alarmed)


## How many AI in this raid are heading over to a fight right now.
func _responders() -> int:
	var count := 0
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally._is_responding():
			count += 1
	return count


## Enough others are already going: it stays put, on alert, looking toward the trouble (quicker to spot you).
func _hold_alert(pos: Vector3) -> void:
	_looting_left = 0.0
	_goal = pos
	if state != State.SEARCH:
		_set_state(State.SEARCH)
	if _flat(pos - global_position).length() > 0.5:
		look_at(Vector3(pos.x, global_position.y, pos.z), Vector3.UP)


## The target is reloading, healing or under 40% health (a moment to push).
func _target_busy() -> bool:
	return _target != null and is_instance_valid(_target) and (_target.is_healing() or (_target.gun != null and _target.gun.is_reloading)
		or _target.is_low())   # (0.15.18, owner: you're under 40% health, so they come at you)


## The closest player who can still be fought (co-op ready: never assumes a single player).
func _pick_target() -> Player:
	var best: Player = null
	var best_dist := INF
	for node in RaidScope.nodes(self, &"player"):
		var player := node as Player
		if player == null or player.out_of_fight():
			continue
		var d := global_position.distance_to(player.global_position)
		if d < best_dist:
			best = player
			best_dist = d
	return best


## Shot by someone other than who it's fighting (co-op): it turns on the one shooting it (0.12.31; it used to keep
## its eyes on the closest player while someone else shot it).
func _target_shooter(source_position: Vector3) -> void:
	for node in RaidScope.nodes(self, &"player"):
		var player := node as Player
		if player != null and player != _target and not player.out_of_fight() \
				and player.global_position.distance_to(source_position) < 2.5:
			_target = player
			_lost_sight_time = 0.0
			return


## Something threatened it (a shot fired, a hit, a near miss): no break in the fight right now.
func notice_threat() -> void:
	if puppet:
		return
	_since_threat = 0.0


var _glint: MeshInstance3D = null
var _bark_left := 0.0
## Seconds to its next mutter while wandering (0.20.4; its own dice, so the AI's other rolls don't change).
var _mutter_left := -1.0
static var _mutter_dice := RandomNumberGenerator.new()
var _voice := 1.0
## Where the last hit on it came from (friends nearby turn that way when it dies).
var _last_hit_from := Vector3.INF


## The scope glint: a bright spot by the head that always faces the camera.
func _make_glint() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.98, 0.8, 1.0)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	# A solid bright core with a soft edge (an additive glow vanished against the bright sky).
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.22, Color(1, 1, 1, 1))
	grad.add_point(0.5, Color(1, 0.8, 0.25, 0.9))
	tex.gradient = grad
	mat.albedo_texture = tex
	quad.material = mat
	_glint = MeshInstance3D.new()
	_glint.mesh = quad
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0.12, 1.72, -0.45)
	_glint.visible = false
	add_child(_glint)


## How bright its scope glint looks from `eye` (0 = none): full while it aims your way, a faint flicker as its
## scan sweeps past you, nothing when it faces away or you're right next to it.
func glint_strength(eye: Vector3) -> float:
	if not glint or state == State.DEAD:
		return 0.0
	var to_eye := _flat(eye - global_position)
	if to_eye.length() < 12.0:
		return 0.0
	var facing := _flat(-global_basis.z).normalized()
	var angle := rad_to_deg(facing.angle_to(to_eye.normalized()))
	var aiming := (_net_flags & NET_AIM) != 0 if puppet else state in [State.ALERT, State.ENGAGE]
	if aiming:
		return clampf((40.0 - angle) / 15.0, 0.0, 1.0)
	return clampf((14.0 - angle) / 8.0, 0.0, 1.0) * 0.5


func _update_glint() -> void:
	if _glint == null:
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var strength := glint_strength(camera.global_position) if camera != null else 0.0
	_glint.visible = strength > 0.0
	if _glint.visible:
		# Grows with distance so it still reads as a bright dot far away, and twinkles a little.
		var dist := camera.global_position.distance_to(_glint.global_position)
		var size := clampf(dist * 0.06, 0.8, 8.0) * strength * randf_range(0.8, 1.15)
		_glint.scale = Vector3.ONE * size


func _has_line_of_sight() -> bool:
	if _target == null:
		return false
	var eyes := global_position + Vector3(0, 1.65, 0)
	var query := PhysicsRayQueryParameters3D.create(eyes, _target.eye_position(), 1 | Door.LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Just died: unaware friends close by, or ones that see it go down, turn toward roughly where it was shot from.
func _warn_friends() -> void:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3(0, 1.2, 0)
	var said := false   # (one "man down" is enough)
	for node in RaidScope.nodes(self, &"enemies"):
		var friend := node as Scav
		if friend == null or friend == self or friend.puppet or friend.faction != faction or friend.state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
			continue
		var d := friend.global_position.distance_to(global_position)
		if d > buddy_see_radius:
			continue
		if d > buddy_hear_radius:
			var eyes := friend.global_position + Vector3(0, 1.65, 0)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, chest, 1 | Door.LAYER)).is_empty():
				continue
		friend.notice_near_miss(_last_hit_from)
		if not said:
			said = true
			friend._bark("man_down")


## Alert sound (puppets: the server's scav spotted someone).
## Says a callout (`chance` of it, at most one per bark_cooldown); online the server passes it on to players.
func _bark(kind: String, chance := 1.0) -> void:
	if puppet or _bark_left > 0.0 or randf() > chance:
		return
	_bark_left = bark_cooldown
	play_bark(kind)
	barked.emit(kind)


## Chatter (Sound update 0.20.4): a line that isn't a callout (muttering on patrol, a chuckle after a kill, a
## grenade warning). It doesn't use up the callout cooldown, so it never holds back a "spotted" or a "cover".
func _chatter(kind: String) -> void:
	if puppet or _bark_left > 0.0:
		return
	play_bark(kind)
	barked.emit(kind)


## Muttering is quiet and only heard close by (0.20.4).
const MUTTER_RANGE := 20.0


## The callout's sound (puppets: the server's scav said it).
func play_bark(kind: String) -> void:
	var stream := _voice_line(kind, voice_set)
	if stream != null and is_inside_tree():
		var mutter := kind == "idle"
		Effects.sound_at(get_tree().current_scene, stream, global_position + Vector3(0, 1.6, 0), -7.0 if mutter else -1.0, 0.03,
			_voice, 4.0 if mutter else 8.0, MUTTER_RANGE if mutter else BARK_HEAR_RANGE)


## A random take of a callout: audio/voice/<kind>.wav, plus <kind>_2.wav, <kind>_3.wav... if they exist (a voice set:
## audio/voice/<set>/..., falling back to everyone's).
static var _voice_takes := {}


static func _voice_line(kind: String, set_name := "") -> AudioStream:
	var key := set_name + "/" + kind
	if not _voice_takes.has(key):
		var takes: Array[AudioStream] = []
		var folder := "res://audio/voice/" + (set_name + "/" if set_name != "" else "")
		if set_name == "" and VOICE.has(kind):
			takes.append(VOICE[kind])
		elif ResourceLoader.exists(folder + kind + ".wav"):
			takes.append(load(folder + kind + ".wav"))
		for i in range(2, 9):
			var path := "%s%s_%d.wav" % [folder, kind, i]
			if not ResourceLoader.exists(path):
				break
			takes.append(load(path))
		if takes.is_empty() and set_name != "":
			return _voice_line(kind)
		_voice_takes[key] = takes
	var options: Array[AudioStream] = _voice_takes[key]
	return options.pick_random() if not options.is_empty() else null


func net_alerted() -> void:
	Effects.sound_at(get_tree().current_scene, ALERT_SOUND, global_position, -2.0, 0.05, 1.0, 6.0, BARK_HEAR_RANGE)
