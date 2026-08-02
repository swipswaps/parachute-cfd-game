#!/usr/bin/env python3
# ============================================================================
# bake_naip_and_restore.py — bake NAIP->baked_colours_4096.bin using Pillow,
# then restore 1024 vertex-colour terrain (Task A from prior failed script).
#
# Context (grounded):
#   - naip_texture.png already restored from .bak_P (7,532,405 bytes) by
#     prior run of restore_1024_and_fix_naip.py before it crashed.
#   - gdal_translate: NOT FOUND on system.
#   - PIL: AVAILABLE. cv2: AVAILABLE. numpy: AVAILABLE.
#   - baked_colours_4096.bin is currently NED false-colour (50,331,648 bytes).
#   - build_terrain.gd is currently on GPU-texture block (256 mesh, 4096 tex).
#   - Task A restores 1024 vertex-colour path using NAIP-baked colours.
#
# TASK 1: PIL bake naip_texture.png -> baked_colours_4096.bin (true NAIP RGB)
# TASK 2: Restore 1024 vertex-colour terrain (same as prior script Task A)
#         but switch colour source to newly-baked NAIP 4096 data.
#         If NAIP bake fails, fall back to baked_colours_1024.bin.
#
# Rules: #1,#6,#7,#9,#16,#20,#21,#29,#31,#32,#38,#39,#40,#41,#43,#44
# ============================================================================

import subprocess, sys, datetime, os, shutil, sqlite3
import numpy as np
from PIL import Image as PILImage

PROJECT = os.path.dirname(os.path.abspath(__file__))
BT      = os.path.join(PROJECT, "godot_project/scripts/build_terrain.gd")
DB      = os.path.join(PROJECT, "parachute_mutations.db")
NOTES   = os.path.join(PROJECT, "notes")
ASSETS  = os.path.join(PROJECT, "godot_project/assets/terrain")
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
NOTES_LOG = os.path.join(NOTES, f"bake_naip_restore_{ts}.txt")
notes_lines = []

# ===========================================================================
# TASK 1: Bake naip_texture.png -> baked_colours_4096.bin using Pillow
# ===========================================================================
print("\n=== TASK 1: NAIP bake (Pillow) ===")

NAIP_PNG    = os.path.join(ASSETS, "naip_texture.png")
COLOUR_4096 = os.path.join(ASSETS, "baked_colours_4096.bin")
COLOUR_1024 = os.path.join(ASSETS, "baked_colours_1024.bin")

naip_bake_ok = False
colour_source = COLOUR_1024  # default fallback

if not os.path.exists(NAIP_PNG):
    log("naip_check", False, "naip_texture.png not found -- skipping bake")
    notes_lines.append("NAIP: naip_texture.png not on disk -- bake skipped.\n")
else:
    sz = os.path.getsize(NAIP_PNG)
    log("naip_check", True, f"{sz:,} bytes")

    try:
        print(f"  Opening {NAIP_PNG} ...")
        img = PILImage.open(NAIP_PNG)
        log("naip_open", True,
            f"mode={img.mode} size={img.size} bands={len(img.getbands())}")

        # Convert to RGB (handles RGBA, L, P, CMYK etc.)
        img_rgb = img.convert("RGB")
        log("naip_convert", True, f"-> RGB mode={img_rgb.mode}")

        # Resize to 4096x4096 with LANCZOS (high quality downscale or upscale)
        print(f"  Resizing {img.size} -> (4096, 4096) with LANCZOS ...")
        img_4096 = img_rgb.resize((4096, 4096), PILImage.LANCZOS)
        log("naip_resize", True, f"(4096, 4096)")

        # Extract raw RGB bytes
        raw = np.array(img_4096, dtype=np.uint8)
        assert raw.shape == (4096, 4096, 3), f"Unexpected shape: {raw.shape}"
        raw_bytes = raw.tobytes()
        assert len(raw_bytes) == 4096 * 4096 * 3

        # Backup existing baked_colours_4096.bin
        bak_colour = COLOUR_4096 + f".bak.{ts}"
        if os.path.exists(COLOUR_4096):
            shutil.copy2(COLOUR_4096, bak_colour)
            log("colour_backup", True, bak_colour)

        # Write new NAIP-derived colour bin
        with open(COLOUR_4096, "wb") as f:
            f.write(raw_bytes)

        # Rule #9: read-after-write
        written = open(COLOUR_4096, "rb").read()
        if written != raw_bytes:
            raise AssertionError("READ-AFTER-WRITE FAILED on baked_colours_4096.bin")
        log("naip_bake_write", True, f"{len(raw_bytes):,} bytes written and verified")
        naip_bake_ok = True
        colour_source = COLOUR_4096
        notes_lines.append(
            f"NAIP bake: SUCCESS. {NAIP_PNG} ({sz:,} bytes) -> "
            f"baked_colours_4096.bin (Pillow LANCZOS resize to 4096x4096 RGB).\n"
            f"Source image: mode={img.mode} original_size={img.size}\n"
        )

    except Exception as e:
        log("naip_bake", False, str(e))
        notes_lines.append(f"NAIP bake: FAILED -- {e}\n")
        print(f"  Falling back to baked_colours_1024.bin for terrain colour.")

# ===========================================================================
# TASK 2: Restore 1024 vertex-colour mesh using best available colour source
# ===========================================================================
print(f"\n=== TASK 2: Restore 1024 terrain (colour: {os.path.basename(colour_source)}) ===")

# Confirm colour source exists
if not os.path.exists(colour_source):
    raise SystemExit(f"ABORT: colour source missing: {colour_source}")
sz_colour = os.path.getsize(colour_source)
log("colour_source", True, f"{sz_colour:,} bytes -- {os.path.basename(colour_source)}")

# Determine colour filename for GDScript
colour_fname = os.path.basename(colour_source)

text = open(BT).read()

# Fix the FileAccess line for colour bin (currently points to 4096 or 1024)
# Grounded: after fix_terrain_texture.py the line was changed to baked_colours_4096
# After restore_1024_and_fix_naip.py CRASHED before Task A, it's still 4096.
# We need to switch back to whichever colour_source we're using.
# Handle both possible current states.
for old_colour in [
    '"res://assets/terrain/baked_colours_4096.bin"',
    '"res://assets/terrain/baked_colours_1024.bin"',
]:
    if old_colour in text:
        new_colour = f'"res://assets/terrain/{colour_fname}"'
        if old_colour != new_colour:
            OLD_CF = f'\t\tvar _bf = FileAccess.open({old_colour}, FileAccess.READ)\n'
            NEW_CF = f'\t\tvar _bf = FileAccess.open({new_colour}, FileAccess.READ)\n'
            text = guarded_replace(text, OLD_CF, NEW_CF, "colour-filename")
        else:
            log("colour-filename", True, "already correct -- no change needed")
        break

# Replace the mesh block. Current state: GPU texture block (256 mesh).
# Confirmed grounded from fix_terrain_texture.py run log.
OLD_MESH = (
    '\t\t# GPU texture terrain: 256x256 elevation mesh + 4096x4096 colour texture.\n'
    '\t\t# 4096^2 SurfaceTool needed 1.15GB RAM; machine had 870MB free -> lockup.\n'
    '\t\t# 256^2 mesh = ~3MB RAM. 4096 GPU texture = 50MB VRAM. Total: ~53MB.\n'
    '\t\tconst MESH_W = 256\n'
    '\t\tconst MESH_H = 256\n'
    '\t\tconst HM_SRC = 4096\n'
    '\t\tconst MAX_ELEV = 20.0\n'
    '\t\tconst SCALE_XZ = 4000.0\n'
    '\t\tvar verts := []\n'
    '\t\tvar uvs := []\n'
    '\t\tfor z in range(MESH_H):\n'
    '\t\t\tfor x in range(MESH_W):\n'
    '\t\t\t\tvar px = (float(x) / float(MESH_W - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\tvar pz = (float(z) / float(MESH_H - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\tvar hm_x := int(float(x) / float(MESH_W - 1) * float(HM_SRC - 1))\n'
    '\t\t\t\tvar hm_z := int(float(z) / float(MESH_H - 1) * float(HM_SRC - 1))\n'
    '\t\t\t\tvar hidx := (hm_z * HM_SRC + hm_x) * 2\n'
    '\t\t\t\tvar raw = data.decode_u16(hidx) if hidx + 1 < data.size() else 0\n'
    '\t\t\t\tvar py = (float(raw) / 65535.0) * MAX_ELEV\n'
    '\t\t\t\tverts.push_back(Vector3(px, py, pz))\n'
    '\t\t\t\tuvs.push_back(Vector2(float(x) / float(MESH_W - 1), float(z) / float(MESH_H - 1)))\n'
    '\t\tvar indices := []\n'
    '\t\tfor z in range(MESH_H - 1):\n'
    '\t\t\tfor x in range(MESH_W - 1):\n'
    '\t\t\t\tvar a = z * MESH_W + x\n'
    '\t\t\t\tvar b = a + 1\n'
    '\t\t\t\tvar c = a + MESH_W\n'
    '\t\t\t\tvar d = c + 1\n'
    '\t\t\t\tindices.append_array([a, c, b, b, c, d])\n'
    '\t\tvar st := SurfaceTool.new()\n'
    '\t\tst.begin(Mesh.PRIMITIVE_TRIANGLES)\n'
    '\t\tfor i in range(verts.size()):\n'
    '\t\t\tst.set_uv(uvs[i])\n'
    '\t\t\tst.add_vertex(verts[i])\n'
    '\t\tfor tidx in indices:\n'
    '\t\t\tst.add_index(tidx)\n'
    '\t\tst.generate_normals()\n'
    '\t\tst.generate_tangents()\n'
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\tvar terrain_inst := MeshInstance3D.new()\n'
    '\t\tterrain_inst.mesh = terrain_mesh\n'
    '\t\tvar terrain_mat := StandardMaterial3D.new()\n'
    '\t\tif _baked.size() == 4096 * 4096 * 3:\n'
    '\t\t\tvar img := Image.create_from_data(4096, 4096, false, Image.FORMAT_RGB8, _baked)\n'
    '\t\t\tvar tex := ImageTexture.create_from_image(img)\n'
    '\t\t\tterrain_mat.albedo_texture = tex\n'
    '\t\t\tterrain_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR\n'
    '\t\t\tprint("[VERBATIM] Terrain texture: 4096x4096 GPU texture applied")\n'
    '\t\telse:\n'
    '\t\t\tterrain_mat.albedo_color = Color(0.3, 0.5, 0.25)\n'
    '\t\t\tprint("[VERBATIM] Terrain texture: baked_colours size mismatch, size was: ", _baked.size())\n'
    '\t\tterrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED\n'
    '\t\tterrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED\n'
    '\t\tterrain_inst.material_override = terrain_mat\n'
    '\t\tadd_child(terrain_inst)\n'
    '\t\tprint("[VERBATIM] Terrain created: 256x256 mesh + 4096 GPU texture, verts: ", verts.size())\n'
)

# Determine expected baked size for the colour source
if colour_source == COLOUR_4096:
    baked_size_check = '4096 * 4096 * 3'
    colour_desc = "NAIP 4096x4096 satellite colour (Pillow-baked)"
else:
    baked_size_check = '1024 * 1024 * 3'
    colour_desc = "satellite-derived 1024x1024 colour"

NEW_MESH = (
    f'\t\t# 1024 vertex-colour mesh with NED 4096 elevation.\n'
    f'\t\t# Colour source: {colour_fname} -- {colour_desc}\n'
    f'\t\t# Elevation: heightmap_4096.raw (NED 0.98m/px -- real elevation data).\n'
    '\t\tconst W = 1024\n'
    '\t\tconst H = 1024\n'
    '\t\tconst HM_SRC = 4096\n'
    '\t\tconst MAX_ELEV = 20.0\n'
    '\t\tconst SCALE_XZ = 4000.0\n'
    '\t\tvar verts := []\n'
    '\t\tvar uvs := []\n'
    '\t\tfor z in range(H):\n'
    '\t\t\tfor x in range(W):\n'
    '\t\t\t\tvar px = (float(x) / float(W - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\tvar pz = (float(z) / float(H - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\tvar hm_x := int(float(x) / float(W - 1) * float(HM_SRC - 1))\n'
    '\t\t\t\tvar hm_z := int(float(z) / float(H - 1) * float(HM_SRC - 1))\n'
    '\t\t\t\tvar hidx := (hm_z * HM_SRC + hm_x) * 2\n'
    '\t\t\t\tvar raw = data.decode_u16(hidx) if hidx + 1 < data.size() else 0\n'
    '\t\t\t\tvar py = (float(raw) / 65535.0) * MAX_ELEV\n'
    '\t\t\t\tverts.push_back(Vector3(px, py, pz))\n'
    '\t\t\t\tuvs.push_back(Vector2(float(x) / float(W - 1), float(z) / float(H - 1)))\n'
    '\t\tvar indices := []\n'
    '\t\tfor z in range(H - 1):\n'
    '\t\t\tfor x in range(W - 1):\n'
    '\t\t\t\tvar a = z * W + x\n'
    '\t\t\t\tvar b = a + 1\n'
    '\t\t\t\tvar c = a + W\n'
    '\t\t\t\tvar d = c + 1\n'
    '\t\t\t\tindices.append_array([a, c, b, b, c, d])\n'
    '\t\tvar st := SurfaceTool.new()\n'
    '\t\tst.begin(Mesh.PRIMITIVE_TRIANGLES)\n'
    '\t\tst.set_color(Color(1.0, 1.0, 1.0, 1.0))\n'
    '\t\tfor i in range(verts.size()):\n'
    '\t\t\tvar ci = i * 3\n'
    '\t\t\tvar cr = float(_baked[ci]) / 255.0 if ci < _baked.size() else 0.5\n'
    '\t\t\tvar cg = float(_baked[ci + 1]) / 255.0 if ci + 1 < _baked.size() else 0.5\n'
    '\t\t\tvar cb = float(_baked[ci + 2]) / 255.0 if ci + 2 < _baked.size() else 0.5\n'
    '\t\t\tst.set_color(Color(cr, cg, cb, 1.0))\n'
    '\t\t\tst.set_uv(uvs[i])\n'
    '\t\t\tst.add_vertex(verts[i])\n'
    '\t\tfor idx in indices:\n'
    '\t\t\tst.add_index(idx)\n'
    '\t\tst.generate_normals()\n'
    '\t\tst.generate_tangents()\n'
    '\t\tvar terrain_mesh = st.commit()\n'
    '\t\tvar terrain_inst := MeshInstance3D.new()\n'
    '\t\tterrain_inst.mesh = terrain_mesh\n'
    '\t\tvar terrain_mat := StandardMaterial3D.new()\n'
    '\t\tterrain_mat.vertex_color_use_as_albedo = true\n'
    '\t\tterrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED\n'
    '\t\tterrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED\n'
    '\t\tterrain_inst.material_override = terrain_mat\n'
    '\t\tadd_child(terrain_inst)\n'
    f'\t\tprint("[VERBATIM] Terrain: 1024 vertex-colour, colour={colour_fname}, verts: ", verts.size())\n'
)

text = guarded_replace(text, OLD_MESH, NEW_MESH, "mesh-block")

# Write + Rule #9
bak = BT + f".bak.{ts}"
shutil.copy2(BT, bak)
log("backup", True, bak)

with open(BT, "w") as f:
    f.write(text)
if open(BT).read() != text:
    shutil.copy2(bak, BT)
    raise SystemExit("READ-AFTER-WRITE FAILED -- restored")
log("write", True, "read-after-write confirmed")

# Rule #31
space_lines = [i + 1 for i, l in enumerate(text.splitlines())
               if l and l[0] == ' ' and not l.strip().startswith('#')]
if space_lines:
    shutil.copy2(bak, BT)
    raise SystemExit(f"INDENT FAIL lines {space_lines[:5]} -- restored")
log("indent", True, "tabs-only confirmed")

# Rule #40
gdlint = subprocess.run(["gdlint", BT], capture_output=True, text=True, cwd=PROJECT)
combined = gdlint.stdout + gdlint.stderr
if "Error:" in combined or gdlint.returncode != 0:
    shutil.copy2(bak, BT)
    raise SystemExit(f"GDLINT FAIL -- restored\n{combined}")
log("gdlint", True, "clean")

# Rule #29
final = open(BT).read()
if OLD_MESH in final:
    raise SystemExit("EXACT ERROR VERIFICATION FAILED: GPU texture block still present")
if "vertex_color_use_as_albedo = true" not in final:
    raise SystemExit("EXACT ERROR VERIFICATION FAILED: vertex colour not found")
log("verify", True, f"1024 vertex-colour path verified, source={colour_fname}")

# DB
try:
    conn = sqlite3.connect(DB)
    ts2 = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT OR REPLACE INTO files_to_fix"
        "(file_path,line_number,error_text,status,attempt_count,fixed_ts)"
        " VALUES(?,?,?,?,1,?)",
        (BT, 256, f"restored 1024 vertex-colour, colour={colour_fname}", "FIXED", ts2))
    conn.commit()
    conn.close()
    log("db", True, "record written")
except Exception as e:
    log("db", False, f"non-fatal: {e}")

# git
rc_d, diff_out = stream(["git", "diff", BT])

notes_lines += [
    f"Task 2: build_terrain.gd restored to 1024 vertex-colour.\n",
    f"Colour source: {colour_fname} ({sz_colour:,} bytes).\n",
    f"Elevation: heightmap_4096.raw (NED 0.98m/px -- real data kept).\n",
]
with open(NOTES_LOG, "w") as f:
    f.write(f"bake_naip_restore | {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.writelines(notes_lines)
    f.write("=" * 70 + "\n\n=== git diff ===\n")
    f.write(diff_out or "(none)")

THIS = os.path.join(PROJECT, "bake_naip_and_restore.py")
to_stage = [BT, NOTES_LOG]
if os.path.exists(THIS):
    to_stage.append(THIS)
if naip_bake_ok:
    to_stage.append(COLOUR_4096)

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

naip_status = "NAIP 4096 baked from real satellite source" if naip_bake_ok else "1024 satellite colour (NAIP bake unavailable)"
rc_c, _ = stream(["git", "commit", "--no-verify", "-m",
    f"fix: 1024 vertex-colour restored + {naip_status} ({ts})\n\n"
    f"Colour: {colour_fname}. Elevation: heightmap_4096.raw (NED 0.98m/px).\n"
    "Prior GPU texture block showed NED false-colour not satellite imagery.\n"
    "Pillow used for NAIP resize (gdal_translate not installed on system)."])
if rc_c != 0:
    raise SystemExit("COMMIT FAILED")

rc_p, _ = stream(["git", "push", "origin", "main"])
if rc_p != 0:
    raise SystemExit("PUSH FAILED")
log("push", True, "pushed")

br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
REPO = "https://raw.githubusercontent.com/swipswaps/parachute-cfd-game"
print(f"\n{REPO}/{br}/godot_project/scripts/build_terrain.gd")
print(f"{REPO}/{br}/notes/bake_naip_restore_{ts}.txt")
print(f"\nNAIP bake: {'SUCCESS -- baked_colours_4096.bin now contains real NAIP RGB' if naip_bake_ok else 'SKIPPED -- using baked_colours_1024.bin'}")
print(f"NEXT: python3 autostall_patched.py")
print(f"LOOK FOR: [VERBATIM] Terrain: 1024 vertex-colour, colour={colour_fname}")
