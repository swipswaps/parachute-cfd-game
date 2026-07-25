-- MSFS‑style pilot career tables for autostall gamification

CREATE TABLE IF NOT EXISTS pilot_career (
    pilot_id        INTEGER PRIMARY KEY,
    name            TEXT UNIQUE NOT NULL,
    total_flight_minutes INTEGER DEFAULT 0,
    total_flights   INTEGER DEFAULT 0,
    total_landings  INTEGER DEFAULT 0,   -- successful game completions
    total_fixes     INTEGER DEFAULT 0,
    rank            TEXT DEFAULT 'Student Pilot',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS flights (
    flight_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    pilot_id        INTEGER NOT NULL,
    start_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time        TIMESTAMP,
    duration_minutes INTEGER,
    outcome         TEXT CHECK(outcome IN ('landed','crashed','aborted')) NOT NULL,
    bugs_encountered INTEGER DEFAULT 0,
    bugs_fixed      INTEGER DEFAULT 0,
    notes           TEXT,
    FOREIGN KEY (pilot_id) REFERENCES pilot_career(pilot_id)
);

CREATE TABLE IF NOT EXISTS ratings (
    rating_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    code            TEXT UNIQUE NOT NULL,
    name            TEXT NOT NULL,
    description     TEXT,
    required_fixes  INTEGER DEFAULT 10,
    category        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pilot_ratings (
    pilot_id        INTEGER,
    rating_id       INTEGER,
    earned_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (pilot_id, rating_id),
    FOREIGN KEY (pilot_id) REFERENCES pilot_career(pilot_id),
    FOREIGN KEY (rating_id) REFERENCES ratings(rating_id)
);

CREATE TABLE IF NOT EXISTS pilot_category_fixes (
    pilot_id INTEGER,
    category TEXT,
    count INTEGER DEFAULT 0,
    PRIMARY KEY (pilot_id, category),
    FOREIGN KEY (pilot_id) REFERENCES pilot_career(pilot_id)
);

INSERT OR IGNORE INTO ratings (code, name, description, required_fixes, category) VALUES
    ('IR',  'Instrument Rating',    'Fix 5 indent‑related errors',        5, 'Indent'),
    ('NT',  'Null Texture Rating',   'Fix 5 null‑texture errors',         5, 'NullTexture'),
    ('PPL', 'Private Pilot License', 'Successfully land 5 simulations',   5, 'General');
