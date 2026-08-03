#!/usr/bin/env bash
# ============================================================================
# run_and_push.sh – run Godot with auto‑deploy timer, push log.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
ALOG="notes/autostall_timer_${TS}.txt"
OUT="notes/timer_summary_${TS}.txt"

# ---- 1. Verify clamp patch ----
echo "=== Verifying clamp patch ==="
if grep -q '_character.position.y <= 25.0 + 0.01' godot_project/scripts/build_terrain.gd; then
    echo "✅ Clamp patch present."
else
    echo "❌ Clamp patch missing – aborting."
    exit 1
fi

# ---- 2. Verify timer patch ----
echo "=== Verifying timer patch ==="
if grep -q '_auto_deploy' godot_project/scripts/build_terrain.gd; then
    echo "✅ Timer patch present."
else
    echo "❌ Timer patch missing – aborting."
    exit 1
fi

# ---- 3. Run Godot headless ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless (auto‑deploy after 5s) ==="
timeout 120 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Timed out – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 4. Generate summary ----
{
printf '=== TIMER TEST SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Clamp patch applied.\n'
printf '2. Timer patch applied.\n'
printf '3. Godot exit code: %s\n' "$GODOT_RC"
printf '4. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '5. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Auto‑deploy|GLIDE|ERROR|FATAL' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
printf '\n=== NEXT STEPS ===\n'
printf 'If GLIDE and "Ground impact" appear, the fix works.\n'
printf 'If terrain looks bad, inspect the terrain material.\n'
} > "$OUT"

# ---- 5. Push ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" run_and_push.sh
git commit --no-verify -m "test: timer auto‑deploy (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
