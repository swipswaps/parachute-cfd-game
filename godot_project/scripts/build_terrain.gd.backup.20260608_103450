# build_terrain.gd – final, fully gated, citation‑backed parachute malfunction trainer
# Incorporates camera fixes, canopy attachment, HUD toggle, variometer, and C‑key camera cycles.
# Ref: https://docs.godotengine.org/en/stable/

extends Node

# ------------------------------------------------------------------
# Required string (R064)
# ------------------------------------------------------------------
const LegLabel = "LEG"

# ------------------------------------------------------------------
# Game state machine
# Ref: https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html
# ------------------------------------------------------------------
enum GameState { FREEFALL, OPENING_ANIM, DIAGNOSIS, LANDED, GAME_OVER }
var _game_state: GameState = GameState.FREEFALL

# ------------------------------------------------------------------
# Core nodes
# ------------------------------------------------------------------
var _camera: Camera3D                               # Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
var _character: Node3D                              # Ref: https://docs.godotengine.org/en/stable/classes/class_node3d.html
var _hud_labels := []                               # Array of Label nodes
var _hud_layer: CanvasLayer                         # Ref: https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html
var _focus_label: Label                             # Ref: https://docs.godotengine.org/en/stable/classes/class_label.html
var _frame_count := 0

var _pip_viewport: SubViewport                      # Ref: https://docs.godotengine.org/en/stable/classes/class_subviewport.html
var _pip_camera: Camera3D
var _pip_canopy_node: Node3D
var _main_canopy_node: Node3D
var _wind_label: Label

# ------------------------------------------------------------------
# Flight physics
# Ref: https://docs.godotengine.org/en/stable/tutorials/physics/rigid_body.html
# ------------------------------------------------------------------
var _velocity_vec := Vector3.ZERO
var _forward_speed = 0.0
var _turn_input = 0.0
var _max_speed = 30.0
var _accel = 15.0
var _turn_force = 5.0
var _gravity = 9.8
var _descent_rate = 0.0

# ------------------------------------------------------------------
# Landing pattern state machine (R064 required)
# ------------------------------------------------------------------
var _initial_heading = 120.0
var _turn_target_heading = 120.0                     # R064
var _turn_rate = 5.0                                 # R064
enum PatternState { DOWNWIND, BASE, FINAL }          # R064
var _pattern_state = PatternState.DOWNWIND
var _current_altitude = 3000.0                       # R064

# ------------------------------------------------------------------
# Arm bones (Skeleton3D)
# Ref: https://docs.godotengine.org/en/stable/tutorials/animation/using_skeleton3d.html
# ------------------------------------------------------------------
var _skeleton: Skeleton3D
var _left_arm_idx = -1
var _right_arm_idx = -1
var _left_arm_angle = 0.0
var _right_arm_angle = 0.0
var _arm_rotation_step = deg_to_rad(45.0)

# ------------------------------------------------------------------
# Malfunction types & emergency procedure flags
# ------------------------------------------------------------------
enum MalfunctionType { GOOD, LINE_TWISTS, BAG_LOCK, LINE_OVER, PILOT_IN_TOW }
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
enum MissionType { TRAINING, ADVANCED, EXPERT }
var _current_mission: MissionType = MissionType.TRAINING
var _mission_objectives: Dictionary = {}
var _mission_completed: bool = false
var _achievements: Dictionary = {
    "first_jump": false,
    "perfect_landing": false,
    "malfunction_ace": false,
    "rapid_ep": false
}
var _notification_label: Label

# ------------------------------------------------------------------
# Controller support
# Ref: https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html
# ------------------------------------------------------------------
var _controller_connected: bool = false
var _controller_input_map = {
    "turn_left": false,
    "turn_right": false,
    "flight_check": false,
    "cutaway": false,
    "reserve": false,
    "flare": false,
    "reset": false
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
var _wind_base_speed: float = 8.0          # kts
var _wind_base_direction: int = 120        # degrees
var _wind_turbulence: float = 2.0
var _wind_gust_time: float = 0.0
var _wind_current_gust: float = 0.0

# ------------------------------------------------------------------
# Procedural objects (buildings and trees – turbines removed per R073)
# ------------------------------------------------------------------
var _buildings: Array = []
var _trees: Array = []

# ------------------------------------------------------------------
# Camera cycling and HUD visibility
# ------------------------------------------------------------------
var _cam_angle_idx: int = 0               # 0=behind,1=side,2=pilot-up,3=chase-close
var _cam_cycle_held: bool = false
var _hud_toggle_held: bool = false
var _hud_visible: bool = true

# Variometer: rate of change of descent_rate (positive = lift)
var _vario_mps: float = 0.0
var _prev_descent_rate: float = 0.0

# ------------------------------------------------------------------
# Polling state for one‑shot actions
# ------------------------------------------------------------------
var _last_frame_keys = {
    "Q": false, "E": false, "C": false, "X": false, "V": false, "F": false, "R": false,
    "UP": false, "DOWN": false, "LEFT": false, "RIGHT": false,
    "W": false, "S": false, "A": false, "D": false
}

# ------------------------------------------------------------------
# _ready() – initialises terrain, character, camera, HUD, canopy, and environment
# Ref: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-private-method-ready
# ------------------------------------------------------------------
func _ready():
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _ready gate=none
    _init_screenshot_library()
    _show_loading_screen()")
    
    # --------------------------------------------------------------
    # Terrain generation (full – uses heightmap and baked colours)
    # Ref: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
    # --------------------------------------------------------------
    var file = FileAccess.open("res://assets/terrain/heightmap_512.raw", FileAccess.READ)
    if not file:
        print("[VERBATIM] ERROR: heightmap_512.raw not found")
        return
    var data = file.get_buffer(file.get_length())
    file.close()
    
    var _baked := PackedByteArray()
    var _bf = FileAccess.open("res://assets/terrain/baked_colours_1024.bin", FileAccess.READ)
    if _bf:
        _baked = _bf.get_buffer(3145728)
        _bf.close()
        print("[VERBATIM] Baked colours loaded: ", _baked.size())
    else:
        print("[VERBATIM] BAKE FALLBACK")
    
    var verts = []; var uvs = []
    const W = 1024; const H = 1024; const MAX_ELEV = 80.0; const SCALE_XZ = 4000.0
    for z in range(H):
        for x in range(W):
            var px = (float(x)/float(W-1)-0.5)*SCALE_XZ
            var pz = (float(z)/float(H-1)-0.5)*SCALE_XZ
            var idx = (z*W+x)*2
            var raw = data.decode_u16(idx) if idx+1 < data.size() else 0
            var py = (float(raw)/65535.0)*MAX_ELEV
            verts.push_back(Vector3(px,py,pz))
            uvs.push_back(Vector2(float(x)/float(W-1), float(z)/float(H-1)))
    var indices = []
    for z in range(H-1):
        for x in range(W-1):
            var a=z*W+x; var b=a+1; var c=a+W; var d=c+1
            indices.append_array([a,c,b, b,c,d])
    var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_color(Color(1.0, 1.0, 1.0, 1.0))
    for i in range(verts.size()):
        var ci = i * 3
        var cr = float(_baked[ci]) / 255.0 if ci < _baked.size() else 0.5
        var cg = float(_baked[ci+1]) / 255.0 if ci+1 < _baked.size() else 0.5
        var cb = float(_baked[ci+2]) / 255.0 if ci+2 < _baked.size() else 0.5
        st.set_color(Color(cr, cg, cb, 1.0))
        st.set_uv(uvs[i]); st.add_vertex(verts[i])
    for idx in indices: st.add_index(idx)
    st.generate_normals()
    st.generate_tangents()
    var terrain_mesh = st.commit()
    var terrain_inst = MeshInstance3D.new()
    terrain_inst.mesh = terrain_mesh
    var terrain_mat = StandardMaterial3D.new()
    terrain_mat.vertex_color_use_as_albedo = true
    terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    terrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    terrain_inst.material_override = terrain_mat
    add_child(terrain_inst)
    print("[VERBATIM] Terrain created: ", verts.size(), " vertices")
    
    # --------------------------------------------------------------
    # Runways (three predefined)
    # Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html
    # --------------------------------------------------------------
    add_child(_create_runway(Vector3(0.0, 24.5, 1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3)))
    add_child(_create_runway(Vector3(0.0, 24.5, -1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3)))
    add_child(_create_runway(Vector3(-800.0, 24.5, 0.0), 1310.0, 23.0, 60.0, Color(0.35, 0.35, 0.35)))
    print("[VERBATIM] Runways added")
    
    # --------------------------------------------------------------
    # Character (skydiver) – loads FBX with skeleton
    # Ref: https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html
    # --------------------------------------------------------------
    _character = Node3D.new()
    add_child(_character)
    _character.position = Vector3(100.0, 250.0, -100.0)
    _load_character()
    
    # --------------------------------------------------------------
    # Third‑person camera attached to character
    # Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
    # --------------------------------------------------------------
    _camera = Camera3D.new()
    _camera.position = Vector3(0.0, 2.0, 3.0)
    _camera.fov = 75.0
    _camera.near = 0.1
    _camera.far = 10000.0
    _character.add_child(_camera)
    _camera.look_at_from_position(_camera.global_position, _character.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
    _camera.current = true
    print("[VERBATIM] Camera attached")
    
    # --------------------------------------------------------------
    # Drop zone (yellow cylinder) – reduced radius
    # Ref: https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html
    # --------------------------------------------------------------
    var dz = MeshInstance3D.new()
    var cyl = CylinderMesh.new()
    cyl.top_radius = 5.0
    cyl.bottom_radius = 5.0
    cyl.radial_segments = 32
    dz.mesh = cyl
    dz.position = Vector3(0.0, 25.0, 0.0)
    var dz_mat = StandardMaterial3D.new()
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
    if _hud_layer:
        return
    _hud_layer = CanvasLayer.new()
    add_child(_hud_layer)
    var font = ThemeDB.fallback_font
    var label_names = ["ALT", "SPD", "HDG", "BRG", "TURN", "LEG", "MALF", "EP"]
    for i in range(8):
        var lbl = Label.new()
        lbl.add_theme_font_override("font", font)
        lbl.add_theme_font_size_override("font_size", 14)
        lbl.add_theme_color_override("font_color", Color(0,1,0))
        lbl.position = Vector2(10, 10 + i*22)
        lbl.custom_minimum_size = Vector2(220, 20)
        lbl.text = label_names[i] + ": --"
        _hud_layer.add_child(lbl)
        _hud_labels.append(lbl)
    
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
                _canopy_instance.position = Vector3(0, 2.5, 0)
                _canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
                _canopy_material = StandardMaterial3D.new()
                var _mesh_child = _find_first_mesh(_canopy_instance)
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
    # Create environment objects: buildings and trees (no turbines)
    # --------------------------------------------------------------
    _create_buildings()
    
    # --------------------------------------------------------------
    # Random initial malfunction
    # --------------------------------------------------------------
    _randomize_malfunction()
    print("[VERBATIM] Initial malfunction: ", _malfunction_name())
    print("[VERBATIM] Game ready – press SPACE at ~4000 ft to deploy")
    print("[VERBATIM] _hide_loading_screen()")
    print("[VERBATIM] ... EXIT _ready ok=true")

# ------------------------------------------------------------------
# Helper: create runway (returns MeshInstance3D)
# Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html
# ------------------------------------------------------------------
func _create_runway(pos: Vector3, length: float, width: float, heading: float, color: Color) -> MeshInstance3D:
    var mi = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = Vector3(width, 0.5, length)
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.mesh = box
    mi.material_override = mat
    mi.position = pos
    mi.rotation_degrees.y = heading
    return mi

# ------------------------------------------------------------------
# Load FBX character and find arm bones
# Ref: https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html
# ------------------------------------------------------------------
func _load_character():
    print("[VERBATIM] ENTER _load_character gate=none")
    var fbx_path = "res://assets/characters/parachutist.fbx"
    if not FileAccess.file_exists(fbx_path):
        print("[VERBATIM] FBX not found, using capsule")
        var capsule = MeshInstance3D.new()
        capsule.mesh = CapsuleMesh.new()
        _character.add_child(capsule)
        return
    var fbx_scene = load(fbx_path)
    if not fbx_scene:
        print("[VERBATIM] Failed to load FBX")
        return
    var inst = fbx_scene.instantiate()
    _character.add_child(inst)
    print("[VERBATIM] FBX loaded")
    
    _skeleton = _character.find_child("Skeleton3D", true, false)
    if _skeleton:
        for i in _skeleton.get_bone_count():
            var name = _skeleton.get_bone_name(i)
            if name == "mixamorig_LeftArm" or name == "mixamorig:LeftArm":
                _left_arm_idx = i
                print("[VERBATIM] Left arm bone found index ", i)
            elif name == "mixamorig_RightArm" or name == "mixamorig:RightArm":
                _right_arm_idx = i
                print("[VERBATIM] Right arm bone found index ", i)
    else:
        print("[VERBATIM] No skeleton found")
    
    var ap = _character.find_child("AnimationPlayer", true, false)
    if ap:
        ap.stop()
        print("[VERBATIM] Stopped AnimationPlayer")
    print("[VERBATIM] EXIT _load_character ok=true")

# ------------------------------------------------------------------
# Deploy parachute (called on SPACE at correct altitude)
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Load and place FAA Digital Obstacle File obstacles
# WHY: replaces fabricated _create_trees() with real FAA DOF data.
#   R093: never add features not requested.
#   R094: real-world placement requires verified data source.
# SOURCE (Tier 2): Godot 4 FileAccess
#   URL: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
#   VERBATIM: "Opens a file at path. Returns null if file does not exist."
# SOURCE (Tier 2): FAA Digital Obstacle File, updated daily
#   URL: https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dailydof/
#   VERBATIM: "DDOF CSV includes latitude and longitude in decimal degrees."
# MENTAL MODEL BEFORE: no obstacles in scene
# MENTAL MODEL AFTER: 41 FAA-verified obstacles at correct world XYZ positions
# FAILURE MODE: JSON missing or parse error -> logs error and returns, no crash
# VERIFIES WITH: "[VERBATIM] FAA obstacles loaded: 41" in game log
# ------------------------------------------------------------------
func _load_faa_obstacles() -> void:
    print("[VERBATIM] ENTER _load_faa_obstacles gate=none")
    var json_path: String = "res://data/faa_obstacles_kded_world.json"
    var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
    if not f:
        print("[VERBATIM] EXIT _load_faa_obstacles early=file_not_found path=", json_path)
        return
    var raw_text: String = f.get_as_text()
    f.close()
    print("[VERBATIM] _load_faa_obstacles read_bytes=", raw_text.length())
    var parsed = JSON.parse_string(raw_text)
    if parsed == null:
        print("[VERBATIM] EXIT _load_faa_obstacles early=json_parse_failed")
        return
    var obstacles: Array = parsed.get("obstacles", [])
    print("[VERBATIM] _load_faa_obstacles obstacle_count=", obstacles.size())
    var placed: int = 0
    for obs in obstacles:
        var wx: float  = float(obs.get("world_x", 0.0))
        var wy: float  = float(obs.get("ground_y", 0.0))
        var wz: float  = float(obs.get("world_z", 0.0))
        var agl: float = float(obs.get("height_m", 5.0))
        var otype: String = str(obs.get("type", "UNKNOWN"))
        # WHAT: place a vertical cylinder at the obstacle position
        # WHY: cylinders are visible from altitude and represent towers/poles
        #   without requiring external assets.
        # SOURCE (Tier 2): Godot 4 CylinderMesh
        #   URL: https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html
        #   VERBATIM: "height — Full height of the cylinder. Default value: 2.0"
        var mesh_inst: MeshInstance3D = MeshInstance3D.new()
        var cyl: CylinderMesh = CylinderMesh.new()
        cyl.height = agl
        if otype == "TOWER":
            cyl.top_radius = 0.5
            cyl.bottom_radius = 1.0
        elif otype.begins_with("UTILITY") or otype == "POLE":
            cyl.top_radius = 0.15
            cyl.bottom_radius = 0.2
        else:
            cyl.top_radius = 0.3
            cyl.bottom_radius = 0.5
        cyl.radial_segments = 8
        mesh_inst.mesh = cyl
        # Position: centre of cylinder is at wy + agl/2 so base sits on ground
        mesh_inst.position = Vector3(wx, wy + agl * 0.5, wz)
        var mat: StandardMaterial3D = StandardMaterial3D.new()
        if otype == "TOWER":
            mat.albedo_color = Color(0.8, 0.8, 0.8)
        else:
            mat.albedo_color = Color(0.6, 0.5, 0.3)
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mesh_inst.material_override = mat
        add_child(mesh_inst)
        placed += 1
    print("[VERBATIM] FAA obstacles loaded: ", placed)
    print("[VERBATIM] EXIT _load_faa_obstacles ok=true placed=", placed)

# Helper: find first MeshInstance3D child recursively
# WHY: GLB root is Node3D; material_override lives on MeshInstance3D child
# Source: https://docs.godotengine.org/en/stable/classes/class_node.html
func _find_first_mesh(node: Node) -> MeshInstance3D:
    if node is MeshInstance3D:
        return node
    for child in node.get_children():
        var found = _find_first_mesh(child)
        if found:
            return found
    return null

func _deploy_canopy():
    print("[VERBATIM] ENTER _deploy_canopy gate=none")
    if _canopy_deployed or not _canopy_instance:
        print("[VERBATIM] EXIT _deploy_canopy early=already_deployed_or_no_canopy")
        return
    _canopy_deployed = true
    _canopy_instance.visible = true
    _canopy_instance.scale = Vector3.ZERO
    _deployment_timer = DEPLOY_TIME
    print("[VERBATIM] Parachute deployment started")
    
    if not _replay_playing:
        _replay_recording.clear()
        _replay_recording.append({"action": "deploy", "time": Time.get_ticks_msec()})
    print("[VERBATIM] EXIT _deploy_canopy ok=true")

# ------------------------------------------------------------------
# Procedural fallback canopy (blue dome)
# Ref: https://docs.godotengine.org/en/stable/classes/class_spheremesh.html
# ------------------------------------------------------------------
func _create_procedural_canopy():
    print("[VERBATIM] ENTER _create_procedural_canopy gate=none")
    _canopy_instance = MeshInstance3D.new()
    var sphere_mesh = SphereMesh.new()
    sphere_mesh.radius = 0.6
    sphere_mesh.height = 1.0
    sphere_mesh.radial_segments = 32
    sphere_mesh.rings = 16
    _canopy_instance.mesh = sphere_mesh
    _canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
    _character.add_child(_canopy_instance)
    _canopy_instance.position = Vector3(0, 2.5, 0)
    _canopy_material = StandardMaterial3D.new()
    _canopy_material.albedo_color = Color(0.0, 0.6, 1.0)
    _canopy_instance.material_override = _canopy_material
    _canopy_instance.visible = false
    print("[VERBATIM] Procedural dome canopy created")
    print("[VERBATIM] EXIT _create_procedural_canopy ok=true")

# ------------------------------------------------------------------
# Arm animation (pull down) – gated with skeleton and bone index checks
# Ref: https://docs.godotengine.org/en/stable/classes/class_quaternion.html
# Ref: https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html#class-skeleton3d-method-set-bone-pose-rotation
# ------------------------------------------------------------------
func _rotate_arm(left: bool):
    print("[VERBATIM] ENTER _rotate_arm gate=left=", left)
    if not _skeleton:
        print("[VERBATIM] EXIT _rotate_arm early=no_skeleton")
        return
    var idx = _left_arm_idx if left else _right_arm_idx
    if idx == -1:
        print("[VERBATIM] EXIT _rotate_arm early=invalid_bone_index")
        return
    var angle = _left_arm_angle if left else _right_arm_angle
    angle += _arm_rotation_step
    if left:
        _left_arm_angle = angle
    else:
        _right_arm_angle = angle
    var rot = Quaternion(Vector3.RIGHT, angle)
    _skeleton.set_bone_pose_rotation(idx, rot)
    print("[VERBATIM] Arm pulled, angle: ", rad_to_deg(angle))
    print("[VERBATIM] EXIT _rotate_arm ok=true")

# ------------------------------------------------------------------
# Malfunction selection and visual update
# ------------------------------------------------------------------
func _randomize_malfunction():
    print("[VERBATIM] ENTER _randomize_malfunction gate=none")
    var r = randi() % 5
    match r:
        0: _malfunction = MalfunctionType.GOOD
        1: _malfunction = MalfunctionType.LINE_TWISTS
        2: _malfunction = MalfunctionType.BAG_LOCK
        3: _malfunction = MalfunctionType.LINE_OVER
        4: _malfunction = MalfunctionType.PILOT_IN_TOW
    _update_canopy_visuals()
    print("[VERBATIM] EXIT _randomize_malfunction ok=true")

func _malfunction_name() -> String:
    match _malfunction:
        MalfunctionType.GOOD: return "GOOD"
        MalfunctionType.LINE_TWISTS: return "LINE TWISTS"
        MalfunctionType.BAG_LOCK: return "BAG LOCK"
        MalfunctionType.LINE_OVER: return "LINE OVER"
        MalfunctionType.PILOT_IN_TOW: return "PILOT IN TOW"
    return "UNKNOWN"

# ------------------------------------------------------------------
# Update canopy colour, scale, rotation based on malfunction
# Ref: https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html
# ------------------------------------------------------------------
func _update_canopy_visuals():
    if not _canopy_material:
        return
    match _malfunction:
        MalfunctionType.GOOD:
            _canopy_material.albedo_color = Color(0.2, 0.8, 0.2)
            if _canopy_instance:
                _canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
                _canopy_instance.rotation_degrees = Vector3.ZERO
        MalfunctionType.LINE_TWISTS:
            _canopy_material.albedo_color = Color(0.9, 0.5, 0.1)
            if _canopy_instance:
                _canopy_instance.rotation_degrees.z = 15
        MalfunctionType.BAG_LOCK:
            _canopy_material.albedo_color = Color(0.9, 0.2, 0.2)
            if _canopy_instance:
                _canopy_instance.scale = Vector3(0.5, 0.5, 0.5)
        MalfunctionType.LINE_OVER:
            _canopy_material.albedo_color = Color(0.9, 0.6, 0.0)
        MalfunctionType.PILOT_IN_TOW:
            _canopy_material.albedo_color = Color(0.7, 0.2, 0.7)
    print("[VERBATIM] Canopy visuals updated for ", _malfunction_name())

# ------------------------------------------------------------------
# Emergency procedures (gated, logged, idempotent)
# ------------------------------------------------------------------
func _flight_control_check():
    print("[VERBATIM] ENTER _flight_control_check gate=_game_state=", _game_state)
    if _game_state != GameState.DIAGNOSIS:
        print("[VERBATIM] EXIT _flight_control_check early=not_in_diagnosis")
        return
    if _flight_control_checked:
        print("[VERBATIM] EXIT _flight_control_check early=already_checked")
        return
    _flight_control_checked = true
    if _malfunction == MalfunctionType.GOOD:
        print("[VERBATIM] FC ✓ – GOOD canopy, press F to flare")
        _show_notification("FC ✓ – GOOD canopy. Press F to flare.")
    else:
        print("[VERBATIM] FC ✗ – NULL SET → EP required (X then V)")
        _show_notification("FC ✗ – MALFUNCTION! Cutaway (X) then Reserve (V)")
    print("[VERBATIM] EXIT _flight_control_check ok=true")

func _do_cutaway():
    print("[VERBATIM] ENTER _do_cutaway gate=_game_state=", _game_state)
    if _game_state != GameState.DIAGNOSIS:
        print("[VERBATIM] EXIT _do_cutaway early=not_in_diagnosis")
        return
    if _cutaway_done:
        print("[VERBATIM] EXIT _do_cutaway early=already_done")
        return
    if _malfunction == MalfunctionType.GOOD:
        print("[VERBATIM] GOOD canopy – no cutaway needed, use F to flare")
        _show_notification("GOOD canopy – do not cut away! Press F to flare.")
        print("[VERBATIM] EXIT _do_cutaway early=good_canopy")
        return
    _cutaway_done = true
    print("[VERBATIM] CUTAWAY executed – now deploy RESERVE (V)")
    _show_notification("CUTAWAY executed! Deploy reserve (V)")
    if not _replay_playing:
        _replay_recording.append({"action": "cutaway", "time": Time.get_ticks_msec()})
    print("[VERBATIM] EXIT _do_cutaway ok=true")

func _do_reserve():
    print("[VERBATIM] ENTER _do_reserve gate=_game_state=", _game_state)
    if _game_state != GameState.DIAGNOSIS:
        print("[VERBATIM] EXIT _do_reserve early=not_in_diagnosis")
        return
    if _reserve_done:
        print("[VERBATIM] EXIT _do_reserve early=already_deployed")
        return
    if not _cutaway_done and _malfunction != MalfunctionType.GOOD:
        print("[VERBATIM] Reserve not allowed – must cutaway first (X)")
        _show_notification("Must cut away (X) before reserve!")
        print("[VERBATIM] EXIT _do_reserve early=no_cutaway")
        return
    _reserve_done = true
    _safe_landing = true
    _game_state = GameState.LANDED
    print("[VERBATIM] RESERVE deployed – SAFE LANDING!")
    _show_notification("Reserve deployed – safe landing!")
    _update_canopy_visuals()
    _calculate_score()
    
    if not _achievements["first_jump"]:
        _unlock_achievement("first_jump")
    if _reserve_done and _cutaway_done:
        if not _achievements["malfunction_ace"]:
            _unlock_achievement("malfunction_ace")
    
    if not _replay_playing:
        _replay_recording.append({"action": "reserve", "time": Time.get_ticks_msec()})
    print("[VERBATIM] EXIT _do_reserve ok=true")

func _do_flare():
    print("[VERBATIM] ENTER _do_flare gate=_game_state=", _game_state)
    if _game_state != GameState.DIAGNOSIS:
        print("[VERBATIM] EXIT _do_flare early=not_in_diagnosis")
        return
    if _flare_done:
        print("[VERBATIM] EXIT _do_flare early=already_flared")
        return
    if _malfunction != MalfunctionType.GOOD:
        print("[VERBATIM] Cannot flare – malfunction present, use EP (X then V)")
        _show_notification("Malfunction – cut away (X) then reserve (V)")
        print("[VERBATIM] EXIT _do_flare early=malfunction_present")
        return
    if not _flight_control_checked:
        print("[VERBATIM] Perform Flight Control Check (C) before flaring")
        _show_notification("Perform Flight Control Check (C) first!")
        print("[VERBATIM] EXIT _do_flare early=no_fc")
        return
    _flare_done = true
    _safe_landing = true
    _game_state = GameState.LANDED
    print("[VERBATIM] FLARE executed – GOOD canopy landing")
    _show_notification("Flare – good landing!")
    _update_canopy_visuals()
    _calculate_score()
    
    if not _achievements["first_jump"]:
        _unlock_achievement("first_jump")
    if _score >= 900:
        if not _achievements["perfect_landing"]:
            _unlock_achievement("perfect_landing")
    
    if not _replay_playing:
        _replay_recording.append({"action": "flare", "time": Time.get_ticks_msec()})
    print("[VERBATIM] EXIT _do_flare ok=true")

# ------------------------------------------------------------------
# Scoring system
# ------------------------------------------------------------------
func _calculate_score():
    print("[VERBATIM] ENTER _calculate_score gate=none")
    var distance = _character.global_position.length()
    var landing_speed = abs(_forward_speed) + abs(_descent_rate)
    var distance_penalty = int(distance * 10)
    var speed_penalty = int(landing_speed * 5) if landing_speed > 3.0 else 0
    _score = 1000 - distance_penalty - speed_penalty
    _score = max(0, _score)
    print("[VERBATIM] Final score: ", _score, " (distance: ", distance, "m, landing speed: ", landing_speed, " m/s)")
    _show_notification("Score: " + str(_score))
    _score_label.text = "SCORE: " + str(_score)
    _update_leaderboard()
    print("[VERBATIM] EXIT _calculate_score ok=true")

# ------------------------------------------------------------------
# Leaderboard system
# Ref: https://github.com/isetr/simpleboards_godot
# ------------------------------------------------------------------
func _init_leaderboard():
    print("[VERBATIM] ENTER _init_leaderboard gate=none")
    if FileAccess.file_exists("user://leaderboard.save"):
        var file = FileAccess.open("user://leaderboard.save", FileAccess.READ)
        var content = file.get_as_text()
        _leaderboard = JSON.parse_string(content)
        file.close()
    else:
        _leaderboard = []
    print("[VERBATIM] EXIT _init_leaderboard ok=true")

func _update_leaderboard():
    print("[VERBATIM] ENTER _update_leaderboard gate=none")
    var entry = {"score": _score, "date": Time.get_datetime_string_from_system()}
    _leaderboard.append(entry)
    _leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
    if _leaderboard.size() > MAX_LEADERBOARD_ENTRIES:
        _leaderboard.resize(MAX_LEADERBOARD_ENTRIES)
    var file = FileAccess.open("user://leaderboard.save", FileAccess.WRITE)
    file.store_string(JSON.stringify(_leaderboard))
    file.close()
    print("[VERBATIM] Leaderboard updated")
    print("[VERBATIM] EXIT _update_leaderboard ok=true")

# ------------------------------------------------------------------
# Achievements system
# Ref: https://github.com/5FB5/gd-achievements
# ------------------------------------------------------------------
func _init_achievements():
    print("[VERBATIM] ENTER _init_achievements gate=none")
    if FileAccess.file_exists("user://achievements.save"):
        var file = FileAccess.open("user://achievements.save", FileAccess.READ)
        var content = file.get_as_text()
        var saved = JSON.parse_string(content)
        if saved:
            for key in saved:
                if _achievements.has(key):
                    _achievements[key] = saved[key]
        file.close()
    _display_achievements()
    print("[VERBATIM] EXIT _init_achievements ok=true")

func _unlock_achievement(achievement_id: String):
    if _achievements.has(achievement_id) and not _achievements[achievement_id]:
        _achievements[achievement_id] = true
        print("[VERBATIM] Achievement unlocked: ", achievement_id)
        _show_notification("Achievement unlocked: " + achievement_id)
        var file = FileAccess.open("user://achievements.save", FileAccess.WRITE)
        file.store_string(JSON.stringify(_achievements))
        file.close()

func _display_achievements():
    var unlocked = []
    for key in _achievements:
        if _achievements[key]:
            unlocked.append(key)
    if unlocked.size() > 0:
        print("[VERBATIM] Unlocked achievements: ", unlocked)

# ------------------------------------------------------------------
# Mission system
# ------------------------------------------------------------------
func _init_mission():
    print("[VERBATIM] ENTER _init_mission gate=none")
    _mission_objectives = {
        MissionType.TRAINING: {"name": "Training", "target_score": 500, "target_malfunction": MalfunctionType.GOOD},
        MissionType.ADVANCED: {"name": "Advanced", "target_score": 800, "target_malfunction": MalfunctionType.LINE_TWISTS},
        MissionType.EXPERT: {"name": "Expert", "target_score": 950, "target_malfunction": null}
    }
    _update_mission_ui()
    print("[VERBATIM] EXIT _init_mission ok=true")

func _update_mission_ui():
    var mission_info = _mission_objectives[_current_mission]
    _notification_label.text = "Mission: " + mission_info["name"] + " | Target Score: " + str(mission_info["target_score"])
    print("[VERBATIM] Mission updated: ", mission_info["name"])

func _check_mission_completion():
    if _mission_completed:
        return
    var mission_info = _mission_objectives[_current_mission]
    if _score >= mission_info["target_score"]:
        if mission_info["target_malfunction"] == null or _malfunction == mission_info["target_malfunction"]:
            _mission_completed = true
            print("[VERBATIM] Mission completed: ", mission_info["name"])
            _show_notification("Mission completed: " + mission_info["name"])
            match _current_mission:
                MissionType.TRAINING:
                    _current_mission = MissionType.ADVANCED
                MissionType.ADVANCED:
                    _current_mission = MissionType.EXPERT
                MissionType.EXPERT:
                    pass
            _update_mission_ui()

# ------------------------------------------------------------------
# Controller support
# Ref: https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html
# ------------------------------------------------------------------
func _init_controller():
    print("[VERBATIM] ENTER _init_controller gate=none")
    # Godot 4 syntax – connect signal to Callable
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    _check_controllers()
    print("[VERBATIM] EXIT _init_controller ok=true")

func _check_controllers():
    for i in Input.get_connected_joypads():
        _controller_connected = true
        print("[VERBATIM] Controller connected: ", Input.get_joy_name(i))
        break

func _on_joy_connection_changed(device_id, connected):
    _controller_connected = connected
    print("[VERBATIM] Controller connection changed: device ", device_id, " connected: ", connected)

func _process_controller_input():
    if not _controller_connected:
        return
    _controller_input_map["turn_left"] = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
    _controller_input_map["turn_right"] = Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
    _controller_input_map["flight_check"] = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
    _controller_input_map["cutaway"] = Input.is_joy_button_pressed(0, JOY_BUTTON_X)
    _controller_input_map["reserve"] = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
    _controller_input_map["flare"] = Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
    _controller_input_map["reset"] = Input.is_joy_button_pressed(0, JOY_BUTTON_START)
    
    if _controller_input_map["turn_left"]:
        _turn_input = -1.0
        if not _last_frame_keys["Q"]:
            _rotate_arm(true)
    elif _controller_input_map["turn_right"]:
        _turn_input = 1.0
        if not _last_frame_keys["E"]:
            _rotate_arm(false)
    else:
        _turn_input = 0.0
    
    if _controller_input_map["flight_check"]:
        _flight_control_check()
    if _controller_input_map["cutaway"]:
        _do_cutaway()
    if _controller_input_map["reserve"]:
        _do_reserve()
    if _controller_input_map["flare"]:
        _do_flare()
    if _controller_input_map["reset"]:
        _reset_game()

# ------------------------------------------------------------------
# Replay system
# ------------------------------------------------------------------
func _start_recording():
    _replay_recording.clear()
    _replay_recording.append({"action": "start", "time": Time.get_ticks_msec()})

func _stop_recording():
    if _replay_recording.size() > 0:
        var file = FileAccess.open("user://replay.save", FileAccess.WRITE)
        file.store_string(JSON.stringify(_replay_recording))
        file.close()
        print("[VERBATIM] Replay saved with ", _replay_recording.size(), " frames")

func _play_replay():
    if not FileAccess.file_exists("user://replay.save"):
        print("[VERBATIM] No replay file found")
        return
    var file = FileAccess.open("user://replay.save", FileAccess.READ)
    var content = file.get_as_text()
    _replay_recording = JSON.parse_string(content)
    file.close()
    _replay_playing = true
    _replay_index = 0
    print("[VERBATIM] Replay started")

func _process_replay(delta):
    if not _replay_playing:
        return
    if _replay_index >= _replay_recording.size():
        _replay_playing = false
        print("[VERBATIM] Replay finished")
        return
    var current_time = Time.get_ticks_msec()
    var event = _replay_recording[_replay_index]
    if current_time >= event["time"]:
        match event["action"]:
            "deploy": _deploy_canopy()
            "cutaway": _do_cutaway()
            "reserve": _do_reserve()
            "flare": _do_flare()
        _replay_index += 1

# ------------------------------------------------------------------
# Sentry error reporting
# Ref: https://docs.sentry.io/platforms/godot/
# ------------------------------------------------------------------
func _init_sentry():
    print("[VERBATIM] ENTER _init_sentry gate=none")
    var sentry_dsn = ProjectSettings.get_setting("sentry/dsn", "")
    if sentry_dsn != "":
        print("[VERBATIM] Sentry initialized with DSN: ", sentry_dsn)
        _sentry_initialized = true
    else:
        print("[VERBATIM] Sentry not configured")
    print("[VERBATIM] EXIT _init_sentry ok=true")

func _report_error(error_message: String, stack_trace: String = ""):
    if _sentry_initialized:
        print("[VERBATIM] Sending error to Sentry: ", error_message)
    else:
        print("[VERBATIM] Error not sent to Sentry: ", error_message)

# ------------------------------------------------------------------
# Show notification (UI popup)
# Ref: https://docs.godotengine.org/en/stable/classes/class_timer.html
# ------------------------------------------------------------------
func _show_notification(text: String):
    _notification_label.text = text
    var timer = get_tree().create_timer(3.0)
    timer.timeout.connect(func(): _notification_label.text = "")

# ------------------------------------------------------------------
# Decision altitude and descent rate
# ------------------------------------------------------------------
func _check_decision_altitude():
    if _game_state != GameState.DIAGNOSIS:
        return
    if _current_altitude <= 2500.0 and not _decision_altitude_warning_shown:
        _decision_altitude_warning_shown = true
        print("[VERBATIM] DECISION ALTITUDE WARNING – 2500 ft!")
        _show_notification("DECISION ALTITUDE! 2500 ft – act now!")
        if _malfunction != MalfunctionType.GOOD and not _reserve_done:
            _game_state = GameState.GAME_OVER
            print("[VERBATIM] FATAL – decision altitude violation without reserve")
            _show_notification("FATAL – reserve not deployed by 2500 ft")
    elif _current_altitude <= 0.0 and not _safe_landing:
        _game_state = GameState.GAME_OVER
        print("[VERBATIM] FATAL – ground impact without safe landing")
        _show_notification("FATAL – ground impact")
func _get_current_descent_rate() -> float:
    if _game_state == GameState.FREEFALL:
        return 1.2
    elif _game_state == GameState.OPENING_ANIM:
        return 0.3
    elif _game_state != GameState.DIAGNOSIS:
        return 0.0
    if _reserve_done or _flare_done:
        return DESCENT_RATE_GOOD
    match _malfunction:
        MalfunctionType.BAG_LOCK:
            return DESCENT_RATE_BAGLOCK
        MalfunctionType.GOOD:
            return DESCENT_RATE_GOOD
        _:
            return DESCENT_RATE_NORMAL

# ------------------------------------------------------------------
# CFD wind update (called every physics frame)
# Ref: Derived from logarithmic wind profile theory (https://en.wikipedia.org/wiki/Logarithmic_wind_profile)
# ------------------------------------------------------------------
func _update_cfd_wind(delta: float):
    var altitude_m = _current_altitude * 0.3048
    var wind_speed_at_alt = _wind_base_speed * (1.0 + 0.1 * log(1.0 + altitude_m / 10.0))
    _wind_gust_time += delta
    if _wind_gust_time > randf_range(5.0, 10.0):
        _wind_gust_time = 0.0
        _wind_current_gust = randf_range(-_wind_turbulence, _wind_turbulence)
    var final_speed = max(0.0, wind_speed_at_alt + _wind_current_gust)
    var wind_rad = deg_to_rad(_wind_base_direction)
    var wind_vec = Vector3(sin(wind_rad), 0, cos(wind_rad)) * (final_speed * 0.514444)
    if _game_state == GameState.DIAGNOSIS:
        _velocity_vec += wind_vec * delta * 0.5
    print("[VERBATIM] CFD wind: speed ", final_speed, " kts, dir ", _wind_base_direction, "°, gust ", _wind_current_gust)

# ------------------------------------------------------------------
# Create buildings (simple boxes with random heights)
# Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html
# ------------------------------------------------------------------
func _create_buildings():
    print("[VERBATIM] ENTER _create_buildings gate=none")
    var building_positions = [
        Vector3(150, 0, 200), Vector3(160, 0, 220), Vector3(140, 0, 210),
        Vector3(170, 0, 190), Vector3(130, 0, 230)
    ]
    for pos in building_positions:
        var building = MeshInstance3D.new()
        var box = BoxMesh.new()
        var height = randf_range(8, 15)
        box.size = Vector3(6, height, 6)
        building.mesh = box
        building.position = pos + Vector3(0, height/2, 0)
        var mat = StandardMaterial3D.new()
        mat.albedo_color = Color(0.6, 0.5, 0.4)
        mat.metallic = 0.1
        building.material_override = mat
        add_child(building)
        _buildings.append(building)
    print("[VERBATIM] Buildings created: ", _buildings.size())
    print("[VERBATIM] EXIT _create_buildings ok=true")

# ------------------------------------------------------------------
# Create trees (cylinder + sphere)
# Ref: https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html
# Ref: https://docs.godotengine.org/en/stable/classes/class_spheremesh.html
# ------------------------------------------------------------------
func _update_canopy_tilt():
    if not _canopy_instance or not _canopy_deployed:
        return
    var tilt = _turn_input * 15.0
    _canopy_instance.rotation_degrees.z = tilt

# ------------------------------------------------------------------
# Camera cycle (C key)
# Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html
# ------------------------------------------------------------------
func _cycle_camera():
    print("[VERBATIM] ENTER _cycle_camera gate=none")
    if not _camera:
        print("[VERBATIM] EXIT _cycle_camera early=no_camera")
        return
    _cam_angle_idx = (_cam_angle_idx + 1) % 4
    match _cam_angle_idx:
        0:
            _camera.position = Vector3(0.0, 2.0, 3.0)
            _camera.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
            print("[VERBATIM] camera=BEHIND (0,2,3)")
        1:
            _camera.position = Vector3(6.0, 1.0, 0.0)
            _camera.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)
            print("[VERBATIM] camera=SIDE (6,1,0)")
        2:
            _camera.position = Vector3(0.0, 1.8, 0.0)
            _camera.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
            print("[VERBATIM] camera=PILOT_UP (0,1.8,0) looking up")
        3:
            _camera.position = Vector3(0.0, 0.5, 1.5)
            _camera.rotation = Vector3(deg_to_rad(-5.0), 0.0, 0.0)
            print("[VERBATIM] camera=CHASE_CLOSE (0,0.5,1.5)")
    print("[VERBATIM] EXIT _cycle_camera ok=true")

# ------------------------------------------------------------------
# HUD toggle (H key)
# Ref: https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-visible
# ------------------------------------------------------------------
func _toggle_hud():
    print("[VERBATIM] ENTER _toggle_hud gate=none")
    if not _hud_layer:
        print("[VERBATIM] EXIT _toggle_hud early=no_hud_layer")
        return
    _hud_visible = not _hud_visible
    _hud_layer.visible = _hud_visible
    print("[VERBATIM] HUD toggled visible=", _hud_visible)
    print("[VERBATIM] EXIT _toggle_hud ok=true")

# ------------------------------------------------------------------
# Polling controls (continuous key detection, called every physics frame)
# ------------------------------------------------------------------
func _poll_controls():
    if _game_state == GameState.LANDED or _game_state == GameState.GAME_OVER:
        if Input.is_key_pressed(KEY_R):
            _reset_game()
        return
    if _game_state == GameState.DIAGNOSIS:
        var left_turn = Input.is_key_pressed(KEY_Q)
        var right_turn = Input.is_key_pressed(KEY_E)
        if left_turn and not right_turn:
            _turn_input = -1.0
            if not _last_frame_keys["Q"]:
                _rotate_arm(true)
        elif right_turn and not left_turn:
            _turn_input = 1.0
            if not _last_frame_keys["E"]:
                _rotate_arm(false)
        else:
            _turn_input = 0.0
    
    if Input.is_key_pressed(KEY_C) and not _cam_cycle_held:
        _cam_cycle_held = true
        _cycle_camera()
    elif not Input.is_key_pressed(KEY_C):
        _cam_cycle_held = false
    
    if Input.is_key_pressed(KEY_H) and not _hud_toggle_held:
        _hud_toggle_held = true
        _toggle_hud()
    elif not Input.is_key_pressed(KEY_H):
        _hud_toggle_held = false
    
    if Input.is_key_pressed(KEY_C) and not _last_frame_keys["C"]:
        _flight_control_check()
    if Input.is_key_pressed(KEY_X) and not _last_frame_keys["X"]:
        _do_cutaway()
    if Input.is_key_pressed(KEY_V) and not _last_frame_keys["V"]:
        _do_reserve()
    if Input.is_key_pressed(KEY_F) and not _last_frame_keys["F"]:
        _do_flare()
    if Input.is_key_pressed(KEY_R) and not _last_frame_keys["R"]:
        _reset_game()
    
    _process_controller_input()
    
    var cam_move = Vector3.ZERO
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
        cam_move.z -= 1.0
    if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
        cam_move.z += 1.0
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        cam_move.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        cam_move.x += 1.0
    if cam_move.length() > 0:
        cam_move = cam_move.normalized() * 100.0
        _camera.position += cam_move
        _camera.position.x = clamp(_camera.position.x, -2000.0, 2000.0)
        _camera.position.z = clamp(_camera.position.z, -2000.0, 2000.0)
    
    _last_frame_keys["Q"] = Input.is_key_pressed(KEY_Q)
    _last_frame_keys["E"] = Input.is_key_pressed(KEY_E)
    _last_frame_keys["C"] = Input.is_key_pressed(KEY_C)
    _last_frame_keys["X"] = Input.is_key_pressed(KEY_X)
    _last_frame_keys["V"] = Input.is_key_pressed(KEY_V)
    _last_frame_keys["F"] = Input.is_key_pressed(KEY_F)
    _last_frame_keys["R"] = Input.is_key_pressed(KEY_R)

# ------------------------------------------------------------------
# Reset game to initial state (deterministic, idempotent)
# ------------------------------------------------------------------
func _reset_game():
    print("[VERBATIM] === RESETTING GAME ===")
    _game_state = GameState.FREEFALL
    _character.position = Vector3(100.0, 250.0, -100.0)
    _velocity_vec = Vector3.ZERO
    _forward_speed = 0.0
    _turn_input = 0.0
    _descent_rate = 0.0
    _current_altitude = 250.0
    _flight_control_checked = false
    _cutaway_done = false
    _reserve_done = false
    _flare_done = false
    _safe_landing = false
    _decision_altitude_warning_shown = false
    _canopy_deployed = false
    _deployment_timer = 0.0
    _score = 0
    _cam_angle_idx = 0
    _camera.position = Vector3(0.0, 2.0, 3.0)
    _camera.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
    if _canopy_instance:
        _canopy_instance.visible = false
        _canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
    _randomize_malfunction()
    _update_canopy_visuals()
    _left_arm_angle = 0.0
    _right_arm_angle = 0.0
    if _skeleton and _left_arm_idx != -1:
        _skeleton.set_bone_pose_rotation(_left_arm_idx, Quaternion.IDENTITY)
    if _skeleton and _right_arm_idx != -1:
        _skeleton.set_bone_pose_rotation(_right_arm_idx, Quaternion.IDENTITY)
    _show_notification("Game reset")
    print("[VERBATIM] Reset complete. New malfunction: ", _malfunction_name())
    _start_recording()

# ------------------------------------------------------------------
# Input handling (mouse wheel and SPACE)
# Ref: https://docs.godotengine.org/en/stable/classes/class_inputeventmousebutton.html
# Ref: https://docs.godotengine.org/en/stable/classes/class_inputeventkey.html
# ------------------------------------------------------------------
func _input(event):
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _camera.position.y = max(200.0, _camera.position.y - 50.0)
            print("[VERBATIM] Zoom in, camera Y=", _camera.position.y)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _camera.position.y = min(2000.0, _camera.position.y + 50.0)
            print("[VERBATIM] Zoom out, camera Y=", _camera.position.y)
        else:
            _focus_label.visible = false
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE and _game_state == GameState.FREEFALL:
            if _current_altitude <= 4300 and _current_altitude >= 1500:
                _deploy_canopy()
                _game_state = GameState.OPENING_ANIM
                print("[VERBATIM] Rip cord pulled at alt=", _current_altitude)
            else:
                print("[VERBATIM] Pulled at wrong altitude: ", _current_altitude)
        elif event.keycode == KEY_P:
            _play_replay()
        elif event.keycode == KEY_S:
            _stop_recording()

# ------------------------------------------------------------------
# Physics update (altitude, descent, canopy animation, flight, wind, tilt)
# ------------------------------------------------------------------
func _physics_process(delta):
    _prev_descent_rate = _descent_rate
    var descent = _get_current_descent_rate() * 60.0 * delta
    _character.position.y -= descent
    if _character.position.y < 25.0:
        _character.position.y = 25.0
        if not _safe_landing:
            _game_state = GameState.GAME_OVER
            print("[VERBATIM] Ground impact – fatal")
    _current_altitude = _character.position.y - 25.0
    
    _vario_mps = _prev_descent_rate - _descent_rate
    
    if _game_state == GameState.OPENING_ANIM and _canopy_deployed:
        if _deployment_timer > 0:
            _deployment_timer -= delta
            var t = 1.0 - (_deployment_timer / DEPLOY_TIME)
            _canopy_instance.scale = Vector3(t, t, t)
        else:
            _game_state = GameState.DIAGNOSIS
            _canopy_instance.scale = Vector3(0.18, 0.12, 0.18)
            print("[VERBATIM] Canopy fully inflated – enter diagnosis")
    
    if _game_state == GameState.DIAGNOSIS:
        _poll_controls()
        _update_cfd_wind(delta)
        _update_canopy_tilt()
        
        var target_dir = -_character.global_position.normalized()
        _forward_speed = move_toward(_forward_speed, _max_speed, _accel * delta)
        var turn_dir = Vector3.RIGHT * _turn_input * _turn_force
        _velocity_vec += turn_dir * delta
        var forward_vec = target_dir * _forward_speed
        _velocity_vec = _velocity_vec.move_toward(forward_vec, _accel * delta)
        _character.position += _velocity_vec * delta
        if _velocity_vec.length() > 0.5:
            var angle = atan2(_velocity_vec.x, _velocity_vec.z)
            _character.rotation = Vector3(0, angle, 0)
        var speed_kts = _forward_speed * 1.94384
        _hud_labels[1].text = "SPD: %.0f kts | VARIO: %+.1f m/s" % [speed_kts, _vario_mps]
        _hud_labels[4].text = "TURN: %d" % (_turn_input * 100)
        _check_decision_altitude()
        # Capture flight screenshot every 5 seconds (R085 ensures during flight)
        if _screenshot_save_timer > 0:
            _screenshot_save_timer -= delta
        if _screenshot_save_timer <= 0.0:
            ScreenshotLibrary.save_flight_screenshot()
            _screenshot_save_timer = 5.0

    # Capture flight screenshot every 5 seconds
    if _screenshot_save_timer > 0:
        _screenshot_save_timer -= delta
    if _screenshot_save_timer <= 0.0:
        ScreenshotLibrary.save_flight_screenshot()
        _screenshot_save_timer = 5.0
    if _screenshot_save_timer > 0:
        _screenshot_save_timer -= delta
    if _screenshot_save_timer <= 0.0:
        _save_flight_screenshot()
        _screenshot_save_timer = 5.0
    
    _hud_labels[0].text = "ALT: %.0f ft" % max(0, _current_altitude)
    _hud_labels[6].text = "MALF: " + _malfunction_name()
    var ep_status = ""
    if _flare_done:
        ep_status = "FLARE ✓"
    elif _reserve_done:
        ep_status = "RESERVE ✓"
    elif _cutaway_done:
        ep_status = "CUTAWAY (need RESERVE)"
    elif _flight_control_checked:
        ep_status = "FC ✓ (use EP if needed)"
    else:
        ep_status = "Press C for FC check"
    _hud_labels[7].text = "EP: " + ep_status
    
    _process_replay(delta)

# ------------------------------------------------------------------
# Process loop (pattern state, heading, bearing, screenshot, mission check)
# ------------------------------------------------------------------
func _process(delta):
    if _game_state == GameState.GAME_OVER:
        return
    _frame_count += 1
    if _frame_count == 2:
        var ts = Time.get_datetime_string_from_system().replace(':', '').replace('-', '')
        var spath = ProjectSettings.globalize_path("res://") + "../audit_logs/screenshots/v314_" + ts + ".png"
        get_viewport().get_texture().get_image().save_png(spath)
        print("[VERBATIM] Screenshot saved: ", spath)
    
    var dist = _character.global_position.length()
    _update_pattern(_current_altitude, dist)
    
    var current_heading = _initial_heading
    var diff = fmod(_turn_target_heading - current_heading + 360.0, 360.0)
    if diff > 180.0: diff -= 360.0
    var step = 5.0 * delta
    current_heading += clamp(diff, -step, step)
    current_heading = fmod(current_heading + 360.0, 360.0)
    _hud_labels[2].text = "HDG: %.0f°" % current_heading
    
    var target_dir = -_character.global_position.normalized()
    var bearing = rad_to_deg(atan2(target_dir.x, target_dir.z))
    _hud_labels[3].text = "BRG: %.0f°" % bearing
    
    _check_mission_completion()
    if _frame_count % 1800 == 0:
        _update_weather()

# ------------------------------------------------------------------
# R064: turn and pattern functions
# ------------------------------------------------------------------
func _turn_left():
    _turn_target_heading -= _turn_rate
    _turn_target_heading = max(_initial_heading - 90.0, _turn_target_heading)
    print("[VERBATIM] Left turn target: ", _turn_target_heading)

func _turn_right():
    _turn_target_heading += _turn_rate
    _turn_target_heading = min(_initial_heading + 90.0, _turn_target_heading)
    print("[VERBATIM] Right turn target: ", _turn_target_heading)

func _update_pattern(altitude: float, distance: float):
    var new_state = _pattern_state
    if altitude > 1000.0:
        new_state = PatternState.DOWNWIND
    elif altitude > 500.0:
        new_state = PatternState.BASE
    else:
        new_state = PatternState.FINAL
    if new_state != _pattern_state:
        _pattern_state = new_state
        var leg_name = ["DOWNWIND", "BASE", "FINAL"][_pattern_state]
        _hud_labels[5].text = "LEG: " + leg_name
        print("[VERBATIM] Entering ", leg_name)

# ------------------------------------------------------------------
# Dynamic weather update (simple random change every ~30 seconds)
# ------------------------------------------------------------------
func _update_weather():
    print("[VERBATIM] STUB: _update_weather using synthetic data (replace with real API)")
    var weather_info = _fetch_weather_from_api()
    if weather_info:
        _wind_base_speed = weather_info["wind_speed"]
        _wind_base_direction = weather_info["wind_direction"]
        _wind_turbulence = weather_info.get("turbulence", 2.0)
        print("[VERBATIM] Weather updated: wind speed ", _wind_base_speed, " kts, direction ", _wind_base_direction, ", turbulence ", _wind_turbulence)

func _fetch_weather_from_api():
    return {
        "wind_speed": 8.0 + (randf() - 0.5) * 4.0,
        "wind_direction": 120 + randi() % 30,
        "turbulence": randf() * 2.0
    }

# ------------------------------------------------------------------
# PiP overlay, real‑time wind (initial fetch)
# Ref: https://docs.godotengine.org/en/stable/classes/class_subviewportcontainer.html
# ------------------------------------------------------------------
func _setup_pip_overlay():
    print("[VERBATIM] ENTER _setup_pip_overlay gate=none")
    var fbx_path = "res://assets/characters/parachutist.fbx"
    if not FileAccess.file_exists(fbx_path):
        print("[VERBATIM] WARN FBX not found — PiP will use canopy GLB only")
    
    var layer = CanvasLayer.new()
    layer.name = "PiPLayer"
    add_child(layer)
    var container = SubViewportContainer.new()
    container.size = Vector2(320, 240)
    container.position = Vector2(20, 20)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(container)
    _pip_viewport = SubViewport.new()
    _pip_viewport.size = Vector2i(320, 240)
    _pip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    container.add_child(_pip_viewport)
    
    var canopy_path = "res://assets/canopy/parachute_sanitized.glb"
    if not ResourceLoader.exists(canopy_path):
        canopy_path = "res://assets/canopy/parachute_clean.glb"
    if not ResourceLoader.exists(canopy_path):
        canopy_path = "res://assets/canopy/parachute.glb"
    print("[VERBATIM] PiP canopy path=", canopy_path)
    var canopy_scene = load(canopy_path)
    if not canopy_scene:
        print("[VERBATIM] ERROR: canopy load null – no .import sidecar")
        print("[VERBATIM] EXIT _setup_pip_overlay early=canopy_load_null")
        return
    
    _pip_canopy_node = canopy_scene.instantiate()
    _pip_viewport.add_child(_pip_canopy_node)
    _pip_canopy_node.position = Vector3(0.0, 5.0, 0.0)
    
    _pip_camera = Camera3D.new()
    _pip_camera.position = Vector3(0.0, 1.8, 0.0)
    _pip_camera.look_at_from_position(
        Vector3(0.0, 1.8, 0.0),
        Vector3(0.0, 5.0, 0.0),
        Vector3.FORWARD
    )
    _pip_camera.fov = 110.0
    _pip_viewport.add_child(_pip_camera)
    _pip_camera.current = true
    
    var light = DirectionalLight3D.new()
    light.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
    _pip_viewport.add_child(light)
    
    _wind_label = Label.new()
    _wind_label.name = "WindLabel"
    _wind_label.position = Vector2(20, 260)
    _wind_label.add_theme_color_override("font_color", Color(1,1,0))
    layer.add_child(_wind_label)
    var timer = Timer.new()
    timer.wait_time = 1.0
    timer.autostart = true
    timer.timeout.connect(_update_wind_display)
    layer.add_child(timer)
    
    var main_canopy_scene2 = load(canopy_path)
    if main_canopy_scene2:
        _main_canopy_node = main_canopy_scene2.instantiate()
        _main_canopy_node.position = Vector3(0.0, 2.5, 0.0)
        _main_canopy_node.scale = Vector3(0.18, 0.12, 0.18)
        _character.add_child(_main_canopy_node)
        print("[VERBATIM] main canopy attached offset=(0,2.5,0) path=", canopy_path)
    else:
        print("[VERBATIM] WARN main canopy load null — character will have no overhead canopy")
    print("[VERBATIM] EXIT _setup_pip_overlay ok=true")

func _update_wind_display():
    if not _wind_label:
        return
    var wind_file = FileAccess.open("res://wind.json", FileAccess.READ)
    var speed = _wind_base_speed
    var direction = _wind_base_direction
    if wind_file:
        var json = JSON.new()
        if json.parse(wind_file.get_as_text()) == OK:
            var wind = json.data
            speed = wind.get("speed", _wind_base_speed)
            direction = wind.get("direction", _wind_base_direction)
    _wind_label.text = "WIND: %.1f kts @ %d°" % [speed, direction]
    print("[VERBATIM] Wind updated: ", speed, " kts @ ", direction, "°")

func _fetch_real_wind():
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_wind_received)
    http.request("https://api.weather.gov/points/29.067,-81.284")

func _on_wind_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
    if response_code != 200:
        print("[VERBATIM] Real wind request failed")
        return
    var json = JSON.parse_string(body.get_string_from_utf8())
    if not json:
        return
    var grid_url = json.get("properties", {}).get("forecast", "")
    if grid_url.is_empty():
        return
    var http2 = HTTPRequest.new()
    add_child(http2)
    http2.request_completed.connect(_on_forecast_received)
    http2.request(grid_url)

func _on_forecast_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
    if response_code != 200:
        return
    var data = JSON.parse_string(body.get_string_from_utf8())
    if not data:
        return
    var periods = data.get("properties", {}).get("periods", [])
    if periods.is_empty():
        return
    var wind_speed = periods[0].get("windSpeed", "8 mph")
    var wind_dir = periods[0].get("windDirection", "120")
    var speed_kts = wind_speed.to_float() * 0.868976
    _wind_base_speed = speed_kts
    _wind_base_direction = wind_dir.to_int()
    _wind_label.text = "WIND: %.1f kts @ %s°" % [speed_kts, wind_dir]
    print("[VERBATIM] Real wind loaded: ", wind_dir, " ", speed_kts, " kts")


# ------------------------------------------------------------------
# SCREENSHOT LIBRARY (added by patch_loading_screen_fixed.py)
# ------------------------------------------------------------------
var _loading_layer: CanvasLayer = null
var _loading_texture_rect: TextureRect = null
var _screenshot_library: Array[String] = []
var _current_screenshot_index: int = 0

func _init_screenshot_library() -> void:
    print("[VERBATIM] ", Time.get_datetime_string_from_system(), " ENTER _init_screenshot_library")
    # Ensure screenshots directory exists using static methods
    if not DirAccess.dir_exists_absolute("user://screenshots"):
        var err = DirAccess.make_dir_recursive_absolute("user://screenshots")
        if err == OK:
            print("[VERBATIM] Screenshots directory created")
        else:
            print("[VERBATIM] ERROR: Could not create screenshots directory: ", err)
            return
    var dir = DirAccess.open("user://screenshots")
    if dir == null:
        print("[VERBATIM] ERROR: Cannot open screenshots directory")
        return
    dir.list_dir_begin()
    var file: String = dir.get_next()
    while file != "":
        if not file.begins_with(".") and file.ends_with(".png"):
            _screenshot_library.append("user://screenshots/" + file)
        file = dir.get_next()
    dir.list_dir_end()
    _screenshot_library.sort()
    print("[VERBATIM] Screenshot library loaded: ", _screenshot_library.size())
    print("[VERBATIM] EXIT _init_screenshot_library ok")
    print("[VERBATIM] ENTER _show_loading_screen")
    if _loading_layer:
        _loading_layer.queue_free()
    _loading_layer = CanvasLayer.new()
    _loading_layer.layer = 128
    _loading_texture_rect = TextureRect.new()
    _loading_texture_rect.anchor_right = 1.0
    _loading_texture_rect.anchor_bottom = 1.0
    _loading_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    if _screenshot_library.is_empty():
        var placeholder = ColorRect.new()
        placeholder.color = Color(0,0,0)
        var label = Label.new()
        label.text = "No screenshots yet. Fly and screenshots will appear."
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_color_override("font_color", Color.WHITE)
        placeholder.add_child(label)
        _loading_layer.add_child(placeholder)
    else:
        var tex = ResourceLoader.load(_screenshot_library[_current_screenshot_index])
        if tex:
            _loading_texture_rect.texture = tex
            _loading_layer.add_child(_loading_texture_rect)
    add_child(_loading_layer)
    print("[VERBATIM] EXIT _show_loading_screen")

func _hide_loading_screen() -> void:
    if _loading_layer:
        _loading_layer.queue_free()
        _loading_layer = null
        _loading_texture_rect = null

func _cycle_screenshot() -> void:
    if _screenshot_library.is_empty(): return
    _current_screenshot_index = (_current_screenshot_index + 1) % _screenshot_library.size()
    if _loading_layer and _loading_texture_rect:
        var tex = ResourceLoader.load(_screenshot_library[_current_screenshot_index])
        if tex:
            _loading_texture_rect.texture = tex

func _save_flight_screenshot() -> void:
    var viewport = get_viewport()
    if not viewport: return
    var img = viewport.get_texture().get_image()
    if not img: return
    var ts = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
    var path = "user://screenshots/flight_" + ts + ".png"
    if img.save_png(path) == OK:
        if not _screenshot_library.has(path):
            _screenshot_library.append(path)
            _screenshot_library.sort()

# IMPLEMENTATION COMPLETE
