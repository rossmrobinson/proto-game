# Deep Research Request: Active Ragdoll System in Godot 4.6 + Jolt Physics

## Who This Is For

I need Gemini Deep Research to find real-world solutions, working implementations, papers, and Godot-specific techniques for building a **stable always-on active ragdoll** in Godot 4.6 with Jolt Physics. We've been iterating blindly and need expert-level guidance.

---

## What We're Building

An interactive 3D game where 2 humanoid NPCs stand in a room. Each NPC has:
- A **skinned mesh** imported from Blender (`.blend` file, ~53 bones)
- A **procedural ragdoll** built in GDScript: 66 `RigidBody3D` ("BodyPart") nodes connected by `Generic6DOFJoint3D` joints
- An **active ragdoll controller** ("SkeletonBinding") that applies spring forces every `_physics_process` to hold the ragdoll in a target pose
- Each body part is **individually grabbable** — when grabbed, its spring weakens to 5% so the player can move it

The skinned mesh must follow the ragdoll (not the other way around). We write ragdoll transforms back into `Skeleton3D` bone poses every frame so the mesh deforms to match.

---

## The Problem We Can't Solve

The ragdolls **shake/vibrate/seize in place**. They don't explode anymore (we fixed that), but they oscillate rapidly — a high-frequency jitter that makes them look like they're having a seizure. They hold roughly the right pose but never settle into stillness.

We've been through **12+ commits** trying to fix this. Every parameter change either makes them explode or keeps them vibrating. We suspect we're fundamentally misunderstanding something about how springs interact with Jolt physics in Godot.

---

## Our Architecture (Exact Current Implementation)

### Ragdoll Construction (`humanoid_ragdoll_builder.gd`)

- 66 `BodyPart` nodes (extends `RigidBody3D`), all children of one `Node3D`
- Connected by `Generic6DOFJoint3D` with locked linear axes (0,0 limits) and per-joint angular limits in degrees
- Part masses range from **0.05 kg** (finger tips) to **10.0 kg** (chest)
- All 66 parts within one NPC have mutual `add_collision_exception_with()` — no self-collision
- Parts are `freeze = true` with `FREEZE_MODE_KINEMATIC` at build time
- `continuous_cd = true` on all parts
- Parts are on physics layers 3+4, mask 1+3+4+5 (NOT layer 1 or 2)

### Skeleton Binding (`skeleton_binding.gd`)

**Bind sequence:**
1. Build bone_idx → BodyPart mapping using a name dictionary
2. Cache `skeleton.get_bone_global_pose(bone_idx)` for each mapped bone into `_rest_poses` dictionary — these are the **spring targets** and never change
3. Adjust rest poses: rotate arm chains 75° down from T-pose (arms-at-sides idle)
4. Snap all parts to bone positions (`global_transform = bone_global`)
5. Keep parts frozen for 3 physics frames while re-snapping each frame
6. Unfreeze all parts, set velocities to zero

**Every `_physics_process` after unfreeze:**
1. Ramp `_spring_scale` from 0→1 over 0.4 seconds
2. For each bone→part pair, apply spring forces:

```
# Position spring (PD controller)
displacement = target_pos - part.global_position
force = displacement * spring_stiffness * stiff_mult
force -= part.linear_velocity * spring_damping * stiff_mult
force = force.limit_length(max_spring_accel * part.mass)
part.apply_central_force(force)

# Rotation spring (PD controller via quaternion difference)
diff_quat = target_quat * current_quat.inverse()
# (shortest arc, extract axis-angle)
torque = axis * angle * angular_stiffness * stiff_mult
torque -= part.angular_velocity * angular_damping * stiff_mult
torque = torque.limit_length(max_angular_accel * part.mass)
part.apply_torque(torque)
```

3. Write physics transforms back into skeleton:
```
part_in_skel = skeleton.global_transform.inverse() * part.global_transform
skeleton.set_bone_pose(bone_idx, local_pose)  # relative to parent bone
```

**Current tuning values:**
| Parameter | Value |
|-----------|-------|
| `spring_stiffness` | 400 N/m |
| `spring_damping` | 40 |
| `angular_stiffness` | 80 N·m/rad |
| `angular_damping` | 12 |
| `max_spring_accel` | 80 m/s² |
| `max_angular_accel` | 60 rad/s² |
| `spawn_ramp_time` | 0.4 s |
| `spawn_freeze_frames` | 3 |

### Joints

All joints are `Generic6DOFJoint3D` with:
- Linear limits locked to (0, 0) on all axes
- Angular limits set per-joint in degrees (e.g., elbow: -5 to 145° on X)
- No angular spring/damping set on the joints themselves (except soft-tissue joints)
- Joint `position` is set to the anchor point in world space at build time

### What We've Already Tried

| Attempt | Result |
|---------|--------|
| Higher spring stiffness (400→800) | More violent vibration |
| Lower spring stiffness (400→100) | Parts droop, still vibrate |
| Higher damping (40→100) | Slight improvement, still jitters |
| Damping ratio tuning | Can't find stable zone |
| Force clamping (20→80 m/s²) | Prevents explosion but doesn't stop vibration |
| Caching rest poses (immutable spring targets) | Fixed a feedback loop bug but vibration remains |
| Freeze + snap + ramp sequence | Prevents initial explosion, vibration starts after ramp |
| Different ramp times (0.2→0.6s) | No meaningful difference |
| `continuous_cd = true` on all parts | No visible effect |

---

## Environment Details

- **Engine:** Godot 4.6 stable (build `89cea1439`)
- **Physics:** Jolt Physics (godot-jolt extension, NOT default GodotPhysics)
- **Renderer:** Forward+ (D3D12, Vulkan), NVIDIA GTX 1070
- **Physics rate:** Default 60 Hz (we have NOT changed `physics/common/physics_ticks_per_second`)
- **OS:** Windows 11

---

## Specific Questions for Research

### 1. Fundamental Approach
Is applying `apply_central_force()` + `apply_torque()` per-frame to RigidBody3D the correct way to build an active ragdoll in Godot 4.6 with Jolt? Or should we be using a completely different mechanism, such as:
- Setting `linear_velocity` / `angular_velocity` directly instead of forces?
- Using joint motors (angular motor on `Generic6DOFJoint3D`) instead of external spring forces?
- Using `_integrate_forces()` callback instead of `_physics_process()`?
- Using Jolt-specific APIs or settings we're not aware of?

### 2. Spring-Joint Conflict
We suspect our springs fight our joints. The spring pulls a forearm toward position X, but the elbow joint constrains it to an arc — the joint correction and spring force may alternate each frame, causing oscillation. Is this a known issue? How do other active ragdoll implementations avoid this?

### 3. Correct PD Controller Tuning for Ragdolls
Our PD controller applies force proportional to displacement and damping proportional to velocity. But we're operating on individual rigid bodies that are connected by joints in a chain. Is a simple PD controller fundamentally wrong for this? Should we be using:
- Per-joint angle PD controllers (torque applied at joints, not at body COM)?
- Inverse dynamics / computed torque methods?
- A different spring model that accounts for the chain structure?

### 4. Jolt Physics Specifics
- Does Jolt have built-in joint motor support that Godot exposes? (Generic6DOFJoint3D has `FLAG_ENABLE_MOTOR` — should we use that instead of `apply_torque`?)
- Does Jolt's solver iterate in a way that makes our per-frame forces destabilize?
- Is there a recommended physics tick rate for ragdoll stability in Jolt? (Should we run at 120Hz?)
- Does `continuous_cd = true` on 66 bodies cause performance/stability issues?

### 5. Skeleton Writeback
We write physics transforms back into the Skeleton3D every frame. Is this the correct way to skin a mesh to a ragdoll in Godot 4.6? Or should we:
- Use `PhysicalBoneSimulator3D` for the writeback part (even if not for the spring forces)?
- Use `BoneAttachment3D` nodes?
- Calculate skin deformation differently?

### 6. Reference Implementations
Are there any open-source Godot 4.x active ragdoll implementations that:
- Work with Jolt physics?
- Use always-on springs (not just "toggle ragdoll on death")?
- Support per-bone grab/interaction?
- Have been proven stable?

### 7. Alternative Architecture
Would it be more stable and simpler to:
- Have the skeleton play animations normally
- Use `PhysicalBoneSimulator3D` to overlay ragdoll physics on specific bones when interacted with
- Only switch to full ragdoll on certain events (collapse, grab, push)
- This would mean the NPC is animation-driven by default, not physics-driven

### 8. Mass and Scale Issues
Our finger tips are 0.05 kg and our chest is 10 kg — a 200:1 mass ratio in the same joint chain. Is this causing numerical instability in Jolt? What mass ratios are safe? Should we use uniform masses for stability?

### 9. Physics Tick Rate
We're at default 60 Hz. For 66 rigid bodies per NPC (132 total) with tight joints, should we be running at 120 or 240 Hz? What's the performance trade-off on a GTX 1070?

---

## What "Success" Looks Like

Two humanoid NPCs standing in a room:
- Holding a relaxed idle pose with arms at sides
- No visible vibration or jitter
- Gently swaying or breathing subtly (natural micro-motion is fine)
- When the player grabs any body part, springs weaken and the part follows the player's hand
- When released, the part smoothly returns to its target pose
- The skinned mesh accurately follows the physics simulation
- Stable at 60 FPS on a GTX 1070

---

## What We Need Back

1. **A recommended architecture** — should we keep our force-based springs or switch to joint motors / animation-hybrid / different approach entirely?
2. **Specific Godot 4.6 API calls** to use (not generic physics advice — we need the actual node types, methods, and properties)
3. **Tuning guidelines** — what spring/damping values work for stable PD controllers on ragdoll chains in Jolt?
4. **Code patterns or references** — any open-source Godot 4 active ragdoll that we can study
5. **A step-by-step migration plan** if the answer is "your current architecture is fundamentally wrong"
