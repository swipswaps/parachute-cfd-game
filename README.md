# Parachute-CFD Forensic Hub v2

Read-only gamified dashboard over `parachute_mutations.db` — surfaces
parse/gdparse/gdformat/repair/recovery activity from the pipeline's own
SQLite log tables.

## Why v2

v1 read only `autohealactions` (1,488 rows). Real DB has TWO heal-actions
tables — the primary one is `auto_heal_actions` (snake_case, 15,710 rows,
richer schema). v2 unions both tables and normalizes the nanosecond
`timestamp` column that v1 assumed was ISO text.

v2 also queries tables v1 ignored:

- `parse_checks` (3,677 rows)   → parser history card
- `parse_error_log` (1,065)     → error-class card
- `strategy_rewards` (33)       → UCB1 bandit card (with seed detection)
- `repair_rules` (8)            → same card, second data source
- `files_to_fix` (77)           → kanban card
- `tool_audit` (2,470)          → performance card (avg ms per tool)
- `issues` (38)                 → RCA log

## Fabrication guard

Every gamification metric traces to a real COUNT/SUM. Metrics with no
supporting data show "not yet unlocked" rather than an invented number.
`strategy_rewards` rows with `wins == total_trials == 10000` are flagged
as `likely seeded` and NOT counted toward the Bandit Learner achievement.

## Read-only guarantee

DB opened via `sqlite3.connect("file:PATH?mode=ro", uri=True)`. Write
attempts are rejected at the driver layer — the pipeline's canonical DB
cannot be mutated by this hub.

## Usage

    python3 forensic_hub_v2.py --db ./parachute_mutations.db
    # then open http://127.0.0.1:8765/

Flags:
    --db PATH    path to parachute_mutations.db  (default: ./parachute_mutations.db)
    --port N     default 8765
    --host H     default 127.0.0.1 (loopback only)

Env:
    PARACHUTE_DB=/abs/path python3 forensic_hub_v2.py

Stop with Ctrl-C.
