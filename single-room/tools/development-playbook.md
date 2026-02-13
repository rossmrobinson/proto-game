# Proto-Game Development Playbook

> Reference doc for all future Copilot sessions. Read this before making changes.

---

## 0. Copilot Rules (Opus)

### Ross Accessibility
- Keep responses short and scannable (tables, bullets). Avoid paragraphs.
- Do the work first. Explain only if asked.

### Safety + Version Discipline
- Do not cite engine or tool versions without verifying in-project.
- Do not add hardcoded ports, URLs, or magic numbers outside centralized config.

### Editing Discipline
- No spaces in file/folder names. Follow naming table in section 7.
- Use GDScript 4.6 syntax, strict typing everywhere.
- Run relevant scanners after edits and fix all warnings.
- Long tasks run in background terminals.

### LLM Diagnostics
- The in-editor LLM chat is named "Glyph" (Godot GPT Codex).

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
| Fluid system | CODED | Accumulator, surface decals, strings, emitters, orgasm-intensity scaling |
| Grab interaction | UNTESTED | Springs weaken on grab, but grab system untested with active ragdoll |
| Player model (Player1) | LOADED | .glb exported, meshes on layer 2, rotation PI applied |
| Diagnostics (F3) | OK | FPS/VRAM/draw calls overlay |
| NPC brain/memory/voice | CODED | 504 TTS lines generated, brain subsystems wired |
| Collision layers | OK | 8 named layers in project.godot |

### Known Bugs (Fix Before Adding Features)
1. **Player can't move** — WASD does nothing at runtime
2. **FPS camera grey** — camera at Y=1.82 sits inside Player1 head mesh
3. **TPS camera only tilts** — no yaw rotation visible; model faces away
4. **Player model on layer 2 but FPS still grey** — `_set_mesh_layers()` may not be reaching all MeshInstance3D children (check imported scene tree depth)

### Recent Fixes (Do Not Regress)
1. **Ragdoll spawn stability** — freeze parts, align to bones for 3 frames, ramp springs over 0.4s, raise NPC root to Y=0.15
2. **Self-collision explosion** — all same-NPC body parts mutually excluded from collisions

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
- Every NPC `BodyPart` (RigidBody3D) is dynamic after spawn (frozen only during initial settle)
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

### Ragdoll Spawn Stability Playbook (MANDATORY)
1. **Build parts, then freeze**: set `FREEZE_MODE_KINEMATIC` on all parts after creation.
2. **Align to bones for 3 frames**: snap each part to its target bone pose while frozen.
3. **Unfreeze after settle**: unfreeze on frame 3; keep springs off during freeze.
4. **Ramp springs**: scale stiffness from 0 to full over 0.4s.
5. **Spawn above floor**: NPC root Y >= 0.15 to clear floor surface.
6. **Delay inter-NPC collisions**: mask out other NPC layers for 0.2s, then restore.

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

### Systems (15 files)
| File | Purpose |
|------|---------|
| `grab_system.gd` | Legacy grab (superseded by hand_interaction) |
| `grabbable.gd` | Generic grabbable object (crate, etc.) |
| `diagnostics_overlay.gd` | F3 debug overlay |
| `npc_command_system.gd` | Voice command dispatch to NPCs |
| `sfx_engine.gd` | Sound effects engine |
| `fluid_system.gd` | Top-level fluid coordinator per NPC |
| `fluid_accumulator.gd` | Per-passage fluid retention, deposit/expel/leak |
| `fluid_surface.gd` | Decal3D patches on external body surfaces |
| `fluid_string.gd` | ImmediateMesh viscous threads between surfaces |
| `body_fluid_emitter.gd` | GPU particle emitter configured from FluidType |
| `body_fluid_library.gd` | 17+ fluid preset factory |
| `fluid_type.gd` | Fluid data resource (30+ properties) |
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
| 8 | NPC_FineMotor | Fingers, toes, fine motor parts |

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
4. Base pose is A-pose (arms 30-45 degrees down, palms forward)
5. All transforms applied (`Ctrl+A → All Transforms`)
6. No animations / NLA strips
7. No physics shapes
8. Export as `.glb` (binary glTF)
9. `export_yup = True` (Godot convention)
10. `export_apply = True` (bake modifiers)
11. Test: import in Godot, verify model faces forward (-Z)

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

---

## 12. Player Collision + Posture Pitfalls

### Capsule Resize Sink Bug
Symptom: `is_on_floor()` true but player slowly sinks.

Root cause: `PlayerPosture` lerps capsule height toward stale defaults for a few frames before `_ready()` sets targets.

Fix: initialize `_target_height` and `_target_camera_y` before first physics tick or guard `_physics_process` until initialized.

### Dynamic Capsule Resize Rules
1. Keep capsule bottom at constant world Y when changing height.
2. Apply resize before `move_and_slide()` each frame.
3. Avoid oscillating lerps; snap when within epsilon.
4. Use `floor_snap_length` when shrinking to prevent micro-penetration.

---

## 13. Ragdoll Debug Checklist

### Fast Triage (Run in Order)
1. **Spawn Y**: NPC root Y >= 0.15 and no body part intersects floor at frame 0.
2. **Freeze settle**: parts frozen for 3 physics frames while snapped to bone pose.
3. **Spring ramp**: stiffness ramps 0 -> full over 0.4s.
4. **Self-collision**: verify all 66 parts mutually excluded.
5. **Inter-NPC collisions**: temporarily disable other NPC layers for first 0.2s.

### Telemetry to Capture (Print or Debug Overlay)
- Part count, joint count, and exceptions count
- Max penetration depth at spawn
- Max bone offset at snap, unfreeze, and first 10 frames
- Max linear and angular velocity in first 10 frames
- Any part with `sleeping = false` while frozen (should not happen)

### Expected Healthy Signals
- Max bone offset <= 0.02m at unfreeze
- Max linear velocity < 2.0 m/s in first 10 frames
- No spikes in angular velocity > 10 rad/s
- No part below floor plane at unfreeze

### Common Root Causes
1. **Spawn overlap**: any part starts below floor or inside other NPC.
2. **Mismatched bone pose**: alignment uses wrong bone or wrong transform space.
3. **Joint anchor mismatch**: joint frames set before parts are placed.
4. **Spring too stiff early**: ramp not applied or ramp duration too short.
5. **Layer/mask reset**: `body_part._ready()` overwrites settings post-build.

### Fix Ladder
1. Raise spawn Y and re-snap for 3 frames.
2. Confirm alignment uses bone global pose, not local.
3. Rebuild joints after snap (or re-set joint frames after snap).
4. Increase ramp to 0.6s and clamp max force.
5. Remove any per-part `_ready()` collision changes; keep it in builder.

---

## 14. Ragdoll Debug Controls

| Key | Action |
|-----|--------|
| F3 | Toggle diagnostics overlay |
| F5 | Toggle ragdoll debug on/off |
| F6 | Toggle ragdoll overlay text |
| F7 | Toggle ragdoll debug meshes |
| F8 | Toggle per-part labels |
| F9 | Toggle bone-to-part offset lines |
| F10 | Toggle joint axes |
| F11 | Toggle telemetry logging |

---

## 15. Ragdoll Test Scenes

| Scene | Purpose |
|------|---------|
| `res://scenes/ragdoll_spawn_test.tscn` | Single NPC spawn stability |
| `res://scenes/ragdoll_dual_test.tscn` | Two NPCs + inter-collision test |

Each scene includes `RagdollScenarioRunner` which writes a JSON report to `J:/proto-game/single-room/logs/` after 5 seconds.

---

## 16. Scanner Suite

Run all scanners from VS Code:
1. Task: **Scanners: Run All**
2. Optional: **Scanners: Godot Check** (requires `GODOT_PATH` env var)

Scripts live in `tools/scanners/`:
- `hardcoded-values-scan.py`
- `layer-mask-audit.py`
- `unused-resource-scan.py`
- `todo-tracker.py`
- `complexity-scan.py`
- `scene-validator.py`
- `run-all.ps1`
- `godot-check.ps1`

---

## 17. Cache Management

### Cache Levels
| Level | What It Clears | Use When |
|------|-----------------|----------|
| L1 | `J:/proto-game/single-room/logs/` | Daily cleanup, noisy diagnostics |
| L2 | `.godot/` | Import weirdness, stale editor state |
| L3 | `.godot/` + full `user://` | Persistent regressions |
| L4 | L3 + global Godot cache (env var) | Suspected global cache corruption |

### VS Code Tasks
| Task | Action |
|------|--------|
| `Cache: Print Paths` | Show resolved cache paths |
| `Cache: Clear Logs` | L1 |
| `Cache: Clear Project Cache` | L2 |
| `Cache: Clear User Data` | user:// full wipe |
| `Cache: Clear All` | L3 (and L4 if configured) |
| `Cache: Clear All (Global)` | L3 + global cache |
| `Cache: Status` | Show cache sizes |
| `Cache: Prune Logs (7d)` | Delete old logs |
| `Cache: Clear Global Only` | Global Godot cache only |
| `Cache: Clear GPU Shader` | GPU shader cache (env var) |
| `Cache: Clear Nuclear` | L4 + GPU shader |

### Env Vars (Optional)
| Var | Purpose |
|-----|---------|
| `GODOT_USERDATA_DIR` | Override user data path |
| `GODOT_GLOBAL_CACHE_DIR` | Enable global cache clearing |
| `GPU_SHADER_CACHE_DIR` | Enable GPU shader cache clearing |

### Godot Path Print
Run `res://tools/cache/print_cache_paths.gd` via the editor Script Run button
to print the true cache paths from Godot.

---

## 18. LLM Diagnostics (Local Proxy + Godot Plugin)

### Required Env Vars (local only)
| Var | Purpose |
|-----|---------|
| `OPENAI_API_KEY` | API key for proxy (never commit) |
| `OPENAI_MODEL` | Model name (default: gpt-5.2-codex) |
| `LLM_PROXY_PORT` | Proxy port (default: 8787) |

### Start Proxy
VS Code task: **LLM Proxy: Start**

### Enable Plugin
Godot: Project Settings -> Plugins -> Enable **LLM Diagnostics**

### Use
- Dock panel: set endpoint, click **Analyze**
- Auto-analyze: toggles when `godot_check.log` changes and contains ERROR

### Data Sent
- Tail of `res://godot_check.log`
- Latest `J:/proto-game/single-room/logs/*.jsonl` tail

---

## 19. Fluid System Architecture

### Overview
Each NPC owns one `FluidSystem` node that coordinates four subsystems:
- **FluidAccumulator** — per-passage volume tracking (oral, vaginal, anal)
- **BodyFluidEmitter pool** — GPU particle emitters for streams/drips/bursts
- **FluidSurface** — Decal3D patches on external body (face, chest, thighs)
- **FluidString pool** — ImmediateMesh viscous threads (saliva, semen strands)

### Signal Flow
```
ArousalSystem.orgasm_started(intensity)
  └─► FluidSystem._on_orgasm_started(intensity)
        ├─ Has penis? → _begin_ejaculation(target, intensity)
        │    ├─ target == "" → _emit_external_ejaculation(volume)
        │    └─ target != "" → emit internal_ejaculation signal
        │         └─► Orchestrator routes to receiving NPC's deposit_into_passage()
        └─ Has vagina? → accumulator.deposit("vaginal", vaginal_fluid, surge)

FluidAccumulator.fluid_leaking(passage, fluid, rate)
  └─► FluidSystem._on_fluid_leaking() → start leak emitter

FluidAccumulator.passage_emptied(passage)
  └─► FluidSystem._on_passage_emptied() → stop leak emitter

FluidAccumulator.fluid_expelled(passage, fluid, vol, dir)
  └─► FluidSystem._on_fluid_expelled() → burst emitter

ThirdPartyInsertion.insertion_started / insertion_ended
  └─► FluidSystem → accumulator.set_penetrated()
```

### Orgasm Intensity Formula
```
intensity = 1.0
  + sustained_bonus (0→0.6 over 30s of high arousal)
  + participant_bonus (0.15 per extra participant)
  ± random (±0.25)
  clamped ≥ 0.3
```
Scales ejaculation volume, duration, and spurt count.

### Leaking Rules
| Trigger | Rate | Condition |
|---------|------|----------|
| Penetration | `penetration_leak_rate × excess_fraction` | Volume > threshold × capacity |
| Gravity | `gravity_leak_rate × down_dot` | Passage opening faces downward |
| Overflow | `excess × 10.0` (instant burst rate) | Deposit pushes past max capacity |
| Evaporation | Passage cleared | Volume < `evaporation_threshold` |

Penetration and gravity leaks combine into a single signal per frame to prevent double-counting.

### Cooldown Bypass
When `cooldown_bypass = true`:
- Refractory period = 1s (instead of 15s)
- Arousal decay = 8× normal during refractory
- 20% arousal gain still allowed during refractory
- Enables rapid back-to-back orgasms for gameplay

### Fluid Type Resource
`FluidType` has 30+ properties across groups: Appearance, Physics, String Forming, Mixing.
`BodyFluidLibrary` provides 17+ named presets (saliva, semen, tears, sweat, blood, etc.).

---

## 20. Cross-NPC Fluid Wiring

All four original stubs are now implemented with automatic detection:

| Feature | How It Works |
|---------|-------------|
| Insertion target | `register_external_insertion_system()` auto-detects penis entering a passage via `ThirdPartyInsertion` signals |
| Participant count | Automatically tracked when insertion starts/ends; updates `ArousalSystem.set_participant_count()` |
| Internal ejaculation | `internal_ejaculation` signal auto-routes to receiving NPC's `deposit_into_passage()` |
| Sweat | Surface patches on torso/head/arms when arousal > `sweat_arousal_threshold` |
| Tears | Eye emitters when `CharacterProfile.discomfort_level` > `tear_discomfort_threshold` |

### How to Wire Two NPCs

```gdscript
# In the orchestrator or scenario setup:
# npc_a has a penis, npc_b has passages with a ThirdPartyInsertion system.
npc_a.fluid_system.register_external_insertion_system(
    npc_b.get_node("ThirdPartyInsertion") as ThirdPartyInsertion,
    npc_b.fluid_system)
# That's it — insertion target, ejaculation routing, and participant
# counting are all handled automatically from this single call.
```

### Manual Override (still available)
```gdscript
# If you need to override the automatic behavior:
npc_a.fluid_system.set_insertion_target("vaginal")
npc_a.arousal_system.set_participant_count(3)
```

---

## 21. NPC Mood / Mode System

NPCs have a single active **mood** that governs animation style, body language,
facial expression, and behavioral decision-making.

| Priority | Mood | Behavior |
|----------|------|----------|
| 0 (highest) | **In Shock** | Extreme fear, paralysis — no voluntary movement |
| 1 | **Afraid** | Physical avoidance — backs away, flinches, protective posture |
| 2 | **Sad** | Lethargic and/or emotional — slow movement, slumped posture |
| 3 | **Enraged** | Physical aggression — attacks, throws objects |
| 4 | **Angry** | Physical resistance — pushes away, stiffens body |
| 5 | **Annoyed** | Body language + facial cues only — eye rolls, sighs, crossed arms |
| 6 | **Neutral** | Default idle state |
| 7 | **Happy** | Positive body language + facial cues — smiles, relaxed posture |
| 8 | **Ecstatic** | Energetic, highly expressive — bouncing, laughing, wide gestures |
| 9 | **Flirtatious** | Seductive body language, touching object-of-affection's body |
| 10 | **Aroused** | Sexually forward — will flirt and escalate toward intimacy |
| 11 | **Sex-Crazed** | Direct aggressive sexual interaction — will interrupt player activities to initiate |
| 12 (peak) | **Climax Coma** | Shock-like state but without pain/distress. If partners handle all movement, can be sustained indefinitely. This is the "maxed out" level. |

### Design Notes
- Mood is **not** a linear scale — an NPC can transition between non-adjacent moods
  based on stimuli (e.g. Neutral → Afraid on sudden threat).
- Arousal, comfort, and discomfort from existing systems feed into mood transitions.
- Climax Coma is entered when orgasm intensity is extreme; NPC goes limp but remains
  responsive to continued stimulation. Exit requires arousal dropping below threshold.
- Mood drives which animation set / blend tree branch is active.

---

## 22. NPC Room Awareness & Idle Activities

### Room Awareness — Detecting Intimate Activity
Every NPC should detect physical/intimate activity happening in the room.
When an idle NPC detects it, they roll against a behavior table:

| Behavior | Description |
|----------|-------------|
| **Watch (from current position)** | Turns head/body to observe; stays put |
| **Watch + masturbate (current position)** | Watches and self-stimulates where they are |
| **Walk over + watch** | Moves closer to observe from nearby |
| **Walk over + masturbate** | Approaches and self-stimulates while watching |
| **Walk over + join** | Approaches and physically joins the activity |

Probability weights are influenced by current mood, arousal level, and relationship
with the participants (future: personality traits from CharacterProfile).

### Idle Activities
NPCs not engaged in interaction pick from available activities:

| Activity | Animation Type | Notes |
|----------|---------------|-------|
| Sitting/lying on furniture | Contextual IK | Needs furniture interaction points |
| Yoga | Pose sequence | Reuses pose system |
| Dancing | Looping anim | Music-reactive if audio playing |
| Pole dancing | Prop-anchored anim | Requires pole prop in scene |
| Reading a book | Seated + hand IK | Prop: book object |
| Playing chess | Seated + hand controls | Two-NPC activity; exercises hand IK |
| Masturbating | Self-interaction | Driven by arousal level threshold |
| Engaging other NPCs sexually | Multi-NPC scenario | Uses existing interaction systems |

---

## 23. Fluid Persistence & Resource Management

### Goal
All generated fluids (particles, decals, strings) remain rendered in the scene
**indefinitely** as long as system resources allow.

### Eviction Policy
When resource pressure is detected (VRAM, particle count, or frame budget):
1. Sort all active fluid instances by **creation timestamp** (oldest first).
2. Evict oldest instances first — fade out over ~0.5 s, then free.
3. Newly created fluids are never evicted in the same frame they spawn.

### Thresholds (tunable in config)
| Metric | Soft Limit | Hard Limit | Action |
|--------|-----------|------------|--------|
| Active particle systems | 50 | 80 | Soft: stop spawning new. Hard: evict oldest. |
| Surface decal count | 100 | 150 | Same eviction pattern. |
| Fluid string count | 20 | 30 | Strings are short-lived anyway; hard limit forces oldest cut. |
| GPU frame time delta | +2 ms | +4 ms | Soft: reduce emission rates. Hard: bulk evict. |

### Implementation Location
`FluidSystem._process()` already runs per-frame. Add a resource monitor
that checks counts against limits and calls eviction when needed.
The `_active_emitters` dictionary and `FluidSurface._active_patches` array
already track everything needed for age-sorted eviction.

---

## 24. Constriction & Grip Pressure Systems

Two sibling systems that share the same pressure-ramp architecture but map to
different output domains.

### 24a. Constriction System (`constriction_system.gd`)

**Purpose:** External neck squeeze (choking) + oral-depth airway occlusion.

#### Inputs
| Source | Signal / Poll | What it provides |
|--------|--------------|------------------|
| Neck `BodyPart` | `part_grabbed` / `part_released` | Grip on/off |
| `ThirdPartyInsertion` | `depth_changed("oral", …)` | Oral depth → airway occlusion |

#### Outputs
| Property | Range | Meaning |
|----------|-------|---------|
| `constriction_pressure` | 0–1 | Raw neck grip strength |
| `oral_airway_occlusion` | 0–1 | How much oral depth blocks the airway |
| `airway_level` | 0–1 | Combined (max of grip + oral). 0 = open, 1 = sealed |
| `consciousness` | 0–1 | 1 = awake, 0 = blacked out |
| `breathing_suppression` | 0–1 | Read by BodyLanguageSystem to dampen breathing |
| `breath_amplitude_override` | float | Multiplier on breathing amplitude |
| `breath_frequency_override` | float | Multiplier on breathing frequency |

#### Key Tuning
| Parameter | Default | Notes |
|-----------|---------|-------|
| `grip_airway_factor` | 0.85 | Fraction of grip that occludes airway |
| `pain_only_threshold` | 0.7 | Below = erogenous comfort; above = pain only |
| `blackout_time` | 8 s | Full seal before consciousness lost |
| `recovery_time` | 4 s | Open airway needed to recover |
| `gasp_duration` | 1.2 s | Exaggerated recovery breaths on release |

#### Flow
1. Neck grabbed → pressure ramps up (4.0/s)
2. `airway_level` computed as max(grip contribution, oral occlusion)
3. Nerve PRESS on neck at `intensity = pressure × 0.6`
4. Light pressure → comfort; heavy → discomfort → tears
5. `BodyLanguageSystem` reads `breath_amplitude_override` / `breath_frequency_override`
6. At 90%+ airway → blackout timer ticks; 8 s = unconscious
7. On release → gasp recovery (amplitude ×3, 1.2 s)

---

### 24b. Grip Pressure System (`grip_pressure_system.gd`)

**Purpose:** External squeeze on penis segments. Light = pleasure, hard = pain.

#### Inputs
| Source | Signal / Poll | What it provides |
|--------|--------------|------------------|
| `penis_base/mid/tip` BodyParts | `part_grabbed` / `part_released` | Per-segment grab |
| Segment RigidBody3D | `global_position` (polled) | Velocity for stroke detection |

#### Outputs
| Property | Range | Meaning |
|----------|-------|---------|
| `grip_pressure` | 0–1 | Weighted combination of all segments |
| `segment_pressure` | Dict[0–1] | Per-segment pressure |
| `is_gripped` | bool | Any segment held |

#### Key Tuning
| Parameter | Default | Notes |
|-----------|---------|-------|
| `pleasure_peak_pressure` | 0.45 | Sweet spot — Gaussian centre |
| `pleasure_curve_width` | 0.2 | Gaussian σ |
| `max_pleasure_per_second` | 8.0 | Comfort/s at peak |
| `pain_threshold` | 0.7 | Above → linear pain ramp |
| `max_pain_per_second` | 15.0 | Discomfort/s at full crush |
| `arousal_boost_per_second` | 0.06 | Arousal Δ/s at peak pleasure |
| `stroke_velocity_threshold` | 0.15 m/s | Axial velocity to detect stroke |

#### Pleasure / Pain Curve
- Gaussian bell for pleasure centred at `pleasure_peak_pressure` (0.45)
- Linear ramp for pain above `pain_threshold` (0.7)
- Both feed CharacterProfile comfort/discomfort

#### Stroke Detection
Monitors shaft-axis velocity on the mid segment. When axial speed exceeds
`stroke_velocity_threshold` → fires a STROKE touch type with ×1.8 pleasure
multiplier plus a comfort bonus.

#### Integration with ArousalSystem
The existing `grab_stiffness_factor` (0.25) in ArousalSystem already softens
erection physics when any penis part is grabbed. GripPressureSystem operates
on top of that — it doesn't duplicate the stiffness override, it adds the
pleasure/pain/nerve/stroke layer.

### Shared Architecture Pattern
Both systems use:
- **Pressure ramp** — smoothed via `ramp_speed` / `release_speed` per tick
- **Nerve PRESS events** — intensity scaled by pressure
- **Comfort/Discomfort dual curve** — light = comfort, heavy = discomfort
- **Signal-based state tracking** — `*_started` / `*_ended` transitions

---

## 25. Mouth Action System (Oral + Tongue)

Two cooperating systems that drive jaw motor, suction, biting, and tongue
surface-following on top of the existing ragdoll anatomy (jaw hinge,
3-segment tongue, oral passage).

### 25a. TouchType Additions

| TouchType | Base Mult | Zone Interactions |
|-----------|-----------|-------------------|
| `LICK` | 0.4 | EROGENOUS ×2.0, TICKLISH ×2.2 |
| `SUCK` | 0.7 | EROGENOUS ×1.8 |
| `BITE` | 1.6 | PAIN_PRONE ×1.6, PRESSURE_POINT ×1.5 |

### 25b. Oral Action System (`oral_action_system.gd`)

**Purpose:** Jaw motor control, suction physics, bite-clamp, "what's in the mouth" detection.

#### Action Modes
| Mode | Jaw Behaviour | Nerve Output |
|------|--------------|--------------|
| IDLE | Rest (2° open) | None |
| SUCK | Oscillates around 8° at 1.2 Hz | SUCK on enclosed parts each pulse |
| BITE | Clamps toward 0° | BITE on enclosed parts, pressure ramps to 0.8 |
| LICK | Opens to 12° (tongue room) | Delegated to TongueSurfaceFollow |
| OPEN | Opens to 30° | None (insertion prep) |

#### Enclosed Part Detection
Scans BodyParts within `mouth_detection_radius` (4 cm) of mouth centre every
0.1 s. Checks all NPC and player ragdolls except self.

#### Cross-NPC Nerve Routing
`_apply_touch_to_owner()` finds the NerveSystem on the **owner** of the target
BodyPart and calls `receive_touch()` on it — so sucking player's finger
stimulates the player, not the NPC doing the sucking.

### 25c. Tongue Surface Follow (`tongue_surface_follow.gd`)

**Purpose:** Steers the 3-segment tongue chain to follow / trace body surfaces.

#### Modes
| Mode | Behaviour |
|------|-----------|
| RETRACTED | Spring return to jaw (rest position) |
| FOLLOW | Tip tracks a single BodyPart surface point |
| PATH | Tip traces a sequence of BodyPart surface points with dwell time |

#### Physics Approach
- **No IK** — applies forces (`apply_central_force`) to tongue segments
- Tip: `tip_follow_force` (3 N) toward target
- Mid: `mid_shaping_force` (1.5 N) toward midpoint of base↔target (curves the tongue)
- Overshoot damping when tip velocity opposes target direction
- Contact detected when tip is within `contact_distance` (1.5 cm)
- Max reach: 12 cm — beyond this, tongue gives up

#### Lick Nerve Events
While in contact, fires `TouchType.LICK` on the target part's owner NerveSystem.
Intensity scales with tongue-tip velocity (active licking = ×1.5 bonus).
Also self-stimulates tongue_tip at 30% intensity (tongue is erogenous).

#### Path Mode (Advanced Licking)
`start_path()` accepts an array of `{part: BodyPart, offset: Vector3}` steps.
Tongue follows each step, dwells `path_dwell_time` (0.8 s), then advances.
Example — lick penis base → shaft → tip → tickle head → retract:
```gdscript
tongue_follow.start_path([
    {"part": ragdoll.parts["penis_base"], "offset": Vector3(0, 0.01, 0)},
    {"part": ragdoll.parts["penis_mid"],  "offset": Vector3(0, 0.01, 0)},
    {"part": ragdoll.parts["penis_tip"],  "offset": Vector3(0, 0.005, 0)},
])
# On path_completed → oral_action.set_action(OralAction.OPEN) → insertion
```

### Integration Points
| System | How it connects |
|--------|----------------|
| `NerveSystem` | Receives LICK / SUCK / BITE touch events |
| `CharacterProfile` | Receives comfort (light bite, suck) / discomfort (hard bite) |
| `ThirdPartyInsertion` | OralAction.OPEN prepares jaw for passage insertion |
| `ConstrictionSystem` | Deep oral insertion → airway occlusion (already wired) |
| `PassageResponse` | Oral passage dilation from insertion (already wired) |
| `FluidSystem` | Saliva (future: triggered by oral activity) |
