#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0015.sh – Idempotent, self‑healing CFD‑to‑Godot automation
# Fix: disable `set -u` when sourcing OpenFOAM bashrc to avoid unbound variable.
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Full Workflow (Idempotent) ==="
echo "Working directory: $REPO_ROOT"

# ----------------------------------------------------------------------
# Helper: idempotent step runner
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# 0. Repository sanity check
# ----------------------------------------------------------------------
if [[ ! -f README.md ]] || [[ ! -d scripts ]]; then
    echo "ERROR: Must be run from the root of the parachute-cfd-game repository."
    exit 1
fi

# ----------------------------------------------------------------------
# 0b. Auto‑activate OpenFOAM environment if not already active
# ----------------------------------------------------------------------
if ! command -v simpleFoam &>/dev/null; then
    echo "OpenFOAM environment not active – attempting to source it now..."
    # Locate bashrc (same logic as in v12)
    OF_BASHRC=""
    if [[ -f /usr/lib/openfoam/openfoam2512/etc/bashrc ]]; then
        OF_BASHRC="/usr/lib/openfoam/openfoam2512/etc/bashrc"
    elif [[ -f /usr/lib/openfoam/openfoam2412/etc/bashrc ]]; then
        OF_BASHRC="/usr/lib/openfoam/openfoam2412/etc/bashrc"
    else
        OF_BASHRC=$(find /usr/lib/openfoam -name "bashrc" 2>/dev/null | head -1)
    fi

    if [[ -z "$OF_BASHRC" || ! -f "$OF_BASHRC" ]]; then
        echo "ERROR: Cannot locate OpenFOAM bashrc. Please run 'ofsrc' manually."
        exit 1
    fi

    # Temporarily disable `set -u` because OpenFOAM bashrc references unset variables.
    set +u
    # shellcheck source=/dev/null
    source "$OF_BASHRC"
    set -u
    echo "✅ OpenFOAM environment sourced from $OF_BASHRC"
else
    echo "✅ OpenFOAM environment already active"
fi

# ----------------------------------------------------------------------
# 1. User input – cached in .cfd_state to avoid re‑asking
# ----------------------------------------------------------------------
STATE_FILE=".cfd_state"
if [[ -f "$STATE_FILE" ]]; then
    echo "Previous run state found. Loading parameters..."
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    echo "   Location    : $LOCATION_NAME"
    echo "   DAE file    : $DAE_PATH"
    echo "   Grid spacing: $GRID_SPACING m"
    read -r -p "Use these values? (y/n, default y): " use_prev
    use_prev=${use_prev:-y}
    if [[ "$use_prev" =~ ^[Nn]$ ]]; then
        # Force re‑ask
        unset LOCATION_NAME DAE_PATH GRID_SPACING
    fi
fi

if [[ -z "${LOCATION_NAME:-}" ]]; then
    read -r -p "Location name (e.g., sf_downtown): " LOCATION_NAME
    read -r -p "Path to COLLADA (.dae) file from Google Earth: " DAE_PATH
    read -r -p "Mesh refinement grid spacing (meters) [default 10]: " GRID_SPACING
    GRID_SPACING=${GRID_SPACING:-10}
    # Save for next run
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
# 2. Create directories
# ----------------------------------------------------------------------
mkdir -p terrain cfd_mesh game_data godot_project/data godot_project/assets/terrain

# ----------------------------------------------------------------------
# 3. Convert COLLADA → STL (idempotent: check output STL exists)
# ----------------------------------------------------------------------
STL_FILE="cfd_mesh/${LOCATION_NAME}.stl"
run_step "COLLADA → STL" \
    "test -s '$STL_FILE'" \
    "python scripts/collada_to_stl.py --input '$DAE_PATH' --output '$STL_FILE' --simplify 1.0" \
    "test -s '$STL_FILE'"

# ----------------------------------------------------------------------
# 4. Classify geometry (idempotent: output JSON exists)
# ----------------------------------------------------------------------
ZONES_FILE="cfd_mesh/${LOCATION_NAME}_zones.json"
run_step "Classify geometry" \
    "test -s '$ZONES_FILE'" \
    "python scripts/classify_geometry.py --input '$DAE_PATH' --output '$ZONES_FILE'" \
    "test -s '$ZONES_FILE'"

# ----------------------------------------------------------------------
# 5. Setup OpenFOAM case (idempotent: case directory exists and contains terrain.stl)
# ----------------------------------------------------------------------
CASE_DIR="cases/${LOCATION_NAME}"
run_step "Setup OpenFOAM case" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "bash scripts/setup_openfoam_case.sh '$LOCATION_NAME' && cp '$STL_FILE' '$CASE_DIR/constant/triSurface/terrain.stl'" \
    "test -d '$CASE_DIR' && test -f '$CASE_DIR/constant/triSurface/terrain.stl'"

# ----------------------------------------------------------------------
# 6. Generate CFD mesh (idempotent: check constant/polyMesh/ exists)
# ----------------------------------------------------------------------
run_step "Generate mesh (snappyHexMesh)" \
    "test -d '$CASE_DIR/constant/polyMesh'" \
    "(cd '$CASE_DIR' && ./Allrun.mesh)" \
    "test -d '$CASE_DIR/constant/polyMesh'"

# ----------------------------------------------------------------------
# 7. Run isothermal simulation (idempotent: check for final time directory)
#    Assumes endTime=1000 in controlDict
# ----------------------------------------------------------------------
run_step "Run isothermal simulation" \
    "test -d '$CASE_DIR/1000'" \
    "(cd '$CASE_DIR' && ./Allrun.isothermal)" \
    "test -d '$CASE_DIR/1000'"

# ----------------------------------------------------------------------
# 8. Extract wind field to JSON (idempotent: output JSON exists and non‑empty)
# ----------------------------------------------------------------------
WIND_JSON="game_data/${LOCATION_NAME}_wind.json"
run_step "Extract wind field to JSON" \
    "test -s '$WIND_JSON'" \
    "(cd '$CASE_DIR' && foamToVTK && pvpython ../../scripts/extract_wind_vectors.py --case . --grid-spacing '$GRID_SPACING' --output '../../$WIND_JSON')" \
    "test -s '$WIND_JSON'"

# ----------------------------------------------------------------------
# 9. Copy assets to Godot project (idempotent with backup)
# ----------------------------------------------------------------------
GODOT_DATA="godot_project/data/wind_field.json"
GODOT_DAE="godot_project/assets/terrain/${LOCATION_NAME}.dae"
GODOT_STL="godot_project/assets/terrain/${LOCATION_NAME}.stl"

# Backup existing files if they differ (simple existence check)
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
# 10. Final instructions
# ----------------------------------------------------------------------
echo ""
echo "✅ Workflow completed successfully!"
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