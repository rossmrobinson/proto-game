class_name HumanoidRagdollBuilder
extends Node3D

const RAGDOLL_PROPORTIONS = preload("res://scripts/npc/ragdoll_proportions.gd")
const RAGDOLL_COLLISION_CONFIG = preload("res://scripts/npc/ragdoll_collision_config.gd")
## Procedurally constructs a fully-segmented humanoid ragdoll with anatomically
## correct joint limits. Each segment is a BodyPart (RigidBody3D) connected
## by Generic6DOFJoint3D nodes.
##
## Segments (~140-190 depending on body_type):
##   Torso:    pelvis, spine_lower, spine_mid, spine_upper, chest, neck, head
##   Face:     jaw, tongue (3 segments), L/R eye
##   Chest:    L/R breast (inner/outer/upper/lower) + nipple = 10 parts
##   Pelvis:   L/R inner_glute + outer_glute, groin segments (body_type dependent)
##   Genitals: penis_base/mid/tip OR labia_l/r + clitoris, scrotum_l/r
##   Passages: ring-of-4 entrance (4) + 8 depths × 4 quadrants (32) per tunnel
##   Oral:     ring-of-4 entrance (4) + 5 depths × 4 quadrants (20) = 24 parts
##   Arms:     L/R clavicle, upper_arm, forearm, hand
##   Hands:    L/R thumb(4), index(4), middle(4), ring(4), pinky(4) = 40 total
##   Legs:     L/R upper_leg, lower_leg, foot
##   Feet:     L/R big_toe(2), index_toe(3), middle_toe(3), ring_toe(3), pinky_toe(3) = 28 total
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

@export_group("Level of Detail")
## Controls how many physics bodies are built.
## FULL: All parts including fingers, toes, face, and passage chains (~190).
## MEDIUM: Limbs + soft tissue, no fingers/toes/face/passages (~45).
## MINIMAL: Skeleton chain only, no soft tissue (~23).
enum DetailLevel { FULL, MEDIUM, MINIMAL }
@export var detail_level: DetailLevel = DetailLevel.FULL

@export_group("Sleep Policy")
## Allow reduced LOD ragdolls to sleep to lower physics cost.
@export var enable_lod_sleep_policy: bool = true
## Keep torso/core chain awake in reduced LOD to avoid full-body freeze artifacts.
@export var keep_torso_awake_on_reduced_lod: bool = true

# ── Runtime References ───────────────────────────────────────────────────────
## Dictionary mapping part_name -> BodyPart node
var parts: Dictionary = {}
## All joints created
var joints: Array[Generic6DOFJoint3D] = []
## Maps joint key ("parent_to_child") -> Generic6DOFJoint3D for animator lookup
var joint_map: Dictionary = {}
## Maps child part_name -> Generic6DOFJoint3D that connects it to parent.
## Used by SkeletonBinding to drive motor targets.
var child_to_joint: Dictionary = {}

func _ready() -> void:
	_build_ragdoll()
	_apply_sleep_policy()
	RAGDOLL_COLLISION_CONFIG.apply_collision_exclusions(parts)
	RAGDOLL_COLLISION_CONFIG.restore_breast_collisions(parts)
	RAGDOLL_COLLISION_CONFIG.restore_self_touch_collisions(parts)
	RAGDOLL_COLLISION_CONFIG.restore_penis_passage_collisions(parts)
	RAGDOLL_COLLISION_CONFIG.assign_soft_tissue_layers(parts)
	RAGDOLL_COLLISION_CONFIG.assign_internal_layers(parts)
	RAGDOLL_COLLISION_CONFIG.assign_fine_motor_layers(parts)
	# Freeze all parts so they don't interact with physics until the
	# skeleton binding snaps them to bone poses and ramps springs.
	for part_name_key: String in parts:
		var part: BodyPart = parts[part_name_key] as BodyPart
		part.freeze = true
		part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ragdoll_built.emit()

# ──────────────────────────────────────────────────────────────────────────────
#  BUILD PIPELINE
# ──────────────────────────────────────────────────────────────────────────────

func _build_ragdoll() -> void:
	var h: float = body_height
	_build_torso(h)
	if detail_level == DetailLevel.FULL:
		_build_face(h)
	if detail_level != DetailLevel.MINIMAL:
		_build_breasts(h)
		_build_glutes(h)
		_build_groin(h)
	_build_arms(h)
	_build_legs(h)


## Construct the core torso chain: pelvis → spine × 3 → chest → neck → head,
## plus all spine joints.
func _build_torso(h: float) -> void:
	var pelvis: BodyPart = _create_part("pelvis", "Pelvis",
		Vector3(0.0, RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.UPPER_LEG_FRAC * h + RAGDOLL_PROPORTIONS.LOWER_LEG_FRAC * h + RAGDOLL_PROPORTIONS.FOOT_FRAC * h, 0.0),
		_capsule_shape(0.12 * h, RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h),
		12.0 * mass_scale, 0.9)

	var spine_base_y: float = pelvis.position.y + RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.5
	var spine_lower: BodyPart = _create_part("spine_lower", "Lower Spine",
		Vector3(0.0, spine_base_y + RAGDOLL_PROPORTIONS.SPINE_LOWER_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.10 * h, RAGDOLL_PROPORTIONS.SPINE_LOWER_FRAC * h),
		8.0 * mass_scale, 0.85)

	var spine_mid: BodyPart = _create_part("spine_mid", "Mid Spine",
		Vector3(0.0, spine_lower.position.y + RAGDOLL_PROPORTIONS.SPINE_LOWER_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.SPINE_MID_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.105 * h, RAGDOLL_PROPORTIONS.SPINE_MID_FRAC * h),
		8.0 * mass_scale, 0.85)

	var spine_upper: BodyPart = _create_part("spine_upper", "Upper Spine",
		Vector3(0.0, spine_mid.position.y + RAGDOLL_PROPORTIONS.SPINE_MID_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.SPINE_UPPER_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.11 * h, RAGDOLL_PROPORTIONS.SPINE_UPPER_FRAC * h),
		8.0 * mass_scale, 0.85)

	var chest: BodyPart = _create_part("chest", "Chest",
		Vector3(0.0, spine_upper.position.y + RAGDOLL_PROPORTIONS.SPINE_UPPER_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.14 * h, RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h),
		15.0 * mass_scale, 0.9)

	var neck: BodyPart = _create_part("neck", "Neck",
		Vector3(0.0, chest.position.y + RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.NECK_HEIGHT_FRAC * h * 0.5, 0.0),
		_capsule_shape(0.04 * h, RAGDOLL_PROPORTIONS.NECK_HEIGHT_FRAC * h),
		3.0 * mass_scale, 0.7)

	var head: BodyPart = _create_part("head", "Head",
		Vector3(0.0, neck.position.y + RAGDOLL_PROPORTIONS.NECK_HEIGHT_FRAC * h * 0.5 + RAGDOLL_PROPORTIONS.HEAD_HEIGHT_FRAC * h * 0.5, 0.0),
		_sphere_shape(RAGDOLL_PROPORTIONS.HEAD_HEIGHT_FRAC * h * 0.5),
		4.5 * mass_scale, 0.95)

	# ── Spine joints ────────────────────────────────────────────────────
	# Pelvis -> Spine Lower: limited flexion
	_create_joint(pelvis, spine_lower,
		Vector3(0, spine_base_y, 0),
		Vector3(-20, -15, -10), Vector3(20, 15, 10))

	# Spine Lower -> Spine Mid: moderate flex
	_create_joint(spine_lower, spine_mid,
		Vector3(0, spine_lower.position.y + RAGDOLL_PROPORTIONS.SPINE_LOWER_FRAC * h * 0.5, 0),
		Vector3(-12, -12, -6), Vector3(18, 12, 6))

	# Spine Mid -> Spine Upper: moderate flex
	_create_joint(spine_mid, spine_upper,
		Vector3(0, spine_mid.position.y + RAGDOLL_PROPORTIONS.SPINE_MID_FRAC * h * 0.5, 0),
		Vector3(-12, -12, -6), Vector3(18, 12, 6))

	# Spine Upper -> Chest: limited
	_create_joint(spine_upper, chest,
		Vector3(0, spine_upper.position.y + RAGDOLL_PROPORTIONS.SPINE_UPPER_FRAC * h * 0.5, 0),
		Vector3(-10, -10, -5), Vector3(15, 10, 5))

	# Chest -> Neck: moderate
	_create_joint(chest, neck,
		Vector3(0, chest.position.y + RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.5, 0),
		Vector3(-15, -20, -10), Vector3(15, 20, 10))

	# Neck -> Head: wide range
	_create_joint(neck, head,
		Vector3(0, neck.position.y + RAGDOLL_PROPORTIONS.NECK_HEIGHT_FRAC * h * 0.5, 0),
		Vector3(-40, -55, -25), Vector3(55, 55, 25))


## Construct jaw, tongue (3-seg), eyes, and oral passage chain.
func _build_face(h: float) -> void:
	var head: BodyPart = parts["head"]
	# Jaw — hinged below ears, swings open/closed
	var jaw_y: float = head.position.y - RAGDOLL_PROPORTIONS.HEAD_HEIGHT_FRAC * h * 0.3
	var jaw_z: float = RAGDOLL_PROPORTIONS.EYE_OFFSET_Z_FRAC * h * 0.4
	var jaw_part: BodyPart = _create_part("jaw", "Jaw",
		Vector3(0.0, jaw_y, jaw_z),
		_box_shape(Vector3(RAGDOLL_PROPORTIONS.JAW_WIDTH_FRAC * h, RAGDOLL_PROPORTIONS.JAW_HEIGHT_FRAC * h, RAGDOLL_PROPORTIONS.JAW_DEPTH_FRAC * h)),
		1.5 * mass_scale, 0.3, true, true, true)

	# Jaw hinge — mostly pitch (open/close), limited yaw (side to side)
	_create_joint(head, jaw_part,
		Vector3(0.0, head.position.y - RAGDOLL_PROPORTIONS.HEAD_HEIGHT_FRAC * h * 0.15, 0.0),
		Vector3(-35, -5, -3), Vector3(5, 5, 3))

	# Tongue — 3-segment chain from jaw going inward
	var tongue_dir: Vector3 = Vector3(0.0, -0.2, 0.9).normalized()
	var tongue_start: Vector3 = Vector3(0.0, jaw_y + RAGDOLL_PROPORTIONS.JAW_HEIGHT_FRAC * h * 0.2, jaw_z)
	var tongue_seg_len: float = RAGDOLL_PROPORTIONS.TONGUE_SEG_LENGTH_FRAC * h
	var tongue_r: float = RAGDOLL_PROPORTIONS.TONGUE_RADIUS_FRAC * h
	var tongue_names: PackedStringArray = ["tongue_base", "tongue_mid", "tongue_tip"]
	var prev_tongue: BodyPart = jaw_part
	var tongue_joint_pos: Vector3 = tongue_start

	for ti: int in range(tongue_names.size()):
		var tn: String = tongue_names[ti]
		var t_offset: Vector3 = tongue_dir * tongue_seg_len * (ti + 0.5)
		var t_pos: Vector3 = tongue_start + t_offset
		var t_r_scale: float = 1.0 - ti * 0.15
		var tongue_seg: BodyPart = _create_part(tn, tn.capitalize().replace("_", " "),
			t_pos,
			_capsule_shape(tongue_r * t_r_scale, tongue_seg_len),
			0.3 * mass_scale, 0.1, false, false, false)
		tongue_seg.linear_damp = 6.0
		tongue_seg.angular_damp = 8.0

		_create_soft_joint(prev_tongue, tongue_seg,
			tongue_joint_pos,
			Vector3(-15, -10, -10), Vector3(15, 10, 10),
			10.0, 3.0)

		tongue_joint_pos = t_pos + tongue_dir * tongue_seg_len * 0.5
		prev_tongue = tongue_seg

	# Eyes — small spheres in eye sockets
	for eye_sign: float in [-1.0, 1.0]:
		var eye_side: String = "left" if eye_sign < 0 else "right"
		var eye_x: float = eye_sign * RAGDOLL_PROPORTIONS.EYE_OFFSET_X_FRAC * h
		var eye_y: float = head.position.y + RAGDOLL_PROPORTIONS.HEAD_HEIGHT_FRAC * h * 0.05
		var eye_z: float = RAGDOLL_PROPORTIONS.EYE_OFFSET_Z_FRAC * h

		var eye_part: BodyPart = _create_part(
			"%s_eye" % eye_side, "%s Eye" % eye_side.capitalize(),
			Vector3(eye_x, eye_y, eye_z),
			_sphere_shape(RAGDOLL_PROPORTIONS.EYE_RADIUS_FRAC * h),
			0.3 * mass_scale, 0.05, false, false, false)

		# Tight ball-in-socket — eyes look around but don't pop out
		_create_joint(head, eye_part,
			Vector3(eye_x, eye_y, eye_z * 0.5),
			Vector3(-25, -35, -5), Vector3(15, 35, 5))

	# ── Oral passage (throat) ───────────────────────────────────────────
	# Entrance ring sits at the back of the mouth (behind the jaw).
	# Direction goes backward and slightly downward into the throat/neck.
	var oral_anchor_y: float = jaw_y + RAGDOLL_PROPORTIONS.JAW_HEIGHT_FRAC * h * 0.1
	var oral_anchor_z: float = jaw_z - RAGDOLL_PROPORTIONS.JAW_DEPTH_FRAC * h * 0.3
	_create_passage_chain("oral", jaw_part,
		Vector3(0.0, oral_anchor_y, oral_anchor_z),
		Vector3(0.0, -0.3, -0.9).normalized(),  # Back and slightly down
		RAGDOLL_PROPORTIONS.ORAL_PASSAGE_SEGMENTS, h)


## Breast quadrant assembly: 4 sub-spheres + nipple per side, cross-linked
## for cohesion and deformation.
func _build_breasts(h: float) -> void:
	var chest: BodyPart = parts["chest"]
	var br: float = RAGDOLL_PROPORTIONS.BREAST_RADIUS_FRAC * h
	var qr: float = br * RAGDOLL_PROPORTIONS.BREAST_QUAD_RADIUS_SCALE  # quadrant sphere radius

	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var breast_cx: float = side_sign * RAGDOLL_PROPORTIONS.BREAST_OFFSET_X_FRAC * h
		var breast_cy: float = chest.position.y - RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.1
		var breast_cz: float = RAGDOLL_PROPORTIONS.BREAST_OFFSET_Z_FRAC * h

		# Build quadrant offset table (local to breast centre)
		# Inner/outer are along X (sign-flipped per side), upper/lower along Y.
		var quad_names: PackedStringArray = ["inner", "outer", "upper", "lower"]
		var quad_offsets: Array[Vector3] = [
			Vector3(side_sign * RAGDOLL_PROPORTIONS.BREAST_QUAD_INNER_X_FRAC * br, 0.0, 0.0),
			Vector3(side_sign * RAGDOLL_PROPORTIONS.BREAST_QUAD_OUTER_X_FRAC * br, 0.0, 0.0),
			Vector3(0.0, RAGDOLL_PROPORTIONS.BREAST_QUAD_UPPER_Y_FRAC * br, 0.0),
			Vector3(0.0, RAGDOLL_PROPORTIONS.BREAST_QUAD_LOWER_Y_FRAC * br, 0.0),
		]
		# Lower quadrant gets more mass (sag).
		var quad_masses: PackedFloat64Array = [0.8, 0.8, 0.7, 1.0]

		var quad_parts: Array[BodyPart] = []
		for qi: int in range(quad_names.size()):
			var qn: String = quad_names[qi]
			var q_pos: Vector3 = Vector3(breast_cx, breast_cy, breast_cz) + quad_offsets[qi]
			var q_mass: float = (quad_masses[qi] as float) * mass_scale

			var qpart: BodyPart = _create_part(
				"%s_breast_%s" % [side, qn],
				"%s Breast %s" % [side.capitalize(), qn.capitalize()],
				q_pos,
				_sphere_shape(qr),
				q_mass, 0.3)

			# Each quadrant jointed to chest with soft spring
			var anchor: Vector3 = Vector3(breast_cx, breast_cy + br * 0.4, breast_cz * 0.4) \
				+ quad_offsets[qi] * 0.3
			_create_soft_joint(chest, qpart, anchor,
				Vector3(-15, -10, -15), Vector3(15, 10, 15),
				8.0, 1.5)
			quad_parts.append(qpart)

		# Cross-link adjacent quadrants for cohesion (inner↔upper, upper↔outer,
		# outer↔lower, lower↔inner — forming a ring).
		var link_pairs: Array[Vector2i] = [
			Vector2i(0, 2), Vector2i(2, 1), Vector2i(1, 3), Vector2i(3, 0)]
		for lp: Vector2i in link_pairs:
			var a: BodyPart = quad_parts[lp.x]
			var b: BodyPart = quad_parts[lp.y]
			var mid: Vector3 = (a.position + b.position) * 0.5
			_create_soft_joint(a, b, mid,
				Vector3(-8, -8, -8), Vector3(8, 8, 8),
				6.0, 1.5)

		# Nipple — small sphere on the front, jointed to a phantom anchor
		# between the 4 quadrant parts (the inner quadrant provides the
		# physical parent joint since it's closest to front-centre).
		var nipple_pos: Vector3 = Vector3(breast_cx, breast_cy, breast_cz + br * 0.9)
		var nipple: BodyPart = _create_part(
			"%s_breast_nipple" % side, "%s Nipple" % side.capitalize(),
			nipple_pos,
			_sphere_shape(RAGDOLL_PROPORTIONS.NIPPLE_RADIUS_FRAC * h),
			0.5 * mass_scale, 0.15)

		# Jointed to inner quadrant (closest to nipple position)
		_create_soft_joint(quad_parts[0], nipple,
			(quad_parts[0].position + nipple_pos) * 0.5,
			Vector3(-5, -5, -5), Vector3(5, 5, 5),
			15.0, 3.0)


## Glute inner/outer split per side — cleft/spread deformation.
func _build_glutes(h: float) -> void:
	var pelvis: BodyPart = parts["pelvis"]
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var glute_y: float = pelvis.position.y - RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.15
		var glute_z: float = RAGDOLL_PROPORTIONS.GLUTE_OFFSET_Z_FRAC * h

		# Inner glute — closer to cleft
		var inner_x: float = side_sign * RAGDOLL_PROPORTIONS.GLUTE_INNER_OFFSET_X_FRAC * h
		var inner_glute: BodyPart = _create_part(
			"%s_inner_glute" % side, "%s Inner Glute" % side.capitalize(),
			Vector3(inner_x, glute_y, glute_z),
			_sphere_shape(RAGDOLL_PROPORTIONS.GLUTE_RADIUS_FRAC * h * 0.6),
			1.5 * mass_scale, 0.4)

		_create_soft_joint(pelvis, inner_glute,
			Vector3(inner_x, glute_y + RAGDOLL_PROPORTIONS.GLUTE_RADIUS_FRAC * h * 0.3, glute_z * 0.3),
			Vector3(-8, -5, -8), Vector3(8, 5, 8),
			14.0, 3.0)

		# Outer glute — further from cleft, larger
		var outer_x: float = side_sign * RAGDOLL_PROPORTIONS.GLUTE_OUTER_OFFSET_X_FRAC * h
		var outer_glute: BodyPart = _create_part(
			"%s_outer_glute" % side, "%s Outer Glute" % side.capitalize(),
			Vector3(outer_x, glute_y, glute_z),
			_sphere_shape(RAGDOLL_PROPORTIONS.GLUTE_RADIUS_FRAC * h * 0.8),
			2.0 * mass_scale, 0.5)

		_create_soft_joint(pelvis, outer_glute,
			Vector3(outer_x, glute_y + RAGDOLL_PROPORTIONS.GLUTE_RADIUS_FRAC * h * 0.3, glute_z * 0.3),
			Vector3(-10, -8, -10), Vector3(10, 8, 10),
			12.0, 2.5)

		# Cross-link inner↔outer for cohesion
		var mid_x: float = (inner_x + outer_x) * 0.5
		_create_soft_joint(inner_glute, outer_glute,
			Vector3(mid_x, glute_y, glute_z),
			Vector3(-5, -5, -5), Vector3(5, 5, 5),
			8.0, 2.0)


## Groin anatomy: penis/scrotum (male), labia/clitoris/vaginal (female),
## anal passage (all). Body-type dependent.
func _build_groin(h: float) -> void:
	var pelvis: BodyPart = parts["pelvis"]
	var groin_anchor_y: float = pelvis.position.y - RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.45
	var groin_z: float = 0.04 * h  # Front of pelvis

	if body_type == BodyType.MALE or body_type == BodyType.ANDROGYNOUS:
		# Penis — 3-segment articulated chain (base → mid → tip)
		var seg_len: float = RAGDOLL_PROPORTIONS.PENIS_SEGMENT_LENGTH_FRAC * h
		var penis_base: BodyPart = _create_part(
			"penis_base", "Penis Base",
			Vector3(0.0, groin_anchor_y - seg_len * 0.5, groin_z),
			_capsule_shape(RAGDOLL_PROPORTIONS.PENIS_RADIUS_FRAC * h, seg_len),
			0.5 * mass_scale, 0.25)

		_create_soft_joint(pelvis, penis_base,
			Vector3(0.0, groin_anchor_y, groin_z),
			Vector3(-90, -45, -45), Vector3(45, 45, 45),
			5.0, 1.2)

		var penis_mid: BodyPart = _create_part(
			"penis_mid", "Penis Mid",
			Vector3(0.0, groin_anchor_y - seg_len * 1.5, groin_z),
			_capsule_shape(RAGDOLL_PROPORTIONS.PENIS_RADIUS_FRAC * h * 0.9, seg_len),
			0.5 * mass_scale, 0.25)

		_create_soft_joint(penis_base, penis_mid,
			Vector3(0.0, groin_anchor_y - seg_len, groin_z),
			Vector3(-40, -25, -25), Vector3(40, 25, 25),
			4.0, 1.0)

		var penis_tip: BodyPart = _create_part(
			"penis_tip", "Penis Tip",
			Vector3(0.0, groin_anchor_y - seg_len * 2.5, groin_z),
			_capsule_shape(RAGDOLL_PROPORTIONS.PENIS_RADIUS_FRAC * h * 0.8, seg_len),
			0.5 * mass_scale, 0.2)

		_create_soft_joint(penis_mid, penis_tip,
			Vector3(0.0, groin_anchor_y - seg_len * 2.0, groin_z),
			Vector3(-30, -20, -20), Vector3(30, 20, 20),
			3.5, 0.8)

		# Scrotum — independent left/right
		for scr_sign: float in [-1.0, 1.0]:
			var scr_side: String = "left" if scr_sign < 0 else "right"
			var scr_x: float = scr_sign * RAGDOLL_PROPORTIONS.SCROTUM_OFFSET_X_FRAC * h
			var scr_y: float = groin_anchor_y - seg_len * 0.3

			var scrotum: BodyPart = _create_part(
				"scrotum_%s" % scr_side, "%s Scrotum" % scr_side.capitalize(),
				Vector3(scr_x, scr_y, groin_z * 0.5),
				_sphere_shape(RAGDOLL_PROPORTIONS.SCROTUM_RADIUS_FRAC * h),
				0.5 * mass_scale, 0.2)

			_create_soft_joint(pelvis, scrotum,
				Vector3(scr_x * 0.5, scr_y + RAGDOLL_PROPORTIONS.SCROTUM_RADIUS_FRAC * h * 0.5, groin_z * 0.4),
				Vector3(-30, -20, -20), Vector3(30, 20, 20),
				5.0, 1.5)

	if body_type == BodyType.FEMALE or body_type == BodyType.ANDROGYNOUS:
		# Labia — left and right
		for lab_sign: float in [-1.0, 1.0]:
			var lab_side: String = "left" if lab_sign < 0 else "right"
			var lab_x: float = lab_sign * RAGDOLL_PROPORTIONS.LABIA_OFFSET_X_FRAC * h

			var labia: BodyPart = _create_part(
				"labia_%s" % lab_side, "%s Labia" % lab_side.capitalize(),
				Vector3(lab_x, groin_anchor_y, groin_z * 0.8),
				_box_shape(Vector3(0.008 * h, RAGDOLL_PROPORTIONS.LABIA_HEIGHT_FRAC * h, 0.012 * h)),
				0.5 * mass_scale, 0.15)

			_create_soft_joint(pelvis, labia,
				Vector3(lab_x * 0.5, groin_anchor_y + RAGDOLL_PROPORTIONS.LABIA_HEIGHT_FRAC * h * 0.5, groin_z * 0.4),
				Vector3(-5, -3, -3), Vector3(5, 3, 3),
				15.0, 3.0)

		# Clitoris — tiny sphere between labia
		var clitoris: BodyPart = _create_part(
			"clitoris", "Clitoris",
			Vector3(0.0, groin_anchor_y + RAGDOLL_PROPORTIONS.LABIA_HEIGHT_FRAC * h * 0.35, groin_z * 0.9),
			_sphere_shape(RAGDOLL_PROPORTIONS.CLITORIS_RADIUS_FRAC * h),
			0.5 * mass_scale, 0.1)

		_create_soft_joint(pelvis, clitoris,
			Vector3(0.0, groin_anchor_y + RAGDOLL_PROPORTIONS.LABIA_HEIGHT_FRAC * h * 0.4, groin_z * 0.5),
			Vector3(-3, -3, -3), Vector3(3, 3, 3),
			20.0, 4.0)

		# Vaginal canal — only at FULL detail (passage chains are expensive)
		if detail_level == DetailLevel.FULL:
			_create_passage_chain("vaginal", pelvis,
				Vector3(0.0, groin_anchor_y, groin_z * 0.5),
				Vector3(0.0, 0.3, -0.9).normalized(),
				RAGDOLL_PROPORTIONS.PASSAGE_SEGMENTS_VAGINAL, h)

	# ── Anal passage (all body types) ───────────────────────────────────
	var anal_anchor_y: float = pelvis.position.y - RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.4
	var anal_z: float = RAGDOLL_PROPORTIONS.GLUTE_OFFSET_Z_FRAC * h * 0.5  # Between glutes

	if detail_level == DetailLevel.FULL:
		_create_passage_chain("anal", pelvis,
			Vector3(0.0, anal_anchor_y, anal_z),
			Vector3(0.0, 0.4, -0.85).normalized(),  # Angled inward and slightly up
			RAGDOLL_PROPORTIONS.PASSAGE_SEGMENTS_ANAL, h)


## Arms: clavicle → upper arm → forearm → hand → 5×4 finger phalanges,
## plus shoulder/elbow/wrist joints.
func _build_arms(h: float) -> void:
	var chest: BodyPart = parts["chest"]
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var shoulder_x: float = side_sign * RAGDOLL_PROPORTIONS.SHOULDER_WIDTH_FRAC * h

		var clavicle: BodyPart = _create_part(
			"%s_clavicle" % side, "%s Clavicle" % side.capitalize(),
			Vector3(shoulder_x * 0.5, chest.position.y + RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.3, 0.0),
			_capsule_shape_horizontal(0.02 * h, RAGDOLL_PROPORTIONS.CLAVICLE_FRAC * h),
			2.0 * mass_scale, 0.6)

		var upper_arm: BodyPart = _create_part(
			"%s_upper_arm" % side, "%s Upper Arm" % side.capitalize(),
			Vector3(shoulder_x, chest.position.y + RAGDOLL_PROPORTIONS.CHEST_HEIGHT_FRAC * h * 0.3 - RAGDOLL_PROPORTIONS.UPPER_ARM_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.04 * h, RAGDOLL_PROPORTIONS.UPPER_ARM_FRAC * h),
			4.0 * mass_scale, 0.6)

		var forearm: BodyPart = _create_part(
			"%s_forearm" % side, "%s Forearm" % side.capitalize(),
			Vector3(shoulder_x, upper_arm.position.y - RAGDOLL_PROPORTIONS.UPPER_ARM_FRAC * h * 0.5 - RAGDOLL_PROPORTIONS.FOREARM_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.035 * h, RAGDOLL_PROPORTIONS.FOREARM_FRAC * h),
			2.5 * mass_scale, 0.55)

		var hand: BodyPart = _create_part(
			"%s_hand" % side, "%s Hand" % side.capitalize(),
			Vector3(shoulder_x, forearm.position.y - RAGDOLL_PROPORTIONS.FOREARM_FRAC * h * 0.5 - RAGDOLL_PROPORTIONS.HAND_FRAC * h * 0.5, 0.0),
			_box_shape(Vector3(0.05 * h, RAGDOLL_PROPORTIONS.HAND_FRAC * h, 0.03 * h)),
			1.5 * mass_scale, 0.4)

		# ── Fully articulated fingers (FULL detail only) ──────────
		if detail_level == DetailLevel.FULL:
			_build_hand_fingers(h, hand, shoulder_x, side, side_sign)

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
			Vector3(shoulder_x, upper_arm.position.y - RAGDOLL_PROPORTIONS.UPPER_ARM_FRAC * h * 0.5, 0),
			Vector3(0, -5, -5), Vector3(145, 5, 5))

		# Forearm -> Hand (wrist)
		_create_joint(forearm, hand,
			Vector3(shoulder_x, forearm.position.y - RAGDOLL_PROPORTIONS.FOREARM_FRAC * h * 0.5, 0),
			Vector3(-70, -20, -40), Vector3(70, 20, 40))


## Legs: upper leg → lower leg → foot → 5×2-3 toe phalanges,
## plus hip/knee/ankle joints.
func _build_legs(h: float) -> void:
	var pelvis: BodyPart = parts["pelvis"]
	for side_sign: float in [-1.0, 1.0]:
		var side: String = "left" if side_sign < 0 else "right"
		var hip_x: float = side_sign * RAGDOLL_PROPORTIONS.HIP_WIDTH_FRAC * h

		var upper_leg: BodyPart = _create_part(
			"%s_upper_leg" % side, "%s Upper Leg" % side.capitalize(),
			Vector3(hip_x, pelvis.position.y - RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.5 - RAGDOLL_PROPORTIONS.UPPER_LEG_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.06 * h, RAGDOLL_PROPORTIONS.UPPER_LEG_FRAC * h),
			8.0 * mass_scale, 0.7)

		var lower_leg: BodyPart = _create_part(
			"%s_lower_leg" % side, "%s Lower Leg" % side.capitalize(),
			Vector3(hip_x, upper_leg.position.y - RAGDOLL_PROPORTIONS.UPPER_LEG_FRAC * h * 0.5 - RAGDOLL_PROPORTIONS.LOWER_LEG_FRAC * h * 0.5, 0.0),
			_capsule_shape(0.045 * h, RAGDOLL_PROPORTIONS.LOWER_LEG_FRAC * h),
			4.0 * mass_scale, 0.65)

		var foot: BodyPart = _create_part(
			"%s_foot" % side, "%s Foot" % side.capitalize(),
			Vector3(hip_x, RAGDOLL_PROPORTIONS.FOOT_FRAC * h * 0.5, 0.03 * h),
			_box_shape(Vector3(0.05 * h, RAGDOLL_PROPORTIONS.FOOT_FRAC * h, 0.10 * h)),
			2.0 * mass_scale, 0.5)

		var toes: BodyPart = _create_part(
			"%s_toes" % side, "%s Toes" % side.capitalize(),
			Vector3(hip_x, 0.015 * h, 0.08 * h + 0.05 * h),
			_box_shape(Vector3(0.04 * h, 0.015 * h, 0.03 * h)),
			1.0 * mass_scale, 0.3)

		# ── Individual toes (FULL detail only) ─────────────────────
		if detail_level == DetailLevel.FULL:
			_build_foot_toes(h, foot, hip_x, side, side_sign)

		# ── Leg joints ──────────────────────────────────────────────
		# Pelvis -> Upper Leg (hip — ball and socket)
		_create_joint(pelvis, upper_leg,
			Vector3(hip_x, pelvis.position.y - RAGDOLL_PROPORTIONS.PELVIS_HEIGHT_FRAC * h * 0.5, 0),
			Vector3(-100, -30, -40), Vector3(30, 45, 40))

		# Upper Leg -> Lower Leg (knee — hinge)
		_create_joint(upper_leg, lower_leg,
			Vector3(hip_x, upper_leg.position.y - RAGDOLL_PROPORTIONS.UPPER_LEG_FRAC * h * 0.5, 0),
			Vector3(-140, -3, -3), Vector3(0, 3, 3))

		# Lower Leg -> Foot (ankle)
		_create_joint(lower_leg, foot,
			Vector3(hip_x, RAGDOLL_PROPORTIONS.FOOT_FRAC * h, 0.03 * h),
			Vector3(-40, -15, -20), Vector3(25, 15, 20))

		# Foot -> Toes (legacy single-toes joint for backward compat)
		_create_joint(foot, toes,
			Vector3(hip_x, 0.015 * h, 0.08 * h),
			Vector3(-30, -5, -5), Vector3(50, 5, 5))


## Build all 5×4 finger phalanges for one hand. Only called at FULL detail.
func _build_hand_fingers(h: float, hand: BodyPart, shoulder_x: float,
		side: String, side_sign: float) -> void:
	var hand_base_y: float = hand.position.y - RAGDOLL_PROPORTIONS.HAND_FRAC * h * 0.5
	var finger_r: float = RAGDOLL_PROPORTIONS.FINGER_RADIUS_FRAC * h

	for f_idx: int in range(RAGDOLL_PROPORTIONS.FINGER_NAMES.size()):
		var f_name: String = RAGDOLL_PROPORTIONS.FINGER_NAMES[f_idx]
		var seg_lengths: PackedFloat64Array = RAGDOLL_PROPORTIONS.get_finger_seg_fracs(f_idx)
		var f_x_off: float = RAGDOLL_PROPORTIONS.FINGER_X_OFFSETS[f_idx] * h * side_sign
		var f_z_off: float = RAGDOLL_PROPORTIONS.FINGER_Z_OFFSETS[f_idx] * h
		var is_thumb: bool = (f_idx == 0)

		# Anchor: where the finger attaches to the hand
		var anchor_y: float = hand_base_y if not is_thumb else hand.position.y + RAGDOLL_PROPORTIONS.HAND_FRAC * h * 0.1
		var anchor_pos: Vector3 = Vector3(
			shoulder_x + f_x_off,
			anchor_y,
			f_z_off)

		var prev_part: BodyPart = hand
		var joint_pos: Vector3 = anchor_pos

		for seg_idx: int in range(RAGDOLL_PROPORTIONS.FINGER_SEG_NAMES.size()):
			var seg_name: String = RAGDOLL_PROPORTIONS.FINGER_SEG_NAMES[seg_idx]
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
				1.0 * mass_scale, 0.2)

			# Joint limits differ by finger and segment
			var lo: Vector3
			var hi: Vector3
			if is_thumb:
				if seg_idx == 0:  # Metacarpal
					lo = Vector3(-10, -15 * side_sign, -10)
					hi = Vector3(20, 15 * side_sign, 10)
				elif seg_idx == 1:  # Proximal (MCP)
					lo = Vector3(-30, -40 * side_sign, -25)
					hi = Vector3(60, 40 * side_sign, 25)
				else:  # Middle, Distal
					lo = Vector3(-10, -5, -5)
					hi = Vector3(80, 5, 5)
			else:
				if seg_idx == 0:  # Metacarpal
					lo = Vector3(-5, -5, -5)
					hi = Vector3(15, 5, 5)
				elif seg_idx == 1:  # Proximal (MCP)
					lo = Vector3(-15, -8, -10)
					hi = Vector3(90, 8, 10)
				else:  # Middle (PIP), Distal (DIP)
					lo = Vector3(0, -3, -3)
					hi = Vector3(110, 3, 3)

			_create_joint(prev_part, seg_part, joint_pos, lo, hi)

			# Advance chain
			joint_pos = Vector3(seg_pos.x, seg_pos.y - seg_len * 0.5, seg_pos.z)
			prev_part = seg_part


## Build all 5×2-3 toe phalanges for one foot. Only called at FULL detail.
func _build_foot_toes(h: float, foot: BodyPart, hip_x: float,
		side: String, side_sign: float) -> void:
	var foot_front_z: float = foot.position.z + 0.05 * h
	var toe_r: float = RAGDOLL_PROPORTIONS.TOE_RADIUS_FRAC * h

	for t_idx: int in range(RAGDOLL_PROPORTIONS.TOE_NAMES.size()):
		var t_name: String = RAGDOLL_PROPORTIONS.TOE_NAMES[t_idx]
		var t_seg_fracs: PackedFloat64Array = RAGDOLL_PROPORTIONS.get_toe_seg_fracs(t_idx)
		var t_x_off: float = RAGDOLL_PROPORTIONS.TOE_X_OFFSETS[t_idx] * h * side_sign
		var t_z_off: float = RAGDOLL_PROPORTIONS.TOE_Z_OFFSETS[t_idx] * h

		var toe_anchor: Vector3 = Vector3(
			hip_x + t_x_off,
			foot.position.y - RAGDOLL_PROPORTIONS.FOOT_FRAC * h * 0.3,
			foot_front_z + t_z_off)

		var prev_toe_part: BodyPart = foot
		var toe_joint_pos: Vector3 = toe_anchor

		for t_seg: int in range(t_seg_fracs.size()):
			var seg_num: String = "%02d" % (t_seg + 1)
			var seg_len: float = t_seg_fracs[t_seg] * h
			var t_part_name: String = "%s_%s_%s" % [side, t_name, seg_num]
			var t_display: String = "%s %s %s" % [
				side.capitalize(), t_name.replace("_", " ").capitalize(), seg_num]

			var seg_pos: Vector3 = Vector3(
				toe_joint_pos.x,
				toe_joint_pos.y,
				toe_joint_pos.z + seg_len * 0.5)

			var t_r_scale: float = 1.0 - t_seg * 0.1
			var toe_part: BodyPart = _create_part(
				t_part_name, t_display, seg_pos,
				_capsule_shape(toe_r * t_r_scale, seg_len),
				0.3 * mass_scale, 0.15)

			# Toes mostly flex up/down
			var t_lo: Vector3
			var t_hi: Vector3
			if t_seg == 0:
				t_lo = Vector3(-30, -5, -5)
				t_hi = Vector3(50, 5, 5)
			else:
				t_lo = Vector3(-10, -3, -3)
				t_hi = Vector3(40, 3, 3)

			_create_joint(prev_toe_part, toe_part, toe_joint_pos, t_lo, t_hi)

			toe_joint_pos = Vector3(seg_pos.x, seg_pos.y, seg_pos.z + seg_len * 0.5)
			prev_toe_part = toe_part


## Return the approximate physics body count for the current detail level
## and body type. Useful for budget estimation.
func get_expected_body_count() -> int:
	var count: int = 0
	# Torso: pelvis, spine×3, chest, neck, head = 7
	count += 7
	# Arms: L/R clavicle, upper_arm, forearm, hand = 8
	count += 8
	# Legs: L/R upper_leg, lower_leg, foot, toes = 8
	count += 8

	if detail_level == DetailLevel.FULL:
		# Face: jaw, tongue×3, eyes×2 = 6
		count += 6
		# Fingers: 5 fingers × 4 segments × 2 hands = 40
		count += 40
		# Individual toes: 5 toes × ~2.6 segments × 2 feet ≈ 28
		count += 28

	if detail_level != DetailLevel.MINIMAL:
		# Breasts: L/R (inner,outer,upper,lower,nipple) = 10
		count += 10
		# Glutes: L/R (inner,outer) = 4
		count += 4
		# Groin external (body-type dependent)
		if body_type == BodyType.MALE or body_type == BodyType.ANDROGYNOUS:
			count += 5  # penis×3, scrotum×2
		if body_type == BodyType.FEMALE or body_type == BodyType.ANDROGYNOUS:
			count += 3  # labia×2, clitoris

	if detail_level == DetailLevel.FULL:
		# Oral passage: ring 4 + depth 20 = 24
		count += 24
		# Anal passage: ring 4 + depth 32 = 36
		count += 36
		if body_type == BodyType.FEMALE or body_type == BodyType.ANDROGYNOUS:
			count += 36  # Vaginal passage

	return count


## Rebuild the ragdoll at a new LOD level. Snapshots transforms of parts
## that survive, destroys everything, rebuilds, and restores positions.
## Emits ragdoll_built when complete. Caller must re-bind skeleton.
func rebuild_at_lod(new_level: DetailLevel) -> void:
	if new_level == detail_level:
		return

	# Snapshot surviving part transforms (skeleton-core parts survive all levels)
	var saved_transforms: Dictionary = {}
	for part_name: String in parts:
		var bp: BodyPart = parts[part_name] as BodyPart
		if bp != null:
			saved_transforms[part_name] = bp.global_transform

	# Destroy all existing parts and joints
	for joint: Generic6DOFJoint3D in joints:
		if is_instance_valid(joint):
			joint.queue_free()
	for part_name: String in parts:
		var bp: BodyPart = parts[part_name] as BodyPart
		if is_instance_valid(bp):
			bp.queue_free()

	parts.clear()
	joints.clear()
	joint_map.clear()
	child_to_joint.clear()

	# Rebuild at new level
	detail_level = new_level
	_build_ragdoll()
	_apply_sleep_policy()

	# Restore transforms for parts that existed before
	for part_name: String in saved_transforms:
		if parts.has(part_name):
			var bp: BodyPart = parts[part_name] as BodyPart
			if bp != null:
				bp.global_transform = saved_transforms[part_name] as Transform3D

	ragdoll_built.emit()


# ──────────────────────────────────────────────────────────────────────────────
#  FACTORY HELPERS
# ──────────────────────────────────────────────────────────────────────────────

func _create_part(p_name: String, p_display: String, pos: Vector3,
		shape: Shape3D, p_mass: float, p_grab_stiffness: float,
		p_grabbable: bool = true, p_targetable: bool = true,
		p_apply_default_collision: bool = true) -> BodyPart:
	var part: BodyPart = BodyPart.new()
	part.name = p_name.to_pascal_case()
	part.part_name = p_name
	part.display_name = p_display
	part.mass = p_mass
	part.grab_stiffness = p_grab_stiffness
	part.is_grabbable = p_grabbable
	part.is_targetable = p_targetable
	part.apply_default_collision = p_apply_default_collision
	part.position = pos
	part.continuous_cd = false  # Disabled — CCD fights Jolt constraint solver in ragdoll chains
	part.can_sleep = _part_can_sleep(p_name)
	part.linear_damp = 2.0   # Resist wild translational movement
	part.angular_damp = 4.0  # Resist wild rotational movement / oscillation

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


func _part_can_sleep(part_name: String) -> bool:
	if not enable_lod_sleep_policy:
		return false
	if detail_level == DetailLevel.FULL:
		return false
	if not keep_torso_awake_on_reduced_lod:
		return true
	return not RAGDOLL_PROPORTIONS.REDUCED_LOD_AWAKE_PARTS.has(part_name)


func _apply_sleep_policy() -> void:
	for part_name: String in parts:
		var part: BodyPart = parts[part_name] as BodyPart
		if part == null:
			continue
		part.can_sleep = _part_can_sleep(part_name)


func _create_joint(parent_part: BodyPart, child_part: BodyPart,
		anchor_pos: Vector3,
		angular_lower_deg: Vector3, angular_upper_deg: Vector3) -> Generic6DOFJoint3D:
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "Joint_%s_to_%s" % [parent_part.part_name, child_part.part_name]
	# Anchor position is specified in the ragdoll root's local space.
	var anchor_global: Vector3 = global_transform * anchor_pos

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

	# Parent to the parent body so the joint moves with the ragdoll (no world anchor).
	parent_part.add_child(joint)
	joint.global_transform = Transform3D(parent_part.global_basis, anchor_global)
	joint.add_to_group(&"ragdoll_joint")
	joints.append(joint)
	joint_map[map_key] = joint
	child_to_joint[child_part.part_name] = joint

	# Angular motors are NOT used — skeleton_binding applies corrective torque
	# directly via apply_torque() instead (frame-independent PD controller).

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

	# Disable motors on soft tissue — angular springs handle natural jiggle instead
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)

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


## Builds a chain of ring-of-4 segments to simulate an internal passage.
## Each depth level has 4 tiny bodies (top/bot/left/right) forming a
## deformable ring.  All segments are non-grabbable, very low mass,
## high damping, with spring return.  An entrance ring of 4 parts is
## created at the opening before the chain.
func _create_passage_chain(passage_name: String, anchor_part: BodyPart,
		start_pos: Vector3, direction: Vector3,
		segment_count: int, h: float) -> Array[BodyPart]:
	var seg_radius: float = RAGDOLL_PROPORTIONS.PASSAGE_SEGMENT_RADIUS_FRAC * h
	var seg_length: float = RAGDOLL_PROPORTIONS.PASSAGE_SEGMENT_LENGTH_FRAC * h
	var ring_offset_dist: float = seg_radius * 1.2  # How far ring parts spread from centre
	var chain: Array[BodyPart] = []

	# Build a local coordinate frame from the direction vector
	var forward: Vector3 = direction.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var right_vec: Vector3 = forward.cross(up).normalized()
	var up_vec: Vector3 = right_vec.cross(forward).normalized()

	# Ring offset vectors in world space for each quadrant
	var q_offsets: Array[Vector3] = [
		up_vec * ring_offset_dist,       # top
		-up_vec * ring_offset_dist,      # bot
		-right_vec * ring_offset_dist,   # left
		right_vec * ring_offset_dist,    # right
	]

	# ── Entrance ring (at the opening) ──────────────────────────────────
	var ring_radius: float = RAGDOLL_PROPORTIONS.ENTRANCE_RING_RADIUS_FRAC * h
	for q_idx: int in range(4):
		var q_name: String = RAGDOLL_PROPORTIONS.PASSAGE_RING_QUADRANTS[q_idx]
		var ring_pos: Vector3 = start_pos + q_offsets[q_idx]
		var ring_part_name: String = "%s_ring_%s" % [passage_name, q_name]
		var ring_display: String = "%s Ring %s" % [passage_name.capitalize(), q_name.capitalize()]

		var ring_part: BodyPart = _create_part(ring_part_name, ring_display,
			ring_pos, _sphere_shape(ring_radius),
			0.3 * mass_scale, 0.1, false, false, false)
		ring_part.linear_damp = 10.0
		ring_part.angular_damp = 12.0

		# Stiff spring to anchor — entrance ring resists but yields to pressure
		_create_soft_joint(anchor_part, ring_part, start_pos + q_offsets[q_idx] * 0.5,
			Vector3(-10, -10, -10), Vector3(10, 10, 10),
			18.0, 5.0)
		chain.append(ring_part)

	# ── Depth segments (ring of 4 per level) ────────────────────────────
	# prev_ring[q_idx] holds the previous depth's part for each quadrant
	var prev_ring: Array[BodyPart] = []
	for q_idx: int in range(4):
		prev_ring.append(anchor_part)

	for depth: int in range(segment_count):
		var centre_pos: Vector3 = start_pos + forward * seg_length * (depth + 1)

		for q_idx: int in range(4):
			var q_name: String = RAGDOLL_PROPORTIONS.PASSAGE_RING_QUADRANTS[q_idx]
			var seg_pos: Vector3 = centre_pos + q_offsets[q_idx]
			var seg_name: String = "%s_passage_%d_%s" % [passage_name, depth, q_name]
			var seg_display: String = "%s %d %s" % [passage_name.capitalize(), depth + 1, q_name.capitalize()]

			var seg: BodyPart = _create_part(seg_name, seg_display, seg_pos,
				_capsule_shape(seg_radius * 0.5, seg_length),
				0.3 * mass_scale, 0.1, false, false, false)

			# High damping for internal tissue
			seg.linear_damp = 8.0
			seg.angular_damp = 10.0

			# Joint to previous depth (same quadrant) — soft spring return
			var joint_pos: Vector3 = start_pos + forward * seg_length * (depth + 0.5) + q_offsets[q_idx]
			_create_soft_joint(prev_ring[q_idx], seg, joint_pos,
				Vector3(-15, -15, -15), Vector3(15, 15, 15),
				12.0, 4.0)

			chain.append(seg)
			prev_ring[q_idx] = seg

		# Cross-link adjacent quadrants at this depth for ring cohesion
		# top↔left, left↔bot, bot↔right, right↔top
		var depth_parts: Array[BodyPart] = []
		for q_idx: int in range(4):
			depth_parts.append(chain[chain.size() - 4 + q_idx])
		for q_idx: int in range(4):
			var next_q: int = (q_idx + 1) % 4
			_create_soft_joint(depth_parts[q_idx], depth_parts[next_q],
				centre_pos + (q_offsets[q_idx] + q_offsets[next_q]) * 0.5,
				Vector3(-8, -8, -8), Vector3(8, 8, 8),
				6.0, 2.0)

	return chain


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
