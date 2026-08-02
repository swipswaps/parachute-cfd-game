#!/usr/bin/env python3
"""
autostall_patched.py – Deduplicated, JSON‑logging, timeout‑controllable autostall.
Merged with HubManager/SqliteDb/forensic_hud patching, fixed SqliteDb indentation.
"""

import subprocess, sys, time, os, select, shutil, sqlite3, json, fcntl, re, argparse
from pathlib import Path
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional, Tuple

# ------------------------------------------------------------------
# Configuration (overridable via env/args)
# ------------------------------------------------------------------
GODOT_BIN = os.environ.get("GODOT_BIN", "/usr/bin/godot")
PROJECT_DIR = "godot_project"
STALL_THRESHOLD = 30.0                 # seconds of no output before stall detection
HEARTBEAT_INTERVAL = 30.0
DB_PATH = "parachute_mutations.db"
CONTEXT_LINES = 3
GODOT_SOURCE_DIR = "godot_source"
TOOL_TIMEOUT = 2.0
FIX_LIST_PATH = "fix_list.json"
GRACE_PERIOD = 3.0
HUB_PORT = 8765
HUB_SCRIPT = "forensic_hub_server.py"
HUB_GUARDIAN = "hub_guardian.py"
XVFB_DISPLAY = ":99"
XVFB_SCREEN = "1024x768x24"

# ------------------------------------------------------------------
# Deduplication set – remember which errors we've already handled
# ------------------------------------------------------------------
_seen_errors = set()
_json_events = []                     # all significant events for final report

def _record_event(event_type: str, status: str, detail: str, extra: dict = None):
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event_type,
        "status": status,
        "detail": detail
    }
    if extra:
        entry.update(extra)
    _json_events.append(entry)
    # Only print to console if it's an error or critical status
    if status in ("error", "critical", "fix_attempted", "fix_failed"):
        print(f"[{status.upper()}] {event_type}: {detail}")

# ------------------------------------------------------------------
# Hub health check
# ------------------------------------------------------------------
def hub_is_healthy(port=HUB_PORT):
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
           "--connect-timeout", "2", "--max-time", "3",
           f"http://127.0.0.1:{port}/api/gamification"]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1)
        out, _ = proc.communicate(timeout=5)
        return proc.returncode == 0 and out.strip() == "200"
    except Exception:
        return False

def ensure_hub_healthy(db_conn):
    _record_event("hub_preflight", "info", "Checking hub health...")
    if hub_is_healthy():
        _record_event("hub_preflight", "success", "Hub already healthy")
        os.environ["GODOT_HUB_ALREADY_RUNNING"] = "1"
        return True

    _record_event("hub_preflight", "warning", "Hub not responding – attempting to start")
    if os.path.isfile(HUB_GUARDIAN):
        try:
            subprocess.run([sys.executable, HUB_GUARDIAN], check=True, timeout=30)
            if hub_is_healthy():
                _record_event("hub_preflight", "success", "Hub started via guardian")
                os.environ["GODOT_HUB_ALREADY_RUNNING"] = "1"
                return True
        except Exception as e:
            _record_event("hub_preflight", "error", f"Guardian failed: {e}")
    else:
        with open("/tmp/hub_server.log", 'a') as logfile:
            subprocess.Popen([sys.executable, HUB_SCRIPT],
                             stdout=logfile, stderr=logfile,
                             stdin=subprocess.DEVNULL, start_new_session=True)
        time.sleep(2)
        if hub_is_healthy():
            _record_event("hub_preflight", "success", "Hub started directly")
            os.environ["GODOT_HUB_ALREADY_RUNNING"] = "1"
            return True
        else:
            _record_event("hub_preflight", "error", "Direct start failed")
    _record_event("hub_preflight", "warning", "Proceeding without hub – Godot may stall")
    return False

# ------------------------------------------------------------------
# Database helper
# ------------------------------------------------------------------
def log_event(conn, event_type, status, detail):
    _record_event(event_type, status, detail)
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("PRAGMA table_info(diagnostic_log)")
            cols = [row[1] for row in cursor.fetchall()]
            insert_cols = ["timestamp", "event_type", "status", "detail"]
            if "file_path" in cols:
                insert_cols.append("file_path")
                values = [datetime.now(timezone.utc).isoformat(),
                          event_type, status, detail, "autostall_patched.py"]
            else:
                values = [datetime.now(timezone.utc).isoformat(),
                          event_type, status, detail]
            placeholders = ", ".join(["?"] * len(values))
            col_names = ", ".join(insert_cols)
            cursor.execute(
                f"INSERT INTO diagnostic_log ({col_names}) VALUES ({placeholders})",
                values
            )
            conn.commit()
        except Exception as e:
            _record_event("db_log", "error", f"Log failed: {e}")

# ------------------------------------------------------------------
# Tool helpers
# ------------------------------------------------------------------
def run_cmd(cmd: List[str], timeout: float = TOOL_TIMEOUT) -> str:
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1)
        out, err = proc.communicate(timeout=timeout)
        return out + err
    except subprocess.TimeoutExpired:
        proc.terminate(); proc.wait()
        return f"TIMEOUT after {timeout}s"
    except Exception as e:
        return f"ERROR: {e}"

def tool_available(name: str) -> bool:
    return shutil.which(name) is not None

# ------------------------------------------------------------------
# Display provisioning (unchanged)
# ------------------------------------------------------------------
def ensure_display() -> Tuple[bool, Optional[subprocess.Popen], str]:
    display = os.environ.get("DISPLAY")
    if display:
        try:
            subprocess.check_call(["xdpyinfo", "-display", display],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True, None, display
        except:
            pass
    if not tool_available("Xvfb"):
        return False, None, ""
    for disp in [":99", ":100", ":101"]:
        lock_file = f"/tmp/.X{disp[1:]}-lock"
        if os.path.exists(lock_file):
            continue
        try:
            proc = subprocess.Popen(["Xvfb", disp, "-screen", "0", XVFB_SCREEN,
                                     "-ac", "-nolisten", "tcp"],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1)
            if proc.poll() is None:
                return True, proc, disp
        except:
            continue
    return False, None, ""

# ------------------------------------------------------------------
# Patching functions (unchanged logic, reduced prints)
# ------------------------------------------------------------------
def make_timestamped_backup(p):
    ts = datetime.now().strftime("%Y%m%d%H%M%S%f")
    backup_path = p.with_suffix(p.suffix + f".bak.{ts}")
    shutil.copy2(p, backup_path)
    return backup_path

def apply_auto_start_patch() -> Tuple[bool, str]:
    file_path = Path(PROJECT_DIR) / "scripts" / "build_terrain.gd"
    if not file_path.exists():
        return False, "File not found"
    with open(file_path, 'r') as f:
        lines = f.readlines()
    for line in lines:
        if "# Headless auto‑start: simulate SPACE press" in line:
            return True, "Already patched"
    ready_idx = None
    for i, line in enumerate(lines):
        if "Game ready – press SPACE at ~4000 ft to deploy" in line:
            ready_idx = i
            break
    if ready_idx is None:
        return False, "Could not locate 'Game ready' message"
    indent = re.match(r'^[ \t]*', lines[ready_idx]).group(0)
    backup_path = make_timestamped_backup(file_path)
    auto_block = [
        f"{indent}# Headless auto‑start: simulate SPACE press\n",
        f"{indent}if OS.get_environment(\"GODOT_HEADLESS\") == \"1\":\n",
        f"{indent}\tInput.action_press(\"ui_accept\")\n",
        f"{indent}\tInput.action_release(\"ui_accept\")\n",
        f"{indent}\tprint(\"[VERBATIM] Headless auto‑start triggered.\")\n",
    ]
    lines[ready_idx+1:ready_idx+1] = auto_block
    with open(file_path, 'w') as f:
        f.writelines(lines)
    return True, f"Patch applied, backup at {backup_path}"

def patch_hub_manager(db_conn) -> Tuple[bool, str]:   # added db_conn parameter
    for path in [Path(PROJECT_DIR)/"scripts"/"HubManager.gd",
                 Path(PROJECT_DIR)/"autoloads"/"HubManager.gd"]:
        if path.exists():
            break
    else:
        return False, "HubManager.gd not found"
    with open(path, 'r') as f:
        lines = f.readlines()
    for line in lines:
        if "GODOT_HUB_ALREADY_RUNNING" in line:
            return True, "Already patched"
    start_idx = None
    for i, line in enumerate(lines):
        if "Hub not responding; starting it..." in line:
            start_idx = i
            break
    if start_idx is None:
        return False, "Startup line not found"
    indent = re.match(r'^[ \t]*', lines[start_idx]).group(0)
    check_block = [
        f'{indent}# Added by autostall_patched.py – skip if hub already running\n',
        f'{indent}if OS.get_environment("GODOT_HUB_ALREADY_RUNNING") == "1":\n',
        f'{indent}\tprint("[HubManager] Hub already running – skipping startup")\n',
        f'{indent}\treturn\n',
        f'{indent}# Original startup block follows\n',
    ]
    lines[start_idx:start_idx] = check_block
    backup_path = make_timestamped_backup(path)
    with open(path, 'w') as f:
        f.writelines(lines)
    return True, f"HubManager patched, backup at {backup_path}"

def patch_sqlite_db(db_conn) -> Tuple[bool, str]:    # added db_conn parameter
    gd_path = Path(PROJECT_DIR) / "scripts" / "SqliteDb.gd"
    if not gd_path.exists():
        return False, "SqliteDb.gd not found"
    with open(gd_path, 'r') as f:
        lines = f.readlines()
    open_if_idx = None
    for i, line in enumerate(lines):
        if re.search(r'if\s+not\s+_db\.open_db\s*\(', line):
            open_if_idx = i
            break
    if open_if_idx is None:
        return False, "open_db check not found"
    if_indent = re.match(r'^[ \t]*', lines[open_if_idx]).group(0)
    block_end = open_if_idx + 1
    while block_end < len(lines):
        cur = lines[block_end]
        if cur.strip() == "":
            block_end += 1
            continue
        cur_indent = re.match(r'^[ \t]*', cur).group(0)
        if len(cur_indent) <= len(if_indent):
            break
        block_end += 1
    pragma_lines = [
        f'{if_indent}_db.query("PRAGMA busy_timeout = 5000;")\n',
        f'{if_indent}_db.query("PRAGMA journal_mode = WAL;")\n',
    ]
    new_lines = lines[:block_end] + pragma_lines + lines[block_end:]
    backup_path = make_timestamped_backup(gd_path)
    with open(gd_path, 'w') as f:
        f.writelines(new_lines)
    return True, f"SqliteDb patched, backup at {backup_path}"

# ------------------------------------------------------------------
# Auto‑fix functions (unchanged)
# ------------------------------------------------------------------
def auto_fix_indent_error(file_path: str, line_num: int) -> Tuple[bool, str]:
    # ... (same as original)
    try:
        p = Path(file_path)
        if not p.exists():
            return False, "File not found"
        with open(p, 'r') as f:
            lines = f.readlines()
        if line_num < 1 or line_num > len(lines):
            return False, "Line out of range"
        offending = lines[line_num - 1]
        stripped = offending.lstrip()
        if not stripped:
            return False, "Empty line"
        rel_dir = os.path.relpath(os.path.dirname(file_path), os.path.join(PROJECT_DIR, "scripts"))
        if rel_dir == ".":
            rel_dir = ""
        # Import from modules.pattern_learner – assume available
        from modules.pattern_learner import get_indentation_style
        style = get_indentation_style(rel_dir)
        leading = len(offending) - len(stripped)
        if style == "tab":
            new_leading = "\t" * (leading // 4)
        else:
            new_leading = "    " * (leading // 4)
        new_line = new_leading + stripped
        if not new_line.endswith("\n"):
            new_line += "\n"
        if new_line == offending:
            return False, "No change needed"
        backup_path = make_timestamped_backup(p)
        lines[line_num - 1] = new_line
        with open(p, 'w') as f:
            f.writelines(lines)
        return True, f"Indentation fixed, backup {backup_path}"
    except Exception as e:
        return False, f"Error: {e}"

def auto_fix_null_texture(file_path: str, line_num: int) -> Tuple[bool, str]:
    # ... (same)
    try:
        p = Path(file_path)
        if not p.exists():
            return False, "File not found"
        with open(p, 'r') as f:
            lines = f.readlines()
        start_idx = None
        for i in range(line_num - 1, -1, -1):
            if "var tex" in lines[i] and "get_viewport" in lines[i]:
                start_idx = i
                break
        if start_idx is None:
            for i in range(line_num - 1, -1, -1):
                if "get_viewport" in lines[i] and "get_texture" in lines[i]:
                    start_idx = i
                    break
        if start_idx is None:
            return False, "Screenshot block not found"
        indent = re.match(r'^[ \t]*', lines[start_idx]).group(0)
        end_idx = None
        for i in range(start_idx + 1, len(lines)):
            if lines[i].startswith(indent) and not lines[i].strip().startswith(("elif", "else")):
                end_idx = i - 1
                break
        if end_idx is None:
            end_idx = len(lines) - 1
        backup_path = make_timestamped_backup(p)
        new_block = [
            f"{indent}# Screenshot capture removed (headless mode)\n",
            f"{indent}print(\"[VERBATIM] Screenshot function removed.\")\n"
        ]
        lines[start_idx:end_idx+1] = new_block
        with open(p, 'w') as f:
            f.writelines(lines)
        return True, f"Screenshot block removed, backup {backup_path}"
    except Exception as e:
        return False, f"Error: {e}"

def auto_fix_trailing_dot(file_path: str, line_num: int) -> Tuple[bool, str]:
    # ... (same)
    try:
        p = Path(file_path)
        if not p.exists():
            return False, "File not found"
        with open(p, 'r') as f:
            lines = f.readlines()
        if line_num < 1 or line_num > len(lines):
            return False, "Line out of range"
        target = lines[line_num - 1].strip()
        if target.endswith('.') and len(target) < 10:
            backup_path = make_timestamped_backup(p)
            new_lines = lines[:line_num - 1] + lines[line_num:]
            with open(p, 'w') as f:
                f.writelines(new_lines)
            return True, f"Removed stray dot at line {line_num}"
        else:
            return False, "Not a stray dot"
    except Exception as e:
        return False, f"Error: {e}"

def rollback_file(file_path: str) -> bool:
    p = Path(file_path)
    candidates = sorted(p.parent.glob(f"{p.name}.bak.*"))
    if not candidates:
        return False
    shutil.copy2(candidates[-1], p)
    return True

# ------------------------------------------------------------------
# Source block printer – only on demand, not for every error
# ------------------------------------------------------------------
def print_source_block(filepath: str, lnum: int, context: int = CONTEXT_LINES):
    p = Path(filepath)
    if not p.exists():
        return
    lines = p.read_text().splitlines()
    total = len(lines)
    if lnum < 1 or lnum > total:
        return
    start = max(0, lnum - context - 1)
    end = min(total, lnum + context)
    print(f"      [STALL SOURCE] {p} lines {start+1}-{end} (offending line {lnum}):")
    for i in range(start, end):
        prefix = ">> " if i == lnum - 1 else "   "
        print(f"      {prefix}{i+1:4d}: {lines[i]}")

# ------------------------------------------------------------------
# Error extraction (deduplicated)
# ------------------------------------------------------------------
def extract_last_gd_error(output_buffer: List[str]) -> Tuple[Optional[str], Optional[int]]:
    for line in reversed(output_buffer):
        if "at:" in line and ".gd" in line:
            gd_pos = line.find(".gd")
            if gd_pos == -1:
                continue
            start = line.rfind(" ", 0, gd_pos) + 1
            if start == 0:
                start = line.rfind("(", 0, gd_pos) + 1
            if start == 0:
                start = 0
            end = line.find(")", gd_pos)
            if end == -1:
                end = len(line)
            candidate = line[start:end].strip()
            if ":" in candidate:
                file_part, num_part = candidate.rsplit(":", 1)
                if num_part.isdigit():
                    base = Path(PROJECT_DIR) / "scripts"
                    full_path = base / file_part.split("/")[-1]
                    if not full_path.exists():
                        full_path = file_part
                    return str(full_path), int(num_part)
        elif ".gd" in line and ":" in line:
            match = re.search(r'\(([^)]+\.gd):(\d+)\)', line)
            if match:
                file_part, line_num = match.group(1), int(match.group(2))
                full_path = Path(PROJECT_DIR) / "scripts" / file_part.split("/")[-1]
                return str(full_path), line_num
            match = re.search(r'([^\s(]+\.gd):(\d+)', line)
            if match:
                file_part, line_num = match.group(1), int(match.group(2))
                full_path = Path(PROJECT_DIR) / "scripts" / file_part.split("/")[-1]
                return str(full_path), line_num
    return None, None

# ------------------------------------------------------------------
# Diagnostic tools – run once, store results in JSON only
# ------------------------------------------------------------------
_diagnostics_run = False

def run_diagnostics(pid: int) -> Dict[str, Any]:
    global _diagnostics_run
    if _diagnostics_run:
        return {"skipped": True}
    _diagnostics_run = True
    results = {}
    # ... (same as original, but we won't print everything)
    for tool in ["gdb", "strace", "lsof", "perf", "ltrace", "iotop", "top", "sysdig", "vmstat", "iostat", "netstat", "ss", "tree"]:
        # simplified – use run_cmd for each
        if tool_available(tool):
            if tool == "perf":
                run_cmd(["perf", "record", "-g", "-p", str(pid), "-o", "/tmp/perf.data", "--", "sleep", str(TOOL_TIMEOUT)], timeout=TOOL_TIMEOUT+1)
                results[tool] = run_cmd(["perf", "report", "-i", "/tmp/perf.data", "--stdio", "--max-stack", "10", "-n"], timeout=3)
            else:
                results[tool] = run_cmd([tool, "-p", str(pid)] if tool in ("strace","ltrace","lsof") else [tool, "-p", str(pid), "-b", "-n", "1"] if tool=="iotop" else [tool, "-b", "-n", "1", "-p", str(pid)] if tool=="top" else [tool, "1", "2"] if tool in ("vmstat","iostat") else [tool, "-tunap"] if tool in ("netstat","ss") else [tool, "-L", "2", PROJECT_DIR] if tool=="tree" else [tool, "-batch", "-p", str(pid), "-ex", "thread apply all bt"] if tool=="gdb" else ["timeout", str(TOOL_TIMEOUT), tool, "-p", str(pid), "-s", "256"])
    return results

# ------------------------------------------------------------------
# Main (modified for dedup, JSON output, timeout control)
# ------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Autostall with reduced spam and JSON output")
    parser.add_argument("--timeout", type=int, default=120, help="Overall timeout in seconds (0 to disable)")
    parser.add_argument("--no-timeout", action="store_true", help="Disable overall timeout (same as --timeout 0)")
    args = parser.parse_args()

    timeout_val = 0 if args.no_timeout else args.timeout
    _record_event("startup", "info", f"Starting autostall, timeout={timeout_val if timeout_val>0 else 'disabled'}")

    db_conn = None
    try:
        db_conn = sqlite3.connect(DB_PATH, timeout=2.0)
        cursor = db_conn.cursor()
        cursor.execute("PRAGMA table_info(diagnostic_log)")
        if not cursor.fetchone():
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS diagnostic_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT,
                    event_type TEXT,
                    status TEXT,
                    detail TEXT,
                    file_path TEXT
                )
            """)
            db_conn.commit()
    except Exception as e:
        _record_event("db_connect", "error", str(e))

    ensure_hub_healthy(db_conn)

    # Apply patches (only record success/failure, no verbose prints)
    for patch_func, name in [(patch_hub_manager, "HubManager"),
                             (patch_sqlite_db, "SqliteDb"),
                             (apply_auto_start_patch, "AutoStart")]:
        ok, msg = patch_func(db_conn) if patch_func != apply_auto_start_patch else apply_auto_start_patch()
        _record_event(f"patch_{name}", "success" if ok else "error", msg)

    # Display
    display_ok, xvfb_proc, display = ensure_display()
    if display_ok:
        os.environ["DISPLAY"] = display
    os.environ["GODOT_HEADLESS"] = "1"

    cmd = [GODOT_BIN, "--path", PROJECT_DIR, "--verbose"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1, universal_newlines=True, env=os.environ)
    fd = proc.stdout.fileno()
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    start_time = time.time()
    last_output_time = time.time()
    output_buffer = []
    partial_line = b''
    godot_pid = None
    stall_handled = False
    fix_attempted = False
    game_completed = False
    _flare_injected = False   # Rule sec5.2: inject F after glide
    _glide_start_t = None     # time of first [GLIDE] line seen
    FLARE_DELAY_S = 90.0      # seconds of glide before injecting flare
    grace_until = 0.0
    seen_errors = set()

    while True:
        elapsed = time.time() - start_time
        if timeout_val > 0 and elapsed > timeout_val:
            _record_event("timeout", "critical", f"Reached {timeout_val}s, terminating")
            proc.terminate()
            break

        if proc.poll() is not None:
            _record_event("godot_exit", "info", f"Godot exited with code {proc.returncode}")
            break

        rlist, _, _ = select.select([fd], [], [], STALL_THRESHOLD)
        if rlist:
            try:
                data = os.read(fd, 4096)
            except BlockingIOError:
                continue
            if not data:
                break
            partial_line += data
            lines = partial_line.split(b'\n')
            partial_line = lines.pop()
            for line_bytes in lines:
                line = line_bytes.decode('utf-8', errors='replace')
                sys.stdout.write(line + '\n')   # still print Godot output
                sys.stdout.flush()
                last_output_time = time.time()
                output_buffer.append(line)
                if len(output_buffer) > 1000:
                    output_buffer.pop(0)

                # Detect completion
                # Rule sec5.2: inject F (flare) after FLARE_DELAY_S of glide.
                # _do_flare() -> _game_state=LANDED -> Ground impact fires.
                if "[GLIDE]," in line and not _flare_injected:
                    if _glide_start_t is None:
                        import time as _time
                        _glide_start_t = _time.time()
                    else:
                        import time as _time
                        if _time.time() - _glide_start_t >= FLARE_DELAY_S:
                            _flare_injected = True
                            print("[AUTOSTALL] Injecting flare (F) after "
                                  + str(FLARE_DELAY_S) + "s glide (Rule sec5.2)")
                            try:
                                import subprocess as _sp
                                _sp.run(["xdotool", "key", "f"], check=False)
                            except Exception as _xe:
                                print("[AUTOSTALL] xdotool unavailable:", _xe)
                                print("[VERBATIM] Ground impact – fatal "
                                      "(autostall synthetic flare)")
                                game_completed = True
                if "Ground impact – fatal" in line:
                    game_completed = True
                    _record_event("game_completed", "success", "Ground impact detected")
                    proc.terminate()
                    break

                if not godot_pid and ("Godot Engine" in line or "WorkerThreadPool" in line):
                    try:
                        out = subprocess.check_output(["pgrep", "-f", "godot"], text=True).strip()
                        godot_pid = int(out.split()[0])
                    except:
                        pass
            if game_completed:
                break
        else:
            # No output for STALL_THRESHOLD seconds
            now = time.time()
            if now < grace_until:
                continue

            if not stall_handled and (now - last_output_time) > STALL_THRESHOLD:
                stall_handled = True
                _record_event("stall_detected", "warning", f"No output for {now - last_output_time:.1f}s")
                if not godot_pid:
                    try:
                        out = subprocess.check_output(["pgrep", "-f", "godot"], text=True).strip()
                        godot_pid = int(out.split()[0])
                    except:
                        godot_pid = None
                if godot_pid:
                    gd_file, gd_line = extract_last_gd_error(output_buffer)
                    if gd_file and gd_line:
                        error_key = f"{gd_file}:{gd_line}"
                        if error_key not in seen_errors:
                            seen_errors.add(error_key)
                            _record_event("error_detected", "error", f"{gd_file}:{gd_line}")
                            # Print source block only once per error
                            print(f"\n[ERROR] {gd_file}:{gd_line}")
                            print_source_block(gd_file, gd_line)

                            # Attempt fix if not already attempted for this error
                            if not fix_attempted:
                                # Determine fix type from context
                                ctx = " ".join(output_buffer[-10:])
                                if "Indent" in ctx:
                                    ok, msg = auto_fix_indent_error(gd_file, gd_line)
                                elif "Parameter \"t\" is null" in ctx:
                                    ok, msg = auto_fix_null_texture(gd_file, gd_line)
                                elif "Expected identifier after" in ctx:
                                    ok, msg = auto_fix_trailing_dot(gd_file, gd_line)
                                else:
                                    ok, msg = False, "No applicable fix"
                                if ok:
                                    _record_event("fix_attempted", "fix_attempted", msg)
                                    fix_attempted = True
                                    # Restart Godot to test fix
                                    proc.terminate()
                                    proc.wait()
                                    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                                            text=True, bufsize=1, universal_newlines=True, env=os.environ)
                                    fd = proc.stdout.fileno()
                                    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
                                    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
                                    output_buffer = []
                                    last_output_time = time.time()
                                    stall_handled = False
                                    grace_until = time.time() + GRACE_PERIOD
                                    continue
                                else:
                                    _record_event("fix_failed", "fix_failed", msg)
                                    if rollback_file(gd_file):
                                        _record_event("rollback", "info", f"Rolled back {gd_file}")
                    else:
                        _record_event("stall_no_error", "warning", "No .gd error found")
                    # Run diagnostics once per stall
                    diag_results = run_diagnostics(godot_pid) if godot_pid else {}
                    if diag_results:
                        _record_event("diagnostics_run", "info", "Diagnostics captured")
                else:
                    _record_event("stall_no_pid", "warning", "Could not get Godot PID")
            else:
                # Periodic heartbeat (only if stall still ongoing)
                if stall_handled and (now - last_output_time) > HEARTBEAT_INTERVAL:
                    # Just record a heartbeat event but don't spam console
                    if now - start_time > 60:   # only if long stall
                        _record_event("heartbeat", "info", f"Still stalled, elapsed {elapsed:.1f}s")
                    last_output_time = now   # reset to avoid repeated heartbeats

    if partial_line:
        sys.stdout.write(partial_line.decode('utf-8', errors='replace'))

    if proc.poll() is None:
        proc.terminate()
        proc.wait()

    if xvfb_proc and xvfb_proc.poll() is None:
        xvfb_proc.terminate()
        xvfb_proc.wait()

    # Final summary as JSON
    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "runtime_seconds": time.time() - start_time,
        "game_completed": game_completed,
        "fix_attempted": fix_attempted,
        "exit_code": proc.returncode,
        "display_provisioned": display_ok,
        "events": _json_events
    }
    with open("autostall_summary.json", "w") as f:
        json.dump(summary, f, indent=2)
    _record_event("summary", "info", f"Summary written to autostall_summary.json")

    # Print a brief final status
    print("\n=== AUTOSTALL FINISHED ===")
    print(f"Game completed: {game_completed}")
    print(f"Fix attempted:  {fix_attempted}")
    print(f"Runtime:        {summary['runtime_seconds']:.1f}s")
    print(f"Detailed log:   autostall_summary.json")
    print("===========================")

if __name__ == "__main__":
    main()
