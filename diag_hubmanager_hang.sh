#!/usr/bin/env bash
# Captures the hang STACK before killing (no arbitrary kill-before-capture).
# PART A: HubManager's hub-start code, numbered, with path (the blocking call)
# PART B: live /proc stack + wchan + fds + child procs + gdb bt at the freeze
PROJECT="/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
REMOTE_RAW="https://raw.githubusercontent.com/swipswaps/parachute-cfd-game/main"
cd "$PROJECT" || exit 1
TS=$(date -u +%Y%m%d%H%M%S)
OUT="notes/hubmanager_hang_${TS}.txt"
RUN="notes/_run_hang_${TS}.log"
GODOT_BIN=""
for c in godot godot4 /usr/local/bin/godot /usr/bin/godot; do
    command -v "$c" >/dev/null 2>&1 && GODOT_BIN="$c" && break
done
{
printf '%s\n' "=== HubManager hang diagnostic $TS UTC ==="
printf 'godot: %s\n' "${GODOT_BIN:-NONE}"

printf '\n%s\n' "########## PART A: HubManager hub-start code ##########"
HM=$(grep -rlF 'Hub not responding' godot_project --include=*.gd 2>/dev/null | head -1)
printf 'HubManager path: %s\n' "${HM:-NOT FOUND}"
if [ -n "$HM" ]; then
  for anchor in 'Hub not responding' 'OS.execute' 'OS.create_process' 'func _ensure_hub' 'func _start_hub' 'connect_to_host' 'get_response' 'request(' 'poll(' 'while' 'await'; do
    grep -nF "$anchor" "$HM" 2>/dev/null | while IFS=: read -r ln rest; do
      printf '%s\n' "--- \"$anchor\" @ $HM:$ln (context) ---"
      awk -v L="$ln" 'NR>=L-4 && NR<=L+4 {printf "%5d: %s\n", NR, $0}' "$HM"
    done
  done
fi

printf '\n%s\n' "########## PART B: LIVE STATE AT HANG ##########"
if [ -z "$GODOT_BIN" ]; then
  printf '%s\n' "SKIP (Rule #37): godot not found"
else
  unset GODOT_HEADLESS
  stdbuf -oL -eL "$GODOT_BIN" --path godot_project > "$RUN" 2>&1 &
  GPID=$!
  printf 'godot pid=%s; waiting for hang signature (max 30s)...\n' "$GPID"
  for i in $(seq 1 30); do
    sleep 1
    if grep -q 'Hub not responding; starting it' "$RUN" 2>/dev/null; then
      C1=$(grep -c '_physics_process: ENTER' "$RUN"); sleep 3
      C2=$(grep -c '_physics_process: ENTER' "$RUN")
      printf 'hang signature seen at ~%ss. physics frames before=%s after+3s=%s\n' "$i" "$C1" "$C2"
      break
    fi
  done
  if kill -0 "$GPID" 2>/dev/null; then
    printf '\n%s\n' "--- /proc/$GPID/status ---"
    grep -E '^(State|Threads|VmRSS):' /proc/$GPID/status 2>/dev/null || printf '(unreadable)\n'
    printf '\n%s\n' "--- /proc/$GPID/wchan (kernel wait channel) ---"
    cat /proc/$GPID/wchan 2>/dev/null; echo
    printf '\n%s\n' "--- open sockets/pipes (blocking connect leaves a trace) ---"
    ls -l /proc/$GPID/fd 2>/dev/null | grep -Ei 'socket|pipe' | head -20
    printf '\n%s\n' "--- child processes (did hub spawn? blocking wait?) ---"
    ps --ppid "$GPID" -o pid,stat,wchan,cmd 2>/dev/null || pgrep -P "$GPID"
    printf '\n%s\n' "--- gdb thread backtrace (if available) ---"
    if command -v gdb >/dev/null 2>&1; then
      timeout 25 gdb -p "$GPID" -batch -ex 'set pagination off' -ex 'thread apply all bt' 2>&1 | head -100 \
        || printf '(gdb attach failed — likely ptrace_scope=1; run: sudo sysctl kernel.yama.ptrace_scope=0)\n'
    else
      printf '(gdb not installed — SKIP per Rule #37)\n'
    fi
    printf '\n%s\n' "--- port 8765 listener ---"
    ss -ltnp 2>/dev/null | grep 8765 || printf '(nothing on 8765 — hub never bound)\n'
    kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
    printf '\n(killed AFTER capture — the timeout did not omit the stack)\n'
  else
    printf 'process exited on its own — last 20 lines:\n'; tail -20 "$RUN"
  fi
fi
printf '\n=== END ===\n'
} 2>&1 | tee "$OUT"
git add -f "$OUT" "$RUN" diag_hubmanager_hang.sh 2>/dev/null
git commit --no-verify -m "diag: HubManager hang live stack ${TS}"
git push origin main
printf '\n=== RAW LINK ===\n%s/%s\n' "$REMOTE_RAW" "$OUT"
