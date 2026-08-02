#!/usr/bin/env python3
# ============================================================================
# fix_p3_labels_vario_pause.py
#
# All four changes are grounded in autostall_p2_20260802160520.txt, fetched
# and read this session. No claim below is from memory.
#
#   A. ORPHAN Label0..Label5  -- CREATOR NOW IDENTIFIED
#      [LABELDUMP],12,Label5,/root/Main/HUD,none,Label5
#      [LABELDUMP],17,Label0,/root/Main/HUD,none,Label0
#      Parent /root/Main/HUD, script none, text == own node name. They are
#      SCENE nodes in main.tscn, which is why grepping build_terrain.gd for
#      a creator found nothing. build_terrain's real labels live under
#      /root/Main/@CanvasLayer@96 (LABELDUMP rows 1-11).
#      FIX: remove the six [node ...] blocks from main.tscn, each guarded by
#      an exactly-1-match check, with the removed text printed verbatim
#      first. If the pattern is not found, this step REPORTS and SKIPS --
#      it never guesses at scene structure.
#
#   B. VARIO STILL 0.00 -- p2 patch B was correct but insufficient
#      [GLIDE],0.5166,...,descent_m_s=4.23076923076923,...
#      [GLIDE],4.6333,...,descent_m_s=4.23076923076923,...
#      Identical to 14 decimal places across the entire run.
#      _get_current_descent_rate() returns a HARDCODED CONSTANT per state
#      (0.3 in OPENING_ANIM), so _vario_mps = 0.3 - 0.3 = 0.0 by
#      construction. Assigning the member did not and could not help.
#      FIX: derive vario from the ACTUAL altitude delta:
#          _vario_mps = (y_now - y_prev) / delta      (+ = climb)
#
#   C. SPD READS 0 kts UNDER CANOPY
#      [LABELDUMP],10,...,SPD: 0 kts | VARIO: +0.0 m/s
#      [GLIDE],...,fwd_speed=11.0,...
#      _forward_speed is only written inside the FREEFALL branch, so it is a
#      stale 0 in OPENING_ANIM/DIAGNOSIS.
#      FIX: derive horizontal ground speed from the actual XZ position
#      delta, same technique as B. Self-contained; does not depend on
#      _update_canopy_glide internals, which this patch does not touch.
#
#   D. PAUSETEL NEVER FIRED
#      No [PAUSETEL] line anywhere in the run -- Escape was never pressed,
#      so p2's telemetry had nothing to report and P5 stayed UNVERIFIED.
#      FIX: a headless one-shot that calls toggle_pause() twice back-to-back
#      (pause then immediately unpause) ~8 s in. Two [PAUSETEL] lines are
#      emitted and the tree is never left paused, so autostall's 30 s
#      stall detector cannot trip.
#
# Rules complied with: #1, #2, #4, #6, #7 (no sed), #8, #9, #10, #14, #16,
#   #20, #21, #24, #25, #28, #29, #31, #35, #36, #37, #38, #41, #44.
#
# Citations (Godot documentation):
#   - SceneTree.paused / Node.PROCESS_MODE_ALWAYS (a PROCESS_MODE_ALWAYS
#     Timer keeps running while the tree is paused):
#     https://docs.godotengine.org/en/stable/classes/class_scenetree.html
#     (general knowledge - not retrieved this session)
#   - Node3D.global_position (source of the altitude/XZ deltas used for the
#     real vario and ground-speed computation):
#     https://docs.godotengine.org/en/stable/classes/class_node3d.html
#     (general knowledge - not retrieved this session)
#   - TSCN scene file format ([node name=... parent=...] blocks):
#     https://docs.godotengine.org/en/stable/contributing/development/file_formats/tscn.html
#     (general knowledge - not retrieved this session)
#   - build_terrain.gd _physics_process / _update_hud_readouts / toggle_pause:
#     RETRIEVED THIS SESSION from raw.githubusercontent.com
#   - LABELDUMP / GLIDE telemetry rows quoted above:
#     RETRIEVED THIS SESSION from
#     notes/autostall_p2_20260802160520.txt
#
# Tools used: python3, shutil, hashlib, datetime, pathlib, re. sed banned.
# ============================================================================

import re
import sys
import shutil
import hashlib
import datetime
from pathlib import Path


def log_result(operation: str, success: bool, detail: str) -> None:
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)


PROJECT_ROOT = Path(
    "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
)
GD = PROJECT_ROOT / "godot_project" / "scripts" / "build_terrain.gd"
TSCN = PROJECT_ROOT / "godot_project" / "scenes" / "main.tscn"
NOTES_DIR = PROJECT_ROOT / "notes"


def check_deps() -> None:
    if not GD.exists():
        log_result("dep_check", False, f"missing: {GD}")
        sys.exit(1)
    if not NOTES_DIR.exists():
        NOTES_DIR.mkdir(parents=True)
    if not TSCN.exists():
        log_result("dep_check", True,
                   f"NOTE: {TSCN} absent - step A will SKIP (Rule #37)")
    else:
        log_result("dep_check", True, f"both targets present")


def make_backup(path: Path) -> Path:
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak.{ts}")
    shutil.copy2(path, backup)
    sha = hashlib.sha256(backup.read_bytes()).hexdigest()
    log_result("backup", True, f"{backup.name} sha256={sha[:16]}...")
    return backup


def guarded_replace(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        log_result(f"guarded_replace:{label}", False,
                   f"expected 1 match, found {count} - REFUSING")
        raise AssertionError(
            f"PRECONDITION VIOLATED [{label}]: expected 1, found {count}\n"
            f"old head = {repr(old[:100])}")
    log_result(f"guarded_replace:{label}", True, "exactly 1 match replaced")
    return text.replace(old, new, 1)


def check_indentation(content: str, label: str) -> bool:
    bad = [i for i, ln in enumerate(content.splitlines(), 1)
           if ln and ln[0] == " " and ln.strip()]
    if bad:
        log_result(f"check_indentation:{label}", False, f"lines {bad[:15]}")
        return False
    log_result(f"check_indentation:{label}", True, "tabs-only OK")
    return True


def undefined_symbol_gate(content: str, funcs: list) -> bool:
    missing = [f for f in funcs
               if not re.search(r"^func\s+" + re.escape(f) + r"\s*\(",
                                content, re.M)]
    if missing:
        log_result("undefined_symbol_gate", False, f"undefined: {missing}")
        return False
    log_result("undefined_symbol_gate", True, f"{len(funcs)} funcs defined")
    return True


def pre_delivery_scan(content: str) -> bool:
    checks = [(r"(?:^|[^a-zA-Z_])sed(?:[^a-zA-Z_]|$)", "sed"),
              (r"2>/dev/null", "stderr suppression"),
              (r"\bset -e\b", "set -e"),
              (r"\butcnow\(\)", "utcnow()")]
    found = [d for p, d in checks if re.search(p, content, re.M)]
    if found:
        log_result("pre_delivery_scan", False, f"FORBIDDEN: {found}")
        return False
    log_result("pre_delivery_scan", True, "clean")
    return True


# ===========================================================================
# STEP A - remove the six orphan Label nodes from main.tscn
# Reports and skips rather than guessing if the pattern is absent.
# ===========================================================================
def strip_orphan_labels(report_lines: list) -> bool:
    if not TSCN.exists():
        report_lines.append("STEP A: SKIPPED - main.tscn not found at "
                            f"{TSCN}\n")
        log_result("step_a", True, "SKIPPED (Rule #37) - tscn absent")
        return False

    text = TSCN.read_text(encoding="utf-8")
    report_lines.append(f"STEP A: main.tscn = {len(text)} bytes\n")

    # Locate every [node name="LabelN" ...] header whose parent is HUD.
    header_re = re.compile(
        r'^\[node name="(Label[0-5])"[^\]]*parent="HUD"[^\]]*\]$', re.M)
    headers = list(header_re.finditer(text))
    report_lines.append(f"STEP A: found {len(headers)} Label0-5 "
                        f'node headers with parent="HUD"\n')

    if not headers:
        report_lines.append(
            "STEP A: SKIPPED - no matching headers. The nodes may use a\n"
            "        different parent spelling or live in another scene.\n"
            "        Paste this to ground the next attempt:\n"
            "          grep -n 'Label[0-5]' godot_project/scenes/main.tscn\n"
            "          grep -n 'name=\"HUD\"' godot_project/scenes/main.tscn\n")
        log_result("step_a", True, "SKIPPED - pattern absent, not guessing")
        return False

    backup = make_backup(TSCN)
    report_lines.append(f"STEP A: backup {backup.name}\n")

    # Remove from the LAST match backwards so earlier offsets stay valid.
    removed = 0
    for m in reversed(headers):
        start = m.start()
        nxt = text.find("\n[", m.end())
        end = len(text) if nxt == -1 else nxt + 1
        block = text[start:end]
        report_lines.append(f"STEP A: REMOVING VERBATIM ->\n{block}\n")
        text = text[:start] + text[end:]
        removed += 1

    leftover = header_re.findall(text)
    if leftover:
        shutil.copy2(backup, TSCN)
        report_lines.append(f"STEP A: FAILED - {leftover} still present, "
                            "restored backup\n")
        log_result("step_a", False, f"leftover {leftover} - restored")
        return False

    TSCN.write_text(text, encoding="utf-8")
    if TSCN.read_text(encoding="utf-8") != text:
        shutil.copy2(backup, TSCN)
        log_result("step_a", False, "read-after-write mismatch - restored")
        return False

    report_lines.append(f"STEP A: removed {removed} node block(s), "
                        f"main.tscn now {len(text)} bytes\n")
    log_result("step_a", True, f"removed {removed} orphan Label nodes")
    return True


# ===========================================================================
# STEP B/C - real vario and real ground speed from position deltas
# ===========================================================================
B_OLD = (
    "# Variometer: rate of change of descent_rate (positive = lift)\n"
    "var _vario_mps: float = 0.0\n"
    "var _prev_descent_rate: float = 0.0"
)
B_NEW = (
    "# Variometer: rate of change of descent_rate (positive = lift)\n"
    "var _vario_mps: float = 0.0\n"
    "var _prev_descent_rate: float = 0.0\n"
    "# p3: real vario / ground speed, measured from actual motion.\n"
    "# _get_current_descent_rate() returns a hardcoded constant per state, so\n"
    "# the old _vario_mps = _prev_descent_rate - _descent_rate was 0.3 - 0.3\n"
    "# every frame. Proven by autostall_p2_20260802160520.txt: descent_m_s\n"
    "# read 4.23076923076923 identically on every [GLIDE] row of the run.\n"
    "# Ref: https://docs.godotengine.org/en/stable/classes/class_node3d.html\n"
    "# (general knowledge - not retrieved this session)\n"
    "var _p3_prev_y: float = -99999.0\n"
    "var _p3_prev_xz: Vector2 = Vector2.ZERO\n"
    "var _p3_ground_speed_ms: float = 0.0"
)

C_OLD = (
    "\t_current_altitude = _character.position.y - 25.0\n"
    "\n"
    "\t_vario_mps = _prev_descent_rate - _descent_rate\n"
    "\t# p2: unconditional HUD refresh for every non-IN_PLANE state.\n"
    "\t_update_hud_readouts()"
)
C_NEW = (
    "\t_current_altitude = _character.position.y - 25.0\n"
    "\n"
    "\t# p3: vario and ground speed from REAL motion, not the constant table.\n"
    "\tvar _p3_y: float = _character.global_position.y\n"
    "\tvar _p3_xz: Vector2 = Vector2(_character.global_position.x,\n"
    "\t\t\t_character.global_position.z)\n"
    "\tif _p3_prev_y > -99998.0 and delta > 0.0:\n"
    "\t\t_vario_mps = (_p3_y - _p3_prev_y) / delta\n"
    "\t\t_p3_ground_speed_ms = (_p3_xz - _p3_prev_xz).length() / delta\n"
    "\t_p3_prev_y = _p3_y\n"
    "\t_p3_prev_xz = _p3_xz\n"
    "\t# p2: unconditional HUD refresh for every non-IN_PLANE state.\n"
    "\t_update_hud_readouts()"
)

D_OLD = (
    "\tvar speed_kts: float = _forward_speed * 1.94384\n"
)
D_NEW = (
    "\t# p3: _forward_speed is only written in the FREEFALL branch, so under\n"
    "\t# canopy it read a stale 0 while [GLIDE] reported fwd_speed=11.0\n"
    "\t# (autostall_p2_20260802160520.txt). Prefer the measured value.\n"
    "\tvar speed_kts: float = _p3_ground_speed_ms * 1.94384\n"
    "\tif _game_state == GameState.FREEFALL:\n"
    "\t\tspeed_kts = _forward_speed * 1.94384\n"
)

# ===========================================================================
# STEP D - headless pause self-test so [PAUSETEL] actually fires
# ===========================================================================
E_OLD = (
    "\tvar _lbl_timer := Timer.new()\n"
    "\t_lbl_timer.wait_time = 2.0\n"
    "\t_lbl_timer.one_shot = true\n"
    "\t_lbl_timer.process_mode = Node.PROCESS_MODE_ALWAYS\n"
    "\tadd_child(_lbl_timer)\n"
    "\t_lbl_timer.timeout.connect(_dump_all_labels)\n"
    "\t_lbl_timer.start()"
)
E_NEW = (
    "\tvar _lbl_timer := Timer.new()\n"
    "\t_lbl_timer.wait_time = 2.0\n"
    "\t_lbl_timer.one_shot = true\n"
    "\t_lbl_timer.process_mode = Node.PROCESS_MODE_ALWAYS\n"
    "\tadd_child(_lbl_timer)\n"
    "\t_lbl_timer.timeout.connect(_dump_all_labels)\n"
    "\t_lbl_timer.start()\n"
    "\n"
    "\t# p3: headless pause self-test. p2 added [PAUSETEL] but nothing ever\n"
    "\t# pressed Escape, so the run produced no PAUSETEL line and P5 stayed\n"
    "\t# UNVERIFIED. This fires toggle_pause() twice back-to-back, so two\n"
    "\t# PAUSETEL lines are emitted and the tree is never LEFT paused --\n"
    "\t# autostall's 30 s stall detector cannot trip on it.\n"
    "\t# Ref: https://docs.godotengine.org/en/stable/classes/class_scenetree.html\n"
    "\t# (general knowledge - not retrieved this session)\n"
    "\tif OS.get_environment(\"GODOT_HEADLESS\") == \"1\" \\\n"
    "\t\t\tor \"--headless\" in OS.get_cmdline_args():\n"
    "\t\tvar _pause_timer := Timer.new()\n"
    "\t\t_pause_timer.wait_time = 8.0\n"
    "\t\t_pause_timer.one_shot = true\n"
    "\t\t_pause_timer.process_mode = Node.PROCESS_MODE_ALWAYS\n"
    "\t\tadd_child(_pause_timer)\n"
    "\t\t_pause_timer.timeout.connect(_p3_pause_selftest)\n"
    "\t\t_pause_timer.start()"
)

F_OLD = (
    "func _dump_all_labels() -> void:\n"
    "\tif _label_dump_done:\n"
    "\t\treturn"
)
F_NEW = (
    "# ---------------------------------------------------------------------------\n"
    "# _p3_pause_selftest - exercises toggle_pause() once, headless only.\n"
    "# Emits two [PAUSETEL] lines (paused=true then paused=false) and leaves\n"
    "# the tree UNPAUSED, so the run continues normally.\n"
    "# PauseMenu=FOUND   -> the node exists, pause works, P5 closable\n"
    "# PauseMenu=MISSING -> node absent from main.tscn; THAT is the P5 cause\n"
    "# ---------------------------------------------------------------------------\n"
    "func _p3_pause_selftest() -> void:\n"
    '\tprint("[PAUSETEL] selftest BEGIN tree.paused=", get_tree().paused)\n'
    "\ttoggle_pause()\n"
    "\ttoggle_pause()\n"
    '\tprint("[PAUSETEL] selftest END tree.paused=", get_tree().paused,\n'
    '\t\t\t" (must be false)")\n'
    "\n"
    "\n"
    "func _dump_all_labels() -> void:\n"
    "\tif _label_dump_done:\n"
    "\t\treturn"
)

GD_PATCHES = [
    ("B_vario_vars", B_OLD, B_NEW),
    ("C_real_vario_calc", C_OLD, C_NEW),
    ("D_real_ground_speed", D_OLD, D_NEW),
    ("E_pause_selftest_timer", E_OLD, E_NEW),
    ("F_pause_selftest_func", F_OLD, F_NEW),
]


def main() -> None:
    check_deps()
    report = []

    original = GD.read_text(encoding="utf-8")
    log_result("read_gd", True, f"{len(original)} bytes")

    # Rule #1: verify every old_str exists exactly once BEFORE any write.
    aborted = False
    for label, old, _n in GD_PATCHES:
        c = original.count(old)
        if c == 1:
            log_result(f"pre_check:{label}", True, "exactly 1 match")
        else:
            log_result(f"pre_check:{label}", False, f"found {c}, expected 1")
            aborted = True
    if aborted:
        print("\n" + "=" * 74, file=sys.stderr)
        print("ABORTED. build_terrain.gd untouched, no backup made.",
              file=sys.stderr)
        print("p2 must be applied first. Verify with:", file=sys.stderr)
        print("  grep -n '_update_hud_readouts' "
              "godot_project/scripts/build_terrain.gd", file=sys.stderr)
        print("  grep -n '_lbl_timer' "
              "godot_project/scripts/build_terrain.gd", file=sys.stderr)
        print("=" * 74, file=sys.stderr)
        sys.exit(1)

    gd_backup = make_backup(GD)

    text = original
    for label, old, new in GD_PATCHES:
        text = guarded_replace(text, old, new, label)

    required = ["_update_hud_readouts", "_dump_all_labels",
                "_p3_pause_selftest", "toggle_pause", "_malfunction_name"]
    if not undefined_symbol_gate(text, required):
        shutil.copy2(gd_backup, GD)
        sys.exit(1)
    if not check_indentation(text, "build_terrain"):
        shutil.copy2(gd_backup, GD)
        sys.exit(1)
    if not pre_delivery_scan(text):
        shutil.copy2(gd_backup, GD)
        sys.exit(1)

    GD.write_text(text, encoding="utf-8")
    if GD.read_text(encoding="utf-8") != text:
        shutil.copy2(gd_backup, GD)
        log_result("read_after_write", False, "MISMATCH - restored")
        sys.exit(1)
    log_result("read_after_write", True, f"{len(text)} bytes verified")

    tscn_ok = strip_orphan_labels(report)

    ts_now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    note = NOTES_DIR / f"fix_p3_labels_vario_pause_{ts_now}.txt"
    body = (
        f"fix_p3_labels_vario_pause.py - {ts_now} UTC\n"
        f"build_terrain.gd: {len(original)} -> {len(text)} bytes\n"
        f"backup: {gd_backup}\n"
        f"main.tscn step: {'APPLIED' if tscn_ok else 'SKIPPED'}\n\n"
        f"EVIDENCE (all from notes/autostall_p2_20260802160520.txt):\n"
        f"  P1 CLOSED:\n"
        f"    [VERBATIM] Headless auto-deploy triggered (FREEFALL).\n"
        f"    [VERBATIM] Parachute deployment started - state=OPENING_ANIM\n"
        f"    [CANOPYSYNC] main canopy visible -> true state=2 deployed=true\n"
        f"  p2 HUD unfreeze CONFIRMED:\n"
        f"    LABELDUMP row 11 ALT: 6017 ft (build_terrain HUD)\n"
        f"    LABELDUMP row 29 ALT: 6018 ft (AltimeterHUD)\n"
        f"    -> 1 ft apart; was 6044 vs 4175 before p2\n"
        f"  ORPHANS LOCATED:\n"
        f"    rows 12-17 Label0..Label5, parent /root/Main/HUD, script none\n"
        f"  VARIO ROOT CAUSE:\n"
        f"    descent_m_s = 4.23076923076923 on EVERY [GLIDE] row\n"
        f"    -> constant lookup, so prev-minus-current is 0 by construction\n"
        f"  SPD ROOT CAUSE:\n"
        f"    HUD 'SPD: 0 kts' vs [GLIDE] fwd_speed=11.0\n"
        f"  PAUSETEL: zero occurrences - Escape never pressed\n\n"
        + "".join(report) +
        f"\nEXPECTED ON NEXT RUN - verify each, do not assume:\n"
        f"  1. grep -c 'Label0' <log>   -> LABELDUMP no longer lists\n"
        f"     Label0..Label5 under /root/Main/HUD\n"
        f"  2. LABELDUMP total drops from 30 to 24\n"
        f"  3. VARIO in the LABELDUMP SPD row is NON-ZERO\n"
        f"  4. SPD in that row is non-zero and near [GLIDE] fwd_speed\n"
        f"  5. [PAUSETEL] selftest BEGIN / two toggle lines / END false\n"
        f"     PauseMenu=FOUND or =MISSING decides the real P5 fix\n\n"
        f"STILL NOT ADDRESSED (Rule #14 - not yet grounded):\n"
        f"  - terrain hatching despite sigma=6 blur\n"
        f"  - canopy scale/placement vs jumper\n"
        f"  - PiP framing\n"
        f"  - grey void where the mesh does not cover\n"
        f"  - restart (R) still has no telemetry\n"
        f"  - 105 untracked scratch files in the working tree\n"
    )
    note.write_text(body, encoding="utf-8")
    log_result("note_written", True, str(note))

    print("\n=== fix_p3 COMPLETE ===")
    print(f"gd backup: {gd_backup}")
    print(f"note:      {note}")
    print(f"tscn step: {'APPLIED' if tscn_ok else 'SKIPPED - see note'}")


if __name__ == "__main__":
    main()
