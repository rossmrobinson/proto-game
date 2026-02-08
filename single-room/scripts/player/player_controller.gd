class_name PlayerController
extends CharacterBody3D
## First/Third person player controller with camera toggle.
## Attach this script to the root CharacterBody3D node of the player scene.

# ── Movement Parameters ──────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 10.0
@export var friction: float = 12.0
@export var jump_impulse: float = 5.0
@export var gravity_multiplier: float = 1.0

# ── Mouse Look ───────────────────────────────────────────────────────────────
@export_group("Mouse Look")
@export var mouse_sensitivity: float = 0.002
@export var pitch_min: float = -89.0
@export var pitch_max: float = 89.0

# ── Node References ──────────────────────────────────────────────────────────
@onready var head_pivot: Node3D = $HeadPivot
@onready var camera_fps: Camera3D = $HeadPivot/CameraFPS
@onready var spring_arm: SpringArm3D = $HeadPivot/SpringArm3D
@onready var camera_tps: Camera3D = $HeadPivot/SpringArm3D/CameraTPS
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var interaction_ray: RayCast3D = $HeadPivot/InteractionRay

# ── State ────────────────────────────────────────────────────────────────────
var is_first_person: bool = true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _targeting: TargetingSystem = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera_mode()
	# Cache sibling TargetingSystem for detached-cursor routing
	for child: Node in get_children():
		if child is TargetingSystem:
			_targeting = child as TargetingSystem
			break


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look — route to crosshair when detached, else rotate camera
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _targeting != null and _targeting.detached_cursor:
			_targeting.move_crosshair(motion.relative)
		else:
			_handle_mouse_look(motion)
	
	# Camera toggle (V key)
	if event.is_action_pressed(&"toggle_camera"):
		is_first_person = not is_first_person
		_apply_camera_mode()
	
	# Escape to free mouse
	if event.is_action_pressed(&"ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	move_and_slide()


# ── Movement ─────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta


func _handle_jump() -> void:
	var jump_enabled: bool = get_meta(&"jump_enabled", true) as bool
	if not jump_enabled:
		return
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_impulse


func _handle_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		&"move_left", &"move_right",
		&"move_forward", &"move_backward"
	)
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	
	var is_sprinting: bool = Input.is_action_pressed(&"sprint")
	var target_speed: float = sprint_speed if is_sprinting else walk_speed
	# Apply posture speed modifier if present
	var speed_mult: float = get_meta(&"speed_multiplier", 1.0) as float
	target_speed *= speed_mult
	
	if direction.length() > 0.0:
		velocity.x = lerpf(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = lerpf(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = lerpf(velocity.x, 0.0, friction * delta)
		velocity.z = lerpf(velocity.z, 0.0, friction * delta)


# ── Mouse Look ───────────────────────────────────────────────────────────────

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	# Yaw: rotate the whole body
	rotate_y(-event.relative.x * mouse_sensitivity)
	# Pitch: rotate the head pivot only
	head_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
	head_pivot.rotation.x = clampf(
		head_pivot.rotation.x,
		deg_to_rad(pitch_min),
		deg_to_rad(pitch_max)
	)


# ── Camera Toggle ────────────────────────────────────────────────────────────

func _apply_camera_mode() -> void:
	if is_first_person:
		camera_fps.current = true
		camera_tps.current = false
		# Hide the body in first person to prevent clipping
		body_mesh.set_layer_mask_value(2, false)
		# FPS camera ignores layer 2 (PlayerBody), but it doesn't matter since mesh is hidden
		camera_fps.set_cull_mask_value(2, false)
		camera_tps.set_cull_mask_value(2, true)
	else:
		camera_fps.current = false
		camera_tps.current = true
		# Show the body in third person
		body_mesh.set_layer_mask_value(2, true)


# ── Public API ───────────────────────────────────────────────────────────────

## Returns the currently active camera.
func get_active_camera() -> Camera3D:
	return camera_fps if is_first_person else camera_tps


## Returns the current movement speed (0 to sprint_speed).
func get_current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
