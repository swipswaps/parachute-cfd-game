extends Node
# ==========================================================================
# forensic_hud.gd  (autoload as ForensicHUD)
#
# In-game overlay for the forensic HUB. Both this HUD and the browser view
# are HTTP clients of the same forensic hub server; single source of truth.
#
# ARCHITECTURE (do not "simplify" -- each choice fixes a prior real bug):
#   * extends Node, NOT CanvasLayer: get_global_mouse_position() is defined
#     on CanvasItem, not CanvasLayer (prior gdparse failure).
#   * extends Node, NOT Control: the visible panel lives inside a
#     CanvasLayer child, and CanvasLayer ignores its parent's canvas
#     transform -- dragging the root's global_position moves NOTHING on
#     screen. Drag must move _panel.position directly.
#   * Drag uses a rect hit-test on _panel with event.position (viewport
#     coords == CanvasLayer coords, since _layer has no transform).
#     Without the hit-test, every left-click in the game would be
#     swallowed by set_input_as_handled(), breaking the PiP drag too.
#   * F3 toggles _layer.visible (toggling the root's visibility does not
#     hide CanvasLayer children).
#   * No per-mouse-event print() calls: those flooded the log and
#     triggered autostall.py [STALL SOURCE] warnings previously.
#
# Controls: F3 toggles the panel. Left-click + drag anywhere on the panel
# to move it. Position persists to user://forensic_hud.cfg. Each citation
# card has a [+]/[-] toggle; URL rows open via OS.shell_open.
# ==========================================================================

const DEFAULT_HUB_URL := "http://127.0.0.1:8765"
const STATS_PATH      := "/api/gamification"
const LEADER_PATH     := "/api/leaderboard"
const CITE_PATH       := "/api/citations"
const INTEG_PATH      := "/api/integrity"
const POLL_FAST_SEC   := 2.0
const POLL_SLOW_SEC   := 10.0
const PANEL_START_POS := Vector2(24, 24)
const PANEL_MIN_SIZE  := Vector2(360, 480)
const POS_CFG_PATH    := "user://forensic_hud.cfg"

var _hub_url: String = ""
var _layer: CanvasLayer
var _panel: PanelContainer
var _vbox: VBoxContainer

var _title_label: Label
var _url_label: Label
var _status_label: Label
var _gam_label: Label
var _leader_vbox: VBoxContainer
var _cite_vbox: VBoxContainer
var _time_label: Label

var _stats_req: HTTPRequest
var _leader_req: HTTPRequest
var _cite_req: HTTPRequest
var _integ_req: HTTPRequest
var _fast_timer: Timer
var _slow_timer: Timer

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _citations_loaded: bool = false
var _card_expanded: Dictionary = {}

func _resolve_hub_url() -> String:
	var key := "application/forensic_hub/url"
	if ProjectSettings.has_setting(key):
		var v = ProjectSettings.get_setting(key)
		if typeof(v) == TYPE_STRING and String(v) != "":
			return String(v)
	var env := OS.get_environment("FORENSIC_HUB_URL")
	if env != "":
		return env
	return DEFAULT_HUB_URL

func _mklabel(txt: String, color := Color(0.9, 0.95, 0.9, 1.0)) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", color)
	return l

func _mkbutton(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	return b

func _panel_rect() -> Rect2:
	var sz := _panel.size
	if sz == Vector2.ZERO:
		sz = PANEL_MIN_SIZE
	return Rect2(_panel.position, sz)

func _input(event: InputEvent) -> void:
	print("[FHUD DEBUG] _input called with event: %s" % event)
	
	print("[HUD_DIAG] _input called")
# F3 toggle – safe with null check
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			if _layer != null:
				_layer.visible = not _layer.visible
			get_viewport().set_input_as_handled()
		return
	# Do not process mouse events if panel is hidden
	if _layer == null or not _layer.visible or _panel == null:
		return
	# Delegate mouse events to _gui_input (which handles dragging)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_gui_input(event)
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.position = _load_saved_position()
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.90)
	sb.border_color = Color(0.35, 0.85, 0.35, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(_vbox)

	_title_label = _mklabel("FORENSIC HUB", Color(0.55, 1.0, 0.55, 1.0))
	_vbox.add_child(_title_label)
	_url_label = _mklabel("hub: " + _hub_url, Color(0.65, 0.85, 0.65, 1.0))
	_vbox.add_child(_url_label)
	_vbox.add_child(HSeparator.new())

	_status_label = _mklabel("status: (starting)")
	_vbox.add_child(_status_label)
	_gam_label = _mklabel("Level - / XP - / Streak -")
	_gam_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_gam_label)

	_vbox.add_child(HSeparator.new())
	_vbox.add_child(_mklabel("Top strategies (UCB1)"))
	_leader_vbox = VBoxContainer.new()
	_vbox.add_child(_leader_vbox)

	_vbox.add_child(HSeparator.new())
	_vbox.add_child(_mklabel("Citations"))
	_cite_vbox = VBoxContainer.new()
	_vbox.add_child(_cite_vbox)

	_vbox.add_child(HSeparator.new())
	_time_label = _mklabel("t: --:--:--", Color(0.6, 0.75, 0.6, 1.0))
	_vbox.add_child(_time_label)

func _load_saved_position() -> Vector2:
	var config := ConfigFile.new()
	if config.load(POS_CFG_PATH) == OK:
		var saved_pos = config.get_value("position", "panel", PANEL_START_POS)
		if typeof(saved_pos) == TYPE_VECTOR2:
			return saved_pos
	return PANEL_START_POS

func _save_position() -> void:
	if _panel == null:
		return
	var config := ConfigFile.new()
	config.set_value("position", "panel", _panel.position)
	config.save(POS_CFG_PATH)

func _exit_tree() -> void:
	_save_position()

func _ready() -> void:
	# set_as_top_level(true)  # REMOVED: Godot 3 API, not available in Godot 4. HUD is already on CanvasLayer (layer=1) which provides equivalent isolation. Ref: https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html
	
	print("[HUD_DIAG] _ready called")
	_hub_url = _resolve_hub_url()
	_build_ui()

	for child in get_tree().get_nodes_in_group("forensic_text"):
		if child is RichTextLabel:
			child.selection_enabled = true

	_stats_req = HTTPRequest.new()
	_leader_req = HTTPRequest.new()
	_cite_req = HTTPRequest.new()
	_integ_req = HTTPRequest.new()
	add_child(_stats_req)
	add_child(_leader_req)
	add_child(_cite_req)
	add_child(_integ_req)
	_stats_req.request_completed.connect(_on_stats_completed)
	_leader_req.request_completed.connect(_on_leader_completed)
	_cite_req.request_completed.connect(_on_cite_completed)
	_integ_req.request_completed.connect(_on_integ_completed)

	_fast_timer = Timer.new()
	_fast_timer.wait_time = POLL_FAST_SEC
	_fast_timer.autostart = true
	_fast_timer.timeout.connect(_poll_fast)
	add_child(_fast_timer)

	_slow_timer = Timer.new()
	_slow_timer.wait_time = POLL_SLOW_SEC
	_slow_timer.autostart = true
	_slow_timer.timeout.connect(_poll_slow)
	add_child(_slow_timer)

	_poll_fast()
	_poll_slow()

func _poll_fast() -> void:
	var err_a := _stats_req.request(_hub_url + STATS_PATH)
	if err_a != OK:
		_status_label.text = "hub request err: %d (%s)" % [err_a, _hub_url + STATS_PATH]
	var err_b := _leader_req.request(_hub_url + LEADER_PATH)
	if err_b != OK:
		_status_label.text = "leader err: %d" % err_b

func _poll_slow() -> void:
	if not _citations_loaded:
		var err_c := _cite_req.request(_hub_url + CITE_PATH)
		if err_c != OK:
			_status_label.text = "cite err: %d" % err_c
	var err_i := _integ_req.request(_hub_url + INTEG_PATH)
	if err_i != OK:
		_status_label.text = "integ err: %d" % err_i

func _on_stats_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_time_label.text = "t: " + Time.get_time_string_from_system()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_status_label.text = "hub offline (%s) result=%d code=%d" % [_hub_url, result, response_code]
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_status_label.text = "hub /api/stats: non-dict payload"
		return
	var d: Dictionary = parsed
	if d.has("db_unavailable") and d["db_unavailable"]:
		_status_label.text = "hub OK, DB unavailable"
		_gam_label.text = "(no pipeline DB found)"
		return
	_status_label.text = "hub OK  (%s)" % _hub_url
	var lv = d.get("level", "-")
	var xp = d.get("xp", "-")
	var st = d.get("streak", "-")
	var sr = d.get("success_rate", 0.0)
	var caught = d.get("pokedex_caught", "-")
	var known = d.get("pokedex_known", "-")
	var unresolved = d.get("unresolved_parse_errors", "-")
	var ach = d.get("achievements", [])
	var ach_lines := "achievements:"
	if typeof(ach) == TYPE_ARRAY:
		for a in ach:
			ach_lines += "\n  * " + str(a)
	_gam_label.text = ("Level %s   XP %s   Streak %s\n"
		+ "success rate: %s\n"
		+ "pokedex: %s / %s trained\n"
		+ "unresolved parse errors: %s\n"
		+ ach_lines) % [str(lv), str(xp), str(st), str(sr), str(caught), str(known), str(unresolved)]

func _on_leader_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		return
	for c in _leader_vbox.get_children():
		c.queue_free()
	var rows: Array = parsed
	if rows.is_empty():
		_leader_vbox.add_child(_mklabel("  (no strategies yet)"))
		return
	var shown := 0
	for row in rows:
		if shown >= 6:
			break
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		var txt := "  %s [%s] wins=%s/%s wr=%s ucb1=%s" % [
			str(r.get("name", "?")),
			str(r.get("error_class", "?")),
			str(r.get("wins", 0)),
			str(r.get("trials", 0)),
			str(r.get("win_rate", 0)),
			str(r.get("ucb1", 0)),
		]
		_leader_vbox.add_child(_mklabel(txt))
		shown += 1

func _on_cite_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var all_cites: Array = []
	if d.has("principles") and typeof(d["principles"]) == TYPE_ARRAY:
		all_cites += d["principles"]
	if d.has("godot_docs") and typeof(d["godot_docs"]) == TYPE_ARRAY:
		all_cites += d["godot_docs"]
	if all_cites.is_empty():
		return
	_citations_loaded = true
	for c in _cite_vbox.get_children():
		c.queue_free()
	for cite in all_cites:
		if typeof(cite) != TYPE_DICTIONARY:
			continue
		_add_citation_card(cite as Dictionary)

func _on_integ_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.has("quick_check"):
		var qc := str(d["quick_check"])
		var color := Color(0.55, 1.0, 0.55, 1.0) if qc == "ok" else Color(1.0, 0.5, 0.5, 1.0)
		_status_label.add_theme_color_override("font_color", color)

func _add_citation_card(cite: Dictionary) -> void:
	var cid := str(cite.get("id", "?"))
	var label := str(cite.get("label", "(unlabeled)"))
	var url := str(cite.get("url", ""))
	var verbatim := str(cite.get("verbatim", ""))
	var applies := str(cite.get("applies_to", ""))
	var header_row := HBoxContainer.new()
	var toggle := _mkbutton("+")
	toggle.custom_minimum_size = Vector2(22, 22)
	header_row.add_child(toggle)
	header_row.add_child(_mklabel(" [%s] %s" % [cid, label], Color(0.85, 0.95, 0.85, 1.0)))
	_cite_vbox.add_child(header_row)

	var body_box := VBoxContainer.new()
	body_box.visible = _card_expanded.get(cid, false)
	var quote_label := _mklabel("  \"" + verbatim + "\"", Color(0.85, 0.85, 0.85, 1.0))
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_box.add_child(quote_label)
	if applies != "":
		var applies_label := _mklabel("  applies: " + applies, Color(0.7, 0.9, 0.7, 1.0))
		applies_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body_box.add_child(applies_label)
	if url != "":
		var url_btn := _mkbutton("  open: " + url)
		url_btn.pressed.connect(func(): OS.shell_open(url))
		body_box.add_child(url_btn)
	_cite_vbox.add_child(body_box)

	toggle.pressed.connect(func():
		var cur = _card_expanded.get(cid, false)
		_card_expanded[cid] = not cur
		body_box.visible = not cur
		toggle.text = "-" if not cur else "+"
	)


func _gui_input(event: InputEvent) -> void:
	
	print("[HUD_DIAG] _gui_input called")
	print("[HUD] _gui_input called: ", event)
	# Only process if panel is visible
	if _layer == null or not _layer.visible or _panel == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and _panel_rect().has_point(mb.position):
			_dragging = true
			_drag_offset = mb.position - _panel.position
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _dragging:
			_dragging = false
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and _dragging:
		_panel.position = event.position - _drag_offset
		get_viewport().set_input_as_handled()
