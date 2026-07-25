# PATH: godot_project/tools/STUB_BACKLOG.md
#
# WHAT: the 33 known_repairs rows still stubbed after this session
#       (row 1, INVALID_INDENT/rebuild_indentation, is now implemented —
#       see indent_rebuild_repair.py and 001_implement_rebuild_indentation.sql)
#
# WHY these are not implemented in this session: each would need a real
# failing GDScript example to test against (Dev/Prod Parity — no synthetic
# test data), and this session had real failing examples for exactly one
# error class (INVALID_INDENT, from plugin.gd). Writing pattern_old/
# pattern_new for the other 33 without a real failure to verify against
# would mean shipping unverified regex/heuristics into a production
# repair pipeline — worse than the current inert stubs, which at least
# fail safe by doing nothing.
#
# NOT prioritized by guesswork — ranked by real usage evidence already
# in the database this conversation queried.

## Rows with UNIQUE, non-generic error_class (likely highest value — one
## error class, one clear fix, easiest to verify against a real example
## when one occurs):

- id=2  UNDECLARED_VAR       / prepend_var_declaration
- id=3  MISSING_CLASS_BODY   / insert_pass_body
- id=4  UNRESOLVABLE_BASE    / strip_extends
- id=5  DUPLICATE_SIGNAL     / remove_duplicate_signal

## Rows sharing error_class='UNEXPECTED_TOKEN' (28 stub rows) — this is
## the fingerprint's catch-all class (see error_fingerprints id=6,
## pattern='Unexpected token'), so the database can't currently
## distinguish which of these 28 named strategies should fire for a given
## UNEXPECTED_TOKEN failure without additional sub-classification logic
## that doesn't exist yet. Implementing these one at a time as real
## examples surface (per Scientific Debugging — real observed failure
## first, hypothesis second) is lower-risk than pre-writing 28 pattern
## guesses against error text no one has seen yet:

id=6  fix_active_enum_closing_brace
id=7  fix_invalid_parentheses_after_number
id=8  fix_merged_var_declaration
id=9  fix_not_var
id=10 fix_commented_closing_brace
id=11 fix_unclosed_quoted_string
id=12 fix_missing_method_call_parentheses
id=13 fix_unclosed_parentheses_globally
id=14 fix_unclosed_function_signature
id=15 fix_unclosed_string
id=16 fix_missing_parenthesis
id=17 fix_decorator_semicolon
id=18 remove_double_colon
id=19 fix_trailing_semicolon
id=20 fix_semicolon_colon
id=21 fix_multicolon_in_comment
id=22 comment_orphan_else
id=23 comment_top_level_orphan_body
id=24 fix_func_name_as_type_hint
id=25 fix_split_var_name
id=26 fix_extends_inside_func
id=27 fix_typed_var_missing_enum
id=28 fix_malformed_clamp
id=29 fix_invalid_comment_line
id=30 wrap_top_level_statements
id=31 fix_incomplete_statements
id=32 gdformat_recheck
id=35 fix_replay_api_usage
id=36 fix_all_unbalanced_braces

# VERIFIES WITH (for whoever picks one of these up next): the same
# five-step loop used for INVALID_INDENT this session —
#   1. get a real gdparse failure matching that error_class
#   2. state the root cause from the real stderr, not a guess
#   3. implement + guarded-replace (Design by Contract precondition)
#   4. read-back + re-run gdparse (Read-After-Write + Verification Before
#      Delivery)
#   5. no-op test against known-clean files before touching repair_rules
#      or applied_fixes in the real database
