class_name NPCActivityController
extends Node

@export_enum("none", "ada_patrol", "vero_sit_stand", "sara_pole_dance", "irene_jog")
var activity_profile: String = "none"

@export_group("Room")
@export var room_half_extent: float = 9.76
@export var edge_margin: float = 1.0
@export var arrival_distance: float = 0.6

@export_group("Movement")
@export var movement_enabled: bool = true
@export var patrol_force: float = 35.0
@export var patrol_max_speed: float = 1.8
@export var jog_force: float = 60.0
@export var jog_max_speed: float = 3.2

@export_group("Sit/Stand")
@export var stand_pose_name: String = "mountain"
@export var sit_pose_name: String = "seated_bottom"
@export var sit_stand_interval: float = 10.0
@export var pose_blend_time: float = 0.6

@export_group("Pole Dance")
@export var dance_pose_duration: float = 1.3
@export var dance_spring_scale: float = 0.7
@export var dance_damping_scale: float = 0.7
@export var dance_pose_names: PackedStringArray = PackedStringArray([
	"salsa_hip_left",
	"salsa_hip_right",
	"belly_roll_back",
	"hiphop_wave",
	"tango_dip",
	"swing_open",
])

var _npc: NPCPlaceholder = null
var _animator: RagdollAnimator = null
var _pelvis: RigidBody3D = null
var _active: bool = true

var _path_points: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _jog_forward: bool = true
var _sit_timer: float = 0.0
var _is_sitting: bool = false

var _dance_cached: bool = false
var _dance_prev_stiffness: float = 0.0
var _dance_prev_damping: float = 0.0


func _ready() -> void:
	call_deferred(&"_initialize")


func set_active(enabled: bool) -> void:
	if _active == enabled:
		return
	_active = enabled
	if not _active:
		_stop_activity()
		return
	_start_activity()


func on_ragdoll_built() -> void:
	_refresh_pelvis()


func _initialize() -> void:
	_npc = get_parent() as NPCPlaceholder
	if _npc == null:
		return
	if _npc.ragdoll != null:
		_npc.ragdoll.ragdoll_built.connect(_on_ragdoll_built)
	_animator = _find_animator()
	_refresh_pelvis()
	_start_activity()


func _physics_process(delta: float) -> void:
	if not _active or _npc == null:
		return
	if not _npc.is_awake:
		return
	match activity_profile:
		"ada_patrol":
			_update_patrol(delta)
		"irene_jog":
			_update_jog(delta)
		"vero_sit_stand":
			_update_sit_stand(delta)
		_:
			pass


func _start_activity() -> void:
	if activity_profile == "none":
		return
	if _npc != null and _npc.behavior != null:
		_npc.behavior.pause()
	match activity_profile:
		"ada_patrol":
			_start_patrol()
		"irene_jog":
			_start_jog()
		"vero_sit_stand":
			_start_sit_stand()
		"sara_pole_dance":
			_start_pole_dance()
		_:
			pass


func _stop_activity() -> void:
	if activity_profile == "sara_pole_dance":
		_stop_pole_dance()


func _start_patrol() -> void:
	_path_points = _build_perimeter_path()
	_path_index = 0
	_apply_pose(stand_pose_name)


func _start_jog() -> void:
	_path_points = _build_jog_path()
	_path_index = 0
	_jog_forward = true
	_apply_pose(stand_pose_name)


func _start_sit_stand() -> void:
	_sit_timer = 0.0
	_is_sitting = false
	_apply_pose(stand_pose_name)


func _start_pole_dance() -> void:
	if _animator == null:
		return
	_cache_dance_settings()
	_animator.spring_stiffness = _dance_prev_stiffness * dance_spring_scale
	_animator.spring_damping = _dance_prev_damping * dance_damping_scale
	var poses: Array[RagdollPose] = _resolve_poses(dance_pose_names)
	if poses.is_empty():
		return
	var holds: Array[float] = []
	for _pose: RagdollPose in poses:
		holds.append(dance_pose_duration)
	_animator.play_sequence("sara_pole_dance", poses, holds, true)


func _stop_pole_dance() -> void:
	if _animator == null:
		return
	if _dance_cached:
		_animator.spring_stiffness = _dance_prev_stiffness
		_animator.spring_damping = _dance_prev_damping
	_animator.stop_sequence()


func _update_patrol(_delta: float) -> void:
	if _path_points.is_empty() or _pelvis == null or not movement_enabled:
		return
	var target: Vector3 = _path_points[_path_index]
	var dist: float = _drive_toward(target, patrol_max_speed, patrol_force)
	if dist <= arrival_distance:
		_path_index = (_path_index + 1) % _path_points.size()


func _update_jog(_delta: float) -> void:
	if _path_points.size() < 2 or _pelvis == null or not movement_enabled:
		return
	var target_idx: int = 1 if _jog_forward else 0
	var target: Vector3 = _path_points[target_idx]
	var dist: float = _drive_toward(target, jog_max_speed, jog_force)
	if dist <= arrival_distance:
		_jog_forward = not _jog_forward


func _update_sit_stand(delta: float) -> void:
	_sit_timer += delta
	if _sit_timer < sit_stand_interval:
		return
	_sit_timer = 0.0
	_is_sitting = not _is_sitting
	_apply_pose(sit_pose_name if _is_sitting else stand_pose_name)


func _apply_pose(pose_name: String) -> void:
	if _animator == null:
		return
	_animator.set_pose_by_name(pose_name, pose_blend_time)


func _drive_toward(target: Vector3, max_speed: float, force: float) -> float:
	if _pelvis == null:
		return INF
	var pos: Vector3 = _pelvis.global_position
	var flat_target: Vector3 = Vector3(target.x, pos.y, target.z)
	var to_target: Vector3 = flat_target - pos
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist <= 0.01:
		return dist
	var dir: Vector3 = to_target / dist
	var vel: Vector3 = _pelvis.linear_velocity
	var flat_vel: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if flat_vel.length() < max_speed:
		_pelvis.apply_central_force(dir * force * _pelvis.mass)
	return dist


func _build_perimeter_path() -> PackedVector3Array:
	var h: float = maxf(0.5, room_half_extent - edge_margin)
	return PackedVector3Array([
		Vector3(-h, 0.0, -h),
		Vector3(h, 0.0, -h),
		Vector3(h, 0.0, h),
		Vector3(-h, 0.0, h),
	])


func _build_jog_path() -> PackedVector3Array:
	var h: float = maxf(0.5, room_half_extent - edge_margin)
	var z: float = 0.0
	if _npc != null:
		z = _npc.global_position.z
	return PackedVector3Array([
		Vector3(-h, 0.0, z),
		Vector3(h, 0.0, z),
	])


func _refresh_pelvis() -> void:
	_pelvis = null
	if _npc == null or _npc.ragdoll == null:
		return
	if _npc.ragdoll.parts.has("pelvis"):
		var part: Node = _npc.ragdoll.parts["pelvis"] as Node
		if part is RigidBody3D:
			_pelvis = part as RigidBody3D


func _find_animator() -> RagdollAnimator:
	if _npc == null:
		return null
	var direct: Node = _npc.get_node_or_null("RagdollAnimator")
	if direct is RagdollAnimator:
		return direct as RagdollAnimator
	for child: Node in _npc.get_children():
		if child.has_method(&"set_pose"):
			return child as RagdollAnimator
	return null


func _resolve_poses(pose_names: PackedStringArray) -> Array[RagdollPose]:
	var poses: Array[RagdollPose] = []
	for pose_name: String in pose_names:
		var pose: RagdollPose = RagdollPoseLibrary.get_pose(pose_name)
		if pose != null:
			poses.append(pose)
	return poses


func _cache_dance_settings() -> void:
	if _animator == null:
		return
	_dance_cached = true
	_dance_prev_stiffness = _animator.spring_stiffness
	_dance_prev_damping = _animator.spring_damping


func _on_ragdoll_built() -> void:
	on_ragdoll_built()
