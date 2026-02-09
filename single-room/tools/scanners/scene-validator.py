import argparse
import re
import sys
from pathlib import Path

NODE_PATTERN = re.compile(r"^\[node name=\"([^\"]+)\"")
PASCAL_PATTERN = re.compile(r"^[A-Z][A-Za-z0-9]*$")


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return ".godot" in parts or "addons" in parts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--check-filenames", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}")
        return 2

    issues = []
    for path in root.rglob("*.tscn"):
        if should_skip(path):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for idx, line in enumerate(text.splitlines(), 1):
            match = NODE_PATTERN.match(line.strip())
            if not match:
                continue
            name = match.group(1)
            if " " in name:
                issues.append((path, idx, f"node name has spaces: {name}"))
            elif not PASCAL_PATTERN.match(name):
                issues.append((path, idx, f"node name not PascalCase: {name}"))

        if args.check_filenames:
            stem = path.stem
            if " " in stem or "-" in stem:
                issues.append((path, 1, f"file name should be snake_case: {path.name}"))

    if issues:
        print("Scene validator issues:")
        for path, idx, msg in issues:
            rel = path.relative_to(root)
            print(f"- {rel}:{idx} {msg}")
        return 1

    print("Scene validator: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
