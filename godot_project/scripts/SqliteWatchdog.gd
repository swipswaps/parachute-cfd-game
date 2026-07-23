extends Node
# PATH: godot_project/scripts/SqliteWatchdog.gd
# Safe version – skips if SqliteDb not available.:


func _ready() -> void:
	print("[VERBATIM] SqliteWatchdog.gd _ready() called")
	print("[VERBATIM] SqliteWatchdog.gd _ready() called")
	print("[VERBATIM] SqliteWatchdog.gd _ready() called")
	print("[VERBATIM] Watchdog: _ready started")
	if not has_node("/root/SqliteDb"):
		print("[VERBATIM] Watchdog: SqliteDb not available; skipping scan.")
		return
	var sqlite := get_node("/root/SqliteDb")
	if not sqlite._db_ok:
		print("[VERBATIM] Watchdog: SqliteDb not ready; skipping scan.")
		return
	print("[VERBATIM] Watchdog: started, polling user://screenshots/")
	print("[VERBATIM] Watchdog: scan disabled — single-launch screenshot mode")
	print("[VERBATIM] Watchdog: _ready completed")


class ScreenshotLibrary:
	static func save_flight_screenshot():
		pass
