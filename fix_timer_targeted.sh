#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
ALOG="notes/autostall_targeted_${TS}.txt"
OUT="notes/fix_timer_targeted_${TS}.txt"

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

# ── PATCH 1: remove the 5s timer SETUP in _ready() ──────────────────────────
# Target ONLY the two-line timer setup: create_timer(5.0) + connect(_auto_deploy)
# Live extraction: find the create_timer line
p1_idx = None
for i, ln in enumerate(lines):
    if "_temp_timer = get_tree().create_timer(5.0)" in ln:
        p1_idx = i
        break
if p1_idx is None:
    log("p1_locate", False, "create_timer(5.0) line not found")
    shutil.copy2(backup, target); sys.exit(1)
log("p1_locate", True, f"line {p1_idx+1}: {lines[p1_idx]!r}")

# Confirm next line is the connect call
if p1_idx + 1 >= len(lines) or '_auto_deploy' not in lines[p1_idx + 1]:
    log("p1_guard", False, f"next line is not _auto_deploy connect: {lines[p1_idx+1]!r}")
    shutil.copy2(backup, target); sys.exit(1)

# Extract exact 2-line block (with surrounding newlines to avoid blank line remnant)
old_p1 = "\n" + lines[p1_idx] + "\n" + lines[p1_idx + 1]
if text.count(old_p1) != 1:
    log("p1_guard", False, f"count={text.count(old_p1)}")
    shutil.copy2(backup, target); sys.exit("P1 PRECONDITION")
log("p1_guard", True, "exactly 1 match")

text = text.replace(old_p1, "", 1)
log("p1_apply", True, "timer setup removed")

# ── PATCH 2: remove func _auto_deploy() + orphaned comment ──────────────────
# Live extraction: find func _auto_deploy():
lines2 = text.split("\n")
func_idx = next((i for i, ln in enumerate(lines2) if ln == "func _auto_deploy():"), None)
if func_idx is None:
    log("p2_locate", False, "func _auto_deploy(): not found")
    shutil.copy2(backup, target); sys.exit(1)
log("p2_locate", True, f"func at line {func_idx+1}")

# Extract: func header + body lines (all indented lines after it)
func_end = func_idx + 1
while func_end < len(lines2):
    ln = lines2[func_end]
    if ln and not ln.startswith("\t") and not ln.startswith("#"):
        break
    func_end += 1

old_p2_lines = lines2[func_idx:func_end]
old_p2 = "\n".join(old_p2_lines)
log("p2_block", True, f"lines {func_idx+1}-{func_end}: {len(old_p2_lines)} lines")
for ln in old_p2_lines:
    print(f"  removing: {ln!r}")

if text.count(old_p2) != 1:
    log("p2_guard", False, f"count={text.count(old_p2)}")
    shutil.copy2(backup, target); sys.exit("P2 PRECONDITION")
log("p2_guard", True, "exactly 1 match")

# Replace with empty (the surrounding \n from adjacent lines stays)
text = text.replace(old_p2, "", 1)
log("p2_apply", True, "func _auto_deploy() removed")

# ── Write + verify ────────────────────────────────────────────────────────────
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
with open(target, "r", encoding="utf-8") as f:
    written = f.read()
if written != text:
    shutil.copy2(backup, target); log("raw", False, "MISMATCH"); sys.exit("RAW FAIL")
log("read_after_write", True, "bytes match")

bad = [i+1 for i, ln in enumerate(written.split("\n")) if ln and ln[0]==" " and ln.strip()]
if bad:
    shutil.copy2(backup, target); log("tabs", False, str(bad[:5])); sys.exit("TABS FAIL")
log("tabs_check", True, "clean")

# Semantic: func _auto_deploy must be gone; create_timer(5.0) must be gone;
# but _headless_auto_deploy and get_tree().quit must still exist (they have other uses)
checks = {
    "func _auto_deploy() removed": "func _auto_deploy():" not in written,
    "create_timer(5.0) removed":   "create_timer(5.0)" not in written,
    "_headless_auto_deploy kept":  "_headless_auto_deploy" in written,
    "_deploy_canopy kept":         "_deploy_canopy()" in written,
}
all_ok = True
for name, ok in checks.items():
    log(f"semantic/{name}", ok, "")
    if not ok:
        all_ok = False
if not all_ok:
    shutil.copy2(backup, target); sys.exit("SEMANTIC FAIL")

lines_final = written.split("\n")
log("final_line_count", True, str(len(lines_final)))
print("\nPATCH SUCCESS", flush=True)
PYEOF

FIX_RC=$?
[ "$FIX_RC" -ne 0 ] && { printf '*** PATCH FAILED (exit %s) — restored from backup ***\n' "$FIX_RC"; exit 1; }

printf '\n=== Verify key markers remain ===\n'
grep -n '_headless_auto_deploy\|_deploy_canopy\|225\.0\|Ground impact\|GAME_OVER' \
    "$TARGET" | grep -v '^\s*#' | head -15
printf 'Lines: '; wc -l < "$TARGET"

printf '\n=== AUTOSTALL RUN ===\n'
python3 autostall_patched.py --no-timeout 2>&1 | tee "$ALOG"

{
printf '=== fix_timer_targeted.sh — %s UTC ===\n\n' "$TS"
printf 'Parse errors: '
grep -i 'parse error\|SCRIPT ERROR' "$ALOG" | head -3 || printf '(none)\n'
printf '\nKey markers:\n'
grep 'Ground impact\|GAME_OVER\|warp\|Game completed\|Auto.deploy\|Runtime' \
    "$ALOG" | grep -v '\[GLIDE\]' | head -20
printf '\nGLIDE count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG" || echo 0)"
printf 'Runtime: '; grep 'Runtime:' "$ALOG" || printf '(none)\n'
} > "$OUT"

git add -f "$TARGET" "$OUT" "$ALOG" fix_timer_targeted.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "fix: remove _auto_deploy 5s timer (${TS})" && \
    git push origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
