class_name NPCBPMSync
extends Node
## Syncs NPC animation timing to the current BPM from BPMMusicPlayer.
##
## Modulates activity controller step durations and pose blend times so that
## NPC movements drift toward being on-beat. The sync is gradual — it takes
## a few seconds to "lock in" rather than snapping jarringly to the beat.
##
## Add as a child of the main scene (sibling to NPCs and BPMMusicPlayer).

signal npc_synced(npc_name: String, sync_ratio: float)

# ── Config ───────────────────────────────────────────────────────────────────

@export_group("Sync Behaviour")
## How many seconds it takes for an NPC to fully lock onto the beat.
@export_range(1.0, 10.0) var ease_in_duration: float = 3.5
## Maximum speed-up/slow-down ratio (1.3 = ±30% from base timing).
@export_range(1.05, 2.0) var max_tempo_ratio: float = 1.3
## How many beats per pose step (1 = every beat, 2 = every other beat, etc.).
@export_range(0.5, 4.0) var beats_per_step: float = 1.0
## Slight random offset per NPC so they don't all snap in unison.
@export_range(0.0, 1.0) var individuality: float = 0.2

# ── Runtime ──────────────────────────────────────────────────────────────────

var _music_player: Node = null  # BPMMusicPlayer (loose typed until .uid generated)
## Per-NPC sync state: npc_name → {ease_progress, base_duration, offset}
var _sync_state: Dictionary = {}
## Cached activity controllers found at init
var _controllers: Array[NPCActivityController] = []
var _startup_done: bool = false


func _ready() -> void:
	call_deferred(&"_find_systems")


func _find_systems() -> void:
	# Find BPMMusicPlayer in the scene tree
	_music_player = _find_typed_child(get_tree().root, &"BPMMusicPlayer")
	if _music_player == null:
		# Also check siblings
		for sibling: Node in get_parent().get_children():
			if sibling.has_method(&"set_external_bpm"):
				_music_player = sibling
				break

	# Find all NPCActivityControllers in the scene
	_find_activity_controllers(get_tree().root)
	_startup_done = true

	if _music_player != null:
		_music_player.bpm_changed.connect(_on_bpm_changed)


func _find_activity_controllers(node: Node) -> void:
	if node is NPCActivityController:
		var ctrl: NPCActivityController = node as NPCActivityController
		_controllers.append(ctrl)
		# Initialize sync state
		var npc_name: String = ""
		if ctrl.get_parent() != null:
			npc_name = ctrl.get_parent().name
		_sync_state[npc_name] = {
			"ease_progress": 0.0,
			"base_dance_duration": ctrl.dance_pose_duration,
			"base_sit_interval": ctrl.sit_stand_interval,
			"offset": randf() * individuality,
		}
	for child: Node in node.get_children():
		_find_activity_controllers(child)


func _physics_process(delta: float) -> void:
	if not _startup_done or _music_player == null:
		return
	if _music_player.current_bpm <= 0.0:
		_reset_all_timings()
		return

	var target_step_sec: float = (60.0 / _music_player.current_bpm) * beats_per_step

	for ctrl: NPCActivityController in _controllers:
		var npc_name: String = ""
		if ctrl.get_parent() != null:
			npc_name = ctrl.get_parent().name

		if not _sync_state.has(npc_name):
			continue

		var state: Dictionary = _sync_state[npc_name] as Dictionary
		var sync_ease: float = state["ease_progress"] as float
		sync_ease = minf(sync_ease + delta / ease_in_duration, 1.0)
		state["ease_progress"] = sync_ease

		# Compute blended duration: lerp from base toward BPM-locked
		var base_dur: float = state["base_dance_duration"] as float
		var ratio: float = base_dur / maxf(target_step_sec, 0.1)
		ratio = clampf(ratio, 1.0 / max_tempo_ratio, max_tempo_ratio)

		# Smoothed ease-in (quadratic ease-out curve)
		var ease_factor: float = 1.0 - (1.0 - sync_ease) * (1.0 - sync_ease)

		var synced_duration: float = lerpf(base_dur, target_step_sec, ease_factor)
		ctrl.dance_pose_duration = synced_duration

		# Also adjust sit/stand interval to be on-beat (multiple beats)
		var base_sit: float = state["base_sit_interval"] as float
		if target_step_sec > 0.0:
			var beats_in_sit: float = roundf(base_sit / target_step_sec)
			beats_in_sit = maxf(beats_in_sit, 2.0)
			var synced_sit: float = lerpf(base_sit, beats_in_sit * target_step_sec, ease_factor)
			ctrl.sit_stand_interval = synced_sit

		npc_synced.emit(npc_name, ease_factor)


func _on_bpm_changed(_new_bpm: float) -> void:
	# Reset ease-in on BPM change so NPCs gradually re-lock
	for npc_name: String in _sync_state:
		var state: Dictionary = _sync_state[npc_name] as Dictionary
		# Don't reset fully — partial re-ease for smoother transitions
		state["ease_progress"] = maxf((state["ease_progress"] as float) * 0.5, 0.0)


func _reset_all_timings() -> void:
	for ctrl: NPCActivityController in _controllers:
		var npc_name: String = ""
		if ctrl.get_parent() != null:
			npc_name = ctrl.get_parent().name
		if _sync_state.has(npc_name):
			var state: Dictionary = _sync_state[npc_name] as Dictionary
			ctrl.dance_pose_duration = state["base_dance_duration"] as float
			ctrl.sit_stand_interval = state["base_sit_interval"] as float
			state["ease_progress"] = 0.0


func _find_typed_child(node: Node, type_name: StringName) -> Node:
	if node.get_class() == type_name:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_typed_child(child, type_name)
		if found != null:
			return found
	return null
