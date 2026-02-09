class_name AutopilotSystem
extends Node
## Plays looping animation sequences in a hands-free "autopilot" mode.
## Toggled by middle-mouse hold (1 second). Banks of animations can be
## assigned per context. For now, provides infrastructure + a few defaults.
##
## Attach as child of PlayerController, sibling of HandInteractionSystem.

signal autopilot_started(bank_name: String, sequence_name: String)
signal autopilot_stopped()

## An animation bank is a named collection of looping sequences.
## Each sequence is an Array of pose names played in order.
var _banks: Dictionary = {}  # bank_name → { sequence_name → Array[String] }
var _active_bank: String = ""
var _active_sequence: String = ""
var _sequence_index: int = 0
var _is_active: bool = false
var _pose_timer: float = 0.0

@export_group("Timing")
## Default seconds per pose in a sequence.
@export var pose_duration: float = 1.5
## Blend time between poses within a sequence.
@export var blend_time: float = 0.6

var _target_npc: Node = null  # The NPC whose animator we're driving
var _hand_system: Node = null  # HandInteractionSystem sibling


func _ready() -> void:
	_register_default_banks()
	# Find sibling HandInteractionSystem
	for sibling: Node in get_parent().get_children():
		if sibling.has_method(&"is_grabbing"):
			_hand_system = sibling
			if sibling.has_signal(&"autopilot_toggled"):
				sibling.connect(&"autopilot_toggled", _on_autopilot_toggled)
			break


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_pose_timer += delta
	if _pose_timer >= pose_duration:
		_pose_timer = 0.0
		_advance_sequence()


## Start autopilot with a specific bank and sequence.
func start(bank_name: String, sequence_name: String, npc: Node) -> bool:
	if not _banks.has(bank_name):
		push_warning("[AutopilotSystem] Unknown bank: %s" % bank_name)
		return false
	var bank: Dictionary = _banks[bank_name] as Dictionary
	if not bank.has(sequence_name):
		push_warning("[AutopilotSystem] Unknown sequence '%s' in bank '%s'" % [
			sequence_name, bank_name])
		return false

	_target_npc = npc
	_active_bank = bank_name
	_active_sequence = sequence_name
	_sequence_index = 0
	_pose_timer = 0.0
	_is_active = true
	_apply_current_pose()
	autopilot_started.emit(bank_name, sequence_name)
	return true


## Stop autopilot mode.
func stop() -> void:
	_is_active = false
	_target_npc = null
	_active_bank = ""
	_active_sequence = ""
	autopilot_stopped.emit()


## Register a new animation bank.
func register_bank(bank_name: String, sequences: Dictionary) -> void:
	_banks[bank_name] = sequences


## Get list of registered bank names.
func get_bank_names() -> Array[String]:
	var names: Array[String] = []
	for key: String in _banks.keys():
		names.append(key)
	return names


## Get sequence names within a bank.
func get_sequence_names(bank_name: String) -> Array[String]:
	var names: Array[String] = []
	if _banks.has(bank_name):
		var bank: Dictionary = _banks[bank_name] as Dictionary
		for key: String in bank.keys():
			names.append(key)
	return names


func is_active() -> bool:
	return _is_active


# ── Internal ─────────────────────────────────────────────────────────────────

func _advance_sequence() -> void:
	var bank: Dictionary = _banks.get(_active_bank, {}) as Dictionary
	var sequence: Array = bank.get(_active_sequence, []) as Array
	if sequence.is_empty():
		stop()
		return
	_sequence_index = (_sequence_index + 1) % sequence.size()
	_apply_current_pose()


func _apply_current_pose() -> void:
	if _target_npc == null or not is_instance_valid(_target_npc):
		stop()
		return

	var bank: Dictionary = _banks.get(_active_bank, {}) as Dictionary
	var sequence: Array = bank.get(_active_sequence, []) as Array
	if _sequence_index >= sequence.size():
		return

	var pose_name: String = sequence[_sequence_index] as String

	# Find the NPC's RagdollAnimator and set the pose by name
	for child: Node in _target_npc.get_children():
		if child.has_method(&"set_pose"):
			# The pose library needs to resolve the name to a RagdollPose.
			# For now just try calling with the name; the animator can look it up.
			if child.has_method(&"set_pose_by_name"):
				child.call(&"set_pose_by_name", pose_name, blend_time)
			break


func _on_autopilot_toggled(enabled: bool) -> void:
	if enabled:
		# Auto-start with the first sequence in the active bank if we have an NPC
		if _active_bank == "":
			_active_bank = "idle"
		if _target_npc != null:
			var bank: Dictionary = _banks.get(_active_bank, {}) as Dictionary
			if not bank.is_empty():
				var first_seq: String = bank.keys()[0] as String
				start(_active_bank, first_seq, _target_npc)
				return
		# No NPC to drive — just flag as active so it starts when one is assigned
		_is_active = true
		autopilot_started.emit(_active_bank, "")
	else:
		stop()


func _register_default_banks() -> void:
	# Placeholder banks — sequence entries are pose names from the pose libraries.
	# These will be filled in once Ross sees the game running and can pick what he wants.
	register_bank("idle", {
		"breathe": ["neutral_stand", "neutral_stand"],
		"shift_weight": ["neutral_stand", "weight_left", "neutral_stand", "weight_right"],
	})

	register_bank("explore", {
		"look_around": ["head_left", "neutral_stand", "head_right", "neutral_stand"],
		"stretch": ["arms_up_stretch", "neutral_stand", "side_stretch_left",
			"neutral_stand", "side_stretch_right", "neutral_stand"],
	})

	register_bank("intimate", {
		"slow_caress": ["caress_start", "caress_mid", "caress_end"],
		"gentle_rock": ["rock_forward", "rock_back"],
	})
