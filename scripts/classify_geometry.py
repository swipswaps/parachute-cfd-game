#!/usr/bin/env python3
"""
Classify terrain geometry into buildings, trees, and ground for CFD setup.

WHAT: Analyzes COLLADA mesh to auto-detect vertical structures (buildings),
      porous zones (trees), and ground surface
WHY:  OpenFOAM requires different boundary conditions and mesh refinement
      for each geometry type
MENTAL MODEL BEFORE: Single unified mesh
MENTAL MODEL AFTER:  Classified zones → buildings (wall BC), trees (porous),
                     ground (thermal BC)
FAILURE MODE: Height threshold wrong → misclassifies buildings as ground
VERIFIES WITH: JSON output with geometry lists, visualize in Blender

Source (Tier 4): Urban CFD best practices - classify obstacles by height
  Franke et al. (2007) COST Action 732 Guidelines section 3.2
  Minimum building height: 3m to be considered obstacle
"""

import argparse
import trimesh
import numpy as np
import json

def classify_geometry(input_dae, output_json, 
                     building_height_min=3.0,
                     tree_height_min=2.0,
                     tree_height_max=30.0):
    """
    Classify mesh components into CFD zones.
    
    Args:
        input_dae: Input COLLADA file
        output_json: Output JSON with classified zones
        building_height_min: Minimum height (m) to classify as building
        tree_height_min: Minimum height (m) for trees
        tree_height_max: Maximum height (m) for trees (taller = building)
    
    MENTAL MODEL: Analyze bounding boxes → height-based classification →
                  export zone lists for OpenFOAM case setup
    FAILURE MODE: No distinct geometry nodes → entire mesh classified as one type
    VERIFIES WITH: JSON contains 3 categories with face/vertex ranges
    
    Source: Urban CFD modeling guidelines specify 3m minimum obstacle height
      for turbulence modeling (COST Action 732, section 3.2.1)
    """
    
    print(f"Loading geometry: {input_dae}")
    
    # Load COLLADA scene
    scene = trimesh.load(input_dae, force='scene')
    
    zones = {
        "buildings": [],
        "trees": [],
        "ground": [],
        "metadata": {
            "building_height_min": building_height_min,
            "tree_height_range": [tree_height_min, tree_height_max],
            "total_geometries": len(scene.geometry)
        }
    }
    
    for name, geometry in scene.geometry.items():
        if not isinstance(geometry, trimesh.Trimesh):
            continue
        
        # Get bounding box
        bounds = geometry.bounds  # [[xmin, ymin, zmin], [xmax, ymax, zmax]]
        height = bounds[1][2] - bounds[0][2]
        
        # Classify based on height
        # MENTAL MODEL: Buildings are tall and solid, trees are medium height,
        #               ground is flat/low
        geometry_info = {
            "name": name,
            "height": float(height),
            "bounds": bounds.tolist(),
            "vertices": len(geometry.vertices),
            "faces": len(geometry.faces),
            "centroid": geometry.centroid.tolist()
        }
        
        if height >= building_height_min and height > tree_height_max:
            # Tall structure → building
            zones["buildings"].append(geometry_info)
            print(f"  BUILDING: {name} (h={height:.1f}m)")
            
        elif tree_height_min <= height <= tree_height_max:
            # Medium height → likely tree canopy
            # NOTE: This is heuristic - may need manual adjustment
            zones["trees"].append(geometry_info)
            print(f"  TREE: {name} (h={height:.1f}m)")
            
        else:
            # Low/flat → ground surface
            zones["ground"].append(geometry_info)
            print(f"  GROUND: {name} (h={height:.1f}m)")
    
    # Write classification
    with open(output_json, 'w') as f:
        json.dump(zones, f, indent=2)
    
    print(f"\nClassification complete:")
    print(f"  Buildings: {len(zones['buildings'])}")
    print(f"  Trees: {len(zones['trees'])}")
    print(f"  Ground: {len(zones['ground'])}")
    print(f"\nOutput: {output_json}")
    print("\nNext step: Review classification, manually adjust if needed")
    print("Then run: ./scripts/setup_openfoam_case.sh <case_name>")
    
    return zones

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Classify terrain geometry for CFD zones"
    )
    parser.add_argument("--input", type=str, required=True,
                        help="Input COLLADA (.dae) file")
    parser.add_argument("--output", type=str, required=True,
                        help="Output JSON file with zones")
    parser.add_argument("--building-height", type=float, default=3.0,
                        help="Minimum building height in meters (default: 3.0)")
    parser.add_argument("--tree-min", type=float, default=2.0,
                        help="Minimum tree height in meters (default: 2.0)")
    parser.add_argument("--tree-max", type=float, default=30.0,
                        help="Maximum tree height in meters (default: 30.0)")
    
    args = parser.parse_args()
    
    classify_geometry(args.input, args.output,
                     args.building_height, args.tree_min, args.tree_max)