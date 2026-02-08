class_name PiercingAttachment
extends RigidBody3D
## A physics-driven piercing attached to a BodyPart via a soft spring joint.
## Pulling the piercing stretches the spring, simulating skin pull.
## When meshes exist, a skin-deformation callback can hook into the stretch.

signal piercing_grabbed(piercing_name: String)
signal piercing_released(piercing_name: String)
signal piercing_torn(piercing_name: String)
signal skin_stretch_changed(piercing_name: String, stretch_ratio: float)

@export var piercing_type: PiercingType

## The BodyPart this piercing is attached to.
var attached_body_part: RigidBody3D = null
## Local position on the body part surface where the piercing is anchored.
var attachment_local_pos: Vector3 = Vector3.ZERO
## The joint connecting this piercing to the body part.
var _spring_joint: Generic6DOFJoint3D = null
## Current stretch ratio (0 = resting, 1 = max_stretch).
var _stretch_ratio: float = 0.0
## Whether this piercing has been torn free.
var _is_torn: bool = false
## Whether this piercing is currently being grabbed.
var _is_grabbed: bool = false
## Collision shape node.
var _collision: CollisionShape3D = null
## Visual mesh node (placeholder until real meshes).
var _mesh: MeshInstance3D = null


func _ready() -> void:
	if piercing_type == null:
		push_error("[PiercingAttachment] No piercing_type assigned.")
		return
	_setup_physics()
	_setup_visual()
	add_to_group(&"piercings")
	add_to_group(&"interactable")


func _physics_process(_delta: float) -> void:
	if _is_torn or attached_body_part == null or _spring_joint == null:
		return
	_update_stretch()


## Attach this piercing to a body part at a given local position.
func attach_to(body_part: RigidBody3D, local_pos: Vector3) -> void:
	attached_body_part = body_part
	attachment_local_pos = local_pos

	# Position the piercing at the attachment point in world space.
	var world_pos: Vector3 = body_part.global_transform * local_pos
	global_position = world_pos

	# Build the spring joint connecting piercing to body part.
	_create_spring_joint()


## Detach the piercing (tear or manual removal).
func detach() -> void:
	if _spring_joint != null:
		_spring_joint.queue_free()
		_spring_joint = null
	attached_body_part = null
	_is_torn = true
	piercing_torn.emit(piercing_type.piercing_name)


## Called by the grab system when the player grabs this piercing.
func grab() -> void:
	_is_grabbed = true
	piercing_grabbed.emit(piercing_type.piercing_name)


## Called by the grab system when the player releases this piercing.
func release() -> void:
	_is_grabbed = false
	piercing_released.emit(piercing_type.piercing_name)


func get_stretch_ratio() -> float:
	return _stretch_ratio


func is_torn() -> bool:
	return _is_torn


# ── Internal ─────────────────────────────────────────────────────────────────

func _setup_physics() -> void:
	var pt: PiercingType = piercing_type

	mass = pt.mass
	gravity_scale = 1.0
	linear_damp = 3.0
	angular_damp = 5.0
	continuous_cd = true

	# Collision on layer 4 (Interactable), scan layer 3 (NPC) + 1 (World).
	collision_layer = 8  # bit 4
	collision_mask = 5   # bits 1 + 3

	_collision = CollisionShape3D.new()
	_collision.name = "PiercingCollision"
	var col_shape: SphereShape3D = SphereShape3D.new()
	col_shape.radius = pt.size * 0.5
	_collision.shape = col_shape
	add_child(_collision)


func _setup_visual() -> void:
	var pt: PiercingType = piercing_type

	_mesh = MeshInstance3D.new()
	_mesh.name = "PiercingMesh"

	# Placeholder shape based on type
	match pt.shape_type:
		"Ring":
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = pt.size * 0.3
			torus.outer_radius = pt.size * 0.5
			_mesh.mesh = torus
		"Barbell":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = pt.size * 0.15
			capsule.height = pt.size
			_mesh.mesh = capsule
		"Stud":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = pt.size * 0.4
			_mesh.mesh = sphere
		"Hook":
			# Approximate with a small cylinder
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = pt.size * 0.1
			cyl.bottom_radius = pt.size * 0.1
			cyl.height = pt.size * 0.8
			_mesh.mesh = cyl
		"Chain":
			# Tiny cylinder link placeholder
			var cyl2: CylinderMesh = CylinderMesh.new()
			cyl2.top_radius = pt.size * 0.08
			cyl2.bottom_radius = pt.size * 0.08
			cyl2.height = pt.size
			_mesh.mesh = cyl2

	# Material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = pt.color
	mat.metallic = pt.metallic
	mat.roughness = pt.roughness
	_mesh.material_override = mat

	add_child(_mesh)


func _create_spring_joint() -> void:
	if attached_body_part == null or piercing_type == null:
		return

	var pt: PiercingType = piercing_type

	_spring_joint = Generic6DOFJoint3D.new()
	_spring_joint.name = "PiercingSkinJoint"

	# Node paths: A = body part, B = this piercing.
	# The joint lives as a child of this piercing.
	_spring_joint.node_a = attached_body_part.get_path()
	_spring_joint.node_b = get_path()

	# Free linear movement (spring pull) on all axes.
	# Linear limits — allow movement up to max_stretch.
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -pt.max_stretch)
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, pt.max_stretch)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -pt.max_stretch)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, pt.max_stretch)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -pt.max_stretch)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, pt.max_stretch)

	# Enable linear spring on all axes.
	_spring_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)
	_spring_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)
	_spring_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)

	# Spring stiffness and damping.
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, pt.attachment_stiffness)
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, pt.attachment_damping)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, pt.attachment_stiffness)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, pt.attachment_damping)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, pt.attachment_stiffness)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, pt.attachment_damping)

	# Lock angular — piercings don't independently rotate on their own joint.
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	_spring_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	_spring_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	_spring_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)

	add_child(_spring_joint)


func _update_stretch() -> void:
	if attached_body_part == null or piercing_type == null:
		return

	var anchor_world: Vector3 = attached_body_part.global_transform * attachment_local_pos
	var current_pos: Vector3 = global_position
	var distance: float = anchor_world.distance_to(current_pos)

	_stretch_ratio = clampf(distance / piercing_type.max_stretch, 0.0, 1.0)
	skin_stretch_changed.emit(piercing_type.piercing_name, _stretch_ratio)

	# Tear check
	if piercing_type.can_tear and distance > piercing_type.max_stretch * 1.2:
		detach()
