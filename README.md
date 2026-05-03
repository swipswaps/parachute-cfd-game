# Parachute CFD Landing Game

Gamified parachute landing simulator combining real Google Earth terrain data with OpenFOAM CFD wind simulations visualized as rotating wind rotors over actual buildings, trees, and terrain features.

## Concept

Land a parachute accurately by reading real-time wind conditions visualized as 3D rotating wind rotors (turbines) placed over the actual terrain. Wind patterns include:
- **Building wake turbulence** - rotors show wind deflection around structures
- **Tree canopy effects** - reduced wind speed, turbulence visualization
- **Solar thermal lift** - rising air columns over heated surfaces (parking lots, roofs)
- **Terrain channeling** - valley/street wind acceleration zones

## Architecture

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


## Data Flow

### 1. Google Earth → Terrain Model
- **Tool**: Google Earth Pro or RenderDoc
- **Export**: COLLADA (.dae) with elevation data
- **Location examples**: 
  - Urban: Downtown areas with tall buildings
  - Mixed: Parks with trees + buildings
  - Thermal: Parking lots, industrial zones (solar heating)

### 2. Terrain → OpenFOAM Mesh
- **Input**: COLLADA geometry
- **Process**: Convert to STL → snappyHexMesh
- **Output**: CFD mesh with refined zones (building edges, tree canopies)

### 3. CFD Simulation
- **Solver**: buoyantSimpleFoam (thermal effects) or simpleFoam (isothermal)
- **Boundary conditions**:
  - Inlet: Realistic wind profile (log-law, 5-15 m/s)
  - Surfaces: Wall functions, thermal zones (solar heated)
  - Trees: Porous media zones
- **Output**: 3D velocity and temperature fields

### 4. Wind Visualization
- **Method**: Place 3D rotor models at grid points
- **Rotation**: Local wind speed drives RPM
- **Orientation**: Rotor axis aligned with wind vector
- **Color coding**: 
  - Blue: Calm (< 3 m/s)
  - Green: Moderate (3-8 m/s)
  - Yellow: Strong (8-12 m/s)
  - Red: Dangerous (> 12 m/s)

### 5. Godot Game
- **Terrain**: Imported COLLADA from Google Earth
- **Wind field**: Interpolated from CFD data (JSON/binary)
- **Parachute**: Physics body responding to local wind
- **Rotors**: MeshInstance3D with AnimationPlayer
- **HUD**: Wind speed, altitude, target distance

## Technical Requirements

### Software Stack
- **Google Earth Pro**: Terrain export (free desktop version)
  - Source: https://www.google.com/earth/versions/
- **Blender 3.6+**: COLLADA cleanup, mesh optimization
  - Source: https://www.blender.org/download/
- **OpenFOAM v10+**: CFD simulation
  - Source: https://openfoam.org/download/
- **ParaView 5.11+**: CFD post-processing, wind vector extraction
  - Source: https://www.paraview.org/download/
- **Godot 4.2+**: Game engine
  - Source: https://godotengine.org/download

### Python Dependencies
```bash
pip install --user numpy vtk trimesh pykml lxml gdal

Workflow
Step 1: Extract Google Earth Terrain

Option A: Google Earth Pro Export
bash

# 1. Open Google Earth Pro
# 2. Navigate to target location (e.g., 37.7749° N, 122.4194° W for San Francisco)
# 3. Zoom to desired area (100-500m radius recommended)
# 4. File → Save → Save Place As... → KML
# 5. Tools → Options → 3D View → Set terrain quality to Maximum
# 6. Use third-party tools to extract 3D buildings:
#    - SketchUp Pro (File → Geo-location → Add Location)
#    - Blender with Google Earth Decoder addon

Option B: Programmatic (using this repo's tools)
bash

# Generate KML for specific coordinates
python scripts/generate_terrain_kml.py \
    --lat 37.7749 \
    --lon -122.4194 \
    --radius 300 \
    --output terrain_sf_downtown.kml

# Download terrain tiles (requires API key)
python scripts/download_terrain_tiles.py \
    --kml terrain_sf_downtown.kml \
    --api-key YOUR_GOOGLE_API_KEY \
    --output terrain/sf_downtown.dae

Step 2: Process Terrain for CFD
bash

# Convert COLLADA to STL for OpenFOAM
python scripts/collada_to_stl.py \
    --input terrain/sf_downtown.dae \
    --output cfd_mesh/terrain.stl \
    --simplify 0.5  # Reduce polygon count for CFD

# Identify building/tree zones from geometry
python scripts/classify_geometry.py \
    --input terrain/sf_downtown.dae \
    --output cfd_mesh/zones.json
    # Output: {"buildings": [...], "trees": [...], "ground": [...]}

Step 3: Generate OpenFOAM Mesh
bash

# Create base mesh directory
./scripts/setup_openfoam_case.sh sf_downtown

cd cases/sf_downtown

# Configure snappyHexMesh for terrain
# (automatically generated from zones.json)
./Allrun.mesh

# Expected output:
# - Refined mesh around buildings
# - Porous zones for trees
# - Ground with thermal boundary patches

Step 4: Run CFD Simulation
bash

# Isothermal case (wind only)
cd cases/sf_downtown
./Allrun.isothermal

# Thermal case (solar heating + wind)
./Allrun.thermal

# Monitor convergence
foamMonitor -l postProcessing/residuals/0/residuals.dat

Step 5: Extract Wind Data for Game
bash

# Export wind vectors at rotor positions
pvpython scripts/extract_wind_vectors.py \
    --case cases/sf_downtown \
    --time latest \
    --grid-spacing 10 \
    --output game_data/wind_field.json

# Generate rotor placement data
python scripts/place_rotors.py \
    --wind-field game_data/wind_field.json \
    --terrain terrain/sf_downtown.dae \
    --output game_data/rotor_positions.json

Step 6: Build Godot Game
bash

# Import assets
cp terrain/sf_downtown.dae godot_project/assets/terrain/
cp game_data/*.json godot_project/data/

# Open in Godot
godot godot_project/project.godot

# Or build standalone
godot --headless --export-release "Linux/X11" parachute_game.x86_64

Game Mechanics
Parachute Physics

    Drag coefficient: Cd = 1.5 (realistic ram-air parachute)

        Source: Knacke, T.W. (1991). "Parachute Recovery Systems Design Manual". Para Publishing.

    Glide ratio: 3:1 (forward:descent)

    Wing loading: 0.8 lb/ft² typical sport parachute

    Turn rate: Bank angle → turn rate via lift vector

Wind Interaction

    Sample rate: 60 Hz interpolation from CFD grid

    Turbulence: Perlin noise overlay (10% of mean wind)

    Thermal lift: Updraft zones over dark surfaces (2-5 m/s)

        Source: Reichmann, H. (2005). "Cross-Country Soaring". Soaring Society of America.

Scoring System

Base Score: 1000 points

Distance from target: -10 pts/meter
Excess speed at landing: -5 pts per m/s over 3 m/s
Flight time bonus: +2 pts/second (efficiency)
Wind reading bonus: +50 pts if landed upwind of target
Thermal usage bonus: +100 pts if used thermal lift
Difficulty Levels

    Novice: Calm winds (2-4 m/s), no thermals, large target

    Sport: Moderate winds (5-8 m/s), weak thermals, medium target

    Expert: Strong winds (8-12 m/s), strong thermals, small target

    Extreme: Variable winds, building rotors, thermal streets, precision target

CFD Validation
Wind Rotor Visualization Accuracy

The rotating wind rotors are not just visual effects - they represent actual CFD-computed wind vectors:

    Rotor RPM: Linearly scaled to local wind speed

        Formula: RPM = wind_speed_m/s * 60 / (2 * π * rotor_radius_m)

        Source: Manwell, J.F. et al. (2009). "Wind Energy Explained". Wiley. Ch.3 p.85

    Rotor orientation: Quaternion from wind vector direction

        Yaw: arctan2(Vy, Vx)

        Pitch: arcsin(Vz / |V|)

CFD Mesh Requirements

    Building resolution: Min 5 cells across smallest building dimension

        Source: Franke, J. et al. (2007). "Best Practice Guideline for CFD simulation of flows in the urban environment". COST Action 732.

    First cell height: y+ < 30 for wall functions

        Source: OpenFOAM User Guide v10, Chapter 7.2.3

        URL: https://www.openfoam.com/documentation/guides/latest/doc/guide-turbulence-ras-wall-functions.html

    Tree porosity: Drag coefficient Cd ≈ 0.2-0.3

        Source: Gromke, C. & Ruck, B. (2008). "Effects of trees on the dilution of vehicle exhaust emissions in urban street canyons". International Journal of Environment and Waste Management.

Example Locations
1. San Francisco Financial District

    Coordinates: 37.7946° N, 122.3999° W

    Features: Tall buildings (wind channeling), Transamerica Pyramid (wake)

    Challenges: Strong building rotors, thermal lift from glass facades

2. Central Park, New York

    Coordinates: 40.7829° N, 73.9654° W

    Features: Open fields, tree canopy, surrounding buildings

    Challenges: Tree turbulence, thermal lift over Sheep Meadow

3. Dubai Marina

    Coordinates: 25.0808° N, 55.1376° E

    Features: Extreme building heights, desert thermal effects

    Challenges: Strong thermals, narrow channels between skyscrapers

File Structure

parachute-cfd-game/
├── README.md
├── requirements.txt
├── scripts/
│ ├── generate_terrain_kml.py # KML generator for locations
│ ├── download_terrain_tiles.py # Google Earth data fetcher
│ ├── collada_to_stl.py # Terrain → STL converter
│ ├── classify_geometry.py # Auto-detect buildings/trees
│ ├── setup_openfoam_case.sh # CFD case generator
│ ├── extract_wind_vectors.py # CFD → game data
│ └── place_rotors.py # Rotor position calculator
├── cases/
│ └── template/ # OpenFOAM case template
│ ├── 0.orig/ # Boundary conditions
│ ├── constant/ # Mesh, turbulence models
│ ├── system/ # Solver settings
│ ├── Allrun.mesh
│ ├── Allrun.isothermal
│ └── Allrun.thermal
├── godot_project/
│ ├── project.godot
│ ├── scenes/
│ │ ├── main.tscn # Main game scene
│ │ ├── parachute.tscn # Parachute physics
│ │ └── wind_rotor.tscn # Rotor visual
│ ├── scripts/
│ │ ├── parachute_controller.gd # Flight physics
│ │ ├── wind_field.gd # CFD interpolation
│ │ └── game_manager.gd # Scoring, UI
│ ├── assets/
│ │ ├── terrain/ # Imported COLLADA
│ │ ├── models/ # Parachute, rotor meshes
│ │ └── textures/
│ └── data/ # CFD wind field JSON
└── docs/
├── cfd_setup.md # Detailed CFD workflow
├── godot_integration.md # Game implementation guide
└── locations.md # Curated landing zones
References
Google Earth Data

    Google Earth KML Reference: https://developers.google.com/kml/documentation/kmlreference

    COLLADA 1.4.1 Specification: https://www.khronos.org/collada/

OpenFOAM CFD

    OpenFOAM v10 User Guide: https://www.openfoam.com/documentation/guides/latest/doc/

    buoyantSimpleFoam Solver: https://www.openfoam.com/documentation/guides/latest/api/classFoam_1_1buoyantSimpleFoam.html

    snappyHexMesh: https://www.openfoam.com/documentation/guides/latest/doc/guide-meshing-snappyhexmesh.html

Parachute Aerodynamics

    Knacke, T.W. (1991). "Parachute Recovery Systems Design Manual". Para Publishing. NWC TP 6575.

    Lingard, J.S. (1995). "Ram-Air Parachute Design". AIAA Paper 95-1565.

Urban CFD Validation

    COST Action 732 (2007). "Best Practice Guideline for CFD simulation of flows in the urban environment".

        URL: http://www.cost.eu/domains_actions/essem/Actions/732

Godot Engine

    Godot 4.2 Documentation: https://docs.godotengine.org/en/stable/

    Physics Servers: https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html

License

MIT License - See LICENSE file
Contributing

Contributions welcome! Focus areas:

    Additional validated CFD cases (cities, terrain types)

    Improved thermal modeling (solar angle, surface materials)

    Multiplayer parachute racing

    VR support for immersive landing experience