import argparse
import re
import sys
from pathlib import Path

REF_PATTERN = re.compile(r"res://[^\s\"']+")

ASSET_EXTS = {
    ".tscn", ".tres", ".res", ".glb", ".blend", ".png", ".jpg", ".jpeg",
    ".tga", ".webp", ".wav", ".ogg", ".mp3", ".mp4",
}

REF_EXTS = {".gd", ".tscn", ".tres", ".cfg", ".ini", ".json", ".godot"}


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    return ".godot" in parts or "addons" in parts or "tools" in parts


def collect_references(root: Path) -> set[str]:
    refs = set()
    for path in root.rglob("*"):
        if path.is_dir() or should_skip(path) or path.suffix not in REF_EXTS:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in REF_PATTERN.findall(text):
            refs.add(match)
    return refs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}")
        return 2

    refs = collect_references(root)
    unused = []
    assets_root = root / "assets"
    if assets_root.exists():
        for path in assets_root.rglob("*"):
            if path.is_dir() or path.suffix not in ASSET_EXTS:
                continue
            res_path = f"res://{path.relative_to(root).as_posix()}"
            if res_path not in refs:
                unused.append(path.relative_to(root))

    if unused:
        print("Unused resource scan found candidates:")
        for path in sorted(unused):
            print(f"- {path}")
        return 1

    print("Unused resource scan: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
