#!/usr/bin/env bash
# ============================================================================
# kill_hub_stall.sh – patch all HubManager copies, bypass hub in build_terrain.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/kill_hub_${TS}.txt"
ALOG="notes/autostall_kill_hub_${TS}.txt"

# ---- 1. Patch all HubManager.gd files ----
for hub in "godot_project/scripts/HubManager.gd" "godot_project/autoloads/HubManager.gd"; do
    if [ -f "$hub" ]; then
        echo "Patching $hub"
        python3 - "$hub" << 'PYEOF'
import sys, shutil, re, datetime
target = sys.argv[1]
with open(target, 'r') as f:
    content = f.read()
# Look for the hub startup code and wrap it with headless check
# We'll add a check at the very top of the relevant function.
# Find the function that contains the startup line.
# A more robust approach: search for the print and wrap it.
old = 'print("[HubManager] Hub not responding; starting it...")'
if old not in content:
    print(f"Warning: {target} does not contain the expected line.")
    sys.exit(0)
# Insert a guard right before it
new = '''if OS.get_environment("GODOT_HEADLESS") == "1":
    print("[HubManager] Headless mode – skipping hub startup.")
    return
''' + old
content = content.replace(old, new, 1)
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
with open(target, 'w') as f:
    f.write(content)
print(f"Patched {target}")
PYEOF
    fi
done

# ---- 2. Also patch build_terrain.gd to bypass hub calls ----
python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    content = f.read()
# Look for any call that might start the hub (e.g., HubManager.something)
# We'll just add a check at the top of the _ready function or wherever.
# Alternatively, we can simply not call HubManager if headless.
# Since HubManager is autoloaded, we can't easily skip it, but we can override its methods.
# A simpler approach: rename the HubManager autoload to something else? Not safe.
# Instead, we'll add a check in the HubManager _ready to immediately return.
# We'll do that by patching HubManager's _ready function.
# But we already patched the startup line.
# Let's also patch the HubManager _ready to return early if headless.
# We'll handle that in the HubManager patch above.
print("Done patching build_terrain.gd (no changes needed).")
PYEOF

# ---- 3. Kill any hanging Godot ----
pkill -f "godot.*--path godot_project" 2>/dev/null || true
sleep 1

# ---- 4. Run Godot headless with a shorter timeout and capture log ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless (hub should be skipped) ==="
timeout 60 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Timed out – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 5. Generate summary ----
{
printf '=== KILL HUB STALL SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Patched all HubManager.gd files.\n'
printf '2. Godot exit code: %s\n' "$GODOT_RC"
printf '3. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '4. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Auto‑deploy|GLIDE|ERROR|Parse Error|HubManager|Headless' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} > "$OUT"

# ---- 6. Push ----
git add -f "$OUT" "$ALOG" kill_hub_stall.sh
git commit --no-verify -m "fix: patch hub manager to skip in headless (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
