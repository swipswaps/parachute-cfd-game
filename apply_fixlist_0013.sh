#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0013.sh – Guided CFD-to-Godot automation
# Principle: "If it can be typed, it MUST be scripted!"
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Full Workflow ==="
echo "Working directory: $REPO_ROOT"

# ----------------------------------------------------------------------
# 0. Prerequisites check
# ----------------------------------------------------------------------
if [[ ! -f README.md ]] || [[ ! -d scripts ]]; then
    echo "ERROR: Must be run from the root of the parachute-cfd-game repository."
    exit 1
fi

# Check that OpenFOAM environment is available
if ! command -v simpleFoam &>/dev/null; then
    echo "OpenFOAM environment not active. Please run:  ofsrc"
    echo "If the alias is not defined, source your OpenFOAM bashrc manually."
    exit 1
fi
echo "✅ OpenFOAM environment OK"

# ----------------------------------------------------------------------
# 1. Ask for user input
# ----------------------------------------------------------------------
read -r -p "Location name (e.g., sf_downtown): " LOCATION_NAME
read -r -p "Path to COLLADA (.dae) file from Google Earth: " DAE_PATH

if [[ ! -f "$DAE_PATH" ]]; then
    echo "ERROR: File not found: $DAE_PATH"
    exit 1
fi

# Optional parameters
read -r -p "Mesh refinement grid spacing (meters) [default 10]: " GRID_SPACING
GRID_SPACING=${GRID_SPACING:-10}

# ----------------------------------------------------------------------
# 2. Create working directories
# ----------------------------------------------------------------------
mkdir -p terrain cfd_mesh game_data godot_project/data godot_project/assets/terrain

# ----------------------------------------------------------------------
# 3. Convert COLLADA to STL (no simplification)
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 1: Converting COLLADA to STL (keeping all faces)..."
python scripts/collada_to_stl.py \
    --input "$DAE_PATH" \
    --output "cfd_mesh/${LOCATION_NAME}.stl" \
    --simplify 1.0

# ----------------------------------------------------------------------
# 4. Classify geometry
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 2: Classifying buildings, trees, ground..."
python scripts/classify_geometry.py \
    --input "$DAE_PATH" \
    --output "cfd_mesh/${LOCATION_NAME}_zones.json"

# ----------------------------------------------------------------------
# 5. Setup OpenFOAM case
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 3: Creating OpenFOAM case..."
bash scripts/setup_openfoam_case.sh "$LOCATION_NAME"

CASE_DIR="cases/${LOCATION_NAME}"
if [[ ! -d "$CASE_DIR" ]]; then
    echo "ERROR: OpenFOAM case directory was not created."
    exit 1
fi

# Link the STL file into the case
cp "cfd_mesh/${LOCATION_NAME}.stl" "$CASE_DIR/constant/triSurface/terrain.stl"

# ----------------------------------------------------------------------
# 6. Generate mesh (snappyHexMesh)
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 4: Generating CFD mesh (this may take several minutes)..."
cd "$CASE_DIR"
if ! ./Allrun.mesh; then
    echo "ERROR: Mesh generation failed. Check your STL for watertightness."
    echo "You can try fixing the STL in ParaView (Filters → Clean to Grid)."
    exit 1
fi

# ----------------------------------------------------------------------
# 7. Run isothermal wind simulation
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 5: Running isothermal wind simulation..."
echo "This can take 10-30 minutes. Monitor convergence with:"
echo "  foamMonitor -l postProcessing/residuals/0/residuals.dat"
if ! ./Allrun.isothermal; then
    echo "ERROR: Simulation did not converge. Check residuals and boundary conditions."
    exit 1
fi

# ----------------------------------------------------------------------
# 8. Export wind field for Godot
# ----------------------------------------------------------------------
echo ""
echo "➤ Step 6: Extracting wind field to JSON..."
foamToVTK
pvpython ../../scripts/extract_wind_vectors.py \
    --case . \
    --grid-spacing "$GRID_SPACING" \
    --output "../../game_data/${LOCATION_NAME}_wind.json"

# ----------------------------------------------------------------------
# 9. Copy files to Godot project
# ----------------------------------------------------------------------
cd ../..
echo ""
echo "➤ Step 7: Preparing Godot assets..."
cp "game_data/${LOCATION_NAME}_wind.json" "godot_project/data/wind_field.json"
cp "terrain/${LOCATION_NAME}.dae" "godot_project/assets/terrain/"
# Also copy the STL (optional, for reference)
cp "cfd_mesh/${LOCATION_NAME}.stl" "godot_project/assets/terrain/"

# ----------------------------------------------------------------------
# 10. Launch Godot (or instruct)
# ----------------------------------------------------------------------
echo ""
echo "✅ Workflow completed successfully!"
echo ""
echo "Next steps (manual, one-time per location):"
echo "  1. Open Godot project:  godot godot_project/project.godot"
echo "  2. Open the main scene: scenes/main.tscn"
echo "  3. Drag 'assets/terrain/${LOCATION_NAME}.dae' into the scene."
echo "  4. Add collision: select terrain node → Add Child → StaticBody3D → CollisionShape3D →"
echo "     set shape to ConcavePolygonShape3D using the mesh."
echo "  5. Press F5 to play."
echo ""
echo "Controls: Arrow keys (left/right) to steer, down arrow to brake."
echo ""
echo "To reuse this location later, simply run this script again – it will skip already completed steps."

# Optionally open Godot automatically
read -r -p "Launch Godot now? (y/n) " launch_godot
if [[ "$launch_godot" =~ ^[Yy]$ ]]; then
    godot godot_project/project.godot
fi