class_name ThirdPartyInsertion
extends Node
## Manages three-entity insertion: an actor manipulates a tool body into a
## target NPC's passage.
##
## Example: Person 6 (actor) grabs Player's penis (tool) and inserts it into
## Person 1's vaginal passage (target).
##
## The system:
##   1. Tracks the tool body parts (e.g. penis_base, penis_mid, penis_tip).
##   2. Computes insertion depth by projecting the tool tip onto the passage
##      axis (entrance → depth direction).
##   3. Creates a soft guide joint when the tool enters the passage, keeping
##      the tool centred in the tunnel without overriding actor input.
##   4. Fires signals for depth/contact that PassageResponse and NerveSystem
##      can react to.
##
## Attach to the *target* NPC (the one being penetrated).

signal insertion_started(passage_name: String, tool_tip: RigidBody3D)
signal insertion_ended(passage_name: String)
signal depth_changed(passage_name: String, depth: float, max_depth: float)

# ── Configuration ────────────────────────────────────────────────────────────

@export_group("Detection")
## Radius around the passage entrance in which the tool tip triggers entry.
@export var entry_radius: float = 0.06
## How far the tool must retract beyond the entrance before exit is declared.
@export var exit_margin: float = 0.03

@export_group("Guide Joint")
## Whether to add a soft centering joint that keeps the tool in the passage.
@export var guide_enabled: bool = true
## Linear spring stiffness of the centering joint (N/m).
@export var guide_stiffness: float = 8.0
## Linear spring damping of the centering joint.
@export var guide_damping: float = 2.0

# ── Runtime State ────────────────────────────────────────────────────────────

## Per-passage tracking.  Key: passage name ("vaginal", "anal", "oral").
## Value: _InsertionState (inner class).
var _active_insertions: Dictionary = {}

## Owner's ragdoll builder (target NPC).
var _target_ragdoll: HumanoidRagdollBuilder = null

## Passage metadata: { passage_name → { entrance_pos, direction, length } }
var _passage_meta: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)


## Call once after the target NPC's ragdoll is built.
## passage_names: which passages to monitor (e.g. ["vaginal", "anal"]).
func setup(target_ragdoll: HumanoidRagdollBuilder,
		passage_names: PackedStringArray) -> void:
	for active_name: String in _active_insertions.keys():
		end_attempt(active_name)
	_active_insertions.clear()
	_passage_meta.clear()

	_target_ragdoll = target_ragdoll
	if _target_ragdoll == null:
		push_warning("[ThirdPartyInsertion] setup() called with null ragdoll")
		return

	for pname: String in passage_names:
		_build_passage_meta(pname)

	if _passage_meta.size() > 0:
		set_physics_process(true)
		print("[ThirdPartyInsertion] Monitoring %d passages" % _passage_meta.size())


## Begin tracking a tool body for insertion into a specific passage.
## tool_parts: ordered Array of RigidBody3D from base → tip.
## actor: the NPC or Player operating the tool (for ownership/attribution).
func begin_attempt(passage_name: String, tool_parts: Array[RigidBody3D],
		actor: Node3D) -> void:
	if not _passage_meta.has(passage_name):
		push_warning("[ThirdPartyInsertion] Unknown passage: %s" % passage_name)
		return
	if _active_insertions.has(passage_name):
		push_warning("[ThirdPartyInsertion] %s already has an active insertion" % passage_name)
		return
	if tool_parts.is_empty():
		push_warning("[ThirdPartyInsertion] begin_attempt('%s') called with empty tool_parts" % passage_name)
		return

	var valid_tool_parts: Array[RigidBody3D] = []
	for part: RigidBody3D in tool_parts:
		if part != null and is_instance_valid(part):
			valid_tool_parts.append(part)
	if valid_tool_parts.is_empty():
		push_warning("[ThirdPartyInsertion] begin_attempt('%s') has no valid tool bodies" % passage_name)
		return

	var tool_tip: RigidBody3D = valid_tool_parts[valid_tool_parts.size() - 1]

	var state: Dictionary = {
		"tool_parts": valid_tool_parts,
		"actor": actor,
		"tool_tip": tool_tip,
		"is_inserted": false,
		"depth": 0.0,
		"guide_joint": null,
	}
	_active_insertions[passage_name] = state


## Stop tracking a tool for a given passage. Cleans up guide joint.
func end_attempt(passage_name: String) -> void:
	if not _active_insertions.has(passage_name):
		return
	var state: Dictionary = _active_insertions[passage_name] as Dictionary
	_destroy_guide_joint(state)
	if state["is_inserted"] as bool:
		insertion_ended.emit(passage_name)
	_active_insertions.erase(passage_name)


func _physics_process(_delta: float) -> void:
	for passage_name: String in _active_insertions.keys():
		_update_insertion(passage_name)


## Returns current insertion depth for a passage (0.0 if not inserted).
func get_depth(passage_name: String) -> float:
	if _active_insertions.has(passage_name):
		return (_active_insertions[passage_name] as Dictionary)["depth"] as float
	return 0.0


## Returns whether a tool is currently inside the given passage.
func is_inserted(passage_name: String) -> bool:
	if _active_insertions.has(passage_name):
		return (_active_insertions[passage_name] as Dictionary)["is_inserted"] as bool
	return false


# ── Internal ─────────────────────────────────────────────────────────────────

func _build_passage_meta(pname: String) -> void:
	if _target_ragdoll == null:
		return

	# Find entrance ring parts to compute entrance position
	var entrance_parts: Array[BodyPart] = []
	var depth_parts: Array[BodyPart] = []

	for part_name: String in _target_ragdoll.parts:
		if part_name.begins_with(pname):
			var bp: BodyPart = _target_ragdoll.parts[part_name] as BodyPart
			if bp == null:
				continue
			if part_name.contains("_ring_"):
				entrance_parts.append(bp)
			elif part_name.contains("_passage_"):
				depth_parts.append(bp)

	if entrance_parts.is_empty():
		push_warning("[ThirdPartyInsertion] No entrance ring parts for '%s'" % pname)
		return

	# Entrance position = average of ring parts
	var entrance_pos: Vector3 = Vector3.ZERO
	for bp: BodyPart in entrance_parts:
		entrance_pos += bp.global_position
	entrance_pos /= float(entrance_parts.size())

	# Find the deepest passage part to compute direction and length
	var deepest_pos: Vector3 = entrance_pos
	var max_dist: float = 0.0
	for bp: BodyPart in depth_parts:
		var dist: float = bp.global_position.distance_to(entrance_pos)
		if dist > max_dist:
			max_dist = dist
			deepest_pos = bp.global_position

	var direction: Vector3 = Vector3(0.0, 0.0, -1.0)  # fallback
	if max_dist > 0.001:
		direction = (deepest_pos - entrance_pos).normalized()
	var passage_length: float = max_dist
	if passage_length <= 0.001:
		passage_length = maxf(entry_radius * 2.0, 0.05)
		push_warning("[ThirdPartyInsertion] '%s' has no depth parts; using fallback length %.3f" % [
			pname, passage_length])

	_passage_meta[pname] = {
		"entrance_parts": entrance_parts,
		"depth_parts": depth_parts,
		"entrance_pos": entrance_pos,
		"direction": direction,
		"length": passage_length,
	}


func _update_insertion(passage_name: String) -> void:
	var state: Dictionary = _active_insertions[passage_name] as Dictionary
	var meta: Dictionary = _passage_meta[passage_name] as Dictionary
	var tool_tip: RigidBody3D = state["tool_tip"] as RigidBody3D

	if tool_tip == null or not is_instance_valid(tool_tip):
		end_attempt(passage_name)
		return

	# Recompute entrance position dynamically (body may have moved)
	var entrance_pos: Vector3 = Vector3.ZERO
	var entrance_parts: Array = meta["entrance_parts"] as Array
	var valid_count: int = 0
	for part: Variant in entrance_parts:
		var bp: BodyPart = part as BodyPart
		if bp != null and is_instance_valid(bp):
			entrance_pos += bp.global_position
			valid_count += 1
	if valid_count == 0:
		end_attempt(passage_name)
		return
	entrance_pos /= float(valid_count)

	# Recompute direction from entrance to deepest part
	var direction: Vector3 = meta["direction"] as Vector3
	var depth_parts: Array = meta["depth_parts"] as Array
	if not depth_parts.is_empty():
		var deepest: BodyPart = null
		var max_d: float = 0.0
		for part: Variant in depth_parts:
			var bp: BodyPart = part as BodyPart
			if bp == null or not is_instance_valid(bp):
				continue
			var d: float = bp.global_position.distance_to(entrance_pos)
			if d > max_d:
				max_d = d
				deepest = bp
		if deepest != null and max_d > 0.001:
			direction = (deepest.global_position - entrance_pos).normalized()
			meta["length"] = max_d

	var tip_pos: Vector3 = tool_tip.global_position
	var to_tip: Vector3 = tip_pos - entrance_pos

	# Project onto passage axis
	var axial_dist: float = to_tip.dot(direction)
	# Lateral distance from passage axis
	var lateral: Vector3 = to_tip - direction * axial_dist
	var lateral_dist: float = lateral.length()

	var was_inserted: bool = state["is_inserted"] as bool
	var passage_length: float = meta["length"] as float

	if not was_inserted:
		# Check entry: tip near entrance and approaching from the right side
		if lateral_dist < entry_radius and axial_dist > -exit_margin and axial_dist < passage_length:
			state["is_inserted"] = true
			state["depth"] = clampf(axial_dist, 0.0, passage_length)
			if guide_enabled:
				_create_guide_joint(state, meta, entrance_pos, direction)
			insertion_started.emit(passage_name, tool_tip)
			depth_changed.emit(passage_name, state["depth"] as float, passage_length)
	else:
		# Already inserted — track depth
		if axial_dist < -exit_margin or lateral_dist > entry_radius * 3.0:
			# Withdrew or pulled out sideways
			state["is_inserted"] = false
			state["depth"] = 0.0
			_destroy_guide_joint(state)
			insertion_ended.emit(passage_name)
		else:
			state["depth"] = clampf(axial_dist, 0.0, passage_length)
			depth_changed.emit(passage_name, state["depth"] as float, passage_length)
			# Update guide joint target position along axis
			_update_guide_joint(state, entrance_pos, direction)


func _create_guide_joint(state: Dictionary, meta: Dictionary,
		entrance_pos: Vector3, _direction: Vector3) -> void:
	var tool_tip: RigidBody3D = state["tool_tip"] as RigidBody3D
	if tool_tip == null:
		return
	var existing_joint: Generic6DOFJoint3D = state.get("guide_joint") as Generic6DOFJoint3D
	if existing_joint != null and is_instance_valid(existing_joint):
		return

	# Find the nearest entrance ring part to anchor the joint
	var anchor_part: BodyPart = null
	var min_dist: float = INF
	var entrance_parts: Array = meta["entrance_parts"] as Array
	for part: Variant in entrance_parts:
		var bp: BodyPart = part as BodyPart
		if bp == null or not is_instance_valid(bp):
			continue
		var d: float = bp.global_position.distance_to(entrance_pos)
		if d < min_dist:
			min_dist = d
			anchor_part = bp

	if anchor_part == null:
		return

	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "InsertionGuide"
	joint.node_a = anchor_part.get_path()
	joint.node_b = tool_tip.get_path()
	joint.global_position = entrance_pos

	# Soft linear spring centering — allow axial movement, resist lateral
	# X and Z: centering springs. Y: free (depth axis may not align to Y
	# but the joint operates in local space of node_a, which is fine for
	# a soft guide — the springs gently push toward the anchor position.)
	var flag_spring: int = Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING
	joint.set_flag_x(flag_spring, true)
	joint.set_flag_y(flag_spring, true)
	joint.set_flag_z(flag_spring, true)

	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, guide_stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, guide_damping)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, guide_stiffness * 0.1)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, guide_damping * 0.1)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, guide_stiffness)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, guide_damping)

	# Wide linear limits so the joint doesn't rigidly lock
	var wide: float = 0.5
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -wide)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, wide)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -wide)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, wide)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -wide)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, wide)

	# Free rotation
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-180))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(180))

	var parent_node: Node = null
	if get_tree() != null:
		parent_node = get_tree().current_scene
	if parent_node == null:
		parent_node = self
	parent_node.add_child(joint)
	state["guide_joint"] = joint


func _update_guide_joint(_state: Dictionary, _entrance_pos: Vector3,
		_direction: Vector3) -> void:
	# The guide joint's anchor is on the ring part, which moves with the
	# body — no manual position update needed. The spring keeps the tool
	# centred automatically.
	pass


func _destroy_guide_joint(state: Dictionary) -> void:
	var joint: Generic6DOFJoint3D = state.get("guide_joint") as Generic6DOFJoint3D
	if joint != null and is_instance_valid(joint):
		joint.queue_free()
	state["guide_joint"] = null
