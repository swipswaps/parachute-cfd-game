-- PATH: godot_project/tools/migrations/001_implement_rebuild_indentation.sql
--
-- WHAT: replaces known_repairs row 1's stub (pattern_old='', pattern_new='')
--       with a real, tested reference to the sibling-inference algorithm
--       in indent_rebuild_repair.py. The actual repair logic lives in
--       Python (heuristic, not a static regex), so these columns store a
--       description pointing to it rather than a literal pattern — a
--       fixed-string pattern_old/pattern_new can't express "match the
--       indentation of the nearest non-blank sibling line."
--
-- WHY: confirmed this conversation — real query against this exact row
--      showed pattern_old='' pattern_new='' despite being registered as
--      the active strategy for error_class='INVALID_INDENT'. That gap is
--      the root cause of an earlier session's blind, unguarded .lstrip()
--      fix on plugin.gd:45, which is what caused the CURRENT failure this
--      conversation started from.
--
-- VERIFIES WITH: after applying, SELECT pattern_old FROM known_repairs
--      WHERE id=1 no longer returns an empty string.

UPDATE known_repairs
SET
    pattern_old = 'INDENTATION_MISMATCH:sibling-inferred',
    pattern_new = 'godot_project/tools/indent_rebuild_repair.py:infer_correct_indent',
    description = 'Rebuild indentation from block structure — implemented and verified against plugin.gd (2 defects, both root-caused to a prior unguarded .lstrip() fix); verified as a correct no-op against 4 already-clean files (FlightTrack.gd, TrackImporter.gd, build_terrain.gd, CanopyReplay.gd, all byte-identical before/after)'
WHERE id = 1
  AND error_class = 'INVALID_INDENT'
  AND strategy_name = 'rebuild_indentation'
  AND pattern_old = ''
  AND pattern_new = '';
-- WHY the WHERE clause repeats the stub condition: Design by Contract —
-- this migration must refuse to overwrite row 1 if someone has already
-- implemented it a different way since this conversation. Confirm with:
--   SELECT changes();  -- must return 1, not 0, after running
