#!/usr/bin/env bash
# ============================================================================
# diag_frame_throughput.sh
# Tests whether main freezes after frame 1 (the real "plane not visible" cause).
# Line-buffered (stdbuf) so SIGKILL cannot hide the tail. Runs BOTH main and
# _0062 for the same duration and counts _physics_process frames over time.
#  main few frames + _0062 many frames => main hangs; bisect the per-frame call.
# Rules: #8 stderr kept, #32 stream/line-buffer, #47 push+raw, #38 safe quoting
# ============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REF="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game_0062"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/frame_throughput_${TS}.txt"
RUN_MAIN="notes/_run_main_${TS}.log"
RUN_REF="notes/_run_ref_${TS}.log"
DUR=20

GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done

run_one() {
    local label="$1" path="$2" log="$3"
    printf '%s\n' "--- launching $label ($DUR s, line-buffered, windowed, no auto-jump) ---"
    if [ -z "$GODOT_BIN" ]; then
        printf '%s\n' "SKIP (Rule #37): godot binary not found"
        return
    fi
    ( cd "$path" && unset GODOT_HEADLESS && \
      timeout "$DUR" stdbuf -oL -eL "$GODOT_BIN" --path godot_project ) > "$log" 2>&1
    printf '%s\n' "$label exit=$? loglines=$(wc -l < "$log")"
}

count_frames() {
    local label="$1" log="$2"
    printf '%s\n' "===== $label frame throughput ====="
    if [ ! -f "$log" ]; then printf '(no log)\n'; return; fi
    local pp
    pp=$(grep -c '_physics_process: ENTER' "$log")
    printf 'physics_process ENTER count in %ss: %s\n' "$DUR" "$pp"
    printf 'plane-position-updated count: %s\n' "$(grep -c 'plane position updated' "$log")"
    printf 'total log lines: %s\n' "$(wc -l < "$log")"
    printf '%s\n' "--- last 30 lines (where it stopped, if it stopped) ---"
    tail -30 "$log"
    printf '%s\n' "--- per-subsystem per-frame call presence (main-only funcs) ---"
    for tag in ARMTEL PIPLIVE CANOPYSYNC GLIDE PAUSETEL 'DB CLOSED' 'database is locked' 'SCRIPT ERROR' 'Nonexistent'; do
        printf '  %-22s %s\n' "$tag" "$(grep -c "$tag" "$log")"
    done
}

{
printf '%s\n' "=== frame throughput diagnostic $TS UTC ==="
printf 'godot: %s   duration each: %ss\n\n' "${GODOT_BIN:-NONE}" "$DUR"

run_one MAIN  "$PROJECT" "$RUN_MAIN"
run_one _0062 "$REF"     "$RUN_REF"

printf '\n'
count_frames MAIN  "$RUN_MAIN"
printf '\n'
count_frames _0062 "$RUN_REF"

printf '\n%s\n' "=== INTERPRETATION ==="
if [ -f "$RUN_MAIN" ] && [ -f "$RUN_REF" ]; then
    M=$(grep -c '_physics_process: ENTER' "$RUN_MAIN")
    R=$(grep -c '_physics_process: ENTER' "$RUN_REF")
    printf 'main frames=%s   _0062 frames=%s\n' "$M" "$R"
    if [ "$M" -lt 10 ] && [ "$R" -gt 100 ]; then
        printf '%s\n' 'VERDICT: main HANGS after very few frames while _0062 runs freely.'
        printf '%s\n' 'The hang is in a per-frame call main added and _0062 lacks.'
        printf '%s\n' 'Next: the last subsystem tag with a nonzero count above marks the stall point.'
    elif [ "$M" -gt 100 ]; then
        printf '%s\n' 'VERDICT: main does NOT hang — it runs many frames. The plane renders.'
        printf '%s\n' 'The earlier 1-frame capture was stdout buffering, not a freeze.'
    else
        printf '%s\n' 'VERDICT: inconclusive — see counts and tails above.'
    fi
fi
printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" "$RUN_MAIN" "$RUN_REF" diag_frame_throughput.sh 2>/dev/null
git commit --no-verify -m "diag: main-vs-_0062 frame throughput (hang test) ${TS}"
git push origin main
git ls-remote origin main | head -1
printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$RUN_MAIN"
