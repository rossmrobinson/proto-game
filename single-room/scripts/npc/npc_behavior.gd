class_name NPCBehavior
extends Node
## Autonomous NPC behavior controller.
## When the NPC is NOT being directly commanded, this drives idle/loop
## animations and simple worldspace actions (look around, shift weight, etc.).
##
## When the NPC IS commanded, this pauses and cedes control to the player.
## Attach as child of NPCPlaceholder.

signal behavior_started(behavior_name: String)
signal behavior_stopped()

enum State { IDLE, LOOPING, PAUSED }

@export_group("Timing")
## Seconds between idle behavior changes.
@export var idle_change_interval: float = 5.0
## Random jitter added/subtracted from the interval.
@export var idle_change_jitter: float = 2.0

# ── State ────────────────────────────────────────────────────────────────────
var state: State = State.IDLE
var _npc: NPCPlaceholder = null
var _timer: float = 0.0
var _next_change: float = 5.0
## The name of the behavior currently executing.
var current_behavior: String = "idle"

## Registry of simple behaviors.  Each entry is a Callable that receives
## the NPC reference and returns nothing.  It's expected to issue a
## pose/action and then yield until the next call.
var _behaviors: Dictionary = {}  # name → Callable


func _ready() -> void:
	_npc = get_parent() as NPCPlaceholder
	_randomize_timer()
	_register_defaults()


func _physics_process(delta: float) -> void:
	if state == State.PAUSED:
		return

	_timer += delta
	if _timer >= _next_change:
		_timer = 0.0
		_randomize_timer()
		_pick_behavior()


# ── Public API ───────────────────────────────────────────────────────────────

## Pause autonomous behavior (called when the player starts commanding).
func pause() -> void:
	state = State.PAUSED
	behavior_stopped.emit()


## Resume autonomous behavior.
func resume() -> void:
	state = State.IDLE
	_timer = 0.0
	_randomize_timer()


## Register a named behavior.
func register_behavior(behavior_name: String, callback: Callable) -> void:
	_behaviors[behavior_name] = callback


## Force a specific behavior immediately.
func force_behavior(behavior_name: String) -> void:
	if not _behaviors.has(behavior_name):
		push_warning("[NPCBehavior] Unknown behavior: %s" % behavior_name)
		return
	current_behavior = behavior_name
	var cb: Callable = _behaviors[behavior_name] as Callable
	cb.call(_npc)
	behavior_started.emit(behavior_name)


# ── Internal ─────────────────────────────────────────────────────────────────

func _randomize_timer() -> void:
	_next_change = idle_change_interval + randf_range(-idle_change_jitter, idle_change_jitter)
	_next_change = maxf(_next_change, 1.0)


func _pick_behavior() -> void:
	if _behaviors.is_empty():
		return
	var names: Array = _behaviors.keys()
	var pick: String = names[randi() % names.size()] as String
	force_behavior(pick)


func _register_defaults() -> void:
	# Simple placeholder behaviors that just print — will be replaced with
	# actual pose/animation calls once the ragdoll animator is wired up.
	register_behavior("idle", func(npc: NPCPlaceholder) -> void:
		# Do nothing visible — just stand there
		pass
	)
	register_behavior("shift_weight", func(npc: NPCPlaceholder) -> void:
		# Slight random torso offset to look alive
		if npc.ragdoll != null and is_instance_valid(npc.ragdoll):
			var pelvis: Node3D = npc.ragdoll.parts.get("pelvis") as Node3D
			if pelvis != null and pelvis is RigidBody3D:
				var body: RigidBody3D = pelvis as RigidBody3D
				var nudge: Vector3 = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.05, 0.05))
				body.apply_central_impulse(nudge)
	)
	register_behavior("look_around", func(npc: NPCPlaceholder) -> void:
		# Small head impulse
		if npc.ragdoll != null and is_instance_valid(npc.ragdoll):
			var head: Node3D = npc.ragdoll.parts.get("head") as Node3D
			if head != null and head is RigidBody3D:
				var body: RigidBody3D = head as RigidBody3D
				var look: Vector3 = Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.05, 0.05))
				body.apply_central_impulse(look)
	)
