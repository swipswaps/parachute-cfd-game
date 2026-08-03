#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
FHUD="godot_project/scripts/forensic_hud.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_landing_hud_${TS}.txt"

{
printf '=== diag_landing_hud.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. LANDED transition (lines 1140-1210) ===\n'
awk 'NR>=1140 && NR<=1210 {printf "%4d: %s\n", NR, $0}' "$TARGET"

printf '\n=== 2. OPENING_ANIM physics branch — position/altitude update ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().split("\n")
# Find the OPENING_ANIM (state=2) block in _physics_process
in_phys = False
in_opening = False
depth = 0
for i, ln in enumerate(lines):
    if "func _physics_process" in ln:
        in_phys = True
    if in_phys and ("OPENING_ANIM" in ln or "state == GameState.OPENING" in ln or "state == 2" in ln):
        in_opening = True
        start = i
    if in_opening:
        print(f"{i+1:4d}: {ln}")
        if i > start + 80:
            break
PYEOF

printf '\n=== 3. What stops descent — ground/altitude clamp search ===\n'
grep -n 'ground\|floor\|clamp\|max.*y\|position\.y\|AGL\|altitude.*25\|25\.0\|82' "$TARGET" \
    | grep -v '^\s*#' | head -30

printf '\n=== 4. forensic_hud.gd — HTTP polling / timer / request code ===\n'
if [ -f "$FHUD" ]; then
    grep -n 'Timer\|timer\|HTTPRequest\|http\|request\|_poll\|timeout\|_on_.*complet\|status\|hub_url\|api' \
        "$FHUD" | head -50
else
    printf 'forensic_hud.gd not found at %s\n' "$FHUD"
    find godot_project -name 'forensic_hud.gd' | head -5
fi

printf '\n=== 5. forensic_hub_server.py running? ===\n'
ps aux | grep forensic_hub | grep -v grep || printf '(not running)\n'
curl -s --max-time 2 http://127.0.0.1:8765/api/stats | head -5 || printf '(connection refused or timeout)\n'

printf '\n=== 6. autostall proc.terminate() context (lines 585-600, 638-650) ===\n'
awk 'NR>=585 && NR<=655 {printf "%4d: %s\n", NR, $0}' autostall_patched.py

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" diag_landing_hud.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: landing transition + forensic hud + autostall (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
