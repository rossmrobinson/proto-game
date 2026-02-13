class_name NPCModelLoader

const RAGDOLL_PROPORTIONS = preload("res://scripts/npc/ragdoll_proportions.gd")
## Static utility for loading MakeHuman .blend models into the scene.
##
## Handles: scene loading, armature discovery, skeleton extraction,
## animation stopping, auto-scaling, and ragdoll alignment.
##
## Usage:
##   var skel: Skeleton3D = NPCModelLoader.load_model(self, npc_name, ...)
##   if skel != null:
##       skeleton_binding = SkeletonBinding.new()
##       skeleton_binding.bind(skel, ragdoll)


const BLEND_PATH: String = "res://assets/models/room1-models.blend"


# ──────────────────────────────────────────────────────────────────────────────
#  PUBLIC API
# ──────────────────────────────────────────────────────────────────────────────

## Load a .blend model, find the named armature, reparent it under target_node,
## scale/align it to the ragdoll, and return the Skeleton3D.
## Returns null on any failure (warnings are pushed internally).
static func load_model(
		target_node: Node3D,
		npc_name: String,
		model_name: String,
		ragdoll: HumanoidRagdollBuilder,
		auto_scale_model: bool,
		p_model_scale: float) -> Skeleton3D:

	if not ResourceLoader.exists(BLEND_PATH):
		push_warning("[NPCModelLoader] Model file not found: %s — keeping placeholder meshes" % BLEND_PATH)
		return null

	var scene_res: PackedScene = load(BLEND_PATH) as PackedScene
	if scene_res == null:
		push_warning("[NPCModelLoader] Failed to load model scene: %s" % BLEND_PATH)
		return null

	var scene_root: Node3D = scene_res.instantiate() as Node3D
	if scene_root == null:
		push_warning("[NPCModelLoader] Model scene instantiation failed")
		return null

	# Debug: list all top-level children in the imported scene
	var child_names: PackedStringArray = []
	for child: Node in scene_root.get_children():
		child_names.append(child.name)
	print("[NPCModelLoader] %s: .blend scene children: %s" % [npc_name, ", ".join(child_names)])

	# Find the named armature/mesh matching our model_name
	var armature: Node = _find_armature(scene_root, model_name)
	if armature == null:
		push_warning("[NPCModelLoader] Armature '%s' not found in %s — children: %s" % [
			model_name, BLEND_PATH, ", ".join(child_names)])
		scene_root.queue_free()
		return null

	print("[NPCModelLoader] %s: found armature node '%s' (type=%s)" % [
		npc_name, armature.name, armature.get_class()])

	# Reparent just the armature node into the target
	_clear_owner_recursive(armature)
	armature.get_parent().remove_child(armature)
	scene_root.queue_free()
	target_node.add_child(armature)

	# Zero only X and Z — Y offset is the Blender ground-to-origin height
	if armature is Node3D:
		var arm3d: Node3D = armature as Node3D
		arm3d.position = Vector3(0.0, arm3d.position.y, 0.0)
		arm3d.rotation = Vector3.ZERO

	# Find the Skeleton3D within the armature subtree
	var skel: Skeleton3D = _find_skeleton(armature)
	if skel == null:
		push_warning("[NPCModelLoader] No Skeleton3D found under armature '%s'" % model_name)
		return null

	# Stop any imported animations that might override bone poses
	_stop_imported_animations(armature)
	_report_animation_drivers(npc_name, armature)

	# Auto-scale and align the model to match the ragdoll
	if armature is Node3D:
		_apply_model_scale(armature as Node3D, skel, ragdoll, auto_scale_model, p_model_scale)
		_align_model_to_ragdoll(armature as Node3D, skel, ragdoll)

	_log_model_scale(npc_name, skel, ragdoll)
	return skel


# ──────────────────────────────────────────────────────────────────────────────
#  SCALING & ALIGNMENT
# ──────────────────────────────────────────────────────────────────────────────

static func _apply_model_scale(armature: Node3D, skel: Skeleton3D,
		ragdoll: HumanoidRagdollBuilder,
		auto_scale_model: bool, p_model_scale: float) -> void:
	if armature == null or skel == null:
		return
	var height: float = _get_skeleton_height(skel)
	if height <= 0.0:
		return
	var target_height: float = _get_target_body_height(ragdoll)
	if target_height <= 0.0:
		return
	var auto_scale: float = target_height / height
	var final_scale: float = p_model_scale
	if auto_scale_model:
		final_scale *= auto_scale
	if final_scale <= 0.0:
		push_warning("[NPCModelLoader] Invalid model scale: %.3f" % final_scale)
		return
	armature.scale = Vector3.ONE * final_scale


static func _align_model_to_ragdoll(armature: Node3D, skel: Skeleton3D,
		ragdoll: HumanoidRagdollBuilder) -> void:
	if armature == null or skel == null:
		return
	var ragdoll_min_y: float = _get_ragdoll_min_foot_y(ragdoll)
	if ragdoll_min_y == INF:
		return
	var skel_min_y: float = _get_skeleton_min_foot_y(skel)
	if skel_min_y == INF:
		return
	var delta_y: float = ragdoll_min_y - skel_min_y
	if absf(delta_y) < 0.0001:
		return
	armature.position.y += delta_y


static func _log_model_scale(npc_name: String, skel: Skeleton3D,
		ragdoll: HumanoidRagdollBuilder) -> void:
	var height: float = _get_skeleton_height(skel)
	if skel is Node3D:
		height *= _get_node_scale_factor(skel as Node3D)
	if height <= 0.0:
		return
	var target_height: float = _get_target_body_height(ragdoll)
	if target_height <= 0.0:
		return
	var ratio: float = height / target_height
	print("[NPCModelLoader] %s model height=%.2f target=%.2f ratio=%.2f" % [
		npc_name, height, target_height, ratio])
	if ratio < 0.9 or ratio > 1.1:
		push_warning("[NPCModelLoader] %s scale mismatch: model %.2f vs target %.2f" % [
			npc_name, height, target_height])


# ──────────────────────────────────────────────────────────────────────────────
#  SKELETON MEASUREMENT
# ──────────────────────────────────────────────────────────────────────────────

static func _get_target_body_height(ragdoll: HumanoidRagdollBuilder) -> float:
	if ragdoll != null:
		return float(ragdoll.body_height)
	return 1.75


static func _get_skeleton_height(skel: Skeleton3D) -> float:
	if skel == null:
		return 0.0
	var bone_count: int = skel.get_bone_count()
	if bone_count <= 0:
		return 0.0
	var min_y: float = INF
	var max_y: float = -INF
	for i: int in range(bone_count):
		var pose: Transform3D = skel.get_bone_global_pose(i)
		var pos: Vector3 = pose.origin
		min_y = minf(min_y, pos.y)
		max_y = maxf(max_y, pos.y)
	var height: float = max_y - min_y
	return maxf(height, 0.0)


static func _get_ragdoll_min_foot_y(ragdoll: HumanoidRagdollBuilder) -> float:
	if ragdoll == null:
		return INF
	var min_y: float = INF
	var foot_parts: PackedStringArray = [
		"left_foot", "right_foot", "left_toes", "right_toes",
	]
	for part_name: String in foot_parts:
		if not ragdoll.parts.has(part_name):
			continue
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		if part == null:
			continue
		var half_height: float = part.get_collision_half_height()
		min_y = minf(min_y, part.global_position.y - half_height)
	return min_y


static func _get_skeleton_min_foot_y(skel: Skeleton3D) -> float:
	if skel == null:
		return INF
	var min_y: float = INF
	var foot_parts: PackedStringArray = [
		"left_foot", "right_foot", "left_toes", "right_toes",
	]
	for part_name: String in foot_parts:
		var bone_name: String = RAGDOLL_PROPORTIONS.get_blender_bone_name_for_part(part_name)
		if bone_name == "":
			bone_name = part_name
		var idx: int = _find_bone_index_ci(skel, bone_name)
		if idx < 0:
			continue
		var pose: Transform3D = skel.get_bone_global_pose(idx)
		var world_pos: Vector3 = (skel.global_transform * pose).origin
		min_y = minf(min_y, world_pos.y)
	if min_y == INF:
		min_y = _get_skeleton_min_y_fallback(skel)
	return min_y


static func _get_skeleton_min_y_fallback(skel: Skeleton3D) -> float:
	var bone_count: int = skel.get_bone_count()
	if bone_count <= 0:
		return INF
	var min_y: float = INF
	for i: int in range(bone_count):
		var pose: Transform3D = skel.get_bone_global_pose(i)
		var world_pos: Vector3 = (skel.global_transform * pose).origin
		min_y = minf(min_y, world_pos.y)
	return min_y


# ──────────────────────────────────────────────────────────────────────────────
#  SCENE TREE HELPERS
# ──────────────────────────────────────────────────────────────────────────────

static func _find_bone_index_ci(skel: Skeleton3D, bone_name: String) -> int:
	if bone_name == "":
		return -1
	var target: String = bone_name.to_lower()
	var bone_count: int = skel.get_bone_count()
	for i: int in range(bone_count):
		if skel.get_bone_name(i).to_lower() == target:
			return i
	return -1


static func _get_node_scale_factor(node: Node3D) -> float:
	if node == null:
		return 1.0
	var scale_vec: Vector3 = node.global_transform.basis.get_scale()
	var scale_factor: float = maxf(absf(scale_vec.x), maxf(absf(scale_vec.y), absf(scale_vec.z)))
	if scale_factor <= 0.0:
		return 1.0
	return scale_factor


## Stop any AnimationPlayer or AnimationTree nodes from auto-driving bones.
static func _stop_imported_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.stop()
		ap.autoplay = &""
	if node is AnimationTree:
		var tree: AnimationTree = node as AnimationTree
		tree.active = false
	for child: Node in node.get_children():
		_stop_imported_animations(child)


## One-shot diagnostic: report any animation drivers still active after stop.
static func _report_animation_drivers(npc_name: String, node: Node) -> void:
	var active_players: PackedStringArray = []
	var active_trees: PackedStringArray = []
	_collect_active_drivers(node, active_players, active_trees)
	if active_players.is_empty() and active_trees.is_empty():
		print("[NPCModelLoader] %s: no active animation drivers" % npc_name)
		return
	if not active_players.is_empty():
		push_warning("[NPCModelLoader] %s: active AnimationPlayer(s): %s" % [
			npc_name, ", ".join(active_players)])
	if not active_trees.is_empty():
		push_warning("[NPCModelLoader] %s: active AnimationTree(s): %s" % [
			npc_name, ", ".join(active_trees)])


static func _collect_active_drivers(node: Node,
		active_players: PackedStringArray,
		active_trees: PackedStringArray) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		if ap.is_playing() or ap.autoplay != &"":
			active_players.append(ap.name)
	if node is AnimationTree:
		var tree: AnimationTree = node as AnimationTree
		if tree.active:
			active_trees.append(tree.name)
	for child: Node in node.get_children():
		_collect_active_drivers(child, active_players, active_trees)


## Recursively search for a node whose name contains the model name (armature root).
static func _find_armature(root: Node, target_name: String) -> Node:
	var target_lower: String = target_name.to_lower()
	for child: Node in root.get_children():
		if child.name.to_lower().contains(target_lower):
			return child
	# Deeper search
	for child: Node in root.get_children():
		var found: Node = _find_armature(child, target_name)
		if found != null:
			return found
	return null


## Find the first Skeleton3D in a subtree.
static func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Recursively clear the owner on a node and all its descendants.
## Prevents "inconsistent owner" warnings when reparenting imported sub-trees.
static func _clear_owner_recursive(node: Node) -> void:
	node.set_owner(null)
	for child: Node in node.get_children():
		_clear_owner_recursive(child)
