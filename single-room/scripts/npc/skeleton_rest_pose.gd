class_name SkeletonRestPose
extends RefCounted

## Cache the skeleton rest pose at bind time, then adjust from T-pose to
## a natural arms-at-sides idle.  These targets are never overwritten.
static func cache_rest_poses(binding: SkeletonBinding) -> void:
	binding._rest_poses.clear()
	for bone_idx: int in binding._bone_to_part:
		binding._rest_poses[bone_idx] = binding.skeleton.get_bone_global_pose(bone_idx)
	adjust_rest_to_idle(binding)
	apply_rest_forward_fix(binding)
	binding._log_arm_pose_metrics()


## Rotate the arm chains from T-pose (arms horizontal) to a natural idle
## (arms hanging at sides).  Operates on the cached rest poses so the actual
## skeleton data is never touched.
static func adjust_rest_to_idle(binding: SkeletonBinding) -> void:
	# Bone names that form each arm chain — upper arm is the root of rotation.
	var left_arm_chain: PackedStringArray = [
		"left_upper_arm", "left_forearm", "left_hand",
		"left_thumb_00", "left_thumb_01", "left_thumb_02", "left_thumb_03",
		"left_index_00", "left_index_01", "left_index_02", "left_index_03",
		"left_middle_00", "left_middle_01", "left_middle_02", "left_middle_03",
		"left_ring_00", "left_ring_01", "left_ring_02", "left_ring_03",
		"left_pinky_00", "left_pinky_01", "left_pinky_02", "left_pinky_03",
	]
	var right_arm_chain: PackedStringArray = [
		"right_upper_arm", "right_forearm", "right_hand",
		"right_thumb_00", "right_thumb_01", "right_thumb_02", "right_thumb_03",
		"right_index_00", "right_index_01", "right_index_02", "right_index_03",
		"right_middle_00", "right_middle_01", "right_middle_02", "right_middle_03",
		"right_ring_00", "right_ring_01", "right_ring_02", "right_ring_03",
		"right_pinky_00", "right_pinky_01", "right_pinky_02", "right_pinky_03",
	]

	# Build part_name → bone_idx reverse lookup for this skeleton
	var name_to_bone: Dictionary = {}
	for bone_idx: int in binding._bone_to_part:
		var part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		name_to_bone[part.part_name] = bone_idx

	# Find the upper arm bone pose to determine the pivot point for each side
	rotate_arm_chain(binding, left_arm_chain, name_to_bone, -1.0)
	rotate_arm_chain(binding, right_arm_chain, name_to_bone, 1.0)


static func apply_rest_forward_fix(binding: SkeletonBinding) -> void:
	if not binding.rest_forward_fix_enabled:
		return
	if binding._pelvis_bone_idx < 0 or not binding._rest_poses.has(binding._pelvis_bone_idx):
		return
	var pelvis_pose: Transform3D = binding._rest_poses[binding._pelvis_bone_idx]
	var pelvis_origin: Vector3 = pelvis_pose.origin
	var up_dir: Vector3 = Vector3.UP
	var chest_idx: int = get_bone_idx_for_part(binding, "chest")
	if chest_idx >= 0 and binding._rest_poses.has(chest_idx):
		up_dir = (binding._rest_poses[chest_idx].origin - pelvis_origin).normalized()
		if up_dir.length() < 0.0001:
			up_dir = Vector3.UP
	var left_leg_idx: int = get_bone_idx_for_part(binding, "left_upper_leg")
	var right_leg_idx: int = get_bone_idx_for_part(binding, "right_upper_leg")
	var right_dir: Vector3 = Vector3.RIGHT
	if left_leg_idx >= 0 and right_leg_idx >= 0 and binding._rest_poses.has(left_leg_idx) and binding._rest_poses.has(right_leg_idx):
		right_dir = (binding._rest_poses[right_leg_idx].origin - binding._rest_poses[left_leg_idx].origin).normalized()
		if right_dir.length() < 0.0001:
			right_dir = Vector3.RIGHT
	var forward_dir: Vector3 = up_dir.cross(right_dir).normalized()
	if forward_dir.length() < 0.0001:
		forward_dir = Vector3.FORWARD
	var target_forward: Vector3 = Vector3.FORWARD
	var axis: Vector3 = forward_dir.cross(target_forward)
	var angle: float = forward_dir.angle_to(target_forward)
	if axis.length() < 0.0001 or angle < 0.0001:
		return
	axis = axis.normalized()
	var rot: Basis = Basis(axis, angle)
	for bone_idx: int in binding._rest_poses:
		var pose: Transform3D = binding._rest_poses[bone_idx]
		var offset: Vector3 = pose.origin - pelvis_origin
		var new_origin: Vector3 = pelvis_origin + rot * offset
		var new_basis: Basis = rot * pose.basis
		binding._rest_poses[bone_idx] = Transform3D(new_basis, new_origin)


## Rotate an arm chain's rest poses downward around the shoulder pivot.
## `side_sign` is -1 for left, +1 for right (determines rotation direction).
static func rotate_arm_chain(binding: SkeletonBinding, chain: PackedStringArray,
		name_to_bone: Dictionary, _side_sign: float) -> void:
	if not name_to_bone.has(chain[0]):
		return
	var shoulder_bone_idx: int = name_to_bone[chain[0]] as int
	var shoulder_pose: Transform3D = binding._rest_poses[shoulder_bone_idx]
	var pivot: Vector3 = shoulder_pose.origin
	var hand_idx: int = get_bone_idx_for_part(binding, chain[min(2, chain.size() - 1)])
	if hand_idx < 0:
		return
	var hand_pose: Transform3D = binding._rest_poses[hand_idx]
	var arm_vec: Vector3 = (hand_pose.origin - shoulder_pose.origin).normalized()
	if arm_vec.length() < 0.0001:
		return
	var target: Vector3 = Vector3.DOWN
	var axis: Vector3 = arm_vec.cross(target)
	var angle: float = arm_vec.angle_to(target)
	if axis.length() < 0.0001 or angle < 0.0001:
		return
	axis = axis.normalized()
	var rot: Basis = Basis(axis, angle)

	for part_name: String in chain:
		if not name_to_bone.has(part_name):
			continue
		var bone_idx: int = name_to_bone[part_name] as int
		var pose: Transform3D = binding._rest_poses[bone_idx]
		# Rotate position around shoulder pivot
		var offset: Vector3 = pose.origin - pivot
		var new_origin: Vector3 = pivot + rot * offset
		# Rotate the bone's own orientation too
		var new_basis: Basis = rot * pose.basis
		binding._rest_poses[bone_idx] = Transform3D(new_basis, new_origin)


static func get_bone_idx_for_part(binding: SkeletonBinding, part_name: String) -> int:
	for bone_idx: int in binding._bone_to_part:
		var part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		if part != null and part.part_name == part_name:
			return bone_idx
	return -1


## Pre-compute the rest-pose relative quaternion for each motor joint.
## This is the rotation the joint should maintain: parent_rest.inverse() * child_rest.
static func cache_rest_relative_rotations(binding: SkeletonBinding) -> void:
	binding._rest_relative.clear()
	for bone_idx: int in binding._bone_to_joint:
		var joint: Generic6DOFJoint3D = binding._bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var parent_part: BodyPart = joint.get_node(joint.node_a) as BodyPart
		if binding._part_to_bone.has(parent_part):
			var parent_bone_idx: int = binding._part_to_bone[parent_part] as int
			var parent_rest_quat: Quaternion = binding._rest_poses[parent_bone_idx].basis.get_rotation_quaternion()
			var child_rest_quat: Quaternion = binding._rest_poses[bone_idx].basis.get_rotation_quaternion()
			binding._rest_relative[bone_idx] = parent_rest_quat.inverse() * child_rest_quat
		else:
			# Parent has no mapped bone (shouldn't happen in practice)
			binding._rest_relative[bone_idx] = Quaternion.IDENTITY
			push_warning("[SkeletonBinding] No parent bone for joint child bone %d" % bone_idx)


static func cache_rest_relative_from_parts(binding: SkeletonBinding) -> void:
	binding._rest_relative.clear()
	for bone_idx: int in binding._bone_to_joint:
		var joint: Generic6DOFJoint3D = binding._bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var child_part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		if joint == null or child_part == null:
			continue
		var parent_part: RigidBody3D = joint.get_node(joint.node_a) as RigidBody3D
		if parent_part == null:
			continue
		var parent_quat: Quaternion = parent_part.global_basis.get_rotation_quaternion()
		var child_quat: Quaternion = child_part.global_basis.get_rotation_quaternion()
		binding._rest_relative[bone_idx] = parent_quat.inverse() * child_quat


static func refresh_rest_relative(binding: SkeletonBinding) -> void:
	if binding._use_physics_rest_relative:
		cache_rest_relative_from_parts(binding)
	else:
		cache_rest_relative_rotations(binding)
