class_name CharacterProfile
extends Node
## Tracks an NPC's comfort/discomfort levels and derives emotional state.
## Driven by NerveSystem stimulation events. Read by BodyLanguageSystem.
##
## No UI meters — the emotional state drives body language only.

signal comfort_changed(new_level: float, delta: float)
signal discomfort_changed(new_level: float, delta: float)
signal emotional_state_changed(new_state: EmotionalState, old_state: EmotionalState)

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

# ── Runtime ──────────────────────────────────────────────────────────────────
## 0–100 scale. Not opposites — both can be high simultaneously.
var comfort_level: float = 0.0
var discomfort_level: float = 0.0
var current_state: EmotionalState = EmotionalState.NEUTRAL


func _physics_process(delta: float) -> void:
	# Natural decay toward baseline
	var decay: float = emotional_recovery_rate * delta
	if comfort_level > 0.0:
		comfort_level = maxf(comfort_level - decay, 0.0)
	if discomfort_level > 0.0:
		discomfort_level = maxf(discomfort_level - decay, 0.0)

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


# ── Internal ─────────────────────────────────────────────────────────────────

func _evaluate_state() -> void:
	var old: EmotionalState = current_state
	var new_state: EmotionalState = EmotionalState.NEUTRAL

	var c: float = comfort_level
	var d: float = discomfort_level

	# Overwhelmed takes priority when both axes are high
	if c >= overwhelmed_threshold and d >= overwhelmed_threshold:
		new_state = EmotionalState.OVERWHELMED
	elif d >= distressed_threshold:
		new_state = EmotionalState.DISTRESSED
	elif d >= tense_threshold:
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
