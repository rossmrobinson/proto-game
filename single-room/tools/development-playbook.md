# Proto-Game Development Playbook

> Reference doc for all future Copilot sessions. Read this before making changes.

---

## 1. Current State Summary

### What Works
| System | Status | Notes |
|--------|--------|-------|
| Room | OK | 4.88m greybox, floor/walls/ceiling, lit |
| Player movement | BROKEN | WASD mapped, code looks correct, but no movement at runtime |
| Player camera | BROKEN | FPS: grey screen (camera inside model head). TPS: behind player, only tilts |
| Camera toggle (V) | PARTIAL | Switches cameras, but both cameras broken |
| NPC models (Ada, Vero) | OK | Loaded from shared .blend, 53 bones bound |
| Active ragdoll | OK | PD-controller springs, skeleton writeback |
| Grab interaction | UNTESTED | Springs weaken on grab, but grab system untested with active ragdoll |
| Player model (Player1) | LOADED | .glb exported, meshes on layer 2, rotation PI applied |
| Diagnostics (F3) | OK | FPS/VRAM/draw calls overlay |
| NPC brain/memory/voice | CODED | 504 TTS lines generated, brain subsystems wired |
| Collision layers | OK | 7 named layers in project.godot |

### Known Bugs (Fix Before Adding Features)
1. **Player can't move** — WASD does nothing at runtime
2. **FPS camera grey** — camera at Y=1.82 sits inside Player1 head mesh
3. **TPS camera only tilts** — no yaw rotation visible; model faces away
4. **Player model on layer 2 but FPS still grey** — `_set_mesh_layers()` may not be reaching all MeshInstance3D children (check imported scene tree depth)

---

## 2. Scene Tree Architecture

```
Main (Node3D)
├── WorldEnvironment
├── GreyboxRoom (instance)
├── Player (CharacterBody3D) ← player_controller.gd
│   ├── CollisionShape3D (capsule 2.0m, center Y=1.0)
│   ├── BodyMesh (blue capsule, layers=3, center Y=1.0)
│   ├── HeadPivot (Node3D, Y=1.82)
│   │   ├── CameraFPS (cull_mask excludes layer 2, fov=75, near=0.05)
│   │   ├── SpringArm3D (Y+0.3, length=3.0)
│   │   │   └── CameraTPS (X+0.5 offset, fov=70)
│   │   └── InteractionRay
│   ├── PlayerModel (loaded at runtime from .glb) ← PROBLEM AREA
│   ├── TargetingSystem
│   ├── HandInteractionSystem
│   ├── PlayerPosture
│   ├── AutopilotSystem
│   ├── PlayerSelfTouch
│   └── NPCCommandSystem
├── NPCPlaceholder "Ada" (Node3D)
│   ├── HumanoidRagdoll (builder, ~66 BodyPart RigidBodies)
│   ├── [Armature from .blend] (reparented, has Skeleton3D + meshes)
│   ├── SkeletonBinding (active ragdoll springs)
│   ├── CharacterProfile, NerveSystem, BodyLanguage, NPCBehavior
│   ├── NPCMemory, NPCAttention, NPCVoicePlayer
│   └── NPCBrain
├── NPCPlaceholder "Vero" (same structure)
└── GrabbableCrate1 (RigidBody3D)
```

---

## 3. Root Causes of Current Bugs

### Bug: Player Can't Move
**Likely cause:** `move_and_slide()` returns true (collision occurred). Player CharacterBody3D `collision_mask = 13` (layers 1, 3, 4). The Player1 model's imported collision shapes or static bodies (if any exist inside the .glb) may be colliding with the capsule.

**Fix strategy:**
1. Check if player1.glb contains any CollisionShape3D or StaticBody3D nodes
2. Strip them on load, or set collision layers to 0
3. Also verify Input actions are registering (add debug print in `_handle_movement`)

### Bug: FPS Grey Screen
**Root cause:** CameraFPS at Y=1.82 is inside the Player1 head mesh. Even though `_set_mesh_layers(model, 2)` is called AND CameraFPS cull_mask excludes layer 2, the grey may be caused by:
- Meshes nested inside sub-scenes that `_set_mesh_layers()` doesn't reach
- The model's root node having a mesh

**Fix strategy:**
1. After loading model, print count of meshes found and their layer values
2. Ensure recursive walk covers ALL descendants (not just direct children)
3. Alternatively: don't rotate the whole model by PI, instead keep it hidden in FPS entirely

### Bug: TPS Only Tilts
**Root cause:** Camera yaw comes from `rotate_y()` on the CharacterBody3D root. If something resets the root's rotation (like the model loading), yaw breaks.

**Fix strategy:**
1. Verify `rotate_y()` is being called (add debug print)
2. Check that no child node's transform is overriding the root
3. Ensure `_unhandled_input` receives mouse events (check `Input.mouse_mode`)

---

## 4. Correct Player Model Integration Pattern

### What the Blender Export Script Should Produce
- Origin at feet (Y=0 at ground plane)
- Facing -Y in Blender (which becomes -Z in Godot via glTF +Y-up export)
- No animations, no physics shapes, no empties
- Single armature + mesh children only
- Applied transforms (loc/rot/scale all identity)

### What the Godot Loader Should Do
```
1. Instantiate .glb PackedScene
2. Recursively remove any CollisionShape3D/StaticBody3D/RigidBody3D
3. Recursively set all MeshInstance3D.layers = layer 2 bitmask
4. Stop all AnimationPlayers
5. Add as child of CharacterBody3D
6. Position at (0, 0, 0) relative to parent — feet at capsule bottom
7. NO rotation needed if Blender export is correct
```

### Visual Layer Strategy
| Layer | What | CameraFPS sees | CameraTPS sees |
|-------|------|----------------|----------------|
| 1 | Environment, NPCs | Yes | Yes |
| 2 | Player body mesh | **No** (culled) | Yes |
| 3 | BodyMesh placeholder | Yes (if visible) | Yes |

CameraFPS `cull_mask = 1048573` = all layers except layer 2.
CameraTPS `cull_mask` = default (all layers).

---

## 5. Active Ragdoll Architecture

### How It Works
- Every NPC `BodyPart` (RigidBody3D) is **always dynamic, never frozen**
- `SkeletonBinding` applies PD-controller spring forces every `_physics_process`:
  - **Position spring:** pulls part toward skeleton bone position
  - **Rotation spring:** twists part toward skeleton bone orientation
  - **Damping:** prevents oscillation
- After forces, skeleton is **written back from physics** so skinned mesh follows ragdoll
- When a part is grabbed, spring strength drops to 5% → part yields to player

### Tuning Values
| Parameter | Value | Effect |
|-----------|-------|--------|
| `spring_stiffness` | 400 | N/m — position hold strength |
| `spring_damping` | 40 | Prevents bouncing |
| `angular_stiffness` | 80 | N·m/rad — rotation hold |
| `angular_damping` | 12 | Prevents spin oscillation |
| `grabbed_spring_ratio` | 0.05 | 5% strength when grabbed |

### Why Not PhysicalBoneSimulator3D?
Godot's built-in `PhysicalBoneSimulator3D` + `PhysicalBone3D` system is simpler but:
- Doesn't support per-bone grab with spring weakening
- Doesn't allow custom spring tuning per body part
- Our system gives 66+ independently interactive body parts
- Built-in system is designed for "toggle ragdoll on death" — not always-on active ragdoll

**Decision: Keep custom active ragdoll.** Re-evaluate only if Jolt physics performance becomes an issue.

---

## 6. File Inventory (41 GDScript files)

### Player (6 files)
| File | Purpose |
|------|---------|
| `player_controller.gd` | FPS/TPS movement, camera, model loading |
| `hand_interaction_system.gd` | Dual-hand mouse grab/push/pelvis controls |
| `targeting_system.gd` | Crosshair, detached cursor, target cycling |
| `player_posture.gd` | Standing/crouching/prone, speed modifier |
| `autopilot_system.gd` | Auto-movement toward NPC targets |
| `player_self_touch.gd` | Player self-touch zone interaction |

### NPC (12 files)
| File | Purpose |
|------|---------|
| `npc_placeholder.gd` | NPC spawner, model loader, subsystem wirer |
| `humanoid_ragdoll_builder.gd` | Procedural 66-part ragdoll construction |
| `body_part.gd` | Single physics segment, grab/release/impact |
| `skeleton_binding.gd` | Active ragdoll PD springs + skeleton writeback |
| `nerve_system.gd` | Touch/pain/pleasure nerve processing |
| `nerve_sensitivity.gd` | Per-zone sensitivity data |
| `character_profile.gd` | Name, personality, preferences |
| `body_language_system.gd` | Posture and gesture state |
| `npc_behavior.gd` | Behavior tree / state machine |
| `npc_brain.gd` | Central coordinator for memory/attention/voice |
| `npc_memory.gd` | Event memory storage |
| `npc_attention.gd` | Focus/awareness tracking |

### Systems (11 files)
| File | Purpose |
|------|---------|
| `grab_system.gd` | Legacy grab (superseded by hand_interaction) |
| `grabbable.gd` | Generic grabbable object (crate, etc.) |
| `diagnostics_overlay.gd` | F3 debug overlay |
| `npc_command_system.gd` | Voice command dispatch to NPCs |
| `sfx_engine.gd` | Sound effects engine |
| `body_fluid_emitter.gd` | Fluid particle system |
| `body_fluid_library.gd` | Fluid type definitions |
| `fluid_type.gd` | Fluid data resource |
| `piercing_attachment.gd` | Piercing physics attachment |
| `piercing_library.gd` | Piercing type catalog |
| `piercing_type.gd` | Piercing data resource |
| `equippable_phallus.gd` | Equippable anatomy item |

### Animation (5 pose libraries)
| File | Poses |
|------|-------|
| `yoga_poses.gd` | Yoga pose definitions |
| `martial_arts_poses.gd` | Combat poses |
| `kama_sutra_poses.gd` | Position definitions |
| `gymnastics_poses.gd` | Athletic poses |
| `dance_poses.gd` | Dance poses |
| `ragdoll_pose.gd` | Pose data structure |
| `ragdoll_animator.gd` | Pose interpolation system |

### UI (3 files)
| File | Purpose |
|------|---------|
| `hud.gd` | Main HUD |
| `command_indicator.gd` | Command mode UI |
| `character_editor_panel.gd` | F4 character editor |

---

## 7. Physics Layer Map

| Layer | Name | Used By |
|-------|------|---------|
| 1 | Environment | Floor, walls, ceiling |
| 2 | Player | CharacterBody3D capsule |
| 3 | NPC_External | BodyPart RigidBodies (external) |
| 4 | Interactable | Grabbable items + BodyParts |
| 5 | NPC_SoftTissue | Breasts, genitals, glutes |
| 6 | NPC_Internal | Anal/vaginal passage segments |
| 7 | Equipment | Equippable items |

---

## 8. Immediate Fix Priority Queue

Do these in order. Each one should be a single commit.

### Fix 1: Debug Movement
- Add `print()` in `_handle_movement` to verify input is reading
- Add `print()` in `_physics_process` to verify velocity
- Check if player is colliding with something at spawn

### Fix 2: Strip Physics from Player Model
- After instantiating player1.glb, recursively remove any CollisionShape3D, StaticBody3D, RigidBody3D nodes
- This prevents the model's imported collision from blocking the CharacterBody3D

### Fix 3: Verify Mesh Layer Assignment
- After `_set_mesh_layers()`, print how many meshes were set to layer 2
- Verify CameraFPS cull_mask is correct at runtime

### Fix 4: Fix Camera Yaw
- Add debug print for `rotate_y()` calls
- Verify mouse mode is CAPTURED at start
- Check that HeadPivot rotation isn't leaking to the body

### Fix 5: Remove Debug Prints
- Clean up all temporary prints once issues are resolved

---

## 9. Future Feature Roadmap

### Phase 1: Core Stability (NOW)
- [ ] Fix player movement
- [ ] Fix FPS/TPS camera
- [ ] Verify grab interaction with active ragdoll
- [ ] Test all input actions work

### Phase 2: Player Body Visibility
- [ ] FPS: see own body when looking down (headless body on layer visible to FPS cam)
- [ ] FPS arms with IK for grab reach visualization
- [ ] Body sway/head bob during movement

### Phase 3: NPC Interaction Polish
- [ ] Pose system integration (yoga, kama sutra, etc.)
- [ ] Nerve system response to touch (pleasure/pain/discomfort)
- [ ] Voice reactions (504 TTS lines wired to brain states)
- [ ] Body language reactions to player proximity

### Phase 4: LLM Backend
- [ ] Google Colab FastAPI server
- [ ] Ngrok tunnel for local connection
- [ ] Brain → LLM prompt pipeline
- [ ] Memory-aware dialogue

### Phase 5: Visual Polish
- [ ] SDFGI lighting
- [ ] PBR materials on room
- [ ] Character skin shaders (SSS)
- [ ] Volumetric fog

---

## 10. Blender Pipeline Rules

### Model Export Checklist
1. Origin at feet (Y=0 at ground plane in Blender)
2. Facing -Y in Blender (becomes -Z in Godot)
3. Scale applied (1,1,1)
4. All transforms applied (`Ctrl+A → All Transforms`)
5. No animations / NLA strips
6. No physics shapes
7. Export as `.glb` (binary glTF)
8. `export_yup = True` (Godot convention)
9. `export_apply = True` (bake modifiers)
10. Test: import in Godot, verify model faces forward (-Z)

### Shared .blend Import (for NPCs)
- Godot imports entire .blend file as one PackedScene
- Each armature is a top-level child
- `npc_placeholder.gd` extracts the named armature, reparents it
- Preserves Y offset (Blender ground-to-origin height)

### Standalone .glb Import (for Player)
- Single model per file
- `player_controller.gd` loads via `player_model_path` export
- No extraction needed — entire scene is the model

---

## 11. Debugging Checklist

When something doesn't work, check in this order:

1. **Godot Output panel** — look for push_error/push_warning messages
2. **Debugger → Errors tab** — runtime errors and stack traces
3. **Physics layers** — is the object on the right layer? Is the mask correct?
4. **Visual layers** — is the mesh on the right render layer? Does the camera see it?
5. **Input map** — is the action defined in project.godot? Correct key code?
6. **Node paths** — do `@onready` references resolve? (null = scene structure mismatch)
7. **Signal connections** — is the signal connected? Is the handler receiving?
8. **Transform hierarchy** — is a parent's rotation/scale affecting children unexpectedly?
