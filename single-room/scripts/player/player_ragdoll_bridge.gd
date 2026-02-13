class_name PlayerRagdollBridge
extends Node
## Bridges PlayerController (CharacterBody3D) with a HumanoidRagdollBuilder,
## giving the player a full physics-driven body that NPCs can push, pull, grab.
##
## The CharacterBody3D still owns movement input; the ragdoll pelvis follows it
## via stiff spring forces.  When an NPC grabs a player body part the binding
## springs weaken automatically (SkeletonBinding grabbed_motor_ratio) and the
## pull feeds back as velocity on the CharacterBody3D.
##
## Attach as child of PlayerController.

signal ragdoll_ready(ragdoll: HumanoidRagdollBuilder)
signal binding_ready(binding: SkeletonBinding)

const FORCE_REFERENCE_TPS: float = 120.0

# ── Body Config ──────────────────────────────────────────────────────────────

@export_group("Body")
@export var body_type: HumanoidRagdollBuilder.BodyType = HumanoidRagdollBuilder.BodyType.MALE
@export var body_height: float = 1.78
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)

# ── Pelvis Tracking ─────────────────────────────────────────────────────────

@export_group("Pelvis Tracking")
## Spring force keeping the ragdoll pelvis centred on the CharacterBody3D.
## Higher = stiffer follow.  Multiplied by pelvis mass internally.
@export var pelvis_track_stiffness: float = 600.0
## Damping on the pelvis tracking spring (mass-proportional).
@export var pelvis_track_damping: float = 60.0
## Pelvis height as a fraction of body_height (navel ≈ 0.52).
@export var pelvis_height_fraction: float = 0.52

# ── NPC Pull Feedback ────────────────────────────────────────────────────────

@export_group("NPC Feedback")
## How much grab-pull on ragdoll parts translates to CharacterBody3D velocity.
@export_range(0.0, 1.0) var feedback_strength: float = 0.3
## Maximum velocity contribution from NPC pull feedback (m/s).
@export var feedback_velocity_cap: float = 3.0

# ── Rotation Follow ─────────────────────────────────────────────────────────

@export_group("Rotation Follow")
## Torque keeping the ragdoll pelvis yaw aligned with the player's facing.
@export var yaw_torque_stiffness: float = 200.0
@export var yaw_torque_damping: float = 30.0

# ── References ───────────────────────────────────────────────────────────────

var ragdoll: HumanoidRagdollBuilder = null
var skeleton_binding: SkeletonBinding = null
var nerve_system: NerveSystem = null
var arousal_system: ArousalSystem = null
var passage_response: PassageResponse = null
var _player: PlayerController = null
var _posture: PlayerPosture = null
var _pelvis: BodyPart = null
var _ragdoll_built: bool = false
var _binding_bound: bool = false
var _force_tick_scale: float = 1.0


func _ready() -> void:
	var physics_tps: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_force_tick_scale = FORCE_REFERENCE_TPS / maxf(physics_tps, 1.0)

	_player = get_parent() as PlayerController
	if _player == null:
		push_error("[PlayerRagdollBridge] Must be child of PlayerController")
		return

	# Find posture sibling for dynamic pelvis height
	for sibling: Node in _player.get_children():
		if sibling is PlayerPosture:
			_posture = sibling as PlayerPosture
			break

	# Create the ragdoll — connect BEFORE add_child so we catch ragdoll_built
	ragdoll = HumanoidRagdollBuilder.new()
	ragdoll.name = "HumanoidRagdoll"
	ragdoll.body_type = body_type
	ragdoll.body_height = body_height
	ragdoll.body_color = body_color
	ragdoll.show_meshes = false  # player model provides visuals
	ragdoll.ragdoll_built.connect(_on_ragdoll_built)
	_player.add_child(ragdoll)

	# Listen for model load (skeleton becomes available)
	if _player.has_signal(&"player_model_loaded"):
		_player.player_model_loaded.connect(_on_player_model_loaded)
	else:
		push_warning("[PlayerRagdollBridge] PlayerController missing player_model_loaded signal")


func _on_ragdoll_built() -> void:
	_ragdoll_built = true
	_pelvis = ragdoll.parts.get("pelvis", null) as BodyPart

	# ── Spawn NerveSystem ───────────────────────────────────────────────
	nerve_system = NerveSystem.new()
	nerve_system.name = "PlayerNerveSystem"
	_player.add_child(nerve_system)
	var sens_map: Dictionary = NerveSensitivity.get_default_map()
	nerve_system.set_sensitivity_map(sens_map)

	# Exclude every ragdoll part from the CharacterBody3D so they don't collide
	for part_name: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		_player.add_collision_exception_with(part)
		part.ragdoll_owner = _player
		# Wire nerve sensitivity
		if sens_map.has(part_name):
			part.nerve_sensitivity = sens_map[part_name] as NerveSensitivity
		part._nerve_system = nerve_system

	print("[PlayerRagdollBridge] Ragdoll built — %d parts, collision exclusions set" %
		ragdoll.parts.size())
	ragdoll_ready.emit(ragdoll)


func _on_player_model_loaded(skeleton: Skeleton3D) -> void:
	if skeleton == null or ragdoll == null:
		push_warning("[PlayerRagdollBridge] Cannot bind — skeleton or ragdoll null")
		return

	skeleton_binding = SkeletonBinding.new()
	skeleton_binding.name = "PlayerSkeletonBinding"
	# Player stands via CharacterBody3D — no stand-assist needed
	skeleton_binding.stand_assist_enabled = false
	skeleton_binding.hide_placeholder_meshes = true
	_player.add_child(skeleton_binding)
	skeleton_binding.bind(skeleton, ragdoll)
	_binding_bound = true

	# ── Spawn ArousalSystem + PassageResponse ───────────────────────────
	arousal_system = ArousalSystem.new()
	arousal_system.name = "PlayerArousalSystem"
	_player.add_child(arousal_system)
	arousal_system.setup(self)

	passage_response = PassageResponse.new()
	passage_response.name = "PlayerPassageResponse"
	_player.add_child(passage_response)
	passage_response.setup(self, arousal_system)

	print("[PlayerRagdollBridge] Skeleton bound — %d bones" %
		skeleton_binding._bone_to_part.size())
	binding_ready.emit(skeleton_binding)


func _physics_process(delta: float) -> void:
	if not _ragdoll_built or _pelvis == null:
		return
	if not is_instance_valid(_pelvis):
		return

	_track_pelvis_to_player(delta)
	_track_pelvis_yaw(delta)
	_apply_npc_feedback(delta)


# ═════════════════════════════════════════════════════════════════════════════
#  PELVIS TRACKING
# ═════════════════════════════════════════════════════════════════════════════

func _track_pelvis_to_player(_delta: float) -> void:
	## Drive the ragdoll pelvis to follow the CharacterBody3D position,
	## accounting for posture-dependent height.
	var height_frac: float = pelvis_height_fraction
	if _posture != null:
		height_frac *= _get_posture_height_ratio()

	var target_pos: Vector3 = _player.global_position + Vector3(
		0.0, body_height * height_frac, 0.0)
	var error: Vector3 = target_pos - _pelvis.global_position
	var vel_error: Vector3 = _player.velocity - _pelvis.linear_velocity

	var m: float = _pelvis.mass
	var force: Vector3 = (error * pelvis_track_stiffness + vel_error * pelvis_track_damping) * m
	_pelvis.apply_central_force(force * _force_tick_scale)


func _track_pelvis_yaw(_delta: float) -> void:
	## Torque the ragdoll pelvis to match the player's yaw (Y rotation).
	var target_yaw: float = _player.global_rotation.y
	var current_yaw: float = _pelvis.global_rotation.y
	var yaw_error: float = angle_difference(current_yaw, target_yaw)
	var ang_vel_y: float = _pelvis.angular_velocity.y

	var torque_y: float = (yaw_error * yaw_torque_stiffness - ang_vel_y * yaw_torque_damping)
	torque_y *= _pelvis.mass
	_pelvis.apply_torque(Vector3(0.0, torque_y * _force_tick_scale, 0.0))


# ═════════════════════════════════════════════════════════════════════════════
#  NPC PULL FEEDBACK
# ═════════════════════════════════════════════════════════════════════════════

func _apply_npc_feedback(delta: float) -> void:
	## When NPCs grab player body parts, accumulate the pull direction and
	## nudge the CharacterBody3D velocity so the player feels the tug.
	if feedback_strength <= 0.0:
		return

	var total_pull: Vector3 = Vector3.ZERO
	var pull_count: int = 0

	for part_name: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		if part.grabbed_by != null and is_instance_valid(part.grabbed_by):
			var pull: Vector3 = part.linear_velocity - _player.velocity
			total_pull += pull
			pull_count += 1

	if pull_count > 0:
		total_pull /= float(pull_count)
		total_pull = total_pull.limit_length(feedback_velocity_cap)
		# Only affect horizontal movement — vertical is gravity-controlled
		var feedback: Vector3 = total_pull * feedback_strength * delta
		_player.velocity.x += feedback.x
		_player.velocity.z += feedback.z


# ═════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════════════════════

func _get_posture_height_ratio() -> float:
	if _posture == null:
		return 1.0
	match _posture.current_posture:
		PlayerPosture.Posture.CROUCHING:
			return _posture.crouch_height / _posture.standing_height
		PlayerPosture.Posture.KNEELING:
			return _posture.kneel_height / _posture.standing_height
		PlayerPosture.Posture.PRONE:
			return _posture.prone_height / _posture.standing_height
		_:
			return 1.0


## Get a specific body part by name (convenience for other systems).
func get_part(part_name: String) -> BodyPart:
	if ragdoll == null:
		return null
	return ragdoll.parts.get(part_name, null) as BodyPart


## Check if any player body part is currently grabbed by an NPC.
func is_any_part_grabbed() -> bool:
	if ragdoll == null:
		return false
	for part_name: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		if part.grabbed_by != null and is_instance_valid(part.grabbed_by):
			return true
	return false


## Get the count of currently grabbed player body parts.
func get_grabbed_count() -> int:
	if ragdoll == null:
		return 0
	var count: int = 0
	for part_name: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name] as BodyPart
		if part.grabbed_by != null and is_instance_valid(part.grabbed_by):
			count += 1
	return count
