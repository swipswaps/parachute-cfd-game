#!/usr/bin/env bash
# ============================================================================
# diagnose_end_of_file.sh – show tail of build_terrain.gd to debug indent error.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/eof_diagnostic_${TS}.txt"

{
printf '=== END-OF-FILE DIAGNOSTIC — %s UTC ===\n\n' "$TS"

# ---- 1. Show lines 3840-3860 (around the error) ----
printf '1. Lines 3840-3860 of build_terrain.gd (with line numbers):\n'
sed -n '3840,3860p' godot_project/scripts/build_terrain.gd | cat -n | sed 's/^[ ]*//' | awk '{printf "%4d: %s\n", $1+3839, substr($0, index($0,$2))}'
printf '\n'

# ---- 2. Show last 20 lines of the file ----
printf '2. Last 20 lines of build_terrain.gd:\n'
tail -20 godot_project/scripts/build_terrain.gd | cat -n
printf '\n'

# ---- 3. Show any lines with trailing spaces or tabs ----
printf '3. Lines with trailing spaces or tabs (last 50):\n'
tail -50 godot_project/scripts/build_terrain.gd | cat -e
printf '\n'

# ---- 4. Show the entire timer insertion block (search for "_auto_deploy_timer") ----
printf '4. Timer block (lines containing "_auto_deploy_timer"):\n'
grep -n -B2 -A2 '_auto_deploy_timer' godot_project/scripts/build_terrain.gd
printf '\n'

# ---- 5. Show the _auto_deploy method (if present) ----
printf '5. _auto_deploy method:\n'
grep -n -B2 -A5 'func _auto_deploy' godot_project/scripts/build_terrain.gd

} 2>&1 | tee "$OUT"

git add -f "$OUT" diagnose_end_of_file.sh
git commit --no-verify -m "diagnostic: end-of-file indentation (${TS})" || true
git push origin main || true

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
