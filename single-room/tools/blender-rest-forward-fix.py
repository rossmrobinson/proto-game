"""
Blender Rest Forward Fix

Rotates armature rest pose so forward aligns with a target axis.
Run in Blender (Scripting workspace -> Run Script).

Defaults:
- Target forward: +Y (Blender forward)
- Uses pelvis/chest/upper-leg bones to infer current forward

Adjust TARGET_FORWARD if your rig faces a different axis.
"""

import bpy  # type: ignore
from mathutils import Matrix, Vector  # type: ignore


# --- Config ---
USE_SELECTED_ONLY = True
TARGET_FORWARD = Vector((0.0, 1.0, 0.0))  # +Y in Blender

PELVIS_BONE_NAMES = [
    "pelvis",
    "Root",
    "root",
    "Hips",
    "hips",
]

CHEST_BONE_NAMES = [
    "spine_03",
    "chest",
    "spine_02",
    "spine_2",
    "spine2",
]

LEFT_LEG_BONE_NAMES = [
    "thigh_l",
    "left_upper_leg",
    "upperleg_l",
    "upper_leg_l",
]

RIGHT_LEG_BONE_NAMES = [
    "thigh_r",
    "right_upper_leg",
    "upperleg_r",
    "upper_leg_r",
]


def _find_edit_bone(edit_bones, names):
    for name in names:
        if name in edit_bones:
            return edit_bones[name]
    return None


def _compute_forward(pelvis, chest, left_leg, right_leg):
    up_dir = (chest.head - pelvis.head).normalized()
    if up_dir.length < 1e-6:
        return None
    right_dir = (right_leg.head - left_leg.head).normalized()
    if right_dir.length < 1e-6:
        return None
    forward = up_dir.cross(right_dir)
    if forward.length < 1e-6:
        return None
    return forward.normalized()


def _rotate_armature(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = arm_obj.data.edit_bones

    pelvis = _find_edit_bone(edit_bones, PELVIS_BONE_NAMES)
    chest = _find_edit_bone(edit_bones, CHEST_BONE_NAMES)
    left_leg = _find_edit_bone(edit_bones, LEFT_LEG_BONE_NAMES)
    right_leg = _find_edit_bone(edit_bones, RIGHT_LEG_BONE_NAMES)

    if pelvis is None or chest is None or left_leg is None or right_leg is None:
        bpy.ops.object.mode_set(mode="OBJECT")
        print(f"[ForwardFix] {arm_obj.name}: missing reference bones, skipping")
        return

    forward = _compute_forward(pelvis, chest, left_leg, right_leg)
    if forward is None:
        bpy.ops.object.mode_set(mode="OBJECT")
        print(f"[ForwardFix] {arm_obj.name}: unable to compute forward")
        return

    target_forward = TARGET_FORWARD.normalized()
    axis = forward.cross(target_forward)
    angle = forward.angle(target_forward)

    if axis.length < 1e-6 or angle < 1e-6:
        bpy.ops.object.mode_set(mode="OBJECT")
        print(f"[ForwardFix] {arm_obj.name}: already aligned")
        return

    axis.normalize()
    rot = Matrix.Rotation(angle, 4, axis)
    pivot = pelvis.head.copy()
    transform = Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot)

    for bone in edit_bones:
        bone.transform(transform, roll=True)

    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"[ForwardFix] {arm_obj.name}: rotated by {angle:.3f} rad")


# --- Run ---
objs = []
if USE_SELECTED_ONLY:
    objs = [obj for obj in bpy.context.selected_objects if obj.type == "ARMATURE"]
else:
    objs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]

if not objs:
    print("[ForwardFix] No armatures found")
else:
    for obj in objs:
        _rotate_armature(obj)
