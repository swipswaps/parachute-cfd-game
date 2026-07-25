extends Node

@export var pull_speed: float = 2.5
@export var release_speed: float = 3.5
@export var max_pull_angle: float = 45.0
@export var forward_lean: float = 15.0

var skeleton: Skeleton3D = null
var left_arm_idx: int = -1
var right_arm_idx: int = -1
var left_pull: float = 0.0
var right_pull: float = 0.0


func _ready() -> void:
	print("[ToggleAnimator] Initializing...")
	var parent := get_parent()
	while parent != null:
		skeleton = parent.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			break
		parent = parent.get_parent()
	if not skeleton:
		print("[ToggleAnimator] No Skeleton3D - animation disabled")
		set_process(false)
		return
	print("[ToggleAnimator] Skeleton: ", skeleton.get_bone_count(), " bones")
	var left_names := ["mixamorig:LeftArm", "LeftArm", "Left_Arm", "L_Arm"]
	var right_names := ["mixamorig:RightArm", "RightArm", "Right_Arm", "R_Arm"]
	for name in left_names:
		left_arm_idx = skeleton.find_bone(name)
		if left_arm_idx != -1:
			print("[ToggleAnimator] Left arm: ", name, " [", left_arm_idx, "]")
			break
	for name in right_names:
		right_arm_idx = skeleton.find_bone(name)
		if right_arm_idx != -1:
			print("[ToggleAnimator] Right arm: ", name, " [", right_arm_idx, "]")
			break
	if left_arm_idx == -1 or right_arm_idx == -1:
		print("[ToggleAnimator] Arm bones not found")
		set_process(false)
	else:
		print("[ToggleAnimator] ✓ Ready")


func _process(delta: float) -> void:
	if not skeleton or left_arm_idx == -1 or right_arm_idx == -1:
		return
	var left_input = 1.0 if Input.is_key_pressed(KEY_Q) else 0.0
	var right_input = 1.0 if Input.is_key_pressed(KEY_E) else 0.0
	if left_input > 0.0:
		left_pull = min(left_pull + pull_speed * delta, 1.0)
	else:
		left_pull = max(left_pull - release_speed * delta, 0.0)
	if right_input > 0.0:
		right_pull = min(right_pull + pull_speed * delta, 1.0)
	else:
		right_pull = max(right_pull - release_speed * delta, 0.0)
	_apply_arm_rotation(left_arm_idx, left_pull)
	_apply_arm_rotation(right_arm_idx, right_pull)


func _apply_arm_rotation(bone_idx: int, pull_amount: float) -> void:
	var pitch := deg_to_rad(-pull_amount * max_pull_angle)
	var forward := deg_to_rad(-pull_amount * forward_lean)
	var target_rot = Quaternion.from_euler(Vector3(pitch, 0.0, forward))
	skeleton.set_bone_pose_rotation(bone_idx, target_rot)


func get_left_pull() -> float:
	return left_pull


func get_right_pull() -> float:
	return right_pull
