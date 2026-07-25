#!/usr/bin/env python3
"""Patches autostall.py to insert gamification hooks."""
import sys, shutil

AUTOSTALL = "autostall.py"   # we run from project root
BACKUP = AUTOSTALL + ".bak"

def patch():
    with open(AUTOSTALL, 'r') as f:
        lines = f.readlines()
    shutil.copy2(AUTOSTALL, BACKUP)
    print("[PATCHER] Backup saved as", BACKUP)

    # 1. Insert import after the first import line
    import_inserted = False
    for i, line in enumerate(lines):
        if line.startswith("import ") and not import_inserted:
            lines.insert(i+1, "from gamification.logbook import init_db, start_flight, end_flight, record_fix_category\n")
            import_inserted = True
            break

    # 2. Add global variables inside main(), after display setup
    main_start = None
    for i, line in enumerate(lines):
        if line.strip().startswith("def main():"):
            main_start = i
            break
    # locate the line 'os.environ["DISPLAY"] = display' and then the end of the if/else block
    display_end = None
    for j in range(main_start, len(lines)):
        if 'os.environ["DISPLAY"]' in lines[j] and 'display' in lines[j]:
            # find the next line that is not indented further (end of the if/else)
            k = j+1
            while k < len(lines):
                if lines[k].strip() and not lines[k].startswith("    "):
                    break
                k += 1
            display_end = k
            break
    if display_end:
        indent = "    "
        insert_lines = [
            f"{indent}# -- Gamification start --\n",
            f"{indent}init_db()\n",
            f"{indent}_flight_id = start_flight()\n",
            f"{indent}_pilot_name = 'default'\n",
            f"{indent}_fixes_attempted = 0\n",
            f"{indent}# -- Gamification end --\n",
        ]
        for line in reversed(insert_lines):
            lines.insert(display_end, line)

    # 3. Insert record_fix_category for indent / null‑texture fixes
    for i, line in enumerate(lines):
        if 'store_error(gd_file, gd_line, f"Fix attempted at' in line and 'status="fix_attempted"' in line:
            context = "".join(lines[max(0,i-5):i])
            indent = line[:len(line) - len(line.lstrip())]
            if "indentation" in context.lower():
                lines.insert(i+1, f'{indent}record_fix_category(_pilot_name, "Indent")\n')
                print("[PATCHER] Inserted indent fix category hook.")
            elif "null" in context.lower() or "screenshot" in context.lower():
                lines.insert(i+1, f'{indent}record_fix_category(_pilot_name, "NullTexture")\n')
                print("[PATCHER] Inserted null texture fix category hook.")

    # 4. Insert end_flight call before the summary line
    for i, line in enumerate(lines):
        if line.strip().startswith('print("[SUMMARY] autostall.py finished.")'):
            insert_pos = i
            break
    else:
        # fallback: before if __name__ == "__main__"
        for i, line in enumerate(lines):
            if line.strip().startswith("if __name__"):
                insert_pos = i
                break
    if insert_pos:
        block = [
            '    # -- Gamification flight end --\n',
            '    if _flight_id is not None:\n',
            '        outcome = "landed" if game_completed else ("aborted" if proc.returncode == 0 else "crashed")\n',
            '        bugs_encountered = sum(1 for l in output_buffer if "SCRIPT ERROR" in l or "ERROR:" in l)\n',
            '        end_flight(_flight_id, outcome, bugs_encountered=bugs_encountered,\n',
            '                   bugs_fixed=fix_attempted_this_run,\n',
            '                   notes=f"fix_attempted={fix_attempted_this_run}")\n',
            '    # -- End gamification --\n',
        ]
        for line in reversed(block):
            lines.insert(insert_pos, line)

    with open(AUTOSTALL, 'w') as f:
        f.writelines(lines)
    print("[PATCHER] autostall.py patched successfully.")

if __name__ == "__main__":
    patch()
