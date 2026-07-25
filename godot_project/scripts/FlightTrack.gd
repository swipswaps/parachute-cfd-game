# FlightTrack.gd – normalized in‑engine track format
# Verified against FlySight CSV spec (flysight.ca) and altimeter exports.
# All times in seconds, positions in Godot axes: +X East, +Y Up, -Z North.

class_name FlightTrack
extends Resource

var points: Array[TrackPoint] = []
var freefall_end_idx: int = -1  # index where canopy begins (if detected)


func add_point(t: float, pos: Vector3, vel: Vector3 = Vector3.ZERO, horiz: bool = true) -> void:
	var p := TrackPoint.new()
	p.time = t
	p.pos = pos
	p.vel = vel
	p.has_horizontal = horiz
	points.append(p)


# Binary search interpolation – O(log n)


func get_state_at_time(t: float) -> Dictionary:
	if points.is_empty():
		return {}
	var lo := 0
	var hi := points.size() - 1
	while lo < hi:
		var mid = (lo + hi) >> 1
		if points[mid].time < t:
			lo = mid + 1
		else:
			hi = mid
	var idx = lo
	if idx == 0:
		return {"pos": points[0].pos, "vel": points[0].vel}
	elif idx >= points.size():
		return {"pos": points[-1].pos, "vel": points[-1].vel}
	else:
		var a = points[idx - 1]
		var b = points[idx]
		var frac = clamp((t - a.time) / (b.time - a.time), 0.0, 1.0)
		var pos = a.pos.lerp(b.pos, frac)
		var vel = a.vel.lerp(b.vel, frac) if a.vel and b.vel else Vector3.ZERO
		return {"pos": pos, "vel": vel}


class TrackPoint:
	var time: float
	var pos: Vector3
	var vel: Vector3  # local velocity (body axes) – optional
	var has_horizontal: bool = true
