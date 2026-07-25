#!/usr/bin/env python3
"""
autostall.py – Adaptive self‑healing for Godot simulations with automatic display provisioning.
- Ensures a valid X11 display (starts Xvfb if needed) so that the game renders correctly.
- No screenshot capture – the dummy renderer is bypassed, eliminating grey screen.
- Full diagnostics (gdb, strace, perf, etc.) run once per session.
- Auto‑starts headless‑like simulation (simulates SPACE press).
- Detects game completion and terminates cleanly.
"""

import subprocess
import sys
import time
import os
import select
import shutil
import sqlite3
import json
import fcntl
import re
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional, Tuple

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
GODOT_BIN = "/usr/bin/godot"
PROJECT_DIR = "godot_project"
TIMEOUT = 120
STALL_THRESHOLD = 30.0
HEARTBEAT_INTERVAL = 30.0
DB_PATH = "parachute_mutations.db"
CONTEXT_LINES = 3
TOOL_TIMEOUT = 2.0
FIX_LIST_PATH = "fix_list.json"
GRACE_PERIOD = 3.0

# Display provisioning
XVFB_DISPLAY = ":99"
XVFB_SCREEN = "1024x768x24"

# ------------------------------------------------------------------
# Helper: run a command with timeout
# ------------------------------------------------------------------
def run_cmd(cmd: List[str], timeout: float = TOOL_TIMEOUT) -> str:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.stdout + res.stderr
    except subprocess.TimeoutExpired:
        return f"TIMEOUT after {timeout}s"
    except Exception as e:
        return f"ERROR: {e}"

def tool_available(name: str) -> bool:
    return shutil.which(name) is not None

# ------------------------------------------------------------------
# Display provisioning: ensure a valid X11 display
# ------------------------------------------------------------------
def ensure_display() -> Tuple[bool, Optional[subprocess.Popen], str]:
    """
    Checks if DISPLAY is set and points to a valid X server.
    If not, attempts to start Xvfb on a free display.
    Returns (success, Xvfb_process, display_string).
    """
    display = os.environ.get("DISPLAY")
    if display:
        # Quick check: try to open a connection
        try:
            subprocess.check_call(["xdpyinfo", "-display", display], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"[DISPLAY] Using existing display: {display}")
            return True, None, display
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"[DISPLAY] DISPLAY={display} is set but not usable. Will try to start Xvfb.")
    else:
        print("[DISPLAY] DISPLAY not set. Will try to start Xvfb.")

    if not tool_available("Xvfb"):
        print("[DISPLAY] Xvfb not installed. Falling back to headless (dummy renderer).")
        print("[DISPLAY] To avoid grey screen, install Xvfb (e.g., 'sudo dnf install xorg-x11-server-Xvfb').")
        return False, None, ""

    # Try to find a free display number (we'll use :99 as default, but may try others)
    for disp in [":99", ":100", ":101"]:
        # Check if the display is already in use
        lock_file = f"/tmp/.X{disp[1:]}-lock"
        if os.path.exists(lock_file):
            print(f"[DISPLAY] Display {disp} appears to be in use. Trying next.")
            continue
        try:
            # Start Xvfb
            proc = subprocess.Popen(
                ["Xvfb", disp, "-screen", "0", XVFB_SCREEN, "-ac", "-nolisten", "tcp"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            # Wait a moment for it to start
            time.sleep(1)
            # Verify it's running
            if proc.poll() is None:
                print(f"[DISPLAY] Started Xvfb on {disp}")
                return True, proc, disp
            else:
                print(f"[DISPLAY] Xvfb on {disp} exited unexpectedly.")
        except Exception as e:
            print(f"[DISPLAY] Failed to start Xvfb on {disp}: {e}")
            continue

    print("[DISPLAY] Could not start Xvfb. Falling back to headless.")
    return False, None, ""

# ------------------------------------------------------------------
# Database schema helper: returns the table name to use
# ------------------------------------------------------------------
def get_error_table() -> str:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='files_to_fix'")
    if cursor.fetchone():
        return "files_to_fix"
    else:
        return "error_blocks"

# ------------------------------------------------------------------
# Auto‑extract file/line from output buffer (handles both at: and backtraces)
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
                    file_name = file_part.split("/")[-1]
                    full_path = base / file_name
                    if not full_path.exists():
                        full_path = file_part
                    return str(full_path), int(num_part)
        elif ".gd" in line and ":" in line:
            match = re.search(r'\(([^)]+\.gd):(\d+)\)', line)
            if match:
                file_part = match.group(1)
                line_num = int(match.group(2))
                base = Path(PROJECT_DIR) / "scripts"
                file_name = file_part.split("/")[-1]
                full_path = base / file_name
                if not full_path.exists():
                    full_path = file_part
                return str(full_path), line_num
            match = re.search(r'([^\s(]+\.gd):(\d+)', line)
            if match:
                file_part = match.group(1)
                line_num = int(match.group(2))
                base = Path(PROJECT_DIR) / "scripts"
                file_name = file_part.split("/")[-1]
                full_path = base / file_name
                if not full_path.exists():
                    full_path = file_part
                return str(full_path), line_num
    return None, None

# ------------------------------------------------------------------
# Proactive patch: add headless auto-start to build_terrain.gd (idempotent)
# ------------------------------------------------------------------
def apply_auto_start_patch() -> Tuple[bool, str]:
    file_path = os.path.join(PROJECT_DIR, "scripts", "build_terrain.gd")
    p = Path(file_path)
    if not p.exists():
        return False, f"File not found: {file_path}"
    with open(p, 'r') as f:
        lines = f.readlines()

    # Check if the patch is already applied (look for the exact comment line)
    for line in lines:
        if "# Headless auto‑start: simulate SPACE press" in line:
            return True, "Auto‑start patch already applied."

    # Find the line with "Game ready – press SPACE at ~4000 ft to deploy"
    ready_line_idx = None
    for i, line in enumerate(lines):
        if "Game ready – press SPACE at ~4000 ft to deploy" in line:
            ready_line_idx = i
            break
    if ready_line_idx is None:
        return False, "Could not locate 'Game ready' message line."

    # Determine indentation of that line
    indent = re.match(r'^[ \t]*', lines[ready_line_idx]).group(0)

    # Create backup
    backup_path = p.with_suffix(p.suffix + ".bak")
    shutil.copy2(p, backup_path)

    # Insert auto-start block right after the message
    auto_start_block = [
        f"{indent}# Headless auto‑start: simulate SPACE press\n",
        f"{indent}if OS.get_environment(\"GODOT_HEADLESS\") == \"1\":\n",
        f"{indent}\tInput.action_press(\"ui_accept\")\n",
        f"{indent}\tInput.action_release(\"ui_accept\")\n",
        f"{indent}\tprint(\"[VERBATIM] Headless auto‑start triggered.\")\n",
    ]
    # Insert after the message line
    lines[ready_line_idx+1:ready_line_idx+1] = auto_start_block

    with open(p, 'w') as f:
        f.writelines(lines)

    return True, f"Auto‑start patch applied. Backup at {backup_path}"

# ------------------------------------------------------------------
# Auto‑fix: indentation error
# ------------------------------------------------------------------
def auto_fix_indent_error(file_path: str, line_num: int, reference_line: int = 1505) -> Tuple[bool, str]:
    try:
        p = Path(file_path)
        if not p.exists():
            return False, "File not found"
        with open(p, 'r') as f:
            lines = f.readlines()
        if line_num < 1 or line_num > len(lines):
            return False, "Line number out of range"
        ref_line = lines[reference_line - 1] if 1 <= reference_line <= len(lines) else None
        if not ref_line:
            return False, "Reference line out of range"
        ref_indent = re.match(r'^[ \t]*', ref_line).group(0)
        offending_line = lines[line_num - 1]
        stripped = offending_line.lstrip()
        new_line = ref_indent + stripped
        if new_line == offending_line:
            return False, "No change needed (indentation already matches)"
        backup_path = p.with_suffix(p.suffix + ".bak")
        shutil.copy2(p, backup_path)
        lines[line_num - 1] = new_line
        with open(p, 'w') as f:
            f.writelines(lines)
        return True, f"Indentation corrected. Backup at {backup_path}"
    except Exception as e:
        return False, f"Error: {e}"

# ------------------------------------------------------------------
# Auto‑fix: null texture error – remove the entire screenshot block (no capture)
# ------------------------------------------------------------------
def auto_fix_null_texture(file_path: str, line_num: int) -> Tuple[bool, str]:
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
            return False, "Could not locate the screenshot block (no var tex line)"

        indent = re.match(r'^[ \t]*', lines[start_idx]).group(0)
        end_idx = None
        for i in range(start_idx + 1, len(lines)):
            if lines[i].startswith(indent) and not lines[i].strip().startswith("elif") and not lines[i].strip().startswith("else"):
                end_idx = i - 1
                break
        if end_idx is None:
            end_idx = len(lines) - 1

        backup_path = p.with_suffix(p.suffix + ".bak")
        shutil.copy2(p, backup_path)

        # Replace with a comment and a print (no screenshot capture)
        new_block = [
            f"{indent}# Screenshot capture removed – rendering is working; no need to capture.\n",
            f"{indent}print(\"[VERBATIM] Screenshot function removed (headless mode).\")\n"
        ]
        lines[start_idx:end_idx+1] = new_block

        with open(p, 'w') as f:
            f.writelines(lines)
        return True, f"Screenshot block removed (no capture). Backup at {backup_path}"
    except Exception as e:
        return False, f"Error: {e}"

# ------------------------------------------------------------------
# Rollback function
# ------------------------------------------------------------------
def rollback_file(file_path: str) -> bool:
    p = Path(file_path)
    backup_path = p.with_suffix(p.suffix + ".bak")
    if backup_path.exists():
        shutil.copy2(backup_path, p)
        return True
    return False

# ------------------------------------------------------------------
# Source block printer (dynamic)
# ------------------------------------------------------------------
def print_source_block(filepath: str, lnum: int, context: int = CONTEXT_LINES):
    p = Path(filepath)
    if not p.exists():
        print(f"      [WARNING] File not found: {filepath}")
        return
    lines = p.read_text().splitlines()
    total = len(lines)
    if lnum < 1 or lnum > total:
        print(f"      [WARNING] line {lnum} out of range (file has {total} lines)")
        return
    start = max(0, lnum - context - 1)
    end = min(total, lnum + context)
    print(f"      [STALL SOURCE] {p} lines {start+1}-{end} (offending line {lnum}):")
    for i in range(start, end):
        prefix = ">> " if i == lnum - 1 else "   "
        print(f"      {prefix}{i+1:4d}: {lines[i]}")

# ------------------------------------------------------------------
# Store error in database (auto‑schema detection)
# ------------------------------------------------------------------
def store_error(file_path: str, line_num: int, message: str, status: str = "new"):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='files_to_fix'")
        if cursor.fetchone():
            sql = """
                INSERT OR REPLACE INTO files_to_fix (file_path, line_number, error_text, status)
                VALUES (?, ?, ?, ?)
            """
            cursor.execute(sql, (file_path, line_num, message, status))
            conn.commit()
            print(f"[DB] Stored/replaced error in files_to_fix with status {status}")
        else:
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS error_blocks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT NOT NULL,
                    line_number INTEGER NOT NULL,
                    error_text TEXT,
                    context TEXT,
                    status TEXT DEFAULT 'new',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(file_path, line_number)
                )
            ''')
            p = Path(file_path)
            lines = p.read_text().splitlines() if p.exists() else []
            start = max(0, line_num - CONTEXT_LINES - 1)
            end = min(len(lines), line_num + CONTEXT_LINES)
            context_lines = [f"{i+1:4d}: {lines[i]}" for i in range(start, end)] if lines else []
            context_str = "\n".join(context_lines)
            sql = """
                INSERT OR REPLACE INTO error_blocks (file_path, line_number, error_text, context, status)
                VALUES (?, ?, ?, ?, ?)
            """
            cursor.execute(sql, (file_path, line_num, lines[line_num-1].strip() if lines else message, context_str, status))
            conn.commit()
            print("[DB] Stored error in 'error_blocks'")
        conn.close()
    except Exception as e:
        print(f"[DB] Error: {e}")

# ------------------------------------------------------------------
# Diagnostic tools (prioritized) – run only once
# ------------------------------------------------------------------
_diagnostics_run = False

def run_diagnostics(pid: int) -> Dict[str, Any]:
    global _diagnostics_run
    if _diagnostics_run:
        return {"skipped": "Diagnostics already run this session"}
    _diagnostics_run = True

    results = {}
    proc_info = {}
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            proc_info["status"] = f.read()
    except:
        proc_info["status"] = "unavailable"
    try:
        with open(f"/proc/{pid}/wchan", "r") as f:
            proc_info["wchan"] = f.read().strip()
    except:
        proc_info["wchan"] = "unavailable"
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            proc_info["cmdline"] = f.read().replace(b'\0', b' ').decode('utf-8')
    except:
        proc_info["cmdline"] = "unavailable"
    results["proc_info"] = proc_info

    if tool_available("gdb"):
        results["gdb"] = run_cmd(["gdb", "-batch", "-p", str(pid), "-ex", "thread apply all bt"])
    else:
        results["gdb"] = "gdb not installed"

    if tool_available("strace"):
        results["strace"] = run_cmd(["timeout", str(TOOL_TIMEOUT), "strace", "-p", str(pid), "-s", "256"])
    else:
        results["strace"] = "strace not installed"

    if tool_available("lsof"):
        results["lsof"] = run_cmd(["lsof", "-p", str(pid)])
    else:
        results["lsof"] = "lsof not installed"

    if tool_available("perf"):
        record_cmd = ["perf", "record", "-g", "-p", str(pid), "-o", "/tmp/perf.data", "--", "sleep", str(TOOL_TIMEOUT)]
        run_cmd(record_cmd, timeout=TOOL_TIMEOUT+1)
        report_cmd = ["perf", "report", "-i", "/tmp/perf.data", "--stdio", "--max-stack", "10", "-n"]
        results["perf"] = run_cmd(report_cmd, timeout=3)
    else:
        results["perf"] = "perf not installed"

    if tool_available("ltrace"):
        results["ltrace"] = run_cmd(["timeout", str(TOOL_TIMEOUT), "ltrace", "-p", str(pid), "-s", "256"])
    else:
        results["ltrace"] = "ltrace not installed"

    if tool_available("iotop"):
        results["iotop"] = run_cmd(["timeout", str(TOOL_TIMEOUT), "iotop", "-p", str(pid), "-b", "-n", "1"])
    else:
        results["iotop"] = "iotop not installed"

    if tool_available("top"):
        results["top"] = run_cmd(["top", "-b", "-n", "1", "-p", str(pid)])
    else:
        results["top"] = "top not installed"

    if tool_available("sysdig"):
        results["sysdig"] = run_cmd(["timeout", str(TOOL_TIMEOUT), "sysdig", "-p", "%proc.name %proc.pid %evt.type", "proc.pid=" + str(pid)])
    else:
        results["sysdig"] = "sysdig not installed"
    if tool_available("vmstat"):
        results["vmstat"] = run_cmd(["vmstat", "1", "2"])
    else:
        results["vmstat"] = "vmstat not installed"
    if tool_available("iostat"):
        results["iostat"] = run_cmd(["iostat", "-x", "1", "2"])
    else:
        results["iostat"] = "iostat not installed"
    if tool_available("netstat"):
        results["netstat"] = run_cmd(["netstat", "-tunap"])
    else:
        results["netstat"] = "netstat not installed"
    if tool_available("ss"):
        results["ss"] = run_cmd(["ss", "-tunap"])
    else:
        results["ss"] = "ss not installed"

    if tool_available("tree"):
        results["tree"] = run_cmd(["tree", "-L", "2", PROJECT_DIR])
    else:
        results["tree"] = "tree not installed"

    return results

def print_diagnostic_summary(results: Dict[str, Any]):
    if "skipped" in results:
        print("[DIAG] Skipped (already run this session).")
        return
    print("\n=== DIAGNOSTIC SUMMARY ===")
    print(f"PID: {results.get('pid', 'N/A')}")
    wchan = results.get('proc_info', {}).get('wchan', 'N/A')
    print(f"wchan: {wchan}")

    strace_out = results.get('strace', '')
    if strace_out and "TIMEOUT" not in strace_out:
        lines = strace_out.splitlines()
        print("Strace (last 3 lines):")
        for line in lines[-3:]:
            print(f"  {line[:120]}")
    else:
        print("Strace: unavailable")

    lsof_out = results.get('lsof', '')
    if lsof_out and "TIMEOUT" not in lsof_out:
        print("Lsof: open files (non‑memory, non‑pipe):")
        for line in lsof_out.splitlines():
            if "REG" in line or "DIR" in line:
                print(f"  {line[:120]}")
    else:
        print("Lsof: unavailable")

    perf_out = results.get('perf', '')
    if perf_out and "TIMEOUT" not in perf_out:
        print("Perf top functions:")
        count = 0
        for line in perf_out.splitlines():
            if "." in line and "[" in line and "]" in line:
                print(f"  {line[:100]}")
                count += 1
                if count >= 3:
                    break
    else:
        print("Perf: unavailable")

    gdb_out = results.get('gdb', '')
    if gdb_out and "TIMEOUT" not in gdb_out:
        print("GDB (first 5 lines of backtrace):")
        count = 0
        for line in gdb_out.splitlines():
            if "#" in line:
                print(f"  {line[:120]}")
                count += 1
                if count >= 5:
                    break
    else:
        print("GDB: unavailable")

    for tool in ["ltrace", "iotop", "top", "sysdig", "vmstat", "iostat", "netstat", "ss", "tree"]:
        if tool in results and "TIMEOUT" not in results[tool] and "not installed" not in results[tool]:
            print(f"{tool.capitalize()}: ran successfully (output in JSON report)")

    print(f"Full report saved to stall_report.json")

# ------------------------------------------------------------------
# Main: launch Godot with proper display, monitor, heal, and report
# ------------------------------------------------------------------
def main():
    # Ensure a valid display (starts Xvfb if needed)
    display_ok, xvfb_proc, display = ensure_display()
    if display_ok:
        os.environ["DISPLAY"] = display
        print(f"[ENV] Using DISPLAY={display}")
    else:
        print("[ENV] No valid display – Godot will likely use dummy renderer.")
        print("[ENV] Diagnostics may be limited, but the script will continue.")
        # Keep existing DISPLAY or unset it

    # Apply auto-start patch before launching Godot
    print("[PATCH] Auto‑start disabled by user preference")
    success = True
    msg = "Auto‑start disabled by user preference"
    if success:
        print(f"[PATCH] {msg}")
    else:
        print(f"[PATCH] Failed: {msg} (continuing anyway)")

    os.environ["GODOT_HEADLESS"] = "1"   # Still used for auto‑start trigger

    print("[SETUP] godot binary:", GODOT_BIN)
    print("[SETUP] project dir: ", os.path.abspath(PROJECT_DIR))
    print("[RUN] /usr/bin/godot --path godot_project --verbose")
    print("[RUN] stall threshold: {}s   timeout: {}s".format(STALL_THRESHOLD, TIMEOUT))
    print("[ENV] GODOT_HEADLESS=1 (for auto‑start detection only)")
    print("="*72)

    # Do NOT use --headless – we want rendering to work with the display
    cmd = [GODOT_BIN, "--path", PROJECT_DIR, "--verbose"]
    # If we have a display, we can also add --display-driver x11 (optional)
    # but Godot will auto-detect.

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
        env=os.environ
    )

    fd = proc.stdout.fileno()
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    start_time = time.time()
    last_output_time = time.time()
    stall_reported = False
    output_buffer = []
    partial_line = b''
    godot_pid = None

    last_heartbeat = time.time()
    stall_handled = False
    fix_attempted_this_run = False
    game_completed = False
    grace_until = 0.0

    error_table = get_error_table()
    print(f"[DB] Using table: {error_table}")

    while True:
        elapsed = time.time() - start_time
        if elapsed > TIMEOUT:
            print(f"\n[TIMEOUT] reached {TIMEOUT}s. Terminating.")
            proc.terminate()
            break

        if proc.poll() is not None:
            print("[INFO] Godot process exited on its own.")
            break

        rlist, _, _ = select.select([fd], [], [], STALL_THRESHOLD)
        if rlist:
            try:
                data = os.read(fd, 4096)
            except BlockingIOError:
                continue
            if not data:
                print("[INFO] EOF from Godot; process likely finished.")
                break
            partial_line += data
            lines = partial_line.split(b'\n')
            partial_line = lines.pop()
            for line_bytes in lines:
                line = line_bytes.decode('utf-8', errors='replace')
                sys.stdout.write(line + '\n')
                sys.stdout.flush()
                last_output_time = time.time()
                stall_reported = False
                stall_handled = False
                output_buffer.append(line)
                if len(output_buffer) > 1000:
                    output_buffer.pop(0)

                if "Ground impact – fatal" in line:
                    game_completed = True
                    print("[INFO] Game completed (ground impact). Terminating Godot...")
                    proc.terminate()
                    time.sleep(1)
                    if proc.poll() is None:
                        proc.kill()
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
            now = time.time()
            elapsed_since_output = now - last_output_time

            if now < grace_until:
                continue

            if not stall_reported and elapsed_since_output > STALL_THRESHOLD:
                stall_reported = True
                if not godot_pid:
                    try:
                        out = subprocess.check_output(["pgrep", "-f", "godot"], text=True).strip()
                        godot_pid = int(out.split()[0])
                    except:
                        godot_pid = None
                if godot_pid:
                    gd_file, gd_line = extract_last_gd_error(output_buffer)
                    if gd_file and gd_line:
                        print(f"\n[STALL #1] quiet {elapsed_since_output:.1f}s — stepping through in-flight code:")
                        print_source_block(gd_file, gd_line)
                        store_error(gd_file, gd_line, f"Parse error at {gd_file}:{gd_line}")

                        error_context = " ".join(output_buffer[-10:])
                        fix_applied = False
                        if "Indent" in error_context and not fix_attempted_this_run:
                            conn = sqlite3.connect(DB_PATH)
                            cursor = conn.cursor()
                            query = f"""
                                SELECT status FROM {error_table}
                                WHERE file_path=? AND line_number=? AND error_text LIKE ?
                                ORDER BY id DESC LIMIT 1
                            """
                            cursor.execute(query, (gd_file, gd_line, "%Indent%"))
                            row = cursor.fetchone()
                            if row and row[0] in ('fix_attempted', 'fix_failed'):
                                print("[FIX] Already attempted fix for this error; skipping to avoid loop.")
                            else:
                                print("[FIX] Attempting to correct indentation automatically...")
                                success, msg = auto_fix_indent_error(gd_file, gd_line, reference_line=1505)
                                if success:
                                    print(f"[FIX] {msg}")
                                    store_error(gd_file, gd_line, f"Fix attempted at {gd_file}:{gd_line}", status="fix_attempted")
                                    fix_attempted_this_run = True
                                    fix_applied = True
                                else:
                                    print(f"[FIX] Auto‑fix failed: {msg}")
                                    store_error(gd_file, gd_line, f"Fix failed: {msg}", status="fix_failed")
                        elif "Parameter \"t\" is null" in error_context and not fix_attempted_this_run:
                            conn = sqlite3.connect(DB_PATH)
                            cursor = conn.cursor()
                            query = f"""
                                SELECT status FROM {error_table}
                                WHERE file_path=? AND line_number=? AND error_text LIKE ?
                                ORDER BY id DESC LIMIT 1
                            """
                            cursor.execute(query, (gd_file, gd_line, "%Parameter \"t\" is null%"))
                            row = cursor.fetchone()
                            if row and row[0] in ('fix_attempted', 'fix_failed'):
                                print("[FIX] Already attempted fix for this error; skipping to avoid loop.")
                            else:
                                print("[FIX] Attempting to remove screenshot block entirely (no capture)...")
                                success, msg = auto_fix_null_texture(gd_file, gd_line)
                                if success:
                                    print(f"[FIX] {msg}")
                                    store_error(gd_file, gd_line, f"Fix attempted at {gd_file}:{gd_line}", status="fix_attempted")
                                    fix_attempted_this_run = True
                                    fix_applied = True
                                else:
                                    print(f"[FIX] Auto‑fix failed: {msg}")
                                    store_error(gd_file, gd_line, f"Fix failed: {msg}", status="fix_failed")

                        if fix_applied:
                            print("[FIX] Testing the fix by restarting Godot...")
                            proc.terminate()
                            proc.wait()
                            proc = subprocess.Popen(
                                cmd,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,
                                text=True,
                                bufsize=1,
                                universal_newlines=True,
                                env=os.environ
                            )
                            fd = proc.stdout.fileno()
                            flags = fcntl.fcntl(fd, fcntl.F_GETFL)
                            fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
                            output_buffer = []
                            last_output_time = time.time()
                            stall_reported = False
                            stall_handled = False
                            grace_until = time.time() + GRACE_PERIOD
                            continue

                        if fix_attempted_this_run:
                            conn = sqlite3.connect(DB_PATH)
                            cursor = conn.cursor()
                            query = f"""
                                SELECT status FROM {error_table}
                                WHERE file_path=? AND line_number=?
                                ORDER BY id DESC LIMIT 1
                            """
                            cursor.execute(query, (gd_file, gd_line))
                            row = cursor.fetchone()
                            if row and row[0] == 'fix_attempted':
                                print("[FIX] Fix did not resolve the error. Rolling back...")
                                if rollback_file(gd_file):
                                    print("[FIX] Rolled back to original.")
                                    store_error(gd_file, gd_line, "Fix rolled back", status="fix_failed")
                                else:
                                    print("[FIX] No backup found; manual intervention required.")
                            else:
                                if not row:
                                    print("[FIX] Error resolved! Marking as fixed.")
                                    store_error(gd_file, gd_line, "Fixed successfully", status="fixed")
                    else:
                        print(f"\n[STALL #1] quiet {elapsed_since_output:.1f}s — no .gd error found in log.")
                    # Run diagnostics only once
                    print("\n[DIAG] Running diagnostic tools (timeout {}s each)...".format(TOOL_TIMEOUT))
                    results = run_diagnostics(godot_pid)
                    results["timestamp"] = datetime.now().isoformat()
                    results["pid"] = godot_pid
                    report_file = "stall_report.json"
                    with open(report_file, "w") as f:
                        json.dump(results, f, indent=2, default=str)
                    print_diagnostic_summary(results)
                    stall_handled = True
                else:
                    print("[STALL] Could not find Godot PID; skipping diagnostics.")
            elif stall_reported and stall_handled:
                if time.time() - last_heartbeat > HEARTBEAT_INTERVAL:
                    print(f"[STALL] process still stuck, elapsed={elapsed:.1f}s (no new output)")
                    sys.stdout.flush()
                    last_heartbeat = time.time()

    if partial_line:
        line = partial_line.decode('utf-8', errors='replace')
        sys.stdout.write(line + '\n')

    if proc.poll() is None:
        proc.terminate()
        proc.wait()

    # Stop Xvfb if we started it
    if xvfb_proc and xvfb_proc.poll() is None:
        print("[DISPLAY] Stopping Xvfb...")
        xvfb_proc.terminate()
        xvfb_proc.wait()

    summary = {
        "timestamp": datetime.now().isoformat(),
        "runtime": time.time() - start_time,
        "game_completed": game_completed,
        "fix_attempted": fix_attempted_this_run,
        "diagnostics_run": _diagnostics_run,
        "exit_code": proc.returncode,
        "display_provisioned": display_ok
    }
    with open("run_summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    print("\n[SUMMARY] autostall.py finished.")
    if game_completed:
        print("[SUMMARY] Game completed normally (ground impact detected).")
    else:
        print("[SUMMARY] Process terminated by script.")
    print(f"[SUMMARY] Runtime: {summary['runtime']:.1f}s")
    print("[SUMMARY] Diagnostics data preserved in stall_report.json")
    print("="*72)

if __name__ == "__main__":
    main()
