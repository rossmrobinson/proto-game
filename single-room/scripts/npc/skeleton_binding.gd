class_name SkeletonBinding
extends Node
## Active-ragdoll skeleton binding — MOTOR-DRIVEN architecture.
##
## Instead of applying external forces (which fight the constraint solver and
## cause jitter), this drives each joint's angular motor to reach a target
## velocity proportional to the pose error. Motors are solved INSIDE the
## constraint solver simultaneously with joint limits — zero energy injection
## → zero jitter.
##
## The skeleton writeback runs in _process (not _physics_process) so it reads
## the interpolated visual position from Godot's physics interpolation,
## giving smooth motion at any render framerate.

## ── Tuning ──────────────────────────────────────────────────────────────────

## Motor gain (1/s). Higher = faster convergence to rest pose.
## Angular target velocity = axis * angle * motor_gain.
@export var motor_gain: float = 20.0
## Damping gain for relative angular velocity (D-term of PD controller).
## Resists relative spin between parent and child to prevent overshoot.
@export var motor_damping: float = 0.8
## Motor torque limit multiplier for grabbed parts (0-1).
## Lower = easier to pull away from pose.
@export_range(0.0, 1.0) var grabbed_motor_ratio: float = 0.05
## How long (seconds) to ramp motor strength from 0 → full after spawn.
@export var spawn_ramp_time: float = 0.0
## How many physics frames to keep parts frozen after bind (lets Jolt settle).
@export var spawn_freeze_frames: int = 10

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

## Spawn-ramp state.
var _spawn_elapsed: float = 0.0
var _spawn_frames: int = 0
var _parts_frozen: bool = true
var _motor_scale: float = 0.0
var _npc_name: String = ""

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

	# Ensure reverse bone map is populated
	HumanoidRagdollBuilder._init_reverse_bone_map()

	_build_bone_mapping()
	_build_joint_mapping()

	# Cache rest poses BEFORE any writeback corrupts them.
	# Motors will always drive toward these stable targets.
	_cache_rest_poses()

	# Teleport parts to bone positions before motors kick in
	_snap_parts_to_bones()

	# Cache NPC name for diagnostics
	var npc_owner: Node = ragdoll.get_parent()
	if npc_owner != null and npc_owner.has_method(&"get"):
		_npc_name = str(npc_owner.get(&"npc_name"))
	else:
		_npc_name = ragdoll.get_parent().name if ragdoll.get_parent() != null else "?"

	# Diagnostic: show part positions after initial snap
	_log_part_bounds("after_snap")

	if hide_placeholder_meshes:
		_hide_debug_meshes()

	set_physics_process(true)
	set_process(true)
	print("[SkeletonBinding] Motor-driven ragdoll bound — %d bones, %d motor joints, gain=%.1f" % [
		_bone_to_part.size(), _bone_to_joint.size(), motor_gain])


func _physics_process(delta: float) -> void:
	if skeleton == null or ragdoll == null:
		return

	# ── Spawn ramp: freeze → unfreeze → ramp motors ─────────────────────
	_spawn_frames += 1
	if _parts_frozen:
		# Keep snapping to bones while frozen so parts stay aligned
		_snap_parts_to_bones()
		if _spawn_frames >= spawn_freeze_frames:
			_log_part_bounds("pre_unfreeze")
			_unfreeze_all_parts()
			_parts_frozen = false
			_log_part_bounds("post_unfreeze")
		return

	# Ramp motor scale from 0 → 1 over spawn_ramp_time
	if _spawn_elapsed < spawn_ramp_time:
		_spawn_elapsed += delta
		_motor_scale = clampf(_spawn_elapsed / spawn_ramp_time, 0.0, 1.0)
	else:
		_motor_scale = 1.0

	_update_motor_targets()


## Writeback runs in _process (render frame), reading interpolated transforms
## from Godot's physics interpolation for smooth motion.
func _process(_delta: float) -> void:
	if skeleton == null or ragdoll == null or _parts_frozen:
		return
	_write_skeleton_from_physics()


## ── Motor Targets ───────────────────────────────────────────────────────────

## Set each joint's angular motor target velocity so parts converge to rest pose.
## Uses RELATIVE rotation error (child vs parent) — each motor only corrects its
## own joint, preventing ancestor-error fighting that causes violent thrashing.
## PD controller: P = error * gain, D = -relative_angular_vel * damping.
func _update_motor_targets() -> void:
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
		# Ensure shortest arc
		if diff.w < 0.0:
			diff = -diff

		var axis: Vector3 = Vector3(diff.x, diff.y, diff.z)
		var sin_half: float = axis.length()

		# P-term: angular velocity proportional to rotation error
		var target_vel: Vector3 = Vector3.ZERO
		if sin_half > 0.001:
			axis = axis / sin_half
			var angle: float = 2.0 * atan2(sin_half, diff.w)
			if angle > PI:
				angle -= TAU
			target_vel = axis * angle * motor_gain

		# D-term: damp RELATIVE angular velocity (child vs parent)
		var relative_ang_vel: Vector3 = part.angular_velocity - parent_part.angular_velocity
		target_vel -= relative_ang_vel * motor_damping

		# Scale by spawn ramp
		target_vel *= _motor_scale

		# Convert world-space velocity to joint-local axes.
		var joint_basis_inv: Basis = joint.global_basis.inverse()
		var local_vel: Vector3 = joint_basis_inv * target_vel

		# Reduce motor force limit when grabbed (instead of reducing velocity)
		var force_limit: float = HumanoidRagdollBuilder.MOTOR_FORCE_LIMIT
		if part.grabbed_by != null:
			force_limit *= grabbed_motor_ratio

		# Set motor target velocity and force limit per axis
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, local_vel.x)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, local_vel.y)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, local_vel.z)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)


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


## ── Bone Mapping ────────────────────────────────────────────────────────────

## Build the bone_idx → BodyPart lookup from BONE_NAME_MAP.
func _build_bone_mapping() -> void:
	_bone_to_part.clear()
	var bone_count: int = skeleton.get_bone_count()
	var unmatched_bones: PackedStringArray = []

	for bone_idx: int in range(bone_count):
		var bone_name: String = skeleton.get_bone_name(bone_idx)

		if HumanoidRagdollBuilder.BONE_NAME_MAP.has(bone_name):
			var part_name: String = HumanoidRagdollBuilder.BONE_NAME_MAP[bone_name] as String
			if ragdoll.parts.has(part_name):
				_bone_to_part[bone_idx] = ragdoll.parts[part_name]
			else:
				push_warning("[SkeletonBinding] Bone '%s' maps to part '%s' but part not found" % [bone_name, part_name])
		elif HumanoidRagdollBuilder.BONE_NAME_MAP.has(bone_name.to_lower()):
			var part_name: String = HumanoidRagdollBuilder.BONE_NAME_MAP[bone_name.to_lower()] as String
			if ragdoll.parts.has(part_name):
				_bone_to_part[bone_idx] = ragdoll.parts[part_name]
		else:
			unmatched_bones.append(bone_name)

	# Build reverse lookup: BodyPart → bone_idx
	_part_to_bone.clear()
	for bone_idx_key: int in _bone_to_part:
		_part_to_bone[_bone_to_part[bone_idx_key]] = bone_idx_key

	if unmatched_bones.size() > 0:
		print("[SkeletonBinding] %d unmatched bones: %s" % [
			unmatched_bones.size(), ", ".join(unmatched_bones)])


## Build the bone_idx → Generic6DOFJoint3D lookup.
## Uses the builder's child_to_joint map (child part_name → joint).
func _build_joint_mapping() -> void:
	_bone_to_joint.clear()
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		if ragdoll.child_to_joint.has(part.part_name):
			_bone_to_joint[bone_idx] = ragdoll.child_to_joint[part.part_name]
	# Pelvis (root) has no parent joint — that's expected
	print("[SkeletonBinding] Joint mapping: %d joints for %d bones" % [
		_bone_to_joint.size(), _bone_to_part.size()])


## ── Helpers ─────────────────────────────────────────────────────────────────

## Teleport all mapped ragdoll parts to their skeleton bone positions.
## Called once at bind time so springs don't have to close a big gap.
func _snap_parts_to_bones() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
		part.global_transform = bone_global
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
		# Keep dynamic — springs hold the pose, not kinematic freeze
		# (unfreeze happens later via spawn ramp)


## Cache the skeleton rest pose at bind time, then adjust from T-pose to
## a natural arms-at-sides idle.  These targets are never overwritten.
func _cache_rest_poses() -> void:
	_rest_poses.clear()
	for bone_idx: int in _bone_to_part:
		_rest_poses[bone_idx] = skeleton.get_bone_global_pose(bone_idx)
	_adjust_rest_to_idle()
	_cache_rest_relative_rotations()


## Pre-compute the rest-pose relative quaternion for each motor joint.
## This is the rotation the joint should maintain: parent_rest.inverse() * child_rest.
func _cache_rest_relative_rotations() -> void:
	_rest_relative.clear()
	for bone_idx: int in _bone_to_joint:
		var joint: Generic6DOFJoint3D = _bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var parent_part: BodyPart = joint.get_node(joint.node_a) as BodyPart
		if _part_to_bone.has(parent_part):
			var parent_bone_idx: int = _part_to_bone[parent_part] as int
			var parent_rest_quat: Quaternion = _rest_poses[parent_bone_idx].basis.get_rotation_quaternion()
			var child_rest_quat: Quaternion = _rest_poses[bone_idx].basis.get_rotation_quaternion()
			_rest_relative[bone_idx] = parent_rest_quat.inverse() * child_rest_quat
		else:
			# Parent has no mapped bone (shouldn't happen in practice)
			_rest_relative[bone_idx] = Quaternion.IDENTITY
			push_warning("[SkeletonBinding] No parent bone for joint child bone %d" % bone_idx)


## Rotate the arm chains from T-pose (arms horizontal) to a natural idle
## (arms hanging at sides).  Operates on the cached rest poses so the actual
## skeleton data is never touched.
func _adjust_rest_to_idle() -> void:
	# Bone names that form each arm chain — upper arm is the root of rotation.
	var left_arm_chain: PackedStringArray = [
		"left_upper_arm", "left_forearm", "left_hand",
		"left_thumb_01", "left_thumb_02", "left_thumb_03",
		"left_index_01", "left_index_02", "left_index_03",
		"left_middle_01", "left_middle_02", "left_middle_03",
		"left_ring_01", "left_ring_02", "left_ring_03",
		"left_pinky_01", "left_pinky_02", "left_pinky_03",
	]
	var right_arm_chain: PackedStringArray = [
		"right_upper_arm", "right_forearm", "right_hand",
		"right_thumb_01", "right_thumb_02", "right_thumb_03",
		"right_index_01", "right_index_02", "right_index_03",
		"right_middle_01", "right_middle_02", "right_middle_03",
		"right_ring_01", "right_ring_02", "right_ring_03",
		"right_pinky_01", "right_pinky_02", "right_pinky_03",
	]

	# Build part_name → bone_idx reverse lookup for this skeleton
	var name_to_bone: Dictionary = {}
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		name_to_bone[part.part_name] = bone_idx

	# Find the upper arm bone pose to determine the pivot point for each side
	_rotate_arm_chain(left_arm_chain, name_to_bone, -1.0)
	_rotate_arm_chain(right_arm_chain, name_to_bone, 1.0)


## Rotate an arm chain's rest poses downward around the shoulder pivot.
## `side_sign` is -1 for left, +1 for right (determines rotation direction).
func _rotate_arm_chain(chain: PackedStringArray, name_to_bone: Dictionary,
		side_sign: float) -> void:
	if not name_to_bone.has(chain[0]):
		return
	var shoulder_bone_idx: int = name_to_bone[chain[0]] as int
	var shoulder_pose: Transform3D = _rest_poses[shoulder_bone_idx]
	var pivot: Vector3 = shoulder_pose.origin

	# Rotate 75° around forward axis (Z) — arms go from horizontal to ~15° from vertical.
	# Left arm rotates +Z, right arm rotates -Z (toward the body).
	var angle: float = deg_to_rad(75.0) * side_sign
	var rot: Basis = Basis(Vector3.FORWARD, angle)

	for part_name: String in chain:
		if not name_to_bone.has(part_name):
			continue
		var bone_idx: int = name_to_bone[part_name] as int
		var pose: Transform3D = _rest_poses[bone_idx]
		# Rotate position around shoulder pivot
		var offset: Vector3 = pose.origin - pivot
		var new_origin: Vector3 = pivot + rot * offset
		# Rotate the bone's own orientation too
		var new_basis: Basis = rot * pose.basis
		_rest_poses[bone_idx] = Transform3D(new_basis, new_origin)


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
