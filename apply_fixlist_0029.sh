#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0029.sh – Complete self‑healing CFD‑to‑Godot pipeline
# - Fixed unbound variable in cleanup step.
# - Same as v0028 otherwise.
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Complete Self‑Healing ==="
echo "Working directory: $REPO_ROOT"

# Helper: idempotent step runner
run_step() {
    local step_name="$1"
    local check_cmd="$2"
    local apply_cmd="$3"
    local verify_cmd="$4"

    echo "➤ Step: $step_name"
    if eval "$check_cmd" 2>/dev/null; then
        echo "  ✅ Already done – skipping"
        return 0
    else
        echo "  🔧 Running..."
        if ! eval "$apply_cmd"; then
            echo "  ❌ Step failed: $step_name"
            exit 1
        fi
        if ! eval "$verify_cmd" 2>/dev/null; then
            echo "  ❌ Verification failed after step: $step_name"
            exit 1
        fi
        echo "  ✅ Completed"
    fi
}

# 0. Repository sanity check
if [[ ! -f README.md ]] || [[ ! -d scripts ]]; then
    echo "ERROR: Must be run from the root of the parachute-cfd-game repository."
    exit 1
fi

# 0b. OpenFOAM environment check (manual activation required)
if ! command -v simpleFoam &>/dev/null; then
    echo "ERROR: OpenFOAM environment not active. Please run: ofsrc"
    exit 1
fi
echo "✅ OpenFOAM environment active"

# ----------------------------------------------------------------------
# 1. System packages (idempotent, Fedora specific)
# ----------------------------------------------------------------------
# OpenFOAM COPR repo
run_step "OpenFOAM COPR repo" \
    "dnf repolist | grep -qi openfoam" \
    "sudo dnf copr enable -y openfoam/openfoam" \
    "dnf repolist | grep -qi openfoam"

# ----------------------------------------------------------------------
# ParaView – idempotent block
# ----------------------------------------------------------------------
echo "➤ Step: ParaView (pvpython)"
if command -v pvpython &>/dev/null || find /usr -name pvpython 2>/dev/null | grep -q pvpython; then
    echo "  ✅ Already done – skipping"
else
    echo "  🔧 Installing ParaView and setting up pvpython..."
    cat > /tmp/pvpy_setup.sh << 'EOF'
#!/bin/sh
PVPY=$(find /usr -name pvpython 2>/dev/null | head -1)
if [ -z "$PVPY" ]; then
    echo "ERROR: pvpython not found after install" >&2
    exit 1
fi
sudo ln -sf "$PVPY" /usr/local/bin/pvpython
EOF
    chmod +x /tmp/pvpy_setup.sh
    sudo dnf install -y paraview
    /tmp/pvpy_setup.sh
    rm -f /tmp/pvpy_setup.sh
fi
if ! pvpython --version 2>&1 | grep -qi paraview; then
    echo "❌ Verification failed: pvpython not working"
    exit 1
fi
echo "  ✅ Completed"

# ----------------------------------------------------------------------
# Flatpak setup (idempotent)
# ----------------------------------------------------------------------
run_step "Flatpak setup" \
    "flatpak --version 2>/dev/null && flatpak remotes 2>/dev/null | grep -q flathub" \
    "sudo dnf install -y flatpak && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" \
    "flatpak --version && flatpak remotes | grep -q flathub"

# Godot Flatpak
run_step "Godot (flatpak)" \
    "command -v godot" \
    "flatpak install -y flathub org.godotengine.Godot && sudo ln -sf /var/lib/flatpak/exports/bin/org.godotengine.Godot /usr/local/bin/godot" \
    "godot --version 2>&1 | grep -qE '[0-9]+\.[0-9]+'"

# GDAL development headers
run_step "GDAL devel" \
    "gdal-config --version" \
    "sudo dnf install -y gdal gdal-devel python3-gdal" \
    "gdal-config --version"

# ----------------------------------------------------------------------
# 2. Python packages (vtk, trimesh, pycollada, fast_simplification, etc.)
# ----------------------------------------------------------------------
run_step "Python packages (vtk, trimesh, pycollada, fast_simplification, etc.)" \
    "python3 -c 'import trimesh, vtk, pykml, lxml, osgeo, scipy, matplotlib, collada, fast_simplification' 2>/dev/null" \
    "python3 -m pip install --user --break-system-packages numpy vtk trimesh pykml lxml GDAL scipy matplotlib pycollada fast_simplification" \
    "python3 -c 'import trimesh, vtk, pykml, lxml, osgeo, scipy, matplotlib, collada, fast_simplification; print(\"OK\")'"

# ----------------------------------------------------------------------
# 3. OpenFOAM template files (full set)
# ----------------------------------------------------------------------
mkdir -p cases/template/{0.orig,constant,system}

run_step "Template 0.orig/p" \
    "test -s cases/template/0.orig/p && grep -q 'symmetryPlane' cases/template/0.orig/p" \
    "python3 -c \"import os; os.makedirs('cases/template/0.orig', exist_ok=True); f=open('cases/template/0.orig/p','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object p; }\\ndimensions [0 2 -2 0 0 0 0];\\ninternalField uniform 0;\\nboundaryField\\n{\\n    inlet { type zeroGradient; }\\n    outlet { type fixedValue; value uniform 0; }\\n    walls { type zeroGradient; }\\n    ground { type zeroGradient; }\\n    top { type symmetryPlane; }\\n}\\n'); f.close(); print('wrote p')\"" \
    "test -s cases/template/0.orig/p && grep -q 'symmetryPlane' cases/template/0.orig/p"

run_step "Template 0.orig/U" \
    "test -s cases/template/0.orig/U && grep -q 'symmetryPlane' cases/template/0.orig/U" \
    "python3 -c \"import os; os.makedirs('cases/template/0.orig', exist_ok=True); f=open('cases/template/0.orig/U','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class volVectorField; object U; }\\ndimensions [0 1 -1 0 0 0 0];\\ninternalField uniform (10 0 0);\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform (10 0 0); }\\n    outlet { type inletOutlet; inletValue uniform (10 0 0); value uniform (10 0 0); }\\n    walls { type noSlip; }\\n    ground { type noSlip; }\\n    top { type symmetryPlane; }\\n}\\n'); f.close(); print('wrote U')\"" \
    "test -s cases/template/0.orig/U && grep -q 'symmetryPlane' cases/template/0.orig/U"

run_step "Template 0.orig/k and epsilon" \
    "test -s cases/template/0.orig/k && grep -q 'symmetryPlane' cases/template/0.orig/k && test -s cases/template/0.orig/epsilon" \
    "python3 -c \"import os; os.makedirs('cases/template/0.orig', exist_ok=True); fk=open('cases/template/0.orig/k','w'); fk.write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object k; }\\ndimensions [0 2 -2 0 0 0 0];\\ninternalField uniform 0.1;\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform 0.1; }\\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\\n    walls { type kqRWallFunction; value uniform 0.1; }\\n    ground { type kqRWallFunction; value uniform 0.1; }\\n    top { type symmetryPlane; }\\n}\\n'); fk.close(); fe=open('cases/template/0.orig/epsilon','w'); fe.write('FoamFile\\n{ version 2.0; format ascii; class volScalarField; object epsilon; }\\ndimensions [0 2 -3 0 0 0 0];\\ninternalField uniform 0.1;\\nboundaryField\\n{\\n    inlet { type fixedValue; value uniform 0.1; }\\n    outlet { type inletOutlet; inletValue uniform 0.1; value uniform 0.1; }\\n    walls { type epsilonWallFunction; value uniform 0.1; }\\n    ground { type epsilonWallFunction; value uniform 0.1; }\\n    top { type symmetryPlane; }\\n}\\n'); fe.close(); print('wrote k and epsilon')\"" \
    "test -s cases/template/0.orig/k && grep -q 'symmetryPlane' cases/template/0.orig/k && test -s cases/template/0.orig/epsilon"

run_step "Template blockMeshDict" \
    "test -s cases/template/system/blockMeshDict && grep -q 'symmetryPlane' cases/template/system/blockMeshDict" \
    "python3 -c \"import os; os.makedirs('cases/template/system', exist_ok=True); f=open('cases/template/system/blockMeshDict','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object blockMeshDict; }\\nscale 1;\\nvertices ( (0 0 0) (300 0 0) (300 300 0) (0 300 0) (0 0 200) (300 0 200) (300 300 200) (0 300 200) );\\nblocks ( hex (0 1 2 3 4 5 6 7) (30 30 20) simpleGrading (1 1 1) );\\nedges ();\\nboundary\\n(\\n    inlet { type patch; faces ((0 4 7 3)); }\\n    outlet { type patch; faces ((1 2 6 5)); }\\n    walls { type wall; faces ((0 1 5 4)(3 7 6 2)); }\\n    ground { type wall; faces ((0 3 2 1)); }\\n    top { type symmetryPlane; faces ((4 5 6 7)); }\\n);\\n'); f.close(); print('wrote blockMeshDict')\"" \
    "test -s cases/template/system/blockMeshDict && grep -q 'symmetryPlane' cases/template/system/blockMeshDict"

run_step "Template snappyHexMeshDict" \
    "test -s cases/template/system/snappyHexMeshDict && grep -q 'terrain.stl' cases/template/system/snappyHexMeshDict" \
    "python3 -c \"import os; os.makedirs('cases/template/system', exist_ok=True); f=open('cases/template/system/snappyHexMeshDict','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object snappyHexMeshDict; }\\ncastellatedMesh true;\\nsnap true;\\naddLayers false;\\ngeometry { terrain.stl { type triSurfaceMesh; name terrain; } }\\ncastellatedMeshControls\\n{\\n    maxLocalCells 1000000; maxGlobalCells 2000000; minRefinementCells 10;\\n    nCellsBetweenLevels 3; features ();\\n    refinementSurfaces { terrain { level (2 3); } }\\n    refinementRegions {}\\n    locationInMesh (150 150 100);\\n    allowFreeStandingZoneFaces true;\\n}\\nsnapControls { nSmoothPatch 3; tolerance 2.0; nSolveIter 30; nRelaxIter 5; }\\naddLayersControls { relativeSizes true; layers {} expansionRatio 1.0; finalLayerThickness 0.3; minThickness 0.1; nGrow 0; }\\nmeshQualityControls { maxNonOrtho 65; maxBoundarySkewness 20; maxInternalSkewness 4; maxConcave 80; minFlatness 0.5; minVol 1e-13; minTetQuality 1e-15; minArea -1; minTwist 0.02; minDeterminant 0.001; minFaceWeight 0.02; minVolRatio 0.01; minTriangleTwist -1; nSmoothScale 4; errorReduction 0.75; }\\nwriteFlags (scalarLevels layerSets layerFields);\\nmergeTolerance 1e-6;\\n'); f.close(); print('wrote snappyHexMeshDict')\"" \
    "test -s cases/template/system/snappyHexMeshDict && grep -q 'terrain.stl' cases/template/system/snappyHexMeshDict"

run_step "Template turbulenceProperties" \
    "test -s cases/template/constant/turbulenceProperties && grep -q 'kEpsilon' cases/template/constant/turbulenceProperties" \
    "python3 -c \"import os; os.makedirs('cases/template/constant', exist_ok=True); f=open('cases/template/constant/turbulenceProperties','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object turbulenceProperties; }\\nsimulationType RAS;\\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\\n'); f.close(); print('wrote turbulenceProperties')\"" \
    "test -s cases/template/constant/turbulenceProperties && grep -q 'kEpsilon' cases/template/constant/turbulenceProperties"

run_step "Template surfaceFeatureExtractDict" \
    "test -s cases/template/system/surfaceFeatureExtractDict && grep -q 'extractFromSurface' cases/template/system/surfaceFeatureExtractDict" \
    "python3 -c \"import os; os.makedirs('cases/template/system', exist_ok=True); f=open('cases/template/system/surfaceFeatureExtractDict','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object surfaceFeatureExtractDict; }\\nterrain.stl\\n{\\n    extractionMethod extractFromSurface;\\n    extractFromSurfaceCoeffs { includedAngle 150; }\\n    writeObj yes;\\n}\\n'); f.close(); print('wrote surfaceFeatureExtractDict')\"" \
    "test -s cases/template/system/surfaceFeatureExtractDict && grep -q 'extractFromSurface' cases/template/system/surfaceFeatureExtractDict"

run_step "Template physicalProperties" \
    "test -s cases/template/constant/physicalProperties && grep -q 'nu' cases/template/constant/physicalProperties" \
    "python3 -c \"import os; os.makedirs('cases/template/constant', exist_ok=True); f=open('cases/template/constant/physicalProperties','w'); f.write('FoamFile\\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\\nviscosityModel Newtonian;\\nnu 1.5e-05;\\n'); f.close(); print('wrote physicalProperties')\"" \
    "test -s cases/template/constant/physicalProperties && grep -q 'nu' cases/template/constant/physicalProperties"

# ----------------------------------------------------------------------
# 4. Stub scripts and documentation
# ----------------------------------------------------------------------
run_step "Stub download_terrain_tiles.py" \
    "grep -q 'manually' scripts/download_terrain_tiles.py 2>/dev/null" \
    "python3 -c \"stub='#!/usr/bin/env python3\\nimport sys\\nprint(\\\"ERROR: Automated terrain download not implemented.\\\")\\nprint(\\\"Please export COLLADA manually from Google Earth Pro.\\\")\\nsys.exit(1)\\n'; open('scripts/download_terrain_tiles.py','w').write(stub); import os; os.chmod('scripts/download_terrain_tiles.py',0o755)\"" \
    "grep -q 'manually' scripts/download_terrain_tiles.py"

run_step "Stub place_rotors.py" \
    "grep -q 'not implemented' scripts/place_rotors.py 2>/dev/null" \
    "python3 -c \"stub='#!/usr/bin/env python3\\nimport sys\\nprint(\\\"ERROR: place_rotors.py not implemented.\\\")\\nprint(\\\"Read wind_field.json, place rotor positions at wind speed maxima.\\\")\\nsys.exit(1)\\n'; open('scripts/place_rotors.py','w').write(stub); import os; os.chmod('scripts/place_rotors.py',0o755)\"" \
    "grep -q 'not implemented' scripts/place_rotors.py"

run_step "Documentation stubs" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md" \
    "python3 -c 'import os; os.makedirs(\"docs\", exist_ok=True); for name,body in [(\"cfd_setup.md\",\"# CFD Setup Guide\\n\\nSee QUICKSTART.md for full workflow.\\n\"),(\"godot_integration.md\",\"# Godot Integration\\n\\nSee godot_project/scripts/ for wind_field.gd, parachute_controller.gd, game_manager.gd.\\n\"),(\"locations.md\",\"# Curated Landing Zones\\n\\n- San Francisco Financial District: 37.7946N 122.3999W\\n- Central Park NYC: 40.7829N 73.9654W\\n- Dubai Marina: 25.0808N 55.1376E\\n\")]: path=os.path.join(\"docs\",name); (os.path.exists(path) and os.path.getsize(path)>0) or (open(path,\"w\").write(body) and print(\"wrote\",path))'" \
    "test -s docs/cfd_setup.md && test -s docs/godot_integration.md && test -s docs/locations.md"

# ----------------------------------------------------------------------
# 5. Test collada_to_stl with a cube
# ----------------------------------------------------------------------
run_step "Test collada_to_stl (cube)" \
    "false" \
    "python3 -c 'import trimesh; cube = trimesh.creation.box(extents=[100,100,10]); cube.export(\"test_cube.dae\")' && python3 scripts/collada_to_stl.py --input test_cube.dae --output test_cube.stl --simplify 1.0" \
    "test -s test_cube.stl"

# ----------------------------------------------------------------------
# 6. Clean test artifacts (fixed unbound variable)
# ----------------------------------------------------------------------
run_step "Clean test artifacts" \
    "false" \
    "rm -f test_cube.dae test_cube.stl zones_test.json test.kml && ( ! ls test_cube.dae test_cube.stl zones_test.json test.kml 2>/dev/null | grep -q . )" \
    "for f in test_cube.dae test_cube.stl zones_test.json test.kml; do [ ! -f \"$f\" ] || exit 1; done"

# ----------------------------------------------------------------------
# 7. Set execute bits on all scripts
# ----------------------------------------------------------------------
run_step "Set execute bits" \
    "test -x scripts/setup_openfoam_case.sh" \
    "find scripts/ -name '*.sh' -o -name '*.py' | xargs -r chmod +x" \
    "test -x scripts/setup_openfoam_case.sh && test -x scripts/collada_to_stl.py"

# ----------------------------------------------------------------------
# 8. Create terrain helper script (disabled – manual DAE only)
# ----------------------------------------------------------------------
if [[ ! -f scripts/create_terrain_dae.sh ]]; then
    echo "Creating terrain helper (disabled) – manual DAE export required..."
    cat > scripts/create_terrain_dae.sh << 'EOF'
#!/usr/bin/env bash
echo "ERROR: Automatic terrain download is not available."
echo "Please export a COLLADA (.dae) file manually from Google Earth Pro."
echo "Then run this script again and provide the path to that file."
exit 1
EOF
    chmod +x scripts/create_terrain_dae.sh
fi

# ----------------------------------------------------------------------
# 9. User input
# ----------------------------------------------------------------------
STATE_FILE=".cfd_state"
if [[ -f "$STATE_FILE" ]]; then
    echo "Previous run state found. Loading parameters..."
    source "$STATE_FILE"
    echo "   Location    : $LOCATION_NAME"
    echo "   DAE file    : $DAE_PATH"
    echo "   Grid spacing: $GRID_SPACING m"
    read -r -p "Use these values? (y/n, default y): " use_prev
    use_prev=${use_prev:-y}
    if [[ "$use_prev" =~ ^[Nn]$ ]]; then
        unset LOCATION_NAME DAE_PATH GRID_SPACING
    fi
fi

if [[ -z "${LOCATION_NAME:-}" ]]; then
    read -r -p "Location name (e.g., sf_downtown): " LOCATION_NAME
    while [[ -z "$DAE_PATH" || ! -f "$DAE_PATH" ]]; do
        read -r -p "Path to COLLADA (.dae) file from Google Earth Pro: " DAE_PATH
        if [[ ! -f "$DAE_PATH" ]]; then
            echo "File not found. Please provide a valid path."
        fi
    done
    read -r -p "Mesh refinement grid spacing (meters) [default 10]: " GRID_SPACING
    GRID_SPACING=${GRID_SPACING:-10}
    cat > "$STATE_FILE" << EOF
LOCATION_NAME="$LOCATION_NAME"
DAE_PATH="$DAE_PATH"
GRID_SPACING="$GRID_SPACING"
EOF
    echo "Parameters saved to $STATE_FILE"
fi

if [[ ! -f "$DAE_PATH" ]]; then
    echo "ERROR: COLLADA file not found: $DAE_PATH"
    exit 1
fi

# ----------------------------------------------------------------------
# 10. Create directories
# ----------------------------------------------------------------------
mkdir -p terrain cfd_mesh game_data godot_project/data godot_project/assets/terrain

# ----------------------------------------------------------------------
# 11. Convert COLLADA → STL and run CFD pipeline
# ----------------------------------------------------------------------
STL_FILE="cfd_mesh/${LOCATION_NAME}.stl"
run_step "COLLADA → STL" \
    "test -s '$STL_FILE'" \
    "python scripts/collada_to_stl.py --input '$DAE_PATH' --output '$STL_FILE' --simplify 1.0" \
    "test -s '$STL_FILE'"

ZONES_FILE="cfd_mesh/${LOCATION_NAME}_zones.json"
run_step "Classify geometry" \
    "test -s '$ZONES_FILE'" \
    "python scripts/classify_geometry.py --input '$DAE_PATH' --output '$ZONES_FILE'" \
    "test -s '$ZONES_FILE'"

CASE_DIR="cases/${LOCATION_NAME}"
run_step "Setup OpenFOAM case" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "bash scripts/setup_openfoam_case.sh '$LOCATION_NAME' && cp '$STL_FILE' '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'"

run_step "Generate mesh (snappyHexMesh)" \
    "test -d '$CASE_DIR/constant/polyMesh'" \
    "(cd '$CASE_DIR' && ./Allrun.mesh)" \
    "test -d '$CASE_DIR/constant/polyMesh'"

run_step "Run isothermal simulation" \
    "test -d '$CASE_DIR/1000'" \
    "(cd '$CASE_DIR' && ./Allrun.isothermal)" \
    "test -d '$CASE_DIR/1000'"

WIND_JSON="game_data/${LOCATION_NAME}_wind.json"
run_step "Extract wind field to JSON" \
    "test -s '$WIND_JSON'" \
    "(cd '$CASE_DIR' && foamToVTK && pvpython ../../scripts/extract_wind_vectors.py --case . --grid-spacing '$GRID_SPACING' --output '../../$WIND_JSON')" \
    "test -s '$WIND_JSON'"

GODOT_DATA="godot_project/data/wind_field.json"
GODOT_DAE="godot_project/assets/terrain/${LOCATION_NAME}.dae"
GODOT_STL="godot_project/assets/terrain/${LOCATION_NAME}.stl"

for f in "$GODOT_DATA" "$GODOT_DAE" "$GODOT_STL"; do
    if [[ -f "$f" ]] && ! cmp -s "$f" "${f}.bak" 2>/dev/null; then
        cp "$f" "${f}.bak"
        echo "📁 Backed up $f to ${f}.bak"
    fi
done

run_step "Copy Godot assets" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_DAE'" \
    "cp '$WIND_JSON' '$GODOT_DATA' && cp '$DAE_PATH' '$GODOT_DAE' && cp '$STL_FILE' '$GODOT_STL'" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_DAE'"

# ----------------------------------------------------------------------
# 12. Git commit (if any changes)
# ----------------------------------------------------------------------
run_step "Commit all changes" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null" \
    "git add -A && (git diff --staged --quiet || git commit -m 'fix: apply complete self‑healing pipeline')" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null"

echo ""
echo "✅ All fixes applied successfully!"
echo ""
echo "Next steps (manual, one-time per location):"
echo "  1. Open Godot:      godot godot_project/project.godot"
echo "  2. Open main scene: scenes/main.tscn"
echo "  3. Drag '$GODOT_DAE' into the scene."
echo "  4. Add collision: select terrain node → Add Child → StaticBody3D"
echo "     → CollisionShape3D → set shape to ConcavePolygonShape3D from mesh."
echo "  5. Press F5 to play."
echo ""
echo "Controls: Arrow keys (left/right) to steer, down arrow to brake."
echo ""
echo "To re-run this script (e.g., after changing DAE or grid spacing),"
echo "delete the state file: rm '$STATE_FILE'"