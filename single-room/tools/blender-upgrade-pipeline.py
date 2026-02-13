#!/usr/bin/env python3
"""One-click MotionBuilder→custom rig upgrade pipeline for Blender.

Runs, in order:
1) `blender-add-soft-tissue-bones.py`
2) Optional `.blend` save
3) `blender-rig-dump.py`
4) Summary + optional rig-dump copy into project

This orchestrator runs OUTSIDE Blender and launches Blender in batch mode.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def _resolve_blender_path(raw_path: str | None) -> Path:
    if raw_path is not None and raw_path.strip() != "":
        blender_path: Path = Path(raw_path).expanduser()
    else:
        env_path: str = os.getenv("BLENDER_PATH", "")
        if env_path.strip() != "":
            blender_path = Path(env_path).expanduser()
        else:
            which_path: str | None = shutil.which("blender")
            if which_path is None:
                raise FileNotFoundError(
                    "Blender executable not found. Pass --blender-path or set BLENDER_PATH."
                )
            blender_path = Path(which_path)

    if not blender_path.exists():
        raise FileNotFoundError(f"Blender executable not found: {blender_path}")
    return blender_path


def _bootstrap_code() -> str:
    return """
from __future__ import annotations

import json
import os
import runpy
import traceback
from pathlib import Path
import sys

import bpy  # type: ignore


def _run_script(path: Path, step: str, report: dict) -> bool:
    try:
        runpy.run_path(str(path), run_name="__main__")
        report["steps"][step] = {"ok": True}
        return True
    except Exception as exc:  # pragma: no cover - executed inside Blender
        report["steps"][step] = {
            "ok": False,
            "error": str(exc),
            "trace": traceback.format_exc(),
        }
        return False


def _rig_dump_output_path() -> str:
    blend_path: str = bpy.data.filepath
    if blend_path:
        blend_file: Path = Path(blend_path)
        return str(blend_file.with_name(f"{blend_file.stem}-rig-dump.json"))
    return str(Path.home() / "blender-rig-dump.json")


def main() -> int:
    argv: list[str] = sys.argv
    if "--" not in argv:
        raise SystemExit("Missing '--' args for bootstrap")

    args: list[str] = argv[argv.index("--") + 1 :]
    if len(args) != 7:
        raise SystemExit(
            "Expected args: <add_script> <dump_script> <report_path> <save_flag> <armature_filter> <sex_profile> <male_armatures>"
        )

    add_script: Path = Path(args[0])
    dump_script: Path = Path(args[1])
    report_path: Path = Path(args[2])
    save_flag: bool = args[3] == "1"
    armature_filter: str = "" if args[4] == "__ALL__" else args[4].strip()
    sex_profile: str = args[5].strip().lower()
    male_armatures: str = args[6].strip()

    report: dict = {
        "ok": False,
        "steps": {},
        "blend_path": bpy.data.filepath,
        "rig_dump_path": "",
        "armature_filter": armature_filter,
        "sex_profile": sex_profile,
        "male_armatures": male_armatures,
    }

    if armature_filter:
        os.environ["SOFT_TISSUE_ARMATURE"] = armature_filter
    else:
        os.environ.pop("SOFT_TISSUE_ARMATURE", None)

    os.environ["SOFT_TISSUE_SEX"] = sex_profile if sex_profile else "auto"
    os.environ["SOFT_TISSUE_MALE_ARMATURES"] = male_armatures

    add_ok: bool = _run_script(add_script, "add_soft_tissue", report)

    if add_ok and save_flag:
        try:
            bpy.ops.wm.save_mainfile()
            report["steps"]["save_blend"] = {"ok": True}
        except Exception as exc:  # pragma: no cover - executed inside Blender
            report["steps"]["save_blend"] = {
                "ok": False,
                "error": str(exc),
                "trace": traceback.format_exc(),
            }
            add_ok = False

    dump_ok: bool = False
    if add_ok:
        if armature_filter:
            os.environ["RIG_DUMP_ARMATURE"] = armature_filter
        else:
            os.environ.pop("RIG_DUMP_ARMATURE", None)
        dump_ok = _run_script(dump_script, "rig_dump", report)

    report["rig_dump_path"] = _rig_dump_output_path()
    report["ok"] = bool(add_ok and dump_ok)

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
""".lstrip()


def _write_temp_bootstrap(root: Path) -> Path:
    tmp_dir: Path = root / "tools" / "cache" / "tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        suffix="-upgrade-bootstrap.py",
        prefix="blender-",
        dir=tmp_dir,
        delete=False,
    ) as handle:
        handle.write(_bootstrap_code())
        return Path(handle.name)


def _run_blender_pipeline(
    blender_path: Path,
    blend_path: Path,
    add_script: Path,
    dump_script: Path,
    bootstrap_path: Path,
    report_path: Path,
    save_blend: bool,
    armature_name: str | None,
    sex_profile: str,
    male_armatures: str,
    cwd: Path,
) -> int:
    armature_arg: str = armature_name.strip() if isinstance(armature_name, str) else ""
    if armature_arg == "":
        armature_arg = "__ALL__"

    command: list[str] = [
        str(blender_path),
        "-b",
        str(blend_path),
        "--python",
        str(bootstrap_path),
        "--",
        str(add_script),
        str(dump_script),
        str(report_path),
        "1" if save_blend else "0",
        armature_arg,
        sex_profile,
        male_armatures,
    ]

    process: subprocess.CompletedProcess[str] = subprocess.run(
        command,
        cwd=str(cwd),
        check=False,
        text=True,
    )
    return int(process.returncode)


def _load_json(path: Path) -> dict[str, Any]:
    data: Any = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return data


def _print_summary(rig_dump_data: list[dict[str, Any]]) -> tuple[int, int, int]:
    total_bones: int = 0
    total_unmapped_deform: int = 0
    total_custom: int = 0

    print("\n=== Upgrade Summary ===")
    for rig in rig_dump_data:
        rig_name: str = str(rig.get("armature_name", "<unknown>"))
        bone_count: int = int(rig.get("bone_count", 0))
        unmapped: int = int(rig.get("unmapped_deform", 0))
        custom: int = int(rig.get("custom_soft_tissue_bones", 0))
        warnings: int = len(rig.get("warnings", []))

        total_bones += bone_count
        total_unmapped_deform += unmapped
        total_custom += custom

        print(
            f"- {rig_name}: bones={bone_count}, custom={custom}, "
            f"unmapped_deform={unmapped}, warnings={warnings}"
        )

    print(
        f"- totals: bones={total_bones}, custom={total_custom}, "
        f"unmapped_deform={total_unmapped_deform}"
    )
    return total_bones, total_custom, total_unmapped_deform


def main() -> int:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Run one-click Blender rig upgrade pipeline"
    )
    parser.add_argument("--blend", required=True, help="Path to .blend file")
    parser.add_argument(
        "--blender-path",
        default=None,
        help="Path to Blender executable (or set BLENDER_PATH)",
    )
    parser.add_argument(
        "--save",
        action="store_true",
        help="Save the .blend after injecting custom bones",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero if unmapped deform bones remain",
    )
    parser.add_argument(
        "--copy-rig-dump-to",
        default=None,
        help="Optional destination path to copy generated rig-dump JSON",
    )
    parser.add_argument(
        "--armature",
        default=None,
        help="Optional armature name filter (for example: Player1)",
    )
    parser.add_argument(
        "--sex",
        choices=["auto", "male", "female"],
        default="auto",
        help="Sex profile for custom bone sets (default: auto)",
    )
    parser.add_argument(
        "--male-armatures",
        default="Player1",
        help="Comma-separated armature names treated as male when --sex auto",
    )
    args: argparse.Namespace = parser.parse_args()

    this_file: Path = Path(__file__).resolve()
    single_room_root: Path = this_file.parents[1]

    blend_path: Path = Path(args.blend).expanduser().resolve()
    if not blend_path.exists():
        raise FileNotFoundError(f"Blend file not found: {blend_path}")

    blender_path: Path = _resolve_blender_path(args.blender_path)

    add_script: Path = single_room_root / "tools" / "blender-add-soft-tissue-bones.py"
    dump_script: Path = single_room_root / "tools" / "blender-rig-dump.py"
    report_path: Path = single_room_root / "logs" / "blender-upgrade-report.json"

    for required_path in (add_script, dump_script):
        if not required_path.exists():
            raise FileNotFoundError(f"Required script not found: {required_path}")

    bootstrap_path: Path = _write_temp_bootstrap(single_room_root)

    print("Running Blender upgrade pipeline...")
    print(f"- blender: {blender_path}")
    print(f"- blend:   {blend_path}")
    print(f"- save:    {args.save}")
    if args.armature:
        print(f"- armature:{args.armature}")
    print(f"- sex:     {args.sex}")
    if args.sex == "auto":
        print(f"- male-armatures: {args.male_armatures}")

    exit_code: int = _run_blender_pipeline(
        blender_path=blender_path,
        blend_path=blend_path,
        add_script=add_script,
        dump_script=dump_script,
        bootstrap_path=bootstrap_path,
        report_path=report_path,
        save_blend=bool(args.save),
        armature_name=args.armature,
        sex_profile=str(args.sex),
        male_armatures=str(args.male_armatures),
        cwd=single_room_root,
    )

    if not report_path.exists():
        print("ERROR: Bootstrap report was not written.")
        return 1

    report_data: dict[str, Any] = _load_json(report_path)
    rig_dump_path: Path = Path(str(report_data.get("rig_dump_path", "")))

    print(f"- report:  {report_path}")
    print(f"- dump:    {rig_dump_path}")

    if exit_code != 0 or not bool(report_data.get("ok", False)):
        print("\nPipeline failed.")
        for step_name, step_data in report_data.get("steps", {}).items():
            if isinstance(step_data, dict) and not bool(step_data.get("ok", False)):
                print(f"- {step_name}: {step_data.get('error', 'unknown error')}")
        return 1

    if not rig_dump_path.exists():
        print("ERROR: Rig dump JSON not found after successful pipeline.")
        return 1

    dump_raw: Any = json.loads(rig_dump_path.read_text(encoding="utf-8"))
    if not isinstance(dump_raw, list):
        print("ERROR: Rig dump JSON has unexpected format.")
        return 1

    if args.armature:
        dump_raw = [
            rig for rig in dump_raw if str(rig.get("armature_name", "")) == str(args.armature)
        ]
        if not dump_raw:
            print(f"ERROR: Armature '{args.armature}' not found in rig dump output.")
            return 1

        rig_dump_path.write_text(json.dumps(dump_raw, indent=2), encoding="utf-8")
    elif not dump_raw:
        print("ERROR: No armatures found in rig dump output.")
        return 1

    _, _, unmapped_deform = _print_summary(dump_raw)

    if args.copy_rig_dump_to:
        copy_dest: Path = Path(args.copy_rig_dump_to).expanduser().resolve()
        copy_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(rig_dump_path, copy_dest)
        print(f"- copied rig dump to: {copy_dest}")

    if args.strict and unmapped_deform > 0:
        print("\nStrict mode: failing due to unmapped deform bones.")
        return 1

    print("\nPipeline complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
