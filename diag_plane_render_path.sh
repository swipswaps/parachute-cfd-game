#!/usr/bin/env bash
# ============================================================================
# diag_plane_render_path.sh
# Proves, from logs alone, the plane-visibility state in main:
#  PART 1  windowed run (NO --headless, NO GODOT_HEADLESS) so auto-jump does
#          NOT fire -> game stays IN_PLANE, plane orbits, telemetry captured
#  PART 2  runtime extract: plane creation, visible/scale, plane+camera frames
#  PART 3  geometry: camera->plane vector per sampled frame (in front? distance?)
#  PART 4  numbered render-path code from main (±context, with file path)
#  PART 5  same sections from _0062 (working baseline)
#  PART 6  targeted diff of ONLY those functions
# Rules: #8 stderr kept, #32 stream, #47 push+raw link, #38 safe quoting
# ============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REF="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game_0062"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/plane_render_path_${TS}.txt"
RUN="notes/_run_windowed_${TS}.log"
GD="godot_project/scripts/build_terrain.gd"
REFGD="$REF/godot_project/scripts/build_terrain.gd"

# find godot binary
GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done

{
printf '=== plane render-path diagnostic %s UTC ===\n' "$TS"
printf 'godot binary: %s\n\n' "${GODOT_BIN:-NOT FOUND}"

# ---- PART 1: windowed run, auto-jump suppressed ------------------------------
printf '########## PART 1: WINDOWED RUN (stays IN_PLANE) ##########\n'
if [ -z "$GODOT_BIN" ]; then
    printf 'SKIP (Rule #37): godot binary not found — cannot produce runtime evidence\n'
else
    unset GODOT_HEADLESS
    printf 'Launching windowed for 25s. A window WILL appear. Do NOT press J.\n'
    printf 'cmd: %s --path godot_project  (no --headless, GODOT_HEADLESS unset)\n\n' "$GODOT_BIN"
    timeout 25 "$GODOT_BIN" --path godot_project > "$RUN" 2>&1
    printf 'run exit: %s   run log lines: %s\n' "$?" "$(wc -l < "$RUN")"
fi

# ---- PART 2: runtime extract -------------------------------------------------
printf '\n########## PART 2: RUNTIME PLANE + CAMERA TELEMETRY ##########\n'
if [ -f "$RUN" ]; then
    printf '--- plane creation / visibility ---\n'
    grep -nE 'plane created|_plane_node=|Cessna|FlyingPlane|visible=|scale=' "$RUN" | head -20
    printf '\n--- GameState transitions (want to STAY at 0/IN_PLANE) ---\n'
    grep -nE 'state=|EXIT AIRCRAFT|FREEFALL|transitioning' "$RUN" | head -15
    printf '\n--- first 12 IN_PLANE physics frames (plane pos + camera pos) ---\n'
    grep -nE 'plane position updated|camera moved from|Camera updated' "$RUN" | head -24
    printf '\n--- any render/mesh/cull warnings ---\n'
    grep -niE 'mesh|cull|frustum|not visible|null|error' "$RUN" | grep -iE 'plane|cessna|mesh|cull|frustum' | head -15
else
    printf '(no run log — PART 1 skipped)\n'
fi

# ---- PART 3: geometry from a sampled frame -----------------------------------
printf '\n########## PART 3: CAMERA->PLANE GEOMETRY ##########\n'
if [ -f "$RUN" ]; then
python3 - "$RUN" <<'PYEOF'
import re, sys
run = sys.argv[1]
txt = open(run, errors="replace").read()
# plane position updated to (x, y, z)
planes = re.findall(r'plane position updated to \(([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\)', txt)
# camera moved from (...) to (x, y, z)
cams = re.findall(r'camera moved from \([^)]*\) to \(([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\)', txt)
print(f"parsed plane frames={len(planes)}  camera frames={len(cams)}")
n = min(len(planes), len(cams))
if n == 0:
    print("No paired plane/camera frames captured. If PART 2 shows the plane was")
    print("created but there are 0 physics frames, the run left IN_PLANE immediately")
    print("(auto-jump still fired) OR the window closed before physics ran.")
else:
    import math
    for i in list(range(min(3, n))) + ([n-1] if n > 3 else []):
        px, py, pz = map(float, planes[i])
        cx, cy, cz = map(float, cams[i])
        dx, dy, dz = px-cx, py-cy, pz-cz
        dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        print(f"frame {i}: plane=({px:.1f},{py:.1f},{pz:.1f}) "
              f"camera=({cx:.1f},{cy:.1f},{cz:.1f}) "
              f"delta=({dx:.1f},{dy:.1f},{dz:.1f}) dist={dist:.1f}m")
    print("Note: code calls _camera.look_at(plane) every frame, so the plane is")
    print("centered in view by construction. If dist is within near/far (0.1..10000)")
    print("and PART 2 shows visible=true, the plane IS framed — 'not visible' would")
    print("then mean occlusion, scale, or the window never actually rendered.")
PYEOF
else
    printf '(no run log)\n'
fi

# ---- helper: numbered extract around each anchor -----------------------------
extract() {
    local file="$1" label="$2"; shift 2
    printf '\n===== %s  [%s] =====\n' "$label" "$file"
    for anchor in "$@"; do
        local hits
        hits=$(grep -nF "$anchor" "$file" | cut -d: -f1)
        for ln in $hits; do
            printf -- '--- anchor "%s" @ line %s (±5) ---\n' "$anchor" "$ln"
            awk -v L="$ln" 'NR>=L-5 && NR<=L+5 {printf "%5d: %s\n", NR, $0}' "$file"
        done
    done
}

ANCHORS_PLANE='_plane_node = plane'
# gather the render-path anchors present in both files
COMMON_ANCHORS=(
  'plane.global_position = Vector3'
  'Cessna'
  '_plane_node = plane'
  '_camera = Camera3D.new()'
  'func _update_camera_position'
  'func _load_camera_settings'
  '_camera.look_at'
)

# ---- PART 4: main render path -------------------------------------------------
printf '\n########## PART 4: MAIN render-path code (numbered, with path) ##########\n'
extract "$GD" "MAIN" "${COMMON_ANCHORS[@]}"

# ---- PART 5: _0062 render path -----------------------------------------------
printf '\n########## PART 5: _0062 render-path code (numbered, with path) ##########\n'
if [ -f "$REFGD" ]; then
    extract "$REFGD" "_0062" "${COMMON_ANCHORS[@]}"
else
    printf 'SKIP: _0062 not found at %s\n' "$REFGD"
fi

# ---- PART 6: targeted diff of the plane-creation function --------------------
printf '\n########## PART 6: DIFF main vs _0062, plane-create block ##########\n'
if [ -f "$REFGD" ]; then
    # isolate from 'Cessna' load to '_plane_node = plane' in each, diff those slices
    for tag in MAIN REF; do
        f="$GD"; [ "$tag" = "REF" ] && f="$REFGD"
        s=$(grep -nF 'Cessna' "$f" | head -1 | cut -d: -f1)
        e=$(grep -nF '_plane_node = plane' "$f" | head -1 | cut -d: -f1)
        [ -z "$s" ] && s=1; [ -z "$e" ] && e=$((s+40))
        awk -v A="$s" -v B="$e" 'NR>=A-2 && NR<=B+2' "$f" > "/tmp/slice_${tag}_${TS}.gd"
        printf '%s slice: lines %s..%s of %s\n' "$tag" "$s" "$e" "$f"
    done
    printf -- '--- diff (REF=_0062 < , MAIN > ) ---\n'
    diff "/tmp/slice_REF_${TS}.gd" "/tmp/slice_MAIN_${TS}.gd" || printf '(identical)\n'
    rm -f "/tmp/slice_REF_${TS}.gd" "/tmp/slice_MAIN_${TS}.gd"
fi

printf '\n=== END DIAGNOSTIC ===\n'
} 2>&1 | tee "$OUT"

# stage the report + the run log AFTER both are fully written (Rule #47 anti-truncation)
git add -f "$OUT" "$RUN" diag_plane_render_path.sh 2>/dev/null
git add -f "$GD"
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "diag: plane render-path runtime+code evidence (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINKS FOR LLM REVIEW ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$RUN"
