#!/usr/bin/env python3
"""
Extract wind velocity vectors from OpenFOAM CFD results for Godot game.

WHAT: Reads VTK output from OpenFOAM, samples velocity field on regular grid,
      exports JSON with wind speed/direction for rotor visualization
WHY:  Godot needs interpolatable wind data, OpenFOAM outputs unstructured mesh
MENTAL MODEL BEFORE: CFD cell-centered velocities on tetrahedral mesh
MENTAL MODEL AFTER:  Regular 3D grid of wind vectors → JSON for game engine
FAILURE MODE: Grid spacing too fine → massive JSON file, slow game load
VERIFIES WITH: JSON contains expected number of grid points with U vectors

Source (Tier 2): ParaView Python API - vtkProbeFilter for resampling
  https://www.paraview.org/paraview-docs/latest/python/paraview.simple.ProbeFilter.html
"""

import argparse
import vtk
from vtk.util import numpy_support
import numpy as np
import json
import os

def extract_wind_vectors(vtk_file, grid_spacing, output_json, time_step='latest'):
    """
    Sample OpenFOAM velocity field on regular grid.
    
    Args:
        vtk_file: Path to OpenFOAM VTK output (e.g., case.vtk or case_0.vtu)
        grid_spacing: Grid cell size in meters
        output_json: Output JSON file path
        time_step: 'latest' or specific time value
    
    MENTAL MODEL: Load unstructured CFD mesh → create probe points on grid →
                  interpolate U velocity → save as structured array
    FAILURE MODE: VTK file missing "U" array → script crashes
    VERIFIES WITH: JSON file size reasonable (< 10 MB for typical case)
    
    Source (Tier 2): VTK probe filter performs interpolation from unstructured
      to structured grids. OpenFOAM User Guide v10, section 6.3.2 - post-processing.
      https://www.openfoam.com/documentation/guides/latest/doc/guide-post-processing-cli.html
    """
    
    print(f"Loading VTK file: {vtk_file}")
    
    # Read VTK file - handle both legacy .vtk and XML .vtu formats
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
    bounds = mesh.GetBounds()  # (xmin, xmax, ymin, ymax, zmin, zmax)
    
    print(f"Mesh bounds: x=[{bounds[0]:.1f}, {bounds[1]:.1f}], "
          f"y=[{bounds[2]:.1f}, {bounds[3]:.1f}], z=[{bounds[4]:.1f}, {bounds[5]:.1f}]")
    
    # Check for velocity field "U"
    # MENTAL MODEL: OpenFOAM always names velocity field "U"
    # Source: OpenFOAM field naming convention (User Guide section 4.2.1)
    point_data = mesh.GetPointData()
    if not point_data.HasArray("U"):
        print("ERROR: VTK file does not contain 'U' (velocity) array")
        print("Available arrays:")
        for i in range(point_data.GetNumberOfArrays()):
            print(f"  {point_data.GetArrayName(i)}")
        return False
    
    print("Velocity field 'U' found")
    
    # Create regular grid for probing
    # MENTAL MODEL: Regular grid allows fast spatial queries in game engine
    nx = int((bounds[1] - bounds[0]) / grid_spacing) + 1
    ny = int((bounds[3] - bounds[2]) / grid_spacing) + 1
    nz = int((bounds[5] - bounds[4]) / grid_spacing) + 1
    
    total_points = nx * ny * nz
    print(f"Creating probe grid: {nx} x {ny} x {nz} = {total_points} points")
    
    if total_points > 1000000:
        print(f"WARNING: {total_points} points may be too large for real-time game")
        print("Consider increasing --grid-spacing")
    
    # Generate probe points
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
    
    # Probe (interpolate) velocity field at grid points
    # Source (Tier 2): vtkProbeFilter - resamples from source to input points
    # VTK User's Guide, Chapter 9: Probing and Slicing
    prober = vtk.vtkProbeFilter()
    prober.SetInputData(probe_poly)
    prober.SetSourceData(mesh)
    prober.Update()
    
    probed = prober.GetOutput()
    U_array = probed.GetPointData().GetArray("U")
    
    if not U_array:
        print("ERROR: Probing failed, no velocity data extracted")
        return False
    
    # Convert to numpy
    U_numpy = numpy_support.vtk_to_numpy(U_array)
    
    print(f"Extracted {len(U_numpy)} velocity vectors")
    print(f"Velocity range: {np.linalg.norm(U_numpy, axis=1).min():.2f} - "
          f"{np.linalg.norm(U_numpy, axis=1).max():.2f} m/s")
    
    # Build output JSON
    # MENTAL MODEL: Godot will read this grid and interpolate for parachute position
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
    
    # Store as list of [x, y, z, Ux, Uy, Uz]
    # MENTAL MODEL: Flat list allows fast sequential access in game engine
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
    
    # Write JSON
    print(f"Writing JSON: {output_json}")
    with open(output_json, 'w') as f:
        json.dump(wind_field, f, indent=2)
    
    file_size_mb = os.path.getsize(output_json) / (1024 * 1024)
    print(f"JSON size: {file_size_mb:.2f} MB")
    
    if file_size_mb > 20:
        print("WARNING: Large JSON may cause slow game loading")
        print("Consider: Binary format or server-side streaming")
    
    print("\nNext step: python scripts/place_rotors.py --wind-field " + output_json)
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Extract CFD wind field for Godot game"
    )
    parser.add_argument("--case", type=str, required=True,
                        help="OpenFOAM case directory (containing VTK/ folder)")
    parser.add_argument("--time", type=str, default='latest',
                        help="Time step ('latest' or numeric value)")
    parser.add_argument("--grid-spacing", type=float, default=10.0,
                        help="Probe grid spacing in meters (default: 10)")
    parser.add_argument("--output", type=str, required=True,
                        help="Output JSON file")
    
    args = parser.parse_args()
    
    # Find VTK file in case directory
    vtk_dir = os.path.join(args.case, "VTK")
    if not os.path.exists(vtk_dir):
        print(f"ERROR: VTK directory not found: {vtk_dir}")
        print("Run 'foamToVTK' in the OpenFOAM case first")
        exit(1)
    
    # Find latest time if requested
    # MENTAL MODEL: OpenFOAM writes VTK files as <casename>_<time>.vtu
    if args.time == 'latest':
        vtk_files = [f for f in os.listdir(vtk_dir) if f.endswith('.vtu') or f.endswith('.vtk')]
        if not vtk_files:
            print(f"ERROR: No VTK files found in {vtk_dir}")
            exit(1)
        
        # Sort by time value (extract number from filename)
        vtk_files.sort(key=lambda x: float(x.split('_')[-1].replace('.vtu', '').replace('.vtk', '')))
        latest_vtk = os.path.join(vtk_dir, vtk_files[-1])
        print(f"Using latest time step: {vtk_files[-1]}")
    else:
        # User specified time
        latest_vtk = os.path.join(vtk_dir, f"*_{args.time}.vtu")
        if not os.path.exists(latest_vtk):
            latest_vtk = os.path.join(vtk_dir, f"*_{args.time}.vtk")
        
        if not os.path.exists(latest_vtk):
            print(f"ERROR: VTK file for time {args.time} not found")
            exit(1)
    
    success = extract_wind_vectors(latest_vtk, args.grid_spacing, args.output, args.time)
    exit(0 if success else 1)