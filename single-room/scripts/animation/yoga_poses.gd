class_name YogaPoses
extends RefCounted
## Yoga pose library — classical asanas.
##
## TUNING NOTE: Angles are anatomical approximations. Verify in-game.
## Some poses (lotus, crow) require extreme flexibility — drive_stiffness
## is set lower so the ragdoll strains toward the pose without breaking joints.


static func get_all() -> Dictionary:
	return {
		"mountain": _mountain(),
		"warrior_i": _warrior_i(),
		"warrior_ii": _warrior_ii(),
		"warrior_iii": _warrior_iii(),
		"tree": _tree(),
		"downward_dog": _downward_dog(),
		"cobra": _cobra(),
		"childs_pose": _childs_pose(),
		"triangle": _triangle(),
		"chair": _chair(),
		"bridge": _bridge(),
		"dancer": _dancer(),
		"lotus": _lotus(),
		"half_moon": _half_moon(),
		"corpse": _corpse(),
	}


static func _mountain() -> RagdollPose:
	return RagdollPose.create("mountain", "yoga", {
		"pelvis_to_spine_lower": Vector3(0, 0, 0),
		"chest_to_neck": Vector3(-3, 0, 0),
		"neck_to_head": Vector3(5, 0, 0),
	}, 0.7, "Tadasana — standing tall, neutral alignment, slight chin tuck")


static func _warrior_i() -> RagdollPose:
	return RagdollPose.create("warrior_i", "yoga", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"spine_lower_to_spine_upper": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-70, 0, -5),
		"left_upper_leg_to_left_lower_leg": Vector3(-80, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(20, 0, 5),
		"right_upper_leg_to_right_lower_leg": Vector3(-10, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.7, "Virabhadrasana I — deep lunge, arms overhead, hips square")


static func _warrior_ii() -> RagdollPose:
	return RagdollPose.create("warrior_ii", "yoga", {
		"pelvis_to_spine_lower": Vector3(0, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-70, 0, -25),
		"left_upper_leg_to_left_lower_leg": Vector3(-80, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(10, 0, 25),
		"right_upper_leg_to_right_lower_leg": Vector3(-5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(0, 0, 65),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -65),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"neck_to_head": Vector3(0, -30, 0),
	}, 0.7, "Virabhadrasana II — wide lunge, arms extended to sides, gaze over front hand")


static func _warrior_iii() -> RagdollPose:
	return RagdollPose.create("warrior_iii", "yoga", {
		"pelvis_to_spine_lower": Vector3(15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(15, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-5, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(25, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 5),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -5),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"neck_to_head": Vector3(-20, 0, 0),
	}, 0.8, "Virabhadrasana III — balancing on left leg, torso and right leg horizontal")


static func _tree() -> RagdollPose:
	return RagdollPose.create("tree", "yoga", {
		"pelvis_to_right_upper_leg": Vector3(-20, 40, 30),
		"right_upper_leg_to_right_lower_leg": Vector3(-120, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.6, "Vrksasana — standing on left, right foot on inner thigh, arms overhead")


static func _downward_dog() -> RagdollPose:
	return RagdollPose.create("downward_dog", "yoga", {
		"pelvis_to_spine_lower": Vector3(20, 0, 0),
		"spine_lower_to_spine_upper": Vector3(20, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"chest_to_neck": Vector3(10, 0, 0),
		"neck_to_head": Vector3(30, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(25, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(25, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
	}, 0.6, "Adho Mukha Svanasana — inverted V, hips high, heels toward ground")


static func _cobra() -> RagdollPose:
	return RagdollPose.create("cobra", "yoga", {
		"pelvis_to_spine_lower": Vector3(-15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-12, 0, 0),
		"spine_upper_to_chest": Vector3(-10, 0, 0),
		"chest_to_neck": Vector3(-10, 0, 0),
		"neck_to_head": Vector3(-15, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(10, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(10, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-20, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-20, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
	}, 0.6, "Bhujangasana — prone, upper body arched up, arms supporting")


static func _childs_pose() -> RagdollPose:
	return RagdollPose.create("childs_pose", "yoga", {
		"pelvis_to_spine_lower": Vector3(15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(15, 0, 0),
		"spine_upper_to_chest": Vector3(10, 0, 0),
		"chest_to_neck": Vector3(10, 0, 0),
		"neck_to_head": Vector3(20, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-95, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-95, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-130, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-130, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
	}, 0.4, "Balasana — kneeling, torso folded over thighs, arms extended forward")


static func _triangle() -> RagdollPose:
	return RagdollPose.create("triangle", "yoga", {
		"pelvis_to_spine_lower": Vector3(0, 0, -8),
		"spine_lower_to_spine_upper": Vector3(0, 0, -8),
		"spine_upper_to_chest": Vector3(0, 0, -5),
		"pelvis_to_left_upper_leg": Vector3(0, 0, -30),
		"pelvis_to_right_upper_leg": Vector3(0, 0, 30),
		"left_clavicle_to_left_upper_arm": Vector3(0, 0, 70),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -70),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"neck_to_head": Vector3(0, 0, 15),
	}, 0.6, "Trikonasana — wide stance, side bend left, arms vertical line")


static func _chair() -> RagdollPose:
	return RagdollPose.create("chair", "yoga", {
		"pelvis_to_spine_lower": Vector3(5, 0, 0),
		"spine_lower_to_spine_upper": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-60, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-60, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-60, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-60, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(85, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(85, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
	}, 0.7, "Utkatasana — deep squat with straight back and arms overhead")


static func _bridge() -> RagdollPose:
	return RagdollPose.create("bridge", "yoga", {
		"pelvis_to_spine_lower": Vector3(-15, 0, 0),
		"spine_lower_to_spine_upper": Vector3(-10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-50, 0, 5),
		"left_upper_leg_to_left_lower_leg": Vector3(-100, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-100, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-30, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-30, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(5, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(5, 0, 0),
	}, 0.6, "Setu Bandhasana — supine, hips lifted, feet and shoulders on ground")


static func _dancer() -> RagdollPose:
	return RagdollPose.create("dancer", "yoga", {
		"pelvis_to_spine_lower": Vector3(10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(0, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(25, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-100, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(80, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(-40, 0, -20),
		"right_upper_arm_to_right_forearm": Vector3(70, 0, 0),
		"right_forearm_to_right_hand": Vector3(-30, 0, 0),
	}, 0.6, "Natarajasana — standing on left, right foot held behind, reaching forward")


static func _lotus() -> RagdollPose:
	return RagdollPose.create("lotus", "yoga", {
		"pelvis_to_left_upper_leg": Vector3(-70, -25, -35),
		"pelvis_to_right_upper_leg": Vector3(-70, 25, 35),
		"left_upper_leg_to_left_lower_leg": Vector3(-130, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-130, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(-10, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(60, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(60, 0, 0),
	}, 0.4, "Padmasana — seated cross-legged, hands on knees, spine straight")


static func _half_moon() -> RagdollPose:
	return RagdollPose.create("half_moon", "yoga", {
		"pelvis_to_spine_lower": Vector3(0, 0, -8),
		"spine_lower_to_spine_upper": Vector3(5, 0, -5),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(20, 0, 30),
		"left_clavicle_to_left_upper_arm": Vector3(-30, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -70),
		"left_upper_arm_to_left_forearm": Vector3(3, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(3, 0, 0),
		"neck_to_head": Vector3(0, 0, 20),
	}, 0.6, "Ardha Chandrasana — balance on left leg and left hand, body open to side")


static func _corpse() -> RagdollPose:
	return RagdollPose.create("corpse", "yoga", {
		"pelvis_to_left_upper_leg": Vector3(5, -10, -15),
		"pelvis_to_right_upper_leg": Vector3(5, 10, 15),
		"left_clavicle_to_left_upper_arm": Vector3(-10, -15, 35),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 15, -35),
		"left_upper_arm_to_left_forearm": Vector3(15, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(15, 0, 0),
	}, 0.2, "Savasana — supine, fully relaxed, arms and legs slightly splayed")
