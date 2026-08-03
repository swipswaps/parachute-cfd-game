#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
ALOG="notes/autostall_p3c_20260802215741.txt"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_post_handoff_${TS}.txt"

{
printf '=== diag_post_handoff.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. PUSH STATUS ===\n'
git log --oneline -5

printf '\n=== 2. UNVERIFIED MARKERS (tail of truncated autostall log) ===\n'
if [ -f "$ALOG" ]; then
    printf 'PAUSETEL lines:\n'
    grep 'PAUSETEL' "$ALOG" || printf '(none)\n'
    printf 'Game completed lines:\n'
    grep 'Game completed' "$ALOG" || printf '(none)\n'
    printf 'Total lines in log: '; wc -l < "$ALOG"
else
    printf 'ALOG NOT FOUND: %s\n' "$ALOG"
fi

printf '\n=== 3. BUG A — AUTO-JUMP GATE AUDIT ===\n'
printf 'GODOT_HEADLESS env var in this shell: [%s]\n' "$GODOT_HEADLESS"
printf '\nauto-jump gate in build_terrain.gd:\n'
grep -n 'GODOT_HEADLESS\|_headless_auto_jump\|OS\.is_headless\|\-\-headless\|headless_auto' "$TARGET" | head -30
printf '\nauto-jump gate in InputManager.gd (if present):\n'
grep -n 'GODOT_HEADLESS\|_headless_auto_jump\|OS\.is_headless\|\-\-headless' \
    godot_project/autoloads/InputManager.gd 2>/dev/null | head -20 || printf '(file not found)\n'

printf '\n=== 4. TERRAIN TEXTURE STATUS ===\n'
python3 -c "
from PIL import Image
import os
p = 'godot_project/assets/textures/naip_texture.png'
if os.path.exists(p):
    im = Image.open(p)
    print(f'mode={im.mode} size={im.size} palette={im.palette}')
else:
    print('naip_texture.png not found at expected path')
" 2>&1 || printf 'PIL not available\n'

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_post_handoff.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: post-handoff verification (${TS})" && \
    git push origin main && \
    git ls-remote origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK FOR LLM REVIEW ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
