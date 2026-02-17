class_name ActionDriver
extends Node
## Evaluates ActionPattern (motion + tempo) each physics tick and feeds
## additive joint offsets into RagdollAnimator.
##
## This is the runtime engine that makes motions MOVE. It:
##   1. Advances a phase clock based on the tempo's cycles/sec
##   2. Evaluates the motion's oscillation channels at that phase
##   3. Scales offsets by depth, force, and any jitter
##   4. Pushes the result into RagdollAnimator.apply_offset_layer()
##
## Attach as a child of NPCPlaceholder (sibling of RagdollAnimator).

signal pattern_started(pattern_name: String)
signal pattern_stopped(pattern_name: String)
signal pattern_escalated(from_name: String, to_name: String)
signal cycle_completed(cycle_count: int)

@export var ragdoll_animator: RagdollAnimator
@export var auto_detect_animator: bool = true
@export_range(0.0, 2.0) var amplitude_scale: float = 1.0
@export_range(0.1, 5.0) var speed_scale: float = 1.0

var _pattern: ActionPattern = null
var _phase: float = 0.0
var _elapsed: float = 0.0
var _cycle_count: int = 0
var _paused: bool = false
var _current_depth: float = 0.5
var _current_force: float = 0.5
var _stroke_depth: float = 0.5
var _external_bpm: float = 0.0
var _blend_from_offsets: Dictionary = {}
var _blend_t: float = 1.0
var _blend_speed: float = 5.0

func _ready() -> void:
	if ragdoll_animator == null and auto_detect_animator:
		_find_animator()
	set_physics_process(false)

func play_pattern_by_name(pattern_name: String, blend_time: float = 0.4) -> bool:
	var pat: ActionPattern = ActionLibrary.get_pattern(pattern_name)
	if pat == null:
		push_warning("[ActionDriver] Unknown pattern: %s" % pattern_name)
		return false
	play_pattern(pat, blend_time)
	return true

func play_pattern(pattern: ActionPattern, blend_time: float = 0.4) -> void:
	if pattern == null:
		return
	if _pattern != null and is_physics_processing():
		_blend_from_offsets = _evaluate_current()
		_blend_t = 0.0
		_blend_speed = 1.0 / maxf(blend_time, 0.01)
		var old_name: String = _pattern.pattern_name
		pattern_stopped.emit(old_name)
	_pattern = pattern
	_phase = 0.0
	_elapsed = 0.0
	_cycle_count = 0
	_paused = false
	if ragdoll_animator != null and pattern.base_pose_name != "":
		ragdoll_animator.set_pose_by_name(pattern.base_pose_name)
	if pattern.tempo != null:
		_stroke_depth = pattern.tempo.sample_depth()
		_current_force = pattern.tempo.force
	set_physics_process(true)
	pattern_started.emit(pattern.pattern_name)

func play_motion_tempo(motion_name: String, tempo_name: String, base_pose: String = "", blend_time: float = 0.4) -> bool:
	var m: ActionMotion = ActionLibrary.get_motion(motion_name)
	var t: ActionTempo = ActionLibrary.get_tempo(tempo_name)
	if m == null or t == null:
		push_warning("[ActionDriver] Unknown motion/tempo: %s / %s" % [motion_name, tempo_name])
		return false
	var pat: ActionPattern = ActionPattern.create("%s_%s" % [motion_name, tempo_name], m, t, base_pose)
	play_pattern(pat, blend_time)
	return true

func stop(blend_time: float = 0.3) -> void:
	if _pattern == null:
		return
	if blend_time > 0.0:
		_blend_from_offsets = _evaluate_current()
		_blend_t = 0.0
		_blend_speed = 1.0 / maxf(blend_time, 0.01)
	var old_name: String = _pattern.pattern_name
	_pattern = null
	_phase = 0.0
	_elapsed = 0.0
	if ragdoll_animator != null:
		ragdoll_animator.apply_offset_layer({})
	set_physics_process(false)
	pattern_stopped.emit(old_name)

func set_paused(paused: bool) -> void:
	_paused = paused

func set_tempo(tempo_name: String) -> void:
	if _pattern == null:
		return
	var t: ActionTempo = ActionLibrary.get_tempo(tempo_name)
	if t == null:
		push_warning("[ActionDriver] Unknown tempo: %s" % tempo_name)
		return
	_pattern.tempo = t
	_stroke_depth = t.sample_depth()

func set_motion(motion_name: String) -> void:
	if _pattern == null:
		return
	var m: ActionMotion = ActionLibrary.get_motion(motion_name)
	if m == null:
		push_warning("[ActionDriver] Unknown motion: %s" % motion_name)
		return
	_blend_from_offsets = _evaluate_current()
	_blend_t = 0.0
	_blend_speed = 5.0
	_pattern.motion = m

func set_external_bpm(bpm: float) -> void:
	_external_bpm = bpm

func get_current_pattern_name() -> String:
	if _pattern != null:
		return _pattern.pattern_name
	return ""

func is_playing() -> bool:
	return _pattern != null and is_physics_processing()

func _physics_process(delta: float) -> void:
	if _pattern == null:
		return
	if ragdoll_animator == null:
		return
	_elapsed += delta
	if not _paused:
		var cps: float = _get_effective_cps() * speed_scale
		var prev_phase: float = _phase
		_phase += cps * delta
		if _phase >= 1.0:
			_phase -= 1.0
			_cycle_count += 1
			_stroke_depth = _pattern.tempo.sample_depth()
			_current_force = _pattern.tempo.get_force_at(_elapsed)
			cycle_completed.emit(_cycle_count)
			_check_escalation()
		var offsets: Dictionary = _evaluate_current()
		if _blend_t < 1.0:
			_blend_t = minf(_blend_t + delta * _blend_speed, 1.0)
			offsets = _blend_offsets(_blend_from_offsets, offsets, _blend_t)
		ragdoll_animator.apply_offset_layer(offsets)

func _evaluate_current() -> Dictionary:
	if _pattern == null or _pattern.motion == null:
		return {}
	return _pattern.motion.evaluate(_phase)

func _get_effective_cps() -> float:
	if _external_bpm > 0.0 and _pattern != null and _pattern.tempo != null and _pattern.tempo.sync_to_bpm:
		return (_external_bpm / 60.0) / _pattern.tempo.beats_per_cycle
	if _pattern != null and _pattern.tempo != null:
		return _pattern.tempo.get_speed_at(_elapsed)
	return 1.0

func _check_escalation() -> void:
	if _pattern == null or _pattern.escalation_target == "":
		return
	if _elapsed >= _pattern.escalation_after and _current_force >= _pattern.escalation_on_arousal:
		play_pattern_by_name(_pattern.escalation_target, 0.4)
		pattern_escalated.emit(_pattern.pattern_name, _pattern.escalation_target)

func _blend_offsets(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result: Dictionary = {}
	for key in b.keys():
		var va: Vector3 = a.get(key, Vector3.ZERO)
		var vb: Vector3 = b[key]
		result[key] = va.lerp(vb, t)
	return result

func _find_animator() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child is RagdollAnimator:
			ragdoll_animator = child
			return
