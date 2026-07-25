# CanopyReplay.gd – drives the canopy rigidbody along a recorded track
# Ref: Basis.looking_at() forward axis is -Z (Godot 4 docs)

@tool
class_name CanopyReplay
extends Node

@export var active: bool = false
@export var track: FlightTrack = null
@export var synth_glide_ratio: float = 2.5  # forward/vertical ratio for altimeter tracks
@export var start_at_phase: bool = true  # true = start at freefall_end_idx


func _physics_process(_delta: float) -> void:
	if not active or not track or track.points.is_empty():
		return
	var t = Time.get_unix_time_from_system()  # real time since start
	var state = track.get_state_at_time(t)
	if state.is_empty():
		return
	var target_pos = state["pos"]
	var target_vel = state.get("vel", Vector3.ZERO)
	# Move the parent (which should be a RigidBody3D)
	var body := get_parent()
	if body is RigidBody3D:
		# If track has horizontal data, use that for heading
		if track.points[0].has_horizontal and target_vel.length() > 0.1:
			# Face the direction of travel
			var basis := _safe_basis_toward(
				body.global_position, body.global_position + target_vel, Vector3.UP
			)
			body.global_transform.basis = basis
		# Set position
		body.global_position = target_pos
		# Optionally set linear velocity for collision response
		body.linear_velocity = target_vel
	else:
		# fallback: if body is Node3D, just move
		body.global_position = target_pos


# Safe basis to avoid NaN when looking at near-equal vectors
# Ref: Basis.looking_at() forward axis is -Z, no guard for zero vectors.


func _safe_basis_toward(from: Vector3, to: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	var dir = (to - from).normalized()
	if dir.length() < 0.001:
		return Basis()
	return Basis.looking_at(to, up, false)
