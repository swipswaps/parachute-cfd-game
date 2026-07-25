# PATH: scripts/debug_components.gd

extends Node


static func run():
	print("\n===== 3D COMPONENT DEBUG =====\n")
	var root = Engine.get_main_loop().current_scene
	if not root:
		print("ERROR: No current scene")
		return
	var camera = Engine.get_main_loop().root.get_viewport().get_camera_3d()
	if camera:
		print("--- Camera ---")
		print("  Position: ", camera.global_position)
		print(
			"  Rotation (deg): ",
			rad_to_deg(camera.rotation.x),
			", ",
			rad_to_deg(camera.rotation.y),
			", ",
			rad_to_deg(camera.rotation.z),
		)
		print("  Current: ", camera.current)
		print("  Cull mask: ", camera.cull_mask)
	else:
		print("ERROR: No camera")
	var world_env := _find_node_by_class(root, "WorldEnvironment")
	if world_env and world_env.environment:
		print("\n--- WorldEnvironment ---")
		print("  Background mode: ", world_env.environment.background_mode)
		if world_env.environment.background_mode != Environment.BG_SKY:
			print("  WARNING: Not BG_SKY – grey screen likely")
	var meshes := _find_all_by_class(root, "MeshInstance3D")
	print("\n--- MeshInstance3D (Terrain, Runways, etc.) ---")
	for mi in meshes:
		print(
			"  ",
			mi.name,
			" visible=",
			mi.visible,
			" pos=",
			mi.global_position,
			" scale=",
			mi.scale,
		)
	var bodies := _find_all_by_class(root, "CharacterBody3D")
	print("\n--- CharacterBody3D (Player) ---")
	for body in bodies:
		print("  ", body.name, " pos=", body.global_position, " visible=", body.visible)
		var body_meshes := _find_all_by_class(body, "MeshInstance3D")
		if body_meshes.is_empty():
			print("    WARNING: No MeshInstance3D child – character invisible")
	var canopy := _find_node_by_name(root, "canopy_model")
	if canopy:
		print("\n--- Canopy scale=", canopy.scale, " visible=", canopy.visible)
	var plane := _find_node_by_name(root, "FlyingPlane")
	if plane:
		print("\n--- Plane pos=", plane.global_position, " visible=", plane.visible)
	print("\n===== DEBUG END =====\n")


static func _find_node_by_name(node: Node, name: String) -> Node:
	if node.name == name: return node
	for child in node.get_children():
		var found := _find_node_by_name(child, name)
		if found: return found
	return null


static func _find_node_by_class(node: Node, cls_name: String) -> Node:
	if node.is_class(cls_name): return node
	for child in node.get_children():
		var found := _find_node_by_class(child, cls_name)
		if found: return found
	return null


static func _find_all_by_class(node: Node, cls_name: String) -> Array[Node]:
	var results: Array[Node] = []
	if node.is_class(cls_name): results.append(node)
	for child in node.get_children():
		results.append_array(_find_all_by_class(child, cls_name))
	return results
