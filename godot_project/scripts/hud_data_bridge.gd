extends Node
# Example: call ForensicHUD.update_stats() from your main game loop.
# Attach this script to any node that has access to altitude, speed, etc.

func _ready() -> void:
	# You can call this from _physics_process or signals.
	pass

func push_example_data() -> void:
	var data := {
		"alt": 4551,
		"speed": 58,
		"vario": 0.0,
		"level": 0,
		"xp": 0,
		"brg": 108,
		"turns": 0,
		"leg": "BASE",
		"fail": "--",
		"streak": "Press J or SPACE to exit aircraft",
		"label": 5,
		"wind": "12.5 kts @ 240°"
	}
	ForensicHUD.update_stats(data)
