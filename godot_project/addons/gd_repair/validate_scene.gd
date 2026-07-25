# PATH: addons/gd_repair/validate_scene.gd
#
# WHAT: EditorScript that validates the parachute simulator scene at editor time.
#
# HOW TO RUN (Godot 4 only):
#   1. Open this file in the Script Editor tab
#   2. Make sure this tab is ACTIVE
#   3. File -> Run  (or Ctrl+Shift+X)
#   Output appears in the Output panel.
#
# FIX-G changes in this version:
#   - find_child("*", "TypeName", true, false)  <- WRONG in Godot 4 (4 args, type removed)
#   - find_children("*", "TypeName", true, false) <- CORRECT (plural, keeps type filter)
#   - Array[String] -> Array (untyped, avoids parse errors)
#   - Inline cast "var x: Camera3D = node as Camera3D" -> is-guard pattern
#
# Source (Tier 2 — Godot 4 Node.find_child — 3 params max, no type):
#   https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-child
# Source (Tier 2 — Godot 4 Node.find_children — has type param):
#   https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-children
# Source (Tier 2 — EditorScript._run):
#   https://docs.godotengine.org/en/stable/classes/class_editorscript.html#class-editorscript-private-method-run
# Source (Tier 2 — EditorInterface.get_edited_scene_root):
#   https://docs.godotengine.org/en/stable/classes/class_editorinterface.html#class-editorinterface-method-get-edited-scene-root

@tool
extends EditorScript


func _run() -> void:
	print("=".repeat(60))
	print("[VALIDATE] parachute-cfd-game scene validator")
	print("[VALIDATE] Run: Script Editor -> File -> Run  (Ctrl+Shift+X)")
	print("=".repeat(60))

	var pass_count: int = 0
	var fail_count: int = 0
	var warn_count: int = 0

	# ------------------------------------------------------------------
	# CHECK 0: scene is open
	# ------------------------------------------------------------------
	# WHY: get_edited_scene_root() returns null if no scene is open in the
	#      Scene tab. All node searches below would crash on null.
	# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_editorinterface.html
	var scene: Node = EditorInterface.get_edited_scene_root()
	if scene == null:
		print("[FAIL] No scene open. Open main scene in Scene tab, then re-run.")
		return
	print("[PASS] Scene: '%s'" % scene.name)
	pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 1: character node
	# ------------------------------------------------------------------
	# WHY: character is created at runtime (add_child in _load_character).
	#      Always WARN — that is expected and correct.
	# FIX-G: use find_children (plural) NOT find_child with type argument.
	# Source (Tier 2 — Node.find_children):
	#   https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-children
	var char_results: Array = scene.find_children("*harness*", "", true, false)
	if char_results.is_empty():
		char_results = scene.find_children("*Character*", "", true, false)
	if char_results.is_empty():
		char_results = scene.find_children("*character*", "", true, false)

	var character: Node = char_results[0] if not char_results.is_empty() else null

	if character == null:
		print("[WARN] No character node in editor scene (expected — runtime instantiated).")
		print("       Run game, check: [VERBATIM] MeshInstance3D children count: N")
		print("       N==0 means FBX has no geometry.")
		warn_count += 1
	else:
		print("[PASS] Character: '%s' (%s)" % [character.name, character.get_class()])
		pass_count += 1

		# 1a: MeshInstance3D children
		# FIX-G: find_children with type="MeshInstance3D"
		# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-children
		var meshes: Array = character.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			print("[FAIL] Character has 0 MeshInstance3D children.")
			fail_count += 1
		else:
			print("[PASS] Character has %d MeshInstance3D child(ren)." % meshes.size())
			pass_count += 1

		# 1b: visible flag — FIX-G: is-guard, no inline cast
		# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_node3d.html
		if character is Node3D:
			if not character.visible:
				print("[FAIL] Character.visible = false")
				fail_count += 1
			else:
				print("[PASS] Character.visible = true")
				pass_count += 1
			print("[INFO] Character position: %s" % character.position)
			if character.position.y < 25.0:
				print("[WARN] Character y=%.1f may be underground." % character.position.y)
				warn_count += 1
			else:
				print("[PASS] Character y=%.1f above terrain." % character.position.y)
				pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 2: camera
	# ------------------------------------------------------------------
	# WHY: camera also created at runtime. Always WARN.
	# FIX-G: find_children with type="Camera3D", then is-guard before accessing properties.
	# Source (Tier 2 — Node.find_children):
	#   https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-children
	var cam_results: Array = scene.find_children("*", "Camera3D", true, false)
	if cam_results.is_empty():
		print("[WARN] No Camera3D in editor scene (expected — runtime created).")
		print("       Run game, check: [VERBATIM] Camera position: (x, y, z)")
		print("       After FIX-C: offset should be (0, 4, 8) from character.")
		warn_count += 1
	else:
		var cam: Node = cam_results[0]
		if cam is Camera3D:
			print("[PASS] Camera3D: '%s' at %s" % [cam.name, cam.global_position])
			pass_count += 1
			if character != null and character is Node3D:
				var dist: float = cam.global_position.distance_to(character.global_position)
				print("[INFO] Camera-character distance: %.1f units" % dist)
				if dist < 0.5:
					print("[FAIL] Camera inside character — will render nothing.")
					fail_count += 1
				else:
					print("[PASS] Camera distance OK (%.1f units)." % dist)
					pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 3: InputMap actions
	# ------------------------------------------------------------------
	# WHY: is_action_just_pressed() silently returns false for unregistered actions.
	#      Missing actions = controls that do nothing with no error.
	# FIX-G: use plain Array not Array[String] to avoid parse errors.
	# Source (Tier 2 — InputMap.has_action):
	#   https://docs.godotengine.org/en/stable/classes/class_inputmap.html#class-inputmap-method-has-action
	print("\n[VALIDATE] InputMap actions:")
	var required_actions: Array = [
		"deploy", "turnleft", "turnright", "cyclecamera",
		"togglehud", "flightcheck", "cutaway", "reserve",
		"flare", "restart", "pause",
	]
	var missing_actions: Array = []
	for action in required_actions:
		if InputMap.has_action(action):
			print("[PASS]   '%s'" % action)
			pass_count += 1
		else:
			print("[FAIL]   '%s' NOT registered" % action)
			missing_actions.append(action)
			fail_count += 1
	if not missing_actions.is_empty():
		print("[FAIL] %d missing: %s" % [missing_actions.size(), str(missing_actions)])
		print("       Fix: python3 addons/gd_repair/repair_gdscript_v2.py scripts/build_terrain.gd")

	# ------------------------------------------------------------------
	# CHECK 4: canopy node
	# ------------------------------------------------------------------
	# WHY: canopy also runtime-loaded. Always WARN.
	# FIX-G: find_children with empty type string (search by name pattern only).
	# Source (Tier 2): https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-find-children
	print("\n[VALIDATE] Canopy:")
	var canopy_results: Array = scene.find_children("*canopy*", "", true, false)
	if canopy_results.is_empty():
		canopy_results = scene.find_children("*parachute*", "", true, false)
	if canopy_results.is_empty():
		canopy_results = scene.find_children("*sanitized*", "", true, false)

	if canopy_results.is_empty():
		print("[WARN] No canopy node in editor scene (expected — runtime loaded).")
		print("       Run game, check: [VERBATIM] Clean GLB loaded from: ...")
		print("       After FIX-B: scale should be Vector3(3.0, 2.0, 3.0).")
		warn_count += 1
	else:
		var canopy: Node = canopy_results[0]
		print("[PASS] Canopy: '%s' (%s)" % [canopy.name, canopy.get_class()])
		pass_count += 1
		if canopy is Node3D:
			var s: Vector3 = canopy.scale
			print("[INFO] Canopy scale: %s" % s)
			if s.length() < 0.5:
				print("[FAIL] Canopy scale ~zero — invisible when deployed. FIX-B should set (3,2,3).")
				fail_count += 1
			else:
				print("[PASS] Canopy scale non-zero.")
				pass_count += 1

	# ------------------------------------------------------------------
	# CHECK 5: ScreenshotLibrary autoload
	# ------------------------------------------------------------------
	# WHY: Engine.has_singleton() only checks C++ singletons, NOT GDScript autoloads.
	#      GDScript autoloads register under ProjectSettings "autoload/Name".
	# Source (Tier 2 — ProjectSettings.has_setting):
	#   https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-has-setting
	# Source (Tier 2 — Godot AutoLoad):
	#   https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
	print("\n[VALIDATE] ScreenshotLibrary autoload:")
	if ProjectSettings.has_setting("autoload/ScreenshotLibrary"):
		print("[PASS] ScreenshotLibrary registered: %s" % str(ProjectSettings.get_setting("autoload/ScreenshotLibrary")))
		pass_count += 1
	else:
		print("[WARN] ScreenshotLibrary not in ProjectSettings autoloads.")
		print("       Project -> Project Settings -> AutoLoad -> add ScreenshotLibrary")
		warn_count += 1

	# ------------------------------------------------------------------
	# CHECK 6: project.godot exists with [input] section
	# ------------------------------------------------------------------
	# Source (Tier 2 — FileAccess):
	#   https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
	print("\n[VALIDATE] project.godot:")
	if FileAccess.file_exists("res://project.godot"):
		var f: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
		var contents: String = f.get_as_text()
		f.close()
		if "[input]" in contents:
			print("[PASS] project.godot exists with [input] section.")
			pass_count += 1
		else:
			print("[WARN] project.godot has no [input] section.")
			warn_count += 1
	else:
		print("[FAIL] project.godot not found at res://project.godot")
		fail_count += 1

	# ------------------------------------------------------------------
	# SUMMARY
	# ------------------------------------------------------------------
	print("\n" + "=".repeat(60))
	print("[VALIDATE] SUMMARY: %d PASS  %d WARN  %d FAIL" % [pass_count, warn_count, fail_count])
	if fail_count == 0:
		if warn_count == 0:
			print("[VALIDATE] ALL CHECKS PASSED.")
		else:
			print("[VALIDATE] No FAILs. WARNs for character/camera/canopy are EXPECTED")
			print("           (those nodes are created at runtime, not in editor scene).")
			print("           Only InputMap FAILs need fixing before running the game.")
	else:
		print("[VALIDATE] %d FAILURE(S). Fix InputMap FAILs before running." % fail_count)
		print("           Run: python3 addons/gd_repair/repair_gdscript_v2.py scripts/build_terrain.gd")
	print("=".repeat(60))
# IMPLEMENTATION COMPLETE
