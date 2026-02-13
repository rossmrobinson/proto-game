class_name ConstrictionSystem
extends Node
## Tracks external neck constriction (choking) and oral-depth airway occlusion.
##
## Outputs:
##   airway_level   — 0.0 = fully open, 1.0 = fully sealed
##   constriction_pressure — 0.0 – 1.0 raw grip pressure on neck
##
## Feeds into:
##   - BodyLanguageSystem (breathing suppression / gasping)
##   - NerveSystem (pain + erogenous stimulation on neck)
##   - CharacterProfile (discomfort / emotional state push)
##   - FluidSystem tears (indirectly via discomfort)
##   - Consciousness timer (blackout on prolonged full seal)

# ── Signals ──────────────────────────────────────────────────────────────────
signal airway_changed(airway_level: float)
signal constriction_started()
signal constriction_ended()
signal consciousness_lost()
signal consciousness_regained()

# ── Constriction Tuning ──────────────────────────────────────────────────────
@export_group("Constriction Tuning")
## How quickly grip pressure ramps toward target (per second).
@export var pressure_ramp_speed: float = 4.0
## How quickly grip pressure decays toward zero on release (per second).
@export var pressure_release_speed: float = 6.0
## Fraction of grip intensity that translates to airway occlusion (0–1).
@export_range(0.0, 1.0) var grip_airway_factor: float = 0.85
## Oral depth (0–1 normalised) at which the airway starts to occlude.
@export_range(0.0, 1.0) var oral_depth_airway_start: float = 0.6
## Oral depth at which airway is fully occluded.
@export_range(0.0, 1.0) var oral_depth_airway_full: float = 0.95

# ── Nerve / Comfort Tuning ───────────────────────────────────────────────────
@export_group("Nerve / Comfort")
## Nerve touch intensity sent per tick while constricted (scaled by pressure).
@export var nerve_intensity_scale: float = 0.6
## Discomfort per second pushed to CharacterProfile at full pressure.
@export var discomfort_per_second: float = 12.0
## Comfort per second at light pressure (erogenous neck stimulation).
@export var comfort_per_second_light: float = 3.0
## Pressure threshold (0–1) above which comfort stops and only pain applies.
@export_range(0.0, 1.0) var pain_only_threshold: float = 0.7

# ── Consciousness ────────────────────────────────────────────────────────────
@export_group("Consciousness")
## Seconds of full airway seal before consciousness is lost.
@export var blackout_time: float = 8.0
## Seconds of open airway needed to fully recover from near-blackout.
@export var recovery_time: float = 4.0
## Airway level above which the blackout timer starts ticking.
@export_range(0.0, 1.0) var blackout_airway_threshold: float = 0.9

# ── Breathing Override ───────────────────────────────────────────────────────
@export_group("Breathing Override")
## Breathing amplitude multiplier at full airway occlusion (0 = no breath).
@export_range(0.0, 1.0) var breath_amplitude_at_seal: float = 0.0
## Breathing frequency multiplier at full occlusion (rapid shallow gasps).
@export var breath_frequency_at_seal: float = 2.5
## How fast breathing overrides blend in/out (per second).
@export var breath_blend_speed: float = 5.0

# ── Gasp Recovery ────────────────────────────────────────────────────────────
@export_group("Gasp Recovery")
## Duration of the exaggerated gasp when airway reopens (seconds).
@export var gasp_duration: float = 1.2
## Breathing amplitude multiplier during gasp.
@export var gasp_amplitude_mult: float = 3.0
## Breathing frequency during gasp.
@export var gasp_frequency: float = 0.8

# ── Runtime State ────────────────────────────────────────────────────────────
## Current grip pressure on the neck (0–1).
var constriction_pressure: float = 0.0
## Oral insertion contribution to airway occlusion (0–1).
var oral_airway_occlusion: float = 0.0
## Combined airway openness level (0 = open, 1 = sealed).
var airway_level: float = 0.0
## Consciousness level (1 = fully conscious, 0 = blacked out).
var consciousness: float = 1.0
## True while any constriction source is active.
var is_constricted: bool = false

## Breathing suppression factor for BodyLanguageSystem to read.
## 0.0 = no suppression, 1.0 = fully suppressed.
var breathing_suppression: float = 0.0
## Breathing amplitude override multiplier (1.0 = normal).
var breath_amplitude_override: float = 1.0
## Breathing frequency override multiplier (1.0 = normal).
var breath_frequency_override: float = 1.0

# ── Internal ─────────────────────────────────────────────────────────────────
var _target_pressure: float = 0.0
var _blackout_accumulator: float = 0.0
var _gasp_timer: float = 0.0
var _was_constricted: bool = false
var _conscious: bool = true

# Subsystem references (set by setup())
var _character_profile: CharacterProfile = null
var _nerve_system: NerveSystem = null
var _body_language: BodyLanguageSystem = null
var _ragdoll: HumanoidRagdollBuilder = null
var _third_party_insertion: Node = null  # ThirdPartyInsertion (optional)


func setup(npc_root: Node3D) -> void:
	for child: Node in npc_root.get_children():
		if child is CharacterProfile:
			_character_profile = child as CharacterProfile
		elif child is NerveSystem:
			_nerve_system = child as NerveSystem
		elif child is BodyLanguageSystem:
			_body_language = child as BodyLanguageSystem
		elif child is HumanoidRagdollBuilder:
			_ragdoll = child as HumanoidRagdollBuilder
		elif child.has_method(&"is_inserted"):
			_third_party_insertion = child

	# Connect neck grab signals if ragdoll has a neck part
	if _ragdoll != null and _ragdoll.parts.has("neck"):
		var neck_part: BodyPart = _ragdoll.parts["neck"] as BodyPart
		neck_part.part_grabbed.connect(_on_neck_grabbed)
		neck_part.part_released.connect(_on_neck_released)

	# Connect oral insertion signals if third party insertion exists
	if _third_party_insertion != null:
		if _third_party_insertion.has_signal("depth_changed"):
			_third_party_insertion.depth_changed.connect(_on_oral_depth_changed)


func _on_neck_grabbed(_part_name: String, _by: Node3D) -> void:
	_target_pressure = 1.0


func _on_neck_released(_part_name: String, _by: Node3D) -> void:
	_target_pressure = 0.0


func _on_oral_depth_changed(passage_name: String, depth: float,
		max_depth: float) -> void:
	if passage_name != "oral":
		return
	var normalised: float = depth / maxf(max_depth, 0.001)
	if normalised < oral_depth_airway_start:
		oral_airway_occlusion = 0.0
	elif normalised >= oral_depth_airway_full:
		oral_airway_occlusion = 1.0
	else:
		oral_airway_occlusion = (normalised - oral_depth_airway_start) \
			/ (oral_depth_airway_full - oral_depth_airway_start)


func _physics_process(delta: float) -> void:
	_update_pressure(delta)
	_update_airway()
	_update_nerve_feedback(delta)
	_update_consciousness(delta)
	_update_breathing_override(delta)
	_update_gasp(delta)


func _update_pressure(delta: float) -> void:
	if _target_pressure > constriction_pressure:
		constriction_pressure = minf(
			constriction_pressure + pressure_ramp_speed * delta,
			_target_pressure)
	elif _target_pressure < constriction_pressure:
		constriction_pressure = maxf(
			constriction_pressure - pressure_release_speed * delta,
			_target_pressure)

	# Track constriction state transitions
	var was: bool = is_constricted
	is_constricted = constriction_pressure > 0.01 or oral_airway_occlusion > 0.01
	if is_constricted and not was:
		_was_constricted = true
		constriction_started.emit()
	elif not is_constricted and was:
		constriction_ended.emit()
		# Start gasp recovery
		if _was_constricted:
			_gasp_timer = gasp_duration
			_was_constricted = false


func _update_airway() -> void:
	var grip_contribution: float = constriction_pressure * grip_airway_factor
	var prev_airway: float = airway_level
	airway_level = clampf(maxf(grip_contribution, oral_airway_occlusion), 0.0, 1.0)
	if absf(airway_level - prev_airway) > 0.001:
		airway_changed.emit(airway_level)


func _update_nerve_feedback(delta: float) -> void:
	if _nerve_system == null or _character_profile == null:
		return
	if constriction_pressure < 0.01:
		return

	# Nerve stimulation on neck
	var intensity: float = constriction_pressure * nerve_intensity_scale
	_nerve_system.receive_touch("neck", NerveSystem.TouchType.PRESS, intensity)

	# Comfort at light pressure (erogenous), pain at heavy pressure
	if constriction_pressure < pain_only_threshold:
		var comfort_t: float = constriction_pressure / pain_only_threshold
		_character_profile.add_comfort(
			comfort_per_second_light * comfort_t * delta)
	# Discomfort scales with pressure above threshold
	if constriction_pressure > pain_only_threshold:
		var pain_t: float = (constriction_pressure - pain_only_threshold) \
			/ (1.0 - pain_only_threshold)
		_character_profile.add_discomfort(discomfort_per_second * pain_t * delta)
	elif constriction_pressure > 0.5:
		# Moderate pressure: mild discomfort
		var mild_t: float = (constriction_pressure - 0.5) \
			/ (pain_only_threshold - 0.5)
		_character_profile.add_discomfort(
			discomfort_per_second * 0.3 * mild_t * delta)


func _update_consciousness(delta: float) -> void:
	if airway_level >= blackout_airway_threshold:
		_blackout_accumulator += delta
		var fraction: float = _blackout_accumulator / blackout_time
		consciousness = clampf(1.0 - fraction, 0.0, 1.0)
		if consciousness <= 0.0 and _conscious:
			_conscious = false
			consciousness_lost.emit()
	else:
		if _blackout_accumulator > 0.0:
			_blackout_accumulator = maxf(
				_blackout_accumulator - delta * (blackout_time / recovery_time),
				0.0)
			consciousness = clampf(
				1.0 - (_blackout_accumulator / blackout_time), 0.0, 1.0)
		if not _conscious and consciousness >= 0.5:
			_conscious = true
			consciousness_regained.emit()


func _update_breathing_override(delta: float) -> void:
	# Target breathing modifiers based on airway level
	var target_amp: float = lerpf(1.0, breath_amplitude_at_seal, airway_level)
	var target_freq: float = lerpf(1.0, breath_frequency_at_seal, airway_level)
	var target_suppression: float = airway_level

	# Smooth blend
	var blend: float = minf(breath_blend_speed * delta, 1.0)
	breath_amplitude_override = lerpf(breath_amplitude_override, target_amp, blend)
	breath_frequency_override = lerpf(breath_frequency_override, target_freq, blend)
	breathing_suppression = lerpf(breathing_suppression, target_suppression, blend)


func _update_gasp(delta: float) -> void:
	if _gasp_timer <= 0.0:
		return
	_gasp_timer -= delta
	if _gasp_timer <= 0.0:
		_gasp_timer = 0.0
		# Overrides return to normal via blend in _update_breathing_override
		return

	# During gasp: override breathing to exaggerated recovery breaths
	var gasp_t: float = _gasp_timer / gasp_duration
	breath_amplitude_override = lerpf(1.0, gasp_amplitude_mult, gasp_t)
	breath_frequency_override = lerpf(1.0, gasp_frequency, gasp_t)
	breathing_suppression = 0.0  # Airway open during gasp
