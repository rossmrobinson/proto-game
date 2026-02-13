# MakeHuman → Blender → Godot Rigging Pipeline

How to bring a new character from MakeHuman into the game with full physics rigging.

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| MakeHuman | 1.2.0+ | With MPFB2 Blender add-on |
| Blender | 4.x | MPFB2 installed |
| Godot | 4.6 | Jolt Physics enabled |

---

## Step 1 — Create Base Model in MakeHuman

1. Design body in MakeHuman (proportions, gender, etc.)
2. **Rig selection:** Choose **"MotionBuilder Full"** (or "Game Engine") — the rig that gives PascalCase bone names (Hips, Spine, Spine1, Spine2, Spine3, LeftArm, etc.)
3. Export as `.mhx2` **or** use MPFB2 to import directly into Blender

> **Why MotionBuilder Full?** The entire ragdoll builder's `BONE_NAME_MAP` is keyed to this rig. Using a different rig means remapping ~160 bone names.

---

## Step 2 — Import into Blender

### Option A: MPFB2 (preferred)
1. In Blender: `MPFB2 → Import Human`
2. Select your `.mhm` preset or configure in-panel
3. MPFB2 creates an Armature with the correct bone hierarchy

### Option B: MHX2
1. `File → Import → MakeHuman (.mhx2)`
2. Ensure "MotionBuilder Full" rig was selected in MakeHuman

---

## Step 3 — Run `blender-add-soft-tissue-bones.py`

This script adds all custom physics bones the ragdoll needs:

```
Blender → Scripting tab → Open → single-room/tools/blender-add-soft-tissue-bones.py → Run
```

### What it adds (~120 bones):

| Group | Count | Examples |
|---|---|---|
| Glutes | 4 | left/right_inner_glute, left/right_outer_glute |
| Breasts | 12 | 4 quadrants (inner/outer/upper/lower) + nipple per side |
| Male genitals | 5 | penis_base/mid/tip, scrotum_left/right |
| Female genitals | 3 | labia_left/right, clitoris |
| Vaginal passage | 36 | 4 entrance ring + 8×4 depth quadrants |
| Anal passage | 36 | 4 entrance ring + 8×4 depth quadrants |
| Oral passage | 24 | 4 entrance ring + 5×4 depth quadrants |

**Total custom bones:** ~120 (on top of ~156 stock MotionBuilder bones)

The script also creates **stub vertex groups** on every mesh parented to the armature, so you can start weight-painting immediately.

---

## Step 4 — Weight-Paint the Custom Bones

This is the manual step that makes each character unique.

### Priority order (most visible impact first):

1. **Breasts** — inner/outer/upper/lower quadrants + nipple
2. **Glutes** — inner/outer per side
3. **Genitals** — penis segments or labia/clitoris
4. **Passage openings** — entrance ring bones (vaginal, anal, oral)
5. **Deep passage segments** — depths 0-7 (minimal visible deformation, mostly physics)

### Weight-painting tips:

- Each custom bone's vertex group should have **smooth falloff** weights (not binary 0/1)
- Breast quadrants should **overlap slightly** at boundaries for smooth deformation
- Passage bones: assign **very thin rings of vertices** around the tunnel interior
- Use Blender's "Transfer Weights" from a template character to speed up new models
- The `blender-rig-dump.py` script can verify all expected bones exist and have weights

---

## Step 5 — Verify with `blender-rig-dump.py`

```
Blender → Scripting tab → Open → single-room/tools/blender-rig-dump.py → Run
```

This outputs a JSON report listing:
- All bones found vs. expected (highlights missing ones)
- Vertex group coverage per bone
- Bone hierarchy validation

Fix any warnings before exporting.

---

## Step 6 — Export to Godot

### Option A: Direct `.blend` import (preferred)
- Save the `.blend` file into `single-room/assets/models/`
- Godot 4 imports `.blend` files directly via its Blender bridge
- Ensure Blender is configured in Godot's Editor Settings → Filesystem → Blender

### Option B: `.glb` export
- `File → Export → glTF 2.0 (.glb)`
- Settings: **Include → Armatures, Meshes** checked
- **Transform → +Y Up** (Godot convention)
- Save into `single-room/assets/models/`

---

## Step 7 — Wire Up in Godot

The `npc_placeholder.gd` script handles instantiation:

1. Set the mesh/skeleton resource on the NPC node
2. `HumanoidRagdollBuilder` auto-discovers bones via `BONE_NAME_MAP`
3. `SkeletonBinding` PD controller drives mesh bones to follow physics bodies
4. `NerveSystem`, `ArousalSystem`, `PassageResponse`, `ShapeKeyDriver` all wire up in `_on_ragdoll_built()`

---

## Reusing the Rig Across Models

### Template approach (recommended):

1. Fully weight-paint ONE reference model per body type (male/female/androgynous)
2. Save as a `.blend` template
3. For new characters:
   - Create new body in MakeHuman with same rig
   - Import into Blender
   - Use **Transfer Weights** (`Object Data Properties → Vertex Groups → Transfer Weights`) from the template to the new mesh
   - Adjust weights for body-specific differences (bigger breasts need wider quadrant weights, etc.)

### MakeHuman custom rig option:

MakeHuman supports adding custom rigs via its **Skeleton tab**:
- You can create a `.json` rig definition referencing the MotionBuilder Full skeleton plus extra bones
- However, this is fragile and version-dependent
- **Recommended:** Keep MakeHuman stock rig, add custom bones in Blender post-import

This keeps the pipeline clean: MakeHuman does body shape, Blender does rigging extensions, Godot does physics.

---

## Shape Keys Needed in Blender

The `ShapeKeyDriver` in Godot looks for these blend shapes on the body mesh:

| Shape Key | Driven By | Notes |
|---|---|---|
| `penis_erect_len` | ArousalSystem | Length increase during erection |
| `penis_erect_girth` | ArousalSystem | Girth increase |
| `penis_erect_pose` | ArousalSystem | Upward curve when erect |
| `penis_pulse` | ArousalSystem | Throb deformation |
| `penis_veins` | ArousalSystem | Vein visibility at high erection |
| `scrotum_tension` | ArousalSystem | Tightening at arousal |
| `scrotum_relax` | ArousalSystem | Relaxed/hanging state |
| `tunnel_min` | PassageResponse | Passage contracted tight |
| `tunnel_max` | PassageResponse | Passage dilated open |
| `tunnel_pulse` | PassageResponse | Rhythmic contraction |
| `left_nipple_erect` | ArousalSystem | Nipple hardening |
| `right_nipple_erect` | ArousalSystem | Nipple hardening |

Create these as **Shape Keys** on the body mesh in Blender. They don't need to be extreme — subtle deformation driven by the physics system creates realistic results.

---

## Physics Layer Reference

| Layer | Name | What's on it |
|---|---|---|
| 1 | Environment | Floors, walls, furniture |
| 2 | Player | Player character body |
| 3 | NPC_External | Skeletal ragdoll parts (torso, limbs) |
| 4 | Interactable | Anything grabbable/targetable |
| 5 | NPC_SoftTissue | Breasts, glutes, genitals |
| 6 | NPC_Internal | Passage walls (vaginal, anal, oral) |
| 7 | Equipment | Piercings, toys, clothing |
| 8 | NPC_FineMotor | Finger segments + tongue (can reach passages) |

---

## Checklist for a New Character

- [ ] MakeHuman model with MotionBuilder Full rig
- [ ] Imported into Blender (MPFB2 or MHX2)
- [ ] `blender-add-soft-tissue-bones.py` run successfully
- [ ] Weight-painted: breasts, glutes, genitals, passage openings
- [ ] Shape keys created (at minimum: nipple_erect, tunnel_min/max)
- [ ] `blender-rig-dump.py` passes with no warnings
- [ ] Exported to Godot (`.blend` or `.glb`)
- [ ] Spawns in-game with ragdoll physics working
- [ ] Passage penetration tested (fingers, penis)
- [ ] Nerve sensitivity feels right (adjust in `nerve_sensitivity.gd` if needed)
