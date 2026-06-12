#!/usr/bin/env bash
# PATH: parachute-cfd-game/run_game_debug.sh
#
# WHAT: launch Godot with live terminal output AND automatic window focus
#       so keyboard input reaches the game immediately without manual clicking
#
# WHY:  run_game.sh | tee | grep kept terminal focused — Godot window opened
#       behind it and never received keyboard events. Backgrounding hid output.
#       This script: (1) launches Godot with stdout/stderr live in terminal,
#       (2) waits for the window to appear, (3) uses xdotool to focus it,
#       (4) keeps all [VERBATIM] output streaming in the same terminal.
#
# ASSUMES: xdotool installed (confirmed: used in prior test framework sessions)
#          Godot 4 binary at path defined in run_game.sh or GODOT_BIN env var
#          DISPLAY is set (X11 session active)
#
# VERIFIES WITH: after launch, terminal shows [VERBATIM] lines live;
#                pressing SPACE immediately shows "deploy pressed" without
#                needing to click the window first
#
# FAILURE MODE: xdotool not found → install prompt shown, game still launches
#               (user must click window manually as fallback)
#               Godot window title differs → xdotool focus fails silently,
#               fallback message printed
#
# MENTAL MODEL BEFORE: terminal holds focus, Godot window is unfocused,
#                      all keypresses go to terminal, game sees nothing
# MENTAL MODEL AFTER:  Godot window is focused via xdotool, keypresses go
#                      to game, [VERBATIM] lines stream in terminal behind it
#
# CITATION (Tier 2 — xdotool window focus):
#   xdotool man page, windowfocus command:
#   https://manpages.ubuntu.com/manpages/focal/man1/xdotool.1.html
# CITATION (Tier 2 — Godot 4 command line arguments):
#   https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
# CITATION (Tier 2 — bash set -uo pipefail):
#   bash(1) man page: https://man7.org/linux/man-pages/man1/bash.1.html

set -uo pipefail

# ── LOCATE GODOT BINARY ──────────────────────────────────────────────────────
# WHY: different installs put Godot at different paths; check in priority order
# ASSUMES: one of these paths exists or GODOT_BIN env var is set
# VERIFIES WITH: GODOT variable is set to a valid executable path
# FAILURE MODE: none found → error message with install hint, exit 1
# CITATION (Tier 2 — Godot 4 Linux installation paths):
#   https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
find_godot() {
    # WHY: check env var first so user can override without editing script
    # ASSUMES: GODOT_BIN is set to a valid path if provided
    # VERIFIES WITH: command -v or test -x succeeds
    # MENTAL MODEL BEFORE: GODOT_BIN may or may not be set
    # MENTAL MODEL AFTER:  GODOT set to first valid path found
    # FAILURE MODE: none found → returns 1
    if [[ -n "${GODOT_BIN:-}" ]] && command -v "$GODOT_BIN" &>/dev/null; then
        echo "$GODOT_BIN"; return 0
    fi
    local candidates=(
        "godot4"
        "godot"
        "/usr/local/bin/godot4"
        "/usr/bin/godot4"
        "$HOME/.local/bin/godot4"
        # Flatpak
        "flatpak run org.godotengine.Godot"
    )
    for c in "${candidates[@]}"; do
        if command -v "$c" &>/dev/null 2>&1 || [[ -x "$c" ]]; then
            echo "$c"; return 0
        fi
    done
    # Check run_game.sh for the binary path used there
    local rgs="${BASH_SOURCE[0]%/*}/run_game.sh"
    if [[ -f "$rgs" ]]; then
        local extracted
        extracted=$(grep -oE '(godot[^ ]*|/[^ ]*godot[^ ]*)' "$rgs" | head -1)
        if [[ -n "$extracted" ]] && command -v "$extracted" &>/dev/null 2>&1; then
            echo "$extracted"; return 0
        fi
    fi
    return 1
}

# ── DEPENDENCY CHECK: xdotool ────────────────────────────────────────────────
# WHY: xdotool gives the Godot window focus without requiring a mouse click
# ASSUMES: dnf is available (Fedora confirmed from session context)
# VERIFIES WITH: command -v xdotool exits 0
# MENTAL MODEL BEFORE: xdotool may not be installed
# MENTAL MODEL AFTER:  xdotool available or user prompted
# FAILURE MODE: install declined → game launches without auto-focus, user clicks
# CITATION (Tier 2 — xdotool): https://manpages.ubuntu.com/manpages/focal/man1/xdotool.1.html
HAS_XDOTOOL=true
if ! command -v xdotool &>/dev/null; then
    echo "[WARN] xdotool not found — window auto-focus disabled"
    echo "[WARN] Install with: sudo dnf install xdotool"
    read -r -p "Install xdotool now? [y/N] " resp
    if [[ "$resp" =~ ^[Yy]$ ]]; then
        sudo dnf install -y xdotool
        HAS_XDOTOOL=true
    else
        HAS_XDOTOOL=false
        echo "[INFO] Continuing without xdotool — click the game window to focus it"
    fi
fi

# ── LOCATE PROJECT ───────────────────────────────────────────────────────────
# WHY: script may be run from parachute-cfd-game/ or godot_project/
# ASSUMES: project.godot is in godot_project/
# VERIFIES WITH: project.godot exists at resolved path
# FAILURE MODE: not found → error with expected path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/godot_project/project.godot" ]]; then
    PROJECT_DIR="$SCRIPT_DIR/godot_project"
elif [[ -f "$SCRIPT_DIR/project.godot" ]]; then
    PROJECT_DIR="$SCRIPT_DIR"
else
    echo "[ERROR] Cannot find project.godot in $SCRIPT_DIR or $SCRIPT_DIR/godot_project"
    exit 1
fi
echo "[INFO] Project: $PROJECT_DIR"

# ── LOCATE GODOT ─────────────────────────────────────────────────────────────
GODOT=$(find_godot) || {
    echo "[ERROR] Godot 4 binary not found."
    echo "        Set GODOT_BIN=/path/to/godot4 or install Godot 4."
    exit 1
}
echo "[INFO] Godot binary: $GODOT"

# ── LOG FILE ─────────────────────────────────────────────────────────────────
# WHY: write all output to log AND stream to terminal simultaneously
# ASSUMES: /tmp is writable
# VERIFIES WITH: log file exists after launch
LOGFILE="/tmp/godot_debug_$(date +%Y%m%d_%H%M%S).log"
echo "[INFO] Full log: $LOGFILE"
echo "[INFO] Launching game..."
echo ""
echo "=========================================="
echo "  CONTROLS (after window gets focus):"
echo "  SPACE       = deploy canopy (~4000 ft)"
echo "  Q / E       = turn left / right"
echo "  C           = cycle camera"
echo "  H           = toggle HUD"
echo "  Tab         = flight check"
echo "  X           = cutaway"
echo "  V           = reserve"
echo "  F           = flare"
echo "  R           = restart"
echo "  Escape      = pause"
echo "=========================================="
echo ""

# ── LAUNCH GODOT WITH LIVE OUTPUT ────────────────────────────────────────────
# WHY: tee writes to log and stdout simultaneously; --path sets project root
# ASSUMES: Godot 4 accepts --path argument
# VERIFIES WITH: [VERBATIM] lines appear in terminal after launch
# CITATION (Tier 2 — Godot --path argument):
#   https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
$GODOT --path "$PROJECT_DIR" 2>&1 | tee "$LOGFILE" &
GODOT_PID=$!
echo "[INFO] Godot PID: $GODOT_PID"

# ── AUTO-FOCUS WINDOW ────────────────────────────────────────────────────────
# WHY: without focus, Input.is_action_just_pressed() returns false for all keys
#      xdotool search finds the window by name and calls windowfocus on it
# ASSUMES: Godot window title contains "Parachute" or "Godot" within 8 seconds
# VERIFIES WITH: xdotool search returns a window ID; focus command exits 0
# MENTAL MODEL BEFORE: Godot window exists but terminal has keyboard focus
# MENTAL MODEL AFTER:  Godot window has keyboard focus; keys go to game
# FAILURE MODE: window not found in timeout → print manual focus instruction
# CITATION (Tier 2 — xdotool search and windowfocus):
#   https://manpages.ubuntu.com/manpages/focal/man1/xdotool.1.html
if $HAS_XDOTOOL; then
    echo "[INFO] Waiting for Godot window..."
    FOCUSED=false
    for i in $(seq 1 16); do
        sleep 0.5
        # Search for window by title — Godot 4 titles include project name or "Godot"
        WID=$(xdotool search --name "Parachute\|Godot\|parachute" 2>/dev/null | head -1)
        if [[ -n "$WID" ]]; then
            xdotool windowfocus --sync "$WID" 2>/dev/null && {
                echo "[INFO] Window focused (ID=$WID) — press SPACE to deploy"
                FOCUSED=true
                break
            }
        fi
    done
    if ! $FOCUSED; then
        echo "[WARN] Could not auto-focus window after 8s"
        echo "[WARN] Click the game window manually, then press SPACE"
    fi
fi

# ── WAIT AND SHOW FILTERED DIAGNOSTICS ───────────────────────────────────────
# WHY: wait for Godot to exit; show key diagnostic lines as they arrive
# ASSUMES: Godot process exits when game window is closed
# VERIFIES WITH: [VERBATIM] deploy/DIAGNOSIS lines appear when SPACE is pressed
echo ""
echo "[INFO] Watching for key events (press SPACE in game window)..."
echo "[INFO] Key diagnostic lines will appear here:"
echo "---"
# Stream the log file to terminal filtered for important events
tail -f "$LOGFILE" --pid=$GODOT_PID 2>/dev/null | grep --line-buffered \
    -E "deploy|OPENING|DIAGNOSIS|INPUT|turn|flare|cutaway|reserve|ERROR|FATAL|POLL: [a-z]" &
TAIL_PID=$!

wait $GODOT_PID 2>/dev/null
kill $TAIL_PID 2>/dev/null || true

echo ""
echo "[INFO] Game exited. Full log: $LOGFILE"
echo "[INFO] Last 20 diagnostic lines:"
grep -E "deploy|OPENING|DIAGNOSIS|INPUT|turn|flare|cutaway|reserve|ERROR|POLL: [a-z]" \
    "$LOGFILE" | tail -20
