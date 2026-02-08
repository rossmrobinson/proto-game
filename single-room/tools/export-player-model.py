"""
Export Player1 from room1-models.blend as a standalone .glb for Godot.

HOW TO USE:
  1. Open Blender
  2. File → Open → J:\proto-game\single-room\assets\models\room1-models.blend
  3. Switch to the Scripting workspace (top tab bar)
  4. Click "New" to create a new text block
  5. Paste this entire script
  6. Click the ▶ Run Script button (or Alt+P)
  7. Output: J:\proto-game\single-room\assets\models\player1.glb

WHAT IT DOES:
  - Finds the "Player1" armature in the scene
  - Duplicates it (leaves original untouched)
  - Moves the duplicate to world origin (0,0,0)
  - Applies all transforms so the mesh is clean
  - Clears all animations and NLA strips
  - Exports as .glb with correct Godot orientation (+Y up, -Z forward)
  - Deletes the duplicate, restoring the original scene
"""

import bpy
import os

# ── CONFIG ───────────────────────────────────────────────────────────────────
ARMATURE_NAME = "Player1"
OUTPUT_DIR = r"J:\proto-game\single-room\assets\models"
OUTPUT_FILE = "player1.glb"
# ─────────────────────────────────────────────────────────────────────────────


def find_armature(name: str):
    """Find an armature object whose name contains the target."""
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and name.lower() in obj.name.lower():
            return obj
    return None


def get_mesh_children(armature):
    """Get all mesh objects parented to the armature."""
    return [c for c in armature.children if c.type == "MESH"]


def clear_animations(armature):
    """Remove all animation data, actions, and NLA tracks."""
    # Clear armature action
    if armature.animation_data:
        armature.animation_data.action = None
        # Remove NLA tracks
        if armature.animation_data.nla_tracks:
            for track in list(armature.animation_data.nla_tracks):
                armature.animation_data.nla_tracks.remove(track)
        bpy.data.objects[armature.name].animation_data_clear()

    # Clear mesh children actions
    for mesh_obj in get_mesh_children(armature):
        if mesh_obj.animation_data:
            mesh_obj.animation_data.action = None
            if mesh_obj.animation_data.nla_tracks:
                for track in list(mesh_obj.animation_data.nla_tracks):
                    mesh_obj.animation_data.nla_tracks.remove(track)
            mesh_obj.animation_data_clear()


def main():
    print("\n" + "=" * 60)
    print("  Export Player Model for Godot")
    print("=" * 60)

    # Find the armature
    armature = find_armature(ARMATURE_NAME)
    if armature is None:
        print(f"ERROR: No armature containing '{ARMATURE_NAME}' found!")
        print(f"  Available armatures: {[o.name for o in bpy.data.objects if o.type == 'ARMATURE']}")
        return

    print(f"  Found: {armature.name}")
    meshes = get_mesh_children(armature)
    print(f"  Mesh children: {[m.name for m in meshes]}")

    # Deselect everything
    bpy.ops.object.select_all(action="DESELECT")

    # Select the armature and its mesh children
    armature.select_set(True)
    for mesh_obj in meshes:
        mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = armature

    # Duplicate
    bpy.ops.object.duplicate()
    dup_armature = bpy.context.active_object
    dup_meshes = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    print(f"  Duplicated as: {dup_armature.name}")

    # Move to world origin
    dup_armature.location = (0, 0, 0)
    dup_armature.rotation_euler = (0, 0, 0)
    dup_armature.scale = (1, 1, 1)

    # Apply transforms on the duplicate
    bpy.ops.object.select_all(action="DESELECT")
    dup_armature.select_set(True)
    for m in dup_meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = dup_armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Clear animations
    clear_animations(dup_armature)
    print("  Animations cleared")

    # Reset pose (T-pose / rest pose)
    bpy.context.view_layer.objects.active = dup_armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")
    print("  Pose reset to rest")

    # Select only the duplicate for export
    bpy.ops.object.select_all(action="DESELECT")
    dup_armature.select_set(True)
    for m in dup_meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = dup_armature

    # Export
    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_animations=False,
        export_skins=True,
        export_yup=True,  # Godot expects +Y up
    )

    print(f"  Exported: {output_path}")

    # Clean up — delete the duplicates
    bpy.ops.object.select_all(action="DESELECT")
    dup_armature.select_set(True)
    for m in dup_meshes:
        m.select_set(True)
    bpy.ops.object.delete()

    print("  Duplicates cleaned up")
    print("=" * 60)
    print("  DONE! Import player1.glb in Godot and set the export path")
    print("  in the Player node's 'player_model_path' to:")
    print("    res://assets/models/player1.glb")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
