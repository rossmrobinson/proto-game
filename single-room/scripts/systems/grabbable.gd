class_name Grabbable
extends RigidBody3D
## Base class for any physics object that can be grabbed, pushed, or pulled.
## Add to the "interactable" group automatically. Place on physics layer 4.

signal grabbed(by: Node3D)
signal released(by: Node3D)

@export_group("Grab Properties")
## How strongly this object resists being moved while grabbed (0 = weightless feel, 1 = full mass).
@export_range(0.0, 1.0) var grab_weight_factor: float = 0.5
## Maximum distance the grab joint can stretch before breaking.
@export var grab_break_distance: float = 2.0
## Whether this object can be grabbed at all.
@export var is_grabbable: bool = true
## Custom label shown in the interaction prompt (e.g., "Pick up Mug").
@export var display_name: String = ""

## Who is currently grabbing this object (null if free).
var grabbed_by: Node3D = null
## The joint connecting this to the grabber.
var _grab_joint: Joint3D = null


func _ready() -> void:
	add_to_group(&"interactable")
	# Ensure we're on the Interactable physics layer (layer 4)
	set_collision_layer_value(4, true)
	# Collide with environment (1), player (2), NPC (3), and other interactables (4)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	set_collision_mask_value(4, true)


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return name


## Called by the grab system to attach this object to a grabber body.
func grab(grabber: Node3D, grab_body: StaticBody3D, hit_point: Vector3) -> bool:
	if not is_grabbable or grabbed_by != null:
		return false

	grabbed_by = grabber

	# Create a 6DOF joint at the hit point for full control
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "GrabJoint"

	# Joint position at the hit point in world space
	joint.global_position = hit_point

	# Connect: node_a = the grab anchor, node_b = this object
	joint.node_a = grab_body.get_path()
	joint.node_b = get_path()

	# Lock linear axes so the object follows the grab point
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.01)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.01)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.01)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.01)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.01)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.01)

	# Allow free rotation so the player can orient the object
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))

	get_tree().current_scene.add_child(joint)
	_grab_joint = joint

	# Reduce gravity effect while grabbed for more responsive feel
	gravity_scale = grab_weight_factor
	# Increase damping to reduce wild swinging
	linear_damp = 8.0
	angular_damp = 10.0

	grabbed.emit(grabber)
	return true


## Called by the grab system to release this object.
func release() -> void:
	if _grab_joint != null and is_instance_valid(_grab_joint):
		_grab_joint.queue_free()
		_grab_joint = null

	# Restore physics defaults
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.0

	var prev: Node3D = grabbed_by
	grabbed_by = null
	released.emit(prev)

	var prev_grabber: Node3D = grabbed_by
	grabbed_by = null
	released.emit(prev_grabber)


## Apply an impulse push away from a source position.
func push_from(source_pos: Vector3, force: float) -> void:
	var dir: Vector3 = (global_position - source_pos).normalized()
	apply_central_impulse(dir * force)


## Apply a pull toward a target position.
func pull_toward(target_pos: Vector3, force: float, _delta: float) -> void:
	var dir: Vector3 = (target_pos - global_position).normalized()
	var dist: float = global_position.distance_to(target_pos)
	apply_central_force(dir * force * minf(dist, 3.0))


func _physics_process(_delta: float) -> void:
	# Break the grab if the object gets too far from the grab point
	if grabbed_by != null and _grab_joint != null and is_instance_valid(_grab_joint):
		var joint_pos: Vector3 = _grab_joint.global_position
		if global_position.distance_to(joint_pos) > grab_break_distance:
			release()
