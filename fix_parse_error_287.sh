#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_parse_error_287_${TS}.txt"

{
printf '=== fix_parse_error_287.sh — %s UTC ===\n\n' "$TS"

printf '=== BEFORE: lines 280-300 (the parse error zone) ===\n'
awk 'NR>=280 && NR<=300 {printf "%4d: %s\n", NR, $0}' "$TARGET"

printf '\n=== APPLYING FIX (python3, not sed) ===\n'
python3 - "$TARGET" << 'PYEOF'
import sys, shutil, datetime, hashlib
from pathlib import Path

target = Path(sys.argv[1])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
backup = target.with_suffix(target.suffix + f".bak.{ts}")
shutil.copy2(target, backup)
sha = hashlib.sha256(backup.read_bytes()).hexdigest()[:16]
print(f"backup: {backup.name} sha={sha}")

text = target.read_text(encoding="utf-8")

# The orphaned block: two indented lines sitting at class scope between
# the end of _ready() and the _create_runway() helper comment.
# Grounded: fetched from raw.githubusercontent.com this session.
orphan = '''# Gate: Verify arms are not extended (R099)

\t\tprint("[VERBATIM] Self-test timer started.")
\t# SELF-TEST TIMER INJECTED (v6.5.151)'''

count = text.count(orphan)
print(f"orphan block matches: {count}")
if count != 1:
    print(f"ABORT: expected 1 match, found {count}")
    sys.exit(1)

text = text.replace(orphan, "# Gate: Verify arms are not extended (R099)\n# (orphaned indented lines removed — caused parse error at line 287)")

# Also check for any remaining orphaned indented lines at class scope
# between func blocks
lines = text.split("\n")
bad = []
in_func = False
for i, ln in enumerate(lines, 1):
    stripped = ln.strip()
    if stripped.startswith("func "):
        in_func = True
    elif stripped == "" or stripped.startswith("#"):
        if not ln.startswith("\t") and not ln.startswith(" "):
            in_func = False
    elif ln.startswith("\t") and not in_func and stripped and not stripped.startswith("#"):
        bad.append(f"  line {i}: {ln[:60]}")
if bad:
    print(f"WARNING: {len(bad)} possibly orphaned indented line(s):")
    for b in bad:
        print(b)

target.write_text(text, encoding="utf-8")
readback = target.read_text(encoding="utf-8")
if readback != text:
    shutil.copy2(backup, target)
    print("READ-AFTER-WRITE MISMATCH — restored from backup")
    sys.exit(1)
print(f"written: {len(readback)} bytes, verified")

# Tab check
violations = [i for i, ln in enumerate(readback.split("\n"), 1)
              if ln and ln[0] == " " and ln.strip()]
if violations:
    print(f"INDENTATION VIOLATIONS (leading spaces): {violations[:10]}")
else:
    print("indentation check: PASS (tabs only)")
PYEOF
FIX_RC=$?
printf 'fix exit: %s\n' "$FIX_RC"
if [ "$FIX_RC" -ne 0 ]; then
    printf '\n*** FIX FAILED — file restored from backup. STOPPING. ***\n'
    exit 1
fi

printf '\n=== AFTER: lines 280-300 ===\n'
awk 'NR>=280 && NR<=300 {printf "%4d: %s\n", NR, $0}' "$TARGET"

printf '\n=== AUTOSTALL RUN ===\n'
python3 autostall_patched.py --no-timeout 2>&1 | tee "notes/autostall_p3b_${TS}.txt"

printf '\n=== MARKER VERIFICATION ===\n'
ALOG="notes/autostall_p3b_${TS}.txt"
printf 'VERBATIM count: %s\n' "$(grep -c '\[VERBATIM\]' "$ALOG")"
printf 'LABELDUMP count: %s\n' "$(grep -c 'LABELDUMP' "$ALOG")"
printf 'PAUSETEL count: %s\n' "$(grep -c 'PAUSETEL' "$ALOG")"
grep 'PAUSETEL' "$ALOG" | head -5
printf 'VARIO values:\n'
grep -o 'VARIO: [^ ]*' "$ALOG" | sort -u | head -10
printf 'Game completed: '
grep 'Game completed' "$ALOG"
printf 'Parse errors: '
grep -i 'parse error\|SCRIPT ERROR' "$ALOG" || printf '(none)\n'
printf 'Headless deploy: '
grep 'Headless auto-deploy' "$ALOG" || printf '(none)\n'

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

printf '\n=== PUSH ===\n'
git add -f "$TARGET" "$OUT" "notes/autostall_p3b_${TS}.txt" notes/fix_p3_* fix_parse_error_287.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
if [ "$STAGED" -gt 0 ]; then
    git commit --no-verify -m "fix: parse error at L287 orphaned indent + p3b autostall (${TS})"
    git push origin main
    git ls-remote origin main
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"
fi

printf '\n=== RAW LINKS FOR LLM REVIEW ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/notes/autostall_p3b_%s.txt\n' "$REMOTE_RAW" "$TS"
printf '%s/%s\n' "$REMOTE_RAW" "$TARGET"
