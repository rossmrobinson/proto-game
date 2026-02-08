class_name RagdollPose
extends Resource
## A target pose for a ragdoll. Stores desired joint angles per body part pair.
## Used by RagdollAnimator to drive an active ragdoll toward a specific position.

## Human-readable name (e.g. "warrior_ii", "ballet_arabesque").
@export var pose_name: String = ""
## Category tag (e.g. "dance", "yoga", "martial_arts").
@export var category: String = ""
## Short description of the pose.
@export var description: String = ""
## Maps joint key ("parent_to_child") -> target Vector3 euler angles (degrees).
## Only joints that differ from rest (0,0,0) need entries.
@export var joint_targets: Dictionary = {}
## How stiff the motors should be when driving to this pose (0.0 = floppy, 1.0 = rigid).
@export_range(0.0, 1.0) var drive_stiffness: float = 0.6
## Whether this is a resting/held pose vs. a transient keyframe in a sequence.
@export var is_static: bool = true


## Factory method for creating poses from code.
static func create(p_name: String, p_category: String, p_targets: Dictionary,
		p_stiffness: float = 0.6, p_desc: String = "") -> RagdollPose:
	var pose: RagdollPose = RagdollPose.new()
	pose.pose_name = p_name
	pose.category = p_category
	pose.joint_targets = p_targets
	pose.drive_stiffness = p_stiffness
	pose.description = p_desc
	return pose
