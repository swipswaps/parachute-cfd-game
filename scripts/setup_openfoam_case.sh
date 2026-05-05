#!/usr/bin/env bash
# PATH: scripts/setup_openfoam_case.sh
# WHAT: Generates OpenFOAM case directory from terrain STL and zones JSON
# WHY:  Automates CFD setup for each Google Earth location
# MENTAL MODEL BEFORE: Manual blockMesh/snappyHexMesh/boundary setup
# MENTAL MODEL AFTER:  One command generates complete runnable case
# FAILURE MODE: STL or JSON missing → case incomplete
# VERIFIES WITH: Case directory created with all required files
#
# Source (Tier 2): OpenFOAM case structure documented in User Guide section 2.1
#   https://www.openfoam.com/documentation/guides/latest/doc/guide-case-file-structure.html

set -euo pipefail

CASE_NAME="${1:-}"

if [[ -z "$CASE_NAME" ]]; then
    echo "USAGE: $0 <case_name>"
    echo "  Creates cases/<case_name> with OpenFOAM directory structure"
    exit 1
fi

CASE_DIR="cases/$CASE_NAME"
TEMPLATE_DIR="cases/template"

echo "Setting up OpenFOAM case: $CASE_NAME"

# Create case directory
# MENTAL MODEL: OpenFOAM expects 0/, constant/, system/ subdirectories
# Source: OpenFOAM User Guide v10, section 2.1.1
mkdir -p "$CASE_DIR"/{0.orig,constant/triSurface,system}

# Copy boundary conditions
if [[ -d "$TEMPLATE_DIR/0.orig" ]]; then
    cp -r "$TEMPLATE_DIR/0.orig/"* "$CASE_DIR/0.orig/"
fi

# Copy mesh/solver configuration
if [[ -d "$TEMPLATE_DIR/system" ]]; then
    cp "$TEMPLATE_DIR/system/"* "$CASE_DIR/system/"
fi

if [[ -d "$TEMPLATE_DIR/constant" ]]; then
    cp -r "$TEMPLATE_DIR/constant/"* "$CASE_DIR/constant/"
fi

# Copy STL if exists
STL_FILE="cfd_mesh/${CASE_NAME}.stl"
if [[ -f "$STL_FILE" ]]; then
    cp "$STL_FILE" "$CASE_DIR/constant/triSurface/terrain.stl"
    echo "  Copied terrain STL"
else
    echo "  WARNING: STL not found: $STL_FILE"
    echo "  Run: python scripts/collada_to_stl.py first"
fi

# Generate run scripts
cat > "$CASE_DIR/Allrun.mesh" << 'EOFMESH'
#!/bin/sh
# WHAT: Mesh generation script for OpenFOAM case
# WHY:  Automates blockMesh → snappyHexMesh workflow
# VERIFIES WITH: constant/polyMesh/ directory created

cd "${0%/*}" || exit
. "${WM_PROJECT_DIR:?}"/bin/tools/RunFunctions

runApplication blockMesh
runApplication surfaceFeatureExtract
runApplication snappyHexMesh -overwrite
EOFMESH

cat > "$CASE_DIR/Allrun.isothermal" << 'EOFISO'
#!/bin/sh
# WHAT: Run isothermal wind simulation (no thermal effects)
# WHY:  Faster convergence for testing, suitable for neutral stability
# VERIFIES WITH: Case converges in < 1000 iterations

cd "${0%/*}" || exit
. "${WM_PROJECT_DIR:?}"/bin/tools/RunFunctions

# Source (Tier 2): simpleFoam for steady incompressible turbulent flow
# OpenFOAM v10 User Guide, section 7.2.1
# https://www.openfoam.com/documentation/guides/latest/doc/guide-applications-solvers-incompressible-simpleFoam.html

runApplication simpleFoam
EOFISO

cat > "$CASE_DIR/Allrun.thermal" << 'EOFTHERM'
#!/bin/sh
# WHAT: Run thermal buoyancy simulation (solar heating effects)
# WHY:  Captures thermal lift over hot surfaces (parking lots, roofs)
# VERIFIES WITH: Temperature field shows hot/cold zones

cd "${0%/*}" || exit
. "${WM_PROJECT_DIR:?}"/bin/tools/RunFunctions

# Source (Tier 2): buoyantSimpleFoam for buoyancy-driven flows
# OpenFOAM v10 User Guide, section 7.3.2
# https://www.openfoam.com/documentation/guides/latest/doc/guide-applications-solvers-heatTransfer-buoyantSimpleFoam.html

runApplication buoyantSimpleFoam
EOFTHERM

chmod +x "$CASE_DIR"/Allrun.*

echo "Case created: $CASE_DIR"
echo ""
echo "Next steps:"
echo "  cd $CASE_DIR"
echo "  ./Allrun.mesh"
echo "  ./Allrun.isothermal  # or ./Allrun.thermal for buoyancy"