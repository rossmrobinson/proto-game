class_name SkeletonBinding
extends Node
## Syncs a Skeleton3D (from an imported mesh) with our ragdoll physics bodies.
##
## Two modes:
##   ANIMATED  – Skeleton drives physics bodies (default when playing anims).
##   RAGDOLL   – Physics bodies drive skeleton (free-fall / grabbed).
##
## Uses HumanoidRagdollBuilder.BONE_NAME_MAP for name resolution.

enum Mode { ANIMATED, RAGDOLL }

## Current sync mode.
var mode: Mode = Mode.ANIMATED

## The Skeleton3D from the imported model scene.
var skeleton: Skeleton3D = null

## Reference to the ragdoll builder that owns the physics parts.
var ragdoll: HumanoidRagdollBuilder = null

## Cached mapping: bone_idx (int) → BodyPart node.
var _bone_to_part: Dictionary = {}

## Cached mapping: bone_idx (int) → rest-pose offset from part origin.
## Used to compensate for differences between bone pivot and body center.
var _bone_rest_offsets: Dictionary = {}

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

	if hide_placeholder_meshes:
		_hide_debug_meshes()

	set_physics_process(true)
	print("[SkeletonBinding] Bound %d bones to ragdoll parts" % _bone_to_part.size())


## Switch between animation-driven and physics-driven modes.
func set_mode(p_mode: Mode) -> void:
	if mode == p_mode:
		return
	mode = p_mode

	match mode:
		Mode.ANIMATED:
			# Clear any bone overrides so animations take control again
			for bone_idx: int in _bone_to_part:
				skeleton.clear_bone_pose_all_overrides()
			# Unfreeze ragdoll parts so they can be repositioned
			_set_parts_kinematic(false)

		Mode.RAGDOLL:
			# Stop animation player if one exists
			var anim_player: AnimationPlayer = _find_anim_player()
			if anim_player != null and anim_player.is_playing():
				anim_player.pause()


func _physics_process(_delta: float) -> void:
	if skeleton == null or ragdoll == null:
		return

	match mode:
		Mode.ANIMATED:
			_sync_skeleton_to_ragdoll()
		Mode.RAGDOLL:
			_sync_ragdoll_to_skeleton()


## ANIMATED mode: skeleton bone transforms → physics body positions.
func _sync_skeleton_to_ragdoll() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
		# Move the physics body to match the bone
		# Use global_position so the part follows regardless of hierarchy
		part.global_position = bone_global.origin
		part.global_basis = bone_global.basis


## RAGDOLL mode: physics body transforms → skeleton bone overrides.
func _sync_ragdoll_to_skeleton() -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		# Convert part's global transform to skeleton-local space
		var skel_inv: Transform3D = skeleton.global_transform.affine_inverse()
		var part_in_skel: Transform3D = skel_inv * part.global_transform

		# Get parent bone's global pose to express this as a local override
		var parent_idx: int = skeleton.get_bone_parent(bone_idx)
		if parent_idx >= 0:
			var parent_global: Transform3D = skeleton.get_bone_global_pose(parent_idx)
			var local_pose: Transform3D = parent_global.affine_inverse() * part_in_skel
			skeleton.set_bone_pose(bone_idx, local_pose)
		else:
			skeleton.set_bone_pose(bone_idx, part_in_skel)


## Build the bone_idx → BodyPart lookup from BONE_NAME_MAP.
func _build_bone_mapping() -> void:
	_bone_to_part.clear()
	var bone_count: int = skeleton.get_bone_count()

	for bone_idx: int in range(bone_count):
		var bone_name: String = skeleton.get_bone_name(bone_idx)

		# Check if this Blender bone name maps to one of our ragdoll parts
		if HumanoidRagdollBuilder.BONE_NAME_MAP.has(bone_name):
			var part_name: String = HumanoidRagdollBuilder.BONE_NAME_MAP[bone_name] as String
			if ragdoll.parts.has(part_name):
				_bone_to_part[bone_idx] = ragdoll.parts[part_name]
			else:
				push_warning("[SkeletonBinding] Bone '%s' maps to part '%s' but part not found in ragdoll" % [bone_name, part_name])
		# Also try lowercase bone name (Blender sometimes exports differently)
		elif HumanoidRagdollBuilder.BONE_NAME_MAP.has(bone_name.to_lower()):
			var part_name: String = HumanoidRagdollBuilder.BONE_NAME_MAP[bone_name.to_lower()] as String
			if ragdoll.parts.has(part_name):
				_bone_to_part[bone_idx] = ragdoll.parts[part_name]


## Hide the placeholder debug spheres/capsules since we now have a real mesh.
func _hide_debug_meshes() -> void:
	for part_name: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		for child: Node in part.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false


## Set all bound ragdoll parts to kinematic (animated mode) or dynamic (ragdoll).
func _set_parts_kinematic(kinematic: bool) -> void:
	for bone_idx: int in _bone_to_part:
		var part: BodyPart = _bone_to_part[bone_idx] as BodyPart
		if kinematic:
			part.freeze = true
			part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		else:
			part.freeze = false


## Find an AnimationPlayer sibling or child of the skeleton's parent.
func _find_anim_player() -> AnimationPlayer:
	if skeleton == null:
		return null
	var parent: Node = skeleton.get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
	return null
