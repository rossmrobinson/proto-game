class_name NPCPlaceholder
extends Node3D
## Placeholder NPC that spawns a full humanoid ragdoll.
## Brain subsystems: Memory, Attention, Voice, central Brain coordinator.

@export var npc_name: String = "TestNPC"
@export var body_height: float = 1.75
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)
## Model name inside the .blend file ("Ada", "Vero", "Player1") — leave empty for placeholder mesh.
@export var model_name: String = ""

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

	nerve_system = NerveSystem.new()
	nerve_system.name = "NerveSystem"
	add_child(nerve_system)

	body_language = BodyLanguageSystem.new()
	body_language.name = "BodyLanguageSystem"
	add_child(body_language)

	behavior = NPCBehavior.new()
	behavior.name = "NPCBehavior"
	add_child(behavior)

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

	# Brain last — it finds siblings via deferred _wire_subsystems()
	brain = NPCBrain.new()
	brain.name = "NPCBrain"
	add_child(brain)

	# Now that all subsystems exist, run the ragdoll-built handler
	_on_ragdoll_built()


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
		_load_model()


## Called when any body part is grabbed — springs auto-weaken via grabbed_spring_ratio.
func _on_part_grabbed(_p_part_name: String, _by: Node3D) -> void:
	pass  # Active ragdoll handles this — grabbed parts get weaker springs automatically


## Called when a body part is released — springs auto-restore.
func _on_part_released(_p_part_name: String, _by: Node3D) -> void:
	pass  # Active ragdoll handles this — part springs back to bone pose on its own


## Load the skinned mesh from the .blend import and bind its skeleton to the ragdoll.
func _load_model() -> void:
	# Godot imports each object in a .blend as a child of the root scene.
	# The imported scene path follows: res://assets/models/<file>.blend
	var blend_path: String = "res://assets/models/room1-models.blend"
	if not ResourceLoader.exists(blend_path):
		push_warning("[NPC] Model file not found: %s — keeping placeholder meshes" % blend_path)
		return

	var scene_res: PackedScene = load(blend_path) as PackedScene
	if scene_res == null:
		push_warning("[NPC] Failed to load model scene: %s" % blend_path)
		return

	var scene_root: Node3D = scene_res.instantiate() as Node3D
	if scene_root == null:
		push_warning("[NPC] Model scene instantiation failed")
		return

	# Debug: list all top-level children in the imported scene
	var child_names: PackedStringArray = []
	for child: Node in scene_root.get_children():
		child_names.append(child.name)
	print("[NPC] %s: .blend scene children: %s" % [npc_name, ", ".join(child_names)])

	# Find the named armature/mesh matching our model_name
	var armature: Node = _find_armature(scene_root, model_name)
	if armature == null:
		push_warning("[NPC] Armature '%s' not found in %s — children: %s" % [
			model_name, blend_path, ", ".join(child_names)])
		scene_root.queue_free()
		return

	print("[NPC] %s: found armature node '%s' (type=%s)" % [npc_name, armature.name, armature.get_class()])

	# Reparent just the armature node into this NPC
	# Unset owner recursively to avoid "inconsistent owner" warning
	_clear_owner_recursive(armature)
	armature.get_parent().remove_child(armature)
	scene_root.queue_free()
	add_child(armature)
	# Zero only X and Z — the Y offset is the Blender ground-to-origin height
	# that keeps the model standing on the floor instead of sinking through it.
	if armature is Node3D:
		var arm3d: Node3D = armature as Node3D
		arm3d.position = Vector3(0.0, arm3d.position.y, 0.0)
		arm3d.rotation = Vector3.ZERO

	# Find the Skeleton3D within the armature subtree
	var skel: Skeleton3D = _find_skeleton(armature)
	if skel == null:
		push_warning("[NPC] No Skeleton3D found under armature '%s'" % model_name)
		return

	# Create and wire up the skeleton binding
	skeleton_binding = SkeletonBinding.new()
	skeleton_binding.name = "SkeletonBinding"
	add_child(skeleton_binding)
	skeleton_binding.bind(skel, ragdoll)

	# Connect grab/release signals so the mesh switches to ragdoll physics when touched
	for part_key: String in ragdoll.parts:
		var part: BodyPart = ragdoll.parts[part_key] as BodyPart
		part.part_grabbed.connect(_on_part_grabbed)
		part.part_released.connect(_on_part_released)

	print("[NPC] %s model loaded — %d bones bound" % [
		model_name, skeleton_binding._bone_to_part.size()])


## Recursively search for a node whose name contains the model name (armature root).
func _find_armature(root: Node, target_name: String) -> Node:
	var target_lower: String = target_name.to_lower()
	for child: Node in root.get_children():
		if child.name.to_lower().contains(target_lower):
			return child
	# Deeper search
	for child: Node in root.get_children():
		var found: Node = _find_armature(child, target_name)
		if found != null:
			return found
	return null


## Find the first Skeleton3D in a subtree.
func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Recursively clear the owner on a node and all its descendants.
## Prevents "inconsistent owner" warnings when reparenting imported sub-trees.
func _clear_owner_recursive(node: Node) -> void:
	node.set_owner(null)
	for child: Node in node.get_children():
		_clear_owner_recursive(child)
