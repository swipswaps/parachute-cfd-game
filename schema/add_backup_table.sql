-- PATH: schema/add_backup_table.sql
-- WHAT: Create a table to store file backups.
-- WHY:  Enables rollback to a known good state if a fix breaks the file.
-- Source (Tier 2): SQLite CREATE TABLE:
--   https://www.sqlite.org/lang_createtable.html

CREATE TABLE IF NOT EXISTS file_backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,          -- relative path within project
    backup_content BLOB NOT NULL,     -- full file content
    description TEXT,                 -- why backed up (e.g., "before applying FIX_007")
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);