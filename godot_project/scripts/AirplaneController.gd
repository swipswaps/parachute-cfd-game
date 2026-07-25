extends Node

const PLANE_SCENES = ["res://scenes/planes/cessna.tscn", "res://scenes/planes/twin_otter.tscn"]
const SKIN_MATERIALS = [
	"res://materials/plane_skin_default.tres",
	"res://materials/plane_skin_red.tres",
]

var _plane_node: Node3D = null
var _container: Node3D = null
var _model_idx: int = 0
var _skin_idx: int = 0


func _ready() -> void:
	_container = Node3D.new()
	_container.name = "PlaneContainer"
	add_child(_container)
	load_plane(0)
	var reg := get_node_or_null("/root/ComponentRegistry")
	if reg and reg.has_method("register_airplane_controller"):
		reg.register_airplane_controller(self)


func load_plane(index: int) -> bool:
	if index < 0 or index >= PLANE_SCENES.size():
		return false
	for c in _container.get_children():
		_container.remove_child(c)
	c.queue_free()
	var scene = load(PLANE_SCENES[index])
	if not scene:
		return false
	var inst = scene.instantiate()
	if not inst:
		return false
	_container.add_child(inst)
	_plane_node = inst
	_model_idx = index
	apply_skin(_skin_idx)
	return true


func apply_skin(index: int) -> bool:
	if index < 0 or index >= SKIN_MATERIALS.size():
		return false
	var mat = load(SKIN_MATERIALS[index])
	if not mat:
		return false
	_apply_material_recursive(_plane_node, mat)
	_skin_idx = index
	return true


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for c in node.get_children():
		_apply_material_recursive(c, mat)


func get_plane() -> Node3D:
	return _plane_node


func set_position(pos: Vector3) -> void:
	if _container:
		_container.position = pos


func set_rotation(rot: Vector3) -> void:
	if _container:
		_container.rotation = rot


func get_health() -> Dictionary:
	return {
		"plane_loaded": _plane_node != null,
		"model_index": _model_idx,
		"skin_index": _skin_idx,
		"position": _container.position if _container else Vector3.ZERO,
	}
