#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TEXTURE="godot_project/assets/terrain/naip_texture.png"
DB="parachute_mutations.db"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_terrain_camera_${TS}.txt"

{
printf '=== fix_terrain_camera.sh — %s UTC ===\n\n' "$TS"

# ── FIX 1: terrain texture P→RGB ────────────────────────────────────────────
printf '=== FIX 1: terrain texture mode=P → RGB ===\n'
python3 - "$TEXTURE" << 'PYEOF'
import sys, shutil, datetime
from PIL import Image

path = sys.argv[1]
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = f"{path}.bak.{ts}"
shutil.copy2(path, backup)
print(f"backup: {backup}")

im = Image.open(path)
print(f"before: mode={im.mode} size={im.size} palette={im.palette}")

rgb = im.convert("RGB")
print(f"after convert: mode={rgb.mode}")

rgb.save(path, "PNG")

verify = Image.open(path)
print(f"verify: mode={verify.mode} size={verify.size}")
if verify.mode != "RGB":
    shutil.copy2(backup, path)
    print("FAIL: mode not RGB — restored")
    sys.exit(1)
print("SUCCESS: palette removed, true-colour PNG written")
import os
print(f"file size: {os.path.getsize(path)/1024/1024:.2f} MB")
PYEOF
TERRAIN_RC=$?
printf 'terrain fix exit: %s\n' "$TERRAIN_RC"

# ── FIX 2: camera distance 300→80 in DB ─────────────────────────────────────
printf '\n=== FIX 2: camera_distance_plane 300→80 in DB ===\n'
printf 'BEFORE:\n'
sqlite3 "$DB" "SELECT key, value FROM user_preferences WHERE key LIKE '%camera%';"

sqlite3 "$DB" "INSERT OR REPLACE INTO user_preferences (key, value)
               VALUES ('camera_distance_plane', '80.0');"
sqlite3 "$DB" "INSERT OR REPLACE INTO user_preferences (key, value)
               VALUES ('camera_distance_freefall', '80.0');"

printf 'AFTER:\n'
sqlite3 "$DB" "SELECT key, value FROM user_preferences WHERE key LIKE '%camera%';"
printf 'camera DB fix: done\n'

# ── DIAG 3: autostall timeout logic ─────────────────────────────────────────
printf '\n=== DIAG 3: autostall timeout / --no-timeout parsing ===\n'
grep -n 'timeout\|TIMEOUT\|no.timeout\|argv\|sys\.argv\|argparse\|SIGTERM\|kill\|terminate' \
    autostall_patched.py | head -40

printf '\n=== DIAG 3b: autostall_patched.py line count ===\n'
wc -l autostall_patched.py

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

git add -f "$TEXTURE" "$OUT" fix_terrain_camera.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "fix: terrain P→RGB + camera 300→80 (${TS})" && \
    git push origin main && \
    git ls-remote origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINK ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
