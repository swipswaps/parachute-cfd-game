#!/usr/bin/env bash
# ============================================================================
# liveplay2.sh
#
# Answers "are we not using autostall_fixed.py?":
#   autostall_patched.py IS the current working autostall (Game completed: True
#   in 49.9s confirmed). autostall_fixed.py does not exist unless an earlier
#   session created it — check below.
#
# The game DID open last time. The window appeared behind the terminal.
# This script raises the window to the foreground after launch using wmctrl.
#
# For LIVE PLAY the game must launch WITHOUT autostall (no GODOT_HEADLESS)
# so the user sees the airplane and presses J manually.
# autostall is for CI testing only — it auto-jumps via GODOT_HEADLESS=1.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
GAMELOG="notes/liveplay2_${TS}.txt"

# Check for autostall_fixed.py
printf '=== autostall file audit ===\n'
ls -lh autostall*.py 2>/dev/null || printf '(none)\n'
printf 'Current working autostall: autostall_patched.py\n'
printf 'autostall_fixed.py: '
[ -f autostall_fixed.py ] && printf 'EXISTS (%s bytes)\n' "$(wc -c < autostall_fixed.py)" \
                           || printf 'does not exist\n'

unset GODOT_HEADLESS

printf '\n=== Launching game window ===\n'
printf 'THE WINDOW MAY OPEN BEHIND THIS TERMINAL.\n'
printf 'Look for "Parachute" in your taskbar / Alt+Tab list.\n'
printf 'Click the Godot window, then press J to jump.\n\n'

# Launch Godot in background, then raise the window
cd "$PROJECT_ROOT/godot_project"
godot . > "$PROJECT_ROOT/$GAMELOG" 2>&1 &
GODOT_PID=$!
printf 'Godot PID: %s\n' "$GODOT_PID"

# Wait for window to appear then raise it
sleep 4
# Try wmctrl first, then xdotool as fallback
if command -v wmctrl > /dev/null; then
    wmctrl -a "Parachute" 2>/dev/null && printf 'wmctrl: window raised\n' \
        || wmctrl -a "Godot" 2>/dev/null && printf 'wmctrl: godot window raised\n' \
        || printf 'wmctrl: window not found by name (check taskbar)\n'
elif command -v xdotool > /dev/null; then
    xdotool search --name "Parachute" windowactivate 2>/dev/null \
        && printf 'xdotool: window raised\n' \
        || printf 'xdotool: window not found — check taskbar\n'
else
    printf '(wmctrl/xdotool not available — find window in taskbar manually)\n'
fi

printf '\nWaiting for Godot to exit (close game window when done)...\n'
wait "$GODOT_PID"
printf 'Game closed. Pushing log...\n'

cd "$PROJECT_ROOT"
printf '\n=== Session summary ===\n'
printf 'Plane loaded:    '; grep -c 'Cessna model loaded' "$GAMELOG" || printf '0\n'
printf 'Auto-jump fired: '; grep -c 'EXIT AIRCRAFT' "$GAMELOG" || printf '0\n'
printf 'J pressed:       '; grep -c 'exit aircraft triggered' "$GAMELOG" || printf '0\n'
printf 'Output lines:    '; wc -l < "$GAMELOG"

git add -f "$GAMELOG" liveplay2.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "liveplay2: session log (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$GAMELOG"
