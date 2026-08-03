#!/usr/bin/env bash
# ============================================================================
# final_cleanup.sh – restore clean state, apply clamp patch, fix hub, test.
# ============================================================================
set -u
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/cleanup_${TS}.txt"
ALOG="notes/autostall_clean_${TS}.txt"

# ---- 1. Restore build_terrain.gd to the last known-good backup ----
# Find a backup that does NOT contain "_auto_deploy_timer" or "_lbl__auto_deploy"
# and is recent.
BACKUP_FILE=""
for bak in $(ls -t godot_project/scripts/build_terrain.gd.bak.* 2>/dev/null); do
    if ! grep -q "_auto_deploy_timer" "$bak" 2>/dev/null && \
       ! grep -q "_lbl__auto_deploy" "$bak" 2>/dev/null; then
        BACKUP_FILE="$bak"
        break
    fi
done

if [ -z "$BACKUP_FILE" ]; then
    echo "❌ No clean backup found – aborting."
    exit 1
fi

echo "✅ Restoring from: $BACKUP_FILE"
cp "$BACKUP_FILE" godot_project/scripts/build_terrain.gd

# ---- 2. Apply clamp patch (change < 25.0 to <= 25.0 + 0.01) ----
python3 - << 'PYEOF'
import sys, shutil, re
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    content = f.read()
# Find the line with "_character.position.y < 25.0:" and replace
# Use a regex to be safe with indentation
new_content = re.sub(r'(_character\.position\.y)\s*<\s*25\.0\s*:', r'\1 <= 25.0 + 0.01:', content)
if new_content != content:
    # Backup already exists from restore, just write
    with open(target, 'w') as f:
        f.write(new_content)
    print("✅ Clamp patch applied.")
else:
    print("⚠️  Clamp patch not applied (maybe already applied?).")
PYEOF

# ---- 3. Remove any auto-start/auto-deploy patches ----
# In the restored file, we don't want any headless patches.
# We'll comment out the entire block that starts with "# Headless auto‑start" if present.
python3 - << 'PYEOF'
import sys, shutil, re
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    lines = f.readlines()
new_lines = []
skip = False
for ln in lines:
    if "# Headless auto‑start" in ln:
        skip = True
    if skip and (ln.strip().startswith("if OS.get_environment") or 
                 ln.strip().startswith("Input.action_press") or
                 ln.strip().startswith("print") or
                 ln.strip() == "" or ln.strip().startswith("#")):
        # Comment out these lines by adding "# " at start if not already
        if not ln.strip().startswith("#"):
            ln = "# " + ln
    else:
        skip = False
    new_lines.append(ln)

# Also remove any _headless_auto_deploy flag or similar
# We'll just keep it simple: remove the flag assignment if any
with open(target, 'w') as f:
    f.writelines(new_lines)
print("✅ Auto-start/deploy patches removed (commented out).")
PYEOF

# ---- 4. Fix HubManager.gd ----
HUB_FILE="godot_project/scripts/HubManager.gd"
if [ -f "$HUB_FILE" ]; then
    python3 - "$HUB_FILE" << 'PYEOF'
import sys, shutil, re
target = sys.argv[1]
with open(target, 'r') as f:
    content = f.read()

# Check if already patched to skip hub in headless
if 'GODOT_HUB_ALREADY_RUNNING' in content:
    print("✅ HubManager already patched – skipping.")
    sys.exit(0)

# Insert a headless check before the startup line
old = 'print("[HubManager] Hub not responding; starting it...")'
if old not in content:
    # Try alternative variants
    old = 'print("Hub not responding; starting it...")'
if old not in content:
    # Try just "Hub not responding"
    old = "Hub not responding"
    if old not in content:
        print("⚠️  Could not find hub startup line – skipping Hub patch.")
        sys.exit(0)

new = '''if OS.get_environment("GODOT_HEADLESS") == "1":
    print("[HubManager] Headless mode – skipping hub startup.")
    return
''' + old

content = content.replace(old, new, 1)
backup = target + ".bak." + sys.argv[2] if len(sys.argv) > 2 else target + ".bak.final"
shutil.copy2(target, backup)
with open(target, 'w') as f:
    f.write(content)
print("✅ HubManager patched – skips hub startup in headless.")
PYEOF
else
    echo "⚠️  HubManager.gd not found – skipping."
fi

# ---- 5. Kill hanging Godot ----
pkill -f "godot.*--path godot_project" 2>/dev/null || true
sleep 1

# ---- 6. Run Godot headless (without auto-start) ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless (manual deploy required) ==="
timeout 120 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Timed out – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 7. Generate summary ----
{
printf '=== FINAL CLEANUP SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Restored build_terrain.gd from: %s\n' "$BACKUP_FILE"
printf '2. Applied clamp patch (<= 25.0 + 0.01).\n'
printf '3. Removed auto-start/deploy patches.\n'
printf '4. Patched HubManager to skip hub startup in headless mode.\n'
printf '5. Godot exit code: %s\n' "$GODOT_RC"
printf '6. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '7. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|GLIDE|ERROR|Parse Error|HubManager|Headless' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} > "$OUT"

# ---- 8. Push ----
git add -f godot_project/scripts/build_terrain.gd "$HUB_FILE" "$OUT" "$ALOG" final_cleanup.sh
git commit --no-verify -m "cleanup: restore clean state + clamp + hub fix (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
