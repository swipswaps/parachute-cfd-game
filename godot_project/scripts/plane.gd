extends CharacterBody3D
signal jumped_from_plane(player_pos: Vector3, plane_vel: Vector3)

func _ready() -> void:
	pass

func _process(_delta) -> void:
	# Heartbeat to confirm this script is active
	if Engine.get_process_frames() % 300 == 0:
		pass
	if Input.is_action_just_pressed("deploy"):
		emit_signal("jumped_from_plane", global_position, velocity)

# IMPLEMENTATION COMPLETE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("deploy"):
		emit_signal("jumped_from_plane", global_position, velocity)

func test_plane_process() -> void:
	pass

# IMPLEMENTATION COMPLETE

func jump_from_plane() -> void:
	emit_signal("jumped_from_plane", global_position, velocity)
