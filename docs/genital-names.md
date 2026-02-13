Here’s a locked naming sheet you can follow. It avoids redo and stays compatible with the current ragdoll parts.

**Rules**
- Deform vertex group name == bone name (exact match).
- Use `snake_case`; use `left_` / `right_` prefixes.
- Blender‑only mask groups start with `mask_` (safe; ignored by Godot).
- Shape keys use `snake_case`.

**Deform bones + vertex groups (male anatomy)**
- `penis_base`
- `penis_mid`
- `penis_tip`
- `scrotum_left`
- `scrotum_right`

**Deform bones + vertex groups (buttocks)**
- `left_glute`
- `right_glute`

**Detail mask groups (Blender‑only)**
- `mask_penis_shaft`
- `mask_penis_glans`
- `mask_penis_veins`
- `mask_scrotum_left`
- `mask_scrotum_right`
- `mask_scrotum_center`
- `mask_glute_cleft`
- `mask_glute_upper_left`
- `mask_glute_upper_right`
- `mask_glute_lower_left`
- `mask_glute_lower_right`
- `mask_glute_haunch_left`
- `mask_glute_haunch_right`

**Shape keys (animation targets)**
- `penis_erect_len`
- `penis_erect_girth`
- `penis_erect_pose` (optional curve/tilt)
- `penis_pulse` (tiny additive)
- `penis_veins`
- `scrotum_tension`
- `scrotum_relax`

**Scrotum/testicles share one surface**
- Still use `scrotum_left` + `scrotum_right` groups with a soft 50/50 split down the center.
- Use `mask_scrotum_center` if you want the cleft to stay stable.

If you add any new deform bones beyond this list, tell me so I can update the mapping in humanoid_ragdoll_builder.gd.


Short answer: make min + max shape keys, and set the rest pose at a neutral mid (slightly open). That gives the most stable physics and smooth animation.

Why

Rest at mid keeps collisions stable and avoids self‑intersection.
Min/max keys give you full range for animation and procedural “pulse.”
Recommended setup

Sculpt base mesh to the neutral mid.
Shape keys:
tunnel_min (contracted)
tunnel_max (expanded)
Optional tunnel_pulse (small additive)
Drive in Godot with curves (AnimationPlayer or script).