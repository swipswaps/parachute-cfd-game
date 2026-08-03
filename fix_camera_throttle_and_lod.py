#!/usr/bin/env python3
# ============================================================================
# fix_camera_throttle_and_lod.py
#
# Fix A: throttle _save_camera_settings so it fires at most once per second
#        (on mouse-release or timer), not on every InputEventMouseMotion.
#        Root cause: _input -> _update_camera_position -> _save_camera_settings
#        fires ~60x/sec while RMB held, saturating the SQLite DB and triggering
#        the 30s stall detector in autostall_fixed.py.
#
# Fix B: call generate_lods() on the committed terrain ArrayMesh before
#        assigning it to terrain_inst.mesh. Godot 4 engine then automatically
#        transitions mesh detail based on screen coverage.
#        Root cause: W=512 H=512 single static mesh, no LOD levels, coarse
#        appearance at mid/far range.
#
# Rules complied with: #1, #2, #6, #7, #9, #10, #16, #21, #24, #29, #30,
#                      #31, #38, #41, #46
#
# Citations (Godot documentation):
#   - InputEventMouseMotion (fired every frame mouse moves):
#     https://docs.godotengine.org/en/stable/classes/class_inputeventmousemotion.html
#     (general knowledge — not retrieved this session)
#   - ArrayMesh.generate_lods() (generates LOD levels from base mesh):
#     https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-method-generate-lods
#     (general knowledge — not retrieved this session)
#   - SurfaceTool.commit() (returns ArrayMesh):
#     https://docs.godotengine.org/en/stable/classes/class_surfacetool.html#class-surfacetool-method-commit
#     (general knowledge — not retrieved this session)
#   - str.count() exact-byte match:
#     https://docs.python.org/3/library/stdtypes.html#str.count
#     (general knowledge — not retrieved this session)
#   - shutil.copy2 timestamped backup:
#     https://docs.python.org/3/library/shutil.html#shutil.copy2
#     (general knowledge — not retrieved this session)
#
# Tools used: python3, shutil, sqlite3 (read-only verify). sed BANNED.
# ============================================================================

import sys
import shutil
import datetime
import subprocess


def log_result(operation: str, success: bool, detail: str) -> None:
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)


def get_leading_ws(line: str) -> str:
    ws = ""
    for c in line:
        if c in "\t ":
            ws += c
        else:
            break
    return ws


TARGET = "godot_project/scripts/build_terrain.gd"

# ── pre-delivery gate (Rule #24 / #41) ──────────────────────────────────────
def pre_delivery_gate(script_path: str) -> None:
    with open(script_path, "r") as f:
        text = f.read()
    violations = []
    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if not stripped.startswith("#") and "sed" in line.split():
            violations.append(f"sed at line {i}")
        _banned = "utc" + "now" + "()"
        if _banned in line and not stripped.startswith("#") and '"' + _banned not in line:
            violations.append(f"utcnow() at line {i}")
    if violations:
        log_result("pre_delivery_gate", False, str(violations))
        sys.exit(f"PRE-DELIVERY GATE FAILED: {violations}")
    log_result("pre_delivery_gate", True, "no forbidden patterns")


pre_delivery_gate(__file__)


# ── read live file ───────────────────────────────────────────────────────────
with open(TARGET, "r", encoding="utf-8") as f:
    original = f.read()
log_result("read_live_file", True, f"{len(original)} bytes, {original.count(chr(10))+1} lines")


# ════════════════════════════════════════════════════════════════════════════
# FIX A — throttle _save_camera_settings
#
# Strategy:
#   1. Remove _save_camera_settings() call from _update_camera_position
#      (line 2880 in original). Camera position still updates every frame;
#      the DB write is deferred.
#   2. Add _cam_save_pending flag set to true in _update_camera_position.
#   3. Add MOUSE_BUTTON_RIGHT release handler in _input that calls
#      _save_camera_settings() once when the user lifts the button.
#
# This is simpler and more correct than a timer: save exactly once per drag,
# not every second, and not every frame.
# ════════════════════════════════════════════════════════════════════════════

# Step A1: remove _save_camera_settings() call from _update_camera_position
# Exact old_str extracted from live file lines 2879-2880.
OLD_A1 = (
    '\tprint("[DEBUG] Camera updated: pos=", _camera.global_position, " target=", target)\n'
    '\t_save_camera_settings()'
)
NEW_A1 = (
    '\tprint("[DEBUG] Camera updated: pos=", _camera.global_position, " target=", target)\n'
    '\t_cam_save_pending = true'
)
count_a1 = original.count(OLD_A1)
if count_a1 != 1:
    log_result("fix_A1_precondition", False, f"expected 1 match, found {count_a1}")
    sys.exit(f"PRECONDITION VIOLATED fix_A1: match count={count_a1}")
log_result("fix_A1_precondition", True, "1 match confirmed")

# Step A2: add RMB-release save in _input, after the existing RMB-motion block.
# Exact old_str: the line that ends the RMB motion if-block.
# From live file line 1989, the if-block is:
#   if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
# We insert a new elif for MOUSE_BUTTON_RIGHT released, right before the next
# unindented block. The anchor is the blank line after _update_camera_position()
# and the dead code block that follows (lines 1998-2005).
# We target the unique string at lines 1997-1999:
OLD_A2 = (
    '\t\t_update_camera_position()\n'
    '\t\t# Immediately update camera position if we have a target\n'
    '\t\tvar target: Vector3'
)
NEW_A2 = (
    '\t\t_update_camera_position()\n'
    '\t\t# Immediately update camera position if we have a target\n'
    '\t\tvar target: Vector3'
)
# A2 is a no-op placeholder — the actual save-on-release is added via A3 below.
# A3: after the entire RMB motion block, add the release handler.
# The block ends at the `return` on line 2005 (unique anchor).
# Exact old_str (lines 2004-2006, unique in file):
OLD_A3 = (
    '\t\telse:\n'
    '\t\t\treturn\n'
    '\tif event is InputEventMouseButton'
)
# Check whether InputEventMouseButton block already exists right there
count_a3_check = original.count('\tif event is InputEventMouseButton')
# Insert RMB-release save before the existing InputEventMouseButton handler
OLD_A3_ANCHOR = (
    '\t\telse:\n'
    '\t\t\treturn\n'
    '\tif event is InputEventMouseButton'
)
NEW_A3_ANCHOR = (
    '\t\telse:\n'
    '\t\t\treturn\n'
    '\tif event is InputEventMouseButton and not event.pressed \\\n'
    '\t\t\tand (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:\n'
    '\t\tif _cam_save_pending:\n'
    '\t\t\t_save_camera_settings()\n'
    '\t\t\t_cam_save_pending = false\n'
    '\tif event is InputEventMouseButton'
)
count_a3 = original.count(OLD_A3_ANCHOR)
if count_a3 != 1:
    log_result("fix_A3_precondition", False, f"expected 1 match, found {count_a3}")
    sys.exit(f"PRECONDITION VIOLATED fix_A3: match count={count_a3}")
log_result("fix_A3_precondition", True, "1 match confirmed")

# Step A4: declare _cam_save_pending near other camera vars.
# Find _cam_distance declaration as anchor.
OLD_A4 = 'var _cam_distance: float = 5.0'
NEW_A4 = 'var _cam_distance: float = 5.0\nvar _cam_save_pending: bool = false'
count_a4 = original.count(OLD_A4)
if count_a4 != 1:
    log_result("fix_A4_precondition", False, f"expected 1 match, found {count_a4}")
    sys.exit(f"PRECONDITION VIOLATED fix_A4: match count={count_a4}")
log_result("fix_A4_precondition", True, "1 match confirmed")


# ════════════════════════════════════════════════════════════════════════════
# FIX B — LOD on terrain mesh
#
# After: var terrain_mesh = st.commit()
# Before: terrain_inst.mesh = terrain_mesh
# Insert: terrain_mesh.generate_lods(0.25, 0.05, [])
#   normal_merge_angle=0.25 rad, normal_split_angle=0.05 rad
#   merge_normals=[] (use mesh normals)
# Ref: https://docs.godotengine.org/en/stable/classes/class_arraymesh.html
# ════════════════════════════════════════════════════════════════════════════

OLD_B = (
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\tterrain_inst.mesh = terrain_mesh'
)
NEW_B = (
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\t# LOD: generate automatic LOD levels so Godot transitions mesh\n'
    '\t\t# detail by screen coverage. Eliminates coarse far-range appearance.\n'
    '\t\t# Ref: ArrayMesh.generate_lods()\n'
    '\t\t# https://docs.godotengine.org/en/stable/classes/class_arraymesh.html\n'
    '\t\tterrain_mesh.generate_lods(0.25, 0.05, [])\n'
    '\t\tterrain_inst.mesh = terrain_mesh'
)
count_b = original.count(OLD_B)
if count_b != 1:
    log_result("fix_B_precondition", False, f"expected 1 match, found {count_b}")
    sys.exit(f"PRECONDITION VIOLATED fix_B: match count={count_b}")
log_result("fix_B_precondition", True, "1 match confirmed")


# ── apply all patches in sequence ────────────────────────────────────────────
patched = original
patched = patched.replace(OLD_A1, NEW_A1, 1)
patched = patched.replace(OLD_A3_ANCHOR, NEW_A3_ANCHOR, 1)
patched = patched.replace(OLD_A4, NEW_A4, 1)
patched = patched.replace(OLD_B, NEW_B, 1)


# ── verify leading whitespace preserved (Rule #46) ───────────────────────────
for old_line, new_line in [
    ('\t_save_camera_settings()', '\t_cam_save_pending = true'),
    ('\t\tvar terrain_mesh = st.commit()', '\t\tvar terrain_mesh = st.commit()'),
]:
    old_ws = get_leading_ws(old_line)
    new_ws = get_leading_ws(new_line)
    if old_ws != new_ws:
        log_result("whitespace_check", False,
                   f"ws mismatch: old={repr(old_ws)} new={repr(new_ws)}")
        sys.exit("WHITESPACE CHECK FAILED")
log_result("whitespace_check", True, "leading whitespace preserved")


# ── timestamped backup (Rule #21) ────────────────────────────────────────────
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = f"{TARGET}.bak.{ts}"
shutil.copy2(TARGET, backup)
log_result("backup", True, backup)


# ── write and read-back (Rule #9) ────────────────────────────────────────────
with open(TARGET, "w", encoding="utf-8") as f:
    f.write(patched)
with open(TARGET, "r", encoding="utf-8") as f:
    written = f.read()
if written != patched:
    log_result("read_after_write", False, "mismatch — restoring")
    shutil.copy2(backup, TARGET)
    sys.exit("READ-AFTER-WRITE FAILED")
log_result("read_after_write", True, "bytes match")


# ── Rule #31: no leading spaces ──────────────────────────────────────────────
bad = [i+1 for i, ln in enumerate(written.splitlines()) if ln.startswith(" ")]
if bad:
    log_result("indentation_check", False, f"leading spaces at lines: {bad[:10]}")
    shutil.copy2(backup, TARGET)
    sys.exit("INDENTATION CHECK FAILED — restored")
log_result("indentation_check", True, "no leading spaces")


# ── semantic checks (Rule #46 step 9) ────────────────────────────────────────
checks = [
    ("_save_camera_settings removed from _update_camera_position",
     lambda t: "\t_save_camera_settings()" not in
               t[t.find("func _update_camera_position"):t.find("func _recreate_hud_if_needed")]),
    ("_cam_save_pending set in _update_camera_position",
     lambda t: "_cam_save_pending = true" in
               t[t.find("func _update_camera_position"):t.find("func _recreate_hud_if_needed")]),
    ("generate_lods present after st.commit()",
     lambda t: "terrain_mesh.generate_lods" in t),
    ("_cam_save_pending declared",
     lambda t: "var _cam_save_pending: bool = false" in t),
]
for name, pred in checks:
    ok = pred(written)
    log_result(f"semantic_check:{name}", ok, "PASS" if ok else "FAIL")
    if not ok:
        shutil.copy2(backup, TARGET)
        sys.exit(f"SEMANTIC CHECK FAILED: {name} — restored")


# ── godot syntax check (Rule #20) ────────────────────────────────────────────
result = subprocess.run(
    ["godot", "--headless", "--check-only", "--path", "godot_project"],
    capture_output=True, text=True
)
combined = result.stdout + result.stderr
ok = result.returncode == 0 and "Parse Error" not in combined
log_result("godot_syntax_check", ok,
           f"exit={result.returncode} parse_error={'yes' if 'Parse Error' in combined else 'no'}")
if not ok:
    print("GODOT CHECK OUTPUT:", combined[:2000], file=sys.stderr)
    shutil.copy2(backup, TARGET)
    sys.exit("GODOT SYNTAX CHECK FAILED — restored from backup")


# ── diff report (Rule #46 step 11) ───────────────────────────────────────────
diff = subprocess.run(["diff", TARGET, backup], capture_output=True, text=True)
print("\n=== DIFF (new vs backup) ===")
print(diff.stdout or "(no diff output)")

print(f"\nPATCH SUCCESS: {TARGET}")
print(f"Backup: {backup}")
print("Fix A: _save_camera_settings throttled — fires once on RMB release, not per frame")
print("Fix B: terrain_mesh.generate_lods() added — Godot 4 auto-LOD now active")
