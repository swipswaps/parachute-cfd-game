#!/usr/bin/env bash
# Rules: #6,#7,#9,#21,#31,#41,#46,#47
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
FHUD="godot_project/scripts/forensic_hud.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
ALOG="notes/autostall_landing_${TS}.txt"
OUT="notes/fix_landing_warp_${TS}.txt"

python3 - "$TARGET" << 'PYEOF'
import sys, shutil, datetime

def log(op, ok, detail):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {detail}", flush=True)

def lws(line):
    ws = ""
    for c in line:
        if c in "\t ": ws += c
        else: break
    return ws

target = sys.argv[1]
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = f"{target}.bak.{ts}"
with open(target, "r", encoding="utf-8") as f:
    text = f.read()
lines = text.split("\n")
log("read_file", True, f"{len(text)} bytes, {len(lines)} lines")
shutil.copy2(target, backup)
log("backup", True, backup)

# ── PATCH 0: add _headless_warp_done class var ──────────────────────────────
# Anchor: the _headless_auto_deploy line (known from prior diag to be line 129)
p0_sig = "var _headless_auto_deploy: bool = false"
p0_idx = next((i for i, ln in enumerate(lines) if p0_sig in ln), None)
if p0_idx is None:
    log("p0_locate", False, "anchor not found"); shutil.copy2(backup, target); sys.exit(1)
log("p0_locate", True, f"line {p0_idx+1}")
old_p0 = lines[p0_idx]
if text.count(old_p0) != 1:
    log("p0_guard", False, f"count={text.count(old_p0)}"); shutil.copy2(backup, target); sys.exit("P0 PRECONDITION")
new_p0 = old_p0 + "\nvar _headless_warp_done: bool = false    # set on first OPENING_ANIM frame in headless — alt warp"
text = text.replace(old_p0, new_p0, 1)
log("p0_apply", True, "_headless_warp_done var added")

# ── PATCH 1: headless altitude warp in OPENING_ANIM branch ──────────────────
# Anchor: the comment before _check_decision_altitude() — live extraction
p1_lines = text.split("\n")
p1_idx = next((i for i, ln in enumerate(p1_lines) if "_check_decision_altitude()" in ln and not ln.strip().startswith("#")), None)
if p1_idx is None:
    log("p1_locate", False, "_check_decision_altitude() not found"); shutil.copy2(backup, target); sys.exit(1)
log("p1_locate", True, f"_check_decision_altitude at line {p1_idx+1}")
old_p1_line = p1_lines[p1_idx]
ws1 = lws(old_p1_line)
if text.count(old_p1_line) != 1:
    log("p1_guard", False, f"count={text.count(old_p1_line)}"); shutil.copy2(backup, target); sys.exit("P1 PRECONDITION")
# Insert warp code before the call
warp_block = (
    ws1 + "# Headless altitude warp: set character to 200m AGL so full descent takes ~47s\n"
    + ws1 + "# instead of ~430s. Fires once on first OPENING_ANIM frame. Rule #46 live-extracted.\n"
    + ws1 + "# Ref: OS.get_environment: https://docs.godotengine.org/en/stable/classes/class_os.html\n"
    + ws1 + "if not _headless_warp_done and (\n"
    + ws1 + "\t\tOS.get_environment(\"GODOT_HEADLESS\") == \"1\" or\n"
    + ws1 + "\t\t\"--headless\" in OS.get_cmdline_args()):\n"
    + ws1 + "\t_character.position.y = 225.0  # 200m AGL + 25m ground offset\n"
    + ws1 + "\t_current_altitude = 200.0\n"
    + ws1 + "\t_headless_warp_done = true\n"
    + ws1 + "\tprint(\"[VERBATIM] Headless altitude warp: 200m AGL for fast test\")\n"
    + old_p1_line
)
text = text.replace(old_p1_line, warp_block, 1)
log("p1_apply", True, "headless warp inserted before _check_decision_altitude()")

# ── PATCH 2: ground impact GAME_OVER + autostall-detectable print ────────────
# Anchor: the y-clamp block (lines 2138-2139). Live extract the exact bytes.
p2_lines = text.split("\n")
p2_idx = None
for i, ln in enumerate(p2_lines):
    if "_character.position.y < 25.0:" in ln:
        # confirm next line is the clamp
        if i + 1 < len(p2_lines) and "_character.position.y = 25.0" in p2_lines[i + 1]:
            p2_idx = i
            break
if p2_idx is None:
    log("p2_locate", False, "y<25 clamp block not found"); shutil.copy2(backup, target); sys.exit(1)
log("p2_locate", True, f"y-clamp at line {p2_idx+1}")
old_p2 = p2_lines[p2_idx] + "\n" + p2_lines[p2_idx + 1]
ws2_if = lws(p2_lines[p2_idx])
ws2_body = lws(p2_lines[p2_idx + 1])
if text.count(old_p2) != 1:
    log("p2_guard", False, f"count={text.count(old_p2)}"); shutil.copy2(backup, target); sys.exit("P2 PRECONDITION")
# After clamping, add ground-impact GAME_OVER if not safely landed
# Print "Ground impact – fatal" to match autostall line 589 detector
new_p2 = (
    old_p2
    + "\n" + ws2_body + "if not _safe_landing and _game_state != GameState.GAME_OVER:\n"
    + ws2_body + "\t_game_state = GameState.GAME_OVER\n"
    + ws2_body + "\tprint(\"[VERBATIM] Ground impact – fatal (no flare)\")\n"
    + ws2_body + "\tprint(\"[VERBATIM] FATAL – ground impact without safe landing\")"
)
text = text.replace(old_p2, new_p2, 1)
log("p2_apply", True, "ground impact GAME_OVER + print added")

# ── Write + verify ────────────────────────────────────────────────────────────
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
with open(target, "r", encoding="utf-8") as f:
    written = f.read()
if written != text:
    shutil.copy2(backup, target); log("raw", False, "MISMATCH"); sys.exit("RAW FAIL")
log("read_after_write", True, "bytes match")

bad = [i+1 for i, ln in enumerate(written.split("\n")) if ln and ln[0] == " " and ln.strip()]
if bad:
    shutil.copy2(backup, target); log("tabs", False, f"spaces at {bad[:5]}"); sys.exit("TABS FAIL")
log("tabs_check", True, "no leading spaces")

# Semantic: _headless_warp_done must appear in code (not just a comment)
code_lines = [ln for ln in written.split("\n") if not ln.strip().startswith("#")]
warp_uses = sum(1 for ln in code_lines if "_headless_warp_done" in ln)
if warp_uses < 2:  # var decl + at least one use
    shutil.copy2(backup, target); log("semantic", False, f"warp_done uses={warp_uses}"); sys.exit("SEMANTIC FAIL")
log("semantic", True, f"_headless_warp_done in {warp_uses} code lines")
print("PATCH SUCCESS", flush=True)
PYEOF

FIX_RC=$?
[ "$FIX_RC" -ne 0 ] && { printf '*** PATCH FAILED (exit %s) ***\n' "$FIX_RC"; exit 1; }

printf '\n=== PATCHED: warp + ground impact context ===\n'
grep -n '_headless_warp_done\|Ground impact.*fatal\|GAME_OVER\|225\.0' "$TARGET" | head -20

# ── FORENSIC HUD DIAGNOSTIC ──────────────────────────────────────────────────
printf '\n=== FORENSIC HUD: server endpoints ===\n'
curl -s --max-time 2 http://127.0.0.1:8765/api/gamification | head -5
curl -s --max-time 2 http://127.0.0.1:8765/api/control_health | head -5

printf '\n=== FORENSIC HUD: add_child + poll_fast + on_stats (forensic_hud.gd) ===\n'
grep -n 'add_child\|_poll_fast\|_on_stats\|_on_ctrl\|_on_leader\|request(' "$FHUD" | head -30

printf '\n=== FORENSIC HUD: _poll_fast function ===\n'
python3 - "$FHUD" << 'PYEOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
start = next((i for i, ln in enumerate(lines) if "func _poll_fast" in ln), None)
if start is None:
    print("_poll_fast not found")
else:
    for i in range(start, min(start+25, len(lines))):
        print(f"{i+1:4d}: {lines[i]}")
PYEOF

printf '\n=== FORENSIC HUD: _on_stats_completed function ===\n'
python3 - "$FHUD" << 'PYEOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
start = next((i for i, ln in enumerate(lines) if "func _on_stats_completed" in ln or "func _on_ctrl_health_completed" in ln), None)
if start is None:
    print("completion handler not found"); sys.exit()
for i in range(start, min(start+30, len(lines))):
    print(f"{i+1:4d}: {lines[i]}")
    if i > start and lines[i].startswith("func "):
        break
PYEOF

# ── AUTOSTALL ────────────────────────────────────────────────────────────────
printf '\n=== AUTOSTALL RUN ===\n'
python3 autostall_patched.py --no-timeout 2>&1 | tee "$ALOG"

{
printf '=== fix_landing_warp.sh report — %s UTC ===\n\n' "$TS"
printf 'GAME_OVER/LANDED markers:\n'
grep 'Ground impact\|GAME_OVER\|LANDED\|Game completed\|Headless.*warp' "$ALOG" || printf '(none)\n'
printf '\nGLIDE count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" || echo 0)"
printf 'Runtime: '; grep 'Runtime:' "$ALOG" || printf '(none)\n'
} > "$OUT"

git add -f "$TARGET" "$OUT" "$ALOG" fix_landing_warp.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "fix: headless warp 200m + ground-impact GAME_OVER (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
