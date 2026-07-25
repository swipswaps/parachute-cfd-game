@tool
extends Node

var parent: Node = null
var _character: Node3D  # or whatever type you use
var state: int          # reference to BuildTerrain.GameState enum if needed

func setup(parent_node: Node) -> void:
	parent = parent_node

func _ready() -> void:
	print("[VERBATIM] FlightController _ready")

func _process(delta: float) -> void:
	if parent == null:
		return
	if Input.is_action_pressed("pitch"):
		_handle_pitch(delta)
	if Input.is_action_pressed("roll"):
		_handle_roll(delta)
	if Input.is_action_pressed("yaw"):
		_handle_yaw(delta)
	if Input.is_action_pressed("throttle"):
		_handle_throttle(delta)
	if Input.is_action_pressed("brake"):
		_handle_brake(delta)
	if Input.is_action_pressed("collective"):
		_handle_collective(delta)
	if Input.is_action_pressed("camera_cycle"):
		_handle_camera_cycle(delta)
	if Input.is_action_pressed("hud_toggle"):
		_handle_hud_toggle(delta)
	if Input.is_action_pressed("flight_check"):
		_handle_flight_check(delta)

	if Input.is_action_pressed("turn_left"):
		_handle_turn_left(delta)
	if Input.is_action_pressed("turn_right"):
		_handle_turn_right(delta)
func _input(event: InputEvent) -> void:
	print("[INPUT] flight_controller.gd:36 _input/_unhandled_input triggered")
	print("[INPUT] flight_controller.gd:36 _input/_unhandled_input triggered")
	# Only handle mouse and keyboard events here
	if event is InputEventMouseMotion:
		# Rotate character based on mouse movement
		var sensitivity := 0.002
		if _character:
			_character.rotate_y(-event.relative.x * sensitivity)
			# Pitch not implemented for simplicity
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if state == BuildTerrain.GameState.FREEFALL:   # ensure BuildTerrain.GameState is defined elsewhere
			_deploy_canopy()

func _handle_pitch(_delta: float) -> void:
	pass  # implement

func _handle_roll(_delta: float) -> void:
	pass  # implement

func _handle_yaw(_delta: float) -> void:
	pass  # implement

func _handle_throttle(_delta: float) -> void:
	pass  # implement

func _handle_brake(_delta: float) -> void:
	pass  # implement

func _handle_collective(_delta: float) -> void:
	pass  # implement

func _handle_camera_cycle(_delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.has_method("_cycle_camera"):
		main._cycle_camera()
func _handle_hud_toggle(_delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.has_method("_toggle_hud"):
		main._toggle_hud()

func _handle_turn_left(_delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.has_method("_turn_left"):
		main._turn_left()

func _handle_turn_right(_delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.has_method("_turn_right"):
		main._turn_right()
func _handle_flight_check(_delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.has_method("_flight_control_check"):
		main._flight_control_check()
func _deploy_canopy() -> void:
	print("[VERBATIM] Deploying canopy from flight_controller")
	# Add your canopy deployment logic here
