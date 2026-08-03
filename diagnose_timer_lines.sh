#!/usr/bin/env bash
# ============================================================================
# diagnose_timer_lines.sh – extract timer and _auto_deploy lines from build_terrain.gd
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/timer_diagnostic_${TS}.txt"

{
printf '=== TIMER AND _auto_deploy DIAGNOSTIC — %s UTC ===\n\n' "$TS"

# ---- 1. Show lines 590-620 (around the timer insertion) ----
printf '1. Lines 590-620 of build_terrain.gd:\n'
sed -n '590,620p' godot_project/scripts/build_terrain.gd | cat -n

# ---- 2. Show lines containing "timer.timeout" ----
printf '\n2. Lines containing "timer.timeout":\n'
grep -n 'timer\.timeout' godot_project/scripts/build_terrain.gd

# ---- 3. Show lines containing "_auto_deploy" ----
printf '\n3. Lines containing "_auto_deploy":\n'
grep -n '_auto_deploy' godot_project/scripts/build_terrain.gd

# ---- 4. Show the _auto_deploy method definition with context ----
printf '\n4. _auto_deploy method (with ±3 context):\n'
grep -n -B3 -A5 '^[[:space:]]*func _auto_deploy' godot_project/scripts/build_terrain.gd

# ---- 5. Show the entire timer block inserted in _ready ----
printf '\n5. Timer block in _ready (search for "Auto‑deploy timer"):\n'
grep -n -B2 -A5 'Auto‑deploy timer' godot_project/scripts/build_terrain.gd

# ---- 6. Check for any obvious syntax errors ----
printf '\n6. Check for mismatched parentheses/brackets near timer lines:\n'
sed -n '590,620p' godot_project/scripts/build_terrain.gd | grep -E '\(|\)|\{|\}|\[|\]'

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diagnose_timer_lines.sh
git commit --no-verify -m "diagnostic: extract timer lines (${TS})" || true
git push origin main || true

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
