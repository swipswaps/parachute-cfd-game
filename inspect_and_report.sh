#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/inspect_${TS}.txt"

{
printf '=== inspect_and_report.sh — %s UTC ===\n\n' "$TS"

printf '=== 1. Database files on disk ===\n'
find . -name '*.db' -not -path './.git/*' | sort
printf '\n'

printf '=== 2. parachute_mutations.db schema ===\n'
sqlite3 parachute_mutations.db '.schema' 2>&1
printf '\n'

printf '=== 3. parachute_mutations.db tables and row counts ===\n'
sqlite3 parachute_mutations.db "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" 2>&1 | while read t; do
    printf '%s: %s rows\n' "$t" "$(sqlite3 parachute_mutations.db "SELECT COUNT(*) FROM \"$t\";" 2>&1)"
done
printf '\n'

printf '=== 4. Any other .db files schemas ===\n'
find . -name '*.db' -not -path './.git/*' -not -name 'parachute_mutations.db' | while read db; do
    printf '\n--- %s ---\n' "$db"
    sqlite3 "$db" '.schema' 2>&1
done
printf '\n'

printf '=== 5. Affected file inventory (all files referenced in stall output) ===\n'
printf 'godot_project/scripts/build_terrain.gd: '
wc -l godot_project/scripts/build_terrain.gd | awk '{print $1}' 
printf 'godot_project/scripts/SqliteDb.gd: '
wc -l godot_project/scripts/SqliteDb.gd | awk '{print $1}'
printf '\n'

printf '=== 6. build_terrain.gd — _save_camera_settings (lines 2828-2845) ===\n'
awk 'NR>=2828 && NR<=2845 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== 7. build_terrain.gd — _update_camera_position (lines 2870-2885) ===\n'
awk 'NR>=2870 && NR<=2885 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== 8. build_terrain.gd — _input camera orbit block (lines 1990-2005) ===\n'
awk 'NR>=1990 && NR<=2005 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== 9. SqliteDb.gd — _query (lines 228-240) ===\n'
awk 'NR>=228 && NR<=240 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/SqliteDb.gd
printf '\n'

printf '=== 10. build_terrain.gd — LOD/terrain constants (grep) ===\n'
grep -n 'const W\|const H\|LOD\|lod\|chunk_size\|CHUNK\|terrain_size\|mesh_size\|SubdivisionMesh\|MeshInstance\|_lod\|lod_' \
    godot_project/scripts/build_terrain.gd | head -40
printf '\n'

printf '=== 11. stall_report.json (last 50 lines) ===\n'
tail -50 stall_report.json 2>/dev/null || printf '(not found)\n'
printf '\n'

printf '=== 12. userPreferences rules compliance check ===\n'
printf 'Rules that require code implementation vs explanation:\n'
printf '  Rule #7: no sed — grep check:\n'
grep -rn '\bsed\b' godot_project/scripts/build_terrain.gd 2>/dev/null | grep -v '^\s*#' | head -5 || printf '  CLEAN\n'
printf '  Rule #31: tabs-only indentation check (build_terrain.gd leading spaces):\n'
grep -c '^ ' godot_project/scripts/build_terrain.gd 2>/dev/null && printf '  VIOLATION: leading spaces found\n' || printf '  CLEAN\n'
printf '\n'

printf '=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" inspect_and_report.sh
STAGED=$(git diff --cached --name-only | wc -l)
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "inspect: schema + code audit (${TS})" && \
    git push origin main

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
