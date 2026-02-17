class_name PhaseLinkedAudio
extends Node
## Triggers voice lines and SFX synchronized to ActionDriver's motion phase.
##
## Moans land at the peak of a thrust stroke — the moment of deepest
## penetration, hardest impact, or most intense contact.
##
## Attach as child of NPCPlaceholder (sibling of ActionDriver, NPCVoicePlayer).

signal phase_trigger(phase_name: String, phase_value: float)

@export_group("Phase Points")
## Phase value (0–1) at which the "impact" trigger fires (deepest point).
@export_range(0.0, 1.0) var impact_phase: float = 0.5
## Phase value for the "withdrawal" trigger (shallowest point).
@export_range(0.0, 1.0) var withdrawal_phase: float = 0.0
## How close the current phase must be to the trigger to fire (±window).
@export_range(0.01, 0.15) var phase_window: float = 0.05

@export_group("Voice Triggers")
@export var voice_enabled: bool = true
@export_range(0.0, 1.0) var voice_probability: float = 0.3
@export_range(0.0, 1.0) var voice_arousal_minimum: float = 0.15
@export var voice_arousal_categories: Array[Dictionary] = [
	{"min_arousal": 0.85, "category": "overwhelmed"},
	{"min_arousal": 0.6, "category": "intense"},
	{"min_arousal": 0.35, "category": "pleased"},
	{"min_arousal": 0.0, "category": "soft"},
]
@export_range(0.5, 10.0) var voice_min_interval: float = 1.5

@export_group("SFX Triggers")
@export var sfx_enabled: bool = true
@export var impact_sfx_category: StringName = &"impact"
@export var impact_sfx_volume_db: float = -6.0

var _driver: ActionDriver = null
var _voice: NPCVoicePlayer = null
var _arousal_sys: ArousalSystem = null
var _sfx_engine: Node = null
var _last_phase: float = 0.0
var _voice_timer: float = 0.0
var _impact_fired_this_cycle: bool = false
var _withdrawal_fired_this_cycle: bool = false
var _npc: Node3D = null
var _initialized: bool = false


func _ready() -> void:
	call_deferred(&"_wire")


func _wire() -> void:
	var parent: Node = get_parent()
	_npc = parent as Node3D
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child is ActionDriver:
			_driver = child as ActionDriver
		elif child is NPCVoicePlayer:
			_voice = child as NPCVoicePlayer
		elif child is ArousalSystem:
			_arousal_sys = child as ArousalSystem
	_sfx_engine = _find_in_tree(&"SFXEngine")
	if _driver != null:
		_driver.cycle_completed.connect(_on_cycle_completed)
	_initialized = _driver != null


func _physics_process(delta: float) -> void:
	if not _initialized or _driver == null or not _driver.is_playing():
		return
	_voice_timer += delta
	var current_phase: float = _driver._phase
	if not _impact_fired_this_cycle:
		if _phase_crossed(current_phase, _last_phase, impact_phase):
			_impact_fired_this_cycle = true
			_on_impact_point(current_phase)
	if not _withdrawal_fired_this_cycle:
		if _phase_crossed(current_phase, _last_phase, withdrawal_phase):
			_withdrawal_fired_this_cycle = true
			phase_trigger.emit("withdrawal", current_phase)
	_last_phase = current_phase


func _on_cycle_completed(_count: int) -> void:
	_impact_fired_this_cycle = false
	_withdrawal_fired_this_cycle = false


func _on_impact_point(current_phase: float) -> void:
	phase_trigger.emit("impact", current_phase)
	var arousal: float = 0.0
	if _arousal_sys != null:
		arousal = _arousal_sys.arousal_level
	if voice_enabled and _voice != null and _voice_timer >= voice_min_interval:
		if arousal >= voice_arousal_minimum and randf() < voice_probability:
			var category: String = _get_voice_category(arousal)
			if category != "" and _voice.can_speak(category):
				_voice.speak(category)
				_voice_timer = 0.0
	if sfx_enabled and _sfx_engine != null and _npc != null:
		var force: float = 0.5
		if _driver._pattern != null and _driver._pattern.tempo != null:
			force = _driver._pattern.tempo.get_force_at(_driver._elapsed)
		if force > 0.3:
			var vol: float = impact_sfx_volume_db + (force * 6.0)
			if _sfx_engine.has_method(&"play_3d"):
				_sfx_engine.call(&"play_3d", impact_sfx_category,
					_npc.global_position, vol)


func _get_voice_category(arousal: float) -> String:
	for tier: Dictionary in voice_arousal_categories:
		var min_a: float = tier.get("min_arousal", 0.0) as float
		var cat: String = tier.get("category", "") as String
		if arousal >= min_a and cat != "":
			return cat
	return "soft"


func _phase_crossed(current: float, previous: float, trigger: float) -> bool:
	if previous <= current:
		return previous < trigger and current >= trigger
	else:
		return previous < trigger or current >= trigger


func _find_in_tree(type_name: StringName) -> Node:
	var root: Node = get_tree().root
	for child: Node in root.get_children():
		if child.get_class() == type_name or child.name == type_name:
			return child
	return null
