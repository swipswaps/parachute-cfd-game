# PATH: scripts/forensic_hud.gd
#
# WHAT: Persistent on-screen log that captures every _log() call from every
#       script in the game. Displays last 18 lines on screen at all times.
#       Errors (containing ERROR/FATAL/WARNING) shown in red, others in yellow.
#       Does NOT clear — accumulates the full session history in memory.
#
# HOW TO ADD TO GAME: In build_terrain.gd _ready(), after HUD is created:
#   var forensic = load("res://scripts/forensic_hud.gd").new()
#   add_child(forensic)
#
# HOW IT RECEIVES MESSAGES: any script that calls
#   get_tree().get_nodes_in_group("forensic_hud")
#   node.add_entry(msg)
# will appear here. parachute_controller.gd already does this.
#
# Source (Tier 2 — Godot 4 CanvasLayer):
#   https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html
# Source (Tier 2 — Godot 4 SceneTree.get_nodes_in_group):
#   https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-get-nodes-in-group

extends CanvasLayer

const MAX_VISIBLE := 18
const PANEL_WIDTH := 780
const LINE_HEIGHT := 17

var _all_entries: Array[String] = []
var _labels: Array[Label] = []
var _bg: ColorRect


func _ready() -> void:
	# CanvasLayer at layer 10 — above HUD (layer 1) but below loading screen (128)
	layer = 10
	add_to_group("forensic_hud")

	# Dark semi-transparent background for readability
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.7)
	_bg.size = Vector2(PANEL_WIDTH, MAX_VISIBLE * LINE_HEIGHT + 6)
	_bg.position = Vector2(4, 240)
	add_child(_bg)

	# Pre-create label pool — one label per visible line
	# Source: https://docs.godotengine.org/en/stable/classes/class_label.html
	var font = ThemeDB.fallback_font
	for i in range(MAX_VISIBLE):
		var lbl = Label.new()
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(1, 0.85, 0))
		lbl.position = Vector2(6, 243 + i * LINE_HEIGHT)
		lbl.custom_minimum_size = Vector2(PANEL_WIDTH - 8, LINE_HEIGHT)
		lbl.clip_text = true
		lbl.text = ""
		add_child(lbl)
		_labels.append(lbl)

	add_entry("ForensicHUD ready — capturing all _log() calls")


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
			var entry_is_error = "ERROR" in entry or "FATAL" in entry
			var entry_is_warn = "WARN" in entry or "WARNING" in entry
			if entry_is_error:
				_labels[i].add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			elif entry_is_warn:
				_labels[i].add_theme_color_override("font_color", Color(1, 0.6, 0.1))
			else:
				_labels[i].add_theme_color_override("font_color", Color(1, 0.85, 0))
		else:
			_labels[i].text = ""


func get_full_log() -> String:
	# Returns all entries as a single newline-separated string for export
	return "\n".join(_all_entries)

# IMPLEMENTATION COMPLETE
