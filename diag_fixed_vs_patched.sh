#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/diag_fixed_vs_patched_${TS}.txt"

{
printf '=== diag_fixed_vs_patched.sh — %s UTC ===\n\n' "$TS"

# ── 1. What is autostall_fixed.py? ─────────────────────────────────────────
printf '=== 1. autostall_fixed.py head (first 60 lines) ===\n'
head -60 autostall_fixed.py

printf '\n=== 2. autostall_fixed.py game_completed and timeout logic ===\n'
grep -n 'game_completed\|timeout\|Ground impact\|no.timeout\|STALL\|GLIDE\|Game completed' \
    autostall_fixed.py | head -20

printf '\n=== 3. Key differences from autostall_patched.py ===\n'
printf 'Line counts:\n'
wc -l autostall_fixed.py autostall_patched.py
printf '\nDiff summary (autostall_fixed vs autostall_patched):\n'
diff <(grep -n 'def \|game_completed\|Ground impact\|timeout' autostall_fixed.py) \
     <(grep -n 'def \|game_completed\|Ground impact\|timeout' autostall_patched.py) | head -30

# ── 4. Last autostall CI run markers ───────────────────────────────────────
printf '\n=== 4. Most recent autostall CI log (tail) ===\n'
LATEST_ALOG=$(ls -t notes/autostall_82ft_*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_ALOG" ]; then
    printf 'Log: %s\n' "$LATEST_ALOG"
    printf 'Game completed: '; grep 'Game completed' "$LATEST_ALOG" || printf '(not found)\n'
    printf 'Runtime: '; grep 'Runtime:' "$LATEST_ALOG" || printf '(not found)\n'
    printf 'GLIDE rows: %s\n' "$(grep -c '\[GLIDE\],' "$LATEST_ALOG" || echo 0)"
    printf 'Ground impact: '; grep 'Ground impact' "$LATEST_ALOG" | head -3 || printf '(not found)\n'
    printf 'Last 10 lines:\n'; tail -10 "$LATEST_ALOG"
else
    printf '(no autostall_82ft log found)\n'
fi

# ── 5. Quick autostall run with autostall_fixed.py ───────────────────────
printf '\n=== 5. autostall_fixed.py quick test (30s timeout) ===\n'
FLOG="notes/autostall_fixed_test_${TS}.txt"
python3 autostall_fixed.py --timeout 30 2>&1 | tee "$FLOG"
printf '\nautostall_fixed.py markers:\n'
grep -E 'Game completed|Runtime|Ground impact|GLIDE_HDR|Parse Error' "$FLOG" \
    | grep -v '\[GLIDE\],' | head -10
printf 'GLIDE rows: %s\n' "$(grep -c '\[GLIDE\],' "$FLOG" || echo 0)"

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" "$FLOG" diag_fixed_vs_patched.sh 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "diag: autostall_fixed vs patched comparison (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
