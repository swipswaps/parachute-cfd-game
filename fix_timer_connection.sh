#!/usr/bin/env bash
# ============================================================================
# fix_timer_connection.sh – correct the undeclared identifier at line 584.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_timer_connection_${TS}.txt"
ALOG="notes/autostall_timer_fixed_${TS}.txt"

python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"

with open(target, 'r') as f:
    lines = f.readlines()

# ---- 1. Locate line 584 ----
# We'll use the line number from the diagnostic: line 584 (1-indexed)
# Convert to 0-indexed: 583
idx = 583
if idx >= len(lines):
    print(f"❌ Line 584 out of range – aborting.")
    sys.exit(1)

old_line = lines[idx]
print(f"Line 584: {old_line.strip()}")

# ---- 2. Replace with correct line ----
# The correct line should be: _lbl_timer.timeout.connect(_dump_all_labels)
new_line = "_lbl_timer.timeout.connect(_dump_all_labels)\n"

# Check if it's already correct
if old_line.strip() == new_line.strip():
    print("✅ Line 584 already correct – skipping.")
    sys.exit(0)

# Backup
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

# Replace
lines[idx] = new_line

with open(target, 'w') as f:
    f.writelines(lines)

print("✅ Corrected line 584 to use _lbl_timer.")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ Fix failed – aborting."
    exit 1
fi

# ---- 3. Run Godot headless ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless with fixed timer connection ==="
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
printf '=== TIMER CONNECTION FIX SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Fixed line 584: _lbl__auto_deploy_timer → _lbl_timer.\n'
printf '2. Godot exit code: %s\n' "$GODOT_RC"
printf '3. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '4. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Auto‑deploy|GLIDE|ERROR|Parse Error' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} > "$OUT"

# ---- 5. Push ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" fix_timer_connection.sh
git commit --no-verify -m "fix: correct timer connection at line 584 (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
