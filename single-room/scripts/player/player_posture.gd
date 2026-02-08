class_name PlayerPosture
extends Node
## Player posture state machine: standing, crouching, kneeling, prone.
## Child of PlayerController. Manages collision height and camera position.
##
## Controls:
##   Tap CTRL        → toggle crouch
##   Hold CTRL       → kneel (stand on release)
##   Double-tap CTRL → go prone
##   Spacebar        → jump (standing) or stand up (other postures)

signal posture_changed(new_posture: Posture, old_posture: Posture)

enum Posture { STANDING, CROUCHING, KNEELING, PRONE }

@export_group("Heights")
@export var standing_height: float = 2.0
@export var crouch_height: float = 1.1
@export var kneel_height: float = 0.8
@export var prone_height: float = 0.35

@export_group("Camera Y Offsets")
@export var standing_camera_y: float = 1.82
@export var crouch_camera_y: float = 1.0
@export var kneel_camera_y: float = 0.73
@export var prone_camera_y: float = 0.32

@export_group("Timing")
## CTRL must be released within this time to count as a tap (seconds).
@export var tap_threshold: float = 0.3
## Two taps within this window = double-tap (seconds).
@export var double_tap_window: float = 0.3
## CTRL held beyond this = kneel (seconds).
@export var hold_threshold: float = 0.35
## How fast the collision/camera interpolates between postures.
@export var transition_speed: float = 6.0

@export_group("Movement")
## Speed multiplier per posture.
@export var crouch_speed_mult: float = 0.5
@export var kneel_speed_mult: float = 0.0
@export var prone_speed_mult: float = 0.15

# ── State ────────────────────────────────────────────────────────────────────
var current_posture: Posture = Posture.STANDING
var _ctrl_press_time: float = -1.0
var _ctrl_held: bool = false
var _pending_tap_time: float = -1.0
var _kneel_triggered: bool = false

var _target_height: float = 1.8
var _target_camera_y: float = 0.8

@onready var _player: PlayerController = get_parent() as PlayerController
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null


func _ready() -> void:
	# Find the player's collision capsule
	for child: Node in _player.get_children():
		if child is CollisionShape3D:
			_collision_shape = child as CollisionShape3D
			if _collision_shape.shape is CapsuleShape3D:
				_capsule = _collision_shape.shape as CapsuleShape3D
			break
	_target_height = standing_height
	_target_camera_y = standing_camera_y
	print("[Posture] Standing height=%.2f camera_y=%.2f" % [standing_height, standing_camera_y])


func _unhandled_input(event: InputEvent) -> void:
	# CTRL key for crouch/kneel/prone
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_CTRL and not key.echo:
			if key.pressed:
				_on_ctrl_pressed()
			else:
				_on_ctrl_released()
			get_viewport().set_input_as_handled()
			return

	# Spacebar: jump if standing, stand up otherwise
	if event.is_action_pressed(&"jump"):
		if current_posture != Posture.STANDING:
			_change_posture(Posture.STANDING)
			get_viewport().set_input_as_handled()
			# Consumed — controller won't jump


func _physics_process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	# Hold detection: if CTRL held past threshold → kneel
	if _ctrl_held and not _kneel_triggered and _ctrl_press_time > 0.0:
		if (now - _ctrl_press_time) >= hold_threshold:
			_change_posture(Posture.KNEELING)
			_kneel_triggered = true

	# Pending tap timeout: if no second tap arrives → single tap action
	if _pending_tap_time > 0.0 and (now - _pending_tap_time) > double_tap_window:
		_execute_single_tap()
		_pending_tap_time = -1.0

	# Smooth interpolation of collision and camera
	if _capsule != null:
		_capsule.height = lerpf(_capsule.height, _target_height, transition_speed * delta)
		if _collision_shape != null:
			_collision_shape.position.y = _capsule.height / 2.0

	if _player.head_pivot != null:
		_player.head_pivot.position.y = lerpf(
			_player.head_pivot.position.y, _target_camera_y,
			transition_speed * delta)

	# Tell the player controller whether jump and speed are modified
	_player.set_meta(&"jump_enabled", current_posture == Posture.STANDING)
	_player.set_meta(&"speed_multiplier", get_speed_multiplier())


# ── CTRL Handling ────────────────────────────────────────────────────────────

func _on_ctrl_pressed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_ctrl_press_time = now
	_ctrl_held = true
	_kneel_triggered = false


func _on_ctrl_released() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var held_time: float = now - _ctrl_press_time if _ctrl_press_time > 0.0 else 0.0
	_ctrl_held = false

	if held_time >= hold_threshold:
		# Was a hold → kneel. Release = stand.
		if current_posture == Posture.KNEELING:
			_change_posture(Posture.STANDING)
		_pending_tap_time = -1.0
	else:
		# Short press = tap. Check for double-tap.
		if _pending_tap_time > 0.0 and (now - _pending_tap_time) <= double_tap_window:
			# Double-tap → prone
			_pending_tap_time = -1.0
			_change_posture(Posture.PRONE)
		else:
			# First tap — wait for possible second tap
			_pending_tap_time = now

	_ctrl_press_time = -1.0


func _execute_single_tap() -> void:
	match current_posture:
		Posture.STANDING:
			_change_posture(Posture.CROUCHING)
		Posture.CROUCHING:
			_change_posture(Posture.STANDING)
		Posture.PRONE:
			# Tap while prone → crouch (halfway up)
			_change_posture(Posture.CROUCHING)
		_:
			_change_posture(Posture.CROUCHING)


func _change_posture(new_posture: Posture) -> void:
	if new_posture == current_posture:
		return
	var old: Posture = current_posture
	current_posture = new_posture

	match new_posture:
		Posture.STANDING:
			_target_height = standing_height
			_target_camera_y = standing_camera_y
		Posture.CROUCHING:
			_target_height = crouch_height
			_target_camera_y = crouch_camera_y
		Posture.KNEELING:
			_target_height = kneel_height
			_target_camera_y = kneel_camera_y
		Posture.PRONE:
			_target_height = prone_height
			_target_camera_y = prone_camera_y

	posture_changed.emit(new_posture, old)


## Speed multiplier for the player controller based on current posture.
func get_speed_multiplier() -> float:
	match current_posture:
		Posture.STANDING:
			return 1.0
		Posture.CROUCHING:
			return crouch_speed_mult
		Posture.KNEELING:
			return kneel_speed_mult
		Posture.PRONE:
			return prone_speed_mult
	return 1.0
