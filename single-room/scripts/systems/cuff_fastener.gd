class_name CuffFastener
extends Grabbable
## Simple cuff fastener that can attach to rigid bodies via a locked joint.

@export_group("Cuff")
@export var cuff_radius: float = 0.06
@export var cuff_width: float = 0.02
@export var cuff_thickness: float = 0.01
@export var open_gap: float = 0.04
@export var cuff_mass: float = 0.6
@export var open_damping: float = 2.0
@export var closed_damping: float = 6.0
@export var attach_break_distance: float = 0.8

var _attach_joint: Generic6DOFJoint3D = null
var _attached_body: RigidBody3D = null
var _open_root: Node3D = null
var _closed_mesh: MeshInstance3D = null
var _is_open: bool = true


func _ready() -> void:
	super._ready()
	mass = cuff_mass
	add_to_group(&"fastener")
	_build_collision()
	_build_visuals()
	_set_open(true)


func is_fastener() -> bool:
	return true


func is_attached() -> bool:
	return _attach_joint != null and is_instance_valid(_attach_joint)


func attach_to(target: Node3D, hit_point: Vector3) -> bool:
	if is_attached():
		return false
	if target == null or target is not RigidBody3D:
		return false

	var body: RigidBody3D = target as RigidBody3D
	_attached_body = body

	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "CuffAttachJoint"
	joint.global_position = hit_point
	joint.node_a = get_path()
	joint.node_b = body.get_path()

	# Lock linear axes
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Lock angular axes
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)

	get_tree().current_scene.add_child(joint)
	_attach_joint = joint
	_set_open(false)
	return true


func detach() -> void:
	if _attach_joint != null and is_instance_valid(_attach_joint):
		_attach_joint.queue_free()
	_attach_joint = null
	_attached_body = null
	_set_open(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_attached():
		return
	if global_position.distance_to(_attach_joint.global_position) > attach_break_distance:
		detach()


func _build_collision() -> void:
	if _get_collision_shape() != null:
		return
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = cuff_radius
	shape.height = cuff_width
	col.shape = shape
	add_child(col)


func _build_visuals() -> void:
	if _open_root != null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.65, 0.7, 1.0)
	mat.metallic = 0.9
	mat.roughness = 0.2

	_open_root = Node3D.new()
	_open_root.name = "CuffOpen"
	add_child(_open_root)

	var arm_mesh: BoxMesh = BoxMesh.new()
	arm_mesh.size = Vector3(cuff_thickness, cuff_width, cuff_radius)

	var left_arm: MeshInstance3D = MeshInstance3D.new()
	left_arm.mesh = arm_mesh
	left_arm.material_override = mat
	left_arm.position = Vector3(-(open_gap * 0.5 + cuff_thickness * 0.5), 0.0, 0.0)
	_open_root.add_child(left_arm)

	var right_arm: MeshInstance3D = MeshInstance3D.new()
	right_arm.mesh = arm_mesh
	right_arm.material_override = mat
	right_arm.position = Vector3(open_gap * 0.5 + cuff_thickness * 0.5, 0.0, 0.0)
	_open_root.add_child(right_arm)

	var bridge_mesh: BoxMesh = BoxMesh.new()
	bridge_mesh.size = Vector3(open_gap + cuff_thickness * 2.0, cuff_width, cuff_thickness)
	var bridge: MeshInstance3D = MeshInstance3D.new()
	bridge.mesh = bridge_mesh
	bridge.material_override = mat
	bridge.position = Vector3(0.0, 0.0, -cuff_radius * 0.45)
	_open_root.add_child(bridge)

	_closed_mesh = MeshInstance3D.new()
	_closed_mesh.name = "CuffClosed"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = cuff_radius - cuff_thickness * 0.6
	torus.outer_radius = cuff_radius + cuff_thickness * 0.6
	_closed_mesh.mesh = torus
	_closed_mesh.material_override = mat
	add_child(_closed_mesh)


func _set_open(open_state: bool) -> void:
	_is_open = open_state
	if _open_root != null:
		_open_root.visible = _is_open
	if _closed_mesh != null:
		_closed_mesh.visible = not _is_open
	angular_damp = open_damping if _is_open else closed_damping


func _get_collision_shape() -> CollisionShape3D:
	for child: Node in get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
