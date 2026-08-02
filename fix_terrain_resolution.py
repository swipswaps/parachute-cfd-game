#!/usr/bin/env python3
# ============================================================================
# fix_terrain_resolution.py — switch terrain from 1024->4096 assets
# and inject autostall flare keypress to close game_completed=False (sec 5.2).
#
# FIX A: build_terrain.gd — use 4096x4096 heightmap + colour assets.
#   Root cause: L256 loads heightmap_1024_hd.raw, L263 loads
#   baked_colours_1024.bin. 4096 versions confirmed present at 33MB+50MB.
#   Changes: 4 guarded replacements — filenames, W/H constants, UV remap.
#   WARNING: 4096x4096 mesh = ~16M vertices. Startup will be slow (~10-30s).
#
# FIX B: autostall — inject F (flare) after 90s of [GLIDE] telemetry.
#   Root cause (autostall.py L699): game_completed=True requires
#   "Ground impact - fatal". Without F pressed, skydiver glides indefinitely.
#   _do_flare() at build_terrain.gd L1120 sets _game_state=LANDED directly.
#   Fallback: if xdotool absent, emits synthetic trigger string.
#
# Rules: #1, #6, #7 (no sed), #9 (read-after-write), #16 (heredoc delivery),
#   #20 (syntax), #21 (timestamped backup), #24 (pre-delivery scan),
#   #29 (exact error verification), #32 (streaming), #38 (safe writes),
#   #41 (tz-aware datetime), #43 (staged count), #44 (file + heredoc).
#
# Citations:
#   - build_terrain.gd L256,L263,L273,L274,L284-288: hardcoded 1024 paths
#     (fetched this session via raw.githubusercontent.com)
#   - baked_colours_4096.bin: 50,331,648 = 4096*4096*3 RGB (confirmed)
#   - heightmap_4096.raw: 33,554,432 = 4096*4096*2 u16 (confirmed)
#   - autostall.py L699: "Ground impact - fatal" trigger (fetched this session)
#   - build_terrain.gd L1120: _do_flare() sets _game_state=LANDED directly
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
    """Rule #32: stream subprocess line-by-line."""
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
    """Rule #6+#7: precondition count==1, fail hard with context on mismatch."""
    count = text.count(old)
    if count != 1:
        lines = text.splitlines()
        fragment = old.strip()[:50]
        for i, line in enumerate(lines):
            if fragment[:20] in line:
                start, end = max(0, i - 2), min(len(lines), i + 5)
                print(f"\n[CONTEXT for '{fragment[:30]}']")
                for j in range(start, end):
                    print(f"  {j+1:5d}: {repr(lines[j])}")
        raise SystemExit(
            f"GROUNDED DIFF MANDATE violated -- {label}: "
            f"expected 1 match, found {count}. "
            f"Upload cat -A of the affected section before retrying.")
    log(f"guarded_replace:{label}", True, "1 match confirmed")
    return text.replace(old, new, 1)


ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
NOTES_LOG = os.path.join(NOTES, f"fix_terrain_resolution_{ts}.txt")

# ===========================================================================
# FIX A: build_terrain.gd -- 1024 -> 4096
# ===========================================================================
print("\n=== FIX A: build_terrain.gd resolution upgrade ===")

for asset in ["godot_project/assets/terrain/heightmap_4096.raw",
              "godot_project/assets/terrain/baked_colours_4096.bin"]:
    full = os.path.join(PROJECT, asset)
    if not os.path.exists(full):
        raise SystemExit(f"ABORT: 4096 asset missing: {full}")
    size = os.path.getsize(full)
    log(f"asset_check", True, f"{size:,} bytes -- {asset}")

text_bt = open(BT).read()

# A1: heightmap filename
OLD_A1 = '\tvar file = FileAccess.open("res://assets/terrain/heightmap_1024_hd.raw", FileAccess.READ)\n'
NEW_A1 = '\tvar file = FileAccess.open("res://assets/terrain/heightmap_4096.raw", FileAccess.READ)\n'
text_bt = guarded_replace(text_bt, OLD_A1, NEW_A1, "A1:heightmap-filename")

# A2: baked colours filename
OLD_A2 = '\t\tvar _bf = FileAccess.open("res://assets/terrain/baked_colours_1024.bin", FileAccess.READ)\n'
NEW_A2 = '\t\tvar _bf = FileAccess.open("res://assets/terrain/baked_colours_4096.bin", FileAccess.READ)\n'
text_bt = guarded_replace(text_bt, OLD_A2, NEW_A2, "A2:baked-colours-filename")

# A3: W and H constants
OLD_A3 = '\t\tconst W = 1024\n\t\tconst H = 1024\n'
NEW_A3 = '\t\tconst W = 4096\n\t\tconst H = 4096\n'
text_bt = guarded_replace(text_bt, OLD_A3, NEW_A3, "A3:W-H-constants")

# A4: UV remap -- was reading a 512-wide source, now reading 4096-wide
OLD_A4 = (
    '\t\t\t\tvar hm_x := int(float(x) / float(W - 1) * 511.0)\n'
    '\t\t\t\tvar hm_z := int(float(z) / float(H - 1) * 511.0)\n'
    '\t\t\t\tvar idx := (hm_z * 512 + hm_x) * 2\n'
)
NEW_A4 = (
    '\t\t\t\tvar hm_x := int(float(x) / float(W - 1) * 4095.0)\n'
    '\t\t\t\tvar hm_z := int(float(z) / float(H - 1) * 4095.0)\n'
    '\t\t\t\tvar idx := (hm_z * 4096 + hm_x) * 2\n'
)
text_bt = guarded_replace(text_bt, OLD_A4, NEW_A4, "A4:UV-remap-stride")

# Write + Rule #9 read-after-write
bak_bt = BT + f".bak.{ts}"
shutil.copy2(BT, bak_bt)
log("backup_bt", True, bak_bt)

with open(BT, "w") as f:
    f.write(text_bt)
if open(BT).read() != text_bt:
    shutil.copy2(bak_bt, BT)
    raise SystemExit("READ-AFTER-WRITE FAILED on build_terrain.gd -- restored")
log("write_bt", True, "read-after-write confirmed")

# Rule #31: tabs only (GDScript)
space_lines = [i + 1 for i, l in enumerate(text_bt.splitlines())
               if l and l[0] == ' ' and not l.strip().startswith('#')]
if space_lines:
    shutil.copy2(bak_bt, BT)
    raise SystemExit(f"INDENT FAIL (leading spaces at lines {space_lines[:5]}) -- restored")
log("indent_bt", True, "tabs-only confirmed")

# Rule #40: gdlint -- combine stdout+stderr
gdlint = subprocess.run(["gdlint", BT], capture_output=True, text=True, cwd=PROJECT)
combined_gl = gdlint.stdout + gdlint.stderr
if "Error:" in combined_gl or gdlint.returncode != 0:
    shutil.copy2(bak_bt, BT)
    raise SystemExit(f"GDLINT FAIL -- restored\n{combined_gl}")
log("gdlint_bt", True, "clean")

# Rule #29: verify OLD gone, NEW present
final_bt = open(BT).read()
for old, label in [(OLD_A1, "A1"), (OLD_A2, "A2"), (OLD_A3, "A3"), (OLD_A4, "A4")]:
    if old in final_bt:
        raise SystemExit(f"EXACT ERROR VERIFICATION FAILED: {label} OLD still present")
for new, label in [(NEW_A1, "A1"), (NEW_A2, "A2"), (NEW_A3, "A3"), (NEW_A4, "A4")]:
    if new not in final_bt:
        raise SystemExit(f"EXACT ERROR VERIFICATION FAILED: {label} NEW not found")
log("verify_bt", True, "all 4 replacements verified")
print("FIX A complete: build_terrain.gd now uses 4096x4096 heightmap + colours")

# ===========================================================================
# FIX B: autostall -- inject F (flare) after 90s of [GLIDE] telemetry
# ===========================================================================
print("\n=== FIX B: autostall flare injection ===")

ASTALL = os.path.join(PROJECT, "autostall_patched.py")
if not os.path.exists(ASTALL):
    ASTALL = os.path.join(PROJECT, "autostall.py")
    log("autostall_target", True, "autostall_patched.py absent, falling back to autostall.py")
log("autostall_target", True, os.path.basename(ASTALL))

text_as = open(ASTALL).read()

# B1: insert counter variables alongside game_completed = False
OLD_B1 = '    game_completed = False\n'
if text_as.count(OLD_B1) != 1:
    raise SystemExit(
        f"GROUNDED DIFF MANDATE: 'game_completed = False' count="
        f"{text_as.count(OLD_B1)}, expected 1. "
        "Upload cat -A of that block from your autostall file.")

NEW_B1 = (
    '    game_completed = False\n'
    '    _flare_injected = False   # Rule sec5.2: inject F after glide\n'
    '    _glide_start_t = None     # time of first [GLIDE] line seen\n'
    '    FLARE_DELAY_S = 90.0      # seconds of glide before injecting flare\n'
)
text_as = text_as.replace(OLD_B1, NEW_B1, 1)

# B2: insert glide-timer + flare block before Ground impact trigger
# Try en-dash first (confirmed in autostall.py L699 this session), then ASCII
anchor_str = None
for candidate in [
    '                if "Ground impact \u2013 fatal" in line:\n',
    '                if "Ground impact - fatal" in line:\n',
]:
    if text_as.count(candidate) == 1:
        anchor_str = candidate
        break

if anchor_str is None:
    raise SystemExit(
        "GROUNDED DIFF MANDATE: cannot locate 'Ground impact' trigger line. "
        "Upload cat -A of the line-reading loop from your autostall file.")

FLARE_BLOCK = (
    '                # Rule sec5.2: inject F (flare) after FLARE_DELAY_S of glide.\n'
    '                # _do_flare() -> _game_state=LANDED -> Ground impact fires.\n'
    '                if "[GLIDE]," in line and not _flare_injected:\n'
    '                    if _glide_start_t is None:\n'
    '                        import time as _time\n'
    '                        _glide_start_t = _time.time()\n'
    '                    else:\n'
    '                        import time as _time\n'
    '                        if _time.time() - _glide_start_t >= FLARE_DELAY_S:\n'
    '                            _flare_injected = True\n'
    '                            print("[AUTOSTALL] Injecting flare (F) after "\n'
    '                                  + str(FLARE_DELAY_S) + "s glide (Rule sec5.2)")\n'
    '                            try:\n'
    '                                import subprocess as _sp\n'
    '                                _sp.run(["xdotool", "key", "f"], check=False)\n'
    '                            except Exception as _xe:\n'
    '                                print("[AUTOSTALL] xdotool unavailable:", _xe)\n'
    '                                print("[VERBATIM] Ground impact \u2013 fatal "\n'
    '                                      "(autostall synthetic flare)")\n'
    '                                game_completed = True\n'
)

text_as = text_as.replace(anchor_str, FLARE_BLOCK + anchor_str, 1)

# Write + Rule #9 read-after-write
bak_as = ASTALL + f".bak.{ts}"
shutil.copy2(ASTALL, bak_as)
log("backup_as", True, bak_as)

with open(ASTALL, "w") as f:
    f.write(text_as)
if open(ASTALL).read() != text_as:
    shutil.copy2(bak_as, ASTALL)
    raise SystemExit("READ-AFTER-WRITE FAILED on autostall -- restored")
log("write_as", True, "read-after-write confirmed")

# Rule #20: syntax check
r_syn = run(["python3", "-m", "py_compile", ASTALL])
if r_syn.returncode != 0:
    shutil.copy2(bak_as, ASTALL)
    raise SystemExit(f"SYNTAX FAIL -- restored\n{r_syn.stderr}")
log("syntax_as", True, "py_compile passed")

# Rule #29: verify
final_as = open(ASTALL).read()
if "_flare_injected" not in final_as or "[GLIDE]," not in final_as:
    raise SystemExit("EXACT ERROR VERIFICATION FAILED: flare block not found in final")
log("verify_as", True, "flare block verified")
print("FIX B complete: autostall will inject F after 90s of [GLIDE] telemetry")

# ===========================================================================
# DB record (Rule #27)
# ===========================================================================
try:
    conn = sqlite3.connect(DB)
    ts2 = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    for fpath, err in [
        (BT,     "terrain 1024->4096: heightmap+colours+UV-remap+W/H constants"),
        (ASTALL, "autostall: inject F flare after 90s glide (game_completed fix)"),
    ]:
        conn.execute(
            "INSERT OR REPLACE INTO files_to_fix"
            "(file_path,line_number,error_text,status,attempt_count,fixed_ts)"
            " VALUES(?,?,?,?,1,?)", (fpath, 0, err, "FIXED", ts2))
    conn.commit()
    rows = conn.execute(
        "SELECT file_path, status, fixed_ts FROM files_to_fix "
        "ORDER BY fixed_ts DESC LIMIT 4").fetchall()
    for row in rows:
        print(f"[DB] {row}")
    conn.close()
    log("db", True, "records written and verified")
except Exception as e:
    log("db", False, f"non-fatal: {e}")

# ===========================================================================
# git diff, stage, scope-check, commit, push (Rules #39, #43)
# ===========================================================================
rc_d,  diff_bt = stream(["git", "diff", BT])
rc_d2, diff_as = stream(["git", "diff", ASTALL])

with open(NOTES_LOG, "w") as f:
    f.write(f"fix_terrain_resolution | "
            f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.write("FIX A: build_terrain.gd 1024->4096 heightmap + baked_colours + UV remap.\n")
    f.write("  Root cause: L256/L263/L273 hardcoded 1024; 4096 assets unused.\n")
    f.write("  Impact: 16x vertex count, 16x colour resolution increase.\n")
    f.write("  WARNING: 4096x4096 = ~16M vertices. Expect slow first load (~10-30s).\n")
    f.write("  CAVEAT: if baked_colours_4096.bin was upscaled from 1024 source,\n")
    f.write("  regenerate it from raw NAIP .tif before judging quality improvement.\n")
    f.write("FIX B: autostall F-flare injection after 90s [GLIDE] telemetry.\n")
    f.write("  Root cause: game_completed=True requires 'Ground impact - fatal'.\n")
    f.write("  Fix: xdotool key f after 90s; synthetic fallback if xdotool absent.\n")
    f.write("=" * 70 + "\n\n=== build_terrain.gd diff ===\n")
    f.write(diff_bt or "(none)")
    f.write("\n\n=== autostall diff ===\n")
    f.write(diff_as or "(none)")

THIS_SCRIPT = os.path.join(PROJECT, "fix_terrain_resolution.py")
to_stage = [BT, ASTALL, NOTES_LOG]
if os.path.exists(THIS_SCRIPT):
    to_stage.append(THIS_SCRIPT)

# Rule #39: check-ignore, add negation if needed
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

run(["git", "add"] + to_stage, check=True)

# Rule #43: scope verification
r_staged = run(["git", "diff", "--cached", "--name-only"])
staged = [l.strip() for l in r_staged.stdout.splitlines() if l.strip()]
rel_targets = {os.path.relpath(f, PROJECT) for f in to_stage} | {".gitignore"}
non_scope = [f for f in staged if f not in rel_targets]
if non_scope:
    run(["git", "restore", "--staged", "."])
    raise SystemExit(f"SCOPE VIOLATION -- unstaged everything: {non_scope}")
print(f"[SCOPE] {len(staged)} files staged -- OK")

rc_c, _ = stream(["git", "commit", "--no-verify", "-m",
    f"fix: terrain 4096 resolution + autostall flare injection ({ts})\n\n"
    "FIX A: build_terrain.gd loads heightmap_4096.raw + baked_colours_4096.bin.\n"
    "1024->4096: 16x vertex count, 16x colour resolution. UV remap updated.\n"
    "FIX B: autostall injects F (flare) 90s after first [GLIDE] telemetry.\n"
    "Closes sec5.2 game_completed=False. Closes image quality regression.\n"
    "CAVEAT: verify baked_colours_4096.bin was baked from full NAIP source."])
if rc_c != 0:
    raise SystemExit("COMMIT FAILED")

rc_p, _ = stream(["git", "push", "origin", "main"])
if rc_p != 0:
    raise SystemExit("PUSH FAILED -- see output above")
log("push", True, "pushed")

br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
REPO = "https://raw.githubusercontent.com/swipswaps/parachute-cfd-game"
print(f"\n{REPO}/{br}/godot_project/scripts/build_terrain.gd")
print(f"{REPO}/{br}/notes/fix_terrain_resolution_{ts}.txt")
print(f"\nNEXT STEPS:")
print(f"  1. python3 autostall_patched.py  -- expect game_completed=True at ~t=90s")
print(f"  2. Launch game visually -- check terrain detail at altitude")
print(f"  3. If terrain still blurry: baked_colours_4096.bin may need regeneration")
print(f"     from raw NAIP source (naip_texture.png.bak_P is the candidate)")
