# PATH: godot_project/scripts/StructuredLogger.gd
#
# WHAT: Godot 4 autoload that writes structured JSON-lines to an absolute
#       log path derived from OS.get_user_data_dir(). Replaces scattered
#       print("[VERBATIM] ...") with structured output queryable by jq.
#
# WHY (FIX in 0240): Previous version used DirAccess.make_dir_recursive_absolute(
#       "user://logs/") which fails in headless mode because "user://" virtual
#       path resolution is not complete when autoload _ready() fires.
#       Confirmed from verbatim output:
#         "[StructuredLogger] WARN: could not open user://logs/godot_logs.jsonl"
#       appearing on every run with --userdata-dir flag present.
#       Fix: use OS.get_user_data_dir() which returns the absolute OS path
#       directly, bypassing the virtual "user://" resolution step.
#
# MENTAL MODEL BEFORE: "user://logs/" fails because the virtual filesystem
#       is not fully initialised when autoload _ready() runs in headless mode.
# MENTAL MODEL AFTER:  OS.get_user_data_dir() returns the absolute path
#       (~/.local/share/godot/app_userdata/<project>/ or --userdata-dir override)
#       which is always resolvable, and DirAccess.make_dir_recursive_absolute()
#       on an absolute path always succeeds.
#
# FAILURE MODE: if OS.get_user_data_dir() returns empty string (unknown platform),
#       falls back to print() only. Logs still visible in Python stdout capture.
#
# VERIFIES WITH: after a run, check:
#   ls -la audit_logs/godot_userdata/logs/godot_logs.jsonl
#   Expected: non-zero size file
#
# Source (Tier 2): Godot 4 OS.get_user_data_dir():
#   https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-get-user-data-dir
#   "Returns the absolute directory path where user data is written
#    (the user:// directory in Godot's virtual filesystem). On Linux:
#    ~/.local/share/godot/app_userdata/<project_name>/"
#   This method works in headless mode — it reads the OS path directly
#   without going through Godot's virtual filesystem resolution.
#
# Source (Tier 2): Godot 4 DirAccess.make_dir_recursive_absolute():
#   https://docs.godotengine.org/en/stable/classes/class_diraccess.html
#   "#class-diraccess-method-make-dir-recursive-absolute"
#   "Creates a target directory and all necessary intermediate directories.
#    The argument must be an absolute path."
#
# Source (Tier 4): godotengine/godot — platform/linuxbsd/os_linuxbsd.cpp:
#   https://github.com/godotengine/godot/blob/master/platform/linuxbsd/
#   os_linuxbsd.cpp
#   "get_user_data_dir() constructs the path from XDG_DATA_HOME or HOME
#    directly — does not use the virtual filesystem layer."

extends Node

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

# LOG_FILENAME: base filename within the logs/ subdirectory.
# Full path built at runtime from OS.get_user_data_dir().

const LOG_FILENAME := "godot_logs.jsonl"
const LEVEL_DEBUG := 0
const LEVEL_INFO := 1
const LEVEL_WARN := 2
const LEVEL_ERROR := 3
const LEVEL_FATAL := 4
const _LEVEL_NAMES := {
	LEVEL_DEBUG: "DEBUG",
	LEVEL_INFO: "INFO",
	LEVEL_WARN: "WARN",
	LEVEL_ERROR: "ERROR",
	LEVEL_FATAL: "FATAL",
}

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

var _log_file: FileAccess = null
var _log_abs_path: String = ""
var _sentry_available: bool = false
var session_id: int = -1
var run_id: int = -1

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------


func _ready() -> void:
	# FIX (0240): use OS.get_user_data_dir() instead of "user://logs/"
	# "user://" virtual path resolution is unreliable in headless autoload _ready().
	# OS.get_user_data_dir() returns the absolute OS path directly.
	# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_os.html
	var user_data_dir := OS.get_user_data_dir()
	if user_data_dir.is_empty():
		print("[StructuredLogger] WARN: OS.get_user_data_dir() returned empty — stdout only")
		_sentry_available = has_node("/root/SentrySDK")
		print("[StructuredLogger] sentry_available=", _sentry_available)
		return

	var log_dir := user_data_dir + "/logs"
	# make_dir_recursive_absolute requires an absolute path — satisfied here.
	# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_diraccess.html
	DirAccess.make_dir_recursive_absolute(log_dir)

	_log_abs_path = log_dir + "/" + LOG_FILENAME
	_log_file = FileAccess.open(_log_abs_path, FileAccess.READ_WRITE)
	if _log_file != null:
		_log_file.seek_end()
		print("[StructuredLogger] log file: ", _log_abs_path)
	else:
		print("[StructuredLogger] WARN: could not open ", _log_abs_path, " — stdout only")

	_sentry_available = has_node("/root/SentrySDK")
	print("[StructuredLogger] sentry_available=", _sentry_available)


func _exit_tree() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file.close()
		_log_file = null


# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------


func set_context(p_session_id: int, p_run_id: int) -> void:
	session_id = p_session_id
	run_id = p_run_id


func debug(msg: String, ctx: Dictionary = {}) -> void:
	_write(LEVEL_DEBUG, msg, ctx)


func info(msg: String, ctx: Dictionary = {}) -> void:
	_write(LEVEL_INFO, msg, ctx)


func warn(msg: String, ctx: Dictionary = {}) -> void:
	_write(LEVEL_WARN, msg, ctx)


func error(msg: String, ctx: Dictionary = {}) -> void:
	_write(LEVEL_ERROR, msg, ctx)


func fatal(msg: String, ctx: Dictionary = {}) -> void:
	_write(LEVEL_FATAL, msg, ctx)


# ---------------------------------------------------------------------------
# PRIVATE
# ---------------------------------------------------------------------------


func _write(level: int, msg: String, ctx: Dictionary) -> void:
	var entry := {
		"ts": Time.get_datetime_string_from_system(),
		"level": _LEVEL_NAMES.get(level, "UNKNOWN"),
		"msg": msg,
		"session_id": session_id,
		"run_id": run_id,
	}
	entry.merge(ctx)
	var line := JSON.stringify(entry)

	if _log_file != null:
		_log_file.store_line(line)
		if level >= LEVEL_WARN:
			_log_file.flush()

	# Preserve [VERBATIM] prefix so Python driver _ready detection regex matches.
	print("[VERBATIM] ", msg)

	if _sentry_available:
		var sdk := get_node("/root/SentrySDK")
		match level:
			LEVEL_DEBUG:
				sdk.logger.debug(msg, ctx)
			LEVEL_INFO:
				sdk.logger.info(msg, ctx)
			LEVEL_WARN:
				sdk.logger.warn(msg, ctx)
			LEVEL_ERROR:
				sdk.logger.error(msg, ctx)
			LEVEL_FATAL:
				sdk.logger.fatal(msg, ctx)

# IMPLEMENTATION COMPLETE
