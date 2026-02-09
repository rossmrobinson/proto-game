class_name SkeletonBinding
extends Node
## Active-ragdoll skeleton binding.
##
## Spring forces push each part toward a cached REST POSE (captured at bind
## time). Grabbed parts have weaker springs so the player can pull them.
## Forces are clamped by mass to prevent light parts (fingers) from exploding.
##
## The skeleton is written back from physics every frame so the skinned mesh
## follows the ragdoll. Writeback does NOT affect spring targets — those use
## the cached rest poses for stability.
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

## Maximum linear acceleration (m/s²) a spring can apply to any part.
## Prevents light parts (fingers) from getting launched.
@export var max_spring_accel: float = 80.0
## Maximum angular acceleration (rad/s²) a spring can apply.
@export var max_angular_accel: float = 60.0
## How long (seconds) to ramp spring strength from 0 → full after spawn.
@export var spawn_ramp_time: float = 0.4
## How many physics frames to keep parts frozen after bind (lets Jolt settle).
@export var spawn_freeze_frames: int = 3

## ── References ──────────────────────────────────────────────────────────────

## The Skeleton3D from the imported model scene.
var skeleton: Skeleton3D = null

## Reference to the ragdoll builder that owns the physics parts.
var ragdoll: HumanoidRagdollBuilder = null

## Cached mapping: bone_idx (int) → BodyPart node.
var _bone_to_part: Dictionary = {}

## Cached rest-pose transforms: bone_idx → Transform3D (skeleton-local).
## Springs pull toward these stable poses, NOT the writeback-overwritten skeleton.
var _rest_poses: Dictionary = {}

## Spawn-ramp state.
var _spawn_elapsed: float = 0.0
var _spawn_frames: int = 0
var _parts_frozen: bool = true
var _spring_scale: float = 0.0
var _npc_name: String = ""

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

	# Cache rest poses BEFORE any writeback corrupts them.
	# Springs will always pull toward these stable targets.
	_cache_rest_poses()

	# Teleport parts to bone positions before springs kick in
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
	print("[SkeletonBinding] Active ragdoll bound — %d bones, springs=%.0f/%.0f" % [
		_bone_to_part.size(), spring_stiffness, angular_stiffness])


func _physics_process(delta: float) -> void:
	if skeleton == null or ragdoll == null:
		return

	# ── Spawn ramp: freeze → unfreeze → ramp springs ────────────────────
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

	# Ramp spring scale from 0 → 1 over spawn_ramp_time
	if _spawn_elapsed < spawn_ramp_time:
		_spawn_elapsed += delta
		_spring_scale = clampf(_spawn_elapsed / spawn_ramp_time, 0.0, 1.0)
	else:
		_spring_scale = 1.0

	_apply_spring_forces(delta)
	_write_skeleton_from_physics()


## ── Spring Forces ───────────────────────────────────────────────────────────

## Apply PD-controller spring forces pushing each part toward its rest pose.
## Uses cached rest poses (not live skeleton) so writeback doesn't corrupt targets.
## Forces are clamped by mass to prevent light parts (fingers) from exploding.
func _apply_spring_forces(_delta: float) -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		# Use cached rest pose — immune to writeback corruption
		var bone_global: Transform3D = skeleton.global_transform * _rest_poses[bone_idx]

		# Weaken springs on grabbed parts so they yield to the player
		var stiff_mult: float = grabbed_spring_ratio if part.grabbed_by != null else 1.0
		stiff_mult *= _spring_scale

		# ── Position spring ──────────────────────────────────────────────
		var displacement: Vector3 = bone_global.origin - part.global_position
		var force: Vector3 = displacement * spring_stiffness * stiff_mult
		force -= part.linear_velocity * spring_damping * stiff_mult
		# Clamp by mass to prevent extreme acceleration on light parts
		var max_force: float = max_spring_accel * part.mass
		if force.length_squared() > max_force * max_force:
			force = force.limit_length(max_force)
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
			# Clamp torque by mass to prevent spin explosions on light parts
			var max_torque: float = max_angular_accel * part.mass
			if torque.length_squared() > max_torque * max_torque:
				torque = torque.limit_length(max_torque)
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
		# (unfreeze happens later via spawn ramp)


## Cache the skeleton rest pose at bind time, then adjust from T-pose to
## a natural arms-at-sides idle.  These targets are never overwritten.
func _cache_rest_poses() -> void:
	_rest_poses.clear()
	for bone_idx: int in _bone_to_part:
		_rest_poses[bone_idx] = skeleton.get_bone_global_pose(bone_idx)
	_adjust_rest_to_idle()


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
