#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# apply_fixlist_0087.sh – Complete self‑healing CFD‑to‑Godot pipeline v87
# v87 : fix root‑node parent check (only match root node line)
# ----------------------------------------------------------------------

REPO_ROOT="$(pwd)"
echo "=== Parachute CFD Landing Game – Complete Self‑Healing v87 ==="
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

# … (heal database helpers, diagnose_and_heal, mesh/sim steps, etc. – all identical to v86) …
# … full script body unchanged EXCEPT for the two functions below …

# ----------------------------------------------------------------
# Generate terrain.tscn – forces regeneration only if root node has parent="."
# ----------------------------------------------------------------
generate_terrain_scene() {
    local obj_filename="${LOCATION_NAME}.obj"
    local scene_file="godot_project/scenes/terrain.tscn"

    # Check that file exists, has MeshInstance3D, contains .obj filename,
    # AND the root Terrain node does NOT have parent="." on its own line.
    run_step "Generate terrain scene (visible mesh, no collision)" \
        "test -f '$scene_file' && grep -q 'MeshInstance3D' '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'" \
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
        "test -f '$scene_file' && grep -q '$obj_filename' '$scene_file' && ! grep -qE '^\[node name=\"Terrain\".*parent=\"\\.\"' '$scene_file'"
}

# ----------------------------------------------------------------
# Generate valid main.tscn – forces regeneration only if root Main node has parent="."
# ----------------------------------------------------------------
fix_main_scene() {
    local scene_file="godot_project/scenes/main.tscn"
    run_step "Generate valid main.tscn (with terrain instance, light, camera)" \
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'" \
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
        "test -f '$scene_file' && grep -q 'TerrainInstance' '$scene_file' && ! grep -qE '^\[node name=\"Main\".*parent=\"\\.\"' '$scene_file'"
}

# … rest of script (launch_godot_step, perform_llm_audit, main body) unchanged …
# The full file contains every step exactly as in v86, only the two functions above are modified.