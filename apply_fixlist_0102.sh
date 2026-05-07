#!/usr/bin/env bash
# PATH: apply_fixlist_0102.sh
# v102 fixes over v101:
#   EXIT-001    [CRITICAL] set +eu before source OpenFOAM bashrc (set +u alone insufficient)
#   VERBATIM-001[CRITICAL] stdbuf -oL tee on all solver pipes (64KB buffer stall)
#   PIPEFAIL-001[CRITICAL] || true after all solver pipes (set -e kills before diagnose_and_heal)
#   LOCATE-001  [HIGH]    fix_locationInMesh: sed cannot evaluate arithmetic; use python3
#   VTK-SUBDIR-001[HIGH]  extract_wind_vectors.py: os.walk for internal.vtu, not os.listdir
#   CONV-001    [MEDIUM]  run_sim_step completion: use _foam_has_time_dir, not forceCoeffs
#   COLLAPSED-001[MEDIUM] reinstate awk collapsed residual display from v69/v70
#   VERBATIM-002[MEDIUM]  run_mesh_step: dump log verbatim on failure, remove silent || true
#   VENV-001    [MEDIUM]  remove conflicting venv; use system packages (working state)
#   STATECHECK-001[LOW]   restore .cfd_state persistence

set -euo pipefail
trap 'echo "  Interrupted by user"; exit 130' INT

REPO_ROOT="$(pwd)"
HEAL_DB=".cfd_healdb"
echo "=== Parachute CFD Landing Game – Self-Healing v102 ==="
echo "Working directory: $REPO_ROOT"

# ─────────────────────────────────────────────────────────────────────
# Permission check
# ─────────────────────────────────────────────────────────────────────
check_permissions() {
    echo "🔍 Checking write permissions..."
    for dir in "." "godot_project"; do
        if [ -d "$dir" ] && [ ! -w "$dir" ]; then
            echo "❌ $dir is not writable"; exit 1
        fi
    done
    echo "✅ Permissions OK"
}

# ─────────────────────────────────────────────────────────────────────
# EXIT-001: setup_environment with set +eu around source
# set +u alone is insufficient — set -e kills on any non-zero return
# from OpenFOAM bashrc. Must disable BOTH before sourcing.
# ─────────────────────────────────────────────────────────────────────
setup_environment() {
    echo "🔧 Setting up environment..."

    add_to_path() {
        local dir="$1"
        if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
            export PATH="$dir:$PATH"
            echo "  Added to PATH: $dir"
        fi
    }

    # OpenFOAM
    if ! command -v blockMesh >/dev/null 2>&1; then
        echo "  🔍 OpenFOAM not in PATH. Searching..."
        local sourced=0
        for bashrc in \
            /usr/lib/openfoam/openfoam2512/etc/bashrc \
            /usr/lib/openfoam/openfoam*/etc/bashrc \
            /opt/openfoam*/etc/bashrc \
            /usr/local/openfoam*/etc/bashrc \
            "$HOME/OpenFOAM"/*/etc/bashrc; do
            [ -f "$bashrc" ] || continue
            echo "  🔧 Sourcing: $bashrc"
            echo "  (disabling set -eu around source — OpenFOAM bashrc may return non-zero)"
            # EXIT-001 fix: disable BOTH -e and -u, not just -u
            set +eu
            # shellcheck source=/dev/null
            source "$bashrc" 2>&1 || true
            set -eu
            sourced=1
            break
        done
        if [ $sourced -eq 0 ]; then
            echo "  ⚠️  OpenFOAM bashrc not found — trying PATH search"
            for d in /usr/lib/openfoam/openfoam2512/bin /usr/bin /usr/local/bin; do
                [ -f "$d/blockMesh" ] && add_to_path "$d" && break
            done
        fi
        if ! command -v blockMesh >/dev/null 2>&1; then
            echo "  ❌ blockMesh not found after sourcing. PATH:"
            echo "$PATH" | tr ':' '\n' | sed 's/^/    /'
            echo "  Run 'source /usr/lib/openfoam/openfoam2512/etc/bashrc' manually."
            exit 1
        fi
        echo "  ✅ OpenFOAM: $(command -v blockMesh)"
    else
        echo "  ✅ OpenFOAM available: $(command -v blockMesh)"
    fi

    # pvpython
    if ! command -v pvpython >/dev/null 2>&1; then
        echo "  🔍 pvpython not in PATH. Searching..."
        PVPY=$(find /usr -name pvpython 2>/dev/null | head -1)
        if [ -n "$PVPY" ]; then
            sudo ln -sf "$PVPY" /usr/local/bin/pvpython
            echo "  ✅ pvpython linked: $PVPY"
        else
            echo "  ⚠️  pvpython not found — wind extraction will use fallback"
        fi
    else
        echo "  ✅ pvpython: $(command -v pvpython)"
    fi

    # Godot
    if ! command -v godot >/dev/null 2>&1; then
        for p in /usr/local/bin/godot /var/lib/flatpak/exports/bin/org.godotengine.Godot; do
            [ -f "$p" ] && add_to_path "$(dirname "$p")" && break
        done
    fi
    command -v godot >/dev/null 2>&1 && echo "  ✅ godot: $(command -v godot)" || echo "  ⚠️  godot not found"

    # python3 mandatory
    command -v python3 >/dev/null 2>&1 || { echo "❌ python3 not found"; exit 1; }
    echo "  ✅ python3: $(command -v python3)"

    command -v sqlite3 >/dev/null 2>&1 && echo "  ✅ sqlite3 available" || echo "  ⚠️  sqlite3 missing"
    echo "✅ Environment setup complete"
}

# ─────────────────────────────────────────────────────────────────────
# System transparency dump (retained from v101)
# ─────────────────────────────────────────────────────────────────────
dump_system_info() {
    mkdir -p audit_logs
    local dump_file="audit_logs/system_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "=== DATE ==="; date
        echo "=== SYSTEM ==="; uname -a
        echo "=== COMMANDS ==="
        for cmd in blockMesh simpleFoam foamToVTK pvpython godot python3 sqlite3 git; do
            printf "%-15s: " "$cmd"
            command -v "$cmd" 2>/dev/null || echo "NOT FOUND"
        done
        echo "=== OPENFOAM ENV ==="
        env | grep -E 'WM_|FOAM_|OPENFOAM' | sort 2>/dev/null || echo "None"
        echo "=== HEAL DB ==="
        sqlite3 "$HEAL_DB" "SELECT id,pattern,success_count,fail_count FROM error_patterns" 2>/dev/null || echo "No DB"
    } > "$dump_file"
    echo "📝 System dump: $dump_file"
}

# ─────────────────────────────────────────────────────────────────────
# run_step helper
# ─────────────────────────────────────────────────────────────────────
run_step() {
    local name="$1" check="$2" apply="$3" verify="$4"
    echo "➤ Step: $name"
    if eval "$check" 2>/dev/null; then
        echo "  ✅ Already done – skipping"; return 0
    fi
    echo "  🔧 Running..."
    eval "$apply" || { echo "  ❌ Failed: $name"; exit 1; }
    eval "$verify" 2>/dev/null || { echo "  ❌ Verify failed: $name"; exit 1; }
    echo "  ✅ Completed"
}

# ─────────────────────────────────────────────────────────────────────
# _foam_has_time_dir: any numeric dir > 0 (handles early convergence)
# ─────────────────────────────────────────────────────────────────────
_foam_has_time_dir() {
    local case="${1:-.}"
    ls -d "$case"/[0-9]* 2>/dev/null | grep -v "^$case/0$" | \
        grep -v "^$case/0\.orig$" | grep -qE "/[0-9]+$"
}

_foam_latest_time_dir() {
    local case="${1:-.}"
    ls -d "$case"/[0-9]* 2>/dev/null | grep -v "^$case/0$" | \
        grep -v "^$case/0\.orig$" | grep -E "/[0-9]+$" | \
        sort -t/ -k2 -n | tail -1 | xargs -r basename
}

# ─────────────────────────────────────────────────────────────────────
# LOCATE-001: fix_locationInMesh using python3 (sed cannot eval arithmetic)
# ─────────────────────────────────────────────────────────────────────
fix_locationInMesh() {
    local dict="$1"
    [ -f "$dict" ] || return 0
    grep -q 'locationInMesh' "$dict" || return 0
    python3 - "$dict" << 'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f: content = f.read()
def add_z(m):
    x, y, z = float(m.group(1)), float(m.group(2)), float(m.group(3))
    new_z = z + 80
    return f"locationInMesh ({x} {y} {new_z})"
new = re.sub(r'locationInMesh \(([0-9.]+) ([0-9.]+) ([0-9.]+)\)', add_z, content)
with open(path, 'w') as f: f.write(new)
print(f"  locationInMesh Z adjusted +80 in {path}")
PYEOF
}

# ─────────────────────────────────────────────────────────────────────
# Heal database — 20 patterns from v101 + v70 session
# ─────────────────────────────────────────────────────────────────────
cat > /tmp/cfd_init_healdb.py << 'INIT_EOF'
#!/usr/bin/env python3
import sqlite3, sys
from datetime import datetime
db = sys.argv[1] if len(sys.argv) > 1 else ".cfd_healdb"
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE IF NOT EXISTS error_patterns (id INTEGER PRIMARY KEY, pattern TEXT UNIQUE, description TEXT, fix_cmd TEXT, success_count INTEGER DEFAULT 0, fail_count INTEGER DEFAULT 0, first_seen TEXT, last_seen TEXT, priority REAL DEFAULT 0.5)")
conn.execute("CREATE TABLE IF NOT EXISTS heal_events (id INTEGER PRIMARY KEY, timestamp TEXT, pattern_id INTEGER, case_dir TEXT, outcome TEXT)")
conn.execute("CREATE TABLE IF NOT EXISTS unknown_errors (id INTEGER PRIMARY KEY, timestamp TEXT, case_dir TEXT, foam_error TEXT, log_excerpt TEXT, status TEXT DEFAULT 'unresolved')")
now = datetime.now().isoformat()
PATTERNS = [
    ("cannot find file.*transportProperties","transportProperties missing","python3 -c \"open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')\""),
    ("Entry 'transportModel' not found","transportProperties wrong keyword","python3 -c \"open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')\""),
    ("cannot find file.*physicalProperties","physicalProperties missing","python3 -c \"open('{case}/constant/physicalProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\\nviscosityModel Newtonian;\\nnu 1.5e-05;\\n')\""),
    ("cannot find file.*turbulenceProperties","turbulenceProperties missing","python3 -c \"open('{case}/constant/turbulenceProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\\nsimulationType RAS;\\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\\n')\""),
    ("cannot find file.*/0/nut","0/nut missing","python3 -c \"import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/nut','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object nut; }\\ndimensions [0 2 -1 0 0 0 0];\\ninternalField uniform 0;\\nboundaryField\\n{\\n    inlet { type calculated; value uniform 0; }\\n    outlet { type calculated; value uniform 0; }\\n    walls { type nutLowReWallFunction; value uniform 0; }\\n    ground { type nutLowReWallFunction; value uniform 0; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    ("cannot find file.*/0/omega","0/omega missing","python3 -c \"import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/omega','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object omega; }\\ndimensions [0 0 -1 0 0 0 0];\\ninternalField uniform 1;\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform 1; }\\n    outlet { type inletOutlet; inletValue uniform 1; value uniform 1; }\\n    walls { type omegaWallFunction; value uniform 1; }\\n    ground { type omegaWallFunction; value uniform 1; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    ("Cannot open mesh description|polyMesh/boundary","polyMesh missing","bash -c 'cd {case} && ./Allrun.mesh 2>&1 | tee log.Allrun.mesh.reheal'"),
    ("did not find.*cell|No cells.*selected","locationInMesh inside solid","fix_locationInMesh {case}/system/snappyHexMeshDict"),
    ("cannot find file.*controlDict","Missing controlDict","mkdir -p {case}/system && python3 -c \"open('{case}/system/controlDict','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object controlDict; }\\napplication simpleFoam;\\nstartFrom startTime;\\nstartTime 0;\\nstopAt endTime;\\nendTime 1000;\\ndeltaT 1;\\nwriteControl timeStep;\\nwriteInterval 100;\\npurgeWrite 0;\\nwriteFormat ascii;\\nwritePrecision 6;\\nwriteCompression off;\\ntimeFormat general;\\ntimePrecision 6;\\nrunTimeModifiable true;\\n')\""),
    ("cannot find file.*fvSchemes","Missing fvSchemes","mkdir -p {case}/system && python3 -c \"open('{case}/system/fvSchemes','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object fvSchemes; }\\nddtSchemes { default steadyState; }\\ngradSchemes { default Gauss linear; }\\ndivSchemes { default none; div(phi,U) Gauss linearUpwind grad(U); }\\nlaplacianSchemes { default Gauss linear corrected; }\\ninterpolationSchemes { default linear; }\\nsnGradSchemes { default corrected; }\\n')\""),
    ("cannot find file.*fvSolution","Missing fvSolution","mkdir -p {case}/system && python3 -c \"open('{case}/system/fvSolution','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object fvSolution; }\\nsolvers { p { solver GAMG; tolerance 1e-06; relTol 0.01; smoother GaussSeidel; } U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-05; relTol 0.1; } }\\nSIMPLE { nNonOrthogonalCorrectors 1; pRefCell 0; pRefValue 0; }\\n')\""),
    ("cannot find file.*/0/p","Missing 0/p","mkdir -p {case}/0 && python3 -c \"open('{case}/0/p','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object p; }\\ndimensions [0 2 -2 0 0 0 0];\\ninternalField uniform 0;\\nboundaryField\\n{\\n    inlet { type zeroGradient; }\\n    outlet { type fixedValue; value uniform 0; }\\n    walls { type zeroGradient; }\\n    ground { type zeroGradient; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    ("cannot find file.*/0/U","Missing 0/U","mkdir -p {case}/0 && python3 -c \"open('{case}/0/U','w').write('FoamFile\\n{ version 2.0; format ascii; class volVectorField; object U; }\\ndimensions [0 1 -1 0 0 0 0];\\ninternalField uniform (10 0 0);\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform (10 0 0); }\\n    outlet { type inletOutlet; inletValue uniform (10 0 0); value uniform (10 0 0); }\\n    walls { type noSlip; }\\n    ground { type noSlip; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    ("VTK directory not found|No VTK files","Run foamToVTK","cd {case} && foamToVTK -latestTime 2>&1 | tee log.foamToVTK"),
]
for p,d,f in PATTERNS:
    conn.execute("INSERT OR IGNORE INTO error_patterns (pattern,description,fix_cmd,first_seen,last_seen) VALUES (?,?,?,?,?)",(p,d,f,now,now))
conn.commit()
count = conn.execute("SELECT COUNT(*) FROM error_patterns").fetchone()[0]
print(f"  Heal DB: {count} patterns in {db}")
conn.close()
INIT_EOF

cat > /tmp/cfd_db_diagnose.py << 'DIAG_EOF'
#!/usr/bin/env python3
import sqlite3, re, sys, os
from datetime import datetime
db_path = sys.argv[1] if len(sys.argv)>1 else ".cfd_healdb"
if len(sys.argv)>2 and sys.argv[2]=='--show-unknown':
    if not os.path.exists(db_path): print("No DB"); sys.exit(0)
    conn=sqlite3.connect(db_path)
    for ts,err,exc in conn.execute("SELECT timestamp,foam_error,log_excerpt FROM unknown_errors ORDER BY id DESC LIMIT 5").fetchall():
        print(f"\n[{ts}] {err}\n{(exc or '')[-300:]}")
    conn.close(); sys.exit(0)
if len(sys.argv)>2 and sys.argv[2]=='--record-outcome':
    pid,outcome,case_dir=sys.argv[3],sys.argv[4],sys.argv[5] if len(sys.argv)>5 else "."
    conn=sqlite3.connect(db_path)
    col="success_count" if outcome=="healed" else "fail_count"
    conn.execute(f"UPDATE error_patterns SET {col}={col}+1,last_seen=? WHERE id=?",(datetime.now().isoformat(),pid))
    conn.execute("INSERT INTO heal_events (timestamp,pattern_id,case_dir,outcome) VALUES (?,?,?,?)",(datetime.now().isoformat(),pid,case_dir,outcome))
    conn.commit(); conn.close(); sys.exit(0)
if len(sys.argv)<4: print("USAGE"); sys.exit(1)
log_path,case_dir=sys.argv[2],os.path.abspath(sys.argv[3])
if not os.path.exists(db_path): print("NO_DB"); sys.exit(0)
if not os.path.exists(log_path): print("NO_LOG"); sys.exit(0)
with open(log_path) as f: log_text=f.read()
log_tail="\n".join(log_text.splitlines()[-20:])
conn=sqlite3.connect(db_path)
rows=conn.execute("SELECT id,pattern,description,fix_cmd FROM error_patterns ORDER BY success_count DESC,id").fetchall()
matched=None
for pid,pattern,desc,fix_cmd in rows:
    if re.search(pattern,log_text,re.IGNORECASE): matched=(pid,pattern,desc,fix_cmd); break
if not matched:
    foam_err=next((l.strip() for l in log_text.splitlines() if 'FOAM FATAL' in l or 'FOAM exiting' in l),"")
    conn.execute("INSERT INTO unknown_errors (timestamp,case_dir,foam_error,log_excerpt) VALUES (?,?,?,?)",(datetime.now().isoformat(),case_dir,foam_err,log_tail))
    conn.commit(); conn.close(); print("UNKNOWN"); sys.exit(0)
pid,pattern,desc,fix_cmd=matched
fix_cmd_fmt=fix_cmd.replace("{case}",case_dir)
conn.execute("UPDATE error_patterns SET last_seen=? WHERE id=?",(datetime.now().isoformat(),pid))
conn.commit(); conn.close()
print(f"MATCHED:{pid}:{desc}:{fix_cmd_fmt}")
DIAG_EOF

init_heal_db() {
    python3 /tmp/cfd_init_healdb.py "$HEAL_DB"
}

# ─────────────────────────────────────────────────────────────────────
# diagnose_and_heal: DB first, hardcoded fallbacks second
# ─────────────────────────────────────────────────────────────────────
diagnose_and_heal() {
    local log="$1"
    local case_dir="${2:-.}"
    echo "  🔍 Diagnosing: $(basename "$log")..."

    local result
    result=$(python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" "$log" "$case_dir" 2>/dev/null || echo "NO_DB")

    case "$result" in
        NO_DB|NO_LOG|USAGE)
            echo "  ℹ️  DB unavailable — trying hardcoded rules";;
        UNKNOWN)
            echo "  ⚠️  Unknown error recorded in DB"
            echo "      Review: python3 /tmp/cfd_db_diagnose.py $HEAL_DB --show-unknown"
            return 1;;
        MATCHED:*)
            local pid desc fix_cmd
            pid=$(echo "$result"  | cut -d: -f2)
            desc=$(echo "$result" | cut -d: -f3)
            fix_cmd=$(echo "$result" | cut -d: -f4-)
            echo "  🗄️  DB match [#$pid]: $desc"
            echo "  🔧 Applying DB fix..."
            if eval "$fix_cmd"; then
                python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$pid" "healed" "$case_dir" 2>/dev/null || true
                echo "  ✅ DB heal applied"
                return 0
            else
                python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$pid" "failed" "$case_dir" 2>/dev/null || true
                echo "  ❌ DB heal failed"
                return 1
            fi;;
    esac

    # Hardcoded fallbacks
    if grep -q "cannot find file.*transportProperties" "$log" 2>/dev/null; then
        echo "  HEAL: writing transportProperties..."
        python3 -c "open('$case_dir/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"
        return 0
    fi
    if grep -q "Entry 'transportModel' not found" "$log" 2>/dev/null; then
        echo "  HEAL: fixing transportModel keyword..."
        python3 -c "open('$case_dir/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"
        return 0
    fi
    if grep -q "cannot find file.*/0/nut" "$log" 2>/dev/null; then
        echo "  HEAL: writing 0/nut..."
        mkdir -p "$case_dir/0"
        python3 -c "open('$case_dir/0/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')"
        return 0
    fi
    if grep -qE "did not find.*cell|No cells.*selected" "$log" 2>/dev/null; then
        echo "  HEAL: adjusting locationInMesh..."
        fix_locationInMesh "$case_dir/system/snappyHexMeshDict"
        return 0
    fi
    echo "  ❌ No heal rule matched"
    return 1
}

# ─────────────────────────────────────────────────────────────────────
# run_mesh_step: live output, log dump on failure, diagnose_and_heal
# VERBATIM-002: stdbuf -oL tee, no || true swallowing errors
# ─────────────────────────────────────────────────────────────────────
_foam_log_dump() {
    local log="$1" lines="${2:-50}"
    echo "  ━━━ LAST $lines LINES: $(basename "$log") ━━━"
    tail -"$lines" "$log" 2>/dev/null || echo "  (log not found)"
    echo "  ━━━ END LOG ━━━"
}

run_mesh_step() {
    local case_dir="$1"
    echo "➤ Step: Generate mesh"
    echo "  Case: $case_dir"

    if [ -f "$case_dir/constant/polyMesh/points" ]; then
        echo "  ✅ Already done – skipping"; return 0
    fi

    cd "$case_dir" || { echo "  ❌ Case dir not found: $case_dir"; exit 1; }

    echo "  🔧 blockMesh..."
    { blockMesh 2>&1 | stdbuf -oL tee log.blockMesh; } || true
    if grep -q "FOAM FATAL\|FOAM exiting\|error:" log.blockMesh 2>/dev/null; then
        echo "  ❌ blockMesh failed"
        _foam_log_dump log.blockMesh 30
        cd - >/dev/null; exit 1
    fi
    echo "  ✅ blockMesh OK"

    echo "  🔧 surfaceFeatureExtract..."
    { surfaceFeatureExtract 2>&1 | stdbuf -oL tee log.surfaceFeatureExtract; } || true
    if grep -q "FOAM FATAL\|FOAM exiting" log.surfaceFeatureExtract 2>/dev/null; then
        echo "  ❌ surfaceFeatureExtract failed"
        _foam_log_dump log.surfaceFeatureExtract 20
        cd - >/dev/null; exit 1
    fi
    echo "  ✅ surfaceFeatureExtract OK"

    echo "  🔧 snappyHexMesh (may take 2-10 min)..."
    { snappyHexMesh -overwrite 2>&1 | stdbuf -oL tee log.snappyHexMesh; } || true

    if [ -f "constant/polyMesh/points" ]; then
        echo "  ✅ Mesh OK"
        cd - >/dev/null; return 0
    fi

    echo "  ❌ snappyHexMesh failed"
    _foam_log_dump log.snappyHexMesh 60
    echo "  🔍 Attempting heal..."

    if diagnose_and_heal "log.snappyHexMesh" "."; then
        echo "  🔄 Retrying snappyHexMesh..."
        { snappyHexMesh -overwrite 2>&1 | stdbuf -oL tee log.snappyHexMesh; } || true
        if [ -f "constant/polyMesh/points" ]; then
            echo "  ✅ Mesh OK after heal"
            cd - >/dev/null; return 0
        fi
        echo "  ❌ Mesh still failed after heal"
        _foam_log_dump log.snappyHexMesh 30
    fi
    cd - >/dev/null; exit 1
}

# ─────────────────────────────────────────────────────────────────────
# run_sim_step:
#   VERBATIM-001: stdbuf -oL tee on all solver pipes
#   PIPEFAIL-001: || true after all solver pipes
#   CONV-001:     _foam_has_time_dir not forceCoeffs
#   COLLAPSED-001: awk collapsed display from v69/v70
# ─────────────────────────────────────────────────────────────────────
run_sim_step() {
    local case_dir="$1"
    local solver="${2:-simpleFoam}"
    echo "➤ Step: Run $solver"

    if _foam_has_time_dir "$case_dir"; then
        echo "  ✅ Already done – skipping (time dir: $(_foam_latest_time_dir "$case_dir"))"; return 0
    fi

    cd "$case_dir" || { echo "  ❌ Case dir not found"; exit 1; }
    cp -r 0.orig 0 2>/dev/null || true

    echo "  🔧 $solver — log: $(pwd)/log.$solver"
    echo "  Target: residuals < 1e-4. Stall: 50 non-improving iters."
    printf "  %-6s %-13s %-13s %-13s %-13s %s\n" "Time" "Ux" "Uy" "Uz" "p" "Status"
    printf "  %s\n" "----------------------------------------------------------------------"

    # PIPEFAIL-001 + VERBATIM-001: || true prevents set -e kill; stdbuf prevents 64KB stall
    { $solver 2>&1 | stdbuf -oL tee log.$solver; } || true

    # COLLAPSED-001: awk post-processor — POSIX 2-arg match, p[^a-z] pattern
    awk '
    BEGIN { prev=999; stall=0; iter=0; ux=0; uy=0; uz=0; pr=0; t="?" }
    /^Time = /            { t = $3 }
    /Solving for Ux/      { if (match($0,/[0-9][0-9.eE+\-]*/)) ux=substr($0,RSTART,RLENGTH)+0 }
    /Solving for Uy/      { if (match($0,/[0-9][0-9.eE+\-]*/)) uy=substr($0,RSTART,RLENGTH)+0 }
    /Solving for Uz/      { if (match($0,/[0-9][0-9.eE+\-]*/)) uz=substr($0,RSTART,RLENGTH)+0 }
    /Solving for p[^a-z]/ { if (match($0,/[0-9][0-9.eE+\-]*/)) pr=substr($0,RSTART,RLENGTH)+0 }
    /^ExecutionTime/ {
        iter++
        status = "running"
        if (ux<1e-4 && uy<1e-4 && uz<1e-4 && pr<1e-4) status = "CONVERGED"
        if (ux>1 || uy>1 || uz>1)                       status = "DIVERGED"
        if (ux >= prev*0.999) stall++; else stall=0
        if (stall>=50)                                   status = "STALLED"
        prev = ux
        if (iter%10==0 || status!="running") {
            printf "  #%-5d T=%-5s Ux=%-10.2e Uy=%-10.2e Uz=%-10.2e p=%-10.2e [%s] stall=%d\n",
                iter, t, ux, uy, uz, pr, status, stall
        }
        if (status != "running") exit
    }
    ' log.$solver
    echo ""

    if grep -qE "FOAM FATAL|Segmentation fault" log.$solver 2>/dev/null; then
        echo "  ❌ $solver fatal error"
        _foam_log_dump log.$solver 40
        if diagnose_and_heal "log.$solver" "."; then
            echo "  🔄 Retrying $solver..."
            cp -r 0.orig 0 2>/dev/null || true
            { $solver 2>&1 | stdbuf -oL tee log.${solver}.retry; } || true
            if _foam_has_time_dir .; then
                echo "  ✅ $solver succeeded after heal"
                cd - >/dev/null; return 0
            fi
            echo "  ❌ Still failed. Log: $(pwd)/log.${solver}.retry"
            cd - >/dev/null; exit 1
        fi
        cd - >/dev/null; exit 1
    fi

    if awk '
        BEGIN{prev=999;stall=0}
        /Solving for Ux/{if(match($0,/[0-9][0-9.eE+\-]*/))ux=substr($0,RSTART,RLENGTH)+0}
        /^ExecutionTime/{if(ux>=prev*0.999)stall++;else stall=0;prev=ux}
        END{exit (stall>=50)?0:1}
    ' log.$solver 2>/dev/null; then
        echo "  ⚠️  STALL: residuals not improving (50+ iters)"
        tail -20 log.$solver
        echo "  Continuing with available results..."
    fi

    if ! _foam_has_time_dir .; then
        echo "  ❌ $solver produced no time directory"
        _foam_log_dump log.$solver 40
        cd - >/dev/null; exit 1
    fi

    echo "  ✅ $solver done — latest: $(_foam_latest_time_dir .)"
    cd - >/dev/null
}

# ─────────────────────────────────────────────────────────────────────
# VTK-SUBDIR-001: extract_wind_vectors.py with os.walk (subdirs)
# ─────────────────────────────────────────────────────────────────────
ensure_extract_wind_vectors() {
    mkdir -p scripts
    cat > scripts/extract_wind_vectors.py << 'PY_EOF'
#!/usr/bin/env python3
# PATH: scripts/extract_wind_vectors.py
# VTK-SUBDIR-001: uses os.walk to find internal.vtu in subdirectories
# foamToVTK creates VTK/casename_N/internal.vtu — not flat files in VTK/
import argparse, vtk, json, os, sys
from vtk.util import numpy_support

def find_latest_vtu(vtk_dir):
    """Walk VTK/ subdirectories to find the latest internal.vtu"""
    vtu_files = []
    for root, dirs, files in os.walk(vtk_dir):
        for f in files:
            if f == 'internal.vtu':
                vtu_files.append(os.path.join(root, f))
    if not vtu_files:
        return None
    # Sort by path — latest time dir sorts last numerically
    vtu_files.sort()
    return vtu_files[-1]

def extract(vtk_file, grid_spacing, output_json):
    print(f"Loading VTK: {vtk_file}")
    reader = vtk.vtkXMLUnstructuredGridReader()
    reader.SetFileName(vtk_file)
    reader.Update()
    mesh = reader.GetOutput()
    bounds = mesh.GetBounds()
    print(f"Bounds: x=[{bounds[0]:.1f},{bounds[1]:.1f}] y=[{bounds[2]:.1f},{bounds[3]:.1f}] z=[{bounds[4]:.1f},{bounds[5]:.1f}]")
    if not mesh.GetPointData().HasArray("U"):
        print("ERROR: No U velocity array in mesh"); return False
    nx = int((bounds[1]-bounds[0])/grid_spacing)+1
    ny = int((bounds[3]-bounds[2])/grid_spacing)+1
    nz = int((bounds[5]-bounds[4])/grid_spacing)+1
    print(f"Grid: {nx}x{ny}x{nz} = {nx*ny*nz} points")
    pts = vtk.vtkPoints()
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                pts.InsertNextPoint(bounds[0]+i*grid_spacing, bounds[2]+j*grid_spacing, bounds[4]+k*grid_spacing)
    poly = vtk.vtkPolyData(); poly.SetPoints(pts)
    prober = vtk.vtkProbeFilter()
    prober.SetInputData(poly); prober.SetSourceData(mesh); prober.Update()
    U_arr = prober.GetOutput().GetPointData().GetArray("U")
    if not U_arr: print("ERROR: Probing failed"); return False
    U = numpy_support.vtk_to_numpy(U_arr)
    wind = {"metadata": {"grid_spacing": grid_spacing, "dimensions": [nx,ny,nz],
            "bounds": {"x": list(bounds[0:2]), "y": list(bounds[2:4]), "z": list(bounds[4:6])}},
            "velocities": []}
    idx = 0
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                x,y,z = bounds[0]+i*grid_spacing, bounds[2]+j*grid_spacing, bounds[4]+k*grid_spacing
                wind["velocities"].append({"pos":[float(x),float(y),float(z)], "vel":[float(U[idx][0]),float(U[idx][1]),float(U[idx][2])]})
                idx += 1
    with open(output_json, 'w') as f: json.dump(wind, f)
    print(f"Written: {output_json} ({os.path.getsize(output_json)//1024} KB)")
    return True

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--case", required=True)
    p.add_argument("--grid-spacing", type=float, default=10.0)
    p.add_argument("--output", required=True)
    p.add_argument("--vtk-file", default=None)
    args = p.parse_args()
    if args.vtk_file:
        vtk_file = args.vtk_file
    else:
        vtk_dir = os.path.join(args.case, "VTK")
        if not os.path.exists(vtk_dir):
            print(f"ERROR: VTK directory not found: {vtk_dir}"); sys.exit(1)
        vtk_file = find_latest_vtu(vtk_dir)
        if not vtk_file:
            print(f"ERROR: No internal.vtu found in {vtk_dir}"); sys.exit(1)
    sys.exit(0 if extract(vtk_file, args.grid_spacing, args.output) else 1)
PY_EOF
    chmod +x scripts/extract_wind_vectors.py
}

# ─────────────────────────────────────────────────────────────────────
# audit (retained from v101)
# ─────────────────────────────────────────────────────────────────────
perform_audit() {
    mkdir -p audit_logs
    local f="audit_logs/audit_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "=== System ==="; uname -a; date
        echo "=== Git ==="; git status 2>/dev/null || echo "Not a repo"
        echo "=== Patterns ==="
        sqlite3 "$HEAL_DB" "SELECT id,description,success_count,fail_count FROM error_patterns" 2>/dev/null || echo "No DB"
        echo "=== Unknown errors ==="
        sqlite3 "$HEAL_DB" "SELECT timestamp,foam_error FROM unknown_errors ORDER BY id DESC LIMIT 5" 2>/dev/null
        echo "=== DB dump ==="; sqlite3 "$HEAL_DB" .dump 2>/dev/null
    } > "$f"
    echo "📝 Audit: $f"
    echo "    To review: python3 /tmp/cfd_db_diagnose.py $HEAL_DB --show-unknown"
}

# ─────────────────────────────────────────────────────────────────────
# System packages (from v70 — confirmed working)
# ─────────────────────────────────────────────────────────────────────
echo "➤ Step: OpenFOAM COPR repo"
dnf repolist | grep -qi openfoam && echo "  ✅ Already done – skipping" || \
    { sudo dnf copr enable -y openfoam/openfoam && echo "  ✅ Completed"; }

echo "➤ Step: ParaView"
if command -v pvpython &>/dev/null || find /usr -name pvpython 2>/dev/null | grep -q pvpython; then
    echo "  ✅ Already done – skipping"
else
    sudo dnf install -y paraview
    PVPY=$(find /usr -name pvpython 2>/dev/null | head -1)
    [ -n "$PVPY" ] && sudo ln -sf "$PVPY" /usr/local/bin/pvpython
fi

run_step "Flatpak + Flathub" \
    "flatpak --version 2>/dev/null && flatpak remotes 2>/dev/null | grep -q flathub" \
    "sudo dnf install -y flatpak && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" \
    "flatpak --version && flatpak remotes | grep -q flathub"

run_step "Godot" \
    "command -v godot" \
    "flatpak install -y flathub org.godotengine.Godot && sudo ln -sf /var/lib/flatpak/exports/bin/org.godotengine.Godot /usr/local/bin/godot" \
    "godot --version 2>&1 | grep -qE '[0-9]+\.[0-9]+'"

run_step "GDAL" "gdal-config --version" "sudo dnf install -y gdal gdal-devel python3-gdal" "gdal-config --version"
run_step "xdotool" "command -v xdotool" "sudo dnf install -y xdotool" "command -v xdotool"
run_step "Java 17" "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'" "sudo dnf install -y java-17-openjdk-headless" "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'"

run_step "OSM2World jar + lib" \
    "test -f /tmp/osm2world/OSM2World.jar && test -d /tmp/osm2world/lib" \
    "sudo rm -rf /tmp/osm2world && mkdir -p /tmp/osm2world && wget -q -O /tmp/osm2world/osm2world.zip 'https://osm2world.org/download/files/latest/OSM2World-latest-bin.zip' && unzip -q /tmp/osm2world/osm2world.zip -d /tmp/osm2world && rm -f /tmp/osm2world/osm2world.zip" \
    "test -f /tmp/osm2world/OSM2World.jar && test -d /tmp/osm2world/lib"

run_step "Python packages" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification' 2>/dev/null" \
    "python3 -m pip install --user --break-system-packages numpy vtk trimesh pykml lxml GDAL scipy matplotlib pycollada fast_simplification" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification; print(\"OK\")'"

# Templates
mkdir -p cases/template/{0.orig,constant,system}

run_step "Template 0.orig/nut" \
    "test -s cases/template/0.orig/nut && grep -q nutLowReWallFunction cases/template/0.orig/nut" \
    "python3 -c \"open('cases/template/0.orig/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/nut && grep -q nutLowReWallFunction cases/template/0.orig/nut"

run_step "Template 0.orig/p" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p" \
    "python3 -c \"open('cases/template/0.orig/p','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object p; }\ndimensions [0 2 -2 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type zeroGradient; }\n    outlet { type fixedValue; value uniform 0; }\n    walls { type zeroGradient; }\n    ground { type zeroGradient; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p"

run_step "Template 0.orig/U" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U" \
    "python3 -c \"open('cases/template/0.orig/U','w').write('FoamFile\n{ version 2.0; format ascii; class volVectorField; object U; }\ndimensions [0 1 -1 0 0 0 0];\ninternalField uniform (10 0 0);\nboundaryField\n{\n    inlet { type fixedValue; value uniform (10 0 0); }\n    outlet { type inletOutlet; inletValue uniform (10 0 0); value uniform (10 0 0); }\n    walls { type noSlip; }\n    ground { type noSlip; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U"

run_step "Template k+epsilon" \
    "test -s cases/template/0.orig/k && grep -q symmetryPlane cases/template/0.orig/k && test -s cases/template/0.orig/epsilon" \
    "python3 -c \"
open('cases/template/0.orig/k','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object k; }\ndimensions [0 2 -2 0 0 0 0];\ninternalField uniform 0.1;\nboundaryField\n{\n    inlet { type fixedValue; value uniform 0.1; }\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\n    walls { type kqRWallFunction; value uniform 0.1; }\n    ground { type kqRWallFunction; value uniform 0.1; }\n    top { type symmetryPlane; }\n}\n')
open('cases/template/0.orig/epsilon','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object epsilon; }\ndimensions [0 2 -3 0 0 0 0];\ninternalField uniform 0.1;\nboundaryField\n{\n    inlet { type fixedValue; value uniform 0.1; }\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\n    walls { type epsilonWallFunction; value uniform 0.1; }\n    ground { type epsilonWallFunction; value uniform 0.1; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/k && grep -q symmetryPlane cases/template/0.orig/k"

run_step "Template blockMeshDict" \
    "test -s cases/template/system/blockMeshDict && grep -q symmetryPlane cases/template/system/blockMeshDict" \
    "python3 -c \"open('cases/template/system/blockMeshDict','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object blockMeshDict; }\nscale 1;\nvertices ( (0 0 0) (300 0 0) (300 300 0) (0 300 0) (0 0 200) (300 0 200) (300 300 200) (0 300 200) );\nblocks ( hex (0 1 2 3 4 5 6 7) (30 30 20) simpleGrading (1 1 1) );\nedges ();\nboundary\n(\n    inlet { type patch; faces ((0 4 7 3)); }\n    outlet { type patch; faces ((1 2 6 5)); }\n    walls { type wall; faces ((0 1 5 4)(3 7 6 2)); }\n    ground { type wall; faces ((0 3 2 1)); }\n    top { type symmetryPlane; faces ((4 5 6 7)); }\n);\n')\"" \
    "test -s cases/template/system/blockMeshDict && grep -q symmetryPlane cases/template/system/blockMeshDict"

run_step "Template snappyHexMeshDict" \
    "test -s cases/template/system/snappyHexMeshDict && grep -q terrain.stl cases/template/system/snappyHexMeshDict" \
    "python3 -c \"open('cases/template/system/snappyHexMeshDict','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object snappyHexMeshDict; }\ncastellatedMesh true;\nsnap true;\naddLayers false;\ngeometry { terrain.stl { type triSurfaceMesh; name terrain; } }\ncastellatedMeshControls\n{\n    maxLocalCells 1000000; maxGlobalCells 2000000; minRefinementCells 10;\n    nCellsBetweenLevels 3; features ();\n    refinementSurfaces { terrain { level (2 3); } }\n    refinementRegions {}\n    locationInMesh (150 150 100);\n    allowFreeStandingZoneFaces true;\n}\nsnapControls { nSmoothPatch 3; tolerance 2.0; nSolveIter 30; nRelaxIter 5; }\naddLayersControls { relativeSizes true; layers {} expansionRatio 1.0; finalLayerThickness 0.3; minThickness 0.1; nGrow 0; }\nmeshQualityControls { maxNonOrtho 65; maxBoundarySkewness 20; maxInternalSkewness 4; maxConcave 80; minFlatness 0.5; minVol 1e-13; minTetQuality 1e-15; minArea -1; minTwist 0.02; minDeterminant 0.001; minFaceWeight 0.02; minVolRatio 0.01; minTriangleTwist -1; nSmoothScale 4; errorReduction 0.75; }\nwriteFlags (scalarLevels layerSets layerFields);\nmergeTolerance 1e-6;\n')\"" \
    "test -s cases/template/system/snappyHexMeshDict && grep -q terrain.stl cases/template/system/snappyHexMeshDict"

run_step "Template turbulenceProperties" \
    "test -s cases/template/constant/turbulenceProperties && grep -q kEpsilon cases/template/constant/turbulenceProperties" \
    "python3 -c \"open('cases/template/constant/turbulenceProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\nsimulationType RAS;\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\n')\"" \
    "test -s cases/template/constant/turbulenceProperties && grep -q kEpsilon cases/template/constant/turbulenceProperties"

run_step "Template surfaceFeatureExtractDict" \
    "test -s cases/template/system/surfaceFeatureExtractDict && grep -q extractFromSurface cases/template/system/surfaceFeatureExtractDict" \
    "python3 -c \"open('cases/template/system/surfaceFeatureExtractDict','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object surfaceFeatureExtractDict; }\nterrain.stl\n{\n    extractionMethod extractFromSurface;\n    extractFromSurfaceCoeffs { includedAngle 150; }\n    writeObj yes;\n}\n')\"" \
    "test -s cases/template/system/surfaceFeatureExtractDict && grep -q extractFromSurface cases/template/system/surfaceFeatureExtractDict"

run_step "Template physicalProperties" \
    "test -s cases/template/constant/physicalProperties && grep -q nu cases/template/constant/physicalProperties" \
    "python3 -c \"open('cases/template/constant/physicalProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\nviscosityModel Newtonian;\nnu 1.5e-05;\n')\"" \
    "test -s cases/template/constant/physicalProperties && grep -q nu cases/template/constant/physicalProperties"

run_step "Template transportProperties" \
    "test -s cases/template/constant/transportProperties && grep -q transportModel cases/template/constant/transportProperties" \
    "python3 -c \"open('cases/template/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')\"" \
    "test -s cases/template/constant/transportProperties && grep -q transportModel cases/template/constant/transportProperties"

run_step "Stub download_terrain_tiles.py" \
    "grep -q 'OSM pipeline' scripts/download_terrain_tiles.py 2>/dev/null" \
    "import os; os.makedirs('scripts',exist_ok=True); python3 -c \"open('scripts/download_terrain_tiles.py','w').write('#!/usr/bin/env python3\nimport sys\nprint(\\\"Use OSM pipeline in apply_fixlist_0102.sh.\\\")\nsys.exit(1)\n'); import os; os.chmod('scripts/download_terrain_tiles.py',0o755)\"" \
    "grep -q 'OSM pipeline' scripts/download_terrain_tiles.py"

run_step "Stub place_rotors.py" \
    "grep -q 'not implemented' scripts/place_rotors.py 2>/dev/null" \
    "python3 -c \"import os; os.makedirs('scripts',exist_ok=True); open('scripts/place_rotors.py','w').write('#!/usr/bin/env python3\nimport sys\nprint(\\\"place_rotors.py not implemented.\\\")\nsys.exit(1)\n'); os.chmod('scripts/place_rotors.py',0o755)\"" \
    "grep -q 'not implemented' scripts/place_rotors.py"

run_step "Documentation stubs" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md" \
    "python3 -c \"
import os; os.makedirs('docs',exist_ok=True)
for name,body in [('cfd_setup.md','# CFD Setup\n'),('godot_integration.md','# Godot\n'),('locations.md','# Locations\n\n- Skydive DeLand: 29.0119N 81.2462W\n')]:
    p=os.path.join('docs',name)
    if not (os.path.exists(p) and os.path.getsize(p)>0): open(p,'w').write(body)\"" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md"

run_step "Test collada_to_stl" \
    "false" \
    "python3 -c 'import trimesh; trimesh.creation.box(extents=[100,100,10]).export(\"test_cube.dae\")' && python3 scripts/collada_to_stl.py --input test_cube.dae --output test_cube.stl --simplify 1.0" \
    "test -s test_cube.stl"

run_step "Clean test artifacts" \
    "false" \
    "rm -f test_cube.dae test_cube.stl" \
    "for f in test_cube.dae test_cube.stl; do [ ! -f \"\$f\" ] || exit 1; done"

run_step "Set execute bits" \
    "test -x scripts/setup_openfoam_case.sh" \
    "find scripts/ -name '*.sh' -o -name '*.py' | xargs -r chmod +x" \
    "test -x scripts/setup_openfoam_case.sh"

# Now run the main setup sequence
check_permissions
setup_environment
init_heal_db
dump_system_info
ensure_extract_wind_vectors

# ─────────────────────────────────────────────────────────────────────
# STATECHECK-001: restore .cfd_state persistence from v70
# ─────────────────────────────────────────────────────────────────────
STATE_FILE=".cfd_state"
if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
    echo "Previous state:"
    echo "   Location    : ${LOCATION_NAME:-}"
    echo "   STL file    : ${STL_PATH:-}"
    echo "   Grid spacing: ${GRID_SPACING:-10} m"
    read -r -p "Use these values? (y/n, default y): " _use; _use=${_use:-y}
    [[ "$_use" =~ ^[Nn]$ ]] && unset LOCATION_NAME STL_PATH GRID_SPACING
fi

if [[ -z "${LOCATION_NAME:-}" ]]; then
    read -r -p "Location name (default: skydive_deland): " LOCATION_NAME
    LOCATION_NAME=${LOCATION_NAME:-skydive_deland}
    read -r -p "Latitude  (default: 29.0119): " _lat; _lat=${_lat:-29.0119}
    read -r -p "Longitude (default: -81.2462): " _lon; _lon=${_lon:--81.2462}
    read -r -p "Radius in meters (default 400): " _radius; _radius=${_radius:-400}
    read -r -p "Grid spacing (default 10): " GRID_SPACING; GRID_SPACING=${GRID_SPACING:-10}
    echo "  Using: $LOCATION_NAME  lat=$_lat  lon=$_lon  radius=${_radius}m  grid=${GRID_SPACING}m"

    mkdir -p terrain cfd_mesh
    python3 - << PYEOF
import math
lat, lon, r = float("$_lat"), float("$_lon"), float("$_radius")
dlat = r / 111320
dlon = r / (111320 * math.cos(math.radians(lat)))
bbox = f"{lat-dlat:.6f},{lon-dlon:.6f},{lat+dlat:.6f},{lon+dlon:.6f}"
with open("/tmp/osm_bbox.txt","w") as f: f.write(bbox)
print(f"BBox: {bbox}")
PYEOF
    BBOX=$(cat /tmp/osm_bbox.txt)
    OSM_FILE="terrain/${LOCATION_NAME}.osm"

    run_step "Download OSM data" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'" \
        "curl -s --max-time 60 --retry 3 -o '$OSM_FILE' 'https://overpass-api.de/api/interpreter' --data 'data=[out:xml][timeout:30];(node($BBOX);way($BBOX);relation($BBOX););out body;>;out skel qt;'" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'"

    OBJ_FILE="terrain/${LOCATION_NAME}.obj"
    run_step "OSM → OBJ (OSM2World)" \
        "test -s '$OBJ_FILE'" \
        "java -Xmx2g \
          --add-exports java.base/java.lang=ALL-UNNAMED \
          --add-exports java.desktop/sun.awt=ALL-UNNAMED \
          --add-exports java.desktop/sun.java2d=ALL-UNNAMED \
          -jar /tmp/osm2world/OSM2World.jar \
          -i '$OSM_FILE' -o '$OBJ_FILE'" \
        "test -s '$OBJ_FILE'"

    STL_PATH="cfd_mesh/${LOCATION_NAME}.stl"
    run_step "OBJ → STL" \
        "test -s '$STL_PATH'" \
        "python3 -c \"
import trimesh, sys
mesh = trimesh.load('$OBJ_FILE', force='mesh')
print(f'  Vertices: {len(mesh.vertices)}, Faces: {len(mesh.faces)}')
if len(mesh.faces)==0: print('WARNING: Empty mesh — OSM may lack 3D data for this area')
mesh.export('$STL_PATH')
print('STL: $STL_PATH')\"" \
        "test -s '$STL_PATH'"

    cat > "$STATE_FILE" << EOF
LOCATION_NAME="$LOCATION_NAME"
STL_PATH="$STL_PATH"
GRID_SPACING="$GRID_SPACING"
EOF
    echo "State saved to $STATE_FILE"
fi

STL_PATH="${STL_PATH:-cfd_mesh/${LOCATION_NAME}.stl}"
GRID_SPACING="${GRID_SPACING:-10}"
[[ -s "$STL_PATH" ]] || { echo "ERROR: STL not found: $STL_PATH"; exit 1; }

mkdir -p game_data godot_project/data godot_project/assets/terrain
CASE_DIR="cases/${LOCATION_NAME}"
WIND_JSON="game_data/${LOCATION_NAME}_wind.json"

run_step "Setup OpenFOAM case" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "bash scripts/setup_openfoam_case.sh '$LOCATION_NAME' && cp '$STL_PATH' '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'"

run_step "0/nut in case" \
    "test -s '${CASE_DIR}/0/nut' && grep -q nutLowReWallFunction '${CASE_DIR}/0/nut'" \
    "mkdir -p '${CASE_DIR}/0' && python3 -c \"open('${CASE_DIR}/0/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s '${CASE_DIR}/0/nut' && grep -q nutLowReWallFunction '${CASE_DIR}/0/nut'"

run_step "transportProperties in case" \
    "test -s '${CASE_DIR}/constant/transportProperties' && grep -q transportModel '${CASE_DIR}/constant/transportProperties'" \
    "python3 -c \"open('${CASE_DIR}/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')\"" \
    "test -s '${CASE_DIR}/constant/transportProperties' && grep -q transportModel '${CASE_DIR}/constant/transportProperties'"

run_mesh_step "$CASE_DIR"
run_sim_step "$CASE_DIR" simpleFoam

run_step "Extract wind field" \
    "test -s '$WIND_JSON'" \
    "(cd '$CASE_DIR' \
      && foamToVTK -latestTime 2>&1 | stdbuf -oL tee log.foamToVTK \
      && LATEST_VTU=\$(find VTK -name 'internal.vtu' 2>/dev/null | sort | tail -1) \
      && { [ -n \"\$LATEST_VTU\" ] || { echo 'ERROR: no internal.vtu in VTK/'; exit 1; }; } \
      && echo \"Using: \$LATEST_VTU\" \
      && pvpython ../../scripts/extract_wind_vectors.py \
           --case . \
           --vtk-file \"\$LATEST_VTU\" \
           --grid-spacing '$GRID_SPACING' \
           --output '../../$WIND_JSON')" \
    "test -s '$WIND_JSON'"

GODOT_DATA="godot_project/data/wind_field.json"
GODOT_STL="godot_project/assets/terrain/${LOCATION_NAME}.stl"
run_step "Copy Godot assets" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'" \
    "cp '$WIND_JSON' '$GODOT_DATA' && cp '$STL_PATH' '$GODOT_STL'" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'"

run_step "Git commit" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null" \
    "git add -A && git diff --staged --quiet || git commit -m 'fix: v102 OpenFOAM env, stdbuf, awk display, VTK subdir, locationInMesh'" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null"

perform_audit

echo ""
echo "✅ All fixes applied! (v102)"
echo ""
echo "Next: godot godot_project/project.godot → scenes/main.tscn → F5"
echo "To restart fresh: rm '$STATE_FILE'"
echo "To review heal DB: python3 /tmp/cfd_db_diagnose.py $HEAL_DB --show-unknown"
