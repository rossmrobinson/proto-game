class_name SkeletonDebugQueries
## Read-only debug/snapshot queries for SkeletonBinding.
##
## Extracted for navigability — these functions only READ ragdoll state
## (positions, rotations, joint limits) and serialize it for diagnostics.
## They never mutate physics or binding state.
##
## Usage:
##   var entries: Array[Dictionary] = SkeletonDebugQueries.get_debug_part_entries(binding)
##   var snapshot: Dictionary = SkeletonDebugQueries.get_snapshot_data(binding, 20, 20)


# ──────────────────────────────────────────────────────────────────────────────
#  PART / JOINT QUERY
# ──────────────────────────────────────────────────────────────────────────────

static func get_debug_part_entries(binding: SkeletonBinding) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if binding.skeleton == null:
		return entries
	for bone_idx: int in binding._bone_to_part:
		var part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		var target_pos: Vector3 = binding._get_target_position(bone_idx)
		entries.append({
			"part": part,
			"target_pos": target_pos,
		})
	return entries


static func get_debug_joint_entries(binding: SkeletonBinding) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for bone_idx: int in binding._bone_to_joint:
		var joint: Generic6DOFJoint3D = binding._bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		if joint == null or part == null:
			continue
		var parent_body: RigidBody3D = joint.get_node(joint.node_a) as RigidBody3D
		if parent_body == null:
			continue
		var parent_idx: int = -1
		if parent_body is BodyPart and binding._part_to_bone.has(parent_body):
			parent_idx = binding._part_to_bone[parent_body] as int
		var parent_quat: Quaternion = parent_body.global_basis.get_rotation_quaternion()
		var child_quat: Quaternion = part.global_basis.get_rotation_quaternion()
		var current_rel: Quaternion = parent_quat.inverse() * child_quat
		var target_rel: Quaternion = binding._rest_relative.get(bone_idx, Quaternion.IDENTITY) as Quaternion
		var diff: Quaternion = target_rel.inverse() * current_rel
		if diff.w < 0.0:
			diff = -diff
		var axis: Vector3 = Vector3(diff.x, diff.y, diff.z)
		var sin_half: float = axis.length()
		var angle: float = 0.0
		if sin_half > 0.001:
			angle = 2.0 * atan2(sin_half, diff.w)
		var error_deg: float = absf(rad_to_deg(angle))
		var axis_align: float = 1.0
		if parent_idx >= 0:
			var parent_rest: Transform3D = binding._get_rest_pose_world(parent_idx)
			var child_rest: Transform3D = binding._get_rest_pose_world(bone_idx)
			var bone_dir: Vector3 = (child_rest.origin - parent_rest.origin).normalized()
			if bone_dir.length() > 0.0001:
				axis_align = absf(bone_dir.dot(joint.global_basis.y.normalized()))
		var parent_name: String = parent_body.name
		if parent_body is BodyPart:
			parent_name = (parent_body as BodyPart).part_name
		var joint_name: String = "%s_to_%s" % [parent_name, part.part_name]
		entries.append({
			"part": part,
			"joint": joint_name,
			"error_deg": error_deg,
			"axis_align": axis_align,
		})
	return entries


# ──────────────────────────────────────────────────────────────────────────────
#  FULL SNAPSHOT
# ──────────────────────────────────────────────────────────────────────────────

static func get_snapshot_data(binding: SkeletonBinding,
		max_parts: int, max_joints: int) -> Dictionary:
	var data: Dictionary = {
		"npc": binding._npc_name,
		"rest_source": "physics" if binding._use_physics_rest_relative else "bone",
		"recover_scale": binding._recover_scale,
		"recover_passive": binding._recover_passive,
		"auto_recover": binding.auto_recover,
		"parts": [],
		"joints": [],
	}
	if binding._pelvis_bone_idx >= 0 and binding._bone_to_part.has(binding._pelvis_bone_idx):
		var pelvis: BodyPart = binding._bone_to_part[binding._pelvis_bone_idx] as BodyPart
		var pelvis_target: Vector3 = binding._get_target_position(binding._pelvis_bone_idx)
		data["pelvis"] = {
			"pos": _vec3_to_dict(pelvis.global_position),
			"basis": _basis_to_dict(pelvis.global_basis),
		}
		data["pelvis_target"] = _vec3_to_dict(pelvis_target)
		data["pelvis_offset"] = pelvis.global_position.distance_to(pelvis_target)

	var part_entries: Array = []
	var debug_parts: Array = get_debug_part_entries(binding)
	for entry: Dictionary in debug_parts:
		var part: BodyPart = entry["part"] as BodyPart
		var target_pos: Vector3 = entry["target_pos"] as Vector3
		var offset: float = part.global_position.distance_to(target_pos)
		var bone_idx: int = -1
		var bone_name: String = ""
		if binding._part_to_bone.has(part):
			bone_idx = binding._part_to_bone[part] as int
			if binding.skeleton != null and bone_idx >= 0:
				bone_name = binding.skeleton.get_bone_name(bone_idx)
		part_entries.append({
			"name": part.part_name,
			"bone_idx": bone_idx,
			"bone_name": bone_name,
			"pos": _vec3_to_dict(part.global_position),
			"target": _vec3_to_dict(target_pos),
			"offset": offset,
			"lin_vel": _vec3_to_dict(part.linear_velocity),
			"ang_vel": _vec3_to_dict(part.angular_velocity),
			"mass": part.mass,
			"freeze": part.freeze,
			"gravity_scale": part.gravity_scale,
		})
	part_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("offset", 0.0)) > float(b.get("offset", 0.0))
	)
	if max_parts > 0 and part_entries.size() > max_parts:
		part_entries = part_entries.slice(0, max_parts)
	data["parts"] = part_entries

	var joint_entries: Array = []
	for bone_idx: int in binding._bone_to_joint:
		var joint: Generic6DOFJoint3D = binding._bone_to_joint[bone_idx] as Generic6DOFJoint3D
		var child_part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		if joint == null or child_part == null:
			continue
		var parent_body: RigidBody3D = joint.get_node(joint.node_a) as RigidBody3D
		if parent_body == null:
			continue
		var parent_name: String = parent_body.name
		var parent_idx: int = -1
		if parent_body is BodyPart:
			parent_name = (parent_body as BodyPart).part_name
			if binding._part_to_bone.has(parent_body):
				parent_idx = binding._part_to_bone[parent_body] as int
		var parent_quat: Quaternion = parent_body.global_basis.get_rotation_quaternion()
		var child_quat: Quaternion = child_part.global_basis.get_rotation_quaternion()
		var current_rel: Quaternion = parent_quat.inverse() * child_quat
		var target_rel: Quaternion = binding._rest_relative.get(bone_idx, Quaternion.IDENTITY) as Quaternion
		var diff: Quaternion = target_rel.inverse() * current_rel
		if diff.w < 0.0:
			diff = -diff
		var axis: Vector3 = Vector3(diff.x, diff.y, diff.z)
		var sin_half: float = axis.length()
		var angle: float = 0.0
		if sin_half > 0.001:
			angle = 2.0 * atan2(sin_half, diff.w)
		var error_deg: float = absf(rad_to_deg(angle))

		var parent_rest: Transform3D = parent_body.global_transform
		if parent_idx >= 0:
			parent_rest = binding._get_rest_pose_world(parent_idx)
		var child_rest: Transform3D = binding._get_rest_pose_world(bone_idx)
		var bone_dir: Vector3 = Vector3.ZERO
		if parent_idx >= 0:
			bone_dir = (child_rest.origin - parent_rest.origin).normalized()
		var axis_align: float = 0.0
		if bone_dir.length() > 0.0001:
			var joint_y: Vector3 = joint.global_transform.basis.y.normalized()
			axis_align = absf(bone_dir.dot(joint_y))
		var limits: Dictionary = {
			"x": {
				"lower": rad_to_deg(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),
				"upper": rad_to_deg(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
			},
			"y": {
				"lower": rad_to_deg(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),
				"upper": rad_to_deg(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
			},
			"z": {
				"lower": rad_to_deg(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),
				"upper": rad_to_deg(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
			},
		}

		joint_entries.append({
			"joint": "%s_to_%s" % [parent_name, child_part.part_name],
			"parent": parent_name,
			"parent_idx": parent_idx,
			"child": child_part.part_name,
			"child_idx": bone_idx,
			"error_deg": error_deg,
			"current_rel": _quat_to_dict(current_rel),
			"target_rel": _quat_to_dict(target_rel),
			"joint_global": _transform_to_dict(joint.global_transform),
			"parent_rest": _transform_to_dict(parent_rest),
			"child_rest": _transform_to_dict(child_rest),
			"bone_dir": _vec3_to_dict(bone_dir),
			"axis_align": axis_align,
			"limits": limits,
		})
	joint_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("error_deg", 0.0)) > float(b.get("error_deg", 0.0))
	)
	if max_joints > 0 and joint_entries.size() > max_joints:
		joint_entries = joint_entries.slice(0, max_joints)
	data["joints"] = joint_entries
	return data


# ──────────────────────────────────────────────────────────────────────────────
#  SERIALIZATION HELPERS
# ──────────────────────────────────────────────────────────────────────────────

static func _vec3_to_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _quat_to_dict(value: Quaternion) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}


static func _basis_to_dict(value: Basis) -> Dictionary:
	return {
		"x": _vec3_to_dict(value.x),
		"y": _vec3_to_dict(value.y),
		"z": _vec3_to_dict(value.z),
	}


static func _transform_to_dict(value: Transform3D) -> Dictionary:
	return {
		"origin": _vec3_to_dict(value.origin),
		"basis": _basis_to_dict(value.basis),
	}


# ──────────────────────────────────────────────────────────────────────────────
#  ARM METRICS
# ──────────────────────────────────────────────────────────────────────────────

static func log_arm_pose_metrics(binding: SkeletonBinding) -> void:
	var left_angle: float = _get_arm_angle_deg(binding, "left_upper_arm", "left_hand")
	var right_angle: float = _get_arm_angle_deg(binding, "right_upper_arm", "right_hand")
	if left_angle >= 0.0:
		print("[SkeletonBinding] Rest arm angle L=%.1f deg" % left_angle)
	if right_angle >= 0.0:
		print("[SkeletonBinding] Rest arm angle R=%.1f deg" % right_angle)


static func _get_arm_angle_deg(binding: SkeletonBinding,
		upper_name: String, hand_name: String) -> float:
	var upper_idx: int = _get_bone_idx_for_part(binding, upper_name)
	var hand_idx: int = _get_bone_idx_for_part(binding, hand_name)
	if upper_idx < 0 or hand_idx < 0:
		return -1.0
	var upper_pose: Transform3D = binding._rest_poses[upper_idx]
	var hand_pose: Transform3D = binding._rest_poses[hand_idx]
	var vec: Vector3 = hand_pose.origin - upper_pose.origin
	if vec.length() < 0.0001:
		return -1.0
	vec = vec.normalized()
	var dot_val: float = clampf(vec.dot(Vector3.DOWN), -1.0, 1.0)
	return rad_to_deg(acos(dot_val))


static func _get_bone_idx_for_part(binding: SkeletonBinding,
		part_name: String) -> int:
	for bone_idx: int in binding._bone_to_part:
		var part: BodyPart = binding._bone_to_part[bone_idx] as BodyPart
		if part.part_name == part_name:
			return bone_idx
	return -1
