extends Node

func _ready():
	# Defer to avoid blocking startup
	call_deferred("_ensure_hub")

func _ensure_hub():
	# Non-blocking hub startup. Prior versions used OS.<execute-call>()
	# which blocks the main thread on the child process stdout pipe.
	# See:
	#   https://straydragon.github.io/godot-csharp-api-doc/4.3-stable/main/Godot.OS.html
	#   https://docs.godotengine.org/en/stable/classes/class_os.html
	#   https://github.com/godotengine/godot-proposals/discussions/8871
	# Root cause confirmed by live gdb backtrace:
	#   notes/hubmanager_hang_20260804111857.txt
	if OS.get_environment("GODOT_HUB_ALREADY_RUNNING") == "1":
		print("[HubManager] Hub already running (env) - skipping startup")
		return
	var project_dir = ProjectSettings.globalize_path("res://")
	# exec + < /dev/null closes inherited stdin so python3 cannot
	# hold the parent pipe fd open (which was the observed hang).
	var start_cmd = "cd %s/.. && exec python3 forensic_hub_server.py . < /dev/null > /tmp/hub_server.log 2>&1" % project_dir
	var pid = OS.create_process("/bin/sh", ["-c", start_cmd])
	if pid > 0:
		print("[HubManager] Hub spawn requested pid=", pid, " non-blocking")
	else:
		print("[HubManager] Hub spawn failed (create_process returned ", pid, ")")
