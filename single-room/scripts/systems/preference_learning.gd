class_name PreferenceLearning
extends Node
## Tracks which ActionPatterns produce the best NPC responses — highest
## arousal gain, highest comfort, fewest distress signals. Builds a
## lightweight preference model the LLM can query for personalization.
##
## Attach as child of NPCPlaceholder (sibling of ActionDriver,
## ArousalSystem, CharacterProfile, NPCMemory).

signal preference_updated(pattern_name: String, score: float)
signal preference_report_ready(report: Dictionary)

@export_group("Sampling")
@export_range(1.0, 15.0) var sample_interval: float = 3.0
@export var max_samples_per_pattern: int = 20
@export_range(0.5, 5.0) var min_active_time: float = 2.0

@export_group("Scoring Weights")
@export_range(0.0, 2.0) var w_arousal_gain: float = 1.0
@export_range(0.0, 2.0) var w_comfort: float = 0.8
@export_range(0.0, 5.0) var w_distress_penalty: float = 2.0
@export_range(0.0, 3.0) var w_orgasm_proximity: float = 1.5

var _driver: ActionDriver = null
var _arousal_sys: ArousalSystem = null
var _profile: CharacterProfile = null
var _memory: NPCMemory = null

var _pattern_data: Dictionary = {}
var _pattern_scores: Dictionary = {}

var _sample_timer: float = 0.0
var _pattern_start_time: float = 0.0
var _arousal_at_pattern_start: float = 0.0
var _current_pattern_name: String = ""
var _initialized: bool = false
var _clock: float = 0.0


func _ready() -> void:
	call_deferred(&"_wire")


func _wire() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child is ActionDriver:
			_driver = child as ActionDriver
		elif child is ArousalSystem:
			_arousal_sys = child as ArousalSystem
		elif child is CharacterProfile:
			_profile = child as CharacterProfile
		elif child is NPCMemory:
			_memory = child as NPCMemory
	if _driver != null:
		_driver.pattern_started.connect(_on_pattern_started)
		_driver.pattern_stopped.connect(_on_pattern_stopped)
	if _arousal_sys != null:
		_arousal_sys.orgasm_started.connect(_on_orgasm)
	_initialized = _driver != null and _arousal_sys != null


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	_clock += delta
	_sample_timer += delta
	if _sample_timer >= sample_interval and _current_pattern_name != "":
		var elapsed: float = _clock - _pattern_start_time
		if elapsed >= min_active_time:
			_take_sample()
			_sample_timer = 0.0


func _on_pattern_started(pattern_name: String) -> void:
	_current_pattern_name = pattern_name
	_pattern_start_time = _clock
	_sample_timer = 0.0
	if _arousal_sys != null:
		_arousal_at_pattern_start = _arousal_sys.arousal_level


func _on_pattern_stopped(_pattern_name: String) -> void:
	if _current_pattern_name != "" and (_clock - _pattern_start_time) >= min_active_time:
		_take_sample()
	_current_pattern_name = ""


func _on_orgasm(_intensity: float) -> void:
	if _current_pattern_name != "":
		_ensure_scores_entry(_current_pattern_name)
		var entry: Dictionary = _pattern_scores[_current_pattern_name]
		entry["total_orgasms"] = (entry["total_orgasms"] as int) + 1
		_pattern_scores[_current_pattern_name] = entry


func get_score(pattern_name: String) -> float:
	if _pattern_scores.has(pattern_name):
		return (_pattern_scores[pattern_name] as Dictionary)["avg_score"] as float
	return -1.0


func get_top_patterns(count: int = 5) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for pname: String in _pattern_scores:
		var entry: Dictionary = _pattern_scores[pname]
		entries.append({"pattern": pname, "score": entry["avg_score"],
			"samples": entry["sample_count"], "orgasms": entry["total_orgasms"]})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["score"] as float) > (b["score"] as float))
	return entries.slice(0, mini(count, entries.size()))


func get_worst_patterns(count: int = 3) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for pname: String in _pattern_scores:
		var entry: Dictionary = _pattern_scores[pname]
		entries.append({"pattern": pname, "score": entry["avg_score"],
			"samples": entry["sample_count"]})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["score"] as float) < (b["score"] as float))
	return entries.slice(0, mini(count, entries.size()))


func get_preference_report() -> Dictionary:
	var report: Dictionary = {
		"top_patterns": get_top_patterns(5),
		"worst_patterns": get_worst_patterns(3),
		"total_patterns_tried": _pattern_scores.size(),
		"total_samples": _get_total_samples(),
	}
	preference_report_ready.emit(report)
	return report


func get_preference_summary() -> String:
	var top: Array[Dictionary] = get_top_patterns(3)
	var worst: Array[Dictionary] = get_worst_patterns(2)
	if top.is_empty():
		return "No preference data yet."
	var lines: Array[String] = ["Preference summary:"]
	lines.append("  Favorites:")
	for entry: Dictionary in top:
		lines.append("    - %s (score: %.1f, %d samples, %d orgasms)" % [
			entry["pattern"], entry["score"],
			entry["samples"], entry.get("orgasms", 0)])
	if not worst.is_empty():
		lines.append("  Least enjoyed:")
		for entry: Dictionary in worst:
			lines.append("    - %s (score: %.1f)" % [entry["pattern"], entry["score"]])
	return "\n".join(lines)


func clear() -> void:
	_pattern_data.clear()
	_pattern_scores.clear()


func _take_sample() -> void:
	if _current_pattern_name == "":
		return
	var arousal_now: float = _arousal_sys.arousal_level if _arousal_sys != null else 0.0
	var arousal_delta: float = arousal_now - _arousal_at_pattern_start
	var comfort: float = 0.5
	if _profile != null:
		comfort = _profile.comfort_level
	var distress_count: int = 0
	if _memory != null:
		var elapsed: float = _clock - _pattern_start_time
		distress_count = _memory.count_recent(&"distress", elapsed)
	var score: float = 0.0
	score += arousal_delta * w_arousal_gain
	score += comfort * w_comfort
	score -= float(distress_count) * w_distress_penalty
	score += arousal_now * w_orgasm_proximity
	var sample: Dictionary = {
		"arousal_delta": arousal_delta, "comfort": comfort,
		"distress_count": distress_count, "arousal_peak": arousal_now,
		"score": score, "time": _clock,
	}
	if not _pattern_data.has(_current_pattern_name):
		_pattern_data[_current_pattern_name] = [] as Array[Dictionary]
	var samples: Array = _pattern_data[_current_pattern_name] as Array
	samples.append(sample)
	if samples.size() > max_samples_per_pattern:
		samples.remove_at(0)
	_pattern_data[_current_pattern_name] = samples
	_recompute_aggregate(_current_pattern_name)
	preference_updated.emit(_current_pattern_name, score)
	_arousal_at_pattern_start = arousal_now


func _recompute_aggregate(pattern_name: String) -> void:
	_ensure_scores_entry(pattern_name)
	var samples: Array = _pattern_data.get(pattern_name, []) as Array
	if samples.is_empty():
		return
	var total: float = 0.0
	var best: float = -999.0
	var worst: float = 999.0
	for s: Variant in samples:
		var sd: Dictionary = s as Dictionary
		var sc: float = sd["score"] as float
		total += sc
		best = maxf(best, sc)
		worst = minf(worst, sc)
	var avg: float = total / float(samples.size())
	var entry: Dictionary = _pattern_scores[pattern_name]
	entry["avg_score"] = avg
	entry["sample_count"] = samples.size()
	entry["best_score"] = best
	entry["worst_score"] = worst
	_pattern_scores[pattern_name] = entry


func _ensure_scores_entry(pattern_name: String) -> void:
	if not _pattern_scores.has(pattern_name):
		_pattern_scores[pattern_name] = {
			"avg_score": 0.0, "sample_count": 0,
			"best_score": 0.0, "worst_score": 0.0,
			"total_orgasms": 0,
		}


func _get_total_samples() -> int:
	var total: int = 0
	for pname: String in _pattern_data:
		total += (_pattern_data[pname] as Array).size()
	return total
