
func _ready():
    await get_tree().create_timer(1.0).timeout
    _set_selectable_on_children(self)
    _fetch_and_display_hub_data()

extends CanvasLayer
# forensic_hud.gd – manages the on-screen forensic overlay and PiP windows.
# This version has the hud_draggable.gd script attached to the main HUD panel.

signal pip_closed(pip_id: String)

var _layer: CanvasLayer
var _panel: Panel
var _pip_container: Control  # parent for PiP windows
var _pips: Dictionary = {}   # id -> PiPControl
var _next_pip_pos: Vector2 = Vector2(24, 24)

# --------------------------------------
# PiPControl – simple draggable PiP window
# --------------------------------------
class PiPControl:
	extends Panel
	var pip_id: String
	var _drag_active: bool = false
	var _drag_offset: Vector2 = Vector2.ZERO

	func _init(id: String, parent: Control) -> void:
		pip_id = id
		parent.add_child(self)
		mouse_filter = MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_active = true
				_drag_offset = event.position
				accept_event()
			else:
				_drag_active = false
				accept_event()
		elif event is InputEventMouseMotion and _drag_active:
			position += event.relative
			accept_event()


# --------------------------------------
# Main HUD
# --------------------------------------
func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_panel = Panel.new()
	_panel.size = Vector2(300, 400)
	_panel.position = Vector2(24, 24)
	# vFIX: set_script BEFORE add_child — in Godot 4, _ready() only fires
	# when the node enters the scene tree; setting the script after add_child
	# means _ready() already ran under the prior (empty) script.
	if _panel and not _panel.has_method("_gui_input"):
		_panel.set_script(preload("res://scripts/hud_draggable.gd"))
	_layer.add_child(_panel)
	# vFIX2: deferred confirmation — fires one frame after tree entry,
	# inside the game loop where autostall can capture it.
	call_deferred("_confirm_drag_attached")

	# PiP container (stays above the HUD panel)
	_pip_container = Control.new()
	_pip_container.mouse_filter = MOUSE_FILTER_IGNORE
	_layer.add_child(_pip_container)


# --------------------------------------
# PiP management
# --------------------------------------
func open_pip(id: String, title: String, content: Control) -> PiPControl:
	if _pips.has(id):
		return _pips[id] as PiPControl

	var pip = PiPControl.new(id, _pip_container)
	pip.position = _next_pip_pos
	_next_pip_pos += Vector2(32, 32)
	_pips[id] = pip
	print("[HUD] Opened PiP: %s at %s" % [id, pip.position])
	return pip

func close_pip(id: String) -> void:
	if _pips.has(id):
		var pip = _pips[id] as PiPControl
		pip.queue_free()
		_pips.erase(id)
		emit_signal("pip_closed", id)
		print("[HUD] Closed PiP: %s" % id)

func move_pip_to(pip_id: String, pos: Vector2) -> void:
	if _pips.has(pip_id):
		(_pips[pip_id] as PiPControl).position = pos

func _confirm_drag_attached() -> void:
	if _panel and _panel.has_method("_gui_input"):
		print("[VERBATIM] HUD drag script _ready — _gui_input confirmed on panel")
	else:
		print("[VERBATIM] HUD drag script MISSING — _gui_input not found on panel")
		print("[HUD] _panel script=", _panel.get_script() if _panel else "(null panel)")

# Added functions

# Added by fix_forensic_hud.py – make all labels selectable
func _set_selectable_on_children(node):
    for child in node.get_children():
        if child is Label:
            child.selectable = true
        elif child is RichTextLabel:
            child.selection_enabled = true
        _set_selectable_on_children(child)


# Added by fix_forensic_hud.py – fetch and display hub data
func _fetch_and_display_hub_data():
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_hub_data_received)
    var error = http.request("http://127.0.0.1:8765/api/gamification")
    if error != OK:
        print("[HUD] HTTP request failed: ", error)
    else:
        print("[HUD] Fetching hub data...")

func _on_hub_data_received(result, response_code, headers, body):
    if response_code != 200:
        print("[HUD] Hub data fetch failed: ", response_code)
        return
    var data = JSON.parse_string(body.get_string_from_utf8())
    if data == null:
        print("[HUD] Failed to parse JSON response.")
        return
    var display = get_node_or_null("HUB_DATA_LABEL")
    if not display:
        display = Label.new()
        display.name = "HUB_DATA_LABEL"
        display.visible = true
        display.text = "Hub Data:"
        display.position = Vector2(10, 10)
        display.selectable = true
        add_child(display)
    var text = "Hub Data:\n"
    text += "Status: " + str(data.get("status", "unknown")) + "\n"
    text += "Port: " + str(data.get("port", "N/A")) + "\n"
    text += "DB: " + str(data.get("db", "N/A")) + "\n"
    var endpoints = data.get("endpoints", [])
    if endpoints is Array:
        text += "Endpoints:\n"
        for ep in endpoints:
            text += "  - " + str(ep) + "\n"
    for key in data.keys():
        if key not in ["status", "port", "db", "endpoints"]:
            text += str(key) + ": " + str(data[key]) + "\n"
    display.text = text
    print("[HUD] Hub data displayed.")
