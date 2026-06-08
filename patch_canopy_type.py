#!/usr/bin/env python3
# PATH: patch_canopy_type.py
# WHAT: fix _canopy_instance type declaration (MeshInstance3D → Node3D) so
#       GLB instantiation assignment no longer fails with type mismatch,
#       and fix _update_canopy_visuals GOOD case resetting scale to 1,1,1
#
# WHY:  1. var _canopy_instance: MeshInstance3D — GLB scene.instantiate()
#          returns Node3D (the GLB root). GDScript strict typing rejects the
#          assignment and silently nulls _canopy_instance, so all scale fixes
#          and visibility calls are skipped. The GLB canopy renders unscaled
#          via the PiP path instead.
#          Fix: declare as Node3D. For material_override, find the first
#          MeshInstance3D child inside the GLB.
#          Source: Godot 4 docs — PackedScene.instantiate() returns Node, not
#          the specific subtype of the root node.
#          https://docs.godotengine.org/en/stable/classes/class_packedscene.html
#       2. _update_canopy_visuals GOOD branch resets scale to Vector3(1,1,1)
#          overriding the deployed scale. Fix: use Vector3(0.35,0.25,0.35).
#
# MENTAL MODEL BEFORE:
#   GLB load → type mismatch → _canopy_instance = null → scale fix skipped
#   → GLB renders via PiP path at full world scale → enormous canopy
# MENTAL MODEL AFTER:
#   GLB load → Node3D assigned OK → scale fix applies → proportional canopy
#
# FAILURE MODE: assert fires → exact string changed; run
#   grep -n 'var _canopy_instance\|material_override\|Vector3(1,1,1)' build_terrain.gd
# VERIFIES WITH: no type mismatch in log; canopy proportional in screenshot
# ASSUMES: cwd is parachute-cfd-game; file matches verbatim output from docs

import sys
from pathlib import Path

TARGET = Path("godot_project/scripts/build_terrain.gd")
if not TARGET.exists():
    print(f"FAIL: {TARGET} not found")
    sys.exit(1)

src = TARGET.read_text(encoding="utf-8")
print(f"[VERBATIM] Read {TARGET}: {len(src)} bytes")

changes = [
    # ------------------------------------------------------------------
    # FIX 1: declaration — MeshInstance3D → Node3D
    # Confirmed from verbatim: line 89 "var _canopy_instance: MeshInstance3D"
    # ------------------------------------------------------------------
    (
        "canopy declaration MeshInstance3D→Node3D",
        "var _canopy_instance: MeshInstance3D\n",
        "var _canopy_instance: Node3D\n",
    ),
    # ------------------------------------------------------------------
    # FIX 2: material_override on GLB root — Node3D has no material_override.
    # Replace with child search for first MeshInstance3D inside the GLB.
    # Confirmed from verbatim lines 382-385:
    #   _canopy_instance.position = Vector3(0, 2.5, 0)
    #   _canopy_material = StandardMaterial3D.new()
    #   _canopy_instance.material_override = _canopy_material
    #   _canopy_instance.visible = false
    # ------------------------------------------------------------------
    (
        "GLB material_override → child mesh search",
        "                _canopy_instance.position = Vector3(0, 2.5, 0)\n"
        "                _canopy_material = StandardMaterial3D.new()\n"
        "                _canopy_instance.material_override = _canopy_material\n"
        "                _canopy_instance.visible = false\n",
        "                _canopy_instance.position = Vector3(0, 2.5, 0)\n"
        "                _canopy_instance.scale = Vector3(0.35, 0.25, 0.35)\n"
        "                _canopy_material = StandardMaterial3D.new()\n"
        "                var _mesh_child = _find_first_mesh(_canopy_instance)\n"
        "                if _mesh_child:\n"
        "                    _mesh_child.material_override = _canopy_material\n"
        "                _canopy_instance.visible = false\n",
    ),
    # ------------------------------------------------------------------
    # FIX 3: GOOD malfunction branch resets scale to 1,1,1 — override fix
    # Confirmed from verbatim lines 568-570
    # ------------------------------------------------------------------
    (
        "GOOD malfunction scale reset",
        "            if _canopy_instance:\n"
        "                _canopy_instance.scale = Vector3(1,1,1)\n"
        "                _canopy_instance.rotation_degrees = Vector3.ZERO\n",
        "            if _canopy_instance:\n"
        "                _canopy_instance.scale = Vector3(0.35, 0.25, 0.35)\n"
        "                _canopy_instance.rotation_degrees = Vector3.ZERO\n",
    ),
]

result = src
for name, old, new in changes:
    count = result.count(old)
    assert count == 1, (
        f"GATE FAIL [{name}]: expected 1 occurrence, found {count}\n"
        f"  Pattern: {repr(old[:80])}"
    )
    result = result.replace(old, new, 1)
    print(f"PASS [{name}]")

# ------------------------------------------------------------------
# Insert _find_first_mesh helper before _deploy_canopy
# Confirmed anchor: "func _deploy_canopy():" from doc 8 verbatim
# ------------------------------------------------------------------
HELPER = (
    "# Helper: find first MeshInstance3D child recursively\n"
    "# WHY: GLB root is Node3D; material_override lives on MeshInstance3D child\n"
    "# Source: https://docs.godotengine.org/en/stable/classes/class_node.html\n"
    "func _find_first_mesh(node: Node) -> MeshInstance3D:\n"
    "    if node is MeshInstance3D:\n"
    "        return node\n"
    "    for child in node.get_children():\n"
    "        var found = _find_first_mesh(child)\n"
    "        if found:\n"
    "            return found\n"
    "    return null\n"
    "\n"
)
ANCHOR = "func _deploy_canopy():\n"
count = result.count(ANCHOR)
assert count == 1, f"GATE FAIL [helper anchor]: expected 1, found {count}"
result = result.replace(ANCHOR, HELPER + ANCHOR, 1)
print("PASS [_find_first_mesh helper inserted]")

TARGET.write_text(result, encoding="utf-8")
verify = TARGET.read_text(encoding="utf-8")
assert verify == result, "READ-BACK FAIL"
print(f"[VERBATIM] READ-BACK PASS: {TARGET.stat().st_size} bytes")

checks = [
    ("Node3D declaration present",        "var _canopy_instance: Node3D"),
    ("MeshInstance3D declaration absent", "var _canopy_instance: MeshInstance3D"),
    ("helper function present",           "_find_first_mesh"),
    ("scale 0.35 in GLB block",           "Vector3(0.35, 0.25, 0.35)"),
    ("GOOD branch scale corrected",       "scale = Vector3(0.35, 0.25, 0.35)"),
]
for label, pattern in checks:
    found = pattern in verify
    expected = "absent" not in label
    status = "PASS" if found == expected else "FAIL"
    print(f"{status} [post-check {label}]")
    if status == "FAIL":
        sys.exit(1)

print("\n# IMPLEMENTATION COMPLETE")