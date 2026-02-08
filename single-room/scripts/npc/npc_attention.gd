class_name NPCAttention
extends Node
## Tracks what the NPC is paying attention to and drives gaze direction.
## Monitors player proximity, touch events, sounds, and other NPCs.
##
## The brain reads `focus_target` and `awareness_level` to make decisions.
## BodyLanguageSystem (future) can read `look_direction` for head orientation.
##
## Attach as child of NPCPlaceholder.

signal focus_changed(new_target: Node3D, old_target: Node3D)
signal awareness_changed(new_level: AwarenessLevel, old_level: AwarenessLevel)
signal player_entered_proximity()
signal player_exited_proximity()

## How aware the NPC currently is of external stimuli.
enum AwarenessLevel {
	UNAWARE,    ## Idle, nothing interesting happening
	NOTICED,    ## Something caught attention briefly
	ATTENTIVE,  ## Actively watching something
	FIXATED,    ## Locked on — being touched, grabbed, etc.
	STARTLED,   ## Sudden unexpected event
}

@export_group("Detection")
## NPC can notice things within this radius (meters).
@export var awareness_radius: float = 8.0
## Distance at which the NPC becomes ATTENTIVE to the player.
@export var attention_radius: float = 4.0
## Distance at which the NPC is considered in close/intimate proximity.
@export var close_radius: float = 1.5
## How many seconds before STARTLED decays to ATTENTIVE.
@export var startle_duration: float = 1.2
## How many seconds of no stimuli before dropping from ATTENTIVE to NOTICED.
@export var attention_decay_time: float = 5.0
## How many seconds of no stimuli before dropping from NOTICED to UNAWARE.
@export var notice_decay_time: float = 8.0

# ── State ────────────────────────────────────────────────────────────────────
## What the NPC is currently looking at / focused on (can be null).
var focus_target: Node3D = null
## Current awareness level.
var awareness_level: AwarenessLevel = AwarenessLevel.UNAWARE
## Normalized direction from NPC toward focus target (world space).
var look_direction: Vector3 = Vector3.FORWARD
## Whether the player is within awareness_radius.
var player_in_range: bool = false
## Whether the player is within close_radius.
var player_close: bool = false
## Distance to the player (updated each frame, INF if no player found).
var player_distance: float = INF

## Internal timers
var _attention_timer: float = 0.0
var _startle_timer: float = 0.0
var _npc: Node3D = null
var _player_ref: Node3D = null
## Competing interest targets sorted by priority.
var _interests: Array[Dictionary] = []  # { "target": Node3D, "priority": float }


func _ready() -> void:
	_npc = get_parent() as Node3D
	# Defer player lookup
	call_deferred(&"_find_player")


func _physics_process(delta: float) -> void:
	_update_player_distance()
	_update_proximity_events()
	_tick_timers(delta)
	_evaluate_awareness()
	_update_look_direction()


# ── Public API ───────────────────────────────────────────────────────────────

## Force attention to a specific target at a given priority.
func notice(target: Node3D, priority: float = 1.0) -> void:
	_attention_timer = 0.0
	_add_interest(target, priority)
	_resolve_focus()
	if awareness_level < AwarenessLevel.NOTICED:
		_set_awareness(AwarenessLevel.NOTICED)


## Trigger a startle response (sudden grab, loud sound, etc.).
func startle(source: Node3D = null) -> void:
	_startle_timer = startle_duration
	_attention_timer = 0.0
	if source != null:
		_add_interest(source, 10.0)
		_resolve_focus()
	_set_awareness(AwarenessLevel.STARTLED)


## Something is actively happening (touch, grab) — lock attention.
func fixate(target: Node3D) -> void:
	_attention_timer = 0.0
	_add_interest(target, 100.0)
	_resolve_focus()
	_set_awareness(AwarenessLevel.FIXATED)


## Release fixation (e.g., grab ended).
func release_fixation() -> void:
	# Remove highest-priority interest
	if not _interests.is_empty():
		_interests.pop_back()
	_resolve_focus()
	_attention_timer = 0.0
	if awareness_level == AwarenessLevel.FIXATED:
		_set_awareness(AwarenessLevel.ATTENTIVE)


## Clear all tracked interests and reset to UNAWARE.
func reset() -> void:
	_interests.clear()
	_set_focus(null)
	_set_awareness(AwarenessLevel.UNAWARE)
	_attention_timer = 0.0
	_startle_timer = 0.0


## Get a readable label for the current awareness level.
func get_awareness_label() -> String:
	match awareness_level:
		AwarenessLevel.UNAWARE:
			return "unaware"
		AwarenessLevel.NOTICED:
			return "noticed"
		AwarenessLevel.ATTENTIVE:
			return "attentive"
		AwarenessLevel.FIXATED:
			return "fixated"
		AwarenessLevel.STARTLED:
			return "startled"
	return "unknown"


# ── Internal ─────────────────────────────────────────────────────────────────

func _find_player() -> void:
	# Look for PlayerController in the scene
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var nodes: Array[Node] = tree.get_nodes_in_group(&"player")
	if not nodes.is_empty():
		_player_ref = nodes[0] as Node3D
		return
	# Fallback: find CharacterBody3D tagged as player
	var scene: Node = tree.current_scene
	if scene == null:
		return
	_player_ref = _find_player_recursive(scene)


func _find_player_recursive(node: Node) -> Node3D:
	if node is CharacterBody3D and node.is_in_group(&"player"):
		return node as Node3D
	# Also check for PlayerController class
	if node.get_script() != null:
		var script: Script = node.get_script() as Script
		if script != null and script.get_global_name() == &"PlayerController":
			return node as Node3D
	for child: Node in node.get_children():
		var found: Node3D = _find_player_recursive(child)
		if found != null:
			return found
	return null


func _update_player_distance() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		player_distance = INF
		return
	if _npc == null:
		player_distance = INF
		return
	player_distance = _npc.global_position.distance_to(_player_ref.global_position)


func _update_proximity_events() -> void:
	var was_in_range: bool = player_in_range
	var was_close: bool = player_close

	player_in_range = player_distance <= awareness_radius
	player_close = player_distance <= close_radius

	if player_in_range and not was_in_range:
		player_entered_proximity.emit()
		# Auto-notice the player when they enter range
		if _player_ref != null:
			notice(_player_ref, 2.0)
	elif not player_in_range and was_in_range:
		player_exited_proximity.emit()


func _tick_timers(delta: float) -> void:
	# Startle decay
	if _startle_timer > 0.0:
		_startle_timer -= delta
		if _startle_timer <= 0.0:
			_startle_timer = 0.0
			if awareness_level == AwarenessLevel.STARTLED:
				_set_awareness(AwarenessLevel.ATTENTIVE)

	# Attention decay timer
	if awareness_level >= AwarenessLevel.NOTICED and awareness_level != AwarenessLevel.STARTLED:
		if awareness_level != AwarenessLevel.FIXATED:
			_attention_timer += delta

	# Decay interest priorities over time
	for i: int in range(_interests.size() - 1, -1, -1):
		var entry: Dictionary = _interests[i]
		var p: float = entry["priority"] as float
		p -= delta * 0.5
		if p <= 0.0:
			_interests.remove_at(i)
		else:
			entry["priority"] = p


func _evaluate_awareness() -> void:
	# Don't auto-demote during startle or fixation
	if awareness_level == AwarenessLevel.STARTLED or awareness_level == AwarenessLevel.FIXATED:
		return

	if awareness_level == AwarenessLevel.ATTENTIVE:
		if _attention_timer >= attention_decay_time:
			_set_awareness(AwarenessLevel.NOTICED)
			_attention_timer = 0.0
	elif awareness_level == AwarenessLevel.NOTICED:
		if _attention_timer >= notice_decay_time:
			_set_awareness(AwarenessLevel.UNAWARE)
			_attention_timer = 0.0

	# Auto-upgrade based on player distance
	if _player_ref != null and is_instance_valid(_player_ref):
		if player_distance <= attention_radius and awareness_level < AwarenessLevel.ATTENTIVE:
			_set_awareness(AwarenessLevel.ATTENTIVE)
			_set_focus(_player_ref)
			_attention_timer = 0.0
		elif player_distance <= awareness_radius and awareness_level < AwarenessLevel.NOTICED:
			_set_awareness(AwarenessLevel.NOTICED)
			_attention_timer = 0.0


func _update_look_direction() -> void:
	if focus_target == null or not is_instance_valid(focus_target):
		look_direction = -_npc.global_basis.z if _npc != null else Vector3.FORWARD
		return
	if _npc == null:
		return
	var dir: Vector3 = (focus_target.global_position - _npc.global_position)
	if dir.length_squared() > 0.001:
		look_direction = dir.normalized()


func _add_interest(target: Node3D, priority: float) -> void:
	# Update existing or insert
	for entry: Dictionary in _interests:
		if entry["target"] == target:
			var current_p: float = entry["priority"] as float
			entry["priority"] = maxf(current_p, priority)
			_sort_interests()
			return
	_interests.append({"target": target, "priority": priority})
	_sort_interests()
	# Cap interest list
	if _interests.size() > 8:
		_interests.remove_at(0)


func _sort_interests() -> void:
	_interests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["priority"] as float) < (b["priority"] as float)
	)


func _resolve_focus() -> void:
	if _interests.is_empty():
		_set_focus(null)
		return
	var best: Dictionary = _interests[_interests.size() - 1]
	var target: Node3D = best["target"] as Node3D
	if target != null and is_instance_valid(target):
		_set_focus(target)
	else:
		_interests.pop_back()
		_resolve_focus()


func _set_focus(target: Node3D) -> void:
	if target == focus_target:
		return
	var old: Node3D = focus_target
	focus_target = target
	focus_changed.emit(target, old)


func _set_awareness(level: AwarenessLevel) -> void:
	if level == awareness_level:
		return
	var old: AwarenessLevel = awareness_level
	awareness_level = level
	awareness_changed.emit(level, old)
