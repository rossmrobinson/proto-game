class_name BodyLanguageSystem
extends Node
## Reads emotional state from CharacterProfile and drives sub-animations
## that layer on top of primary pose/animation. No UI meters — body language
## IS the feedback channel.
##
## Attach as a child of the NPC root (sibling of NerveSystem, CharacterProfile).
## Requires a RagdollAnimator sibling to apply the sub-poses.

signal expression_changed(new_expression: String)

# ── Idle Micro-Motions ───────────────────────────────────────────────────────
# Layered on top of whatever the primary animation is doing.
# These define small joint angle OFFSETS (degrees) keyed by joint name.

## Neutral: subtle idle sway.
const IDLE_NEUTRAL: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(0.0, 0.0, 0.0),
	"neck_to_head": Vector3(0.0, 0.0, 0.0),
}

## Relaxed: shoulders drop, head tilts slightly, spine softens.
const IDLE_RELAXED: Dictionary = {
	"chest_to_neck": Vector3(-3.0, 0.0, 0.0),
	"neck_to_head": Vector3(-5.0, 3.0, 0.0),
	"left_clavicle_to_left_upper_arm": Vector3(0.0, 0.0, -5.0),
	"right_clavicle_to_right_upper_arm": Vector3(0.0, 0.0, -5.0),
	"spine_upper_to_chest": Vector3(-2.0, 0.0, 0.0),
}

## Content: body opens up, slight chest lift, arms looser.
const IDLE_CONTENT: Dictionary = {
	"spine_upper_to_chest": Vector3(3.0, 0.0, 0.0),
	"chest_to_neck": Vector3(-2.0, 0.0, 0.0),
	"neck_to_head": Vector3(-3.0, 0.0, 0.0),
	"left_clavicle_to_left_upper_arm": Vector3(0.0, 0.0, -8.0),
	"right_clavicle_to_right_upper_arm": Vector3(0.0, 0.0, -8.0),
}

## Aroused: spine arches, head tilts back, breathing rhythm via chest.
const IDLE_AROUSED: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(5.0, 0.0, 0.0),
	"spine_mid_to_spine_upper": Vector3(4.0, 0.0, 0.0),
	"spine_upper_to_chest": Vector3(5.0, 0.0, 0.0),
	"chest_to_neck": Vector3(-4.0, 0.0, 0.0),
	"neck_to_head": Vector3(-10.0, 0.0, 0.0),
	"pelvis_to_spine_lower": Vector3(4.0, 0.0, 0.0),
}

## Tense: shoulders rise, spine stiffens, head pulls slightly forward.
const IDLE_TENSE: Dictionary = {
	"left_clavicle_to_left_upper_arm": Vector3(0.0, 0.0, 8.0),
	"right_clavicle_to_right_upper_arm": Vector3(0.0, 0.0, 8.0),
	"chest_to_neck": Vector3(5.0, 0.0, 0.0),
	"neck_to_head": Vector3(8.0, 0.0, 0.0),
	"spine_upper_to_chest": Vector3(-3.0, 0.0, 0.0),
}

## Distressed: curling inward, head drops, arms pull close.
const IDLE_DISTRESSED: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(-8.0, 0.0, 0.0),
	"spine_mid_to_spine_upper": Vector3(-6.0, 0.0, 0.0),
	"spine_upper_to_chest": Vector3(-8.0, 0.0, 0.0),
	"chest_to_neck": Vector3(10.0, 0.0, 0.0),
	"neck_to_head": Vector3(15.0, 0.0, 0.0),
	"left_clavicle_to_left_upper_arm": Vector3(0.0, 0.0, 15.0),
	"right_clavicle_to_right_upper_arm": Vector3(0.0, 0.0, 15.0),
	"left_upper_arm_to_left_forearm": Vector3(-40.0, 0.0, 0.0),
	"right_upper_arm_to_right_forearm": Vector3(-40.0, 0.0, 0.0),
}

## Overwhelmed: trembling, twitchy — handled via oscillation, not static pose.
const IDLE_OVERWHELMED: Dictionary = {
	"spine_lower_to_spine_mid": Vector3(-4.0, 0.0, 0.0),
	"neck_to_head": Vector3(-5.0, 0.0, 0.0),
	"spine_upper_to_chest": Vector3(3.0, 0.0, 0.0),
}

# ── Breathing Patterns ───────────────────────────────────────────────────────
# Oscillation amplitude (degrees) and frequency (Hz) for chest expansion.
const BREATHING: Dictionary = {
	CharacterProfile.EmotionalState.NEUTRAL: {"amplitude": 1.5, "frequency": 0.25},
	CharacterProfile.EmotionalState.RELAXED: {"amplitude": 2.5, "frequency": 0.18},
	CharacterProfile.EmotionalState.CONTENT: {"amplitude": 3.0, "frequency": 0.2},
	CharacterProfile.EmotionalState.AROUSED: {"amplitude": 5.0, "frequency": 0.45},
	CharacterProfile.EmotionalState.TENSE: {"amplitude": 2.0, "frequency": 0.35},
	CharacterProfile.EmotionalState.DISTRESSED: {"amplitude": 3.5, "frequency": 0.5},
	CharacterProfile.EmotionalState.OVERWHELMED: {"amplitude": 6.0, "frequency": 0.6},
}

# ── State ────────────────────────────────────────────────────────────────────
var _profile: CharacterProfile = null
var _animator: Node = null  # RagdollAnimator — typed loosely to avoid load order
var _current_offsets: Dictionary = {}
var _target_offsets: Dictionary = {}
var _blend_progress: float = 1.0
var _blend_duration: float = 0.8
var _breath_time: float = 0.0
var _tremble_time: float = 0.0
var _current_expression: String = "neutral"

## How strongly body language offsets are applied (0 = off, 1 = full).
@export_range(0.0, 1.0) var influence: float = 0.8
## Tremble intensity multiplier for the overwhelmed state.
@export_range(0.0, 5.0) var tremble_intensity: float = 2.0


func _ready() -> void:
	for sibling: Node in get_parent().get_children():
		if sibling is CharacterProfile:
			_profile = sibling as CharacterProfile
			_profile.emotional_state_changed.connect(_on_emotional_state_changed)
		elif sibling.get_class() == "Node" and sibling.has_method(&"set_pose"):
			_animator = sibling
	# Also check script class
	if _animator == null:
		for sibling: Node in get_parent().get_children():
			if sibling.get_script() != null and sibling.has_method(&"set_pose"):
				_animator = sibling
				break


func _physics_process(delta: float) -> void:
	if _profile == null:
		return

	# Blend toward target offsets
	if _blend_progress < 1.0:
		_blend_progress = minf(_blend_progress + delta / _blend_duration, 1.0)

	# Breathing oscillation
	var breath_params: Dictionary = BREATHING.get(
		_profile.current_state, BREATHING[CharacterProfile.EmotionalState.NEUTRAL]) as Dictionary
	var amp: float = breath_params["amplitude"] as float
	var freq: float = breath_params["frequency"] as float
	_breath_time += delta
	var breath_offset: float = sin(_breath_time * freq * TAU) * amp

	# Trembling for overwhelmed state
	var tremble_offset: Vector3 = Vector3.ZERO
	if _profile.current_state == CharacterProfile.EmotionalState.OVERWHELMED:
		_tremble_time += delta
		tremble_offset = Vector3(
			sin(_tremble_time * 17.3) * tremble_intensity,
			sin(_tremble_time * 13.7) * tremble_intensity * 0.5,
			sin(_tremble_time * 11.1) * tremble_intensity * 0.7
		)

	# Build the final offset dictionary for this frame
	var frame_offsets: Dictionary = {}
	for joint_key: String in _target_offsets.keys():
		var target: Vector3 = _target_offsets[joint_key] as Vector3
		var current: Vector3 = _current_offsets.get(joint_key, Vector3.ZERO) as Vector3
		var blended: Vector3 = current.lerp(target, _smoothstep(_blend_progress))
		frame_offsets[joint_key] = blended * influence

	# Add breathing to chest joint
	var chest_key: String = "spine_upper_to_chest"
	var chest_val: Vector3 = frame_offsets.get(chest_key, Vector3.ZERO) as Vector3
	chest_val.x += breath_offset
	frame_offsets[chest_key] = chest_val

	# Add tremble to multiple joints
	if tremble_offset.length() > 0.01:
		for joint_key: String in ["neck_to_head", "left_hand_to_left_fingers",
				"right_hand_to_right_fingers", "spine_mid_to_spine_upper"]:
			var val: Vector3 = frame_offsets.get(joint_key, Vector3.ZERO) as Vector3
			frame_offsets[joint_key] = val + tremble_offset

	# Apply offsets to animator if available
	if _animator != null and _animator.has_method(&"apply_offset_layer"):
		_animator.call(&"apply_offset_layer", frame_offsets)


## Get the current body language expression label.
func get_expression() -> String:
	return _current_expression


# ── Callbacks ────────────────────────────────────────────────────────────────

func _on_emotional_state_changed(new_state: CharacterProfile.EmotionalState,
		_old_state: CharacterProfile.EmotionalState) -> void:
	_current_offsets = _target_offsets.duplicate()
	_target_offsets = _get_offsets_for_state(new_state)
	_blend_progress = 0.0

	var label: String = "neutral"
	match new_state:
		CharacterProfile.EmotionalState.RELAXED:
			label = "relaxed"
		CharacterProfile.EmotionalState.CONTENT:
			label = "content"
		CharacterProfile.EmotionalState.AROUSED:
			label = "aroused"
		CharacterProfile.EmotionalState.TENSE:
			label = "tense"
		CharacterProfile.EmotionalState.DISTRESSED:
			label = "distressed"
		CharacterProfile.EmotionalState.OVERWHELMED:
			label = "overwhelmed"
	_current_expression = label
	expression_changed.emit(label)


func _get_offsets_for_state(state: CharacterProfile.EmotionalState) -> Dictionary:
	match state:
		CharacterProfile.EmotionalState.RELAXED:
			return IDLE_RELAXED.duplicate()
		CharacterProfile.EmotionalState.CONTENT:
			return IDLE_CONTENT.duplicate()
		CharacterProfile.EmotionalState.AROUSED:
			return IDLE_AROUSED.duplicate()
		CharacterProfile.EmotionalState.TENSE:
			return IDLE_TENSE.duplicate()
		CharacterProfile.EmotionalState.DISTRESSED:
			return IDLE_DISTRESSED.duplicate()
		CharacterProfile.EmotionalState.OVERWHELMED:
			return IDLE_OVERWHELMED.duplicate()
	return IDLE_NEUTRAL.duplicate()


func _smoothstep(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
