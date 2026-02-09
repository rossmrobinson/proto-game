class_name HumanoidRagdollBuilder
extends Node3D
## Procedurally constructs a fully-segmented humanoid ragdoll with anatomically
## correct joint limits. Each segment is a BodyPart (RigidBody3D) connected
## by Generic6DOFJoint3D nodes.
##
## Segments (~55-60 depending on body_type):
##   Torso:    pelvis, spine_lower, spine_upper, chest, neck, head
##   Chest:    L/R breast_mass + breast_nipple
##   Pelvis:   L/R glute, groin segments (body_type dependent)
##   Genitals: penis_base/mid/tip OR labia_l/r + clitoris, scrotum_l/r
##   Passages: anal canal chain, vaginal canal chain (FEMALE/ANDROGYNOUS)
##   Arms:     L/R clavicle, upper_arm, forearm, hand
##   Hands:    L/R thumb(3), index(3), middle(3), ring(3), pinky(3) = 30 total
##   Legs:     L/R upper_leg, lower_leg, foot, toes
##
## Attach this to an empty Node3D. It builds everything in _ready().
## The "root" body part is the pelvis — the rest hang from it.

signal ragdoll_built()

@export_group("Body Scale")
## Total height of the humanoid in meters.
@export var body_height: float = 1.75
## Overall scale multiplier for mass.
@export var mass_scale: float = 1.0

@export_group("Body Type")
enum BodyType { MALE, FEMALE, ANDROGYNOUS }
## Determines genital anatomy and internal passage configuration.
@export var body_type: BodyType = BodyType.MALE

@export_group("Visual")
## Color for the placeholder capsule/box meshes.
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)
## Whether to draw debug collision meshes.
@export var show_meshes: bool = true

# ── Runtime References ───────────────────────────────────────────────────────
## Dictionary mapping part_name -> BodyPart node
var parts: Dictionary = {}
## All joints created
var joints: Array[Generic6DOFJoint3D] = []
## Maps joint key ("parent_to_child") -> Generic6DOFJoint3D for animator lookup
var joint_map: Dictionary = {}

# ── Proportions (fraction of body_height) ────────────────────────────────────
# These come from anatomical proportions (roughly based on an ideal 7.5 head model)
const HEAD_HEIGHT_FRAC: float = 0.13
const NECK_HEIGHT_FRAC: float = 0.03
const CHEST_HEIGHT_FRAC: float = 0.10
const SPINE_UPPER_FRAC: float = 0.07
const SPINE_LOWER_FRAC: float = 0.07
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
const PASSAGE_SEGMENTS_ANAL: int = 3
const PASSAGE_SEGMENTS_VAGINAL: int = 4

# Finger dimensions (fraction of body_height)
const FINGER_RADIUS_FRAC: float = 0.006
# Per-finger segment lengths [proximal, middle, distal] as fraction of body_height
const THUMB_SEG_FRACS: PackedFloat64Array = [0.016, 0.018, 0.014]
const INDEX_SEG_FRACS: PackedFloat64Array = [0.013, 0.012, 0.014]
const MIDDLE_SEG_FRACS: PackedFloat64Array = [0.017, 0.014, 0.013]
const RING_SEG_FRACS: PackedFloat64Array = [0.015, 0.013, 0.014]
const PINKY_SEG_FRACS: PackedFloat64Array = [0.011, 0.008, 0.010]

# Finger X offsets from hand centre (fraction of body_height), thumb is special
const FINGER_X_OFFSETS: PackedFloat64Array = [0.0, 0.01, 0.0, -0.007, -0.018]
# Finger Z offsets from hand front (fraction of body_height)
const FINGER_Z_OFFSETS: PackedFloat64Array = [0.02, 0.0, -0.005, -0.012, -0.02]
const FINGER_NAMES: PackedStringArray = ["thumb", "index", "middle", "ring", "pinky"]
const FINGER_SEG_NAMES: PackedStringArray = ["01", "02", "03"]


## Part names that should be placed on the internal-only physics layer.
const INTERNAL_PARTS: PackedStringArray = [
	"anal_passage_0", "anal_passage_1", "anal_passage_2",
	"vaginal_passage_0", "vaginal_passage_1", "vaginal_passage_2", "vaginal_passage_3",
]

## Soft-tissue parts placed on layer 5 (NPC_SoftTissue) instead of layer 3.
const SOFT_TISSUE_PARTS: PackedStringArray = [
	"left_breast_mass", "right_breast_mass",
	"left_breast_nipple", "right_breast_nipple",
	"left_glute", "right_glute",
	"penis_base", "penis_mid", "penis_tip",
	"scrotum_left", "scrotum_right",
	"labia_left", "labia_right", "clitoris",
]

## Maps Blender bone names → our ragdoll part names for import/animation.
const BONE_NAME_MAP: Dictionary = {
	"Root": "pelvis",
	"pelvis": "pelvis",
	"spine_01": "spine_lower",
	"spine_02": "spine_upper",
	"spine_03": "chest",
	"neck_01": "neck",
	"head": "head",
	"clavicle_l": "left_clavicle",
	"clavicle_r": "right_clavicle",
	"upperarm_l": "left_upper_arm",
	"upperarm_r": "right_upper_arm",
	"lowerarm_l": "left_forearm",
	"lowerarm_r": "right_forearm",
	"hand_l": "left_hand",
	"hand_r": "right_hand",
	"thumb_01_l": "left_thumb_01",
	"thumb_02_l": "left_thumb_02",
	"thumb_03_l": "left_thumb_03",
	"thumb_01_r": "right_thumb_01",
	"thumb_02_r": "right_thumb_02",
	"thumb_03_r": "right_thumb_03",
	"index_01_l": "left_index_01",
	"index_02_l": "left_index_02",
	"index_03_l": "left_index_03",
	"index_01_r": "right_index_01",
	"index_02_r": "right_index_02",
	"index_03_r": "right_index_03",
	"middle_01_l": "left_middle_01",
	"middle_02_l": "left_middle_02",
	"middle_03_l": "left_middle_03",
	"middle_01_r": "right_middle_01",
	"middle_02_r": "right_middle_02",
	"middle_03_r": "right_middle_03",
	"ring_01_l": "left_ring_01",
	"ring_02_l": "left_ring_02",
	"ring_03_l": "left_ring_03",
	"ring_01_r": "right_ring_01",
	"ring_02_r": "right_ring_02",
	"ring_03_r": "right_ring_03",
	"pinky_01_l": "left_pinky_01",
	"pinky_02_l": "left_pinky_02",
	"pinky_03_l": "left_pinky_03",
	"pinky_01_r": "right_pinky_01",
	"pinky_02_r": "right_pinky_02",
	"pinky_03_r": "right_pinky_03",
	"thigh_l": "left_upper_leg",
	"thigh_r": "right_upper_leg",
	"calf_l": "left_lower_leg",
	"calf_r": "right_lower_leg",
	"foot_l": "left_foot",
	"foot_r": "right_foot",
	"ball_l": "left_toes",
	"ball_r": "right_toes",
}

## Reverse: ragdoll part name → Blender bone name.
static var PART_TO_BONE_MAP: Dictionary = {}

## Lookup helper arrays for finger construction (populated in _init_finger_fracs).
var _finger_frac_table: Array = []


func _ready() -> void:
	_init_finger_fracs()
	_init_reverse_bone_map()
	_build_ragdoll()
	_apply_collision_exclusions()
	_assign_soft_tissue_layers()
	_assign_internal_layers()
	ragdoll_built.emit()


func _init_finger_fracs() -> void:
	_finger_frac_table = [
		THUMB_SEG_FRACS,
		INDEX_SEG_FRACS,
		MIDDLE_SEG_FRACS,
		RING_SEG_FRACS,
		PINKY_SEG_FRACS,
	]


static func _init_reverse_bone_map() -> void:
	if not PART_TO_BONE_MAP.is_empty():
		return
	for blender_name: String in BONE_NAME_MAP:
		var our_name: String = BONE_NAME_MAP[blender_name] as String
		PART_TO_BONE_MAP[our_name] = blender_name


# ──────────────────────────────────────────────────────────────────────────────
#  BUILD PIPELINE
# ──────────────────────────────────────────────────────────────────────────────

func _build_ragdoll() -> void:
	var h: float = body_height

	# ── Torso chain (bottom-up) ──────────────────────────────────────────
	var pelvis: BodyPart = _create_part("pelvis", "Pelvis",
		Vector3(0.0, PELVIS_HEIGHT_FRAC * h * 0.5 + UPPER_LEG_FRAC * h + LOWER_LEG_FRAC * h + FOOT_FRAC * h, 0.0),
		_capsule_shape(0.12 * h, PELVIS_HEIGHT_FRAC * h),
		8.0 * mass_scale, 0.9)

	var spine_base_y: float = pelvis.position.y + PELVIS_HEIGHT_FRAC * h * 0.5
	var spine_lower: BodyPart = _create_part("spine_lower", "Lower Spine",
		Vector3(0.0, spine_base_y + SPINE_LOWER_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.10 * h, SPINE_LOWER_FRAC * h),
		5.0 * mass_scale, 0.85)

	var spine_upper: BodyPart = _create_part("spine_upper", "Upper Spine",
		Vector3(0.0, spine_lower.position.y + SPINE_LOWER_FRAC * h * 0.5 + SPINE_UPPER_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.11 * h, SPINE_UPPER_FRAC * h),
		5.0 * mass_scale, 0.85)

	var chest: BodyPart = _create_part("chest", "Chest",
		Vector3(0.0, spine_upper.position.y + SPINE_UPPER_FRAC * h * 0.5 + CHEST_HEIGHT_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.14 * h, CHEST_HEIGHT_FRAC * h),
		10.0 * mass_scale, 0.9)

	var neck: BodyPart = _create_part("neck", "Neck",
		Vector3(0.0, chest.position.y + CHEST_HEIGHT_FRAC * h * 0.5 + NECK_HEIGHT_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.04 * h, NECK_HEIGHT_FRAC * h),
		2.0 * mass_scale, 0.7)

	var head: BodyPart = _create_part("head", "Head",
		Vector3(0.0, neck.position.y + NECK_HEIGHT_FRAC * h * 0.5 + HEAD_HEIGHT_FRAC * h * 0.5, 0.0),
		_sphere_shape(HEAD_HEIGHT_FRAC * h * 0.5),
		4.5 * mass_scale, 0.95)

	# ── Spine joints ────────────────────────────────────────────────────
	# Pelvis -> Spine Lower: limited flexion
	_create_joint(pelvis, spine_lower,
		Vector3(0, spine_base_y, 0),
		Vector3(-20, -15, -10), Vector3(20, 15, 10))

	# Spine Lower -> Upper: moderate flex
	_create_joint(spine_lower, spine_upper,
		Vector3(0, spine_lower.position.y + SPINE_LOWER_FRAC * h * 0.5, 0),
		Vector3(-15, -15, -8), Vector3(25, 15, 8))

	# Spine Upper -> Chest: limited
	_create_joint(spine_upper, chest,
		Vector3(0, spine_upper.position.y + SPINE_UPPER_FRAC * h * 0.5, 0),
		Vector3(-10, -10, -5), Vector3(15, 10, 5))

	# Chest -> Neck: moderate
	_create_joint(chest, neck,
		Vector3(0, chest.position.y + CHEST_HEIGHT_FRAC * h * 0.5, 0),
		Vector3(-15, -20, -10), Vector3(15, 20, 10))

	# Neck -> Head: wide range
	_create_joint(neck, head,
		Vector3(0, neck.position.y + NECK_HEIGHT_FRAC * h * 0.5, 0),
		Vector3(-40, -55, -25), Vector3(55, 55, 25))

	# ── Breasts (both sides — mass + nipple) ────────────────────────────
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var breast_x: float = side_sign * BREAST_OFFSET_X_FRAC * h
		var breast_y: float = chest.position.y - CHEST_HEIGHT_FRAC * h * 0.1
		var breast_z: float = BREAST_OFFSET_Z_FRAC * h

		var breast_mass: BodyPart = _create_part(
			"%s_breast_mass" % side, "%s Breast" % side.capitalize(),
			Vector3(breast_x, breast_y, breast_z),
			_sphere_shape(BREAST_RADIUS_FRAC * h),
			0.4 * mass_scale, 0.3)

		# Soft spring joint for natural jiggle
		_create_soft_joint(chest, breast_mass,
			Vector3(breast_x, breast_y + BREAST_RADIUS_FRAC * h * 0.5, breast_z * 0.5),
			Vector3(-15, -10, -15), Vector3(15, 10, 15),
			8.0, 1.5)

		# Nipple — small tip part on front of breast
		var nipple_pos: Vector3 = Vector3(breast_x, breast_y, breast_z + BREAST_RADIUS_FRAC * h * 0.9)
		var nipple: BodyPart = _create_part(
			"%s_breast_nipple" % side, "%s Nipple" % side.capitalize(),
			nipple_pos,
			_sphere_shape(NIPPLE_RADIUS_FRAC * h),
			0.02 * mass_scale, 0.15)

		_create_soft_joint(breast_mass, nipple,
			Vector3(breast_x, breast_y, breast_z + BREAST_RADIUS_FRAC * h * 0.5),
			Vector3(-8, -8, -8), Vector3(8, 8, 8),
			15.0, 3.0)

	# ── Glutes (both sides) ─────────────────────────────────────────────
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var glute_x: float = side_sign * GLUTE_OFFSET_X_FRAC * h
		var glute_y: float = pelvis.position.y - PELVIS_HEIGHT_FRAC * h * 0.15
		var glute_z: float = GLUTE_OFFSET_Z_FRAC * h

		var glute: BodyPart = _create_part(
			"%s_glute" % side, "%s Glute" % side.capitalize(),
			Vector3(glute_x, glute_y, glute_z),
			_sphere_shape(GLUTE_RADIUS_FRAC * h),
			1.2 * mass_scale, 0.5)

		# Moderate spring joint — glutes move less freely than breasts
		_create_soft_joint(pelvis, glute,
			Vector3(glute_x, glute_y + GLUTE_RADIUS_FRAC * h * 0.3, glute_z * 0.3),
			Vector3(-10, -8, -10), Vector3(10, 8, 10),
			12.0, 2.5)

	# ── Groin anatomy (body_type dependent) ──────────────────────────────
	var groin_anchor_y: float = pelvis.position.y - PELVIS_HEIGHT_FRAC * h * 0.45
	var groin_z: float = 0.04 * h  # Front of pelvis

	if body_type == BodyType.MALE or body_type == BodyType.ANDROGYNOUS:
		# Penis — 3-segment articulated chain (base → mid → tip)
		var seg_len: float = PENIS_SEGMENT_LENGTH_FRAC * h
		var penis_base: BodyPart = _create_part(
			"penis_base", "Penis Base",
			Vector3(0.0, groin_anchor_y - seg_len * 0.5, groin_z),
			_capsule_shape(PENIS_RADIUS_FRAC * h, seg_len),
			0.06 * mass_scale, 0.25)

		_create_soft_joint(pelvis, penis_base,
			Vector3(0.0, groin_anchor_y, groin_z),
			Vector3(-90, -45, -45), Vector3(45, 45, 45),
			5.0, 1.2)

		var penis_mid: BodyPart = _create_part(
			"penis_mid", "Penis Mid",
			Vector3(0.0, groin_anchor_y - seg_len * 1.5, groin_z),
			_capsule_shape(PENIS_RADIUS_FRAC * h * 0.9, seg_len),
			0.05 * mass_scale, 0.25)

		_create_soft_joint(penis_base, penis_mid,
			Vector3(0.0, groin_anchor_y - seg_len, groin_z),
			Vector3(-40, -25, -25), Vector3(40, 25, 25),
			4.0, 1.0)

		var penis_tip: BodyPart = _create_part(
			"penis_tip", "Penis Tip",
			Vector3(0.0, groin_anchor_y - seg_len * 2.5, groin_z),
			_capsule_shape(PENIS_RADIUS_FRAC * h * 0.8, seg_len),
			0.04 * mass_scale, 0.2)

		_create_soft_joint(penis_mid, penis_tip,
			Vector3(0.0, groin_anchor_y - seg_len * 2.0, groin_z),
			Vector3(-30, -20, -20), Vector3(30, 20, 20),
			3.5, 0.8)

		# Scrotum — independent left/right
		for scr_sign: float in [-1.0, 1.0]:
			var scr_side: String = "left" if scr_sign < 0 else "right"
			var scr_x: float = scr_sign * SCROTUM_OFFSET_X_FRAC * h
			var scr_y: float = groin_anchor_y - seg_len * 0.3

			var scrotum: BodyPart = _create_part(
				"scrotum_%s" % scr_side, "%s Scrotum" % scr_side.capitalize(),
				Vector3(scr_x, scr_y, groin_z * 0.5),
				_sphere_shape(SCROTUM_RADIUS_FRAC * h),
				0.05 * mass_scale, 0.2)

			_create_soft_joint(pelvis, scrotum,
				Vector3(scr_x * 0.5, scr_y + SCROTUM_RADIUS_FRAC * h * 0.5, groin_z * 0.4),
				Vector3(-30, -20, -20), Vector3(30, 20, 20),
				5.0, 1.5)

	if body_type == BodyType.FEMALE or body_type == BodyType.ANDROGYNOUS:
		# Labia — left and right
		for lab_sign: float in [-1.0, 1.0]:
			var lab_side: String = "left" if lab_sign < 0 else "right"
			var lab_x: float = lab_sign * LABIA_OFFSET_X_FRAC * h

			var labia: BodyPart = _create_part(
				"labia_%s" % lab_side, "%s Labia" % lab_side.capitalize(),
				Vector3(lab_x, groin_anchor_y, groin_z * 0.8),
				_box_shape(Vector3(0.008 * h, LABIA_HEIGHT_FRAC * h, 0.012 * h)),
				0.02 * mass_scale, 0.15)

			_create_soft_joint(pelvis, labia,
				Vector3(lab_x * 0.5, groin_anchor_y + LABIA_HEIGHT_FRAC * h * 0.5, groin_z * 0.4),
				Vector3(-5, -3, -3), Vector3(5, 3, 3),
				15.0, 3.0)

		# Clitoris — tiny sphere between labia
		var clitoris: BodyPart = _create_part(
			"clitoris", "Clitoris",
			Vector3(0.0, groin_anchor_y + LABIA_HEIGHT_FRAC * h * 0.35, groin_z * 0.9),
			_sphere_shape(CLITORIS_RADIUS_FRAC * h),
			0.01 * mass_scale, 0.1)

		_create_soft_joint(pelvis, clitoris,
			Vector3(0.0, groin_anchor_y + LABIA_HEIGHT_FRAC * h * 0.4, groin_z * 0.5),
			Vector3(-3, -3, -3), Vector3(3, 3, 3),
			20.0, 4.0)

		# Vaginal canal — chain of soft segments going inward/upward
		# Anchor from the labia region
		_create_passage_chain("vaginal", pelvis,
			Vector3(0.0, groin_anchor_y, groin_z * 0.5),
			Vector3(0.0, 0.3, -0.9).normalized(),
			PASSAGE_SEGMENTS_VAGINAL, h)

	# ── Anal passage (all body types) ───────────────────────────────────
	var anal_anchor_y: float = pelvis.position.y - PELVIS_HEIGHT_FRAC * h * 0.4
	var anal_z: float = GLUTE_OFFSET_Z_FRAC * h * 0.5  # Between glutes

	_create_passage_chain("anal", pelvis,
		Vector3(0.0, anal_anchor_y, anal_z),
		Vector3(0.0, 0.4, -0.85).normalized(),  # Angled inward and slightly up
		PASSAGE_SEGMENTS_ANAL, h)

	# ── Arms (both sides) ───────────────────────────────────────────────
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var shoulder_x: float = side_sign * SHOULDER_WIDTH_FRAC * h

		var clavicle: BodyPart = _create_part(
			"%s_clavicle" % side, "%s Clavicle" % side.capitalize(),
			Vector3(shoulder_x * 0.5, chest.position.y + CHEST_HEIGHT_FRAC * h * 0.3, 0.0),
			_capsule_shape_horizontal(0.02 * h, CLAVICLE_FRAC * h),
			1.5 * mass_scale, 0.6)

		var upper_arm: BodyPart = _create_part(
			"%s_upper_arm" % side, "%s Upper Arm" % side.capitalize(),
			Vector3(shoulder_x, chest.position.y + CHEST_HEIGHT_FRAC * h * 0.3 - UPPER_ARM_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.04 * h, UPPER_ARM_FRAC * h),
			2.5 * mass_scale, 0.6)

		var forearm: BodyPart = _create_part(
			"%s_forearm" % side, "%s Forearm" % side.capitalize(),
			Vector3(shoulder_x, upper_arm.position.y - UPPER_ARM_FRAC * h * 0.5 - FOREARM_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.035 * h, FOREARM_FRAC * h),
			1.8 * mass_scale, 0.55)

		var hand: BodyPart = _create_part(
			"%s_hand" % side, "%s Hand" % side.capitalize(),
			Vector3(shoulder_x, forearm.position.y - FOREARM_FRAC * h * 0.5 - HAND_FRAC * h * 0.5, 0.0),
			_box_shape(Vector3(0.05 * h, HAND_FRAC * h, 0.03 * h)),
			0.5 * mass_scale, 0.4)

		# ── Fully articulated fingers (5 × 3 phalanges per hand) ───────
		var hand_base_y: float = hand.position.y - HAND_FRAC * h * 0.5
		var finger_r: float = FINGER_RADIUS_FRAC * h

		for f_idx: int in range(FINGER_NAMES.size()):
			var f_name: String = FINGER_NAMES[f_idx]
			var seg_lengths: Array = _finger_frac_table[f_idx]
			var f_x_off: float = FINGER_X_OFFSETS[f_idx] * h * side_sign
			var f_z_off: float = FINGER_Z_OFFSETS[f_idx] * h
			var is_thumb: bool = (f_idx == 0)

			# Anchor: where the finger attaches to the hand
			var anchor_y: float = hand_base_y if not is_thumb else hand.position.y + HAND_FRAC * h * 0.1
			var anchor_pos: Vector3 = Vector3(
				shoulder_x + f_x_off,
				anchor_y,
				f_z_off)

			var prev_part: BodyPart = hand
			var joint_pos: Vector3 = anchor_pos

			for seg_idx: int in range(FINGER_SEG_NAMES.size()):
				var seg_name: String = FINGER_SEG_NAMES[seg_idx]
				var seg_len: float = (seg_lengths[seg_idx] as float) * h
				var part_name: String = "%s_%s_%s" % [side, f_name, seg_name]
				var display_name: String = "%s %s %s" % [
					side.capitalize(), f_name.capitalize(), seg_name]

				var seg_pos: Vector3 = Vector3(
					joint_pos.x,
					joint_pos.y - seg_len * 0.5,
					joint_pos.z)

				# Taper radius slightly for distal phalanges
				var r_scale: float = 1.0 - seg_idx * 0.1
				var seg_part: BodyPart = _create_part(
					part_name, display_name, seg_pos,
					_capsule_shape(finger_r * r_scale, seg_len),
					0.05 * mass_scale, 0.2)

				# Joint limits differ by finger and segment
				var lo: Vector3
				var hi: Vector3
				if is_thumb:
					if seg_idx == 0:
						lo = Vector3(-30, -40 * side_sign, -25)
						hi = Vector3(60, 40 * side_sign, 25)
					else:
						lo = Vector3(-10, -5, -5)
						hi = Vector3(80, 5, 5)
				else:
					if seg_idx == 0:
						lo = Vector3(-15, -8, -10)
						hi = Vector3(90, 8, 10)
					else:
						lo = Vector3(0, -3, -3)
						hi = Vector3(110, 3, 3)

				_create_joint(prev_part, seg_part, joint_pos, lo, hi)

				# Advance chain
				joint_pos = Vector3(seg_pos.x, seg_pos.y - seg_len * 0.5, seg_pos.z)
				prev_part = seg_part

		# ── Arm joints ──────────────────────────────────────────────
		# Chest -> Clavicle
		_create_joint(chest, clavicle,
			Vector3(shoulder_x * 0.1, clavicle.position.y, 0),
			Vector3(-5, -10, -5), Vector3(15, 10, 5))

		# Clavicle -> Upper Arm (shoulder — wide range, mirrored for left/right)
		var sh_y_lo: float = -60.0 if side_sign > 0 else -90.0
		var sh_y_hi: float = 90.0 if side_sign > 0 else 60.0
		var sh_z_lo: float = -80.0 if side_sign > 0 else -30.0
		var sh_z_hi: float = 30.0 if side_sign > 0 else 80.0
		_create_joint(clavicle, upper_arm,
			Vector3(shoulder_x, clavicle.position.y, 0),
			Vector3(-90, sh_y_lo, sh_z_lo), Vector3(90, sh_y_hi, sh_z_hi))

		# Upper Arm -> Forearm (elbow — hinge-like)
		_create_joint(upper_arm, forearm,
			Vector3(shoulder_x, upper_arm.position.y - UPPER_ARM_FRAC * h * 0.5, 0),
			Vector3(0, -5, -5), Vector3(145, 5, 5))

		# Forearm -> Hand (wrist)
		_create_joint(forearm, hand,
			Vector3(shoulder_x, forearm.position.y - FOREARM_FRAC * h * 0.5, 0),
			Vector3(-70, -20, -40), Vector3(70, 20, 40))

	# ── Legs (both sides) ───────────────────────────────────────────────
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var hip_x: float = side_sign * HIP_WIDTH_FRAC * h

		var upper_leg: BodyPart = _create_part(
			"%s_upper_leg" % side, "%s Upper Leg" % side.capitalize(),
			Vector3(hip_x, pelvis.position.y - PELVIS_HEIGHT_FRAC * h * 0.5 - UPPER_LEG_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.06 * h, UPPER_LEG_FRAC * h),
			6.0 * mass_scale, 0.7)

		var lower_leg: BodyPart = _create_part(
			"%s_lower_leg" % side, "%s Lower Leg" % side.capitalize(),
			Vector3(hip_x, upper_leg.position.y - UPPER_LEG_FRAC * h * 0.5 - LOWER_LEG_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.045 * h, LOWER_LEG_FRAC * h),
			4.0 * mass_scale, 0.65)

		var foot: BodyPart = _create_part(
			"%s_foot" % side, "%s Foot" % side.capitalize(),
			Vector3(hip_x, FOOT_FRAC * h * 0.5, 0.03 * h),
			_box_shape(Vector3(0.05 * h, FOOT_FRAC * h, 0.10 * h)),
			1.0 * mass_scale, 0.5)

		var toes: BodyPart = _create_part(
			"%s_toes" % side, "%s Toes" % side.capitalize(),
			Vector3(hip_x, 0.015 * h, 0.08 * h + 0.05 * h),
			_box_shape(Vector3(0.04 * h, 0.015 * h, 0.03 * h)),
			0.2 * mass_scale, 0.3)

		# ── Leg joints ──────────────────────────────────────────────
		# Pelvis -> Upper Leg (hip — ball and socket)
		_create_joint(pelvis, upper_leg,
			Vector3(hip_x, pelvis.position.y - PELVIS_HEIGHT_FRAC * h * 0.5, 0),
			Vector3(-100, -30, -40), Vector3(30, 45, 40))

		# Upper Leg -> Lower Leg (knee — hinge)
		_create_joint(upper_leg, lower_leg,
			Vector3(hip_x, upper_leg.position.y - UPPER_LEG_FRAC * h * 0.5, 0),
			Vector3(-140, -3, -3), Vector3(0, 3, 3))

		# Lower Leg -> Foot (ankle)
		_create_joint(lower_leg, foot,
			Vector3(hip_x, FOOT_FRAC * h, 0.03 * h),
			Vector3(-40, -15, -20), Vector3(25, 15, 20))

		# Foot -> Toes
		_create_joint(foot, toes,
			Vector3(hip_x, 0.015 * h, 0.08 * h),
			Vector3(-30, -5, -5), Vector3(50, 5, 5))


# ──────────────────────────────────────────────────────────────────────────────
#  FACTORY HELPERS
# ──────────────────────────────────────────────────────────────────────────────

func _create_part(p_name: String, p_display: String, pos: Vector3,
		shape: Shape3D, p_mass: float, p_grab_stiffness: float,
		p_grabbable: bool = true) -> BodyPart:
	var part: BodyPart = BodyPart.new()
	part.name = p_name.to_pascal_case()
	part.part_name = p_name
	part.display_name = p_display
	part.mass = p_mass
	part.grab_stiffness = p_grab_stiffness
	part.is_grabbable = p_grabbable
	part.position = pos
	part.continuous_cd = true  # Prevent tunneling for small parts

	# Collision shape
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	# Rotate capsules to be vertical (they default to Y-up which is correct)
	part.add_child(col)

	# Visual mesh (placeholder)
	if show_meshes:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.mesh = _shape_to_mesh(shape)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = body_color
		mat.roughness = 0.7
		mesh_inst.material_override = mat
		part.add_child(mesh_inst)

	add_child(part)
	parts[p_name] = part
	return part


func _create_joint(parent_part: BodyPart, child_part: BodyPart,
		anchor_pos: Vector3,
		angular_lower_deg: Vector3, angular_upper_deg: Vector3) -> Generic6DOFJoint3D:
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "Joint_%s_to_%s" % [parent_part.part_name, child_part.part_name]
	joint.position = anchor_pos

	var map_key: String = "%s_to_%s" % [parent_part.part_name, child_part.part_name]

	joint.node_a = parent_part.get_path()
	joint.node_b = child_part.get_path()

	# Lock linear axes (bones shouldn't slide apart)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Angular limits (degrees -> radians)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(angular_lower_deg.x))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(angular_upper_deg.x))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(angular_lower_deg.y))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(angular_upper_deg.y))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(angular_lower_deg.z))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(angular_upper_deg.z))

	add_child(joint)
	joints.append(joint)
	joint_map[map_key] = joint

	# Track adjacency
	parent_part.connected_parts.append(child_part)
	child_part.connected_parts.append(parent_part)

	return joint


## Creates a joint with angular spring behavior for soft tissue (breasts, glutes, genitals).
## Spring joints resist deformation but allow natural movement.
func _create_soft_joint(parent_part: BodyPart, child_part: BodyPart,
		anchor_pos: Vector3,
		angular_lower_deg: Vector3, angular_upper_deg: Vector3,
		spring_stiffness: float = 8.0,
		spring_damping: float = 1.5) -> Generic6DOFJoint3D:
	var joint: Generic6DOFJoint3D = _create_joint(
		parent_part, child_part, anchor_pos,
		angular_lower_deg, angular_upper_deg)

	# Enable angular springs on all 3 axes — gives elastic "return to rest" behavior
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, spring_stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, spring_damping)

	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, spring_stiffness)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, spring_damping)

	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, spring_stiffness)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, spring_damping)

	return joint


## Builds a chain of small, soft-jointed segments to simulate an internal passage.
## Each segment is non-grabbable, very low mass, high damping, with spring return.
func _create_passage_chain(passage_name: String, anchor_part: BodyPart,
		start_pos: Vector3, direction: Vector3,
		segment_count: int, h: float) -> Array[BodyPart]:
	var seg_radius: float = PASSAGE_SEGMENT_RADIUS_FRAC * h
	var seg_length: float = PASSAGE_SEGMENT_LENGTH_FRAC * h
	var chain: Array[BodyPart] = []
	var prev_part: BodyPart = anchor_part

	for i: int in range(segment_count):
		var offset: Vector3 = direction * seg_length * (i + 1)
		var seg_pos: Vector3 = start_pos + offset
		var seg_name: String = "%s_passage_%d" % [passage_name, i]
		var seg_display: String = "%s Passage %d" % [passage_name.capitalize(), i + 1]

		var seg: BodyPart = _create_part(seg_name, seg_display, seg_pos,
			_capsule_shape(seg_radius, seg_length),
			0.02 * mass_scale, 0.1, false)  # Not grabbable

		# High damping for internal tissue — resists wild oscillation
		seg.linear_damp = 8.0
		seg.angular_damp = 10.0

		# Very soft spring joints — elastic, returns to rest shape
		var joint_pos: Vector3 = start_pos + direction * seg_length * (i + 0.5)
		_create_soft_joint(prev_part, seg, joint_pos,
			Vector3(-15, -15, -15), Vector3(15, 15, 15),
			12.0, 4.0)

		chain.append(seg)
		prev_part = seg

	return chain


# ──────────────────────────────────────────────────────────────────────────────
#  COLLISION EXCLUSIONS
# ──────────────────────────────────────────────────────────────────────────────

## Add collision exceptions between every directly-jointed pair of body parts.
## Adjacent parts are held together by joints — if they also collide via the
## physics broadphase they'll jitter violently.  Non-adjacent parts (e.g.
## hand vs thigh on the same NPC) remain free to collide for posing.
func _apply_collision_exclusions() -> void:
	for joint: Generic6DOFJoint3D in joints:
		var a: BodyPart = get_node_or_null(joint.node_a) as BodyPart
		var b: BodyPart = get_node_or_null(joint.node_b) as BodyPart
		if a != null and b != null:
			a.add_collision_exception_with(b)
			b.add_collision_exception_with(a)


## Move passage segments to layer 6 (NPC_Internal) so they don't interact
## with external physics.  They keep mask layer 3 so rays/queries can reach them.
func _assign_internal_layers() -> void:
	for part_name_key: String in parts:
		if part_name_key in INTERNAL_PARTS:
			var part: BodyPart = parts[part_name_key] as BodyPart
			# Clear external layers
			part.collision_layer = 0
			part.set_collision_layer_value(6, true)  # NPC_Internal
			# Only collide with other internals + equipment
			part.collision_mask = 0
			part.set_collision_mask_value(6, true)  # Other internal segments
			part.set_collision_mask_value(7, true)  # Equipment (piercings, toys)


## Move soft-tissue parts (breasts, glutes, genitals) to layer 5 (NPC_SoftTissue).
## They keep the same broad mask as skeletal parts but live on their own layer so
## gameplay queries can distinguish a grab on a breast vs. a grab on the ribcage.
func _assign_soft_tissue_layers() -> void:
	for part_name_key: String in parts:
		if part_name_key in SOFT_TISSUE_PARTS:
			var part: BodyPart = parts[part_name_key] as BodyPart
			# Move off NPC_External (3), onto NPC_SoftTissue (5).
			# Keep Interactable (4) so targeting/grab queries still find them.
			part.collision_layer = 0
			part.set_collision_layer_value(4, true)  # Interactable
			part.set_collision_layer_value(5, true)  # NPC_SoftTissue
			# Mask: Environment + NPC_External + Interactable + SoftTissue + Equipment
			# Do NOT include layer 2 (Player) — NPC parts must not push the player
			part.collision_mask = 0
			part.set_collision_mask_value(1, true)  # Environment
			part.set_collision_mask_value(3, true)  # NPC_External
			part.set_collision_mask_value(4, true)  # Interactable
			part.set_collision_mask_value(5, true)  # Other soft tissue
			part.set_collision_mask_value(7, true)  # Equipment


# ──────────────────────────────────────────────────────────────────────────────
#  SHAPE FACTORIES
# ──────────────────────────────────────────────────────────────────────────────

func _capsule_shape(radius: float, height: float) -> CapsuleShape3D:
	var s: CapsuleShape3D = CapsuleShape3D.new()
	s.radius = radius
	s.height = maxf(height, radius * 2.0 + 0.01)
	return s


func _capsule_shape_horizontal(radius: float, length: float) -> CapsuleShape3D:
	# Capsules in Godot are Y-up. For horizontal, we rotate the CollisionShape.
	# We'll handle rotation in _create_part by detecting this.
	# For now, create standard capsule — the clavicle part will be rotated.
	var s: CapsuleShape3D = CapsuleShape3D.new()
	s.radius = radius
	s.height = maxf(length, radius * 2.0 + 0.01)
	return s


func _sphere_shape(radius: float) -> SphereShape3D:
	var s: SphereShape3D = SphereShape3D.new()
	s.radius = radius
	return s


func _box_shape(extents: Vector3) -> BoxShape3D:
	var s: BoxShape3D = BoxShape3D.new()
	s.size = extents
	return s


func _shape_to_mesh(shape: Shape3D) -> Mesh:
	if shape is CapsuleShape3D:
		var cap: CapsuleShape3D = shape as CapsuleShape3D
		var m: CapsuleMesh = CapsuleMesh.new()
		m.radius = cap.radius
		m.height = cap.height
		return m
	elif shape is SphereShape3D:
		var sph: SphereShape3D = shape as SphereShape3D
		var m: SphereMesh = SphereMesh.new()
		m.radius = sph.radius
		m.height = sph.radius * 2.0
		return m
	elif shape is BoxShape3D:
		var bx: BoxShape3D = shape as BoxShape3D
		var m: BoxMesh = BoxMesh.new()
		m.size = bx.size
		return m
	return BoxMesh.new()


# ──────────────────────────────────────────────────────────────────────────────
#  PUBLIC API
# ──────────────────────────────────────────────────────────────────────────────

## Get a specific body part by name.
func get_part(p_name: String) -> BodyPart:
	return parts.get(p_name, null) as BodyPart


## Get all body parts as an array.
func get_all_parts() -> Array:
	return parts.values()


## Apply an explosion force from a point to all body parts.
func apply_explosion(origin: Vector3, force: float, radius: float) -> void:
	for part: BodyPart in parts.values():
		var dist: float = part.global_position.distance_to(origin)
		if dist < radius:
			var falloff: float = 1.0 - (dist / radius)
			var dir: Vector3 = (part.global_position - origin).normalized()
			part.apply_central_impulse(dir * force * falloff)


## Get the center of mass of the entire ragdoll (approximate).
func get_center_of_mass() -> Vector3:
	var total_mass: float = 0.0
	var weighted_pos: Vector3 = Vector3.ZERO
	for part: BodyPart in parts.values():
		weighted_pos += part.global_position * part.mass
		total_mass += part.mass
	if total_mass > 0.0:
		return weighted_pos / total_mass
	return global_position
