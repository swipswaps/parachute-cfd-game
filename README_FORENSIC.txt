================================================================================
  Forensic HUD and HTTP Hub – Setup Instructions
================================================================================

Files written:
  - godot_project/scripts/forensic_hud.gd   (in‑game F3 overlay)
  - forensic_hub_v2.py                      (HTTP server, port 8765)
  - start_forensic.sh                       (launcher)
  - README_FORENSIC.txt                     (this file)

Step 1: Register the autoload in godot_project/project.godot
------------------------------------------------------------
Add the following line under the [autoload] section:

    ForensicHUD="*res://scripts/forensic_hud.gd"

If [autoload] does not exist, add it at the end of the file.

Step 2: Start the hub and game together
----------------------------------------
    ./start_forensic.sh

This will:
  - Launch forensic_hub_v2.py in the background
  - Wait 2 seconds for the hub to start
  - Launch autostall.py (your Godot game)
  - When the game exits, the hub is stopped automatically

Step 3: In the game, press F3 to toggle the HUD overlay
--------------------------------------------------------
The HUD will show:
  - Level, XP, Success/Fail counts, Longest streak
  - These numbers come from the same database as the web dashboard.

You can also open a browser at http://127.0.0.1:8765 to see the same data.

================================================================================
