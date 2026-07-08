extends Node

var log_file_path: String = "user://audit_log.txt"
var _file: FileAccess
var _start_time_usec: int


func _ready() -> void:
	_start_time_usec = Time.get_ticks_usec()
	_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _file:
		_writeln("=== AUDIT START ===")
		_writeln("Engine version: %s" % Engine.get_version_info().string)
		_writeln("Platform: %s" % OS.get_name())
		var _rd = RenderingServer.get_rendering_device()
		var _rname = _rd.get_device_name() if _rd else "OpenGL/Compatibility"
		_writeln("Renderer: %s" % _rname)
	else:
		push_warning("Audit: Failed to open log file")


func _process(delta: float) -> void:
	# Basic per-frame metrics
	var now = Time.get_ticks_usec()
	var elapsed_ms = (now - _start_time_usec) / 1000.0

	var fps = Engine.get_frames_per_second()
	var frame_time_ms = 1000.0 / max(fps, 0.001)

	# Keep this lightweight: e.g., log every 30th frame
	if int(elapsed_ms) % 500 == 0:
		_writeln("t=%.1f ms | fps=%.1f | frame_time=%.3f ms" % [elapsed_ms, fps, frame_time_ms])


func log_event(msg: String) -> void:
	_writeln("EVENT: %s" % msg)


func log_error(msg: String) -> void:
	_writeln("ERROR: %s" % msg)
	print("[ERROR-LOC] audit.gd:38 about to call error func")
	print("[ERROR-LOC] audit.gd:39 about to call error func")
	print("[ERROR-LOC] audit.gd:40 about to call error func")
	print("[ERROR-LOC] audit.gd:41 about to call error func")
	print("[ERROR-LOC] audit.gd:45 about to call error func")
	print("[ERROR-LOC] audit.gd:46 about to call error func")
	print("[ERROR-LOC] audit.gd:47 about to call error func")
	push_error(msg)


func log_stack(tag: String = "STACK") -> void:
	_writeln("%s: %s" % [tag, get_stack()])


func _writeln(line: String) -> void:
	if _file:
		_file.store_line(line)
		_file.flush()
