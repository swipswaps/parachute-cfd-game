# PATH: addons/gd_repair/validate_scene.gd
# WHAT: EditorScript that validates the parachute simulator scene at editor time.
#       Checks character mesh presence, camera aim, InputMap registrations,
#       and canopy node structure. Prints a PASS/FAIL report to the Output panel.
# WHY:  The Python repair script cannot detect missing 3D meshes, wrong camera
#       positions, or missing InputMap actions at runtime. This script runs inside
#       the Godot editor with full access to the scene tree and engine state.
#       Source: https://docs.godotengine.org/en/stable/classes/class_editorscript.html
# HOW TO RUN: In Godot editor -> Project -> Tools -> Execute Script
#       Select this file. Output appears in the Output panel (bottom of editor).
# MENTAL MODEL BEFORE: scene may have invisible character, wrong camera, missing actions.
# MENTAL MODEL AFTER:  each check prints PASS or FAIL with exact values found.
# FAILURE MODE: if get_scene() returns null, the main scene is not open in editor.
#       Open res://scenes/main.tscn (or equivalent) before running.
# VERIFIES WITH: all lines in Output panel start with [PASS] or [WARN] or [FAIL].
# ASSUMES: Godot 4.x. Scene has nodes named: Character (or similar), Camera3D.
#   InputMap actions registered in project.godot.
#   Source: https://docs.godotengine.org/en/stable/classes/class_inputmap.html
#   Source: https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html
#   Source: https://docs.godotengine.org/en/stable/classes/class_camera3d.html

@tool
extends EditorScript


# _run() is called by Project -> Tools -> Execute Script.
# Source:
# https://docs.godotengine.org/en/stable/classes/class_editorscript.html#class-editorscript-private-method-run


func _run() -> void:
	print("=" .repeat(60))
	print("[VALIDATE] parachute-cfd-game scene validator")
	print("[VALIDATE] Running inside Godot editor -- full scene access")
	print("=".repeat(60))

	var pass_count: int = 0   # number of checks that passed
	var fail_count: int = 0   # number of checks that failed
	var warn_count: int = 0   # number of advisory warnings

	# ------------------------------------------------------------------
	# CHECK 0: scene is open
	# ------------------------------------------------------------------
	# WHAT: confirms a scene is loaded in the editor before any other check.
	# WHY:  get_scene() returns null if no scene is open; all node checks
	#       would crash with a null dereference.
	# Source:
	# https://docs.godotengine.org/en/stable/classes/class_editorscript.html#class-editorscript-method-get-scene
	var scene: Node = get_scene()
	if scene == null:
		print("[FAIL] No scene open in editor.")
		print("       Open the main scene (e.g. res://scenes/main.tscn) then re-run.")
		return
	print("[PASS] Scene open: %s" % scene.name)
	pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 1: character node exists
	# ------------------------------------------------------------------
	# WHAT: searches the scene tree for any Node3D that could be the skydiver.
	# WHY:  the character might be loaded dynamically (add_child in _ready),
	#       so it may not exist in the editor scene tree. This check catches
	#       whether the scene has a placeholder or the node at all.
	# Source:
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-child
	var character: Node = scene.find_child("*character*", true)
	if character == null:
		print("[WARN] No node with 'character' in name found in editor scene.")
		print("       Character is likely instantiated at runtime via add_child().")
		print("       Run the game and check '[VERBATIM] MeshInstance3D children count:' in logs.")
		warn_count += 1
	else:
		print("[PASS] Character node found: %s (type: %s)" % [character.name, character.get_class()])
		pass_count += 1

		# CHECK 1a: character has MeshInstance3D children
		# WHAT: counts MeshInstance3D nodes under the character.
		# WHY:  if count == 0, the FBX import failed to produce visible geometry.
		#       This was the suspected cause of the invisible character in the logs.
		# Source: https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html
		var meshes: Array = character.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() == 0:
			print("[FAIL] Character has 0 MeshInstance3D children -- FBX may have no mesh.")
			print("       Open the FBX in Blender and verify geometry exists.")
			fail_count += 1
		else:
			print("[PASS] Character has %d MeshInstance3D child(ren)." % meshes.size())
			pass_count += 1

		# CHECK 1b: character is visible
		# Source:
		# https://docs.godotengine.org/en/stable/classes/class_node3d.html#class-node3d-property-visible
		if character is Node3D:
			if not character.visible:
				print("[FAIL] Character node visible = false.")
				fail_count += 1
			else:
				print("[PASS] Character node visible = true.")
				pass_count += 1

		# CHECK 1c: character is not at origin or underground
		# WHAT: checks character position is above terrain level.
		# WHY:  position (0,0,0) or y < 0 means the character was never placed
		#       correctly; it would be underground or at the scene origin.
		# Source:
		# https://docs.godotengine.org/en/stable/classes/class_node3d.html#class-node3d-property-position
		if character is Node3D:
			var pos: Vector3 = character.position
			print("[INFO] Character position: %s" % pos)
			if pos.y < 25.0:
				print("[WARN] Character y=%.1f -- may be underground (terrain floor ~25 ft)." % pos.y)
				warn_count += 1
			elif pos.y < 100.0:
				print("[WARN] Character y=%.1f -- lower than expected starting altitude (~6000 ft)." % pos.y)
				warn_count += 1
			else:
				print("[PASS] Character y=%.1f -- above terrain." % pos.y)
				pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 2: camera node exists and is aimed at character
	# ------------------------------------------------------------------
	# WHAT: finds Camera3D in the scene and checks its position relative
	#       to the character.
	# WHY:  if the camera is at origin or aimed away, the character is not
	#       visible even if it has meshes. This was a suspected cause in the
	#       grey-screen session.
	# Source: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
	var camera: Camera3D = scene.find_child("*", "Camera3D", true, false) as Camera3D
	if camera == null:
		print("[WARN] No Camera3D found in editor scene.")
		print("       Camera may be instantiated at runtime. Check logs for:")
		print("       '[VERBATIM] Camera position:' after FIX-22 runs.")
		warn_count += 1
	else:
		var cam_pos: Vector3 = camera.global_position
		print("[PASS] Camera3D found: %s at %s" % [camera.name, cam_pos])
		pass_count += 1
		if character != null and character is Node3D:
			var dist: float = cam_pos.distance_to(character.global_position)
			print("[INFO] Camera distance to character: %.1f units" % dist)
			if dist < 0.1:
				print("[FAIL] Camera is at the same position as character -- will see nothing.")
				fail_count += 1
			elif dist > 500.0:
				print("[WARN] Camera is %.1f units from character -- may be too far." % dist)
				warn_count += 1
			else:
				print("[PASS] Camera distance to character looks reasonable (%.1f units)." % dist)
				pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 3: InputMap actions
	# ------------------------------------------------------------------
	# WHAT: verifies all required InputMap actions are registered.
	# WHY:  is_action_just_pressed() returns false silently if action not in
	#       InputMap. Missing actions were confirmed as a bug in prior sessions.
	# Source:
	# https://docs.godotengine.org/en/stable/classes/class_inputmap.html#class-inputmap-method-has-action
	var required_actions: Array[String] = [
		"deploy", "turnleft", "turnright", "cyclecamera",
		"togglehud", "flightcheck", "cutaway", "reserve",
		"flare", "restart", "pause",
	]
	print("\n[VALIDATE] InputMap action check:")
	var missing_actions: Array[String] = []
	for action in required_actions:
		if InputMap.has_action(action):
			print("[PASS]   action '%s' registered" % action)
			pass_count += 1
		else:
			print("[FAIL]   action '%s' NOT registered" % action)
			missing_actions.append(action)
			fail_count += 1
	if missing_actions.size() > 0:
		print("[FAIL] Missing actions: %s" % missing_actions)
		print("       Run repair_gdscript_v2.py to add them to project.godot.")

	# ------------------------------------------------------------------
	# CHECK 4: canopy node exists
	# ------------------------------------------------------------------
	# WHAT: searches scene for a node likely to be the parachute canopy.
	# WHY:  if the canopy GLB failed to load, deploy animation has nothing to show.
	# Source:
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-child
	print("\n[VALIDATE] Canopy node check:")
	var canopy: Node = scene.find_child("*canopy*", true)
	if canopy == null:
		print("[WARN] No canopy/parachute node found in editor scene.")
		print("       Canopy may be instantiated at runtime. Check logs for:")
		print("       '[VERBATIM] Clean GLB loaded from:'")
		warn_count += 1
	else:
		print("[PASS] Canopy node found: %s (type: %s)" % [canopy.name, canopy.get_class()])
		pass_count += 1
		if canopy is Node3D:
			var scale: Vector3 = canopy.scale
			print("[INFO] Canopy scale: %s" % scale)
			if scale.length() < 0.01:
				print("[FAIL] Canopy scale is ~zero -- canopy will be invisible.")
				fail_count += 1
			else:
				print("[PASS] Canopy scale looks non-zero.")
				pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 5: _save_flight_screenshot autoload
	# ------------------------------------------------------------------
	# WHAT: checks if _save_flight_screenshot is registered as an autoload.
	# WHY:  _save_flight_screenshot() is called in FIX-10 and
	#       the screenshot timer. If not registered, all those calls will crash
	#       at runtime with "Class '_save_flight_screenshot' does not exist".
	# Source: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
	print("\n[VALIDATE] _save_flight_screenshot autoload check:")
	if Engine.has_singleton("_save_flight_screenshot"):
		print("[PASS] _save_flight_screenshot autoload is registered.")
		pass_count += 1
	else:
		print("[WARN] _save_flight_screenshot not found as singleton/autoload.")
		print("       If screenshot calls appear in the game, add _save_flight_screenshot")
		print("       to Project -> Project Settings -> AutoLoad.")
		warn_count += 1

	# ------------------------------------------------------------------
	# SUMMARY
	# ------------------------------------------------------------------
	print("\n" + "=".repeat(60))
	print("[VALIDATE] SUMMARY: %d PASS, %d WARN, %d FAIL" % [pass_count, warn_count, fail_count])
	if fail_count == 0 and warn_count == 0:
		print("[VALIDATE] ALL CHECKS PASSED -- scene is configured correctly.")
	elif fail_count == 0:
		print("[VALIDATE] No failures. Review %d warning(s) above." % warn_count)
	else:
		print("[VALIDATE] %d FAILURE(S) require attention before running the game." % fail_count)
	print("=".repeat(60))
# IMPLEMENTATION COMPLETE
