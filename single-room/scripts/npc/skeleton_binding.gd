class_name SkeletonBinding
extends Node

const SKELETON_REST_POSE = preload("res://scripts/npc/skeleton_rest_pose.gd")
const SKELETON_STAND_ASSIST = preload("res://scripts/npc/skeleton_stand_assist.gd")
const RAGDOLL_PROPORTIONS = preload("res://scripts/npc/ragdoll_proportions.gd")
## Active-ragdoll skeleton binding — mass-proportional position + orientation springs.
##
## Two systems keep the ragdoll upright:
## 1. Per-part position springs — each part is pulled toward its skeleton bone
##    world position. Force = stiffness × mass × error, so heavy parts get
##    stronger springs automatically. Equilibrium sag ≈ g / stiffness.
## 2. Per-joint orientation torques — mass-proportional PD controller drives
##    each joint toward its rest-pose relative rotation; pelvis uses absolute
##    world-space target.
##
## The skeleton writeback runs in _process (not _physics_process) so it reads
## the interpolated visual position from Godot's physics interpolation,
## giving smooth motion at any render framerate.

## ── Tuning ──────────────────────────────────────────────────────────────────

## Position spring stiffness (1/s²). Multiplied by each part's mass so heavy
## parts get proportionally stronger springs.  Effective force = stiffness × mass × error.
## Equilibrium sag under gravity ≈ g / stiffness (≈ 2.5 cm at 400).
@export var spring_stiffness: float = 400.0
## Position spring damping (1/s). Also mass-proportional.
## Critical damping ≈ 2 × √stiffness ≈ 40 at stiffness 400.
@export var spring_damping: float = 40.0
## Angular PD stiffness (1/s²). Mass-proportional corrective torque.
@export var angular_stiffness: float = 80.0
## Angular PD damping (1/s). Mass-proportional angular damping.
@export var angular_damping: float = 12.0
## Maximum torque per unit mass (N·m/kg). Prevents instability on large errors.
@export var max_torque: float = 50.0
## Torque multiplier for grabbed parts (0-1).
## Lower = easier to pull away from pose.
@export_range(0.0, 1.0) var grabbed_motor_ratio: float = 0.05
## How long (seconds) to ramp spring strength from min -> full after spawn.
@export var spawn_ramp_time: float = 0.4
## Minimum motor scale during ramp (prevents free-fall at unfreeze).
@export var spawn_ramp_floor: float = 0.3
## How many physics frames to keep parts frozen after bind (lets Jolt settle).
@export var spawn_freeze_frames: int = 10

@export_group("Recovery")
## When true, ragdoll stays passive while moving and ramps back to active pose.
@export var auto_recover: bool = true
## Time (seconds) to remain passive after motion settles.
@export var recover_delay: float = 0.8
## Ramp time (seconds) to restore full motor strength.
@export var recover_ramp_time: float = 0.8
## Max linear velocity to be considered settled.
@export var recover_linear_threshold: float = 0.35
## Max angular velocity to be considered settled.
@export var recover_angular_threshold: float = 1.5
## Damping multiplier while passive (dead-weight feel).
@export var passive_damp_multiplier: float = 2.5
## Minimum motor scale while passive to keep the body coherent.
@export_range(0.0, 1.0) var passive_motor_floor: float = 0.3
## Spring scale for core parts while passive.
@export var passive_core_scale: float = 1.0
## Spring scale for non-core parts while passive.
@export var passive_limb_scale: float = 0.35
## Low joint PD scale while passive to preserve structure without twitching.
@export_range(0.0, 1.0) var passive_joint_scale: float = 0.15
## Low pelvis lock scale while passive.
@export_range(0.0, 1.0) var passive_pelvis_scale: float = 0.1
## If true, only core parts are used to decide stability.
@export var recover_use_core_parts: bool = true
## Parts treated as core while passive (keeps overall structure).
@export var passive_core_parts: PackedStringArray = [
	"pelvis", "spine_lower", "spine_mid", "spine_upper", "chest", "neck", "head",
	"left_upper_leg", "right_upper_leg", "left_lower_leg", "right_lower_leg",
	"left_upper_arm", "right_upper_arm", "left_forearm", "right_forearm",
]
## If true, widen joint limits while passive.
@export var allow_passive_limit_widen: bool = false

@export_group("Extra Damping")
@export var extra_damping_enabled: bool = false
@export var extra_leg_linear_damp: float = 0.0
@export var extra_leg_angular_damp: float = 0.0
@export var extra_foot_linear_damp: float = 0.0
@export var extra_foot_angular_damp: float = 0.0
@export var extra_leg_parts: PackedStringArray = [
	"left_lower_leg", "right_lower_leg",
]
@export var extra_foot_parts: PackedStringArray = [
	"left_foot", "right_foot", "left_toes", "right_toes",
]

@export_group("Force Clamp")
@export var clamp_force_enabled: bool = false
@export var clamp_force_z: float = 0.0
@export var clamp_force_parts: PackedStringArray = [
	"chest",
	"left_lower_leg", "right_lower_leg",
	"left_foot", "right_foot", "left_toes", "right_toes",
]

@export_group("Target Offset")
@export var target_z_offset_enabled: bool = false
@export var target_z_offset: float = 0.0
@export var target_z_offset_parts: PackedStringArray = [
	"chest",
	"left_lower_leg", "right_lower_leg",
	"left_foot", "right_foot", "left_toes", "right_toes",
]
@export var target_z_offset_chest: float = 0.0
@export var target_z_offset_legs: float = 0.0
@export var target_z_offset_feet: float = 0.0

@export_group("Rest Pose Fix")
@export var rest_forward_fix_enabled: bool = false

@export_group("Stand Assist")
## Adds a pelvis lift + upright torque during recovery.
@export var stand_assist_enabled: bool = true
## Vertical spring strength for pelvis lift (1/s^2).
@export var stand_up_force: float = 18.0
## Vertical damping for pelvis lift (1/s).
@export var stand_up_damping: float = 6.0
## Max lift force per unit mass (N/kg).
@export var stand_up_max_force: float = 80.0
## Upright torque strength (1/s^2).
@export var stand_up_torque: float = 14.0
## Upright torque damping (1/s).
@export var stand_up_torque_damping: float = 4.0
## Minimum recovery scale before assist kicks in.
@export_range(0.0, 1.0) var stand_up_min_scale: float = 0.1

## ── References ──────────────────────────────────────────────────────────────

## The Skeleton3D from the imported model scene.
var skeleton: Skeleton3D = null

## Reference to the ragdoll builder that owns the physics parts.
var ragdoll: HumanoidRagdollBuilder = null

## Cached mapping: bone_idx (int) → BodyPart node.
var _bone_to_part: Dictionary = {}

## Cached mapping: bone_idx (int) → Generic6DOFJoint3D (the joint where this
## part is node_b / child). Pelvis has no joint entry.
var _bone_to_joint: Dictionary = {}

## Cached rest-pose transforms: bone_idx → Transform3D (skeleton-local).
## Motors drive toward these stable poses.
var _rest_poses: Dictionary = {}

## Reverse lookup: BodyPart → bone_idx.
var _part_to_bone: Dictionary = {}

## Cached rest-pose RELATIVE quaternion per joint: bone_idx → Quaternion.
## Each is parent_rest.inverse() * child_rest — the rotation the joint should
## maintain regardless of parent’s world orientation.
var _rest_relative: Dictionary = {}
var _unmatched_bones: PackedStringArray = []

## Spawn-ramp state.
var _spawn_elapsed: float = 0.0
var _spawn_frames: int = 0
var _parts_frozen: bool = true
var _motor_scale: float = 0.0
var _spawn_cached: bool = false
var _spawn_origin: Vector3 = Vector3.ZERO
var _spawn_pelvis_position: Vector3 = Vector3.ZERO
var _last_spring_force: Vector3 = Vector3.ZERO
var _last_stand_force: Vector3 = Vector3.ZERO
var _last_total_force: Vector3 = Vector3.ZERO
var _last_force_top_parts: Array = []
var _npc_name: String = ""
var _pelvis_bone_idx: int = -1
var _bone_targets_local: Dictionary = {}
var _use_pelvis_targets: bool = false
var _joint_limit_cache: Dictionary = {}
var _limits_disabled: bool = false
var _debug_disable_limits: bool = false
var _auto_disable_limits: bool = false
var _enable_position_springs: bool = true
var _enable_joint_pd: bool = true
var _enable_pelvis_lock: bool = true
var _use_physics_rest_relative: bool = true
var _rest_pelvis_height: float = 0.0
var _recover_scale: float = 1.0
var _recover_timer: float = 0.0
var _recover_passive: bool = false
var _forced_sleep: bool = false
var _damping_cache: Dictionary = {}
var _passive_core_lookup: Dictionary = {}
var _diag_frames: int = 0
var _diag: Node = null

## If true, placeholder debug meshes on ragdoll parts are hidden
## (because the real skinned mesh is visible instead).
var hide_placeholder_meshes: bool = true


func _ready() -> void:
	set_physics_process(false)
	set_process(false)


## Call once after both skeleton and ragdoll are ready.
func bind(p_skeleton: Skeleton3D, p_ragdoll: HumanoidRagdollBuilder) -> void:
	skeleton = p_skeleton
	ragdoll = p_ragdoll

	if skeleton == null or ragdoll == null:
		push_error("[SkeletonBinding] bind() called with null skeleton or ragdoll")
		return

	_build_bone_mapping()
	_build_joint_mapping()

	# Cache rest poses BEFORE any writeback corrupts them.
	# Motors will always drive toward these stable targets.
	SKELETON_REST_POSE.cache_rest_poses(self)
	_cache_bone_targets()
	_cache_joint_limits()

	add_to_group(&"ragdoll_binding")
	_diag = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	if _diag != null:
		_diag.register_binding(self)

	# Teleport parts to bone positions before springs kick in
	_snap_parts_to_bones()
	_cache_spawn_origin()
	SKELETON_STAND_ASSIST.cache_rest_pelvis_height(self)
	SKELETON_REST_POSE.refresh_rest_relative(self)
	_cache_part_damping()
	_apply_passive_damping(false)
	_build_passive_core_lookup()
	_report_diag_event("after_snap")

	# Cache NPC name for diagnostics
	var npc_owner: Node = ragdoll.get_parent()
	if npc_owner != null and npc_owner.has_method(&"get"):
		_npc_name = str(npc_owner.get(&"npc_name"))
	elif npc_owner != null:
		_npc_name = str(npc_owner.name)
	else:
		_npc_name = "?"

	# Diagnostic: show part positions after initial snap
	_log_part_bounds("after_snap")
	print("[SkeletonBinding] rest_source=%s limits=%s springs=%s pd=%s pelvis_lock=%s" % [
		"PHYS" if _use_physics_rest_relative else "BONE",
		"OFF" if _limits_disabled else "ON",
		"ON" if _enable_position_springs else "OFF",
		"ON" if _enable_joint_pd else "OFF",
		"ON" if _enable_pelvis_lock else "OFF",
	])

	if hide_placeholder_meshes:
		_hide_debug_meshes()

	set_physics_process(true)
	set_process(true)
	print("[SkeletonBinding] Active ragdoll bound — %d bones, %d joints, spring=%.0f ang=%.0f" % [
		_bone_to_part.size(), _bone_to_joint.size(), spring_stiffness, angular_stiffness])


func _physics_process(delta: float) -> void:
	if skeleton == null or ragdoll == null:
		return

	# ── Spawn ramp: freeze → unfreeze → ramp motors ─────────────────────
	_spawn_frames += 1
	if _parts_frozen:
		# Parts are genuinely frozen (RigidBody3D.freeze = true).
		# No need to re-snap — they stay put.
		if _spawn_frames >= spawn_freeze_frames:
			_log_part_bounds("pre_unfreeze")
			_report_diag_event("pre_unfreeze")
			_unfreeze_all_parts()
			_parts_frozen = false
			_log_part_bounds("post_unfreeze")
			_report_diag_event("post_unfreeze")
		return

	# Ramp motor scale from spawn_ramp_floor → 1 over spawn_ramp_time
	if _spawn_elapsed < spawn_ramp_time:
		_spawn_elapsed += delta
		var t: float = clampf(_spawn_elapsed / spawn_ramp_time, 0.0, 1.0)
		_motor_scale = lerpf(spawn_ramp_floor, 1.0, t)
	else:
		_motor_scale = 1.0

	_update_recovery(delta)

	_update_motor_targets()

	# Diagnostic: log first 30 frames after unfreeze (every 10th frame)
	_diag_frames += 1
	if _diag_frames <= 30 and _diag_frames % 10 == 0:
		_log_part_bounds("dynamic_frame_%d" % _diag_frames)
		_report_diag_event("dynamic_frame_%d" % _diag_frames)


## Writeback runs in _process (render frame), reading interpolated transforms
## from Godot's physics interpolation for smooth motion.
func _process(_delta: float) -> void:
	if skeleton == null or ragdoll == null or _parts_frozen:
		return
	_write_skeleton_from_physics()


## ── Corrective Torques ──────────────────────────────────────────────────────

## Apply corrective torques via apply_torque() — works in world space,
## no joint-frame ambiguity. Each joint computes RELATIVE rotation error
## (child vs parent), pelvis uses ABSOLUTE world-space target.
func _update_motor_targets() -> void:
	# ── Per-part position springs (mass-proportional) ────────────────
	# F = (error × stiffness − velocity × damping) × mass × ramp.
	# Mass-proportional means every part has the same natural frequency
	# regardless of weight — heavy parts get stronger springs automatically.
	var motor_scale: float = _motor_scale * _recover_scale
	var spring_scale: float = motor_scale
	var joint_scale: float = motor_scale
	var pelvis_scale: float = motor_scale
	_last_spring_force = Vector3.ZERO
	_last_stand_force = Vector3.ZERO
	_last_force_top_parts.clear()
	var force_entries: Array = []
	if _recover_passive:
		spring_scale = max(spring_scale, passive_motor_floor)
		joint_scale = max(joint_scale, passive_joint_scale)
		pelvis_scale = max(pelvis_scale, passive_pelvis_scale)
	if _enable_position_springs and spring_scale > 0.0:
		for bone_idx: int in _bone_to_part:
			var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
			var target_pos: Vector3 = _get_target_position(bone_idx)
			var pos_error: Vector3 = target_pos - part.global_position
			var pos_force: Vector3 = (pos_error * spring_stiffness - part.linear_velocity * spring_damping) * part.mass
			var part_scale: float = 1.0
			if _recover_passive:
				part_scale = passive_core_scale if _is_core_part(part.part_name) else passive_limb_scale
			pos_force *= spring_scale * part_scale
			if part.grabbed_by != null:
				pos_force *= grabbed_motor_ratio
			if clamp_force_enabled and clamp_force_z > 0.0 and clamp_force_parts.has(part.part_name):
				pos_force.z = clampf(pos_force.z, -clamp_force_z, clamp_force_z)
			_last_spring_force += pos_force
			force_entries.append({
				"part": part.part_name,
				"x": pos_force.x,
				"y": pos_force.y,
				"z": pos_force.z,
				"mag": pos_force.length(),
			})
			part.apply_central_force(pos_force)
	if force_entries.size() > 0:
		force_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("mag", 0.0)) > float(b.get("mag", 0.0))
		)
		var limit: int = min(5, force_entries.size())
		for i: int in range(limit):
			_last_force_top_parts.append(force_entries[i])

	# ── Joint PD torques (relative rotation) ────────────────────────────
	if _enable_joint_pd and joint_scale > 0.0:
		for bone_idx: int in _bone_to_joint:
			var joint: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
			var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
			var parent_part: RigidBody3D = joint.get_node(joint.node_a) as RigidBody3D

			# Target child orientation = parent’s CURRENT world rotation * rest relative
			var parent_quat: Quaternion = parent_part.global_basis.get_rotation_quaternion()
			var target_quat: Quaternion = parent_quat * _rest_relative[bone_idx]

			# Quaternion difference: how far is the child from the target?
			var current_quat: Quaternion = part.global_basis.get_rotation_quaternion()
			var diff: Quaternion = target_quat * current_quat.inverse()
			if diff.w < 0.0:
				diff = -diff

			var axis: Vector3 = Vector3(diff.x, diff.y, diff.z)
			var sin_half: float = axis.length()

			# P-term: corrective torque proportional to angle error × mass
			var torque: Vector3 = Vector3.ZERO
			if sin_half > 0.001:
				axis = axis / sin_half
				var angle: float = 2.0 * atan2(sin_half, diff.w)
				if angle > PI:
					angle -= TAU
				torque = axis * angle * angular_stiffness * part.mass

			# D-term: damp RELATIVE angular velocity (child vs parent) × mass
			var rel_ang_vel: Vector3 = part.angular_velocity - parent_part.angular_velocity
			torque -= rel_ang_vel * angular_damping * part.mass

			# Scale by spawn ramp, recovery ramp, and passive floor
			torque *= joint_scale

			# Clamp torque to prevent instability (mass-scaled limit)
			var torque_limit: float = max_torque * part.mass
			var mag: float = torque.length()
			if mag > torque_limit:
				torque = torque * (torque_limit / mag)

			# Reduce torque when grabbed
			if part.grabbed_by != null:
				torque *= grabbed_motor_ratio

			part.apply_torque(torque)

	# ── Pelvis stabilization (world-space absolute target) ──────────────
	if _enable_pelvis_lock and pelvis_scale > 0.0 and _pelvis_bone_idx >= 0 and _bone_to_part.has(_pelvis_bone_idx):
		var pelvis: BodyPart = _bone_to_part[_pelvis_bone_idx] as BodyPart
		var pelvis_target: Transform3D = skeleton.global_transform * _rest_poses[_pelvis_bone_idx]
		var p_target_q: Quaternion = pelvis_target.basis.get_rotation_quaternion()
		var p_current_q: Quaternion = pelvis.global_basis.get_rotation_quaternion()
		var p_diff: Quaternion = p_target_q * p_current_q.inverse()
		if p_diff.w < 0.0:
			p_diff = -p_diff

		var p_axis: Vector3 = Vector3(p_diff.x, p_diff.y, p_diff.z)
		var p_sin: float = p_axis.length()

		var p_torque: Vector3 = Vector3.ZERO
		if p_sin > 0.001:
			p_axis = p_axis / p_sin
			var p_angle: float = 2.0 * atan2(p_sin, p_diff.w)
			if p_angle > PI:
				p_angle -= TAU
			p_torque = p_axis * p_angle * angular_stiffness * 1.5 * pelvis.mass

		p_torque -= pelvis.angular_velocity * angular_damping * 1.5 * pelvis.mass
		p_torque *= pelvis_scale

		var p_torque_limit: float = max_torque * 1.5 * pelvis.mass
		var p_mag: float = p_torque.length()
		if p_mag > p_torque_limit:
			p_torque = p_torque * (p_torque_limit / p_mag)

		if pelvis.grabbed_by != null:
			p_torque *= grabbed_motor_ratio

		pelvis.apply_torque(p_torque)

	SKELETON_STAND_ASSIST.apply_stand_assist(self, motor_scale)
	_last_total_force = _last_spring_force + _last_stand_force


## ── Skeleton Writeback ──────────────────────────────────────────────────────

## Write physics body transforms back into skeleton bone poses so the skinned
## mesh follows the ragdoll. Uses set_bone_global_pose_override for direct
## world-space mapping — no parent chain recomputation needed.
func _write_skeleton_from_physics() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var skel_inv: Transform3D = skeleton.global_transform.affine_inverse()
		var part_in_skel: Transform3D = skel_inv * part.global_transform
		skeleton.set_bone_global_pose_override(bone_idx, part_in_skel, 1.0, true)


## ── Bone Mapping (delegates to SkeletonBoneMapper) ──────────────────────────

func _build_bone_mapping() -> void:
	var result: Dictionary = SkeletonBoneMapper.build_bone_mapping(skeleton, ragdoll.parts)
	_bone_to_part = result["bone_to_part"]
	_part_to_bone = result["part_to_bone"]
	_unmatched_bones = result["unmatched_bones"]


func _build_joint_mapping() -> void:
	var result: Dictionary = SkeletonBoneMapper.build_joint_mapping(
		_bone_to_part, ragdoll.child_to_joint)
	_bone_to_joint = result["bone_to_joint"]
	_pelvis_bone_idx = result["pelvis_bone_idx"]


## ── Helpers ─────────────────────────────────────────────────────────────────

## Teleport all mapped ragdoll parts to their skeleton bone positions
## and freeze them so Jolt doesn't disturb them during the settle period.
## Called once at bind time.
func _snap_parts_to_bones() -> void:
	# Pre-calculate offsets before ANY part moves.
	# Joint positions depend on parent parts, which might move during the loop.
	var part_offsets: Dictionary = {}
	for bone_idx: int in _bone_to_part:
		if _bone_to_joint.has(bone_idx):
			var p: BodyPart = _bone_to_part[bone_idx] as BodyPart
			var j: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
			# Vector pointing from Joint to Part Center, in Part's local space.
			# Local space is rotation-invariant if Part and Skeleton rotation match.
			var offset_local: Vector3 = p.global_transform.basis.inverse() * (p.global_transform.origin - j.global_transform.origin)
			part_offsets[bone_idx] = offset_local

	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		# Use _rest_poses (idle-adjusted) when available, otherwise raw skeleton pose
		var bone_global: Transform3D
		if _rest_poses.has(bone_idx):
			bone_global = skeleton.global_transform * _rest_poses[bone_idx]
		else:
			bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
		
		# CRITICAL FIX: The Ragdoll part center is NOT at the joint (bone start).
		# It is offset by half its length (or similar).
		# The Joint (Generic6DOFJoint3D) is at the bone start.
		# We must maintain the relative offset between Part and Joint.
		var joint: Generic6DOFJoint3D = null
		if _bone_to_joint.has(bone_idx):
			joint = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
		
		# If we have a joint, we can calculate the correct offset.
		# If not (e.g. Pelvis), bone_global center is likely correct (or close enough).
		if joint != null and part_offsets.has(bone_idx):
			var final_offset: Vector3 = part_offsets[bone_idx]
			
			# Apply to new bone pose
			# New Part Pos = Bone Pos + (Bone Basis * offset_local)
			var new_origin: Vector3 = bone_global.origin + (bone_global.basis * final_offset)
			part.global_transform = Transform3D(bone_global.basis, new_origin)
		else:
			# Fallback for root/pelvis
			part.global_transform = bone_global

		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
		# Actually freeze the RigidBody3D so Jolt ignores it during settle
		part.freeze = true
	_snap_joints_to_bones()


func _cache_joint_limits() -> void:
	_joint_limit_cache.clear()
	for bone_idx: int in _bone_to_joint:
		var joint: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
		_joint_limit_cache[bone_idx] = {
			"x": {
				"lower": joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),
				"upper": joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),
			},
			"y": {
				"lower": joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),
				"upper": joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),
			},
			"z": {
				"lower": joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),
				"upper": joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),
			},
		}


func apply_debug_overrides(config: RagdollDebugConfig) -> void:
	if config == null:
		return
	_debug_disable_limits = config.disable_joint_limits
	_apply_joint_limit_override(_debug_disable_limits or _auto_disable_limits)
	_enable_position_springs = not config.disable_position_springs
	_enable_joint_pd = not config.disable_joint_pd
	_enable_pelvis_lock = not config.disable_pelvis_lock
	if _use_physics_rest_relative != config.use_physics_rest_relative:
		_use_physics_rest_relative = config.use_physics_rest_relative
		SKELETON_REST_POSE.refresh_rest_relative(self)
	if not auto_recover:
		_set_passive_state(false)
		_recover_scale = 1.0
		_recover_timer = 0.0


func apply_runtime_overrides(overrides: Dictionary) -> void:
	if overrides.is_empty():
		return
	for key: String in overrides:
		var val: Variant = overrides[key]
		match key:
			"spring_stiffness":
				spring_stiffness = float(val)
			"spring_damping":
				spring_damping = float(val)
			"angular_stiffness":
				angular_stiffness = float(val)
			"angular_damping":
				angular_damping = float(val)
			"max_torque":
				max_torque = float(val)
			"grabbed_motor_ratio":
				grabbed_motor_ratio = float(val)
			"spawn_ramp_time":
				spawn_ramp_time = float(val)
			"spawn_ramp_floor":
				spawn_ramp_floor = float(val)
			"spawn_freeze_frames":
				spawn_freeze_frames = int(val)
			"passive_motor_floor":
				passive_motor_floor = float(val)
			"passive_core_scale":
				passive_core_scale = float(val)
			"passive_limb_scale":
				passive_limb_scale = float(val)
			"passive_joint_scale":
				passive_joint_scale = float(val)
			"passive_pelvis_scale":
				passive_pelvis_scale = float(val)
			"passive_damp_multiplier":
				passive_damp_multiplier = float(val)
			"recover_delay":
				recover_delay = float(val)
			"recover_ramp_time":
				recover_ramp_time = float(val)
			"recover_linear_threshold":
				recover_linear_threshold = float(val)
			"recover_angular_threshold":
				recover_angular_threshold = float(val)
			"recover_use_core_parts":
				recover_use_core_parts = bool(val)
			"allow_passive_limit_widen":
				allow_passive_limit_widen = bool(val)
			"stand_up_force":
				stand_up_force = float(val)
			"stand_up_damping":
				stand_up_damping = float(val)
			"stand_up_max_force":
				stand_up_max_force = float(val)
			"stand_up_torque":
				stand_up_torque = float(val)
			"stand_up_torque_damping":
				stand_up_torque_damping = float(val)
			"stand_up_min_scale":
				stand_up_min_scale = float(val)
			"auto_recover":
				auto_recover = bool(val)
			"stand_assist_enabled":
				stand_assist_enabled = bool(val)
			"extra_damping_enabled":
				extra_damping_enabled = bool(val)
			"extra_leg_linear_damp":
				extra_leg_linear_damp = float(val)
			"extra_leg_angular_damp":
				extra_leg_angular_damp = float(val)
			"extra_foot_linear_damp":
				extra_foot_linear_damp = float(val)
			"extra_foot_angular_damp":
				extra_foot_angular_damp = float(val)
			"clamp_force_enabled":
				clamp_force_enabled = bool(val)
			"clamp_force_z":
				clamp_force_z = float(val)
			"target_z_offset_enabled":
				target_z_offset_enabled = bool(val)
			"target_z_offset":
				target_z_offset = float(val)
			"target_z_offset_chest":
				target_z_offset_chest = float(val)
			"target_z_offset_legs":
				target_z_offset_legs = float(val)
			"target_z_offset_feet":
				target_z_offset_feet = float(val)
			"rest_forward_fix_enabled":
				rest_forward_fix_enabled = bool(val)
			_:
				pass
	_apply_passive_damping(_recover_passive)


func _apply_joint_limit_override(disable_limits: bool) -> void:
	if disable_limits == _limits_disabled:
		return
	_limits_disabled = disable_limits
	for bone_idx: int in _bone_to_joint:
		var joint: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
		if disable_limits:
			var wide: float = deg_to_rad(179.0)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -wide)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, wide)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -wide)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, wide)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -wide)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, wide)
		else:
			var cached: Dictionary = _joint_limit_cache.get(bone_idx, {}) as Dictionary
			if cached.is_empty():
				continue
			var x_vals: Dictionary = cached.get("x", {}) as Dictionary
			var y_vals: Dictionary = cached.get("y", {}) as Dictionary
			var z_vals: Dictionary = cached.get("z", {}) as Dictionary
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, float(x_vals.get("lower", 0.0)))
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, float(x_vals.get("upper", 0.0)))
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, float(y_vals.get("lower", 0.0)))
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, float(y_vals.get("upper", 0.0)))
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, float(z_vals.get("lower", 0.0)))
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, float(z_vals.get("upper", 0.0)))


func _cache_part_damping() -> void:
	_damping_cache.clear()
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		_damping_cache[part] = {
			"lin": part.linear_damp,
			"ang": part.angular_damp,
			"sleep": part.can_sleep,
		}


func _build_passive_core_lookup() -> void:
	_passive_core_lookup.clear()
	for core_name: String in passive_core_parts:
		_passive_core_lookup[core_name] = true


func _is_core_part(part_name: String) -> bool:
	return _passive_core_lookup.has(part_name)


func _cache_spawn_origin() -> void:
	_spawn_cached = true
	if ragdoll is Node3D:
		_spawn_origin = (ragdoll as Node3D).global_position
	else:
		_spawn_origin = Vector3.ZERO
	_spawn_pelvis_position = _spawn_origin
	if ragdoll != null and ragdoll.parts.has("pelvis"):
		var pelvis: BodyPart = ragdoll.parts["pelvis"] as BodyPart
		if pelvis != null:
			_spawn_pelvis_position = pelvis.global_position


func _apply_passive_damping(passive: bool) -> void:
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		var cached: Dictionary = _damping_cache.get(part, {}) as Dictionary
		var base_lin: float = float(cached.get("lin", part.linear_damp))
		var base_ang: float = float(cached.get("ang", part.angular_damp))
		var lin: float = base_lin
		var ang: float = base_ang
		if passive:
			lin *= passive_damp_multiplier
			ang *= passive_damp_multiplier
			part.can_sleep = true
		else:
			part.can_sleep = false
		var extra: Vector2 = _get_extra_damping(part.part_name)
		lin += extra.x
		ang += extra.y
		part.linear_damp = lin
		part.angular_damp = ang


func _get_extra_damping(part_name: String) -> Vector2:
	if not extra_damping_enabled:
		return Vector2.ZERO
	var lin: float = 0.0
	var ang: float = 0.0
	if extra_leg_parts.has(part_name):
		lin += extra_leg_linear_damp
		ang += extra_leg_angular_damp
	if extra_foot_parts.has(part_name):
		lin += extra_foot_linear_damp
		ang += extra_foot_angular_damp
	return Vector2(lin, ang)


func _set_passive_state(passive: bool) -> void:
	if _recover_passive == passive:
		return
	_recover_passive = passive
	_apply_passive_damping(passive)


func set_forced_sleep(enabled: bool) -> void:
	_forced_sleep = enabled
	if _forced_sleep:
		_recover_scale = 0.0
		_recover_timer = 0.0
		_auto_disable_limits = allow_passive_limit_widen
		_apply_joint_limit_override(_debug_disable_limits or _auto_disable_limits)
		_set_passive_state(true)
		return
	_auto_disable_limits = false
	_apply_joint_limit_override(_debug_disable_limits)
	_set_passive_state(false)
	_recover_scale = 1.0
	_recover_timer = 0.0


func is_forced_sleeping() -> bool:
	return _forced_sleep


func _is_unstable() -> bool:
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		if recover_use_core_parts and not _is_core_part(part.part_name):
			continue
		if part.grabbed_by != null:
			return true
		if part.linear_velocity.length() > recover_linear_threshold:
			return true
		if part.angular_velocity.length() > recover_angular_threshold:
			return true
	return false


func _update_recovery(delta: float) -> void:
	if _forced_sleep:
		_recover_scale = 0.0
		_recover_timer = 0.0
		_auto_disable_limits = allow_passive_limit_widen
		_apply_joint_limit_override(_debug_disable_limits or _auto_disable_limits)
		_set_passive_state(true)
		return
	if not auto_recover:
		_recover_scale = 1.0
		_recover_timer = 0.0
		_auto_disable_limits = false
		_apply_joint_limit_override(_debug_disable_limits)
		_set_passive_state(false)
		return
	if _is_unstable():
		_recover_timer = 0.0
		_recover_scale = 0.0
		_auto_disable_limits = allow_passive_limit_widen
		_apply_joint_limit_override(_debug_disable_limits or _auto_disable_limits)
		_set_passive_state(true)
		return
	if _recover_scale < 1.0:
		_recover_timer += delta
		if _recover_timer < recover_delay:
			_set_passive_state(true)
			return
		_set_passive_state(false)
		_auto_disable_limits = allow_passive_limit_widen
		_apply_joint_limit_override(_debug_disable_limits or _auto_disable_limits)
		var ramp: float = max(recover_ramp_time, 0.01)
		_recover_scale = minf(1.0, _recover_scale + delta / ramp)
		if _recover_scale >= 1.0:
			_auto_disable_limits = false
			_apply_joint_limit_override(_debug_disable_limits)
			_set_passive_state(false)
		return
	_recover_timer = 0.0
	_auto_disable_limits = false
	_apply_joint_limit_override(_debug_disable_limits)
	_set_passive_state(false)


func _cache_bone_targets() -> void:
	_bone_targets_local.clear()
	_use_pelvis_targets = false
	if _pelvis_bone_idx >= 0 and _rest_poses.has(_pelvis_bone_idx):
		_use_pelvis_targets = true
		var pelvis_rest: Transform3D = _rest_poses[_pelvis_bone_idx]
		var pelvis_inv: Transform3D = pelvis_rest.affine_inverse()
		for bone_idx: int in _bone_to_part:
			var rest_pose: Transform3D = _rest_poses[bone_idx]
			_bone_targets_local[bone_idx] = pelvis_inv * rest_pose
		return
	for bone_idx: int in _bone_to_part:
		_bone_targets_local[bone_idx] = _rest_poses[bone_idx]


func _get_target_position(bone_idx: int) -> Vector3:
	if _use_pelvis_targets and _pelvis_bone_idx >= 0:
		var pelvis_part: BodyPart = _bone_to_part[_pelvis_bone_idx] as BodyPart
		var local_pose: Transform3D = _bone_targets_local[bone_idx] as Transform3D
		var target: Vector3 = (pelvis_part.global_transform * local_pose).origin
		return _apply_target_z_offset(bone_idx, target)
	var rest_pose: Transform3D = _bone_targets_local[bone_idx] as Transform3D
	var target_world: Vector3 = (skeleton.global_transform * rest_pose).origin
	return _apply_target_z_offset(bone_idx, target_world)


func _apply_target_z_offset(bone_idx: int, target: Vector3) -> Vector3:
	if not target_z_offset_enabled or target_z_offset == 0.0:
		return target
	if not _bone_to_part.has(bone_idx):
		return target
	var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
	if part == null:
		return target
	if not target_z_offset_parts.has(part.part_name):
		return target
	var out: Vector3 = target
	var offset: float = target_z_offset
	if part.part_name == "chest":
		offset = target_z_offset_chest
	elif part.part_name.ends_with("_lower_leg"):
		offset = target_z_offset_legs
	elif part.part_name.ends_with("_foot") or part.part_name.ends_with("_toes"):
		offset = target_z_offset_feet
	out.z += offset
	return out


func _snap_joints_to_bones() -> void:
	for bone_idx: int in _bone_to_joint:
		var joint: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var child_rest: Transform3D = _get_rest_pose_world(bone_idx)
		var parent_part: BodyPart = joint.get_node(joint.node_a) as BodyPart
		if parent_part != null and _part_to_bone.has(parent_part):
			var parent_idx: int = _part_to_bone[parent_part] as int
			var parent_rest: Transform3D = _get_rest_pose_world(parent_idx)
			var bone_dir_world: Vector3 = child_rest.origin - parent_rest.origin
			var local_basis: Basis = _build_joint_basis_local(parent_part.global_basis, bone_dir_world)
			var local_pos: Vector3 = parent_part.to_local(child_rest.origin)
			joint.transform = Transform3D(local_basis, local_pos)
		else:
			joint.global_transform = child_rest


func _get_rest_pose_world(bone_idx: int) -> Transform3D:
	if _rest_poses.has(bone_idx):
		return skeleton.global_transform * _rest_poses[bone_idx]
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)


func _build_joint_basis_local(parent_basis_world: Basis, bone_dir_world: Vector3) -> Basis:
	if bone_dir_world.length() < 0.0001:
		return Basis.IDENTITY
	var inv_parent: Basis = parent_basis_world.inverse()
	var y_axis: Vector3 = (inv_parent * bone_dir_world).normalized()
	var ref_axis: Vector3 = Vector3.RIGHT
	if absf(y_axis.dot(ref_axis)) > 0.95:
		ref_axis = Vector3.FORWARD
	var z_axis: Vector3 = y_axis.cross(ref_axis).normalized()
	if z_axis.length() < 0.0001:
		ref_axis = Vector3.UP
		z_axis = y_axis.cross(ref_axis).normalized()
	var x_axis: Vector3 = z_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _unfreeze_all_parts() -> void:
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		part.freeze = false
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO


func _log_part_bounds(tag: String) -> void:
	var min_y: float = 999.0
	var max_y: float = -999.0
	var max_dist: float = 0.0
	var worst_part: String = ""
	var npc_origin: Vector3 = ragdoll.global_position
	var frozen_count: int = 0
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		var py: float = part.global_position.y
		if py < min_y:
			min_y = py
		if py > max_y:
			max_y = py
		var dist: float = part.global_position.distance_to(npc_origin)
		if dist > max_dist:
			max_dist = dist
			worst_part = part_name_key
		if part.freeze:
			frozen_count += 1
	print("[Ragdoll:%s] %s — y=[%.2f..%.2f] max_dist=%.2f(%s) frozen=%d/%d" % [
		_npc_name, tag, min_y, max_y, max_dist, worst_part,
		frozen_count, ragdoll.parts.size()])


func snap_parts_to_rest_pose() -> void:
	if ragdoll == null or skeleton == null:
		return
	_snap_parts_to_bones()


func freeze_parts() -> void:
	if ragdoll == null:
		return
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		part.freeze = true
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO


func unfreeze_parts() -> void:
	_unfreeze_all_parts()


func get_npc_name() -> String:
	return _npc_name


func has_spawn_origin() -> bool:
	return _spawn_cached


func get_spawn_origin() -> Vector3:
	return _spawn_origin


func get_spawn_pelvis_position() -> Vector3:
	return _spawn_pelvis_position


func get_rest_pelvis_height() -> float:
	return _rest_pelvis_height


func get_current_pelvis_position() -> Vector3:
	if ragdoll != null and ragdoll.parts.has("pelvis"):
		var pelvis: BodyPart = ragdoll.parts["pelvis"] as BodyPart
		if pelvis != null:
			return pelvis.global_position
	if ragdoll is Node3D:
		return (ragdoll as Node3D).global_position
	return Vector3.ZERO


func get_force_budget() -> Dictionary:
	var top_parts: Array = _last_force_top_parts
	if top_parts.is_empty():
		top_parts = _compute_force_top_parts()
		_last_force_top_parts = top_parts.duplicate(true)
	return {
		"spring": _last_spring_force,
		"stand": _last_stand_force,
		"total": _last_total_force,
		"top_parts": top_parts.duplicate(true),
	}


func get_force_top_parts_debug() -> Array:
	var top_parts: Array = _compute_force_top_parts()
	_last_force_top_parts = top_parts.duplicate(true)
	return top_parts


func _compute_force_top_parts() -> Array:
	var motor_scale: float = _motor_scale * _recover_scale
	var spring_scale: float = motor_scale
	if _recover_passive:
		spring_scale = max(spring_scale, passive_motor_floor)
	if not _enable_position_springs:
		spring_scale = 0.0
	var force_entries: Array = []
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var target_pos: Vector3 = _get_target_position(bone_idx)
		var pos_error: Vector3 = target_pos - part.global_position
		var pos_force: Vector3 = (pos_error * spring_stiffness - part.linear_velocity * spring_damping) * part.mass
		var part_scale: float = 1.0
		if _recover_passive:
			part_scale = passive_core_scale if _is_core_part(part.part_name) else passive_limb_scale
		pos_force *= spring_scale * part_scale
		if part.grabbed_by != null:
			pos_force *= grabbed_motor_ratio
		force_entries.append({
			"part": part.part_name,
			"x": pos_force.x,
			"y": pos_force.y,
			"z": pos_force.z,
			"mag": pos_force.length(),
		})
	if force_entries.is_empty():
		return []
	force_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("mag", 0.0)) > float(b.get("mag", 0.0))
	)
	var out: Array = []
	var limit: int = min(5, force_entries.size())
	for i: int in range(limit):
		out.append(force_entries[i])
	return out


func get_unmatched_bones() -> PackedStringArray:
	return _unmatched_bones.duplicate()


func get_debug_part_entries() -> Array[Dictionary]:
	return SkeletonDebugQueries.get_debug_part_entries(self)


func get_debug_joint_entries() -> Array[Dictionary]:
	return SkeletonDebugQueries.get_debug_joint_entries(self)


func get_snapshot_data(max_parts: int, max_joints: int) -> Dictionary:
	return SkeletonDebugQueries.get_snapshot_data(self, max_parts, max_joints)


func _log_arm_pose_metrics() -> void:
	SkeletonDebugQueries.log_arm_pose_metrics(self)


func _report_diag_event(tag: String) -> void:
	return # Disabled to prevent log spam/crash
	if _diag == null:
		return
	_diag.report_event(self, tag)


## Hide the placeholder debug spheres/capsules since we now have a real mesh.
func _hide_debug_meshes() -> void:
	var hidden_count: int = 0
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		hidden_count += _hide_meshes_recursive(part)
	print("[SkeletonBinding] Hidden %d placeholder meshes" % hidden_count)


## Recursively hide all MeshInstance3D nodes under a given root.
func _hide_meshes_recursive(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
			count += 1
		count += _hide_meshes_recursive(child)
	return count
