# Pattern Miner report — run 2

- project_root: `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game`
- source_db:    `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/parachute_mutations.db`  (read-only)
- parser:       `gdparse`
- .gd files scanned: **2**
- working:      **1**
- failing:      **1**
- unknown:      **0**

---

## `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/scripts/plane.gd`  line 14  [no-class]

**Signature at failure**:  `if` at indent 1

### Current window (before fix)

```gdscript
		),
		InputMap.has_action("deploy")
	)
	if not InputMap.has_action("deploy");:
print(
			(
				Time.get_datetime_string_from_system()
```

### Parser stderr

```
/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/scripts/plane.gd:

	if not InputMap.has_action("deploy");:
                                            ^

Unexpected token Token('SEMICOLON', ';') at line 14, column 38.
Expected one of: 
	* COLON


```

### Mined candidates (3)

#### Candidate #1  — from `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/godot_project/scripts/build_terrain.gd` line 252  (dir distance 3, score 73.0)

**Template (verbatim from working sibling)**

```gdscript
	# Ref: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
	# --------------------------------------------------------------
	var file = FileAccess.open("res://assets/terrain/heightmap_512.raw", FileAccess.READ)
	if file:
		# --- Heightmap exists: generate detailed terrain ---
		var data = file.get_buffer(file.get_length())
		file.close()
```

**Dry-run unified diff** (not applied)

```diff
--- /home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/scripts/plane.gd:11-17 (current)
+++ MINED_TEMPLATE (dry-run — not applied)
@@ -1,7 +1,7 @@
-		),
-		InputMap.has_action("deploy")
-	)
-	if not InputMap.has_action("deploy");:
-print(
-			(
-				Time.get_datetime_string_from_system()
+	# Ref: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
+	# --------------------------------------------------------------
+	var file = FileAccess.open("res://assets/terrain/heightmap_512.raw", FileAccess.READ)
+	if file:
+		# --- Heightmap exists: generate detailed terrain ---
+		var data = file.get_buffer(file.get_length())
+		file.close()
```

#### Candidate #2  — from `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/godot_project/scripts/build_terrain.gd` line 374  (dir distance 3, score 73.0)

**Template (verbatim from working sibling)**

```gdscript
	add_child(_camera)

	# Ensure plane exists before positioning camera
	if _plane_node:
		# Position camera using orbit angles
		var plane_pos = _plane_node.global_position
		var offset = Vector3(0, 0, -_cam_distance)
```

**Dry-run unified diff** (not applied)

```diff
--- /home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/scripts/plane.gd:11-17 (current)
+++ MINED_TEMPLATE (dry-run — not applied)
@@ -1,7 +1,7 @@
-		),
-		InputMap.has_action("deploy")
-	)
-	if not InputMap.has_action("deploy");:
-print(
-			(
-				Time.get_datetime_string_from_system()
+	add_child(_camera)
+
+	# Ensure plane exists before positioning camera
+	if _plane_node:
+		# Position camera using orbit angles
+		var plane_pos = _plane_node.global_position
+		var offset = Vector3(0, 0, -_cam_distance)
```

#### Candidate #3  — from `/home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/godot_project/scripts/build_terrain.gd` line 417  (dir distance 3, score 73.0)

**Template (verbatim from working sibling)**

```gdscript
	# HUD (8 lines + score + notification)
	# Ref: https://docs.godotengine.org/en/stable/classes/class_label.html
	# --------------------------------------------------------------
	if _hud_layer:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 1
```

**Dry-run unified diff** (not applied)

```diff
--- /home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game/scripts/plane.gd:11-17 (current)
+++ MINED_TEMPLATE (dry-run — not applied)
@@ -1,7 +1,7 @@
-		),
-		InputMap.has_action("deploy")
-	)
-	if not InputMap.has_action("deploy");:
-print(
-			(
-				Time.get_datetime_string_from_system()
+	# HUD (8 lines + score + notification)
+	# Ref: https://docs.godotengine.org/en/stable/classes/class_label.html
+	# --------------------------------------------------------------
+	if _hud_layer:
+		return
+	_hud_layer = CanvasLayer.new()
+	_hud_layer.layer = 1
```

---
