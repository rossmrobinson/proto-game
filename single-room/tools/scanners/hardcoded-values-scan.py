import argparse
import re
import sys
from pathlib import Path


URL_PATTERN = re.compile(r"\b(?:https?|wss?|tcp|udp)://", re.IGNORECASE)
PORT_PATTERN = re.compile(r"\b(?:port|PORT|listen_port|server_port)\b[^\n]*\b(\d{2,5})\b")

TEXT_EXTS = {".gd", ".tscn", ".tres", ".cfg", ".ini", ".json", ".py"}
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


def scan_file(path: Path):
    hits = []
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return hits
    for idx, line in enumerate(text.splitlines(), 1):
        if URL_PATTERN.search(line):
            hits.append((idx, "url", line.strip()))
        if PORT_PATTERN.search(line):
            hits.append((idx, "port", line.strip()))
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}")
        return 2

    issues = []
    for path in root.rglob("*"):
        if path.is_dir() or should_skip(path) or path.suffix not in TEXT_EXTS:
            continue
        for line_no, kind, line in scan_file(path):
            issues.append((path, line_no, kind, line))

    if issues:
        print("Hardcoded value scan found potential issues:")
        for path, line_no, kind, line in issues:
            rel = path.relative_to(root)
            print(f"- {rel}:{line_no} [{kind}] {line}")
        return 1

    print("Hardcoded value scan: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
