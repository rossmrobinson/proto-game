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
