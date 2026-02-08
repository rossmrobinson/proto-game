class_name GymnasticsPoses
extends RefCounted
## Gymnastics pose library — static holds and keyframe positions.
##
## TUNING NOTE: Angles are anatomical approximations. Verify in-game.
## Some poses (iron cross, planche) demand extreme strength — drive_stiffness
## is high so the ragdoll fights harder to hold the shape.


static func get_all() -> Dictionary:
	return {
		"handstand": _handstand(),
		"bridge_backbend": _bridge_backbend(),
		"front_split": _front_split(),
		"side_split": _side_split(),
		"tuck": _tuck(),
		"pike": _pike(),
		"layout": _layout(),
		"l_sit": _l_sit(),
		"hollow_body": _hollow_body(),
		"straddle": _straddle(),
		"iron_cross": _iron_cross(),
		"planche": _planche(),
	}


static func _handstand() -> RagdollPose:
	return RagdollPose.create("handstand", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-3, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(10, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(10, 0, 3),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"left_lower_leg_to_left_foot": Vector3(-20, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-20, 0, 0),
	}, 0.9, "Inverted vertical — arms locked, body straight, toes pointed")


static func _bridge_backbend() -> RagdollPose:
	return RagdollPose.create("bridge_backbend", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(-18, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-15, 0, 0),
		"spine_upper_to_chest": Vector3(-12, 0, 0),
		"chest_to_neck": Vector3(-10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, -8),
		"pelvis_to_right_upper_leg": Vector3(-50, 0, 8),
		"left_upper_leg_to_left_lower_leg": Vector3(-100, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-100, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 15),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -15),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.8, "Full bridge — hands and feet on floor, spine in deep arch")


static func _front_split() -> RagdollPose:
	return RagdollPose.create("front_split", "gymnastics", {
		"pelvis_to_left_upper_leg": Vector3(-95, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(25, 0, 0),
		"left_upper_leg_to_left_lower_leg": Vector3(0, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(0, 0, 0),
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(10, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.7, "Front split — left leg forward, right leg back, hips square to ground")


static func _side_split() -> RagdollPose:
	return RagdollPose.create("side_split", "gymnastics", {
		"pelvis_to_left_upper_leg": Vector3(0, 0, -38),
		"pelvis_to_right_upper_leg": Vector3(0, 0, 38),
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(10, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.7, "Side/straddle split — legs out to sides, torso upright")


static func _tuck() -> RagdollPose:
	return RagdollPose.create("tuck", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-95, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-95, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-130, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-130, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(100, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(100, 0, 0),
	}, 0.8, "Tuck position — knees pulled tight to chest, hands gripping shins")


static func _pike() -> RagdollPose:
	return RagdollPose.create("pike", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(18, 0, 0),
		"spine_lower_to_spine_upper": Vector3(15, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-95, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(-95, 0, 3),
		"left_upper_leg_to_left_lower_leg": Vector3(0, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(0, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(60, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(60, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.8, "Pike — legs straight, body folded at hips, reaching for toes")


static func _layout() -> RagdollPose:
	return RagdollPose.create("layout", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(-10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-8, 0, 0),
		"spine_upper_to_chest": Vector3(-5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(10, 0, -2),
		"pelvis_to_right_upper_leg": Vector3(10, 0, 2),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"left_lower_leg_to_left_foot": Vector3(-25, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-25, 0, 0),
	}, 0.8, "Layout — slight back arch, arms overhead, toes pointed, fully extended")


static func _l_sit() -> RagdollPose:
	return RagdollPose.create("l_sit", "gymnastics", {
		"pelvis_to_left_upper_leg": Vector3(-85, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(-85, 0, 3),
		"left_upper_leg_to_left_lower_leg": Vector3(0, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(0, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-40, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(-40, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
		"left_lower_leg_to_left_foot": Vector3(-20, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-20, 0, 0),
	}, 0.9, "L-sit — supported on hands, legs horizontal and straight, hips at 90°")


static func _hollow_body() -> RagdollPose:
	return RagdollPose.create("hollow_body", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(8, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(-20, 0, 3),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 8),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -8),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
	}, 0.8, "Hollow body hold — supine, lower back pressed flat, arms/legs elevated")


static func _straddle() -> RagdollPose:
	return RagdollPose.create("straddle", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(12, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-80, 0, -35),
		"pelvis_to_right_upper_leg": Vector3(-80, 0, 35),
		"left_upper_leg_to_left_lower_leg": Vector3(0, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(0, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(40, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(40, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.7, "Straddle sit — legs wide and straight, torso folding forward")


static func _iron_cross() -> RagdollPose:
	return RagdollPose.create("iron_cross", "gymnastics", {
		"left_clavicle_to_left_upper_arm": Vector3(0, 0, 70),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -70),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(5, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(5, 0, 3),
		"left_lower_leg_to_left_foot": Vector3(-20, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-20, 0, 0),
	}, 1.0, "Iron cross — arms fully extended to sides supporting body weight, body vertical")


static func _planche() -> RagdollPose:
	return RagdollPose.create("planche", "gymnastics", {
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-3, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(15, 0, -3),
		"pelvis_to_right_upper_leg": Vector3(15, 0, 3),
		"left_clavicle_to_left_upper_arm": Vector3(-50, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(-50, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
		"left_lower_leg_to_left_foot": Vector3(-20, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-20, 0, 0),
	}, 1.0, "Planche — horizontal body supported on straight arms, face down, legs extended")
