import math
import importlib

bpy = None
Vector = None
Matrix = None
WORLD_UP = None
APPLY_TRANSFORMS = True
ROTATE_BOUND_MESHES = True
RELINK_MESHES = True
APPLY_MESH_TRANSFORMS = False

PELVIS_NAMES = [
    "pelvis",
    "hips",
    "root",
    "root_pelvis",
]
CHEST_NAMES = [
    "spine_03",
    "chest",
    "spine_upper",
    "spine_02",
]
LEFT_LEG_NAMES = [
    "thigh_l",
    "upper_leg_l",
    "left_upper_leg",
]
RIGHT_LEG_NAMES = [
    "thigh_r",
    "upper_leg_r",
    "right_upper_leg",
]


def _ensure_blender_imports():
    global bpy, Vector, Matrix, WORLD_UP
    if bpy is not None:
        return
    bpy = importlib.import_module("bpy")
    mathutils = importlib.import_module("mathutils")
    Vector = mathutils.Vector
    Matrix = mathutils.Matrix
    WORLD_UP = Vector((0.0, 0.0, 1.0))


def _find_bone(armature_obj, name_list):
    bones = armature_obj.data.bones
    lower_map = {b.name.lower(): b for b in bones}
    for name in name_list:
        bone = lower_map.get(name.lower())
        if bone is not None:
            return bone
    return None


def _get_up_dir(armature_obj):
    pelvis = _find_bone(armature_obj, PELVIS_NAMES)
    chest = _find_bone(armature_obj, CHEST_NAMES)
    if pelvis is None or chest is None:
        return None
    vec = chest.head_local - pelvis.head_local
    if vec.length < 1.0e-6:
        vec = chest.tail_local - pelvis.head_local
    if vec.length < 1.0e-6:
        return None
    return vec.normalized()


def _get_right_dir(armature_obj):
    left_leg = _find_bone(armature_obj, LEFT_LEG_NAMES)
    right_leg = _find_bone(armature_obj, RIGHT_LEG_NAMES)
    if left_leg is None or right_leg is None:
        return None
    vec = right_leg.head_local - left_leg.head_local
    if vec.length < 1.0e-6:
        vec = right_leg.tail_local - left_leg.head_local
    if vec.length < 1.0e-6:
        return None
    return vec.normalized()


def _set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _apply_rotation(obj):
    _set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)


def _get_bound_meshes(armature_obj):
    meshes = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if obj.parent == armature_obj:
            meshes.append(obj)
            continue
        for mod in obj.modifiers:
            if mod.type == "ARMATURE" and mod.object == armature_obj:
                meshes.append(obj)
                break
    return meshes


def _serialize_armature_modifier(obj, mod):
    props = {}
    for key in [
        "use_vertex_groups",
        "use_bone_envelopes",
        "use_deform_preserve_volume",
        "use_multi_modifier",
    ]:
        if hasattr(mod, key):
            props[key] = getattr(mod, key)
    return {
        "name": mod.name,
        "index": list(obj.modifiers).index(mod),
        "props": props,
    }


def _detach_meshes(armature_obj):
    meshes = _get_bound_meshes(armature_obj)
    entries = []
    for mesh in meshes:
        info = {
            "obj": mesh,
            "world": mesh.matrix_world.copy(),
            "parent": mesh.parent,
            "parent_type": mesh.parent_type,
            "parent_bone": mesh.parent_bone,
            "parent_inv": mesh.matrix_parent_inverse.copy(),
            "mods": [],
        }
        for mod in list(mesh.modifiers):
            if mod.type == "ARMATURE" and mod.object == armature_obj:
                info["mods"].append(_serialize_armature_modifier(mesh, mod))
                mesh.modifiers.remove(mod)
        mesh.parent = None
        mesh.parent_type = "OBJECT"
        mesh.parent_bone = ""
        mesh.matrix_parent_inverse = Matrix.Identity(4)
        mesh.matrix_world = info["world"]
        entries.append(info)
    return entries


def _restore_meshes(entries, armature_obj):
    for info in entries:
        mesh = info.get("obj")
        if mesh is None or mesh.type != "MESH":
            continue
        if info.get("parent") is not None:
            mesh.parent = info.get("parent")
            mesh.parent_type = info.get("parent_type")
            mesh.parent_bone = info.get("parent_bone")
            mesh.matrix_parent_inverse = info.get("parent_inv")
        for mod_info in info.get("mods", []):
            new_mod = mesh.modifiers.new(mod_info.get("name", "Armature"), "ARMATURE")
            new_mod.object = armature_obj
            for key, value in mod_info.get("props", {}).items():
                if hasattr(new_mod, key):
                    setattr(new_mod, key, value)
            target_index = mod_info.get("index")
            if target_index is not None and hasattr(mesh.modifiers, "move"):
                try:
                    mesh.modifiers.move(len(mesh.modifiers) - 1, target_index)
                except Exception:
                    pass
        mesh.matrix_world = info.get("world")
        if APPLY_MESH_TRANSFORMS:
            _apply_rotation(mesh)


def _flip_armature_if_needed(obj):
    up_local = _get_up_dir(obj)
    if up_local is None:
        print(f"[fix] {obj.name}: missing pelvis/chest bones")
        return False
    up_world = (obj.matrix_world.to_3x3() @ up_local).normalized()
    dot = up_world.dot(WORLD_UP)
    if dot >= 0.0:
        print(f"[fix] {obj.name}: up looks ok (dot={dot:.3f})")
        return False
    axis_local = _get_right_dir(obj)
    if axis_local is None:
        axis_local = Vector((1.0, 0.0, 0.0))
    rot_local = Matrix.Rotation(math.pi, 4, axis_local)
    old_world = obj.matrix_world.copy()
    new_world = old_world @ rot_local
    delta = new_world @ old_world.inverted()
    relink = []
    if RELINK_MESHES:
        relink = _detach_meshes(obj)
    obj.matrix_world = new_world
    meshes = _get_bound_meshes(obj) if ROTATE_BOUND_MESHES else []
    if not RELINK_MESHES:
        for mesh in meshes:
            mesh.matrix_world = delta @ mesh.matrix_world
    if APPLY_TRANSFORMS:
        _apply_rotation(obj)
        if not RELINK_MESHES:
            for mesh in meshes:
                _apply_rotation(mesh)
    if RELINK_MESHES:
        _restore_meshes(relink, obj)
    print(f"[fix] {obj.name}: flipped (dot={dot:.3f})")
    return True


def main():
    _ensure_blender_imports()
    if bpy.ops.object.mode_set.poll():
        bpy.ops.object.mode_set(mode="OBJECT")
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not armatures:
        print("[fix] No armatures found")
        return
    flipped = 0
    for obj in armatures:
        if _flip_armature_if_needed(obj):
            flipped += 1
    print(f"[fix] Done. Flipped {flipped} armature(s).")


if __name__ == "__main__":
    main()
