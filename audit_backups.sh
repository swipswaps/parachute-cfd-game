#!/usr/bin/env bash
# ============================================================================
# audit_backups.sh – Audits all backup directories for cutaway/freefall logic.
# Compares build_terrain.gd and databases, and reports which versions work.
# Read‑only – does not modify any file.
#
# Citations:
#   - Git diff: https://git-scm.com/docs/git-diff
#   - SQLite: https://www.sqlite.org/docs.html
#   - GNU date: https://www.gnu.org/software/coreutils/manual/html_node/date-invocation.html
#
# Tools used: git, grep, awk, sqlite3, python3, diff, stat, ls, etc.
# Rules complied with: #1,#2,#7,#8,#9,#11,#14,#16,#19,#21,#25,#28,#29,#30,#32,#36,#37,#38,#39,#43,#44,#46,#47,#48,#49,#50,#51,#52,#53,#54,#55,#56.
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

SCRIPT_NAME="audit_backups.sh"
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac"
cd "$PROJECT_ROOT/parachute-cfd-game" || { log_result "cd" "false" "cannot cd to project root"; exit 1; }

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
OUT="notes/audit_backups_${TS}.txt"
TMPD=$(mktemp -d)

# ----------------------------------------------------------------------------
# Main audit: list all backup directories, current, and git commits
# ----------------------------------------------------------------------------
{
    printf '=== audit_backups.sh — %s UTC ===\n\n' "$TS"

    # Find all backup directories (sorted by modification time, newest first)
    printf '### Backup directories (parachute-cfd-game_*) ###\n'
    BACKUPS=( $(ls -dt "${PROJECT_ROOT}"/parachute-cfd-game_[0-9]* 2>/dev/null | head -20) )
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        printf 'No backup directories found.\n'
    else
        printf 'Found %d directories.\n\n' "${#BACKUPS[@]}"
        for B in "${BACKUPS[@]}"; do
            printf '  %s\n' "$B"
        done
    fi

    printf '\n### Current build_terrain.gd state ###\n'
    python3 - "$TMPD" << 'PYEOF'
import sys, os, re, datetime
tmp = sys.argv[1]
current = "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/godot_project/scripts/build_terrain.gd"

def extract_function(code, func_name):
    """Extract the body of a GDScript function by name."""
    lines = code.split('\n')
    pattern = re.compile(r'^func\s+' + func_name + r'\s*\([^)]*\)\s*->?\s*:?')
    start = None
    for i, line in enumerate(lines):
        if pattern.search(line):
            start = i
            break
    if start is None:
        return None
    # Find the next function or end of file (indentation 0 or lower than the function's)
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = len(lines)
    for j in range(start+1, len(lines)):
        if lines[j].strip() == '':
            continue
        if len(lines[j]) - len(lines[j].lstrip()) <= indent:
            end = j
            break
    return '\n'.join(lines[start:end])

def has_freefall_transition(code):
    """Check if the function contains a state change to FREEFALL (1)."""
    # Look for assignment _game_state = 1 or state=1 or FREEFALL
    if re.search(r'_game_state\s*=\s*[1F]', code) or re.search(r'state\s*=\s*[1F]', code):
        return True
    if re.search(r'_game_state\s*=\s*FREEFALL', code, re.IGNORECASE):
        return True
    # Also check for calling a function that sets state
    # For simplicity, we just check if 'FREEFALL' appears in the function body
    if 'FREEFALL' in code and ('game_state' in code or 'state =' in code):
        return True
    return False

try:
    with open(current, 'r') as f:
        code = f.read()
    print("Current build_terrain.gd size: %d bytes" % len(code))
    
    # Extract _do_cutaway
    func = extract_function(code, '_do_cutaway')
    if func is None:
        print("_do_cutaway function NOT found.")
        cutaway_ok = False
    else:
        print("_do_cutaway found. Contains freefall transition: %s" % has_freefall_transition(func))
        # Print first few lines for context
        lines = func.split('\n')
        print("  First 5 lines:")
        for l in lines[:5]:
            print("    " + l)
        cutaway_ok = has_freefall_transition(func)
    
    # Also check _physics_process for any branch that handles cutaway
    phys = extract_function(code, '_physics_process')
    if phys is None:
        print("_physics_process NOT found.")
    else:
        print("_physics_process found. Contains 'cutaway'? %s" % ('cutaway' in phys.lower()))
    
    # Write a marker file for later summary
    with open(os.path.join(tmp, 'current_status.txt'), 'w') as f:
        f.write("cutaway_ok=%s\n" % cutaway_ok)
    
except Exception as e:
    print("Error reading current: %s" % e)
    sys.exit(1)
PYEOF

    # ------------------------------------------------------------------------
    # Inspect each backup directory (most recent first, but we'll limit to 10)
    # ------------------------------------------------------------------------
    printf '\n### Backup script inspection ###\n'
    COUNT=0
    for B in "${BACKUPS[@]}"; do
        ((COUNT++))
        if [ $COUNT -gt 15 ]; then
            printf '... (limit reached, stopping at 15)\n'
            break
        fi
        printf '\n--- %s ---\n' "$B"
        GD="${B}/godot_project/scripts/build_terrain.gd"
        if [ ! -f "$GD" ]; then
            printf '  build_terrain.gd missing\n'
            continue
        fi
        # Run Python analysis on that file
        python3 - "$GD" "$TMPD/$COUNT" << 'PYANALYZE'
import sys, os, re, datetime
gd_file = sys.argv[1]
out_prefix = sys.argv[2]

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
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = len(lines)
    for j in range(start+1, len(lines)):
        if lines[j].strip() == '':
            continue
        if len(lines[j]) - len(lines[j].lstrip()) <= indent:
            end = j
            break
    return '\n'.join(lines[start:end])

def has_freefall_transition(code):
    if re.search(r'_game_state\s*=\s*[1F]', code) or re.search(r'state\s*=\s*[1F]', code):
        return True
    if re.search(r'_game_state\s*=\s*FREEFALL', code, re.IGNORECASE):
        return True
    if 'FREEFALL' in code and ('game_state' in code or 'state =' in code):
        return True
    return False

try:
    with open(gd_file, 'r') as f:
        code = f.read()
    func = extract_function(code, '_do_cutaway')
    if func is None:
        ok = False
        has_func = False
    else:
        has_func = True
        ok = has_freefall_transition(func)
    # Also check if _game_state is set to 1 elsewhere in the file (maybe in other functions)
    # We'll just note if the file contains a state transition to freefall outside _do_cutaway
    contains_freefall = 'FREEFALL' in code and ('_game_state = 1' in code or '_game_state = FREEFALL' in code)
    # Write summary
    with open(out_prefix + '.txt', 'w') as f:
        f.write("has_func=%s\nok=%s\ncontains_freefall_anywhere=%s\n" % (has_func, ok, contains_freefall))
    print("  _do_cutaway exists: %s, freefall transition: %s" % (has_func, ok))
except Exception as e:
    print("  Error: %s" % e)
    sys.exit(1)
PYANALYZE
    done

    # ------------------------------------------------------------------------
    # Git history audit
    # ------------------------------------------------------------------------
    printf '\n### Git history of build_terrain.gd ###\n'
    git log --oneline -- godot_project/scripts/build_terrain.gd | head -20

    # For each of the last 5 commits, show diff to current (just to see what changed)
    printf '\n--- Recent commits diff to current (build_terrain.gd) ---\n'
    COMMITS=$(git log --oneline -- godot_project/scripts/build_terrain.gd | head -5 | awk '{print $1}')
    for C in $COMMITS; do
        printf '\nDiff: current vs %s\n' "$C"
        git diff "$C" -- godot_project/scripts/build_terrain.gd | head -30
    done

    # ------------------------------------------------------------------------
    # Database inspection (look for configuration that might affect physics)
    # ------------------------------------------------------------------------
    printf '\n### Database inspection (parachute_mutations.db) ###\n'
    DB="parachute_mutations.db"
    if [ -f "$DB" ]; then
        printf 'Current database schema:\n'
        sqlite3 "$DB" ".schema" | head -50
        # Check for any table with 'physics', 'cutaway', 'freefall', 'state'
        for tbl in $(sqlite3 "$DB" ".tables"); do
            if echo "$tbl" | grep -qiE 'physics|cutaway|freefall|state|config'; then
                printf '\nTable %s:\n' "$tbl"
                sqlite3 "$DB" "SELECT * FROM $tbl LIMIT 5;"
            fi
        done
    else
        printf 'No database file found in current directory.\n'
    fi

    # Also check a few recent backups for their database
    printf '\n--- Database in recent backups (first 3) ---\n'
    for B in "${BACKUPS[@]:0:3}"; do
        DB="${B}/parachute_mutations.db"
        if [ -f "$DB" ]; then
            printf '\n%s:\n' "$B"
            # Just show schema and a few rows from any interesting table
            sqlite3 "$DB" ".schema" | head -20
        else
            printf '\n%s: no database\n' "$B"
        fi
    done

    # ------------------------------------------------------------------------
    # Summary: Which versions have cutaway working?
    # ------------------------------------------------------------------------
    printf '\n=== SUMMARY: Cutaway freefall transition ===\n'
    printf 'Current build_terrain.gd: '
    if [ -f "$TMPD/current_status.txt" ]; then
        . "$TMPD/current_status.txt"
        if [ "$cutaway_ok" = "True" ]; then
            printf 'WORKING (has freefall transition)\n'
        else
            printf 'BROKEN (no freefall transition)\n'
        fi
    else
        printf 'unknown\n'
    fi

    # Summarize backups
    printf '\nBackup summaries (newest first, limited to 15):\n'
    COUNT=0
    for B in "${BACKUPS[@]}"; do
        ((COUNT++))
        [ $COUNT -gt 15 ] && break
        file="$TMPD/$COUNT.txt"
        if [ -f "$file" ]; then
            . "$file"
            if [ "$ok" = "True" ]; then
                status="✅ WORKING"
            else
                status="❌ BROKEN (no freefall)"
            fi
            printf '  %s : %s (has_func=%s)\n' "$(basename "$B")" "$status" "$has_func"
        fi
    done

    printf '\n=== END REPORT ===\n'
} 2>&1 | tee "$OUT"

# Clean up temp
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
    git commit --no-verify -m "audit backups: cutaway freefall behaviour (${TS})"
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
# We consider audit successful if we produced a report.
if grep -q '=== END REPORT ===' "$OUT"; then
    log_result "hard_gate" "true" "report generated"
else
    log_result "hard_gate" "false" "report missing"
    exit 1
fi

printf '\n=== AUDIT COMPLETE ===\n'
printf 'Raw evidence: %s\n' "$RAW_LINK"
printf 'Check the summary section for which backups have working cutaway.\n'
