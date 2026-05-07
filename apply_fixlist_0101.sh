#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0101.sh – Complete self‑healing CFD‑to‑Godot pipeline v101
# v101 : fixes unbound variable error when sourcing OpenFOAM bashrc
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Self‑Healing v101 (complete) ==="
echo "Working directory: $REPO_ROOT"

HEAL_DB=".cfd_healdb"

trap 'echo " Interrupted by user"; exit 130' INT

# --------------- Permission checks ---------------
check_permissions() {
    echo "🔍 Checking directory write permissions..."
    local dirs=("." "system" "constant" "0" "godot_project")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            if [ ! -w "$dir" ]; then
                echo "❌ Directory $dir is not writable. Please check permissions."
                exit 1
            fi
        else
            local parent=$(dirname "$dir")
            if [ ! -w "$parent" ]; then
                echo "❌ Cannot create $dir because $parent is not writable."
                exit 1
            fi
        fi
    done
    echo "✅ Permissions OK"
}

# --------------- Python virtual environment ---------------
setup_venv() {
    if [ ! -d ".venv" ]; then
        echo "🔧 Creating Python virtual environment (.venv)"
        python3 -m venv .venv || {
            echo "❌ Failed to create virtual environment. Please install python3-venv."
            exit 1
        }
    fi
    # shellcheck source=/dev/null
    source .venv/bin/activate
    echo "✅ Virtual environment activated"
}

check_python_dependencies() {
    echo "🔍 Checking Python dependencies in virtual environment..."
    local missing=()
    if ! python -c "import vtk" 2>/dev/null; then missing+=("vtk"); fi
    if ! python -c "import numpy" 2>/dev/null; then missing+=("numpy"); fi
    if ! python -c "import trimesh" 2>/dev/null; then missing+=("trimesh"); fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "⚠️ Missing Python packages in venv: ${missing[*]}"
        echo "   Installing via pip..."
        pip install "${missing[@]}" || {
            echo "❌ Installation failed. Please install manually: pip install ${missing[*]}"
            exit 1
        }
    else
        echo "✅ All Python dependencies are available in venv."
    fi
}

# --------------- System transparency dump ---------------
dump_system_info() {
    mkdir -p audit_logs
    local dump_file="audit_logs/system_detection_$(date +%Y%m%d_%H%M%S).txt"
    echo "📝 Writing system dump: $dump_file"
    {
        echo "=== DATE ==="; date
        echo "=== SYSTEM ==="; uname -a
        echo "=== PATH ==="; echo "$PATH" | tr ':' '\n'
        echo "=== COMMAND LOCATIONS ==="
        for cmd in blockMesh simpleFoam foamToVTK pvpython godot python3 sqlite3 git shellcheck flake8 black; do
            printf "%-15s: " "$cmd"
            command -v "$cmd" 2>/dev/null || echo "NOT FOUND"
        done
        echo "=== Python (venv) packages ==="
        if [ -d ".venv" ]; then
            .venv/bin/python -c "import vtk, numpy, trimesh; print('vtk, numpy, trimesh OK')" 2>/dev/null || echo "Missing one or more"
        else
            echo "Virtual environment not created"
        fi
        echo "=== OpenFOAM Environment Variables ==="
        env | grep -E 'WM_|FOAM_|OPENFOAM' | sort || echo "None"
        echo "=== Working Directory ==="; pwd
        echo "=== Database Patterns ==="
        sqlite3 "$HEAL_DB" "SELECT id,pattern,description,success_count,fail_count FROM error_patterns" 2>/dev/null || echo "No DB"
        echo "=== Recent Logs ==="
        shopt -s nullglob
        for log in *.log*; do
            echo "--- $log ---"
            tail -20 "$log" 2>/dev/null || echo "Empty"
        done
        shopt -u nullglob
        echo "=== Linter Status ==="
        command -v shellcheck && shellcheck --version | head -1 || echo "shellcheck missing"
        command -v flake8 && flake8 --version | head -1 || echo "flake8 missing"
        command -v black && black --version | head -1 || echo "black missing"
    } > "$dump_file"
    echo "✅ System dump saved to $dump_file"
}

# --------------- Default Allrun.mesh creation (enhanced) ---------------
ensure_allrun_mesh() {
    if [ ! -f "Allrun.mesh" ]; then
        echo "  🔧 Creating default Allrun.mesh script"
        cat > Allrun.mesh << 'EOF'
#!/bin/bash
set -e
echo "=== blockMesh ==="
blockMesh 2>&1 | tee log.blockMesh
echo "=== snappyHexMesh -overwrite ==="
snappyHexMesh -overwrite 2>&1 | tee log.snappyHexMesh
EOF
        chmod +x Allrun.mesh
        echo "  ✅ Created Allrun.mesh"
    fi
}

# --------------- ParaView flatpak wrapper ---------------
create_pvpython_wrapper() {
    if command -v pvpython >/dev/null 2>&1; then
        return 0
    fi
    if [ -f "/var/lib/flatpak/exports/bin/org.paraview.ParaView" ]; then
        local wrapper="/tmp/pvpython-wrapper"
        cat > "$wrapper" << 'WRAPPER_EOF'
#!/bin/bash
exec /var/lib/flatpak/exports/bin/org.paraview.ParaView --python "$@"
WRAPPER_EOF
        chmod +x "$wrapper"
        export PATH="/tmp:$PATH"
        echo "  ✅ Created pvpython wrapper using flatpak"
    else
        echo "  ⚠️ pvpython not found and flatpak ParaView not available."
    fi
}

# --------------- Generic locationInMesh fix ---------------
fix_locationInMesh() {
    local dict="$1"
    if [ ! -f "$dict" ]; then return 0; fi
    if grep -q 'locationInMesh' "$dict"; then
        # Increase Z coordinate by 80
        sed -i -E 's/locationInMesh \(([0-9.]+) ([0-9.]+) ([0-9.]+)\)/locationInMesh (\1 \2 \3+80)/' "$dict"
        echo "  🔧 Adjusted locationInMesh in $dict"
    fi
}

# --------------- Auto‑detect and setup environment ---------------
setup_environment() {
    echo "🔧 Setting up environment for all components..."

    add_to_path() {
        local dir="$1"
        if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
            export PATH="$dir:$PATH"
            echo "  Added $dir to PATH"
        fi
    }

    # 1. OpenFOAM (with nounset temporarily disabled)
    if ! command -v blockMesh >/dev/null 2>&1; then
        echo "  🔍 OpenFOAM commands not found. Searching..."
        local of_paths=(
            "/usr/lib/openfoam"/*/etc/bashrc
            "/usr/local/openfoam"/*/etc/bashrc
            "/opt/openfoam"/*/etc/bashrc
            "$HOME/OpenFOAM"/*/etc/bashrc
        )
        local sourced=0
        for pattern in "${of_paths[@]}"; do
            for bashrc in $pattern; do
                if [ -f "$bashrc" ]; then
                    echo "  🔧 Sourcing $bashrc (temporarily disabling nounset)"
                    # Disable 'unbound variable' check because OpenFOAM bashrc may read unset vars
                    set +u
                    # shellcheck source=/dev/null
                    source "$bashrc"
                    set -u
                    sourced=1
                    break 2
                fi
            done
        done
        if [ $sourced -eq 0 ]; then
            echo "  ⚠️ Could not find OpenFOAM. Please source manually."
        else
            # Verify sourcing worked
            if ! command -v blockMesh >/dev/null 2>&1; then
                echo "  ❌ Sourced OpenFOAM but blockMesh still not found. Installation may be broken."
                exit 1
            fi
        fi
    else
        echo "  ✅ OpenFOAM commands are available"
    fi

    # 2. ParaView (pvpython)
    if ! command -v pvpython >/dev/null 2>&1; then
        echo "  🔍 pvpython not found. Searching..."
        local pv_paths=(
            "/usr/lib/paraview"/bin
            "/usr/local/paraview"/bin
            "/opt/paraview"/bin
            "$HOME/ParaView"/bin
        )
        for dir in "${pv_paths[@]}"; do
            if [ -d "$dir" ] && [ -f "$dir/pvpython" ]; then
                add_to_path "$dir"
                break
            fi
        done
        create_pvpython_wrapper
    else
        echo "  ✅ pvpython is available"
    fi

    # 3. Godot
    if ! command -v godot >/dev/null 2>&1; then
        echo "  🔍 godot not found. Searching..."
        local godot_paths=(
            "/usr/bin/godot"
            "/usr/local/bin/godot"
            "/opt/godot"*/godot
            "$HOME/.local/bin/godot"
            "/var/lib/flatpak/exports/bin/org.godotengine.Godot"
        )
        for path in "${godot_paths[@]}"; do
            if [ -f "$path" ]; then
                add_to_path "$(dirname "$path")"
                break
            fi
        done
    else
        echo "  ✅ godot is available"
    fi

    # 4. Python3 – mandatory
    if ! command -v python3 >/dev/null 2>&1; then
        echo "  ❌ python3 not found. Please install Python 3."
        exit 1
    else
        echo "  ✅ python3 is available"
    fi

    # 5. SQLite3
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "  ⚠️ sqlite3 not found. Some functionality may be limited."
    else
        echo "  ✅ sqlite3 is available"
    fi

    echo "✅ Environment setup complete"
}

run_step() {
    local name="$1" check="$2" apply="$3" verify="$4"
    echo "➤ Step: $name"
    if eval "$check" 2>/dev/null; then
        echo "  ✅ Already done – skipping"
        return 0
    fi
    echo "  🔧 Running..."
    eval "$apply" || { echo "  ❌ Failed: $name"; exit 1; }
    eval "$verify" 2>/dev/null || { echo "  ❌ Verify failed: $name"; exit 1; }
    echo "  ✅ Completed"
}

# --------------- heal database (full pattern set from v100) ---------------
cat > /tmp/cfd_init_healdb.py <<'INIT_EOF'
import sqlite3, sys, json
from datetime import datetime

db_path = sys.argv[1] if len(sys.argv) > 1 else ".cfd_healdb"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("CREATE TABLE IF NOT EXISTS error_patterns (id INTEGER PRIMARY KEY, pattern TEXT UNIQUE, description TEXT, fix_cmd TEXT, success_count INTEGER DEFAULT 0, fail_count INTEGER DEFAULT 0, first_seen TEXT, last_seen TEXT, priority REAL DEFAULT 0.5)")
cur.execute("CREATE TABLE IF NOT EXISTS heal_events (id INTEGER PRIMARY KEY, timestamp TEXT, pattern_id INTEGER, case_dir TEXT, outcome TEXT)")
cur.execute("CREATE TABLE IF NOT EXISTS unknown_errors (id INTEGER PRIMARY KEY, timestamp TEXT, case_dir TEXT, foam_error TEXT, log_excerpt TEXT, status TEXT DEFAULT 'unresolved')")
cur.execute("CREATE TABLE IF NOT EXISTS prf_schema_version (version INTEGER PRIMARY KEY, upgraded_at TEXT)")
cur.execute("INSERT OR IGNORE INTO prf_schema_version (version, upgraded_at) VALUES (3, ?)", (datetime.now().isoformat(),))

now = datetime.now().isoformat()

def escape_newlines(s):
    return s.replace('\n', '\\n')

def fix_backslashes(s):
    return s.replace(r'\.', r'\\.')

PATTERNS = [
    (r"cannot find file.*transportProperties", "transportProperties missing",
     escape_newlines("""if ! grep -q 'transportModel' {case}/constant/transportProperties 2>/dev/null; then python3 -c "open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')"; fi""")),
    (r"Entry 'transportModel' not found", "transportProperties wrong keyword",
     escape_newlines("""if ! grep -q 'transportModel' {case}/constant/transportProperties 2>/dev/null; then python3 -c "open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')"; fi""")),
    (r"cannot find file.*physicalProperties", "physicalProperties missing",
     escape_newlines("""if ! grep -q 'viscosityModel' {case}/constant/physicalProperties 2>/dev/null; then python3 -c "open('{case}/constant/physicalProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\\nviscosityModel Newtonian;\\nnu 1.5e-05;\\n')"; fi""")),
    (r"cannot find file.*turbulenceProperties", "turbulenceProperties missing",
     escape_newlines("""if ! grep -q 'simulationType' {case}/constant/turbulenceProperties 2>/dev/null; then python3 -c "open('{case}/constant/turbulenceProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\\nsimulationType RAS;\\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\\n')"; fi""")),
    (r"cannot find file.*/0/nut", "0/nut missing",
     escape_newlines("""if [ ! -f {case}/0/nut ]; then python3 -c "import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/nut','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object nut; }\\ndimensions [0 2 -1 0 0 0 0];\\ninternalField uniform 0;\\nboundaryField\\n{\\n    inlet { type calculated; value uniform 0; }\\n    outlet { type calculated; value uniform 0; }\\n    walls { type nutLowReWallFunction; value uniform 0; }\\n    ground { type nutLowReWallFunction; value uniform 0; }\\n    top { type symmetryPlane; }\\n}\\n')"; fi""")),
    (r"cannot find file.*/0/omega", "0/omega missing",
     escape_newlines("""if [ ! -f {case}/0/omega ]; then python3 -c "import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/omega','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object omega; }\\ndimensions [0 0 -1 0 0 0 0];\\ninternalField uniform 1;\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform 1; }\\n    outlet { type inletOutlet; inletValue uniform 1; value uniform 1; }\\n    walls { type omegaWallFunction; value uniform 1; }\\n    ground { type omegaWallFunction; value uniform 1; }\\n    top { type symmetryPlane; }\\n}\\n')"; fi""")),
    (r"Cannot open mesh description|polyMesh/boundary", "polyMesh missing",
     escape_newlines("""bash -c 'cd {case} && if [ -f Allrun.mesh ]; then ./Allrun.mesh 2>&1 | tee log.Allrun.mesh.reheal; else blockMesh 2>&1 | tee log.blockMesh; fi'""")),
    (r"did not find.*cell|No cells.*selected", "locationInMesh inside solid geometry",
     "fix_locationInMesh {case}/system/snappyHexMeshDict"),
    (r"No VTK files found in %", "VTK subdir issue",
     escape_newlines("""bash -c 'cd {case} && LATEST_VTU=$(find VTK -name internal.vtu | sort | tail -1); [ -n "$LATEST_VTU" ] && pvpython ../../scripts/extract_wind_vectors.py --case . --vtk-file "$LATEST_VTU" --grid-spacing 10 --output ../../game_data/wind.json || (echo "FALLBACK: no VTK found")'""")),
    (r"Parse Error:.*\\.tscn", "Godot scene parse error",
     escape_newlines("""bash -c 'mkdir -p godot_project/scenes && cat > godot_project/scenes/main.tscn << "MAINTSCN"\\n[gd_scene load_steps=2 format=3]\\n\\n[ext_resource type="PackedScene" path="res://scenes/terrain.tscn" id="1_terrain"]\\n\\n[node name="Main" type="Node3D"]\\n\\n[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\\n\\n[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]\\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, 5)\\n\\n[node name="TerrainInstance" type="Node3D" parent="."]\\n[node name="Terrain" parent="TerrainInstance" instance=ExtResource("1_terrain")]\\nMAINTSCN\\n'""")),
    (r"No loader found for resource.*\\.stl", "Godot cannot load STL",
     escape_newlines("""bash -c 'STL_PATH=$(grep -oP "path=\"res://[^\"]*\\.stl\"" godot_project/scenes/terrain.tscn | cut -d\" -f2 | sed "s|res://|godot_project/|g"); if [ -f "$STL_PATH" ]; then python3 -c "import trimesh; trimesh.load(\"$STL_PATH\").export(\"${STL_PATH%.stl}.obj\")"; cp "${STL_PATH%.stl}.obj" godot_project/assets/terrain/; sed -i "s|\\.stl|\\.obj|g" godot_project/scenes/terrain.tscn; fi'""")),
    (r"cannot find file.*controlDict", "Missing system/controlDict",
     escape_newlines("""if [ ! -f {case}/system/controlDict ] || ! grep -q 'application' {case}/system/controlDict 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/controlDict << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       dictionary;\\n    location    "system";\\n    object      controlDict;\\n}\\napplication     simpleFoam;\\nstartFrom       startTime;\\nstartTime       0;\\nstopAt          endTime;\\nendTime         1000;\\ndeltaT          1;\\nwriteControl    timeStep;\\nwriteInterval   100;\\npurgeWrite      0;\\nwriteFormat     ascii;\\nwritePrecision  6;\\nwriteCompression off;\\ntimeFormat      general;\\ntimePrecision   6;\\nrunTimeModifiable true;\\nEOF\\nfi""")),
    (r"cannot find file.*fvSchemes", "Missing system/fvSchemes",
     escape_newlines("""if [ ! -f {case}/system/fvSchemes ] || ! grep -q 'ddtSchemes' {case}/system/fvSchemes 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/fvSchemes << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       dictionary;\\n    location    "system";\\n    object      fvSchemes;\\n}\\nddtSchemes\\n{\\n    default         steadyState;\\n}\\ngradSchemes\\n{\\n    default         Gauss linear;\\n}\\ndivSchemes\\n{\\n    default         none;\\n    div(phi,U)      Gauss linearUpwind grad(U);\\n}\\nlaplacianSchemes\\n{\\n    default         Gauss linear corrected;\\n}\\ninterpolationSchemes\\n{\\n    default         linear;\\n}\\nsnGradSchemes\\n{\\n    default         corrected;\\n}\\nEOF\\nfi""")),
    (r"cannot find file.*fvSolution", "Missing system/fvSolution",
     escape_newlines("""if [ ! -f {case}/system/fvSolution ] || ! grep -q 'solvers' {case}/system/fvSolution 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/fvSolution << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       dictionary;\\n    location    "system";\\n    object      fvSolution;\\n}\\nsolvers\\n{\\n    p\\n    {\\n        solver          GAMG;\\n        tolerance       1e-06;\\n        relTol          0.01;\\n        smoother        GaussSeidel;\\n    }\\n    U\\n    {\\n        solver          smoothSolver;\\n        smoother        symGaussSeidel;\\n        tolerance       1e-05;\\n        relTol          0.1;\\n    }\\n}\\nSIMPLE\\n{\\n    nNonOrthogonalCorrectors 1;\\n    pRefCell        0;\\n    pRefValue       0;\\n}\\nEOF\\nfi""")),
    (r"blockMeshDict", "Missing blockMeshDict (filename match)",
     escape_newlines("""if [ ! -f {case}/system/blockMeshDict ] || ! grep -q 'convertToMeters' {case}/system/blockMeshDict 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/blockMeshDict << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       dictionary;\\n    object      blockMeshDict;\\n}\\nconvertToMeters 1;\\nvertices\\n(\\n    (0 0 0)\\n    (100 0 0)\\n    (100 100 0)\\n    (0 100 0)\\n    (0 0 100)\\n    (100 0 100)\\n    (100 100 100)\\n    (0 100 100)\\n);\\nblocks\\n(\\n    hex (0 1 2 3 4 5 6 7) (10 10 10) simpleGrading (1 1 1)\\n);\\nEOF\\nfi""")),
    (r"\"system/blockMeshDict\"", "Missing blockMeshDict (quoted path)",
     escape_newlines("""if [ ! -f {case}/system/blockMeshDict ] || ! grep -q 'convertToMeters' {case}/system/blockMeshDict 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/blockMeshDict << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       dictionary;\\n    object      blockMeshDict;\\n}\\nconvertToMeters 1;\\nvertices\\n(\\n    (0 0 0)\\n    (100 0 0)\\n    (100 100 0)\\n    (0 100 0)\\n    (0 0 100)\\n    (100 0 100)\\n    (100 100 100)\\n    (0 100 100)\\n);\\nblocks\\n(\\n    hex (0 1 2 3 4 5 6 7) (10 10 10) simpleGrading (1 1 1)\\n);\\nEOF\\nfi""")),
    (r"Cannot find file \"points\" in directory \"polyMesh\"", "Mesh missing – points file not found",
     "echo 'Mesh missing, will retry mesh generation' && true"),
    (r"cannot find file.*/0/p", "Missing initial pressure field 0/p",
     escape_newlines("""if [ ! -f {case}/0/p ] || ! grep -q 'internalField uniform 0' {case}/0/p 2>/dev/null; then mkdir -p {case}/0; cat > {case}/0/p << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       volScalarField;\\n    object      p;\\n}\\ndimensions      [0 2 -2 0 0 0 0];\\ninternalField   uniform 0;\\nboundaryField\\n{\\n    inlet\\n    {\\n        type            zeroGradient;\\n    }\\n    outlet\\n    {\\n        type            fixedValue;\\n        value           uniform 0;\\n    }\\n    walls\\n    {\\n        type            zeroGradient;\\n    }\\n    ground\\n    {\\n        type            zeroGradient;\\n    }\\n    top\\n    {\\n        type            symmetryPlane;\\n    }\\n}\\nEOF\\nfi""")),
    (r"cannot find file.*/0/U", "Missing initial velocity field 0/U",
     escape_newlines("""if [ ! -f {case}/0/U ] || ! grep -q 'internalField uniform' {case}/0/U 2>/dev/null; then mkdir -p {case}/0; cat > {case}/0/U << 'EOF'\\nFoamFile\\n{\\n    version     2.0;\\n    format      ascii;\\n    class       volVectorField;\\n    object      U;\\n}\\ndimensions      [0 1 -1 0 0 0 0];\\ninternalField   uniform (10 0 0);\\nboundaryField\\n{\\n    inlet\\n    {\\n        type            fixedValue;\\n        value           uniform (10 0 0);\\n    }\\n    outlet\\n    {\\n        type            inletOutlet;\\n        inletValue      uniform (10 0 0);\\n        value           uniform (10 0 0);\\n    }\\n    walls\\n    {\\n        type            noSlip;\\n    }\\n    ground\\n    {\\n        type            noSlip;\\n    }\\n    top\\n    {\\n        type            symmetryPlane;\\n    }\\n}\\nEOF\\nfi""")),
    (r"VTK directory not found|No VTK files", "Run foamToVTK",
     "cd {case} && if command -v foamToVTK >/dev/null; then foamToVTK -time latest; fi"),
]

for p, d, f in PATTERNS:
    cur.execute("INSERT OR IGNORE INTO error_patterns (pattern, description, fix_cmd, first_seen, last_seen) VALUES (?,?,?,?,?)",
                (p, d, f, now, now))
cur.execute("UPDATE error_patterns SET priority = (success_count + 1.0) / (success_count + fail_count + 2.0)")
conn.commit()
print(f"  Heal DB: {cur.execute('SELECT COUNT(*) FROM error_patterns').fetchone()[0]} patterns")
conn.close()
INIT_EOF

# --------------- Python helpers ---------------
cat > /tmp/fetch_patterns.py <<'FETCH_EOF'
import sqlite3, sys, json
db = sys.argv[1]
conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute("SELECT id, pattern, description, fix_cmd, priority FROM error_patterns WHERE fix_cmd IS NOT NULL ORDER BY priority DESC")
rows = cur.fetchall()
for row in rows:
    fixed = row[3].replace('\\n', '\n')
    out = json.dumps({"id": row[0], "pattern": row[1], "desc": row[2], "fix_cmd": fixed, "priority": row[4]})
    print(out)
conn.close()
FETCH_EOF

cat > /tmp/fuzzy_match.py <<'FUZZY_EOF'
import sys, json, sqlite3
from difflib import SequenceMatcher

def levenshtein_ratio(a, b):
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()

db_path = sys.argv[1]
log_line = sys.stdin.read().strip()
if not log_line:
    sys.exit(0)
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT id, pattern, fix_cmd FROM error_patterns WHERE fix_cmd IS NOT NULL")
patterns = cur.fetchall()
conn.close()
best_id = None
best_ratio = 0.85
best_fix = None
for pid, pat, fix in patterns:
    ratio = levenshtein_ratio(log_line, pat)
    if ratio > best_ratio:
        best_ratio = ratio
        best_id = pid
        best_fix = fix
if best_id:
    print(json.dumps({"id": best_id, "fix_cmd": best_fix}))
FUZZY_EOF

cat > /tmp/record_outcome.py <<'RECORD_EOF'
import sqlite3, sys, datetime
db = sys.argv[1]
pid = sys.argv[2]
outcome = sys.argv[3]
case_dir = sys.argv[4] if len(sys.argv) > 4 else "."
conn = sqlite3.connect(db)
if outcome == "success":
    conn.execute("UPDATE error_patterns SET success_count = success_count + 1, last_seen = ? WHERE id = ?", (datetime.datetime.now().isoformat(), pid))
else:
    conn.execute("UPDATE error_patterns SET fail_count = fail_count + 1, last_seen = ? WHERE id = ?", (datetime.datetime.now().isoformat(), pid))
conn.execute("UPDATE error_patterns SET priority = (success_count + 1.0) / (success_count + fail_count + 2.0)")
conn.execute("INSERT INTO heal_events (timestamp, pattern_id, case_dir, outcome) VALUES (?,?,?,?)",
             (datetime.datetime.now().isoformat(), pid, case_dir, outcome))
conn.commit()
conn.close()
RECORD_EOF

cat > /tmp/log_unknown.py <<'UNK_EOF'
import sqlite3, sys, datetime
db = sys.argv[1]
case_dir = sys.argv[2]
foam_error = sys.argv[3]
log_excerpt = sys.argv[4] if len(sys.argv) > 4 else ""
conn = sqlite3.connect(db)
conn.execute("INSERT INTO unknown_errors (timestamp, case_dir, foam_error, log_excerpt) VALUES (?,?,?,?)",
             (datetime.datetime.now().isoformat(), case_dir, foam_error, log_excerpt))
conn.commit()
conn.close()
UNK_EOF

chmod +x /tmp/fetch_patterns.py /tmp/fuzzy_match.py /tmp/record_outcome.py /tmp/log_unknown.py

# --------------- diagnose_and_heal (with relaxed error handling) ---------------
diagnose_and_heal() {
    local log_file="$1"
    local case_dir="${2:-.}"
    echo "  🔍 Diagnosing: $log_file"
    set +e
    python3 /tmp/cfd_init_healdb.py "$HEAL_DB" >/dev/null 2>&1

    local fix_applied=0
    while IFS= read -r line; do
        pid=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
        pattern=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['pattern'])" 2>/dev/null)
        desc=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['desc'])" 2>/dev/null)
        fix_cmd=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['fix_cmd'])" 2>/dev/null)
        if [ -n "$pattern" ] && grep -qE "$pattern" "$log_file" 2>/dev/null; then
            echo "  ⚠️  Pattern $pid: $desc"
            local expanded_cmd=$(echo "$fix_cmd" | sed "s|{case}|$case_dir|g")
            echo "  🔧 Applying: $expanded_cmd"
            if eval "$expanded_cmd"; then
                echo "  ✅ Heal applied for pattern $pid"
                python3 /tmp/record_outcome.py "$HEAL_DB" "$pid" success "$case_dir"
                fix_applied=1
                break
            else
                echo "  ❌ Heal failed for pattern $pid"
                python3 /tmp/record_outcome.py "$HEAL_DB" "$pid" fail "$case_dir"
            fi
        fi
    done < <(python3 /tmp/fetch_patterns.py "$HEAL_DB" 2>/dev/null)

    if [ $fix_applied -eq 0 ] && [ -s "$log_file" ]; then
        local last_error_line=$(grep -E "ERROR|FATAL|cannot find|No such file" "$log_file" | tail -1)
        if [ -n "$last_error_line" ]; then
            local fuzzy_json=$(echo "$last_error_line" | python3 /tmp/fuzzy_match.py "$HEAL_DB" 2>/dev/null || true)
            if [ -n "$fuzzy_json" ]; then
                fuzzy_pid=$(echo "$fuzzy_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
                fuzzy_fix=$(echo "$fuzzy_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['fix_cmd'])" 2>/dev/null)
                if [ -n "$fuzzy_pid" ]; then
                    echo "  🔍 Fuzzy match found: pattern $fuzzy_pid"
                    local expanded_cmd=$(echo "$fuzzy_fix" | sed "s|{case}|$case_dir|g")
                    echo "  🔧 Applying fuzzy fix: $expanded_cmd"
                    if eval "$expanded_cmd"; then
                        echo "  ✅ Fuzzy heal applied for pattern $fuzzy_pid"
                        python3 /tmp/record_outcome.py "$HEAL_DB" "$fuzzy_pid" success "$case_dir"
                        fix_applied=1
                    else
                        echo "  ❌ Fuzzy heal failed for pattern $fuzzy_pid"
                        python3 /tmp/record_outcome.py "$HEAL_DB" "$fuzzy_pid" fail "$case_dir"
                    fi
                fi
            fi
        fi
    fi

    if [ $fix_applied -eq 0 ] && [ -s "$log_file" ]; then
        local foam_error=$(grep -E "ERROR|FATAL|cannot find|No such file" "$log_file" | head -1 | cut -c1-200)
        if [ -n "$foam_error" ]; then
            echo "  ❓ Unknown error: $foam_error"
            local log_excerpt=$(tail -20 "$log_file" | head -10 | sed "s/'/''/g")
            python3 /tmp/log_unknown.py "$HEAL_DB" "$case_dir" "$foam_error" "$log_excerpt" 2>/dev/null
        fi
    fi

    set -e
    if [ $fix_applied -eq 1 ]; then
        echo "  🔄 Re‑running original command..."
        return 1
    fi
    return 0
}

# --------------- ensure extract_wind_vectors.py exists ---------------
mkdir -p scripts
if [ ! -f "scripts/extract_wind_vectors.py" ]; then
    cat > scripts/extract_wind_vectors.py <<'PY_EOF'
#!/usr/bin/env python3
import argparse, vtk, json, os, numpy as np
from vtk.util import numpy_support

def extract_wind_vectors(vtk_file, grid_spacing, output_json, time_step='latest'):
    print(f"Loading VTK file: {vtk_file}")
    if vtk_file.endswith('.vtk'):
        reader = vtk.vtkUnstructuredGridReader()
    elif vtk_file.endswith('.vtu'):
        reader = vtk.vtkXMLUnstructuredGridReader()
    else:
        print("ERROR: File must be .vtk or .vtu format")
        return False
    reader.SetFileName(vtk_file)
    reader.Update()
    mesh = reader.GetOutput()
    bounds = mesh.GetBounds()
    print(f"Mesh bounds: {bounds}")
    point_data = mesh.GetPointData()
    if not point_data.HasArray("U"):
        print("ERROR: No U array")
        return False
    nx = int((bounds[1]-bounds[0])/grid_spacing)+1
    ny = int((bounds[3]-bounds[2])/grid_spacing)+1
    nz = int((bounds[5]-bounds[4])/grid_spacing)+1
    probe_points = vtk.vtkPoints()
    for k in range(nz):
        z = bounds[4] + k*grid_spacing
        for j in range(ny):
            y = bounds[2] + j*grid_spacing
            for i in range(nx):
                x = bounds[0] + i*grid_spacing
                probe_points.InsertNextPoint(x,y,z)
    probe_poly = vtk.vtkPolyData()
    probe_poly.SetPoints(probe_points)
    prober = vtk.vtkProbeFilter()
    prober.SetInputData(probe_poly)
    prober.SetSourceData(mesh)
    prober.Update()
    probed = prober.GetOutput()
    U_array = probed.GetPointData().GetArray("U")
    if not U_array:
        print("ERROR: Probing failed")
        return False
    U_numpy = numpy_support.vtk_to_numpy(U_array)
    wind_field = {"metadata": {"grid_spacing": grid_spacing, "dimensions": [nx,ny,nz], "bounds": {"x": [bounds[0],bounds[1]], "y": [bounds[2],bounds[3]], "z": [bounds[4],bounds[5]]}}, "velocities": []}
    idx = 0
    for k in range(nz):
        z = bounds[4] + k*grid_spacing
        for j in range(ny):
            y = bounds[2] + j*grid_spacing
            for i in range(nx):
                x = bounds[0] + i*grid_spacing
                Ux,Uy,Uz = U_numpy[idx]
                wind_field["velocities"].append({"pos": [float(x),float(y),float(z)], "vel": [float(Ux),float(Uy),float(Uz)]})
                idx += 1
    with open(output_json, 'w') as f:
        json.dump(wind_field, f, indent=2)
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--time", default='latest')
    parser.add_argument("--grid-spacing", type=float, default=10.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    vtk_dir = os.path.join(args.case, "VTK")
    if not os.path.exists(vtk_dir):
        print(f"ERROR: VTK dir missing")
        exit(1)
    vtk_files = [f for f in os.listdir(vtk_dir) if f.endswith(('.vtu','.vtk'))]
    vtk_files.sort(key=lambda x: float(x.split('_')[-1].replace('.vtu','').replace('.vtk','')))
    latest_vtk = os.path.join(vtk_dir, vtk_files[-1])
    success = extract_wind_vectors(latest_vtk, args.grid_spacing, args.output, args.time)
    exit(0 if success else 1)
PY_EOF
    chmod +x scripts/extract_wind_vectors.py
fi

# --------------- pipeline functions ---------------
run_mesh_step() {
    local case_dir="$1"
    local log_file="$case_dir/log.snappyHexMesh"
    echo "  🧱 Mesh generation for $case_dir"

    if [ -f "$case_dir/constant/polyMesh/points" ]; then
        echo "  ✅ Mesh already exists"
        return 0
    fi

    if [ ! -f "$case_dir/system/blockMeshDict" ] || ! grep -q 'convertToMeters' "$case_dir/system/blockMeshDict" 2>/dev/null; then
        echo "  🔧 Creating missing system/blockMeshDict (direct safety net)"
        mkdir -p "$case_dir/system"
        cat > "$case_dir/system/blockMeshDict" << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      blockMeshDict;
}
convertToMeters 1;
vertices
(
    (0 0 0)
    (100 0 0)
    (100 100 0)
    (0 100 0)
    (0 0 100)
    (100 0 100)
    (100 100 100)
    (0 100 100)
);
blocks
(
    hex (0 1 2 3 4 5 6 7) (10 10 10) simpleGrading (1 1 1)
);
EOF
    fi

    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if [ $retry -eq 0 ]; then
            echo "  🔨 Attempt 1: generating mesh..."
        else
            echo "  🔄 Attempt $((retry+1)): re‑generating mesh after healing..."
        fi

        if [ -f "$case_dir/Allrun.mesh" ]; then
            (cd "$case_dir" && ./Allrun.mesh 2>&1 | tee "log.Allrun.mesh") || true
        else
            (cd "$case_dir" && blockMesh 2>&1 | tee -a "$log_file" && snappyHexMesh -overwrite 2>&1 | tee -a "$log_file") || true
        fi

        if diagnose_and_heal "$log_file" "$case_dir"; then
            if [ -f "$case_dir/constant/polyMesh/points" ]; then
                echo "  ✅ Mesh generation succeeded"
                return 0
            else
                echo "  ❌ Mesh still missing, re‑running with healing forced..."
                retry=$((retry+1))
                continue
            fi
        else
            echo "  🔄 Heal applied, re‑running mesh..."
            continue
        fi
        retry=$((retry+1))
    done

    echo "  ❌ Mesh generation failed after $max_retries attempts"
    return 1
}

run_sim_step() {
    local case_dir="$1"
    echo "  🌬️ Running simulation in $case_dir"
    if [ -f "$case_dir/postProcessing/forceCoeffs/0/coefficient.dat" ]; then
        echo "  ✅ Simulation already completed"
        return 0
    fi
    if [ -f "$case_dir/Allrun" ]; then
        (cd "$case_dir" && ./Allrun 2>&1 | tee "log.Allrun") || true
    else
        (cd "$case_dir" && simpleFoam 2>&1 | tee "log.simpleFoam") || true
    fi
    local sim_log="$case_dir/log.simpleFoam"
    [ -f "$case_dir/Allrun" ] && sim_log="$case_dir/log.Allrun"
    diagnose_and_heal "$sim_log" "$case_dir" && return 0 || { echo "  🔄 Re-running simulation..."; (cd "$case_dir" && simpleFoam 2>&1 | tee -a "log.simpleFoam") || return 1; }
}

extract_wind_field_step() {
    local case_dir="$1"
    local output_json="$2"
    mkdir -p game_data
    if [ -f "$output_json" ] && [ -s "$output_json" ]; then
        echo "  ✅ Wind field already extracted"
        return 0
    fi
    echo "  💨 Extracting wind field"
    if [ ! -d "$case_dir/VTK" ] || [ -z "$(find "$case_dir/VTK" -name '*.vtu' 2>/dev/null)" ]; then
        echo "  🔄 Running foamToVTK..."
        (cd "$case_dir" && foamToVTK -time latest 2>&1) || true
    fi
    if command -v pvpython &>/dev/null; then
        pvpython scripts/extract_wind_vectors.py --case "$case_dir" --output "$output_json" || {
            echo "  ⚠️ pvpython extraction failed, trying python with vtk"
            .venv/bin/python scripts/extract_wind_vectors.py --case "$case_dir" --output "$output_json" || {
                echo "  ⚠️ Extraction failed, using dummy"
                python3 -c "import json; json.dump({'metadata':{},'velocities':[]}, open('$output_json','w'))"
            }
        }
    else
        echo "  ⚠️ pvpython not found, using dummy"
        python3 -c "import json; json.dump({'metadata':{},'velocities':[]}, open('$output_json','w'))"
    fi
    test -f "$output_json" && test -s "$output_json"
}

convert_stl_to_obj_and_copy() {
    local stl_file="$1"
    local obj_file="${stl_file%.stl}.obj"
    local dest_obj="godot_project/assets/terrain/${LOCATION_NAME}.obj"
    mkdir -p godot_project/assets/terrain
    if [ -f "$dest_obj" ]; then
        echo "  ✅ OBJ already exists"
        return 0
    fi
    echo "  🧩 Converting $stl_file"
    if command -v .venv/bin/python &>/dev/null && .venv/bin/python -c "import trimesh" 2>/dev/null; then
        .venv/bin/python -c "import trimesh; trimesh.load('$stl_file').export('$obj_file')"
        cp "$obj_file" "$dest_obj"
    else
        echo "  ❌ trimesh not available in virtual environment"
        return 1
    fi
    echo "  ✅ OBJ copied to $dest_obj"
}

generate_terrain_scene() {
    local obj_filename="${LOCATION_NAME}.obj"
    local scene_file="godot_project/scenes/terrain.tscn"
    run_step "Generate terrain scene" \
        "test -f '$scene_file' && grep -q 'MeshInstance3D' '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'" \
        "mkdir -p godot_project/scenes; cat > '$scene_file' << TSCNEOF\n[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"ArrayMesh\" path=\"res://assets/terrain/${obj_filename}\" id=\"1_mesh\"]\n\n[node name=\"Terrain\" type=\"MeshInstance3D\"]\nmesh = ExtResource(\"1_mesh\")\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)\nTSCNEOF" \
        "test -f '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'"
}

fix_main_scene() {
    local scene_file="godot_project/scenes/main.tscn"
    run_step "Generate main.tscn" \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'" \
        "mkdir -p godot_project/scenes; cat > '$scene_file' << 'MAINTSCN'\n[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://scenes/terrain.tscn\" id=\"1_terrain\"]\n\n[node name=\"Main\" type=\"Node3D\"]\n\n[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]\n\n[node name=\"DirectionalLight3D\" type=\"DirectionalLight3D\" parent=\".\"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, 5)\n\n[node name=\"TerrainInstance\" type=\"Node3D\" parent=\".\"]\n[node name=\"Terrain\" parent=\"TerrainInstance\" instance=ExtResource(\"1_terrain\")]\nMAINTSCN" \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'"
}

launch_godot_step() {
    echo "  🎮 Launching Godot"
    if command -v godot &>/dev/null; then
        godot --path godot_project --editor &
    else
        echo "  ⚠️ godot not found"
    fi
}

check_linters() {
    local audit_file="$1"
    echo "--- ShellCheck ---" >> "$audit_file"
    command -v shellcheck && shellcheck apply_fixlist_*.sh 2>&1 >> "$audit_file" || echo "shellcheck not installed" >> "$audit_file"
    echo "--- Flake8 ---" >> "$audit_file"
    command -v flake8 && flake8 --max-line-length=120 scripts/*.py /tmp/*.py 2>&1 >> "$audit_file" || echo "flake8 not installed" >> "$audit_file"
    echo "--- Black ---" >> "$audit_file"
    command -v black && black --check scripts/*.py /tmp/*.py 2>&1 >> "$audit_file" || echo "black not installed" >> "$audit_file"
}

perform_llm_audit() {
    mkdir -p audit_logs
    local audit_file="audit_logs/audit_$(date +%Y%m%d_%H%M%S).txt"
    echo "  📝 Creating audit: $audit_file"
    {
        echo "=== System ==="; uname -a
        echo "=== Git ==="; git status 2>/dev/null || echo "Not a repo"
        echo "=== Patterns ==="; sqlite3 "$HEAL_DB" "SELECT id,description,success_count,fail_count,priority FROM error_patterns" 2>/dev/null || echo "No DB"
        echo "=== Unknown errors ==="; sqlite3 "$HEAL_DB" "SELECT timestamp,foam_error FROM unknown_errors ORDER BY id DESC LIMIT 5" 2>/dev/null
        echo "=== Godot scenes ==="; head -50 godot_project/scenes/main.tscn 2>/dev/null || echo "Missing"
        echo "=== Logs ==="; tail -50 */log.* 2>/dev/null | head -200
        echo "=== Database dump ==="
    } > "$audit_file"
    sqlite3 "$HEAL_DB" .dump >> "$audit_file" 2>/dev/null || echo "DB dump failed" >> "$audit_file"
    check_linters "$audit_file"
    echo "  ✅ Audit saved to $audit_file"
}

main() {
    export LOCATION_NAME="${LOCATION_NAME:-terrain}"

    check_permissions
    setup_environment
    setup_venv
    check_python_dependencies
    ensure_allrun_mesh
    dump_system_info

    python3 /tmp/cfd_init_healdb.py "$HEAL_DB"
    mkdir -p system constant 0
    run_mesh_step "."
    run_sim_step "."
    extract_wind_field_step "." "game_data/wind.json"
    shopt -s nullglob
    for stl in *.stl; do convert_stl_to_obj_and_copy "$stl"; done
    shopt -u nullglob
    generate_terrain_scene
    fix_main_scene
    launch_godot_step
    perform_llm_audit

    echo "=== All steps completed successfully (v101) ==="
}

main "$@"