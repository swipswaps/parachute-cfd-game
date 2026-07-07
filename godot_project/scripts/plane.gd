extends CharacterBody3D

signal jumped_from_plane(player_pos: Vector3, plane_vel: Vector3)


func _ready():
	print(
		Time.get_datetime_string_from_system() + " [INFO] plane.gd: InputMap.has_action('deploy') = ",
		InputMap.has_action("deploy"),
	)


func _process(_delta):
	# Heartbeat to confirm this script is active
	if Engine.get_process_frames() % 300 == 0:
		print("[VERBATIM] plane.gd: _process active (heartbeat)")
	if Input.is_action_just_pressed("deploy"):
		print("[VERBATIM] Plane: deploy action detected")
		emit_signal("jumped_from_plane", global_position, velocity)
# IMPLEMENTATION COMPLETE


func _unhandled_input(event: InputEvent):
	print("[INPUT] plane.gd:23 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:23 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:23 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:17 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:17 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:17 _input/_unhandled_input triggered")
	print("[INPUT] plane.gd:17 _input/_unhandled_input triggered")
	if event.is_action_pressed("deploy"):
		print("[VERBATIM] Plane: unhandled_input deploy")
		emit_signal("jumped_from_plane", global_position, velocity)


func test_plane_process():
	print("[VERBATIM] plane.gd: test_plane_process called")

# IMPLEMENTATION COMPLETE


func jump_from_plane():
	print(Time.get_datetime_string_from_system() + " [INFO] plane.gd: jump_from_plane called, emitting signal")
	emit_signal("jumped_from_plane", global_position, velocity)
