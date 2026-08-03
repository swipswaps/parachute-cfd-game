#!/usr/bin/env bash
# ============================================================================
# liveplay.sh — Launch game for live play, capture all output to a log.
#
# WHAT YOU SHOULD SEE IN THE GAME WINDOW:
#   - Cessna airplane circling at ~6000ft, camera 80m behind it
#   - HUD overlay showing: "EP: Press J or SPACE to exit aircraft"
#   - No auto-jump, no auto-exit
#
# HOW TO PLAY:
#   1. Click the game window to give it keyboard focus
#   2. Press J to exit the aircraft (start freefall)
#   3. Press SPACE at ~4000ft AGL to deploy canopy
#   4. Glide down, press F near ground to flare
#   5. Close window when done — this script then pushes the log
#
# WHY THE TERMINAL GOES QUIET:
#   Godot only prints on game events. While IN_PLANE waiting for J,
#   the background thread produces ~1 line/sec at most. This is normal.
#   Watch the GAME WINDOW, not the terminal.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
GAMELOG="notes/liveplay_${TS}.txt"

# Unset GODOT_HEADLESS so no headless gates fire (Rule #1: grounded check)
unset GODOT_HEADLESS
printf 'GODOT_HEADLESS=[%s] — must be empty\n' "$GODOT_HEADLESS"
printf 'Launching game window. Focus the window and press J to jump.\n'
printf 'Output captured to: %s\n\n' "$GAMELOG"

# Launch — tee captures all output while still showing it in terminal
cd "$PROJECT_ROOT/godot_project" && \
    godot . 2>&1 | tee "$PROJECT_ROOT/$GAMELOG"

# After window closes, push the log
cd "$PROJECT_ROOT"
printf '\n=== Game session ended. Pushing log... ===\n'

# Summarise what happened
printf '\n=== SESSION SUMMARY ===\n'
printf 'Last state before close: '; grep -o 'state=[0-9]' "$GAMELOG" | tail -1 || printf '(none)\n'
printf 'Auto-jump fired?        '; grep -c 'EXIT AIRCRAFT' "$GAMELOG" || printf '0\n'
printf 'Canopy deployed?        '; grep -c 'deployment started' "$GAMELOG" || printf '0\n'
printf 'GLIDE rows:             '; grep -c '\[GLIDE\],' "$GAMELOG" || printf '0\n'
printf 'Plane visible?          '; grep 'Cessna model loaded' "$GAMELOG" | head -1 || printf '(not logged)\n'
printf 'Camera distance loaded: '; grep 'plane camera distance' "$GAMELOG" | head -1 || printf '(not logged)\n'
printf 'Output lines:           '; wc -l < "$GAMELOG"

git add -f "$GAMELOG" liveplay.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "liveplay: session log (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$GAMELOG"
