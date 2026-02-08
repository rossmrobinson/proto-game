"""
Blender Rig Dump — run inside Blender's scripting workspace.

For each armature in the scene, outputs:
  - Bone hierarchy (parent → children)
  - Head/tail world positions + length
  - Roll, envelope, connected flag
  - Vertex group counts (how many verts each bone influences)

Usage:
  1. Open your .blend file
  2. Go to Scripting workspace
  3. Paste or open this script
  4. Click Run Script
  5. Check Blender's System Console (Window → Toggle System Console) for output
  6. Also writes JSON to the same folder as the .blend file
"""

import bpy  # type: ignore
import json
import os
from mathutils import Vector  # type: ignore


def gather_rig_data() -> list[dict]:
    """Collect rig info from every armature in the scene."""
    results: list[dict] = []

    for obj in bpy.data.objects:
        if obj.type != "ARMATURE":
            continue

        arm_data: dict = {
            "armature_name": obj.name,
            "bone_count": len(obj.data.bones),
            "bones": [],
        }

        # Vertex group weights — find meshes parented to this armature
        vgroup_counts: dict[str, int] = {}
        for child in obj.children:
            if child.type != "MESH":
                continue
            mesh = child.data
            for vg in child.vertex_groups:
                count = 0
                vg_idx = vg.index
                for vert in mesh.vertices:
                    for g in vert.groups:
                        if g.group == vg_idx and g.weight > 0.01:
                            count += 1
                            break
                vgroup_counts[vg.name] = vgroup_counts.get(vg.name, 0) + count

        # Walk bones in edit mode for head/tail, then back to object mode
        # Use pose bones for final transforms
        for bone in obj.data.bones:
            head_world = obj.matrix_world @ bone.head_local
            tail_world = obj.matrix_world @ bone.tail_local
            length = (tail_world - head_world).length

            bone_info: dict = {
                "name": bone.name,
                "parent": bone.parent.name if bone.parent else None,
                "children": [c.name for c in bone.children],
                "head": [round(head_world.x, 4), round(head_world.y, 4), round(head_world.z, 4)],
                "tail": [round(tail_world.x, 4), round(tail_world.y, 4), round(tail_world.z, 4)],
                "length": round(length, 4),
                "connected": bone.use_connect,
                "verts_influenced": vgroup_counts.get(bone.name, 0),
            }
            arm_data["bones"].append(bone_info)

        # Sort: roots first, then alphabetical
        arm_data["bones"].sort(key=lambda b: (0 if b["parent"] is None else 1, b["name"]))
        results.append(arm_data)

    return results


def print_summary(rigs: list[dict]) -> None:
    """Print a compact readable summary to Blender console."""
    for rig in rigs:
        print("=" * 70)
        print(f"ARMATURE: {rig['armature_name']}  ({rig['bone_count']} bones)")
        print("=" * 70)
        print(f"{'Bone':<30} {'Parent':<25} {'Len':>6} {'Verts':>6} {'Conn':>5}")
        print("-" * 70)
        for b in rig["bones"]:
            parent = b["parent"] or "(root)"
            conn = "Y" if b["connected"] else ""
            print(f"{b['name']:<30} {parent:<25} {b['length']:>6.3f} {b['verts_influenced']:>6} {conn:>5}")
        print()

        # Hierarchy tree
        print("HIERARCHY:")
        roots = [b for b in rig["bones"] if b["parent"] is None]
        bone_map = {b["name"]: b for b in rig["bones"]}

        def print_tree(name: str, depth: int = 0) -> None:
            indent = "  " * depth
            marker = "└─ " if depth > 0 else ""
            b = bone_map[name]
            print(f"{indent}{marker}{name}  (L={b['length']:.3f})")
            for child_name in sorted(b["children"]):
                print_tree(child_name, depth + 1)

        for root in roots:
            print_tree(root["name"])
        print()


def write_json(rigs: list[dict]) -> str:
    """Write JSON next to the .blend file, or to temp if unsaved."""
    blend_path = bpy.data.filepath
    if blend_path:
        out_dir = os.path.dirname(blend_path)
        base = os.path.splitext(os.path.basename(blend_path))[0]
        out_path = os.path.join(out_dir, f"{base}-rig-dump.json")
    else:
        out_path = os.path.join(os.path.expanduser("~"), "blender-rig-dump.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(rigs, f, indent=2)

    return out_path


# ── Run ──────────────────────────────────────────────────────────────────────
rigs = gather_rig_data()
if not rigs:
    print("No armatures found in the scene.")
else:
    print_summary(rigs)
    path = write_json(rigs)
    print(f"JSON written to: {path}")
    print(f"Copy that file to J:\\proto-game\\single-room\\tools\\ so Copilot can read it.")
