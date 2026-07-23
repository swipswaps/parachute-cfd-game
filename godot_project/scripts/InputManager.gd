# InputManager.gd – central input handling using _unhandled_input (pattern from
# godot-simplified-flightsim)

extends Node

const ACTIONS: Dictionary = {
	"deploy": KEY_SPACE,
	"turnleft": KEY_Q,
	"turnright": KEY_E,
	"cyclecamera": KEY_C,
	"togglehud": KEY_H,
	"flightcheck": KEY_TAB,
	"cutaway": KEY_X,
	"reserve": KEY_V,
	"flare": KEY_F,
	"restart": KEY_R,
	"pause": KEY_ESCAPE,
}


func _ready() -> void:
	if not InputMap.has_action("ui_accept"):
		pass


# ------------------------------------------------------------------
# FILTERED INPUT HANDLING
# ------------------------------------------------------------------
# Only processes input events that are relevant to the game.
# Reduces spam and improves performance.
# Ref: https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
# ------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Filter: only process key presses and mouse button events
	if not (event is InputEventKey or event is InputEventMouseButton):
		return

	# Only log if the event is a press (not release)
	if event is InputEventKey and event.pressed:
		# Check for known actions
		if InputMap.has_action("ui_accept") and event.is_action_pressed("ui_accept"):
			print("[INPUT] ui_accept pressed")
		elif InputMap.has_action("ui_cancel") and event.is_action_pressed("ui_cancel"):
			print("[INPUT] ui_cancel pressed")
		elif InputMap.has_action("restart") and event.is_action_pressed("restart"):
			print("[INPUT] restart pressed")
		# Add more actions as needed
		# You can also handle unhandled events separately
		ErrorLogger._forward_error("Input action missing", {"action": "ui_accept"})
	print(Time.get_datetime_string_from_system() + " [INFO] InputManager ready")
	print(
		Time.get_datetime_string_from_system() + " [INFO] InputMap.has_action('restart') = ",
		InputMap.has_action("restart"),
	)
	# Ensure all actions exist - now handled by project.godot

	# Headless auto‑start: simulate SPACE press
	if OS.get_environment("GODOT_HEADLESS") == "1":
		# Wait a frame to ensure everything is ready
		await get_tree().process_frame
		Input.action_press("ui_accept")
		Input.action_release("ui_accept")
		print("[VERBATIM] InputManager auto‑start triggered.")


func _unhandled_input(event) -> void:
	print("[INPUT] InputManager.gd:16 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:16 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:16 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:9 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:9 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:9 _input/_unhandled_input triggered")
	print("[INPUT] InputManager.gd:9 _input/_unhandled_input triggered")
	# FALLBACK: direct keycode check for R
	if event is InputEventKey and event.pressed and event.keycode == 82:
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: FALLBACK - R key pressed, resetting"
			)
		)
		get_tree().reload_current_scene()
		return

#	# FALLBACK: direct keycode check for Space (deploy)
#	if event is InputEventKey and event.pressed and event.keycode == 32:
#		print(
#			(
#				Time.get_datetime_string_from_system()
#				+ " [INFO] InputManager: FALLBACK - Space key pressed, deploying canopy"
#			)
#		)
#		var plane = get_node_or_null("/root/Main/FlyingPlane")
#		if plane and plane.has_method("jump_from_plane"):
#			plane.jump_from_plane()
#		return
	# This is the key pattern: catch all key events at the root level.
	# Pattern from: github.com/fbcosentino/godot-simplified-flightsim
	if event is InputEventKey and event.pressed:
		var key_name = OS.get_keycode_string(event.keycode)
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: key="
				+ key_name
				+ " code="
				+ str(event.keycode)
			)
		)

	# Dispatch actions to the game
	if event.is_action_pressed("deploy"):
		print(
			Time.get_datetime_string_from_system() + " [INFO] InputManager: action 'deploy' pressed"
		)
		var plane = get_node_or_null("/root/Main/FlyingPlane")
		if plane and plane.has_method("jump_from_plane"):
			plane.jump_from_plane()
	if event.is_action_pressed("restart"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'restart' pressed"
			)
		)
		var main = get_tree().current_scene
		if main and main.has_method("_reset_game"):
			main._reset_game()
	if event.is_action_pressed("turn_left"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'turn_left' pressed"
			)
		)
	if event.is_action_pressed("turn_right"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'turn_right' pressed"
			)
		)
	if event.is_action_pressed("camera_cycle"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'cycle_camera' pressed"
			)
		)
	if event.is_action_pressed("togglehud"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'toggle_hud' pressed"
			)
		)
	if event.is_action_pressed("flightcheck"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'flight_check' pressed"
			)
		)
	if event.is_action_pressed("cutaway"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'cutaway' pressed"
			)
		)
	if event.is_action_pressed("reserve"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'reserve' pressed"
			)
		)
	if event.is_action_pressed("flare"):
		print(
			Time.get_datetime_string_from_system() + " [INFO] InputManager: action 'flare' pressed"
		)
	if event.is_action_pressed("pause"):
		print(
			Time.get_datetime_string_from_system() + " [INFO] InputManager: action 'pause' pressed"
		)
# IMPLEMENTATION COMPLETE
