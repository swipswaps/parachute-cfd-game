extends Node
# Auto-generated registry

var parachute_controller: Node
var altimeter_hud: Node
var pip_draggable: Node
var character: Node
var db_guard: Node
var view_pose_controller: Node
var airplane_controller: Node


func register_parachute_controller(node: Node) -> void:
	parachute_controller = node


func register_altimeter_hud(node: Node) -> void:
	altimeter_hud = node


func register_pip_draggable(node: Node) -> void:
	pip_draggable = node


func register_character(node: Node) -> void:
	character = node


func register_db_guard(node: Node) -> void:
	db_guard = node


func register_view_pose_controller(node: Node) -> void:
	view_pose_controller = node


func register_airplane_controller(node: Node) -> void:
	airplane_controller = node


func get_health_report() -> Dictionary:
	var report := { }
	if parachute_controller and parachute_controller.has_method("get_health"):
		report["parachute"] = parachute_controller.get_health()
	if altimeter_hud and altimeter_hud.has_method("get_health"):
		report["hud"] = altimeter_hud.get_health()
	if pip_draggable and pip_draggable.has_method("get_health"):
		report["pip"] = pip_draggable.get_health()
	if character and character.has_method("get_health"):
		report["character"] = character.get_health()
	if db_guard and db_guard.has_method("get_health"):
		report["database"] = db_guard.get_health()
	if view_pose_controller and view_pose_controller.has_method("get_health"):
		report["view_pose"] = view_pose_controller.get_health()
	if airplane_controller and airplane_controller.has_method("get_health"):
		report["airplane"] = airplane_controller.get_health()
	return report
