class_name RagdollCalibrationRunner
extends Node

const CONFIG_PATH: String = "res://config/ragdoll-calibration-config.tres"
const MAX_START_ATTEMPTS: int = 120

enum State {
	IDLE,
	FREEZE_BASELINE,
	SETTLE_POSE,
	HOLD_BASELINE,
	RUN_LOGGING,
	COMPLETE,
}

var config: RagdollCalibrationConfig = null

var _state: int = State.IDLE
var _timer: float = 0.0
var _sample_timer: float = 0.0
var _run_timer: float = 0.0
var _iteration: int = 0
var _pending_start: bool = false
var _start_attempts: int = 0

var _npc: NPCPlaceholder = null
var _binding: SkeletonBinding = null
var _ragdoll: HumanoidRagdollBuilder = null
var _animator: RagdollAnimator = null

var _baseline: Dictionary = {}
var _part_accum: Dictionary = {}
var _part_max: Dictionary = {}
var _part_final: Dictionary = {}
var _sample_count: int = 0
var _run_samples: Array = []
var _results: Array = []
var _log_path: String = ""


func _ready() -> void:
	add_to_group(&"ragdoll_calibration")
	config = _load_config()
	if config == null:
		return
	if not OS.is_debug_build():
		return
	if not config.enabled:
		return
	_pending_start = config.auto_start
	set_physics_process(true)


func request_start() -> void:
	if not OS.is_debug_build():
		return
	if config == null:
		config = _load_config()
	if config == null or not config.enabled:
		return
	_pending_start = true
	_start_attempts = 0
	if _state != State.IDLE and _state != State.COMPLETE:
		_state = State.IDLE


func _physics_process(delta: float) -> void:
	if _pending_start:
		if _try_start_run():
			_pending_start = false
		else:
			return
	if _state == State.IDLE or _state == State.COMPLETE:
		return

	match _state:
		State.FREEZE_BASELINE:
			# Baseline snap already applied; wait for hold timer in HOLD_BASELINE.
			_enter_hold_baseline()
		State.SETTLE_POSE:
			_timer += delta
			if _timer >= config.pose_settle_seconds:
				_freeze_physics(false)
				_enter_hold_baseline()
		State.HOLD_BASELINE:
			_timer += delta
			if _timer >= config.baseline_hold_seconds:
				_capture_baseline()
				_enter_run_logging()
		State.RUN_LOGGING:
			_run_timer += delta
			_sample_timer += delta
			if _sample_timer >= config.sample_interval:
				_sample_timer = 0.0
				_sample_run()
			if _run_timer >= config.run_seconds:
				_finish_iteration()
		_:
			pass


func _load_config() -> RagdollCalibrationConfig:
	if not ResourceLoader.exists(CONFIG_PATH):
		return null
	var res: Resource = load(CONFIG_PATH)
	if res is RagdollCalibrationConfig:
		return res as RagdollCalibrationConfig
	return null


func _try_start_run() -> bool:
	_npc = _find_target_npc()
	if _npc == null:
		_start_attempts += 1
		if _start_attempts >= MAX_START_ATTEMPTS:
			push_warning("[RagdollCalibration] NPC not found after retries")
			_pending_start = false
		return false
	_binding = _npc.skeleton_binding
	if _binding == null:
		_binding = _npc.get_node_or_null("SkeletonBinding") as SkeletonBinding
	_ragdoll = _npc.ragdoll
	_animator = _find_animator(_npc)
	if _binding == null or _ragdoll == null:
		_start_attempts += 1
		if _start_attempts >= MAX_START_ATTEMPTS:
			push_warning("[RagdollCalibration] Binding not ready for %s" % _npc.npc_name)
			_pending_start = false
		return false
	_start_attempts = 0
	_prepare_npc()
	_iteration = 0
	_results.clear()
	_log_path = _build_log_path()
	_ensure_log_dir()
	_cleanup_logs()
	_enter_freeze_baseline()
	return true


func _find_target_npc() -> NPCPlaceholder:
	var nodes: Array = get_tree().get_nodes_in_group(&"npc")
	if nodes.is_empty():
		return null
	if config.npc_name == "":
		return nodes[0] as NPCPlaceholder
	for node: Node in nodes:
		var npc: NPCPlaceholder = node as NPCPlaceholder
		if npc == null:
			continue
		if npc.npc_name == config.npc_name or npc.name == config.npc_name:
			return npc
	return null


func _find_animator(npc: NPCPlaceholder) -> RagdollAnimator:
	if npc == null:
		return null
	var direct: Node = npc.get_node_or_null("RagdollAnimator")
	if direct is RagdollAnimator:
		return direct as RagdollAnimator
	for child: Node in npc.get_children():
		if child is RagdollAnimator:
			return child as RagdollAnimator
	return null


func _prepare_npc() -> void:
	if _npc == null:
		return
	if _npc.has_method(&"set_sleeping"):
		_npc.call(&"set_sleeping", false)
	if _npc.activity_controller != null:
		_npc.activity_controller.set_active(false)
	if _animator != null:
		_animator.stop_sequence()
		_animator.clear_pose()


func _enter_freeze_baseline() -> void:
	_state = State.FREEZE_BASELINE
	_timer = 0.0
	_sample_timer = 0.0
	_run_timer = 0.0
	_sample_count = 0
	_run_samples.clear()
	_part_accum.clear()
	_part_max.clear()
	_part_final.clear()
	_baseline.clear()

	_apply_overrides_from_file()
	_freeze_physics()

	if _animator != null:
		if config.pose_name != "":
			_animator.set_pose_by_name(config.pose_name, 0.0)
			_state = State.SETTLE_POSE
			_timer = 0.0
			_unfreeze_physics(false)
			return
		_animator.clear_pose()


func _enter_hold_baseline() -> void:
	_state = State.HOLD_BASELINE
	_timer = 0.0


func _enter_run_logging() -> void:
	_state = State.RUN_LOGGING
	_timer = 0.0
	_run_timer = 0.0
	_sample_timer = 0.0
	_sample_count = 0
	_run_samples.clear()
	_part_accum.clear()
	_part_max.clear()
	_part_final.clear()
	_unfreeze_physics()


func _finish_iteration() -> void:
	_freeze_physics()
	var result: Dictionary = _build_iteration_result()
	_results.append(result)
	_write_log()
	_iteration += 1
	if _iteration >= config.iterations:
		_state = State.COMPLETE
		return
	_enter_freeze_baseline()


func _freeze_physics(snap_to_rest: bool = true) -> void:
	if _binding == null:
		return
	_binding.set_forced_sleep(true)
	if snap_to_rest:
		_binding.snap_parts_to_rest_pose()
	_binding.freeze_parts()


func _unfreeze_physics(enable_binding: bool = true) -> void:
	if _binding == null:
		return
	if enable_binding:
		_binding.set_forced_sleep(false)
	_binding.unfreeze_parts()


func _capture_baseline() -> void:
	if _ragdoll == null:
		return
	_baseline.clear()
	for part_name_key: String in _ragdoll.parts:
		var part: BodyPart = _ragdoll.parts[part_name_key] as BodyPart
		if part == null:
			continue
		_baseline[part.part_name] = part.global_position


func _sample_run() -> void:
	if _ragdoll == null:
		return
	var sample_mean: Vector3 = Vector3.ZERO
	var part_count: int = 0
	var max_dist: float = 0.0
	var max_part: String = ""
	for part_name_key: String in _ragdoll.parts:
		var part: BodyPart = _ragdoll.parts[part_name_key] as BodyPart
		if part == null:
			continue
		var base: Vector3 = _baseline.get(part.part_name, part.global_position) as Vector3
		var delta: Vector3 = part.global_position - base
		part_count += 1
		sample_mean += delta
		var dist: float = delta.length()
		if dist > max_dist:
			max_dist = dist
			max_part = part.part_name
		var prev: Vector3 = _part_accum.get(part.part_name, Vector3.ZERO) as Vector3
		_part_accum[part.part_name] = prev + delta
		var prev_max: float = float(_part_max.get(part.part_name, 0.0))
		if dist > prev_max:
			_part_max[part.part_name] = dist
		_part_final[part.part_name] = delta
	if part_count > 0:
		sample_mean /= float(part_count)
	_run_samples.append({
		"t": _run_timer,
		"mean": _vec3_to_dict(sample_mean),
		"max_part": max_part,
		"max_dist": max_dist,
	})
	_sample_count += 1


func _build_iteration_result() -> Dictionary:
	var mean_all: Vector3 = _compute_mean_all()
	var part_summary: Array = _build_part_summary()
	var suggestion: Dictionary = _build_suggestion()
	if config.auto_apply_suggestions:
		_apply_suggestion(suggestion)
	return {
		"iteration": _iteration + 1,
		"pose": config.pose_name if config.pose_name != "" else "rest",
		"sample_count": _sample_count,
		"mean_delta": _vec3_to_dict(mean_all),
		"baseline": _baseline_to_dict(),
		"parts": part_summary,
		"samples": _run_samples.duplicate(true),
		"suggested_overrides": suggestion,
	}


func _compute_mean_all() -> Vector3:
	var out: Vector3 = Vector3.ZERO
	var count: int = 0
	if _sample_count <= 0:
		return out
	for part_name: String in _part_accum:
		var sum: Vector3 = _part_accum[part_name] as Vector3
		out += sum / float(_sample_count)
		count += 1
	if count > 0:
		out /= float(count)
	return out


func _build_part_summary() -> Array:
	var entries: Array = []
	if _sample_count <= 0:
		return entries
	for part_name: String in _part_final:
		var sum: Vector3 = _part_accum.get(part_name, Vector3.ZERO) as Vector3
		var mean: Vector3 = sum / float(_sample_count)
		var final: Vector3 = _part_final.get(part_name, Vector3.ZERO) as Vector3
		var max_dist: float = float(_part_max.get(part_name, 0.0))
		entries.append({
			"part": part_name,
			"mean": _vec3_to_dict(mean),
			"mean_dist": mean.length(),
			"max_dist": max_dist,
			"final": _vec3_to_dict(final),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("mean_dist", 0.0)) > float(b.get("mean_dist", 0.0))
	)
	if config.max_report_parts > 0 and entries.size() > config.max_report_parts:
		entries = entries.slice(0, config.max_report_parts)
	return entries


func _build_suggestion() -> Dictionary:
	if _sample_count <= 0:
		return {}
	var parts: PackedStringArray = config.suggest_parts
	var sum_z: float = 0.0
	var count: int = 0
	if parts.is_empty():
		for part_name: String in _part_accum:
			var sum: Vector3 = _part_accum[part_name] as Vector3
			sum_z += (sum.z / float(_sample_count))
			count += 1
	else:
		for part_name: String in parts:
			if not _part_accum.has(part_name):
				continue
			var sum: Vector3 = _part_accum[part_name] as Vector3
			sum_z += (sum.z / float(_sample_count))
			count += 1
	if count <= 0:
		return {}
	var mean_z: float = sum_z / float(count)
	if absf(mean_z) < config.suggest_min_drift_z:
		return {}
	var step: float = clampf(-mean_z * config.suggest_scale, -config.suggest_max_step, config.suggest_max_step)
	var new_offset: float = step
	if _binding != null:
		new_offset = _binding.target_z_offset + step
	return {
		"target_z_offset_enabled": true,
		"target_z_offset": new_offset,
		"mean_drift_z": mean_z,
		"step": step,
	}


func _apply_suggestion(suggestion: Dictionary) -> void:
	if suggestion.is_empty() or _binding == null:
		return
	var overrides: Dictionary = {}
	if suggestion.has("target_z_offset_enabled"):
		var enabled: bool = bool(suggestion.get("target_z_offset_enabled", false))
		_binding.target_z_offset_enabled = enabled
		overrides["target_z_offset_enabled"] = enabled
	if suggestion.has("target_z_offset"):
		var value: float = float(suggestion.get("target_z_offset", 0.0))
		_binding.target_z_offset = value
		overrides["target_z_offset"] = value
	_write_override_file(overrides)


func _apply_overrides_from_file() -> void:
	var overrides: Dictionary = _read_override_file()
	if overrides.is_empty() or _binding == null:
		return
	if _binding.has_method(&"apply_runtime_overrides"):
		_binding.call(&"apply_runtime_overrides", overrides)


func _read_override_file() -> Dictionary:
	if config == null or config.overrides_path == "":
		return {}
	if not FileAccess.file_exists(config.overrides_path):
		return {}
	var file: FileAccess = FileAccess.open(config.overrides_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed as Dictionary
	if data.has("overrides") and typeof(data["overrides"]) == TYPE_DICTIONARY:
		return data["overrides"] as Dictionary
	return data


func _write_override_file(overrides: Dictionary) -> void:
	if config == null or config.overrides_path == "" or overrides.is_empty():
		return
	var current: Dictionary = _read_override_file()
	for key: String in overrides:
		current[key] = overrides[key]
	var wrapper: Dictionary = {"overrides": current}
	var file: FileAccess = FileAccess.open(config.overrides_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(wrapper, "\t"))
	file.close()


func _baseline_to_dict() -> Dictionary:
	var out: Dictionary = {}
	for part_name: String in _baseline:
		var pos: Vector3 = _baseline[part_name] as Vector3
		out[part_name] = _vec3_to_dict(pos)
	return out


func _vec3_to_dict(vec: Vector3) -> Dictionary:
	return {"x": vec.x, "y": vec.y, "z": vec.z}


func _ensure_log_dir() -> void:
	if config == null or config.log_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(config.log_dir)


func _cleanup_logs() -> void:
	if config == null or config.log_dir == "":
		return
	var files: PackedStringArray = DirAccess.get_files_at(config.log_dir)
	if files.is_empty():
		return
	var now: int = int(Time.get_unix_time_from_system())
	var max_age_days: int = maxi(0, config.log_max_age_days)
	var max_age_sec: int = max_age_days * 86400
	var entries: Array = []
	for filename: String in files:
		if not filename.begins_with("ragdoll_calibration_"):
			continue
		if not filename.ends_with(".json"):
			continue
		var full_path: String = "%s/%s" % [config.log_dir, filename]
		var mtime: int = FileAccess.get_modified_time(full_path)
		if max_age_sec > 0 and now - mtime > max_age_sec:
			_delete_file(full_path)
			continue
		entries.append({"path": full_path, "mtime": mtime})
	var max_files: int = maxi(0, config.log_max_files)
	if max_files <= 0:
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("mtime", 0)) > int(b.get("mtime", 0))
	)
	for i: int in range(entries.size()):
		if i < max_files:
			continue
		var path: String = str(entries[i].get("path", ""))
		if path != "":
			_delete_file(path)


func _delete_file(path: String) -> void:
	if path == "":
		return
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)


func _build_log_path() -> String:
	var npc_label: String = "npc"
	if _npc != null and _npc.npc_name != "":
		npc_label = _npc.npc_name
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	return "%s/ragdoll_calibration_%s_%s.json" % [config.log_dir, npc_label, stamp]


func _write_log() -> void:
	if _log_path == "":
		return
	var output: Dictionary = {
		"npc": _npc.npc_name if _npc != null else "",
		"time_ms": Time.get_ticks_msec(),
		"config": _config_to_dict(),
		"iterations": _results.duplicate(true),
	}
	var file: FileAccess = FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(output, "\t"))
	file.close()


func _config_to_dict() -> Dictionary:
	if config == null:
		return {}
	var suggest_list: Array = []
	for part_name: String in config.suggest_parts:
		suggest_list.append(part_name)
	return {
		"npc_name": config.npc_name,
		"pose_name": config.pose_name,
		"pose_settle_seconds": config.pose_settle_seconds,
		"baseline_hold_seconds": config.baseline_hold_seconds,
		"run_seconds": config.run_seconds,
		"sample_interval": config.sample_interval,
		"iterations": config.iterations,
		"max_report_parts": config.max_report_parts,
		"log_dir": config.log_dir,
		"auto_apply_suggestions": config.auto_apply_suggestions,
		"suggest_min_drift_z": config.suggest_min_drift_z,
		"suggest_scale": config.suggest_scale,
		"suggest_max_step": config.suggest_max_step,
		"suggest_parts": suggest_list,
	}
