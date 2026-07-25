# Assertion Gating Guide: Verifying Prose Claims Against File State

## Overview

This guide explains how to use three Python tools to **gate**, **log**, and **display affected lines** for every prose assertion in your development transcript.

The tools verify that claims made in prose (e.g., "line 1230 has `_paused = false`") actually match what's in the files.

---

## The Three Tools

### 1. `gate_assertions.py` — Specific Known Assertions

**Purpose**: Gate a pre-defined set of known assertions from the development transcript.

**What it verifies**:
- ✅ Unpause fix exists at lines 1229-1230
- ✅ Camera position code exists
- ✅ ResourceThrottle indentation (three pass statements with 2 tabs)
- ✅ HUD altitude label updates
- ✅ Physics process function defined
- ✅ All required input actions in project.godot

**Usage**:
```bash
cd /home/owner/Documents/69f7bcc6-1f68-83ea-b9b2-95a4db8629ac/parachute-cfd-game
python3 /home/claude/gate_assertions.py
```

**Output**:
```
[INFO] ASSERTION: Unpause: if _paused: _paused = false exists at lines 1229-1230 | STATUS: GATED
       Line 1229: →→if·_paused:
  >>>  Line 1230: →→→_paused·=·false
       Line 1231: →→→print("[VERBATIM]·Unpaused·by·key·press")
```

**Status indicators**:
- `GATED` ✅ — Assertion passed; code was found and matches claim
- `FALSIFIED` ❌ — Assertion failed; expected code not found or incorrect
- `UNVERIFIABLE` ⚠️ — File not found or unreadable

---

### 2. `extract_and_gate_assertions.py` — Extract and Gate Prose Claims

**Purpose**: Automatically extract prose assertions from the transcript, then gate each one against actual files.

**What it does**:
1. Parses the transcript to find prose claims like "The pattern X should match at line N"
2. Extracts regex patterns, file paths, line numbers, and expected content
3. Gates each extracted claim against the actual files
4. Displays affected lines with context

**Usage**:
```bash
python3 /home/claude/extract_and_gate_assertions.py
```

**Output format**:
```
✅ [1] The pattern `if _paused.*_paused = false` should match
   Status: GATED
   Affected lines:
     >>> 1229: →→if·_paused:
         1230: →→→_paused·=·false

❌ [2] File godot_project/scripts/build_terrain.gd contains _camera.position = Vector3(0, 200, 300)
   Status: FALSIFIED
   Reason: Expected text not found: _camera.position = Vector3(0, 200, 300)
```

---

### 3. `gate_transcript_terminal_output.py` — Gate Against Terminal Output

**Purpose**: Gate prose assertions against the actual terminal output embedded in the transcript (lines 14794-14826), which shows the real file state.

**What it does**:
1. Extracts the terminal output sections from the transcript
2. Verifies that prose claims match the actual output shown
3. Highlights discrepancies immediately

**Usage**:
```bash
python3 /home/claude/gate_transcript_terminal_output.py
```

**Output**:
```
✅ ASSERTION 1: Unpause: Pattern 'if _paused: _paused = false' exists
   Status: GATED
   Section: Unpause lines
   Affected lines from terminal output:
     1229: →→if·_paused:
     1230: →→→_paused·=·false

❌ ASSERTION 2: Camera: Line ~311-325 should contain camera position setup
   Status: FALSIFIED
   REASON: Pattern not found in shown range
   (sample) 311: →var·dz_mat·=·StandardMaterial3D.new()
   (sample) 312: →dz_mat.albedo_color·=·Color(1.0,·0.8,·0.0,·0.85)
```

---

## Understanding the Output Format

### Whitespace Visualization

The tools display whitespace using special characters so you can verify indentation exactly:

- `→` = one tab character
- `·` = one space character
- Normal text = actual characters

Example:
```
1229: →→if·_paused:
```
This means: 2 tabs, then "if", then space, then "_paused:"

### Status Symbols

- `✅ GATED` — Prose claim verified against actual file content
- `❌ FALSIFIED` — Prose claim does not match actual file content
- `⚠️ UNVERIFIABLE` — File not found, cannot verify claim
- `ℹ️ INFO` — Requires manual review (e.g., special claims)

### Affected Lines Display

Each gated assertion shows relevant file lines with context:

```
>>>  1230: →→→_paused·=·false
     1231: →→→print("[VERBATIM]·Unpaused·by·key·press")
     1232: →#·Unpause·on·any·key·press
```

The `>>>` marker shows the line that matched the claim. Lines above/below provide context.

---

## How to Interpret Results

### GATED ✅ Assertion

**What it means**: The prose claim is accurate. The code you described actually exists in the file, with the exact content and location claimed.

**Example**:
```
✅ Unpause: if _paused: _paused = false exists at lines 1229-1230 | STATUS: GATED
```

**Action**: No action needed. The claim is verified.

### FALSIFIED ❌ Assertion

**What it means**: The prose claim is inaccurate. Either:
- The code doesn't exist where you said it would
- The code exists but with different content/indentation
- The file doesn't have that code at all

**Example**:
```
❌ Camera: _camera.position = Vector3(0, 200, 300) | STATUS: FALSIFIED
   Reason: Expected text not found: _camera.position = Vector3(0, 200, 300)
```

**Action**: 
1. Verify the actual location of the code using `grep`
2. Check if the code exists with different formatting
3. Rewrite the claim to match actual file state, or apply the fix

### UNVERIFIABLE ⚠️ Assertion

**What it means**: The file doesn't exist or can't be read, so the claim cannot be verified either way.

**Example**:
```
⚠️ File godot_project/old_scripts/backup.gd | STATUS: UNVERIFIABLE
   File not found: /home/owner/.../godot_project/old_scripts/backup.gd
```

**Action**: 
1. Check the file path is correct
2. Verify the file exists
3. Check read permissions

---

## Workflow: From Assertion to Verified Fix

### Step 1: Extract Assertions from Prose

Read your development notes and identify claims:

- "Line 1230 has `_paused = false`"
- "Pattern `if _paused:` should match at line 1229"
- "Camera position set to Vector3(0, 200, 300)"

### Step 2: Run the Extraction Tool

```bash
python3 /home/claude/extract_and_gate_assertions.py 2>&1 | tee gating_report.txt
```

### Step 3: Review Gating Results

Check the report for:
- **GATED claims**: Already verified, no action needed
- **FALSIFIED claims**: Need investigation and fix

### Step 4: For Each FALSIFIED Claim

Use `grep` to find the actual code location:

```bash
cd /home/owner/Documents/.../parachute-cfd-game
grep -n "_camera.position" godot_project/scripts/build_terrain.gd
grep -n "if _paused" godot_project/scripts/build_terrain.gd
```

### Step 5: Update the Claim or Apply the Fix

If code is missing:
```bash
# Apply the fix
python3 /path/to/fix_script.py

# Re-gate to verify
python3 /home/claude/gate_assertions.py
```

If claim location is wrong:
```bash
# Update your notes with actual line numbers
# Re-run gating with corrected paths
```

---

## Key Rules for Prose Assertions

### Rule: Every Assertion Must be Gatable

A prose claim must include enough specificity for a tool to verify it:

❌ **Too vague**:
> "The unpause code should be there somewhere"

✅ **Specific and gatable**:
> "Pattern `if _paused:` followed by `_paused = false` exists at lines 1229-1230"

### Rule: Whitespace Matters

Indentation is code structure. If your claim says "two-tab indentation", the assertion will fail if it has one tab or four spaces instead.

### Rule: Exact Content or Fuzzy Pattern, Not Both

Choose one:
- **Exact**: "Line 1230 is exactly: `→→→_paused = false`"
- **Pattern**: "File contains pattern: `_paused\s*=\s*false`"

Don't mix both in the same claim.

---

## Common Issues and Fixes

### Issue: "Pattern found" but then "Pattern not found"

**Cause**: The regex pattern is too strict or matches across line boundaries.

**Solution**: Use `re.search(..., re.MULTILINE)` in the tool. Most tools already do this.

### Issue: Line numbers are off by one

**Cause**: Human line counting (1-indexed) vs computer line counting (0-indexed).

**Solution**: Tools automatically handle this. Line 1 in display is index 0 in arrays.

### Issue: Whitespace doesn't match even though content looks the same

**Cause**: You're using spaces instead of tabs (or vice versa), or the count is different.

**Solution**: Always use the whitespace-visible output (→ and ·) to see the actual difference.

### Issue: Tool says "File not found" but I can see the file exists

**Cause**: Path is relative, not absolute. Tool is looking in wrong location.

**Solution**: Pass `--base-dir` to specify the correct base directory, or `cd` to the right location.

---

## Logging: Where Outputs Are Stored

All three tools print to stdout. To save results:

```bash
# Save all outputs to a single file
python3 /home/claude/gate_assertions.py > gating_all.log 2>&1
python3 /home/claude/extract_and_gate_assertions.py >> gating_all.log 2>&1
python3 /home/claude/gate_transcript_terminal_output.py >> gating_all.log 2>&1

# Review the log
cat gating_all.log | grep -E "(GATED|FALSIFIED|UNVERIFIABLE)" | sort | uniq -c
```

---

## Advanced: Custom Assertions

To add your own assertions, edit `gate_assertions.py` and add methods like:

```python
def verify_my_custom_claim(self):
    """Assertion: My custom claim here"""
    assertion = Assertion(
        line_num=123,  # line in transcript where you made the claim
        description="My custom claim description",
        file_path="godot_project/scripts/MyScript.gd",
        pattern=r'some_function\(\s*\)',  # regex to match
    )
    status, affected = self.gate_assertion(assertion)
    self.log(f"ASSERTION: {assertion.description} | STATUS: {status}")
    for line in affected:
        self.log(f"  {line}")
    self.assertions.append((assertion, status))
```

Then call it from `main()`:

```python
def main():
    gate = AssertionGate()
    # ... existing verifications ...
    gate.verify_my_custom_claim()  # Add your custom verification
    gate.report_summary()
```

---

## Summary

| Tool | Purpose | Input | Output |
|------|---------|-------|--------|
| `gate_assertions.py` | Gate known specific assertions | None (hardcoded) | ✅ GATED / ❌ FALSIFIED status |
| `extract_and_gate_assertions.py` | Extract and gate all prose claims | Transcript file | Extracted claims + status for each |
| `gate_transcript_terminal_output.py` | Verify claims against terminal output | Transcript (internal) | Verification against ground truth |

**Use all three** to get complete coverage of your prose assertions.

**Order to run**:
1. `gate_transcript_terminal_output.py` — Ground truth check (fastest)
2. `gate_assertions.py` — Known assertions (quick spot-checks)
3. `extract_and_gate_assertions.py` — Comprehensive scan (thorough)

---

## Rule 0 Self-Check

This guide implements the following principles:

- ✅ **Every assertion has a test** — each claim can be verified
- ✅ **Whitespace is visible** — indentation mismatches are immediately clear
- ✅ **Affected lines are shown** — the exact code that passes/fails is visible
- ✅ **Status is unambiguous** — GATED/FALSIFIED/UNVERIFIABLE leaves no room for doubt
- ✅ **Logging is comprehensive** — all results can be saved to file and reviewed

This prevents the pattern where prose claims are accepted without verification, leading to inconsistent development and hard-to-debug failures.
