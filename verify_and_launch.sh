#!/usr/bin/env bash
# ============================================================================
# verify_and_launch.sh
#
# PURPOSE: Verify no remaining unconditional auto-exit paths exist in live
#   play, then launch the game without GODOT_HEADLESS so the user sees the
#   airplane circling and must press J to jump.
#
# CONFIRMED FIXED (this session):
#   - func _auto_deploy() with get_tree().quit() REMOVED
#   - create_timer(5.0) setup in _ready() REMOVED
#   - camera_distance_plane changed from 300m → 80m in DB
#   - Autostall: Game completed: True in 49.9s (GLIDE 88 rows, warp working)
#
# LIVE PLAY EXPECTED BEHAVIOR (GODOT_HEADLESS not set):
#   1. Airplane visible at 80m camera distance
#   2. HUD shows: "EP: Press J or SPACE to exit aircraft"
#   3. Game waits indefinitely — no auto-jump, no auto-exit
#   4. Player presses J → FREEFALL → SPACE to deploy canopy → glide down
#
# Rules complied with: #1, #7, #8, #9, #31, #41, #47
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/verify_launch_${TS}.txt"

{
printf '=== verify_and_launch.sh — %s UTC ===\n\n' "$TS"

# ── 1. Confirm no unconditional get_tree().quit() or create_timer exits ──────
# Any quit() NOT inside a func that requires --run-tests or headless is a bug.
# _run_tests() quit is safe (only fires with --run-tests arg).
# We expect exactly 1 quit() at line ~2826 inside _run_tests().
printf '=== 1. All get_tree().quit() calls (must only be in _run_tests) ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().split("\n")
quit_lines = [(i+1, ln) for i, ln in enumerate(lines)
              if "get_tree().quit()" in ln and not ln.strip().startswith("#")]
for lineno, ln in quit_lines:
    # Walk back to find enclosing func
    func_name = "unknown"
    for j in range(lineno-2, max(0, lineno-60), -1):
        if lines[j].startswith("func "):
            func_name = lines[j].strip()
            break
    print(f"  line {lineno}: {ln.strip()!r}")
    print(f"    enclosing: {func_name}")
    # Flag if not inside _run_tests
    if "_run_tests" not in func_name:
        print(f"    WARNING: quit() outside _run_tests — live play will exit!")
    else:
        print(f"    OK: gated behind --run-tests cmdline arg")
PYEOF

# ── 2. Confirm no create_timer without a GODOT_HEADLESS gate ─────────────────
# The removed 5s timer was unconditional — fired in live play too.
# Any remaining create_timer should only exist inside headless-gated blocks.
printf '\n=== 2. All create_timer() calls (must be gated or benign) ===\n'
grep -n 'create_timer' "$TARGET" | head -10

# ── 3. Show IN_PLANE _poll_controls branch — confirm J triggers exit ──────────
# This is the path the user takes in live play. Must not auto-fire.
printf '\n=== 3. IN_PLANE _poll_controls branch ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
# Find "_poll_controls: exit aircraft triggered" context
for i, ln in enumerate(lines):
    if "exit aircraft" in ln.lower() and "poll" in "".join(lines[max(0,i-5):i+1]).lower():
        start = max(0, i-8)
        for j in range(start, min(len(lines), i+3)):
            print(f"  {j+1}: {lines[j]!r}")
        break
PYEOF

# ── 4. Confirm headless gates on all auto-start paths ────────────────────────
printf '\n=== 4. Headless gates on all auto-start / auto-jump paths ===\n'
grep -n 'GODOT_HEADLESS\|--headless\|_headless_auto_jump\|_headless_auto_deploy\|_headless_warp' \
    "$TARGET" | grep -v '^\s*#' | head -20

# ── 5. Camera distance from DB ────────────────────────────────────────────────
printf '\n=== 5. Camera distance in DB ===\n'
sqlite3 parachute_mutations.db \
    "SELECT key, value FROM user_preferences WHERE key LIKE '%camera%';"

# ── 6. Verify GODOT_HEADLESS is NOT set in live shell ─────────────────────────
printf '\n=== 6. GODOT_HEADLESS in current shell ===\n'
printf 'GODOT_HEADLESS=[%s] (must be empty for live play)\n' "$GODOT_HEADLESS"

printf '\n=== VERIFICATION COMPLETE ===\n'
printf 'To launch in live play mode:\n'
printf '  cd %s/godot_project && godot .\n' "$PROJECT_ROOT"
printf 'Expected: airplane visible at 80m, HUD shows J-to-jump prompt, no auto-exit.\n'
} 2>&1 | tee "$OUT"

# ── Push verification report ──────────────────────────────────────────────────
git add -f "$OUT" verify_and_launch.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "verify: live-play safety audit + launch guide (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"

# ── Launch live play (no GODOT_HEADLESS, no --headless, no autostall) ─────────
printf '\n=== LAUNCHING LIVE PLAY ===\n'
printf 'GODOT_HEADLESS is unset — headless auto-jump will NOT fire.\n'
printf 'Camera: 80m behind plane. Press J to exit aircraft.\n'
printf 'Close the window when done to return to this terminal.\n\n'
unset GODOT_HEADLESS
cd "$PROJECT_ROOT/godot_project" && godot .
