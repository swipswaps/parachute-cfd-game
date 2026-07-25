extends Node

var _camera: Camera3D
var _move_speed = 2000.0
var _udp := PacketPeerUDP.new()
var _pattern = [
	Vector3(500.0, 400.0, -800.0), Vector3(500.0, 400.0, 800.0),
	Vector3(200.0, 300.0, 800.0), Vector3(-50.0, 200.0, 200.0),
	Vector3(-50.0, 24.0, 0.0), Vector3(0.0, 0.0, 0.0)
]
var _current_point = 0
var _altitude = 400.0
var _character: Node3D
var _toggle_animator: Node
var _hud_labels := []
var _hud_layer: CanvasLayer
var _focus_label: Label
var _frame_count := 0

func _ready():
	print("[v313] Parachute Landing Pattern Trainer")
	print("[v313] IMPORT RETRY ACTIVE – OBJ fallback for character")
	
	# Terrain
	var file = FileAccess.open("res://assets/terrain/heightmap_512.raw", FileAccess.READ)
	if file:
		var data = file.get_buffer(file.get_length()); file.close()
		# WHY: load pre-baked satellite colours (786432 bytes = 262144 verts * 3 channels)
		#      FileAccess reads raw binary; fallback to empty array if missing
		var _baked := PackedByteArray()
		var _bf = FileAccess.open("res://assets/terrain/baked_colours.bin", FileAccess.READ)
		if _bf:
			_baked = _bf.get_buffer(786432)
			_bf.close()
			print("[v314] BAKED: ", _baked.size(), " bytes loaded")
			print("[v314] BAKED first pixel: RGB(", _baked[0], ",", _baked[1], ",", _baked[2], ")")
		else:
			print("[v314] BAKE FALLBACK: file missing, using elevation colour")
		var verts = []; var uvs = []
		const W = 512; const H = 512; const MAX_ELEV = 80.0; const SCALE_XZ = 4000.0
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
		st.set_color(Color(1.0, 1.0, 1.0, 1.0))  # WHY: registers colour format before first vertex
		for i in range(verts.size()):
			var ci = i * 3
			var cr = float(_baked[ci]) / 255.0
			var cg = float(_baked[ci + 1]) / 255.0
			var cb = float(_baked[ci + 2]) / 255.0
			st.set_color(Color(cr, cg, cb, 1.0))
			st.set_uv(uvs[i]); st.add_vertex(verts[i])
		for idx in indices: st.add_index(idx)
		st.generate_normals()
		var terrain_mesh = st.commit()
		var terrain_inst = MeshInstance3D.new()
		terrain_inst.mesh = terrain_mesh
		
		# texture from v308 proven method
		# WHY: vertex colour proven on Intel IVB gl_compatibility (v295 line 254).
		#      ImageTexture albedo does not render on this hardware/driver combination.
		#      Colour: R=elevation normalized, G=elevation normalized, B=0.1 (terrain tint)
		# Source: apply_fixlist_0295.sh line 254: st.set_color(Color(r, g, 0.1, 1.0))
		var terrain_mat = StandardMaterial3D.new()
		terrain_mat.vertex_color_use_as_albedo = true
		terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		terrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		terrain_inst.material_override = terrain_mat
		print("[v314] Terrain: vertex colour material applied")
		add_child(terrain_inst)
		print("[v313] TERRAIN: ", verts.size(), " verts")
	
	# Runways
	add_child(_create_runway(Vector3(0.0, 24.5, 1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3)))
	add_child(_create_runway(Vector3(0.0, 24.5, -1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3)))
	add_child(_create_runway(Vector3(-800.0, 24.5, 0.0), 1310.0, 23.0, 60.0, Color(0.35, 0.35, 0.35)))
	
	# Camera (v307 fix)
	_camera = Camera3D.new()
	_camera.transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
		Vector3(0.0, 3000.0, 0.0)
	)
	add_child(_camera)
	print("[v313] CAMERA: Top-down Y=3000")
	
	# Character – OBJ loading with fallback
	_load_character()
	
	# HUD
	_hud_layer = CanvasLayer.new(); add_child(_hud_layer)
	_create_hud()
	_create_focus_label()
	
	# Drop zone marker at landing point (0,0,0)
	# WHY: _pattern ends at Vector3(0,0,0) but nothing marks it visually.
	var dz = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.height = 0.5
	cyl.top_radius = 80.0
	cyl.bottom_radius = 80.0
	cyl.radial_segments = 32
	dz.mesh = cyl
	dz.position = Vector3(0.0, 25.0, 0.0)
	var dz_mat = StandardMaterial3D.new()
	dz_mat.albedo_color = Color(1.0, 0.8, 0.0, 0.85)
	dz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dz.material_override = dz_mat
	add_child(dz)
	print("[v314] DROP ZONE: circle at (0,25,0) radius=80")

	# UDP
	_udp.set_dest_address("127.0.0.1", 9999)
	var timer = Timer.new(); timer.wait_time = 0.5; timer.autostart = true
	timer.timeout.connect(_send_kml_update); add_child(timer)
	
	print("[v313] READY ✓")

func _create_runway(pos, length, width, heading, color):
	var box = BoxMesh.new(); box.size = Vector3(width, 0.3, length)
	var mi = MeshInstance3D.new(); mi.mesh = box
	mi.position = pos; mi.rotation_degrees = Vector3(0.0, heading, 0.0)
	var mat = StandardMaterial3D.new(); mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi

func _load_character():
	print("[v313] === CHARACTER LOADING (OBJ fallback) ===")
	_character = Node3D.new()
	_character.name = "Parachutist"
	_character.position = Vector3(0.0, 200.0, 0.0)
	_character.scale = Vector3(5.0, 5.0, 5.0)
	add_child(_character)
	
	var fbx_path = "res://assets/characters/parachutist.fbx"
	var loaded_scene = null

	if FileAccess.file_exists(fbx_path):
		print("[v314] Trying FBX...")
		var res = load(fbx_path)
		# WHY: FBX importer produces PackedScene not Mesh -- instantiate then add
		# Source: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
		if res and res is PackedScene:
			var inst = res.instantiate()
			if inst:
				_character.add_child(inst)
				print("[v314] FBX loaded and instantiated")
				loaded_scene = res
			else:
				print("[v314] FBX instantiate failed")
		else:
			print("[v314] FBX load failed res=", res)
	else:
		print("[v314] FBX file not found: ", fbx_path)

	if loaded_scene == null:
		print("[v314] FALLBACK: Capsule")
		var capsule = MeshInstance3D.new()
		capsule.mesh = CapsuleMesh.new()
		_character.add_child(capsule)

func _create_hud():
	for i in range(5):
		var label = Label.new()
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0, 1.0))
		label.position = Vector2(10.0, 10.0 + i * 25.0)
		_hud_layer.add_child(label)
		_hud_labels.append(label)

func _create_focus_label():
	_focus_label = Label.new()
	_focus_label.text = ">>> CLICK WINDOW TO ENABLE CONTROLS <<<"
	_focus_label.add_theme_font_size_override("font_size", 22)
	_focus_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_focus_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hud_layer.add_child(_focus_label)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		_focus_label.visible = false

func _process(delta):
	_frame_count += 1
	if _frame_count == 2:
		var ts = Time.get_datetime_string_from_system().replace(':', '').replace('-', '')
		var spath = ProjectSettings.globalize_path("res://") + "../audit_logs/screenshots/v314_" + ts + ".png"
		get_viewport().get_texture().get_image().save_png(spath)
		print('[v314] SCREENSHOT: ', spath)
	var move = Vector3.ZERO
	if Input.is_key_pressed(KEY_LEFT):  move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if Input.is_key_pressed(KEY_UP):    move.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):  move.z += 1.0
	_camera.position += move * _move_speed * delta
	if Input.is_key_pressed(KEY_W): _current_point = min(_current_point + 1, _pattern.size() - 1)
	if Input.is_key_pressed(KEY_S): _current_point = max(_current_point - 1, 0)
	if _character and _current_point < _pattern.size():
		var target = _pattern[_current_point]
		_character.position = _character.position.lerp(Vector3(target.x, target.y, target.z), 3.0 * delta)
	# v307 turn response preserved
	if _toggle_animator and _toggle_animator.has_method("get_left_pull"):
		var left = _toggle_animator.get_left_pull()
		var right = _toggle_animator.get_right_pull()
		var turn_input = right - left
		var max_turn_rate = deg_to_rad(35.0)
		var target_yaw = _character.rotation.y + turn_input * max_turn_rate * delta
		_character.rotation.y = lerp(_character.rotation.y, target_yaw, 5.0 * delta)
	_altitude = _pattern[_current_point].y
	_update_hud()

func _update_hud():
	if _hud_labels.size() < 5: return
	var alt_ft = _altitude * 3.28084
	var speed_ms = 50.0
	var heading = 120.0 if _current_point < 2 else (50.0 if _current_point < 4 else 0.0)
	var wind_kts = 8.0
	var left_pct = 0.0
	var right_pct = 0.0
	if _toggle_animator and _toggle_animator.has_method("get_left_pull"):
		left_pct = _toggle_animator.get_left_pull() * 100.0
		right_pct = _toggle_animator.get_right_pull() * 100.0
	_hud_labels[0].text = "ALT: %.0f ft  (%.0f m)" % [alt_ft, _altitude]
	_hud_labels[1].text = "SPD: %.0f kts  (%.0f m/s)" % [speed_ms * 1.94384, speed_ms]
	_hud_labels[2].text = "HDG: %.0f°  WIND: %.0f kts" % [heading, wind_kts]
	_hud_labels[3].text = "LEFT: %.0f%%  RIGHT: %.0f%%" % [left_pct, right_pct]
	_hud_labels[4].text = "HOLD Q=left toggle  E=right toggle"

func _send_kml_update():
	var lat = 29.067 + (_camera.position.z / 111320.0)
	var lon = -81.284 + (_camera.position.x / (111320.0 * cos(deg_to_rad(29.067))))
	var alt = _camera.position.y
	var path = []
	for pt in _pattern:
		var plat = 29.067 + (pt.z / 111320.0)
		var plon = -81.284 + (pt.x / (111320.0 * cos(deg_to_rad(29.067))))
		path.append([plat, plon, pt.y])
	var json_str = JSON.stringify({"lat": lat, "lon": lon, "alt": alt, "path": path})
	_udp.put_packet(json_str.to_ascii_buffer())
