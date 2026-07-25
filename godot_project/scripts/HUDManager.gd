extends Node
## HUDManager — Central portal for HUD component management.
## Manages visibility, dragging, collapsibility, and selectability.
## State is stored in the database via SqliteDb (if available).

signal hud_toggled(name: String, visible: bool)
signal hud_collapsed(name: String, collapsed: bool)

var _components: Dictionary = {}

func _ready():
	if has_node("/root/ForensicHUD"):
		var hud = get_node("/root/ForensicHUD")
		register_component("ForensicHUD", hud)
	_load_state()

func register_component(name: String, node: Node):
	_components[name] = node

func toggle_visibility(name: String):
	if not _components.has(name):
		return
	var node = _components[name]
	if node.has_method("toggle_visible"):
		node.toggle_visible()
	else:
		if node.has_method("set_visible"):
			node.visible = not node.visible
		elif node.has_method("toggle_layer_visible"):
			node.toggle_layer_visible()
	emit_signal("hud_toggled", name, node.visible if node.has_method("get_visible") else false)
	_save_state()

func set_collapsed(name: String, collapsed: bool):
	if not _components.has(name):
		return
	var node = _components[name]
	if node.has_method("set_collapsed"):
		node.set_collapsed(collapsed)
	emit_signal("hud_collapsed", name, collapsed)
	_save_state()

func set_text_selectable(name: String, selectable: bool):
	if not _components.has(name):
		return
	var node = _components[name]
	if node.has_method("set_text_selectable"):
		node.set_text_selectable(selectable)

func _save_state():
	var db = get_node_or_null("/root/SqliteDb")
	if db and db.has_method("query"):
		var data = {}
		for name in _components:
			var node = _components[name]
			data[name] = {
				"visible": node.visible if node.has_method("get_visible") else false,
				"collapsed": node.collapsed if node.has_method("get_collapsed") else false
			}
		var json = JSON.stringify(data)
		db.query("INSERT OR REPLACE INTO hud_state (key, value) VALUES ('state', ?);", [json])

func _load_state():
	var db = get_node_or_null("/root/SqliteDb")
	if db and db.has_method("query"):
		var result = db.query("SELECT value FROM hud_state WHERE key = 'state';")
		if result and result.size() > 0:
			var json = result[0]["value"]
			var data = JSON.parse_string(json)
			if data:
				for name in data:
					if _components.has(name):
						var node = _components[name]
						if data[name].has("visible"):
							if node.has_method("set_visible"):
								node.visible = data[name]["visible"]
						if data[name].has("collapsed"):
							if node.has_method("set_collapsed"):
								node.set_collapsed(data[name]["collapsed"])
