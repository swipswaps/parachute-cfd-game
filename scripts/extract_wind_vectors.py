#!/usr/bin/env python3
# PATH: scripts/extract_wind_vectors.py
# VTK-SUBDIR-001: uses os.walk to find internal.vtu in subdirectories
# foamToVTK creates VTK/casename_N/internal.vtu — not flat files in VTK/
import argparse, vtk, json, os, sys
from vtk.util import numpy_support

def find_latest_vtu(vtk_dir):
    """Walk VTK/ subdirectories to find the latest internal.vtu"""
    vtu_files = []
    for root, dirs, files in os.walk(vtk_dir):
        for f in files:
            if f == 'internal.vtu':
                vtu_files.append(os.path.join(root, f))
    if not vtu_files:
        return None
    # Sort by path — latest time dir sorts last numerically
    vtu_files.sort()
    return vtu_files[-1]

def extract(vtk_file, grid_spacing, output_json):
    print(f"Loading VTK: {vtk_file}")
    reader = vtk.vtkXMLUnstructuredGridReader()
    reader.SetFileName(vtk_file)
    reader.Update()
    mesh = reader.GetOutput()
    bounds = mesh.GetBounds()
    print(f"Bounds: x=[{bounds[0]:.1f},{bounds[1]:.1f}] y=[{bounds[2]:.1f},{bounds[3]:.1f}] z=[{bounds[4]:.1f},{bounds[5]:.1f}]")
    if not mesh.GetPointData().HasArray("U"):
        print("ERROR: No U velocity array in mesh"); return False
    nx = int((bounds[1]-bounds[0])/grid_spacing)+1
    ny = int((bounds[3]-bounds[2])/grid_spacing)+1
    nz = int((bounds[5]-bounds[4])/grid_spacing)+1
    print(f"Grid: {nx}x{ny}x{nz} = {nx*ny*nz} points")
    pts = vtk.vtkPoints()
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                pts.InsertNextPoint(bounds[0]+i*grid_spacing, bounds[2]+j*grid_spacing, bounds[4]+k*grid_spacing)
    poly = vtk.vtkPolyData(); poly.SetPoints(pts)
    prober = vtk.vtkProbeFilter()
    prober.SetInputData(poly); prober.SetSourceData(mesh); prober.Update()
    U_arr = prober.GetOutput().GetPointData().GetArray("U")
    if not U_arr: print("ERROR: Probing failed"); return False
    U = numpy_support.vtk_to_numpy(U_arr)
    wind = {"metadata": {"grid_spacing": grid_spacing, "dimensions": [nx,ny,nz],
            "bounds": {"x": list(bounds[0:2]), "y": list(bounds[2:4]), "z": list(bounds[4:6])}},
            "velocities": []}
    idx = 0
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                x,y,z = bounds[0]+i*grid_spacing, bounds[2]+j*grid_spacing, bounds[4]+k*grid_spacing
                wind["velocities"].append({"pos":[float(x),float(y),float(z)], "vel":[float(U[idx][0]),float(U[idx][1]),float(U[idx][2])]})
                idx += 1
    with open(output_json, 'w') as f: json.dump(wind, f)
    print(f"Written: {output_json} ({os.path.getsize(output_json)//1024} KB)")
    return True

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--case", required=True)
    p.add_argument("--grid-spacing", type=float, default=10.0)
    p.add_argument("--output", required=True)
    p.add_argument("--vtk-file", default=None)
    args = p.parse_args()
    if args.vtk_file:
        vtk_file = args.vtk_file
    else:
        vtk_dir = os.path.join(args.case, "VTK")
        if not os.path.exists(vtk_dir):
            print(f"ERROR: VTK directory not found: {vtk_dir}"); sys.exit(1)
        vtk_file = find_latest_vtu(vtk_dir)
        if not vtk_file:
            print(f"ERROR: No internal.vtu found in {vtk_dir}"); sys.exit(1)
    sys.exit(0 if extract(vtk_file, args.grid_spacing, args.output) else 1)
