class_name RagdollScenarioRunner
extends Node

@export var test_duration: float = 5.0
@export var settle_time: float = 0.5
@export var auto_quit: bool = false

var _elapsed: float = 0.0
var _reported: bool = false
var _diag: Node = null
var _issues: PackedStringArray = []


func _ready() -> void:
	_diag = get_tree().root.get_node_or_null(^"RagdollDiagnostics")
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < settle_time:
		return

	if _diag != null and _diag.has_method(&"get_all_snapshots"):
		_collect_issues(_diag.call(&"get_all_snapshots") as Array)

	if _elapsed >= test_duration and not _reported:
		_report()
		_reported = true
		if auto_quit:
			get_tree().quit()


func _collect_issues(snapshots: Array) -> void:
	for item: Variant in snapshots:
		if not (item is Dictionary):
			continue
		var snap: Dictionary = item as Dictionary
		var issues: Array = snap.get("issues", []) as Array
		if issues.is_empty():
			continue
		var npc_name: String = snap.get("npc", "?")
		var summary: String = "%s: %s" % [npc_name, ", ".join(issues)]
		if not _issues.has(summary):
			_issues.append(summary)


func _report() -> void:
	var status: String = "PASS" if _issues.is_empty() else "FAIL"
	print("[RagdollScenarioRunner] %s after %.2fs" % [status, _elapsed])
	if not _issues.is_empty():
		for issue: String in _issues:
			push_warning("[RagdollScenarioRunner] %s" % issue)
	_write_report(status)


func _write_report(status: String) -> void:
	var log_dir: String = "J:/proto-game/single-room/logs"
	if _diag != null and _diag.has_method(&"config"):
		var cfg: Object = _diag.get("config")
		if cfg != null and cfg.has_method(&"get"):
			log_dir = str(cfg.get("log_dir"))
	_ensure_log_dir(log_dir)
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "%s/ragdoll_scenario_report_%s.json" % [log_dir, timestamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[RagdollScenarioRunner] Cannot write report: %s" % path)
		return
	var payload: Dictionary = {
		"status": status,
		"elapsed": _elapsed,
		"issues": _issues,
	}
	file.store_line(JSON.stringify(payload))


func _ensure_log_dir(log_dir: String) -> void:
	if log_dir.begins_with("user://"):
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			push_warning("[RagdollScenarioRunner] Cannot open user:// for log dir")
			return
		var rel: String = log_dir.trim_prefix("user://")
		if rel == "":
			return
		dir.make_dir_recursive(rel)
		return
	DirAccess.make_dir_recursive_absolute(log_dir)
