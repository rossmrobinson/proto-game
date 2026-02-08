class_name DancePoses
extends RefCounted
## Dance pose library — ballet, waltz, salsa, hip-hop, breakdance.
##
## TUNING NOTE: Joint angles are first approximations based on anatomy.
## Signs may need flipping after in-game testing with the actual joint frame
## orientations. Structure and ranges are correct; exact directions need
## verification.
##
## Joint key convention: "parent_to_child" matches HumanoidRagdollBuilder joints.
## Angles: Vector3(pitch_deg, yaw_deg, roll_deg) relative to rest pose.
## Unspecified joints stay at rest (0, 0, 0).


static func get_all() -> Dictionary:
	return {
		"ballet_first_position": _ballet_first_position(),
		"ballet_second_position": _ballet_second_position(),
		"ballet_fifth_position": _ballet_fifth_position(),
		"ballet_arabesque": _ballet_arabesque(),
		"ballet_plie": _ballet_plie(),
		"ballet_releve": _ballet_releve(),
		"waltz_closed_frame": _waltz_closed_frame(),
		"salsa_hip_left": _salsa_hip_left(),
		"salsa_hip_right": _salsa_hip_right(),
		"hiphop_pop": _hiphop_pop(),
		"hiphop_wave": _hiphop_wave(),
		"breakdance_freeze": _breakdance_freeze(),
		"tango_dip": _tango_dip(),
		"belly_roll_back": _belly_roll_back(),
		"swing_open": _swing_open(),
	}


static func _ballet_first_position() -> RagdollPose:
	return RagdollPose.create("ballet_first_position", "dance", {
		"pelvis_to_left_upper_leg": Vector3(0, -20, 0),
		"pelvis_to_right_upper_leg": Vector3(0, 20, 0),
		"left_clavicle_to_left_upper_arm": Vector3(15, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(15, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(35, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(35, 0, 0),
		"left_forearm_to_left_hand": Vector3(-10, 0, 10),
		"right_forearm_to_right_hand": Vector3(-10, 0, -10),
	}, 0.7, "Heels together, toes turned out, arms in oval at navel")


static func _ballet_second_position() -> RagdollPose:
	return RagdollPose.create("ballet_second_position", "dance", {
		"pelvis_to_left_upper_leg": Vector3(0, -20, -20),
		"pelvis_to_right_upper_leg": Vector3(0, 20, 20),
		"left_clavicle_to_left_upper_arm": Vector3(0, 0, 60),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -60),
		"left_upper_arm_to_left_forearm": Vector3(8, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(8, 0, 0),
	}, 0.7, "Feet wide, toes out, arms extended to sides at shoulder height")


static func _ballet_fifth_position() -> RagdollPose:
	return RagdollPose.create("ballet_fifth_position", "dance", {
		"pelvis_to_left_upper_leg": Vector3(-5, -25, 5),
		"pelvis_to_right_upper_leg": Vector3(-5, 25, -5),
		"left_clavicle_to_left_upper_arm": Vector3(70, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(70, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(15, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(15, 0, 0),
	}, 0.7, "Feet crossed and turned out, arms overhead in oval")


static func _ballet_arabesque() -> RagdollPose:
	return RagdollPose.create("ballet_arabesque", "dance", {
		"pelvis_to_spine_lower": Vector3(10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(0, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(25, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(0, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(80, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -50),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(8, 0, 0),
	}, 0.7, "Standing on left leg, right leg extended behind, arm forward")


static func _ballet_plie() -> RagdollPose:
	return RagdollPose.create("ballet_plie", "dance", {
		"pelvis_to_left_upper_leg": Vector3(-40, -20, -15),
		"pelvis_to_right_upper_leg": Vector3(-40, 20, 15),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(15, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(15, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(30, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.6, "Deep knee bend with turnout, arms in first position")


static func _ballet_releve() -> RagdollPose:
	return RagdollPose.create("ballet_releve", "dance", {
		"left_lower_leg_to_left_foot": Vector3(-35, 0, 0),
		"right_lower_leg_to_right_foot": Vector3(-35, 0, 0),
		"left_foot_to_left_toes": Vector3(40, 0, 0),
		"right_foot_to_right_toes": Vector3(40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(70, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(70, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(12, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(12, 0, 0),
	}, 0.8, "Standing on toes, arms in fifth/crown position")


static func _waltz_closed_frame() -> RagdollPose:
	return RagdollPose.create("waltz_closed_frame", "dance", {
		"pelvis_to_spine_lower": Vector3(3, 0, 0),
		"spine_upper_to_chest": Vector3(5, 0, 0),
		"chest_to_neck": Vector3(-5, 5, 0),
		"left_clavicle_to_left_upper_arm": Vector3(50, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(80, 0, 0),
		"left_forearm_to_left_hand": Vector3(0, -10, 0),
		"right_forearm_to_right_hand": Vector3(0, 10, 0),
	}, 0.5, "Waltz partner frame — left arm up, right extended")


static func _salsa_hip_left() -> RagdollPose:
	return RagdollPose.create("salsa_hip_left", "dance", {
		"pelvis_to_spine_lower": Vector3(0, 5, -8),
		"spine_lower_to_spine_upper": Vector3(0, 0, 5),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-20, 0, 5),
		"right_upper_leg_to_right_lower_leg": Vector3(-25, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(60, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(60, 0, 0),
	}, 0.4, "Hip popped left, weight on left leg, arms at waist")


static func _salsa_hip_right() -> RagdollPose:
	return RagdollPose.create("salsa_hip_right", "dance", {
		"pelvis_to_spine_lower": Vector3(0, -5, 8),
		"spine_lower_to_spine_upper": Vector3(0, 0, -5),
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-25, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(10, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(60, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(60, 0, 0),
	}, 0.4, "Hip popped right, weight on right leg, arms at waist")


static func _hiphop_pop() -> RagdollPose:
	return RagdollPose.create("hiphop_pop", "dance", {
		"pelvis_to_spine_lower": Vector3(-8, 0, 0),
		"spine_lower_to_spine_upper": Vector3(15, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-15, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-15, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-20, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(30, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(110, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(110, 0, 0),
	}, 0.5, "Chest popped forward, knees bent, arms angular")


static func _hiphop_wave() -> RagdollPose:
	return RagdollPose.create("hiphop_wave", "dance", {
		"pelvis_to_spine_lower": Vector3(-10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-5, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"chest_to_neck": Vector3(10, 0, 0),
		"neck_to_head": Vector3(-15, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 50),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -50),
		"left_upper_arm_to_left_forearm": Vector3(70, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(70, 0, 0),
	}, 0.3, "Body wave — sequential spine undulation, arms flowing")


static func _breakdance_freeze() -> RagdollPose:
	return RagdollPose.create("breakdance_freeze", "dance", {
		"pelvis_to_spine_lower": Vector3(15, 10, -5),
		"spine_lower_to_spine_upper": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-80, 0, -20),
		"pelvis_to_right_upper_leg": Vector3(-40, 20, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-60, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-90, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-50, 0, 50),
		"right_clavicle_to_right_upper_arm": Vector3(60, 0, -60),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.8, "Baby freeze — weight on one arm, legs elevated and angular")


static func _tango_dip() -> RagdollPose:
	return RagdollPose.create("tango_dip", "dance", {
		"pelvis_to_spine_lower": Vector3(-15, 5, 0),
		"spine_lower_to_spine_upper": Vector3(-10, 5, 0),
		"spine_upper_to_chest": Vector3(-8, 0, 0),
		"chest_to_neck": Vector3(-10, 0, 0),
		"neck_to_head": Vector3(20, -15, -10),
		"pelvis_to_left_upper_leg": Vector3(-60, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(15, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-80, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-30, 0, 60),
		"right_clavicle_to_right_upper_arm": Vector3(40, 0, -40),
		"right_upper_arm_to_right_forearm": Vector3(60, 0, 0),
	}, 0.5, "Tango dip — deep lunge, back arched, head turned")


static func _belly_roll_back() -> RagdollPose:
	return RagdollPose.create("belly_roll_back", "dance", {
		"pelvis_to_spine_lower": Vector3(-15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(20, 0, 0),
		"spine_upper_to_chest": Vector3(-5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -8),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 8),
		"left_upper_leg_to_left_lower_leg": Vector3(-15, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-15, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -40),
		"left_upper_arm_to_left_forearm": Vector3(30, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.3, "Belly roll — pelvis tucked back, chest forward, flowing arms")


static func _swing_open() -> RagdollPose:
	return RagdollPose.create("swing_open", "dance", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"spine_upper_to_chest": Vector3(5, -10, 0),
		"pelvis_to_left_upper_leg": Vector3(-30, 0, -25),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-15, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 60),
		"right_clavicle_to_right_upper_arm": Vector3(70, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(20, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
	}, 0.4, "Swing dance open position — wide stance, arms open and dynamic")
