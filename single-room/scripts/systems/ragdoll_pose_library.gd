class_name RagdollPoseLibrary
extends RefCounted

static var _pose_cache: Dictionary = {}
static var _initialized: bool = false


static func get_pose(pose_name: String) -> RagdollPose:
	_ensure_loaded()
	return _pose_cache.get(pose_name, null) as RagdollPose


static func get_all() -> Dictionary:
	_ensure_loaded()
	return _pose_cache.duplicate()


static func _ensure_loaded() -> void:
	if _initialized:
		return
	_initialized = true
	_pose_cache.clear()
	_merge_library(DancePoses.get_all())
	_merge_library(YogaPoses.get_all())
	_merge_library(MartialArtsPoses.get_all())
	_merge_library(GymnasticsPoses.get_all())
	_merge_library(KamaSutraPoses.get_all())


static func _merge_library(lib: Dictionary) -> void:
	for pose_name: String in lib:
		if _pose_cache.has(pose_name):
			continue
		_pose_cache[pose_name] = lib[pose_name]
