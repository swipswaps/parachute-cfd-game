extends Node

var _camera: Camera3D = null
var _airplane: Node3D = null
var _anim_player: AnimationPlayer = null


func _ready() -> void:
	# Find camera
	_camera = get_tree().get_first_node_in_group("camera")
	if not _camera:
		var cameras = get_tree().get_nodes_in_group("Camera3D")
		if cameras.size() > 0:
			_camera = cameras[0]

	# Find airplane
	_airplane = get_tree().get_first_node_in_group("airplane")
	if not _airplane:
		# Fallback: try to find any node with "Aircraft" script (by class name)
		var all_nodes = get_tree().get_nodes_in_group("*")  # not ideal, but quick
		for n in all_nodes:
			if n is Node3D and n.get_script() and n.get_script().get_global_name() == "Aircraft":
				_airplane = n
				break

	if _camera and _airplane:
		# If the camera is an orbit_camera, set its target
		if _camera.has_method("set_target") or _camera.get("target") != null:
			_camera.target = _airplane
			print("ViewPoseController: camera target set to airplane")
	else:
		print("ViewPoseController: camera or airplane not found")

	# Optional: find character (for animations) – preserve existing logic
	_character = get_tree().get_first_node_in_group("character")
	if not _character:
		_character = get_node_or_null("/root/World/Character")
	if _character:
		_anim_player = _character.get_node_or_null("AnimationPlayer")

	var reg := get_node_or_null("/root/ComponentRegistry")
	if reg and reg.has_method("register_view_pose_controller"):
		reg.register_view_pose_controller(self)

# Keep all existing methods (get_camera, get_character, etc.)


func get_camera() -> Camera3D:
	return _camera


func get_character() -> Node3D:
	return _character


func set_camera_fov(fov: float) -> void:
	if _camera:
		_camera.fov = fov


func set_camera_position(pos: Vector3) -> void:
	if _camera:
		_camera.position = pos


func set_character_position(pos: Vector3) -> void:
	if _character:
		_character.position = pos


func play_animation(name: String, blend: float = 0.1) -> void:
	if _anim_player:
		_anim_player.play(name, blend)


func get_health() -> Dictionary:
	return {
		"camera_available": _camera != null,
		"character_available": _character != null,
		"anim_player_available": _anim_player != null,
		"current_animation": _anim_player.current_animation if _anim_player else "",
	}
