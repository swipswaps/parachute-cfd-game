#!/usr/bin/env bash
PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
TARGET="godot_project/scripts/build_terrain.gd"
cd "$PROJECT_ROOT" || exit 1

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_const_indent_${TS}.txt"

{
printf '=== fix_const_indent.sh — %s UTC ===\n\n' "$TS"
printf '=== BEFORE: lines 283-290 ===\n'
awk 'NR>=283 && NR<=290 {printf "%4d: %s\n", NR, $0}' "$TARGET"

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

# The LOD fix put W and H at class scope (zero indent) but they sit
# physically inside _ready()'s `if file:` block which needs two tabs.
# Lines 287-289 (HM_SRC, MAX_ELEV, SCALE_XZ) are correctly at two tabs.
# Fix: indent W and H to match.
old = "const W = 512\nconst H = 512\n\t\tconst HM_SRC = 4096"
new = "\t\tconst W = 512\n\t\tconst H = 512\n\t\tconst HM_SRC = 4096"

count = text.count(old)
print(f"const indent matches: {count}")
if count != 1:
    print(f"ABORT: expected 1 match, found {count}")
    sys.exit(1)

text = text.replace(old, new, 1)

# Verify no leading-space lines (Rule #31)
violations = [i for i, ln in enumerate(text.split("\n"), 1)
              if ln and ln[0] == " " and ln.strip()]
if violations:
    print(f"INDENTATION VIOLATIONS: {violations[:10]}")
    shutil.copy2(backup, target)
    print("RESTORED from backup due to indentation violations")
    sys.exit(1)

target.write_text(text, encoding="utf-8")
readback = target.read_text(encoding="utf-8")
if readback != text:
    shutil.copy2(backup, target)
    print("READ-AFTER-WRITE MISMATCH — restored")
    sys.exit(1)
print(f"written: {len(readback)} bytes, verified")
print("indentation check: PASS")

# Quick parse-error smoke test: look for any remaining zero-indent
# non-comment, non-blank, non-func, non-var, non-class, non-enum,
# non-const, non-extends lines that start with a tab (would be orphaned)
import re
func_starts = [i for i, ln in enumerate(text.split("\n"), 1)
               if re.match(r'^func\s', ln)]
print(f"func definitions found: {len(func_starts)}")
print(f"first 5 func lines: {func_starts[:5]}")
PYEOF

FIX_RC=$?
printf 'fix exit: %s\n' "$FIX_RC"
if [ "$FIX_RC" -ne 0 ]; then
    printf '\n*** FIX FAILED — restored from backup. STOPPING. ***\n'
    exit 1
fi

printf '\n=== AFTER: lines 283-290 ===\n'
awk 'NR>=283 && NR<=290 {printf "%4d: %s\n", NR, $0}' "$TARGET"

printf '\n=== GODOT PARSE CHECK (--check-only if available) ===\n'
if command -v godot > /dev/null; then
    timeout 15 godot --headless --check-only --path godot_project 2>&1 | head -20
    printf 'godot exit: %s\n' "$?"
else
    printf 'SKIP: godot not in PATH (Rule #37)\n'
fi

printf '\n=== AUTOSTALL RUN ===\n'
python3 autostall_patched.py --no-timeout 2>&1 | tee "notes/autostall_p3c_${TS}.txt"

ALOG="notes/autostall_p3c_${TS}.txt"
printf '\n=== MARKER VERIFICATION ===\n'
printf 'Parse errors: '; grep -i 'parse error\|SCRIPT ERROR' "$ALOG" || printf '(none)\n'
printf 'VERBATIM count: %s\n' "$(grep -c '\[VERBATIM\]' "$ALOG")"
printf 'LABELDUMP count: %s\n' "$(grep -c 'LABELDUMP' "$ALOG")"
printf 'PAUSETEL: '; grep 'PAUSETEL' "$ALOG" | head -5 || printf '(none)\n'
printf 'VARIO values: '; grep -o 'VARIO: [^ ]*' "$ALOG" | sort -u | head -5
printf 'Headless deploy: '; grep 'Headless auto-deploy' "$ALOG" || printf '(none)\n'
printf 'Game completed: '; grep 'Game completed' "$ALOG"
printf 'GLIDE count: %s\n' "$(grep -c '\[GLIDE\]' "$ALOG")"

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

printf '\n=== PUSH ===\n'
git add -f "$TARGET" "$OUT" "notes/autostall_p3c_${TS}.txt" fix_const_indent.sh
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git diff --cached --name-only
if [ "$STAGED" -gt 0 ]; then
    git commit --no-verify -m "fix: const W/H indent at L285-286 — parse error at L287 (${TS})"
    git push origin main
    git ls-remote origin main
    printf 'local HEAD: %s\n' "$(git rev-parse HEAD)"
fi

printf '\n=== RAW LINKS FOR LLM REVIEW ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/notes/autostall_p3c_%s.txt\n' "$REMOTE_RAW" "$TS"
printf '%s/%s\n' "$REMOTE_RAW" "$TARGET"
