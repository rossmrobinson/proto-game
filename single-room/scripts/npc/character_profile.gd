class_name CharacterProfile
extends Node
## Tracks an NPC's comfort/discomfort levels and derives emotional state.
## Driven by NerveSystem stimulation events. Read by BodyLanguageSystem.
##
## Dynamic pain threshold: high comfort near the pain boundary pushes
## the tense/distressed thresholds upward, simulating the way pleasure
## can mask or raise resistance to pain.

signal comfort_changed(new_level: float, delta: float)
signal discomfort_changed(new_level: float, delta: float)
signal emotional_state_changed(new_state: EmotionalState, old_state: EmotionalState)
signal pain_threshold_shifted(effective_tense: float, effective_distressed: float)

## Emotional states derived from comfort + discomfort combination.
enum EmotionalState {
	NEUTRAL,       ## Baseline — nothing notable
	RELAXED,       ## Moderate comfort, low discomfort
	CONTENT,       ## High comfort, low discomfort
	AROUSED,       ## Very high comfort (especially from erogenous zones)
	TENSE,         ## Moderate discomfort, low comfort
	DISTRESSED,    ## High discomfort
	OVERWHELMED,   ## Both comfort and discomfort very high
}

@export var character_name: String = ""

@export_group("Personality")
## How much pain the character can tolerate before becoming distressed (0–1).
@export_range(0.0, 1.0) var pain_tolerance: float = 0.5
## How receptive the character is to touch in general (0–1).
@export_range(0.0, 1.0) var touch_receptivity: float = 0.5
## Multiplier for erogenous zone effects.
@export_range(0.5, 2.0) var erogenous_sensitivity: float = 1.0
## How quickly the character's comfort/discomfort returns to baseline.
@export_range(0.1, 2.0) var emotional_recovery_rate: float = 0.5

@export_group("Thresholds")
## Comfort level above which the character is considered relaxed.
@export var relaxed_threshold: float = 30.0
## Comfort level above which the character is content.
@export var content_threshold: float = 60.0
## Comfort level above which the character is aroused.
@export var aroused_threshold: float = 80.0
## Discomfort level above which the character is tense.
@export var tense_threshold: float = 25.0
## Discomfort level above which the character is distressed.
@export var distressed_threshold: float = 55.0
## When both comfort AND discomfort exceed this, the character is overwhelmed.
@export var overwhelmed_threshold: float = 65.0

@export_group("Dynamic Pain Threshold")
## Enable pleasure→pain threshold shifting.
@export var dynamic_pain_enabled: bool = true
## Maximum amount the tense threshold can be raised by pleasure (absolute).
@export_range(0.0, 40.0) var max_tense_shift: float = 20.0
## Maximum amount the distressed threshold can be raised by pleasure.
@export_range(0.0, 40.0) var max_distressed_shift: float = 15.0
## Comfort level must exceed this fraction of the tense threshold
## for the shift to kick in. 1.0 = comfort must equal tense threshold.
@export_range(0.5, 2.0) var shift_activation_ratio: float = 0.8
## How fast the threshold shift ramps up (higher = sharper curve).
@export_range(0.5, 4.0) var shift_ramp_exponent: float = 1.5
## How quickly the shifted threshold decays back when comfort drops (per sec).
@export_range(0.1, 5.0) var shift_decay_rate: float = 1.0

# ── Runtime ──────────────────────────────────────────────────────────────────
## 0–100 scale. Not opposites — both can be high simultaneously.
var comfort_level: float = 0.0
var discomfort_level: float = 0.0
var current_state: EmotionalState = EmotionalState.NEUTRAL

## Current shift applied to tense/distressed thresholds (0 to max).
var _tense_shift: float = 0.0
var _distressed_shift: float = 0.0
## Effective thresholds (base + shift). Updated every frame.
var effective_tense_threshold: float = 25.0
var effective_distressed_threshold: float = 55.0


func _physics_process(delta: float) -> void:
	# Natural decay toward baseline
	var decay: float = emotional_recovery_rate * delta
	if comfort_level > 0.0:
		comfort_level = maxf(comfort_level - decay, 0.0)
	if discomfort_level > 0.0:
		discomfort_level = maxf(discomfort_level - decay, 0.0)

	# Dynamic pain threshold — pleasure masks pain
	_update_pain_threshold_shift(delta)

	# Re-evaluate emotional state
	_evaluate_state()


## Add comfort (called by NerveSystem).
func add_comfort(amount: float) -> void:
	var scaled: float = amount * touch_receptivity
	comfort_level = clampf(comfort_level + scaled, 0.0, 100.0)
	comfort_changed.emit(comfort_level, scaled)


## Add discomfort (called by NerveSystem).
func add_discomfort(amount: float) -> void:
	# Pain tolerance reduces discomfort accumulation
	var scaled: float = amount * (1.0 - pain_tolerance * 0.5)
	discomfort_level = clampf(discomfort_level + scaled, 0.0, 100.0)
	discomfort_changed.emit(discomfort_level, scaled)


## Force-set comfort (for cutscenes or debug).
func set_comfort(value: float) -> void:
	comfort_level = clampf(value, 0.0, 100.0)
	_evaluate_state()


## Force-set discomfort (for cutscenes or debug).
func set_discomfort(value: float) -> void:
	discomfort_level = clampf(value, 0.0, 100.0)
	_evaluate_state()


## Get the current emotional state.
func get_emotional_state() -> EmotionalState:
	return current_state


## Get a readable label for the current state.
func get_state_label() -> String:
	match current_state:
		EmotionalState.NEUTRAL:
			return "neutral"
		EmotionalState.RELAXED:
			return "relaxed"
		EmotionalState.CONTENT:
			return "content"
		EmotionalState.AROUSED:
			return "aroused"
		EmotionalState.TENSE:
			return "tense"
		EmotionalState.DISTRESSED:
			return "distressed"
		EmotionalState.OVERWHELMED:
			return "overwhelmed"
	return "unknown"


## Returns comfort and discomfort as a normalized Vector2 (for external systems).
func get_feeling_vector() -> Vector2:
	return Vector2(comfort_level / 100.0, discomfort_level / 100.0)


## Get ALL tunable parameters as a Dictionary.  Used by the UI panel.
func get_params() -> Dictionary:
	return {
		"character_name": character_name,
		"pain_tolerance": pain_tolerance,
		"touch_receptivity": touch_receptivity,
		"erogenous_sensitivity": erogenous_sensitivity,
		"emotional_recovery_rate": emotional_recovery_rate,
		"relaxed_threshold": relaxed_threshold,
		"content_threshold": content_threshold,
		"aroused_threshold": aroused_threshold,
		"tense_threshold": tense_threshold,
		"distressed_threshold": distressed_threshold,
		"overwhelmed_threshold": overwhelmed_threshold,
		"dynamic_pain_enabled": dynamic_pain_enabled,
		"max_tense_shift": max_tense_shift,
		"max_distressed_shift": max_distressed_shift,
		"shift_activation_ratio": shift_activation_ratio,
		"shift_ramp_exponent": shift_ramp_exponent,
		"shift_decay_rate": shift_decay_rate,
	}


## Apply a Dictionary of overrides (keys must match property names).
func apply_overrides(overrides: Dictionary) -> void:
	for key: String in overrides.keys():
		if key in self:
			set(key, overrides[key])


# ── Internal ─────────────────────────────────────────────────────────────────

func _update_pain_threshold_shift(delta: float) -> void:
	if not dynamic_pain_enabled:
		_tense_shift = 0.0
		_distressed_shift = 0.0
		effective_tense_threshold = tense_threshold
		effective_distressed_threshold = distressed_threshold
		return

	# How close is discomfort to the base tense threshold?
	var pain_proximity: float = discomfort_level / tense_threshold if tense_threshold > 0.0 else 0.0
	# How much comfort is available to mask it?
	var comfort_ratio: float = comfort_level / (tense_threshold * shift_activation_ratio) \
		if tense_threshold > 0.0 else 0.0

	# shift_factor: 0 when comfort is low or pain is far from threshold,
	# approaches 1 when both comfort and pain-proximity are high.
	var raw_factor: float = minf(comfort_ratio, 1.0) * clampf(pain_proximity, 0.0, 1.5)
	var target_factor: float = clampf(pow(raw_factor, shift_ramp_exponent), 0.0, 1.0)

	# Smooth toward target, decay back when conditions aren't met
	var target_tense: float = target_factor * max_tense_shift
	var target_distressed: float = target_factor * max_distressed_shift

	if target_tense > _tense_shift:
		# Ramp up at 2x decay rate (comfort kicks in fast)
		_tense_shift = minf(_tense_shift + shift_decay_rate * 2.0 * delta, target_tense)
	else:
		_tense_shift = maxf(_tense_shift - shift_decay_rate * delta, target_tense)

	if target_distressed > _distressed_shift:
		_distressed_shift = minf(_distressed_shift + shift_decay_rate * 2.0 * delta, target_distressed)
	else:
		_distressed_shift = maxf(_distressed_shift - shift_decay_rate * delta, target_distressed)

	var new_tense: float = tense_threshold + _tense_shift
	var new_distressed: float = distressed_threshold + _distressed_shift

	# Emit if changed meaningfully (avoid signal spam)
	if absf(new_tense - effective_tense_threshold) > 0.1 \
			or absf(new_distressed - effective_distressed_threshold) > 0.1:
		effective_tense_threshold = new_tense
		effective_distressed_threshold = new_distressed
		pain_threshold_shifted.emit(effective_tense_threshold, effective_distressed_threshold)
	else:
		effective_tense_threshold = new_tense
		effective_distressed_threshold = new_distressed


func _evaluate_state() -> void:
	var old: EmotionalState = current_state
	var new_state: EmotionalState = EmotionalState.NEUTRAL

	var c: float = comfort_level
	var d: float = discomfort_level

	# Use effective (dynamically shifted) thresholds for pain evaluation
	var eff_tense: float = effective_tense_threshold
	var eff_distressed: float = effective_distressed_threshold

	# Overwhelmed takes priority when both axes are high
	if c >= overwhelmed_threshold and d >= overwhelmed_threshold:
		new_state = EmotionalState.OVERWHELMED
	elif d >= eff_distressed:
		new_state = EmotionalState.DISTRESSED
	elif d >= eff_tense:
		new_state = EmotionalState.TENSE
	elif c >= aroused_threshold:
		new_state = EmotionalState.AROUSED
	elif c >= content_threshold:
		new_state = EmotionalState.CONTENT
	elif c >= relaxed_threshold:
		new_state = EmotionalState.RELAXED

	if new_state != old:
		current_state = new_state
		emotional_state_changed.emit(new_state, old)
