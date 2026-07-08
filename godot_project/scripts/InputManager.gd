# InputManager.gd – central input handling using _unhandled_input (pattern from
# godot-simplified-flightsim)

extends Node


func _ready():
	print(Time.get_datetime_string_from_system() + " [INFO] InputManager ready")
	print(
		Time.get_datetime_string_from_system() + " [INFO] InputMap.has_action('restart') = ",
		InputMap.has_action("restart"),
	)
	# Ensure all actions exist - now handled by project.godot


func _unhandled_input(event):
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
	if event.is_action_pressed("cycle_camera"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'cycle_camera' pressed"
			)
		)
	if event.is_action_pressed("toggle_hud"):
		print(
			(
				Time.get_datetime_string_from_system()
				+ " [INFO] InputManager: action 'toggle_hud' pressed"
			)
		)
	if event.is_action_pressed("flight_check"):
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
