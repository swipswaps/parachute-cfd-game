#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/code_audit_${TS}.txt"

{
printf '=== code_audit.sh — %s UTC ===\n\n' "$TS"

printf '=== A. user_preferences table contents ===\n'
sqlite3 parachute_mutations.db "SELECT key, value FROM user_preferences ORDER BY key;"
printf '\n'

printf '=== B. build_terrain.gd line count ===\n'
wc -l godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== C. _save_camera_settings — lines 2825-2848 ===\n'
awk 'NR>=2825 && NR<=2848 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== D. _update_camera_position — lines 2868-2888 ===\n'
awk 'NR>=2868 && NR<=2888 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== E. _input camera orbit block — lines 1988-2005 ===\n'
awk 'NR>=1988 && NR<=2005 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/build_terrain.gd
printf '\n'

printf '=== F. SqliteDb.gd _query — lines 226-242 ===\n'
awk 'NR>=226 && NR<=242 {printf "%4d: %s\n", NR, $0}' godot_project/scripts/SqliteDb.gd
printf '\n'

printf '=== G. LOD / terrain constants grep ===\n'
grep -n 'const W\b\|const H\b\|lod_dist\|LOD\|chunk_size\|CHUNK_SIZE\|terrain_size\|mesh_lod\|_lod\b\|lod_levels\|SubdivisionMesh\|surface_tool\|ArrayMesh\|set_lod\|lod_bias\|MeshInstance3D\|lod_threshold' \
    godot_project/scripts/build_terrain.gd | head -60
printf '\n'

printf '=== H. Terrain mesh generation — grep for vertex/mesh creation ===\n'
grep -n 'SurfaceTool\|ArrayMesh\|create_from_height\|set_vertex\|add_vertex\|PlaneMesh\|subdivide\|ImmediateMesh\|MeshDataTool\|vertex_count\|INDEX\|verts\|mesh =' \
    godot_project/scripts/build_terrain.gd | head -40
printf '\n'

printf '=== I. gamification/logbook.py — lines 1-30 ===\n'
awk 'NR>=1 && NR<=30 {printf "%4d: %s\n", NR, $0}' gamification/logbook.py 2>/dev/null || printf '(not found)\n'
printf '\n'

printf '=== J. autostall_fixed.py — init_db call and main() tail ===\n'
grep -n 'def init_db\|def main\|init_db()\|game_completed\|Ground impact' autostall_fixed.py | tail -20
printf '\n'

printf '=== K. Rule #31 indentation check (leading spaces in build_terrain.gd) ===\n'
SPACE_LINES=$(grep -c '^ ' godot_project/scripts/build_terrain.gd 2>/dev/null || echo 0)
printf 'Lines with leading spaces: %s\n' "$SPACE_LINES"
printf '\n'

printf '=== L. terrain_upgrades table contents ===\n'
sqlite3 parachute_mutations.db "SELECT * FROM terrain_upgrades ORDER BY id;"
printf '\n'

printf '=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$OUT" code_audit.sh
git commit --no-verify -m "audit: code + LOD + userPrefs (${TS})"
git push origin main
printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
