from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def _resolve_path(raw: str | None, root: Path, fallback: Path) -> Path:
    if raw is None or raw.strip() == "":
        return fallback
    path: Path = Path(raw)
    if path.is_absolute():
        return path
    return root / path


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data: Any = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return data


def _extract_overrides(data: dict[str, Any]) -> dict[str, Any]:
    raw_overrides: Any = data.get("overrides", data)
    if not isinstance(raw_overrides, dict):
        raise ValueError("Overrides payload must be a JSON object")
    return raw_overrides


def _backup_existing(path: Path) -> Path:
    stamp: str = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path: Path = path.with_name(f"{path.stem}.backup-{stamp}{path.suffix}")
    backup_path.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return backup_path


def main() -> int:
    root: Path = Path(__file__).resolve().parents[1]
    default_profile: Path = root / "config" / "rig-review-safe-overrides.json"
    default_output: Path = root / "logs" / "llm_overrides.json"

    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Apply rig-review safe defaults into logs/llm_overrides.json"
    )
    parser.add_argument("--profile", type=str, default=None, help="Override profile path")
    parser.add_argument("--output", type=str, default=None, help="Output override path")
    parser.add_argument("--merge", action="store_true", help="Merge into existing output overrides")
    parser.add_argument("--dry-run", action="store_true", help="Print merged payload without writing")
    args: argparse.Namespace = parser.parse_args()

    profile_path: Path = _resolve_path(args.profile, root, default_profile)
    output_path: Path = _resolve_path(args.output, root, default_output)

    if not profile_path.exists():
        raise FileNotFoundError(f"Profile not found: {profile_path}")

    profile_data: dict[str, Any] = _load_json(profile_path)
    profile_overrides: dict[str, Any] = _extract_overrides(profile_data)

    merged_overrides: dict[str, Any] = {}
    if args.merge and output_path.exists():
        current_data: dict[str, Any] = _load_json(output_path)
        merged_overrides.update(_extract_overrides(current_data))
    merged_overrides.update(profile_overrides)

    payload: dict[str, Any] = {"overrides": merged_overrides}

    if args.dry_run:
        print(json.dumps(payload, indent=2))
        return 0

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        backup_path: Path = _backup_existing(output_path)
        print(f"Backup written: {backup_path}")

    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Profile source: {profile_path}")
    print(f"Overrides written: {output_path}")
    print(f"Keys applied: {len(merged_overrides)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
