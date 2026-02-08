class_name MartialArtsPoses
extends RefCounted
## Martial arts pose library — stances, strikes, kicks, blocks.
## Covers karate, boxing, muay thai, wrestling, judo, capoeira.
##
## TUNING NOTE: Angles are anatomical approximations. Verify in-game.


static func get_all() -> Dictionary:
	return {
		"horse_stance": _horse_stance(),
		"front_stance": _front_stance(),
		"back_stance": _back_stance(),
		"boxing_guard": _boxing_guard(),
		"front_kick_chamber": _front_kick_chamber(),
		"side_kick_extend": _side_kick_extend(),
		"roundhouse_chamber": _roundhouse_chamber(),
		"high_block": _high_block(),
		"low_block": _low_block(),
		"straight_punch": _straight_punch(),
		"muay_thai_clinch": _muay_thai_clinch(),
		"crane_stance": _crane_stance(),
		"wrestling_stance": _wrestling_stance(),
		"judo_kuzushi": _judo_kuzushi(),
		"capoeira_ginga": _capoeira_ginga(),
	}


static func _horse_stance() -> RagdollPose:
	return RagdollPose.create("horse_stance", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-55, 0, -30),
		"pelvis_to_right_upper_leg": Vector3(-55, 0, 30),
		"left_upper_leg_to_left_lower_leg": Vector3(-55, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-55, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(15, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(15, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.8, "Kiba-dachi — deep wide squat, fists at hips")


static func _front_stance() -> RagdollPose:
	return RagdollPose.create("front_stance", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-60, 0, -10),
		"left_upper_leg_to_left_lower_leg": Vector3(-70, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(15, 0, 5),
		"right_upper_leg_to_right_lower_leg": Vector3(-10, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 15),
		"right_clavicle_to_right_upper_arm": Vector3(30, 0, -10),
		"left_upper_arm_to_left_forearm": Vector3(80, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(100, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.8, "Zenkutsu-dachi — long front lunge, rear leg straight, fists ready")


static func _back_stance() -> RagdollPose:
	return RagdollPose.create("back_stance", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -5),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-65, 0, 10),
		"right_upper_leg_to_right_lower_leg": Vector3(-65, 0, 0),
		"pelvis_to_spine_lower": Vector3(-5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -15),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.8, "Kokutsu-dachi — weight on rear leg, front leg light, guarding hands")


static func _boxing_guard() -> RagdollPose:
	return RagdollPose.create("boxing_guard", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-15, 0, -10),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 10),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-15, 0, 0),
		"pelvis_to_spine_lower": Vector3(5, -5, 0),
		"spine_lower_to_spine_upper": Vector3(5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(30, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(120, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(130, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
		"neck_to_head": Vector3(10, -10, 0),
	}, 0.7, "Orthodox boxing guard — chin tucked, fists high, slight southpaw lean")


static func _front_kick_chamber() -> RagdollPose:
	return RagdollPose.create("front_kick_chamber", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -5),
		"left_upper_leg_to_left_lower_leg": Vector3(-15, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-85, 0, 5),
		"right_upper_leg_to_right_lower_leg": Vector3(-120, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 20),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(100, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(100, 0, 0),
	}, 0.8, "Mae geri chamber — right knee raised high, shin pulled back")


static func _side_kick_extend() -> RagdollPose:
	return RagdollPose.create("side_kick_extend", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(0, 0, -5),
		"pelvis_to_left_upper_leg": Vector3(-15, 0, -5),
		"left_upper_leg_to_left_lower_leg": Vector3(-15, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-10, 30, 35),
		"right_upper_leg_to_right_lower_leg": Vector3(-5, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 30),
		"right_clavicle_to_right_upper_arm": Vector3(10, 0, -50),
		"left_upper_arm_to_left_forearm": Vector3(100, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(30, 0, 0),
	}, 0.9, "Yoko geri — right leg extended sideways, body leaned away")


static func _roundhouse_chamber() -> RagdollPose:
	return RagdollPose.create("roundhouse_chamber", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(0, 10, 0),
		"pelvis_to_left_upper_leg": Vector3(-10, 0, -5),
		"pelvis_to_right_upper_leg": Vector3(-80, 25, 15),
		"right_upper_leg_to_right_lower_leg": Vector3(-110, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(25, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(35, 0, -20),
		"left_upper_arm_to_left_forearm": Vector3(100, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
	}, 0.8, "Mawashi geri chamber — hip rotated, knee up and across")


static func _high_block() -> RagdollPose:
	return RagdollPose.create("high_block", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-40, 0, -10),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(75, 0, 30),
		"left_upper_arm_to_left_forearm": Vector3(120, 0, 0),
		"left_forearm_to_left_hand": Vector3(-20, 0, 10),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -15),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.8, "Jodan age-uke — left forearm raised above head to block overhead strike")


static func _low_block() -> RagdollPose:
	return RagdollPose.create("low_block", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-40, 0, -10),
		"left_upper_leg_to_left_lower_leg": Vector3(-40, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(-20, 0, 20),
		"left_upper_arm_to_left_forearm": Vector3(20, 0, 0),
		"right_clavicle_to_right_upper_arm": Vector3(20, 0, -15),
		"right_upper_arm_to_right_forearm": Vector3(90, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.8, "Gedan barai — left arm sweeping down across body to block low attacks")


static func _straight_punch() -> RagdollPose:
	return RagdollPose.create("straight_punch", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(5, 10, 0),
		"spine_lower_to_spine_upper": Vector3(5, 5, 0),
		"pelvis_to_left_upper_leg": Vector3(-30, 0, -10),
		"left_upper_leg_to_left_lower_leg": Vector3(-30, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-10, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(20, 0, 15),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_clavicle_to_right_upper_arm": Vector3(80, 0, -5),
		"right_upper_arm_to_right_forearm": Vector3(10, 0, 0),
		"left_hand_to_left_fingers": Vector3(70, 0, 0),
		"right_hand_to_right_fingers": Vector3(70, 0, 0),
	}, 0.9, "Choku-zuki — right arm fully extended, torso rotated into punch")


static func _muay_thai_clinch() -> RagdollPose:
	return RagdollPose.create("muay_thai_clinch", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(8, 0, 0),
		"spine_lower_to_spine_upper": Vector3(8, 0, 0),
		"spine_upper_to_chest": Vector3(5, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-20, 0, -8),
		"pelvis_to_right_upper_leg": Vector3(-20, 0, 8),
		"left_upper_leg_to_left_lower_leg": Vector3(-25, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-25, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(60, 0, 15),
		"right_clavicle_to_right_upper_arm": Vector3(60, 0, -15),
		"left_upper_arm_to_left_forearm": Vector3(130, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(130, 0, 0),
	}, 0.7, "Muay Thai plum — hunched forward, both arms clasping opponent's neck")


static func _crane_stance() -> RagdollPose:
	return RagdollPose.create("crane_stance", "martial_arts", {
		"pelvis_to_left_upper_leg": Vector3(-15, 0, -5),
		"left_upper_leg_to_left_lower_leg": Vector3(-20, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-80, 0, 10),
		"right_upper_leg_to_right_lower_leg": Vector3(-90, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(0, 0, 65),
		"right_clavicle_to_right_upper_arm": Vector3(0, 0, -65),
		"left_upper_arm_to_left_forearm": Vector3(80, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(80, 0, 0),
		"left_forearm_to_left_hand": Vector3(-40, 0, 15),
		"right_forearm_to_right_hand": Vector3(-40, 0, -15),
	}, 0.7, "Crane stance — one leg raised, arms extended like wings, wrists cocked")


static func _wrestling_stance() -> RagdollPose:
	return RagdollPose.create("wrestling_stance", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(10, 0, 0),
		"spine_lower_to_spine_upper": Vector3(10, 0, 0),
		"pelvis_to_left_upper_leg": Vector3(-45, 0, -15),
		"pelvis_to_right_upper_leg": Vector3(-35, 0, 15),
		"left_upper_leg_to_left_lower_leg": Vector3(-50, 0, 0),
		"right_upper_leg_to_right_lower_leg": Vector3(-40, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 25),
		"right_clavicle_to_right_upper_arm": Vector3(30, 0, -25),
		"left_upper_arm_to_left_forearm": Vector3(80, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(80, 0, 0),
		"neck_to_head": Vector3(15, 0, 0),
	}, 0.7, "Low wrestling stance — bent over, arms extended to grapple, head watching")


static func _judo_kuzushi() -> RagdollPose:
	return RagdollPose.create("judo_kuzushi", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(10, 15, 0),
		"spine_lower_to_spine_upper": Vector3(5, 10, 0),
		"pelvis_to_left_upper_leg": Vector3(-50, 0, -10),
		"left_upper_leg_to_left_lower_leg": Vector3(-50, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(-20, 0, 5),
		"left_clavicle_to_left_upper_arm": Vector3(50, 0, 30),
		"left_upper_arm_to_left_forearm": Vector3(90, 0, 0),
		"right_clavicle_to_right_upper_arm": Vector3(40, 0, -20),
		"right_upper_arm_to_right_forearm": Vector3(70, 0, 0),
	}, 0.7, "Kuzushi entry — pulling opponent off balance, body rotated for throw")


static func _capoeira_ginga() -> RagdollPose:
	return RagdollPose.create("capoeira_ginga", "martial_arts", {
		"pelvis_to_spine_lower": Vector3(-5, -10, 0),
		"pelvis_to_left_upper_leg": Vector3(-40, 0, -15),
		"left_upper_leg_to_left_lower_leg": Vector3(-50, 0, 0),
		"pelvis_to_right_upper_leg": Vector3(15, 0, 10),
		"right_upper_leg_to_right_lower_leg": Vector3(-10, 0, 0),
		"left_clavicle_to_left_upper_arm": Vector3(30, 0, 40),
		"right_clavicle_to_right_upper_arm": Vector3(-10, 0, -30),
		"left_upper_arm_to_left_forearm": Vector3(60, 0, 0),
		"right_upper_arm_to_right_forearm": Vector3(40, 0, 0),
	}, 0.5, "Ginga base — swaying stance, one leg back, flowing arm guard")
