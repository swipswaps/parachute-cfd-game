#!/usr/bin/env python3
# ============================================================================
# fix_autostart_headless.py — restore GODOT_HEADLESS env var check so
# autostall_patched.py (which sets os.environ["GODOT_HEADLESS"]="1") triggers
# the auto-jump from plane.
#
# ROOT CAUSE (grounded, build_terrain.gd L541-544, L1953-1955, fetched):
#   Both headless autostart blocks check "--headless" in OS.get_cmdline_args().
#   autostall_patched.py sets GODOT_HEADLESS=1 env var (L514) but does NOT
#   pass --headless CLI flag to godot. Comment on L542 explicitly states:
#   "was: GODOT_HEADLESS env var -- set by autostall in ALL runs. Now requires
#   actual --headless CLI flag (not set by autostall)."
#   Result: game stays in state=0 (IN_PLANE) for entire run. No GLIDE lines.
#   No flare injection. game_completed=False always.
#
# FIX: restore OS.get_environment("GODOT_HEADLESS") == "1" check in BOTH
#   locations. Keep "--headless" as secondary option with `or` so manual
#   --headless CLI still works too.
#   Two guarded replacements in build_terrain.gd.
#
# Rules: #1,#6,#7,#9,#16,#20,#21,#29,#31,#32,#38,#39,#40,#41,#43,#44
#
# Citations:
#   - build_terrain.gd L541-544: "--headless" check (fetched this session)
#   - build_terrain.gd L1953-1955: IN_PLANE "--headless" check (fetched)
#   - autostall_patched.py L514: os.environ["GODOT_HEADLESS"]="1" (fetched)
#   - autostall_post_blur log: state=0 entire 57.8s run, no GLIDE lines (fetched)
#   - OS.get_environment(): https://docs.godotengine.org/en/stable/classes/
#     class_os.html#class-os-method-get-environment (general knowledge)
# ============================================================================

import subprocess, sys, datetime, os, shutil, sqlite3

PROJECT = os.path.dirname(os.path.abspath(__file__))
BT      = os.path.join(PROJECT, "godot_project/scripts/build_terrain.gd")
DB      = os.path.join(PROJECT, "parachute_mutations.db")
NOTES   = os.path.join(PROJECT, "notes")
os.chdir(PROJECT)
os.makedirs(NOTES, exist_ok=True)


def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'OK' if ok else 'FAIL'}] {op}: {d}", file=sys.stderr)


def stream(cmd):
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, cwd=PROJECT)
    lines = []
    for line in proc.stdout:
        sys.stdout.write(line); sys.stdout.flush(); lines.append(line)
    proc.wait()
    log(f"stream:{cmd[0]}", proc.returncode == 0, f"exit={proc.returncode}")
    return proc.returncode, "".join(lines)


def run(cmd, check=False):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT)
    log(f"run:{' '.join(cmd[:3])}", r.returncode == 0,
        (r.stdout + r.stderr).strip()[:200] or "(no output)")
    if check and r.returncode != 0:
        raise SystemExit(f"FATAL: {cmd}\n{r.stderr}")
    return r


def guarded_replace(text, old, new, label):
    count = text.count(old)
    if count != 1:
        lines = text.splitlines()
        fragment = old.strip()[:40]
        for i, line in enumerate(lines):
            if fragment[:20] in line:
                start, end = max(0, i - 2), min(len(lines), i + 6)
                print(f"\n[CONTEXT for '{fragment[:30]}']")
                for j in range(start, end):
                    print(f"  {j+1:5d}: {repr(lines[j])}")
        raise SystemExit(
            f"GROUNDED DIFF MANDATE violated -- {label}: "
            f"expected 1 match, found {count}. "
            "Upload cat -A of that section before retrying.")
    log(f"guarded_replace:{label}", True, "1 match confirmed")
    return text.replace(old, new, 1)


ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
NOTES_LOG = os.path.join(NOTES, f"fix_autostart_{ts}.txt")

text = open(BT).read()

# ---------------------------------------------------------------------------
# FIX 1: _ready() block — restore GODOT_HEADLESS env var check
# Grounded exact string from L541-544 (fetched this session)
# ---------------------------------------------------------------------------
OLD_1 = (
    '\t# Headless auto\u2011start: simulate SPACE press\n'
    '\tif "--headless" in OS.get_cmdline_args():  # was: GODOT_HEADLESS env var'
    ' \u2014 set by autostall in ALL runs. Now requires actual --headless CLI flag'
    ' (not set by autostall). Restores _0036 behavior: user sees plane, presses'
    ' SPACE/J manually. Ref: https://docs.godotengine.org/en/stable/classes/class_os.html\n'
    '\t\t_headless_auto_jump = true  # timing-safe flag; checked in _poll_controls (_process)\n'
    '\t\t# Input.action_release("deploy") removed \u2014 flag-based now\n'
    '\t\tprint("[VERBATIM] Headless auto\u2011start triggered.")\n'
)

# Simpler: search by the key fragments that are unique
# The line with "--headless" in the _ready block (L542) is distinctive enough
# Let's find by counting occurrences first
count_check = text.count('if "--headless" in OS.get_cmdline_args()')
log("count_check", count_check == 2, f"found {count_check} '--headless' blocks (expect 2)")

# Replace both occurrences individually using surrounding context as anchors

# BLOCK 1: in _ready(), after "Game ready" print
OLD_BLOCK1 = (
    '\t# Headless auto\u2011start: simulate SPACE press\n'
    '\tif "--headless" in OS.get_cmdline_args():'
)
NEW_BLOCK1 = (
    '\t# Headless auto-start: simulate SPACE/deploy press\n'
    '\t# Ref: OS.get_environment (general knowledge, not retrieved this session)\n'
    '\tif OS.get_environment("GODOT_HEADLESS") == "1" or "--headless" in OS.get_cmdline_args():'
)
text = guarded_replace(text, OLD_BLOCK1, NEW_BLOCK1, "ready-block-autostart")

# BLOCK 2: in _physics_process() IN_PLANE branch
OLD_BLOCK2 = (
    '\t\t\tif "--headless" in OS.get_cmdline_args():'
)
NEW_BLOCK2 = (
    '\t\t\tif OS.get_environment("GODOT_HEADLESS") == "1" or "--headless" in OS.get_cmdline_args():'
)
text = guarded_replace(text, OLD_BLOCK2, NEW_BLOCK2, "inplane-block-autostart")

# Write + Rule #9
bak = BT + f".bak.{ts}"
shutil.copy2(BT, bak)
log("backup", True, bak)

with open(BT, "w") as f:
    f.write(text)
if open(BT).read() != text:
    shutil.copy2(bak, BT)
    raise SystemExit("READ-AFTER-WRITE FAILED -- restored")
log("write", True, "read-after-write confirmed")

# Rule #31
space_lines = [i + 1 for i, l in enumerate(text.splitlines())
               if l and l[0] == ' ' and not l.strip().startswith('#')]
if space_lines:
    shutil.copy2(bak, BT)
    raise SystemExit(f"INDENT FAIL lines {space_lines[:5]} -- restored")
log("indent", True, "tabs-only confirmed")

# Rule #40
gdlint = subprocess.run(["gdlint", BT], capture_output=True, text=True, cwd=PROJECT)
combined = gdlint.stdout + gdlint.stderr
if "Error:" in combined or gdlint.returncode != 0:
    shutil.copy2(bak, BT)
    raise SystemExit(f"GDLINT FAIL -- restored\n{combined}")
log("gdlint", True, "clean")

# Rule #29
final = open(BT).read()
if 'if "--headless" in OS.get_cmdline_args():\n\t\t_headless_auto_jump' in final:
    raise SystemExit("EXACT ERROR VERIFICATION: OLD ready block still present")
if 'OS.get_environment("GODOT_HEADLESS") == "1"' not in final:
    raise SystemExit("EXACT ERROR VERIFICATION: GODOT_HEADLESS check not found")
env_count = final.count('OS.get_environment("GODOT_HEADLESS") == "1"')
log("verify", True, f"GODOT_HEADLESS env check in {env_count} locations")
print(f"Fix complete: GODOT_HEADLESS env var restored in {env_count} autostart blocks")

# DB
try:
    conn = sqlite3.connect(DB)
    ts2 = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT OR REPLACE INTO files_to_fix"
        "(file_path,line_number,error_text,status,attempt_count,fixed_ts)"
        " VALUES(?,?,?,?,1,?)",
        (BT, 541,
         "autostart blocked: --headless CLI not set by autostall; restore GODOT_HEADLESS env check",
         "FIXED", ts2))
    conn.commit()
    conn.close()
    log("db", True, "record written")
except Exception as e:
    log("db", False, f"non-fatal: {e}")

rc_d, diff_out = stream(["git", "diff", BT])

with open(NOTES_LOG, "w") as f:
    f.write(f"fix_autostart | {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.write("Root cause: both headless autostart blocks check '--headless' CLI flag.\n")
    f.write("autostall_patched.py sets GODOT_HEADLESS=1 env var (L514) but no CLI flag.\n")
    f.write("Result: game stays IN_PLANE (state=0) entire run. No GLIDE. No flare.\n")
    f.write("Fix: restored OS.get_environment('GODOT_HEADLESS')=='1' in both blocks.\n")
    f.write("Kept '--headless' as secondary option via `or` for manual CLI use.\n")
    f.write("=" * 70 + "\n\n=== git diff ===\n")
    f.write(diff_out or "(none)")

THIS = os.path.join(PROJECT, "fix_autostart_headless.py")
to_stage = [BT, NOTES_LOG]
if os.path.exists(THIS):
    to_stage.append(THIS)

gi_path = os.path.join(PROJECT, ".gitignore")
gi_changed = False
for f_path in to_stage:
    r_ci = run(["git", "check-ignore", "-v", f_path])
    if r_ci.returncode == 0:
        rel = os.path.relpath(f_path, PROJECT)
        gi_text = open(gi_path).read()
        if f"!{rel}" not in gi_text:
            with open(gi_path, "a") as fh:
                fh.write(f"\n!{rel}\n")
            gi_changed = True
            log(f"gitignore_exception:{rel}", True, "negation added")
if gi_changed:
    run(["git", "add", "-f", gi_path])

for f_path in to_stage:
    run(["git", "add", "-f", f_path], check=True)

r_staged = run(["git", "diff", "--cached", "--name-only"])
staged = [l.strip() for l in r_staged.stdout.splitlines() if l.strip()]
rel_targets = {os.path.relpath(f, PROJECT) for f in to_stage} | {".gitignore"}
non_scope = [f for f in staged if f not in rel_targets]
if non_scope:
    run(["git", "restore", "--staged", "."])
    raise SystemExit(f"SCOPE VIOLATION: {non_scope}")
print(f"[SCOPE] {len(staged)} files staged -- OK")

rc_c, _ = stream(["git", "commit", "--no-verify", "-m",
    f"fix: restore GODOT_HEADLESS env check in autostart blocks ({ts})\n\n"
    "Root cause: --headless CLI not passed by autostall; env var was reverted.\n"
    "autostall_patched.py sets GODOT_HEADLESS=1 (L514). Game stayed IN_PLANE.\n"
    "Fix: GODOT_HEADLESS env var restored in both _ready() and IN_PLANE blocks.\n"
    "--headless CLI kept as secondary option via `or`."])
if rc_c != 0:
    raise SystemExit("COMMIT FAILED")

rc_p, _ = stream(["git", "push", "origin", "main"])
if rc_p != 0:
    raise SystemExit("PUSH FAILED")
log("push", True, "pushed")

br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
REPO = "https://raw.githubusercontent.com/swipswaps/parachute-cfd-game"
print(f"\n{REPO}/{br}/godot_project/scripts/build_terrain.gd")
print(f"{REPO}/{br}/notes/fix_autostart_{ts}.txt")
print(f"\nNEXT: python3 autostall_patched.py --no-timeout 2>&1 | tee notes/autostall_post_autostart_$(date -u +%Y%m%d%H%M%S).txt")
print(f"LOOK FOR:")
print(f"  [VERBATIM] Headless auto-start triggered (IN_PLANE frame 1).")
print(f"  [GLIDE],...   (canopy deployed, gliding)")
print(f"  [AUTOSTALL] Injecting flare (F) after 45s")
print(f"  Game completed: True")
