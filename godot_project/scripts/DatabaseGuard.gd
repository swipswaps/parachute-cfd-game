# PATH: godot_project/scripts/DatabaseGuard.gd
# WHAT: Centralized database health management with automatic recovery

extends Node


# ------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------

signal db_healthy
signal db_unhealthy(error: String)
signal db_recovered



var _last_error: String = ""
var _total_queries: int = 0
var _circuit_state: String = "CLOSED"
var _circuit_last_failure: int = 0
var _circuit_timeout_ms: int = 60_000
var _failure_count: int = 0
var _failure_threshold: int = 5
var _recovery_attempts: int = 0
var _max_recovery_attempts: int = 5
var _connection_retries: int = 0
var _retry_delay_ms: int = 1000
var _successful_queries: int = 0


# ------------------------------------------------------------------
# Node references and health state
# ------------------------------------------------------------------
var _db: Node = null
var _is_healthy: bool = false




func _ready() -> void:
	print("[VERBATIM] DatabaseGuard.gd _ready() called")
	_db = get_node_or_null("/root/SqliteDb")
	if _db:
		_check_db_health()
	else:
		_is_healthy = false
		_last_error = "SqliteDb not found"
		print("[VERBATIM] DatabaseGuard: SqliteDb not found, will retry")
		_schedule_retry()
	print("[VERBATIM] DatabaseGuard: _ready ok=true")


func _exit_tree() -> void:
	print("[VERBATIM] DatabaseGuard: _exit_tree called")
	_db = null


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------


func execute_query(sql: String, args: Array = []) -> Array:
	_total_queries += 1
	if _circuit_state == "OPEN":
		if Time.get_ticks_msec() - _circuit_last_failure > _circuit_timeout_ms:
			_circuit_state = "HALF_OPEN"
			print("[VERBATIM] DatabaseGuard: circuit HALF_OPEN - testing")
		else:
			print("[VERBATIM] DatabaseGuard: circuit OPEN - rejecting query")
			return []
	if not _ensure_db_ready():
		return []
	var attempt := 0
	var max_attempts := 3
	while attempt < max_attempts:
		var result = _execute_with_retry(sql, args)
		if result != null:
			_record_success()
			return result
		attempt += 1
		if attempt < max_attempts:
			print("[VERBATIM] DatabaseGuard: query failed, retry %d/%d" % [attempt, max_attempts])
			OS.delay_msec(_retry_delay_ms * attempt)
	_record_failure(sql)
	return []


func execute_write(sql: String, args: Array = []) -> bool:
	var result := execute_query(sql, args)
	return result != null and result.size() > 0


func is_healthy() -> bool:
	_check_db_health()
	return _is_healthy and _circuit_state != "OPEN"


func get_health_report() -> Dictionary:
	return {
		"_is_healthy": _is_healthy,
		"circuit_state": _circuit_state,
		"failure_count": _failure_count,
		"recovery_attempts": _recovery_attempts,
		"connection_retries": _connection_retries,
		"last_error": _last_error,
		"total_queries": _total_queries,
		"successful_queries": _successful_queries,
		"success_rate": float(_successful_queries) / float(max(1, _total_queries)) * 100.0,
	}


func reset_circuit() -> void:
	_circuit_state = "CLOSED"
	_failure_count = 0
	print("[VERBATIM] DatabaseGuard: circuit manually reset")


# ------------------------------------------------------------------
# Core operations
# ------------------------------------------------------------------


func _ensure_db_ready() -> bool:
	if not _db:
		_db = get_node_or_null("/root/SqliteDb")
		if not _db:
			_last_error = "SqliteDb not available"
			return false
	_check_db_health()
	if not _is_healthy:
		_attempt_recovery()
		return _is_healthy
	return true


func _check_db_health() -> void:
	if not _db:
		_is_healthy = false
		return
	if not _db.has_method("_query"):
		_is_healthy = false
		_last_error = "SqliteDb._query method not found"
		return
	var result = _db._query("SELECT 1")
	if result != null and result.size() > 0:
		_is_healthy = true
		_last_error = ""
		if _circuit_state == "OPEN" or _circuit_state == "HALF_OPEN":
			_circuit_state = "CLOSED"
			emit_signal("db_recovered")
	else:
		_is_healthy = false
		_last_error = "Health check failed"


func _attempt_recovery() -> void:
	if _recovery_attempts >= _max_recovery_attempts:
		print("[VERBATIM] DatabaseGuard: max recovery attempts reached")
		return
	_recovery_attempts += 1
	print(
		(
			"[VERBATIM] DatabaseGuard: recovery attempt %d/%d"
			% [_recovery_attempts, _max_recovery_attempts]
		)
	)
	_db = null
	OS.delay_msec(500)
	_db = get_node_or_null("/root/SqliteDb")
	if _db:
		_check_db_health()
		if _is_healthy:
			emit_signal("db_recovered")
			print("[VERBATIM] DatabaseGuard: recovery SUCCESS")
			return
	_schedule_retry()


func _schedule_retry() -> void:
	var delay = min(_retry_delay_ms * pow(2, _connection_retries), 30_000)
	_connection_retries += 1
	var timer := Timer.new()
	timer.wait_time = delay / 1000.0
	timer.one_shot = true
	timer.timeout.connect(_on_retry_timer_timeout)
	add_child(timer)
	timer.start()
	print("[VERBATIM] DatabaseGuard: retry scheduled in %d ms" % delay)


func _on_retry_timer_timeout() -> void:
	_check_db_health()
	if not _is_healthy:
		_attempt_recovery()


func _execute_with_retry(sql: String, args: Array):
	if not _db or not _db.has_method("_query"):
		return null
	var result = _db._query(sql, args)
	if result != null:
		return result
	else:
		return null


func _record_success() -> void:
	_successful_queries += 1
	_failure_count = max(0, _failure_count - 1)
	if _circuit_state == "HALF_OPEN":
		_circuit_state = "CLOSED"
		emit_signal("db_recovered")
		print("[VERBATIM] DatabaseGuard: circuit CLOSED")


func _record_failure(sql: String) -> void:
	_failure_count += 1
	_circuit_last_failure = Time.get_ticks_msec()
	if _failure_count >= _failure_threshold and _circuit_state == "CLOSED":
		_circuit_state = "OPEN"
		emit_signal("db_unhealthy", "Circuit breaker OPEN after %d failures" % _failure_count)
		print("[VERBATIM] DatabaseGuard: circuit OPEN")


# ------------------------------------------------------------------
# Maintenance
# ------------------------------------------------------------------


func vacuum_db() -> bool:
	if not _ensure_db_ready():
		return false
	var result := execute_query("VACUUM")
	return result != null


func compact_db() -> bool:
	return vacuum_db()


func checkpoint_db() -> bool:
	if not _ensure_db_ready():
		return false
	var result := execute_query("PRAGMA wal_checkpoint(TRUNCATE)")
	return result != null
