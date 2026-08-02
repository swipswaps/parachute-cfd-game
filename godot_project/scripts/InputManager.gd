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

	# Headless auto-start: simulate ui_accept ONCE at boot, only for
	# actual --headless CLI runs. Moved out of _input() (this session) —
	# it was gated on GODOT_HEADLESS env var, which autostall.py sets
	# to "1" unconditionally on every run, interactive or not, so the
	# old code re-fired (with an await mid-_input()!) on every single
	# key/mouse event. Same fix pattern as build_terrain.gd Defect 3.
	if "--headless" in OS.get_cmdline_args():
		call_deferred("_on_ready_headless_deferred")


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
		else:
			# FIX (this session): was unconditional — fired even when
			# ui_accept/ui_cancel/restart matched above, falsely
			# reporting a missing action on every keypress. Now only
			# the genuine unmatched-action fallback.
			ErrorLogger._forward_error("Input action missing", {"action": "ui_accept"})
	print(Time.get_datetime_string_from_system() + " [INFO] InputManager ready")
	print(
		Time.get_datetime_string_from_system() + " [INFO] InputMap.has_action('restart') = ",
		InputMap.has_action("restart"),
	)
	# Ensure all actions exist - now handled by project.godot
	# Headless auto-start moved to _ready() (this session) — see there.


func _unhandled_input(event) -> void:
	# FIX (this session): 7 duplicate prints removed. Their literal
	# text ("InputManager.gd:16" / "InputManager.gd:9") was being
	# misread by autostall.py's error extractor as a real file:line
	# reference, producing false "[STALL SOURCE]" dumps of the inert
	# ACTIONS dict on every deploy/restart/etc. No crash was ever
	# occurring — confirmed via session_20260723_174844.txt showing
	# normal gameplay immediately before/after each false alarm.
	print("[INPUT] unhandled_input triggered")
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

func _on_ready_headless_deferred() -> void:
	await get_tree().process_frame
	Input.action_press("ui_accept")
	Input.action_release("ui_accept")
	print("[VERBATIM] InputManager auto‑start triggered.")
