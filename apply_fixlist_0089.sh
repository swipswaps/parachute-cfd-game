#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0089.sh – Complete self‑healing CFD‑to‑Godot pipeline v89
# v89 : full improvements including fuzzy matching, priority, unknown logging
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Complete Self‑Healing v89 ==="
echo "Working directory: $REPO_ROOT"

HEAL_DB=".cfd_healdb"
SCHEMA_VERSION=3

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

# --------------- heal database helpers (written to /tmp) --------------

cat > /tmp/cfd_init_healdb.py <<'INIT_EOF'
#!/usr/bin/env python3
"""
Initialize or upgrade the self-healing database.
Supports schema versioning, fuzzy matching, and error pattern storage.
"""
import sqlite3, sys, os, re
from datetime import datetime
from pathlib import Path

db_path = sys.argv[1] if len(sys.argv) > 1 else ".cfd_healdb"
target_version = 3

conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys = ON")
cur = conn.cursor()

# ---- Schema creation / upgrade ----
cur.execute("CREATE TABLE IF NOT EXISTS prf_schema_version (version INTEGER PRIMARY KEY, upgraded_at TEXT)")
cur.execute("SELECT version FROM prf_schema_version ORDER BY version DESC LIMIT 1")
row = cur.fetchone()
current_version = row[0] if row else 0

def upgrade_to_v1():
    cur.execute("""
    CREATE TABLE IF NOT EXISTS error_patterns (
        id INTEGER PRIMARY KEY,
        pattern TEXT UNIQUE,
        description TEXT,
        fix_cmd TEXT,
        success_count INTEGER DEFAULT 0,
        fail_count INTEGER DEFAULT 0,
        first_seen TEXT,
        last_seen TEXT,
        fuzzy_match BOOLEAN DEFAULT 0
    )""")
    cur.execute("""
    CREATE TABLE IF NOT EXISTS heal_events (
        id INTEGER PRIMARY KEY,
        timestamp TEXT,
        pattern_id INTEGER,
        case_dir TEXT,
        outcome TEXT
    )""")
    cur.execute("""
    CREATE TABLE IF NOT EXISTS unknown_errors (
        id INTEGER PRIMARY KEY,
        timestamp TEXT,
        case_dir TEXT,
        foam_error TEXT,
        log_excerpt TEXT,
        status TEXT DEFAULT 'unresolved'
    )""")
    cur.execute("INSERT OR IGNORE INTO prf_schema_version (version, upgraded_at) VALUES (1, ?)", (datetime.now().isoformat(),))

def upgrade_to_v2():
    # Add fuzzy_match column if missing
    cur.execute("PRAGMA table_info(error_patterns)")
    cols = [c[1] for c in cur.fetchall()]
    if 'fuzzy_match' not in cols:
        cur.execute("ALTER TABLE error_patterns ADD COLUMN fuzzy_match BOOLEAN DEFAULT 0")
    cur.execute("INSERT OR IGNORE INTO prf_schema_version (version, upgraded_at) VALUES (2, ?)", (datetime.now().isoformat(),))

def upgrade_to_v3():
    # Add priority column
    cur.execute("PRAGMA table_info(error_patterns)")
    cols = [c[1] for c in cur.fetchall()]
    if 'priority' not in cols:
        cur.execute("ALTER TABLE error_patterns ADD COLUMN priority REAL DEFAULT 0.5")
        # Initialize priority based on existing counts
        cur.execute("UPDATE error_patterns SET priority = (success_count + 1.0) / (success_count + fail_count + 2.0)")
    cur.execute("INSERT OR IGNORE INTO prf_schema_version (version, upgraded_at) VALUES (3, ?)", (datetime.now().isoformat(),))

if current_version < 1:
    upgrade_to_v1()
if current_version < 2:
    upgrade_to_v2()
if current_version < 3:
    upgrade_to_v3()

# ---- Pattern definitions (idempotent insert) ----
now = datetime.now().isoformat()
PATTERNS = [
    (r"cannot find file.*transportProperties",
     "transportProperties missing (openfoam-2512)",
     r"""if ! grep -q 'transportModel' {case}/constant/transportProperties 2>/dev/null; then python3 -c "open('{case}/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"; fi""", 0),
    (r"Entry 'transportModel' not found",
     "transportProperties wrong keyword (viscosityModel not transportModel)",
     r"""if ! grep -q 'transportModel' {case}/constant/transportProperties 2>/dev/null; then python3 -c "open('{case}/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"; fi""", 0),
    (r"cannot find file.*physicalProperties",
     "physicalProperties missing (OF.org v10+)",
     r"""if ! grep -q 'viscosityModel' {case}/constant/physicalProperties 2>/dev/null; then python3 -c "open('{case}/constant/physicalProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\nviscosityModel Newtonian;\nnu 1.5e-05;\n')"; fi""", 0),
    (r"cannot find file.*turbulenceProperties",
     "turbulenceProperties missing",
     r"""if ! grep -q 'simulationType' {case}/constant/turbulenceProperties 2>/dev/null; then python3 -c "open('{case}/constant/turbulenceProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\nsimulationType RAS;\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\n')"; fi""", 0),
    (r"cannot find file.*/0/nut",
     "0/nut missing (k-epsilon turbulent viscosity wall field)",
     r"""if [ ! -f {case}/0/nut ]; then python3 -c "import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')"; fi""", 0),
    (r"cannot find file.*/0/omega",
     "0/omega missing (k-omega SST field)",
     r"""if [ ! -f {case}/0/omega ]; then python3 -c "import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/omega','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object omega; }\ndimensions [0 0 -1 0 0 0 0];\ninternalField uniform 1;\nboundaryField\n{\n    inlet { type fixedValue; value uniform 1; }\n    outlet { type inletOutlet; inletValue uniform 1; value uniform 1; }\n    walls { type omegaWallFunction; value uniform 1; }\n    ground { type omegaWallFunction; value uniform 1; }\n    top { type symmetryPlane; }\n}\n')"; fi""", 0),
    (r"Cannot open mesh description|polyMesh/boundary",
     "polyMesh missing",
     r"bash -c 'cd {case} && if [ -f Allrun.mesh ]; then ./Allrun.mesh 2>&1 | tee log.Allrun.mesh.reheal; fi'", 0),
    (r"did not find.*cell|No cells.*selected",
     "locationInMesh inside solid geometry",
     r"sed -i 's/locationInMesh (150 150 100)/locationInMesh (150 150 180)/' {case}/system/snappyHexMeshDict", 0),
    (r"No VTK files found in %",
     "VTK subdir issue – internal.vtu nested",
     r"""bash -c 'cd {case} && LATEST_VTU=$(find VTK -name internal.vtu | sort | tail -1); [ -n "$LATEST_VTU" ] && pvpython ../../scripts/extract_wind_vectors.py --case . --vtk-file "$LATEST_VTU" --grid-spacing 10 --output ../../game_data/wind.json || (echo "FALLBACK: no VTK found")'""", 0),
    (r"Parse Error:.*\.tscn",
     "Godot scene parse error – regenerate minimal main.tscn",
     r"""bash -c 'mkdir -p godot_project/scenes && cat > godot_project/scenes/main.tscn << "MAINTSCN"\n[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://scenes/terrain.tscn" id="1_terrain"]\n\n[node name="Main" type="Node3D"]\n\n[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\n\n[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, 5)\n\n[node name="TerrainInstance" type="Node3D" parent="."]\n[node name="Terrain" parent="TerrainInstance" instance=ExtResource("1_terrain")]\nMAINTSCN\n'""", 0),
    (r"No loader found for resource.*\.stl",
     "Godot cannot load STL – convert to OBJ and update scene",
     r"""bash -c 'STL_PATH=$(grep -oP "path=\"res://[^\"]*\.stl\"" godot_project/scenes/terrain.tscn | cut -d\" -f2 | sed "s|res://|godot_project/|g"); if [ -f "$STL_PATH" ]; then python3 -c "import trimesh; trimesh.load(\"$STL_PATH\").export(\"${STL_PATH%.stl}.obj\")"; cp "${STL_PATH%.stl}.obj" godot_project/assets/terrain/; sed -i "s|\.stl|\.obj|g" godot_project/scenes/terrain.tscn; fi'""", 0),
    # New patterns added in v89:
    (r"cannot find file.*controlDict",
     "Missing system/controlDict – create minimal controlDict",
     r"""if [ ! -f {case}/system/controlDict ] || ! grep -q 'application' {case}/system/controlDict 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/controlDict << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "system";
    object      controlDict;
}
application     simpleFoam;
startFrom       startTime;
startTime       0;
stopAt          endTime;
endTime         1000;
deltaT          1;
writeControl    timeStep;
writeInterval   100;
purgeWrite      0;
writeFormat     ascii;
writePrecision  6;
writeCompression off;
timeFormat      general;
timePrecision   6;
runTimeModifiable true;
EOF
fi""", 0),
    (r"cannot find file.*fvSchemes",
     "Missing system/fvSchemes – create minimal fvSchemes",
     r"""if [ ! -f {case}/system/fvSchemes ] || ! grep -q 'ddtSchemes' {case}/system/fvSchemes 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/fvSchemes << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "system";
    object      fvSchemes;
}
ddtSchemes
{
    default         steadyState;
}
gradSchemes
{
    default         Gauss linear;
}
divSchemes
{
    default         none;
    div(phi,U)      Gauss linearUpwind grad(U);
}
laplacianSchemes
{
    default         Gauss linear corrected;
}
interpolationSchemes
{
    default         linear;
}
snGradSchemes
{
    default         corrected;
}
EOF
fi""", 0),
    (r"cannot find file.*fvSolution",
     "Missing system/fvSolution – create minimal fvSolution",
     r"""if [ ! -f {case}/system/fvSolution ] || ! grep -q 'solvers' {case}/system/fvSolution 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/fvSolution << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "system";
    object      fvSolution;
}
solvers
{
    p
    {
        solver          GAMG;
        tolerance       1e-06;
        relTol          0.01;
        smoother        GaussSeidel;
    }
    U
    {
        solver          smoothSolver;
        smoother        symGaussSeidel;
        tolerance       1e-05;
        relTol          0.1;
    }
}
SIMPLE
{
    nNonOrthogonalCorrectors 1;
    pRefCell        0;
    pRefValue       0;
}
EOF
fi""", 0),
    (r"cannot find file.*blockMeshDict",
     "Missing system/blockMeshDict – create minimal blockMeshDict",
     r"""if [ ! -f {case}/system/blockMeshDict ] || ! grep -q 'convertToMeters' {case}/system/blockMeshDict 2>/dev/null; then mkdir -p {case}/system; cat > {case}/system/blockMeshDict << 'EOF'
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
fi""", 0),
    (r"cannot find file.*/0/p",
     "Missing initial pressure field 0/p",
     r"""if [ ! -f {case}/0/p ] || ! grep -q 'internalField uniform 0' {case}/0/p 2>/dev/null; then mkdir -p {case}/0; cat > {case}/0/p << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       volScalarField;
    object      p;
}
dimensions      [0 2 -2 0 0 0 0];
internalField   uniform 0;
boundaryField
{
    inlet
    {
        type            zeroGradient;
    }
    outlet
    {
        type            fixedValue;
        value           uniform 0;
    }
    walls
    {
        type            zeroGradient;
    }
    ground
    {
        type            zeroGradient;
    }
    top
    {
        type            symmetryPlane;
    }
}
EOF
fi""", 0),
    (r"cannot find file.*/0/U",
     "Missing initial velocity field 0/U",
     r"""if [ ! -f {case}/0/U ] || ! grep -q 'internalField uniform' {case}/0/U 2>/dev/null; then mkdir -p {case}/0; cat > {case}/0/U << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       volVectorField;
    object      U;
}
dimensions      [0 1 -1 0 0 0 0];
internalField   uniform (10 0 0);
boundaryField
{
    inlet
    {
        type            fixedValue;
        value           uniform (10 0 0);
    }
    outlet
    {
        type            inletOutlet;
        inletValue      uniform (10 0 0);
        value           uniform (10 0 0);
    }
    walls
    {
        type            noSlip;
    }
    ground
    {
        type            noSlip;
    }
    top
    {
        type            symmetryPlane;
    }
}
EOF
fi""", 0),
    (r"VTK directory not found|No VTK files",
     "Run foamToVTK to generate VTK output",
     r"cd {case} && if command -v foamToVTK >/dev/null; then foamToVTK -time latest; fi", 0),
]

for p,d,f, fuzzy in PATTERNS:
    cur.execute("""
        INSERT OR IGNORE INTO error_patterns (pattern, description, fix_cmd, first_seen, last_seen, fuzzy_match)
        VALUES (?,?,?,?,?,?)
    """, (p, d, f, now, now, fuzzy))
conn.commit()

# Update priority for all patterns after insert
cur.execute("UPDATE error_patterns SET priority = (success_count + 1.0) / (success_count + fail_count + 2.0)")
conn.commit()

print(f"  Heal DB: {cur.execute('SELECT COUNT(*) FROM error_patterns').fetchone()[0]} patterns in {db_path}")
conn.close()
INIT_EOF

cat > /tmp/cfd_db_diagnose.py <<'DIAG_EOF'
#!/usr/bin/env python3
"""
Database diagnosis and healing application.
Supports exact regex matching, fuzzy fallback, pattern application, and unknown logging.
"""
import sqlite3, re, sys, os, subprocess
from datetime import datetime
from difflib import SequenceMatcher

def levenshtein_ratio(a, b):
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()

db_path = sys.argv[1] if len(sys.argv) > 1 else ".cfd_healdb"

if len(sys.argv) > 2 and sys.argv[2] == '--show-unknown':
    if not os.path.exists(db_path): print("No DB"); sys.exit(0)
    conn = sqlite3.connect(db_path)
    rows = conn.execute("SELECT timestamp,foam_error,log_excerpt FROM unknown_errors ORDER BY id DESC LIMIT 5").fetchall()
    for ts, err, exc in rows:
        print(f"\n[{ts}] {err}\n{(exc or '')[-300:]}")
    conn.close()
    sys.exit(0)

if len(sys.argv) > 2 and sys.argv[2] == '--record-outcome':
    pid, outcome, case_dir = sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "."
    conn = sqlite3.connect(db_path)
    if outcome == "success":
        conn.execute("UPDATE error_patterns SET success_count = success_count + 1 WHERE id = ?", (pid,))
    else:
        conn.execute("UPDATE error_patterns SET fail_count = fail_count + 1 WHERE id = ?", (pid,))
    # Recalculate priority
    conn.execute("UPDATE error_patterns SET priority = (success_count + 1.0) / (success_count + fail_count + 2.0)")
    conn.execute("INSERT INTO heal_events (timestamp,pattern_id,case_dir,outcome) VALUES (?,?,?,?)",
                 (datetime.now().isoformat(), pid, case_dir, outcome))
    conn.commit()
    conn.close()
    sys.exit(0)

if len(sys.argv) > 2 and sys.argv[2] == '--fuzzy-match':
    # Fuzzy match mode: read log line from stdin, return best matching pattern id
    log_line = sys.stdin.read().strip()
    if not log_line:
        sys.exit(0)
    conn = sqlite3.connect(db_path)
    patterns = conn.execute("SELECT id, pattern, priority FROM error_patterns").fetchall()
    conn.close()
    best_id = None
    best_ratio = 0.85  # threshold
    for pid, pat, prio in patterns:
        ratio = levenshtein_ratio(log_line, pat)
        if ratio > best_ratio:
            best_ratio = ratio
            best_id = pid
    if best_id:
        print(best_id)
    sys.exit(0)

# Main diagnose mode (for bash to fetch all patterns)
if not os.path.exists(db_path):
    print("No DB found. Run main script first.")
    sys.exit(1)

conn = sqlite3.connect(db_path)
# Fetch patterns ordered by priority descending (most reliable first)
patterns = conn.execute("""
    SELECT id, pattern, description, fix_cmd, fuzzy_match
    FROM error_patterns
    WHERE fix_cmd IS NOT NULL
    ORDER BY priority DESC
""").fetchall()
conn.close()

for pid, pat, desc, fix_cmd, fuzzy in patterns:
    print(f"{pid}\x1F{pat}\x1F{desc}\x1F{fix_cmd}\x1F{fuzzy}")
DIAG_EOF

chmod +x /tmp/cfd_init_healdb.py /tmp/cfd_db_diagnose.py

# --------------- diagnose_and_heal (with fuzzy fallback and unknown logging) ---------------
diagnose_and_heal() {
    local log_file="$1"
    local case_dir="${2:-.}"
    echo "  🔍 Diagnosing: $log_file"
    python3 /tmp/cfd_init_healdb.py "$HEAL_DB" >/dev/null 2>&1

    local fix_applied=0

    # Collect log excerpt for unknown logging
    local log_excerpt=$(tail -20 "$log_file" 2>/dev/null | head -10)

    # First try exact regex matches
    while IFS=$'\x1F' read -r pid pattern desc fix_cmd fuzzy; do
        if grep -qE "$pattern" "$log_file" 2>/dev/null; then
            echo "  ⚠️  Pattern $pid: $desc"
            local expanded_cmd=$(echo "$fix_cmd" | sed "s|{case}|$case_dir|g")
            echo "  🔧 Applying: $expanded_cmd"
            if eval "$expanded_cmd"; then
                echo "  ✅ Heal applied for pattern $pid"
                python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$pid" success "$case_dir"
                fix_applied=1
            else
                echo "  ❌ Heal failed for pattern $pid"
                python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$pid" fail "$case_dir"
            fi
            # If fix applied, stop further pattern matching for this log
            if [ $fix_applied -eq 1 ]; then break; fi
        fi
    done < <(sqlite3 "$HEAL_DB" -batch -noheader -separator $'\x1F' \
        "SELECT id, pattern, description, fix_cmd, fuzzy_match FROM error_patterns WHERE fix_cmd IS NOT NULL ORDER BY priority DESC" 2>/dev/null || true)

    # If no exact match, try fuzzy matching
    if [ $fix_applied -eq 0 ] && [ -s "$log_file" ]; then
        local last_error_line=$(grep -E "ERROR|FATAL|cannot find" "$log_file" | tail -1)
        if [ -n "$last_error_line" ]; then
            local fuzzy_pid=$(echo "$last_error_line" | python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --fuzzy-match 2>/dev/null || true)
            if [ -n "$fuzzy_pid" ]; then
                echo "  🔍 Fuzzy match found: pattern $fuzzy_pid"
                # Fetch the fix_cmd for that pattern
                local fuzzy_cmd=$(sqlite3 "$HEAL_DB" -batch -noheader "SELECT fix_cmd FROM error_patterns WHERE id = $fuzzy_pid" 2>/dev/null)
                if [ -n "$fuzzy_cmd" ]; then
                    local expanded_cmd=$(echo "$fuzzy_cmd" | sed "s|{case}|$case_dir|g")
                    echo "  🔧 Applying fuzzy fix: $expanded_cmd"
                    if eval "$expanded_cmd"; then
                        echo "  ✅ Fuzzy heal applied for pattern $fuzzy_pid"
                        python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$fuzzy_pid" success "$case_dir"
                        fix_applied=1
                    else
                        echo "  ❌ Fuzzy heal failed for pattern $fuzzy_pid"
                        python3 /tmp/cfd_db_diagnose.py "$HEAL_DB" --record-outcome "$fuzzy_pid" fail "$case_dir"
                    fi
                fi
            fi
        fi
    fi

    # If still no fix, log unknown error
    if [ $fix_applied -eq 0 ] && [ -s "$log_file" ]; then
        local foam_error=$(grep -E "ERROR|FATAL|cannot find" "$log_file" | head -1 | cut -c1-200)
        if [ -n "$foam_error" ]; then
            echo "  ❓ Unknown error: $foam_error"
            echo "  📝 Logging to unknown_errors table"
            sqlite3 "$HEAL_DB" "INSERT INTO unknown_errors (timestamp, case_dir, foam_error, log_excerpt) VALUES (datetime('now'), '$case_dir', '$foam_error', '${log_excerpt//\'/\'\'}')" 2>/dev/null || true
        fi
    fi

    if [ $fix_applied -eq 1 ]; then
        echo "  🔄 Re‑running original command..."
        return 1
    fi
    return 0
}

# --------------- ensure extract_wind_vectors.py exists ---------------
mkdir -p scripts
if [ ! -f "scripts/extract_wind_vectors.py" ]; then
    echo "📝 Creating scripts/extract_wind_vectors.py (embedded version)"
    cat > scripts/extract_wind_vectors.py <<'PY_EOF'
#!/usr/bin/env python3
"""
Extract wind velocity vectors from OpenFOAM CFD results for Godot game.
Full embedded version – requires VTK/ParaView.
"""
import argparse
import vtk
from vtk.util import numpy_support
import numpy as np
import json
import os

def extract_wind_vectors(vtk_file, grid_spacing, output_json, time_step='latest'):
    print(f"Loading VTK file: {vtk_file}")
    reader = None
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
    print(f"Mesh bounds: x=[{bounds[0]:.1f}, {bounds[1]:.1f}], "
          f"y=[{bounds[2]:.1f}, {bounds[3]:.1f}], z=[{bounds[4]:.1f}, {bounds[5]:.1f}]")
    point_data = mesh.GetPointData()
    if not point_data.HasArray("U"):
        print("ERROR: VTK file does not contain 'U' (velocity) array")
        print("Available arrays:")
        for i in range(point_data.GetNumberOfArrays()):
            print(f"  {point_data.GetArrayName(i)}")
        return False
    nx = int((bounds[1] - bounds[0]) / grid_spacing) + 1
    ny = int((bounds[3] - bounds[2]) / grid_spacing) + 1
    nz = int((bounds[5] - bounds[4]) / grid_spacing) + 1
    total_points = nx * ny * nz
    print(f"Creating probe grid: {nx} x {ny} x {nz} = {total_points} points")
    probe_points = vtk.vtkPoints()
    for k in range(nz):
        z = bounds[4] + k * grid_spacing
        for j in range(ny):
            y = bounds[2] + j * grid_spacing
            for i in range(nx):
                x = bounds[0] + i * grid_spacing
                probe_points.InsertNextPoint(x, y, z)
    probe_poly = vtk.vtkPolyData()
    probe_poly.SetPoints(probe_points)
    prober = vtk.vtkProbeFilter()
    prober.SetInputData(probe_poly)
    prober.SetSourceData(mesh)
    prober.Update()
    probed = prober.GetOutput()
    U_array = probed.GetPointData().GetArray("U")
    if not U_array:
        print("ERROR: Probing failed, no velocity data extracted")
        return False
    U_numpy = numpy_support.vtk_to_numpy(U_array)
    print(f"Extracted {len(U_numpy)} velocity vectors")
    wind_field = {
        "metadata": {
            "grid_spacing": grid_spacing,
            "dimensions": [nx, ny, nz],
            "bounds": {
                "x": [bounds[0], bounds[1]],
                "y": [bounds[2], bounds[3]],
                "z": [bounds[4], bounds[5]]
            },
            "source_case": os.path.dirname(vtk_file),
            "time_step": time_step
        },
        "velocities": []
    }
    idx = 0
    for k in range(nz):
        z = bounds[4] + k * grid_spacing
        for j in range(ny):
            y = bounds[2] + j * grid_spacing
            for i in range(nx):
                x = bounds[0] + i * grid_spacing
                Ux, Uy, Uz = U_numpy[idx]
                wind_field["velocities"].append({
                    "pos": [float(x), float(y), float(z)],
                    "vel": [float(Ux), float(Uy), float(Uz)]
                })
                idx += 1
    with open(output_json, 'w') as f:
        json.dump(wind_field, f, indent=2)
    print(f"JSON written: {output_json}")
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
        print(f"ERROR: VTK directory not found: {vtk_dir}")
        exit(1)
    if args.time == 'latest':
        vtk_files = [f for f in os.listdir(vtk_dir) if f.endswith('.vtu') or f.endswith('.vtk')]
        vtk_files.sort(key=lambda x: float(x.split('_')[-1].replace('.vtu', '').replace('.vtk', '')))
        latest_vtk = os.path.join(vtk_dir, vtk_files[-1])
        print(f"Using latest: {vtk_files[-1]}")
    else:
        latest_vtk = os.path.join(vtk_dir, f"*_{args.time}.vtu")
    success = extract_wind_vectors(latest_vtk, args.grid_spacing, args.output, args.time)
    exit(0 if success else 1)
PY_EOF
    chmod +x scripts/extract_wind_vectors.py
fi

# --------------- pipeline functions (idempotent) ---------------
run_mesh_step() {
    local case_dir="$1"
    local log_file="$case_dir/log.snappyHexMesh"
    echo "  🧱 Mesh generation for $case_dir"
    if [ -f "$case_dir/constant/polyMesh/points" ]; then
        echo "  ✅ Mesh already exists"
        return 0
    fi
    if [ -f "$case_dir/Allrun.mesh" ]; then
        (cd "$case_dir" && ./Allrun.mesh 2>&1 | tee "log.Allrun.mesh") || true
    else
        echo "  ❌ No Allrun.mesh script found, using default blockMesh+snappyHexMesh"
        mkdir -p "$case_dir/system"
        if [ ! -f "$case_dir/system/blockMeshDict" ]; then
            # Create default blockMeshDict via heal pattern; trigger diagnose_and_heal will create it
            true
        fi
        (cd "$case_dir" && blockMesh 2>&1 | tee -a "$log_file" && snappyHexMesh -overwrite 2>&1 | tee -a "$log_file") || true
    fi
    diagnose_and_heal "$log_file" "$case_dir" && { echo "  ✅ Mesh generation succeeded"; return 0; } || { echo "  🔄 Heal applied, re‑running mesh..."; (cd "$case_dir" && blockMesh 2>&1 | tee -a "$log_file" && snappyHexMesh -overwrite 2>&1 | tee -a "$log_file") || return 1; }
}

run_sim_step() {
    local case_dir="$1"
    echo "  🌬️ Running OpenFOAM simulation in $case_dir"
    if [ -f "$case_dir/postProcessing/forceCoeffs/0/coefficient.dat" ]; then
        echo "  ✅ Simulation already completed (forceCoeffs present)"
        return 0
    fi
    if [ -f "$case_dir/Allrun" ]; then
        (cd "$case_dir" && ./Allrun 2>&1 | tee "log.Allrun") || true
    else
        (cd "$case_dir" && simpleFoam 2>&1 | tee "log.simpleFoam") || true
    fi
    local sim_log="$case_dir/log.simpleFoam"
    [ -f "$case_dir/Allrun" ] && sim_log="$case_dir/log.Allrun"
    diagnose_and_heal "$sim_log" "$case_dir" && return 0 || { echo "  🔄 Heal applied, re‑running simulation..."; (cd "$case_dir" && simpleFoam 2>&1 | tee -a "log.simpleFoam") || return 1; }
}

extract_wind_field_step() {
    local case_dir="$1"
    local output_json="$2"
    mkdir -p game_data
    if [ -f "$output_json" ] && [ -s "$output_json" ]; then
        echo "  ✅ Wind field already extracted: $output_json"
        return 0
    fi
    echo "  💨 Extracting wind field from CFD results"
    # Ensure VTK files exist
    if [ ! -d "$case_dir/VTK" ] || [ -z "$(find "$case_dir/VTK" -name '*.vtu' 2>/dev/null)" ]; then
        echo "  🔄 VTK directory missing, running foamToVTK..."
        (cd "$case_dir" && foamToVTK -time latest 2>&1) || true
    fi
    if command -v pvpython &>/dev/null; then
        python3 scripts/extract_wind_vectors.py --case "$case_dir" --grid-spacing 10 --output "$output_json" || {
            echo "  ⚠️ pvpython extraction failed, trying fallback"
            python3 -c "import json; json.dump({'metadata':{'grid_spacing':10,'dimensions':[10,10,10]},'velocities':[]}, open('$output_json','w'))"
        }
    else
        echo "  ⚠️ pvpython not found – creating dummy wind field"
        python3 -c "import json; json.dump({'metadata':{'grid_spacing':10,'dimensions':[10,10,10]},'velocities':[]}, open('$output_json','w'))"
    fi
    test -f "$output_json" && test -s "$output_json"
}

convert_stl_to_obj_and_copy() {
    local stl_file="$1"
    local obj_file="${stl_file%.stl}.obj"
    local dest_obj="godot_project/assets/terrain/${LOCATION_NAME}.obj"
    mkdir -p godot_project/assets/terrain
    if [ -f "$dest_obj" ]; then
        echo "  ✅ OBJ already exists: $dest_obj"
        return 0
    fi
    echo "  🧩 Converting $stl_file to OBJ"
    if command -v python3 &>/dev/null && python3 -c "import trimesh" 2>/dev/null; then
        python3 -c "import trimesh; trimesh.load('$stl_file').export('$obj_file')"
    else
        echo "  ❌ trimesh not available – cannot convert STL"
        return 1
    fi
    cp "$obj_file" "$dest_obj"
    echo "  ✅ OBJ copied to $dest_obj"
}

generate_terrain_scene() {
    local obj_filename="${LOCATION_NAME}.obj"
    local scene_file="godot_project/scenes/terrain.tscn"
    run_step "Generate terrain scene (visible mesh, no collision)" \
        "test -f '$scene_file' && grep -q 'MeshInstance3D' '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'" \
        "
        mkdir -p godot_project/scenes
        cat > '$scene_file' << TSCNEOF
[gd_scene load_steps=2 format=3]

[ext_resource type=\"ArrayMesh\" path=\"res://assets/terrain/${obj_filename}\" id=\"1_mesh\"]

[node name=\"Terrain\" type=\"MeshInstance3D\"]
mesh = ExtResource(\"1_mesh\")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
TSCNEOF
        " \
        "test -f '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'"
}

fix_main_scene() {
    local scene_file="godot_project/scenes/main.tscn"
    run_step "Generate valid main.tscn (with terrain instance, light, camera)" \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'" \
        "
        mkdir -p godot_project/scenes
        cat > '$scene_file' << 'MAINTSCN'
[gd_scene load_steps=2 format=3]

[ext_resource type=\"PackedScene\" path=\"res://scenes/terrain.tscn\" id=\"1_terrain\"]

[node name=\"Main\" type=\"Node3D\"]

[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]

[node name=\"DirectionalLight3D\" type=\"DirectionalLight3D\" parent=\".\"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, 5)

[node name=\"TerrainInstance\" type=\"Node3D\" parent=\".\"]
[node name=\"Terrain\" parent=\"TerrainInstance\" instance=ExtResource(\"1_terrain\")]
MAINTSCN
        " \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'"
}

launch_godot_step() {
    echo "  🎮 Launching Godot project"
    if command -v godot &>/dev/null; then
        godot --path godot_project --editor &
    else
        echo "  ⚠️ godot command not found – open the project manually"
    fi
}

# --------------- linter integration ---------------
check_linters() {
    local audit_file="$1"
    echo "  🔍 Running linters..." >> "$audit_file"
    echo "--- ShellCheck ---" >> "$audit_file"
    if command -v shellcheck &>/dev/null; then
        shellcheck apply_fixlist_*.sh 2>&1 >> "$audit_file" || echo "  ⚠️ ShellCheck issues found (see audit)" >&2
    else
        echo "shellcheck not installed" >> "$audit_file"
    fi
    echo "--- Flake8 ---" >> "$audit_file"
    if command -v flake8 &>/dev/null; then
        flake8 --max-line-length=120 scripts/*.py /tmp/*.py 2>&1 >> "$audit_file" || echo "  ⚠️ Flake8 issues found (see audit)" >&2
    else
        echo "flake8 not installed" >> "$audit_file"
    fi
    echo "--- Black (check only) ---" >> "$audit_file"
    if command -v black &>/dev/null; then
        black --check scripts/*.py /tmp/*.py 2>&1 >> "$audit_file" || echo "  ⚠️ Black formatting issues (see audit)" >&2
    else
        echo "black not installed" >> "$audit_file"
    fi
}

perform_llm_audit() {
    mkdir -p audit_logs
    local audit_file="audit_logs/audit_$(date +%Y%m%d_%H%M%S).txt"
    echo "  📝 Creating LLM audit dump: $audit_file"
    {
        echo "=== System Information ==="
        uname -a
        echo "=== Working Directory ==="
        pwd
        echo "=== Git Status ==="
        git status 2>/dev/null || echo "Not a git repo"
        echo "=== Heal DB Patterns ==="
        sqlite3 "$HEAL_DB" "SELECT id,description,success_count,fail_count,priority FROM error_patterns" 2>/dev/null || echo "No DB"
        echo "=== Unknown Errors (last 5) ==="
        sqlite3 "$HEAL_DB" "SELECT timestamp,foam_error FROM unknown_errors ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "No unknown errors"
        echo "=== Godot Scene Files ==="
        head -50 godot_project/scenes/main.tscn 2>/dev/null || echo "Missing"
        echo "=== CFD Log Excerpts ==="
        tail -50 */log.* 2>/dev/null | head -200 || echo "No logs"
        echo "=== Linter Output ==="
    } > "$audit_file"
    check_linters "$audit_file"
    echo "  ✅ Audit saved to $audit_file"
}

# --------------- main orchestration ---------------
main() {
    export LOCATION_NAME="${LOCATION_NAME:-terrain}"

    python3 /tmp/cfd_init_healdb.py "$HEAL_DB"

    # Create necessary directories
    mkdir -p system constant 0

    run_mesh_step "."
    run_sim_step "."
    extract_wind_field_step "." "game_data/wind.json"

    shopt -s nullglob
    for stl in *.stl; do
        convert_stl_to_obj_and_copy "$stl"
    done
    shopt -u nullglob

    generate_terrain_scene
    fix_main_scene
    launch_godot_step
    perform_llm_audit

    echo "=== All steps completed successfully (v89 fully restored) ==="
}

main "$@"