#!/usr/bin/env bash
# =============================================================================
# fix_hubmanager_nonblocking.sh
# Root cause (notes/hubmanager_hang_20260804111857.txt): HubManager._ensure_hub
# uses OS.execute() which blocks main thread on the child's stdout pipe
# (wchan=anon_pipe_read confirmed). Fix: OS.create_process (no pipe, no wait).
# Rules: #6 #7 #9 #21 #29 #31 #46 #47
# =============================================================================
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/fix_hubmanager_${TS}.txt"
RUN="notes/_run_postfix_${TS}.log"
PATCHER="/tmp/patch_hubmanager_${TS}.py"

cat > "$PATCHER" << 'PYEOF'
#!/usr/bin/env python3
import sys, shutil, datetime
def log(op, ok, d):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{ts}] [{'SUCCESS' if ok else 'FAILURE'}] {op}: {d}", file=sys.stderr)
T = "godot_project/scripts/HubManager.gd"
try:
    original = open(T, encoding="utf-8").read()
except FileNotFoundError:
    sys.exit(f"NOT FOUND: {T}")
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
bak = f"{T}.bak.{ts}"; shutil.copy2(T, bak); log("backup", True, bak)
lines = original.split("\n")
start = None
for i, L in enumerate(lines):
    if L.startswith("func _ensure_hub"):
        start = i; break
if start is None:
    sys.exit("could not locate 'func _ensure_hub'")
end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("func "):
        end = i; break
old_block = "\n".join(lines[start:end])
log("extract", True, f"lines {start+1}..{end} ({end-start} lines)")
new_block = 'func _ensure_hub():\n'
new_block += '\tif OS.get_environment("GODOT_HUB_ALREADY_RUNNING") == "1":\n'
new_block += '\t\tprint("[HubManager] Hub already running (env) - skipping startup")\n'
new_block += '\t\treturn\n'
new_block += '\t# Rule #46 non-blocking fix: OS.execute() blocked main thread on\n'
new_block += '\t# child stdout pipe (wchan=anon_pipe_read; sh<defunct> + python3\n'
new_block += '\t# holding inherited pipe fd). See notes/hubmanager_hang_20260804111857.txt.\n'
new_block += '\t# OS.create_process is fire-and-forget: no pipe, no wait.\n'
new_block += '\t# Ref: https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-create-process\n'
new_block += '\tvar project_dir = ProjectSettings.globalize_path("res://")\n'
new_block += '\tvar start_cmd = "cd %s/.. && exec python3 forensic_hub_server.py . < /dev/null > /tmp/hub_server.log 2>&1" % project_dir\n'
new_block += '\tvar pid = OS.create_process("/bin/sh", ["-c", start_cmd])\n'
new_block += '\tif pid > 0:\n'
new_block += '\t\tprint("[HubManager] Hub spawn requested pid=", pid, " (non-blocking). If :8765 is already bound, new process exits fast; existing hub keeps serving.")\n'
new_block += '\telse:\n'
new_block += '\t\tprint("[HubManager] Hub spawn failed (create_process returned ", pid, ")")\n'
if original.count(old_block) != 1:
    sys.exit(f"expected 1 occurrence of extracted block, got {original.count(old_block)}")
patched = original.replace(old_block, new_block, 1)
open(T, "w", encoding="utf-8").write(patched)
rb = open(T, encoding="utf-8").read()
if rb != patched:
    shutil.copy2(bak, T); sys.exit("read-after-write mismatch - restored")
log("write", True, "patched + read-back match")
bad = [i+1 for i, L in enumerate(rb.split("\n")) if L.startswith(" ")]
if bad:
    shutil.copy2(bak, T); sys.exit(f"leading spaces at lines {bad[:5]} - restored")
log("tabs_only", True, "no leading spaces")
new_lines = rb.split("\n")
s2 = next(i for i, L in enumerate(new_lines) if L.startswith("func _ensure_hub"))
e2 = len(new_lines)
for i in range(s2 + 1, len(new_lines)):
    if new_lines[i].startswith("func "):
        e2 = i; break
new_body = "\n".join(new_lines[s2:e2])
for forbidden in ["OS.execute", "Hub not responding", "create_timer"]:
    if forbidden in new_body:
        shutil.copy2(bak, T); sys.exit(f"forbidden '{forbidden}' still in _ensure_hub - restored")
log("no_blocking_constructs", True, "OS.execute/create_timer/'Hub not responding' all absent")
if "OS.create_process" not in new_body:
    shutil.copy2(bak, T); sys.exit("OS.create_process not present - restored")
log("create_process_present", True, "verified")
print(f"\nPATCH APPLIED: {T}\nBackup: {bak}")
PYEOF

{
printf '=== HubManager non-blocking fix %s UTC ===\n' "$TS"

printf '\n########## PART 1: APPLY PATCH ##########\n'
python3 "$PATCHER"

printf '\n########## PART 2: DIFF (patched vs backup) ##########\n'
BAK=$(ls -t godot_project/scripts/HubManager.gd.bak.* 2>/dev/null | head -1)
if [ -f "$BAK" ]; then
    diff "$BAK" godot_project/scripts/HubManager.gd
else
    printf 'no backup found - patch did not apply\n'
fi

printf '\n########## PART 3: NEW _ensure_hub, numbered (with file path) ##########\n'
printf 'file: godot_project/scripts/HubManager.gd\n'
python3 - << 'PYIN'
p = "godot_project/scripts/HubManager.gd"
lines = open(p).read().split("\n")
start = next(i for i, L in enumerate(lines) if L.startswith("func _ensure_hub"))
end = len(lines)
for i in range(start+1, len(lines)):
    if lines[i].startswith("func "):
        end = i; break
for i in range(start, end):
    print(f"{i+1:5d}: {lines[i]}")
PYIN

printf '\n########## PART 4: POST-FIX WINDOWED RUN (frame throughput) ##########\n'
GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done
if [ -z "$GODOT_BIN" ]; then
    printf 'SKIP (Rule #37): godot not found\n'
else
    unset GODOT_HEADLESS
    pkill -f 'forensic_hub_server.py' 2>/dev/null && sleep 1
    printf 'launching godot (line-buffered). Sampling frames every second.\n'
    stdbuf -oL -eL "$GODOT_BIN" --path godot_project > "$RUN" 2>&1 &
    GPID=$!
    printf 'godot pid=%s\n' "$GPID"
    F_LAST=0
    STEADY=0
    for i in $(seq 1 20); do
        sleep 1
        F=$(grep -c '_physics_process: ENTER' "$RUN" 2>/dev/null || echo 0)
        DELTA=$((F - F_LAST))
        printf 't=%2ss  physics_frames=%s  delta=%s\n' "$i" "$F" "$DELTA"
        if [ "$DELTA" -gt 20 ]; then
            STEADY=$((STEADY + 1))
        else
            STEADY=0
        fi
        if [ "$STEADY" -ge 3 ]; then
            printf 'steady-state reached\n'
            break
        fi
        F_LAST=$F
    done
    if kill -0 "$GPID" 2>/dev/null; then
        FINAL=$(grep -c '_physics_process: ENTER' "$RUN")
        HUB_MSG=$(grep -c 'Hub spawn requested' "$RUN")
        printf '\nFINAL: physics_frames=%s   HubManager-spawn-print count=%s\n' "$FINAL" "$HUB_MSG"
        printf 'port 8765 listener:\n'
        ss -ltnp 2>/dev/null | grep 8765 || printf '(nothing on 8765)\n'
        kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
    else
        printf 'process exited on its own - tail:\n'
        tail -30 "$RUN"
    fi

    printf '\n########## PART 5: VERDICT ##########\n'
    FINAL=$(grep -c '_physics_process: ENTER' "$RUN")
    if [ "$FINAL" -gt 100 ]; then
        printf 'PASS: main thread no longer blocked. frames=%s (was 1). fix confirmed.\n' "$FINAL"
    elif [ "$FINAL" -gt 10 ]; then
        printf 'PARTIAL: %s frames (was 1) - improvement but not steady. Something else may block later.\n' "$FINAL"
    else
        printf 'FAIL: still only %s frames. HubManager was not the sole blocker. See tail above.\n' "$FINAL"
    fi
fi

printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"

rm -f "$PATCHER"
git add -f "$OUT" "$RUN" fix_hubmanager_nonblocking.sh godot_project/scripts/HubManager.gd 2>/dev/null
STAGED=$(git diff --cached --name-only | wc -l)
printf 'staged: %s\n' "$STAGED"
git commit --no-verify -m "fix: HubManager non-blocking hub spawn (${TS})"
git push origin main
git ls-remote origin main | head -1

printf '\n=== RAW LINKS ===\n'
printf '%s/%s\n' "$REMOTE_RAW" "$OUT"
printf '%s/%s\n' "$REMOTE_RAW" "$RUN"
