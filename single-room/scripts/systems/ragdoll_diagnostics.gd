extends Node

const CONFIG_PATH: String = "res://config/ragdoll-debug-config.tres"

var config: RagdollDebugConfig = null

var _snapshots: Dictionary = {}
var _sample_timer: float = 0.0
var _label_timer: float = 0.0

var _visualizer: RagdollDebugVisualizer = null
var _log_manager: RagdollLogManager = null

var _override_path: String = "J:/proto-game/single-room/logs/llm_overrides.json"
var _override_mtime: int = 0
var _override_cache: Dictionary = {}
var _respawn_path: String = "J:/proto-game/single-room/logs/llm-respawn-request.json"
var _respawn_mtime: int = 0
var _respawn_last_id: int = 0
var _pose_report_path: String = "J:/proto-game/single-room/logs/llm-pose-report-request.json"
var _pose_report_mtime: int = 0
var _pose_report_last_id: int = 0


func _ready() -> void:
	config = _load_config()
	_ensure_actions()
	_log_manager = RagdollLogManager.new()
	_log_manager.cleanup_logs(config)
	_visualizer = RagdollDebugVisualizer.new(self)
	_visualizer.setup()
	_visualizer.set_mesh_visibility(config.enabled and config.show_debug_meshes)
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"respawn_npcs"):
		_respawn_all_npcs()
		return
	if event.is_action_pressed(&"toggle_ragdoll_debug"):
		config.enabled = not config.enabled
		_visualizer.clear_lines()
		_visualizer.update_labels(_snapshots, config)
		_visualizer.set_mesh_visibility(config.enabled and config.show_debug_meshes)
		return
	if event.is_action_pressed(&"toggle_ragdoll_overlay"):
		config.show_overlay = not config.show_overlay
		return
	if event.is_action_pressed(&"toggle_ragdoll_meshes"):
		config.show_debug_meshes = not config.show_debug_meshes
		_visualizer.apply_mesh_visibility(config)
		return
	if event.is_action_pressed(&"toggle_ragdoll_labels"):
		config.show_part_labels = not config.show_part_labels
		_visualizer.update_labels(_snapshots, config)
		return
	if event.is_action_pressed(&"toggle_ragdoll_offsets"):
		config.show_offset_lines = not config.show_offset_lines
		_visualizer.clear_lines()
		return
	if event.is_action_pressed(&"toggle_ragdoll_axes"):
		config.show_joint_axes = not config.show_joint_axes
		_visualizer.clear_lines()
		return
	if event.is_action_pressed(&"toggle_ragdoll_telemetry"):
		config.log_to_file = not config.log_to_file
		return
	if event.is_action_pressed(&"toggle_ragdoll_limits"):
		config.disable_joint_limits = not config.disable_joint_limits
		return
	if event.is_action_pressed(&"toggle_ragdoll_springs"):
		config.disable_position_springs = not config.disable_position_springs
		return
	if event.is_action_pressed(&"toggle_ragdoll_joint_pd"):
		config.disable_joint_pd = not config.disable_joint_pd
		return
	if event.is_action_pressed(&"toggle_ragdoll_pelvis_lock"):
		config.disable_pelvis_lock = not config.disable_pelvis_lock
		return
	if event.is_action_pressed(&"toggle_ragdoll_rest_source"):
		config.use_physics_rest_relative = not config.use_physics_rest_relative
		return
	if event.is_action_pressed(&"dump_ragdoll_snapshot"):
		_dump_snapshot("manual")
		return


func _physics_process(delta: float) -> void:
	_tick_respawn_requests()
	_tick_pose_report_requests()
	if config == null or not config.enabled:
		return

	_sample_timer += delta
	if _sample_timer >= config.sample_interval:
		_sample_timer = 0.0
		_sample_ragdolls()

	_label_timer += delta
	if _label_timer >= config.label_update_interval:
		_label_timer = 0.0
		_visualizer.update_labels(_snapshots, config)


func _process(_delta: float) -> void:
	if config == null or not config.enabled:
		return
	if not config.show_offset_lines and not config.show_joint_axes:
		return
	_visualizer.update_lines(_snapshots, config)


func register_binding(binding: SkeletonBinding) -> void:
	if binding == null:
		return
	var npc_name: String = binding.get_npc_name()
	if npc_name == "":
		return
	_log_manager.register(npc_name)


func report_event(binding: SkeletonBinding, tag: String) -> void:
	if binding == null or config == null or not config.enabled:
		return
	var snapshot: Dictionary = _compute_snapshot(binding)
	snapshot["tag"] = tag
	_snapshots[binding.get_npc_name()] = snapshot
	_log_manager.log_snapshot(snapshot, config)
	if tag == "after_snap" or tag == "post_unfreeze" or tag.begins_with("dynamic_frame_"):
		_log_manager.log_joint_summary(binding, tag)


func get_overlay_text() -> String:
	if config == null or not config.enabled or not config.show_overlay:
		return ""
	var lines: PackedStringArray = []
	lines.append("Ragdoll Debug: %s" % ["ON" if config.enabled else "OFF"])
	lines.append("Lines=%s Axes=%s Labels=%s Meshes=%s Log=%s" % [
		"ON" if config.show_offset_lines else "OFF",
		"ON" if config.show_joint_axes else "OFF",
		"ON" if config.show_part_labels else "OFF",
		"ON" if config.show_debug_meshes else "OFF",
		"ON" if config.log_to_file else "OFF",
	])

	var npc_keys: Array = _snapshots.keys()
	npc_keys.sort()
	for npc_name: String in npc_keys:
		var snap: Dictionary = _snapshots[npc_name] as Dictionary
		var issues: Array = snap.get("issues", []) as Array
		var issue_flag: String = "!" if issues.size() > 0 else ""
		lines.append("%s: off=%.3f v=%.2f w=%.2f j=%.1f pen=%d%s" % [
			npc_name,
			float(snap.get("max_offset", 0.0)),
			float(snap.get("max_lin_vel", 0.0)),
			float(snap.get("max_ang_vel", 0.0)),
			float(snap.get("max_joint_error", 0.0)),
			int(snap.get("penetrations", 0)) + int(snap.get("inter_npc_hits", 0)),
			issue_flag,
		])
		lines.append("%s: a=%.2f lim=%s sp=%s pd=%s pel=%s" % [
			npc_name,
			float(snap.get("min_axis_align", 1.0)),
			"OFF" if config.disable_joint_limits else "ON",
			"OFF" if config.disable_position_springs else "ON",
			"OFF" if config.disable_joint_pd else "ON",
			"OFF" if config.disable_pelvis_lock else "ON",
		])
		lines.append("%s: rest=%s" % [
			npc_name,
			"PHYS" if config.use_physics_rest_relative else "BONE",
		])
		lines.append("%s: rec=%.2f passive=%s" % [
			npc_name,
			float(snap.get("recover_scale", 1.0)),
			"YES" if bool(snap.get("recover_passive", false)) else "NO",
		])
		lines.append("%s: drift=%.2f dir=(%.2f,%.2f)" % [
			npc_name,
			float(snap.get("drift_dist", 0.0)),
			float(snap.get("drift_dir_x", 0.0)),
			float(snap.get("drift_dir_z", 0.0)),
		])
		lines.append("%s: force=%.1f dir=(%.2f,%.2f)" % [
			npc_name,
			float(snap.get("force_total_mag", 0.0)),
			float(snap.get("force_dir_x", 0.0)),
			float(snap.get("force_dir_z", 0.0)),
		])

	return "\n".join(lines)


func get_all_snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc_name: String in _snapshots:
		out.append(_snapshots[npc_name] as Dictionary)
	return out


func _sample_ragdolls() -> void:
	var bindings: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	var overrides: Dictionary = _load_overrides()
	for node: Node in bindings:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding == null:
			continue
		if binding.has_method(&"apply_debug_overrides"):
			binding.call(&"apply_debug_overrides", config)
		if not overrides.is_empty() and binding.has_method(&"apply_runtime_overrides"):
			binding.call(&"apply_runtime_overrides", overrides)
		var snapshot: Dictionary = _compute_snapshot(binding)
		_snapshots[binding.get_npc_name()] = snapshot
		_log_manager.log_snapshot(snapshot, config)
		_log_manager.maybe_auto_snapshot(binding, snapshot, config)

	_visualizer.apply_mesh_visibility(config)


func _tick_respawn_requests() -> void:
	if not FileAccess.file_exists(_respawn_path):
		return
	var mtime: int = FileAccess.get_modified_time(_respawn_path)
	if mtime == _respawn_mtime:
		return
	_respawn_mtime = mtime
	var file: FileAccess = FileAccess.open(_respawn_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed as Dictionary
	var request_id: int = int(data.get("time_ms", 0))
	if request_id == 0 or request_id == _respawn_last_id:
		return
	_respawn_last_id = request_id
	_respawn_all_npcs()


func _respawn_all_npcs() -> void:
	var nodes: Array = get_tree().get_nodes_in_group(&"npc")
	for node: Node in nodes:
		if node == null:
			continue
		if node.has_method(&"respawn"):
			node.call(&"respawn")


func _tick_pose_report_requests() -> void:
	if not FileAccess.file_exists(_pose_report_path):
		return
	var mtime: int = FileAccess.get_modified_time(_pose_report_path)
	if mtime == _pose_report_mtime:
		return
	_pose_report_mtime = mtime
	var file: FileAccess = FileAccess.open(_pose_report_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed as Dictionary
	var request_id: int = int(data.get("time_ms", 0))
	if request_id == 0 or request_id == _pose_report_last_id:
		return
	_pose_report_last_id = request_id
	var npc_name: String = str(data.get("npc_name", ""))
	_dump_pose_report(npc_name)


func _dump_pose_report(npc_name: String) -> void:
	var target_name: String = npc_name
	if target_name == "":
		target_name = _pick_default_npc_name()
	if target_name == "":
		push_warning("[RagdollDiagnostics] Pose report: no NPC found")
		return
	var binding: SkeletonBinding = _find_binding_by_name(target_name)
	if binding == null:
		push_warning("[RagdollDiagnostics] Pose report: NPC not found: %s" % target_name)
		return
	var report: Dictionary = binding.get_snapshot_data(0, 0)
	report["time_ms"] = Time.get_ticks_msec()
	report["tag"] = "pose_report"
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "J:/proto-game/single-room/logs/ragdoll_pose_report_%s_%s.json" % [target_name, stamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(report, "\t"))
	file.close()
	print("[RagdollDiagnostics] Pose report written: %s" % path)
	if _log_manager != null:
		_log_manager.maybe_cleanup_logs(config)


func _find_binding_by_name(npc_name: String) -> SkeletonBinding:
	var bindings: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	for node: Node in bindings:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding == null:
			continue
		if binding.get_npc_name() == npc_name:
			return binding
	return null


func _pick_default_npc_name() -> String:
	var commanded: String = _get_commanded_npc_name()
	if commanded != "" and commanded != "Self":
		return commanded
	var bindings: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	for node: Node in bindings:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding != null:
			return binding.get_npc_name()
	return ""


func _get_commanded_npc_name() -> String:
	var players: Array = get_tree().get_nodes_in_group(&"player")
	for player: Node in players:
		for child: Node in player.get_children():
			if child == null:
				continue
			if child.has_method(&"is_commanding") and child.has_method(&"get_command_label"):
				var commanding: bool = bool(child.call(&"is_commanding"))
				if commanding:
					return str(child.call(&"get_command_label"))
	return ""


func _compute_snapshot(binding: SkeletonBinding) -> Dictionary:
	var entries: Array = binding.get_debug_part_entries()
	var max_offset: float = 0.0
	var max_offset_part: String = ""
	var max_lin: float = 0.0
	var max_lin_part: String = ""
	var max_ang: float = 0.0
	var max_ang_part: String = ""
	var max_joint_error: float = 0.0
	var max_joint_name: String = ""
	var min_axis_align: float = 1.0
	var axis_low_count: int = 0
	var min_y: float = INF
	var max_y: float = -INF
	var penetrations: int = 0
	var inter_npc_hits: int = 0
	var unmatched_count: int = 0
	var parts_out: Array = []
	var drift: Dictionary = _compute_drift(binding)
	var drift_vec: Vector3 = drift.get("vec", Vector3.ZERO) as Vector3
	var drift_dir: Vector3 = drift.get("dir", Vector3.ZERO) as Vector3
	var drift_dist: float = float(drift.get("dist", 0.0))
	var spawn_pos: Vector3 = drift.get("spawn", Vector3.ZERO) as Vector3
	var pelvis_pos: Vector3 = drift.get("pelvis", Vector3.ZERO) as Vector3
	var force: Dictionary = _compute_force_budget(binding)
	var force_spring: Vector3 = force.get("spring", Vector3.ZERO) as Vector3
	var force_stand: Vector3 = force.get("stand", Vector3.ZERO) as Vector3
	var force_total: Vector3 = force.get("total", Vector3.ZERO) as Vector3
	var force_top_parts: Array = force.get("top_parts", []) as Array
	var force_total_mag: float = force_total.length()
	var force_dir: Vector3 = Vector3.ZERO
	if force_total_mag > 0.0001:
		force_dir = force_total / force_total_mag

	for entry: Dictionary in entries:
		var part: BodyPart = entry["part"] as BodyPart
		var target_pos: Vector3 = entry["target_pos"] as Vector3
		var offset: float = part.global_position.distance_to(target_pos)
		var lin_vel: float = part.linear_velocity.length()
		var ang_vel: float = part.angular_velocity.length()
		var half_height: float = part.get_collision_half_height()
		var part_min_y: float = part.global_position.y - half_height
		var part_max_y: float = part.global_position.y + half_height

		if offset > max_offset:
			max_offset = offset
			max_offset_part = part.part_name
		if lin_vel > max_lin:
			max_lin = lin_vel
			max_lin_part = part.part_name
		if ang_vel > max_ang:
			max_ang = ang_vel
			max_ang_part = part.part_name

		min_y = minf(min_y, part_min_y)
		max_y = maxf(max_y, part_max_y)

		if part_min_y < config.floor_y - config.max_penetration:
			penetrations += 1

		for other: Node in part.get_colliding_bodies():
			if other is BodyPart:
				var other_part: BodyPart = other as BodyPart
				if other_part.ragdoll_owner != part.ragdoll_owner:
					inter_npc_hits += 1

		parts_out.append({
			"part": part,
			"target_pos": target_pos,
			"offset": offset,
			"lin_vel": lin_vel,
			"ang_vel": ang_vel,
			"half_height": half_height,
		})

	var joint_entries: Array = binding.get_debug_joint_entries()
	for j_entry: Dictionary in joint_entries:
		var err: float = float(j_entry.get("error_deg", 0.0))
		if err > max_joint_error:
			max_joint_error = err
			max_joint_name = str(j_entry.get("joint", ""))
		var axis_align: float = float(j_entry.get("axis_align", 1.0))
		min_axis_align = minf(min_axis_align, axis_align)
		if axis_align < config.min_axis_align:
			axis_low_count += 1

	if binding.has_method(&"get_unmatched_bones"):
		var unmatched: PackedStringArray = binding.call(&"get_unmatched_bones") as PackedStringArray
		unmatched_count = unmatched.size()

	var issues: Array[String] = []
	if max_offset > config.max_offset:
		issues.append("offset")
	if max_lin > config.max_linear_velocity:
		issues.append("lin_vel")
	if max_ang > config.max_angular_velocity:
		issues.append("ang_vel")
	if penetrations > 0:
		issues.append("floor_penetration")
	if inter_npc_hits > 0:
		issues.append("inter_npc_collision")
	if max_joint_error > config.max_joint_error_deg:
		issues.append("joint_error")
	if axis_low_count > 0:
		issues.append("joint_axis")
	if unmatched_count > config.max_unmatched_bones:
		issues.append("unmatched_bones")

	if min_y == INF:
		min_y = 0.0
	if max_y == -INF:
		max_y = 0.0

	return {
		"npc": binding.get_npc_name(),
		"max_offset": max_offset,
		"max_offset_part": max_offset_part,
		"max_lin_vel": max_lin,
		"max_lin_part": max_lin_part,
		"max_ang_vel": max_ang,
		"max_ang_part": max_ang_part,
		"max_joint_error": max_joint_error,
		"max_joint_name": max_joint_name,
		"min_axis_align": min_axis_align,
		"axis_low_count": axis_low_count,
		"min_y": min_y,
		"max_y": max_y,
		"penetrations": penetrations,
		"inter_npc_hits": inter_npc_hits,
		"unmatched_bones": unmatched_count,
		"spawn_x": spawn_pos.x,
		"spawn_y": spawn_pos.y,
		"spawn_z": spawn_pos.z,
		"pelvis_x": pelvis_pos.x,
		"pelvis_y": pelvis_pos.y,
		"pelvis_z": pelvis_pos.z,
		"drift_x": drift_vec.x,
		"drift_y": drift_vec.y,
		"drift_z": drift_vec.z,
		"drift_dist": drift_dist,
		"drift_dir_x": drift_dir.x,
		"drift_dir_z": drift_dir.z,
		"force_spring_x": force_spring.x,
		"force_spring_y": force_spring.y,
		"force_spring_z": force_spring.z,
		"force_stand_x": force_stand.x,
		"force_stand_y": force_stand.y,
		"force_stand_z": force_stand.z,
		"force_total_x": force_total.x,
		"force_total_y": force_total.y,
		"force_total_z": force_total.z,
		"force_total_mag": force_total_mag,
		"force_dir_x": force_dir.x,
		"force_dir_z": force_dir.z,
		"force_top_parts": force_top_parts,
		"force_top_parts_count": force_top_parts.size(),
		"issues": issues,
		"parts": parts_out,
	}


func _compute_force_budget(binding: SkeletonBinding) -> Dictionary:
	if binding == null:
		return {"spring": Vector3.ZERO, "stand": Vector3.ZERO, "total": Vector3.ZERO}
	if binding.has_method(&"get_force_budget"):
		var budget: Dictionary = binding.call(&"get_force_budget") as Dictionary
		var spring: Vector3 = budget.get("spring", Vector3.ZERO) as Vector3
		var stand: Vector3 = budget.get("stand", Vector3.ZERO) as Vector3
		var total: Vector3 = budget.get("total", spring + stand) as Vector3
		var top_parts: Array = budget.get("top_parts", []) as Array
		if binding.has_method(&"get_force_top_parts_debug"):
			top_parts = binding.call(&"get_force_top_parts_debug") as Array
		return {"spring": spring, "stand": stand, "total": total, "top_parts": top_parts}
	return {"spring": Vector3.ZERO, "stand": Vector3.ZERO, "total": Vector3.ZERO}


func _compute_drift(binding: SkeletonBinding) -> Dictionary:
	if binding == null:
		return {"spawn": Vector3.ZERO, "pelvis": Vector3.ZERO, "vec": Vector3.ZERO, "dir": Vector3.ZERO, "dist": 0.0}
	var has_spawn: bool = false
	var spawn_pos: Vector3 = Vector3.ZERO
	var spawn_pelvis: Vector3 = Vector3.ZERO
	var pelvis_pos: Vector3 = Vector3.ZERO
	if binding.has_method(&"has_spawn_origin"):
		has_spawn = bool(binding.call(&"has_spawn_origin"))
	if binding.has_method(&"get_spawn_origin"):
		spawn_pos = binding.call(&"get_spawn_origin") as Vector3
	if binding.has_method(&"get_spawn_pelvis_position"):
		spawn_pelvis = binding.call(&"get_spawn_pelvis_position") as Vector3
	if binding.has_method(&"get_current_pelvis_position"):
		pelvis_pos = binding.call(&"get_current_pelvis_position") as Vector3
	if not has_spawn:
		spawn_pos = pelvis_pos
		spawn_pelvis = pelvis_pos
	if spawn_pelvis == Vector3.ZERO:
		spawn_pelvis = spawn_pos
	var drift_vec: Vector3 = pelvis_pos - spawn_pelvis
	var drift_dist: float = drift_vec.length()
	var drift_dir: Vector3 = Vector3.ZERO
	if drift_dist > 0.0001:
		drift_dir = drift_vec / drift_dist
	return {
		"spawn": spawn_pos,
		"pelvis": pelvis_pos,
		"vec": drift_vec,
		"dir": drift_dir,
		"dist": drift_dist,
	}


func _load_overrides() -> Dictionary:
	if not FileAccess.file_exists(_override_path):
		_override_cache = {}
		_override_mtime = 0
		return {}
	var mtime: int = FileAccess.get_modified_time(_override_path)
	if mtime <= 0 or mtime == _override_mtime:
		return _override_cache
	_override_mtime = mtime
	var file: FileAccess = FileAccess.open(_override_path, FileAccess.READ)
	if file == null:
		_override_cache = {}
		return {}
	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_override_cache = {}
		return {}
	var data: Dictionary = parsed as Dictionary
	if data.has("overrides") and data.get("overrides") is Dictionary:
		_override_cache = data.get("overrides") as Dictionary
	else:
		_override_cache = data
	return _override_cache


func _dump_snapshot(reason: String) -> void:
	if config == null:
		return
	var bindings: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	for node: Node in bindings:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding == null:
			continue
		var snapshot: Dictionary = _compute_snapshot(binding)
		_log_manager.dump_for_binding(binding, reason, snapshot, config)


func dump_snapshot(reason: String = "manual") -> void:
	_dump_snapshot(reason)


func _load_config() -> RagdollDebugConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var res: Resource = load(CONFIG_PATH)
		if res is RagdollDebugConfig:
			return res as RagdollDebugConfig
	return RagdollDebugConfig.new()


func _ensure_actions() -> void:
	_ensure_action(&"toggle_ragdoll_debug", KEY_F4)
	_ensure_action(&"toggle_ragdoll_overlay", KEY_F6)
	_ensure_action(&"toggle_ragdoll_meshes", KEY_F7)
	_ensure_action(&"toggle_ragdoll_labels", KEY_F8)
	_ensure_action(&"toggle_ragdoll_offsets", KEY_F9)
	_ensure_action(&"toggle_ragdoll_axes", KEY_F10)
	_ensure_action(&"toggle_ragdoll_telemetry", KEY_F11)
	_ensure_action(&"dump_ragdoll_snapshot", KEY_F12)
	_ensure_action(&"toggle_ragdoll_limits", KEY_K)
	_ensure_action(&"toggle_ragdoll_springs", KEY_O)
	_ensure_action(&"toggle_ragdoll_joint_pd", KEY_J)
	_ensure_action(&"toggle_ragdoll_pelvis_lock", KEY_P)
	_ensure_action(&"toggle_ragdoll_rest_source", KEY_U)
	_ensure_action(&"respawn_npcs", KEY_R)


func _ensure_action(action_name: StringName, keycode: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
