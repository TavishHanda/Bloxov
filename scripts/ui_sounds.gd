class_name UISounds
extends RefCounted
## Menu and screen sounds (Sound update 0.20.6), on their own UI bus: a soft click on every button, equipping gear,
## buying, Ming's boxes, START RAID, the extract countdown, and the end of a raid. Soft and low, like the sell sound.

const CLICK := preload("res://audio/ui/click.wav")
const EQUIP := preload("res://audio/ui/equip.wav")
const BUY := preload("res://audio/ui/buy.wav")
const BOX := preload("res://audio/ui/box.wav")
const START := preload("res://audio/ui/start.wav")
const BEEP := preload("res://audio/ui/beep.wav")
const BEEP_LAST := preload("res://audio/ui/beep_last.wav")
const EXTRACTED := preload("res://audio/ui/extracted.wav")
const DIED := preload("res://audio/ui/died.wav")
const BUS := &"UI"

static var _hooked := false


## Plays a UI sound (not in the game world: no echo, its own volume).
static func play(node: Node, stream: AudioStream, volume_db := -8.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.bus = Hearing.bus(BUS)
	audio.process_mode = Node.PROCESS_MODE_ALWAYS   # (menus open over a paused raid)
	node.get_tree().root.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()


## Every button, now and from now on, clicks when pressed (once per game).
static func hook_buttons(tree: SceneTree) -> void:
	if _hooked:
		return
	_hooked = true
	tree.node_added.connect(_on_node_added)
	for node in tree.root.find_children("*", "BaseButton", true, false):
		_on_node_added(node)


static func _on_node_added(node: Node) -> void:
	if node is BaseButton and not (node as BaseButton).pressed.is_connected(_click.bind(node)):
		(node as BaseButton).pressed.connect(_click.bind(node))


static func _click(button: BaseButton) -> void:
	play(button, CLICK, -14.0)
