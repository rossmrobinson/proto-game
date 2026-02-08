class_name NPCPlaceholder
extends Node3D
## Placeholder NPC that spawns a full humanoid ragdoll.
## Later this will be replaced with animated Blender models and LLM brain.

@export var npc_name: String = "TestNPC"
@export var body_height: float = 1.75
@export var body_color: Color = Color(0.85, 0.72, 0.6, 1.0)

@onready var ragdoll: HumanoidRagdollBuilder = $HumanoidRagdoll


func _ready() -> void:
	ragdoll.ragdoll_built.connect(_on_ragdoll_built)


func _on_ragdoll_built() -> void:
	print("[NPC] %s ragdoll built: %d body parts" % [npc_name, ragdoll.parts.size()])
