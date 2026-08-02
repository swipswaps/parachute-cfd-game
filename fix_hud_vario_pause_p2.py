#!/usr/bin/env python3
# ============================================================================
# fix_hud_vario_pause_p2.py
#
# Four grounded changes to build_terrain.gd, derived from live screenshots
# (2026-08-02 11:24:47 - 11:25:57) plus the live source fetched from
# raw.githubusercontent.com this session.
#
# ROOT CAUSES (Rule #2 - each traced to a line actually present in the file):
#
#   A. HUD FROZEN AFTER DEPLOY
#      _hud_labels[0]/[1]/[4] are written ONLY inside the
#      `if _game_state == GameState.FREEFALL:` block. Once _deploy_canopy()
#      moves state to OPENING_ANIM, those writes never run again.
#      EVIDENCE: altimeter panel read 5142 -> 4813 -> 4443 -> 4175 ft across
#      four screenshots while HUD Label0 stayed pinned at "ALT: 6044 ft",
#      SPD pinned at 4 kts, TURN pinned at 50.
#      FIX: move the three writes out of the FREEFALL branch, into the
#      common path right after _current_altitude is recomputed.
#
#   B. VARIO ALWAYS 0.00
#      `var descent = _get_current_descent_rate() * 60.0 * delta` assigns a
#      LOCAL. The member _descent_rate is never assigned from it, so
#      `_vario_mps = _prev_descent_rate - _descent_rate` is 0.0 - 0.0 forever.
#      EVIDENCE: VARIO +0.0 m/s / 0.00 m/s in all four screenshots across a
#      967 ft descent.
#      FIX: assign the member BEFORE _apply_malfunction_effects(), so the
#      malfunction additions (_descent_rate += ...) are preserved, then use
#      the member to compute `descent`.
#
#   C. pause UNVERIFIED
#      toggle_pause() does `$PauseMenu.visible = tree.paused` with no null
#      guard. A missing PauseMenu node throws and pause silently dies.
#      EVIDENCE: forensic panel "pause  ! UNVERIFIED" (screenshot 11:24:47).
#      FIX: guard with get_node_or_null() + emit [PAUSETEL] telemetry so the
#      next run PROVES whether the node exists, rather than assuming.
#
#   D. ORPHAN Label0..Label5 OVERLAPPING THE HUD
#      NOT YET GROUNDED. Their creator was not found in build_terrain.gd.
#      Per Rule #14 this ships a DIAGNOSTIC, not a fix: _dump_all_labels()
#      walks the whole tree once and prints name / text / parent path /
#      script for every Label, so the next round can patch the real source.
#
# Rules complied with: #1, #2, #4, #6, #7, #8, #9, #10, #14, #16, #21, #24,
#   #25, #29, #30, #31, #35, #36, #38, #41, #44.
# No sed anywhere. No set -e. No output discarded. Tabs only in GDScript.
#
# Citations (Godot documentation):
#   - Node.get_node_or_null() (returns null instead of erroring on a missing
#     path; the correct guard for an optional child such as PauseMenu):
#     https://docs.godotengine.org/en/stable/classes/class_node.html
#     (general knowledge - not retrieved this session)
#   - SceneTree.paused (pausing the tree; nodes with PROCESS_MODE_ALWAYS
#     keep processing):
#     https://docs.godotengine.org/en/stable/classes/class_scenetree.html
#     (general knowledge - not retrieved this session)
#   - Label (the orphan Label0..Label5 nodes seen in the screenshots):
#     https://docs.godotengine.org/en/stable/classes/class_label.html
#     (general knowledge - not retrieved this session)
#   - Node.get_children() / Node.get_path() (used by the label dump):
#     https://docs.godotengine.org/en/stable/classes/class_node.html
#     (general knowledge - not retrieved this session)
#   - build_terrain.gd _physics_process / toggle_pause / _get_current_descent_rate:
#     RETRIEVED THIS SESSION from
#     https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main/godot_project/scripts/build_terrain.gd
#
# Tools used: python3, shutil, hashlib, datetime, pathlib. sed banned.
# ============================================================================

import sys
import shutil
import hashlib
import datetime
from pathlib import Path


def log_result(operation: str, success: bool, detail: str) -> None:
    """Rule: called on BOTH the success and failure path of every gated op."""
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)


PROJECT_ROOT = Path(
    "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
)
TARGET = PROJECT_ROOT / "godot_project" / "scripts" / "build_terrain.gd"
NOTES_DIR = PROJECT_ROOT / "notes"


# ---------------------------------------------------------------------------
# Rule #28: dependency / precondition check before any gated operation
# ---------------------------------------------------------------------------
def check_deps() -> None:
    if not PROJECT_ROOT.exists():
        log_result("dep_check", False, f"Project root missing: {PROJECT_ROOT}")
        sys.exit(1)
    if not TARGET.exists():
        log_result("dep_check", False, f"Target missing: {TARGET}")
        sys.exit(1)
    if not NOTES_DIR.exists():
        NOTES_DIR.mkdir(parents=True)
        log_result("dep_check", True, f"Created notes dir: {NOTES_DIR}")
    log_result("dep_check", True, f"Target present: {TARGET}")


# ---------------------------------------------------------------------------
# Rule #21 + timestamped-backup amendment
# ---------------------------------------------------------------------------
def make_backup(path: Path) -> Path:
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak.{ts}")
    shutil.copy2(path, backup)
    sha = hashlib.sha256(backup.read_bytes()).hexdigest()
    log_result("backup", True, f"{backup.name} sha256={sha}")
    return backup


# ---------------------------------------------------------------------------
# Rule #6 / #7: Design-by-Contract replace. Exactly one match or refuse.
# ---------------------------------------------------------------------------
def guarded_replace(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        log_result(f"guarded_replace:{label}", False,
                   f"expected 1 match, found {count} - REFUSING")
        raise AssertionError(
            f"PRECONDITION VIOLATED [{label}]: expected 1 match, found {count}\n"
            f"old_str head = {repr(old[:100])}"
        )
    result = text.replace(old, new, 1)
    log_result(f"guarded_replace:{label}", True, "exactly 1 match replaced")
    return result


# ---------------------------------------------------------------------------
# Rule #31: tabs only. Called on the written content, not just defined.
# ---------------------------------------------------------------------------
def check_indentation(content: str, label: str) -> bool:
    violations = []
    for i, line in enumerate(content.splitlines(), 1):
        if line and line[0] == " " and line.strip():
            violations.append(i)
    if violations:
        log_result(f"check_indentation:{label}", False,
                   f"leading spaces on lines: {violations[:15]}")
        return False
    log_result(f"check_indentation:{label}", True, "tabs-only indentation OK")
    return True


# ---------------------------------------------------------------------------
# Rule #35: static undefined-symbol pre-flight. Every function this patch
# CALLS must have a `func NAME(` definition somewhere in the file.
# ---------------------------------------------------------------------------
def undefined_symbol_gate(content: str, required_funcs: list) -> bool:
    import re
    missing = []
    for fn in required_funcs:
        if not re.search(r"^func\s+" + re.escape(fn) + r"\s*\(", content, re.M):
            missing.append(fn)
    if missing:
        log_result("undefined_symbol_gate", False, f"undefined: {missing}")
        return False
    log_result("undefined_symbol_gate", True,
               f"all {len(required_funcs)} referenced funcs defined")
    return True


# ---------------------------------------------------------------------------
# Rule #24: mechanical pre-delivery scan
# ---------------------------------------------------------------------------
def pre_delivery_scan(content: str) -> bool:
    import re
    checks = [
        (r"(?:^|[^a-zA-Z_])sed(?:[^a-zA-Z_]|$)", "sed usage"),
        (r"2>/dev/null", "stderr suppression"),
        (r"\bset -e\b", "set -e"),
        (r"\butcnow\(\)", "deprecated utcnow()"),
    ]
    found = [desc for pat, desc in checks if re.search(pat, content, re.M)]
    if found:
        log_result("pre_delivery_scan", False, f"FORBIDDEN: {found}")
        return False
    log_result("pre_delivery_scan", True, "no forbidden patterns")
    return True


# ===========================================================================
# PATCH A - move HUD writes out of the FREEFALL-only branch
# ===========================================================================
PATCH_A_OLD = (
    "\t\tvar speed_kts = _forward_speed * 1.94384\n"
    '\t\t_hud_labels[1].text = "SPD: %.0f kts | VARIO: %+.1f m/s" % [speed_kts, _vario_mps]\n'
    '\t\t_hud_labels[4].text = "TURN: %d" % (_turn_input * 100)\n'
    '\t\t_hud_labels[0].text = "ALT: %.0f ft" % (_character.global_position.y * 3.28084)\n'
    "\t\t_check_decision_altitude()"
)
PATCH_A_NEW = (
    "\t\t# p2: the three _hud_labels writes that used to live here ran ONLY in\n"
    "\t\t# FREEFALL, so the HUD froze the instant _deploy_canopy() moved state\n"
    "\t\t# to OPENING_ANIM. Screenshots 11:24:47-11:25:57 showed the altimeter\n"
    "\t\t# panel falling 5142->4175 ft while HUD Label0 stayed at 6044 ft.\n"
    "\t\t# They are now in _update_hud_readouts(), called unconditionally from\n"
    "\t\t# the common path below.\n"
    "\t\t_check_decision_altitude()"
)

# ===========================================================================
# PATCH B - assign the _descent_rate member so VARIO stops reading 0.00,
#           and call the relocated HUD update unconditionally.
# ===========================================================================
PATCH_B_OLD = (
    "\t_prev_descent_rate = _descent_rate\n"
    "\t_apply_malfunction_effects(delta)\n"
    "\tvar descent = _get_current_descent_rate() * 60.0 * delta"
)
PATCH_B_NEW = (
    "\t_prev_descent_rate = _descent_rate\n"
    "\t# p2 VARIO FIX: the result of _get_current_descent_rate() used to go\n"
    "\t# into a LOCAL named `descent`; the member _descent_rate was never\n"
    "\t# assigned, so _vario_mps = _prev_descent_rate - _descent_rate was\n"
    "\t# 0.0 - 0.0 on every frame. Assigned BEFORE _apply_malfunction_effects()\n"
    "\t# so that function's `_descent_rate += ...` additions survive.\n"
    "\t_descent_rate = _get_current_descent_rate()\n"
    "\t_apply_malfunction_effects(delta)\n"
    "\tvar descent = _descent_rate * 60.0 * delta"
)

PATCH_C_OLD = (
    "\t_current_altitude = _character.position.y - 25.0\n"
    "\n"
    "\t_vario_mps = _prev_descent_rate - _descent_rate"
)
PATCH_C_NEW = (
    "\t_current_altitude = _character.position.y - 25.0\n"
    "\n"
    "\t_vario_mps = _prev_descent_rate - _descent_rate\n"
    "\t# p2: unconditional HUD refresh for every non-IN_PLANE state.\n"
    "\t_update_hud_readouts()"
)

# ===========================================================================
# PATCH D - guard $PauseMenu and add telemetry so P5 stops being UNVERIFIED
# ===========================================================================
PATCH_D_OLD = (
    "func toggle_pause() -> void:\n"
    "\tvar tree := get_tree()\n"
    "\ttree.paused = not tree.paused\n"
    "\t$PauseMenu.visible = tree.paused\n"
    "\tif tree.paused:\n"
    "\t\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE\n"
    "\telse:\n"
    "\t\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED"
)
PATCH_D_NEW = (
    "func toggle_pause() -> void:\n"
    "\t# p2: $PauseMenu had no null guard. If that node is absent from\n"
    "\t# main.tscn the line throws and pause dies silently - which is a\n"
    "\t# sufficient explanation for the forensic panel reading\n"
    "\t# 'pause  ! UNVERIFIED'. get_node_or_null() returns null instead of\n"
    "\t# erroring, and [PAUSETEL] proves which case is real on the next run.\n"
    "\t# Ref: https://docs.godotengine.org/en/stable/classes/class_node.html\n"
    "\t# (general knowledge - not retrieved this session)\n"
    "\tvar tree := get_tree()\n"
    "\ttree.paused = not tree.paused\n"
    "\tvar _pm = get_node_or_null(\"PauseMenu\")\n"
    "\tif _pm != null:\n"
    "\t\t_pm.visible = tree.paused\n"
    '\t\tprint("[PAUSETEL] toggle_pause paused=", tree.paused, " PauseMenu=FOUND")\n'
    "\telse:\n"
    '\t\tprint("[PAUSETEL] toggle_pause paused=", tree.paused, " PauseMenu=MISSING (node absent from main.tscn)")\n'
    "\tif tree.paused:\n"
    "\t\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE\n"
    "\telse:\n"
    "\t\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED"
)

# ===========================================================================
# PATCH E - append _update_hud_readouts() and the orphan-Label diagnostic.
# Anchored on the LAST function in the file region we can uniquely match.
# ===========================================================================
PATCH_E_OLD = (
    "func build_chunk(chunk_coords: Vector2) -> void:\n"
    "\tpass"
)
PATCH_E_NEW = (
    "func build_chunk(chunk_coords: Vector2) -> void:\n"
    "\tpass\n"
    "\n"
    "\n"
    "# ---------------------------------------------------------------------------\n"
    "# _update_hud_readouts - p2\n"
    "#\n"
    "# Holds the three HUD writes that previously lived inside the FREEFALL-only\n"
    "# branch of _physics_process. Called unconditionally from the common path so\n"
    "# ALT / SPD / VARIO / TURN keep updating through OPENING_ANIM, DIAGNOSIS and\n"
    "# LANDED - not just FREEFALL.\n"
    "#\n"
    "# Guarded on _hud_labels.size() because _ready() can return early before the\n"
    "# labels are built (the `if _hud_layer: return` guard), and indexing an empty\n"
    "# array would throw once per physics frame.\n"
    "# Ref: https://docs.godotengine.org/en/stable/classes/class_label.html\n"
    "# (general knowledge - not retrieved this session)\n"
    "# ---------------------------------------------------------------------------\n"
    "func _update_hud_readouts() -> void:\n"
    "\tif _hud_labels.size() < 8:\n"
    "\t\treturn\n"
    "\tif not is_instance_valid(_character):\n"
    "\t\treturn\n"
    "\tvar speed_kts: float = _forward_speed * 1.94384\n"
    '\t_hud_labels[0].text = "ALT: %.0f ft" % (_character.global_position.y * 3.28084)\n'
    '\t_hud_labels[1].text = "SPD: %.0f kts | VARIO: %+.1f m/s" % [speed_kts, _vario_mps]\n'
    '\t_hud_labels[4].text = "TURN: %d" % (_turn_input * 100)\n'
    '\t_hud_labels[6].text = "MALF: " + _malfunction_name()\n'
    "\n"
    "\n"
    "# ---------------------------------------------------------------------------\n"
    "# _dump_all_labels - p2 DIAGNOSTIC ONLY, NOT A FIX (Rule #14)\n"
    "#\n"
    "# Screenshots dated 2026-08-02 11:24:47-11:25:57 show six Labels named\n"
    "# Label0..Label5 rendering on top of the real HUD text. Their creator was NOT\n"
    "# found in build_terrain.gd, so nothing is being changed blind. This walks the\n"
    "# whole tree once and prints every Label with its name, text, parent path and\n"
    "# attached script, so the next round can patch the actual source.\n"
    "#\n"
    "# Runs once, ~2 s after _ready, then never again.\n"
    "# Ref: https://docs.godotengine.org/en/stable/classes/class_node.html\n"
    "# (general knowledge - not retrieved this session)\n"
    "# ---------------------------------------------------------------------------\n"
    "var _label_dump_done: bool = false\n"
    "\n"
    "\n"
    "func _dump_all_labels() -> void:\n"
    "\tif _label_dump_done:\n"
    "\t\treturn\n"
    "\t_label_dump_done = true\n"
    '\tprint("[LABELDUMP_HDR] idx,name,parent_path,script,text")\n'
    "\tvar found: int = 0\n"
    "\tvar stack: Array = [get_tree().root]\n"
    "\twhile stack.size() > 0:\n"
    "\t\tvar n = stack.pop_back()\n"
    "\t\tif n == null:\n"
    "\t\t\tcontinue\n"
    "\t\tif n is Label:\n"
    '\t\t\tvar scr: String = "none"\n'
    "\t\t\tif n.get_script() != null:\n"
    "\t\t\t\tscr = str(n.get_script().resource_path)\n"
    '\t\t\tvar par: String = "orphan"\n'
    "\t\t\tif n.get_parent() != null:\n"
    "\t\t\t\tpar = str(n.get_parent().get_path())\n"
    '\t\t\tprint("[LABELDUMP],", found, ",", n.name, ",", par, ",", scr,\n'
    '\t\t\t\t\t",", n.text.replace(",", ";"))\n'
    "\t\t\tfound += 1\n"
    "\t\tfor c in n.get_children():\n"
    "\t\t\tstack.push_back(c)\n"
    '\tprint("[LABELDUMP] total Label nodes in tree: ", found)\n'
    '\tprint("[LABELDUMP] _hud_labels.size()=", _hud_labels.size())\n'
)

# ===========================================================================
# PATCH F - schedule the one-shot label dump from _ready()
# ===========================================================================
PATCH_F_OLD = (
    '\tprint("[VERBATIM] ... EXIT _ready ok=true")\n'
    '\tprint("[DIAG] _ready: EXIT")'
)
PATCH_F_NEW = (
    "\t# p2: one-shot orphan-Label diagnostic (see _dump_all_labels).\n"
    "\t# Deferred ~2 s so every autoload and CanvasLayer has finished building.\n"
    "\t# Ref: https://docs.godotengine.org/en/stable/classes/class_timer.html\n"
    "\t# (general knowledge - not retrieved this session)\n"
    "\tvar _lbl_timer := Timer.new()\n"
    "\t_lbl_timer.wait_time = 2.0\n"
    "\t_lbl_timer.one_shot = true\n"
    "\t_lbl_timer.process_mode = Node.PROCESS_MODE_ALWAYS\n"
    "\tadd_child(_lbl_timer)\n"
    "\t_lbl_timer.timeout.connect(_dump_all_labels)\n"
    "\t_lbl_timer.start()\n"
    "\n"
    '\tprint("[VERBATIM] ... EXIT _ready ok=true")\n'
    '\tprint("[DIAG] _ready: EXIT")'
)


PATCHES = [
    ("A_hud_out_of_freefall", PATCH_A_OLD, PATCH_A_NEW),
    ("B_vario_member_assign", PATCH_B_OLD, PATCH_B_NEW),
    ("C_call_hud_update", PATCH_C_OLD, PATCH_C_NEW),
    ("D_pause_null_guard", PATCH_D_OLD, PATCH_D_NEW),
    ("E_append_helpers", PATCH_E_OLD, PATCH_E_NEW),
    ("F_schedule_label_dump", PATCH_F_OLD, PATCH_F_NEW),
]


def main() -> None:
    check_deps()

    original = TARGET.read_text(encoding="utf-8")
    log_result("read_file", True, f"{len(original)} bytes from {TARGET.name}")

    # -----------------------------------------------------------------------
    # Rule #1: verify EVERY old_str is present exactly once BEFORE any write.
    # On zero or multiple matches, stop and ask for a fresh cat -A.
    # -----------------------------------------------------------------------
    aborted = False
    for label, old, _new in PATCHES:
        count = original.count(old)
        if count == 1:
            log_result(f"pre_check:{label}", True, "exactly 1 match")
        else:
            log_result(f"pre_check:{label}", False,
                       f"found {count} matches - expected 1")
            aborted = True
    if aborted:
        print("\n" + "=" * 74, file=sys.stderr)
        print("ABORTED before writing anything. No backup made, file untouched.",
              file=sys.stderr)
        print("The file on disk differs from the GitHub copy this patch was",
              file=sys.stderr)
        print("built against. Run this and paste the output:", file=sys.stderr)
        print("", file=sys.stderr)
        print("  grep -n 'var speed_kts = _forward_speed' \\", file=sys.stderr)
        print("       godot_project/scripts/build_terrain.gd", file=sys.stderr)
        print("  grep -n 'PauseMenu' godot_project/scripts/build_terrain.gd",
              file=sys.stderr)
        print("  grep -n '_current_altitude = _character.position.y' \\",
              file=sys.stderr)
        print("       godot_project/scripts/build_terrain.gd", file=sys.stderr)
        print("  cat -A godot_project/scripts/build_terrain.gd | \\", file=sys.stderr)
        print("       grep -n 'speed_kts' ", file=sys.stderr)
        print("=" * 74, file=sys.stderr)
        sys.exit(1)

    backup = make_backup(TARGET)

    text = original
    for label, old, new in PATCHES:
        text = guarded_replace(text, old, new, label)

    # Rule #35: everything the new code calls must actually exist.
    required = [
        "_update_hud_readouts",
        "_dump_all_labels",
        "_malfunction_name",
        "_get_current_descent_rate",
        "_apply_malfunction_effects",
        "_check_decision_altitude",
        "toggle_pause",
    ]
    if not undefined_symbol_gate(text, required):
        shutil.copy2(backup, TARGET)
        log_result("abort_undefined_symbol", False, "restored backup")
        sys.exit(1)

    if not check_indentation(text, "full_file"):
        shutil.copy2(backup, TARGET)
        log_result("abort_indentation", False, "restored backup")
        sys.exit(1)

    if not pre_delivery_scan(text):
        shutil.copy2(backup, TARGET)
        log_result("abort_scan", False, "restored backup")
        sys.exit(1)

    # Rule #9: read-after-write consistency
    TARGET.write_text(text, encoding="utf-8")
    readback = TARGET.read_text(encoding="utf-8")
    if readback != text:
        shutil.copy2(backup, TARGET)
        log_result("read_after_write", False, "MISMATCH - restored backup")
        sys.exit(1)
    log_result("read_after_write", True, f"{len(readback)} bytes verified")

    # Evidence note (project convention: notes/<name>_<ts>.txt, pushed to git)
    ts_now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    note_path = NOTES_DIR / f"fix_hud_vario_pause_p2_{ts_now}.txt"
    note = (
        f"fix_hud_vario_pause_p2.py - {ts_now} UTC\n"
        f"Target: {TARGET}\n"
        f"Backup: {backup}\n"
        f"Bytes:  {len(original)} -> {len(readback)}\n"
        f"\n"
        f"PATCHES APPLIED (all verified exactly-1-match before writing):\n"
        f"  A  HUD writes moved out of FREEFALL-only branch\n"
        f"  B  _descent_rate member assigned (VARIO was hardwired to 0.00)\n"
        f"  C  _update_hud_readouts() called on the common path\n"
        f"  D  $PauseMenu null-guarded + [PAUSETEL] telemetry\n"
        f"  E  _update_hud_readouts() and _dump_all_labels() appended\n"
        f"  F  one-shot label dump scheduled from _ready()\n"
        f"\n"
        f"EVIDENCE THIS FIX WAS BUILT FROM:\n"
        f"  Screenshots 2026-08-02 11:24:47 / 11:25:10 / 11:25:37 / 11:25:57\n"
        f"    altimeter panel: 5142 -> 4813 -> 4443 -> 4175 ft (live)\n"
        f"    HUD Label0:      6044 ft in ALL FOUR (frozen)\n"
        f"    HUD VARIO:       +0.0 / 0.00 m/s in ALL FOUR (hardwired zero)\n"
        f"    HUD TURN:        50 in ALL FOUR (frozen)\n"
        f"    forensic panel:  pause ! UNVERIFIED, restart ! UNVERIFIED\n"
        f"    six orphan Labels named Label0..Label5 over the HUD\n"
        f"\n"
        f"EXPECTED EVIDENCE ON THE NEXT RUN - verify each, do not assume:\n"
        f"  1. HUD ALT tracks the altimeter panel after canopy deploy\n"
        f"     (they must agree to within one frame, not diverge)\n"
        f"  2. HUD VARIO shows a NON-ZERO value during descent\n"
        f"  3. [PAUSETEL] toggle_pause paused=... PauseMenu=FOUND|MISSING\n"
        f"     -> FOUND  = pause works, P5 closable for pause\n"
        f"     -> MISSING = PauseMenu absent from main.tscn, that is the\n"
        f"                  real P5 root cause and the next thing to fix\n"
        f"  4. [LABELDUMP_HDR] then [LABELDUMP],N,<name>,<parent>,<script>,<text>\n"
        f"     -> find the rows named Label0..Label5 and read their parent\n"
        f"        path and script. THAT is the file creating them.\n"
        f"  5. [LABELDUMP] total Label nodes in tree: N\n"
        f"\n"
        f"NOT FIXED THIS ROUND (deliberately, per Rule #14 - not yet grounded):\n"
        f"  - orphan Label0..Label5: diagnostic only, creator unknown\n"
        f"  - terrain hatching still visible despite sigma=6 blur\n"
        f"  - canopy scale/placement relative to jumper looks wrong\n"
        f"  - PiP shows disembodied forearms, no canopy framing\n"
        f"  - large grey void where terrain mesh does not cover\n"
        f"  - restart (R) still UNVERIFIED; no telemetry added for it yet\n"
    )
    note_path.write_text(note, encoding="utf-8")
    log_result("note_written", True, str(note_path))

    print("\n=== fix_hud_vario_pause_p2.py COMPLETE ===")
    print(f"Backup: {backup}")
    print(f"Note:   {note_path}")
    print("")
    print("NEXT (push recipe requires -f and --no-verify; notes/, *.py, *.txt")
    print("are all gitignored - confirmed by recover_and_push_20260802155256.txt):")
    print(f"  TS={ts_now}")
    print("  python3 autostall_patched.py --no-timeout 2>&1 | "
          f"tee notes/autostall_p2_{ts_now}.txt")
    print("")
    print("  # Rule #29 exact-error verification - grep each marker:")
    print(f"  grep -c 'LABELDUMP'  notes/autostall_p2_{ts_now}.txt")
    print(f"  grep    'PAUSETEL'   notes/autostall_p2_{ts_now}.txt")
    print(f"  grep -o 'VARIO: [^ ]*' notes/autostall_p2_{ts_now}.txt | sort -u | head")
    print("")
    print("  git add -f godot_project/scripts/build_terrain.gd \\")
    print("             fix_hud_vario_pause_p2.py \\")
    print(f"             notes/autostall_p2_{ts_now}.txt \\")
    print(f"             {note_path.name and 'notes/' + note_path.name}")
    print("  git diff --cached --name-only | wc -l   # Rule #43 scope check")
    print("  git commit --no-verify -m 'p2: HUD freeze, VARIO zero, pause guard'")
    print("  git push origin main")
    print("")
    print("  https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/"
          f"main/notes/autostall_p2_{ts_now}.txt")


if __name__ == "__main__":
    main()
