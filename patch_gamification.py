#!/usr/bin/env python3
import sys
import datetime
import shutil
import re

def log_result(op, ok, detail):
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if ok else "FAILURE"
    print(f"[{ts}] [{status}] {op}: {detail}", file=sys.stderr)

def get_leading_ws(line):
    ws = ""
    for c in line:
        if c in "\t ":
            ws += c
        else:
            break
    return ws

TARGET = "autostall_fixed.py"
BACKUP = f"{TARGET}.bak.{datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')}"

# Read live file
with open(TARGET, "r", encoding="utf-8") as f:
    content = f.read()
lines = content.splitlines()

# Locate the gamification block start: "# -- Gamification --"
start_idx = None
for i, line in enumerate(lines):
    if line.strip() == "# -- Gamification --":
        start_idx = i
        break
if start_idx is None:
    log_result("locate_start", False, "Could not find '# -- Gamification --'")
    sys.exit(1)
log_result("locate_start", True, f"Found at line {start_idx+1}")

# Find end of the block: next line that starts with "def " at column 0
end_idx = None
for i in range(start_idx + 1, len(lines)):
    if re.match(r'^def\s+', lines[i]) and not lines[i].startswith((' ', '\t')):
        end_idx = i
        break
if end_idx is None:
    end_idx = len(lines)

# Extract old block (from start_idx to end_idx-1)
old_lines = lines[start_idx:end_idx]
old_block = "\n".join(old_lines)

# Count matches
if content.count(old_block) != 1:
    log_result("precondition", False, f"Expected 1 match, found {content.count(old_block)}")
    sys.exit(1)

# Build new block
new_block = '''    # -- Gamification (with retry on DB lock) --
    # Ensure any existing DB connection is closed before we start fresh
    if db_conn:
        db_conn.close()
        db_conn = None

    # Give the OS a moment to release the file lock from the just‑exited Godot
    time.sleep(0.5)

    def retry_db_operation(operation, *args, max_attempts=5, **kwargs):
        """Execute a DB operation with exponential backoff on SQLITE_BUSY."""
        for attempt in range(max_attempts):
            try:
                return operation(*args, **kwargs)
            except sqlite3.OperationalError as e:
                if "database is locked" in str(e) and attempt < max_attempts - 1:
                    wait = 0.5 * (2 ** attempt)  # 0.5, 1, 2, 4, 8 seconds
                    print(f"[DB] Locked, retrying in {wait:.1f}s (attempt {attempt+1}/{max_attempts})")
                    time.sleep(wait)
                else:
                    raise  # Re‑raise if out of attempts or other error
        return None  # fallback

    try:
        # init_db() might create tables – retry if locked
        retry_db_operation(init_db)
        learn_indentation()  # this doesn't touch the DB, can stay outside

        # start_flight opens a new connection and writes – retry
        _flight_id = retry_db_operation(start_flight)

        _pilot_name = 'default'
        if _flight_id is not None:
            outcome = "landed" if game_completed else ("aborted" if proc.returncode == 0 else "crashed")
            bugs_encountered = sum(1 for l in output_buffer if "SCRIPT ERROR" in l or "ERROR:" in l)
            # end_flight also writes – retry
            retry_db_operation(
                end_flight,
                _flight_id, outcome,
                bugs_encountered=bugs_encountered,
                bugs_fixed=fix_attempted_this_run,
                notes=f"fix_attempted={fix_attempted_this_run}"
            )
    except sqlite3.OperationalError as e:
        print(f"[ERROR] Gamification log failed after retries: {e}")
        # Optionally write a fallback log to a flat file for manual import
        with open("gamification_fallback.log", "a") as f:
            f.write(f"{datetime.now().isoformat()} | {e}\\n")
'''

# Preserve leading whitespace: the old block is indented (4 spaces) inside main.
# We'll extract the indentation from the first line of old_block.
first_line = old_lines[0]
indent = get_leading_ws(first_line)  # should be "    "
# The new_block we defined is already indented with 4 spaces, but we can adjust.
# We'll ensure new_block is indented correctly: we'll indent it to match the original.
# Since we wrote new_block with 4 spaces, it should match. We'll keep as is.

# Apply patch
patched_content = content.replace(old_block, new_block, 1)

# Write with backup
shutil.copy2(TARGET, BACKUP)
with open(TARGET, "w", encoding="utf-8") as f:
    f.write(patched_content)

# Read back and verify
with open(TARGET, "r", encoding="utf-8") as f:
    written = f.read()
if written != patched_content:
    log_result("read_after_write", False, "Mismatch, restoring backup")
    shutil.copy2(BACKUP, TARGET)
    sys.exit(1)
log_result("read_after_write", True, "Patch applied successfully")

# Optional: check that the new block is present
if "# -- Gamification (with retry on DB lock) --" not in written:
    log_result("semantic_check", False, "New block not found after patch")
    shutil.copy2(BACKUP, TARGET)
    sys.exit(1)
log_result("semantic_check", True, "New block present")
print("PATCH SUCCESS")
sys.exit(0)
