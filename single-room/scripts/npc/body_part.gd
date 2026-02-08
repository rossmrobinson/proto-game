class_name BodyPart
extends RigidBody3D
## A single segment of a ragdoll humanoid. Each body part is independently
## grabbable, targetable, and responds to physics.
##
## This is similar to Grabbable but specialized for ragdoll segments that
## are connected to other parts via joints.

signal part_grabbed(part_name: String, by: Node3D)
signal part_released(part_name: String, by: Node3D)
signal part_hit(part_name: String, force: float, hit_point: Vector3)

## Which body part this represents (e.g., "head", "left_upper_arm", "right_hand")
@export var part_name: String = ""
## Readable label for UI
@export var display_name: String = ""
## How much this part resists grab movement (head feels heavier than a finger)
@export_range(0.0, 1.0) var grab_stiffness: float = 0.5
## Max stretch before the grab breaks
@export var grab_break_distance: float = 1.5
## Whether this part can be grabbed
@export var is_grabbable: bool = true

# ── Grab State ───────────────────────────────────────────────────────────────
var grabbed_by: Node3D = null
var _grab_joint: Generic6DOFJoint3D = null

# ── Internal ─────────────────────────────────────────────────────────────────
## Reference to the parent ragdoll root (set by HumanoidRagdollBuilder)
var ragdoll_owner: Node3D = null
## Adjacent parts connected by joints (set by builder)
var connected_parts: Array[BodyPart] = []


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"body_part")
	# Physics layer 3 (NPC) + layer 4 (Interactable)
	set_collision_layer_value(3, true)
	set_collision_layer_value(4, true)
	# Collide with environment, player, other NPCs, interactables
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	set_collision_mask_value(4, true)
	# Start with some damping for stable ragdoll
	linear_damp = 1.0
	angular_damp = 2.0


func get_part_name() -> String:
	return part_name


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return part_name.replace("_", " ").capitalize()


## Grab this body part. Creates a joint to the grab anchor.
func grab(grabber: Node3D, grab_body: StaticBody3D, hit_point: Vector3) -> bool:
	if not is_grabbable or grabbed_by != null:
		return false

	grabbed_by = grabber

	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "BodyPartGrabJoint_%s" % part_name
	joint.global_position = hit_point

	joint.node_a = grab_body.get_path()
	joint.node_b = get_path()

	# Soft linear constraint — allows slight flex for natural feel
	var linear_slack: float = 0.05 * (1.0 - grab_stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)

	# Allow some rotation so the part can pivot naturally while grabbed
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))

	get_tree().current_scene.add_child(joint)
	_grab_joint = joint

	# Make the part lighter while grabbed for responsive feel
	gravity_scale = 0.3
	linear_damp = 6.0
	angular_damp = 8.0

	part_grabbed.emit(part_name, grabber)
	return true


## Release this body part from a grab.
func release() -> void:
	if _grab_joint != null and is_instance_valid(_grab_joint):
		_grab_joint.queue_free()
		_grab_joint = null

	gravity_scale = 1.0
	linear_damp = 1.0
	angular_damp = 2.0

	var prev: Node3D = grabbed_by
	grabbed_by = null
	part_released.emit(part_name, prev)


## Apply an impact force to this body part.
func apply_hit(force_dir: Vector3, magnitude: float, point: Vector3) -> void:
	apply_impulse(force_dir * magnitude, point - global_position)
	part_hit.emit(part_name, magnitude, point)


func _physics_process(_delta: float) -> void:
	# Auto-release if grab joint stretches too far
	if grabbed_by != null and _grab_joint != null and is_instance_valid(_grab_joint):
		if global_position.distance_to(_grab_joint.global_position) > grab_break_distance:
			release()
