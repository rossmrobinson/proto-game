class_name SkeletonBinding
extends Node
## Active-ragdoll skeleton binding.
##
## Physics bodies are ALWAYS dynamic (never frozen). Spring forces push each
## part toward its skeleton bone pose. Grabbed parts have weaker springs so the
## player can pull them. When every part is free, the NPC holds its idle pose
## with a natural, slightly alive feel.
##
## The skeleton is written back from physics every frame so the skinned mesh
## follows the ragdoll, not the other way around.
##
## Uses HumanoidRagdollBuilder.BONE_NAME_MAP for name resolution.

## ── Tuning ──────────────────────────────────────────────────────────────────

## Positional spring stiffness (N/m). Higher = stiffer pose hold.
@export var spring_stiffness: float = 400.0
## Positional damping. Prevents oscillation.
@export var spring_damping: float = 40.0
## Angular spring stiffness (N·m/rad). Higher = stiffer rotation hold.
@export var angular_stiffness: float = 80.0
## Angular damping.
@export var angular_damping: float = 12.0
## Multiplier applied to spring stiffness while a part is grabbed (0-1).
## Lower = easier to pull away from pose.
@export_range(0.0, 1.0) var grabbed_spring_ratio: float = 0.05

## ── References ──────────────────────────────────────────────────────────────

## The Skeleton3D from the imported model scene.
var skeleton: Skeleton3D = null

## Reference to the ragdoll builder that owns the physics parts.
var ragdoll: HumanoidRagdollBuilder = null

## Cached mapping: bone_idx (int) → BodyPart node.
var _bone_to_part: Dictionary = {}

## If true, placeholder debug meshes on ragdoll parts are hidden
## (because the real skinned mesh is visible instead).
var hide_placeholder_meshes: bool = true


func _ready() -> void:
	set_physics_process(false)


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

	# Teleport parts to bone positions before springs kick in
	_snap_parts_to_bones()

	if hide_placeholder_meshes:
		_hide_debug_meshes()

	set_physics_process(true)
	print("[SkeletonBinding] Active ragdoll bound — %d bones, springs=%.0f/%.0f" % [
		_bone_to_part.size(), spring_stiffness, angular_stiffness])


func _physics_process(delta: float) -> void:
	if skeleton == null or ragdoll == null:
		return
	_apply_spring_forces(delta)
	_write_skeleton_from_physics()


## ── Spring Forces ───────────────────────────────────────────────────────────

## Apply PD-controller spring forces pushing each part toward its bone pose.
func _apply_spring_forces(_delta: float) -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)

		# Weaken springs on grabbed parts so they yield to the player
		var stiff_mult: float = grabbed_spring_ratio if part.grabbed_by != null else 1.0

		# ── Position spring ──────────────────────────────────────────────
		var displacement: Vector3 = bone_global.origin - part.global_position
		var force: Vector3 = displacement * spring_stiffness * stiff_mult
		force -= part.linear_velocity * spring_damping * stiff_mult
		part.apply_central_force(force)

		# ── Rotation spring ──────────────────────────────────────────────
		var current_quat: Quaternion = part.global_basis.get_rotation_quaternion()
		var target_quat: Quaternion = bone_global.basis.get_rotation_quaternion()
		# Shortest-arc difference
		var diff: Quaternion = target_quat * current_quat.inverse()
		# Ensure we take the short path
		if diff.w < 0.0:
			diff = -diff
		var axis: Vector3 = Vector3(diff.x, diff.y, diff.z)
		var sin_half: float = axis.length()
		if sin_half > 0.001:
			axis = axis / sin_half
			var angle: float = 2.0 * atan2(sin_half, diff.w)
			if angle > PI:
				angle -= TAU
			var torque: Vector3 = axis * angle * angular_stiffness * stiff_mult
			torque -= part.angular_velocity * angular_damping * stiff_mult
			part.apply_torque(torque)


## ── Skeleton Writeback ──────────────────────────────────────────────────────

## Write physics body transforms back into skeleton bone poses so the skinned
## mesh follows the ragdoll every frame.
func _write_skeleton_from_physics() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var skel_inv: Transform3D = skeleton.global_transform.affine_inverse()
		var part_in_skel: Transform3D = skel_inv * part.global_transform

		var parent_idx: int = skeleton.get_bone_parent(bone_idx)
		if parent_idx >= 0:
			var parent_global: Transform3D = skeleton.get_bone_global_pose(parent_idx)
			var local_pose: Transform3D = parent_global.affine_inverse() * part_in_skel
			skeleton.set_bone_pose(bone_idx, local_pose)
		else:
			skeleton.set_bone_pose(bone_idx, part_in_skel)


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

	if unmatched_bones.size() > 0:
		print("[SkeletonBinding] %d unmatched bones: %s" % [
			unmatched_bones.size(), ", ".join(unmatched_bones)])


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
		part.freeze = false


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
