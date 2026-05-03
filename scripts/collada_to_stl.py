#!/usr/bin/env python3
"""
Convert COLLADA (.dae) terrain from Google Earth to STL for OpenFOAM.

WHAT: Loads COLLADA geometry, simplifies mesh, exports to STL binary format
WHY:  OpenFOAM snappyHexMesh requires STL; Google Earth exports COLLADA
MENTAL MODEL BEFORE: COLLADA with textures, complex geometry
MENTAL MODEL AFTER:  Simplified STL triangle mesh ready for CFD meshing
FAILURE MODE: Simplify ratio too high (> 0.9) → loses building details
VERIFIES WITH: Output STL file readable by ParaView, polygon count reduced

Source (Tier 4): trimesh library - mesh simplification using quadric decimation
  https://github.com/mikedh/trimesh/blob/main/trimesh/simplify.py#L20-L85
"""

import argparse
import trimesh
import numpy as np

def collada_to_stl(input_dae, output_stl, simplify_ratio=0.5, z_offset=0.0):
    """
    Convert COLLADA to STL with optional mesh simplification.
    
    Args:
        input_dae: Input COLLADA file path
        output_stl: Output STL file path
        simplify_ratio: Target face count ratio (0.5 = 50% of original faces)
        z_offset: Vertical offset in meters (elevate terrain if needed)
    
    MENTAL MODEL: Load geometry → merge meshes → decimate → save binary STL
    FAILURE MODE: File not found → trimesh raises IOError
    VERIFIES WITH: STL file created, openable in ParaView
    
    Source (Tier 4): trimesh.load() handles COLLADA via pycollada backend
      https://github.com/mikedh/trimesh/blob/main/trimesh/exchange/load.py#L88
    """
    
    print(f"Loading COLLADA: {input_dae}")
    
    # Load COLLADA - trimesh automatically handles .dae format
    # Source: trimesh supports COLLADA 1.4.1 via pycollada
    try:
        mesh = trimesh.load(input_dae, force='mesh')
    except Exception as e:
        print(f"ERROR loading COLLADA: {e}")
        print("Ensure file is valid COLLADA 1.4.1 format from Google Earth")
        return False
    
    # Handle scene vs single mesh
    # MENTAL MODEL: Google Earth exports may contain multiple mesh nodes
    if isinstance(mesh, trimesh.Scene):
        print(f"Scene contains {len(mesh.geometry)} geometries, merging...")
        mesh = trimesh.util.concatenate(
            [geom for geom in mesh.geometry.values() if isinstance(geom, trimesh.Trimesh)]
        )
    
    original_faces = len(mesh.faces)
    print(f"Original mesh: {len(mesh.vertices)} vertices, {original_faces} faces")
    
    # Apply z-offset if specified
    if z_offset != 0.0:
        mesh.vertices[:, 2] += z_offset
        print(f"Applied z-offset: {z_offset}m")
    
    # Simplify mesh using quadric decimation
    # Source (Tier 4): Garland & Heckbert (1997) quadric error metric decimation
    # Implementation: https://github.com/mikedh/trimesh/blob/main/trimesh/simplify.py
    if simplify_ratio < 1.0:
        target_faces = int(original_faces * simplify_ratio)
        print(f"Simplifying to {target_faces} faces (ratio: {simplify_ratio})...")
        
        mesh = mesh.simplify_quadric_decimation(target_faces)
        
        print(f"Simplified mesh: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces")
        print(f"Reduction: {100 * (1 - len(mesh.faces) / original_faces):.1f}%")
    
    # Export to binary STL
    # MENTAL MODEL: Binary STL is compact, widely supported by CAD/CFD tools
    # Source (Tier 2): STL format spec - binary more efficient than ASCII for large meshes
    print(f"Exporting to STL: {output_stl}")
    mesh.export(output_stl, file_type='stl')
    
    print("Conversion complete!")
    print(f"\nNext step: Use in OpenFOAM snappyHexMesh")
    print(f"  surfaceFeatureExtract")
    print(f"  snappyHexMesh -overwrite")
    
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert Google Earth COLLADA to STL for OpenFOAM"
    )
    parser.add_argument("--input", type=str, required=True,
                        help="Input COLLADA (.dae) file")
    parser.add_argument("--output", type=str, required=True,
                        help="Output STL file")
    parser.add_argument("--simplify", type=float, default=0.5,
                        help="Simplification ratio 0-1 (default: 0.5 = 50%% faces)")
    parser.add_argument("--z-offset", type=float, default=0.0,
                        help="Vertical offset in meters (default: 0)")
    
    args = parser.parse_args()
    
    if not args.input.endswith('.dae'):
        print("WARNING: Input should be .dae file from Google Earth")
    if not args.output.endswith('.stl'):
        args.output += '.stl'
    
    if not (0 < args.simplify <= 1.0):
        print("ERROR: Simplify ratio must be between 0 and 1")
        exit(1)
    
    success = collada_to_stl(args.input, args.output, args.simplify, args.z_offset)
    exit(0 if success else 1)