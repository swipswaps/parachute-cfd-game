#!/usr/bin/env python3
"""
backup_and_clean.py – Back up untracked files, then clean, commit, push.

Usage:
    python3 backup_and_clean.py --dry-run   # preview only
    python3 backup_and_clean.py             # interactive
"""

import os
import sys
import subprocess
import shutil
from datetime import datetime
from pathlib import Path

# ----------------------------------------------------------------------
# Extra .gitignore patterns (appended)
# ----------------------------------------------------------------------
EXTRA_IGNORE = """
# Logs and audit outputs
*.log
audit_logs/

# Temporary and backup files
*.backup_*
*.tmp
*.bak
*.orig
*.swp

# Python scripts that are not core tools
*.pyc
__pycache__/
*.sh
*.py
!controlled_edit.py
!prepare_repo.py
!backup_and_clean.py

# Godot editor and cache
.godot/
.import/

# Local databases
*.db
*.db-shm
*.db-wal
parachute_mutations.db

# Godot script UID files
*.gd.uid

# Editor-specific
.vscode/
.idea/
"""

def run_cmd(cmd, dry_run=False):
    """Print and optionally execute a shell command."""
    print(f"$ {' '.join(cmd)}")
    if not dry_run:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        return result.returncode
    return 0

def get_untracked_files():
    """Return list of untracked files/dirs (excluding .gitignore patterns)."""
    result = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        capture_output=True, text=True
    )
    return [line for line in result.stdout.splitlines() if line.strip()]

def backup_untracked(untracked, backup_dir, dry_run=False):
    """Copy untracked files to backup_dir, preserving structure."""
    if dry_run:
        print(f"Would copy {len(untracked)} files/dirs to {backup_dir}")
        for item in untracked:
            print(f"  {item}")
        return

    backup_path = Path(backup_dir)
    backup_path.mkdir(parents=True, exist_ok=True)

    for item in untracked:
        src = Path(item)
        if src.is_dir():
            dst = backup_path / item
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst, symlinks=False, ignore_dangling_symlinks=True)
        else:
            dst = backup_path / item
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    print(f"✅ Backed up {len(untracked)} items to {backup_dir}")

def update_gitignore(dry_run=False):
    """Append extra ignore patterns to .gitignore."""
    gitignore = Path(".gitignore")
    if gitignore.exists():
        with open(gitignore, "r") as f:
            existing = f.read()
    else:
        existing = ""

    if EXTRA_IGNORE.strip() not in existing:
        with open(gitignore, "a") as f:
            f.write("\n" + EXTRA_IGNORE)
        print("✅ Updated .gitignore")
    else:
        print("ℹ️  .gitignore already contains extra patterns")

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Preview only")
    args = parser.parse_args()

    # 1. Get list of untracked files
    untracked = get_untracked_files()
    if not untracked:
        print("✅ No untracked files found.")
        sys.exit(0)

    print(f"Found {len(untracked)} untracked items.")

    # 2. Create backup folder name
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = f"backup_untracked_{timestamp}"

    # 3. Backup
    print(f"\n📦 Backing up to {backup_dir} ...")
    backup_untracked(untracked, backup_dir, args.dry_run)

    # 4. Clean (if not dry-run)
    if not args.dry_run:
        print("\n🧹 Removing untracked files from working directory...")
        run_cmd(["git", "clean", "-f", "-d"], dry_run=False)
    else:
        print("\n[DRY RUN] Would run git clean -f -d")

    # 5. Update .gitignore
    print("\n📝 Updating .gitignore...")
    update_gitignore(args.dry_run)

    # 6. Format (if not dry-run)
    if not args.dry_run:
        print("\n🔧 Formatting build_terrain.gd...")
        run_cmd(["gdformat", "godot_project/scripts/build_terrain.gd"], dry_run=False)

    # 7. Stage, commit, push (if not dry-run)
    if not args.dry_run:
        print("\n📦 Staging...")
        run_cmd(["git", "add", "."], dry_run=False)
        print("\n📝 Committing...")
        run_cmd(["git", "commit", "-m", "chore: cleanup untracked files and apply formatting"], dry_run=False)
        print("\n🚀 Pushing...")
        run_cmd(["git", "push", "origin", "main"], dry_run=False)
        print("\n✅ Done. Backup is in", backup_dir)
    else:
        print("\n[DRY RUN] Completed – no changes were made.")

if __name__ == "__main__":
    main()
