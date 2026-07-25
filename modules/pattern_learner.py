"""Pattern Learner – learns code conventions from existing .gd files
   and stores them in parachute_mutations.db for use by autostall fixes."""
import os, sqlite3, re
from collections import Counter

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "parachute_mutations.db")
SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "godot_project", "scripts")

def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    conn = _connect()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS code_patterns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern_type TEXT NOT NULL,
            path_pattern TEXT NOT NULL,
            style_value TEXT NOT NULL,
            confidence REAL DEFAULT 1.0,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(pattern_type, path_pattern)
        )
    """)
    conn.commit()
    conn.close()

def learn_indentation():
    """Scan every .gd file (non‑backup) and determine the dominant
       indentation style (tab or space) for each directory."""
    styles = {}   # directory -> list of styles ('tab','space') from each file
    for root, dirs, files in os.walk(SCRIPTS_DIR):
        # skip backup directories
        if "backup" in root.lower():
            continue
        for f in files:
            if not f.endswith(".gd") or "backup" in f.lower():
                continue
            full = os.path.join(root, f)
            try:
                with open(full, "r", encoding="utf-8", errors="replace") as fh:
                    lines = fh.readlines()
            except:
                continue
            # Determine style for this file: if at least 80% of indented lines
            # start with a tab, call it tab; else space.
            indent_lines = [l for l in lines if l and l[0] in (' ', '\t')]
            if not indent_lines:
                continue
            tab_count = sum(1 for l in indent_lines if l[0] == '\t')
            space_count = len(indent_lines) - tab_count
            style = "tab" if tab_count >= space_count else "space"
            rel_dir = os.path.relpath(os.path.dirname(full), SCRIPTS_DIR)
            if rel_dir == ".":
                rel_dir = ""   # root scripts dir
            styles.setdefault(rel_dir, []).append(style)

    # For each directory, pick the dominant style
    conn = _connect()
    for dir_path, style_list in styles.items():
        counter = Counter(style_list)
        dominant = counter.most_common(1)[0][0]
        confidence = counter[dominant] / len(style_list)
        conn.execute("""
            INSERT OR REPLACE INTO code_patterns (pattern_type, path_pattern, style_value, confidence)
            VALUES ('indentation', ?, ?, ?)
        """, (dir_path if dir_path else "root", dominant, round(confidence, 3)))
    conn.commit()
    conn.close()
    print(f"[PATTERN] Learned indentation styles for {len(styles)} directories.")

def get_indentation_style(script_dir: str) -> str:
    """Return the expected indentation style ('tab' or 'space') for a given
       relative script directory. Falls back to the root style if not found."""
    conn = _connect()
    # try exact match first, then root
    rows = conn.execute("SELECT style_value FROM code_patterns WHERE pattern_type='indentation' AND path_pattern=?", (script_dir,)).fetchall()
    if not rows:
        rows = conn.execute("SELECT style_value FROM code_patterns WHERE pattern_type='indentation' AND path_pattern='root'").fetchall()
    conn.close()
    if rows:
        return rows[0][0]
    return "tab"   # default to tab if no data (Godot's default)
