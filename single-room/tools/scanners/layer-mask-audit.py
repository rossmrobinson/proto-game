import argparse
import re
import sys
from pathlib import Path

LAYER_PATTERN = re.compile(r'3d_physics/layer_(\d+)\s*=\s*"([^"]+)"')
CALL_PATTERN = re.compile(r"set_collision_(layer|mask)_value\((\d+)")


def parse_layers(project_path: Path):
    layers = set()
    text = project_path.read_text(encoding="utf-8", errors="ignore")
    for line in text.splitlines():
        match = LAYER_PATTERN.search(line)
        if match:
            layers.add(int(match.group(1)))
    return layers


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return ".godot" in parts or "addons" in parts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    project = root / "project.godot"
    if not project.exists():
        print("project.godot not found")
        return 2

    layers = parse_layers(project)
    if not layers:
        print("No physics layers found in project.godot")
        return 2

    issues = []
    for path in root.rglob("*.gd"):
        if should_skip(path):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for idx, line in enumerate(text.splitlines(), 1):
            match = CALL_PATTERN.search(line)
            if match:
                index = int(match.group(2))
                if index not in layers:
                    rel = path.relative_to(root)
                    issues.append((rel, idx, index, line.strip()))

    if issues:
        print("Layer/mask audit found out-of-range indices:")
        for rel, idx, index, line in issues:
            print(f"- {rel}:{idx} [layer {index}] {line}")
        return 1

    print("Layer/mask audit: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
