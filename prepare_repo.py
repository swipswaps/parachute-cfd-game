#!/usr/bin/env python3
"""
prepare_repo.py – Audit Godot project for repository readiness.

This script scans your project directory, reports on existing essential files,
identifies what's missing, and offers to create a proper .gitignore.

Usage:
    python3 prepare_repo.py            # run audit and report
    python3 prepare_repo.py --dry-run  # preview without writing anything
    python3 prepare_repo.py --generate-gitignore  # write a .gitignore file
"""

import os
import sys
import shutil
import argparse
from datetime import datetime
from pathlib import Path

# ----------------------------------------------------------------------
# CONFIGURATION: Paths to check (relative to current directory)
# ----------------------------------------------------------------------
ESSENTIAL_PATHS = [
    "godot_project/project.godot",
    "godot_project/scripts",
    "godot_project/scenes",
]

RECOMMENDED_PATHS = [
    "godot_project/assets",
    "godot_project/addons",
    "README.md",
]

IGNORE_PATTERNS = [
    ".godot/",
    ".import/",
    "*.backup_*",
    "*.tmp",
    "__pycache__/",
    "*.pyc",
    "*.db",
    "*.gd.uid",
]

# ----------------------------------------------------------------------
# Core functions
# ----------------------------------------------------------------------
def check_paths(paths, label):
    """Check existence of given paths and return status."""
    status = {}
    for p in paths:
        full = Path(p)
        exists = full.exists()
        status[p] = exists
    return status

def report_status(status, label):
    """Print a formatted report of path statuses."""
    print(f"\n--- {label} ---")
    all_ok = True
    for path, exists in status.items():
        symbol = "✅" if exists else "❌"
        print(f"  {symbol} {path}")
        if not exists:
            all_ok = False
    return all_ok

def generate_gitignore_content():
    """Return a .gitignore content as a string."""
    lines = [
        "# Godot 4+ generated folders",
        ".godot/",
        ".import/",
        "",
        "# Backup and temporary files",
        "*.backup_*",
        "*.tmp",
        "",
        "# Python cache",
        "__pycache__/",
        "*.pyc",
        "",
        "# Local databases (unless game data)",
        "*.db",
        "",
        "# Godot script UID files (optional)",
        "*.gd.uid",
        "",
        "# Editor-specific (optional)",
        ".vscode/",
        ".idea/",
    ]
    return "\n".join(lines)

def write_gitignore():
    """Write .gitignore file with backup if existing."""
    gitignore_path = Path(".gitignore")
    if gitignore_path.exists():
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = gitignore_path.with_name(f".gitignore.backup_{timestamp}")
        shutil.copy2(gitignore_path, backup)
        print(f"📦 Existing .gitignore backed up to {backup}")
    content = generate_gitignore_content()
    with open(gitignore_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("✅ Created .gitignore in current directory.")

def main():
    parser = argparse.ArgumentParser(
        description="Audit Godot project for repository completeness."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview the report without modifying anything."
    )
    parser.add_argument(
        "--generate-gitignore",
        action="store_true",
        help="Generate a .gitignore file (ignores --dry-run)."
    )
    args = parser.parse_args()

    if args.generate_gitignore:
        if args.dry_run:
            print("--- .gitignore content (dry-run) ---")
            print(generate_gitignore_content())
            return
        write_gitignore()
        return

    # ---- Audit ----
    print("🔍 Scanning for essential and recommended files...\n")

    essential_status = check_paths(ESSENTIAL_PATHS, "Essential")
    recommended_status = check_paths(RECOMMENDED_PATHS, "Recommended")

    essential_ok = report_status(essential_status, "Essential")
    recommended_ok = report_status(recommended_status, "Recommended")

    # ---- Summary ----
    print("\n--- Summary ---")
    if essential_ok:
        print("✅ All essential files are present.")
    else:
        print("❌ Some essential files are missing. The project may not run.")

    if recommended_ok:
        print("✅ All recommended files are present.")
    else:
        print("⚠️ Some recommended files are missing (e.g., README.md, assets).")

    # ---- .gitignore ----
    gitignore_exists = Path(".gitignore").exists()
    print(f"\n.gitignore: {'✅ exists' if gitignore_exists else '❌ missing'}")
    if not gitignore_exists and not args.dry_run:
        print("   → Run with --generate-gitignore to create one.")

    # ---- What to commit ----
    print("\n--- What to commit (typical) ---")
    print("  - godot_project/ (all .gd, .tscn, .import, assets)")
    print("  - README.md")
    print("  - .gitignore (if generated)")
    print("  - controlled_edit.py (optional, but good to keep)")

    if args.dry_run:
        print("\n[DRY RUN] No files were modified.")

if __name__ == "__main__":
    main()
