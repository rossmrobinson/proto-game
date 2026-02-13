class_name RagdollParameterSweep
extends Node

@export var enabled: bool = true
@export var run_on_start: bool = false
@export var apply_best: bool = true
@export var rounds: int = 2
@export var start_delay: float = 0.5
@export var settle_time: float = 0.7
@export var sample_time: float = 0.4
@export var step_delay: float = 0.4
@export var cooldown_time: float = 0.2
@export var target_score: float = 8.0
@export var max_trials: int = 120
@export var report_path: String = "J:/proto-game/single-room/logs/ragdoll_sweep_report.jsonl"
@export var target_npc_names: PackedStringArray = []
@export var print_each_trial: bool = true

@export_group("Sweep Mode")
## When true, sweep a stability-focused subset (sleep thresholds + damping).
@export var focused_stability_sweep: bool = true

@export var trigger_action: StringName = &"run_ragdoll_sweep"
@export var trigger_key: Key = KEY_F2

@export var spring_values: PackedFloat32Array = [250.0, 350.0, 450.0, 550.0]
@export var angular_values: PackedFloat32Array = [40.0, 60.0, 80.0, 100.0]
@export var spring_damping_values: PackedFloat32Array = [32.0, 40.0, 48.0, 56.0]
@export var angular_damping_values: PackedFloat32Array = [10.0, 12.0, 14.0, 16.0]
@export var passive_damp_multiplier_values: PackedFloat32Array = [2.0, 2.5, 3.0, 3.5]
@export var recover_linear_threshold_values: PackedFloat32Array = [0.2, 0.3, 0.4]
@export var recover_angular_threshold_values: PackedFloat32Array = [1.0, 1.5, 2.0]
@export var passive_motor_floor_values: PackedFloat32Array = [0.2, 0.3, 0.4]
@export var passive_limb_scale_values: PackedFloat32Array = [0.25, 0.35, 0.45]
@export var passive_joint_scale_values: PackedFloat32Array = [0.0, 0.1, 0.2]
@export var stand_up_force_values: PackedFloat32Array = [12.0, 18.0, 24.0]
@export var stand_up_torque_values: PackedFloat32Array = [10.0, 14.0, 18.0]

var _diag: Node = null
var _floor_y: float = 0.0
var _max_penetration: float = 0.01
var _bindings: Array = []
var _running: bool = false
var _report_file: FileAccess = null


func _ready() -> void:
	if not enabled:
		return
	_ensure_action()
	_diag = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	if _diag != null and _diag.has_method(&"get"):
		var cfg: Object = _diag.get("config")
		if cfg != null and cfg.has_method(&"get"):
			_floor_y = float(cfg.get("floor_y"))
			_max_penetration = float(cfg.get("max_penetration"))
	if run_on_start:
		call_deferred(&"_start")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed(trigger_action):
		call_deferred(&"_start")


func _start() -> void:
	if _running:
		return
	_running = true
	await get_tree().create_timer(start_delay).timeout
	_bindings = _get_bindings()
	if _bindings.is_empty():
		push_warning("[RagdollSweep] No bindings found")
		_running = false
		return
	_report_file = _open_report()
	var base: Dictionary = _capture_params(_bindings[0] as SkeletonBinding)
	var current: Dictionary = base.duplicate(true)
	var best: Dictionary = current.duplicate(true)
	var best_score: float = INF
	var trials: int = 0

	for round_idx: int in range(rounds):
		for param_name: String in _param_order():
			var values: PackedFloat32Array = _get_values(param_name)
			if values.is_empty():
				continue
			var local_best_score: float = INF
			var local_best_val: float = float(current.get(param_name, 0.0))
			for val: float in values:
				current[param_name] = val
				_apply_params(_bindings, current)
				if print_each_trial:
					print("[RagdollSweep] %s=%.3f" % [param_name, val])
				if step_delay > 0.0:
					await get_tree().create_timer(step_delay).timeout
				await _settle_and_sample()
				var score: float = _score_all(_bindings)
				_write_report(round_idx, trials, current, score)
				trials += 1
				if score < local_best_score:
					local_best_score = score
					local_best_val = val
				if score < best_score:
					best_score = score
					best = current.duplicate(true)
				if trials >= max_trials or best_score <= target_score:
					break
				await get_tree().create_timer(cooldown_time).timeout
			if trials >= max_trials or best_score <= target_score:
				break
			current[param_name] = local_best_val
			_apply_params(_bindings, current)
		if trials >= max_trials or best_score <= target_score:
			break

	if apply_best:
		_apply_params(_bindings, best)
	else:
		_apply_params(_bindings, base)
	_close_report()
	print("[RagdollSweep] Done. best_score=%.3f" % best_score)
	_running = false


func _get_bindings() -> Array:
	var out: Array = []
	var nodes: Array = get_tree().get_nodes_in_group(&"ragdoll_binding")
	for node: Node in nodes:
		var binding: SkeletonBinding = node as SkeletonBinding
		if binding == null:
			continue
		if not target_npc_names.is_empty() and not target_npc_names.has(binding.get_npc_name()):
			continue
		out.append(binding)
	return out


func _capture_params(binding: SkeletonBinding) -> Dictionary:
	return {
		"spring_stiffness": binding.spring_stiffness,
		"spring_damping": binding.spring_damping,
		"angular_stiffness": binding.angular_stiffness,
		"angular_damping": binding.angular_damping,
		"passive_damp_multiplier": binding.passive_damp_multiplier,
		"recover_linear_threshold": binding.recover_linear_threshold,
		"recover_angular_threshold": binding.recover_angular_threshold,
		"passive_motor_floor": binding.passive_motor_floor,
		"passive_limb_scale": binding.passive_limb_scale,
		"passive_joint_scale": binding.passive_joint_scale,
		"stand_up_force": binding.stand_up_force,
		"stand_up_torque": binding.stand_up_torque,
	}


func _apply_params(bindings: Array, params: Dictionary) -> void:
	for node: SkeletonBinding in bindings:
		node.spring_stiffness = float(params.get("spring_stiffness", node.spring_stiffness))
		node.spring_damping = float(params.get("spring_damping", node.spring_damping))
		node.angular_stiffness = float(params.get("angular_stiffness", node.angular_stiffness))
		node.angular_damping = float(params.get("angular_damping", node.angular_damping))
		node.passive_damp_multiplier = float(params.get("passive_damp_multiplier", node.passive_damp_multiplier))
		node.recover_linear_threshold = float(params.get("recover_linear_threshold", node.recover_linear_threshold))
		node.recover_angular_threshold = float(params.get("recover_angular_threshold", node.recover_angular_threshold))
		node.passive_motor_floor = float(params.get("passive_motor_floor", node.passive_motor_floor))
		node.passive_limb_scale = float(params.get("passive_limb_scale", node.passive_limb_scale))
		node.passive_joint_scale = float(params.get("passive_joint_scale", node.passive_joint_scale))
		node.stand_up_force = float(params.get("stand_up_force", node.stand_up_force))
		node.stand_up_torque = float(params.get("stand_up_torque", node.stand_up_torque))


func _settle_and_sample() -> void:
	await get_tree().create_timer(settle_time).timeout
	await get_tree().create_timer(sample_time).timeout


func _score_all(bindings: Array) -> float:
	var total: float = 0.0
	for node: SkeletonBinding in bindings:
		var stats: Dictionary = _measure_binding(node)
		var score: float = 0.0
		score += float(stats.get("max_offset", 0.0)) * 10.0
		score += float(stats.get("max_joint_error", 0.0)) * 0.2
		score += float(stats.get("max_lin_vel", 0.0)) * 0.5
		score += float(stats.get("max_ang_vel", 0.0)) * 0.2
		score += float(stats.get("penetrations", 0)) * 5.0
		score += (1.0 - float(stats.get("min_axis_align", 1.0))) * 5.0
		total += score
	return total / max(1, bindings.size())


func _measure_binding(binding: SkeletonBinding) -> Dictionary:
	var entries: Array = binding.get_debug_part_entries()
	var max_offset: float = 0.0
	var max_lin: float = 0.0
	var max_ang: float = 0.0
	var penetrations: int = 0
	for entry: Dictionary in entries:
		var part: BodyPart = entry["part"] as BodyPart
		var target_pos: Vector3 = entry["target_pos"] as Vector3
		var offset: float = part.global_position.distance_to(target_pos)
		max_offset = maxf(max_offset, offset)
		max_lin = maxf(max_lin, part.linear_velocity.length())
		max_ang = maxf(max_ang, part.angular_velocity.length())
		var half_height: float = part.get_collision_half_height()
		if (part.global_position.y - half_height) < _floor_y - _max_penetration:
			penetrations += 1

	var joints: Array = binding.get_debug_joint_entries()
	var max_joint_error: float = 0.0
	var min_axis_align: float = 1.0
	for j_entry: Dictionary in joints:
		var err: float = float(j_entry.get("error_deg", 0.0))
		max_joint_error = maxf(max_joint_error, err)
		var axis_align: float = float(j_entry.get("axis_align", 1.0))
		min_axis_align = minf(min_axis_align, axis_align)

	return {
		"max_offset": max_offset,
		"max_lin_vel": max_lin,
		"max_ang_vel": max_ang,
		"max_joint_error": max_joint_error,
		"min_axis_align": min_axis_align,
		"penetrations": penetrations,
	}


func _param_order() -> PackedStringArray:
	if focused_stability_sweep:
		return [
			"spring_damping",
			"angular_damping",
			"passive_damp_multiplier",
			"recover_linear_threshold",
			"recover_angular_threshold",
			"passive_motor_floor",
			"passive_limb_scale",
			"passive_joint_scale",
		]
	return [
		"spring_stiffness",
		"spring_damping",
		"angular_stiffness",
		"angular_damping",
		"passive_damp_multiplier",
		"recover_linear_threshold",
		"recover_angular_threshold",
		"passive_motor_floor",
		"passive_limb_scale",
		"passive_joint_scale",
		"stand_up_force",
		"stand_up_torque",
	]


func _get_values(param_name: String) -> PackedFloat32Array:
	match param_name:
		"spring_stiffness":
			return spring_values
		"spring_damping":
			return spring_damping_values
		"angular_stiffness":
			return angular_values
		"angular_damping":
			return angular_damping_values
		"passive_damp_multiplier":
			return passive_damp_multiplier_values
		"recover_linear_threshold":
			return recover_linear_threshold_values
		"recover_angular_threshold":
			return recover_angular_threshold_values
		"passive_motor_floor":
			return passive_motor_floor_values
		"passive_limb_scale":
			return passive_limb_scale_values
		"passive_joint_scale":
			return passive_joint_scale_values
		"stand_up_force":
			return stand_up_force_values
		"stand_up_torque":
			return stand_up_torque_values
		_:
			return []


func _open_report() -> FileAccess:
	_ensure_report_dir(report_path)
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_warning("[RagdollSweep] Cannot open report: %s" % report_path)
		return null
	return file


func _write_report(round_idx: int, trial_idx: int, params: Dictionary, score: float) -> void:
	if _report_file == null:
		return
	var payload: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"round": round_idx,
		"trial": trial_idx,
		"params": params,
		"score": score,
	}
	_report_file.store_line(JSON.stringify(payload))


func _close_report() -> void:
	if _report_file != null:
		_report_file.close()
		_report_file = null


func _ensure_report_dir(path: String) -> void:
	if path.begins_with("user://"):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			return
		var rel: String = path.trim_prefix("user://")
		rel = rel.get_base_dir()
		if rel != "":
			dir.make_dir_recursive(rel)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())


func _ensure_action() -> void:
	if InputMap.has_action(trigger_action):
		return
	InputMap.add_action(trigger_action)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = trigger_key
	InputMap.action_add_event(trigger_action, ev)
