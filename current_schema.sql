CREATE TABLE sessions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            -- session_label: identifies which generate_fix_NNNN.py ran
            -- WHY: links all mutations and parse results to the script that
            --   produced them; allows per-session audit ("what did 0207 do?")
            session_label TEXT NOT NULL,
            started_at  TEXT NOT NULL,
            completed   INTEGER DEFAULT 0,
            notes       TEXT
        );
CREATE TABLE sqlite_sequence(name,seq);
CREATE TABLE mutations (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      INTEGER REFERENCES sessions(id),
            -- fix_id: maps to fix_list_0207.json "id" field
            fix_id          TEXT NOT NULL,
            file_path       TEXT NOT NULL,
            -- content_before: SHA-256 of file content before mutation
            -- WHY: allows detection of conflicting mutations across sessions
            --   (Tanenbaum 2007 vector clock equivalent for file state)
            content_sha256_before TEXT,
            content_sha256_after  TEXT,
            -- already_applied: 1 if SELECT found this exact patch already present
            -- WHY: the idempotence gate — prevents re-applying committed mutations
            already_applied INTEGER DEFAULT 0,
            applied_at      TEXT NOT NULL,
            description     TEXT
        );
CREATE TABLE gdparse_results (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id  INTEGER REFERENCES sessions(id),
            fix_id      TEXT NOT NULL,
            file_path   TEXT NOT NULL,
            passed      INTEGER NOT NULL,  -- 1=PASS 0=FAIL
            stderr_text TEXT,
            checked_at  TEXT NOT NULL
        );
CREATE TABLE gdscript_version_rules (
            id                          INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id                     TEXT UNIQUE NOT NULL,
            category                    TEXT NOT NULL,
            title                       TEXT NOT NULL,
            feature_description         TEXT NOT NULL,
            first_seen_godot_version    TEXT,
            gdparse_version_misses      TEXT,
            severity                    TEXT NOT NULL,
            fix_strategy                TEXT,
            source_tier2                TEXT,
            error_message_pattern       TEXT,
            added_at                    TEXT NOT NULL
        );
CREATE TABLE gdscript_rule_test_results (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      INTEGER REFERENCES sessions(id),
            rule_id         TEXT REFERENCES gdscript_version_rules(rule_id),
            file_path       TEXT NOT NULL,
            test_type       TEXT NOT NULL CHECK(test_type IN ('gdparse','godot_launch')),
            variant         TEXT NOT NULL CHECK(variant IN ('A','B')),
            result          TEXT NOT NULL CHECK(result IN ('PASS','FAIL')),
            error_message   TEXT,
            godot_pid       INTEGER,
            cpu_pct         REAL,
            rss_mb          REAL,
            elapsed_s       REAL,
            contention_flag INTEGER DEFAULT 0,
            tested_at       TEXT NOT NULL
        );
CREATE TABLE rule_sources (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id     TEXT REFERENCES gdscript_version_rules(rule_id),
            source_type TEXT NOT NULL CHECK(source_type IN
                        ('official_docs','forum','github','local_log')),
            source_url  TEXT NOT NULL,
            quote_text  TEXT,
            added_at    TEXT NOT NULL
        );
CREATE TABLE validators (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            name     TEXT NOT NULL,
            version  TEXT NOT NULL,
            UNIQUE(name, version)
        );
CREATE TABLE validator_results (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id   INTEGER REFERENCES sessions(id),
            file_path    TEXT NOT NULL,
            rule_id      TEXT REFERENCES gdscript_version_rules(rule_id),
            validator_id INTEGER REFERENCES validators(id),
            result       TEXT NOT NULL CHECK(result IN ('PASS','FAIL','ERROR')),
            error_msg    TEXT,
            elapsed_ms   INTEGER,
            -- disagreement: 1 if this validator disagrees with the reference oracle (Godot)
            -- WHAT: populated by compare_validators() after both gdparse and
            --   godot_launch results are available for the same file/rule
            -- WHY: a single column makes the query trivial vs joining tables
            disagreement INTEGER DEFAULT 0,
            tested_at    TEXT NOT NULL
        , validator_name TEXT, validator_version TEXT);
CREATE TABLE resource_contention (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      INTEGER REFERENCES sessions(id),
            godot_pid       INTEGER NOT NULL,
            snapshot_seq    INTEGER NOT NULL,  -- monotonic index per PID per session
            cpu_pct         REAL,              -- (delta utime+stime) / elapsed_ticks * 100
            rss_mb          REAL,              -- VmRSS in kB / 1024
            threads         INTEGER,           -- /proc/PID/status Threads:
            fd_count        INTEGER,           -- /proc/PID/fd/* count
            contention_flag INTEGER DEFAULT 0, -- 1 if cpu_pct > 90 or rss_mb > 512
            recorded_at     TEXT NOT NULL
        );
CREATE TABLE pid_tuning (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id    INTEGER REFERENCES sessions(id),
            godot_pid     INTEGER NOT NULL,
            nice_before   INTEGER,
            nice_after    INTEGER,
            ionice_class_before TEXT,
            ionice_class_after  TEXT,
            contention_before   INTEGER,   -- contention_flag before adjustment
            contention_after    INTEGER,   -- contention_flag after adjustment (if re-tested)
            outcome       TEXT,            -- 'improved', 'no_change', 'worse'
            recorded_at   TEXT NOT NULL
        );
CREATE TABLE recovery_graph (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      INTEGER REFERENCES sessions(id),
            -- parent_rule_id: the rule whose fix was necessary for child to appear
            parent_rule_id  TEXT REFERENCES gdscript_version_rules(rule_id),
            -- child_rule_id: the rule that was masked until parent was fixed
            child_rule_id   TEXT REFERENCES gdscript_version_rules(rule_id),
            -- masked_until_session: session_label where child was first seen
            masked_until_session TEXT,
            -- confirmed_from: source evidence for this masking relationship
            confirmed_from  TEXT,
            notes           TEXT,
            added_at        TEXT NOT NULL
        );
CREATE TABLE schema_audit_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      INTEGER REFERENCES sessions(id),
            -- tables_json: JSON array of table names at session start
            tables_json     TEXT NOT NULL,
            -- missing_required: comma-separated list of any REQUIRED_TABLES absent
            missing_required TEXT,
            audited_at      TEXT NOT NULL
        );
CREATE TABLE lint_results (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id    INTEGER REFERENCES sessions(id),
            file_path     TEXT NOT NULL,
            -- rule_id: VR011=disconnected_signal, VR012=duplicate_input,
            --          VR013=missing_visibility, VR014=missing_collision
            rule_id       TEXT,
            finding_type  TEXT NOT NULL,
            line_no       INTEGER,
            -- detail: what was found (e.g. signal name, action name)
            detail        TEXT,
            -- fix_suggestion: one-line description of the correct fix
            fix_suggestion TEXT,
            severity      TEXT NOT NULL DEFAULT 'high',
            -- status: open, fixed, accepted_risk
            status        TEXT NOT NULL DEFAULT 'open',
            found_at      TEXT NOT NULL
        );
CREATE TABLE alembic_version (
	version_num VARCHAR(32) NOT NULL, 
	CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);
