extends CanvasLayer
## Shows the "click to play" hint while the mouse is free, and the crosshair while playing.

@onready var hint: Label = $Hint
@onready var crosshair: Label = $Crosshair


func _process(_delta: float) -> void:
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	hint.visible = not playing
	crosshair.visible = playing
