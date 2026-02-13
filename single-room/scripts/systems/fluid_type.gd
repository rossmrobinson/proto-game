class_name FluidType
extends Resource
## Defines the visual and physical properties of a bodily fluid.
## Used by BodyFluidEmitter to configure particle behavior.

@export var fluid_name: String = ""
@export var category: String = ""

@export_group("Appearance")
@export var color: Color = Color(1.0, 1.0, 1.0, 0.8)
## Secondary color for variation/gradient (e.g., blood darkens as it dries).
@export var color_secondary: Color = Color(1.0, 1.0, 1.0, 0.5)
@export_range(0.001, 0.05) var particle_radius: float = 0.008
## How opaque the fluid is (0 = transparent like sweat, 1 = opaque like blood).
@export_range(0.0, 1.0) var opacity: float = 0.7
## Emission intensity for glowing fluids (bile, bioluminescent edge cases). Usually 0.
@export_range(0.0, 2.0) var emission_energy: float = 0.0
## Metallic sheen (saliva has slight sheen, blood does not).
@export_range(0.0, 1.0) var metallic: float = 0.0
## Surface roughness (lower = shinier/wetter look).
@export_range(0.0, 1.0) var roughness: float = 0.2

@export_group("Physics")
## How thick the fluid is. Affects drip speed, spread, and splat behavior.
## 0 = water-thin (sweat, urine), 1 = extremely thick (mucus, semen).
@export_range(0.0, 1.0) var viscosity: float = 0.1
## How strongly particles stick to surfaces on contact.
@export_range(0.0, 1.0) var surface_adhesion: float = 0.3
## Gravity multiplier. <1 for thick drips that cling, >1 for heavy splashes.
@export_range(0.1, 3.0) var gravity_scale: float = 1.0
## Base velocity when emitted (meters/sec). Spray vs ooze.
@export_range(0.0, 5.0) var emission_speed: float = 0.5
## Random spread angle (degrees). 0 = focused stream, 90 = wide spray.
@export_range(0.0, 90.0) var spread_angle: float = 15.0

@export_group("Lifetime")
## How long particles live (seconds) before fading.
@export_range(0.5, 30.0) var lifetime: float = 5.0
## How long surface puddles/splatters persist (seconds). 0 = no persistence.
@export_range(0.0, 120.0) var surface_lifetime: float = 30.0
## Rate at which opacity fades over lifetime (simulates drying/absorption).
@export_range(0.0, 1.0) var dry_rate: float = 0.1

@export_group("Behavior")
## Whether this fluid drips (forms droplets that fall).
@export var can_drip: bool = true
## Whether this fluid can pool on surfaces.
@export var can_pool: bool = true
## Whether this fluid leaves streaks/trails when flowing over surfaces.
@export var can_streak: bool = true
## Whether this fluid creates splash sub-particles on impact.
@export var can_splash: bool = true
## Volume of drip sounds (0 = silent, 1 = full).
@export_range(0.0, 1.0) var sound_volume: float = 0.3

@export_group("String Forming")
## Whether this fluid can form viscous threads between separating surfaces.
@export var can_form_strings: bool = false
## Maximum length (metres) a string can stretch before breaking.
@export_range(0.01, 0.5) var string_max_length: float = 0.15
## Minimum viscosity at which strings form (thinner fluids can't string).
@export_range(0.0, 1.0) var string_viscosity_threshold: float = 0.2

@export_group("Mixing")
## How readily this fluid blends when combined with another.
## 0 = immiscible (oil-in-water beading), 1 = instant blend.
@export_range(0.0, 1.0) var miscibility: float = 0.5


static func create(p_name: String, p_category: String, overrides: Dictionary = {}) -> FluidType:
	var ft: FluidType = FluidType.new()
	ft.fluid_name = p_name
	ft.category = p_category
	for key: String in overrides:
		if key in ft:
			ft.set(key, overrides[key])
		else:
			push_warning("[FluidType] Unknown property '%s' in overrides for '%s'" % [key, p_name])
	return ft


## Create a blended fluid from two source fluids weighted by volume ratio.
## ratio: 0.0 = 100% fluid_a, 1.0 = 100% fluid_b.
static func mix(fluid_a: FluidType, fluid_b: FluidType, ratio: float) -> FluidType:
	var t: float = clampf(ratio, 0.0, 1.0)
	var mix_quality: float = minf(fluid_a.miscibility, fluid_b.miscibility)
	# Blend factor is dampened by miscibility — immiscible fluids barely mix
	var eff_t: float = lerpf(0.0, t, mix_quality) if t < 0.5 else lerpf(t, 1.0, mix_quality)

	var result: FluidType = FluidType.new()
	result.fluid_name = "%s+%s" % [fluid_a.fluid_name, fluid_b.fluid_name]
	result.category = "mixed"

	# Appearance blends
	result.color = fluid_a.color.lerp(fluid_b.color, eff_t)
	result.color_secondary = fluid_a.color_secondary.lerp(fluid_b.color_secondary, eff_t)
	result.opacity = lerpf(fluid_a.opacity, fluid_b.opacity, eff_t)
	result.metallic = lerpf(fluid_a.metallic, fluid_b.metallic, eff_t)
	result.roughness = lerpf(fluid_a.roughness, fluid_b.roughness, eff_t)
	result.particle_radius = lerpf(fluid_a.particle_radius, fluid_b.particle_radius, eff_t)

	# Physics — viscosity averages but adhesion takes the stickier one
	result.viscosity = lerpf(fluid_a.viscosity, fluid_b.viscosity, eff_t)
	result.surface_adhesion = maxf(
		lerpf(fluid_a.surface_adhesion, fluid_b.surface_adhesion, eff_t),
		maxf(fluid_a.surface_adhesion, fluid_b.surface_adhesion) * 0.7)
	result.gravity_scale = lerpf(fluid_a.gravity_scale, fluid_b.gravity_scale, eff_t)
	result.emission_speed = lerpf(fluid_a.emission_speed, fluid_b.emission_speed, eff_t)
	result.spread_angle = lerpf(fluid_a.spread_angle, fluid_b.spread_angle, eff_t)

	# Lifetime — the longer-lived component dominates
	result.lifetime = maxf(fluid_a.lifetime, fluid_b.lifetime)
	result.surface_lifetime = maxf(fluid_a.surface_lifetime, fluid_b.surface_lifetime)
	result.dry_rate = lerpf(fluid_a.dry_rate, fluid_b.dry_rate, eff_t)

	# Behavior — union of capabilities
	result.can_drip = fluid_a.can_drip or fluid_b.can_drip
	result.can_pool = fluid_a.can_pool or fluid_b.can_pool
	result.can_streak = fluid_a.can_streak or fluid_b.can_streak
	result.can_splash = fluid_a.can_splash or fluid_b.can_splash
	result.sound_volume = maxf(fluid_a.sound_volume, fluid_b.sound_volume)

	# String forming — either source can contribute
	result.can_form_strings = fluid_a.can_form_strings or fluid_b.can_form_strings
	result.string_max_length = maxf(fluid_a.string_max_length, fluid_b.string_max_length)
	result.string_viscosity_threshold = minf(
		fluid_a.string_viscosity_threshold, fluid_b.string_viscosity_threshold)

	result.miscibility = lerpf(fluid_a.miscibility, fluid_b.miscibility, 0.5)

	return result
