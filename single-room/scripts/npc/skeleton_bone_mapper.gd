class_name SkeletonBoneMapper
extends RefCounted
## Static utility — builds bone↔part and bone↔joint lookups at bind time.
##
## Pure algorithm: takes a Skeleton3D + ragdoll data, returns dictionaries.
## SkeletonBinding calls these once during bind() and stores the results.

const RAGDOLL_PROPORTIONS = preload("res://scripts/npc/ragdoll_proportions.gd")

## ── Bone → Part Mapping ─────────────────────────────────────────────────────

## Build the bone_idx → BodyPart lookup from BONE_NAME_MAP.
## Returns { "bone_to_part": Dictionary, "part_to_bone": Dictionary,
##           "unmatched_bones": PackedStringArray }
static func build_bone_mapping(
	skeleton: Skeleton3D,
	parts: Dictionary,  ## part_name → BodyPart  (ragdoll.parts)
) -> Dictionary:
	var bone_to_part: Dictionary = {}
	var bone_count: int = skeleton.get_bone_count()
	var unmatched_bones: PackedStringArray = []
	var candidates: Dictionary = {}

	for bone_idx: int in range(bone_count):
		var bone_name: String = skeleton.get_bone_name(bone_idx)
		var part_name: String = _map_bone_name_to_part(bone_name)
		if part_name == "":
			unmatched_bones.append(bone_name)
			continue
		if not parts.has(part_name):
			push_warning(
				"[SkeletonBoneMapper] Bone '%s' maps to part '%s' but part not found"
				% [bone_name, part_name])
			continue
		if not candidates.has(part_name):
			candidates[part_name] = []
		candidates[part_name].append({"idx": bone_idx, "name": bone_name})

	# Choose a single bone per part to avoid duplicate forces
	for part_name_key: String in candidates:
		var chosen: Dictionary = _pick_bone_candidate(
			part_name_key, candidates[part_name_key] as Array)
		if chosen.is_empty():
			continue
		var chosen_idx: int = int(chosen.get("idx", -1))
		if chosen_idx >= 0:
			bone_to_part[chosen_idx] = parts[part_name_key]

	# Build reverse lookup: BodyPart → bone_idx
	var part_to_bone: Dictionary = {}
	for bone_idx_key: int in bone_to_part:
		part_to_bone[bone_to_part[bone_idx_key]] = bone_idx_key

	if unmatched_bones.size() > 0:
		print("[SkeletonBoneMapper] %d unmatched bones: %s" % [
			unmatched_bones.size(), ", ".join(unmatched_bones)])

	return {
		"bone_to_part": bone_to_part,
		"part_to_bone": part_to_bone,
		"unmatched_bones": unmatched_bones,
	}


## ── Joint Mapping ───────────────────────────────────────────────────────────

## Build the bone_idx → Generic6DOFJoint3D lookup.
## Returns { "bone_to_joint": Dictionary, "pelvis_bone_idx": int }
static func build_joint_mapping(
	bone_to_part: Dictionary,   ## bone_idx → BodyPart
	child_to_joint: Dictionary,  ## child part_name → Generic6DOFJoint3D  (ragdoll.child_to_joint)
) -> Dictionary:
	var bone_to_joint: Dictionary = {}
	var pelvis_bone_idx: int = -1

	for bone_idx: int in bone_to_part:
		var part: BodyPart = bone_to_part[bone_idx] as BodyPart
		if child_to_joint.has(part.part_name):
			bone_to_joint[bone_idx] = child_to_joint[part.part_name]
		elif part.part_name == "pelvis":
			pelvis_bone_idx = bone_idx

	# Pelvis (root) has no parent joint — stabilized via world-space torque
	print("[SkeletonBoneMapper] Joint mapping: %d joints for %d bones (pelvis=%d)" % [
		bone_to_joint.size(), bone_to_part.size(), pelvis_bone_idx])

	return {
		"bone_to_joint": bone_to_joint,
		"pelvis_bone_idx": pelvis_bone_idx,
	}


## ── Internal helpers ────────────────────────────────────────────────────────

static func _map_bone_name_to_part(bone_name: String) -> String:
	return RAGDOLL_PROPORTIONS.get_part_name_for_bone(bone_name)


static func _pick_bone_candidate(part_name: String, options: Array) -> Dictionary:
	if options.is_empty():
		return {}
	if options.size() == 1:
		return options[0] as Dictionary
	# Prefer the exact Blender bone name when known
	var desired: String = RAGDOLL_PROPORTIONS.get_blender_bone_name_for_part(part_name)
	if desired != "":
		for item: Dictionary in options:
			if str(item.get("name", "")).to_lower() == desired.to_lower():
				_print_duplicate_mapping(part_name, options, item)
				return item
	# Prefer non-root if multiple candidates exist
	for item: Dictionary in options:
		var bone_name: String = str(item.get("name", "")).to_lower()
		if bone_name != "root":
			_print_duplicate_mapping(part_name, options, item)
			return item
	_print_duplicate_mapping(part_name, options, options[0] as Dictionary)
	return options[0] as Dictionary


static func _print_duplicate_mapping(
	part_name: String, options: Array, chosen: Dictionary,
) -> void:
	var names: PackedStringArray = []
	for item: Dictionary in options:
		names.append(str(item.get("name", "?")))
	print("[SkeletonBoneMapper] Duplicate bone mapping for part '%s': %s (using '%s')" % [
		part_name, ", ".join(names), str(chosen.get("name", "?"))])
