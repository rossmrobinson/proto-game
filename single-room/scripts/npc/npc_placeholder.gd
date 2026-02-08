class_name NPCPlaceholder
extends Node3D
## Placeholder NPC that spawns a full humanoid ragdoll.
## Brain subsystems: Memory, Attention, Voice, central Brain coordinator.

@export var npc_name: String = "TestNPC"
@export var body_height: float = 1.75
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)

@onready var ragdoll: HumanoidRagdollBuilder = $HumanoidRagdoll
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
