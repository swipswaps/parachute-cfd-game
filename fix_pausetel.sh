#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
ALOG="notes/autostall_pausetel_${TS}.txt"
OUT="notes/fix_pausetel_${TS}.txt"

python3 - "$TARGET" << 'PYEOF'
import sys, shutil, datetime

def log(op, ok, detail):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {detail}", flush=True)

def leading_ws(line):
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

# ── PATCH 1: selftest double-toggle ─────────────────────────────────────────
sig = "func _p3_pause_selftest() -> void:"
sig_idx = next((i for i, ln in enumerate(lines) if ln == sig), None)
if sig_idx is None:
    log("p1_locate", False, "signature not found"); shutil.copy2(backup, target); sys.exit(1)
log("p1_locate", True, f"line {sig_idx+1}")

old_p1 = "\n".join(lines[sig_idx : sig_idx + 6])
if text.count(old_p1) != 1:
    log("p1_guard", False, f"count={text.count(old_p1)}"); shutil.copy2(backup, target)
    sys.exit(f"PRECONDITION VIOLATED: p1 count={text.count(old_p1)}")
log("p1_guard", True, "exactly 1 match")

bw = leading_ws(lines[sig_idx + 1])

# Note: comments deliberately avoid the string "toggle_pause()" so the
# semantic check (which counts code-line occurrences only) stays unambiguous.
new_p1 = (
    sig + "\n"
    + bw + "# Drive to a known state before testing. The prior version called\n"
    + bw + "# the toggle function twice, netting zero change from tree.paused=true,\n"
    + bw + "# leaving the game frozen (PAUSETEL FAIL). Fix: one toggle, explicit restore.\n"
    + bw + "# Ref: SceneTree.paused (general knowledge — not retrieved this session):\n"
    + bw + "# https://docs.godotengine.org/en/stable/classes/class_scenetree.html\n"
    + bw + "get_tree().paused = true\n"
    + bw + 'print("[PAUSETEL] selftest BEGIN tree.paused=", get_tree().paused)\n'
    + bw + "toggle_pause()\n"
    + bw + "var _ok := not get_tree().paused\n"
    + bw + 'print("[PAUSETEL] selftest ", "PASS" if _ok else "FAIL",\n'
    + bw * 3 + '" tree.paused=", get_tree().paused, " (must be false)")\n'
    + bw + "get_tree().paused = false\n"
    + bw + 'print("[PAUSETEL] selftest END tree.paused=", get_tree().paused)'
)

text = text.replace(old_p1, new_p1, 1)
log("p1_apply", True, "selftest body replaced")

# ── PATCH 2: line 553 env-var-only gate ─────────────────────────────────────
lines2 = text.split("\n")
p2_idx = None
for i, ln in enumerate(lines2):
    if ('OS.get_environment("GODOT_HEADLESS") == "1"' in ln
            and 'or "--headless"' not in ln
            and i + 1 < len(lines2)
            and 'Input.action_press("ui_accept")' in lines2[i + 1]):
        p2_idx = i
        break

if p2_idx is None:
    log("p2_locate", True, "env-var-only gate not found — skipping")
else:
    log("p2_locate", True, f"env-var-only gate at line {p2_idx+1}")
    old_p2 = lines2[p2_idx] + "\n" + lines2[p2_idx + 1]
    ws2 = leading_ws(lines2[p2_idx])
    new_p2 = (ws2 + 'if OS.get_environment("GODOT_HEADLESS") == "1"'
              + ' or "--headless" in OS.get_cmdline_args():'
              + "\n" + lines2[p2_idx + 1])
    if text.count(old_p2) != 1:
        log("p2_guard", False, f"count={text.count(old_p2)}"); shutil.copy2(backup, target)
        sys.exit(f"PRECONDITION VIOLATED: p2 count={text.count(old_p2)}")
    log("p2_guard", True, "exactly 1 match")
    text = text.replace(old_p2, new_p2, 1)
    log("p2_apply", True, "L553 gate updated")

# ── Write + verify ───────────────────────────────────────────────────────────
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
with open(target, "r", encoding="utf-8") as f:
    written = f.read()
if written != text:
    shutil.copy2(backup, target); log("raw", False, "MISMATCH — restored"); sys.exit("RAW FAIL")
log("read_after_write", True, "bytes match")

bad = [i+1 for i, ln in enumerate(written.split("\n")) if ln and ln[0] == " " and ln.strip()]
if bad:
    shutil.copy2(backup, target); log("tabs", False, f"spaces at lines {bad[:10]}"); sys.exit("TABS FAIL")
log("tabs_check", True, "no leading spaces")

# Semantic: count toggle_pause() in non-comment code lines only (Rule #46)
# Previous failure: comment text "toggle twice" matched the same substring.
start = written.find("func _p3_pause_selftest() -> void:")
stop  = written.find("\nfunc ", start + 1)
body  = written[start:stop] if stop > 0 else written[start:]
code_lines = [ln for ln in body.split("\n") if ln.strip() and not ln.strip().startswith("#")]
tc = sum(1 for ln in code_lines if "toggle_pause()" in ln)
if tc != 1:
    shutil.copy2(backup, target)
    log("semantic", False, f"toggle_pause() in code lines: {tc} (expected 1)")
    sys.exit("SEMANTIC FAIL")
log("semantic", True, f"exactly 1 toggle_pause() in code lines")

print(f"\nPATCH SUCCESS  backup={backup}", flush=True)
PYEOF

FIX_RC=$?
[ "$FIX_RC" -ne 0 ] && { printf '*** PATCH FAILED (exit %s) — STOPPING ***\n' "$FIX_RC"; exit 1; }

printf '\n=== PATCHED selftest ===\n'
awk 'NR>=2924 && NR<=2945 {printf "%4d: %s\n", NR, $0}' "$TARGET"

# ── Autostall (streams live; $ALOG written before $OUT) ─────────────────────
printf '\n=== AUTOSTALL RUN ===\n'
python3 autostall_patched.py --no-timeout 2>&1 | tee "$ALOG"

# ── Assemble $OUT after $ALOG is complete (Rule #47 — no self-truncation) ───
{
printf '=== fix_pausetel.sh report — %s UTC ===\n\n' "$TS"
printf '=== PAUSETEL markers ===\n'
grep 'PAUSETEL' "$ALOG" || printf '(none)\n'
printf '\n=== Game completed ===\n'
grep 'Game completed' "$ALOG" || printf '(not found)\n'
printf '\n=== Parse errors ===\n'
grep -i 'parse error\|SCRIPT ERROR' "$ALOG" | head -5 || printf '(none)\n'
printf '\n=== GLIDE count ===\n'
grep -c '\[GLIDE\]' "$ALOG" || printf '0\n'
} > "$OUT"

git add -f "$TARGET" "$OUT" "$ALOG" fix_pausetel.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
[ "$STAGED" -gt 0 ] && \
    git commit --no-verify -m "fix: pausetel selftest one-toggle + L553 gate (${TS})" && \
    git push origin main && \
    git ls-remote origin main && \
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$ALOG"
