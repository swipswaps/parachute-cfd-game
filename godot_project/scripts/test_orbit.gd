
extends Node

# This script runs inside Godot and performs the actual camera tests.

var _camera: Camera3D
var _plane_node: Node3D
var _build_terrain: Node
var _game: Node
var _test_results := {}

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Find the main game node (it's the root of the main scene)
	# The main scene is typically a Node named "Game" or the root.
	# We'll search for the main scene by looking for the build_terrain script.
	for node in get_tree().get_root().get_children():
		if node.has_method("toggle_pause") or node.has_method("_ready"):
			_game = node
			break
	if not _game:
		_game = get_tree().get_root().get_child(0)
	_camera = _game.find_child("Camera3D", true, false)
	if not _camera:
		_camera = get_tree().get_root().find_child("Camera3D", true, false)
	_plane_node = _game.find_child("FlyingPlane", true, false)
	if not _plane_node:
		_plane_node = get_tree().get_root().find_child("FlyingPlane", true, false)
	_build_terrain = _game.find_child("BuildTerrain", true, false)
	if not _build_terrain:
		_build_terrain = get_tree().get_root().find_child("BuildTerrain", true, false)
	print("[TEST] Found camera: ", _camera != null)
	print("[TEST] Found plane: ", _plane_node != null)
	print("[TEST] Found build_terrain: ", _build_terrain != null)
	_run_tests()

func _run_tests() -> void:
	print("[TEST] Starting orbital camera integration tests")
	if not _camera or not _plane_node:
		print("[TEST] ERROR: Missing required nodes")
		get_tree().quit()
		return

	# Test 1: Initial camera position (should be behind and above)
	var init_pos = _camera.global_position
	var target = _plane_node.global_position
	var behind = init_pos.z > target.z
	var above = init_pos.y > target.y + 5.0
	_test_results["initial_position"] = {"behind": behind, "above": above, "pass": behind and above}
	print("[TEST] Initial position behind? ", behind, " above? ", above)

	# Test 2: Simulate right-click drag to change azimuth
	var azimuth_changed := false
	var init_az := 0.0
	var new_az := 0.0
	if _build_terrain:
		init_az = _build_terrain._cam_azimuth
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(100, 0)
		ev.button_mask = MOUSE_BUTTON_MASK_RIGHT
		_build_terrain._input(ev)
		new_az = _build_terrain._cam_azimuth
		azimuth_changed = new_az != init_az
	_test_results["azimuth_changed"] = {"initial": init_az, "new": new_az, "pass": azimuth_changed}
	print("[TEST] Azimuth changed? ", azimuth_changed, " from ", init_az, " to ", new_az)

	# Test 3: Zoom in
	var zoom_in_worked := false
	var init_dist := 0.0
	var new_dist := 0.0
	if _build_terrain:
		init_dist = _build_terrain._cam_distance
		var wheel_ev := InputEventMouseButton.new()
		wheel_ev.button_index = MOUSE_BUTTON_WHEEL_UP
		_build_terrain._input(wheel_ev)
		new_dist = _build_terrain._cam_distance
		zoom_in_worked = new_dist < init_dist
	_test_results["zoom_in"] = {"initial": init_dist, "new": new_dist, "pass": zoom_in_worked}
	print("[TEST] Zoom in worked? ", zoom_in_worked, " distance: ", init_dist, " -> ", new_dist)

	# Test 4: Pause and then test azimuth again
	var azimuth_during_pause := false
	var paused_az := 0.0
	var new_paused_az := 0.0
	if _build_terrain:
		if _game.has_method("toggle_pause"):
			_game.toggle_pause()
		elif _build_terrain.has_method("toggle_pause"):
			_build_terrain.toggle_pause()
		await get_tree().process_frame
		paused_az = _build_terrain._cam_azimuth
		var ev2 := InputEventMouseMotion.new()
		ev2.relative = Vector2(-50, 0)
		ev2.button_mask = MOUSE_BUTTON_MASK_RIGHT
		_build_terrain._input(ev2)
		new_paused_az = _build_terrain._cam_azimuth
		azimuth_during_pause = new_paused_az != paused_az
	_test_results["azimuth_during_pause"] = {"initial": paused_az, "new": new_paused_az, "pass": azimuth_during_pause}
	print("[TEST] Azimuth changed during pause? ", azimuth_during_pause)

	# Final report
	print("[TEST_RESULTS] ", JSON.stringify(_test_results))
	get_tree().quit()
