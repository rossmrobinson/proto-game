class_name BodyFluidLibrary
extends RefCounted
## Complete library of bodily fluid types with realistic physical properties.
## Call get_all() for the full dictionary or get_fluid("blood") for one.


static func get_all() -> Dictionary:
	return {
		# ── Blood & Circulatory ──────────────────────────────────────────
		"blood": _blood(),
		"blood_arterial": _blood_arterial(),
		"blood_menstrual": _blood_menstrual(),

		# ── Sweat & Skin ────────────────────────────────────────────────
		"sweat": _sweat(),
		"sebum": _sebum(),

		# ── Oral / Respiratory ──────────────────────────────────────────
		"saliva": _saliva(),
		"mucus_nasal": _mucus_nasal(),
		"phlegm": _phlegm(),
		"vomit": _vomit(),

		# ── Ocular ──────────────────────────────────────────────────────
		"tears": _tears(),

		# ── Digestive / Excretory ───────────────────────────────────────
		"urine": _urine(),
		"bile": _bile(),
		"feces_liquid": _feces_liquid(),

		# ── Reproductive ────────────────────────────────────────────────
		"semen": _semen(),
		"pre_ejaculate": _pre_ejaculate(),
		"vaginal_fluid": _vaginal_fluid(),
		"cervical_mucus": _cervical_mucus(),
		"breast_milk": _breast_milk(),

		# ── Wound / Medical ─────────────────────────────────────────────
		"pus": _pus(),
		"lymph": _lymph(),
		"synovial": _synovial(),
	}


static func get_fluid(fluid_name: String) -> FluidType:
	var all: Dictionary = get_all()
	if all.has(fluid_name):
		return all[fluid_name] as FluidType
	push_warning("[BodyFluidLibrary] Unknown fluid: %s" % fluid_name)
	return null


# ── Convenience Accessors ────────────────────────────────────────────────────

static func semen() -> FluidType:
	return _semen()

static func pre_ejaculate() -> FluidType:
	return _pre_ejaculate()

static func vaginal_fluid() -> FluidType:
	return _vaginal_fluid()

static func cervical_mucus() -> FluidType:
	return _cervical_mucus()

static func saliva() -> FluidType:
	return _saliva()

static func sweat() -> FluidType:
	return _sweat()

static func tears() -> FluidType:
	return _tears()

static func blood() -> FluidType:
	return _blood()

static func breast_milk() -> FluidType:
	return _breast_milk()

static func urine() -> FluidType:
	return _urine()


# ── Blood & Circulatory ──────────────────────────────────────────────────────

static func _blood() -> FluidType:
	return FluidType.create("blood", "circulatory", {
		"color": Color(0.55, 0.02, 0.02, 0.95),
		"color_secondary": Color(0.3, 0.01, 0.01, 0.8),
		"viscosity": 0.35,
		"surface_adhesion": 0.7,
		"gravity_scale": 1.1,
		"emission_speed": 0.8,
		"spread_angle": 20.0,
		"lifetime": 8.0,
		"surface_lifetime": 90.0,
		"dry_rate": 0.03,
		"opacity": 0.95,
		"roughness": 0.25,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.4,
	})


static func _blood_arterial() -> FluidType:
	return FluidType.create("blood_arterial", "circulatory", {
		"color": Color(0.7, 0.05, 0.02, 0.95),
		"color_secondary": Color(0.55, 0.02, 0.02, 0.9),
		"viscosity": 0.3,
		"surface_adhesion": 0.65,
		"gravity_scale": 1.0,
		"emission_speed": 3.5,
		"spread_angle": 30.0,
		"lifetime": 6.0,
		"surface_lifetime": 90.0,
		"dry_rate": 0.03,
		"opacity": 0.95,
		"roughness": 0.2,
		"can_splash": true,
		"sound_volume": 0.6,
	})


static func _blood_menstrual() -> FluidType:
	return FluidType.create("blood_menstrual", "circulatory", {
		"color": Color(0.45, 0.02, 0.02, 0.9),
		"color_secondary": Color(0.3, 0.01, 0.01, 0.7),
		"viscosity": 0.5,
		"surface_adhesion": 0.6,
		"gravity_scale": 1.0,
		"emission_speed": 0.2,
		"spread_angle": 10.0,
		"lifetime": 10.0,
		"surface_lifetime": 60.0,
		"dry_rate": 0.04,
		"opacity": 0.9,
		"roughness": 0.3,
		"can_drip": true,
		"can_streak": true,
		"sound_volume": 0.2,
	})


# ── Sweat & Skin ─────────────────────────────────────────────────────────────

static func _sweat() -> FluidType:
	return FluidType.create("sweat", "skin", {
		"color": Color(0.85, 0.88, 0.9, 0.25),
		"color_secondary": Color(0.85, 0.88, 0.9, 0.1),
		"particle_radius": 0.004,
		"viscosity": 0.02,
		"surface_adhesion": 0.15,
		"gravity_scale": 0.8,
		"emission_speed": 0.05,
		"spread_angle": 60.0,
		"lifetime": 4.0,
		"surface_lifetime": 15.0,
		"dry_rate": 0.25,
		"opacity": 0.2,
		"roughness": 0.1,
		"metallic": 0.15,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
	})


static func _sebum() -> FluidType:
	return FluidType.create("sebum", "skin", {
		"color": Color(0.9, 0.85, 0.6, 0.4),
		"color_secondary": Color(0.85, 0.8, 0.55, 0.3),
		"particle_radius": 0.003,
		"viscosity": 0.7,
		"surface_adhesion": 0.8,
		"gravity_scale": 0.5,
		"emission_speed": 0.02,
		"spread_angle": 5.0,
		"lifetime": 20.0,
		"surface_lifetime": 60.0,
		"dry_rate": 0.02,
		"opacity": 0.35,
		"roughness": 0.15,
		"metallic": 0.2,
		"can_drip": false,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.0,
	})


# ── Oral / Respiratory ───────────────────────────────────────────────────────

static func _saliva() -> FluidType:
	return FluidType.create("saliva", "oral", {
		"color": Color(0.9, 0.92, 0.95, 0.5),
		"color_secondary": Color(0.85, 0.88, 0.9, 0.3),
		"viscosity": 0.15,
		"surface_adhesion": 0.3,
		"gravity_scale": 1.0,
		"emission_speed": 0.6,
		"spread_angle": 15.0,
		"lifetime": 5.0,
		"surface_lifetime": 20.0,
		"dry_rate": 0.15,
		"opacity": 0.45,
		"roughness": 0.12,
		"metallic": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.2,
		"can_form_strings": true,
		"string_max_length": 0.12,
		"string_viscosity_threshold": 0.1,
		"miscibility": 0.7,
	})


static func _mucus_nasal() -> FluidType:
	return FluidType.create("mucus_nasal", "respiratory", {
		"color": Color(0.7, 0.82, 0.5, 0.7),
		"color_secondary": Color(0.6, 0.75, 0.4, 0.5),
		"viscosity": 0.75,
		"surface_adhesion": 0.85,
		"gravity_scale": 0.6,
		"emission_speed": 0.3,
		"spread_angle": 10.0,
		"lifetime": 12.0,
		"surface_lifetime": 45.0,
		"dry_rate": 0.05,
		"opacity": 0.7,
		"roughness": 0.3,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.15,
	})


static func _phlegm() -> FluidType:
	return FluidType.create("phlegm", "respiratory", {
		"color": Color(0.65, 0.75, 0.45, 0.8),
		"color_secondary": Color(0.5, 0.6, 0.35, 0.6),
		"viscosity": 0.85,
		"surface_adhesion": 0.9,
		"gravity_scale": 0.5,
		"emission_speed": 1.5,
		"spread_angle": 25.0,
		"lifetime": 10.0,
		"surface_lifetime": 40.0,
		"dry_rate": 0.06,
		"opacity": 0.75,
		"roughness": 0.35,
		"can_drip": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.3,
	})


static func _vomit() -> FluidType:
	return FluidType.create("vomit", "digestive", {
		"color": Color(0.65, 0.55, 0.25, 0.9),
		"color_secondary": Color(0.5, 0.4, 0.2, 0.7),
		"particle_radius": 0.015,
		"viscosity": 0.55,
		"surface_adhesion": 0.5,
		"gravity_scale": 1.3,
		"emission_speed": 3.0,
		"spread_angle": 35.0,
		"lifetime": 10.0,
		"surface_lifetime": 60.0,
		"dry_rate": 0.05,
		"opacity": 0.9,
		"roughness": 0.4,
		"can_drip": true,
		"can_pool": true,
		"can_splash": true,
		"sound_volume": 0.7,
	})


# ── Ocular ───────────────────────────────────────────────────────────────────

static func _tears() -> FluidType:
	return FluidType.create("tears", "ocular", {
		"color": Color(0.9, 0.93, 0.97, 0.3),
		"color_secondary": Color(0.9, 0.93, 0.97, 0.1),
		"particle_radius": 0.003,
		"viscosity": 0.05,
		"surface_adhesion": 0.1,
		"gravity_scale": 0.9,
		"emission_speed": 0.1,
		"spread_angle": 5.0,
		"lifetime": 3.0,
		"surface_lifetime": 10.0,
		"dry_rate": 0.3,
		"opacity": 0.25,
		"roughness": 0.08,
		"metallic": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
	})


# ── Digestive / Excretory ────────────────────────────────────────────────────

static func _urine() -> FluidType:
	return FluidType.create("urine", "excretory", {
		"color": Color(0.95, 0.85, 0.3, 0.7),
		"color_secondary": Color(0.9, 0.75, 0.2, 0.5),
		"viscosity": 0.03,
		"surface_adhesion": 0.1,
		"gravity_scale": 1.0,
		"emission_speed": 2.0,
		"spread_angle": 8.0,
		"lifetime": 6.0,
		"surface_lifetime": 45.0,
		"dry_rate": 0.1,
		"opacity": 0.65,
		"roughness": 0.1,
		"can_drip": true,
		"can_pool": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.5,
	})


static func _bile() -> FluidType:
	return FluidType.create("bile", "digestive", {
		"color": Color(0.4, 0.5, 0.1, 0.85),
		"color_secondary": Color(0.3, 0.4, 0.05, 0.7),
		"viscosity": 0.4,
		"surface_adhesion": 0.5,
		"gravity_scale": 1.1,
		"emission_speed": 0.5,
		"spread_angle": 15.0,
		"lifetime": 8.0,
		"surface_lifetime": 50.0,
		"dry_rate": 0.06,
		"opacity": 0.85,
		"roughness": 0.3,
		"emission_energy": 0.05,
		"can_pool": true,
		"can_splash": true,
		"sound_volume": 0.3,
	})


static func _feces_liquid() -> FluidType:
	return FluidType.create("feces_liquid", "excretory", {
		"color": Color(0.3, 0.2, 0.08, 0.9),
		"color_secondary": Color(0.2, 0.12, 0.04, 0.8),
		"particle_radius": 0.012,
		"viscosity": 0.65,
		"surface_adhesion": 0.7,
		"gravity_scale": 1.2,
		"emission_speed": 0.8,
		"spread_angle": 20.0,
		"lifetime": 12.0,
		"surface_lifetime": 90.0,
		"dry_rate": 0.04,
		"opacity": 0.9,
		"roughness": 0.5,
		"can_pool": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.5,
	})


# ── Reproductive ─────────────────────────────────────────────────────────────

static func _semen() -> FluidType:
	return FluidType.create("semen", "reproductive", {
		"color": Color(0.92, 0.92, 0.88, 0.85),
		"color_secondary": Color(0.88, 0.88, 0.82, 0.6),
		"viscosity": 0.7,
		"surface_adhesion": 0.75,
		"gravity_scale": 0.7,
		"emission_speed": 2.5,
		"spread_angle": 15.0,
		"lifetime": 10.0,
		"surface_lifetime": 60.0,
		"dry_rate": 0.06,
		"opacity": 0.85,
		"roughness": 0.2,
		"metallic": 0.05,
		"can_drip": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.25,
		"can_form_strings": true,
		"string_max_length": 0.2,
		"string_viscosity_threshold": 0.15,
		"miscibility": 0.6,
	})


static func _pre_ejaculate() -> FluidType:
	return FluidType.create("pre_ejaculate", "reproductive", {
		"color": Color(0.9, 0.92, 0.93, 0.45),
		"color_secondary": Color(0.88, 0.9, 0.9, 0.25),
		"particle_radius": 0.005,
		"viscosity": 0.3,
		"surface_adhesion": 0.4,
		"gravity_scale": 0.8,
		"emission_speed": 0.05,
		"spread_angle": 5.0,
		"lifetime": 6.0,
		"surface_lifetime": 20.0,
		"dry_rate": 0.12,
		"opacity": 0.4,
		"roughness": 0.12,
		"metallic": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
		"can_form_strings": true,
		"string_max_length": 0.08,
		"string_viscosity_threshold": 0.2,
		"miscibility": 0.8,
	})


static func _vaginal_fluid() -> FluidType:
	return FluidType.create("vaginal_fluid", "reproductive", {
		"color": Color(0.92, 0.92, 0.9, 0.5),
		"color_secondary": Color(0.88, 0.88, 0.85, 0.3),
		"particle_radius": 0.005,
		"viscosity": 0.25,
		"surface_adhesion": 0.35,
		"gravity_scale": 0.85,
		"emission_speed": 0.1,
		"spread_angle": 10.0,
		"lifetime": 6.0,
		"surface_lifetime": 25.0,
		"dry_rate": 0.12,
		"opacity": 0.45,
		"roughness": 0.1,
		"metallic": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.1,
		"miscibility": 0.7,
	})


static func _cervical_mucus() -> FluidType:
	return FluidType.create("cervical_mucus", "reproductive", {
		"color": Color(0.9, 0.92, 0.88, 0.6),
		"color_secondary": Color(0.85, 0.88, 0.82, 0.4),
		"viscosity": 0.8,
		"surface_adhesion": 0.85,
		"gravity_scale": 0.5,
		"emission_speed": 0.05,
		"spread_angle": 5.0,
		"lifetime": 15.0,
		"surface_lifetime": 40.0,
		"dry_rate": 0.04,
		"opacity": 0.55,
		"roughness": 0.25,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
		"can_form_strings": true,
		"string_max_length": 0.25,
		"string_viscosity_threshold": 0.15,
		"miscibility": 0.5,
	})


static func _breast_milk() -> FluidType:
	return FluidType.create("breast_milk", "reproductive", {
		"color": Color(0.95, 0.95, 0.9, 0.8),
		"color_secondary": Color(0.92, 0.92, 0.85, 0.6),
		"viscosity": 0.15,
		"surface_adhesion": 0.25,
		"gravity_scale": 1.0,
		"emission_speed": 0.8,
		"spread_angle": 12.0,
		"lifetime": 6.0,
		"surface_lifetime": 30.0,
		"dry_rate": 0.1,
		"opacity": 0.8,
		"roughness": 0.15,
		"can_drip": true,
		"can_streak": true,
		"can_splash": true,
		"sound_volume": 0.2,
	})


# ── Wound / Medical ──────────────────────────────────────────────────────────

static func _pus() -> FluidType:
	return FluidType.create("pus", "wound", {
		"color": Color(0.85, 0.85, 0.5, 0.85),
		"color_secondary": Color(0.75, 0.75, 0.4, 0.6),
		"viscosity": 0.8,
		"surface_adhesion": 0.85,
		"gravity_scale": 0.5,
		"emission_speed": 0.2,
		"spread_angle": 8.0,
		"lifetime": 15.0,
		"surface_lifetime": 50.0,
		"dry_rate": 0.04,
		"opacity": 0.85,
		"roughness": 0.35,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.1,
	})


static func _lymph() -> FluidType:
	return FluidType.create("lymph", "wound", {
		"color": Color(0.9, 0.92, 0.75, 0.35),
		"color_secondary": Color(0.88, 0.9, 0.7, 0.2),
		"particle_radius": 0.004,
		"viscosity": 0.08,
		"surface_adhesion": 0.15,
		"gravity_scale": 0.9,
		"emission_speed": 0.1,
		"spread_angle": 10.0,
		"lifetime": 5.0,
		"surface_lifetime": 15.0,
		"dry_rate": 0.2,
		"opacity": 0.3,
		"roughness": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
	})


static func _synovial() -> FluidType:
	return FluidType.create("synovial", "wound", {
		"color": Color(0.9, 0.88, 0.6, 0.5),
		"color_secondary": Color(0.85, 0.82, 0.5, 0.3),
		"particle_radius": 0.005,
		"viscosity": 0.6,
		"surface_adhesion": 0.7,
		"gravity_scale": 0.6,
		"emission_speed": 0.1,
		"spread_angle": 5.0,
		"lifetime": 10.0,
		"surface_lifetime": 30.0,
		"dry_rate": 0.05,
		"opacity": 0.45,
		"roughness": 0.15,
		"metallic": 0.1,
		"can_drip": true,
		"can_streak": true,
		"can_splash": false,
		"sound_volume": 0.05,
	})
