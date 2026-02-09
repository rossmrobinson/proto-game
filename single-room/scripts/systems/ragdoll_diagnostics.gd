extends Node

const CONFIG_PATH: String = "res://config/ragdoll-debug-config.tres"

var config: RagdollDebugConfig = null

var _snapshots: Dictionary = {}
var _sample_timer: float = 0.0
var _label_timer: float = 0.0

var _line_mesh: ImmediateMesh = null
var _line_instance: MeshInstance3D = null
var _line_material: StandardMaterial3D = null

var _labels: Dictionary = {}
var _log_files: Dictionary = {}
var _log_counts: Dictionary = {}


func _ready() -> void:
	config = _load_config()
	_ensure_actions()
	_setup_line_mesh()
	_set_debug_mesh_visibility(config.enabled and config.show_debug_meshes)
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_ragdoll_debug"):
		config.enabled = not config.enabled
		_clear_debug_lines()
		_update_all_labels()
		_set_debug_mesh_visibility(config.enabled and config.show_debug_meshes)
		return
	if event.is_action_pressed(&"toggle_ragdoll_overlay"):
		config.show_overlay = not config.show_overlay
		return
	if event.is_action_pressed(&"toggle_ragdoll_meshes"):
		config.show_debug_meshes = not config.show_debug_meshes
		_apply_debug_mesh_visibility()
		return
	if event.is_action_pressed(&"toggle_ragdoll_labels"):
		config.show_part_labels = not config.show_part_labels
		_update_all_labels()
		return
	if event.is_action_pressed(&"toggle_ragdoll_offsets"):
		config.show_offset_lines = not config.show_offset_lines
		_clear_debug_lines()
		return
	if event.is_action_pressed(&"toggle_ragdoll_axes"):
		config.show_joint_axes = not config.show_joint_axes
		_clear_debug_lines()
		return
	if event.is_action_pressed(&"toggle_ragdoll_telemetry"):
		config.log_to_file = not config.log_to_file
		return


func _physics_process(delta: float) -> void:
	if config == null or not config.enabled:
		return

	_sample_timer += delta
	if _sample_timer >= config.sample_interval:
		_sample_timer = 0.0
		_sample_ragdolls()

	_label_timer += delta
	if _label_timer >= config.label_update_interval:
		_label_timer = 0.0
		_update_all_labels()


func _process(_delta: float) -> void:
	if config == null or not config.enabled:
		return
	if not config.show_offset_lines and not config.show_joint_axes:
		return
	_update_debug_lines()


func register_binding(binding: SkeletonBinding) -> void:
	if binding == null:
		return
	var npc_name: String = binding.get_npc_name()
	if npc_name == "":
		return
	if not _log_counts.has(npc_name):
		_log_counts[npc_name] = 0


func report_event(binding: SkeletonBinding, tag: String) -> void:
	if binding == null or config == null or not config.enabled:
		return
	var snapshot: Dictionary = _compute_snapshot(binding)
	snapshot["tag"] = tag
	_snapshots[binding.get_npc_name()] = snapshot
	_log_snapshot(snapshot)


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
		lines.append("%s: off=%.3f v=%.2f w=%.2f pen=%d%s" % [
			npc_name,
			float(snap.get("max_offset", 0.0)),
			float(snap.get("max_lin_vel", 0.0)),
			float(snap.get("max_ang_vel", 0.0)),
			int(snap.get("penetrations", 0)) + int(snap.get("inter_npc_hits", 0)),
			issue_flag,
		])

	return "\n".join(lines)


func get_all_snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc_name: String in _snapshots:
		out.append(_snapshots[npc_name] as Dictionary)
	return out


func _sample_ragdolls() -> void:
	var bindings: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	for node: Node in bindings:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding == null:
			continue
		var snapshot: Dictionary = _compute_snapshot(binding)
		_snapshots[binding.get_npc_name()] = snapshot
		_log_snapshot(snapshot)

	_apply_debug_mesh_visibility()


func _compute_snapshot(binding: SkeletonBinding) -> Dictionary:
	var entries: Array = binding.get_debug_part_entries()
	var max_offset: float = 0.0
	var max_offset_part: String = ""
	var max_lin: float = 0.0
	var max_lin_part: String = ""
	var max_ang: float = 0.0
	var max_ang_part: String = ""
	var min_y: float = INF
	var max_y: float = -INF
	var penetrations: int = 0
	var inter_npc_hits: int = 0
	var parts_out: Array = []

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
		"min_y": min_y,
		"max_y": max_y,
		"penetrations": penetrations,
		"inter_npc_hits": inter_npc_hits,
		"issues": issues,
		"parts": parts_out,
	}


func _apply_debug_mesh_visibility() -> void:
	if config == null:
		return
	var parts: Array = get_tree().get_nodes_in_group(&"body_part")
	for node: Node in parts:
		var part: BodyPart = node as BodyPart
		if part == null:
			continue
		part.set_debug_mesh_visible(config.show_debug_meshes)


func _set_debug_mesh_visibility(visible: bool) -> void:
	var parts: Array = get_tree().get_nodes_in_group(&"body_part")
	for node: Node in parts:
		var part: BodyPart = node as BodyPart
		if part == null:
			continue
		part.set_debug_mesh_visible(visible)


func _setup_line_mesh() -> void:
	_line_mesh = ImmediateMesh.new()
	_line_instance = MeshInstance3D.new()
	_line_instance.name = "RagdollDebugLines"
	_line_instance.mesh = _line_mesh
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_instance.material_override = _line_material
	add_child(_line_instance)


func _clear_debug_lines() -> void:
	if _line_mesh != null:
		_line_mesh.clear_surfaces()


func _update_debug_lines() -> void:
	if _line_mesh == null:
		return

	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	if config.show_offset_lines:
		var color_ok: Color = Color(0.2, 0.8, 1.0, 0.9)
		var color_bad: Color = Color(1.0, 0.3, 0.2, 0.9)
		for npc_name: String in _snapshots:
			var snap: Dictionary = _snapshots[npc_name] as Dictionary
			var parts: Array = snap.get("parts", []) as Array
			for entry: Dictionary in parts:
				var part: BodyPart = entry["part"] as BodyPart
				var target_pos: Vector3 = entry["target_pos"] as Vector3
				var offset: float = float(entry["offset"])
				var color: Color = color_bad if offset > config.max_offset else color_ok
				_line_mesh.surface_set_color(color)
				_line_mesh.surface_add_vertex(target_pos)
				_line_mesh.surface_set_color(color)
				_line_mesh.surface_add_vertex(part.global_position)

	if config.show_joint_axes:
		var axis_len: float = config.axis_length
		var axes_drawn: int = 0
		var joints: Array = get_tree().get_nodes_in_group(&"ragdoll_joint")
		for node: Node in joints:
			if axes_drawn >= config.max_joint_axes:
				break
			var joint: Generic6DOFJoint3D = node as Generic6DOFJoint3D
			if joint == null:
				continue
			var origin: Vector3 = joint.global_transform.origin
			var basis: Basis = joint.global_transform.basis
			_line_mesh.surface_set_color(Color(1.0, 0.2, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(1.0, 0.2, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.x * axis_len)

			_line_mesh.surface_set_color(Color(0.2, 1.0, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(0.2, 1.0, 0.2, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.y * axis_len)

			_line_mesh.surface_set_color(Color(0.2, 0.4, 1.0, 0.9))
			_line_mesh.surface_add_vertex(origin)
			_line_mesh.surface_set_color(Color(0.2, 0.4, 1.0, 0.9))
			_line_mesh.surface_add_vertex(origin + basis.z * axis_len)

			axes_drawn += 1

	_line_mesh.surface_end()


func _update_all_labels() -> void:
	if config == null:
		return
	if not config.show_part_labels:
		for label_key: int in _labels:
			var label: Label3D = _labels[label_key] as Label3D
			if label != null:
				label.visible = false
		return

	for npc_name: String in _snapshots:
		var snap: Dictionary = _snapshots[npc_name] as Dictionary
		var parts: Array = snap.get("parts", []) as Array
		for entry: Dictionary in parts:
			var part: BodyPart = entry["part"] as BodyPart
			var offset: float = float(entry["offset"])
			var lin_vel: float = float(entry["lin_vel"])
			var ang_vel: float = float(entry["ang_vel"])
			var half_height: float = float(entry["half_height"])
			var label: Label3D = _get_or_create_label(part)
			label.text = "%s off=%.3f v=%.2f w=%.2f" % [
				part.part_name, offset, lin_vel, ang_vel]
			label.position = Vector3(0.0, half_height + 0.05, 0.0)
			label.visible = true


func _get_or_create_label(part: BodyPart) -> Label3D:
	var key: int = part.get_instance_id()
	if _labels.has(key):
		return _labels[key] as Label3D

	var label: Label3D = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	part.add_child(label)
	_labels[key] = label
	return label


func _log_snapshot(snapshot: Dictionary) -> void:
	if config == null or not config.log_to_file:
		return
	var npc_name: String = snapshot.get("npc", "")
	if npc_name == "":
		return

	var count: int = int(_log_counts.get(npc_name, 0))
	if count >= config.log_frames:
		return

	var log_file: FileAccess = _get_log_file(npc_name)
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
		"min_y": snapshot.get("min_y", 0.0),
		"max_y": snapshot.get("max_y", 0.0),
		"penetrations": snapshot.get("penetrations", 0),
		"inter_npc_hits": snapshot.get("inter_npc_hits", 0),
		"issues": snapshot.get("issues", []),
	}
	log_file.store_line(JSON.stringify(payload))
	_log_counts[npc_name] = count + 1


func _get_log_file(npc_name: String) -> FileAccess:
	if _log_files.has(npc_name):
		return _log_files[npc_name] as FileAccess

	DirAccess.make_dir_recursive_absolute(config.log_dir)

	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var file_path: String = "%s/ragdoll_%s_%s.jsonl" % [config.log_dir, npc_name, timestamp]
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("[RagdollDiagnostics] Cannot open log file: %s" % file_path)
		return null

	_log_files[npc_name] = file
	return file


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


func _ensure_action(name: StringName, keycode: Key) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(name, ev)
