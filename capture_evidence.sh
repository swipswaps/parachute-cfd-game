#!/usr/bin/env bash
# ============================================================================
# capture_evidence.sh – capture offending lines with visible whitespace, push.
# ============================================================================
set -u
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
EVIDENCE="notes/offending_lines_${TS}.txt"

{
printf '=== OFFENDING LINES (with visible whitespace) — %s UTC ===\n\n' "$TS"

printf '--- HubManager.gd lines 25-35 ---\n'
python3 -c "
with open('godot_project/scripts/HubManager.gd', 'r') as f:
    lines = f.readlines()
for i in range(24, min(35, len(lines))):
    print(f\"{i+1:4d}: {repr(lines[i])}\")
"

printf '\n--- build_terrain.gd lines 3848-3860 ---\n'
python3 -c "
with open('godot_project/scripts/build_terrain.gd', 'r') as f:
    lines = f.readlines()
for i in range(3847, min(3860, len(lines))):
    print(f\"{i+1:4d}: {repr(lines[i])}\")
"

printf '\n--- Full HubManager.gd first 35 lines ---\n'
head -35 godot_project/scripts/HubManager.gd | cat -n

printf '\n--- Full build_terrain.gd last 30 lines ---\n'
tail -30 godot_project/scripts/build_terrain.gd | cat -n
} > "$EVIDENCE"

git add -f "$EVIDENCE" capture_evidence.sh
git commit --no-verify -m "evidence: offending lines with visible whitespace (${TS})" || true
git push origin main || true

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$EVIDENCE"
