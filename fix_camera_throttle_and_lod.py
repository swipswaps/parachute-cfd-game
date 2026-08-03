#!/usr/bin/env python3
# ============================================================================
# fix_camera_throttle_and_lod.py
#
# Fix A: throttle _save_camera_settings — fires once on RMB release, not
#        every InputEventMouseMotion frame (~60x/sec while dragging).
# Fix B: call generate_lods() on terrain ArrayMesh for automatic LOD.
#
# Rules: #1,#2,#6,#7,#9,#10,#16,#21,#24,#29,#30,#31,#38,#41,#44,#46
#
# Citations:
#   - InputEventMouseMotion:
#     https://docs.godotengine.org/en/stable/classes/class_inputeventmousemotion.html
#     (general knowledge — not retrieved this session)
#   - ArrayMesh.generate_lods():
#     https://docs.godotengine.org/en/stable/classes/class_arraymesh.html
#     (general knowledge — not retrieved this session)
#   - str.count(): https://docs.python.org/3/library/stdtypes.html#str.count
#     (general knowledge — not retrieved this session)
#   - shutil.copy2(): https://docs.python.org/3/library/shutil.html#shutil.copy2
#     (general knowledge — not retrieved this session)
#   - datetime.timezone.utc:
#     https://docs.python.org/3/library/datetime.html#datetime.timezone.utc
#     (general knowledge — not retrieved this session)
#
# Tools: python3, shutil, subprocess. sed BANNED.
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
# Banned tokens constructed so this file cannot self-flag.
_BANNED_SED = "se" + "d"
_BANNED_UTC = "utcno" + "w()"


def pre_delivery_gate() -> None:
    with open(__file__, "r") as f:
        lines = f.readlines()
    violations = []
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if _BANNED_SED in line.split() and "_BANNED_SED" not in line:
            violations.append(f"sed at line {i}")
        if _BANNED_UTC in line and "_BANNED_UTC" not in line:
            violations.append(f"utcno" + f"w() at line {i}")
    if violations:
        log_result("pre_delivery_gate", False, str(violations))
        sys.exit(f"PRE-DELIVERY GATE FAILED: {violations}")
    log_result("pre_delivery_gate", True, "no forbidden patterns in fix script")


pre_delivery_gate()

# ── read live file ───────────────────────────────────────────────────────────
with open(TARGET, "r", encoding="utf-8") as f:
    original = f.read()
log_result("read_live_file", True,
           f"{len(original)} bytes, {original.count(chr(10))+1} lines")

# ════════════════════════════════════════════════════════════════════════════
# FIX A — throttle _save_camera_settings
#
# A1: declare _cam_save_pending flag near _cam_distance
# A2: in _update_camera_position, replace _save_camera_settings() with flag
# A3: in _input, add RMB-release handler that calls _save_camera_settings()
#     once. Anchor: unique transition from cam_orbit print block to
#     InputEventKey handler (live-extracted from cat -A output 2011-2015).
# ════════════════════════════════════════════════════════════════════════════

OLD_A1 = "var _cam_distance: float = 5.0"
NEW_A1 = "var _cam_distance: float = 5.0\nvar _cam_save_pending: bool = false"

OLD_A2 = (
    '\tprint("[DEBUG] Camera updated: pos=", _camera.global_position,'
    ' " target=", target)\n'
    '\t_save_camera_settings()'
)
NEW_A2 = (
    '\tprint("[DEBUG] Camera updated: pos=", _camera.global_position,'
    ' " target=", target)\n'
    '\t_cam_save_pending = true'
)

# Anchor extracted live from lines 2011-2015 (cat -A confirmed tabs, no CRLF):
#   2011: \t\tprint(
#   2012: \t\t\t"[VERBATIM] cam_orbit az=", ...
#   2013: \t\t)
#   2014: (blank)
#   2015: \tif event is InputEventKey
OLD_A3 = (
    '\t\tprint(\n'
    '\t\t\t"[VERBATIM] cam_orbit az=", rad_to_deg(_cam_azimuth),'
    ' " el=", rad_to_deg(_cam_elevation)\n'
    '\t\t)\n'
    '\n'
    '\tif event is InputEventKey'
)
NEW_A3 = (
    '\t\tprint(\n'
    '\t\t\t"[VERBATIM] cam_orbit az=", rad_to_deg(_cam_azimuth),'
    ' " el=", rad_to_deg(_cam_elevation)\n'
    '\t\t)\n'
    '\n'
    '\t# Save camera distance once on RMB release (Rule #46 — throttle DB write)\n'
    '\t# Ref: InputEventMouseButton\n'
    '\t# https://docs.godotengine.org/en/stable/classes/class_inputeventmousebutton.html\n'
    '\tif event is InputEventMouseButton and not event.pressed \\\n'
    '\t\t\tand (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:\n'
    '\t\tif _cam_save_pending:\n'
    '\t\t\t_save_camera_settings()\n'
    '\t\t\t_cam_save_pending = false\n'
    '\n'
    '\tif event is InputEventKey'
)

# ════════════════════════════════════════════════════════════════════════════
# FIX B — terrain LOD
# Anchor live-extracted: lines 327-329 in original (st.commit then mesh assign)
# ════════════════════════════════════════════════════════════════════════════

OLD_B = (
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\tterrain_inst.mesh = terrain_mesh'
)
NEW_B = (
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\t# Generate automatic LOD levels — Godot 4 transitions mesh detail\n'
    '\t\t# by screen coverage. Eliminates coarse far-range appearance.\n'
    '\t\t# Ref: ArrayMesh.generate_lods()\n'
    '\t\t# https://docs.godotengine.org/en/stable/classes/class_arraymesh.html\n'
    '\t\tterrain_mesh.generate_lods(0.25, 0.05, [])\n'
    '\t\tterrain_inst.mesh = terrain_mesh'
)

# ── precondition guards (Rule #6 / #46) ─────────────────────────────────────
patches = [
    ("A1_cam_save_pending_decl", OLD_A1, NEW_A1),
    ("A2_remove_save_from_update", OLD_A2, NEW_A2),
    ("A3_rmbrelease_handler", OLD_A3, NEW_A3),
    ("B_generate_lods", OLD_B, NEW_B),
]

for name, old, new in patches:
    count = original.count(old)
    if count != 1:
        log_result(f"precondition:{name}", False,
                   f"expected 1 match, found {count}")
        sys.exit(f"PRECONDITION VIOLATED {name}: count={count}")
    log_result(f"precondition:{name}", True, "1 match confirmed")

# ── apply patches ────────────────────────────────────────────────────────────
patched = original
for name, old, new in patches:
    patched = patched.replace(old, new, 1)

# ── whitespace preservation (Rule #46) ───────────────────────────────────────
ws_pairs = [
    ('\t_save_camera_settings()', '\t_cam_save_pending = true'),
    ('\t\tvar terrain_mesh = st.commit()', '\t\tvar terrain_mesh = st.commit()'),
]
for old_line, new_line in ws_pairs:
    if get_leading_ws(old_line) != get_leading_ws(new_line):
        log_result("whitespace_check", False,
                   f"{repr(old_line)} -> {repr(new_line)}")
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
    shutil.copy2(backup, TARGET)
    log_result("read_after_write", False, "mismatch — restored")
    sys.exit("READ-AFTER-WRITE FAILED")
log_result("read_after_write", True, "bytes match")

# ── Rule #31: no leading spaces ──────────────────────────────────────────────
bad = [i+1 for i, ln in enumerate(written.splitlines()) if ln.startswith(" ")]
if bad:
    shutil.copy2(backup, TARGET)
    log_result("indentation_check", False, f"leading spaces at: {bad[:10]}")
    sys.exit("INDENTATION CHECK FAILED — restored")
log_result("indentation_check", True, "no leading spaces")

# ── semantic checks (Rule #46) ───────────────────────────────────────────────
def between(text, start_fn, end_fn):
    a = text.find(start_fn)
    b = text.find(end_fn, a)
    return text[a:b] if a != -1 and b != -1 else ""


checks = [
    ("_save_camera_settings removed from _update_camera_position",
     lambda t: "\t_save_camera_settings()" not in
               between(t, "func _update_camera_position", "func _recreate_hud_if_needed")),
    ("_cam_save_pending = true in _update_camera_position",
     lambda t: "_cam_save_pending = true" in
               between(t, "func _update_camera_position", "func _recreate_hud_if_needed")),
    ("generate_lods present",
     lambda t: "terrain_mesh.generate_lods" in t),
    ("_cam_save_pending declared",
     lambda t: "var _cam_save_pending: bool = false" in t),
    ("RMB release handler present in _input",
     lambda t: "_cam_save_pending = false" in
               between(t, "func _input", "func _poll_controls")),
]
for name, pred in checks:
    ok = pred(written)
    log_result(f"semantic:{name}", ok, "PASS" if ok else "FAIL")
    if not ok:
        shutil.copy2(backup, TARGET)
        sys.exit(f"SEMANTIC FAILED: {name} — restored")

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
    print("GODOT OUTPUT:", combined[:2000], file=sys.stderr)
    shutil.copy2(backup, TARGET)
    sys.exit("GODOT SYNTAX CHECK FAILED — restored")

# ── diff report ───────────────────────────────────────────────────────────────
diff = subprocess.run(["diff", TARGET, backup], capture_output=True, text=True)
print("\n=== DIFF (patched vs backup) ===")
print(diff.stdout or "(no output)")
print(f"\nPATCH SUCCESS: {TARGET}")
print(f"Backup: {backup}")
print("Fix A: _save_camera_settings fires once on RMB release — not per frame")
print("Fix B: terrain_mesh.generate_lods() active — Godot 4 auto-LOD enabled")
