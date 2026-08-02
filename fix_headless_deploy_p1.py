#!/usr/bin/env python3
# ============================================================================
# fix_headless_deploy_p1.py – Add _headless_auto_deploy flag so the canopy
# deploys automatically during headless autostall runs.
#
# Root cause (Rule #2 / grounded evidence):
#   autostall_patched.py sets GODOT_HEADLESS=1 and does NOT pass --headless CLI.
#   _physics_process IN_PLANE block fires Input.action_press("deploy") at frame 1
#   while _game_state is still IN_PLANE. By the time state transitions to FREEFALL,
#   the action is no longer "just pressed". No deploy ever fires headlessly.
#   Live evidence: autostall_timed_20260802131041.txt — hundreds of
#   [VERBATIM] POLL: checking deploy state=1 canopy=false with no deploy.
#
# Fix: Add _headless_auto_deploy bool flag; set alongside headless jump;
#   consume in _poll_controls() FREEFALL branch.
#
# Rules complied with: #1, #2, #4, #6, #7, #8, #9, #10, #15, #16, #21,
#   #22, #24, #25, #29, #30, #31, #35, #38, #41.
# No sed. No set -e. Tabs only in GDScript output.
#
# Citations (Godot documentation):
#   - OS.get_environment(): https://docs.godotengine.org/en/stable/classes/class_os.html
#     (general knowledge — not retrieved this session)
#   - Input.is_action_just_pressed():
#     https://docs.godotengine.org/en/stable/classes/class_input.html
#     (general knowledge — not retrieved this session)
#   - GameState enum / _game_state: build_terrain.gd (retrieved this session)
#   - _deploy_canopy(): build_terrain.gd (retrieved this session)
#
# Tools used: python3, shutil, datetime. No sed. No subprocess.run for file ops.
# ============================================================================

import sys
import shutil
import datetime
from pathlib import Path

def log_result(operation: str, success: bool, detail: str) -> None:
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)

PROJECT_ROOT = Path("/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game")
TARGET = PROJECT_ROOT / "godot_project" / "scripts" / "build_terrain.gd"
NOTES_DIR = PROJECT_ROOT / "notes"

def check_deps():
    if not TARGET.exists():
        log_result("dep_check", False, f"Target not found: {TARGET}")
        sys.exit(1)
    if not NOTES_DIR.exists():
        NOTES_DIR.mkdir(parents=True)
    log_result("dep_check", True, f"Target exists: {TARGET}")

def make_backup(path: Path) -> Path:
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak.{ts}")
    shutil.copy2(path, backup)
    import hashlib
    sha = hashlib.sha256(backup.read_bytes()).hexdigest()
    log_result("backup", True, f"{backup} sha256={sha}")
    return backup

def guarded_replace(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        log_result(f"guarded_replace:{label}", False,
                   f"expected 1 match, found {count} — REFUSING")
        raise AssertionError(f"PRECONDITION VIOLATED [{label}]: expected 1 match, found {count}\n"
                             f"old_str={repr(old[:80])}")
    result = text.replace(old, new, 1)
    log_result(f"guarded_replace:{label}", True, "1 match replaced")
    return result

def check_indentation(content: str, label: str) -> bool:
    violations = []
    for i, line in enumerate(content.splitlines(), 1):
        if line and line[0] == ' ' and line.strip():
            violations.append(i)
    if violations:
        log_result(f"check_indentation:{label}", False,
                   f"leading spaces on lines: {violations[:10]}")
        return False
    log_result(f"check_indentation:{label}", True, "tabs-only indentation OK")
    return True

def pre_delivery_scan(content: str) -> bool:
    import re
    forbidden = [
        (r'(?:^|[^a-zA-Z_])sed(?:[^a-zA-Z_]|$)', "sed usage"),
        (r'2>/dev/null', "stderr suppression"),
        (r'\bset -e\b', "set -e"),
        (r'\butcnow\(\)', "utcnow() deprecated"),
    ]
    found = []
    for pattern, desc in forbidden:
        if re.search(pattern, content, re.MULTILINE):
            found.append(desc)
    if found:
        log_result("pre_delivery_scan", False, f"FORBIDDEN patterns: {found}")
        return False
    log_result("pre_delivery_scan", True, "no forbidden patterns")
    return True

PATCH1_OLD = 'var _headless_auto_jump: bool = false  # set by IN_PLANE headless patch; consumed in _poll_controls'
PATCH1_NEW = ('var _headless_auto_jump: bool = false  # set by IN_PLANE headless patch; consumed in _poll_controls\n'
              'var _headless_auto_deploy: bool = false  # set when headless jump fires; consumed in FREEFALL _poll_controls')

PATCH2_OLD = ('\t\t\t\tif not ProjectSettings.has_setting("_headless_space_fired"):\n'
              '\t\t\t\t\tProjectSettings.set_setting("_headless_space_fired", true)\n'
              '\t\t\t\t\tInput.action_press("deploy")\n'
              '\t\t\t\t\tInput.action_release("deploy")\n'
              '\t\t\t\t\tprint("[VERBATIM] Headless auto-start triggered (IN_PLANE frame 1).")')
PATCH2_NEW = ('\t\t\t\tif not ProjectSettings.has_setting("_headless_space_fired"):\n'
              '\t\t\t\t\tProjectSettings.set_setting("_headless_space_fired", true)\n'
              '\t\t\t\t\tInput.action_press("deploy")\n'
              '\t\t\t\t\tInput.action_release("deploy")\n'
              '\t\t\t\t\t_headless_auto_deploy = true\n'
              '\t\t\t\t\tprint("[VERBATIM] Headless auto-start triggered (IN_PLANE frame 1).")')

PATCH3_OLD = ('\tprint("[VERBATIM] POLL: checking deploy state=", _game_state, " canopy=", _canopy_deployed)\n'
              '\tif Input.is_action_just_pressed("deploy") and not _canopy_deployed:\n'
              '\t\tprint("[VERBATIM] POLL: deploy pressed - calling _deploy_canopy")\n'
              '\t\t_deploy_canopy()')
PATCH3_NEW = ('\tprint("[VERBATIM] POLL: checking deploy state=", _game_state, " canopy=", _canopy_deployed)\n'
              '\t# Headless auto-deploy: fired when _headless_auto_deploy set in IN_PLANE frame 1.\n'
              '\t# _deploy_canopy() requires state==FREEFALL; this flag is consumed only here,\n'
              '\t# so it fires on the first FREEFALL _poll_controls() call.\n'
              '\t# Ref: https://docs.godotengine.org/en/stable/classes/class_input.html\n'
              '\t# (general knowledge — not retrieved this session)\n'
              '\tif _headless_auto_deploy and _game_state == GameState.FREEFALL and not _canopy_deployed:\n'
              '\t\t_headless_auto_deploy = false\n'
              '\t\tprint("[VERBATIM] Headless auto-deploy triggered (FREEFALL).")\n'
              '\t\t_deploy_canopy()\n'
              '\tif Input.is_action_just_pressed("deploy") and not _canopy_deployed:\n'
              '\t\tprint("[VERBATIM] POLL: deploy pressed - calling _deploy_canopy")\n'
              '\t\t_deploy_canopy()')

def main():
    check_deps()

    original = TARGET.read_text(encoding="utf-8")
    log_result("read_file", True, f"{len(original)} bytes read from {TARGET}")

    for label, old in [("patch1_var", PATCH1_OLD),
                        ("patch2_physics", PATCH2_OLD),
                        ("patch3_poll", PATCH3_OLD)]:
        count = original.count(old)
        if count != 1:
            log_result(f"pre_check:{label}", False,
                       f"Expected 1 match, found {count}. ABORTING.")
            sys.exit(1)
        log_result(f"pre_check:{label}", True, f"Exactly 1 match found")

    backup = make_backup(TARGET)

    text = original
    text = guarded_replace(text, PATCH1_OLD, PATCH1_NEW, "add_var_decl")
    text = guarded_replace(text, PATCH2_OLD, PATCH2_NEW, "set_flag_in_physics_process")
    text = guarded_replace(text, PATCH3_OLD, PATCH3_NEW, "consume_flag_in_poll_controls")

    if not check_indentation(text, "full_file"):
        log_result("abort_indentation", False, "Aborting due to indentation violations")
        sys.exit(1)

    if not pre_delivery_scan(text):
        log_result("abort_scan", False, "Aborting due to forbidden patterns")
        sys.exit(1)

    TARGET.write_text(text, encoding="utf-8")
    readback = TARGET.read_text(encoding="utf-8")
    if readback != text:
        log_result("read_after_write", False, "READ-AFTER-WRITE MISMATCH — restoring backup")
        shutil.copy2(backup, TARGET)
        sys.exit(1)
    log_result("read_after_write", True, f"{len(readback)} bytes written and verified")

    ts_now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    note_path = NOTES_DIR / f"fix_headless_deploy_p1_{ts_now}.txt"
    note = (
        f"fix_headless_deploy_p1.py ran at {ts_now} UTC\n"
        f"Target: {TARGET}\n"
        f"Backup: {backup}\n"
        f"Patches applied:\n"
        f"  1. Added var _headless_auto_deploy: bool = false\n"
        f"  2. Set _headless_auto_deploy = true in _physics_process IN_PLANE headless block\n"
        f"  3. Consume flag in _poll_controls() FREEFALL branch — calls _deploy_canopy()\n"
        f"Expected evidence after next autostall run:\n"
        f"  [VERBATIM] Headless auto-deploy triggered (FREEFALL).\n"
        f"  [VERBATIM] ENTER _deploy_canopy gate=none\n"
        f"  [VERBATIM] Parachute deployment started — state=OPENING_ANIM\n"
        f"  [VERBATIM] EXIT _deploy_canopy ok=true\n"
        f"  Then GLIDE lines with non-zero pull values.\n"
    )
    note_path.write_text(note, encoding="utf-8")
    log_result("note_written", True, str(note_path))

    print(f"\n=== fix_headless_deploy_p1.py COMPLETE ===")
    print(f"Backup:    {backup}")
    print(f"Note:      {note_path}")
    print(f"Next step: python3 autostall_patched.py --no-timeout 2>&1 | tee notes/autostall_post_deploy_{ts_now}.txt")
    print(f"Evidence:  look for '[VERBATIM] Parachute deployment started'")
    print(f"Then push: git add godot_project/scripts/build_terrain.gd notes/ && git commit -m 'P1: headless auto-deploy flag' && git push")
    print(f"Raw link:  https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main/notes/fix_headless_deploy_p1_{ts_now}.txt")

if __name__ == "__main__":
    main()
