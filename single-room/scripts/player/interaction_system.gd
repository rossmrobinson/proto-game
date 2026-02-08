class_name InteractionSystem
extends Node
## Manages player interaction with world objects.
## Attach to the player scene. Reads from the InteractionRay node.

signal interaction_target_changed(target: Node3D)
signal interacted_with(target: Node3D)

@export var interaction_distance: float = 2.5

@onready var player: PlayerController = get_parent() as PlayerController

var current_target: Node3D = null


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	var ray: RayCast3D = player.interaction_ray
	if ray == null:
		return
	
	ray.target_position = Vector3(0.0, 0.0, -interaction_distance)
	
	var new_target: Node3D = null
	if ray.is_colliding():
		var collider: Object = ray.get_collider()
		if collider is Node3D and collider.is_in_group(&"interactable"):
			new_target = collider as Node3D
	
	if new_target != current_target:
		current_target = new_target
		interaction_target_changed.emit(current_target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and current_target != null:
		interacted_with.emit(current_target)
		# If the target has an interact method, call it
		if current_target.has_method(&"interact"):
			current_target.call(&"interact")
