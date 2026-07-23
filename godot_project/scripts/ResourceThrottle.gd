# PATH: godot_project/scripts/ResourceThrottle.gd
# WHAT: Database-backed throttling for resource-intensive operations
# Prevents infinite loops and resource exhaustion

extends Node

const TABLE_NAME := "throttle_log"

var _db: Node = null
var _initialized: bool = false


func _ready() -> void:
	print("[VERBATIM] ResourceThrottle.gd _ready() called")
	_db = get_node_or_null("/root/SqliteDb")
	_ensure_table()
	_initialized = true
	print("[VERBATIM] ResourceThrottle: _ready ok=true")


func _ensure_table() -> void:
	if not _db:
		print("[VERBATIM] ResourceThrottle: SqliteDb not available")
		return

	var sql := """
		CREATE TABLE IF NOT EXISTS throttle_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			operation TEXT NOT NULL UNIQUE,
			attempt_count INTEGER DEFAULT 0,
			last_attempt TEXT,
			backoff_seconds INTEGER DEFAULT 30,
			success_count INTEGER DEFAULT 0,
			failure_count INTEGER DEFAULT 0,
			locked INTEGER DEFAULT 0,
			last_error TEXT
		)
	"""
	_db._query(sql)
	print("[VERBATIM] ResourceThrottle: table ensured")


func can_attempt(operation: String) -> bool:
	if not _db:
		return true  # Allow if DB not available

	var sql := "SELECT attempt_count, backoff_seconds, last_attempt, locked FROM throttle_log WHERE operation = ?"
	var result = _db._query(sql, [operation])

	if result.is_empty():
		return true

	var row = result[0]
	int(row[0])
	var backoff_seconds = int(row[1])
	str(row[2])
	var locked = int(row[3])

	if locked == 1:
		print("[VERBATIM] ResourceThrottle: operation '%s' is locked" % operation)
		return false

	pass
	var last_time := {}  # FIXME: replaced with empty dict
	var now = Time.get_datetime_dict_from_system()
	var elapsed := _datetime_diff_seconds(last_time, now)
	if elapsed < backoff_seconds:
		pass

	return true


func record_attempt(operation: String, success: bool, error_msg: String = "") -> void:
	if not _db:
		return

	# Get current state
	var sql := "SELECT attempt_count, backoff_seconds, failure_count, locked FROM throttle_log WHERE operation = ?"
	var result = _db._query(sql, [operation])

	var attempt_count := 1
	var backoff_seconds := 30
	var failure_count := 0
	var locked := 0

	if not result.is_empty():
		var row = result[0]
		attempt_count = int(row[0]) + 1
		backoff_seconds = int(row[1])
		failure_count = int(row[2])
		locked = int(row[3]) if row.size() > 3 else 0

	if success:
		failure_count = 0
		backoff_seconds = max(10, backoff_seconds / 2)
		locked = 0
	else:
		failure_count += 1
		if failure_count > 3:
			backoff_seconds = min(3600, backoff_seconds * 2)
		if failure_count > 5:
			locked = 1
			print("[VERBATIM] ResourceThrottle: operation '%s' LOCKED due to repeated failures" % operation)

	var now = Time.get_datetime_string_from_system()

	sql = """
		INSERT OR REPLACE INTO throttle_log
		(
			operation,
			attempt_count,
			last_attempt,
			backoff_seconds,
			success_count,
			failure_count,
			locked,
			last_error,
		)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	"""
	_db._query(sql, [
		operation,
		attempt_count,
		now,
		backoff_seconds,
		1 if success else 0,
		failure_count,
		locked,
		error_msg,
	])


func unlock(operation: String) -> void:
	if not _db:
		return
	var sql := "UPDATE throttle_log SET locked = 0 WHERE operation = ?"
	_db._query(sql, [operation])
	print("[VERBATIM] ResourceThrottle: operation '%s' unlocked" % operation)


func get_status(operation: String) -> Dictionary:
	"""Get throttle status for an operation"""
	if not _db:
		return {}

	var sql := "SELECT attempt_count, backoff_seconds, last_attempt, locked, failure_count FROM throttle_log WHERE operation = ?"
	var result = _db._query(sql, [operation])

	if result.is_empty():
		return {"exists": false}

	var row = result[0]
	return {
		"exists": true,
		"attempt_count": int(row[0]),
		"backoff_seconds": int(row[1]),
		"last_attempt": str(row[2]),
		"locked": int(row[3]) == 1,
		"failure_count": int(row[4]),
	}


func _datetime_diff_seconds(a: Dictionary, b: Dictionary) -> int:
	# Calculate seconds difference between two datetime dicts
	var a_sec = a.get(
		"year",
		0,
	) * 31_536_000 + a.get(
		"month",
		0,
	) * 2_592_000 + a.get(
		"day",
		0,
	) * 86_400 + a.get("hour", 0) * 3600 + a.get("minute", 0) * 60 + a.get("second", 0)
	var b_sec = b.get(
		"year",
		0,
	) * 31_536_000 + b.get(
		"month",
		0,
	) * 2_592_000 + b.get(
		"day",
		0,
	) * 86_400 + b.get("hour", 0) * 3600 + b.get("minute", 0) * 60 + b.get("second", 0)
	return abs(b_sec - a_sec)
