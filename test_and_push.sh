#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fullrun_${TS}.txt"

{
printf '=== fullrun.sh — %s UTC ===\n\n' "$TS"

printf '=== autostall_fixed.py full run ===\n'
python3 autostall_fixed.py --no-timeout

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

printf '\n=== CI markers ===\n'
grep -E 'Game completed|Ground impact|Runtime:|STALL|game_completed' "$OUT" | tail -20
printf 'GLIDE rows: %s\n' "$(grep -c '\[GLIDE\],' "$OUT" || echo 0)"
tail -5 "$OUT"

git add -f "$OUT" test_and_push.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "test: autostall_fixed full run (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
