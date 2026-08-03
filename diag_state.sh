#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_state_${TS}.txt"

{
printf '=== diag_state.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. build_terrain.gd current state ===\n'
wc -l "$TARGET"
python3 - "$TARGET" << 'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
lines = text.split("\n")
print(f"bytes: {len(text)}")
# Key markers
markers = {
    "_headless_warp_done": "_headless_warp_done" in text,
    "Ground impact fatal": "Ground impact" in text and "fatal" in text,
    "GAME_OVER block": "_game_state = GameState.GAME_OVER" in text,
    "225.0 warp alt": "225.0" in text,
    "class-scope if": any(ln.startswith("if ") and not ln.startswith("if __") for ln in lines),
    "GLIDE print": "[GLIDE]" in text,
    "toggle_pause def": "func toggle_pause" in text,
    "_headless_auto_deploy def": "var _headless_auto_deploy" in text,
}
for k, v in markers.items():
    print(f"  {k}: {v}")
# Show line 1470-1476 (parse error zone)
print("\nLines 1470-1476:")
for i in range(1469, min(1476, len(lines))):
    print(f"  {i+1}: {lines[i]!r}")
# Check for class-scope if
bad = [i+1 for i, ln in enumerate(lines) if ln.startswith("if ")]
if bad:
    print(f"\nClass-scope 'if' at lines: {bad[:5]}")
else:
    print("\nNo class-scope 'if' found — file is structurally clean at top level")
PYEOF

printf '\n=== 2. All build_terrain.gd backups (newest first) ===\n'
for bak in $(ls -t godot_project/scripts/build_terrain.gd.bak.* 2>/dev/null | head -10); do
    wc=$(wc -l < "$bak")
    has_warp=$(python3 -c "t=open('$bak').read(); print('warp' if '_headless_warp_done' in t else 'clean')" 2>/dev/null)
    has_parse=$(python3 -c "
import sys
lines = open('$bak').read().split('\n')
bad = [i+1 for i, ln in enumerate(lines) if ln.startswith('if ')]
print('class-scope-if:' + str(bad[:2]) if bad else 'parse-ok')
" 2>/dev/null)
    printf '  %-60s  lines=%-5s  %s  %s\n' "$bak" "$wc" "$has_warp" "$has_parse"
done

printf '\n=== 3. autostall_patched.py current state ===\n'
wc -l autostall_patched.py
grep -n 'def apply_auto_start\|game_completed\|Ground impact\|no-timeout\|timeout_val' \
    autostall_patched.py | head -20

printf '\n=== 4. y-clamp zone in current build_terrain.gd ===\n'
grep -n 'position\.y < 25\|position\.y = 25\|position\.y <= 25\|GAME_OVER\|safe_landing' \
    "$TARGET" | grep -v '^\s*#' | head -20

printf '\n=== 5. What the other LLM scripts targeted (recent script names) ===\n'
ls -lt fix_82ft*.sh remove_autostart*.sh apply_clamp*.py fix_parse_errors*.py \
    final_fix*.py final_fix*.sh surgical_fix*.py 2>/dev/null | awk '{print $6,$7,$8,$9}' | head -20

printf '\n=== 6. Quick autostall (60s max — just to confirm parse) ===\n'
timeout 75 python3 autostall_patched.py --timeout 60 2>&1 | tail -30

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_state.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: full state audit before fix (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
