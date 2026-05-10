# Skydive University – Canopy Flight Trainer

## Quick Start
- **Godot binary:** `./bin/Godot_v4.6.2-stable_linux.x86_64`
- **Launch:** `./bin/Godot_v4.6.2-stable_linux.x86_64 --path "$(pwd)/godot_project" --rendering-driver opengl3`
- **Import:** `./bin/Godot_v4.6.2-stable_linux.x86_64 --headless --import --project-path "$(pwd)/godot_project" --quit`
- **Working script:** `apply_fixlist_0305.sh` (latest stable)

## Critical Constraints
1. **Use `--path` not `--project-path`** to launch – `--project-path` opens Project Manager.
2. **llvmpipe driver** clears viewport to black after first frame. Game window shows black. This is **normal and unfixable**.
3. **Capture screenshots internally** in GDScript (frame 2), not externally via xdotool.
4. **Godot 4.6.2 binary CANNOT import FBX or glTF** – must convert to OBJ first.
5. **Blender OBJ export** needs `select_all(action='SELECT')` before export, no `use_selection=True`.
6. **Camera top-down transform:** `Transform3D(1,0,0, 0,0,1, 0,-1,0, 0,CAM_Y,0)`
7. **Animation API:** Use `AnimationLibrary` + `add_animation_library("base", lib)` + play with `"base/Idle"`.
8. **HUD:** Use `CanvasLayer` for GUI (renders even when 3D viewport is black).
9. **Google Earth bridge:** UDP to KML via `/tmp/kml_bridge_v2.py` on port 9999.

## Airport Data
- KDED DeLand Municipal: 29.067°N, 81.284°W, 79ft/24m elevation
- USGS 3DEP DEM downloaded (srtm_deland_enhanced.tif)
- Heightmap: 512×512, 4000×4000 game units, max elevation 80m
- Runways: 12/30 (6001×100ft), 5/23 (4300×75ft)

## Key Files
| File | Purpose |
|---|---|
| `godot_project/scripts/build_terrain.gd` | Main scene (terrain + character + HUD + UDP) |
| `godot_project/scenes/main.tscn` | Godot scene |
| `godot_project/assets/terrain/heightmap_512.raw` | Elevation data (512×512 uint16) |
| `godot_project/assets/characters/parachutist.fbx` | Source character (2.3MB Mixamo) |
| `/tmp/kml_bridge_v2.py` | UDP→KML bridge for Google Earth |
| `.cfd_healdb` | SQLite error/fix database |
