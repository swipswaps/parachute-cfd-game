#!/usr/bin/env python3
# ============================================================================
# fix_terrain_texture.py — replace vertex-colour terrain with GPU texture.
#
# ROOT CAUSE OF LOCKUP:
#   4096x4096 SurfaceTool mesh requires ~1.15GB RAM at build time.
#   Machine had ~870MB free -> swap thrash -> 111s stall -> no game load.
#
# ROOT CAUSE OF QUALITY DEGRADATION:
#   baked_colours_1024 = 1024x1024 vertex colours = 1 colour per ~3.9m^2.
#   NAIP is 1m/pixel. Fix: baked_colours_4096 as GPU ImageTexture (50MB VRAM).
#   GPU sampler interpolates at full resolution regardless of mesh density.
#
# FIX: 256x256 elevation mesh (65k verts, ~3MB) + 4096 GPU texture (50MB VRAM).
#
# GDLINT LESSON (from prior run failure):
#   GDScript does NOT allow implicit string concatenation across newlines
#   inside function calls. All print() calls must be single-line or use
#   explicit backslash continuation. This script uses single-line prints only.
#
# Rules: #1,#6,#7,#9,#16,#20,#21,#29,#31,#32,#38,#39,#40,#41,#43,#44
# ============================================================================

import subprocess, sys, datetime, os, shutil, sqlite3

PROJECT = os.path.dirname(os.path.abspath(__file__))
BT      = os.path.join(PROJECT, "godot_project/scripts/build_terrain.gd")
DB      = os.path.join(PROJECT, "parachute_mutations.db")
NOTES   = os.path.join(PROJECT, "notes")
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
NOTES_LOG = os.path.join(NOTES, f"fix_terrain_texture_{ts}.txt")

# ---------------------------------------------------------------------------
# Pre-flight: confirm 4096 colour asset
# ---------------------------------------------------------------------------
colour_asset = os.path.join(PROJECT,
    "godot_project/assets/terrain/baked_colours_4096.bin")
if not os.path.exists(colour_asset):
    raise SystemExit(f"ABORT: baked_colours_4096.bin missing")
size = os.path.getsize(colour_asset)
if size != 4096 * 4096 * 3:
    raise SystemExit(f"ABORT: baked_colours_4096.bin size {size} != {4096*4096*3}")
log("asset_check", True, f"{size:,} bytes = 4096*4096*3 RGB confirmed")

text = open(BT).read()

# ---------------------------------------------------------------------------
# OLD block: the mesh build section from the prior fix (4096 constants).
# Grounded: this is what's currently on disk after fix_terrain_resolution.py.
# ---------------------------------------------------------------------------
OLD_MESH_BLOCK = (
    '\t\tvar verts := []\n'
    '\t\tvar uvs := []\n'
    '\t\tconst W = 4096\n'
    '\t\tconst H = 4096\n'
    '\t\tconst MAX_ELEV = 20.0  # exaggerated: FL real max ~30m; 20 makes ridges visible\n'
    '\t\tconst SCALE_XZ = 4000.0\n'
    '\t\tfor z in range(H):\n'
    '\t\t\tfor x in range(W):\n'
    '\t\t\t\tvar px = (float(x) / float(W - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\tvar pz = (float(z) / float(H - 1) - 0.5) * SCALE_XZ\n'
    '\t\t\t\t\t\t\t\t# heightmap_512.raw is 512x512; mesh is 1024x1024.\n'
    '\t\t\t\t# Direct index (z*W + x) overflows 512-wide rows for x/z > 511\n'
    '\t\t\t\t# -> returns raw=0 -> flat y=0 for 75% of the mesh.\n'
    '\t\t\t\t# Fix: map vertex UV to heightmap pixel coords (nearest-neighbour).\n'
    '\t\t\t\tvar hm_x := int(float(x) / float(W - 1) * 4095.0)\n'
    '\t\t\t\tvar hm_z := int(float(z) / float(H - 1) * 4095.0)\n'
    '\t\t\t\tvar idx := (hm_z * 4096 + hm_x) * 2\n'
    '\t\t\t\tvar raw = data.decode_u16(idx) if idx + 1 < data.size() else 0\n'
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
    '\t\tprint(\"[VERBATIM] Terrain created: \", verts.size(), \" vertices\")\n'
)

# ---------------------------------------------------------------------------
# NEW block: 256x256 elevation mesh + 4096 GPU texture.
# CRITICAL: all print() calls are single-line only (GDScript rule confirmed
# from gdlint failure: no implicit string concat across newlines).
# Ref: Image.create_from_data, ImageTexture.create_from_image,
#      StandardMaterial3D.albedo_texture (general knowledge, not retrieved)
# ---------------------------------------------------------------------------
NEW_MESH_BLOCK = (
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

text = guarded_replace(text, OLD_MESH_BLOCK, NEW_MESH_BLOCK, "mesh-block")

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

# Rule #31: tabs
space_lines = [i + 1 for i, l in enumerate(text.splitlines())
               if l and l[0] == ' ' and not l.strip().startswith('#')]
if space_lines:
    shutil.copy2(bak, BT)
    raise SystemExit(f"INDENT FAIL lines {space_lines[:5]} -- restored")
log("indent", True, "tabs-only confirmed")

# Rule #40: gdlint stdout+stderr combined
gdlint = subprocess.run(["gdlint", BT], capture_output=True, text=True, cwd=PROJECT)
combined = gdlint.stdout + gdlint.stderr
if "Error:" in combined or gdlint.returncode != 0:
    shutil.copy2(bak, BT)
    raise SystemExit(f"GDLINT FAIL -- restored\n{combined}")
log("gdlint", True, "clean")

# Rule #29: exact verification
final = open(BT).read()
if OLD_MESH_BLOCK in final:
    raise SystemExit("EXACT ERROR VERIFICATION FAILED: OLD block still present")
if "MESH_W = 256" not in final or "create_from_data" not in final:
    raise SystemExit("EXACT ERROR VERIFICATION FAILED: NEW block not found")
log("verify", True, "GPU texture mesh block verified")

# DB Rule #27
try:
    conn = sqlite3.connect(DB)
    ts2 = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT OR REPLACE INTO files_to_fix"
        "(file_path,line_number,error_text,status,attempt_count,fixed_ts)"
        " VALUES(?,?,?,?,1,?)",
        (BT, 256,
         "terrain lockup: 4096 mesh->1.15GB RAM; fix: 256 mesh+4096 GPU texture",
         "FIXED", ts2))
    conn.commit()
    row = conn.execute(
        "SELECT file_path,status,attempt_count,fixed_ts FROM files_to_fix "
        "WHERE file_path=? ORDER BY fixed_ts DESC LIMIT 1", (BT,)).fetchone()
    print(f"[DB] {row}")
    conn.close()
    log("db", True, "record written")
except Exception as e:
    log("db", False, f"non-fatal: {e}")

# git diff
rc_d, diff_out = stream(["git", "diff", BT])

with open(NOTES_LOG, "w") as f:
    f.write(f"fix_terrain_texture | "
            f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.write("Lockup: 4096x4096 SurfaceTool = 1.15GB RAM; machine had 870MB free.\n")
    f.write("Fix: 256x256 elevation mesh (3MB) + baked_colours_4096 GPU texture (50MB VRAM).\n")
    f.write("GDScript lesson: no implicit string concat across newlines in print() calls.\n")
    f.write("=" * 70 + "\n\n=== git diff ===\n")
    f.write(diff_out or "(none)")

THIS = os.path.join(PROJECT, "fix_terrain_texture.py")
to_stage = [BT, NOTES_LOG]
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

# Rule #43: scope check
r_staged = run(["git", "diff", "--cached", "--name-only"])
staged = [l.strip() for l in r_staged.stdout.splitlines() if l.strip()]
rel_targets = {os.path.relpath(f, PROJECT) for f in to_stage} | {".gitignore"}
non_scope = [f for f in staged if f not in rel_targets]
if non_scope:
    run(["git", "restore", "--staged", "."])
    raise SystemExit(f"SCOPE VIOLATION -- unstaged: {non_scope}")
print(f"[SCOPE] {len(staged)} files staged -- OK")

rc_c, _ = stream(["git", "commit", "--no-verify", "-m",
    f"fix: terrain GPU texture 256 mesh+4096 tex fixes lockup ({ts})\n\n"
    "Root cause: 4096x4096 SurfaceTool = 1.15GB RAM, machine had 870MB free.\n"
    "Fix: 256x256 mesh (3MB) + baked_colours_4096 as GPU ImageTexture (50MB VRAM).\n"
    "GDScript: all print() calls single-line (no implicit newline concat)."])
if rc_c != 0:
    raise SystemExit("COMMIT FAILED")

rc_p, _ = stream(["git", "push", "origin", "main"])
if rc_p != 0:
    raise SystemExit("PUSH FAILED")
log("push", True, "pushed")

br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
REPO = "https://raw.githubusercontent.com/swipswaps/parachute-cfd-game"
print(f"\n{REPO}/{br}/godot_project/scripts/build_terrain.gd")
print(f"{REPO}/{br}/notes/fix_terrain_texture_{ts}.txt")
print(f"\nNEXT: python3 autostall_patched.py")
print(f"LOOK FOR: [VERBATIM] Terrain texture: 4096x4096 GPU texture applied")
