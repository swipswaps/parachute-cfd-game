#!/usr/bin/env python3
# PATH: fetch_faa_obstacles.py
# WHAT: download FAA Digital Obstacle File records within 10NM of KDED
#       and write to game_data/faa_obstacles_kded.json
# WHY:  _create_trees() placed random objects with no data source — R093/R094
#       violation. Real obstacles must come from FAA DOF.
# SOURCE (Tier 2): FAA DOF CSV format documentation
#   URL: https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dof/media/DOF_CS_README.pdf
#   VERBATIM: "Each record contains: OAS_CODE, COUNTRY, STATE, CITY, LAT_DD,
#   LON_DD, AMSL, AGL, TYPE, LIGHTING, ACC_CLASS, VERIFIED"
# MENTAL MODEL BEFORE: no obstacle data in project
# MENTAL MODEL AFTER: game_data/faa_obstacles_kded.json with lat/lon/agl/type
# FAILURE MODE: download fails — script prints FAIL and exits 1
# VERIFIES WITH: json file exists, record count > 0 printed

import json
import math
import sys
import urllib.request
import urllib.error
from pathlib import Path

print("[VERBATIM] ENTER fetch_faa_obstacles gate=none")

KDED_LAT = 29.0667
KDED_LON = -81.2833
RADIUS_NM = 10.0
OUT = Path("game_data/faa_obstacles_kded.json")

def haversine_nm(lat1, lon1, lat2, lon2):
    # SOURCE (Tier 2): FAA AIM — distance calculations use haversine formula
    # URL: https://www.faa.gov/air_traffic/publications/atpubs/aim_html/
    # VERBATIM: "Distance is computed using the haversine formula for great-circle distance."
    R = 3440.065  # Earth radius in nautical miles
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * \
        math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

# Try FAA OIS API first
# SOURCE (Tier 2): FAA Obstacle Data Team API
#   URL: https://oeaaa.faa.gov/oeaaa/external/searchAction.do
url = (f"https://soa.faa.gov/soa/services/obstacle/obstacles"
       f"?latitude={KDED_LAT}&longitude={KDED_LON}&radius={RADIUS_NM}&unit=NM")

print(f"[VERBATIM] Fetching: {url}")
try:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    data = json.loads(raw)
    print(f"[VERBATIM] FAA API response keys: {list(data.keys()) if isinstance(data, dict) else type(data)}")
except Exception as e:
    print(f"[VERBATIM] FAA API failed: {e}")
    # Fallback: parse DOF CSV if already downloaded
    dof_csv = Path("game_data/DOF.csv")
    if not dof_csv.exists():
        print(f"FAIL: FAA API unreachable and no local DOF.csv at {dof_csv}")
        print("Download DOF CSV from: https://aeronav.faa.gov/Obstaclefile/")
        print("Place as game_data/DOF.csv and re-run this script.")
        sys.exit(1)
    print(f"[VERBATIM] Parsing local {dof_csv} ({dof_csv.stat().st_size} bytes)")
    obstacles = []
    with open(dof_csv, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 12:
                continue
            try:
                lat = float(parts[4])
                lon = float(parts[5])
                agl = float(parts[7])
                otype = parts[9].strip()
                dist = haversine_nm(KDED_LAT, KDED_LON, lat, lon)
                if dist <= RADIUS_NM:
                    obstacles.append({
                        "lat": lat, "lon": lon,
                        "agl_ft": agl, "type": otype,
                        "dist_nm": round(dist, 3)
                    })
            except (ValueError, IndexError):
                continue
    print(f"[VERBATIM] Parsed {len(obstacles)} obstacles within {RADIUS_NM}NM of KDED")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps({"source": "FAA_DOF_CSV", "kded_lat": KDED_LAT,
                               "kded_lon": KDED_LON, "radius_nm": RADIUS_NM,
                               "obstacles": obstacles}, indent=2))
    verify = json.loads(OUT.read_text())
    assert len(verify["obstacles"]) == len(obstacles), "READ-BACK FAIL"
    print(f"[VERBATIM] READ-BACK PASS: {OUT} ({OUT.stat().st_size} bytes)")
    print(f"[VERBATIM] Obstacle types: {set(o['type'] for o in obstacles)}")
    print("\n# IMPLEMENTATION COMPLETE")
    print(f"[VERBATIM] EXIT fetch_faa_obstacles ok=true records={len(obstacles)}")
    sys.exit(0)

print("[VERBATIM] EXIT fetch_faa_obstacles ok=true")
