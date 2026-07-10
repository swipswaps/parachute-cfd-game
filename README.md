# Parachute Landing Pattern – v314 (current) + CFD Roadmap

**Current working game:** a USPA‑compliant skydiving malfunction trainer.  
**Planned evolution:** add real‑time CFD wind fields, Google Earth terrain, and rotating wind rotors.

---

## Current Features (fully repaired, verified)

A skydiving canopy flight simulator built in Godot 4.6.2.  
Implements USPA Integrated Student Program (ISP) sequence: freefall → deploy → opening animation → diagnose → fly to landing.

### Controls (after clicking the game window)

- SPACE       – deploy pilot chute (from freefall, ~4000–6000 ft)
- Q / E       – turn left / right (during diagnosis phase)
- C           – cycle camera (behind / side / pilot‑up / chase)
- H           – toggle HUD
- Tab         – flight control check (diagnosis phase)
- X           – cut away malfunctioning main canopy
- V           – deploy reserve canopy
- F           – flare (only after flight check and good canopy)
- R           – restart game
- Escape      – pause

Controller support: left/right shoulder = turn, A = flight check, X = cutaway, B = reserve, Y = flare, Start = restart.

### State machine (matches USPA ISP)

- FREEFALL    – exit aircraft, fast descent, only SPACE works.
- OPENING_ANIM – canopy inflates over 1.2 seconds, controls locked.
- DIAGNOSIS   – canopy open, all controls active, random malfunction assigned.
- LANDED      – successful landing (flare or reserve).
- GAME_OVER   – fatal ground impact or decision‑altitude violation.

Decision altitude: 2500 ft AGL. Failure to cut away/reserve by this altitude triggers GAME_OVER.

### Recent fixes applied (all verified)

- Inserted missing `if _game_state == GameState.FREEFALL:` guard for flight movement block.
- Added `_poll_controls()` call to `_process()` – controls now respond every frame.
- Fixed state machine: `_deploy_canopy()` now sets `OPENING_ANIM`; `_physics_process` counts down `_deployment_timer` and transitions to `DIAGNOSIS`.
- Corrected InputMap: added `turnleft`, `turnright`, `cyclecamera`, `togglehud`, `flightcheck`, `pause` actions.
- Repaired malformed `"events:[]}deploy"` key – renamed to `deploy`.
- Removed duplicate functions (`_unhandled_input`, `toggle_pause`).
- Raised starting altitude from 3000 ft to 6000 ft (USPA ISP Category A).
- Added verbose logging for deploy checks and ground impact (state + altitude).
- Screenshot on every GAME_OVER (saved to `user://screenshots/`).
- Fixed freefall camera orbit: right‑click drag now orbits the camera in freefall (same as plane) and character no longer auto‑rotates from velocity.

### Running the current game

Use the debug wrapper script to auto‑focus the window and stream logs:

    cd /path/to/parachute-cfd-game
    ./run_game_debug.sh

If `xdotool` is not installed, install it first:

    sudo apt install xdotool   # Debian/Ubuntu
    sudo dnf install xdotool   # Fedora

Then click the game window manually after it opens.

### Troubleshooting (current version)

- **No key presses work** → ensure the game window has focus (click it or use `run_game_debug.sh`).
- **SPACE does nothing** → check that the InputMap action `deploy` exists (run `repair_gdscript_v2.py`).
- **Game ends instantly** → altitude may be 3000 ft; run the repair script to raise to 6000 ft.
- **Parse errors** → run the repair script:

        cd godot_project
        python3 addons/gd_repair/repair_gdscript_v2.py scripts/build_terrain.gd

The repair script is idempotent – safe to run multiple times.

---

## Roadmap / Planned Future Features

The following are **not yet implemented** but are planned for future versions. They will transform the game into a full CFD‑based parachute landing simulator with Google Earth terrain and real‑time wind visualization.

### Concept (future)

Land a parachute accurately by reading real‑time wind conditions visualized as 3D rotating wind rotors (turbines) placed over the actual terrain. Wind patterns will include:
- Building wake turbulence – rotors show wind deflection around structures
- Tree canopy effects – reduced wind speed, turbulence visualization
- Solar thermal lift – rising air columns over heated surfaces (parking lots, roofs)
- Terrain channeling – valley/street wind acceleration zones

### Planned Architecture (future)

    Google Earth Terrain Export
    ↓
    OpenFOAM CFD Mesh Generation (buildings, trees, terrain)
    ↓
    Wind Flow Simulation (thermal effects, obstacles)
    ↓
    Wind Vector Field → Rotor Visualization Data
    ↓
    Godot Game Engine
    ├─ Terrain from Google Earth (COLLADA/glTF)
    ├─ Wind Rotors (rotating at local wind speed/direction)
    ├─ Parachute Physics (responds to CFD wind field)
    └─ Scoring (accuracy, time, wind reading skill)

### Planned Data Flow (future)

1. **Google Earth → Terrain Model**  
   - Tool: Google Earth Pro or RenderDoc  
   - Export: COLLADA (.dae) with elevation data  

2. **Terrain → OpenFOAM Mesh**  
   - Input: COLLADA geometry → STL → snappyHexMesh  
   - Output: CFD mesh with refined zones (building edges, tree canopies)

3. **CFD Simulation**  
   - Solver: buoyantSimpleFoam (thermal effects) or simpleFoam (isothermal)  
   - Output: 3D velocity and temperature fields

4. **Wind Visualization**  
   - Place 3D rotor models at grid points, rotation speed from local wind, colour‑coded by wind speed (blue calm → red dangerous)

5. **Godot Integration**  
   - Import COLLADA terrain, interpolate CFD wind field, parachute physics, rotor animations

### Planned Technical Stack (future)

- Google Earth Pro – terrain export  
- Blender 3.6+ – COLLADA cleanup  
- OpenFOAM v10+ – CFD simulation  
- ParaView 5.11+ – wind vector extraction  
- Godot 4.2+ – game engine  

Python dependencies (future scripts):

    pip install --user numpy vtk trimesh pykml lxml gdal

### Planned Workflow (future)

Step 1: Extract Google Earth Terrain (using scripts/generate_terrain_kml.py etc.)  
Step 2: Process Terrain for CFD (collada_to_stl.py, classify_geometry.py)  
Step 3: Generate OpenFOAM Mesh (setup_openfoam_case.sh, snappyHexMesh)  
Step 4: Run CFD Simulation (Allrun.isothermal / Allrun.thermal)  
Step 5: Extract Wind Data for Game (extract_wind_vectors.py, place_rotors.py)  
Step 6: Build Godot Game (import assets, wind field interpolation, rotor visuals)

### Planned Game Mechanics (future)

- **Parachute Physics** – realistic ram‑air parachute (Cd, glide ratio, turn rate)  
- **Wind Interaction** – 60 Hz interpolation from CFD grid, turbulence overlay, thermal lift  
- **Scoring System** – 1000 base points minus distance/speed penalties, plus bonuses for wind reading and thermal usage  
- **Difficulty Levels** – Novice, Sport, Expert, Extreme (varying wind, thermals, target size)

### Example Future Locations

- San Francisco Financial District – tall building wind channeling, thermal lift from glass facades  
- Central Park, New York – open fields, tree canopy turbulence, thermal lift over meadows  
- Dubai Marina – extreme building heights, desert thermals, narrow wind channels

### Planned File Structure (future additions)

    scripts/          – terrain extraction, CFD conversion, rotor placement  
    cases/            – OpenFOAM case templates  
    godot_project/    – scenes, scripts, assets, data for wind field  
    docs/             – CFD setup, Godot integration, location guides

### References (future work)

- Google Earth KML Reference, COLLADA 1.4.1  
- OpenFOAM v10 User Guide, snappyHexMesh  
- Knacke, T.W. "Parachute Recovery Systems Design Manual"  
- COST Action 732 "Best Practice Guideline for CFD simulation of flows in the urban environment"  
- Godot 4.2 Documentation

---

## Repository

- Game code: (your remote URL, e.g., `https://github.com/swipswaps/parachute-cfd-game`)
- Repair script repository: `https://github.com/swipswaps/gdscript-repair`

## License

MIT – see LICENSE file.

## Contributing

Contributions welcome for both current game improvements and future CFD features.