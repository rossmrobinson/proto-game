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
		# Left fingers — metacarpal → distal escalating sensitivity
		"left_thumb_00":    create(0.40, N,   0.2,     0.15,      0.6),
		"left_thumb_01":    create(0.60, N,   0.25,    0.2,       0.6),
		"left_thumb_02":    create(0.65, N,   0.3,     0.2,       0.6),
		"left_thumb_03":    create(0.75, T,   0.4,     0.2,       0.6),
		"left_index_00":    create(0.35, N,   0.2,     0.15,      0.6),
		"left_index_01":    create(0.55, N,   0.25,    0.15,      0.6),
		"left_index_02":    create(0.65, N,   0.3,     0.2,       0.6),
		"left_index_03":    create(0.80, T,   0.45,    0.2,       0.6),
		"left_middle_00":   create(0.30, N,   0.2,     0.15,      0.6),
		"left_middle_02":   create(0.60, N,   0.3,     0.2,       0.6),
		"left_middle_03":   create(0.75, T,   0.4,     0.2,       0.6),
		"left_ring_00":     create(0.30, N,   0.2,     0.15,      0.6),
		"left_ring_01":     create(0.45, N,   0.2,     0.15,      0.6),
		"left_ring_02":     create(0.55, N,   0.25,    0.15,      0.6),
		"left_ring_03":     create(0.70, T,   0.35,    0.2,       0.6),
		"left_pinky_00":    create(0.25, N,   0.15,    0.15,      0.6),
		"left_pinky_01":    create(0.40, N,   0.2,     0.15,      0.6),
		"left_pinky_02":    create(0.50, N,   0.25,    0.15,      0.6),
		"left_pinky_03":    create(0.65, T,   0.3,     0.2,       0.6),

		# ── Right Arm ───────────────────────────────────────────────
		"right_clavicle":   create(0.35, N,   0.2,     0.2,       0.5),
		"right_upper_arm":  create(0.3,  N,   0.2,     0.15,      0.5),
		"right_forearm":    create(0.35, N,   0.2,     0.15,      0.5),
		"right_hand":       create(0.7,  T,   0.4,     0.2,       0.6),
		# Right fingers — mirror of left
		"right_thumb_00":   create(0.40, N,   0.2,     0.15,      0.6),
		"right_thumb_01":   create(0.60, N,   0.25,    0.2,       0.6),
		"right_thumb_02":   create(0.65, N,   0.3,     0.2,       0.6),
		"right_thumb_03":   create(0.75, T,   0.4,     0.2,       0.6),
		"right_index_00":   create(0.35, N,   0.2,     0.15,      0.6),
		"right_index_01":   create(0.55, N,   0.25,    0.15,      0.6),
		"right_index_02":   create(0.65, N,   0.3,     0.2,       0.6),
		"right_index_03":   create(0.80, T,   0.45,    0.2,       0.6),
		"right_middle_00":  create(0.30, N,   0.2,     0.15,      0.6),
		"right_middle_01":  create(0.50, N,   0.25,    0.15,      0.6),
		"right_middle_02":  create(0.60, N,   0.3,     0.2,       0.6),
		"right_middle_03":  create(0.75, T,   0.4,     0.2,       0.6),
		"right_ring_00":    create(0.30, N,   0.2,     0.15,      0.6),
		"right_ring_01":    create(0.45, N,   0.2,     0.15,      0.6),
		"right_ring_02":    create(0.55, N,   0.25,    0.15,      0.6),
		"right_ring_03":    create(0.70, T,   0.35,    0.2,       0.6),
		"right_pinky_00":   create(0.25, N,   0.15,    0.15,      0.6),
		"right_pinky_01":   create(0.40, N,   0.2,     0.15,      0.6),
		"right_pinky_02":   create(0.50, N,   0.25,    0.15,      0.6),
		"right_pinky_03":   create(0.65, T,   0.3,     0.2,       0.6),

		# ── Left Leg ────────────────────────────────────────────────
		"left_upper_leg":   create(0.4,  N,   0.3,     0.15,      0.5),
		"left_lower_leg":   create(0.3,  N,   0.2,     0.15,      0.5),
		"left_foot":        create(0.7,  T,   0.25,    0.25,      0.6),
		"left_toes":        create(0.75, T,   0.2,     0.3,       0.6),
		# Left toes — per-toe sensitivity (big toe highest)
		"left_toe_big_01":  create(0.75, T,   0.2,     0.3,       0.6),
		"left_toe_big_02":  create(0.80, T,   0.25,    0.3,       0.6),

		# ── Right Leg ───────────────────────────────────────────────
		"right_upper_leg":  create(0.4,  N,   0.3,     0.15,      0.5),
		"right_lower_leg":  create(0.3,  N,   0.2,     0.15,      0.5),
		"right_foot":       create(0.7,  T,   0.25,    0.25,      0.6),
		"right_toes":       create(0.75, T,   0.2,     0.3,       0.6),
		# Right toes — per-toe sensitivity
		"right_toe_big_01": create(0.75, T,   0.2,     0.3,       0.6),
		"right_toe_big_02": create(0.80, T,   0.25,    0.3,       0.6),

		# ── Face ────────────────────────────────────────────────────
		"jaw":              create(0.5,  P,   0.2,     0.4,       0.5),
		"tongue_base":      create(0.7,  E,   0.5,     0.2,       0.4),
		"tongue_mid":       create(0.8,  E,   0.6,     0.2,       0.4),
		"tongue_tip":       create(0.9,  E,   0.7,     0.2,       0.35),
		"left_eye":         create(0.6,  P,   0.1,     0.8,       0.5),
		"right_eye":        create(0.6,  P,   0.1,     0.8,       0.5),

		# ── Soft Tissue ─────────────────────────────────────────────
		# Breast quadrants — inner (cleavage) most erogenous, lower least.
		"left_breast_inner":   create(0.80, E,   0.65,    0.2,       0.4),
		"left_breast_outer":   create(0.65, E,   0.50,    0.2,       0.4),
		"left_breast_upper":   create(0.70, E,   0.55,    0.2,       0.4),
		"left_breast_lower":   create(0.60, E,   0.45,    0.15,      0.4),
		"right_breast_inner":  create(0.80, E,   0.65,    0.2,       0.4),
		"right_breast_outer":  create(0.65, E,   0.50,    0.2,       0.4),
		"right_breast_upper":  create(0.70, E,   0.55,    0.2,       0.4),
		"right_breast_lower":  create(0.60, E,   0.45,    0.15,      0.4),
		"left_breast_nipple":  create(0.95, E,   0.85,    0.25,      0.35),
		"right_breast_nipple": create(0.95, E,   0.85,    0.25,      0.35),
		"left_inner_glute":   create(0.55, E,   0.45,    0.15,      0.4),
		"left_outer_glute":   create(0.45, E,   0.35,    0.15,      0.4),
		"right_inner_glute":  create(0.55, E,   0.45,    0.15,      0.4),
		"right_outer_glute":  create(0.45, E,   0.35,    0.15,      0.4),

		# ── Genitals (multi-segment) ────────────────────────────────
		"penis_base":       create(0.80, E,   0.7,     0.25,      0.3),
		"penis_mid":        create(0.90, E,   0.8,     0.25,      0.3),
		"penis_tip":        create(0.98, E,   0.9,     0.3,       0.3),
		"scrotum_left":     create(0.75, E,   0.5,     0.4,       0.3),
		"scrotum_right":    create(0.75, E,   0.5,     0.4,       0.3),
		"labia_left":       create(0.90, E,   0.8,     0.25,      0.3),
		"labia_right":      create(0.90, E,   0.8,     0.25,      0.3),
		"clitoris":         create(0.99, E,   0.95,    0.3,       0.25),

		# ── Entrance rings (high sensitivity at opening) ────────────
		"vaginal_ring_top":   create(0.92, E,   0.85,   0.25,      0.3),
		"vaginal_ring_bot":   create(0.92, E,   0.85,   0.25,      0.3),
		"vaginal_ring_left":  create(0.92, E,   0.85,   0.25,      0.3),
		"vaginal_ring_right": create(0.92, E,   0.85,   0.25,      0.3),
		"anal_ring_top":      create(0.88, E,   0.65,   0.35,      0.3),
		"anal_ring_bot":      create(0.88, E,   0.65,   0.35,      0.3),
		"anal_ring_left":     create(0.88, E,   0.65,   0.35,      0.3),
		"anal_ring_right":    create(0.88, E,   0.65,   0.35,      0.3),

		# ── Internal passages (ring-of-4, sensitivity tapers with depth) ─
		# Vaginal passage (8 depths × 4 quadrants — first 6 are interactive zone)
		"vaginal_passage_0_top": create(0.90, E, 0.80, 0.25, 0.3),
		"vaginal_passage_0_bot": create(0.90, E, 0.80, 0.25, 0.3),
		"vaginal_passage_0_left": create(0.90, E, 0.80, 0.25, 0.3),
		"vaginal_passage_0_right": create(0.90, E, 0.80, 0.25, 0.3),
		"vaginal_passage_1_top": create(0.87, E, 0.77, 0.22, 0.3),
		"vaginal_passage_1_bot": create(0.87, E, 0.77, 0.22, 0.3),
		"vaginal_passage_1_left": create(0.87, E, 0.77, 0.22, 0.3),
		"vaginal_passage_1_right": create(0.87, E, 0.77, 0.22, 0.3),
		"vaginal_passage_2_top": create(0.84, E, 0.74, 0.20, 0.3),
		"vaginal_passage_2_bot": create(0.84, E, 0.74, 0.20, 0.3),
		"vaginal_passage_2_left": create(0.84, E, 0.74, 0.20, 0.3),
		"vaginal_passage_2_right": create(0.84, E, 0.74, 0.20, 0.3),
		"vaginal_passage_3_top": create(0.80, E, 0.70, 0.20, 0.3),
		"vaginal_passage_3_bot": create(0.80, E, 0.70, 0.20, 0.3),
		"vaginal_passage_3_left": create(0.80, E, 0.70, 0.20, 0.3),
		"vaginal_passage_3_right": create(0.80, E, 0.70, 0.20, 0.3),
		"vaginal_passage_4_top": create(0.76, E, 0.66, 0.18, 0.3),
		"vaginal_passage_4_bot": create(0.76, E, 0.66, 0.18, 0.3),
		"vaginal_passage_4_left": create(0.76, E, 0.66, 0.18, 0.3),
		"vaginal_passage_4_right": create(0.76, E, 0.66, 0.18, 0.3),
		"vaginal_passage_5_top": create(0.72, E, 0.62, 0.18, 0.3),
		"vaginal_passage_5_bot": create(0.72, E, 0.62, 0.18, 0.3),
		"vaginal_passage_5_left": create(0.72, E, 0.62, 0.18, 0.3),
		"vaginal_passage_5_right": create(0.72, E, 0.62, 0.18, 0.3),
		# Buffer zone (depths 6-7: reduced sensitivity)
		"vaginal_passage_6_top": create(0.60, E, 0.50, 0.15, 0.3),
		"vaginal_passage_6_bot": create(0.60, E, 0.50, 0.15, 0.3),
		"vaginal_passage_6_left": create(0.60, E, 0.50, 0.15, 0.3),
		"vaginal_passage_6_right": create(0.60, E, 0.50, 0.15, 0.3),
		"vaginal_passage_7_top": create(0.50, E, 0.40, 0.12, 0.3),
		"vaginal_passage_7_bot": create(0.50, E, 0.40, 0.12, 0.3),
		"vaginal_passage_7_left": create(0.50, E, 0.40, 0.12, 0.3),
		"vaginal_passage_7_right": create(0.50, E, 0.40, 0.12, 0.3),
		# Anal passage (8 depths × 4 quadrants)
		"anal_passage_0_top": create(0.85, E, 0.60, 0.35, 0.3),
		"anal_passage_0_bot": create(0.85, E, 0.60, 0.35, 0.3),
		"anal_passage_0_left": create(0.85, E, 0.60, 0.35, 0.3),
		"anal_passage_0_right": create(0.85, E, 0.60, 0.35, 0.3),
		"anal_passage_1_top": create(0.80, E, 0.55, 0.30, 0.3),
		"anal_passage_1_bot": create(0.80, E, 0.55, 0.30, 0.3),
		"anal_passage_1_left": create(0.80, E, 0.55, 0.30, 0.3),
		"anal_passage_1_right": create(0.80, E, 0.55, 0.30, 0.3),
		"anal_passage_2_top": create(0.75, E, 0.50, 0.28, 0.3),
		"anal_passage_2_bot": create(0.75, E, 0.50, 0.28, 0.3),
		"anal_passage_2_left": create(0.75, E, 0.50, 0.28, 0.3),
		"anal_passage_2_right": create(0.75, E, 0.50, 0.28, 0.3),
		"anal_passage_3_top": create(0.70, E, 0.45, 0.25, 0.3),
		"anal_passage_3_bot": create(0.70, E, 0.45, 0.25, 0.3),
		"anal_passage_3_left": create(0.70, E, 0.45, 0.25, 0.3),
		"anal_passage_3_right": create(0.70, E, 0.45, 0.25, 0.3),
		"anal_passage_4_top": create(0.65, E, 0.40, 0.22, 0.3),
		"anal_passage_4_bot": create(0.65, E, 0.40, 0.22, 0.3),
		"anal_passage_4_left": create(0.65, E, 0.40, 0.22, 0.3),
		"anal_passage_4_right": create(0.65, E, 0.40, 0.22, 0.3),
		"anal_passage_5_top": create(0.60, E, 0.35, 0.20, 0.3),
		"anal_passage_5_bot": create(0.60, E, 0.35, 0.20, 0.3),
		"anal_passage_5_left": create(0.60, E, 0.35, 0.20, 0.3),
		"anal_passage_5_right": create(0.60, E, 0.35, 0.20, 0.3),
		# Buffer zone (depths 6-7)
		"anal_passage_6_top": create(0.50, E, 0.30, 0.18, 0.3),
		"anal_passage_6_bot": create(0.50, E, 0.30, 0.18, 0.3),
		"anal_passage_6_left": create(0.50, E, 0.30, 0.18, 0.3),
		"anal_passage_6_right": create(0.50, E, 0.30, 0.18, 0.3),
		"anal_passage_7_top": create(0.40, E, 0.25, 0.15, 0.3),
		"anal_passage_7_bot": create(0.40, E, 0.25, 0.15, 0.3),
		"anal_passage_7_left": create(0.40, E, 0.25, 0.15, 0.3),
		"anal_passage_7_right": create(0.40, E, 0.25, 0.15, 0.3),

		# ── Oral passage (5 depths × 4 quadrants) ──────────────────
		# Entrance ring — lips/teeth opening (high sensitivity, mixed)
		"oral_ring_top":   create(0.80, E, 0.60, 0.30, 0.3),
		"oral_ring_bot":   create(0.80, E, 0.60, 0.30, 0.3),
		"oral_ring_left":  create(0.80, E, 0.60, 0.30, 0.3),
		"oral_ring_right": create(0.80, E, 0.60, 0.30, 0.3),
		# Depth 0 — back of mouth (sensitive, gag onset)
		"oral_passage_0_top": create(0.75, E, 0.50, 0.35, 0.3),
		"oral_passage_0_bot": create(0.75, E, 0.50, 0.35, 0.3),
		"oral_passage_0_left": create(0.75, E, 0.50, 0.35, 0.3),
		"oral_passage_0_right": create(0.75, E, 0.50, 0.35, 0.3),
		# Depth 1 — pharynx (strong gag zone, high discomfort)
		"oral_passage_1_top": create(0.70, P, 0.30, 0.60, 0.25),
		"oral_passage_1_bot": create(0.70, P, 0.30, 0.60, 0.25),
		"oral_passage_1_left": create(0.70, P, 0.30, 0.60, 0.25),
		"oral_passage_1_right": create(0.70, P, 0.30, 0.60, 0.25),
		# Depth 2 — upper throat (mostly discomfort)
		"oral_passage_2_top": create(0.60, P, 0.20, 0.65, 0.25),
		"oral_passage_2_bot": create(0.60, P, 0.20, 0.65, 0.25),
		"oral_passage_2_left": create(0.60, P, 0.20, 0.65, 0.25),
		"oral_passage_2_right": create(0.60, P, 0.20, 0.65, 0.25),
		# Depth 3–4 — deep throat (almost all discomfort, tight)
		"oral_passage_3_top": create(0.50, P, 0.10, 0.70, 0.25),
		"oral_passage_3_bot": create(0.50, P, 0.10, 0.70, 0.25),
		"oral_passage_3_left": create(0.50, P, 0.10, 0.70, 0.25),
		"oral_passage_3_right": create(0.50, P, 0.10, 0.70, 0.25),
		"oral_passage_4_top": create(0.40, P, 0.05, 0.75, 0.25),
		"oral_passage_4_bot": create(0.40, P, 0.05, 0.75, 0.25),
		"oral_passage_4_left": create(0.40, P, 0.05, 0.75, 0.25),
		"oral_passage_4_right": create(0.40, P, 0.05, 0.75, 0.25),

		# ── Inner Thigh (if mapped separately later) ────────────────
		"left_inner_thigh":  create(0.75, E,   0.55,   0.15,      0.5),
		"right_inner_thigh": create(0.75, E,   0.55,   0.15,      0.5),
	}
