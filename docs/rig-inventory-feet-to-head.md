# Rig Inventory — Feet to Head

Date: 2026-02-13

## Source Artifacts

- Blend file: `J:\proto-game-blender\room1-models.blend`
- Inventory dump: `single-room/room1-models-rig-dump.json`
- Game map source: `single-room/scripts/npc/ragdoll_proportions.gd`

## Alignment Status

| Check | Result |
|---|---|
| Armature | `Player1` |
| Actual deform bones in model | `156` |
| Bones mapped to Godot | `156/156` |
| Unmapped deform bones | `0` |
| Extra model bones not in map | `0` |
| Expected full map keys (stock + custom) | `274` |
| Missing from current model | `118` |
| Missing chunk type | **Custom soft-tissue/internal only** |

## Chunk Plan (Feet → Head)

| Chunk | Status | Missing |
|---|---|---|
| Feet + Legs (stock MotionBuilder) | ✅ Ready | `0` |
| Pelvis + Soft Tissue + Internal | ⚠ Build Next | `118` |
| Torso + Arms + Hands (stock MotionBuilder) | ✅ Ready | `0` |
| Head + Face + Tongue + Eyes (stock map) | ✅ Ready | `0` |

## Missing Bones Breakdown (118)

| Group | Count |
|---|---:|
| Glutes (`left/right_inner/outer_glute`) | 4 |
| Breasts (`inner/outer/upper/lower` + nipples) | 10 |
| Male genital chain (`penis_*`, `scrotum_*`) | 5 |
| Female genital chain (`labia_*`, `clitoris`) | 3 |
| Entrance rings (`vaginal_*`, `anal_*`, `oral_*`) | 12 |
| Passage depth bones (`vaginal 32`, `anal 32`, `oral 20`) | 84 |
| **Total** | **118** |

## Weighting Warnings in Current Stock Rig

`28` deform bones currently show `0 vertices` in the dump.

Highest-impact to check while rigging in chunks:
- `LeftHandThumb1`, `RightHandThumb1`
- `RightForeArmRoll`
- Face/expressive chain: `oris*`, `levator*`, `special*`, `temporalis*`, `oculi*`, `risorius*`
- `Head`

## Build Order for Blender Session

1. Add glutes + breasts first, verify deformation in pose mode.
2. Add genital chain(s), then verify parent links to `Hips`.
3. Add all entrance rings (`vaginal/anal/oral`) and test local orientation.
4. Add passage depth chains (`0→7`, oral `0→4`) with strict naming.
5. Re-run `blender-rig-dump.py` and verify:
   - `custom_soft_tissue_bones > 0`
   - `mapped_to_godot == bone_count`
   - no new unmapped deform bones

## Commands Used

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b "J:\proto-game-blender\room1-models.blend" --python "J:\proto-game\single-room\tools\blender-rig-dump.py"
```
