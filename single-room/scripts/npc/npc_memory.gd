class_name NPCMemory
extends Node
## Short-term event memory for an NPC.
## Stores a ring buffer of recent events with timestamps so the brain
## can make context-aware decisions (e.g., "grabbed twice in 5 seconds →
## annoyed" vs. "first grab in a while → surprised").
##
## Each event is a Dictionary:
##   { "type": StringName, "part": String, "intensity": float,
##     "source": Node3D, "time": float, "data": Variant }

signal event_recorded(event: Dictionary)

@export_group("Capacity")
## Maximum number of events stored before oldest are discarded.
@export var max_events: int = 64
## Events older than this (seconds) are considered "forgotten" by queries.
@export var relevance_window: float = 30.0

# ── State ────────────────────────────────────────────────────────────────────
## Ring buffer of event dictionaries.
var _events: Array[Dictionary] = []
## Running game-time clock (seconds since NPC spawned).
var _clock: float = 0.0


func _physics_process(delta: float) -> void:
	_clock += delta


# ── Public API ───────────────────────────────────────────────────────────────

## Record a new event.
func record(event_type: StringName, part: String = "",
		intensity: float = 1.0, source: Node3D = null,
		data: Variant = null) -> void:
	var entry: Dictionary = {
		"type": event_type,
		"part": part,
		"intensity": intensity,
		"source": source,
		"time": _clock,
		"data": data,
	}
	_events.append(entry)
	if _events.size() > max_events:
		_events.remove_at(0)
	event_recorded.emit(entry)


## Count events of a given type within the last `window` seconds.
func count_recent(event_type: StringName, window: float = -1.0) -> int:
	var cutoff: float = _clock - (window if window > 0.0 else relevance_window)
	var total: int = 0
	for i: int in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		var ev_time: float = ev["time"] as float
		if ev_time < cutoff:
			break
		if ev["type"] == event_type:
			total += 1
	return total


## Get the most recent event of a given type (or null if none).
func get_last(event_type: StringName) -> Variant:
	for i: int in range(_events.size() - 1, -1, -1):
		if _events[i]["type"] == event_type:
			return _events[i]
	return null


## Seconds since the last event of this type (or INF if never).
func time_since(event_type: StringName) -> float:
	var last: Variant = get_last(event_type)
	if last == null:
		return INF
	return _clock - (last as Dictionary)["time"] as float


## Get all events within the last `window` seconds, newest first.
func get_recent(window: float = -1.0) -> Array[Dictionary]:
	var cutoff: float = _clock - (window if window > 0.0 else relevance_window)
	var result: Array[Dictionary] = []
	for i: int in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		var ev_time: float = ev["time"] as float
		if ev_time < cutoff:
			break
		result.append(ev)
	return result


## Get all events of a specific type within window, newest first.
func get_recent_of_type(event_type: StringName, window: float = -1.0) -> Array[Dictionary]:
	var cutoff: float = _clock - (window if window > 0.0 else relevance_window)
	var result: Array[Dictionary] = []
	for i: int in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		var ev_time: float = ev["time"] as float
		if ev_time < cutoff:
			break
		if ev["type"] == event_type:
			result.append(ev)
	return result


## Wipe all stored events.
func clear() -> void:
	_events.clear()


## Current internal clock value (seconds since spawn).
func get_clock() -> float:
	return _clock
