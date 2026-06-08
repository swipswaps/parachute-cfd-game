#!/usr/bin/env python3
# PATH: build_skills_0056.py
# WHAT: Merge skills_0055.json + skills_0056_new_entries.json → skills_0056.json
# WHY:  Add R091 (PackedScene.instantiate() must assign to Node3D not subtype),
#       R092 (all instantiated nodes must have scale set before add_child),
#       T052 (GLB bounding box scale calculator).
#       These rules were proven necessary in the 2026-06-07 canopy fix session:
#       R091 would have caught the MeshInstance3D type mismatch at line 379.
#       R092 would have caught the missing scale on _main_canopy_node.
# ASSUMES: skills_0055.json and skills_0056_new_entries.json in same directory.
# VERIFIES WITH: PASS N=8 FAIL=0; rules=52, techniques=52, SI=20.

import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).parent
BASE  = HERE / "skills_0055.json"
NEW   = HERE / "skills_0056_new_entries.json"
OUT   = HERE / "skills_0056.json"
BACKUP_SUFFIX = f".backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"


def log(msg: str) -> None:
    print(f"[VERBATIM] {msg}")


def gate_exists(p: Path) -> None:
    log(f"Checking: {p.name}")
    assert p.exists(), f"GATE FAIL: {p} not found"
    log(f"PASS: {p.name} exists")


def load_json(p: Path) -> dict:
    log(f"Loading {p.name}")
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    log(f"Loaded {p.name} — version {d.get('version', 'unknown')}")
    return d


def write_readback(data: dict, p: Path) -> None:
    log(f"Writing {p.name}")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    with open(p, encoding="utf-8") as f:
        verify = json.load(f)
    assert data == verify, f"READ-BACK FAIL: {p.name}"
    log(f"READ-BACK PASS: {p.name} ({p.stat().st_size} bytes)")


def main() -> None:
    log("=== Starting build_skills_0056.py ===")

    gate_exists(BASE)
    gate_exists(NEW)

    if OUT.exists():
        bak = OUT.with_suffix(OUT.suffix + BACKUP_SUFFIX)
        shutil.copy2(OUT, bak)
        log(f"Backup: {bak.name}")

    base = load_json(BASE)
    new  = load_json(NEW)

    assert base["version"] == "v0055", f"Expected v0055, got {base['version']}"

    existing_rules  = base.get("rules", {})
    existing_techs  = {t["id"]: t for t in base.get("techniques", [])}
    existing_si     = base.get("search_ux_improvements", [])
    what_learned    = base.get("what_was_learned", "")

    new_rules  = new.get("new_rules", {})
    new_techs  = new.get("new_techniques", [])
    new_si     = new.get("new_search_ux_improvements", [])

    log(f"Base rules: {len(existing_rules)}, Base techniques: {len(existing_techs)}, Base SI: {len(existing_si)}")
    log(f"New rules: {len(new_rules)}, New techniques: {len(new_techs)}, New SI: {len(new_si)}")

    # Gate 1: no ID collisions
    for rid in new_rules:
        assert rid not in existing_rules, f"GATE FAIL: rule {rid} already exists"
    for t in new_techs:
        assert t["id"] not in existing_techs, f"GATE FAIL: technique {t['id']} already exists"
    log("Gate 1 PASS: no ID collisions")

    merged_rules = {**existing_rules, **new_rules}
    merged_techs = {**existing_techs, **{t["id"]: t for t in new_techs}}
    merged_si    = existing_si + new_si

    added_what = (
        " v0056 adds R091, R092, T052 from the 2026-06-07 canopy fix session: "
        "R091 (PackedScene.instantiate() must assign to Node3D not a subtype — "
        "MeshInstance3D assignment causes silent null and skips all subsequent ops), "
        "R092 (every instantiated node must have .scale set before add_child — "
        "a scale fix on one instance does not propagate to other instances of the same asset), "
        "T052 (GLB bounding box scale calculator — reads POSITION accessor min/max from "
        "GLB binary header to derive exact scale factor for a target world dimension)."
    )
    merged_what = what_learned + added_what

    output = {
        "skill_name":   "skills_0056",
        "title":        "Complete Verification & Compliance Skill — v0056 (adds R091, R092, T052: GLB instantiate type safety, per-instance scale, bbox calculator)",
        "version":      "v0056",
        "parent_skill": "skills_0055",
        "core_principle": base["core_principle"],
        "what_was_learned": merged_what,
        "techniques":   list(merged_techs.values()),
        "search_ux_improvements": merged_si,
        "rules":        merged_rules,
        "implementation_order": base.get("implementation_order", {}),
        "gate_integration":     base.get("gate_integration", {}),
        "last_backup":  datetime.now().isoformat(),
    }

    # Gate 2: all base rules preserved
    for rid in existing_rules:
        assert rid in merged_rules, f"GATE FAIL: base rule {rid} missing"
    log("Gate 2 PASS: all base rules preserved")

    # Gate 3: all new rules present
    for rid in new_rules:
        assert rid in merged_rules, f"GATE FAIL: new rule {rid} missing"
    log("Gate 3 PASS: all new rules present")

    # Gate 4: all base techniques preserved
    out_tids = {t["id"] for t in output["techniques"]}
    for tid in existing_techs:
        assert tid in out_tids, f"GATE FAIL: technique {tid} missing"
    log("Gate 4 PASS: all base techniques preserved")

    # Gate 5: new techniques present
    for t in new_techs:
        assert t["id"] in out_tids, f"GATE FAIL: new technique {t['id']} missing"
    log("Gate 5 PASS: new techniques present")

    # Gate 6: rule count
    expected_rules = len(existing_rules) + len(new_rules)
    assert len(output["rules"]) == expected_rules, \
        f"GATE FAIL: expected {expected_rules} rules, got {len(output['rules'])}"
    log(f"Gate 6 PASS: total rules = {len(output['rules'])}")

    # Gate 7: technique count
    expected_techs = len(existing_techs) + len(new_techs)
    assert len(output["techniques"]) == expected_techs, \
        f"GATE FAIL: expected {expected_techs} techniques, got {len(output['techniques'])}"
    log(f"Gate 7 PASS: total techniques = {len(output['techniques'])}")

    # Gate 8: SI count
    assert len(output["search_ux_improvements"]) == len(existing_si) + len(new_si), \
        "GATE FAIL: SI count mismatch"
    log(f"Gate 8 PASS: SI entries = {len(output['search_ux_improvements'])}")

    write_readback(output, OUT)

    # Optional audit
    audit = HERE / "skills_audit.py"
    if audit.exists():
        log("Running skills_audit.py...")
        r = subprocess.run(["python3", str(audit), str(OUT)], capture_output=True, text=True)
        print(r.stdout)
        if r.returncode != 0:
            log("WARNING: skills_audit.py non-zero exit")
            print(r.stderr)
    else:
        log("No skills_audit.py — skipping")

    print("\n# IMPLEMENTATION COMPLETE")
    log(f"skills_0056.json: {len(output['rules'])} rules, "
        f"{len(output['techniques'])} techniques, "
        f"{len(output['search_ux_improvements'])} SI entries")
    log("=== build_skills_0056.py finished ===")


if __name__ == "__main__":
    main()
