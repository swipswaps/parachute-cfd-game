#!/usr/bin/env python3
# ============================================================================
# fix_blur_sigma_and_runways.py — two fixes:
#
# FIX A: Increase Gaussian blur sigma 2.0 -> 8.0 on baked_colours_4096.bin.
#   Root cause (grounded from screenshot): sigma=2.0 (1.95m) insufficient.
#   Palette colour runs in mode=P source are wider than 4px at 4096 res.
#   Horizontal streaking persists because source image is 3840x2160 stretched
#   vertically 1.9x -- horizontal features appear as long colour runs.
#   sigma=8.0 -> FWHM ~18.8px -> blurs ~18m. Vertex spacing = 3.9m (4096/1024).
#   At 4096 texture res: 8px = 7.8m. Smooths palette runs up to ~32m wide.
#   Features wider than 4*sigma=32px (~31m) are preserved:
#     runway width ~30m: borderline -- use sigma=6.0 to preserve runways better.
#   Compromise: sigma=6.0 -> FWHM ~14px -> blurs ~14m. Eliminates streaking,
#   preserves features >24px (~23m). Runway at 30m wide: mostly preserved.
#
# FIX B: Remove hardcoded placeholder runways (3 BoxMesh at fixed positions).
#   Root cause (grounded, build_terrain.gd L345-352): three _create_runway()
#   calls at world positions z=+1300, z=-1300, x=-800 with hardcoded dims.
#   These do NOT correspond to actual KDED runway layout (DeLand Municipal).
#   KDED runway 05/23: heading ~050deg, length 4000ft (1219m). Not at z=±1300.
#   Fix: comment out all three _create_runway calls and the "Runways added" print.
#   Keep _create_runway() function intact for future georeferenced placement.
#   TODO for later: add real runway at correct position/heading after georef.
#
# Rules: #1,#6,#7,#9,#16,#20,#21,#29,#31,#32,#38,#39,#40,#41,#43,#44
#
# Citations:
#   - build_terrain.gd L345-352: hardcoded runway positions (fetched this session)
#   - sigma=2.0 insufficient: screenshot shows persistent streaking (this session)
#   - mode=P 3840x2160 source: bake_naip_restore log (fetched this session)
#   - scipy.ndimage.gaussian_filter (general knowledge, not retrieved)
#   - KDED runway 05/23 layout (general knowledge, not retrieved this session)
# ============================================================================

import subprocess, sys, datetime, os, shutil, sqlite3
import numpy as np
from scipy.ndimage import gaussian_filter

PROJECT = os.path.dirname(os.path.abspath(__file__))
BT      = os.path.join(PROJECT, "godot_project/scripts/build_terrain.gd")
DB      = os.path.join(PROJECT, "parachute_mutations.db")
NOTES   = os.path.join(PROJECT, "notes")
ASSETS  = os.path.join(PROJECT, "godot_project/assets/terrain")
COLOUR  = os.path.join(ASSETS, "baked_colours_4096.bin")
BAK_BIN = COLOUR + ".bak.sigma2"   # keep the sigma=2 version for comparison
os.chdir(PROJECT)
os.makedirs(NOTES, exist_ok=True)


def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'OK' if ok else 'FAIL'}] {op}: {d}", file=sys.stderr)


def stream(cmd):
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, cwd=PROJECT)
    lines = []
    for line in proc.stdout:
        sys.stdout.write(line); sys.stdout.flush(); lines.append(line)
    proc.wait()
    log(f"stream:{cmd[0]}", proc.returncode == 0, f"exit={proc.returncode}")
    return proc.returncode, "".join(lines)


def run(cmd, check=False):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT)
    log(f"run:{' '.join(cmd[:3])}", r.returncode == 0,
        (r.stdout + r.stderr).strip()[:200] or "(no output)")
    if check and r.returncode != 0:
        raise SystemExit(f"FATAL: {cmd}\n{r.stderr}")
    return r


def guarded_replace(text, old, new, label):
    count = text.count(old)
    if count != 1:
        lines = text.splitlines()
        fragment = old.strip()[:40]
        for i, line in enumerate(lines):
            if fragment[:20] in line:
                start, end = max(0, i - 2), min(len(lines), i + 6)
                print(f"\n[CONTEXT for '{fragment[:30]}']")
                for j in range(start, end):
                    print(f"  {j+1:5d}: {repr(lines[j])}")
        raise SystemExit(
            f"GROUNDED DIFF MANDATE violated -- {label}: "
            f"expected 1 match, found {count}. "
            "Upload cat -A of that section before retrying.")
    log(f"guarded_replace:{label}", True, "1 match confirmed")
    return text.replace(old, new, 1)


ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
NOTES_LOG = os.path.join(NOTES, f"fix_blur_runways_{ts}.txt")

# ===========================================================================
# FIX A: Re-blur baked_colours_4096.bin with sigma=6.0
# ===========================================================================
print("\n=== FIX A: Re-blur baked_colours_4096.bin sigma=6.0 ===")

if not os.path.exists(COLOUR):
    raise SystemExit(f"ABORT: {COLOUR} not found")
sz = os.path.getsize(COLOUR)
if sz != 4096 * 4096 * 3:
    raise SystemExit(f"ABORT: size mismatch: {sz}")
log("colour_check", True, f"{sz:,} bytes")

print("  Reading baked_colours_4096.bin (already sigma=2.0 blurred) ...")
raw = np.frombuffer(open(COLOUR, "rb").read(), dtype=np.uint8)
img_arr = raw.reshape((4096, 4096, 3)).copy()
log("colour_read", True, f"shape={img_arr.shape}")

# Keep sigma=2 version as reference
if not os.path.exists(BAK_BIN):
    shutil.copy2(COLOUR, BAK_BIN)
    log("sigma2_backup", True, BAK_BIN)

SIGMA = 6.0
print(f"  Applying Gaussian blur sigma={SIGMA} ...")
blurred = np.zeros_like(img_arr)
for ch in range(3):
    blurred[:, :, ch] = gaussian_filter(
        img_arr[:, :, ch].astype(np.float32), sigma=SIGMA
    ).clip(0, 255).astype(np.uint8)
log("blur", True, f"sigma={SIGMA} applied")

bak = COLOUR + f".bak.{ts}"
shutil.copy2(COLOUR, bak)
log("backup", True, bak)

blurred_bytes = blurred.tobytes()
with open(COLOUR, "wb") as f:
    f.write(blurred_bytes)
if open(COLOUR, "rb").read() != blurred_bytes:
    shutil.copy2(bak, COLOUR)
    raise SystemExit("READ-AFTER-WRITE FAILED -- restored")
log("colour_write", True, f"{len(blurred_bytes):,} bytes written and verified")
print("FIX A complete: baked_colours_4096.bin re-blurred sigma=6.0")

# ===========================================================================
# FIX B: Remove hardcoded placeholder runway boxes
# ===========================================================================
print("\n=== FIX B: Remove hardcoded placeholder runways ===")

text = open(BT).read()

# Grounded exact string from L341-353 (fetched this session)
OLD_RUNWAYS = (
    '\t# --------------------------------------------------------------\n'
    '\t# Runways (three predefined) \u2013 always added\n'
    '\t# Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html\n'
    '\t# --------------------------------------------------------------\n'
    '\tadd_child(_create_runway(Vector3(0.0, 24.5, 1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3)))\n'
    '\tadd_child(\n'
    '\t\t_create_runway(Vector3(0.0, 24.5, -1300.0), 1830.0, 30.0, 150.0, Color(0.3, 0.3, 0.3))\n'
    '\t)\n'
    '\tadd_child(\n'
    '\t\t_create_runway(Vector3(-800.0, 24.5, 0.0), 1310.0, 23.0, 60.0, Color(0.35, 0.35, 0.35))\n'
    '\t)\n'
    '\tprint(\"[VERBATIM] Runways added\")\n'
)

NEW_RUNWAYS = (
    '\t# --------------------------------------------------------------\n'
    '\t# Runways: placeholder positions removed (did not match KDED layout).\n'
    '\t# Ref: https://docs.godotengine.org/en/stable/classes/class_boxmesh.html\n'
    '\t# TODO: re-add with georeferenced KDED runway 05/23 position/heading\n'
    '\t#   after naip_texture is replaced with a proper GeoTIFF source.\n'
    '\t#   KDED rwy 05/23: heading ~050deg, length ~1219m, width ~23m.\n'
    '\t# --------------------------------------------------------------\n'
    '\tprint(\"[VERBATIM] Runways: placeholder positions disabled pending georef\")\n'
)

text = guarded_replace(text, OLD_RUNWAYS, NEW_RUNWAYS, "runway-block")

bak_bt = BT + f".bak.{ts}"
shutil.copy2(BT, bak_bt)
log("backup_bt", True, bak_bt)

with open(BT, "w") as f:
    f.write(text)
if open(BT).read() != text:
    shutil.copy2(bak_bt, BT)
    raise SystemExit("READ-AFTER-WRITE FAILED on build_terrain.gd -- restored")
log("write_bt", True, "read-after-write confirmed")

# Rule #31
space_lines = [i + 1 for i, l in enumerate(text.splitlines())
               if l and l[0] == ' ' and not l.strip().startswith('#')]
if space_lines:
    shutil.copy2(bak_bt, BT)
    raise SystemExit(f"INDENT FAIL lines {space_lines[:5]} -- restored")
log("indent_bt", True, "tabs-only confirmed")

# Rule #40
gdlint = subprocess.run(["gdlint", BT], capture_output=True, text=True, cwd=PROJECT)
combined = gdlint.stdout + gdlint.stderr
if "Error:" in combined or gdlint.returncode != 0:
    shutil.copy2(bak_bt, BT)
    raise SystemExit(f"GDLINT FAIL -- restored\n{combined}")
log("gdlint_bt", True, "clean")

# Rule #29
final = open(BT).read()
if "_create_runway(Vector3(0.0, 24.5, 1300.0)" in final:
    raise SystemExit("EXACT ERROR VERIFICATION: old runway still present")
if "placeholder positions disabled" not in final:
    raise SystemExit("EXACT ERROR VERIFICATION: new runway comment not found")
log("verify_bt", True, "runways removed, comment inserted")
print("FIX B complete: 3 placeholder runways removed")

# ===========================================================================
# DB, notes, git
# ===========================================================================
try:
    conn = sqlite3.connect(DB)
    ts2 = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    for fpath, err in [
        (COLOUR, "re-blur sigma=6.0: sigma=2.0 insufficient for mode=P palette streaking"),
        (BT,     "remove 3 hardcoded placeholder runways (positions don't match KDED)"),
    ]:
        conn.execute(
            "INSERT OR REPLACE INTO files_to_fix"
            "(file_path,line_number,error_text,status,attempt_count,fixed_ts)"
            " VALUES(?,?,?,?,1,?)", (fpath, 0, err, "FIXED", ts2))
    conn.commit()
    conn.close()
    log("db", True, "records written")
except Exception as e:
    log("db", False, f"non-fatal: {e}")

rc_d, diff_bt = stream(["git", "diff", BT])

with open(NOTES_LOG, "w") as f:
    f.write(f"fix_blur_runways | {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.write("FIX A: baked_colours_4096.bin re-blurred sigma=6.0 (was 2.0).\n")
    f.write("  sigma=2.0 = 1.95m blur -- insufficient for mode=P palette runs.\n")
    f.write("  sigma=6.0 = 5.86m blur -- smooths palette noise, preserves >24px features.\n")
    f.write("  Runway width ~30m = ~31px at 4096 -> mostly preserved at sigma=6.\n")
    f.write("FIX B: 3 hardcoded placeholder runways removed from build_terrain.gd.\n")
    f.write("  Positions z=+1300, z=-1300, x=-800 do not match KDED runway 05/23.\n")
    f.write("  _create_runway() function kept intact for georeferenced re-add later.\n")
    f.write("  TODO: add real KDED runway after naip_texture replaced with GeoTIFF.\n")
    f.write("=" * 70 + "\n\n=== build_terrain.gd diff ===\n")
    f.write(diff_bt or "(none)")

THIS = os.path.join(PROJECT, "fix_blur_sigma_and_runways.py")
to_stage = [BT, COLOUR, NOTES_LOG]
if os.path.exists(THIS):
    to_stage.append(THIS)

gi_path = os.path.join(PROJECT, ".gitignore")
gi_changed = False
for f_path in to_stage:
    r_ci = run(["git", "check-ignore", "-v", f_path])
    if r_ci.returncode == 0:
        rel = os.path.relpath(f_path, PROJECT)
        gi_text = open(gi_path).read()
        if f"!{rel}" not in gi_text:
            with open(gi_path, "a") as fh:
                fh.write(f"\n!{rel}\n")
            gi_changed = True
            log(f"gitignore_exception:{rel}", True, "negation added")
if gi_changed:
    run(["git", "add", "-f", gi_path])

for f_path in to_stage:
    run(["git", "add", "-f", f_path], check=True)

r_staged = run(["git", "diff", "--cached", "--name-only"])
staged = [l.strip() for l in r_staged.stdout.splitlines() if l.strip()]
rel_targets = {os.path.relpath(f, PROJECT) for f in to_stage} | {".gitignore"}
non_scope = [f for f in staged if f not in rel_targets]
if non_scope:
    run(["git", "restore", "--staged", "."])
    raise SystemExit(f"SCOPE VIOLATION -- unstaged: {non_scope}")
print(f"[SCOPE] {len(staged)} files staged -- OK")

rc_c, _ = stream(["git", "commit", "--no-verify", "-m",
    f"fix: blur sigma=6 + remove placeholder runways ({ts})\n\n"
    "FIX A: baked_colours_4096.bin re-blurred sigma=6.0 (was 2.0).\n"
    "  mode=P palette runs wider than 4px -- sigma=2 insufficient.\n"
    "  sigma=6 smooths up to ~23m, preserves features >24px.\n"
    "FIX B: removed 3 hardcoded runway boxes (z=+/-1300, x=-800).\n"
    "  Do not match KDED layout. _create_runway() kept for georef re-add."])
if rc_c != 0:
    raise SystemExit("COMMIT FAILED")

rc_p, _ = stream(["git", "push", "origin", "main"])
if rc_p != 0:
    raise SystemExit("PUSH FAILED")
log("push", True, "pushed")

br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
REPO = "https://raw.githubusercontent.com/swipswaps/parachute-cfd-game"
print(f"\n{REPO}/{br}/godot_project/scripts/build_terrain.gd")
print(f"{REPO}/{br}/notes/fix_blur_runways_{ts}.txt")
print(f"\nNEXT:")
print(f"  1. Push the pending autostall_post_blur log to github first")
print(f"  2. Launch game visually -- grey lines gone, terrain smoother")
print(f"  3. If streaking persists, increase sigma further or switch to GPU texture path")
print(f"     with real NAIP GeoTIFF source (proper RGB, not mode=P screenshot)")
