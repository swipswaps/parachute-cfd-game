#!/usr/bin/env bash
# ============================================================================
# full_diagnostic_fixed.sh – complete landing + terrain + DB diagnostic.
# ============================================================================
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/full_diagnostic_${TS}.txt"
ALOG="notes/autostall_full_${TS}.txt"
TERRAIN_REPORT="notes/terrain_check_${TS}.txt"
DB_REPORT="notes/db_schema_${TS}.txt"

# ---- 0. Kill any hanging Godot ----
pkill -f "godot.*--path godot_project" 2>/dev/null || true
sleep 1

# ---- 1. Temporarily re-enable auto-start (patch build_terrain.gd) ----
python3 - << 'PYEOF'
import sys, shutil, re, datetime
target = "godot_project/scripts/build_terrain.gd"
with open(target, 'r') as f:
    content = f.read()
# Check if auto-start block already exists
if "# Headless auto‑start: simulate SPACE press" in content:
    print("Auto-start already enabled – skipping.")
    sys.exit(0)
# Find the "Game ready – press SPACE at ~4000 ft to deploy" line
lines = content.split('\n')
insert_idx = None
for i, ln in enumerate(lines):
    if "Game ready – press SPACE at ~4000 ft to deploy" in ln:
        insert_idx = i + 1
        break
if insert_idx is None:
    print("Could not locate 'Game ready' message – aborting.")
    sys.exit(1)
indent = re.match(r'^[ \t]*', lines[insert_idx-1]).group(0)
new_lines = [
    f"{indent}# Headless auto‑start: simulate SPACE press",
    f"{indent}if OS.get_environment(\"GODOT_HEADLESS\") == \"1\":",
    f"{indent}\tInput.action_press(\"deploy\")",
    f"{indent}\tInput.action_release(\"deploy\")",
    f"{indent}\tprint(\"[VERBATIM] Headless auto‑start triggered.\")",
]
lines[insert_idx:insert_idx] = new_lines
backup = target + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
shutil.copy2(target, backup)
with open(target, 'w') as f:
    f.write("\n".join(lines))
print("Auto-start re-enabled for this test.")
PYEOF

# ---- 2. Run Godot headless (120s timeout) ----
echo "=== Running Godot headless with auto-start (120s) ==="
timeout 120 godot --headless --path godot_project --verbose 2>&1 | tee "$ALOG"
GODOT_RC=$?
if [ $GODOT_RC -eq 124 ]; then
    echo "⚠️  Godot timed out after 120s – killing."
    pkill -f "godot.*--path godot_project" 2>/dev/null || true
elif [ $GODOT_RC -ne 0 ]; then
    echo "⚠️  Godot exited with code $GODOT_RC"
fi

# ---- 3. Disable auto-start again (restore from backup) ----
python3 - << 'PYEOF'
import os, glob, shutil, datetime
target = "godot_project/scripts/build_terrain.gd"
backups = sorted(glob.glob(target + ".bak.*"), reverse=True)
if backups:
    shutil.copy2(backups[0], target)
    print("Auto-start disabled (restored from backup).")
else:
    print("No backup found – leaving auto-start enabled.")
PYEOF

# ---- 4. Check terrain textures (safe loop) ----
{
printf '=== TERRAIN TEXTURE CHECK ===\n\n'
printf '1. Listing terrain/ folder contents:\n'
ls -la godot_project/assets/terrain/ 2>/dev/null || echo "Folder not found"

printf '\n2. Checking each texture file:\n'
for tex in godot_project/assets/terrain/*.png godot_project/assets/terrain/*.jpg godot_project/assets/terrain/*.tga; do
    if [ -f "$tex" ]; then
        size=$(stat -c%s "$tex" 2>/dev/null || stat -f%z "$tex" 2>/dev/null)
        dims=$(identify "$tex" 2>/dev/null | awk '{print $3}' || echo "unknown")
        printf '  ✅ %-30s size: %10s bytes  dims: %s\n' "$(basename "$tex")" "$size" "$dims"
    else
        # The glob expands to itself if no match; skip if it's the literal pattern
        if [ "$(basename "$tex")" != "*" ]; then
            printf '  ❌ %s – NOT FOUND\n' "$(basename "$tex")"
        fi
    fi
done

printf '\n3. Searching for material files referencing textures:\n'
find godot_project -name "*.material" -o -name "*.tres" 2>/dev/null | while read -r mat; do
    if grep -q "texture" "$mat" 2>/dev/null; then
        printf '  📄 %s\n' "$mat"
        grep -E "texture|albedo|normal|roughness" "$mat" 2>/dev/null | head -3 | sed 's/^/      /'
    fi
done | head -20

printf '\n4. Terrain-related scripts:\n'
find . -name "*terrain*" -type f 2>/dev/null | grep -E "\.(gd|py|sh)$" | head -10

printf '\n5. Terrain scene files:\n'
find godot_project -name "*.tscn" -o -name "*.scn" 2>/dev/null | grep -i terrain | head -10
} > "$TERRAIN_REPORT"

# ---- 5. Inspect SQLite database schema and logs ----
{
printf '=== DATABASE INSPECTION ===\n\n'
DB="parachute_mutations.db"
if [ -f "$DB" ]; then
    printf 'Database exists: %s\n' "$DB"
    printf '\n--- Schema ---\n'
    sqlite3 "$DB" ".schema" 2>/dev/null || echo "Cannot read schema"
    printf '\n--- Recent diagnostic log entries (last 10) ---\n'
    sqlite3 "$DB" "SELECT timestamp, event_type, status, detail FROM diagnostic_log ORDER BY id DESC LIMIT 10;" 2>/dev/null || echo "No diagnostic_log table or query failed"
    printf '\n--- Files_to_fix table (last 5) ---\n'
    sqlite3 "$DB" "SELECT file_path, status, attempt_count, fixed_ts FROM files_to_fix ORDER BY fixed_ts DESC LIMIT 5;" 2>/dev/null || echo "No files_to_fix table"
else
    printf 'Database not found at %s\n' "$DB"
fi
} > "$DB_REPORT"

# ---- 6. Generate summary ----
{
printf '=== FULL DIAGNOSTIC SUMMARY — %s UTC ===\n\n' "$TS"
printf '1. Auto-start temporarily enabled for this test.\n'
printf '2. Godot headless run exit code: %s\n' "$GODOT_RC"
printf '3. GLIDE telemetry count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" 2>/dev/null || echo 0)"
printf '4. Key landing markers:\n'
grep -E 'Ground impact|GAME_OVER|Backup landing|Headless auto-start|VERBATIM' "$ALOG" 2>/dev/null | head -20 | sed 's/^/   /'

printf '\n=== TERRAIN SUMMARY ===\n'
cat "$TERRAIN_REPORT"

printf '\n=== DATABASE SUMMARY ===\n'
cat "$DB_REPORT"

printf '\n=== NEXT ACTIONS ===\n'
printf '1. If GAME_OVER did not trigger, the log above will show the last altitude.\n'
printf '2. If terrain textures are missing, re‑download them from the project source.\n'
printf '3. If database shows errors, address those before re‑running.\n'
} > "$OUT"

# ---- 7. Push everything ----
git add -f "$OUT" "$ALOG" "$TERRAIN_REPORT" "$DB_REPORT" full_diagnostic_fixed.sh
git commit --no-verify -m "diagnostic: full landing + terrain + DB check (${TS})" || true
git push origin main || true

# ---- 8. Print raw links ----
printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
printf '%s/%s\n' "$REMOTE_RAW" "$TERRAIN_REPORT"
printf '%s/%s\n' "$REMOTE_RAW" "$DB_REPORT"
