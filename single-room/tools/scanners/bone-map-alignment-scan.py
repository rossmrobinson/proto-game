#!/usr/bin/env python3
"""Validate rig bone-map alignment across Godot and Blender tooling.

Checks:
1) `ragdoll_proportions.gd` BONE_NAME_MAP matches
   `blender-rig-dump.py` GODOT_BONE_NAME_MAP (including generated passage keys).
2) All bones created by `blender-add-soft-tissue-bones.py` are present in
   Godot BONE_NAME_MAP and map to themselves.

Exit code 0 on success, 1 on any drift.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _extract_gd_bone_map(content: str) -> dict[str, str]:
    block_match = re.search(
        r"const\s+BONE_NAME_MAP\s*:\s*Dictionary\s*=\s*\{(.*?)\n\}",
        content,
        re.S,
    )
    if block_match is None:
        raise ValueError("Could not find BONE_NAME_MAP in ragdoll_proportions.gd")
    return {
        key: value
        for key, value in re.findall(r'"([^\"]+)"\s*:\s*"([^\"]+)"', block_match.group(1))
    }


def _extract_rig_dump_bone_map(content: str) -> dict[str, str]:
    block_match = re.search(
        r"GODOT_BONE_NAME_MAP\s*:\s*dict\[str,\s*str\]\s*=\s*\{(.*?)\n\}",
        content,
        re.S,
    )
    if block_match is None:
        raise ValueError("Could not find GODOT_BONE_NAME_MAP in blender-rig-dump.py")

    result: dict[str, str] = {
        key: value
        for key, value in re.findall(r'"([^\"]+)"\s*:\s*"([^\"]+)"', block_match.group(1))
    }

    for tunnel in ("vaginal", "anal"):
        for depth in range(8):
            for quadrant in ("top", "bot", "left", "right"):
                name = f"{tunnel}_passage_{depth}_{quadrant}"
                result[name] = name

    for depth in range(5):
        for quadrant in ("top", "bot", "left", "right"):
            name = f"oral_passage_{depth}_{quadrant}"
            result[name] = name

    return result


def _extract_tuple_names(content: str, list_name: str) -> set[str]:
    list_match = re.search(rf"{list_name}\s*:\s*list\[tuple\]\s*=\s*\[(.*?)\n\]", content, re.S)
    if list_match is None:
        raise ValueError(f"Could not find {list_name} in blender-add-soft-tissue-bones.py")
    return set(re.findall(r'\(\s*"([^\"]+)"\s*,', list_match.group(1)))


def _expected_custom_soft_tissue_bones(add_soft_tissue_content: str) -> set[str]:
    names: set[str] = set()
    for var_name in ("GLUTE_BONES", "BREAST_BONES", "MALE_GENITAL_BONES", "FEMALE_GENITAL_BONES"):
        names.update(_extract_tuple_names(add_soft_tissue_content, var_name))

    for tunnel in ("vaginal", "anal"):
        for quadrant in ("top", "bot", "left", "right"):
            names.add(f"{tunnel}_ring_{quadrant}")
        for depth in range(8):
            for quadrant in ("top", "bot", "left", "right"):
                names.add(f"{tunnel}_passage_{depth}_{quadrant}")

    for quadrant in ("top", "bot", "left", "right"):
        names.add(f"oral_ring_{quadrant}")
    for depth in range(5):
        for quadrant in ("top", "bot", "left", "right"):
            names.add(f"oral_passage_{depth}_{quadrant}")

    return names


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Godot/Blender bone-map alignment")
    parser.add_argument("--root", required=True, help="Project root path")
    args = parser.parse_args()

    root = Path(args.root)
    proportions_path = root / "scripts" / "npc" / "ragdoll_proportions.gd"
    rig_dump_path = root / "tools" / "blender-rig-dump.py"
    add_soft_tissue_path = root / "tools" / "blender-add-soft-tissue-bones.py"

    gd_map = _extract_gd_bone_map(_read(proportions_path))
    rig_dump_map = _extract_rig_dump_bone_map(_read(rig_dump_path))

    errors: list[str] = []

    missing_in_rig_dump = sorted(set(gd_map) - set(rig_dump_map))
    extra_in_rig_dump = sorted(set(rig_dump_map) - set(gd_map))
    if missing_in_rig_dump:
        errors.append(
            f"Rig dump map missing {len(missing_in_rig_dump)} keys: "
            + ", ".join(missing_in_rig_dump[:12])
        )
    if extra_in_rig_dump:
        errors.append(
            f"Rig dump map has {len(extra_in_rig_dump)} extra keys: "
            + ", ".join(extra_in_rig_dump[:12])
        )

    shared_keys = sorted(set(gd_map) & set(rig_dump_map))
    mismatched_values = [k for k in shared_keys if gd_map[k] != rig_dump_map[k]]
    if mismatched_values:
        preview = ", ".join(f"{k}=>{gd_map[k]}/{rig_dump_map[k]}" for k in mismatched_values[:12])
        errors.append(f"Map value mismatches ({len(mismatched_values)}): {preview}")

    custom_expected = _expected_custom_soft_tissue_bones(_read(add_soft_tissue_path))
    missing_custom = sorted(name for name in custom_expected if gd_map.get(name) != name)
    if missing_custom:
        errors.append(
            f"Custom soft-tissue/passage names missing or non-identity in Godot map ({len(missing_custom)}): "
            + ", ".join(missing_custom[:12])
        )

    if errors:
        print("Bone-map alignment: FAIL")
        for message in errors:
            print(f"  - {message}")
        return 1

    print(
        "Bone-map alignment: OK "
        f"(gd={len(gd_map)} keys, rig_dump={len(rig_dump_map)} keys, custom={len(custom_expected)} names)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
