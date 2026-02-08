class_name HUD
extends Control
## Minimal HUD showing crosshair and interaction prompts.

@onready var crosshair: TextureRect = $Crosshair
@onready var interaction_label: Label = $InteractionLabel


func _ready() -> void:
	interaction_label.visible = false


## Call this when the interaction target changes.
func set_interaction_prompt(target: Node3D) -> void:
	if target != null:
		interaction_label.text = "Press [E] to interact"
		interaction_label.visible = true
	else:
		interaction_label.visible = false
