class_name KamaSutraPoses
extends RefCounted
## Kama Sutra position library — single-body poses.
##
## Each entry defines ONE person's body position. Two-person scenes are
## composed by setting different poses on two ragdolls and positioning
## them relative to each other. Paired poses are suffixed _a / _b.
##
## TUNING NOTE: Angles are anatomical approximations. Verify in-game.


static func get_all() -> Dictionary:
	return {
		"missionary_bottom": _missionary_bottom(),
		"missionary_top": _missionary_top(),
		"cowgirl_bottom": _cowgirl_bottom(),
		"cowgirl_top": _cowgirl_top(),
		"doggy_front": _doggy_front(),
		"doggy_rear": _doggy_rear(),
		"lotus_a": _lotus_a(),
		"lotus_b": _lotus_b(),
		"standing_front": _standing_front(),
		"standing_rear": _standing_rear(),
		"spooning_front": _spooning_front(),
		"spooning_rear": _spooning_rear(),
		"bridge_bottom": _bridge_bottom(),
		"bridge_top": _bridge_top(),
		"seated_bottom": _seated_bottom(),
		"seated_top": _seated_top(),
		"scissors_a": _scissors_a(),
		"scissors_b": _scissors_b(),
		"butterfly_bottom": _butterfly_bottom(),
		"butterfly_top": _butterfly_top(),
	}


# ── Missionary ───────────────────────────────────────────────────────────────

static func _missionary_bottom() -> RagdollPose:
	return RagdollPose.create("missionary_bottom", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, -25),
		"pelvis_to_right_upper_leg": Vector3(-50, 0, 25),
		"left_upper_leg_to_left_lower_leg": Vector3(-60, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-60, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(30, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.4, "Supine, knees up and apart, arms open")


static func _missionary_top() -> RagdollPose:
	return RagdollPose.create("missionary_top", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(10, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(10, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-20, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-40, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-40, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
	}, 0.5, "Prone, propped on forearms, hips low")


# ── Cowgirl ──────────────────────────────────────────────────────────────────

static func _cowgirl_bottom() -> RagdollPose:
	return RagdollPose.create("cowgirl_bottom", "kama_sutra", {
		"pelvis_to_left_upper_leg": Vector3(5, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(5, 0, 10),
		"left_clavicle_to_left_upper_arm": Vector3(-15, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-15, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(10, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.3, "Supine, legs slightly apart, relaxed")


static func _cowgirl_top() -> RagdollPose:
	return RagdollPose.create("cowgirl_top", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-70, 0, -30),
		"pelvis_to_right_upper_leg": Vector3(-70, 0, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-100, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-100, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-15, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(-15, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(20, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(20, 0, 0),
	}, 0.5, "Kneeling straddle, upright torso, hands on partner or own thighs")


# ── Doggy ────────────────────────────────────────────────────────────────────

static func _doggy_front() -> RagdollPose:
	return RagdollPose.create("doggy_front", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(10, 0, 0),
		"spine_upper_to_chest": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-85, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-85, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-95, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-95, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-50, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-50, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
	}, 0.5, "On all fours, weight on hands and knees")


static func _doggy_rear() -> RagdollPose:
	return RagdollPose.create("doggy_rear", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-40, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-40, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -20),
	}, 0.5, "Kneeling upright behind partner, hands on hips")


# ── Lotus ────────────────────────────────────────────────────────────────────

static func _lotus_a() -> RagdollPose:
	return RagdollPose.create("lotus_a", "kama_sutra", {
		"pelvis_to_left_upper_leg": Vector3(-65, -20, -30),
		"pelvis_to_right_upper_leg": Vector3(-65, 20, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-120, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-120, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(40, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.5, "Seated cross-legged, arms wrapped around partner")


static func _lotus_b() -> RagdollPose:
	return RagdollPose.create("lotus_b", "kama_sutra", {
		"pelvis_to_left_upper_leg": Vector3(-70, 0, -30),
		"pelvis_to_right_upper_leg": Vector3(-70, 0, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-90, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-90, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(40, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.5, "Seated in partner's lap, legs wrapped around waist")


# ── Standing ─────────────────────────────────────────────────────────────────

static func _standing_front() -> RagdollPose:
	return RagdollPose.create("standing_front", "kama_sutra", {
		"pelvis_to_left_upper_leg": Vector3(0, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-80, 0, 30),
		"right_upper_leg_to_right_lower_leg": Vector3(-40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(50, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(50, 0, 0),
	}, 0.5, "Standing on one leg, other leg raised and wrapped, arms on partner")


static func _standing_rear() -> RagdollPose:
	return RagdollPose.create("standing_rear", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-10, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-10, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(15, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(15, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(40, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.5, "Standing behind partner, slight knee bend, hands supporting")


# ── Spooning ─────────────────────────────────────────────────────────────────

static func _spooning_front() -> RagdollPose:
	return RagdollPose.create("spooning_front", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-40, 0, 0),
		"left_upper_leg_to_left_lower_leg": Vector3(-50, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(-20, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(40, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.3, "Lying on side, fetal curve, knees drawn up — front spoon")


static func _spooning_rear() -> RagdollPose:
	return RagdollPose.create("spooning_rear", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-40, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-30, 0, 0),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-30, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(-5, 0, -15),
		"left_upper_arm_to_left_forearm": Vector3(50, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.3, "Lying on side, matching front spoon curve — rear spoon")


# ── Bridge ───────────────────────────────────────────────────────────────────

static func _bridge_bottom() -> RagdollPose:
	return RagdollPose.create("bridge_bottom", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-50, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-100, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-100, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-30, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-30, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(10, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.5, "Bridge arch — supine, hips raised high, feet flat")


static func _bridge_top() -> RagdollPose:
	return RagdollPose.create("bridge_top", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-30, 0, -15),
		"pelvis_to_right_upper_leg": Vector3(-30, 0, 15),
		"left_upper_leg_to_left_lower_leg": Vector3(-30, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-30, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -20),
	}, 0.5, "Kneeling over bridge partner, moderate lean forward")


# ── Seated ───────────────────────────────────────────────────────────────────

static func _seated_bottom() -> RagdollPose:
	return RagdollPose.create("seated_bottom", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-80, 0, -20),
		"pelvis_to_right_upper_leg": Vector3(-80, 0, 20),
		"left_upper_leg_to_left_lower_leg": Vector3(-90, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-90, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-20, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-20, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(40, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.5, "Seated on surface, legs forward and apart, leaning back slightly")


static func _seated_top() -> RagdollPose:
	return RagdollPose.create("seated_top", "kama_sutra", {
		"pelvis_to_left_upper_leg": Vector3(-65, 0, -25),
		"pelvis_to_right_upper_leg": Vector3(-65, 0, 25),
		"left_upper_leg_to_left_lower_leg": Vector3(-80, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-80, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(30, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.5, "Straddling seated partner, legs wrapped, arms on shoulders")


# ── Scissors ─────────────────────────────────────────────────────────────────

static func _scissors_a() -> RagdollPose:
	return RagdollPose.create("scissors_a", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-5, -10, 5),
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -30),
		"pelvis_to_right_upper_leg": Vector3(-60, 0, 20),
		"right_upper_leg_to_right_lower_leg": Vector3(-20, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-20, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-15, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(15, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(20, 0, 0),
	}, 0.4, "Side-lying, legs interlocked at angle — person A")


static func _scissors_b() -> RagdollPose:
	return RagdollPose.create("scissors_b", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-5, 10, -5),
		"pelvis_to_left_upper_leg": Vector3(-55, 0, -20),
		"pelvis_to_right_upper_leg": Vector3(-25, 0, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-15, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-20, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(20, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(15, 0, 0),
	}, 0.4, "Side-lying, legs interlocked at angle — person B")


# ── Butterfly ────────────────────────────────────────────────────────────────

static func _butterfly_bottom() -> RagdollPose:
	return RagdollPose.create("butterfly_bottom", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-55, -15, -35),
		"pelvis_to_right_upper_leg": Vector3(-55, 15, 35),
		"left_upper_leg_to_left_lower_leg": Vector3(-70, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-70, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-20, 0, 45),
		"right_clavicle_to_right_upper_arm": Vector3(-20, 0, -45),
		"left_upper_arm_to_left_forearm": Vector3(10, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.4, "Supine at edge, knees open and drawn toward chest — butterfly")


static func _butterfly_top() -> RagdollPose:
	return RagdollPose.create("butterfly_top", "kama_sutra", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-20, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-20, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 15),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -15),
		"left_upper_arm_to_left_forearm": Vector3(30, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.5, "Standing between partner's legs, slight lean forward, hands on thighs")
