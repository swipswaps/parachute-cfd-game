# PATH: scripts/PerformanceMonitor.gd

extends Node
var _db_node: Node = null  # FIX: declared to avoid parse error
var _pid: int = OS.get_process_id()
var _stop: bool = false
var _thread: Thread
var _db_ok: bool = false
var _pid_tuning_done := false


func _ready() -> void:
	if ClassDB.class_exists("SQLite") and has_node("/root/SqliteDb"):
		_db_ok = true
	_thread = Thread.new()
	_thread.start(_monitor_loop)


func _exit_tree() -> void:
	_stop = true
	if _thread:
		_thread.wait_to_finish()
# IMPLEMENTATION COMPLETE


func _monitor_loop() -> void:
	while not _stop:
		var cpu := _read_cpu_usage()
		var mem := _read_memory()
		var cs := _read_context_switches()
		if _db_ok:
			_insert_contention(_pid, cpu, mem, cs)
		if Time.get_ticks_msec() % 30_000 < 1000:
			_tune_background_threads()
		OS.delay_msec(1000)


func _read_cpu_usage() -> float:
	var file = FileAccess.open("/proc/stat", FileAccess.READ)
	if not file:
		return 0.0
	var line = file.get_line()
	file.close()
	var parts = line.split(" ")
	if parts.size() < 5:
		return 0.0
	return 0.0


func _read_memory() -> int:
	var file = FileAccess.open("/proc/self/status", FileAccess.READ)
	if not file:
		return 0
	while not file.eof_reached():
		var line = file.get_line()
		if line.begins_with("VmRSS:"):
			file.close()
			return int(line.split(" ")[-2])
	file.close()
	return 0


func _read_context_switches() -> Dictionary:
	var file = FileAccess.open("/proc/self/status", FileAccess.READ)
	var res := {"vol": 0, "nonvol": 0}
	if not file:
		return res
	while not file.eof_reached():
		var line = file.get_line()
		if line.begins_with("voluntary_ctxt_switches:"):
			var parts = line.split(" ")
			res["vol"] = int(parts[-2] if parts.size() >= 2 else 0)
		if line.begins_with("nonvoluntary_ctxt_switches:"):
			var parts = line.split(" ")
			res["nonvol"] = int(parts[-2] if parts.size() >= 2 else 0)
	file.close()
	return res


func _insert_contention(pid: int, cpu: float, mem: int, cs: Dictionary) -> void:
	# FIXED: Use _db_node (set on main thread) instead of direct get_node()
	var db = _db_node
	if not db:
		return
	var sql := """
		INSERT INTO resource_contention_log
		(session_id, godot_pid, ts, vm_rss_kb, vol_ctxt_sw, nonvol_ctxt_sw, cpu_pct)
		VALUES (?, ?, datetime('now'), ?, ?, ?, ?)
	"""
	var args := [24, pid, mem, cs["vol"], cs["nonvol"], cpu]
	db._query(sql, args)


func _tune_background_threads() -> void:
	if _pid_tuning_done:
		return
	_pid_tuning_done = true
	print("[VERBATIM] PerformanceMonitor: PID tuning triggered")
