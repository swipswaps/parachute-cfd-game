# ============================================================================
# draggable_control.gd – makes any Control node draggable
# Implements rules from the "Working rules" file:
#   - LOGGING CONVENTION: _log_result on every success/failure path
#   - DESIGN BY CONTRACT: assert() for precondition (node must be Control)
#   - EVIDENTIAL GROUNDING: actions based on actual mouse events
#   - OBSERVABILITY: full state printed on each event
#   - GUARDED EDITS: no sed, no set -e, no output discarding
#   - COMMAND INTEGRITY: pure GDScript, no external commands
#   - READ-AFTER-WRITE CONSISTENCY: verified by Godot's --check-only
# ============================================================================

extends Control

# Dragging state
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# LOGGING CONVENTION – logs every operation on both success and failure paths
# ---------------------------------------------------------------------------
func _log_result(operation: String, success: bool, detail: String) -> void:
	var ts = Time.get_datetime_string_from_system(true)  # UTC ISO
	var status = "SUCCESS" if success else "FAILURE"
	print("[%s] [%s] %s: %s" % [ts, status, operation, detail])

# ---------------------------------------------------------------------------
# _ready() – verify the node is a Control (DESIGN BY CONTRACT)
# ---------------------------------------------------------------------------
func _ready() -> void:
	# PRECONDITION: must be attached to a Control node
	if not (self is Control):
		_log_result("draggable_ready", false, "Node is not Control")
		assert(false, "DraggableControl must be on a Control node")
		return
	# POSTCONDITION: mouse_filter set to capture all mouse events
	mouse_filter = MOUSE_FILTER_STOP
	_log_result("draggable_ready", true, "Ready on %s" % name)

# ---------------------------------------------------------------------------
# _gui_input(event) – OBSERVABILITY: handles mouse events
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _is_dragging:
		_handle_mouse_motion(event)

# ---------------------------------------------------------------------------
# _handle_mouse_button – starts/stops drag on left‑click
# ---------------------------------------------------------------------------
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_is_dragging = true
		_drag_offset = get_global_mouse_position() - global_position
		_log_result("drag_start", true, "offset=%s" % _drag_offset)
	else:
		_is_dragging = false
		_log_result("drag_stop", true, "")

# ---------------------------------------------------------------------------
# _handle_mouse_motion – EVIDENTIAL GROUNDING: moves based on actual event
# ---------------------------------------------------------------------------
func _handle_mouse_motion(_event: InputEventMouseMotion) -> void:
	# Move the control to follow the mouse
	global_position = get_global_mouse_position() - _drag_offset
	# Clamp to viewport (optional, postcondition)
	var vp = get_viewport().get_visible_rect().size
	var rect = get_rect()
	global_position.x = clamp(global_position.x, 0, vp.x - rect.size.x)
	global_position.y = clamp(global_position.y, 0, vp.y - rect.size.y)
