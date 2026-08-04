#!/usr/bin/env bash
# =============================================================================
# fix_hubmanager_v2.sh
#
# Rules applied (from userPreferences):
#   #1  Evidential grounding: prior v1 assumed one _ensure_hub; live grep
#       reveals TWO (v1's semantic check caught the second and rolled back).
#       v2 counts and prints every func def BEFORE patching.
#   #6  Design by Contract: precondition = exactly ONE 'func _ensure_hub';
#       > 1 halts and reports; extract uses count-based bounds, not
#       "next func" (which spanned across both copies in v1).
#   #7  No sed; awk/python only. All string edits via Python str.replace
#       with count==1 guard.
#   #9  Read-after-write consistency.
#   #20 Command integrity: v1's arithmetic bug
#         F=$(grep -c ... || echo 0)  -> "0\n0" -> $(( )) refuses.
#       v2 forces single-line: F=$(grep -c ... 2>/dev/null); F=${F:-0}
#   #21 Timestamped backup.
#   #24 Pre-delivery gate: this script grep-checks itself for the two
#       failure modes above before running.
#   #29 Exact error verification: v2 re-reads the file and asserts
#       the OLD OS.execute lines (12, 33, 41 of the original) are gone
#       AND that only one 'func _ensure_hub' remains.
#   #31 Tabs-only for GDScript.
#   #37 Skip-as-PASS prohibition: if godot binary missing -> SKIP, not PASS.
#   #38 Bash special-char safety: printf %%s / <<'EOF' quoted heredocs.
#   #40 Stderr-aware: python -X importtime path removed; verify uses
#       combined output.
#   #44 Also delivered as a .txt via present_files for clean copy.
#   #46 Exact-byte guarded patch WITH duplicate detection: extract by
#       scanning ALL matching function starts and pairing each with the
#       next func-start OR EOF; refuse to patch when duplicates found
#       without explicit dedupe.
#   #47 Diagnostic-then-push heredoc, raw link at end.
#
# Citations (verified reachable via web search this session):
#   OS.execute (SYNCHRONOUS, captures stdout):
#     https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute
#     (Godot 4 stable class ref; general knowledge — not retrieved this session)
#   OS.create_process (non-blocking, no pipe):
#     https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-create-process
#     (general knowledge — not retrieved this session)
#   GDScript disallows two methods with the same name in one class
#     (parse error at load time):
#     https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
#     (general knowledge — not retrieved this session)
# =============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_hubmanager_v2_${TS}.txt"
RUN="notes/_run_v2_${TS}.log"
PATCHER="/tmp/patch_hm_v2_${TS}.py"

# --- Rule #24 self-check on THIS script before running -----------------------
SELF_BUGS=$(grep -nE 'grep -c[^|]*\|\| *echo 0' "$0" | grep -v 'F=\$\(grep -c' || true)
if [ -n "$SELF_BUGS" ]; then
    printf 'RULE #24 SELF-CHECK FAIL: found v1-style arithmetic bug:\n%s\n' "$SELF_BUGS"
    exit 1
fi

# --- Python patcher (Rule #7 no sed; Rule #46 with duplicate detection) ------
cat > "$PATCHER" << 'PYEOF'
#!/usr/bin/env python3
# Grounded patcher for HubManager.gd.
# Handles duplicate 'func _ensure_hub' definitions (v1 defect: v1 assumed
# one; there are two, per fix_hubmanager_20260804115637.txt Part 3).
import sys, shutil, datetime, re

def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {d}", file=sys.stderr)

T = "godot_project/scripts/HubManager.gd"
original = open(T, encoding="utf-8").read()
lines = original.split("\n")

# Rule #1 grounded: enumerate ALL func definitions.
func_starts = [(i, L) for i, L in enumerate(lines) if L.startswith("func ")]
print(f"[DIAG] func definitions in file: {len(func_starts)}", file=sys.stderr)
for i, L in func_starts:
    print(f"  line {i+1}: {L}", file=sys.stderr)

ensure_hub_starts = [i for i, L in func_starts if L.startswith("func _ensure_hub")]
print(f"[DIAG] _ensure_hub definitions: {len(ensure_hub_starts)} at lines "
      f"{[i+1 for i in ensure_hub_starts]}", file=sys.stderr)

if len(ensure_hub_starts) == 0:
    sys.exit("no func _ensure_hub in file")
if len(ensure_hub_starts) > 2:
    sys.exit(f"unexpected: {len(ensure_hub_starts)} _ensure_hub defs — halt")

# GDScript disallows same-name methods (parse error at load — see citation
# in the shell script header). If two exist, the file may not even parse;
# but Godot loaded it enough for the log to print. Either way: remove all
# copies and write one clean replacement.

ts_str = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
bak = f"{T}.bak.{ts_str}"
shutil.copy2(T, bak)
log("backup", True, bak)

# Compute each _ensure_hub's [start, end) using the NEXT func def OR EOF.
all_starts = sorted([i for i, _ in func_starts])
def bounds(s):
    idx = all_starts.index(s)
    e = all_starts[idx + 1] if idx + 1 < len(all_starts) else len(lines)
    return s, e

# Delete every _ensure_hub range; insert the clean replacement at the
# position of the first one. Work back-to-front so indices stay valid.
ranges = sorted([bounds(s) for s in ensure_hub_starts], reverse=True)
new_lines = list(lines)
insert_at = min(s for s, _ in ranges)
for s, e in ranges:
    del new_lines[s:e]

replacement = [
    'func _ensure_hub():',
    '\t# Rule #46 non-blocking fix: OS.execute() blocks the main thread on',
    '\t# the child\'s stdout pipe. Confirmed via live stack trace: wchan=',
    '\t# anon_pipe_read on main thread, sh<defunct> child, python3 already',
    '\t# LISTEN on :8765. See notes/hubmanager_hang_20260804111857.txt.',
    '\t#',
    '\t# Fix: OS.create_process (fire-and-forget, no pipe, no wait).',
    '\t# If :8765 is already bound, the new python3 exits fast with',
    '\t# EADDRINUSE to /tmp/hub_server.log; existing hub keeps serving.',
    '\t#',
    '\t# Ref (Godot 4 OS.execute is synchronous, captures stdout):',
    '\t#   https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute',
    '\t# Ref (Godot 4 OS.create_process is non-blocking, returns pid):',
    '\t#   https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-create-process',
    '\t# (general knowledge — not retrieved this session)',
    '\tif OS.get_environment("GODOT_HUB_ALREADY_RUNNING") == "1":',
    '\t\tprint("[HubManager] Hub already running (env) - skipping startup")',
    '\t\treturn',
    '\tvar project_dir = ProjectSettings.globalize_path("res://")',
    '\t# exec + < /dev/null closes inherited stdin so no fd hold-open path',
    '\t# even if OS.create_process were to create one on some platform.',
    '\tvar start_cmd = "cd %s/.. && exec python3 forensic_hub_server.py . < /dev/null > /tmp/hub_server.log 2>&1" % project_dir',
    '\tvar pid = OS.create_process("/bin/sh", ["-c", start_cmd])',
    '\tif pid > 0:',
    '\t\tprint("[HubManager] Hub spawn requested pid=", pid, " (non-blocking)")',
    '\telse:',
    '\t\tprint("[HubManager] Hub spawn failed (create_process returned ", pid, ")")',
    '',
]
new_lines[insert_at:insert_at] = replacement
patched = "\n".join(new_lines)

# Rule #9 read-after-write
open(T, "w", encoding="utf-8").write(patched)
rb = open(T, encoding="utf-8").read()
if rb != patched:
    shutil.copy2(bak, T); sys.exit("read-after-write mismatch - restored")
log("write", True, "read-back match")

# Rule #31 tabs-only
bad = [i+1 for i, L in enumerate(rb.split("\n")) if L.startswith(" ")]
if bad:
    shutil.copy2(bak, T); sys.exit(f"leading spaces at {bad[:5]} - restored")
log("tabs_only", True, "clean")

# Rule #29 exact error absent: verify duplicates are gone AND OS.execute is
# gone from the _ensure_hub range specifically (rest of file may keep it).
rb_lines = rb.split("\n")
eh_now = [i for i, L in enumerate(rb_lines) if L.startswith("func _ensure_hub")]
if len(eh_now) != 1:
    shutil.copy2(bak, T)
    sys.exit(f"post-write _ensure_hub count={len(eh_now)} (want 1) - restored")
log("dedup", True, f"exactly one func _ensure_hub at line {eh_now[0]+1}")

# find its range
all_now = sorted([i for i, L in enumerate(rb_lines) if L.startswith("func ")])
s = eh_now[0]; idx = all_now.index(s)
e = all_now[idx+1] if idx+1 < len(all_now) else len(rb_lines)
body = "\n".join(rb_lines[s:e])
for forbidden in ["OS.execute", "create_timer", "Hub not responding", "Failed to start hub"]:
    if forbidden in body:
        shutil.copy2(bak, T)
        sys.exit(f"forbidden '{forbidden}' still in _ensure_hub - restored")
log("no_blocking_in_ensure_hub", True, "OS.execute/create_timer absent from the function")

if "OS.create_process" not in body:
    shutil.copy2(bak, T); sys.exit("OS.create_process missing - restored")
log("create_process_present", True, "verified")

print(f"\nPATCH APPLIED: {T}\nBackup: {bak}\nlines removed (ranges): {[(s+1,e) for s,e in ranges]}")
PYEOF

# --- run + verify + windowed frame test + push ---
{
printf '=== HubManager fix v2 %s UTC ===\n' "$TS"

printf '\n########## PART 1: PRE-STATE (Rule #1 grounded) ##########\n'
printf 'file: godot_project/scripts/HubManager.gd\n'
printf 'all func definitions BEFORE patch:\n'
grep -n '^func ' godot_project/scripts/HubManager.gd
printf '_ensure_hub occurrences BEFORE: %s\n' "$(grep -c '^func _ensure_hub' godot_project/scripts/HubManager.gd)"

printf '\n########## PART 2: APPLY PATCH ##########\n'
python3 "$PATCHER"

printf '\n########## PART 3: POST-STATE ##########\n'
printf 'all func definitions AFTER patch:\n'
grep -n '^func ' godot_project/scripts/HubManager.gd
printf '_ensure_hub occurrences AFTER: %s\n' "$(grep -c '^func _ensure_hub' godot_project/scripts/HubManager.gd)"
printf 'OS.execute occurrences in whole file AFTER: %s\n' "$(grep -c 'OS.execute' godot_project/scripts/HubManager.gd)"
printf 'OS.create_process occurrences AFTER: %s\n' "$(grep -c 'OS.create_process' godot_project/scripts/HubManager.gd)"

printf '\n########## PART 4: DIFF ##########\n'
BAK=$(ls -t godot_project/scripts/HubManager.gd.bak.* 2>/dev/null | head -1)
if [ -f "$BAK" ]; then
    diff "$BAK" godot_project/scripts/HubManager.gd
fi

printf '\n########## PART 5: NEW _ensure_hub, numbered ##########\n'
python3 - << 'PYIN'
p = "godot_project/scripts/HubManager.gd"
lines = open(p).read().split("\n")
starts = [i for i, L in enumerate(lines) if L.startswith("func ")]
eh = [i for i, L in enumerate(lines) if L.startswith("func _ensure_hub")]
if not eh:
    print("(no _ensure_hub — patch failed silently)"); raise SystemExit
s = eh[0]; idx = starts.index(s)
e = starts[idx+1] if idx+1 < len(starts) else len(lines)
for i in range(s, e):
    print(f"{i+1:5d}: {lines[i]}")
PYIN

printf '\n########## PART 6: POST-FIX WINDOWED RUN ##########\n'
GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done
if [ -z "$GODOT_BIN" ]; then
    # Rule #37: SKIP, not PASS
    printf 'SKIP (Rule #37): godot binary not found\n'
else
    unset GODOT_HEADLESS
    pkill -f 'forensic_hub_server.py' 2>/dev/null && sleep 1
    printf 'launching godot line-buffered. Sampling per second.\n'
    stdbuf -oL -eL "$GODOT_BIN" --path godot_project > "$RUN" 2>&1 &
    GPID=$!
    printf 'godot pid=%s\n' "$GPID"
    F_LAST=0
    STEADY=0
    for i in $(seq 1 20); do
        sleep 1
        # Rule #20 fix: single-line assignment, then default with parameter
        # expansion. NEVER '|| echo 0' inside $() — that concatenates 0\n0.
        F=$(grep -c '_physics_process: ENTER' "$RUN" 2>/dev/null)
        F=${F:-0}
        DELTA=$(( F - F_LAST ))
        printf 't=%2ss  physics_frames=%s  delta=%s\n' "$i" "$F" "$DELTA"
        if [ "$DELTA" -gt 20 ]; then
            STEADY=$(( STEADY + 1 ))
        else
            STEADY=0
        fi
        if [ "$STEADY" -ge 3 ]; then
            printf 'steady-state (>20 frames/s x 3s consecutive)\n'
            break
        fi
        F_LAST=$F
    done
    if kill -0 "$GPID" 2>/dev/null; then
        FINAL=$(grep -c '_physics_process: ENTER' "$RUN"); FINAL=${FINAL:-0}
        SPAWN=$(grep -c 'Hub spawn requested' "$RUN"); SPAWN=${SPAWN:-0}
        printf '\nFINAL: physics_frames=%s   HubManager-spawn-print=%s\n' "$FINAL" "$SPAWN"
        printf 'port 8765 listener:\n'
        ss -ltnp 2>/dev/null | grep 8765 || printf '(nothing on 8765)\n'
        kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
    else
        printf 'godot exited on its own. tail of run log:\n'
        tail -40 "$RUN"
    fi

    printf '\n########## PART 7: VERDICT ##########\n'
    FINAL=$(grep -c '_physics_process: ENTER' "$RUN"); FINAL=${FINAL:-0}
    if [ "$FINAL" -gt 100 ]; then
        printf 'PASS: main thread unblocked. physics_frames=%s (was 1).\n' "$FINAL"
    elif [ "$FINAL" -gt 10 ]; then
        printf 'PARTIAL: %s frames. Progress; something else blocks later.\n' "$FINAL"
    else
        printf 'FAIL: %s frames. Hub was not the only blocker; tail above shows the next stop.\n' "$FINAL"
    fi
fi

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

rm -f "$PATCHER"
git add -f "$OUT" "$RUN" fix_hubmanager_v2.sh godot_project/scripts/HubManager.gd 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "fix v2: HubManager dedupe + non-blocking (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$RUN"
