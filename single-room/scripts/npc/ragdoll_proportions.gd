class_name RagdollProportions
extends RefCounted

const MOTOR_FORCE_LIMIT: float = 3000.0

const REDUCED_LOD_AWAKE_PARTS: Dictionary = {
	"pelvis": true,
	"spine_lower": true,
	"spine_mid": true,
	"spine_upper": true,
	"chest": true,
	"neck": true,
	"head": true,
}

# ── Proportions (fraction of body_height) ────────────────────────────────────
# These come from anatomical proportions (roughly based on an ideal 7.5 head model)
const HEAD_HEIGHT_FRAC: float = 0.13
const NECK_HEIGHT_FRAC: float = 0.03
const CHEST_HEIGHT_FRAC: float = 0.10
const SPINE_UPPER_FRAC: float = 0.047
const SPINE_MID_FRAC: float = 0.046
const SPINE_LOWER_FRAC: float = 0.047
const PELVIS_HEIGHT_FRAC: float = 0.10
const UPPER_ARM_FRAC: float = 0.16
const FOREARM_FRAC: float = 0.14
const HAND_FRAC: float = 0.055
const CLAVICLE_FRAC: float = 0.04
const UPPER_LEG_FRAC: float = 0.23
const LOWER_LEG_FRAC: float = 0.22
const FOOT_FRAC: float = 0.04
const TOE_FRAC: float = 0.03
const SHOULDER_WIDTH_FRAC: float = 0.24
const HIP_WIDTH_FRAC: float = 0.10

# Soft tissue & anatomy
const BREAST_RADIUS_FRAC: float = 0.035
const BREAST_OFFSET_X_FRAC: float = 0.065
const BREAST_OFFSET_Z_FRAC: float = 0.06
const NIPPLE_RADIUS_FRAC: float = 0.008
# Breast quadrant sub-part offsets (fraction of BREAST_RADIUS_FRAC, so the
# actual offset = BREAST_QUAD_*_FRAC * BREAST_RADIUS_FRAC * h).  Each quadrant
# sphere sits at ~60% of the full breast radius from centre.
const BREAST_QUAD_INNER_X_FRAC: float = -0.6   # toward cleavage (sign flipped per side)
const BREAST_QUAD_OUTER_X_FRAC: float = 0.6    # away from cleavage
const BREAST_QUAD_UPPER_Y_FRAC: float = 0.55
const BREAST_QUAD_LOWER_Y_FRAC: float = -0.55
# Each quadrant sphere is this fraction of the full breast radius.
const BREAST_QUAD_RADIUS_SCALE: float = 0.55
const GLUTE_RADIUS_FRAC: float = 0.055
const GLUTE_OFFSET_X_FRAC: float = 0.06
const GLUTE_OFFSET_Z_FRAC: float = -0.06
const PENIS_SEGMENT_LENGTH_FRAC: float = 0.015
const PENIS_RADIUS_FRAC: float = 0.015
const SCROTUM_RADIUS_FRAC: float = 0.018
const SCROTUM_OFFSET_X_FRAC: float = 0.012
const LABIA_HEIGHT_FRAC: float = 0.025
const LABIA_OFFSET_X_FRAC: float = 0.01
const CLITORIS_RADIUS_FRAC: float = 0.006
const VULVA_HEIGHT_FRAC: float = 0.025
const PASSAGE_SEGMENT_RADIUS_FRAC: float = 0.010
const PASSAGE_SEGMENT_LENGTH_FRAC: float = 0.022
const PASSAGE_SEGMENTS_ANAL: int = 8
const PASSAGE_SEGMENTS_VAGINAL: int = 8
const PASSAGE_RING_QUADRANTS: PackedStringArray = ["top", "bot", "left", "right"]
const PASSAGE_RING_OFFSETS: Array = [
	Vector3(0.0, 0.0, 1.0),   # top: +Z (forward/up relative to passage)
	Vector3(0.0, 0.0, -1.0),  # bot: -Z
	Vector3(-1.0, 0.0, 0.0),  # left: -X
	Vector3(1.0, 0.0, 0.0),   # right: +X
]
const ENTRANCE_RING_RADIUS_FRAC: float = 0.014
# Glute inner/outer split offsets (fraction of body_height)
const GLUTE_INNER_OFFSET_X_FRAC: float = 0.03
const GLUTE_OUTER_OFFSET_X_FRAC: float = 0.09

# Finger dimensions (fraction of body_height)
const FINGER_RADIUS_FRAC: float = 0.006
# Per-finger segment lengths [metacarpal, proximal, middle, distal] as fraction of body_height
const THUMB_SEG_FRACS: PackedFloat64Array = [0.012, 0.016, 0.018, 0.014]
const INDEX_SEG_FRACS: PackedFloat64Array = [0.016, 0.013, 0.012, 0.014]
const MIDDLE_SEG_FRACS: PackedFloat64Array = [0.018, 0.017, 0.014, 0.013]
const RING_SEG_FRACS: PackedFloat64Array = [0.016, 0.015, 0.013, 0.014]
const PINKY_SEG_FRACS: PackedFloat64Array = [0.014, 0.011, 0.008, 0.010]

# Finger X offsets from hand centre (fraction of body_height), thumb is special
const FINGER_X_OFFSETS: PackedFloat64Array = [0.0, 0.01, 0.0, -0.007, -0.018]
# Finger Z offsets from hand front (fraction of body_height)
const FINGER_Z_OFFSETS: PackedFloat64Array = [0.02, 0.0, -0.005, -0.012, -0.02]
const FINGER_NAMES: PackedStringArray = ["thumb", "index", "middle", "ring", "pinky"]
const FINGER_SEG_NAMES: PackedStringArray = ["00", "01", "02", "03"]

# Toe dimensions (fraction of body_height)
const TOE_RADIUS_FRAC: float = 0.004
const TOE_NAMES: PackedStringArray = ["toe_big", "toe_index", "toe_middle", "toe_ring", "toe_pinky"]
const TOE_BIG_SEG_FRACS: PackedFloat64Array = [0.012, 0.008]
const TOE_INDEX_SEG_FRACS: PackedFloat64Array = [0.008, 0.006, 0.005]
const TOE_MIDDLE_SEG_FRACS: PackedFloat64Array = [0.007, 0.005, 0.004]
const TOE_RING_SEG_FRACS: PackedFloat64Array = [0.006, 0.005, 0.004]
const TOE_PINKY_SEG_FRACS: PackedFloat64Array = [0.005, 0.004, 0.003]
const TOE_X_OFFSETS: PackedFloat64Array = [0.02, 0.01, 0.0, -0.008, -0.018]
const TOE_Z_OFFSETS: PackedFloat64Array = [0.0, 0.01, 0.005, -0.002, -0.01]

# Face dimensions (fraction of body_height)
const JAW_HEIGHT_FRAC: float = 0.04
const JAW_WIDTH_FRAC: float = 0.06
const JAW_DEPTH_FRAC: float = 0.04
const TONGUE_SEG_LENGTH_FRAC: float = 0.012
const TONGUE_RADIUS_FRAC: float = 0.008
# Oral passage (throat) — fewer depths than vaginal/anal since throat is shorter.
const ORAL_PASSAGE_SEGMENTS: int = 5
const ORAL_PASSAGE_RADIUS_FRAC: float = 0.012
const ORAL_PASSAGE_SEG_LENGTH_FRAC: float = 0.020
const EYE_RADIUS_FRAC: float = 0.012
const EYE_OFFSET_X_FRAC: float = 0.03
const EYE_OFFSET_Z_FRAC: float = 0.05


## Part names that should be placed on the internal-only physics layer.
## Generated: 2 tunnels × (4 entrance ring + 8 depths × 4 quadrants) = 72 parts
##          + 1 oral tunnel × (4 entrance ring + 5 depths × 4 quadrants) = 24 parts
##          = 96 total.
const INTERNAL_PARTS: PackedStringArray = [
	# Oral entrance ring
	"oral_ring_top", "oral_ring_bot", "oral_ring_left", "oral_ring_right",
	# Oral passage (5 depths × 4 quadrants)
	"oral_passage_0_top", "oral_passage_0_bot", "oral_passage_0_left", "oral_passage_0_right",
	"oral_passage_1_top", "oral_passage_1_bot", "oral_passage_1_left", "oral_passage_1_right",
	"oral_passage_2_top", "oral_passage_2_bot", "oral_passage_2_left", "oral_passage_2_right",
	"oral_passage_3_top", "oral_passage_3_bot", "oral_passage_3_left", "oral_passage_3_right",
	"oral_passage_4_top", "oral_passage_4_bot", "oral_passage_4_left", "oral_passage_4_right",
	# Vaginal entrance ring
	"vaginal_ring_top", "vaginal_ring_bot", "vaginal_ring_left", "vaginal_ring_right",
	# Vaginal passage (8 depths × 4 quadrants)
	"vaginal_passage_0_top", "vaginal_passage_0_bot", "vaginal_passage_0_left", "vaginal_passage_0_right",
	"vaginal_passage_1_top", "vaginal_passage_1_bot", "vaginal_passage_1_left", "vaginal_passage_1_right",
	"vaginal_passage_2_top", "vaginal_passage_2_bot", "vaginal_passage_2_left", "vaginal_passage_2_right",
	"vaginal_passage_3_top", "vaginal_passage_3_bot", "vaginal_passage_3_left", "vaginal_passage_3_right",
	"vaginal_passage_4_top", "vaginal_passage_4_bot", "vaginal_passage_4_left", "vaginal_passage_4_right",
	"vaginal_passage_5_top", "vaginal_passage_5_bot", "vaginal_passage_5_left", "vaginal_passage_5_right",
	"vaginal_passage_6_top", "vaginal_passage_6_bot", "vaginal_passage_6_left", "vaginal_passage_6_right",
	"vaginal_passage_7_top", "vaginal_passage_7_bot", "vaginal_passage_7_left", "vaginal_passage_7_right",
	# Anal entrance ring
	"anal_ring_top", "anal_ring_bot", "anal_ring_left", "anal_ring_right",
	# Anal passage (8 depths × 4 quadrants)
	"anal_passage_0_top", "anal_passage_0_bot", "anal_passage_0_left", "anal_passage_0_right",
	"anal_passage_1_top", "anal_passage_1_bot", "anal_passage_1_left", "anal_passage_1_right",
	"anal_passage_2_top", "anal_passage_2_bot", "anal_passage_2_left", "anal_passage_2_right",
	"anal_passage_3_top", "anal_passage_3_bot", "anal_passage_3_left", "anal_passage_3_right",
	"anal_passage_4_top", "anal_passage_4_bot", "anal_passage_4_left", "anal_passage_4_right",
	"anal_passage_5_top", "anal_passage_5_bot", "anal_passage_5_left", "anal_passage_5_right",
	"anal_passage_6_top", "anal_passage_6_bot", "anal_passage_6_left", "anal_passage_6_right",
	"anal_passage_7_top", "anal_passage_7_bot", "anal_passage_7_left", "anal_passage_7_right",
]

## Soft-tissue parts placed on layer 5 (NPC_SoftTissue) instead of layer 3.
const SOFT_TISSUE_PARTS: PackedStringArray = [
	"left_breast_inner", "left_breast_outer",
	"left_breast_upper", "left_breast_lower",
	"right_breast_inner", "right_breast_outer",
	"right_breast_upper", "right_breast_lower",
	"left_breast_nipple", "right_breast_nipple",
	"left_inner_glute", "left_outer_glute",
	"right_inner_glute", "right_outer_glute",
	"penis_base", "penis_mid", "penis_tip",
	"scrotum_left", "scrotum_right",
	"labia_left", "labia_right", "clitoris",
]

## Face parts — may receive special collision/interaction treatment.
const FACE_PARTS: PackedStringArray = [
	"jaw", "tongue_base", "tongue_mid", "tongue_tip",
	"left_eye", "right_eye",
]

## Parts placed on layer 8 (NPC_FineMotor) in addition to their base layer.
## These are small parts that need to collide with internal passages
## (fingers for insertion, tongue for oral contact).
const FINE_MOTOR_PARTS: PackedStringArray = [
	"tongue_base", "tongue_mid", "tongue_tip",
	"left_thumb_00", "left_thumb_01", "left_thumb_02", "left_thumb_03",
	"left_index_00", "left_index_01", "left_index_02", "left_index_03",
	"left_middle_00", "left_middle_01", "left_middle_02", "left_middle_03",
	"left_ring_00", "left_ring_01", "left_ring_02", "left_ring_03",
	"left_pinky_00", "left_pinky_01", "left_pinky_02", "left_pinky_03",
	"right_thumb_00", "right_thumb_01", "right_thumb_02", "right_thumb_03",
	"right_index_00", "right_index_01", "right_index_02", "right_index_03",
	"right_middle_00", "right_middle_01", "right_middle_02", "right_middle_03",
	"right_ring_00", "right_ring_01", "right_ring_02", "right_ring_03",
	"right_pinky_00", "right_pinky_01", "right_pinky_02", "right_pinky_03",
]

## Parts that contact the ground for standing/foot placement calculations.
const GROUND_CONTACT_PARTS: PackedStringArray = [
	"left_foot", "right_foot",
	"left_toe_big_01", "left_toe_index_01", "left_toe_middle_01",
	"left_toe_ring_01", "left_toe_pinky_01",
	"right_toe_big_01", "right_toe_index_01", "right_toe_middle_01",
	"right_toe_ring_01", "right_toe_pinky_01",
]

## Named part groups for bulk operations (pose, animation, queries).
const PART_GROUPS: Dictionary = {
	"torso": ["pelvis", "spine_lower", "spine_mid", "spine_upper", "chest"],
	"head_all": ["neck", "head", "jaw", "tongue_base", "tongue_mid", "tongue_tip", "left_eye", "right_eye"],
	"left_arm": ["left_clavicle", "left_upper_arm", "left_forearm", "left_hand"],
	"right_arm": ["right_clavicle", "right_upper_arm", "right_forearm", "right_hand"],
	"left_leg": ["left_upper_leg", "left_lower_leg", "left_foot"],
	"right_leg": ["right_upper_leg", "right_lower_leg", "right_foot"],
}

## Maps Blender/MotionBuilder Full Rig bone names → ragdoll part names.
## Roll bones map to nearest structural part (twist helpers, no physics part).
## Face muscles map to head or jaw for structural mesh following.
const BONE_NAME_MAP: Dictionary = {
	# ── Root / Torso ────────────────────────────────────────────────────
	"Hips": "pelvis",
	"Spine": "spine_lower",
	"Spine1": "spine_mid",
	"Spine2": "spine_upper",
	"Spine3": "chest",
	"Neck": "neck",
	"Head": "head",
	# ── Left Arm (roll bones → nearest structural part) ─────────────────
	"LeftShoulder": "left_clavicle",
	"LeftArm": "left_upper_arm",
	"LeftArmRoll": "left_upper_arm",
	"LeftForeArm": "left_forearm",
	"LeftForeArmRoll": "left_forearm",
	"LeftHand": "left_hand",
	# ── Right Arm ───────────────────────────────────────────────────────
	"RightShoulder": "right_clavicle",
	"RightArm": "right_upper_arm",
	"RightArmRoll": "right_upper_arm",
	"RightForeArm": "right_forearm",
	"RightForeArmRoll": "right_forearm",
	"RightHand": "right_hand",
	# ── Left Fingers (4 segments: metacarpal + 3 phalanges) ─────────────
	"LeftHandThumb1": "left_thumb_00",
	"LeftHandThumb2": "left_thumb_01",
	"LeftHandThumb3": "left_thumb_02",
	"LeftHandThumb4": "left_thumb_03",
	"LeftHandIndex1": "left_index_00",
	"LeftHandIndex2": "left_index_01",
	"LeftHandIndex3": "left_index_02",
	"LeftHandIndex4": "left_index_03",
	"LeftHandMiddle1": "left_middle_00",
	"LeftHandMiddle2": "left_middle_01",
	"LeftHandMiddle3": "left_middle_02",
	"LeftHandMiddle4": "left_middle_03",
	"LeftHandRing1": "left_ring_00",
	"LeftHandRing2": "left_ring_01",
	"LeftHandRing3": "left_ring_02",
	"LeftHandRing4": "left_ring_03",
	"LeftHandPinky1": "left_pinky_00",
	"LeftHandPinky2": "left_pinky_01",
	"LeftHandPinky3": "left_pinky_02",
	"LeftHandPinky4": "left_pinky_03",
	# ── Right Fingers ───────────────────────────────────────────────────
	"RightHandThumb1": "right_thumb_00",
	"RightHandThumb2": "right_thumb_01",
	"RightHandThumb3": "right_thumb_02",
	"RightHandThumb4": "right_thumb_03",
	"RightHandIndex1": "right_index_00",
	"RightHandIndex2": "right_index_01",
	"RightHandIndex3": "right_index_02",
	"RightHandIndex4": "right_index_03",
	"RightHandMiddle1": "right_middle_00",
	"RightHandMiddle2": "right_middle_01",
	"RightHandMiddle3": "right_middle_02",
	"RightHandMiddle4": "right_middle_03",
	"RightHandRing1": "right_ring_00",
	"RightHandRing2": "right_ring_01",
	"RightHandRing3": "right_ring_02",
	"RightHandRing4": "right_ring_03",
	"RightHandPinky1": "right_pinky_00",
	"RightHandPinky2": "right_pinky_01",
	"RightHandPinky3": "right_pinky_02",
	"RightHandPinky4": "right_pinky_03",
	# ── Left Leg (roll bones → nearest structural part) ─────────────────
	"LeftUpLeg": "left_upper_leg",
	"LeftUpLegRoll": "left_upper_leg",
	"LeftLeg": "left_lower_leg",
	"LeftLegRoll": "left_lower_leg",
	"LeftFoot": "left_foot",
	# ── Right Leg ───────────────────────────────────────────────────────
	"RightUpLeg": "right_upper_leg",
	"RightUpLegRoll": "right_upper_leg",
	"RightLeg": "right_lower_leg",
	"RightLegRoll": "right_lower_leg",
	"RightFoot": "right_foot",
	# ── Left Toes (5 toes, 2-3 segments each) ──────────────────────────
	"LeftFootThumb1": "left_toe_big_01",
	"LeftFootThumb2": "left_toe_big_02",
	"LeftFootIndex1": "left_toe_index_01",
	"LeftFootIndex2": "left_toe_index_02",
	"LeftFootIndex3": "left_toe_index_03",
	"LeftFootMiddle1": "left_toe_middle_01",
	"LeftFootMiddle2": "left_toe_middle_02",
	"LeftFootMiddle3": "left_toe_middle_03",
	"LeftFootRing1": "left_toe_ring_01",
	"LeftFootRing2": "left_toe_ring_02",
	"LeftFootRing3": "left_toe_ring_03",
	"LeftFootPinky1": "left_toe_pinky_01",
	"LeftFootPinky2": "left_toe_pinky_02",
	"LeftFootPinky3": "left_toe_pinky_03",
	# ── Right Toes ──────────────────────────────────────────────────────
	"RightFootThumb1": "right_toe_big_01",
	"RightFootThumb2": "right_toe_big_02",
	"RightFootIndex1": "right_toe_index_01",
	"RightFootIndex2": "right_toe_index_02",
	"RightFootIndex3": "right_toe_index_03",
	"RightFootMiddle1": "right_toe_middle_01",
	"RightFootMiddle2": "right_toe_middle_02",
	"RightFootMiddle3": "right_toe_middle_03",
	"RightFootRing1": "right_toe_ring_01",
	"RightFootRing2": "right_toe_ring_02",
	"RightFootRing3": "right_toe_ring_03",
	"RightFootPinky1": "right_toe_pinky_01",
	"RightFootPinky2": "right_toe_pinky_02",
	"RightFootPinky3": "right_toe_pinky_03",
	# ── Face ────────────────────────────────────────────────────────────
	"jaw": "jaw",
	"tongue00": "tongue_base",
	"tongue01": "tongue_mid",
	"tongue02": "tongue_mid",
	"tongue03": "tongue_tip",
	"tongue04": "tongue_tip",
	"tongue05.L": "tongue_mid",
	"tongue05.R": "tongue_mid",
	"tongue06.L": "tongue_mid",
	"tongue06.R": "tongue_mid",
	"tongue07.L": "tongue_tip",
	"tongue07.R": "tongue_tip",
	"eye.L": "left_eye",
	"eye.R": "right_eye",
	# Face muscles → head or jaw (structural mapping, not physics-driven)
	"special04": "jaw",
	"oris02": "jaw",
	"oris01": "jaw",
	"oris06.L": "jaw",
	"oris06.R": "jaw",
	"oris07.L": "jaw",
	"oris07.R": "jaw",
	"levator02.L": "head",
	"levator02.R": "head",
	"levator03.L": "head",
	"levator03.R": "head",
	"levator04.L": "head",
	"levator04.R": "head",
	"levator05.L": "head",
	"levator05.R": "head",
	"special01": "head",
	"oris04.L": "head",
	"oris04.R": "head",
	"oris03.L": "head",
	"oris03.R": "head",
	"oris06": "head",
	"oris05": "head",
	"special03": "head",
	"levator06.L": "head",
	"levator06.R": "head",
	"special06.L": "head",
	"special06.R": "head",
	"special05.L": "head",
	"special05.R": "head",
	"orbicularis03.L": "head",
	"orbicularis03.R": "head",
	"orbicularis04.L": "head",
	"orbicularis04.R": "head",
	"temporalis01.L": "head",
	"temporalis01.R": "head",
	"temporalis02.L": "head",
	"temporalis02.R": "head",
	"oculi02.L": "head",
	"oculi02.R": "head",
	"oculi01.L": "head",
	"oculi01.R": "head",
	"risorius02.L": "head",
	"risorius02.R": "head",
	"risorius03.L": "head",
	"risorius03.R": "head",
	# ── Soft-tissue bones (added by blender-add-soft-tissue-bones.py) ──
	"left_inner_glute": "left_inner_glute",
	"left_outer_glute": "left_outer_glute",
	"right_inner_glute": "right_inner_glute",
	"right_outer_glute": "right_outer_glute",
	"left_breast_inner": "left_breast_inner",
	"left_breast_outer": "left_breast_outer",
	"left_breast_upper": "left_breast_upper",
	"left_breast_lower": "left_breast_lower",
	"right_breast_inner": "right_breast_inner",
	"right_breast_outer": "right_breast_outer",
	"right_breast_upper": "right_breast_upper",
	"right_breast_lower": "right_breast_lower",
	"left_breast_nipple": "left_breast_nipple",
	"right_breast_nipple": "right_breast_nipple",
	"penis_base": "penis_base",
	"penis_mid": "penis_mid",
	"penis_tip": "penis_tip",
	"scrotum_left": "scrotum_left",
	"scrotum_right": "scrotum_right",
	"labia_left": "labia_left",
	"labia_right": "labia_right",
	"clitoris": "clitoris",
	# ── Entrance ring bones ────────────────────────────────────────────
	"vaginal_ring_top": "vaginal_ring_top",
	"vaginal_ring_bot": "vaginal_ring_bot",
	"vaginal_ring_left": "vaginal_ring_left",
	"vaginal_ring_right": "vaginal_ring_right",
	"anal_ring_top": "anal_ring_top",
	"anal_ring_bot": "anal_ring_bot",
	"anal_ring_left": "anal_ring_left",
	"anal_ring_right": "anal_ring_right",
	# ── Vaginal passage ring bones (8 depths × 4 quadrants) ───────────
	"vaginal_passage_0_top": "vaginal_passage_0_top",
	"vaginal_passage_0_bot": "vaginal_passage_0_bot",
	"vaginal_passage_0_left": "vaginal_passage_0_left",
	"vaginal_passage_0_right": "vaginal_passage_0_right",
	"vaginal_passage_1_top": "vaginal_passage_1_top",
	"vaginal_passage_1_bot": "vaginal_passage_1_bot",
	"vaginal_passage_1_left": "vaginal_passage_1_left",
	"vaginal_passage_1_right": "vaginal_passage_1_right",
	"vaginal_passage_2_top": "vaginal_passage_2_top",
	"vaginal_passage_2_bot": "vaginal_passage_2_bot",
	"vaginal_passage_2_left": "vaginal_passage_2_left",
	"vaginal_passage_2_right": "vaginal_passage_2_right",
	"vaginal_passage_3_top": "vaginal_passage_3_top",
	"vaginal_passage_3_bot": "vaginal_passage_3_bot",
	"vaginal_passage_3_left": "vaginal_passage_3_left",
	"vaginal_passage_3_right": "vaginal_passage_3_right",
	"vaginal_passage_4_top": "vaginal_passage_4_top",
	"vaginal_passage_4_bot": "vaginal_passage_4_bot",
	"vaginal_passage_4_left": "vaginal_passage_4_left",
	"vaginal_passage_4_right": "vaginal_passage_4_right",
	"vaginal_passage_5_top": "vaginal_passage_5_top",
	"vaginal_passage_5_bot": "vaginal_passage_5_bot",
	"vaginal_passage_5_left": "vaginal_passage_5_left",
	"vaginal_passage_5_right": "vaginal_passage_5_right",
	"vaginal_passage_6_top": "vaginal_passage_6_top",
	"vaginal_passage_6_bot": "vaginal_passage_6_bot",
	"vaginal_passage_6_left": "vaginal_passage_6_left",
	"vaginal_passage_6_right": "vaginal_passage_6_right",
	"vaginal_passage_7_top": "vaginal_passage_7_top",
	"vaginal_passage_7_bot": "vaginal_passage_7_bot",
	"vaginal_passage_7_left": "vaginal_passage_7_left",
	"vaginal_passage_7_right": "vaginal_passage_7_right",
	# ── Anal passage ring bones (8 depths × 4 quadrants) ──────────────
	"anal_passage_0_top": "anal_passage_0_top",
	"anal_passage_0_bot": "anal_passage_0_bot",
	"anal_passage_0_left": "anal_passage_0_left",
	"anal_passage_0_right": "anal_passage_0_right",
	"anal_passage_1_top": "anal_passage_1_top",
	"anal_passage_1_bot": "anal_passage_1_bot",
	"anal_passage_1_left": "anal_passage_1_left",
	"anal_passage_1_right": "anal_passage_1_right",
	"anal_passage_2_top": "anal_passage_2_top",
	"anal_passage_2_bot": "anal_passage_2_bot",
	"anal_passage_2_left": "anal_passage_2_left",
	"anal_passage_2_right": "anal_passage_2_right",
	"anal_passage_3_top": "anal_passage_3_top",
	"anal_passage_3_bot": "anal_passage_3_bot",
	"anal_passage_3_left": "anal_passage_3_left",
	"anal_passage_3_right": "anal_passage_3_right",
	"anal_passage_4_top": "anal_passage_4_top",
	"anal_passage_4_bot": "anal_passage_4_bot",
	"anal_passage_4_left": "anal_passage_4_left",
	"anal_passage_4_right": "anal_passage_4_right",
	"anal_passage_5_top": "anal_passage_5_top",
	"anal_passage_5_bot": "anal_passage_5_bot",
	"anal_passage_5_left": "anal_passage_5_left",
	"anal_passage_5_right": "anal_passage_5_right",
	"anal_passage_6_top": "anal_passage_6_top",
	"anal_passage_6_bot": "anal_passage_6_bot",
	"anal_passage_6_left": "anal_passage_6_left",
	"anal_passage_6_right": "anal_passage_6_right",
	"anal_passage_7_top": "anal_passage_7_top",
	"anal_passage_7_bot": "anal_passage_7_bot",
	"anal_passage_7_left": "anal_passage_7_left",
	"anal_passage_7_right": "anal_passage_7_right",
	# ── Oral entrance ring bones ──────────────────────────────────────
	"oral_ring_top": "oral_ring_top",
	"oral_ring_bot": "oral_ring_bot",
	"oral_ring_left": "oral_ring_left",
	"oral_ring_right": "oral_ring_right",
	# ── Oral passage ring bones (5 depths × 4 quadrants) ──────────────
	"oral_passage_0_top": "oral_passage_0_top",
	"oral_passage_0_bot": "oral_passage_0_bot",
	"oral_passage_0_left": "oral_passage_0_left",
	"oral_passage_0_right": "oral_passage_0_right",
	"oral_passage_1_top": "oral_passage_1_top",
	"oral_passage_1_bot": "oral_passage_1_bot",
	"oral_passage_1_left": "oral_passage_1_left",
	"oral_passage_1_right": "oral_passage_1_right",
	"oral_passage_2_top": "oral_passage_2_top",
	"oral_passage_2_bot": "oral_passage_2_bot",
	"oral_passage_2_left": "oral_passage_2_left",
	"oral_passage_2_right": "oral_passage_2_right",
	"oral_passage_3_top": "oral_passage_3_top",
	"oral_passage_3_bot": "oral_passage_3_bot",
	"oral_passage_3_left": "oral_passage_3_left",
	"oral_passage_3_right": "oral_passage_3_right",
	"oral_passage_4_top": "oral_passage_4_top",
	"oral_passage_4_bot": "oral_passage_4_bot",
	"oral_passage_4_left": "oral_passage_4_left",
	"oral_passage_4_right": "oral_passage_4_right",
}

## Reverse: ragdoll part name → Blender bone name.
static var PART_TO_BONE_MAP: Dictionary = {}


static func init_reverse_bone_map() -> void:
	if not PART_TO_BONE_MAP.is_empty():
		return
	for blender_name: String in BONE_NAME_MAP:
		var our_name: String = BONE_NAME_MAP[blender_name] as String
		PART_TO_BONE_MAP[our_name] = blender_name


static func get_part_name_for_bone(bone_name: String) -> String:
	if bone_name == "":
		return ""
	if BONE_NAME_MAP.has(bone_name):
		return BONE_NAME_MAP[bone_name] as String
	var lower_name: String = bone_name.to_lower()
	if BONE_NAME_MAP.has(lower_name):
		return BONE_NAME_MAP[lower_name] as String
	return ""


static func get_blender_bone_name_for_part(part_name: String) -> String:
	if part_name == "":
		return ""
	init_reverse_bone_map()
	if PART_TO_BONE_MAP.has(part_name):
		return str(PART_TO_BONE_MAP[part_name])
	return ""


static func get_finger_seg_fracs(finger_index: int) -> PackedFloat64Array:
	match finger_index:
		0:
			return THUMB_SEG_FRACS
		1:
			return INDEX_SEG_FRACS
		2:
			return MIDDLE_SEG_FRACS
		3:
			return RING_SEG_FRACS
		4:
			return PINKY_SEG_FRACS
		_:
			return PackedFloat64Array()


static func get_toe_seg_fracs(toe_index: int) -> PackedFloat64Array:
	match toe_index:
		0:
			return TOE_BIG_SEG_FRACS
		1:
			return TOE_INDEX_SEG_FRACS
		2:
			return TOE_MIDDLE_SEG_FRACS
		3:
			return TOE_RING_SEG_FRACS
		4:
			return TOE_PINKY_SEG_FRACS
		_:
			return PackedFloat64Array()
