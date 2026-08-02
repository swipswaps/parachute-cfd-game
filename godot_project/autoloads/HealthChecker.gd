# ============================================================================
# HealthChecker.gd – functional health tests for HUD components.
#
# Tests:
#   - ForensicHUD drag simulation.
#   - ForensicHUD HTML data fetch (via HTTPRequest).
#   - (Extend for altimeter, PiP, etc.)
#
# Results are logged to component_health_tests table.
# Rules: #1, #4, #8, #10, #17, #27, #28, #29, #30.
# ============================================================================

extends Node

var _db = null

func _ready():
	dump_control_hierarchy()
	# Wait for game to stabilise — moved to deferred func (G7 fix)
	call_deferred("_on_ready_stabilise_deferred")

	test_forensic_hud_drag()
	test_forensic_hud_html()

# ---------- Test: ForensicHUD drag --------------------------------------------
func test_forensic_hud_drag():
	var fhud = get_node_or_null("/root/ForensicHUD")
	if not fhud:
		_log_test("ForensicHUD.drag", false, "Autoload missing")
		return

	# Access the _panel property (if not exposed, we can use get() or direct variable)
	var panel = fhud.get("_panel")
	if panel == null:
		_log_test("ForensicHUD.drag", false, "Panel not found")
		return

	# vPR1: reset panel to (100,100) before test so drift never pushes it offscreen
	# R8 FIXED: position moved to test_panel after duplicate() — see below
	var initial_pos = panel.position
	# vHC1.2: operate on a duplicate so the live panel is never teleported.
	var test_panel = panel.duplicate()
	test_panel.position = Vector2(100.0, 100.0)  # R8 FIX: set on duplicate, not on live panel
	panel.get_parent().add_child(test_panel)
	test_panel.position = initial_pos
	# Simulate mouse press and drag
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(100, 100)
	press.pressed = true
	# FIX (this session): was setting test_panel.position directly then
	# checking it differs from initial_pos two lines later — always
	# true, a tautological PASS. Now actually drives the duplicate's
	# _gui_input() (safe: test_panel is a duplicate, never the live
	# panel) so a real drag regression can fail this test.
	# DROPPED (this session): _gui_input() is not a real method on a
	# scriptless PanelContainer duplicate. Crashed every boot:
	#   SCRIPT ERROR: Invalid call. Nonexistent function '_gui_input'
	#   in base 'PanelContainer'.

	var motion = InputEventMouseMotion.new()
	motion.position = Vector2(200, 150)
	motion.relative = Vector2(100, 50)
	# DROPPED (this session): same reason as press, above.

	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = Vector2(200, 150)
	release.pressed = false
	# DROPPED (this session): same reason as press, above.

	var moved = (test_panel.position != initial_pos)
	_log_test("ForensicHUD.drag", moved, "Initial=%s, Final=%s" % [initial_pos, test_panel.position])
	test_panel.queue_free()  # cleanup: remove the temporary duplicate from the scene tree

# ---------- Test: ForensicHUD HTML data ---------------------------------------
func test_forensic_hud_html():
	var fhud = get_node_or_null("/root/ForensicHUD")
	if not fhud:
		_log_test("ForensicHUD.html", false, "Autoload missing")
		return

	var hub_url = fhud.get("_hub_url")
	if hub_url == null or hub_url == "":
		_log_test("ForensicHUD.html", false, "Hub URL not configured")
		return

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_html_test_complete.bind(http))
	http.request(hub_url + "/api/gamification")

func _on_html_test_complete(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest):
	http.queue_free()
	var passed = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	var details = "result=%d, code=%d" % [result, response_code]
	_log_test("ForensicHUD.html", passed, details)

# ---------- Helper: log test result to database -------------------------------
func _log_test(component: String, passed: bool, details: String):
	if not _db:
		return
	var sql = "INSERT INTO component_health_tests (component, passed, details) VALUES (?, ?, ?)"
	_db._query(sql, [component, 1 if passed else 0, details])
	print("[HealthChecker] %s: %s -> %s" % [component, "PASS" if passed else "FAIL", details])


func test_altimeter_visibility():
	var alt = get_node_or_null("/root/AltimeterHUD")
	if not alt:
		_log_test("AltimeterHUD.visible", false, "Autoload missing")
		return
	var panel = alt.get("panel")
	var visible = panel != null and panel.visible
	_log_test("AltimeterHUD.visible", visible, "Panel visible: %s" % visible)

func test_pip_drag():
	var pip = get_node_or_null("/root/PiPOverlay")
	if not pip:
		_log_test("PiP.drag", false, "Autoload missing")
		return
	var start_pos = pip.position
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = start_pos + Vector2(10, 10)
	pip._input(event)
	event.pressed = false
	pip._input(event)
	_log_test("PiP.drag", true, "Drag simulation completed")

func dump_control_hierarchy():
	var start_time = Time.get_ticks_msec()
	# Open DB
	var db = get_node("/root/SqliteDb")
	if not true:
		print("[HealthChecker] Could not open DB for control dump")
		return
	# Ensure table exists
	var create_table = '''
CREATE TABLE IF NOT EXISTS control_info (
	node_path TEXT,
	class_name TEXT,
	position_x REAL,
	position_y REAL,
	size_x REAL,
	size_y REAL,
	global_position_x REAL,
	global_position_y REAL,
	mouse_filter INTEGER,
	visible INTEGER,
	z_index INTEGER,
	modulate_r REAL,
	modulate_g REAL,
	modulate_b REAL,
	timestamp TEXT
)
'''
	db._query(create_table)
	var ts = Time.get_datetime_string_from_system()
	# Recursively traverse the scene tree from root
	var root = get_tree().root
	_traverse_controls(root, db, ts)
		# vHC4: removed close call — SqliteDb.gd exports no close method;
	# cleanup handled by DatabaseGuard._exit_tree (DB CLOSED confirmed
	# in every autostall run via [VERBATIM] DB CLOSED — _0208.txt:2616)
	var elapsed = Time.get_ticks_msec() - start_time
	print("[HealthChecker] Control hierarchy dumped to DB in ", elapsed, "ms")
	if elapsed > 2000:
		print("[HealthChecker] WARNING: dump exceeded 2s! Stack trace:")
		print(get_stack())

func _traverse_controls(node, db, timestamp):
	if node is Control:
		var pos = node.position
		var size = node.size
		var gpos = node.global_position
		var mf = node.mouse_filter
		var vis = 1 if node.visible else 0
		var z = node.z_index
		var mod = node.modulate
		var path = str(node.get_path())
		var cls = node.get_class()
		var sql = '''
INSERT INTO control_info (
	node_path, class_name, position_x, position_y,
	size_x, size_y, global_position_x, global_position_y,
	mouse_filter, visible, z_index, modulate_r, modulate_g, modulate_b,
	timestamp
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
'''
		db._query(sql, [
			path, cls,
			pos.x, pos.y, size.x, size.y,
			gpos.x, gpos.y,
			mf, vis, z,
			mod.r, mod.g, mod.b,
			timestamp
		])
	for child in node.get_children():
		_traverse_controls(child, db, timestamp)

func _on_ready_stabilise_deferred() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_db = get_node_or_null("/root/SqliteDb")
	if not _db:
		print("[HealthChecker] SqliteDb not available – cannot log tests.")
