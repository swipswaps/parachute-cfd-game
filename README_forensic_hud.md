# forensic_hud.gd  --  in-game client of forensic_hub_v2.py

## What this file does
Autoload `ForensicHUD` that draws a draggable overlay in the running Godot
game. It polls the same HTTP endpoints the browser view uses, so both views
show identical numbers -- a single source of truth.

    parachute_mutations.db (ro)
              |
              v
    forensic_hub_v2.py  (HTTP server, port 8765)
              |
      +-------+-------+
      v               v
    Browser        ForensicHUD (this file, F3 to toggle)

## Endpoints polled
- `GET /api/stats`  every 2 s
- `GET /api/tools`  every 5 s

## Config resolution (first match wins)
1. `ProjectSettings["application/forensic_hub/url"]`
2. env `FORENSIC_HUB_URL`
3. default `http://127.0.0.1:8765`

## Register as autoload
Add to `project.godot` under `[autoload]`:

    ForensicHUD="*res://scripts/forensic_hud.gd"

## Failure mode
If the hub is unreachable the status label shows verbatim:

    hub offline (URL)  result=N  code=N

where `result` is the `HTTPRequest.Result` enum int and `code` is the HTTP
response code. Game keeps running.

## Controls
- `F3` toggles the overlay.
- Left-click and drag anywhere on the panel to move it.

## Why the previous fix broke
The previous `apply_hud_fix.sh` wrote a version that extended `CanvasLayer`
but called `get_global_mouse_position()`, which is a `CanvasItem` method,
not a `CanvasLayer` method. Parse failed at `forensic_hud.gd:40` and `:49`
(see transcript lines 17554-17560). This rewrite extends `Node` and uses
`event.position` from `InputEventMouseButton`/`InputEventMouseMotion`,
which is defined on any input event and needs no `CanvasItem` method.
