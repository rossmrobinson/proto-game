"""
Blender → Godot 4 Scene Setup Script
=====================================
Run this inside Blender (Text Editor → Open → Run Script, or paste into console).

What this does:
  1. Configures scene units for Godot (1 unit = 1 meter)
  2. Sets color management for PBR/sRGB compatibility
  3. Configures render settings optimized for asset preview on GTX 1070
  4. Sets up glTF export preferences
  5. Creates a PBR material template you can duplicate for new objects
  6. Configures armature settings for game-ready skeleton export
  7. Adds custom properties for Godot collision mesh suffixes

Run once per new .blend file, or save as a startup template.
"""

import bpy
import math


# ══════════════════════════════════════════════════════════════════════════════
#  1. SCENE UNITS & SCALE
# ══════════════════════════════════════════════════════════════════════════════

def setup_units():
    """Configure scene to match Godot's coordinate system."""
    scene = bpy.context.scene

    # Godot uses meters. Set Blender to match.
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = 'METERS'

    # Grid scale for viewport
    # In Blender 4.x, grid settings are per-3D viewport
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.overlay.grid_scale = 1.0
                    space.clip_start = 0.01
                    space.clip_end = 1000.0

    print("[Setup] Units: Metric, 1 unit = 1 meter")


# ══════════════════════════════════════════════════════════════════════════════
#  2. COLOR MANAGEMENT (sRGB for Godot PBR)
# ══════════════════════════════════════════════════════════════════════════════

def setup_color_management():
    """Configure color management for PBR-correct rendering and export."""
    scene = bpy.context.scene

    # Standard sRGB for Godot compatibility
    scene.display_settings.display_device = 'sRGB'

    # Use Standard view transform for WYSIWYG with Godot
    # (AgX/Filmic in Blender change the look; Standard matches what Godot sees)
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    # Sequencer color space
    scene.sequencer_colorspace_settings.name = 'sRGB'

    print("[Setup] Color management: sRGB / Standard (matches Godot)")


# ══════════════════════════════════════════════════════════════════════════════
#  3. RENDER SETTINGS (Preview optimization for GTX 1070)
# ══════════════════════════════════════════════════════════════════════════════

def setup_render_settings():
    """Configure Cycles/EEVEE for efficient asset preview."""
    scene = bpy.context.scene

    # ── EEVEE (fast viewport preview, similar to Godot Forward+) ──────────
    # Use EEVEE as the primary render engine for preview — it's closest to
    # what you'll see in Godot's Forward+ renderer.
    scene.render.engine = 'BLENDER_EEVEE_NEXT'

    # Resolution matching Godot target
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100

    # EEVEE settings that approximate Godot Forward+
    eevee = scene.eevee
    eevee.taa_render_samples = 64
    eevee.taa_samples = 16

    # Enable screen space effects similar to our Godot setup
    # Note: EEVEE Next always enables SSAO — no manual toggle needed.

    # ── Cycles (for baking high-quality normal maps, AO maps) ─────────────
    cycles = scene.cycles if hasattr(scene, 'cycles') else None
    if cycles:
        cycles.device = 'GPU'
        cycles.samples = 128          # Enough for clean bakes
        cycles.preview_samples = 32
        cycles.use_denoising = True
        cycles.use_adaptive_sampling = True
        cycles.adaptive_threshold = 0.01

    # ── Output settings for texture baking ────────────────────────────────
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 15

    print("[Setup] Render: EEVEE Next (preview) + Cycles GPU (baking)")


# ══════════════════════════════════════════════════════════════════════════════
#  4. TEXTURE DEFAULTS
# ══════════════════════════════════════════════════════════════════════════════

def setup_texture_defaults():
    """Set sane defaults for texture creation.

    For GTX 1070 (8GB VRAM) at 1080p:
      - Characters:  2048x2048 (albedo, normal, ORM)
      - Props:       1024x1024
      - Environment: 2048x2048 or 1024x1024 for tiling
      - Tiny objects: 512x512

    Use ORM packing: R=Occlusion, G=Roughness, B=Metallic
    This cuts texture count per material from 5 to 3.
    """
    # Store as custom scene properties for reference
    scene = bpy.context.scene
    scene["godot_tex_character"] = "2048x2048"
    scene["godot_tex_props"] = "1024x1024"
    scene["godot_tex_environment"] = "2048x2048"
    scene["godot_tex_small"] = "512x512"
    scene["godot_orm_packing"] = "R=AO, G=Roughness, B=Metallic"

    print("[Setup] Texture size guidelines saved as scene custom properties")
    print("  Characters:  2048x2048")
    print("  Props:       1024x1024")
    print("  Environment: 2048x2048")
    print("  Small items: 512x512")
    print("  ORM packing: R=AO, G=Roughness, B=Metallic")


# ══════════════════════════════════════════════════════════════════════════════
#  5. PBR MATERIAL TEMPLATE
# ══════════════════════════════════════════════════════════════════════════════

def create_pbr_template_material():
    """Create a reusable PBR material node setup that exports cleanly to glTF/Godot.

    The material uses a Principled BSDF with:
      - Albedo (Base Color) texture input
      - Normal Map texture input
      - ORM packed texture input (split into AO, Roughness, Metallic)

    Duplicate this material for each new asset.
    """
    mat_name = "GodotPBR_Template"

    # Don't recreate if it exists
    if mat_name in bpy.data.materials:
        print(f"[Setup] Material '{mat_name}' already exists, skipping")
        return bpy.data.materials[mat_name]

    mat = bpy.data.materials.new(name=mat_name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    # Clear default nodes
    nodes.clear()

    # ── Output ────────────────────────────────────────────────────────────
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (600, 0)

    # ── Principled BSDF ──────────────────────────────────────────────────
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (200, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

    # ── Albedo Texture ───────────────────────────────────────────────────
    albedo_tex = nodes.new('ShaderNodeTexImage')
    albedo_tex.name = "Albedo"
    albedo_tex.label = "Albedo (Base Color)"
    albedo_tex.location = (-500, 300)
    links.new(albedo_tex.outputs['Color'], bsdf.inputs['Base Color'])

    # ── Normal Map ───────────────────────────────────────────────────────
    normal_tex = nodes.new('ShaderNodeTexImage')
    normal_tex.name = "NormalMap"
    normal_tex.label = "Normal Map"
    normal_tex.location = (-500, -100)

    normal_map = nodes.new('ShaderNodeNormalMap')
    normal_map.location = (-100, -100)
    links.new(normal_tex.outputs['Color'], normal_map.inputs['Color'])
    links.new(normal_map.outputs['Normal'], bsdf.inputs['Normal'])

    # Normal maps must be Non-Color to avoid sRGB double-correction
    normal_tex.image_user.use_auto_refresh = True  # harmless default
    # The colorspace is set on the Image data, not the node — it can only be
    # assigned after a texture is loaded. Tag the node so a helper can fix it.
    normal_tex["colorspace_hint"] = "Non-Color"

    # ── ORM Packed Texture ───────────────────────────────────────────────
    orm_tex = nodes.new('ShaderNodeTexImage')
    orm_tex.name = "ORM"
    orm_tex.label = "ORM (AO/Rough/Metal)"
    orm_tex.location = (-500, -500)

    # Separate RGB to split ORM channels
    sep_rgb = nodes.new('ShaderNodeSeparateColor')
    sep_rgb.location = (-200, -500)
    links.new(orm_tex.outputs['Color'], sep_rgb.inputs['Color'])

    # R = Ambient Occlusion (not directly in Principled BSDF, but glTF uses it)
    # For now, multiply AO with albedo for viewport preview
    # Blender 4.x: ShaderNodeMixRGB was removed; use ShaderNodeMix instead.
    mix_ao = nodes.new('ShaderNodeMix')
    mix_ao.data_type = 'RGBA'
    mix_ao.blend_type = 'MULTIPLY'
    mix_ao.inputs['Factor'].default_value = 1.0
    mix_ao.location = (-100, 300)
    links.new(albedo_tex.outputs['Color'], mix_ao.inputs['A'])
    links.new(sep_rgb.outputs['Red'], mix_ao.inputs['B'])
    # Reconnect albedo through AO multiply
    links.new(mix_ao.outputs['Result'], bsdf.inputs['Base Color'])

    # G = Roughness
    links.new(sep_rgb.outputs['Green'], bsdf.inputs['Roughness'])

    # B = Metallic
    links.new(sep_rgb.outputs['Blue'], bsdf.inputs['Metallic'])

    # ── UV Map ───────────────────────────────────────────────────────────
    uv_map = nodes.new('ShaderNodeUVMap')
    uv_map.location = (-800, 0)
    links.new(uv_map.outputs['UV'], albedo_tex.inputs['Vector'])
    links.new(uv_map.outputs['UV'], normal_tex.inputs['Vector'])
    links.new(uv_map.outputs['UV'], orm_tex.inputs['Vector'])

    print(f"[Setup] Created PBR template material: '{mat_name}'")
    print("  Inputs: Albedo, Normal Map, ORM (R=AO, G=Rough, B=Metal)")
    print("  Duplicate this material for each new object")

    return mat


# ══════════════════════════════════════════════════════════════════════════════
#  6. ARMATURE / SKELETON SETTINGS
# ══════════════════════════════════════════════════════════════════════════════

def setup_armature_defaults():
    """Configure default armature settings for game-ready skeleton export.

    Bones should follow Godot naming conventions:
      - Use snake_case for bone names (e.g., left_upper_arm)
      - Root bone should be named 'root' or 'pelvis'
      - Suffix collision meshes with '-col' for auto-import in Godot
      - Keep bone rolls consistent (local Y along bone, Z forward)
    """
    # Store naming conventions as scene properties
    scene = bpy.context.scene
    scene["godot_bone_convention"] = "snake_case"
    scene["godot_collision_suffix"] = "-col"
    scene["godot_root_bone"] = "pelvis"

    print("[Setup] Armature conventions:")
    print("  Bone naming:     snake_case (e.g., left_upper_arm)")
    print("  Collision suffix: -col (auto-detected by Godot importer)")
    print("  Root bone:       'pelvis' or 'root'")


# ══════════════════════════════════════════════════════════════════════════════
#  7. EXPORT PRESETS (glTF 2.0)
# ══════════════════════════════════════════════════════════════════════════════

def print_export_guide():
    """Print the recommended glTF export settings to the console.

    Note: Blender Python API doesn't support saving export presets
    programmatically. These settings should be used when exporting via
    File → Export → glTF 2.0.
    """
    guide = """
╔══════════════════════════════════════════════════════════════╗
║            glTF 2.0 Export Settings for Godot 4             ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  Format:     glTF Binary (.glb)                              ║
║  Copyright:  (your name)                                     ║
║                                                              ║
║  ── Include ──────────────────────────────────────────────   ║
║  ☑ Selected Objects (when exporting single assets)           ║
║  ☑ Custom Properties                                         ║
║                                                              ║
║  ── Transform ────────────────────────────────────────────   ║
║  Y Up:  ☑ (Godot uses Y-up)                                 ║
║                                                              ║
║  ── Mesh ─────────────────────────────────────────────────   ║
║  ☑ Apply Modifiers                                           ║
║  ☑ UVs                                                       ║
║  ☑ Normals                                                   ║
║  ☑ Tangents (needed for normal maps)                         ║
║  ☑ Vertex Colors (if used)                                   ║
║  ☐ Loose Edges / Points (disable to reduce size)             ║
║  Compression: ☑ Draco (reduces file size ~60-80%)            ║
║                                                              ║
║  ── Material ─────────────────────────────────────────────   ║
║  ☑ Export Materials                                          ║
║  Images: Automatic (embeds in .glb)                          ║
║                                                              ║
║  ── Armature ─────────────────────────────────────────────   ║
║  ☑ Export Armatures                                          ║
║  ☑ Export Deformation Bones Only (important for performance) ║
║  ☐ Export All Bone Influences (unless >4 weights needed)     ║
║                                                              ║
║  ── Animation ────────────────────────────────────────────   ║
║  ☑ Export Animations                                         ║
║  ☑ Group By NLA Track                                        ║
║  ☑ Optimize Animation Size                                   ║
║  Sampling Rate: 24 (or match your animation FPS)             ║
║                                                              ║
║  ── Alternative: Just use .blend files directly! ──────────  ║
║  Godot 4 can import .blend files natively if Blender is      ║
║  installed. Just save the .blend into your Godot project's   ║
║  assets/models/ folder and Godot auto-converts it.           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"""
    print(guide)


# ══════════════════════════════════════════════════════════════════════════════
#  8. VIEWPORT SETUP
# ══════════════════════════════════════════════════════════════════════════════

def setup_viewport():
    """Configure 3D viewport for game asset workflow."""
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    # Material preview mode (closest to Godot's look)
                    space.shading.type = 'MATERIAL'
                    space.shading.use_scene_lights = True
                    space.shading.use_scene_world = False

                    # Studio lighting for consistent material preview
                    space.shading.studio_light = 'studio.exr'

                    # Show backface culling (Godot culls backfaces by default)
                    space.shading.show_backface_culling = True

                    # Overlay settings
                    space.overlay.show_floor = True
                    space.overlay.show_axis_x = True
                    space.overlay.show_axis_y = True
                    space.overlay.show_axis_z = False
                    space.overlay.show_wireframes = False

    print("[Setup] Viewport: Material Preview with backface culling")


# ══════════════════════════════════════════════════════════════════════════════
#  9. CLEAN DEFAULT SCENE
# ══════════════════════════════════════════════════════════════════════════════

def clean_default_scene():
    """Remove default cube, camera, and light. Add a ground plane."""
    # Remove default objects
    for obj_name in ["Cube", "Camera", "Light"]:
        if obj_name in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[obj_name], do_unlink=True)

    # Add a 10x10m ground plane as reference (matches our Godot greybox room)
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "GroundPlane_Reference"
    ground.display_type = 'WIRE'  # Wireframe so it doesn't obscure anything

    # Add an area light for material preview
    bpy.ops.object.light_add(type='AREA', location=(0, 0, 3))
    light = bpy.context.active_object
    light.name = "PreviewLight"
    light.data.energy = 100.0
    light.data.size = 4.0
    light.data.color = (1.0, 0.95, 0.85)

    print("[Setup] Cleaned scene: removed defaults, added reference ground plane")


# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    print("\n" + "=" * 60)
    print("  Blender → Godot 4 Scene Setup")
    print("  Target: GTX 1070 / 1080p / Forward+")
    print("=" * 60 + "\n")

    setup_units()
    setup_color_management()
    setup_render_settings()
    setup_texture_defaults()
    create_pbr_template_material()
    setup_armature_defaults()
    setup_viewport()
    clean_default_scene()
    print_export_guide()

    print("\n" + "=" * 60)
    print("  Setup complete!")
    print("  • Duplicate 'GodotPBR_Template' material for each object")
    print("  • Use -col suffix on collision meshes")
    print("  • Save .blend directly into Godot's assets/models/ folder")
    print("  • Or export as .glb with the settings shown above")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
