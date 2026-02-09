class_name SkeletonBinding
extends Node
## Active-ragdoll skeleton binding — per-part position + orientation springs.
##
## Two systems keep the ragdoll upright:
## 1. Per-part position springs — each part is pulled toward its skeleton bone
##    world position. This implicitly fights gravity (spring pulls up when
##    the part sags below its target).
## 2. Per-joint orientation torques — PD controller drives each joint toward
##    its rest-pose relative rotation; pelvis uses absolute world-space target.
##
## The skeleton writeback runs in _process (not _physics_process) so it reads
## the interpolated visual position from Godot's physics interpolation,
## giving smooth motion at any render framerate.

## ── Tuning ──────────────────────────────────────────────────────────────────

## Position spring stiffness (N/m). Pulls each part toward its bone position.
## This is what keeps the ragdoll upright — implicitly fights gravity.
@export var spring_stiffness: float = 400.0
## Position spring damping (N·s/m). Prevents oscillation / bouncing.
@export var spring_damping: float = 40.0
## Angular PD stiffness (N·m/rad). Corrective torque toward rest-pose rotation.
@export var angular_stiffness: float = 80.0
## Angular PD damping (N·m·s/rad). Resists relative angular velocity.
@export var angular_damping: float = 12.0
## Maximum torque magnitude (N·m) per part. Prevents instability on large errors.
@export var max_torque: float = 500.0
## Torque multiplier for grabbed parts (0-1).
## Lower = easier to pull away from pose.
@export_range(0.0, 1.0) var grabbed_motor_ratio: float = 0.05
## How long (seconds) to ramp spring strength from 0 -> full after spawn.
@export var spawn_ramp_time: float = 0.4
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
var _pelvis_bone_idx: int = -1
var _bone_targets: Dictionary = {}
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

	# Ensure reverse bone map is populated
	HumanoidRagdollBuilder._init_reverse_bone_map()

	_build_bone_mapping()
	_build_joint_mapping()

	# Cache rest poses BEFORE any writeback corrupts them.
	# Motors will always drive toward these stable targets.
	_cache_rest_poses()

	add_to_group(&"ragdoll_binding")
	_diag = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	if _diag != null:
		_diag.register_binding(self)

	# Teleport parts to bone positions before springs kick in
	_snap_parts_to_bones()
	_report_diag_event("after_snap")

	# Cache bone world-space target positions for per-part position springs
	_bone_targets.clear()
	for bone_idx: int in _bone_to_part:
		var bone_global: Transform3D = skeleton.global_transform * _rest_poses[bone_idx]
		_bone_targets[bone_idx] = bone_global.origin

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
	print("[SkeletonBinding] Active ragdoll bound — %d bones, %d joints, spring=%.0f ang=%.0f" % [
		_bone_to_part.size(), _bone_to_joint.size(), spring_stiffness, angular_stiffness])


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
			_report_diag_event("pre_unfreeze")
			_unfreeze_all_parts()
			_parts_frozen = false
			_log_part_bounds("post_unfreeze")
			_report_diag_event("post_unfreeze")
		return

	# Ramp motor scale from 0 → 1 over spawn_ramp_time
	if _spawn_elapsed < spawn_ramp_time:
		_spawn_elapsed += delta
		_motor_scale = clampf(_spawn_elapsed / spawn_ramp_time, 0.0, 1.0)
	else:
		_motor_scale = 1.0

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
	# ── Per-part position springs ─────────────────────────────────────
	# Each part is pulled toward its bone-target world position.
	# This implicitly fights gravity (spring pulls up when part sags).
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var target_pos: Vector3 = _bone_targets[bone_idx] as Vector3
		var pos_error: Vector3 = target_pos - part.global_position
		var pos_force: Vector3 = pos_error * spring_stiffness - part.linear_velocity * spring_damping
		pos_force *= _motor_scale
		if part.grabbed_by != null:
			pos_force *= grabbed_motor_ratio
		part.apply_central_force(pos_force)

	# ── Joint PD torques (relative rotation) ────────────────────────────
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

		# P-term: corrective torque proportional to angle error
		var torque: Vector3 = Vector3.ZERO
		if sin_half > 0.001:
			axis = axis / sin_half
			var angle: float = 2.0 * atan2(sin_half, diff.w)
			if angle > PI:
				angle -= TAU
			torque = axis * angle * angular_stiffness

		# D-term: damp RELATIVE angular velocity (child vs parent)
		var rel_ang_vel: Vector3 = part.angular_velocity - parent_part.angular_velocity
		torque -= rel_ang_vel * angular_damping

		# Scale by spawn ramp
		torque *= _motor_scale

		# Clamp torque to prevent instability
		var mag: float = torque.length()
		if mag > max_torque:
			torque = torque * (max_torque / mag)

		# Reduce torque when grabbed
		if part.grabbed_by != null:
			torque *= grabbed_motor_ratio

		part.apply_torque(torque)

	# ── Pelvis stabilization (world-space absolute target) ──────────────
	if _pelvis_bone_idx >= 0 and _bone_to_part.has(_pelvis_bone_idx):
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
			p_torque = p_axis * p_angle * angular_stiffness * 1.5

		p_torque -= pelvis.angular_velocity * angular_damping * 1.5
		p_torque *= _motor_scale

		var p_mag: float = p_torque.length()
		if p_mag > max_torque * 1.5:
			p_torque = p_torque * (max_torque * 1.5 / p_mag)

		if pelvis.grabbed_by != null:
			p_torque *= grabbed_motor_ratio

		pelvis.apply_torque(p_torque)


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
	_pelvis_bone_idx = -1
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		if ragdoll.child_to_joint.has(part.part_name):
			_bone_to_joint[bone_idx] = ragdoll.child_to_joint[part.part_name]
		elif part.part_name == "pelvis":
			_pelvis_bone_idx = bone_idx
	# Pelvis (root) has no parent joint — stabilized via world-space torque
	print("[SkeletonBinding] Joint mapping: %d joints for %d bones (pelvis=%d)" % [
		_bone_to_joint.size(), _bone_to_part.size(), _pelvis_bone_idx])


## ── Helpers ─────────────────────────────────────────────────────────────────

## Teleport all mapped ragdoll parts to their skeleton bone positions.
## Called once at bind time so springs don't have to close a big gap.
func _snap_parts_to_bones() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		# Use _rest_poses (idle-adjusted) when available, otherwise raw skeleton pose
		var bone_global: Transform3D
		if _rest_poses.has(bone_idx):
			bone_global = skeleton.global_transform * _rest_poses[bone_idx]
		else:
			bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
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


func get_npc_name() -> String:
	return _npc_name


func get_debug_part_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if skeleton == null:
		return entries
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var target: Transform3D = skeleton.global_transform * _rest_poses[bone_idx]
		entries.append({
			"part": part,
			"target_pos": target.origin,
		})
	return entries


func _report_diag_event(tag: String) -> void:
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
