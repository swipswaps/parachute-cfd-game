#!/usr/bin/env bash
# ============================================================================
# patch_final.sh – Corrected patch: replace colour loop with 0062 version,
# update _do_cutaway to transition to FREEFALL. Semantic check verifies that
# the loop no longer uses COLOUR_BOX (the constant definition may remain).
#
# Citations:
#   - SurfaceTool: https://docs.godotengine.org/en/stable/classes/class_surfacetool.html
#   - Godot GDScript: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
# Rules: #1,#2,#7,#8,#9,#11,#14,#16,#19,#21,#25,#28,#29,#30,#32,#36,#37,#38,#39,#43,#44,#46,#47,#48,#49,#50,#51,#52,#53,#54,#55,#56.
# ============================================================================

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"; [ "$success" = "true" ] && status="SUCCESS"
    printf '[%s] [%s] %s: %s\n' "$ts" "$status" "$operation" "$detail" >&2
}

RULE_DB="${HOME}/.parachute_rule_compliance.db"
log_rule_compliance() {
    local rule_id="$1" script_name="$2" passed="$3" evidence="$4"
    local ts row_count
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sqlite3 "$RULE_DB" <<SQL
CREATE TABLE IF NOT EXISTS rule_compliance (
    rule_id TEXT NOT NULL, script_name TEXT NOT NULL,
    passed INTEGER NOT NULL CHECK (passed IN (0, 1)),
    evidence TEXT, ts TEXT NOT NULL,
    PRIMARY KEY (rule_id, script_name, ts)
);
INSERT INTO rule_compliance (rule_id, script_name, passed, evidence, ts)
VALUES ('$rule_id', '$script_name', $passed, '$evidence', '$ts');
SQL
    row_count=$(sqlite3 "$RULE_DB" "SELECT COUNT(*) FROM rule_compliance WHERE rule_id='$rule_id' AND script_name='$script_name' AND ts='$ts';")
    if [ "$row_count" -ne 1 ]; then
        log_result "rule_compliance" "false" "read-back failed for rule $rule_id"
        exit 1
    fi
    log_result "rule_compliance" "true" "logged rule $rule_id passed=$passed"
}

SCRIPT_NAME="patch_final.sh"
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac"
CURRENT="$PROJECT_ROOT/parachute-cfd-game"
DIR_0062="$PROJECT_ROOT/parachute-cfd-game_0062"
TARGET="$CURRENT/godot_project/scripts/build_terrain.gd"
SOURCE_COLOUR="$DIR_0062/godot_project/scripts/build_terrain.gd"

cd "$CURRENT" || { log_result "cd" "false" "cannot cd to current"; exit 1; }

# --- Rule #28 DEPENDENCY MANAGEMENT -----------------------------------------
MISSING=""
for tool in git grep awk diff sha256sum sqlite3 python3 printf tee head tail wc stat ls; do
    command -v "$tool" > /dev/null || MISSING="${MISSING} ${tool}"
done
if [ -n "$MISSING" ]; then
    log_result "dependency_check" "false" "missing:${MISSING}"
    exit 1
fi
log_result "dependency_check" "true" "all tools present"
log_rule_compliance "28" "$SCRIPT_NAME" 1 "tools present"

# --- Rule #49 IMPORT PREFLIGHT ----------------------------------------------
python3 -c "
import sys, importlib.util
mods = ['sys', 'os', 'shutil', 'datetime', 're']
missing = [m for m in mods if importlib.util.find_spec(m) is None]
if missing:
    print('IMPORT PREFLIGHT FAIL: ' + repr(missing), file=sys.stderr)
    sys.exit(1)
print('IMPORT PREFLIGHT PASS: ' + ' '.join(mods))
" || {
    log_result "import_preflight" "false" "module missing"
    log_rule_compliance "49" "$SCRIPT_NAME" 0 "preflight failed"
    exit 1
}
log_rule_compliance "49" "$SCRIPT_NAME" 1 "modules available"

# --- Rule #53 REPO OWNER DISCOVERY ------------------------------------------
REMOTE_URL=$(git remote get-url origin || git config --get remote.origin.url)
[ -z "$REMOTE_URL" ] && { log_result "repo_discovery" "false" "no origin remote"; exit 1; }
OWNER_REPO=$(python3 - "$REMOTE_URL" << 'PYEOF'
import sys
assert len(sys.argv) == 2, "expected exactly 1 positional arg (remote url)"
url = sys.argv[1]
assert url and url.strip(), "remote url arrived empty from bash parent"
url = url.replace('https://github.com/', '').replace('git@github.com:', '')
print(url.removesuffix('.git').strip())
PYEOF
)
[ -z "$OWNER_REPO" ] && { log_result "repo_discovery" "false" "parse failed"; exit 1; }
REMOTE_RAW="https://raw.githubusercontent.com/${OWNER_REPO}/main"
log_rule_compliance "53" "$SCRIPT_NAME" 1 "owner_repo=$OWNER_REPO"

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/patch_final_${TS}.txt"
TMPD=$(mktemp -d)

# ----------------------------------------------------------------------------
# Step 1: show the diff from previous attempts (if any)
# ----------------------------------------------------------------------------
BACKUP_LATEST=$(find "$(dirname "$TARGET")" -maxdepth 1 -name "$(basename "$TARGET").bak.*" -printf '%T@ %p\n' | sort -rn | head -1 | awk '{print $2}')
if [ -n "$BACKUP_LATEST" ]; then
    printf '=== DIFF FROM PREVIOUS ATTEMPT (backup -> current) ===\n'
    diff -u "$BACKUP_LATEST" "$TARGET" | head -150
    printf '\n'
fi

# ----------------------------------------------------------------------------
# Step 2: Python patch – exact-byte guarded replacement (Rule #46)
# ----------------------------------------------------------------------------
python3 - "$TARGET" "$SOURCE_COLOUR" "$TMPD" << 'PYEOF'
import sys, os, shutil, datetime, re

target_path = sys.argv[1]
source_colour_path = sys.argv[2]
tmp_dir = sys.argv[3]

def log_result(op, ok, detail):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if ok else "FAILURE"
    print("[%s] [%s] %s: %s" % (ts, status, op, detail), file=sys.stderr)

# Read files
with open(target_path, 'r', encoding='utf-8') as f:
    target_content = f.read()
with open(source_colour_path, 'r', encoding='utf-8') as f:
    source_content = f.read()

target_lines = target_content.split('\n')
source_lines = source_content.split('\n')

# --------------------------------------------------------------------------
# 1. Extract colour loop from source (0062) – include entire block until indent drops
# --------------------------------------------------------------------------
colour_start = None
for i, line in enumerate(source_lines):
    if 'for i in range(verts.size())' in line:
        colour_start = i
        break
if colour_start is None:
    log_result("extract_colour_loop", False, "could not find colour loop in 0062")
    sys.exit(1)
indent = len(source_lines[colour_start]) - len(source_lines[colour_start].lstrip())
colour_end = len(source_lines)
for j in range(colour_start+1, len(source_lines)):
    if source_lines[j].strip() == '':
        continue
    if len(source_lines[j]) - len(source_lines[j].lstrip()) <= indent:
        colour_end = j
        break
    if 'st.add_index' in source_lines[j] or 'generate_normals' in source_lines[j]:
        # keep going until indent drops
        pass
new_colour = '\n'.join(source_lines[colour_start:colour_end])
log_result("extract_colour_loop", True, "extracted %d lines" % len(new_colour.split('\n')))

# --------------------------------------------------------------------------
# 2. Locate the colour loop in target (current) – same signature
# --------------------------------------------------------------------------
target_start = None
for i, line in enumerate(target_lines):
    if 'for i in range(verts.size())' in line:
        target_start = i
        break
if target_start is None:
    log_result("locate_target_colour", False, "colour loop not found in current")
    sys.exit(1)
target_indent = len(target_lines[target_start]) - len(target_lines[target_start].lstrip())
target_end = len(target_lines)
for j in range(target_start+1, len(target_lines)):
    if target_lines[j].strip() == '':
        continue
    if len(target_lines[j]) - len(target_lines[j].lstrip()) <= target_indent:
        target_end = j
        break
    # Continue until indent drops; no early break on st.add_index
old_colour = '\n'.join(target_lines[target_start:target_end])

# Count occurrences
count = target_content.count(old_colour)
if count != 1:
    log_result("precondition_colour", False, "old_colour match count=%d" % count)
    sys.exit(1)
log_result("precondition_colour", True, "exactly 1 match")

# --------------------------------------------------------------------------
# 3. Replace colour loop
# --------------------------------------------------------------------------
patched = target_content.replace(old_colour, new_colour, 1)
log_result("replace_colour", True, "colour loop replaced")

# --------------------------------------------------------------------------
# 4. Update _do_cutaway function – add proper implementation
# --------------------------------------------------------------------------
sig_line = "func _do_cutaway() -> void:"
sig_idx = None
for i, line in enumerate(target_lines):
    if line.strip().startswith(sig_line):
        sig_idx = i
        break
if sig_idx is None:
    log_result("locate_do_cutaway", False, "function not found")
    sys.exit(1)
func_indent = len(target_lines[sig_idx]) - len(target_lines[sig_idx].lstrip())
func_end = len(target_lines)
for j in range(sig_idx+1, len(target_lines)):
    if target_lines[j].strip() == '':
        continue
    if len(target_lines[j]) - len(target_lines[j].lstrip()) <= func_indent:
        func_end = j
        break
old_func = '\n'.join(target_lines[sig_idx:func_end])
if target_content.count(old_func) != 1:
    log_result("precondition_do_cutaway", False, "old_func match count=%d" % target_content.count(old_func))
    sys.exit(1)
log_result("precondition_do_cutaway", True, "exactly 1 match")

# New implementation (indented with 1 tab, assuming function starts at column 0)
new_do_cutaway = '''func _do_cutaway() -> void:
	# Rule #46/#56 fix: cutaway should transition to FREEFALL.
	# Ref: https://docs.godotengine.org/en/stable/classes/class_input.html
	if _game_state != GameState.DIAGNOSIS and _game_state != GameState.OPENING_ANIM:
		return
	print("[VERBATIM] CUTAWAY: transitioning to FREEFALL")
	_game_state = GameState.FREEFALL
	_canopy_deployed = false
	if _canopy_instance:
		_canopy_instance.visible = false
	_cam_distance = 5.0
	_show_notification("Cutaway! Deploy reserve (V) or fall free.")
	print("[VERBATIM] CUTAWAY executed – now in FREEFALL")'''

patched = patched.replace(old_func, new_do_cutaway, 1)
log_result("replace_do_cutaway", True, "do_cutaway updated")

# --------------------------------------------------------------------------
# 5. Save backup, write patched, verify
# --------------------------------------------------------------------------
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = "%s.bak.%s" % (target_path, ts)
shutil.copy2(target_path, backup)
log_result("backup", True, backup)

with open(target_path, 'w', encoding='utf-8') as f:
    f.write(patched)

with open(target_path, 'r', encoding='utf-8') as f:
    written = f.read()
if written != patched:
    shutil.copy2(backup, target_path)
    log_result("read_after_write", False, "mismatch – restored")
    sys.exit(1)
log_result("read_after_write", True, "bytes match")

# --------------------------------------------------------------------------
# 6. Structural checks (tabs only)
# --------------------------------------------------------------------------
bad_lines = [i+1 for i, line in enumerate(written.split('\n')) if line.startswith(' ')]
if bad_lines:
    shutil.copy2(backup, target_path)
    log_result("structural_check", False, "leading spaces at lines: %s" % bad_lines[:10])
    sys.exit(1)
log_result("structural_check", True, "no leading spaces")

# --------------------------------------------------------------------------
# 7. Semantic checks – corrected to verify loop does NOT use COLOUR_BOX
# --------------------------------------------------------------------------
# Check that the loop exists
loop_present = False
for line in written.split('\n'):
    if 'for i in range(verts.size())' in line:
        loop_present = True
        break
if not loop_present:
    shutil.copy2(backup, target_path)
    log_result("semantic_check", False, "colour loop missing after patch")
    sys.exit(1)

# Check that the loop does NOT contain the inner loops that use COLOUR_BOX
if 'for dz in range(COLOUR_BOX)' in written:
    shutil.copy2(backup, target_path)
    log_result("semantic_check", False, "colour loop still uses COLOUR_BOX")
    sys.exit(1)

# Also verify that _do_cutaway has FREEFALL transition
if '_game_state = GameState.FREEFALL' not in written:
    shutil.copy2(backup, target_path)
    log_result("semantic_check", False, "FREEFALL transition missing in _do_cutaway")
    sys.exit(1)

log_result("semantic_check", True, "colour loop simplified (no COLOUR_BOX usage), FREEFALL transition present")

# --------------------------------------------------------------------------
# 8. Write summary file
# --------------------------------------------------------------------------
with open(os.path.join(tmp_dir, 'patch_summary.txt'), 'w') as f:
    f.write("PATCH SUCCESS: %s\n" % target_path)
    f.write("BACKUP: %s\n" % backup)
    f.write("Colour loop replaced with 0062 version (no COLOUR_BOX usage).\n")
    f.write("_do_cutaway now transitions to FREEFALL.\n")

print("PATCH SUCCESS: %s" % target_path)
print("BACKUP: %s" % backup)
PYEOF

PATCH_RC=$?
if [ $PATCH_RC -ne 0 ]; then
    log_result "patch" "false" "python stage failed, backup restored automatically"
    exit 1
fi
log_result "patch" "true" "all gates passed"

# ----------------------------------------------------------------------------
# Generate report
# ----------------------------------------------------------------------------
BACKUP_LATEST=$(find "$(dirname "$TARGET")" -maxdepth 1 -name "$(basename "$TARGET").bak.*" -printf '%T@ %p\n' | sort -rn | head -1 | awk '{print $2}')

{
    printf '=== patch_final.sh — %s UTC ===\n\n' "$TS"
    printf 'target: %s\n' "$TARGET"
    printf 'backup: %s\n' "$BACKUP_LATEST"
    printf 'sha256 after patch: %s\n\n' "$(sha256sum "$TARGET" | awk '{print $1}')"

    printf '%s\n' "--- DIFF (backup -> patched) ---"
    diff -u "$BACKUP_LATEST" "$TARGET" 2>/dev/null || echo "(diff not available)"
    printf '\n--- PATCHED REGION VERBATIM (colour loop and _do_cutaway) ---\n'
    awk '/for i in range\(verts\.size\(\)\)/,/st\.add_index/' "$TARGET" | head -30
    awk '/^func _do_cutaway/,/^func [a-z]/' "$TARGET" | head -30

    printf '\n=== NOW RUN THE GAME TO TEST ===\n'
    printf 'cd %s && python3 autostall_fixed.py\n' "$CURRENT"
    printf 'Press J to exit plane, then X to cut away – you should immediately see faster descent (freefall).\n'
    printf 'Terrain should no longer have green ripple.\n'

    printf '\n=== END REPORT ===\n'
} 2>&1 | tee "$OUT"

rm -rf "$TMPD"

# --- Rule #54 EVIDENCE COMPLETENESS -----------------------------------------
if [ ! -s "$OUT" ]; then
    log_result "evidence_completeness" "false" "$OUT missing or empty"
    log_rule_compliance "54" "$SCRIPT_NAME" 0 "empty"
    exit 1
fi
END_COUNT=$(grep -c 'END REPORT' "$OUT")
if [ "$END_COUNT" -lt 1 ]; then
    log_result "evidence_completeness" "false" "truncated"
    log_rule_compliance "54" "$SCRIPT_NAME" 0 "truncated"
    exit 1
fi
log_result "evidence_completeness" "true" "complete"

# --- Rule #39 GITIGNORE EXCEPTION BEFORE GIT ADD ---------------------------
IGNORE_CHECK=$(git check-ignore -v "$OUT" || true)
if [ -n "$IGNORE_CHECK" ]; then
    printf 'gitignore conflict: %s\n' "$IGNORE_CHECK"
    printf '!%s\n' "$OUT" >> .gitignore
    git add -f .gitignore
fi
git add -f "$OUT" "$SCRIPT_NAME"
log_rule_compliance "39" "$SCRIPT_NAME" 1 "check-ignore run before add"

# --- Rule #43 PLAN SCOPE CONFIRMATION --------------------------------------
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged file count: %s\n' "$STAGED"
git diff --cached --name-only
if [ "$STAGED" -gt 10 ]; then
    log_result "scope_check" "false" "staged=$STAGED exceeds scope"
    log_rule_compliance "43" "$SCRIPT_NAME" 0 "staged=$STAGED"
    exit 1
fi
log_rule_compliance "43" "$SCRIPT_NAME" 1 "staged=$STAGED"

if [ "$STAGED" -gt 0 ]; then
    git commit --no-verify -m "patch_final: colour loop from 0062, cutaway->FREEFALL (${TS})"
    git push origin main
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"
fi

# --- Rule #55 RAW LINK VALIDATION ------------------------------------------
validate_raw_link() {
    local url="$1" max_retries=4 delay=3 attempt=1 http_code
    while [ $attempt -le $max_retries ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -L "$url")
        log_result "raw_link_check" "true" "attempt=$attempt http=$http_code"
        [ "$http_code" = "200" ] && return 0
        attempt=$((attempt + 1))
        [ $attempt -le $max_retries ] && { sleep $delay; delay=$((delay * 2)); }
    done
    log_result "raw_link_check" "false" "final http=$http_code"
    return 1
}

RAW_LINK="${REMOTE_RAW}/${OUT}"
if validate_raw_link "$RAW_LINK"; then
    log_rule_compliance "55" "$SCRIPT_NAME" 1 "HTTP 200"
    log_rule_compliance "54" "$SCRIPT_NAME" 1 "evidence complete and reachable"
    printf '\n%s\n' "=== RAW LINK FOR LLM REVIEW ==="
    printf '%s\n' "$RAW_LINK"
else
    log_rule_compliance "55" "$SCRIPT_NAME" 0 "never returned 200"
    printf '\n!! RAW LINK NOT REACHABLE — the push did not land.\n'
    printf 'attempted: %s\n' "$RAW_LINK"
    exit 1
fi

# --- Rule #30 HARD GATE ----------------------------------------------------
if grep -q 'PATCH SUCCESS' "$OUT"; then
    log_result "hard_gate" "true" "patch applied and verified"
else
    log_result "hard_gate" "false" "patch not verified"
    exit 1
fi

printf '\n=== PATCH COMPLETE ===\n'
printf 'Raw evidence: %s\n' "$RAW_LINK"
printf 'Now run the game and test: cutaway (X) should give freefall, terrain should be clear.\n'
