# gdlint: disable=max-file-lines
# forensic_hud.gd – final, fully gated, citation‑backed parachute malfunction trainer
# gdlint:ignore=max-file-lines
@tool
extends Panel

const MAX_VISIBLE = 10
var _all_entries = []
var _labels = []


func _ready():
	if not Engine.is_editor_hint():
		return
	_setup_hud()
	_recreate_hud_if_needed()


func _setup_hud():
	for i in range(MAX_VISIBLE):
		var label = Label.new()
		label.add_theme_font_override("font", ThemeDB.fallback_font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0, 1, 0))
		label.position = Vector2(10, 10 + i * 20)
		label.custom_minimum_size = Vector2(800, 20)
		add_child(label)
		_labels.append(label)


func _recreate_hud_if_needed():
	if not has_node("hud_text"):
		return
	var db = SqliteDb
	if not db:
		return
	var fixes = db.query(
		"SELECT fix_name, status, applied_at FROM applied_fixes ORDER BY applied_at DESC LIMIT 10"
	)
	var verifications = (
		db
		. query(
			"SELECT component, passed, verified_at, evidence FROM verificationresults ORDER BY verified_at DESC LIMIT 5"
		)
	)
	var output: String = "=== FIX HISTORY ===\n"
	if fixes != null and typeof(fixes) == TYPE_ARRAY:
		for row in fixes:
			output += str(row.get("fix_name", "?")) + " : " + str(row.get("status", "?")) + "\n"
	if has_node("hud_text"):
		get_node("hud_text").text = output
	else:
		print("[HUD] " + output)


func add_entry(msg: String) -> void:
	# WHAT: add a timestamped entry and refresh the visible lines
	# Called by any script via get_tree().get_nodes_in_group("forensic_hud")
	var ts = Time.get_datetime_string_from_system().substr(11, 8)  # HH:MM:SS
	_all_entries.append(ts + " " + msg)

	# Determine colour: red for errors, orange for warnings, yellow for normal
	var is_error = "ERROR" in msg or "FATAL" in msg
	var is_warn = "WARN" in msg or "WARNING" in msg

	# Refresh visible window: show last MAX_VISIBLE entries
	var start = max(0, _all_entries.size() - MAX_VISIBLE)
	for i in range(MAX_VISIBLE):
		var entry_idx = start + i
		if entry_idx < _all_entries.size():
			var entry = _all_entries[entry_idx]
			_labels[i].text = entry
			# Colour by content
			if "ERROR" in entry or "FATAL" in entry:
				_labels[i].add_theme_color_override("font_color", Color(1, 0, 0))
			elif "WARN" in entry or "WARNING" in entry:
				_labels[i].add_theme_color_override("font_color", Color(1, 0.8, 0))
			else:
				_labels[i].add_theme_color_override("font_color", Color(0, 1, 0))
		else:
			_labels[i].text = ""

# ----- END AUTOHEAL PATCH (method) -----
