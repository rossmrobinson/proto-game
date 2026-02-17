class_name PhaseSync
extends Node
## Synchronizes two or more ActionDrivers so their motions relate to each
## other — counter-phase, in-phase, staggered, etc.
##
## One actor is the LEADER; all others follow with configurable phase
## offsets and role behaviors.

signal sync_established(leader_name: String, follower_count: int)
signal sync_broken()

enum SyncRole {
	LEADER,
	COUNTER,
	IN_PHASE,
	STAGGERED,
}

@export_group("Sync Behavior")
@export_range(1.0, 30.0) var sync_stiffness: float = 8.0
@export_range(0.01, 0.5) var max_correction_per_tick: float = 0.15
@export var mirror_speed: bool = true
@export var mirror_amplitude: bool = false

var _actors: Array[Dictionary] = []
var _leader: ActionDriver = null
var _active: bool = false


func add_actor(driver: ActionDriver, role: SyncRole = SyncRole.COUNTER,
		offset: float = 0.5, actor_name: String = "") -> void:
	if driver == null:
		push_warning("[PhaseSync] Null driver passed to add_actor.")
		return
	for a: Dictionary in _actors:
		if a["driver"] == driver:
			push_warning("[PhaseSync] Driver already registered: %s" % actor_name)
			return
	var entry: Dictionary = {
		"driver": driver,
		"role": role,
		"offset": _resolve_offset(role, offset),
		"name": actor_name if actor_name != "" else "Actor_%d" % _actors.size(),
	}
	_actors.append(entry)
	if role == SyncRole.LEADER:
		_leader = driver
	_check_activation()


func remove_actor(driver: ActionDriver) -> void:
	for i: int in range(_actors.size() - 1, -1, -1):
		if _actors[i]["driver"] == driver:
			if _actors[i]["role"] == SyncRole.LEADER:
				_leader = null
			_actors.remove_at(i)
	_check_activation()


func clear() -> void:
	_actors.clear()
	_leader = null
	_active = false
	set_physics_process(false)
	sync_broken.emit()


func get_leader() -> ActionDriver:
	return _leader


func set_actor_offset(driver: ActionDriver, new_offset: float) -> void:
	for a: Dictionary in _actors:
		if a["driver"] == driver:
			a["offset"] = fmod(new_offset, 1.0)
			return


func set_actor_role(driver: ActionDriver, new_role: SyncRole,
		new_offset: float = -1.0) -> void:
	for a: Dictionary in _actors:
		if a["driver"] == driver:
			a["role"] = new_role
			if new_offset >= 0.0:
				a["offset"] = fmod(new_offset, 1.0)
			else:
				a["offset"] = _resolve_offset(new_role, a["offset"])
			if new_role == SyncRole.LEADER:
				_leader = driver
			return


func _physics_process(delta: float) -> void:
	if not _active or _leader == null:
		return
	if not _leader.is_playing():
		return
	var leader_phase: float = _leader._phase
	for actor: Dictionary in _actors:
		var driver: ActionDriver = actor["driver"] as ActionDriver
		if driver == null or driver == _leader:
			continue
		if not driver.is_playing():
			continue
		var role: int = actor["role"] as int
		if role == SyncRole.LEADER:
			continue
		var target_phase: float = fmod(leader_phase + actor["offset"], 1.0)
		_nudge_phase(driver, target_phase, delta)
		if mirror_speed:
			driver.speed_scale = _leader.speed_scale
		if mirror_amplitude:
			driver.amplitude_scale = _leader.amplitude_scale


func _nudge_phase(driver: ActionDriver, target: float, delta: float) -> void:
	var current: float = driver._phase
	var diff: float = target - current
	if diff > 0.5:
		diff -= 1.0
	elif diff < -0.5:
		diff += 1.0
	var correction: float = diff * sync_stiffness * delta
	correction = clampf(correction, -max_correction_per_tick, max_correction_per_tick)
	driver._phase = fmod(current + correction + 1.0, 1.0)


func _resolve_offset(role: SyncRole, provided: float) -> float:
	match role:
		SyncRole.LEADER:
			return 0.0
		SyncRole.COUNTER:
			return 0.5
		SyncRole.IN_PHASE:
			return 0.0
		SyncRole.STAGGERED:
			return fmod(provided, 1.0)
	return 0.0


func _check_activation() -> void:
	var has_leader: bool = _leader != null
	var has_followers: bool = false
	for a: Dictionary in _actors:
		if a["driver"] != _leader:
			has_followers = true
			break
	if has_leader and has_followers:
		if not _active:
			_active = true
			set_physics_process(true)
			var follower_count: int = _actors.size() - 1
			var leader_name: String = ""
			for a: Dictionary in _actors:
				if a["driver"] == _leader:
					leader_name = a["name"]
					break
			sync_established.emit(leader_name, follower_count)
	else:
		if _active:
			_active = false
			set_physics_process(false)
			sync_broken.emit()
