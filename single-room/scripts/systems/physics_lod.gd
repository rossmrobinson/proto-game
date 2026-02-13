class_name PhysicsLOD
extends Node
## Per-NPC level-of-detail manager for ragdoll physics bodies.
## Monitors distance to the camera (or a nominated focus point) and
## promotes / demotes the ragdoll detail level automatically.
##
## Manual overrides are supported — call force_lod() to pin a specific
## level regardless of distance.  Call release_lod() to resume automatic.
##
## Attach as a child of the NPC root (the node that owns both the ragdoll
## and the skeleton binding).

signal lod_changed(old_level: int, new_level: int)

# ── Configuration ────────────────────────────────────────────────────────────

@export_group("Distance Thresholds")
## Distance (metres) beyond which the NPC drops to MEDIUM detail.
@export var medium_distance: float = 4.0
## Distance (metres) beyond which the NPC drops to MINIMAL detail.
@export var minimal_distance: float = 8.0
## Hysteresis band added onto each threshold when *promoting* back up.
## Prevents flicker when hovering near a boundary.
@export var hysteresis: float = 0.5

@export_group("Timing")
## Seconds between LOD evaluations (no need to check every frame).
@export var eval_interval: float = 0.5

# ── Runtime State ────────────────────────────────────────────────────────────

## The ragdoll builder this LOD manager controls.
var _ragdoll: HumanoidRagdollBuilder = null
## The skeleton binding that must be re-bound after a LOD transition.
var _skeleton_binding: Node = null  # SkeletonBinding
## The skeleton used for re-binding.
var _skeleton: Skeleton3D = null
## Time accumulator for eval_interval.
var _eval_timer: float = 0.0
## When non-null, automatic LOD is disabled and this level is forced.
var _forced_level: Variant = null  # null | DetailLevel int
## Current effective detail level (cached to avoid redundant transitions).
var _current_level: int = -1
## Reference point for distance checks (usually Camera3D).
var _focus_point: Node3D = null


func _ready() -> void:
	set_physics_process(false)


## Wire up after ragdoll is built. Must be called before LOD can operate.
func setup(ragdoll: HumanoidRagdollBuilder, skeleton_binding: Node,
		skeleton: Skeleton3D) -> void:
	_ragdoll = ragdoll
	_skeleton_binding = skeleton_binding
	_skeleton = skeleton
	_current_level = ragdoll.detail_level
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_eval_timer += delta
	if _eval_timer < eval_interval:
		return
	_eval_timer = 0.0

	if _ragdoll == null:
		return

	# Forced override — skip distance check
	if _forced_level != null:
		_apply_level(_forced_level as int)
		return

	# Find focus point (camera) lazily
	if _focus_point == null or not is_instance_valid(_focus_point):
		var vp: Viewport = get_viewport()
		if vp != null:
			_focus_point = vp.get_camera_3d()
	if _focus_point == null:
		return

	var dist: float = _focus_point.global_position.distance_to(
		_ragdoll.global_position)

	var desired: int = _distance_to_level(dist)
	_apply_level(desired)


## Force a specific LOD level until release_lod() is called.
func force_lod(level: int) -> void:
	_forced_level = level
	_apply_level(level)


## Resume automatic distance-based LOD.
func release_lod() -> void:
	_forced_level = null


## Returns the current effective detail level.
func get_current_level() -> int:
	return _current_level


## Returns whether LOD is currently forced (manual override active).
func is_forced() -> bool:
	return _forced_level != null


# ── Internal ─────────────────────────────────────────────────────────────────

func _distance_to_level(dist: float) -> int:
	# Demotion uses the raw threshold; promotion adds hysteresis.
	if _current_level == HumanoidRagdollBuilder.DetailLevel.FULL:
		# Currently FULL — demote?
		if dist > minimal_distance:
			return HumanoidRagdollBuilder.DetailLevel.MINIMAL
		if dist > medium_distance:
			return HumanoidRagdollBuilder.DetailLevel.MEDIUM
		return HumanoidRagdollBuilder.DetailLevel.FULL

	if _current_level == HumanoidRagdollBuilder.DetailLevel.MEDIUM:
		# Currently MEDIUM — demote or promote?
		if dist > minimal_distance:
			return HumanoidRagdollBuilder.DetailLevel.MINIMAL
		if dist < medium_distance - hysteresis:
			return HumanoidRagdollBuilder.DetailLevel.FULL
		return HumanoidRagdollBuilder.DetailLevel.MEDIUM

	# Currently MINIMAL — promote?
	if dist < medium_distance - hysteresis:
		return HumanoidRagdollBuilder.DetailLevel.FULL
	if dist < minimal_distance - hysteresis:
		return HumanoidRagdollBuilder.DetailLevel.MEDIUM
	return HumanoidRagdollBuilder.DetailLevel.MINIMAL


func _apply_level(desired: int) -> void:
	if desired == _current_level:
		return

	var old: int = _current_level
	_ragdoll.rebuild_at_lod(desired as HumanoidRagdollBuilder.DetailLevel)
	_current_level = desired

	# Re-bind skeleton after rebuild
	if _skeleton_binding != null and _skeleton != null:
		if _skeleton_binding.has_method(&"bind"):
			_skeleton_binding.call(&"bind", _skeleton, _ragdoll)

	lod_changed.emit(old, desired)
	var owner_name: String = "?"
	if _ragdoll != null and _ragdoll.get_parent() != null:
		owner_name = str(_ragdoll.get_parent().name)
	print("[PhysicsLOD] %s: %s → %s (%d bodies)" % [
		owner_name,
		_level_name(old), _level_name(desired),
		_ragdoll.get_expected_body_count()])


static func _level_name(level: int) -> String:
	match level:
		HumanoidRagdollBuilder.DetailLevel.FULL:
			return "FULL"
		HumanoidRagdollBuilder.DetailLevel.MEDIUM:
			return "MEDIUM"
		HumanoidRagdollBuilder.DetailLevel.MINIMAL:
			return "MINIMAL"
		_:
			return "UNKNOWN"
