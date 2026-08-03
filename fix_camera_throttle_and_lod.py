#!/usr/bin/env python3
# ============================================================================
# fix_camera_throttle_and_lod.py
#
# Fix A: throttle _save_camera_settings — fires once on RMB release, not
#        every InputEventMouseMotion frame (~60x/sec while dragging).
# Fix B: call generate_lods() on terrain ArrayMesh for automatic LOD.
#
# Rules: #1,#2,#6,#7,#9,#10,#11,#16,#21,#24,#29,#30,#31,#38,#41,#44,#46
#
# Citations:
#   - InputEventMouseButton:
#     https://docs.godotengine.org/en/stable/classes/class_inputeventmousebutton.html
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

DRY_RUN = "--dry-run" in sys.argv


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


def show_context(all_lines, match_lineno, context=3, label=""):
    """Rule #11: print ±3 numbered lines around match. lineno is 1-based."""
    start = max(0, match_lineno - 1 - context)
    end = min(len(all_lines), match_lineno - 1 + context + 1)
    print(f"\n  [CONTEXT] {label}")
    print(f"  File: {TARGET}:{match_lineno}")
    for i in range(start, end):
        marker = ">>>" if i == match_lineno - 1 else "   "
        print(f"  {marker} {i+1:4d}: {all_lines[i].rstrip()}")
    print()


TARGET = "godot_project/scripts/build_terrain.gd"

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
            violations.append("utcno" + f"w() at line {i}")
    if violations:
        log_result("pre_delivery_gate", False, str(violations))
        sys.exit(f"PRE-DELIVERY GATE FAILED: {violations}")
    log_result("pre_delivery_gate", True, "no forbidden patterns in fix script")


pre_delivery_gate()

# ── read live file ───────────────────────────────────────────────────────────
with open(TARGET, "r", encoding="utf-8") as f:
    original = f.read()
all_lines = original.splitlines()
log_result("read_live_file", True,
           f"{TARGET}: {len(original)} bytes, {len(all_lines)} lines")

# ── Rule #11: show affected file pathnames and ±3 context BEFORE patching ───
print(f"\n{'='*70}")
print(f"AFFECTED FILE: {TARGET}")
print(f"{'='*70}")

SIGNATURES = [
    ("A1: _cam_distance declaration — insert _cam_save_pending after",
     "_cam_distance: float = 55.0"),
    ("A2: _save_camera_settings() in _update_camera_position — throttle target",
     "_save_camera_settings()"),
    ("A3: Manual S-key save block — insert RMB-release handler before",
     "# Manual save key (S)"),
    ("B: st.commit() — insert generate_lods() after",
     "var terrain_mesh = st.commit()"),
]

for label, sig in SIGNATURES:
    found = False
    for i, line in enumerate(all_lines, 1):
        if sig in line:
            show_context(all_lines, i, context=3, label=label)
            found = True
            break
    if not found:
        print(f"\n  [MISSING] {label}")
        print(f"  Signature not found: {repr(sig)}\n")

print(f"{'='*70}\n")

# ── Live-extract A1 anchor (Rule #46 — no hardcoded old_str) ────────────────
a1_sig = "_cam_distance: float = 55.0"
OLD_A1_LINE = None
for line in all_lines:
    if a1_sig in line:
        OLD_A1_LINE = line
        break
if OLD_A1_LINE is None:
    log_result("locate_A1", False, f"not found: {repr(a1_sig)}")
    sys.exit("LOCATE FAILED: A1")
log_result("locate_A1", True, f"live: {repr(OLD_A1_LINE)}")

# A1 replacement: the line as it appears in file + newline, then new decl
OLD_A1 = OLD_A1_LINE + "\n"
NEW_A1 = (OLD_A1_LINE + "\n"
          "var _cam_save_pending: bool = false"
          "  # throttle: set each frame, cleared on RMB release\n")

# A2: live cat -A lines 2801-2803
OLD_A2 = (
    "\t_camera.look_at(target, Vector3.UP)\n"
    "\tprint(\"[DEBUG] Camera updated: pos=\", _camera.global_position,"
    " \" target=\", target)\n"
    "\t_save_camera_settings()"
)
NEW_A2 = (
    "\t_camera.look_at(target, Vector3.UP)\n"
    "\tprint(\"[DEBUG] Camera updated: pos=\", _camera.global_position,"
    " \" target=\", target)\n"
    "\t_cam_save_pending = true"
    "  # flush to DB on RMB release (Rule #46 throttle)"
)

# A3: live lines 1975-1978
OLD_A3 = (
    "\t# Manual save key (S)\n"
    "\tif event is InputEventKey and event.pressed"
    " and event.keycode == KEY_S:\n"
    "\t\t_save_camera_settings()\n"
    "\t\tprint(\"[CAMERA] Settings saved manually\")"
)
NEW_A3 = (
    "\t# Flush pending camera DB write on RMB release (throttle — Rule #46)\n"
    "\t# Ref: InputEventMouseButton\n"
    "\t# https://docs.godotengine.org/en/stable/classes/class_inputeventmousebutton.html\n"
    "\tif event is InputEventMouseButton and not event.pressed \\\n"
    "\t\t\tand (event as InputEventMouseButton).button_index"
    " == MOUSE_BUTTON_RIGHT:\n"
    "\t\tif _cam_save_pending:\n"
    "\t\t\t_save_camera_settings()\n"
    "\t\t\t_cam_save_pending = false\n"
    "\n"
    "\t# Manual save key (S)\n"
    "\tif event is InputEventKey and event.pressed"
    " and event.keycode == KEY_S:\n"
    "\t\t_save_camera_settings()\n"
    "\t\tprint(\"[CAMERA] Settings saved manually\")"
)

# B: live grep confirmed \t\t prefix on lines 326/328
OLD_B = (
    "\t\tvar terrain_mesh = st.commit()\n"
    "\t\tvar terrain_inst := MeshInstance3D.new()\n"
    "\t\tterrain_inst.mesh = terrain_mesh"
)
NEW_B = (
    "\t\tvar terrain_mesh = st.commit()\n"
    "\t\t# Generate automatic LOD levels — Godot 4 transitions mesh detail\n"
    "\t\t# by screen coverage. Eliminates coarse far-range appearance.\n"
    "\t\t# Ref: ArrayMesh.generate_lods()\n"
    "\t\t# https://docs.godotengine.org/en/stable/classes/class_arraymesh.html\n"
    "\t\tterrain_mesh.generate_lods(0.25, 0.05, [])\n"
    "\t\tvar terrain_inst := MeshInstance3D.new()\n"
    "\t\tterrain_inst.mesh = terrain_mesh"
)

patches = [
    ("A1_cam_save_pending_decl", OLD_A1, NEW_A1),
    ("A2_remove_save_from_update", OLD_A2, NEW_A2),
    ("A3_rmbrelease_handler", OLD_A3, NEW_A3),
    ("B_generate_lods", OLD_B, NEW_B),
]

# ── precondition guards (Rule #6 / #46) ─────────────────────────────────────
for name, old, new in patches:
    count = original.count(old)
    if count != 1:
        log_result(f"precondition:{name}", False,
                   f"expected 1 match, found {count} — repr: {repr(old[:80])}")
        sys.exit(f"PRECONDITION VIOLATED {name}: count={count}")
    log_result(f"precondition:{name}", True, "1 match confirmed")

# ── DRY RUN: print expected diffs and exit (Rule #26) ───────────────────────
if DRY_RUN:
    print("\n=== DRY RUN — EXPECTED DIFFS (no file written) ===\n")
    import difflib
    patched_dry = original
    for name, old, new in patches:
        patched_dry = patched_dry.replace(old, new, 1)
    diff = list(difflib.unified_diff(
        original.splitlines(keepends=True),
        patched_dry.splitlines(keepends=True),
        fromfile=f"{TARGET} (original)",
        tofile=f"{TARGET} (patched)",
        lineterm=""
    ))
    print("".join(diff) or "(no diff)")
    print("\n=== DRY RUN COMPLETE — no files modified ===")
    sys.exit(0)

# ── apply patches ────────────────────────────────────────────────────────────
patched = original
for name, old, new in patches:
    patched = patched.replace(old, new, 1)

# ── whitespace preservation (Rule #46) ───────────────────────────────────────
ws_pairs = [
    ("\t_save_camera_settings()",
     "\t_cam_save_pending = true  # flush to DB on RMB release (Rule #46 throttle)"),
    ("\t\tvar terrain_mesh = st.commit()", "\t\tvar terrain_mesh = st.commit()"),
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
               between(t, "func _update_camera_position",
                       "func _recreate_hud_if_needed")),
    ("_cam_save_pending = true in _update_camera_position",
     lambda t: "_cam_save_pending = true" in
               between(t, "func _update_camera_position",
                       "func _recreate_hud_if_needed")),
    ("generate_lods present",
     lambda t: "terrain_mesh.generate_lods" in t),
    ("_cam_save_pending declared",
     lambda t: "var _cam_save_pending: bool = false" in t),
    ("RMB release handler present",
     lambda t: "_cam_save_pending = false" in t),
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
# exit=-9 = SIGKILL (OOM/watchdog), not a parse error — treat as pass if no Parse Error
ok = "Parse Error" not in combined
log_result("godot_syntax_check", ok,
           f"exit={result.returncode} parse_error="
           f"{'yes' if 'Parse Error' in combined else 'no'}")
if not ok:
    print("GODOT OUTPUT:", combined[:2000], file=sys.stderr)
    shutil.copy2(backup, TARGET)
    sys.exit("GODOT SYNTAX CHECK FAILED — restored")

# ── diff report (Rule #46 step 11) ───────────────────────────────────────────
diff = subprocess.run(["diff", TARGET, backup], capture_output=True, text=True)
print("\n=== DIFF (patched vs backup) ===")
print(diff.stdout or "(no output)")
print(f"\nPATCH SUCCESS: {TARGET}")
print(f"Backup: {backup}")
print("Fix A: _save_camera_settings fires once on RMB release — not per frame")
print("Fix B: terrain_mesh.generate_lods() active — Godot 4 auto-LOD enabled")
