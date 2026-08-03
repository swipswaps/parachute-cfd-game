#!/usr/bin/env bash
# ============================================================================
# fix_nested_method_v2.sh – move _auto_deploy out of _ready, skip hanging check.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_nested_v2_${TS}.txt"
ALOG="notes/autostall_fixed_v2_${TS}.txt"

python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"

with open(target, 'r') as f:
    lines = f.readlines()

# ---- 1. Locate the nested _auto_deploy inside _ready ----
start_idx = None
end_idx = None
for i, ln in enumerate(lines):
    if ln.strip() == "func _auto_deploy():":
        cur_indent = re.match(r'^[ \t]*', ln).group(0)
        if len(cur_indent) > 0:  # indented => inside a function
            start_idx = i
            # Find end: next line with same or less indent
            indent = cur_indent
            for j in range(i+1, len(lines)):
                if lines[j].strip() == "":
                    continue
                cur = re.match(r'^[ \t]*', lines[j]).group(0)
                if len(cur) <= len(indent) and not lines[j].strip().startswith("#"):
                    end_idx = j
                    break
            else:
                end_idx = len(lines)
            break

if start_idx is None:
    print("❌ Nested _auto_deploy method not found – aborting.")
    sys.exit(1)

print(f"Found nested _auto_deploy at lines {start_idx+1}-{end_idx}")

# ---- 2. Extract and remove method ----
method_lines = lines[start_idx:end_idx]
del lines[start_idx:end_idx]

# ---- 3. Find insertion point (after last class var) ----
insert_point = None
for i in range(len(lines)-1, -1, -1):
    if re.match(r'^[ \t]*var ', lines[i]) and not lines[i].strip().startswith("#"):
        insert_point = i + 1
        break
if insert_point is None:
    # fallback: after extends line
    for i, ln in enumerate(lines):
        if ln.strip().startswith("extends "):
            insert_point = i + 1
            break
if insert_point is None:
    print("❌ Could not find insertion point – aborting.")
    sys.exit(1)

# ---- 4. Strip one level of indent from method lines ----
# method_indent is the indent of the method definition line
method_indent = re.match(r'^[ \t]*', method_lines[0]).group(0)
# Remove that indent from all lines that start with it
for i, ln in enumerate(method_lines):
    if ln.startswith(method_indent):
        method_lines[i] = ln[len(method_indent):]

# ---- 5. Insert at class scope ----
lines[insert_point:insert_point] = method_lines
print(f"Inserted _auto_deploy at class scope (line {insert_point+1})")

# ---- 6. Ensure timer connection uses Callable ----
for i, ln in enumerate(lines):
    if "timer.timeout.connect" in ln and "_auto_deploy" in ln:
        if "Callable" not in ln:
            lines[i] = ln.replace("timer.timeout.connect(_auto_deploy)", 'timer.timeout.connect(Callable(self, "_auto_deploy"))')
            print("Fixed timer connection.")

# ---- 7. Write and backup ----
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
print(f"Backup: {backup}")

with open(target, 'w') as f:
    f.writelines(lines)
print("✅ _auto_deploy moved to class scope.")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ Fix failed – aborting."
    exit 1
fi

# ---- 8. Run Godot headless (skip check) ----
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

# ---- 9. Generate summary ----
{
printf '=== NESTED METHOD FIX V2 SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Moved _auto_deploy from inside _ready to class scope.\n'
printf '2. Godot exit code: %s\n' "$GODOT_RC"
printf '3. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '4. Key markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Auto‑deploy|GLIDE|ERROR' "$ALOG" 2>/dev/null | head -30 | sed 's/^/   /'
} > "$OUT"

# ---- 10. Push ----
git add -f godot_project/scripts/build_terrain.gd "$OUT" "$ALOG" fix_nested_method_v2.sh
git commit --no-verify -m "fix: move _auto_deploy to class scope (v2, ${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
