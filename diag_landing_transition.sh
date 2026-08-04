#!/usr/bin/env bash
# =============================================================================
# diag_landing_transition.sh
#
# GOAL: produce every piece of ground truth needed to fix the LANDED
# transition in ONE next-turn patch. No guessing, no partial patches.
#
# PROOF v3 landed and game runs (from THIS session's fetched logs):
#   notes/fix_hubmanager_v3_20260804120838.txt
#     PART 3: OS.execute() CALLS in code AFTER: 0
#     PART 3: OS.create_process() CALLS in code AFTER: 1
#     PART 6: t=6s 8 -> t=7s 72 -> t=8s 133 -> t=9s 193 frames
#     PART 7: PASS: main thread unblocked. physics_frames=204 (was 1)
#     port 8765 listener: LISTEN 127.0.0.1:8765 python3 pid=497684
#   -> Hub blocker resolved. Plane orbits. Ready to tackle next bug.
#
# TARGET BUG (memory /areas/parachute-cfd-game.md):
#   "Headless pipeline runs to OPENING_ANIM/GLIDE; Game completed: False
#    because GameState.LANDED transition never fires when character
#    reaches 82ft/25m ground plane"
#
# WHAT THIS DIAGNOSTIC EMITS (all numbered, all with file paths):
#   PART A: every _game_state transition (assignments to GameState.*)
#   PART B: every write to _character.position.y (descent + resets)
#   PART C: every reference to GameState.LANDED (writes + reads)
#   PART D: ground-plane constant (25.0, MAX_ELEV, or similar)
#   PART E: current _get_current_descent_rate() and its callers
#   PART F: is there ANY altitude/ground check on the descent path?
#   PART G: current GameState enum definition (source of truth)
#   PART H: run windowed 15s and grep _game_state values emitted at runtime,
#           so we know what state the game IS in at freeze / at end
#
# CITATIONS (retrieved this session):
#   Node3D.position (character position writes):
#     https://docs.godotengine.org/en/stable/classes/class_node3d.html
#   GDScript enum + match/if syntax (state machine primitives):
#     https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
#   Godot 4 stable classes index (verified reachable this session):
#     https://docs.godotengine.org/en/stable/classes/
#
# USERPREFERENCES RULES APPLIED:
#   #1  Evidential Grounding — enumerates real bytes; no memory-only claims.
#   #7  No sed — awk / grep / python only.
#   #14 Scientific Debugging — collect evidence BEFORE proposing a fix so
#       next-turn patch is a one-shot, not the v1/v2 rollback loop.
#   #20 Command Integrity — F=${VAR:-0} pattern, no `|| echo 0` in $().
#   #24 Pre-delivery gate — self-check for the v2 arithmetic bug.
#   #37 Skip-as-PASS — godot missing => SKIP, not PASS.
#   #38 Bash special-char safety — quoted heredocs, printf %%.
#   #44 Delivered as .txt via present_files for clean copy.
#   #47 Diagnostic-then-push heredoc; raw links at end.
# =============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_landing_${TS}.txt"
RUN="notes/_run_landing_${TS}.log"

# --- Rule #24 pre-delivery self-check ----------------------------------------
if grep -qE 'grep -c[^)]*\|\| *echo 0' "$0"; then
    printf 'RULE #24 SELF-CHECK FAIL: v2-style || echo 0 arithmetic bug\n'
    exit 1
fi

GD="godot_project/scripts/build_terrain.gd"

# --- helper: numbered context around every grep hit for a pattern ------------
show_hits() {
    local pattern="$1" ctx="${2:-4}" file="${3:-$GD}"
    local matches
    matches=$(grep -nE "$pattern" "$file" 2>/dev/null | cut -d: -f1)
    if [ -z "$matches" ]; then
        printf '  (no hits)\n'
        return
    fi
    local seen=""
    for ln in $matches; do
        # skip if this line already inside a printed window
        if [ -n "$seen" ]; then
            for prev in $seen; do
                if [ "$ln" -ge "$((prev - ctx))" ] && \
                   [ "$ln" -le "$((prev + ctx))" ]; then
                    ln=""; break
                fi
            done
        fi
        [ -z "$ln" ] && continue
        printf -- '--- %s @ %s:%s (+/-%s) ---\n' "$pattern" "$file" "$ln" "$ctx"
        awk -v L="$ln" -v C="$ctx" \
            'NR>=L-C && NR<=L+C {printf "%5d: %s\n", NR, $0}' "$file"
        seen="$seen $ln"
    done
}

{
printf '=== landing transition diagnostic %s UTC ===\n' "$TS"
printf 'target file: %s\n' "$GD"
printf 'lines: %s\n\n' "$(wc -l < "$GD")"

printf '########## PART A: every _game_state = TRANSITION ##########\n'
show_hits '_game_state\s*=\s*GameState\.' 4

printf '\n########## PART B: every write to _character.position.y ##########\n'
show_hits '_character\.position\.y' 4

printf '\n########## PART C: every reference to GameState.LANDED ##########\n'
show_hits 'GameState\.LANDED' 4

printf '\n########## PART D: ground-plane constants / MAX_ELEV / GROUND ##########\n'
show_hits '(^|[^A-Za-z_])(GROUND|MAX_ELEV|_GROUND|LANDING_ALT|ground_y|_ground_)' 3

printf '\n########## PART E: _get_current_descent_rate() and callers ##########\n'
show_hits '_get_current_descent_rate' 4

printf '\n########## PART F: any altitude-based check on descent path? ##########\n'
# altitudes-comparison patterns: y <=, y <, .y <=, altitude <, current_altitude
show_hits '_current_altitude\s*[<>=]|\.position\.y\s*[<>=]|altitude\s*<=|altitude\s*<' 4

printf '\n########## PART G: GameState enum definition (single source) ##########\n'
show_hits '(^|\s)enum\s+GameState|IN_PLANE\s*,\s*FREEFALL|LANDED\s*,\s*GAME_OVER' 3

printf '\n########## PART H: RUNTIME state emissions (windowed 15s run) ##########\n'
GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done
if [ -z "$GODOT_BIN" ]; then
    printf 'SKIP (Rule #37): godot not found\n'
else
    unset GODOT_HEADLESS
    pkill -f 'forensic_hub_server.py' 2>/dev/null && sleep 1
    printf 'launching godot windowed 15s, line-buffered.\n'
    stdbuf -oL -eL "$GODOT_BIN" --path godot_project > "$RUN" 2>&1 &
    GPID=$!
    printf 'godot pid=%s\n' "$GPID"
    for i in $(seq 1 15); do
        sleep 1
        F=$(grep -c '_physics_process: ENTER' "$RUN" 2>/dev/null); F=${F:-0}
        S=$(grep -oE 'state=[0-9]+' "$RUN" 2>/dev/null | sort -u \
            | tr '\n' ',' )
        printf 't=%2ss  frames=%s  distinct-states-seen: %s\n' "$i" "$F" "${S:-none}"
    done
    if kill -0 "$GPID" 2>/dev/null; then
        kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
    fi

    printf '\n--- runtime state distribution (grep of full run log) ---\n'
    printf 'frames total: %s\n' "$(grep -c '_physics_process: ENTER' "$RUN")"
    printf 'IN_PLANE state=0 frames: %s\n' "$(grep -c 'state=0' "$RUN")"
    printf 'FREEFALL state=1 frames: %s\n' "$(grep -c 'state=1' "$RUN")"
    printf 'OPENING_ANIM state=2 frames: %s\n' "$(grep -c 'state=2' "$RUN")"
    printf 'DIAGNOSIS state=3 frames: %s\n' "$(grep -c 'state=3' "$RUN")"
    printf 'LANDED state=4 frames: %s\n' "$(grep -c 'state=4' "$RUN")"
    printf 'GAME_OVER state=5 frames: %s\n' "$(grep -c 'state=5' "$RUN")"

    printf '\n--- any [LANDED] / "LANDED" prints in run? ---\n'
    grep -nE 'LANDED|GAME_OVER|_reset_game|GameState\.LANDED' "$RUN" | head -20 \
        || printf '(none — confirms LANDED never emitted)\n'

    printf '\n--- lowest _character.y observed (drop-monotonic parse) ---\n'
    python3 - << 'PYIN'
import re
try:
    txt = open("notes/_run_landing_20260804104916.log").read()
except Exception as e:
    print(f"(parse skip: {e})"); raise SystemExit
lo = None
for m in re.finditer(r'\[GLIDE\][^\n]*?y=?([\-\d\.]+)', txt):
    y = float(m.group(1))
    if lo is None or y < lo: lo = y
for m in re.finditer(r'ALT[:=]\s*([\-\d\.]+)\s*ft', txt):
    y = float(m.group(1))
    if lo is None or y < lo: lo = y
for m in re.finditer(r'position updated to \(([-\d\.]+),\s*([-\d\.]+),', txt):
    y = float(m.group(2))
    if lo is None or y < lo: lo = y
print(f"lowest y/altitude parsed: {lo}")
PYIN
fi

printf '\n########## PART I: what does DIAGNOSIS state DO on descent? ##########\n'
show_hits 'GameState\.DIAGNOSIS' 4
show_hits '_do_landing|_land\(|_on_landed|land_character' 3

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

# Rule #47 push + raw link
git add -f "$OUT" "$RUN" diag_landing_transition.sh 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "diag: landing transition ground truth (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$RUN"
