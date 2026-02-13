class_name PassageResponse
extends Node
## Modulates passage physics (spring stiffness, angular limits, damping)
## based on arousal level. When aroused, passages soften and dilate; when
## unaroused, they are tight and resist penetration.
##
## Also delivers arousal-contextual pain/pleasure through NerveSystem:
##   - Low arousal + forced entry → extra discomfort (pain)
##   - High arousal + contact → extra comfort (pleasure)
##
## Drives tunnel_pulse for rhythmic contractions when aroused.

signal dilation_changed(new_level: float)

# ── Dilation Tuning ──────────────────────────────────────────────────────────

@export_group("Dilation")
## Passage depth-chain spring stiffness at zero arousal (tight).
@export var base_stiffness: float = 12.0
## Passage depth-chain spring stiffness at full arousal (yielding).
@export var aroused_stiffness: float = 3.0
## Entrance ring spring stiffness at zero arousal.
@export var base_ring_stiffness: float = 18.0
## Entrance ring spring stiffness at full arousal.
@export var aroused_ring_stiffness: float = 5.0
## Passage angular limit (degrees) at zero arousal.
@export var base_angular_limit: float = 15.0
## Passage angular limit at full arousal.
@export var aroused_angular_limit: float = 30.0
## Entrance ring angular limit at zero arousal.
@export var base_ring_angular_limit: float = 10.0
## Entrance ring angular limit at full arousal.
@export var aroused_ring_angular_limit: float = 22.0
## Spring damping at zero arousal.
@export var base_damping: float = 4.0
## Spring damping at full arousal (less resistance to movement).
@export var aroused_damping: float = 1.5
## How fast dilation tracks arousal upward (per second).
@export_range(0.5, 5.0) var dilation_rise_speed: float = 2.0
## How fast dilation drops when arousal falls (per second).
@export_range(0.5, 5.0) var dilation_fall_speed: float = 1.0

# ── Pain / Pleasure Tuning ───────────────────────────────────────────────────

@export_group("Pain and Pleasure")
## Extra discomfort per passage impact when arousal is zero.
## Scaled down as arousal rises (arousal masks penetration pain).
@export var max_pain_per_impact: float = 8.0
## How much arousal reduces passage pain (1.0 = fully eliminated at peak).
@export_range(0.0, 1.0) var arousal_pain_reduction: float = 0.85
## Extra comfort delivered per passage contact when arousal is high.
@export var max_pleasure_per_contact: float = 3.0
## Arousal must exceed this to generate pleasure from passage contact.
@export_range(0.0, 1.0) var pleasure_arousal_threshold: float = 0.3

# ── Tunnel Pulse Tuning ─────────────────────────────────────────────────────

@export_group("Tunnel Pulse")
## Enable rhythmic passage contractions when aroused.
@export var tunnel_pulse_enabled: bool = true
## Pulse frequency in Hz.
@export_range(0.3, 2.0) var tunnel_pulse_frequency: float = 0.6
## Pulse amplitude (0–1 for shape key).
@export_range(0.0, 0.5) var tunnel_pulse_amplitude: float = 0.1
## Dilation must exceed this for pulse to activate.
@export_range(0.0, 1.0) var pulse_dilation_threshold: float = 0.3

# ── Active Grip Tuning ───────────────────────────────────────────────────────

@export_group("Active Grip")
## Enable active grip forces that squeeze inward on penetrating objects.
@export var grip_enabled: bool = true
## Maximum inward force (Newtons) per ring part when fully gripping.
@export var grip_force_max: float = 4.0
## Grip strength rises with arousal (involuntary contraction).
## At zero arousal, grip is this fraction of max.
@export_range(0.0, 1.0) var grip_base_fraction: float = 0.3
## How much the rhythmic pulse modulates grip (on top of baseline).
@export_range(0.0, 1.0) var grip_pulse_modulation: float = 0.4
## Only apply grip to ring levels where an overlapping body is detected
## within this radius from the ring centre (metres).
@export var grip_detection_radius: float = 0.03

# ── Runtime State ────────────────────────────────────────────────────────────

## Current dilation level (0.0 = tight, 1.0 = fully dilated).
var dilation_level: float = 0.0
## Current tunnel pulse value (0–1, for shape key driver).
var tunnel_pulse_value: float = 0.0

# ── Internal ─────────────────────────────────────────────────────────────────

var _arousal_system: ArousalSystem = null
var _nerve_system: NerveSystem = null
var _character_profile: Node = null  # CharacterProfile
## Passage depth-chain joints: { part_name: Generic6DOFJoint3D }
var _passage_joints: Dictionary = {}
## Entrance ring joints: { part_name: Generic6DOFJoint3D }
var _ring_joints: Dictionary = {}
## Cached passage BodyPart refs for grip force: { part_name: BodyPart }
var _passage_parts: Dictionary = {}
var _ring_parts: Dictionary = {}
var _pulse_time: float = 0.0
## Signal throttle.
var _prev_dilation_signal: float = -1.0
const SIGNAL_THRESHOLD: float = 0.005


## Wire up after ragdoll is built.
func setup(npc: Node, arousal: ArousalSystem) -> void:
	_arousal_system = arousal
	_nerve_system = npc.get("nerve_system") as NerveSystem
	_character_profile = npc.get("character_profile")

	# Cache passage and ring joints from ragdoll
	var ragdoll: HumanoidRagdollBuilder = npc.get("ragdoll") as HumanoidRagdollBuilder
	if ragdoll == null:
		return

	for part_name: String in ragdoll.child_to_joint:
		if part_name.contains("_passage_"):
			_passage_joints[part_name] = ragdoll.child_to_joint[part_name]
			if ragdoll.parts.has(part_name):
				_passage_parts[part_name] = ragdoll.parts[part_name]
		elif part_name.contains("_ring_"):
			_ring_joints[part_name] = ragdoll.child_to_joint[part_name]
			if ragdoll.parts.has(part_name):
				_ring_parts[part_name] = ragdoll.parts[part_name]

	# Connect to nerve system stimulation events for passage-specific pain/pleasure
	if _nerve_system != null:
		_nerve_system.stimulation_event.connect(_on_stimulation_event)

	var total_joints: int = _passage_joints.size() + _ring_joints.size()
	if total_joints > 0:
		print("[PassageResponse] Tracking %d passage joints + %d ring joints" % [
			_passage_joints.size(), _ring_joints.size()])


func _physics_process(delta: float) -> void:
	if _arousal_system == null:
		return

	# Dilation smoothly follows arousal
	var target: float = _arousal_system.arousal_level
	if target > dilation_level:
		dilation_level = minf(dilation_level + dilation_rise_speed * delta, target)
	else:
		dilation_level = maxf(dilation_level - dilation_fall_speed * delta, target)

	# Apply spring parameters to passage joints
	_update_passage_springs()

	# Tunnel pulse
	if tunnel_pulse_enabled and dilation_level > pulse_dilation_threshold:
		_pulse_time += delta * tunnel_pulse_frequency * TAU
		var strength: float = (dilation_level - pulse_dilation_threshold) \
			/ maxf(1.0 - pulse_dilation_threshold, 0.01)
		tunnel_pulse_value = maxf(sin(_pulse_time) * tunnel_pulse_amplitude * strength, 0.0)
	else:
		_pulse_time = 0.0
		tunnel_pulse_value = 0.0

	# Active grip
	if grip_enabled:
		_apply_grip_forces(delta)

	# Throttled signal
	if absf(dilation_level - _prev_dilation_signal) > SIGNAL_THRESHOLD:
		_prev_dilation_signal = dilation_level
		dilation_changed.emit(dilation_level)


## Apply interpolated spring stiffness, damping, and angular limits to joints.
func _update_passage_springs() -> void:
	var t: float = dilation_level

	# Depth chain joints
	var stiffness: float = lerpf(base_stiffness, aroused_stiffness, t)
	var damping: float = lerpf(base_damping, aroused_damping, t)
	var ang_limit: float = lerpf(base_angular_limit, aroused_angular_limit, t)

	for part_name: String in _passage_joints:
		var joint: Generic6DOFJoint3D = _passage_joints[part_name] as Generic6DOFJoint3D
		_set_spring_params(joint, stiffness, damping, ang_limit)

	# Entrance ring joints (stiffer baseline but still soften)
	var ring_stiff: float = lerpf(base_ring_stiffness, aroused_ring_stiffness, t)
	var ring_damp: float = lerpf(base_damping * 1.25, aroused_damping * 1.25, t)
	var ring_ang: float = lerpf(base_ring_angular_limit, aroused_ring_angular_limit, t)

	for part_name: String in _ring_joints:
		var joint: Generic6DOFJoint3D = _ring_joints[part_name] as Generic6DOFJoint3D
		_set_spring_params(joint, ring_stiff, ring_damp, ring_ang)


func _set_spring_params(joint: Generic6DOFJoint3D, stiffness: float,
		damping: float, ang_limit_deg: float) -> void:
	var limit_rad: float = deg_to_rad(ang_limit_deg)

	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)

	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)


## Apply inward grip forces on passage ring parts when something is between them.
## Uses a simple area-overlap heuristic: if any other body is within
## grip_detection_radius of the ring centre, apply inward force per quadrant.
## Force is modulated by arousal (involuntary clenching) and tunnel pulse.
func _apply_grip_forces(_delta: float) -> void:
	# Compute grip strength: baseline + arousal ramp + pulse modulation
	var arousal: float = _arousal_system.arousal_level if _arousal_system != null else 0.0
	var base_grip: float = grip_base_fraction
	var arousal_grip: float = (1.0 - grip_base_fraction) * arousal
	var pulse_grip: float = tunnel_pulse_value * grip_pulse_modulation
	var total_grip: float = clampf(base_grip + arousal_grip + pulse_grip, 0.0, 1.0)
	var force_magnitude: float = grip_force_max * total_grip

	if force_magnitude < 0.01:
		return

	# Group ring/passage parts by tunnel+depth to compute ring centres.
	# For each ring of 4, the centre is the average position.
	# Apply inward force (toward centre) on each quadrant part.
	var rings: Dictionary = {}  # "vaginal_0" → Array[BodyPart]
	for pname: String in _passage_parts:
		var bp: BodyPart = _passage_parts[pname] as BodyPart
		# Extract ring key: e.g. "vaginal_passage_3_top" → "vaginal_3"
		var bits: PackedStringArray = pname.split("_")
		if bits.size() >= 4:
			var ring_key: String = "%s_%s" % [bits[0], bits[2]]
			if not rings.has(ring_key):
				rings[ring_key] = [] as Array[BodyPart]
			(rings[ring_key] as Array[BodyPart]).append(bp)
	for pname: String in _ring_parts:
		var bp: BodyPart = _ring_parts[pname] as BodyPart
		var bits: PackedStringArray = pname.split("_")
		if bits.size() >= 3:
			var ring_key: String = "%s_ring" % bits[0]
			if not rings.has(ring_key):
				rings[ring_key] = [] as Array[BodyPart]
			(rings[ring_key] as Array[BodyPart]).append(bp)

	for ring_key: String in rings:
		var ring_bodies: Array[BodyPart] = rings[ring_key] as Array[BodyPart]
		if ring_bodies.size() < 2:
			continue
		# Compute centre of this ring
		var centre: Vector3 = Vector3.ZERO
		for bp: BodyPart in ring_bodies:
			centre += bp.global_position
		centre /= float(ring_bodies.size())

		# Check if anything foreign is near the ring centre using overlapping bodies
		var has_intruder: bool = false
		for bp: BodyPart in ring_bodies:
			var contacts: Array[Node3D] = bp.get_colliding_bodies()
			for contact: Node3D in contacts:
				if contact is BodyPart:
					var other: BodyPart = contact as BodyPart
					# Foreign body = not in this NPC's passage parts
					if not _passage_parts.has(other.part_name) \
							and not _ring_parts.has(other.part_name):
						has_intruder = true
						break
			if has_intruder:
				break

		if has_intruder:
			# Apply inward force on each ring part toward centre
			for bp: BodyPart in ring_bodies:
				var dir: Vector3 = (centre - bp.global_position).normalized()
				bp.apply_central_force(dir * force_magnitude)


## Intercept NerveSystem stimulation on passage parts to modulate pain/pleasure
## based on current arousal state.
func _on_stimulation_event(part_name: String, touch_type: NerveSystem.TouchType,
		intensity: float, _comfort_delta: float, _discomfort_delta: float) -> void:
	# Only respond to passage parts
	if not part_name.contains("_passage_") and not part_name.contains("_ring_"):
		return
	if _character_profile == null:
		return

	var arousal: float = _arousal_system.arousal_level if _arousal_system != null else 0.0

	# Extra pain on impact when arousal is low
	if touch_type == NerveSystem.TouchType.IMPACT \
			or touch_type == NerveSystem.TouchType.PUSH:
		var pain_scale: float = 1.0 - arousal * arousal_pain_reduction
		var extra_pain: float = max_pain_per_impact * pain_scale * intensity
		if extra_pain > 0.1:
			_character_profile.call(&"add_discomfort", extra_pain)

	# Extra pleasure on stroke/press when arousal is adequate
	if arousal > pleasure_arousal_threshold:
		if touch_type == NerveSystem.TouchType.STROKE \
				or touch_type == NerveSystem.TouchType.PRESS:
			var pleasure_scale: float = (arousal - pleasure_arousal_threshold) \
				/ maxf(1.0 - pleasure_arousal_threshold, 0.01)
			var extra_pleasure: float = max_pleasure_per_contact * pleasure_scale * intensity
			if extra_pleasure > 0.1:
				_character_profile.call(&"add_comfort", extra_pleasure)


## Get all tunable parameters as a Dictionary.
func get_params() -> Dictionary:
	return {
		"dilation_level": dilation_level,
		"tunnel_pulse_value": tunnel_pulse_value,
		"base_stiffness": base_stiffness,
		"aroused_stiffness": aroused_stiffness,
		"base_ring_stiffness": base_ring_stiffness,
		"aroused_ring_stiffness": aroused_ring_stiffness,
	}
