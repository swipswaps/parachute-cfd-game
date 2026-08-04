#!/usr/bin/env python3
# ============================================================================
# fix_plane_camera.py — three grounded patches to make the plane visible
#
# Bug 1: plane spawns at y=1828.8, should be _PLANE_ALTITUDE (1853.8)
#        line 2659: plane.global_position = Vector3(0, 1828.8, 0)
# Bug 2: _update_camera_position() uses +_cam_distance (positive Z = in front)
#        line 2808: var offset := Vector3(0, 0, _cam_distance)
# Bug 3: _cam_distance reset missing on restart; also not called before initial
#        camera placement
#
# Rules: #6 (precondition guard), #7 (no sed), #9 (read-after-write),
#        #21 (timestamped backup), #29 (exact error absent), #46 (live extract)
# ============================================================================
import sys
import shutil
import datetime

def log_result(op, ok, detail):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {detail}", file=sys.stderr)

TARGET = "godot_project/scripts/build_terrain.gd"

with open(TARGET, "r", encoding="utf-8") as f:
    text = f.read()

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = f"{TARGET}.bak.{ts}"
shutil.copy2(TARGET, backup)
log_result("backup", True, backup)

errors = []

# ── PATCH 1: plane spawn altitude ────────────────────────────────────────────
# Grounded: line 2659 confirmed via diag
OLD1 = "\tplane.global_position = Vector3(0, 1828.8, 0)"
NEW1 = "\tplane.global_position = Vector3(0, _PLANE_ALTITUDE, 0)"
c1 = text.count(OLD1)
if c1 != 1:
    errors.append(f"PATCH1 match={c1} (expected 1)")
else:
    text = text.replace(OLD1, NEW1, 1)
    log_result("patch1_spawn_altitude", True, "plane spawns at _PLANE_ALTITUDE")

# ── PATCH 2: _update_camera_position sign fix ────────────────────────────────
# Grounded: line 2808 confirmed via diag — positive Z puts camera in front
OLD2 = "\tvar offset := Vector3(0, 0, _cam_distance)\n\tvar rot = Quaternion(Vector3.UP, _cam_azimuth) * Quaternion(Vector3.RIGHT, _cam_elevation)"
NEW2 = "\tvar offset := Vector3(0, 0, -_cam_distance)\n\tvar rot = Quaternion(Vector3.UP, _cam_azimuth) * Quaternion(Vector3.RIGHT, _cam_elevation)"
c2 = text.count(OLD2)
if c2 != 1:
    errors.append(f"PATCH2 match={c2} (expected 1)")
else:
    text = text.replace(OLD2, NEW2, 1)
    log_result("patch2_camera_sign", True, "_update_camera_position offset now negative Z")

# ── PATCH 3: call _load_camera_settings before initial camera placement ───────
# Grounded: camera placed at lines 392-404 using _cam_distance=55.0 (default)
# _load_camera_settings() call must come BEFORE the camera block
# Anchor: "# Third-person camera" comment at line 381-382
OLD3 = "\t# --------------------------------------------------------------\n\t# Third\u2011person camera \u2013 child of root, initially follows plane"
NEW3 = "\t_load_camera_settings()  # load DB distance before placing camera\n\t# --------------------------------------------------------------\n\t# Third\u2011person camera \u2013 child of root, initially follows plane"

# The em-dash and non-breaking hyphen may differ — use a safer anchor
OLD3_ALT = "\t# Third\u2011person camera \u2013 child of root, initially follows plane\n\t# Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html"
NEW3_ALT = "\t_load_camera_settings()  # load DB distance before placing camera (line 382 anchor)\n\t# Third\u2011person camera \u2013 child of root, initially follows plane\n\t# Ref: https://docs.godotengine.org/en/stable/classes/class_camera3d.html"

c3 = text.count(OLD3_ALT)
if c3 == 1:
    text = text.replace(OLD3_ALT, NEW3_ALT, 1)
    log_result("patch3_load_settings_early", True, "_load_camera_settings() called before camera placement")
else:
    # Try ASCII-safe anchor: the comment block just before Camera3D.new()
    OLD3_B = "\t# Ensure plane exists before positioning camera\n\tif _plane_node:"
    NEW3_B = "\t_load_camera_settings()  # Rule: load DB value before camera placement\n\t# Ensure plane exists before positioning camera\n\tif _plane_node:"
    c3b = text.count(OLD3_B)
    if c3b == 1:
        text = text.replace(OLD3_B, NEW3_B, 1)
        log_result("patch3_load_settings_early_fallback", True, "used fallback anchor for patch3")
    else:
        errors.append(f"PATCH3 alt match={c3} fallback={c3b} (expected 1 each)")

# ── PATCH 4: reset _cam_distance on restart ──────────────────────────────────
# Grounded: _reset_game() at line 1818 never restores _cam_distance
OLD4 = "func _reset_game() -> void:\n\tprint(\"[DIAG] _reset_game: ENTER\")\n\tprint(\"[VERBATIM] === RESETTING GAME ===\")\n\t_game_state = GameState.IN_PLANE\n\tif _plane_node:\n\t\t_plane_node.visible = true\n\t\t_plane_angle = 0.0\n\t_character.visible = false"
NEW4 = "func _reset_game() -> void:\n\tprint(\"[DIAG] _reset_game: ENTER\")\n\tprint(\"[VERBATIM] === RESETTING GAME ===\")\n\t_game_state = GameState.IN_PLANE\n\t_load_camera_settings()  # restore plane camera distance on restart\n\tif _plane_node:\n\t\t_plane_node.visible = true\n\t\t_plane_angle = 0.0\n\t_character.visible = false"
c4 = text.count(OLD4)
if c4 != 1:
    errors.append(f"PATCH4 match={c4} (expected 1)")
else:
    text = text.replace(OLD4, NEW4, 1)
    log_result("patch4_reset_cam_distance", True, "_load_camera_settings() called on restart")

if errors:
    shutil.copy2(backup, TARGET)
    log_result("ROLLBACK", False, f"restored from backup; errors: {errors}")
    sys.exit(f"PATCH FAILED: {errors}")

# Write
with open(TARGET, "w", encoding="utf-8") as f:
    f.write(text)

# Read-back
with open(TARGET, "r", encoding="utf-8") as f:
    written = f.read()
if written != text:
    shutil.copy2(backup, TARGET)
    log_result("read_after_write", False, "mismatch — restored from backup")
    sys.exit("READ-AFTER-WRITE FAILED")
log_result("read_after_write", True, "verified")

# Verify Bug 2 is fixed (sign now negative)
if "var offset := Vector3(0, 0, _cam_distance)" in written:
    shutil.copy2(backup, TARGET)
    log_result("semantic_check", False, "positive-Z offset still present — restored")
    sys.exit("SEMANTIC CHECK FAILED: positive offset not patched")
log_result("semantic_check", True, "no positive-Z cam offset remaining")

# Verify plane altitude fix
if "plane.global_position = Vector3(0, 1828.8, 0)" in written:
    shutil.copy2(backup, TARGET)
    log_result("semantic_check2", False, "old spawn altitude still present — restored")
    sys.exit("SEMANTIC CHECK FAILED: spawn altitude not patched")
log_result("semantic_check2", True, "plane spawn altitude uses _PLANE_ALTITUDE")

print(f"\nALL PATCHES APPLIED. Backup: {backup}")
print(f"diff {TARGET} {backup}")
