class_name RagdollLogManager
extends RefCounted
## Owns JSONL log-file handles, snapshot writing, and log-dir cleanup
## for the ragdoll diagnostics system.
##
## Constructed once by RagdollDiagnostics.  Config is passed per-call so the
## manager never holds stale references.

var _log_files: Dictionary = {}
var _log_counts: Dictionary = {}
var _last_snapshot_ms: int = 0
var _last_cleanup_ms: int = 0


## ── Registration ────────────────────────────────────────────────────────────

func register(npc_name: String) -> void:
	if not _log_counts.has(npc_name):
		_log_counts[npc_name] = 0


## ── JSONL frame logging ─────────────────────────────────────────────────────

func log_snapshot(snapshot: Dictionary, config: RagdollDebugConfig) -> void:
	if config == null or not config.log_to_file:
		return
	var npc_name: String = snapshot.get("npc", "")
	if npc_name == "":
		return

	var count: int = int(_log_counts.get(npc_name, 0))
	if count >= config.log_frames:
		return

	var log_file: FileAccess = _get_log_file(npc_name, config)
	if log_file == null:
		return

	var payload: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"npc": npc_name,
		"tag": snapshot.get("tag", "sample"),
		"max_offset": snapshot.get("max_offset", 0.0),
		"max_offset_part": snapshot.get("max_offset_part", ""),
		"max_lin_vel": snapshot.get("max_lin_vel", 0.0),
		"max_lin_part": snapshot.get("max_lin_part", ""),
		"max_ang_vel": snapshot.get("max_ang_vel", 0.0),
		"max_ang_part": snapshot.get("max_ang_part", ""),
		"max_joint_error": snapshot.get("max_joint_error", 0.0),
		"max_joint_name": snapshot.get("max_joint_name", ""),
		"min_y": snapshot.get("min_y", 0.0),
		"max_y": snapshot.get("max_y", 0.0),
		"spawn_x": snapshot.get("spawn_x", 0.0),
		"spawn_y": snapshot.get("spawn_y", 0.0),
		"spawn_z": snapshot.get("spawn_z", 0.0),
		"pelvis_x": snapshot.get("pelvis_x", 0.0),
		"pelvis_y": snapshot.get("pelvis_y", 0.0),
		"pelvis_z": snapshot.get("pelvis_z", 0.0),
		"drift_x": snapshot.get("drift_x", 0.0),
		"drift_y": snapshot.get("drift_y", 0.0),
		"drift_z": snapshot.get("drift_z", 0.0),
		"drift_dist": snapshot.get("drift_dist", 0.0),
		"drift_dir_x": snapshot.get("drift_dir_x", 0.0),
		"drift_dir_z": snapshot.get("drift_dir_z", 0.0),
		"force_spring_x": snapshot.get("force_spring_x", 0.0),
		"force_spring_y": snapshot.get("force_spring_y", 0.0),
		"force_spring_z": snapshot.get("force_spring_z", 0.0),
		"force_stand_x": snapshot.get("force_stand_x", 0.0),
		"force_stand_y": snapshot.get("force_stand_y", 0.0),
		"force_stand_z": snapshot.get("force_stand_z", 0.0),
		"force_total_x": snapshot.get("force_total_x", 0.0),
		"force_total_y": snapshot.get("force_total_y", 0.0),
		"force_total_z": snapshot.get("force_total_z", 0.0),
		"force_total_mag": snapshot.get("force_total_mag", 0.0),
		"force_dir_x": snapshot.get("force_dir_x", 0.0),
		"force_dir_z": snapshot.get("force_dir_z", 0.0),
		"force_top_parts": snapshot.get("force_top_parts", []),
		"force_top_parts_count": snapshot.get("force_top_parts_count", 0),
		"penetrations": snapshot.get("penetrations", 0),
		"inter_npc_hits": snapshot.get("inter_npc_hits", 0),
		"unmatched_bones": snapshot.get("unmatched_bones", 0),
		"issues": snapshot.get("issues", []),
	}
	log_file.store_line(JSON.stringify(payload))
	_log_counts[npc_name] = count + 1
	maybe_cleanup_logs(config)


func log_joint_summary(binding: SkeletonBinding, tag: String) -> void:
	var entries: Array = binding.get_debug_joint_entries()
	if entries.is_empty():
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("error_deg", 0.0)) > float(b.get("error_deg", 0.0))
	)
	var top: PackedStringArray = []
	var limit: int = min(5, entries.size())
	for i: int in range(limit):
		var item: Dictionary = entries[i] as Dictionary
		var joint_name: String = str(item.get("joint", ""))
		var err: float = float(item.get("error_deg", 0.0))
		top.append("%s=%.1f" % [joint_name, err])
	print("[RagdollDiag] %s %s top_joints: %s" % [
		binding.get_npc_name(), tag, ", ".join(top)])


## ── Auto-snapshot on issues ─────────────────────────────────────────────────

func maybe_auto_snapshot(
	binding: SkeletonBinding,
	snapshot: Dictionary,
	config: RagdollDebugConfig,
) -> void:
	if config == null or not config.auto_snapshot_on_issue:
		return
	var issues: Array = snapshot.get("issues", []) as Array
	if issues.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var cooldown_ms: int = int(config.auto_snapshot_cooldown * 1000.0)
	if now - _last_snapshot_ms < cooldown_ms:
		return
	_last_snapshot_ms = now
	dump_for_binding(binding, "auto_issue", snapshot, config)


## ── Snapshot file writing ───────────────────────────────────────────────────

func dump_for_binding(
	binding: SkeletonBinding,
	reason: String,
	snapshot: Dictionary,
	config: RagdollDebugConfig,
) -> void:
	if config == null or binding == null:
		return
	ensure_log_dir(config.log_dir)
	var npc_name: String = binding.get_npc_name()
	if npc_name == "":
		npc_name = "unknown"
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "%s/ragdoll_snapshot_%s_%s.json" % [config.log_dir, npc_name, timestamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[RagdollLogManager] Cannot write snapshot: %s" % path)
		return
	var summary: Dictionary = snapshot_summary(snapshot)
	var data: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"reason": reason,
		"npc": npc_name,
		"project": str(ProjectSettings.get_setting("application/config/name")),
		"engine": Engine.get_version_info(),
		"summary": summary,
		"snapshot": binding.get_snapshot_data(
			config.snapshot_max_parts, config.snapshot_max_joints),
	}
	file.store_line(JSON.stringify(data))
	file.close()
	print("[RagdollLogManager] Snapshot written: %s" % path)
	maybe_cleanup_logs(config)


static func snapshot_summary(snapshot: Dictionary) -> Dictionary:
	return {
		"max_offset": snapshot.get("max_offset", 0.0),
		"max_offset_part": snapshot.get("max_offset_part", ""),
		"max_lin_vel": snapshot.get("max_lin_vel", 0.0),
		"max_lin_part": snapshot.get("max_lin_part", ""),
		"max_ang_vel": snapshot.get("max_ang_vel", 0.0),
		"max_ang_part": snapshot.get("max_ang_part", ""),
		"max_joint_error": snapshot.get("max_joint_error", 0.0),
		"max_joint_name": snapshot.get("max_joint_name", ""),
		"min_y": snapshot.get("min_y", 0.0),
		"max_y": snapshot.get("max_y", 0.0),
		"penetrations": snapshot.get("penetrations", 0),
		"inter_npc_hits": snapshot.get("inter_npc_hits", 0),
		"unmatched_bones": snapshot.get("unmatched_bones", 0),
		"issues": snapshot.get("issues", []),
	}


## ── Log-file handle ─────────────────────────────────────────────────────────

func _get_log_file(npc_name: String, config: RagdollDebugConfig) -> FileAccess:
	if _log_files.has(npc_name):
		return _log_files[npc_name] as FileAccess

	DirAccess.make_dir_recursive_absolute(config.log_dir)
	var file_path: String = ""
	if config.log_use_timestamped_files:
		var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		file_path = "%s/ragdoll_%s_%s.jsonl" % [config.log_dir, npc_name, timestamp]
	else:
		file_path = "%s/ragdoll_%s.jsonl" % [config.log_dir, npc_name]
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("[RagdollLogManager] Cannot open log file: %s" % file_path)
		return null

	_log_files[npc_name] = file
	maybe_cleanup_logs(config)
	return file


## ── Log directory management ────────────────────────────────────────────────

static func ensure_log_dir(log_dir: String) -> void:
	if log_dir.begins_with("user://"):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			push_warning("[RagdollLogManager] Cannot open user:// for logs")
			return
		var rel: String = log_dir.trim_prefix("user://")
		if rel != "":
			dir.make_dir_recursive(rel)
		return
	DirAccess.make_dir_recursive_absolute(log_dir)


func cleanup_logs(config: RagdollDebugConfig) -> void:
	if config == null:
		return
	if config.log_dir == "":
		return
	ensure_log_dir(config.log_dir)
	var files: PackedStringArray = DirAccess.get_files_at(config.log_dir)
	if files.is_empty():
		return
	var now: int = int(Time.get_unix_time_from_system())
	var max_age_days: int = maxi(0, config.log_max_age_days)
	var max_age_sec: int = max_age_days * 86400
	_cleanup_ragdoll_logs(files, now, max_age_sec, config)
	_cleanup_prefix_logs(files, now, max_age_sec,
		"ragdoll_snapshot_", ".json", config.snapshot_max_files, config.log_dir)
	_cleanup_prefix_logs(files, now, max_age_sec,
		"ragdoll_pose_report_", ".json", config.pose_report_max_files, config.log_dir)


func maybe_cleanup_logs(config: RagdollDebugConfig) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_cleanup_ms < 2000:
		return
	_last_cleanup_ms = now_ms
	cleanup_logs(config)


func _cleanup_ragdoll_logs(
	files: PackedStringArray, now: int, max_age_sec: int,
	config: RagdollDebugConfig,
) -> void:
	var max_files: int = maxi(0, config.log_max_files_per_npc)
	var buckets: Dictionary = {}
	for filename: String in files:
		if not filename.begins_with("ragdoll_"):
			continue
		if not filename.ends_with(".jsonl"):
			continue
		var base: String = filename.trim_suffix(".jsonl")
		var split_idx: int = base.rfind("_")
		if split_idx <= 7:
			continue
		var npc_name: String = base.substr(8, split_idx - 8)
		var full_path: String = "%s/%s" % [config.log_dir, filename]
		var mtime: int = FileAccess.get_modified_time(full_path)
		if max_age_sec > 0 and now - mtime > max_age_sec:
			_delete_file(full_path)
			continue
		if not buckets.has(npc_name):
			buckets[npc_name] = []
		var list: Array = buckets[npc_name] as Array
		list.append({"path": full_path, "mtime": mtime})
		buckets[npc_name] = list

	if max_files <= 0:
		return
	for npc_name: String in buckets:
		var entries: Array = buckets[npc_name] as Array
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("mtime", 0)) > int(b.get("mtime", 0))
		)
		for i: int in range(entries.size()):
			if i < max_files:
				continue
			var path: String = str(entries[i].get("path", ""))
			if path != "":
				_delete_file(path)


static func _cleanup_prefix_logs(
	files: PackedStringArray, now: int, max_age_sec: int,
	prefix: String, suffix: String, max_files: int, log_dir: String,
) -> void:
	var entries: Array = []
	for filename: String in files:
		if not filename.begins_with(prefix):
			continue
		if not filename.ends_with(suffix):
			continue
		var full_path: String = "%s/%s" % [log_dir, filename]
		var mtime: int = FileAccess.get_modified_time(full_path)
		if max_age_sec > 0 and now - mtime > max_age_sec:
			_delete_file(full_path)
			continue
		entries.append({"path": full_path, "mtime": mtime})

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


static func _delete_file(path: String) -> void:
	if path == "":
		return
	if not FileAccess.file_exists(path):
		return
	var err: Error = DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("[RagdollLogManager] Failed to delete log: %s" % path)
