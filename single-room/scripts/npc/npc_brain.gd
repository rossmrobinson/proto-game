class_name NPCBrain
extends Node
## Central decision-maker for an NPC.
## Subscribes to events from NerveSystem, CharacterProfile, BodyPart signals,
## NPCCommandSystem, and NPCAttention.  Maintains short-term memory via
## NPCMemory and triggers reactions: voice lines, gaze shifts, behavior
## changes, and (future) LLM queries to Google Colab.
##
## Attach as child of NPCPlaceholder.

# ── Event type constants (used as StringName keys in NPCMemory) ──────────────
const EVT_GRAB: StringName = &"grab"
const EVT_RELEASE: StringName = &"release"
const EVT_IMPACT: StringName = &"impact"
const EVT_TOUCH: StringName = &"touch"
const EVT_COMMAND_START: StringName = &"command_start"
const EVT_COMMAND_END: StringName = &"command_end"
const EVT_PLAYER_APPROACH: StringName = &"player_approach"
const EVT_PLAYER_LEAVE: StringName = &"player_leave"
const EVT_EMOTIONAL_SHIFT: StringName = &"emotional_shift"
const EVT_VOICE_LINE: StringName = &"voice_line"

signal reaction_triggered(reaction_name: String, data: Dictionary)

@export_group("Personality")
## How likely the NPC is to speak unprompted (0 = silent, 1 = chatty).
@export_range(0.0, 1.0) var talkativeness: float = 0.5
## How quickly the NPC startles (0 = stoic, 1 = jumpy).
@export_range(0.0, 1.0) var nervousness: float = 0.3
## How positively the NPC reacts to being touched (0 = averse, 1 = receptive).
@export_range(0.0, 1.0) var touch_openness: float = 0.5
## How likely the NPC is to resist commands (0 = obedient, 1 = defiant).
@export_range(0.0, 1.0) var defiance: float = 0.2
## How long (seconds) before the NPC tries an idle voice line.
@export var idle_speak_interval: float = 15.0
## Random jitter on idle speak interval.
@export var idle_speak_jitter: float = 5.0

@export_group("Reaction Tuning")
## Grabs within this window count as "repeated" for annoyance buildup.
@export var repeat_grab_window: float = 10.0
## Number of grabs in the window before the NPC gets annoyed.
@export var annoyance_grab_threshold: int = 3
## Minimum impact intensity to trigger a pain voice line.
@export var pain_voice_threshold: float = 1.0
## Minimum impact intensity to trigger a startled reaction.
@export var startle_impact_threshold: float = 2.0

# ── Sibling References ───────────────────────────────────────────────────────
var _npc: NPCPlaceholder = null
var memory: NPCMemory = null
var voice: NPCVoicePlayer = null
var attention: NPCAttention = null
var _profile: CharacterProfile = null
var _nerve: NerveSystem = null
var _behavior: NPCBehavior = null
var _body_language: BodyLanguageSystem = null

# ── Internal State ───────────────────────────────────────────────────────────
## Whether the NPC is currently being commanded by the player.
var _is_commanded: bool = false
## Timer for idle speech.
var _idle_speak_timer: float = 0.0
var _next_idle_speak: float = 15.0
## Whether the brain has been initialized (deferred wiring).
var _initialized: bool = false
## Greet cooldown — seconds before greeting the player again.
var _greet_cooldown: float = 0.0
## Has the NPC greeted the player at least once this session?
var _has_greeted: bool = false


func _ready() -> void:
	_npc = get_parent() as NPCPlaceholder
	call_deferred(&"_wire_subsystems")
	_randomize_idle_timer()


func _physics_process(delta: float) -> void:
	if not _initialized:
		return

	# Greet cooldown
	if _greet_cooldown > 0.0:
		_greet_cooldown -= delta

	# Idle speech timer
	if not _is_commanded:
		_idle_speak_timer += delta
		if _idle_speak_timer >= _next_idle_speak:
			_idle_speak_timer = 0.0
			_randomize_idle_timer()
			_try_idle_speak()


# ═════════════════════════════════════════════════════════════════════════════
#  REACTION LOGIC — event → decision → action
# ═════════════════════════════════════════════════════════════════════════════

## Called when any body part is grabbed.
func _on_part_grabbed(part_name: String, by: Node3D) -> void:
	memory.record(EVT_GRAB, part_name, 1.0, by)
	attention.fixate(by)

	var recent_grabs: int = memory.count_recent(EVT_GRAB, repeat_grab_window)

	# First grab → surprised or curious
	if recent_grabs <= 1:
		if _roll(nervousness):
			attention.startle(by)
			_speak(&"startled")
		else:
			_speak(&"grabbed")
	# Repeated grabs → escalating annoyance or comfort depending on openness
	elif recent_grabs >= annoyance_grab_threshold:
		if _roll(1.0 - touch_openness):
			_speak(&"annoyed")
		else:
			_speak(&"comfort")
	else:
		_speak(&"grabbed")

	reaction_triggered.emit("grab", {"part": part_name, "by": by})


## Called when any body part is released.
func _on_part_released(part_name: String, _by: Node3D) -> void:
	memory.record(EVT_RELEASE, part_name)
	attention.release_fixation()
	_speak(&"released")
	reaction_triggered.emit("release", {"part": part_name})


## Called when a body part receives an impact.
func _on_part_impact(part_name: String, impact_force: float, other_body: Node) -> void:
	memory.record(EVT_IMPACT, part_name, impact_force, other_body as Node3D)

	if impact_force >= startle_impact_threshold:
		attention.startle(other_body as Node3D if other_body is Node3D else null)
		_speak(&"startled", true)  # interrupt
	elif impact_force >= pain_voice_threshold:
		_speak(&"pain")
	else:
		_speak(&"effort")

	reaction_triggered.emit("impact", {
		"part": part_name, "force": impact_force, "other": other_body,
	})


## Called when the NerveSystem processes a touch event.
func _on_stimulation_event(part_name: String, touch_type: NerveSystem.TouchType,
		intensity: float, comfort_delta: float, discomfort_delta: float) -> void:
	memory.record(EVT_TOUCH, part_name, intensity, null, {
		"touch_type": touch_type,
		"comfort_delta": comfort_delta,
		"discomfort_delta": discomfort_delta,
	})

	# High comfort → contentment voice
	if comfort_delta > 0.5 and _profile != null:
		if _profile.comfort_level > _profile.content_threshold:
			_speak(&"comfort")

	# High discomfort → pain voice
	if discomfort_delta > 0.5 and _profile != null:
		if _profile.discomfort_level > _profile.tense_threshold:
			_speak(&"pain")


## Called when the emotional state changes.
func _on_emotional_state_changed(new_state: CharacterProfile.EmotionalState,
		old_state: CharacterProfile.EmotionalState) -> void:
	memory.record(EVT_EMOTIONAL_SHIFT, "", 0.0, null, {
		"from": old_state, "to": new_state,
	})

	# Voice reactions to emotional transitions
	match new_state:
		CharacterProfile.EmotionalState.CONTENT:
			_speak(&"comfort")
		CharacterProfile.EmotionalState.AROUSED:
			_speak(&"comfort")
		CharacterProfile.EmotionalState.DISTRESSED:
			_speak(&"pain")
		CharacterProfile.EmotionalState.OVERWHELMED:
			_speak(&"pain", true)  # interrupt — this is intense
		CharacterProfile.EmotionalState.TENSE:
			_speak(&"annoyed")
		CharacterProfile.EmotionalState.RELAXED:
			# Only speak if transitioning DOWN from something intense
			if old_state == CharacterProfile.EmotionalState.DISTRESSED \
					or old_state == CharacterProfile.EmotionalState.OVERWHELMED:
				_speak(&"comfort")

	reaction_triggered.emit("emotional_shift", {
		"from": old_state, "to": new_state,
	})


## Called when the player starts commanding this NPC.
func _on_commanded() -> void:
	_is_commanded = true
	memory.record(EVT_COMMAND_START)
	_idle_speak_timer = 0.0

	if _roll(defiance):
		_speak(&"annoyed")
	else:
		_speak(&"commanded")

	reaction_triggered.emit("commanded", {})


## Called when the player stops commanding this NPC.
func _on_command_released() -> void:
	_is_commanded = false
	memory.record(EVT_COMMAND_END)
	_speak(&"command-released")
	reaction_triggered.emit("command_released", {})


## Called when the player enters detection range.
func _on_player_entered_proximity() -> void:
	memory.record(EVT_PLAYER_APPROACH)

	# Greet if we haven't recently
	if _greet_cooldown <= 0.0:
		if _roll(talkativeness + 0.3):  # bias toward greeting
			_speak(&"greetings")
			_has_greeted = true
			_greet_cooldown = 60.0  # Don't greet again for a minute

	reaction_triggered.emit("player_approach", {})


## Called when the player leaves detection range.
func _on_player_exited_proximity() -> void:
	memory.record(EVT_PLAYER_LEAVE)
	reaction_triggered.emit("player_leave", {})


# ═════════════════════════════════════════════════════════════════════════════
#  IDLE BEHAVIOR
# ═════════════════════════════════════════════════════════════════════════════

func _try_idle_speak() -> void:
	if voice == null:
		return
	if not _roll(talkativeness):
		return
	# Pick contextual idle line based on emotional state
	if _profile != null:
		match _profile.current_state:
			CharacterProfile.EmotionalState.RELAXED, \
			CharacterProfile.EmotionalState.CONTENT:
				if _roll(0.5):
					_speak(&"comfort")
					return
			CharacterProfile.EmotionalState.TENSE:
				if _roll(0.5):
					_speak(&"annoyed")
					return
	# Default: generic idle or curious
	if _roll(0.4):
		_speak(&"curious")
	else:
		_speak(&"idle")


# ═════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════════════════════

## Attempt to speak a voice category. Returns true if successful.
func _speak(category: StringName, interrupt: bool = false) -> bool:
	if voice == null:
		return false
	var cat_str: String = String(category)
	var success: bool = voice.speak(cat_str, interrupt)
	if success:
		memory.record(EVT_VOICE_LINE, "", 0.0, null, cat_str)
	return success


## Probabilistic roll: returns true with probability `chance` (0–1).
func _roll(chance: float) -> bool:
	return randf() < clampf(chance, 0.0, 1.0)


func _randomize_idle_timer() -> void:
	_next_idle_speak = idle_speak_interval + randf_range(
		-idle_speak_jitter, idle_speak_jitter)
	_next_idle_speak = maxf(_next_idle_speak, 3.0)


# ═════════════════════════════════════════════════════════════════════════════
#  WIRING — connects to all sibling subsystems
# ═════════════════════════════════════════════════════════════════════════════

func _wire_subsystems() -> void:
	if _npc == null:
		push_error("[NPCBrain] No NPCPlaceholder parent found.")
		return

	# Find siblings
	for child: Node in _npc.get_children():
		if child is NPCMemory:
			memory = child as NPCMemory
		elif child is NPCVoicePlayer:
			voice = child as NPCVoicePlayer
		elif child is NPCAttention:
			attention = child as NPCAttention
		elif child is CharacterProfile:
			_profile = child as CharacterProfile
		elif child is NerveSystem:
			_nerve = child as NerveSystem
		elif child is NPCBehavior:
			_behavior = child as NPCBehavior
		elif child is BodyLanguageSystem:
			_body_language = child as BodyLanguageSystem

	# Connect NerveSystem events
	if _nerve != null:
		_nerve.stimulation_event.connect(_on_stimulation_event)

	# Connect CharacterProfile emotional shifts
	if _profile != null:
		_profile.emotional_state_changed.connect(_on_emotional_state_changed)

	# Connect NPCAttention proximity events
	if attention != null:
		attention.player_entered_proximity.connect(_on_player_entered_proximity)
		attention.player_exited_proximity.connect(_on_player_exited_proximity)

	# Connect body part signals (grab/release/impact) from ragdoll
	if _npc.ragdoll != null:
		_connect_body_parts()
	else:
		# Ragdoll may not be built yet — connect when it is
		if _npc.ragdoll != null:
			_npc.ragdoll.ragdoll_built.connect(_connect_body_parts)

	# Connect NPCCommandSystem (it's on the player, not a sibling).
	# We listen indirectly — the command_indicator or npc_placeholder handles this.
	# The brain will be notified via on_commanded() / on_command_released().

	_initialized = true

	# Log what we found
	var found: PackedStringArray = PackedStringArray()
	if memory != null:
		found.append("Memory")
	if voice != null:
		found.append("Voice")
	if attention != null:
		found.append("Attention")
	if _profile != null:
		found.append("Profile")
	if _nerve != null:
		found.append("Nerve")
	if _behavior != null:
		found.append("Behavior")
	if _body_language != null:
		found.append("BodyLang")
	print("[NPCBrain] %s wired: %s" % [_npc.npc_name, ", ".join(found)])


func _connect_body_parts() -> void:
	if _npc.ragdoll == null:
		return
	for part_name_key: String in _npc.ragdoll.parts:
		var part: BodyPart = _npc.ragdoll.parts[part_name_key] as BodyPart
		if part == null:
			continue
		if not part.part_grabbed.is_connected(_on_part_grabbed):
			part.part_grabbed.connect(_on_part_grabbed)
		if not part.part_released.is_connected(_on_part_released):
			part.part_released.connect(_on_part_released)
		if not part.part_impact.is_connected(_on_part_impact):
			part.part_impact.connect(_on_part_impact)
