class_name HandInteractionSystem
extends Node3D
## Dual-hand mouse interaction system.
## Left click = left hand, Right click = right hand.
## Supersedes GrabSystem with richer gesture vocabulary.
##
## Controls:
##   L/R Single Click : Grab target (if empty) or use held item on target
##   L/R Double Click : Drop held item
##   L/R Double + Hold: Throw held item
##   Wheel Horizontal : Rotate player pelvis/hips left-right
##   Wheel Vertical   : Crotch/hip thrust positioning (or adjust hold distance)
##   Middle Click x2  : Press genitals to target surface
##   Middle Hold 1s   : Toggle autopilot mode

signal hand_grabbed(hand: Hand, target: Node3D)
signal hand_released(hand: Hand, target: Node3D)
signal hand_pushed(hand: Hand, target: Node3D, force: float)
signal hand_push_released(hand: Hand, target: Node3D, force: float)
signal pelvis_rotated(angle_delta_deg: float)
signal pelvis_thrust(amount: float)
signal genitals_pressed()
signal autopilot_toggled(enabled: bool)

enum Hand { LEFT, RIGHT }

const FOLLOW_PARTS: PackedStringArray = [
	"left_hand", "right_hand",
	"left_forearm", "right_forearm",
	"left_upper_arm", "right_upper_arm",
]
const DEFAULT_FOLLOW_PULL_DISTANCE: float = 0.35
const DEFAULT_FOLLOW_PULL_MIN_TIME: float = 0.1

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

@export_group("Strike")
@export var strike_force: float = 6.0

@export_group("Throw")
@export var throw_force: float = 12.0
@export var throw_hold_time: float = 0.25

@export_group("Pelvis")
## Degrees of pelvis rotation per horizontal scroll tick.
@export var pelvis_rotate_per_tick: float = 5.0
## Meters of thrust per vertical scroll tick.
@export var thrust_per_tick: float = 0.08

# ── Per-hand state (inner class to avoid left_/right_ duplication) ───────────
class _HandState:
	var held: Node3D = null
	var hold_distance: float = 1.5
	var pending: bool = false
	var pending_time: float = 0.0
	var double_click_hold: bool = false
	var double_click_time: float = 0.0
	var throw_armed: bool = false
	var grab_local_offset: Vector3 = Vector3.ZERO
	var anchor: StaticBody3D = null
	var follow_target: BodyPart = null
	var follow_npc: NPCPlaceholder = null
	var follow_start_distance: float = 0.0
	var follow_start_time: float = 0.0
	var follow_triggered: bool = false

var _hands: Dictionary = {}  # Hand enum → _HandState

# Middle mouse
var _middle_press_time: float = -1.0
var _middle_pending: bool = false
var _middle_pending_time: float = 0.0
var _middle_held: bool = false
var _autopilot_active: bool = false
var _autopilot_fired: bool = false

var _focused_hand: Hand = Hand.LEFT
var _free_hands_active: bool = false

@onready var _player: PlayerController = get_parent() as PlayerController
var _targeting: TargetingSystem = null
var _command_system: NPCCommandSystem = null
var _ragdoll_bridge: PlayerRagdollBridge = null
var _mount_system: MountPositionSystem = null
var _claim_system: InteractionClaimSystem = null


func _ready() -> void:
	_ensure_action(&"switch_hand", KEY_ALT)
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
		if child is PlayerRagdollBridge:
			_ragdoll_bridge = child as PlayerRagdollBridge

	# Find global claim system singleton
	var claim_nodes: Array[Node] = get_tree().get_nodes_in_group(
		&"interaction_claim_system")
	if not claim_nodes.is_empty():
		_claim_system = claim_nodes[0] as InteractionClaimSystem

	# Create a MountPositionSystem for the player if bridge is present
	if _ragdoll_bridge != null:
		_mount_system = MountPositionSystem.new()
		_mount_system.name = "PlayerMountSystem"
		_player.add_child(_mount_system)
		genitals_pressed.connect(_on_genitals_pressed_mount)


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
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_on_hand_released(Hand.LEFT)
			MOUSE_BUTTON_RIGHT:
				_on_hand_released(Hand.RIGHT)
			MOUSE_BUTTON_MIDDLE:
				_on_middle_released()


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _player != null and _player.has_method(&"is_free_hands_active"):
		_free_hands_active = bool(_player.call(&"is_free_hands_active"))
	if Input.is_action_just_pressed(&"switch_hand"):
		_focused_hand = Hand.RIGHT if _focused_hand == Hand.LEFT else Hand.LEFT

	# Expire pending single clicks — check both hands
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		if hs.pending and (now - hs.pending_time) > double_click_window:
			_execute_single_click(hand)
			hs.pending = false

		if hs.double_click_hold:
			if (now - hs.double_click_time) >= throw_hold_time:
				hs.throw_armed = true

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
	var both_hands: bool = _free_hands_active and Input.is_action_pressed(&"switch_hand")
	for hand: Hand in _hands:
		var hs: _HandState = _hands[hand] as _HandState
		var active_hand: bool = true
		if _free_hands_active:
			active_hand = both_hands or hand == _focused_hand
		if active_hand:
			_update_anchor(hs.anchor, hs.hold_distance, hs.held, hs.grab_local_offset, delta)
		# Clear invalid held references
		if hs.held != null and not is_instance_valid(hs.held):
			hs.held = null
		_update_follow_pull(hand, hs)


# ── Click Handling ───────────────────────────────────────────────────────────

func _on_hand_click(hand: Hand) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var hs: _HandState = _hands[hand] as _HandState

	if hs.pending and (now - hs.pending_time) <= double_click_window:
		hs.pending = false
		hs.double_click_hold = true
		hs.double_click_time = now
		hs.throw_armed = false
	else:
		hs.pending = true
		hs.pending_time = now


func _on_hand_released(hand: Hand) -> void:
	var hs: _HandState = _hands[hand] as _HandState
	if not hs.double_click_hold:
		return
	if hs.throw_armed:
		_throw_held(hand)
	else:
		_drop_held(hand)
	hs.double_click_hold = false
	hs.throw_armed = false


func _execute_single_click(hand: Hand) -> void:
	var held: Node3D = _get_held(hand)
	if held != null:
		_use_held_on_target(hand, held)
	else:
		_try_grab(hand)


# ── Grab / Release / Push ────────────────────────────────────────────────────

func _try_grab(hand: Hand) -> void:
	var target: Node3D = _get_target()
	if target == null:
		return
	if target is BodyPart:
		var part: BodyPart = target as BodyPart
		if not part.is_grabbable or part.grabbed_by != null:
			return
	elif target is Grabbable:
		var grab: Grabbable = target as Grabbable
		if not grab.is_grabbable or grab.grabbed_by != null:
			return
	else:
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

	var success: bool = false
	if target is BodyPart:
		success = (target as BodyPart).grab(actor, hs.anchor, hit_point)
	elif target is Grabbable:
		success = (target as Grabbable).grab(actor, hs.anchor, hit_point)
	if success:
		_set_held(hand, target)
		hs.grab_local_offset = target.to_local(hit_point)
		# Register claim with InteractionClaimSystem
		if _claim_system != null and target is BodyPart:
			_claim_system.request_claim(
				target as BodyPart, actor,
				InteractionClaimSystem.ClaimPriority.PLAYER)
		hand_grabbed.emit(hand, target)
		if target is BodyPart:
			_init_follow_candidate(hand, target as BodyPart, actor)


func _release_hand(hand: Hand) -> void:
	var held: Node3D = _get_held(hand)
	if held == null:
		return
	var hs: _HandState = _hands[hand] as _HandState
	if is_instance_valid(held):
		if held is BodyPart:
			# Release claim before releasing physics
			if _claim_system != null:
				_claim_system.release_claim(
					held as BodyPart, _get_actor())
			(held as BodyPart).release()
		elif held is Grabbable:
			(held as Grabbable).release()
	_set_held(hand, null)
	hs.grab_local_offset = Vector3.ZERO
	hand_released.emit(hand, held)
	_clear_follow_candidate(hand)


func _use_held_on_target(hand: Hand, held: Node3D) -> void:
	var target: Node3D = _get_target()
	if target == null:
		return
	if _is_fastener(held):
		_try_attach_fastener(hand, held, target)
	else:
		_strike_target(held, target)


func _drop_held(hand: Hand) -> void:
	_release_hand(hand)


func _throw_held(hand: Hand) -> void:
	var held: Node3D = _get_held(hand)
	if held == null:
		return
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return
	var dir: Vector3 = -camera.global_basis.z
	_release_hand(hand)
	if held is RigidBody3D:
		(held as RigidBody3D).apply_impulse(dir * throw_force, Vector3.ZERO)


func _is_fastener(node: Node3D) -> bool:
	if node == null:
		return false
	if node is CuffFastener:
		return true
	return node.is_in_group(&"fastener")


func _try_attach_fastener(hand: Hand, held: Node3D, target: Node3D) -> void:
	if held is not CuffFastener:
		return
	var cuff: CuffFastener = held as CuffFastener
	var hit_point: Vector3 = target.global_position
	if _targeting != null and _targeting.current_target == target:
		hit_point = _targeting.target_hit_point
	if cuff.attach_to(target, hit_point):
		_release_hand(hand)


func _strike_target(held: Node3D, target: Node3D) -> void:
	if target == null:
		return
	var origin: Vector3 = held.global_position if held != null else _player.global_position
	var dir: Vector3 = (target.global_position - origin).normalized()
	if dir.is_zero_approx():
		var camera: Camera3D = _player.get_active_camera()
		if camera != null:
			dir = -camera.global_basis.z
		else:
			dir = Vector3.FORWARD
	if target is BodyPart:
		(target as BodyPart).apply_hit(dir, strike_force, target.global_position)
	elif target is RigidBody3D:
		(target as RigidBody3D).apply_impulse(dir * strike_force, Vector3.ZERO)
	if held is RigidBody3D:
		(held as RigidBody3D).apply_impulse(-dir * strike_force * 0.2, Vector3.ZERO)


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


func _on_genitals_pressed_mount() -> void:
	## Double-middle-click → begin mounting the commanded NPC using the
	## player's ragdoll genitals.  Requires both a ragdoll bridge and a
	## currently commanded NPC.
	if _mount_system == null or _ragdoll_bridge == null:
		return
	if _ragdoll_bridge.ragdoll == null:
		return
	# Already mounting — cancel and re-target
	if _mount_system.is_mounting():
		_mount_system.cancel_mount()

	# Target: commanded NPC or the NPC currently under the cursor
	var target_npc: NPCPlaceholder = null
	if _command_system != null and _command_system.commanded_npc != null:
		target_npc = _command_system.commanded_npc
	elif _targeting != null and _targeting.current_target != null:
		var owner_node: Node3D = _targeting.current_target
		# Walk up to find the NPCPlaceholder
		while owner_node != null:
			if owner_node is NPCPlaceholder:
				target_npc = owner_node as NPCPlaceholder
				break
			owner_node = owner_node.get_parent() as Node3D

	if target_npc == null:
		return

	_mount_system.begin_mount(_ragdoll_bridge.ragdoll, target_npc)


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


func _update_anchor(anchor: StaticBody3D, hold_dist: float, held: Node3D,
		grab_local_offset: Vector3, delta: float) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	if not anchor.is_inside_tree():
		return
	var camera: Camera3D = _player.get_active_camera()
	if camera == null:
		return

	var aim_pos: Vector3
	if _free_hands_active and held != null and is_instance_valid(held):
		var along_pos: Vector3 = _get_along_object_position(held, grab_local_offset)
		anchor.global_position = anchor.global_position.lerp(along_pos, grab_move_speed * delta)
		return

	# In detached-cursor mode, guide held objects toward the crosshair position
	if _targeting != null and _targeting.is_detached_cursor_active():
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


func _get_along_object_position(held: Node3D, grab_local_offset: Vector3) -> Vector3:
	if _targeting != null and _targeting.current_overlay_target == held:
		return _targeting.overlay_hit_point
	return held.to_global(grab_local_offset)


func _init_follow_candidate(hand: Hand, target: BodyPart, actor: Node3D) -> void:
	if actor != _player:
		return
	if target == null or not FOLLOW_PARTS.has(target.part_name):
		return
	var npc: NPCPlaceholder = target.ragdoll_owner as NPCPlaceholder
	if npc == null:
		return
	if npc.has_method(&"is_follow_active"):
		if not bool(npc.call(&"is_follow_active")):
			return
	var hs: _HandState = _hands[hand] as _HandState
	hs.follow_target = target
	hs.follow_npc = npc
	hs.follow_start_distance = target.global_position.distance_to(_get_follow_anchor(npc))
	hs.follow_start_time = Time.get_ticks_msec() / 1000.0
	hs.follow_triggered = false


func _clear_follow_candidate(hand: Hand) -> void:
	var hs: _HandState = _hands[hand] as _HandState
	hs.follow_target = null
	hs.follow_npc = null
	hs.follow_start_distance = 0.0
	hs.follow_start_time = 0.0
	hs.follow_triggered = false


func _update_follow_pull(hand: Hand, hs: _HandState) -> void:
	if hs.follow_target == null or hs.follow_npc == null:
		return
	if hs.follow_triggered:
		return
	if hs.held != hs.follow_target:
		_clear_follow_candidate(hand)
		return
	if not is_instance_valid(hs.follow_target) or not is_instance_valid(hs.follow_npc):
		_clear_follow_candidate(hand)
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var min_time: float = DEFAULT_FOLLOW_PULL_MIN_TIME
	if hs.follow_npc.has_method(&"get_follow_pull_min_time"):
		min_time = float(hs.follow_npc.call(&"get_follow_pull_min_time"))
	if (now - hs.follow_start_time) < min_time:
		return
	var anchor: Vector3 = _get_follow_anchor(hs.follow_npc)
	var current_dist: float = hs.follow_target.global_position.distance_to(anchor)
	var threshold: float = DEFAULT_FOLLOW_PULL_DISTANCE
	if hs.follow_npc.has_method(&"get_follow_pull_distance"):
		threshold = float(hs.follow_npc.call(&"get_follow_pull_distance"))
	if (current_dist - hs.follow_start_distance) < threshold:
		return
	if _command_system != null and _command_system.commanded_npc != hs.follow_npc:
		_command_system.set_commanded(hs.follow_npc)
	hs.follow_triggered = true


func _get_follow_anchor(npc: NPCPlaceholder) -> Vector3:
	if npc == null:
		return Vector3.ZERO
	if npc.has_method(&"get_follow_anchor_position"):
		return npc.call(&"get_follow_anchor_position") as Vector3
	return npc.global_position


func _ensure_action(action_name: StringName, keycode: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_target() -> Node3D:
	if _targeting != null:
		var target: Node3D = _targeting.get_current_interactable()
		if target != null:
			return target
	return _raycast_for_interactable()


func _raycast_for_interactable() -> Node3D:
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
	if collider is Node3D:
		var node: Node3D = collider as Node3D
		if node.is_in_group(&"interactable"):
			return node
	return null


func _get_held(hand: Hand) -> Node3D:
	var hs: _HandState = _hands[hand] as _HandState
	return hs.held


func _set_held(hand: Hand, part: Node3D) -> void:
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
func get_held(hand: Hand) -> Node3D:
	var hs: _HandState = _hands[hand] as _HandState
	if hs.held != null and is_instance_valid(hs.held):
		return hs.held
	return null


## Returns the active actor — the commanded NPC's root, or the player.
func _get_actor() -> Node3D:
	if _command_system != null and _command_system.is_commanding():
		return _command_system.commanded_npc as Node3D
	return _player as Node3D
