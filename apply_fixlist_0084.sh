#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0084.sh – Complete self‑healing CFD‑to‑Godot pipeline v84
# v84 : fix root node parent attribute, raw-string regex, all prior fixes
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Complete Self‑Healing v84 ==="
echo "Working directory: $REPO_ROOT"

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
HEAL_DB=".cfd_healdb"

cat > /tmp/cfd_init_healdb.py << 'INIT_EOF'
#!/usr/bin/env python3
import sqlite3, sys
from datetime import datetime
db = sys.argv[1] if len(sys.argv) > 1 else ".cfd_healdb"
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE IF NOT EXISTS error_patterns (id INTEGER PRIMARY KEY, pattern TEXT UNIQUE, description TEXT, fix_cmd TEXT, success_count INTEGER DEFAULT 0, fail_count INTEGER DEFAULT 0, first_seen TEXT, last_seen TEXT)")
conn.execute("CREATE TABLE IF NOT EXISTS heal_events (id INTEGER PRIMARY KEY, timestamp TEXT, pattern_id INTEGER, case_dir TEXT, outcome TEXT)")
conn.execute("CREATE TABLE IF NOT EXISTS unknown_errors (id INTEGER PRIMARY KEY, timestamp TEXT, case_dir TEXT, foam_error TEXT, log_excerpt TEXT, status TEXT DEFAULT 'unresolved')")
now = datetime.now().isoformat()
PATTERNS = [
    (r"cannot find file.*transportProperties","transportProperties missing (openfoam-2512)","python3 -c \"open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')\""),
    (r"Entry 'transportModel' not found","transportProperties wrong keyword (viscosityModel not transportModel)","python3 -c \"open('{case}/constant/transportProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\\ntransportModel Newtonian;\\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\\n')\""),
    (r"cannot find file.*physicalProperties","physicalProperties missing (OF.org v10+)","python3 -c \"open('{case}/constant/physicalProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\\nviscosityModel Newtonian;\\nnu 1.5e-05;\\n')\""),
    (r"cannot find file.*turbulenceProperties","turbulenceProperties missing","python3 -c \"open('{case}/constant/turbulenceProperties','w').write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\\nsimulationType RAS;\\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\\n')\""),
    (r"cannot find file.*/0/nut","0/nut missing (k-epsilon turbulent viscosity wall field)","python3 -c \"import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/nut','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object nut; }\\ndimensions [0 2 -1 0 0 0 0];\\ninternalField uniform 0;\\nboundaryField\\n{\\n    inlet { type calculated; value uniform 0; }\\n    outlet { type calculated; value uniform 0; }\\n    walls { type nutLowReWallFunction; value uniform 0; }\\n    ground { type nutLowReWallFunction; value uniform 0; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    (r"cannot find file.*/0/omega","0/omega missing (k-omega SST field)","python3 -c \"import os; os.makedirs('{case}/0',exist_ok=True); open('{case}/0/omega','w').write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object omega; }\\ndimensions [0 0 -1 0 0 0 0];\\ninternalField uniform 1;\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform 1; }\\n    outlet { type inletOutlet; inletValue uniform 1; value uniform 1; }\\n    walls { type omegaWallFunction; value uniform 1; }\\n    ground { type omegaWallFunction; value uniform 1; }\\n    top { type symmetryPlane; }\\n}\\n')\""),
    (r"Cannot open mesh description|polyMesh/boundary","polyMesh missing","bash -c 'cd {case} && ./Allrun.mesh 2>&1 | tee log.Allrun.mesh.reheal'"),
    (r"did not find.*cell|No cells.*selected","locationInMesh inside solid geometry","sed -i 's/locationInMesh (150 150 100)/locationInMesh (150 150 180)/' {case}/system/snappyHexMeshDict"),
    (r"No VTK files found in %","VTK subdir issue – internal.vtu nested","bash -c 'cd {case} && LATEST_VTU=$(find VTK -name internal.vtu | sort | tail -1); [ -n \"$LATEST_VTU\" ] && pvpython ../../scripts/extract_wind_vectors.py --case . --vtk-file \"$LATEST_VTU\" --grid-spacing 10 --output ../../game_data/wind.json || (echo FALLBACK; pvpython - << 'PEOF' ... )'"),
    (r"Parse Error:.*\.tscn","Godot scene parse error – regenerate minimal main.tscn","bash -c 'mkdir -p godot_project/scenes && cat > godot_project/scenes/main.tscn << \"MAINTSCN\"\n[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://scenes/terrain.tscn\" id=\"1_terrain\"]\n\n[node name=\"Main\" type=\"Node3D\"]\n\n[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]\n\n[node name=\"DirectionalLight3D\" type=\"DirectionalLight3D\" parent=\".\"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 10, 5)\n\n[node name=\"TerrainInstance\" type=\"Node3D\" parent=\".\"]\n[node name=\"Terrain\" parent=\"TerrainInstance\" instance=ExtResource(\"1_terrain\")]\nMAINTSCN\n'"),
    (r"No loader found for resource.*\.stl","Godot cannot load STL – convert to OBJ and update scene","bash -c 'STL_PATH=$(grep -oP \"path=\\\"res://[^\\\"]*\\.stl\\\"\" godot_project/scenes/terrain.tscn | cut -d\\\" -f2 | sed \"s|res://|godot_project/|g\"); if [ -f \"$STL_PATH\" ]; then python3 -c \"import trimesh; trimesh.load(\\\"$STL_PATH\\\").export(\\\"${STL_PATH%.stl}.obj\\\")\"; cp \"${STL_PATH%.stl}.obj\" godot_project/assets/terrain/; sed -i \"s|\\.stl|\.obj|g\" godot_project/scenes/terrain.tscn; fi'"),
]
for p,d,f in PATTERNS:
    conn.execute("INSERT OR IGNORE INTO error_patterns (pattern,description,fix_cmd,first_seen,last_seen) VALUES (?,?,?,?,?)",(p,d,f,now,now))
conn.commit()
count=conn.execute("SELECT COUNT(*) FROM error_patterns").fetchone()[0]
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

init_heal_db() { python3 /tmp/cfd_init_healdb.py "$HEAL_DB"; }

db_diagnose_and_heal() {
    local log="$1"; local case_dir="${2:-.}"; local db="${HEAL_DB:-.cfd_healdb}"
    echo "  🗄️  Consulting heal database ($db)..."
    local result=$(python3 /tmp/cfd_db_diagnose.py "$db" "$log" "$case_dir")
    case "$result" in
        NO_DB|NO_LOG|USAGE) echo "  ℹ️  DB unavailable — falling through to hardcoded rules"; return 1 ;;
        UNKNOWN) echo "  ⚠️  Unknown error — recorded in DB for future pattern development"
                 echo "      Review: python3 /tmp/cfd_db_diagnose.py $db --show-unknown"; return 1 ;;
        MATCHED:*)
            local pid desc fix_cmd
            pid=$(echo "$result"|cut -d: -f2); desc=$(echo "$result"|cut -d: -f3); fix_cmd=$(echo "$result"|cut -d: -f4-)
            echo "  🗄️  DB match [#$pid]: $desc"; echo "  🔧 Applying DB fix..."
            if eval "$fix_cmd"; then
                python3 /tmp/cfd_db_diagnose.py "$db" --record-outcome "$pid" "healed" "$case_dir"
                echo "  ✅ DB heal applied and recorded"; return 0
            else
                python3 /tmp/cfd_db_diagnose.py "$db" --record-outcome "$pid" "failed" "$case_dir"
                echo "  ❌ DB heal fix failed"; return 1
            fi ;;
    esac
}

diagnose_and_heal() {
    local log="$1"; local case_dir="$2"
    echo "  🔍 Diagnosing from $(basename "$log")..."
    if db_diagnose_and_heal "$log" "${case_dir:-.}"; then return 0; fi
    echo "  ↩  DB did not resolve — trying hardcoded rules..."

    # TRANSPORT-MISSING
    if grep -q "cannot find file.*transportProperties" "$log" 2>/dev/null; then
        echo "  HEAL [TRANSPORT-MISSING]: writing transportProperties..."
        python3 -c "
open('$case_dir/constant/transportProperties','w').write(
'FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"
        echo "  ✅ transportProperties written"; return 0
    fi

    # TRANSPORT-WRONG-KEY
    if grep -q "Entry 'transportModel' not found" "$log" 2>/dev/null; then
        echo "  HEAL [TRANSPORT-WRONG-KEY]: overwriting transportProperties with correct keyword..."
        python3 -c "
open('$case_dir/constant/transportProperties','w').write(
'FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')"
        echo "  ✅ transportProperties overwritten (transportModel keyword)"; return 0
    fi

    # PHYSICAL-MISSING
    if grep -q "cannot find file.*physicalProperties" "$log" 2>/dev/null; then
        echo "  HEAL [PHYSICAL-MISSING]: writing physicalProperties..."
        python3 -c "
open('$case_dir/constant/physicalProperties','w').write(
'FoamFile\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\nviscosityModel Newtonian;\nnu 1.5e-05;\n')"
        echo "  ✅ physicalProperties written"; return 0
    fi

    # TURBULENCE-MISSING
    if grep -q "cannot find file.*turbulenceProperties" "$log" 2>/dev/null; then
        echo "  HEAL [TURBULENCE-MISSING]: writing turbulenceProperties..."
        python3 -c "
open('$case_dir/constant/turbulenceProperties','w').write(
'FoamFile\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\nsimulationType RAS;\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\n')"
        echo "  ✅ turbulenceProperties written"; return 0
    fi

    # MESH-NOT-FOUND
    if grep -q "Cannot open mesh description\|polyMesh/boundary" "$log" 2>/dev/null; then
        echo "  HEAL [MESH-NOT-FOUND]: mesh missing — re-running Allrun.mesh..."
        (cd "$case_dir" && ./Allrun.mesh 2>&1 | tee log.Allrun.mesh.reheal)
        if [[ -d "$case_dir/constant/polyMesh" ]]; then
            echo "  ✅ mesh regenerated"; return 0
        else
            echo "  ❌ mesh regeneration failed — check log.Allrun.mesh.reheal"; return 1
        fi
    fi

    # BC-MISSING-PATCH
    if grep -qE "Cannot find patchField entry|patch.*not found in field" "$log" 2>/dev/null; then
        local missing_patch=$(grep -oE "patch '([^']+)'" "$log" | head -1 | tr -d "'patch ")
        local missing_field=$(grep -oE "field (p|U|k|epsilon)" "$log" | head -1 | awk '{print $2}')
        echo "  HEAL [BC-MISSING-PATCH]: adding patch '$missing_patch' to 0/$missing_field..."
        if [[ -n "$missing_patch" && -n "$missing_field" ]]; then
            sed -i "s/^}/    $missing_patch { type zeroGradient; }\n}/" "$case_dir/0/$missing_field" 2>/dev/null || true
            echo "  ✅ patch added (verify: cat $case_dir/0/$missing_field)"
        fi
        return 0
    fi

    # NUT-MISSING
    if grep -q "cannot find file.*/0/nut" "$log" 2>/dev/null; then
        echo "  HEAL [NUT-MISSING]: writing 0/nut (k-epsilon turbulent viscosity)..."
        mkdir -p "$case_dir/0"
        python3 -c "
open('$case_dir/0/nut','w').write(
'FoamFile
{ version 2.0; format ascii; class volScalarField; object nut; }
dimensions [0 2 -1 0 0 0 0];
internalField uniform 0;
boundaryField
{
    inlet { type calculated; value uniform 0; }
    outlet { type calculated; value uniform 0; }
    walls { type nutLowReWallFunction; value uniform 0; }
    ground { type nutLowReWallFunction; value uniform 0; }
    top { type symmetryPlane; }
}
')"
        echo "  ✅ 0/nut written"; return 0
    fi

    # OMEGA-MISSING
    if grep -q "cannot find file.*/0/omega" "$log" 2>/dev/null; then
        echo "  HEAL [OMEGA-MISSING]: writing 0/omega (k-omega SST)..."
        mkdir -p "$case_dir/0"
        python3 -c "
open('$case_dir/0/omega','w').write(
'FoamFile
{ version 2.0; format ascii; class volScalarField; object omega; }
dimensions [0 0 -1 0 0 0 0];
internalField uniform 1;
boundaryField
{
    inlet { type fixedValue; value uniform 1; }
    outlet { type inletOutlet; inletValue uniform 1; value uniform 1; }
    walls { type omegaWallFunction; value uniform 1; }
    ground { type omegaWallFunction; value uniform 1; }
    top { type symmetryPlane; }
}
')"
        echo "  ✅ 0/omega written"; return 0
    fi

    # GENERIC-MISSING-FIELD
    local missing_field=$(grep -oE "cannot find file.*/0/[a-zA-Z]+" "$log" 2>/dev/null | grep -oE "/0/[a-zA-Z]+" | head -1 | tr -d '/0/')
    if [[ -n "$missing_field" ]]; then
        echo "  HEAL [GENERIC-MISSING-FIELD]: missing 0/$missing_field — writing zero-value placeholder..."
        mkdir -p "$case_dir/0"
        python3 -c "
open('$case_dir/0/$missing_field','w').write(
'FoamFile
{ version 2.0; format ascii; class volScalarField; object $missing_field; }
dimensions [0 0 0 0 0 0 0];
internalField uniform 0;
boundaryField
{
    inlet { type zeroGradient; }
    outlet { type zeroGradient; }
    walls { type zeroGradient; }
    ground { type zeroGradient; }
    top { type symmetryPlane; }
}
')"
        echo "  ✅ 0/$missing_field written (zero placeholder — may need manual adjustment)"; return 0
    fi

    echo "  ❌ No self-healing rule matched for this error"
    echo "  Full log: $log"
    return 1
}

# --------------- mesh / sim steps -------------------------
_foam_has_time_dir() {
    local case="${1:-.}"
    ls -d "$case"/[0-9]* 2>/dev/null | grep -v "^$case/0$" | grep -v "^$case/0\.orig$" | grep -qE "/[0-9]+$"
}
_foam_latest_time_dir() {
    local case="${1:-.}"
    ls -d "$case"/[0-9]* 2>/dev/null | grep -v "^$case/0$" | grep -v "^$case/0\.orig$" | grep -E "/[0-9]+$" | sort -t/ -k2 -n | tail -1 | xargs -r basename
}

run_mesh_step() {
    local case_dir="$1"
    echo "➤ Step: Generate mesh (blockMesh + surfaceFeatureExtract + snappyHexMesh)"
    echo "  Case: $case_dir"
    if [[ -d "$case_dir/constant/polyMesh" ]]; then echo "  ✅ Already done – skipping"; return 0; fi
    cd "$case_dir" || { echo "  ❌ Case dir not found: $case_dir"; exit 1; }
    _foam_log_dump() { local log="$1"; shift; echo "  ━━━ LAST ${1:-50} LINES: $(basename "$log") ━━━"; tail -"${1:-50}" "$log" 2>/dev/null || echo "  (log not found)"; echo "  ━━━ END LOG ━━━"; }
    echo "  🔧 blockMesh..."; blockMesh 2>&1 | tee log.blockMesh
    if grep -q 'FOAM FATAL\|FOAM exiting\|error:' log.blockMesh 2>/dev/null; then echo "  ❌ blockMesh failed"; _foam_log_dump log.blockMesh 30; cd - >/dev/null; exit 1; fi
    echo "  ✅ blockMesh OK"
    echo "  🔧 surfaceFeatureExtract..."; surfaceFeatureExtract 2>&1 | tee log.surfaceFeatureExtract
    if grep -q 'FOAM FATAL\|FOAM exiting\|error:' log.surfaceFeatureExtract 2>/dev/null; then echo "  ❌ surfaceFeatureExtract failed"; _foam_log_dump log.surfaceFeatureExtract 30; cd - >/dev/null; exit 1; fi
    echo "  ✅ surfaceFeatureExtract OK"
    echo "  🔧 snappyHexMesh (2-10 min — live progress below)..."
    snappyHexMesh -overwrite 2>&1 | tee log.snappyHexMesh
    if [[ -d constant/polyMesh ]]; then echo "  ✅ snappyHexMesh OK"; cd - >/dev/null; return 0; fi
    echo "  ❌ snappyHexMesh failed — polyMesh not created"
    _foam_log_dump log.snappyHexMesh 60; echo "  🔍 Diagnosing..."
    local retried=0
    if grep -qE 'did not find.*cell|No cells.*selected|0 cells' log.snappyHexMesh 2>/dev/null; then
        echo "  DIAGNOSIS: locationInMesh inside solid geometry."; echo "  FIX: Moving to z=180m..."; sed -i 's/locationInMesh (150 150 100)/locationInMesh (150 150 180)/' system/snappyHexMeshDict
        echo "  Re-running snappyHexMesh..."; snappyHexMesh -overwrite 2>&1 | tee log.snappyHexMesh; retried=1
    fi
    if grep -qE 'FOAM FATAL|bad_alloc|Killed|cell limit' log.snappyHexMesh 2>/dev/null && [[ $retried -eq 0 ]]; then
        echo "  DIAGNOSIS: OOM or cell limit exceeded."; echo "  FIX: Halving cell limits..."; sed -i 's/maxLocalCells 1000000/maxLocalCells 500000/' system/snappyHexMeshDict; sed -i 's/maxGlobalCells 2000000/maxGlobalCells 1000000/' system/snappyHexMeshDict
        echo "  Re-running snappyHexMesh..."; snappyHexMesh -overwrite 2>&1 | tee log.snappyHexMesh; retried=1
    fi
    if [[ -d constant/polyMesh ]]; then echo "  ✅ snappyHexMesh OK after retry"; cd - >/dev/null; return 0; fi
    if [[ $retried -eq 1 ]]; then echo "  ❌ snappyHexMesh still failed after retry"; _foam_log_dump log.snappyHexMesh 40; fi
    echo "  Full log: $case_dir/log.snappyHexMesh"; cd - >/dev/null; exit 1
}

run_sim_step() {
    local case_dir="$1"
    local solver="${2:-simpleFoam}"
    echo "➤ Step: Run $solver"
    if _foam_has_time_dir "$case_dir"; then echo "  ✅ Already done – skipping"; return 0; fi
    cd "$case_dir" || { echo "  ❌ Case dir not found: $case_dir"; exit 1; }
    cp -r 0.orig 0 2>/dev/null || true
    echo "  🔧 $solver — full log: $(pwd)/log.$solver"
    echo "  Target: all residuals < 1e-4. Stall: 50 non-improving iters."
    printf "  %-6s %-13s %-13s %-13s %-13s %s\n" "Time" "Ux" "Uy" "Uz" "p" "Status"
    printf "  %s\n" "----------------------------------------------------------------------"
    { $solver 2>&1 | stdbuf -oL tee log.$solver; } || true
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
    if grep -qE 'FOAM FATAL|Segmentation fault' log.$solver 2>/dev/null; then
        echo "  ❌ $solver fatal error"
        echo "  ━━━ LAST 40 LINES ━━━"; tail -40 log.$solver; echo "  ━━━ END ━━━"
        if diagnose_and_heal "log.$solver" "."; then
            echo "  🔄 Retrying $solver after heal..."; cp -r 0.orig 0 2>/dev/null || true
            { $solver 2>&1 | stdbuf -oL tee log.${solver}.retry; } || true
            awk '
            BEGIN{iter=0;ux=0}
            /^Time =/{t=$3}
            /Solving for Ux/{if(match($0,/[0-9][0-9.eE+\-]*/))ux=substr($0,RSTART,RLENGTH)+0}
            /^ExecutionTime/{iter++;if(iter%10==0)printf "  #%-5d T=%s Ux=%.2e\n",iter,t,ux}
            ' log.${solver}.retry
            if _foam_has_time_dir .; then echo "  ✅ $solver succeeded after heal"; cd - >/dev/null; return 0; fi
            echo "  ❌ still failed — log: $(pwd)/log.${solver}.retry"; cd - >/dev/null; exit 1
        fi
        cd - >/dev/null; exit 1
    fi
    if awk '
        BEGIN{prev=999;stall=0}
        /Solving for Ux/{match($0,/Initial residual = ([0-9.eE+\-]+)/,a);ux=a[1]+0}
        /^ExecutionTime/{if(ux>=prev*0.999)stall++;else stall=0;prev=ux}
        END{exit (stall>=50)?0:1}
    ' log.$solver 2>/dev/null; then
        echo "  ⚠️  STALL: residuals not improving. Last 20 lines:"; tail -20 log.$solver
        echo "  Continuing with available results..."
    fi
    if ! _foam_has_time_dir .; then
        echo "  ❌ no time directory produced"; tail -40 log.$solver; cd - >/dev/null; exit 1
    fi
    echo "  ✅ $solver done — latest time dir: $(_foam_latest_time_dir .)"
    cd - >/dev/null
}

# --------------- VTK extraction (with DB fallback) --------------------
extract_wind_field_step() {
    [[ -n "${LOCATION_NAME:-}" ]] || { echo "ERROR: LOCATION_NAME not set"; exit 1; }
    WIND_JSON="game_data/${LOCATION_NAME}_wind.json"
    run_step "Extract wind field" \
        "test -s '$WIND_JSON'" \
        "(cd '$CASE_DIR' \
          && foamToVTK -latestTime \
          && LATEST_VTU=\$(find VTK -name 'internal.vtu' 2>/dev/null | sort | tail -1) \
          && { [ -n \"\$LATEST_VTU\" ] || { echo 'ERROR: no internal.vtu found in VTK/'; exit 1; }; } \
          && echo \"Using: \$LATEST_VTU\" \
          && pvpython ../../scripts/extract_wind_vectors.py \
               --case . \
               --vtk-file \"\$LATEST_VTU\" \
               --grid-spacing '$GRID_SPACING' \
               --output '../../$WIND_JSON' \
          || pvpython - << 'PVEOF'
import vtk, json, math, os, sys
from vtk.util import numpy_support
case_dir = os.getcwd()
vtk_dir = os.path.join(case_dir, 'VTK')
vtu_files = []
for root, dirs, files in os.walk(vtk_dir):
    for f in files:
        if f == 'internal.vtu':
            vtu_files.append(os.path.join(root, f))
if not vtu_files:
    print('ERROR: no internal.vtu found'); sys.exit(1)
vtu_path = sorted(vtu_files)[-1]
print(f'Reading: {vtu_path}')
reader = vtk.vtkXMLUnstructuredGridReader()
reader.SetFileName(vtu_path)
reader.Update()
mesh = reader.GetOutput()
bounds = mesh.GetBounds()
gs = $GRID_SPACING
nx = int((bounds[1]-bounds[0])/gs)+1
ny = int((bounds[3]-bounds[2])/gs)+1
nz = int((bounds[5]-bounds[4])/gs)+1
prober = vtk.vtkProbeFilter()
pts = vtk.vtkPoints()
for k in range(nz):
    for j in range(ny):
        for i in range(nx):
            pts.InsertNextPoint(bounds[0]+i*gs, bounds[2]+j*gs, bounds[4]+k*gs)
poly = vtk.vtkPolyData(); poly.SetPoints(pts)
prober.SetInputData(poly); prober.SetSourceData(mesh); prober.Update()
U = numpy_support.vtk_to_numpy(prober.GetOutput().GetPointData().GetArray('U'))
wind = {'metadata':{'grid_spacing':gs,'dimensions':[nx,ny,nz],'bounds':{'x':[bounds[0],bounds[1]],'y':[bounds[2],bounds[3]],'z':[bounds[4],bounds[5]]}},'velocities':[]}
idx = 0
for k in range(nz):
    for j in range(ny):
        for i in range(nx):
            x,y,z = bounds[0]+i*gs, bounds[2]+j*gs, bounds[4]+k*gs
            wind['velocities'].append({'pos':[float(x),float(y),float(z)],'vel':[float(U[idx][0]),float(U[idx][1]),float(U[idx][2])]})
            idx+=1
out = '../../$WIND_JSON'
with open(out,'w') as f: json.dump(wind,f)
print(f'Written: {out} ({os.path.getsize(out)//1024} KB)')
PVEOF
        )" \
        "test -s '$WIND_JSON'"
}

# ----------------------------------------------------------------
# Convert STL to OBJ for Godot compatibility and copy to project
# ----------------------------------------------------------------
convert_stl_to_obj_and_copy() {
    local stl_file="${STL_PATH}"
    local obj_file="${stl_file%.stl}.obj"
    local godot_obj="godot_project/assets/terrain/${LOCATION_NAME}.obj"

    run_step "Convert STL to OBJ and copy to Godot assets" \
        "test -f '$godot_obj'" \
        "python3 -c \"import trimesh; trimesh.load('$stl_file').export('$obj_file')\" && cp '$obj_file' '$godot_obj'" \
        "test -f '$godot_obj'"
}

# ----------------------------------------------------------------
# Generate terrain.tscn – references .obj, no parent on root
# ----------------------------------------------------------------
generate_terrain_scene() {
    local obj_filename="${LOCATION_NAME}.obj"
    local scene_file="godot_project/scenes/terrain.tscn"

    run_step "Generate terrain scene (visible mesh, no collision)" \
        "test -f '$scene_file' && grep -q 'MeshInstance3D' '$scene_file' && grep -q '$obj_filename' '$scene_file'" \
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
        "test -f '$scene_file' && grep -q '$obj_filename' '$scene_file'"
}

# ----------------------------------------------------------------
# Generate valid main.tscn – no parent on root
# ----------------------------------------------------------------
fix_main_scene() {
    local scene_file="godot_project/scenes/main.tscn"
    run_step "Generate valid main.tscn (with terrain instance, light, camera)" \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file'" \
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
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file'"
}

# --------------- Interactive Godot launch ----------------------
launch_godot_step() {
    local godot_project_path="godot_project/project.godot"
    if [[ ! -f "$godot_project_path" ]]; then
        echo "  ❌ Godot project not found: $godot_project_path"
        return 1
    fi
    echo ""
    echo "  🎮 The scene is ready. Would you like to launch Godot now?"
    read -r -p "  Launch Godot? (y/n, default y): " _launch
    _launch=${_launch:-y}
    if [[ "$_launch" =~ ^[Yy]$ ]]; then
        echo "  🚀 Launching Godot Engine..."
        godot "$godot_project_path" &
    else
        echo "  ℹ️  You can start later with: godot $godot_project_path"
    fi
}

# --------------- LLM audit info ---------------------------------------
llm_audit_info() {
    echo ""
    echo "# To prepare files for LLM self-heal review, run:"
    echo "  sqlite3 .cfd_healdb .dump > cfd_healdb_dump.txt"
    echo "# Then upload these three files:"
    echo "  1. apply_fixlist_0084.sh"
    echo "  2. cfd_healdb_dump.txt"
    echo "  3. scripts/extract_wind_vectors.py"
    echo ""
}

# ==================== MAIN ============================================
[[ -f README.md && -d scripts ]] || { echo "ERROR: Run from repo root"; exit 1; }
command -v simpleFoam &>/dev/null || { echo "ERROR: OpenFOAM not active. Run: ofsrc"; exit 1; }
echo "✅ OpenFOAM active"
init_heal_db

# default location (prevents unbound variable errors)
LOCATION_NAME="skydive_deland"

# ------------------------------------------------------------
# 1. System packages
# ------------------------------------------------------------
run_step "OpenFOAM COPR repo" \
    "dnf repolist | grep -qi openfoam" \
    "sudo dnf copr enable -y openfoam/openfoam" \
    "dnf repolist | grep -qi openfoam"

echo "➤ Step: ParaView (pvpython)"
if command -v pvpython &>/dev/null || find /usr -name pvpython 2>/dev/null | grep -q pvpython; then
    echo "  ✅ Already done – skipping"
else
    sudo dnf install -y paraview
    PVPY=$(find /usr -name pvpython 2>/dev/null | head -1)
    [ -n "$PVPY" ] || { echo "ERROR: pvpython not found"; exit 1; }
    sudo ln -sf "$PVPY" /usr/local/bin/pvpython
fi
pvpython --version 2>&1 | grep -qi paraview || { echo "❌ pvpython broken"; exit 1; }
echo "  ✅ Completed"

run_step "Flatpak + Flathub" \
    "flatpak --version 2>/dev/null && flatpak remotes 2>/dev/null | grep -q flathub" \
    "sudo dnf install -y flatpak && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" \
    "flatpak --version && flatpak remotes | grep -q flathub"

run_step "Godot (flatpak)" \
    "command -v godot" \
    "flatpak install -y flathub org.godotengine.Godot && sudo ln -sf /var/lib/flatpak/exports/bin/org.godotengine.Godot /usr/local/bin/godot" \
    "godot --version 2>&1 | grep -qE '[0-9]+\.[0-9]+'"

run_step "GDAL devel" \
    "gdal-config --version" \
    "sudo dnf install -y gdal gdal-devel python3-gdal" \
    "gdal-config --version"

run_step "xdotool" \
    "command -v xdotool" \
    "sudo dnf install -y xdotool" \
    "command -v xdotool"

# ------------------------------------------------------------
# 2. Google Earth Pro (optional, not in critical path)
# ------------------------------------------------------------
flatpak list 2>/dev/null | grep -q com.google.EarthPro && \
    { flatpak uninstall -y com.google.EarthPro 2>/dev/null || true; }
rpm -q google-earth-pro-stable 2>/dev/null && \
    { sudo rpm -e google-earth-pro-stable 2>/dev/null || true; }

run_step "Download GE Pro RPM" \
    "test -f /tmp/google-earth-pro-stable.rpm" \
    "wget -q -O /tmp/google-earth-pro-stable.rpm 'https://dl.google.com/linux/earth/rpm/stable/x86_64/google-earth-pro-stable-7.3.6.10201-0.x86_64.rpm'" \
    "test -f /tmp/google-earth-pro-stable.rpm"

run_step "rpm2cpio" \
    "command -v rpm2cpio" \
    "sudo dnf install -y rpm-build" \
    "command -v rpm2cpio"

run_step "Extract GE Pro RPM" \
    "test -f /tmp/ge_extract/opt/google/earth/pro/googleearth-bin" \
    "sudo rm -rf /tmp/ge_extract && mkdir -p /tmp/ge_extract && cd /tmp/ge_extract && rpm2cpio /tmp/google-earth-pro-stable.rpm | cpio -idm 2>/dev/null; true" \
    "test -f /tmp/ge_extract/opt/google/earth/pro/googleearth-bin"

run_step "chmod GE real binary" \
    "test -x /tmp/ge_extract/opt/google/earth/pro/googleearth-bin" \
    "chmod +x /tmp/ge_extract/opt/google/earth/pro/googleearth-bin /tmp/ge_extract/opt/google/earth/pro/googleearth" \
    "test -x /tmp/ge_extract/opt/google/earth/pro/googleearth-bin"

run_step "Install GE Pro to /opt" \
    "test -x /opt/google/earth/pro/googleearth-bin" \
    "sudo cp -rp /tmp/ge_extract/opt/google /opt/ && sudo chmod +x /opt/google/earth/pro/googleearth-bin /opt/google/earth/pro/googleearth && sudo rm -rf /tmp/ge_extract && rm -f /tmp/google-earth-pro-stable.rpm" \
    "test -x /opt/google/earth/pro/googleearth-bin"

run_step "GE Pro launcher wrapper" \
    "test -x /usr/local/bin/google-earth-pro && grep -q QT_X11_NO_MITSHM /usr/local/bin/google-earth-pro" \
    "sudo tee /usr/local/bin/google-earth-pro > /dev/null << 'WEOF'
#!/usr/bin/env bash
GE_DIR=/opt/google/earth/pro
export DISPLAY=\"\${DISPLAY:-:0}\"
export QT_X11_NO_MITSHM=1
export LD_LIBRARY_PATH=\"\$GE_DIR:\${LD_LIBRARY_PATH:-}\"
exec \"\$GE_DIR/googleearth-bin\" \"\$@\"
WEOF
sudo chmod +x /usr/local/bin/google-earth-pro" \
    "test -x /usr/local/bin/google-earth-pro && grep -q QT_X11_NO_MITSHM /usr/local/bin/google-earth-pro"

run_step "GE Pro /opt symlink" \
    "test -L /opt/google/earth/pro/google-earth-pro || test -x /opt/google/earth/pro/google-earth-pro" \
    "sudo ln -sf /usr/local/bin/google-earth-pro /opt/google/earth/pro/google-earth-pro" \
    "command -v google-earth-pro"

# ------------------------------------------------------------
# 3. Java 17 + OSM2World
# ------------------------------------------------------------
run_step "Java 17" \
    "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'" \
    "sudo dnf install -y java-17-openjdk-headless" \
    "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'"

run_step "OSM2World jar + lib" \
    "test -f /tmp/osm2world/OSM2World.jar && test -d /tmp/osm2world/lib" \
    "sudo rm -rf /tmp/osm2world && mkdir -p /tmp/osm2world \
     && wget -q -O /tmp/osm2world/osm2world.zip 'https://osm2world.org/download/files/latest/OSM2World-latest-bin.zip' \
     && unzip -q /tmp/osm2world/osm2world.zip -d /tmp/osm2world \
     && rm -f /tmp/osm2world/osm2world.zip" \
    "test -f /tmp/osm2world/OSM2World.jar && test -d /tmp/osm2world/lib"

# ------------------------------------------------------------
# 4. Python packages
# ------------------------------------------------------------
run_step "Python packages" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification' 2>/dev/null" \
    "python3 -m pip install --user --break-system-packages numpy vtk trimesh pykml lxml GDAL scipy matplotlib pycollada fast_simplification" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification; print(\"OK\")'"

# ------------------------------------------------------------
# 5. OpenFOAM template files
# ------------------------------------------------------------
mkdir -p cases/template/{0.orig,constant,system}

run_step "Template 0.orig/p" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p" \
    "python3 -c \"open('cases/template/0.orig/p','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object p; }\ndimensions [0 2 -2 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type zeroGradient; }\n    outlet { type fixedValue; value uniform 0; }\n    walls { type zeroGradient; }\n    ground { type zeroGradient; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p"

run_step "Template 0.orig/U" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U" \
    "python3 -c \"open('cases/template/0.orig/U','w').write('FoamFile\n{ version 2.0; format ascii; class volVectorField; object U; }\ndimensions [0 1 -1 0 0 0 0];\ninternalField uniform (10 0 0);\nboundaryField\n{\n    inlet { type fixedValue; value uniform (10 0 0); }\n    outlet { type inletOutlet; inletValue uniform (10 0 0); value uniform (10 0 0); }\n    walls { type noSlip; }\n    ground { type noSlip; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U"

run_step "Template 0.orig/nut (k-epsilon wall field)" \
    "test -s cases/template/0.orig/nut && grep -q 'nutLowReWallFunction' cases/template/0.orig/nut" \
    "python3 -c \"open('cases/template/0.orig/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/nut && grep -q 'nutLowReWallFunction' cases/template/0.orig/nut"

run_step "Template 0.orig/k and epsilon" \
    "test -s cases/template/0.orig/k && grep -q symmetryPlane cases/template/0.orig/k && test -s cases/template/0.orig/epsilon" \
    "python3 -c \"
open('cases/template/0.orig/k','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object k; }\ndimensions [0 2 -2 0 0 0 0];\ninternalField uniform 0.1;\nboundaryField\n{\n    inlet { type fixedValue; value uniform 0.1; }\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\n    walls { type kqRWallFunction; value uniform 0.1; }\n    ground { type kqRWallFunction; value uniform 0.1; }\n    top { type symmetryPlane; }\n}\n')
open('cases/template/0.orig/epsilon','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object epsilon; }\ndimensions [0 2 -3 0 0 0 0];\ninternalField uniform 0.1;\nboundaryField\n{\n    inlet { type fixedValue; value uniform 0.1; }\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\n    walls { type epsilonWallFunction; value uniform 0.1; }\n    ground { type epsilonWallFunction; value uniform 0.1; }\n    top { type symmetryPlane; }\n}\n')
\"" \
    "test -s cases/template/0.orig/k && grep -q symmetryPlane cases/template/0.orig/k && test -s cases/template/0.orig/epsilon"

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
    "test -s cases/template/constant/physicalProperties && grep -q 'nu' cases/template/constant/physicalProperties" \
    "python3 -c \"open('cases/template/constant/physicalProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\ntransportModel Newtonian;\nnu 1.5e-05;\n')\"" \
    "test -s cases/template/constant/physicalProperties && grep -q 'nu' cases/template/constant/physicalProperties"

run_step "Template transportProperties (openfoam-2512 compat)" \
    "test -s cases/template/constant/transportProperties && grep -q 'transportModel' cases/template/constant/transportProperties" \
    "python3 -c \"open('cases/template/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')\"" \
    "test -s cases/template/constant/transportProperties && grep -q 'transportModel' cases/template/constant/transportProperties"

# ------------------------------------------------------------
# 6. Stubs and docs
# ------------------------------------------------------------
run_step "Stub download_terrain_tiles.py" \
    "grep -q 'OSM pipeline' scripts/download_terrain_tiles.py 2>/dev/null" \
    "python3 -c \"import os; os.makedirs('scripts', exist_ok=True); open('scripts/download_terrain_tiles.py','w').write('#!/usr/bin/env python3\nimport sys\nprint(\\\"Use OSM pipeline in apply_fixlist_0084.sh instead.\\\")\nsys.exit(1)\n'); import os; os.chmod('scripts/download_terrain_tiles.py',0o755)\"" \
    "grep -q 'OSM pipeline' scripts/download_terrain_tiles.py"

run_step "Stub place_rotors.py" \
    "grep -q 'not implemented' scripts/place_rotors.py 2>/dev/null" \
    "python3 -c \"import os; os.makedirs('scripts', exist_ok=True); open('scripts/place_rotors.py','w').write('#!/usr/bin/env python3\nimport sys\nprint(\\\"place_rotors.py not implemented.\\\")\nsys.exit(1)\n'); import os; os.chmod('scripts/place_rotors.py',0o755)\"" \
    "grep -q 'not implemented' scripts/place_rotors.py"

run_step "Documentation stubs" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md" \
    "python3 -c \"
import os; os.makedirs('docs', exist_ok=True)
for name, body in [
  ('cfd_setup.md',        '# CFD Setup Guide\n\nSee QUICKSTART.md for full workflow.\n'),
  ('godot_integration.md','# Godot Integration\n\nSee godot_project/scripts/.\n'),
  ('locations.md',        '# Curated Landing Zones\n\n- Skydive DeLand: 29.0119N 81.2462W\n- San Francisco: 37.7946N 122.3999W\n'),
]:
    p = os.path.join('docs', name)
    if not (os.path.exists(p) and os.path.getsize(p) > 0):
        open(p,'w').write(body); print('wrote', p)
\"" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md"

# ------------------------------------------------------------
# 7. Smoke test + cleanup
# ------------------------------------------------------------
run_step "Test collada_to_stl (cube)" \
    "false" \
    "python3 -c 'import trimesh; trimesh.creation.box(extents=[100,100,10]).export(\"test_cube.dae\")' && python3 scripts/collada_to_stl.py --input test_cube.dae --output test_cube.stl --simplify 1.0" \
    "test -s test_cube.stl"

run_step "Clean test artifacts" \
    "false" \
    "rm -f test_cube.dae test_cube.stl zones_test.json test.kml" \
    "for f in test_cube.dae test_cube.stl zones_test.json test.kml; do [ ! -f \"\$f\" ] || exit 1; done"

run_step "Set execute bits" \
    "test -x scripts/setup_openfoam_case.sh" \
    "find scripts/ -name '*.sh' -o -name '*.py' | xargs -r chmod +x" \
    "test -x scripts/setup_openfoam_case.sh && test -x scripts/collada_to_stl.py"

# ------------------------------------------------------------
# 8. Location + terrain (OSM2World primary path)
# ------------------------------------------------------------
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
    read -r -p "Latitude  (default: 29.0119 — Skydive DeLand): " _lat
    _lat=${_lat:-29.0119}
    read -r -p "Longitude (default: -81.2462 — Skydive DeLand): " _lon
    _lon=${_lon:--81.2462}
    read -r -p "Radius in meters (default 400): " _radius
    _radius=${_radius:-400}
    read -r -p "Grid spacing in meters (default 10): " GRID_SPACING
    GRID_SPACING=${GRID_SPACING:-10}
    echo "  Using: $LOCATION_NAME  lat=$_lat  lon=$_lon  radius=${_radius}m  grid=${GRID_SPACING}m"

    mkdir -p terrain cfd_mesh

    python3 - << PYEOF
import math
lat, lon, r = float("$_lat"), float("$_lon"), float("$_radius")
dlat = r / 111320
dlon = r / (111320 * math.cos(math.radians(lat)))
bbox = f"{lat-dlat:.6f},{lon-dlon:.6f},{lat+dlat:.6f},{lon+dlon:.6f}"
with open("/tmp/osm_bbox.txt","w") as f:
    f.write(bbox)
print(f"BBox: {bbox}")
PYEOF
    BBOX=$(cat /tmp/osm_bbox.txt)

    OSM_FILE="terrain/${LOCATION_NAME}.osm"

    run_step "Download OSM data" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'" \
        "curl -s --max-time 60 --retry 3 \
          -o '$OSM_FILE' \
          'https://overpass-api.de/api/interpreter' \
          --data 'data=[out:xml][timeout:30];(node($BBOX);way($BBOX);relation($BBOX););out body;>;out skel qt;'" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'"

    OBJ_FILE="terrain/${LOCATION_NAME}.obj"

    run_step "OSM → OBJ (OSM2World)" \
        "test -s '$OBJ_FILE'" \
        "java -Xmx2g \
          --add-exports java.base/java.lang=ALL-UNNAMED \
          --add-exports java.desktop/sun.awt=ALL-UNNAMED \
          --add-exports java.desktop/sun.java2d=ALL-UNNAMED \
          -jar /tmp/osm2world/OSM2World.jar \
          -i '$OSM_FILE' \
          -o '$OBJ_FILE'" \
        "test -s '$OBJ_FILE'"

    STL_PATH="cfd_mesh/${LOCATION_NAME}.stl"

    run_step "OBJ → STL (trimesh)" \
        "test -s '$STL_PATH'" \
        "python3 - << 'PYEOF'
import trimesh, sys
mesh = trimesh.load('$OBJ_FILE', force='mesh')
print(f'  Vertices: {len(mesh.vertices)}, Faces: {len(mesh.faces)}')
if len(mesh.faces) == 0:
    print('WARNING: Empty mesh. OSM has no 3D data for this area.')
    print('CFD will run on flat terrain (valid for open-field drop zones).')
mesh.export('$STL_PATH')
print(f'STL: $STL_PATH')
PYEOF" \
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

# ------------------------------------------------------------
# 9. CFD pipeline
# ------------------------------------------------------------
mkdir -p game_data godot_project/data godot_project/assets/terrain

CASE_DIR="cases/${LOCATION_NAME}"

run_step "Setup OpenFOAM case" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "bash scripts/setup_openfoam_case.sh '$LOCATION_NAME' && cp '$STL_PATH' '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'"

run_step "0/nut in case (k-epsilon)" \
    "test -s '${CASE_DIR}/0/nut' && grep -q 'nutLowReWallFunction' '${CASE_DIR}/0/nut'" \
    "mkdir -p '${CASE_DIR}/0' && python3 -c \"open('${CASE_DIR}/0/nut','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object nut; }\ndimensions [0 2 -1 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type calculated; value uniform 0; }\n    outlet { type calculated; value uniform 0; }\n    walls { type nutLowReWallFunction; value uniform 0; }\n    ground { type nutLowReWallFunction; value uniform 0; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s '${CASE_DIR}/0/nut' && grep -q 'nutLowReWallFunction' '${CASE_DIR}/0/nut'"

run_step "transportProperties in case (openfoam-2512)" \
    "test -s '${CASE_DIR}/constant/transportProperties' && grep -q 'transportModel' '${CASE_DIR}/constant/transportProperties'" \
    "python3 -c \"open('${CASE_DIR}/constant/transportProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object transportProperties; }\ntransportModel Newtonian;\nnu nu [0 2 -1 0 0 0 0] 1.5e-05;\n')\"" \
    "test -s '${CASE_DIR}/constant/transportProperties' && grep -q 'transportModel' '${CASE_DIR}/constant/transportProperties'"

run_mesh_step "$CASE_DIR"
run_sim_step "$CASE_DIR" simpleFoam

# VTK extraction with DB fallback
extract_wind_field_step

GODOT_DATA="godot_project/data/wind_field.json"
GODOT_STL="godot_project/assets/terrain/${LOCATION_NAME}.stl"
for f in "$GODOT_DATA" "$GODOT_STL"; do
    [[ -f "$f" ]] && cp "$f" "${f}.bak" 2>/dev/null || true
done

run_step "Copy Godot assets" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'" \
    "cp '$WIND_JSON' '$GODOT_DATA' && cp '$STL_PATH' '$GODOT_STL'" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'"

# v84: Convert STL to OBJ, copy to Godot, generate scenes (root nodes without parent attribute)
convert_stl_to_obj_and_copy
generate_terrain_scene
fix_main_scene

run_step "Commit all changes" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null" \
    "git add -A && git diff --staged --quiet || git commit -m 'fix: v84 root node parent fix, raw-string regex, Godot 4.x scene compatibility'" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null"

launch_godot_step
llm_audit_info
echo ""
echo "✅ All fixes applied! (v84)"