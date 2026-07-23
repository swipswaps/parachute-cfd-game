# PATH: godot_project/scripts/SqliteDb.gd
# Safe version – prints info, never errors.
extends Node


class ScreenshotLibrary:
	pass

var _db = null
var _db_ok = null

const DB_PATH := "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/parachute_mutations.db"

var db = null


func _ready() -> void:
	print("[VERBATIM] SqliteDb.gd _ready() called")
	print("[VERBATIM] SqliteDb.gd _ready() called")
	print("[VERBATIM] SqliteDb.gd _ready() called")
	print("[VERBATIM] SqliteDb: _ready started")
	if not ClassDB.class_exists("SQLite"):
		print("[VERBATIM] SqliteDb: SQLite extension not loaded; continuing without database.")
		return
	_db = ClassDB.instantiate("SQLite")
	if not _db:
		print("[VERBATIM] SqliteDb: failed to instantiate SQLite.")
		return
	_db.path = DB_PATH
	_db.verbosity_level = 0
	if not _db.open_db():
		print("[VERBATIM] SqliteDb: open_db() failed for " + DB_PATH)
		return
	_db_ok = true
	print("[VERBATIM] DB OPEN OK ", DB_PATH)
	_create_tables()
	print("[VERBATIM] SqliteDb: _ready completed")


func _exit_tree() -> void:
	if _db_ok and _db:
		_db.close_db()
	print("[VERBATIM] DB CLOSED")


func _query(sql: String, args: Array = []) -> Array:
	if not _db_ok or not _db:
		print("[VERBATIM] DB NOT AVAILABLE – skipping: ", sql.left(60))
		return []
	if not _db.query_with_bindings(sql, args):
		print("[VERBATIM] DB QUERY FAIL: " + sql.left(80))
		return []
	return _db.query_result


func _create_tables() -> void:
	_query(
		"CREATE TABLE IF NOT EXISTS issues (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL DEFAULT (datetime('now')), symptom TEXT NOT NULL, root_cause TEXT NOT NULL, fix_applied TEXT NOT NULL, verified INTEGER NOT NULL DEFAULT 0)"
	)
	_query(
		"CREATE TABLE IF NOT EXISTS screenshots (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL DEFAULT (datetime('now')), filename TEXT NOT NULL UNIQUE, path TEXT NOT NULL)"
	)
	_query(
		"CREATE TABLE IF NOT EXISTS parse_errors (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL DEFAULT (datetime('now')), script TEXT NOT NULL, error_text TEXT NOT NULL, fix_script TEXT NOT NULL, fix_result TEXT NOT NULL DEFAULT 'pending')"
	)
	print("[VERBATIM] DB tables ensured")


func insert_issue(symptom: String, root_cause: String, fix_applied: String, verified: int = 0) -> void:
	_query(
		"INSERT INTO issues (symptom, root_cause, fix_applied, verified) VALUES (?,?,?,?)",
		[symptom, root_cause, fix_applied, verified]
	)
	print("[VERBATIM] DB issue logged: ", symptom.left(60))


func get_issues(only_open: bool = false) -> Array:
	if only_open:
		return _query("SELECT * FROM issues WHERE verified=0 ORDER BY id DESC")
	return _query("SELECT * FROM issues ORDER BY id DESC")


func mark_verified(id: int) -> void:
	_query("UPDATE issues SET verified=1 WHERE id=?", [id])
	print("[VERBATIM] DB issue ", id, " marked verified")


func insert_screenshot(filename: String, path: String) -> void:
	_query("INSERT OR REPLACE INTO screenshots (filename, path) VALUES (?,?)", [filename, path])
	print("[VERBATIM] DB screenshot logged: ", filename)


func get_screenshots() -> Array:
	return _query("SELECT * FROM screenshots ORDER BY id DESC")


func log_parse_error(
	script: String, error_text: String, fix_script: String, fix_result: String = "pending"
):
	_query(
		"INSERT INTO parse_errors (script, error_text, fix_script, fix_result) VALUES (?,?,?,?)",
		[script, error_text, fix_script, fix_result]
	)
	print("[VERBATIM] DB parse_error logged for: ", script)


func get_parse_errors(only_pending: bool = false) -> Array:
	if only_pending:
		return _query("SELECT * FROM parse_errors WHERE fix_result='pending' ORDER BY id DESC")
	return _query("SELECT * FROM parse_errors ORDER BY id DESC")


func mark_parse_error_fixed(id: int) -> void:
	_query("UPDATE parse_errors SET fix_result='fixed' WHERE id=?", [id])
	print("[VERBATIM] DB parse_error ", id, " marked fixed")

# IMPLEMENTATION COMPLETE
