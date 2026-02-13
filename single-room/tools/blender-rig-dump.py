"""
Blender Rig Dump — run inside Blender's scripting workspace.

Comprehensive rig audit tool.  For each armature in the scene, outputs:
  - Total bone count + deform vs non-deform breakdown
  - Bone hierarchy (parent → children) as an indented tree
  - Head/tail world positions, length, roll
  - Connected flag, deform flag
  - Vertex group counts (how many verts each bone influences)
  - Cross-reference against Godot BONE_NAME_MAP (shows unmapped bones)
  - Flags custom soft-tissue bones injected by blender-add-soft-tissue-bones.py
  - Orphan vertex groups (groups with no matching bone)
  - Warnings: zero-length bones, no-vert deform bones, duplicate names

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


ARMATURE_FILTER: str = os.getenv("RIG_DUMP_ARMATURE", "").strip()


# ══════════════════════════════════════════════════════════════════════════════
#  GODOT CROSS-REFERENCE DATA
# ══════════════════════════════════════════════════════════════════════════════
# Mirror of BONE_NAME_MAP from humanoid_ragdoll_builder.gd so we can flag
# unmapped bones without needing Godot running.

GODOT_BONE_NAME_MAP: dict[str, str] = {
    # Root / Torso
    "Hips": "pelvis",
    "Spine": "spine_lower",
    "Spine1": "spine_mid",
    "Spine2": "spine_upper",
    "Spine3": "chest",
    "Neck": "neck",
    "Head": "head",
    # Left Arm
    "LeftShoulder": "left_clavicle",
    "LeftArm": "left_upper_arm",
    "LeftArmRoll": "left_upper_arm",
    "LeftForeArm": "left_forearm",
    "LeftForeArmRoll": "left_forearm",
    "LeftHand": "left_hand",
    # Right Arm
    "RightShoulder": "right_clavicle",
    "RightArm": "right_upper_arm",
    "RightArmRoll": "right_upper_arm",
    "RightForeArm": "right_forearm",
    "RightForeArmRoll": "right_forearm",
    "RightHand": "right_hand",
    # Left Fingers (4 segments)
    "LeftHandThumb1": "left_thumb_00",
    "LeftHandThumb2": "left_thumb_01",
    "LeftHandThumb3": "left_thumb_02",
    "LeftHandThumb4": "left_thumb_03",
    "LeftHandIndex1": "left_index_00",
    "LeftHandIndex2": "left_index_01",
    "LeftHandIndex3": "left_index_02",
    "LeftHandIndex4": "left_index_03",
    "LeftHandMiddle1": "left_middle_00",
    "LeftHandMiddle2": "left_middle_01",
    "LeftHandMiddle3": "left_middle_02",
    "LeftHandMiddle4": "left_middle_03",
    "LeftHandRing1": "left_ring_00",
    "LeftHandRing2": "left_ring_01",
    "LeftHandRing3": "left_ring_02",
    "LeftHandRing4": "left_ring_03",
    "LeftHandPinky1": "left_pinky_00",
    "LeftHandPinky2": "left_pinky_01",
    "LeftHandPinky3": "left_pinky_02",
    "LeftHandPinky4": "left_pinky_03",
    # Right Fingers
    "RightHandThumb1": "right_thumb_00",
    "RightHandThumb2": "right_thumb_01",
    "RightHandThumb3": "right_thumb_02",
    "RightHandThumb4": "right_thumb_03",
    "RightHandIndex1": "right_index_00",
    "RightHandIndex2": "right_index_01",
    "RightHandIndex3": "right_index_02",
    "RightHandIndex4": "right_index_03",
    "RightHandMiddle1": "right_middle_00",
    "RightHandMiddle2": "right_middle_01",
    "RightHandMiddle3": "right_middle_02",
    "RightHandMiddle4": "right_middle_03",
    "RightHandRing1": "right_ring_00",
    "RightHandRing2": "right_ring_01",
    "RightHandRing3": "right_ring_02",
    "RightHandRing4": "right_ring_03",
    "RightHandPinky1": "right_pinky_00",
    "RightHandPinky2": "right_pinky_01",
    "RightHandPinky3": "right_pinky_02",
    "RightHandPinky4": "right_pinky_03",
    # Left Leg
    "LeftUpLeg": "left_upper_leg",
    "LeftUpLegRoll": "left_upper_leg",
    "LeftLeg": "left_lower_leg",
    "LeftLegRoll": "left_lower_leg",
    "LeftFoot": "left_foot",
    # Right Leg
    "RightUpLeg": "right_upper_leg",
    "RightUpLegRoll": "right_upper_leg",
    "RightLeg": "right_lower_leg",
    "RightLegRoll": "right_lower_leg",
    "RightFoot": "right_foot",
    # Left Toes
    "LeftFootThumb1": "left_toe_big_01",
    "LeftFootThumb2": "left_toe_big_02",
    "LeftFootIndex1": "left_toe_index_01",
    "LeftFootIndex2": "left_toe_index_02",
    "LeftFootIndex3": "left_toe_index_03",
    "LeftFootMiddle1": "left_toe_middle_01",
    "LeftFootMiddle2": "left_toe_middle_02",
    "LeftFootMiddle3": "left_toe_middle_03",
    "LeftFootRing1": "left_toe_ring_01",
    "LeftFootRing2": "left_toe_ring_02",
    "LeftFootRing3": "left_toe_ring_03",
    "LeftFootPinky1": "left_toe_pinky_01",
    "LeftFootPinky2": "left_toe_pinky_02",
    "LeftFootPinky3": "left_toe_pinky_03",
    # Right Toes
    "RightFootThumb1": "right_toe_big_01",
    "RightFootThumb2": "right_toe_big_02",
    "RightFootIndex1": "right_toe_index_01",
    "RightFootIndex2": "right_toe_index_02",
    "RightFootIndex3": "right_toe_index_03",
    "RightFootMiddle1": "right_toe_middle_01",
    "RightFootMiddle2": "right_toe_middle_02",
    "RightFootMiddle3": "right_toe_middle_03",
    "RightFootRing1": "right_toe_ring_01",
    "RightFootRing2": "right_toe_ring_02",
    "RightFootRing3": "right_toe_ring_03",
    "RightFootPinky1": "right_toe_pinky_01",
    "RightFootPinky2": "right_toe_pinky_02",
    "RightFootPinky3": "right_toe_pinky_03",
    # Face
    "jaw": "jaw",
    "tongue00": "tongue_base",
    "tongue01": "tongue_mid",
    "tongue02": "tongue_mid",
    "tongue03": "tongue_tip",
    "tongue04": "tongue_tip",
    "tongue05.L": "tongue_mid",
    "tongue05.R": "tongue_mid",
    "tongue06.L": "tongue_mid",
    "tongue06.R": "tongue_mid",
    "tongue07.L": "tongue_tip",
    "tongue07.R": "tongue_tip",
    "eye.L": "left_eye",
    "eye.R": "right_eye",
    # Face muscles → head or jaw
    "special04": "jaw",
    "oris02": "jaw",
    "oris01": "jaw",
    "oris06.L": "jaw",
    "oris06.R": "jaw",
    "oris07.L": "jaw",
    "oris07.R": "jaw",
    "levator02.L": "head",
    "levator02.R": "head",
    "levator03.L": "head",
    "levator03.R": "head",
    "levator04.L": "head",
    "levator04.R": "head",
    "levator05.L": "head",
    "levator05.R": "head",
    "special01": "head",
    "oris04.L": "head",
    "oris04.R": "head",
    "oris03.L": "head",
    "oris03.R": "head",
    "oris06": "head",
    "oris05": "head",
    "special03": "head",
    "levator06.L": "head",
    "levator06.R": "head",
    "special06.L": "head",
    "special06.R": "head",
    "special05.L": "head",
    "special05.R": "head",
    "orbicularis03.L": "head",
    "orbicularis03.R": "head",
    "orbicularis04.L": "head",
    "orbicularis04.R": "head",
    "temporalis01.L": "head",
    "temporalis01.R": "head",
    "temporalis02.L": "head",
    "temporalis02.R": "head",
    "oculi02.L": "head",
    "oculi02.R": "head",
    "oculi01.L": "head",
    "oculi01.R": "head",
    "risorius02.L": "head",
    "risorius02.R": "head",
    "risorius03.L": "head",
    "risorius03.R": "head",
    # Soft-tissue bones (blender-add-soft-tissue-bones.py)
    "left_inner_glute": "left_inner_glute",
    "left_outer_glute": "left_outer_glute",
    "right_inner_glute": "right_inner_glute",
    "right_outer_glute": "right_outer_glute",
    "left_breast_inner": "left_breast_inner",
    "left_breast_outer": "left_breast_outer",
    "left_breast_upper": "left_breast_upper",
    "left_breast_lower": "left_breast_lower",
    "right_breast_inner": "right_breast_inner",
    "right_breast_outer": "right_breast_outer",
    "right_breast_upper": "right_breast_upper",
    "right_breast_lower": "right_breast_lower",
    "left_breast_nipple": "left_breast_nipple",
    "right_breast_nipple": "right_breast_nipple",
    "penis_base": "penis_base",
    "penis_mid": "penis_mid",
    "penis_tip": "penis_tip",
    "scrotum_left": "scrotum_left",
    "scrotum_right": "scrotum_right",
    "labia_left": "labia_left",
    "labia_right": "labia_right",
    "clitoris": "clitoris",
    # Entrance ring bones
    "vaginal_ring_top": "vaginal_ring_top",
    "vaginal_ring_bot": "vaginal_ring_bot",
    "vaginal_ring_left": "vaginal_ring_left",
    "vaginal_ring_right": "vaginal_ring_right",
    "anal_ring_top": "anal_ring_top",
    "anal_ring_bot": "anal_ring_bot",
    "anal_ring_left": "anal_ring_left",
    "anal_ring_right": "anal_ring_right",
    # Oral entrance ring bones
    "oral_ring_top": "oral_ring_top",
    "oral_ring_bot": "oral_ring_bot",
    "oral_ring_left": "oral_ring_left",
    "oral_ring_right": "oral_ring_right",
}
# Programmatically add passage ring bones (8 depths × 4 quadrants × 2 tunnels + 5 depths × 4 quadrants × 1 oral)
for _tunnel in ("vaginal", "anal"):
    for _d in range(8):
        for _q in ("top", "bot", "left", "right"):
            _key = f"{_tunnel}_passage_{_d}_{_q}"
            GODOT_BONE_NAME_MAP[_key] = _key
for _d in range(5):
    for _q in ("top", "bot", "left", "right"):
        _key = f"oral_passage_{_d}_{_q}"
        GODOT_BONE_NAME_MAP[_key] = _key

# Bones injected by blender-add-soft-tissue-bones.py (not in stock rig)
CUSTOM_SOFT_TISSUE_BONES: set[str] = {
    "left_inner_glute", "left_outer_glute",
    "right_inner_glute", "right_outer_glute",
    "left_breast_inner", "left_breast_outer",
    "left_breast_upper", "left_breast_lower",
    "right_breast_inner", "right_breast_outer",
    "right_breast_upper", "right_breast_lower",
    "left_breast_nipple", "right_breast_nipple",
    "penis_base", "penis_mid", "penis_tip",
    "scrotum_left", "scrotum_right",
    "labia_left", "labia_right", "clitoris",
}
# Add passage/ring bones to custom set
for _tunnel in ("vaginal", "anal"):
    for _q in ("top", "bot", "left", "right"):
        CUSTOM_SOFT_TISSUE_BONES.add(f"{_tunnel}_ring_{_q}")
    for _d in range(8):
        for _q in ("top", "bot", "left", "right"):
            CUSTOM_SOFT_TISSUE_BONES.add(f"{_tunnel}_passage_{_d}_{_q}")
# Oral passage (5 depths)
for _q in ("top", "bot", "left", "right"):
    CUSTOM_SOFT_TISSUE_BONES.add(f"oral_ring_{_q}")
for _d in range(5):
    for _q in ("top", "bot", "left", "right"):
        CUSTOM_SOFT_TISSUE_BONES.add(f"oral_passage_{_d}_{_q}")


# ══════════════════════════════════════════════════════════════════════════════
#  DATA COLLECTION
# ══════════════════════════════════════════════════════════════════════════════

def _get_edit_bone_rolls(armature_obj: object) -> dict[str, float]:
    """Enter edit mode briefly to grab roll values (only available on EditBones)."""
    prev_mode: str = armature_obj.mode if hasattr(armature_obj, "mode") else "OBJECT"
    bpy.context.view_layer.objects.active = armature_obj
    bpy.ops.object.mode_set(mode="EDIT")
    rolls: dict[str, float] = {}
    for ebone in armature_obj.data.edit_bones:
        rolls[ebone.name] = round(ebone.roll, 4)
    bpy.ops.object.mode_set(mode=prev_mode if prev_mode != "EDIT" else "OBJECT")
    return rolls


def _count_vertex_influences(armature_obj: object) -> dict[str, int]:
    """Count how many vertices (weight > 0.01) each vertex group influences."""
    counts: dict[str, int] = {}
    for child in armature_obj.children:
        if child.type != "MESH":
            continue
        mesh = child.data
        for vg in child.vertex_groups:
            count: int = 0
            vg_idx: int = vg.index
            for vert in mesh.vertices:
                for g in vert.groups:
                    if g.group == vg_idx and g.weight > 0.01:
                        count += 1
                        break
            counts[vg.name] = counts.get(vg.name, 0) + count
    return counts


def _get_all_vertex_group_names(armature_obj: object) -> set[str]:
    """Return the union of all vertex group names across child meshes."""
    names: set[str] = set()
    for child in armature_obj.children:
        if child.type != "MESH":
            continue
        for vg in child.vertex_groups:
            names.add(vg.name)
    return names


def gather_rig_data() -> list[dict]:
    """Collect rig info from armatures in the scene (optionally filtered by name)."""
    results: list[dict] = []

    for obj in bpy.data.objects:
        if obj.type != "ARMATURE":
            continue
        if ARMATURE_FILTER and obj.name != ARMATURE_FILTER:
            continue

        rolls: dict[str, float] = _get_edit_bone_rolls(obj)
        vgroup_counts: dict[str, int] = _count_vertex_influences(obj)
        all_vgroups: set[str] = _get_all_vertex_group_names(obj)
        bone_names_set: set[str] = {b.name for b in obj.data.bones}

        # Orphan vertex groups: exist on mesh but have no matching bone
        orphan_vgroups: list[str] = sorted(all_vgroups - bone_names_set)

        deform_count: int = 0
        non_deform_count: int = 0
        warnings: list[str] = []
        bones_list: list[dict] = []

        for bone in obj.data.bones:
            head_world = obj.matrix_world @ bone.head_local
            tail_world = obj.matrix_world @ bone.tail_local
            length: float = (tail_world - head_world).length
            is_deform: bool = bone.use_deform
            is_custom: bool = bone.name in CUSTOM_SOFT_TISSUE_BONES
            godot_part: str = GODOT_BONE_NAME_MAP.get(bone.name, "")
            verts: int = vgroup_counts.get(bone.name, 0)
            roll: float = rolls.get(bone.name, 0.0)

            if is_deform:
                deform_count += 1
            else:
                non_deform_count += 1

            # Warnings
            bone_warnings: list[str] = []
            if length < 0.0001:
                bone_warnings.append("ZERO_LENGTH")
                warnings.append(f"Zero-length bone: {bone.name}")
            if is_deform and verts == 0:
                bone_warnings.append("NO_VERTS")
                warnings.append(f"Deform bone with 0 vertices: {bone.name}")
            if is_deform and godot_part == "":
                bone_warnings.append("UNMAPPED")
                warnings.append(f"Deform bone not in BONE_NAME_MAP: {bone.name}")

            bone_info: dict = {
                "name": bone.name,
                "parent": bone.parent.name if bone.parent else None,
                "children": [c.name for c in bone.children],
                "head": [round(head_world.x, 4), round(head_world.y, 4), round(head_world.z, 4)],
                "tail": [round(tail_world.x, 4), round(tail_world.y, 4), round(tail_world.z, 4)],
                "length": round(length, 4),
                "roll": roll,
                "connected": bone.use_connect,
                "deform": is_deform,
                "custom_bone": is_custom,
                "godot_part": godot_part,
                "verts_influenced": verts,
                "warnings": bone_warnings,
            }
            bones_list.append(bone_info)

        # Sort: roots first, then alphabetical
        bones_list.sort(key=lambda b: (0 if b["parent"] is None else 1, b["name"]))

        arm_data: dict = {
            "armature_name": obj.name,
            "bone_count": len(obj.data.bones),
            "deform_bones": deform_count,
            "non_deform_bones": non_deform_count,
            "custom_soft_tissue_bones": sum(1 for b in bones_list if b["custom_bone"]),
            "mapped_to_godot": sum(1 for b in bones_list if b["godot_part"] != ""),
            "unmapped_deform": sum(1 for b in bones_list if b["deform"] and b["godot_part"] == ""),
            "orphan_vertex_groups": orphan_vgroups,
            "warnings": warnings,
            "bones": bones_list,
        }
        results.append(arm_data)

    return results


# ══════════════════════════════════════════════════════════════════════════════
#  CONSOLE OUTPUT
# ══════════════════════════════════════════════════════════════════════════════

def print_summary(rigs: list[dict]) -> None:
    """Print a compact readable summary to Blender console."""
    for rig in rigs:
        print()
        print("=" * 90)
        print(f"  ARMATURE: {rig['armature_name']}")
        print(f"  Total bones: {rig['bone_count']}  "
              f"(deform: {rig['deform_bones']}, non-deform: {rig['non_deform_bones']})")
        print(f"  Custom soft-tissue bones found: {rig['custom_soft_tissue_bones']}")
        print(f"  Mapped to Godot: {rig['mapped_to_godot']}  "
              f"| Unmapped deform: {rig['unmapped_deform']}")
        if rig["orphan_vertex_groups"]:
            print(f"  Orphan vertex groups (no bone): {len(rig['orphan_vertex_groups'])}")
        print("=" * 90)

        # ── Warnings ─────────────────────────────────────────────────────────
        if rig["warnings"]:
            print()
            print(f"  ⚠ WARNINGS ({len(rig['warnings'])}):")
            for w in rig["warnings"]:
                print(f"    - {w}")

        # ── Bone table ───────────────────────────────────────────────────────
        print()
        hdr = (f"{'Bone':<32} {'Parent':<24} {'Godot Part':<24} "
               f"{'Len':>6} {'Roll':>6} {'Verts':>6} {'Def':>4} {'Cst':>4} {'Flags'}")
        print(hdr)
        print("-" * len(hdr))
        for b in rig["bones"]:
            parent: str = b["parent"] or "(root)"
            godot: str = b["godot_part"] or "---"
            deform: str = "D" if b["deform"] else ""
            custom: str = "C" if b["custom_bone"] else ""
            flags: str = " ".join(b["warnings"]) if b["warnings"] else ""
            print(f"{b['name']:<32} {parent:<24} {godot:<24} "
                  f"{b['length']:>6.3f} {b['roll']:>6.2f} {b['verts_influenced']:>6} "
                  f"{deform:>4} {custom:>4} {flags}")

        # ── Orphan vertex groups ─────────────────────────────────────────────
        if rig["orphan_vertex_groups"]:
            print()
            print("  ORPHAN VERTEX GROUPS (no matching bone):")
            for name in rig["orphan_vertex_groups"]:
                print(f"    - {name}")

        # ── Hierarchy tree ───────────────────────────────────────────────────
        print()
        print("  HIERARCHY TREE:")
        bone_map: dict[str, dict] = {b["name"]: b for b in rig["bones"]}

        def print_tree(name: str, prefix: str = "", is_last: bool = True) -> None:
            b = bone_map[name]
            connector: str = "└── " if is_last else "├── "
            tag: str = ""
            if b["custom_bone"]:
                tag += " [CUSTOM]"
            if b["deform"] and b["godot_part"] == "":
                tag += " [UNMAPPED]"
            if b["warnings"]:
                tag += " [!]"
            print(f"  {prefix}{connector}{name}{tag}")
            children: list[str] = sorted(b["children"])
            child_prefix: str = prefix + ("    " if is_last else "│   ")
            for i, child_name in enumerate(children):
                print_tree(child_name, child_prefix, i == len(children) - 1)

        roots: list[dict] = [b for b in rig["bones"] if b["parent"] is None]
        for i, root in enumerate(roots):
            print_tree(root["name"], "", i == len(roots) - 1)

        # ── Quick stats ──────────────────────────────────────────────────────
        print()
        print("  BONE NAME MAP COVERAGE:")
        mapped_names: set[str] = {b["name"] for b in rig["bones"] if b["godot_part"] != ""}
        unmapped_deform: list[str] = sorted(
            b["name"] for b in rig["bones"] if b["deform"] and b["godot_part"] == ""
        )
        unmapped_non_deform: list[str] = sorted(
            b["name"] for b in rig["bones"] if not b["deform"] and b["godot_part"] == ""
        )
        print(f"    Mapped: {len(mapped_names)}/{rig['bone_count']}")
        if unmapped_deform:
            print(f"    Unmapped DEFORM bones ({len(unmapped_deform)}) — NEED MAPPING:")
            for n in unmapped_deform:
                print(f"      - {n}")
        if unmapped_non_deform:
            print(f"    Unmapped non-deform bones ({len(unmapped_non_deform)}) — OK to skip:")
            for n in unmapped_non_deform:
                print(f"      - {n}")
        print()


# ══════════════════════════════════════════════════════════════════════════════
#  JSON OUTPUT
# ══════════════════════════════════════════════════════════════════════════════

def write_json(rigs: list[dict]) -> str:
    """Write JSON next to the .blend file, or to temp if unsaved."""
    blend_path: str = bpy.data.filepath
    if blend_path:
        out_dir: str = os.path.dirname(blend_path)
        base: str = os.path.splitext(os.path.basename(blend_path))[0]
        out_path: str = os.path.join(out_dir, f"{base}-rig-dump.json")
    else:
        out_path = os.path.join(os.path.expanduser("~"), "blender-rig-dump.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(rigs, f, indent=2)

    return out_path


# ── Run ──────────────────────────────────────────────────────────────────────
rigs = gather_rig_data()
if not rigs:
    if ARMATURE_FILTER:
        print(f"No armatures found matching filter: {ARMATURE_FILTER}")
    else:
        print("No armatures found in the scene.")
else:
    print_summary(rigs)

path = write_json(rigs)
print(f"JSON written to: {path}")
if ARMATURE_FILTER:
    print(f"Armature filter applied: {ARMATURE_FILTER}")
print(f"Copy that file to J:\\proto-game\\single-room\\ so Copilot can read it.")
