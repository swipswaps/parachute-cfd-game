#!/usr/bin/env python3
import sys
from pathlib import Path
from dataclasses import dataclass

@dataclass
class FuncBlock:
    name: str
    start: int
    end: int
    lines: list

def is_func_header(line: str) -> bool:
    s = line.lstrip()
    return s.startswith("func ") or s.startswith("static func ")

def get_func_name(line: str) -> str:
    s = line.lstrip()
    if s.startswith("static func "):
        s = s[len("static func "):]
    else:
        s = s[len("func "):]
    return s.split("(", 1)[0].strip()

def indent_width(line: str) -> int:
    n = 0
    for ch in line:
        if ch == "\t":
            n += 4
        elif ch == " ":
            n += 1
        else:
            break
    return n

def find_function_blocks(lines):
    blocks = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        if is_func_header(line):
            start = i
            base_indent = indent_width(line)
            name = get_func_name(line)
            j = i + 1

            while j < n:
                nxt = lines[j]
                stripped = nxt.strip()

                if stripped == "":
                    j += 1
                    continue

                if is_func_header(nxt) and indent_width(nxt) <= base_indent:
                    break

                if indent_width(nxt) <= base_indent and not stripped.startswith("#"):
                    break

                j += 1

            blocks.append(FuncBlock(name=name, start=start + 1, end=j, lines=lines[start:j]))
            i = j
        else:
            i += 1

    return blocks

def analyze_block(block: FuncBlock, seen_names: dict):
    text = "\n".join(block.lines)
    stripped_lines = [ln.strip() for ln in block.lines if ln.strip()]
    issues = []

    if seen_names.get(block.name, 0) > 1:
        issues.append("duplicate_function_name")

    if any(ln.startswith("func ") or ln.startswith("static func ") for ln in stripped_lines[1:]):
        issues.append("nested_function_header")

    if text.count("if _game_state in [GameState.LANDED, GameState.GAME_OVER]:") > 0:
        for idx, ln in enumerate(block.lines):
            if "if _game_state in [GameState.LANDED, GameState.GAME_OVER]:" in ln:
                if idx + 1 < len(block.lines):
                    nxt = block.lines[idx + 1]
                    if nxt.strip() == "return" and not nxt.startswith("\t"):
                        issues.append("bad_return_indentation")

    open_parens = text.count("(") - text.count(")")
    open_brackets = text.count("[") - text.count("]")
    open_braces = text.count("{") - text.count("}")

    if open_parens != 0 or open_brackets != 0 or open_braces != 0:
        issues.append("unbalanced_delimiters")

    if len(stripped_lines) <= 1:
        issues.append("empty_block")

    if issues:
        if "duplicate_function_name" in issues or "nested_function_header" in issues or "bad_return_indentation" in issues or "unbalanced_delimiters" in issues:
            verdict = "REMOVE"
        else:
            verdict = "NEEDS WORK"
    else:
        verdict = "WORKS"

    return verdict, issues

def main():
    if len(sys.argv) < 2:
        print("Usage: python scan_gd.py path/to/file.gd")
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}")
        sys.exit(1)

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    blocks = find_function_blocks(lines)

    seen_names = {}
    for b in blocks:
        seen_names[b.name] = seen_names.get(b.name, 0) + 1

    print("FUNCTION REPORT")
    print("=" * 60)

    works = needs = remove = 0

    for b in blocks:
        verdict, issues = analyze_block(b, seen_names)
        if verdict == "WORKS":
            works += 1
        elif verdict == "NEEDS WORK":
            needs += 1
        else:
            remove += 1

        dup = " duplicate" if seen_names.get(b.name, 0) > 1 else ""
        print(f"{verdict}: {b.name}{dup}  (lines {b.start}-{b.end})")
        if issues:
            print("  issues: " + ", ".join(issues))

    print("\nSUMMARY")
    print("=" * 60)
    print(f"functions: {len(blocks)}")
    print(f"WORKS: {works}")
    print(f"NEEDS WORK: {needs}")
    print(f"REMOVE: {remove}")

if __name__ == "__main__":
    main()