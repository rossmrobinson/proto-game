class_name GrabSystem
extends Node3D
## Player grab system: point at objects, click to grab, drag them around.
## Attach as a child of the Player node. Needs a reference to the head pivot.
##
## Controls:
##   Left Click  = Grab / Release
##   Right Click  = Push grabbed object away
##   Scroll Up   = Pull closer
##   Scroll Down  = Push farther
##   R            = Rotate grabbed object

signal grab_started(target: Node3D, body_part_name: String)
signal grab_ended(target: Node3D)

@export_group("Grab Settings")
@export var grab_distance: float = 3.0
@export var hold_distance: float = 1.5
@export var hold_distance_min: float = 0.5
@export var hold_distance_max: float = 4.0
@export var grab_move_speed: float = 15.0
@export var push_force: float = 8.0
@export var throw_force: float = 6.0

# ── Internal State ───────────────────────────────────────────────────────────
var _held_object: Node3D = null  # The Grabbable or BodyPart currently held
var _grab_anchor: StaticBody3D = null  # Kinematic body that the joint attaches to
var _current_hold_distance: float = 1.5
var _is_rotating: bool = false

@onready var _player: PlayerController = get_parent() as PlayerController


func _ready() -> void:
	# Create the invisible anchor body that follows the camera aim point.
	# Grabbed objects are jointed to this.
	_grab_anchor = StaticBody3D.new()
	_grab_anchor.name = "GrabAnchor"
	# The anchor doesn't collide with anything — it's purely a joint target
	_grab_anchor.collision_layer = 0
	_grab_anchor.collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.01
	col.shape = shape
	_grab_anchor.add_child(col)
	get_tree().current_scene.call_deferred("add_child", _grab_anchor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					if _held_object != null:
						_release()
					else:
						_try_grab()
				MOUSE_BUTTON_RIGHT:
					if _held_object != null:
						_throw_object()
				MOUSE_BUTTON_WHEEL_UP:
					if _held_object != null:
						_current_hold_distance = minf(_current_hold_distance + 0.2, hold_distance_max)
				MOUSE_BUTTON_WHEEL_DOWN:
					if _held_object != null:
						_current_hold_distance = maxf(_current_hold_distance - 0.2, hold_distance_min)


func _physics_process(delta: float) -> void:
	if _grab_anchor == null or not is_instance_valid(_grab_anchor):
		return

	# Move the anchor to where the player is aiming
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	var aim_origin: Vector3 = camera.global_position
	var aim_dir: Vector3 = -camera.global_basis.z
	var target_pos: Vector3 = aim_origin + aim_dir * _current_hold_distance
	_grab_anchor.global_position = _grab_anchor.global_position.lerp(target_pos, grab_move_speed * delta)

	# Check if the held object has been freed externally
	if _held_object != null and not is_instance_valid(_held_object):
		_held_object = null


# ── Grab Logic ───────────────────────────────────────────────────────────────

func _try_grab() -> void:
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	# Raycast from the center of the screen
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var end: Vector3 = origin + (-camera.global_basis.z) * grab_distance

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	# Interact with NPC (layer 3) and Interactable (layer 4)
	query.collision_mask = 4 | 8  # layers 3 and 4 (bitmask: layer 3 = 4, layer 4 = 8)
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_body: Object = result["collider"]
	var hit_point: Vector3 = result["position"]

	# Set hold distance to current distance to object
	_current_hold_distance = origin.distance_to(hit_point)

	# Move anchor to hit point before creating joint
	_grab_anchor.global_position = hit_point

	var body_part_name: String = ""

	if hit_body is RigidBody3D:
		# Check if it's a Grabbable
		if hit_body.has_method(&"grab"):
			var success: bool = hit_body.call(&"grab", _player, _grab_anchor, hit_point)
			if success:
				_held_object = hit_body as Node3D
				# Check if it's a body part for the signal
				if hit_body.has_method(&"get_part_name"):
					body_part_name = hit_body.call(&"get_part_name")
				grab_started.emit(_held_object, body_part_name)


func _release() -> void:
	if _held_object == null:
		return

	if is_instance_valid(_held_object) and _held_object.has_method(&"release"):
		_held_object.call(&"release")

	var prev: Node3D = _held_object
	_held_object = null
	grab_ended.emit(prev)


func _throw_object() -> void:
	if _held_object == null or not is_instance_valid(_held_object):
		return

	var camera: Camera3D = _player.get_active_camera()
	var throw_dir: Vector3 = -camera.global_basis.z

	if _held_object is RigidBody3D:
		var rb: RigidBody3D = _held_object as RigidBody3D
		# Release first, then apply impulse
		if _held_object.has_method(&"release"):
			_held_object.call(&"release")
		rb.apply_central_impulse(throw_dir * throw_force)

	var prev: Node3D = _held_object
	_held_object = null
	grab_ended.emit(prev)


## Returns true if currently holding something.
func is_grabbing() -> bool:
	return _held_object != null and is_instance_valid(_held_object)


## Returns the currently held object, or null.
func get_held_object() -> Node3D:
	return _held_object if is_grabbing() else null
