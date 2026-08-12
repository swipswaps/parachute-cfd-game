#!/usr/bin/env bash
# ============================================================================
# extract_and_diff.sh – Extracts full function bodies and terrain generation
# from 0062, 0074, and current, and generates diffs.
# ============================================================================

PROJECT_ROOT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac"
CUR="$PROJECT_ROOT/parachute-cfd-game/godot_project/scripts/build_terrain.gd"
D74="$PROJECT_ROOT/parachute-cfd-game_0074/godot_project/scripts/build_terrain.gd"
D62="$PROJECT_ROOT/parachute-cfd-game_0062/godot_project/scripts/build_terrain.gd"

# Use awk to extract function body (handles indentation)
extract_func() {
    local file="$1" func="$2"
    awk -v f="$func" '
        $0 ~ "^[[:space:]]*func " f "\\(" {
            flag=1
            indent=length($0)-length(substr($0, match($0, /[^ ]/)))
            print
            next
        }
        flag && length($0)-length(substr($0, match($0, /[^ ]/))) <= indent && $0 !~ /^$/ {
            flag=0
        }
        flag { print }
    ' "$file"
}

# Extract the terrain generation block (from "verts = []" to "st.commit()" or similar)
extract_terrain_gen() {
    local file="$1"
    awk '
        /verts = \[\]/ { flag=1; print; next }
        flag && /st\.commit\(\)/ { print; flag=0 }
        flag { print }
    ' "$file"
}

TS=$(date -u +%Y%m%d%H%M%S)
OUTDIR="$PROJECT_ROOT/parachute-cfd-game/notes/extract_$TS"
mkdir -p "$OUTDIR"

# Extract functions from each version
for label in cur d74 d62; do
    case $label in
        cur) file="$CUR"; prefix="CURRENT" ;;
        d74) file="$D74"; prefix="0074" ;;
        d62) file="$D62"; prefix="0062" ;;
    esac
    for func in _physics_process _do_cutaway _do_reserve; do
        extract_func "$file" "$func" > "$OUTDIR/${prefix}_${func}.txt"
    done
    extract_terrain_gen "$file" > "$OUTDIR/${prefix}_terrain_gen.txt"
done

# Generate report
REPORT="$OUTDIR/report.txt"
{
    echo "=== EXTRACT AND DIFF REPORT ==="
    echo "Timestamp: $(date -u)"
    echo

    for func in _physics_process _do_cutaway _do_reserve terrain_gen; do
        echo "--- $func ---"
        for prefix in CURRENT 0074 0062; do
            echo "=== $prefix ==="
            cat "$OUTDIR/${prefix}_${func}.txt"
            echo
        done

        echo "--- DIFF: CURRENT vs 0074 ($func) ---"
        diff -u "$OUTDIR/CURRENT_${func}.txt" "$OUTDIR/0074_${func}.txt" || true
        echo
        echo "--- DIFF: CURRENT vs 0062 ($func) ---"
        diff -u "$OUTDIR/CURRENT_${func}.txt" "$OUTDIR/0062_${func}.txt" || true
        echo
        echo "--- DIFF: 0074 vs 0062 ($func) ---"
        diff -u "$OUTDIR/0074_${func}.txt" "$OUTDIR/0062_${func}.txt" || true
        echo "----------------------------------------"
        echo
    done

    echo "=== END REPORT ==="
} > "$REPORT"

# Push to git
cd "$PROJECT_ROOT/parachute-cfd-game"
git add -f "$REPORT" "$0"
git commit --no-verify -m "extract and diff: physics, cutaway, reserve, terrain gen (${TS})"
git push origin main

REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#.*github.com[:/](.*)\.git#\1#')
RAW_LINK="https://raw.githubusercontent.com/${OWNER_REPO}/main/notes/extract_$TS/report.txt"

echo "=== RAW LINK ==="
echo "$RAW_LINK"
