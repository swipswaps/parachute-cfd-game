extends CanvasLayer
# ==========================================================================
# altimeter_hud.gd
#
# Purpose: simple ALT/VARIO panel, draggable, F4 toggle.
# WHY this rewrite: the prior version (transcript 17417-17479) triggered
#   "Nodes with non-equal opposite anchors will have their size overridden
#   after _ready()." (transcript 17593-17597, points at altimeter_hud.gd:23)
# because vbox had anchor_right=1.0 anchor_bottom=1.0 AND an explicit size
# assignment in _ready() -- Godot's Control layout rewrites size after
# _ready() when opposite anchors differ. Fix: use anchors only (no explicit
# size) so the vbox fills the panel deterministically, and defer the panel
# child add so anchor propagation is stable.
# ==========================================================================

var panel: Panel
var vbox: VBoxContainer
var altitude_label: Label
var vario_label: Label
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var _alt_update_seen: bool = false

func _ready() -> void:
	panel = Panel.new()
	panel.size = Vector2(200, 100)
	panel.position = Vector2(50, 200)
	add_child(panel)
	panel.visible = true

	vbox = VBoxContainer.new()
	# Use anchors that fully fill the panel, and DO NOT also set size --
	# setting both is what produced the "non-equal opposite anchors" warning.
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 4
	vbox.offset_top = 4
	vbox.offset_right = -4
	vbox.offset_bottom = -4
	panel.add_child(vbox)

	altitude_label = Label.new()
	altitude_label.text = "ALT: 0 ft"
	vbox.add_child(altitude_label)

	vario_label = Label.new()
	vario_label.text = "VARIO: 0.0 m/s"
	vbox.add_child(vario_label)

	panel.visible = true
	print("[ALTIMETER] ready: layer=", layer, " visible=", visible, " panel.pos=", panel.position, " panel.size=", panel.size, " panel.visible=", panel.visible)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			panel.visible = not panel.visible
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = mb.position
			var rect := Rect2(panel.position, panel.size)
			if mb.pressed and rect.has_point(pos):
				dragging = true
				drag_offset = pos - panel.position
				get_viewport().set_input_as_handled()
			elif not mb.pressed:
				dragging = false

	if event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		panel.position = mm.position - drag_offset
		get_viewport().set_input_as_handled()

func update_altitude(alt_ft: float, vario: float = 0.0) -> void:
	if not _alt_update_seen:
		_alt_update_seen = true
		print("[ALTIMETER] update_altitude FIRST CALL: alt_ft=", alt_ft)
	altitude_label.text = "ALT: %d ft" % int(round(alt_ft))
	vario_label.text = "VARIO: %.2f m/s" % vario
