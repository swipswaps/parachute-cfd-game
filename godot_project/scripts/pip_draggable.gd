extends SubViewportContainer
# pip_draggable.gd – only drags when clicked directly on the PiP.
# Uses _gui_input so it only responds to events that hit this Control.

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	position = Vector2(10, 10)
	visible = true
	mouse_filter = MOUSE_FILTER_STOP
	size = Vector2(320, 240)
	if get_child_count() > 0 and get_child(0) is SubViewport:
		get_child(0).size = Vector2i(320, 240)
	print("[PIP] _ready: size=", size, " position=", position)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = event.position
			accept_event()
			print("[PIP] drag start offset=", _drag_offset)
		else:
			_dragging = false
			accept_event()
			print("[PIP] drag end position=", position)
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative
		accept_event()

func _save_position() -> void:
	var main = get_tree().current_scene
	if main and main.has_method("save_pip_position"):
		main.save_pip_position(position)
		print("[PIP] position saved: ", position)
