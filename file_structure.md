# File Structure

Complete repository layout with descriptions:

parachute-cfd-game/
│
├── README.md                          # Main documentation
├── LICENSE                            # MIT license
├── requirements.txt                   # Python dependencies
├── .gitignore                         # Git ignore patterns
│
├── scripts/                           # Automation scripts
│   ├── generate_terrain_kml.py        # Generate KML for Google Earth location
│   ├── collada_to_stl.py              # Convert terrain COLLADA → STL for CFD
│   ├── classify_geometry.py           # Auto-detect buildings/trees from mesh
│   ├── setup_openfoam_case.sh         # Generate OpenFOAM case from template
│   ├── extract_wind_vectors.py        # CFD results → game JSON
│   └── place_rotors.py                # Calculate rotor visualization positions
│
├── cases/                             # OpenFOAM CFD simulations
│   ├── template/                      # Base case template
│   │   ├── 0.orig/                    # Initial/boundary conditions
│   │   ├── constant/                  # Physics properties, turbulence models
│   │   │   └── triSurface/            # STL geometry files
│   │   └── system/                    # Solver/mesh settings
│   │       ├── controlDict            # Time/output control
│   │       ├── fvSchemes              # Discretization schemes
│   │       ├── fvSolution             # Linear solver settings
│   │       ├── blockMeshDict          # Base mesh generation
│   │       └── snappyHexMeshDict      # Terrain mesh refinement
│   │
│   └── <location_name>/               # Specific location cases (auto-generated)
│       ├── 0.orig/
│       ├── constant/
│       ├── system/
│       ├── Allrun.mesh                # Mesh generation script
│       ├── Allrun.isothermal          # Run isothermal simulation
│       └── Allrun.thermal             # Run buoyant simulation
│
├── terrain/                           # Exported Google Earth data
│   ├── <location>.kml                 # KML placemarks
│   ├── <location>.dae                 # COLLADA 3D terrain
│   └── <location>.stl                 # Simplified STL for CFD
│
├── cfd_mesh/                          # Processed meshes
│   ├── <location>.stl                 # Terrain STL
│   └── zones.json                     # Building/tree classification
│
├── game_data/                         # CFD → game data
│   ├── wind_field.json                # Interpolated wind velocity grid
│   └── rotor_positions.json           # Rotor placement coordinates
│
├── godot_project/                     # Godot game engine project
│   ├── project.godot                  # Godot project config
│   │
│   ├── scenes/                        # Game scenes
│   │   ├── main.tscn                  # Main game scene
│   │   ├── parachute.tscn             # Parachute physics object
│   │   ├── wind_rotor.tscn            # Rotating wind visualization
│   │   └── hud.tscn                   # Heads-up display
│   │
│   ├── scripts/                       # GDScript game logic
│   │   ├── wind_field.gd              # Wind field loader/interpolator
│   │   ├── parachute_controller.gd    # Parachute physics
│   │   ├── game_manager.gd            # Game state/scoring
│   │   └── rotor_visualizer.gd        # Wind rotor rotation logic
│   │
│   ├── assets/                        # Game assets
│   │   ├── terrain/                   # Imported COLLADA terrain
│   │   ├── models/                    # 3D models (parachute, rotor)
│   │   ├── textures/                  # Texture maps
│   │   └── audio/                     # Sound effects
│   │
│   └── data/                          # Runtime data
│       ├── wind_field.json            # Copied from game_data/
│       └── locations.json             # Available landing locations
│
└── docs/                              # Additional documentation
├── cfd_setup.md                   # Detailed CFD workflow guide
├── godot_integration.md           # Game implementation details
├── locations.md                   # Curated landing zone database
└── file_structure.md              # This file


## Key Directories Explained

### `scripts/`
Python scripts for the complete terrain → CFD → game pipeline. Each script is standalone and documented with `--help`.

### `cases/template/`
OpenFOAM case template that `setup_openfoam_case.sh` copies and customizes for each location. Modify this to change default CFD settings globally.

### `godot_project/`
Complete Godot 4.x game project. Open `project.godot` in Godot Editor to develop/test.

### `game_data/`
Intermediate data files between CFD and game. JSON format allows easy inspection and debugging.

## File Size Guidelines

- **Terrain COLLADA**: 5-50 MB typical (Google Earth export)
- **STL mesh**: 1-10 MB after simplification
- **wind_field.json**: 5-20 MB depending on grid spacing
- **Godot project (total)**: < 100 MB without terrain

Large files (> 100 MB) should use Git LFS or be excluded via .gitignore.