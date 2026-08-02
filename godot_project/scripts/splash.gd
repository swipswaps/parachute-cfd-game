extends Control

const MAX_RETRIES: int = 3

var retry_count: int = 0

@onready var progress_bar = $ProgressBar if has_node("ProgressBar") else null
@onready var status_label = $StatusLabel if has_node("StatusLabel") else null


func _ready() -> void:
	print("[VERBATIM] ENTER splash _ready")
	if status_label:
		status_label.text = "Checking game integrity..."

	call_deferred("_on_ready_integrity_check")
		_load_game()
		return

	# GameIntegrity exists, connect to its signal and start check
	GameIntegrity.integrity_check_completed.connect(_on_integrity_done)
	GameIntegrity.check_and_repair()


func _on_integrity_done(success: bool, log_path: String) -> void:
	print("[VERBATIM] Integrity check complete. Success: ", success)
	print("[VERBATIM] Log file: ", log_path)
	if status_label:
		status_label.text = "Integrity: " + ("PASS" if success else "FAIL") + "\nLog: " + log_path.get_file()
	_load_game()


func _load_game() -> void:
	if status_label:
		status_label.text = "Loading game..."
	var scene_path := "res://scenes/main.tscn"
	var error = ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		print("[VERBATIM] ERROR: failed to start threaded load")
		if status_label:
			status_label.text = "ERROR: Failed to load scene"
		return

	var tree := get_tree()
	var status = ResourceLoader.THREAD_LOAD_IN_PROGRESS
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var progress := []
		status = ResourceLoader.load_threaded_get_status(scene_path, progress)
		if progress.size() > 0 and progress_bar:
			progress_bar.value = progress[0] * 100
		if not is_instance_valid(tree): break
		await tree.process_frame

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var main_scene = ResourceLoader.load_threaded_get(scene_path)
		if main_scene != null:
			if is_instance_valid(tree): tree.change_scene_to_packed(main_scene)
			print("[VERBATIM] Main scene loaded")
		else:
			print("[VERBATIM] ERROR: loaded scene is null")
			if retry_count < MAX_RETRIES:
				retry_count += 1
				print("[VERBATIM] Retrying load (attempt %d)" % retry_count)
				if status_label:
					status_label.text = "Retrying load (%d/%d)..." % [retry_count, MAX_RETRIES]
				await get_tree().create_timer(0.5).timeout
				_load_game()
			else:
				print("[VERBATIM] Max retries reached – aborting")
				if status_label:
					status_label.text = "FAILED TO LOAD GAME – check logs"
	else:
		print("[VERBATIM] ERROR: threaded load failed")
		if status_label:
			status_label.text = "ERROR: Scene load failed"
# IMPLEMENTATION COMPLETE

func _on_ready_integrity_check() -> void:
	await get_tree().process_frame
	# Check if GameIntegrity autoload exists
	if not has_node("/root/GameIntegrity"):
		print("[VERBATIM] GameIntegrity autoload not found – skipping integrity check")
