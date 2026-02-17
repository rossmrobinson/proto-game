class_name ArousalMotionLink
extends Node
## Reads ArousalSystem arousal_level and auto-modulates ActionDriver
## speed, amplitude, and tempo tier. Creates the feedback loop where
## higher arousal → faster/deeper motion → more stimulation → higher arousal.
##
## Attach as child of NPCPlaceholder (sibling of ActionDriver, ArousalSystem).

signal tempo_shifted(from_tempo: String, to_tempo: String)

# ── Continuous Modulation ────────────────────────────────────────────────────

@export_group("Speed Scaling")
## ActionDriver.speed_scale at arousal = 0.
@export_range(0.1, 2.0) var speed_at_zero_arousal: float = 0.7
## ActionDriver.speed_scale at arousal = 1.
@export_range(0.5, 4.0) var speed_at_full_arousal: float = 1.8
## Smoothing factor (lower = more sluggish response).
@export_range(1.0, 20.0) var speed_smooth: float = 4.0

@export_group("Amplitude Scaling")
## ActionDriver.amplitude_scale at arousal = 0.
@export_range(0.2, 1.5) var amplitude_at_zero: float = 0.6
## ActionDriver.amplitude_scale at arousal = 1.
@export_range(0.5, 2.0) var amplitude_at_full: float = 1.3
## Smoothing factor for amplitude changes.
@export_range(1.0, 20.0) var amplitude_smooth: float = 3.0

# ── Stepped Tempo Tiers ─────────────────────────────────────────────────────

@export_group("Tempo Tiers")
## Arousal thresholds for tempo shifts (ascending order).
## Each entry: { "threshold": float, "tempo": String }
@export var tempo_tiers: Array[Dictionary] = [
	{"threshold": 0.0, "tempo": "tender"},
	{"threshold": 0.15, "tempo": "sensual"},
	{"threshold": 0.30, "tempo": "steady"},
	{"threshold": 0.45, "tempo": "eager"},
	{"threshold": 0.60, "tempo": "aggressive"},
	{"threshold": 0.75, "tempo": "relentless"},
	{"threshold": 0.90, "tempo": "frenzy"},
]
## Hysteresis: arousal must drop this far below a tier's threshold to downshift.
@export_range(0.0, 0.15) var tier_hysteresis: float = 0.05

@export_group("Orgasm Override")
## Tempo to force during orgasm peak.
@export var orgasm_tempo: String = "frenzy"
## During afterglow, drop to this tempo.
@export var afterglow_tempo: String = "tender"

# ── State ────────────────────────────────────────────────────────────────────

var _driver: ActionDriver = null
var _arousal_sys: ArousalSystem = null
var _current_speed: float = 1.0
var _current_amplitude: float = 1.0
var _current_tier_index: int = 0
var _current_tier_tempo: String = "tender"
var _in_orgasm: bool = false
var _initialized: bool = false


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
	if _arousal_sys != null:
		_arousal_sys.orgasm_started.connect(_on_orgasm)
	_initialized = _driver != null and _arousal_sys != null


func _physics_process(delta: float) -> void:
	if not _initialized or _driver == null or _arousal_sys == null:
		return
	if _in_orgasm:
		return

	var arousal: float = _arousal_sys.arousal_level

	# ── Speed ────────────────────────────────────────────────────────
	var target_speed: float = lerpf(speed_at_zero_arousal, speed_at_full_arousal, arousal)
	_current_speed = lerpf(_current_speed, target_speed, delta * speed_smooth)
	_driver.speed_scale = _current_speed

	# ── Amplitude ────────────────────────────────────────────────────
	var target_amp: float = lerpf(amplitude_at_zero, amplitude_at_full, arousal)
	_current_amplitude = lerpf(_current_amplitude, target_amp, delta * amplitude_smooth)
	_driver.amplitude_scale = _current_amplitude

	# ── Tempo tier ───────────────────────────────────────────────────
	_update_tempo_tier(arousal)


func _update_tempo_tier(arousal: float) -> void:
	if tempo_tiers.is_empty():
		return

	# Find the highest tier whose threshold is met
	var best_index: int = 0
	for i: int in range(tempo_tiers.size()):
		var threshold: float = tempo_tiers[i].get("threshold", 0.0) as float
		if arousal >= threshold:
			best_index = i

	# Hysteresis: only downshift if arousal is below threshold - hysteresis
	if best_index < _current_tier_index:
		var current_threshold: float = tempo_tiers[_current_tier_index].get("threshold", 0.0) as float
		if arousal >= current_threshold - tier_hysteresis:
			return  # Stay at current tier

	if best_index != _current_tier_index:
		var old: String = _current_tier_tempo
		_current_tier_index = best_index
		_current_tier_tempo = tempo_tiers[best_index].get("tempo", "tender") as String
		if _driver != null and _driver.is_playing():
			_driver.set_tempo(_current_tier_tempo)
		tempo_shifted.emit(old, _current_tier_tempo)


func _on_orgasm(_intensity: float) -> void:
	_in_orgasm = true
	# Lock to orgasm tempo
	if orgasm_tempo != "" and _driver != null and _driver.is_playing():
		var old: String = _current_tier_tempo
		_current_tier_tempo = orgasm_tempo
		_driver.set_tempo(orgasm_tempo)
		tempo_shifted.emit(old, orgasm_tempo)
	# Schedule afterglow transition
	get_tree().create_timer(3.0).timeout.connect(_on_afterglow)


func _on_afterglow() -> void:
	_in_orgasm = false
	# Drop to afterglow tempo
	if afterglow_tempo != "" and _driver != null:
		var old: String = _current_tier_tempo
		_current_tier_tempo = afterglow_tempo
		_driver.set_tempo(afterglow_tempo)
		tempo_shifted.emit(old, afterglow_tempo)
	_current_tier_index = 0
