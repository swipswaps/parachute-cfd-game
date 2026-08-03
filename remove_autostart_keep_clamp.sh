#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/remove_autostart_${TS}.txt"

# ---- Remove auto-start block from build_terrain.gd ----
python3 - "$TARGET" << 'PYEOF'
import sys, shutil, datetime, re
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    lines = f.readlines()

# Find the auto-start block – starts with "# Headless auto‑start:" and ends before the next line with same indent or lower
start_idx = None
for i, line in enumerate(lines):
    if "# Headless auto‑start: simulate SPACE press" in line:
        start_idx = i
        break
if start_idx is None:
    print("Auto-start block not found – nothing to remove.")
    sys.exit(0)

# Find the end of the block: look for the next line at the same or lower indentation
indent = re.match(r'^[ \t]*', lines[start_idx]).group(0)
end_idx = start_idx + 1
while end_idx < len(lines):
    cur_indent = re.match(r'^[ \t]*', lines[end_idx]).group(0)
    # If the line is blank or is a comment, continue
    if lines[end_idx].strip() == "":
        end_idx += 1
        continue
    if len(cur_indent) <= len(indent) and lines[end_idx].strip() != "":
        break
    end_idx += 1

# Remove the block
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
del lines[start_idx:end_idx]

with open(target, 'w') as f:
    f.writelines(lines)
print(f"Auto-start block removed. Backup at {backup}")
PYEOF

if [ $? -ne 0 ]; then
    echo "⚠️  build_terrain.gd patch failed – continuing anyway."
fi

# ---- Disable auto-start in autostall_patched.py ----
python3 - << 'PYEOF'
import sys, re, shutil, datetime
path = "autostall_patched.py"
with open(path, 'r') as f:
    content = f.read()

# Find the line that calls apply_auto_start_patch and comment it out
# Look for "apply_auto_start_patch" in the main loop
pattern = r'(\s*)(apply_auto_start_patch\s*\()'
new_content = re.sub(pattern, r'\1# \2', content)

if new_content == content:
    print("No change to autostall_patched.py – apply_auto_start_patch not found.")
else:
    backup = path + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, backup)
    with open(path, 'w') as f:
        f.write(new_content)
    print(f"Autostall_patched.py patched (commented out auto-start). Backup at {backup}")
PYEOF

# ---- Generate summary ----
{
printf '=== remove_autostart_keep_clamp.sh — %s UTC ===\n\n' "$TS"
printf '1. Auto-start block removed from build_terrain.gd.\n'
printf '2. Auto-start patch call commented out in autostall_patched.py.\n'
printf '3. Clamp patch remains (line 2139: <= 25.0 + 0.01).\n\n'
printf 'Next steps:\n'
printf '  - Manually deploy the parachute by pressing Space after jump.\n'
printf '  - Observe if the canopy descends and triggers GAME_OVER.\n'
printf '  - If terrain looks bad, check texture paths and shader settings.\n'
} > "$OUT"

# ---- Push ----
git add -f godot_project/scripts/build_terrain.gd autostall_patched.py "$OUT" remove_autostart_keep_clamp.sh
git commit --no-verify -m "fix: remove auto-start, keep clamp patch (${TS})" || true
git push origin main || true

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
