#!/usr/bin/env python3
import sys
from pathlib import Path

TARGET = Path("godot_project/scripts/build_terrain.gd")
if not TARGET.exists():
    print(f"FAIL: {TARGET} not found")
    sys.exit(1)

src = TARGET.read_text(encoding="utf-8")
print(f"[VERBATIM] Read {TARGET}: {len(src)} bytes")

OLD = (
    "        _main_canopy_node = main_canopy_scene2.instantiate()\n"
    "        _main_canopy_node.position = Vector3(0.0, 2.5, 0.0)\n"
    "        _character.add_child(_main_canopy_node)\n"
)
NEW = (
    "        _main_canopy_node = main_canopy_scene2.instantiate()\n"
    "        _main_canopy_node.position = Vector3(0.0, 2.5, 0.0)\n"
    "        _main_canopy_node.scale = Vector3(0.35, 0.25, 0.35)\n"
    "        _character.add_child(_main_canopy_node)\n"
)

count = src.count(OLD)
assert count == 1, f"GATE FAIL: expected 1 occurrence, found {count}"
result = src.replace(OLD, NEW, 1)
print("PASS [_main_canopy_node scale added]")

TARGET.write_text(result, encoding="utf-8")
verify = TARGET.read_text(encoding="utf-8")
assert verify == result, "READ-BACK FAIL"
print(f"[VERBATIM] READ-BACK PASS: {TARGET.stat().st_size} bytes")

assert "        _main_canopy_node.scale = Vector3(0.35, 0.25, 0.35)\n" in verify
print("PASS [post-check scale line present]")
print("\n# IMPLEMENTATION COMPLETE")
