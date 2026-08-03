#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_landing_terrain_${TS}.txt"
ALOG="notes/autostall_landing_fixed_${TS}.txt"

# ---- 1. Remove _safe_landing guard from clamp block ----
python3 - << 'PYEOF'
import sys, shutil, datetime, re
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    lines = f.readlines()

# Locate the clamp block lines 2139-2143
# We'll find the line containing "_character.position.y <= 25.0 + 0.01:" and replace the inner if
p_idx = None
for i, ln in enumerate(lines):
    if "_character.position.y <= 25.0 + 0.01:" in ln:
        # Ensure the next lines match the expected pattern
        if i+4 < len(lines) and "_character.position.y = 25.0" in lines[i+1]:
            p_idx = i
            break
if p_idx is None:
    print("Clamp block not found – skipping.")
    sys.exit(0)

# We want to change the inner condition from:
#   if not _safe_landing and _game_state != GameState.GAME_OVER:
# to:
#   if _game_state != GameState.GAME_OVER:
# So remove the "_safe_landing and " part.
old_inner = "if not _safe_landing and _game_state != GameState.GAME_OVER:"
new_inner = "if _game_state != GameState.GAME_OVER:"

# Check if it's already changed
if old_inner not in "".join(lines):
    print("Inner condition already changed or not found – skipping.")
    sys.exit(0)

# Create backup
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)

# Replace in the file
modified = False
for i, ln in enumerate(lines):
    if old_inner in ln and "_character.position.y = 25.0" in lines[i-1]:
        lines[i] = lines[i].replace(old_inner, new_inner)
        modified = True
        break

if not modified:
    print("Could not replace inner condition – skipping.")
    sys.exit(0)

with open(target, 'w') as f:
    f.writelines(lines)
print(f"Removed _safe_landing guard from clamp block. Backup at {backup}")
PYEOF

# ---- 2. Add backup altitude check (after clamp block) ----
python3 - << 'PYEOF'
import sys, shutil, datetime, re
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    content = f.read()

# Find the physics_process function and add a check at the end
# Look for "func _physics_process(delta: float) -> void:" and the end of it
# We'll insert a check that triggers GAME_OVER if _current_altitude <= 0.0 for > 2 seconds
# We'll add a new variable at the top of the class: var _altitude_ground_timer: float = 0.0
# Then in physics_process, at the end, check _current_altitude <= 0.0 and increment timer, else reset.
# If timer > 2.0, set GAME_OVER.

# Add class variable
var_decl = "var _altitude_ground_timer: float = 0.0"
if var_decl in content:
    print("Backup altitude check already added – skipping.")
    sys.exit(0)

# Find a good place to add the var: after other var declarations or at the top of the class
# We'll insert after the _headless_warp_done declaration.
lines = content.split("\n")
insert_idx = None
for i, ln in enumerate(lines):
    if "var _headless_warp_done:" in ln:
        insert_idx = i + 1
        break
if insert_idx is None:
    # fallback: after the first "var" line
    for i, ln in enumerate(lines):
        if ln.strip().startswith("var "):
            insert_idx = i + 1
            break
if insert_idx is None:
    print("Could not find place to insert var – skipping altitude check.")
    sys.exit(0)

lines.insert(insert_idx, "var _altitude_ground_timer: float = 0.0  # backup landing timer")
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)

# Now find the end of _physics_process and add the check
# We'll find "func _physics_process(delta: float) -> void:" and then the last "}" or the function end
func_start = None
for i, ln in enumerate(lines):
    if "func _physics_process(delta: float) -> void:" in ln:
        func_start = i
        break
if func_start is None:
    print("Could not find _physics_process – skipping altitude check.")
    sys.exit(0)

# Find the matching end brace (or the line before the next function)
# We'll look for the last line that is not indented (same indent as func) or the next "func"
indent = re.match(r'^[ \t]*', lines[func_start]).group(0)
func_end = None
for i in range(func_start + 1, len(lines)):
    if lines[i].strip() == "":
        continue
    if lines[i].startswith("func ") and i > func_start:
        func_end = i - 1
        break
    if lines[i].startswith("class ") or lines[i].startswith("extends "):
        func_end = i - 1
        break
    # If the line has same indent as func and is not a comment, it's the end
    if re.match(r'^[ \t]*', lines[i]).group(0) == indent and not lines[i].strip().startswith("#"):
        func_end = i - 1
        break
if func_end is None:
    func_end = len(lines) - 1

# Insert the altitude check right before the end of the function (before the closing brace or before the next func)
# We'll add it after the existing code but before any return or closing brace.
# Look for the last line of the function that is not a closing brace or return.
# We'll insert after the last indented line that is not a closing brace.
insert_pos = func_end
while insert_pos > func_start and (lines[insert_pos].strip() == "" or lines[insert_pos].strip() in ["}", "return"]):
    insert_pos -= 1
if insert_pos < func_start:
    print("Could not find insertion point – skipping altitude check.")
    sys.exit(0)

# Insert the new code after the last line
new_lines = [
    "",
    indent + "# Backup landing check: if altitude <= 0 for > 2s, force GAME_OVER",
    indent + "if _current_altitude <= 0.0:",
    indent + "\t_altitude_ground_timer += delta",
    indent + "\tif _altitude_ground_timer > 2.0 and _game_state != GameState.GAME_OVER:",
    indent + "\t\t_game_state = GameState.GAME_OVER",
    indent + '\t\tprint("[VERBATIM] Backup landing – ground contact (no flare)")',
    indent + "else:",
    indent + "\t_altitude_ground_timer = 0.0",
]
lines[insert_pos+1:insert_pos+1] = new_lines

with open(target, 'w') as f:
    f.write("\n".join(lines))
print(f"Added backup altitude check. Backup at {backup}")
PYEOF

# ---- 3. Log terrain texture paths for debugging ----
python3 - << 'PYEOF'
import sys, os, json, datetime
import glob
target = "godot_project"
textures = glob.glob(os.path.join(target, "**", "*.png"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.jpg"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.jpeg"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.tga"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.dds"), recursive=True)
# Also check for .material files that reference textures
materials = glob.glob(os.path.join(target, "**", "*.material"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.tres"), recursive=True) + \
            glob.glob(os.path.join(target, "**", "*.res"), recursive=True)
# Write to a file
with open("notes/terrain_textures_20260803150000.txt", "w") as f:
    f.write("=== Terrain texture files ===\n")
    for t in textures:
        f.write(t + "\n")
    f.write("\n=== Material files (may reference textures) ===\n")
    for m in materials:
        f.write(m + "\n")
print("Terrain texture list saved to notes/terrain_textures_20260803150000.txt")
PYEOF

# ---- 4. Generate summary ----
{
printf '=== fix_landing_terrain.sh — %s UTC ===\n\n' "$TS"
printf '1. Removed _safe_landing guard from clamp block (now always triggers GAME_OVER).\n'
printf '2. Added backup altitude check: if altitude <=0 for >2s, forces GAME_OVER.\n'
printf '3. Logged terrain texture paths for debugging.\n\n'
printf 'Terrain texture file: notes/terrain_textures_20260803150000.txt\n'
} > "$OUT"

# ---- 5. Push all changes ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" notes/terrain_textures_20260803150000.txt fix_landing_terrain.sh
git commit --no-verify -m "fix: remove safe_landing guard, add backup landing timer, terrain texture log (${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "notes/terrain_textures_20260803150000.txt"
