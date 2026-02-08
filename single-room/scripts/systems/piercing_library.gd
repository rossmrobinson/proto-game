class_name PiercingLibrary
extends RefCounted
## Pre-built piercing type definitions for common body piercings.


static func get_all() -> Dictionary:
	return {
		# ── Ear ──────────────────────────────────────────────────────────
		"ear_lobe_ring": _ear_lobe_ring(),
		"ear_lobe_stud": _ear_lobe_stud(),
		"ear_helix_ring": _ear_helix_ring(),
		"ear_industrial_barbell": _ear_industrial_barbell(),

		# ── Face ─────────────────────────────────────────────────────────
		"nose_ring": _nose_ring(),
		"nose_stud": _nose_stud(),
		"septum_ring": _septum_ring(),
		"lip_ring": _lip_ring(),
		"lip_stud": _lip_stud(),
		"eyebrow_barbell": _eyebrow_barbell(),
		"tongue_barbell": _tongue_barbell(),

		# ── Torso ────────────────────────────────────────────────────────
		"nipple_ring": _nipple_ring(),
		"nipple_barbell": _nipple_barbell(),
		"navel_ring": _navel_ring(),

		# ── Genital ──────────────────────────────────────────────────────
		"genital_ring": _genital_ring(),
		"genital_barbell": _genital_barbell(),

		# ── Surface / Dermal ─────────────────────────────────────────────
		"dermal_stud": _dermal_stud(),

		# ── Chain / Decorative ───────────────────────────────────────────
		"chain_connector": _chain_connector(),
	}


static func get_piercing(piercing_name: String) -> PiercingType:
	var all: Dictionary = get_all()
	if all.has(piercing_name):
		return all[piercing_name] as PiercingType
	push_warning("[PiercingLibrary] Unknown piercing: %s" % piercing_name)
	return null


# ── Ear ──────────────────────────────────────────────────────────────────────

static func _ear_lobe_ring() -> PiercingType:
	return PiercingType.create("ear_lobe_ring", "Ring", {
		"size": 0.008,
		"mass": 0.003,
		"attachment_stiffness": 10.0,
		"attachment_damping": 1.5,
		"max_stretch": 0.03,
		"color": Color(0.85, 0.85, 0.85),
	})


static func _ear_lobe_stud() -> PiercingType:
	return PiercingType.create("ear_lobe_stud", "Stud", {
		"size": 0.005,
		"mass": 0.002,
		"attachment_stiffness": 15.0,
		"attachment_damping": 2.0,
		"max_stretch": 0.015,
		"color": Color(0.9, 0.9, 0.85),
	})


static func _ear_helix_ring() -> PiercingType:
	return PiercingType.create("ear_helix_ring", "Ring", {
		"size": 0.006,
		"mass": 0.002,
		"attachment_stiffness": 12.0,
		"attachment_damping": 1.8,
		"max_stretch": 0.02,
		"color": Color(0.8, 0.8, 0.8),
	})


static func _ear_industrial_barbell() -> PiercingType:
	return PiercingType.create("ear_industrial_barbell", "Barbell", {
		"size": 0.02,
		"mass": 0.006,
		"attachment_stiffness": 15.0,
		"attachment_damping": 2.0,
		"max_stretch": 0.015,
		"color": Color(0.75, 0.75, 0.75),
	})


# ── Face ─────────────────────────────────────────────────────────────────────

static func _nose_ring() -> PiercingType:
	return PiercingType.create("nose_ring", "Ring", {
		"size": 0.006,
		"mass": 0.002,
		"attachment_stiffness": 12.0,
		"attachment_damping": 1.8,
		"max_stretch": 0.02,
		"color": Color(0.85, 0.85, 0.85),
	})


static func _nose_stud() -> PiercingType:
	return PiercingType.create("nose_stud", "Stud", {
		"size": 0.003,
		"mass": 0.001,
		"attachment_stiffness": 18.0,
		"attachment_damping": 2.5,
		"max_stretch": 0.01,
		"color": Color(0.9, 0.9, 0.85),
	})


static func _septum_ring() -> PiercingType:
	return PiercingType.create("septum_ring", "Ring", {
		"size": 0.01,
		"mass": 0.004,
		"attachment_stiffness": 10.0,
		"attachment_damping": 1.5,
		"max_stretch": 0.025,
		"color": Color(0.8, 0.8, 0.8),
	})


static func _lip_ring() -> PiercingType:
	return PiercingType.create("lip_ring", "Ring", {
		"size": 0.007,
		"mass": 0.003,
		"attachment_stiffness": 8.0,
		"attachment_damping": 1.2,
		"max_stretch": 0.035,
		"color": Color(0.85, 0.85, 0.85),
	})


static func _lip_stud() -> PiercingType:
	return PiercingType.create("lip_stud", "Stud", {
		"size": 0.004,
		"mass": 0.002,
		"attachment_stiffness": 14.0,
		"attachment_damping": 2.0,
		"max_stretch": 0.015,
		"color": Color(0.85, 0.85, 0.8),
	})


static func _eyebrow_barbell() -> PiercingType:
	return PiercingType.create("eyebrow_barbell", "Barbell", {
		"size": 0.012,
		"mass": 0.003,
		"attachment_stiffness": 10.0,
		"attachment_damping": 1.5,
		"max_stretch": 0.025,
		"color": Color(0.8, 0.8, 0.8),
	})


static func _tongue_barbell() -> PiercingType:
	return PiercingType.create("tongue_barbell", "Barbell", {
		"size": 0.01,
		"mass": 0.004,
		"attachment_stiffness": 12.0,
		"attachment_damping": 2.0,
		"max_stretch": 0.02,
		"color": Color(0.75, 0.75, 0.75),
	})


# ── Torso ────────────────────────────────────────────────────────────────────

static func _nipple_ring() -> PiercingType:
	return PiercingType.create("nipple_ring", "Ring", {
		"size": 0.01,
		"mass": 0.004,
		"attachment_stiffness": 6.0,
		"attachment_damping": 1.0,
		"max_stretch": 0.04,
		"color": Color(0.85, 0.85, 0.85),
	})


static func _nipple_barbell() -> PiercingType:
	return PiercingType.create("nipple_barbell", "Barbell", {
		"size": 0.015,
		"mass": 0.005,
		"attachment_stiffness": 8.0,
		"attachment_damping": 1.2,
		"max_stretch": 0.035,
		"color": Color(0.8, 0.8, 0.8),
	})


static func _navel_ring() -> PiercingType:
	return PiercingType.create("navel_ring", "Ring", {
		"size": 0.012,
		"mass": 0.005,
		"attachment_stiffness": 6.0,
		"attachment_damping": 1.0,
		"max_stretch": 0.045,
		"color": Color(0.85, 0.85, 0.85),
	})


# ── Genital ──────────────────────────────────────────────────────────────────

static func _genital_ring() -> PiercingType:
	return PiercingType.create("genital_ring", "Ring", {
		"size": 0.008,
		"mass": 0.003,
		"attachment_stiffness": 5.0,
		"attachment_damping": 1.0,
		"max_stretch": 0.05,
		"color": Color(0.85, 0.85, 0.85),
	})


static func _genital_barbell() -> PiercingType:
	return PiercingType.create("genital_barbell", "Barbell", {
		"size": 0.012,
		"mass": 0.004,
		"attachment_stiffness": 7.0,
		"attachment_damping": 1.2,
		"max_stretch": 0.04,
		"color": Color(0.8, 0.8, 0.8),
	})


# ── Surface / Dermal ─────────────────────────────────────────────────────────

static func _dermal_stud() -> PiercingType:
	return PiercingType.create("dermal_stud", "Stud", {
		"size": 0.004,
		"mass": 0.002,
		"attachment_stiffness": 20.0,
		"attachment_damping": 3.0,
		"max_stretch": 0.01,
		"color": Color(0.9, 0.9, 0.85),
	})


# ── Chain / Decorative ───────────────────────────────────────────────────────

static func _chain_connector() -> PiercingType:
	return PiercingType.create("chain_connector", "Chain", {
		"size": 0.003,
		"mass": 0.008,
		"attachment_stiffness": 3.0,
		"attachment_damping": 0.8,
		"max_stretch": 0.06,
		"can_tear": false,
		"color": Color(0.85, 0.78, 0.5),
		"metallic": 0.95,
		"roughness": 0.1,
	})
