class_name GripPressureSystem
extends Node
## Tracks external grip (squeeze) on penis segments.
##
## Borrows the same pressure-ramp architecture as ConstrictionSystem but maps
## output to arousal/pleasure rather than airway restriction.
##
## Outputs:
##   grip_pressure    — 0.0 – 1.0 (combined from all grabbed segments)
##   squeeze_pleasure — comfort delta per tick (fed to CharacterProfile)
##   squeeze_pain     — discomfort delta per tick (fed to CharacterProfile)
##
## Feeds into:
##   - NerveSystem (per-segment PRESS stimulation)
##   - CharacterProfile (comfort / discomfort)
##   - ArousalSystem (arousal boost from penile stimulation)
##   - Erection physics (ArousalSystem grab_stiffness_factor handles softening)

# ── Signals ──────────────────────────────────────────────────────────────────
signal grip_started()
signal grip_ended()
signal grip_pressure_changed(pressure: float)
## Emitted when grip pain crosses the pain threshold.
signal pain_spike(intensity: float)

# ── Segment Names ────────────────────────────────────────────────────────────
const PENIS_SEGMENTS: Array[String] = ["penis_base", "penis_mid", "penis_tip"]

# ── Pressure Tuning ──────────────────────────────────────────────────────────
@export_group("Pressure Tuning")
## How quickly grip pressure ramps toward target (per second).
@export var pressure_ramp_speed: float = 5.0
## How quickly grip pressure decays on release (per second).
@export var pressure_release_speed: float = 8.0
## Weight of each segment in the combined pressure.
## More sensitive tip contributes proportionally more.
@export var segment_weights: Dictionary = {
	"penis_base": 0.2,
	"penis_mid": 0.35,
	"penis_tip": 0.45,
}

# ── Pleasure / Pain Curve ────────────────────────────────────────────────────
@export_group("Pleasure / Pain Curve")
## Pressure range that delivers maximum pleasure (light-to-moderate grip).
@export_range(0.0, 1.0) var pleasure_peak_pressure: float = 0.45
## Width of the pleasure bell curve (std deviation).
@export_range(0.05, 0.5) var pleasure_curve_width: float = 0.2
## Maximum pleasure (comfort) per second at the sweet spot.
@export var max_pleasure_per_second: float = 8.0
## Pressure threshold above which pain begins.
@export_range(0.0, 1.0) var pain_threshold: float = 0.7
## Maximum pain (discomfort) per second at full crush.
@export var max_pain_per_second: float = 15.0
## How much arousal is boosted per second at peak pleasure pressure.
@export var arousal_boost_per_second: float = 0.06

# ── Nerve Tuning ─────────────────────────────────────────────────────────────
@export_group("Nerve Tuning")
## Nerve touch intensity scale per tick while gripped (per segment).
@export var nerve_intensity_scale: float = 0.5
## Additional sensitivity multiplier for the tip segment.
@export var tip_sensitivity_bonus: float = 1.3

# ── Stroke Detection ────────────────────────────────────────────────────────
@export_group("Stroke Detection")
## Velocity threshold (m/s) along the shaft axis that counts as a stroke.
@export var stroke_velocity_threshold: float = 0.15
## Cooldown between stroke events (seconds).
@export var stroke_cooldown: float = 0.08
## Pleasure multiplier for stroke vs static grip.
@export var stroke_pleasure_multiplier: float = 1.8

# ── Runtime State ────────────────────────────────────────────────────────────
## Per-segment grab state (true if that segment is currently grabbed).
var segment_grabbed: Dictionary = {
	"penis_base": false,
	"penis_mid": false,
	"penis_tip": false,
}
## Per-segment current pressure (0–1).
var segment_pressure: Dictionary = {
	"penis_base": 0.0,
	"penis_mid": 0.0,
	"penis_tip": 0.0,
}
## Combined weighted grip pressure (0–1).
var grip_pressure: float = 0.0
## True while any segment is grabbed.
var is_gripped: bool = false
## Accumulated stroke cooldown timer.
var _stroke_cd: float = 0.0

# ── Internal ─────────────────────────────────────────────────────────────────
var _character_profile: CharacterProfile = null
var _nerve_system: NerveSystem = null
var _arousal_system: Node = null  # ArousalSystem — loosely typed to avoid load order
var _ragdoll: HumanoidRagdollBuilder = null
var _prev_positions: Dictionary = {}  # segment_name → Vector3


func setup(npc_root: Node3D) -> void:
	for child: Node in npc_root.get_children():
		if child is CharacterProfile:
			_character_profile = child as CharacterProfile
		elif child is NerveSystem:
			_nerve_system = child as NerveSystem
		elif child is HumanoidRagdollBuilder:
			_ragdoll = child as HumanoidRagdollBuilder
		elif child.get_script() != null and child.has_method(&"_update_erection"):
			_arousal_system = child

	# Connect grab/release signals on each penis segment
	if _ragdoll == null:
		return
	for seg_name: String in PENIS_SEGMENTS:
		if not _ragdoll.parts.has(seg_name):
			continue
		var part: BodyPart = _ragdoll.parts[seg_name] as BodyPart
		part.part_grabbed.connect(_on_segment_grabbed.bind(seg_name))
		part.part_released.connect(_on_segment_released.bind(seg_name))
		# Cache initial position for stroke detection
		var rb: RigidBody3D = part as RigidBody3D
		if rb != null:
			_prev_positions[seg_name] = rb.global_position


func _on_segment_grabbed(_part_name: String, _by: Node3D,
		seg_name: String) -> void:
	segment_grabbed[seg_name] = true


func _on_segment_released(_part_name: String, _by: Node3D,
		seg_name: String) -> void:
	segment_grabbed[seg_name] = false


func _physics_process(delta: float) -> void:
	_update_segment_pressures(delta)
	_update_combined_pressure()
	_update_nerve_feedback(delta)
	_update_pleasure_pain(delta)
	_detect_strokes(delta)


func _update_segment_pressures(delta: float) -> void:
	for seg_name: String in PENIS_SEGMENTS:
		var is_held: bool = segment_grabbed[seg_name] as bool
		var target: float = 1.0 if is_held else 0.0
		var current: float = segment_pressure[seg_name] as float
		if target > current:
			segment_pressure[seg_name] = minf(
				current + pressure_ramp_speed * delta, target)
		elif target < current:
			segment_pressure[seg_name] = maxf(
				current - pressure_release_speed * delta, target)


func _update_combined_pressure() -> void:
	var prev: float = grip_pressure
	var total: float = 0.0
	for seg_name: String in PENIS_SEGMENTS:
		var weight: float = segment_weights.get(seg_name, 0.33) as float
		total += (segment_pressure[seg_name] as float) * weight
	grip_pressure = clampf(total, 0.0, 1.0)

	# State transitions
	var was: bool = is_gripped
	is_gripped = grip_pressure > 0.01
	if is_gripped and not was:
		grip_started.emit()
	elif not is_gripped and was:
		grip_ended.emit()
	if absf(grip_pressure - prev) > 0.001:
		grip_pressure_changed.emit(grip_pressure)


func _update_nerve_feedback(_delta: float) -> void:
	if _nerve_system == null:
		return
	for seg_name: String in PENIS_SEGMENTS:
		var pressure: float = segment_pressure[seg_name] as float
		if pressure < 0.01:
			continue
		var intensity: float = pressure * nerve_intensity_scale
		if seg_name == "penis_tip":
			intensity *= tip_sensitivity_bonus
		_nerve_system.receive_touch(seg_name, NerveSystem.TouchType.PRESS, intensity)


func _update_pleasure_pain(delta: float) -> void:
	if _character_profile == null:
		return
	if grip_pressure < 0.01:
		return

	# Pleasure uses a Gaussian bell curve centred on pleasure_peak_pressure
	var diff: float = grip_pressure - pleasure_peak_pressure
	var pleasure_t: float = exp(-(diff * diff) / (2.0 * pleasure_curve_width \
		* pleasure_curve_width))
	_character_profile.add_comfort(max_pleasure_per_second * pleasure_t * delta)

	# Arousal boost proportional to pleasure
	if _arousal_system != null and _arousal_system.has_method(&"set_arousal"):
		var current_arousal: float = _arousal_system.get(&"arousal_level") as float
		_arousal_system.call(&"set_arousal",
			current_arousal + arousal_boost_per_second * pleasure_t * delta)

	# Pain above threshold — linear ramp
	if grip_pressure > pain_threshold:
		var pain_t: float = (grip_pressure - pain_threshold) \
			/ (1.0 - pain_threshold)
		var pain_amount: float = max_pain_per_second * pain_t * delta
		_character_profile.add_discomfort(pain_amount)
		if pain_t > 0.5:
			pain_spike.emit(pain_t)


func _detect_strokes(delta: float) -> void:
	if _ragdoll == null or _nerve_system == null:
		return
	_stroke_cd = maxf(_stroke_cd - delta, 0.0)
	if _stroke_cd > 0.0:
		return

	# Check shaft-axis velocity on grabbed mid segment (most representative)
	if not (segment_grabbed["penis_mid"] as bool):
		return
	if not _ragdoll.parts.has("penis_mid"):
		return
	var mid_rb: RigidBody3D = _ragdoll.parts["penis_mid"] as RigidBody3D
	if mid_rb == null:
		return

	var current_pos: Vector3 = mid_rb.global_position
	var prev_pos: Vector3 = _prev_positions.get("penis_mid",
		current_pos) as Vector3
	var velocity: Vector3 = (current_pos - prev_pos) / maxf(delta, 0.001)
	_prev_positions["penis_mid"] = current_pos

	# Use the shaft direction (base → tip) as the stroke axis
	if not _ragdoll.parts.has("penis_base") or not _ragdoll.parts.has("penis_tip"):
		return
	var base_pos: Vector3 = (_ragdoll.parts["penis_base"] as RigidBody3D) \
		.global_position
	var tip_pos: Vector3 = (_ragdoll.parts["penis_tip"] as RigidBody3D) \
		.global_position
	var shaft_dir: Vector3 = (tip_pos - base_pos).normalized()
	var axial_speed: float = absf(velocity.dot(shaft_dir))

	if axial_speed >= stroke_velocity_threshold:
		_stroke_cd = stroke_cooldown
		var intensity: float = clampf(axial_speed / (stroke_velocity_threshold * 3.0),
			0.0, 1.0) * nerve_intensity_scale * stroke_pleasure_multiplier
		_nerve_system.receive_touch("penis_mid", NerveSystem.TouchType.STROKE,
			intensity)
		# Bonus comfort from stroking (one-shot per stroke event)
		if _character_profile != null:
			_character_profile.add_comfort(
				max_pleasure_per_second * stroke_pleasure_multiplier * 0.3 \
				* stroke_cooldown)
