shader_type canvas_item;
// SensationScreenFX — edge glow, tunnel vision, pain pulse, O₂ desaturation.
// Driven by uniforms set from GDScript every frame.

// ── Edge Glow (per-region, 8 zones) ────────────────────────────────────────
// Each zone: top-left, top, top-right, left, right, bottom-left, bottom, bottom-right
// intensity 0..1, pulsing 0..1 (modulates over time)
uniform float glow_top_left      : hint_range(0.0, 1.0) = 0.0;
uniform float glow_top           : hint_range(0.0, 1.0) = 0.0;
uniform float glow_top_right     : hint_range(0.0, 1.0) = 0.0;
uniform float glow_left          : hint_range(0.0, 1.0) = 0.0;
uniform float glow_right         : hint_range(0.0, 1.0) = 0.0;
uniform float glow_bottom_left   : hint_range(0.0, 1.0) = 0.0;
uniform float glow_bottom        : hint_range(0.0, 1.0) = 0.0;
uniform float glow_bottom_right  : hint_range(0.0, 1.0) = 0.0;

// Glow colour per region (default warm skin-touch tone)
uniform vec3 glow_color : source_color = vec3(1.0, 0.85, 0.65);

// ── Genital / Bottom Edge Arousal Color ────────────────────────────────────
// Overrides bottom glow color: blue(cold) → pink(warm) → red(peak)
uniform vec3 arousal_glow_color : source_color = vec3(1.0, 0.4, 0.6);
// 0..1 arousal level — blends bottom color from default to arousal color
uniform float arousal_level      : hint_range(0.0, 1.0) = 0.0;
// Genital pulse phase (0–1 cyclic, from throb system)
uniform float genital_pulse      : hint_range(0.0, 1.0) = 0.0;
// Whether genitals are actively throbbing (enables sine pulse)
uniform float genital_pulse_active : hint_range(0.0, 1.0) = 0.0;

// ── Tunnel Vision ──────────────────────────────────────────────────────────
// 0 = clear, 1 = maximum tunnel (only centre visible)
uniform float tunnel_intensity   : hint_range(0.0, 1.0) = 0.0;

// ── Pain Overlay ───────────────────────────────────────────────────────────
// Red edge pulse. 0 = none, 1 = full pain border.
uniform float pain_level         : hint_range(0.0, 1.0) = 0.0;
uniform float pain_pulse_phase   : hint_range(0.0, 1.0) = 0.0;

// ── Oxygen Desaturation ────────────────────────────────────────────────────
// 1 = full colour, 0 = fully desaturated (greyscale)
uniform float oxygen_saturation  : hint_range(0.0, 1.0) = 1.0;

// ── Glow Geometry ──────────────────────────────────────────────────────────
// How far inward the glow extends from screen edge (fraction of screen)
uniform float glow_width : hint_range(0.01, 0.25) = 0.12;
// Softness of glow falloff
uniform float glow_softness : hint_range(0.5, 5.0) = 2.5;


// Computes edge proximity: 0 at centre, 1 at edge, per direction.
// Returns vec4(left, right, top, bottom) each 0..1.
vec4 edge_factors(vec2 uv) {
    float left   = 1.0 - smoothstep(0.0, glow_width, uv.x);
    float right  = 1.0 - smoothstep(0.0, glow_width, 1.0 - uv.x);
    float top    = 1.0 - smoothstep(0.0, glow_width, uv.y);
    float bottom = 1.0 - smoothstep(0.0, glow_width, 1.0 - uv.y);
    return vec4(left, right, top, bottom);
}


void fragment() {
    vec2 uv = UV;
    vec4 ef = edge_factors(uv);

    // ── Sensation Edge Glow ────────────────────────────────────────────
    // Combine 8 zone intensities with edge proximity masks.
    // Corner zones use product of two edges; edge zones use single edge.
    float top_left_mask  = ef.x * ef.z;              // left × top
    float top_mask       = ef.z * (1.0 - ef.x) * (1.0 - ef.y); // top only (not corners)
    float top_right_mask = ef.y * ef.z;              // right × top
    float left_mask      = ef.x * (1.0 - ef.z) * (1.0 - ef.w); // left only
    float right_mask     = ef.y * (1.0 - ef.z) * (1.0 - ef.w); // right only
    float bot_left_mask  = ef.x * ef.w;              // left × bottom
    float bot_mask       = ef.w * (1.0 - ef.x) * (1.0 - ef.y); // bottom only
    float bot_right_mask = ef.y * ef.w;              // right × bottom

    float glow_accum = 0.0;
    glow_accum += top_left_mask  * glow_top_left;
    glow_accum += top_mask       * glow_top;
    glow_accum += top_right_mask * glow_top_right;
    glow_accum += left_mask      * glow_left;
    glow_accum += right_mask     * glow_right;
    glow_accum += bot_left_mask  * glow_bottom_left;
    glow_accum += bot_mask       * glow_bottom;
    glow_accum += bot_right_mask * glow_bottom_right;
    glow_accum = clamp(glow_accum, 0.0, 1.0);

    // Raise to power for soft falloff
    glow_accum = pow(glow_accum, 1.0 / glow_softness);

    // Bottom edge colour: blend between normal glow and arousal colour
    float bottom_region = ef.w;  // how close to bottom edge
    vec3 bottom_color = mix(glow_color, arousal_glow_color, arousal_level);
    // Genital pulse modulation (sine throb)
    float pulse_mod = 1.0 + genital_pulse_active * sin(genital_pulse * 6.2832) * 0.4;
    bottom_color *= pulse_mod;

    // Final glow colour: blend bottom arousal colour into bottom areas
    vec3 final_glow_color = mix(glow_color, bottom_color, bottom_region);

    // ── Pain Pulse Overlay ─────────────────────────────────────────────
    float any_edge = max(max(ef.x, ef.y), max(ef.z, ef.w));
    float pain_pulse_val = 0.5 + 0.5 * sin(pain_pulse_phase * 6.2832);
    float pain_glow = any_edge * pain_level * pain_pulse_val;
    vec3 pain_color = vec3(0.9, 0.1, 0.05);

    // ── Combine Edge Glows ─────────────────────────────────────────────
    vec3 edge_color = final_glow_color * glow_accum + pain_color * pain_glow;
    float edge_alpha = clamp(glow_accum + pain_glow, 0.0, 1.0);

    // ── Tunnel Vision Vignette ─────────────────────────────────────────
    vec2 centre = uv - vec2(0.5);
    float dist = length(centre) * 2.0;  // 0 at centre, ~1.41 at corners
    // tunnel_intensity controls how far in the darkness reaches
    // At 0: no effect. At 1: only very centre is visible.
    float vignette_start = mix(1.2, 0.25, tunnel_intensity);
    float vignette_end   = mix(1.5, 0.6, tunnel_intensity);
    float vignette = smoothstep(vignette_start, vignette_end, dist);
    // Darken + slight warm tint in tunnel region
    vec3 tunnel_color = vec3(0.02, 0.01, 0.0);

    // ── Oxygen Desaturation ────────────────────────────────────────────
    // Applied as a colour transform hint — the actual scene behind uses
    // screen texture, but since we're an overlay we encode desat as a
    // grey tint overlay.  oxygen_saturation < 1 → overlay grey.
    float desat_amount = 1.0 - oxygen_saturation;
    vec3 desat_overlay = vec3(0.3, 0.3, 0.32);  // cool grey

    // ── Composite ──────────────────────────────────────────────────────
    vec3 final_color = edge_color;
    float final_alpha = edge_alpha * 0.6;  // edge glow semi-transparent

    // Add tunnel vignette darkness
    final_color = mix(final_color, tunnel_color, vignette * 0.9);
    final_alpha = max(final_alpha, vignette * 0.95);

    // Add desaturation overlay
    final_color = mix(final_color, desat_overlay, desat_amount * 0.7);
    final_alpha = max(final_alpha, desat_amount * 0.5);

    COLOR = vec4(final_color, final_alpha);
}
