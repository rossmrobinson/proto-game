class_name SkeletonStandAssist
extends RefCounted

static func apply_stand_assist(binding: SkeletonBinding, motor_scale: float) -> void:
	if not binding.stand_assist_enabled:
		return
	if motor_scale < binding.stand_up_min_scale:
		return
	if binding._pelvis_bone_idx < 0 or not binding._bone_to_part.has(binding._pelvis_bone_idx):
		return
	var min_foot_y: float = get_current_min_foot_y(binding)
	if min_foot_y == INF or binding._rest_pelvis_height <= 0.0:
		return
	var pelvis: BodyPart = binding._bone_to_part[binding._pelvis_bone_idx] as BodyPart
	var target_y: float = min_foot_y + binding._rest_pelvis_height
	var err_y: float = target_y - pelvis.global_position.y
	if absf(err_y) < 0.001:
		return
	var up_force: float = (err_y * binding.stand_up_force - pelvis.linear_velocity.y * binding.stand_up_damping) * pelvis.mass
	var max_force: float = binding.stand_up_max_force * pelvis.mass
	up_force = clampf(up_force, -max_force, max_force)
	binding._last_stand_force = Vector3(0.0, up_force, 0.0)
	pelvis.apply_central_force(Vector3(0.0, up_force, 0.0))

	var up_axis: Vector3 = pelvis.global_basis.y
	var axis: Vector3 = up_axis.cross(Vector3.UP)
	var axis_len: float = axis.length()
	if axis_len < 0.0001:
		return
	axis = axis / axis_len
	var angle: float = clampf(up_axis.angle_to(Vector3.UP), 0.0, PI)
	var torque: Vector3 = axis * angle * binding.stand_up_torque * pelvis.mass
	var ang_vel_along: float = pelvis.angular_velocity.dot(axis)
	torque -= axis * ang_vel_along * binding.stand_up_torque_damping * pelvis.mass
	var torque_limit: float = binding.max_torque * pelvis.mass
	if torque.length() > torque_limit:
		torque = torque.normalized() * torque_limit
	pelvis.apply_torque(torque)


static func cache_rest_pelvis_height(binding: SkeletonBinding) -> void:
	binding._rest_pelvis_height = 0.0
	if binding._pelvis_bone_idx < 0 or not binding._bone_to_part.has(binding._pelvis_bone_idx):
		return
	var min_foot_y: float = get_current_min_foot_y(binding)
	if min_foot_y == INF:
		return
	var pelvis: BodyPart = binding._bone_to_part[binding._pelvis_bone_idx] as BodyPart
	binding._rest_pelvis_height = pelvis.global_position.y - min_foot_y


static func get_current_min_foot_y(binding: SkeletonBinding) -> float:
	var min_y: float = INF
	var foot_names: PackedStringArray = [
		"left_foot", "right_foot", "left_toes", "right_toes",
	]
	for foot_name: String in foot_names:
		if not binding.ragdoll.parts.has(foot_name):
			continue
		var part: BodyPart = binding.ragdoll.parts[foot_name] as BodyPart
		if part == null:
			continue
		var half_height: float = part.get_collision_half_height()
		min_y = minf(min_y, part.global_position.y - half_height)
	return min_y
