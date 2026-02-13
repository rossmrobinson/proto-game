class_name ChainRig
extends Node3D
## Procedural chain with two hanging cuff ends and a vertical wall slider.
## Supports latching-winch mode: the slider is locked in place until an NPC
## grabs a handle link and pulls.  Releasing re-latches at the new position.

signal spool_changed(new_y: float)
signal latched()
signal unlatched()

@export_group("Layout")
@export var branch_separation: float = 0.45
@export var segment_count: int = 10
@export var segment_length: float = 0.18
@export var segment_radius: float = 0.015
@export var segment_mass: float = 0.2
@export var cuff_scene: PackedScene
@export var slider_min_y: float = -1.6
@export var slider_max_y: float = 0.0
@export var handle_index: int = 1

@export_group("Physics")
@export var joint_angle_limit_deg: float = 50.0
@export var link_linear_damp: float = 0.6
@export var link_angular_damp: float = 1.2

@export_group("Winch")
## If true, the slider locks in place when no handle is grabbed.
@export var latch_enabled: bool = true
## Motor force used to hold the slider in the latched position (N).
@export var latch_motor_force: float = 5000.0
## Speed limit when an NPC actively pulls the chain (m/s).
@export var pull_speed_limit: float = 0.8

var _wall_anchor: StaticBody3D = null
var _slider: RigidBody3D = null
var _slider_joint: Generic6DOFJoint3D = null
var _latch_y: float = 0.0
var _is_latched: bool = true
var _handle_links: Array[Grabbable] = []
var _active_grabs: int = 0


func _ready() -> void:
	_build_chain()


func _build_chain() -> void:
	_wall_anchor = StaticBody3D.new()
	_wall_anchor.name = "WallAnchor"
	_wall_anchor.position = Vector3.ZERO
	add_child(_wall_anchor)

	_slider = RigidBody3D.new()
	_slider.name = "PulleySlider"
	_slider.mass = 1.0
	_slider.linear_damp = 5.0
	_slider.angular_damp = 6.0
	add_child(_slider)
	_slider.position = Vector3.ZERO

	_slider_joint = _create_slider_joint(_wall_anchor, _slider)

	_build_branch(-branch_separation * 0.5, "Left")
	_build_branch(branch_separation * 0.5, "Right")

	# Apply initial latch
	if latch_enabled:
		_latch_y = _slider.position.y
		_apply_latch()


func _build_branch(x_offset: float, label: String) -> void:
	var prev: RigidBody3D = _slider
	var base_pos: Vector3 = _slider.global_position + Vector3(x_offset, 0.0, 0.0)

	for i: int in range(segment_count):
		var link: RigidBody3D = _create_link(label, i)
		link.global_position = base_pos + Vector3(0.0, -segment_length * float(i + 1), 0.0)
		_create_chain_joint(prev, link, base_pos + Vector3(0.0, -segment_length * float(i) - segment_length * 0.5, 0.0))
		prev.add_collision_exception_with(link)
		link.add_collision_exception_with(prev)
		prev = link

	var cuff: RigidBody3D = _create_cuff(label)
	cuff.global_position = base_pos + Vector3(0.0, -segment_length * float(segment_count + 1), 0.0)
	_create_chain_joint(prev, cuff, base_pos + Vector3(0.0, -segment_length * float(segment_count) - segment_length * 0.5, 0.0))
	prev.add_collision_exception_with(cuff)
	cuff.add_collision_exception_with(prev)


func _create_link(label: String, index: int) -> RigidBody3D:
	var is_handle: bool = index == handle_index
	var link: RigidBody3D
	if is_handle:
		var grab_link: Grabbable = Grabbable.new()
		grab_link.name = "%sChainHandle_%d" % [label, index]
		grab_link.is_grabbable = true
		grab_link.grab_weight_factor = 0.4
		grab_link.grabbed.connect(_on_handle_grabbed)
		grab_link.released.connect(_on_handle_released)
		_handle_links.append(grab_link)
		link = grab_link
	else:
		link = RigidBody3D.new()
		link.name = "%sChainLink_%d" % [label, index]

	link.mass = segment_mass
	link.linear_damp = link_linear_damp
	link.angular_damp = link_angular_damp
	link.continuous_cd = false
	link.can_sleep = false

	link.collision_layer = 0
	link.set_collision_layer_value(4, true)  # Interactable
	link.collision_mask = 0
	link.set_collision_mask_value(1, true)  # Environment
	link.set_collision_mask_value(2, true)  # Player
	link.set_collision_mask_value(3, true)  # NPC_External
	link.set_collision_mask_value(4, true)  # Interactable

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = segment_radius
	shape.height = maxf(segment_length, segment_radius * 2.0 + 0.01)
	col.shape = shape
	link.add_child(col)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = shape.radius
	cap.height = shape.height
	mesh.mesh = cap
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28, 1.0)
	mat.metallic = 0.8
	mat.roughness = 0.2
	mesh.material_override = mat
	link.add_child(mesh)

	add_child(link)
	return link


func _create_cuff(label: String) -> RigidBody3D:
	var cuff: RigidBody3D
	if cuff_scene != null:
		var inst: Node = cuff_scene.instantiate()
		if inst is RigidBody3D:
			cuff = inst as RigidBody3D
		else:
			inst.queue_free()
			cuff = CuffFastener.new()
	else:
		cuff = CuffFastener.new()

	cuff.name = "%sCuff" % label
	add_child(cuff)
	return cuff


func _create_chain_joint(parent_part: RigidBody3D, child_part: RigidBody3D,
		anchor_global: Vector3) -> void:
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "Joint_%s_to_%s" % [parent_part.name, child_part.name]
	joint.node_a = parent_part.get_path()
	joint.node_b = child_part.get_path()

	# Lock linear axes
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	var limit: float = deg_to_rad(joint_angle_limit_deg)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit)

	parent_part.add_child(joint)
	joint.global_transform = Transform3D(parent_part.global_basis, anchor_global)


func _create_slider_joint(anchor: StaticBody3D, slider: RigidBody3D) -> Generic6DOFJoint3D:
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "SliderJoint"
	joint.node_a = anchor.get_path()
	joint.node_b = slider.get_path()

	# Lock X/Z, allow Y
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, slider_min_y)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slider_max_y)

	# Lock rotation
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)

	anchor.add_child(joint)
	joint.global_transform = Transform3D(anchor.global_basis, anchor.global_position)
	return joint


# ── Winch / Latch API ──────────────────────────────────────────────────────────

func latch() -> void:
	if _is_latched:
		return
	_latch_y = _slider.position.y
	_apply_latch()
	_is_latched = true
	spool_changed.emit(_latch_y)
	latched.emit()


func unlatch() -> void:
	if not _is_latched:
		return
	_release_latch()
	_is_latched = false
	unlatched.emit()


## Returns the current spool position (Y offset from anchor).
func get_spool_position() -> float:
	if _slider != null:
		return _slider.position.y
	return _latch_y


## Programmatically set the spool to a specific Y position (clamped to limits).
func set_spool_position(target_y: float) -> void:
	target_y = clampf(target_y, slider_min_y, slider_max_y)
	_latch_y = target_y
	if _slider != null:
		_slider.position.y = target_y
	if _is_latched and _slider_joint != null:
		_apply_latch()
	spool_changed.emit(_latch_y)


func is_latched() -> bool:
	return _is_latched


# ── Handle grab callbacks ──────────────────────────────────────────────────────

func _on_handle_grabbed(_by: Node3D) -> void:
	_active_grabs += 1
	if _active_grabs == 1 and latch_enabled:
		unlatch()


func _on_handle_released(_by: Node3D) -> void:
	_active_grabs = maxi(_active_grabs - 1, 0)
	if _active_grabs == 0 and latch_enabled:
		latch()


# ── Internal latch helpers ─────────────────────────────────────────────────────

func _apply_latch() -> void:
	if _slider_joint == null:
		return
	# Enable Y-axis motor with zero target velocity and huge force to hold
	_slider_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, true)
	_slider_joint.set_param_y(
		Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_TARGET_VELOCITY, 0.0)
	_slider_joint.set_param_y(
		Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_FORCE_LIMIT, latch_motor_force)


func _release_latch() -> void:
	if _slider_joint == null:
		return
	# Disable motor so slider moves freely under external forces
	_slider_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, false)
