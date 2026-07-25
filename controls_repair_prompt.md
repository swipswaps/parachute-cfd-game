# PATH: controls_repair_prompt.md
# CONTROLS REPAIR PROMPT — parachute-cfd-game
# Paste this as the first message of the repair session, with these files
# attached: build_terrain.gd, project.godot, setup_input_map.gd,
# evaluate_repo.py, run_patch.py, audit_all.py, skills_0066_new_entries.json

You are repairing the input/controls system of a Godot 4.6 project so the
game becomes playable end-to-end: SPACE deploys, state reaches DIAGNOSIS,
C runs flight check ONLY, Y cycles camera ONLY, Q/E turn, X/V/F work,
R reloads the scene. You will produce ONE Python patch script.

## GROUND TRUTH — verified defects (do not re-derive, do verify)

Run this FIRST and paste its complete output before writing any code:

    python3 evaluate_repo.py godot_project/scripts/build_terrain.gd \
        godot_project/project.godot godot_project/scripts/setup_input_map.gd

It must report these 6 defects. If it does not, STOP and report the
discrepancy instead of patching.

D1  STATE MACHINE DEAD TRANSITION — build_terrain.gd
    The only `_game_state = GameState.DIAGNOSIS` write (line ~1458) is
    inside `if _game_state == GameState.OPENING_ANIM` (line ~1452), and
    NO line ever assigns OPENING_ANIM. `_deploy_canopy()` (line ~652)
    sets `_canopy_deployed`/`_deployment_timer` but not the state.
    FIX: add `_game_state = GameState.OPENING_ANIM` in `_deploy_canopy()`
    immediately after `_deployment_timer = DEPLOY_TIME`, so the existing
    `_physics_process` animation block performs OPENING_ANIM -> DIAGNOSIS.
    Citation required: Godot state-machine pattern,
    https://docs.godotengine.org/en/stable/tutorials/scripting/state_machines.html

D2  INPUTMAP COLLISION — project.godot
    cycle_camera physical_keycode/keycode = 67 (C); flight_check also 67.
    One C press fires both actions.
    FIX: rebind cycle_camera to 89 (Y): keycode, physical_keycode, and
    unicode (121) fields, inside the cycle_camera block ONLY.
    Citation required: InputMap docs,
    https://docs.godotengine.org/en/stable/classes/class_inputmap.html

D3  TRIPLE INPUT PATHS — build_terrain.gd
    All seven one-shots (_deploy_canopy, _flight_control_check,
    _cycle_camera, _reset_game, _do_cutaway, _do_reserve, _do_flare)
    trigger from _poll_controls (raw KEY_* polling, lines ~1249-1331)
    AND _input (action block, lines ~1407-1438) AND _unhandled_input
    (lines ~1857-1901). _input marks only deploy/check_arms handled,
    so events propagate -> double/triple fire.
    FIX: _unhandled_input becomes the ONLY one-shot handler (leave it
    untouched). _input keeps ONLY its mouse-orbit + verbatim key-logging
    sections (delete the action block from the unique anchor comment
    "# Only accept input during active flight" to end of function).
    _poll_controls keeps ONLY continuous state: turn hold via
    is_action_pressed, _process_controller_input(), WASD camera move.
    Citation required: input event propagation order,
    https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html

D4  MANUAL RESET — build_terrain.gd
    _reset_game (line ~1335) performs a 29-assignment manual reset
    (source of the arm-disappearance bug).
    FIX: replace the body with get_tree().reload_current_scene().
    Citation required:
    https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-reload-current-scene

D5  COLLISION RE-INTRODUCTION HAZARD — setup_input_map.gd
    The EditorScript binds "cycle_camera": [KEY_Y, KEY_C]. Re-running it
    restores the C collision.
    FIX: change to [KEY_Y] and set "check_arms": [KEY_P] (matching
    project.godot keycode 80).

D6  DEAD ACTIONS — project.godot
    x_photo, v_replay, f_restart have empty events. Remove them or bind
    them; either way state the choice and why.

OUT OF SCOPE (declare, do not touch): the loading-screen/stale-screenshot
bug in _show_loading_screen (~line 1914). Mark it NOT COVERED.

## NON-NEGOTIABLE SCRIPT CONTRACT

1. INSPECT FIRST. Before emitting the patch script, print the verbatim
   bodies of every function you will modify (_deploy_canopy, _input,
   _poll_controls, _reset_game) from the attached file, with line numbers.
   If any expected function is missing or duplicated: say so and STOP.
2. Python only. No sed, no awk — including in commands given to the user.
3. Every multiline GDScript edit uses line-based function-bounds
   replacement or unique-anchor truncation with an
   `assert count == 1` guard. Regex only for single-line field edits
   (e.g. keycode numbers inside one named block).
4. NO f-strings anywhere near brace-bearing output. Input Map lines and
   any generated config use str.format() named placeholders or
   json.dumps. (Prior failure: f-string "single '}' is not allowed"
   killed two delivered scripts before any edit landed.)
5. Indentation: the file is 4-space indented. Inserted GDScript bodies
   must be 4-space. Fail fast if the file contains tab-indented lines.
6. Gates, in order, all printing [VERBATIM] evidence lines:
   a. PREFLIGHT: targets exist; skills_0066_new_entries.json (or newer)
      present; gdparse available (auto-install via pip with
      --break-system-packages); timestamped backups of BOTH files.
   b. gdparse pre-patch on build_terrain.gd.
   c. Patches D1, D3, D4 (gd file) with per-patch [VERBATIM] line counts.
   d. Read-back on the gd file: new markers present
      (reload_current_scene; OPENING_ANIM assignment in _deploy_canopy)
      AND old signatures absent (the poll one-shot lines; the _input
      action-block anchor comment). On any mismatch: restore backup,
      exit 1.
   e. gdparse post-patch; on failure restore backup and exit 1.
   f. Patches D2, D5, D6 (project.godot, setup_input_map.gd) then
      read-back: every required action present exactly once; the
      cycle_camera block contains no 67; setup_input_map.gd contains
      no KEY_C in the cycle_camera list.
   g. SCOPE lines: each of D1-D6 -> COVERED; loading screen -> NOT
      COVERED.
   h. "# IMPLEMENTATION COMPLETE" printed ONLY if a violations counter
      equals zero; otherwise exit nonzero. Never print success
      unconditionally.
7. Every WARNING path is sys.exit(1) — no WARNING-and-continue.
8. Citations: every behavioral claim in comments carries its Godot docs
   URL (the five URLs above at minimum). Tier rules per the rulebook:
   official docs require the direct URL.
9. Deliver: (a) the script, (b) a six-bullet list mapping D1-D6 to the
   exact patch each receives, (c) the verification checklist of gates
   it runs, (d) the expected [VERBATIM] success transcript. No claims of
   success — the transcript the USER pastes after running is the only
   proof.

## EXECUTION CONTRACT FOR YOU (the model)

Before delivery you must, in your own environment:
  - python3 -m py_compile the script (show output),
  - run it via `python3 run_patch.py <script> godot_project/scripts/build_terrain.gd godot_project/project.godot`
    against copies of the ATTACHED files (not a simplified mock — R131),
  - run `python3 evaluate_repo.py` on the PATCHED copies and show it
    reporting 0 (or only the declared NOT COVERED) defects,
  - run audit_all.py checks 120,122,125,127,128 on the script and 126,129
    on the patched gd, showing each PASS.
If any of these cannot be run, say which and why, and do not claim the
corresponding gate passed. The model's word is not evidence; tool output
is evidence.

## ACCEPTANCE TEST (user-side, after running the script)

    ./run_game.sh
Expected in-game, with matching [VERBATIM] log lines:
  SPACE -> "Parachute deployment started" then state OPENING_ANIM ->
  DIAGNOSIS after DEPLOY_TIME; C -> exactly ONE
  "ENTER _flight_control_check" and ZERO "_cycle_camera"; Y -> exactly
  ONE "ENTER _cycle_camera"; R -> "RESETTING GAME (reloading scene)"
  and arms present after reload; X/V/F each fire exactly once per press.
If any line fires twice per press, the repair FAILED — paste the log.
