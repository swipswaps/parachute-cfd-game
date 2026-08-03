#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fixed_full_${TS}.txt"

{
printf '=== run_fixed_full.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. File inventory ===\n'
ls -lh autostall_fixed.py autostall_patched.py
wc -l autostall_fixed.py autostall_patched.py

printf '\n=== 2. autostall_fixed.py key logic ===\n'
grep -n 'game_completed\|Ground impact\|timeout\|no.timeout\|STALL\|Game completed\|--timeout\|--no-timeout' \
    autostall_fixed.py | head -30

printf '\n=== 3. Full run with autostall_fixed.py (no timeout) ===\n'
python3 autostall_fixed.py --no-timeout 2>&1

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" run_fixed_full.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: autostall_fixed full run (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
