-- proposed_db_consolidation.sql (generated 2026-07-17T12:18:49.931752Z)
-- NOT APPLIED by audit_db_sprawl.py. Review, then apply manually with:
--   sqlite3 forensics.db < proposed_db_consolidation.sql
-- from the repo root ONLY (single canonical location kills BLOCKER 1).

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL,          -- every writer stamps the same run_id,
                                   -- e.g. $(date +%Y%m%d%H%M%S)-$$
    ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    source TEXT NOT NULL,          -- which tool/script wrote this
    kind TEXT NOT NULL,            -- 'diagnosis'|'fix'|'error'|'audit'|'heal'
    file_path TEXT,
    detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_run ON events(run_id);
CREATE INDEX IF NOT EXISTS idx_events_kind_ts ON events(kind, ts);

-- Migration template (fill real paths from db_registry.tsv, then run):
-- ATTACH DATABASE 'diagnostics.db' AS diag;
-- INSERT INTO events (run_id, ts, source, kind, detail)
--   SELECT 'migrated', checked_at, 'diagnostics.db', 'diagnosis',
--          check_name || ': ' || result || char(10) || evidence
--   FROM diag.diagnosis_log;
-- DETACH DATABASE diag;
-- (repeat per source DB; originals left untouched -- archive, don't delete)
