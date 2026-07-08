#!/usr/bin/env python3
"""
controlled_edit.py – Guarded, controlled edits to source files.

This script applies a set of predefined replacements to specified files.
It strictly enforces that each old text matches exactly once before replacing,
aborts if not, and provides a dry-run mode showing line numbers, context,
and unified diffs.

Design by Contract: every replacement is guarded by `text.count(old) == 1`.
Read-after-write consistency verifies the change landed.
Timestamped backups are created before any write.

Usage:
    python3 controlled_edit.py --dry-run   # preview changes
    python3 controlled_edit.py             # apply changes
    python3 controlled_edit.py --help      # full help

Configuration: Edit the EDITS list below to define the operations.
Each entry is a dict with keys:
    file   : path to the target file
    old    : exact string to replace (must occur exactly once)
    new    : replacement string

The script is self-contained, stdlib only.
"""

import os
import sys
import re
import shutil
import argparse
import difflib
from datetime import datetime
from pathlib import Path

# ----------------------------------------------------------------------
# CONFIGURATION: Define the edits to apply.
# Each operation must have `old` occur exactly once in the file.
# ----------------------------------------------------------------------
EDITS = [
    {
        "file": "godot_project/scripts/build_terrain.gd",
        "old": (
            "\t# Camera follows character for all other states\n"
            "\tif is_instance_valid(_character) and is_instance_valid(_camera):\n"
            "\t\tvar target = _character.global_position\n"
            "\t\tvar offset = Vector3(0, 0, -_cam_distance)\n"
            "\t\toffset = offset.rotated(Vector3.UP, _cam_azimuth)\n"
            "\t\toffset = offset.rotated(Vector3.RIGHT, _cam_elevation)\n"
            "\t\t_camera.global_position = target + offset\n"
            "\t\t_camera.look_at(target, Vector3.UP)\n"
        ),
        "new": (
            "\t# Camera follows character for all post‑plane states\n"
            "\tif _game_state != GameState.IN_PLANE and _character and _camera:\n"
            "\t\t_camera.global_position = _character.global_position + Vector3(0, 10, -15)\n"
            "\t\t_camera.look_at(_character.global_position, Vector3.UP)\n"
            "\t\tprint(\"[DIAG] _physics_process: camera target set to character (state: \", _game_state, \")\")\n"
        ),
    },
    {
        "file": "godot_project/scripts/build_terrain.gd",
        "old": (
            "\t\t_hud_labels[4].text = \"TURN: %d\" % (_turn_input * 100)\n"
        ),
        "new": (
            "\t\t_hud_labels[4].text = \"TURN: %d\" % (_turn_input * 100)\n"
            "\t\t_hud_labels[0].text = \"ALT: %.0f ft\" % _character.global_position.y\n"
        ),
    },
]

# ----------------------------------------------------------------------
# Helper: find line number of a substring in a file content.
# ----------------------------------------------------------------------
def find_line_number(content, substring):
    """Return the 1-based line number of the first occurrence of substring,
    or None if not found."""
    lines = content.splitlines(keepends=True)
    for idx, line in enumerate(lines, start=1):
        if substring in line:
            return idx
    return None

# ----------------------------------------------------------------------
# Helper: print context (3 lines before/after) for a match.
# ----------------------------------------------------------------------
def print_context(content, substring, context_lines=3):
    """Print lines around the match with line numbers."""
    lines = content.splitlines(keepends=True)
    line_no = None
    for idx, line in enumerate(lines, start=1):
        if substring in line:
            line_no = idx
            break
    if line_no is None:
        print("[CONTEXT] Substring not found in content.")
        return
    start = max(0, line_no - context_lines - 1)
    end = min(len(lines), line_no + context_lines)
    print(f"[CONTEXT] Lines {start+1} to {end} (match at line {line_no}):")
    for i in range(start, end):
        prefix = ">" if i == line_no - 1 else " "
        print(f"{prefix}{i+1:4d}: {lines[i].rstrip()}")

# ----------------------------------------------------------------------
# Core function: apply a single guarded edit.
# ----------------------------------------------------------------------
def apply_edit(file_path, old_text, new_text, dry_run=False):
    """
    Apply a replacement to the file, ensuring old_text occurs exactly once.
    Returns (success, message, diff_lines).
    """
    if not os.path.isfile(file_path):
        return False, f"File not found: {file_path}", []

    # Read the file
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Guard: count occurrences
    count = content.count(old_text)
    if count != 1:
        return False, f"Guard failed: old text appears {count} times (expected 1) in {file_path}", []

    # If dry-run, show context and diff without writing
    if dry_run:
        print(f"\n[DRY RUN] Edit for {file_path}:")
        print_context(content, old_text)
        # Generate unified diff
        new_content = content.replace(old_text, new_text, 1)
        diff = difflib.unified_diff(
            content.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=file_path,
            tofile=file_path + " (new)"
        )
        diff_lines = list(diff)
        print("Unified diff:")
        sys.stdout.writelines(diff_lines)
        return True, "Dry-run completed", diff_lines

    # ---- Actual write ----
    # Create timestamped backup
    backup_path = f"{file_path}.backup_{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(file_path, backup_path)
    print(f"Backup created: {backup_path}")

    # Perform replacement
    new_content = content.replace(old_text, new_text, 1)

    # Write new content
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    # Read-after-write consistency check
    with open(file_path, 'r', encoding='utf-8') as f:
        written = f.read()
    if written != new_content:
        # Restore backup
        shutil.copy2(backup_path, file_path)
        return False, "Read-after-write mismatch; rolled back", []

    # Generate diff for reporting
    diff = difflib.unified_diff(
        content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile=file_path,
        tofile=file_path + " (new)"
    )
    diff_lines = list(diff)

    print(f"Applied edit to {file_path}")
    return True, "Edit applied successfully", diff_lines

# ----------------------------------------------------------------------
# Main: process all edits.
# ----------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Apply guarded controlled edits to source files."
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Preview changes without writing any files."
    )
    args = parser.parse_args()

    all_success = True
    for edit in EDITS:
        file_path = edit.get("file")
        old_text = edit.get("old")
        new_text = edit.get("new")

        if not file_path or old_text is None or new_text is None:
            print(f"Skipping invalid edit entry: {edit}")
            continue

        success, msg, diff_lines = apply_edit(file_path, old_text, new_text, args.dry_run)
        if not success:
            print(f"ERROR: {msg}")
            all_success = False

    if not all_success:
        print("One or more edits failed. No changes were applied (dry-run?)")
        sys.exit(1)

    if args.dry_run:
        print("Dry-run completed. No files were changed.")
    else:
        print("All edits applied successfully. Backups are available.")

if __name__ == "__main__":
    main()
