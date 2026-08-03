#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_pausetel_${TS}.txt"

{
printf '=== diag_pausetel.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. toggle_pause function (full body) ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys
text = open(sys.argv[1]).read()
lines = text.split("\n")
# Find func toggle_pause
start = None
for i, ln in enumerate(lines):
    if ln.strip().startswith("func toggle_pause"):
        start = i
        break
if start is None:
    print("ERROR: func toggle_pause not found")
    sys.exit(1)
# Extract until next func at same indent level
end = start + 1
while end < len(lines):
    ln = lines[end]
    if ln.startswith("func ") and end > start:
        break
    end += 1
for i in range(start, end):
    print(f"{i+1:4d}: {lines[i]}")
PYEOF

printf '\n=== 2. PAUSETEL selftest function (full body) ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys
text = open(sys.argv[1]).read()
lines = text.split("\n")
start = None
for i, ln in enumerate(lines):
    if "PAUSETEL" in ln and "selftest" in ln.lower() and ln.strip().startswith("func"):
        start = i
        break
    # Also check for a function that contains PAUSETEL
if start is None:
    # Find the first line containing PAUSETEL selftest in any function
    for i, ln in enumerate(lines):
        if "PAUSETEL" in ln and "selftest" in ln and "BEGIN" in ln:
            # Walk back to find func
            for j in range(i, -1, -1):
                if lines[j].startswith("func "):
                    start = j
                    break
            break
if start is None:
    print("ERROR: PAUSETEL selftest function not found")
    sys.exit(1)
end = start + 1
while end < len(lines):
    ln = lines[end]
    if ln.startswith("func ") and end > start:
        break
    end += 1
for i in range(start, end):
    print(f"{i+1:4d}: {lines[i]}")
PYEOF

printf '\n=== 3. Line 553 context (±5 lines) ===\n'
awk 'NR>=548 && NR<=558 {printf "%4d: %s\n", NR, $0}' "$TARGET"

printf '\n=== 4. PauseMenu references in build_terrain.gd ===\n'
grep -n 'PauseMenu\|pause_menu\|pause_overlay' "$TARGET" | head -30

printf '\n=== 5. PauseMenu node in main.tscn ===\n'
grep -n 'PauseMenu\|pause_menu' godot_project/scenes/main.tscn | head -20 || printf '(none found)\n'

printf '\n=== 6. naip_texture.png actual location ===\n'
find godot_project -name 'naip_texture*' -o -name 'NAIP*' 2>/dev/null | head -20
find . -maxdepth 3 -name '*.png' | grep -i naip | head -10

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_pausetel.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: pausetel selftest context (${TS})" && \
    git push origin main && \
    git ls-remote origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
