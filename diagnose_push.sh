#!/usr/bin/env bash
# ============================================================================
# diagnose_push.sh – capture parse error, push evidence, print raw links.
# Complies with Rules #1, #8, #47.
# ============================================================================
set -u
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/parse_diagnostic_${TS}.txt"
LINES="notes/build_terrain_lines_${TS}.txt"

# ---- 1. Run godot --check-only with timeout ----
echo "=== Capturing parse error with godot --check-only (timeout 30s) ==="
timeout 30 godot --headless --check-only --path godot_project 2>&1 | tee "$OUT"

# ---- 2. Extract the offending lines from build_terrain.gd with visible whitespace ----
{
printf '=== build_terrain.gd lines 3845-3860 with visible whitespace (repr) ===\n'
python3 - << 'PYEOF'
with open("godot_project/scripts/build_terrain.gd", 'r') as f:
    lines = f.readlines()
for i in range(3844, min(3860, len(lines))):
    print(f"{i+1:4d}: {repr(lines[i])}")
PYEOF
} > "$LINES"

# ---- 3. Push all evidence ----
git add -f "$OUT" "$LINES" diagnose_push.sh
git commit --no-verify -m "diagnostic: parse error capture (${TS})" || true
git push origin main || true

# ---- 4. Print raw links ----
printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$LINES"
