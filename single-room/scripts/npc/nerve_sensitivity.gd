class_name NerveSensitivity
extends Resource
## Defines nerve/touch sensitivity for a single body part.
## Drives comfort/discomfort response via the NerveSystem.

## Zone classification — affects how stimulation maps to feelings.
enum Zone {
	NEUTRAL,        ## Ordinary skin surface
	EROGENOUS,      ## Heightened pleasure response
	PAIN_PRONE,     ## Easily hurt (face, joints, etc.)
	TICKLISH,       ## Light touch triggers reflexive response
	PRESSURE_POINT, ## Deep-tissue response to firm pressure
}

@export var base_sensitivity: float = 0.5
@export var zone_type: Zone = Zone.NEUTRAL
## How strongly stimulation on this part generates comfort (0–1).
@export_range(0.0, 1.0) var comfort_weight: float = 0.3
## How strongly stimulation on this part generates discomfort (0–1).
@export_range(0.0, 1.0) var discomfort_weight: float = 0.1
## How fast accumulated stimulation decays per second.
@export_range(0.05, 3.0) var stimulation_decay: float = 0.5


static func create(p_sensitivity: float, p_zone: Zone,
		p_comfort: float, p_discomfort: float,
		p_decay: float = 0.5) -> NerveSensitivity:
	var ns: NerveSensitivity = NerveSensitivity.new()
	ns.base_sensitivity = p_sensitivity
	ns.zone_type = p_zone
	ns.comfort_weight = p_comfort
	ns.discomfort_weight = p_discomfort
	ns.stimulation_decay = p_decay
	return ns


## Returns a default sensitivity map keyed by body part name.
## Used by HumanoidRagdollBuilder when creating parts.
static func get_default_map() -> Dictionary:
	var N: Zone = Zone.NEUTRAL
	var E: Zone = Zone.EROGENOUS
	var P: Zone = Zone.PAIN_PRONE
	var T: Zone = Zone.TICKLISH
	var PR: Zone = Zone.PRESSURE_POINT

	#                           sens   zone  comfort  discomfort  decay
	return {
		# ── Core ─────────────────────────────────────────────────────
		"pelvis":           create(0.5,  N,   0.3,     0.2,       0.4),
		"spine_lower":      create(0.5,  PR,  0.4,     0.3,       0.5),
		"spine_mid":        create(0.4,  PR,  0.3,     0.3,       0.5),
		"spine_upper":      create(0.4,  PR,  0.3,     0.3,       0.5),
		"chest":            create(0.45, N,   0.3,     0.2,       0.5),
		"neck":             create(0.8,  E,   0.6,     0.4,       0.6),
		"head":             create(0.6,  P,   0.3,     0.5,       0.5),

		# ── Left Arm ────────────────────────────────────────────────
		"left_clavicle":    create(0.35, N,   0.2,     0.2,       0.5),
		"left_upper_arm":   create(0.3,  N,   0.2,     0.15,      0.5),
		"left_forearm":     create(0.35, N,   0.2,     0.15,      0.5),
		"left_hand":        create(0.7,  T,   0.4,     0.2,       0.6),
		# Left fingers — proximal → distal escalating sensitivity
		"left_thumb_01":    create(0.60, N,   0.25,    0.2,       0.6),
		"left_thumb_02":    create(0.65, N,   0.3,     0.2,       0.6),
		"left_thumb_03":    create(0.75, T,   0.4,     0.2,       0.6),
		"left_index_01":    create(0.55, N,   0.25,    0.15,      0.6),
		"left_index_02":    create(0.65, N,   0.3,     0.2,       0.6),
		"left_index_03":    create(0.80, T,   0.45,    0.2,       0.6),
		"left_middle_01":   create(0.50, N,   0.25,    0.15,      0.6),
		"left_middle_02":   create(0.60, N,   0.3,     0.2,       0.6),
		"left_middle_03":   create(0.75, T,   0.4,     0.2,       0.6),
		"left_ring_01":     create(0.45, N,   0.2,     0.15,      0.6),
		"left_ring_02":     create(0.55, N,   0.25,    0.15,      0.6),
		"left_ring_03":     create(0.70, T,   0.35,    0.2,       0.6),
		"left_pinky_01":    create(0.40, N,   0.2,     0.15,      0.6),
		"left_pinky_02":    create(0.50, N,   0.25,    0.15,      0.6),
		"left_pinky_03":    create(0.65, T,   0.3,     0.2,       0.6),

		# ── Right Arm ───────────────────────────────────────────────
		"right_clavicle":   create(0.35, N,   0.2,     0.2,       0.5),
		"right_upper_arm":  create(0.3,  N,   0.2,     0.15,      0.5),
		"right_forearm":    create(0.35, N,   0.2,     0.15,      0.5),
		"right_hand":       create(0.7,  T,   0.4,     0.2,       0.6),
		# Right fingers — mirror of left
		"right_thumb_01":   create(0.60, N,   0.25,    0.2,       0.6),
		"right_thumb_02":   create(0.65, N,   0.3,     0.2,       0.6),
		"right_thumb_03":   create(0.75, T,   0.4,     0.2,       0.6),
		"right_index_01":   create(0.55, N,   0.25,    0.15,      0.6),
		"right_index_02":   create(0.65, N,   0.3,     0.2,       0.6),
		"right_index_03":   create(0.80, T,   0.45,    0.2,       0.6),
		"right_middle_01":  create(0.50, N,   0.25,    0.15,      0.6),
		"right_middle_02":  create(0.60, N,   0.3,     0.2,       0.6),
		"right_middle_03":  create(0.75, T,   0.4,     0.2,       0.6),
		"right_ring_01":    create(0.45, N,   0.2,     0.15,      0.6),
		"right_ring_02":    create(0.55, N,   0.25,    0.15,      0.6),
		"right_ring_03":    create(0.70, T,   0.35,    0.2,       0.6),
		"right_pinky_01":   create(0.40, N,   0.2,     0.15,      0.6),
		"right_pinky_02":   create(0.50, N,   0.25,    0.15,      0.6),
		"right_pinky_03":   create(0.65, T,   0.3,     0.2,       0.6),

		# ── Left Leg ────────────────────────────────────────────────
		"left_upper_leg":   create(0.4,  N,   0.3,     0.15,      0.5),
		"left_lower_leg":   create(0.3,  N,   0.2,     0.15,      0.5),
		"left_foot":        create(0.7,  T,   0.25,    0.25,      0.6),
		"left_toes":        create(0.75, T,   0.2,     0.3,       0.6),

		# ── Right Leg ───────────────────────────────────────────────
		"right_upper_leg":  create(0.4,  N,   0.3,     0.15,      0.5),
		"right_lower_leg":  create(0.3,  N,   0.2,     0.15,      0.5),
		"right_foot":       create(0.7,  T,   0.25,    0.25,      0.6),
		"right_toes":       create(0.75, T,   0.2,     0.3,       0.6),

		# ── Soft Tissue ─────────────────────────────────────────────
		"left_breast_mass":   create(0.75, E,   0.6,     0.2,       0.4),
		"right_breast_mass":  create(0.75, E,   0.6,     0.2,       0.4),
		"left_breast_nipple": create(0.95, E,   0.85,    0.25,      0.35),
		"right_breast_nipple":create(0.95, E,   0.85,    0.25,      0.35),
		"left_glute":         create(0.5,  E,   0.4,     0.15,      0.4),
		"right_glute":        create(0.5,  E,   0.4,     0.15,      0.4),

		# ── Genitals (multi-segment) ────────────────────────────────
		"penis_base":       create(0.80, E,   0.7,     0.25,      0.3),
		"penis_mid":        create(0.90, E,   0.8,     0.25,      0.3),
		"penis_tip":        create(0.98, E,   0.9,     0.3,       0.3),
		"scrotum_left":     create(0.75, E,   0.5,     0.4,       0.3),
		"scrotum_right":    create(0.75, E,   0.5,     0.4,       0.3),
		"labia_left":       create(0.90, E,   0.8,     0.25,      0.3),
		"labia_right":      create(0.90, E,   0.8,     0.25,      0.3),
		"clitoris":         create(0.99, E,   0.95,    0.3,       0.25),

		# ── Internal passages ───────────────────────────────────────
		"vaginal_canal_0":  create(0.9,  E,   0.8,     0.25,      0.3),
		"vaginal_canal_1":  create(0.85, E,   0.75,    0.2,       0.3),
		"vaginal_canal_2":  create(0.8,  E,   0.7,     0.2,       0.3),
		"vaginal_canal_3":  create(0.75, E,   0.65,    0.2,       0.3),
		"anal_canal_0":     create(0.85, E,   0.6,     0.35,      0.3),
		"anal_canal_1":     create(0.75, E,   0.5,     0.3,       0.3),
		"anal_canal_2":     create(0.65, E,   0.4,     0.25,      0.3),

		# ── Inner Thigh (if mapped separately later) ────────────────
		"left_inner_thigh":  create(0.75, E,   0.55,   0.15,      0.5),
		"right_inner_thigh": create(0.75, E,   0.55,   0.15,      0.5),
	}
