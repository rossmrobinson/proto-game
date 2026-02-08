class_name RagdollAnimator
extends Node
## Active ragdoll animation controller.
## Drives HumanoidRagdollBuilder joints toward target poses using angular spring
## equilibrium points. The ragdoll tries to hold the pose while remaining
## physically interactive — push it and it'll wobble then recover.
##
## Attach as a child or sibling of HumanoidRagdollBuilder.
## Assign the ragdoll export, or it will auto-detect from parent.

signal pose_reached(pose_name: String)
signal sequence_finished(sequence_name: String)

@export var ragdoll: HumanoidRagdollBuilder

@export_group("Drive Settings")
## Base spring stiffness. Higher = snappier, more rigid posing.
@export var spring_stiffness: float = 40.0
## Base spring damping. Higher = less oscillation.
@export var spring_damping: float = 5.0
## Seconds to blend between poses.
@export var blend_time: float = 0.4

# ── Pose State ───────────────────────────────────────────────────────────────
var _current_pose: RagdollPose = null
var _target_pose: RagdollPose = null
var _blend_t: float = 1.0
var _blend_speed: float = 2.5
var _current_targets: Dictionary = {}
var _driven_joints: Array[String] = []
var _active: bool = false

# ── Sequence State ───────────────────────────────────────────────────────────
var _sequence: Array[RagdollPose] = []
var _sequence_holds: Array[float] = []
var _sequence_index: int = -1
var _sequence_timer: float = 0.0
var _sequence_loop: bool = false
var _sequence_name: String = ""


func _ready() -> void:
	if ragdoll == null:
		ragdoll = get_parent() as HumanoidRagdollBuilder
	if ragdoll == null:
		push_error("[RagdollAnimator] No ragdoll found. Assign via export or parent.")


## Set a single target pose. If immediate, snaps instantly; otherwise blends.
func set_pose(pose: RagdollPose, immediate: bool = false) -> void:
	if ragdoll == null or pose == null:
		return

	_stop_sequence_internal()

	if immediate:
		_current_pose = pose
		_target_pose = pose
		_blend_t = 1.0
		_current_targets = pose.joint_targets.duplicate()
		_apply_targets()
		_active = true
		pose_reached.emit(pose.pose_name)
	else:
		_target_pose = pose
		_blend_t = 0.0
		_blend_speed = 1.0 / maxf(blend_time, 0.01)
		_active = true


## Play a looping or one-shot sequence of poses.
## hold_times[i] = seconds to hold poses[i] before blending to next.
func play_sequence(seq_name: String, poses: Array[RagdollPose],
		hold_times: Array[float], loop: bool = false) -> void:
	if poses.is_empty():
		return
	_sequence = poses
	_sequence_holds = hold_times
	_sequence_loop = loop
	_sequence_name = seq_name
	_sequence_index = 0
	_sequence_timer = 0.0
	set_pose(poses[0])


## Stop sequence playback (keeps current pose active).
func stop_sequence() -> void:
	_stop_sequence_internal()


## Go fully limp — disable all pose-driven springs.
func clear_pose() -> void:
	_stop_sequence_internal()
	_active = false
	_current_pose = null
	_target_pose = null
	_current_targets.clear()
	_disable_driven_springs()


## Returns true if driving toward or holding a pose.
func is_active() -> bool:
	return _active


func _physics_process(delta: float) -> void:
	if not _active or ragdoll == null:
		return

	# Blend toward target
	if _blend_t < 1.0:
		_blend_t = minf(_blend_t + delta * _blend_speed, 1.0)
		_interpolate_targets()
		_apply_targets()
		if _blend_t >= 1.0:
			_current_pose = _target_pose
			pose_reached.emit(_current_pose.pose_name)

	# Advance sequence timer
	if _sequence_index >= 0:
		_sequence_timer += delta
		var hold_dur: float = _sequence_holds[_sequence_index] if _sequence_index < _sequence_holds.size() else 1.0
		if _sequence_timer >= hold_dur and _blend_t >= 1.0:
			_advance_sequence()


# ──────────────────────────────────────────────────────────────────────────────
#  INTERNAL
# ──────────────────────────────────────────────────────────────────────────────

func _interpolate_targets() -> void:
	if _target_pose == null:
		return
	var prev: Dictionary = _current_pose.joint_targets if _current_pose != null else {}
	var next: Dictionary = _target_pose.joint_targets

	# Gather every joint key from both poses
	var all_keys: Dictionary = {}
	for key: String in prev:
		all_keys[key] = true
	for key: String in next:
		all_keys[key] = true

	var t: float = _smooth_step(_blend_t)
	for key: String in all_keys:
		var from_val: Vector3 = prev.get(key, Vector3.ZERO) as Vector3
		var to_val: Vector3 = next.get(key, Vector3.ZERO) as Vector3
		_current_targets[key] = from_val.lerp(to_val, t)


func _apply_targets() -> void:
	var stiffness_mult: float = 1.0
	if _target_pose != null:
		stiffness_mult = _target_pose.drive_stiffness

	var s: float = spring_stiffness * stiffness_mult
	var d: float = spring_damping * stiffness_mult

	for joint_key: String in _current_targets:
		var joint: Generic6DOFJoint3D = ragdoll.joint_map.get(joint_key) as Generic6DOFJoint3D
		if joint == null:
			continue
		var target: Vector3 = _current_targets[joint_key] as Vector3
		_enable_spring(joint, target, s, d)
		if not _driven_joints.has(joint_key):
			_driven_joints.append(joint_key)


func _enable_spring(joint: Generic6DOFJoint3D, target_deg: Vector3,
		s: float, d: float) -> void:
	# X axis
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, s)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, d)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, deg_to_rad(target_deg.x))
	# Y axis
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, s)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, d)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, deg_to_rad(target_deg.y))
	# Z axis
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, s)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, d)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, deg_to_rad(target_deg.z))


func _disable_driven_springs() -> void:
	if ragdoll == null:
		return
	for joint_key: String in _driven_joints:
		var joint: Generic6DOFJoint3D = ragdoll.joint_map.get(joint_key) as Generic6DOFJoint3D
		if joint == null:
			continue
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
	_driven_joints.clear()


func _advance_sequence() -> void:
	_sequence_index += 1
	_sequence_timer = 0.0
	if _sequence_index >= _sequence.size():
		if _sequence_loop:
			_sequence_index = 0
			set_pose(_sequence[0])
		else:
			var finished_name: String = _sequence_name
			_stop_sequence_internal()
			sequence_finished.emit(finished_name)
			return
	set_pose(_sequence[_sequence_index])


func _stop_sequence_internal() -> void:
	_sequence.clear()
	_sequence_holds.clear()
	_sequence_index = -1
	_sequence_timer = 0.0


func _smooth_step(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
