class_name BodyPart
extends RigidBody3D
## A single segment of a ragdoll humanoid. Each body part is independently
## grabbable, targetable, and responds to physics.
##
## This is similar to Grabbable but specialized for ragdoll segments that
## are connected to other parts via joints.

signal part_grabbed(part_name: String, by: Node3D)
signal part_released(part_name: String, by: Node3D)
signal part_hit(part_name: String, force: float, hit_point: Vector3)
signal part_impact(part_name: String, impact_force: float, other_body: Node)

## Which body part this represents (e.g., "head", "left_upper_arm", "right_hand")
@export var part_name: String = ""
## Readable label for UI
@export var display_name: String = ""
## How much this part resists grab movement (head feels heavier than a finger)
@export_range(0.0, 1.0) var grab_stiffness: float = 0.5
## Max stretch before the grab breaks
@export var grab_break_distance: float = 1.5
## Whether this part can be grabbed
@export var is_grabbable: bool = true

@export_group("Impact Detection")
## Minimum relative velocity (m/s) to register as an impact.
@export var impact_velocity_threshold: float = 1.5
## Cooldown between impact events to prevent spam (seconds).
@export var impact_cooldown: float = 0.15
## Multiplier converting velocity (m/s) to nerve intensity.
@export var impact_intensity_scale: float = 0.4

## Nerve sensitivity data (assigned by ragdoll builder or manually).
var nerve_sensitivity: NerveSensitivity = null
## Reference to the NPC's NerveSystem (set by builder or _ready scan).
var _nerve_system: Node = null

# ── Grab State ───────────────────────────────────────────────────────────────
var grabbed_by: Node3D = null
var _grab_joint: Generic6DOFJoint3D = null

# ── Impact State ─────────────────────────────────────────────────────────────
## Velocity from previous physics frame for delta-v computation.
var _prev_velocity: Vector3 = Vector3.ZERO
## Time since last impact event (seconds). Used for cooldown.
var _impact_timer: float = 0.0

# ── Cached References ────────────────────────────────────────────────────────
var _sfx_engine: Node = null

# ── Internal ─────────────────────────────────────────────────────────────────
## Reference to the parent ragdoll root (set by HumanoidRagdollBuilder)
var ragdoll_owner: Node3D = null
## Adjacent parts connected by joints (set by builder)
var connected_parts: Array[BodyPart] = []


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"body_part")
	# Physics layer 3 (NPC) + layer 4 (Interactable)
	set_collision_layer_value(3, true)
	set_collision_layer_value(4, true)
	# Try to find the NerveSystem in the ragdoll owner
	if ragdoll_owner != null:
		for child: Node in ragdoll_owner.get_children():
			if child.has_method(&"receive_touch"):
				_nerve_system = child
				break
	# Collide with environment, player, other NPCs, interactables, soft tissue
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	set_collision_mask_value(4, true)
	set_collision_mask_value(5, true)  # NPC_SoftTissue
	# Start with some damping for stable ragdoll
	linear_damp = 1.0
	angular_damp = 2.0
	# Enable contact monitoring for velocity-based impact detection
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	# Cache SFX engine reference once
	_sfx_engine = _find_sfx_engine()


func get_part_name() -> String:
	return part_name


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return part_name.replace("_", " ").capitalize()


## Grab this body part. Creates a joint to the grab anchor.
func grab(grabber: Node3D, grab_body: StaticBody3D, hit_point: Vector3) -> bool:
	if not is_grabbable or grabbed_by != null:
		return false
	if not grab_body.is_inside_tree():
		push_warning("[BodyPart] grab() called but anchor not in tree yet")
		return false

	grabbed_by = grabber

	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.name = "BodyPartGrabJoint_%s" % part_name
	joint.global_position = hit_point

	joint.node_a = grab_body.get_path()
	joint.node_b = get_path()

	# Soft linear constraint — allows slight flex for natural feel
	var linear_slack: float = 0.05 * (1.0 - grab_stiffness)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear_slack)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear_slack)

	# Allow some rotation so the part can pivot naturally while grabbed
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-45))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(45))

	get_tree().current_scene.add_child(joint)
	_grab_joint = joint

	# Make the part lighter while grabbed for responsive feel
	gravity_scale = 0.3
	linear_damp = 6.0
	angular_damp = 8.0

	part_grabbed.emit(part_name, grabber)
	# Notify nerve system
	if _nerve_system != null:
		_nerve_system.call(&"receive_touch", part_name,
			NerveSystem.TouchType.GRAB, 1.0)
	return true


## Release this body part from a grab.
func release() -> void:
	if _grab_joint != null and is_instance_valid(_grab_joint):
		_grab_joint.queue_free()
		_grab_joint = null

	gravity_scale = 1.0
	linear_damp = 1.0
	angular_damp = 2.0

	var prev: Node3D = grabbed_by
	grabbed_by = null
	part_released.emit(part_name, prev)
	# Notify nerve system
	if _nerve_system != null:
		_nerve_system.call(&"receive_touch", part_name,
			NerveSystem.TouchType.RELEASE, 0.5)


## Apply an impact force to this body part.
func apply_hit(force_dir: Vector3, magnitude: float, point: Vector3) -> void:
	apply_impulse(force_dir * magnitude, point - global_position)
	part_hit.emit(part_name, magnitude, point)
	# Notify nerve system — push type with intensity scaled by force
	if _nerve_system != null:
		var intensity: float = clampf(magnitude / 10.0, 0.1, 3.0)
		_nerve_system.call(&"receive_touch", part_name,
			NerveSystem.TouchType.PUSH, intensity)


func _physics_process(delta: float) -> void:
	# Tick impact cooldown
	if _impact_timer > 0.0:
		_impact_timer -= delta

	# Auto-release if grab joint stretches too far
	if grabbed_by != null and _grab_joint != null and is_instance_valid(_grab_joint):
		if global_position.distance_to(_grab_joint.global_position) > grab_break_distance:
			release()

	# Store velocity for next-frame delta-v computation
	_prev_velocity = linear_velocity


# ── Velocity-Based Impact Detection ──────────────────────────────────────────

func _on_body_entered(other: Node) -> void:
	if _impact_timer > 0.0:
		return  # Still in cooldown

	# Compute relative velocity
	var other_vel: Vector3 = Vector3.ZERO
	if other is RigidBody3D:
		other_vel = (other as RigidBody3D).linear_velocity
	elif other is CharacterBody3D:
		other_vel = (other as CharacterBody3D).velocity

	# Delta-v: how fast the two objects approached each other
	var relative_vel: Vector3 = _prev_velocity - other_vel
	var impact_speed: float = relative_vel.length()

	if impact_speed < impact_velocity_threshold:
		return  # Too gentle to register

	_impact_timer = impact_cooldown

	# Scale intensity by velocity
	var intensity: float = clampf(impact_speed * impact_intensity_scale, 0.1, 5.0)

	# Emit signal with real force value
	part_impact.emit(part_name, intensity, other)
	# Also fire the generic part_hit for any listeners
	part_hit.emit(part_name, intensity, global_position)

	# Notify nerve system — IMPACT type with velocity-scaled intensity
	if _nerve_system != null:
		_nerve_system.call(&"receive_touch", part_name,
			NerveSystem.TouchType.IMPACT, intensity)

	# Trigger impact SFX proportional to force
	_play_impact_sfx(impact_speed, intensity)


func _play_impact_sfx(speed: float, intensity: float) -> void:
	if _sfx_engine == null:
		return

	# Volume scales with intensity: soft taps are quiet, hard hits are loud
	var volume_db: float = lerpf(-24.0, 0.0, clampf(intensity / 3.0, 0.0, 1.0))
	# Pitch varies slightly for natural feel, heavier hits sound lower
	var pitch: float = lerpf(1.2, 0.7, clampf(speed / 15.0, 0.0, 1.0))

	# Try to play a registered impact sound
	var stream: AudioStream = _sfx_engine.call(
		&"get_sound", SFXEngine.Category.IMPACT, "body_impact") as AudioStream
	if stream != null:
		_sfx_engine.call(&"play_at", stream, global_position,
			SFXEngine.BUS_SFX, volume_db, pitch)
		# Heavy hits also rumble the LFE
		if intensity > 1.5:
			var lfe_vol: float = volume_db - 6.0
			_sfx_engine.call(&"play_at", stream, global_position,
				SFXEngine.BUS_LFE, lfe_vol, pitch * 0.6)


func _find_sfx_engine() -> Node:
	# Check autoload (autoloads live under /root/<name>)
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var autoload: Node = tree.root.get_node_or_null(^"SFXEngine")
	if autoload != null:
		return autoload
	# Fallback: find in scene tree by class
	var root: Node = tree.current_scene
	if root == null:
		return null
	if root is SFXEngine:
		return root
	for child: Node in root.get_children():
		if child is SFXEngine:
			return child
	return null
