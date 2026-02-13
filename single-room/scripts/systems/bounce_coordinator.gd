class_name BounceCoordinator
extends Node
## Coordinates synchronized rhythmic bouncing across multiple actors.
##
## In the suspension scenario, Persons 2-3 hold Person 1's legs and push
## down in rhythm, while the chain's elasticity provides the return stroke.
## The coordinator provides a shared phase clock and applies forces to
## designated body parts on beat.
##
## Each "slot" is a participating body part with a phase offset so actors
## can push in-phase, counter-phase, or any custom relationship.

signal beat_tick(phase: float)

# ── Configuration ────────────────────────────────────────────────────────────

@export_group("Rhythm")
## Beats per minute of the bounce cycle.
@export_range(20.0, 200.0) var bpm: float = 60.0
## Shape of the force curve per beat.  0 = sharp impulse, 1 = smooth sine.
@export_range(0.0, 1.0) var curve_smoothness: float = 0.7

@export_group("Forces")
## Peak downward force applied to each bouncing body part (N).
@export var push_force: float = 35.0
## Fraction of the cycle during which force is applied (duty cycle 0–1).
@export_range(0.1, 0.9) var duty_cycle: float = 0.4

# ── Runtime State ────────────────────────────────────────────────────────────

## Master phase (0.0 – 1.0), advances with BPM.
var _phase: float = 0.0
var _running: bool = false
var _slots: Array[Dictionary] = []
# Each slot: { "body": RigidBody3D, "phase_offset": float, "direction": Vector3 }


func _ready() -> void:
	set_physics_process(false)


## Start the bounce clock.
func start() -> void:
	_running = true
	_phase = 0.0
	set_physics_process(true)


## Pause the clock (slots stay registered).
func stop() -> void:
	_running = false
	set_physics_process(false)


## Register a body part to receive rhythmic force.
## phase_offset: 0.0 = in-phase with master, 0.5 = counter-phase, etc.
## direction: force direction in world space (default DOWN).
func add_slot(body: RigidBody3D, phase_offset: float = 0.0,
		direction: Vector3 = Vector3.DOWN) -> int:
	var slot: Dictionary = {
		"body": body,
		"phase_offset": phase_offset,
		"direction": direction.normalized(),
	}
	_slots.append(slot)
	return _slots.size() - 1


## Remove a slot by index.
func remove_slot(index: int) -> void:
	if index >= 0 and index < _slots.size():
		_slots.remove_at(index)


## Remove all slots for a specific body.
func remove_body(body: RigidBody3D) -> void:
	for i: int in range(_slots.size() - 1, -1, -1):
		if (_slots[i] as Dictionary)["body"] == body:
			_slots.remove_at(i)


## Clear all slots.
func clear_slots() -> void:
	_slots.clear()


## Change BPM at runtime.
func set_bpm(new_bpm: float) -> void:
	bpm = clampf(new_bpm, 20.0, 200.0)


## Get the current master phase (0.0 – 1.0).
func get_phase() -> float:
	return _phase


func _physics_process(delta: float) -> void:
	if not _running:
		return

	# Advance phase
	var freq: float = bpm / 60.0
	_phase += freq * delta
	if _phase >= 1.0:
		_phase -= floorf(_phase)  # wrap
		beat_tick.emit(_phase)

	# Apply forces to slots
	for slot: Dictionary in _slots:
		var body: RigidBody3D = slot["body"] as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue

		var offset: float = slot["phase_offset"] as float
		var dir: Vector3 = slot["direction"] as Vector3
		var slot_phase: float = fmod(_phase + offset, 1.0)

		var strength: float = _compute_force_curve(slot_phase)
		if strength > 0.001:
			body.apply_central_force(dir * push_force * strength)


## Compute force strength from phase position and duty cycle.
func _compute_force_curve(slot_phase: float) -> float:
	if slot_phase > duty_cycle:
		return 0.0

	# Normalise within the duty window [0, 1]
	var t: float = slot_phase / duty_cycle

	if curve_smoothness > 0.5:
		# Smooth sine bell: sin(π·t)
		return sin(t * PI)
	elif curve_smoothness > 0.0:
		# Blend between sharp and sine
		var sharp: float = 1.0 if t < 0.5 else 0.0
		var smooth: float = sin(t * PI)
		var blend: float = curve_smoothness / 0.5
		return lerpf(sharp, smooth, blend)
	else:
		# Sharp impulse: first half of duty = 1.0, second half = 0.0
		return 1.0 if t < 0.5 else 0.0
