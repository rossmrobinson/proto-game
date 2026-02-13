# Blender Upgrade Pipeline

One command to upgrade a MotionBuilder-based rig to the project custom bone layout.

## What it runs

1. `single-room/tools/blender-add-soft-tissue-bones.py`
2. Optional save of the `.blend`
3. `single-room/tools/blender-rig-dump.py`
4. Summary report + optional rig-dump copy

## Prereqs

- Blender executable available via:
  - `--blender-path`, or
  - `BLENDER_PATH` environment variable, or
  - `blender` available on `PATH`
- Valid `.blend` file path

## Command

From workspace root:

```powershell
.\.venv\Scripts\python.exe .\single-room\tools\blender-upgrade-pipeline.py --blend "J:\proto-game-blender\room1-models.blend" --blender-path "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --armature "Player1" --sex "male" --save --strict --copy-rig-dump-to ".\single-room\room1-models-rig-dump.json"
```

## Flags

- `--blend` (required): path to `.blend`
- `--blender-path`: Blender executable path
- `--save`: persist injected custom bones to `.blend`
- `--strict`: fail if `unmapped_deform > 0`
- `--copy-rig-dump-to`: copy generated rig dump JSON to a chosen path
- `--armature`: limit output to one armature name (for example `Player1`)
- `--sex`: choose `auto`, `male`, or `female` custom bone profile
- `--male-armatures`: comma-separated male armature names used when `--sex auto` (default: `Player1`)

## Outputs

- Report JSON: `single-room/logs/blender-upgrade-report.json`
- Rig dump JSON: next to the `.blend` as `<blend-name>-rig-dump.json`
- Optional copied rig dump: path from `--copy-rig-dump-to`
- With `--armature`, the rig dump JSON is filtered down to only that armature

## Sex profile behavior

- `--sex male`: keeps male-specific bones, removes female-specific bones from targeted armature(s)
- `--sex female`: keeps female-specific bones, removes male-specific bones from targeted armature(s)
- `--sex auto`: treats names from `--male-armatures` as male, all others as female
