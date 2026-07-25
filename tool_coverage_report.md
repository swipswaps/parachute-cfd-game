# Tool coverage audit — run 2

- source_db (read-only): `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/parachute_mutations.db`
- generated:             `2026-07-11 09:46:08`

## Coverage gap — installed but unused

| tool | family | why it matters | probe exit |
|---|---|---|---|
| **ast-grep** | ast-grep | Structural search/replace across 26+ languages [4] | 0 |
| **diff** | general | Unified diff output for dry-run reports | 0 |
| **gd2py** | gdtoolkit | GDScript-to-Python converter [3] — unlocks stdlib ast [2] and ast-grep [4] | 0 |
| **gdcli** | unknown | Not verified via web search; probe records actual --help output | 0 |
| **gdeye** | unknown | Not verified via web search; probe records actual --help output | 0 |
| **gdshrapt** | gdshrapt | Semantic-level GDScript platform [5] | 0 |
| **git** | general | Diffs, blame, log — read-only history the hub can show | 0 |
| **sg** | ast-grep | ast-grep alias per its docs [4] | 0 |

## Installed AND used (real counts)

| tool | family | aha uses | audit uses | variants | variant uses | total |
|---|---|---:|---:|---|---:|---:|
| gdformat | gdtoolkit | 1243 | 503 | — | 0 | **1746** |
| gdlint | gdtoolkit | 819 | 19 | — | 0 | **838** |
| gdparse | gdtoolkit | 8348 | 171 | gdparse_check | 907 | **9426** |
| gdradon | gdtoolkit | 192 | 13 | — | 0 | **205** |
| gdstyle | gdstyle | 373 | 13 | gdstyle_--fix, gdstyle_--unsafe-fix | 2664 | **3050** |

## Not installed on this host

_All candidates present._

## gd2py → Python-AST bridge demo

- sample: `godot_project/scripts/build_terrain.gd`
- gd2py exit: `0`
- ast.parse ok: **True**
- nodes extracted: **1812**

**Head of Python source (from gd2py):**

```python
pass
camera_target = 1
_cam_distance = 1
_cam_azimuth = 1
_cam_elevation = 1
LegLabel = 1
pass
_game_state = 1
_plane_node = 1
_plane_angle = 1
_PLANE_ORBIT_RADIUS = 1
_PLANE_ORBIT_SPEED = 1
_PLANE_ALTITUDE = 1
_camera = None
_character = None
_hud_labels = 1
_hud_layer = None
_focus_label = None
_frame_count = 1
_pip_viewport = None
_pip_camera = None
_pip_canopy_node = None
_main_canopy_node = None
_wind_label = None
_pip_layer = None
_velocity_vec = 1
_forward_speed = 1
_turn_input = 1
_max_s
```

**Structural signature (first 20 nodes):**

```json
[
  {
    "node": "Assign",
    "line": 2,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 3,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 4,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 5,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 6,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 8,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 9,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 10,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 11,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 12,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 13,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 14,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 15,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 16,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 17,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 18,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 19,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 20,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 21,
    "name": "Assign"
  },
  {
    "node": "Assign",
    "line": 22,
    "name": "Assign"
  }
]
```
