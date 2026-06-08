#!/usr/bin/env python3
# PATH: patch_canopy_hud.py
# WHAT: fix canopy scale (too large relative to skeleton) and HUD duplicate
#       CanvasLayer accumulation (gray box covering left of screen)
#
# WHY:  1. Canopy: procedural sphere radius=1.5 with final scale Vector3(1,1,1)
#          produces a 3m-diameter dome on a 1.8m skeleton — visually enormous.
#          Fix: radius=0.6, final scale Vector3(0.35,0.25,0.35).
#          Source: Godot 4 SphereMesh docs — radius is in metres, scale multiplies it.
#          https://docs.godotengine.org/en/stable/classes/class_spheremesh.html
#       2. HUD: _update_canopy_visuals() creates a new CanvasLayer + all labels
#          on every call. _randomize_malfunction() calls it on every reset.
#          Multiple overlapping CanvasLayers render as a gray block.
#          Fix: guard with `if _hud_layer:` so creation runs exactly once.
#          Source: Godot 4 CanvasLayer docs — each instance is a separate compositor layer.
#          https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html
#
# MENTAL MODEL BEFORE:
#   - Canopy: radius=1.5 * scale=1.0 = 1.5m radius (3m wide) dome
#   - HUD: every reset spawns a new CanvasLayer stacked on previous ones
# MENTAL MODEL AFTER:
#   - Canopy: radius=0.6 * scale=0.35 = 0.21m radius — proportional to skeleton
#   - HUD: CanvasLayer created once; subsequent calls skip creation block
#
# FAILURE MODE:
#   - If assert fires: the exact string changed since this patch was written —
#     run: grep -n 'sphere_mesh.radius\|Vector3(1,1,1)\|_hud_layer = CanvasLayer' build_terrain.gd
#     to find current line and update OLD strings below
#   - If read-back fails: disk full or permission error on write
#
# VERIFIES WITH:
#   - Script prints PASS for each of 5 replacements
#   - grep confirms new values present, old values absent
#   - bash -n confirms no syntax error introduced in the .gd file (GDScript
#     syntax check requires Godot headless; bash -n only catches shell issues
#     in this script itself)
#
# ASSUMES:
#   - cwd is parachute-cfd-game when this script is run
#   - build_terrain.gd matches the verbatim text from docs 8, 9, 10

import sys
from pathlib import Path

TARGET = Path("godot_project/scripts/build_terrain.gd")

# Guard: file must exist
if not TARGET.exists():
    print(f"FAIL: {TARGET} not found — run from parachute-cfd-game/")
    sys.exit(1)

src = TARGET.read_text(encoding="utf-8")
original_size = len(src)
print(f"[VERBATIM] Read {TARGET}: {original_size} bytes")

changes = [
    # ------------------------------------------------------------------
    # FIX 1a: procedural canopy sphere radius 1.5 → 0.6
    # Confirmed from doc 8 verbatim: "sphere_mesh.radius = 1.5"
    # ------------------------------------------------------------------
    (
        "canopy sphere radius",
        "    sphere_mesh.radius = 1.5\n",
        "    sphere_mesh.radius = 0.6\n",
    ),
    # ------------------------------------------------------------------
    # FIX 1b: procedural canopy initial scale Vector3(1.0,1.0,0.3) → Vector3(0.35,0.25,0.35)
    # Confirmed from doc 8 verbatim: "_canopy_instance.scale = Vector3(1.0, 1.0, 0.3)"
    # ------------------------------------------------------------------
    (
        "canopy initial scale",
        "    _canopy_instance.scale = Vector3(1.0, 1.0, 0.3)\n",
        "    _canopy_instance.scale = Vector3(0.35, 0.25, 0.35)\n",
    ),
    # ------------------------------------------------------------------
    # FIX 1c: deployment animation final scale at line 1263
    # Confirmed from doc 9 grep: line 1263 "_canopy_instance.scale = Vector3(1,1,1)"
    # inside OPENING_ANIM block — this is the post-animation settled scale
    # Replace only the one inside the OPENING_ANIM block by using surrounding context
    # ------------------------------------------------------------------
    (
        "deployment final scale (OPENING_ANIM block)",
        "            _game_state = GameState.DIAGNOSIS\n            _canopy_instance.scale = Vector3(1,1,1)\n            print(\"[VERBATIM] Canopy fully inflated – enter diagnosis\")",
        "            _game_state = GameState.DIAGNOSIS\n            _canopy_instance.scale = Vector3(0.35, 0.25, 0.35)\n            print(\"[VERBATIM] Canopy fully inflated – enter diagnosis\")",
    ),
    # ------------------------------------------------------------------
    # FIX 1d: reset block scale at line 1199
    # Confirmed from doc 10 verbatim:
    #   "        _canopy_instance.scale = Vector3(1,1,1)"
    # inside the reset block (after "_canopy_instance.visible = false")
    # ------------------------------------------------------------------
    (
        "reset block canopy scale",
        "        _canopy_instance.visible = false\n        _canopy_instance.scale = Vector3(1,1,1)\n    _randomize_malfunction()",
        "        _canopy_instance.visible = false\n        _canopy_instance.scale = Vector3(0.35, 0.25, 0.35)\n    _randomize_malfunction()",
    ),
    # ------------------------------------------------------------------
    # FIX 2: HUD duplicate CanvasLayer guard
    # Confirmed from doc 8 verbatim: "_hud_layer = CanvasLayer.new()" is the
    # first line of the HUD block inside _update_canopy_visuals().
    # Guard: skip entire HUD creation if _hud_layer already exists.
    # ------------------------------------------------------------------
    (
        "HUD duplicate CanvasLayer guard",
        "    # --------------------------------------------------------------\n    # HUD (8 lines + score + notification)\n    # Ref: https://docs.godotengine.org/en/stable/classes/class_label.html\n    # --------------------------------------------------------------\n    _hud_layer = CanvasLayer.new()",
        "    # --------------------------------------------------------------\n    # HUD (8 lines + score + notification)\n    # Ref: https://docs.godotengine.org/en/stable/classes/class_label.html\n    # --------------------------------------------------------------\n    if _hud_layer:\n        return\n    _hud_layer = CanvasLayer.new()",
    ),
]

result = src
for name, old, new in changes:
    count = result.count(old)
    assert count == 1, (
        f"GATE FAIL [{name}]: expected exactly 1 occurrence, found {count}.\n"
        f"  Pattern: {repr(old[:80])}"
    )
    result = result.replace(old, new, 1)
    print(f"PASS [{name}]: 1 occurrence replaced")

# Read-back verification
TARGET.write_text(result, encoding="utf-8")
verify = TARGET.read_text(encoding="utf-8")
assert verify == result, "READ-BACK FAIL: on-disk content does not match in-memory content"
print(f"[VERBATIM] READ-BACK PASS: {TARGET.stat().st_size} bytes written and verified")

# Confirm new values present
checks = [
    ("radius 0.6 present",        "sphere_mesh.radius = 0.6"),
    ("radius 1.5 absent",         "sphere_mesh.radius = 1.5"),
    ("scale 0.35 present",        "Vector3(0.35, 0.25, 0.35)"),
    ("HUD guard present",         "if _hud_layer:\n        return"),
]
for label, pattern in checks:
    found = pattern in verify
    expected = "absent" not in label
    if found == expected:
        print(f"PASS [post-check {label}]")
    else:
        print(f"FAIL [post-check {label}] — manual inspection required")
        sys.exit(1)

print("\n# IMPLEMENTATION COMPLETE")
print("Run: cd parachute-cfd-game && python3 patch_canopy_hud.py")
print("Then launch game and confirm canopy is skeleton-proportional and HUD has no gray box")