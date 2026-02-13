class_name SuspensionDetector
extends Node
## Monitors foot-ground contact to detect when an NPC is suspended (hanging).
## When both feet are airborne for longer than the grace period, the detector
## signals suspension and disables the skeleton-binding assists that fight
## gravity (stand-assist, pelvis-lock, position springs).
##
## On ground contact, those systems are automatically re-enabled.
##
## Attach as a sibling of SkeletonBinding under the NPC root.

signal suspension_started()
signal suspension_ended()

# ── Configuration ────────────────────────────────────────────────────────────

@export_group("Detection")
## Seconds both feet must be airborne before suspension is declared.
@export var grace_period: float = 0.4
## How close a foot must be to something below it to count as "grounded" (m).
@export var ground_probe_distance: float = 0.12
## Physics layers to consider as ground (default: Environment=1).
@export_flags_3d_physics var ground_mask: int = 1

@export_group("Spring Tuning")
## Multiplier applied to spine joint stiffness while suspended.
## Lower = more ragdoll-like drooping.  0.0 = fully limp spine.
@export_range(0.0, 1.0) var suspended_spine_stiffness: float = 0.15
## Multiplier applied to position-spring strength while suspended.
@export_range(0.0, 1.0) var suspended_spring_scale: float = 0.05

# ── Runtime State ────────────────────────────────────────────────────────────

var _ragdoll: HumanoidRagdollBuilder = null
var _skeleton_binding: Node = null
var _left_foot: RigidBody3D = null
var _right_foot: RigidBody3D = null
var _airborne_timer: float = 0.0
var _is_suspended: bool = false

## Cached originals so we can restore on landing
var _orig_stand_assist_enabled: bool = true
var _orig_pelvis_lock: bool = true
var _orig_position_springs: bool = true
var _space_state: PhysicsDirectSpaceState3D = null
var _cached_exclude_rids: Array[RID] = []


func _ready() -> void:
	set_physics_process(false)


## Wire up after ragdoll is built.
func setup(ragdoll: HumanoidRagdollBuilder, skeleton_binding: Node) -> void:
	if _ragdoll != null and _ragdoll.ragdoll_built.is_connected(_on_ragdoll_rebuilt):
		_ragdoll.ragdoll_built.disconnect(_on_ragdoll_rebuilt)

	_ragdoll = ragdoll
	_skeleton_binding = skeleton_binding
	if _ragdoll != null and not _ragdoll.ragdoll_built.is_connected(_on_ragdoll_rebuilt):
		_ragdoll.ragdoll_built.connect(_on_ragdoll_rebuilt)
	_on_ragdoll_rebuilt()

	if _left_foot == null and _right_foot == null:
		push_warning("[SuspensionDetector] No foot parts found — detector disabled.")
		return

	# Cache original binding state
	if _skeleton_binding != null:
		if _skeleton_binding.get(&"stand_assist_enabled") != null:
			_orig_stand_assist_enabled = _skeleton_binding.get(&"stand_assist_enabled") as bool
		if _skeleton_binding.get(&"_enable_pelvis_lock") != null:
			_orig_pelvis_lock = _skeleton_binding.get(&"_enable_pelvis_lock") as bool
		if _skeleton_binding.get(&"_enable_position_springs") != null:
			_orig_position_springs = _skeleton_binding.get(&"_enable_position_springs") as bool

	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _ragdoll == null:
		return

	# Lazy-acquire space state
	if _space_state == null:
		var world: World3D = get_viewport().find_world_3d() if get_viewport() != null else null
		if world != null:
			_space_state = world.direct_space_state
	if _space_state == null:
		return

	var left_grounded: bool = _is_foot_grounded(_left_foot)
	var right_grounded: bool = _is_foot_grounded(_right_foot)
	var any_grounded: bool = left_grounded or right_grounded

	if any_grounded:
		_airborne_timer = 0.0
		if _is_suspended:
			_end_suspension()
	else:
		_airborne_timer += delta
		if _airborne_timer >= grace_period and not _is_suspended:
			_begin_suspension()


## Returns whether this NPC is currently detected as suspended (hanging).
func is_suspended() -> bool:
	return _is_suspended


# ── Internal ─────────────────────────────────────────────────────────────────

func _is_foot_grounded(foot: RigidBody3D) -> bool:
	if foot == null:
		return false
	var origin: Vector3 = foot.global_position
	var target: Vector3 = origin + Vector3.DOWN * ground_probe_distance

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, target, ground_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Exclude the foot itself and all ragdoll parts
	var exclude: Array[RID] = _cached_exclude_rids.duplicate()
	var foot_rid: RID = foot.get_rid()
	if not exclude.has(foot_rid):
		exclude.append(foot_rid)
	query.exclude = exclude

	var result: Dictionary = _space_state.intersect_ray(query)
	return not result.is_empty()


func _on_ragdoll_rebuilt() -> void:
	_left_foot = null
	_right_foot = null
	if _ragdoll == null:
		_cached_exclude_rids.clear()
		return

	if _ragdoll.parts.has("left_foot"):
		_left_foot = _ragdoll.parts["left_foot"] as RigidBody3D
	if _ragdoll.parts.has("right_foot"):
		_right_foot = _ragdoll.parts["right_foot"] as RigidBody3D
	_rebuild_exclusion_cache()


func _rebuild_exclusion_cache() -> void:
	_cached_exclude_rids.clear()
	if _ragdoll == null:
		return
	for part_name: String in _ragdoll.parts:
		var bp: RigidBody3D = _ragdoll.parts[part_name] as RigidBody3D
		if bp != null and is_instance_valid(bp):
			_cached_exclude_rids.append(bp.get_rid())


func _begin_suspension() -> void:
	_is_suspended = true

	if _skeleton_binding != null:
		# Disable systems that fight gravity
		_skeleton_binding.set(&"stand_assist_enabled", false)
		_skeleton_binding.set(&"_enable_pelvis_lock", false)
		_skeleton_binding.set(&"_enable_position_springs", false)

	suspension_started.emit()
	var owner_name: String = "?"
	if _ragdoll != null and _ragdoll.get_parent() != null:
		owner_name = str(_ragdoll.get_parent().name)
	print("[SuspensionDetector] %s: SUSPENDED" % [owner_name])


func _end_suspension() -> void:
	_is_suspended = false

	if _skeleton_binding != null:
		# Restore original state
		_skeleton_binding.set(&"stand_assist_enabled", _orig_stand_assist_enabled)
		_skeleton_binding.set(&"_enable_pelvis_lock", _orig_pelvis_lock)
		_skeleton_binding.set(&"_enable_position_springs", _orig_position_springs)

	suspension_ended.emit()
	var owner_name: String = "?"
	if _ragdoll != null and _ragdoll.get_parent() != null:
		owner_name = str(_ragdoll.get_parent().name)
	print("[SuspensionDetector] %s: GROUNDED" % [owner_name])
