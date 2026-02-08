class_name HandInteractionSystem
extends Node3D
## Dual-hand mouse interaction system.
## Left click = left hand, Right click = right hand.
## Supersedes GrabSystem with richer gesture vocabulary.
##
## Controls:
##   L/R Single Click : Grab target (or release if already holding)
##   L/R Double Click : Push target (or push-release if holding)
##   Wheel Horizontal : Rotate player pelvis/hips left-right
##   Wheel Vertical   : Crotch/hip thrust positioning (or adjust hold distance)
##   Middle Click x2  : Press genitals to target surface
##   Middle Hold 1s   : Toggle autopilot mode

signal hand_grabbed(hand: Hand, target: BodyPart)
signal hand_released(hand: Hand, target: BodyPart)
signal hand_pushed(hand: Hand, target: BodyPart, force: float)
signal hand_push_released(hand: Hand, target: BodyPart, force: float)
signal pelvis_rotated(angle_delta_deg: float)
signal pelvis_thrust(amount: float)
signal genitals_pressed()
signal autopilot_toggled(enabled: bool)

enum Hand { LEFT, RIGHT }

# ── Config ───────────────────────────────────────────────────────────────────
@export_group("Timing")
@export var double_click_window: float = 0.25
@export var autopilot_hold_time: float = 1.0

@export_group("Grab")
@export var grab_distance: float = 3.0
@export var hold_distance_min: float = 0.5
@export var hold_distance_max: float = 4.0
@export var grab_move_speed: float = 15.0

@export_group("Push")
@export var push_force: float = 6.0

@export_group("Pelvis")
## Degrees of pelvis rotation per horizontal scroll tick.
@export var pelvis_rotate_per_tick: float = 5.0
## Meters of thrust per vertical scroll tick.
@export var thrust_per_tick: float = 0.08

# ── Per-hand state (inner class to avoid left_/right_ duplication) ───────────
class _HandState:
	var held: BodyPart = null
	var hold_distance: float = 1.5
	var pending: bool = false
	var pending_time: float = 0.0
	var anchor: StaticBody3D = null

var _hands: Dictionary = {}  # Hand enum → _HandState

# Middle mouse
var _middle_press_time: float = -1.0
var _middle_pending: bool = false
var _middle_pending_time: float = 0.0
var _middle_held: bool = false
var _autopilot_active: bool = false
var _autopilot_fired: bool = false

@onready var _player: PlayerController = get_parent() as PlayerController
var _targeting: TargetingSystem = null
var _command_system: NPCCommandSystem = null


func _ready() -> void:
	# Build per-hand state
	for hand: Hand in [Hand.LEFT, Hand.RIGHT]:
		var hs: _HandState = _HandState.new()
		var anchor_name: String = "LeftHandAnchor" if hand == Hand.LEFT else "RightHandAnchor"
		hs.anchor = _create_anchor(anchor_name)
		_hands[hand] = hs
	# Find siblings
	for child: Node in _player.get_children():
		if child is TargetingSystem:
			_targeting = child as TargetingSystem
		if child is NPCCommandSystem:
			_command_system = child as NPCCommandSystem


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton

	if mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_on_hand_click(Hand.LEFT)
			MOUSE_BUTTON_RIGHT:
				_on_hand_click(Hand.RIGHT)
			MOUSE_BUTTON_MIDDLE:
				_on_middle_pressed()
			MOUSE_BUTTON_WHEEL_LEFT:
				pelvis_rotated.emit(-pelvis_rotate_per_tick)
			MOUSE_BUTTON_WHEEL_RIGHT:
				pelvis_rotated.emit(pelvis_rotate_per_tick)
			MOUSE_BUTTON_WHEEL_UP:
				_on_scroll_vertical(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_on_scroll_vertical(-1.0)
	else:
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_on_middle_released()


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	# Expire pending single clicks — check both hands
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		if hs.pending and (now - hs.pending_time) > double_click_window:
			_execute_single_click(hand)
			hs.pending = false

	# Expire pending middle click
	if _middle_pending and (now - _middle_pending_time) > double_click_window:
		_middle_pending = false

	# Autopilot hold detection
	if _middle_held and not _autopilot_fired and _middle_press_time > 0.0:
		if (now - _middle_press_time) >= autopilot_hold_time:
			_autopilot_active = not _autopilot_active
			autopilot_toggled.emit(_autopilot_active)
			_autopilot_fired = true


func _physics_process(delta: float) -> void:
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		_update_anchor(hs.anchor, hs.hold_distance, delta)
		# Clear invalid held references
		if hs.held != null and not is_instance_valid(hs.held):
			hs.held = null


# ── Click Handling ───────────────────────────────────────────────────────────

func _on_hand_click(hand: Hand) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var hs: _HandState = _hands[hand] as _HandState

	if hs.pending and (now - hs.pending_time) <= double_click_window:
		hs.pending = false
		_execute_double_click(hand)
	else:
		hs.pending = true
		hs.pending_time = now


func _execute_single_click(hand: Hand) -> void:
	var held: BodyPart = _get_held(hand)
	if held != null:
		_release_hand(hand)
	else:
		_try_grab(hand)


func _execute_double_click(hand: Hand) -> void:
	var held: BodyPart = _get_held(hand)
	if held != null:
		# Push-release: shove and let go in one fluid motion
		_push_release(hand, held)
	else:
		# Push: target gets shoved backward
		_push_target(hand)


# ── Grab / Release / Push ────────────────────────────────────────────────────

func _try_grab(hand: Hand) -> void:
	var target: BodyPart = _get_target()
	if target == null or not target.is_grabbable or target.grabbed_by != null:
		return

	# Determine the acting entity — commanded NPC or player
	var actor: Node3D = _get_actor()

	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	var hs: _HandState = _hands[hand] as _HandState

	# Use targeting system hit point if available, else approximate
	var hit_point: Vector3 = target.global_position
	if _targeting != null and _targeting.current_target == target:
		hit_point = _targeting.target_hit_point

	var dist: float = camera.global_position.distance_to(hit_point)
	hs.hold_distance = dist
	hs.anchor.global_position = hit_point

	var success: bool = target.grab(actor, hs.anchor, hit_point)
	if success:
		_set_held(hand, target)
		hand_grabbed.emit(hand, target)


func _release_hand(hand: Hand) -> void:
	var held: BodyPart = _get_held(hand)
	if held == null:
		return
	if is_instance_valid(held):
		held.release()
	_set_held(hand, null)
	hand_released.emit(hand, held)


func _push_target(hand: Hand) -> void:
	var target: BodyPart = _get_target()
	if target == null:
		return
	# Push direction: from the actor toward the target
	var actor: Node3D = _get_actor()
	var push_dir: Vector3 = (target.global_position - actor.global_position).normalized()
	if push_dir.is_zero_approx():
		var camera: Camera3D = _player.get_active_camera()
		if camera != null:
			push_dir = -camera.global_basis.z
		else:
			push_dir = Vector3.FORWARD
	target.apply_hit(push_dir, push_force, target.global_position)
	hand_pushed.emit(hand, target, push_force)


func _push_release(hand: Hand, held: BodyPart) -> void:
	if not is_instance_valid(held):
		_set_held(hand, null)
		return
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return
	var push_dir: Vector3 = -camera.global_basis.z
	# Release then shove in one frame
	held.release()
	held.apply_impulse(push_dir * push_force, Vector3.ZERO)
	_set_held(hand, null)
	hand_push_released.emit(hand, held, push_force)


# ── Middle Mouse ─────────────────────────────────────────────────────────────

func _on_middle_pressed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	if _middle_pending and (now - _middle_pending_time) <= double_click_window:
		# Double middle click → genitals to surface
		_middle_pending = false
		genitals_pressed.emit()
	else:
		_middle_pending = true
		_middle_pending_time = now

	_middle_press_time = now
	_middle_held = true
	_autopilot_fired = false


func _on_middle_released() -> void:
	_middle_held = false
	_middle_press_time = -1.0


# ── Scroll ───────────────────────────────────────────────────────────────────

func _on_scroll_vertical(direction: float) -> void:
	# If either hand is holding something, adjust that hand's hold distance.
	# Otherwise, thrust control.
	var adjusted: bool = false
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		if hs.held != null:
			hs.hold_distance = clampf(
				hs.hold_distance + direction * 0.15,
				hold_distance_min, hold_distance_max)
			adjusted = true

	if not adjusted:
		pelvis_thrust.emit(direction * thrust_per_tick)


# ── Anchor Management ────────────────────────────────────────────────────────

func _create_anchor(anchor_name: String) -> StaticBody3D:
	var anchor: StaticBody3D = StaticBody3D.new()
	anchor.name = anchor_name
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.01
	col.shape = shape
	anchor.add_child(col)
	get_tree().current_scene.call_deferred("add_child", anchor)
	return anchor


func _update_anchor(anchor: StaticBody3D, hold_dist: float, delta: float) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	if not anchor.is_inside_tree():
		return
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	var aim_pos: Vector3

	# In detached-cursor mode, guide held objects toward the crosshair position
	if _targeting != null and _targeting.detached_cursor:
		var ray: Array = _targeting.get_aim_ray()
		if ray.size() == 2:
			var ray_origin: Vector3 = ray[0] as Vector3
			var ray_dir: Vector3 = ray[1] as Vector3
			aim_pos = ray_origin + ray_dir * hold_dist
		else:
			aim_pos = camera.global_position + (-camera.global_basis.z) * hold_dist
	else:
		aim_pos = camera.global_position + (-camera.global_basis.z) * hold_dist

	anchor.global_position = anchor.global_position.lerp(aim_pos, grab_move_speed * delta)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_target() -> BodyPart:
	if _targeting != null and _targeting.current_target != null:
		return _targeting.current_target
	return _raycast_for_part()


func _raycast_for_part() -> BodyPart:
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return null
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var ray_end: Vector3 = origin + (-camera.global_basis.z) * grab_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, ray_end)
	query.collision_mask = 4 | 8 | 16  # layer 3 + 4 + 5 (SoftTissue)
	query.collide_with_bodies = true
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider: Object = result["collider"]
	if collider is BodyPart:
		return collider as BodyPart
	return null


func _get_held(hand: Hand) -> BodyPart:
	var hs: _HandState = _hands[hand] as _HandState
	return hs.held


func _set_held(hand: Hand, part: BodyPart) -> void:
	var hs: _HandState = _hands[hand] as _HandState
	hs.held = part


## True if either hand is holding something.
func is_grabbing() -> bool:
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		if hs.held != null and is_instance_valid(hs.held):
			return true
	return false


## Get what a specific hand is holding (or null).
func get_held(hand: Hand) -> BodyPart:
	var hs: _HandState = _hands[hand] as _HandState
	if hs.held != null and is_instance_valid(hs.held):
		return hs.held
	return null


## Returns the active actor — the commanded NPC's root, or the player.
func _get_actor() -> Node3D:
	if _command_system != null and _command_system.is_commanding():
		return _command_system.commanded_npc as Node3D
	return _player as Node3D
