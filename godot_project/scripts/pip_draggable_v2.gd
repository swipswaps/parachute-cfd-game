extends SubViewportContainer

var dragging := false
var drag_offset := Vector2()


func _input(event) -> void:
	print("[INPUT] pip_draggable_v2.gd:7 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:7 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:7 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:6 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:6 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:6 _input/_unhandled_input triggered")
	print("[INPUT] pip_draggable_v2.gd:6 _input/_unhandled_input triggered")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_offset = get_global_mouse_position() - position
			get_viewport().set_input_as_handled()
		else:
			dragging = false
			var main = get_tree().current_scene
			if main.has_method("save_pip_position"):
				main.save_pip_position(position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		position = get_global_mouse_position() - drag_offset
		get_viewport().set_input_as_handled()
