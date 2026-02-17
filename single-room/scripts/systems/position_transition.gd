class_name PositionTransition
extends Node
## Choreographs smooth transitions between sexual positions for one or
## more actors. Instead of a hard-cut from missionary → doggy, this walks
## through intermediate waypoint poses with timing, then starts the new
## ActionPattern when actors are in place.

signal transition_started(from_name: String, to_name: String)
signal waypoint_reached(index: int, pose_name: String)
signal transition_completed(to_name: String)
signal transition_cancelled()

class TransitionWaypoint:
	var pose_name: String = ""
	var hold_time: float = 0.5
	var blend_time: float = 0.4

	static func create(p_pose: String, p_hold: float = 0.5,
			p_blend: float = 0.4) -> TransitionWaypoint:
		var wp: TransitionWaypoint = TransitionWaypoint.new()
		wp.pose_name = p_pose
		wp.hold_time = p_hold
		wp.blend_time = p_blend
		return wp


class TransitionRoute:
	var from_pattern: String = ""
	var to_pattern: String = ""
	var actor_waypoints: Dictionary = {}
	var final_blend_time: float = 0.5
	var stop_motion_during: bool = true

	static func create(p_from: String, p_to: String) -> TransitionRoute:
		var route: TransitionRoute = TransitionRoute.new()
		route.from_pattern = p_from
		route.to_pattern = p_to
		return route


@export_group("Timing")
@export_range(0.1, 3.0) var time_scale: float = 1.0

var _routes: Dictionary = {}
var _actors: Dictionary = {}
var _transitioning: bool = false
var _current_route: TransitionRoute = null
var _waypoint_index: int = -1
var _phase_timer: float = 0.0
var _phase: StringName = &"idle"
var _actors_ready: Dictionary = {}


func register_actor(tag: String, driver: ActionDriver, animator: RagdollAnimator) -> void:
	_actors[tag] = {"driver": driver, "animator": animator}


func unregister_actor(tag: String) -> void:
	_actors.erase(tag)


func add_route(route: TransitionRoute) -> void:
	var key: String = "%s->%s" % [route.from_pattern, route.to_pattern]
	_routes[key] = route


func has_route(from_pattern: String, to_pattern: String) -> bool:
	return _routes.has("%s->%s" % [from_pattern, to_pattern])


func transition(to_pattern: String, from_pattern: String = "") -> bool:
	if _transitioning:
		push_warning("[PositionTransition] Already transitioning.")
		return false
	if from_pattern == "":
		for tag: String in _actors:
			var entry: Dictionary = _actors[tag]
			var driver: ActionDriver = entry["driver"] as ActionDriver
			if driver != null and driver.is_playing():
				from_pattern = driver.get_current_pattern_name()
				break
	if from_pattern == "":
		push_warning("[PositionTransition] No active pattern to transition from.")
		return false
	var key: String = "%s->%s" % [from_pattern, to_pattern]
	if not _routes.has(key):
		_direct_swap(to_pattern)
		return true
	_current_route = _routes[key] as TransitionRoute
	_transitioning = true
	_waypoint_index = -1
	_phase_timer = 0.0
	_actors_ready.clear()
	transition_started.emit(from_pattern, to_pattern)
	if _current_route.stop_motion_during:
		for tag: String in _actors:
			var entry: Dictionary = _actors[tag]
			var driver: ActionDriver = entry["driver"] as ActionDriver
			if driver != null:
				driver.stop(0.3)
	_advance_waypoint()
	set_physics_process(true)
	return true


func cancel() -> void:
	if _transitioning:
		_transitioning = false
		_current_route = null
		set_physics_process(false)
		transition_cancelled.emit()


func is_transitioning() -> bool:
	return _transitioning


func _ready() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _transitioning or _current_route == null:
		return
	_phase_timer += delta * time_scale
	match _phase:
		&"blending":
			_process_blending()
		&"holding":
			_process_holding()
		&"finalizing":
			_process_finalizing()


func _process_blending() -> void:
	var all_ready: bool = true
	for tag: String in _actors:
		if not _actors_ready.get(tag, false):
			var entry: Dictionary = _actors[tag]
			var animator: RagdollAnimator = entry["animator"] as RagdollAnimator
			if animator != null and animator._blend_t >= 1.0:
				_actors_ready[tag] = true
			else:
				all_ready = false
	if all_ready:
		_phase = &"holding"
		_phase_timer = 0.0


func _process_holding() -> void:
	var hold_time: float = _get_current_hold_time()
	if _phase_timer >= hold_time:
		_advance_waypoint()


func _process_finalizing() -> void:
	if _phase_timer >= _current_route.final_blend_time:
		var to_pattern: String = _current_route.to_pattern
		for tag: String in _actors:
			var entry: Dictionary = _actors[tag]
			var driver: ActionDriver = entry["driver"] as ActionDriver
			if driver != null:
				driver.play_pattern_by_name(to_pattern, _current_route.final_blend_time)
		_transitioning = false
		_current_route = null
		set_physics_process(false)
		transition_completed.emit(to_pattern)


func _advance_waypoint() -> void:
	_waypoint_index += 1
	_actors_ready.clear()
	var max_waypoints: int = 0
	for tag: String in _current_route.actor_waypoints:
		var wps: Array = _current_route.actor_waypoints[tag] as Array
		max_waypoints = maxi(max_waypoints, wps.size())
	if _waypoint_index >= max_waypoints:
		_phase = &"finalizing"
		_phase_timer = 0.0
		return
	for tag: String in _actors:
		if not _current_route.actor_waypoints.has(tag):
			_actors_ready[tag] = true
			continue
		var wps: Array = _current_route.actor_waypoints[tag] as Array
		if _waypoint_index >= wps.size():
			_actors_ready[tag] = true
			continue
		var wp: TransitionWaypoint = wps[_waypoint_index] as TransitionWaypoint
		var entry: Dictionary = _actors[tag]
		var animator: RagdollAnimator = entry["animator"] as RagdollAnimator
		if animator != null and wp.pose_name != "":
			animator.set_pose_by_name(wp.pose_name, wp.blend_time)
			_actors_ready[tag] = false
	_phase = &"blending"
	_phase_timer = 0.0
	for tag: String in _current_route.actor_waypoints:
		var wps: Array = _current_route.actor_waypoints[tag] as Array
		if _waypoint_index < wps.size():
			var wp: TransitionWaypoint = wps[_waypoint_index] as TransitionWaypoint
			waypoint_reached.emit(_waypoint_index, wp.pose_name)
			break


func _get_current_hold_time() -> float:
	for tag: String in _current_route.actor_waypoints:
		var wps: Array = _current_route.actor_waypoints[tag] as Array
		if _waypoint_index < wps.size():
			var wp: TransitionWaypoint = wps[_waypoint_index] as TransitionWaypoint
			return wp.hold_time
	return 0.5


func _direct_swap(to_pattern: String) -> void:
	for tag: String in _actors:
		var entry: Dictionary = _actors[tag]
		var driver: ActionDriver = entry["driver"] as ActionDriver
		if driver != null:
			driver.play_pattern_by_name(to_pattern, 0.6)
	transition_completed.emit(to_pattern)
