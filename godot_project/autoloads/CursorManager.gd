extends Node
func set_safe_cursor(cursor_name: String, fallback: Texture2D = null) -> void:
	if ResourceLoader.exists(cursor_name):
		Input.set_custom_mouse_cursor(load(cursor_name), Input.CURSOR_ARROW)
	else:
		var error_bus = Engine.get_singleton("ErrorBus")
		if error_bus and error_bus.has_signal("error_occurred"):
			error_bus.error_occurred.emit("CursorManager", "set_safe_cursor", 0, "", "Cursor '" + cursor_name + "' not found. Using fallback.", 1)
		else:
			push_error("CursorManager: Cursor '" + cursor_name + "' not found. Using fallback.")
		if fallback:
			Input.set_custom_mouse_cursor(fallback, Input.CURSOR_ARROW)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
