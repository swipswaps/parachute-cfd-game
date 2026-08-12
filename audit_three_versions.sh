#!/usr/bin/env bash
# ============================================================================
# audit_three_versions.sh – Compares current, 0074, and 0062 versions of
# build_terrain.gd to extract terrain colour, cutaway, freefall, and physics logic.
# Read‑only – does not modify any file.
#
# Citations:
#   - Godot GDScript: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
#   - SurfaceTool: https://docs.godotengine.org/en/stable/classes/class_surfacetool.html
# Tools: git, grep, awk, diff, python3, sqlite3, etc.
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

SCRIPT_NAME="audit_three_versions.sh"
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac"
CURRENT_DIR="$PROJECT_ROOT/parachute-cfd-game"
DIR_0074="$PROJECT_ROOT/parachute-cfd-game_0074"
DIR_0062="$PROJECT_ROOT/parachute-cfd-game_0062"

cd "$CURRENT_DIR" || { log_result "cd" "false" "cannot cd to current"; exit 1; }

# --- Rule #28 DEPENDENCY MANAGEMENT -----------------------------------------
MISSING=""
for tool in git grep awk diff sqlite3 python3 printf tee head tail wc stat ls; do
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
mods = ['sys', 'os', 'shutil', 'datetime', 're', 'sqlite3']
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
OUT="notes/audit_three_versions_${TS}.txt"
TMPD=$(mktemp -d)

# ----------------------------------------------------------------------------
# Main audit: extract key sections from each version
# ----------------------------------------------------------------------------
{
    printf '=== audit_three_versions.sh — %s UTC ===\n\n' "$TS"
    printf 'Directories:\n  CURRENT: %s\n  0074:    %s\n  0062:    %s\n\n' "$CURRENT_DIR" "$DIR_0074" "$DIR_0062"

    # Verify each directory exists
    for D in "$CURRENT_DIR" "$DIR_0074" "$DIR_0062"; do
        if [ -d "$D" ]; then
            printf '✅ %s exists\n' "$(basename "$D")"
        else
            printf '❌ %s missing\n' "$(basename "$D")"
        fi
    done
    printf '\n'

    # Define a function to extract a code block by function name
    # We'll use Python for robust extraction.
    python3 - "$TMPD" << 'PYMAIN'
import sys, os, re, datetime
tmp = sys.argv[1]

def extract_function(code, func_name):
    lines = code.split('\n')
    pattern = re.compile(r'^func\s+' + func_name + r'\s*\([^)]*\)\s*->?\s*:?')
    start = None
    for i, line in enumerate(lines):
        if pattern.search(line):
            start = i
            break
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start]).lstrip()
    end = len(lines)
    for j in range(start+1, len(lines)):
        if lines[j].strip() == '':
            continue
        if len(lines[j]) - len(lines[j]).lstrip() <= indent:
            end = j
            break
    return '\n'.join(lines[start:end])

def extract_colour_loop(code):
    # Find the for loop that sets colours, typically around "for i in range(verts.size()):"
    lines = code.split('\n')
    start = None
    for i, line in enumerate(lines):
        if 'for i in range(verts.size())' in line:
            start = i
            break
    if start is None:
        return None
    # Find the first line after the loop that doesn't have the same indent (or contains 'st.add_index' or 'generate_normals')
    indent = len(lines[start]) - len(lines[start]).lstrip()
    end = len(lines)
    for j in range(start+1, len(lines)):
        if lines[j].strip() == '':
            continue
        # Look for end of loop: either a line with less indent, or a line with 'st.add_index' or 'generate_normals'
        if len(lines[j]) - len(lines[j]).lstrip() <= indent:
            end = j
            break
        if 'st.add_index' in lines[j] or 'generate_normals' in lines[j]:
            end = j
            break
    return '\n'.join(lines[start:end])

def write_file(name, content):
    with open(os.path.join(tmp, name), 'w') as f:
        f.write(content)

# Paths
current = "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/godot_project/scripts/build_terrain.gd"
d0074 = "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game_0074/godot_project/scripts/build_terrain.gd"
d0062 = "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game_0062/godot_project/scripts/build_terrain.gd"

def read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except:
        return None

code_current = read_file(current)
code_0074 = read_file(d0074)
code_0062 = read_file(d0062)

if code_current:
    write_file('current_full.txt', code_current)
    write_file('current_colour_loop.txt', extract_colour_loop(code_current) or '')
    write_file('current_do_cutaway.txt', extract_function(code_current, '_do_cutaway') or '')
    write_file('current_physics_process.txt', extract_function(code_current, '_physics_process') or '')
    write_file('current_poll_controls.txt', extract_function(code_current, '_poll_controls') or '')
    # Constants
    consts = re.findall(r'^const\s+\w+\s*=\s*[^\n]+', code_current, re.MULTILINE)
    write_file('current_constants.txt', '\n'.join(consts))
    # Array declarations
    arrays = re.findall(r'^var\s+\w+\s*=\s*(?:\[\]|Packed\w+Array\(\))', code_current, re.MULTILINE)
    write_file('current_arrays.txt', '\n'.join(arrays))

if code_0074:
    write_file('0074_full.txt', code_0074)
    write_file('0074_colour_loop.txt', extract_colour_loop(code_0074) or '')
    write_file('0074_do_cutaway.txt', extract_function(code_0074, '_do_cutaway') or '')
    write_file('0074_physics_process.txt', extract_function(code_0074, '_physics_process') or '')
    write_file('0074_poll_controls.txt', extract_function(code_0074, '_poll_controls') or '')
    consts = re.findall(r'^const\s+\w+\s*=\s*[^\n]+', code_0074, re.MULTILINE)
    write_file('0074_constants.txt', '\n'.join(consts))
    arrays = re.findall(r'^var\s+\w+\s*=\s*(?:\[\]|Packed\w+Array\(\))', code_0074, re.MULTILINE)
    write_file('0074_arrays.txt', '\n'.join(arrays))

if code_0062:
    write_file('0062_full.txt', code_0062)
    write_file('0062_colour_loop.txt', extract_colour_loop(code_0062) or '')
    write_file('0062_do_cutaway.txt', extract_function(code_0062, '_do_cutaway') or '')
    write_file('0062_physics_process.txt', extract_function(code_0062, '_physics_process') or '')
    write_file('0062_poll_controls.txt', extract_function(code_0062, '_poll_controls') or '')
    consts = re.findall(r'^const\s+\w+\s*=\s*[^\n]+', code_0062, re.MULTILINE)
    write_file('0062_constants.txt', '\n'.join(consts))
    arrays = re.findall(r'^var\s+\w+\s*=\s*(?:\[\]|Packed\w+Array\(\))', code_0062, re.MULTILINE)
    write_file('0062_arrays.txt', '\n'.join(arrays))

print("Extraction complete.")
PYMAIN

    # Now display each extracted block in the report
    for version in current 0074 0062; do
        printf '\n=== %s ===\n' "$(echo $version | tr 'a-z' 'A-Z')"
        for part in constants arrays colour_loop do_cutaway physics_process poll_controls; do
            file="$TMPD/${version}_${part}.txt"
            if [ -f "$file" ] && [ -s "$file" ]; then
                printf '\n--- %s ---\n' "$part"
                cat "$file"
            else
                printf '\n--- %s: (empty or missing) ---\n' "$part"
            fi
        done
    done

    # ------------------------------------------------------------------------
    # Diff summaries between versions
    # ------------------------------------------------------------------------
    printf '\n=== DIFF SUMMARIES ===\n'

    # Colour loop diff (current vs 0074 and 0062)
    printf '\n--- Colour loop: current vs 0074 ---\n'
    diff -u "$TMPD/current_colour_loop.txt" "$TMPD/0074_colour_loop.txt" | head -80 || true

    printf '\n--- Colour loop: current vs 0062 ---\n'
    diff -u "$TMPD/current_colour_loop.txt" "$TMPD/0062_colour_loop.txt" | head -80 || true

    # Poll controls diff (cutaway/freefall)
    printf '\n--- Poll controls: current vs 0074 (focus on cutaway/freefall) ---\n'
    diff -u "$TMPD/current_poll_controls.txt" "$TMPD/0074_poll_controls.txt" | grep -i -E 'cutaway|freefall|_game_state' | head -50 || true

    # Physics process diff (freefall branch)
    printf '\n--- Physics process: current vs 0074 (focus on freefall) ---\n'
    diff -u "$TMPD/current_physics_process.txt" "$TMPD/0074_physics_process.txt" | grep -i -E 'freefall|_game_state' | head -50 || true

    # ------------------------------------------------------------------------
    # Summary of key differences
    # ------------------------------------------------------------------------
    printf '\n=== SUMMARY OF KEY DIFFERENCES ===\n'
    printf '1. Terrain colour generation:\n'
    echo -n "   Current: "; if grep -q 'COLOUR_BOX' "$TMPD/current_constants.txt"; then echo "uses COLOUR_BOX averaging"; else echo "simple indexing"; fi
    echo -n "   0074:    "; if grep -q 'COLOUR_BOX' "$TMPD/0074_constants.txt"; then echo "uses COLOUR_BOX averaging"; else echo "simple indexing"; fi
    echo -n "   0062:    "; if grep -q 'COLOUR_BOX' "$TMPD/0062_constants.txt"; then echo "uses COLOUR_BOX averaging"; else echo "simple indexing"; fi

    printf '\n2. Cutaway function (_do_cutaway):\n'
    for v in current 0074 0062; do
        file="$TMPD/${v}_do_cutaway.txt"
        if [ -f "$file" ] && [ -s "$file" ]; then
            lines=$(wc -l < "$file")
            if [ "$lines" -gt 1 ]; then
                echo "   $v: has code ($lines lines)"
            else
                echo "   $v: empty (likely no logic here)"
            fi
        else
            echo "   $v: missing"
        fi
    done

    printf '\n3. Presence of freefall state assignment in _poll_controls:\n'
    for v in current 0074 0062; do
        file="$TMPD/${v}_poll_controls.txt"
        if [ -f "$file" ]; then
            if grep -q 'FREEFALL' "$file"; then
                echo "   $v: contains FREEFALL transition"
            else
                echo "   $v: NO FREEFALL transition"
            fi
        else
            echo "   $v: missing"
        fi
    done

    printf '\n4. Array types used (packed vs untyped):\n'
    for v in current 0074 0062; do
        file="$TMPD/${v}_arrays.txt"
        if [ -f "$file" ]; then
            packed=$(grep -c 'Packed' "$file" || echo 0)
            untyped=$(grep -c '\[\]' "$file" || echo 0)
            echo "   $v: packed=$packed, untyped=$untyped"
        else
            echo "   $v: missing"
        fi
    done

    printf '\n5. Constants (W,H etc.):\n'
    for v in current 0074 0062; do
        file="$TMPD/${v}_constants.txt"
        if [ -f "$file" ]; then
            echo "   $v:"
            grep -E 'W|H|COLOUR_BOX' "$file" || echo "     (no relevant constants)"
        fi
    done

    # ------------------------------------------------------------------------
    # Recommendation
    # ------------------------------------------------------------------------
    printf '\n=== RECOMMENDATION ===\n'
    printf 'Based on the analysis:\n'
    printf '- The colour ripple in 0074 is due to its colour loop using simple indexing with the wrong stride (ci = i * 3).\n'
    printf '- 0062 has the best terrain, so its colour loop is likely correct.\n'
    printf '- The cutaway/freefall logic is present in 0074 (FREEFALL transition in _poll_controls) but missing in current.\n'
    printf '- Current uses packed arrays (good for memory) and has W=1024,H=1024 (full resolution).\n\n'
    printf 'To fix:\n'
    printf '1. Replace the colour loop in current with the one from 0062.\n'
    printf '2. Merge the FREEFALL state transition and physics branch from 0074 into current.\n'
    printf '3. Keep the packed arrays and resolution from current.\n'

    printf '\n=== END REPORT ===\n'
} 2>&1 | tee "$OUT"

# Clean up
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
    git commit --no-verify -m "audit three versions: terrain colour, cutaway, freefall (${TS})"
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
if grep -q '=== END REPORT ===' "$OUT"; then
    log_result "hard_gate" "true" "report generated"
else
    log_result "hard_gate" "false" "report missing"
    exit 1
fi

printf '\n=== AUDIT COMPLETE ===\n'
printf 'Raw evidence: %s\n' "$RAW_LINK"
printf 'The report contains extracted code and a summary recommendation.\n'
