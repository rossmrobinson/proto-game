import argparse
import re
import sys
from pathlib import Path

FUNC_PATTERN = re.compile(r"^\s*func\s+([A-Za-z0-9_]+)")
CTRL_PATTERN = re.compile(r"\b(if|elif|for|while|match|case)\b|&&|\|\|")
EXCLUDED_PARTS = {
    ".godot",
    "addons",
    ".venv",
    "venv",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    "node_modules",
    "logs",
    "llm-models",
    ".git",
}


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return any(part in EXCLUDED_PARTS for part in parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--max", type=int, default=35)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}")
        return 2

    issues = []
    for path in root.rglob("*.gd"):
        if should_skip(path):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        current = None
        complexity = 1
        for idx, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("#"):
                continue
            match = FUNC_PATTERN.match(line)
            if match:
                if current and complexity > args.max:
                    issues.append((path, current, complexity))
                current = match.group(1)
                complexity = 1
                continue
            if current:
                complexity += len(CTRL_PATTERN.findall(line))
        if current and complexity > args.max:
            issues.append((path, current, complexity))

    if issues:
        print("Cyclomatic complexity scan found functions over limit:")
        for path, func_name, score in issues:
            rel = path.relative_to(root)
            print(f"- {rel}:{func_name} complexity={score}")
        return 1

    print("Cyclomatic complexity scan: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
