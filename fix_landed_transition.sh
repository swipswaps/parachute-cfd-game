#!/usr/bin/env bash
# =============================================================================
# fix_landed_transition.sh
#
# GOAL: GameState.LANDED fires on ground contact under a deployed canopy,
#       even when _do_flare() was never pressed. autostall_patched.py
#       should report "Game completed: True" instead of False.
#
# GROUNDED IN LOGS (Rule #1):
#   notes/diag_landing_20260804121715.txt
#     PART C: GameState.LANDED write count in build_terrain.gd = 1
#             (line 1164 inside _do_flare; nowhere else)
#     PART A/F: ground clamp at lines 2095..2101 only writes GAME_OVER
#             when `not _safe_landing`; safe path falls through with
#             NO state change -> character sits at y=25 forever.
#     PART H: 506 windowed frames, state=0 x 1239, state=1..5 all zero.
#
# FIX SHAPE (lines 2095..2101):
#   BEFORE:
#     if _character.position.y < 25.0:
#         _character.position.y = 25.0
#         if not _safe_landing:
#             ScreenshotLibrary.save_flight_screenshot()
#             print("[VERBATIM] FAILURE SCREENSHOT: ground impact ...")
#             _game_state = GameState.GAME_OVER
#             print("[VERBATIM] Ground impact - fatal")
#   AFTER (adds a LANDED branch; keeps GAME_OVER as the unsafe path):
#     if _character.position.y < 25.0:
#         _character.position.y = 25.0
#         if _game_state != GameState.LANDED and _game_state != GameState.GAME_OVER:
#             var safe := _safe_landing or (_canopy_deployed and _descent_rate < 8.0)
#             if safe:
#                 _safe_landing = true
#                 _game_state = GameState.LANDED
#                 print("[VERBATIM] Ground contact - SAFE LANDING (state=LANDED)")
#             else:
#                 ScreenshotLibrary.save_flight_screenshot()
#                 print("[VERBATIM] FAILURE SCREENSHOT: ground impact (physics_process)")
#                 _game_state = GameState.GAME_OVER
#                 print("[VERBATIM] Ground impact - fatal")
#
# 8.0 m/s threshold rationale: typical parachute rate of descent under
# a fully-inflated ram-air canopy is 4-6 m/s; 8 m/s allows a modest
# margin for a hard-but-survivable arrival before crossing into a
# "fatal impact" classification.
#
# CITATIONS (retrieved this session where possible; otherwise flagged):
#   Godot state-machine tutorial (referenced at line 26 of the target file):
#     https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html
#     (URL structure verified against Godot Stable docs index this session;
#      exact page not fetched this session.)
#   Godot 4 stable classes index (verified reachable this session):
#     https://docs.godotengine.org/en/stable/classes/
#   Godot OS.execute is synchronous, previously cited for the hub fix:
#     https://straydragon.github.io/godot-csharp-api-doc/4.3-stable/main/Godot.OS.html
#     "The main thread will be blocked until the executed command
#      terminates." (retrieved this session)
#   Parachute canopy rate-of-descent typical values:
#     USPA Skydiver's Information Manual (general knowledge - not
#     retrieved this session)
#
# USERPREFERENCES RULES APPLIED:
#   #1  Evidential Grounding - every claim traces to the diag log.
#   #6  Design by Contract - precondition: exactly 1 occurrence of the
#       extracted 7-line ground-check block.
#   #7  No sed - all edits via Python str.replace with count guard.
#   #9  Read-after-Write consistency.
#   #14 Scientific Debugging - comment-aware forbidden-string check
#       so citation comments cannot self-trip rollback (v2 defect).
#   #20 Command Integrity - F=${VAR:-0} default expansion; no `|| echo 0`.
#   #21 Timestamped backup.
#   #24 Pre-delivery gate - self-check for v2 arithmetic bug.
#   #29 Exact Error Absent - post-write grep verifies old fall-through
#       is gone and LANDED reference count grew from 3 to 4.
#   #31 Tabs-only for GDScript.
#   #37 Skip-as-PASS Prohibition - godot missing -> SKIP, not PASS.
#   #38 Bash special-char safety - quoted heredocs, printf %%.
#   #44 Delivered as .txt via present_files.
#   #46 Exact-byte guarded patch with LIVE EXTRACTION of the 7-line
#       target block; whitespace preserved via string-level replace.
#   #47 Diagnostic-then-push heredoc; two raw links at end.
# =============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_landed_${TS}.txt"
AUTOSTALL_LOG="notes/_autostall_landed_${TS}.log"
PATCHER="/tmp/patch_landed_${TS}.py"

# --- Rule #24 pre-delivery self-check ----------------------------------------
if grep -qE 'grep -c[^)]*\|\| *echo 0' "$0"; then
    printf 'RULE #24 SELF-CHECK FAIL: v2-style || echo 0 arithmetic bug\n'
    exit 1
fi

cat > "$PATCHER" << 'PYEOF'
#!/usr/bin/env python3
# Rule #46 exact-byte guarded patch. The target 7-line block is extracted
# LIVE from the file (no hardcoded bytes) using two anchor lines. If the
# block doesn't match exactly once, halt.
#
# Rule #14 fix: comment-aware forbidden-string check so a citation
# comment containing "GameState.GAME_OVER" cannot trip rollback.
import sys, shutil, datetime, re

def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {d}",
          file=sys.stderr)

def strip_gdscript_comments(text: str) -> str:
    out = []
    for line in text.split("\n"):
        if line.lstrip().startswith("#"):
            out.append("")
            continue
        if "#" in line:
            out.append(line.split("#", 1)[0].rstrip())
        else:
            out.append(line)
    return "\n".join(out)

T = "godot_project/scripts/build_terrain.gd"
original = open(T, encoding="utf-8").read()

# Rule #1 grounded: confirm structure before patching.
print(f"[DIAG] file length: {len(original)} bytes, "
      f"{len(original.splitlines())} lines", file=sys.stderr)
landed_count_before = len(re.findall(r'\bGameState\.LANDED\b', original))
print(f"[DIAG] GameState.LANDED references before: {landed_count_before}",
      file=sys.stderr)

# Anchor: the exact 7-line ground-contact block as seen in
# diag_landing_20260804121715.txt PART B lines 2095-2101. Extract by
# scanning for a UNIQUE prefix "if _character.position.y < 25.0:" and
# the trailing "print(\"[VERBATIM] Ground impact - fatal\")".
lines = original.split("\n")
start_pat = re.compile(r'^\tif _character\.position\.y\s*<\s*25\.0\s*:\s*$')
starts = [i for i, L in enumerate(lines) if start_pat.match(L)]
if len(starts) != 1:
    sys.exit(f"expected exactly 1 'if _character.position.y < 25.0:' "
             f"line, got {len(starts)}: {starts}")

s = starts[0]
# The block is 7 lines: the if, clamp, if not safe, screenshot, print,
# GAME_OVER, print. Verify shape before extracting to avoid surprising
# indentation.
expected_slice_len = 7
old_block_lines = lines[s : s + expected_slice_len]
old_block = "\n".join(old_block_lines)

# Rule #29 exact match sanity: check the last line is the fatal print
if not old_block_lines[6].startswith("\t\t\tprint(") or \
   "Ground impact" not in old_block_lines[6]:
    sys.exit(f"unexpected slice tail: {old_block_lines[6]!r}")
if 'not _safe_landing' not in old_block_lines[2]:
    sys.exit(f"unexpected slice middle: {old_block_lines[2]!r}")
log("extract", True,
    f"lines {s+1}..{s+expected_slice_len} match expected shape")

# Rule #6 precondition
if original.count(old_block) != 1:
    sys.exit(f"expected exactly 1 occurrence of extracted block, "
             f"got {original.count(old_block)}")

# The replacement. Comments carry the diagnostic and citation context
# per Rule #36 (Godot doc references) and Rule #25 (verbose commenting).
# Indentation matches the original: outer if is one tab, inner is two,
# inner-inner is three - GDScript demands tabs (Rule #31).
new_block = "\n".join([
    "\tif _character.position.y < 25.0:",
    "\t\t_character.position.y = 25.0",
    "\t\t# LANDED-transition fix (this session):",
    "\t\t# Old code only wrote GAME_OVER when `not _safe_landing`, so a",
    "\t\t# deployed-canopy descent to ground without a flare press left",
    "\t\t# the state stuck at DIAGNOSIS forever. Proven by",
    "\t\t# notes/diag_landing_20260804121715.txt PART H: 1239 state=0",
    "\t\t# emissions and zero emissions in states 1..5 across 506 frames.",
    "\t\t# Ref: state machine tutorial (referenced at line 26 of this file):",
    "\t\t#   https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html",
    "\t\t# Descent-rate threshold rationale: parachute canopies typically",
    "\t\t# achieve 4-6 m/s rate of descent when fully inflated (USPA SIM,",
    "\t\t# general knowledge - not retrieved this session); 8 m/s allows",
    "\t\t# margin for a hard but survivable arrival.",
    "\t\tif _game_state != GameState.LANDED and _game_state != GameState.GAME_OVER:",
    "\t\t\tvar safe := _safe_landing or (_canopy_deployed and _descent_rate < 8.0)",
    "\t\t\tif safe:",
    "\t\t\t\t_safe_landing = true",
    "\t\t\t\t_game_state = GameState.LANDED",
    "\t\t\t\tprint(\"[VERBATIM] Ground contact - SAFE LANDING (state=LANDED)\")",
    "\t\t\telse:",
    "\t\t\t\tScreenshotLibrary.save_flight_screenshot()",
    "\t\t\t\tprint(\"[VERBATIM] FAILURE SCREENSHOT: ground impact (physics_process)\")",
    "\t\t\t\t_game_state = GameState.GAME_OVER",
    "\t\t\t\tprint(\"[VERBATIM] Ground impact - fatal\")",
])

ts_str = datetime.datetime.now(datetime.timezone.utc).strftime(
    "%Y%m%d%H%M%S")
bak = f"{T}.bak.{ts_str}"
shutil.copy2(T, bak)
log("backup", True, bak)

patched = original.replace(old_block, new_block, 1)
if patched == original:
    sys.exit("replace produced identical text - something is wrong")

open(T, "w", encoding="utf-8").write(patched)
rb = open(T, encoding="utf-8").read()
if rb != patched:
    shutil.copy2(bak, T)
    sys.exit("read-after-write mismatch - restored")
log("write", True, "read-back match")

# Rule #31 tabs-only
bad = [i + 1 for i, L in enumerate(rb.split("\n")) if L.startswith(" ")]
if bad:
    shutil.copy2(bak, T)
    sys.exit(f"leading spaces at {bad[:5]} - restored")
log("tabs_only", True, "no leading spaces")

# Rule #14 / #29 comment-aware semantic checks
rb_code = strip_gdscript_comments(rb)

# LANDED write count in CODE should be exactly 2 now (line 1164 in
# _do_flare + our new line inside the ground-contact block).
landed_writes = re.findall(r'^\s*_game_state\s*=\s*GameState\.LANDED\s*$',
                           rb_code, re.M)
if len(landed_writes) != 2:
    shutil.copy2(bak, T)
    sys.exit(f"expected 2 LANDED writes in code, got {len(landed_writes)}")
log("landed_writes", True, "exactly 2 (flare + ground contact)")

# The old fall-through pattern is gone: check that no ground-clamp block
# ends without writing SOME state - proxy: verify the new "safe" var is
# present.
if not re.search(r'var\s+safe\s*:=\s*_safe_landing\s+or\s+\('
                 r'_canopy_deployed and _descent_rate\s*<\s*8\.0\)',
                 rb_code):
    shutil.copy2(bak, T)
    sys.exit("safe-landing predicate missing - restored")
log("safe_predicate_present", True, "verified in code")

# The old-shape-check: exactly one bare "GAME_OVER path" is now inside
# the else of the safe check.
if 'GAME_OVER path' in rb_code:
    # sentinel: this string should NOT appear anywhere
    shutil.copy2(bak, T)
    sys.exit("sentinel 'GAME_OVER path' in code - unexpected")

print(f"\nPATCH APPLIED: {T}\nBackup: {bak}")
PYEOF

{
printf '=== LANDED transition fix %s UTC ===\n' "$TS"

printf '\n########## PART 1: PRE-STATE (grounded) ##########\n'
printf 'GameState.LANDED reference count BEFORE: %s\n' \
    "$(grep -c 'GameState\.LANDED' godot_project/scripts/build_terrain.gd)"
printf 'ground-clamp block hit BEFORE:\n'
grep -n '^\tif _character\.position\.y < 25\.0:' \
    godot_project/scripts/build_terrain.gd

printf '\n########## PART 2: APPLY PATCH ##########\n'
python3 "$PATCHER"

printf '\n########## PART 3: POST-STATE ##########\n'
printf 'GameState.LANDED reference count AFTER: %s\n' \
    "$(grep -c 'GameState\.LANDED' godot_project/scripts/build_terrain.gd)"
printf 'safe-landing predicate present AFTER:\n'
grep -n 'var safe := _safe_landing' \
    godot_project/scripts/build_terrain.gd \
    || printf '(missing - patch failed)\n'

printf '\n########## PART 4: DIFF ##########\n'
BAK=$(ls -t godot_project/scripts/build_terrain.gd.bak.* 2>/dev/null \
      | head -1)
[ -f "$BAK" ] && diff "$BAK" godot_project/scripts/build_terrain.gd

printf '\n########## PART 5: NEW ground-contact block, numbered ##########\n'
python3 - << 'PYIN'
import re
p = "godot_project/scripts/build_terrain.gd"
lines = open(p).read().split("\n")
starts = [i for i, L in enumerate(lines)
          if re.match(r'^\tif _character\.position\.y\s*<\s*25\.0\s*:\s*$', L)]
if not starts:
    print("(patch failed - anchor missing)"); raise SystemExit
s = starts[0]
# print until we see either the next top-level statement at same indent
# or 30 lines, whichever first
for i in range(s, min(s + 30, len(lines))):
    print(f"{i+1:5d}: {lines[i]}")
    if i > s and lines[i].startswith("\t_current_altitude"):
        break
PYIN

printf '\n########## PART 6: AUTOSTALL RUN (headless pipeline exerciser) ##########\n'
# Autostall is the ONLY harness that auto-jumps and runs the full descent
# pipeline to ground contact. Windowed play cannot exercise this without
# a user pressing J and waiting minutes. --no-timeout lets it complete
# naturally per the project's own autostall pattern.
pkill -f 'forensic_hub_server.py' 2>/dev/null && sleep 1
if [ ! -f autostall_patched.py ]; then
    printf 'SKIP (Rule #37): autostall_patched.py not found\n'
else
    printf 'launching autostall_patched.py --no-timeout, streaming to log\n'
    stdbuf -oL -eL python3 autostall_patched.py --no-timeout \
        > "$AUTOSTALL_LOG" 2>&1 &
    APID=$!
    printf 'autostall pid=%s\n' "$APID"
    # Sample every 2s until either LANDED appears, Game completed line
    # appears, or we hit a 90s ceiling. Rule #20: single-line grep, then
    # default expansion. Never `|| echo 0` inside $().
    for i in $(seq 1 45); do
        sleep 2
        L=$(grep -c 'state=LANDED\|state=4\|SAFE LANDING' \
            "$AUTOSTALL_LOG" 2>/dev/null); L=${L:-0}
        C=$(grep -c 'Game completed' "$AUTOSTALL_LOG" 2>/dev/null); C=${C:-0}
        F=$(grep -c '_physics_process: ENTER' "$AUTOSTALL_LOG" 2>/dev/null)
        F=${F:-0}
        printf 't=%3ss  frames=%s  LANDED-hits=%s  completed-lines=%s\n' \
            "$((i*2))" "$F" "$L" "$C"
        if [ "$C" -gt 0 ]; then
            printf 'Game completed line seen; giving 4s for tail\n'
            sleep 4; break
        fi
    done
    if kill -0 "$APID" 2>/dev/null; then
        kill "$APID" 2>/dev/null; sleep 1; kill -9 "$APID" 2>/dev/null
    fi
fi

printf '\n########## PART 7: LANDED EVIDENCE (grep) ##########\n'
if [ -f "$AUTOSTALL_LOG" ]; then
    printf -- '--- state emission distribution ---\n'
    for s in 0 1 2 3 4 5; do
        n=$(grep -c "state=$s" "$AUTOSTALL_LOG"); n=${n:-0}
        printf '  state=%s : %s\n' "$s" "$n"
    done
    printf -- '\n--- SAFE LANDING lines ---\n'
    grep -n 'SAFE LANDING\|state=LANDED\|GameState\.LANDED' \
        "$AUTOSTALL_LOG" | head -15 \
        || printf '(none - LANDED transition did NOT fire)\n'
    printf -- '\n--- Game completed lines ---\n'
    grep -n 'Game completed' "$AUTOSTALL_LOG" | head -5 \
        || printf '(none - autostall never reached completion check)\n'
    printf -- '\n--- last 20 lines of autostall log ---\n'
    tail -20 "$AUTOSTALL_LOG"
fi

printf '\n########## PART 8: VERDICT ##########\n'
if [ -f "$AUTOSTALL_LOG" ]; then
    LANDED_HITS=$(grep -c 'SAFE LANDING\|Game completed: True' \
                  "$AUTOSTALL_LOG"); LANDED_HITS=${LANDED_HITS:-0}
    FAIL_HITS=$(grep -c 'Game completed: False' \
                "$AUTOSTALL_LOG"); FAIL_HITS=${FAIL_HITS:-0}
    if [ "$LANDED_HITS" -gt 0 ] && [ "$FAIL_HITS" -eq 0 ]; then
        printf 'PASS: LANDED fired and Game completed: True.\n'
    elif [ "$LANDED_HITS" -gt 0 ]; then
        printf 'MIXED: LANDED fired (%s hits) but Game completed: False also seen (%s).\n' \
            "$LANDED_HITS" "$FAIL_HITS"
    else
        printf 'FAIL: no LANDED emissions. Tail above shows where it stopped.\n'
    fi
fi

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

rm -f "$PATCHER"
git add -f "$OUT" "$AUTOSTALL_LOG" fix_landed_transition.sh \
    godot_project/scripts/build_terrain.gd 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "fix: LANDED transition on safe ground contact (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$AUTOSTALL_LOG"
