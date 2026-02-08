class_name HumanoidRagdollBuilder
extends Node3D
## Procedurally constructs a 25-segment humanoid ragdoll with anatomically
## correct joint limits. Each segment is a BodyPart (RigidBody3D) connected
## by Generic6DOFJoint3D nodes.
##
## Segments (25 total):
##   Torso:  pelvis, spine_lower, spine_upper, chest, neck, head
##   Arms:   L/R clavicle, upper_arm, forearm, hand
##   Hands:  L/R thumb, fingers (4 grouped)
##   Legs:   L/R upper_leg, lower_leg, foot, toes
##
## Attach this to an empty Node3D. It builds everything in _ready().
## The "root" body part is the pelvis — the rest hang from it.

signal ragdoll_built()

@export_group("Body Scale")
## Total height of the humanoid in meters.
@export var body_height: float = 1.75
## Overall scale multiplier for mass.
@export var mass_scale: float = 1.0

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


func _ready() -> void:
	_build_ragdoll()
	ragdoll_built.emit()


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

		# Thumb (1 segment)
		var thumb: BodyPart = _create_part(
			"%s_thumb" % side, "%s Thumb" % side.capitalize(),
			Vector3(shoulder_x + side_sign * 0.03 * h,
				hand.position.y + HAND_FRAC * h * 0.1,
				0.02 * h),
			_capsule_shape(0.01 * h, 0.03 * h),
			0.1 * mass_scale, 0.3)

		# Fingers grouped (1 segment for index+middle+ring+pinky)
		var fingers: BodyPart = _create_part(
			"%s_fingers" % side, "%s Fingers" % side.capitalize(),
			Vector3(shoulder_x, hand.position.y - HAND_FRAC * h * 0.5 - 0.02 * h, 0.0),
			_box_shape(Vector3(0.04 * h, 0.035 * h, 0.02 * h)),
			0.2 * mass_scale, 0.3)

		# ── Arm joints ──────────────────────────────────────────────
		# Chest -> Clavicle
		_create_joint(chest, clavicle,
			Vector3(shoulder_x * 0.1, clavicle.position.y, 0),
			Vector3(-5, -10, -5), Vector3(15, 10, 5))

		# Clavicle -> Upper Arm (shoulder — wide range)
		_create_joint(clavicle, upper_arm,
			Vector3(shoulder_x, clavicle.position.y, 0),
			Vector3(-90, -60, -80), Vector3(90, 90, 30))

		# Upper Arm -> Forearm (elbow — hinge-like)
		_create_joint(upper_arm, forearm,
			Vector3(shoulder_x, upper_arm.position.y - UPPER_ARM_FRAC * h * 0.5, 0),
			Vector3(0, -5, -5), Vector3(145, 5, 5))

		# Forearm -> Hand (wrist)
		_create_joint(forearm, hand,
			Vector3(shoulder_x, forearm.position.y - FOREARM_FRAC * h * 0.5, 0),
			Vector3(-70, -20, -40), Vector3(70, 20, 40))

		# Hand -> Thumb
		_create_joint(hand, thumb,
			Vector3(shoulder_x + side_sign * 0.025 * h, hand.position.y + HAND_FRAC * h * 0.2, 0.01 * h),
			Vector3(-30, -30, -20), Vector3(60, 30, 20))

		# Hand -> Fingers
		_create_joint(hand, fingers,
			Vector3(shoulder_x, hand.position.y - HAND_FRAC * h * 0.5, 0),
			Vector3(-10, -5, -5), Vector3(90, 5, 5))

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
		shape: Shape3D, p_mass: float, p_grab_stiffness: float) -> BodyPart:
	var part: BodyPart = BodyPart.new()
	part.name = p_name.to_pascal_case()
	part.part_name = p_name
	part.display_name = p_display
	part.mass = p_mass
	part.grab_stiffness = p_grab_stiffness
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

	# Track adjacency
	parent_part.connected_parts.append(child_part)
	child_part.connected_parts.append(parent_part)

	return joint


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
