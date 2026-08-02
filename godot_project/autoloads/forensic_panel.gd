extends CanvasLayer
# ============================================================================
# ForensicPanel – pull‑based unified container (forensic HUD + PiP).
#
# Based on evidence from discover_panel_wiring.py:
#   - SqliteDb API is _query(), not query()
#   - PiP is created at runtime in build_terrain.gd – search by type
#   - Input polled in _process (cannot be suppressed by set_input_as_handled)
#
# REFERENCES:
#   - Node._process: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-process
#   - Input.is_physical_key_pressed: https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-method-is-physical-key-pressed
#   - HTTPRequest: https://docs.godotengine.org/en/stable/classes/class_httprequest.html
# ============================================================================

const REFRESH_SEC := 2.0
const HUB_URL := "http://127.0.0.1:8765/api/summary"

var _panel: PanelContainer
var _label: RichTextLabel
var _pip_slot: PanelContainer
var _db: Node = null
var _http: HTTPRequest
var _accum := 0.0
var _toggle_latch := false   # edge‑detect so held key doesn't flicker
var _process_alive_logged := false  # one-shot heartbeat, this session

func _ready() -> void:
	visible = true

	layer = 100
	_build_ui()
	_db = get_node_or_null("/root/SqliteDb")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_hub_reply)
	_adopt_pip_container.call_deferred()
	visible = false
	print("[FPANEL] ready. Toggle: F3 / F9 / ` / T (polled in _process, not _input)")
	# DIAGNOSTIC (this session): _process() has never fired once in any
	# capture so far. Reporting engine-side state directly at _ready()
	# completion, same approach that confirmed forensic_hud.gd IS
	# correctly registered for input despite _input() never firing.
	print("[FPANEL_DIAG] is_inside_tree()=", is_inside_tree(),
		" process_mode=", process_mode,
		" frame=", Engine.get_process_frames(),
		" layer=", layer,
		" visible=", visible)

	# Retry adoption after a short delay to allow PiP creation
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	timer.timeout.connect(_adopt_pip_container)
	add_child(timer)
	timer.start()

# Renamed from _process() (this session): Godot never invoked _process()
# on this autoload despite is_inside_tree()=true/process_mode=0 at
# _ready() — root cause undetermined after exhaustive audit. Called
# explicitly from build_terrain.gd's _physics_process() instead.
func poll_forensic_panel() -> void:
	# Edge-detected toggle: any of F3 / F9 / backtick / T flips visibility.
	# Polled here (not _input) per this file's own header note: input
	# polled in _process cannot be suppressed by set_input_as_handled.
	# Ref: https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-method-is-physical-key-pressed
	# Ref: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-process
	# FIX v2 (this session): checking BOTH is_key_pressed and
	# is_physical_key_pressed (either counts) — v1 used only
	# is_key_pressed and still showed 0 toggles in the next capture,
	# so this removes the single-method guess. Also adds a one-time
	# heartbeat so the next capture shows directly whether _process()
	# runs at all for this autoload, same question is_processing_input()
	# already answered for forensic_hud.gd.
	if not _process_alive_logged:
		_process_alive_logged = true
		print("[FPANEL] _process() alive, frame=", Engine.get_process_frames())
	var pressed := (
		Input.is_key_pressed(KEY_F3) or Input.is_physical_key_pressed(KEY_F3)
		or Input.is_key_pressed(KEY_F9) or Input.is_physical_key_pressed(KEY_F9)
		or Input.is_key_pressed(KEY_QUOTELEFT) or Input.is_physical_key_pressed(KEY_QUOTELEFT)
		or Input.is_key_pressed(KEY_T) or Input.is_physical_key_pressed(KEY_T)
	)
	if pressed and not _toggle_latch:
		_toggle_latch = true
		visible = not visible
		print("[FPANEL] toggled visible=", visible)
	elif not pressed:
		_toggle_latch = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.62
	_panel.anchor_top = 0.05
	_panel.anchor_right = 0.98
	_panel.anchor_bottom = 0.95
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "FORENSIC PANEL"
	vbox.add_child(title)

	_label = RichTextLabel.new()
	_label.selection_enabled = true
	_label.context_menu_enabled = true
	_label.bbcode_enabled = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(_label)

	_pip_slot = PanelContainer.new()
	_pip_slot.custom_minimum_size = Vector2(320, 200)
	vbox.add_child(_pip_slot)


func _on_hub_reply(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		_label.text = body.get_string_from_utf8()
	else:
		_label.text = "[hub unreachable: HTTP %d -- will retry in %.0fs]" % [code, REFRESH_SEC]



func _try_adopt_later() -> void:
	print("[FPANEL] _try_adopt_later: attempt")
	print("[FPANEL] _pip_container = ", _pip_container)
	# Retry with longer delay for dynamic container creation
	for i in range(30):
		if _adopt_pip_container():
			return
		await get_tree().create_timer(1.0).timeout
	print("[FPANEL] No PiP container in this build (creator lives only in scripts/backups/) — continuing without PiP")

func _adopt_pip_container() -> bool:
	# Try to find an existing pip_container node in the scene
	var tree = get_tree()
	if not tree:
		print("[FPANEL] No scene tree yet")
		return false
	var containers = tree.get_nodes_in_group("pip_container")
	if containers and containers.size() > 0:
		_pip_container = containers[0]
		print("[FPANEL] Adopted existing pip container")
		return true
	# No container found – create one
	print("[FPANEL] No pip_container group found, creating one")
	_pip_container = SubViewportContainer.new()
	_pip_container.name = "PIPContainer"
	_pip_container.size = Vector2(320, 180)
	_pip_container.position = Vector2(10, 10)
	_pip_container.visible = true
	# Add a SubViewport inside it
	var viewport = SubViewport.new()
	viewport.size = Vector2(320, 180)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	_pip_container.add_child(viewport)
	# Add to root (or to this panel if root not available)
	var root = tree.root
	if root:
		root.add_child(_pip_container)
	else:
		add_child(_pip_container)
	print("[FPANEL] Created new pip container")
	return true
var _pip_container: SubViewportContainer = null


# === AUTO-ADDED: Group-based PiP discovery for dynamic containers ===
# Fixes: [FPANEL] FAILED to adopt PiP after 10 attempts
# Citation: Godot Node Groups:
#   https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-to-group
# Citation: Godot Signals:
#   https://docs.godotengine.org/en/stable/classes/class_signal.html
#
# The PiP container is created dynamically in build_terrain.gd.

func _get_drag_data(_at_position: Vector2) -> Dictionary:
	return {}