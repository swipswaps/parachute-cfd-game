# gdlint: disable=max-file-lines,function-variable-name,constant-name,unused-argument,max-returns
# build_terrain.gd – final, fully gated, citation‑backed parachute malfunction trainer
# gdlint:ignore=max-file-lines,function-variable-name
# Incorporates camera fixes, canopy attachment, HUD toggle, variometer, and C‑key camera cycles.
# Ref: https://docs.godotengine.org/en/stable/
extends Node
var camera_distance: float = 60.0  # default distance
var camera_target: String = "plane"  # "plane" or "character"
# ------------------------------------------------------------------
# Orbit camera parameters
# ------------------------------------------------------------------
var _cam_distance: float = 55.0  # distance from target
var _cam_azimuth: float = 0.0  # radians, 0 = behind
var _cam_elevation: float = 0.3  # radians, positive = above
# ------------------------------------------------------------------
# Required string (R064)
# ------------------------------------------------------------------
const LegLabel = "LEG"
# ------------------------------------------------------------------
# Game state machine
# Ref: https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html
# ------------------------------------------------------------------
enum GameState {
	IN_PLANE,
	FREEFALL,
	OPENING_ANIM,
	DIAGNOSIS,
	LANDED,
	GAME_OVER,
}
var _game_state: GameState = GameState.IN_PLANE
# Plane orbit (IN_PLANE state)
var _plane_node: Node3D = null
var _plane_angle: float = 0.0
const _PLANE_ORBIT_RADIUS: float = 800.0
const _PLANE_ORBIT_SPEED: float = 0.18
const _PLANE_ALTITUDE: float = 1853.8  # 6000 ft AGL in metres + 25 m ground (was 6025 m)
# ------------------------------------------------------------------
# Core nodes
# ------------------------------------------------------------------
var _camera: Camera3D  # Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
var _character: Node3D  # Ref: https://docs.godotengine.org/en/stable/classes/class_node3d.html
var _hud_labels := []  # Array of Label nodes
var _hud_layer: CanvasLayer  # Ref: https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html
var _focus_label: Label  # Ref: https://docs.godotengine.org/en/stable/classes/class_label.html
var _frame_count := 0
var _pip_viewport: SubViewport  # Ref: https://docs.godotengine.org/en/stable/classes/class_subviewport.html
var _pip_camera: Camera3D
var _pip_canopy_node: Node3D
var _main_canopy_node: Node3D
var _wind_label: Label
var _pip_layer: CanvasLayer  # NEW for layering (R104)
# ------------------------------------------------------------------
# Flight physics
# Ref: https://docs.godotengine.org/en/stable/tutorials/physics/rigid_body.html
# ------------------------------------------------------------------
var _velocity_vec := Vector3.ZERO
var _forward_speed := 0.0
var _turn_input := 0.0
var _max_speed := 30.0
var _accel := 15.0
var _turn_force := 5.0
var _gravity := 9.8
var _descent_rate := 0.0
# ------------------------------------------------------------------
# Landing pattern state machine (R064 required)
# ------------------------------------------------------------------
var _initial_heading := 120.0
var _turn_target_heading := 120.0  # R064
var _turn_rate := 5.0  # R064
enum PatternState {
	DOWNWIND,
	BASE,
	FINAL,
}
var _pattern_state = PatternState.DOWNWIND
var _current_altitude := 1828.8  # R064
# ------------------------------------------------------------------
# Arm bones (Skeleton3D)
# Ref: https://docs.godotengine.org/en/stable/tutorials/animation/using_skeleton3d.html
# ------------------------------------------------------------------
var _skeleton: Skeleton3D
var _left_arm_idx := -1
var _right_arm_idx := -1
var _left_arm_angle := 0.0
var _right_arm_angle := 0.0
var _arm_rotation_step := deg_to_rad(45.0)
# ------------------------------------------------------------------
# Malfunction types & emergency procedure flags
# ------------------------------------------------------------------
enum MalfunctionType {
	GOOD,
	LINE_TWISTS,
	BAG_LOCK,
	LINE_OVER,
	PILOT_IN_TOW,
}
var _malfunction: MalfunctionType = MalfunctionType.GOOD
var _flight_control_checked: bool = false
var _cutaway_done: bool = false
var _reserve_done: bool = false
var _flare_done: bool = false
var _safe_landing: bool = false
var _decision_altitude_warning_shown: bool = false
# Descent rates (ft per frame, ~60 fps)
const DESCENT_RATE_NORMAL: float = 0.44
const DESCENT_RATE_BAGLOCK: float = 0.98
const DESCENT_RATE_GOOD: float = 0.22
# ------------------------------------------------------------------
# 3D Canopy model (repaired GLB) and attachment
# ------------------------------------------------------------------
var _canopy_instance: Node3D
var _canopy_material: StandardMaterial3D
var _canopy_deployed: bool = false
var _headless_auto_jump: bool = false  # set by IN_PLANE headless patch; consumed in _poll_controls
var _headless_auto_deploy: bool = false  # set when headless jump fires; consumed in FREEFALL _poll_controls
var _headless_warp_done: bool = false    # one-shot flag: headless altitude warp
var _deployment_timer
var _screenshot_save_timer: float = 0.0
const DEPLOY_TIME: float = 1.2
# ------------------------------------------------------------------
# Scoring, leaderboard, achievements, missions, etc.
# ------------------------------------------------------------------
var _score: int = 0
var _score_label: Label
var _leaderboard: Array = []
const MAX_LEADERBOARD_ENTRIES: int = 10
enum MissionType {
	TRAINING,
	ADVANCED,
	EXPERT,
}
var _current_mission: MissionType = MissionType.TRAINING
var _mission_objectives: Dictionary = {}
var _mission_completed: bool = false
var _achievements: Dictionary = {
	"first_jump": false,
	"perfect_landing": false,
	"malfunction_ace": false,
	"rapid_ep": false,
}
var _notification_label: Label
# ------------------------------------------------------------------
# Controller support
# Ref: https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html
# ------------------------------------------------------------------
var _controller_connected: bool = false
var _controller_input_map := {
	"turn_left": false,
	"turn_right": false,
	"flightcheck": false,
	"cutaway": false,
	"reserve": false,
	"flare": false,
	"reset": false,
}
# ------------------------------------------------------------------
# Replay system
# ------------------------------------------------------------------
var _replay_recording: Array = []
var _replay_playing: bool = false
var _replay_index: int = 0
# ------------------------------------------------------------------
# Sentry error reporting
# Ref: https://docs.sentry.io/platforms/godot/
# ------------------------------------------------------------------
var _sentry_initialized: bool = false
# ------------------------------------------------------------------
# CFD wind variables
# ------------------------------------------------------------------
var _wind_base_speed: float = 8.0  # kts
var _wind_base_direction: int = 120  # degrees
var _wind_turbulence: float = 2.0
var _wind_gust_time: float = 0.0
var _wind_current_gust: float = 0.0
var _wind_log_timer: float = 0.0  # throttle [WIND] print to 5-second intervals
# ------------------------------------------------------------------
# Procedural objects (buildings and trees – turbines removed per R073)
# ------------------------------------------------------------------
var _buildings: Array = []
var _trees: Array = []
# ------------------------------------------------------------------
# Camera cycling and HUD visibility
# ------------------------------------------------------------------
var _cam_angle_idx: int = 0  # 0=behind,1=side,2=pilot-up,3=chase-close
var _cam_cycle_held: bool = false
var _hud_toggle_held: bool = false
var _initial_paused: bool = true
var _hud_visible: bool = true
# Variometer: rate of change of descent_rate (positive = lift)
var _vario_mps: float = 0.0
var _prev_descent_rate: float = 0.0
# p3: real vario / ground speed, measured from actual motion.
# _get_current_descent_rate() returns a hardcoded constant per state, so
# the old _vario_mps = _prev_descent_rate - _descent_rate was 0.3 - 0.3
# every frame. Proven by autostall_p2_20260802160520.txt: descent_m_s
# read 4.23076923076923 identically on every [GLIDE] row of the run.
# Ref: https://docs.godotengine.org/en/stable/classes/class_node3d.html
# (general knowledge - not retrieved this session)
var _p3_prev_y: float = -99999.0
var _p3_prev_xz: Vector2 = Vector2.ZERO
var _p3_ground_speed_ms: float = 0.0
# ------------------------------------------------------------------
# Polling state for one‑shot actions
# ------------------------------------------------------------------
var _last_frame_keys := {
	"Q": false,
	"E": false,
	"C": false,
	"X": false,
	"V": false,
	"F": false,
	"R": false,
	"UP": false,
	"DOWN": false,
	"LEFT": false,
	"RIGHT": false,
	"W": false,
	"S": false,
	"A": false,
	"D": false,
}
# ------------------------------------------------------------------
# _ready() – initialises terrain, character, camera, HUD, canopy, and environment
# Ref: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-private-method-ready
# ------------------------------------------------------------------
func _ready() -> void:
	camera_distance = 60.0  # reset to default
	_load_camera_settings()
	get_tree().paused = true
	process_mode = PROCESS_MODE_ALWAYS
	print("[INIT] Press SPACE to start")
	print("[DIAG] _ready: ENTER")
	print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _ready gate=none")
	# Loading screen removed – it was blocking the view and useless.
	# _init_screenshot_library()  # optional, can keep
	# _show_loading_screen()      # REMOVED
	# --------------------------------------------------------------
	# Terrain generation (full – uses heightmap and baked colours) with fallback
	# Ref: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
	# --------------------------------------------------------------
	var file = FileAccess.open("res://assets/terrain/heightmap_4096.raw", FileAccess.READ)
	if file:
		# --- Heightmap exists: generate detailed terrain ---
		var data = file.get_buffer(file.get_length())
		file.close()
		var _baked := PackedByteArray()
		var _bf = FileAccess.open("res://assets/terrain/baked_colours_4096.bin", FileAccess.READ)
		if _bf:
			_baked = _bf.get_buffer(_bf.get_length())
			_bf.close()
			print("[VERBATIM] Baked colours loaded: ", _baked.size())
		else:
			print("[VERBATIM] BAKE FALLBACK")
		# 1024 vertex-colour mesh with NED 4096 elevation.
		# Colour source: baked_colours_4096.bin -- NAIP 4096x4096 satellite colour (Pillow-baked)
		# Elevation: heightmap_4096.raw (NED 0.98m/px -- real elevation data).
		const W = 512
		const H = 512
		const HM_SRC = 4096
		const MAX_ELEV = 20.0
		const SCALE_XZ = 4000.0
		var verts := []
		var uvs := []
		for z in range(H):
			for x in range(W):
				var px = (float(x) / float(W - 1) - 0.5) * SCALE_XZ
				var pz = (float(z) / float(H - 1) - 0.5) * SCALE_XZ
				var hm_x := int(float(x) / float(W - 1) * float(HM_SRC - 1))
				var hm_z := int(float(z) / float(H - 1) * float(HM_SRC - 1))
				var hidx := (hm_z * HM_SRC + hm_x) * 2
				var raw = data.decode_u16(hidx) if hidx + 1 < data.size() else 0
				var py = (float(raw) / 65535.0) * MAX_ELEV
				verts.push_back(Vector3(px, py, pz))
				uvs.push_back(Vector2(float(x) / float(W - 1), float(z) / float(H - 1)))
		var indices := []
		for z in range(H - 1):
			for x in range(W - 1):
				var a = z * W + x
				var b = a + 1
				var c = a + W
				var d = c + 1
				indices.append_array([a, c, b, b, c, d])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(1.0, 1.0, 1.0, 1.0))
		for i in range(verts.size()):
			var ci = i * 3
			var cr = float(_baked[ci]) / 255.0 if ci < _baked.size() else 0.5
			var cg = float(_baked[ci + 1]) / 255.0 if ci + 1 < _baked.size() else 0.5
			var cb = float(_baked[ci + 2]) / 255.0 if ci + 2 < _baked.size() else 0.5
			st.set_color(Color(cr, cg, cb, 1.0))
			st.set_uv(uvs[i])
			st.add_vertex(verts[i])
		for idx in indices:
			st.add_index(idx)
		st.generate_normals()
		st.generate_tangents()
		var terrain_mesh = st.commit()
		var terrain_inst := MeshInstance3D.new()
		terrain_inst.mesh = terrain_mesh
		var terrain_mat := StandardMaterial3D.new()
		terrain_mat.vertex_color_use_as_albedo = true
		terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		terrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		terrain_inst.material_override = terrain_mat
		add_child(terrain_inst)
		print("[VERBATIM] Terrain: 1024 vertex-colour, colour=baked_colours_4096.bin, verts: ", verts.size())
	else:
		# --- Heightmap missing: flat terrain fallback ---
		print("[VERBATIM] WARNING: heightmap_512.raw not found – using flat terrain fallback")
		var flat_mesh := PlaneMesh.new()
		flat_mesh.size = Vector2(8000, 8000)
		flat_mesh.subdivide_width = 64
		flat_mesh.subdivide_depth = 64
		var flat_inst := MeshInstance3D.new()
		flat_inst.mesh = flat_mesh
		var flat_mat := StandardMaterial3D.new()
		flat_mat.albedo_color = Color(0.2, 0.5, 0.15)
		flat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat_inst.material_override = flat_mat
		add_child(flat_inst)
		print("[VERBATIM] Flat terrain fallback created")
	# --------------------------------------------------------------
	# Runways: placeholder positions removed (did not match KDED layout).
	# Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html
	# TODO: re-add with georeferenced KDED runway 05/23 position/heading
	#   after naip_texture is replaced with a proper GeoTIFF source.
	#   KDED rwy 05/23: heading ~050deg, length ~1219m, width ~23m.
	# --------------------------------------------------------------
	print("[VERBATIM] Runways: placeholder positions disabled pending georef")
	# --------------------------------------------------------------
	# Character (skydiver) – loads FBX with skeleton
	# Ref: https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html
	# --------------------------------------------------------------
	_character = Node3D.new()
	add_child(_character)
	_character.position = Vector3(100.0, 1828.8, -100.0)
	print("[DEBUG] _character position after set: ", _character.position)
	print("[DEBUG] _character global_position: ", _character.global_position)
	_load_character()
	print("[DIAG] _ready: character loaded")
	# --------------------------------------------------------------
	# Plane – must be created before camera look_at
	# --------------------------------------------------------------
	_create_plane()
	_setup_plane_node()
	print("[DIAG] _ready: plane created, _plane_node=", _plane_node)
	# --------------------------------------------------------------
	# Third‑person camera – child of root, initially follows plane
	# Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
	# --------------------------------------------------------------
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 2.0, 3.0)
	_camera.fov = 75.0
	_camera.near = 0.1
	_camera.far = 10000.0
	add_child(_camera)
	# Ensure plane exists before positioning camera
	if _plane_node:
		# Position camera using orbit angles
		var plane_pos = _plane_node.global_position
		var offset = Vector3(0, 0, -_cam_distance)
		offset = offset.rotated(Vector3.UP, _cam_azimuth)
		offset = offset.rotated(Vector3.RIGHT, _cam_elevation)
		_camera.global_position = plane_pos + offset
		_camera.look_at(plane_pos, Vector3.UP)
		_camera.current = true
		_camera.process_mode = PROCESS_MODE_ALWAYS  # allow orbit during pause
		print("[DEBUG] Plane position: ", plane_pos)
		print("[DEBUG] Camera position: ", _camera.global_position)
		print("[DIAG] _ready: camera positioned")
	else:
		print("[ERROR] Plane node is null, camera not positioned.")
		print("[DIAG] _ready: ERROR – plane node null")
	print("[VERBATIM] Camera attached to root, following plane")
	# --------------------------------------------------------------
	# Drop zone (yellow cylinder) – reduced radius
	# Ref: https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html
	# --------------------------------------------------------------
	var dz := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.radial_segments = 32
	dz.mesh = cyl
	dz.position = Vector3(0.0, 25.0, 0.0)
	var dz_mat := StandardMaterial3D.new()
	dz_mat.albedo_color = Color(1.0, 0.8, 0.0, 0.85)
	dz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dz.material_override = dz_mat
	add_child(dz)
	print("[VERBATIM] Drop zone created")
	_load_faa_obstacles()
	# --------------------------------------------------------------
	# HUD (8 lines + score + notification)
	# Ref: https://docs.godotengine.org/en/stable/classes/class_label.html
	# --------------------------------------------------------------
	# if true: return  # REMOVED: was disabling _hud_labels population. Caused _poll_controls() gate (_hud_labels.size()<8) to block all controls. build_terrain.gd:418 fix_hud_gate.py
	if _hud_layer:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 1
	var bg_panel := Panel.new()
	bg_panel.anchor_right = 1.0
	bg_panel.anchor_bottom = 1.0
	var style := StyleBoxEmpty.new()
	bg_panel.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(bg_panel)
	add_child(_hud_layer)
	var font = ThemeDB.fallback_font
	var label_names := ["ALT", "SPD", "HDG", "BRG", "TURN", "LEG", "MALF", "EP"]
	for i in range(8):
		var lbl := Label.new()
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0, 1, 0))
		lbl.position = Vector2(50, 10 + i * 22)
		lbl.custom_minimum_size = Vector2(220, 20)
		lbl.text = label_names[i] + ": --"
		_hud_layer.add_child(lbl)
		_hud_labels.append(lbl)
	var _hud_bg_panel := ColorRect.new()
	_hud_bg_panel.color = Color(0, 0, 0, 0.35)
	_hud_bg_panel.size = Vector2(280, 210)
	_hud_bg_panel.position = Vector2(5, 5)
	_hud_layer.add_child(_hud_bg_panel)
	_score_label = Label.new()
	_score_label.add_theme_font_override("font", font)
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_score_label.position = Vector2(10, 200)
	_hud_layer.add_child(_score_label)
	_notification_label = Label.new()
	_notification_label.add_theme_font_override("font", font)
	_notification_label.add_theme_font_size_override("font_size", 16)
	_notification_label.add_theme_color_override("font_color", Color(1, 0.8, 0))
	_notification_label.position = Vector2(400, 20)
	_hud_layer.add_child(_notification_label)
	_focus_label = Label.new()
	_focus_label.text = ">>> CLICK WINDOW THEN PRESS KEYS: Q/E turn, C FC check, X cutaway, V reserve, F flare, R restart, C cycle views, H toggle HUD <<<"
	_focus_label.add_theme_font_override("font", font)
	_focus_label.add_theme_font_size_override("font_size", 16)
	_focus_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_focus_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hud_layer.add_child(_focus_label)
	print("[VERBATIM] HUD created")
	print("[DIAG] _ready: HUD created, _hud_labels size=", _hud_labels.size())
	# --------------------------------------------------------------
	# Initial heading (parse from HUD, fallback 120)
	# --------------------------------------------------------------
	var heading_text = _hud_labels[2].text
	var parts = heading_text.split("°")
	if parts.size() > 0:
		var sub = parts[0].split(":")
		if sub.size() > 1:
			_initial_heading = float(sub[1].strip_edges())
	_turn_target_heading = _initial_heading
	print("[VERBATIM] Initial heading set to ", _initial_heading)
	# --------------------------------------------------------------
	# Real‑time wind and PiP overlay
	# --------------------------------------------------------------
	_fetch_real_wind()
	_setup_pip_overlay()
	# --------------------------------------------------------------
	# Initialise subsystems
	# --------------------------------------------------------------
	_init_achievements()
	_init_mission()
	_init_leaderboard()
	_init_controller()
	_init_sentry()
	# --------------------------------------------------------------
	# Load the repaired GLB – fallback to procedural dome
	# Ref: https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
	# --------------------------------------------------------------
	var canopy_path = "res://assets/canopy/parachute_sanitized.glb"
	if ResourceLoader.exists(canopy_path):
		var scene = load(canopy_path)
		if scene:
			_canopy_instance = scene.instantiate()
			if _canopy_instance:
				_character.add_child(_canopy_instance)
				_canopy_instance.position = Vector3(0, 3.2, 0)
				_canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
				_canopy_material = StandardMaterial3D.new()
				var _mesh_child := _find_first_mesh(_canopy_instance)
				if _mesh_child:
					_mesh_child.material_override = _canopy_material
				_canopy_instance.visible = false
				print("[VERBATIM] Clean GLB loaded from: ", canopy_path)
			else:
				_create_procedural_canopy()
		else:
			_create_procedural_canopy()
	else:
		print("[VERBATIM] Clean GLB not found – using procedural dome.")
		_create_procedural_canopy()
	# --------------------------------------------------------------
	# Random initial malfunction
	# --------------------------------------------------------------
	_randomize_malfunction()
	print("[VERBATIM] Initial malfunction: ", _malfunction_name())
	print("[VERBATIM] Game ready – press SPACE at ~4000 ft to deploy")
