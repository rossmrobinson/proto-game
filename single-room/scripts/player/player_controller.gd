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

## Optional standalone player model scene (e.g., "res://assets/models/room1-models.blend").
## Leave empty to use the placeholder capsule.
@export_group("Model")
@export var player_model_path: String = ""
## Optional model name inside the scene (used for multi-model .blend files).
@export var player_model_name: String = ""
@export var show_body_in_fps: bool = true

# ── Node References ──────────────────────────────────────────────────────────
@onready var head_pivot: Node3D = $HeadPivot
@onready var camera_fps: Camera3D = $HeadPivot/CameraFPS
@onready var spring_arm: SpringArm3D = $HeadPivot/SpringArm3D
@onready var camera_tps: Camera3D = $HeadPivot/SpringArm3D/CameraTPS
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var interaction_ray: RayCast3D = $HeadPivot/InteractionRay

# ── Signals ──────────────────────────────────────────────────────────────────
## Emitted after the player model loads and a Skeleton3D is found.
signal player_model_loaded(skeleton: Skeleton3D)

# ── State ────────────────────────────────────────────────────────────────────
var is_first_person: bool = true
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _targeting: TargetingSystem = null
var _ragdoll_bridge: PlayerRagdollBridge = null
## The loaded player mesh root (if any).
var _player_model: Node3D = null
var _free_hands_active: bool = false
var _free_hands_hold: bool = false
var _free_hands_toggle: bool = false
var _free_hands_last_tap: float = 0.0
@export var free_hands_double_tap_window: float = 0.3

func _ready() -> void:
	print("========== PLAYER READY — BUILD 2026-02-08-C ==========")
	_ensure_action(&"free_hands", KEY_CAPSLOCK)
	# Force collision settings regardless of .tscn cache
	collision_mask = 1
	collision_layer = 2
	# Force FPS camera cull_mask: all layers EXCEPT layer 2 (player body)
	_update_fps_cull_mask()
	print("[Player] collision_layer=%d  collision_mask=%d  fps_cull=%d" % [
		collision_layer, collision_mask, camera_fps.cull_mask])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera_mode()
	# Cache sibling systems
	for child: Node in get_children():
		if child is TargetingSystem:
			_targeting = child as TargetingSystem
		if child is PlayerRagdollBridge:
			_ragdoll_bridge = child as PlayerRagdollBridge
	# Load standalone player model if configured
	if player_model_path != "":
		_load_player_model()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_free_hands_input(event):
		return
	# Mouse look — route to crosshair when detached, else rotate camera
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _targeting != null and _targeting.is_detached_cursor_active():
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


func _process(_delta: float) -> void:
	_update_free_hands()


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


func _update_free_hands() -> void:
	var active: bool = _free_hands_hold
	if _free_hands_toggle:
		active = not _free_hands_hold
	if active == _free_hands_active:
		return
	_free_hands_active = active
	if _targeting != null:
		_targeting.set_free_hands(_free_hands_active)
	if _free_hands_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_free_hands_active() -> bool:
	return _free_hands_active


func _handle_free_hands_input(event: InputEvent) -> bool:
	if event is not InputEventKey:
		return false
	var key: InputEventKey = event as InputEventKey
	if key.echo:
		return false
	if key.physical_keycode != KEY_CAPSLOCK:
		return false
	var now: float = Time.get_ticks_msec() / 1000.0
	if key.pressed:
		if now - _free_hands_last_tap <= free_hands_double_tap_window:
			_free_hands_toggle = not _free_hands_toggle
			_free_hands_last_tap = 0.0
		else:
			_free_hands_last_tap = now
		_free_hands_hold = true
	else:
		_free_hands_hold = false
	return true


func _ensure_action(action_name: StringName, keycode: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)


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
		_update_fps_cull_mask()
		if show_body_in_fps:
			if _player_model != null:
				_player_model.visible = true
				body_mesh.visible = false
			else:
				body_mesh.visible = true
		else:
			if _player_model != null:
				_player_model.visible = false
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

	var scene_root: Node3D = scene_res.instantiate() as Node3D
	if scene_root == null:
		push_warning("[Player] Model instantiation failed")
		return

	var model: Node3D = scene_root
	if player_model_name != "":
		var picked: Node3D = _extract_named_model(scene_root, player_model_name)
		if picked == null:
			push_warning("[Player] Model '%s' not found in %s" % [
				player_model_name, player_model_path])
			scene_root.queue_free()
			return
		model = picked

	model.name = "PlayerModel"
	_clear_owner_recursive(model)

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
	_apply_idle_pose_to_model(model)

	# Hide placeholder capsule — model replaces it
	body_mesh.visible = false

	# Exclude player model from the SpringArm so it doesn't push the TPS camera
	_exclude_bodies_from_spring_arm(model)

	_apply_camera_mode()

	# Emit skeleton for ragdoll bridge binding
	var skel: Skeleton3D = _find_skeleton(model)
	if skel != null:
		player_model_loaded.emit(skel)
		print("[Player] Model loaded + skeleton emitted: %s" % player_model_path)
	else:
		print("[Player] Model loaded (no skeleton): %s" % player_model_path)


func _update_fps_cull_mask() -> void:
	if camera_fps == null:
		return
	var mask: int = 0xFFFFF
	if not show_body_in_fps:
		mask &= ~(1 << 1)
	camera_fps.cull_mask = mask


func _apply_idle_pose_to_model(model: Node3D) -> void:
	var skeleton: Skeleton3D = _find_skeleton(model)
	if skeleton == null:
		return
	var left_chain: PackedStringArray = [
		"upperarm_l", "lowerarm_l", "hand_l",
		"thumb_01_l", "thumb_02_l", "thumb_03_l",
		"index_01_l", "index_02_l", "index_03_l",
		"middle_01_l", "middle_02_l", "middle_03_l",
		"ring_01_l", "ring_02_l", "ring_03_l",
		"pinky_01_l", "pinky_02_l", "pinky_03_l",
	]
	var right_chain: PackedStringArray = [
		"upperarm_r", "lowerarm_r", "hand_r",
		"thumb_01_r", "thumb_02_r", "thumb_03_r",
		"index_01_r", "index_02_r", "index_03_r",
		"middle_01_r", "middle_02_r", "middle_03_r",
		"ring_01_r", "ring_02_r", "ring_03_r",
		"pinky_01_r", "pinky_02_r", "pinky_03_r",
	]
	_rotate_arm_chain_to_down(skeleton, left_chain)
	_rotate_arm_chain_to_down(skeleton, right_chain)


func _rotate_arm_chain_to_down(skeleton: Skeleton3D, chain: PackedStringArray) -> void:
	if chain.is_empty():
		return
	var shoulder_idx: int = skeleton.find_bone(chain[0])
	if shoulder_idx < 0:
		return
	var hand_idx: int = skeleton.find_bone(chain[min(2, chain.size() - 1)])
	if hand_idx < 0:
		hand_idx = skeleton.find_bone(chain[chain.size() - 1])
	if hand_idx < 0:
		return
	var shoulder_pose: Transform3D = skeleton.get_bone_global_pose(shoulder_idx)
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(hand_idx)
	var arm_vec: Vector3 = (hand_pose.origin - shoulder_pose.origin).normalized()
	if arm_vec.length() < 0.0001:
		return
	var target: Vector3 = Vector3.DOWN
	var axis: Vector3 = arm_vec.cross(target)
	var angle: float = arm_vec.angle_to(target)
	if axis.length() < 0.0001 or angle < 0.0001:
		return
	axis = axis.normalized()
	var rot: Basis = Basis(axis, angle)
	var pivot: Vector3 = shoulder_pose.origin
	for bone_name: String in chain:
		var bone_idx: int = skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		var pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
		var offset: Vector3 = pose.origin - pivot
		var new_origin: Vector3 = pivot + rot * offset
		var new_basis: Basis = rot * pose.basis
		skeleton.set_bone_global_pose_override(bone_idx, Transform3D(new_basis, new_origin), 1.0, true)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _extract_named_model(scene_root: Node3D, target_name: String) -> Node3D:
	var target_lower: String = target_name.to_lower()
	var found: Node3D = null
	for child: Node in scene_root.get_children():
		if child is Node3D and child.name.to_lower().contains(target_lower):
			found = child as Node3D
			break
	if found == null:
		return null
	if found == scene_root:
		return found
	var parent: Node = found.get_parent()
	if parent != null:
		parent.remove_child(found)
	scene_root.queue_free()
	return found


func _clear_owner_recursive(node: Node) -> void:
	if node == null:
		return
	if node.owner != null:
		node.owner = null
	for child: Node in node.get_children():
		_clear_owner_recursive(child)


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
