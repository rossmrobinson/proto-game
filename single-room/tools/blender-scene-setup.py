import importlib

bpy = None

USE_IMPERIAL_DISPLAY = True
USE_SEPARATE_UNITS = True
LENGTH_UNIT = "FEET"

# Keep 1 Blender unit = 1 meter for Godot scale.
UNIT_SCALE_METERS = 1.0

# Optional: set True if you want 1 Blender unit = 1 foot.
USE_FEET_AS_BU = False

TARGET_FPS = 60
GRAVITY_Z = -9.81

VIEW_CLIP_START = 0.01
VIEW_CLIP_END = 1000.0
GRID_SCALE = 1.0
GRID_SUBDIVISIONS = 10


def _ensure_blender_imports():
    global bpy
    if bpy is not None:
        return
    bpy = importlib.import_module("bpy")


def _apply_scene_settings(scene):
    units = scene.unit_settings
    units.system = "IMPERIAL" if USE_IMPERIAL_DISPLAY else "METRIC"
    units.use_separate = USE_SEPARATE_UNITS
    units.length_unit = LENGTH_UNIT

    if USE_FEET_AS_BU:
        units.scale_length = 0.3048
    else:
        units.scale_length = UNIT_SCALE_METERS

    scene.render.fps = TARGET_FPS
    scene.render.fps_base = 1.0
    scene.gravity = (0.0, 0.0, GRAVITY_Z)


def _apply_viewport_settings():
    wm = bpy.context.window_manager
    for window in wm.windows:
        screen = window.screen
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                space.clip_start = VIEW_CLIP_START
                space.clip_end = VIEW_CLIP_END
                overlay = space.overlay
                overlay.grid_scale = GRID_SCALE
                overlay.grid_subdivisions = GRID_SUBDIVISIONS
                overlay.show_axis_x = True
                overlay.show_axis_y = True
                overlay.show_axis_z = True
                overlay.show_floor = True


def main():
    _ensure_blender_imports()
    for scene in bpy.data.scenes:
        _apply_scene_settings(scene)
    _apply_viewport_settings()
    print("[scene-setup] Done.")
    print(f"[scene-setup] Units: {bpy.context.scene.unit_settings.system}"
          f" | scale_length={bpy.context.scene.unit_settings.scale_length}")


if __name__ == "__main__":
    main()
