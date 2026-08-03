#!/usr/bin/env bash
# ============================================================================
# fix_duplicate_timer.sh – rename duplicate 'timer' variable to avoid conflict.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_duplicate_timer_${TS}.txt"
ALOG="notes/autostall_fixed_timer_${TS}.txt"

python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"

with open(target, 'r') as f:
    content = f.read()

# ---- 1. Replace the duplicate 'timer' variable with a unique name ----
# Find lines like: var timer = get_tree().create_timer(5.0)
# Replace with: var _auto_deploy_timer = get_tree().create_timer(5.0)
old_timer_decl = "var timer = get_tree().create_timer(5.0)"
new_timer_decl = "var _auto_deploy_timer = get_tree().create_timer(5.0)"

if old_timer_decl not in content:
    print("❌ Timer declaration not found – aborting.")
    sys.exit(1)

content = content.replace(old_timer_decl, new_timer_decl, 1)

# ---- 2. Update the connection line to use the new variable name ----
old_connect = "timer.timeout.connect(Callable(self, \"_auto_deploy\"))"
new_connect = "_auto_deploy_timer.timeout.connect(Callable(self, \"_auto_deploy\"))"

if old_connect not in content:
    # Try the non-Callable version
    old_connect_alt = "timer.timeout.connect(_auto_deploy)"
    if old_connect_alt in content:
        content = content.replace(old_connect_alt, new_connect, 1)
    else:
        # Fallback: replace any occurrence of 'timer.timeout' with '_auto_deploy_timer.timeout'
        content = content.replace("timer.timeout", "_auto_deploy_timer.timeout", 1)
        print("⚠️  Used fallback replacement.")
else:
    content = content.replace(old_connect, new_connect, 1)

# ---- 3. Also rename any remaining references to 'timer' in the auto-deploy block ----
content = content.replace("timer.timeout", "_auto_deploy_timer.timeout", 1)

# ---- 4. Backup and write ----
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

with open(target, 'w') as f:
    f.write(content)

print("✅ Timer variable renamed to _auto_deploy_timer.")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ Fix failed – aborting."
    exit 1
fi

# ---- 5. Run Godot headless ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless with fixed timer ==="
timeout 120 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Timed out – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 6. Generate summary ----
{
printf '=== DUPLICATE TIMER FIX SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Renamed duplicate "timer" variable to "_auto_deploy_timer".\n'
printf '2. Updated connection to use the new variable name.\n'
printf '3. Godot exit code: %s\n' "$GODOT_RC"
printf '4. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '5. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Auto‑deploy|GLIDE|ERROR|Parse Error' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} > "$OUT"

# ---- 7. Push ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" fix_duplicate_timer.sh
git commit --no-verify -m "fix: rename duplicate timer variable (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
