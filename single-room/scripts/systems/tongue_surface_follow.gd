class_name TongueSurfaceFollow
extends Node
## Drives the 3-segment tongue chain to follow a target surface.
##
## Modes:
##   RETRACTED — tongue inside mouth (spring return to rest)
##   FOLLOW    — tongue tip tracks a target body part surface
##   PATH      — tongue tip traces along a sequence of body parts
##
## Physics approach: applies forces to tongue segments to steer
## them toward target positions. Does NOT use IK — works WITH the
## existing soft-joint springs rather than fighting them.
##
## Fires LICK TouchType on the target via NerveSystem each tick
## the tongue tip is in contact.

# ── Signals ──────────────────────────────────────────────────────────────────
signal contact_started(target_part: String)
signal contact_lost(target_part: String)
signal path_step_reached(step_index: int, part_name: String)
signal path_completed()

# ── Enums ────────────────────────────────────────────────────────────────────
enum TongueMode { RETRACTED, FOLLOW, PATH }

# ── Force Tuning ─────────────────────────────────────────────────────────────
@export_group("Force Tuning")
## Force applied to tongue tip toward target (Newtons).
@export var tip_follow_force: float = 3.0
## Force applied to tongue mid to shape the curve (Newtons).
@export var mid_shaping_force: float = 1.5
## Distance threshold (metres) to consider tongue "in contact".
@export var contact_distance: float = 0.015
## Max reach distance — beyond this the tongue gives up.
@export var max_reach: float = 0.12
## Force multiplier when tongue is overshooting (damping assist).
@export var overshoot_damping: float = 4.0

# ── Lick Nerve Tuning ───────────────────────────────────────────────────────
@export_group("Lick Nerve")
## Nerve intensity per tick while tongue is in contact.
@export var lick_intensity: float = 0.4
## Extra intensity multiplier when tongue velocity is high (active licking).
@export var motion_intensity_bonus: float = 1.5
## Minimum tongue-tip speed (m/s) to count as active licking.
@export var active_lick_speed: float = 0.05

# ── Path Mode ────────────────────────────────────────────────────────────────
@export_group("Path Mode")
## How long the tongue dwells on each path step (seconds).
@export var path_dwell_time: float = 0.8
## Distance from step target to advance to next step.
@export var path_step_threshold: float = 0.02
## When true, path loops instead of completing.
@export var path_loop: bool = false

# ── Runtime State ────────────────────────────────────────────────────────────
## Current tongue mode.
var mode: TongueMode = TongueMode.RETRACTED
## Target BodyPart the tongue is tracking (FOLLOW mode).
var follow_target: BodyPart = null
## Surface offset on the target (local-space point on its surface).
var follow_surface_offset: Vector3 = Vector3.ZERO
## Whether the tongue tip is currently touching the target.
var is_in_contact: bool = false
## Path of targets for PATH mode.
var path_targets: Array[Dictionary] = []  # [{part: BodyPart, offset: Vector3}]
## Current step in the path.
var path_index: int = 0
## Dwell timer for current path step.
var path_dwell_timer: float = 0.0

# ── Internal ─────────────────────────────────────────────────────────────────
var _ragdoll: HumanoidRagdollBuilder = null
var _nerve_system: NerveSystem = null
var _tongue_tip: BodyPart = null
var _tongue_mid: BodyPart = null
var _tongue_base: BodyPart = null
var _jaw_part: BodyPart = null
var _prev_tip_pos: Vector3 = Vector3.ZERO
var _contact_part_name: String = ""


func setup(npc_root: Node3D) -> void:
	for child: Node in npc_root.get_children():
		if child is NerveSystem:
			_nerve_system = child as NerveSystem
		elif child is HumanoidRagdollBuilder:
			_ragdoll = child as HumanoidRagdollBuilder

	if _ragdoll == null:
		return

	if _ragdoll.parts.has("tongue_tip"):
		_tongue_tip = _ragdoll.parts["tongue_tip"] as BodyPart
	if _ragdoll.parts.has("tongue_mid"):
		_tongue_mid = _ragdoll.parts["tongue_mid"] as BodyPart
	if _ragdoll.parts.has("tongue_base"):
		_tongue_base = _ragdoll.parts["tongue_base"] as BodyPart
	if _ragdoll.parts.has("jaw"):
		_jaw_part = _ragdoll.parts["jaw"] as BodyPart

	if _tongue_tip != null:
		_prev_tip_pos = _tongue_tip.global_position


# ── Public API ───────────────────────────────────────────────────────────────

## Retract tongue back into mouth.
func retract() -> void:
	mode = TongueMode.RETRACTED
	follow_target = null
	path_targets.clear()
	path_index = 0
	_clear_contact()


## Start following a specific body part surface.
func start_follow(target: BodyPart, surface_offset: Vector3 = Vector3.ZERO) -> void:
	if target == null:
		return
	mode = TongueMode.FOLLOW
	follow_target = target
	follow_surface_offset = surface_offset
	path_targets.clear()


## Start tracing a path of body parts in sequence.
## Each entry: { "part": BodyPart, "offset": Vector3 }
func start_path(targets: Array[Dictionary]) -> void:
	if targets.is_empty():
		return
	mode = TongueMode.PATH
	path_targets = targets
	path_index = 0
	path_dwell_timer = 0.0
	follow_target = null
	# Set initial follow target to first path step
	var first: Dictionary = path_targets[0]
	follow_target = first.get("part") as BodyPart
	follow_surface_offset = first.get("offset", Vector3.ZERO) as Vector3


# ── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _tongue_tip == null:
		return

	match mode:
		TongueMode.RETRACTED:
			_apply_retract_forces()
		TongueMode.FOLLOW:
			_apply_follow_forces(delta)
		TongueMode.PATH:
			_apply_follow_forces(delta)
			_advance_path(delta)

	_prev_tip_pos = _tongue_tip.global_position


func _apply_retract_forces() -> void:
	# Let the soft-joint springs pull tongue back naturally.
	# Apply a small inward force to help retraction.
	if _jaw_part == null or _tongue_tip == null:
		return
	var retract_target: Vector3 = _jaw_part.global_position
	var tip_pos: Vector3 = _tongue_tip.global_position
	var to_target: Vector3 = retract_target - tip_pos
	var dist: float = to_target.length()
	if dist > 0.005:
		_tongue_tip.apply_central_force(to_target.normalized() * tip_follow_force * 0.5)
	_clear_contact()


func _apply_follow_forces(delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		retract()
		return

	# Target world position
	var target_world: Vector3 = follow_target.global_transform * follow_surface_offset
	var tip_pos: Vector3 = _tongue_tip.global_position
	var to_target: Vector3 = target_world - tip_pos
	var dist: float = to_target.length()

	# Give up if too far
	if dist > max_reach:
		_clear_contact()
		return

	# Apply force toward target on tip
	if dist > 0.001:
		var dir: Vector3 = to_target.normalized()
		var force_mag: float = tip_follow_force

		# Reduce force when close to avoid overshoot
		if dist < contact_distance * 3.0:
			force_mag *= dist / (contact_distance * 3.0)

		# Damping: oppose tip velocity component away from target
		var tip_vel: Vector3 = _tongue_tip.linear_velocity
		var away_speed: float = -tip_vel.dot(dir)
		if away_speed > 0.0:
			force_mag += away_speed * overshoot_damping

		_tongue_tip.apply_central_force(dir * force_mag)

	# Shape the mid segment: pull it toward the midpoint between base and target
	if _tongue_mid != null and _tongue_base != null:
		var base_pos: Vector3 = _tongue_base.global_position
		var mid_target: Vector3 = (base_pos + target_world) * 0.5
		var mid_pos: Vector3 = _tongue_mid.global_position
		var mid_to_target: Vector3 = mid_target - mid_pos
		if mid_to_target.length() > 0.002:
			_tongue_mid.apply_central_force(
				mid_to_target.normalized() * mid_shaping_force)

	# Contact detection
	var was_contact: bool = is_in_contact
	is_in_contact = dist <= contact_distance

	if is_in_contact and not was_contact:
		_contact_part_name = follow_target.part_name
		contact_started.emit(_contact_part_name)
	elif not is_in_contact and was_contact:
		contact_lost.emit(_contact_part_name)
		_contact_part_name = ""

	# Fire LICK nerve events while in contact
	if is_in_contact:
		_fire_lick_event(delta)


func _fire_lick_event(_delta: float) -> void:
	if follow_target == null:
		return

	# Calculate tongue tip speed for motion bonus
	var tip_vel: Vector3 = _tongue_tip.global_position - _prev_tip_pos
	# _prev_tip_pos is updated once per frame in _physics_process
	var tip_speed: float = tip_vel.length() * Engine.physics_ticks_per_second
	var motion_mult: float = 1.0
	if tip_speed >= active_lick_speed:
		motion_mult = lerpf(1.0, motion_intensity_bonus,
			clampf(tip_speed / (active_lick_speed * 4.0), 0.0, 1.0))

	var intensity: float = lick_intensity * motion_mult

	# Apply to the target part's owner NerveSystem
	var owner_node: Node3D = follow_target.ragdoll_owner
	if owner_node != null:
		for child: Node in owner_node.get_children():
			if child.has_method(&"receive_touch"):
				child.call(&"receive_touch", follow_target.part_name,
					NerveSystem.TouchType.LICK, intensity)
				break

	# Also stimulate this NPC's own tongue (tongue_tip is erogenous)
	if _nerve_system != null:
		_nerve_system.receive_touch("tongue_tip", NerveSystem.TouchType.LICK,
			intensity * 0.3)


func _advance_path(delta: float) -> void:
	if path_targets.is_empty():
		return

	# Check if tongue reached current step
	if is_in_contact:
		path_dwell_timer += delta
		if path_dwell_timer >= path_dwell_time:
			# Advance to next step
			path_index += 1
			path_dwell_timer = 0.0
			path_step_reached.emit(path_index - 1, _contact_part_name)

			if path_index >= path_targets.size():
				if path_loop:
					path_index = 0
				else:
					path_completed.emit()
					retract()
					return

			# Update follow target to new step
			var step: Dictionary = path_targets[path_index]
			follow_target = step.get("part") as BodyPart
			follow_surface_offset = step.get("offset", Vector3.ZERO) as Vector3


func _clear_contact() -> void:
	if is_in_contact:
		is_in_contact = false
		if _contact_part_name != "":
			contact_lost.emit(_contact_part_name)
			_contact_part_name = ""
