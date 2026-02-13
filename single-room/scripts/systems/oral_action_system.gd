class_name OralActionSystem
extends Node
## Drives jaw motor, suction mechanics, and bite-clamp physics.
##
## Three action modes:
##   IDLE   — jaw at rest, no oral forces applied
##   SUCK   — jaw partially closed, rhythmic negative-pressure on enclosed parts
##   BITE   — jaw clamp, pressure scales with jaw motor target angle
##
## The tongue is handled by TongueSurfaceFollow (sibling node).
## This system owns the jaw motor and the "what's in the mouth" detection.

# ── Signals ──────────────────────────────────────────────────────────────────
signal action_changed(new_action: OralAction)
signal suck_pulse(intensity: float)
signal bite_applied(target_part: String, pressure: float)
@warning_ignore("unused_signal")
signal mouth_opened(aperture: float)
@warning_ignore("unused_signal")
signal mouth_closed()

# ── Enums ────────────────────────────────────────────────────────────────────
enum OralAction { IDLE, SUCK, BITE, LICK, OPEN }

# ── Jaw Motor Tuning ────────────────────────────────────────────────────────
@export_group("Jaw Motor")
## Max jaw open angle in degrees (negative X = open).
@export var jaw_max_open_deg: float = 35.0
## Jaw close angle (degrees). 0 = teeth together.
@export var jaw_closed_deg: float = 0.0
## Jaw motor torque (N·m) — how hard the jaw clamps.
@export var jaw_motor_torque: float = 8.0
## How fast the jaw motor moves toward its target (deg/sec).
@export var jaw_motor_speed: float = 120.0
## Default resting jaw aperture (slightly open for natural look).
@export var jaw_rest_deg: float = 2.0

# ── Suck Tuning ──────────────────────────────────────────────────────────────
@export_group("Suck Action")
## Suck pulse frequency (Hz).
@export var suck_frequency: float = 1.2
## Suck pulse amplitude (0–1 modulates jaw aperture oscillation).
@export_range(0.0, 1.0) var suck_amplitude: float = 0.3
## Jaw aperture during suck (degrees open — partially closed around object).
@export var suck_jaw_deg: float = 8.0
## Nerve intensity scale per suck pulse (delivered to enclosed parts).
@export var suck_nerve_intensity: float = 0.5
## How much jaw oscillates during suck (degrees ±).
@export var suck_jaw_oscillation: float = 4.0

# ── Bite Tuning ──────────────────────────────────────────────────────────────
@export_group("Bite Action")
## Jaw angle during bite (degrees — how closed).
@export var bite_jaw_deg: float = -2.0
## Maximum bite pressure (0–1) at full jaw clamp.
@export_range(0.0, 1.0) var bite_max_pressure: float = 0.8
## Nerve intensity per tick while biting (scaled by pressure).
@export var bite_nerve_intensity: float = 0.7
## Discomfort per second at full bite pressure.
@export var bite_discomfort_per_second: float = 10.0
## Light bite threshold (below this = playful nibble = comfort).
@export_range(0.0, 1.0) var bite_playful_threshold: float = 0.3
## Comfort per second during a playful bite (erogenous parts).
@export var bite_playful_comfort_per_second: float = 4.0

# ── Open Mouth Tuning ───────────────────────────────────────────────────────
@export_group("Open Mouth")
## Target jaw angle when mouth is being held open.
@export var open_jaw_deg: float = 30.0

# ── Detection ────────────────────────────────────────────────────────────────
@export_group("Detection")
## Radius around mouth centre to detect "enclosed" body parts.
@export var mouth_detection_radius: float = 0.04
## How often to re-scan for enclosed parts (seconds).
@export var scan_interval: float = 0.1

# ── Runtime State ────────────────────────────────────────────────────────────
## Current oral action mode.
var current_action: OralAction = OralAction.IDLE
## Parts currently inside the mouth (part_name → BodyPart).
var enclosed_parts: Dictionary = {}
## Current jaw angle target (degrees, negative = open).
var jaw_target_deg: float = 2.0
## Current bite pressure (0–1).
var bite_pressure: float = 0.0
## Current suck phase (0–TAU cyclic).
var suck_phase: float = 0.0

# ── Internal ─────────────────────────────────────────────────────────────────
var _ragdoll: HumanoidRagdollBuilder = null
var _nerve_system: NerveSystem = null
var _character_profile: CharacterProfile = null
var _jaw_joint: Generic6DOFJoint3D = null
var _jaw_part: BodyPart = null
var _head_part: BodyPart = null
var _scan_timer: float = 0.0
var _mouth_centre_offset: Vector3 = Vector3.ZERO  # Local to head


func setup(npc_root: Node3D) -> void:
	for child: Node in npc_root.get_children():
		if child is NerveSystem:
			_nerve_system = child as NerveSystem
		elif child is CharacterProfile:
			_character_profile = child as CharacterProfile
		elif child is HumanoidRagdollBuilder:
			_ragdoll = child as HumanoidRagdollBuilder

	if _ragdoll == null:
		return

	# Get jaw and head parts
	if _ragdoll.parts.has("jaw"):
		_jaw_part = _ragdoll.parts["jaw"] as BodyPart
	if _ragdoll.parts.has("head"):
		_head_part = _ragdoll.parts["head"] as BodyPart

	# Get the jaw joint (head→jaw)
	var jaw_key: String = "head_to_jaw"
	if _ragdoll.joint_map.has(jaw_key):
		_jaw_joint = _ragdoll.joint_map[jaw_key] as Generic6DOFJoint3D
		_enable_jaw_motor()

	# Calculate mouth centre offset (between jaw and head, forward)
	if _jaw_part != null and _head_part != null:
		var mid: Vector3 = (_jaw_part.position + _head_part.position) * 0.5
		# Shift forward (local Z) to be at the lip line
		_mouth_centre_offset = mid + Vector3(0.0, 0.0, 0.02)


func _enable_jaw_motor() -> void:
	if _jaw_joint == null:
		return
	# Enable angular motor on X axis (pitch = open/close)
	_jaw_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	_jaw_joint.set_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, jaw_motor_torque)
	_jaw_joint.set_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,
		deg_to_rad(jaw_motor_speed))


func set_action(action: OralAction) -> void:
	if current_action == action:
		return
	var prev: OralAction = current_action
	current_action = action
	action_changed.emit(action)

	match action:
		OralAction.IDLE:
			jaw_target_deg = jaw_rest_deg
			bite_pressure = 0.0
		OralAction.SUCK:
			jaw_target_deg = suck_jaw_deg
			suck_phase = 0.0
		OralAction.BITE:
			jaw_target_deg = bite_jaw_deg
		OralAction.LICK:
			# Jaw opens slightly to let tongue work
			jaw_target_deg = 12.0
		OralAction.OPEN:
			jaw_target_deg = open_jaw_deg

	# On transition away from BITE, release bite pressure
	if prev == OralAction.BITE and action != OralAction.BITE:
		bite_pressure = 0.0


func _physics_process(delta: float) -> void:
	_update_jaw_motor(delta)
	_scan_enclosed_parts(delta)

	match current_action:
		OralAction.SUCK:
			_update_suck(delta)
		OralAction.BITE:
			_update_bite(delta)
		OralAction.IDLE, OralAction.OPEN, OralAction.LICK:
			pass  # Jaw motor handles positioning, no extra feedback


func _update_jaw_motor(_delta: float) -> void:
	if _jaw_joint == null:
		return
	# The jaw joint's X axis controls pitch. Negative angle = open jaw.
	# Motor target velocity drives toward jaw_target_deg.
	var current_limit_lower: float = _jaw_joint.get_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
	var target_rad: float = deg_to_rad(-jaw_target_deg)  # Negative = open
	# Clamp target within joint limits
	var lower_lim: float = _jaw_joint.get_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
	var upper_lim: float = _jaw_joint.get_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
	target_rad = clampf(target_rad, lower_lim, upper_lim)

	# Compute motor velocity to reach target
	# We estimate current angle from jaw part orientation relative to head
	var velocity_sign: float = signf(target_rad - current_limit_lower)
	_jaw_joint.set_param_x(
		Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,
		velocity_sign * deg_to_rad(jaw_motor_speed))


func _scan_enclosed_parts(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = scan_interval

	if _head_part == null:
		return

	# World-space mouth centre
	var mouth_world: Vector3 = _head_part.global_transform * _mouth_centre_offset
	var radius_sq: float = mouth_detection_radius * mouth_detection_radius

	# Clear previous
	var new_enclosed: Dictionary = {}

	# Scan all parts from all NPC ragdolls and player
	var all_bodies: Array[Node] = []
	for npc: Node in get_tree().get_nodes_in_group(&"npc"):
		if npc == get_parent():
			continue  # Don't detect own parts
		var rag: HumanoidRagdollBuilder = npc.get("ragdoll") as HumanoidRagdollBuilder
		if rag == null:
			continue
		for pname: String in rag.parts:
			all_bodies.append(rag.parts[pname])

	# Also check player parts if player has ragdoll
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		var rag: HumanoidRagdollBuilder = player.get("ragdoll") as HumanoidRagdollBuilder
		if rag == null:
			continue
		for pname: String in rag.parts:
			all_bodies.append(rag.parts[pname])

	for body: Node in all_bodies:
		if body is not BodyPart:
			continue
		var bp: BodyPart = body as BodyPart
		var dist_sq: float = mouth_world.distance_squared_to(bp.global_position)
		if dist_sq <= radius_sq:
			new_enclosed[bp.part_name] = bp

	enclosed_parts = new_enclosed


func _update_suck(delta: float) -> void:
	suck_phase += delta * suck_frequency * TAU
	if suck_phase > TAU:
		suck_phase -= TAU

	# Jaw oscillates around suck_jaw_deg
	var osc: float = sin(suck_phase) * suck_jaw_oscillation
	jaw_target_deg = suck_jaw_deg + osc

	# On the "pull" phase of the cycle (negative sine), fire suck stimulation
	var pulse: float = maxf(-sin(suck_phase), 0.0) * suck_amplitude
	if pulse > 0.01 and enclosed_parts.size() > 0:
		suck_pulse.emit(pulse)
		for pname: String in enclosed_parts:
			if _nerve_system != null:
				_nerve_system.receive_touch(
					pname, NerveSystem.TouchType.SUCK,
					suck_nerve_intensity * pulse)
			# Comfort from sucking on erogenous parts (applied to OTHER NPC)
			var bp: BodyPart = enclosed_parts[pname] as BodyPart
			_apply_touch_to_owner(bp, NerveSystem.TouchType.SUCK,
				suck_nerve_intensity * pulse)


func _update_bite(delta: float) -> void:
	# Bite pressure ramps toward max while action is BITE
	bite_pressure = minf(bite_pressure + 2.0 * delta, bite_max_pressure)

	for pname: String in enclosed_parts:
		# Nerve event on the bitten part
		var intensity: float = bite_nerve_intensity * bite_pressure
		if _nerve_system != null:
			_nerve_system.receive_touch(
				pname, NerveSystem.TouchType.BITE, intensity)

		# Apply to the owner of the bitten part
		var bp: BodyPart = enclosed_parts[pname] as BodyPart
		_apply_touch_to_owner(bp, NerveSystem.TouchType.BITE, intensity)

		# Playful nibble vs painful clamp on THIS NPC's profile (biter feels nothing)
		bite_applied.emit(pname, bite_pressure)


## Sends a nerve touch to whatever NPC/player actually owns the target body part.
func _apply_touch_to_owner(bp: BodyPart, touch_type: NerveSystem.TouchType,
		intensity: float) -> void:
	if bp == null or bp.ragdoll_owner == null:
		return
	var owner_node: Node3D = bp.ragdoll_owner
	# Find the NerveSystem on the owner
	for child: Node in owner_node.get_children():
		if child.has_method(&"receive_touch"):
			child.call(&"receive_touch", bp.part_name, touch_type, intensity)
			break


## Utility: get the world-space mouth centre position.
func get_mouth_position() -> Vector3:
	if _head_part == null:
		var parent_3d: Node3D = get_parent() as Node3D
		if parent_3d != null:
			return parent_3d.global_position
		return Vector3.ZERO
	return _head_part.global_transform * _mouth_centre_offset


## Utility: get the forward direction of the mouth (where it's pointing).
func get_mouth_forward() -> Vector3:
	if _head_part == null:
		var parent_3d: Node3D = get_parent() as Node3D
		if parent_3d != null:
			return -parent_3d.global_basis.z
		return Vector3.FORWARD
	return -_head_part.global_basis.z
