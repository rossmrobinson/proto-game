class_name ActionTempo
extends Resource
## Speed / depth / force / rhythm profile for an ActionMotion.
##
## The tempo controls HOW FAST, HOW DEEP, and HOW HARD the motion plays.
## Separated from the trajectory so you can pair any motion with any tempo
## (e.g. "circular_grind" + "aggressive" vs. "circular_grind" + "tender").

# ── Speed ────────────────────────────────────────────────────────────────────

@export_group("Speed")
## Base cycles per second (1.0 = one full stroke per second).
@export_range(0.05, 10.0) var cycles_per_second: float = 1.0
## Random ± jitter applied per-cycle to prevent robotic feel.
@export_range(0.0, 0.5) var speed_jitter: float = 0.05
## Ramp-up: how much cps increases per second of continuous play.
@export_range(0.0, 1.0) var acceleration: float = 0.0
## Hard cap on cps even with acceleration.
@export_range(0.1, 15.0) var max_cycles_per_second: float = 5.0

# ── Depth ────────────────────────────────────────────────────────────────────

@export_group("Depth")
## Minimum depth scalar (0 = surface, 1 = full amplitude).
@export_range(0.0, 1.0) var depth_min: float = 0.5
## Maximum depth scalar.
@export_range(0.0, 1.5) var depth_max: float = 1.0
## Per-stroke random depth variation.
@export_range(0.0, 0.5) var depth_jitter: float = 0.1

# ── Force ────────────────────────────────────────────────────────────────────

@export_group("Force")
## Impact force scalar (0 = none, 1 = full, >1 = slam).
@export_range(0.0, 2.0) var force: float = 0.5
## Duty cycle: fraction of stroke spent in the "active" phase vs. pause.
@export_range(0.1, 1.0) var duty_cycle: float = 0.8
## Extra seconds of pause between strokes (stacks with duty_cycle).
@export_range(0.0, 2.0) var inter_stroke_pause: float = 0.0

# ── Rhythm / BPM ─────────────────────────────────────────────────────────────

@export_group("Rhythm")
## Whether this tempo should lock to an external BPM source.
@export var sync_to_bpm: bool = false
## How many beats per motion cycle (1 = 1:1, 2 = half-time, 0.5 = double-time).
@export_range(0.25, 4.0) var beats_per_cycle: float = 1.0


## Get the effective speed at a given elapsed time (accounts for acceleration).
func get_speed_at(elapsed: float) -> float:
	var cps: float = cycles_per_second + acceleration * elapsed
	if speed_jitter > 0.0:
		cps += randf_range(-speed_jitter, speed_jitter)
	return clampf(cps, 0.05, max_cycles_per_second)


## Sample a random depth value within the configured range + jitter.
func sample_depth() -> float:
	var base: float = randf_range(depth_min, depth_max)
	if depth_jitter > 0.0:
		base += randf_range(-depth_jitter, depth_jitter)
	return clampf(base, 0.0, 1.5)


## Get force at a given elapsed time (currently constant, extensible).
func get_force_at(_elapsed: float) -> float:
	return force


## Factory method.
static func create(p_name: String, p_cps: float, p_depth_min: float,
		p_depth_max: float, p_force: float) -> ActionTempo:
	var t: ActionTempo = ActionTempo.new()
	t.cycles_per_second = p_cps
	t.depth_min = p_depth_min
	t.depth_max = p_depth_max
	t.force = p_force
	# Store name in metadata (resource_name)
	t.resource_name = p_name
	return t
