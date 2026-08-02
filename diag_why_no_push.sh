#!/usr/bin/env bash
# ============================================================================
# diag_why_no_push.sh — DISCRIMINATING DIAGNOSTIC, MUTATES NOTHING
#
# WHY THIS EXISTS (Rule #14 Scientific Debugging):
#   Two consecutive fix rounds produced zero verifiable change on the remote:
#     - notes/autostall_post_deploy_20260802152227.txt -> HTTP 404
#     - notes/autostall_p2_20260802153636.txt          -> HTTP 404
#     - build_terrain.gd on main is byte-identical to the pre-P1 copy
#       (no _headless_auto_deploy, no _update_hud_readouts, no _dump_all_labels,
#        no get_node_or_null("PauseMenu"), HUD writes still FREEFALL-only)
#   Rule #14 says: after 2 failed attempts, STOP fixing and run a diagnostic
#   that DISCRIMINATES between hypotheses. That is all this script does.
#
# HYPOTHESES THIS DISCRIMINATES:
#   H1  fix scripts never ran, or aborted at their exactly-1-match pre-check
#   H2  ran + wrote, but the files are gitignored          (Rule #45 scenario)
#   H3  ran + committed, but never pushed                  (git log origin..HEAD)
#   H4  pushed to a different branch or a different remote
#   H5  you are in a different working tree than my scripts target
#
# THIS SCRIPT MUTATES NOTHING. No git add, no commit, no push, no file edit.
# Read-only inspection plus one output file under notes/.
#
# Rules complied with: #1 (every claim traces to a command actually run),
#   #7 (no sed anywhere; grep/awk/git only), #8 (verbatim output, stderr never
#   discarded, no 2>/dev/null), #13 (nothing follows the final command block),
#   #14, #28 (dependency check first), #32 (all output streams live via tee),
#   #37 (missing tool reports SKIP, never PASS), #38 (printf, never bare echo
#   for strings containing shell metacharacters), #39/#45 (gitignore audit),
#   #43 (staged-scope report).
#
# Citations:
#   - git check-ignore:        https://git-scm.com/docs/git-check-ignore
#   - git rev-list / log:      https://git-scm.com/docs/git-log
#   - git branch -vv upstream: https://git-scm.com/docs/git-branch
#   - git ls-files:            https://git-scm.com/docs/git-ls-files
#     (all four: general knowledge — not retrieved this session)
# ============================================================================

PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
TARGET="godot_project/scripts/build_terrain.gd"

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"; [ "$success" = "true" ] && status="SUCCESS"
    printf '[%s] [%s] %s: %s\n' "$ts" "$status" "$operation" "$detail" >&2
}

# --- Rule #28: dependency check BEFORE any gated operation -----------------
for tool in git grep awk date tee; do
    if command -v "$tool" > /dev/null; then
        log_result "dep:$tool" "true" "present"
    else
        log_result "dep:$tool" "false" "MISSING — install before continuing"
        exit 1
    fi
done

cd "$PROJECT_ROOT" || { log_result "cd" "false" "cannot cd to $PROJECT_ROOT"; exit 1; }

TS=$(date -u +%Y%m%d%H%M%S)
mkdir -p notes
OUT="notes/diag_why_no_push_${TS}.txt"

{
printf '=== diag_why_no_push.sh — %s UTC ===\n' "$TS"
printf 'PWD:  %s\n' "$(pwd)"
printf 'HOST: %s\n' "$(hostname)"
printf '\n'

printf '=== H5: AM I IN THE RIGHT WORKING TREE? ===\n'
printf 'git toplevel: %s\n' "$(git rev-parse --show-toplevel)"
printf 'expected:     %s\n' "$PROJECT_ROOT"
if [ "$(git rev-parse --show-toplevel)" = "$PROJECT_ROOT" ]; then
    printf 'H5 RESULT: MATCH — correct tree\n'
else
    printf 'H5 RESULT: *** MISMATCH *** — the fix scripts targeted a different path\n'
fi
printf '\n'

printf '=== H1: DID THE FIXES ACTUALLY LAND IN THE FILE ON DISK? ===\n'
printf -- '--- P1 marker: _headless_auto_deploy ---\n'
grep -n '_headless_auto_deploy' "$TARGET" || printf '  (ZERO MATCHES — P1 NOT applied to disk)\n'
printf -- '--- P2 marker: _update_hud_readouts ---\n'
grep -n '_update_hud_readouts' "$TARGET" || printf '  (ZERO MATCHES — P2 patch A/C NOT applied)\n'
printf -- '--- P2 marker: _dump_all_labels ---\n'
grep -n '_dump_all_labels' "$TARGET" || printf '  (ZERO MATCHES — P2 patch E/F NOT applied)\n'
printf -- '--- P2 marker: get_node_or_null PauseMenu ---\n'
grep -n 'get_node_or_null("PauseMenu")' "$TARGET" || printf '  (ZERO MATCHES — P2 patch D NOT applied)\n'
printf -- '--- ORIGINAL line P2 patch B should have replaced ---\n'
grep -n 'var descent = _get_current_descent_rate()' "$TARGET" || printf '  (not found — patch B DID apply)\n'
printf -- '--- ORIGINAL line P2 patch D should have replaced ---\n'
grep -n '\$PauseMenu.visible' "$TARGET" || printf '  (not found — patch D DID apply)\n'
printf '\n'

printf '=== H1b: DO THE FIX SCRIPTS EVEN EXIST ON DISK? ===\n'
ls -la fix_headless_deploy_p1.py fix_hud_vario_pause_p2.py 2>&1
printf '\n'

printf '=== H1c: BACKUPS — did a fix script ever get far enough to back up? ===\n'
ls -la godot_project/scripts/build_terrain.gd.bak.* 2>&1 | tail -20
printf '\n'

printf '=== H2: GITIGNORE AUDIT (Rule #39 / #45) ===\n'
printf -- '--- is notes/ ignored? ---\n'
git check-ignore -v notes/ || printf '  notes/ is NOT ignored\n'
printf -- '--- are the specific missing files ignored? ---\n'
git check-ignore -v \
    notes/autostall_post_deploy_20260802152227.txt \
    notes/autostall_p2_20260802153636.txt \
    fix_headless_deploy_p1.py \
    fix_hud_vario_pause_p2.py \
    "$TARGET" || printf '  none of the above are ignored\n'
printf -- '--- .gitignore lines mentioning notes, txt, py, or bak ---\n'
grep -n -E 'notes|\.txt|\.py|bak' .gitignore || printf '  (no such lines in .gitignore)\n'
printf '\n'

printf '=== H2b: DO THE MISSING FILES EXIST ON DISK AT ALL? ===\n'
ls -la notes/ | tail -25
printf '\n'
printf 'total files in notes/: %s\n' "$(ls -1 notes/ | wc -l)"
printf '\n'

printf '=== H3: COMMITTED BUT NOT PUSHED? ===\n'
printf -- '--- current branch and upstream ---\n'
git branch -vv
printf -- '--- commits on HEAD not on origin/main ---\n'
git log --oneline origin/main..HEAD || printf '  (origin/main unknown — see H4)\n'
printf -- '--- commits on origin/main not on HEAD ---\n'
git log --oneline HEAD..origin/main || printf '  (none or origin/main unknown)\n'
printf -- '--- last 8 commits on HEAD ---\n'
git log --oneline -8
printf '\n'

printf '=== H4: REMOTE CONFIGURATION ===\n'
git remote -v
printf -- '--- all branches, local and remote ---\n'
git branch -a
printf -- '--- what does the remote actually have as main HEAD? ---\n'
git ls-remote origin main
printf -- '--- what is our HEAD sha? ---\n'
git rev-parse HEAD
printf '\n'

printf '=== WORKING TREE STATE (Rule #43 scope report — read only) ===\n'
printf -- '--- git status short ---\n'
git status --short | head -40
printf -- '--- unstaged/untracked count ---\n'
printf 'modified+untracked: %s\n' "$(git status --porcelain | wc -l)"
printf 'staged:             %s\n' "$(git diff --cached --name-only | wc -l)"
printf '\n'

printf '=== IS build_terrain.gd MODIFIED RELATIVE TO HEAD? ===\n'
if git diff --quiet -- "$TARGET"; then
    printf 'RESULT: build_terrain.gd is IDENTICAL to HEAD (no uncommitted change)\n'
else
    printf 'RESULT: build_terrain.gd DIFFERS from HEAD — diff stat follows\n'
    git diff --stat -- "$TARGET"
fi
printf '\n'

printf '=== SHA OF build_terrain.gd ON DISK vs ON origin/main ===\n'
printf 'disk:        %s\n' "$(git hash-object "$TARGET")"
printf 'origin/main: %s\n' "$(git rev-parse "origin/main:$TARGET" || printf 'UNRESOLVED')"
printf '\n'

printf '=== END OF DIAGNOSTIC ===\n'
printf 'Output file: %s\n' "$OUT"
} 2>&1 | tee "$OUT"

log_result "diagnostic" "true" "written to $OUT"

printf '\n'
printf 'If a push DOES work, run these two lines and post the raw link:\n'
printf '  git add -f %s && git commit -m "diag: why no push" && git push\n' "$OUT"
printf '  https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main/%s\n' "$OUT"
printf 'If push does NOT work, upload %s directly (Rule #34).\n' "$OUT"
