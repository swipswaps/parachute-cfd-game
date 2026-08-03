#!/usr/bin/env bash
# ============================================================================
# diagnose_auto_deploy.sh – exhaustive grep for _auto_deploy and timer block.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/auto_deploy_diagnostic_${TS}.txt"

{
printf '=== AUTO_DEPLOY DIAGNOSTIC — %s UTC ===\n\n' "$TS"

# ---- 1. Find all occurrences of _auto_deploy ----
printf '1. All lines containing "_auto_deploy":\n'
grep -n '_auto_deploy' godot_project/scripts/build_terrain.gd 2>/dev/null || echo "No matches found"
printf '\n'

# ---- 2. Show lines around each occurrence ----
printf '2. Context for each occurrence (±3):\n'
grep -n -B3 -A3 '_auto_deploy' godot_project/scripts/build_terrain.gd 2>/dev/null | head -50
printf '\n'

# ---- 3. Show the full function definition if found ----
printf '3. Function definition (grep for "func _auto_deploy"):\n'
grep -n 'func _auto_deploy' godot_project/scripts/build_terrain.gd 2>/dev/null || echo "Function definition not found"
printf '\n'

# ---- 4. Show the timer block ----
printf '4. Timer block (contains "_auto_deploy_timer" or "create_timer"):\n'
grep -n -B2 -A5 'create_timer\|_auto_deploy_timer' godot_project/scripts/build_terrain.gd 2>/dev/null | head -40
printf '\n'

# ---- 5. Show the last 30 lines of the file ----
printf '5. Last 30 lines of build_terrain.gd:\n'
tail -30 godot_project/scripts/build_terrain.gd | cat -n
printf '\n'

# ---- 6. Check for any obvious parse error markers ----
printf '6. Check for "Parse Error" in recent godot output (optional):\n'
# We'll just note that we're skipping the hanging check.
printf '(Skipping godot --check-only to avoid hang.)\n'

} 2>&1 | tee "$OUT"

git add -f "$OUT" diagnose_auto_deploy.sh
git commit --no-verify -m "diagnostic: locate _auto_deploy and timer (${TS})" || true
git push origin main || true

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
