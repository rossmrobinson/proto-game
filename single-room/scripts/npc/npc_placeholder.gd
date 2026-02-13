class_name NPCPlaceholder
extends Node3D
## Placeholder NPC that spawns a full humanoid ragdoll.
## Brain subsystems: Memory, Attention, Voice, central Brain coordinator.

@export var npc_name: String = "TestNPC"
@export var body_height: float = 1.75
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)
@export_group("Model")
## Model name inside the .blend file ("Ada", "Vero", "Sara", "Irene", "Player1") — leave empty for placeholder mesh.
@export var model_name: String = ""
@export var auto_scale_model: bool = true
@export var model_scale: float = 1.0
## Per-NPC stand assist override.
@export var stand_assist_enabled: bool = true

@export_group("Follow Command")
@export var is_awake: bool = true
@export var follow_on_pull_enabled: bool = true
@export var follow_pull_distance: float = 0.35
@export var follow_pull_min_time: float = 0.1

@export_group("Activity")
@export_enum("none", "ada_patrol", "vero_sit_stand", "sara_pole_dance", "irene_jog")
var activity_profile: String = "none"
@export var activity_room_half_extent: float = 9.76
@export var activity_edge_margin: float = 1.0
@export var activity_movement_enabled: bool = true

@export_group("Personality")
@export_enum("Neutral", "Prude", "Friendly", "Handsy", "Horny", "Aggressive", "Aggressive Helper")
var personality_preset: int = 0

@export_group("LLM")
@export var llm_enabled: bool = false
@export var llm_persona_id: String = "default"
@export var llm_config: LLMConfig = null

const NPC_SCENE_PATH: String = "res://scenes/npc_placeholder.tscn"
const _PresetLib: GDScript = preload("res://scripts/npc/npc_personality_preset.gd")

@onready var ragdoll: HumanoidRagdollBuilder = $HumanoidRagdoll
var skeleton_binding: SkeletonBinding = null
var nerve_system: NerveSystem = null
var character_profile: CharacterProfile = null
var body_language: BodyLanguageSystem = null
var behavior: NPCBehavior = null
var brain: NPCBrain = null
var memory: NPCMemory = null
var attention: NPCAttention = null
var voice_player: NPCVoicePlayer = null
var animator: RagdollAnimator = null
var activity_controller: NPCActivityController = null
var llm_controller: LLMNPCController = null
var arousal_system: ArousalSystem = null
var passage_response: PassageResponse = null
var shape_key_driver: ShapeKeyDriver = null
var interaction_intent: NPCInteractionIntent = null
var interaction_targeting: NPCInteractionTargeting = null
var mount_system: MountPositionSystem = null
var fluid_system: FluidSystem = null
var constriction_system: Node = null  # ConstrictionSystem
var grip_pressure_system: Node = null  # GripPressureSystem
var oral_action_system: Node = null  # OralActionSystem
var tongue_follow: Node = null  # TongueSurfaceFollow
var autonomous_drive: Node = null  # NPCAutonomousDrive

var _sleeping: bool = false
var _sleep_body_language_influence: float = 0.0
var _sleep_stand_assist_enabled: bool = true
var _sleep_cached: bool = false


func _ready() -> void:
	# Register in the "npc" group so NPCCommandSystem can find us.
	add_to_group(&"npc")

	# Note: child _ready() fires BEFORE parent _ready(), so the ragdoll is
	# already built by the time we reach here.  Connect for future rebuilds,
	# then call the handler after all subsystems are spawned.
	ragdoll.ragdoll_built.connect(_on_ragdoll_built)
	# Spawn NPC subsystems — order matters (brain wires to siblings via deferred)
	character_profile = CharacterProfile.new()
	character_profile.name = "CharacterProfile"
	character_profile.character_name = npc_name
	add_child(character_profile)

	animator = _ensure_animator()

	nerve_system = NerveSystem.new()
	nerve_system.name = "NerveSystem"
	add_child(nerve_system)

	arousal_system = ArousalSystem.new()
	arousal_system.name = "ArousalSystem"
	add_child(arousal_system)

	passage_response = PassageResponse.new()
	passage_response.name = "PassageResponse"
	add_child(passage_response)

	shape_key_driver = ShapeKeyDriver.new()
	shape_key_driver.name = "ShapeKeyDriver"
	add_child(shape_key_driver)

	body_language = BodyLanguageSystem.new()
	body_language.name = "BodyLanguageSystem"
	add_child(body_language)

	behavior = NPCBehavior.new()
	behavior.name = "NPCBehavior"
	add_child(behavior)

	activity_controller = _ensure_activity_controller()

	# Brain subsystems
	memory = NPCMemory.new()
	memory.name = "NPCMemory"
	add_child(memory)

	attention = NPCAttention.new()
	attention.name = "NPCAttention"
	add_child(attention)

	voice_player = NPCVoicePlayer.new()
	voice_player.name = "NPCVoicePlayer"
	add_child(voice_player)

	# Interaction subsystems (intent → targeting → mount)
	interaction_intent = NPCInteractionIntent.new()
	interaction_intent.name = "NPCInteractionIntent"
	add_child(interaction_intent)

	interaction_targeting = NPCInteractionTargeting.new()
	interaction_targeting.name = "NPCInteractionTargeting"
	add_child(interaction_targeting)

	mount_system = MountPositionSystem.new()
	mount_system.name = "MountPositionSystem"
	add_child(mount_system)

	fluid_system = FluidSystem.new()
	fluid_system.name = "FluidSystem"
	add_child(fluid_system)

	var _ConstrictionSystem: GDScript = preload(
		"res://scripts/systems/constriction_system.gd")
	constriction_system = _ConstrictionSystem.new()
	constriction_system.name = "ConstrictionSystem"
	add_child(constriction_system)

	var _GripPressureSystem: GDScript = preload(
		"res://scripts/systems/grip_pressure_system.gd")
	grip_pressure_system = _GripPressureSystem.new()
	grip_pressure_system.name = "GripPressureSystem"
	add_child(grip_pressure_system)

	var _OralActionSystem: GDScript = preload(
		"res://scripts/systems/oral_action_system.gd")
	oral_action_system = _OralActionSystem.new()
	oral_action_system.name = "OralActionSystem"
	add_child(oral_action_system)

	var _TongueSurfaceFollow: GDScript = preload(
		"res://scripts/systems/tongue_surface_follow.gd")
	tongue_follow = _TongueSurfaceFollow.new()
	tongue_follow.name = "TongueSurfaceFollow"
	add_child(tongue_follow)

	# Autonomous drive (personality-driven behavior)
	var _NPCAutonomousDrive: GDScript = preload(
		"res://scripts/npc/npc_autonomous_drive.gd")
	autonomous_drive = _NPCAutonomousDrive.new()
	autonomous_drive.name = "NPCAutonomousDrive"
	add_child(autonomous_drive)

	# Brain last — it finds siblings via deferred _wire_subsystems()
	brain = NPCBrain.new()
	brain.name = "NPCBrain"
	add_child(brain)

	# Optional LLM controller
	if llm_enabled:
		llm_controller = LLMNPCController.new()
		llm_controller.name = "LLMNPCController"
		llm_controller.persona_id = llm_persona_id
		if llm_config != null:
			llm_controller.llm_config = llm_config
		add_child(llm_controller)

	# Apply personality preset to all subsystems
	_apply_personality_preset()

	# Now that all subsystems exist, run the ragdoll-built handler
	_on_ragdoll_built()


## Map the @export_enum int to NPCPersonalityPreset.Type and apply overrides
## to all subsystems.
func _apply_personality_preset() -> void:
	# The @export_enum order matches _PresetLib.Type exactly:
	# 0=Neutral, 1=Prude, 2=Friendly, 3=Handsy, 4=Horny, 5=Aggressive, 6=AggressiveHelper
	var preset_type: int = clampi(personality_preset, 0, 6)
	var data: Dictionary = _PresetLib.get_preset(preset_type)

	# ── CharacterProfile ────────────────────────────────────────────────
	if character_profile != null and data.has("profile"):
		character_profile.apply_overrides(data["profile"] as Dictionary)

	# ── NPCBrain ────────────────────────────────────────────────────────
	if brain != null and data.has("brain"):
		var brain_data: Dictionary = data["brain"] as Dictionary
		for key: String in brain_data:
			if key in brain:
				brain.set(key, brain_data[key])

	# ── NPCBehavior ─────────────────────────────────────────────────────
	if behavior != null and data.has("behavior"):
		var beh_data: Dictionary = data["behavior"] as Dictionary
		for key: String in beh_data:
			if key in behavior:
				behavior.set(key, beh_data[key])

	# ── NPCInteractionTargeting ─────────────────────────────────────────
	if interaction_targeting != null and data.has("targeting"):
		var tgt_data: Dictionary = data["targeting"] as Dictionary
		for key: String in tgt_data:
			if key in interaction_targeting:
				interaction_targeting.set(key, tgt_data[key])

	# ── NPCAutonomousDrive ──────────────────────────────────────────────
	if autonomous_drive != null and data.has("drive"):
		if autonomous_drive.has_method(&"apply_drive"):
			autonomous_drive.call(&"apply_drive", data["drive"] as Dictionary)

	print("[NPC] %s personality: %s" % [
		npc_name, _PresetLib.get_label(preset_type)])


func _on_ragdoll_built() -> void:
	print("[NPC] %s ragdoll built: %d body parts" % [npc_name, ragdoll.parts.size()])
	# Wire up nerve sensitivity map
	var sens_map: Dictionary = NerveSensitivity.get_default_map()
	nerve_system.set_sensitivity_map(sens_map)
	# Set ragdoll_owner on each part so they can find the NerveSystem
	for part_name_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_name_key] as BodyPart
		part.ragdoll_owner = self
		if sens_map.has(part_name_key):
			part.nerve_sensitivity = sens_map[part_name_key] as NerveSensitivity
		# Let the part find the nerve system now that ragdoll_owner is set
		for child: Node in get_children():
			if child.has_method(&"receive_touch"):
				part._nerve_system = child
				break

	# If a model name is set, load the skinned mesh and bind skeleton
	if model_name != "":
		var skel: Skeleton3D = NPCModelLoader.load_model(
			self, npc_name, model_name, ragdoll, auto_scale_model, model_scale)
		if skel != null:
			_bind_skeleton(skel)

	# Wire arousal / passage / shape-key systems (need ragdoll + nerve to be ready)
	if arousal_system != null:
		arousal_system.setup(self)
	if passage_response != null and arousal_system != null:
		passage_response.setup(self, arousal_system)
	if shape_key_driver != null and arousal_system != null:
		shape_key_driver.setup(self, arousal_system, passage_response)

	# Wire fluid system (needs ragdoll, arousal, nerve, profile)
	if fluid_system != null:
		fluid_system.setup(self)

	# Wire constriction system (needs ragdoll, nerve, profile, body_language)
	if constriction_system != null:
		constriction_system.setup(self)

	# Wire grip pressure system (needs ragdoll, nerve, profile, arousal)
	if grip_pressure_system != null:
		grip_pressure_system.setup(self)

	# Wire oral action system (needs ragdoll, nerve, profile)
	if oral_action_system != null:
		oral_action_system.setup(self)

	# Wire tongue surface follow (needs ragdoll, nerve)
	if tongue_follow != null:
		tongue_follow.setup(self)

	if activity_controller != null and activity_controller.has_method(&"on_ragdoll_built"):
		activity_controller.call(&"on_ragdoll_built")
	_apply_sleep_state_to_binding()


func sleep() -> void:
	set_sleeping(true)


func wake() -> void:
	set_sleeping(false)


func set_sleeping(sleeping: bool) -> void:
	if _sleeping == sleeping:
		return
	_sleeping = sleeping
	is_awake = not sleeping
	if sleeping:
		if animator != null:
			animator.clear_pose()
		if body_language != null:
			_sleep_body_language_influence = body_language.influence
			body_language.influence = 0.0
		if activity_controller != null:
			activity_controller.set_active(false)
	else:
		if body_language != null:
			body_language.influence = _sleep_body_language_influence
		if activity_controller != null:
			activity_controller.set_active(true)
	_apply_sleep_state_to_binding()


func _apply_sleep_state_to_binding() -> void:
	if skeleton_binding == null:
		return
	if _sleeping:
		if not _sleep_cached:
			_sleep_cached = true
			_sleep_stand_assist_enabled = skeleton_binding.stand_assist_enabled
		skeleton_binding.stand_assist_enabled = false
		skeleton_binding.set_forced_sleep(true)
	else:
		if _sleep_cached:
			skeleton_binding.stand_assist_enabled = _sleep_stand_assist_enabled
			_sleep_cached = false
		skeleton_binding.set_forced_sleep(false)


func _ensure_animator() -> RagdollAnimator:
	var existing: Node = get_node_or_null("RagdollAnimator")
	if existing is RagdollAnimator:
		var animator_node: RagdollAnimator = existing as RagdollAnimator
		animator_node.ragdoll = ragdoll
		return animator_node
	var new_animator: RagdollAnimator = RagdollAnimator.new()
	new_animator.name = "RagdollAnimator"
	new_animator.ragdoll = ragdoll
	add_child(new_animator)
	return new_animator


func _ensure_activity_controller() -> NPCActivityController:
	var existing: Node = get_node_or_null("NPCActivityController")
	if existing is NPCActivityController:
		var controller: NPCActivityController = existing as NPCActivityController
		controller.activity_profile = activity_profile
		controller.room_half_extent = activity_room_half_extent
		controller.edge_margin = activity_edge_margin
		controller.movement_enabled = activity_movement_enabled
		return controller
	var new_controller: NPCActivityController = NPCActivityController.new()
	new_controller.name = "NPCActivityController"
	new_controller.activity_profile = activity_profile
	new_controller.room_half_extent = activity_room_half_extent
	new_controller.edge_margin = activity_edge_margin
	new_controller.movement_enabled = activity_movement_enabled
	add_child(new_controller)
	return new_controller


## Called when any body part is grabbed — springs auto-weaken via grabbed_spring_ratio.
func _on_part_grabbed(_p_part_name: String, _by: Node3D) -> void:
	pass  # Active ragdoll handles this — grabbed parts get weaker springs automatically


## Called when a body part is released — springs auto-restore.
func _on_part_released(_p_part_name: String, _by: Node3D) -> void:
	pass  # Active ragdoll handles this — part springs back to bone pose on its own


## Bind a discovered Skeleton3D to the ragdoll via SkeletonBinding.
func _bind_skeleton(skel: Skeleton3D) -> void:
	skeleton_binding = SkeletonBinding.new()
	skeleton_binding.name = "SkeletonBinding"
	add_child(skeleton_binding)
	skeleton_binding.bind(skel, ragdoll)
	skeleton_binding.stand_assist_enabled = stand_assist_enabled

	# Connect grab/release signals so the mesh switches to ragdoll physics
	for part_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_key] as BodyPart
		part.part_grabbed.connect(_on_part_grabbed)
		part.part_released.connect(_on_part_released)

	print("[NPC] %s model loaded — %d bones bound" % [
		model_name, skeleton_binding._bone_to_part.size()])


func get_follow_anchor_position() -> Vector3:
	if ragdoll != null and ragdoll.parts.has("pelvis"):
		var pelvis: BodyPart = ragdoll.parts["pelvis"] as BodyPart
		if pelvis != null:
			return pelvis.global_position
	return global_position


func is_follow_active() -> bool:
	return is_awake and follow_on_pull_enabled


func get_follow_pull_distance() -> float:
	return follow_pull_distance


func get_follow_pull_min_time() -> float:
	return follow_pull_min_time


func respawn() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var scene_res: PackedScene = load(NPC_SCENE_PATH) as PackedScene
	if scene_res == null:
		push_warning("[NPC] Respawn failed: scene not found")
		return
	var new_node: Node = scene_res.instantiate()
	if new_node == null:
		return
	if new_node is NPCPlaceholder:
		var new_npc: NPCPlaceholder = new_node as NPCPlaceholder
		new_npc.name = name
		new_npc.global_transform = global_transform
		new_npc.npc_name = npc_name
		new_npc.body_height = body_height
		new_npc.body_color = body_color
		new_npc.model_name = model_name
		new_npc.auto_scale_model = auto_scale_model
		new_npc.model_scale = model_scale
		new_npc.stand_assist_enabled = stand_assist_enabled
		new_npc.is_awake = is_awake
		new_npc.follow_on_pull_enabled = follow_on_pull_enabled
		new_npc.follow_pull_distance = follow_pull_distance
		new_npc.follow_pull_min_time = follow_pull_min_time
		new_npc.personality_preset = personality_preset
		var ragdoll_node: Node = new_npc.get_node_or_null("HumanoidRagdoll")
		if ragdoll_node != null:
			ragdoll_node.set("body_height", body_height)
			ragdoll_node.set("body_color", body_color)
	parent.add_child(new_node)
	queue_free()

