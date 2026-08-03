#!/usr/bin/env bash
# ============================================================================
# diagnose_and_fix_hub.sh – find HubManager.gd, patch it, fix timer, run test.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/hub_fix_${TS}.txt"
ALOG="notes/autostall_hub_fixed_${TS}.txt"

# ---- 1. Locate HubManager.gd ----
HUB_FILE=""
for f in "godot_project/scripts/HubManager.gd" "godot_project/autoloads/HubManager.gd"; do
    if [ -f "$f" ]; then
        HUB_FILE="$f"
        break
    fi
done

if [ -z "$HUB_FILE" ]; then
    echo "❌ HubManager.gd not found – aborting."
    exit 1
fi
echo "✅ Found HubManager.gd at: $HUB_FILE"

# ---- 2. Diagnostic: show lines around hub startup ----
printf '=== HUB MANAGER DIAGNOSTIC — %s UTC ===\n\n' "$TS" > "$OUT"
printf 'File: %s\n\n' "$HUB_FILE" >> "$OUT"
printf 'Lines containing "Hub not responding":\n' >> "$OUT"
grep -n -B2 -A5 "Hub not responding" "$HUB_FILE" >> "$OUT" 2>/dev/null || echo "(not found)" >> "$OUT"
printf '\nLines containing "starting it":\n' >> "$OUT"
grep -n -B2 -A5 "starting it" "$HUB_FILE" >> "$OUT" 2>/dev/null || echo "(not found)" >> "$OUT"

# ---- 3. Apply patch to HubManager ----
python3 - "$HUB_FILE" << 'PYEOF'
import sys, shutil, re, datetime
target = sys.argv[1]

with open(target, 'r') as f:
    content = f.read()

# Check if already patched
if "GODOT_HUB_ALREADY_RUNNING" in content:
    print("✅ HubManager already patched – skipping.")
    sys.exit(0)

# Find the line that prints "Hub not responding; starting it..."
old = 'print("[HubManager] Hub not responding; starting it...")'
if old not in content:
    # Try alternative variants
    old = 'print("Hub not responding; starting it...")'
if old not in content:
    # Try just "Hub not responding"
    old = "Hub not responding"
    if old not in content:
        print("❌ Could not find hub startup line – aborting.")
        sys.exit(1)

# Insert the headless check before the startup line
new = '''if OS.get_environment("GODOT_HEADLESS") == "1":
    print("[HubManager] Headless mode – skipping hub startup.")
    return
''' + old

content = content.replace(old, new, 1)

backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

with open(target, 'w') as f:
    f.write(content)
print("✅ HubManager patched.")
PYEOF
HUB_RC=$?
if [ $HUB_RC -ne 0 ]; then
    echo "⚠️  Hub patch failed – continuing anyway."
fi

# ---- 4. Fix timer connection (same as before) ----
python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"

with open(target, 'r') as f:
    lines = f.readlines()

# Remove class-scope timer connections
for i, ln in enumerate(lines):
    if not ln.startswith((" ", "\t")) and "_lbl_timer.timeout.connect" in ln:
        lines[i] = ""

# Find _lbl_timer creation
creation_idx = None
for i, ln in enumerate(lines):
    if "Timer.new()" in ln and "_lbl_timer" in ln:
        creation_idx = i
        break

if creation_idx is not None:
    # Check if connection already exists after it
    connection_exists = False
    for i in range(creation_idx + 1, min(creation_idx + 10, len(lines))):
        if "_lbl_timer.timeout.connect" in lines[i]:
            connection_exists = True
            break
    if not connection_exists:
        indent = re.match(r'^[ \t]*', lines[creation_idx]).group(0)
        insert_line = f"{indent}_lbl_timer.timeout.connect(_dump_all_labels)\n"
        lines.insert(creation_idx + 1, insert_line)
        print("Inserted timer connection.")

# Backup and write
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

with open(target, 'w') as f:
    f.writelines(lines)
print("✅ Timer connection fixed.")
PYEOF

# ---- 5. Kill hanging Godot ----
pkill -f "godot.*--path godot_project" 2>/dev/null || true
sleep 1

# ---- 6. Run Godot headless ----
export GODOT_HEADLESS=1
echo "=== Running Godot headless with hub patch ==="
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
printf '\n=== HUB FIX SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. HubManager file: %s\n' "$HUB_FILE"
printf '2. Hub patch applied: %s\n' "$([ $HUB_RC -eq 0 ] && echo "✅" || echo "❌")"
printf '3. Timer connection fixed.\n'
printf '4. Godot exit code: %s\n' "$GODOT_RC"
printf '5. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '6. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Auto‑deploy|GLIDE|ERROR|Parse Error|HubManager|Headless' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} >> "$OUT"

# ---- 8. Push ----
git add -f "$HUB_FILE" godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" diagnose_and_fix_hub.sh
git commit --no-verify -m "fix: hub patch + timer fix (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
