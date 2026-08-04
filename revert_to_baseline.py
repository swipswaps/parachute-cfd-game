#!/usr/bin/env python3
# Revert my two non-fixes to match the proven-working _0062 baseline.
# Grounded: ground_truth_20260804104138.txt shows _0062 uses 1828.8 spawn
# and +_cam_distance; main diverged. Neither affects visibility, but parity
# with the working reference is the correct state.
import sys, shutil, datetime
def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {d}", file=sys.stderr)

T = "godot_project/scripts/build_terrain.gd"
text = open(T, encoding="utf-8").read()
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
bak = f"{T}.bak.{ts}"; shutil.copy2(T, bak); log("backup", True, bak)

errs = []
# Revert camera sign to match _0062 (positive)
O1 = "\tvar offset := Vector3(0, 0, -_cam_distance)"
N1 = "\tvar offset := Vector3(0, 0, _cam_distance)"
if text.count(O1) == 1:
    text = text.replace(O1, N1, 1); log("revert_cam_sign", True, "-> +_cam_distance (matches _0062)")
else:
    errs.append(f"cam_sign count={text.count(O1)}")

# Revert spawn to match _0062 (1828.8) — cosmetic, restores parity
O2 = "\tplane.global_position = Vector3(0, _PLANE_ALTITUDE, 0)"
N2 = "\tplane.global_position = Vector3(0, 1828.8, 0)"
if text.count(O2) == 1:
    text = text.replace(O2, N2, 1); log("revert_spawn", True, "-> 1828.8 (matches _0062)")
else:
    errs.append(f"spawn count={text.count(O2)}")

if errs:
    shutil.copy2(bak, T); log("ROLLBACK", False, str(errs)); sys.exit(f"FAILED: {errs}")

open(T, "w", encoding="utf-8").write(text)
rb = open(T, encoding="utf-8").read()
if rb != text: shutil.copy2(bak, T); sys.exit("read-after-write mismatch, restored")
if "var offset := Vector3(0, 0, -_cam_distance)" in rb: sys.exit("cam sign not reverted")
log("verify", True, "both reverted, read-back OK")
print(f"reverted. backup {bak}")
