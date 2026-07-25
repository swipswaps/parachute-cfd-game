# Game Validation Toolset

This toolset validates all Godot scripts before the game starts, catches parse errors, shows diagnostic context (±3 lines), offers auto‑fixes, and logs everything to the database.

## Features
- Pre‑launch scanning for parse errors (using Godot in headless mode, with robust timeout)
- Diagnostic context with ±3 lines and line numbers
- Interactive fix interface (auto‑fix, rollback, approve broken)
- Dry‑run mode (`--dry-run`) to preview changes without applying
- Full audit trail in `parachute_mutations.db` with attempt counting
- SHA‑256 verified backups and rollback
- Self‑audit for forbidden patterns (MECHANICAL PRE‑DELIVERY GATE)
- Diff preview before applying any fix
- Syntax checking of generated Python files (via COMMAND INTEGRITY)

## Usage
1. Run `./launch_with_validation.sh` from the validation_tools directory.
2. Use `--dry-run` to preview fixes without applying: `./launch_with_validation.sh --dry-run`
3. Follow the interactive prompts.

## Files
- `main_validate.py` – orchestrator
- `script_scanner.py` – scans scripts for errors
- `fix_handlers.py` – auto‑fix functions with diff preview
- `db_audit.py` – database operations
- `launch_with_validation.sh` – runner script

## Rules Compliance
- LOGGING CONVENTION
- EVIDENTIAL GROUNDING
- DIAGNOSTIC TRANSPARENCY
- GUARDED EDITS (no sed)
- READ-AFTER-WRITE CONSISTENCY
- VERIFICATION BEFORE DELIVERY
- MECHANICAL PRE‑DELIVERY GATE
- DATABASE LOGGING REQUIREMENT
- SELF‑HEALING WITH VERIFIABLE BACKUPS
- CODE COMMENTING STANDARD
- DRY‑RUN DIAGNOSTIC PARITY
- COMMAND INTEGRITY
- DEPENDENCY MANAGEMENT
- ENFORCEMENT AND NON‑EVASION
