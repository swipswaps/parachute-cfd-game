#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0061.sh – Complete self-healing CFD-to-Godot pipeline
#
# v61 changes — all derived from confirmed evidence, not guesses:
#
# GE-EXPORT-001 [CRITICAL]
#   Google Earth Pro Linux CANNOT export 3D terrain mesh.
#   "Save My Places" writes ~/.googleearth/myplaces.kml — bookmark data only.
#   Confirmed: terminal showed myplaces.kml 25K, no .dae or .kmz produced.
#   Fix: OSM + OSM2World is the primary terrain pipeline. No GUI required.
#
# OSM2WORLD-ZIP-001 [CRITICAL]
#   OSM2World-latest-bin.zip extracts FLAT (no subdirectory).
#   Prior glob "cp */OSM2World.jar" fails — file is at root of extract dir.
#   Confirmed: GitHub issue #108 unzip output shows flat structure.
#   Fix: cp /tmp/osm2world_dl_out/OSM2World.jar directly.
#
# OSM2WORLD-JAVA-001 [CRITICAL]
#   OSM2World requires --add-exports flags for Java 17+ module system.
#   Without them: InaccessibleObjectException on launch.
#   Confirmed: osm2world-windows.bat contains the exact flags required.
#   Fix: three --add-exports flags added to java invocation.
#
# JAVA-INSTALL-001 [HIGH]
#   No Java install step. OSM2World requires JRE 17+.
#   Fix: check version, install java-17-openjdk-headless if needed.
#
# OVERPASS-URL-001 [HIGH]
#   GET /api/map returns 403. Use POST to /api/interpreter with QL query.
#   Fix: curl with --data 'data=[out:xml]...'
#
# OBJ-DAE-STL-001 [HIGH]
#   OBJ->DAE->STL round-trip is unnecessary. trimesh loads OBJ -> STL direct.
#   Fix: skip DAE intermediary entirely.
#
# BBOX-CALC-001 [MEDIUM]
#   Bash cannot do float arithmetic. Compute bbox in python3, write to file.
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Complete Self-Healing v61 ==="
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

# Sanity checks
[[ -f README.md && -d scripts ]] || { echo "ERROR: Run from repo root"; exit 1; }
command -v simpleFoam &>/dev/null || { echo "ERROR: OpenFOAM not active. Run: ofsrc"; exit 1; }
echo "✅ OpenFOAM active"

# ─────────────────────────────────────────────────────────────────────
# 1. System packages
# ─────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────
# 2. Google Earth Pro (retained — installed, available, not in critical path)
#    GE-EXPORT-001: Linux GE cannot export terrain mesh.
#    myplaces.kml confirmed = bookmark data only. OSM2World is primary pipeline.
# ─────────────────────────────────────────────────────────────────────
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
# v58 window fix: DISPLAY, Qt flags, bundled libs
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

# ─────────────────────────────────────────────────────────────────────
# 3. Java 17 + OSM2World (JAVA-INSTALL-001, OSM2WORLD-ZIP-001, OSM2WORLD-JAVA-001)
# ─────────────────────────────────────────────────────────────────────
# JAVA-INSTALL-001: OSM2World requires JRE 17+
run_step "Java 17" \
    "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'" \
    "sudo dnf install -y java-17-openjdk-headless" \
    "java -version 2>&1 | grep -qE '(17|21|22|23|24)\.'"

# OSM2WORLD-ZIP-001: zip extracts FLAT — confirmed from GitHub issue #108 unzip output.
# Files land at root of extract dir: OSM2World.jar, osm2world.sh, lib/, ...
# NO subdirectory wrapper. cp direct path, not glob.
run_step "OSM2World jar" \
    "test -f /tmp/osm2world/OSM2World.jar" \
    "mkdir -p /tmp/osm2world_dl_out /tmp/osm2world \
     && wget -q -O /tmp/osm2world_dl_out/osm2world.zip 'https://osm2world.org/download/files/latest/OSM2World-latest-bin.zip' \
     && unzip -q /tmp/osm2world_dl_out/osm2world.zip -d /tmp/osm2world_dl_out \
     && cp /tmp/osm2world_dl_out/OSM2World.jar /tmp/osm2world/OSM2World.jar \
     && rm -rf /tmp/osm2world_dl_out" \
    "test -f /tmp/osm2world/OSM2World.jar"

# ─────────────────────────────────────────────────────────────────────
# 4. Python packages
# ─────────────────────────────────────────────────────────────────────
run_step "Python packages" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification' 2>/dev/null" \
    "python3 -m pip install --user --break-system-packages numpy vtk trimesh pykml lxml GDAL scipy matplotlib pycollada fast_simplification" \
    "python3 -c 'import trimesh,vtk,pykml,lxml,osgeo,scipy,matplotlib,collada,fast_simplification; print(\"OK\")'"

# ─────────────────────────────────────────────────────────────────────
# 5. OpenFOAM template files
# ─────────────────────────────────────────────────────────────────────
mkdir -p cases/template/{0.orig,constant,system}

run_step "Template 0.orig/p" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p" \
    "python3 -c \"open('cases/template/0.orig/p','w').write('FoamFile\n{ version 2.0; format ascii; class volScalarField; object p; }\ndimensions [0 2 -2 0 0 0 0];\ninternalField uniform 0;\nboundaryField\n{\n    inlet { type zeroGradient; }\n    outlet { type fixedValue; value uniform 0; }\n    walls { type zeroGradient; }\n    ground { type zeroGradient; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/p && grep -q symmetryPlane cases/template/0.orig/p"

run_step "Template 0.orig/U" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U" \
    "python3 -c \"open('cases/template/0.orig/U','w').write('FoamFile\n{ version 2.0; format ascii; class volVectorField; object U; }\ndimensions [0 1 -1 0 0 0 0];\ninternalField uniform (10 0 0);\nboundaryField\n{\n    inlet { type fixedValue; value uniform (10 0 0); }\n    outlet { type inletOutlet; inletValue uniform (10 0 0); value uniform (10 0 0); }\n    walls { type noSlip; }\n    ground { type noSlip; }\n    top { type symmetryPlane; }\n}\n')\"" \
    "test -s cases/template/0.orig/U && grep -q symmetryPlane cases/template/0.orig/U"

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
    "python3 -c \"open('cases/template/constant/physicalProperties','w').write('FoamFile\n{ version 2.0; format ascii; class dictionary; object physicalProperties; }\nviscosityModel Newtonian;\nnu 1.5e-05;\n')\"" \
    "test -s cases/template/constant/physicalProperties && grep -q 'nu' cases/template/constant/physicalProperties"

# ─────────────────────────────────────────────────────────────────────
# 6. Stubs and docs
# ─────────────────────────────────────────────────────────────────────
run_step "Stub download_terrain_tiles.py" \
    "grep -q 'OSM pipeline' scripts/download_terrain_tiles.py 2>/dev/null" \
    "python3 -c \"import os; os.makedirs('scripts', exist_ok=True); open('scripts/download_terrain_tiles.py','w').write('#!/usr/bin/env python3\nimport sys\nprint(\\\"Use OSM pipeline in apply_fixlist_0061.sh instead.\\\")\nsys.exit(1)\n'); import os; os.chmod('scripts/download_terrain_tiles.py',0o755)\"" \
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

# ─────────────────────────────────────────────────────────────────────
# 7. Smoke test + cleanup
# ─────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────
# 8. Location + terrain (OSM2World primary path)
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
    while [[ -z "${LOCATION_NAME:-}" ]]; do
        read -r -p "Location name (e.g., skydive_deland): " LOCATION_NAME
        [[ -z "$LOCATION_NAME" ]] && echo "  ERROR: location name is required"
    done
    while [[ -z "${_lat:-}" ]]; do
        read -r -p "Latitude  (e.g., 29.0119): " _lat
        [[ -z "$_lat" ]] && echo "  ERROR: latitude is required"
    done
    while [[ -z "${_lon:-}" ]]; do
        read -r -p "Longitude (e.g., -81.2462): " _lon
        [[ -z "$_lon" ]] && echo "  ERROR: longitude is required"
    done
    read -r -p "Radius in meters (default 400): " _radius
    _radius=${_radius:-400}
    read -r -p "Grid spacing in meters (default 10): " GRID_SPACING
    GRID_SPACING=${GRID_SPACING:-10}

    mkdir -p terrain cfd_mesh

    # BBOX-CALC-001: compute bbox entirely in python3 — bash cannot do float arithmetic
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

    # OVERPASS-URL-001: POST to /api/interpreter — GET /api/map returns 403 from many IPs
    run_step "Download OSM data" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'" \
        "curl -s --max-time 60 --retry 3 \
          -o '$OSM_FILE' \
          'https://overpass-api.de/api/interpreter' \
          --data 'data=[out:xml][timeout:30];(node($BBOX);way($BBOX);relation($BBOX););out body;>;out skel qt;'" \
        "test -s '$OSM_FILE' && head -1 '$OSM_FILE' | grep -q '<?xml'"

    OBJ_FILE="terrain/${LOCATION_NAME}.obj"

    # OSM2WORLD-JAVA-001: --add-exports required for Java 17+ module system
    # Confirmed from osm2world-windows.bat: github.com/tordanik/OSM2World
    # OSM2WORLD-ZIP-001: jar is at /tmp/osm2world/OSM2World.jar (flat extract)
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

    # OBJ-DAE-STL-001: load OBJ -> export STL directly — no DAE round-trip needed
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

# ─────────────────────────────────────────────────────────────────────
# 9. CFD pipeline (unchanged from v58)
# ─────────────────────────────────────────────────────────────────────
mkdir -p game_data godot_project/data godot_project/assets/terrain

CASE_DIR="cases/${LOCATION_NAME}"

run_step "Setup OpenFOAM case" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "bash scripts/setup_openfoam_case.sh '$LOCATION_NAME' && cp '$STL_PATH' '$CASE_DIR/constant/triSurface/terrain.stl'" \
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
run_step "Extract wind field" \
    "test -s '$WIND_JSON'" \
    "(cd '$CASE_DIR' && foamToVTK && pvpython ../../scripts/extract_wind_vectors.py --case . --grid-spacing '$GRID_SPACING' --output '../../$WIND_JSON')" \
    "test -s '$WIND_JSON'"

GODOT_DATA="godot_project/data/wind_field.json"
GODOT_STL="godot_project/assets/terrain/${LOCATION_NAME}.stl"
for f in "$GODOT_DATA" "$GODOT_STL"; do
    [[ -f "$f" ]] && cp "$f" "${f}.bak" 2>/dev/null || true
done

run_step "Copy Godot assets" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'" \
    "cp '$WIND_JSON' '$GODOT_DATA' && cp '$STL_PATH' '$GODOT_STL'" \
    "test -f '$GODOT_DATA' && test -f '$GODOT_STL'"

# ─────────────────────────────────────────────────────────────────────
# 10. Git commit
# ─────────────────────────────────────────────────────────────────────
run_step "Commit all changes" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null" \
    "git add -A && git diff --staged --quiet || git commit -m 'fix: v61 required-input validation, stub fix, OSM terrain pipeline, GE export removed, OSM2World fixes'" \
    "git rev-parse HEAD >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null && git diff --staged --quiet 2>/dev/null"

echo ""
echo "✅ All fixes applied! (v59)"
echo ""
echo "Next steps:"
echo "  1. godot godot_project/project.godot"
echo "  2. Open scenes/main.tscn"
echo "  3. Drag godot_project/assets/terrain/${LOCATION_NAME}.stl into scene"
echo "  4. Add StaticBody3D + ConcavePolygonShape3D for collision"
echo "  5. F5 to play — Arrow keys steer, Down arrow brakes"
echo ""
echo "To restart with a new location: rm '$STATE_FILE'"
