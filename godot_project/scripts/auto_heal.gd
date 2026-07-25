extends Node

# Singleton to automatically heal indentation errors using the database.
# Relies on godot-sqlite plugin (https://github.com/2shady4u/godot-sqlite)

const DB_PATH := "res://parachute_mutations.db"
const TARGET_FILE := "res://godot_project/scripts/build_terrain.gd"

var db: SQLite

func _ready() -> void:
	# Run the fix automatically when the node is ready (e.g., on game start)
	apply_indentation_fix()

func apply_indentation_fix() -> void:
	if not _ensure_db():
		return

	# 1. Query repair_rules for a fix matching the error signature
	var error_signature := "indentation mismatch: tabs vs spaces"
	var query = """
		SELECT strategy_name, pattern_old, pattern_new
		FROM repair_rules
		WHERE error_class LIKE ?
		ORDER BY wins DESC
		LIMIT 1
	"""
	var result = db.query_with_bindings(query, ["%" + error_signature + "%"])

	var fix_applied := false
	if result and result.size() > 0:
		var rule = result[0]
		apply_rule(rule["pattern_old"], rule["pattern_new"])
		log_autoheal("repair_rules", rule["strategy_name"], true)
		fix_applied = true
	else:
		# Fallback: convert leading spaces to tabs
		convert_spaces_to_tabs()
		log_autoheal("fallback", "generic_spaces_to_tabs", true)
		fix_applied = true

	# Also ensure Q/E turn checks are present
	ensure_qe_turn_checks()

	db.close_db()
	print("[AutoHeal] Indentation fix applied." if fix_applied else "[AutoHeal] No fix needed.")

func _ensure_db() -> bool:
	if not FileAccess.file_exists(DB_PATH):
		push_error("Database not found at ", DB_PATH)
		return false

	db = SQLite.new()
	db.path = DB_PATH
	db.open_db()
	if not db.is_open():
		push_error("Failed to open database.")
		return false
	return true

func apply_rule(pattern_old: String, pattern_new: String) -> void:
	var file = FileAccess.open(TARGET_FILE, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	# Use regex substitution (simple; for more complex patterns, use RegEx class)
	var regex = RegEx.new()
	regex.compile(pattern_old)
	var new_content = regex.sub(content, pattern_new, true)

	# Write back
	file = FileAccess.open(TARGET_FILE, FileAccess.WRITE)
	file.store_string(new_content)
	file.close()

func convert_spaces_to_tabs() -> void:
	var file = FileAccess.open(TARGET_FILE, FileAccess.READ)
	var lines = file.get_as_text().split("\n")
	file.close()

	for i in range(lines.size()):
		var line = lines[i]
		while line.begins_with("    "):
			line = "\t" + line.substr(4)
		lines[i] = line

	var new_content = "\n".join(lines)
	file = FileAccess.open(TARGET_FILE, FileAccess.WRITE)
	file.store_string(new_content)
	file.close()

func ensure_qe_turn_checks() -> void:
	# If the Q/E block is already present, skip.
	var file = FileAccess.open(TARGET_FILE, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	if content.find("# --- Q/E turn input") != -1:
		return  # already there

	# Find func _physics_process(delta): and insert after it
	var regex = RegEx.new()
	regex.compile("(func _physics_process\\([^)]*\\):)\\s*")
	var result = regex.search(content)
	if not result:
		return

	var indent := "\t"  # assume tabs; could be inferred from file
	var block = """
{indent}# --- Q/E turn input (checked first so it's available for all states) ---
{indent}if Input.is_key_pressed(KEY_Q):
{indent}\t_turn_input = -1.0
{indent}elif Input.is_key_pressed(KEY_E):
{indent}\t_turn_input = 1.0
{indent}else:
{indent}\t_turn_input = 0.0
""".format({"indent": indent})

	var insert_pos = result.get_end()
	var new_content = content.insert(insert_pos, block)

	file = FileAccess.open(TARGET_FILE, FileAccess.WRITE)
	file.store_string(new_content)
	file.close()

func log_autoheal(source: String, action: String, success: bool) -> void:
	if not db.is_open():
		return
	var query = """
		INSERT INTO autohealactions
		(run_id, iteration, file_path, tool_used, success, timestamp, raw_output)
		VALUES (?, ?, ?, ?, ?, datetime('now'), ?)
	"""
	db.query_with_bindings(query, [
		"autoheal_script", 1, TARGET_FILE,
		"godot-sqlite", success,
		"Source: %s, Action: %s" % [source, action]
	])
