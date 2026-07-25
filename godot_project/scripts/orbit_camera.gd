extends Camera3D

@export var target: Node3D
@export var distance: float = 50.0
@export var min_distance: float = 5.0
@export var max_distance: float = 500.0
@export var sensitivity: float = 0.005

var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("camera")   # so ViewPoseController can find it
	if not target:
		# Try to find the airplane automatically
		var plane = get_tree().get_first_node_in_group("airplane")
		if plane:
			target = plane
			print("orbit_camera: target set to ", target.name)
		else:
			print("WARNING: orbit_camera has no target and no 'airplane' group found.")
	if target:
		_update_camera()


func _input(event: InputEvent) -> void:
	print("[INPUT] orbit_camera.gd:29 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:29 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:29 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:27 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:27 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:27 _input/_unhandled_input triggered")
	print("[INPUT] orbit_camera.gd:27 _input/_unhandled_input triggered")
	if not target:
		return

	# Mouse drag to orbit
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			_last_mouse_pos = event.position

	if event is InputEventMouseMotion and _is_dragging:
		var delta = event.position - _last_mouse_pos
		_yaw -= delta.x * sensitivity
		_pitch -= delta.y * sensitivity
		_pitch = clamp(_pitch, -1.5, 1.5)
		_last_mouse_pos = event.position
		_update_camera()

	# Scroll to zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(distance - 5.0, min_distance)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(distance + 5.0, max_distance)
			_update_camera()


func _update_camera() -> void:
	var offset := Vector3(
		distance * sin(_yaw) * cos(_pitch),
		distance * sin(_pitch),
		distance * cos(_yaw) * cos(_pitch)
	)
	global_position = target.global_position + offset
	look_at(target.global_position, Vector3.UP)
