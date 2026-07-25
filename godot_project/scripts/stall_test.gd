extends Node

func _ready() -> void:
	print("[TEST] Stall test started. Will hang forever.")
	# Infinite loop – Godot will hang, triggering stall detection.
	while true:
		await get_tree().create_timer(0.1).timeout
		print("[TEST] still looping...")
