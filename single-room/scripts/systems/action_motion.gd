class_name ActionMotion
extends Resource
## Describes a continuous motion trajectory via joint oscillation channels.
##
## Each channel maps a joint_key to a periodic curve that produces
## additive angular offsets. Mix several channels together and you get a
## thrust, grind, bounce, bob, or any other repeating body motion.
##
## Evaluated at a "phase" value in [0,1] representing one full cycle.

# ── Curve types ──────────────────────────────────────────────────────────────
enum CurveType { SINE, TRIANGLE, SAWTOOTH, BOUNCE, SQUARE }

# ── Identity ─────────────────────────────────────────────────────────────────

@export_group("Identity")
## Human-readable name (e.g. "linear_thrust", "circular_grind").
@export var motion_name: String = ""
## Category tag for library queries.
@export var category: String = ""
## Which role this motion targets: "active" (thrusting) or "passive" (receiving).
@export var role: String = "active"

@export_group("Depth")
## Baseline minimum depth fraction (0 = surface, 1 = full penetration).
@export_range(0.0, 1.0) var base_depth_min: float = 0.3
## Baseline maximum depth fraction.
@export_range(0.0, 1.0) var base_depth_max: float = 1.0

@export_group("Mixing")
## Whether this motion can be additively composed with another.
@export var composable: bool = true
## Priority when two motions conflict on the same joint (higher wins).
@export var priority: int = 0

# ── Channel Data ─────────────────────────────────────────────────────────────
## Maps joint_key (String) → channel config (Dictionary).
## Channel config: { "axis": Vector3, "amplitude_deg": float,
##   "phase_offset": float, "curve": CurveType }
##
## axis: unit vector for rotation axis (x=pitch, y=yaw, z=roll).
## amplitude_deg: peak-to-peak angle in degrees.
## phase_offset: 0–1 offset from master phase (delays this channel).
## curve: which waveform drives the oscillation.
@export var channels: Dictionary = {}


## Evaluate all channels at the given phase, returning additive joint offsets.
## Returns Dictionary: joint_key → Vector3(degrees).
func evaluate(phase: float) -> Dictionary:
	var offsets: Dictionary = {}
	for joint_key: String in channels:
		var ch: Dictionary = channels[joint_key] as Dictionary
		var axis: Vector3 = ch.get("axis", Vector3.RIGHT) as Vector3
		var amp: float = ch.get("amplitude_deg", 10.0) as float
		var offset: float = ch.get("phase_offset", 0.0) as float
		var curve_type: int = ch.get("curve", CurveType.SINE) as int
		var p: float = fmod(phase + offset, 1.0)
		var value: float = _eval_curve(p, curve_type) * amp
		offsets[joint_key] = axis * value
	return offsets


## Evaluate a single curve type at phase p ∈ [0,1]. Returns [-1, 1].
func _eval_curve(p: float, curve_type: int) -> float:
	match curve_type:
		CurveType.SINE:
			return sin(p * TAU)
		CurveType.TRIANGLE:
			# Triangle: 0→1 over [0,0.25], 1→-1 over [0.25,0.75], -1→0 over [0.75,1]
			if p < 0.25:
				return p * 4.0
			elif p < 0.75:
				return 1.0 - (p - 0.25) * 4.0
			else:
				return -1.0 + (p - 0.75) * 4.0
		CurveType.SAWTOOTH:
			return 2.0 * p - 1.0
		CurveType.BOUNCE:
			# Absolute sine — always positive, bouncy feel.
			return absf(sin(p * TAU))
		CurveType.SQUARE:
			return 1.0 if p < 0.5 else -1.0
	return 0.0


## Factory method.
static func create(p_name: String, p_category: String, p_role: String,
		p_channels: Dictionary) -> ActionMotion:
	var m: ActionMotion = ActionMotion.new()
	m.motion_name = p_name
	m.category = p_category
	m.role = p_role
	m.channels = p_channels
	return m
