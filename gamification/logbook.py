"""MSFS‑style pilot logbook and career tracking for autostall.py."""
import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "parachute_mutations.db")

def _connect():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    with open(schema_path) as f:
        schema = f.read()
    conn = _connect()
    conn.executescript(schema)
    conn.commit()
    conn.close()

def get_or_create_pilot(name="default"):
    conn = _connect()
    cur = conn.execute("SELECT pilot_id FROM pilot_career WHERE name=?", (name,))
    row = cur.fetchone()
    if row:
        pid = row[0]
    else:
        cur.execute("INSERT INTO pilot_career (name) VALUES (?)", (name,))
        pid = cur.lastrowid
    conn.commit()
    conn.close()
    return pid

def start_flight(pilot_name="default"):
    pid = get_or_create_pilot(pilot_name)
    conn = _connect()
    cur = conn.execute(
        "INSERT INTO flights (pilot_id, start_time) VALUES (?, ?)",
        (pid, datetime.now().isoformat())
    )
    flight_id = cur.lastrowid
    conn.commit()
    conn.close()
    return flight_id

def end_flight(flight_id, outcome, bugs_encountered=0, bugs_fixed=0, notes=""):
    conn = _connect()
    cur = conn.execute("SELECT start_time FROM flights WHERE flight_id=?", (flight_id,))
    row = cur.fetchone()
    if row:
        start = datetime.fromisoformat(row[0])
        duration = (datetime.now() - start).total_seconds() / 60.0
    else:
        duration = 0
    conn.execute("""
        UPDATE flights SET end_time=?, duration_minutes=?, outcome=?,
            bugs_encountered=?, bugs_fixed=?, notes=?
        WHERE flight_id=?
    """, (datetime.now().isoformat(), int(duration), outcome,
          bugs_encountered, bugs_fixed, notes, flight_id))
    pid = conn.execute("SELECT pilot_id FROM flights WHERE flight_id=?", (flight_id,)).fetchone()[0]
    if outcome == 'landed':
        conn.execute("UPDATE pilot_career SET total_landings = total_landings + 1 WHERE pilot_id=?", (pid,))
    conn.execute("""
        UPDATE pilot_career SET total_flight_minutes = total_flight_minutes + ?,
            total_flights = total_flights + 1, total_fixes = total_fixes + ?
        WHERE pilot_id=?
    """, (int(duration), bugs_fixed, pid))
    conn.commit()
    _check_ratings(pid)
    _promote_rank(pid)
    conn.close()

def record_fix_category(pilot_name, category):
    """Increment the fix count for a specific category for the given pilot."""
    pid = get_or_create_pilot(pilot_name)
    conn = _connect()
    conn.execute("""
        INSERT INTO pilot_category_fixes (pilot_id, category, count)
        VALUES (?, ?, 1)
        ON CONFLICT(pilot_id, category) DO UPDATE SET count = count + 1
    """, (pid, category))
    conn.commit()
    conn.close()

def _check_ratings(pilot_id):
    conn = _connect()
    cur = conn.execute("""
        SELECT r.rating_id, r.code, r.required_fixes, r.category,
               COALESCE(pcf.count, 0) as current_count
        FROM ratings r
        LEFT JOIN pilot_category_fixes pcf ON pcf.category = r.category AND pcf.pilot_id = ?
        WHERE r.required_fixes <= COALESCE(pcf.count, 0)
        AND r.rating_id NOT IN (SELECT rating_id FROM pilot_ratings WHERE pilot_id = ?)
    """, (pilot_id, pilot_id))
    for row in cur.fetchall():
        conn.execute("INSERT OR IGNORE INTO pilot_ratings (pilot_id, rating_id) VALUES (?, ?)",
                     (pilot_id, row[0]))
        print(f"[GAMIFY] Rating earned: {row[1]} - {row[3]} ({row[2]} fixes)")
    conn.commit()
    conn.close()

def _promote_rank(pilot_id):
    conn = _connect()
    cur = conn.execute("""
        SELECT total_flight_minutes, total_landings, total_fixes,
               (SELECT COUNT(*) FROM pilot_ratings WHERE pilot_id=?) as rating_count
        FROM pilot_career WHERE pilot_id=?
    """, (pilot_id, pilot_id))
    row = cur.fetchone()
    if not row:
        conn.close()
        return
    minutes, landings, fixes, ratings = row
    new_rank = 'Student Pilot'
    if minutes > 5 and fixes >= 2:
        new_rank = 'Sport Pilot'
    if minutes > 15 and landings >= 2 and ratings >= 1:
        new_rank = 'Private Pilot'
    if minutes > 30 and landings >= 5 and ratings >= 2:
        new_rank = 'Commercial Pilot'
    if minutes > 60 and landings >= 10 and ratings >= 3:
        new_rank = 'Airline Transport Pilot (ATP)'
    cur.execute("UPDATE pilot_career SET rank = ? WHERE pilot_id = ?", (new_rank, pilot_id))
    conn.commit()
    conn.close()
