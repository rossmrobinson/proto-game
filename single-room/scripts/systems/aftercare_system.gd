class_name AftercareSystem
extends Node
## Physical aftercare behavior during post-orgasm phases.
##
## When orgasm fires, this system plays tender behaviors — cuddling poses,
## slow breathing, voice lines — then gradually fades out.
##
## Attach as child of NPCPlaceholder (sibling of ActionDriver,
## ArousalSystem, CharacterProfile, NPCVoicePlayer, RagdollAnimator).

signal aftercare_started()
signal aftercare_ended()
signal aftercare_behavior(behavior_name: String)

@export_group("Timing")
@export_range(0.5, 5.0) var onset_delay: float = 2.0
@export_range(3.0, 30.0) var aftercare_duration: float = 10.0
@export_range(2.0, 15.0) var voice_interval: float = 4.0

@export_group("Behaviors")
@export var aftercare_pattern: String = "standing_idle"
@export var aftercare_pose: String = ""
@export var stop_active_pattern: bool = true
@export_range(0.1, 2.0) var blend_time: float = 0.8

@export_group("Voice")
@export var voice_categories: Array[String] = [
	"afterglow", "tender", "satisfied", "whisper",
]
@export_range(0.0, 1.0) var voice_probability: float = 0.6

@export_group("Body Language")
@export var aftercare_offsets: Dictionary = {}

const CATCHING_BREATH: Dictionary = {
	"spine_upper_to_chest": Vector3(5.0, 0.0, 0.0),
	"chest_to_neck": Vector3(-6.0, 0.0, 0.0),
	"neck_to_head": Vector3(-12.0, 0.0, 0.0),
	"pelvis_to_spine_lower": Vector3(3.0, 0.0, 0.0),
	"left_clavicle_to_left_upper_arm": Vector3(0.0, 0.0, -10.0),
	"right_clavicle_to_right_upper_arm": Vector3(0.0, 0.0, -10.0),
}

const CUDDLE_CURL: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(-4.0, 0.0, 0.0),
	"spine_mid_to_spine_upper": Vector3(-5.0, 0.0, 0.0),
	"chest_to_neck": Vector3(-3.0, 5.0, 0.0),
	"neck_to_head": Vector3(-8.0, 8.0, 0.0),
	"left_upper_arm_to_left_forearm": Vector3(0.0, 0.0, -45.0),
	"right_upper_arm_to_right_forearm": Vector3(0.0, 0.0, -45.0),
	"left_clavicle_to_left_upper_arm": Vector3(15.0, 10.0, 0.0),
	"right_clavicle_to_right_upper_arm": Vector3(15.0, -10.0, 0.0),
}

const RECOVERY_STAND: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(0.0, 2.0, 0.0),
	"chest_to_neck": Vector3(-2.0, 0.0, 0.0),
	"neck_to_head": Vector3(-5.0, 0.0, 0.0),
	"pelvis_to_spine_lower": Vector3(2.0, 0.0, 0.0),
}

const AFTERCARE_POSTURES: Array[Dictionary] = [
	CATCHING_BREATH, CUDDLE_CURL, RECOVERY_STAND,
]

enum Phase { INACTIVE, WAITING, ACTIVE, FADING }

var _phase: Phase = Phase.INACTIVE
var _driver: ActionDriver = null
var _arousal_sys: ArousalSystem = null
var _profile: CharacterProfile = null
var _voice: NPCVoicePlayer = null
var _animator: RagdollAnimator = null
var _body_lang: BodyLanguageSystem = null
var _phase_timer: float = 0.0
var _voice_timer: float = 0.0
var _active_offsets: Dictionary = {}
var _fade_t: float = 0.0
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
		elif child is CharacterProfile:
			_profile = child as CharacterProfile
		elif child is NPCVoicePlayer:
			_voice = child as NPCVoicePlayer
		elif child is RagdollAnimator:
			_animator = child as RagdollAnimator
		elif child is BodyLanguageSystem:
			_body_lang = child as BodyLanguageSystem
	if _arousal_sys != null:
		_arousal_sys.orgasm_started.connect(_on_orgasm)
	_initialized = _arousal_sys != null


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	match _phase:
		Phase.INACTIVE:
			return
		Phase.WAITING:
			_process_waiting(delta)
		Phase.ACTIVE:
			_process_active(delta)
		Phase.FADING:
			_process_fading(delta)


func _on_orgasm(_intensity: float) -> void:
	if _phase != Phase.INACTIVE:
		return
	_phase = Phase.WAITING
	_phase_timer = 0.0


func _process_waiting(delta: float) -> void:
	_phase_timer += delta
	if _phase_timer >= onset_delay:
		_begin_aftercare()


func _process_active(delta: float) -> void:
	_phase_timer += delta
	_voice_timer += delta
	if _voice_timer >= voice_interval and _voice != null:
		_try_aftercare_voice()
		_voice_timer = 0.0
	if _phase_timer >= aftercare_duration:
		_begin_fade()


func _process_fading(delta: float) -> void:
	_fade_t += delta * 0.5
	if _fade_t >= 1.0:
		_end_aftercare()
		return
	if _animator != null and not _active_offsets.is_empty():
		var faded: Dictionary = {}
		for joint_key: String in _active_offsets:
			var target: Vector3 = _active_offsets[joint_key] as Vector3
			faded[joint_key] = target * (1.0 - _fade_t)
		_animator.apply_offset_layer(faded)


func _begin_aftercare() -> void:
	_phase = Phase.ACTIVE
	_phase_timer = 0.0
	_voice_timer = voice_interval * 0.5
	if stop_active_pattern and _driver != null and _driver.is_playing():
		_driver.stop(blend_time)
	if not aftercare_offsets.is_empty():
		_active_offsets = aftercare_offsets.duplicate()
	elif not AFTERCARE_POSTURES.is_empty():
		_active_offsets = AFTERCARE_POSTURES[randi() % AFTERCARE_POSTURES.size()].duplicate()
	if _animator != null and not _active_offsets.is_empty():
		_animator.apply_offset_layer(_active_offsets)
	if aftercare_pattern != "" and _driver != null:
		_driver.play_pattern_by_name(aftercare_pattern, blend_time)
	elif aftercare_pose != "" and _animator != null:
		_animator.set_pose_by_name(aftercare_pose, blend_time)
	if _profile != null and _profile.has_method(&"set_emotional_state"):
		_profile.set_emotional_state(CharacterProfile.EmotionalState.RELAXED)
	aftercare_started.emit()
	aftercare_behavior.emit("begin")


func _begin_fade() -> void:
	_phase = Phase.FADING
	_fade_t = 0.0
	aftercare_behavior.emit("fading")


func _end_aftercare() -> void:
	_phase = Phase.INACTIVE
	_phase_timer = 0.0
	if _animator != null:
		_animator.apply_offset_layer({})
	aftercare_ended.emit()
	aftercare_behavior.emit("ended")


func _try_aftercare_voice() -> void:
	if _voice == null or voice_categories.is_empty():
		return
	if randf() > voice_probability:
		return
	var shuffled: Array[String] = voice_categories.duplicate()
	shuffled.shuffle()
	for category: String in shuffled:
		if _voice.can_speak(category):
			_voice.speak(category)
			aftercare_behavior.emit("voice_%s" % category)
			return


func is_active() -> bool:
	return _phase != Phase.INACTIVE


func get_phase() -> Phase:
	return _phase


func trigger_aftercare() -> void:
	if _phase == Phase.INACTIVE:
		_phase = Phase.WAITING
		_phase_timer = 0.0


func cancel() -> void:
	if _phase != Phase.INACTIVE:
		_end_aftercare()
