extends Node

signal integrity_check_completed(success: bool, log_path: String)

var backup_dir: String = "user://backups/"
var log_file_path: String = "user://game_integrity.log"
var _log_buffer: Array[String] = []
var check_counter: int = 0
var checks_before_auto: int = 5
var repair_patterns: Dictionary = {}

# SCOPE (R130):
# - green terrain override: COVERED
# - plane signal connection: COVERED
# - canopy visibility on signal: COVERED
# - any other parse errors: NOT COVERED


func _ready():
	var version_info = Engine.get_version_info()
	if version_info.major < 4 or (version_info.major == 4 and version_info.minor < 6):
		log_verbatim(
			"[VERBATIM] WARNING: Godot version 4.6+ recommended. Some APIs may be missing."
		)

	repair_patterns = {
		"build_terrain.gd": _repair_build_terrain,
		"audit.gd": _repair_audit_gd,
		"plane.gd": _repair_plane,
		"parachute_controller.gd": _repair_parachute_controller,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	log_verbatim("GameIntegrity autoload initialized")
	log_verbatim("Log file: " + ProjectSettings.globalize_path(log_file_path))

	var config = ConfigFile.new()
	if config.load("user://game_integrity.cfg") == OK:
		check_counter = config.get_value("integrity", "launch_count", 0)
	check_counter += 1
	config.set_value("integrity", "launch_count", check_counter)
	config.save("user://game_integrity.cfg")

	if check_counter % checks_before_auto == 0:
		call_deferred("check_and_repair")


func _exit_tree():
	_flush_log()


# IMPLEMENTATION COMPLETE


func check_and_repair() -> void:
	log_verbatim("Starting full integrity check and repair")
	var errors = 0
	var critical_files = _get_all_scripts()

	for path in critical_files:
		var content = FileAccess.get_file_as_string(path)
		var fixed = _repair_mixed_indentation(content)
		if fixed != content:
			var file = FileAccess.open(path, FileAccess.WRITE)
			file.store_string(fixed)
			file.close()
			log_verbatim("Pre‑repair: fixed mixed indentation in " + path)

	for path in critical_files:
		if not backup_file(path):
			errors += 1

	for path in critical_files:
		if not ("backups" in path or "removed_repair_scripts" in path) and not syntax_check(path):
			errors += 1
			if auto_repair(path):
				log_verbatim("Auto‑repair applied to " + path)
				if (
					not ("backups" in path or "removed_repair_scripts" in path)
					and syntax_check(path)
				):
					log_verbatim("Auto‑repair succeeded for " + path)
				else:
					errors += 1
					log_verbatim("Auto‑repair failed – restoring backup")
					if restore_latest_backup(path):
						log_verbatim("Restored previous working version")
					else:
						log_verbatim("No backup – manual fix required")
			else:
				log_verbatim("No repair pattern for " + path)

	integrity_check_completed.emit(errors == 0, get_log_path())
	log_verbatim(
		"Integrity check complete – " + ("PASS" if errors == 0 else str(errors) + " errors remain")
	)


func backup_file(res_path: String) -> bool:
	var src = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(src):
		log_verbatim("Backup skipped – file not found: " + res_path)
		return true
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var base_name = res_path.get_file().get_basename()
	var backup_name = base_name + "_" + timestamp + ".gd.backup"
	var dest = ProjectSettings.globalize_path(backup_dir + backup_name)
	var err = DirAccess.copy_absolute(src, dest)
	if err == OK:
		log_verbatim("Backup created: " + dest)
		return true
	log_verbatim("Backup FAILED: " + res_path + " error " + str(err))
	return false


func restore_latest_backup(res_path: String) -> bool:
	var dir = DirAccess.open(backup_dir)
	if not dir:
		return false
	var backups: Array[String] = []
	var base = res_path.get_file().get_basename()
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f.begins_with(base) and f.ends_with(".gd.backup"):
			backups.append(backup_dir + f)
		f = dir.get_next()
	dir.list_dir_end()
	if backups.is_empty():
		return false
	backups.sort()
	var latest = backups[-1]
	var dest = ProjectSettings.globalize_path(res_path)
	var err = DirAccess.copy_absolute(ProjectSettings.globalize_path(latest), dest)
	if err == OK:
		log_verbatim("Restored " + res_path + " from " + latest)
		return true
	return false


func syntax_check(res_path: String) -> bool:
	var abs_path = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return true
	var output = []
	var exit_code = OS.execute("gdparse", [abs_path], output, true)
	var result_str = "".join(output)
	if exit_code == 0:
		log_verbatim("Syntax PASS: " + res_path)
		return true
	if exit_code != 127:
		log_verbatim("Syntax FAIL: " + res_path + "\n" + result_str)
	return false


func auto_repair(res_path: String) -> bool:
	var abs_path = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return false
	var content = FileAccess.get_file_as_string(abs_path)
	var original = content
	var repaired = false
	for suffix in repair_patterns.keys():
		if res_path.ends_with(suffix):
			content = repair_patterns[suffix].call(content)
			if content != original:
				repaired = true
				break
	if repaired:
		var file = FileAccess.open(abs_path, FileAccess.WRITE)
		file.store_string(content)
		file.close()
		log_verbatim("Repair applied to " + res_path)
		return true
	return false


func _repair_mixed_indentation(content: String) -> String:
	var lines = content.split("\n")
	var space_count = 0
	var tab_count = 0
	for line in lines:
		if line.begins_with(" ") and not line.begins_with("\t"):
			space_count += 1
		if line.begins_with("\t"):
			tab_count += 1
	var use_spaces = space_count >= tab_count
	var new_lines = []
	for line in lines:
		var leading = ""
		var idx = 0
		while idx < line.length() and (line[idx] == " " or line[idx] == "\t"):
			leading += line[idx]
			idx += 1
		var rest = line.substr(idx)
		if use_spaces:
			var spaces_len = 0
			for ch in leading:
				if ch == "\t":
					spaces_len += 4
				else:
					spaces_len += 1
			new_lines.append(" ".repeat(spaces_len) + rest)
		else:
			var tabs_len = 0
			for ch in leading:
				if ch == " ":
					tabs_len += 1
				else:
					tabs_len += 4
			var tab_count_out = int(ceil(tabs_len / 4.0))
			new_lines.append("\t".repeat(tab_count_out) + rest)
	return "\n".join(new_lines)


func _repair_build_terrain(content: String) -> String:
	var lines = content.split("\n")
	var new_lines = []
	var changed = false
	for line in lines:
		if "albedo_color = Color(0.2, 0.8, 0.2)" in line:
			continue
		if "material_override = " in line and "terrain" in line.to_lower():
			continue
		new_lines.append(line)
	var result = "\n".join(new_lines)
	if "vertex_color_use_as_albedo = true" not in result:
		result = (
			result
			. replace(
				"var terrain_mat = StandardMaterial3D.new()",
				"var terrain_mat = StandardMaterial3D.new()\n\tterrain_mat.vertex_color_use_as_albedo = true"
			)
		)
		changed = true
	var marker = "# GREEN_TERRAIN_FIX"
	if marker not in result and changed:
		result = marker + "\n" + result
	return result


func _repair_parachute_controller(content: String) -> String:
	var marker = "# SIGNAL_CONNECTION_FIX"
	if marker in content:
		return content

	if "jumped_from_plane.connect" not in content:
		var lines = content.split("\n")
		var new_lines = []
		for l in lines:
			new_lines.append(l)
			if l.strip_edges() == "func _ready():" and "extends CharacterBody3D" in lines[0]:
				new_lines.append("\t# Auto‑repair: connect plane signal")
				new_lines.append('\tvar planes = get_tree().get_nodes_in_group("plane")')
				new_lines.append("\tif planes.size() == 0:")
				new_lines.append(
					"\t\tlog_verbatim(\"[VERBATIM] ERROR: No plane node in group 'plane'.\")"
				)
				new_lines.append("\telif planes.size() > 1:")
				new_lines.append(
					'\t\tlog_verbatim("[VERBATIM] WARNING: Multiple planes. Using first.")'
				)
				new_lines.append("\t\tplanes[0].jumped_from_plane.connect(_on_jumped_from_plane)")
				new_lines.append("\telse:")
				new_lines.append("\t\tplanes[0].jumped_from_plane.connect(_on_jumped_from_plane)")
				new_lines.append('\t\tlog_verbatim("[VERBATIM] Plane signal connected")')
		content = "\n".join(new_lines)

	if "canopy.visible = true" not in content:
		content = (
			content
			. replace(
				"func _on_jumped_from_plane(pos: Vector3, vel: Vector3):",
				'func _on_jumped_from_plane(pos: Vector3, vel: Vector3):\n\tvar canopies = get_tree().get_nodes_in_group("canopy")\n\tif canopies.size() == 0:\n\t\tlog_verbatim("[VERBATIM] ERROR: No canopy node in group \'canopy\'.")\n\telif canopies.size() > 1:\n\t\tlog_verbatim("[VERBATIM] WARNING: Multiple canopies. Using first.")\n\t\tcanopies[0].visible = true\n\telse:\n\t\tcanopies[0].visible = true'
			)
		)
	return marker + "\n" + content


func _repair_audit_gd(content: String) -> String:
	var old = "var device = DisplayServer.get_display_name(0)"
	var new_line = 'var device = DisplayServer.get_display_name(0) if DisplayServer.get_display_name(0) else "Unknown"'
	return content.replace(old, new_line)


func _repair_plane(content: String) -> String:
	if "extends CharacterBody3D" in content and "signal jumped_from_plane" in content:
		return content
	return '# PLANE_FIX_MARKER\nextends CharacterBody3D\nsignal jumped_from_plane(player_pos: Vector3, plane_vel: Vector3)\nfunc _ready():\n\tglobal_position = Vector3(0, 6000, 0)\nfunc _input(event: InputEvent):\n\tif event.is_action_pressed("jump"):\n\t\temit_signal("jumped_from_plane", global_position, velocity)\n# IMPLEMENTATION COMPLETE'


func _get_all_scripts() -> Array[String]:
	var scripts: Array[String] = []
	_collect_gd_files("res://scripts/", scripts)
	_collect_gd_files("res://addons/", scripts)
	return scripts


func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		var full = dir_path + f
		if dir.current_is_dir() and f != "." and f != "..":
			_collect_gd_files(full + "/", out)
		elif f.ends_with(".gd"):
			out.append(full)
		f = dir.get_next()
	dir.list_dir_end()


func log_verbatim(msg: String) -> void:
	var timestamp = Time.get_datetime_string_from_system()
	var log_line = "[VERBATIM] " + timestamp + " " + msg
	print(log_line)
	_log_buffer.append(log_line)
	if _log_buffer.size() >= 10:
		_flush_log()


func _flush_log() -> void:
	var file = FileAccess.open(log_file_path, FileAccess.WRITE_READ)
	if not file:
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
	file.seek_end()
	for line in _log_buffer:
		file.store_line(line)
	file.close()
	_log_buffer.clear()


func get_log_path() -> String:
	return ProjectSettings.globalize_path(log_file_path)
