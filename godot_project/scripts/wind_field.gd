# PATH: godot_project/scripts/wind_field.gd
# WHAT: Loads CFD wind field JSON and provides interpolation for game objects
# WHY:  Parachute needs real-time wind velocity lookup at arbitrary positions
# MENTAL MODEL BEFORE: JSON file on disk with discrete grid points
# MENTAL MODEL AFTER:  Loaded 3D array with trilinear interpolation
# FAILURE MODE: Position outside grid bounds → return zero vector
# VERIFIES WITH: get_wind_at() returns expected velocity near known grid point
#
# Source (Tier 1): Trilinear interpolation for 3D scalar/vector fields
#   Bourke, P. (1999). "Interpolation methods". Swinburne University.
#   Formula: f(x,y,z) = weighted sum of 8 corner values
extends Node

# Wind field data
var grid_spacing: float = 10.0
var dimensions: Vector3i  # nx, ny, nz
var bounds_min: Vector3
var bounds_max: Vector3
var velocities: Array = []  # Flat array of Vector3

# Metadata
var source_case: String = ""
var time_step: String = ""

func _ready():
	# Load wind field on startup
	load_wind_field("res://data/wind_field.json")

func load_wind_field(json_path: String) -> bool:
	"""
	Load CFD wind field from JSON.
	
	MENTAL MODEL: Parse JSON → store as flat array of Vector3 → enable fast indexing
	FAILURE MODE: JSON missing or malformed → return false, velocities empty
	VERIFIES WITH: dimensions set correctly, velocities.size() == nx*ny*nz
	
	Source (Tier 2): Godot FileAccess API - read JSON data
	  https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
	"""
	
	if not FileAccess.file_exists(json_path):
		push_error("Wind field JSON not found: " + json_path)
		return false
	
	var file = FileAccess.open(json_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse wind field JSON")
		return false
	
	var data = json.data
	
	# Extract metadata
	var meta = data["metadata"]
	grid_spacing = meta["grid_spacing"]
	dimensions = Vector3i(meta["dimensions"][0], meta["dimensions"][1], meta["dimensions"][2])
	
	bounds_min = Vector3(meta["bounds"]["x"][0], meta["bounds"]["y"][0], meta["bounds"]["z"][0])
	bounds_max = Vector3(meta["bounds"]["x"][1], meta["bounds"]["y"][1], meta["bounds"]["z"][1])
	
	source_case = meta.get("source_case", "")
	time_step = meta.get("time_step", "")
	
	# Load velocities
	# MENTAL MODEL: Store as flat array matching grid iteration order (k, j, i)
	# Source: Same order as Python export script uses
	velocities.clear()
	for v in data["velocities"]:
		var vel = Vector3(v["vel"][0], v["vel"][1], v["vel"][2])
		velocities.append(vel)
	
	print("Wind field loaded:")
	print("  Grid: %d x %d x %d" % [dimensions.x, dimensions.y, dimensions.z])
	print("  Spacing: %.1f m" % grid_spacing)
	print("  Bounds: " + str(bounds_min) + " to " + str(bounds_max))
	print("  Velocities: %d vectors" % velocities.size())
	
	return true

func get_wind_at(position: Vector3) -> Vector3:
	"""
	Get interpolated wind velocity at arbitrary position.
	
	MENTAL MODEL: Find surrounding 8 grid points → trilinear interpolation
	FAILURE MODE: Position outside bounds → clamp to nearest grid cell
	VERIFIES WITH: Returns smooth velocity field, no discontinuities
	
	Source (Tier 1): Trilinear interpolation weights from fractional grid coordinates
	  w000 = (1-xf)*(1-yf)*(1-zf), w001 = (1-xf)*(1-yf)*zf, etc.
	  Reference: Bourke (1999) "Interpolation methods"
	"""
	
	if velocities.is_empty():
		return Vector3.ZERO
	
	# Clamp to grid bounds
	# MENTAL MODEL: Outside grid → extrapolation unreliable, use boundary value
	var clamped_pos = position.clamp(bounds_min, bounds_max)
	
	# Convert to grid coordinates
	var grid_pos = (clamped_pos - bounds_min) / grid_spacing
	
	# Get integer indices (floor)
	var i0 = int(floor(grid_pos.x))
	var j0 = int(floor(grid_pos.y))
	var k0 = int(floor(grid_pos.z))
	
	# Clamp to valid range
	i0 = clamp(i0, 0, dimensions.x - 2)
	j0 = clamp(j0, 0, dimensions.y - 2)
	k0 = clamp(k0, 0, dimensions.z - 2)
	
	var i1 = i0 + 1
	var j1 = j0 + 1
	var k1 = k0 + 1
	
	# Fractional parts for interpolation
	var xf = grid_pos.x - float(i0)
	var yf = grid_pos.y - float(j0)
	var zf = grid_pos.z - float(k0)
	
	# Get 8 corner velocities
	# MENTAL MODEL: Flat array indexed as [k * ny * nx + j * nx + i]
	# Source: Standard row-major 3D array indexing
	var v000 = velocities[k0 * dimensions.y * dimensions.x + j0 * dimensions.x + i0]
	var v001 = velocities[k1 * dimensions.y * dimensions.x + j0 * dimensions.x + i0]
	var v010 = velocities[k0 * dimensions.y * dimensions.x + j1 * dimensions.x + i0]
	var v011 = velocities[k1 * dimensions.y * dimensions.x + j1 * dimensions.x + i0]
	var v100 = velocities[k0 * dimensions.y * dimensions.x + j0 * dimensions.x + i1]
	var v101 = velocities[k1 * dimensions.y * dimensions.x + j0 * dimensions.x + i1]
	var v110 = velocities[k0 * dimensions.y * dimensions.x + j1 * dimensions.x + i1]
	var v111 = velocities[k1 * dimensions.y * dimensions.x + j1 * dimensions.x + i1]
	
	# Trilinear interpolation
	# Source (Tier 1): Weighted sum of 8 corners based on fractional distance
	var v00 = v000.lerp(v001, zf)
	var v01 = v010.lerp(v011, zf)
	var v10 = v100.lerp(v101, zf)
	var v11 = v110.lerp(v111, zf)
	
	var v0 = v00.lerp(v01, yf)
	var v1 = v10.lerp(v11, yf)
	
	var velocity = v0.lerp(v1, xf)
	
	return velocity

func is_in_bounds(position: Vector3) -> bool:
	"""Check if position is within CFD grid bounds."""
	return (position.x >= bounds_min.x and position.x <= bounds_max.x and
	        position.y >= bounds_min.y and position.y <= bounds_max.y and
	        position.z >= bounds_min.z and position.z <= bounds_max.z)