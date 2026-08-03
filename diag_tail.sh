#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
ALOG="notes/autostall_pausetel_20260803100311.txt"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_tail_${TS}.txt"

{
printf '=== diag_tail.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. Game completed context (±5 lines) ===\n'
grep -n -A5 -B5 'Game completed' "$ALOG" | head -40 || printf '(not found)\n'

printf '\n=== 2. Last 80 lines of autostall log ===\n'
tail -80 "$ALOG"

printf '\n=== 3. Does autostall_patched.py set GODOT_HEADLESS? ===\n'
grep -n 'GODOT_HEADLESS' autostall_patched.py | head -10 || printf '(none)\n'

printf '\n=== 4. Landing / Game completed logic in build_terrain.gd ===\n'
grep -n 'Game completed\|game_completed\|LANDED\|_check_landing\|landing_check' "$TARGET" | head -20

printf '\n=== 5. Terrain texture info ===\n'
file godot_project/assets/terrain/naip_texture.png
identify godot_project/assets/terrain/naip_texture.png 2>/dev/null || printf '(imagemagick not available)\n'
python3 -c "
from PIL import Image
im = Image.open('godot_project/assets/terrain/naip_texture.png')
print(f'PIL: mode={im.mode} size={im.size}')
" 2>/dev/null || printf '(PIL not available)\n'
ls -lh godot_project/assets/terrain/naip_texture.png

printf '\n=== 6. Camera distance constant in build_terrain.gd ===\n'
grep -n 'plane_camera_distance\|300\|camera.*dist\|dist.*camera' "$TARGET" | grep -v '^\s*#' | head -10

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_tail.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: tail + landing + terrain + camera (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
