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
## The loaded player mesh armature (if any).
var _player_armature: Node3D = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera_mode()
	# Cache sibling TargetingSystem for detached-cursor routing
	for child: Node in get_children():
		if child is TargetingSystem:
			_targeting = child as TargetingSystem
			break
	# Load the Player1 model from the blend file
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
		# Hide everything in FPS — mesh on layer 2 is already excluded by cull_mask
		body_mesh.visible = false
	else:
		camera_fps.current = false
		camera_tps.current = true
		# TPS: show real mesh if loaded, else show placeholder
		if _player_armature != null:
			_player_armature.visible = true
			body_mesh.visible = false
		else:
			body_mesh.visible = true


# ── Player Model Loading ─────────────────────────────────────────────────────

## Load the Player1 skinned mesh from the shared .blend file.
func _load_player_model() -> void:
	var blend_path: String = "res://assets/models/room1-models.blend"
	if not ResourceLoader.exists(blend_path):
		push_warning("[Player] Model file not found: %s" % blend_path)
		return

	var scene_res: PackedScene = load(blend_path) as PackedScene
	if scene_res == null:
		push_warning("[Player] Failed to load model scene")
		return

	var scene_root: Node3D = scene_res.instantiate() as Node3D
	if scene_root == null:
		push_warning("[Player] Model instantiation failed")
		return

	# Find the Player1 armature
	var armature: Node = _find_child_by_name(scene_root, "Player1")
	if armature == null:
		push_warning("[Player] 'Player1' armature not found in .blend")
		scene_root.queue_free()
		return

	# Reparent into the player
	_clear_owner_recursive(armature)
	armature.get_parent().remove_child(armature)
	scene_root.queue_free()
	add_child(armature)

	# Position: keep the Blender Y offset (ground-to-origin height), zero X/Z
	if armature is Node3D:
		var arm3d: Node3D = armature as Node3D
		arm3d.position = Vector3(0.0, arm3d.position.y, 0.0)
		arm3d.rotation = Vector3.ZERO

	_player_armature = armature as Node3D

	# Put mesh on visual layer 2 — FPS camera (cull_mask bit 1 off) won't render it,
	# but TPS camera (default all-layers mask) will.
	for mesh_inst: MeshInstance3D in _find_meshes_recursive(armature):
		mesh_inst.layers = 2  # Layer 2 only

	# Stop any auto-playing Blender animations that fight the CharacterBody3D
	_stop_imported_animations(armature)

	# Hide the blue placeholder capsule
	body_mesh.visible = false

	print("[Player] Player1 model loaded")


## Find a direct child whose name contains the target (case-insensitive).
func _find_child_by_name(root: Node, target: String) -> Node:
	var target_lower: String = target.to_lower()
	for child: Node in root.get_children():
		if child.name.to_lower().contains(target_lower):
			return child
	# Deeper search
	for child: Node in root.get_children():
		var found: Node = _find_child_by_name(child, target)
		if found != null:
			return found
	return null


## Recursively collect all MeshInstance3D nodes.
func _find_meshes_recursive(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_find_meshes_recursive(child))
	return result


## Recursively clear owners to avoid reparent warnings.
func _clear_owner_recursive(node: Node) -> void:
	node.set_owner(null)
	for child: Node in node.get_children():
		_clear_owner_recursive(child)


## Stop any AnimationPlayers from the Blender import that auto-play.
func _stop_imported_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.stop()
		ap.autoplay = &""
	for child: Node in node.get_children():
		_stop_imported_animations(child)


# ── Public API ───────────────────────────────────────────────────────────────

## Returns the currently active camera.
func get_active_camera() -> Camera3D:
	return camera_fps if is_first_person else camera_tps


## Returns the current movement speed (0 to sprint_speed).
func get_current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
