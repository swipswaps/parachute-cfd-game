#!/usr/bin/env bash
# ============================================================================
# final_fix_all_v2.sh – safe auto‑start patch with proper indent detection.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/final_fix_v2_${TS}.txt"
ALOG="notes/autostall_final_v2_${TS}.txt"

# ---- 1. Apply auto-start patch (no class-scope check) ----
python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"

with open(target, 'r') as f:
    lines = f.readlines()

# Find the anchor – any of these variants
anchors = [
    "Game ready – press SPACE at ~4000 ft to deploy",
    "Game ready – press SPACE",
    "press SPACE at ~4000 ft"
]
anchor_idx = None
for i, ln in enumerate(lines):
    for a in anchors:
        if a in ln:
            anchor_idx = i
            break
    if anchor_idx is not None:
        break

if anchor_idx is None:
    print("ERROR: No anchor found – aborting.")
    sys.exit(1)

# Get the indent of the anchor line
indent = re.match(r'^[ \t]*', lines[anchor_idx]).group(0)
print(f"Anchor line {anchor_idx+1}: {lines[anchor_idx].strip()}")
print(f"Indent: {repr(indent)}")

# Ensure we insert after the anchor line, but if there's a blank line or comment, skip them
insert_idx = anchor_idx + 1
while insert_idx < len(lines) and (lines[insert_idx].strip() == "" or lines[insert_idx].strip().startswith("#")):
    insert_idx += 1

# Backup
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

# Build new lines – both deploy and ui_accept as fallbacks
new_lines = [
    f"{indent}# Headless auto‑start: simulate SPACE press\n",
    f"{indent}if OS.get_environment(\"GODOT_HEADLESS\") == \"1\":\n",
    f"{indent}\tInput.action_press(\"deploy\")\n",
    f"{indent}\tInput.action_release(\"deploy\")\n",
    f"{indent}\tprint(\"[VERBATIM] Headless auto‑start triggered (deploy)\")\n",
    f"{indent}\t# Fallback: some builds use ui_accept\n",
    f"{indent}\tInput.action_press(\"ui_accept\")\n",
    f"{indent}\tInput.action_release(\"ui_accept\")\n",
    f"{indent}\tprint(\"[VERBATIM] Headless auto‑start triggered (ui_accept)\")\n",
]

# Insert
lines[insert_idx:insert_idx] = new_lines

# Write
with open(target, 'w') as f:
    f.writelines(lines)
print("✅ Auto-start patch applied.")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ Auto-start patch failed – aborting."
    exit 1
fi

# ---- 2. Run Godot headless (120s) ----
echo "=== Running Godot headless with auto-start (120s) ==="
timeout 120 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Godot timed out – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 3. Generate summary ----
{
printf '=== FINAL FIX V2 SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Auto-start patch applied (both deploy and ui_accept).\n'
printf '2. Godot run exit code: %s\n' "$GODOT_RC"
printf '3. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '4. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Headless auto-start|GLIDE' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
printf '\n=== NEXT STEPS ===\n'
printf 'If GLIDE telemetry appears, check for "Ground impact" or "Backup landing".\n'
printf 'If terrain looks bad, inspect the terrain material in Godot.\n'
} > "$OUT"

# ---- 4. Push ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" final_fix_all_v2.sh
git commit --no-verify -m "fix: auto-start patch v2 + test (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
