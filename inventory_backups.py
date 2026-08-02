#!/usr/bin/env python3
# ============================================================================
# inventory_backups.py -- READ-ONLY. MUTATES NOTHING.
#
# WHY (Rule #14 Scientific Debugging):
#   The uploaded transcript reaches three mutually contradictory conclusions
#   about which backup precedes the mouse fix (its own lines 95, 1091, 1099),
#   using only file-size arithmetic and no executed commands. Restoring from
#   a backup chosen that way is a coin flip across 81 candidates, and would
#   risk P1/P2 work that IS proven by autostall_p2_20260802160520.txt.
#
#   This script replaces that guesswork with a marker table. Every cell is a
#   substring test run against bytes actually read from disk.
#
# NO WRITES. NO git. NO restore. Reads files, prints a table, writes ONE
# report under notes/.
#
# Rules complied with: #1 (every claim from a read that happened), #7 (no
#   sed), #8 (verbatim output, nothing discarded), #14, #21 (backups are
#   inspected, never overwritten), #24, #25, #28, #37 (missing -> SKIP, not
#   PASS), #41 (timezone-aware).
#
# Citations:
#   - hashlib.sha256: https://docs.python.org/3/library/hashlib.html
#     (general knowledge - not retrieved this session)
#   - Marker strings below: taken from patches emitted this session and from
#     the audit results quoted in the uploaded transcript.
# ============================================================================

import sys
import hashlib
import datetime
from pathlib import Path

PROJECT_ROOT = Path(
    "/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game"
)
SCRIPTS = PROJECT_ROOT / "godot_project" / "scripts"
GD = SCRIPTS / "build_terrain.gd"
NOTES_DIR = PROJECT_ROOT / "notes"


def log_result(operation: str, success: bool, detail: str) -> None:
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)


# Short column name -> substring that proves the fix is present.
MARKERS = [
    ("P1deploy", "_headless_auto_deploy"),
    ("P2hud",    "_update_hud_readouts"),
    ("P2dump",   "_dump_all_labels"),
    ("P2pause",  'get_node_or_null("PauseMenu")'),
    ("P3vario",  "_p3_prev_y"),
    ("P3self",   "_p3_pause_selftest"),
    ("LOD512",   "512"),
]


def toggle_pause_has_capture(text: str) -> str:
    """Extract toggle_pause() and report whether MOUSE_MODE_CAPTURED is in it.

    The transcript's audit used a naive whole-file substring match, which
    cannot distinguish the real assignment from a comment mentioning the
    constant. This slices the function body instead.
    """
    i = text.find("func toggle_pause(")
    if i == -1:
        return "NOFUNC"
    j = text.find("\nfunc ", i + 1)
    body = text[i:] if j == -1 else text[i:j]
    if "MOUSE_MODE_CAPTURED" not in body:
        return "clean"
    for line in body.split("\n"):
        s = line.strip()
        if s.startswith("#"):
            continue
        if "MOUSE_MODE_CAPTURED" in s:
            return "CAPTURED"
    return "comment-only"


def scan(path: Path) -> dict:
    raw = path.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    row = {
        "name": path.name,
        "bytes": len(raw),
        "lines": text.count("\n") + 1,
        "sha8": hashlib.sha256(raw).hexdigest()[:8],
        "mtime": datetime.datetime.fromtimestamp(
            path.stat().st_mtime, datetime.timezone.utc
        ).strftime("%Y-%m-%d %H:%M:%S"),
        "toggle": toggle_pause_has_capture(text),
        "spaces": any(
            ln and ln[0] == " " and ln.strip() for ln in text.split("\n")
        ),
    }
    for col, needle in MARKERS:
        row[col] = "Y" if needle in text else "-"
    return row


def main() -> None:
    if not GD.exists():
        log_result("dep_check", False, f"missing: {GD}")
        sys.exit(1)
    if not NOTES_DIR.exists():
        NOTES_DIR.mkdir(parents=True)

    backups = sorted(SCRIPTS.glob("build_terrain.gd.bak*"))
    log_result("dep_check", True,
               f"current + {len(backups)} backup(s) to inspect")

    rows = [scan(GD)]
    rows[0]["name"] = "*** CURRENT ***"
    for b in backups:
        try:
            rows.append(scan(b))
        except Exception as exc:
            log_result(f"scan:{b.name}", False, f"SKIP - {exc}")

    cols = [c for c, _ in MARKERS]
    header = (f"{'file':<34} {'bytes':>7} {'lines':>5} {'sha8':<9} "
              f"{'mtime(UTC)':<20} {'toggle':<12} {'sp':<3} "
              + " ".join(f"{c:<9}" for c in cols))

    out = [
        "=" * len(header),
        "BUILD_TERRAIN.GD MARKER INVENTORY -- read-only, nothing modified",
        f"generated {datetime.datetime.now(datetime.timezone.utc).isoformat()}",
        "",
        "toggle column:  CAPTURED = live MOUSE_MODE_CAPTURED assignment in",
        "                           toggle_pause() (the actual defect)",
        "                comment-only = the constant appears only in a comment",
        "                clean  = absent    NOFUNC = toggle_pause not found",
        "sp column:      Y = file contains space-indented code (Rule #31 fail)",
        "",
        "Marker -> substring tested:",
    ]
    for c, n in MARKERS:
        out.append(f"  {c:<9} <- {n!r}")
    out += ["", "NOTE: LOD512 tests for the bare string '512' and will match",
            "      unrelated numbers. Treat it as weak evidence only.",
            "", header, "=" * len(header)]

    for r in rows:
        out.append(
            f"{r['name']:<34} {r['bytes']:>7} {r['lines']:>5} {r['sha8']:<9} "
            f"{r['mtime']:<20} {r['toggle']:<12} "
            f"{'Y' if r['spaces'] else '-':<3} "
            + " ".join(f"{r[c]:<9}" for c in cols)
        )

    cur = rows[0]
    out += [
        "=" * len(header),
        "",
        "CURRENT FILE VERDICT:",
        f"  toggle_pause defect present : {cur['toggle']}",
        f"  space-indented code (Rule 31): {'YES' if cur['spaces'] else 'no'}",
        "  fixes present               : "
        + ", ".join(c for c in cols if cur[c] == "Y"),
        "  fixes ABSENT                : "
        + (", ".join(c for c in cols if cur[c] != "Y") or "(none)"),
        "",
        "HOW TO READ THIS:",
        "  If CURRENT already has more Y marks than every backup, a restore",
        "  can only LOSE work -- patch the one defect instead.",
        "  If a specific fix shows '-' on CURRENT but 'Y' on some backup,",
        "  that fix was lost; recover THAT FUNCTION from that backup, do not",
        "  roll the whole file back.",
        "  Identical sha8 values mean identical files -- those backups are",
        "  redundant regardless of their differing timestamps.",
    ]

    body = "\n".join(out)
    print(body)

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    note = NOTES_DIR / f"inventory_backups_{ts}.txt"
    note.write_text(body + "\n", encoding="utf-8")
    log_result("inventory", True, f"{len(rows)} file(s) -> {note}")
    print(f"\nReport: {note}")


if __name__ == "__main__":
    main()
