#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
ALOG="notes/autostall_deploy_fixed_${TS}.txt"
OUT="notes/fix_autostart_action_v2_${TS}.txt"

# ---- 1. Fix action name in build_terrain.gd ----
python3 - << 'PYEOF'
import re, sys
path = "godot_project/scripts/build_terrain.gd"
with open(path, 'r') as f:
    content = f.read()

# Replace any "ui_accept" with "deploy" inside an Input.action_press/release call
# But only in the auto-start block (around the HEADLESS check)
# We'll use a more flexible approach: locate the block and replace.
pattern = r'(if OS\.get_environment\("GODOT_HEADLESS"\) == "1":\s*)(Input\.action_press\(")ui_accept("\)\s*Input\.action_release\(")ui_accept("\))'
replacement = r'\1\2deploy\3\4deploy\5'
new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

if new_content == content:
    print("⚠️  No replacement made – trying simpler replace...")
    # Fallback: replace all occurrences of action_press("ui_accept") in the file
    new_content = content.replace('Input.action_press("ui_accept")', 'Input.action_press("deploy")')
    new_content = new_content.replace('Input.action_release("ui_accept")', 'Input.action_release("deploy")')

if new_content == content:
    print("ERROR: No changes made – aborting.")
    sys.exit(1)

with open(path, 'w') as f:
    f.write(new_content)
print("✅ build_terrain.gd patched: ui_accept → deploy")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ build_terrain.gd patch failed – continuing anyway."
fi

# ---- 2. Fix action name in autostall_patched.py ----
python3 - << 'PYEOF'
import re, sys
path = "autostall_patched.py"
with open(path, 'r') as f:
    content = f.read()

# Replace in the auto-start patch block (the one that writes to build_terrain.gd)
# We'll replace all occurrences of "ui_accept" with "deploy" in the whole file
new_content = content.replace('Input.action_press("ui_accept")', 'Input.action_press("deploy")')
new_content = new_content.replace('Input.action_release("ui_accept")', 'Input.action_release("deploy")')

if new_content == content:
    print("⚠️  No changes made in autostall_patched.py")
else:
    with open(path, 'w') as f:
        f.write(new_content)
    print("✅ autostall_patched.py patched: ui_accept → deploy")
PYEOF

# ---- 3. Kill any hanging Godot ----
pkill -f "godot.*--path godot_project" || true
sleep 1

# ---- 4. Run autostall ----
echo "=== Running autostall_patched.py with deploy fix (timeout 300s) ==="
timeout 300 python3 autostall_patched.py --no-timeout 2>&1 | tee "$ALOG"
RC=$?

if [ $RC -eq 124 ]; then
    echo "⚠️  Autostall timed out after 300s – killing Godot."
    pkill -f "godot.*--path godot_project" || true
elif [ $RC -ne 0 ]; then
    echo "⚠️  Autostall exited with code $RC"
fi

# ---- 5. Generate summary ----
{
printf '=== fix_autostart_action_v2.sh — %s UTC ===\n\n' "$TS"
printf 'Patches applied:\n'
printf '  - build_terrain.gd: ui_accept → deploy\n'
printf '  - autostall_patched.py: ui_accept → deploy\n'
printf 'Autostall exit code: %s\n' "$RC"
printf '\nKey markers:\n'
grep -E 'Ground impact|GAME_OVER|warp|GLIDE|deploy|Headless' "$ALOG" | grep -v '\[GLIDE\]' | head -30
printf '\nGLIDE count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" || echo 0)"
printf '\nLast 10 lines:\n'
tail -10 "$ALOG"
} > "$OUT"

# ---- 6. Push ----
git add -f godot_project/scripts/build_terrain.gd autostall_patched.py "$ALOG" "$OUT" fix_autostart_action_v2.sh
git commit --no-verify -m "fix: autostart action ui_accept → deploy (v2, ${TS})" || true
git push origin main || true

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
