extends Node

var log_path := "game_state.log"
var log_path_tmp := "/tmp/game_state.log"
var run_id := 0


func _init():
	var args = OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == "--run-id":
			run_id = int(args[i + 1])
			break
	print("[TEST] test_runner.gd _init called, run_id=", run_id)
	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		print("[TEST] ERROR: Could not load main scene")
		quit()
		return
	var main_node = main_scene.instantiate()
	if not main_node:
		print("[TEST] ERROR: Could not instantiate main scene")
		quit()
		return
	root.add_child(main_node)
	# Use a Timer to wait for the game to be ready
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_run_test_deferred)
	root.add_child(timer)


func _run_test_deferred() -> void:
	print("[TEST] _run_test_deferred started")
	var main = root.find_child("Main", true, false)
	if not main:
		print("[TEST] ERROR: Main node not found")
		quit()
		return
	print("[TEST] Main node found")

	var state = (
		main.get("game_state") if main.has_method("get") and main.get("game_state") != null else -1
	)
	var altitude = (
		main.get("altitude") if main.has_method("get") and main.get("altitude") != null else 0.0
	)
	print("[TEST] Initial state=", state, " altitude=", altitude)

	var file = FileAccess.open(log_path, FileAccess.WRITE)
	if not file:
		print("[TEST] ERROR: Could not open log file for writing (current dir)")
		file = FileAccess.open(log_path_tmp, FileAccess.WRITE)
		if not file:
			print("[TEST] ERROR: Could not open /tmp/game_state.log either")
			quit()
			return
			print("[TEST] Writing to /tmp/game_state.log")
	else:
		print("[TEST] Writing to ./game_state.log")

	file.store_line("run_id=" + str(run_id))
	file.store_line("initial_state=" + str(state))
	file.store_line("initial_altitude=" + str(altitude))
	file.close()

	print("[TEST] Pressing SPACE to deploy")
	Input.action_press("ui_accept")
	await create_timer(0.5).timeout
	Input.action_release("ui_accept")
	await create_timer(1.0).timeout

	state = (
		main.get("game_state") if main.has_method("get") and main.get("game_state") != null else -1
	)
	altitude = (
		main.get("altitude") if main.has_method("get") and main.get("altitude") != null else 0.0
	)
	print("[TEST] After deploy state=", state, " altitude=", altitude)

	file = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line("after_state=" + str(state))
		file.store_line("after_altitude=" + str(altitude))
		file.close()
		print("[TEST] Appended to ./game_state.log")
	else:
		file = FileAccess.open(log_path_tmp, FileAccess.READ_WRITE)
		if file:
			file.seek_end()
			file.store_line("after_state=" + str(state))
			file.store_line("after_altitude=" + str(altitude))
			file.close()
			print("[TEST] Appended to /tmp/game_state.log")
		else:
			print("[TEST] ERROR: Could not append to log file")

	var viewport = get_root().get_viewport()
	var img = viewport.get_texture().get_image()
	var ts = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var path = "user://screenshots/test_" + ts + ".png"
	img.save_png(path)
	print("[TEST] Screenshot saved: ", path)

	print("[TEST] Test completed, quitting")
	quit()
