class_name ArousalSystem
extends Node
## Tracks arousal state for an NPC. Drives erection physics (joint stiffness,
## angular limits) and throbbing. Provides arousal/erection/throb data for
## ShapeKeyDriver and PassageResponse.
##
## Listens to NerveSystem.stimulation_event for genital/erogenous parts.
## Updates penis joint spring parameters every physics frame.

signal arousal_changed(new_level: float)
signal erection_changed(new_level: float)
signal nipple_erection_changed(new_level: float)
signal throb_pulse(phase: float)
## Emitted once when arousal reaches orgasm threshold and refractory begins.
## intensity: 0.0–2.0+ scale factor (1.0 = baseline, higher = stronger).
signal orgasm_started(intensity: float)

# ── Arousal Tuning ───────────────────────────────────────────────────────────

@export_group("Arousal")
## How fast arousal builds from stimulation (per unit of comfort delta).
@export_range(0.01, 2.0) var arousal_gain_rate: float = 0.4
## How fast arousal decays when not stimulated (per second).
@export_range(0.01, 1.0) var arousal_decay_rate: float = 0.05
## Parts that contribute to genital arousal (primary).
@export var primary_parts: PackedStringArray = [
	"penis_base", "penis_mid", "penis_tip",
	"scrotum_left", "scrotum_right",
	"clitoris", "labia_left", "labia_right",
]
## Parts that contribute to arousal at reduced rate (secondary).
@export var secondary_parts: PackedStringArray = [
	"left_breast_nipple", "right_breast_nipple",
	"left_inner_glute", "right_inner_glute",
	"neck",
]
## Secondary parts contribute at this fraction of primary rate.
@export_range(0.0, 1.0) var secondary_multiplier: float = 0.3
## Passage stimulation contributes to arousal at this fraction.
@export_range(0.0, 1.0) var passage_multiplier: float = 0.6

# ── Erection Tuning ─────────────────────────────────────────────────────────

@export_group("Erection")
## Arousal level at which erection begins (semi-erect).
@export_range(0.0, 1.0) var erection_onset: float = 0.2
## Arousal level at which erection is fully hard.
@export_range(0.0, 1.0) var erection_full: float = 0.75
## How fast erection follows arousal upward (per second).
@export_range(0.1, 5.0) var erection_rise_speed: float = 0.8
## How fast erection drops when arousal falls (per second).
@export_range(0.1, 5.0) var erection_fall_speed: float = 0.3

# ── Throbbing Tuning ────────────────────────────────────────────────────────

@export_group("Throbbing")
## Enable throbbing when erection is high.
@export var throbbing_enabled: bool = true
## Erection level above which throbbing starts.
@export_range(0.0, 1.0) var throb_erection_threshold: float = 0.85
## Throb frequency in Hz (heartbeat-like, 60–90 BPM).
@export_range(0.5, 3.0) var throb_frequency: float = 1.2
## Throb amplitude (modulates shape key and physics spring).
@export_range(0.0, 1.0) var throb_amplitude: float = 0.15

# ── Erection Physics Tuning ─────────────────────────────────────────────────

@export_group("Erection Physics")
## Penis base spring stiffness: flaccid → erect.
@export var flaccid_base_stiffness: float = 5.0
@export var erect_base_stiffness: float = 45.0
## Penis mid spring stiffness: flaccid → erect.
@export var flaccid_mid_stiffness: float = 4.0
@export var erect_mid_stiffness: float = 40.0
## Penis tip spring stiffness: flaccid → erect.
@export var flaccid_tip_stiffness: float = 3.5
@export var erect_tip_stiffness: float = 35.0
## Base angular limit (degrees) flaccid → erect.
@export var flaccid_base_angular_limit: float = 90.0
@export var erect_base_angular_limit: float = 15.0
## Mid angular limit (degrees) flaccid → erect.
@export var flaccid_mid_angular_limit: float = 40.0
@export var erect_mid_angular_limit: float = 10.0
## Tip angular limit (degrees) flaccid → erect.
@export var flaccid_tip_angular_limit: float = 30.0
@export var erect_tip_angular_limit: float = 8.0
## Damping multiplier when fully erect (reduces wobble).
@export_range(1.0, 5.0) var erect_damping_multiplier: float = 3.0
## Base spring damping values (flaccid).
@export var flaccid_base_damping: float = 1.2
@export var flaccid_mid_damping: float = 1.0
@export var flaccid_tip_damping: float = 0.8

@export_group("Nipple Arousal")
## Arousal level at which nipples begin to harden.
@export_range(0.0, 1.0) var nipple_onset: float = 0.1
## Arousal level at which nipples are fully erect.
@export_range(0.0, 1.0) var nipple_full: float = 0.55
## Nipple joint spring stiffness when soft.
@export var nipple_soft_stiffness: float = 15.0
## Nipple joint spring stiffness when fully erect.
@export var nipple_erect_stiffness: float = 35.0
## Nipple joint spring damping when soft.
@export var nipple_soft_damping: float = 3.0
## Nipple joint spring damping when erect.
@export var nipple_erect_damping: float = 6.0
## Nipple angular limit (degrees) when soft.
@export var nipple_soft_angular_limit: float = 5.0
## Nipple angular limit when erect (tighter — nipple stands firm).
@export var nipple_erect_angular_limit: float = 2.0
## Rise/fall speeds for nipple erection.
@export_range(0.5, 5.0) var nipple_rise_speed: float = 1.5
@export_range(0.5, 5.0) var nipple_fall_speed: float = 0.6
## Local stimulation on nipple also drives nipple erection independently.
## This fraction is added on top of the arousal-based nipple state.
@export_range(0.0, 1.0) var nipple_local_stim_weight: float = 0.4

@export_group("Scrotum")
## How much scrotum draws up at full erection (0 = stays relaxed, 1 = fully tight).
@export_range(0.0, 1.0) var scrotum_tension_at_full_erection: float = 0.8

@export_group("Orgasm")
## Arousal level that triggers orgasm.
@export_range(0.8, 1.0) var orgasm_threshold: float = 0.95
## Duration (seconds) of the refractory period after orgasm.
@export_range(1.0, 60.0) var refractory_duration: float = 15.0
## Arousal drops to this level after orgasm.
@export_range(0.0, 0.5) var post_orgasm_arousal: float = 0.15
## Random intensity variance (±). A value of 0.3 means intensity varies ±30%.
@export_range(0.0, 0.5) var orgasm_random_variance: float = 0.25
## Seconds of sustained high-arousal needed to reach max intensity bonus.
@export_range(1.0, 120.0) var sustained_pleasure_cap: float = 30.0
## Maximum bonus multiplier from sustained high arousal.
@export_range(0.0, 1.5) var sustained_pleasure_bonus: float = 0.6
## Bonus intensity per active participant beyond the first.
@export_range(0.0, 0.5) var participant_bonus_each: float = 0.15

@export_group("Cooldown Bypass")
## When true, refractory period is drastically shortened (gameplay mode).
@export var cooldown_bypass: bool = false
## Refractory duration when bypass is active (seconds).
@export_range(0.0, 5.0) var bypass_refractory_duration: float = 1.0
## Refractory decay multiplier when bypass is active.
@export_range(1.0, 20.0) var bypass_decay_multiplier: float = 8.0

@export_group("Grab Override")
## Factor applied to erection stiffness while any penis part is grabbed.
## Lower = easier to manually bend. 0.25 means 25% of normal stiffness.
@export_range(0.0, 1.0) var grab_stiffness_factor: float = 0.25
## Multiplier on angular limits while grabbed. 3.0 = triple the angular range.
@export_range(1.0, 6.0) var grab_limit_multiplier: float = 3.0
## How quickly the stiffness blends toward the grab-softened value (per second).
@export_range(1.0, 20.0) var grab_blend_speed: float = 8.0

# ── Runtime State ────────────────────────────────────────────────────────────

## Current arousal level (0.0 = none, 1.0 = peak).
var arousal_level: float = 0.0
## Current erection level (0.0 = flaccid, 1.0 = fully erect).
var erection_level: float = 0.0
## Current throb phase (0.0–1.0 cyclic).
var throb_phase: float = 0.0
## Current throb value (raw sine × amplitude, can be slightly negative).
var throb_value: float = 0.0
## Scrotum tension (0.0 = relaxed, 1.0 = fully drawn up).
var scrotum_tension: float = 0.0
## Current nipple erection level (0.0 = soft, 1.0 = fully hard).
var nipple_erection: float = 0.0
## Whether currently in refractory period after orgasm.
var in_refractory: bool = false
## Time remaining in refractory period.
var _refractory_timer: float = 0.0
## Last computed orgasm intensity (0.0–2.0+).
var last_orgasm_intensity: float = 0.0
## How long arousal has been above orgasm_threshold continuously (seconds).
var _sustained_high_time: float = 0.0
## Number of participants currently interacting with this NPC.
var _active_participant_count: int = 1

# ── Internal ─────────────────────────────────────────────────────────────────

var _has_penis: bool = false
## Cached joint references: "penis_base" / "penis_mid" / "penis_tip" → joint.
var _penis_joints: Dictionary = {}
## Cached penis BodyPart references for grab detection.
var _penis_parts: Dictionary = {}
## Current grab-blend factor (0 = normal, 1 = fully softened).
var _grab_blend: float = 0.0
## Cached nipple joint references: "left_breast_nipple" / "right_breast_nipple" → joint.
var _nipple_joints: Dictionary = {}
var _nerve_system: NerveSystem = null
var _throb_time: float = 0.0
## Fast lookup for passage part names.
var _passage_part_names: Dictionary = {}
## Previous values for signal throttling.
var _prev_arousal_signal: float = -1.0
var _prev_erection_signal: float = -1.0
var _prev_nipple_signal: float = -1.0
## Minimum change to emit a signal (avoids per-frame spam).
const SIGNAL_THRESHOLD: float = 0.005


## Wire up to an NPC's subsystems. Call after ragdoll is built.
func setup(npc: Node) -> void:
	# Find NerveSystem
	_nerve_system = npc.get("nerve_system") as NerveSystem
	if _nerve_system != null:
		_nerve_system.stimulation_event.connect(_on_stimulation_event)

	# Cache penis joints from ragdoll
	var ragdoll: HumanoidRagdollBuilder = npc.get("ragdoll") as HumanoidRagdollBuilder
	if ragdoll == null:
		return

	_has_penis = ragdoll.parts.has("penis_base")
	if _has_penis:
		for pname: String in ["penis_base", "penis_mid", "penis_tip"]:
			if ragdoll.child_to_joint.has(pname):
				_penis_joints[pname] = ragdoll.child_to_joint[pname]
			if ragdoll.parts.has(pname):
				_penis_parts[pname] = ragdoll.parts[pname]

	# Cache nipple joints
	for nip_name: String in ["left_breast_nipple", "right_breast_nipple"]:
		if ragdoll.child_to_joint.has(nip_name):
			_nipple_joints[nip_name] = ragdoll.child_to_joint[nip_name]

	# Build passage-part lookup for arousal contribution
	for part_key: String in ragdoll.parts:
		if part_key.begins_with("vaginal_passage_") or part_key.begins_with("anal_passage_") \
				or part_key.begins_with("vaginal_ring_") or part_key.begins_with("anal_ring_"):
			_passage_part_names[part_key] = true


func _physics_process(delta: float) -> void:
	# Refractory period — suppresses arousal gain
	if in_refractory:
		_refractory_timer -= delta
		if _refractory_timer <= 0.0:
			in_refractory = false

	# Track sustained high arousal for intensity bonus
	if arousal_level >= orgasm_threshold * 0.9:
		_sustained_high_time += delta
	else:
		_sustained_high_time = maxf(_sustained_high_time - delta * 2.0, 0.0)

	# Natural decay
	if arousal_level > 0.0:
		var decay: float = arousal_decay_rate
		if in_refractory:
			var refract_mult: float = bypass_decay_multiplier if cooldown_bypass else 3.0
			decay *= refract_mult
		arousal_level = maxf(arousal_level - decay * delta, 0.0)

	# Orgasm check — only when not already in refractory
	if not in_refractory and arousal_level >= orgasm_threshold:
		_trigger_orgasm()

	# Erection tracks arousal with lag
	var target_erection: float = _arousal_to_erection(arousal_level)
	if target_erection > erection_level:
		erection_level = minf(erection_level + erection_rise_speed * delta, target_erection)
	else:
		erection_level = maxf(erection_level - erection_fall_speed * delta, target_erection)

	# Scrotum tension follows erection
	scrotum_tension = erection_level * scrotum_tension_at_full_erection

	# Nipple erection — driven by arousal + local stimulation
	var nipple_target: float = _arousal_to_nipple(arousal_level)
	# Blend in local nipple stimulation (either side)
	if _nerve_system != null:
		var left_stim: float = _nerve_system.get_stimulation("left_breast_nipple")
		var right_stim: float = _nerve_system.get_stimulation("right_breast_nipple")
		var local: float = maxf(left_stim, right_stim) * nipple_local_stim_weight
		nipple_target = clampf(nipple_target + local, 0.0, 1.0)
	if nipple_target > nipple_erection:
		nipple_erection = minf(nipple_erection + nipple_rise_speed * delta, nipple_target)
	else:
		nipple_erection = maxf(nipple_erection - nipple_fall_speed * delta, nipple_target)
	_update_nipple_physics()

	# Throbbing
	if throbbing_enabled and erection_level >= throb_erection_threshold:
		_throb_time += delta * throb_frequency * TAU
		throb_phase = fmod(_throb_time, TAU) / TAU
		throb_value = sin(_throb_time) * throb_amplitude
		throb_pulse.emit(throb_phase)
	else:
		_throb_time = 0.0
		throb_phase = 0.0
		throb_value = 0.0

	# Update erection physics on penis joints
	if _has_penis:
		_update_grab_blend(delta)
		_update_erection_physics()

	# Throttled signals
	if absf(arousal_level - _prev_arousal_signal) > SIGNAL_THRESHOLD:
		_prev_arousal_signal = arousal_level
		arousal_changed.emit(arousal_level)
	if absf(erection_level - _prev_erection_signal) > SIGNAL_THRESHOLD:
		_prev_erection_signal = erection_level
		erection_changed.emit(erection_level)
	if absf(nipple_erection - _prev_nipple_signal) > SIGNAL_THRESHOLD:
		_prev_nipple_signal = nipple_erection
		nipple_erection_changed.emit(nipple_erection)


## Convert arousal (0–1) to target erection (0–1) via onset/full thresholds.
func _arousal_to_erection(arousal: float) -> float:
	if arousal < erection_onset:
		return 0.0
	if arousal >= erection_full:
		return 1.0
	return (arousal - erection_onset) / (erection_full - erection_onset)


## Fire orgasm event, begin refractory, and drop arousal.
func _trigger_orgasm() -> void:
	# Compute intensity
	var intensity: float = _compute_orgasm_intensity()
	last_orgasm_intensity = intensity

	in_refractory = true
	_refractory_timer = bypass_refractory_duration if cooldown_bypass else refractory_duration
	orgasm_started.emit(intensity)
	# Drop arousal — stronger orgasm drops further
	arousal_level = post_orgasm_arousal * (1.0 / maxf(intensity, 0.5))
	# Reset sustained counter
	_sustained_high_time = 0.0


## Compute orgasm intensity from sustained pleasure, participant count, and randomness.
## Returns 0.3–2.0+ (1.0 = baseline average).
func _compute_orgasm_intensity() -> float:
	# Base: 1.0
	var base: float = 1.0

	# Sustained pleasure bonus (0 → sustained_pleasure_bonus over sustained_pleasure_cap seconds)
	var sustained_t: float = clampf(_sustained_high_time / sustained_pleasure_cap, 0.0, 1.0)
	var sustained_bonus: float = sustained_pleasure_bonus * sustained_t

	# Participant bonus (each beyond the first adds participant_bonus_each)
	var participant_add: float = maxf(float(_active_participant_count) - 1.0, 0.0) \
		* participant_bonus_each

	# Random factor: ±variance
	var rng_offset: float = randf_range(-orgasm_random_variance, orgasm_random_variance)

	var intensity: float = base + sustained_bonus + participant_add + rng_offset
	return maxf(intensity, 0.3)


## Set the number of active participants (called by orchestrator / interaction system).
func set_participant_count(count: int) -> void:
	_active_participant_count = maxi(count, 1)


## Apply spring stiffness and angular limits to penis joints based on erection.
## When a penis part is grabbed, blends toward softer values so the player
## can manually bend and guide it.
func _update_erection_physics() -> void:
	var t: float = erection_level
	var throb_mod: float = throb_value
	var gb: float = _grab_blend  # 0 = normal erection, 1 = grab-softened

	# Base joint
	if _penis_joints.has("penis_base"):
		var joint: Generic6DOFJoint3D = _penis_joints["penis_base"] as Generic6DOFJoint3D
		var stiffness: float = lerpf(flaccid_base_stiffness, erect_base_stiffness, t) \
			+ throb_mod * 5.0
		var damping: float = lerpf(flaccid_base_damping,
			flaccid_base_damping * erect_damping_multiplier, t)
		var ang_limit: float = lerpf(flaccid_base_angular_limit, erect_base_angular_limit, t)
		stiffness = lerpf(stiffness, stiffness * grab_stiffness_factor, gb)
		ang_limit = lerpf(ang_limit, ang_limit * grab_limit_multiplier, gb)
		_set_joint_spring(joint, stiffness, damping)
		_set_joint_angular_limits(joint, ang_limit)

	# Mid joint
	if _penis_joints.has("penis_mid"):
		var joint: Generic6DOFJoint3D = _penis_joints["penis_mid"] as Generic6DOFJoint3D
		var stiffness: float = lerpf(flaccid_mid_stiffness, erect_mid_stiffness, t) \
			+ throb_mod * 3.0
		var damping: float = lerpf(flaccid_mid_damping,
			flaccid_mid_damping * erect_damping_multiplier, t)
		var ang_limit: float = lerpf(flaccid_mid_angular_limit, erect_mid_angular_limit, t)
		stiffness = lerpf(stiffness, stiffness * grab_stiffness_factor, gb)
		ang_limit = lerpf(ang_limit, ang_limit * grab_limit_multiplier, gb)
		_set_joint_spring(joint, stiffness, damping)
		_set_joint_angular_limits(joint, ang_limit)

	# Tip joint
	if _penis_joints.has("penis_tip"):
		var joint: Generic6DOFJoint3D = _penis_joints["penis_tip"] as Generic6DOFJoint3D
		var stiffness: float = lerpf(flaccid_tip_stiffness, erect_tip_stiffness, t) \
			+ throb_mod * 2.0
		var damping: float = lerpf(flaccid_tip_damping,
			flaccid_tip_damping * erect_damping_multiplier, t)
		var ang_limit: float = lerpf(flaccid_tip_angular_limit, erect_tip_angular_limit, t)
		stiffness = lerpf(stiffness, stiffness * grab_stiffness_factor, gb)
		ang_limit = lerpf(ang_limit, ang_limit * grab_limit_multiplier, gb)
		_set_joint_spring(joint, stiffness, damping)
		_set_joint_angular_limits(joint, ang_limit)


## Smoothly blend _grab_blend toward 1 when any penis part is grabbed,
## or back toward 0 when released.
func _update_grab_blend(delta: float) -> void:
	var target: float = 1.0 if _is_penis_grabbed() else 0.0
	_grab_blend = move_toward(_grab_blend, target, grab_blend_speed * delta)


## Returns true if any penis BodyPart is currently held by a grabber.
func _is_penis_grabbed() -> bool:
	for pname: String in _penis_parts:
		var part: BodyPart = _penis_parts[pname] as BodyPart
		if part != null and part.grabbed_by != null:
			return true
	return false


## Set angular spring stiffness + damping on all 3 axes of a 6DOF joint.
func _set_joint_spring(joint: Generic6DOFJoint3D, stiffness: float,
		damping: float) -> void:
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, stiffness)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, damping)


## Set symmetric angular limits (±limit_deg) on all 3 axes.
func _set_joint_angular_limits(joint: Generic6DOFJoint3D,
		limit_deg: float) -> void:
	var limit_rad: float = deg_to_rad(limit_deg)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit_rad)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit_rad)


## Convert arousal (0–1) to target nipple erection (0–1) via onset/full.
func _arousal_to_nipple(arousal: float) -> float:
	if arousal < nipple_onset:
		return 0.0
	if arousal >= nipple_full:
		return 1.0
	return (arousal - nipple_onset) / (nipple_full - nipple_onset)


## Apply spring stiffness and angular limits to nipple joints.
func _update_nipple_physics() -> void:
	var t: float = nipple_erection
	var stiffness: float = lerpf(nipple_soft_stiffness, nipple_erect_stiffness, t)
	var damping: float = lerpf(nipple_soft_damping, nipple_erect_damping, t)
	var ang_limit: float = lerpf(nipple_soft_angular_limit, nipple_erect_angular_limit, t)
	for nip_name: String in _nipple_joints:
		var joint: Generic6DOFJoint3D = _nipple_joints[nip_name] as Generic6DOFJoint3D
		_set_joint_spring(joint, stiffness, damping)
		_set_joint_angular_limits(joint, ang_limit)


## Handle NerveSystem stimulation events — route to arousal accumulator.
func _on_stimulation_event(part_name: String, _touch_type: NerveSystem.TouchType,
		_intensity: float, comfort_delta: float, _discomfort_delta: float) -> void:
	# Only positive comfort contributes to arousal
	if comfort_delta <= 0.0:
		return
	# Refractory period suppresses arousal gain (bypass allows reduced gain)
	if in_refractory:
		if not cooldown_bypass:
			return
		# With bypass, allow 20% of normal gain so player isn't stuck waiting
		comfort_delta *= 0.2

	var multiplier: float = 0.0
	if part_name in primary_parts:
		multiplier = 1.0
	elif part_name in secondary_parts:
		multiplier = secondary_multiplier
	elif _passage_part_names.has(part_name):
		multiplier = passage_multiplier
	else:
		return

	var gain: float = comfort_delta * arousal_gain_rate * multiplier
	arousal_level = clampf(arousal_level + gain, 0.0, 1.0)


## Force-set arousal level (for debug/cutscenes).
func set_arousal(value: float) -> void:
	arousal_level = clampf(value, 0.0, 1.0)


## Get erection as a readable label for diagnostics.
func get_erection_label() -> String:
	if erection_level < 0.05:
		return "flaccid"
	elif erection_level < 0.5:
		return "semi-erect (%d%%)" % roundi(erection_level * 100.0)
	elif erection_level < 0.95:
		return "erect (%d%%)" % roundi(erection_level * 100.0)
	else:
		return "fully erect"


## Get all tunable parameters as a Dictionary (for UI panels / LLM).
func get_params() -> Dictionary:
	return {
		"arousal_level": arousal_level,
		"erection_level": erection_level,
		"nipple_erection": nipple_erection,
		"throb_phase": throb_phase,
		"scrotum_tension": scrotum_tension,
		"arousal_gain_rate": arousal_gain_rate,
		"arousal_decay_rate": arousal_decay_rate,
		"erection_onset": erection_onset,
		"erection_full": erection_full,
		"throbbing_enabled": throbbing_enabled,
		"throb_frequency": throb_frequency,
		"in_refractory": in_refractory,
		"refractory_timer": _refractory_timer,
		"last_orgasm_intensity": last_orgasm_intensity,
		"sustained_high_time": _sustained_high_time,
		"participant_count": _active_participant_count,
		"cooldown_bypass": cooldown_bypass,
	}
