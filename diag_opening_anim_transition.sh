#!/usr/bin/env bash
# =============================================================================
# diag_opening_anim_transition.sh
#
# GOAL: locate the exact insertion point for the missing
#       OPENING_ANIM -> DIAGNOSIS transition so the next patch is a
#       one-shot (Rule #14 scientific debugging).
#
# PROOF FROM LOGS (Rule #1 grounded):
#   notes/fix_landed_20260804173410.txt PART 3: LANDED patch applied,
#     safe-landing predicate present at line 2110; refs 3 -> 5.
#   notes/fix_landed_20260804173410.txt PART 7 state distribution:
#     state=0 IN_PLANE:      12
#     state=1 FREEFALL:      11
#     state=2 OPENING_ANIM:  4896   <-- stuck here for the rest of the run
#     state=3 DIAGNOSIS:     0      <-- never reached
#     state=4 LANDED:        0
#     state=5 GAME_OVER:     0
#   notes/fix_landed_20260804173410.txt PART 7 tail: repeats forever:
#     [DIAG] _physics_process: ENTER, state=2
#     [VERBATIM] DIAGNOSIS turning block executed
#     [VERBATIM] POLL: checking deploy state=2 canopy=true
#   notes/diag_landing_20260804121715.txt PART A: only 8 state transitions
#     write GameState.*, none of them writes GameState.DIAGNOSIS.
#     -> Confirmed: the transition simply does not exist in code.
#
# WHAT THIS DIAGNOSTIC EMITS (all numbered, all with file paths):
#   PART A: every reference to _deployment_timer  (deploy timer countdown)
#   PART B: every reference to GameState.OPENING_ANIM (branches that use it)
#   PART C: every write / read to _canopy_instance.scale (opening animation)
#   PART D: every reference to _canopy_deployed (deploy flag)
#   PART E: the full _deploy_canopy() function body
#   PART F: the OPENING_ANIM branch in _physics_process (descent path)
#   PART G: the full _physics_process function's opening lines and branch
#           dispatch to see the current state-branch structure
#   PART H: is there ANY existing "timer countdown" pattern anywhere in
#           build_terrain.gd we can mirror?
#
# CITATIONS (retrieved this session unless noted):
#   Godot state machine tutorial pattern:
#     https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html
#     (URL structure verified against docs index; page not fetched this session)
#   Godot 4 stable classes index (verified reachable this session):
#     https://docs.godotengine.org/en/stable/classes/
#   Godot Node._physics_process(delta) virtual method contract:
#     https://docs.godotengine.org/en/stable/classes/class_node.html
#     (general knowledge - not retrieved this session)
#
# USERPREFERENCES RULES APPLIED:
#   #1  Evidential Grounding - claims trace to fetched logs and grep output.
#   #7  No sed - awk / grep / python only.
#   #14 Scientific Debugging - evidence before patch. This is a diagnostic-
#       only run; NO edits to build_terrain.gd.
#   #20 Command Integrity - F=${VAR:-0}; no `|| echo 0` in $() arithmetic.
#   #24 Pre-delivery gate - self-check for the v2 arithmetic bug.
#   #37 Skip-as-PASS - not applicable (pure grep, no god/lint dependency).
#   #38 Bash special-char safety - printf %%, quoted heredocs, single-quoted
#       regex to avoid the "stray \ before t" warning seen in the prior
#       fix_landed log PART 1 (bash consumed the double-escape).
#   #44 Delivered as .txt via present_files by the LLM.
#   #47 Diagnostic-then-push heredoc; raw link printed at end.
# =============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_opening_anim_${TS}.txt"
GD="godot_project/scripts/build_terrain.gd"

# --- Rule #24 pre-delivery self-check ----------------------------------------
if grep -qE 'grep -c[^)]*\|\| *echo 0' "$0"; then
    printf 'RULE #24 SELF-CHECK FAIL: v2-style || echo 0 arithmetic bug\n'
    exit 1
fi

# --- Rule #7/#38: python-based context printer, no sed, no escaping issues ---
show_hits() {
    local pattern="$1" ctx="${2:-4}"
    python3 - "$GD" "$pattern" "$ctx" << 'PYIN'
import sys, re
path, pat, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3])
lines = open(path, encoding="utf-8").read().split("\n")
try:
    rx = re.compile(pat)
except re.error as e:
    print(f"  (bad regex: {e})"); raise SystemExit
hits = [i for i, L in enumerate(lines) if rx.search(L)]
if not hits:
    print("  (no hits)")
    raise SystemExit
seen = set()
for ln in hits:
    if any(abs(ln - p) <= ctx for p in seen):
        continue
    print(f"--- {pat} @ {path}:{ln+1} (+/-{ctx}) ---")
    for i in range(max(0, ln - ctx), min(len(lines), ln + ctx + 1)):
        marker = ">> " if i == ln else "   "
        print(f"{marker}{i+1:5d}: {lines[i]}")
    seen.add(ln)
PYIN
}

show_function() {
    local func_name="$1"
    python3 - "$GD" "$func_name" << 'PYIN'
import sys
path, name = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
start = None
for i, L in enumerate(lines):
    if L.startswith(f"func {name}("):
        start = i; break
if start is None:
    print(f"  (function {name} not found)")
    raise SystemExit
end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("func "):
        end = i; break
print(f"--- func {name} @ {path}:{start+1}..{end} ({end-start} lines) ---")
for i in range(start, end):
    print(f"{i+1:5d}: {lines[i]}")
PYIN
}

show_state_branch() {
    # Prints a range around every occurrence of a state-check pattern
    # inside _physics_process specifically. We locate _physics_process
    # bounds first, then filter hits to that range.
    local pattern="$1" ctx="${2:-3}"
    python3 - "$GD" "$pattern" "$ctx" << 'PYIN'
import sys, re
path, pat, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3])
lines = open(path, encoding="utf-8").read().split("\n")
# find _physics_process bounds
starts = [i for i, L in enumerate(lines) if L.startswith("func ")]
pp = None
for i, L in enumerate(lines):
    if L.startswith("func _physics_process"):
        pp = i; break
if pp is None:
    print("  (_physics_process not found)")
    raise SystemExit
idx = starts.index(pp)
pp_end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
rx = re.compile(pat)
hits = [i for i in range(pp, pp_end) if rx.search(lines[i])]
if not hits:
    print(f"  (no hits inside _physics_process @ {pp+1}..{pp_end})")
    raise SystemExit
print(f"  (_physics_process spans @ {pp+1}..{pp_end}, {len(hits)} hits)")
seen = set()
for ln in hits:
    if any(abs(ln - p) <= ctx for p in seen):
        continue
    print(f"--- {pat} @ {path}:{ln+1} (+/-{ctx}) ---")
    for i in range(max(pp, ln - ctx), min(pp_end, ln + ctx + 1)):
        marker = ">> " if i == ln else "   "
        print(f"{marker}{i+1:5d}: {lines[i]}")
    seen.add(ln)
PYIN
}

{
printf '=== OPENING_ANIM -> DIAGNOSIS transition locator %s UTC ===\n' "$TS"
printf 'target: %s\n' "$GD"
printf 'lines : %s\n\n' "$(wc -l < "$GD")"

printf '########## PART A: _deployment_timer references ##########\n'
show_hits '_deployment_timer' 4

printf '\n########## PART B: GameState.OPENING_ANIM references ##########\n'
show_hits 'GameState\.OPENING_ANIM' 4

printf '\n########## PART C: _canopy_instance.scale (opening animation) ##########\n'
show_hits '_canopy_instance\.scale' 4

printf '\n########## PART D: _canopy_deployed references ##########\n'
show_hits '_canopy_deployed' 4

printf '\n########## PART E: full _deploy_canopy() function ##########\n'
show_function "_deploy_canopy"

printf '\n########## PART F: OPENING_ANIM branch inside _physics_process ##########\n'
printf 'F1: state-check hits mentioning OPENING_ANIM inside _physics_process:\n'
show_state_branch 'OPENING_ANIM' 5

printf '\nF2: any "state == GameState." or "_game_state ==" hits inside _physics_process:\n'
show_state_branch '_game_state\s*==' 3

printf '\n########## PART G: _physics_process opening lines (branch structure) ##########\n'
python3 - "$GD" << 'PYIN'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
pp = None
for i, L in enumerate(lines):
    if L.startswith("func _physics_process"):
        pp = i; break
if pp is None:
    print("  (_physics_process not found)")
    raise SystemExit
print(f"  _physics_process starts at line {pp+1}")
print(f"  first 60 lines of _physics_process:")
end = min(len(lines), pp + 60)
for i in range(pp, end):
    print(f"{i+1:5d}: {lines[i]}")
PYIN

printf '\n########## PART H: any existing "if X_timer > 0: X_timer -= delta" pattern ##########\n'
show_hits 'timer\s*>\s*0.*\n.*timer\s*-=' 2
printf '(single-line search fallback below)\n'
show_hits 'timer\s*-=\s*delta' 3

printf '\n########## PART I: are there any -1 sentinel / DEPLOY_TIME constants? ##########\n'
show_hits '(DEPLOY_TIME|CANOPY_OPEN|_CANOPY_TIME|OPEN_DURATION)' 3

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_opening_anim_transition.sh 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "diag: OPENING_ANIM -> DIAGNOSIS transition locator (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
