import argparse
import re
import sys
from pathlib import Path

PATTERN = re.compile(r"\b(TODO|FIXME|HACK)\b")

TEXT_EXTS = {".gd", ".py", ".md", ".tscn", ".tres", ".cfg", ".ini", ".json"}
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
    "tools",
}


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return any(part in EXCLUDED_PARTS for part in parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}")
        return 2

    hits = []
    for path in root.rglob("*"):
        if path.is_dir() or should_skip(path) or path.suffix not in TEXT_EXTS:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for idx, line in enumerate(text.splitlines(), 1):
            if PATTERN.search(line):
                rel = path.relative_to(root)
                hits.append((rel, idx, line.strip()))

    if hits:
        print("TODO/FIXME/HACK tracker:")
        for rel, idx, line in hits:
            print(f"- {rel}:{idx} {line}")
        return 0

    print("TODO tracker: no markers found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
