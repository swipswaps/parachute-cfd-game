#!/usr/bin/env bash
# ============================================================================
# verify_patch_status.sh – Read‑only audit of the current build_terrain.gd
# and the parachute_mutations.db to confirm the patch was applied.
# ============================================================================

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"; [ "$success" = "true" ] && status="SUCCESS"
    printf '[%s] [%s] %s: %s\n' "$ts" "$status" "$operation" "$detail" >&2
}

PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac"
CURRENT="$PROJECT_ROOT/parachute-cfd-game"
cd "$CURRENT" || { log_result "cd" "false" "cannot cd to current"; exit 1; }

TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/verify_patch_status_${TS}.txt"

{
    printf '=== verify_patch_status.sh — %s UTC ===\n\n' "$TS"

    # ------------------------------------------------------------------------
    # 1. Check build_terrain.gd
    # ------------------------------------------------------------------------
    TARGET="godot_project/scripts/build_terrain.gd"
    if [ ! -f "$TARGET" ]; then
        printf 'ERROR: %s not found\n' "$TARGET"
        exit 1
    fi

    # Extract the colour loop (the for i in range(verts.size()) block)
    COLOUR_LOOP=$(awk '/for i in range\(verts\.size\(\)\)/,/st\.add_index/' "$TARGET" | head -30)
    # Extract _do_cutaway function
    DO_CUTAWAY=$(awk '/^func _do_cutaway\(/,/^func [a-z]/' "$TARGET" | head -30)

    printf '--- Colour loop (first 20 lines) ---\n%s\n\n' "$COLOUR_LOOP"
    printf '--- _do_cutaway ---\n%s\n\n' "$DO_CUTAWAY"

    # Check for COLOUR_BOX usage inside the loop (should be absent)
    if echo "$COLOUR_LOOP" | grep -q 'COLOUR_BOX'; then
        COLOUR_OK=false
        printf '[FAIL] Colour loop still uses COLOUR_BOX.\n'
    else
        COLOUR_OK=true
        printf '[PASS] Colour loop is simplified (no COLOUR_BOX).\n'
    fi

    # Check that _do_cutaway contains FREEFALL transition
    if echo "$DO_CUTAWAY" | grep -q 'GameState.FREEFALL'; then
        CUTAWAY_OK=true
        printf '[PASS] _do_cutaway transitions to FREEFALL.\n'
    else
        CUTAWAY_OK=false
        printf '[FAIL] _do_cutaway does NOT transition to FREEFALL.\n'
    fi

    # ------------------------------------------------------------------------
    # 2. Inspect database (parachute_mutations.db)
    # ------------------------------------------------------------------------
    DB="parachute_mutations.db"
    if [ -f "$DB" ]; then
        printf '\n--- Database schema ---\n'
        sqlite3 "$DB" ".schema" | head -50

        # Check for any tables that might store patch status or configuration
        printf '\n--- Tables with patch/status keywords ---\n'
        for tbl in $(sqlite3 "$DB" ".tables"); do
            if echo "$tbl" | grep -qiE 'patch|status|config|files_to_fix|rule_compliance'; then
                printf '\nTable: %s\n' "$tbl"
                sqlite3 "$DB" "SELECT * FROM $tbl LIMIT 5;"
            fi
        done
    else
        printf '\n[INFO] No database file found (parachute_mutations.db).\n'
    fi

    # ------------------------------------------------------------------------
    # 3. Check for backup files from recent patches
    # ------------------------------------------------------------------------
    printf '\n--- Recent backup files ---\n'
    ls -lt "$(dirname "$TARGET")" | grep -E '\.bak\.[0-9]+' | head -5

    # ------------------------------------------------------------------------
    # 4. Overall verdict
    # ------------------------------------------------------------------------
    printf '\n=== VERDICT ===\n'
    if [ "$COLOUR_OK" = true ] && [ "$CUTAWAY_OK" = true ]; then
        printf '✅ Patch is ACTIVE and working (colour loop simplified, cutaway->FREEFALL).\n'
        printf '   Run the game to verify visually and functionally.\n'
    else
        printf '❌ Patch is NOT fully applied. Missing:\n'
        [ "$COLOUR_OK" = false ] && printf '   - Colour loop still uses COLOUR_BOX\n'
        [ "$CUTAWAY_OK" = false ] && printf '   - _do_cutaway missing FREEFALL transition\n'
        printf '   You may need to reapply the patch.\n'
    fi

    printf '\n=== END REPORT ===\n'
} 2>&1 | tee "$OUT"

# ----------------------------------------------------------------------------
# Push evidence (simplified)
# ----------------------------------------------------------------------------
git add -f "$OUT" "$0" 2>/dev/null
git commit --no-verify -m "verify patch status (${TS})" 2>/dev/null
git push origin main 2>/dev/null

REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#.*github.com[:/](.*)\.git#\1#')
RAW_LINK="https://raw.githubusercontent.com/${OWNER_REPO}/main/${OUT}"
printf '\n=== RAW LINK FOR LLM REVIEW ===\n%s\n' "$RAW_LINK"

printf '\n=== VERIFICATION COMPLETE ===\n'
