#!/usr/bin/env python3
"""
controlled_edit.py — Guarded, structured file edit with transparency.

Supports:
  --dry-run          Print context, diff, and backup info without writing.
  --apply            Actually apply the change (after confirmation, unless -y used).

This script targets the rotation line in build_terrain.gd:
  _character.rotation.y = _cam_azimuth
and replaces it with a commented-out version to match plane behaviour.

All edits are guarded by DESIGN BY CONTRACT: exactly one occurrence must exist,
otherwise the script aborts with a clear message.

Read-after-write consistency and verification (grep) are performed when applying.
"""

import sys
import os
import shutil
import subprocess
import difflib
import datetime

# ----------------------------------------------------------------------
# Configuration: what to change, where, and how.
# ----------------------------------------------------------------------
TARGET_FILE = "godot_project/scripts/build_terrain.gd"
OLD_LINE = "_character.rotation.y = _cam_azimuth"
NEW_LINE = "# _character.rotation.y = _cam_azimuth  # removed to match plane behaviour"
CONTEXT_LINES = 5          # lines before/after for display
BACKUP_SUFFIX = ".bak"     # will be appended with timestamp


# ----------------------------------------------------------------------
# Helper: create a timestamped backup of the file.
# ----------------------------------------------------------------------
def create_backup(file_path: str) -> str:
    """Create a backup of file_path with a timestamp, return backup path."""
    if not os.path.exists(file_path):
        return None
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = file_path + BACKUP_SUFFIX + "_" + timestamp
    shutil.copy2(file_path, backup_path)
    return backup_path


# ----------------------------------------------------------------------
# Helper: show context around a specific line number.
# ----------------------------------------------------------------------
def show_context(lines: list, line_num: int, context: int = CONTEXT_LINES) -> None:
    """Print CONTEXT_LINES lines before and after the given line number (0-based)."""
    start = max(0, line_num - context)
    end = min(len(lines), line_num + context + 1)
    print(f"--- Context (lines {start+1}–{end}):")
    for i in range(start, end):
        marker = ">" if i == line_num else " "
        print(f"{marker}{i+1:4d}: {lines[i]}")
    print()


# ----------------------------------------------------------------------
# Helper: show unified diff between old and new content.
# ----------------------------------------------------------------------
def show_diff(old_content: str, new_content: str, file_path: str) -> None:
    """Print a unified diff of the change."""
    diff = difflib.unified_diff(
        old_content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile="a/" + file_path,
        tofile="b/" + file_path,
        n=3
    )
    print("--- Unified diff:")
    print("".join(diff))
    print()


# ----------------------------------------------------------------------
# Helper: verify that the old line no longer appears (grep check).
# ----------------------------------------------------------------------
def verify_old_line_gone(file_path: str, old_line: str) -> bool:
    """Run grep -n on the file to see if old_line still exists."""
    try:
        result = subprocess.run(
            ["grep", "-n", old_line, file_path],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print(f"VERIFICATION FAILED: old line still present:\n{result.stdout}")
            return False
        else:
            print("VERIFICATION PASSED: old line no longer found in file.")
            return True
    except Exception as e:
        print(f"VERIFICATION ERROR: grep failed: {e}")
        return False


# ----------------------------------------------------------------------
# Main function: process the file with dry-run or apply.
# ----------------------------------------------------------------------
def main():
    # Parse arguments: --dry-run or --apply
    if len(sys.argv) != 2 or sys.argv[1] not in ("--dry-run", "--apply"):
        print("Usage: python3 controlled_edit.py --dry-run | --apply")
        print("  --dry-run  : Show context, diff, backup info, but do NOT write.")
        print("  --apply    : Apply the change (after confirmation).")
        sys.exit(1)

    dry_run = (sys.argv[1] == "--dry-run")
    apply_mode = (sys.argv[1] == "--apply")

    # Resolve full path for transparency
    full_path = os.path.abspath(TARGET_FILE)
    print(f"Target file: {full_path}")

    # Check file existence
    if not os.path.exists(full_path):
        print(f"ERROR: File not found: {full_path}")
        sys.exit(1)

    # Read current content
    with open(full_path, "r") as f:
        old_content = f.read()

    # Guard: exactly one occurrence of the old line.
    count = old_content.count(OLD_LINE)
    if count != 1:
        print(f"PRECONDITION VIOLATION: Expected exactly 1 occurrence of:")
        print(f"  {OLD_LINE!r}")
        print(f"Found {count} occurrences. Refusing to proceed.")
        sys.exit(1)

    # Find the line number (0-based) of the first occurrence.
    lines = old_content.splitlines()
    line_num = None
    for idx, line in enumerate(lines):
        if line.strip() == OLD_LINE:
            line_num = idx
            break
    if line_num is None:
        print("INTERNAL ERROR: Could not locate line number despite count==1.")
        sys.exit(1)

    # Show context and diff
    show_context(lines, line_num)
    new_content = old_content.replace(OLD_LINE, NEW_LINE, 1)
    show_diff(old_content, new_content, TARGET_FILE)

    # If dry-run, stop here.
    if dry_run:
        print("--dry-run: No changes written. Backup would be created at:")
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        print(f"  {full_path}{BACKUP_SUFFIX}_{timestamp}")
        print("Exiting.")
        sys.exit(0)

    # Apply mode: ask for confirmation unless we add a -y flag later.
    print("\nDo you want to apply this change? (y/n): ", end="")
    response = sys.stdin.readline().strip().lower()
    if response != 'y':
        print("Aborted by user.")
        sys.exit(0)

    # Create backup
    backup_path = create_backup(full_path)
    if backup_path:
        print(f"Backup created: {backup_path}")

    # Write the new content
    try:
        with open(full_path, "w") as f:
            f.write(new_content)
        print("Write completed.")
    except Exception as e:
        print(f"ERROR: Failed to write file: {e}")
        sys.exit(1)

    # Read-after-write consistency check
    with open(full_path, "r") as f:
        written_content = f.read()
    if written_content != new_content:
        print("READ-AFTER-WRITE FAILURE: written content does not match expected.")
        print("Attempting to restore from backup...")
        if backup_path and os.path.exists(backup_path):
            shutil.copy2(backup_path, full_path)
            print("Restored from backup.")
        sys.exit(1)
    else:
        print("Read-after-write consistency: OK.")

    # Verification: grep for the old line (should be gone)
    if verify_old_line_gone(full_path, OLD_LINE):
        print("SUCCESS: Change applied and verified.")
    else:
        print("WARNING: Verification failed — old line still appears.")
        print("You may need to inspect the file manually.")
        sys.exit(1)


if __name__ == "__main__":
    main()
