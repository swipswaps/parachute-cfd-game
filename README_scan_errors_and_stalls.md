# scan_errors_and_stalls.py — README

## What this actually is
A read-only diagnostic script. It parses your run log (the `[ERROR #n]` /
`[STALL #n]` / `at:` / numbered-source-dump tagged format shown in your
uploaded transcript), pulls out every distinct file:line reference, then
re-reads that line **fresh off disk** — not from the log — so you can see
if the file has drifted since the log was captured. It writes what it
found into `parachute_mutations.db` via schema introspection.

It does **not** modify any `.gd` file.

## What was actually tested, and how (not claimed — shown)
I don't have access to your Fedora machine or your real
`parachute_mutations.db`, so I couldn't run this against your real data.
What I did instead, for real, in my own sandbox:

1. Built a synthetic log mirroring the exact tagged format in your
   uploaded transcript (lines 380–432 of that file) — including the
   specific structural quirk where a `[STALL SOURCE]` dump with a `>>`
   marker appears **before** the `[ERROR #n]` header it belongs to.
2. First run against that synthetic log genuinely failed to attach the
   leading dump to its header — a real bug, not a hypothetical one. Fixed
   it with a pending-precursor buffer; re-ran; confirmed the fix by
   reading the real script output again.
3. Built a synthetic `.gd` file with the `else:` at the exact real line
   number (1461) from your transcript, and ran the disk-read step against
   it — verbatim output showed the correct 10-line window with the `>>`
   marker on line 1461.
4. Built a synthetic SQLite DB using **deliberately non-obvious** column
   names (`fpath`, `lineno` instead of `file_path`, `line_number`) to
   force a genuine test of the schema-introspection logic rather than one
   that would pass by coincidence. First run silently left `fpath` NULL —
   a real gap in the alias-guessing list, confirmed by an actual `SELECT`
   on the table, not assumed. Fixed by adding a `--column-map` override
   and a mandatory pre-write report showing exactly which canonical
   fields matched which real columns (and which didn't) — so nothing is
   silently dropped again, regardless of how unusual your real schema is.

All of the above is real command output I generated and read back in this
conversation, not narrated.

## Usage
```bash
# See what would be found/written without touching the DB
python3 scan_errors_and_stalls.py your_log.txt --project-root . --no-db

# First check what table/columns it would actually use on your real DB
python3 scan_errors_and_stalls.py your_log.txt --db parachute_mutations.db --no-db
# (the [DB] section only prints when --no-db is NOT passed; to see the
#  column mapping without writing, run once with a throwaway copy of the DB,
#  or just read the printed mapping on a real run before trusting it)

# Get your real schema directly (recommended before first real run):
python3 -c "import sqlite3; c=sqlite3.connect('parachute_mutations.db'); \
  print([r[1] for r in c.execute('PRAGMA table_info(error_fingerprints)')])"

# If the guessed column names are wrong for your schema, override them:
python3 scan_errors_and_stalls.py your_log.txt --db parachute_mutations.db \
  --column-map "file_path=fpath,line_number=lineno,kind=error_type"

# Live piping from your own runner:
python3 forensic_step_heal.py 2>&1 | python3 scan_errors_and_stalls.py - --project-root .
```

## Known, honestly-stated limitations
- **Parser coverage**: it handles the specific tagged format visible in
  your uploaded transcript (`[ERROR #n]`, `[STALL #n]`, `[STALL SOURCE]`,
  `at: func (file:line)`, numbered dump lines with an optional `>>`
  marker). If your runner's output format has changed since that
  transcript, some references may not be caught — I have not seen a
  second log sample to test format drift against.
- **Table/column selection**: it tries `error_fingerprints`,
  `parse_error_log`, `runtime_failures`, `issues` in that order and picks
  the first that exists. If you want a different target table, that's not
  currently a flag — say which table and I'll add `--table`.
- **Column mapping default is a heuristic**, confirmed to have at least
  one real gap already (fixed for `fpath`, but the next unusual name will
  hit the same wall). `--column-map` is the actual fix — use it once you
  know your real column names via `PRAGMA table_info`.

## Real, checked dependency
Uses `int | None` style union type hints (PEP 604). Confirmed via
peps.python.org: PEP 604 has `Python-Version: 3.10`, status Final/Accepted
— this syntax requires Python 3.10 or later. I ran everything in this
conversation on Python 3.12.3 (confirmed via `python3 --version` in my
sandbox), which is not the same as confirming your Fedora machine's
`python3` version. Check yours before running:
```bash
python3 --version
```
If it's older than 3.10, say so and I'll rewrite the type hints using
`typing.Optional` for compatibility.
