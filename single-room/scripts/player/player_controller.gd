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

## Optional standalone player model (e.g., "res://assets/models/player1.glb").
## Leave empty to use the placeholder capsule.
@export_group("Model")
@export var player_model_path: String = ""

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
## The loaded player mesh root (if any).
var _player_model: Node3D = null

func _ready() -> void:
	print("========== PLAYER READY — BUILD 2026-02-08-C ==========")
	# Force collision settings regardless of .tscn cache
	collision_mask = 1
	collision_layer = 2
	# Force FPS camera cull_mask: all layers EXCEPT layer 2 (player body)
	camera_fps.cull_mask = 0xFFFFF & ~(1 << 1)  # 1048573
	print("[Player] collision_layer=%d  collision_mask=%d  fps_cull=%d" % [
		collision_layer, collision_mask, camera_fps.cull_mask])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera_mode()
	# Cache sibling TargetingSystem for detached-cursor routing
	for child: Node in get_children():
		if child is TargetingSystem:
			_targeting = child as TargetingSystem
			break
	# Load standalone player model if configured
	if player_model_path != "":
		_load_player_model()


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
		# Player model stays visible — CameraFPS cull_mask excludes layer 2.
		# Hide the blue placeholder capsule.
		body_mesh.visible = false
	else:
		camera_fps.current = false
		camera_tps.current = true
		if _player_model != null:
			_player_model.visible = true
			body_mesh.visible = false
		else:
			body_mesh.visible = true


# ── Player Model Loading ─────────────────────────────────────────────────────

## Load a standalone .glb model for the player body.
## The model must be exported with: origin at feet, facing -Z, no animations.
func _load_player_model() -> void:
	if not ResourceLoader.exists(player_model_path):
		push_warning("[Player] Model not found: %s" % player_model_path)
		return

	var scene_res: PackedScene = load(player_model_path) as PackedScene
	if scene_res == null:
		push_warning("[Player] Failed to load model: %s" % player_model_path)
		return

	var model: Node3D = scene_res.instantiate() as Node3D
	if model == null:
		push_warning("[Player] Model instantiation failed")
		return

	model.name = "PlayerModel"

	# Strip any physics bodies / collision shapes from the imported scene
	# (doing this BEFORE adding to tree prevents collisions on first frame)
	var stripped: int = _strip_physics_nodes(model)
	if stripped > 0:
		print("[Player] Stripped %d physics node(s) from model" % stripped)

	# Face -Z (same as player forward) — glTF exports face +Z by default
	model.rotation.y = PI
	add_child(model)
	_player_model = model

	# Put all visual instances on render layer 2 so CameraFPS culls them
	var mesh_count: int = _set_visual_layers(model, 2)
	print("[Player] Set %d visual node(s) to render layer 2" % mesh_count)

	# Stop any auto-playing animations
	_stop_imported_animations(model)

	# Hide placeholder capsule — model replaces it
	body_mesh.visible = false

	# Exclude player model from the SpringArm so it doesn't push the TPS camera
	_exclude_bodies_from_spring_arm(model)

	_apply_camera_mode()
	print("[Player] Model loaded: %s" % player_model_path)


## Recursively remove CollisionShape3D, StaticBody3D, RigidBody3D, etc.
## from an imported scene tree. Returns count of nodes removed.
func _strip_physics_nodes(node: Node) -> int:
	var removed: int = 0
	# Walk children in reverse so removal doesn't shift indices
	for i: int in range(node.get_child_count() - 1, -1, -1):
		var child: Node = node.get_child(i)
		if child is CollisionShape3D or child is CollisionObject3D:
			child.queue_free()
			removed += 1
		else:
			removed += _strip_physics_nodes(child)
	return removed


## Stop any AnimationPlayers from the Blender import that auto-play.
func _stop_imported_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.stop()
		ap.autoplay = &""
	for child: Node in node.get_children():
		_stop_imported_animations(child)


## Set all VisualInstance3D nodes (meshes, particles, etc.) to the given
## visual layer (1-based). Returns count of nodes modified.
func _set_visual_layers(node: Node, layer: int) -> int:
	var count: int = 0
	if node is VisualInstance3D:
		var vi: VisualInstance3D = node as VisualInstance3D
		vi.layers = 1 << (layer - 1)
		count += 1
	for child: Node in node.get_children():
		count += _set_visual_layers(child, layer)
	return count


## Exclude all physics bodies under `root` from SpringArm3D collision.
func _exclude_bodies_from_spring_arm(root: Node) -> void:
	if spring_arm == null:
		return
	_collect_and_exclude_bodies(root)


func _collect_and_exclude_bodies(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		spring_arm.add_excluded_object(co.get_rid())
	for child: Node in node.get_children():
		_collect_and_exclude_bodies(child)


# ── Public API ───────────────────────────────────────────────────────────────

## Returns the currently active camera.
func get_active_camera() -> Camera3D:
	return camera_fps if is_first_person else camera_tps


## Returns the current movement speed (0 to sprint_speed).
func get_current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
