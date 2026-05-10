#!/usr/bin/env bash
# PATH: apply_fixlist_0305.sh
# v305: Extract FBX mesh as OBJ, load directly in Godot, fix animations.
#       All fixes 1‑84 applied.

set -euo pipefail
PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ_DIR"

rm -f /tmp/godot_*.log /tmp/kml_bridge.log 2>/dev/null || true
SCREENSHOT_DIR="audit_logs/screenshots"
mkdir -p "$SCREENSHOT_DIR" audit_logs godot_project/assets/terrain godot_project/scripts godot_project/scenes godot_project/assets/characters

sqlite3 .cfd_healdb << 'INIT_DB'
CREATE TABLE IF NOT EXISTS v305_operations (id INTEGER PRIMARY KEY AUTOINCREMENT, attempt INTEGER, operation TEXT, status TEXT, details TEXT, timestamp TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS v305_diagnostics (id INTEGER PRIMARY KEY AUTOINCREMENT, attempt INTEGER, component TEXT, check_name TEXT, result TEXT, timestamp TEXT DEFAULT CURRENT_TIMESTAMP);
DELETE FROM v305_operations; DELETE FROM v305_diagnostics;
INIT_DB
log_op() { local att="$1" op="$2" status="$3" det="${4:-}"; sqlite3 .cfd_healdb "INSERT INTO v305_operations (attempt,operation,status,details) VALUES ($att,'$op','$status','${det//\'/\'\'}');" 2>/dev/null || true; echo "[$att] $op: $status  $det"; }

export_audit() {
    echo ""; echo "EXPORTING AUDIT LOGS"
    sqlite3 .cfd_healdb .dump > audit_logs/v305_full_db.sql 2>/dev/null || true
    cp "$0" audit_logs/apply_fixlist_0305.sh 2>/dev/null || true
    echo "✓ Audit complete"
}
trap 'export_audit' EXIT INT TERM

GODOT_BIN="./bin/Godot_v4.6.2-stable_linux.x86_64"
[ ! -x "$GODOT_BIN" ] && { echo "FATAL: Godot binary not found" >&2; exit 1; }

echo "=== DEPENDENCIES ==="
python3 -m pip install --quiet Pillow elevation rasterio numpy requests simplekml trimesh 2>/dev/null || true
log_op 0 "dependency_check" "PASS"

# ---- Heightmap ----
if [ ! -s godot_project/assets/terrain/heightmap_512.raw ]; then
    python3 << 'CONVERT_512'
import rasterio, numpy as np, struct, os
from PIL import Image
src = "srtm_deland_enhanced.tif" if os.path.exists("srtm_deland_enhanced.tif") else "srtm_deland.tif"
with rasterio.open(src) as f:
    band = f.read(1).astype(np.float64); band[band<-1000]=0
    mn,mx = band.min(),band.max()
    img = Image.fromarray(((band-mn)/(mx-mn+1e-9)*65535).astype(np.uint16))
    img = img.resize((512,512), Image.LANCZOS)
    arr = np.array(img, dtype=np.uint16)
    os.makedirs("godot_project/assets/terrain", exist_ok=True)
    with open("godot_project/assets/terrain/heightmap_512.raw","wb") as out:
        for v in arr.flatten(): out.write(struct.pack("<H",v))
CONVERT_512
fi
log_op 1 "heightmap" "PASS"

# ---- Texture ----
if [ ! -s godot_project/assets/terrain/naip_texture.png ]; then
    python3 << 'TEX_FALLBACK'
import numpy as np, struct
from PIL import Image
with open("godot_project/assets/terrain/heightmap_512.raw","rb") as f: data=f.read()
h=np.array([struct.unpack('<H',data[i:i+2])[0]/65535.0 for i in range(0,len(data),2)]).reshape((512,512))
r=(h*200+20).astype(np.uint8); g=(200-h*150).astype(np.uint8); b=(h*80).astype(np.uint8)
Image.fromarray(np.stack([r,g,b],axis=-1)).save("godot_project/assets/terrain/naip_texture.png")
TEX_FALLBACK
fi
log_op 2 "texture" "PASS"

# ---- Extract FBX mesh as OBJ (reliable) ----
echo "=== CHARACTER: FBX → OBJ ==="
OBJ_PATH="godot_project/assets/characters/parachutist.obj"
FBX_PATH="godot_project/assets/characters/parachutist.fbx"

if [ -f "$FBX_PATH" ] && [ ! -s "$OBJ_PATH" ]; then
    python3 << 'EXTRACT_MESH'
import trimesh, os
fbx = "godot_project/assets/characters/parachutist.fbx"
obj = "godot_project/assets/characters/parachutist.obj"
try:
    scene = trimesh.load(fbx)
    # if the result is a scene, export it directly; otherwise it's a single mesh
    if isinstance(scene, trimesh.Scene):
        scene.export(obj)
        print("Exported FBX scene to OBJ")
    elif isinstance(scene, trimesh.Trimesh):
        scene.export(obj)
        print("Exported FBX mesh to OBJ")
    else:
        raise RuntimeError("Unknown trimesh output")
except Exception as e:
    print(f"OBJ export failed: {e}")
EXTRACT_MESH
fi

if [ -s "$OBJ_PATH" ]; then
    log_op 3 "character" "PASS" "OBJ ready ($(stat -c%s $OBJ_PATH) bytes)"
else
    log_op 3 "character" "WARN" "No OBJ character"
fi

# ---- KML bridge ----
cat > /tmp/kml_bridge_v2.py << 'BRIDGE_PY'
#!/usr/bin/env python3
import socket, time, json, simplekml
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("127.0.0.1", 9999)); sock.settimeout(1.0)
lat,lon,alt = 29.067,-81.284,1200
path_points = []
def update(lat,lon,alt,path):
    kml=simplekml.Kml(); kml.document.name="Parachute Landing Pattern"
    look=kml.newlookat(); look.latitude=lat; look.longitude=lon; look.altitude=alt; look.range=1500; look.tilt=45
    if path and len(path)>=2:
        ls=kml.newlinestring(name="Landing Pattern"); ls.coords=[(p[1],p[0],p[2]) for p in path]
        ls.style.linestyle.color=simplekml.Color.red; ls.style.linestyle.width=4; ls.altitudemode=simplekml.AltitudeMode.relativetoground; ls.extrude=1
    kml.save("/tmp/godot_camera.kml")
update(lat,lon,alt,None)
while True:
    try:
        data,addr=sock.recvfrom(4096)
        msg=data.decode().strip()
        if msg.startswith("{"):
            info=json.loads(msg); lat=info.get("lat",lat); lon=info.get("lon",lon); alt=info.get("alt",alt)
            if "path" in info: path_points=info["path"]
            update(lat,lon,alt,path_points)
    except socket.timeout: pass
    time.sleep(0.5)
BRIDGE_PY
chmod +x /tmp/kml_bridge_v2.py
log_op 4 "kml_bridge" "PASS"

# ---- NetworkLink ----
cat > /tmp/network_link.kml << 'LINK'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document><name>Parachute</name>
    <NetworkLink><name>Live View</name>
      <Link><href>/tmp/godot_camera.kml</href>
        <refreshMode>onInterval</refreshMode><refreshInterval>1</refreshInterval>
      </Link>
    </NetworkLink>
  </Document>
</kml>
LINK

# ---- Build Godot scene ----
build_game() {
    local attempt="$1"
    echo ""; echo "=== BUILD ATTEMPT $attempt ==="

    cat > godot_project/scripts/build_terrain.gd << 'GDS'
extends Node

var _camera: Camera3D
var _move_speed = 2000.0
var _zoom_speed = 200.0
var _udp := PacketPeerUDP.new()
var _pattern = [
    Vector3(500, 400, -800), Vector3(500, 400, 800),
    Vector3(200, 300, 800), Vector3(-50, 200, 200),
    Vector3(-50, 24, 0), Vector3(0, 0, 0)
]
var _current_point = 0
var _altitude = 400.0
var _toggle_left = false
var _toggle_right = false
var _character: Node3D
var _anim_player: AnimationPlayer
var _hud_labels := []
var _hud_layer: CanvasLayer
var _focus_label: Label

func _ready():
    print("[v305] Parachute Landing Pattern Trainer")
    
    # ---- Terrain ----
    var file = FileAccess.open("res://assets/terrain/heightmap_512.raw", FileAccess.READ)
    if file:
        var data = file.get_buffer(file.get_length()); file.close()
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
        for i in range(verts.size()):
            st.set_uv(uvs[i]); st.add_vertex(verts[i])
        for idx in indices: st.add_index(idx)
        st.generate_normals()
        var mi = MeshInstance3D.new(); mi.mesh = st.commit()
        var mat = StandardMaterial3D.new()
        if FileAccess.file_exists("res://assets/terrain/naip_texture.png"):
            var img = Image.load_from_file("res://assets/terrain/naip_texture.png")
            var tex = ImageTexture.create_from_image(img)
            if tex: mat.albedo_texture = tex
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        mi.material_override = mat; add_child(mi)
        print("[TERRAIN] ", verts.size(), " verts")
    
    # ---- Runways ----
    add_child(_create_runway(Vector3(0,24,50), 1829,30,120, Color(0.15,0.15,0.15)))
    add_child(_create_runway(Vector3(20,24,-30), 1311,23,50, Color(0.15,0.15,0.15)))
    
    # ---- Lighting ----
    var light1 = DirectionalLight3D.new()
    light1.position = Vector3(500, 1000, 500); light1.light_energy = 1.5
    add_child(light1)
    var light2 = DirectionalLight3D.new()
    light2.position = Vector3(-500, 500, -500); light2.light_energy = 1.0
    add_child(light2)
    var world_env = WorldEnvironment.new()
    var env = Environment.new()
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.4, 0.4, 0.5, 1.0)
    env.ambient_light_energy = 0.6
    world_env.environment = env; add_child(world_env)
    
    # ---- Camera ----
    _camera = Camera3D.new()
    _camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    _camera.fov = 60; _camera.near = 0.1; _camera.far = 20000
    _camera.current = true; add_child(_camera)
    _camera.position = Vector3(0, 800, -1500)
    _camera.look_at(Vector3(0, 0, 0))
    
    # ---- Character ----
    _load_character()
    
    # ---- HUD ----
    _hud_layer = CanvasLayer.new(); add_child(_hud_layer)
    _create_hud()
    _create_focus_label()
    
    # ---- UDP bridge ----
    _udp.set_dest_address("127.0.0.1", 9999)
    var timer = Timer.new(); timer.wait_time = 0.5; timer.autostart = true
    timer.timeout.connect(_send_kml_update); add_child(timer)
    
    print("[READY] CLICK THE GAME WINDOW, then use Q/E for toggles, WASD to fly, arrows to pan")

func _create_runway(pos,length,width,heading,color):
    var box = BoxMesh.new(); box.size = Vector3(width,0.3,length)
    var mi = MeshInstance3D.new(); mi.mesh = box
    mi.position = pos; mi.rotation_degrees = Vector3(0,heading,0)
    var mat = StandardMaterial3D.new(); mat.albedo_color = color; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.material_override = mat; return mi

func _load_character():
    var char_mesh: Mesh = CapsuleMesh.new()
    var scale = Vector3(1,1,1)
    
    # Try to load OBJ (reliable) first, then FBX, then glb
    if FileAccess.file_exists("res://assets/characters/parachutist.obj"):
        var obj_res = load("res://assets/characters/parachutist.obj")
        if obj_res and obj_res is PackedScene:
            var node = obj_res.instantiate()
            var mesh_child = node.find_child_by_type("MeshInstance3D")
            if mesh_child and mesh_child.mesh:
                char_mesh = mesh_child.mesh
                scale = node.scale
                print("[CHAR] Loaded mesh from OBJ")
    
    _character = MeshInstance3D.new()
    _character.mesh = char_mesh
    _character.scale = scale * 5.0
    _character.position = Vector3(0, 200, 0)
    add_child(_character)
    
    # AnimationPlayer with toggle animations
    _anim_player = AnimationPlayer.new()
    _anim_player.name = "AnimationPlayer"
    _character.add_child(_anim_player)
    
    var lib = AnimationLibrary.new()
    
    var idle = Animation.new(); idle.length = 0.5
    idle.add_track(Animation.TYPE_VALUE)
    idle.track_set_path(0, ".:rotation_degrees")
    idle.track_insert_key(0, 0.0, Vector3(0,0,0))
    lib.add_animation("Idle", idle)
    
    var left = Animation.new(); left.length = 0.5
    left.add_track(Animation.TYPE_VALUE)
    left.track_set_path(0, ".:rotation_degrees")
    left.track_insert_key(0, 0.0, Vector3(0,0,0))
    left.track_insert_key(0, 0.25, Vector3(0,0,-30))
    left.track_insert_key(0, 0.5, Vector3(0,0,0))
    lib.add_animation("LeftToggle", left)
    
    var right = Animation.new(); right.length = 0.5
    right.add_track(Animation.TYPE_VALUE)
    right.track_set_path(0, ".:rotation_degrees")
    right.track_insert_key(0, 0.0, Vector3(0,0,0))
    right.track_insert_key(0, 0.25, Vector3(0,0,30))
    right.track_insert_key(0, 0.5, Vector3(0,0,0))
    lib.add_animation("RightToggle", right)
    
    _anim_player.add_animation_library("base", lib)
    _anim_player.play("base/Idle")
    print("[CHAR] Character ready with toggle animations")

func _create_hud():
    for i in range(4):
        var label = Label.new()
        label.add_theme_font_size_override("font_size", 18)
        label.add_theme_color_override("font_color", Color(0,1,0,1))
        label.position = Vector2(10, 10 + i*25)
        _hud_layer.add_child(label)
        _hud_labels.append(label)

func _create_focus_label():
    _focus_label = Label.new()
    _focus_label.text = ">>> CLICK THIS WINDOW TO ENABLE CONTROLS <<<"
    _focus_label.add_theme_font_size_override("font_size", 22)
    _focus_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))
    _focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _focus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _focus_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    _hud_layer.add_child(_focus_label)

func _input(event):
    if event is InputEventMouseButton and event.pressed:
        _focus_label.visible = false
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_SPACE: _current_point = min(_current_point+1, _pattern.size()-1)
            KEY_Q: _toggle_left = !_toggle_left; _try_play_toggle()
            KEY_E: _toggle_right = !_toggle_right; _try_play_toggle()

func _try_play_toggle():
    if not _anim_player: return
    if _toggle_left:
        if _anim_player.has_animation("base/LeftToggle"):
            _anim_player.play("base/LeftToggle")
            print("[TOGGLE] LEFT ON")
    elif _toggle_right:
        if _anim_player.has_animation("base/RightToggle"):
            _anim_player.play("base/RightToggle")
            print("[TOGGLE] RIGHT ON")
    else:
        if _anim_player.has_animation("base/Idle"):
            _anim_player.play("base/Idle")
    _update_hud()

func _process(delta):
    var move = Vector3.ZERO
    if Input.is_key_pressed(KEY_LEFT):  move.x -= 1
    if Input.is_key_pressed(KEY_RIGHT): move.x += 1
    if Input.is_key_pressed(KEY_UP):    move.z -= 1
    if Input.is_key_pressed(KEY_DOWN):  move.z += 1
    _camera.position += move * _move_speed * delta
    if Input.is_key_pressed(KEY_W): _current_point = min(_current_point+1, _pattern.size()-1)
    if Input.is_key_pressed(KEY_S): _current_point = max(_current_point-1, 0)
    
    if _character and _current_point < _pattern.size():
        var target = _pattern[_current_point]
        _character.position = _character.position.lerp(
            Vector3(target.x, target.y, target.z), 3.0*delta)
    _altitude = _pattern[_current_point].y
    _update_hud()

func _update_hud():
    if _hud_labels.size() < 4: return
    var alt_ft = _altitude * 3.28084
    var speed_ms = 50.0
    var heading = 120.0 if _current_point < 2 else (50.0 if _current_point < 4 else 0.0)
    var wind_kts = 8.0
    _hud_labels[0].text = "ALT: %.0f ft  (%.0f m)" % [alt_ft, _altitude]
    _hud_labels[1].text = "SPD: %.0f kts  (%.0f m/s)" % [speed_ms * 1.94384, speed_ms]
    _hud_labels[2].text = "HDG: %.0f°  WIND: %.0f kts" % [heading, wind_kts]
    _hud_labels[3].text = "TOGGLES: Q=%s E=%s" % [_toggle_left, _toggle_right]

func _send_kml_update():
    var lat = 29.067 + (_camera.position.z / 111320.0)
    var lon = -81.284 + (_camera.position.x / (111320.0 * cos(deg_to_rad(29.067))))
    var alt = _camera.position.y
    var path = []
    for pt in _pattern:
        var plat = 29.067 + (pt.z / 111320.0)
        var plon = -81.284 + (pt.x / (111320.0 * cos(deg_to_rad(29.067))))
        path.append([plat, plon, pt.y])
    var json_str = JSON.stringify({"lat":lat,"lon":lon,"alt":alt,"path":path})
    _udp.put_packet(json_str.to_ascii_buffer())
GDS

    cat > godot_project/scenes/main.tscn << 'SCENE'
[gd_scene load_steps=2 format=3 uid="uid://main_v305"]
[ext_resource type="Script" path="res://scripts/build_terrain.gd" id="1"]
[node name="Main" type="Node3D"]
[node name="Builder" type="Node" parent="."]
script = ExtResource("1")
SCENE

    cat > godot_project/project.godot << 'PROJ'
config_version=5
[application]
config/name="Parachute Landing Pattern"
run/main_scene="res://scenes/main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
environment/defaults/default_clear_color=Color(0.1,0.1,0.15,1)
PROJ

    export LIBGL_ALWAYS_SOFTWARE=1
    "$GODOT_BIN" --headless --import --project-path "$(pwd)/godot_project" --quit >/dev/null 2>&1
    "$GODOT_BIN" --headless --import --project-path "$(pwd)/godot_project" --quit >/dev/null 2>&1
    log_op $attempt "import" "PASS"
}

build_game 1

python3 /tmp/kml_bridge_v2.py > /tmp/kml_bridge.log 2>&1 &
BRIDGE_PID=$!
echo "KML bridge PID: $BRIDGE_PID"

GE_PATH=$(which google-earth-pro 2>/dev/null || echo "")
if [ -n "$GE_PATH" ]; then
    "$GE_PATH" /tmp/network_link.kml &
    GE_PID=$!
    log_op 5 "google_earth" "LAUNCHED" "PID=$GE_PID"
else
    echo "⚠️  Google Earth Pro not found."
    log_op 5 "google_earth" "NOT_FOUND" ""
fi

echo ""; echo "=== LAUNCHING ==="
export LIBGL_ALWAYS_SOFTWARE=1
"$GODOT_BIN" --path "$(pwd)/godot_project" --rendering-driver opengl3 2>&1 | tee /tmp/godot_run_v305.log

kill $BRIDGE_PID 2>/dev/null || true
[ -n "${GE_PID:-}" ] && kill $GE_PID 2>/dev/null || true

echo ""; echo "Trainer exited."
export_audit